extends Node
class_name PromptBuilder

# ============================================
# Prompt构建器
# 从模板文件加载并填充变量
# ============================================

const PROMPTS_DIR = "res://prompts/"
const FRAGMENTS_DIR = "res://prompts/fragments/"

# 缓存加载的模板
static var template_cache: Dictionary = {}

# ============================================
# V2主入口：构建自然语言决策Prompt
# ============================================
static func build_natural_decision_prompt(agent: AIAgent, perception: Dictionary) -> String:
	# V2: 加载自然语言决策模板
	var template = _load_template("natural_decision_template.md")
	if template.is_empty():
		push_error("[PromptBuilder] 无法加载V2决策模板")
		return ""
	
	# 获取Agent数据
	var agent_name = agent.character.name
	var personality = CharacterPersonality.get_personality(agent_name)
	
	# 构建变量映射
	var variables = {}
	
	# 角色描述
	variables["role_description"] = _get_role_description(personality)
	variables["agent_name"] = agent_name
	
	# 基本信息和人格
	variables["basic_info"] = _build_basic_info(personality)
	variables["big_five_traits"] = _build_big_five_traits(personality)
	variables["mental_health_status"] = _build_mental_health_status(personality)
	variables["functioning_level"] = _build_functioning_level(personality)
	variables["specific_abilities"] = _build_specific_abilities(personality)
	
	# 认知计算参数
	variables["cognitive_parameters"] = _build_cognitive_parameters(personality)
	
	# 当前状态（使用TimeUtils统一获取）
	variables["current_time"] = TimeUtils.get_formatted_current_time()
	variables["current_room"] = perception.get("current_room", "未知")
	variables["current_period"] = TimeUtils.get_current_period()
	variables["behavior_constraints"] = _build_behavior_constraints()
	
	# 故事背景和社会规则
	variables["story_background"] = _build_story_background()
	variables["social_rules"] = _build_social_rules()
	
	# 周围环境信息
	variables["environment_info"] = _build_environment_info(perception)
	
	# 感知到的情境参数
	variables["perceived_params"] = _build_perceived_params(agent, perception.get("current_room", ""))
	
	# 记忆（简化版）
	variables["memories"] = _build_memories(agent)
	
	# 当前活动状态
	variables["activity_status"] = _build_activity_status(agent)
	
	# 填充模板
	return _fill_template(template, variables)

# V2: 构建附近角色列表
static func _build_nearby_agents(agents: Array) -> String:
	if agents.is_empty():
		return "无"
	
	var names = []
	for agent in agents:
		names.append(agent.get("name", "未知"))
	
	return "、".join(names)

# ============================================
# 构建对话回复Prompt
# ============================================
static func build_dialogue_reply_prompt(agent: AIAgent, dialogue_context: Dictionary) -> String:
	var template = _load_template("dialogue_reply_template.md")
	if template.is_empty():
		return ""
	
	var agent_name = agent.character.name
	var personality = CharacterPersonality.get_personality(agent_name)
	
	var variables = {}
	variables["role_description"] = _get_role_description(personality)
	variables["agent_name"] = agent_name
	variables["basic_info"] = _build_basic_info(personality)
	variables["story_background"] = _build_story_background()
	variables["social_rules"] = _build_social_rules()
	variables["big_five_traits"] = _build_big_five_traits(personality)
	variables["mood_status"] = _build_mood_status(agent)
	variables["dialogue_initiator"] = dialogue_context.get("initiator", "")
	variables["current_speaker"] = dialogue_context.get("current_speaker", "")
	variables["dialogue_range"] = dialogue_context.get("range", "中范围")
	variables["dialogue_duration"] = dialogue_context.get("duration", "0分钟")
	variables["dialogue_history"] = _build_dialogue_history(dialogue_context.get("history", []))
	variables["heard_content"] = dialogue_context.get("content", "")
	variables["relationship_with_speaker"] = _build_relationship(agent, dialogue_context.get("current_speaker", ""))
	variables["topic_interest"] = dialogue_context.get("topic_interest", "一般")
	variables["time_constraints"] = TimelineState.instance.get_constraints().get("description", "")
	
	return _fill_template(template, variables)

# ============================================
# 辅助方法：构建各部分内容
# ============================================

static func _get_role_description(personality: Dictionary) -> String:
	var role_type = personality.get("role_type", "student")
	if role_type == "teacher":
		return "教师"
	return "学生"

