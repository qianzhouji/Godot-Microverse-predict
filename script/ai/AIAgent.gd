class_name AIAgent
extends Node

# ============================================
# 状态枚举
# ============================================
enum AgentState {
	IDLE,                    # 空闲
	PERCEIVING,              # 感知中
	EXPERIENCING,            # 体验中
	DECIDING,                # 决策中
	WAITING_FOR_CLICK,       # 等待Click执行
	EXECUTING_ACTION,        # 执行行动中
	IN_DIALOGUE,             # 在对话中
	IN_ACTIVITY,             # 在活动中(体育/自习)
	MOVING                   # 移动中
}

# ============================================
# 核心引用
# ============================================
var character: CharacterBody2D = null          # 角色节点
var room_manager = null           # 房间管理器 (RoomManager类型，通过场景树获取)

# ============================================
# 感知层组件(保留)
# ============================================
var reward_receiver: AgentRewardReceiver = null    # 奖赏接收器

# ============================================
# 状态管理(新增)
# ============================================
var current_state: AgentState = AgentState.IDLE
var current_activity: String = ""              # 当前活动类型
var activity_start_time: float = 0.0           # 活动开始时间
var last_activity: String = ""                 # 上一周期活动(用于体验)

# ============================================
# 三步活动缓存
# ============================================
var activity_cache: Array[Activity] = []       # 缓存的活动序列（最多3步）
var current_activity_index: int = 0            # 当前执行的活动索引
var movement_executor: MovementExecutor = null # 移动执行器

# ============================================
# 自然语言决策
# ============================================
var last_natural_decision: String = ""         # 上次自然语言决策

# ============================================
# 信息接收系统
# ============================================
var information_receiver: InformationReceiver = null  # 信息接收器

# ============================================
# 玩家控制(保留)
# ============================================
var is_player_controlled: bool = false

# ============================================
# V1兼容: 旧版请求缓存系统
# ============================================
var cached_request: ActionRequest = null       # 缓存的行动请求(V1)
var is_waiting_execution: bool = false         # 是否等待执行(V1)

# ============================================
# 移动相关变量
# ============================================
var _is_moving: bool = false                   # 是否正在移动
var _target_position: Vector2 = Vector2.ZERO   # 目标位置
var _movement_check_timer: float = 0.0         # 移动检查计时器
const MOVEMENT_CHECK_INTERVAL: float = 0.5     # 每0.5秒检查一次移动状态

# ============================================
# 初始化
# ============================================
func _ready():
	print("[AIAgent] 初始化AIAgent...")

	# 获取角色引用
	character = get_parent() as CharacterBody2D
	if not character:
		push_error("[AIAgent] 父节点不是CharacterBody2D")
		return

	# 获取房间管理器
	room_manager = _get_room_manager()

	# 创建感知层组件
	_create_reward_receiver()
	
	# V2: 创建信息接收器
	_create_information_receiver()

	# 连接时序系统信号
	_connect_to_timing_system()

	print("[AIAgent] %s 初始化完成" % character.name)

# ============================================
# 感知层组件创建(保留原逻辑)
# ============================================
func _create_reward_receiver() -> void:
	reward_receiver = AgentRewardReceiver.new()
	reward_receiver.ai_agent = self
	add_child(reward_receiver)
	print("[AIAgent] %s 奖赏接收器已创建" % character.name)

# ============================================
# V2: 信息接收器创建
# ============================================
func _create_information_receiver() -> void:
	information_receiver = InformationReceiver.new(character.name)
	print("[AIAgent] %s 信息接收器已创建" % character.name)

# ============================================
# 连接时序系统(新增)
# ============================================
func _connect_to_timing_system() -> void:
	# 延迟连接,确保TimingSystem已初始化
	await get_tree().create_timer(1.0).timeout
	
	print("[AIAgent] %s 尝试连接时序系统..." % character.name)
	print("[AIAgent] %s TimingSystem.instance = %s" % [character.name, TimingSystem.instance])

	if TimingSystem.instance:
		TimingSystem.instance.click_triggered.connect(_on_click_triggered)
		print("[AIAgent] %s 已连接到时序系统" % character.name)
	else:
		push_warning("[AIAgent] %s TimingSystem未找到" % character.name)

# ============================================
# Click触发回调(核心入口) - V2时序逻辑
# ============================================
func _on_click_triggered(game_time: float, day: int, click_num: int):
	print("\n[AIAgent] %s _on_click_triggered被调用, click_num=%d" % [character.name, click_num])
	if is_player_controlled:
		print("[AIAgent] %s 是玩家控制,跳过" % character.name)
		return

	print("[AIAgent] %s 收到Click #%d" % [character.name, click_num])
	print("[AIAgent] %s activity_cache.size()=%d, current_activity_index=%d" % [character.name, activity_cache.size(), current_activity_index])
	print("[AIAgent] %s ActivityManager.instance=%s" % [character.name, ActivityManager.instance])
	if ActivityManager.instance:
		print("[AIAgent] %s ActivityManager.instance.has_activity=%s" % [character.name, ActivityManager.instance.has_activity(character.name)])

	# V2时序逻辑：
	# 1. 如果有V2活动缓存 → 执行下一步
	# 2. 如果正在活动中 → 体验 + 决策
	# 3. 否则 → 感知 + 决策
	
	# 优先检查活动缓存（如果为空，尝试从协调器获取）
	if activity_cache.size() == 0 and ActivityCoordinator.instance:
		var assigned_activities = ActivityCoordinator.instance.get_assigned_activities(character.name)
		if assigned_activities.size() > 0:
			print("[AIAgent] %s 从协调器获取到 %d 个分配活动" % [character.name, assigned_activities.size()])
			receive_activity_sequence(assigned_activities)
	
	if activity_cache.size() > 0 and current_activity_index < activity_cache.size():
		print("[AIAgent] %s 执行缓存活动" % character.name)
		_execute_next_cached_activity()
	elif ActivityManager.instance and ActivityManager.instance.has_activity(character.name):
		# 正在活动中：体验 + 决策
		print("[AIAgent] %s 执行活动中更新" % character.name)
		_perform_activity_update()
	else:
		# 空闲状态 → 感知 + 自然语言决策 + 提交协调器
		print("[AIAgent] %s 执行V2认知循环" % character.name)
		_perform_v2_cognitive_cycle()

# ============================================
# 活动中更新：体验(累积) + 决策(继续/停止/更换)
# ============================================
func _perform_activity_update():
	print("[AIAgent] %s 活动中更新..." % character.name)
	
	# 1. 获取当前活动信息
	var activity_info = ActivityManager.instance.get_activity_info(character.name)
	if not activity_info.has_activity:
		# 活动已结束，回到空闲状态
		_perform_v2_cognitive_cycle()
		return
	
	# 2. 体验阶段：接收累积奖赏（ActivityManager已在Click时触发RewardSystem）
	current_state = AgentState.EXPERIENCING
	var experience_result = _experience_current_activity(activity_info)
	print("[AIAgent] %s 体验完成: 累计时长%.1f分钟, 收益%.3f" % [
		character.name,
		activity_info.duration,
		experience_result.get("cumulative_gain", 0.0)
	])
	
	# 3. 感知阶段（更新环境信息）
	current_state = AgentState.PERCEIVING
	var perception = _perceive()
	# 添加活动信息到感知
	perception["current_activity"] = activity_info
	
	# 4. 决策阶段：继续/停止/更换活动
	current_state = AgentState.DECIDING
	var decision = await _make_activity_decision(perception, activity_info, experience_result)
	print("[AIAgent] %s 活动决策: %s" % [character.name, decision.get("decision_type", "unknown")])
	
	# 5. 执行决策
	_execute_activity_decision(decision, activity_info)

# ============================================
# V2: 认知循环 - 感知 → 自然语言决策 → 提交协调器
# ============================================
func _perform_v2_cognitive_cycle():
	print("[AIAgent] %s _perform_v2_cognitive_cycle开始执行" % character.name)
	
	# 1. 感知阶段
	current_state = AgentState.PERCEIVING
	print("[AIAgent] %s 开始感知..." % character.name)
	var perception = _perceive()
	print("[AIAgent] %s 感知完成" % character.name)

	# 2. 体验阶段(如果有上一周期活动)
	current_state = AgentState.EXPERIENCING
	if not last_activity.is_empty():
		print("[AIAgent] %s 开始体验..." % character.name)
		_experience(last_activity)
		print("[AIAgent] %s 体验完成" % character.name)
	else:
		print("[AIAgent] %s 无上一活动,跳过体验" % character.name)

	# 3. V2: 自然语言决策阶段
	current_state = AgentState.DECIDING
	print("[AIAgent] %s 开始自然语言决策..." % character.name)
	var natural_decision = await _make_natural_decision(perception)
	print("[AIAgent] %s 自然语言决策: %s" % [character.name, natural_decision])
	
	# 4. V2: 提交决策到协调器
	print("[AIAgent] %s 准备提交决策到协调器..." % character.name)
	_submit_decision_to_coordinator(natural_decision)
	
	# V2: 决策已提交，等待协调器下发活动
	print("[AIAgent] %s 决策已提交,等待协调器下发活动" % character.name)
	# 实际活动将在下一个Click周期通过 receive_activity_sequence() 接收
	print("[AIAgent] %s 决策已提交，等待协调器分配..." % character.name)

