extends SceneTree
## Pruebas headless: HUD de combate reactivo final v2 + HUD de raid para sanador.
## Ejecutar: Godot --headless --path clients/godot-mmo-client -s tests/unit/test_hud_combat_and_raid.gd
## Código de salida 0 = todo PASS.

const T = preload("res://ui/tokens/hud_tokens.gd")
const RaidHUD = preload("res://ui/components/RaidHUD/RaidHUD.gd")

var _fails: Array[String] = []
var _checks := 0


func check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("  PASS: ", msg)
	else:
		_fails.append(msg)
		printerr("  FAIL: ", msg)


func _initialize() -> void:
	_run.call_deferred()


func _frame() -> void:
	await process_frame
	await process_frame


func _run() -> void:
	print("== HUD de combate v2 + HUD de raid ==")
	await _test_hud_combat()
	await _test_raid()
	_test_mana_longevity()
	print("\n%d comprobaciones, %d fallos" % [_checks, _fails.size()])
	if _fails.is_empty():
		print("RESULTADO: 100% PASS")
	else:
		print("RESULTADO: FAIL")
	quit(0 if _fails.is_empty() else 1)


# ----------------------------------------------------------------------------
func _test_hud_combat() -> void:
	print("-- HUDv2: modo combate / exploración --")
	var hud: Control = load("res://ui/components/HUDv2/hud.tscn").instantiate()
	root.add_child(hud)
	await _frame()

	hud.set_quests(["Cazar lobos (3/8)", "Hablar con Mira"])
	var external_chat := Control.new()
	root.add_child(external_chat)
	hud.register_chat(external_chat)
	var mode_events: Array = []
	hud.combat_mode_changed.connect(func(c: bool) -> void: mode_events.append(c))

	check(not hud.is_in_combat(), "Arranca en exploración")
	check(is_equal_approx(hud.feed_root.modulate.a, 1.0), "Exploración: chat al 100 %")
	check(hud.quest_tracker.visible and hud.quest_tracker.get_child_count() == 2, "Exploración: rastreador de misiones visible (2)")
	check(hud.btn_recall.visible and hud.btn_shop.visible, "Exploración: botones de utilidad visibles")

	hud.set_combat_mode(true)
	check(hud.is_in_combat(), "set_combat_mode(true) entra en combate")
	check(is_equal_approx(hud.feed_root.modulate.a, 0.60), "Combate: chat atenuado a 0.60")
	check(is_equal_approx(hud.get_chat_alpha(), T.COMBAT_CHAT_ALPHA), "get_chat_alpha() = COMBAT_CHAT_ALPHA")
	check(is_equal_approx(external_chat.modulate.a, 0.60), "Combate: chat externo registrado también al 0.60")
	check(not hud.quest_tracker.visible, "Combate: misiones ocultas")
	check(not hud.btn_recall.visible and not hud.btn_shop.visible, "Combate: botones de utilidad ocultos")
	check(hud.combat_hint.visible and hud.combat_hint.text == "+2 misiones ocultas durante el combate", "Combate: aviso '+2 misiones ocultas durante el combate'")
	check(hud.portrait.visible and hud.health_bar.visible and hud.abilities[0].visible, "Combate: retrato, vida y habilidades siguen visibles")

	hud.set_combat_mode(false)
	check(is_equal_approx(hud.feed_root.modulate.a, 1.0) and is_equal_approx(external_chat.modulate.a, 1.0), "Exploración: opacidad del chat restaurada a 1.0")
	check(hud.quest_tracker.visible and hud.btn_recall.visible and hud.btn_shop.visible, "Exploración: misiones y utilidad de nuevo visibles")
	check(not hud.combat_hint.visible, "Exploración: aviso de misiones ocultas apagado")
	check(mode_events == [true, false], "Señal combat_mode_changed emitida en cada cambio (%s)" % str(mode_events))
	hud.set_combat_mode(false)
	check(mode_events.size() == 2, "Sin señal si el modo no cambia")

	print("-- HUDv2: interrupciones en quickslots --")
	hud.set_ability(0, 3, 5, 40, false, 1, 0.0)    # Q corte (interrumpe)
	hud.set_ability(1, 2, 5, 60, false, 1, 0.0)    # W escudo
	hud.set_ability(2, 1, 5, 50, false, 1, 5.0)    # E aturdimiento en enfriamiento
	hud.set_ability(3, 0, 3, 100, true, 6, 0.0)    # R bloqueada
	hud.set_interrupt_slots([0, 2, 3])
	check(hud.get_glowing_interrupt_slots().is_empty(), "Sin canalización enemiga: ninguna habilidad brilla")
	check(hud.abilities[0].get_border_color() == hud.accent, "Q sin brillo usa el acento")
	hud.set_interrupt_highlight(true)
	var glowing: Array[int] = hud.get_glowing_interrupt_slots()
	check(str(glowing) == "[0, 2]", "Objetivo canaliza interrumpible: brillan Q (corte) y E (aturdir) %s" % str(glowing))
	check(not hud.abilities[1].is_interrupt_glowing(), "W (no interrumpe) no brilla")
	check(not hud.abilities[3].is_interrupt_glowing(), "R bloqueada no brilla aunque sea de corte")
	check(hud.abilities[0].get_border_color() == T.INTERRUPT_GLOW and T.INTERRUPT_GLOW == Color("#f5c35b"), "Borde dorado #f5c35b en Q")
	hud.set_interrupt_highlight(false)
	check(hud.get_glowing_interrupt_slots().is_empty(), "Fin de la canalización: brillo apagado")
	hud.abilities[1].set_interrupt_highlight(true)
	check(not hud.abilities[1].is_interrupt_glowing(), "ability_slot.set_interrupt_highlight respeta can_interrupt")
	hud.abilities[1].set_interrupt_highlight(false)

	print("-- HUDv2: vida + escudo --")
	hud.set_health(18420.0, 30100.0, 0.0)
	hud.set_shield(2700.0)
	await _frame()
	var hb = hud.health_bar
	check(is_equal_approx(hb.shield, 2700.0), "set_shield guarda 2.700")
	check(is_equal_approx(hb.get_shield_fraction(), 2700.0 / 30100.0), "Tramo blanco = escudo / vida máx (%.4f)" % hb.get_shield_fraction())
	check(hb.get_display_text() == "18.420 / 30.100  +2.700 escudo", "Texto '18.420 / 30.100  +2.700 escudo' (%s)" % hb.get_display_text())
	check(T.SHIELD == Color(1, 1, 1, 0.55), "Token SHIELD blanco al 55 %")
	hud.set_health(29000.0, 30100.0, 0.0)
	check(is_equal_approx(hb.get_shield_fraction(), 1100.0 / 30100.0), "Escudo recortado al final de la barra")
	hud.set_shield(0.0)
	check(hb.get_shield_fraction() == 0.0 and not hb.get_display_text().contains("escudo"), "Sin escudo: sin tramo ni texto")

	print("-- HUDv2: iconos vectoriales de 16 px en atributos --")
	var row = hud.stat_rows["attack_damage"]
	check(row.icon_size == 16 and T.STAT_ROW_ICON == T.STAT_ICON_SIZE_HUD, "Fila de stat con icono de 16 px")
	check(row.get_icon_key() == "dano" and row.has_vector_icon(), "attack_damage -> icono SVG canónico 'dano'")
	var all_icons := true
	for id in hud.stat_rows:
		all_icons = all_icons and hud.stat_rows[id].has_vector_icon()
	check(all_icons, "Las 16 filas de atributos tienen icono vectorial")
	check(row.get_icon_layers()[0]["d"] == T.STATS["dano"]["path"], "Capa del icono = path SVG del token")

	hud.queue_free()
	external_chat.queue_free()
	await _frame()


