# 动态特质变化示例
# 这个文件展示了如何在游戏过程中使用 DynamicPersonality 系统

extends Node

class_name DynamicPersonalityExample

# 示例1：任务成功时自动更新特质
func example_task_success(character: Node):
	# 当 StudentXiaoming 成功完成数学作业时
	# 这会：
	# - 提升 self_efficacy（自我效能感）+15%
	# - 降低 effort_sensitivity（努力敏感性）-10%
	# - 提升 motivation_level（动机水平）+10%
	# - 自动添加记忆记录这些变化
	DynamicPersonality.apply_event_effect(character, "task_success")

# 示例2：任务失败时自动更新特质
func example_task_failure(character: Node):
	# 当 StudentXiaoming 考试不及格时
	# 这会：
	# - 降低 self_efficacy（自我效能感）-10%
	# - 提升 effort_sensitivity（努力敏感性）+15%
	# - 降低 motivation_level（动机水平）-15%
	DynamicPersonality.apply_event_effect(character, "task_failure")

# 示例3：积极社交互动
func example_positive_social(character: Node):
	# 当 StudentXiaoming 和老师愉快交流后
	# 这会：
	# - 提升 attachment_security（依恋安全感）+10%
	# - 提升 motivation_level（动机水平）+5%
	DynamicPersonality.apply_event_effect(character, "social_positive")

# 示例4：消极社交互动
func example_negative_social(character: Node):
	# 当 StudentXiaoming 被同学欺负后
	# 这会：
	# - 降低 attachment_security（依恋安全感）-10%
	# - 提升 effort_sensitivity（努力敏感性）+10%
	DynamicPersonality.apply_event_effect(character, "social_negative")

# 示例5：受到表扬
func example_praise(character: Node):
	# 当 StudentXiaoming 被表扬时
	# 这会：
	# - 提升 self_efficacy（自我效能感）+10%
	# - 提升 motivation_level（动机水平）+10%
	DynamicPersonality.apply_event_effect(character, "praise_received")

# 示例6：受到批评
func example_criticism(character: Node):
	# 当 StudentXiaoming 被批评时
	# 这会：
	# - 降低 self_efficacy（自我效能感）-10%
	# - 提升 effort_sensitivity（努力敏感性）+15%
	DynamicPersonality.apply_event_effect(character, "criticism_received")

# 示例7：手动精确调整特质
func example_manual_adjustment(character: Node):
	# 如果需要更精确的控制，可以直接更新特定特质
	
	# 例如：经过一次成功的演讲后，大幅提升自信
	DynamicPersonality.update_trait(
		character, 
		"self_efficacy", 
		0.25,  # 提升25%
		"成功完成了一次班级演讲，同学们都为你鼓掌"
	)
	
	# 同时降低努力敏感性
	DynamicPersonality.update_trait(
		character,
		"effort_sensitivity",
		-0.15,  # 降低15%
		"发现准备演讲并没有想象中那么困难"
	)

# 示例8：在AI决策中读取当前特质
func example_read_traits_in_prompt(character: Node) -> String:
	# 获取当前特质值
	var traits = DynamicPersonality.get_dynamic_traits(character)
	
	var self_efficacy = traits.get("self_efficacy", 0.5)
	var effort_sensitivity = traits.get("effort_sensitivity", 0.5)
	var motivation_level = traits.get("motivation_level", 0.5)
	
	# 根据特质生成不同的提示词
	var prompt = ""
	
	if self_efficacy < 0.3:
		prompt += "你对自己很没有信心，总是觉得自己做不好事情。"
	elif self_efficacy > 0.7:
		prompt += "你对自己很有信心，相信自己能够完成任务。"
	
	if effort_sensitivity > 0.7:
		prompt += "你觉得很多事情都很费力，不太愿意付出努力。"
	elif effort_sensitivity < 0.3:
		prompt += "你觉得大多数事情都不会太费力，愿意尝试。"
	
	if motivation_level < 0.3:
		prompt += "你感到缺乏动力，对很多事情提不起兴趣。"
	elif motivation_level > 0.7:
		prompt += "你充满动力，积极主动地想要做事情。"
	
	return prompt

# 示例9：检查特质变化并触发特殊事件
func example_check_trait_changes(character: Node):
	var traits = DynamicPersonality.get_dynamic_traits(character)
	
	# 检查是否进入严重抑郁状态
	if traits.get("motivation_level", 0.5) < 0.2 and traits.get("self_efficacy", 0.5) < 0.2:
		# 触发特殊事件：老师注意到学生的异常
		print("%s 的心理状态需要关注！" % character.name)
		# 可以在这里触发 TeacherWang 主动来找 StudentXiaoming 对话
	
	# 检查是否恢复良好
	if traits.get("motivation_level", 0.5) > 0.6 and traits.get("self_efficacy", 0.5) > 0.6:
		print("%s 的心理状态明显改善！" % character.name)
		# 可以在这里触发积极事件

# 示例10：特质对决策的影响
func example_trait_affects_decision(character: Node, task_difficulty: String) -> String:
	var traits = DynamicPersonality.get_dynamic_traits(character)
	var effort_sensitivity = traits.get("effort_sensitivity", 0.5)
	var self_efficacy = traits.get("self_efficacy", 0.5)
	
	# 高努力敏感性 + 低自我效能感 = 倾向于回避困难任务
	if effort_sensitivity > 0.7 and self_efficacy < 0.4:
		if task_difficulty == "困难":
			return "回避"
		elif task_difficulty == "中等":
			return "犹豫"
	
	# 低努力敏感性 + 高自我效能感 = 积极接受挑战
	if effort_sensitivity < 0.4 and self_efficacy > 0.6:
		return "积极接受"
	
	return "正常对待"