# ============================================
# 感知阶段
# ============================================
func _perceive() -> Dictionary:
	var perception = {
		"current_room": "",
		"nearby_agents": [],
		"visible_behaviors": [],
		"audible_contents": [],
		"time_constraints": {},
		"current_time": 0.0
	}

	# 1. 获取当前子场景
	var current_room_area = _get_current_room()
	if current_room_area:
		perception.current_room = current_room_area.room_name

	# 2. 获取同场景其他Agent（包含活动状态）
	perception.nearby_agents = _get_agents_in_same_room_with_status()

	# 3. 获取时间轴约束
	if TimelineState.instance:
		perception.time_constraints = TimelineState.instance.get_constraints()

	# 4. 获取当前游戏时间
	if TimingSystem.instance:
		perception.current_time = TimingSystem.instance.current_game_time

	# TODO: 集成DialogueManager获取对话行为和内容

	return perception

# ============================================
# 体验阶段(新增)
# ============================================
func _experience(previous_activity: String) -> float:
	# 1. 从奖赏接收器获取最近接收的奖赏
	if not reward_receiver:
		return 0.0

	var last_reward = reward_receiver.get_last_reward()
	if last_reward.is_empty():
		return 0.0

	var objective_gain = last_reward.get("gain", 0.0)
	var perceived_gain = last_reward.get("perceived_gain", 0.0)
	var room_name = last_reward.get("room", "")

	# 2. 贝叶斯更新已经在AgentRewardReceiver中自动完成
	# 这里只需要获取更新后的感知参数
	var personality = _get_personality()
	var is_depression = personality.get("role_type", "") == "depression_risk_student"

	var perceived_params = PerceptionSystem.get_perceived_params(
		character.name,
		room_name,
		is_depression
	)

	print("[AIAgent] %s 体验: 客观=%.3f, 感知=%.3f" % [character.name, objective_gain, perceived_gain])

	return perceived_gain

# ============================================
# 体验当前活动（新时序逻辑）
# ============================================
func _experience_current_activity(activity_info: Dictionary) -> Dictionary:
	# 从奖赏接收器获取最近接收的奖赏（ActivityManager已在Click时触发）
	if not reward_receiver:
		return {"cumulative_gain": 0.0, "perceived_gain": 0.0}
	
	var last_reward = reward_receiver.get_last_reward()
	if last_reward.is_empty():
		return {"cumulative_gain": 0.0, "perceived_gain": 0.0}
	
	var objective_gain = last_reward.get("gain", 0.0)
	var perceived_gain = last_reward.get("perceived_gain", 0.0)
	var room_name = last_reward.get("room", "")
	
	# 贝叶斯更新已在AgentRewardReceiver中自动完成
	var personality = _get_personality()
	var is_depression = personality.get("role_type", "") == "depression_risk_student"
	
	var perceived_params = PerceptionSystem.get_perceived_params(
		character.name,
		room_name,
		is_depression
	)
	
	return {
		"cumulative_gain": objective_gain,
		"perceived_gain": perceived_gain,
		"room_name": room_name,
		"perceived_params": perceived_params,
		"activity_duration": activity_info.get("duration", 0.0)
	}

# ============================================
# 活动决策（继续/停止/更换）- 新时序逻辑
# ============================================
func _make_activity_decision(perception: Dictionary, activity_info: Dictionary, experience: Dictionary) -> Dictionary:
	print("[AIAgent] %s 进行活动决策..." % character.name)
	
	var personality = _get_personality()
	var is_depression = personality.get("role_type", "") == "depression_risk_student"
	
	# 获取MVT决策建议
	var room_name = experience.get("room_name", "")
	var current_duration = experience.get("activity_duration", 0.0)
	var perceived_params = experience.get("perceived_params", {})
	var perceived_S = perceived_params.get("S", 0.5)
	var perceived_a = perceived_params.get("a", 0.5)
	
	# 获取效用参数
	var utility_params = UtilitySystem.get_agent_utility_params(personality)
	var p_base = utility_params.p_base
	var eta_s = utility_params.eta_s
	var eta_a = utility_params.eta_a
	var beta_effort = utility_params.beta_effort
	var alpha = utility_params.alpha
	
	# 获取努力成本
	var effort = 0.5
	if RewardSystem.instance and not room_name.is_empty():
		var room_data = RewardSystem.instance._get_room_objective_params(room_name)
		effort = room_data.get("E", 0.5)
	
	# 计算MVT最优停留时间
	var optimal_time = UtilitySystem.calculate_optimal_time(
		perceived_S, perceived_a, effort, alpha, beta_effort, p_base, eta_s, eta_a
	)
	
	# 决策逻辑
	var decision_type = "continue"  # 默认继续
	var reason = ""
	
	if current_duration >= optimal_time:
		# 已达到最优时间，建议离开
		decision_type = "stop"
		reason = "已停留%.1f分钟，达到MVT预测的最优时间(%.1f分钟)" % [current_duration, optimal_time]
	else:
		# 检查是否有更好的替代选项
		var remaining = optimal_time - current_duration
		var alternative = _check_better_alternative(perception, experience)
		
		if alternative.has_alternative and alternative.utility_diff > 0.2:
			decision_type = "switch"
			reason = "发现更优选项：%s（效用差%.2f）" % [alternative.name, alternative.utility_diff]
		else:
			decision_type = "continue"
			reason = "已停留%.1f分钟，距离最优时间还有%.1f分钟" % [current_duration, remaining]
	
	# 构建决策Prompt让LLM确认
	var prompt = _build_activity_decision_prompt(perception, activity_info, experience, decision_type, reason)
	var response = await _call_local_llm(prompt)
	var llm_decision = _parse_activity_decision_response(response, decision_type)
	
	return {
		"decision_type": llm_decision.decision_type,
		"reason": llm_decision.reason,
		"mvt_suggestion": decision_type,
		"mvt_reason": reason,
		"optimal_time": optimal_time,
		"current_duration": current_duration,
		"target_action": llm_decision.target_action
	}

# 检查是否有更好的替代选项
func _check_better_alternative(perception: Dictionary, experience: Dictionary) -> Dictionary:
	# TODO: 实现替代选项检查
	return {"has_alternative": false, "utility_diff": 0.0, "name": ""}

# 构建活动决策Prompt
func _build_activity_decision_prompt(perception: Dictionary, activity_info: Dictionary, 
									experience: Dictionary, mvt_suggestion: String, mvt_reason: String) -> String:
	var prompt = "你是" + character.name + "，正在进行" + activity_info.get("activity_name", "活动") + "。\n\n"
	
	prompt += "【当前活动状态】\n"
	prompt += "- 活动类型：" + activity_info.get("activity_name", "未知") + "\n"
	prompt += "- 已持续时间：%.1f分钟\n" % experience.get("activity_duration", 0.0)
	prompt += "- 累积收益：%.3f\n" % experience.get("cumulative_gain", 0.0)
	
	var params = experience.get("perceived_params", {})
	prompt += "- 感知情境收益：%.0f%%\n" % (params.get("S", 0.5) * 100)
	prompt += "- 感知衰减速度：%.0f%%\n" % (params.get("a", 0.5) * 100)
	
	prompt += "\n【MVT模型建议】\n"
	prompt += mvt_reason + "\n"
	prompt += "建议：" + ("继续当前活动" if mvt_suggestion == "continue" else 
					("停止活动" if mvt_suggestion == "stop" else "更换活动")) + "\n"
	
	prompt += "\n【当前环境】\n"
	prompt += "- 当前场景：" + perception.get("current_room", "未知") + "\n"
	prompt += "- 附近角色：" + str(perception.get("nearby_agents", []).size()) + "人\n"
	
	prompt += "\n请决定：\n"
	prompt += "1. CONTINUE - 继续当前活动\n"
	prompt += "2. STOP - 停止当前活动，转为空闲\n"
	prompt += "3. SWITCH - 更换为其他活动\n"
	prompt += "\n请以JSON格式输出：{\"decision\": \"CONTINUE/STOP/SWITCH\", \"reason\": \"...\", \"target_action\": \"...\"}"
	
	return prompt

