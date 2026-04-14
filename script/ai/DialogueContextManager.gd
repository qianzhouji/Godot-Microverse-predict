extends Node
class_name DialogueContextManager

# ============================================
# DialogueContextManager - 对话上下文管理器
# ============================================
# 管理多Agent对话的上下文同步
# 确保所有参与者看到一致的对话历史
# 支持对话摘要和关键信息提取
# ============================================

# 对话上下文数据类
class DialogueContext:
	var dialogue_id: String
	var participants: Array[String] = []           # 参与者名称列表
	var message_history: Array[Dictionary] = []    # 完整消息历史
	var summary: String = ""                        # 对话摘要
	var key_points: Array[String] = []             # 关键信息点
	var topic: String = ""                          # 当前主题
	var emotional_tone: float = 0.0                 # 整体情感基调 (-1到1)
	var last_update_time: float = 0.0
	
	func _init(p_id: String):
		dialogue_id = p_id
		last_update_time = Time.get_unix_time_from_system()
	
	func add_message(speaker: String, content: String, msg_type: String = "normal"):
		"""添加消息到历史"""
		var message = {
			"speaker": speaker,
			"content": content,
			"type": msg_type,
			"timestamp": Time.get_unix_time_from_system(),
			"index": message_history.size()
		}
		message_history.append(message)
		last_update_time = Time.get_unix_time_from_system()
		
		# 更新情感基调
		_update_emotional_tone(content)
	
	func _update_emotional_tone(content: String):
		"""更新情感基调"""
		var sentiment = _analyze_sentiment(content)
		emotional_tone = emotional_tone * 0.8 + sentiment * 0.2
	
	func _analyze_sentiment(text: String) -> float:
		"""简化版情感分析"""
		var positive_words = ["好", "棒", "开心", "喜欢", "谢谢", "不错", "很好", "太好了", "哈哈", "愉快"]
		var negative_words = ["不好", "讨厌", "烦", "累", "难过", "抱歉", "对不起", "糟", "差", "生气"]
		
		var score = 0.0
		var count = 0
		
		for word in positive_words:
			if text.find(word) != -1:
				score += 0.3
				count += 1
		
		for word in negative_words:
			if text.find(word) != -1:
				score -= 0.3
				count += 1
		
		if count == 0:
			return 0.0
		return clamp(score, -1.0, 1.0)
	
	func get_recent_context(message_count: int = 5) -> Array:
		"""获取最近的对话上下文"""
		var start_idx = max(0, message_history.size() - message_count)
		return message_history.slice(start_idx)
	
	func get_formatted_context(max_messages: int = 10) -> String:
		"""获取格式化的对话上下文用于Prompt"""
		var result = ""
		var start_idx = max(0, message_history.size() - max_messages)
		
		for i in range(start_idx, message_history.size()):
			var msg = message_history[i]
			if msg.type == "system":
				result += "[%s]\n" % msg.content
			else:
				result += "%s: %s\n" % [msg.speaker, msg.content]
		
		return result.strip_edges()
	
	func extract_key_points() -> Array[String]:
		"""提取关键信息点"""
		# 简化版：提取包含重要关键词的消息
		var important_keywords = ["决定", "计划", "约定", "重要", "必须", "记得", "别忘了"]
		var points = []
		
		for msg in message_history:
			for keyword in important_keywords:
				if msg.content.find(keyword) != -1:
					points.append("%s提到：%s" % [msg.speaker, msg.content])
					break
		
		key_points = points
		return points
	
	func generate_summary() -> String:
		"""生成对话摘要"""
		if message_history.is_empty():
			return "暂无对话内容"
		
		var speaker_set = {}
		var topics = []
		
		for msg in message_history:
			speaker_set[msg.speaker] = true
		
		var speakers = speaker_set.keys()
		summary = "一场有%s参与的对话，共%d条消息" % [", ".join(speakers), message_history.size()]
		
		if emotional_tone > 0.3:
			summary += "，氛围愉快"
		elif emotional_tone < -0.3:
			summary += "，氛围有些沉重"
		else:
			summary += "，氛围平和"
		
		return summary

# 对话上下文存储 {dialogue_id: DialogueContext}
var dialogue_contexts: Dictionary = {}

# 配置参数
const MAX_CONTEXT_MESSAGES: int = 50           # 最大保留消息数
const CONTEXT_SYNC_INTERVAL: float = 1.0       # 上下文同步间隔（秒）

# 信号
signal context_updated(dialogue_id: String, message_count: int)
signal summary_generated(dialogue_id: String, summary: String)
signal key_points_extracted(dialogue_id: String, points: Array)

func _ready():
	print("[DialogueContextManager] 对话上下文管理器已初始化")
	_setup_sync_timer()

