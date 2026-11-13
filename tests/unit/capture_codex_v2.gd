extends SceneTree
## Captura visual del Códice v2 (no headless): Entradas, modal de decisión e Inversiones.
## Run: Godot --path clients/godot-mmo-client -s tests/unit/capture_codex_v2.gd
## Salida: test_evidence/codex_v2_*.png

const KS = preload("res://shared-core/KnowledgeService.gd")
const CodexScene = preload("res://ui/windows/CodexWindow/CodexWindow.tscn")


func _initialize() -> void:
	_run.call_deferred()


func _shot(name: String) -> void:
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_evidence"))
	img.save_png("res://test_evidence/codex_v2_%s.png" % name)
	print("[capture] codex_v2_%s.png" % name)


func _run() -> void:
	root.size = Vector2i(1280, 720)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	var bg := ColorRect.new()
	bg.color = Color("#05080a")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var ks: Node = KS.new()
	ks.wiki_sync_enabled = false
	ks.clock_override = 1762992000
	root.add_child(ks)
	var codex = CodexScene.instantiate()
	if codex.get_script() == null:
		printerr("[capture] CodexWindow sin script (error de parseo)")
		quit(1)
		return
	codex.service = ks
	root.add_child(codex)
	await process_frame
	codex.position = Vector2(5, 20)
	print("[capture] min size codex=", codex.get_combined_minimum_size(), " menu=", codex.menu_bar.get_combined_minimum_size())
	codex.menu_bar.set_currencies(12480, 340)
	codex.fit_to_viewport()
	print("[capture] codex rect=", codex.get_rect(), " compact=", codex.get_meta("menu_compact", false))
	codex.select_category("objetos")
	await _shot("entradas")
	codex.open_decision("item_amuleto_vacio")
	await _shot("decision")
	codex.close_decision()
	codex.select_subtab("secretos")
	await _shot("secretos")
	codex.select_subtab("publicados")
	await _shot("publicados")
	codex.select_subtab("inversiones")
	await _shot("inversiones")
	quit(0)
