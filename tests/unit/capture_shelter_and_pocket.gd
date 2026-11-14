extends SceneTree
## Captura visual (no headless) del Refugio «El Nido» y del refugio de bolsillo.
## Run: Godot --rendering-driver opengl3 --path clients/godot-mmo-client -s tests/unit/capture_shelter_and_pocket.gd
## Salida: test_evidence/shelter_*.png

const SS = preload("res://shared-core/ShelterService.gd")
const KS = preload("res://shared-core/KnowledgeService.gd")
const ShelterScene = preload("res://ui/windows/ShelterWindow/ShelterWindow.tscn")
const PocketScene = preload("res://ui/windows/ShelterWindow/ShelterPocket.tscn")


func _initialize() -> void:
	_run.call_deferred()


func _shot(file_name: String) -> void:
	for i in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_evidence"))
	img.save_png("res://test_evidence/%s.png" % file_name)
	print("[capture] %s.png" % file_name)


func _run() -> void:
	root.size = Vector2i(1280, 720)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	var bg := ColorRect.new()
	bg.color = Color("#05080a")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)

	var s: Node = SS.new()
	s.roll_override = 10.0
	var ks: Node = KS.new()
	ks.wiki_sync_enabled = false
	s.connect_knowledge(ks)
	ks.add_investment({"id": "inv_gildas", "npc_id": "pnj_gildas", "name": "Puesto de Gildas", "share": 0.02, "status": "active"})
	ks.add_investment({"id": "inv_torin", "npc_id": "pnj_torin", "name": "Forja de Torin", "share": 0.03, "status": "active"})
	ks.record_transaction("inv_gildas", 21000)
	ks.record_transaction("inv_torin", 9000)
	ks.collect_to_shelter()
	ks.record_transaction("inv_gildas", 6000)
	# Un rato de vida: tónicos listos, Pispa de viaje, Torq a punto de elegir.
	s.tick(0.2)
	s.away_log = ["+340 esquirlas en el sótano", "Pispa trajo una Pluma de grieta", "Brisa te prestó a Lía 8 h", "Torq espera que elijas camino"]

	var w = ShelterScene.instantiate()
	if w.get_script() == null:
		printerr("[capture] ShelterWindow sin script (error de parseo)")
		quit(1)
		return
	w.service = s
	root.add_child(w)
	await process_frame
	w.position = Vector2(5, 20)
	w.fit_to_viewport()

	# 1. Corte lateral (Vivir) con el Taller seleccionado.
	w.select_subtab("refugio")
	w.select_cell(1, 0)
	await _shot("shelter_side_cut")

	# 2. Modo Construir: Telar en el hueco junto al Almacén.
	w.set_build_mode(true)
	w.select_catalog_item("telar")
	w.select_cell(1, 4)
	await _shot("shelter_build_mode")
	w.set_build_mode(false)

	# 3. Producción con el atasco de la Destilería.
	w.select_subtab("produccion")
	await _shot("shelter_production_chains")

	# 4. Expediciones: Ruinas de Ferrum con Ysolde y la bifurcación de Torq.
	w.select_subtab("expediciones")
	w.select_expedition("ruinas_ferrum")
	w.set_duration(4)
	await _shot("shelter_expeditions")

	# 5. Pispa buscando hierbas (★ misión).
	w.select_subtab("pispa")
	w.select_pispa_target("hierbas")
	await _shot("shelter_pispa_pet")

	# Extra: Mejoras.
	w.select_subtab("mejoras")
	await _shot("shelter_upgrades")
	w.queue_free()
	await process_frame

	# 6. Refugio de bolsillo sobre la pantalla de carga.
	var tex := load("res://design_ref/pantallas_png/MMO-Carga.png") as Texture2D
	var scene_bg := TextureRect.new()
	scene_bg.texture = tex
	scene_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	scene_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	scene_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(scene_bg)
	var s2: Node = SS.new()
	s2.tick(0.1)
	var p = PocketScene.instantiate()
	p.service = s2
	p.capture_shortcut = true
	root.add_child(p)
	await process_frame
	p.position = Vector2(1280 - p.size.x - 24, 24)
	await _shot("shelter_pocket_overlay")
	p.queue_free()
	await process_frame
	# `s` y `s2` los adoptan (y liberan) la ventana y el bolsillo.
	ks.free()
	quit(0)
