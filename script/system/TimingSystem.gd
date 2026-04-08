extends Node
class_name TimingSystem

# 单例模式
static var instance: TimingSystem

# 时间配置
const CLICK_INTERVAL_MINUTES: float = 5.0  # 游戏时间5分钟一个Click
const REAL_SECONDS_PER_GAME_MINUTE: float = 60.0  # 60现实秒 = 1游戏分钟（1:1时间流逝）

# 状态
var is_running: bool = false
var current_game_time: float = 8.0 * 60.0  # 从8:00开始（分钟）
var current_day: int = 1
var click_count: int = 0

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
	
	day_started.emit(current_day, current_game_time)
	print("[TimingSystem] 第%d天开始，时间：%s" % [current_day, format_time(current_game_time)])
	
	# 第一次Click（8:00统一感知+决策）
	_trigger_click()

# 停止时序系统
func end_day():
	is_running = false
	day_ended.emit(current_day, current_game_time)
	print("[TimingSystem] 第%d天结束，时间：%s" % [current_day, format_time(current_game_time)])

# 主循环
func _process(delta: float):
	if not is_running:
		return
	
	# 更新游戏时间（1:1流逝，delta是现实秒，直接加到游戏时间）
	# 游戏时间以分钟为单位，所以 delta(秒) / 60 = 游戏分钟
	var game_delta = delta / 60.0
	current_game_time += game_delta
	
	# 检查是否到达Click时刻
	var minutes_since_last_click = fmod(current_game_time, CLICK_INTERVAL_MINUTES)
	if minutes_since_last_click < game_delta:  # 刚越过5分钟边界
		_trigger_click()
	
	# 检查是否到达17:00（放学时间）
	if current_game_time >= 17.0 * 60.0 and current_game_time < 17.5 * 60.0:
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
	
	# V2: 2. 触发所有Agent的感知+决策（提交到协调器）
	# V2: 等待所有Agent提交决策，然后执行协调
	print("[TimingSystem] ActivityCoordinator.instance = %s" % ActivityCoordinator.instance)
	if ActivityCoordinator.instance:
		print("[TimingSystem] 开始触发Agent决策收集...")
		# 先触发Agent决策收集
		click_triggered.emit(current_game_time, current_day, click_count)
		print("[TimingSystem] click_triggered信号已发射")
		
		# V2: 等待Agent提交决策
		# 最大等待时间：6秒(延迟) + 30秒(LLM超时) + 缓冲 = 40秒
		print("[TimingSystem] 等待Agent提交决策...")
		var max_wait = 40.0  # 最大等待40秒
		var waited = 0.0
		while waited < max_wait:
			await get_tree().create_timer(1.0).timeout
			waited += 1.0
			var pending_count = ActivityCoordinator.instance.get_pending_count()
			print("[TimingSystem] 已等待%.0f秒，%d个Agent已提交决策" % [waited, pending_count])
			# 如果所有Agent都提交了，提前结束等待
			if pending_count >= 12:  # 假设有12个Agent
				print("[TimingSystem] 所有Agent已提交，提前结束等待")
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

# 格式化时间显示
func format_time(minutes: float) -> String:
	var h = int(minutes / 60)
	var m = int(fmod(minutes, 60))
	return "%02d:%02d" % [h, m]

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
		if agent.name == agent_id:
			return agent
	return null

# 获取所有Agent（临时实现）
func _get_all_agents() -> Array:
	# TODO: 集成AgentManager
	return get_tree().get_nodes_in_group("ai_agents")
