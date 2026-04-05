extends Node

class_name DynamicPersonality

# 动态特质管理器
# 用于在运行时动态调整角色的心理特质

# 特质变化阈值
const CHANGE_THRESHOLD = 0.1

# 获取角色的动态特质
static func get_dynamic_traits(character: Node) -> Dictionary:
	if not character:
		return {}
	
	# 从 character_data 中获取动态特质
	var character_data = character.get_meta("character_data", {})
	if not character_data.has("dynamic_traits"):
		# 初始化默认特质
		character_data["dynamic_traits"] = _get_default_traits(character.name)
		character.set_meta("character_data", character_data)
	
	return character_data["dynamic_traits"]

# 更新动态特质
static func update_trait(character: Node, trait_name: String, delta: float, reason: String = "") -> void:
	if not character:
		return
	
	var traits = get_dynamic_traits(character)
	var old_value = traits.get(trait_name, 0.5)
	var new_value = old_value + delta
	
	# 应用边界保护（防止过度偏离基线）
	if trait_name in ["p_base", "eta_s", "eta_a", "beta_effort"]:
		new_value = _apply_boundary_protection(character, trait_name, new_value)
	
	# 确保在有效范围内
	new_value = clamp(new_value, 0.0, 1.0)
	
	# 只有变化超过阈值才记录
	if abs(new_value - old_value) >= CHANGE_THRESHOLD:
		traits[trait_name] = new_value
		
		# 保存到 character_data
		var character_data = character.get_meta("character_data", {})
		character_data["dynamic_traits"] = traits
		character.set_meta("character_data", character_data)
		
		# 添加记忆记录特质变化
		if not reason.is_empty():
			var memory_text = "你的%s发生了变化（%.0f%% → %.0f%%），原因：%s" % [
				_get_trait_display_name(trait_name),
				old_value * 100,
				new_value * 100,
				reason
			]
			MemoryManager.add_memory(
				character,
				memory_text,
				MemoryManager.MemoryType.PERSONAL,
				MemoryManager.MemoryImportance.NORMAL
			)
		
		print("[DynamicPersonality] %s 的 %s 从 %.2f 变为 %.2f" % [
			character.name, trait_name, old_value, new_value
		])



# 获取默认特质值
static func _get_default_traits(character_name: String) -> Dictionary:
	# 从 CharacterPersonality 获取角色的基线认知机制参数
	var personality = CharacterPersonality.get_personality(character_name)
	var base_traits = {
		"daily_depression_level": 0.5,
		"p_base": 0.5,
		"eta_s": 0.5,
		"eta_a": 0.5,
		"beta_effort": 0.5
	}
	
	# 如果角色配置中有认知机制参数，使用配置值作为初始值
	if personality.has("cognitive_mechanism"):
		var cm = personality["cognitive_mechanism"]
		if cm.has("p_base"):
			base_traits["p_base"] = cm["p_base"]
		if cm.has("eta_s"):
			base_traits["eta_s"] = cm["eta_s"]
		if cm.has("eta_a"):
			base_traits["eta_a"] = cm["eta_a"]
		if cm.has("beta_effort"):
			base_traits["beta_effort"] = cm["beta_effort"]
	
	return base_traits

# 获取特质的显示名称
static func _get_trait_display_name(trait_name: String) -> String:
	var names = {
		"daily_depression_level": "当日抑郁水平",
		"p_base": "离开阈值",
		"eta_s": "初始奖赏感知权重",
		"eta_a": "衰减率感知权重",
		"beta_effort": "努力敏感性"
	}
	return names.get(trait_name, trait_name)

# ============================================
# 动态更新规则 - 抑郁水平与认知机制
# ============================================

# 应用任务反馈影响
static func apply_task_feedback(character: Node, success: bool, effort_level: float = 0.5) -> void:
	"""
	应用任务完成/失败对认知机制的影响
	
	参数:
		character: 角色节点
		success: 任务是否成功
		effort_level: 任务努力水平(0-1)，影响变化幅度
	"""
	if not character:
		return
	
	# 获取角色类型（抑郁vs健康）
	var personality = CharacterPersonality.get_personality(character.name)
	var is_depression = personality.get("role_type", "") == "depression_risk_student"
	
	# 个体差异：抑郁Agent对负面事件更敏感，恢复更慢
	var sensitivity = 1.5 if is_depression else 0.8
	var recovery_rate = 0.7 if is_depression else 1.2
	
	if success:
		# 任务成功：降低努力敏感性，提升离开阈值，缓解抑郁
		var delta_beta = -0.05 * recovery_rate * effort_level
		var delta_p_base = 0.03 * recovery_rate
		var delta_depression = -0.02 * recovery_rate
		
		update_trait(character, "beta_effort", delta_beta, 
					 "任务成功增强自信，降低努力敏感性")
		update_trait(character, "p_base", delta_p_base, 
					 "任务成功提升对环境奖赏的估计")
		update_trait(character, "daily_depression_level", delta_depression, 
					 "任务成功缓解抑郁情绪")
	else:
		# 任务失败：增加努力敏感性，降低离开阈值，加重抑郁
		var delta_beta = 0.08 * sensitivity * effort_level
		var delta_p_base = -0.05 * sensitivity
		var delta_depression = 0.05 * sensitivity
		
		update_trait(character, "beta_effort", delta_beta, 
					 "任务失败增加努力成本感知（抑郁恶化）")
		update_trait(character, "p_base", delta_p_base, 
					 "任务失败降低对环境奖赏的估计")
		update_trait(character, "daily_depression_level", delta_depression, 
					 "任务失败加重抑郁情绪")

