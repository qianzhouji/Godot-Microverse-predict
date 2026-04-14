extends Node
class_name GroupDialogueManager

# ============================================
# GroupDialogueManager - 群组对话管理器
# ============================================
# 管理所有对话（2人及以上），替代原有的1v1对话系统
# 使用中范围划分系统（与AIAgent感知系统一致）：
#   - 4象限: 教室、图书馆、自习室、食堂
#   - 左右分区: 大走廊
#   - 单区域: 小走廊
# 范围由对话发起人所在的中范围决定
# ============================================

# 对话范围枚举（与AIAgent的中范围划分一致）
enum DialogueRange {
	WHISPER,      # 悄悄话 - 贴身范围（约30px，同一象限内）
	NORMAL,       # 普通对话 - 中范围（同一象限/分区）
	BROADCAST     # 广播 - 全房间（跨象限）
}

# 中范围类型（与AIAgent一致）
enum MediumRangeType {
	FOUR_QUADRANT,    # 4象限(教室、图书馆、自习室、食堂)
	LEFT_RIGHT,       # 左右分区(大走廊)
	SINGLE            # 单区域(小走廊)
}

# 群组对话数据类
class GroupDialogueData:
	var dialogue_id: String
	var participants: Array[CharacterBody2D] = []  # 参与者列表
	var state: int  # 使用DialogueLifecycleManager.DialogueState
	var start_time: float
	var last_interaction_time: float
	var message_history: Array[Dictionary] = []  # 消息历史
	var topic: String = ""  # 讨论主题
	var max_participants: int = 7  # 最大参与者数（中/大范围7人，小范围3人）
	
	# 对话范围（由发起人决定）
	var dialogue_range: int = DialogueRange.NORMAL  # 默认普通对话
	var range_distance: float = NORMAL_DISTANCE
	
	# 中范围信息（与场景划分对接）
	var medium_range_type: int = -1  # 中范围类型
	var medium_range_id: String = ""  # 中范围标识（如"Q1", "LEFT", "CENTER"）
	var room_name: String = ""  # 所在房间
	
	# 发起人和主要目标（用于2人对话）
	var initiator: CharacterBody2D = null
	var primary_target: CharacterBody2D = null  # 主要对话对象（可选）
	
	# 发言队列管理器
	var speaker_queue_manager: SpeakerQueueManager = null
	
	func _init(p_id: String, p_participants: Array[CharacterBody2D], p_range: int = DialogueRange.NORMAL, p_initiator: CharacterBody2D = null, p_target: CharacterBody2D = null, p_room: String = "", p_medium_type: int = -1, p_medium_id: String = ""):
		dialogue_id = p_id
		participants = p_participants.duplicate()
		dialogue_range = p_range
		initiator = p_initiator
		primary_target = p_target
		room_name = p_room
		medium_range_type = p_medium_type
		medium_range_id = p_medium_id
		
		# 根据范围设置距离
		match dialogue_range:
			DialogueRange.WHISPER:
				range_distance = WHISPER_DISTANCE   # 悄悄话
			DialogueRange.NORMAL:
				range_distance = NORMAL_DISTANCE    # 普通对话
			DialogueRange.BROADCAST:
				range_distance = 99999.0            # 广播（全房间）
		
		state = 0  # INITIATING
		start_time = Time.get_unix_time_from_system()
		last_interaction_time = start_time
		
		# 创建发言队列管理器
		_speaker_queue_manager = SpeakerQueueManager.new()
		_speaker_queue_manager.initialize_queue(participants, dialogue_id, topic)
	
	func get_range_name() -> String:
		"""获取范围名称"""
		match dialogue_range:
			DialogueRange.WHISPER:
				return "悄悄话"
			DialogueRange.NORMAL:
				return "普通对话"
			DialogueRange.BROADCAST:
				return "广播"
			_:
				return "未知"
	
	func is_whisper() -> bool:
		"""是否是悄悄话"""
		return dialogue_range == DialogueRange.WHISPER
	
	func is_in_range(character: CharacterBody2D) -> bool:
		"""检查角色是否在当前对话范围内（距离检查）"""
		if participants.is_empty():
			return false
		
		# 检查与任一参与者的距离
		for participant in participants:
			if participant == character:
				return true  # 自己肯定在范围内
			if is_instance_valid(participant) and is_instance_valid(character):
				if participant.global_position.distance_to(character.global_position) <= range_distance:
					return true
		return false
	
	func is_in_same_medium_range(character: CharacterBody2D) -> bool:
		"""检查角色是否与发起人在同一中范围"""
		if not is_instance_valid(character):
			return false
		
		# 获取角色的中范围信息（从元数据）
		var char_room = character.get_meta("current_room", "")
		var char_medium_id = character.get_meta("medium_range_id", "")
		
		# 广播范围不需要检查中范围
		if dialogue_range == DialogueRange.BROADCAST:
			return char_room == room_name  # 只要在同一房间即可
		
		# 普通对话和悄悄话需要同一中范围
		return char_room == room_name and char_medium_id == medium_range_id
	
	func get_next_speaker() -> CharacterBody2D:
		"""获取下一位发言者（使用优先级队列）"""
		if _speaker_queue_manager:
			return _speaker_queue_manager.select_next_speaker()
		return null
	
	func get_speak_delay(character: CharacterBody2D) -> float:
		"""获取发言延迟"""
		if _speaker_queue_manager:
			return _speaker_queue_manager.get_speak_delay(character)
		return 2.0
	
	func add_message(speaker_name: String, content: String):
		"""添加消息到历史"""
		message_history.append({
			"speaker": speaker_name,
			"content": content,
			"timestamp": Time.get_unix_time_from_system()
		})
		last_interaction_time = Time.get_unix_time_from_system()
		
		# 通知发言队列管理器
		if _speaker_queue_manager:
			var speaker = _find_character_by_name(speaker_name)
			if speaker:
				_speaker_queue_manager.record_message(speaker, content)
	
	func _find_character_by_name(name: String) -> CharacterBody2D:
		"""根据名称查找角色"""
		for p in participants:
			if p.name == name:
				return p
		return null
	
	func add_participant(character: CharacterBody2D) -> bool:
		"""添加参与者"""
		if participants.has(character):
			return false
		
		# 根据范围检查人数限制
		var max_count = max_participants
		if dialogue_range == DialogueRange.SMALL:
			max_count = 3  # 悄悄话最多3人
		
		if participants.size() >= max_count:
			return false
		
		participants.append(character)
		
		# 添加到发言队列管理器
		if _speaker_queue_manager:
			_speaker_queue_manager.add_participant(character)
		
		return true
	
	func remove_participant(character: CharacterBody2D) -> bool:
		"""移除参与者"""
		if not participants.has(character):
			return false
		participants.erase(character)
		
		# 从发言队列管理器移除
		if _speaker_queue_manager:
			_speaker_queue_manager.remove_participant(character)
		
		return true
	
	func get_duration() -> float:
		return Time.get_unix_time_from_system() - start_time
	
	func get_formatted_history(max_messages: int = 10) -> String:
		"""获取格式化的对话历史用于Prompt"""
		var result = ""
		var start_idx = max(0, message_history.size() - max_messages)
		for i in range(start_idx, message_history.size()):
			var msg = message_history[i]
			result += "%s: %s\n" % [msg.speaker, msg.content]
		return result.strip_edges()

