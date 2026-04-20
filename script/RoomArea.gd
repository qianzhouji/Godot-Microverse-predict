extends Area2D

@export var room_name: String = "未命名房间"
@export var room_desc: String = "这里是一个房间"

func _ready():
	add_to_group("room_area")

# ========== 情境参数（基于边际价值定理 MVT）==========
# 初始收益率 (S): 情境开始时的奖赏水平
# 取值: 0.0-1.0 (低: 0.0-0.4, 中: 0.4-0.7, 高: 0.7-1.0)
@export var initial_reward_rate: float = 0.5

# 收益衰减率 (a): 奖赏随时间消耗的速度
# 取值: 0.0-1.0 (慢: 0.0-0.3, 中: 0.3-0.6, 快: 0.6-1.0)
@export var reward_decay_rate: float = 0.5

# 努力水平 (effort): 参与该情境所需付出的努力
# 取值: 0.0-1.0 (低: 0.0-0.3, 中: 0.3-0.6, 高: 0.6-1.0)
@export var effort_level: float = 0.5

# 活动类型标签（用于AI决策参考）
@export var activity_types: Array[String] = []

# ============================================
# ⭐ 感知层与系统层分离说明 ⭐
# ============================================
# 以下函数已弃用或修改，以符合"Agent不可见客观参数"原则
#
# 设计原则：
# - Agent不能直接读取 initial_reward_rate, reward_decay_rate, effort_level
# - Agent只能通过 RewardSystem 接收系统发放的"奖赏"数值
# - Agent通过 PerceptionSystem 对奖赏进行贝叶斯推断
#
# 正确的信息获取方式：
# - 客观收益计算: RewardSystem.distribute_reward()
# - 主观感知参数: PerceptionSystem.get_perceived_params()
# - 情境基本信息: get_basic_description() (仅名称、描述、活动类型)

# 获取情境的基本描述（仅包含Agent可见信息）
# ⭐ 修改：不再包含客观参数S,a,E
func get_basic_description() -> String:
	"""
	获取房间的基本描述信息（Agent可见）
	
	注意：此函数只返回情境的名称、描述和活动类型
	不包含客观参数(S,a,E)，Agent需要通过体验采样间接感知
	"""
	var desc = "\n【当前情境】"
	desc += "\n- 名称：%s" % room_name
	desc += "\n- 描述：%s" % room_desc
	
	if activity_types.size() > 0:
		desc += "\n- 适合的活动类型：" + ", ".join(activity_types)
	
	desc += "\n\n（你需要通过亲身体验来感知这个情境的特征）"
	
	return desc

# ❌ 已弃用: get_situation_params_description()
# 原因: 此函数直接返回客观参数S,a,E给AI Prompt，违反"Agent不可见客观参数"原则
# 替代方案: 
#   - 使用 get_basic_description() 获取基本信息
#   - 使用 PerceptionSystem.get_belief_description() 获取感知描述
#   - 客观参数只能通过 RewardSystem 间接获取

# 保留旧函数但标记为弃用，返回警告信息
func get_situation_params_description() -> String:
	push_warning("[RoomArea] get_situation_params_description() 已弃用！" +
				 "Agent不应直接访问客观参数S,a,E。" +
				 "请使用 get_basic_description() 或 PerceptionSystem.get_belief_description()")
	
	# 返回基本信息而非完整参数
	return get_basic_description() + "\n\n[警告：尝试直接访问客观参数，已阻止]"

# ============================================
# 系统层内部接口（仅供系统层组件使用）
# ============================================
# 以下函数仅供 RewardSystem, RoomManager 等系统层组件调用
# Agent不应直接调用这些函数

# 获取客观情境参数（系统层内部使用）
# ⚠️ 警告：此函数仅供系统层组件调用，Agent不应直接访问
func _get_objective_params_internal() -> Dictionary:
	"""
	获取房间的客观参数（系统层内部使用）
	
	返回:
		{"S": 初始收益率, "a": 衰减率, "E": 努力成本}
	
	⚠️ 警告：此函数仅供RewardSystem等系统层组件调用
	Agent不应直接调用此函数，应通过RewardSystem接收奖赏
	"""
	return {
		"S": initial_reward_rate,
		"a": reward_decay_rate,
		"E": effort_level
	}

# 计算客观收益（系统层内部使用）
# G(t) = (S/a)[1 - exp(-at)]
# ⚠️ 警告：此函数仅供系统层组件调用
func _calculate_objective_gain_internal(time: float) -> float:
	"""
	计算指定时间的客观收益（系统层内部使用）
	
	参数:
		time: 停留时间
	
	返回:
		客观收益值（0-1）
	
	⚠️ 警告：此函数仅供系统层组件调用
	Agent不应直接调用此函数
	"""
	var a = reward_decay_rate
	if a < 0.001:
		a = 0.001
	
	var gain = (initial_reward_rate / a) * (1.0 - exp(-a * time))
	return clamp(gain, 0.0, 1.0)
