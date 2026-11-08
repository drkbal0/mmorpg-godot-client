extends SceneTree

func _init():
	print("--- TEST EVAL START ---")
	var target_node = null
	var spawn_pos = target_node.global_position + Vector3(0, 2.0, 0) if target_node else Vector3(0, 2, 8)
	print("RESULT: ", spawn_pos)
	quit()
