class_name MovementExecutor
extends RefCounted

# ============================================
# MovementExecutor - 移动活动执行器
# ============================================
# 负责执行Activity.MOVE_TO类型的活动
# 将移动逻辑从AIAgent中抽离，实现Activity系统整合
# ============================================

# 移动状态
enum MoveState {
	IDLE,           # 空闲
	MOVING,         # 移动中
	ARRIVED,        # 已到达
	FAILED          # 移动失败
}

# 当前状态
var current_state: MoveState = MoveState.IDLE

# 移动参数
var target_position: Vector2 = Vector2.ZERO
var target_room: String = ""
var move_speed: float = 100.0  # 像素/秒

# 导航引用
var navigation_agent: NavigationAgent2D = null
var character: CharacterBody2D = null

# 回调
var on_arrived: Callable = Callable()
var on_failed: Callable = Callable()

# ============================================
# 初始化
# ============================================

func _init(p_character: CharacterBody2D, p_navigation_agent: NavigationAgent2D = null):
	character = p_character
	navigation_agent = p_navigation_agent

# ============================================
# 移动活动执行接口
# ============================================

func execute_move_activity(activity: Activity) -> Dictionary:
	"""
	执行移动活动
	
	参数:
		activity: Activity类型为MOVE_TO的活动
	
	返回:
		{"success": bool, "reason": String, "estimated_duration": float}
	"""
	if activity.activity_type != Activity.ActivityType.MOVE_TO:
		return {"success": false, "reason": "不是移动活动", "estimated_duration": 0.0}
	
	# 提取参数
	var params = activity.parameters
	target_position = params.get("target_location", Vector2.ZERO)
	target_room = params.get("target_room", "")
	
	if target_position == Vector2.ZERO:
		return {"success": false, "reason": "目标位置无效", "estimated_duration": 0.0}
	
	# 计算预计移动时间
	var distance = character.global_position.distance_to(target_position)
	var estimated_duration = distance / move_speed
	
	# 开始移动
	var start_result = _start_movement()
	
	return {
		"success": start_result,
		"reason": "" if start_result else "无法开始移动",
		"estimated_duration": estimated_duration
	}

func _start_movement() -> bool:
	"""开始移动"""
	if not character:
		return false
	
	current_state = MoveState.MOVING
	
	# 使用NavigationAgent2D或简单移动
	if navigation_agent and navigation_agent.is_enabled():
		# 使用导航
		navigation_agent.target_position = target_position
		print("[MovementExecutor] %s 开始导航移动至 %s" % [character.name, target_position])
	else:
		# 简单直线移动（无导航）
		print("[MovementExecutor] %s 开始直线移动至 %s" % [character.name, target_position])
	
	return true

# ============================================
# 每帧更新（需要在AIAgent._process中调用）
# ============================================

func update(delta: float) -> void:
	"""更新移动状态，每帧调用"""
	if current_state != MoveState.MOVING:
		return
	
	if not character:
		return
	
	# 检查是否到达
	var distance = character.global_position.distance_to(target_position)
	if distance < 5.0:  # 5像素内视为到达
		_arrived()
		return
	
	# 执行移动
	if navigation_agent and navigation_agent.is_enabled():
		# 使用导航代理
		_update_navigation_movement(delta)
	else:
		# 简单直线移动
		_update_direct_movement(delta)

func _update_navigation_movement(delta: float) -> void:
	"""使用NavigationAgent2D移动"""
	if navigation_agent.is_navigation_finished():
		_arrived()
		return
	
	var next_pos = navigation_agent.get_next_path_position()
	var direction = (next_pos - character.global_position).normalized()
	
	character.velocity = direction * move_speed
	character.move_and_slide()

func _update_direct_movement(delta: float) -> void:
	"""直接直线移动（无导航）"""
	var direction = (target_position - character.global_position).normalized()
	
	character.velocity = direction * move_speed
	character.move_and_slide()

# ============================================
# 状态回调
# ============================================

func _arrived() -> void:
	"""到达目标"""
	current_state = MoveState.ARRIVED
	character.velocity = Vector2.ZERO
	print("[MovementExecutor] %s 已到达目标位置 %s" % [character.name, target_position])
	
	if on_arrived.is_valid():
		on_arrived.call()

func _failed(reason: String) -> void:
	"""移动失败"""
	current_state = MoveState.FAILED
	character.velocity = Vector2.ZERO
	print("[MovementExecutor] %s 移动失败: %s" % [character.name, reason])
	
	if on_failed.is_valid():
		on_failed.call(reason)

# ============================================
# 公共接口
# ============================================

func is_moving() -> bool:
	return current_state == MoveState.MOVING

func has_arrived() -> bool:
	return current_state == MoveState.ARRIVED

func stop_movement() -> void:
	"""停止移动"""
	current_state = MoveState.IDLE
	if character:
		character.velocity = Vector2.ZERO
	print("[MovementExecutor] %s 移动已停止" % (character.name if character else "Unknown"))

func get_remaining_distance() -> float:
	"""获取剩余距离"""
	if not character or current_state != MoveState.MOVING:
		return 0.0
	return character.global_position.distance_to(target_position)

func get_move_progress() -> float:
	"""获取移动进度(0.0-1.0)"""
	if not character:
		return 0.0
	
	# 需要记录起始位置才能计算进度，这里简化处理
	var remaining = get_remaining_distance()
	if remaining < 1.0:
		return 1.0
	return 0.5  # 无法精确计算时返回中间值

