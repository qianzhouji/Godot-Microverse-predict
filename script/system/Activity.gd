class_name Activity
extends RefCounted

# ============================================
# Activity System V2 - 基础活动数据结构
# ============================================
# 所有可执行活动的基础定义
# 支持专注度机制和场景约束
# ============================================

# 活动类型枚举
enum ActivityType {
	MOVE_TO,
	INITIATE_DIALOGUE,
	JOIN_DIALOGUE,
	LEAVE_DIALOGUE,
	LISTEN,
	QA_TEACHER,
	SELF_STUDY,
	SPORTS,
	GROUP_DISCUSSION,
	NORMAL_DIALOGUE,
	WHISPER
}

# 专注度档位
enum FocusLevel {
	LOW = 30,      # 30% 专注
	MEDIUM = 65,   # 65% 专注
	HIGH = 100     # 100% 专注
}

# ============================================
# 活动属性
# ============================================
var activity_id: String           # 唯一标识
var activity_type: ActivityType   # 活动类型
var activity_name: String         # 显示名称

# 约束条件
var allowed_scenes: Array[String] = []   # 允许的场景（空数组=无限制）
var required_state: String = ""          # 所需角色状态（如"in_class"）
var requires_focus: bool = false         # 是否需要专注度

# 专注度相关
var focus_level: FocusLevel = FocusLevel.HIGH  # 默认100%
var effort_multiplier: float = 1.0             # 努力倍数（根据专注度计算）
var reward_multiplier: float = 1.0             # 奖赏倍数（根据专注度计算）

# 活动参数
var parameters: Dictionary = {}   # 活动特定参数
# MOVE_TO: { "target_location": Vector2, "target_room": String }
# NORMAL_DIALOGUE: { "target_agent": String, "topic": String }
# WHISPER: { "target_agent": String, "content": String }
# LISTEN: { "target_teacher": String, "subject": String }
# QA_TEACHER: { "question": String, "is_answer": bool }
# SELF_STUDY: { "subject": String, "material": String }
# SPORTS: { "sport_type": String, "intensity": float }
# GROUP_DISCUSSION: { "topic": String, "members": Array[String] }

# 活动元数据
var duration_expected: float = 0.0     # 预期持续时间（游戏分钟）
var is_interruptible: bool = true      # 是否可中断
var created_at: float = 0.0            # 创建时间戳

# ============================================
# 构造函数
# ============================================
func _init(p_type: ActivityType, p_id: String = ""):
	activity_type = p_type
	activity_id = p_id if p_id != "" else _generate_id()
	activity_name = _get_default_name(p_type)
	created_at = Time.get_unix_time_from_system()
	
	# 根据类型设置默认约束
	_setup_default_constraints()

# ============================================
# 静态工厂方法
# ============================================

static func create_move_to(target_location: Vector2, target_room: String = "") -> Activity:
	var activity = Activity.new(ActivityType.MOVE_TO)
	activity.parameters = {
		"target_location": target_location,
		"target_room": target_room
	}
	activity.duration_expected = 0.5  # 移动通常很快
	return activity

static func create_normal_dialogue(target_agent: String, topic: String = "") -> Activity:
	var activity = Activity.new(ActivityType.NORMAL_DIALOGUE)
	activity.parameters = {
		"target_agent": target_agent,
		"topic": topic
	}
	activity.duration_expected = 10.0
	return activity

static func create_whisper(target_agent: String, content: String = "") -> Activity:
	var activity = Activity.new(ActivityType.WHISPER)
	activity.parameters = {
		"target_agent": target_agent,
		"content": content
	}
	activity.duration_expected = 5.0
	return activity

static func create_listen(target_teacher: String, focus: FocusLevel = FocusLevel.HIGH) -> Activity:
	var activity = Activity.new(ActivityType.LISTEN)
	activity.requires_focus = true
	activity.focus_level = focus
	activity.parameters = {
		"target_teacher": target_teacher
	}
	activity.duration_expected = 45.0  # 一节课
	activity._update_multipliers()
	return activity

static func create_qa_teacher(question: String = "", is_answer: bool = false, 
							focus: FocusLevel = FocusLevel.HIGH) -> Activity:
	var activity = Activity.new(ActivityType.QA_TEACHER)
	activity.requires_focus = true
	activity.focus_level = focus
	activity.parameters = {
		"question": question,
		"is_answer": is_answer
	}
	activity.duration_expected = 2.0
	activity._update_multipliers()
	return activity

static func create_self_study(subject: String, focus: FocusLevel = FocusLevel.HIGH) -> Activity:
	var activity = Activity.new(ActivityType.SELF_STUDY)
	activity.requires_focus = true
	activity.focus_level = focus
	var scenes: Array[String] = ["library", "study_room"]
	activity.allowed_scenes = scenes
	activity.parameters = {
		"subject": subject
	}
	activity.duration_expected = 60.0
	activity._update_multipliers()
	return activity

