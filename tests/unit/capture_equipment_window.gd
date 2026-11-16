extends SceneTree
## Captura visual (no headless) del Paso 10 UI v2.4: Equipo e inventario [C].
## Run: Godot --rendering-driver opengl3 --path clients/godot-mmo-client -s tests/unit/capture_equipment_window.gd
## Salida: test_evidence/equipment_overview.png, equipment_stat_comparison.png y equipment_set_swap.png

const ES = preload("res://shared-core/EquipmentService.gd")
const COM = preload("res://shared-core/CommerceService.gd")

var _saved: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _shot(file_name: String) -> void:
	for i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_evidence"))
	var path := "res://test_evidence/%s.png" % file_name
	var err := img.save_png(path)
	if err == OK:
		_saved.append(file_name)
	print("[capture] %s.png (%s)" % [file_name, "ok" if err == OK else "error %d" % err])


func _find_cell(w: Control, item_id: String) -> Control:
	for c in w.grid_cells:
		if c.item_id == item_id:
			return c
	return null


func _run() -> void:
	root.size = Vector2i(1280, 720)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	var bg := ColorRect.new()
	bg.color = Color("#05080a")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)

	var commerce: Node = COM.new()
	commerce.load_seed()
	root.add_child(commerce)
	var svc: Node = ES.new()
	svc.load_seed()
	root.add_child(svc)

	var w = load("res://ui/windows/EquipmentWindow/EquipmentWindow.tscn").instantiate()
	if w.get_script() == null:
		printerr("[capture] EquipmentWindow sin script (error de parseo)")
		quit(1)
		return
	w.service = svc
	w.commerce = commerce
	root.add_child(w)
	await process_frame
	w.position = Vector2(5, 20)
	w.fit_to_viewport()

	# 1. Vista general: paperdoll del conjunto Daño (iLvl 412) y las 16 estadísticas.
	w.avatar.rotate_by(0.35)
	await _shot("equipment_overview")

	# 2. Comparación: hover sobre «Anillo de la deriva» (▲ celeridad/daño, ▼ armadura).
	var cell: Control = _find_cell(w, "anillo_deriva")
	if cell:
		cell.hovered = true
		cell.queue_redraw()
		w._on_cell_hover(cell)
	await _shot("equipment_stat_comparison")
	if cell:
		cell.hovered = false
		cell.queue_redraw()
	w.clear_preview()

	# 3. Cambio de conjunto: F1 Daño -> F2 Tanque (yelmo, coraza, escudo y mandoble de bastión).
	var ev := InputEventKey.new()
	ev.keycode = KEY_F2
	ev.pressed = true
	w.handle_key(ev)
	var shield: Control = w.doll_slots["off_hand"]
	shield.hovered = true
	shield.queue_redraw()
	await _shot("equipment_set_swap")

	w.queue_free()
	await process_frame
	var expected := ["equipment_overview", "equipment_stat_comparison", "equipment_set_swap"]
	var ok := expected.all(func(f) -> bool: return _saved.has(f))
	print("[capture] %d capturas guardadas: %s" % [_saved.size(), ", ".join(_saved)])
	quit(0 if ok else 1)