func _setup_sync_timer():
	"""设置同步定时器"""
	var timer = Timer.new()
	timer.wait_time = CONTEXT_SYNC_INTERVAL
	timer.timeout.connect(_on_sync_timer_timeout)
	add_child(timer)
	timer.start()

func _on_sync_timer_timeout():
	"""定期同步上下文"""
	_sync_all_contexts()

# ============================================
# 上下文管理
# ============================================

func create_context(dialogue_id: String, participants: Array[String]) -> DialogueContext:
	"""创建新的对话上下文"""
	var context = DialogueContext.new(dialogue_id)
	context.participants = participants.duplicate()
	dialogue_contexts[dialogue_id] = context
	print("[DialogueContextManager] 创建上下文：%s (参与者: %s)" % [dialogue_id, ", ".join(participants)])
	return context

func get_context(dialogue_id: String) -> DialogueContext:
	"""获取对话上下文"""
	return dialogue_contexts.get(dialogue_id)

func add_message(dialogue_id: String, speaker: String, content: String, msg_type: String = "normal"):
	"""添加消息到上下文"""
	var context = dialogue_contexts.get(dialogue_id)
	if not context:
		return
	
	context.add_message(speaker, content, msg_type)
	
	# 限制消息数量
	if context.message_history.size() > MAX_CONTEXT_MESSAGES:
		context.message_history.pop_front()
	
	context_updated.emit(dialogue_id, context.message_history.size())
	
	# 定期生成摘要
	if context.message_history.size() % 10 == 0:
		var summary = context.generate_summary()
		summary_generated.emit(dialogue_id, summary)

func add_system_message(dialogue_id: String, content: String):
	"""添加系统消息"""
	add_message(dialogue_id, "系统", content, "system")

func remove_context(dialogue_id: String):
	"""移除对话上下文"""
	if dialogue_contexts.has(dialogue_id):
		# 生成最终摘要
		var context = dialogue_contexts[dialogue_id]
		var final_summary = context.generate_summary()
		var key_points = context.extract_key_points()
		
		print("[DialogueContextManager] 移除上下文：%s" % dialogue_id)
		print("  最终摘要：%s" % final_summary)
		print("  关键信息：%s" % ", ".join(key_points))
		
		dialogue_contexts.erase(dialogue_id)

# ============================================
# 上下文同步
# ============================================

func _sync_all_contexts():
	"""同步所有活跃对话的上下文"""
	# 从DialogService获取活跃对话
	var dialog_service = _get_dialog_service()
	if not dialog_service:
		return
	
	for dialogue_id in dialog_service.active_conversations:
		var conversation = dialog_service.active_conversations[dialogue_id]
		_sync_conversation_context(dialogue_id, conversation)

func _sync_conversation_context(dialogue_id: String, conversation):
	"""同步单个对话的上下文"""
	# 确保上下文存在
	if not dialogue_contexts.has(dialogue_id):
		var participants = [conversation.speaker.name, conversation.listener.name]
		create_context(dialogue_id, participants)

func sync_with_group_dialogue(dialogue_id: String):
	"""同步群组对话上下文"""
	var group_manager = get_node_or_null("/root/GroupDialogueManager")
	if not group_manager:
		return
	
	var group_data = group_manager.get_group_dialogue_data(dialogue_id)
	if not group_data:
		return
	
	# 确保上下文存在
	if not dialogue_contexts.has(dialogue_id):
		var participant_names = []
		for p in group_data.participants:
			participant_names.append(p.name)
		create_context(dialogue_id, participant_names)
	
	# 同步消息历史
	var context = dialogue_contexts[dialogue_id]
	for msg in group_data.message_history:
		if not _message_exists_in_context(context, msg):
			context.add_message(msg.speaker, msg.content)

func _message_exists_in_context(context: DialogueContext, msg: Dictionary) -> bool:
	"""检查消息是否已存在于上下文中"""
	for existing in context.message_history:
		if existing.speaker == msg.speaker and existing.content == msg.content:
			return true
	return false

# ============================================
# 上下文查询与格式化
# ============================================

func get_context_for_prompt(dialogue_id: String, 
							requester_name: String,
							max_messages: int = 8) -> String:
	"""
	获取用于Prompt的对话上下文
	
	参数:
		dialogue_id: 对话ID
		requester_name: 请求者名称（用于个性化上下文）
		max_messages: 最大消息数
	
	返回:
		格式化的上下文字符串
	"""
	var context = dialogue_contexts.get(dialogue_id)
	if not context:
		return ""
	
	var result = ""
	
	# 添加主题信息
	if not context.topic.is_empty():
		result += "讨论主题：%s\n" % context.topic
	
	# 添加参与者信息
	result += "参与者：%s\n" % ", ".join(context.participants)
	
	# 添加情感基调
	if context.emotional_tone > 0.3:
		result += "氛围：愉快\n"
	elif context.emotional_tone < -0.3:
		result += "氛围：沉重\n"
	
	result += "\n对话历史：\n"
	result += context.get_formatted_context(max_messages)
	
	return result

