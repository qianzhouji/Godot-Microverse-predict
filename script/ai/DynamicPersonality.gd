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
	var new_value = clamp(old_value + delta, 0.0, 1.0)
	
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
