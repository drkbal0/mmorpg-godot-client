extends SceneTree
## Captura visual del Paso 13 UI v2.4: Diálogo cinematográfico con PNJ y Muerte / recap táctico.
## Run: Godot --path clients/godot-mmo-client --rendering-driver opengl3 -s tests/unit/capture_dialogue_and_death_recap.gd
##      (en --headless no hay framebuffer: se conserva la evidencia existente)
## Salida: test_evidence/dialogue_window_cinematic.png, dialogue_options_active.png,
##         death_window_overview.png y death_window_resurrecting.png

const DS = preload("res://shared-core/DialogueService.gd")
const DR = preload("res://shared-core/DeathRecapService.gd")
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


## Fondo del mundo (el mismo «mapa-fondo» del HTML) para ver el letterbox y el filtro gris.
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
	root.size = Vector2i(1280, 720)
	if not _headless:
		DisplayServer.window_set_size(Vector2i(1280, 720))
	_world()

	# ------------------------------------------------------------------
	# Diálogo con Mira
	# ------------------------------------------------------------------
	var ds: Node = DS.new()
	ds.load_seed()
	var w = load("res://ui/windows/DialogueWindow/DialogueWindow.tscn").instantiate()
	if w.get_script() == null:
		printerr("[capture] DialogueWindow sin script (error de parseo)")
		quit(1)
		return
	w.service = ds
	root.add_child(w)
	w.initialize_window({"npc_id": "mira", "dialogue_node_id": "intro"})

	# 1. Letterbox: primer fragmento con cursor ▍, relación Aliada (3/5) y la opción 1 resaltada.
	await _shot("dialogue_window_cinematic")

	# 2. Texto completo (Espacio), resaltado en la rama alternativa [2] e historial [H] abierto.
	w.handle_key(KEY_SPACE)
	w.handle_key(KEY_DOWN)
	w.handle_key(KEY_H)
	await _shot("dialogue_options_active")
	w.queue_free()
	await process_frame

	# ------------------------------------------------------------------
	# Muerte y recap táctico
	# ------------------------------------------------------------------
	var dr: Node = DR.new()
	dr.load_seed()
	dr.auto_tick = false
	var d = load("res://ui/windows/DeathWindow/DeathWindow.tscn").instantiate()
	d.service = dr
	root.add_child(d)
	d.initialize_window({})

	# 3. «Has caído»: últimos 5 s, evitables, consejo del escudo, Brisa al 60 % y 0:12.
	await _shot("death_window_overview")

	# 4. Resurrección en curso al 90 % con aceptación manual y repetición [R] pedida.
	d.handle_key(KEY_A)
	dr.tick(1.2)
	d.handle_key(KEY_R)
	await _shot("death_window_resurrecting")
	d.queue_free()
	await process_frame

	var expected := ["dialogue_window_cinematic", "dialogue_options_active", "death_window_overview", "death_window_resurrecting"]
	var ok := expected.all(func(f) -> bool: return _saved.has(f))
	print("[capture] %d capturas: %s" % [_saved.size(), ", ".join(_saved)])
	quit(0 if ok else 1)
