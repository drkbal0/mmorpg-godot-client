extends SceneTree
## Captura visual del Paso 16 UI v2.4 (ADR 114): Ajustes globales y Editor de interfaz.
## Run: Godot --path clients/godot-mmo-client --rendering-driver opengl3 -s tests/unit/capture_settings_and_ui_editor.gd
##      (en --headless no hay framebuffer: se conserva la evidencia existente)
## Salida: test_evidence/settings_graphics_performance.png, settings_audio_buses.png,
##         settings_controls_conflict.png, ui_editor_drag_drop_grid.png y ui_editor_module_properties.png

const SS = preload("res://shared-core/SettingsService.gd")
const ES = preload("res://shared-core/UIEditorService.gd")
const SETTINGS_SCENE := "res://ui/windows/SettingsWindow/SettingsWindow.tscn"
const EDITOR_SCENE := "res://ui/windows/UIEditorWindow/UIEditorWindow.tscn"

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


## Servicios aislados: no tocan user://settings.cfg, user://ui_layouts.cfg ni el motor.
func _settings() -> Node:
	var s: Node = SS.new()
	s.load_seed()
	s.autosave = false
	s.apply_to_engine = false
	s.auto_tick = false
	return s


func _editor() -> Node:
	var e: Node = ES.new()
	e.load_seed()
	e.autosave = false
	return e


func _settings_window(s: Node) -> Node:
	var w = load(SETTINGS_SCENE).instantiate()
	w.settings = s
	root.add_child(w)
	w.initialize_window({})
	return w


func _run() -> void:
	_headless = DisplayServer.get_name() == "headless"
	root.size = Vector2i(1440, 810)
	if not _headless:
		DisplayServer.window_set_size(Vector2i(1440, 810))

	# 1. Gráficos + rendimiento estimado + búsqueda «sombras» + 3 cambios sin aplicar (como el HTML).
	var s1 := _settings()
	s1.set_value("interface", "chat_opacity", 60)
	s1.set_value("accessibility", "narrator", true)
	s1.set_value("network", "telemetry_rate", 30)
	var w1 = _settings_window(s1)
	w1.set_search("sombras")
	await _shot("settings_graphics_performance")
	w1.queue_free()
	await process_frame

	# 2. Sonido: los 5 buses con volúmenes distintos y Ambiente silenciado.
	var s2 := _settings()
	for kv in [["Master", 80], ["Music", 60], ["SFX", 90], ["Ambience", 70], ["UI", 75]]:
		s2.set_bus_volume(kv[0], kv[1])
	s2.apply()
	s2.set_bus_muted("Ambience", true)
	var w2 = _settings_window(s2)
	w2.select_category("audio")
	await _shot("settings_audio_buses")
	w2.queue_free()
	await process_frame

	# 3. Controles: atajo repetido G (Señales y Montura) con la solución «Montura → Z».
	var s3 := _settings()
	var w3 = _settings_window(s3)
	w3.select_category("controls")
	for i in 3:
		await process_frame
	w3.options_scroll.ensure_control_visible(w3.option_rows["mount"])
	await _shot("settings_controls_conflict")
	w3.queue_free()
	await process_frame

	# 4. Editor: arrastre de la Línea de tiempo con cuadrícula y guía rosa «alineado con Objetivo».
	var s4 := _settings()
	var e4 := _editor()
	var w4 = load(EDITOR_SCENE).instantiate()
	w4.settings = s4
	w4.editor = e4
	root.add_child(w4)
	w4.initialize_window({})
	e4.begin_drag("timeline")
	e4.drag_to(Vector2(304, 112))
	await _shot("ui_editor_drag_drop_grid")
	e4.end_drag()
	w4.queue_free()
	await process_frame

	# 5. Editor: propiedades del módulo seleccionado (Chat al 120 % y 60 % fuera de combate),
	#    diseño Sanador y accesibilidad (Deutan., texto grande).
	var s5 := _settings()
	var e5 := _editor()
	var w5 = load(EDITOR_SCENE).instantiate()
	w5.settings = s5
	w5.editor = e5
	root.add_child(w5)
	w5.initialize_window({"preset": "healer", "module": "chat_box"})
	w5.set_scale_percent(120)
	w5.set_opacity_percent(60)
	w5.set_color_mode("deuteranopia")
	w5.set_a11y("large_text", true)
	await _shot("ui_editor_module_properties")
	w5.queue_free()
	await process_frame

	var expected := [
		"settings_graphics_performance",
		"settings_audio_buses",
		"settings_controls_conflict",
		"ui_editor_drag_drop_grid",
		"ui_editor_module_properties",
	]
	var ok := expected.all(func(f) -> bool: return _saved.has(f))
	print("[capture] %d capturas: %s" % [_saved.size(), ", ".join(_saved)])
	quit(0 if ok else 1)
