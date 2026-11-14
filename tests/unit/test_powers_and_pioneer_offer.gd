extends SceneTree
## Suite headless (UI v2.4 Pasos 6-7): oferta de inversión del pionero y sistema
## de Poderes (Crisol · Atlas · Constelación · Afinidades) + atajo [N].
## Run: Godot --headless --path clients/godot-mmo-client -s tests/unit/test_powers_and_pioneer_offer.gd
## Exit code 0 = todo PASS.

const PS = preload("res://shared-core/PowersService.gd")
const KS = preload("res://shared-core/KnowledgeService.gd")
const T = preload("res://ui/tokens/hud_tokens.gd")
const PowersScene = preload("res://ui/windows/PowersWindow/PowersWindow.tscn")
const PowersScript = preload("res://ui/windows/PowersWindow/PowersWindow.gd")
const OfferScene = preload("res://ui/windows/PioneerOfferModal/PioneerOfferModal.tscn")
const OfferScript = preload("res://ui/windows/PioneerOfferModal/PioneerOfferModal.gd")
const CodexScene = preload("res://ui/windows/CodexWindow/CodexWindow.tscn")

const MIN_CHECKS := 150
const T0 := 1762992000

var _fails: Array[String] = []
var _checks := 0


class FakeOrchestrator extends Node:
	var registry: Node
	var toggled: Array[String] = []

	func toggle_window(id: String, _params: Dictionary = {}) -> void:
		toggled.append(id)


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
	print("== [TEST] Oferta del pionero + Poderes (Crisol, Atlas, Constelación, Afinidades) ==")
	await _test_registry_and_shortcut()
	_test_service_energies_and_affinity()
	_test_crisol_service()
	_test_loadout_and_resonance()
	_test_atlas_service()
	_test_constellation_service()
	await _test_powers_window_crisol()
	await _test_powers_window_atlas()
	await _test_powers_window_constellation_and_affinities()
	_test_offer_service()
	await _test_offer_modal()
	await _test_offer_defer_in_codex()
	check(_checks >= MIN_CHECKS, "Se ejecutaron todas las comprobaciones (%d >= %d)" % [_checks, MIN_CHECKS])
	print("== %d checks, %d fallos ==" % [_checks, _fails.size()])
	if _fails.is_empty():
		print("RESULTADO: 100% PASS")
		quit(0)
	else:
		for f in _fails:
			printerr("  - ", f)
		quit(1)


func _key(code: int) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	return ev


func _all_texts(n: Node) -> String:
	if n == null:
		return ""
	var out := ""
	if n is Label or n is Button or n is LineEdit:
		out += str(n.text) + "\n"
	for c in n.get_children():
		out += _all_texts(c)
	return out


# --------------------------------------------------------------------------
func _test_registry_and_shortcut() -> void:
	print("-- Registro [N] -> powers, menú común y UIInputRouter")
	var Registry = load("res://ui/orchestration/UIWindowRegistry.gd")
	var UITypes = load("res://ui/types/UITypes.gd")
	var reg: Node = Registry.new()
	check(reg.is_registered("powers"), "UIWindowRegistry: «powers» registrada")
	check(reg.get_metadata("powers").scene_path == "res://ui/windows/PowersWindow/PowersWindow.tscn", "powers -> PowersWindow.tscn")
	check(ResourceLoader.exists(reg.get_metadata("powers").scene_path), "La escena de Poderes existe")
	check(reg.get_shortcut_keys("powers") == [KEY_N], "powers -> [KEY_N]")
	check(reg.get_window_for_key(KEY_N) == "powers", "KEY_N resuelve a «powers»")
	check(reg.get_window_for_key(KEY_F12) == "", "Tecla sin ventana -> \"\"")
	check(reg.get_shortcut_keys("codex_window") == [], "Ventanas sin atajo declarado -> []")
	check(reg.is_registered("pioneer_offer") and reg.get_metadata("pioneer_offer").category == UITypes.WindowCategory.MODAL_OVERLAY, "pioneer_offer registrada como MODAL_OVERLAY")
	check(ResourceLoader.exists(reg.get_metadata("pioneer_offer").scene_path), "La escena del modal de oferta existe")

	var bar = load("res://ui/menu/menu_bar.tscn").instantiate()
	root.add_child(bar)
	check(bar.get_tab("poderes")["window"] == "powers" and bar.get_shortcut("poderes") == "N", "Menú: pestaña Poderes [N] -> powers")
	var nav := [""]
	bar.navigation_requested.connect(func(w: String, _p: Dictionary) -> void: nav[0] = w)
	check(bar.handle_shortcut(_key(KEY_N)) and nav[0] == "powers", "Menú: [N] navega a powers")
	bar.queue_free()

	var router: Node = load("res://ui/orchestration/UIInputRouter.gd").new()
	var orch := FakeOrchestrator.new()
	orch.registry = reg
	check(router.handle_window_shortcut(_key(KEY_N), orch) and orch.toggled == ["powers"], "UIInputRouter: [N] abre/cierra powers")
	var ctrl_n := _key(KEY_N)
	ctrl_n.ctrl_pressed = true
	check(not router.handle_window_shortcut(ctrl_n, orch), "Ctrl+N no abre Poderes")
	var echo := _key(KEY_N)
	echo.echo = true
	check(not router.handle_window_shortcut(echo, orch), "Eco de tecla ignorado")
	check(not router.handle_window_shortcut(_key(KEY_Y), orch), "Tecla sin ventana no se consume")
	router.free()
	orch.free()
	reg.free()
	await process_frame


