extends Node
class_name DialogueLifecycleManager

# ============================================
# DialogueLifecycleManager - 对话生命周期管理器
# ============================================
# 管理对话的完整生命周期：开始 → 进行 → 结束
# 协调对话状态与 Agent 状态的同步
# 处理对话被打断、离开等异常情况
# ============================================

# 对话状态枚举
enum DialogueState {
	INITIATING,      # 正在发起（等待对方响应）
	ACTIVE,          # 活跃进行中
	PAUSED,          # 暂停（一方离开范围）
	ENDING,          # 正在结束
	ENDED            # 已结束
}

# 对话数据类
class DialogueData:
	var conversation_id: String
	var speaker: CharacterBody2D
	var listener: CharacterBody2D
	var state: DialogueState
	var start_time: float
	var last_interaction_time: float
	var message_count: int = 0
	var topic: String = ""
	var emotional_valence: float = 0.0  # -1.0 ~ 1.0
	
	func _init(p_id: String, p_speaker: CharacterBody2D, p_listener: CharacterBody2D):
		conversation_id = p_id
		speaker = p_speaker
		listener = p_listener
		state = DialogueState.INITIATING
		start_time = Time.get_unix_time_from_system()
		last_interaction_time = start_time
	
	func update_state(new_state: DialogueState):
		state = new_state
		last_interaction_time = Time.get_unix_time_from_system()
	
	func add_message():
		message_count += 1
		last_interaction_time = Time.get_unix_time_from_system()
	
	func get_duration() -> float:
		return Time.get_unix_time_from_system() - start_time
	
	func is_timed_out(timeout_seconds: float = 300.0) -> bool:
		# 5分钟无交互视为超时
		return Time.get_unix_time_from_system() - last_interaction_time > timeout_seconds

# 对话数据存储 {conversation_id: DialogueData}
var dialogue_data_map: Dictionary = {}

# 配置参数
const DIALOGUE_RANGE: float = 150.0           # 对话有效范围（像素）
const DIALOGUE_CHECK_INTERVAL: float = 1.0    # 对话状态检查间隔（秒）
const MAX_MESSAGES_PER_DIALOGUE: int = 10     # 单次对话最大消息数
const DIALOGUE_TIMEOUT: float = 300.0         # 对话超时时间（秒）

# 信号
signal dialogue_state_changed(conversation_id: String, old_state: int, new_state: int)
signal dialogue_message_added(conversation_id: String, speaker_name: String, message: String)
signal dialogue_timeout(conversation_id: String)
signal dialogue_range_exited(conversation_id: String, character_name: String)

# 定时器
var check_timer: Timer

func _ready():
	print("[DialogueLifecycleManager] 对话生命周期管理器已初始化")
	_setup_timer()

func _setup_timer():
	check_timer = Timer.new()
	check_timer.wait_time = DIALOGUE_CHECK_INTERVAL
	check_timer.timeout.connect(_on_check_timer_timeout)
	add_child(check_timer)
	check_timer.start()

# ============================================
# 生命周期管理
# ============================================

# 注册新对话
func register_dialogue(conversation_id: String, speaker: CharacterBody2D, listener: CharacterBody2D) -> DialogueData:
	var dialogue_data = DialogueData.new(conversation_id, speaker, listener)
	dialogue_data_map[conversation_id] = dialogue_data
	
	print("[DialogueLifecycleManager] 注册对话：%s (%s <-> %s)" % [conversation_id, speaker.name, listener.name])
	
	# 连接对话结束信号
	_connect_to_dialog_service(conversation_id)
	
	return dialogue_data

# 激活对话（对方接受后调用）
func activate_dialogue(conversation_id: String) -> bool:
	if not dialogue_data_map.has(conversation_id):
		return false
	
	var dialogue_data = dialogue_data_map[conversation_id]
	var old_state = dialogue_data.state
	
	if old_state == DialogueState.INITIATING:
		dialogue_data.update_state(DialogueState.ACTIVE)
		dialogue_state_changed.emit(conversation_id, old_state, DialogueState.ACTIVE)
		print("[DialogueLifecycleManager] 对话激活：%s" % conversation_id)
		return true
	
	return false

