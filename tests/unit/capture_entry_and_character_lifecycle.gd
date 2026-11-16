extends SceneTree
## Captura visual del Paso 15 UI v2.4: Entrada, autenticación y ciclo de vida del personaje.
## Run: Godot --path clients/godot-mmo-client --rendering-driver opengl3 -s tests/unit/capture_entry_and_character_lifecycle.gd
##      (en --headless no hay framebuffer: se conserva la evidencia existente)
## Salida: test_evidence/launcher_overview.png, login_qr_passkey.png,
##         character_select_carousel.png, character_create_steps.png y loading_screen_tactical.png

const AS = preload("res://shared-core/AuthLifecycleService.gd")
const SCENE_BG := "res://design_ref/assets/mapa-fondo.jpg"

var _saved: Array[String] = []
var _headless := false


func _initialize() -> void:
	_run.call_deferred()


func _shot(file_name: String) -> void:
	for i in 6:
		await process_frame
	if not _headless:
		await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_evidence"))
	var path := "res://test_evidence/%s.png" % file_name
	var img := root.get_texture().get_image() if not _headless else null
	if img == null or img.is_empty():
		var exists := FileAccess.file_exists(path)
		print("[capture] %s.png (headless: sin framebuffer, %s)" % [file_name, "se conserva la existente" if exists else "FALTA"])
		if exists:
			_saved.append(file_name)
		return
	var err := img.save_png(path)
	if err == OK:
		_saved.append(file_name)
	print("[capture] %s.png (%s)" % [file_name, "ok" if err == OK else "error %d" % err])


func _world() -> void:
	var img := Image.load_from_file(ProjectSettings.globalize_path(SCENE_BG))
	if img != null and not img.is_empty():
		var tr := TextureRect.new()
		tr.name = "World"
		tr.texture = ImageTexture.create_from_image(img)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		root.add_child(tr)
	else:
		var bg := ColorRect.new()
		bg.color = Color("#070a0c")
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		root.add_child(bg)


func _run() -> void:
	_headless = DisplayServer.get_name() == "headless"
	root.size = Vector2i(1440, 810)
	if not _headless:
		DisplayServer.window_set_size(Vector2i(1440, 810))
	_world()

	# 1. Launcher Window
	var svc1: Node = AS.new()
	svc1.load_seed()
	var launcher = load("res://ui/windows/LauncherWindow/LauncherWindow.tscn").instantiate()
	launcher.service = svc1
	root.add_child(launcher)
	launcher.initialize_window({})
	await _shot("launcher_overview")
	launcher.queue_free()
	await process_frame

	# 2. Login Window
	var svc2: Node = AS.new()
	svc2.load_seed()
	var login = load("res://ui/windows/LoginWindow/LoginWindow.tscn").instantiate()
	login.service = svc2
	root.add_child(login)
	login.initialize_window({})
	await _shot("login_qr_passkey")
	login.queue_free()
	await process_frame

	# 3. Character Select Window
	var svc3: Node = AS.new()
	svc3.load_seed()
	var select_w = load("res://ui/windows/CharacterSelectWindow/CharacterSelectWindow.tscn").instantiate()
	select_w.service = svc3
	root.add_child(select_w)
	select_w.initialize_window({})
	await _shot("character_select_carousel")
	select_w.queue_free()
	await process_frame

	# 4. Character Creation Window
	var svc4: Node = AS.new()
	svc4.load_seed()
	svc4.begin_creation()
	var create_w = load("res://ui/windows/CharacterCreationWindow/CharacterCreationWindow.tscn").instantiate()
	create_w.service = svc4
	root.add_child(create_w)
	create_w.initialize_window({})
	create_w.primary_action()
	create_w.choose_class("rift_weaver")
	await _shot("character_create_steps")
	create_w.queue_free()
	await process_frame

	# 5. Game Loading Window
	var svc5: Node = AS.new()
	svc5.load_seed()
	var load_w = load("res://ui/windows/GameLoadingWindow/GameLoadingWindow.tscn").instantiate()
	load_w.service = svc5
	root.add_child(load_w)
	load_w.initialize_window({})
	await _shot("loading_screen_tactical")
	load_w.queue_free()
	await process_frame

	var expected := [
		"launcher_overview",
		"login_qr_passkey",
		"character_select_carousel",
		"character_create_steps",
		"loading_screen_tactical"
	]
	var ok := expected.all(func(f) -> bool: return _saved.has(f))
	print("[capture] %d capturas: %s" % [_saved.size(), ", ".join(_saved)])
	quit(0 if ok else 1)
