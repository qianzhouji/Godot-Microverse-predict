# MemoryManager - 兼容性别名
# 为了保持向后兼容，将 MemoryManager 映射到 MemorySystem
# 所有调用都会被转发到 MemorySystem 单例

extends Node

# 委托所有调用到 MemorySystem
func _get(property: StringName):
	if MemorySystem.instance:
		return MemorySystem.instance.get(property)
	return null

func _set(property: StringName, value) -> bool:
	if MemorySystem.instance:
		MemorySystem.instance.set(property, value)
		return true
	return false

func _get_method_list() -> Array:
	if MemorySystem.instance:
		return MemorySystem.instance.get_method_list()
	return []

# 保持枚举兼容
const MemoryType = MemorySystem.MemoryType
const MemoryImportance = MemorySystem.MemoryImportance

# 转发函数调用
func get_character_memories(character: Node) -> Array:
	if MemorySystem.instance:
		return MemorySystem.instance.get_character_memories(character)
	return []

func add_memory(character: Node, memory_content: String, 
				memory_type: int = MemorySystem.MemoryType.PERSONAL, 
				importance: int = MemorySystem.MemoryImportance.NORMAL) -> void:
	if MemorySystem.instance:
		MemorySystem.instance.add_memory(character, memory_content, memory_type, importance)

func get_formatted_memories_for_prompt(character: Node, max_count: int = -1) -> String:
	if MemorySystem.instance:
		return MemorySystem.instance.get_formatted_memories_for_prompt(character, max_count)
	return "\n\n记忆信息：\n- 暂无重要记忆"

# 内部方法转发（被 GodUI 直接调用）
func _format_memory_for_display(memory: Dictionary) -> String:
	if MemorySystem.instance:
		return MemorySystem.instance._format_memory_for_display(memory)
	return ""

func _get_memory_importance(memory: Dictionary) -> int:
	if MemorySystem.instance:
		return MemorySystem.instance._get_memory_importance(memory)
	return 3

func _get_memory_timestamp(memory: Dictionary) -> float:
	if MemorySystem.instance:
		return MemorySystem.instance._get_memory_timestamp(memory)
	return 0.0
