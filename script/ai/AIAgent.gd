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
	IN_ACTIVITY              # 在活动中（体育/自习）
}

# ============================================
# 核心引用
# ============================================
var character: CharacterBody2D = null          # 角色节点
var room_manager: RoomManager = null           # 房间管理器

# ============================================
# 感知层组件（保留）
# ============================================
var reward_receiver: AgentRewardReceiver = null    # 奖赏接收器

# ============================================
# 状态管理（新增）
# ============================================
var current_state: AgentState = AgentState.IDLE
var current_activity: String = ""              # 当前活动类型
var activity_start_time: float = 0.0           # 活动开始时间
var last_activity: String = ""                 # 上一周期活动（用于体验）

# ============================================
# 决策缓存（新增）
# ============================================
var cached_request: ActionRequest = null       # 缓存的行动请求
var is_waiting_execution: bool = false         # 是否等待执行

# ============================================
# 玩家控制（保留）
# ============================================
var is_player_controlled: bool = false

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
	
	# 连接时序系统信号
	_connect_to_timing_system()
	
	print("[AIAgent] %s 初始化完成" % character.name)

# ============================================
# 感知层组件创建（保留原逻辑）
# ============================================
func _create_reward_receiver() -> void:
	reward_receiver = AgentRewardReceiver.new()
	reward_receiver.ai_agent = self
	add_child(reward_receiver)
	print("[AIAgent] %s 奖赏接收器已创建" % character.name)

# ============================================
# 连接时序系统（新增）
# ============================================
func _connect_to_timing_system() -> void:
	# 延迟连接，确保TimingSystem已初始化
	await get_tree().create_timer(1.0).timeout
	
	if TimingSystem.instance:
		TimingSystem.instance.click_triggered.connect(_on_click_triggered)
		print("[AIAgent] %s 已连接到时序系统" % character.name)
	else:
		push_warning("[AIAgent] %s TimingSystem未找到" % character.name)

# ============================================
# Click触发回调（核心入口）
# ============================================
func _on_click_triggered(game_time: float, day: int, click_num: int):
	if is_player_controlled:
		return
	
	print("\n[AIAgent] %s 收到Click #%d" % [character.name, click_num])
	
	# 1. 如果有缓存的请求，执行它
	if is_waiting_execution and cached_request:
		_execute_cached_request()
		return
	
	# 2. 否则开始新的感知-体验-决策循环
	_perform_cognitive_cycle()

# ============================================
# 认知循环：感知 → 体验 → 决策
# ============================================
func _perform_cognitive_cycle():
	# 1. 感知阶段
	current_state = AgentState.PERCEIVING
	var perception = _perceive()
	print("[AIAgent] %s 感知完成" % character.name)
	
	# 2. 体验阶段（如果有上一周期活动）
	current_state = AgentState.EXPERIENCING
	if not last_activity.is_empty():
		_experience(last_activity)
		print("[AIAgent] %s 体验完成" % character.name)
	
	# 3. 决策阶段
	current_state = AgentState.DECIDING
	var request = _make_decision(perception)
	print("[AIAgent] %s 决策完成: %s" % [character.name, request.get_action_name()])
	
	# 4. 提交请求到时序系统
	_submit_request(request)

# ============================================
# 感知阶段（新增）
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
	
	# 2. 获取同场景其他Agent
	perception.nearby_agents = _get_agents_in_same_room()
	
	# 3. 获取时间轴约束
	if TimelineState.instance:
		perception.time_constraints = TimelineState.instance.get_constraints()
	
	# 4. 获取当前游戏时间
	if TimingSystem.instance:
		perception.current_time = TimingSystem.instance.current_game_time
	
	# TODO: 集成DialogueManager获取对话行为和内容
	
	return perception

