extends SceneTree
## Captura visual del Paso 17 UI v2.4 (ADR 115): HUD de raid extendido para sanador.
## Run: Godot --path clients/godot-mmo-client --rendering-driver opengl3 -s tests/unit/capture_raid_hud_and_consolidation.gd
##      (en --headless no hay framebuffer: se conserva la evidencia existente)
## Salida (test_evidence/):
##   raid_hud_20players.png            vista general: 20 integrantes, jefe colosal y alerta central
##   raid_healer_clickcast.png         detalle de click-casting: curación, escudo, purificación y selección
##   raid_boss_and_tactical_alert.png  detalle de la barra del jefe y la tarjeta de alerta
##   raid_healer_compact_bar.png       consola inferior compacta con la proyección de maná

const RS = preload("res://shared-core/RaidService.gd")
const SCENE := "res://ui/windows/RaidHUDWindow/RaidHUDWindow.tscn"
const SIZE := Vector2i(1440, 810)

var _saved: Array[String] = []
var _headless := false


func _initialize() -> void:
	_run.call_deferred()


## Guarda el framebuffer completo o el recorte `crop` (px del escenario 1440×810).
func _shot(file_name: String, crop: Rect2i = Rect2i()) -> void:
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
	if crop.size != Vector2i.ZERO:
		var k := float(img.get_width()) / float(SIZE.x)
		var r := Rect2i(Vector2i(Vector2(crop.position) * k), Vector2i(Vector2(crop.size) * k))
		img = img.get_region(r.intersection(Rect2i(Vector2i.ZERO, img.get_size())))
	var err := img.save_png(path)
	if err == OK:
		_saved.append(file_name)
	print("[capture] %s.png %dx%d (%s)" % [file_name, img.get_width(), img.get_height(), "ok" if err == OK else "error %d" % err])


## Servicio aislado (sin reloj automático): reproduce el estado exacto del HTML.
func _raid() -> Node:
	var r: Node = RS.new()
	r.auto_tick = false
	r.load_seed()
	return r


func _window(r: Node, params: Dictionary = {}) -> Node:
	var w = load(SCENE).instantiate()
	w.raid = r
	root.add_child(w)
	var p := {"backdrop": true}
	p.merge(params, true)
	w.initialize_window(p)
	return w


func _run() -> void:
	_headless = DisplayServer.get_name() == "headless"
	root.size = SIZE
	if not _headless:
		DisplayServer.window_set_size(SIZE)

	# 1. Vista general (estado del diseño): 20 integrantes, jefe en Fase 2 al 43 %, alerta «3».
	var r1 := _raid()
	var w1 = _window(r1)
	await _shot("raid_hud_20players")
	w1.queue_free()
	await process_frame

	# 2. Click-casting: Shift+clic purifica a Joao, clic izq. cura a Dren (queda seleccionado),
	#    clic der. escuda a Pim y clic izq. resucita a Ivo. Recorte de la cuadrícula.
	var r2 := _raid()
	var w2 = _window(r2)
	w2.click_member("joao", MOUSE_BUTTON_LEFT, true)
	w2.click_member("pim", MOUSE_BUTTON_RIGHT)
	w2.click_member("ivo", MOUSE_BUTTON_LEFT)
	w2.click_member("dren", MOUSE_BUTTON_LEFT)
	await _shot("raid_healer_clickcast", Rect2i(20, 270, 600, 320))
	w2.queue_free()
	await process_frame

	# 3. Jefe y alerta táctica: recorte superior centrado.
	var r3 := _raid()
	var w3 = _window(r3)
	await _shot("raid_boss_and_tactical_alert", Rect2i(400, 0, 640, 280))
	w3.queue_free()
	await process_frame

	# 4. Consola compacta del sanador: recorte inferior (trapecio, vida, maná y 10 ranuras).
	var r4 := _raid()
	var w4 = _window(r4)
	await _shot("raid_healer_compact_bar", Rect2i(360, 660, 720, 150))
	w4.queue_free()
	await process_frame

	var expected := [
		"raid_hud_20players",
		"raid_healer_clickcast",
		"raid_boss_and_tactical_alert",
		"raid_healer_compact_bar",
	]
	var ok := expected.all(func(f) -> bool: return _saved.has(f))
	print("[capture] %d capturas: %s" % [_saved.size(), ", ".join(_saved)])
	quit(0 if ok else 1)
