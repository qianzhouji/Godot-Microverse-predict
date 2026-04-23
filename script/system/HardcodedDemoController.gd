extends Node
# 注意：不使用class_name，因为此脚本已配置为AutoLoad
# 通过HardcodedDemoController.instance访问单例

# ============================================
# 硬编码Demo控制器 V2 - 全天社交活动流程
# 为3个学生角色安排一整天的课程、对话、社交互动
# ============================================

# 单例
static var instance: Node

# Demo配置
const DEMO_MODE: bool = true  # 启用硬编码模式

# ============================================
# 角色配置
# ============================================
# 学生角色（抑郁风险 vs 健康对照）
var demo_agents: Array[String] = ["StudentXiaoming", "StudentXiaohong", "StudentXiaogang"]

# 角色属性（用于决策逻辑）
var agent_traits: Dictionary = {
	"StudentXiaoming": {"depression_risk": true, "phq9": 12, "personality": "内向敏感", "friends": ["StudentXiaogang"]},
	"StudentXiaohong": {"depression_risk": false, "phq9": 3, "personality": "开朗外向", "friends": ["StudentXiaogang"]},
	"StudentXiaogang": {"depression_risk": false, "phq9": 4, "personality": "活泼友善", "friends": ["StudentXiaoming", "StudentXiaohong"]}
}

var agent_positions: Dictionary = {}  # 记录每个角色的位置
var agent_dialogue_ids: Dictionary = {}  # 记录每个角色的对话ID

# ============================================
# 场景位置配置（硬编码坐标）
# ============================================
const CLASSROOM_MAIN: Vector2 = Vector2(400, 300)      # 教室主教学区
const CLASSROOM_GROUP: Vector2 = Vector2(600, 300)     # 教室小组讨论区
const CAFETERIA: Vector2 = Vector2(200, 500)           # 食堂
const GYM: Vector2 = Vector2(800, 400)                 # 体育馆
const LIBRARY: Vector2 = Vector2(100, 200)             # 图书馆

# ============================================
# 对话范围类型
# ============================================
const RANGE_WHISPER: int = 0    # 悄悄话（最多3人，30px范围）
const RANGE_NORMAL: int = 1     # 普通对话（最多7人，同一中范围）
const RANGE_BROADCAST: int = 2  # 广播（无限制，全房间）

# ============================================
# Click流程控制
# ============================================
var current_click: int = 0
var is_demo_running: bool = false

# 课程表时间线（游戏时间8:00-17:30，共约22个Click）
# 每个Click = 5分钟游戏时间
const SCHEDULE: Dictionary = {
	# ========== 上午课程 ==========
	# 早到教室，课前闲聊
	1: {"time": "8:00", "period": "课前闲聊", "location": "CLASSROOM_MAIN", "type": "free_chat"},
	2: {"time": "8:05", "period": "班主任课", "location": "CLASSROOM_MAIN", "type": "class"},
	3: {"time": "8:10", "period": "班主任课", "location": "CLASSROOM_MAIN", "type": "class"},
	# 课间休息，走廊对话
	4: {"time": "8:55", "period": "课间休息", "location": "CLASSROOM_MAIN", "type": "break_chat"},
	# 英语课
	5: {"time": "9:00", "period": "英语课", "location": "CLASSROOM_MAIN", "type": "class"},
	6: {"time": "9:05", "period": "英语课", "location": "CLASSROOM_MAIN", "type": "class"},
	# 小组讨论
	7: {"time": "9:50", "period": "小组讨论", "location": "CLASSROOM_GROUP", "type": "discussion"},
	8: {"time": "9:55", "period": "小组讨论", "location": "CLASSROOM_GROUP", "type": "discussion"},
	
	# ========== 午休 ==========
	# 去食堂路上
	9: {"time": "10:45", "period": "去食堂", "location": "CAFETERIA", "type": "transition"},
	# 午餐社交 - 多轮对话
	10: {"time": "10:50", "period": "午餐对话1", "location": "CAFETERIA", "type": "break"},
	11: {"time": "10:55", "period": "午餐对话2", "location": "CAFETERIA", "type": "break_chat"},
	12: {"time": "11:40", "period": "午餐对话3", "location": "CAFETERIA", "type": "break"},
	
	# ========== 下午课程 ==========
	# 数学课
	13: {"time": "11:45", "period": "数学课", "location": "CLASSROOM_MAIN", "type": "class"},
	14: {"time": "11:50", "period": "数学课", "location": "CLASSROOM_MAIN", "type": "class"},
	# 课间
	15: {"time": "12:35", "period": "课间闲聊", "location": "CLASSROOM_MAIN", "type": "break_chat"},
	# 体育活动
	16: {"time": "12:40", "period": "体育活动", "location": "GYM", "type": "activity"},
	17: {"time": "12:45", "period": "体育活动", "location": "GYM", "type": "activity_chat"},
	
	# ========== 放学 ==========
	# 去图书馆
	18: {"time": "13:35", "period": "去图书馆", "location": "LIBRARY", "type": "transition"},
	# 图书馆社交
	19: {"time": "13:40", "period": "图书馆对话1", "location": "LIBRARY", "type": "free"},
	20: {"time": "13:45", "period": "图书馆对话2", "location": "LIBRARY", "type": "free_chat"},
	# 告别
	21: {"time": "14:30", "period": "告别", "location": "LIBRARY", "type": "farewell"},
	22: {"time": "14:35", "period": "回家", "location": "LIBRARY", "type": "end"},
}

