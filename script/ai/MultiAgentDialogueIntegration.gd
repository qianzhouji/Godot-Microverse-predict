extends Node
class_name MultiAgentDialogueIntegration

# ============================================
# MultiAgentDialogueIntegration - 多Agent对话集成器
# ============================================
# 整合所有多Agent对话功能：
# - 1对1对话（DialogService）
# - 群组对话（GroupDialogueManager）
# - 打断/插入（DialogueInterruptionManager）
# - 上下文同步（DialogueContextManager）
# ============================================

# 单例
static var instance: MultiAgentDialogueIntegration

# 子管理器引用
var group_dialogue_manager: GroupDialogueManager = null
var interruption_manager: DialogueInterruptionManager = null
var context_manager: DialogueContextManager = null

# 配置参数
const AUTO_FORM_GROUP_THRESHOLD: float = 100.0   # 自动形成群组的距离阈值
const AUTO_FORM_GROUP_MIN_COUNT: int = 3         # 自动形成群组的最小人数

# 信号
signal dialogue_mode_changed(character_name: String, new_mode: String)
signal multi_dialogue_started(dialogue_id: String, participants: Array)
signal multi_dialogue_ended(dialogue_id: String, reason: String)

func _ready():
	instance = self
	print("[MultiAgentDialogueIntegration] 多Agent对话集成器初始化")
	
	# 创建子管理器
	_setup_managers()
	
	# 连接信号
	_connect_signals()

func _setup_managers():
	"""设置子管理器"""
	
	# 群组对话管理器
	group_dialogue_manager = GroupDialogueManager.new()
	group_dialogue_manager.name = "GroupDialogueManager"
	add_child(group_dialogue_manager)
	print("[MultiAgentDialogueIntegration] GroupDialogueManager已创建")
	
	# 打断管理器
	interruption_manager = DialogueInterruptionManager.new()
	interruption_manager.name = "DialogueInterruptionManager"
	add_child(interruption_manager)
	print("[MultiAgentDialogueIntegration] DialogueInterruptionManager已创建")
	
	# 上下文管理器
	context_manager = DialogueContextManager.new()
	context_manager.name = "DialogueContextManager"
	add_child(context_manager)
	print("[MultiAgentDialogueIntegration] DialogueContextManager已创建")

func _connect_signals():
	"""连接信号"""
	
	# 群组对话信号
	if group_dialogue_manager:
		group_dialogue_manager.group_dialogue_started.connect(_on_group_dialogue_started)
		group_dialogue_manager.group_dialogue_ended.connect(_on_group_dialogue_ended)
		group_dialogue_manager.group_message_generated.connect(_on_group_message_generated)
	
	# 打断信号
	if interruption_manager:
		interruption_manager.interruption_succeeded.connect(_on_interruption_succeeded)
		interruption_manager.interruption_rejected.connect(_on_interruption_rejected)

# ============================================
# 统一对话接口
# ============================================

func start_dialogue(initiator: CharacterBody2D,
					target: CharacterBody2D,
					dialogue_range: int = GroupDialogueManager.DialogueRange.MEDIUM,
					topic: String = "") -> bool:
	"""
	统一对话开始接口（全部使用群组对话，范围由发起人决定）

	参数:
		initiator: 发起者
		target: 目标（可以是单个角色或角色数组）
		dialogue_range: 对话范围 (SMALL=悄悄话30px, MEDIUM=普通对话150px, LARGE=公开讨论300px)
		topic: 讨论主题

	返回:
		是否成功开始对话
	"""

	# 如果target是数组，处理为群组对话
	if target is Array:
		var participants = target as Array[CharacterBody2D]
		if not participants.has(initiator):
			participants.append(initiator)
		return start_group_dialogue(initiator, participants, topic, dialogue_range)

	# 2人对话也使用群组对话系统
	return start_group_dialogue(initiator, [initiator, target], topic, dialogue_range, target)

