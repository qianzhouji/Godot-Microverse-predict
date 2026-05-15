extends Node
# 注意：此脚本配置为AutoLoad，不使用class_name
# 通过DialogueManager单例访问

# ============================================
# DialogueManager - 统一对话管理器
# ============================================
# 支持大/中/小三个范围的广播式对话系统
# - 小范围(WHISPER): 悄悄话，同一中范围，最多3人
# - 中范围(NORMAL): 普通对话，同一中范围，最多7人
# - 大范围(BROADCAST): 教师上课，整个教室，无人数上限
#
# 核心特性:
# - 所有对话均为广播式，同范围内所有角色可见
# - 行为可见性: 同一子场景内所有对话行为可见
# - 悄悄话行为: 范围外角色50%概率感知到
# - 内容可见性: 只有同一范围内角色可见内容
# - 移动后内容: 从进入范围后的那次Click开始记录
# ============================================

# 对话范围枚举
enum RangeType {
	WHISPER,      # 悄悄话 - 以角色为中心，30px半径，最多3人
	NORMAL,       # 普通对话 - 以发起者所在中范围为边界，最多7人
	BROADCAST     # 广播 - 以发起者所在子场景(RoomArea)为边界，无人数上限
}

# 对话结束原因
enum EndReason {
	SILENCE,      # 全员沉默
	TIMEOUT,      # 超时(45分钟)
	MANUAL,       # 手动结束
	EMPTY         # 人数不足
}

# 对话数据类
class DialogueData:
	var dialogue_id: String
	var range_type: int           # RangeType
	var room_name: String         # 所在房间
	var medium_range_id: String   # 中范围标识 (Q1/Q2/Q3/Q4/LEFT/RIGHT/CENTER)
	var topic: String             # 讨论主题

	# 参与者管理 {character: joined_at_click}
	var participants: Dictionary = {}
	var initiator: CharacterBody2D = null

	# 消息历史 [{speaker, content, click_index}]
	var message_history: Array[Dictionary] = []

	# 时间记录
	var start_click: int = 0
	var start_time: float = 0.0      # 游戏时间
	var last_message_click: int = 0
	var last_message_time: float = 0.0

	# 发言管理
	var speaker_queue: SpeakerQueueManager = null
	var current_speaker: CharacterBody2D = null
	var silence_rounds: int = 0      # 连续沉默轮次

	# 教师选择标记（大范围对话）
	var teacher_selected_speaker: String = ""  # 教师指定的下一个发言者

	func _init(p_id: String, p_initiator: CharacterBody2D, p_range: int,
			   p_room: String, p_medium_range: String, p_start_click: int, p_start_time: float):
		dialogue_id = p_id
		initiator = p_initiator
		range_type = p_range
		room_name = p_room
		medium_range_id = p_medium_range
		start_click = p_start_click
		start_time = p_start_time
		last_message_click = p_start_click
		last_message_time = p_start_time

		# 创建发言队列管理器
		speaker_queue = SpeakerQueueManager.new()

	func get_range_name() -> String:
		match range_type:
			RangeType.WHISPER:
				return "悄悄话"
			RangeType.NORMAL:
				return "普通对话"
			RangeType.BROADCAST:
				return "广播"
			_:
				return "未知"

	func get_max_participants() -> int:
		match range_type:
			RangeType.WHISPER:
				return 3
			RangeType.NORMAL:
				return 7
			RangeType.BROADCAST:
				return -1  # 大范围无人数上限(-1表示无限制)
			_:
				return 7

	# 获取对话范围的边界区域
	func get_range_boundary() -> Dictionary:
		"""
		获取对话范围的边界信息

		返回:
			{
				"type": "circle" | "medium_range" | "room_area",
				"center": Vector2,  # 圆心或区域中心
				"radius": float,     # 仅WHISPER使用
				"room_name": String, # NORMAL和BROADCAST使用
				"medium_range_id": String  # NORMAL使用
			}
		"""
		match range_type:
			RangeType.WHISPER:
				return {
					"type": "circle",
					"center": initiator.global_position if initiator else Vector2.ZERO,
					"radius": 30.0,
					"room_name": room_name,
					"medium_range_id": medium_range_id
				}
			RangeType.NORMAL:
				return {
					"type": "medium_range",
					"center": Vector2.ZERO,  # 中范围边界由room_manager计算
					"radius": 0.0,
					"room_name": room_name,
					"medium_range_id": medium_range_id
				}
			RangeType.BROADCAST:
				return {
					"type": "room_area",
					"center": Vector2.ZERO,  # 子场景边界由room_manager计算
					"radius": 0.0,
					"room_name": room_name,
					"medium_range_id": ""
				}
			_:
				return {"type": "circle", "center": Vector2.ZERO, "radius": 30.0, "room_name": "", "medium_range_id": ""}

	# 检查角色是否在对话范围内（需要外部传入AIAgent引用）
	func is_character_in_range(character: CharacterBody2D, ai_agent = null) -> bool:
		"""检查角色是否在此对话的范围内"""
		if not is_instance_valid(character):
			return false

		var boundary = get_range_boundary()

		match boundary.type:
			"circle":
				# WHISPER: 30px圆形范围
				var distance = character.global_position.distance_to(boundary.center)
				return distance <= boundary.radius

			"medium_range":
				# NORMAL: 同一中范围
				if ai_agent and ai_agent.has_method("_get_character_room"):
					var char_room = ai_agent._get_character_room(character)
					if char_room != boundary.room_name:
						return false
				elif character.get_meta("current_room", "") != boundary.room_name:
					return false
				if ai_agent and ai_agent.has_method("_get_character_medium_range"):
					var char_medium_range = ai_agent._get_character_medium_range(character)
					return char_medium_range == boundary.medium_range_id
				# 回退：使用元数据
				return character.get_meta("medium_range_id", "") == boundary.medium_range_id

			"room_area":
				# BROADCAST: 同一子场景
				if ai_agent and ai_agent.has_method("_get_character_room"):
					var char_room = ai_agent._get_character_room(character)
					return char_room == boundary.room_name
				# 回退：使用元数据
				return character.get_meta("current_room", "") == boundary.room_name

		return false

	func add_participant(character: CharacterBody2D, click_index: int) -> bool:
		if participants.has(character):
			return false
		var max_participants = get_max_participants()
		if max_participants > 0 and participants.size() >= max_participants:
			return false

		participants[character] = click_index

		# 添加到发言队列
		var participant_array: Array[CharacterBody2D] = []
		participant_array.assign(participants.keys())
		if speaker_queue.speaker_states.is_empty():
			speaker_queue.initialize_queue(participant_array, dialogue_id, topic)
		else:
			speaker_queue.add_participant(character)

		return true

	func remove_participant(character: CharacterBody2D) -> bool:
		if not participants.has(character):
			return false

		participants.erase(character)
		speaker_queue.remove_participant(character)

		return true

	func add_message(speaker: String, content: String, click_index: int):
		message_history.append({
			"speaker": speaker,
			"content": content,
			"click_index": click_index,
			"timestamp": Time.get_unix_time_from_system()
		})
		last_message_click = click_index
		last_message_time = Time.get_unix_time_from_system()
		silence_rounds = 0

	func get_messages_since(click_index: int) -> Array[Dictionary]:
		"""获取从指定Click索引之后的消息"""
		var result: Array[Dictionary] = []
		for msg in message_history:
			if msg.click_index >= click_index:
				result.append(msg)
		return result

	func get_formatted_history(max_messages: int = 10) -> String:
		var result = ""
		var start_idx = max(0, message_history.size() - max_messages)
		for i in range(start_idx, message_history.size()):
			var msg = message_history[i]
			result += "%s: %s\n" % [msg.speaker, msg.content]
		return result.strip_edges()