# 解析活动决策响应
func _parse_activity_decision_response(response: String, default_decision: String) -> Dictionary:
	var json_text = _extract_json_from_text(response)
	var json = JSON.new()
	var parse_result = json.parse(json_text)
	
	if parse_result != OK:
		return {"decision_type": default_decision, "reason": "解析失败，使用默认决策", "target_action": ""}
	
	var data = json.get_data()
	var decision = data.get("decision", default_decision).to_lower()
	
	return {
		"decision_type": decision,
		"reason": data.get("reason", ""),
		"target_action": data.get("target_action", "")
	}

# 执行活动决策
func _execute_activity_decision(decision: Dictionary, activity_info: Dictionary):
	var decision_type = decision.get("decision_type", "continue")
	
	match decision_type:
		"continue":
			# 继续当前活动，无需操作
			print("[AIAgent] %s 继续当前活动" % character.name)
			current_state = AgentState.IN_ACTIVITY
			
		"stop":
			# 停止当前活动
			print("[AIAgent] %s 停止活动" % character.name)
			if ActivityManager.instance:
				ActivityManager.instance.end_activity(character.name, "MVT决策：达到最优时间")
			current_state = AgentState.IDLE
			last_activity = activity_info.get("activity_name", "")
			
			# 停止后需要新的决策周期
			_perform_v2_cognitive_cycle()
			
		"switch":
			# 更换活动
			print("[AIAgent] %s 更换活动" % character.name)
			if ActivityManager.instance:
				ActivityManager.instance.end_activity(character.name, "更换活动")
			current_state = AgentState.IDLE
			last_activity = activity_info.get("activity_name", "")
			
			# 更换活动需要新的决策
			_perform_v2_cognitive_cycle()

# ============================================
# 调用本地部署的大模型API
# ============================================
func _call_local_llm(prompt: String, max_retries: int = 3) -> String:
	# 本地部署的大模型API配置
	# 默认使用Ollama本地服务,可通过修改配置支持其他本地模型
	var api_url = "http://localhost:11434/api/generate"
	var model_name = "qwen2.5:1.5b"  # 使用1.5B模型以提高并发性能

	print("[AIAgent] %s _call_local_llm被调用, prompt长度=%d, 最大重试=%d" % [character.name, prompt.length(), max_retries])
	
	if prompt.is_empty():
		push_error("[AIAgent] %s Prompt为空!" % character.name)
		return "{}"

	for retry in range(max_retries):
		if retry > 0:
			print("[AIAgent] %s 第%d次重试..." % [character.name, retry])
			await get_tree().create_timer(1.0 * retry).timeout  # 递增延迟

		var http_request = HTTPRequest.new()
		add_child(http_request)
		
		# 设置超时
		http_request.timeout = 30.0  # 30秒超时

		var body = {
			"model": model_name,
			"prompt": prompt,
			"stream": false,
			"options": {
				"temperature": 0.7,
				"num_predict": 200  # 减少生成长度以加快速度
			}
		}

		var json_body = JSON.stringify(body)
		var headers = ["Content-Type: application/json"]

		print("[AIAgent] %s 调用本地LLM (尝试%d/%d)..." % [character.name, retry + 1, max_retries])

		var error = http_request.request(api_url, headers, HTTPClient.METHOD_POST, json_body)
		if error != OK:
			push_error("[AIAgent] HTTP请求失败: %d" % error)
			print("[AIAgent] %s HTTP请求错误: %d" % [character.name, error])
			http_request.queue_free()
			continue  # 重试

		print("[AIAgent] %s 等待LLM响应..." % character.name)
		
		# 等待响应
		var result = await http_request.request_completed
		http_request.queue_free()

		var response_code = result[1]
		var body_text = result[3].get_string_from_utf8()
		
		print("[AIAgent] %s 收到HTTP响应, code=%d, body长度=%d" % [character.name, response_code, body_text.length()])

		if response_code == 0:
			print("[AIAgent] %s 连接失败，准备重试..." % character.name)
			continue  # 重试

		if response_code != 200:
			push_error("[AIAgent] API错误: %d, %s" % [response_code, body_text])
			print("[AIAgent] %s API错误: %s" % [character.name, body_text])
			continue  # 重试

		# 解析Ollama响应
		var json = JSON.new()
		var parse_result = json.parse(body_text)
		if parse_result != OK:
			push_error("[AIAgent] JSON解析失败: %s" % body_text)
			print("[AIAgent] %s JSON解析失败: %s" % [character.name, body_text])
			continue  # 重试

		var response_data = json.get_data()
		var response_text = response_data.get("response", "")

		if response_text.is_empty():
			print("[AIAgent] %s 响应为空，准备重试..." % character.name)
			continue  # 重试

		print("[AIAgent] %s 成功收到LLM响应: %s" % [character.name, response_text.substr(0, 100)])
		return response_text

	# 所有重试都失败
	push_error("[AIAgent] %s 调用LLM失败，已重试%d次" % [character.name, max_retries])
	return "{}"

# ============================================
# 解析决策响应为ActionRequest
# ============================================
func _parse_decision_response(response: String) -> ActionRequest:
	# 尝试从响应中提取JSON
	var json_text = _extract_json_from_text(response)

	var json = JSON.new()
	var parse_result = json.parse(json_text)

	if parse_result != OK:
		print("[AIAgent] 无法解析决策响应,使用默认WAIT: %s" % response)
		return ActionRequest.new(character.name, ActionRequest.ActionType.WAIT)

	var data = json.get_data()

	# 获取行动类型
	var action_type_str = data.get("action_type", "WAIT")
	var action_type = _string_to_action_type(action_type_str)

	# 创建请求
	var request = ActionRequest.new(character.name, action_type)
	request.target_id = data.get("target_id", "")
	request.target_range_id = data.get("target_range_id", "")

	# 处理两步缓存
	if data.has("cached_step2"):
		var step2_data = data.cached_step2
		if step2_data and step2_data.has("action_type"):
			var step2_type = _string_to_action_type(step2_data.action_type)
			request.cached_step2 = ActionRequest.new(character.name, step2_type)
			request.cached_step2.target_id = step2_data.get("target_id", "")

	print("[AIAgent] %s 解析决策: %s" % [character.name, request.get_action_name()])
	return request

# ============================================
# 从文本中提取JSON
# ============================================
func _extract_json_from_text(text: String) -> String:
	# 查找JSON代码块
	var json_start = text.find("{")
	var json_end = text.rfind("}")

	if json_start >= 0 and json_end > json_start:
		return text.substr(json_start, json_end - json_start + 1)

	return text

# ============================================
# 字符串转行动类型
# ============================================
func _string_to_action_type(type_str: String) -> ActionRequest.ActionType:
	match type_str.to_upper():
		"MOVE_TO_RANGE":
			return ActionRequest.ActionType.MOVE_TO_RANGE
		"START_DIALOGUE":
			return ActionRequest.ActionType.START_DIALOGUE
		"JOIN_DIALOGUE":
			return ActionRequest.ActionType.JOIN_DIALOGUE
		"EXIT_DIALOGUE":
			return ActionRequest.ActionType.EXIT_DIALOGUE
		"START_SPORTS":
			return ActionRequest.ActionType.START_SPORTS
		"END_SPORTS":
			return ActionRequest.ActionType.END_SPORTS
		"START_STUDY":
			return ActionRequest.ActionType.START_STUDY
		"END_STUDY":
			return ActionRequest.ActionType.END_STUDY
		"WAIT", _:
			return ActionRequest.ActionType.WAIT

# ============================================
# V2: 自然语言决策
# ============================================
func _make_natural_decision(perception: Dictionary) -> String:
	"""
	V2: 生成自然语言决策描述
	
	返回:
		自然语言描述的决策意图（如"我想去图书馆自习数学"）
	"""
	print("[AIAgent] %s 开始自然语言决策..." % character.name)
	
	# 添加随机延迟，避免所有Agent同时调用LLM
	# 使用基于角色名的固定偏移 + 随机延迟，确保分散
	var name_hash = character.name.hash()
	var fixed_delay = (abs(name_hash) % 10) * 0.5  # 0-5秒基于名字的固定延迟
	var random_delay = randf() * 1.0  # 0-1秒随机延迟
	var total_delay = fixed_delay + random_delay
	print("[AIAgent] %s 等待 %.2f 秒以避免并发 (固定%.2f + 随机%.2f)..." % [character.name, total_delay, fixed_delay, random_delay])
	await get_tree().create_timer(total_delay).timeout
	
	# V2: 使用PromptBuilder从文件加载模板
	var prompt = PromptBuilder.build_natural_decision_prompt(self, perception)
	print("[AIAgent] %s Prompt构建完成, 长度=%d" % [character.name, prompt.length()])
	
	if prompt.is_empty():
		push_error("[AIAgent] %s Prompt为空,无法调用LLM" % character.name)
		return "{}"
	
	# 调用LLM
	var response = await _call_local_llm(prompt)
	print("[AIAgent] %s LLM响应: %s" % [character.name, response.substr(0, 50)])
	
	# 提取决策文本
	var decision = _extract_decision_text(response)
	last_natural_decision = decision
	
	print("[AIAgent] %s 最终决策: %s" % [character.name, decision])
	return decision

