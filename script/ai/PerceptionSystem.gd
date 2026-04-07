extends Node

class_name PerceptionSystem

# 贝叶斯感知系统
# 负责管理Agent对情境参数的感知推断

# 先验分布参数
const PRIOR_S_MEAN = 0.5
const PRIOR_S_VAR = 0.25  # Uniform(0,1)的方差
const PRIOR_A_MEAN = 0.5
const PRIOR_A_VAR = 0.25

# 抑郁风险Agent的悲观先验
const DEPRESSION_PRIOR_S_MEAN = 0.3
const DEPRESSION_PRIOR_S_VAR = 0.15
const DEPRESSION_PRIOR_A_MEAN = 0.6
const DEPRESSION_PRIOR_A_VAR = 0.15

# 感知噪声基准（极小，确保Agent能较准确感知客观收益）
# 注意：主要噪声应在决策层（ε），感知层噪声仅表示轻微的不确定性
const BASE_PERCEPTION_NOISE = 0.02  # 从0.1降低到0.02，标准差仅2%

# 每个Agent对每个情境的信念缓存
# 结构: {agent_name: {room_name: BeliefState}}
static var agent_beliefs: Dictionary = {}

# 信念状态类
class BeliefState:
	var S_mean: float      # 对初始收益率的后验均值
	var S_var: float       # 对初始收益率的后验方差
	var a_mean: float      # 对衰减率的后验均值
	var a_var: float       # 对衰减率的后验方差
	var samples: Array     # 观测样本缓存 [{time, gain}]
	var last_update_time: int  # 上次更新时间
	
	func _init(is_depression_risk: bool = false):
		if is_depression_risk:
			# 抑郁Agent：悲观先验
			S_mean = DEPRESSION_PRIOR_S_MEAN
			S_var = DEPRESSION_PRIOR_S_VAR
			a_mean = DEPRESSION_PRIOR_A_MEAN
			a_var = DEPRESSION_PRIOR_A_VAR
		else:
			# 健康Agent：中性先验
			S_mean = PRIOR_S_MEAN
			S_var = PRIOR_S_VAR
			a_mean = PRIOR_A_MEAN
			a_var = PRIOR_A_VAR
		
		samples = []
		last_update_time = 0

# 获取或创建Agent对某情境的信念
static func get_belief(agent_name: String, room_name: String, is_depression_risk: bool = false) -> BeliefState:
	if not agent_beliefs.has(agent_name):
		agent_beliefs[agent_name] = {}
	
	if not agent_beliefs[agent_name].has(room_name):
		agent_beliefs[agent_name][room_name] = BeliefState.new(is_depression_risk)
	
	return agent_beliefs[agent_name][room_name]

# 感知收益（添加极小的感知噪声）
# 理论依据：主要噪声应在决策层（公式中的ε），感知层噪声仅表示轻微的不确定性
# 设计原则：噪声足够小，确保Agent能较准确感知客观收益，但仍有个体差异
static func perceive_gain(actual_gain: float, eta_s: float, eta_a: float) -> float:
	# 感知精度由eta_s和eta_a共同决定
	# 高eta → 更低的噪声（更精确）
	var avg_eta = (eta_s + eta_a) / 2.0
	
	# 噪声公式：基准噪声 × (1 - 平均感知权重 × 0.3)
	# 当eta=0.5时，噪声 = 0.02 × 0.85 = 0.017（标准差1.7%）
	# 当eta=1.0时，噪声 = 0.02 × 0.7 = 0.014（标准差1.4%）
	var noise_std = BASE_PERCEPTION_NOISE * (1.0 - avg_eta * 0.3)
	
	# 添加高斯噪声（极小）
	var noise = randfn(0.0, noise_std)
	var perceived = actual_gain + noise
	
	# 确保在合理范围内
	return clamp(perceived, 0.0, 1.0)

# 添加观测样本
static func add_sample(agent_name: String, room_name: String, time: float, actual_gain: float, 
					   eta_s: float, eta_a: float, is_depression_risk: bool = false) -> void:
	var belief = get_belief(agent_name, room_name, is_depression_risk)
	var perceived_gain = perceive_gain(actual_gain, eta_s, eta_a)
	
	belief.samples.append({
		"time": time,
		"gain": perceived_gain
	})
	
	# 样本数量达到阈值时更新信念
	if belief.samples.size() >= 3:
		_update_beliefs(agent_name, room_name)

