extends SceneTree
## Captura visual del Paso 14 UI v2.4: Antesala y Resumen de mazmorra.
## Run: Godot --path clients/godot-mmo-client --rendering-driver opengl3 -s tests/unit/capture_dungeon_lobby_and_summary.gd
##      (en --headless no hay framebuffer: se conserva la evidencia existente)
## Salida: test_evidence/dungeon_lobby_5players.png, dungeon_lobby_ready_timer.png,
##         dungeon_summary_overview.png y dungeon_summary_group_praise.png

const LS = preload("res://shared-core/DungeonLobbyService.gd")
const SS = preload("res://shared-core/DungeonSummaryService.gd")
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


## Fondo del mundo (el mismo «mapa-fondo» del HTML) bajo el velo de la pantalla.
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
		bg.color = Color("#26331f")
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		root.add_child(bg)


func _run() -> void:
	_headless = DisplayServer.get_name() == "headless"
	root.size = Vector2i(1440, 810)
	if not _headless:
		DisplayServer.window_set_size(Vector2i(1440, 810))
	_world()

	# ------------------------------------------------------------------
	# Antesala
	# ------------------------------------------------------------------
	var ls: Node = LS.new()
	ls.load_seed()
	ls.auto_tick = false
	var w = load("res://ui/windows/DungeonLobbyWindow/DungeonLobbyWindow.tscn").instantiate()
	if w.get_script() == null:
		printerr("[capture] DungeonLobbyWindow sin script (error de parseo)")
		quit(1)
		return
	w.service = ls
	root.add_child(w)
	w.initialize_window({})

	# 1. Estado del HTML: 3 listos, Brisa cambiando a Sanación, Vela preparando, Nox al 41 %.
	await _shot("dungeon_lobby_5players")

	# 2. Los 5 listos y la cuenta atrás corriendo (0:17), «Iniciar ahora» activo.
	ls.ready_everyone()
	ls.tick(7.0)
	w._process(0.0)
	await _shot("dungeon_lobby_ready_timer")
	w.queue_free()
	await process_frame

	# ------------------------------------------------------------------
	# Resumen
	# ------------------------------------------------------------------
	var ss: Node = SS.new()
	ss.load_seed()
	var s = load("res://ui/windows/DungeonSummaryWindow/DungeonSummaryWindow.tscn").instantiate()
	s.service = ss
	root.add_child(s)
	s.initialize_window({})

	# 3. Las 3 columnas del HTML: botín inteligente, momentos (Brisa elogiada) y progreso.
	await _shot("dungeon_summary_overview")

	# 4. Elogios a Toro, Nox y Vela, la guja equipada y las hombreras ofrecidas a Toro.
	s.praise("toro")
	s.praise("nox")
	s.praise("vela")
	s.do_loot_action("guja_ferrum", "equip")
	s.do_loot_action("hombreras_vado", "offer")
	await _shot("dungeon_summary_group_praise")
	s.queue_free()
	await process_frame

	var expected := ["dungeon_lobby_5players", "dungeon_lobby_ready_timer", "dungeon_summary_overview", "dungeon_summary_group_praise"]
	var ok := expected.all(func(f) -> bool: return _saved.has(f))
	print("[capture] %d capturas: %s" % [_saved.size(), ", ".join(_saved)])
	quit(0 if ok else 1)