# 应用社交互动反馈影响
static func apply_social_feedback(character: Node, positive: bool, intensity: float = 1.0) -> void:
	"""
	应用社交互动对认知机制的影响
	
	参数:
		character: 角色节点
		positive: 互动是否积极（被接纳vs被拒绝）
		intensity: 互动强度(0-1)
	"""
	if not character:
		return
	
	var personality = CharacterPersonality.get_personality(character.name)
	var is_depression = personality.get("role_type", "") == "depression_risk_student"
	var sensitivity = 1.5 if is_depression else 0.8
	
	if positive:
		# 积极社交：改善情绪，提升奖赏感知
		update_trait(character, "daily_depression_level", -0.03 * intensity, 
					 "获得同伴支持，情绪改善")
		update_trait(character, "eta_s", 0.02 * intensity, 
					 "积极体验提升对初始奖赏的敏感度")
	else:
		# 消极社交：加重抑郁，增加回避
		update_trait(character, "daily_depression_level", 0.06 * intensity * sensitivity, 
					 "社交 rejection 加重抑郁")
		update_trait(character, "beta_effort", 0.04 * intensity * sensitivity, 
					 "社交回避倾向增加")
		update_trait(character, "eta_a", 0.03 * intensity * sensitivity, 
					 "负面预期增强，高估奖赏衰减")

# 应用教师评价影响
static func apply_teacher_feedback(character: Node, positive: bool) -> void:
	"""
	应用教师评价对认知机制的影响
	
	参数:
		character: 角色节点
		positive: 评价是否积极（表扬vs批评）
	"""
	if not character:
		return
	
	var personality = CharacterPersonality.get_personality(character.name)
	var is_depression = personality.get("role_type", "") == "depression_risk_student"
	var sensitivity = 1.5 if is_depression else 0.8
	
	if positive:
		# 表扬：降低努力敏感性，改善情绪
		update_trait(character, "beta_effort", -0.04, 
					 "获得认可，降低努力敏感性")
		update_trait(character, "daily_depression_level", -0.04, 
					 "获得认可，情绪改善")
	else:
		# 批评：增加努力敏感性，加重抑郁
		update_trait(character, "beta_effort", 0.06 * sensitivity, 
					 "批评增加努力成本感知")
		update_trait(character, "daily_depression_level", 0.05 * sensitivity, 
					 "批评加重抑郁情绪")

# 每日PHQ-9自评更新
static func daily_phq9_update(character: Node, day_events: Array = []) -> Dictionary:
	"""
	每日结束时根据当天经历更新PHQ-9抑郁水平和认知参数
	
	参数:
		character: 角色节点
		day_events: 当日事件列表 [{type, valence, intensity}]
	
	返回:
		更新后的特质字典
	"""
	if not character:
		return {}
	
	var traits = get_dynamic_traits(character)
	var old_depression = traits.get("daily_depression_level", 0.5)
	
	# 基于当日事件计算净情绪变化
	var net_mood_change = 0.0
	for event in day_events:
		var valence = event.get("valence", 0)  # -1=负面, 0=中性, 1=正面
		var intensity = event.get("intensity", 0.5)
		net_mood_change += valence * intensity * 0.02
	
	# 应用自然恢复（睡眠、休息）
	var natural_recovery = -0.01  # 每天自然恢复1%
	
	# 计算新的抑郁水平
	var new_depression = old_depression + net_mood_change + natural_recovery
	new_depression = clamp(new_depression, 0.0, 1.0)
	
	# 更新抑郁水平
	if abs(new_depression - old_depression) >= 0.01:
		update_trait(character, "daily_depression_level", new_depression - old_depression, 
					 "每日PHQ-9自评更新")
	
	# 根据抑郁水平调整认知参数（高抑郁恶化认知）
	_apply_depression_cognitive_effects(character, new_depression)
	
	return get_dynamic_traits(character)

