extends Node

# Logger - 游戏日志系统
# 按照游戏时间输出三种日志：
# 1. activity_log.txt - 所有角色的移动和活动
# 2. monologue_log.txt - 所有角色的任务内心独白
# 3. dialogue_log.txt - 所有角色之间的对话

# 日志目录改为桌面，方便查看
const LOG_DIR = "/Users/yuke/Desktop/Microverse_Logs"
const ACTIVITY_LOG = "activity_log.txt"
const MONOLOGUE_LOG = "monologue_log.txt"
const DIALOGUE_LOG = "dialogue_log.txt"

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
	
	print("[Logger] 日志系统初始化完成")

func _create_log_file(filename: String):
	"""创建或清空日志文件"""
	var file = FileAccess.open(LOG_DIR + "/" + filename, FileAccess.WRITE)
	if file:
		var timestamp = _get_game_timestamp()
		file.store_line("=== 日志开始: " + timestamp + " ===")
		file.close()

func _get_game_timestamp() -> String:
	"""获取游戏内时间戳"""
	var dns = get_node_or_null("/root/DayNightSystem")
	if dns:
		var day = dns.current_day
		var weekday = dns.current_weekday
		var hour = int(dns.current_hour)
		var minute = int((dns.current_hour - hour) * 60)
		var weekday_names = ["", "周一", "周二", "周三", "周四", "周五", "周六", "周日"]
		return "第%d天 %s %02d:%02d" % [day, weekday_names[weekday], hour, minute]
	return "未知时间"

func _write_log(filename: String, content: String):
	"""写入日志文件"""
	var file = FileAccess.open(LOG_DIR + "/" + filename, FileAccess.READ_WRITE)
	if file:
		file.seek_end()
		file.store_line(content)
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
