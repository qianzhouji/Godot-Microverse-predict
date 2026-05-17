extends Node

# 调试脚本：检查Agent决策流程

func _ready():
	print("=== Agent决策流程调试 ===")
	
	# 等待游戏启动
	await get_tree().create_timer(2.0).timeout
	
	# 检查所有AIAgent的状态
	var agents = get_tree().get_nodes_in_group("ai_agents")
	print("\n找到 %d 个AIAgent" % agents.size())
	
	for agent in agents:
		print("\n--- Agent: %s ---" % agent.character.name)
		print("  current_state: %s" % agent.current_state)
		print("  activity_cache.size(): %d" % agent.activity_cache.size())
		print("  current_activity_index: %d" % agent.current_activity_index)
		print("  current_activity: %s" % agent.current_activity)
		print("  last_activity: %s" % agent.last_activity)
		
		# 检查是否有缓存但未执行
		if agent.activity_cache.size() > 0:
			print("  缓存活动:")
			for i in range(agent.activity_cache.size()):
				var act = agent.activity_cache[i]
				print("    [%d] %s (类型: %s)" % [i, act.activity_name, act.activity_type])
			print("  当前索引: %d, 是否还有未执行: %s" % [agent.current_activity_index, agent.current_activity_index < agent.activity_cache.size()])
	
	# 检查ActivityCoordinator
	if ActivityCoordinator.instance:
		print("\n--- ActivityCoordinator ---")
		print("  pending_decisions: %d" % ActivityCoordinator.instance.pending_decisions.size())
		print("  coordination_results: %d" % ActivityCoordinator.instance.coordination_results.size())
	
	# 检查TimingSystem
	if TimingSystem.instance:
		print("\n--- TimingSystem ---")
		print("  is_running: %s" % TimingSystem.instance.is_running)
		print("  current_game_time: %s" % TimingSystem.instance.format_time(TimingSystem.instance.current_game_time))
		print("  click_count: %d" % TimingSystem.instance.click_count)
