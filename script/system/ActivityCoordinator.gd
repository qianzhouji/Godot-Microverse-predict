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

func _load_prompt_template() -> void:
	"""加载协调器Prompt模板"""
	# 从文件加载或直接使用内置模板
	var prompt_path = "res://docs/prompts/coordinator_prompt.md"
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
	
	print("[ActivityCoordinator] 开始协调 %d 个Agent..." % pending_decisions.size())
	
	# 打印所有Agent的决策内容
	print("[ActivityCoordinator] ===== 所有Agent决策内容 =====")
	for agent_id in pending_decisions.keys():
		var decision = pending_decisions[agent_id]
		# 截断过长的决策文本
		var display_decision = decision
		if display_decision.length() > 200:
			display_decision = display_decision.substr(0, 200) + "..."
		print("[ActivityCoordinator]   %s: %s" % [agent_id, display_decision.replace("\n", " ")])
	print("[ActivityCoordinator] ===== 决策内容结束 =====")
	
	# 构建输入数据
	var input_data = _build_coordination_input(game_context)
	
	# 构建Prompt
	var prompt = _build_coordination_prompt(input_data)
	
	# 调用LLM
	var response = await _call_llm(prompt)
	
	if response.is_empty():
		coordination_failed.emit("LLM调用失败")
		is_coordinating = false
		return {}
	
	# 打印完整LLM响应用于调试
	print("[ActivityCoordinator] ===== LLM完整响应 =====")
	print("[ActivityCoordinator] 响应长度: %d" % response.length())
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
		"NORMAL_DIALOGUE",
		"WHISPER",
		"LISTEN",
		"QA_TEACHER",
		"SELF_STUDY",
		"SPORTS",
		"GROUP_DISCUSSION"
	]

func _get_scene_constraints() -> Dictionary:
	"""获取场景约束"""
	if ActivityManager.instance:
		return ActivityManager.instance.scene_activity_map
	return {
		"classroom": ["LISTEN", "QA_TEACHER", "GROUP_DISCUSSION"],
		"library": ["SELF_STUDY"],
		"study_room": ["SELF_STUDY"],
		"gym": ["SPORTS"],
		"playground": ["SPORTS"],
		"discussion_room": ["GROUP_DISCUSSION"]
	}

# ============================================
# Prompt构建
# ============================================

func _build_coordination_prompt(input_data: Dictionary) -> String:
	"""构建协调Prompt"""
	var prompt = coordinator_prompt_template + "\n\n"
	
	prompt += "## 当前协调任务\n\n"
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
2. 将意图映射为具体活动（MOVE_TO, NORMAL_DIALOGUE, WHISPER, LISTEN, QA_TEACHER, SELF_STUDY, SPORTS, GROUP_DISCUSSION）
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

【关键字段名】
- 顶层字段必须是 "agents" (数组)
- 每个agent必须有 "agent_id" 和 "steps" (数组)
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
			
			# 尝试获取steps、assignments或activities
			var steps = agent_data.get("steps", [])
			var agent_assignments = agent_data.get("assignments", [])
			var agent_activities = agent_data.get("activities", [])
			
			print("[ActivityCoordinator] _parse_coordination_response: 处理agent, agent_id=%s, steps=%d, assignments=%d, activities=%d" % [agent_id, steps.size(), agent_assignments.size(), agent_activities.size()])
			
			if agent_id.is_empty():
				print("[ActivityCoordinator] _parse_coordination_response: agent_id为空,跳过")
				continue
			
			var parsed_activities: Array[Activity] = []
			
			# 优先使用steps，如果没有则使用assignments或activities
			var activity_list = steps
			if activity_list.is_empty():
				activity_list = agent_assignments
			if activity_list.is_empty():
				activity_list = agent_activities
			
			for step_data in activity_list:
				var activity = _parse_step_to_activity(step_data, agent_id)
				if activity:
					parsed_activities.append(activity)
				else:
					print("[ActivityCoordinator] _parse_coordination_response: 解析step失败, step_data=%s" % str(step_data))
			
			results[agent_id] = parsed_activities
			print("[ActivityCoordinator] %s 分配到 %d 个活动" % [agent_id, parsed_activities.size()])
	
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
			
			# 如果LLM没有返回坐标，根据房间名自动分配
			if target_location == Vector2.ZERO and not target_room.is_empty():
				target_location = _get_room_default_position(target_room)
				print("[ActivityCoordinator] _parse_step_to_activity MOVE_TO: 使用房间默认坐标 %s" % str(target_location))
			
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
			var topic = parameters.get("topic", "")
			var members_raw = parameters.get("members", [])
			# 转换为Array[String]
			var members: Array[String] = []
			for m in members_raw:
				if m is String:
					members.append(m)
			var discussion_focus = _int_to_focus_level(focus_level)
			activity = Activity.create_group_discussion(topic, members, discussion_focus)
	
	if activity:
		activity.activity_id = "%s_step%d_%d" % [agent_id, step_data.get("step", 1), Time.get_unix_time_from_system()]
	
	return activity

