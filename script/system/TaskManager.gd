extends Node

# TaskManager - 学校任务管理系统（重构版）
# 核心职责：
# 1. 根据课程表，在上课时间强制Agent移动到对应教室
# 2. 下课时间允许Agent自由活动
# 3. 删除复杂的初始任务分配，简化系统

# 课程时间表（时间 -> 课程信息）
const SCHEDULE = {
	8.0: {"subject": "班主任课", "teacher": "TeacherWang", "room": "教室", "room_type": "main_teaching", "duration": 45},
	8.75: {"subject": "课间休息", "type": "break", "duration": 10},
	8.916: {"subject": "英语课", "teacher": "TeacherChen", "room": "教室", "room_type": "main_teaching", "duration": 45},
	9.666: {"subject": "课间休息", "type": "break", "duration": 10},
	9.833: {"subject": "小组讨论", "room": "教室", "room_type": "group_discussion", "duration": 45},
	10.75: {"subject": "午休", "room": "食堂", "room_type": "cafeteria", "duration": 60},
	11.75: {"subject": "数学课", "teacher": "TeacherLi", "room": "教室", "room_type": "main_teaching", "duration": 45},
	12.5: {"subject": "课间休息", "type": "break", "duration": 10},
	12.666: {"subject": "体育活动", "room": "体育馆", "room_type": "gym", "duration": 45}
}

# 教室场景中的具体房间名称映射
const ROOM_NAME_MAP = {
	"main_teaching": "教室（主教学区）",
	"group_discussion": "教室（小组讨论区）",
	"cafeteria": "食堂",
	"gym": "体育馆",
	"corridor": "走廊"
}

# 当前课程状态
var current_class: Dictionary = {}
var is_class_time: bool = false

func _ready():
	# 监听时间变化
	var dns = get_node_or_null("/root/DayNightSystem")
	if dns:
		dns.hour_changed.connect(_on_hour_changed)
		dns.day_started.connect(_on_day_started)
		print("[TaskManager] 已连接到DayNightSystem")
	else:
		push_warning("[TaskManager] 未找到DayNightSystem")

func _on_day_started(day_number: int, weekday: String):
	print("[TaskManager] 第", day_number, "天开始，", weekday)
	# 清除所有Agent的任务状态，准备新的一天
	_clear_all_agent_tasks()

func _on_hour_changed(hour: int):
	# 检查当前时间对应的课程
	var new_class = _get_current_class()
	
	# 如果课程发生变化
	if new_class != current_class:
		current_class = new_class
		if current_class.is_empty():
			# 放学或休息时间
			is_class_time = false
			print("[TaskManager] 当前无课程，Agent可自由活动")
		else:
			is_class_time = true
			_assign_class_tasks(current_class)

func _get_current_class() -> Dictionary:
	"""获取当前时间的课程"""
	var dns = get_node_or_null("/root/DayNightSystem")
	if not dns:
		return {}
	
	var current_hour = dns.current_hour
	
	# 找到当前应该进行的课程
	var last_class = {}
	var last_time = 0.0
	
	for class_time in SCHEDULE.keys():
		if current_hour >= class_time:
			var class_info = SCHEDULE[class_time].duplicate()
			# 检查课程是否已结束
			var end_time = class_time + (class_info.get("duration", 45) / 60.0)
			if current_hour < end_time:
				last_class = class_info
				last_class["start_time"] = class_time
				last_class["end_time"] = end_time
				last_time = class_time
	
	return last_class

func _assign_class_tasks(class_info: Dictionary):
	"""为所有Agent分配当前课程任务（移动到对应地点）"""
	var class_type = class_info.get("type", "")
	var subject = class_info.get("subject", "")
	var room_type = class_info.get("room_type", "")
	var teacher = class_info.get("teacher", "")
	
	print("[TaskManager] 开始课程: ", subject, " (", room_type, ")")
	
	# 获取所有角色
	var characters = get_tree().get_nodes_in_group("character")
	
	for character in characters:
		if not character.has_meta("character_data"):
			continue
		
		var data = character.get_meta("character_data")
		var role_type = data.get("role_type", "")
		
		# 根据课程类型分配任务
		match class_type:
			"break":
				# 课间休息：允许自由活动，不强制移动
				_remove_class_task(character)
			_:
				# 正式课程：需要移动到对应教室
				if role_type == "teacher" and character.name == teacher:
					# 授课教师移动到教室
					_add_move_to_room_task(character, room_type, subject, "teaching")
				elif role_type == "depression_risk_student" or role_type == "healthy_student":
					# 学生移动到教室（抑郁风险学生可能逃课）
					if _should_attend_class(character, subject):
						_add_move_to_room_task(character, room_type, subject, "attending")
					else:
						# 逃课：不分配移动任务，允许Agent自由决定
						_remove_class_task(character)
						print("[TaskManager] ", character.name, " 选择逃课")