func start_group_dialogue(initiator: CharacterBody2D,
						  participants: Array[CharacterBody2D],
						  topic: String = "",
						  dialogue_range: int = GroupDialogueManager.DialogueRange.MEDIUM,
						  primary_target: CharacterBody2D = null) -> bool:
	"""开始群组对话（支持2人及以上）"""

	if not group_dialogue_manager:
		push_error("[MultiAgentDialogueIntegration] GroupDialogueManager未初始化")
		return false

	var success = group_dialogue_manager.try_start_group_dialogue(initiator, participants, topic, dialogue_range, primary_target)

	if success:
		var dialogue_id = group_dialogue_manager.get_character_group_dialogue(initiator)
		var participant_names = []
		for p in participants:
			participant_names.append(p.name)

		var range_name = "对话"
		match dialogue_range:
			GroupDialogueManager.DialogueRange.SMALL:
				range_name = "悄悄话"
			GroupDialogueManager.DialogueRange.MEDIUM:
				range_name = "普通对话"
			GroupDialogueManager.DialogueRange.LARGE:
				range_name = "公开讨论"

		print("[MultiAgentDialogueIntegration] %s开始：%s (参与者: %s)" % [
			range_name, dialogue_id, ", ".join(participant_names)
		])

		# 创建上下文
		if context_manager:
			context_manager.create_context(dialogue_id, participant_names)

		for p in participants:
			dialogue_mode_changed.emit(p.name, "dialogue")

		multi_dialogue_started.emit(dialogue_id, participant_names)

	return success

func request_join_dialogue(requester: CharacterBody2D, 
						   target_dialogue: Variant,
						   interruption_type: int = 0) -> bool:
	"""
	请求加入对话
	
	参数:
		requester: 请求加入者
		target_dialogue: 目标对话ID或目标角色
		interruption_type: 打断类型（使用DialogueInterruptionManager.InterruptionType）
	"""
	
	if not interruption_manager:
		return false
	
	# 如果传入的是角色，找到其对话
	var target_character = target_dialogue
	if target_dialogue is String:
		target_character = _find_character_in_dialogue(target_dialogue)
	
	if not target_character:
		return false
	
	return interruption_manager.request_interruption(
		requester, 
		target_character, 
		interruption_type
	)

func leave_dialogue(character: CharacterBody2D) -> bool:
	"""离开当前对话"""

	# 检查是否在群组对话中（现在所有对话都是群组对话）
	if group_dialogue_manager and group_dialogue_manager.is_character_in_group_dialogue(character):
		var dialogue_id = group_dialogue_manager.get_character_group_dialogue(character)
		return group_dialogue_manager.leave_group_dialogue(character, dialogue_id)

	return false

# ============================================
# 智能对话形成
# ============================================

func check_auto_form_group(center_character: CharacterBody2D) -> bool:
	"""
	检查是否自动形成群组对话
	当附近有足够多的人在互相接近时，自动形成群组
	"""
	
	var nearby_characters = _get_nearby_characters(center_character, AUTO_FORM_GROUP_THRESHOLD)
	
	if nearby_characters.size() + 1 >= AUTO_FORM_GROUP_MIN_COUNT:
		# 检查这些人是否已经在对话中
		var available_characters = [center_character]
		for char in nearby_characters:
			if not is_character_in_any_dialogue(char):
				available_characters.append(char)
		
		if available_characters.size() >= AUTO_FORM_GROUP_MIN_COUNT:
			# 自动形成群组对话
			print("[MultiAgentDialogueIntegration] 自动形成群组对话，参与者：%d人" % available_characters.size())
			return start_group_dialogue(center_character, available_characters, "自由讨论")
	
	return false

func suggest_dialogue_opportunities(character: CharacterBody2D) -> Array:
	"""
	为角色建议对话机会
	
	返回:
		可对话目标列表，包含优先级和建议类型
	"""
	
	var opportunities = []
	
	# 获取附近角色
	var nearby = _get_nearby_characters(character, 200.0)
	
	for other in nearby:
		if is_character_in_any_dialogue(other):
			# 对方在对话中，检查是否可以加入
			if interruption_manager and interruption_manager.can_interrupt(character, other):
				var options = interruption_manager.get_interruption_options(character, other)
				opportunities.append({
					"target": other,
					"type": "join",
					"priority": 3,
					"options": options
				})
		else:
			# 对方空闲，可以开始新对话
			var priority = _calculate_dialogue_priority(character, other)
			opportunities.append({
				"target": other,
				"type": "start",
				"priority": priority,
				"suggested_type": "normal" if priority > 5 else "casual"
			})
	
	# 按优先级排序
	opportunities.sort_custom(func(a, b): return a.priority > b.priority)
	
	return opportunities

# ============================================
# 查询接口
# ============================================

func is_character_in_any_dialogue(character: CharacterBody2D) -> bool:
	"""检查角色是否在任何对话中（现在全部使用群组对话）"""
	if not character:
		return false
	return group_dialogue_manager and group_dialogue_manager.is_character_in_group_dialogue(character)

