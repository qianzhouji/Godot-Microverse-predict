extends RefCounted
class_name ConversationManager

# 对话参与者
var speaker: CharacterBody2D
var listener: CharacterBody2D
var conversation_id: String
var is_active: bool = false

# 对话相关的场景引用
var dialog_bubble_scene = preload("res://scene/UI/DialogBubble.tscn")
var chat_history_scene = preload("res://scene/ChatHistory.tscn")

# AI相关脚本引用
var MemoryManager = preload("res://script/ai/memory/MemoryManager.gd")
var BackgroundStoryManager = preload("res://script/ai/background_story/BackgroundStoryManager.gd")
var DynamicPersonality = preload("res://script/ai/DynamicPersonality.gd")

# HTTP请求对象
var http_request: HTTPRequest

# 信号
signal conversation_ended(conversation_id: String)
signal dialog_generated(speaker_name: String, dialog_text: String)

func _init(p_speaker: CharacterBody2D, p_listener: CharacterBody2D):
	speaker = p_speaker
	listener = p_listener
	conversation_id = generate_conversation_id()
	is_active = true
	
	# 确保说话者有ChatHistory节点
	if not speaker.has_node("ChatHistory"):
		var chat_history = chat_history_scene.instantiate()
		speaker.add_child(chat_history)
	
	# 确保听众也有ChatHistory节点
	if not listener.has_node("ChatHistory"):
		var chat_history = chat_history_scene.instantiate()
		listener.add_child(chat_history)

func generate_conversation_id() -> String:
	return "%s_%s_%d" % [speaker.name, listener.name, Time.get_unix_time_from_system()]

# 开始对话
func start_conversation():
	if not is_active:
		return
	
	print("[ConversationManager] 开始对话：%s <-> %s" % [speaker.name, listener.name])
	await generate_dialog()

# 结束对话
func end_conversation():
	if not is_active:
		return
	
	print("[ConversationManager] 结束对话：%s" % conversation_id)
	
	# 保存聊天记录
	if speaker and speaker.has_node("ChatHistory"):
		var history_node = speaker.get_node("ChatHistory")
		history_node.save_history()
	
	if listener and listener.has_node("ChatHistory"):
		var history_node = listener.get_node("ChatHistory")
		history_node.save_history()
	
	# 清理HTTP请求
	if http_request and is_instance_valid(http_request):
		http_request.queue_free()
	
	is_active = false
	conversation_ended.emit(conversation_id)

# 生成对话内容
func generate_dialog():
	if not is_active:
		return
	
	print("\n[对话系统] 开始生成对话")
	print("[对话系统] 说话者：", speaker.name)
	print("[对话系统] 听众：", listener.name)
	
	# 获取说话者和听众的人设
	var speaker_personality = CharacterPersonality.get_personality(speaker.name)
	var listener_personality = CharacterPersonality.get_personality(listener.name)
	
	# 获取说话者的详细状态信息（包括记忆）
	var speaker_status = get_character_status_info(speaker)
	
	var company_basic_info = get_company_basic_info()
	var company_info = get_company_employees_info()
	
	# 获取说话者的当前任务
	var speaker_tasks = get_character_tasks(speaker)
	
	# 获取之前的聊天记录
	var chat_history = ""
	if speaker.has_node("ChatHistory"):
		var history_node = speaker.get_node("ChatHistory")
		chat_history = history_node.get_recent_conversation_with(listener.name, 5)
	
	# 构建对话prompt（不包含听众的记忆信息）
	var prompt = build_dialog_prompt(speaker_personality, listener_personality, 
									 speaker_status, "", company_basic_info, company_info, 
									 speaker_tasks, chat_history)
	
	print("[对话系统] 生成的prompt：\n", prompt)
	
	# 使用APIManager生成对话
	var api_manager = null
	var main_loop = Engine.get_main_loop() as SceneTree
	if main_loop and main_loop.root:
		api_manager = main_loop.root.get_node("APIManager")
	
	if not api_manager:
		print("[ConversationManager] 无法获取APIManager")
		return
	
	http_request = await api_manager.generate_dialog(prompt)
	
	# 连接回调函数
	if http_request and not http_request.request_completed.is_connected(_on_request_completed):
		http_request.request_completed.connect(_on_request_completed)

