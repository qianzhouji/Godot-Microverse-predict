extends Node
# 注意：不使用class_name，因为此脚本已配置为AutoLoad
# 通过HardcodedDemoController.instance访问单例

# ============================================
# 硬编码Demo控制器
# 用于对话系统测试，完全控制流程，不依赖LLM
# ============================================

# 单例
static var instance: Node

# Demo配置
const DEMO_MODE: bool = true  # 启用硬编码模式

# 角色配置
var demo_agents: Array[String] = ["StudentXiaoming", "StudentXiaohong", "StudentXiaogang"]
var agent_positions: Dictionary = {}  # 记录每个角色的位置

# Click流程控制
var current_click: int = 0
var is_demo_running: bool = false

# 教室中心位置（硬编码）
const CLASSROOM_CENTER: Vector2 = Vector2(400, 300)
const DIALOGUE_RANGE_TYPE: int = 1  # 1 = NORMAL普通对话 (范围200px，中范围)

# 信号
signal demo_step_completed(step: int, description: String)

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
	print("\n[HardcodedDemoController] ========== DEMO开始 ==========")
	print("[HardcodedDemoController] 角色列表: %s" % demo_agents)
	print("[HardcodedDemoController] 教室中心位置: %s" % CLASSROOM_CENTER)
	print("[HardcodedDemoController] ==============================\n")

# 由TimingSystem调用，替代原有的协调器逻辑
func execute_hardcoded_click(click_num: int, game_time: float) -> Dictionary:
	current_click = click_num
	print("\n[HardcodedDemoController] ===== CLICK #%d =====" % click_num)
	
	var assignments: Dictionary = {}
	
	match click_num:
		1:
			# Click 1: 所有角色移动到教室
			assignments = _click1_move_to_classroom()
			
		2:
			# Click 2: 小明发起对话
			assignments = _click2_initiate_dialogue()
			
		3:
			# Click 3: 其他角色加入对话
			assignments = _click3_join_dialogue()
			
		4:
			# Click 4+: 继续对话或结束
			assignments = _click4_continue_dialogue()
			
		_:
			# 后续Click: 保持对话状态
			assignments = _click_continue()
	
	print("[HardcodedDemoController] 本Click分配: %d 个角色" % assignments.size())
	for agent_id in assignments.keys():
		var activities = assignments[agent_id]
		print("[HardcodedDemoController]   - %s: %d 个活动" % [agent_id, activities.size()])
		for act in activities:
			print("[HardcodedDemoController]     * %s" % act.activity_type)
	
	return assignments

# Click 1: 所有角色移动到教室
func _click1_move_to_classroom() -> Dictionary:
	print("[HardcodedDemoController] [Click 1] 所有角色移动到教室")
	
	var assignments: Dictionary = {}
	
	for agent_id in demo_agents:
		# 为每个角色分配移动到教室中心的活动
		var activity = Activity.new(Activity.ActivityType.MOVE_TO, "move_to_classroom_%s" % agent_id)
		activity.parameters = {
			"target_location": {
				"x": CLASSROOM_CENTER.x + randf_range(-30, 30),
				"y": CLASSROOM_CENTER.y + randf_range(-30, 30)
			}
		}
		activity.step_index = 0
		
		assignments[agent_id] = [activity]
		print("[HardcodedDemoController]   %s -> MOVE_TO (%s)" % [agent_id, activity.parameters.target_location])
	
	demo_step_completed.emit(1, "所有角色移动到教室")
	return assignments