# 活跃对话 {dialogue_id: DialogueData}
var active_dialogues: Dictionary = {}

# 配置参数
const DIALOGUE_TIMEOUT_MINUTES: float = 45.0  # 45分钟游戏时间超时
const MAX_MESSAGE_HISTORY: int = 100          # 最大消息历史数
const SINGLE_PARTICIPANT_GRACE_CLICKS: int = 2 # 普通对话等待他人加入的Click数

# 信号
signal dialogue_started(dialogue_id: String, initiator_name: String, range_type: int, room: String)
signal dialogue_ended(dialogue_id: String, reason: String, duration_minutes: float)
signal participant_joined(dialogue_id: String, character_name: String)
signal participant_left(dialogue_id: String, character_name: String)
signal message_added(dialogue_id: String, speaker_name: String, content: String)
signal speaker_selected(dialogue_id: String, speaker_name: String)

func _ready():
	print("[DialogueManager] 统一对话管理器已初始化")

# ============================================
# 核心对话管理
# ============================================

func start_dialogue(initiator: CharacterBody2D, range_type: int, topic: String = "",
					room_name: String = "", medium_range_id: String = "",
					start_click: int = 0, start_time: float = 0.0) -> String:
	"""
	发起新对话

	参数:
		initiator: 发起者
		range_type: 对话范围 (WHISPER/NORMAL/BROADCAST)
		topic: 讨论主题
		room_name: 所在房间
		medium_range_id: 中范围标识
		start_click: 开始Click索引
		start_time: 游戏开始时间

	返回:
		dialogue_id: 对话ID，失败返回空字符串
	"""
	if not is_instance_valid(initiator):
		push_error("[DialogueManager] 发起者无效")
		return ""

	# 获取房间和中范围信息（如果未提供）
	if room_name.is_empty():
		room_name = _get_character_room(initiator)
	if medium_range_id.is_empty():
		medium_range_id = _get_character_medium_range(initiator)

	if room_name.is_empty():
		push_error("[DialogueManager] 无法获取发起者所在房间")
		return ""

	_end_dialogues_for_character(initiator, EndReason.MANUAL)

	# 生成对话ID: dlg_<发起人>_<游戏时间戳>
	var time_str = str(int(start_time))
	var dialogue_id = "dlg_%s_%s" % [initiator.name, time_str]

	# 创建对话数据
	var dialogue_data = DialogueData.new(
		dialogue_id, initiator, range_type,
		room_name, medium_range_id, start_click, start_time
	)
	dialogue_data.topic = topic
	dialogue_data.add_participant(initiator, start_click)

	active_dialogues[dialogue_id] = dialogue_data

	# 设置发起者元数据
	_set_character_dialogue_meta(initiator, dialogue_id, range_type)

	print("[DialogueManager] %s开始: %s (房间:%s, 范围:%s, 主题:%s)" % [
		dialogue_data.get_range_name(), dialogue_id, room_name, medium_range_id, topic
	])

	# 记录对话开始到日志
	var logger = get_node_or_null("/root/Logger")
	if logger:
		var participant_names: Array[String] = [initiator.name]
		logger.log_conversation_start(initiator.name, "群聊", room_name)
		logger.log_dialogue("系统", "群聊", "=== %s 发起%s，主题：%s ===" % [initiator.name, dialogue_data.get_range_name(), topic], room_name)

	dialogue_started.emit(dialogue_id, initiator.name, range_type, room_name)

	return dialogue_id

