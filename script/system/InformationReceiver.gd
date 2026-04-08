class_name InformationReceiver
extends RefCounted

# ============================================
# InformationReceiver - 信息接收系统
# ============================================
# 处理对话类活动中的信息接收
# 根据专注度过滤信息内容
# ============================================

# 信息记录
class InformationRecord:
	var source_id: String           # 信息来源
	var content: String             # 完整内容
	var received_content: String    # 实际接收到的内容
	var reception_ratio: float      # 接收比例
	var timestamp: float            # 时间戳
	var topic: String               # 话题
	var is_important: bool          # 是否重要信息
	
	func _init(p_source: String, p_content: String, p_ratio: float, p_topic: String = ""):
		source_id = p_source
		content = p_content
		reception_ratio = p_ratio
		topic = p_topic
		timestamp = Time.get_unix_time_from_system()
		is_important = _check_importance(p_content)
		received_content = _filter_content(p_content, p_ratio)
	
	func _check_importance(text: String) -> bool:
		"""检查内容是否包含重要信息"""
		var important_keywords = [
			"考试", "作业", " deadline", "重要", "必须", "一定",
			"明天", "下周", "注意", "提醒", "关键"
		]
		for keyword in important_keywords:
			if keyword in text:
				return true
		return false
	
	func _filter_content(full_content: String, ratio: float) -> String:
		"""根据接收比例过滤内容"""
		if ratio >= 0.95:
			return full_content
		
		if ratio <= 0.05:
			return "..."
		
		# 按比例保留内容
		var words = full_content.split(" ")
		var total_words = words.size()
		var keep_count = max(1, int(total_words * ratio))
		
		# 随机选择保留的词（模拟选择性听到）
		var kept_words = []
		var rng = RandomNumberGenerator.new()
		rng.randomize()
		
		for i in range(total_words):
			if kept_words.size() < keep_count and rng.randf() < ratio:
				kept_words.append(words[i])
		
		# 如果重要信息未被接收，有概率额外获得
		if is_important and ratio >= 0.3:
			if kept_words.size() < total_words:
				kept_words.append("[重要信息已捕获]")
		
		return " ".join(kept_words) if kept_words.size() > 0 else "..."

# ============================================
# 接收器属性
# ============================================
var agent_id: String = ""
var received_information: Array[InformationRecord] = []
var max_memory_count: int = 20  # 最多记忆的信息条数

# ============================================
# 初始化
# ============================================
func _init(p_agent_id: String):
	agent_id = p_agent_id

# ============================================
# 信息接收接口
# ============================================

func receive_dialogue(source_id: String, content: String, focus_level: float, topic: String = "") -> InformationRecord:
	"""
	接收对话信息
	
	参数:
		source_id: 信息来源Agent ID
		content: 完整对话内容
		focus_level: 专注度比例 (0.0-1.0)
		topic: 话题
	
	返回:
		信息记录
	"""
	var record = InformationRecord.new(source_id, content, focus_level, topic)
	received_information.append(record)
	
	# 限制记忆数量
	if received_information.size() > max_memory_count:
		received_information.pop_front()
	
	print("[InformationReceiver] %s 从 %s 接收信息 (专注度:%d%%): %s" % [
		agent_id,
		source_id,
		int(focus_level * 100),
		record.received_content
	])
	
	return record

func receive_lecture(teacher_id: String, content: String, focus_level: float, subject: String = "") -> InformationRecord:
	"""
	接收课堂讲授信息
	
	参数:
		teacher_id: 教师ID
		content: 讲授内容
		focus_level: 专注度比例
		subject: 科目
	
	返回:
		信息记录
	"""
	# 课堂信息接收更依赖专注度
	var adjusted_ratio = focus_level * 0.9  # 课堂信息稍微更难接收
	
	var record = InformationRecord.new(teacher_id, content, adjusted_ratio, subject)
	received_information.append(record)
	
	if received_information.size() > max_memory_count:
		received_information.pop_front()
	
	print("[InformationReceiver] %s 从 %s 听课 (专注度:%d%%): %s" % [
		agent_id,
		teacher_id,
		int(focus_level * 100),
		record.received_content
	])
	
	return record

