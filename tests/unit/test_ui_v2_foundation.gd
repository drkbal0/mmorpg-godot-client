extends SceneTree
## Suite headless de los cimientos UI v2.4 (tokens, iconos SVG, componentes base y menú común).
## Run: Godot --headless --path clients/godot-mmo-client -s tests/unit/test_ui_v2_foundation.gd
## Exit code 0 = todo PASS.

const T = preload("res://ui/tokens/hud_tokens.gd")
const SvgPath = preload("res://ui/icons/svg_path.gd")
const VectorIcon = preload("res://ui/components/base/vector_icon.gd")
const StatChip = preload("res://ui/components/base/stat_chip.gd")
const CurrencyLabel = preload("res://ui/components/base/currency_label.gd")
const ConstructionBanner = preload("res://ui/components/base/under_construction_banner.gd")
const MenuBarScript = preload("res://ui/menu/menu_bar.gd")

## Anexo A (PROMPT_ANTIGRAVITY.md) — valores esperados literales.
const EXPECTED_STATS := {
	"dano": ["Daño de ataque", "DA", "#ff9a4d"],
	"poder": ["Poder de habilidad", "PH", "#a58bff"],
	"armadura": ["Armadura", "ARM", "#e0b04a"],
	"resmag": ["Resistencia mágica", "RM", "#4fc8ff"],
	"velatq": ["Velocidad de ataque", "VA", "#ffd36b"],
	"celeridad": ["Celeridad", "CEL", "#b8f0ff"],
	"critico": ["Golpe crítico", "CRÍT", "#ff5d5d"],
	"velmov": ["Velocidad de movimiento", "VM", "#9fe36a"],
	"penarm": ["Penetración de armadura", "PEN", "#ff7a59"],
	"penmag": ["Penetración mágica", "PEN M", "#d08bff"],
	"robo": ["Robo de vida", "RV", "#ff4d7a"],
	"omni": ["Omnivampirismo", "OMNI", "#e66bc4"],
	"alcance": ["Alcance", "ALC", "#c3ccd3"],
	"tenacidad": ["Tenacidad", "TEN", "#9a7bff"],
	"curacion": ["Curación y escudos", "CUR", "#4fe39a"],
	"regen": ["Regeneración", "REG", "#6fe0a0"],
}

## Anexo B.
const EXPECTED_ENERGIES := [
	["vacio", "Vacío", "#b47bff"], ["calor", "Calor", "#ff7a45"], ["eco", "Eco", "#7fe0ff"],
	["pulso", "Pulso", "#5aa9ff"], ["runa", "Runa", "#f5b546"], ["savia", "Savia", "#4fe39a"],
	["hierro", "Hierro", "#b8c3ca"], ["marea", "Marea", "#3f8fd6"], ["sombra", "Sombra", "#8a7aa8"],
	["luz", "Luz", "#fff1a8"],
]

const EXPECTED_TABS := [
	["equipo", "Equipo", "C"], ["poderes", "Poderes", "N"], ["misiones", "Misiones", "L"],
	["mapa", "Mapa", "M"], ["codice", "Códice", "J"], ["social", "Social", "O"],
	["refugio", "Refugio", "H"], ["comercio", "Comercio", "P"],
]

var _fails: Array[String] = []
var _checks := 0