func join_dialogue(character: CharacterBody2D, dialogue_id: String, current_click: int) -> bool:
	"""
	加入对话

	参数:
		character: 要加入的角色
		dialogue_id: 对话ID
		current_click: 当前Click索引（用于记录加入时间）
	"""
	if not active_dialogues.has(dialogue_id):
		print("[DialogueManager] 对话不存在: %s" % dialogue_id)
		return false

	var dialogue_data = active_dialogues[dialogue_id]

	# 检查是否已经在对话中
	if dialogue_data.participants.has(character):
		return true

	# 悄悄话不允许新成员加入
	if dialogue_data.range_type == RangeType.WHISPER:
		print("[DialogueManager] %s 是悄悄话，无法加入" % dialogue_id)
		return false

	# 检查人数上限（-1表示无限制）
	var max_participants = dialogue_data.get_max_participants()
	if max_participants > 0 and dialogue_data.participants.size() >= max_participants:
		print("[DialogueManager] %s 已满（%d/%d人）" % [
			dialogue_id, dialogue_data.participants.size(), max_participants
		])
		return false

	# 检查范围（非广播需要同一中范围）
	if dialogue_data.range_type == RangeType.NORMAL:
		var char_room = _get_character_room(character)
		if char_room != dialogue_data.room_name:
			print("[DialogueManager] %s 不在同一房间，无法加入" % character.name)
			return false
		var char_medium = _get_character_medium_range(character)
		if char_medium != dialogue_data.medium_range_id:
			print("[DialogueManager] %s 不在同一中范围，无法加入" % character.name)
			return false

	# 广播只需要同一房间
	if dialogue_data.range_type == RangeType.BROADCAST:
		var char_room = _get_character_room(character)
		if char_room != dialogue_data.room_name:
			print("[DialogueManager] %s 不在同一房间，无法加入" % character.name)
			return false

	_remove_character_from_other_dialogues(character, dialogue_id)

	# 添加参与者
	if dialogue_data.add_participant(character, current_click):
		_set_character_dialogue_meta(character, dialogue_id, dialogue_data.range_type)

		print("[DialogueManager] %s 加入对话 %s" % [character.name, dialogue_id])
		participant_joined.emit(dialogue_id, character.name)

		# 记录加入对话到日志
		var logger = get_node_or_null("/root/Logger")
		if logger:
			var participant_names: Array[String] = []
			for p in dialogue_data.participants.keys():
				if is_instance_valid(p):
					participant_names.append(p.name)
			logger.log_dialogue("系统", "群聊", "=== %s 加入对话，当前参与者：%s ===" % [character.name, ", ".join(participant_names)], dialogue_data.room_name)

		return true

	return false

func leave_dialogue(character: CharacterBody2D, dialogue_id: String) -> bool:
	"""
	离开对话
	"""
	if not active_dialogues.has(dialogue_id):
		return false

	var dialogue_data = active_dialogues[dialogue_id]

	if dialogue_data.remove_participant(character):
		_clear_character_dialogue_meta(character, dialogue_id)

		print("[DialogueManager] %s 离开对话 %s" % [character.name, dialogue_id])
		participant_left.emit(dialogue_id, character.name)

		# 检查是否人数不足
		if dialogue_data.participants.size() < 2:
			_end_dialogue(dialogue_id, EndReason.EMPTY)

		return true

	return false

func end_dialogue(dialogue_id: String, reason: int = EndReason.MANUAL):
	"""
	结束对话（外部调用）
	"""
	_end_dialogue(dialogue_id, reason)

