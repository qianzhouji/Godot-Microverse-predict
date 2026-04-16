extends Node

# 将 Room 类声明为全局可访问
class_name Room

# 存储所有房间信息
var rooms: Dictionary = {}

func _ready():
	add_to_group("room_manager")
	call_deferred("_init_rooms")
# 初始化房间信息
func _init_rooms():
	rooms.clear()
	for area in get_tree().get_nodes_in_group("room_area"):
		var room_name = area.room_name
		var room_desc = area.room_desc
		var collision_shape = area.get_node("CollisionShape2D")
		var shape = collision_shape.shape
		# 计算房间中心位置 = Area2D全局位置 + CollisionShape2D的相对位置
		var position = area.global_position + collision_shape.position
		var size = Vector2.ZERO
		if shape is RectangleShape2D:
			size = shape.extents * 2
		else:
			size = Vector2(100, 100)
		var room_data = RoomData.new(room_name, position, size, room_desc)
		rooms[area.name] = room_data
		#print("房间：", room_name, " 位置：", position, " 大小：", size)
# 获取角色当前所在的房间
func get_current_room(current_rooms: Dictionary, character_position: Vector2) -> RoomData:
	print("角色位置： ", character_position.x, ",", character_position.y)
	for room in current_rooms.values():
		if is_position_in_room(character_position, room):
			return room
	return null

# 判断位置是否在房间内
func is_position_in_room(pos: Vector2, room: RoomData) -> bool:
	# 确保房间数据有效
	if room == null or room.position == Vector2.ZERO:
		return false
	
	# 计算房间的边界
	var left = room.position.x - room.size.x / 2
	var right = room.position.x + room.size.x / 2
	var top = room.position.y - room.size.y / 2
	var bottom = room.position.y + room.size.y / 2
	
	# 判断位置是否在房间边界内
	return pos.x >= left and pos.x <= right and pos.y >= top and pos.y <= bottom

# 获取房间内的重要位置
func get_room_important_locations(room_name: String) -> Dictionary:
	if rooms.has(room_name):
		return rooms[room_name].important_locations
	return {}

# ============================================
# 系统层内部接口（仅供系统层组件使用）
# ============================================
# ⚠️ 警告：此接口仅供RewardSystem等系统层组件调用
# Agent不应直接调用此函数，应通过RewardSystem间接获取信息
func get_room_objective_params_internal(room_name: String) -> Dictionary:
	"""
	获取房间的客观参数（系统层内部使用）
	
	参数:
		room_name: 房间名称
	
	返回:
		Dictionary: {"S": 初始收益率, "a": 衰减率, "E": 努力成本}
		如果未找到房间，返回空字典
	"""
	# 查找RoomArea节点
	var room_areas = get_tree().get_nodes_in_group("room_area")
	for area in room_areas:
		if area.room_name == room_name:
			return {
				"S": area.initial_reward_rate,   # 初始收益率 (Agent不可见)
				"a": area.reward_decay_rate,      # 收益衰减率 (Agent不可见)
				"E": area.effort_level            # 努力成本 (Agent不可见)
			}
	
	push_warning("[RoomManager] 未找到房间: %s" % room_name)
	return {}

# 获取所有房间的客观参数（用于调试）
func get_all_rooms_objective_params() -> Dictionary:
	"""
	获取所有房间的客观参数（仅供调试使用）
	"""
	var all_params = {}
	var room_areas = get_tree().get_nodes_in_group("room_area")
	
	for area in room_areas:
		all_params[area.room_name] = {
			"S": area.initial_reward_rate,
			"a": area.reward_decay_rate,
			"E": area.effort_level
		}
	
	return all_params