# Click 2: 小明发起对话
func _click2_initiate_dialogue() -> Dictionary:
	print("[HardcodedDemoController] [Click 2] 小明发起对话")
	
	var assignments: Dictionary = {}
	
	for agent_id in demo_agents:
		if agent_id == "StudentXiaoming":
			# 小明发起对话
			var activity = Activity.new(Activity.ActivityType.INITIATE_DIALOGUE, "initiate_dialogue_xiaoming")
			activity.parameters = {
				"range_type": DIALOGUE_RANGE_TYPE,  # 1 = NORMAL普通对话
				"topic": "日常闲聊"
			}
			activity.step_index = 0
			
			assignments[agent_id] = [activity]
			print("[HardcodedDemoController]   %s -> INITIATE_DIALOGUE (范围: 普通对话, topic: 日常闲聊)" % agent_id)
		else:
			# 其他角色保持空闲（等待下一Click加入）
			print("[HardcodedDemoController]   %s -> IDLE (等待加入对话)" % agent_id)
			# 不分配活动，保持空闲状态
	
	demo_step_completed.emit(2, "小明发起对话")
	return assignments

# Click 3: 其他角色加入对话
func _click3_join_dialogue() -> Dictionary:
	print("[HardcodedDemoController] [Click 3] 其他角色加入对话")
	
	var assignments: Dictionary = {}
	
	# 获取小明的对话ID（需要从DialogueManager获取）
	var dialogue_id = _get_xiaoming_dialogue_id()
	
	for agent_id in demo_agents:
		if agent_id == "StudentXiaoming":
			# 小明继续对话（已经在对话中）
			print("[HardcodedDemoController]   %s -> 已在对话中，继续" % agent_id)
		else:
			# 其他角色加入对话
			if dialogue_id != "":
				var activity = Activity.new(Activity.ActivityType.JOIN_DIALOGUE, "join_dialogue_%s" % agent_id)
				activity.parameters = {
					"dialogue_id": dialogue_id
				}
				activity.step_index = 0
				
				assignments[agent_id] = [activity]
				print("[HardcodedDemoController]   %s -> JOIN_DIALOGUE (id: %s)" % [agent_id, dialogue_id])
			else:
				print("[HardcodedDemoController]   %s -> 未找到对话ID，保持空闲" % agent_id)
	
	demo_step_completed.emit(3, "其他角色加入对话")
	return assignments

# Click 4+: 继续对话
func _click4_continue_dialogue() -> Dictionary:
	print("[HardcodedDemoController] [Click 4+] 继续对话")
	
	var assignments: Dictionary = {}
	
	# 所有角色已经在对话中，不需要额外分配活动
	# 对话系统会自动管理发言队列
	for agent_id in demo_agents:
		print("[HardcodedDemoController]   %s -> 继续对话" % agent_id)
	
	demo_step_completed.emit(4, "继续对话")
	return assignments

# 后续Click: 保持状态
func _click_continue() -> Dictionary:
	print("[HardcodedDemoController] [Click %d] 保持当前状态" % current_click)
	return {}

# 存储小明的对话ID（由_initiate_dialogue成功时设置）
var _xiaoming_dialogue_id: String = ""

# 设置小明的对话ID（由AIAgent在发起对话成功后调用）
func set_xiaoming_dialogue_id(dialogue_id: String) -> void:
	_xiaoming_dialogue_id = dialogue_id
	print("[HardcodedDemoController] 记录小明的对话ID: %s" % dialogue_id)

# 获取小明的对话ID
func _get_xiaoming_dialogue_id() -> String:
	# 优先使用记录的对话ID
	if not _xiaoming_dialogue_id.is_empty():
		return _xiaoming_dialogue_id
	
	# 备用：尝试从DialogManager查找
	var dialog_manager = get_node_or_null("/root/DialogManager")
	if not dialog_manager:
		print("[HardcodedDemoController] 警告: DialogManager未找到")
		return ""
	
	# 获取小明的角色节点
	var xiaoming = _get_agent("StudentXiaoming")
	if not xiaoming:
		print("[HardcodedDemoController] 警告: 未找到StudentXiaoming")
		return ""
	
	# 从小明的metadata中获取对话ID
	if xiaoming.has_meta("current_dialogue_id"):
		return xiaoming.get_meta("current_dialogue_id")
	
	print("[HardcodedDemoController] 警告: 小明没有current_dialogue_id metadata")
	return ""

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