func _end_dialogue(dialogue_id: String, reason: int):
	"""内部结束对话"""
	if not active_dialogues.has(dialogue_id):
		return

	var dialogue_data = active_dialogues[dialogue_id]

	# 计算持续时间
	var current_time = _get_current_game_time()
	var duration_minutes = max(0.0, current_time - dialogue_data.start_time)

	# 清理所有参与者的元数据
	for character in dialogue_data.participants.keys():
		if is_instance_valid(character):
			_clear_character_dialogue_meta(character, dialogue_id)

	# 同步到记忆系统
	_sync_to_memory(dialogue_data)

	var reason_str = _get_end_reason_string(reason)
	print("[DialogueManager] 对话结束: %s (原因: %s, 持续时间: %.1f分钟)" % [
		dialogue_id, reason_str, duration_minutes
	])

	# 记录对话结束到日志
	var logger = get_node_or_null("/root/Logger")
	if logger:
		var participant_names: Array[String] = []
		for p in dialogue_data.participants.keys():
			if is_instance_valid(p):
				participant_names.append(p.name)
		var participants_str = ", ".join(participant_names)
		logger.log_dialogue("系统", "群聊", "=== 对话结束（%s），参与者：%s，持续时间：%.1f分钟 ===" % [reason_str, participants_str, duration_minutes], dialogue_data.room_name)
		logger.log_conversation_end(participants_str, "群聊")

	dialogue_ended.emit(dialogue_id, reason_str, duration_minutes)

	active_dialogues.erase(dialogue_id)

# ============================================
# 发言管理
# ============================================

func request_to_speak(character: CharacterBody2D, dialogue_id: String,
					  willingness: float = 0.5) -> bool:
	"""
	请求发言

	参数:
		character: 请求发言的角色
		dialogue_id: 对话ID
		willingness: 发言意愿 (0-1)

	返回:
		是否成功提交请求
	"""
	if not active_dialogues.has(dialogue_id):
		return false

	var dialogue_data = active_dialogues[dialogue_id]

	if not dialogue_data.participants.has(character):
		return false

	# 更新发言意愿（影响优先级）
	var state = dialogue_data.speaker_queue.speaker_states.get(character)
	if state:
		state.willingness = willingness

	return true

func teacher_select_speaker(teacher: CharacterBody2D, student_name: String,
							dialogue_id: String) -> bool:
	"""
	教师选择发言者（大范围对话专用）

	参数:
		teacher: 教师角色
		student_name: 选中的学生名称
		dialogue_id: 对话ID

	返回:
		是否成功
	"""
	if not active_dialogues.has(dialogue_id):
		return false

	var dialogue_data = active_dialogues[dialogue_id]

	# 检查是否是广播对话
	if dialogue_data.range_type != RangeType.BROADCAST:
		print("[DialogueManager] 只有大范围对话支持教师选择发言者")
		return false

	# 检查教师是否是发起者
	if dialogue_data.initiator != teacher:
		print("[DialogueManager] 只有发起者可以指定发言者")
		return false

	# 检查学生是否在对话中
	var found_student = null
	for participant in dialogue_data.participants.keys():
		if participant.name == student_name:
			found_student = participant
			break

	if not found_student:
		print("[DialogueManager] 学生 %s 不在对话中" % student_name)
		return false

	# 设置教师选择的标记
	dialogue_data.teacher_selected_speaker = student_name

	print("[DialogueManager] 教师 %s 指定 %s 发言" % [teacher.name, student_name])

	return true

func select_next_speaker(dialogue_id: String) -> CharacterBody2D:
	"""
	选择下一位发言者

	返回:
		选中的发言者，如果没有则返回null
	"""
	if not active_dialogues.has(dialogue_id):
		return null

	var dialogue_data = active_dialogues[dialogue_id]

	# 大范围对话优先使用教师选择
	if dialogue_data.range_type == RangeType.BROADCAST:
		if not dialogue_data.teacher_selected_speaker.is_empty():
			for participant in dialogue_data.participants.keys():
				if participant.name == dialogue_data.teacher_selected_speaker:
					dialogue_data.teacher_selected_speaker = ""
					dialogue_data.current_speaker = participant
					speaker_selected.emit(dialogue_id, participant.name)
					return participant

	# 使用优先级队列选择
	var next_speaker = dialogue_data.speaker_queue.select_next_speaker()
	if next_speaker:
		dialogue_data.current_speaker = next_speaker
		speaker_selected.emit(dialogue_id, next_speaker.name)

	return next_speaker

func add_message(dialogue_id: String, speaker: CharacterBody2D, content: String,
				 click_index: int) -> bool:
	"""
	添加消息到对话
	"""
	if not active_dialogues.has(dialogue_id):
		return false

	var dialogue_data = active_dialogues[dialogue_id]

	if not dialogue_data.participants.has(speaker):
		return false

	var participant_names: Array[String] = []
	for p in dialogue_data.participants.keys():
		if is_instance_valid(p):
			participant_names.append(p.name)
	content = _sanitize_dialogue_content(content, speaker.name, participant_names)
	if content.is_empty():
		return false

	dialogue_data.add_message(speaker.name, content, click_index)

	# 记录到发言队列
	dialogue_data.speaker_queue.record_message(speaker, content)

	print("[DialogueManager] [%s] %s: %s" % [dialogue_id, speaker.name, content.substr(0, 50)])
	message_added.emit(dialogue_id, speaker.name, content)

	# 记录到日志系统
	var logger = get_node_or_null("/root/Logger")
	if logger:
		# 获取其他参与者作为listener
		var listeners: Array[String] = []
		for p in dialogue_data.participants.keys():
			if p != speaker and is_instance_valid(p):
				listeners.append(p.name)
		var listener_str = ", ".join(listeners) if listeners.size() > 0 else "群聊"
		logger.log_dialogue(speaker.name, listener_str, content, dialogue_data.room_name)

	return true

