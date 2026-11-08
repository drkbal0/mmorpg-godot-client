extends Control

func _ready():
	if has_node("/root/UIOrchestrator"):
		var orch = get_node("/root/UIOrchestrator")
		# Capturamos el visual y el offset de los metadatos
		var visual = get_meta("visual")
		var offset = get_meta("click_offset") if has_meta("click_offset") else Vector2.ZERO
		
		orch.start_drag_follow(visual, offset)

func _exit_tree():
	if has_node("/root/UIOrchestrator"):
		get_node("/root/UIOrchestrator").stop_drag_follow()
