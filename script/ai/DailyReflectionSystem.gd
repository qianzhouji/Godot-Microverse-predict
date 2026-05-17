extends Node
class_name DailyReflectionSystem

# 每日反思与认知机制动态调整系统
# 职责：
# 1. 每日结束时自动触发反思
# 2. 基于当日记忆和静态人设进行LLM分析
# 3. 动态调整四项认知计算机制参数
# 4. 完成完整的PHQ-9评估

# 严重程度与基础调整幅度映射
const SEVERITY_TO_MAGNITUDE = {
    1: 0.01,  # 轻微: ±1%
    2: 0.03,  # 轻度: ±3%
    3: 0.05,  # 中度: ±5%
    4: 0.08,  # 重度: ±8%
    5: 0.12   # 严重: ±12%
}

# PHQ-9九项症状
const PHQ9_ITEMS = [
    "对事物几乎没有兴趣或愉悦感",
    "感到沮丧、抑郁或绝望",
    "入睡困难、睡眠不安或睡眠过多",
    "感到疲倦或精力不足",
    "食欲不振或暴饮暴食",
    "觉得自己很失败或让自己或家人失望",
    "难以集中注意力",
    "动作或说话缓慢，或相反地烦躁不安",
    "有伤害自己或自杀的念头"
]

# ============================================
# 主入口：执行每日反思
# ============================================
static func conduct_daily_reflection(character: Node) -> Dictionary:
    """
    执行完整的每日反思流程
    
    参数:
        character: 角色节点
    
    返回:
        反思结果字典，包含反思报告、参数调整、PHQ-9评估
    """
    if not character:
        push_error("[DailyReflectionSystem] character为null")
        return {}
    
    print("[DailyReflectionSystem] %s 开始每日反思..." % character.name)
    
    # 步骤1: 收集当日记忆
    var daily_memories = _collect_daily_memories(character)
    if daily_memories.is_empty():
        print("[DailyReflectionSystem] %s 当日无记忆，跳过反思" % character.name)
        return {}
    
    # 步骤2: 反思分析（LLM）
    var reflection_report = await _analyze_reflection(character, daily_memories)
    if reflection_report.is_empty():
        push_error("[DailyReflectionSystem] 反思分析失败")
        return {}
    
    # 步骤3: 认知参数调整决策（LLM）
    var adjustment_decision = await _decide_cognitive_adjustments(character, reflection_report)
    
    # 步骤4: 计算调整幅度并应用
    var applied_adjustments = _apply_cognitive_adjustments(character, adjustment_decision)
    
    # 步骤5: PHQ-9完整评估（LLM）
    var phq9_assessment = await _conduct_phq9_assessment(character, reflection_report)
    
    # 步骤6: 更新抑郁水平
    _update_depression_level(character, phq9_assessment)
    
    # 步骤7: 记录反思记忆
    _record_reflection_memory(character, reflection_report, applied_adjustments, phq9_assessment)
    
    # 步骤8: 输出到日志文件
    var result = {
        "reflection_report": reflection_report,
        "adjustments": applied_adjustments,
        "phq9_assessment": phq9_assessment,
        "timestamp": Time.get_unix_time_from_system()
    }
    
    # 调用Logger输出每日反思日志
    _log_daily_reflection(character, result)
    
    print("[DailyReflectionSystem] %s 每日反思完成" % character.name)
    return result

# ============================================
# 输出每日反思到日志文件
# ============================================
static func _log_daily_reflection(character: Node, result: Dictionary) -> void:
    """将每日反思结果输出到日志文件"""
    var logger = _get_logger()
    if logger:
        logger.log_daily_reflection(character.name, result)
        
        # 同时记录当前认知参数到认知参数日志
        var current_traits = DynamicPersonality.get_dynamic_traits(character)
        logger.log_cognitive_params(character.name, current_traits, "每日反思后记录")

static func _get_logger() -> Node:
    """获取Logger节点"""
    # 尝试从场景树获取
    var tree = Engine.get_main_loop()
    if tree:
        var root = tree.get_root()
        if root:
            var logger = root.get_node_or_null("/root/Logger")
            if logger:
                return logger
    return null