# 贝叶斯更新信念（使用非线性最小二乘拟合理论收益函数）
static func _update_beliefs(agent_name: String, room_name: String) -> void:
	var belief = agent_beliefs[agent_name][room_name]
	
	if belief.samples.size() < 2:
		return
	
	# 从样本中提取时间和收益
	var times = []
	var gains = []
	for sample in belief.samples:
		times.append(sample.time)
		gains.append(sample.gain)
	
	# 使用非线性最小二乘拟合 G(t) = (S/a)[1 - exp(-at)]
	# 通过网格搜索找到最优的 S 和 a
	var best_S = belief.S_mean
	var best_a = belief.a_mean
	var best_error = 999999.0
	
	# 网格搜索参数范围
	var S_candidates = [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0]
	var a_candidates = [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0]
	
	for S in S_candidates:
		for a in a_candidates:
			if a < 0.01:
				continue
			var total_error = 0.0
			for i in range(times.size()):
				var t = times[i]
				var observed_gain = gains[i]
				# 理论收益: G(t) = (S/a)[1 - exp(-at)]
				var predicted_gain = (S / a) * (1.0 - exp(-a * t))
				var error = pow(observed_gain - predicted_gain, 2)
				total_error += error
			
			if total_error < best_error:
				best_error = total_error
				best_S = S
				best_a = a
	
	# 贝叶斯更新：将拟合结果与先验结合
	# 后验 = 先验 × 似然（使用正态分布共轭先验）
	
	# 观测精度（基于拟合误差）
	var observation_variance_S = clamp(best_error / times.size(), 0.01, 0.25)
	var observation_variance_a = clamp(best_error / times.size(), 0.01, 0.25)
	
	# 更新S的信念
	var prior_precision_S = 1.0 / belief.S_var
	var likelihood_precision_S = 1.0 / observation_variance_S
	var posterior_var_S = 1.0 / (prior_precision_S + likelihood_precision_S)
	var posterior_mean_S = posterior_var_S * (
		prior_precision_S * belief.S_mean + 
		likelihood_precision_S * best_S
	)
	
	belief.S_mean = clamp(posterior_mean_S, 0.0, 1.0)
	belief.S_var = clamp(posterior_var_S, 0.01, 0.25)
	
	# 更新a的信念
	var prior_precision_a = 1.0 / belief.a_var
	var likelihood_precision_a = 1.0 / observation_variance_a
	var posterior_var_a = 1.0 / (prior_precision_a + likelihood_precision_a)
	var posterior_mean_a = posterior_var_a * (
		prior_precision_a * belief.a_mean + 
		likelihood_precision_a * best_a
	)
	
	belief.a_mean = clamp(posterior_mean_a, 0.0, 1.0)
	belief.a_var = clamp(posterior_var_a, 0.01, 0.25)
	
	belief.last_update_time = Time.get_ticks_msec()
	
	# 清空样本缓存（可选：保留最近N个）
	belief.samples.clear()

# 获取感知到的情境参数
static func get_perceived_params(agent_name: String, room_name: String, 
								 is_depression_risk: bool = false) -> Dictionary:
	var belief = get_belief(agent_name, room_name, is_depression_risk)
	
	return {
		"S": belief.S_mean,           # 感知到的初始收益率
		"a": belief.a_mean,           # 感知到的衰减率
		"S_uncertainty": sqrt(belief.S_var),  # 不确定性
		"a_uncertainty": sqrt(belief.a_var),
		"confidence": 1.0 - (belief.S_var + belief.a_var)  # 总体置信度
	}

# 计算感知收益（用信念预测未来收益）
static func predict_gain(agent_name: String, room_name: String, time: float,
						 is_depression_risk: bool = false) -> float:
	var belief = get_belief(agent_name, room_name, is_depression_risk)
	var S = belief.S_mean
	var a = belief.a_mean
	
	if a < 0.01:
		a = 0.01  # 避免除零
	
	# G(t) = (S/a)[1 - exp(-at)]
	var predicted = (S / a) * (1.0 - exp(-a * time))
	return clamp(predicted, 0.0, 1.0)

# 格式化信念状态为prompt文本
static func get_belief_description(agent_name: String, room_name: String,
								   is_depression_risk: bool = false) -> String:
	var belief = get_belief(agent_name, room_name, is_depression_risk)
	var params = get_perceived_params(agent_name, room_name, is_depression_risk)
	
	var desc = "\n\n【你对当前情境的感知】"
	desc += "\n（基于你的经验和观察，你对这个情境有以下判断）"
	
	# 初始收益率感知
	var S_desc = "中等"
	if belief.S_mean >= 0.7:
		S_desc = "较高"
	elif belief.S_mean <= 0.3:
		S_desc = "较低"
	desc += "\n- 你觉得这个情境一开始能获得的收益：%.0f%%（%s）" % [belief.S_mean * 100, S_desc]
	
	# 衰减率感知
	var a_desc = "中等"
	if belief.a_mean >= 0.6:
		a_desc = "较快"
	elif belief.a_mean <= 0.3:
		a_desc = "较慢"
	desc += "\n- 你觉得收益消耗的速度：%.0f%%（%s）" % [belief.a_mean * 100, a_desc]
	
	# 不确定性
	if params.confidence < 0.5:
		desc += "\n- 你对这个情境还不太熟悉，判断可能不太准确"
	elif params.confidence > 0.8:
		desc += "\n- 你对这个情境已经比较熟悉了"
	
	return desc

# 清空所有信念（用于重置模拟）
static func reset_all_beliefs() -> void:
	agent_beliefs.clear()

# 清空特定Agent的信念
static func reset_agent_beliefs(agent_name: String) -> void:
	if agent_beliefs.has(agent_name):
		agent_beliefs.erase(agent_name)
