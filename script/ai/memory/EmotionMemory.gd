class_name EmotionMemory
extends RefCounted

# ============================================
# EmotionMemory - 情感记忆管理
# ============================================
# 管理Agent对其他角色/事物/地点的情感态度
# 包括好感、信任、尊重等维度
# ============================================

# 情感维度枚举
enum EmotionDimension {
	AFFECTION,      # 好感/喜欢
	TRUST,          # 信任
	RESPECT,        # 尊重
	FEAR,           # 恐惧/害怕
	DISLIKE,        # 厌恶/不喜欢
	ANGER           # 愤怒
}

# 情感变化记录
class EmotionChange:
	var timestamp: String
	var real_timestamp: float
	var dimension: String           # 维度名称
	var delta: float                # 变化量
	var trigger_event: String       # 触发事件
	var reason: String              # 原因
	
	func _init(p_timestamp: String, p_dimension: String, p_delta: float):
		timestamp = p_timestamp
		dimension = p_dimension
		delta = p_delta
		real_timestamp = Time.get_unix_time_from_system()
		trigger_event = ""
		reason = ""
	
	func to_dictionary() -> Dictionary:
		return {
			"timestamp": timestamp,
			"real_timestamp": real_timestamp,
			"dimension": dimension,
			"delta": delta,
			"trigger_event": trigger_event,
			"reason": reason
		}
	
	static func from_dictionary(data: Dictionary) -> EmotionChange:
		var change = EmotionChange.new(
			data.get("timestamp", ""),
			data.get("dimension", ""),
			data.get("delta", 0.0)
		)
		change.real_timestamp = data.get("real_timestamp", 0.0)
		change.trigger_event = data.get("trigger_event", "")
		change.reason = data.get("reason", "")
		return change

# 情感状态结构
class EmotionState:
	var target: String              # 目标（角色名、地点、事件类型等）
	var target_type: String         # AGENT, LOCATION, ACTIVITY_TYPE, EVENT_TYPE
	var emotions: Dictionary = {    # 各维度情感值 0.0 ~ 1.0
		"好感": 0.0,
		"信任": 0.0,
		"尊重": 0.0,
		"恐惧": 0.0,
		"厌恶": 0.0,
		"愤怒": 0.0
	}
	var dominant_emotion: String = ""   # 主导情感
	var last_updated: float = 0.0
	var change_history: Array[EmotionChange] = []
	
	func _init(p_target: String, p_type: String):
		target = p_target
		target_type = p_type
	
	func update_emotion(dimension: String, delta: float, timestamp: String, 
						trigger: String = "", reason: String = "") -> void:
		if not emotions.has(dimension):
			return
		
		# 记录变化
		var change = EmotionChange.new(timestamp, dimension, delta)
		change.trigger_event = trigger
		change.reason = reason
		change_history.append(change)
		
		# 更新情感值（带衰减和新值混合）
		var current = emotions[dimension]
		emotions[dimension] = clamp(current + delta, 0.0, 1.0)
		
		# 更新时间
		last_updated = Time.get_unix_time_from_system()
		
		# 重新计算主导情感
		_calculate_dominant_emotion()
	
	func _calculate_dominant_emotion() -> void:
		var max_value = 0.0
		dominant_emotion = ""
		
		for dimension in emotions.keys():
			var value = emotions[dimension]
			if value > max_value:
				max_value = value
				dominant_emotion = dimension
		
		# 如果所有情感都很低，表示中立
		if max_value < 0.1:
			dominant_emotion = "中立"
	
	func get_emotion_towards() -> String:
		if dominant_emotion.is_empty() or dominant_emotion == "中立":
			return "对%s没有特别的情感" % target
		
		var value = emotions.get(dominant_emotion, 0.0)
		var intensity = ""
		if value > 0.7:
			intensity = "强烈的"
		elif value > 0.4:
			intensity = "明显的"
		elif value > 0.1:
			intensity = "些许"
		else:
			intensity = "微弱的"
		
		return "对%s有%s%s" % [target, intensity, dominant_emotion]
	
	func to_dictionary() -> Dictionary:
		var history_dicts = []
		for change in change_history:
			history_dicts.append(change.to_dictionary())
		
		return {
			"target": target,
			"target_type": target_type,
			"emotions": emotions.duplicate(),
			"dominant_emotion": dominant_emotion,
			"last_updated": last_updated,
			"change_history": history_dicts
		}
	
	static func from_dictionary(data: Dictionary) -> EmotionState:
		var state = EmotionState.new(
			data.get("target", ""),
			data.get("target_type", "")
		)
		state.emotions = data.get("emotions", {})
		state.dominant_emotion = data.get("dominant_emotion", "")
		state.last_updated = data.get("last_updated", 0.0)
		
		var history_dicts = data.get("change_history", [])
		for dict in history_dicts:
			state.change_history.append(EmotionChange.from_dictionary(dict))
		
		return state

# 存储的情感状态 {agent_id: {target: EmotionState}}
var _emotion_cache: Dictionary = {}

