extends Node

# Logger - 游戏日志系统
# 按照游戏时间输出七种日志：
# 1. activity_log.txt - 所有角色的移动和活动
# 2. monologue_log.txt - 所有角色的任务内心独白
# 3. dialogue_log.txt - 所有角色之间的对话
# 4. reflection_log.txt - 每日反思日志（包含PHQ-9评估和认知参数变化）
# 5. cognitive_params_log.txt - 认知参数变化日志（记录所有角色的认知参数演变）
# 6. coordination_log.txt - 协调日志（记录ActivityCoordinator接收的请求和下发的命令）
# 7. complete_output_log.txt - 完整输出日志（记录所有系统输出、AI响应、决策过程）

# 日志根目录改为桌面，方便查看
const LOG_BASE_DIR = "/Users/yuke/Desktop/Microverse_Logs"

# 当前运行会话的日志目录路径
var current_session_dir: String

func _ready():
	# 生成带时间戳的会话目录名
	var session_timestamp = _get_session_timestamp()
	current_session_dir = LOG_BASE_DIR + "/" + session_timestamp
	
	# 创建会话目录
	var dir = DirAccess.open("/Users/yuke/Desktop")
	if not dir:
		# 如果桌面路径无法访问，回退到用户目录
		dir = DirAccess.open("user://")
		current_session_dir = "user://Microverse_Logs/" + session_timestamp
	
	# 确保基础目录存在
	if not dir.dir_exists("Microverse_Logs"):
		dir.make_dir("Microverse_Logs")
	
	# 创建本次会话的子目录
	var log_dir = DirAccess.open(LOG_BASE_DIR)
	if log_dir:
		log_dir.make_dir(session_timestamp)
	
	# 创建新的日志文件（使用固定文件名，放在时间戳目录下）
	_create_log_file("activity_log.txt")
	_create_log_file("monologue_log.txt")
	_create_log_file("dialogue_log.txt")
	_create_log_file("reflection_log.txt")
	_create_log_file("cognitive_params_log.txt")
	_create_log_file("coordination_log.txt")
	_create_log_file("complete_output_log.txt")
	
	print("[Logger] 日志系统初始化完成，会话目录: %s" % current_session_dir)

func _get_session_timestamp() -> String:
	"""获取会话时间戳（用于文件名）"""
	var datetime = Time.get_datetime_dict_from_system()
	return "%04d%02d%02d_%02d%02d%02d" % [
		datetime.year, datetime.month, datetime.day,
		datetime.hour, datetime.minute, datetime.second
	]

func _create_log_file(filename: String):
	"""创建或清空日志文件"""
	var file = FileAccess.open(current_session_dir + "/" + filename, FileAccess.WRITE)
	if file:
		var game_timestamp = _get_game_timestamp()
		var real_timestamp = _get_real_timestamp()
		file.store_line("=== 日志开始 ===")
		file.store_line("游戏时间: " + game_timestamp)
		file.store_line("现实时间: " + real_timestamp)
		file.store_line("=" .repeat(40))
		file.close()

func _get_game_timestamp() -> String:
	"""获取游戏内时间戳 (使用TimeUtils统一获取)"""
	# 使用TimeUtils统一获取游戏时间
	var day = TimeUtils.get_game_day()
	var game_time = TimeUtils.get_game_time_minutes()
	return TimeUtils.format_time_with_day(game_time, day)

func _get_real_timestamp() -> String:
	"""获取现实时间戳"""
	var datetime = Time.get_datetime_dict_from_system()
	return "%04d-%02d-%02d %02d:%02d:%02d" % [
		datetime.year, datetime.month, datetime.day,
		datetime.hour, datetime.minute, datetime.second
	]

func _write_log(filename: String, content: String):
	"""写入日志文件（追加模式，带现实时间戳）"""
	var file = FileAccess.open(current_session_dir + "/" + filename, FileAccess.READ_WRITE)
	if file:
		file.seek_end()
		var real_time = _get_real_timestamp()
		var log_line = "[%s] %s" % [real_time, content]
		file.store_line(log_line)
		file.close()

func _write_activity_log(content: String):
	"""写入活动日志"""
	_write_log("activity_log.txt", content)

func _write_monologue_log(content: String):
	"""写入内心独白日志"""
	_write_log("monologue_log.txt", content)

