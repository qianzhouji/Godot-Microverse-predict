extends Node

# Logger - 游戏日志系统
# 按照游戏时间输出六种日志：
# 1. activity_log.txt - 所有角色的移动和活动
# 2. monologue_log.txt - 所有角色的任务内心独白
# 3. dialogue_log.txt - 所有角色之间的对话
# 4. reflection_log.txt - 每日反思日志（包含PHQ-9评估和认知参数变化）
# 5. cognitive_params_log.txt - 认知参数变化日志（记录所有角色的认知参数演变）
# 6. coordination_log.txt - 协调日志（记录ActivityCoordinator接收的请求和下发的命令）

# 日志目录改为桌面，方便查看
const LOG_DIR = "/Users/yuke/Desktop/Microverse_Logs"
const ACTIVITY_LOG = "activity_log.txt"
const MONOLOGUE_LOG = "monologue_log.txt"
const DIALOGUE_LOG = "dialogue_log.txt"
const REFLECTION_LOG = "reflection_log.txt"
const COGNITIVE_PARAMS_LOG = "cognitive_params_log.txt"
const COORDINATION_LOG = "coordination_log.txt"

func _ready():
	# 确保日志目录存在（使用桌面路径）
	var dir = DirAccess.open("/Users/yuke/Desktop")
	if not dir:
		# 如果桌面路径无法访问，回退到用户目录
		dir = DirAccess.open("user://")
	if not dir.dir_exists("Microverse_Logs"):
		dir.make_dir("Microverse_Logs")
	
	# 创建或清空日志文件
	_create_log_file(ACTIVITY_LOG)
	_create_log_file(MONOLOGUE_LOG)
	_create_log_file(DIALOGUE_LOG)
	_create_log_file(REFLECTION_LOG)
	_create_log_file(COGNITIVE_PARAMS_LOG)
	_create_log_file(COORDINATION_LOG)
	
	print("[Logger] 日志系统初始化完成")

func _create_log_file(filename: String):
	"""创建或清空日志文件"""
	var file = FileAccess.open(LOG_DIR + "/" + filename, FileAccess.WRITE)
	if file:
		var game_timestamp = _get_game_timestamp()
		var real_timestamp = _get_real_timestamp()
		file.store_line("=== 日志开始 ===")
		file.store_line("游戏时间: " + game_timestamp)
		file.store_line("现实时间: " + real_timestamp)
		file.store_line("=" .repeat(40))
		file.close()

func _get_game_timestamp() -> String:
	"""获取游戏内时间戳 (V2: 使用TimingSystem)"""
	# V2: 使用TimingSystem获取时间
	if TimingSystem.instance:
		var day = TimingSystem.instance.current_day
		var game_time = TimingSystem.instance.current_game_time
		var hour = int(game_time / 60)
		var minute = int(fmod(game_time, 60))
		return "第%d天 %02d:%02d" % [day, hour, minute]
	
	# 回退到DayNightSystem (V1兼容)
	var dns = get_node_or_null("/root/DayNightSystem")
	if dns:
		var day = dns.current_day
		var weekday = dns.current_weekday
		var hour = int(dns.current_hour)
		var minute = int((dns.current_hour - hour) * 60)
		var weekday_names = ["", "周一", "周二", "周三", "周四", "周五", "周六", "周日"]
		return "第%d天 %s %02d:%02d" % [day, weekday_names[weekday], hour, minute]
	
	return "未知时间"

func _get_real_timestamp() -> String:
	"""获取现实时间戳"""
	var datetime = Time.get_datetime_dict_from_system()
	return "%04d-%02d-%02d %02d:%02d:%02d" % [
		datetime.year, datetime.month, datetime.day,
		datetime.hour, datetime.minute, datetime.second
	]

func _write_log(filename: String, content: String):
	"""写入日志文件（追加模式，带现实时间戳）"""
	var file = FileAccess.open(LOG_DIR + "/" + filename, FileAccess.READ_WRITE)
	if file:
		file.seek_end()
		var real_time = _get_real_timestamp()
		var log_line = "[%s] %s" % [real_time, content]
		file.store_line(log_line)
		file.close()

# ========== 活动日志 ==========

