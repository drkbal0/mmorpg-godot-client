extends SceneTree
## Suite headless: KnowledgeService (visibilidad + «???»), decisiones secreto/wiki,
## Mapa del hallazgo, Códice v2 (sub-pestañas, modal) e Inversiones.
## Run: Godot --headless --path clients/godot-mmo-client -s tests/unit/test_knowledge_service_and_codex.gd
## Exit code 0 = todo PASS.

const KS = preload("res://shared-core/KnowledgeService.gd")
const CodexScene = preload("res://ui/windows/CodexWindow/CodexWindow.tscn")
const CodexScript = preload("res://ui/windows/CodexWindow/CodexWindow.gd")

const MIN_CHECKS := 150  # si una función aborta por error de script, faltan checks -> FAIL
const T0 := 1762992000  # 13 nov 2025 00:00 UTC — reloj determinista

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


func _new_service() -> Node:
	var ks: Node = KS.new()
	ks.clock_override = T0
	ks.wiki_sync_enabled = false
	return ks


func _run() -> void:
	print("== [TEST] KnowledgeService + Códice v2 ==")
	_test_visibility_and_mask()
	_test_pending_transitions()
	_test_publish_gold_and_permanence()
	_test_discovery_map()
	_test_exclusivity_and_others()
	_test_counts_never_reveal_world_total()
	_test_investments_service()
	_test_seed_and_persistence()
	await _test_autoload_and_registry()
	await _test_codex_window()
	await _test_codex_investments_panel()
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
func _test_visibility_and_mask() -> void:
	print("-- Estados de visibilidad y enmascaramiento «???»")
	var ks := _new_service()
	check(KS.UNKNOWN == 0 and KS.SEEN == 1 and KS.KNOWN_SECRET == 2 and KS.PUBLISHED == 3, "Valores canónicos 0..3")
	check(ks.get_visibility("nada") == KS.UNKNOWN, "Id inexistente -> UNKNOWN")
	check(ks.display_name("nada") == "???", "UNKNOWN -> «???»")
	check(ks.display_name("nada", "Fallback") == "???", "UNKNOWN ignora el fallback -> «???»")
	check(not ks.is_known("nada"), "UNKNOWN no es conocido")
	check(ks.display_hint("nada") == "" and ks.display_category("nada") == "???", "UNKNOWN no revela pista ni categoría")

	ks.register_entry("crit_lobo", "criaturas", {"name": "Lobo de ceniza", "description": "Feroz."})
	check(ks.get_visibility("crit_lobo") == KS.UNKNOWN, "register_entry no descubre")
	check(ks.display_name("crit_lobo") == "???", "Registrado pero UNKNOWN -> «???»")
	check(ks.display_description("crit_lobo") == "???", "Descripción oculta si UNKNOWN")

	check(ks.mark_seen("crit_lobo", "", "Aullido en el valle"), "mark_seen UNKNOWN -> SEEN")
	check(ks.get_visibility("crit_lobo") == KS.SEEN and ks.visibility_key("crit_lobo") == "seen", "Estado SEEN / clave 'seen'")
	check(ks.display_name("crit_lobo") == "???", "SEEN -> «???»")
	check(ks.display_name("crit_lobo", "Lobo") == "???", "SEEN con fallback -> «???»")
	check(ks.display_hint("crit_lobo") == "Aullido en el valle", "SEEN expone la pista")
	check(ks.display_category("crit_lobo") == "criaturas", "SEEN expone la categoría (silueta)")
	check(not ks.is_known("crit_lobo"), "SEEN no es conocido")
	var v: Dictionary = ks.get_entry_view("crit_lobo")
	check(v["name"] == "???" and v["description"] == "???" and (v["location"] as Dictionary).is_empty(), "Vista SEEN enmascarada")

	ks.discover_entry("crit_lobo", "criaturas", {"location": {"zone": "Valle", "coords": [1, 2, 3]}})
	check(ks.get_visibility("crit_lobo") == KS.KNOWN_SECRET and ks.is_known("crit_lobo"), "Descubierto -> KNOWN_SECRET, is_known")
	check(ks.display_name("crit_lobo") == "Lobo de ceniza", "KNOWN_SECRET muestra el nombre real")
	ks.decide_entry("crit_lobo", true)
	check(ks.get_visibility("crit_lobo") == KS.PUBLISHED and ks.is_known("crit_lobo"), "PUBLISHED es conocido")
	check(ks.display_name("crit_lobo") == "Lobo de ceniza", "PUBLISHED muestra el nombre")
	ks.discover_entry("obj_sin_nombre", "objetos")
	check(ks.display_name("obj_sin_nombre", "Piedra") == "Piedra", "Conocido sin nombre usa fallback")
	check(not ks.mark_seen("crit_lobo"), "mark_seen no rebaja un conocido")
	ks.free()


