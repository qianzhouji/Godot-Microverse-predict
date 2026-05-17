class_name ActivityCoordinator
extends Node

# 预加载AIAgent以避免循环依赖问题
const AIAgentClass = preload("res://script/ai/AIAgent.gd")

# ============================================
# ActivityCoordinator - 活动协调器
# ============================================
# 中央协调系统核心组件
# 1. 收集所有Agent的自然语言决策
# 2. 调用LLM进行活动分配
# 3. 解析并下发活动序列给各Agent
# ============================================

# 单例
static var instance: ActivityCoordinator

# LLM配置
var llm_api_url: String = "http://localhost:11434/api/generate"
var llm_model: String = "qwen2.5:1.5b"
var llm_temperature: float = 0.3  # 协调器需要更确定性的输出
var llm_max_tokens: int = 2000

# 协调状态
var is_coordinating: bool = false
var pending_decisions: Dictionary = {}  # {agent_id: decision_string}
var coordination_results: Dictionary = {}  # {agent_id: Array[Activity]}

# 对话管理器引用（使用Node类型避免循环依赖）
var dialogue_manager: Node = null

# 信号
signal coordination_started(agent_count: int)
signal coordination_completed(results: Dictionary)
signal coordination_failed(reason: String)
signal activity_assigned(agent_id: String, activities: Array)

# Prompt模板
var coordinator_prompt_template: String = ""

func _ready():
	instance = self
	print("[ActivityCoordinator] 活动协调器初始化完成")
	_load_prompt_template()

	# 获取对话管理器引用（延迟获取避免加载顺序问题）
	await get_tree().process_frame
	dialogue_manager = get_node_or_null("/root/DialogueManager")
	if dialogue_manager:
		print("[ActivityCoordinator] 对话管理器已连接")
	else:
		push_warning("[ActivityCoordinator] 对话管理器未找到")

func _load_prompt_template() -> void:
	"""加载协调器Prompt模板"""
	# 从文件加载或直接使用内置模板
	var prompt_path = "res://prompts/coordinator_prompt.md"
	if FileAccess.file_exists(prompt_path):
		var file = FileAccess.open(prompt_path, FileAccess.READ)
		coordinator_prompt_template = file.get_as_text()
		file.close()
		print("[ActivityCoordinator] 已加载Prompt模板")
	else:
		# 使用内置简化模板
		coordinator_prompt_template = _get_builtin_prompt()
		print("[ActivityCoordinator] 使用内置Prompt模板")

# ============================================
# 协调日志记录
# ============================================

func _log_coordination(event_type: String, data: Dictionary) -> void:
	"""记录协调日志到文件"""
	var logger = get_node_or_null("/root/Logger")
	if logger and logger.has_method("_write_log"):
		var timestamp = _get_real_timestamp()
		var log_line = "[%s] [%s] %s" % [timestamp, event_type, JSON.stringify(data)]
		logger._write_log("coordination_log.txt", log_line)

func _get_real_timestamp() -> String:
	"""获取现实时间戳"""
	var datetime = Time.get_datetime_dict_from_system()
	return "%04d-%02d-%02d %02d:%02d:%02d" % [
		datetime.year, datetime.month, datetime.day,
		datetime.hour, datetime.minute, datetime.second
	]

# ============================================
# 核心协调接口
# ============================================

func submit_decision(agent_id: String, decision: String) -> void:
	"""
	提交Agent决策到协调器

	参数:
		agent_id: Agent唯一标识
		decision: 自然语言决策描述
	"""
	pending_decisions[agent_id] = decision
	print("[ActivityCoordinator] 收到 %s 的决策: %s" % [agent_id, decision])

	# 记录接收到的决策
	_log_coordination("RECEIVE_DECISION", {
		"agent_id": agent_id,
		"decision": decision,
		"pending_count": pending_decisions.size()
	})

func clear_decisions() -> void:
	"""清空所有待处理决策"""
	pending_decisions.clear()
	coordination_results.clear()

func get_pending_count() -> int:
	"""获取待协调的决策数量"""
	return pending_decisions.size()

# ============================================
# 协调执行
# ============================================

