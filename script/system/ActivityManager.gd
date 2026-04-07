extends Node
class_name ActivityManager

# ActivityManager - 活动管理系统
# 职责：
# 1. 管理Agent的活动生命周期
# 2. 记录活动持续时间
# 3. 每次Click时计算累积奖赏
# 4. 支持活动的中断、继续、切换

# 单例
static var instance: ActivityManager

# 活动类型枚举
enum ActivityType {
	NONE,           # 无活动
	CLASS,          # 上课
	STUDY,          # 自习
	DIALOGUE,       # 对话
	SPORTS,         # 体育活动
	MEAL,           # 用餐
	WALK,           # 行走/移动
	REST            # 休息
}

# 活动状态
enum ActivityState {
	IDLE,           # 空闲
	ACTIVE,         # 进行中
	PAUSED,         # 暂停
	ENDING          # 即将结束
}

# 活动记录类
class ActivityRecord:
	var agent_id: String
	var activity_type: ActivityType
	var activity_state: ActivityState
	var start_time: float          # 游戏时间（分钟）
	var last_click_time: float     # 上次Click时间
	var total_duration: float      # 总持续时间
	var current_duration: float    # 当前周期持续时间
	var context: Dictionary        # 活动上下文
	
	func _init(agent: String, type: ActivityType, game_time: float, ctx: Dictionary = {}):
		agent_id = agent
		activity_type = type
		activity_state = ActivityState.ACTIVE
		start_time = game_time
		last_click_time = game_time
		total_duration = 0.0
		current_duration = 0.0
		context = ctx

# 所有Agent的活动记录
# {agent_id: ActivityRecord}
var agent_activities: Dictionary = {}

# 信号
signal activity_started(agent_id: String, activity_type: ActivityType, start_time: float)
signal activity_updated(agent_id: String, duration: float, cumulative_gain: float)
signal activity_ended(agent_id: String, activity_type: ActivityType, total_duration: float, final_gain: float)
signal activity_interrupted(agent_id: String, reason: String)

func _ready():
	instance = self
	print("[ActivityManager] 活动管理系统初始化完成")
	
	# 连接到TimingSystem
	await get_tree().create_timer(0.5).timeout
	if TimingSystem.instance:
		TimingSystem.instance.click_triggered.connect(_on_click_triggered)
		print("[ActivityManager] 已连接到TimingSystem")

# Click触发回调 - 核心入口
func _on_click_triggered(game_time: float, day: int, click_num: int):
	print("\n[ActivityManager] ===== CLICK #%d 活动更新 =====" % click_num)
	
	# 遍历所有Agent，更新活动状态
	for agent_id in agent_activities.keys():
		var record = agent_activities[agent_id]
		_update_activity_on_click(agent_id, record, game_time)
	
	print("[ActivityManager] ===== 活动更新结束 =====\n")

# 更新单个Agent的活动状态
func _update_activity_on_click(agent_id: String, record: ActivityRecord, game_time: float):
	if record.activity_state != ActivityState.ACTIVE:
		return
	
	# 计算本次Click的持续时间
	var click_duration = game_time - record.last_click_time
	record.current_duration = click_duration
	record.total_duration += click_duration
	record.last_click_time = game_time
	
	# 获取活动上下文
	var room_name = record.context.get("room_name", "")
	var effort_level = record.context.get("effort_level", 0.5)
	
	# 计算本次Click的累积奖赏
	var cumulative_gain = 0.0
	if room_name and not room_name.is_empty():
		cumulative_gain = _calculate_cumulative_gain(agent_id, room_name, record.total_duration)
	
	print("[ActivityManager] %s 活动更新: %s, 本次持续%.1f分钟, 累计%.1f分钟, 收益%.3f" % [
		agent_id, 
		_get_activity_name(record.activity_type),
		click_duration,
		record.total_duration,
		cumulative_gain
	])
	
	# 发射信号
	activity_updated.emit(agent_id, record.total_duration, cumulative_gain)
	
	# 通过RewardSystem发放本次Click的奖赏增量
	_distribute_click_reward(agent_id, room_name, record.total_duration, click_duration, effort_level)

# 计算累积收益（使用MVT公式）
func _calculate_cumulative_gain(agent_id: String, room_name: String, total_time: float) -> float:
	if not RewardSystem.instance:
		return 0.0
	
	# 获取房间参数
	var room_data = RewardSystem.instance._get_room_objective_params(room_name)
	if room_data.is_empty():
		return 0.0
	
	var S = room_data.get("S", 0.5)
	var a = room_data.get("a", 0.5)
	
	# 计算累积收益 G(t) = (S/a)[1 - exp(-at)]
	if a < 0.001:
		a = 0.001
	
	var gain = (S / a) * (1.0 - exp(-a * total_time / 60.0))  # 时间转换为秒
	return clamp(gain, 0.0, 1.0)

# 发放本次Click的奖赏增量
func _distribute_click_reward(agent_id: String, room_name: String, total_time: float, click_duration: float, effort: float):
	if not RewardSystem.instance:
		return
	
	# 计算增量收益（本次Click的贡献）
	var gain_before = _calculate_cumulative_gain(agent_id, room_name, total_time - click_duration)
	var gain_after = _calculate_cumulative_gain(agent_id, room_name, total_time)
	var incremental_gain = gain_after - gain_before
	
	# 通过RewardSystem发放
	RewardSystem.instance.distribute_reward(agent_id, room_name, total_time / 60.0)