# 记录消息
func record_message(conversation_id: String, speaker_name: String, message: String):
	if not dialogue_data_map.has(conversation_id):
		return
	
	var dialogue_data = dialogue_data_map[conversation_id]
	dialogue_data.add_message()
	
	# 分析情感倾向（简化版）
	var sentiment = _analyze_sentiment(message)
	dialogue_data.emotional_valence = dialogue_data.emotional_valence * 0.7 + sentiment * 0.3
	
	dialogue_message_added.emit(conversation_id, speaker_name, message)
	
	print("[DialogueLifecycleManager] 对话 %s 添加消息 [%d/%d]：%s" % [
		conversation_id, 
		dialogue_data.message_count, 
		MAX_MESSAGES_PER_DIALOGUE,
		speaker_name
	])
	
	# 检查是否达到最大消息数
	if dialogue_data.message_count >= MAX_MESSAGES_PER_DIALOGUE:
		print("[DialogueLifecycleManager] 对话 %s 达到最大消息数，准备结束" % conversation_id)
		_end_dialogue_gracefully(conversation_id)

# 结束对话
func end_dialogue(conversation_id: String, reason: String = "normal"):
	if not dialogue_data_map.has(conversation_id):
		return
	
	var dialogue_data = dialogue_data_map[conversation_id]
	var old_state = dialogue_data.state
	
	if old_state == DialogueState.ENDED:
		return
	
	dialogue_data.update_state(DialogueState.ENDED)
	dialogue_state_changed.emit(conversation_id, old_state, DialogueState.ENDED)
	
	# 记录对话总结到记忆系统
	_record_dialogue_summary(dialogue_data, reason)
	
	print("[DialogueLifecycleManager] 对话结束：%s (原因: %s, 时长: %.1f秒, 消息数: %d)" % [
		conversation_id,
		reason,
		dialogue_data.get_duration(),
		dialogue_data.message_count
	])
	
	# 清理数据（延迟清理，确保其他系统有时间处理）
	await get_tree().create_timer(5.0).timeout
	dialogue_data_map.erase(conversation_id)

# 强制结束所有对话
func end_all_dialogues(reason: String = "system"):
	var ids = dialogue_data_map.keys()
	for conversation_id in ids:
		end_dialogue(conversation_id, reason)

# ============================================
# 状态检查与异常处理
# ============================================

func _on_check_timer_timeout():
	_check_dialogue_states()

func _check_dialogue_states():
	var current_time = Time.get_unix_time_from_system()
	var dialogues_to_end = []
	
	for conversation_id in dialogue_data_map:
		var dialogue_data = dialogue_data_map[conversation_id]
		
		# 跳过已结束的对话
		if dialogue_data.state == DialogueState.ENDED:
			continue
		
		# 检查超时
		if dialogue_data.is_timed_out(DIALOGUE_TIMEOUT):
			print("[DialogueLifecycleManager] 对话 %s 超时" % conversation_id)
			dialogues_to_end.append({"id": conversation_id, "reason": "timeout"})
			dialogue_timeout.emit(conversation_id)
			continue
		
		# 检查参与者是否还在范围内
		if dialogue_data.state == DialogueState.ACTIVE:
			if not _check_participants_in_range(dialogue_data):
				# 一方离开范围，暂停对话
				if dialogue_data.state != DialogueState.PAUSED:
					var old_state = dialogue_data.state
					dialogue_data.update_state(DialogueState.PAUSED)
					dialogue_state_changed.emit(conversation_id, old_state, DialogueState.PAUSED)
					dialogue_range_exited.emit(conversation_id, _get_absent_participant(dialogue_data))
					print("[DialogueLifecycleManager] 对话 %s 暂停：一方离开范围" % conversation_id)
			else:
				# 双方都在范围内，恢复对话
				if dialogue_data.state == DialogueState.PAUSED:
					var old_state = dialogue_data.state
					dialogue_data.update_state(DialogueState.ACTIVE)
					dialogue_state_changed.emit(conversation_id, old_state, DialogueState.ACTIVE)
					print("[DialogueLifecycleManager] 对话 %s 恢复：双方回到范围" % conversation_id)
	
	# 执行结束操作
	for item in dialogues_to_end:
		end_dialogue(item.id, item.reason)

func _check_participants_in_range(dialogue_data: DialogueData) -> bool:
	if not is_instance_valid(dialogue_data.speaker) or not is_instance_valid(dialogue_data.listener):
		return false
	
	var distance = dialogue_data.speaker.global_position.distance_to(dialogue_data.listener.global_position)
	return distance <= DIALOGUE_RANGE

func _get_absent_participant(dialogue_data: DialogueData) -> String:
	if not is_instance_valid(dialogue_data.speaker):
		return dialogue_data.speaker.name if dialogue_data.speaker else "unknown"
	if not is_instance_valid(dialogue_data.listener):
		return dialogue_data.listener.name if dialogue_data.listener else "unknown"
	
	var distance = dialogue_data.speaker.global_position.distance_to(dialogue_data.listener.global_position)
	if distance > DIALOGUE_RANGE:
		return "双方"
	return ""

