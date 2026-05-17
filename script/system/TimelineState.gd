extends Node
class_name TimelineState

# 单例实例
static var instance: TimelineState

# 课程表配置
const SCHEDULE = {
	8.0: {"subject": "班主任课", "room": "教室（主教学区）", "type": "class"},
	8.916: {"subject": "英语课", "room": "教室（主教学区）", "type": "class"},
	9.833: {"subject": "小组讨论", "room": "教室（小组讨论区）", "type": "discussion"},
	10.75: {"subject": "午休", "room": "食堂", "type": "break"},
	11.75: {"subject": "数学课", "room": "教室（主教学区）", "type": "class"},
	12.666: {"subject": "体育活动", "room": "体育馆", "type": "activity"}
}

# 当前状态
var current_period: String = ""
var current_subject: String = ""
var current_room: String = ""
var is_class_time: bool = false

func _ready():
	instance = self
	
	# 等待TimingSystem初始化完成
	await get_tree().create_timer(0.5).timeout
	
	if TimingSystem.instance:
		TimingSystem.instance.click_triggered.connect(_on_click)
		print("[TimelineState] 已连接到TimingSystem")
	else:
		push_error("[TimelineState] TimingSystem未找到")

func _on_click(game_time: float, day: int, click_num: int):
	update_state(game_time)
	print("[TimelineState] 当前时段：%s，课程：%s" % [current_period, current_subject])

func update_state(game_time: float):
	var hour = game_time / 60.0
	
	# 查找当前课程
	var current_schedule = null
	var schedule_hours = SCHEDULE.keys()
	schedule_hours.sort()
	
	for i in range(schedule_hours.size()):
		var schedule_hour = schedule_hours[i]
		var next_hour = schedule_hours[i + 1] if i + 1 < schedule_hours.size() else 17.0
		
		if hour >= schedule_hour and hour < next_hour:
			current_schedule = SCHEDULE[schedule_hour]
			break
	
	if current_schedule:
		current_subject = current_schedule.subject
		current_room = current_schedule.room
		is_class_time = (current_schedule.type == "class")
		
		if is_class_time:
			current_period = "class_time"
		elif current_schedule.type == "break":
			current_period = "break_time"
		elif current_schedule.type == "discussion":
			current_period = "discussion_time"
		elif current_schedule.type == "activity":
			current_period = "activity_time"
		else:
			current_period = "free_time"
	else:
		current_period = "free_time"
		current_subject = ""
		current_room = ""
		is_class_time = false

# 获取当前时段引导信息。
# 这些字段只提供给LLM作为情境参考，不作为系统层硬性拦截条件。
func get_constraints() -> Dictionary:
	match current_period:
		"class_time":
			return {
				"can_speak_freely": false,
				"can_leave_room": true,
				"must_follow_teacher": true,
				"can_start_dialogue": true,
				"description": "上课时间，通常应优先考虑听课、问答等课堂活动"
			}
		"break_time":
			return {
				"can_speak_freely": true,
				"can_leave_room": true,
				"must_follow_teacher": false,
				"can_start_dialogue": true,
				"description": "午休时间，可自由活动"
			}
		"discussion_time":
			return {
				"can_speak_freely": true,
				"can_leave_room": true,
				"must_follow_teacher": true,
				"can_start_dialogue": true,
				"description": "小组讨论时间，通常应优先围绕讨论任务行动"
			}
		"activity_time":
			return {
				"can_speak_freely": true,
				"can_leave_room": true,
				"must_follow_teacher": true,
				"can_start_dialogue": true,
				"description": "活动时间，通常应优先围绕指定活动行动"
			}
		_:
			return {
				"can_speak_freely": true,
				"can_leave_room": true,
				"must_follow_teacher": false,
				"can_start_dialogue": true,
				"description": "自由时间"
			}

# 获取当前应该所在的房间
func get_expected_room() -> String:
	return current_room

# 检查Agent是否应该在当前房间
func is_agent_in_correct_room(agent_room: String) -> bool:
	if current_room.is_empty():
		return true  # 自由时间，不限制
	return agent_room == current_room