# 信号
signal demo_step_completed(step: int, description: String)
signal day_completed()

func _init():
	instance = self
	print("[HardcodedDemoController] _init called, instance set")

func _ready():
	print("[HardcodedDemoController] 硬编码Demo控制器初始化完成")
	print("[HardcodedDemoController] Demo模式: %s" % DEMO_MODE)
	
	if DEMO_MODE:
		# 延迟启动，等待所有系统初始化
		await get_tree().create_timer(2.0).timeout
		_start_demo()

# 启动Demo
func _start_demo():
	is_demo_running = true
	current_click = 0
	print("\n[HardcodedDemoController] ========== 全天社交活动Demo开始 ==========")
	print("[HardcodedDemoController] 角色列表: %s" % demo_agents)
	print("[HardcodedDemoController] 角色属性:")
	_print_agent_traits()
	print("[HardcodedDemoController] 课程表: 班主任课 → 英语课 → 小组讨论 → 午休 → 数学课 → 体育活动 → 放学")
	print("[HardcodedDemoController] ==========================================\n")

# 打印角色属性（辅助函数）
func _print_agent_traits():
	_print_single_agent_trait(demo_agents[0])
	_print_single_agent_trait(demo_agents[1])
	_print_single_agent_trait(demo_agents[2])

func _print_single_agent_trait(agent_id: String):
	var trait = agent_traits[agent_id]
	var risk_str = _get_risk_string(trait.depression_risk)
	print("[HardcodedDemoController]   - %s: %s (PHQ-9: %d, %s)" % [agent_id, trait.personality, trait.phq9, risk_str])

func _get_risk_string(is_depression_risk: bool) -> String:
	if is_depression_risk:
		return "抑郁风险"
	return "健康"

# ============================================
# 主入口：由TimingSystem调用
# ============================================
func execute_hardcoded_click(click_num: int, game_time: float) -> Dictionary:
	current_click = click_num
	
	# 获取当前课程信息
	var schedule_info = SCHEDULE.get(click_num, {"time": "未知", "period": "自由时间", "type": "free"})
	print("\n[HardcodedDemoController] ===== CLICK #%d | %s | %s =====" % [click_num, schedule_info.time, schedule_info.period])
	
	var assignments: Dictionary = {}
	
	# 根据课程类型和Click编号分配活动
	match schedule_info.type:
		"class":
			assignments = _handle_class_time(click_num, schedule_info)
		"discussion":
			assignments = _handle_discussion_time(click_num, schedule_info)
		"break":
			assignments = _handle_break_time(click_num, schedule_info)
		"break_chat":
			assignments = _handle_break_chat_time(click_num, schedule_info)
		"activity":
			assignments = _handle_activity_time(click_num, schedule_info)
		"activity_chat":
			assignments = _handle_activity_chat_time(click_num, schedule_info)
		"free":
			assignments = _handle_free_time(click_num, schedule_info)
		"free_chat":
			assignments = _handle_free_chat_time(click_num, schedule_info)
		"transition":
			assignments = _handle_transition_time(click_num, schedule_info)
		"farewell":
			assignments = _handle_farewell_time(click_num, schedule_info)
		"end":
			assignments = _handle_end_time(click_num, schedule_info)
		_:
			assignments = _handle_free_time(click_num, schedule_info)
	
	# 打印分配摘要
	if assignments.size() > 0:
		print("[HardcodedDemoController] 本Click分配: %d 个角色" % assignments.size())
		for agent_id in assignments.keys():
			var activities = assignments[agent_id]
			print("[HardcodedDemoController]   - %s: %d 个活动" % [agent_id, activities.size()])
			for act in activities:
				print("[HardcodedDemoController]     * %s" % act.get_type_string())
	
	# 检查是否完成全天
	if click_num >= 22:
		print("\n[HardcodedDemoController] ===== 全天活动结束 =====")
		day_completed.emit()
	
	return assignments