# ----------------------------------------------------------------------------
func _roster() -> Array:
	var names := ["Toro", "Brisa", "Kael", "Nox", "Vela", "Ulric", "Sasha", "Dren", "Ivo", "Lune",
		"Mira", "Joao", "Aren", "Pim", "Kora", "Tess", "Bram", "Oda", "Rhea", "Finn"]
	var classes := ["tanque", "sanador", "mago", "brujo", "arquero"]
	var out: Array = []
	for i in names.size():
		out.append({"name": names[i], "class": classes[i % 5], "hp": 800.0 + i * 10.0, "hp_max": 1000.0, "distance": 10.0})
	return out


func _test_raid() -> void:
	print("-- RaidHUD: 20 marcos --")
	var raid: Control = load("res://ui/components/RaidHUD/RaidHUD.tscn").instantiate()
	root.add_child(raid)
	await _frame()
	check(raid.get_frame_count() == 20, "RaidHUD crea 20 marcos")
	check(raid.group_columns.size() == 4 and raid.group_columns[0].get_child_count() == 5, "4 grupos de 5")
	raid.set_roster(_roster())
	await _frame()
	check(raid.get_visible_frame_count() == 20, "20 marcos visibles tras set_roster")
	check(raid.header.text == "RAID · 20", "Cabecera 'RAID · 20'")
	var names_ok := true
	var vitals_ok := true
	for i in 20:
		var fr = raid.get_frame(i)
		names_ok = names_ok and fr.player_name == _roster()[i]["name"]
		vitals_ok = vitals_ok and is_equal_approx(fr.hp, 800.0 + i * 10.0) and is_equal_approx(fr.hp_max, 1000.0)
	check(names_ok, "Los 20 marcos tienen su nombre")
	check(vitals_ok, "Los 20 marcos tienen su vida")
	check(raid.get_frame(0).player_class == "tanque" and raid.get_frame(0).get_class_color() == Color("#5aa9ff"), "Clase y color de clase")
	check(raid.get_frame(0).size == T.RAID_FRAME_SIZE, "Marco compacto 128×42")
	check(raid.get_frame(0).get_status_text() == "80 %", "Estado '80 %'")
	raid.set_roster(_roster().slice(0, 10))
	check(raid.get_visible_frame_count() == 10 and raid.header.text == "RAID · 10", "Raid de 10 oculta el resto")
	raid.set_roster(_roster())

	print("-- RaidHUD: daño previsto + curación entrante --")
	var toro = raid.get_frame_by_id("Toro")
	raid.update_member("Toro", {"hp": 580.0, "predicted_damage": 300.0, "incoming_heal": 120.0})
	await _frame()
	var span: Vector2 = toro.get_predicted_span()
	check(is_equal_approx(span.x, 0.28) and is_equal_approx(span.y, 0.30), "Achurado de 28 %% a 58 %% (igual que MMO-Raid) %s" % str(span))
	var heal: Vector2 = toro.get_incoming_heal_span()
	check(is_equal_approx(heal.x, 0.58) and is_equal_approx(heal.y, 0.12), "Curación entrante de 58 %% a 70 %% %s" % str(heal))
	check(is_equal_approx(toro.get_projected_health(), 400.0), "Vida proyectada 580 − 300 + 120 = 400")
	check(toro.last_hatch_stripes > 0, "Se dibujan franjas achuradas (%d)" % toro.last_hatch_stripes)
	check(T.RAID_PREDICTED_A == Color(245 / 255.0, 195 / 255.0, 91 / 255.0, 0.75) and T.RAID_INCOMING_HEAL == Color(60 / 255.0, 207 / 255.0, 115 / 255.0, 0.35), "Colores achurado dorado y verde translúcido")
	check(not toro.is_lethal_prediction(), "300 de daño sobre 580 no es letal")
	raid.update_member("Toro", {"hp": 950.0, "incoming_heal": 500.0})
	check(is_equal_approx(toro.get_incoming_heal_span().y, 0.05), "Curación entrante recortada a la vida que falta")
	raid.update_member(1, {"hp": 200.0, "predicted_damage": 450.0, "incoming_heal": 100.0})
	var brisa = raid.get_frame(1)
	check(is_equal_approx(brisa.get_predicted_span().x, 0.0) and is_equal_approx(brisa.get_predicted_span().y, 0.2), "Daño previsto acotado a la vida restante")
	check(brisa.is_lethal_prediction() and str(raid.get_lethal_members()) == "[\"Brisa\"]", "Predicción letal detectada para triaje")
	raid.update_member(1, {"hp": 900.0, "predicted_damage": 0.0, "incoming_heal": 0.0})
	await _frame()
	check(brisa.last_hatch_stripes == 0 and brisa.get_predicted_span().y == 0.0, "Sin daño previsto: sin achurado")

	print("-- RaidHUD: aggro, purificables, alcance --")
	raid.set_aggro_target("Toro")
	check(toro.has_aggro and toro.get_border_color() == Color("#ff6b6b") and toro.get_border_width() == 2, "Aggro: borde rojo #ff6b6b de 2 px")
	check(not brisa.has_aggro and brisa.get_border_color() == T.RAID_FRAME_EDGE, "Resto sin borde rojo")
	var a0: float = toro.get_aggro_pulse_alpha()
	toro._process(0.33)
	var a1: float = toro.get_aggro_pulse_alpha()
	check(not is_equal_approx(a0, a1) and a1 >= 0.55 and a1 <= 1.0, "El borde de aggro pulsa (%.2f -> %.2f)" % [a0, a1])
	raid.set_aggro_target("Kael")
	check(not toro.has_aggro and raid.get_frame_by_id("Kael").has_aggro, "El aggro pasa a Kael y se quita de Toro")
	raid.update_member("Nox", {"dispels": ["magia", "veneno"]})
	var nox = raid.get_frame_by_id("Nox")
	check(nox.dispels.size() == 2 and T.dispel_color("magia") == Color("#b47bff"), "Purificables en rombo (magia #b47bff, veneno)")
	check(nox.tooltip_text.contains("purificable: Magia") and nox.tooltip_text.contains("purificable: Veneno"), "Tooltip nombra los purificables (no solo color)")
	raid.update_member("Vela", {"distance": 42.0})
	var vela = raid.get_frame_by_id("Vela")
	check(vela.is_out_of_range() and is_equal_approx(vela.modulate.a, 0.4), "Fuera de alcance (42 m > 40 m): marco al 40 %")
	check(vela.get_status_text() == "42 m", "Estado muestra '42 m'")
	raid.update_member("Vela", {"distance": 40.0})
	check(not vela.is_out_of_range() and is_equal_approx(vela.modulate.a, 1.0), "A 40 m sigue en alcance")
	raid.update_member("Ivo", {"hp": 0.0})
	var ivo = raid.get_frame_by_id("Ivo")
	check(ivo.is_dead() and ivo.get_status_text() == "Muerto · resucitar" and is_equal_approx(ivo.modulate.a, 0.6), "Muerto: 'Muerto · resucitar' al 60 %")

	print("-- RaidHUD: clics de sanador --")
	var got: Array = []
	raid.heal_requested.connect(func(id: String) -> void: got.append("heal:" + id))
	raid.shield_requested.connect(func(id: String) -> void: got.append("shield:" + id))
	raid.dispel_requested.connect(func(id: String) -> void: got.append("dispel:" + id))
	var click := func(fr: Control, btn: int, shift: bool) -> void:
		var ev := InputEventMouseButton.new()
		ev.button_index = btn
		ev.pressed = true
		ev.shift_pressed = shift
		fr._gui_input(ev)
	click.call(toro, MOUSE_BUTTON_LEFT, false)
	click.call(toro, MOUSE_BUTTON_RIGHT, false)
	click.call(nox, MOUSE_BUTTON_LEFT, true)
	check(got == ["heal:Toro", "shield:Toro", "dispel:Nox"], "Clic sana, clic der. escuda, Shift+clic purifica %s" % str(got))
	check(nox.selected and not toro.selected, "El último clic selecciona el marco")

	print("-- RaidHUD: alerta de mecánica de jefe --")
	var finished := [false]
	raid.boss_alert_finished.connect(func() -> void: finished[0] = true)
	raid.show_boss_alert("¡ALÉJATE DEL GRUPO EN {s}s!", 3.0, "away", "Terremoto rúnico")
	check(raid.is_alert_visible(), "Alerta visible")
	check(raid.get_alert_text() == "¡ALÉJATE DEL GRUPO EN 3s!", "Texto '¡ALÉJATE DEL GRUPO EN 3s!' (%s)" % raid.get_alert_text())
	check(raid.alert_title.text == "¡ALÉJATE DEL GRUPO EN 3s!" and raid.alert_count.text == "3", "Etiquetas de título y cuenta atrás")
	check(raid.alert_arrow.visible and is_equal_approx(raid.get_alert_arrow_rotation(), PI * 0.5), "Flecha direccional orientada")
	raid.tick(1.2)
	check(raid.get_alert_text() == "¡ALÉJATE DEL GRUPO EN 2s!", "Cuenta atrás baja a 2s")
	raid.tick(2.0)
	check(not raid.is_alert_visible() and finished[0], "La alerta se oculta al llegar a 0 y emite boss_alert_finished")
	raid.show_boss_alert("Todos a la izquierda", 2.0, "left")
	check(is_equal_approx(raid.get_alert_arrow_rotation(), 0.0) and raid.get_alert_text() == "Todos a la izquierda", "Alerta 'Todos a la izquierda' con flecha a la izquierda")
	raid.hide_boss_alert()
	check(not raid.is_alert_visible(), "hide_boss_alert la oculta")

	print("-- RaidHUD: telemetría de maná --")
	raid.set_mana(5200.0, 10000.0, 52.0)
	check(is_equal_approx(raid.get_mana_longevity(), 100.0), "5.200 de maná a 52/s = 100 s")
	check(raid.mana_label.text == "Maná 52 % · dura ~1:40 a este ritmo", "Texto '%s'" % raid.mana_label.text)
	check(is_equal_approx(raid.mana_bar.get_fraction(), 0.52), "Barra de maná al 52 %")
	raid.set_mana(5200.0, 10000.0, 0.0)
	check(raid.mana_label.text == "Maná 52 % · sin gasto", "Sin gasto: 'sin gasto'")

	raid.queue_free()
	await _frame()


