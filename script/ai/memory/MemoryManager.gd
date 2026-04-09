# MemoryManager - 兼容性别名
# 为了保持向后兼容，将 MemoryManager 映射到 MemorySystem
# 所有调用都会被转发到 MemorySystem 单例

extends Node

# 获取 MemorySystem 实例
func _get_memory_system():
	return get_node_or_null("/root/MemorySystem")

# 委托所有调用到 MemorySystem
func _get(property: StringName):
	var ms = _get_memory_system()
	if ms:
		return ms.get(property)
	return null

func _set(property: StringName, value) -> bool:
	var ms = _get_memory_system()
	if ms:
		ms.set(property, value)
		return true
	return false

# 保持枚举兼容（从实际实例获取）
var MemoryType:
	get:
		var ms = _get_memory_system()
		if ms:
			return ms.MemoryType
		return 0

var MemoryImportance:
	get:
		var ms = _get_memory_system()
		if ms:
			return ms.MemoryImportance
		return 3

# 转发函数调用
func get_character_memories(character: Node) -> Array:
	var ms = _get_memory_system()
	if ms:
		return ms.get_character_memories(character)
	return []

func add_memory(character: Node, memory_content: String, 
				memory_type: int = 0, 
				importance: int = 3) -> void:
	var ms = _get_memory_system()
	if ms:
		ms.add_memory(character, memory_content, memory_type, importance)

func get_formatted_memories_for_prompt(character: Node, max_count: int = -1) -> String:
	var ms = _get_memory_system()
	if ms:
		return ms.get_formatted_memories_for_prompt(character, max_count)
	return "\n\n记忆信息：\n- 暂无重要记忆"

# 内部方法转发（被 GodUI 直接调用）
func _format_memory_for_display(memory: Dictionary) -> String:
	var ms = _get_memory_system()
	if ms:
		return ms._format_memory_for_display(memory)
	return ""

func _get_memory_importance(memory: Dictionary) -> int:
	var ms = _get_memory_system()
	if ms:
		return ms._get_memory_importance(memory)
	return 3

func _get_memory_timestamp(memory: Dictionary) -> float:
	var ms = _get_memory_system()
	if ms:
		return ms._get_memory_timestamp(memory)
	return 0.0