static func _build_basic_info(personality: Dictionary) -> String:
	var info = []
	
	if personality.has("position"):
		info.append("- 身份：" + personality.position)
	if personality.has("personality"):
		info.append("- 性格：" + personality.personality)
	if personality.has("speaking_style"):
		info.append("- 说话风格：" + personality.speaking_style)
	
	# 人口学信息
	if personality.has("demographics"):
		var demo = personality.demographics
		if demo.has("age"):
			info.append("- 年龄：" + str(demo.age) + "岁")
		if demo.has("gender"):
			info.append("- 性别：" + demo.gender)
		if demo.has("grade"):
			info.append("- 年级：" + demo.grade)
	
	return "\n".join(info)

static func _build_big_five_traits(personality: Dictionary) -> String:
	if not personality.has("big_five"):
		return "暂无人格特质数据"
	
	var bf = personality.big_five
	return "开放性%d、尽责性%d、外向性%d、宜人性%d、神经质%d" % [
		bf.get("openness", 50),
		bf.get("conscientiousness", 50),
		bf.get("extraversion", 50),
		bf.get("agreeableness", 50),
		bf.get("neuroticism", 50)
	]

static func _build_mental_health_status(personality: Dictionary) -> String:
	if not personality.has("initial_depression"):
		return "心理健康状况良好"
	
	var dep = personality.initial_depression
	var status = []
	
	if dep.has("phq9_baseline"):
		status.append("PHQ-9基线分数：" + str(dep.phq9_baseline))
	if dep.has("severity_level"):
		status.append("(" + dep.severity_level + ")")
	if dep.has("symptom_duration_weeks"):
		status.append("症状持续" + str(dep.symptom_duration_weeks) + "周")
	
	return " ".join(status)

static func _build_functioning_level(personality: Dictionary) -> String:
	if not personality.has("functioning_level"):
		return "暂无功能水平数据"
	
	var fl = personality.functioning_level
	return "学业功能%d、社交功能%d、日常生活%d" % [
		fl.get("academic_functioning", 50),
		fl.get("social_functioning", 50),
		fl.get("daily_living", 50)
	]

static func _build_specific_abilities(personality: Dictionary) -> String:
	if not personality.has("specific_ability"):
		return "暂无能力特长数据"
	
	var abilities = []
	var sa = personality.specific_ability
	
	if sa.has("chinese"): abilities.append("语文" + str(sa.chinese))
	if sa.has("math"): abilities.append("数学" + str(sa.math))
	if sa.has("english"): abilities.append("英语" + str(sa.english))
	
	return "、".join(abilities)

static func _build_cognitive_parameters(personality: Dictionary) -> String:
	if not personality.has("cognitive_mechanism"):
		return "使用默认认知参数"
	
	var cm = personality.cognitive_mechanism
	var params = []
	
	if cm.has("p_base"):
		params.append("- 离开阈值 (p_base)：%.0f%%" % (cm.p_base * 100))
	if cm.has("eta_s"):
		params.append("- 初始奖赏感知权重 (η_s)：%.0f%%" % (cm.eta_s * 100))
	if cm.has("eta_a"):
		params.append("- 衰减率感知权重 (η_a)：%.0f%%" % (cm.eta_a * 100))
	if cm.has("beta_effort"):
		params.append("- 努力敏感性 (β_effort)：%.2f" % cm.beta_effort)
	
	return "\n".join(params)

static func _build_behavior_constraints() -> String:
	var constraints = TimelineState.instance.get_constraints()
	return constraints.get("description", "无特殊约束")

static func _build_story_background() -> String:
	# 获取当前场景的故事背景
	# 先初始化背景管理器（如果未初始化）
	BackgroundStoryManager.initialize("School")
	
	# 使用 generate_background_prompt 获取完整的背景信息
	var background_prompt = BackgroundStoryManager.generate_background_prompt()
	
	if background_prompt.is_empty():
		return "【学校名称】阳光中学\n\n【学校简介】一所普通的初中学校。"
	
	return background_prompt

static func _build_social_rules() -> String:
	# 获取当前场景的社会规则
	# 先初始化背景管理器（如果未初始化）
	BackgroundStoryManager.initialize("School")
	
	# 使用 get_all_rules 获取社会规则列表
	var rules = BackgroundStoryManager.get_all_rules()
	
	if rules.is_empty():
		return "【校规校纪】\n1. 遵守校规校纪"
	
	var rules_text = ["【校规校纪】"]
	for i in range(rules.size()):
		rules_text.append("%d. %s" % [i + 1, rules[i]])
	
	return "\n".join(rules_text)

