extends Node
class_name DialogService

# ============================================
# DialogService - 对话服务
# ============================================
# 管理多个并行对话的生命周期
# 协调对话内容生成和状态同步
# 集成 DialogueLifecycleManager 进行完整生命周期管理
# ============================================

# 活跃对话列表 {conversation_id: ConversationManager}
var active_conversations: Dictionary = {}

# 生命周期管理器
var lifecycle_manager: DialogueLifecycleManager

# 信号
signal conversation_started(conversation_id: String, speaker_name: String, listener_name: String)
signal conversation_ended(conversation_id: String)
signal dialog_generated(conversation_id: String, speaker_name: String, dialog_text: String)
signal conversation_state_changed(conversation_id: String, old_state: int, new_state: int)

func _ready():
	print("[DialogService] 对话服务已初始化")
	_setup_lifecycle_manager()

func _setup_lifecycle_manager():
	lifecycle_manager = DialogueLifecycleManager.new()
	lifecycle_manager.dialogue_state_changed.connect(_on_dialogue_state_changed)
	lifecycle_manager.dialogue_timeout.connect(_on_dialogue_timeout)
	lifecycle_manager.dialogue_range_exited.connect(_on_dialogue_range_exited)
	add_child(lifecycle_manager)
	print("[DialogService] 生命周期管理器已初始化")

# ============================================
# 对话管理
# ============================================

# 尝试开始对话
func try_start_conversation(speaker: CharacterBody2D, listener: CharacterBody2D) -> bool:
	if not speaker or not listener:
		print("[DialogService] 无法开始对话：说话者或听众为空")
		return false
	
	if speaker == listener:
		print("[DialogService] 无法开始对话：不能与自己对话")
		return false
	
	# 检查是否已有对话
	if is_character_in_conversation(speaker):
		print("[DialogService] %s 已经在对话中" % speaker.name)
		return false
	
	if is_character_in_conversation(listener):
		print("[DialogService] %s 已经在对话中" % listener.name)
		return false
	
	# 检查距离
	if not _is_in_dialogue_range(speaker, listener):
		print("[DialogService] %s 和 %s 距离太远，无法对话" % [speaker.name, listener.name])
		return false
	
	# 创建新对话
	var conversation = ConversationManager.new(speaker, listener)
	conversation.conversation_ended.connect(_on_conversation_ended)
	conversation.dialog_generated.connect(_on_dialog_generated)
	add_child(conversation)
	
	active_conversations[conversation.conversation_id] = conversation
	
	# 注册到生命周期管理器
	lifecycle_manager.register_dialogue(conversation.conversation_id, speaker, listener)
	
	print("[DialogService] 对话开始：%s <-> %s (ID: %s)" % [speaker.name, listener.name, conversation.conversation_id])
	conversation_started.emit(conversation.conversation_id, speaker.name, listener.name)
	
	# 启动对话
	conversation.start_conversation()
	
	# 激活对话
	lifecycle_manager.activate_dialogue(conversation.conversation_id)
	
	return true

# 结束指定对话
func end_conversation(conversation_id: String) -> void:
	if not active_conversations.has(conversation_id):
		return
	
	var conversation = active_conversations[conversation_id]
	conversation.end_conversation()
	# 注意：对话结束后会从 active_conversations 中移除

# 结束角色参与的所有对话
func end_character_conversations(character: CharacterBody2D) -> void:
	if not character:
		return
	
	var conversations_to_end = []
	for conversation_id in active_conversations:
		var conversation = active_conversations[conversation_id]
		if conversation.speaker == character or conversation.listener == character:
			conversations_to_end.append(conversation_id)
	
	for conversation_id in conversations_to_end:
		end_conversation(conversation_id)

# 清理所有对话
func cleanup_all_conversations() -> void:
	for conversation_id in active_conversations.keys():
		end_conversation(conversation_id)
	active_conversations.clear()

# ============================================
# 查询接口
# ============================================

# 获取活跃对话数量
func get_active_conversation_count() -> int:
	return active_conversations.size()

# 获取活跃对话信息列表
func get_active_conversations_info() -> Array:
	var info_list = []
	for conversation_id in active_conversations:
		var conversation = active_conversations[conversation_id]
		info_list.append({
			"id": conversation_id,
			"speaker": conversation.speaker.name if conversation.speaker else "",
			"listener": conversation.listener.name if conversation.listener else ""
		})
	return info_list

# 检查角色是否在对话中
func is_character_in_conversation(character: CharacterBody2D) -> bool:
	if not character:
		return false
	
	for conversation_id in active_conversations:
		var conversation = active_conversations[conversation_id]
		if conversation.speaker == character or conversation.listener == character:
			return true
	return false

# 获取角色的对话对象
func get_dialogue_partner(character: CharacterBody2D) -> CharacterBody2D:
	if not character:
		return null
	
	for conversation_id in active_conversations:
		var conversation = active_conversations[conversation_id]
		if conversation.speaker == character:
			return conversation.listener
		if conversation.listener == character:
			return conversation.speaker
	return null

# ============================================
# 辅助函数
# ============================================

# 检查是否在对话范围内
func _is_in_dialogue_range(char1: CharacterBody2D, char2: CharacterBody2D) -> bool:
	var max_dialog_distance = 150  # 最大对话距离（像素）
	return char1.global_position.distance_to(char2.global_position) <= max_dialog_distance

# ============================================
# 信号回调
# ============================================

func _on_conversation_ended(conversation_id: String) -> void:
	if active_conversations.has(conversation_id):
		var conversation = active_conversations[conversation_id]
		
		# 通知生命周期管理器结束对话
		lifecycle_manager.end_dialogue(conversation_id, "conversation_ended")
		
		conversation.queue_free()
		active_conversations.erase(conversation_id)
		print("[DialogService] 对话结束：%s" % conversation_id)
		conversation_ended.emit(conversation_id)

func _on_dialog_generated(speaker_name: String, dialog_text: String) -> void:
	# 找到对应的对话ID并转发信号
	for conversation_id in active_conversations:
		var conversation = active_conversations[conversation_id]
		if conversation.speaker and conversation.speaker.name == speaker_name:
			# 记录消息到生命周期管理器
			lifecycle_manager.record_message(conversation_id, speaker_name, dialog_text)
			dialog_generated.emit(conversation_id, speaker_name, dialog_text)
			break

# 生命周期管理器信号回调
func _on_dialogue_state_changed(conversation_id: String, old_state: int, new_state: int) -> void:
	conversation_state_changed.emit(conversation_id, old_state, new_state)
	
	# 如果对话变为结束状态，结束对应的 ConversationManager
	if new_state == DialogueLifecycleManager.DialogueState.ENDED:
		if active_conversations.has(conversation_id):
			var conversation = active_conversations[conversation_id]
			if conversation.is_active:
				conversation.end_conversation()

func _on_dialogue_timeout(conversation_id: String) -> void:
	print("[DialogService] 对话超时：%s" % conversation_id)
	# 超时处理由生命周期管理器完成

func _on_dialogue_range_exited(conversation_id: String, character_name: String) -> void:
	print("[DialogService] 对话 %s：%s 离开范围" % [conversation_id, character_name])