func _test_pending_transitions() -> void:
	print("-- Transición determinista «Por decidir» -> secreto / publicado")
	var ks := _new_service()
	var discovered := []
	ks.entry_discovered.connect(func(id: String) -> void: discovered.append(id))
	var r: Dictionary = ks.discover_entry("obj_a", "objetos", {"name": "A"})
	check(r["ok"] and r["pending"] and r["visibility"] == KS.KNOWN_SECRET, "discover_entry -> bandeja como secreto provisional")
	ks.discover_entry("obj_b", "objetos", {"name": "B"})
	ks.discover_entry("obj_c", "objetos", {"name": "C"})
	check(ks.get_pending_ids() == ["obj_a", "obj_b", "obj_c"], "Bandeja en orden de llegada")
	check(discovered == ["obj_a", "obj_b", "obj_c"], "Señal entry_discovered por cada uno")
	check(ks.get_secrets().is_empty(), "Provisionales no cuentan como secretos consolidados")
	check(not ks.discover_entry("obj_a", "objetos")["ok"], "Redescubrir algo conocido -> already_known")
	check(ks.get_pending_ids().size() == 3, "Sin duplicados en bandeja")

	var keep: Dictionary = ks.decide_entry("obj_a", false)
	check(keep["ok"] and keep["visibility"] == KS.KNOWN_SECRET and keep["gold"] == 0, "Guardar -> KNOWN_SECRET sin oro")
	check(not ks.is_pending("obj_a") and ks.get_secrets().size() == 1, "Sale de la bandeja y entra en Mis secretos")
	var pub: Dictionary = ks.decide_entry("obj_b", true)
	check(pub["ok"] and pub["visibility"] == KS.PUBLISHED, "Publicar -> PUBLISHED")
	check(ks.get_pending_ids() == ["obj_c"], "Bandeja restante determinista")

	# Repetir el mismo guion produce exactamente el mismo estado.
	var ks2 := _new_service()
	for id in ["obj_a", "obj_b", "obj_c"]:
		ks2.discover_entry(id, "objetos", {"name": id.substr(4).to_upper()})
	ks2.decide_entry("obj_a", false)
	ks2.decide_entry("obj_b", true)
	check(JSON.stringify(ks.to_dict()) == JSON.stringify(ks2.to_dict()), "Mismo guion -> mismo estado serializado (determinista)")
	check(not ks.decide_entry("nada", true)["ok"], "Decidir algo no descubierto falla")
	ks.mark_seen("crit_x", "criaturas")
	check(ks.decide_entry("crit_x", false)["reason"] == "not_discovered", "Decidir algo SEEN -> not_discovered")
	ks.free()
	ks2.free()