static func _build_perceived_params(agent: AIAgent, room_name: String) -> String:
	if room_name.is_empty():
		return "不在任何房间内"
	
	var personality = CharacterPersonality.get_personality(agent.character.name)
	var is_depression = personality.get("role_type", "") == "depression_risk_student"
	
	var params = PerceptionSystem.get_perceived_params(
		agent.character.name,
		room_name,
		is_depression
	)
	
	return PerceptionSystem.get_belief_description(agent.character.name, room_name, is_depression)

static func _build_activity_status(agent: AIAgent) -> String:
	match agent.current_state:
		AIAgent.AgentState.IDLE:
			return "空闲"
		AIAgent.AgentState.IN_DIALOGUE:
			return "正在对话中"
		AIAgent.AgentState.IN_ACTIVITY:
			return "正在进行" + agent.current_activity
		_:
			return "其他状态"

static func _build_environment_info(perception: Dictionary) -> String:
	var info = []
	
	# 当前房间
	var room = perception.get("current_room", "未知")
	info.append("当前位置：" + room)
	
	# 附近角色详情
	var nearby = perception.get("nearby_agents", [])
	if nearby.is_empty():
		info.append("附近角色：无")
	else:
		var agents_desc = []
		for agent in nearby:
			var name = agent.get("name", "未知")
			var activity = agent.get("activity", "")
			if activity.is_empty():
				agents_desc.append(name)
			else:
				agents_desc.append(name + "(" + activity + ")")
		info.append("附近角色：" + "、".join(agents_desc))
	
	# 可见行为
	var behaviors = perception.get("visible_behaviors", [])
	if not behaviors.is_empty():
		info.append("可见行为：" + "、".join(behaviors))
	
	# 可听内容
	var audible = perception.get("audible_contents", [])
	if not audible.is_empty():
		info.append("可听内容：" + "、".join(audible))
	
	return "\n".join(info)

static func _build_memories(agent: AIAgent) -> String:
	# TODO: 从记忆系统获取真实记忆
	# 暂时返回简化版本
	return "- 近期活动：正常参与学校生活\n- 社交关系：与同学保持正常交往"

static func _build_mood_status(agent: AIAgent) -> String:
	# TODO: 从DynamicPersonality获取当前心情
	return "心情一般"

static func _build_dialogue_history(history: Array) -> String:
	if history.is_empty():
		return "（对话刚开始）"
	
	var lines = []
	for item in history:
		lines.append(item.speaker + "：" + item.content)
	
	return "\n".join(lines)

static func _build_relationship(agent: AIAgent, other_name: String) -> String:
	# TODO: 从情感关系系统获取
	return "普通同学"

# ============================================
# 模板加载和填充
# ============================================

static func _load_template(filename: String) -> String:
	var path = PROMPTS_DIR + filename
	
	# 检查缓存
	if template_cache.has(path):
		return template_cache[path]
	
	# 加载文件
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("[PromptBuilder] 无法加载模板：" + path)
		return ""
	
	var content = file.get_as_text()
	file.close()
	
	# 缓存
	template_cache[path] = content
	
	return content

static func _fill_template(template: String, variables: Dictionary) -> String:
	var result = template
	
	for key in variables.keys():
		var placeholder = "{{" + key + "}}"
		var value = str(variables[key])
		result = result.replace(placeholder, value)
	
	return result

# ============================================
# 对话系统Prompt构建（新）
# ============================================

static func build_initiate_dialogue_prompt(agent: AIAgent, target_info: Dictionary) -> String:
	"""
	构建发起对话决策Prompt
	
	参数:
	    agent: 发起者Agent
	    target_info: 目标信息 {target_name, target_room, target_medium_range}
	"""
	var agent_name = agent.character.name
	var personality = CharacterPersonality.get_personality(agent_name)
	
	var prompt = "你现在想要发起一场对话。\n\n"
	prompt += "你的信息：\n"
	prompt += "- 名字：%s\n" % agent_name
	prompt += "- 身份：%s\n" % personality.get("position", "学生")
	prompt += "- 性格：%s\n" % personality.get("personality", "普通")
	prompt += "- 说话风格：%s\n" % personality.get("speaking_style", "自然")
	prompt += "\n"
	
	if target_info.has("target_name"):
		prompt += "你想与 %s 对话。\n" % target_info.target_name
	
	if target_info.has("target_room"):
		prompt += "目标位置：%s\n" % target_info.target_room
	
	prompt += "\n请决定：\n"
	prompt += "1. 对话范围：悄悄话(私密)/普通对话(小群体)/广播(公开)\n"
	prompt += "2. 讨论主题（可选）\n"
	prompt += "3. 初始消息内容\n"
	prompt += "\n请以JSON格式返回：\n"
	prompt += '{"range_type": 0/1/2, "topic": "主题", "initial_message": "消息内容"}'
	
	return prompt

