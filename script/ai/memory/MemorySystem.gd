extends Node

# ============================================
# MemorySystem - 记忆系统主控
# ============================================
# 整合事件记忆、社交记忆、情感记忆
# 提供统一的记忆管理接口
# 保持与旧 MemoryManager 的向后兼容性
# ============================================

# 单例
static var instance: MemorySystem

# 子系统
var event_memory: EventMemory
var social_memory: SocialMemory
var emotion_memory: EmotionMemory

# 缓存已加载的Agent数据
var _loaded_agents: Dictionary = {}  # {agent_id: true}

# 新增：自然语言记忆存储 {agent_id: [memory_entry, ...]}
var _natural_memories: Dictionary = {}

# 记忆类型枚举（保持兼容）
enum MemoryType {
	PERSONAL,      # 个人记忆
	INTERACTION,   # 互动记忆
	TASK,          # 任务记忆
	EMOTION,       # 情感记忆
	EVENT          # 事件记忆
}

# 记忆重要性等级（保持兼容）
enum MemoryImportance {
	LOW = 1,
	NORMAL = 3,
	HIGH = 5,
	CRITICAL = 10
}

func _init():
	instance = self
	event_memory = EventMemory.new()
	social_memory = SocialMemory.new()
	emotion_memory = EmotionMemory.new()

func _ready():
	print("[MemorySystem] 记忆系统初始化完成")
	_load_all_saved_memories()
	_connect_to_timing_system()

# ============================================
# 向后兼容接口（必须保持与旧 MemoryManager 一致）
# ============================================

# 获取角色的所有记忆（保持兼容）
# 注意：参数从 Node 改为 agent_id String，但保持函数签名兼容
func get_character_memories(character: Node) -> Array:
	if not character:
		return []
	
	var agent_id = character.name
	_ensure_agent_loaded(agent_id)
	
	# 从事件记忆中构建旧格式的记忆列表
	var events = event_memory.get_events(agent_id)
	var old_format_memories = []
	
	for event in events:
		var memory_obj = {
			"content": MemoryFormatter.format_event_memory(event.to_dictionary()),
			"timestamp": event.timestamp,
			"type": _event_type_to_memory_type(event.event_type),
			"importance": event.importance,
			"created_at": event.real_timestamp
		}
		old_format_memories.append(memory_obj)
	
	return old_format_memories

# 添加记忆到角色（保持兼容）
func add_memory(character: Node, memory_content: String, 
				memory_type: MemoryType = MemoryType.PERSONAL, 
				importance: MemoryImportance = MemoryImportance.NORMAL) -> void:
	
	if not character or memory_content.strip_edges().is_empty():
		return
	
	var agent_id = character.name
	_ensure_agent_loaded(agent_id)
	
	# 获取当前游戏时间
	var game_time = _get_current_game_time()
	var timestamp = MemoryFormatter.format_game_timestamp(game_time)
	
	# 根据记忆类型存储到不同的子系统
	match memory_type:
		MemoryType.PERSONAL, MemoryType.TASK:
			# 存储为通用事件
			event_memory.record_event(
				agent_id, 
				"PERSONAL", 
				game_time,
				"",
				{"content": memory_content},
				importance
			)
		
		MemoryType.EMOTION:
			# 解析情感记忆内容，更新情感状态
			_emotion_memory_from_text(agent_id, memory_content, game_time)
		
		MemoryType.INTERACTION, MemoryType.EVENT:
			# 存储为事件
			event_memory.record_event(
				agent_id,
				"EVENT",
				game_time,
				"",
				{"content": memory_content},
				importance
			)
	
	print("[MemorySystem] 添加记忆: %s - %s" % [agent_id, memory_content.substr(0, 50)])
	
	# 自动保存
	_save_agent_memory(agent_id)