func _test_publish_gold_and_permanence() -> void:
	print("-- Publicar: oro, pionero y permanencia")
	var ks := _new_service()
	var gold := [0]
	var wiki := []
	ks.gold_awarded.connect(func(a: int, _r: String) -> void: gold[0] += a)
	ks.wiki_publish_requested.connect(func(id: String, p: Dictionary) -> void: wiki.append([id, p]))
	ks.player_name = "unu"
	ks.discover_entry("obj_amuleto", "objetos", {"name": "Amuleto", "publish_bonus": 500, "pioneer_title": "Archivista"})
	ks.discover_entry("obj_daga", "objetos", {"name": "Daga"})
	var r: Dictionary = ks.decide_entry("obj_amuleto", true)
	check(r["gold"] == 500 and gold[0] == 500 and ks.gold_earned == 500, "Publicar otorga +500 de oro")
	check(r["title"] == "Archivista" and ks.titles.has("Archivista"), "Otorga el título de pionero")
	check(ks.is_pioneer("obj_amuleto"), "Marcado como pionero")
	check(str(r["wiki_url"]).ends_with("/wiki/obj_amuleto"), "URL de la wiki web")
	check(wiki.size() == 1 and wiki[0][1]["pioneer"] == "unu" and wiki[0][1]["status"] == "published", "Petición a la wiki con el modelo de entrada (pionero, estado)")
	var r2: Dictionary = ks.decide_entry("obj_daga", true)
	check(r2["gold"] == KS.DEFAULT_PUBLISH_BONUS, "Bonus por defecto si la entrada no define uno")

	var back: Dictionary = ks.decide_entry("obj_amuleto", false)
	check(not back["ok"] and back["reason"] == "published_is_permanent", "Publicado -> secreto rechazado (permanente)")
	check(ks.get_visibility("obj_amuleto") == KS.PUBLISHED, "Sigue PUBLISHED")
	check(not ks.set_visibility("obj_amuleto", KS.KNOWN_SECRET), "set_visibility no rebaja PUBLISHED")
	check(not ks.set_visibility("obj_amuleto", KS.UNKNOWN), "set_visibility no oculta PUBLISHED")
	var again: Dictionary = ks.decide_entry("obj_amuleto", true)
	check(not again["ok"] and again["reason"] == "already_published" and ks.gold_earned == 1000, "Republicar no da oro doble")

	ks.discover_entry("obj_tarde", "objetos", {"name": "Tarde"})
	ks.decide_entry("obj_tarde", false)
	var late: Dictionary = ks.publish_entry("obj_tarde")
	check(late["ok"] and ks.get_visibility("obj_tarde") == KS.PUBLISHED, "Un secreto consolidado puede publicarse después")
	ks.free()


func _test_discovery_map() -> void:
	print("-- Mapa del hallazgo")
	var ks := _new_service()
	var emitted := []
	ks.discovery_map_generated.connect(func(m: Dictionary) -> void: emitted.append(m))
	check(ks.generate_discovery_map("nada")["reason"] == "not_a_known_secret", "UNKNOWN -> sin mapa")
	ks.mark_seen("lugar_cueva", "lugares", "Brillo")
	check(not ks.generate_discovery_map("lugar_cueva")["ok"], "SEEN -> sin mapa")
	ks.discover_entry("lugar_cueva", "lugares", {"name": "Cueva", "location": {"zone": "Bosque", "coords": [10.5, 2.0, -3.0]}, "map_base_price": 400})
	var m: Dictionary = ks.generate_discovery_map("lugar_cueva")
	check(m["ok"], "Secreto conocido -> mapa generado")
	var item: Dictionary = m["item"]
	check(item["item_type"] == "discovery_map" and item["tradeable"], "Ítem comercializable de tipo discovery_map")
	check(item["coords"] == [10.5, 2.0, -3.0] and item["zone"] == "Bosque", "Coordenadas exactas y zona")
	check(item["display_name"] == "Mapa del hallazgo: Cueva", "Nombre del ítem")
	check(item["suggested_price"] == 400, "Precio sugerido exclusivo")
	check(emitted.size() == 1, "Señal discovery_map_generated")
	var m2: Dictionary = ks.generate_discovery_map("lugar_cueva")
	check(m2["item"]["id"] != item["id"], "Ids de mapa únicos")
	ks.discover_entry("obj_sin_loc", "objetos", {"name": "Sin ubicación"})
	check(ks.generate_discovery_map("obj_sin_loc")["reason"] == "no_location", "Sin ubicación -> sin mapa")
	ks.decide_entry("lugar_cueva", true)
	check(ks.generate_discovery_map("lugar_cueva")["reason"] == "already_published", "Publicado -> sin mapa (ya es público)")
	ks.free()


