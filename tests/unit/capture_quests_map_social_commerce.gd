extends SceneTree
## Captura visual (no headless) del Paso 9 UI v2.4: Misiones [L], Mapa [M], Social [O],
## Tienda y Pase de batalla (Comercio [P], en construcción).
## Run: Godot --rendering-driver opengl3 --path clients/godot-mmo-client -s tests/unit/capture_quests_map_social_commerce.gd
## Salida: test_evidence/{quests_window,map_window,social_window,shop_window,battle_pass_window}.png
## (+ extras: map_window_travel.png, social_window_neighborhood.png, social_window_guild.png)

const QS = preload("res://shared-core/QuestService.gd")
const WMS = preload("res://shared-core/WorldMapService.gd")
const SOC = preload("res://shared-core/SocialService.gd")
const COM = preload("res://shared-core/CommerceService.gd")
const KS = preload("res://shared-core/KnowledgeService.gd")
const SS = preload("res://shared-core/ShelterService.gd")

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


func _show(scene_path: String, setup: Callable) -> Control:
	var w = load(scene_path).instantiate()
	if w.get_script() == null:
		printerr("[capture] %s sin script (error de parseo)" % scene_path)
		return null
	setup.call(w)
	root.add_child(w)
	await process_frame
	w.position = Vector2(5, 20)
	w.fit_to_viewport()
	return w


func _run() -> void:
	root.size = Vector2i(1280, 720)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	var bg := ColorRect.new()
	bg.color = Color("#05080a")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)

	var ks: Node = KS.new()
	ks.wiki_sync_enabled = false
	ks.load_seed()
	var commerce: Node = COM.new()
	commerce.load_seed()
	# Servicios compartidos colgados de root: así ninguna ventana los adopta (ni libera).
	root.add_child(ks)
	root.add_child(commerce)

	# 1. Misiones: detalle de «Sellar la grieta menor» con 3 misiones en el HUD.
	var q: Node = QS.new()
	q.load_seed()
	q.connect_knowledge(ks)
	root.add_child(q)
	q.track("q_hierbas_brecha")
	var qw: Control = await _show("res://ui/windows/QuestsWindow/QuestsWindow.tscn", func(w) -> void:
		w.service = q
		w.commerce = commerce)
	if qw:
		qw.select_quest("q_sellar_grieta")
		await _shot("quests_window")
		qw.queue_free()

	# 2. Mapa: secretos del Códice, objetivo de misión enfocado y Val'Gorath seleccionado.
	var m: Node = WMS.new()
	m.load_seed()
	m.connect_knowledge(ks)
	root.add_child(m)
	var mw: Control = await _show("res://ui/windows/MapWindow/MapWindow.tscn", func(w) -> void:
		w.service = m
		w.quests = q
		w.commerce = commerce)
	if mw:
		await process_frame
		mw._refresh_quest_markers()
		mw.canvas.player_pos = Vector2(1010, 600)
		mw.canvas.center_on(Vector2(1080, 560), 0.62)
		mw.canvas.focus_on(Vector2(1180, 470), "Sellar la grieta menor", 0.62)
		mw.canvas.center_on(Vector2(1090, 600), 0.62)
		mw.select_marker("boss_valgorath")
		await _shot("map_window")
		# Extra: página Viajar (Vado Roto → Bóveda de Ferrum).
		mw.select_destination("boveda_ferrum")
		mw.set_page("viajar")
		await _shot("map_window_travel")
		mw.queue_free()

	# 3. Social: amigos con grupo y préstamo de habitante en preparación.
	var shelter: Node = SS.new()
	var soc: Node = SOC.new()
	soc.load_seed()
	soc.shelter = shelter
	root.add_child(shelter)
	root.add_child(soc)
	var sw: Control = await _show("res://ui/windows/SocialWindow/SocialWindow.tscn", func(w) -> void:
		w.service = soc
		w.commerce = commerce)
	if sw:
		sw.choose_loan_friend("brisa")
		sw.choose_loan_inhabitant("ysolde")
		await _shot("social_window")
		sw.set_page("gremio")
		sw.donate(500)
		await _shot("social_window_guild")
		sw.set_page("vecindad")
		await _shot("social_window_neighborhood")
		sw.queue_free()

	# 4. Tienda (en construcción).
	var shw: Control = await _show("res://ui/windows/ShopWindow/ShopWindow.tscn", func(w) -> void:
		w.commerce = commerce)
	if shw:
		await _shot("shop_window")
		shw.queue_free()

	# 5. Pase de batalla (en construcción) con el nivel 12 reclamado.
	var pw: Control = await _show("res://ui/windows/BattlePassWindow/BattlePassWindow.tscn", func(w) -> void:
		w.commerce = commerce)
	if pw:
		await process_frame
		pw.claim(10)
		pw.claim(12)
		pw.scroll_to_level(12)
		await _shot("battle_pass_window")
		pw.queue_free()

	await process_frame
	var expected := ["quests_window", "map_window", "social_window", "shop_window", "battle_pass_window"]
	var ok := expected.all(func(f) -> bool: return _saved.has(f))
	print("[capture] %d capturas guardadas: %s" % [_saved.size(), ", ".join(_saved)])
	quit(0 if ok else 1)
