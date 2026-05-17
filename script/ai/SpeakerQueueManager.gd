extends Node
class_name SpeakerQueueManager

# ============================================
# SpeakerQueueManager - 发言队列管理器
# ============================================
# 基于优先级的智能发言队列管理
# 考虑性格、话题相关性、发言历史等因素
# ============================================

# 发言者状态数据
class SpeakerState:
	var character: CharacterBody2D
	var base_priority: float = 50.0           # 基础优先级 (0-100)
	var current_priority: float = 50.0        # 当前优先级
	var last_speak_turn: int = -1             # 上次发言轮次 (-1表示未发言)
	var consecutive_speaks: int = 0           # 连续发言次数
	var silence_turns: int = 0                # 沉默轮次
	var topic_relevance: float = 0.5          # 话题相关度 (0-1)
	var willingness: float = 0.5              # 发言意愿 (0-1)
	var was_interrupted: bool = false         # 是否被打断过
	
	# 动态调整因子
	const CONSECUTIVE_PENALTY: float = -20.0   # 连续发言惩罚
	const SILENCE_BONUS: float = 5.0           # 沉默奖励
	const MAX_SILENCE_BONUS: float = 15.0      # 最大沉默奖励
	const INTERRUPT_BOOST: float = 10.0        # 被打断后补偿
	
	func _init(p_character: CharacterBody2D):
		character = p_character
		_calculate_base_priority()
	
	func _calculate_base_priority():
		"""根据角色性格计算基础优先级"""
		var personality = CharacterPersonality.get_personality(character.name)
		
		# 基础值
		base_priority = 50.0
		
		# 根据大五人格调整
		var big_five = personality.get("big_five", {})
		var extraversion = big_five.get("extraversion", 50)
		var agreeableness = big_five.get("agreeableness", 50)
		
		# 外向性影响发言积极性 (±20)
		base_priority += (extraversion - 50) * 0.4
		
		# 宜人性影响是否让给别人发言机会 (±10)
		base_priority -= (agreeableness - 50) * 0.2
		
		# 根据沟通风格调整
		var communication_style = personality.get("communication_style", "")
		match communication_style:
			"主动型", "主导型":
				base_priority += 15
			"被动型", "倾听型":
				base_priority -= 15
			"平衡型":
				base_priority += 0
		
		# 根据依恋风格调整
		var attachment = personality.get("attachment_style", "")
		if attachment.find("回避") != -1:
			base_priority -= 10
		elif attachment.find("焦虑") != -1:
			base_priority += 10
		
		base_priority = clamp(base_priority, 10.0, 90.0)
		current_priority = base_priority
	
	func update_priority(current_turn: int, topic: String, last_message: String):
		"""更新当前优先级"""
		
		# 1. 基础优先级
		current_priority = base_priority
		
		# 2. 连续发言惩罚
		if last_speak_turn == current_turn - 1:
			consecutive_speaks += 1
			current_priority += CONSECUTIVE_PENALTY * consecutive_speaks
		else:
			consecutive_speaks = 0
		
		# 3. 沉默奖励
		if last_speak_turn >= 0:
			silence_turns = current_turn - last_speak_turn - 1
			var silence_bonus = min(silence_turns * SILENCE_BONUS, MAX_SILENCE_BONUS)
			current_priority += silence_bonus
		
		# 4. 被打断补偿
		if was_interrupted:
			current_priority += INTERRUPT_BOOST
			was_interrupted = false
		
		# 5. 话题相关度计算
		topic_relevance = _calculate_topic_relevance(topic, last_message)
		current_priority += topic_relevance * 20  # 相关度贡献±20
		
		# 6. 发言意愿计算
		willingness = _calculate_willingness()
		current_priority += (willingness - 0.5) * 20  # 意愿贡献±10
		
		# 确保在合理范围内
		current_priority = clamp(current_priority, 0.0, 100.0)
	
	func _calculate_topic_relevance(topic: String, last_message: String) -> float:
		"""计算话题相关度"""
		if topic.is_empty() or last_message.is_empty():
			return 0.5
		
		var relevance = 0.5
		
		# 获取角色人设
		var personality = CharacterPersonality.get_personality(character.name)
		var position = personality.get("position", "")
		
		# 根据角色身份判断话题相关性
		var topic_keywords = {
			"学习": ["作业", "考试", "成绩", "课程", "老师", "学习", "作业"],
			"体育": ["运动", "比赛", "体育", "跑步", "篮球", "足球"],
			"社交": ["朋友", "同学", "关系", "聚会", "聊天", "活动"],
			"日常": ["吃饭", "休息", "天气", "时间", "计划", "今天"]
		}
		
		# 检查话题匹配
		for category in topic_keywords.keys():
			var keywords = topic_keywords[category]
			for keyword in keywords:
				if topic.find(keyword) != -1 or last_message.find(keyword) != -1:
					# 教师更关注学习话题
					if position.find("老师") != -1 or position.find("教师") != -1:
						if category == "学习":
							relevance += 0.2
					# 学生更关注社交和日常
					else:
						if category in ["社交", "日常"]:
							relevance += 0.1
					break
		
		# 检查是否被直接提及
		if last_message.find(character.name) != -1:
			relevance += 0.3
		
		return clamp(relevance, 0.0, 1.0)
	
	func _calculate_willingness() -> float:
		"""计算发言意愿"""
		var willingness = 0.5
		
		# 从角色元数据获取当前状态
		var mood = character.get_meta("mood", "普通")
		var health = character.get_meta("health", "良好")
		
		# 心情影响
		match mood:
			"开心", "愉快", "兴奋":
				willingness += 0.2
			"普通", "平静":
				willingness += 0.0
			"难过", "沮丧", "疲惫":
				willingness -= 0.3
			"生气", "烦躁":
				willingness += 0.1  # 可能想抱怨
		
		# 健康状态影响
		match health:
			"良好", "健康":
				willingness += 0.1
			"一般":
				willingness += 0.0
			"疲惫", "不适", "生病":
				willingness -= 0.2
		
		# 动态人格特质影响
		var dynamic_traits = character.get_meta("dynamic_traits", {})
		var motivation = dynamic_traits.get("motivation_level", 50)
		willingness += (motivation - 50) / 200.0  # ±0.25
		
		return clamp(willingness, 0.0, 1.0)
	
	func on_speak(turn: int):
		"""记录发言"""
		last_speak_turn = turn
		silence_turns = 0
	
	func on_interrupted():
		"""记录被打断"""
		was_interrupted = true
	
	func get_debug_info() -> String:
		"""获取调试信息"""
		return "%s: 基础=%.1f 当前=%.1f 连续=%d 沉默=%d 相关=%.2f 意愿=%.2f" % [
			character.name, base_priority, current_priority, 
			consecutive_speaks, silence_turns, topic_relevance, willingness
		]