func execute_coordination(game_context: Dictionary = {}) -> Dictionary:
	"""
	执行协调 - 调用LLM分配活动

	参数:
		game_context: 游戏上下文 {current_time, current_location, period}

	返回:
		协调结果字典
	"""
	print("[ActivityCoordinator] execute_coordination被调用")
	print("[ActivityCoordinator] pending_decisions数量: %d" % pending_decisions.size())
	print("[ActivityCoordinator] pending_decisions内容: %s" % str(pending_decisions.keys()))

	if pending_decisions.is_empty():
		print("[ActivityCoordinator] 没有待协调的决策")
		return {}

	if is_coordinating:
		print("[ActivityCoordinator] 协调正在进行中")
		return {}

	is_coordinating = true
	coordination_started.emit(pending_decisions.size())

	print("[ActivityCoordinator] 调用LLM为 %d 个Agent分配活动..." % pending_decisions.size())

	# 打印所有Agent的决策内容
	print("[ActivityCoordinator] ===== 所有Agent决策内容 =====")
	for agent_id in pending_decisions.keys():
		var decision = pending_decisions[agent_id]
		var display_decision = decision
		if display_decision.length() > 200:
			display_decision = display_decision.substr(0, 200) + "..."
		print("[ActivityCoordinator]   %s: %s" % [agent_id, display_decision.replace("\n", " ")])
	print("[ActivityCoordinator] ===== 决策内容结束 =====")

	# 构建输入数据
	var input_data = _build_coordination_input(game_context)

	# 构建Prompt
	var prompt = _build_coordination_prompt(input_data)

	# 记录协调输入
	_log_coordination("COORDINATION_INPUT", {
		"game_context": game_context,
		"agent_count": pending_decisions.size(),
		"agents": input_data.get("agents", [])
	})

	# 调用LLM
	var response = await _call_llm(prompt)

	# 记录LLM原始响应
	_log_coordination("LLM_RESPONSE", {
		"response_length": response.length(),
		"response": response
	})

	if response.is_empty():
		coordination_failed.emit("LLM调用失败")
		is_coordinating = false
		return {}

	# 打印完整LLM响应
	print("[ActivityCoordinator] ===== LLM完整响应 =====")
	if response.length() > 500:
		print("[ActivityCoordinator] 响应前500字符:\n%s" % response.substr(0, 500))
		print("[ActivityCoordinator] ... (截断)")
	else:
		print("[ActivityCoordinator] 完整响应:\n%s" % response)
	print("[ActivityCoordinator] ===== 响应结束 =====")

	# 解析响应
	var results = _parse_coordination_response(response)

	# 打印协调结果调试信息
	print("[ActivityCoordinator] ===== 协调结果摘要 =====")
	print("[ActivityCoordinator] 共 %d 个Agent分配结果" % results.size())
	for agent_id in results.keys():
		var activities = results[agent_id]
		print("[ActivityCoordinator]   %s: %d 个活动" % [agent_id, activities.size()])
		for i in range(activities.size()):
			var act = activities[i]
			print("[ActivityCoordinator]     [%d] %s (类型:%s)" % [i+1, act.activity_name, str(act.activity_type)])
	print("[ActivityCoordinator] ===== 协调结果结束 =====")

	# 下发活动给各Agent
	_distribute_activities(results)

	coordination_results = results
	coordination_completed.emit(results)

	is_coordinating = false
	pending_decisions.clear()

	return results

# ============================================
# 调试辅助：直接分配对话活动
# ============================================
func _assign_dialogue_activities_directly() -> Dictionary:
	"""
	调试辅助：直接为所有Agent分配对话活动

	策略：
	1. 将所有Agent移动到同一区域（食堂中心）
	2. 分配INITIATE_DIALOGUE/JOIN_DIALOGUE活动
	"""
	var results = {}

	# 获取所有Agent ID
	var agent_ids = pending_decisions.keys()
	if agent_ids.size() == 0:
		return results

	# 选择一个中心位置（食堂中心）
	var center_position = Vector2(896, 147)

	# 为每个Agent分配活动
	for i in range(agent_ids.size()):
		var agent_id = agent_ids[i]
		var activities: Array[Activity] = []

		# 计算该Agent的目标位置（围绕中心点分布）
		var angle = (2.0 * PI * i) / agent_ids.size()
		var radius = 80.0
		var target_pos = center_position + Vector2(cos(angle) * radius, sin(angle) * radius)

		# Step 1: 移动到集合点
		var move_activity = Activity.create_move_to(target_pos, "食堂")
		move_activity.activity_id = "%s_move_%d" % [agent_id, Time.get_unix_time_from_system()]
		activities.append(move_activity)

		# Step 2: 开始普通对话（NORMAL范围）
		var dialogue_activity = Activity.create_initiate_dialogue(1, "大家好，最近怎么样？", "日常闲聊")  # 1 = NORMAL
		dialogue_activity.activity_id = "%s_dialogue_%d" % [agent_id, Time.get_unix_time_from_system()]
		activities.append(dialogue_activity)

		results[agent_id] = activities
		print("[ActivityCoordinator] 【直接分配】%s: MOVE_TO(%.0f,%.0f) -> NORMAL_DIALOGUE" % [agent_id, target_pos.x, target_pos.y])

	return results

# ============================================
# 输入构建
# ============================================

func _build_coordination_input(game_context: Dictionary) -> Dictionary:
	"""构建协调输入数据"""
	var input = {
		"game_context": game_context,
		"agents": [],
		"available_activities": _get_available_activities(),
		"scene_constraints": _get_scene_constraints()
	}

	# 构建Agent信息
	for agent_id in pending_decisions.keys():
		var agent_info = _get_agent_info(agent_id)
		agent_info["decision"] = pending_decisions[agent_id]
		input.agents.append(agent_info)

	return input

func _get_agent_info(agent_id: String) -> Dictionary:
	"""获取Agent信息"""
	# 从场景树查找Agent
	var agent_node = _find_agent_node(agent_id)

	if agent_node:
		var character = agent_node.get_parent() as CharacterBody2D
		if character:
			var current_room = _get_current_room_name(character)
			return {
				"agent_id": agent_id,
				"role": _get_agent_role(character),
				"current_scene": current_room,
				"current_position": {
					"x": character.global_position.x,
					"y": character.global_position.y
				},
				"current_state": _get_agent_state(agent_node)
			}

	# 默认信息
	return {
		"agent_id": agent_id,
		"role": "unknown",
		"current_scene": "unknown",
		"current_position": {"x": 0, "y": 0},
		"current_state": "idle"
	}

func _get_available_activities() -> Array[String]:
	"""获取可用活动列表"""
	return [
		"MOVE_TO",
		"INITIATE_DIALOGUE",
		"JOIN_DIALOGUE",
		"LEAVE_DIALOGUE",
		"LISTEN",
		"QA_TEACHER",
		"SELF_STUDY",
		"SPORTS",
	]

func _get_scene_constraints() -> Dictionary:
	"""获取场景约束"""
	if ActivityManager.instance:
		return ActivityManager.instance.scene_activity_map
	return {
		"classroom": ["LISTEN", "QA_TEACHER"],
		"library": ["SELF_STUDY"],
		"study_room": ["SELF_STUDY"],
		"gym": ["SPORTS"],
		"playground": ["SPORTS"]
	}

# ============================================
# Prompt构建
# ============================================