# 活跃群组对话 {dialogue_id: GroupDialogueData}
var active_group_dialogues: Dictionary = {}

# 配置参数
# 注意：不同范围有不同的参与人数限制
# - 悄悄话: 最多3人，必须在同一中范围内且贴身
# - 普通对话: 2-7人，必须在同一中范围内
# - 广播: 2-7人，可以跨中范围
const GROUP_MIN_PARTICIPANTS: int = 2      # 最小人数
const GROUP_MAX_PARTICIPANTS: int = 7      # 最大人数（普通/广播）
const WHISPER_MAX_PARTICIPANTS: int = 3    # 悄悄话最大人数

# 距离配置
const WHISPER_DISTANCE: float = 50.0       # 悄悄话距离（贴身）
const NORMAL_DISTANCE: float = 200.0       # 普通对话距离（中范围）

# 范围配置（由发起人决定）
const RANGE_SMALL: float = 30.0            # 小范围 - 悄悄话
const RANGE_MEDIUM: float = 150.0          # 中范围 - 普通对话
const RANGE_LARGE: float = 300.0           # 大范围 - 公开讨论

# 信号
signal group_dialogue_started(dialogue_id: String, participant_names: Array)
signal group_dialogue_ended(dialogue_id: String, reason: String)
signal participant_joined(dialogue_id: String, character_name: String)
signal participant_left(dialogue_id: String, character_name: String)
signal group_message_generated(dialogue_id: String, speaker_name: String, content: String)