# ============================================
# 步骤1: 收集当日记忆
# ============================================
static func _collect_daily_memories(character: Node) -> Array:
    """
    收集角色当日的所有记忆
    """
    var all_memories = []
    if MemorySystem.instance:
        all_memories = MemorySystem.instance.get_character_memories(character)
    else:
        print("[DailyReflectionSystem] MemorySystem 未初始化，无法获取记忆")
    var daily_memories = []
    
    var current_time = Time.get_unix_time_from_system()
    var one_day_ago = current_time - 86400  # 24小时前
    
    for memory in all_memories:
        if memory.timestamp >= one_day_ago:
            daily_memories.append(memory)
    
    # 按时间排序
    daily_memories.sort_custom(func(a, b): return a.timestamp < b.timestamp)
    
    return daily_memories

# ============================================
# 步骤2: 反思分析（LLM）
# ============================================
static func _analyze_reflection(character: Node, memories: Array) -> Dictionary:
    """
    使用LLM分析当日经历，生成反思报告
    """
    var personality = CharacterPersonality.get_personality(character.name)
    var current_traits = DynamicPersonality.get_dynamic_traits(character)
    
    # 构建Prompt
    var prompt = _build_reflection_prompt(character, personality, current_traits, memories)
    
    # 调用LLM（这里使用简化的模拟，实际应调用APIManager）
    # 注意：由于是static函数，需要通过APIManager.instance调用
    if APIManager.instance:
        var http_request = await APIManager.instance.generate_dialog(prompt, character.name)
        
        # 等待响应
        var result = await http_request.request_completed
        
        if result[0] == HTTPRequest.RESULT_SUCCESS:
            var response = JSON.parse_string(result[3].get_string_from_utf8())
            var content = _parse_llm_response(response)
            return _parse_reflection_content(content)
    
    # 降级方案：返回简化报告
    return _generate_fallback_reflection(character, memories)

static func _build_reflection_prompt(character: Node, personality: Dictionary, 
                                     traits: Dictionary, memories: Array) -> String:
    """
    构建反思分析的Prompt
    """
    var prompt = "你是%s，%s。\n\n" % [character.name, personality.get("position", "学生")]
    
    prompt += "【你的性格特点】\n%s\n\n" % personality.get("personality", "")
    
    prompt += "【你当前的心理状态】\n"
    prompt += "- 当日抑郁水平: %.0f%%\n" % (traits.get("daily_depression_level", 0.5) * 100)
    prompt += "- 离开阈值(p_base): %.0f%%\n" % (traits.get("p_base", 0.5) * 100)
    prompt += "- 初始奖赏感知权重(η_s): %.0f%%\n" % (traits.get("eta_s", 0.5) * 100)
    prompt += "- 衰减率感知权重(η_a): %.0f%%\n" % (traits.get("eta_a", 0.5) * 100)
    prompt += "- 努力敏感性(β_effort): %.0f%%\n\n" % (traits.get("beta_effort", 0.5) * 100)
    
    prompt += "【你今天的经历】\n"
    if memories.is_empty():
        prompt += "（今天没有特别的经历）\n"
    else:
        for memory in memories:
            prompt += "- %s\n" % memory.text
    
    prompt += "\n请进行深度自我反思，以第一人称\"我\"回答：\n"
    prompt += "1. 今天你经历的主要情绪主题是什么？（如：挫败感、孤独感、成就感等）\n"
    prompt += "2. 哪些事件对你影响最大？为什么？\n"
    prompt += "3. 这些经历如何影响你的认知模式？\n"
    prompt += "   - 对环境的整体预期（乐观/悲观）\n"
    prompt += "   - 对努力的看法（值得/不值得）\n"
    prompt += "   - 对奖赏的敏感度（提高/降低）\n"
    prompt += "   - 对时间压力的感知（焦虑/放松）\n"
    prompt += "\n请以JSON格式输出：\n"
    prompt += '{"emotional_theme": "...", "key_events": [{"event": "...", "impact": "高/中/低", "psychological_effect": "..."}], '
    prompt += '"cognitive_changes": {"environment_expectation": "...", "effort_attitude": "...", "reward_sensitivity": "...", "time_pressure": "..."}}'
    
    return prompt

static func _parse_llm_response(response) -> String:
    """
    解析LLM响应，提取内容
    """
    if not response:
        return ""
    
    # 根据API类型解析
    if response.has("choices") and response.choices.size() > 0:
        return response.choices[0].message.content
    
    return ""

