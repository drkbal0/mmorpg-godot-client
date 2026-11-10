extends SceneTree
## Headless checks for HUDv2.
## Run: Godot --headless --path clients/godot-mmo-client -s res://tests/unit/test_hud_v2.gd
## Exit code 0 = all pass.

const T = preload("res://ui/hud_tokens.gd")

var _fails: Array[String] = []
var _checks := 0
var _draws := {}


func check(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_fails.append(msg)
		printerr("  FAIL: ", msg)


func _initialize() -> void:
	_run.call_deferred()


func _count_draws(node: CanvasItem, key: String) -> void:
	_draws[key] = 0
	node.draw.connect(func() -> void: _draws[key] += 1)


func _run() -> void:
	print("== HUDv2 tests ==")
	# --- Fonts: tabular digits ------------------------------------------------
	for w in ["regular", "medium", "semibold", "bold"]:
		var f := T.font(w)
		check(f is FontVariation, "font %s es FontVariation" % w)
		var fv := f as FontVariation
		check(fv != null and int(fv.opentype_features.get("tnum", 0)) == 1, "font %s tiene tnum=1" % w)
		check(fv != null and fv.base_font != null and fv.base_font.resource_path.begins_with("res://design_ref/fonts/BarlowSemiCondensed"), "font %s usa Barlow Semi Condensed" % w)
		var w1 := f.get_string_size("1111", HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		var w8 := f.get_string_size("8888", HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		check(is_equal_approx(w1, w8), "font %s digitos tabulares (1111=%.2f, 8888=%.2f)" % [w, w1, w8])
	# Sanity: without tnum Barlow's '1' is narrower (proves the feature is active).
	var plain := FontVariation.new()
	plain.base_font = (T.font("bold") as FontVariation).base_font
	var p1 := plain.get_string_size("1111", HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	var p8 := plain.get_string_size("8888", HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	print("  info: sin tnum 1111=%.2f 8888=%.2f" % [p1, p8])

	# --- Tokens: colors, radii & geometry per prompt spec ---------------------
	check(T.ACCENT_DEFAULT == Color("#46e3c1"), "token ACCENT_DEFAULT es #46e3c1 (Nexo)")
	check(T.PANEL_BG == Color(Color("#0d1216"), 0.97), "token PANEL_BG es #0d1216 @ 0.97")
	check(T.PANEL_EDGE == Color(1, 1, 1, 0.09) and is_equal_approx(T.PANEL_EDGE_WIDTH, 1.5), "token PANEL_EDGE blanco al 9% de 1.5px")
	check(T.SLOT_READY == Color("#1c2a33"), "token SLOT_READY es #1c2a33")
	check(T.SLOT_LOCKED == Color("#11181d"), "token SLOT_LOCKED es #11181d")
	check(T.SLOT_NEUTRAL == Color("#1a252c"), "token SLOT_NEUTRAL es #1a252c")
	check(T.SLOT_EMPTY == Color("#0a0f13") and T.SLOT_EMPTY_BORDER == Color(1, 1, 1, 0.06), "token SLOT_EMPTY es #0a0f13 + blanco 6%")
	check(T.WELL == Color("#070a0c"), "token WELL es #070a0c")
	check(T.BUTTON_BG == Color("#18242b") and T.BUTTON_BORDER == Color(1, 1, 1, 0.08), "token BUTTON_BG es #18242b + blanco 8%")
	check(T.TEXT == Color("#eef2f4"), "token TEXT es #eef2f4")
	check(T.TEXT_SECONDARY == Color("#9aa6ae"), "token TEXT_SECONDARY es #9aa6ae")
	check(T.TEXT_ZERO == Color("#7c8992"), "token TEXT_ZERO es #7c8992")
	check(T.TEXT_KEY == Color("#c3ccd3"), "token TEXT_KEY es #c3ccd3")
	check(T.HEALTH == Color("#3ccf73") and T.HEALTH_REGEN == Color("#a9f0c3"), "tokens HEALTH (#3ccf73) y REGEN (#a9f0c3)")
	check(T.MANA == Color("#3f82f2") and T.MANA_COST == Color("#8fbaff"), "tokens MANA (#3f82f2) y COST (#8fbaff)")
	check(T.GOLD == Color("#f5c35b") and T.ALLY == Color("#6cb8ff"), "tokens GOLD (#f5c35b) y ALLY (#6cb8ff)")
	# Radii tokens
	check(T.ABILITY_RADIUS == 14, "radio tile habilidad = 14")
	check(T.SPELL_RADIUS == 12, "radio tile chico = 12")
	check(T.ITEM_RADIUS == 12, "radio ranura = 12")
	check(T.BUFF_RADIUS == 8, "radio buff = 8")
	check(T.BUTTON_RADIUS == 8, "radio botón = 8")
	check(T.GOLD_BOX_RADIUS == 10, "radio caja oro = 10")
	check(T.HEALTH_BAR_RADIUS == 10 and T.MANA_BAR_RADIUS == 7, "radios barras 10 (vida) y 7 (maná)")
	check(T.STATS_TAB_RADIUS == 18, "radio pestaña stats = 18 (arriba)")
	# Stats tab geometry (x=988, bottom=14, ancho 272)
	check(is_equal_approx(T.STATS_TAB_RECT.position.x, 988.0) and is_equal_approx(T.STATS_TAB_RECT.size.x, 272.0), "pestaña stats x=988 ancho 272")
	check(is_equal_approx(T.STATS_TAB_RECT.end.y, 446.0), "pestaña stats bottom=14 (y=446)")

	# --- HUD scene ------------------------------------------------------------
	var hud: Control = load("res://ui/components/HUDv2/hud.tscn").instantiate()
	root.add_child(hud)
	await process_frame
	check(hud.size == T.HUD_SIZE, "HUD mide 1360x460 (es %s)" % hud.size)
	check(is_equal_approx(hud.anchor_left, 0.5) and is_equal_approx(hud.anchor_right, 0.5) and is_equal_approx(hud.anchor_top, 1.0) and is_equal_approx(hud.anchor_bottom, 1.0), "HUD anclado abajo-centro")
	check(hud.theme != null and hud.theme.resource_path == "res://ui/hud_theme.tres", "HUD usa hud_theme.tres")

	_count_draws(hud.shape_node, "shape")
	_count_draws(hud.get_ability(0), "ability")
	_count_draws(hud.health_bar, "health")

	# set_accent
	var acc := Color("#f2b63d")
	hud.set_accent(acc)
	check(hud.shape_node.accent == acc and hud.get_ability(2).accent == acc and hud.portrait.accent == acc and hud.get_item(5).accent == acc, "set_accent propaga a componentes")

	# set_shape
	for s in ["trapecio", "escalonada", "curva", "Trapecio"]:
		hud.set_shape(s)
		check(hud.shape_node.shape == s.to_lower(), "set_shape(%s)" % s)
		var outline: PackedVector2Array = hud.shape_node.get_outline()
		check(outline.size() >= 4, "outline %s tiene puntos" % s)
		check(hud.shape_node.has_stats_tab() == (s.to_lower() != "escalonada"), "StatsTab solo en trapecio/curva (%s)" % s)
	hud.set_shape("trapecio")
	var trap: PackedVector2Array = hud.shape_node.get_outline()
	check(trap == PackedVector2Array([Vector2(18, 461), Vector2(66, 276), Vector2(1294, 276), Vector2(1342, 461)]), "trapecio exacto")
	check(T.SHADOW_LAYERS.size() == 3 and T.SHADOW_LAYERS.has(Vector2(-2, 0.12)) and T.SHADOW_LAYERS.has(Vector2(-4, 0.08)) and T.SHADOW_LAYERS.has(Vector2(-6, 0.05)), "sombras -2/-4/-6 @ .12/.08/.05")

	# set_level
	hud.set_level(7, 0.5)
	check(hud.portrait.level == 7 and is_equal_approx(hud.portrait.xp_fraction, 0.5), "set_level")
	hud.set_level(8, 1.7)
	check(is_equal_approx(hud.portrait.xp_fraction, 1.0), "xp_fraction se limita a 1")

	# set_health / set_mana
	hud.set_health(612, 1003, 3.9)
	check(is_equal_approx(hud.health_bar.current, 612) and is_equal_approx(hud.health_bar.max_value, 1003) and is_equal_approx(hud.health_bar.regen, 3.9), "set_health")
	hud.set_health(5000, 1003, 0)
	check(is_equal_approx(hud.health_bar.current, 1003), "set_health limita a max")
	hud.set_mana(200, 403)
	check(is_equal_approx(hud.mana_bar.get_fraction(), 200.0 / 403.0), "set_mana")

	# set_ability
	hud.set_ability(0, 2, 5, 24, false, 0, 6.0)
	var q = hud.get_ability(0)
	check(q.rank == 2 and q.max_rank == 5 and q.cost == 24 and not q.locked, "set_ability props")
	check(is_equal_approx(q.get_cooldown_fraction(), 1.0), "cooldown arranca en 1.0")
	hud.set_ability(3, 0, 3, 100, true, 6, 0.0)
	check(hud.get_ability(3).locked and hud.get_ability(3).unlock_level == 6, "habilidad bloqueada Nv. 6")
	hud.set_ability(9, 1, 1, 1, false, 0, 0)  # out of range -> push_error, no crash

	# set_spell
	hud.set_spell(0, 87.0)
	hud.set_spell(1, 39.0)
	check(is_equal_approx(hud.get_spell(0).cooldown, 87.0) and is_equal_approx(hud.get_spell(1).cooldown, 39.0), "set_spell D/F")

	# set_item / trinket / gold
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color.CORNFLOWER_BLUE)
	var tex := ImageTexture.create_from_image(img)
	hud.set_item(0, tex, 23)
	hud.set_item(1, null, 0)
	check(hud.get_item(0).icon == tex and hud.get_item(0).stacks == 23 and hud.get_item(0).has_item(), "set_item con icono")
	check(not hud.get_item(1).has_item(), "slot vacio")
	check(hud.items.size() == T.ITEM_COLUMNS * T.ITEM_ROWS, "grid 3x2")
	hud.set_trinket(2)
	check(hud.trinket.charges == 2, "set_trinket")
	hud.set_gold(1665)
	check(hud.gold_box.amount == 1665, "set_gold")

	# LivePortrait3D tests (Fase 9.13 / ADR 095)
	hud.portrait._setup_live_3d()
	check(hud.portrait.live_portrait != null, "LivePortrait3D instanciado en portrait")
	check(hud.portrait.live_portrait.size == Vector2i(256, 256), "LivePortrait3D resolucion 256x256")
	check(hud.portrait.live_portrait.own_world_3d, "LivePortrait3D own_world_3d activo (aislamiento 3D)")
	check(hud.portrait.portrait_texture != null, "portrait_texture vinculado al SubViewport")
	hud.portrait.flash_damage()
	check(hud.portrait.live_portrait._is_flashing, "flash_damage activa tween de daño")

	# Quickslots Drag & Drop y Consumo Hotbar [1]-[6]
	var slot0 = hud.get_item(0)
	slot0.assign_item("Poción de Vida", tex, 5, "pot-uuid-123")
	check(slot0.item_name == "Poción de Vida", "Quickslot 1 asigna item_name")
	check(slot0.item_id == "pot-uuid-123", "Quickslot 1 asigna item_id")
	check(slot0.stacks == 5, "Quickslot 1 tiene 5 stacks")
	check(slot0.has_item(), "Quickslot 1 has_item == true")
	check("Poción de Vida" in slot0.tooltip_text, "Quickslot 1 tooltip formateado")
	var use_ok = slot0.use_item()
	check(use_ok, "use_item consume con exito")
	check(slot0.stacks == 4, "use_item decrementa stack a 4")
	check(slot0.cooldown_remaining > 0.0, "use_item activa cooldown de 15s")
	var second_use = slot0.use_item()
	check(not second_use, "use_item bloqueado mientras esta en cooldown")
	slot0.clear_item()
	check(not slot0.has_item() and slot0.item_name == "", "clear_item vacia la ranura")

	# Validacion Drag & Drop desde mochila
	var mock_item = Control.new()
	mock_item.set_meta("item_name", "Pergamino de Retorno")
	mock_item.set_meta("texture", tex)
	mock_item.set_meta("quantity", 3)
	mock_item.set_meta("item_id", "scroll-999")
	var drag_payload = {"type": "inventory_item", "item_node": mock_item}
	check(slot0._can_drop_data(Vector2.ZERO, drag_payload), "slot0 acepta drop de inventory_item")
	slot0._drop_data(Vector2.ZERO, drag_payload)
	check(slot0.item_name == "Pergamino de Retorno" and slot0.stacks == 3, "slot0 drop_data asigna items arrastrados")
	mock_item.free()

	# Quickslot public API & Hotkey triggers
	check(hud.use_quickslot(0), "use_quickslot(0) con Pergamino consume con éxito")
	check(not hud.use_quickslot(0), "segundo use_quickslot(0) en cooldown retorna false")
	hud.set_item(1, tex, 1, "Poción de Maná", "pot-mana-1")
	check(hud.use_quickslot(1), "use_quickslot(1) consume con éxito")
	hud.set_shape("curva")
	check(hud.shape == "curva", "set_shape('curva') aplica forma curva")
	hud.set_shape("escalonada")
	check(hud.shape == "escalonada", "set_shape('escalonada') aplica forma escalonada")
	hud.set_accent(Color("#5aa9ff"))
	check(hud.accent == Color("#5aa9ff"), "set_accent cambia color de acento a #5aa9ff")

	# set_stats
	hud.set_stats({"attack_damage": 89, "attack_speed": 0.72, "armor_pen": "0 | 0%", "move_speed": 348.0})
	check(hud.stat_rows["attack_damage"].value_text == "89", "stat int")
	check(hud.stat_rows["attack_speed"].value_text == "0.72", "stat float")
	check(hud.stat_rows["armor_pen"].value_text == "0 | 0%", "stat string")
	check(hud.stat_rows["move_speed"].value_text == "348", "stat float entero")
	check(hud.stat_rows.size() == T.STAT_SCHEMA.size(), "16 filas de stats")
	check(hud.stat_rows["armor_pen"].get_value_color() == T.TEXT_ZERO, "valor cero '0 | 0%' atenua a #7c8992")
	check(hud.stat_rows["attack_damage"].get_value_color() == T.TEXT, "valor no-cero '89' usa #eef2f4")
	check(is_equal_approx(hud.buffs_root.position.x, 240.0) and is_equal_approx(hud.buffs_root.position.y, 262.0), "buffs en (x=240, y=262)")
	check(is_equal_approx(hud.stats_root.position.x, 988.0) and is_equal_approx(hud.stats_root.size.x, 272.0), "stats root en x=988 ancho 272")

	# set_buffs
	hud.set_buffs([{"color": Color.RED, "stacks": 3}, {"color": Color.BLUE}, {"color": Color.GREEN, "duration_fraction": 0.5}])
	await process_frame
	check(hud.get_buff_count() == 3, "set_buffs crea 3 iconos")
	hud.set_buffs([])
	await process_frame
	check(hud.get_buff_count() == 0, "set_buffs vacia")

	# push_feed
	for i in 8:
		hud.push_feed("04:%02d" % i, "Jugador%d" % i, "Campeón", "Baliza de control", i % 2 == 0)
	await process_frame
	check(hud.get_feed_count() == T.FEED_MAX_LINES, "feed limitado a %d lineas" % T.FEED_MAX_LINES)
	var last = hud.feed_root.get_child(hud.get_feed_count() - 1)
	check(last.player == "Jugador7" and last.size.y == T.FEED_LINE_HEIGHT and last.size.x > 100, "feed_line pildora medida")

	# Let a few frames run: cooldowns tick and _draw() executes for all shapes.
	for s in ["trapecio", "escalonada", "curva"]:
		hud.set_shape(s)
		for i in 3:
			await process_frame
	check(q.cooldown < 6.0, "cooldown descuenta en _process")
	check(_draws["shape"] >= 3, "hud_shape _draw ejecutado (%d)" % _draws["shape"])
	check(_draws["ability"] >= 1, "ability_slot _draw ejecutado")
	check(_draws["health"] >= 1, "resource_bar _draw ejecutado")

	# Demo scene loads and runs a tick.
	var demo: Control = load("res://ui/hud_demo.tscn").instantiate()
	root.add_child(demo)
	await process_frame
	check(demo.level == 5, "demo: Nivel inicial = 5")
	check(is_equal_approx(demo.xp, 0.30), "demo: XP inicial = 30% (0.30)")
	check(demo.hud.get_ability(0).rank == 3 and demo.hud.get_ability(0).cost == 24, "demo: Q 3/5 coste 24")
	check(demo.hud.get_ability(1).rank == 1 and demo.hud.get_ability(1).cost == 50, "demo: W 1/5 coste 50")
	check(demo.hud.get_ability(2).rank == 1 and demo.hud.get_ability(2).cost == 60, "demo: E 1/5 coste 60")
	check(demo.hud.get_ability(3).locked and demo.hud.get_ability(3).cost == 100 and demo.hud.get_ability(3).unlock_level == 6, "demo: R bloqueada Nv.6 coste 100")
	check(absf(demo.hud.get_spell(0).cooldown - 87.0) < 0.1, "demo: D 87s")
	check(absf(demo.hud.get_spell(1).cooldown - 39.0) < 0.1, "demo: F 39s")
	check(demo.hud.get_item(0).stacks == 23, "demo: Item 1 x23")
	check(demo.hud.trinket.charges == 1, "demo: Amuleto 1")
	check(demo.gold == 1665, "demo: Oro 1665")
	check(is_equal_approx(demo.hp, 612.0) and is_equal_approx(demo.hp_max, 1003.0) and is_equal_approx(demo.hud.health_bar.regen, 3.9), "demo: Vida 612/1003 (+3.9)")
	check(is_equal_approx(demo.mana, 403.0) and is_equal_approx(demo.mana_max, 403.0), "demo: Maná 403/403")
	demo._on_tick()
	demo._cast(0)
	await process_frame
	check(demo.hud.get_ability(0).cooldown > 0.0, "demo: lanzar Q pone cooldown")
	var map_tex: Texture2D = demo.get_node("Map").texture
	check(map_tex is AtlasTexture and (map_tex as AtlasTexture).atlas.resource_path == "res://design_ref/mapa-fondo.jpg", "demo: fondo mapa-fondo.jpg")
	var tick: Timer = demo.get_node("Tick")
	check(tick != null, "demo: Timer existe")
	check(not tick.is_stopped(), "demo: Timer corriendo (%s)" % tick.time_left)
	demo.queue_free()
	hud.queue_free()
	await process_frame

	print("== %d checks, %d fallos ==" % [_checks, _fails.size()])
	quit(0 if _fails.is_empty() else 1)
