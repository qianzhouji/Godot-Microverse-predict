extends Area2D

@export var room_name: String = "未命名房间"
@export var room_desc: String = "这里是一个房间"

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

# 获取情境参数的格式化描述（用于AI prompt）
func get_situation_params_description() -> String:
	var desc = "\n【当前情境参数】"
	
	# 初始收益率描述
	var rate_desc = "中"
	if initial_reward_rate >= 0.7:
		rate_desc = "高"
	elif initial_reward_rate <= 0.4:
		rate_desc = "低"
	desc += "\n- 初始收益率：%.0f%%（%s）" % [initial_reward_rate * 100, rate_desc]
	
	# 收益衰减率描述
	var decay_desc = "中"
	if reward_decay_rate >= 0.6:
		decay_desc = "快"
	elif reward_decay_rate <= 0.3:
		decay_desc = "慢"
	desc += "\n- 收益衰减率：%.0f%%（%s）" % [reward_decay_rate * 100, decay_desc]
	
	# 努力水平描述
	var effort_desc = "中"
	if effort_level >= 0.6:
		effort_desc = "高"
	elif effort_level <= 0.3:
		effort_desc = "低"
	desc += "\n- 努力水平：%.0f%%（%s）" % [effort_level * 100, effort_desc]
	
	# 添加对AI行为的影响说明
	desc += "\n\n【情境参数对你行为的影响】"
	desc += "\n根据边际价值定理(MVT)，你在本情境中的最优停留时间 T 满足："
	desc += "\nlog(T) = log[η_s · log(S) − log(p_base) − β_effort · effort] − η_a · log(a)"
	
	if initial_reward_rate >= 0.7:
		desc += "\n- 本情境初始奖赏丰富，你可能会被吸引而停留较久"
	elif initial_reward_rate <= 0.4:
		desc += "\n- 本情境初始奖赏较低，你可能不会投入太多时间"
	
	if reward_decay_rate >= 0.6:
		desc += "\n- 奖赏消耗速度快，你需要快速行动或及时离开"
	
	if effort_level >= 0.6:
		desc += "\n- 本情境需要付出较多努力，高努力敏感性的你可能会回避或提前离开"
		desc += "\n- 如果你当前抑郁水平较高，可能会因为努力成本而减少参与"
	elif effort_level <= 0.3:
		desc += "\n- 本情境努力成本较低，即使高努力敏感性的你也可能愿意参与"
	
	if activity_types.size() > 0:
		desc += "\n- 本情境适合的活动类型：" + ", ".join(activity_types)
	
	return desc
