extends SceneTree
## Captura visual (no headless) de Poderes (Crisol · Atlas · Constelación · Afinidades)
## y del modal de oferta de inversión del pionero.
## Run: Godot --rendering-driver opengl3 --path clients/godot-mmo-client -s tests/unit/capture_powers_and_offer.gd
## Salida: test_evidence/powers_*.png y test_evidence/pioneer_offer_modal.png

const PS = preload("res://shared-core/PowersService.gd")
const KS = preload("res://shared-core/KnowledgeService.gd")
const PowersScene = preload("res://ui/windows/PowersWindow/PowersWindow.tscn")
const OfferScene = preload("res://ui/windows/PioneerOfferModal/PioneerOfferModal.tscn")


func _initialize() -> void:
	_run.call_deferred()


func _shot(file_name: String) -> void:
	for i in 4:
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

	# --- Poderes ---------------------------------------------------------------
	var w = PowersScene.instantiate()
	if w.get_script() == null:
		printerr("[capture] PowersWindow sin script (error de parseo)")
		quit(1)
		return
	w.service = PS.new()
	root.add_child(w)
	await process_frame
	w.position = Vector2(5, 20)
	w.menu_bar.set_currencies(12480, 340)
	w.fit_to_viewport()
	print("[capture] powers rect=", w.get_rect(), " compact=", w.get_meta("menu_compact", false))

	w.select_subtab("crisol")
	w.set_crucible(["vacio", "calor"], "area", "canalizado")
	await _shot("powers_crisol")

	w.select_subtab("atlas")
	w.select_atlas_pair("pulso", "eco")
	await _shot("powers_atlas")

	w.select_subtab("constelacion")
	w.select_node("v1")
	await _shot("powers_constelacion")

	w.toggle_crucible_beside()
	await _shot("powers_constelacion_crisol_al_lado")
	w.close_side()

	w.service.record_combat_use(["luz", "sombra"], 60)
	w.select_subtab("afinidades")
	await _shot("powers_afinidades")
	w.queue_free()
	await process_frame

	# --- Oferta del pionero ----------------------------------------------------
	var tex := load("res://design_ref/mapa-fondo.jpg") as Texture2D
	var scene_bg := TextureRect.new()
	scene_bg.texture = tex
	scene_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	scene_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	scene_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	scene_bg.modulate = Color(0.42, 0.46, 0.38)
	root.add_child(scene_bg)
	var ks: Node = KS.new()
	ks.wiki_sync_enabled = false
	var m = OfferScene.instantiate()
	m.service = ks
	root.add_child(m)
	await _shot("pioneer_offer_modal")
	m.queue_free()
	ks.free()
	quit(0)