# 获取或创建情感状态
func _get_emotion_state(agent_id: String, target: String, target_type: String) -> EmotionState:
	if not _emotion_cache.has(agent_id):
		_emotion_cache[agent_id] = {}
	
	var agent_emotions = _emotion_cache[agent_id]
	var key = target_type + ":" + target
	
	if not agent_emotions.has(key):
		agent_emotions[key] = EmotionState.new(target, target_type)
	
	return agent_emotions[key]

# 更新情感
func update_emotion(agent_id: String, target: String, target_type: String,
					dimension: String, delta: float, game_time: float,
					trigger: String = "", reason: String = "") -> void:
	
	var timestamp = _format_game_time(game_time)
	var state = _get_emotion_state(agent_id, target, target_type)
	state.update_emotion(dimension, delta, timestamp, trigger, reason)
	
	print("[EmotionMemory] %s 对 %s 的%s %+0.2f" % [agent_id, target, dimension, delta])

# 获取情感状态
func get_emotion_state(agent_id: String, target: String, target_type: String) -> EmotionState:
	return _get_emotion_state(agent_id, target, target_type)

# 获取特定维度的情感值
func get_emotion_value(agent_id: String, target: String, dimension: String) -> float:
	for type in ["AGENT", "LOCATION", "ACTIVITY_TYPE", "EVENT_TYPE"]:
		var key = type + ":" + target
		if _emotion_cache.has(agent_id) and _emotion_cache[agent_id].has(key):
			var state = _emotion_cache[agent_id][key]
			return state.emotions.get(dimension, 0.0)
	return 0.0

# 获取主导情感
func get_dominant_emotion(agent_id: String, target: String) -> String:
	for type in ["AGENT", "LOCATION", "ACTIVITY_TYPE", "EVENT_TYPE"]:
		var key = type + ":" + target
		if _emotion_cache.has(agent_id) and _emotion_cache[agent_id].has(key):
			return _emotion_cache[agent_id][key].dominant_emotion
	return "中立"

# 获取Agent对某个目标的态度描述
func get_attitude_description(agent_id: String, target: String) -> String:
	for type in ["AGENT", "LOCATION", "ACTIVITY_TYPE", "EVENT_TYPE"]:
		var key = type + ":" + target
		if _emotion_cache.has(agent_id) and _emotion_cache[agent_id].has(key):
			return _emotion_cache[agent_id][key].get_emotion_towards()
	return "对%s没有特别的情感" % target

# 获取Agent的所有情感状态
func get_all_emotions(agent_id: String) -> Array[EmotionState]:
	var result: Array[EmotionState] = []
	if _emotion_cache.has(agent_id):
		for key in _emotion_cache[agent_id].keys():
			result.append(_emotion_cache[agent_id][key])
	return result

# 获取Agent对特定类型的所有情感
func get_emotions_by_type(agent_id: String, target_type: String) -> Array[EmotionState]:
	var result: Array[EmotionState] = []
	if _emotion_cache.has(agent_id):
		for key in _emotion_cache[agent_id].keys():
			if key.begins_with(target_type + ":"):
				result.append(_emotion_cache[agent_id][key])
	return result

# 应用情感衰减（定期调用）
func apply_emotion_decay(agent_id: String, decay_rate: float = 0.95) -> void:
	if not _emotion_cache.has(agent_id):
		return
	
	for key in _emotion_cache[agent_id].keys():
		var state = _emotion_cache[agent_id][key]
		for dimension in state.emotions.keys():
			state.emotions[dimension] *= decay_rate
		state._calculate_dominant_emotion()

# 序列化为字典
func serialize() -> Dictionary:
	var data = {}
	for agent_id in _emotion_cache.keys():
		data[agent_id] = {}
		for key in _emotion_cache[agent_id].keys():
			data[agent_id][key] = _emotion_cache[agent_id][key].to_dictionary()
	return data

# 从字典反序列化
func deserialize(data: Dictionary) -> void:
	_emotion_cache.clear()
	for agent_id in data.keys():
		_emotion_cache[agent_id] = {}
		for key in data[agent_id].keys():
			_emotion_cache[agent_id][key] = EmotionState.from_dictionary(data[agent_id][key])

# 清理旧的历史记录
func cleanup_old_history(agent_id: String, max_history: int = 20) -> void:
	if not _emotion_cache.has(agent_id):
		return
	
	for key in _emotion_cache[agent_id].keys():
		var state = _emotion_cache[agent_id][key]
		if state.change_history.size() > max_history:
			# 保留最近的变化记录
			var sorted = state.change_history.duplicate()
			sorted.sort_custom(func(a, b): return a.real_timestamp > b.real_timestamp)
			
			var kept: Array[EmotionChange] = []
			for i in range(min(max_history, sorted.size())):
				kept.append(sorted[i])
			state.change_history = kept

# 辅助函数：格式化游戏时间
func _format_game_time(game_time_minutes: float) -> String:
	var hours = int(game_time_minutes / 60)
	var minutes = int(fmod(game_time_minutes, 60))
	return "%02d:%02d" % [hours, minutes]