# 获取格式化的记忆文本（用于AI prompt）（保持兼容）
func get_formatted_memories_for_prompt(character: Node, max_count: int = -1) -> String:
	if not character:
		return "\n\n记忆信息：\n- 暂无重要记忆"
	
	var agent_id = character.name
	_ensure_agent_loaded(agent_id)
	
	# 获取各类记忆
	var events = event_memory.get_events(agent_id)
	var relationships = social_memory.get_all_relationships(agent_id)
	var emotions = emotion_memory.get_all_emotions(agent_id)
	
	# 转换为旧格式用于格式化
	var old_format_events = []
	for event in events:
		old_format_events.append(event.to_dictionary())
	
	var old_format_social = []
	for rel in relationships:
		old_format_social.append({
			"with_agent": rel.agent_b if rel.agent_a == agent_id else rel.agent_a,
			"total_interactions": rel.total_interactions,
			"relationship_score": rel.relationship_score
		})
	
	var old_format_emotions = []
	for emotion in emotions:
		old_format_emotions.append(emotion.to_dictionary())
	
	return MemoryFormatter.build_memory_prompt_text(
		old_format_events, 
		old_format_social, 
		old_format_emotions, 
		max_count if max_count > 0 else 5
	)

# 格式化记忆用于显示（保持兼容，被 GodUI 直接调用）
func _format_memory_for_display(memory: Dictionary) -> String:
	return MemoryFormatter.format_memory_for_display(memory)

# 获取记忆的重要性（保持兼容）
func _get_memory_importance(memory: Dictionary) -> int:
	return MemoryFormatter.get_memory_importance(memory)

# 获取记忆的时间戳（保持兼容）
func _get_memory_timestamp(memory: Dictionary) -> float:
	return MemoryFormatter.get_memory_timestamp(memory)

# ============================================
# 新增接口
# ============================================

# 新增：添加自然语言记忆（情感评估用）
func add_natural_memory(agent_id: String, content: String, 
						context: String = "", game_time: float = 0.0) -> void:
	"""
	添加自然语言记忆（用于情感评估和体验记录）
	
	参数:
	- agent_id: Agent标识
	- content: 自然语言内容（情感评估结果）
	- context: 上下文（如活动名称）
	- game_time: 游戏时间
	"""
	if content.strip_edges().is_empty():
		return
	
	_ensure_agent_loaded(agent_id)
	
	# 创建自然语言记忆条目
	var memory_entry = {
		"type": "NATURAL_EMOTION",
		"content": content,
		"context": context,
		"timestamp": MemoryFormatter.format_game_timestamp(game_time) if game_time > 0 else "未知时间",
		"real_timestamp": Time.get_unix_time_from_system()
	}
	
	# 存储到自然语言记忆列表
	if not _natural_memories.has(agent_id):
		_natural_memories[agent_id] = []
	_natural_memories[agent_id].append(memory_entry)
	
	# 限制记忆数量（保留最近50条）
	if _natural_memories[agent_id].size() > 50:
		_natural_memories[agent_id].pop_front()
	
	print("[MemorySystem] %s 添加自然记忆: %s" % [agent_id, content.substr(0, 40)])
	_save_agent_memory(agent_id)

# 新增：获取关于某人的自然语言记忆
func get_memories_about(agent_id: String, target_name: String, max_count: int = 3) -> Array:
	"""
	获取关于特定目标的自然语言记忆
	用于在情感评估时提供上下文
	"""
	if not _natural_memories.has(agent_id):
		return []
	
	var result = []
	var memories = _natural_memories[agent_id]
	
	# 倒序遍历，找最近的相关记忆
	for i in range(memories.size() - 1, -1, -1):
		var mem = memories[i]
		var content = mem.get("content", "")
		# 简单字符串匹配（包含目标名字）
		if target_name in content:
			result.append(content)
			if result.size() >= max_count:
				break
	
	return result

# 记录事件
func record_event(agent_id: String, event_type: String, 
				  game_time: float, location: String = "",
				  details: Dictionary = {}, importance: int = 3,
				  emotional_valence: float = 0.0) -> void:
	
	_ensure_agent_loaded(agent_id)
	event_memory.record_event(agent_id, event_type, game_time, location, 
							  details, importance, emotional_valence)
	_save_agent_memory(agent_id)