func _extract_decision_text(response: String) -> String:
	"""从LLM响应中提取决策文本"""
	# 清理响应文本
	var text = response.strip_edges()
	
	# 移除可能的引号
	if text.begins_with("\"") and text.ends_with("\""):
		text = text.substr(1, text.length() - 2)
	
	# 限制长度
	if text.length() > 200:
		text = text.substr(0, 200)
	
	return text.strip_edges()

# ============================================
# V2: 提交决策到协调器
# ============================================
func _submit_decision_to_coordinator(decision: String) -> void:
	"""将自然语言决策提交到ActivityCoordinator"""
	print("[AIAgent] %s _submit_decision_to_coordinator被调用" % character.name)
	print("[AIAgent] %s ActivityCoordinator.instance = %s" % [character.name, ActivityCoordinator.instance])
	if ActivityCoordinator.instance:
		print("[AIAgent] %s 调用ActivityCoordinator.submit_decision..." % character.name)
		ActivityCoordinator.instance.submit_decision(character.name, decision)
		print("[AIAgent] %s 已提交决策到协调器: %s" % [character.name, decision])
	else:
		push_warning("[AIAgent] %s ActivityCoordinator未找到，无法提交决策" % character.name)

# ============================================
# V2: 接收活动序列（由协调器调用）
# ============================================
func receive_activity_sequence(activities: Array[Activity]) -> void:
	"""
	V2: 接收协调器分配的活动序列
	
	参数:
		activities: 最多3个Activity组成的序列
	"""
	activity_cache = activities
	current_activity_index = 0
	
	print("[AIAgent] %s 收到 %d 个活动" % [character.name, activities.size()])
	for i in range(activities.size()):
		print("  [%d] %s" % [i + 1, activities[i].activity_name])

# ============================================
# V2: 执行缓存的下一个活动
# ============================================
func _execute_next_cached_activity() -> void:
	"""执行活动缓存中的下一个活动"""
	if current_activity_index >= activity_cache.size():
		# 所有活动执行完毕
		activity_cache.clear()
		current_activity_index = 0
		print("[AIAgent] %s 所有缓存活动已执行完毕" % character.name)
		return
	
	var activity = activity_cache[current_activity_index]
	print("[AIAgent] %s 执行活动 [%d/%d]: %s" % [
		character.name, 
		current_activity_index + 1, 
		activity_cache.size(),
		activity.activity_name
	])
	
	# 执行活动
	_execute_v2_activity(activity)
	
	# 移动到下一步
	current_activity_index += 1

# ============================================
# V2: 执行具体活动
# ============================================
func _execute_v2_activity(activity: Activity) -> void:
	"""执行V2 Activity"""
	match activity.activity_type:
		Activity.ActivityType.MOVE_TO:
			_execute_v2_move(activity)
		Activity.ActivityType.NORMAL_DIALOGUE:
			_execute_v2_dialogue(activity)
		Activity.ActivityType.WHISPER:
			_execute_v2_whisper(activity)
		Activity.ActivityType.LISTEN:
			_execute_v2_listen(activity)
		Activity.ActivityType.QA_TEACHER:
			_execute_v2_qa(activity)
		Activity.ActivityType.SELF_STUDY:
			_execute_v2_study(activity)
		Activity.ActivityType.SPORTS:
			_execute_v2_sports(activity)
		Activity.ActivityType.GROUP_DISCUSSION:
			_execute_v2_discussion(activity)
		_:
			print("[AIAgent] %s 未知活动类型: %s" % [character.name, activity.activity_type])

func _execute_v2_move(activity: Activity) -> void:
	"""执行移动活动"""
	# 初始化移动执行器
	if not movement_executor:
		var nav_agent = character.get_node_or_null("NavigationAgent2D")
		movement_executor = MovementExecutor.new(character, nav_agent)
	
	# 执行移动
	var result = movement_executor.execute_move_activity(activity)
	
	if result.success:
		current_state = AgentState.EXECUTING_ACTION
		print("[AIAgent] %s 开始移动，预计%.1f分钟" % [character.name, result.estimated_duration])
	else:
		print("[AIAgent] %s 移动失败: %s" % [character.name, result.reason])

func _execute_v2_dialogue(activity: Activity) -> void:
	"""执行普通对话"""
	var target_agent = activity.parameters.get("target_agent", "")
	var topic = activity.parameters.get("topic", "")
	var focus = activity.focus_level
	
	# 创建对话请求
	var request = ActionRequest.new(character.name, ActionRequest.ActionType.START_DIALOGUE)
	request.target_id = target_agent
	
	# 执行
	_execute_start_dialogue(request)
	
	# V2: 记录信息接收（专注度影响）
	if information_receiver:
		# 模拟接收到的对话内容（实际应从DialogueManager获取）
		var simulated_content = "关于%s的讨论内容..." % topic
		information_receiver.receive_dialogue(target_agent, simulated_content, float(focus) / 100.0, topic)
	
	print("[AIAgent] %s 开始与 %s 对话，话题: %s，专注度: %d%%" % [character.name, target_agent, topic, focus])

func _execute_v2_whisper(activity: Activity) -> void:
	"""执行悄悄话"""
	var target_agent = activity.parameters.get("target_agent", "")
	var content = activity.parameters.get("content", "")
	var focus = activity.focus_level
	
	var request = ActionRequest.new(character.name, ActionRequest.ActionType.START_DIALOGUE)
	request.target_id = target_agent
	
	_execute_start_whisper(request)
	
	# V2: 记录悄悄话信息接收
	if information_receiver:
		information_receiver.receive_dialogue(target_agent, content, float(focus) / 100.0, "悄悄话")
	
	print("[AIAgent] %s 开始向 %s 悄悄话，专注度: %d%%" % [character.name, target_agent, focus])

func _execute_v2_listen(activity: Activity) -> void:
	"""执行聆听（上课）"""
	var focus = activity.focus_level
	var teacher = activity.parameters.get("target_teacher", "老师")
	
	# 开始上课活动
	if ActivityManager.instance:
		var context = {
			"room_name": _get_current_room_name(),
			"focus_level": float(focus) / 100.0,
			"activity_name": "听课"
		}
		ActivityManager.instance.start_activity(character.name, ActivityManager.ActivityType.CLASS, context)
	
	# V2: 记录课堂信息接收
	if information_receiver:
		# 模拟课堂内容（实际应从课程系统获取）
		var lecture_content = "今天的课程要点..."
		information_receiver.receive_lecture(teacher, lecture_content, float(focus) / 100.0, "课程")
	
	current_state = AgentState.IN_ACTIVITY
	current_activity = "听课(%d%%专注)" % focus
	print("[AIAgent] %s 开始听课，专注度: %d%%" % [character.name, focus])

func _execute_v2_qa(activity: Activity) -> void:
	"""执行课堂问答"""
	var question = activity.parameters.get("question", "")
	var is_answer = activity.parameters.get("is_answer", false)
	var focus = activity.focus_level
	
	print("[AIAgent] %s %s，专注度: %d%%" % [
		character.name,
		"回答问题" if is_answer else "提问: " + question,
		focus
	])

func _execute_v2_study(activity: Activity) -> void:
	"""执行自习"""
	var subject = activity.parameters.get("subject", "")
	var focus = activity.focus_level
	
	if ActivityManager.instance:
		var context = {
			"room_name": _get_current_room_name(),
			"focus_level": float(focus) / 100.0,
			"subject": subject,
			"activity_name": "自习" + subject
		}
		ActivityManager.instance.start_activity(character.name, ActivityManager.ActivityType.STUDY, context)
	
	current_state = AgentState.IN_ACTIVITY
	current_activity = "自习%s(%d%%专注)" % [subject, focus]
	print("[AIAgent] %s 开始自习%s，专注度: %d%%" % [character.name, subject, focus])

func _execute_v2_sports(activity: Activity) -> void:
	"""执行体育活动"""
	var sport_type = activity.parameters.get("sport_type", "")
	var intensity = activity.parameters.get("intensity", 0.5)
	var focus = activity.focus_level
	
	if ActivityManager.instance:
		var context = {
			"room_name": _get_current_room_name(),
			"focus_level": float(focus) / 100.0,
			"sport_type": sport_type,
			"intensity": intensity,
			"activity_name": "体育" + sport_type
		}
		ActivityManager.instance.start_activity(character.name, ActivityManager.ActivityType.SPORTS, context)
	
	current_state = AgentState.IN_ACTIVITY
	current_activity = "体育%s(%d%%专注)" % [sport_type, focus]
	print("[AIAgent] %s 开始%s，专注度: %d%%" % [character.name, sport_type, focus])