static func build_join_dialogue_decision_prompt(agent: AIAgent, dialogue_info: Dictionary) -> String:
	"""
	构建是否加入对话的决策Prompt
	
	参数:
	    agent: 决策Agent
	    dialogue_info: 对话信息 {dialogue_id, initiator, participants, range_type, topic}
	"""
	var agent_name = agent.character.name
	var personality = CharacterPersonality.get_personality(agent_name)
	
	var prompt = "你注意到附近有一场对话正在进行。\n\n"
	prompt += "你的信息：\n"
	prompt += "- 名字：%s\n" % agent_name
	prompt += "- 性格：%s\n" % personality.get("personality", "普通")
	prompt += "\n"
	
	prompt += "对话信息：\n"
	prompt += "- 发起人：%s\n" % dialogue_info.get("initiator", "未知")
	prompt += "- 参与者：%s\n" % ", ".join(dialogue_info.get("participants", []))
	prompt += "- 类型：%s\n" % dialogue_info.get("range_type_name", "普通对话")
	
	if dialogue_info.has("topic") and not dialogue_info.topic.is_empty():
		prompt += "- 主题：%s\n" % dialogue_info.topic
	
	prompt += "\n请决定是否加入这场对话。\n"
	prompt += "考虑因素：你的性格、与参与者的关系、对话题的兴趣、当前状态。\n"
	prompt += "\n只回答：加入/不加入\n"
	
	return prompt

static func build_dialogue_response_prompt(agent: AIAgent, 
										   dialogue_history: String,
										   other_participants: Array[String],
										   range_type_name: String,
										   topic: String = "") -> String:
	"""
	构建对话回应Prompt（供AIAgent.generate_dialogue_message使用）
	
	参数:
	    agent: 发言Agent
	    dialogue_history: 对话历史
	    other_participants: 其他参与者
	    range_type_name: 对话范围名称
	    topic: 讨论主题
	"""
	var agent_name = agent.character.name
	var personality = CharacterPersonality.get_personality(agent_name)
	
	var prompt = "你正在参与一场%s。\n\n" % range_type_name
	prompt += "你的信息：\n"
	prompt += "- 名字：%s\n" % agent_name
	prompt += "- 身份：%s\n" % personality.get("position", "学生")
	prompt += "- 性格：%s\n" % personality.get("personality", "普通")
	prompt += "- 说话风格：%s\n" % personality.get("speaking_style", "自然")
	
	if not topic.is_empty():
		prompt += "\n讨论主题：%s\n" % topic
	
	if not other_participants.is_empty():
		prompt += "其他参与者：%s\n" % ", ".join(other_participants)
	
	if not dialogue_history.is_empty():
		prompt += "\n对话历史：\n%s\n" % dialogue_history
	
	prompt += "\n现在轮到你发言。\n"
	prompt += "要求：\n"
	prompt += "- 保持自然，像真人一样说话\n"
	prompt += "- 可以回应其他人的观点\n"
	prompt += "- 对话长度控制在1-3句话，50字以内\n"
	prompt += "- 只返回你要说的话，不要加任何前缀或解释\n"
	prompt += "- 不要重复之前说过的话\n"
	
	return prompt

static func build_teacher_select_speaker_prompt(teacher_agent: AIAgent, 
												 requesting_students: Array[String]) -> String:
	"""
	构建教师选择发言者的Prompt
	
	参数:
	    teacher_agent: 教师Agent
	    requesting_students: 请求发言的学生列表
	"""
	var teacher_name = teacher_agent.character.name
	var personality = CharacterPersonality.get_personality(teacher_name)
	
	var prompt = "你是%s，正在上课。\n" % teacher_name
	prompt += "身份：%s\n" % personality.get("position", "教师")
	prompt += "教学风格：%s\n\n" % personality.get("speaking_style", "严谨")
	
	prompt += "以下学生请求发言：\n"
	for student in requesting_students:
		prompt += "- %s\n" % student
	
	prompt += "\n请从中选择一位学生发言。\n"
	prompt += "考虑因素：学生的参与度、问题的相关性、课堂平衡。\n"
	prompt += "\n只返回你选择的学生名字。\n"
	
	return prompt

# ============================================
# 清除缓存（用于热更新）
# ============================================
static func clear_cache():
	template_cache.clear()
	print("[PromptBuilder] 模板缓存已清除")