func _string_to_activity_type(type_str: String) -> Activity.ActivityType:
	"""字符串转活动类型"""
	match type_str.to_upper():
		"MOVE_TO": return Activity.ActivityType.MOVE_TO
		"NORMAL_DIALOGUE": return Activity.ActivityType.NORMAL_DIALOGUE
		"WHISPER": return Activity.ActivityType.WHISPER
		"LISTEN": return Activity.ActivityType.LISTEN
		"QA_TEACHER": return Activity.ActivityType.QA_TEACHER
		"SELF_STUDY": return Activity.ActivityType.SELF_STUDY
		"SPORTS": return Activity.ActivityType.SPORTS
		"GROUP_DISCUSSION": return Activity.ActivityType.GROUP_DISCUSSION
		_: return Activity.ActivityType.MOVE_TO

func _int_to_focus_level(level: int) -> Activity.FocusLevel:
	"""整数转专注度枚举"""
	match level:
		30: return Activity.FocusLevel.LOW
		65: return Activity.FocusLevel.MEDIUM
		100: return Activity.FocusLevel.HIGH
		_: return Activity.FocusLevel.HIGH

func _get_room_default_position(room_name: String) -> Vector2:
	"""根据房间名返回默认坐标（硬编码，基于School场景布局）"""
	# 教室区域（主教学区）- 场景中央
	if "教室" in room_name or "classroom" in room_name.to_lower():
		return Vector2(1000 + randf_range(-50, 50), 400 + randf_range(-50, 50))
	# 图书馆
	elif "图书馆" in room_name or "library" in room_name.to_lower():
		return Vector2(600 + randf_range(-50, 50), 300 + randf_range(-50, 50))
	# 体育馆
	elif "体育馆" in room_name or "gym" in room_name.to_lower():
		return Vector2(1400 + randf_range(-50, 50), 600 + randf_range(-50, 50))
	# 食堂
	elif "食堂" in room_name or "cafeteria" in room_name.to_lower():
		return Vector2(800 + randf_range(-50, 50), 700 + randf_range(-50, 50))
	# 操场
	elif "操场" in room_name or "playground" in room_name.to_lower():
		return Vector2(1200 + randf_range(-100, 100), 800 + randf_range(-100, 100))
	# 走廊
	elif "走廊" in room_name or "corridor" in room_name.to_lower():
		return Vector2(1000 + randf_range(-100, 100), 200 + randf_range(-50, 50))
	# 默认：教室中央
	else:
		print("[ActivityCoordinator] 未知房间 '%s'，使用默认坐标" % room_name)
		return Vector2(1000 + randf_range(-50, 50), 400 + randf_range(-50, 50))

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
		var agent_node = _find_agent_node(agent_id)
		
		print("[ActivityCoordinator] _distribute_activities: agent_id=%s, agent_node=%s" % [agent_id, agent_node])
		
		if agent_node and agent_node.has_method("receive_activity_sequence"):
			agent_node.receive_activity_sequence(activities)
			activity_assigned.emit(agent_id, activities)
			print("[ActivityCoordinator] 已向 %s 下发 %d 个活动" % [agent_id, activities.size()])
		else:
			# 存储在协调结果中，等待Agent获取
			if not agent_node:
				print("[ActivityCoordinator] %s 的活动已缓存（找不到Agent节点），等待获取" % agent_id)
			else:
				print("[ActivityCoordinator] %s 的活动已缓存（Agent无receive_activity_sequence方法），等待获取" % agent_id)

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
			if room and room.has("room_name"):
				return room.room_name
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