# ============================================
# 公共接口：活动管理
# ============================================

# 开始新活动
func start_activity(agent_id: String, activity_type: ActivityType, context: Dictionary = {}) -> bool:
	# 如果已有活动，先结束
	if agent_activities.has(agent_id):
		end_activity(agent_id, "开始新活动")
	
	var game_time = TimingSystem.instance.current_game_time if TimingSystem.instance else 0.0
	var record = ActivityRecord.new(agent_id, activity_type, game_time, context)
	agent_activities[agent_id] = record
	
	print("[ActivityManager] %s 开始活动: %s" % [agent_id, _get_activity_name(activity_type)])
	activity_started.emit(agent_id, activity_type, game_time)
	
	return true

# 结束活动
func end_activity(agent_id: String, reason: String = "") -> Dictionary:
	if not agent_activities.has(agent_id):
		return {}
	
	var record = agent_activities[agent_id]
	var game_time = TimingSystem.instance.current_game_time if TimingSystem.instance else record.last_click_time
	
	# 计算最终收益
	var final_gain = 0.0
	var room_name = record.context.get("room_name", "")
	if room_name:
		final_gain = _calculate_cumulative_gain(agent_id, room_name, record.total_duration)
	
	var result = {
		"agent_id": agent_id,
		"activity_type": record.activity_type,
		"activity_name": _get_activity_name(record.activity_type),
		"total_duration": record.total_duration,
		"final_gain": final_gain,
		"reason": reason
	}
	
	print("[ActivityManager] %s 结束活动: %s, 总时长%.1f分钟, 最终收益%.3f, 原因: %s" % [
		agent_id,
		_get_activity_name(record.activity_type),
		record.total_duration,
		final_gain,
		reason
	])
	
	activity_ended.emit(agent_id, record.activity_type, record.total_duration, final_gain)
	agent_activities.erase(agent_id)
	
	return result

# 中断活动（被外部事件打断）
func interrupt_activity(agent_id: String, reason: String):
	if not agent_activities.has(agent_id):
		return
	
	var record = agent_activities[agent_id]
	record.activity_state = ActivityState.PAUSED
	
	print("[ActivityManager] %s 活动被中断: %s, 原因: %s" % [
		agent_id,
		_get_activity_name(record.activity_type),
		reason
	])
	
	activity_interrupted.emit(agent_id, reason)

# 恢复活动
func resume_activity(agent_id: String):
	if not agent_activities.has(agent_id):
		return
	
	var record = agent_activities[agent_id]
	if record.activity_state == ActivityState.PAUSED:
		record.activity_state = ActivityState.ACTIVE
		record.last_click_time = TimingSystem.instance.current_game_time if TimingSystem.instance else 0.0
		
		print("[ActivityManager] %s 恢复活动: %s" % [
			agent_id,
			_get_activity_name(record.activity_type)
		])

# 获取Agent当前活动信息
func get_activity_info(agent_id: String) -> Dictionary:
	if not agent_activities.has(agent_id):
		return {
			"has_activity": false,
			"activity_type": ActivityType.NONE,
			"activity_name": "无",
			"duration": 0.0,
			"state": ActivityState.IDLE
		}
	
	var record = agent_activities[agent_id]
	var current_time = TimingSystem.instance.current_game_time if TimingSystem.instance else record.last_click_time
	var real_time_duration = current_time - record.start_time
	
	return {
		"has_activity": true,
		"activity_type": record.activity_type,
		"activity_name": _get_activity_name(record.activity_type),
		"start_time": record.start_time,
		"duration": record.total_duration,
		"real_time_duration": real_time_duration,
		"state": record.activity_state,
		"context": record.context
	}

# 检查Agent是否有活动
func has_activity(agent_id: String) -> bool:
	return agent_activities.has(agent_id)

# 获取活动名称
func _get_activity_name(type: ActivityType) -> String:
	match type:
		ActivityType.CLASS: return "上课"
		ActivityType.STUDY: return "自习"
		ActivityType.DIALOGUE: return "对话"
		ActivityType.SPORTS: return "体育活动"
		ActivityType.MEAL: return "用餐"
		ActivityType.WALK: return "行走"
		ActivityType.REST: return "休息"
		_: return "无"

# ============================================
# 查询接口
# ============================================

# 获取所有活跃活动
func get_all_active_activities() -> Array:
	var result = []
	for agent_id in agent_activities.keys():
		var record = agent_activities[agent_id]
		if record.activity_state == ActivityState.ACTIVE:
			result.append({
				"agent_id": agent_id,
				"activity_type": record.activity_type,
				"duration": record.total_duration
			})
	return result

# 获取特定类型的所有活动
func get_activities_by_type(type: ActivityType) -> Array:
	var result = []
	for agent_id in agent_activities.keys():
		var record = agent_activities[agent_id]
		if record.activity_type == type:
			result.append({
				"agent_id": agent_id,
				"duration": record.total_duration,
				"state": record.activity_state
			})
	return result

# 重置所有活动（用于重新开始模拟）
func reset():
	print("[ActivityManager] 重置所有活动")
	agent_activities.clear()