func log_activity(character_name: String, activity: String, location: String = ""):
	"""记录角色活动
	
	参数:
	- character_name: 角色名
	- activity: 活动描述（如"移动到教室"、"开始上课"、"完成作业"）
	- location: 当前位置（可选）
	"""
	var timestamp = _get_game_timestamp()
	var location_str = " [%s]" % location if location else ""
	var log_line = "[%s] %s%s: %s" % [timestamp, character_name, location_str, activity]
	_write_log(ACTIVITY_LOG, log_line)
	print("[ActivityLog] " + log_line)

func log_movement(character_name: String, from_location: String, to_location: String):
	"""记录角色移动"""
	var timestamp = _get_game_timestamp()
	var log_line = "[%s] %s: 从 %s 移动到 %s" % [timestamp, character_name, from_location, to_location]
	_write_log(ACTIVITY_LOG, log_line)
	print("[ActivityLog] " + log_line)

# ========== 内心独白日志 ==========

func log_monologue(character_name: String, task_description: String, monologue: String):
	"""记录角色对任务的内心独白
	
	参数:
	- character_name: 角色名
	- task_description: 任务描述
	- monologue: 内心独白内容
	"""
	var timestamp = _get_game_timestamp()
	var log_line = "[%s] %s 对任务'%s'的内心独白:\n    %s" % [timestamp, character_name, task_description, monologue]
	_write_log(MONOLOGUE_LOG, log_line)
	print("[MonologueLog] " + character_name + " 的内心独白已记录")

func log_task_evaluation(character_name: String, task_description: String, priority: int, reason: String):
	"""记录角色对任务的评估"""
	var timestamp = _get_game_timestamp()
	var log_line = "[%s] %s 评估任务'%s':\n    渴望程度: %d/10\n    原因: %s" % [timestamp, character_name, task_description, priority, reason]
	_write_log(MONOLOGUE_LOG, log_line)

# ========== 对话日志 ==========

func log_dialogue(speaker: String, listener: String, message: String, location: String = ""):
	"""记录角色对话
	
	参数:
	- speaker: 说话者
	- listener: 倾听者
	- message: 对话内容
	- location: 对话地点（可选）
	"""
	var timestamp = _get_game_timestamp()
	var location_str = " [%s]" % location if location else ""
	var log_line = "[%s]%s %s -> %s: %s" % [timestamp, location_str, speaker, listener, message]
	_write_log(DIALOGUE_LOG, log_line)
	print("[DialogueLog] " + speaker + " -> " + listener)

func log_conversation_start(character1: String, character2: String, location: String = ""):
	"""记录对话开始"""
	var timestamp = _get_game_timestamp()
	var location_str = " [%s]" % location if location else ""
	var log_line = "[%s]%s === %s 与 %s 开始对话 ===" % [timestamp, location_str, character1, character2]
	_write_log(DIALOGUE_LOG, log_line)
	_write_log(DIALOGUE_LOG, "")

func log_conversation_end(character1: String, character2: String):
	"""记录对话结束"""
	var timestamp = _get_game_timestamp()
	var log_line = "[%s] === %s 与 %s 结束对话 ===\n" % [timestamp, character1, character2]
	_write_log(DIALOGUE_LOG, log_line)
	_write_log(DIALOGUE_LOG, "")

# ========== 每日反思日志 ==========