func get_character_dialogue_mode(character: CharacterBody2D) -> String:
	"""获取角色的对话模式（现在只有群组对话）"""
	if not character:
		return "none"
	if group_dialogue_manager and group_dialogue_manager.is_character_in_group_dialogue(character):
		return "dialogue"
	return "none"

func get_dialogue_participants(dialogue_id: String) -> Array:
	"""获取对话的所有参与者"""
	if group_dialogue_manager:
		var group_data = group_dialogue_manager.get_group_dialogue_data(dialogue_id)
		if group_data:
			return group_data.participants
	return []

func get_dialogue_context_for_prompt(character: CharacterBody2D, max_messages: int = 8) -> String:
	"""获取对话上下文用于Prompt"""
	
	if not context_manager:
		return ""
	
	var dialogue_id = _get_dialogue_id_for_character(character)
	if dialogue_id.is_empty():
		return ""
	
	return context_manager.get_context_for_prompt(dialogue_id, character.name, max_messages)

# ============================================
# 辅助函数
# ============================================

func _determine_dialogue_type(initiator: CharacterBody2D, target: CharacterBody2D) -> String:
	"""自动判断对话类型"""
	
	# 检查关系亲密度
	var intimacy = _get_relationship_intimacy(initiator, target)
	
	if intimacy >= 80:
		return "normal"  # 亲密关系，普通对话
	elif intimacy >= 50:
		return "normal"  # 一般关系，普通对话
	else:
		return "normal"  # 默认普通对话

func _get_relationship_intimacy(char1: CharacterBody2D, char2: CharacterBody2D) -> int:
	"""获取关系亲密度"""
	if not char1 or not char2:
		return 0
	
	var relations = char1.get_meta("relations", {})
	if relations.has(char2.name):
		return relations[char2.name].get("strength", 0)
	
	return 0

func _calculate_dialogue_priority(char1: CharacterBody2D, char2: CharacterBody2D) -> int:
	"""计算对话优先级"""
	
	var priority = 5  # 基础优先级
	
	# 根据关系调整
	var intimacy = _get_relationship_intimacy(char1, char2)
	priority += intimacy / 20  # 0-5分
	
	# 根据距离调整（越近优先级越高）
	if is_instance_valid(char1) and is_instance_valid(char2):
		var distance = char1.global_position.distance_to(char2.global_position)
		if distance < 50:
			priority += 2
		elif distance < 100:
			priority += 1
	
	return int(priority)

func _get_nearby_characters(center: CharacterBody2D, radius: float) -> Array:
	"""获取附近的角色"""
	
	var nearby = []
	var all_characters = get_tree().get_nodes_in_group("character")
	
	for char in all_characters:
		if char == center:
			continue
		if is_instance_valid(char) and is_instance_valid(center):
			if center.global_position.distance_to(char.global_position) <= radius:
				nearby.append(char)
	
	return nearby

func _get_dialogue_id_for_character(character: CharacterBody2D) -> String:
	"""获取角色参与的对话ID（现在全部使用群组对话）"""
	if group_dialogue_manager:
		return group_dialogue_manager.get_character_group_dialogue(character)
	return ""

func _find_character_in_dialogue(dialogue_id: String) -> CharacterBody2D:
	"""在对话中查找任一角色"""
	
	var participants = get_dialogue_participants(dialogue_id)
	if not participants.is_empty():
		return participants[0]
	
	return null

# ============================================
# 信号回调
# ============================================

func _on_group_dialogue_started(dialogue_id: String, participant_names: Array):
	print("[MultiAgentDialogueIntegration] 群组对话开始：%s" % dialogue_id)

func _on_group_dialogue_ended(dialogue_id: String, reason: String):
	print("[MultiAgentDialogueIntegration] 群组对话结束：%s (原因: %s)" % [dialogue_id, reason])
	
	# 清理上下文
	if context_manager:
		context_manager.remove_context(dialogue_id)
	
	multi_dialogue_ended.emit(dialogue_id, reason)

func _on_group_message_generated(dialogue_id: String, speaker_name: String, content: String):
	# 同步到上下文管理器
	if context_manager:
		context_manager.add_message(dialogue_id, speaker_name, content)

func _on_interruption_succeeded(dialogue_id: String, requester_name: String):
	print("[MultiAgentDialogueIntegration] 打断成功：%s 加入 %s" % [requester_name, dialogue_id])

func _on_interruption_rejected(dialogue_id: String, requester_name: String, reason: String):
	print("[MultiAgentDialogueIntegration] 打断被拒绝：%s -> %s (原因: %s)" % [
		requester_name, dialogue_id, reason
	])