# ============================================
# 发言队列管理器
# ============================================

# 发言者状态映射 {character: SpeakerState}
var speaker_states: Dictionary = {}

# 当前轮次
var current_turn: int = 0

# 当前对话ID
var current_dialogue_id: String = ""

# 当前话题
var current_topic: String = ""

# 上次发言内容
var last_message: String = ""

# 上次发言者
var last_speaker: CharacterBody2D = null

# 配置参数
const MIN_SPEAK_INTERVAL: float = 2.0       # 最小发言间隔（秒）
const MAX_SPEAK_INTERVAL: float = 8.0       # 最大发言间隔（秒）
const INTERRUPT_THRESHOLD: float = 80.0     # 打断阈值（优先级>=此值可打断）

# 信号
signal speaker_selected(character: CharacterBody2D, priority: float)
signal queue_updated(speaker_list: Array)
signal turn_advanced(turn: int, next_speaker: String)

func _ready():
	print("[SpeakerQueueManager] 发言队列管理器已初始化")

# ============================================
# 队列初始化与管理
# ============================================

func initialize_queue(participants: Array[CharacterBody2D], dialogue_id: String, topic: String = ""):
	"""初始化发言队列"""
	speaker_states.clear()
	current_turn = 0
	current_dialogue_id = dialogue_id
	current_topic = topic
	last_message = ""
	last_speaker = null
	
	for participant in participants:
		var state = SpeakerState.new(participant)
		speaker_states[participant] = state
	
	print("[SpeakerQueueManager] 队列初始化完成，参与者: %d人" % participants.size())
	_log_queue_status()

func add_participant(character: CharacterBody2D):
	"""添加新参与者"""
	if not speaker_states.has(character):
		var state = SpeakerState.new(character)
		# 新加入者获得一定优先级补偿
		state.current_priority += 10
		speaker_states[character] = state
		print("[SpeakerQueueManager] 添加参与者: %s" % character.name)

func remove_participant(character: CharacterBody2D):
	"""移除参与者"""
	if speaker_states.has(character):
		speaker_states.erase(character)
		print("[SpeakerQueueManager] 移除参与者: %s" % character.name)

func end_queue():
	"""结束队列"""
	speaker_states.clear()
	current_turn = 0
	current_dialogue_id = ""
	print("[SpeakerQueueManager] 队列已结束")

# ============================================
# 核心选择逻辑
# ============================================