static func create_sports(sport_type: String, intensity: float = 0.5,
						  focus: FocusLevel = FocusLevel.HIGH) -> Activity:
	var activity = Activity.new(ActivityType.SPORTS)
	activity.requires_focus = true
	activity.focus_level = focus
	var scenes_sports: Array[String] = ["gym", "playground"]
	activity.allowed_scenes = scenes_sports
	activity.parameters = {
		"sport_type": sport_type,
		"intensity": intensity
	}
	activity.duration_expected = 40.0
	activity._update_multipliers()
	return activity

static func create_group_discussion(topic: String, members: Array[String],
									focus: FocusLevel = FocusLevel.HIGH) -> Activity:
	var activity = Activity.new(ActivityType.GROUP_DISCUSSION)
	activity.requires_focus = true
	activity.focus_level = focus
	var scenes_discussion: Array[String] = ["classroom", "discussion_room"]
	activity.allowed_scenes = scenes_discussion
	activity.parameters = {
		"topic": topic,
		"members": members
	}
	activity.duration_expected = 20.0
	activity._update_multipliers()
	return activity

# ============================================
# 对话系统工厂方法（新）
# ============================================

static func create_initiate_dialogue(range_type: int, initial_message: String = "", 
									 topic: String = "") -> Activity:
	"""
	创建发起对话活动
	
	参数:
		range_type: 对话范围 (0=WHISPER悄悄话, 1=NORMAL普通对话, 2=BROADCAST广播)
		initial_message: 初始消息内容（可选）
		topic: 讨论主题（可选）
	"""
	var activity = Activity.new(ActivityType.INITIATE_DIALOGUE)
	activity.parameters = {
		"range_type": range_type,
		"initial_message": initial_message,
		"topic": topic
	}
	activity.duration_expected = 5.0  # 发起对话很快
	activity.is_interruptible = false  # 发起对话不可中断
	return activity

static func create_join_dialogue(dialogue_id: String) -> Activity:
	"""
	创建加入对话活动
	
	参数:
		dialogue_id: 要加入的对话ID
	"""
	var activity = Activity.new(ActivityType.JOIN_DIALOGUE)
	activity.parameters = {
		"dialogue_id": dialogue_id
	}
	activity.duration_expected = 2.0
	activity.is_interruptible = false
	return activity

static func create_leave_dialogue(dialogue_id: String) -> Activity:
	"""
	创建离开对话活动
	
	参数:
		dialogue_id: 要离开的对话ID
	"""
	var activity = Activity.new(ActivityType.LEAVE_DIALOGUE)
	activity.parameters = {
		"dialogue_id": dialogue_id
	}
	activity.duration_expected = 1.0
	activity.is_interruptible = true
	return activity

# ============================================
# 专注度管理
# ============================================

func set_focus_level(level: FocusLevel) -> void:
	focus_level = level
	_update_multipliers()

func _update_multipliers() -> void:
	var ratio = float(focus_level) / 100.0
	effort_multiplier = ratio
	reward_multiplier = ratio

# 获取信息接收比例（用于对话类活动）
func get_information_reception_ratio() -> float:
	if not requires_focus:
		return 1.0
	return float(focus_level) / 100.0

# ============================================
# 约束检查
# ============================================

# 检查是否允许在指定场景执行
func is_allowed_in_scene(scene_name: String) -> bool:
	if allowed_scenes.is_empty():
		return true
	return scene_name.to_lower() in allowed_scenes

# 检查角色状态是否满足
func is_state_satisfied(agent_state: String) -> bool:
	if required_state == "":
		return true
	return agent_state == required_state

# 完整约束检查
func can_execute(scene_name: String, agent_state: String = "") -> Dictionary:
	var result = {
		"can_execute": true,
		"reason": ""
	}
	
	if not is_allowed_in_scene(scene_name):
		result.can_execute = false
		result.reason = "活动 '%s' 不允许在场景 '%s' 执行" % [activity_name, scene_name]
		return result
	
	if not is_state_satisfied(agent_state):
		result.can_execute = false
		result.reason = "活动 '%s' 需要状态 '%s'，当前状态 '%s'" % [activity_name, required_state, agent_state]
		return result
	
	return result

# ============================================
# 序列化
# ============================================

func to_dictionary() -> Dictionary:
	return {
		"activity_id": activity_id,
		"activity_type": activity_type,
		"activity_name": activity_name,
		"focus_level": focus_level,
		"requires_focus": requires_focus,
		"effort_multiplier": effort_multiplier,
		"reward_multiplier": reward_multiplier,
		"parameters": parameters,
		"duration_expected": duration_expected,
		"is_interruptible": is_interruptible
	}

