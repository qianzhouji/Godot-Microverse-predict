extends Node

# TaskManager - 任务管理核心系统
# 严格遵循时间表，确保上课时间所有相关Agent在教室

const MAX_TASKS: int = 5  # 最多5个任务
const CLASS_TASK_PRIORITY: int = 8  # 课程任务优先级（留出空间给更重要的事）
const CURRENT_TASK_PRIORITY: int = 8  # 当前课程任务优先级
const NORMAL_TASK_PRIORITY: int = 3  # 普通任务优先级

# 课程时间表
const SCHEDULE = { # 时间(小时) -> 课程信息
	8.0: {"subject": "班主任课", "teacher": "TeacherWang", "room": "教室（主教学区）", "type": "class"},
	8.75: {"subject": "课间休息", "type": "break"},
	8.916: {"subject": "英语课", "teacher": "TeacherChen", "room": "教室（主教学区）", "type": "class"},
	9.666: {"subject": "课间休息", "type": "break"},
	9.833: {"subject": "小组讨论", "room": "教室（小组讨论区）", "type": "free"},
	10.75: {"subject": "午休", "room": "食堂", "type": "free"},
	11.75: {"subject": "数学课", "teacher": "TeacherLi", "room": "教室（主教学区）", "type": "class"},
	12.5: {"subject": "课间休息", "type": "break"},
	12.666: {"subject": "体育活动", "room": "体育馆", "type": "free"}
}

# 课堂互动类型
const CLASS_INTERACTIONS = [
	"teacher_question",  # 老师提问
	"student_answer",    # 学生回答
	"peer_discussion",   # 同桌讨论
	"group_chat",        # 小组闲聊
	"teacher_warning",   # 老师警告（发现闲聊）
	"note_taking",       # 记笔记
	"listening"          # 听课
]

func _ready():
	# 监听时间变化
	var dns = get_node_or_null("/root/DayNightSystem")
	if dns:
		dns.hour_changed.connect(_on_hour_changed)
		dns.day_started.connect(_on_day_started)

func _on_day_started(day_number: int, weekday: String):
	print("[TaskManager] 第", day_number, "天开始")
	# 每天开始时为所有Agent分配基础任务
	_assign_base_tasks_to_all()

func _on_hour_changed(hour: int):
	# 检查当前时间对应的课程
	var current_class = _get_current_class(hour)
	if current_class:
		_enforce_class_attendance(current_class)

func _get_current_class(hour: int) -> Dictionary:
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
			last_class = SCHEDULE[class_time].duplicate()
			last_time = class_time
	
	if not last_class.is_empty():
		last_class["time"] = last_time
	
	return last_class

func _enforce_class_attendance(class_info: Dictionary):
	"""强制执行课程出勤"""
	var class_type = class_info.get("type", "")
	var subject = class_info.get("subject", "")
	var room = class_info.get("room", "")
	var teacher = class_info.get("teacher", "")
	
	print("[TaskManager] 强制执行: ", subject, " (", class_type, ")")
	
	# 获取所有角色
	var characters = get_tree().get_nodes_in_group("character")
	
	for character in characters:
		if not character.has_meta("character_data"):
			continue
		
		var data = character.get_meta("character_data")
		var role_type = data.get("role_type", "")
		var ai_agent = _get_ai_agent(character)
		
		if not ai_agent:
			continue
		
		# 清除现有任务（保留最多2个非课程任务，但总任务不超过5个）
		_clear_non_class_tasks(character, 2)
		
		match class_type:
			"class":
				# 正式课程：老师和学生必须在教室
				if role_type == "teacher" and character.name == teacher:
					_add_class_task(character, subject, room, "teaching", CURRENT_TASK_PRIORITY)
				elif role_type == "depression_risk_student" or role_type == "healthy_student":
					# 学生根据人设决定是否出勤（抑郁Agent可能逃课）
					if _should_attend_class(character, subject):
						_add_class_task(character, subject, room, "attending", CURRENT_TASK_PRIORITY)
					else:
						# 逃课：添加逃课任务，但优先级较低
						_add_skip_class_task(character, subject)
			
			"break":
				# 课间休息：自由活动，但限制在走廊或教室
				_add_break_task(character)
			
			"free":
				# 自由活动时间（小组讨论、午休、体育）
				if subject == "小组讨论":
					_add_free_activity_task(character, subject, room, "discussion")
				elif subject == "午休":
					_add_free_activity_task(character, subject, room, "lunch")
				elif subject == "体育活动":
					_add_free_activity_task(character, subject, room, "pe")

