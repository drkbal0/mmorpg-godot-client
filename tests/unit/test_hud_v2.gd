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

	# set_stats
	hud.set_stats({"attack_damage": 89, "attack_speed": 0.72, "armor_pen": "0 | 0%", "move_speed": 348.0})
	check(hud.stat_rows["attack_damage"].value_text == "89", "stat int")
	check(hud.stat_rows["attack_speed"].value_text == "0.72", "stat float")
	check(hud.stat_rows["armor_pen"].value_text == "0 | 0%", "stat string")
	check(hud.stat_rows["move_speed"].value_text == "348", "stat float entero")
	check(hud.stat_rows.size() == T.STAT_SCHEMA.size(), "16 filas de stats")

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