func _execute_v2_discussion(activity: Activity) -> void:
	"""执行小组讨论"""
	var topic = activity.parameters.get("topic", "")
	var members = activity.parameters.get("members", [])
	var focus = activity.focus_level
	
	# V2: 记录讨论信息接收
	if information_receiver:
		# 模拟讨论内容
		var discussion_content = "关于%s的讨论..." % topic
		information_receiver.receive_discussion(members, discussion_content, float(focus) / 100.0, topic)
	
	print("[AIAgent] %s 开始小组讨论，话题: %s，成员: %s，专注度: %d%%" % [
		character.name, topic, ", ".join(members), focus
	])

func _get_current_room_name() -> String:
	"""获取当前房间名称"""
	var room = _get_current_room()
	if room and room.has("room_name"):
		return room.room_name
	return "unknown"

# ============================================
# V1兼容: 提交请求到时序系统
# ============================================
func _submit_request(request: ActionRequest):
	cached_request = request
	is_waiting_execution = true
	current_state = AgentState.WAITING_FOR_CLICK

	if TimingSystem.instance:
		var success = TimingSystem.instance.submit_action_request(character.name, request)
		if success:
			print("[AIAgent] %s 请求已提交: %s" % [character.name, request.get_action_name()])
		else:
			print("[AIAgent] %s 请求提交失败" % character.name)

# ============================================
# V1兼容: 执行缓存的请求
# ============================================
func _execute_cached_request():
	if not cached_request:
		return

	print("[AIAgent] %s 执行请求: %s" % [character.name, cached_request.get_action_name()])

	current_state = AgentState.EXECUTING_ACTION
	_execute_action(cached_request)

	# 记录活动用于下一周期的体验
	last_activity = _get_activity_name(cached_request)

	# 清空缓存
	cached_request = null
	is_waiting_execution = false

# ============================================
# 行动执行分发(新增)
# ============================================
func _execute_action(request: ActionRequest):
	match request.action_type:
		ActionRequest.ActionType.MOVE_TO_RANGE:
			_execute_move(request)
		ActionRequest.ActionType.START_DIALOGUE:
			_execute_start_dialogue(request)
		ActionRequest.ActionType.START_WHISPER:
			_execute_start_whisper(request)
		ActionRequest.ActionType.JOIN_DIALOGUE:
			_execute_join_dialogue(request)
		ActionRequest.ActionType.EXIT_DIALOGUE:
			_execute_exit_dialogue(request)
		ActionRequest.ActionType.START_SPORTS:
			_execute_start_sports(request)
		ActionRequest.ActionType.END_SPORTS:
			_execute_end_sports(request)
		ActionRequest.ActionType.START_STUDY:
			_execute_start_study(request)
		ActionRequest.ActionType.END_STUDY:
			_execute_end_study(request)
		ActionRequest.ActionType.WAIT:
			_execute_wait(request)

# ============================================
# 具体行动执行(8种)
# ============================================

# 1. 路径移动
func _execute_move(request: ActionRequest):
	print("[AIAgent] %s 执行移动" % character.name)
	
	# 判断是否是悄悄话移动（根据step2判断）
	var is_whisper = false
	if cached_request and cached_request.cached_step2:
		if cached_request.cached_step2.action_type == ActionRequest.ActionType.START_WHISPER:
			is_whisper = true
	
	# 使用定位函数计算目标位置
	var target_pos = _calculate_move_target(request.target_id, is_whisper)
	
	if target_pos == Vector2.ZERO:
		print("[AIAgent] %s 移动失败：无效目标位置" % character.name)
		return
	
	# 使用CharacterController的move_to方法
	if character.has_method("move_to"):
		character.move_to(target_pos)
		_is_moving = true
		_target_position = target_pos
		print("[AIAgent] %s 开始移动到 %s" % [character.name, str(target_pos)])
	else:
		print("[AIAgent] %s 移动失败：CharacterController没有move_to方法" % character.name)

func _calculate_move_target(target_name: String, is_whisper: bool = false) -> Vector2:
	"""
	定位函数：根据目标名称计算移动目标坐标
	
	参数:
		target_name: 子场景名或角色名
		is_whisper: 是否是悄悄话移动（需要贴身）
		
	返回:
		目标坐标 Vector2
		
	逻辑:
		1. 如果target_name是子场景名（非当前子场景）→ 返回该场景内随机坐标
		2. 如果target_name是角色名:
		   - 悄悄话模式 → 贴身位置（±15px）
		   - 同一中范围 → 目标身边小范围（±30px）
		   - 不同中范围 → 目标中范围中心（±20%）
	"""
	if target_name.is_empty():
		return Vector2.ZERO
	
	# 先尝试查找角色
	var target_character = _find_character_by_name(target_name)
	
	if target_character:
		# 是角色名，判断位置关系
		return _calculate_target_position_for_character(target_character, is_whisper)
	else:
		# 不是角色名，尝试作为子场景名
		return _calculate_target_position_for_room(target_name)

func _find_character_by_name(char_name: String) -> Node:
	"""根据名称查找角色节点"""
	var characters = get_tree().get_nodes_in_group("character")
	for char in characters:
		if char.name == char_name:
			return char
	return null

func _calculate_target_position_for_character(target_char: Node, is_whisper: bool = false) -> Vector2:
	"""
	计算移动到目标角色的位置

	参数:
		target_char: 目标角色节点
		is_whisper: 是否是悄悄话(需要贴身)

	逻辑:
		- 悄悄话模式 → 贴身位置(15像素内)
		- 同一中范围且非悄悄话 → 目标身边小范围(30像素内)
		- 不同中范围 → 目标所在中范围的中心位置(±20%随机偏移)
	"""
	if not target_char:
		return Vector2.ZERO

	# 获取当前角色和目标角色的位置
	var my_pos = character.global_position
	var target_pos = target_char.global_position

	# 获取当前房间
	var current_room = _get_current_room()
	var target_room = _get_current_room_at_position(target_pos)

	# 判断是否在同一中范围(使用新的中范围划分系统)
	var in_same_medium_range = false
	if current_room and target_room and current_room == target_room:
		in_same_medium_range = _is_in_same_medium_range(current_room, my_pos, target_pos)

	if is_whisper:
		# 悄悄话模式:贴身位置(15像素内)
		var whisper_offset = Vector2(randf_range(-15, 15), randf_range(-15, 15))
		return target_pos + whisper_offset
	elif in_same_medium_range:
		# 同一中范围:移动到目标身边小范围(30像素内)
		var small_range_offset = Vector2(randf_range(-30, 30), randf_range(-30, 30))
		return target_pos + small_range_offset
	else:
		# 不同中范围:移动到目标所在中范围的中心位置
		if target_room:
			var target_medium_range = _get_medium_range_description(target_room, target_pos)
			var range_center = _get_medium_range_center_position(target_room, target_medium_range)
			# 在中范围中心附近随机偏移(±20%)
			var random_offset = Vector2(randf_range(-20, 20), randf_range(-20, 20))
			return range_center + random_offset
		else:
			# 找不到房间,直接移动到目标附近
			var medium_range_offset = Vector2(randf_range(-50, 50), randf_range(-50, 50))
			return target_pos + medium_range_offset

func _calculate_target_position_for_room(room_name: String) -> Vector2:
	"""
	计算移动到子场景的位置

	返回该场景内的随机坐标(不要离中心太远)
	"""
	var room = _get_room_by_name(room_name)
	if not room:
		print("[AIAgent] 未找到子场景: %s" % room_name)
		return Vector2.ZERO

	return _get_random_position_in_room(room, 0.3)  # 30%偏移

func _get_random_position_in_room(room, max_offset_ratio: float = 0.3) -> Vector2:
	"""
	获取房间内的随机位置

	参数:
		room: 房间数据
		max_offset_ratio: 最大偏移比例(相对于房间半宽/半高)
		              0.3表示在中心±30%范围内随机
	"""
	if not room:
		return Vector2.ZERO

	var room_pos = room.position
	var room_size = room.size if room.has("size") else Vector2(200, 100)

	# 在中心附近随机偏移(不要离中心太远)
	var half_width = room_size.x * 0.5
	var half_height = room_size.y * 0.5

	var offset_x = randf_range(-half_width * max_offset_ratio, half_width * max_offset_ratio)
	var offset_y = randf_range(-half_height * max_offset_ratio, half_height * max_offset_ratio)

	return room_pos + Vector2(offset_x, offset_y)

func _get_current_room_at_position(pos: Vector2):
	"""获取指定位置所在的房间"""
	if not room_manager:
		return null
	return room_manager.get_current_room(room_manager.rooms, pos)