# 记录互动
func record_interaction(agent_a: String, agent_b: String, 
						interaction_type: String, game_time: float,
						location: String, topic: String = "",
						duration: float = 0.0, 
						emotional_impact: float = 0.0) -> void:
	
	_ensure_agent_loaded(agent_a)
	_ensure_agent_loaded(agent_b)
	
	social_memory.record_interaction(agent_a, agent_b, interaction_type, 
									 game_time, location, topic, duration, 
									 emotional_impact)
	
	# 同时更新双方的情感
	if emotional_impact != 0.0:
		update_emotion(agent_a, agent_b, "AGENT", "好感", emotional_impact, game_time)
		update_emotion(agent_b, agent_a, "AGENT", "好感", emotional_impact, game_time)
	
	_save_agent_memory(agent_a)
	_save_agent_memory(agent_b)

# 更新情感
func update_emotion(agent_id: String, target: String, target_type: String,
					dimension: String, delta: float, game_time: float,
					trigger: String = "", reason: String = "") -> void:
	
	_ensure_agent_loaded(agent_id)
	emotion_memory.update_emotion(agent_id, target, target_type, dimension, 
								  delta, game_time, trigger, reason)
	_save_agent_memory(agent_id)

# 获取最近事件
func get_recent_events(agent_id: String, current_game_time: float, 
					   game_hours: float = 1.0) -> Array[EventMemory.EventRecord]:
	_ensure_agent_loaded(agent_id)
	return event_memory.get_recent_events(agent_id, current_game_time, game_hours)

# 获取关系摘要
func get_relationship_summary(agent_a: String, agent_b: String) -> Dictionary:
	_ensure_agent_loaded(agent_a)
	_ensure_agent_loaded(agent_b)
	
	var rel = social_memory.get_relationship(agent_a, agent_b)
	return {
		"score": rel.relationship_score,
		"description": social_memory.get_relationship_description(agent_a, agent_b),
		"total_interactions": rel.total_interactions,
		"recent_interactions": rel.get_recent_interactions(24).size()
	}

# 获取态度描述
func get_attitude_description(agent_id: String, target: String) -> String:
	_ensure_agent_loaded(agent_id)
	return emotion_memory.get_attitude_description(agent_id, target)

# 便捷方法：记录Agent的活动事件（供AIAgent调用）
func record_agent_activity(agent_id: String, activity_type: String, 
						   game_time: float, location: String,
						   details: Dictionary = {},
						   importance: int = 3) -> void:
	"""
	记录Agent的活动事件
	供AIAgent在活动执行后调用
	"""
	_ensure_agent_loaded(agent_id)
	
	# 根据活动类型设置情感价值
	var emotional_valence = 0.0
	match activity_type:
		"DIALOGUE", "WHISPER":
			emotional_valence = 0.1  # 社交活动通常是正面的
		"SPORTS":
			emotional_valence = 0.2  # 运动带来愉悦
		"SELF_STUDY":
			emotional_valence = 0.05  # 学习略有满足感
		"CLASS":
			emotional_valence = 0.0  # 上课中性
	
	record_event(agent_id, activity_type, game_time, location, 
				 details, importance, emotional_valence)

# 便捷方法：记录Agent之间的互动（供ActivityCoordinator调用）
func record_agents_interaction(agent_ids: Array[String], interaction_type: String,
							   game_time: float, location: String,
							   topic: String = "") -> void:
	"""
	记录多个Agent之间的互动
	供ActivityCoordinator在分配共同活动时调用
	"""
	if agent_ids.size() < 2:
		return
	
	# 两两记录互动
	for i in range(agent_ids.size()):
		for j in range(i + 1, agent_ids.size()):
			record_interaction(agent_ids[i], agent_ids[j], interaction_type,
							   game_time, location, topic, 5.0, 0.05)

# ============================================
# 数据持久化
# ============================================

func _ensure_agent_loaded(agent_id: String) -> void:
	if _loaded_agents.has(agent_id):
		return
	
	# 从文件加载
	var data = MemoryPersistence.load_agent_memory(agent_id)
	if not data.is_empty():
		if data.has("events"):
			event_memory.deserialize(data["events"])
		if data.has("social"):
			social_memory.deserialize(data["social"])
		if data.has("emotions"):
			emotion_memory.deserialize(data["emotions"])
		# 加载自然语言记忆
		if data.has("natural_memories"):
			_natural_memories[agent_id] = data["natural_memories"]
	
	_loaded_agents[agent_id] = true

