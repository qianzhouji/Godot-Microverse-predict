extends Node
class_name DialogueInterruptionManager

# ============================================
# DialogueInterruptionManager - 对话打断管理器
# ============================================
# 管理第三方Agent插入/打断正在进行的对话
# 支持礼貌打断、紧急打断、旁听模式
# ============================================

# 打断类型
enum InterruptionType {
	POLITE,      # 礼貌打断（等待当前话题结束）
	URGENT,      # 紧急打断（有重要事情）
	CASUAL,      # 随意插入（熟人之间）
	LISTEN_ONLY  # 只旁听，不发言
}

# 打断请求数据
class InterruptionRequest:
	var requester: CharacterBody2D      # 请求打断者
	var target_dialogue_id: String      # 目标对话ID
	var interruption_type: int          # 打断类型
	var reason: String                  # 打断原因/借口
	var urgency_level: int              # 紧急程度 1-10
	
	func _init(p_requester: CharacterBody2D, p_target: String, 
			   p_type: int, p_reason: String, p_urgency: int = 5):
		requester = p_requester
		target_dialogue_id = p_target
		interruption_type = p_type
		reason = p_reason
		urgency_level = p_urgency

# 打断响应数据
class InterruptionResponse:
	var accepted: bool                  # 是否接受打断
	var response_type: String           # 响应类型
	var message: String                 # 响应消息
	var accepted_by: Array = []         # 接受打断的参与者
	
	func _init(p_accepted: bool, p_type: String, p_message: String):
		accepted = p_accepted
		response_type = p_type
		message = p_message

# 待处理的打断请求 {requester_name: InterruptionRequest}
var pending_requests: Dictionary = {}

# 配置参数
const INTERRUPTION_RANGE: float = 150.0      # 打断有效范围
const POLITE_WAIT_TIME: float = 30.0         # 礼貌打断等待时间（秒）
const MAX_PENDING_REQUESTS: int = 5          # 最大待处理请求数

# 信号
signal interruption_requested(request: InterruptionRequest)
signal interruption_responded(dialogue_id: String, response: InterruptionResponse)
signal interruption_succeeded(dialogue_id: String, requester_name: String)
signal interruption_rejected(dialogue_id: String, requester_name: String, reason: String)

func _ready():
	print("[DialogueInterruptionManager] 对话打断管理器已初始化")

# ============================================
# 打断请求处理
# ============================================

func request_interruption(requester: CharacterBody2D, 
						  target_character: CharacterBody2D,
						  interruption_type: int = InterruptionType.POLITE,
						  reason: String = "") -> bool:
	"""
	请求打断/插入对话
	
	参数:
		requester: 请求打断的Agent
		target_character: 目标对话中的任一参与者
		interruption_type: 打断类型
		reason: 打断原因
	
	返回:
		请求是否成功提交
	"""
	if not requester or not target_character:
		return false
	
	# 检查是否在范围内
	if not _is_in_range(requester, target_character):
		print("[DialogueInterruptionManager] %s 距离太远，无法打断" % requester.name)
		return false
	
	# 获取目标对话ID
	var target_dialogue_id = _get_character_dialogue_id(target_character)
	if target_dialogue_id.is_empty():
		print("[DialogueInterruptionManager] %s 不在对话中" % target_character.name)
		return false
	
	# 检查是否已经在对话中
	if _is_character_in_dialogue(requester):
		print("[DialogueInterruptionManager] %s 已经在对话中" % requester.name)
		return false
	
	# 检查待处理请求数量
	if pending_requests.size() >= MAX_PENDING_REQUESTS:
		print("[DialogueInterruptionManager] 待处理请求已满")
		return false
	
	# 计算紧急程度
	var urgency = _calculate_urgency(requester, interruption_type, reason)
	
	# 创建打断请求
	var request = InterruptionRequest.new(
		requester, 
		target_dialogue_id, 
		interruption_type,
		reason,
		urgency
	)
	
	pending_requests[requester.name] = request
	
	print("[DialogueInterruptionManager] %s 请求打断对话 %s (类型:%d, 紧急度:%d)" % [
		requester.name, target_dialogue_id, interruption_type, urgency
	])
	
	interruption_requested.emit(request)
	
	# 异步处理打断请求
	_process_interruption_request(request)
	
	return true