func _build_coordination_prompt(input_data: Dictionary) -> String:
	"""构建协调Prompt"""
	var prompt = coordinator_prompt_template + "\n\n"

	prompt += "## 当前协调任务\n\n"
	prompt += "请根据时间表、场景约束、角色当前位置和每个Agent的自然语言决策，分配现实可信的活动序列。\n\n"
	prompt += "协调规则：\n"
	prompt += "1. 尊重当前时段约束：上课时间优先安排听课、问答或同房间内的课堂活动；休息/午餐/自由时间可安排移动、社交、自习或运动\n"
	prompt += "2. 如果Agent表达了明确社交意愿，再协调相关角色移动到同一房间/中范围，并使用INITIATE_DIALOGUE/JOIN_DIALOGUE\n"
	prompt += "3. 不要为了对话强行聚集所有角色；没有社交意愿时，应允许角色独立学习、听课、休息或运动\n"
	prompt += "4. 如果活动需要特定场景但角色不在该场景，先添加MOVE_TO\n\n"

	prompt += "请根据以下输入，为每个Agent分配活动序列：\n\n"
	prompt += "```json\n"
	prompt += JSON.stringify(input_data, "\t")
	prompt += "\n```\n\n"

	prompt += "请输出JSON格式的活动分配方案。"

	return prompt

func _get_builtin_prompt() -> String:
	"""获取内置简化Prompt"""
	return """你是Activity Coordinator（活动协调器）。

你的任务：
1. 理解每个角色的自然语言决策
2. 将意图映射为具体活动（MOVE_TO, INITIATE_DIALOGUE, JOIN_DIALOGUE, LEAVE_DIALOGUE, LISTEN, QA_TEACHER, SELF_STUDY, SPORTS）
3. 检查场景约束
4. 为每个角色分配最多3步的活动序列

【重要】你必须只输出JSON，不要输出任何其他文字、解释或markdown标记。

输出格式必须是纯JSON：
{
  "agents": [
    {
	  "agent_id": "StudentXiaoming",
	  "steps": [
        {
		  "step": 1,
		  "activity_type": "MOVE_TO",
		  "parameters": {"target_location": {"x": 100, "y": 200}, "target_room": "教室"},
		  "focus_level": 100,
		  "estimated_duration": 5.0,
		  "reason": "移动到目标场景"
        },
        {
		  "step": 2,
		  "activity_type": "SELF_STUDY",
		  "parameters": {"subject": "数学"},
		  "focus_level": 100,
		  "estimated_duration": 45.0,
		  "reason": "自习数学"
        }
      ]
    }
  ]
}

【关键字段名 - 必须严格遵守】
- 顶层字段必须是 "agents" (数组)
- 每个agent必须有 "agent_id" 和 "steps" (数组)
- 必须使用 "steps" 字段，不要使用 "activity_sequence" 或其他名称
- steps数组中的每个元素必须有: step, activity_type, parameters, focus_level, estimated_duration, reason

规则：
- 如果活动需要特定场景但角色不在该场景，先添加MOVE_TO
- 专注度默认100%，提到"随便""走神"时用30%或65%
- 最多3步，第1步通常是移动
- MOVE_TO必须包含target_location（x,y坐标）和target_room（房间名）

【注意】只输出JSON，不要添加```json标记或其他任何文字。"""

# ============================================
# LLM调用
# ============================================

func _call_llm(prompt: String) -> String:
	"""调用本地LLM"""
	print("[ActivityCoordinator] 调用LLM...")
	print("[ActivityCoordinator] 模型=%s, URL=%s" % [llm_model, llm_api_url])
	print("[ActivityCoordinator] Prompt长度=%d" % prompt.length())

	var http_request = HTTPRequest.new()
	add_child(http_request)

	# 设置超时
	http_request.timeout = 60.0

	var body = {
		"model": llm_model,
		"prompt": prompt,
		"stream": false,
		"options": {
			"temperature": llm_temperature,
			"num_predict": llm_max_tokens
		}
	}

	var json_body = JSON.stringify(body)
	var headers = ["Content-Type: application/json"]

	print("[ActivityCoordinator] 发送HTTP请求...")
	var error = http_request.request(llm_api_url, headers, HTTPClient.METHOD_POST, json_body)
	if error != OK:
		push_error("[ActivityCoordinator] HTTP请求失败: %d" % error)
		print("[ActivityCoordinator] HTTP请求错误: %d" % error)
		http_request.queue_free()
		return ""

	print("[ActivityCoordinator] 等待LLM响应...")
	# 等待响应
	var result = await http_request.request_completed
	http_request.queue_free()

	var response_code = result[1]
	var body_text = result[3].get_string_from_utf8()

	print("[ActivityCoordinator] 收到HTTP响应, code=%d, body长度=%d" % [response_code, body_text.length()])

	if response_code == 0:
		print("[ActivityCoordinator] 连接失败(code=0), Ollama可能过载")
		return ""

	if response_code != 200:
		push_error("[ActivityCoordinator] API错误: %d, %s" % [response_code, body_text])
		print("[ActivityCoordinator] API错误: %s" % body_text)
		return ""

	# 解析Ollama响应
	var json = JSON.new()
	var parse_result = json.parse(body_text)
	if parse_result != OK:
		push_error("[ActivityCoordinator] JSON解析失败: %s" % body_text)
		print("[ActivityCoordinator] JSON解析失败")
		return ""

	var response_data = json.get_data()
	var response_text = response_data.get("response", "")

	print("[ActivityCoordinator] 收到LLM响应: %s" % response_text.substr(0, 100))
	return response_text

# ============================================
# 响应解析
# ============================================