func select_next_speaker() -> CharacterBody2D:
	"""选择下一位发言者"""
	if speaker_states.is_empty():
		return null
	
	# 更新所有发言者的优先级
	_update_all_priorities()
	
	# 按优先级排序
	var sorted_speakers = _get_sorted_speakers()
	
	# 选择优先级最高的
	var selected = sorted_speakers[0].character
	var selected_priority = sorted_speakers[0].current_priority
	
	# 记录发言
	sorted_speakers[0].on_speak(current_turn)
	last_speaker = selected
	
	# 增加轮次
	current_turn += 1
	
	print("[SpeakerQueueManager] 选择发言者: %s (优先级: %.1f, 轮次: %d)" % [
		selected.name, selected_priority, current_turn
	])
	
	speaker_selected.emit(selected, selected_priority)
	turn_advanced.emit(current_turn, selected.name)
	
	_log_queue_status()
	
	return selected

func try_interrupt(character: CharacterBody2D) -> bool:
	"""尝试打断当前发言"""
	if not speaker_states.has(character):
		return false
	
	var state = speaker_states[character]
	state.update_priority(current_turn, current_topic, last_message)
	
	# 检查是否达到打断阈值
	if state.current_priority >= INTERRUPT_THRESHOLD:
		print("[SpeakerQueueManager] %s 打断成功 (优先级: %.1f)" % [
			character.name, state.current_priority
		])
		return true
	
	return false

func get_speak_delay(character: CharacterBody2D) -> float:
	"""获取发言延迟（模拟自然对话节奏）"""
	if not speaker_states.has(character):
		return MIN_SPEAK_INTERVAL
	
	var state = speaker_states[character]
	
	# 基础延迟
	var delay = MIN_SPEAK_INTERVAL
	
	# 根据性格调整
	var personality = CharacterPersonality.get_personality(character.name)
	var big_five = personality.get("big_five", {})
	var extraversion = big_five.get("extraversion", 50)
	
	# 外向者反应更快
	var reaction_speed = (extraversion - 50) / 100.0  # -0.5 to 0.5
	delay -= reaction_speed * 2.0
	
	# 根据话题相关度调整（相关度高时反应更快）
	delay -= state.topic_relevance * 1.5
	
	# 根据发言意愿调整
	delay -= state.willingness * 1.0
	
	# 添加随机因素
	delay += randf_range(-0.5, 1.0)
	
	return clamp(delay, MIN_SPEAK_INTERVAL, MAX_SPEAK_INTERVAL)

# ============================================
# 优先级更新与排序
# ============================================

func _update_all_priorities():
	"""更新所有发言者的优先级"""
	for character in speaker_states.keys():
		var state = speaker_states[character]
		state.update_priority(current_turn, current_topic, last_message)

func _get_sorted_speakers() -> Array:
	"""获取按优先级排序的发言者列表"""
	var speakers = speaker_states.values()
	
	# 按当前优先级降序排序
	speakers.sort_custom(func(a, b): return a.current_priority > b.current_priority)
	
	return speakers

func update_topic(new_topic: String):
	"""更新当前话题"""
	current_topic = new_topic
	print("[SpeakerQueueManager] 话题更新: %s" % new_topic)

func record_message(speaker: CharacterBody2D, message: String):
	"""记录发言内容"""
	last_message = message

# ============================================
# 查询接口
# ============================================

func get_speaker_priority(character: CharacterBody2D) -> float:
	"""获取指定发言者的当前优先级"""
	if speaker_states.has(character):
		return speaker_states[character].current_priority
	return 0.0

func get_queue_status() -> Dictionary:
	"""获取队列状态"""
	var status = {
		"current_turn": current_turn,
		"participant_count": speaker_states.size(),
		"speakers": []
	}
	
	var sorted = _get_sorted_speakers()
	for state in sorted:
		status.speakers.append({
			"name": state.character.name,
			"priority": state.current_priority,
			"base_priority": state.base_priority,
			"last_speak_turn": state.last_speak_turn,
			"silence_turns": state.silence_turns,
			"consecutive_speaks": state.consecutive_speaks
		})
	
	return status

func get_silence_count() -> int:
	"""获取沉默轮次（距离上次发言最久的角色）"""
	var max_silence = 0
	for state in speaker_states.values():
		if state.silence_turns > max_silence:
			max_silence = state.silence_turns
	return max_silence

# ============================================
# 调试与日志
# ============================================

func _log_queue_status():
	"""记录队列状态"""
	print("[SpeakerQueueManager] ===== 队列状态 (轮次: %d) =====" % current_turn)
	var sorted = _get_sorted_speakers()
	for i in range(sorted.size()):
		var state = sorted[i]
		print("  [%d] %s" % [i + 1, state.get_debug_info()])
	print("[SpeakerQueueManager] ===== 状态结束 =====")

func print_queue_status():
	"""打印队列状态（供外部调用）"""
	_log_queue_status()