static func _parse_reflection_content(content: String) -> Dictionary:
    """
    解析反思内容的JSON
    """
    # 尝试提取JSON部分
    var json_start = content.find("{")
    var json_end = content.rfind("}")
    
    if json_start >= 0 and json_end > json_start:
        var json_str = content.substr(json_start, json_end - json_start + 1)
        var result = JSON.parse_string(json_str)
        if result:
            return result
    
    # 解析失败，返回空字典
    return {}

static func _generate_fallback_reflection(character: Node, memories: Array) -> Dictionary:
    """
    生成简化的降级反思报告（当LLM调用失败时）
    """
    var positive_count = 0
    var negative_count = 0
    
    for memory in memories:
        var text = memory.text.to_lower()
        if "成功" in text or "开心" in text or "表扬" in text:
            positive_count += 1
        elif "失败" in text or "沮丧" in text or "批评" in text:
            negative_count += 1
    
    var emotional_theme = "平静"
    if negative_count > positive_count:
        emotional_theme = "挫败和沮丧"
    elif positive_count > negative_count:
        emotional_theme = "积极和满足"
    
    return {
        "emotional_theme": emotional_theme,
        "key_events": [{"event": "今日经历", "impact": "中", "psychological_effect": "基于事件性质"}],
        "cognitive_changes": {
            "environment_expectation": "基于情绪主题",
            "effort_attitude": "基于情绪主题",
            "reward_sensitivity": "基于情绪主题",
            "time_pressure": "基于情绪主题"
        }
    }

# ============================================
# 步骤3: 认知参数调整决策（LLM）
# ============================================
static func _decide_cognitive_adjustments(character: Node, reflection: Dictionary) -> Dictionary:
    """
    使用LLM决定四项认知参数的调整方向和严重程度
    """
    var current_traits = DynamicPersonality.get_dynamic_traits(character)
    
    var prompt = "基于以下反思结果，判断四项认知计算机制参数的调整方向。\n\n"
    prompt += "【反思结果】\n"
    prompt += "情绪主题: %s\n" % reflection.get("emotional_theme", "")
    prompt += "关键事件: %s\n" % JSON.stringify(reflection.get("key_events", []))
    prompt += "认知变化: %s\n\n" % JSON.stringify(reflection.get("cognitive_changes", {}))
    
    prompt += "【当前参数值】\n"
    prompt += "- 离开阈值(p_base): %.0f%%\n" % (current_traits.get("p_base", 0.5) * 100)
    prompt += "- 初始奖赏感知权重(η_s): %.0f%%\n" % (current_traits.get("eta_s", 0.5) * 100)
    prompt += "- 衰减率感知权重(η_a): %.0f%%\n" % (current_traits.get("eta_a", 0.5) * 100)
    prompt += "- 努力敏感性(β_effort): %.0f%%\n\n" % (current_traits.get("beta_effort", 0.5) * 100)
    
    prompt += "【参数含义】\n"
    prompt += "- p_base: 对环境平均奖赏率的估计（高=乐观，低=悲观）\n"
    prompt += "- η_s: 对初始奖赏的敏感度（高=容易被初始印象影响）\n"
    prompt += "- η_a: 对奖赏衰减的感知（高=容易觉得\"不值了\"）\n"
    prompt += "- β_effort: 努力成本敏感度（高=回避努力，抑郁核心指标）\n\n"
    
    prompt += "请判断每个参数的调整方向（↑增加 ↓减少 →不变）和严重程度（1-5）。\n"
    prompt += "以JSON格式输出：\n"
    prompt += '{"adjustments": [{"parameter": "p_base", "direction": "↑/↓/→", "severity": 1-5, "reason": "..."}, ...], '
    prompt += '"overall_assessment": "整体评估"}'
    
    # 调用LLM（简化实现）
    # 实际应调用APIManager
    
    # 降级方案：基于情绪主题生成调整决策
    return _generate_fallback_adjustment(character, reflection)