func _ready():
	print("[GroupDialogueManager] 群组对话管理器已初始化")

# ============================================
# 群组对话管理
# ============================================

func try_start_group_dialogue(initiator: CharacterBody2D,
							  initial_participants: Array[CharacterBody2D],
							  topic: String = "",
							  dialogue_range: int = DialogueRange.NORMAL,
							  primary_target: CharacterBody2D = null) -> bool:
	"""
	尝试开始群组对话（支持2人及以上，使用中范围划分系统）

	参数:
		initiator: 发起者
		initial_participants: 初始参与者列表（包含发起者）
		topic: 讨论主题
		dialogue_range: 对话范围 (WHISPER=悄悄话, NORMAL=普通对话, BROADCAST=广播)
		primary_target: 主要对话对象（可选，用于2人对话）
	"""
	if initial_participants.size() < GROUP_MIN_PARTICIPANTS:
		print("[GroupDialogueManager] 参与者不足，需要至少%d人" % GROUP_MIN_PARTICIPANTS)
		return false

	# 获取发起人的中范围信息
	var initiator_info = _get_character_medium_range_info(initiator)
	if initiator_info.room_name.is_empty():
		print("[GroupDialogueManager] 无法获取发起人的中范围信息")
		return false

	# 检查所有参与者是否满足范围条件
	for participant in initial_participants:
		if participant == initiator:
			continue
		
		# 检查距离
		if not _is_in_range_by_distance(initiator, participant, WHISPER_DISTANCE if dialogue_range == DialogueRange.WHISPER else NORMAL_DISTANCE):
			print("[GroupDialogueManager] %s 距离太远" % participant.name)
			return false
		
		# 非广播范围需要检查中范围
		if dialogue_range != DialogueRange.BROADCAST:
			if not _is_in_same_medium_range(initiator, participant):
				print("[GroupDialogueManager] %s 不在同一中范围" % participant.name)
				return false

	# 生成对话ID
	var dialogue_id = _generate_group_dialogue_id(initiator, initial_participants)

	# 创建群组对话数据（传入中范围信息）
	var group_data = GroupDialogueData.new(
		dialogue_id, 
		initial_participants, 
		dialogue_range, 
		initiator, 
		primary_target,
		initiator_info.room_name,
		initiator_info.medium_range_type,
		initiator_info.medium_range_id
	)
	group_data.topic = topic
	group_data.state = 1  # ACTIVE

	active_group_dialogues[dialogue_id] = group_data

	# 设置所有参与者的对话状态
	for participant in initial_participants:
		if participant.has_method("set_meta"):
			participant.set_meta("group_dialogue_id", dialogue_id)
			participant.set_meta("in_group_dialogue", true)
			participant.set_meta("dialogue_range", dialogue_range)
			participant.set_meta("dialogue_medium_range_id", initiator_info.medium_range_id)

	var participant_names = _get_participant_names(initial_participants)
	var range_name = group_data.get_range_name()
	print("[GroupDialogueManager] %s开始：%s (范围:%s, 中范围:%s, 参与者:%s)" % [
		range_name, dialogue_id, range_name, initiator_info.medium_range_id, ", ".join(participant_names)
	])
	group_dialogue_started.emit(dialogue_id, participant_names)

	# 开始第一轮对话
	_start_group_dialogue_turn(dialogue_id)

	return true

