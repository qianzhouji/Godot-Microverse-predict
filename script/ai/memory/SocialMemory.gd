class_name SocialMemory
extends RefCounted

# ============================================
# SocialMemory - 社交记忆管理
# ============================================
# 管理Agent之间的社交关系和互动历史
# 包括对话、共同活动、关系分数等
# ============================================

# 互动记录结构
class InteractionRecord:
	var timestamp: String          # 游戏时间
	var real_timestamp: float      # Unix时间戳
	var type: String               # DIALOGUE, WHISPER, GROUP_ACTIVITY, etc.
	var topic: String              # 话题/主题
	var duration: float            # 持续时间（游戏分钟）
	var location: String           # 地点
	var emotional_impact: float    # 对关系的影响 (-1.0 ~ 1.0)
	var content_summary: String    # 内容摘要
	
	func _init(p_timestamp: String, p_type: String):
		timestamp = p_timestamp
		type = p_type
		real_timestamp = Time.get_unix_time_from_system()
		topic = ""
		duration = 0.0
		location = ""
		emotional_impact = 0.0
		content_summary = ""
	
	func to_dictionary() -> Dictionary:
		return {
			"timestamp": timestamp,
			"real_timestamp": real_timestamp,
			"type": type,
			"topic": topic,
			"duration": duration,
			"location": location,
			"emotional_impact": emotional_impact,
			"content_summary": content_summary
		}
	
	static func from_dictionary(data: Dictionary) -> InteractionRecord:
		var record = InteractionRecord.new(
			data.get("timestamp", ""),
			data.get("type", "")
		)
		record.real_timestamp = data.get("real_timestamp", 0.0)
		record.topic = data.get("topic", "")
		record.duration = data.get("duration", 0.0)
		record.location = data.get("location", "")
		record.emotional_impact = data.get("emotional_impact", 0.0)
		record.content_summary = data.get("content_summary", "")
		return record

# 社交关系结构
class Relationship:
	var agent_a: String
	var agent_b: String
	var total_interactions: int = 0
	var relationship_score: float = 0.0    # -1.0 ~ 1.0
	var last_interaction_time: float = 0.0
	var interaction_history: Array[InteractionRecord] = []
	var interaction_count_by_type: Dictionary = {}  # {type: count}
	
	func _init(p_a: String, p_b: String):
		agent_a = p_a
		agent_b = p_b
	
	func record_interaction(record: InteractionRecord) -> void:
		interaction_history.append(record)
		total_interactions += 1
		last_interaction_time = record.real_timestamp
		
		# 更新类型计数
		if not interaction_count_by_type.has(record.type):
			interaction_count_by_type[record.type] = 0
		interaction_count_by_type[record.type] += 1
		
		# 更新关系分数（带衰减）
		var impact = record.emotional_impact
		relationship_score = relationship_score * 0.9 + impact * 0.1
		relationship_score = clamp(relationship_score, -1.0, 1.0)
	
	func get_recent_interactions(hours: int = 24) -> Array[InteractionRecord]:
		var result: Array[InteractionRecord] = []
		var current_time = Time.get_unix_time_from_system()
		var threshold = current_time - (hours * 3600)
		
		for record in interaction_history:
			if record.real_timestamp >= threshold:
				result.append(record)
		
		return result
	
	func get_dominant_interaction_type() -> String:
		var max_count = 0
		var dominant_type = ""
		for type in interaction_count_by_type.keys():
			var count = interaction_count_by_type[type]
			if count > max_count:
				max_count = count
				dominant_type = type
		return dominant_type
	
	func to_dictionary() -> Dictionary:
		var history_dicts = []
		for record in interaction_history:
			history_dicts.append(record.to_dictionary())
		
		return {
			"agent_a": agent_a,
			"agent_b": agent_b,
			"total_interactions": total_interactions,
			"relationship_score": relationship_score,
			"last_interaction_time": last_interaction_time,
			"interaction_history": history_dicts,
			"interaction_count_by_type": interaction_count_by_type
		}
	
	static func from_dictionary(data: Dictionary) -> Relationship:
		var rel = Relationship.new(
			data.get("agent_a", ""),
			data.get("agent_b", "")
		)
		rel.total_interactions = data.get("total_interactions", 0)
		rel.relationship_score = data.get("relationship_score", 0.0)
		rel.last_interaction_time = data.get("last_interaction_time", 0.0)
		rel.interaction_count_by_type = data.get("interaction_count_by_type", {})
		
		var history_dicts = data.get("interaction_history", [])
		for dict in history_dicts:
			rel.interaction_history.append(InteractionRecord.from_dictionary(dict))
		
		return rel