func _should_attend_class(character: Node, subject: String) -> bool:
	"""判断Agent是否应该上课（基于人设和状态）"""
	var personality = CharacterPersonality.get_personality(character.name)
	var role_type = personality.get("role_type", "")
	var beta_effort = personality.get("cognitive_mechanism", {}).get("beta_effort", 0.5)
	
	# 检查是否有特殊状态（生病、受伤等）
	if character.has_meta("status"):
		var status = character.get_meta("status")
		if status == "sick" or status == "injured":
			print("[TaskManager] ", character.name, " 因", status, "请假")
			return false
	
	# 抑郁Agent高努力敏感性，更可能逃课
	if role_type == "depression_risk_student":
		# 努力敏感性越高，逃课概率越高
		var skip_probability = beta_effort * 0.3  # 最高30%逃课概率
		if randf() < skip_probability:
			print("[TaskManager] ", character.name, " 选择逃课（抑郁回避）")
			return false
	
	return true

func _add_class_task(character: Node, subject: String, room: String, activity: String, priority: int):
	"""添加课程任务"""
	var ai_agent = _get_ai_agent(character)
	if not ai_agent:
		return
	
	var task = {
		"id": "class_" + subject + "_" + str(Time.get_unix_time_from_system()),
		"name": subject,
		"description": _get_class_description(character, subject, activity),
		"target_room": room,
		"activity": activity,
		"priority": priority,
		"type": "class",
		"can_interact": true,
		"interactions": _get_available_interactions(character, subject)
	}
	
	ai_agent.add_task(task)
	print("[TaskManager] ", character.name, " 添加课程任务: ", subject, " (优先级:", priority, ")")

func _get_class_description(character: Node, subject: String, activity: String) -> String:
	"""生成课程任务描述"""
	var personality = CharacterPersonality.get_personality(character.name)
	var role_type = personality.get("role_type", "")
	
	if role_type == "teacher":
		return "教授" + subject + "，准备提问学生"
	elif role_type == "depression_risk_student":
		return "在" + subject + "上努力集中注意力，但可能感到疲惫"
	else:
		return "认真听讲" + subject + "，准备回答老师提问"

func _get_available_interactions(character: Node, subject: String) -> Array:
	"""获取可用的课堂互动"""
	var personality = CharacterPersonality.get_personality(character.name)
	var role_type = personality.get("role_type", "")
	var interactions = []
	
	if role_type == "teacher":
		interactions = ["teacher_question", "listening"]
	elif role_type == "depression_risk_student":
		# 抑郁Agent较少主动互动
		interactions = ["listening", "note_taking"]
		if randf() < 0.3:  # 30%概率参与讨论
			interactions.append("peer_discussion")
	else:
		# 健康Agent更积极参与
		interactions = ["listening", "note_taking", "student_answer", "peer_discussion"]
		if randf() < 0.2:  # 20%概率闲聊
			interactions.append("group_chat")
	
	return interactions

func _add_skip_class_task(character: Node, subject: String):
	"""添加逃课任务"""
	var ai_agent = _get_ai_agent(character)
	if not ai_agent:
		return
	
	var skip_locations = ["走廊", "图书馆", "洗手间"]
	var location = skip_locations[randi() % skip_locations.size()]
	
	var task = {
		"id": "skip_" + subject,
		"name": "逃课：" + subject,
		"description": "感到疲惫/焦虑，选择不去上" + subject,
		"target_room": location,
		"priority": 2,  # 低优先级
		"type": "skip"
	}
	
	ai_agent.add_task(task)
	print("[TaskManager] ", character.name, " 逃课任务: ", subject, " -> ", location)