# --------------------------------------------------------------------------
func _test_service_energies_and_affinity() -> void:
	print("-- Energías (Anexo B) y afinidades")
	var s: Node = PS.new()
	check(s.get_energy_count() == 10 and s.energies == T.ENERGY_KEYS, "10 energías canónicas del Anexo B, en orden")
	check(s.energy_name("vacio") == "Vacío" and s.energy_color("calor") == Color("#ff7a45"), "Nombre y color desde hud_tokens")
	check(PS.xp_for_level(1) == 0 and PS.xp_for_level(2) == 100 and PS.xp_for_level(3) == 300, "PX acumulada por nivel (N × 100)")
	check(PS.level_for_xp(299) == 2 and PS.level_for_xp(300) == 3, "Nivel por PX en el umbral")
	check(s.get_affinity_level("vacio") == 14 and s.get_affinity_level("luz") == 1, "Semilla: Vacío nv 14, Luz nv 1")
	var p: Dictionary = s.get_affinity_progress("vacio")
	check(p["level"] == 14 and p["needed"] == 1400 and absf(p["ratio"] - 0.6) < 0.01, "Progreso de Vacío: 60 % de 1.400 PX")
	var before := int(s.get_affinity_progress("luz")["into"])
	var gained: Dictionary = s.record_combat_use(["luz", "luz", "sombra"], 25)
	check(int(s.get_affinity_progress("luz")["into"]) == before + 25, "Uso en combate: +25 PX (energía repetida cuenta una vez)")
	check(gained.has("luz") and gained.has("sombra") and gained.size() == 2, "Ganan PX las 2 energías distintas")
	var ups := [0]
	s.affinity_level_up.connect(func(_e: String, _l: int) -> void: ups[0] += 1)
	check(s.add_affinity_xp("luz", 200) == 1 and ups[0] == 1 and s.get_affinity_level("luz") == 2, "Subida de nivel con señal")
	check(s.add_affinity_xp("luz", 0) == 0 and s.add_affinity_xp("inexistente", 50) == 0, "PX inválida ignorada")
	s.set_affinity("marea", 20)
	check(s.get_affinity_progress("marea")["max"] and s.get_affinity_progress("marea")["ratio"] == 1.0, "Nivel máximo 20 -> barra llena")
	check(s.list_energies("", "affinity")[0] == "marea", "Orden por afinidad (desc)")
	check(s.list_energies("", "az")[0] == "calor" and s.list_energies("", "az")[-1] == "vacio", "Orden A–Z")
	check(s.list_energies("", "recent")[0] == "luz", "Orden por uso reciente")
	check(s.list_energies("sav") == ["savia"], "Buscador de energías")
	s.free()


# --------------------------------------------------------------------------
func _test_crisol_service() -> void:
	print("-- Crisol: 2-3 energías + forma + ritmo")
	var s: Node = PS.new()
	check(PS.FORMS == ["proyectil", "area", "cono", "aura", "trampa"], "5 formas canónicas")
	check(PS.RHYTHMS == ["instantaneo", "canalizado", "retardado"], "3 ritmos canónicos")
	var p: Dictionary = s.compose_power(["vacio", "calor"], "area", "canalizado")
	check(p["ok"] and p["name"] == "Grieta ígnea", "Vacío + Calor + Área + Canalizado = Grieta ígnea")
	check(p["is_new"], "Combinación inédita marcada «¡NUEVA!»")
	check(p["energies"] == ["vacio", "calor"] and p["key"] == "vacio+calor|area|canalizado", "Clave canónica")
	var q: Dictionary = s.compose_power(["calor", "vacio"], "area", "canalizado")
	check(q["key"] == p["key"], "El orden de las energías no cambia el poder")
	# Potencia = Σ afinidad × 3 × (1 + Constelación). Vacío: +12 % rama + 8 % general; Calor: +8 %.
	check(s.get_constellation_bonus("vacio") == 12.0 and s.get_constellation_general_bonus() == 8.0, "Constelación: +12 % Vacío y +8 % general")
	check(p["potency"] == roundi(14 * 3 * 1.20 + 9 * 3 * 1.08), "Potencia 80 = Vacío 14 + Calor 9 con bonus")
	check(str(p["breakdown"]).contains("Vacío 14 + Calor 9"), "Desglose de potencia por afinidades")
	var known: Dictionary = s.compose_power(["eco", "pulso"], "cono", "instantaneo")
	check(known["ok"] and not known["is_new"] and known["name"] == "Resonancia sónica", "Fórmula ya conocida no es «¡NUEVA!»")
	var trio: Dictionary = s.compose_power(["vacio", "vacio", "eco"], "area", "retardado")
	check(trio["ok"] and trio["name"] == "Colapso dimensional" and trio["energies"].size() == 3, "3 energías: Colapso dimensional")
	var proc: Dictionary = s.compose_power(["sombra", "luz", "marea"], "trampa", "retardado")
	check(proc["ok"] and proc["is_new"] and not proc["in_catalog"] and proc["name"] == "Trampa de Marea, Sombra y Luz", "Combinación fuera de catálogo: nombre generado")
	check(s.compose_power(["vacio"], "area", "canalizado")["reason"] == "too_few_energies", "1 energía -> too_few_energies")
	check(s.compose_power([], "area", "canalizado")["reason"] == "too_few_energies", "0 energías -> too_few_energies")
	check(s.compose_power(["vacio", "eco", "pulso", "runa"], "area", "canalizado")["reason"] == "too_many_energies", "4 energías -> too_many_energies")
	check(s.compose_power(["vacio", "nada"], "area", "canalizado")["reason"] == "unknown_energy", "Energía desconocida rechazada")
	check(s.compose_power(["vacio", "eco"], "esfera", "canalizado")["reason"] == "invalid_form", "Forma inválida rechazada")
	check(s.compose_power(["vacio", "eco"], "area", "lento")["reason"] == "invalid_rhythm", "Ritmo inválido rechazado")
	for f in PS.FORMS:
		for r in PS.RHYTHMS:
			if not s.compose_power(["runa", "savia"], f, r)["ok"]:
				check(false, "Forma %s / ritmo %s válidos" % [f, r])
	check(true, "Las 15 combinaciones forma × ritmo son válidas")
	var dummy: Dictionary = s.test_on_dummy(p)
	check(dummy["ok"] and dummy["was_new"] and dummy["seconds"] == 60 and dummy["dps"] > 0, "«Probar en el maniquí»: 60 s y DPS")
	check(not s.compose_power(["vacio", "calor"], "area", "canalizado")["is_new"], "Tras probarla deja de ser «¡NUEVA!»")
	check(not s.test_on_dummy(s.compose_power(["vacio"], "area", "canalizado"))["ok"], "Maniquí rechaza poderes inválidos")
	var hint: Dictionary = s.get_crucible_hint()
	check(hint["pair"] == "calor+pulso" and str(hint["text"]).contains("herrero del Nexo") and hint["untested"] == 11, "Pista de PNJ y 11 pistas sin probar")
	s.discover_power(s.compose_power(["calor", "pulso"], "proyectil", "instantaneo"))
	check(s.get_crucible_hint()["untested"] == 10 and s.get_crucible_hint()["pair"] != "calor+pulso", "Probar la pareja consume la pista")
	s.free()