func _parse_coordination_response(response: String) -> Dictionary:
	"""解析协调响应（LLM已处理双向奔赴逻辑）"""
	var results = {}

	print("[ActivityCoordinator] _parse_coordination_response: 开始解析, response长度=%d" % response.length())
	print("[ActivityCoordinator] _parse_coordination_response: 响应前200字符=%s" % response.substr(0, 200))

	# 提取JSON
	var json_text = _extract_json_from_text(response)
	print("[ActivityCoordinator] _parse_coordination_response: 提取的JSON长度=%d" % json_text.length())
	print("[ActivityCoordinator] _parse_coordination_response: 提取的JSON前200字符=%s" % json_text.substr(0, 200))

	var json = JSON.new()
	var parse_result = json.parse(json_text)

	if parse_result != OK:
		push_error("[ActivityCoordinator] 无法解析响应: %s" % response)
		print("[ActivityCoordinator] _parse_coordination_response: JSON解析失败, error=%d" % parse_result)
		return results

	var data = json.get_data()
	print("[ActivityCoordinator] _parse_coordination_response: 解析后的数据类型=%s" % typeof(data))

	if not data is Dictionary:
		print("[ActivityCoordinator] _parse_coordination_response: 数据不是Dictionary, 是=%s" % typeof(data))
		return results

	# 支持多种格式：
	# 格式1: { "assignments": [{ "agent_id": "...", "steps": [...] }] }
	# 格式2: { "agents": [{ "agent_id": "...", "steps": [...] }] }
	# 格式3: { "agents": [{ "agent_id": "...", "assignments": [...] }] } (LLM实际输出)

	var assignments = data.get("assignments", [])
	var agents = data.get("agents", [])

	print("[ActivityCoordinator] _parse_coordination_response: assignments字段数量=%d, agents字段数量=%d" % [assignments.size(), agents.size()])

	# 解析每个Agent的分配
	if not assignments.is_empty():
		# 格式1: 使用assignments字段
		print("[ActivityCoordinator] _parse_coordination_response: 使用'assignments'字段")
		for assignment in assignments:
			var agent_id = assignment.get("agent_id", "")
			var steps = assignment.get("steps", [])

			print("[ActivityCoordinator] _parse_coordination_response: 处理assignment, agent_id=%s, steps数量=%d" % [agent_id, steps.size()])

			if agent_id.is_empty():
				print("[ActivityCoordinator] _parse_coordination_response: agent_id为空,跳过")
				continue

			var activities: Array[Activity] = []
			for step_data in steps:
				var activity = _parse_step_to_activity(step_data, agent_id)
				if activity:
					activities.append(activity)
				else:
					print("[ActivityCoordinator] _parse_coordination_response: 解析step失败, step_data=%s" % str(step_data))

			results[agent_id] = activities
			print("[ActivityCoordinator] %s 分配到 %d 个活动" % [agent_id, activities.size()])

	elif not agents.is_empty():
		# 格式2或3: 使用agents字段
		print("[ActivityCoordinator] _parse_coordination_response: 使用'agents'字段")
		for agent_data in agents:
			var agent_id = agent_data.get("agent_id", "")

			# 尝试获取steps、assignments、activities或activity_sequence
			var steps = agent_data.get("steps", [])
			var agent_assignments = agent_data.get("assignments", [])
			var agent_activities = agent_data.get("activities", [])
			var activity_sequence = agent_data.get("activity_sequence", [])

			print("[ActivityCoordinator] _parse_coordination_response: 处理agent, agent_id=%s, steps=%d, assignments=%d, activities=%d, activity_sequence=%d" % [agent_id, steps.size(), agent_assignments.size(), agent_activities.size(), activity_sequence.size()])

			if agent_id.is_empty():
				print("[ActivityCoordinator] _parse_coordination_response: agent_id为空,跳过")
				continue

			var parsed_activities: Array[Activity] = []

			# 优先使用steps，如果没有则使用其他字段
			var activity_list = steps
			if activity_list.is_empty():
				activity_list = agent_assignments
			if activity_list.is_empty():
				activity_list = agent_activities
			if activity_list.is_empty():
				activity_list = activity_sequence

			for step_data in activity_list:
				var activity = _parse_step_to_activity(step_data, agent_id)
				if activity:
					parsed_activities.append(activity)
				else:
					print("[ActivityCoordinator] _parse_coordination_response: 解析step失败, step_data=%s" % str(step_data))

			results[agent_id] = parsed_activities
			print("[ActivityCoordinator] %s 分配到 %d 个活动" % [agent_id, parsed_activities.size()])

	_normalize_dialogue_assignments(results)
	return results

