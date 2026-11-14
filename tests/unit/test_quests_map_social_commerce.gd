extends SceneTree
## Suite headless (UI v2.4 Paso 9): Misiones [L], Mapa y viajes [M], Social y vecindad [O]
## y Comercio [P] (Tienda y Pase de batalla EN CONSTRUCCIÓN).
## Run: Godot --headless --path clients/godot-mmo-client -s tests/unit/test_quests_map_social_commerce.gd
## Exit code 0 = todo PASS.

const QS = preload("res://shared-core/QuestService.gd")
const WMS = preload("res://shared-core/WorldMapService.gd")
const SOC = preload("res://shared-core/SocialService.gd")
const COM = preload("res://shared-core/CommerceService.gd")
const KS = preload("res://shared-core/KnowledgeService.gd")
const SS = preload("res://shared-core/ShelterService.gd")
const T = preload("res://ui/tokens/hud_tokens.gd")
const QuestsScene = preload("res://ui/windows/QuestsWindow/QuestsWindow.tscn")
const MapScene = preload("res://ui/windows/MapWindow/MapWindow.tscn")
const SocialScene = preload("res://ui/windows/SocialWindow/SocialWindow.tscn")
const ShopScene = preload("res://ui/windows/ShopWindow/ShopWindow.tscn")
const PassScene = preload("res://ui/windows/BattlePassWindow/BattlePassWindow.tscn")

const MIN_CHECKS := 250
const NEW_WINDOWS := ["quests_window", "map_window", "social_window", "shop_window", "battle_pass_window"]

var _fails: Array[String] = []
var _checks := 0


class FakeOrchestrator extends Node:
	var registry: Node
	var toggled: Array[String] = []

	func toggle_window(id: String, _params: Dictionary = {}) -> void:
		toggled.append(id)


class FakeHud extends RefCounted:
	var quests: Array = []
	var calls := 0

	func set_quests(list: Array) -> void:
		quests = list.duplicate()
		calls += 1