func get_context_for_memory(dialogue_id: String) -> Dictionary:
	"""获取用于记忆存储的上下文摘要"""
	var context = dialogue_contexts.get(dialogue_id)
	if not context:
		return {}
	
	return {
		"dialogue_id": dialogue_id,
		"participants": context.participants,
		"message_count": context.message_history.size(),
		"summary": context.generate_summary(),
		"key_points": context.extract_key_points(),
		"emotional_tone": context.emotional_tone,
		"duration": Time.get_unix_time_from_system() - context.message_history[0].timestamp if not context.message_history.is_empty() else 0
	}

func get_shared_context(dialogue_ids: Array) -> String:
	"""获取多个对话的共享上下文（用于跨对话关联）"""
	if dialogue_ids.is_empty():
		return ""
	
	var all_participants = {}
	var all_topics = []
	var total_messages = 0
	
	for dialogue_id in dialogue_ids:
		var context = dialogue_contexts.get(dialogue_id)
		if context:
			for p in context.participants:
				all_participants[p] = true
			if not context.topic.is_empty():
				all_topics.append(context.topic)
			total_messages += context.message_history.size()
	
	var result = "相关对话汇总：\n"
	result += "涉及人员：%s\n" % ", ".join(all_participants.keys())
	if not all_topics.is_empty():
		result += "讨论主题：%s\n" % ", ".join(all_topics)
	result += "总消息数：%d\n" % total_messages
	
	return result

# ============================================
# 上下文分析与提取
# ============================================

func extract_common_topics(dialogue_id: String) -> Array[String]:
	"""提取对话中的共同话题"""
	var context = dialogue_contexts.get(dialogue_id)
	if not context:
		return []
	
	# 简化版：基于关键词提取
	var topic_keywords = {
		"学习": ["作业", "考试", "成绩", "课程", "老师"],
		"活动": ["体育", "游戏", "比赛", "活动", "社团"],
		"社交": ["朋友", "同学", "关系", "聚会", "聊天"],
		"日常": ["吃饭", "休息", "天气", "时间", "计划"]
	}
	
	var topic_scores = {}
	for topic in topic_keywords.keys():
		topic_scores[topic] = 0
	
	for msg in context.message_history:
		for topic in topic_keywords.keys():
			for keyword in topic_keywords[topic]:
				if msg.content.find(keyword) != -1:
					topic_scores[topic] += 1
	
	# 返回得分最高的话题
	var sorted_topics = topic_scores.keys()
	sorted_topics.sort_custom(func(a, b): return topic_scores[a] > topic_scores[b])
	
	var result = []
	for topic in sorted_topics:
		if topic_scores[topic] > 0:
			result.append(topic)
	
	return result

func find_related_dialogues(character_name: String, time_window: float = 3600.0) -> Array:
	"""查找角色相关的对话（用于关联记忆）"""
	var related = []
	var current_time = Time.get_unix_time_from_system()
	
	for dialogue_id in dialogue_contexts:
		var context = dialogue_contexts[dialogue_id]
		
		# 检查角色是否参与
		if not context.participants.has(character_name):
			continue
		
		# 检查时间窗口
		if current_time - context.last_update_time > time_window:
			continue
		
		related.append({
			"dialogue_id": dialogue_id,
			"participants": context.participants,
			"summary": context.generate_summary(),
			"message_count": context.message_history.size()
		})
	
	return related

# ============================================
# 辅助函数
# ============================================

func _get_dialog_service() -> DialogService:
	"""获取对话服务"""
	var dialog_manager = get_node_or_null("/root/DialogManager")
	if dialog_manager:
		return dialog_manager.dialog_service
	return null

func cleanup_old_contexts(max_age_seconds: float = 7200.0):
	"""清理过旧的上下文"""
	var current_time = Time.get_unix_time_from_system()
	var to_remove = []
	
	for dialogue_id in dialogue_contexts:
		var context = dialogue_contexts[dialogue_id]
		if current_time - context.last_update_time > max_age_seconds:
			to_remove.append(dialogue_id)
	
	for dialogue_id in to_remove:
		remove_context(dialogue_id)
	
	if to_remove.size() > 0:
		print("[DialogueContextManager] 清理了%d个过期上下文" % to_remove.size())