func _add_break_task(character: Node):
	"""添加课间休息任务"""
	var ai_agent = _get_ai_agent(character)
	if not ai_agent:
		return
	
	var personality = CharacterPersonality.get_personality(character.name)
	var extraversion = personality.get("big_five", {}).get("extraversion", 50)
	
	var task = {
		"id": "break_" + str(Time.get_unix_time_from_system()),
		"name": "课间休息",
		"description": "课间休息时间",
		"target_room": "走廊",
		"priority": 4,
		"type": "break"
	}
	
	if extraversion > 70:
		task["description"] = "课间与同学聊天、玩耍"
	elif extraversion < 40:
		task["description"] = "课间独自休息或去洗手间"
	else:
		task["description"] = "课间短暂休息"
	
	ai_agent.add_task(task)

func _add_free_activity_task(character: Node, subject: String, room: String, activity_type: String):
	"""添加自由活动任务"""
	var ai_agent = _get_ai_agent(character)
	if not ai_agent:
		return
	
	var personality = CharacterPersonality.get_personality(character.name)
	var beta_effort = personality.get("cognitive_mechanism", {}).get("beta_effort", 0.5)
	
	var task = {
		"id": "free_" + subject,
		"name": subject,
		"target_room": room,
		"type": "free",
		"priority": 5
	}
	
	match activity_type:
		"discussion":
			if beta_effort > 0.6:
				task["description"] = "参与小组讨论，但可能较少发言"
				task["priority"] = 3  # 抑郁Agent优先级较低
			else:
				task["description"] = "积极参与小组讨论"
				task["priority"] = 5
		"lunch":
			task["description"] = "午餐时间"
			if beta_effort > 0.6:
				task["description"] += "，可能会独自用餐"
			else:
				task["description"] += "，与同学一起用餐"
		"pe":
			if beta_effort > 0.6:
				task["description"] = "体育活动时间，可能会选择旁观"
				task["priority"] = 2  # 抑郁Agent高度回避
			else:
				task["description"] = "积极参与体育活动"
				task["priority"] = 5
	
	ai_agent.add_task(task)

func _assign_base_tasks_to_all():
	"""为所有Agent分配基础任务（最多3个）"""
	var characters = get_tree().get_nodes_in_group("character")
	
	for character in characters:
		var ai_agent = _get_ai_agent(character)
		if not ai_agent:
			continue
		
		# 清除现有任务
		ai_agent.clear_tasks()
		
		# 添加1-2个基础任务
		_add_base_tasks(character, ai_agent)

func _add_base_tasks(character: Node, ai_agent: Node):
	"""添加基础任务（非课程相关）"""
	var personality = CharacterPersonality.get_personality(character.name)
	var role_type = personality.get("role_type", "")
	
	# 只添加1-2个基础任务，留出空间给课程任务
	var base_tasks = []
	
	if role_type == "teacher":
		base_tasks = ["准备教案", "批改作业"]
	elif role_type == "depression_risk_student":
		base_tasks = ["整理书包", "写日记"]
	else:
		base_tasks = ["复习功课", "与同学交流"]
	
	# 只添加1个基础任务
	if base_tasks.size() > 0:
		var task = {
			"id": "base_" + base_tasks[0],
			"name": base_tasks[0],
			"description": base_tasks[0],
			"priority": NORMAL_TASK_PRIORITY
		}
		ai_agent.add_task(task)

