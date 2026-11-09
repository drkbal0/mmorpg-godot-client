extends SceneTree
## Renders the HUDv2 demo (needs a real renderer, NOT --headless) and saves one
## screenshot per shape into res://test_evidence/.
## Run: Godot --path clients/godot-mmo-client -s res://tests/unit/capture_hud_v2.gd

const SHAPES := ["trapecio", "escalonada", "curva"]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1600, 540)
	var demo: Control = load("res://ui/hud_demo.tscn").instantiate()
	root.add_child(demo)
	demo.get_node("Tick").stop()
	for i in 3:
		await process_frame
	demo._cast(1)
	demo.hud.set_ability(0, 2, 5, 24, false, 6, 0.0)
	for s in SHAPES:
		demo.hud.set_shape(s)
		for i in 20:
			await process_frame
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		var path := ProjectSettings.globalize_path("res://test_evidence/hud_v2_%s.png" % s)
		img.save_png(path)
		print("saved ", path)
	quit(0)
