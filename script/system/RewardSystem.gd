extends Node
# 注意：此类通过AutoLoad配置为单例，不使用class_name避免冲突
# 在project.godot中配置: RewardSystem="*res://script/system/RewardSystem.gd"

# 奖赏系统 - 系统层核心组件
# 职责：
# 1. 管理客观情境参数（Agent不可见）
# 2. 计算客观收益 G(t) = (S/a)[1 - exp(-at)]
# 3. 通过信号向Agent发放奖赏
# 4. 封装RoomArea访问，Agent不可直接读取S,a,E

# 单例实例
static var instance: RewardSystem

# 信号：向Agent发放奖赏
# agent_name: 接收奖赏的Agent名称
# room_name: 情境/房间名称
# time: 在情境中停留的时间
# gain: 客观收益值（0-1）
# effort: 情境的努力成本（0-1）
signal reward_distributed(agent_name: String, room_name: String,
						  time: float, gain: float, effort: float)

func _ready():
	instance = self
	print("[RewardSystem] 奖赏系统初始化完成")

# ============================================
# 公开接口：向Agent发放奖赏
# ============================================
# 这是系统层与感知层的唯一合法接口
# Agent只能通过此接口间接"感知"情境，不能直接访问RoomArea
func distribute_reward(agent_name: String, room_name: String, time_in_room: float) -> Dictionary:
	# 1. 获取房间客观参数（系统层内部操作，Agent不可见）
	var room_data = _get_room_objective_params(room_name)
	if room_data.is_empty():
		push_error("[RewardSystem] 未找到房间: %s" % room_name)
		return {"error": "room_not_found", "gain": 0.0, "effort": 0.5}

	var S = room_data.S  # 初始收益率（Agent不可见）
	var a = room_data.a  # 收益衰减率（Agent不可见）
	var E = room_data.E  # 努力成本（Agent不可见）

	# 2. 计算客观收益（TimeUtils内部会处理分钟到秒的转换）
	var actual_gain = _calculate_objective_gain(S, a, time_in_room)

	# 3. 发放奖赏（通过信号通知，Agent通过接收器订阅）
	# Agent只能通过接收器获取此数值，不能直接读取S,a,E
	reward_distributed.emit(agent_name, room_name, time_in_room, actual_gain, E)

	print("[RewardSystem] 向 %s 发放奖赏: %.3f (房间: %s, 时间: %.1f分钟, S=%.2f, a=%.2f)" %
		  [agent_name, actual_gain, room_name, time_in_room, S, a])

	return {
		"gain": actual_gain,
		"effort": E,
		"room_name": room_name,
		"time": time_in_room
	}

# V2: 带上下文的奖赏分发（支持专注度）
func distribute_reward_with_context(agent_name: String, room_name: String, time_in_room: float, context: Dictionary) -> Dictionary:
	"""
	V2: 带上下文的奖赏分发

	参数:
		context: 包含专注度等信息 {focus_level, base_effort, adjusted_effort, base_gain, adjusted_gain}
	"""
	var base_result = distribute_reward(agent_name, room_name, time_in_room)

	# V2: 如果有专注度调整，更新结果
	if context.has("adjusted_gain"):
		base_result.gain = context.adjusted_gain
	if context.has("adjusted_effort"):
		base_result.effort = context.adjusted_effort

	# V2: 添加上下文信息
	base_result["context"] = context

	print("[RewardSystem] %s 专注度: %.0f%%, 调整后奖赏: %.3f" % [
		agent_name,
		context.get("focus_level", 1.0) * 100,
		base_result.gain
	])

	return base_result

# ============================================
# 内部函数：系统层私有，Agent不可调用
# ============================================

# 获取房间客观参数（系统层内部使用）
# ⚠️ 警告：此函数仅供系统层组件调用，Agent不应直接访问
func _get_room_objective_params(room_name: String) -> Dictionary:
	var room_manager = null
	var room_managers = get_tree().get_nodes_in_group("room_manager")
	if room_managers.size() > 0:
		room_manager = room_managers[0]

	if not room_manager:
		room_manager = get_node_or_null("/root/School/RoomManager")
	if not room_manager:
		room_manager = get_node_or_null("/root/Office/RoomManager")
	if not room_manager:
		room_manager = get_node_or_null("/root/RoomManager")

	if not room_manager:
		push_error("[RewardSystem] 未找到RoomManager")
		return {}

	# 通过RoomManager获取，不直接暴露RoomArea节点
	# 这样可以确保Agent无法直接访问RoomArea的导出变量
	if room_manager.has_method("get_room_objective_params_internal"):
		return room_manager.get_room_objective_params_internal(room_name)

	# 降级方案：直接查找（不推荐，但为了兼容性保留）
	push_warning("[RewardSystem] RoomManager未提供内部接口，使用降级方案")
	return _fallback_get_room_params(room_name)

# 降级方案：直接查找RoomArea（不推荐）
func _fallback_get_room_params(room_name: String) -> Dictionary:
	var room_areas = get_tree().get_nodes_in_group("room_area")
	for area in room_areas:
		if area.room_name == room_name:
			return {
				"S": area.initial_reward_rate,
				"a": area.reward_decay_rate,
				"E": area.effort_level
			}
	return {}

# 计算客观收益
# G(t) = (S/a)[1 - exp(-at)]
# time参数：游戏时间（分钟），内部会转换为秒
func _calculate_objective_gain(S: float, a: float, time_minutes: float) -> float:
	# 使用TimeUtils统一计算
	return TimeUtils.calculate_mvt_gain(S, a, time_minutes)

# ============================================
# 工具函数
# ============================================

# 获取情境的理论最优收益（用于验证和调试）
# 此函数仅供调试使用，Agent不应依赖此信息
func get_theoretical_max_gain(room_name: String) -> float:
	var room_data = _get_room_objective_params(room_name)
	if room_data.is_empty():
		return 0.0

	var S = room_data.S
	var a = room_data.a

	# 当 t → ∞ 时，G(t) → S/a
	return clamp(S / a, 0.0, 1.0)

# 获取情境参数的描述（用于调试，不发给Agent）
func get_room_params_debug_info(room_name: String) -> String:
	var room_data = _get_room_objective_params(room_name)
	if room_data.is_empty():
		return "房间未找到: %s" % room_name

	return "房间: %s | S=%.2f | a=%.2f | E=%.2f" % [
		room_name, room_data.S, room_data.a, room_data.E
	]

# 重置系统状态（用于重新开始模拟）
func reset() -> void:
	print("[RewardSystem] 系统状态已重置")