# ============================================
# 时间段处理函数
# ============================================

# 上课时间：移动到教室，听讲，偶尔问答
func _handle_class_time(click_num: int, schedule_info: Dictionary) -> Dictionary:
	print("[HardcodedDemoController] [上课时间] %s" % schedule_info.period)
	
	var assignments: Dictionary = {}
	var location = _get_location_vector(schedule_info.location)
	
	# 处理每个角色的活动
	assignments.merge(_handle_class_for_agent(demo_agents[0], click_num, location))
	assignments.merge(_handle_class_for_agent(demo_agents[1], click_num, location))
	assignments.merge(_handle_class_for_agent(demo_agents[2], click_num, location))
	
	return assignments

func _handle_class_for_agent(agent_id: String, click_num: int, location: Vector2) -> Dictionary:
	var assignments: Dictionary = {}
	var trait = agent_traits[agent_id]
	
	# Click 2-3: 移动到教室
	if click_num == 2 or click_num == 3:
		var activity = Activity.new(Activity.ActivityType.MOVE_TO, "move_to_class_%s_%d" % [agent_id, click_num])
		activity.parameters = {
			"target_location": Vector2(
				location.x + randf_range(-50, 50),
				location.y + randf_range(-30, 30)
			)
		}
		activity.step_index = 0
		assignments[agent_id] = [activity] as Array[Activity]
		print("[HardcodedDemoController]   %s -> 移动到教室" % agent_id)
	
	# 抑郁风险学生可能走神
	elif _is_depression_risk(agent_id) and randf() < 0.3:
		var activity = Activity.new(Activity.ActivityType.LISTEN, "listen_distracted_%s" % agent_id)
		activity.parameters = {"target_teacher": "TeacherWang", "focus_level": "low"}
		activity.step_index = 0
		assignments[agent_id] = [activity] as Array[Activity]
		print("[HardcodedDemoController]   %s -> 听讲（走神中）" % agent_id)
	
	# 小红积极举手问答
	elif agent_id == "StudentXiaohong" and randf() < 0.2:
		var activity = Activity.new(Activity.ActivityType.QA_TEACHER, "qa_%s" % agent_id)
		activity.parameters = {"question": "老师，这个问题我不太明白", "is_answer": false}
		activity.step_index = 0
		assignments[agent_id] = [activity] as Array[Activity]
		print("[HardcodedDemoController]   %s -> 向老师提问" % agent_id)
	
	# 默认：正常听讲
	else:
		var activity = Activity.new(Activity.ActivityType.LISTEN, "listen_%s_%d" % [agent_id, click_num])
		activity.parameters = {"target_teacher": "TeacherWang", "focus_level": "high"}
		activity.step_index = 0
		assignments[agent_id] = [activity] as Array[Activity]
		print("[HardcodedDemoController]   %s -> 认真听讲" % agent_id)
	
	return assignments

func _is_depression_risk(agent_id: String) -> bool:
	var trait = agent_traits[agent_id]
	return trait.depression_risk