# ============================================
# TimingSystem回调 - 发言者选择与内容生成
# ============================================

# 内容生成队列（避免同一帧生成多个）
var _pending_message_generations: Array[Dictionary] = []
var _is_generating: bool = false

func on_click_tick(current_click: int, current_time: float):
	"""
	每个Click调用，由TimingSystem触发

	检查:
	1. 超时对话
	2. 全员沉默
	3. 选择下一位发言者并生成内容
	"""
	var to_end: Array[String] = []
	_pending_message_generations.clear()

	for dialogue_id in active_dialogues.keys():
		var dialogue_data = active_dialogues[dialogue_id]

		# 检查超时 (45分钟游戏时间)
		# current_time和start_time都是游戏分钟，直接相减即可
		var elapsed_minutes = current_time - dialogue_data.start_time
		if elapsed_minutes >= DIALOGUE_TIMEOUT_MINUTES:
			to_end.append(dialogue_id)
			_end_dialogue(dialogue_id, EndReason.TIMEOUT)
			continue

		if _should_end_single_participant_dialogue(dialogue_data, current_click):
			to_end.append(dialogue_id)
			_end_dialogue(dialogue_id, EndReason.EMPTY)
			continue

		# 检查全员沉默（跳过对话创建的第一个Click）
		if current_click > dialogue_data.start_click + 1:
			if dialogue_data.last_message_click < current_click - 1:
				# 上一个Click没有新消息
				dialogue_data.silence_rounds += 1

				if dialogue_data.silence_rounds >= 2:
					# 全员沉默2个Click，结束对话
					to_end.append(dialogue_id)
					_end_dialogue(dialogue_id, EndReason.SILENCE)
					continue
			else:
				dialogue_data.silence_rounds = 0

		# 选择下一位发言者并准备生成内容
		_select_and_queue_speaker(dialogue_id, current_click)

	# 清理已结束的对话
	for dialogue_id in to_end:
		active_dialogues.erase(dialogue_id)

	# 开始生成内容（串行处理避免过载）
	if not _pending_message_generations.is_empty():
		_process_message_generations()

func _select_and_queue_speaker(dialogue_id: String, current_click: int):
	"""
	选择发言者并加入生成队列
	"""
	var dialogue_data = active_dialogues.get(dialogue_id)
	if not dialogue_data:
		return

	if _should_skip_single_participant_speaking(dialogue_data, current_click):
		return

	# 选择下一位发言者
	var next_speaker = select_next_speaker(dialogue_id)
	if not next_speaker:
		return

	# 检查是否是AIAgent（玩家控制的角色不自动生成）
	var ai_agent = _get_ai_agent(next_speaker)
	if not ai_agent:
		return

	# 加入生成队列
	_pending_message_generations.append({
		"dialogue_id": dialogue_id,
		"speaker": next_speaker,
		"ai_agent": ai_agent,
		"click_index": current_click
	})

func _process_message_generations():
	"""
	串行处理消息生成
	"""
	if _is_generating or _pending_message_generations.is_empty():
		return

	_is_generating = true

	while not _pending_message_generations.is_empty():
		var task = _pending_message_generations.pop_front()
		await _generate_message_for_speaker(task)
		# 短暂延迟避免帧率下降
		await get_tree().create_timer(0.1).timeout

	_is_generating = false

func _generate_message_for_speaker(task: Dictionary):
	"""
	为指定发言者生成消息内容
	"""
	var dialogue_id = task.dialogue_id
	var speaker = task.speaker
	var ai_agent = task.ai_agent
	var click_index = task.click_index

	# 检查对话是否仍然存在
	if not active_dialogues.has(dialogue_id):
		return

	var dialogue_data = active_dialogues[dialogue_id]

	# 构建对话历史
	var dialogue_history = dialogue_data.get_formatted_history(8)

	# 获取其他参与者信息
	var other_participants: Array[String] = []
	for p in dialogue_data.participants.keys():
		if p != speaker and is_instance_valid(p):
			other_participants.append(p.name)

	# 调用AIAgent生成内容
	var content = await ai_agent.generate_dialogue_message(
		dialogue_history,
		dialogue_data.topic,
		other_participants,
		dialogue_data.get_range_name()
	)

	if content.is_empty():
		print("[DialogueManager] %s 生成内容为空，跳过" % speaker.name)
		return

	# 添加消息到对话
	add_message(dialogue_id, speaker, content, click_index)