# ============================================
# 体验阶段（新增）
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
# 决策阶段（新增）
# ============================================
func _make_decision(perception: Dictionary) -> ActionRequest:
	print("[AIAgent] %s 开始决策..." % character.name)
	
	# 1. 构建决策Prompt
	var prompt = PromptBuilder.build_decision_prompt(self, perception)
	if prompt.is_empty():
		push_error("[AIAgent] %s Prompt构建失败" % character.name)
		return ActionRequest.new(character.name, ActionRequest.ActionType.WAIT)
	
	# 2. 调用本地部署的大模型API
	var response = await _call_local_llm(prompt)
	
	# 3. 解析响应为ActionRequest
	var request = _parse_decision_response(response)
	
	print("[AIAgent] %s 决策完成: %s" % [character.name, request.get_action_name()])
	return request

# ============================================
# 调用本地部署的大模型API
# ============================================
func _call_local_llm(prompt: String) -> String:
	# 本地部署的大模型API配置
	# 默认使用Ollama本地服务，可通过修改配置支持其他本地模型
	var api_url = "http://localhost:11434/api/generate"
	var model_name = "qwen2.5:14b"  # 或其他本地模型
	
	var http_request = HTTPRequest.new()
	add_child(http_request)
	
	var body = {
		"model": model_name,
		"prompt": prompt,
		"stream": false,
		"options": {
			"temperature": 0.7,
			"num_predict": 500
		}
	}
	
	var json_body = JSON.stringify(body)
	var headers = ["Content-Type: application/json"]
	
	print("[AIAgent] %s 调用本地LLM..." % character.name)
	
	var error = http_request.request(api_url, headers, HTTPClient.METHOD_POST, json_body)
	if error != OK:
		push_error("[AIAgent] HTTP请求失败: %d" % error)
		http_request.queue_free()
		return "{}"
	
	# 等待响应
	var result = await http_request.request_completed
	http_request.queue_free()
	
	var response_code = result[1]
	var body_text = result[3].get_string_from_utf8()
	
	if response_code != 200:
		push_error("[AIAgent] API错误: %d, %s" % [response_code, body_text])
		return "{}"
	
	# 解析Ollama响应
	var json = JSON.new()
	var parse_result = json.parse(body_text)
	if parse_result != OK:
		push_error("[AIAgent] JSON解析失败: %s" % body_text)
		return "{}"
	
	var response_data = json.get_data()
	var response_text = response_data.get("response", "")
	
	print("[AIAgent] %s 收到LLM响应" % character.name)
	return response_text

# ============================================
# 解析决策响应为ActionRequest
# ============================================
func _parse_decision_response(response: String) -> ActionRequest:
	# 尝试从响应中提取JSON
	var json_text = _extract_json_from_text(response)
	
	var json = JSON.new()
	var parse_result = json.parse(json_text)
	
	if parse_result != OK:
		print("[AIAgent] 无法解析决策响应，使用默认WAIT: %s" % response)
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
# 提交请求到时序系统（新增）
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
# 执行缓存的请求（新增）
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
# 行动执行分发（新增）
# ============================================
func _execute_action(request: ActionRequest):
	match request.action_type:
		ActionRequest.ActionType.MOVE_TO_RANGE:
			_execute_move(request)
		ActionRequest.ActionType.START_DIALOGUE:
			_execute_start_dialogue(request)
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
# 具体行动执行（8种）
# ============================================

# 1. 路径移动
func _execute_move(request: ActionRequest):
	print("[AIAgent] %s 执行移动" % character.name)
	
	# 获取目标位置
	var target_pos = request.target_position
	if target_pos == Vector2.ZERO:
		# 如果没有指定位置，尝试从range_id获取
		target_pos = _get_position_from_range_id(request.target_range_id)
	
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

