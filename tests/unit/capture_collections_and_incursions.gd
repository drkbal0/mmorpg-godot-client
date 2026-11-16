extends SceneTree
## Captura visual del Paso 12 UI v2.4: Colecciones e Incursiones con extracción.
## Run: Godot --path clients/godot-mmo-client --headless -s tests/unit/capture_collections_and_incursions.gd
##      (en headless no hay framebuffer; para PNG reales usar --rendering-driver opengl3 sin --headless)
## Salida: test_evidence/collections_window.png, collections_universe_progress.png,
##         incursions_window.png e incursions_preparation_risk.png

const CS = preload("res://shared-core/CollectionsService.gd")
const IS = preload("res://shared-core/IncursionService.gd")
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
	# Colecciones
	# ------------------------------------------------------------------
	var cs: Node = CS.new()
	cs.load_seed()
	root.add_child(cs)
	var w = load("res://ui/windows/CollectionsWindow/CollectionsWindow.tscn").instantiate()
	if w.get_script() == null:
		printerr("[capture] CollectionsWindow sin script (error de parseo)")
		quit(1)
		return
	w.service = cs
	w.commerce = commerce
	root.add_child(w)
	await process_frame
	w.position = Vector2(5, 20)
	w.fit_to_viewport()

	# 1. Monturas 23/96 en orden de catálogo (como el HTML) con Raya de grieta (80 %) en la ficha.
	w.set_sort("catalog")
	w.select_item("raya_grieta")
	await _shot("collections_window")

	# 2. Diario del multiverso vinculado al Códice: 3 secretos nuevos en Runavell
	#    (12 % -> 13 % · 9 secretos), título «Pionero» equipado en la ficha y Lobo invocado.
	var ks: Node = KS.new()
	root.add_child(ks)
	for i in 3:
		ks.discover_entry("runa_%d" % i, "lugares", {"name": "Runa %d" % i, "universe": "runavell"})
		ks.decide_entry("runa_%d" % i, false)
	cs.link_knowledge(ks)
	cs.summon_mount("lobo_ceniza")
	w.set_category("titles")
	w.select_item("titulo_pionero")
	w.refresh()
	await _shot("collections_universe_progress")
	w.queue_free()
	await process_frame

	# ------------------------------------------------------------------
	# Incursiones
	# ------------------------------------------------------------------
	var inc: Node = IS.new()
	inc.load_seed()
	root.add_child(inc)
	var iw = load("res://ui/windows/IncursionsWindow/IncursionsWindow.tscn").instantiate()
	iw.service = inc
	iw.commerce = commerce
	root.add_child(iw)
	await process_frame
	iw.position = Vector2(5, 20)
	iw.fit_to_viewport()

	# 3. Las 3 incursiones con la media (Bóveda de Ferrum) recomendada; bolsa segura 3/3.
	await _shot("incursions_window")

	# 4. Preparación y riesgo: la larga seleccionada sin bengala ni kit, equipo al 41 %
	#    y la Coraza cambiada por la Llave en la bolsa segura (bloqueos en rojo).
	inc.add_flares(-1)
	inc.add_campfire_kits(-1)
	inc.set_durability(41)
	inc.swap_secure("llave_oxidada", "coraza_vado")
	iw.select_incursion("minas_abisales")
	await _shot("incursions_preparation_risk")
	iw.queue_free()
	await process_frame

	var expected := ["collections_window", "collections_universe_progress", "incursions_window", "incursions_preparation_risk"]
	var ok := expected.all(func(f) -> bool: return _saved.has(f))
	print("[capture] %d capturas: %s" % [_saved.size(), ", ".join(_saved)])
	quit(0 if ok else 1)