func _get_ai_agent(character: CharacterBody2D) -> Node:
	"""获取角色的AIAgent组件"""
	if not is_instance_valid(character):
		return null

	# 尝试直接获取AIAgent子节点
	if character.has_node("AIAgent"):
		return character.get_node("AIAgent")

	# 遍历子节点查找
	for child in character.get_children():
		if child.has_method("generate_dialogue_message"):
			return child

	return null

# ============================================
# 感知层接口
# ============================================

func get_visible_dialogues(room_name: String, medium_range_id: String,
						   character: CharacterBody2D) -> Array[Dictionary]:
	"""
	获取角色可见的对话列表（行为可见性）

	同一子场景内所有对话行为可见，悄悄话50%概率被感知

	返回:
		[{dialogue_id, range_type, participants[], is_whisper, perceived}]
	"""
	var result: Array[Dictionary] = []

	for dialogue_id in active_dialogues.keys():
		var dialogue_data = active_dialogues[dialogue_id]

		# 检查是否同一房间
		if dialogue_data.room_name != room_name:
			continue

		var perceived = true

		# 悄悄话特殊处理：不在小范围内的角色50%概率感知
		if dialogue_data.range_type == RangeType.WHISPER:
			if dialogue_data.medium_range_id != medium_range_id:
				# 不在同一中范围，50%概率感知
				perceived = randf() < 0.5

		if perceived:
			var participant_names: Array[String] = []
			for p in dialogue_data.participants.keys():
				if is_instance_valid(p):
					participant_names.append(p.name)

			result.append({
				"dialogue_id": dialogue_id,
				"range_type": dialogue_data.range_type,
				"range_name": dialogue_data.get_range_name(),
				"participants": participant_names,
				"is_whisper": dialogue_data.range_type == RangeType.WHISPER,
				"room": dialogue_data.room_name,
				"medium_range": dialogue_data.medium_range_id
			})

	return result

func get_dialogue_content(dialogue_id: String, character: CharacterBody2D,
						  current_click: int) -> Array[Dictionary]:
	"""
	获取角色可感知的对话内容

	只有同一范围内的角色才能获取内容
	从角色加入对话的Click开始返回消息

	返回:
		消息历史数组，如果不在范围内返回空数组
	"""
	if not active_dialogues.has(dialogue_id):
		return []

	var dialogue_data = active_dialogues[dialogue_id]

	# 检查是否在范围内
	if not _is_character_in_dialogue_range(character, dialogue_data):
		return []

	# 获取角色加入时间
	var joined_click = dialogue_data.participants.get(character, 0)

	# 返回从加入后开始的对话内容
	return dialogue_data.get_messages_since(joined_click)

func get_dialogue_history_for_memory(dialogue_id: String, character: CharacterBody2D) -> Array[Dictionary]:
	"""
	获取用于记忆存储的对话历史

	返回:
		从角色加入时间开始的完整消息历史
	"""
	if not active_dialogues.has(dialogue_id):
		return []

	var dialogue_data = active_dialogues[dialogue_id]
	var joined_click = dialogue_data.participants.get(character, 0)

	return dialogue_data.get_messages_since(joined_click)

# ============================================
# 查询接口
# ============================================

func is_character_in_dialogue(character: CharacterBody2D) -> bool:
	"""检查角色是否在任何对话中"""
	if not is_instance_valid(character):
		return false
	return not _get_active_dialogue_for_character(character).is_empty()

func get_character_dialogue(character: CharacterBody2D) -> String:
	"""获取角色参与的对话ID"""
	if not is_instance_valid(character):
		return ""
	return _get_active_dialogue_for_character(character)

func get_dialogue_info(dialogue_id: String) -> Dictionary:
	"""获取对话信息"""
	if not active_dialogues.has(dialogue_id):
		return {}

	var dialogue_data = active_dialogues[dialogue_id]
	var participant_names: Array[String] = []
	for p in dialogue_data.participants.keys():
		if is_instance_valid(p):
			participant_names.append(p.name)

	return {
		"dialogue_id": dialogue_id,
		"range_type": dialogue_data.range_type,
		"range_name": dialogue_data.get_range_name(),
		"room": dialogue_data.room_name,
		"medium_range": dialogue_data.medium_range_id,
		"topic": dialogue_data.topic,
		"participants": participant_names,
		"participant_count": dialogue_data.participants.size(),
		"message_count": dialogue_data.message_history.size(),
		"start_click": dialogue_data.start_click
	}

func has_active_dialogue(dialogue_id: String) -> bool:
	"""检查对话ID是否仍然活跃"""
	return active_dialogues.has(dialogue_id)