# --------------------------------------------------------------------------
func _test_loadout_and_resonance() -> void:
	print("-- Conjunto: 1 Núcleo · 6 activos · 2 Ecos + resonancia")
	var s: Node = PS.new()
	check(s.active_slots.size() == 6 and s.echo_slots.size() == 2, "6 ranuras activas y 2 Ecos")
	check(s.slot_view(s.core_slot)["name"] == "Colapso dimensional", "Núcleo: Colapso dimensional")
	check(s.slot_view(s.active_slots[0])["name"] == "Haz de grieta" and s.active_slots[2] == "", "Ranura 1 ocupada, ranura 3 libre")
	check(s.first_free_active_slot() == 2, "Primera ranura libre = 3")
	check(s.slot_view(s.echo_slots[0])["name"] == "Armonía del vacío" and s.echo_slots[1] == "", "Eco pasivo 1 y Eco 2 libre")
	var res: Array = s.get_resonance()
	check(res[0]["energy"] == "vacio" and res[0]["count"] == 4 and res[0]["bonus_pct"] == 8, "Vacío en 4 poderes: +8 %")
	check(s.get_resonance_bonus("eco") == 6 and s.get_resonance_bonus("calor") == 4, "Eco ×3 (+6 %), Calor ×2 (+4 %)")
	check(s.get_resonance_bonus("pulso") == 0 and s.get_resonance_bonus("hierro") == 0, "Energía sin repetir: sin bonus")
	check(s.resonance_summary() == "Vacío aparece en 4 poderes: +8 % de potencia. Un 5.º activaría «Eco del abismo».", "Resumen de resonancia (texto del diseño)")
	var base_haz: int = s.compute_potency(s.get_formula("haz_de_grieta")["energies"])["potency"]
	check(s.get_loadout_power_potency(s.active_slots[0]) == roundi(base_haz * 1.08), "La resonancia sube la potencia del poder equipado")
	var p: Dictionary = s.compose_power(["vacio", "calor"], "area", "canalizado")
	var r: Dictionary = s.equip("active", 2, p)
	check(r["ok"] and s.active_slots[2] == p["key"], "Equipar en la ranura 3")
	check(s.is_discovered(p["key"]), "Equipar descubre la combinación")
	res = s.get_resonance()
	check(res[0]["count"] == 5 and res[0]["set_active"] and s.resonance_summary().contains("«Eco del abismo» activo"), "5.º poder de Vacío activa «Eco del abismo»")
	check(s.equip("active", 6, p)["reason"] == "invalid_slot" and s.equip("echo", 2, p)["reason"] == "invalid_slot" and s.equip("core", 1, p)["reason"] == "invalid_slot", "Ranuras fuera de rango rechazadas")
	check(s.equip("active", 0, {"ok": false})["reason"] == "invalid_power", "Poder inválido no se equipa")
	s.equip("active", 5, p)
	check(s.active_slots[5] == p["key"] and s.active_slots[2] == "", "Un poder no se duplica: se mueve de ranura")
	var echo: Dictionary = s.compose_power(["vacio", "vacio"], "aura", "canalizado")
	check(s.equip("echo", 1, echo)["ok"] and s.echo_slots[1] == echo["key"] and s.echo_slots[0] == "", "Eco pasivo movido a la ranura 2")
	check(s.unequip("active", 5) and not s.unequip("active", 5), "Desequipar ranura (y no dos veces)")
	check(s.get_loadout_keys().size() == 5 and s.get_loadout_keys(true).size() == 6, "Claves del conjunto (con y sin Ecos)")
	s.free()


