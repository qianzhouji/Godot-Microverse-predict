extends Node2D

# SceneInitializer - 场景初始化器
# 负责在场景加载完成后启动各个系统

func _ready():
	print("[SceneInitializer] 场景初始化开始...")
	
	# 延迟启动，确保所有系统都已初始化
	await get_tree().create_timer(2.0).timeout
	
	# 启动时序系统
	if TimingSystem.instance:
		print("[SceneInitializer] 启动TimingSystem...")
		TimingSystem.instance.start_day(1)
	else:
		push_error("[SceneInitializer] TimingSystem未找到")
	
	print("[SceneInitializer] 场景初始化完成")
