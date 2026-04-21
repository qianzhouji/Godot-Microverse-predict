extends Node
class_name TimeUtils

# ============================================
# 时间工具类 - 统一全项目时序逻辑
# ============================================
# 核心原则：
# 1. 游戏时间统一使用分钟作为单位（TimingSystem.current_game_time）
# 2. 收益计算等物理公式需要秒时，使用 to_seconds() 转换
# 3. 所有时间获取都通过 TimingSystem，不要直接使用 Time.get_unix_time_from_system()
# ============================================

# 时间单位常量
const MINUTES_PER_HOUR: float = 60.0
const SECONDS_PER_MINUTE: float = 60.0
const SECONDS_PER_HOUR: float = 3600.0

# ============================================
# 统一获取游戏时间（分钟）
# ============================================

# 获取当前游戏时间（分钟）
# 这是获取游戏时间的唯一正确方式。
# 返回从0点开始计算的分钟数（如8:00 = 480.0）
static func get_game_time_minutes() -> float:
	if TimingSystem.instance:
		return TimingSystem.instance.current_game_time
	return 0.0

# 获取当前游戏时间（小时）
# 返回从0点开始计算的小时数（如8:00 = 8.0）
static func get_game_time_hours() -> float:
	return get_game_time_minutes() / MINUTES_PER_HOUR

# 获取当前游戏天数
static func get_game_day() -> int:
	if TimingSystem.instance:
		return TimingSystem.instance.current_day
	return 1

# ============================================
# 时间单位转换
# ============================================

# 将分钟转换为秒
# 用于收益计算等物理公式（因为衰减率a的单位是/秒）
static func to_seconds(minutes: float) -> float:
	return minutes * SECONDS_PER_MINUTE

# 将秒转换为分钟
static func to_minutes(seconds: float) -> float:
	return seconds / SECONDS_PER_MINUTE

# 将分钟转换为小时
static func to_hours(minutes: float) -> float:
	return minutes / MINUTES_PER_HOUR

# ============================================
# 时间格式化
# ============================================

# 将分钟格式化为 HH:MM
static func format_time(minutes: float) -> String:
	var h = int(minutes / MINUTES_PER_HOUR)
	var m = int(fmod(minutes, MINUTES_PER_HOUR))
	return "%02d:%02d" % [h, m]

# 格式化为 第X天 HH:MM
static func format_time_with_day(minutes: float, day: int = 0) -> String:
	var time_str = format_time(minutes)
	if day > 0:
		return "第%d天 %s" % [day, time_str]
	return time_str

# 获取当前游戏时间的格式化字符串
static func get_formatted_current_time() -> String:
	return format_time(get_game_time_minutes())

# ============================================
# 收益计算专用（MVT公式）
# ============================================

# 计算MVT累积收益 G(t) = (S/a)[1 - exp(-at)]
# 参数:
#   S: 初始收益率 (0-1)
#   a: 衰减率 (/分钟) - RoomArea中配置的单位
#   time_minutes: 停留时间（分钟）
# 返回: 累积收益 (0-1)
static func calculate_mvt_gain(S: float, a: float, time_minutes: float) -> float:
	if a < 0.001:
		a = 0.001
	
	# a的单位是/分钟，直接使用分钟计算，避免单位转换错误
	var gain = (S / a) * (1.0 - exp(-a * time_minutes))
	return clamp(gain, 0.0, 1.0)

# 计算MVT瞬时收益 g(t) = S * exp(-at)
# 用于判断是否应该离开当前情境（MVT离开规则）
# 注意：a的单位是/分钟，与time_minutes保持一致
static func calculate_mvt_instantaneous_gain(S: float, a: float, time_minutes: float) -> float:
	if a < 0.001:
		a = 0.001
	
	# a的单位是/分钟，直接使用分钟计算
	return S * exp(-a * time_minutes)

# ============================================
# 时间段检查
# ============================================

# 检查当前时间是否在指定小时范围内
static func is_time_in_range(current_minutes: float, start_hour: float, end_hour: float) -> bool:
	var current_hour = current_minutes / MINUTES_PER_HOUR
	return current_hour >= start_hour and current_hour < end_hour

# 获取当前时间段（用于Prompt）
static func get_current_period() -> String:
	var hour = get_game_time_hours()
	
	if hour < 8.0:
		return "早晨"
	elif hour < 12.0:
		return "上午"
	elif hour < 14.0:
		return "中午"
	elif hour < 17.0:
		return "下午"
	else:
		return "傍晚"

# ============================================
# 调试信息
# ============================================

# 获取时间调试信息
static func get_debug_info() -> Dictionary:
	return {
		"game_time_minutes": get_game_time_minutes(),
		"game_time_hours": get_game_time_hours(),
		"game_day": get_game_day(),
		"formatted": get_formatted_current_time(),
		"period": get_current_period()
	}

# 打印时间调试信息
static func print_debug_info():
	var info = get_debug_info()
	print("[TimeUtils] 游戏时间: %s (第%d天 %s, %.1f分钟/%.2f小时)" % [
		info.formatted,
		info.game_day,
		info.period,
		info.game_time_minutes,
		info.game_time_hours
	])