# --------------------------------------------------------------------------
func _test_atlas_service() -> void:
	print("-- Atlas N × N")
	var s: Node = PS.new()
	var m: Array = s.get_atlas_matrix()
	check(m.size() == 10 and (m[0] as Array).size() == 10, "Matriz 10 × 10")
	check(m[0][0]["pure"] and m[0][0]["state"] == PS.CELL_DISCOVERED and m[0][0]["count"] == 2, "Diagonal Vacío pura: 2 fórmulas")
	check(m[3][2]["pair"] == m[2][3]["pair"] and m[3][2]["count"] == m[2][3]["count"], "Matriz simétrica (Pulso×Eco = Eco×Pulso)")
	check(s.get_atlas_cell("eco", "pulso")["count"] == 2 and PS.cell_label(s.get_atlas_cell("eco", "pulso")) == "2", "Eco + Pulso: descubierta con 2 fórmulas")
	var hint: Dictionary = s.get_atlas_cell("calor", "pulso")
	check(hint["state"] == PS.CELL_HINT and PS.cell_label(hint) == "?" and str(hint["hint"]) != "", "Calor + Pulso: pista «?»")
	var unk: Dictionary = s.get_atlas_cell("sombra", "luz")
	check(unk["state"] == PS.CELL_UNKNOWN and PS.cell_label(unk) == "???", "Sombra + Luz: desconocida «???»")
	check(s.get_atlas_cell("vacio", "calor")["count"] == 1, "Vacío + Calor: 1 (Grieta ígnea aún no descubierta)")
	check(s.get_atlas_cell("eco", "pulso", "control")["count"] == 1 and s.get_atlas_cell("eco", "pulso", "dano")["count"] == 1, "Filtro por rol")
	var st: Dictionary = s.get_atlas_stats()
	check(st["pairs_total"] == 55, "55 parejas con 10 energías (N(N+1)/2)")
	check(st["pairs_discovered"] == 24 and st["formulas_known"] == 43, "24 parejas descubiertas · 43 fórmulas")
	var det: Dictionary = s.get_pair_details("pulso", "eco")
	check(det["formulas"].size() == 2 and det["untested_forms"] == 3, "Detalle: 2 fórmulas y 3 formas sin probar")
	check(det["thirds"][0]["energy"] == "hierro" and det["thirds"][0]["name"] == "Campana de guerra", "+ Hierro: Campana de guerra ✓")
	check(det["thirds"][1]["energy"] == "vacio" and det["thirds"][1]["state"] == PS.CELL_HINT and det["thirds"][1]["hint"] == "silencio que rompe", "+ Vacío: pista «silencio que rompe»")
	check(det["thirds"][2]["state"] == PS.CELL_UNKNOWN and det["thirds"].size() == 4, "Resto: sin descubrir (máx. 4 filas)")
	s.discover_power(s.compose_power(["sombra", "luz"], "cono", "retardado"))
	check(s.get_atlas_cell("luz", "sombra")["state"] == PS.CELL_DISCOVERED and s.get_atlas_cell("luz", "sombra")["count"] == 1, "Descubrir actualiza la celda")
	var grown := [0]
	s.energies_changed.connect(func() -> void: grown[0] += 1)
	check(s.add_energy("cristal", "Cristal", Color("#9ef0ff")) and grown[0] == 1, "Añadir energía nueva (temporada)")
	check(not s.add_energy("cristal", "Cristal", Color.WHITE), "No se duplica una energía")
	m = s.get_atlas_matrix()
	check(m.size() == 11 and (m[10] as Array).size() == 11, "El Atlas crece solo: 11 × 11")
	check(s.get_atlas_stats()["pairs_total"] == 66, "66 parejas con 11 energías")
	check(s.get_atlas_cell("cristal", "vacio")["state"] == PS.CELL_UNKNOWN, "Celdas nuevas empiezan «???»")
	check(s.compose_power(["cristal", "vacio"], "aura", "canalizado")["ok"], "El Crisol acepta la energía nueva")
	s.free()


# --------------------------------------------------------------------------
func _test_constellation_service() -> void:
	print("-- Constelación de clase")
	var s: Node = PS.new()
	check(s.class_title == "Tejedor" and s.nodes.size() == 14, "Constelación del Tejedor con 14 nodos")
	var branches := {}
	for b in s.branches:
		branches[b["energy"]] = true
	check(branches.has("vacio") and branches.has("pulso") and branches.has("eco"), "Ramas: Vacío, Pulso y Eco")
	check(s.get_spent_points() == 30 and s.get_available_points() == 10 and s.total_points == 40, "30 de 40 puntos gastados")
	check(s.get_node_state("v1") == PS.NODE_ACTIVE and s.get_node_state("p2") == PS.NODE_AVAILABLE and s.get_node_state("p_key") == PS.NODE_LOCKED, "Estados: activo, disponible y bloqueado")
	check(s.get_star("v_key")["keystone"], "Piedra angular marcada")
	check(s.node_description("v1") == "Los poderes con Vacío explotan al terminar e infligen 12 % de su daño alrededor.", "Descripción con valor del rango actual")
	var affected: Array = s.get_node_affected_powers("v1")
	check(affected.has("Haz de grieta") and affected.has("Corte de fase") and affected.has("Colapso dimensional") and not affected.has("Muro de ceniza"), "Nodo de Vacío afecta solo a poderes con Vacío")
	check(s.get_node_affected_powers("raiz").size() == s.get_loadout_keys(true).size(), "Nodo raíz afecta a todo el conjunto")
	var grieta := ["vacio", "calor"]
	var pot_before: int = s.compute_potency(grieta)["potency"]
	var dps_before: int = s.simulate_dps()
	var dps_pred: int = s.simulate_dps("v1")
	check(dps_pred > dps_before and s.simulate_dps() == dps_before, "Simulación «con este punto» no modifica el árbol")
	var r: Dictionary = s.allocate_point("v1")
	check(r["ok"] and r["rank"] == 3 and s.get_available_points() == 7, "Asignar punto: v1 rango 3 (coste 3)")
	check(s.get_constellation_bonus("vacio") == 18.0, "Rama del Vacío: +18 %")
	check(s.compute_potency(grieta)["potency"] > pot_before, "La Constelación sube la potencia de los poderes del Crisol con Vacío")
	check(s.simulate_dps() == dps_pred, "DPS real = DPS previsto")
	check(s.compute_potency(["eco", "pulso"])["potency"] == roundi(8 * 3 * 1.17 + 7 * 3 * 1.12), "Poderes sin Vacío no cambian")
	check(s.allocate_point("v1")["reason"] == "max_rank", "Rango máximo")
	check(s.allocate_point("p_key")["reason"] == "locked", "Nodo bloqueado")
	check(s.allocate_point("nada")["reason"] == "unknown_node", "Nodo desconocido")
	check(s.allocate_point("e3")["ok"] and s.get_node_state("e_key") == PS.NODE_AVAILABLE, "Desbloquea la piedra angular del Eco")
	check(s.allocate_point("e_key")["ok"] and s.get_available_points() == 1, "Piedra angular asignada (coste 4)")
	check(s.allocate_point("p2")["reason"] == "not_enough_points", "Sin puntos suficientes")
	check(s.refund_point("v2")["reason"] == "has_dependents", "No se puede dejar huérfano a un hijo")
	check(s.refund_point("p2")["reason"] == "no_rank", "No se reembolsa un nodo a 0")
	check(s.refund_point("e_key")["ok"] and s.get_available_points() == 5, "Reembolso de punto")
	check(s.history.size() == 4 and s.undo_last() and s.get_star("e_key")["rank"] == 1, "Deshacer (Ctrl Z) revierte el último cambio")
	s.free()


