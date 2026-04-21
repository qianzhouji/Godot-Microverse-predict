extends RefCounted
class_name RoomData

var name: String           # 节点名称（如 "RoomArea1"）
var room_name: String      # 显示名称（如 "图书馆"）
var position: Vector2
var size: Vector2
var description: String
var important_locations: Dictionary = {}

func _init(node_name: String, room_pos: Vector2, room_size: Vector2, room_desc: String, display_name: String = ""):
	name = node_name
	room_name = display_name if not display_name.is_empty() else node_name
	position = room_pos
	size = room_size
	description = room_desc 
