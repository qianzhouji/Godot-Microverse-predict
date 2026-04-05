extends Node
class_name AgentRewardReceiver

# Agent奖赏接收器 - 感知层组件
# 职责：
# 1. 订阅RewardSystem信号，接收系统发放的奖赏
# 2. 添加感知噪声（个体差异）
# 3. 将感知后的奖赏传递给PerceptionSystem
# 4. 维护奖赏历史记录

# 引用到所属的AIAgent
var ai_agent: AIAgent = null

# 奖赏历史缓存
# 结构: [{room, time, gain, effort, received_at, perceived_gain}]
var reward_history: Array = []

# 最大历史记录数
const MAX_HISTORY_SIZE: int = 50

func _ready():
	# 延迟订阅信号，确保RewardSystem已初始化
	call_deferred("_subscribe_to_reward_system")

# 订阅RewardSystem信号
func _subscribe_to_reward_system() -> void:
	if RewardSystem.instance:
		RewardSystem.instance.reward_distributed.connect(_on_reward_received)
		print("[AgentRewardReceiver] %s 已订阅奖赏系统" % _get_agent_name())
	else:
		push_warning("[AgentRewardReceiver] RewardSystem未找到，将在5秒后重试")
		# 延迟重试
		var timer = Timer.new()
		timer.wait_time = 5.0
		timer.one_shot = true
		timer.timeout.connect(_subscribe_to_reward_system)
		add_child(timer)
		timer.start()

# 接收奖赏回调（由RewardSystem信号触发）
func _on_reward_received(agent_name: String, room_name: String, 
						 time: float, gain: float, effort: float) -> void:
	# 只处理发给自己的奖赏
	if agent_name != _get_agent_name():
		return
	
	# 获取Agent的认知参数（用于感知噪声）
	var personality = _get_personality()
	var is_depression = personality.get("role_type", "") == "depression_risk_student"
	var cm = personality.get("cognitive_mechanism", {})
	var eta_s = cm.get("eta_s", 0.5)
	var eta_a = cm.get("eta_a", 0.5)
	
	# 添加感知噪声 → 主观感知收益
	# Agent不能直接看到客观gain，只能感知到带噪声的版本
	var perceived_gain = PerceptionSystem.perceive_gain(gain, eta_s, eta_a)
	
	# 记录到历史
	var record = {
		"room": room_name,
		"time": time,
		"gain": gain,              # 客观收益（仅用于调试，Agent"不知道"）
		"perceived_gain": perceived_gain,  # 感知收益（Agent"实际看到"的）
		"effort": effort,
		"received_at": Time.get_unix_time_from_system()
	}
	reward_history.append(record)
	
	# 限制历史大小
	if reward_history.size() > MAX_HISTORY_SIZE:
		reward_history.pop_front()
	
	# 传递给感知系统进行贝叶斯更新
	PerceptionSystem.add_sample(agent_name, room_name, time, 
								perceived_gain, eta_s, eta_a, is_depression)
	
	print("[AgentRewardReceiver] %s 接收奖赏: 客观=%.3f → 感知=%.3f @ %s" % 
		  [agent_name, gain, perceived_gain, room_name])

# ============================================
# 公开接口
# ============================================

# 获取最近一次接收到的奖赏
func get_last_reward() -> Dictionary:
	if reward_history.is_empty():
		return {}
	return reward_history[-1]

# 获取最近一次感知到的收益（Agent"实际看到"的）
func get_last_perceived_gain() -> float:
	if reward_history.is_empty():
		return 0.0
	return reward_history[-1].perceived_gain

# 获取最近一次客观收益（仅用于调试）
func get_last_objective_gain() -> float:
	if reward_history.is_empty():
		return 0.0
	return reward_history[-1].gain

# 获取奖赏历史
func get_reward_history() -> Array:
	return reward_history.duplicate()

# 获取特定房间的奖赏历史
func get_room_reward_history(room_name: String) -> Array:
	var room_history = []
	for record in reward_history:
		if record.room == room_name:
			room_history.append(record)
	return room_history

# 清空历史
func clear_history() -> void:
	reward_history.clear()
	print("[AgentRewardReceiver] %s 奖赏历史已清空" % _get_agent_name())

# 获取统计信息
func get_statistics() -> Dictionary:
	if reward_history.is_empty():
		return {"count": 0}
	
	var total_gain = 0.0
	var total_perceived = 0.0
	var room_counts = {}
	
	for record in reward_history:
		total_gain += record.gain
		total_perceived += record.perceived_gain
		room_counts[record.room] = room_counts.get(record.room, 0) + 1
	
	var count = reward_history.size()
	return {
		"count": count,
		"avg_objective_gain": total_gain / count,
		"avg_perceived_gain": total_perceived / count,
		"perception_bias": (total_perceived - total_gain) / count,
		"room_distribution": room_counts
	}

# ============================================
# 辅助函数
# ============================================

# 获取Agent名称
func _get_agent_name() -> String:
	if ai_agent and ai_agent.character:
		return ai_agent.character.name
	return "Unknown"

# 获取Agent人设
func _get_personality() -> Dictionary:
	var agent_name = _get_agent_name()
	return CharacterPersonality.get_personality(agent_name)

# 调试输出
func _print_debug_info() -> void:
	print("[AgentRewardReceiver] %s 调试信息:" % _get_agent_name())
	print("  历史记录数: %d" % reward_history.size())
	if not reward_history.is_empty():
		var last = reward_history[-1]
		print("  最近奖赏: 客观=%.3f, 感知=%.3f @ %s" % 
			  [last.gain, last.perceived_gain, last.room])