# --------------------------------------------------------------------------
func _make_window() -> Node:
	var w = PowersScene.instantiate()
	check(w.get_script() == PowersScript, "PowersWindow.tscn carga su script")
	w.service = PS.new()
	root.add_child(w)
	return w


func _test_powers_window_crisol() -> void:
	print("-- Ventana de Poderes · Crisol")
	var w = _make_window()
	await process_frame
	check(w.window_id == "powers" and w.menu_bar.active_tab == "poderes", "window_id «powers» y pestaña Poderes activa")
	check(w.get_subtab_ids() == ["crisol", "atlas", "constelacion", "afinidades"], "4 sub-ventanas")
	check(w.current_subtab == "crisol" and w.pages["crisol"].visible and not w.pages["atlas"].visible, "Abre en el Crisol")
	check(w.energy_rows.size() == 10, "Lista con las 10 energías")
	check(w.energy_list.get_child(0).name == "Energy_vacio", "Ordenadas por afinidad (Vacío primero)")
	w.energy_search.text_changed.emit("ma")
	check(w.energy_rows.size() == 1 and w.energy_rows.has("marea"), "Buscador filtra la lista")
	w.energy_search.text_changed.emit("")
	w.set_energy_sort("az")
	check(w.energy_list.get_child(0).name == "Energy_calor", "Orden A–Z")
	check(w.result_name.text == "Crisol vacío" and w.dummy_button.disabled and w.equip_button.disabled, "Crisol vacío: acciones desactivadas")
	var composed := []
	w.power_composed.connect(func(p: Dictionary) -> void: composed.append(p))
	w.energy_rows["vacio"].pressed.emit()
	check(w.get_mixer_energies() == ["vacio"] and w.result_name.text == "Falta una energía", "1 energía: falta otra")
	check(w.energy_rows["vacio"].get_meta("in_crucible"), "Energía en el crisol resaltada")
	w.energy_rows["calor"].pressed.emit()
	w.form_buttons["area"].pressed.emit()
	w.rhythm_buttons["canalizado"].pressed.emit()
	check(w.result_name.text == "Grieta ígnea" and w.new_badge.visible, "2 energías + Área + Canalizado: Grieta ígnea ¡NUEVA!")
	check(w.form_buttons["area"].button_pressed and not w.form_buttons["cono"].button_pressed, "Forma seleccionada marcada")
	check(w.rhythm_buttons["canalizado"].button_pressed, "Ritmo seleccionado marcado")
	check(w.result_potency.text.contains("Vacío 14 + Calor 9"), "Potencia con afinidades")
	check(w.crisol_subtitle.text.contains("tu Constelación suma +12 % al Vacío"), "Cabecera: bonus de la Constelación")
	check(not composed.is_empty() and composed[-1]["name"] == "Grieta ígnea", "Señal power_composed")
	check(w.hint_label.text.begins_with("Pista: ") and w.hint_count_label.text == "11 pistas sin probar", "Pista de PNJ y contador")
	check(w.equip_button.text == "Equipar en la ranura 3" and not w.equip_button.disabled, "«Equipar en la ranura 3»")
	check(w.resonance_label.text.contains("Vacío aparece en 4 poderes: +8 %"), "Resonancia del conjunto visible")
	check(w.core_card.get_node("Row/Info/Name").text == "Colapso dimensional" and w.active_cards[0].get_node("Row/Info/Name").text == "Haz de grieta", "Núcleo y activos visibles")
	check(w.echo_cards[0].get_node("Text").text == "Armonía del vacío" and w.echo_cards[1].get_node("Text").text == "+ vacío", "Ecos pasivos visibles")
	w.set_form("cono")
	check(w.result_name.text != "Grieta ígnea" and w.get_current_power()["form"] == "cono", "Cambiar forma cambia el poder")
	check(not w.set_form("esfera") and not w.set_rhythm("lento"), "Forma/ritmo inválidos rechazados en la UI")
	w.set_form("area")
	var tested := [false]
	w.dummy_tested.connect(func(_p: Dictionary, r: Dictionary) -> void: tested[0] = r["ok"])
	w.dummy_button.pressed.emit()
	await process_frame
	check(tested[0] and not w.new_badge.visible and w.status_label.text.contains("Maniquí"), "«Probar en el maniquí» descubre la combinación")
	check(w.add_energy_to_crucible("eco") and w.get_mixer_energies().size() == 3, "3.ª energía opcional")
	check(not w.add_energy_to_crucible("runa"), "Máximo 3 energías")
	check(w.get_current_power()["ok"] and w.get_current_power()["energies"].size() == 3, "Poder de 3 energías válido")
	w.crucible_view.slot_clicked.emit(2)
	check(w.get_mixer_energies() == ["vacio", "calor"], "Clic en un orbe lo quita del crisol")
	w.equip_button.pressed.emit()
	await process_frame
	check(w.service.active_slots[2] == w.get_current_power()["key"] and w.equip_button.text == "Equipado", "Equipado en la ranura 3")
	check(w.resonance_label.text.contains("«Eco del abismo» activo"), "Resonancia: Eco del abismo activo")
	w.clear_button.pressed.emit()
	check(w.get_mixer_energies().is_empty(), "«Vaciar crisol»")
	w.set_crucible(["vacio", "vacio"], "proyectil", "instantaneo")
	check(w.result_name.text == "Haz de grieta" and not w.new_badge.visible, "Energía pura (Vacío + Vacío)")
	w.queue_free()
	await process_frame