# 小组讨论时间：移动到讨论区，发起/加入讨论
func _handle_discussion_time(click_num: int, schedule_info: Dictionary) -> Dictionary:
	print("[HardcodedDemoController] [小组讨论] 英语小组讨论")
	
	var assignments: Dictionary = {}
	var location = _get_location_vector(schedule_info.location)
	
	match click_num:
		7:
			# 移动到讨论区
			for agent_id in demo_agents:
				var activity = Activity.new(Activity.ActivityType.MOVE_TO, "move_to_discussion_%s" % agent_id)
				activity.parameters = {
					"target_location": Vector2(
						location.x + randf_range(-40, 40),
						location.y + randf_range(-40, 40)
					)
				}
				activity.step_index = 0
				assignments[agent_id] = [activity] as Array[Activity]
				print("[HardcodedDemoController]   %s -> 移动到讨论区" % agent_id)
		
		8:
			# 小刚发起讨论
			var xiaogang_activity = Activity.new(Activity.ActivityType.INITIATE_DIALOGUE, "discussion_initiator")
			xiaogang_activity.parameters = {
				"range_type": RANGE_NORMAL,
				"topic": "英语小组讨论：如何提高口语"
			}
			xiaogang_activity.step_index = 0
			assignments["StudentXiaogang"] = [xiaogang_activity] as Array[Activity]
			print("[HardcodedDemoController]   StudentXiaogang -> 发起小组讨论")
			_store_initiator_dialogue_id("StudentXiaogang")
		
		# Click 9是去食堂的过渡，小组讨论自然结束
	
	return assignments

# 午休时间：移动到食堂，自由社交
func _handle_break_time(click_num: int, schedule_info: Dictionary) -> Dictionary:
	print("[HardcodedDemoController] [午休时间] 食堂社交")
	
	var assignments: Dictionary = {}
	var location = _get_location_vector(schedule_info.location)
	
	match click_num:
		7:
			# 所有人移动到食堂
			for agent_id in demo_agents:
				var activity = Activity.new(Activity.ActivityType.MOVE_TO, "move_to_cafeteria_%s" % agent_id)
				activity.parameters = {
					"target_location": Vector2(
						location.x + randf_range(-60, 60),
						location.y + randf_range(-40, 40)
					)
				}
				activity.step_index = 0
				assignments[agent_id] = [activity] as Array[Activity]
				print("[HardcodedDemoController]   %s -> 移动到食堂" % agent_id)
		
		8:
			# 小红发起午餐对话（普通对话范围）
			var xiaohong_activity = Activity.new(Activity.ActivityType.INITIATE_DIALOGUE, "lunch_chat_initiator")
			xiaohong_activity.parameters = {
				"range_type": RANGE_NORMAL,
				"topic": "午餐闲聊：周末计划"
			}
			xiaohong_activity.step_index = 0
			assignments["StudentXiaohong"] = [xiaohong_activity] as Array[Activity]
			print("[HardcodedDemoController]   StudentXiaohong -> 发起午餐对话")
			_store_initiator_dialogue_id("StudentXiaohong")
		
		9:
			# 其他人加入午餐对话
			var dialogue_id = _get_agent_dialogue_id("StudentXiaohong")
			if dialogue_id != "":
				for agent_id in demo_agents:
					if agent_id != "StudentXiaohong":
						var activity = Activity.new(Activity.ActivityType.JOIN_DIALOGUE, "join_lunch_%s" % agent_id)
						activity.parameters = {"dialogue_id": dialogue_id}
						activity.step_index = 0
						assignments[agent_id] = [activity] as Array[Activity]
						print("[HardcodedDemoController]   %s -> 加入午餐对话" % agent_id)
			else:
				print("[HardcodedDemoController]   未找到午餐对话ID")
	
	return assignments

# 体育活动时间：移动到体育馆，进行活动
func _handle_activity_time(click_num: int, schedule_info: Dictionary) -> Dictionary:
	print("[HardcodedDemoController] [体育活动] 体育馆")
	
	var assignments: Dictionary = {}
	var location = _get_location_vector(schedule_info.location)
	
	match click_num:
		16:
			# 移动到体育馆
			for agent_id in demo_agents:
				var activity = Activity.new(Activity.ActivityType.MOVE_TO, "move_to_gym_%s" % agent_id)
				activity.parameters = {
					"target_location": Vector2(
						location.x + randf_range(-80, 80),
						location.y + randf_range(-50, 50)
					)
				}
				activity.step_index = 0
				assignments[agent_id] = [activity] as Array[Activity]
				print("[HardcodedDemoController]   %s -> 移动到体育馆" % agent_id)
		
		17:
			# 体育活动（运动为主，对话在下一个Click）
			for agent_id in demo_agents:
				var trait = agent_traits[agent_id]
				
				# 抑郁风险学生可能选择旁观
				if trait.depression_risk and randf() < 0.4:
					print("[HardcodedDemoController]   %s -> 旁观体育活动" % agent_id)
					# 不分配活动，保持空闲/旁观状态
				else:
					var activity = Activity.new(Activity.ActivityType.SPORTS, "sports_%s" % agent_id)
					activity.parameters = {
						"sport_type": _get_random_sport(),
						"intensity": 0.7
					}
					activity.step_index = 0
					assignments[agent_id] = [activity] as Array[Activity]
					print("[HardcodedDemoController]   %s -> 参与体育活动" % agent_id)
	
	return assignments

