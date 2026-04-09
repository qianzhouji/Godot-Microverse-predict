class_name MemoryFormatter
extends RefCounted

# ============================================
# MemoryFormatter - 记忆格式化工具
# ============================================
# 负责将记忆数据格式化为可读的文本格式
# 用于UI显示和AI Prompt构建
# ============================================

# 格式化记忆用于显示（单条记忆）
# 被 GodUI.gd:232 直接调用，必须保持兼容
static func format_memory_for_display(memory: Dictionary) -> String:
	var content = memory.get("content", "")
	var timestamp = memory.get("timestamp", "")
	if not timestamp or str(timestamp).strip_edges().is_empty():
		return content
	else:
		return "[%s] %s" % [timestamp, content]

# 获取记忆的重要性
static func get_memory_importance(memory: Dictionary) -> int:
	return memory.get("importance", 3)  # 默认 NORMAL = 3

# 获取记忆的时间戳（Unix时间）
static func get_memory_timestamp(memory: Dictionary) -> float:
	return memory.get("created_at", 0.0)

# 格式化游戏时间戳为可读字符串
static func format_game_timestamp(game_time_minutes: float) -> String:
	var hours = int(game_time_minutes / 60)
	var minutes = int(fmod(game_time_minutes, 60))
	return "%02d:%02d" % [hours, minutes]

# 构建事件记忆的显示文本
static func format_event_memory(event_data: Dictionary) -> String:
	var time_str = event_data.get("timestamp", "")
	var event_type = event_data.get("event_type", "")
	var location = event_data.get("location", "")
	var details = event_data.get("details", {})
	
	var text = "[%s] " % time_str
	
	match event_type:
		"MOVE_TO":
			var from_loc = details.get("from", "")
			var to_loc = details.get("to", "")
			text += "从%s移动到%s" % [from_loc, to_loc]
		"DIALOGUE":
			var participants = details.get("participants", [])
			var topic = details.get("topic", "")
			if participants.size() >= 2:
				text += "与%s讨论%s" % [participants[1], topic]
		"CLASS":
			var subject = details.get("subject", "")
			text += "上了%s课" % subject
		"SELF_STUDY":
			var subject = details.get("subject", "")
			text += "在%s自习%s" % [location, subject]
		"SPORTS":
			var sport_type = details.get("sport_type", "")
			text += "在%s进行%s" % [location, sport_type]
		_:
			text += "在%s进行%s" % [location, event_type]
	
	return text

# 构建社交记忆的显示文本
static func format_social_memory(social_data: Dictionary) -> String:
	var with_agent = social_data.get("with_agent", "")
	var total = social_data.get("total_interactions", 0)
	var score = social_data.get("relationship_score", 0.0)
	
	var relationship_desc = "中立"
	if score > 0.5:
		relationship_desc = "友好"
	elif score > 0.2:
		relationship_desc = "熟悉"
	elif score < -0.5:
		relationship_desc = "敌对"
	elif score < -0.2:
		relationship_desc = "疏远"
	
	return "与%s的关系：%s（互动%d次）" % [with_agent, relationship_desc, total]

# 构建情感记忆的显示文本
static func format_emotion_memory(emotion_data: Dictionary) -> String:
	var target = emotion_data.get("target", "")
	var emotions = emotion_data.get("emotions", {})
	var dominant = emotion_data.get("dominant_emotion", "")
	
	if dominant.is_empty():
		return "对%s没有特别的情感" % target
	
	var strength = emotions.get(dominant, 0.0)
	var strength_desc = ""
	if strength > 0.7:
		strength_desc = "强烈的"
	elif strength > 0.4:
		strength_desc = "一定的"
	else:
		strength_desc = "轻微的"
	
	return "对%s有%s%s" % [target, strength_desc, dominant]

# 综合格式化：将多种记忆合并为Prompt文本
static func build_memory_prompt_text(event_memories: Array, social_memories: Array, emotion_memories: Array, max_count: int = 5) -> String:
	var prompt_text = "\n\n记忆信息："
	var total_count = 0
	
	# 优先添加事件记忆
	for memory in event_memories:
		if total_count >= max_count:
			break
		var text = format_event_memory(memory)
		prompt_text += "\n- " + text
		total_count += 1
	
	# 添加社交记忆
	for memory in social_memories:
		if total_count >= max_count:
			break
		var text = format_social_memory(memory)
		prompt_text += "\n- " + text
		total_count += 1
	
	# 添加情感记忆
	for memory in emotion_memories:
		if total_count >= max_count:
			break
		var text = format_emotion_memory(memory)
		prompt_text += "\n- " + text
		total_count += 1
	
	if total_count == 0:
		prompt_text += "\n- 暂无重要记忆"
	
	return prompt_text