# 2. 开始对话
func _execute_start_dialogue(request: ActionRequest):
	print("[AIAgent] %s 开始对话" % character.name)
	current_state = AgentState.IN_DIALOGUE
	current_activity = "对话"
	activity_start_time = Time.get_unix_time_from_system()
	
	# 获取目标Agent
	var target_agent = _find_agent_by_id(request.target_id)
	if not target_agent:
		print("[AIAgent] %s 开始对话失败：目标不存在" % character.name)
		current_state = AgentState.IDLE
		return
	
	# 向DialogueManager注册新对话
	# TODO: DialogueManager.start_dialogue(self, target_agent)
	
	print("[AIAgent] %s 已向 %s 发起对话" % [character.name, request.target_id])

# 3. 加入对话
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
	
	# 向DialogueManager通知退出
	# TODO: DialogueManager.exit_dialogue(self)
	
	current_state = AgentState.IDLE
	current_activity = ""
	
	print("[AIAgent] %s 已退出对话，时长：%.1f秒" % [character.name, duration])

# 5. 开始体育活动
func _execute_start_sports(request: ActionRequest):
	print("[AIAgent] %s 开始体育活动" % character.name)
	
	# 验证当前在体育馆
	var current_room = _get_current_room()
	if not current_room or current_room.room_name != "体育馆":
		print("[AIAgent] %s 开始体育活动失败：不在体育馆" % character.name)
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
	
	print("[AIAgent] %s 已结束体育活动，时长：%.1f秒" % [character.name, duration])

# 7. 开始自习
func _execute_start_study(request: ActionRequest):
	print("[AIAgent] %s 开始自习" % character.name)
	
	# 验证当前在图书馆或自习室
	var current_room = _get_current_room()
	var valid_rooms = ["图书馆", "自习室"]
	if not current_room or not current_room.room_name in valid_rooms:
		print("[AIAgent] %s 开始自习失败：不在图书馆或自习室" % character.name)
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
	
	print("[AIAgent] %s 已结束自习，时长：%.1f秒" % [character.name, duration])

# 9. 等待
func _execute_wait(request: ActionRequest):
	print("[AIAgent] %s 等待" % character.name)
	current_state = AgentState.IDLE
	# 无需额外操作

# ============================================
# 移动相关变量和方法
# ============================================
var _is_moving: bool = false
var _target_position: Vector2 = Vector2.ZERO
var _movement_check_timer: float = 0.0
const MOVEMENT_CHECK_INTERVAL: float = 0.5  # 每0.5秒检查一次移动状态

func _physics_process(delta: float):
	# 处理移动检查
	if _is_moving and character:
		_movement_check_timer += delta
		
		# 定期检测是否到达目标
		if _movement_check_timer >= MOVEMENT_CHECK_INTERVAL:
			_movement_check_timer = 0.0
			
			# 检查是否到达目标（使用CharacterController的导航路径）
			var current_pos = character.global_position
			var distance_to_target = current_pos.distance_to(_target_position)
			
			# 如果距离小于阈值，认为到达目标
			if distance_to_target < 20.0:  # 20像素阈值
				_is_moving = false
				print("[AIAgent] %s 移动完成，距离目标：%.1f" % [character.name, distance_to_target])
				
				# 检查是否有缓存的step2
				if cached_request and cached_request.cached_step2:
					_validate_and_execute_step2()
				return