func try_join_group_dialogue(character: CharacterBody2D, dialogue_id: String) -> bool:
	"""尝试加入现有群组对话"""
	if not active_group_dialogues.has(dialogue_id):
		return false

	var group_data = active_group_dialogues[dialogue_id]

	# 悄悄话不允许其他人加入
	if group_data.dialogue_range == DialogueRange.WHISPER:
		print("[GroupDialogueManager] %s 是悄悄话，无法加入" % dialogue_id)
		return false

	# 根据范围检查人数限制
	var max_count = GROUP_MAX_PARTICIPANTS  # 默认7人

	# 检查是否已满
	if group_data.participants.size() >= max_count:
		print("[GroupDialogueManager] %s 已满（%d/%d人），无法加入" % [
			dialogue_id, group_data.participants.size(), max_count
		])
		return false
	
	# 检查中范围（非广播范围需要同一中范围）
	if group_data.dialogue_range == DialogueRange.NORMAL:
		if not group_data.is_in_same_medium_range(character):
			print("[GroupDialogueManager] %s 不在同一中范围，无法加入" % character.name)
			return false

	# 检查是否已经在群组中
	if group_data.participants.has(character):
		return false

	# 检查是否在范围内（使用该对话设定的范围距离）
	var in_range = false
	for participant in group_data.participants:
		if _is_in_range_by_distance(character, participant, group_data.range_distance):
			in_range = true
			break

	if not in_range:
		print("[GroupDialogueManager] %s 不在群组范围内" % character.name)
		return false

	# 添加参与者
	if group_data.add_participant(character):
		character.set_meta("group_dialogue_id", dialogue_id)
		character.set_meta("in_group_dialogue", true)
		character.set_meta("dialogue_range", group_data.dialogue_range)

		print("[GroupDialogueManager] %s 加入群组对话 %s" % [character.name, dialogue_id])
		participant_joined.emit(dialogue_id, character.name)

		# 添加系统消息
		group_data.add_message("系统", "%s 加入了讨论" % character.name)

		return true

	return false

func leave_group_dialogue(character: CharacterBody2D, dialogue_id: String) -> bool:
	"""离开群组对话"""
	if not active_group_dialogues.has(dialogue_id):
		return false
	
	var group_data = active_group_dialogues[dialogue_id]
	
	if group_data.remove_participant(character):
		character.remove_meta("group_dialogue_id")
		character.remove_meta("in_group_dialogue")
		
		print("[GroupDialogueManager] %s 离开群组对话 %s" % [character.name, dialogue_id])
		participant_left.emit(dialogue_id, character.name)
		
		# 添加系统消息
		group_data.add_message("系统", "%s 离开了讨论" % character.name)
		
		# 检查是否人数不足
		if group_data.participants.size() < GROUP_MIN_PARTICIPANTS:
			_end_group_dialogue(dialogue_id, "人数不足")
		
		return true
	
	return false

func end_group_dialogue(dialogue_id: String, reason: String = "normal"):
	"""结束群组对话"""
	_end_group_dialogue(dialogue_id, reason)

func _end_group_dialogue(dialogue_id: String, reason: String):
	"""内部结束群组对话"""
	if not active_group_dialogues.has(dialogue_id):
		return

	var group_data = active_group_dialogues[dialogue_id]

	# 清理所有参与者的状态
	for participant in group_data.participants:
		if is_instance_valid(participant):
			participant.remove_meta("group_dialogue_id")
			participant.remove_meta("in_group_dialogue")
			participant.remove_meta("dialogue_range")

	# 记录对话总结
	_record_group_dialogue_summary(group_data, reason)

	var range_name = group_data.get_range_name()
	print("[GroupDialogueManager] %s结束：%s (原因: %s)" % [range_name, dialogue_id, reason])
	group_dialogue_ended.emit(dialogue_id, reason)

	active_group_dialogues.erase(dialogue_id)

