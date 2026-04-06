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
	# TODO: 构建决策Prompt，调用API
	# 暂时返回WAIT请求
	var request = ActionRequest.new(character.name, ActionRequest.ActionType.WAIT)
	return request

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
# 具体行动执行（待实现）
# ============================================
func _execute_move(request: ActionRequest):
	print("[AIAgent] %s 执行移动" % character.name)
	# TODO: 实现移动逻辑

func _execute_start_dialogue(request: ActionRequest):
	print("[AIAgent] %s 开始对话" % character.name)
	current_state = AgentState.IN_DIALOGUE
	# TODO: 实现开始对话

func _execute_join_dialogue(request: ActionRequest):
	print("[AIAgent] %s 加入对话" % character.name)
	current_state = AgentState.IN_DIALOGUE
	# TODO: 实现加入对话

func _execute_exit_dialogue(request: ActionRequest):
	print("[AIAgent] %s 退出对话" % character.name)
	current_state = AgentState.IDLE
	# TODO: 实现退出对话

func _execute_start_sports(request: ActionRequest):
	print("[AIAgent] %s 开始体育活动" % character.name)
	current_state = AgentState.IN_ACTIVITY
	# TODO: 实现开始体育活动

func _execute_end_sports(request: ActionRequest):
	print("[AIAgent] %s 结束体育活动" % character.name)
	current_state = AgentState.IDLE
	# TODO: 实现结束体育活动

func _execute_start_study(request: ActionRequest):
	print("[AIAgent] %s 开始自习" % character.name)
	current_state = AgentState.IN_ACTIVITY
	# TODO: 实现开始自习

func _execute_end_study(request: ActionRequest):
	print("[AIAgent] %s 结束自习" % character.name)
	current_state = AgentState.IDLE
	# TODO: 实现结束自习

func _execute_wait(request: ActionRequest):
	print("[AIAgent] %s 等待" % character.name)
	current_state = AgentState.IDLE

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
func generate_scene_description() -> String:
	# TODO: 从原AIAgent保留此函数
	return ""

func get_environment_info() -> String:
	# TODO: 从原AIAgent保留此函数
	return ""

func move_to_target(target_info: Dictionary, char_node = null):
	# TODO: 从原AIAgent保留此函数
	pass

func _add_memory(target_character, content: String):
	# TODO: 从原AIAgent保留此函数
	pass

func _get_room_situation_params(room_name: String) -> String:
	# TODO: 从原AIAgent保留此函数，改为使用PerceptionSystem
	return ""

func _get_direction_description(from_pos: Vector2, to_pos: Vector2) -> String:
	# TODO: 从原AIAgent保留此函数
	return ""

func _find_target_by_name(target_name: String):
	# TODO: 从原AIAgent保留此函数
	return null

func _choose_random_target() -> Dictionary:
	# TODO: 从原AIAgent保留此函数
	return {}

func get_character_status_info(char_node = null) -> String:
	# TODO: 从原AIAgent保留此函数
	return ""

func get_room_objects(room: RoomData) -> Array:
	# TODO: 从原AIAgent保留此函数
	return []

func get_room_characters(room: RoomData) -> Array:
	# TODO: 从原AIAgent保留此函数
	return []

func get_object_info(obj: Node2D) -> String:
	# TODO: 从原AIAgent保留此函数
	return ""

func _execute_class_movement(target_character, current_task):
	# TODO: 从原AIAgent保留此函数
	pass

func _get_room_entrance_position(room_data) -> Vector2:
	# TODO: 从原AIAgent保留此函数
	return Vector2.ZERO

func _start_arrival_tracking(target_character, target_room: String, current_task):
	# TODO: 从原AIAgent保留此函数
	pass

# ============================================
# MVT决策（保留，后续添加）
# ============================================
func _check_mvt_leave_decision(room_name: String, time_in_room: float, 
							   personality: Dictionary, is_depression: bool):
	# TODO: 从原AIAgent保留此函数
	pass