func check(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_fails.append(msg)
		printerr("  FAIL: ", msg)
	else:
		print("  PASS: ", msg)


func _initialize() -> void:
	_run.call_deferred()


func _key(code: int, ctrl := false) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	ev.ctrl_pressed = ctrl
	return ev


func _hex(c: Color) -> String:
	return "#" + c.to_html(false).to_lower()


func _run() -> void:
	print("== [TEST] UI v2.4 Foundation ==")
	_test_stat_tokens()
	_test_design_ref_crosscheck()
	_test_svg_icons()
	_test_currencies_and_energies()
	_test_theme()
	await _test_stat_row()
	await _test_stat_chip()
	await _test_currency_label()
	await _test_banner()
	await _test_menu_bar()
	await _test_orchestrator_bridge()

	print("\n== RESULTADO: %d/%d PASS ==" % [_checks - _fails.size(), _checks])
	if _fails.is_empty():
		print("ALL PASS")
		quit(0)
	else:
		for f in _fails:
			printerr("  - ", f)
		quit(1)


# ---------------------------------------------------------------------------
func _test_stat_tokens() -> void:
	print("\n--- 1. Tokens: 16 estadísticas canónicas (Anexo A) ---")
	check(T.STAT_KEYS.size() == 16, "STAT_KEYS tiene 16 claves")
	check(T.STATS.size() == 16, "STATS tiene 16 entradas")
	var colors := {}
	var all_ok := true
	for key in EXPECTED_STATS:
		var exp: Array = EXPECTED_STATS[key]
		var s := T.stat(key)
		var ok: bool = not s.is_empty() and s["name"] == exp[0] and s["abbr"] == exp[1] and _hex(s["color"]) == exp[2]
		if not ok:
			all_ok = false
			printerr("    stat discrepante: ", key, " -> ", s)
		colors[exp[2]] = true
		check(not s.is_empty() and (s["path"] as String).begins_with("M"), "stat '%s' tiene path SVG" % key)
		check(is_equal_approx(s.get("bg", Color()).a, 34.0 / 255.0), "stat '%s' fondo al 13%% (#..22)" % key)
	check(all_ok, "Nombre, abreviatura y color de las 16 stats coinciden con el Anexo A")
	check(colors.size() == 16, "Los 16 colores de estadística son únicos")
	check(T.STAT_KEYS == ["dano", "poder", "armadura", "resmag", "velatq", "celeridad", "critico", "velmov", "penarm", "penmag", "robo", "omni", "alcance", "tenacidad", "curacion", "regen"], "Orden canónico de STAT_KEYS")
	check(T.STAT_ICON_SIZES == [16, 20, 24], "Tamaños de icono 16/20/24")
	check(T.stat_icon_size("hud") == 16 and T.stat_icon_size("compare") == 20 and T.stat_icon_size("card") == 24, "Contextos hud/compare/card -> 16/20/24")
	check(T.stat_icon_size(20) == 20 and T.stat_icon_size("desconocido") == 16, "stat_icon_size acepta tamaño directo y cae a 16")
	var legacy_ok := T.STAT_LEGACY_MAP.size() == 16
	for legacy in T.STAT_LEGACY_MAP:
		legacy_ok = legacy_ok and T.STATS.has(T.STAT_LEGACY_MAP[legacy])
	var schema_ok := true
	for row in T.STAT_SCHEMA:
		schema_ok = schema_ok and T.has_stat(row["id"])
	check(legacy_ok, "STAT_LEGACY_MAP cubre 16 claves válidas")
	check(schema_ok, "Todas las stats del HUD v1 (STAT_SCHEMA) resuelven a una clave canónica")
	check(T.stat("attack_damage")["key"] == "dano", "stat('attack_damage') resuelve a 'dano'")
	check(T.stat("no_existe").is_empty() and not T.has_stat("no_existe"), "Stat desconocida devuelve vacío")
	check(T.is_zero_stat_text("0") and T.is_zero_stat_text("0 %") and T.is_zero_stat_text("0,0") and T.is_zero_stat_text("0 | 0 %"), "is_zero_stat_text reconoce ceros (regex del diseño)")
	check(not T.is_zero_stat_text("10") and not T.is_zero_stat_text("0,5"), "is_zero_stat_text no atenúa valores no cero")
	var up := T.delta_style(5)
	var down := T.delta_style(-3)
	var inv := T.delta_style(-3, false)
	check(up["glyph"] == "▲" and up["color"] == T.DELTA_UP, "delta +: ▲ verde")
	check(down["glyph"] == "▼" and down["color"] == T.DELTA_DOWN, "delta -: ▼ rojo")
	check(inv["glyph"] == "▼" and inv["color"] == T.DELTA_UP and inv["improves"], "delta - con higher_is_better=false: ▼ verde (mejora)")
	check(T.delta_style(0)["glyph"] == "", "delta 0 sin glifo")


func _test_design_ref_crosscheck() -> void:
	print("\n--- 2. Cruce con design_ref/tokens_estadisticas.js ---")
	var f := FileAccess.open("res://design_ref/tokens_estadisticas.js", FileAccess.READ)
	check(f != null, "design_ref/tokens_estadisticas.js legible")
	if f == null:
		return
	var src := f.get_as_text()
	var re := RegEx.new()
	re.compile("(\\w+):\\s*\\{\\s*n:\\s*'([^']*)',\\s*s:\\s*'([^']*)',\\s*c:\\s*'([^']*)',\\s*i:\\s*'([^']*)'")
	var found := 0
	var mismatches: Array[String] = []
	for m in re.search_all(src):
		found += 1
		var k := m.get_string(1)
		var s := T.stat(k)
		if s.is_empty() or s["name"] != m.get_string(2) or s["abbr"] != m.get_string(3) \
				or _hex(s["color"]) != m.get_string(4).to_lower() or s["path"] != m.get_string(5):
			mismatches.append(k)
	check(found == 16, "El JS de referencia define 16 stats (encontradas %d)" % found)
	check(mismatches.is_empty(), "Tokens GDScript idénticos al JS (nombre, abrev., color, path) %s" % str(mismatches))


func _test_svg_icons() -> void:
	print("\n--- 3. Iconos SVG vectoriales (parser) ---")
	var line := SvgPath.parse("M3 12h18")
	check(line.size() == 1 and line[0]["points"].size() == 2, "M/h: 1 subtrayecto de 2 puntos")
	check(line[0]["points"][1].is_equal_approx(Vector2(21, 12)), "h relativo calcula x=21")
	var closed := SvgPath.parse("M12 2l8 7-8 13-8-13z")
	check(closed.size() == 1 and closed[0]["closed"] and closed[0]["points"].size() == 4, "Pares implícitos tras l + Z cierran el polígono del Prisma")
	var circle := SvgPath.parse("M12 9a3 3 0 1 0 0 6a3 3 0 1 0 0-6")
	var pts: PackedVector2Array = circle[0]["points"]
	var radius_ok := true
	for p in pts:
		radius_ok = radius_ok and absf(p.distance_to(Vector2(12, 12)) - 3.0) < 0.05
	check(pts.size() > 8 and radius_ok, "Arcos 'a' generan un círculo de radio 3 centrado en (12,12)")
	check(pts[pts.size() - 1].is_equal_approx(Vector2(12, 9)), "El arco termina exactamente en su destino")
	var dot := SvgPath.parse("M17 7h.01")
	check(dot.size() == 1 and dot[0]["points"][1].is_equal_approx(Vector2(17.01, 7)), "Número '.01' sin cero inicial")
	var smooth := SvgPath.parse("M8 3c0 5 8 5 8 9s-8 4-8 9")
	check(smooth[0]["points"][smooth[0]["points"].size() - 1].is_equal_approx(Vector2(8, 21)), "Curvas c + s encadenadas")
	var abs_arc := SvgPath.parse("M12 20s-7-4.5-7-10a4 4 0 0 1 7-2.5A4 4 0 0 1 19 10")
	check(abs_arc[0]["points"][abs_arc[0]["points"].size() - 1].is_equal_approx(Vector2(19, 10)), "Arco absoluto 'A' llega a (19,10)")

	var all_in_bounds := true
	var all_nonempty := true
	for key in T.STAT_KEYS:
		var b := SvgPath.bounds(T.STATS[key]["path"])
		if b.position.x < -0.5 or b.position.y < -0.5 or b.end.x > 24.5 or b.end.y > 24.5:
			all_in_bounds = false
			printerr("    icono fuera del viewBox: ", key, " ", b)
		for size_px in T.STAT_ICON_SIZES:
			var polys := T.stat_icon_polylines(key, size_px)
			if polys.is_empty():
				all_nonempty = false
			for poly in polys:
				for p in poly:
					if p.x < -1.0 or p.y < -1.0 or p.x > size_px + 1.0 or p.y > size_px + 1.0:
						all_in_bounds = false
	check(all_nonempty, "Los 16 iconos producen trazos en 16, 20 y 24 px")
	check(all_in_bounds, "Todos los trazos caben en su caja (viewBox 24 escalado)")
	var p24: Array = T.stat_icon_polylines("armadura", 24)
	var p16: Array = T.stat_icon_polylines("armadura", 16)
	check(p24[0][0].is_equal_approx(p16[0][0] * 1.5), "Escalado vectorial proporcional 16 -> 24 px")
	check(T.stat_icon_layers("critico")[0]["width"] == 2.2, "Trazo de stats 2.2 (como el diseño)")


func _test_currencies_and_energies() -> void:
	print("\n--- 4. Monedas y energías ---")
	check(T.CURRENCY_KEYS == ["oro", "prismas"], "Dos monedas: oro y prismas")
	var gold := T.currency("oro")
	var prisms := T.currency("prismas")
	check(_hex(gold["color"]) == "#f5c35b", "Oro #f5c35b")
	check(_hex(prisms["color"]) == "#7ee8ff", "Prismas #7ee8ff")
	check(not gold["purchasable"] and gold["earnable"], "Oro: se gana jugando, no se compra")
	check(prisms["purchasable"], "Prismas: se compran con dinero real")
	check(T.currency_icon_layers("oro").size() == 2 and T.currency_icon_layers("prismas").size() == 2, "Iconos vectoriales de moneda con 2 capas (moneda / gema)")
	check(T.currency_icon_layers("oro")[0]["fill"] is Color, "Capas de moneda convierten hex -> Color")
	check(T.format_amount(12480) == "12.480", "format_amount(12480) = 12.480")
	check(T.format_amount(340) == "340" and T.format_amount(0) == "0", "format_amount sin separador < 1000")
	check(T.format_amount(1234567) == "1.234.567" and T.format_amount(-1500) == "-1.500", "format_amount millones y negativos")
	check(T.ENERGY_KEYS.size() == 10 and T.ENERGIES.size() == 10, "10 energías iniciales")
	var e_ok := true
	for i in EXPECTED_ENERGIES.size():
		var exp: Array = EXPECTED_ENERGIES[i]
		var e := T.energy(exp[0])
		e_ok = e_ok and T.ENERGY_KEYS[i] == exp[0] and e["name"] == exp[1] and _hex(e["color"]) == exp[2]
	check(e_ok, "Energías: orden, nombre y color del Anexo B")
	check(T.energy("inexistente").is_empty() and T.energy_color("inexistente") == T.TEXT_SECONDARY, "Energía desconocida -> vacío / color secundario")


func _test_theme() -> void:
	print("\n--- 5. Theme ---")
	var th: Theme = load("res://ui/theme/hud_theme.tres")
	check(th != null and th == T.THEME, "Theme en res://ui/theme/hud_theme.tres y referenciado por tokens")
	check(not ResourceLoader.exists("res://ui/hud_theme.tres") and not FileAccess.file_exists("res://ui/hud_tokens.gd"), "Rutas antiguas migradas (sin duplicados)")
	for tv in ["UIMenuBar", "UIMenuTab", "UIMenuKeycap", "UIMenuButton", "StatChip"]:
		check(th.get_type_variation_base(tv) != &"", "Variación de tema '%s'" % tv)
	check(th.has_font("bold", "HUDFonts"), "Fuentes HUDFonts conservadas")


func _test_stat_row() -> void:
	print("\n--- 6. stat_row ---")
	var scene: PackedScene = load("res://ui/components/base/stat_row.tscn")
	check(scene != null, "stat_row.tscn carga")
	var row = scene.instantiate()
	root.add_child(row)
	await process_frame
	row.setup("armadura", 142, 12)
	await process_frame
	check(row.name_label.text == "Armadura", "Nombre desde tokens")
	check(row.value_label.text == "142", "Valor tabular")
	check(row.delta_label.visible and row.delta_label.text == "▲ 12", "Delta positivo '▲ 12'")
	check(row.delta_label.get_theme_color("font_color") == T.DELTA_UP, "Delta positivo en verde")
	check(row.icon.icon_kind == "stat" and row.icon.icon_key == "armadura" and row.icon.icon_size == 16, "Icono armadura 16 px")
	check(row.icon.has_icon(), "Icono con capas vectoriales")
	row.setup("critico", "25 %", -5, {"abbr": true, "context": "compare"})
	await process_frame
	check(row.name_label.text == "CRÍT", "Modo abreviatura")
	check(row.delta_label.text == "▼ 5" and row.delta_label.get_theme_color("font_color") == T.DELTA_DOWN, "Delta negativo '▼ 5' en rojo")
	check(row.icon.icon_size == 20, "Contexto 'compare' -> icono 20 px")
	row.setup("dano", 0)
	await process_frame
	check(row.value_label.get_theme_color("font_color") == T.TEXT_ZERO, "Valor 0 atenuado (#7c8992)")
	check(not row.delta_label.visible, "Sin delta, etiqueta oculta")
	row.setup("attack_speed", 1.5, 0.1, {"delta_text": "0,10"})
	await process_frame
	check(row.stat_key == "velatq" and row.value_label.text == "1,5", "Clave legacy y decimal con coma")
	check(row.delta_label.text == "▲ 0,10", "Texto de delta personalizado")
	check(row.tooltip_text.begins_with("Velocidad de ataque:"), "Nombre accesible/tooltip incluye nombre completo")
	row.setup("dano", 1500)
	check(row.value_label.text == "1.500", "Miles con separador")
	row.queue_free()


func _test_stat_chip() -> void:
	print("\n--- 7. stat_chip ---")
	var chip := StatChip.new()
	root.add_child(chip)
	chip.setup("critico", "25 %")
	await process_frame
	check(chip.icon.icon_key == "critico" and chip.icon.has_icon(), "Chip con icono vectorial")
	check(chip.value_label.text == "25 %", "Chip muestra valor")
	check(not chip.abbr_label.visible, "Abreviatura oculta por defecto")
	chip.setup("penmag", 18, {"abbr": true, "context": "card"})
	await process_frame
	check(chip.abbr_label.visible and chip.abbr_label.text == "PEN M", "Abreviatura visible")
	check(chip.abbr_label.get_theme_color("font_color") == T.stat_color("penmag"), "Abreviatura con color de la stat")
	check(chip.icon.icon_size == 24, "Contexto 'card' -> 24 px")
	var sb := chip.get_theme_stylebox("panel") as StyleBoxFlat
	check(sb != null and sb.bg_color.is_equal_approx(T.stat("penmag")["bg"]), "Fondo del chip = color stat al 13%")
	check(chip.get_combined_minimum_size().x > 24, "Chip con tamaño mínimo coherente")
	var chip_scene: PackedScene = load("res://ui/components/base/stat_chip.tscn")
	var chip2 = chip_scene.instantiate()
	check(chip2.get_node_or_null("Row/Icon") != null, "stat_chip.tscn instancia su estructura")
	chip2.free()
	chip.queue_free()


func _test_currency_label() -> void:
	print("\n--- 8. currency_label ---")
	var gold := CurrencyLabel.new()
	root.add_child(gold)
	gold.setup("oro", 12480)
	await process_frame
	check(gold.amount_label.text == "12.480", "Oro formateado 12.480")
	check(gold.amount_label.get_theme_color("font_color") == Color("#f5c35b"), "Oro en #f5c35b")
	check(not gold.add_button.visible, "Oro sin botón + (no se compra)")
	check(gold.icon.icon_kind == "currency" and gold.icon.has_icon(), "Icono vectorial de moneda")
	var prisms := CurrencyLabel.new()
	root.add_child(prisms)
	prisms.setup("prismas", 340)
	await process_frame
	check(prisms.add_button.visible, "Prismas con botón + (auto)")
	check(prisms.amount_label.get_theme_color("font_color") == Color("#a8f0ff"), "Texto de Prismas #a8f0ff")
	var got := [""]
	prisms.add_requested.connect(func(k: String) -> void: got[0] = k)
	prisms.add_button.pressed.emit()
	check(got[0] == "prismas", "add_requested('prismas') al pulsar +")
	prisms.add_button_mode = "hide"
	check(not prisms.add_button.visible, "add_button_mode=hide oculta +")
	prisms.set_amount(1000)
	check(prisms.amount_label.text == "1.000", "set_amount actualiza el texto")
	gold.queue_free()
	prisms.queue_free()


func _test_banner() -> void:
	print("\n--- 9. under_construction_banner ---")
	var banner := ConstructionBanner.new()
	banner.size = Vector2(1012, 36)
	root.add_child(banner)
	banner.setup({"message": "Estructura propuesta de la tienda · contenido y precios por definir"})
	await process_frame
	check(banner.badge_label.text == "EN CONSTRUCCIÓN", "Insignia 'EN CONSTRUCCIÓN'")
	check(banner.message_label.text.begins_with("Estructura propuesta"), "Mensaje configurable por datos")
	check(banner.custom_minimum_size.y == 36.0, "Alto 36 px")
	check(banner.stripe_count() >= int(1012.0 / 28.0), "Franjas diagonales cubren el ancho (%d)" % banner.stripe_count())
	check(banner.badge.get_theme_stylebox("panel").bg_color == Color("#f5c35b"), "Insignia ámbar #f5c35b")
	banner.setup({"badge": "PRÓXIMAMENTE", "message": ""})
	check(banner.badge_label.text == "PRÓXIMAMENTE" and not banner.message_label.visible, "Insignia/mensaje sustituibles")
	banner.queue_free()


func _test_menu_bar() -> void:
	print("\n--- 10. Menú común (menu_bar) ---")
	var scene: PackedScene = load("res://ui/menu/menu_bar.tscn")
	check(scene != null, "menu_bar.tscn carga")
	var bar = scene.instantiate()
	root.add_child(bar)
	await process_frame
	check(bar.custom_minimum_size.y == 64.0, "Altura 64 px")
	var ids: Array[String] = bar.get_tab_ids()
	check(ids.size() == 8, "8 pestañas")
	var order_ok := true
	for i in EXPECTED_TABS.size():
		var exp: Array = EXPECTED_TABS[i]
		var t: Dictionary = bar.get_tab(exp[0])
		order_ok = order_ok and ids[i] == exp[0] and t["label"] == exp[1] and bar.get_shortcut(exp[0]) == exp[2]
		var btn: Button = bar.get_tab_button(exp[0])
		var cap: Label = btn.get_node_or_null("Content/Keycap/Text") if btn else null
		check(cap != null and cap.text == exp[2], "Pestaña %s muestra atajo visible [%s]" % [exp[1], exp[2]])
		var tab_icon = btn.get_node_or_null("Content/Icon") if btn else null
		check(tab_icon != null and tab_icon.has_icon(), "Pestaña %s con icono vectorial" % exp[1])
	check(order_ok, "Orden, nombres y atajos C N L M J O H P")
	var subs: Array = bar.get_subtabs("comercio")
	check(subs.size() == 3 and subs[0]["id"] == "mercado" and subs[1]["id"] == "tienda" and subs[2]["id"] == "pase", "Comercio: Mercado · Tienda · Pase de batalla")
	check(subs[1]["under_construction"] and subs[2]["under_construction"], "Tienda y Pase marcados en construcción")
	check(bar.get_node_or_null("Margin/Row/Title").text == "MENÚ", "Título MENÚ")
	check(bar.get_node_or_null("Margin/Row/Title").get_theme_color("font_color") == T.ACCENT_DEFAULT, "Título con color de acento")

	var log: Array = []
	bar.tab_selected.connect(func(id: String) -> void: log.append("tab:" + id))
	bar.subtab_selected.connect(func(t: String, s: String) -> void: log.append("sub:%s/%s" % [t, s]))
	bar.navigation_requested.connect(func(w: String, p: Dictionary) -> void: log.append("nav:" + w))
	bar.search_requested.connect(func() -> void: log.append("search"))
	bar.shop_requested.connect(func(src: String) -> void: log.append("shop:" + src))
	bar.settings_requested.connect(func() -> void: log.append("settings"))
	bar.close_requested.connect(func() -> void: log.append("close"))

	var expected_nav := {
		KEY_C: "inventory", KEY_N: "powers", KEY_L: "quests_window", KEY_M: "map_window",
		KEY_J: "codex_window", KEY_O: "social_window", KEY_H: "shelter",
	}
	for code in expected_nav:
		log.clear()
		var consumed: bool = bar.handle_shortcut(_key(code))
		check(consumed and log.has("nav:" + expected_nav[code]), "Atajo %s -> %s" % [OS.get_keycode_string(code), expected_nav[code]])
	check(bar.active_tab == "refugio" and bar.get_tab_button("refugio").button_pressed, "Pestaña activa marcada (Refugio)")
	check(bar.get_tab_button("refugio").get_node("Underline").visible and not bar.get_tab_button("equipo").get_node("Underline").visible, "Subrayado de acento solo en la activa")
	check(bar.get_tab_button("refugio").get_node("Content/Icon").tint == T.MENU_TAB_TEXT_ACTIVE and bar.get_tab_button("equipo").get_node("Content/Icon").tint.a == 0.0, "Icono de la pestaña activa resaltado")

	log.clear()
	check(bar.handle_shortcut(_key(KEY_P)), "Atajo P consumido")
	check(log.has("tab:comercio") and log.has("sub:comercio/mercado") and log.has("nav:marketplace_window"), "P -> Comercio › Mercado (sub-pestaña por defecto)")
	check(bar.commerce_popup.item_count == 3, "Submenú de Comercio con 3 entradas")

	log.clear()
	bar.commerce_popup.id_pressed.emit(2)
	check(log.has("sub:comercio/pase") and log.has("nav:battle_pass_window"), "Submenú: Pase de batalla")
	log.clear()
	bar.select_tab("comercio")
	check(log.has("sub:comercio/pase"), "Comercio recuerda la última sub-pestaña")

	log.clear()
	check(bar.handle_shortcut(_key(KEY_K, true)) and log.has("search") and log.has("nav:global_search"), "Ctrl+K -> búsqueda global")
	log.clear()
	check(not bar.handle_shortcut(_key(KEY_C, true)), "Ctrl+C no se interpreta como pestaña")
	check(bar.handle_shortcut(_key(KEY_F10)) and log.has("settings") and log.has("nav:options_menu"), "F10 -> Ajustes")
	log.clear()
	check(bar.handle_shortcut(_key(KEY_ESCAPE)) and log == ["close"], "Esc -> cerrar")
	log.clear()
	check(not bar.handle_shortcut(_key(KEY_Z)), "Tecla sin asignar no se consume")
	var released := _key(KEY_C)
	released.pressed = false
	check(not bar.handle_shortcut(released), "Soltar tecla no dispara")

	bar.set_currencies(12480, 340)
	check(bar.gold_label.amount_label.text == "12.480" and bar.prisms_label.amount_label.text == "340", "Oro 12.480 · Prismas 340")
	check(not bar.gold_label.add_button.visible and bar.prisms_label.add_button.visible, "Solo Prismas tiene botón +")
	log.clear()
	bar.prisms_label.add_button.pressed.emit()
	check(log.has("shop:prisms_plus") and log.has("sub:comercio/tienda") and log.has("nav:shop_window"), "Prismas + -> Comercio › Tienda")

	log.clear()
	bar.search_button.pressed.emit()
	bar.settings_button.pressed.emit()
	bar.close_button.pressed.emit()
	check(log.has("search") and log.has("settings") and log.has("close"), "Botones derecha: búsqueda, ajustes y cerrar")
	check(bar.search_button.get_node_or_null("Content/Keycap/Text").text == "Ctrl K", "Búsqueda muestra 'Ctrl K'")
	check(bar.close_button.get_node_or_null("Content/Keycap/Text").text == "Esc", "Cerrar muestra 'Esc'")

	log.clear()
	bar.set_active_tab("codice")
	check(log.is_empty() and bar.active_tab == "codice", "set_active_tab no emite señales")
	bar.accent = Color("#5aa9ff")
	check(bar.get_tab_button("codice").get_node("Underline").color == Color("#5aa9ff"), "Acento por universo se propaga")

	bar.configure_tabs([{"id": "a", "label": "Alfa", "key": KEY_1, "window": "alfa"}])
	check(bar.get_tab_ids() == ["a"] and bar.active_tab == "", "configure_tabs: tabla dirigida por datos")
	bar.configure_tabs(MenuBarScript.DEFAULT_TABS)
	check(bar.get_tab_ids().size() == 8, "Restaurar tabla canónica")
	check(not bar.capture_shortcuts, "capture_shortcuts=false por defecto (UIInputRouter manda)")
	await process_frame
	bar.queue_free()


func _test_orchestrator_bridge() -> void:
	print("\n--- 11. Puente con UIOrchestrator ---")
	var orch: Node = root.get_node_or_null("UIOrchestrator")
	var own := false
	if orch == null:
		orch = load("res://ui/orchestration/UIOrchestrator.gd").new()
		root.add_child(orch)
		own = true
		await process_frame
	check(orch.has_method("connect_menu_bar"), "UIOrchestrator.connect_menu_bar existe")
	var bar = load("res://ui/menu/menu_bar.tscn").instantiate()
	root.add_child(bar)
	await process_frame
	orch.connect_menu_bar(bar)
	orch.connect_menu_bar(bar)
	check(bar.navigation_requested.get_connections().size() == 1, "connect_menu_bar es idempotente")
	var unhandled := [""]
	orch.menu_navigation_unhandled.connect(func(w: String, _p: Dictionary) -> void: unhandled[0] = w)
	# Paso 9: la Tienda ya está registrada; una ventana pendiente sigue avisando.
	bar.navigation_requested.emit("ventana_pendiente", {})
	check(unhandled[0] == "ventana_pendiente", "Ventana sin registrar -> menu_navigation_unhandled")
	check(orch.registry.is_registered("shop_window") and orch.registry.is_registered("battle_pass_window"), "Tienda y Pase registrados (Paso 9)")
	check(orch.registry.is_registered("codex_window") and orch.registry.is_registered("marketplace_window"), "Ventanas existentes (Códice, Mercado) registradas para el menú")
	bar.queue_free()
	await process_frame
	if own:
		orch.queue_free()