func _end_dialogue_gracefully(conversation_id: String):
	# 优雅地结束对话（给双方一个结束语的机会）
	if not dialogue_data_map.has(conversation_id):
		return
	
	var dialogue_data = dialogue_data_map[conversation_id]
	
	# 设置结束状态
	var old_state = dialogue_data.state
	dialogue_data.update_state(DialogueState.ENDING)
	dialogue_state_changed.emit(conversation_id, old_state, DialogueState.ENDING)
	
	# 延迟后真正结束
	await get_tree().create_timer(3.0).timeout
	end_dialogue(conversation_id, "max_messages")

# ============================================
# 数据记录与记忆
# ============================================

func _record_dialogue_summary(dialogue_data: DialogueData, reason: String):
	# 记录对话总结到记忆系统
	if MemorySystem.instance:
		var speaker = dialogue_data.speaker
		var listener = dialogue_data.listener
		
		if not is_instance_valid(speaker) or not is_instance_valid(listener):
			return
		
		var duration = dialogue_data.get_duration()
		var summary = "与%s进行了一段对话（%.0f秒，%d条消息）" % [
			listener.name if speaker == dialogue_data.speaker else speaker.name,
			duration,
			dialogue_data.message_count
		]
		
		# 根据情感倾向添加描述
		if dialogue_data.emotional_valence > 0.3:
			summary += "，氛围愉快"
		elif dialogue_data.emotional_valence < -0.3:
			summary += "，氛围有些沉重"
		
		# 添加到双方记忆
		MemorySystem.instance.add_memory(speaker, summary, MemorySystem.MemoryType.INTERACTION, 3)
		MemorySystem.instance.add_memory(listener, summary, MemorySystem.MemoryType.INTERACTION, 3)
		
		# 记录社交互动
		MemorySystem.instance.record_interaction(
			speaker.name,
			listener.name,
			"DIALOGUE",
			{
				"duration": duration,
				"message_count": dialogue_data.message_count,
				"emotional_valence": dialogue_data.emotional_valence,
				"reason": reason
			}
		)

func _analyze_sentiment(message: String) -> float:
	# 简化版情感分析
	# 返回 -1.0 (负面) 到 1.0 (正面)
	var positive_words = ["好", "棒", "开心", "喜欢", "谢谢", "不错", "很好", "太好了", "哈哈"]
	var negative_words = ["不好", "讨厌", "烦", "累", "难过", "抱歉", "对不起", "糟", "差"]
	
	var score = 0.0
	var count = 0
	
	for word in positive_words:
		if message.find(word) != -1:
			score += 0.2
			count += 1
	
	for word in negative_words:
		if message.find(word) != -1:
			score -= 0.2
			count += 1
	
	if count == 0:
		return 0.0
	
	return clamp(score, -1.0, 1.0)

# ============================================
# 查询接口
# ============================================

func get_dialogue_data(conversation_id: String) -> DialogueData:
	return dialogue_data_map.get(conversation_id)

func get_active_dialogue_count() -> int:
	var count = 0
	for dialogue_data in dialogue_data_map.values():
		if dialogue_data.state != DialogueState.ENDED:
			count += 1
	return count

func is_dialogue_active(conversation_id: String) -> bool:
	if not dialogue_data_map.has(conversation_id):
		return false
	var dialogue_data = dialogue_data_map[conversation_id]
	return dialogue_data.state == DialogueState.ACTIVE

func get_character_dialogue_state(character: CharacterBody2D) -> DialogueState:
	if not character:
		return DialogueState.ENDED
	
	for dialogue_data in dialogue_data_map.values():
		if dialogue_data.speaker == character or dialogue_data.listener == character:
			return dialogue_data.state
	
	return DialogueState.ENDED

# ============================================
# 信号连接
# ============================================

func _connect_to_dialog_service(conversation_id: String):
	# 连接到 DialogService 的信号
	var dialog_manager = get_node_or_null("/root/DialogManager")
	if dialog_manager and dialog_manager.dialog_service:
		if not dialog_manager.dialog_service.dialog_generated.is_connected(_on_dialog_generated):
			dialog_manager.dialog_service.dialog_generated.connect(_on_dialog_generated)

func _on_dialog_generated(conversation_id: String, speaker_name: String, dialog_text: String):
	# 转发到消息记录
	record_message(conversation_id, speaker_name, dialog_text)