func _process_interruption_request(request: InterruptionRequest):
	"""处理打断请求"""
	
	# 获取对话参与者
	var participants = _get_dialogue_participants(request.target_dialogue_id)
	if participants.is_empty():
		pending_requests.erase(request.requester.name)
		return
	
	# 根据打断类型处理
	match request.interruption_type:
		InterruptionType.POLITE:
			await _handle_polite_interruption(request, participants)
		InterruptionType.URGENT:
			await _handle_urgent_interruption(request, participants)
		InterruptionType.CASUAL:
			await _handle_casual_interruption(request, participants)
		InterruptionType.LISTEN_ONLY:
			await _handle_listen_only(request, participants)
	
	pending_requests.erase(request.requester.name)

# ============================================
# 不同打断类型的处理
# ============================================

func _handle_polite_interruption(request: InterruptionRequest, participants: Array):
	"""处理礼貌打断 - 等待合适时机"""
	print("[DialogueInterruptionManager] 处理礼貌打断请求：%s" % request.requester.name)
	
	# 等待一段时间或当前话题结束
	await get_tree().create_timer(POLITE_WAIT_TIME).timeout
	
	# 检查请求是否还有效
	if not pending_requests.has(request.requester.name):
		return
	
	# 检查是否还在范围内
	var still_in_range = false
	for participant in participants:
		if _is_in_range(request.requester, participant):
			still_in_range = true
			break
	
	if not still_in_range:
		interruption_rejected.emit(request.target_dialogue_id, request.requester.name, "离开范围")
		return
	
	# 向参与者发送打断请求并收集响应
	var response = await _ask_participants_for_permission(request, participants)
	
	if response.accepted:
		_interruption_accepted(request, participants, response)
	else:
		interruption_rejected.emit(request.target_dialogue_id, request.requester.name, response.message)

func _handle_urgent_interruption(request: InterruptionRequest, participants: Array):
	"""处理紧急打断 - 立即插入"""
	print("[DialogueInterruptionManager] 处理紧急打断请求：%s" % request.requester.name)
	
	# 紧急打断直接询问是否可以插入
	var response = await _ask_participants_for_permission(request, participants)
	
	if response.accepted:
		_interruption_accepted(request, participants, response)
	else:
		# 紧急情况下，如果紧急度足够高，可能强制打断
		if request.urgency_level >= 8:
			print("[DialogueInterruptionManager] 紧急度高，强制打断")
			var forced_response = InterruptionResponse.new(true, "forced", "有紧急情况")
			_interruption_accepted(request, participants, forced_response)
		else:
			interruption_rejected.emit(request.target_dialogue_id, request.requester.name, response.message)

func _handle_casual_interruption(request: InterruptionRequest, participants: Array):
	"""处理随意插入 - 熟人之间"""
	print("[DialogueInterruptionManager] 处理随意插入请求：%s" % request.requester.name)
	
	# 检查与参与者的关系
	var has_good_relationship = false
	for participant in participants:
		if _check_relationship(request.requester, participant):
			has_good_relationship = true
			break
	
	if has_good_relationship:
		# 关系好，直接接受
		var response = InterruptionResponse.new(true, "casual_accepted", "是老朋友了")
		_interruption_accepted(request, participants, response)
	else:
		# 关系一般，转为礼貌打断
		await _handle_polite_interruption(request, participants)

func _handle_listen_only(request: InterruptionRequest, participants: Array):
	"""处理旁听模式"""
	print("[DialogueInterruptionManager] 处理旁听请求：%s" % request.requester.name)
	
	# 旁听通常被允许，但角色不会主动发言
	var response = InterruptionResponse.new(true, "listen_only", "允许旁听")
	
	# 设置旁听状态
	request.requester.set_meta("dialogue_listen_only", true)
	request.requester.set_meta("dialogue_id", request.target_dialogue_id)
	
	interruption_succeeded.emit(request.target_dialogue_id, request.requester.name)
	interruption_responded.emit(request.target_dialogue_id, response)

# ============================================
# 权限询问与响应处理
# ============================================