static func _generate_fallback_adjustment(character: Node, reflection: Dictionary) -> Dictionary:
    """
    生成降级的调整决策（当LLM调用失败时）
    """
    var emotional_theme = reflection.get("emotional_theme", "")
    var is_negative = emotional_theme.contains("挫败") or emotional_theme.contains("沮丧") or emotional_theme.contains("孤独")
    var is_positive = emotional_theme.contains("积极") or emotional_theme.contains("满足") or emotional_theme.contains("成就")
    
    var adjustments = []
    
    if is_negative:
        adjustments = [
            {"parameter": "p_base", "direction": "↓", "severity": 3, "reason": "负面事件导致悲观预期"},
            {"parameter": "eta_s", "direction": "↓", "severity": 2, "reason": "对初始奖赏的敏感度降低"},
            {"parameter": "eta_a", "direction": "↑", "severity": 3, "reason": "更容易觉得事情不值得继续"},
            {"parameter": "beta_effort", "direction": "↑", "severity": 4, "reason": "负面事件增加努力成本感知"}
        ]
    elif is_positive:
        adjustments = [
            {"parameter": "p_base", "direction": "↑", "severity": 2, "reason": "积极体验提升乐观预期"},
            {"parameter": "eta_s", "direction": "↑", "severity": 2, "reason": "对奖赏的期待增加"},
            {"parameter": "eta_a", "direction": "↓", "severity": 1, "reason": "积极体验降低焦虑"},
            {"parameter": "beta_effort", "direction": "↓", "severity": 2, "reason": "成功体验降低努力敏感性"}
        ]
    else:
        adjustments = [
            {"parameter": "p_base", "direction": "→", "severity": 1, "reason": "情绪平稳，无明显变化"},
            {"parameter": "eta_s", "direction": "→", "severity": 1, "reason": "情绪平稳，无明显变化"},
            {"parameter": "eta_a", "direction": "→", "severity": 1, "reason": "情绪平稳，无明显变化"},
            {"parameter": "beta_effort", "direction": "→", "severity": 1, "reason": "情绪平稳，无明显变化"}
        ]
    
    return {
        "adjustments": adjustments,
        "overall_assessment": "基于情绪主题的自动评估"
    }

# ============================================
# 步骤4: 应用认知参数调整
# ============================================
static func _apply_cognitive_adjustments(character: Node, decision: Dictionary) -> Array:
    """
    计算调整幅度并应用
    """
    var applied = []
    var adjustments = decision.get("adjustments", [])
    
    for adj in adjustments:
        var param_name = adj.get("parameter", "")
        var direction = adj.get("direction", "→")
        var severity = adj.get("severity", 1)
        var reason = adj.get("reason", "")
        
        if direction == "→" or param_name.is_empty():
            continue
        
        # 计算调整幅度
        var magnitude = _calculate_adjustment_magnitude(character, direction, severity)
        
        # 应用调整
        DynamicPersonality.update_trait(character, param_name, magnitude, reason)
        
        applied.append({
            "parameter": param_name,
            "direction": direction,
            "magnitude": magnitude,
            "reason": reason
        })
    
    return applied

static func _calculate_adjustment_magnitude(character: Node, direction: String, severity: int) -> float:
    """
    计算调整幅度
    """
    var base_magnitude = SEVERITY_TO_MAGNITUDE.get(severity, 0.01)
    
    # 获取角色类型
    var personality = CharacterPersonality.get_personality(character.name)
    var is_depression = personality.get("role_type", "") == "depression_risk_student"
    
    # 应用个体差异
    var multiplier = 1.0
    if is_depression:
        # 抑郁Agent：负面变化更严重，正面变化更弱
        multiplier = 1.5 if direction == "↑" else 0.7
    else:
        # 健康Agent：有韧性
        multiplier = 0.8 if direction == "↑" else 1.2
    
    var final_magnitude = base_magnitude * multiplier
    
    # 应用方向
    if direction == "↓":
        final_magnitude = -final_magnitude
    
    return final_magnitude