func _test_exclusivity_and_others() -> void:
	print("-- Exclusividad y publicación por otro jugador")
	var ks := _new_service()
	ks.discover_entry("lugar_ambar", "lugares", {"name": "Cueva de ámbar", "location": {"zone": "Z", "coords": [0, 0, 0]}, "map_base_price": 300})
	ks.decide_entry("lugar_ambar", false)
	check(ks.mark_secret_shared("lugar_ambar", "Joao"), "Otro descubre el secreto -> deja de ser exclusivo")
	check(ks.notices.size() == 1 and ks.notices[0]["kind"] == "secret_shared", "Aviso «ya no es exclusivo»")
	check(ks.generate_discovery_map("lugar_ambar")["item"]["suggested_price"] == 150, "El mapa baja de precio")
	ks.discover_entry("obj_x", "objetos", {"name": "X"})
	check(ks.mark_published_by_other("obj_x", "Mira"), "Otro publica antes")
	check(ks.get_visibility("obj_x") == KS.PUBLISHED and not ks.is_pioneer("obj_x"), "PUBLISHED sin pionero propio")
	check(not ks.is_pending("obj_x") and ks.gold_earned == 0, "Sale de la bandeja sin bonus")
	check(ks.notices[0]["kind"] == "pioneer_lost", "Aviso de pérdida de pionero")
	ks.free()


func _test_counts_never_reveal_world_total() -> void:
	print("-- Contadores: solo descubrimientos propios")
	var ks := _new_service()
	for i in 5:
		ks.register_entry("crit_%d" % i, "criaturas", {"name": "C%d" % i})
	ks.mark_seen("crit_0", "", "sombra")
	ks.discover_entry("crit_1", "criaturas")
	ks.decide_entry("crit_1", false)
	ks.discover_entry("crit_2", "criaturas")
	ks.decide_entry("crit_2", true)
	check(ks.count_discovered("criaturas") == 2, "Criaturas: 2 descubiertas (no 5 del mundo, ni la vista de lejos)")
	check(ks.list_entries("criaturas").size() == 3, "Lista: conocidas + vistas de lejos, nunca UNKNOWN")
	var sc: Dictionary = ks.get_status_counts()
	check(sc["secrets"] == 1 and sc["published"] == 1 and sc["pioneer"] == 1 and sc["seen"] == 1, "Contadores de estado")
	check(not ks.has_method("count_world_total") and not ks.has_method("get_world_total"), "Sin API de total del mundo")
	check(ks.list_entries("", "c1").size() == 1, "Búsqueda por nombre visible")
	check(ks.list_entries("", "C0").is_empty(), "La búsqueda no encuentra nombres ocultos")
	ks.free()