# ============================================
# 对话流转管理
# ============================================

func _start_group_dialogue_turn(dialogue_id: String):
	"""开始群组对话的一轮发言"""
	if not active_group_dialogues.has(dialogue_id):
		return
	
	var group_data = active_group_dialogues[dialogue_id]
	var next_speaker = group_data.get_next_speaker()
	
	if not is_instance_valid(next_speaker):
		# 发言者无效，跳过
		return
	
	# 获取发言延迟（模拟自然对话节奏）
	var speak_delay = group_data.get_speak_delay(next_speaker)
	print("[GroupDialogueManager] %s 将在 %.1f 秒后发言" % [next_speaker.name, speak_delay])
	
	# 延迟后生成发言
	await get_tree().create_timer(speak_delay).timeout
	
	# 检查对话是否仍然活跃
	if not active_group_dialogues.has(dialogue_id):
		return
	
	# 生成发言内容
	_generate_group_message(dialogue_id, next_speaker)

func _generate_group_message(dialogue_id: String, speaker: CharacterBody2D):
	"""生成群组对话消息"""
	if not active_group_dialogues.has(dialogue_id):
		return
	
	var group_data = active_group_dialogues[dialogue_id]
	
	# 构建Prompt
	var prompt = _build_group_dialogue_prompt(group_data, speaker)
	
	# 调用LLM生成内容
	var api_manager = get_node_or_null("/root/APIManager")
	if not api_manager:
		return
	
	# 异步生成对话
	_generate_dialogue_async(api_manager, prompt, dialogue_id, speaker)

func _build_group_dialogue_prompt(group_data: GroupDialogueData, speaker: CharacterBody2D) -> String:
	"""构建群组对话Prompt"""
	var speaker_personality = CharacterPersonality.get_personality(speaker.name)
	
	var prompt = "你正在参与一场多人讨论。\n\n"
	prompt += "你的名字是：%s\n" % speaker.name
	prompt += "你的身份是：%s\n" % speaker_personality.get("position", "学生")
	prompt += "你的性格是：%s\n" % speaker_personality.get("personality", "普通")
	prompt += "你的说话风格是：%s\n" % speaker_personality.get("speaking_style", "自然")
	
	# 添加讨论主题
	if not group_data.topic.is_empty():
		prompt += "\n讨论主题：%s\n" % group_data.topic
	
	# 添加其他参与者信息
	prompt += "\n其他参与者：\n"
	for participant in group_data.participants:
		if participant != speaker:
			var p_personality = CharacterPersonality.get_personality(participant.name)
			prompt += "- %s (%s)\n" % [participant.name, p_personality.get("position", "学生")]
	
	# 添加对话历史
	var history = group_data.get_formatted_history(8)
	if not history.is_empty():
		prompt += "\n之前的对话：\n%s\n" % history
	
	# 添加发言指导
	prompt += "\n请根据你的性格和讨论主题，发表你的观点。"
	prompt += "\n注意："
	prompt += "\n- 保持自然，像真人一样说话"
	prompt += "\n- 可以回应其他人的观点"
	prompt += "\n- 对话长度控制在1-3句话，50字以内"
	prompt += "\n- 只返回你要说的话，不要加任何前缀"
	
	return prompt

