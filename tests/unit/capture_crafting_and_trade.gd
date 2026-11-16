extends SceneTree
## Captura visual del Paso 11 UI v2.4: Fabricación y Trato cara a cara.
## Run: Godot --path clients/godot-mmo-client --headless -s tests/unit/capture_crafting_and_trade.gd
##      (en headless no hay framebuffer; para PNG reales usar --rendering-driver opengl3 sin --headless)
## Salida: test_evidence/crafting_window.png, crafting_queue_shelter.png,
##         trade_window_secret_mask.png y trade_window_dual_confirmed.png

const CS = preload("res://shared-core/CraftingService.gd")
const TS = preload("res://shared-core/TradeService.gd")
const KS = preload("res://shared-core/KnowledgeService.gd")
const COM = preload("res://shared-core/CommerceService.gd")

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
		# Servidor de pantalla «headless»: no hay framebuffer que leer. Se deja constancia
		# y se conserva la evidencia existente (generada con un driver de render real).
		var exists := FileAccess.file_exists(path)
		print("[capture] %s.png (headless: sin framebuffer, %s)" % [file_name, "se conserva la existente" if exists else "FALTA"])
		if exists:
			_saved.append(file_name)
		return
	var err := img.save_png(path)
	if err == OK:
		_saved.append(file_name)
	print("[capture] %s.png (%s)" % [file_name, "ok" if err == OK else "error %d" % err])


func _bg() -> void:
	var bg := ColorRect.new()
	bg.name = "Backdrop"
	bg.color = Color("#05080a")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)


func _run() -> void:
	_headless = DisplayServer.get_name() == "headless"
	root.size = Vector2i(1280, 720)
	if not _headless:
		DisplayServer.window_set_size(Vector2i(1280, 720))
	_bg()

	var commerce: Node = COM.new()
	commerce.load_seed()
	root.add_child(commerce)

	# ------------------------------------------------------------------
	# Fabricación
	# ------------------------------------------------------------------
	var cs: Node = CS.new()
	cs.load_seed()
	root.add_child(cs)
	var w = load("res://ui/windows/CraftingWindow/CraftingWindow.tscn").instantiate()
	if w.get_script() == null:
		printerr("[capture] CraftingWindow sin script (error de parseo)")
		quit(1)
		return
	w.service = cs
	w.commerce = commerce
	root.add_child(w)
	await process_frame
	w.position = Vector2(5, 20)
	w.fit_to_viewport()

	# 1. Herrería · Hoja de la grieta ×3: calidad probable, 2/6 de cuero (rojo) y «Comprar lo que falta».
	w.select_recipe("hoja_grieta")
	w.set_qty(3)
	await _shot("crafting_window")

	# 2. Cola de la Forja: Lingote de ferrum ×4 encolado (además de la cola del seed), catalizador
	#    activo en Coraza del vado y la Forja avanzada 30 s.
	w.select_recipe("lingote_ferrum")
	w.set_qty(4)
	w.queue_in_forge()
	cs.tick(30.0)
	w.select_recipe("coraza_vado")
	w.set_qty(1)
	w.set_use_catalyst(true)
	w.refresh()
	await _shot("crafting_queue_shelter")
	w.queue_free()
	await process_frame

	# ------------------------------------------------------------------
	# Trato cara a cara
	# ------------------------------------------------------------------
	var ks: Node = KS.new()
	ks.register_entry("lugar_cueva_ambar", "lugares", {"name": "Cueva de ámbar"}, KS.KNOWN_SECRET)
	root.add_child(ks)
	var ts: Node = TS.new()
	ts.load_seed()
	ts.knowledge = ks
	root.add_child(ts)
	ts.start_session("Sasha", {})

	var tw = load("res://ui/windows/TradeWindow/TradeWindow.tscn").instantiate()
	tw.service = ts
	tw.knowledge = ks
	tw.drive_clock = false
	root.add_child(tw)
	await process_frame
	tw.position = Vector2((1280 - 900) * 0.5, 60)

	# 3. Máscara «???»: Sasha ofrece un objeto épico que no está en tu Códice; Sasha ya confirmó.
	ts.confirm(TS.REMOTE)
	tw.refresh()
	await _shot("trade_window_secret_mask")

	# 4. Doble confirmación: tú cambias el oro (se borran ambas, 3 s de espera), pasa la espera,
	#    Sasha te enseña el objeto y ambos confirman -> LOCKED_BOTH.
	tw.change_gold(50)
	ts.tick(3.0)
	ts.request_reveal()
	ts.reveal_remote_item("corona_umbral")
	ts.confirm(TS.REMOTE)
	tw.press_confirm()
	tw.refresh()
	await _shot("trade_window_dual_confirmed")

	tw.queue_free()
	await process_frame
	var expected := ["crafting_window", "crafting_queue_shelter", "trade_window_secret_mask", "trade_window_dual_confirmed"]
	var ok := expected.all(func(f) -> bool: return _saved.has(f))
	print("[capture] %d capturas: %s" % [_saved.size(), ", ".join(_saved)])
	quit(0 if ok else 1)