func _test_investments_service() -> void:
	print("-- Inversiones (servicio)")
	var ks := _new_service()
	ks.add_investment({"id": "inv_a", "name": "Puesto A", "share": 0.02, "status": "active", "market_value": 1000, "history": [100, 200]})
	ks.add_investment({"id": "inv_b", "name": "Forja B", "share": 0.015, "status": "active", "market_value": 500})
	ks.add_investment({"id": "inv_c", "name": "Tienda cerrada", "share": 0.03, "status": "paused"})
	ks.add_investment({"id": "inv_m", "name": "En misión", "share": 0.0, "status": "mission"})
	check((ks.get_investment("inv_a")["history"] as Array).size() == KS.HISTORY_DAYS, "Histórico normalizado a 14 días")
	check(ks.record_transaction("inv_a", 10000) == 200, "2 % de 10.000 = 200")
	check(ks.record_transaction("inv_b", 1000) == 15, "1,5 % de 1.000 = 15")
	check(ks.record_transaction("inv_c", 10000) == 0, "Contrato pausado: no cobra")
	check(ks.record_transaction("inv_m", 10000) == 0, "En misión: no cobra")
	check(ks.record_transaction("inv_a", -5) == 0, "Importe inválido ignorado")
	var s: Dictionary = ks.get_investment_summary()
	check(s["today"] == 200 + 200 + 15, "Hoy = histórico de hoy + transacciones")
	check(s["yesterday"] == 100, "Ayer")
	check(is_equal_approx(s["change_pct"], 315.0), "Variación vs. ayer (+315 %)")
	check(s["week"] == 100 + 415, "Semana = últimos 7 días")
	check(s["active_count"] == 2 and s["portfolio_value"] == 1500, "Puestos activos y valor de participaciones")
	check(s["pending_payout"] == 215 and ks.pending_payout == 215, "Por cobrar acumula las participaciones")
	var paid := [0]
	ks.payout_collected.connect(func(a: int) -> void: paid[0] = a)
	var c: Dictionary = ks.collect_to_shelter()
	check(c["ok"] and c["amount"] == 215 and c["destination"] == "shelter_storage", "Cobrar al Refugio envía al almacén")
	check(ks.pending_payout == 0 and ks.total_collected == 215 and ks.gold_earned == 215 and paid[0] == 215, "Por cobrar a 0 y oro registrado")
	check(not ks.collect_to_shelter()["ok"], "Nada que cobrar -> rechazado")
	ks.advance_day()
	check(ks.get_investment_summary()["today"] == 0 and ks.get_investment_summary()["yesterday"] == 415, "advance_day desplaza el histórico")
	ks.add_offer({"id": "o1", "name": "Taberna", "share": 0.015, "expires_in_days": 1})
	ks.advance_day()
	check(ks.offers.is_empty(), "Oferta caducada se retira")
	ks.free()


func _test_seed_and_persistence() -> void:
	print("-- Seed de datos y persistencia")
	var ks := _new_service()
	check(ks.load_seed(KS.DEFAULT_SEED_PATH), "Carga el seed JSON del Códice")
	check(ks.get_pending_ids().size() == 3, "Seed: 3 en «Por decidir» (como el diseño)")
	check(ks.display_name("item_cofre_ferrum") == "???" and ks.display_hint("item_cofre_ferrum") == "Visto en un cofre de Ferrum", "Seed: visto de lejos enmascarado")
	check(ks.investments.size() == 5 and ks.pending_payout == 2140, "Seed: 5 inversiones y 2.140 por cobrar")
	var copy := _new_service()
	copy.load_from_dict(JSON.parse_string(JSON.stringify(ks.to_dict())))
	check(JSON.stringify(copy.to_dict()) == JSON.stringify(ks.to_dict()), "to_dict/load_from_dict ida y vuelta")
	ks.free()
	copy.free()


func _test_autoload_and_registry() -> void:
	print("-- Autoload y registro de ventana")
	var cfg := ConfigFile.new()
	cfg.load("res://project.godot")
	check(str(cfg.get_value("autoload", "KnowledgeService", "")) == "*res://shared-core/KnowledgeService.gd", "KnowledgeService registrado como autoload")
	var Registry = load("res://ui/orchestration/UIWindowRegistry.gd")
	var reg: Node = Registry.new()
	check(reg.get_metadata("codex_window").scene_path == "res://ui/windows/CodexWindow/CodexWindow.tscn", "codex_window -> Códice v2")
	reg.free()
	var bar = load("res://ui/menu/menu_bar.tscn").instantiate()
	root.add_child(bar)
	var nav := [""]
	bar.navigation_requested.connect(func(w: String, _p: Dictionary) -> void: nav[0] = w)
	var ev := InputEventKey.new()
	ev.keycode = KEY_J
	ev.pressed = true
	check(bar.handle_shortcut(ev) and nav[0] == "codex_window", "Menú: [J] navega a codex_window")
	bar.queue_free()
	await process_frame