func check(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_fails.append(msg)
		printerr("  FAIL: ", msg)
	else:
		print("  PASS: ", msg)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("== [TEST] Paso 9: Misiones [L] · Mapa [M] · Social [O] · Comercio [P] ==")
	await _test_registry_and_menu()
	await _test_quests_model()
	await _test_pioneer_quests()
	await _test_quests_window()
	_test_map_model()
	_test_travel()
	await _test_map_window()
	await _test_social_model()
	await _test_social_window()
	_test_commerce_model()
	await _test_shop_window()
	await _test_battle_pass_window()
	await _test_orchestrator_navigation()
	check(_checks >= MIN_CHECKS, "Se ejecutaron todas las comprobaciones (%d >= %d)" % [_checks, MIN_CHECKS])
	print("== %d checks, %d fallos ==" % [_checks, _fails.size()])
	if _fails.is_empty():
		print("RESULTADO: 100% PASS")
		quit(0)
	else:
		for f in _fails:
			printerr("  - ", f)
		quit(1)


# --------------------------------------------------------------------------
# Utilidades
# --------------------------------------------------------------------------
func _key(code: int) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	return ev


func _frames(n: int = 2) -> void:
	for i in n:
		await process_frame


func _all_texts(n: Node) -> String:
	if n == null:
		return ""
	var out := ""
	if n is Label or n is Button or n is LineEdit:
		out += str(n.text) + "\n"
	for c in n.get_children():
		out += _all_texts(c)
	return out


func _find_label(n: Node, text: String) -> Label:
	if n is Label and (n as Label).text == text:
		return n
	for c in n.get_children():
		var r := _find_label(c, text)
		if r:
			return r
	return null


func _new_ks() -> Node:
	var ks: Node = KS.new()
	ks.wiki_sync_enabled = false
	ks.load_seed()
	return ks


func _new_quests(ks: Node = null) -> Node:
	var q: Node = QS.new()
	q.load_seed()
	if ks:
		q.connect_knowledge(ks)
	return q


func _new_map(ks: Node = null) -> Node:
	var m: Node = WMS.new()
	m.load_seed()
	if ks:
		m.connect_knowledge(ks)
	return m


func _new_commerce() -> Node:
	var c: Node = COM.new()
	c.load_seed()
	return c


func _new_social(shelter: Node = null) -> Node:
	var s: Node = SOC.new()
	s.load_seed()
	s.shelter = shelter
	return s


## Libera un nodo suelto si sigue vivo (las ventanas adoptan los servicios inyectados).
func _free(n) -> void:
	if is_instance_valid(n) and (not (n is Node) or (n as Node).get_parent() == null):
		n.free()


func _ids(arr: Array) -> Array:
	return arr.map(func(d) -> String: return str(d["id"]))


# --------------------------------------------------------------------------
# 1. Registro, atajos y menú común
# --------------------------------------------------------------------------
func _test_registry_and_menu() -> void:
	print("-- 1. UIWindowRegistry [L][M][O] + Tienda/Pase, menú común y UIInputRouter")
	var Registry = load("res://ui/orchestration/UIWindowRegistry.gd")
	var UITypes = load("res://ui/types/UITypes.gd")
	var reg: Node = Registry.new()
	var expected := {
		"quests_window": ["res://ui/windows/QuestsWindow/QuestsWindow.tscn", [KEY_L]],
		"map_window": ["res://ui/windows/MapWindow/MapWindow.tscn", [KEY_M]],
		"social_window": ["res://ui/windows/SocialWindow/SocialWindow.tscn", [KEY_O]],
		"shop_window": ["res://ui/windows/ShopWindow/ShopWindow.tscn", []],
		"battle_pass_window": ["res://ui/windows/BattlePassWindow/BattlePassWindow.tscn", []],
	}
	for id in expected:
		check(reg.is_registered(id), "Registrada: %s" % id)
		var meta = reg.get_metadata(id)
		check(meta != null and meta.scene_path == expected[id][0], "%s -> %s" % [id, expected[id][0]])
		check(meta != null and ResourceLoader.exists(meta.scene_path), "La escena de %s existe" % id)
		check(meta != null and meta.category == UITypes.WindowCategory.GAME_WINDOW, "%s es GAME_WINDOW" % id)
		check(reg.get_shortcut_keys(id) == expected[id][1], "%s atajos %s" % [id, str(expected[id][1])])
	check(reg.get_window_for_key(KEY_L) == "quests_window", "KEY_L -> quests_window")
	check(reg.get_window_for_key(KEY_M) == "map_window", "KEY_M -> map_window")
	check(reg.get_window_for_key(KEY_O) == "social_window", "KEY_O -> social_window")
	check(reg.get_window_for_key(KEY_N) == "powers" and reg.get_window_for_key(KEY_H) == "shelter", "N y H siguen en Poderes y Refugio")
	check(reg.get_window_for_key(KEY_P) == "", "P no se registra (conflicto con Visión Ki; Comercio lo abre el menú)")

	var bar = load("res://ui/menu/menu_bar.tscn").instantiate()
	root.add_child(bar)
	var nav: Array = []
	bar.navigation_requested.connect(func(w: String, _p: Dictionary) -> void: nav.append(w))
	check(bar.get_tab_ids().size() == 8, "Menú común con 8 pestañas")
	for t in bar.tabs_data:
		var w := str(t["window"])
		check(reg.is_registered(w), "Pestaña %s -> ventana registrada «%s»" % [t["label"], w])
	for s in bar.get_subtabs("comercio"):
		check(reg.is_registered(str(s["window"])), "Comercio › %s -> «%s» registrada" % [s["label"], s["window"]])
	for pair in [[KEY_L, "quests_window"], [KEY_M, "map_window"], [KEY_O, "social_window"]]:
		nav.clear()
		check(bar.handle_shortcut(_key(pair[0])) and nav.has(pair[1]), "Menú: [%s] navega a %s" % [OS.get_keycode_string(pair[0]), pair[1]])
	nav.clear()
	bar.select_subtab("comercio", "tienda")
	check(nav == ["shop_window"], "Comercio › Tienda -> shop_window")
	nav.clear()
	bar.select_subtab("comercio", "pase")
	check(nav == ["battle_pass_window"], "Comercio › Pase -> battle_pass_window")
	nav.clear()
	bar.request_shop("prisms_plus")
	check(nav.has("shop_window"), "Prismas «+» abre la Tienda")
	bar.queue_free()

	var router: Node = load("res://ui/orchestration/UIInputRouter.gd").new()
	var orch := FakeOrchestrator.new()
	orch.registry = reg
	for pair in [[KEY_L, "quests_window"], [KEY_M, "map_window"], [KEY_O, "social_window"]]:
		orch.toggled.clear()
		check(router.handle_window_shortcut(_key(pair[0]), orch) and orch.toggled == [pair[1]], "UIInputRouter: [%s] abre/cierra %s" % [OS.get_keycode_string(pair[0]), pair[1]])
	var ctrl_l := _key(KEY_L)
	ctrl_l.ctrl_pressed = true
	check(not router.handle_window_shortcut(ctrl_l, orch), "Ctrl+L no abre Misiones")
	for a in ["QuestService", "WorldMapService", "SocialService", "CommerceService"]:
		check(str(ProjectSettings.get_setting("autoload/" + a, "")).begins_with("*res://shared-core/"), "Autoload %s registrado" % a)
	_free(router)
	_free(orch)
	_free(reg)
	await process_frame


# --------------------------------------------------------------------------
# 2. Misiones: modelo, filtros, rastreo en HUD
# --------------------------------------------------------------------------
func _test_quests_model() -> void:
	print("-- 2. Misiones: categorías, filtros, progreso y rastreo en el HUD")
	var q: Node = _new_quests()
	var cats := _ids(q.categories)
	check(cats == ["principal", "secundaria", "diaria", "pionero"], "Categorías: Principales, Secundarias, Diarias y Pionero")
	var counts: Dictionary = q.count_by_state()
	check(counts["active"] == 6 and counts["available"] == 2 and counts["completed"] == 3, "Estados: 6 activas, 2 disponibles, 3 hechas (%s)" % str(counts))
	var main_active: Array = q.list_quests("principal", "active")
	check(_ids(main_active) == ["q_sellar_grieta", "q_mensaje_ferrum"], "Filtro Principales + Activas")
	check(q.list_quests("", "completed").size() == 3, "Filtro Completadas")
	check(q.list_quests("diaria", "").size() == 3, "Filtro Diarias (todos los estados)")
	var all_active: Array = q.list_quests("", "active")
	var order := all_active.map(func(d) -> String: return str(d["category"]))
	check(order.find("secundaria") > order.rfind("principal") and order.find("diaria") > order.rfind("secundaria"), "Lista agrupada por categoría")
	var c: Dictionary = q.get_quest("q_cristales_vacio")
	check(c["steps"][0]["label"] == "Cristales de Vacío" and QS.step_text(c["steps"][0]) == "3/5", "Paso con progreso: 3/5 Cristales de Vacío")
	check(c["done_steps"] == 0 and c["total_steps"] == 2 and is_equal_approx(float(c["ratio"]), 0.3), "Progreso agregado (0/2 pasos, 30 %)")
	check(int(c["rewards"]["gold"]) == 120 and int(c["rewards"]["xp"]) == 6800 and (c["rewards"]["items"] as Array).size() == 1, "Recompensas: oro, PX y objetos")
	check(q.get_tracked() == ["q_sellar_grieta", "q_cristales_vacio"], "Rastreo inicial del seed (2)")

	var hud := FakeHud.new()
	q.bind_hud(hud)
	check(hud.quests.size() == 2, "bind_hud empuja las misiones rastreadas")
	check(str(hud.quests[1]).contains("3/5 Cristales de Vacío"), "Línea del HUD con progreso: %s" % str(hud.quests[1]))
	check(q.track("q_hierbas_brecha")["ok"] and hud.quests.size() == 3, "Seguir una 3.ª misión actualiza el HUD")
	var r: Dictionary = q.track("q_mensaje_ferrum")
	check(not r["ok"] and r["reason"] == "max_tracked" and hud.quests.size() == 3, "Máximo 3 misiones en el HUD")
	check(q.track("q_lobos_ceniza")["reason"] == "not_active", "No se puede seguir una misión no activa")
	check(q.untrack("q_hierbas_brecha") and hud.quests.size() == 2, "Dejar de seguir la quita del HUD")
	var tg: Dictionary = q.toggle_track("q_hierbas_brecha")
	check(tg["ok"] and tg["tracked"] and q.is_tracked("q_hierbas_brecha"), "toggle_track activa")
	check(q.toggle_track("q_hierbas_brecha")["tracked"] == false, "toggle_track desactiva")

	# HUD real (HUDv2): rastreador de misiones.
	var hud_scene: PackedScene = load("res://ui/components/HUDv2/hud.tscn")
	var real_hud = hud_scene.instantiate()
	root.add_child(real_hud)
	await process_frame
	q.bind_hud(real_hud)
	check(real_hud.quests.size() == 2 and real_hud.quest_tracker.get_child_count() == 2, "HUDv2: el rastreador muestra 2 misiones")
	q.track("q_hierbas_brecha")
	check(real_hud.quest_tracker.get_child_count() == 3, "HUDv2: 3 misiones tras seguir otra")
	check(str(real_hud.quest_tracker.get_child(0).text).begins_with("◆ Sellar la grieta menor"), "HUDv2: texto «◆ Sellar la grieta menor…»")

	var completed := [""]
	q.quest_completed.connect(func(id: String, _rw: Dictionary) -> void: completed[0] = id)
	q.advance_step("q_cristales_vacio")
	check(q.get_quest("q_cristales_vacio")["steps"][0]["progress"] == 4, "advance_step: 4/5")
	q.advance_step("q_cristales_vacio", 0, 5)
	check(QS.step_text(q.get_quest("q_cristales_vacio")["steps"][0]) == "5/5", "El progreso no pasa del objetivo (5/5)")
	var fin: Dictionary = q.advance_step("q_cristales_vacio")
	check(fin["completed"] and q.get_quest("q_cristales_vacio")["state"] == "completed", "Al completar todos los pasos pasa a Hechas")
	check(completed[0] == "q_cristales_vacio" and q.gold_earned == 120 and q.xp_earned == 6800, "Señal quest_completed y recompensas (120 oro, 6.800 PX)")
	check(not q.is_tracked("q_cristales_vacio") and real_hud.quest_tracker.get_child_count() == 2, "Una misión hecha sale del rastreador del HUD")
	check(q.advance_step("q_cristales_vacio")["reason"] == "not_active", "No se avanza una misión hecha")
	check(q.abandon("q_vado_sin_puente")["ok"] and q.get_quest("q_vado_sin_puente")["state"] == "available" and q.get_quest("q_vado_sin_puente")["steps"][0]["progress"] == 0, "Abandonar: vuelve a Disponibles sin progreso")
	check(q.accept("q_lobos_ceniza")["ok"] and q.get_quest("q_lobos_ceniza")["state"] == "active", "Aceptar una disponible")
	var tgt: Dictionary = q.get_map_target("q_sellar_grieta")
	check(tgt["focus"] == Vector2(1180, 470) and tgt["poi"] == "boss_valgorath", "Objetivo en el mapa: Val'Gorath (1180, 470)")
	var plan: Dictionary = q.plan_session()
	check(plan["steps"].size() == q.get_tracked().size() and int(plan["minutes"]) > 0 and int(plan["xp_per_hour"]) > 0, "Planificador de sesión (tiempo, PX/hora)")
	var saved: Dictionary = q.to_dict()
	var q2: Node = QS.new()
	q2.load_from_dict(saved)
	check(q2.get_tracked() == q.get_tracked() and q2.get_quest("q_cristales_vacio")["state"] == "completed", "to_dict/load_from_dict conserva estado y rastreo")
	real_hud.queue_free()
	_free(q)
	_free(q2)
	await process_frame


func _test_pioneer_quests() -> void:
	print("-- 3. Misiones de Pionero (integradas con KnowledgeService)")
	var ks: Node = _new_ks()
	var q: Node = _new_quests(ks)
	var pio_active: Array = q.list_quests("pionero", "active")
	check(_ids(pio_active).has("pio_inv_taller_runico"), "Contrato en misión -> misión de pionero activa")
	var tr: Dictionary = q.get_quest("pio_inv_taller_runico")
	check(tr["done_steps"] == 2 and tr["total_steps"] == 3, "Progreso del contrato 2/3 desde el Códice")
	var pio_avail: Array = q.list_quests("pionero", "available")
	check(_ids(pio_avail).has("pio_offer_taberna_nexo"), "Oferta guardada -> misión de pionero disponible")
	check(str(q.get_quest("pio_offer_taberna_nexo")["story"]).contains("días para decidir"), "La oferta muestra el plazo para decidir")
	check(q.accept("pio_offer_taberna_nexo")["reason"] == "unknown_or_external", "Las ofertas se deciden en el Códice, no aquí")
	var changed := [0]
	q.quests_changed.connect(func() -> void: changed[0] += 1)
	var offer := {"id": "offer_gildas", "npc_id": "pnj_gildas", "shop_name": "Puesto de Gildas", "zone": "Overworld", "share": 0.02,
		"mission": {"name": "Socio de Gildas", "steps": [{"label": "Lleva 5 Cristales de Vacío a Gildas", "goal": 1}, {"label": "Escolta su carro al Vado", "goal": 1}]}}
	var acc: Dictionary = ks.accept_pioneer_offer(offer)
	check(acc["ok"] and changed[0] > 0, "Aceptar la oferta en KnowledgeService refresca el diario")
	var pg: Dictionary = q.get_quest("pio_inv_gildas")
	check(not pg.is_empty() and pg["state"] == "active" and pg["title"] == "Socio de Gildas", "Nueva misión de pionero «Socio de Gildas»")
	check(pg["steps"][0]["label"] == "Lleva 5 Cristales de Vacío a Gildas", "Pasos con el texto de la misión de la oferta")
	check(q.track("pio_inv_gildas")["ok"], "Una misión de pionero se puede seguir en el HUD")
	q.advance_step("pio_inv_gildas")
	check(int(ks.get_investment("inv_gildas")["mission_step"]) == 1 and q.get_quest("pio_inv_gildas")["done_steps"] == 1, "Avanzar en el diario avanza el contrato (1/2)")
	q.advance_step("pio_inv_gildas")
	check(ks.get_investment("inv_gildas")["status"] == "active" and q.get_quest("pio_inv_gildas")["state"] == "completed", "Misión completada: el contrato empieza a cobrar")
	check(not q.is_tracked("pio_inv_gildas"), "Contrato completado sale del rastreador")
	check(_ids(q.list_quests("pionero", "completed")).has("pio_inv_gildas"), "Aparece en Hechas › Pionero")
	_free(q)
	_free(ks)
	await process_frame


func _test_quests_window() -> void:
	print("-- 4. QuestsWindow [L]")
	var ks: Node = _new_ks()
	var q: Node = _new_quests(ks)
	var w = QuestsScene.instantiate()
	w.service = q
	w.commerce = _new_commerce()
	root.add_child(w)
	await _frames()
	check(w.window_id == "quests_window", "window_id = quests_window")
	check(w.menu_bar.active_tab == "misiones", "Menú común: pestaña Misiones activa")
	check(w.menu_bar.gold_label.amount_label.text == "12.480" and w.menu_bar.prisms_label.amount_label.text == "340", "Menú: Oro 12.480 · Prismas 340")
	check(w.state_buttons["active"].text == "Activas 7" and w.state_buttons["active"].button_pressed, "Chip «Activas 7» (6 + 1 pionero) seleccionado")
	check(w.list_rows.size() == 7, "Lista: 7 activas")
	check(w.find_child("Group_pionero", true, false) != null, "Grupo «Misiones de Pionero» en la lista")
	w.set_category_filter("diaria")
	check(w.list_rows.keys() == ["q_patrulla_nexo"], "Filtro Diarias")
	w.set_category_filter("")
	w.set_state_filter("completed")
	check(w.list_rows.size() == 3 and w.track_button.visible, "Filtro Hechas: 3")
	check(w.track_button.disabled, "No se puede seguir una misión hecha")
	w.set_state_filter("active")
	w.select_quest("q_cristales_vacio")
	await process_frame
	check(w.title_label_big.text == "Cristales de Vacío", "Detalle: título")
	check(w.step_rows[0]["count"].text == "3/5" and w.step_rows[0]["label"].text == "Cristales de Vacío", "Detalle: paso 3/5 Cristales de Vacío")
	var gold_l: Label = _find_label(w.find_child("RewardLine", true, false), "120")
	check(gold_l != null and gold_l.get_theme_color("font_color") == T.GOLD, "Recompensa en oro con color #f5c35b")
	var xp_l: Label = _find_label(w.find_child("RewardLine", true, false), "6.800")
	check(xp_l != null, "Recompensa en PX (6.800)")
	check(_all_texts(w.find_child("RewardLine", true, false)).contains("Polvo de vacío ×2"), "Recompensa de objetos")
	check(w.track_button.text == "Dejar de seguir", "Rastreada: botón «Dejar de seguir»")
	check(w.hud_count_label.text == "2/3", "Panel HUD: 2/3")
	w.select_quest("q_hierbas_brecha")
	var r: Dictionary = w.toggle_track_selected()
	check(r["ok"] and q.is_tracked("q_hierbas_brecha"), "«Seguir en HUD» rastrea la misión")
	await process_frame
	check(w.hud_count_label.text == "3/3" and w.hud_box.get_child_count() == 3, "Panel HUD: 3/3 con 3 tarjetas")
	check(w.list_rows["q_hierbas_brecha"].find_child("TrackMark", true, false).get_child_count() == 1, "Marca ✓ en la fila rastreada")
	w.select_quest("q_mensaje_ferrum")
	r = w.toggle_track_selected()
	check(not r["ok"] and w.feedback_label.text.contains("deja de seguir"), "4.ª misión: aviso de máximo 3")
	w._unhandled_key_input(_key(KEY_T))
	check(not q.is_tracked("q_mensaje_ferrum"), "Atajo T respeta el máximo")
	w.select_quest("q_hierbas_brecha")
	w._unhandled_key_input(_key(KEY_T))
	check(not q.is_tracked("q_hierbas_brecha"), "Atajo T deja de seguir")
	w.set_category_filter("pionero")
	check(w.list_rows.has("pio_inv_taller_runico") and w.selected_id == "pio_inv_taller_runico", "Filtro Pionero: contrato del Taller rúnico")
	await process_frame
	check(_all_texts(w.detail_box).contains("de cada venta"), "Pionero: recompensa = % de cada venta")
	check(not w.abandon_button.visible, "Pionero: no se abandona desde aquí")
	w.set_category_filter("")
	w.select_quest("q_sellar_grieta")
	var got := [{}]
	w.map_requested.connect(func(p: Dictionary) -> void: got[0] = p)
	var params: Dictionary = w.view_on_map()
	check(params["focus"] == Vector2(1180, 470) and got[0].get("quest_id", "") == "q_sellar_grieta", "«Ver en el mapa» emite las coordenadas del objetivo")
	var orch: Node = root.get_node_or_null("UIOrchestrator")
	var mw = orch.get_window_instance("map_window") if orch else null
	check(mw != null and mw.visible, "«Ver en el mapa» abre map_window por UIOrchestrator")
	if mw:
		await process_frame
		check(mw.canvas.focus_target == Vector2(1180, 470) and mw.canvas.center == Vector2(1180, 470), "El mapa se centra en el objetivo")
		check(mw.current_page == "mapa" and mw.canvas.focus_label == "Sellar la grieta menor", "Mapa en la página Mapa con la etiqueta de la misión")
		orch.close_window("map_window", true)
	w.set_state_filter("available")
	w.select_quest("q_lobos_ceniza")
	w._on_abandon_or_accept()
	check(q.get_quest("q_lobos_ceniza")["state"] == "active" and w.state_filter == "active", "«Aceptar» activa la misión")
	w.queue_free()
	await _frames()
	_free(q)
	_free(ks)


# --------------------------------------------------------------------------
# 5. Mapa: niebla, marcadores, secretos
# --------------------------------------------------------------------------
func _test_map_model() -> void:
	print("-- 5. Mapa del mundo: niebla de guerra, PNJ, jefes, El Nido y secretos")
	var m: Node = _new_map()
	check(m.regions.size() == 7 and m.map_size == Vector2(2000, 1300), "7 regiones en un mapa de 2000×1300")
	var views: Array = m.get_regions_view()
	var fog := views.filter(func(r) -> bool: return not r["explored"])
	check(fog.size() == 4 and fog.all(func(r) -> bool: return r["display_name"] == "???"), "Niebla: 4 zonas desconocidas marcadas «???»")
	check(views.filter(func(r) -> bool: return r["explored"]).all(func(r) -> bool: return r["display_name"] != "???"), "Zonas exploradas con su nombre")
	var ids := _ids(m.get_markers())
	check(ids.has("npc_gildas") and m.find_marker("npc_gildas")["kind"] == "npc" and m.find_marker("npc_gildas")["region"] == "verdalia", "PNJ Gildas en el Overworld (Verdalia)")
	check(ids.has("npc_torin") and m.find_marker("npc_torin")["region"] == "forja", "PNJ Torin en la Forja")
	check(m.find_marker("boss_valgorath")["kind"] == "boss" and m.find_marker("boss_valgorath")["name"] == "Val'Gorath", "Jefe Val'Gorath")
	check(m.find_marker("nido_entrance")["kind"] == "shelter", "Entrada a El Nido (Refugio)")
	check(not ids.has("cripta_runica") and not ids.has("coloso_runavell"), "La niebla oculta los PDI de zonas sin explorar")
	check(m.get_secret_markers().is_empty(), "Sin Códice no hay secretos en el mapa")
	check(m.resolve_poi("cripta_runica") == null, "resolve_poi no revela PDI bajo la niebla")
	var exp_sig := [""]
	m.region_explored.connect(func(id: String) -> void: exp_sig[0] = id)
	check(m.explore_region("runavell") and exp_sig[0] == "runavell", "Explorar Runavell")
	check(_ids(m.get_markers()).has("cripta_runica") and m.get_regions_view().filter(func(r) -> bool: return r["id"] == "runavell")[0]["display_name"] == "Criptas de Runavell", "Al explorar se revelan nombre y PDI")
	check(not m.explore_region("runavell"), "Explorar dos veces no hace nada")
	check(is_equal_approx(m.explored_ratio(), 4.0 / 7.0), "Proporción explorada 4/7")
	var no_npc := _ids(m.get_markers({"npc": false}))
	check(not no_npc.has("npc_gildas") and no_npc.has("boss_valgorath"), "Capas: ocultar PNJ")
	check(m.resolve_poi("npc_torin") == Vector2(1530, 330), "resolve_poi(Torin)")

	var ks: Node = _new_ks()
	var m2: Node = _new_map(ks)
	var secrets: Array = m2.get_secret_markers()
	var sids := _ids(secrets)
	check(sids.has("item_amuleto_vacio") and sids.has("lugar_cueva_ambar"), "Secretos personales del Códice en el mapa")
	var amu: Dictionary = secrets.filter(func(s) -> bool: return s["id"] == "item_amuleto_vacio")[0]
	check(amu["pos"] == m2.world_to_map([412.5, 12.0, -88.25]) and amu["region"] == "runavell", "Coordenadas 3D -> mapa (x, z)")
	check(_ids(m2.get_markers()).has("item_amuleto_vacio"), "Tus secretos se ven aunque la zona tenga niebla")
	check(not sids.has("item_cofre_ferrum") and not sids.has("item_daga_eco"), "Ni lo «visto de lejos» ni lo publicado salen como secreto")
	for s in secrets:
		check(int(ks.get_visibility(str(s["id"]))) == KS.KNOWN_SECRET, "Secreto %s es KNOWN_SECRET" % s["id"])
	var changed := [0]
	m2.map_changed.connect(func() -> void: changed[0] += 1)
	ks.discover_entry("lugar_grieta_oculta", "lugares", {"name": "Grieta oculta", "location": {"zone": "Verdalia", "coords": [-50.0, 3.0, -250.0]}})
	check(changed[0] > 0 and _ids(m2.get_markers()).has("lugar_grieta_oculta"), "Un descubrimiento nuevo aparece en el mapa al instante")
	check(m2.resolve_poi("pnj_taberna_nexo") == m2.world_to_map([0.0, 0.0, 12.0]), "resolve_poi usa la ubicación del Códice")
	check(not _ids(m2.get_markers({"secret": false})).has("lugar_cueva_ambar"), "Capa de secretos desactivable")
	_free(m)
	_free(m2)
	_free(ks)


func _test_travel() -> void:
	print("-- 6. Viajes deterministas: caravana, montura, atajo, dirigible (sin teletransporte)")
	var m: Node = _new_map()
	check(not m.has_method("teleport") and not m.has_method("teleport_to"), "No existe teletransporte")
	var car: Dictionary = m.compute_route("boveda_ferrum", "caravana")
	check(car["time_min"] == 12 and car["cost"] == 40 and car["risk_label"] == "Segura", "Caravana: 12 min · 40 oro · Segura")
	check(car["departure_min"] == 6, "Caravana: sale en 6 min")
	var mon: Dictionary = m.compute_route("boveda_ferrum", "montura")
	check(mon["time_min"] == 18 and mon["cost"] == 0 and mon["risk_label"] == "Riesgo medio", "Montura: 18 min · gratis · Riesgo medio (cruza la brecha)")
	var dir: Dictionary = m.compute_route("boveda_ferrum", "dirigible")
	check(dir["time_min"] == 7 and dir["cost"] == 120 and dir["risk_label"] == "Segura", "Dirigible: 7 min · 120 oro · Segura")
	var atj: Dictionary = m.compute_route("boveda_ferrum", "atajo")
	check(atj["time_min"] == 26 and atj["risk_label"] == "Riesgo alto", "Atajo a pie: 26 min · Riesgo alto")
	check(not atj["available"] and atj["reason"] == "secret_unknown", "Atajo bloqueado si no conoces el secreto")
	check(m.compute_route("boveda_ferrum", "caravana") == car, "Cálculo determinista (misma entrada, mismo resultado)")
	var opts: Array = m.get_travel_options("boveda_ferrum")
	check(opts.map(func(o) -> String: return o["mode"]) == ["caravana", "montura", "atajo", "dirigible"], "4 formas de llegar a la Bóveda")
	check(opts.all(func(o) -> bool: return int(o["time_min"]) >= 1), "Todo viaje dura al menos 1 min")
	check(car["segments"].size() >= 2 and car["segments"][0]["kind"] == "wait", "Barra de ruta: espera + tramo seguro")
	var ratio_sum := 0.0
	for s in mon["segments"]:
		ratio_sum += float(s["ratio"])
	check(is_equal_approx(ratio_sum, 1.0) and mon["segments"].any(func(s) -> bool: return s["kind"] == "medium"), "Montura: tramo de riesgo medio en la brecha (suma 100 %)")
	var nexo: Array = m.get_travel_options("nexo")
	check(nexo.map(func(o) -> String: return o["mode"]) == ["caravana", "montura", "dirigible"], "Nexo: sin atajo (no hay)")
	check(m.compute_route("nexo", "caravana")["cost"] == 20 + int(round(6.25 * 5.6)), "Coste = base + por km (Nexo 5,6 km)")
	var nest: Array = m.get_travel_options("el_nido")
	check(nest.size() == 1 and nest[0]["mode"] == "puerta_nido", "El Nido: solo por la puerta de tu depa")
	check(not nest[0]["available"] and nest[0]["reason"] == "origin_not_safe", "La puerta de El Nido solo funciona desde zona segura")
	check(not _ids(m.list_destinations()).has("atajo_cueva"), "El atajo secreto no aparece si no lo conoces")
	check(m.book_travel("boveda_ferrum", "")["reason"] == "no_teleport", "Sin modo de viaje no hay viaje (no_teleport)")
	check(m.book_travel("boveda_ferrum", "dirigible", 50)["reason"] == "not_enough_gold", "Sin oro suficiente no se reserva")
	check(m.book_travel("boveda_ferrum", "atajo")["reason"] == "secret_unknown", "Atajo desconocido no se reserva")
	var booked := [{}]
	m.travel_booked.connect(func(t: Dictionary) -> void: booked[0] = t)
	var b: Dictionary = m.book_travel("boveda_ferrum", "caravana", 1000)
	check(b["ok"] and b["cost"] == 40 and booked[0]["mode"] == "caravana", "Reserva de caravana")
	check(m.book_travel("nexo", "montura")["reason"] == "already_travelling", "Un viaje cada vez")
	check(not m.tick_travel(10.0) and is_equal_approx(m.trip_progress(), 10.0 / 18.0), "Progreso del viaje (incluye la espera)")
	var arrived := [""]
	m.travel_arrived.connect(func(d: String) -> void: arrived[0] = d)
	check(m.tick_travel(8.0) and arrived[0] == "boveda_ferrum" and m.current_location == "boveda_ferrum", "Llegada al destino tras el tiempo calculado")
	m.set_current_location("puesto_vado")
	check(m.is_origin_safe() and m.get_travel_options("el_nido")[0]["available"], "Desde el Puesto del Vado (zona segura) se puede ir a El Nido")
	m.book_travel("nexo", "caravana")
	var dc: Dictionary = m.on_disconnect()
	check(dc["ok"] and dc["safe"] and m.current_location == "nexo", "Desconexión en caravana: llega a la posta y queda a salvo")
	m.book_travel("puesto_vado", "montura")
	var dc2: Dictionary = m.on_disconnect()
	check(dc2["ok"] and not dc2["safe"] and m.current_location == "nexo" and m.active_trip.is_empty(), "Desconexión en montura: se queda donde estaba")

	var ks: Node = _new_ks()
	var m2: Node = _new_map(ks)
	check(_ids(m2.list_destinations()).has("atajo_cueva"), "Con el secreto, «Atajo de la cueva» aparece en destinos")
	check(m2.compute_route("boveda_ferrum", "atajo")["available"], "Con el secreto, el atajo está disponible")
	_free(m)
	_free(m2)
	_free(ks)


func _test_map_window() -> void:
	print("-- 7. MapWindow [M]: lienzo con zoom/paneo, capas y Viajar")
	var ks: Node = _new_ks()
	var svc: Node = _new_map(ks)
	var w = MapScene.instantiate()
	w.service = svc
	w.commerce = _new_commerce()
	root.add_child(w)
	await _frames(3)
	var cv = w.canvas
	check(w.window_id == "map_window" and w.menu_bar.active_tab == "mapa", "map_window con la pestaña Mapa activa")
	check(cv.size.x > 100 and cv.size.y > 100, "Lienzo con tamaño (%s)" % str(cv.size))
	check(w.region_box.get_child_count() == 7, "Lista de 7 regiones")
	var names := _all_texts(w.region_box)
	check(names.count("???") == 4 and names.contains("Forja de Ferrum"), "Regiones: 4 «???» y nombres explorados")
	cv.center_on(Vector2(1000, 600), 1.0)
	var anchor := Vector2(120, 90)
	var before: Vector2 = cv.screen_to_world(anchor)
	cv.zoom_at(2.0, anchor)
	check(is_equal_approx(cv.zoom, 2.0) and cv.screen_to_world(anchor).distance_to(before) < 0.01, "Zoom centrado en el cursor")
	cv.zoom_at(100.0, anchor)
	check(is_equal_approx(cv.zoom, cv.MAX_ZOOM), "Zoom máximo limitado")
	cv.set_zoom(1.0)
	var c0: Vector2 = cv.center
	cv.pan_by(Vector2(50, -20))
	check(cv.center.is_equal_approx(c0 - Vector2(50, -20)), "Paneo mueve la vista")
	cv.pan_by(Vector2(-100000, -100000))
	check(cv.center.x <= svc.map_size.x and cv.center.y <= svc.map_size.y, "Paneo limitado al mapa")
	cv.set_zoom(1.0)
	cv.zoom_in_button.pressed.emit()
	check(cv.zoom > 1.0, "Botón «+» acerca")
	cv.zoom_out_button.pressed.emit()
	cv.zoom_out_button.pressed.emit()
	check(cv.zoom < 1.0, "Botón «−» aleja")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.position = cv.size * 0.5
	var zb: float = cv.zoom
	cv._gui_input(wheel)
	check(cv.zoom > zb, "Rueda del ratón acerca")
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(200, 200)
	cv._gui_input(press)
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(260, 230)
	motion.relative = Vector2(60, 30)
	var cb: Vector2 = cv.center
	cv._gui_input(motion)
	var rel := InputEventMouseButton.new()
	rel.button_index = MOUSE_BUTTON_LEFT
	rel.pressed = false
	rel.position = Vector2(260, 230)
	cv._gui_input(rel)
	check(not cv.center.is_equal_approx(cb), "Arrastrar desplaza el mapa")

	cv.center_on(Vector2(1180, 470), 1.0)
	var boss_screen: Vector2 = cv.world_to_screen(Vector2(1180, 470))
	check(cv.marker_at(boss_screen) == "boss_valgorath", "Clic sobre el jefe lo detecta")
	var clicked := [""]
	cv.marker_clicked.connect(func(id: String) -> void: clicked[0] = id)
	var p2 := InputEventMouseButton.new()
	p2.button_index = MOUSE_BUTTON_LEFT
	p2.pressed = true
	p2.position = boss_screen
	cv._gui_input(p2)
	var r2 := p2.duplicate()
	r2.pressed = false
	cv._gui_input(r2)
	await process_frame
	check(clicked[0] == "boss_valgorath" and w.find_child("MarkerName", true, false).text == "Val'Gorath", "Clic en marcador -> ficha «Val'Gorath»")
	check(not w.travel_here_button.visible, "Un jefe no es destino de viaje")
	var marker_ids := _ids(cv.visible_markers())
	check(marker_ids.has("npc_gildas") and marker_ids.has("npc_torin") and marker_ids.has("nido_entrance") and marker_ids.has("item_amuleto_vacio"), "Lienzo: PNJ, El Nido y secretos")
	check(not marker_ids.has("cripta_runica"), "Lienzo: niebla sobre Runavell")
	w.set_layer("npc", false)
	check(not _ids(cv.visible_markers()).has("npc_gildas") and not w.layer_checks["npc"].button_pressed, "Capa PNJ apagada")
	w.set_layer("npc", true)
	w.set_layer("secret", false)
	check(not _ids(cv.visible_markers()).has("item_amuleto_vacio"), "Capa Secretos apagada")
	w.set_layer("secret", true)
	w.select_marker("boveda_ferrum")
	check(w.travel_here_button.visible, "Bóveda de Ferrum: «Viajar aquí»")
	w.travel_here_button.pressed.emit()
	await process_frame
	check(w.current_page == "viajar" and w.selected_destination == "boveda_ferrum", "«Viajar aquí» abre Viajar con el destino")
	check(w.route_title.text == "Vado Roto → Bóveda de Ferrum", "Ruta: Vado Roto → Bóveda de Ferrum")
	check(w.route_sub.text.contains("3,2 km") and w.route_sub.text.contains("brecha"), "3,2 km · cruza una brecha")
	check(w.option_cards.keys() == ["caravana", "montura", "atajo", "dirigible"], "4 tarjetas de viaje (atajo visible: secreto conocido)")
	var car_card: Button = w.option_cards["caravana"]
	check(car_card.find_child("Time", true, false).text == "12 min" and car_card.find_child("Cost", true, false).text == "40 oro", "Caravana: 12 min · 40 oro")
	check(car_card.find_child("Text", true, false).text == "Segura", "Caravana: insignia Segura")
	check(w.option_cards["montura"].find_child("Text", true, false).text == "Riesgo medio" and w.option_cards["atajo"].find_child("Text", true, false).text == "Riesgo alto", "Riesgo medio / alto")
	check(w.book_button.text.contains("sale en 6 min"), "Botón «Reservar caravana · sale en 6 min»")
	check(w.dest_rows.has("atajo_cueva"), "Destino secreto «Atajo de la cueva»")
	var gold0: int = w.commerce.gold
	var res: Dictionary = w.book_selected()
	check(res["ok"] and w.commerce.gold == gold0 - 40, "Reservar cobra 40 de oro")
	check(w.travel_feedback.text.contains("12 min"), "Confirmación del viaje")
	check(w.book_button.disabled and w.trip_box.get_child_count() == 1, "Viaje en curso: botón bloqueado y estado visible")
	w.select_destination("el_nido")
	check(w.option_cards.keys() == ["puerta_nido"] and w.option_cards["puerta_nido"].disabled, "El Nido desde fuera de zona segura: deshabilitado")
	w.initialize_window({"focus": Vector2(900, 600), "title": "Gildas", "poi": "npc_gildas"})
	check(w.current_page == "mapa" and cv.focus_target == Vector2(900, 600) and cv.selected_marker == "npc_gildas", "initialize_window(focus, poi) enfoca y selecciona")
	w.initialize_window({"poi": "npc_torin", "title": "Torin"})
	check(cv.focus_target == Vector2(1530, 330), "initialize_window(poi) resuelve la posición")
	w.queue_free()
	await _frames()
	_free(svc)
	_free(ks)


# --------------------------------------------------------------------------
# 8. Social
# --------------------------------------------------------------------------
func _test_social_model() -> void:
	print("-- 8. Social: amigos, grupo, préstamo de habitantes, gremio y vecindad")
	var shelter: Node = SS.new()
	var s: Node = _new_social(shelter)
	var fl: Array = s.list_friends()
	check(fl.size() == 8, "8 amigos")
	check(fl[0]["status"] == "online" and fl[fl.size() - 1]["status"] == "offline", "Ordenados: en línea primero, desconectados al final")
	var away_idx := fl.map(func(f) -> String: return f["status"]).find("away")
	check(away_idx > 0 and fl[away_idx - 1]["status"] == "online" and fl[away_idx + 1]["status"] == "offline", "Ausente entre conectados y desconectados")
	check(s.count_online() == 6, "6 en línea (5 + 1 ausente)")
	check(fl.all(func(f) -> bool: return f.has("level") and f.has("zone")), "Cada amigo con nivel y zona")
	check(s.list_friends("offline").size() == 2, "Filtro desconectados")
	check(SOC.status_label("online") == "En línea" and SOC.status_label("offline") == "Desconectado", "Etiquetas de estado")

	var pf = load("res://ui/components/PartyFrames/PartyFrames.tscn").instantiate()
	root.add_child(pf)
	await process_frame
	s.bind_party_frames(pf)
	check(pf.get_member_frames().size() == 2, "party_frames: Toro y Brisa")
	var inv := [""]
	s.party_invite_sent.connect(func(id: String) -> void: inv[0] = id)
	var r: Dictionary = s.invite_to_party("mira")
	check(r["ok"] and inv[0] == "mira" and pf.get_member_frames().size() == 3, "Invitar al grupo: Mira entra en party_frames")
	check(pf.get_member_frames().map(func(f) -> String: return f.player_name).has("Mira"), "Marco de grupo con el nombre de Mira")
	check(s.invite_to_party("ivo")["reason"] == "offline", "No se invita a un desconectado")
	check(s.invite_to_party("toro")["reason"] == "already_in_party", "Ya está en el grupo")
	check(s.invite_to_party("ulric")["reason"] == "party_full", "Grupo completo (4 con el jugador)")
	check(s.remove_from_party("toro") and pf.get_member_frames().size() == 2, "Sacar del grupo actualiza party_frames")

	var lendable: Array = s.get_lendable_inhabitants()
	var lids := _ids(lendable)
	check(not lids.has("kael") and not lids.has("lia") and lids.has("ysolde"), "Prestables: secundarios propios (ni el principal ni prestados)")
	check(not lids.has("torq") and s.lend_inhabitant("brisa", "torq")["reason"] == "busy", "Torq está de expedición: no se presta")
	check(shelter.get_character("ysolde")["room"] != "", "Ysolde trabaja en una sala antes del préstamo")
	var lent := [""]
	s.inhabitant_lent.connect(func(c: String, _f: String, _h: float) -> void: lent[0] = c)
	var lr: Dictionary = s.lend_inhabitant("brisa", "ysolde")
	check(lr["ok"] and lr["hours"] == 8.0 and lent[0] == "ysolde", "Prestar a Ysolde a Brisa 8 h")
	var ys: Dictionary = shelter.get_character("ysolde")
	check(ys["status"] == "lent_out" and ys["lent_to"] == "Brisa" and ys["room"] == "", "Ysolde sale del Refugio (prestada a Brisa)")
	check(not shelter.can_work("ysolde"), "Un prestado no trabaja en tu Refugio")
	check(not _ids(s.get_lendable_inhabitants()).has("ysolde"), "Ya no aparece como prestable")
	check(s.lend_inhabitant("brisa", "ysolde")["reason"] == "already_lent", "No se presta dos veces")
	check(s.lend_inhabitant("brisa", "kael")["reason"] == "main_character", "El principal no se presta")
	check(s.lend_inhabitant("brisa", "lia")["reason"] == "borrowed_from_other", "Lo prestado por otro no se re-presta")
	check(s.lend_inhabitant("nadie", "mira")["reason"] == "unknown_friend", "Amigo desconocido")
	check(s.tick_loans(4.0).is_empty() and float(s.loans[0]["hours_left"]) == 4.0, "Préstamo en curso (4 h restantes)")
	check(s.tick_loans(4.0) == ["ysolde"] and shelter.get_character("ysolde")["status"] == "idle" and s.loans.is_empty(), "Al terminar vuelve a casa")
	check(shelter.can_work("ysolde"), "De vuelta puede trabajar otra vez")

	check(s.guild["name"] == "Orden del Umbral" and s.guild["rank"] == "Veterano", "Gremio: Orden del Umbral · rango Veterano")
	check(s.guild_members_online().size() == 7, "Miembros conectados (7 de la lista)")
	var chest0 := int(s.guild["chest_gold"])
	var dsig := [0]
	s.guild_donation.connect(func(a: int, _c: int) -> void: dsig[0] = a)
	check(s.donate_to_guild(500, 1000)["ok"] and int(s.guild["chest_gold"]) == chest0 + 500 and dsig[0] == 500, "Donar 500 al cofre comunal")
	check(str(s.guild["donations"][0]["name"]).contains("(tú)"), "La donación aparece en el registro")
	check(s.donate_to_guild(2000, 100)["reason"] == "not_enough_gold", "No se dona más oro del que tienes")
	check(s.donate_to_guild(0)["reason"] == "invalid_amount", "Cantidad inválida")

	var grid: Array = s.get_building()
	check(grid.size() == 6 and grid[0].size() == 4, "Edificio de 6 pisos × 4 depas")
	var me: Dictionary = grid[3][1]
	check(me["is_player"] and me["owner"] == "Tú · Kael" and me["comfort"] == 62, "Tu depa (confort 62)")
	var home: Array = s.neighbors_at_home()
	check(home.size() == 8, "8 vecinos en casa (luz encendida)")
	check(home.any(func(c) -> bool: return c["owner"] == "Mira" and c["friend"] and c["guild"]), "Mira en casa: amiga y de tu gremio")
	check(not home.any(func(c) -> bool: return c["is_player"]), "El jugador no cuenta como vecino en casa")
	check(grid[0][2]["rent"] and grid[0][2]["owner"] == "", "Depas en renta")
	var pr: Dictionary = s.contribute_project("horno_comunal", 100)
	check(pr["ok"] and pr["progress"] == 3300 and not pr["done"], "Proyecto vecinal: aportar 100 de madera")
	check(s.contribute_project("horno_comunal", 9999)["done"], "Proyecto completado")
	check(s.contribute_project("horno_comunal", 1)["reason"] == "already_done", "No se aporta a un proyecto terminado")
	check(s.list_projects()[0]["ratio"] == 1.0, "Progreso del proyecto 100 %")
	check(s.can_move_free() and s.days_until_free_move() == 0, "Mudanza gratis disponible")
	var mv: Dictionary = s.move_to("umbral_7")
	check(mv["ok"] and mv["free"] and s.neighborhood["name"] == "Vecindad Umbral 7", "Mudanza gratis a Umbral 7 (con Ulric e Ivo)")
	check(not s.can_move_free() and s.days_until_free_move() == 7, "Siguiente mudanza gratis en 7 días")
	check(s.move_to("brecha_3")["reason"] == "weekly_limit", "Solo una mudanza gratis por semana")
	s.advance_days(7)
	check(s.can_move_free(), "A la semana se renueva")
	check(s.move_to("nexo_1")["reason"] == "no_free_units", "No hay depas libres en Nexo 1")
	pf.queue_free()
	_free(s)
	_free(shelter)
	await process_frame


func _test_social_window() -> void:
	print("-- 9. SocialWindow [O]")
	var shelter: Node = SS.new()
	var s: Node = _new_social(shelter)
	var w = SocialScene.instantiate()
	w.service = s
	w.commerce = _new_commerce()
	root.add_child(w)
	await _frames()
	check(w.window_id == "social_window" and w.menu_bar.active_tab == "social", "social_window con la pestaña Social activa")
	check(w.current_page == "amigos" and w.page_buttons["amigos"].text == "Amigos 8", "Sub-pestaña Amigos (8)")
	check(w.page_buttons.keys() == ["amigos", "gremio", "vecindad"], "Sub-pestañas: Amigos · Gremio · Vecindad")
	check(w.friend_rows.size() == 8, "8 filas de amigos")
	var mira_row: Control = w.friend_rows["mira"]
	check((mira_row.find_child("StatusDot", true, false)).color == w.STATUS_COLORS["online"], "Mira: punto verde (en línea)")
	check(mira_row.find_child("Level", true, false).text == "Nv 33" and mira_row.find_child("Zone", true, false).text.contains("Nexo"), "Mira: nivel 33 y zona Nexo")
	check((w.friend_rows["ivo"].find_child("StatusDot", true, false)).color == w.STATUS_COLORS["offline"], "Ivo: punto gris (desconectado)")
	check(w.invite_buttons["ivo"].disabled and w.invite_buttons["toro"].disabled and w.invite_buttons["toro"].text == "En tu grupo", "Invitar deshabilitado para desconectados y para quien ya está")
	w.invite_buttons["mira"].pressed.emit()
	await process_frame
	check(s.party.has("mira") and w.invite_buttons["mira"].text == "En tu grupo", "«Invitar al grupo» mete a Mira")
	check(_all_texts(w.party_box).contains("4/4"), "Grupo 4/4")
	w.lend_buttons["brisa"].pressed.emit()
	await process_frame
	check(w.loan_friend == "brisa" and w.loan_char != "", "«Prestar habitante» elige a Brisa y un habitante")
	check(w.lend_button.text == "Prestar a Brisa" and not w.lend_button.disabled, "Botón «Prestar a Brisa»")
	check(w.find_child("Inh_torq", true, false) == null and w.find_child("Inh_ysolde", true, false) != null, "Chips: solo habitantes prestables")
	w.choose_loan_inhabitant("mira")
	var lr: Dictionary = w.lend_selected()
	await process_frame
	check(lr["ok"] and shelter.get_character("mira")["status"] == "lent_out", "Préstamo hecho desde la ventana")
	check(_all_texts(w.loan_box).contains("Mira → Brisa"), "Lista «Prestados ahora»")
	w.set_page("gremio")
	await process_frame
	check(w.pages["gremio"].visible and not w.pages["amigos"].visible, "Página Gremio")
	check(w.find_child("GuildName", true, false).text == "Orden del Umbral", "Ficha del gremio")
	check(w.find_child("Rank", true, false).find_child("Text", true, false).text == "Tu rango: Veterano", "Tu rango")
	check(w.find_child("GuildInfo", true, false).text.contains("42 en línea"), "Miembros conectados (42)")
	var chest0 := int(s.guild["chest_gold"])
	var gold0: int = w.commerce.gold
	w.donate_buttons[500].pressed.emit()
	await process_frame
	check(int(s.guild["chest_gold"]) == chest0 + 500 and w.commerce.gold == gold0 - 500, "Donar 500: cofre +500 y tu oro −500")
	check(w.chest_label.text == T.format_amount(chest0 + 500), "Cofre actualizado en pantalla")
	check(w.menu_bar.gold_label.amount_label.text == T.format_amount(gold0 - 500), "El menú refleja el oro gastado")
	w.commerce.gold = 200
	var nd: Dictionary = w.donate(500)
	check(not nd["ok"] and w.guild_feedback.text.contains("oro suficiente"), "Donar sin oro: aviso")
	w.set_page("vecindad")
	await process_frame
	check(w.building_cells.size() == 24, "Edificio: 24 depas")
	var mira_apt: PanelContainer = w.building_cells["0:0"]
	var win_sb := mira_apt.find_child("Window", true, false).get_theme_stylebox("panel") as StyleBoxFlat
	check(win_sb.bg_color == w.LIGHT_ON, "Luz encendida en el depa de Mira")
	check((mira_apt.get_theme_stylebox("panel") as StyleBoxFlat).border_color == w.COLOR_FRIEND, "Amigos resaltados")
	check(w.building_cells["3:1"].find_child("Owner", true, false).text == "Tú · Kael", "Tu depa en el edificio")
	check(w.patio_box.get_child_count() == 6 and _all_texts(w.patio_box).contains("Punto de aparición"), "Patio común: 6 elementos (fuente = punto de aparición)")
	check(w.home_box.get_child_count() == 6, "Vecinos conectados (6)")
	check(_all_texts(w.neighborhood_header).contains("8 en casa"), "Cabecera: 8 en casa")
	var cr: Dictionary = w.contribute("horno_comunal", 100)
	check(cr["ok"] and w.hood_feedback.text == "Aportación registrada.", "Aportar al proyecto vecinal")
	check(w.find_child("MoveStatus", true, false).text == "Mudanza gratis disponible", "Mudanza gratis disponible")
	var mv: Dictionary = w.move_to("umbral_7")
	await process_frame
	check(mv["ok"] and w.find_child("HoodName", true, false).text == "Vecindad Umbral 7", "Mudanza desde la ventana")
	check(w.find_child("MoveStatus", true, false).text.contains("7 días"), "Próxima mudanza en 7 días")
	w.initialize_window({"page": "amigos"})
	check(w.current_page == "amigos", "initialize_window(page)")
	w.queue_free()
	await _frames()
	_free(s)
	_free(shelter)


# --------------------------------------------------------------------------
# 10. Comercio
# --------------------------------------------------------------------------
func _test_commerce_model() -> void:
	print("-- 10. Comercio: dos monedas, tienda cosmética y pase de 50 niveles")
	var c: Node = _new_commerce()
	check(c.gold == 12480 and c.prisms == 340, "Oro 12.480 · Prismas 340")
	check(T.GOLD == Color("#f5c35b") and T.PRISMS == Color("#7ee8ff"), "Colores: oro #f5c35b · Prismas #7ee8ff")
	check(c.shop_under_construction and c.pass_under_construction, "Tienda y Pase en construcción")
	check(c.shop_items.size() == 8 and c.rejected_items.is_empty(), "Catálogo de 8 objetos válidos")
	check(c.shop_items.all(func(i) -> bool: return i["kind"] in ["cosmetic", "comfort"]), "Solo apariencia y comodidad")
	check(c.shop_items.all(func(i) -> bool: return not c.is_pay_to_win(i)), "Ningún objeto da poder")
	check(c.list_shop_items("destacado").size() == 5 and c.list_shop_items("monturas").size() == 1, "Destacado (5) y Monturas (1)")
	check(c.is_pay_to_win({"kind": "cosmetic", "stats": {"damage": 5}}), "Apariencia con estadísticas = pay-to-win")
	check(c.is_pay_to_win({"kind": "gear"}), "Equipo de combate = pay-to-win")
	check(c.is_pay_to_win({"kind": "comfort", "xp_boost": 0.5}), "Potenciador de XP = pay-to-win")
	check(not c.is_pay_to_win({"kind": "comfort", "stats": {}}), "Comodidad sin estadísticas = válida")
	var c2: Node = COM.new()
	c2.load_from_dict({"shop": {"items": [
		{"id": "ok_skin", "kind": "cosmetic", "category": "apariencias", "price_prisms": 100},
		{"id": "p2w_sword", "kind": "gear", "category": "destacado", "price_prisms": 2000, "stats": {"damage": 50}},
		{"id": "p2w_skin", "kind": "cosmetic", "category": "apariencias", "price_prisms": 500, "power": 10},
	]}})
	check(c2.shop_items.size() == 1 and c2.rejected_items.size() == 2, "Al cargar se rechazan los objetos con poder (2)")
	check(c2.get_shop_item("p2w_sword").is_empty() and c2.rejected_items[0]["rejected_reason"] == "kind:gear", "La espada no llega al catálogo")
	var r: Dictionary = c.buy_item("mount_ciervo")
	check(r["reason"] == "under_construction" and c.prisms == 340, "Comprar: en construcción (no cobra)")
	check(c.buy_gold(1000)["reason"] == "gold_not_purchasable", "El oro no se compra")
	var req := [false]
	c.prisms_purchase_requested.connect(func(_p: String) -> void: req[0] = true)
	check(c.request_prisms()["reason"] == "under_construction" and req[0], "«+» Prismas: señal y en construcción")
	check(c.shop_packs.size() == 4, "4 paquetes de Prismas")
	check(c.spend_gold(80) and c.gold == 12400 and not c.spend_gold(999999), "Gastar oro con saldo")

	check(c.max_level == 50 and c.get_pass_levels().size() == 50, "Pase de 50 niveles")
	check(c.level == 12 and c.xp == 640 and is_equal_approx(c.pass_ratio(), 0.64), "Nivel 12 · 640/1.000 XP")
	var ms := []
	for l in range(1, 51):
		if c.is_milestone(l):
			ms.append(l)
	check(ms == [1, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50], "Hitos en 1 y cada 5 niveles")
	check(c.get_level_rewards(50)["premium"] == "Apariencia legendaria «Val'Gorath»" and c.get_level_rewards(50)["milestone"], "Recompensa del nivel 50")
	check(c.get_level_rewards(7)["free"] == "Cofre de materiales" and not c.get_level_rewards(7)["milestone"], "Niveles intermedios con recompensa menor")
	for act in ["combate", "refugio", "expediciones", "fabricacion", "social", "pesca_inventada"]:
		check(c.xp_for_activity(act) > 0, "La actividad «%s» da XP del pase" % act)
	var g: Dictionary = c.add_activity_xp("refugio", 2)
	check(g["gained"] == 160 and c.xp == 800, "Refugio ×2 = +160 XP")
	g = c.add_activity_xp("algo_nuevo")
	check(g["gained"] == 50, "Actividad no listada: XP por defecto (50)")
	var ups := [0]
	c.pass_level_up.connect(func(_l: int) -> void: ups[0] += 1)
	g = c.add_pass_xp(1200)
	check(c.level == 14 and ups[0] == 2 and c.xp == 50, "Subida de 2 niveles (12 → 14)")
	check(c.claim_reward(12)["ok"] and c.claim_reward(12)["reason"] == "already_claimed", "Reclamar nivel 12 (una vez)")
	check(c.claim_reward(20)["reason"] == "level_not_reached", "No se reclama un nivel no alcanzado")
	check(c.claim_reward(10, "premium")["reason"] == "premium_locked", "Pista del pase bloqueada")
	check(c.unlock_premium()["reason"] == "under_construction", "Desbloquear el pase: en construcción")
	c.add_pass_xp(999999)
	check(c.level == 50 and c.xp <= c.xp_per_level, "Tope en el nivel 50")
	var owned_before: int = c.owned_rewards.size()
	var unclaimed: int = c.unclaimed_count()
	var end: Dictionary = c.end_season("Temporada 2")
	check(end["auto_granted"].size() == unclaimed and c.owned_rewards.size() == owned_before + unclaimed, "Fin de temporada: lo alcanzado y no reclamado se entrega (%d)" % unclaimed)
	check(c.owned_rewards.any(func(o) -> bool: return o["level"] == 12 and o["track"] == "free"), "Lo ya reclamado sigue siendo tuyo")
	check(c.level == 1 and c.season == 2 and c.claimed.is_empty(), "Nueva temporada desde el nivel 1")
	_free(c)
	_free(c2)


func _test_shop_window() -> void:
	print("-- 11. ShopWindow (Comercio › Tienda) EN CONSTRUCCIÓN")
	var c: Node = _new_commerce()
	var w = ShopScene.instantiate()
	w.commerce = c
	root.add_child(w)
	await _frames()
	check(w.window_id == "shop_window", "window_id = shop_window")
	check(w.menu_bar.active_tab == "comercio" and w.menu_bar.active_subtab.get("comercio", "") == "tienda", "Menú: Comercio › Tienda")
	var banner = w.banner
	check(banner != null and banner.get_script() == load("res://ui/components/base/under_construction_banner.gd"), "Franja under_construction_banner.gd")
	check(banner.badge_label.text == "EN CONSTRUCCIÓN" and banner.message.contains("contenido y precios por definir"), "«EN CONSTRUCCIÓN» + mensaje de datos")
	check(banner.size.x > 300 and banner.stripe_count() > 5, "Franja diagonal visible (%d franjas)" % banner.stripe_count())
	var sub: Control = w.find_child("CommerceSubnav", true, false)
	check(sub != null and sub.find_child("Sub_tienda", true, false).button_pressed, "Sub-navegación Mercado · Tienda · Pase (Tienda activa)")
	check(w.prisms_label.text == "340" and w.prisms_label.get_theme_color("font_color") == T.PRISMS, "Saldo de Prismas 340 en #7ee8ff")
	check(w.menu_bar.prisms_label.amount_label.text == "340", "Prismas también en el menú")
	check(w.item_cards.size() == 5, "Destacado: 5 objetos")
	var kinds := []
	for id in w.item_cards:
		kinds.append(w.item_cards[id].find_child("Kind", true, false).find_child("Text", true, false).text)
	check(kinds.all(func(k) -> bool: return k in ["Apariencia", "Comodidad"]), "Catálogo: solo Apariencia y Comodidad")
	check(w.policy_label.text.contains("nunca poder en combate"), "Aviso: nunca poder en combate")
	var sig := [false]
	w.prisms_plus_pressed.connect(func() -> void: sig[0] = true)
	w.plus_button.pressed.emit()
	await process_frame
	check(sig[0] and w.category == "prismas" and w.grid.get_child_count() == 4, "«+» muestra los 4 paquetes de Prismas")
	check(w.feedback_label.text.contains("construcción"), "Compra de Prismas en construcción")
	w.select_category("monturas")
	check(w.item_cards.keys() == ["mount_ciervo"], "Categoría Monturas")
	var r: Dictionary = w.buy("mount_ciervo")
	check(r["reason"] == "under_construction" and c.prisms == 340 and w.feedback_label.text.contains("construcción"), "Comprar: aviso de obra, sin cobrar")
	w.initialize_window({"source": "prisms_plus"})
	check(w.category == "prismas", "Abrir desde Prismas «+» va a los paquetes")
	w.queue_free()
	await _frames()
	_free(c)


func _test_battle_pass_window() -> void:
	print("-- 12. BattlePassWindow (Comercio › Pase de batalla) EN CONSTRUCCIÓN")
	var c: Node = _new_commerce()
	var w = PassScene.instantiate()
	w.commerce = c
	root.add_child(w)
	await _frames(3)
	check(w.window_id == "battle_pass_window", "window_id = battle_pass_window")
	check(w.menu_bar.active_subtab.get("comercio", "") == "pase", "Menú: Comercio › Pase de batalla")
	check(w.banner.badge_label.text == "EN CONSTRUCCIÓN" and w.banner.message.contains("recompensas por definir"), "Franja «EN CONSTRUCCIÓN» del Pase")
	check(w.level_columns.size() == 50 and w.free_cells.size() == 50 and w.premium_cells.size() == 50, "50 niveles × 2 pistas")
	check(w.level_label.text == "Nivel 12" and w.xp_label.text == "640 / 1.000 XP del pase", "Nivel 12 · 640 / 1.000 XP")
	check(is_equal_approx(w.xp_bar.ratio, 0.64), "Barra de XP al 64 %")
	check(w.free_cells[10].find_child("Icon", true, false).text == "★" and w.free_cells[11].find_child("Icon", true, false).text == "◆", "Hitos marcados con ★")
	check(w.free_cells[10].find_child("Reward", true, false).text == "Título «Explorador de grietas»", "Recompensa del hito 10")
	check(w.free_cells[20].modulate.a < 1.0 and w.free_cells[12].modulate.a == 1.0, "Niveles no alcanzados atenuados")
	check(w.track_scroll.scroll_horizontal > 0, "La pista se desplaza hasta el nivel actual")
	w.free_cells[12].pressed.emit()
	await process_frame
	check(c.claimed.has("12:free") and w.free_cells[12].find_child("Icon", true, false).text == "✓", "Reclamar nivel 12 (✓)")
	check(w.feedback_label.text.contains("para siempre"), "Lo reclamado es tuyo para siempre")
	w.premium_cells[12].pressed.emit()
	check(w.feedback_label.text.contains("en construcción"), "Pista del pase bloqueada (en construcción)")
	w.free_cells[30].pressed.emit()
	check(w.feedback_label.text.contains("nivel 30"), "Nivel no alcanzado: aviso")
	check(w.challenges_box.get_child_count() == 3, "3 desafíos semanales")
	check(_all_texts(w.activity_box).contains("Refugio +80") and _all_texts(w.activity_box).contains("Otra cosa +50"), "XP por actividad: cualquier cosa cuenta")
	check(_all_texts(w).contains("nunca se pierde"), "Política: lo ganado no caduca")
	w.unlock_button.pressed.emit()
	check(w.feedback_label.text.contains("en construcción"), "Desbloquear: en construcción")
	c.add_activity_xp("expediciones", 3)
	await process_frame
	check(w.level_label.text == "Nivel 13", "La XP de expediciones sube el nivel del pase en pantalla")
	w.queue_free()
	await _frames()
	_free(c)


# --------------------------------------------------------------------------
# 13. Navegación real con UIOrchestrator (menú común)
# --------------------------------------------------------------------------
func _test_orchestrator_navigation() -> void:
	print("-- 13. Menú común + UIOrchestrator: las pestañas abren las ventanas nuevas")
	var orch: Node = root.get_node_or_null("UIOrchestrator")
	check(orch != null, "UIOrchestrator (autoload) disponible")
	if orch == null:
		return
	for id in NEW_WINDOWS:
		orch.close_window(id, true)
	await process_frame
	var bar = load("res://ui/menu/menu_bar.tscn").instantiate()
	root.add_child(bar)
	await process_frame
	orch.connect_menu_bar(bar)
	var steps := [["misiones", "quests_window"], ["mapa", "map_window"], ["social", "social_window"]]
	for st in steps:
		bar.select_tab(st[0])
		await process_frame
		check(orch.is_window_open(st[1]), "Pestaña %s abre %s" % [st[0], st[1]])
		var inst = orch.get_window_instance(st[1])
		check(inst != null and inst.menu_bar.active_tab == st[0], "%s marca su pestaña en su propio menú" % st[1])
	bar.select_subtab("comercio", "tienda")
	await process_frame
	check(orch.is_window_open("shop_window"), "Comercio › Tienda abre shop_window")
	bar.select_subtab("comercio", "pase")
	await process_frame
	check(orch.is_window_open("battle_pass_window"), "Comercio › Pase abre battle_pass_window")
	var shop = orch.get_window_instance("shop_window")
	shop.menu_bar.select_subtab("comercio", "mercado")
	await process_frame
	check(orch.is_window_open("marketplace_window"), "Desde la Tienda, Mercado abre marketplace_window")
	var router: Node = load("res://ui/orchestration/UIInputRouter.gd").new()
	check(router.handle_window_shortcut(_key(KEY_L), orch) and not orch.is_window_open("quests_window"), "[L] cierra Misiones si estaba abierta")
	check(router.handle_window_shortcut(_key(KEY_L), orch) and orch.is_window_open("quests_window"), "[L] la vuelve a abrir")
	bar.select_tab("mapa")
	check(not orch.is_window_open("map_window"), "Pulsar la pestaña de una ventana abierta la cierra (toggle)")
	var q = orch.get_window_instance("quests_window")
	q.menu_bar.request_close()
	await process_frame
	check(not orch.is_window_open("quests_window") or orch.focus_manager.current_focus_id != "quests_window", "Esc del menú cierra la ventana enfocada")
	_free(router)
	for id in NEW_WINDOWS + ["marketplace_window"]:
		orch.close_window(id, true)
	bar.queue_free()
	await _frames()