static func from_dictionary(data: Dictionary) -> Activity:
	var type = data.get("activity_type", ActivityType.MOVE_TO)
	var activity = Activity.new(type, data.get("activity_id", ""))
	activity.activity_name = data.get("activity_name", activity.activity_name)
	activity.focus_level = data.get("focus_level", FocusLevel.HIGH)
	activity.requires_focus = data.get("requires_focus", false)
	activity.effort_multiplier = data.get("effort_multiplier", 1.0)
	activity.reward_multiplier = data.get("reward_multiplier", 1.0)
	activity.parameters = data.get("parameters", {})
	activity.duration_expected = data.get("duration_expected", 0.0)
	activity.is_interruptible = data.get("is_interruptible", true)
	return activity

# ============================================
# 辅助方法
# ============================================

func _generate_id() -> String:
	var timestamp = Time.get_unix_time_from_system()
	var random = randi() % 10000
	return "act_%d_%d" % [timestamp, random]

func _get_default_name(type: ActivityType) -> String:
	match type:
		ActivityType.MOVE_TO:
			return "移动"
		ActivityType.INITIATE_DIALOGUE:
			return "发起对话"
		ActivityType.JOIN_DIALOGUE:
			return "加入对话"
		ActivityType.LEAVE_DIALOGUE:
			return "离开对话"
		ActivityType.LISTEN:
			return "聆听"
		ActivityType.QA_TEACHER:
			return "课堂问答"
		ActivityType.SELF_STUDY:
			return "自习"
		ActivityType.SPORTS:
			return "体育活动"
		ActivityType.GROUP_DISCUSSION:
			return "小组讨论"
		ActivityType.NORMAL_DIALOGUE:
			return "普通对话(旧)"
		ActivityType.WHISPER:
			return "悄悄话(旧)"
		_:
			return "未知活动"

func _setup_default_constraints() -> void:
	match activity_type:
		ActivityType.INITIATE_DIALOGUE:
			is_interruptible = false
		ActivityType.JOIN_DIALOGUE:
			is_interruptible = false
		ActivityType.LEAVE_DIALOGUE:
			is_interruptible = true
		ActivityType.LISTEN:
			requires_focus = true
			var scenes_listen: Array[String] = ["classroom"]
			allowed_scenes = scenes_listen
			required_state = "in_class"
		ActivityType.QA_TEACHER:
			requires_focus = true
			var scenes_qa: Array[String] = ["classroom"]
			allowed_scenes = scenes_qa
			required_state = "in_class"
		ActivityType.SELF_STUDY:
			requires_focus = true
			var scenes_study: Array[String] = ["library", "study_room"]
			allowed_scenes = scenes_study
		ActivityType.SPORTS:
			requires_focus = true
			var scenes_sports_def: Array[String] = ["gym", "playground"]
			allowed_scenes = scenes_sports_def
		ActivityType.GROUP_DISCUSSION:
			requires_focus = true
			var scenes_discussion_def: Array[String] = ["classroom", "discussion_room"]
			allowed_scenes = scenes_discussion_def

# 获取活动类型字符串（用于显示）
func get_type_string() -> String:
	match activity_type:
		ActivityType.MOVE_TO:
			return "MOVE_TO"
		ActivityType.INITIATE_DIALOGUE:
			return "INITIATE_DIALOGUE"
		ActivityType.JOIN_DIALOGUE:
			return "JOIN_DIALOGUE"
		ActivityType.LEAVE_DIALOGUE:
			return "LEAVE_DIALOGUE"
		ActivityType.LISTEN:
			return "LISTEN"
		ActivityType.QA_TEACHER:
			return "QA_TEACHER"
		ActivityType.SELF_STUDY:
			return "SELF_STUDY"
		ActivityType.SPORTS:
			return "SPORTS"
		ActivityType.GROUP_DISCUSSION:
			return "GROUP_DISCUSSION"
		ActivityType.NORMAL_DIALOGUE:
			return "NORMAL_DIALOGUE"
		ActivityType.WHISPER:
			return "WHISPER"
		_:
			return "UNKNOWN"

# 是否为对话类活动（影响信息接收）
func is_dialogue_activity() -> bool:
	return activity_type in [ActivityType.INITIATE_DIALOGUE, ActivityType.JOIN_DIALOGUE,
							 ActivityType.LEAVE_DIALOGUE, ActivityType.GROUP_DISCUSSION]

# 是否为专注度活动
func is_focus_activity() -> bool:
	return requires_focus

func _to_string() -> String:
	return "Activity[%s: %s, focus=%d%%]" % [activity_id, activity_name, focus_level]
