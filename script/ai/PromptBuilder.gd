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
    var template = _load_template("natural_decision_template.txt")
    if template.is_empty():
        push_error("[PromptBuilder] 无法加载V2决策模板")
        return ""
    
    # 获取Agent数据
    var agent_name = agent.character.name
    var personality = CharacterPersonality.get_personality(agent_name)
    
    # 构建变量映射
    var variables = {}
    
    # 基础信息
    variables["agent_name"] = agent_name
    variables["basic_info"] = _build_basic_info(personality)
    
    # 当前状态
    variables["current_time"] = TimingSystem.instance.format_time(TimingSystem.instance.current_game_time)
    variables["current_room"] = perception.get("current_room", "未知")
    variables["current_period"] = TimelineState.instance.current_period
    variables["nearby_agents"] = _build_nearby_agents(perception.get("nearby_agents", []))
    
    # 时间约束
    variables["time_constraints"] = _build_behavior_constraints()
    
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
    var template = _load_template("dialogue_reply_template.txt")
    if template.is_empty():
        return ""
    
    var agent_name = agent.character.name
    var personality = CharacterPersonality.get_personality(agent_name)
    
    var variables = {}
    variables["role_description"] = _get_role_description(personality)
    variables["agent_name"] = agent_name
    variables["basic_info"] = _build_basic_info(personality)
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
# 清除缓存（用于热更新）
# ============================================
static func clear_cache():
    template_cache.clear()
    print("[PromptBuilder] 模板缓存已清除")
