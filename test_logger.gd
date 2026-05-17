extends Node

# 测试Logger系统的脚本
# 运行此脚本可以验证日志输出功能是否正常

func _ready():
	print("=== 测试Logger系统 ===")
	
	# 等待Logger初始化
	await get_tree().create_timer(0.5).timeout
	
	var logger = get_node_or_null("/root/Logger")
	if not logger:
		push_error("Logger未找到！")
		return
	
	print("Logger已找到，开始测试...")
	
	# 测试活动日志
	logger.log_activity("测试角色", "测试活动", "测试位置")
	print("✓ 活动日志测试完成")
	
	# 测试内心独白日志
	logger.log_monologue("测试角色", "测试任务", "这是一个测试内心独白")
	print("✓ 内心独白日志测试完成")
	
	# 测试对话日志
	logger.log_dialogue("角色A", "角色B", "测试对话内容", "教室")
	print("✓ 对话日志测试完成")
	
	# 测试每日反思日志
	var test_reflection = {
		"reflection_report": {
			"emotional_theme": "测试情绪主题",
			"key_events": [
				{"event": "测试事件1", "impact": "高", "psychological_effect": "测试心理影响"}
			],
			"cognitive_changes": {
				"environment_expectation": "测试环境预期",
				"effort_attitude": "测试努力态度",
				"reward_sensitivity": "测试奖赏敏感度",
				"time_pressure": "测试时间压力"
			}
		},
		"phq9_assessment": {
			"total_score": 12,
			"severity_level": "中度抑郁",
			"phq9_scores": [
				{"item": "测试症状", "score": 2, "reason": "测试原因"}
			]
		},
		"adjustments": [
			{"parameter": "beta_effort", "direction": "↑", "magnitude": 0.05, "reason": "测试调整原因"}
		]
	}
	logger.log_daily_reflection("测试角色", test_reflection)
	print("✓ 每日反思日志测试完成")
	
	# 测试认知参数日志
	var test_params = {
		"daily_depression_level": 0.5,
		"p_base": 0.6,
		"eta_s": 0.4,
		"eta_a": 0.5,
		"beta_effort": 0.7
	}
	logger.log_cognitive_params("测试角色", test_params, "测试认知参数变化")
	print("✓ 认知参数日志测试完成")
	
	# 测试批量记录
	var batch_params = {
		"角色A": {"daily_depression_level": 0.3, "p_base": 0.5, "eta_s": 0.5, "eta_a": 0.5, "beta_effort": 0.4},
		"角色B": {"daily_depression_level": 0.7, "p_base": 0.4, "eta_s": 0.3, "eta_a": 0.6, "beta_effort": 0.8}
	}
	logger.log_cognitive_params_batch(batch_params)
	print("✓ 批量认知参数日志测试完成")
	
	print("\n=== 所有测试完成 ===")
	print("日志文件位置: /Users/yuke/Desktop/Microverse_Logs/")
	print("  - activity_log.txt")
	print("  - monologue_log.txt")
	print("  - dialogue_log.txt")
	print("  - reflection_log.txt (新增)")
	print("  - cognitive_params_log.txt (新增)")