func find_joinable_dialogue(character: CharacterBody2D) -> String:
	"""查找角色当前位置可加入的对话"""
	if not is_instance_valid(character):
		return ""

	var char_room = _get_character_room(character)
	var char_medium = _get_character_medium_range(character)
	if not _get_active_dialogue_for_character(character).is_empty():
		return _get_active_dialogue_for_character(character)

	for dialogue_id in active_dialogues.keys():
		var dialogue_data = active_dialogues[dialogue_id]
		if dialogue_data.participants.has(character):
			return dialogue_id
		if dialogue_data.range_type == RangeType.WHISPER:
			continue

		var max_participants = dialogue_data.get_max_participants()
		if max_participants > 0 and dialogue_data.participants.size() >= max_participants:
			continue

		if dialogue_data.range_type == RangeType.NORMAL:
			if char_room == dialogue_data.room_name and char_medium == dialogue_data.medium_range_id:
				return dialogue_id
		elif dialogue_data.range_type == RangeType.BROADCAST:
			if char_room == dialogue_data.room_name:
				return dialogue_id

	return ""

# ============================================
# 辅助函数
# ============================================

func _get_character_room(character: CharacterBody2D) -> String:
	"""获取角色所在房间"""
	if not is_instance_valid(character):
		return ""

	# 优先从AIAgent获取（更准确）
	var ai_agent = _get_ai_agent(character)
	if ai_agent and ai_agent.has_method("_get_character_room"):
		return ai_agent._get_character_room(character)

	# 回退到元数据
	return character.get_meta("current_room", "")

func _get_character_medium_range(character: CharacterBody2D) -> String:
	"""获取角色所在中范围"""
	if not is_instance_valid(character):
		return ""

	# 优先从AIAgent获取（更准确）
	var ai_agent = _get_ai_agent(character)
	if ai_agent and ai_agent.has_method("_get_character_medium_range"):
		return ai_agent._get_character_medium_range(character)

	# 回退到元数据
	return character.get_meta("medium_range_id", "")

func _set_character_dialogue_meta(character: CharacterBody2D, dialogue_id: String, range_type: int):
	"""设置角色对话元数据"""
	if not is_instance_valid(character):
		return
	character.set_meta("current_dialogue_id", dialogue_id)
	character.set_meta("in_dialogue", true)
	character.set_meta("dialogue_range_type", range_type)

func _clear_character_dialogue_meta(character: CharacterBody2D, dialogue_id: String = ""):
	"""清除角色对话元数据"""
	if not is_instance_valid(character):
		return
	if not dialogue_id.is_empty() and character.get_meta("current_dialogue_id", "") != dialogue_id:
		return
	character.remove_meta("current_dialogue_id")
	character.remove_meta("in_dialogue")
	character.remove_meta("dialogue_range_type")

func _get_active_dialogue_for_character(character: CharacterBody2D) -> String:
	"""从活跃对话表中查找角色当前参与的对话，避免依赖过期metadata"""
	if not is_instance_valid(character):
		return ""
	for dialogue_id in active_dialogues.keys():
		var dialogue_data = active_dialogues[dialogue_id]
		if dialogue_data.participants.has(character):
			return dialogue_id
	return ""

func _end_dialogues_for_character(character: CharacterBody2D, reason: int):
	"""结束包含该角色的旧对话，确保角色不会同时参与多个对话"""
	if not is_instance_valid(character):
		return
	var to_end: Array[String] = []
	for dialogue_id in active_dialogues.keys():
		var dialogue_data = active_dialogues[dialogue_id]
		if dialogue_data.participants.has(character):
			to_end.append(dialogue_id)
	for dialogue_id in to_end:
		_end_dialogue(dialogue_id, reason)

func _remove_character_from_other_dialogues(character: CharacterBody2D, keep_dialogue_id: String):
	"""加入新对话前，从其它对话中移除该角色"""
	if not is_instance_valid(character):
		return
	var to_end: Array[String] = []
	for dialogue_id in active_dialogues.keys():
		if dialogue_id == keep_dialogue_id:
			continue
		var dialogue_data = active_dialogues[dialogue_id]
		if dialogue_data.participants.has(character):
			dialogue_data.remove_participant(character)
			_clear_character_dialogue_meta(character, dialogue_id)
			participant_left.emit(dialogue_id, character.name)
			if dialogue_data.participants.size() < 2:
				to_end.append(dialogue_id)
	for dialogue_id in to_end:
		_end_dialogue(dialogue_id, EndReason.EMPTY)

func _get_current_game_time() -> float:
	"""获取当前游戏时间（分钟）"""
	if TimingSystem.instance:
		return TimingSystem.instance.current_game_time
	return TimeUtils.get_game_time_minutes()

func _sanitize_dialogue_content(content: String, speaker_name: String, participant_names: Array[String] = []) -> String:
	"""清理LLM偶尔生成的角色名前缀和多余引号"""
	var cleaned = content.strip_edges()
	cleaned = _strip_outer_quotes(cleaned)

	var prefixes: Array[String] = [
		speaker_name + "：",
		speaker_name + ":",
		"我说：",
		"我说:",
		"你对大家说：",
		"你对大家说:",
		"对大家说：",
		"对大家说:",
		"他说：",
		"他说:",
		"她说：",
		"她说:"
	]
	for participant_name in participant_names:
		prefixes.append(participant_name + "：")
		prefixes.append(participant_name + ":")

	for prefix in prefixes:
		while cleaned.begins_with(prefix):
			cleaned = cleaned.substr(prefix.length()).strip_edges()
			cleaned = _strip_outer_quotes(cleaned)

	cleaned = _extract_quoted_dialogue_after_say(cleaned)

	return cleaned