func _test_powers_window_atlas() -> void:
	print("-- Ventana de Poderes · Atlas")
	var w = _make_window()
	await process_frame
	w.select_subtab("atlas")
	check(w.pages["atlas"].visible and not w.pages["crisol"].visible, "Sub-ventana Atlas visible")
	check(w.atlas_grid.columns == 11, "Rejilla: cabecera + 10 columnas")
	check(w.atlas_cells.size() == 55, "55 celdas (triángulo superior con diagonal)")
	check(w.atlas_stats_label.text == "24 de 55 parejas · 43 fórmulas conocidas", "Resumen del Atlas")
	var c_pure = w.get_atlas_cell_button("vacio", "vacio")
	check(c_pure.get_state() == "discovered" and c_pure.get_cell_text() == "2" and c_pure.cell["pure"], "Celda diagonal: pura con 2")
	var c_disc = w.get_atlas_cell_button("pulso", "eco")
	check(c_disc.get_cell_text() == "2" and c_disc.selected, "Pulso × Eco descubierta y seleccionada")
	var c_hint = w.get_atlas_cell_button("calor", "pulso")
	check(c_hint.get_state() == "hint" and c_hint.get_cell_text() == "?" and c_hint.tooltip_text.begins_with("Pista"), "Celda pista «?»")
	var c_unk = w.get_atlas_cell_button("sombra", "luz")
	check(c_unk.get_state() == "unknown" and c_unk.get_cell_text() == "???", "Celda desconocida «???»")
	check(w.get_atlas_cell_button("luz", "sombra") == c_unk, "Celda simétrica")
	var texts := _all_texts(w.pages["atlas"])
	check(texts.contains("Resonancia sónica") and texts.contains("Latido en cadena"), "Fórmulas conocidas de la pareja")
	check(texts.contains("Campana de guerra ✓") and texts.contains("pista: «silencio que rompe»") and texts.contains("sin descubrir"), "Con una tercera energía: ✓ / pista / sin descubrir")
	check(texts.contains("3 formas más sin probar"), "Formas sin probar")
	var sel := []
	w.atlas_pair_selected.connect(func(a: String, b: String) -> void: sel.append(a + "+" + b))
	w.get_atlas_cell_button("vacio", "calor").pressed.emit()
	check(sel == ["vacio+calor"] and w.get_atlas_cell_button("vacio", "calor").selected and not c_disc.selected, "Clic en celda selecciona la pareja")
	w.set_atlas_role("curacion")
	check(w.get_atlas_cell_button("eco", "pulso").get_state() == "unknown" and w.get_atlas_cell_button("savia", "savia").get_cell_text() == "3", "Filtro de rol (Curación)")
	w.set_atlas_role("")
	w.select_atlas_pair("eco", "pulso")
	w.selected_form = "cono"
	w.selected_rhythm = "instantaneo"
	w.bring_button.pressed.emit()
	check(w.current_subtab == "crisol" and w.pages["crisol"].visible, "«Llevar al Crisol» abre el Crisol")
	check(w.get_mixer_energies() == ["eco", "pulso"] and w.result_name.text == "Resonancia sónica", "La pareja se carga en el mezclador")
	w.select_subtab("atlas")
	w.select_atlas_pair("runa", "runa")
	w.bring_to_crucible()
	check(w.get_mixer_energies() == ["runa", "runa"], "Pareja pura -> la misma energía dos veces")
	w.service.add_energy("cristal", "Cristal", Color("#9ef0ff"))
	await process_frame
	await process_frame
	check(w.atlas_grid.columns == 12 and w.atlas_cells.size() == 66, "Energía nueva: +1 fila y +1 columna (66 celdas)")
	check(w.get_atlas_cell_button("cristal", "cristal").get_cell_text() == "???" and w.energy_rows.has("cristal"), "La energía nueva aparece en Atlas y Crisol")
	check(w.affinity_rows.has("cristal"), "…y en Afinidades")
	w.queue_free()
	await process_frame


