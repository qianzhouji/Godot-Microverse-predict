class_name MemoryPersistence
extends RefCounted

# ============================================
# MemoryPersistence - 记忆持久化存储
# ============================================
# 负责记忆的保存和加载
# 使用 JSON 格式存储到 user://memory/ 目录
# ============================================

const MEMORY_DIR = "user://memory/"
const AGENTS_SUBDIR = "agents/"
const RELATIONSHIPS_SUBDIR = "relationships/"
const GLOBAL_FILE = "global_memory.json"

const CURRENT_VERSION = "1.0"

# 确保目录存在
static func _ensure_directory() -> void:
	var dir = DirAccess.open("user://")
	if not dir.dir_exists("memory"):
		dir.make_dir("memory")
	if not dir.dir_exists("memory/agents"):
		dir.make_dir("memory/agents")
	if not dir.dir_exists("memory/relationships"):
		dir.make_dir("memory/relationships")

# 保存 Agent 的记忆数据
static func save_agent_memory(agent_id: String, data: Dictionary) -> bool:
	_ensure_directory()
	
	var file_path = MEMORY_DIR + AGENTS_SUBDIR + agent_id + ".json"
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	
	if not file:
		push_error("无法保存记忆文件: " + file_path)
		return false
	
	# 添加元数据
	var save_data = {
		"version": CURRENT_VERSION,
		"saved_at": Time.get_unix_time_from_system(),
		"agent_id": agent_id,
		"data": data
	}
	
	file.store_string(JSON.stringify(save_data, "\t"))
	file.close()
	
	return true

# 加载 Agent 的记忆数据
static func load_agent_memory(agent_id: String) -> Dictionary:
	var file_path = MEMORY_DIR + AGENTS_SUBDIR + agent_id + ".json"
	
	if not FileAccess.file_exists(file_path):
		return {}  # 文件不存在，返回空数据
	
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		push_error("无法读取记忆文件: " + file_path)
		return {}
	
	var json_text = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var result = json.parse(json_text)
	
	if result != OK:
		push_error("JSON解析失败: " + file_path)
		return {}
	
	var save_data = json.get_data()
	
	# 版本检查
	var version = save_data.get("version", "0.0")
	if version != CURRENT_VERSION:
		print("[MemoryPersistence] 版本不匹配: " + version + " vs " + CURRENT_VERSION)
		# TODO: 版本迁移逻辑
	
	return save_data.get("data", {})

# 保存社交关系数据
static func save_relationship(agent_a: String, agent_b: String, data: Dictionary) -> bool:
	_ensure_directory()
	
	# 确保顺序一致（避免重复文件）
	var pair = [agent_a, agent_b]
	pair.sort()
	var filename = pair[0] + "_" + pair[1] + ".json"
	
	var file_path = MEMORY_DIR + RELATIONSHIPS_SUBDIR + filename
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	
	if not file:
		push_error("无法保存关系文件: " + file_path)
		return false
	
	var save_data = {
		"version": CURRENT_VERSION,
		"saved_at": Time.get_unix_time_from_system(),
		"agent_a": agent_a,
		"agent_b": agent_b,
		"data": data
	}
	
	file.store_string(JSON.stringify(save_data, "\t"))
	file.close()
	
	return true

# 加载社交关系数据
static func load_relationship(agent_a: String, agent_b: String) -> Dictionary:
	var pair = [agent_a, agent_b]
	pair.sort()
	var filename = pair[0] + "_" + pair[1] + ".json"
	
	var file_path = MEMORY_DIR + RELATIONSHIPS_SUBDIR + filename
	
	if not FileAccess.file_exists(file_path):
		return {}
	
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		push_error("无法读取关系文件: " + file_path)
		return {}
	
	var json_text = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var result = json.parse(json_text)
	
	if result != OK:
		push_error("JSON解析失败: " + file_path)
		return {}
	
	var save_data = json.get_data()
	return save_data.get("data", {})

# 获取所有已保存的 Agent ID
static func get_saved_agent_ids() -> Array[String]:
	var ids: Array[String] = []
	
	var dir = DirAccess.open(MEMORY_DIR + AGENTS_SUBDIR)
	if not dir:
		return ids
	
	dir.list_dir_begin()
	var filename = dir.get_next()
	while filename != "":
		if filename.ends_with(".json"):
			var agent_id = filename.substr(0, filename.length() - 5)  # 移除 .json
			ids.append(agent_id)
		filename = dir.get_next()
	
	return ids

# 删除 Agent 的所有记忆
static func delete_agent_memory(agent_id: String) -> bool:
	var file_path = MEMORY_DIR + AGENTS_SUBDIR + agent_id + ".json"
	
	if FileAccess.file_exists(file_path):
		var dir = DirAccess.open(MEMORY_DIR + AGENTS_SUBDIR)
		if dir:
			return dir.remove(file_path) == OK
	
	return false

# 全局配置保存/加载
static func save_global_config(config: Dictionary) -> bool:
	_ensure_directory()
	
	var file_path = MEMORY_DIR + GLOBAL_FILE
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	
	if not file:
		return false
	
	var save_data = {
		"version": CURRENT_VERSION,
		"saved_at": Time.get_unix_time_from_system(),
		"config": config
	}
	
	file.store_string(JSON.stringify(save_data, "\t"))
	file.close()
	
	return true

static func load_global_config() -> Dictionary:
	var file_path = MEMORY_DIR + GLOBAL_FILE
	
	if not FileAccess.file_exists(file_path):
		return {}
	
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		return {}
	
	var json_text = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var result = json.parse(json_text)
	
	if result != OK:
		return {}
	
	var save_data = json.get_data()
	return save_data.get("config", {})