# 2. 开始对话
func _execute_start_dialogue(request: ActionRequest):
	print("[AIAgent] %s 开始对话" % character.name)
	current_state = AgentState.IN_DIALOGUE
	current_activity = "对话"
	activity_start_time = Time.get_unix_time_from_system()

	# 获取目标Agent
	var target_agent = _find_agent_by_id(request.target_id)
	if not target_agent:
		print("[AIAgent] %s 开始对话失败:目标不存在" % character.name)
		current_state = AgentState.IDLE
		return

	# 记录对话对象，用于感知系统显示
	set_meta("dialogue_partner", request.target_id)
	
	# 同时设置对方的对话对象
	if target_agent.has_method("set_meta"):
		target_agent.set_meta("dialogue_partner", character.name)

	# 向DialogueManager注册新对话
	# TODO: DialogueManager.start_dialogue(self, target_agent)

	print("[AIAgent] %s 已向 %s 发起对话" % [character.name, request.target_id])

# 3. 开始悄悄话(私密对话)
func _execute_start_whisper(request: ActionRequest):
	print("[AIAgent] %s 开始悄悄话" % character.name)
	current_state = AgentState.IN_DIALOGUE
	current_activity = "悄悄话"
	activity_start_time = Time.get_unix_time_from_system()

	# 获取目标Agent
	var target_agent = _find_agent_by_id(request.target_id)
	if not target_agent:
		print("[AIAgent] %s 开始悄悄话失败:目标不存在" % character.name)
		current_state = AgentState.IDLE
		return

	# 记录悄悄话对象，用于感知系统显示
	set_meta("whisper_partner", request.target_id)
	
	# 同时设置对方的悄悄话对象
	if target_agent.has_method("set_meta"):
		target_agent.set_meta("whisper_partner", character.name)

	# 向DialogueManager注册悄悄话(私密对话)
	# TODO: DialogueManager.start_whisper(self, target_agent)

	print("[AIAgent] %s 已向 %s 发起悄悄话" % [character.name, request.target_id])

# 4. 加入对话
func _execute_join_dialogue(request: ActionRequest):
	print("[AIAgent] %s 加入对话" % character.name)
	current_state = AgentState.IN_DIALOGUE
	current_activity = "对话"
	activity_start_time = Time.get_unix_time_from_system()

	# 获取对话ID或目标
	var dialogue_id = request.target_id

	# 向DialogueManager申请加入
	# TODO: DialogueManager.join_dialogue(self, dialogue_id)

	print("[AIAgent] %s 已加入对话 %s" % [character.name, dialogue_id])

# 4. 退出对话
func _execute_exit_dialogue(request: ActionRequest):
	print("[AIAgent] %s 退出对话" % character.name)

	# 计算对话时长
	var duration = Time.get_unix_time_from_system() - activity_start_time

	# 清除对话对象记录
	remove_meta("dialogue_partner")
	remove_meta("whisper_partner")

	# 向DialogueManager通知退出
	# TODO: DialogueManager.exit_dialogue(self)

	current_state = AgentState.IDLE
	current_activity = ""

	print("[AIAgent] %s 已退出对话,时长:%.1f秒" % [character.name, duration])

# 5. 开始体育活动
func _execute_start_sports(request: ActionRequest):
	print("[AIAgent] %s 开始体育活动" % character.name)

	# 验证当前在体育馆
	var current_room = _get_current_room()
	if not current_room or current_room.room_name != "体育馆":
		print("[AIAgent] %s 开始体育活动失败:不在体育馆" % character.name)
		return

	current_state = AgentState.IN_ACTIVITY
	current_activity = "体育活动"
	activity_start_time = Time.get_unix_time_from_system()

	# 向ActivityManager注册
	# TODO: ActivityManager.start_activity(self, "sports")

	print("[AIAgent] %s 已开始体育活动" % character.name)

# 6. 结束体育活动
func _execute_end_sports(request: ActionRequest):
	print("[AIAgent] %s 结束体育活动" % character.name)

	var duration = Time.get_unix_time_from_system() - activity_start_time

	# 向ActivityManager通知结束
	# TODO: ActivityManager.end_activity(self, "sports")

	current_state = AgentState.IDLE
	current_activity = ""

	print("[AIAgent] %s 已结束体育活动,时长:%.1f秒" % [character.name, duration])

# 7. 开始自习
func _execute_start_study(request: ActionRequest):
	print("[AIAgent] %s 开始自习" % character.name)

	# 验证当前在图书馆或自习室
	var current_room = _get_current_room()
	var valid_rooms = ["图书馆", "自习室"]
	if not current_room or not current_room.room_name in valid_rooms:
		print("[AIAgent] %s 开始自习失败:不在图书馆或自习室" % character.name)
		return

	current_state = AgentState.IN_ACTIVITY
	current_activity = "自习"
	activity_start_time = Time.get_unix_time_from_system()

	# 向ActivityManager注册
	# TODO: ActivityManager.start_activity(self, "study")

	print("[AIAgent] %s 已开始自习" % character.name)

# 8. 结束自习
func _execute_end_study(request: ActionRequest):
	print("[AIAgent] %s 结束自习" % character.name)

	var duration = Time.get_unix_time_from_system() - activity_start_time

	# 向ActivityManager通知结束
	# TODO: ActivityManager.end_activity(self, "study")

	current_state = AgentState.IDLE
	current_activity = ""

	print("[AIAgent] %s 已结束自习,时长:%.1f秒" % [character.name, duration])

# 9. 等待
func _execute_wait(request: ActionRequest):
	print("[AIAgent] %s 等待" % character.name)
	current_state = AgentState.IDLE
	# 无需额外操作



func _physics_process(delta: float):
	# V2: 更新MovementExecutor
	if movement_executor and movement_executor.is_moving():
		movement_executor.update(delta)
	
	# 处理移动检查
	if _is_moving and character:
		_movement_check_timer += delta

		# 定期检测是否到达目标
		if _movement_check_timer >= MOVEMENT_CHECK_INTERVAL:
			_movement_check_timer = 0.0

			# 检查是否到达目标(使用CharacterController的导航路径)
			var current_pos = character.global_position
			var distance_to_target = current_pos.distance_to(_target_position)

			# 如果距离小于阈值,认为到达目标
			if distance_to_target < 20.0:  # 20像素阈值
				_is_moving = false
				print("[AIAgent] %s 移动完成,距离目标:%.1f" % [character.name, distance_to_target])

				# 检查是否有缓存的step2
				if cached_request and cached_request.cached_step2:
					_validate_and_execute_step2()
				return

func _get_room_by_name(room_name: String):
	"""根据房间名称获取房间数据"""
	if not room_manager:
		return null

	# 遍历所有房间查找匹配的名称
	for room_id in room_manager.rooms:
		var room = room_manager.rooms[room_id]
		if room.name == room_name or room.room_name == room_name:
			return room

	return null

# ============================================
# 中范围划分系统
# ============================================

enum MediumRangeType {
	FOUR_QUADRANT,    # 4象限(教室、图书馆、自习室、食堂)
	LEFT_RIGHT,       # 左右分区(大走廊)
	SINGLE            # 单区域(小走廊)
}

func _get_room_medium_range_type(room_name: String) -> MediumRangeType:
	"""
	获取房间的中范围划分类型

	4象限:教室、图书馆、自习室、食堂
	左右分区:大走廊
	单区域:小走廊
	"""
	var four_quadrant_rooms = ["教室", "图书馆", "自习室", "食堂"]
	var left_right_rooms = ["大走廊"]

	for room_prefix in four_quadrant_rooms:
		if room_prefix in room_name:
			return MediumRangeType.FOUR_QUADRANT

	for room_prefix in left_right_rooms:
		if room_prefix in room_name:
			return MediumRangeType.LEFT_RIGHT

	return MediumRangeType.SINGLE

func _get_quadrant_at_position(room, pos: Vector2) -> int:
	"""
	获取指定位置在房间中的象限编号

	象限定义(平面直角坐标系):
	- 右上 = 1(x > center.x, y < center.y)
	- 左上 = 2(x < center.x, y < center.y)
	- 左下 = 3(x < center.x, y > center.y)
	- 右下 = 4(x > center.x, y > center.y)

	注意:Godot中y轴向下为正,所以y < center.y是上方
	"""
	if not room:
		return 0

	var room_pos = room.position
	var is_right = pos.x >= room_pos.x
	var is_top = pos.y <= room_pos.y  # y小的是上方

	if is_right and is_top:
		return 1  # 右上
	elif not is_right and is_top:
		return 2  # 左上
	elif not is_right and not is_top:
		return 3  # 左下
	else:
		return 4  # 右下

func _get_left_right_zone_at_position(room, pos: Vector2) -> String:
	"""
	获取指定位置在走廊中的左右分区

	- 左区:x < center.x
	- 右区:x >= center.x
	"""
	if not room:
		return ""

	if pos.x < room.position.x:
		return "左区"
	else:
		return "右区"

