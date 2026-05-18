extends Node
class_name TimingSystem

# 单例模式
static var instance: TimingSystem

# 时间配置
const CLICK_INTERVAL_MINUTES: float = 5.0  # 游戏时间5分钟一个Click
const REAL_SECONDS_PER_CLICK: float = 30.0  # 30现实秒 = 1个Click（游戏5分钟）
const AUTO_START_NEXT_DAY: bool = true  # 日终后自动进入下一天
const NEXT_DAY_DELAY_SECONDS: float = 2.0  # 日终收尾日志/存档后再开新一天
# 时间比例：现实1分钟 = 游戏10分钟，即1现实秒 = 10游戏秒

# 状态
var is_running: bool = false
var current_game_time: float = 8.0 * 60.0  # 从8:00开始（分钟）
var current_day: int = 1
var click_count: int = 0
var _start_time_ms: int = 0  # 记录开始时间的毫秒数
var _last_click_time_ms: int = 0  # 上次Click的时间
var _after_school_phase_entered: bool = false
var _is_scheduling_next_day: bool = false

# 信号
signal click_triggered(game_time: float, day: int, click_num: int)
signal day_started(day: int, start_time: float)
signal day_ended(day: int, end_time: float)
signal before_click(game_time: float)
signal after_click(game_time: float)

# 请求队列
var pending_requests: Dictionary = {}  # agent_id -> ActionRequest

func _init():
	instance = self

func _ready():
	print("[TimingSystem] 时序系统初始化完成")

# 启动时序系统
func start_day(day: int = 1):
	current_day = day
	current_game_time = 8.0 * 60.0  # 8:00
	click_count = 0
	is_running = true
	_after_school_phase_entered = false
	_is_scheduling_next_day = false
	_start_time_ms = Time.get_ticks_msec()
	_last_click_time_ms = _start_time_ms
	
	day_started.emit(current_day, current_game_time)
	print("[TimingSystem] 第%d天开始，时间：%s" % [current_day, format_time(current_game_time)])
	
	# 第一次Click（8:00统一感知+决策）
	_trigger_click()

# 停止时序系统
func end_day():
	is_running = false
	_end_active_dialogues_for_day()
	day_ended.emit(current_day, current_game_time)
	print("[TimingSystem] 第%d天结束，时间：%s" % [current_day, format_time(current_game_time)])
	if AUTO_START_NEXT_DAY:
		_schedule_next_day()

# 主循环
func _process(delta: float):
	if not is_running:
		return
	
	# 更新游戏时间
	# 现实30秒 = 游戏5分钟，所以游戏时间流逝速度是现实的10倍
	# delta(现实秒) * (5/30) = 游戏分钟
	var game_delta = delta * (CLICK_INTERVAL_MINUTES / REAL_SECONDS_PER_CLICK)
	current_game_time += game_delta
	
	# 检查是否到达Click时刻（现实30秒触发一次）
	var current_time_ms = Time.get_ticks_msec()
	var elapsed_real_seconds = (current_time_ms - _last_click_time_ms) / 1000.0
	if elapsed_real_seconds >= REAL_SECONDS_PER_CLICK:
		_last_click_time_ms = current_time_ms
		_trigger_click()
	
	# 检查是否到达17:00（放学时间）
	if not _after_school_phase_entered and current_game_time >= 17.0 * 60.0 and current_game_time < 17.5 * 60.0:
		_enter_after_school_phase()
	
	# 检查是否到达17:30（强制结束）
	if current_game_time >= 17.5 * 60.0:
		_force_end_day()

# V2: 协调决策收集完成信号
signal all_decisions_submitted(click_num: int)

