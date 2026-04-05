extends Node

# ScheduleSystem - 课程表与任务管理系统
# 为所有Agent根据课程表个性化设置任务

const CLASS_DURATION: float = 45.0  # 每节课45分钟（游戏内分钟）
const BREAK_DURATION: float = 10.0  # 课间休息10分钟
const LUNCH_DURATION: float = 60.0  # 午休60分钟

# 课程表结构
# 时间格式：小时.分钟 (如 8.0 = 8:00)
var daily_schedule = {
	"morning": [
		{"time": 8.0, "subject": "班主任课", "teacher": "TeacherWang", "room": "教室（主教学区）", "activity": "课堂发言", "type": "class"},
		{"time": 8.75, "subject": "课间休息", "type": "break"},
		{"time": 8.916, "subject": "英语课", "teacher": "TeacherChen", "room": "教室（主教学区）", "activity": "课堂发言", "type": "class"},
		{"time": 9.666, "subject": "课间休息", "type": "break"},
		{"time": 9.833, "subject": "小组讨论", "teacher": null, "room": "教室（小组讨论区）", "activity": "小组合作", "type": "group_discussion"}
	],
	"lunch": {"start": 10.75, "subject": "午休", "room": "食堂", "activity": "同伴互动", "type": "free"},
	"afternoon": [
		{"time": 11.75, "subject": "数学课", "teacher": "TeacherLi", "room": "教室（主教学区）", "activity": "课堂发言", "type": "class"},
		{"time": 12.5, "subject": "课间休息", "type": "break"},
		{"time": 12.666, "subject": "体育活动", "teacher": null, "room": "体育馆", "activity": "体育活动", "type": "pe"}
	]
}

# 当前课程状态
var current_period: Dictionary = {}
var is_school_day: bool = false

func _ready():
	# 监听DayNightSystem信号
	if DayNightSystem:
		DayNightSystem.day_started.connect(_on_day_started)
		DayNightSystem.hour_changed.connect(_on_hour_changed)
		DayNightSystem.school_time_started.connect(_on_school_time_started)
		DayNightSystem.school_time_ended.connect(_on_school_time_ended)
	
	print("[ScheduleSystem] 课程表系统初始化完成")

func _on_day_started(day_number: int, weekday: String):
	print("[ScheduleSystem] 第", day_number, "天开始，", weekday)
	
	# 检查是否是上学日
	if DayNightSystem and not DayNightSystem.is_weekend():
		is_school_day = true
		print("[ScheduleSystem] 今天是上学日，课程表已激活")
		_assign_daily_tasks()
	else:
		is_school_day = false
		print("[ScheduleSystem] 今天是周末，无课程安排")
		_assign_weekend_tasks()

func _on_hour_changed(hour: int):
	if not is_school_day:
		return
	
	_check_current_period()

func _on_school_time_started():
	print("[ScheduleSystem] 学校时间开始")
	if is_school_day:
		_broadcast_message("同学们，开始上课了！")

func _on_school_time_ended():
	print("[ScheduleSystem] 学校时间结束")
	_broadcast_message("放学了，同学们再见！")
	_clear_all_class_tasks()

# ========== 任务分配核心逻辑 ==========

func _assign_daily_tasks():
	"""为所有Agent分配一天的课程任务"""
	var characters = get_tree().get_nodes_in_group("character")
	
	for character in characters:
		if not character.has_meta("character_data"):
			continue
		
		var data = character.get_meta("character_data")
		var role_type = data.get("role_type", "")
		var ai_agent = _get_ai_agent(character)
		
		if not ai_agent:
			continue
		
		# 根据角色类型分配任务
		match role_type:
			"depression_risk_student":
				_assign_student_schedule(character, ai_agent, true)
			"healthy_student":
				_assign_student_schedule(character, ai_agent, false)
			"teacher":
				_assign_teacher_schedule(character, ai_agent)