# 应用抑郁水平对认知参数的影响
static func _apply_depression_cognitive_effects(character: Node, depression_level: float) -> void:
	"""
	根据抑郁水平自动调整认知参数
	高抑郁水平会恶化认知功能
	"""
	if depression_level > 0.6:
		# 高抑郁水平
		update_trait(character, "beta_effort", 0.02, 
					 "高抑郁水平导致努力敏感性升高")
		update_trait(character, "p_base", -0.02, 
					 "高抑郁水平降低对环境奖赏的估计")
		update_trait(character, "eta_a", 0.01, 
					 "高抑郁水平导致悲观预期")
	elif depression_level < 0.3:
		# 低抑郁水平（恢复）
		update_trait(character, "beta_effort", -0.01, 
					 "情绪改善，努力敏感性降低")
		update_trait(character, "p_base", 0.01, 
					 "情绪改善，对环境更乐观")

# ============================================
# 边界保护机制
# ============================================

# 获取基线值
static func _get_baseline_value(character: Node, trait_name: String) -> float:
	"""
	获取角色的基线认知参数值
	"""
	if not character:
		return 0.5
	
	var personality = CharacterPersonality.get_personality(character.name)
	if personality.has("cognitive_mechanism"):
		var cm = personality["cognitive_mechanism"]
		return cm.get(trait_name, 0.5)
	
	return 0.5

# 应用边界保护（防止参数偏离基线太多）
static func _apply_boundary_protection(character: Node, trait_name: String, new_value: float) -> float:
	"""
	应用边界保护，确保参数不会过度偏离基线
	保持个体稳定性
	"""
	var baseline = _get_baseline_value(character, trait_name)
	var max_deviation = 0.2  # 最大偏离20%
	
	return clamp(new_value, baseline - max_deviation, baseline + max_deviation)

# 获取PHQ-9等级描述
static func get_phq9_level_description(depression_level: float) -> String:
	"""
	根据抑郁水平返回PHQ-9等级描述
	"""
	if depression_level < 0.15:
		return "无抑郁 (PHQ-9: 0-4)"
	elif depression_level < 0.33:
		return "轻度抑郁 (PHQ-9: 5-9)"
	elif depression_level < 0.52:
		return "中度抑郁 (PHQ-9: 10-14)"
	elif depression_level < 0.70:
		return "中重度抑郁 (PHQ-9: 15-19)"
	else:
		return "重度抑郁 (PHQ-9: 20-27)"

# 将动态特质格式化为 prompt 文本
static func get_traits_for_prompt(character: Node) -> String:
	var traits = get_dynamic_traits(character)
	if traits.is_empty():
		return ""
	
	var prompt = "\n\n【努力导向决策的认知计算机制】"
	prompt += "\n- 当日抑郁水平：%.0f%%（0=无抑郁，1=重度抑郁，0.5为基线）" % (traits.get("daily_depression_level", 0.5) * 100)
	prompt += "\n- 离开阈值 (p_base)：%.0f%%（反映个体对环境平均奖赏率的估计）" % (traits.get("p_base", 0.5) * 100)
	prompt += "\n- 初始奖赏感知权重 (η_s)：%.0f%%（反映个体根据情境初始丰富度调节停留时间的敏感程度）" % (traits.get("eta_s", 0.5) * 100)
	prompt += "\n- 衰减率感知权重 (η_a)：%.0f%%（反映个体感知奖赏消耗速度的准确性）" % (traits.get("eta_a", 0.5) * 100)
	prompt += "\n- 努力敏感性 (β_effort)：%.0f%%（表示努力成本对离开阈值的调节作用）" % (traits.get("beta_effort", 0.5) * 100)
	
	# 添加特质影响的说明
	prompt += "\n\n【认知计算机制对你行为的影响】"
	
	var daily_depression = traits.get("daily_depression_level", 0.5)
	var p_base = traits.get("p_base", 0.5)
	var eta_s = traits.get("eta_s", 0.5)
	var eta_a = traits.get("eta_a", 0.5)
	var beta_effort = traits.get("beta_effort", 0.5)
	
	if daily_depression > 0.6:
		prompt += "\n- 你今天感到明显的抑郁情绪，这会影响你的决策和行为"
	elif daily_depression < 0.4:
		prompt += "\n- 你今天的心情相对较好，情绪较为稳定"
	
	if p_base > 0.6:
		prompt += "\n- 你对环境的奖赏率估计较高，倾向于在活动中停留更久"
	elif p_base < 0.4:
		prompt += "\n- 你对环境的奖赏率估计较低，容易提前离开活动"
	
	if eta_s > 0.6:
		prompt += "\n- 你对情境初始丰富度很敏感，初始印象对你的停留时间影响很大"
	
	if eta_a > 0.6:
		prompt += "\n- 你对奖赏消耗速度很敏感，能准确感知奖赏的衰减"
	
	if beta_effort > 0.7:
		prompt += "\n- 你的努力敏感性很高，努力成本会显著降低你的参与意愿（抑郁特质）"
		prompt += "\n- 你倾向于回避需要付出努力的活动，即使这些活动可能带来回报"
	elif beta_effort < 0.3:
		prompt += "\n- 你的努力敏感性较低，不太在意付出的努力成本"
	
	return prompt
