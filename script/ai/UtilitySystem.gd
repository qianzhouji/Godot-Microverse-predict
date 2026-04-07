extends Node

class_name UtilitySystem

# 效用计算系统
# 负责计算Agent的主观效用和决策

# 默认参数值
const DEFAULT_ALPHA = 0.8           # 健康Agent的收益敏感性
const DEFAULT_BETA_EFFORT = 0.4     # 健康Agent的努力敏感性
const DEPRESSION_ALPHA = 0.55       # 抑郁Agent的收益敏感性（降低）
const DEPRESSION_BETA_EFFORT = 0.8  # 抑郁Agent的努力敏感性（升高）

# 计算主观效用（非线性）
# U(G) = G^α - β_effort × E
static func calculate_utility(gain: float, effort: float, 
							  alpha: float, beta_effort: float) -> float:
	# 非线性收益效用：G^α
	var gain_utility = pow(max(gain, 0.0), alpha)
	
	# 努力成本：β_effort × E
	var effort_cost = beta_effort * effort
	
	# 总效用
	var utility = gain_utility - effort_cost
	
	return utility

# 计算感知最优停留时间（MVT）
# 使用理论公式：log(T) = log[ηS · log(S) − log(ρbase) − βeffort · effort] − ηa · log(a) + ε
# 其中 ε 为随机噪声，用 randfn(0, 0.1) 模拟
static func calculate_optimal_time(perceived_S: float, perceived_a: float,
								   effort: float, alpha: float, beta_effort: float,
								   p_base: float, eta_s: float = 0.5, eta_a: float = 0.5,
								   time_step: float = 1.0) -> float:
	# 确保参数在有效范围内
	if perceived_S <= 0.01:
		perceived_S = 0.01
	if perceived_a < 0.001:
		perceived_a = 0.001
	if p_base <= 0.01:
		p_base = 0.01
	if eta_s <= 0.01:
		eta_s = 0.01
	if eta_a <= 0.01:
		eta_a = 0.01
	
	# 理论公式：log(T) = log[ηS · log(S)] − log(ρbase) − βeffort · effort − ηa · log(a) + ε
	# 注意：原公式中的减号，这里分解为各项
	
	# 项1: log[ηS · log(S)]
	var term1 = log(eta_s * log(perceived_S))
	
	# 项2: − log(ρbase)
	var term2 = -log(p_base)
	
	# 项3: − βeffort · effort
	var term3 = -beta_effort * effort
	
	# 项4: − ηa · log(a)
	var term4 = -eta_a * log(perceived_a)
	
	# 项5: ε (随机噪声，标准差0.1)
	var epsilon = randfn(0.0, 0.1)
	
	# 计算 log(T)
	var log_T = term1 + term2 + term3 + term4 + epsilon
	
	# 计算 T = exp(log_T)
	var optimal_time = exp(log_T)
	
	# 限制在合理范围内 (1-60秒)
	optimal_time = clamp(optimal_time, 1.0, 60.0)
	
	return optimal_time

# 获取Agent的效用参数（包含全部四个MVT核心参数）
static func get_agent_utility_params(personality: Dictionary) -> Dictionary:
	var is_depression_risk = personality.get("role_type", "") == "depression_risk_student"
	
	var alpha = DEFAULT_ALPHA
	var beta_effort = DEFAULT_BETA_EFFORT
	var p_base = 0.5      # 离开阈值（环境平均奖赏率估计）
	var eta_s = 0.5       # 初始奖赏感知权重
	var eta_a = 0.5       # 衰减率感知权重
	
	# 从角色配置中读取（如果有）
	if personality.has("cognitive_mechanism"):
		var cm = personality["cognitive_mechanism"]
		if cm.has("beta_effort"):
			beta_effort = cm["beta_effort"]
		if cm.has("p_base"):
			p_base = cm["p_base"]
		if cm.has("eta_s"):
			eta_s = cm["eta_s"]
		if cm.has("eta_a"):
			eta_a = cm["eta_a"]
		# alpha参数可以从配置读取，或使用默认值
		if cm.has("alpha"):
			alpha = cm["alpha"]
		elif is_depression_risk:
			alpha = DEPRESSION_ALPHA
	else:
		# 使用默认值根据角色类型
		if is_depression_risk:
			alpha = DEPRESSION_ALPHA
			beta_effort = DEPRESSION_BETA_EFFORT
			p_base = 0.35   # 抑郁Agent：较低的离开阈值
			eta_s = 0.4     # 抑郁Agent：对初始奖赏较不敏感
			eta_a = 0.7     # 抑郁Agent：高估衰减速度
	
	return {
		"alpha": alpha,
		"beta_effort": beta_effort,
		"p_base": p_base,
		"eta_s": eta_s,
		"eta_a": eta_a,
		"is_depression_risk": is_depression_risk
	}

