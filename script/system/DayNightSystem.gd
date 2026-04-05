extends Node

# DayNightSystem - 游戏时间管理系统
# 注意：作为AutoLoad使用，不需要class_name

# 游戏时间配置
const REAL_SECONDS_PER_GAME_HOUR: float = 60.0  # 1现实分钟 = 1游戏小时
const HOURS_PER_DAY: int = 24
const SCHOOL_START_HOUR: float = 7.0   # 7:00 上学
const SCHOOL_END_HOUR: float = 17.0    # 17:00 放学

# 信号
signal day_started(day_number: int, weekday: String)
signal hour_changed(hour: int)
signal day_ended(day_number: int)
signal school_time_started()
signal school_time_ended()

# 当前时间状态
var current_day: int = 1
var current_hour: float = 7.0  # 从早上7点开始（上学时间）
var current_weekday: int = 1   # 1=周一, 7=周日
var _accumulated_time: float = 0.0
var _is_school_time: bool = false

# 单例
static var instance: DayNightSystem

func _init():
	instance = self

func _ready():
	print("[DayNightSystem] 初始化完成，当前时间：第", current_day, "天 ", _format_time())
	_check_school_time()
	day_started.emit(current_day, get_weekday_name())

func _process(delta: float):
	_accumulated_time += delta
	
	# 每60现实秒推进1游戏小时
	if _accumulated_time >= REAL_SECONDS_PER_GAME_HOUR:
		_accumulated_time -= REAL_SECONDS_PER_GAME_HOUR
		_advance_hour()

func _advance_hour():
	var previous_hour = int(current_hour)
	current_hour += 1.0
	
	# 检查是否跨天
	if current_hour >= HOURS_PER_DAY:
		current_hour = 0.0
		_end_day()
	
	# 发出小时变化信号（仅当整数小时变化时）
	if int(current_hour) != previous_hour:
		hour_changed.emit(int(current_hour))
		print("[DayNightSystem] 时间：", _format_time())
	
	# 检查学校时间
	_check_school_time()

func _end_day():
	print("[DayNightSystem] ===== 第", current_day, "天结束 =====")
	day_ended.emit(current_day)
	
	# 触发所有学生的每日反思
	_trigger_daily_reflection()
	
	# 进入下一天
	current_day += 1
	current_weekday = ((current_weekday - 1 + 1) % 7) + 1  # 循环1-7
	
	print("[DayNightSystem] ===== 第", current_day, "天开始 =====")
	day_started.emit(current_day, get_weekday_name())

func _trigger_daily_reflection():
	print("[DayNightSystem] 触发所有学生每日反思...")
	
	# 获取所有学生角色
	var characters = get_tree().get_nodes_in_group("character")
	var reflection_count = 0
	
	for character in characters:
		if character.has_meta("character_data"):
			var data = character.get_meta("character_data")
			var role_type = data.get("role_type", "")
			
			# 只对学生进行每日反思
			if role_type == "depression_risk_student" or role_type == "healthy_student":
				print("[DayNightSystem] 触发 ", character.name, " 的每日反思")
				DailyReflectionSystem.conduct_daily_reflection(character)
				reflection_count += 1
	
	print("[DayNightSystem] 共触发 ", reflection_count, " 名学生的每日反思")

func _check_school_time():
	var was_school_time = _is_school_time
	_is_school_time = is_school_time()
	
	if _is_school_time and not was_school_time:
		print("[DayNightSystem] 学校时间开始")
		school_time_started.emit()
	elif not _is_school_time and was_school_time:
		print("[DayNightSystem] 学校时间结束")
		school_time_ended.emit()

func _format_time() -> String:
	var hour = int(current_hour)
	var minute = int((current_hour - hour) * 60)
	return "%02d:%02d" % [hour, minute]

# ========== 公共接口 ==========

func get_current_time() -> String:
	return _format_time()

func get_weekday_name() -> String:
	var weekdays = ["", "周一", "周二", "周三", "周四", "周五", "周六", "周日"]
	return weekdays[current_weekday]

func is_school_time() -> bool:
	# 周末不上学
	if current_weekday >= 6:  # 周六周日
		return false
	return current_hour >= SCHOOL_START_HOUR and current_hour < SCHOOL_END_HOUR

func is_weekend() -> bool:
	return current_weekday >= 6

func get_day_progress() -> float:
	return current_hour / HOURS_PER_DAY

func accelerate_time(multiplier: float):
	Engine.time_scale = multiplier
	print("[DayNightSystem] 时间加速：", multiplier, "x")

func reset_time_scale():
	Engine.time_scale = 1.0
	print("[DayNightSystem] 时间恢复正常")

func skip_to_next_day():
	current_hour = HOURS_PER_DAY
	_advance_hour()

# 获取时间描述（用于AI Prompt）
func get_time_context() -> String:
	var context = "当前时间：第" + str(current_day) + "天 " + get_weekday_name() + " " + _format_time()
	
	if is_school_time():
		context += "（学校时间）"
	elif is_weekend():
		context += "（周末休息）"
	else:
		context += "（放学后）"
	
	return context