func _get_position_from_range_id(range_id: String) -> Vector2:
	"""
	从中范围ID获取目标位置
	range_id格式: "房间名_范围类型"，如 "教室（主教学区）_左上"
	"""
	if range_id.is_empty():
		return Vector2.ZERO
	
	# 解析range_id
	var parts = range_id.split("_")
	if parts.size() < 2:
		return Vector2.ZERO
	
	var room_name = parts[0]
	var range_type = parts[1] if parts.size() > 1 else "center"
	
	# 获取房间数据
	var room = _get_room_by_name(room_name)
	if not room:
		print("[AIAgent] 未找到房间: %s" % room_name)
		return Vector2.ZERO
	
	# 计算中范围位置
	var room_pos = room.position
	var room_size = room.size if room.has("size") else Vector2(200, 100)
	
	var offset = Vector2.ZERO
	
	# 根据范围类型计算偏移
	match range_type:
		"左上", "left_top":
			offset = Vector2(-room_size.x * 0.25, -room_size.y * 0.25)
		"右上", "right_top":
			offset = Vector2(room_size.x * 0.25, -room_size.y * 0.25)
		"左下", "left_bottom":
			offset = Vector2(-room_size.x * 0.25, room_size.y * 0.25)
		"右下", "right_bottom":
			offset = Vector2(room_size.x * 0.25, room_size.y * 0.25)
		"左", "left":
			offset = Vector2(-room_size.x * 0.25, 0)
		"右", "right":
			offset = Vector2(room_size.x * 0.25, 0)
		"中心", "center", "":
			offset = Vector2.ZERO
		_:
			# 默认中心
			offset = Vector2.ZERO
	
	# 添加随机偏移（避免所有Agent聚集在同一点）
	var random_offset = Vector2(randf_range(-20, 20), randf_range(-20, 20))
	
	return room_pos + offset + random_offset

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
	
	# 立即感知（无体验）
	var new_perception = _perceive()
	
	var step2 = cached_request.cached_step2
	
	# 验证Step2是否仍然有效
	if _is_step2_valid(step2, new_perception):
		print("[AIAgent] %s Step2有效，继续执行" % character.name)
		_execute_action(step2)
		last_activity = _get_activity_name(step2)
	else:
		print("[AIAgent] %s Step2无效，重新决策" % character.name)
		_make_decision(new_perception)
	
	# 清空缓存
	cached_request = null
	is_waiting_execution = false

func _is_step2_valid(step2: ActionRequest, perception: Dictionary) -> bool:
	# 检查目标是否仍然存在
	if step2.target_id:
		var target = _find_agent_by_id(step2.target_id)
		if not target:
			print("[AIAgent] Step2无效：目标已不存在")
			return false
	
	# 检查时间约束是否变化
	var constraints = TimelineState.instance.get_constraints()
	if step2.action_type == ActionRequest.ActionType.START_DIALOGUE:
		if not constraints.can_start_dialogue:
			print("[AIAgent] Step2无效：现在不能开始对话")
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
# 玩家控制（保留）
# ============================================
func toggle_player_control(enabled: bool):
	is_player_controlled = enabled
	if enabled:
		current_state = AgentState.IDLE
		print("[AIAgent] %s 切换到玩家控制" % character.name)
	else:
		print("[AIAgent] %s 切换到AI控制" % character.name)

# ============================================
# 场景描述生成（保留，后续添加）
# ============================================
# ============================================
# 场景描述生成（从原AIAgent保留）
# ============================================
func generate_scene_description() -> String:
	var description = ""
	
	# 获取当前房间信息
	var current_room = _get_current_room()
	if current_room:
		description += "你现在在" + current_room.room_name + "。"
		description += "\n" + current_room.room_desc
		
		# 添加情境参数(使用感知系统)
		description += _get_room_situation_params(current_room.room_name)
	
	# 获取环境信息
	var env_info = get_environment_info()
	description += "\n" + env_info
	
	# 获取房间内的物品和角色
	if current_room:
		var room_objects = get_room_objects(current_room)
		var room_characters = get_room_characters(current_room)
		
		# 添加物品描述
		if room_objects.size() > 0:
			description += "\n房间内有以下物品:"
			for obj in room_objects:
				var item_info = get_object_info(obj)
				description += "\n- " + item_info
		
		# 添加角色描述
		if room_characters.size() > 0:
			description += "\n房间内有以下角色:"
			for char in room_characters:
				var char_personality = CharacterPersonality.get_personality(char.name)
				var position = char_personality.get("position", "未知职位")
				description += "\n- " + char.name + "(" + position + ")"
	
	return description

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
# MVT决策（保留，后续添加）
# ============================================
func _check_mvt_leave_decision(room_name: String, time_in_room: float, 
							   personality: Dictionary, is_depression: bool):
	# TODO: 从原AIAgent保留此函数
	pass