func _write_dialogue_log(content: String):
	"""写入对话日志"""
	_write_log("dialogue_log.txt", content)

func _write_reflection_log(content: String):
	"""写入反思日志"""
	_write_log("reflection_log.txt", content)

func _write_cognitive_params_log(content: String):
	"""写入认知参数日志"""
	_write_log("cognitive_params_log.txt", content)

func _write_coordination_log(content: String):
	"""写入协调日志"""
	_write_log("coordination_log.txt", content)

func _write_complete_output_log(content: String):
	"""写入完整输出日志"""
	_write_log("complete_output_log.txt", content)

# ========== 完整输出日志 ==========

func log_complete_output(source: String, output_type: String, content: String, agent_name: String = ""):
	"""记录完整输出日志
	
	参数:
	- source: 来源（如"AIAgent", "ActivityCoordinator", "LLM", "System"）
	- output_type: 输出类型（如"Decision", "Response", "Prompt", "Error", "Debug"）
	- content: 输出内容
	- agent_name: 角色名（可选，用于区分不同Agent的输出）
	"""
	var game_timestamp = _get_game_timestamp()
	var agent_str = "[%s] " % agent_name if agent_name else ""
	var log_line = "[%s] %s%s | %s | %s" % [game_timestamp, agent_str, source, output_type, content]
	_write_complete_output_log(log_line)

func log_llm_prompt(agent_name: String, prompt: String, model: String = ""):
	"""记录LLM Prompt"""
	var model_str = " [%s]" % model if model else ""
	log_complete_output("LLM", "Prompt" + model_str, "\n" + prompt, agent_name)

func log_llm_response(agent_name: String, response: String, model: String = ""):
	"""记录LLM响应"""
	var model_str = " [%s]" % model if model else ""
	log_complete_output("LLM", "Response" + model_str, "\n" + response, agent_name)

func log_agent_decision(agent_name: String, decision: String, context: Dictionary = {}):
	"""记录Agent决策过程
	
	参数:
	- agent_name: 角色名
	- decision: 决策内容
	- context: 决策上下文（如当前位置、感知参数、心情等）
	"""
	var context_str = ""
	if not context.is_empty():
		context_str = " | 上下文: " + str(context)
	log_complete_output("AIAgent", "Decision", decision + context_str, agent_name)

func log_system_event(event_type: String, details: String):
	"""记录系统事件"""
	log_complete_output("System", event_type, details)

func log_error(source: String, error_message: String, agent_name: String = ""):
	"""记录错误信息"""
	log_complete_output(source, "Error", error_message, agent_name)

func log_debug(source: String, debug_info: String, agent_name: String = ""):
	"""记录调试信息"""
	log_complete_output(source, "Debug", debug_info, agent_name)

func log_coordination_input(agent_decisions: Dictionary):
	"""记录协调器输入（所有Agent的决策）"""
	var game_timestamp = _get_game_timestamp()
	var content = "\n=== 协调器输入 [%s] ===\n" % game_timestamp
	for agent_name in agent_decisions:
		content += "[%s] %s\n" % [agent_name, agent_decisions[agent_name]]
	content += "=== 结束 ==="
	_write_complete_output_log(content)

func log_coordination_output(assignments: Dictionary):
	"""记录协调器输出（分配的活动序列）"""
	var game_timestamp = _get_game_timestamp()
	var content = "\n=== 协调器输出 [%s] ===\n" % game_timestamp
	for agent_name in assignments:
		content += "[%s] %s\n" % [agent_name, str(assignments[agent_name])]
	content += "=== 结束 ==="
	_write_complete_output_log(content)

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
	_write_activity_log(log_line)
	print("[ActivityLog] " + log_line)

func log_movement(character_name: String, from_location: String, to_location: String):
	"""记录角色移动"""
	var timestamp = _get_game_timestamp()
	var log_line = "[%s] %s: 从 %s 移动到 %s" % [timestamp, character_name, from_location, to_location]
	_write_activity_log(log_line)
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
	_write_monologue_log(log_line)
	print("[MonologueLog] " + character_name + " 的内心独白已记录")

