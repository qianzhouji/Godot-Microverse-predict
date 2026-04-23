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

# 课程表时间线（游戏时间8:00-17:30，每个Click = 5分钟游戏时间）
# 对话发起和加入必须错开（不在同一个Click）
const SCHEDULE: Dictionary = {
	# ========== 8:00-10:00 上午课程 ==========
	# 8:00 早到，移动到教室
	1: {"time": "8:00", "period": "早到教室", "location": "CLASSROOM_MAIN", "type": "move"},
	# 8:05 课前闲聊 - 小刚发起
	2: {"time": "8:05", "period": "课前闲聊发起", "location": "CLASSROOM_MAIN", "type": "dialogue_initiate"},
	# 8:10 课前闲聊 - 小明小红加入
	3: {"time": "8:10", "period": "课前闲聊加入", "location": "CLASSROOM_MAIN", "type": "dialogue_join"},
	# 8:15 班主任课开始
	4: {"time": "8:15", "period": "班主任课", "location": "CLASSROOM_MAIN", "type": "class"},
	5: {"time": "8:20", "period": "班主任课", "location": "CLASSROOM_MAIN", "type": "class"},
	6: {"time": "8:25", "period": "班主任课", "location": "CLASSROOM_MAIN", "type": "class"},
	7: {"time": "8:30", "period": "班主任课", "location": "CLASSROOM_MAIN", "type": "class"},
	# 8:35 课间休息 - 小明小刚对话发起
	8: {"time": "8:35", "period": "课间对话发起", "location": "CLASSROOM_MAIN", "type": "dialogue_initiate"},
	# 8:40 课间休息 - 小红加入
	9: {"time": "8:40", "period": "课间对话加入", "location": "CLASSROOM_MAIN", "type": "dialogue_join"},
	# 8:45 英语课
	10: {"time": "8:45", "period": "英语课", "location": "CLASSROOM_MAIN", "type": "class"},
	11: {"time": "8:50", "period": "英语课", "location": "CLASSROOM_MAIN", "type": "class"},
	12: {"time": "8:55", "period": "英语课", "location": "CLASSROOM_MAIN", "type": "class"},
	13: {"time": "9:00", "period": "英语课", "location": "CLASSROOM_MAIN", "type": "class"},
	# 9:05 移动到小组讨论区
	14: {"time": "9:05", "period": "去讨论区", "location": "CLASSROOM_GROUP", "type": "move"},
	# 9:10 小组讨论 - 小红发起
	15: {"time": "9:10", "period": "小组讨论发起", "location": "CLASSROOM_GROUP", "type": "dialogue_initiate"},
	# 9:15 小组讨论 - 小明小刚加入
	16: {"time": "9:15", "period": "小组讨论加入", "location": "CLASSROOM_GROUP", "type": "dialogue_join"},
	# 9:20 继续小组讨论
	17: {"time": "9:20", "period": "小组讨论继续", "location": "CLASSROOM_GROUP", "type": "dialogue_continue"},
	# 9:25 移动到食堂
	18: {"time": "9:25", "period": "去食堂", "location": "CAFETERIA", "type": "move"},
	# 9:30 午餐对话1 - 小刚发起
	19: {"time": "9:30", "period": "午餐对话1发起", "location": "CAFETERIA", "type": "dialogue_initiate"},
	# 9:35 午餐对话1 - 其他人加入
	20: {"time": "9:35", "period": "午餐对话1加入", "location": "CAFETERIA", "type": "dialogue_join"},
	# 9:40 午餐对话2 - 小红发起
	21: {"time": "9:40", "period": "午餐对话2发起", "location": "CAFETERIA", "type": "dialogue_initiate"},
	# 9:45 午餐对话2 - 其他人加入
	22: {"time": "9:45", "period": "午餐对话2加入", "location": "CAFETERIA", "type": "dialogue_join"},
	# 9:50 午餐对话3 - 小明发起
	23: {"time": "9:50", "period": "午餐对话3发起", "location": "CAFETERIA", "type": "dialogue_initiate"},
	# 9:55 午餐对话3 - 其他人加入
	24: {"time": "9:55", "period": "午餐对话3加入", "location": "CAFETERIA", "type": "dialogue_join"},
	# 10:00 结束
	25: {"time": "10:00", "period": "上午结束", "location": "CAFETERIA", "type": "end"},
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
	var agent_trait = agent_traits[agent_id]
	var risk_str = _get_risk_string(agent_trait.depression_risk)
	print("[HardcodedDemoController]   - %s: %s (PHQ-9: %d, %s)" % [agent_id, agent_trait.personality, agent_trait.phq9, risk_str])

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
	var schedule_info = SCHEDULE.get(click_num, {"time": "未知", "period": "自由时间", "location": "CLASSROOM_MAIN", "type": "free"})
	print("\n[HardcodedDemoController] ===== CLICK #%d | %s | %s =====" % [click_num, schedule_info.time, schedule_info.period])
	
	var assignments: Dictionary = {}
	
	# 根据课程类型和Click编号分配活动
	match schedule_info.type:
		"move":
			assignments = _handle_move_time(click_num, schedule_info)
		"class":
			assignments = _handle_class_time(click_num, schedule_info)
		"dialogue_initiate":
			assignments = _handle_dialogue_initiate(click_num, schedule_info)
		"dialogue_join":
			assignments = _handle_dialogue_join(click_num, schedule_info)
		"dialogue_continue":
			assignments = _handle_dialogue_continue(click_num, schedule_info)
		"end":
			assignments = _handle_end_time(click_num, schedule_info)
		_:
			assignments = {}
	
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
# 8:00-10:00 时间段处理函数
# ============================================

# 移动时间
func _handle_move_time(click_num: int, schedule_info: Dictionary) -> Dictionary:
	print("[HardcodedDemoController] [移动] %s" % schedule_info.period)
	
	var assignments: Dictionary = {}
	var location = _get_location_vector(schedule_info.location)
	
	# Click 1: 早到教室
	if click_num == 1:
		for agent_id in demo_agents:
			var activity = Activity.new(Activity.ActivityType.MOVE_TO, "move_to_class_%s" % agent_id)
			activity.parameters = {
				"target_location": Vector2(
					location.x + randf_range(-50, 50),
					location.y + randf_range(-30, 30)
				)
			}
			activity.step_index = 0
			assignments[agent_id] = [activity] as Array[Activity]
			print("[HardcodedDemoController]   %s -> 移动到教室" % agent_id)
	
	# Click 14: 去讨论区
	elif click_num == 14:
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
	
	# Click 18: 去食堂
	elif click_num == 18:
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
	
	return assignments

# 上课时间
func _handle_class_time(click_num: int, schedule_info: Dictionary) -> Dictionary:
	print("[HardcodedDemoController] [上课时间] %s" % schedule_info.period)
	
	var assignments: Dictionary = {}
	
	for agent_id in demo_agents:
		var agent_trait = agent_traits[agent_id]
		
		# 抑郁风险学生可能走神
		if agent_trait.depression_risk and randf() < 0.3:
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

# 对话发起
func _handle_dialogue_initiate(click_num: int, schedule_info: Dictionary) -> Dictionary:
	print("[HardcodedDemoController] [对话发起] %s" % schedule_info.period)
	
	var assignments: Dictionary = {}
	var location = _get_location_vector(schedule_info.location)
	
	match click_num:
		2:
			# 8:05 课前闲聊 - 小刚发起
			var activity = Activity.new(Activity.ActivityType.INITIATE_DIALOGUE, "pre_class_chat")
			activity.parameters = {
				"range_type": RANGE_NORMAL,
				"topic": "课前闲聊：周末过得怎么样"
			}
			activity.step_index = 0
			assignments["StudentXiaogang"] = [activity] as Array[Activity]
			print("[HardcodedDemoController]   StudentXiaogang -> 发起课前闲聊")
			_store_initiator_dialogue_id("StudentXiaogang")
		
		8:
			# 8:35 课间对话 - 小明发起
			var activity = Activity.new(Activity.ActivityType.INITIATE_DIALOGUE, "break_chat_1")
			activity.parameters = {
				"range_type": RANGE_NORMAL,
				"topic": "课间闲聊：昨晚的作业好难"
			}
			activity.step_index = 0
			assignments["StudentXiaoming"] = [activity] as Array[Activity]
			print("[HardcodedDemoController]   StudentXiaoming -> 发起课间对话")
			_store_initiator_dialogue_id("StudentXiaoming")
		
		15:
			# 9:10 小组讨论 - 小红发起
			var activity = Activity.new(Activity.ActivityType.INITIATE_DIALOGUE, "group_discussion")
			activity.parameters = {
				"range_type": RANGE_NORMAL,
				"topic": "小组讨论：英语口语练习"
			}
			activity.step_index = 0
			assignments["StudentXiaohong"] = [activity] as Array[Activity]
			print("[HardcodedDemoController]   StudentXiaohong -> 发起小组讨论")
			_store_initiator_dialogue_id("StudentXiaohong")
		
		19:
			# 9:30 午餐对话1 - 小刚发起
			var activity = Activity.new(Activity.ActivityType.INITIATE_DIALOGUE, "lunch_chat_1")
			activity.parameters = {
				"range_type": RANGE_NORMAL,
				"topic": "午餐闲聊：最喜欢的食物"
			}
			activity.step_index = 0
			assignments["StudentXiaogang"] = [activity] as Array[Activity]
			print("[HardcodedDemoController]   StudentXiaogang -> 发起午餐对话1")
			_store_initiator_dialogue_id("StudentXiaogang")
		
		21:
			# 9:40 午餐对话2 - 小红发起
			var activity = Activity.new(Activity.ActivityType.INITIATE_DIALOGUE, "lunch_chat_2")
			activity.parameters = {
				"range_type": RANGE_NORMAL,
				"topic": "午餐闲聊：周末计划"
			}
			activity.step_index = 0
			assignments["StudentXiaohong"] = [activity] as Array[Activity]
			print("[HardcodedDemoController]   StudentXiaohong -> 发起午餐对话2")
			_store_initiator_dialogue_id("StudentXiaohong")
		
		23:
			# 9:50 午餐对话3 - 小明发起
			var activity = Activity.new(Activity.ActivityType.INITIATE_DIALOGUE, "lunch_chat_3")
			activity.parameters = {
				"range_type": RANGE_NORMAL,
				"topic": "午餐分享：最近看的一本书"
			}
			activity.step_index = 0
			assignments["StudentXiaoming"] = [activity] as Array[Activity]
			print("[HardcodedDemoController]   StudentXiaoming -> 发起午餐对话3")
			_store_initiator_dialogue_id("StudentXiaoming")
	
	return assignments

# 对话加入
func _handle_dialogue_join(click_num: int, schedule_info: Dictionary) -> Dictionary:
	print("[HardcodedDemoController] [对话加入] %s" % schedule_info.period)
	
	var assignments: Dictionary = {}
	
	match click_num:
		3:
			# 8:10 加入课前闲聊（小刚发起的）
			var dialogue_id = _get_agent_dialogue_id("StudentXiaogang")
			if dialogue_id != "":
				for agent_id in ["StudentXiaoming", "StudentXiaohong"]:
					var activity = Activity.new(Activity.ActivityType.JOIN_DIALOGUE, "join_pre_class_%s" % agent_id)
					activity.parameters = {"dialogue_id": dialogue_id}
					activity.step_index = 0
					assignments[agent_id] = [activity] as Array[Activity]
					print("[HardcodedDemoController]   %s -> 加入课前闲聊" % agent_id)
		
		9:
			# 8:40 加入课间对话（小明发起的）
			var dialogue_id = _get_agent_dialogue_id("StudentXiaoming")
			if dialogue_id != "":
				for agent_id in ["StudentXiaogang", "StudentXiaohong"]:
					var activity = Activity.new(Activity.ActivityType.JOIN_DIALOGUE, "join_break_%s" % agent_id)
					activity.parameters = {"dialogue_id": dialogue_id}
					activity.step_index = 0
					assignments[agent_id] = [activity] as Array[Activity]
					print("[HardcodedDemoController]   %s -> 加入课间对话" % agent_id)
		
		16:
			# 9:15 加入小组讨论（小红发起的）
			var dialogue_id = _get_agent_dialogue_id("StudentXiaohong")
			if dialogue_id != "":
				for agent_id in ["StudentXiaoming", "StudentXiaogang"]:
					var activity = Activity.new(Activity.ActivityType.JOIN_DIALOGUE, "join_discussion_%s" % agent_id)
					activity.parameters = {"dialogue_id": dialogue_id}
					activity.step_index = 0
					assignments[agent_id] = [activity] as Array[Activity]
					print("[HardcodedDemoController]   %s -> 加入小组讨论" % agent_id)
		
		20:
			# 9:35 加入午餐对话1（小刚发起的）
			var dialogue_id = _get_agent_dialogue_id("StudentXiaogang")
			if dialogue_id != "":
				for agent_id in ["StudentXiaoming", "StudentXiaohong"]:
					var activity = Activity.new(Activity.ActivityType.JOIN_DIALOGUE, "join_lunch1_%s" % agent_id)
					activity.parameters = {"dialogue_id": dialogue_id}
					activity.step_index = 0
					assignments[agent_id] = [activity] as Array[Activity]
					print("[HardcodedDemoController]   %s -> 加入午餐对话1" % agent_id)
		
		22:
			# 9:45 加入午餐对话2（小红发起的）
			var dialogue_id = _get_agent_dialogue_id("StudentXiaohong")
			if dialogue_id != "":
				for agent_id in ["StudentXiaoming", "StudentXiaogang"]:
					var activity = Activity.new(Activity.ActivityType.JOIN_DIALOGUE, "join_lunch2_%s" % agent_id)
					activity.parameters = {"dialogue_id": dialogue_id}
					activity.step_index = 0
					assignments[agent_id] = [activity] as Array[Activity]
					print("[HardcodedDemoController]   %s -> 加入午餐对话2" % agent_id)
		
		24:
			# 9:55 加入午餐对话3（小明发起的）
			var dialogue_id = _get_agent_dialogue_id("StudentXiaoming")
			if dialogue_id != "":
				for agent_id in ["StudentXiaogang", "StudentXiaohong"]:
					var activity = Activity.new(Activity.ActivityType.JOIN_DIALOGUE, "join_lunch3_%s" % agent_id)
					activity.parameters = {"dialogue_id": dialogue_id}
					activity.step_index = 0
					assignments[agent_id] = [activity] as Array[Activity]
					print("[HardcodedDemoController]   %s -> 加入午餐对话3" % agent_id)
	
	return assignments

# 对话继续
func _handle_dialogue_continue(click_num: int, schedule_info: Dictionary) -> Dictionary:
	print("[HardcodedDemoController] [对话继续] %s" % schedule_info.period)
	
	var assignments: Dictionary = {}
	
	# Click 17: 9:20 小组讨论继续
	if click_num == 17:
		# 所有人在对话中，系统自动管理发言队列
		print("[HardcodedDemoController]   小组讨论继续进行")
	
	return assignments

# 结束时间
func _handle_end_time(click_num: int, schedule_info: Dictionary) -> Dictionary:
	print("[HardcodedDemoController] [结束] %s" % schedule_info.period)
	
	var assignments: Dictionary = {}
	
	# 10:00 上午结束
	if click_num == 25:
		print("[HardcodedDemoController]   上午活动结束")
	
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