func _make_codex(ks: Node) -> Node:
	var codex = CodexScene.instantiate()
	check(codex.get_script() == CodexScript, "CodexWindow.tscn carga su script")
	codex.service = ks
	root.add_child(codex)
	return codex


func _test_codex_window() -> void:
	print("-- Códice v2: sub-pestañas, entradas y decisiones")
	var ks := _new_service()
	root.add_child(ks)
	ks.load_seed(KS.DEFAULT_SEED_PATH)
	var codex = _make_codex(ks)
	await process_frame
	await process_frame

	check(codex.window_id == "codex_window" and codex.is_in_group("codex_window"), "Ventana registrada como codex_window")
	check(codex.service == ks, "Usa el servicio inyectado")
	check(codex.menu_bar != null and codex.menu_bar.active_tab == "codice", "Menú común con la pestaña Códice [J] activa")
	check(codex.menu_bar.get_shortcut("codice") == "J", "Atajo J visible en la pestaña")
	var ids: Array = codex.get_subtab_ids()
	for sid in ["entradas", "por_decidir", "secretos", "publicados", "inversiones"]:
		check(ids.has(sid) and codex.pages.has(sid) and codex.pages[sid] is Control, "Sub-pestaña instanciada: " + sid)
	check(codex.current_subtab == "entradas" and codex.pages["entradas"].visible, "Arranca en Entradas")
	check(codex.subnav_buttons["por_decidir"].text == "Por decidir · 3", "Subnav muestra «Por decidir · 3»")

	# Entradas: categorías con contadores propios y «???».
	for c in ["criaturas", "objetos", "lugares", "formulas", "pnj"]:
		check(codex.category_buttons.has(c), "Categoría en la barra lateral: " + c)
	check(codex.category_buttons["objetos"].text.ends_with(" " + str(ks.count_discovered("objetos"))), "Contador de Objetos = descubrimientos propios")
	var names: Dictionary = codex.get_visible_entry_names()
	check(names.get("item_cofre_ferrum", "") == "???", "Rejilla: visto de lejos se muestra «???»")
	check(names.get("item_daga_eco", "") == "Daga de eco", "Rejilla: publicado muestra su nombre")
	ks.register_entry("item_oculto", "objetos", {"name": "NO DEBE VERSE"})
	codex.refresh()
	names = codex.get_visible_entry_names()
	check(not names.has("item_oculto"), "Rejilla: UNKNOWN no aparece")
	var texts := _all_texts(codex)
	check(not texts.contains("NO DEBE VERSE"), "Ningún texto de la ventana filtra un nombre UNKNOWN")
	codex.select_category("criaturas")
	names = codex.get_visible_entry_names()
	check(names.size() == 2 and codex.entries_header.text.contains("1 descubiertos"), "Filtro por categoría (1 conocida + 1 vista de lejos)")
	codex.select_category("")

	# Por decidir -> modal lado a lado.
	codex.select_subtab("por_decidir")
	check(codex.pages["por_decidir"].visible and not codex.pages["entradas"].visible, "Cambio de sub-pestaña visible")
	check(codex.pending_list.get_child_count() == 3, "Bandeja con 3 descubrimientos")
	check(codex.open_decision("item_amuleto_vacio") and codex.decision_modal.visible, "Abre el modal de decisión")
	var opts: Node = codex.decision_modal.find_child("Options", true, false)
	check(opts is HBoxContainer and opts.get_child_count() == 2, "Modal con dos opciones lado a lado")
	check(opts.get_child(0).name == "OptionSecret" and opts.get_child(1).name == "OptionPublish", "A: Guardar el secreto · B: Publicar en la wiki")
	check(codex.decision_publish_button.text == "Publicar · +500", "Botón «Publicar · +500»")
	check(codex.decision_modal.find_child("PermanentWarning", true, false) != null, "Aviso de que publicar es permanente")
	var made := []
	codex.decision_made.connect(func(id: String, r: Dictionary) -> void: made.append([id, r]))
	var gold_before: int = codex.menu_bar.gold_label.amount
	codex.decision_publish_button.pressed.emit()
	check(ks.get_visibility("item_amuleto_vacio") == KS.PUBLISHED, "Botón Publicar -> PUBLISHED")
	check(not codex.decision_modal.visible and made.size() == 1 and made[0][1]["gold"] == 500, "Modal cerrado y decisión emitida con +500")
	check(codex.menu_bar.gold_label.amount == gold_before + 500, "Oro del menú sube +500")
	check(ks.titles.has("Archivista"), "Título «Archivista» concedido")
	check(codex.pending_list.get_child_count() == 2 and codex.subnav_buttons["por_decidir"].text == "Por decidir · 2", "Bandeja y subnav actualizados")
	check(not codex.open_decision("item_amuleto_vacio"), "No se puede volver a decidir algo publicado")

	codex.open_decision("crit_guardia_carmesi")
	codex.decision_keep_button.pressed.emit()
	check(ks.get_visibility("crit_guardia_carmesi") == KS.KNOWN_SECRET and not ks.is_pending("crit_guardia_carmesi"), "Botón Guardar -> KNOWN_SECRET consolidado")

	codex.open_decision("pnj_taberna_nexo")
	codex.decision_cancel_button.pressed.emit()
	check(ks.is_pending("pnj_taberna_nexo") and not codex.decision_modal.visible, "Decidir más tarde mantiene la bandeja")

	# Mis secretos: crear Mapa del hallazgo.
	codex.select_subtab("secretos")
	var row: Node = codex.secrets_list.find_child("Secret_crit_guardia_carmesi", true, false)
	check(row != null, "El secreto aparece en Mis secretos")
	var maps := []
	codex.discovery_map_created.connect(func(m: Dictionary) -> void: maps.append(m))
	var mk: Button = row.find_child("MapButton", true, false) if row else null
	check(mk != null and mk.text == "Crear Mapa del Hallazgo", "Botón «Crear Mapa del Hallazgo»")
	if mk:
		mk.pressed.emit()
	check(maps.size() == 1 and maps[0]["entry_id"] == "crit_guardia_carmesi", "Mapa creado desde Mis secretos")
	check(not codex.create_map_for("item_daga_eco")["ok"], "Mapa de algo publicado rechazado desde la UI")

	# Publicados: badge pionero, fecha y wiki.
	codex.select_subtab("publicados")
	var prow: Node = codex.published_list.find_child("Published_item_amuleto_vacio", true, false)
	check(prow != null, "Recién publicado aparece en Publicados")
	var badge: Node = prow.find_child("Badge", true, false) if prow else null
	check(badge != null and badge.get_meta("badge_key") == "pioneer", "Badge PIONERO")
	check(prow != null and _all_texts(prow).contains("13 nov 2025"), "Fecha de publicación")
	check(prow != null and prow.find_child("WikiButton", true, false).tooltip_text.ends_with("/wiki/item_amuleto_vacio"), "Enlace a la wiki web")
	var other: Node = codex.published_list.find_child("Published_item_resina_verdalia", true, false)
	check(other != null and other.find_child("Badge", true, false).get_meta("badge_key") == "published", "Publicado por otro: badge PUBLICADO")

	# Compatibilidad v1 (Hojas de descubrimiento del inventario).
	check(codex.is_secret_acquired("item_daga_eco") and not codex.is_secret_acquired("item_oculto"), "Compat: is_secret_acquired usa el servicio")
	codex.unlock_secret_from_sheet("item_hoja", "Hoja leída")
	check(ks.get_visibility("item_hoja") == KS.KNOWN_SECRET and not ks.is_pending("item_hoja"), "Compat: unlock_secret_from_sheet aprende sin bandeja")

	codex.queue_free()
	ks.queue_free()
	await process_frame