func _generate_dialogue_async(api_manager: Node, prompt: String, dialogue_id: String, speaker: CharacterBody2D):
	"""异步生成对话内容"""
	# 创建HTTP请求
	var http_request = HTTPRequest.new()
	add_child(http_request)
	
	var body = {
		"model": "qwen2.5:1.5b",
		"prompt": prompt,
		"stream": false,
		"options": {
			"temperature": 0.7,
			"num_predict": 100
		}
	}
	
	var error = http_request.request(
		"http://localhost:11434/api/generate",
		["Content-Type: application/json"],
		HTTPClient.METHOD_POST,
		JSON.stringify(body)
	)
	
	if error != OK:
		http_request.queue_free()
		return
	
	# 等待响应
	var result = await http_request.request_completed
	http_request.queue_free()
	
	if result[1] != 200:
		return
	
	# 解析响应
	var json = JSON.new()
	if json.parse(result[3].get_string_from_utf8()) != OK:
		return
	
	var response_data = json.get_data()
	var message = response_data.get("response", "").strip_edges()
	
	if message.is_empty():
		return
	
	# 添加到对话历史
	if active_group_dialogues.has(dialogue_id):
		var group_data = active_group_dialogues[dialogue_id]
		group_data.add_message(speaker.name, message)
		
		# 显示对话气泡
		_show_dialogue_bubble(speaker, message)
		
		# 发射信号
		group_message_generated.emit(dialogue_id, speaker.name, message)
		
		# 记录日志
		var logger = get_node_or_null("/root/Logger")
		if logger:
			var room_name = _get_character_room_name(speaker)
			var other_names = []
			for p in group_data.participants:
				if p != speaker:
					other_names.append(p.name)
			logger.log_dialogue(speaker.name, ", ".join(other_names), "[群组] %s" % message, room_name)
		
		print("[GroupDialogueManager] %s: %s" % [speaker.name, message])
		
		# 调度下一轮发言（如果对话仍然活跃）
		if active_group_dialogues.has(dialogue_id):
			_start_group_dialogue_turn(dialogue_id)

func _show_dialogue_bubble(character: CharacterBody2D, message: String):
	"""显示对话气泡"""
	var dialog_bubble_scene = load("res://scene/UI/DialogBubble.tscn")
	if not dialog_bubble_scene:
		return
	
	var dialog_bubble = dialog_bubble_scene.instantiate()
	get_tree().root.add_child(dialog_bubble)
	dialog_bubble.target_node = character
	dialog_bubble.show_dialog(message)

# ============================================
# 辅助函数
# ============================================

func _generate_group_dialogue_id(initiator: CharacterBody2D, participants: Array[CharacterBody2D]) -> String:
	"""生成群组对话ID"""
	var names = []
	for p in participants:
		names.append(p.name)
	names.sort()
	return "group_%s_%d" % ["_".join(names), Time.get_unix_time_from_system()]

func _get_participant_names(participants: Array[CharacterBody2D]) -> Array:
	"""获取参与者名称列表"""
	var names = []
	for p in participants:
		names.append(p.name)
	return names

func _is_in_group_range(char1: CharacterBody2D, char2: CharacterBody2D) -> bool:
	"""检查是否在群组对话范围内（使用默认中范围150px）"""
	if not is_instance_valid(char1) or not is_instance_valid(char2):
		return false
	return char1.global_position.distance_to(char2.global_position) <= RANGE_MEDIUM

# ============================================
# 中范围接口（与AIAgent感知系统对接）
# ============================================

func _get_character_medium_range_info(character: CharacterBody2D) -> Dictionary:
	"""获取角色的中范围信息（从AIAgent或元数据）"""
	var info = {
		"room_name": "",
		"medium_range_type": -1,
		"medium_range_id": ""
	}
	
	if not is_instance_valid(character):
		return info
	
	# 尝试从元数据获取
	info.room_name = character.get_meta("current_room", "")
	info.medium_range_id = character.get_meta("medium_range_id", "")
	
	# 如果元数据中没有，尝试通过AIAgent获取
	var ai_agent = _get_ai_agent(character)
	if ai_agent:
		var current_room = ai_agent._get_current_room()
		if current_room:
			info.room_name = current_room.get("room_name", "")
			# 获取中范围类型和ID
			var pos = character.global_position
			info.medium_range_type = ai_agent._get_room_medium_range_type(info.room_name)
			info.medium_range_id = ai_agent._get_medium_range_description(current_room, pos)
	
	return info

func _get_ai_agent(character: CharacterBody2D) -> Node:
	"""获取角色的AIAgent组件"""
	if not is_instance_valid(character):
		return null
	
	# 尝试直接获取AIAgent子节点
	if character.has_node("AIAgent"):
		return character.get_node("AIAgent")
	
	# 或者通过其他方式查找
	for child in character.get_children():
		if child is AIAgent:
			return child
	
	return null