func _assign_student_schedule(character: Node, ai_agent: Node, is_depression_risk: bool):
	"""为学生分配个性化课程表"""
	var personality = CharacterPersonality.get_personality(character.name)
	var beta_effort = personality.get("cognitive_mechanism", {}).get("beta_effort", 0.5)
	
	print("[ScheduleSystem] 为学生 ", character.name, " 分配课程表（抑郁风险：", is_depression_risk, "）")
	
	# 上午课程
	for period in daily_schedule["morning"]:
		if period["type"] == "break":
			_assign_break_task(character, ai_agent, is_depression_risk)
		else:
			_assign_class_task(character, ai_agent, period, is_depression_risk, beta_effort)
	
	# 午休
	_assign_lunch_task(character, ai_agent, is_depression_risk)
	
	# 下午课程
	for period in daily_schedule["afternoon"]:
		if period["type"] == "break":
			_assign_break_task(character, ai_agent, is_depression_risk)
		else:
			_assign_class_task(character, ai_agent, period, is_depression_risk, beta_effort)

func _assign_class_task(character: Node, ai_agent: Node, period: Dictionary, is_depression_risk: bool, beta_effort: float):
	"""分配课堂任务，根据抑郁风险程度个性化"""
	
	var task_priority = 3  # 默认中等优先级
	var task_description = ""
	var expected_effort = period.get("activity", "课堂发言")
	
	# 根据课程类型和抑郁风险个性化任务
	if is_depression_risk:
		# 抑郁风险学生对高努力情境回避
		if period["room"] == "教室（主教学区）" and expected_effort == "课堂发言":
			task_priority = 2  # 较低优先级（可能回避）
			task_description = "尝试参与课堂，但可能会感到疲惫和焦虑"
		elif period["room"] == "体育馆":
			task_priority = 1  # 低优先级（高度回避）
			task_description = "体育活动时间，可能会选择旁观或请假"
		elif period["type"] == "group_discussion":
			task_priority = 2  # 中等偏低
			task_description = "参与小组讨论，但可能较少发言"
		else:
			task_description = "参与课堂活动"
	else:
		# 健康学生正常参与
		task_priority = 4  # 高优先级
		if period["type"] == "group_discussion":
			task_description = "积极参与小组讨论，主动发言"
		elif period["room"] == "体育馆":
			task_description = "积极参与体育活动"
		else:
			task_description = "认真听讲，积极参与课堂发言"
	
	# 创建任务
	var task = {
		"id": "class_" + period["subject"] + "_" + str(period["time"]),
		"name": period["subject"],
		"description": task_description,
		"target_room": period["room"],
		"activity_type": expected_effort,
		"start_time": period["time"],
		"duration": CLASS_DURATION,
		"priority": task_priority,
		"teacher": period.get("teacher", null),
		"personalized": true
	}
	
	ai_agent.add_task(task)
	print("[ScheduleSystem] ", character.name, " 添加任务：", period["subject"], "（优先级：", task_priority, "）")

func _assign_break_task(character: Node, ai_agent: Node, is_depression_risk: bool):
	"""分配课间任务，根据性格选择活动"""
	
	var personality = CharacterPersonality.get_personality(character.name)
	var extraversion = personality.get("big_five", {}).get("extraversion", 50)
	
	var task = {
		"id": "break_" + str(Time.get_unix_time_from_system()),
		"name": "课间休息",
		"duration": BREAK_DURATION,
		"priority": 2
	}
	
	# 根据性格选择课间活动
	if is_depression_risk:
		task["description"] = "课间休息时间，可能会独自待在座位上或去安静的角落"
		task["target_room"] = "走廊"  # 可能去走廊但不太社交
		task["activity_type"] = "独处或偶遇互动"
	elif extraversion > 70:
		task["description"] = "课间与同学聊天、玩耍"
		task["target_room"] = "走廊"
		task["activity_type"] = "偶遇互动"
	else:
		task["description"] = "课间休息，可能去洗手间或短暂散步"
		task["target_room"] = "走廊"
		task["activity_type"] = "偶遇互动"
	
	ai_agent.add_task(task)

func _assign_lunch_task(character: Node, ai_agent: Node, is_depression_risk: bool):
	"""分配午休任务"""
	
	var personality = CharacterPersonality.get_personality(character.name)
	var extraversion = personality.get("big_five", {}).get("extraversion", 50)
	
	var task = {
		"id": "lunch_" + str(Time.get_unix_time_from_system()),
		"name": "午休",
		"target_room": "食堂",
		"activity_type": "同伴互动",
		"start_time": 10.75,
		"duration": LUNCH_DURATION,
		"priority": 3
	}
	
	if is_depression_risk:
		task["description"] = "午餐时间，可能会独自用餐或找一个安静的角落"
		task["priority"] = 2  # 较低优先级
	elif extraversion > 75:
		task["description"] = "午餐时间与同学一起用餐，积极社交"
		task["priority"] = 4  # 高优先级
	else:
		task["description"] = "午餐时间，与几个朋友一起用餐"
		task["priority"] = 3
	
	ai_agent.add_task(task)