func _test_codex_investments_panel() -> void:
	print("-- Códice v2: panel de Inversiones")
	var ks := _new_service()
	root.add_child(ks)
	ks.load_seed(KS.DEFAULT_SEED_PATH)
	var codex = _make_codex(ks)
	await process_frame
	codex.select_subtab("inversiones")
	await process_frame
	await process_frame
	check(codex.earnings_chart.size.x > 0.0, "Gráfico con tamaño tras el layout")
	check(codex.pages["inversiones"].visible, "Inversiones visible")
	check(codex.kpi_labels["today"].text == "+1.084", "KPI Hoy = +1.084 (412+380+96+196)")
	check(codex.kpi_labels["today_sub"].text.contains("18 %"), "Variación vs. ayer ▲ 18 %")
	check(codex.kpi_labels["week_sub"].text == "4 puestos activos", "4 puestos activos")
	check(codex.kpi_labels["value"].text == "41.000", "Valor de participaciones 41.000")
	check(codex.investments_table.get_child_count() == 5, "Tabla con 5 inversiones")
	var mission: Node = codex.investments_table.find_child("Inv_inv_taller_runico", true, false)
	check(mission != null and _all_texts(mission).contains("Misión 2/3"), "Estado «Misión 2/3»")
	check(_all_texts(codex.investments_table.find_child("Inv_inv_bram", true, false)).contains("1,5 %"), "Parte 1,5 %")
	check(codex.earnings_chart.values.size() == 14 and codex.earnings_chart.values[13] == 1084, "Gráfico: 14 días, hoy = 1.084")
	check(codex.earnings_chart._get_tooltip(codex.earnings_chart.bar_rect(13).get_center()).begins_with("Hoy"), "Tooltip por barra")
	check(codex.payout_label.text == "2.140 oro" and not codex.collect_button.disabled, "Por cobrar 2.140 oro")
	check(_all_texts(codex.offers_box).contains("Taberna del Nexo"), "Ofertas pendientes")
	check(_all_texts(codex.notices_box).contains("ya no es exclusivo"), "Aviso de secreto no exclusivo")
	check(codex.map_sales_label.text == "3 publicados · 7 vendidos · +1.260 oro", "Mapas del hallazgo en venta")

	ks.record_transaction("inv_orla", 5000)  # 2 % -> +100
	await process_frame
	check(codex.kpi_labels["today"].text == "+1.184", "Transacción de otro jugador actualiza Hoy")
	check(codex.payout_label.text == "2.240 oro", "Y el total por cobrar")
	var paid := [0]
	codex.payout_collected.connect(func(a: int) -> void: paid[0] = a)
	codex.collect_button.pressed.emit()
	check(paid[0] == 2240 and ks.pending_payout == 0, "«Cobrar al Refugio» cobra 2.240")
	check(codex.payout_label.text == "0 oro" and codex.collect_button.disabled, "Por cobrar a 0 y botón desactivado")
	check(codex.fmt_int(1234567) == "1.234.567" and codex.fmt_int(-12480) == "-12.480", "Formato de miles es-ES")
	codex.queue_free()
	ks.queue_free()
	await process_frame


func _all_texts(n: Node) -> String:
	if n == null:
		return ""
	var out := ""
	if n is Label or n is Button:
		out += str(n.text) + "\n"
	for c in n.get_children():
		out += _all_texts(c)
	return out