# 构建对话提示
func build_dialog_prompt(speaker_personality: Dictionary, listener_personality: Dictionary,
						 speaker_status: String, listener_status: String, 
						 company_basic_info: String, company_info: String, speaker_tasks: String, 
						 chat_history: String) -> String:
	
	# 获取故事背景和社会规则
	var background_prompt = BackgroundStoryManager.generate_background_prompt()
	
	var prompt = "你是一个员工，名字是%s。你的职位是：%s。你的性格是：%s。你的说话风格是：%s。" % [
		speaker.name,
		speaker_personality["position"],
		speaker_personality["personality"],
		speaker_personality["speaking_style"]
	]
	
	# ========== 添加说话者心理学特质 ==========
	if speaker_personality.has("thinking_style"):
		prompt += "\n你的思维方式是：" + speaker_personality["thinking_style"]
	
	if speaker_personality.has("attribution_style"):
		prompt += "\n你的归因风格是：" + speaker_personality["attribution_style"]
	
	if speaker_personality.has("decision_style"):
		prompt += "\n你的决策风格是：" + speaker_personality["decision_style"]
	
	if speaker_personality.has("cognitive_bias"):
		prompt += "\n你可能受到以下认知偏误影响：" + str(speaker_personality["cognitive_bias"])
	
	if speaker_personality.has("emotional_intelligence"):
		prompt += "\n你的情商水平（1-10分）：" + str(speaker_personality["emotional_intelligence"])
	
	if speaker_personality.has("stress_response"):
		prompt += "\n你在压力下的反应模式是：" + speaker_personality["stress_response"]
	
	if speaker_personality.has("motivation_type"):
		prompt += "\n你的主要动机类型是：" + speaker_personality["motivation_type"]
	
	if speaker_personality.has("mbti_type"):
		prompt += "\n你的MBTI性格类型是：" + speaker_personality["mbti_type"]
	
	if speaker_personality.has("big_five"):
		var big_five = speaker_personality["big_five"]
		prompt += "\n你的大五人格特质（0-100分）："
		prompt += "开放性" + str(big_five.get("openness", 50)) + "、"
		prompt += "尽责性" + str(big_five.get("conscientiousness", 50)) + "、"
		prompt += "外向性" + str(big_five.get("extraversion", 50)) + "、"
		prompt += "宜人性" + str(big_five.get("agreeableness", 50)) + "、"
		prompt += "神经质" + str(big_five.get("neuroticism", 50))
	
	if speaker_personality.has("defense_mechanisms"):
		prompt += "\n你的心理防御机制包括：" + str(speaker_personality["defense_mechanisms"])
	
	if speaker_personality.has("core_beliefs"):
		prompt += "\n你的核心信念包括：" + str(speaker_personality["core_beliefs"])
	
	if speaker_personality.has("attachment_style"):
		prompt += "\n你的依恋风格是：" + speaker_personality["attachment_style"]
	
	if speaker_personality.has("communication_style"):
		prompt += "\n你的沟通风格是：" + speaker_personality["communication_style"]
	
	# 添加故事背景和社会规则
	if not background_prompt.is_empty():
		prompt += "\n\n" + background_prompt
	
	prompt += company_basic_info
	prompt += company_info
	
	# 添加说话者状态信息（包括自己的记忆）
	prompt += speaker_status
	
	# 添加当前任务信息
	prompt += speaker_tasks
	
	# 添加听众基本信息（不包括对方的记忆和详细状态）
	prompt += "\n\n你正在与%s交谈。%s的职位是：%s。%s的性格是：%s。" % [
		listener.name,
		listener.name,
		listener_personality["position"],
		listener.name,
		listener_personality["personality"]
	]
	
	# 注意：不再添加听众的详细状态信息（包括记忆），因为这些是对方的私人信息
	
	# 添加聊天记录
	if chat_history != "":
		prompt += "\n\n你们之前的对话记录：\n" + chat_history
	
	# 添加对话指导
	prompt += "\n\n请根据你的性格、心理学特质、当前状态、心情、任务和与对方的关系，生成一段自然的对话。"
	prompt += "\n注意："
	prompt += "\n- 体现出你的性格特点和说话风格"
	prompt += "\n- 你的心理学特质（思维方式、归因风格、沟通风格、依恋风格等）会深刻影响你的表达方式和内容"
	prompt += "\n- 考虑你当前的心情和健康状况"
	prompt += "\n- 根据你们的关系程度调整亲密度（受依恋风格影响）"
	prompt += "\n- 如果有相关记忆，可以提及"
	prompt += "\n- 可以结合你的当前任务来聊天,当前突发的记忆优先级大于任务。"
	prompt += "\n- 保持对话自然流畅，不要过于正式"
	prompt += "\n- 对话长度控制在1-3句话，30字以内"
	prompt += "\n- 只返回你要说的话，不要加任何描述、动作或其他内容"
	prompt += "\n- 像真人一样直接说话，不要有'你说：'这样的前缀"
	
	return prompt

