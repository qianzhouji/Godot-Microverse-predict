extends Node

class_name PerceptionSystem

# 贝叶斯感知系统
# 负责管理Agent对情境参数的感知推断

# 先验分布参数
const PRIOR_S_MEAN = 0.5
const PRIOR_S_VAR = 0.25
const PRIOR_A_MEAN = 0.5
const PRIOR_A_VAR = 0.25

# 抑郁风险Agent的悲观先验
const DEPRESSION_PRIOR_S_MEAN = 0.3
const DEPRESSION_PRIOR_S_VAR = 0.15
const DEPRESSION_PRIOR_A_MEAN = 0.6
const DEPRESSION_PRIOR_A_VAR = 0.15

# 感知噪声基准
const BASE_PERCEPTION_NOISE = 0.02

# 每个Agent对每个情境的信念缓存
static var agent_beliefs: Dictionary = {}

# 信念状态类
class BeliefState:
	var S_mean: float
	var S_var: float
	var a_mean: float
	var a_var: float
	var samples: Array
	var last_update_time: int
	
	func _init(is_depression_risk: bool = false):
		if is_depression_risk:
			S_mean = DEPRESSION_PRIOR_S_MEAN
			S_var = DEPRESSION_PRIOR_S_VAR
			a_mean = DEPRESSION_PRIOR_A_MEAN
			a_var = DEPRESSION_PRIOR_A_VAR
		else:
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

# 感知收益
static func perceive_gain(actual_gain: float, eta_s: float, eta_a: float) -> float:
	var avg_eta = (eta_s + eta_a) / 2.0
	var noise_std = BASE_PERCEPTION_NOISE * (1.0 - avg_eta * 0.3)
	var noise = randfn(0.0, noise_std)
	var perceived = actual_gain + noise
	return clamp(perceived, 0.0, 1.0)

# 添加观测样本
static func add_sample(agent_name: String, room_name: String, time_val: float, actual_gain: float, 
					   eta_s: float, eta_a: float, is_depression_risk: bool = false) -> void:
	var belief = get_belief(agent_name, room_name, is_depression_risk)
	var perceived_gain = perceive_gain(actual_gain, eta_s, eta_a)
	
	belief.samples.append({
		"time": time_val,
		"gain": perceived_gain
	})
	
	if belief.samples.size() >= 3:
		_update_beliefs(agent_name, room_name)

# 贝叶斯更新信念
static func _update_beliefs(agent_name: String, room_name: String) -> void:
	var belief = agent_beliefs[agent_name][room_name]
	
	if belief.samples.size() < 2:
		return
	
	var times = []
	var gains = []
	for sample in belief.samples:
		times.append(sample.time)
		gains.append(sample.gain)
	
	var best_S = belief.S_mean
	var best_a = belief.a_mean
	var best_error = 999999.0
	
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
				var predicted_gain = TimeUtils.calculate_mvt_gain(S, a, t)
				var error = pow(observed_gain - predicted_gain, 2)
				total_error += error
			
			if total_error < best_error:
				best_error = total_error
				best_S = S
				best_a = a
	
	var observation_variance_S = clamp(best_error / times.size(), 0.01, 0.25)
	var observation_variance_a = clamp(best_error / times.size(), 0.01, 0.25)
	
	var prior_precision_S = 1.0 / belief.S_var
	var likelihood_precision_S = 1.0 / observation_variance_S
	var posterior_var_S = 1.0 / (prior_precision_S + likelihood_precision_S)
	var posterior_mean_S = posterior_var_S * (
		prior_precision_S * belief.S_mean + 
		likelihood_precision_S * best_S
	)
	
	belief.S_mean = clamp(posterior_mean_S, 0.0, 1.0)
	belief.S_var = clamp(posterior_var_S, 0.01, 0.25)
	
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
	belief.samples.clear()

# 获取感知到的情境参数
static func get_perceived_params(agent_name: String, room_name: String, 
								 is_depression_risk: bool = false) -> Dictionary:
	var belief = get_belief(agent_name, room_name, is_depression_risk)
	
	return {
		"S": belief.S_mean,
		"a": belief.a_mean,
		"S_uncertainty": sqrt(belief.S_var),
		"a_uncertainty": sqrt(belief.a_var),
		"confidence": 1.0 - (belief.S_var + belief.a_var)
	}

# 计算感知收益
static func predict_gain(agent_name: String, room_name: String, time_minutes: float,
						 is_depression_risk: bool = false) -> float:
	var belief = get_belief(agent_name, room_name, is_depression_risk)
	var S = belief.S_mean
	var a = belief.a_mean
	return TimeUtils.calculate_mvt_gain(S, a, time_minutes)

# 格式化信念状态为prompt文本
static func get_belief_description(agent_name: String, room_name: String,
								   is_depression_risk: bool = false) -> String:
	var belief = get_belief(agent_name, room_name, is_depression_risk)
	var params = get_perceived_params(agent_name, room_name, is_depression_risk)
	
	var desc = "\n\n【你对当前情境的感知】"
	desc += "\n（基于你的经验和观察，你对这个情境有以下判断）"
	
	var S_desc = "中等"
	if belief.S_mean >= 0.7:
		S_desc = "较高"
	elif belief.S_mean <= 0.3:
		S_desc = "较低"
	desc += "\n- 你觉得这个情境一开始能获得的收益：%.0f%%（%s）" % [belief.S_mean * 100, S_desc]
	
	var a_desc = "中等"
	if belief.a_mean >= 0.6:
		a_desc = "较快"
	elif belief.a_mean <= 0.3:
		a_desc = "较慢"
	desc += "\n- 你觉得收益消耗的速度：%.0f%%（%s）" % [belief.a_mean * 100, a_desc]
	
	if params.confidence < 0.5:
		desc += "\n- 你对这个情境还不太熟悉，判断可能不太准确"
	elif params.confidence > 0.8:
		desc += "\n- 你对这个情境已经比较熟悉了"
	
	return desc

# 清空所有信念
static func reset_all_beliefs() -> void:
	agent_beliefs.clear()

# 清空特定Agent的信念
static func reset_agent_beliefs(agent_name: String) -> void:
	if agent_beliefs.has(agent_name):
		agent_beliefs.erase(agent_name)