func log_daily_reflection(character_name: String, reflection_data: Dictionary):
	"""记录每日反思日志
	
	参数:
	- character_name: 角色名
	- reflection_data: 反思结果字典，包含:
	  - reflection_report: 反思报告
	  - adjustments: 认知参数调整列表
	  - phq9_assessment: PHQ-9评估结果
	"""
	var game_timestamp = _get_game_timestamp()
	var real_timestamp = _get_real_timestamp()
	
	# 写入分隔线和新的一天标记
	_write_log(REFLECTION_LOG, "")
	_write_log(REFLECTION_LOG, "=" .repeat(60))
	_write_log(REFLECTION_LOG, "【每日反思】%s | 游戏时间: %s" % [character_name, game_timestamp])
	
	# 反思报告
	var report = reflection_data.get("reflection_report", {})
	if not report.is_empty():
		_write_log(REFLECTION_LOG, "【情绪主题】%s" % report.get("emotional_theme", "未记录"))
		
		var key_events = report.get("key_events", [])
		if key_events.size() > 0:
			_write_log(REFLECTION_LOG, "【关键事件】")
			for event in key_events:
				var event_desc = event.get("event", "未知事件")
				var impact = event.get("impact", "中")
				var effect = event.get("psychological_effect", "")
				_write_log(REFLECTION_LOG, "  - %s [影响:%s] %s" % [event_desc, impact, effect])
		
		var cognitive_changes = report.get("cognitive_changes", {})
		if not cognitive_changes.is_empty():
			_write_log(REFLECTION_LOG, "【认知变化】")
			_write_log(REFLECTION_LOG, "  - 环境预期: %s" % cognitive_changes.get("environment_expectation", "未记录"))
			_write_log(REFLECTION_LOG, "  - 努力态度: %s" % cognitive_changes.get("effort_attitude", "未记录"))
			_write_log(REFLECTION_LOG, "  - 奖赏敏感度: %s" % cognitive_changes.get("reward_sensitivity", "未记录"))
			_write_log(REFLECTION_LOG, "  - 时间压力: %s" % cognitive_changes.get("time_pressure", "未记录"))
	
	# PHQ-9评估
	var phq9 = reflection_data.get("phq9_assessment", {})
	if not phq9.is_empty():
		var total_score = phq9.get("total_score", 0)
		var severity = phq9.get("severity_level", "未评估")
		_write_log(REFLECTION_LOG, "【PHQ-9评估】总分: %d | 等级: %s" % [total_score, severity])
		
		var scores = phq9.get("phq9_scores", [])
		if scores.size() > 0:
			_write_log(REFLECTION_LOG, "【PHQ-9分项评分】")
			for item_score in scores:
				var item_name = item_score.get("item", "未知")
				var score = item_score.get("score", 0)
				var reason = item_score.get("reason", "")
				_write_log(REFLECTION_LOG, "  - %s: %d分 | %s" % [item_name, score, reason])
	
	# 认知参数调整
	var adjustments = reflection_data.get("adjustments", [])
	if adjustments.size() > 0:
		_write_log(REFLECTION_LOG, "【认知参数调整】")
		for adj in adjustments:
			var param = adj.get("parameter", "未知")
			var direction = adj.get("direction", "→")
			var magnitude = adj.get("magnitude", 0.0)
			var reason = adj.get("reason", "")
			_write_log(REFLECTION_LOG, "  - %s %s %.1f%% | %s" % [param, direction, magnitude * 100, reason])
	
	_write_log(REFLECTION_LOG, "=" .repeat(60))
	print("[ReflectionLog] %s 的每日反思已记录" % character_name)

# ========== 认知参数日志 ==========

func log_cognitive_params(character_name: String, params: Dictionary, reason: String = ""):
	"""记录认知参数变化
	
	参数:
	- character_name: 角色名
	- params: 认知参数字典，包含:
	  - daily_depression_level: 当日抑郁水平
	  - p_base: 离开阈值
	  - eta_s: 初始奖赏感知权重
	  - eta_a: 衰减率感知权重
	  - beta_effort: 努力敏感性
	- reason: 变化原因（可选）
	"""
	var game_timestamp = _get_game_timestamp()
	
	var depression = params.get("daily_depression_level", 0.5)
	var p_base = params.get("p_base", 0.5)
	var eta_s = params.get("eta_s", 0.5)
	var eta_a = params.get("eta_a", 0.5)
	var beta_effort = params.get("beta_effort", 0.5)
	
	var log_line = "%s | 抑郁:%.0f%% | p_base:%.0f%% | η_s:%.0f%% | η_a:%.0f%% | β_effort:%.0f%%" % [
		character_name,
		depression * 100,
		p_base * 100,
		eta_s * 100,
		eta_a * 100,
		beta_effort * 100
	]
	
	if not reason.is_empty():
		log_line += " | 原因: %s" % reason
	
	_write_log(COGNITIVE_PARAMS_LOG, log_line)

func log_cognitive_params_batch(characters_params: Dictionary):
	"""批量记录多个角色的认知参数
	
	参数:
	- characters_params: 字典，键为角色名，值为认知参数字典
	"""
	var game_timestamp = _get_game_timestamp()
	_write_log(COGNITIVE_PARAMS_LOG, "")
	_write_log(COGNITIVE_PARAMS_LOG, "--- 批量记录 [%s] ---" % game_timestamp)
	
	for character_name in characters_params:
		var params = characters_params[character_name]
		log_cognitive_params(character_name, params)
	
	_write_log(COGNITIVE_PARAMS_LOG, "--- 结束 ---")