func _clear_non_class_tasks(character: Node, keep_count: int):
	"""清除非课程任务，但保留指定数量，总任务不超过MAX_TASKS"""
	var ai_agent = _get_ai_agent(character)
	if not ai_agent:
		return
	
	var tasks = character.get_meta("tasks", [])
	var class_tasks = []
	var other_tasks = []
	
	for task in tasks:
		if task.get("type") == "class":
			class_tasks.append(task)
		else:
			other_tasks.append(task)
	
	# 只保留指定数量的非课程任务
	if other_tasks.size() > keep_count:
		other_tasks.resize(keep_count)
	
	# 合并任务列表（课程任务优先）
	var new_tasks = class_tasks + other_tasks
	new_tasks.sort_custom(func(a, b): return a.get("priority", 0) > b.get("priority", 0))
	
	# 确保总任务数不超过MAX_TASKS
	if new_tasks.size() > MAX_TASKS:
		new_tasks.resize(MAX_TASKS)
	
	character.set_meta("tasks", new_tasks)

func _get_ai_agent(character: Node) -> Node:
	"""获取角色的AIAgent组件"""
	for child in character.get_children():
		if child.has_method("add_task"):
			return child
	return null

# ========== 课堂互动 ==========

func trigger_class_interaction(character: Node, interaction_type: String):
	"""触发课堂互动"""
	var current_class = _get_current_class(0)
	if not current_class:
		return
	
	if current_class.get("type") != "class":
		return  # 只有正式课程才有这些互动
	
	match interaction_type:
		"teacher_question":
			_trigger_teacher_question(character, current_class)
		"student_answer":
			_trigger_student_answer(character, current_class)
		"peer_discussion":
			_trigger_peer_discussion(character, current_class)
		"group_chat":
			_trigger_group_chat(character, current_class)

func _trigger_teacher_question(character: Node, class_info: Dictionary):
	"""老师提问"""
	var teacher_name = class_info.get("teacher", "")
	var subject = class_info.get("subject", "")
	
	print("[TaskManager] ", teacher_name, " 在", subject, "上提问")
	# 这里可以触发DialogManager开始对话

func _trigger_student_answer(character: Node, class_info: Dictionary):
	"""学生回答"""
	print("[TaskManager] ", character.name, " 回答问题")

func _trigger_peer_discussion(character: Node, class_info: Dictionary):
	"""同桌讨论"""
	print("[TaskManager] ", character.name, " 与同桌讨论")

func _trigger_group_chat(character: Node, class_info: Dictionary):
	"""小组闲聊（有风险被老师发现）"""
	print("[TaskManager] ", character.name, " 在闲聊")
	
	# 检查是否被老师发现
	if _is_teacher_watching(class_info):
		print("[TaskManager] ", character.name, " 被老师发现闲聊！")
		_trigger_teacher_warning(character, class_info)

func _is_teacher_watching(class_info: Dictionary) -> bool:
	"""检查老师是否在注意"""
	# 简化实现：30%概率被老师注意到
	return randf() < 0.3

func _trigger_teacher_warning(character: Node, class_info: Dictionary):
	"""老师警告"""
	var teacher_name = class_info.get("teacher", "")
	print("[TaskManager] ", teacher_name, " 警告 ", character.name, " 不要闲聊")
	
	# 触发DynamicPersonality的教师批评反馈
	DynamicPersonality.apply_teacher_feedback(character, false)

# ========== 公共接口 ==========

func get_current_class_info() -> Dictionary:
	"""获取当前课程信息"""
	return _get_current_class(0)

func is_class_time() -> bool:
	"""当前是否是上课时间"""
	var current = _get_current_class(0)
	return current.get("type", "") == "class"

func can_freely_move(character: Node) -> bool:
	"""Agent是否可以自由移动（非强制课程时间）"""
	var current = _get_current_class(0)
	var class_type = current.get("type", "")
	
	if class_type == "class":
		# 正式课程时间，检查是否是逃课状态
		var tasks = character.get_meta("tasks", [])
		for task in tasks:
			if task.get("type") == "skip":
				return true  # 逃课状态可以自由移动
		return false  # 正常上课不能自由移动
	
	# 课间、午休、自由活动时间可以自由移动
	return true