# 放学自由时间：图书馆自习或社交
func _handle_free_time(click_num: int, schedule_info: Dictionary) -> Dictionary:
	print("[HardcodedDemoController] [放学时间] 图书馆")
	
	var assignments: Dictionary = {}
	var location = _get_location_vector(schedule_info.location)
	
	match click_num:
		19:
			# 图书馆第一轮对话：小明发起（虽然内向但尝试主动）
			var xiaoming_activity = Activity.new(Activity.ActivityType.INITIATE_DIALOGUE, "library_chat1_xiaoming")
			xiaoming_activity.parameters = {
				"range_type": RANGE_NORMAL,
				"topic": "图书馆对话：最近的学习困扰"
			}
			xiaoming_activity.step_index = 0
			assignments["StudentXiaoming"] = [xiaoming_activity] as Array[Activity]
			print("[HardcodedDemoController]   StudentXiaoming -> 发起图书馆对话（学习困扰）")
			_store_initiator_dialogue_id("StudentXiaoming")
		
		15:
			# 自由活动：小明自习，小红小刚聊天
			# 小明（抑郁风险）选择独自自习
			var xiaoming_activity = Activity.new(Activity.ActivityType.SELF_STUDY, "self_study_xiaoming")
			xiaoming_activity.parameters = {
				"subject": "数学",
				"focus_level": "medium"
			}
			xiaoming_activity.step_index = 0
			assignments["StudentXiaoming"] = [xiaoming_activity] as Array[Activity]
			print("[HardcodedDemoController]   StudentXiaoming -> 独自自习（需要个人空间）")
			
			# 小红和小刚发起悄悄话
			var xiaogang_activity = Activity.new(Activity.ActivityType.INITIATE_DIALOGUE, "whisper_initiator")
			xiaogang_activity.parameters = {
				"range_type": RANGE_WHISPER,  # 悄悄话
				"topic": "悄悄话：关于小明"
			}
			xiaogang_activity.step_index = 0
			assignments["StudentXiaogang"] = [xiaogang_activity] as Array[Activity]
			print("[HardcodedDemoController]   StudentXiaogang -> 发起悄悄话")
			_store_initiator_dialogue_id("StudentXiaogang")
			
			# 小红加入悄悄话
			var dialogue_id = _get_agent_dialogue_id("StudentXiaogang")
			if dialogue_id != "":
				var xiaohong_activity = Activity.new(Activity.ActivityType.JOIN_DIALOGUE, "join_whisper_xiaohong")
				xiaohong_activity.parameters = {"dialogue_id": dialogue_id}
				xiaohong_activity.step_index = 0
				assignments["StudentXiaohong"] = [xiaohong_activity] as Array[Activity]
				print("[HardcodedDemoController]   StudentXiaohong -> 加入悄悄话")
	
	return assignments