func log_task_evaluation(character_name: String, task_description: String, priority: int, reason: String):
	"""记录角色对任务的评估"""
	var timestamp = _get_game_timestamp()
	var log_line = "[%s] %s 评估任务'%s':\n    渴望程度: %d/10\n    原因: %s" % [timestamp, character_name, task_description, priority, reason]
	_write_monologue_log(log_line)

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
	_write_dialogue_log(log_line)
	print("[DialogueLog] " + speaker + " -> " + listener)

func log_conversation_start(character1: String, character2: String, location: String = ""):
	"""记录对话开始"""
	var timestamp = _get_game_timestamp()
	var location_str = " [%s]" % location if location else ""
	var log_line = "[%s]%s === %s 与 %s 开始对话 ===" % [timestamp, location_str, character1, character2]
	_write_dialogue_log(log_line)
	_write_dialogue_log("")

func log_conversation_end(character1: String, character2: String):
	"""记录对话结束"""
	var timestamp = _get_game_timestamp()
	var log_line = "[%s] === %s 与 %s 结束对话 ===\n" % [timestamp, character1, character2]
	_write_dialogue_log(log_line)
	_write_dialogue_log("")

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
	_write_reflection_log("")
	_write_reflection_log("=" .repeat(60))
	_write_reflection_log("【每日反思】%s | 游戏时间: %s" % [character_name, game_timestamp])
	
	# 反思报告
	var report = reflection_data.get("reflection_report", {})
	if not report.is_empty():
		_write_reflection_log("【情绪主题】%s" % report.get("emotional_theme", "未记录"))
		
		var key_events = report.get("key_events", [])
		if key_events.size() > 0:
			_write_reflection_log("【关键事件】")
			for event in key_events:
				var event_desc = event.get("event", "未知事件")
				var impact = event.get("impact", "中")
				var effect = event.get("psychological_effect", "")
				_write_reflection_log("  - %s [影响:%s] %s" % [event_desc, impact, effect])
		
		var cognitive_changes = report.get("cognitive_changes", {})
		if not cognitive_changes.is_empty():
			_write_reflection_log("【认知变化】")
			_write_reflection_log("  - 环境预期: %s" % cognitive_changes.get("environment_expectation", "未记录"))
			_write_reflection_log("  - 努力态度: %s" % cognitive_changes.get("effort_attitude", "未记录"))
			_write_reflection_log("  - 奖赏敏感度: %s" % cognitive_changes.get("reward_sensitivity", "未记录"))
			_write_reflection_log("  - 时间压力: %s" % cognitive_changes.get("time_pressure", "未记录"))
	
	# PHQ-9评估
	var phq9 = reflection_data.get("phq9_assessment", {})
	if not phq9.is_empty():
		var total_score = phq9.get("total_score", 0)
		var severity = phq9.get("severity_level", "未评估")
		_write_reflection_log("【PHQ-9评估】总分: %d | 等级: %s" % [total_score, severity])
		
		var scores = phq9.get("phq9_scores", [])
		if scores.size() > 0:
			_write_reflection_log("【PHQ-9分项评分】")
			for item_score in scores:
				var item_name = item_score.get("item", "未知")
				var score = item_score.get("score", 0)
				var reason = item_score.get("reason", "")
				_write_reflection_log("  - %s: %d分 | %s" % [item_name, score, reason])
	
	# 认知参数调整
	var adjustments = reflection_data.get("adjustments", [])
	if adjustments.size() > 0:
		_write_reflection_log("【认知参数调整】")
		for adj in adjustments:
			var param = adj.get("parameter", "未知")
			var direction = adj.get("direction", "→")
			var magnitude = adj.get("magnitude", 0.0)
			var reason = adj.get("reason", "")
			_write_reflection_log("  - %s %s %.1f%% | %s" % [param, direction, magnitude * 100, reason])
	
	_write_reflection_log("=" .repeat(60))
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
	
	_write_cognitive_params_log(log_line)

func log_cognitive_params_batch(characters_params: Dictionary):
	"""批量记录多个角色的认知参数
	
	参数:
	- characters_params: 字典，键为角色名，值为认知参数字典
	"""
	var game_timestamp = _get_game_timestamp()
	_write_cognitive_params_log("")
	_write_cognitive_params_log("--- 批量记录 [%s] ---" % game_timestamp)
	
	for character_name in characters_params:
		var params = characters_params[character_name]
		log_cognitive_params(character_name, params)
	
	_write_cognitive_params_log("--- 结束 ---")