func _get_medium_range_description(room, pos: Vector2) -> String:
	"""获取指定位置的中范围描述"""
	if not room:
		return ""

	var range_type = _get_room_medium_range_type(room.room_name)

	match range_type:
		MediumRangeType.FOUR_QUADRANT:
			var quadrant = _get_quadrant_at_position(room, pos)
			return "第%d象限" % quadrant
		MediumRangeType.LEFT_RIGHT:
			var zone = _get_left_right_zone_at_position(room, pos)
			return zone
		MediumRangeType.SINGLE:
			return "中心区域"
		_:
			return ""

func _is_in_same_medium_range(room, pos1: Vector2, pos2: Vector2) -> bool:
	"""判断两个位置是否在同一中范围内"""
	if not room:
		return false

	var range_type = _get_room_medium_range_type(room.room_name)

	match range_type:
		MediumRangeType.FOUR_QUADRANT:
			var q1 = _get_quadrant_at_position(room, pos1)
			var q2 = _get_quadrant_at_position(room, pos2)
			return q1 == q2 and q1 != 0
		MediumRangeType.LEFT_RIGHT:
			var z1 = _get_left_right_zone_at_position(room, pos1)
			var z2 = _get_left_right_zone_at_position(room, pos2)
			return z1 == z2 and z1 != ""
		MediumRangeType.SINGLE:
			return true  # 单区域总是同一中范围
		_:
			return false

func _get_medium_range_center_position(room, range_desc: String) -> Vector2:
	"""
	获取中范围的中心位置

	参数:
		range_desc: 中范围描述,如"第1象限"、"左区"
	"""
	if not room:
		return Vector2.ZERO

	var room_pos = room.position
	var room_size = room.size if room.has("size") else Vector2(200, 100)
	var half_width = room_size.x * 0.5
	var half_height = room_size.y * 0.5

	var range_type = _get_room_medium_range_type(room.room_name)

	match range_type:
		MediumRangeType.FOUR_QUADRANT:
			# 解析象限编号
			var quadrant = int(range_desc.replace("第", "").replace("象限", ""))
			match quadrant:
				1:  # 右上
					return room_pos + Vector2(half_width * 0.5, -half_height * 0.5)
				2:  # 左上
					return room_pos + Vector2(-half_width * 0.5, -half_height * 0.5)
				3:  # 左下
					return room_pos + Vector2(-half_width * 0.5, half_height * 0.5)
				4:  # 右下
					return room_pos + Vector2(half_width * 0.5, half_height * 0.5)

		MediumRangeType.LEFT_RIGHT:
			if range_desc == "左区":
				return room_pos + Vector2(-half_width * 0.5, 0)
			elif range_desc == "右区":
				return room_pos + Vector2(half_width * 0.5, 0)

		MediumRangeType.SINGLE:
			return room_pos

	return room_pos

func _find_agent_by_id(agent_id: String):
	var agents = get_tree().get_nodes_in_group("ai_agents")
	for agent in agents:
		if agent.name == agent_id:
			return agent
	return null

# ============================================
# 两步缓存验证
# ============================================
func _validate_and_execute_step2():
	if not cached_request or not cached_request.cached_step2:
		return

	print("[AIAgent] %s 验证并执行Step2" % character.name)

	# 立即感知(无体验)
	var new_perception = _perceive()

	var step2 = cached_request.cached_step2

	# 验证Step2是否仍然有效
	if _is_step2_valid(step2, new_perception):
		print("[AIAgent] %s Step2有效,继续执行" % character.name)
		_execute_action(step2)
		last_activity = _get_activity_name(step2)
	else:
		print("[AIAgent] %s Step2无效,重新决策" % character.name)
		_perform_v2_cognitive_cycle()

	# 清空缓存
	cached_request = null
	is_waiting_execution = false

func _is_step2_valid(step2: ActionRequest, perception: Dictionary) -> bool:
	# 检查目标是否仍然存在
	if step2.target_id:
		var target = _find_agent_by_id(step2.target_id)
		if not target:
			print("[AIAgent] Step2无效:目标已不存在")
			return false

	# 检查时间约束是否变化
	if TimelineState.instance:
		var constraints = TimelineState.instance.get_constraints()
		if step2.action_type == ActionRequest.ActionType.START_DIALOGUE:
			if not constraints.can_start_dialogue:
				print("[AIAgent] Step2无效:现在不能开始对话")
				return false

	# 其他验证...

	return true

# ============================================
# 辅助方法
# ============================================
func _get_activity_name(request: ActionRequest) -> String:
	match request.action_type:
		ActionRequest.ActionType.MOVE_TO_RANGE:
			return "移动"
		ActionRequest.ActionType.START_DIALOGUE, ActionRequest.ActionType.JOIN_DIALOGUE:
			return "对话"
		ActionRequest.ActionType.START_SPORTS:
			return "体育活动"
		ActionRequest.ActionType.START_STUDY:
			return "自习"
		_:
			return ""

func _get_room_manager():
	var root = get_tree().current_scene
	if root and root.has_node("RoomManager"):
		return root.get_node("RoomManager")
	return null

func _get_current_room():
	if not room_manager:
		return null
	return room_manager.get_current_room(room_manager.rooms, character.global_position)

func _get_agents_in_same_room_with_status() -> Array:
	"""
	获取同场景其他Agent列表，包含活动状态
	
	返回:
		Array[Dictionary]: 每个元素包含agent信息和活动状态
	"""
	var agents = []
	var current_room = _get_current_room()
	if not current_room:
		return agents

	# 遍历所有AIAgent，筛选在同一房间的
	var all_agents = get_tree().get_nodes_in_group("ai_agents")
	for agent in all_agents:
		if agent != self and agent.character:
			var agent_room = _get_current_room_at_position(agent.character.global_position)
			if agent_room == current_room:
				agents.append({
					"name": agent.character.name,
					"position": agent.character.global_position,
					"state": agent.current_state,
					"activity": agent.current_activity,
					"activity_status": _get_character_activity_status(agent.character)
				})
	
	return agents

func _get_agents_in_same_room() -> Array:
	var agents = []
	var current_room = _get_current_room()
	if not current_room:
		return agents

	# TODO: 获取同房间其他Agent
	return agents

func _get_personality() -> Dictionary:
	if not character:
		return {}
	return CharacterPersonality.get_personality(character.name)

# ============================================
# 玩家控制(保留)
# ============================================
func toggle_player_control(enabled: bool):
	is_player_controlled = enabled
	if enabled:
		current_state = AgentState.IDLE
		print("[AIAgent] %s 切换到玩家控制" % character.name)
	else:
		print("[AIAgent] %s 切换到AI控制" % character.name)

# ============================================
# 场景描述生成(新版)
# ============================================
func generate_scene_description() -> String:
	var description = ""

	# 1. 所有可用场景的精确名称和功能
	description += "【所有可用场景】"
	description += _get_all_rooms_description()

	# 2. 当前场景信息
	var current_room = _get_current_room()
	if current_room:
		description += "\n\n【当前场景】"
		description += "\n你当前所在场景:" + current_room.room_name
		description += "\n场景功能:" + current_room.room_desc

		# 添加情境参数(使用感知系统)
		description += _get_room_situation_params(current_room.room_name)

		# 3. 当前场景内的角色及中范围关系
		description += _get_characters_in_medium_range_description()

	# 4. 时间信息
	description += "\n\n【时间信息】"
	description += get_environment_info()

	return description

func _get_all_rooms_description() -> String:
	"""获取所有场景的精确名称和功能描述"""
	var desc = ""

	if not room_manager:
		return desc

	for room_id in room_manager.rooms:
		var room = room_manager.rooms[room_id]
		desc += "\n- " + room.room_name + ":" + room.room_desc

	return desc

func _get_characters_in_medium_range_description() -> String:
	"""
	获取当前场景内所有角色的精确名称,以及中范围关系
	同时感知每个角色的活动状态

	按中范围分组显示角色,并标注每个角色所在的具体中范围和活动状态
	"""
	var desc = "\n\n【场景内角色】"

	var current_room = _get_current_room()
	if not current_room:
		return desc + "\n无"

	var room_characters = get_room_characters(current_room)

	if room_characters.size() == 0:
		return desc + "\n当前场景内没有其他角色"

	# 获取当前角色的中范围
	var my_pos = character.global_position
	var my_medium_range = _get_medium_range_description(current_room, my_pos)

	desc += "\n你当前所在中范围:" + my_medium_range

	# 按中范围分组
	var characters_by_range = {}

	for char in room_characters:
		var char_pos = char.global_position
		var char_medium_range = _get_medium_range_description(current_room, char_pos)
		var char_personality = CharacterPersonality.get_personality(char.name)
		var position = char_personality.get("position", "未知职位")
		var distance = my_pos.distance_to(char_pos)
		
		# 获取该角色的活动状态
		var activity_status = _get_character_activity_status(char)

		var char_info = {
			"name": char.name,
			"position": position,
			"distance": distance,
			"medium_range": char_medium_range,
			"activity_status": activity_status
		}

		if not characters_by_range.has(char_medium_range):
			characters_by_range[char_medium_range] = []
		characters_by_range[char_medium_range].append(char_info)

	# 输出同一中范围的角色
	if characters_by_range.has(my_medium_range):
		desc += "\n\n【同一中范围内(可普通对话)】"
		for char_info in characters_by_range[my_medium_range]:
			desc += "\n- " + char_info.name + "(" + char_info.position + ")：" + char_info.activity_status

	# 输出其他中范围的角色
	var other_ranges = []
	for range_name in characters_by_range.keys():
		if range_name != my_medium_range:
			other_ranges.append(range_name)

	if other_ranges.size() > 0:
		desc += "\n\n【其他中范围(需移动才能对话)】"
		for range_name in other_ranges:
			desc += "\n" + range_name + ":"
			for char_info in characters_by_range[range_name]:
				desc += "\n  - " + char_info.name + "(" + char_info.position + "),距离约" + str(int(char_info.distance)) + "米：" + char_info.activity_status

	return desc