func _parse_step_to_activity(step_data: Dictionary, agent_id: String) -> Activity:
	"""将步骤数据解析为Activity对象"""
	var activity_type_str = step_data.get("activity_type", "MOVE_TO")
	var activity_type = _string_to_activity_type(activity_type_str)

	var parameters = step_data.get("parameters", {})
	var focus_level = step_data.get("focus_level", 100)

	var activity: Activity = null

	match activity_type:
		Activity.ActivityType.MOVE_TO:
			print("[ActivityCoordinator] _parse_step_to_activity MOVE_TO: parameters=%s" % str(parameters))
			var target_location_dict = parameters.get("target_location", {})
			print("[ActivityCoordinator] _parse_step_to_activity MOVE_TO: target_location_dict=%s" % str(target_location_dict))
			var target_location = Vector2(
				target_location_dict.get("x", 0),
				target_location_dict.get("y", 0)
			)
			var target_room = parameters.get("target_room", "")

			var inferred_room = target_room
			if inferred_room.is_empty():
				inferred_room = _infer_target_room_for_step(agent_id, step_data)

			# LLM偶尔会给出不在任何房间内的坐标；解析层兜底到可执行房间坐标。
			if target_location == Vector2.ZERO or not _is_position_in_known_room(target_location):
				if not inferred_room.is_empty():
					target_room = inferred_room
					target_location = _get_room_default_position(target_room)
					print("[ActivityCoordinator] _parse_step_to_activity MOVE_TO: 使用推断房间坐标 %s -> %s" % [target_room, str(target_location)])
			elif target_room.is_empty():
				target_room = _get_room_name_at_position(target_location)

			print("[ActivityCoordinator] _parse_step_to_activity MOVE_TO: target_location=%s, target_room=%s" % [str(target_location), target_room])
			activity = Activity.create_move_to(target_location, target_room)

		Activity.ActivityType.NORMAL_DIALOGUE:
			var target_agent = parameters.get("target_agent", "")
			var topic = parameters.get("topic", "")
			activity = Activity.create_normal_dialogue(target_agent, topic)

		Activity.ActivityType.WHISPER:
			var whisper_target = parameters.get("target_agent", "")
			var content = parameters.get("content", "")
			activity = Activity.create_whisper(whisper_target, content)

		Activity.ActivityType.LISTEN:
			var target_teacher = parameters.get("target_teacher", "")
			var listen_focus = _int_to_focus_level(focus_level)
			activity = Activity.create_listen(target_teacher, listen_focus)

		Activity.ActivityType.QA_TEACHER:
			var question = parameters.get("question", "")
			var is_answer = parameters.get("is_answer", false)
			var qa_focus = _int_to_focus_level(focus_level)
			activity = Activity.create_qa_teacher(question, is_answer, qa_focus)

		Activity.ActivityType.SELF_STUDY:
			var subject = parameters.get("subject", "")
			var study_focus = _int_to_focus_level(focus_level)
			activity = Activity.create_self_study(subject, study_focus)

		Activity.ActivityType.SPORTS:
			var sport_type = parameters.get("sport_type", "")
			var intensity = parameters.get("intensity", 0.5)
			var sports_focus = _int_to_focus_level(focus_level)
			activity = Activity.create_sports(sport_type, intensity, sports_focus)

		Activity.ActivityType.GROUP_DISCUSSION:
			var discussion_topic = parameters.get("topic", "")
			var members: Array[String] = []
			for member in parameters.get("members", []):
				members.append(str(member))
			var discussion_focus = _int_to_focus_level(focus_level)
			activity = Activity.create_group_discussion(discussion_topic, members, discussion_focus)

		Activity.ActivityType.INITIATE_DIALOGUE:
			var range_type = parameters.get("range_type", 1)
			var initial_message = parameters.get("initial_message", "")
			var initiate_topic = parameters.get("topic", "")
			activity = Activity.create_initiate_dialogue(range_type, initial_message, initiate_topic)

		Activity.ActivityType.JOIN_DIALOGUE:
			var join_dialogue_id = parameters.get("dialogue_id", "")
			activity = Activity.create_join_dialogue(join_dialogue_id)

		Activity.ActivityType.LEAVE_DIALOGUE:
			var leave_dialogue_id = parameters.get("dialogue_id", "")
			if leave_dialogue_id.is_empty() and not _agent_has_active_dialogue(agent_id):
				print("[ActivityCoordinator] 跳过 %s 的 LEAVE_DIALOGUE：角色当前不在对话中" % agent_id)
				return null
			activity = Activity.create_leave_dialogue(leave_dialogue_id)


	if activity:
		activity.activity_id = "%s_step%d_%d" % [agent_id, step_data.get("step", 1), Time.get_unix_time_from_system()]
		if step_data.has("estimated_duration"):
			activity.duration_expected = float(step_data.get("estimated_duration", activity.duration_expected))

	return activity

func _string_to_activity_type(type_str: String) -> Activity.ActivityType:
	"""字符串转活动类型"""
	match type_str.to_upper():
		"MOVE_TO": return Activity.ActivityType.MOVE_TO
		"INITIATE_DIALOGUE": return Activity.ActivityType.INITIATE_DIALOGUE
		"JOIN_DIALOGUE": return Activity.ActivityType.JOIN_DIALOGUE
		"LEAVE_DIALOGUE": return Activity.ActivityType.LEAVE_DIALOGUE
		"LISTEN": return Activity.ActivityType.LISTEN
		"QA_TEACHER": return Activity.ActivityType.QA_TEACHER
		"SELF_STUDY": return Activity.ActivityType.SELF_STUDY
		"SPORTS": return Activity.ActivityType.SPORTS
		"GROUP_DISCUSSION": return Activity.ActivityType.GROUP_DISCUSSION

		"NORMAL_DIALOGUE": return Activity.ActivityType.NORMAL_DIALOGUE
		"WHISPER": return Activity.ActivityType.WHISPER
		_: return Activity.ActivityType.MOVE_TO

func _int_to_focus_level(level: int) -> Activity.FocusLevel:
	"""整数转专注度枚举"""
	match level:
		30: return Activity.FocusLevel.LOW
		65: return Activity.FocusLevel.MEDIUM
		100: return Activity.FocusLevel.HIGH
		_: return Activity.FocusLevel.HIGH