# HTTP请求完成回调
func _on_request_completed(result, response_code, headers, body):
	if not is_active:
		return
	
	print("\n[对话系统] 收到API响应")
	print("[对话系统] 响应状态码：", response_code)
	
	if result != HTTPRequest.RESULT_SUCCESS:
		print("[对话系统] HTTP请求失败，错误码：", result)
		return
	

	
	var response = JSON.parse_string(body.get_string_from_utf8())
	var dialog_text = ""
	
	# 获取设置
	var settings_manager = null
	var main_loop = Engine.get_main_loop() as SceneTree
	if main_loop and main_loop.root:
		settings_manager = main_loop.root.get_node("SettingsManager")
	
	if not settings_manager:
		print("[ConversationManager] 无法获取SettingsManager")
		return
	var current_settings = settings_manager.get_settings()
	
	# 使用APIConfig统一解析响应
	dialog_text = APIConfig.parse_response(current_settings.api_type, response)
	if dialog_text == "":
		print("[对话系统] 响应解析失败")
		return
	
	# 创建对话气泡并显示对话内容
	var dialog_bubble = dialog_bubble_scene.instantiate()
	Engine.get_main_loop().root.add_child(dialog_bubble)
	# 设置目标节点为说话的角色，这样气泡会自动跟随
	dialog_bubble.target_node = speaker
	dialog_bubble.show_dialog(dialog_text)
	print("[对话系统] 生成的对话：", dialog_text)
	
	# 保存对话记录到双方的ChatHistory中
	# 格式化消息内容："说话者: 消息内容"
	var formatted_message = speaker.name + ": " + dialog_text
	
	if speaker.has_node("ChatHistory"):
		var speaker_history = speaker.get_node("ChatHistory")
		speaker_history.add_message(listener.name, formatted_message)
		print("说话者聊天记录保存成功")
	
	if listener.has_node("ChatHistory"):
		var listener_history = listener.get_node("ChatHistory")
		listener_history.add_message(speaker.name, formatted_message)
		print("听众聊天记录保存成功")
	
	# 发出对话生成信号
	dialog_generated.emit(speaker.name, dialog_text)
	
	# 让对方角色回复
	if listener and is_active:
		# 交换说话者和听众的角色
		var temp = speaker
		speaker = listener
		listener = temp
		# 生成对方的回复
		await generate_dialog()

# 获取学校师生信息字符串
func get_company_employees_info() -> String:
	var info = "\n\n学校师生名单："
	
	# 遍历CharacterPersonality中的所有角色配置
	for character_name in CharacterPersonality.PERSONALITY_CONFIG:
		var personality = CharacterPersonality.PERSONALITY_CONFIG[character_name]
		info += "\n- " + character_name + "：" + personality["position"]
	
	info += "\n注意：在生成任何内容时，只能提及以上列出的师生，不要创造新的角色名字。"
	return info

# 获取学校基本信息字符串
func get_company_basic_info() -> String:
	return "\n\n学校基本信息：\n这是一所初中学校，有教室、食堂、走廊和体育馆。教室分为北侧的主教学区和南侧的小组讨论区，食堂提供午餐，体育馆可以进行体育活动。"

# 获取角色详细状态信息
func get_character_status_info(character: CharacterBody2D) -> String:
	if not character:
		return "\n当前状态信息不可用。"
	
	# 从角色节点获取数据
	var mood = character.get_meta("mood", "普通")
	var health = character.get_meta("health", "良好")
	var relations = character.get_meta("relations", {})
	
	var status_info = "\n\n【当前个人状态】"
	status_info += "\n😊 心情：%s" % mood
	status_info += "\n❤️ 健康：%s" % health
	
	# 使用MemoryManager获取格式化的记忆信息
	status_info += "\n\n【记忆信息】"
	var memory_manager = MemoryManager.new()
	var memory_text = memory_manager.get_formatted_memories_for_prompt(character)
	# 移除开头的换行符，因为你们已经添加了标题
	if memory_text.begins_with("\n\n记忆信息："):
		memory_text = memory_text.substr(8)  # 移除"\n\n记忆信息："
	status_info += memory_text
	
	status_info += "\n\n【情感关系】"
	if relations.size() > 0:
		for person_name in relations:
			var relation = relations[person_name]
			var emotion_type = relation["type"] if relation.has("type") else "未知"
			var strength = relation["strength"] if relation.has("strength") else 0
			status_info += "\n- 与%s：%s (强度：%d)" % [person_name, emotion_type, strength]
	else:
		status_info += "\n- 暂无特殊情感关系"
	
	return status_info

# 获取角色任务信息
func get_character_tasks(character: CharacterBody2D) -> String:
	var speaker_tasks = ""
	var speaker_metadata = character.get_meta("character_data", {})
	var tasks = speaker_metadata.get("tasks", [])
	if tasks.size() > 0:
		# 获取未完成的任务
		var active_tasks = []
		for task in tasks:
			if not task.get("completed", false):
				active_tasks.append(task)
		
		if active_tasks.size() > 0:
			# 按优先级排序，获取最重要的任务
			active_tasks.sort_custom(func(a, b): return a.priority > b.priority)
			var current_task = active_tasks[0]
			speaker_tasks = "\n\n你当前最重要的任务是：%s（渴望程度：%d）" % [current_task.description, current_task.priority]
			if active_tasks.size() > 1:
				speaker_tasks += "\n你还有其他%d个待完成的任务。" % (active_tasks.size() - 1)
	
	return speaker_tasks