func receive_discussion(participants: Array[String], content: String, focus_level: float, topic: String = "") -> InformationRecord:
	"""
	接收小组讨论信息
	
	参数:
		participants: 参与者列表
		content: 讨论内容
		focus_level: 专注度比例
		topic: 讨论话题
	
	返回:
		信息记录
	"""
	# 小组讨论信息来源为多个参与者
	var source = "、".join(participants)
	var record = InformationRecord.new(source, content, focus_level, topic)
	received_information.append(record)
	
	if received_information.size() > max_memory_count:
		received_information.pop_front()
	
	print("[InformationReceiver] %s 参与讨论 (专注度:%d%%): %s" % [
		agent_id,
		int(focus_level * 100),
		record.received_content
	])
	
	return record

# ============================================
# 信息查询
# ============================================

func get_recent_information(count: int = 5) -> Array[InformationRecord]:
	"""获取最近接收的信息"""
	var result: Array[InformationRecord] = []
	var start_idx = max(0, received_information.size() - count)
	
	for i in range(start_idx, received_information.size()):
		result.append(received_information[i])
	
	return result

func get_information_from_source(source_id: String, count: int = 10) -> Array[InformationRecord]:
	"""获取来自特定来源的信息"""
	var result: Array[InformationRecord] = []
	
	for record in received_information:
		if source_id in record.source_id:
			result.append(record)
			if result.size() >= count:
				break
	
	return result

func get_information_by_topic(topic: String, count: int = 10) -> Array[InformationRecord]:
	"""获取特定话题的信息"""
	var result: Array[InformationRecord] = []
	
	for record in received_information:
		if topic in record.topic:
			result.append(record)
			if result.size() >= count:
				break
	
	return result

func get_missed_important_info() -> Array[InformationRecord]:
	"""获取遗漏的重要信息"""
	var result: Array[InformationRecord] = []
	
	for record in received_information:
		if record.is_important and record.reception_ratio < 0.5:
			result.append(record)
	
	return result

# ============================================
# 记忆管理
# ============================================

func clear_old_information(older_than_seconds: float = 3600) -> int:
	"""清理旧信息"""
	var current_time = Time.get_unix_time_from_system()
	var removed_count = 0
	var new_list: Array[InformationRecord] = []
	
	for record in received_information:
		if current_time - record.timestamp < older_than_seconds:
			new_list.append(record)
		else:
			removed_count += 1
	
	received_information = new_list
	return removed_count

func clear_all() -> void:
	"""清空所有信息"""
	received_information.clear()

# ============================================
# 统计信息
# ============================================

func get_reception_statistics() -> Dictionary:
	"""获取接收统计"""
	if received_information.is_empty():
		return {
			"total_count": 0,
			"average_reception_ratio": 0.0,
			"important_missed": 0
		}
	
	var total_ratio = 0.0
	var important_missed = 0
	
	for record in received_information:
		total_ratio += record.reception_ratio
		if record.is_important and record.reception_ratio < 0.5:
			important_missed += 1
	
	return {
		"total_count": received_information.size(),
		"average_reception_ratio": total_ratio / received_information.size(),
		"important_missed": important_missed
	}

# ============================================
# 格式化输出（用于Prompt）
# ============================================

func format_for_prompt(count: int = 5) -> String:
	"""格式化为Prompt可用的字符串"""
	if received_information.is_empty():
		return "最近没有接收到重要信息。"
	
	var lines = ["最近接收到的信息："]
	var recent = get_recent_information(count)
	
	for record in recent:
		var status = "【重要】" if record.is_important else ""
		var reception = "(听到%d%%)" % int(record.reception_ratio * 100)
		lines.append("- 来自%s: %s %s %s" % [record.source_id, record.received_content, reception, status])
	
	return "\n".join(lines)

func format_missed_important() -> String:
	"""格式化遗漏的重要信息"""
	var missed = get_missed_important_info()
	
	if missed.is_empty():
		return ""
	
	var lines = ["你可能遗漏了以下重要信息："]
	for record in missed:
		lines.append("- 来自%s关于'%s': %s" % [record.source_id, record.topic, record.content])
	
	return "\n".join(lines)