func _test_powers_window_constellation_and_affinities() -> void:
	print("-- Ventana de Poderes · Constelación y Afinidades")
	var w = _make_window()
	await process_frame
	w.select_subtab("constelacion")
	check(w.pages["constelacion"].visible, "Sub-ventana Constelación visible")
	check(w.points_label.text == "30 / 40", "Puntos 30 / 40")
	check(w.node_title.text == "Resonancia de grieta" and w.node_rank_label.text.begins_with("Rango 2 de 3 · Rama del Vacío · coste 3"), "Nodo seleccionado con rango, rama y coste")
	check(w.node_desc.text.contains("12 %"), "Descripción del beneficio")
	check(w.node_affects_title.text == "Afecta a 5 poderes de tu Crisol" and _all_texts(w.node_affects_box).contains("Corte de fase"), "Lista de poderes del Crisol a los que potencia")
	check(w.node_next_label.text.contains("12 → 18"), "Siguiente rango 12 → 18")
	check(w.sim_delta_label.text.begins_with("+") and w.sim_with_label.text.begins_with("Con este punto"), "Simulación contra maniquí")
	var pot_before: int = w.service.compose_power(["vacio", "calor"], "area", "canalizado")["potency"]
	var got := []
	w.point_assigned.connect(func(id: String, r: Dictionary) -> void: got.append([id, r["ok"]]))
	w.assign_button.pressed.emit()
	check(got == [["v1", true]] and w.points_label.text == "33 / 40" and w.node_title.text == "Resonancia de grieta", "Asignar punto desde la UI")
	check(w.service.compose_power(["vacio", "calor"], "area", "canalizado")["potency"] > pot_before, "Impacto en la potencia del Crisol")
	check(w.assign_button.disabled and w.node_next_label.text == "Rango máximo alcanzado", "Rango máximo: botón desactivado")
	w.select_node("p_key")
	check(w.assign_button.disabled and w.node_title.text == "Corazón del reloj", "Nodo bloqueado no se puede asignar")
	w.tree_view.node_clicked.emit("e1")
	check(w.selected_node == "e1" and w.node_affects_title.text.begins_with("Afecta a 3"), "Clic en nodo del árbol (Eco)")
	w.tree_view.size = Vector2(500, 420)
	var pos: Vector2 = w.tree_view.node_pos(w.service.get_star("v2"))
	check(w.tree_view.node_at(pos) == "v2" and w.tree_view.node_at(Vector2(2, 2)) == "", "Hit-test de nodos")
	w.side_button.pressed.emit()
	check(w.is_side_by_side() and w.get_visible_subtabs() == ["constelacion", "crisol"], "«Abrir Crisol al lado»: dos sub-ventanas a la vez")
	check(w.subnav_buttons["crisol"].button_pressed and w.subnav_buttons["constelacion"].button_pressed, "Ambas pestañas marcadas")
	check(not w._crisol_loadout_col.visible and w.crucible_view.is_visible_in_tree(), "Crisol compacto al lado")
	w.set_crucible(["vacio", "eco"], "aura", "instantaneo")
	w.select_node("v1")
	check(w.result_name.text == "Paso del eco" and w.node_affects_title.text.begins_with("Afecta a"), "Inspección simultánea Crisol + nodo")
	w.side_button.pressed.emit()
	check(not w.is_side_by_side() and w.get_visible_subtabs() == ["constelacion"], "Cerrar el Crisol lateral")
	w.select_subtab("afinidades")
	check(w.pages["afinidades"].visible and w.affinity_rows.size() == 10, "Afinidades: 10 barras")
	var row: Dictionary = w.affinity_rows["vacio"]
	check(row["level"].text == "nv 14" and absf(row["bar"].ratio - 0.6) < 0.01, "Vacío nv 14 al 60 %")
	check(row["xp"].text == "840 / 1.400 PX hasta nv 15", "Texto de PX hasta el siguiente nivel")
	check(w.affinity_top_label.text == "Mayor afinidad: Vacío (nv 14)", "Mayor afinidad")
	w.service.record_combat_use(["luz", "sombra"], 150)
	await process_frame
	await process_frame
	check(w.affinity_rows["luz"]["level"].text == "nv 2" and w.affinity_rows["sombra"]["level"].text == "nv 2", "El uso en combate sube las barras")
	w.queue_free()
	await process_frame


# --------------------------------------------------------------------------
func _new_ks() -> Node:
	var ks: Node = KS.new()
	ks.clock_override = T0
	ks.wiki_sync_enabled = false
	return ks


func _test_offer_service() -> void:
	print("-- KnowledgeService: oferta del pionero")
	var ks := _new_ks()
	var offer: Dictionary = OfferScript.DEFAULT_OFFER.duplicate(true)
	var log := []
	ks.pioneer_offer_resolved.connect(func(id: String, d: String, _r: Dictionary) -> void: log.append(d + ":" + id))
	var r: Dictionary = ks.defer_pioneer_offer(offer)
	check(r["ok"] and r["expires_in_days"] == 7 and ks.get_offer(offer["id"])["expires_in_days"] == 7, "Pensarlo: guardada 7 días")
	check(ks.get_offer(offer["id"])["name"] == "Puesto de Gildas" and ks.get_offer(offer["id"])["mission_steps"] == 2, "Oferta guardada con nombre y pasos")
	ks.advance_day()
	ks.advance_day()
	check(ks.defer_pioneer_offer(offer)["expires_in_days"] == 5, "Volver a pensarlo no reinicia el plazo")
	for i in 5:
		ks.advance_day()
	check(ks.get_offer(offer["id"]).is_empty(), "A los 7 días la oferta caduca")
	r = ks.accept_pioneer_offer(offer)
	check(r["ok"] and r["investment_id"] == "inv_gildas" and r["mission_steps"] == 2, "Aceptar: inicia la misión especial")
	var inv: Dictionary = ks.get_investment("inv_gildas")
	check(inv["status"] == "mission" and is_equal_approx(inv["share"], 0.02) and not ks.is_investment_earning(inv), "Contrato en misión: aún no cobra")
	check(ks.record_transaction("inv_gildas", 10000) == 0, "Sin socio activo no hay comisión")
	check(ks.accept_pioneer_offer(offer)["reason"] == "post_has_partner" and ks.defer_pioneer_offer(offer)["reason"] == "post_has_partner", "Un solo socio por puesto")
	check(ks.advance_offer_mission("inv_gildas")["completed"] == false and ks.advance_offer_mission("inv_gildas")["completed"], "Completar los 2 pasos de la misión")
	check(ks.get_investment("inv_gildas")["status"] == "active" and ks.advance_offer_mission("inv_gildas")["reason"] == "not_in_mission", "Socio activo")
	check(ks.record_transaction("inv_gildas", 10000) == 200, "Socio: 2 % de cada transacción (10.000 -> 200)")
	var other: Dictionary = offer.duplicate(true)
	other["id"] = "offer_torin"
	other["npc_id"] = "pnj_torin"
	ks.defer_pioneer_offer(other)
	r = ks.reject_pioneer_offer(other, "Nadia")
	check(r["ok"] and r["passed_to"] == "Nadia" and ks.get_offer("offer_torin").is_empty(), "Rechazar: pasa al siguiente descubridor")
	check(ks.passed_offers.size() == 1 and ks.passed_offers[0]["npc_id"] == "pnj_torin", "Registro de ofertas pasadas")
	check(ks.accept_pioneer_offer({})["reason"] == "invalid_offer", "Oferta inválida")
	check(log == ["defer:offer_gildas_vado", "defer:offer_gildas_vado", "accept:offer_gildas_vado", "defer:offer_torin", "reject:offer_torin"], "Señal pioneer_offer_resolved")
	ks.free()