func _ask_participants_for_permission(request: InterruptionRequest, 
									   participants: Array) -> InterruptionResponse:
	"""询问参与者是否允许打断"""
	
	var accepted_by = []
	var total_weight = 0.0
	var accept_weight = 0.0
	
	for participant in participants:
		var weight = _calculate_participant_weight(participant, request)
		total_weight += weight
		
		# 模拟决策（实际应该调用LLM或基于性格规则）
		var will_accept = _simulate_acceptance_decision(participant, request)
		
		if will_accept:
			accepted_by.append(participant.name)
			accept_weight += weight
	
	# 如果接受权重超过50%，则接受打断
	var acceptance_rate = accept_weight / total_weight if total_weight > 0 else 0.0
	
	if acceptance_rate >= 0.5:
		return InterruptionResponse.new(true, "voted_accepted", 
			"%d/%d 参与者同意" % [accepted_by.size(), participants.size()])
	else:
		return InterruptionResponse.new(false, "voted_rejected",
			"%d/%d 参与者不同意" % [accepted_by.size(), participants.size()])

func _simulate_acceptance_decision(participant: CharacterBody2D, 
								   request: InterruptionRequest) -> bool:
	"""模拟参与者是否接受打断的决策"""
	
	var personality = CharacterPersonality.get_personality(participant.name)
	var base_acceptance = 0.5
	
	# 根据性格调整
	var traits = personality.get("big_five", {})
	var agreeableness = traits.get("agreeableness", 50)
	var extraversion = traits.get("extraversion", 50)
	
	# 宜人性高更容易接受
	base_acceptance += (agreeableness - 50) / 200.0
	
	# 外向性高更喜欢多人交流
	if request.interruption_type != InterruptionType.LISTEN_ONLY:
		base_acceptance += (extraversion - 50) / 200.0
	
	# 根据打断类型调整
	match request.interruption_type:
		InterruptionType.POLITE:
			base_acceptance += 0.2
		InterruptionType.URGENT:
			base_acceptance += 0.3
		InterruptionType.CASUAL:
			base_acceptance += 0.1
	
	# 根据紧急程度调整
	base_acceptance += (request.urgency_level - 5) / 20.0
	
	# 检查关系
	if _check_relationship(participant, request.requester):
		base_acceptance += 0.2
	
	# 随机因素
	base_acceptance += randf_range(-0.1, 0.1)
	
	return randf() < clamp(base_acceptance, 0.0, 1.0)

func _calculate_participant_weight(participant: CharacterBody2D, 
								   request: InterruptionRequest) -> float:
	"""计算参与者在决策中的权重"""
	# 发起者权重更高
	var dialog_service = _get_dialog_service()
	if dialog_service:
		for dialogue_id in dialog_service.active_conversations:
			var conversation = dialog_service.active_conversations[dialogue_id]
			if conversation.speaker == participant:
				return 1.5  # 发起者权重
	return 1.0  # 普通参与者权重

func _interruption_accepted(request: InterruptionRequest, 
							participants: Array, 
							response: InterruptionResponse):
	"""打断被接受后的处理"""
	
	print("[DialogueInterruptionManager] %s 的打断请求被接受" % request.requester.name)
	
	# 获取DialogService
	var dialog_service = _get_dialog_service()
	if not dialog_service:
		return
	
	# 结束原对话（如果是1对1）
	var is_one_on_one = participants.size() == 2
	
	if is_one_on_one:
		# 结束原对话，创建新的多人对话
		dialog_service.end_conversation(request.target_dialogue_id)
		
		# 创建新的对话组（包含新加入者）
		var new_participants = participants.duplicate()
		new_participants.append(request.requester)
		
		# 尝试开始群组对话
		var group_manager = get_node_or_null("/root/GroupDialogueManager")
		if group_manager:
			group_manager.try_start_group_dialogue(request.requester, new_participants)
	else:
		# 已经是多人对话，尝试加入
		var group_manager = get_node_or_null("/root/GroupDialogueManager")
		if group_manager:
			group_manager.try_join_group_dialogue(request.requester, request.target_dialogue_id)
	
	interruption_succeeded.emit(request.target_dialogue_id, request.requester.name)
	interruption_responded.emit(request.target_dialogue_id, response)