# 存储的社交关系 {(agent_a, agent_b): Relationship}
var _relationships: Dictionary = {}

# 获取或创建关系
func _get_relationship(agent_a: String, agent_b: String) -> Relationship:
	# 确保顺序一致
	var pair = [agent_a, agent_b]
	pair.sort()
	var key = pair[0] + "_" + pair[1]
	
	if not _relationships.has(key):
		_relationships[key] = Relationship.new(pair[0], pair[1])
	
	return _relationships[key]

# 记录一次互动
func record_interaction(agent_a: String, agent_b: String, interaction_type: String,
						game_time: float, location: String,
						topic: String = "", duration: float = 0.0,
						emotional_impact: float = 0.0,
						content_summary: String = "") -> void:
	
	var timestamp = _format_game_time(game_time)
	var record = InteractionRecord.new(timestamp, interaction_type)
	record.topic = topic
	record.duration = duration
	record.location = location
	record.emotional_impact = emotional_impact
	record.content_summary = content_summary
	
	var relationship = _get_relationship(agent_a, agent_b)
	relationship.record_interaction(record)
	
	print("[SocialMemory] 记录互动: %s <-> %s (%s)" % [agent_a, agent_b, interaction_type])

# 获取两个Agent的关系
func get_relationship(agent_a: String, agent_b: String) -> Relationship:
	return _get_relationship(agent_a, agent_b)

# 获取关系分数 (-1.0 ~ 1.0)
func get_relationship_score(agent_a: String, agent_b: String) -> float:
	var rel = _get_relationship(agent_a, agent_b)
	return rel.relationship_score

# 获取关系描述文本
func get_relationship_description(agent_a: String, agent_b: String) -> String:
	var score = get_relationship_score(agent_a, agent_b)
	var rel = _get_relationship(agent_a, agent_b)
	
	if score > 0.7:
		return "亲密朋友"
	elif score > 0.4:
		return "好朋友"
	elif score > 0.1:
		return "熟人"
	elif score > -0.1:
		return "普通关系"
	elif score > -0.4:
		return "有些疏远"
	elif score > -0.7:
		return "关系不好"
	else:
		return "敌对"

# 获取Agent的所有关系
func get_all_relationships(agent_id: String) -> Array[Relationship]:
	var result: Array[Relationship] = []
	for key in _relationships.keys():
		var rel = _relationships[key]
		if rel.agent_a == agent_id or rel.agent_b == agent_id:
			result.append(rel)
	return result

# 获取最近互动
func get_recent_interactions(agent_a: String, agent_b: String, hours: int = 24) -> Array[InteractionRecord]:
	var rel = _get_relationship(agent_a, agent_b)
	return rel.get_recent_interactions(hours)

# 获取互动统计
func get_interaction_stats(agent_a: String, agent_b: String) -> Dictionary:
	var rel = _get_relationship(agent_a, agent_b)
	return {
		"total": rel.total_interactions,
		"by_type": rel.interaction_count_by_type.duplicate(),
		"dominant_type": rel.get_dominant_interaction_type(),
		"last_interaction": rel.last_interaction_time
	}

# 序列化为字典
func serialize() -> Dictionary:
	var data = {}
	for key in _relationships.keys():
		data[key] = _relationships[key].to_dictionary()
	return data

# 从字典反序列化
func deserialize(data: Dictionary) -> void:
	_relationships.clear()
	for key in data.keys():
		_relationships[key] = Relationship.from_dictionary(data[key])

# 清理旧互动记录（保留最近N个）
func cleanup_old_interactions(agent_a: String, agent_b: String, max_count: int = 50) -> void:
	var rel = _get_relationship(agent_a, agent_b)
	if rel.interaction_history.size() <= max_count:
		return
	
	# 按时间排序，保留最近的
	var sorted = rel.interaction_history.duplicate()
	sorted.sort_custom(func(a, b): return a.real_timestamp > b.real_timestamp)
	
	var kept: Array[InteractionRecord] = []
	for i in range(min(max_count, sorted.size())):
		kept.append(sorted[i])
	
	rel.interaction_history = kept

# 辅助函数：格式化游戏时间
func _format_game_time(game_time_minutes: float) -> String:
	var hours = int(game_time_minutes / 60)
	var minutes = int(fmod(game_time_minutes, 60))
	return "%02d:%02d" % [hours, minutes]