# ----------------------------------------------------------------------------
func _test_mana_longevity() -> void:
	print("-- Estimador de longevidad de maná --")
	check(is_equal_approx(RaidHUD.calculate_mana_longevity(5200.0, 52.0), 100.0), "5200 / 52 = 100 s")
	check(is_equal_approx(RaidHUD.calculate_mana_longevity(1000.0, 8.0), 125.0), "1000 / 8 = 125 s")
	check(is_equal_approx(RaidHUD.calculate_mana_longevity(333.0, 3.0), 111.0), "333 / 3 = 111 s")
	check(is_equal_approx(RaidHUD.calculate_mana_longevity(7.5, 2.5), 3.0), "7,5 / 2,5 = 3 s")
	check(is_inf(RaidHUD.calculate_mana_longevity(1000.0, 0.0)), "Sin gasto -> INF")
	check(is_inf(RaidHUD.calculate_mana_longevity(1000.0, -5.0)), "Gasto negativo (regenera) -> INF")
	check(RaidHUD.calculate_mana_longevity(0.0, 10.0) == 0.0, "Sin maná -> 0 s")
	check(RaidHUD.format_longevity(100.0) == "1:40", "Formato 100 s = '1:40'")
	check(RaidHUD.format_longevity(59.9) == "0:59", "Formato 59,9 s = '0:59'")
	check(RaidHUD.format_longevity(3725.0) == "1:02:05", "Formato 3725 s = '1:02:05'")
	check(RaidHUD.format_longevity(INF) == "∞", "Formato INF = '∞'")