func _make_offer(ks: Node) -> Node:
	var m = OfferScene.instantiate()
	check(m.get_script() == OfferScript, "PioneerOfferModal.tscn carga su script")
	m.service = ks
	root.add_child(m)
	return m


func _test_offer_modal() -> void:
	print("-- Modal de oferta de inversión")
	var ks := _new_ks()
	var m = _make_offer(ks)
	await process_frame
	check(m.window_id == "pioneer_offer" and m.is_inside_tree(), "Modal instanciado")
	check(m.npc_name_label.text == "Gildas" and m.npc_role_label.text == "Mercader del Vado" and m.pioneer_badge.visible, "PNJ y «Eres su pionero»")
	check(m.offer_title_label.text == "Socio del puesto de Gildas", "Título de la oferta")
	check(m.share_label.text == "2 %" and is_equal_approx(m.get_share_percent(), 2.0), "Cuota de socio 2 %")
	check(OfferScript.share_text(0.015) == "1,5 %" and OfferScript.share_text(0.03) == "3 %", "Formato de cuota")
	check(m.estimate_label.text == "300–900", "Estimado hoy 300–900")
	var steps := _all_texts(m.mission_steps_box)
	check(steps.contains("Paso 1: Provee 5 Cristales de Vacío") and steps.contains("0/5"), "Paso 1 de la misión")
	check(steps.contains("Paso 2: Asegura la ruta comercial") and steps.contains("2.000 oro"), "Paso 2 y cuota de socio")
	check(m.mission_name_label.text == "Ruta de suministro", "Nombre de la misión especial")
	var cond := _all_texts(m.conditions_box)
	check(m.conditions_box.get_child_count() == 4, "4 condiciones visibles")
	check(cond.contains("almacén de tu refugio") and cond.contains("no estés conectado"), "Condición: cobra sin conexión (almacén del refugio)")
	check(cond.contains("vender tu participación"), "Condición: participación vendible")
	check(cond.contains("se pausa"), "Condición: pausa si la tienda cierra")
	check(cond.contains("Solo hay un socio por puesto"), "Condición: un solo socio por puesto")
	check(_all_texts(m.accept_button).contains("Trato hecho") and _all_texts(m.accept_button).contains("Acepta la misión especial"), "Botón 1: Aceptar Misión")
	check(_all_texts(m.defer_button).contains("Déjame pensarlo") and _all_texts(m.defer_button).contains("7 días"), "Botón 2: Pensarlo (7 días)")
	check(_all_texts(m.reject_button).contains("No me interesa") and _all_texts(m.reject_button).contains("siguiente"), "Botón 3: Rechazar")
	var decided := []
	m.offer_decided.connect(func(d: String, r: Dictionary) -> void: decided.append([d, r["ok"]]))
	m.accept_button.pressed.emit()
	check(decided == [["accept", true]] and ks.get_investment("inv_gildas")["status"] == "mission", "Aceptar Misión -> contrato en misión")
	check(m.accept_button.disabled and m.defer_button.disabled and m.reject_button.disabled, "Tras decidir, botones desactivados")
	check(m.status_label.text.contains("Ruta de suministro"), "Mensaje de misión iniciada")
	m.set_offer(OfferScript.DEFAULT_OFFER)
	check(not m.accept_button.disabled, "Nueva oferta reactiva los botones")
	var r: Dictionary = m.accept_offer()
	check(not r["ok"] and m.status_label.text.contains("solo hay uno por puesto"), "Mismo puesto: ya tiene socio")
	m.set_offer({"id": "offer_torin", "npc_id": "pnj_torin", "npc_name": "Torin", "npc_role": "Herrero de Ferrum", "shop_name": "Forja de Torin", "share": 0.015, "next_discoverer": "Nadia"})
	check(m.offer_title_label.text == "Socio del puesto de Torin" and m.share_label.text == "1,5 %", "Oferta de Torin (1,5 %)")
	m._unhandled_key_input(_key(KEY_2))
	check(m.last_decision == "defer" and ks.get_offer("offer_torin")["expires_in_days"] == 7, "Tecla [2]: Pensarlo 7 días")
	check(m.status_label.text.contains("7 días en Códice › Inversiones"), "Mensaje de oferta guardada")
	m.set_offer(ks.get_offer("offer_torin"))
	m.reject_button.pressed.emit()
	check(m.last_decision == "reject" and m.last_result["passed_to"] == "Nadia" and ks.get_offer("offer_torin").is_empty(), "Rechazar -> pasa a Nadia")
	m.initialize_window({"offer": {"id": "offer_ysel2", "npc_id": "pnj_ysel2", "npc_name": "Ysel"}})
	check(m.npc_name_label.text == "Ysel" and m.share_label.text == "2 %", "initialize_window carga la oferta")
	m.queue_free()
	await process_frame
	ks.free()


func _test_offer_defer_in_codex() -> void:
	print("-- «Pensarlo» aparece en Códice › Inversiones")
	var ks := _new_ks()
	ks.defer_pioneer_offer(OfferScript.DEFAULT_OFFER)
	var codex = CodexScene.instantiate()
	codex.service = ks
	root.add_child(codex)
	await process_frame
	codex.select_subtab("inversiones")
	await process_frame
	check(_all_texts(codex.offers_box).contains("Puesto de Gildas") and _all_texts(codex.offers_box).contains("expira en 7 días"), "Oferta guardada visible en Inversiones (7 días)")
	codex.queue_free()
	ks.queue_free()
	await process_frame