func _get_character_activity_status(char_node: Node) -> String:
	"""
	获取指定角色的活动状态描述
	
	返回:
		"未在进行活动" 或具体活动描述，如：
		- "正在移动"
		- "正在与 XXX 对话"
		- "正在自习"
		- "正在进行体育活动"
		- "正在悄悄话"
	"""
	# 获取角色的AIAgent组件
	var agent = char_node.get_node_or_null("AIAgent")
	if not agent:
		return "未在进行活动"
	
	# 根据当前状态返回活动描述
	match agent.current_state:
		AgentState.IDLE:
			return "未在进行活动"
		AgentState.PERCEIVING:
			return "正在观察周围环境"
		AgentState.EXPERIENCING:
			return "正在体验当前活动"
		AgentState.DECIDING:
			return "正在思考下一步行动"
		AgentState.WAITING_FOR_CLICK:
			return "正在等待时机"
		AgentState.EXECUTING_ACTION:
			# 根据当前活动类型返回具体描述
			return _get_activity_description(agent)
		AgentState.IN_DIALOGUE:
			return _get_dialogue_description(agent)
		AgentState.IN_ACTIVITY:
			return _get_activity_description(agent)
		_:
			return "未在进行活动"

func _get_activity_description(agent: Node) -> String:
	"""
	根据Agent的当前活动返回描述
	"""
	var activity = agent.current_activity
	
	match activity:
		"移动":
			return "正在移动"
		"对话":
			return _get_dialogue_description(agent)
		"悄悄话":
			return _get_whisper_description(agent)
		"体育活动":
			return "正在进行体育活动"
		"自习":
			return "正在自习"
		"":
			return "未在进行活动"
		_:
			return "正在" + activity

func _get_dialogue_description(agent: Node) -> String:
	"""
	获取对话状态的描述，包括对话对象
	"""
	# 尝试从agent获取对话对象信息
	# 这里假设agent有一个属性存储对话对象名称
	var dialogue_partner = agent.get_meta("dialogue_partner", "")
	
	if dialogue_partner.is_empty():
		return "正在对话"
	else:
		return "正在与 " + dialogue_partner + " 对话"

func _get_whisper_description(agent: Node) -> String:
	"""
	获取悄悄话状态的描述，包括对话对象
	"""
	var whisper_partner = agent.get_meta("whisper_partner", "")
	
	if whisper_partner.is_empty():
		return "正在悄悄话"
	else:
		return "正在与 " + whisper_partner + " 悄悄话"

func get_environment_info() -> String:
	var environment_info = "这是一所初中学校,有教室、食堂、走廊和体育馆。"
	environment_info += "教室分为北侧的主教学区和南侧的小组讨论区,食堂提供午餐,体育馆可以进行体育活动。"

	# 添加时间信息
	if TimelineState.instance:
		var period = TimelineState.instance.current_period
		var subject = TimelineState.instance.current_subject

		match period:
			"class_time":
				environment_info += "\n现在是上课时间," + subject + "正在进行中。"
			"break_time":
				environment_info += "\n现在是午休时间,学生们正在用餐。"
			"discussion_time":
				environment_info += "\n现在是小组讨论时间。"
			"activity_time":
				environment_info += "\n现在是活动时间。"
			_:
				environment_info += "\n现在是自由活动时间。"

	return environment_info

func get_room_objects(room) -> Array:
	if not room:
		return []

	var room_objects = []
	var objects = get_tree().get_nodes_in_group("interactable")

	for obj in objects:
		if room_manager and room_manager.is_position_in_room(obj.global_position, room):
			room_objects.append(obj)

	return room_objects

func get_room_characters(room) -> Array:
	if not room:
		return []

	var room_characters = []
	var characters = get_tree().get_nodes_in_group("character")

	for char in characters:
		if char != character and room_manager and room_manager.is_position_in_room(char.global_position, room):
			room_characters.append(char)

	return room_characters

func get_object_info(obj: Node2D) -> String:
	var info = obj.name

	# 根据物品类型添加功能描述
	if obj is StaticBody2D:
		if "Chair" in obj.name or obj.is_in_group("chairs"):
			info += "(一把椅子,可以坐下休息)"
		elif "Desk" in obj.name:
			info += "(一张桌子,可以在这里学习)"
		elif "Computer" in obj.name:
			info += "(一台电脑)"
		elif "Bookshelf" in obj.name:
			info += "(一个书架,存放各种书籍)"
		else:
			info += "(一个物品)"

	# 添加距离信息
	var distance = int(obj.global_position.distance_to(character.global_position))
	info += ",距离约" + str(distance) + "米"

	return info

func _get_room_situation_params(room_name: String) -> String:
	var personality = CharacterPersonality.get_personality(character.name)
	var is_depression = personality.get("role_type", "") == "depression_risk_student"

	# 使用感知系统获取Agent对情境的主观感知
	var params_desc = PerceptionSystem.get_belief_description(character.name, room_name, is_depression)

	return params_desc

func get_character_status_info(char_node = null) -> String:
	var target_character = char_node if char_node else character
	var status_info = ""

	# 基本状态信息
	var mood = target_character.get_meta("mood", "普通")
	status_info += "\n\n个人状态信息:"
	status_info += "\n- 心情状态:" + mood

	# 使用MemoryManager获取格式化的记忆信息
	status_info += MemoryManager.get_formatted_memories_for_prompt(target_character, 5)

	return status_info

func _find_target_by_name(target_name: String):
	var agents = get_tree().get_nodes_in_group("ai_agents")
	for agent in agents:
		if agent.name == target_name:
			return agent
	return null

func _add_memory(target_character, content: String):
	MemoryManager.add_memory(target_character, content, MemoryManager.MemoryType.PERSONAL, MemoryManager.MemoryImportance.NORMAL)

# ============================================
# MVT决策：检查是否应该离开当前情境
# ============================================
func _check_mvt_leave_decision(room_name: String, time_in_room: float,
							   personality: Dictionary, is_depression: bool) -> Dictionary:
	"""
	使用MVT理论检查是否应该离开当前情境
	
	返回:
		{
			"should_leave": bool,      # 是否应该离开
			"optimal_time": float,     # 建议的最优停留时间
			"current_time": float,     # 当前已停留时间
			"reason": String           # 决策原因
		}
	"""
	# 获取认知参数
	var params = UtilitySystem.get_agent_utility_params(personality)
	var p_base = params.p_base
	var eta_s = params.eta_s
	var eta_a = params.eta_a
	var beta_effort = params.beta_effort
	var alpha = params.alpha
	
	# 获取当前情境的感知参数
	var perceived_params = PerceptionSystem.get_perceived_params(
		character.name, room_name, is_depression
	)
	var perceived_S = perceived_params.S
	var perceived_a = perceived_params.a
	
	# 获取当前情境的努力成本（从RewardSystem获取）
	var effort = 0.5  # 默认值
	if RewardSystem.instance:
		var room_data = RewardSystem.instance._get_room_objective_params(room_name)
		effort = room_data.get("E", 0.5)
	
	# 使用MVT公式计算最优停留时间
	var optimal_time = UtilitySystem.calculate_optimal_time(
		perceived_S, perceived_a, effort, alpha, beta_effort, p_base, eta_s, eta_a
	)
	
	# 决策：如果当前时间 >= 最优时间，建议离开
	var should_leave = time_in_room >= optimal_time
	
	var reason = ""
	if should_leave:
		reason = "已停留%.1f秒，达到MVT预测的最优时间(%.1f秒)，继续停留的边际收益将低于背景奖励率" % [time_in_room, optimal_time]
	else:
		var remaining = optimal_time - time_in_room
		reason = "已停留%.1f秒，距离MVT预测的最优时间还有%.1f秒" % [time_in_room, remaining]
	
	return {
		"should_leave": should_leave,
		"optimal_time": optimal_time,
		"current_time": time_in_room,
		"reason": reason
	}