# ============================================
# 步骤5: PHQ-9完整评估
# ============================================
static func _conduct_phq9_assessment(character: Node, reflection: Dictionary) -> Dictionary:
    """
    使用LLM完成PHQ-9九项评估
    """
    var prompt = "基于以下反思结果，评估PHQ-9的九项症状（过去2周内，包括今天）。\n\n"
    prompt += "【反思结果】\n"
    prompt += "情绪主题: %s\n" % reflection.get("emotional_theme", "")
    prompt += "关键事件: %s\n" % JSON.stringify(reflection.get("key_events", []))
    prompt += "认知变化: %s\n\n" % JSON.stringify(reflection.get("cognitive_changes", {}))
    
    prompt += "【PHQ-9九项症状】\n"
    for i in range(PHQ9_ITEMS.size()):
        prompt += "%d. %s\n" % [i + 1, PHQ9_ITEMS[i]]
    
    prompt += "\n【评分标准】\n"
    prompt += "0 = 完全没有\n"
    prompt += "1 = 几天\n"
    prompt += "2 = 一半以上的天数\n"
    prompt += "3 = 几乎每天\n\n"
    
    prompt += "请对每项评分（0-3），并简要说明理由。\n"
    prompt += "以JSON格式输出：\n"
    prompt += '{"phq9_scores": [{"item": "...", "score": 0-3, "reason": "..."}, ...], '
    prompt += '"total_score": 0-27, "severity_level": "无抑郁/轻度/中度/中重度/重度"}'
    
    # 调用LLM（简化实现）
    # 实际应调用APIManager
    
    # 降级方案：基于情绪主题生成PHQ-9评估
    return _generate_fallback_phq9(character, reflection)

static func _generate_fallback_phq9(character: Node, reflection: Dictionary) -> Dictionary:
    """
    生成降级的PHQ-9评估（当LLM调用失败时）
    """
    var emotional_theme = reflection.get("emotional_theme", "")
    var is_negative = emotional_theme.contains("挫败") or emotional_theme.contains("沮丧") or emotional_theme.contains("孤独")
    var is_positive = emotional_theme.contains("积极") or emotional_theme.contains("满足") or emotional_theme.contains("成就")
    
    var base_score = 5  # 默认轻度
    if is_negative:
        base_score = 12  # 中度
    elif is_positive:
        base_score = 3   # 无/轻度
    
    # 生成简化的PHQ-9评分
    var scores = []
    for item in PHQ9_ITEMS:
        var score = randi() % 3  # 随机0-2
        if is_negative and (item.contains("沮丧") or item.contains("失败") or item.contains("兴趣")):
            score = 2  # 负面主题时，核心症状更严重
        scores.append({"item": item, "score": score, "reason": "基于情绪主题评估"})
    
    var total = 0
    for s in scores:
        total += s.score
    
    var severity = "轻度抑郁"
    if total < 5:
        severity = "无抑郁"
    elif total < 10:
        severity = "轻度抑郁"
    elif total < 15:
        severity = "中度抑郁"
    elif total < 20:
        severity = "中重度抑郁"
    else:
        severity = "重度抑郁"
    
    return {
        "phq9_scores": scores,
        "total_score": total,
        "severity_level": severity
    }

# ============================================
# 步骤6: 更新抑郁水平
# ============================================
static func _update_depression_level(character: Node, phq9_assessment: Dictionary) -> void:
    """
    基于PHQ-9分数更新抑郁水平
    """
    var total_score = phq9_assessment.get("total_score", 0)
    
    # PHQ-9分数(0-27)转换为抑郁水平(0-1)
    var depression_level = clamp(total_score / 27.0, 0.0, 1.0)
    
    var current_traits = DynamicPersonality.get_dynamic_traits(character)
    var old_level = current_traits.get("daily_depression_level", 0.5)
    
    var delta = depression_level - old_level
    
    DynamicPersonality.update_trait(
        character,
        "daily_depression_level",
        delta,
        "PHQ-9评估结果: %d分 (%s)" % [total_score, phq9_assessment.get("severity_level", "")]
    )

# ============================================
# 步骤7: 记录反思记忆
# ============================================
static func _record_reflection_memory(character: Node, reflection: Dictionary, 
                                      adjustments: Array, phq9: Dictionary) -> void:
    """
    记录每日反思的记忆
    """
    var memory_text = "每日反思：今天%s。" % reflection.get("emotional_theme", "")
    
    if adjustments.size() > 0:
        memory_text += "认知参数发生变化："
        for adj in adjustments:
            memory_text += "%s%s " % [adj.parameter, adj.direction]
    
    memory_text += "PHQ-9评估：%d分 (%s)。" % [
        phq9.get("total_score", 0),
        phq9.get("severity_level", "")
    ]
    
    MemoryManager.add_memory(
        character,
        memory_text,
        MemoryManager.MemoryType.PERSONAL,
        MemoryManager.MemoryImportance.HIGH
    )
    
    print("[DailyReflectionSystem] %s 反思记忆已记录" % character.name)