func _normalize_dialogue_assignments(results: Dictionary) -> void:
	"""修正LLM输出中常见的对话编排错误"""
	var has_initiator = false
	var join_refs: Array[Dictionary] = []

	for agent_id in results.keys():
		var activities = results[agent_id]
		for i in range(activities.size()):
			var activity = activities[i]
			if not activity is Activity:
				continue

			match activity.activity_type:
				Activity.ActivityType.INITIATE_DIALOGUE:
					has_initiator = true
				Activity.ActivityType.JOIN_DIALOGUE:
					var dialogue_id = activity.parameters.get("dialogue_id", "")
					if not dialogue_id.is_empty() and not _is_dialogue_id_available(dialogue_id):
						print("[ActivityCoordinator] 清空 %s 的虚构 dialogue_id: %s" % [agent_id, dialogue_id])
						activity.parameters["dialogue_id"] = ""
					join_refs.append({"agent_id": agent_id, "index": i})

	if has_initiator or join_refs.is_empty():
		return

	var first_join = join_refs[0]
	var initiator_agent = first_join.agent_id
	var initiator_index = first_join.index
	var topic = _infer_dialogue_topic(initiator_agent)
	var initiate_activity = Activity.create_initiate_dialogue(1, "", topic)
	initiate_activity.activity_id = "%s_dialogue_initiate_%d" % [initiator_agent, Time.get_unix_time_from_system()]
	results[initiator_agent][initiator_index] = initiate_activity
	print("[ActivityCoordinator] 将 %s 的首个 JOIN_DIALOGUE 转为 INITIATE_DIALOGUE，避免无人发起对话" % initiator_agent)

func _is_dialogue_id_available(dialogue_id: String) -> bool:
	if dialogue_id.is_empty():
		return true
	if dialogue_manager and dialogue_manager.has_method("has_active_dialogue"):
		return dialogue_manager.has_active_dialogue(dialogue_id)
	return false

func _infer_dialogue_topic(agent_id: String) -> String:
	var decision = pending_decisions.get(agent_id, "")
	if "吃饭" in decision or "午餐" in decision or "食堂" in decision:
		return "一起吃饭聊天"
	if "学习" in decision or "作业" in decision or "题" in decision:
		return "学习讨论"
	if "课程" in decision or "上课" in decision:
		return "课程交流"
	return "日常交流"

func _get_activity_type_name(activity_type: Activity.ActivityType) -> String:
	"""获取活动类型名称"""
	match activity_type:
		Activity.ActivityType.MOVE_TO: return "MOVE_TO"
		Activity.ActivityType.NORMAL_DIALOGUE: return "DIALOGUE"
		Activity.ActivityType.WHISPER: return "WHISPER"
		Activity.ActivityType.LISTEN: return "CLASS"
		Activity.ActivityType.QA_TEACHER: return "QA"
		Activity.ActivityType.SELF_STUDY: return "SELF_STUDY"
		Activity.ActivityType.SPORTS: return "SPORTS"

		Activity.ActivityType.INITIATE_DIALOGUE: return "INITIATE_DIALOGUE"
		Activity.ActivityType.JOIN_DIALOGUE: return "JOIN_DIALOGUE"
		Activity.ActivityType.LEAVE_DIALOGUE: return "LEAVE_DIALOGUE"
		_: return "UNKNOWN"

func _get_room_default_position(room_name: String) -> Vector2:
	"""根据房间名返回默认坐标（硬编码，基于School场景布局）"""
	# 教室区域（主教学区）
	if "教室" in room_name or "classroom" in room_name.to_lower():
		return Vector2(944 + randf_range(-50, 50), 516 + randf_range(-40, 40))
	# 图书馆
	elif "图书馆" in room_name or "library" in room_name.to_lower():
		return Vector2(175 + randf_range(-45, 45), 136 + randf_range(-45, 45))
	# 体育馆
	elif "体育馆" in room_name or "gym" in room_name.to_lower():
		return Vector2(486 + randf_range(-50, 50), 330 + randf_range(-40, 40))
	# 食堂
	elif "食堂" in room_name or "cafeteria" in room_name.to_lower():
		return Vector2(896 + randf_range(-60, 60), 147 + randf_range(-45, 45))
	# 操场
	elif "操场" in room_name or "playground" in room_name.to_lower():
		return Vector2(1200 + randf_range(-100, 100), 800 + randf_range(-100, 100))
	# 走廊
	elif "走廊" in room_name or "corridor" in room_name.to_lower():
		return Vector2(901 + randf_range(-80, 80), 350 + randf_range(-35, 35))
	# 默认：教室中央
	else:
		print("[ActivityCoordinator] 未知房间 '%s'，使用默认坐标" % room_name)
		return Vector2(944 + randf_range(-50, 50), 516 + randf_range(-40, 40))

func _infer_target_room_for_step(agent_id: String, step_data: Dictionary) -> String:
	"""根据Agent意图、step reason和当前时段推断目标房间"""
	var text = "%s %s" % [
		pending_decisions.get(agent_id, ""),
		step_data.get("reason", "")
	]
	var text_lower = text.to_lower()

	if TimelineState.instance and not TimelineState.instance.current_room.is_empty():
		if TimelineState.instance.is_class_time or "上课" in text or "课" in text:
			return TimelineState.instance.current_room

	if "图书馆" in text or "library" in text_lower or "看书" in text or "自习" in text or "学习" in text:
		return "图书馆"
	if "体育" in text or "运动" in text or "健身" in text or "gym" in text_lower:
		return "体育馆"
	if "食堂" in text or "吃饭" in text or "午餐" in text or "canteen" in text_lower or "cafeteria" in text_lower:
		return "食堂"
	if "讨论" in text:
		return "教室（小组讨论区）"
	if "教室" in text or "classroom" in text_lower:
		return "教室（主教学区）"

	if TimelineState.instance and not TimelineState.instance.current_room.is_empty():
		return TimelineState.instance.current_room

	var agent_node = _find_agent_node(agent_id)
	var character = agent_node.get_parent() as CharacterBody2D if agent_node else null
	if character:
		return _get_current_room_name(character)

	return "教室（主教学区）"

func _is_position_in_known_room(position: Vector2) -> bool:
	return not _get_room_name_at_position(position).is_empty()

