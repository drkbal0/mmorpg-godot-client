extends SceneTree
## Captura visual (requiere GPU, sin --headless) de los cimientos UI v2.4 para
## comparar con design_ref/pantallas_png/MMO-Tienda.png (barra de menú + franja).
## Run: Godot --path clients/godot-mmo-client -s tests/unit/capture_ui_v2_foundation.gd
## Salida: test_evidence/ui_v2_foundation.png

const T = preload("res://ui/tokens/hud_tokens.gd")
const StatChip = preload("res://ui/components/base/stat_chip.gd")
const ConstructionBanner = preload("res://ui/components/base/under_construction_banner.gd")

const OUT := "res://test_evidence/ui_v2_foundation.png"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	# Sin escalado canvas_items (base 1280×720) para medir a tamaño real.
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1440, 810)
	DisplayServer.window_set_size(Vector2i(1440, 810))
	var bg := ColorRect.new()
	bg.color = Color("#0b1013")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)

	var bar = load("res://ui/menu/menu_bar.tscn").instantiate()
	root.add_child(bar)
	bar.set_currencies(12480, 340)
	bar.set_active_tab("comercio", "tienda")

	var banner := ConstructionBanner.new()
	banner.position = Vector2(400, 81)
	banner.size = Vector2(1012, 36)
	banner.setup({"message": "Estructura propuesta de la tienda · contenido y precios por definir"})
	root.add_child(banner)

	# Muestrario de filas: 16 stats en 2 columnas (contexto comparación 20 px) con deltas.
	var grid := GridContainer.new()
	grid.columns = 2
	grid.position = Vector2(40, 150)
	grid.add_theme_constant_override("h_separation", 40)
	grid.add_theme_constant_override("v_separation", 6)
	root.add_child(grid)
	var row_scene: PackedScene = load("res://ui/components/base/stat_row.tscn")
	var i := 0
	for key in T.STAT_KEYS:
		var row = row_scene.instantiate()
		row.custom_minimum_size = Vector2(300, 26)
		grid.add_child(row)
		var delta: float = [0, 12, -5, 3][i % 4]
		row.setup(key, [142, "25 %", 0, 1.5][i % 4], delta, {"context": "compare"})
		i += 1

	# Chips en los tres tamaños.
	var chips := HBoxContainer.new()
	chips.position = Vector2(760, 150)
	chips.add_theme_constant_override("separation", 8)
	root.add_child(chips)
	for ctx in ["hud", "compare", "card"]:
		for key in ["armadura", "critico", "penmag", "regen"]:
			var c := StatChip.new()
			chips.add_child(c)
			c.setup(key, 42, {"abbr": ctx == "card", "context": ctx})

	# Energías (Anexo B).
	var energies := HBoxContainer.new()
	energies.position = Vector2(760, 230)
	energies.add_theme_constant_override("separation", 6)
	root.add_child(energies)
	for k in T.ENERGY_KEYS:
		var l := Label.new()
		l.text = T.ENERGIES[k]["name"]
		l.add_theme_color_override("font_color", T.energy_color(k))
		l.add_theme_font_override("font", T.font("bold"))
		energies.add_child(l)

	for _f in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_evidence"))
	var err := img.save_png(OUT)
	print("[capture] ", ProjectSettings.globalize_path(OUT), " err=", err, " size=", img.get_size())
	quit(0 if err == OK else 1)
