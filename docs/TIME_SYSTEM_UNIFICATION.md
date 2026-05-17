# 时间系统统一方案

## 核心原则

1. **游戏时间统一使用"分钟"作为单位**
   - `TimingSystem.current_game_time` 存储从0点开始的分钟数（如8:00 = 480.0）
   - 所有获取游戏时间的地方都通过 `TimeUtils.get_game_time_minutes()`

2. **物理公式需要秒时，使用 `TimeUtils.to_seconds()` 转换**
   - MVT收益公式中的衰减率 `a` 单位是 `/秒`
   - 所有收益计算都通过 `TimeUtils.calculate_mvt_gain()` 统一处理

3. **禁止直接使用 `Time.get_unix_time_from_system()` 获取游戏逻辑时间**
   - 仅用于现实时间戳（日志、存档等）
   - 游戏内时间逻辑必须使用 `TimeUtils`

## 时间工具类 (TimeUtils)

### 获取游戏时间
```gdscript
# 获取当前游戏时间（分钟）- 唯一正确方式
var game_time = TimeUtils.get_game_time_minutes()

# 获取当前游戏时间（小时）
var game_hours = TimeUtils.get_game_time_hours()

# 获取当前游戏天数
var game_day = TimeUtils.get_game_day()
```

### 时间单位转换
```gdscript
# 分钟 -> 秒（用于收益计算）
var seconds = TimeUtils.to_seconds(minutes)

# 秒 -> 分钟
var minutes = TimeUtils.to_minutes(seconds)

# 分钟 -> 小时
var hours = TimeUtils.to_hours(minutes)
```

### 收益计算（MVT公式）
```gdscript
# 计算累积收益 G(t) = (S/a)[1 - exp(-at)]
# time_minutes: 游戏时间（分钟），内部自动转换为秒
var gain = TimeUtils.calculate_mvt_gain(S, a, time_minutes)

# 计算瞬时收益 g(t) = S * exp(-at)
var instant_gain = TimeUtils.calculate_mvt_instantaneous_gain(S, a, time_minutes)
```

### 时间格式化
```gdscript
# 格式化为 HH:MM
var time_str = TimeUtils.format_time(minutes)

# 格式化为 "第X天 HH:MM"
var time_str = TimeUtils.format_time_with_day(minutes, day)

# 获取当前格式化时间
var current_str = TimeUtils.get_formatted_current_time()
```

## 已更新的文件

### 核心系统
- ✅ `TimeUtils.gd` - 新增时间工具类
- ✅ `TimingSystem.gd` - 保持原样（时间源）
- ✅ `RewardSystem.gd` - 使用 `TimeUtils.calculate_mvt_gain()`
- ✅ `ActivityManager.gd` - 使用 `TimeUtils.calculate_mvt_gain()`
- ✅ `RoomArea.gd` - 使用 `TimeUtils.calculate_mvt_gain()`

### AI系统
- ✅ `AIAgent.gd` - 使用 `TimeUtils.get_game_time_minutes()`
- ✅ `PerceptionSystem.gd` - 使用 `TimeUtils.calculate_mvt_gain()`
- ✅ `PromptBuilder.gd` - 使用 `TimeUtils.get_formatted_current_time()`
- ✅ `MemorySystem.gd` - 使用 `TimeUtils.get_game_time_minutes()`

### 其他
- ✅ `ActivityCoordinator.gd` - 使用 `TimeUtils.get_game_time_minutes()`
- ✅ `Logger.gd` - 使用 `TimeUtils.format_time_with_day()`

## 时间单位速查表

| 场景 | 单位 | 获取方式 |
|------|------|----------|
| 游戏时间存储 | 分钟 | `TimeUtils.get_game_time_minutes()` |
| 收益计算 | 秒（内部转换） | `TimeUtils.calculate_mvt_gain()` |
| 活动持续时间 | 分钟 | 直接使用游戏时间差 |
| 显示格式化 | HH:MM | `TimeUtils.format_time()` |
| 现实时间戳 | 秒 | `Time.get_unix_time_from_system()`（仅日志/存档） |

## 注意事项

1. **不要**在收益计算中手动乘以或除以60
   - ❌ `time * 60` 或 `time / 60`
   - ✅ `TimeUtils.to_seconds(time)` 或 `TimeUtils.calculate_mvt_gain()`

2. **不要**直接访问 `TimingSystem.instance.current_game_time`
   - ❌ `TimingSystem.instance.current_game_time`
   - ✅ `TimeUtils.get_game_time_minutes()`

3. **不要**使用 `Time.get_unix_time_from_system()` 获取游戏逻辑时间
   - ❌ `Time.get_unix_time_from_system()`
   - ✅ `TimeUtils.get_game_time_minutes()`

## 调试

```gdscript
# 打印时间调试信息
TimeUtils.print_debug_info()

# 获取时间调试字典
var info = TimeUtils.get_debug_info()
print(info.formatted)  # 如 "08:30"
print(info.game_day)   # 如 1
print(info.period)     # 如 "上午"
```