func _get_room_name_at_position(position: Vector2) -> String:
	var tree = get_tree()
	if not tree:
		return ""

	var room_managers = tree.get_nodes_in_group("room_manager")
	if room_managers.size() == 0:
		return ""

	var room_manager = room_managers[0]
	if not room_manager.has_method("get_current_room"):
		return ""

	var room = room_manager.get_current_room(room_manager.rooms, position)
	if not room:
		return ""

	return room.room_name

func _agent_has_active_dialogue(agent_id: String) -> bool:
	if not dialogue_manager or not dialogue_manager.has_method("get_character_dialogue"):
		return false

	var agent_node = _find_agent_node(agent_id)
	var character = agent_node.get_parent() as CharacterBody2D if agent_node else null
	if not character:
		return false

	return not dialogue_manager.get_character_dialogue(character).is_empty()

func _extract_json_from_text(text: String) -> String:
	"""从文本中提取JSON（支持markdown代码块）"""
	# 首先尝试查找 ```json 或 ``` 标记的代码块
	var code_block_start = text.find("```json")
	if code_block_start >= 0:
		code_block_start += 7  # 跳过 ```json
		var code_block_end = text.find("```", code_block_start)
		if code_block_end >= 0:
			return text.substr(code_block_start, code_block_end - code_block_start).strip_edges()

	# 尝试普通代码块
	code_block_start = text.find("```")
	if code_block_start >= 0:
		code_block_start += 3  # 跳过 ```
		var code_block_end = text.find("```", code_block_start)
		if code_block_end >= 0:
			return text.substr(code_block_start, code_block_end - code_block_start).strip_edges()

	# 回退到查找第一个 { 和最后一个 }
	var json_start = text.find("{")
	var json_end = text.rfind("}")

	if json_start >= 0 and json_end > json_start:
		return text.substr(json_start, json_end - json_start + 1)

	return text

# ============================================
# 活动下发
# ============================================

func _distribute_activities(results: Dictionary) -> void:
	"""将活动序列下发给各Agent"""
	for agent_id in results.keys():
		var activities = results[agent_id]
		if activities.size() > 0:
			_distribute_to_agent(agent_id, activities)

func _distribute_to_agent(agent_id: String, activities: Array[Activity]) -> void:
	"""将活动下发给指定Agent"""
	var agent_node = _find_agent_node(agent_id)

	print("[ActivityCoordinator] _distribute_to_agent: agent_id=%s, agent_node=%s" % [agent_id, agent_node])

	# 记录下发的活动
	var activities_data = []
	for activity in activities:
		activities_data.append({
			"activity_type": _get_activity_type_name(activity.activity_type),
			"activity_name": activity.activity_name,
			"parameters": activity.parameters,
			"focus_level": activity.focus_level
		})
	_log_coordination("DISTRIBUTE_ACTIVITIES", {
		"agent_id": agent_id,
		"activity_count": activities.size(),
		"activities": activities_data
	})

	if agent_node and agent_node.has_method("receive_activity_sequence"):
		agent_node.receive_activity_sequence(activities)
		activity_assigned.emit(agent_id, activities)
		print("[ActivityCoordinator] 已向 %s 下发 %d 个活动" % [agent_id, activities.size()])

		# V2: 记录活动分配事件到记忆系统
		if MemorySystem.instance:
			var game_time = TimingSystem.instance.current_game_time if TimingSystem.instance else 0.0
			for activity in activities:
				var activity_name = _get_activity_type_name(activity.activity_type)
				MemorySystem.instance.record_agent_activity(
					agent_id,
					activity_name,
					game_time,
					"",
					activity.parameters,
					1  # LOW importance
				)
	else:
		# 存储在协调结果中，等待Agent获取
		if not agent_node:
			print("[ActivityCoordinator] %s 的活动已缓存（找不到Agent节点），等待获取" % agent_id)
		else:
			print("[ActivityCoordinator] %s 的活动已缓存（Agent无receive_activity_sequence方法），等待获取" % agent_id)

func _is_dialogue_activity(activity: Activity) -> bool:
	"""检查是否为对话相关活动"""
	return activity.activity_type in [
		Activity.ActivityType.INITIATE_DIALOGUE,
		Activity.ActivityType.JOIN_DIALOGUE,
		Activity.ActivityType.LEAVE_DIALOGUE
	]

func _process_dialogue_activity(agent_id: String, activity: Activity) -> bool:
	"""
	处理对话相关活动

	返回:
		是否成功处理
	"""
	if not dialogue_manager:
		push_error("[ActivityCoordinator] 对话管理器未初始化")
		return false

	var agent_node = _find_agent_node(agent_id)
	if not agent_node:
		push_error("[ActivityCoordinator] 找不到Agent节点: %s" % agent_id)
		return false

	var character = agent_node.get_parent() as CharacterBody2D
	if not character:
		push_error("[ActivityCoordinator] Agent父节点不是CharacterBody2D")
		return false

	match activity.activity_type:
		Activity.ActivityType.INITIATE_DIALOGUE:
			return _handle_initiate_dialogue(character, activity)
		Activity.ActivityType.JOIN_DIALOGUE:
			return _handle_join_dialogue(character, activity)
		Activity.ActivityType.LEAVE_DIALOGUE:
			return _handle_leave_dialogue(character, activity)

	return false

func _handle_initiate_dialogue(character: CharacterBody2D, activity: Activity) -> bool:
	"""处理发起对话活动"""
	var range_type = activity.parameters.get("range_type", 1)  # 1 = NORMAL
	var initial_message = activity.parameters.get("initial_message", "")
	var topic = activity.parameters.get("topic", "")

	# 获取当前游戏时间（从TimingSystem）
	var current_click = _get_current_click()
	var current_time = _get_current_game_time()

	# 调用DialogueManager发起对话
	var dialogue_id = dialogue_manager.start_dialogue(
		character,
		range_type,
		topic,
		"",  # room_name 自动获取
		"",  # medium_range_id 自动获取
		current_click,
		current_time
	)

	if dialogue_id.is_empty():
		print("[ActivityCoordinator] %s 发起对话失败" % character.name)
		return false

	print("[ActivityCoordinator] %s 成功发起对话: %s" % [character.name, dialogue_id])

	# 如果有初始消息，立即添加
	if not initial_message.is_empty():
		dialogue_manager.add_message(dialogue_id, character, initial_message, current_click)

	return true

