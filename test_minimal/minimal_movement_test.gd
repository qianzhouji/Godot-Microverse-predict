extends Node2D

# 最小化移动功能测试
# 只测试 MovementExecutor + Activity 的核心功能

func _ready():
	print("\n========== 最小化移动测试 ==========\n")
	
	# 测试1: Activity 创建
	print("[测试1] Activity.create_move_to")
	var activity = Activity.create_move_to(Vector2(500, 300), "classroom")
	print("  类型: %s (期望: %s)" % [activity.activity_type, Activity.ActivityType.MOVE_TO])
	print("  名称: %s" % activity.activity_name)
	print("  参数: %s" % activity.parameters)
	print("  目标位置: %s" % activity.parameters.get("target_location", "MISSING"))
	print("  ✓ Activity 创建成功\n" if activity.parameters.get("target_location") == Vector2(500, 300) else "  ✗ Activity 创建失败\n")
	
	# 测试2: 坐标解析
	print("[测试2] 坐标格式解析")
	_test_coordinate_parsing()
	
	# 测试3: MovementExecutor 初始化
	print("[测试3] MovementExecutor 初始化")
	var mock_char = CharacterBody2D.new()
	mock_char.global_position = Vector2(100, 100)
	add_child(mock_char)
	
	var nav = NavigationAgent2D.new()
	mock_char.add_child(nav)
	
	var executor = MovementExecutor.new(mock_char, nav)
	print("  MovementExecutor 创建: %s" % ("✓ 成功" if executor else "✗ 失败"))
	
	# 测试4: 执行移动活动
	print("\n[测试4] 执行移动活动")
	var result = executor.execute_move_activity(activity)
	print("  执行结果: %s" % str(result))
	print("  %s" % ("✓ 移动成功" if result.success else "✗ 移动失败: " + result.reason))
	
	print("\n========== 测试结束 ==========\n")

func _test_coordinate_parsing():
	var test_cases = [
		{"name": "标准格式", "params": {"target_location": {"x": 100, "y": 200}}},
		{"name": "字符串坐标", "params": {"target_location": {"x": "150", "y": "250"}}},
		{"name": "直接字段", "params": {"x": 300, "y": 400}},
		{"name": "大写字段", "params": {"target_location": {"X": 500, "Y": 600}}},
		{"name": "缺失坐标", "params": {"target_room": "library"}},
	]
	
	for case in test_cases:
		var pos = _parse_target_location(case.params)
		var status = "✓" if pos != Vector2.ZERO else "✗"
		print("  %s %s: %s -> %s" % [status, case.name, case.params, pos])

func _parse_target_location(params: Dictionary) -> Vector2:
	var loc = params.get("target_location", {})
	
	# 尝试从 target_location 获取
	var x = loc.get("x", 0)
	var y = loc.get("y", 0)
	
	# 如果失败，尝试直接获取
	if x == 0 and y == 0:
		x = params.get("x", 0)
		y = params.get("y", 0)
	
	# 尝试大写字段
	if x == 0 and y == 0 and loc is Dictionary:
		x = loc.get("X", 0)
		y = loc.get("Y", 0)
	
	# 转换字符串
	if x is String: x = x.to_int()
	if y is String: y = y.to_int()
	
	return Vector2(x, y)