# 触发Click（上升沿）
func _trigger_click():
	click_count += 1
	
	print("\n[TimingSystem] ===== CLICK #%d =====" % click_count)
	print("[TimingSystem] 游戏时间：%s" % format_time(current_game_time))
	
	before_click.emit(current_game_time)
	
	# 1. 批准并执行所有待处理请求
	_execute_pending_requests()
	
	# 可选硬编码Demo模式：仅在 HardcodedDemoController.DEMO_MODE 开启时替代完整协调流程。
	if HardcodedDemoController.instance and HardcodedDemoController.instance.is_running():
		print("[TimingSystem] 使用硬编码Demo控制器")
		
		# 触发Agent准备（让Agent进入等待状态）
		click_triggered.emit(current_game_time, current_day, click_count)
		
		# 等待一小段时间让Agent准备好
		await get_tree().create_timer(0.5).timeout
		
		# 执行硬编码的Click逻辑
		var demo_assignments = HardcodedDemoController.instance.execute_hardcoded_click(click_count, current_game_time)
		
		# 将分配的活动下发给Agent
		if not demo_assignments.is_empty():
			print("[TimingSystem] Demo分配 %d 个角色活动" % demo_assignments.size())
			for agent_id in demo_assignments.keys():
				var activities = demo_assignments[agent_id]
				print("[TimingSystem] 尝试查找Agent: %s" % agent_id)
				var agent = _get_agent(agent_id)
				if agent:
					print("[TimingSystem] 找到Agent %s，准备分配 %d 个活动" % [agent_id, activities.size()])
					if agent.has_method("receive_activity_sequence"):
						agent.receive_activity_sequence(activities)
						print("[TimingSystem] 已分配 %d 个活动给 %s" % [activities.size(), agent_id])
					else:
						print("[TimingSystem] 警告: Agent %s 没有receive_activity_sequence方法" % agent_id)
				else:
					print("[TimingSystem] 警告: 未找到Agent %s" % agent_id)
			
			# 等待一下让Agent接收活动
			await get_tree().create_timer(0.5).timeout
			
			# 触发Agent执行活动
			print("[TimingSystem] 触发Agent执行活动...")
			for agent_id in demo_assignments.keys():
				var agent = _get_agent(agent_id)
				if agent and agent.has_method("execute_demo_activity"):
					print("[TimingSystem] 触发 %s 执行活动" % agent_id)
					agent.execute_demo_activity()
				else:
					print("[TimingSystem] 警告: 无法触发 %s 执行活动" % agent_id)
	else:
		# V2: 2. 触发所有Agent的感知+决策（提交到协调器）
		# V2: 等待所有Agent提交决策，然后执行协调
		print("[TimingSystem] ActivityCoordinator.instance = %s" % ActivityCoordinator.instance)
		if ActivityCoordinator.instance:
			print("[TimingSystem] 开始触发Agent决策收集...")
			# 先触发Agent决策收集
			click_triggered.emit(current_game_time, current_day, click_count)
			print("[TimingSystem] click_triggered信号已发射")
			
			# V2: 等待Agent提交决策
			print("[TimingSystem] 等待Agent提交决策...")
			var max_wait = 15.0
			var waited = 0.0
			while waited < max_wait:
				await get_tree().create_timer(1.0).timeout
				waited += 1.0
				var pending_count = ActivityCoordinator.instance.get_pending_count()
				print("[TimingSystem] 已等待%.0f秒，%d个Agent已提交决策" % [waited, pending_count])
				if waited >= 1.0 and pending_count == 0 and not _any_agent_waiting_for_decision():
					print("[TimingSystem] 本Click没有Agent提交新决策，跳过协调等待")
					break
				# 如果所有Agent都提交了，提前结束等待
				# 动态获取场景中的Agent数量
				var expected_agents = get_tree().get_nodes_in_group("character").size()
				if pending_count >= expected_agents:
					print("[TimingSystem] 所有Agent已提交（%d/%d），提前结束等待" % [pending_count, expected_agents])
					break
			
			# V2: 执行协调
			var game_context = {
				"current_time": format_time(current_game_time),
				"current_location": "学校",
				"period": _get_current_period()
			}
			print("[TimingSystem] 开始执行协调...")
			var coordination_results = await ActivityCoordinator.instance.execute_coordination(game_context)
			
			if not coordination_results.is_empty():
				print("[TimingSystem] 协调完成，%d 个Agent收到活动分配" % coordination_results.size())
		else:
			# V1: 直接触发Agent决策
			click_triggered.emit(current_game_time, current_day, click_count)
	
	# 触发对话系统更新（选择发言者、生成内容）
	var dialogue_manager = get_node_or_null("/root/DialogueManager")
	if dialogue_manager and dialogue_manager.has_method("on_click_tick"):
		dialogue_manager.on_click_tick(click_count, current_game_time)
	
	after_click.emit(current_game_time)
	
	print("[TimingSystem] ===== CLICK END =====\n")