func _is_in_same_medium_range(char1: CharacterBody2D, char2: CharacterBody2D) -> bool:
	"""检查两个角色是否在同一个中范围"""
	var info1 = _get_character_medium_range_info(char1)
	var info2 = _get_character_medium_range_info(char2)
	
	# 必须在同一房间
	if info1.room_name != info2.room_name:
		return false
	
	# 必须在同一中范围
	return info1.medium_range_id == info2.medium_range_id

func _is_in_range_by_distance(char1: CharacterBody2D, char2: CharacterBody2D, distance: float) -> bool:
	"""检查是否在指定距离内"""
	if not is_instance_valid(char1) or not is_instance_valid(char2):
		return false
	return char1.global_position.distance_to(char2.global_position) <= distance

func _get_character_room_name(character: CharacterBody2D) -> String:
	"""获取角色所在房间名称"""
	if not is_instance_valid(character):
		return "unknown"
	return character.get_meta("current_room", "unknown")

func _record_group_dialogue_summary(group_data: GroupDialogueData, reason: String):
	"""记录群组对话总结到记忆系统"""
	var memory_system = get_node_or_null("/root/MemorySystem")
	if not memory_system:
		return

	var duration = group_data.get_duration()
	var participant_names = _get_participant_names(group_data.participants)
	var range_name = group_data.get_range_name()

	for participant in group_data.participants:
		if not is_instance_valid(participant):
			continue

		var others = participant_names.duplicate()
		others.erase(participant.name)

		# 根据范围类型生成不同的记忆描述
		var summary = ""
		if group_data.dialogue_range == DialogueRange.SMALL:
			# 悄悄话
			if others.size() == 1:
				summary = "与%s悄悄话（%.0f秒，%d条消息）" % [others[0], duration, group_data.message_history.size()]
			else:
				summary = "参与私密讨论（与%s，%.0f秒，%d条消息）" % [", ".join(others), duration, group_data.message_history.size()]
		elif group_data.dialogue_range == DialogueRange.MEDIUM:
			# 普通对话
			if others.size() == 1:
				summary = "与%s对话（%.0f秒，%d条消息）" % [others[0], duration, group_data.message_history.size()]
			else:
				summary = "参与讨论（与%s，%.0f秒，%d条消息）" % [", ".join(others), duration, group_data.message_history.size()]
		else:
			# 公开讨论
			summary = "参与公开讨论（与%s，%.0f秒，%d条消息）" % [", ".join(others), duration, group_data.message_history.size()]

		if not group_data.topic.is_empty():
			summary += "，主题是：%s" % group_data.topic

		memory_system.add_memory(
			participant,
			summary,
			MemorySystem.MemoryType.INTERACTION,
			4
		)

# ============================================
# 查询接口
# ============================================

func get_active_group_count() -> int:
	"""获取活跃群组对话数量"""
	return active_group_dialogues.size()

func get_group_dialogue_data(dialogue_id: String) -> GroupDialogueData:
	"""获取群组对话数据"""
	return active_group_dialogues.get(dialogue_id)

func is_character_in_group_dialogue(character: CharacterBody2D) -> bool:
	"""检查角色是否在群组对话中"""
	if not character:
		return false
	return character.get_meta("in_group_dialogue", false)

func get_character_group_dialogue(character: CharacterBody2D) -> String:
	"""获取角色参与的群组对话ID"""
	if not character:
		return ""
	return character.get_meta("group_dialogue_id", "")

func get_nearby_group_dialogues(character: CharacterBody2D) -> Array:
	"""获取角色附近的群组对话"""
	var nearby = []
	for dialogue_id in active_group_dialogues:
		var group_data = active_group_dialogues[dialogue_id]
		for participant in group_data.participants:
			if _is_in_group_range(character, participant):
				nearby.append(dialogue_id)
				break
	return nearby