# ============================================
# 新增：课前闲聊时间（Click 1）
# ============================================
func _handle_free_chat_time(click_num: int, schedule_info: Dictionary) -> Dictionary:
	print("[HardcodedDemoController] [课前闲聊] 教室里的早到聊天")
	
	var assignments: Dictionary = {}
	var location = _get_location_vector(schedule_info.location)
	
	match click_num:
		1:
			# 所有人移动到教室
			for agent_id in demo_agents:
				var activity = Activity.new(Activity.ActivityType.MOVE_TO, "move_to_class_early_%s" % agent_id)
				activity.parameters = {
					"target_location": Vector2(
						location.x + randf_range(-60, 60),
						location.y + randf_range(-40, 40)
					)
				}
				activity.step_index = 0
				assignments[agent_id] = [activity] as Array[Activity]
				print("[HardcodedDemoController]   %s -> 早到教室" % agent_id)
		
		4:
			# 课间休息：小明和小刚聊天（朋友间对话）
			var xiaoming_activity = Activity.new(Activity.ActivityType.INITIATE_DIALOGUE, "break_chat_xiaoming")
			xiaoming_activity.parameters = {
				"range_type": RANGE_NORMAL,
				"topic": "课间闲聊：昨晚的作业"
			}
			xiaoming_activity.step_index = 0
			assignments["StudentXiaoming"] = [xiaoming_activity] as Array[Activity]
			print("[HardcodedDemoController]   StudentXiaoming -> 发起课间对话")
			_store_initiator_dialogue_id("StudentXiaoming")
		
		11:
			# 午餐第二轮对话：小刚发起关于兴趣的话题
			var xiaogang_activity = Activity.new(Activity.ActivityType.INITIATE_DIALOGUE, "lunch_chat2_xiaogang")
			xiaogang_activity.parameters = {
				"range_type": RANGE_NORMAL,
				"topic": "午餐话题：最喜欢的电影"
			}
			xiaogang_activity.step_index = 0
			assignments["StudentXiaogang"] = [xiaogang_activity] as Array[Activity]
			print("[HardcodedDemoController]   StudentXiaogang -> 发起午餐对话2")
			_store_initiator_dialogue_id("StudentXiaogang")
		
		15:
			# 课间闲聊：小红分享趣事
			var xiaohong_activity = Activity.new(Activity.ActivityType.INITIATE_DIALOGUE, "break_chat2_xiaohong")
			xiaohong_activity.parameters = {
				"range_type": RANGE_NORMAL,
				"topic": "课间分享：周末的有趣经历"
			}
			xiaohong_activity.step_index = 0
			assignments["StudentXiaohong"] = [xiaohong_activity] as Array[Activity]
			print("[HardcodedDemoController]   StudentXiaohong -> 发起课间分享")
			_store_initiator_dialogue_id("StudentXiaohong")
		
		20:
			# 图书馆第二轮对话：三人一起讨论学习
			var xiaogang_activity = Activity.new(Activity.ActivityType.INITIATE_DIALOGUE, "library_chat2_xiaogang")
			xiaogang_activity.parameters = {
				"range_type": RANGE_NORMAL,
				"topic": "图书馆讨论：一起复习考试"
			}
			xiaogang_activity.step_index = 0
			assignments["StudentXiaogang"] = [xiaogang_activity] as Array[Activity]
			print("[HardcodedDemoController]   StudentXiaogang -> 发起图书馆讨论")
			_store_initiator_dialogue_id("StudentXiaogang")
	
	return assignments

# ============================================
# 新增：课间对话时间（Click 4）
# ============================================
func _handle_break_chat_time(click_num: int, schedule_info: Dictionary) -> Dictionary:
	print("[HardcodedDemoController] [课间对话] 加入对话")
	
	var assignments: Dictionary = {}
	
	# 加入小明的课间对话
	var dialogue_id = _get_agent_dialogue_id("StudentXiaoming")
	if dialogue_id != "":
		for agent_id in demo_agents:
			if agent_id != "StudentXiaoming":
				var activity = Activity.new(Activity.ActivityType.JOIN_DIALOGUE, "join_break_chat_%s" % agent_id)
				activity.parameters = {"dialogue_id": dialogue_id}
				activity.step_index = 0
				assignments[agent_id] = [activity] as Array[Activity]
				print("[HardcodedDemoController]   %s -> 加入课间对话" % agent_id)
	else:
		print("[HardcodedDemoController]   未找到课间对话ID")
	
	return assignments

