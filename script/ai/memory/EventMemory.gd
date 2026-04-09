class_name EventMemory
extends RefCounted

# ============================================
# EventMemory - 事件记忆管理
# ============================================
# 管理Agent的事件历史记录
# 包括移动、对话、上课、自习等活动
# ============================================

# 事件数据结构
class EventRecord:
	var id: String
	var timestamp: String          # 游戏时间字符串 "08:30"
	var real_timestamp: float      # Unix时间戳
	var agent_id: String
	var event_type: String         # MOVE_TO, DIALOGUE, CLASS, etc.
	var location: String
	var details: Dictionary
	var emotional_valence: float   # -1.0 ~ 1.0
	var importance: int            # 1, 3, 5, 10
	
	func _init(p_id: String, p_timestamp: String, p_agent_id: String, p_type: String):
		id = p_id
		timestamp = p_timestamp
		agent_id = p_agent_id
		event_type = p_type
		real_timestamp = Time.get_unix_time_from_system()
		emotional_valence = 0.0
		importance = 3  # NORMAL
		details = {}
		location = ""
	
	func to_dictionary() -> Dictionary:
		return {
			"id": id,
			"timestamp": timestamp,
			"real_timestamp": real_timestamp,
			"agent_id": agent_id,
			"event_type": event_type,
			"location": location,
			"details": details,
			"emotional_valence": emotional_valence,
			"importance": importance
		}
	
	static func from_dictionary(data: Dictionary) -> EventRecord:
		var record = EventRecord.new(
			data.get("id", ""),
			data.get("timestamp", ""),
			data.get("agent_id", ""),
			data.get("event_type", "")
		)
		record.real_timestamp = data.get("real_timestamp", 0.0)
		record.location = data.get("location", "")
		record.details = data.get("details", {})
		record.emotional_valence = data.get("emotional_valence", 0.0)
		record.importance = data.get("importance", 3)
		return record

# 存储的事件记录 {agent_id: [EventRecord, ...]}
var _event_cache: Dictionary = {}

# 记录一个事件
func record_event(agent_id: String, event_type: String, game_time: float, 
				  location: String, details: Dictionary = {}, 
				  importance: int = 3, emotional_valence: float = 0.0) -> EventRecord:
	
	var timestamp = _format_game_time(game_time)
	var event_id = "%s_%s_%d" % [agent_id, event_type, Time.get_unix_time_from_system()]
	
	var record = EventRecord.new(event_id, timestamp, agent_id, event_type)
	record.location = location
	record.details = details
	record.importance = importance
	record.emotional_valence = emotional_valence
	
	# 添加到缓存
	if not _event_cache.has(agent_id):
		_event_cache[agent_id] = []
	_event_cache[agent_id].append(record)
	
	# 按时间排序
	_event_cache[agent_id].sort_custom(func(a, b): return a.real_timestamp > b.real_timestamp)
	
	print("[EventMemory] 记录事件: %s %s at %s" % [agent_id, event_type, timestamp])
	
	return record

# 获取Agent的所有事件
func get_events(agent_id: String) -> Array[EventRecord]:
	if not _event_cache.has(agent_id):
		return []
	
	var result: Array[EventRecord] = []
	for record in _event_cache[agent_id]:
		result.append(record)
	return result

# 获取最近N小时的游戏时间内的事件
func get_recent_events(agent_id: String, current_game_time: float, game_hours: float) -> Array[EventRecord]:
	var all_events = get_events(agent_id)
	var result: Array[EventRecord] = []
	
	# 游戏时间转换为分钟比较
	var time_threshold = current_game_time - (game_hours * 60)
	
	for record in all_events:
		var record_time = _parse_game_time(record.timestamp)
		if record_time >= time_threshold:
			result.append(record)
	
	return result

# 按类型获取事件
func get_events_by_type(agent_id: String, event_type: String) -> Array[EventRecord]:
	var all_events = get_events(agent_id)
	var result: Array[EventRecord] = []
	
	for record in all_events:
		if record.event_type == event_type:
			result.append(record)
	
	return result

# 获取重要事件（重要性 >= threshold）
func get_important_events(agent_id: String, threshold: int = 5) -> Array[EventRecord]:
	var all_events = get_events(agent_id)
	var result: Array[EventRecord] = []
	
	for record in all_events:
		if record.importance >= threshold:
			result.append(record)
	
	return result

# 序列化为字典（用于保存）
func serialize() -> Dictionary:
	var data = {}
	for agent_id in _event_cache.keys():
		var events = _event_cache[agent_id]
		var event_dicts = []
		for event in events:
			event_dicts.append(event.to_dictionary())
		data[agent_id] = event_dicts
	return data

# 从字典反序列化（用于加载）
func deserialize(data: Dictionary) -> void:
	_event_cache.clear()
	for agent_id in data.keys():
		var event_dicts = data[agent_id]
		var events: Array[EventRecord] = []
		for dict in event_dicts:
			events.append(EventRecord.from_dictionary(dict))
		_event_cache[agent_id] = events

# 清理旧事件（保留最近N个）
func cleanup_old_events(agent_id: String, max_count: int = 100) -> void:
	if not _event_cache.has(agent_id):
		return
	
	var events = _event_cache[agent_id]
	if events.size() <= max_count:
		return
	
	# 按重要性排序，保留重要和最新的事件
	var sorted = events.duplicate()
	sorted.sort_custom(func(a, b):
		if a.importance != b.importance:
			return a.importance > b.importance
		return a.real_timestamp > b.real_timestamp
	)
	
	var kept: Array[EventRecord] = []
	for i in range(min(max_count, sorted.size())):
		kept.append(sorted[i])
	
	_event_cache[agent_id] = kept

# 辅助函数：格式化游戏时间
func _format_game_time(game_time_minutes: float) -> String:
	var hours = int(game_time_minutes / 60)
	var minutes = int(fmod(game_time_minutes, 60))
	return "%02d:%02d" % [hours, minutes]

# 辅助函数：解析游戏时间
func _parse_game_time(time_str: String) -> float:
	var parts = time_str.split(":")
	if parts.size() >= 2:
		var hours = parts[0].to_int()
		var minutes = parts[1].to_int()
		return hours * 60.0 + minutes
	return 0.0