func _should_attend_class(character: Node, subject: String) -> bool:
	"""判断Agent是否应该上课（基于人设）"""
	var personality = CharacterPersonality.get_personality(character.name)
	var role_type = personality.get("role_type", "")
	var beta_effort = personality.get("cognitive_mechanism", {}).get("beta_effort", 0.5)
	
	# 检查是否有特殊状态
	if character.has_meta("status"):
		var status = character.get_meta("status")
		if status == "sick" or status == "injured":
			print("[TaskManager] ", character.name, " 因", status, "请假")
			return false
	
	# 抑郁风险学生根据努力敏感性决定是否逃课
	if role_type == "depression_risk_student":
		# beta_effort越高，逃课概率越高（最高30%）
		var skip_probability = beta_effort * 0.3
		if randf() < skip_probability:
			return false
	
	return true

func _add_move_to_room_task(character: Node, room_type: String, subject: String, activity: String):
	"""添加移动到指定房间的任务"""
	var ai_agent = _get_ai_agent(character)
	if not ai_agent:
		return
	
	# 获取目标房间名称
	var target_room = ROOM_NAME_MAP.get(room_type, room_type)
	
	# 创建移动任务
	var task = {
		"id": "class_move_" + str(Time.get_unix_time_from_system()),
		"name": "前往" + subject,
		"description": _get_task_description(character, subject, target_room, activity),
		"target_room": target_room,
		"room_type": room_type,
		"activity": activity,
		"priority": 10,  # 课程任务最高优先级
		"type": "class_movement"  # 标记为课程移动任务
	}
	
	# 清除之前的课程任务
	_remove_class_task(character)
	
	# 添加新任务
	ai_agent.add_task(task)
	print("[TaskManager] ", character.name, " 分配任务: 移动到 ", target_room, " 上", subject)

func _get_task_description(character: Node, subject: String, room: String, activity: String) -> String:
	"""生成任务描述"""
	var personality = CharacterPersonality.get_personality(character.name)
	var role_type = personality.get("role_type", "")
	
	if role_type == "teacher":
		return "前往" + room + "教授" + subject
	elif role_type == "depression_risk_student":
		return "前往" + room + "上" + subject + "（感到有些疲惫）"
	else:
		return "前往" + room + "上" + subject

func _remove_class_task(character: Node):
	"""移除角色的课程任务"""
	var ai_agent = _get_ai_agent(character)
	if not ai_agent:
		return
	
	# 获取当前任务列表
	var tasks = character.get_meta("tasks", [])
	var new_tasks = []
	
	# 过滤掉课程移动任务
	for task in tasks:
		if task.get("type") != "class_movement":
			new_tasks.append(task)
	
	character.set_meta("tasks", new_tasks)

func _clear_all_agent_tasks():
	"""清除所有Agent的任务状态"""
	var characters = get_tree().get_nodes_in_group("character")
	for character in characters:
		_remove_class_task(character)

func _get_ai_agent(character: Node) -> Node:
	"""获取角色的AIAgent组件"""
	for child in character.get_children():
		if child.has_method("add_task"):
			return child
	return null

# ========== 公共接口 ==========

func get_current_class_info() -> Dictionary:
	"""获取当前课程信息"""
	return current_class

func is_in_class_time() -> bool:
	"""当前是否是上课时间"""
	return is_class_time

func get_target_room_for_character(character: Node) -> String:
	"""获取角色当前应该前往的房间"""
	if not is_class_time:
		return ""
	
	var tasks = character.get_meta("tasks", [])
	for task in tasks:
		if task.get("type") == "class_movement":
			return task.get("target_room", "")
	
	return ""