# 格式化效用参数描述（用于AI prompt）
static func get_utility_params_description(personality: Dictionary) -> String:
	var params = get_agent_utility_params(personality)
	var alpha = params.alpha
	var beta_effort = params.beta_effort
	var p_base = params.p_base
	var eta_s = params.eta_s
	var eta_a = params.eta_a
	var is_depression = params.is_depression_risk
	
	var desc = "\n\n【你的效用评估方式】"
	desc += "\n你评估一个活动值不值得参与时，会使用以下方式计算："
	desc += "\n主观效用 = (收益)^%.1f - %.1f × 努力成本" % [alpha, beta_effort]
	
	# alpha描述
	desc += "\n\n- 收益敏感性（α=%.1f）：" % alpha
	if alpha < 0.6:
		desc += "你对收益的反应比较迟钝，同样的收获给你带来的满足感较低"
	elif alpha > 0.7:
		desc += "你对收益比较敏感，能获得正常的满足感"
	else:
		desc += "中等水平"
	
	# beta_effort描述
	desc += "\n- 努力敏感性（β=%.1f）：" % beta_effort
	if beta_effort >= 0.7:
		desc += "【高努力敏感】努力成本会严重降低你的参与意愿，你倾向于回避需要付出努力的活动"
		if is_depression:
			desc += "这是抑郁风险的典型特征"
	elif beta_effort >= 0.5:
		desc += "【中等努力敏感】你会考虑努力成本，但不会因此完全回避"
	else:
		desc += "【低努力敏感】你不太在意付出的努力成本，愿意为目标付出"
	
	# MVT核心参数描述
	desc += "\n\n【你的停留时间决策方式（MVT模型）】"
	desc += "\n你会根据以下认知参数决定在一个情境中停留多久："
	
	desc += "\n- 离开阈值（ρbase=%.2f）：" % p_base
	if p_base < 0.4:
		desc += "你对环境平均奖赏的估计较低，容易满足，倾向于提前离开"
	elif p_base > 0.6:
		desc += "你对环境平均奖赏的估计较高，不容易满足，倾向于停留更久"
	else:
		desc += "中等水平"
	
	desc += "\n- 初始奖赏感知权重（ηS=%.2f）：" % eta_s
	if eta_s < 0.4:
		desc += "你对情境初始丰富度不太敏感"
	elif eta_s > 0.6:
		desc += "你对情境初始丰富度很敏感，会根据第一印象快速调整"
	else:
		desc += "中等水平"
	
	desc += "\n- 衰减率感知权重（ηa=%.2f）：" % eta_a
	if eta_a < 0.4:
		desc += "你对奖赏消耗速度不太敏感"
	elif eta_a > 0.6:
		desc += "你对奖赏消耗速度很敏感，容易觉得'没劲了'而提前离开"
	else:
		desc += "中等水平"
	
	# 举例说明
	desc += "\n\n【举例说明】"
	desc += "\n假设一个活动：收益=0.8，努力=0.6"
	var example_utility = calculate_utility(0.8, 0.6, alpha, beta_effort)
	desc += "\n你的主观效用 = (0.8)^%.1f - %.1f×0.6 = %.2f - %.2f = %.2f" % [
		alpha, beta_effort,
		pow(0.8, alpha), beta_effort * 0.6, example_utility
	]
	
	if example_utility < 0:
		desc += "\n→ 效用为负，你会觉得这个活动不值得参与"
	else:
		desc += "\n→ 效用为正，你可能会考虑参与"
	
	return desc