# ============================================
# 新增：午休多轮对话（Click 10-12）
# ============================================
func _handle_break_time(click_num: int, schedule_info: Dictionary) -> Dictionary:
	print("[HardcodedDemoController] [午休时间] 食堂社交 - 多轮对话")
	
	var assignments: Dictionary = {}
	var location = _get_location_vector(schedule_info.location)
	
	match click_num:
		9:
			# 所有人移动到食堂
			for agent_id in demo_agents:
				var activity = Activity.new(Activity.ActivityType.MOVE_TO, "move_to_cafeteria_%s" % agent_id)
				activity.parameters = {
					"target_location": Vector2(
						location.x + randf_range(-60, 60),
						location.y + randf_range(-40, 40)
					)
				}
				activity.step_index = 0
				assignments[agent_id] = [activity] as Array[Activity]
				print("[HardcodedDemoController]   %s -> 移动到食堂" % agent_id)
		
		10:
			# 午餐第一轮对话：小红发起（周末计划）
			var xiaohong_activity = Activity.new(Activity.ActivityType.INITIATE_DIALOGUE, "lunch_chat1_xiaohong")
			xiaohong_activity.parameters = {
				"range_type": RANGE_NORMAL,
				"topic": "午餐闲聊：周末计划"
			}
			xiaohong_activity.step_index = 0
			assignments["StudentXiaohong"] = [xiaohong_activity] as Array[Activity]
			print("[HardcodedDemoController]   StudentXiaohong -> 发起午餐对话1（周末计划）")
			_store_initiator_dialogue_id("StudentXiaohong")
		
		12:
			# 午餐第三轮对话：小明分享（虽然内向但被朋友带动）
			var xiaoming_activity = Activity.new(Activity.ActivityType.INITIATE_DIALOGUE, "lunch_chat3_xiaoming")
			xiaoming_activity.parameters = {
				"range_type": RANGE_NORMAL,
				"topic": "午餐分享：最近看的一本书"
			}
			xiaoming_activity.step_index = 0
			assignments["StudentXiaoming"] = [xiaoming_activity] as Array[Activity]
			print("[HardcodedDemoController]   StudentXiaoming -> 发起午餐对话3（书籍分享）")
			_store_initiator_dialogue_id("StudentXiaoming")
	
	return assignments

# ============================================
# 新增：加入午餐对话（Click 11）
# ============================================
func _handle_transition_time(click_num: int, schedule_info: Dictionary) -> Dictionary:
	print("[HardcodedDemoController] [场景过渡] 加入对话")
	
	var assignments: Dictionary = {}
	var location = _get_location_vector(schedule_info.location)
	
	match click_num:
		9:
			# 去食堂的路上（移动）
			for agent_id in demo_agents:
				var activity = Activity.new(Activity.ActivityType.MOVE_TO, "walk_to_cafeteria_%s" % agent_id)
				activity.parameters = {
					"target_location": Vector2(
						location.x + randf_range(-40, 40),
						location.y + randf_range(-30, 30)
					)
				}
				activity.step_index = 0
				assignments[agent_id] = [activity] as Array[Activity]
				print("[HardcodedDemoController]   %s -> 走向食堂" % agent_id)
		
		18:
			# 去图书馆的路上
			for agent_id in demo_agents:
				var activity = Activity.new(Activity.ActivityType.MOVE_TO, "walk_to_library_%s" % agent_id)
				activity.parameters = {
					"target_location": Vector2(
						location.x + randf_range(-50, 50),
						location.y + randf_range(-30, 30)
					)
				}
				activity.step_index = 0
				assignments[agent_id] = [activity] as Array[Activity]
				print("[HardcodedDemoController]   %s -> 走向图书馆" % agent_id)
	
	return assignments

# ============================================
# 新增：体育活动对话（Click 17）
# ============================================
func _handle_activity_chat_time(click_num: int, schedule_info: Dictionary) -> Dictionary:
	print("[HardcodedDemoController] [体育活动] 边运动边聊天")
	
	var assignments: Dictionary = {}
	
	# 小红发起体育活动的轻松对话
	var xiaohong_activity = Activity.new(Activity.ActivityType.INITIATE_DIALOGUE, "gym_chat_xiaohong")
	xiaohong_activity.parameters = {
		"range_type": RANGE_NORMAL,
		"topic": "运动闲聊：最喜欢的体育明星"
	}
	xiaohong_activity.step_index = 0
	assignments["StudentXiaohong"] = [xiaohong_activity] as Array[Activity]
	print("[HardcodedDemoController]   StudentXiaohong -> 发起运动闲聊")
	_store_initiator_dialogue_id("StudentXiaohong")
	
	return assignments