func _strip_outer_quotes(text: String) -> String:
	var cleaned = text.strip_edges()
	var quote_pairs = [
		["\"", "\""],
		["'", "'"],
		["“", "”"],
		["‘", "’"]
	]
	for pair in quote_pairs:
		if cleaned.begins_with(pair[0]) and cleaned.ends_with(pair[1]) and cleaned.length() >= 2:
			return cleaned.substr(1, cleaned.length() - 2).strip_edges()
	return cleaned

func _extract_quoted_dialogue_after_say(text: String) -> String:
	var say_markers = ["说：", "说:"]
	for marker in say_markers:
		var marker_index = text.find(marker)
		if marker_index == -1:
			continue
		var rest = text.substr(marker_index + marker.length()).strip_edges()
		rest = _strip_outer_quotes(rest)
		if not rest.is_empty():
			return rest
	return text

func _should_end_single_participant_dialogue(dialogue_data: DialogueData, current_click: int) -> bool:
	"""普通对话没人加入时，短暂等待后自动结束"""
	if dialogue_data.range_type != RangeType.NORMAL:
		return false
	if dialogue_data.participants.size() != 1:
		return false
	return current_click >= dialogue_data.start_click + SINGLE_PARTICIPANT_GRACE_CLICKS

func _should_skip_single_participant_speaking(dialogue_data: DialogueData, current_click: int) -> bool:
	"""普通对话只有发起者时，只允许开场，不持续自言自语"""
	if dialogue_data.range_type != RangeType.NORMAL:
		return false
	if dialogue_data.participants.size() != 1:
		return false
	return current_click > dialogue_data.start_click

func _is_character_in_dialogue_range(character: CharacterBody2D, dialogue_data: DialogueData) -> bool:
	"""检查角色是否在对话范围内（可感知内容）"""
	if not is_instance_valid(character):
		return false

	# 检查是否是对话参与者
	if dialogue_data.participants.has(character):
		return true

	var char_room = _get_character_room(character)
	var char_medium = _get_character_medium_range(character)

	match dialogue_data.range_type:
		RangeType.WHISPER:
			# WHISPER: 30px圆形范围，需要检查实际距离
			if char_room != dialogue_data.room_name:
				return false
			if dialogue_data.initiator and is_instance_valid(dialogue_data.initiator):
				var distance = character.global_position.distance_to(dialogue_data.initiator.global_position)
				return distance <= 30.0
			return false

		RangeType.NORMAL:
			# NORMAL: 同一中范围即可
			return char_room == dialogue_data.room_name and char_medium == dialogue_data.medium_range_id

		RangeType.BROADCAST:
			# BROADCAST: 同一子场景即可
			return char_room == dialogue_data.room_name

	return false

func _sync_to_memory(dialogue_data: DialogueData):
	"""同步对话到记忆系统"""
	var memory_system = get_node_or_null("/root/MemorySystem")
	if not memory_system:
		return

	for character in dialogue_data.participants.keys():
		if not is_instance_valid(character):
			continue

		# 获取该角色的对话历史（从加入时间开始）
		var joined_click = dialogue_data.participants[character]
		var messages = dialogue_data.get_messages_since(joined_click)

		if messages.is_empty():
			continue

		# 生成记忆摘要
		var other_names: Array[String] = []
		for p in dialogue_data.participants.keys():
			if p != character and is_instance_valid(p):
				other_names.append(p.name)

		var summary = "参与%s（与%s，%d条消息）" % [
			dialogue_data.get_range_name(),
			", ".join(other_names),
			messages.size()
		]

		if not dialogue_data.topic.is_empty():
			summary += "，主题：%s" % dialogue_data.topic

		# 添加到记忆系统
		memory_system.add_memory(
			character,
			summary,
			memory_system.MemoryType.INTERACTION,
			memory_system.MemoryImportance.HIGH
		)

		# 记录社交互动（与每个其他参与者）
		var game_time = dialogue_data.start_time
		for other in dialogue_data.participants.keys():
			if other != character and is_instance_valid(other):
				memory_system.record_interaction(
					character.name,
					other.name,
					dialogue_data.get_range_name(),
					game_time,
					dialogue_data.room_name,
					dialogue_data.topic,
					messages.size() * 2.0,  # 估算持续时间
					0.05  # 轻微正面情感影响
				)

func _get_end_reason_string(reason: int) -> String:
	match reason:
		EndReason.SILENCE:
			return "全员沉默"
		EndReason.TIMEOUT:
			return "超时"
		EndReason.MANUAL:
			return "手动结束"
		EndReason.EMPTY:
			return "人数不足"
		_:
			return "未知"