# ============================================
# 静态工具方法
# ============================================

static func calculate_target_position_for_character(
	from_pos: Vector2,
	target_char: CharacterBody2D,
	is_whisper: bool = false,
	room_manager = null
) -> Vector2:
	"""
	计算移动到目标角色的位置
	
	参数:
		from_pos: 起始位置
		target_char: 目标角色
		is_whisper: 是否悄悄话(需要贴身)
		room_manager: 房间管理器(用于中范围判断)
	
	返回:
		目标位置
	"""
	if not target_char:
		return Vector2.ZERO
	
	var target_pos = target_char.global_position
	
	if is_whisper:
		# 悄悄话模式:贴身位置(15像素内)
		var whisper_offset = Vector2(randf_range(-15, 15), randf_range(-15, 15))
		return target_pos + whisper_offset
	
	# 检查是否在同一中范围
	var in_same_medium_range = false
	if room_manager:
		var current_room = room_manager.get_current_room(room_manager.rooms, from_pos)
		var target_room = room_manager.get_current_room(room_manager.rooms, target_pos)
		if current_room and target_room and current_room == target_room:
			in_same_medium_range = _is_in_same_medium_range(current_room, from_pos, target_pos)
	
	if in_same_medium_range:
		# 同一中范围:移动到目标身边小范围(30像素内)
		var small_range_offset = Vector2(randf_range(-30, 30), randf_range(-30, 30))
		return target_pos + small_range_offset
	else:
		# 不同中范围:移动到目标所在中范围的中心位置
		if room_manager:
			var target_room = room_manager.get_current_room(room_manager.rooms, target_pos)
			if target_room:
				var target_medium_range = _get_medium_range_description(target_room, target_pos)
				var range_center = _get_medium_range_center_position(target_room, target_medium_range)
				var random_offset = Vector2(randf_range(-20, 20), randf_range(-20, 20))
				return range_center + random_offset
		
		# 找不到房间信息,直接移动到目标附近
		var medium_range_offset = Vector2(randf_range(-50, 50), randf_range(-50, 50))
		return target_pos + medium_range_offset

static func calculate_target_position_for_room(
	room_data: Dictionary,
	max_offset_ratio: float = 0.3
) -> Vector2:
	"""
	计算移动到房间的位置
	
	参数:
		room_data: 房间数据 {position: Vector2, size: Vector2}
		max_offset_ratio: 最大偏移比例
	
	返回:
		目标位置
	"""
	var room_pos = room_data.get("position", Vector2.ZERO)
	var room_size = room_data.get("size", Vector2(200, 100))
	
	var half_width = room_size.x * 0.5
	var half_height = room_size.y * 0.5
	
	var offset_x = randf_range(-half_width * max_offset_ratio, half_width * max_offset_ratio)
	var offset_y = randf_range(-half_height * max_offset_ratio, half_height * max_offset_ratio)
	
	return room_pos + Vector2(offset_x, offset_y)

# ============================================
# 辅助方法（从AIAgent迁移）
# ============================================

static func _is_in_same_medium_range(room, pos1: Vector2, pos2: Vector2) -> bool:
	"""检查两个位置是否在同一个中范围"""
	# 获取房间中心
	var room_center = room.position if room.has("position") else Vector2.ZERO
	var room_size = room.size if room.has("size") else Vector2(400, 300)
	
	# 简单的象限判断（可根据需要细化）
	var half_width = room_size.x * 0.5
	var half_height = room_size.y * 0.5
	
	var quadrant1 = _get_quadrant(pos1, room_center, half_width, half_height)
	var quadrant2 = _get_quadrant(pos2, room_center, half_width, half_height)
	
	return quadrant1 == quadrant2

static func _get_quadrant(pos: Vector2, center: Vector2, half_w: float, half_h: float) -> int:
	"""获取位置所在象限 (1-4)"""
	var left = pos.x < center.x
	var top = pos.y < center.y
	
	if left and top: return 1
	if not left and top: return 2
	if left and not top: return 3
	return 4

static func _get_medium_range_description(room, pos: Vector2) -> String:
	"""获取中范围描述"""
	var room_center = room.position if room.has("position") else Vector2.ZERO
	var room_size = room.size if room.has("size") else Vector2(400, 300)
	
	var half_width = room_size.x * 0.5
	var half_height = room_size.y * 0.5
	
	var quadrant = _get_quadrant(pos, room_center, half_width, half_height)
	return "第%d象限" % quadrant

static func _get_medium_range_center_position(room, range_desc: String) -> Vector2:
	"""获取中范围中心位置"""
	var room_center = room.position if room.has("position") else Vector2.ZERO
	var room_size = room.size if room.has("size") else Vector2(400, 300)
	
	var half_width = room_size.x * 0.5
	var half_height = room_size.y * 0.5
	
	var quadrant = range_desc.replace("第", "").replace("象限", "").to_int()
	
	match quadrant:
		1: return room_center + Vector2(-half_width * 0.5, -half_height * 0.5)
		2: return room_center + Vector2(half_width * 0.5, -half_height * 0.5)
		3: return room_center + Vector2(-half_width * 0.5, half_height * 0.5)
		4: return room_center + Vector2(half_width * 0.5, half_height * 0.5)
		_: return room_center