# ============================================
# 新增：告别时间（Click 21）
# ============================================
func _handle_farewell_time(click_num: int, schedule_info: Dictionary) -> Dictionary:
	print("[HardcodedDemoController] [告别时间] 放学告别")
	
	var assignments: Dictionary = {}
	
	# 小刚发起告别对话
	var xiaogang_activity = Activity.new(Activity.ActivityType.INITIATE_DIALOGUE, "farewell_xiaogang")
	xiaogang_activity.parameters = {
		"range_type": RANGE_NORMAL,
		"topic": "告别：明天见"
	}
	xiaogang_activity.step_index = 0
	assignments["StudentXiaogang"] = [xiaogang_activity] as Array[Activity]
	print("[HardcodedDemoController]   StudentXiaogang -> 发起告别")
	_store_initiator_dialogue_id("StudentXiaogang")
	
	return assignments

# ============================================
# 新增：结束时间（Click 22）
# ============================================
func _handle_end_time(click_num: int, schedule_info: Dictionary) -> Dictionary:
	print("[HardcodedDemoController] [结束] 各自回家")
	
	var assignments: Dictionary = {}
	
	# 所有人离开当前场景（模拟回家）
	for agent_id in demo_agents:
		print("[HardcodedDemoController]   %s -> 回家" % agent_id)
		# 不分配具体活动，让Agent保持空闲状态
	
	return assignments

# ============================================
# 辅助函数
# ============================================

# 获取随机运动类型
func _get_random_sport() -> String:
	if randf() < 0.5:
		return "篮球"
	else:
		return "羽毛球"

# 获取位置向量
func _get_location_vector(location_name: String) -> Vector2:
	match location_name:
		"CLASSROOM_MAIN": return CLASSROOM_MAIN
		"CLASSROOM_GROUP": return CLASSROOM_GROUP
		"CAFETERIA": return CAFETERIA
		"GYM": return GYM
		"LIBRARY": return LIBRARY
		_: return CLASSROOM_MAIN

# ============================================
# 对话ID管理
# ============================================

# 存储各角色的对话ID
var _agent_dialogue_ids: Dictionary = {}

# 设置角色的对话ID（由AIAgent在发起对话成功后调用）
func set_agent_dialogue_id(agent_id: String, dialogue_id: String) -> void:
	_agent_dialogue_ids[agent_id] = dialogue_id
	print("[HardcodedDemoController] 记录 %s 的对话ID: %s" % [agent_id, dialogue_id])

# 存储发起者的对话ID（供其他人加入）
func _store_initiator_dialogue_id(agent_id: String) -> void:
	# 延迟获取，因为对话ID是在活动执行后才生成的
	await get_tree().create_timer(0.5).timeout
	var agent = _get_agent(agent_id)
	if agent and agent.has_meta("current_dialogue_id"):
		var dialogue_id = agent.get_meta("current_dialogue_id")
		_agent_dialogue_ids[agent_id] = dialogue_id
		print("[HardcodedDemoController] 存储 %s 的对话ID: %s" % [agent_id, dialogue_id])

# 获取角色的对话ID
func _get_agent_dialogue_id(agent_id: String) -> String:
	# 优先使用记录的对话ID
	if _agent_dialogue_ids.has(agent_id):
		return _agent_dialogue_ids[agent_id]
	
	# 从角色metadata获取
	var agent = _get_agent(agent_id)
	if agent and agent.has_meta("current_dialogue_id"):
		return agent.get_meta("current_dialogue_id")
	
	return ""

# 兼容旧接口
func set_xiaoming_dialogue_id(dialogue_id: String) -> void:
	set_agent_dialogue_id("StudentXiaoming", dialogue_id)

func _get_xiaoming_dialogue_id() -> String:
	return _get_agent_dialogue_id("StudentXiaoming")

# 获取Agent角色节点
func _get_agent(agent_id: String) -> CharacterBody2D:
	var characters = get_tree().get_nodes_in_group("character")
	for char_node in characters:
		if char_node.name == agent_id:
			return char_node
	return null

# 检查Demo是否运行中
func is_running() -> bool:
	return is_demo_running and DEMO_MODE

# 获取当前Click数
func get_current_click() -> int:
	return current_click

# 重置Demo
func reset_demo():
	current_click = 0
	is_demo_running = false
	print("[HardcodedDemoController] Demo已重置")