func _handle_join_dialogue(character: CharacterBody2D, activity: Activity) -> bool:
	"""处理加入对话活动"""
	var dialogue_id = activity.parameters.get("dialogue_id", "")

	if dialogue_id.is_empty():
		if dialogue_manager and dialogue_manager.has_method("find_joinable_dialogue"):
			dialogue_id = dialogue_manager.find_joinable_dialogue(character)

	if dialogue_id.is_empty():
		print("[ActivityCoordinator] %s 加入对话失败：未找到可加入的对话" % character.name)
		return false

	var current_click = _get_current_click()

	var success = dialogue_manager.join_dialogue(character, dialogue_id, current_click)

	if success:
		print("[ActivityCoordinator] %s 成功加入对话: %s" % [character.name, dialogue_id])
	else:
		print("[ActivityCoordinator] %s 加入对话失败: %s" % [character.name, dialogue_id])

	return success

func _handle_leave_dialogue(character: CharacterBody2D, activity: Activity) -> bool:
	"""处理离开对话活动"""
	var dialogue_id = activity.parameters.get("dialogue_id", "")

	if dialogue_id.is_empty():
		# 如果没有指定ID，使用角色当前的对话
		dialogue_id = dialogue_manager.get_character_dialogue(character)

	if dialogue_id.is_empty():
		print("[ActivityCoordinator] %s 不在任何对话中" % character.name)
		return false

	var success = dialogue_manager.leave_dialogue(character, dialogue_id)

	if success:
		print("[ActivityCoordinator] %s 成功离开对话: %s" % [character.name, dialogue_id])
	else:
		print("[ActivityCoordinator] %s 离开对话失败: %s" % [character.name, dialogue_id])

	return success

func _get_current_click() -> int:
	"""获取当前Click索引（从TimingSystem）"""
	if TimingSystem.instance and TimingSystem.instance.has_method("get_current_click"):
		return TimingSystem.instance.get_current_click()
	return 0

func _get_current_game_time() -> float:
	"""获取当前游戏时间（分钟）

	使用TimeUtils统一获取，确保全项目时间逻辑一致
	"""
	return TimeUtils.get_game_time_minutes()

func get_assigned_activities(agent_id: String) -> Array[Activity]:
	"""获取分配给指定Agent的活动序列"""
	var result = coordination_results.get(agent_id, [])
	# 确保返回类型是 Array[Activity]
	var typed_result: Array[Activity] = []
	if result is Array:
		for item in result:
			if item is Activity:
				typed_result.append(item)
	return typed_result

# ============================================
# 辅助方法
# ============================================

func _find_agent_node(agent_id: String) -> Node:
	"""查找Agent节点"""
	var tree = get_tree()
	if not tree:
		print("[ActivityCoordinator] _find_agent_node: tree is null")
		return null

	var characters = tree.get_nodes_in_group("character")
	print("[ActivityCoordinator] _find_agent_node: 找到 %d 个character节点" % characters.size())

	for char in characters:
		print("[ActivityCoordinator] _find_agent_node: 检查 character=%s, 目标=%s" % [char.name, agent_id])
		if char.name == agent_id:
			print("[ActivityCoordinator] _find_agent_node: 找到匹配的character %s" % agent_id)
			# AIAgent是Character的子节点
			for child in char.get_children():
				print("[ActivityCoordinator] _find_agent_node: 检查子节点 %s, type=%s" % [child.name, child.get_class()])
				if child is AIAgentClass:
					print("[ActivityCoordinator] _find_agent_node: 找到AIAgent子节点")
					return child
			# 或者AIAgent就是char本身
			if char is AIAgentClass:
				print("[ActivityCoordinator] _find_agent_node: character本身就是AIAgent")
				return char
			print("[ActivityCoordinator] _find_agent_node: character %s 没有AIAgent子节点" % agent_id)

	print("[ActivityCoordinator] _find_agent_node: 未找到 %s" % agent_id)
	return null

func _get_current_room_name(character: CharacterBody2D) -> String:
	"""获取角色当前房间名称"""
	# 从场景树查找 RoomManager
	var tree = get_tree()
	if not tree:
		return "unknown"

	var room_managers = tree.get_nodes_in_group("room_manager")
	if room_managers.size() > 0:
		var room_manager = room_managers[0]
		if room_manager.has_method("get_current_room"):
			var room = room_manager.get_current_room(
				room_manager.rooms,
				character.global_position
			)
			if room:
				return room.name
	return "unknown"

func _get_agent_role(character: CharacterBody2D) -> String:
	"""获取Agent角色类型"""
	# 从角色名称或元数据判断
	var name_lower = character.name.to_lower()
	if "teacher" in name_lower or "principal" in name_lower or "librarian" in name_lower:
		return "teacher"
	return "student"

func _get_agent_state(agent_node: Node) -> String:
	"""获取Agent当前状态"""
	if agent_node is AIAgentClass:
		match agent_node.current_state:
			AIAgentClass.AgentState.IDLE: return "idle"
			AIAgentClass.AgentState.IN_DIALOGUE: return "in_dialogue"
			AIAgentClass.AgentState.IN_ACTIVITY: return "in_activity"
			AIAgentClass.AgentState.MOVING: return "moving"
			_: return "idle"
	return "idle"