# 计算决策效用对比
static func compare_options(option1_gain: float, option1_effort: float,
							option2_gain: float, option2_effort: float,
							alpha: float, beta_effort: float) -> Dictionary:
	var u1 = calculate_utility(option1_gain, option1_effort, alpha, beta_effort)
	var u2 = calculate_utility(option2_gain, option2_effort, alpha, beta_effort)
	
	return {
		"option1_utility": u1,
		"option2_utility": u2,
		"difference": u1 - u2,
		"preferred": 1 if u1 > u2 else 2,
		"margin": abs(u1 - u2)
	}

# 格式化决策分析（用于AI prompt）
static func get_decision_analysis(current_room_params: Dictionary,
								  alternative_options: Array,
								  personality: Dictionary) -> String:
	var params = get_agent_utility_params(personality)
	var alpha = params.alpha
	var beta_effort = params.beta_effort
	var p_base = params.p_base
	var eta_s = params.eta_s
	var eta_a = params.eta_a
	
	var desc = "\n\n【当前决策分析】"
	
	# 当前情境的效用
	var current_S = current_room_params.get("perceived_S", 0.5)
	var current_a = current_room_params.get("perceived_a", 0.5)
	var current_effort = current_room_params.get("effort", 0.5)
	
	# 预测在t=10时的收益
	var predicted_gain = (current_S / max(current_a, 0.01)) * (1.0 - exp(-current_a * 10))
	var current_utility = calculate_utility(predicted_gain, current_effort, alpha, beta_effort)
	
	# 使用MVT公式计算建议停留时间
	var optimal_time = calculate_optimal_time(current_S, current_a, current_effort, 
											  alpha, beta_effort, p_base, eta_s, eta_a)
	
	desc += "\n当前情境（停留约10秒的预期）："
	desc += "\n- 感知初始收益：%.0f%%" % (current_S * 100)
	desc += "\n- 努力成本：%.0f%%" % (current_effort * 100)
	desc += "\n- 预期收益：%.2f" % predicted_gain
	desc += "\n- 主观效用：%.2f" % current_utility
	desc += "\n- MVT建议停留时间：%.1f秒" % optimal_time
	
	if current_utility < 0:
		desc += "\n→ 效用为负，继续停留会让你感到不值得"
	elif current_utility < 0.2:
		desc += "\n→ 效用较低，你可能会考虑离开"
	else:
		desc += "\n→ 效用尚可，你可能会继续停留"
	
	# 其他选项对比
	if alternative_options.size() > 0:
		desc += "\n\n其他可选情境的对比："
		for option in alternative_options:
			var opt_gain = option.get("expected_gain", 0.5)
			var opt_effort = option.get("effort", 0.5)
			var opt_name = option.get("name", "未知")
			var opt_utility = calculate_utility(opt_gain, opt_effort, alpha, beta_effort)
			
			# 计算该选项的建议停留时间
			var opt_S = option.get("S", 0.5)
			var opt_a = option.get("a", 0.5)
			var opt_time = calculate_optimal_time(opt_S, opt_a, opt_effort,
												  alpha, beta_effort, p_base, eta_s, eta_a)
			
			desc += "\n- %s：预期收益%.2f，努力%.0f%%，效用%.2f，建议停留%.1f秒" % [
				opt_name, opt_gain, opt_effort * 100, opt_utility, opt_time
			]
			if opt_utility > current_utility:
				desc += " 【更优选项】"
	
	return desc