func _assign_teacher_schedule(character: Node, ai_agent: Node):
	"""为教师分配教学任务"""
	var teacher_name = character.name
	
	# 根据教师姓名分配对应课程
	for period in daily_schedule["morning"]:
		if period.get("teacher") == teacher_name:
			var task = {
				"id": "teach_" + period["subject"],
				"name": "教授" + period["subject"],
				"description": "在" + period["room"] + "教授" + period["subject"],
				"target_room": period["room"],
				"activity_type": "教学",
				"start_time": period["time"],
				"duration": CLASS_DURATION,
				"priority": 5  # 最高优先级
			}
			ai_agent.add_task(task)
			print("[ScheduleSystem] 教师 ", teacher_name, " 添加教学任务：", period["subject"])
	
	for period in daily_schedule["afternoon"]:
		if period.get("teacher") == teacher_name:
			var task = {
				"id": "teach_" + period["subject"],
				"name": "教授" + period["subject"],
				"description": "在" + period["room"] + "教授" + period["subject"],
				"target_room": period["room"],
				"activity_type": "教学",
				"start_time": period["time"],
				"duration": CLASS_DURATION,
				"priority": 5
			}
			ai_agent.add_task(task)
			print("[ScheduleSystem] 教师 ", teacher_name, " 添加教学任务：", period["subject"])

func _assign_weekend_tasks():
	"""周末任务：自由活动"""
	var characters = get_tree().get_nodes_in_group("character")
	
	for character in characters:
		var ai_agent = _get_ai_agent(character)
		if not ai_agent:
			continue
		
		var task = {
			"id": "weekend_free",
			"name": "周末自由活动",
			"description": "周末时间，可以自由安排活动",
			"priority": 1
		}
		ai_agent.add_task(task)

# ========== 辅助函数 ==========

func _get_ai_agent(character: Node) -> Node:
	"""获取角色的AIAgent组件"""
	for child in character.get_children():
		if child is AIAgent:
			return child
	return null

func _check_current_period():
	"""检查当前时间段"""
	if not DayNightSystem:
		return
	
	var current_hour = DayNightSystem.current_hour
	
	# 检查是否进入新的课程时段
	for period in daily_schedule["morning"]:
		if abs(current_hour - period["time"]) < 0.1:  # 约6分钟误差
			if current_period != period:
				current_period = period
				_broadcast_period_change(period)
	
	for period in daily_schedule["afternoon"]:
		if abs(current_hour - period["time"]) < 0.1:
			if current_period != period:
				current_period = period
				_broadcast_period_change(period)

func _broadcast_period_change(period: Dictionary):
	"""广播课程变化"""
	if period["type"] == "break":
		_broadcast_message("课间休息时间")
	else:
		_broadcast_message(period["subject"] + "开始了，请同学们到" + period["room"])

func _broadcast_message(message: String):
	"""向所有Agent广播消息"""
	print("[ScheduleSystem] 广播：", message)
	# 这里可以触发DialogManager显示通知

func _clear_all_class_tasks():
	"""清除所有课程任务"""
	var characters = get_tree().get_nodes_in_group("character")
	for character in characters:
		var ai_agent = _get_ai_agent(character)
		if ai_agent and ai_agent.has_method("clear_tasks"):
			ai_agent.clear_tasks()

# ========== 公共接口 ==========

func get_current_period() -> Dictionary:
	"""获取当前课程时段"""
	return current_period

func get_schedule_for_character(character_name: String) -> Array:
	"""获取特定角色的课程表"""
	# 这里可以实现查询特定角色任务列表的功能
	return []

func is_class_time() -> bool:
	"""当前是否是上课时间"""
	return current_period.get("type", "") == "class"

func skip_to_next_period():
	"""跳转到下一个课程时段（用于测试）"""
	# 实现跳过当前课程的功能
	pass