func _save_agent_memory(agent_id: String) -> void:
	var data = {
		"events": event_memory.serialize(),
		"social": social_memory.serialize(),
		"emotions": emotion_memory.serialize(),
		"natural_memories": _natural_memories.get(agent_id, [])
	}
	MemoryPersistence.save_agent_memory(agent_id, data)

func _load_all_saved_memories() -> void:
	var agent_ids = MemoryPersistence.get_saved_agent_ids()
	print("[MemorySystem] 发现 %d 个已保存的Agent记忆" % agent_ids.size())

func save_all() -> void:
	for agent_id in _loaded_agents.keys():
		_save_agent_memory(agent_id)
	print("[MemorySystem] 所有记忆已保存")

# ============================================
# 辅助函数
# ============================================

func _get_current_game_time() -> float:
	# 从 TimingSystem 获取当前游戏时间
	if TimingSystem.instance:
		return TimingSystem.instance.current_game_time
	return 8.0 * 60.0  # 默认 8:00

func _event_type_to_memory_type(event_type: String) -> int:
	match event_type:
		"DIALOGUE", "WHISPER":
			return MemoryType.INTERACTION
		"CLASS", "SELF_STUDY", "SPORTS":
			return MemoryType.EVENT
		_:
			return MemoryType.PERSONAL

func _emotion_memory_from_text(agent_id: String, text: String, game_time: float) -> void:
	# 简单解析情感记忆文本，更新对应情感
	# 例如："对小明产生了好感" -> 更新对小明的好感
	
	var targets = ["小明", "小红", "老师", "同学"]  # 简化处理
	var emotions = {
		"好感": "好感",
		"喜欢": "好感",
		"信任": "信任",
		"尊重": "尊重",
		"害怕": "恐惧",
		"讨厌": "厌恶",
		"生气": "愤怒"
	}
	
	for target in targets:
		if target in text:
			for emotion_key in emotions.keys():
				if emotion_key in text:
					var dimension = emotions[emotion_key]
					var delta = 0.1 if "产生" in text or "增加" in text else 0.0
					if delta > 0:
						update_emotion(agent_id, target, "AGENT", dimension, delta, game_time, "", text)
					break
			break

# ============================================
# TimingSystem 集成
# ============================================

func _connect_to_timing_system() -> void:
	# 等待一帧确保 TimingSystem 已初始化
	await get_tree().process_frame
	
	var timing_system = get_node_or_null("/root/TimingSystem")
	if timing_system:
		# 监听 Click 触发信号
		timing_system.click_triggered.connect(_on_click_triggered)
		timing_system.day_started.connect(_on_day_started)
		timing_system.day_ended.connect(_on_day_ended)
		print("[MemorySystem] 已连接到 TimingSystem")
	else:
		push_warning("[MemorySystem] 未找到 TimingSystem")

func _on_click_triggered(game_time: float, day: int, click_num: int) -> void:
	# 每个 Click 结束时可以执行的操作
	# 例如：自动保存记忆、应用情感衰减等
	
	# 每5个Click保存一次（约10现实分钟）
	if click_num % 5 == 0:
		save_all()
	
	# 每10个Click应用一次情感衰减
	if click_num % 10 == 0:
		apply_emotion_decay_to_all(0.98)

func _on_day_started(day: int, start_time: float) -> void:
	print("[MemorySystem] 第%d天开始，加载所有Agent记忆" % day)
	_load_all_saved_memories()

func _on_day_ended(day: int, end_time: float) -> void:
	print("[MemorySystem] 第%d天结束，保存所有记忆" % day)
	save_all()
	cleanup_all_memories(100, 20)  # 清理旧记忆

# ============================================
# 清理和优化
# ============================================

func cleanup_all_memories(max_events: int = 100, max_history: int = 20) -> void:
	for agent_id in _loaded_agents.keys():
		event_memory.cleanup_old_events(agent_id, max_events)
		emotion_memory.cleanup_old_history(agent_id, max_history)
		_save_agent_memory(agent_id)

func apply_emotion_decay_to_all(decay_rate: float = 0.95) -> void:
	for agent_id in _loaded_agents.keys():
		emotion_memory.apply_emotion_decay(agent_id, decay_rate)
		_save_agent_memory(agent_id)