# ============================================
# 辅助函数
# ============================================

func _calculate_urgency(requester: CharacterBody2D, 
						interruption_type: int, 
						reason: String) -> int:
	"""计算打断紧急程度"""
	var base_urgency = 5
	
	match interruption_type:
		InterruptionType.URGENT:
			base_urgency = 8
		InterruptionType.POLITE:
			base_urgency = 4
		InterruptionType.CASUAL:
			base_urgency = 3
		InterruptionType.LISTEN_ONLY:
			base_urgency = 2
	
	# 根据原因调整
	if reason.find("紧急") != -1 or reason.find("重要") != -1:
		base_urgency += 2
	
	return clamp(base_urgency, 1, 10)

func _check_relationship(char1: CharacterBody2D, char2: CharacterBody2D) -> bool:
	"""检查两个角色之间的关系"""
	if not char1 or not char2:
		return false
	
	var relations1 = char1.get_meta("relations", {})
	if relations1.has(char2.name):
		var relation = relations1[char2.name]
		var strength = relation.get("strength", 0)
		return strength >= 50  # 关系强度>=50认为是好朋友
	
	return false

func _is_in_range(char1: CharacterBody2D, char2: CharacterBody2D) -> bool:
	"""检查是否在范围内"""
	if not is_instance_valid(char1) or not is_instance_valid(char2):
		return false
	return char1.global_position.distance_to(char2.global_position) <= INTERRUPTION_RANGE

func _is_character_in_dialogue(character: CharacterBody2D) -> bool:
	"""检查角色是否已经在对话中"""
	if not character:
		return false
	
	var dialog_service = _get_dialog_service()
	if dialog_service:
		return dialog_service.is_character_in_conversation(character)
	
	return false

func _get_character_dialogue_id(character: CharacterBody2D) -> String:
	"""获取角色参与的对话ID"""
	if not character:
		return ""
	
	var dialog_service = _get_dialog_service()
	if dialog_service:
		for dialogue_id in dialog_service.active_conversations:
			var conversation = dialog_service.active_conversations[dialogue_id]
			if conversation.speaker == character or conversation.listener == character:
				return dialogue_id
	
	return ""

func _get_dialogue_participants(dialogue_id: String) -> Array:
	"""获取对话的所有参与者"""
	var participants = []
	
	var dialog_service = _get_dialog_service()
	if dialog_service and dialog_service.active_conversations.has(dialogue_id):
		var conversation = dialog_service.active_conversations[dialogue_id]
		participants.append(conversation.speaker)
		participants.append(conversation.listener)
	
	return participants

func _get_dialog_service() -> DialogService:
	"""获取对话服务"""
	var dialog_manager = get_node_or_null("/root/DialogManager")
	if dialog_manager:
		return dialog_manager.dialog_service
	return null

# ============================================
# 公共接口
# ============================================

func can_interrupt(requester: CharacterBody2D, target_character: CharacterBody2D) -> bool:
	"""检查是否可以打断"""
	if not requester or not target_character:
		return false
	
	if not _is_in_range(requester, target_character):
		return false
	
	if _is_character_in_dialogue(requester):
		return false
	
	var target_dialogue_id = _get_character_dialogue_id(target_character)
	if target_dialogue_id.is_empty():
		return false
	
	return true

func get_interruption_options(requester: CharacterBody2D, 
							  target_character: CharacterBody2D) -> Array:
	"""获取可用的打断选项"""
	if not can_interrupt(requester, target_character):
		return []
	
	var options = []
	
	# 检查关系
	var has_relationship = _check_relationship(requester, target_character)
	
	options.append({
		"type": InterruptionType.POLITE,
		"name": "礼貌打断",
		"description": "等待合适时机加入对话"
	})
	
	options.append({
		"type": InterruptionType.URGENT,
		"name": "紧急打断",
		"description": "有重要事情需要立即沟通"
	})
	
	if has_relationship:
		options.append({
			"type": InterruptionType.CASUAL,
			"name": "随意加入",
			"description": "以熟人的身份自然加入"
		})
	
	options.append({
		"type": InterruptionType.LISTEN_ONLY,
		"name": "旁听",
		"description": "只旁听，不主动发言"
	})
	
	return options