# V2: 获取当前时段
func _get_current_period() -> String:
	if TimelineState.instance:
		return TimelineState.instance.current_period
	return "未知"

# 执行待处理请求
func _execute_pending_requests():
	if pending_requests.is_empty():
		print("[TimingSystem] 无待处理请求")
		return
	
	print("[TimingSystem] 执行 %d 个待处理请求" % pending_requests.size())
	
	for agent_id in pending_requests.keys():
		var request = pending_requests[agent_id]
		print("[TimingSystem] 执行请求：%s -> %s" % [agent_id, request.get_action_name()])
		
		# 调用Agent执行行动
		var agent = _get_agent(agent_id)
		if agent:
			agent.execute_action(request)
	
	# 清空请求队列
	pending_requests.clear()

# Agent提交行动请求
func submit_action_request(agent_id: String, request: ActionRequest) -> bool:
	if not is_running:
		print("[TimingSystem] 错误：时序系统未运行")
		return false
	
	# 17:00后不接受新的开始请求
	if current_game_time >= 17.0 * 60.0 and not request.is_end_action:
		print("[TimingSystem] %s 的请求被拒绝：已进入放学阶段" % agent_id)
		return false
	
	pending_requests[agent_id] = request
	print("[TimingSystem] %s 提交请求：%s" % [agent_id, request.get_action_name()])
	return true

# 进入放学阶段（17:00-17:30）
func _enter_after_school_phase():
	_after_school_phase_entered = true
	print("[TimingSystem] 进入放学阶段（17:00-17:30）")
	print("[TimingSystem] 只接受结束请求，不接受开始请求")

# 强制结束一天（17:30）
func _force_end_day():
	print("[TimingSystem] 强制结束当前活动")
	
	# 强制结束所有Agent的当前活动
	for agent in _get_all_agents():
		if agent.has_method("force_end_current_activity"):
			agent.force_end_current_activity()
	
	end_day()

# 自动进入下一天
func _schedule_next_day() -> void:
	if _is_scheduling_next_day:
		return

	_is_scheduling_next_day = true
	var next_day = current_day + 1
	print("[TimingSystem] 将在 %.1f 秒后自动进入第%d天" % [NEXT_DAY_DELAY_SECONDS, next_day])
	await get_tree().create_timer(NEXT_DAY_DELAY_SECONDS).timeout

	if not is_running:
		start_day(next_day)

func _end_active_dialogues_for_day() -> void:
	var dialogue_manager = get_node_or_null("/root/DialogueManager")
	if dialogue_manager and dialogue_manager.has_method("end_all_dialogues"):
		dialogue_manager.end_all_dialogues(dialogue_manager.EndReason.DAY_END)

# 格式化时间显示
func format_time(minutes: float) -> String:
	var h = int(minutes / 60)
	var m = int(fmod(minutes, 60))
	return "%02d:%02d" % [h, m]

func get_current_click() -> int:
	return click_count

# 获取当前时段类型
func get_current_period() -> String:
	var hour = current_game_time / 60.0
	
	if hour < 8.0:
		return "before_school"
	elif hour < 12.0:
		return "morning_class"
	elif hour < 14.0:
		return "lunch_break"
	elif hour < 17.0:
		return "afternoon_class"
	elif hour < 17.5:
		return "after_school"
	else:
		return "day_ended"

# 获取Agent（临时实现，后续需要AgentManager）
func _get_agent(agent_id: String):
	# TODO: 集成AgentManager
	var agents = get_tree().get_nodes_in_group("ai_agents")
	for agent in agents:
		# AIAgent的name可能不是角色名，需要检查character.name
		if agent.name == agent_id:
			return agent
		# 检查agent是否有character引用
		if agent.has_method("get_character"):
			var char_node = agent.get_character()
			if char_node and char_node.name == agent_id:
				return agent
		# 直接检查agent.get_parent().name（AIAgent的父节点是CharacterBody2D）
		if agent.get_parent() and agent.get_parent().name == agent_id:
			return agent
	return null

# 获取所有Agent（临时实现）
func _get_all_agents() -> Array:
	# TODO: 集成AgentManager
	return get_tree().get_nodes_in_group("ai_agents")

func _any_agent_waiting_for_decision() -> bool:
	for agent in _get_all_agents():
		if agent.has_method("is_waiting_for_decision_result") and agent.is_waiting_for_decision_result():
			return true
	return false
