extends SceneTree
## Suite headless (UI v2.4 Paso 14): Antesala y Resumen de mazmorra.
## Run: Godot --headless --path clients/godot-mmo-client -s tests/unit/test_dungeon_lobby_and_summary.gd
## Exit code 0 = todo PASS.

const LS = preload("res://shared-core/DungeonLobbyService.gd")
const SS = preload("res://shared-core/DungeonSummaryService.gd")
const LobbyScene = preload("res://ui/windows/DungeonLobbyWindow/DungeonLobbyWindow.tscn")
const SummaryScene = preload("res://ui/windows/DungeonSummaryWindow/DungeonSummaryWindow.tscn")
const LobbyWindowConst = preload("res://ui/windows/DungeonLobbyWindow/DungeonLobbyWindow.gd")
const SummaryWindowConst = preload("res://ui/windows/DungeonSummaryWindow/DungeonSummaryWindow.gd")
const T = preload("res://ui/tokens/hud_tokens.gd")
const LOBBY_SEED := "res://config/dungeons/dungeon_lobby_seed.json"
const SUMMARY_SEED := "res://config/dungeons/dungeon_summary_seed.json"

const MIN_CHECKS := 200

var _fails: Array[String] = []
var _checks := 0


func check(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_fails.append(msg)
		printerr("  FAIL: ", msg)
	else:
		print("  PASS: ", msg)


func near(a: float, b: float, eps: float = 0.01) -> bool:
	return absf(a - b) <= eps


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("== [TEST] Paso 14: Antesala y Resumen de mazmorra ==")
	_test_registry()
	await _test_orchestrator()
	_test_lobby_seed()
	_test_lobby_ready_and_countdown()
	_test_lobby_sets()
	_test_lobby_entry_and_extras()
	_test_summary_seed()
	_test_summary_loot()
	_test_summary_moments()
	_test_summary_progress()
	_test_summary_exits_and_present()
	await _test_lobby_window()
	await _test_summary_window()
	check(_checks >= MIN_CHECKS, "Se ejecutaron todas las comprobaciones (%d >= %d)" % [_checks, MIN_CHECKS])
	print("== %d checks, %d fallos ==" % [_checks, _fails.size()])
	if _fails.is_empty():
		print("RESULTADO: 100% PASS (ExitCode 0)")
		quit(0)
	else:
		for f in _fails:
			printerr("  - ", f)
		quit(1)


# --------------------------------------------------------------------------
# Utilidades
# --------------------------------------------------------------------------
func _frames(n: int = 2) -> void:
	for i in n:
		await process_frame


func _ls() -> Node:
	var s: Node = LS.new()
	s.load_seed(LOBBY_SEED)
	s.auto_tick = false
	return s


func _ss() -> Node:
	var s: Node = SS.new()
	s.load_seed(SUMMARY_SEED)
	return s


func _close_color(a: Color, b: Color) -> bool:
	return near(a.r, b.r) and near(a.g, b.g) and near(a.b, b.b) and near(a.a, b.a)


func _key(code: int) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	return ev


func _text(n: Node, child: String) -> String:
	var c := n.find_child(child, true, false)
	if c is Label:
		return (c as Label).text
	if c is Button:
		return (c as Button).text
	return ""


# --------------------------------------------------------------------------
# 1. Registro de ventanas y autoloads
# --------------------------------------------------------------------------
func _test_registry() -> void:
	print("-- 1. UIWindowRegistry y autoloads")
	var Registry = load("res://ui/orchestration/UIWindowRegistry.gd")
	var UITypes = load("res://ui/types/UITypes.gd")
	var reg: Node = Registry.new()
	var expected := [
		["dungeon_lobby", "res://ui/windows/DungeonLobbyWindow/DungeonLobbyWindow.tscn", UITypes.WindowCategory.MODAL_OVERLAY, "MODAL_OVERLAY"],
		["dungeon_summary", "res://ui/windows/DungeonSummaryWindow/DungeonSummaryWindow.tscn", UITypes.WindowCategory.GAME_WINDOW, "GAME_WINDOW"],
	]
	for e in expected:
		var id: String = e[0]
		check(reg.is_registered(id), "Registrada: " + id)
		var meta = reg.get_metadata(id)
		check(meta != null and meta.scene_path == e[1], "%s -> %s" % [id, e[1]])
		check(meta != null and ResourceLoader.exists(meta.scene_path), "La escena de %s existe" % id)
		check(meta != null and meta.category == e[2], "%s es %s" % [id, e[3]])
		check(reg.get_shortcut_keys(id).is_empty(), "%s no roba atajos globales" % id)
	check(reg.get_window_for_key(KEY_H) == "shelter" and reg.is_registered("shelter_pocket"), "H sigue en Refugio y existe el refugio de bolsillo")
	reg.free()
	check(str(ProjectSettings.get_setting("autoload/DungeonLobbyService", "")) == "*res://shared-core/DungeonLobbyService.gd", "Autoload DungeonLobbyService registrado")
	check(str(ProjectSettings.get_setting("autoload/DungeonSummaryService", "")) == "*res://shared-core/DungeonSummaryService.gd", "Autoload DungeonSummaryService registrado")
	var al := root.get_node_or_null("DungeonLobbyService")
	check(al != null and al.members.size() == 5, "Autoload DungeonLobbyService cargó su seed (5 integrantes)")
	var asv := root.get_node_or_null("DungeonSummaryService")
	check(asv != null and asv.loot.size() == 3, "Autoload DungeonSummaryService cargó su seed (3 botines)")
	var mirror := ProjectSettings.globalize_path("res://").path_join("../shared-core")
	for f in ["DungeonLobbyService.gd", "DungeonSummaryService.gd"]:
		var a := FileAccess.get_file_as_string("res://shared-core/" + f)
		var b := FileAccess.get_file_as_string(mirror.path_join(f))
		check(a != "" and a == b, "clients/shared-core/%s sincronizado con el cliente" % f)
	check(FileAccess.file_exists(LOBBY_SEED) and FileAccess.file_exists(SUMMARY_SEED), "Seeds de antesala y resumen presentes")
	check(T.CINEMA_DESIGN_SIZE == Vector2(1440, 810) and T.DUNGEON_TITLE_SIZE == 34, "Tokens: lienzo 1440×810 y título de 34 px")
	check(T.DUNGEON_COLUMN_HEIGHT == 600.0 and T.DUNGEON_PRAISED == Color("#4fe39a") and T.DUNGEON_REPEAT == Color("#46e3c1"), "Tokens: columnas de 600 px, elogio #4fe39a, repetir #46e3c1")


func _test_orchestrator() -> void:
	print("-- 2. UIOrchestrator.open_dungeon_lobby / open_dungeon_summary")
	var orch := root.get_node_or_null("UIOrchestrator")
	check(orch != null, "Autoload UIOrchestrator presente")
	if orch == null:
		return
	check(orch.has_method("open_dungeon_lobby") and orch.has_method("open_dungeon_summary"), "UIOrchestrator expone open_dungeon_lobby y open_dungeon_summary")
	var al: Node = root.get_node("DungeonLobbyService")
	al.auto_tick = false
	var w = orch.open_dungeon_lobby()
	await _frames(2)
	check(w != null and w.window_id == "dungeon_lobby", "open_dungeon_lobby() instancia DungeonLobbyWindow")
	check(w != null and w.service == al, "DungeonLobbyWindow usa el autoload DungeonLobbyService")
	check(w != null and al.dungeon_id == "ferrum_vault" and w.title_label_main.text == "Bóveda de Ferrum · Heroica", "Por defecto: Bóveda de Ferrum · Heroica")
	check(w != null and w.visible and w.get_parent() == orch.window_layer, "Visible en la capa de ventanas")
	w = orch.open_dungeon_lobby("vado_hundido")
	await _frames(1)
	check(al.dungeon_id == "vado_hundido" and w.title_label_main.text == "Vado hundido · Normal", "open_dungeon_lobby(\"vado_hundido\") cambia de mazmorra")
	check(w.player_cards.size() == 5, "Se conserva el grupo de 5")
	w.handle_key(KEY_ESCAPE)
	await _frames(1)
	check(not w.visible and w.close_reason == "hidden", "Esc oculta la antesala")
	al.reset()

	var asv: Node = root.get_node("DungeonSummaryService")
	var s = orch.open_dungeon_summary()
	await _frames(2)
	check(s != null and s.window_id == "dungeon_summary", "open_dungeon_summary() instancia DungeonSummaryWindow")
	check(s != null and s.service == asv, "DungeonSummaryWindow usa el autoload DungeonSummaryService")
	check(s != null and s.loot_rows.size() == 3 and s.moment_rows.size() == 5, "Sin datos: resumen del seed (3 botines, 5 momentos)")
	s = orch.open_dungeon_summary({"completion_s": 2400, "progress": {"xp_gained": 9000}})
	await _frames(1)
	check(asv.completion_text() == "40:00" and not s.record_chip.visible, "open_dungeon_summary(datos): 40:00 y sin récord")
	check(s.xp_label.text == "+9.000 XP" and asv.level() == 32, "Los datos parciales de progreso se fusionan con el seed")
	# Repetir enruta a la antesala a través del orquestador.
	s.choose_exit(SS.EXIT_REPEAT)
	await _frames(2)
	var lobby = orch.registry.get_instance("dungeon_lobby")
	check(not s.visible and s.close_reason == "repeat", "Repetir cierra el resumen")
	check(lobby != null and lobby.visible and al.dungeon_id == "ferrum_vault", "Repetir abre la antesala de la misma mazmorra")
	lobby.handle_key(KEY_ESCAPE)
	asv.reset()
	al.reset()
	await _frames(1)


# --------------------------------------------------------------------------
# 3. DungeonLobbyService: seed
# --------------------------------------------------------------------------
func _test_lobby_seed() -> void:
	print("-- 3. DungeonLobbyService: seed y tarjetas")
	var s := _ls()
	check(s.title_text() == "Bóveda de Ferrum · Heroica", "Título «Bóveda de Ferrum · Heroica»")
	check(s.members.size() == 5, "5 integrantes")
	check(s.members.map(func(m): return m["name"]) == ["Toro", "Brisa", "Kael", "Nox", "Vela"], "Toro, Brisa, Kael, Nox y Vela")
	check(s.local_player == "kael" and s.is_leader() and s.is_local("kael"), "Kael es el jugador local y el líder")
	check(s.display_name(s.get_member("kael")) == "Kael (tú)" and s.display_name(s.get_member("toro")) == "Toro", "«Kael (tú)»")
	check(s.role_line(s.get_member("toro")) == "Tanque · 418", "Toro: Tanque · 418")
	check(s.role_line(s.get_member("brisa")) == "Sanadora · 414", "Brisa: Sanadora · 414")
	check(s.role_line(s.get_member("kael")) == "Daño · 412", "Kael: Daño · 412")
	check(s.role_line(s.get_member("nox")) == "Daño · 405" and s.role_line(s.get_member("vela")) == "Daño · 409", "Nox 405 y Vela 409")
	check(s.role_color("tank") == "#5aa9ff" and s.role_color("healer") == "#4fe39a" and s.role_color("dps") == "#ff9a4d", "Colores de rol del HTML")
	check(s.get_member("toro")["archetype"] == "Guardián" and s.get_member("kael")["archetype"] == "Lancero", "Arquetipos de clase")
	check(s.get_member("toro")["avatar_body"] == "#2b4a8a" and s.get_member("brisa")["avatar_hair"] == "#c97b4a", "Colores del chibi")
	var st: Dictionary = s.status_style(s.get_member("toro"))
	check(st["text"] == "Listo ✓" and st["color"] == "#4fe39a", "Toro: «Listo ✓» verde")
	check(_close_color(Color(st["bg"]), T.DUNGEON_READY_BG), "Fondo del badge listo rgba(79,227,154,0.15)")
	st = s.status_style(s.get_member("brisa"))
	check(st["text"] == "Cambiando conjunto…" and st["color"] == "#f5c35b", "Brisa: «Cambiando conjunto…» ámbar")
	check(_close_color(Color(st["bg"]), T.DUNGEON_CHANGING_BG), "Fondo del badge cambiando rgba(245,195,91,0.15)")
	st = s.status_style(s.get_member("vela"))
	check(st["text"] == "Preparando…" and st["color"] == "#9aa6ae", "Vela: «Preparando…» gris")
	check(s.ready_count() == 3 and not s.all_ready(), "3 de 5 listos")
	var cl: Array = s.checklist(s.get_member("toro"))
	check(cl.size() == 3 and cl.map(func(r): return r["label"]) == ["Consumibles", "Reparación", "Conjunto"], "Checklist: Consumibles · Reparación · Conjunto")
	check(cl[0]["value"] == "✓" and cl[0]["color"] == "#4fe39a", "Toro: consumibles ✓")
	check(cl[1]["value"] == "96 %" and cl[1]["color"] == "#4fe39a", "Toro: reparación 96 % (verde)")
	check(cl[2]["value"] == "Tanque", "Toro: conjunto Tanque")
	cl = s.checklist(s.get_member("brisa"))
	check(cl[0]["value"] == "sin tónicos" and cl[0]["color"] == "#f5c35b", "Brisa: «sin tónicos» ámbar")
	check(cl[1]["value"] == "88 %", "Brisa: reparación 88 %")
	check(cl[2]["value"] == "→ Sanación" and cl[2]["color"] == "#f5c35b", "Brisa: conjunto «→ Sanación»")
	cl = s.checklist(s.get_member("nox"))
	check(cl[1]["value"] == "41 %" and cl[1]["color"] == "#ff8a8a", "Nox: reparación 41 % en rojo")
	check(LS.durability_color(75) == "#4fe39a" and LS.durability_color(60) == "#f5c35b" and LS.durability_color(49) == "#ff8a8a", "Umbrales de reparación 75 / 50")
	check(s.readiness_warnings(s.get_member("nox")) == ["Reparación al 41 %"], "Aviso de reparación de Nox")
	check(s.readiness_warnings(s.get_member("brisa")) == ["Consumibles: sin tónicos"], "Aviso de consumibles de Brisa")
	check(s.countdown_text() == "0:24" and near(s.countdown, 24.0), "Cuenta atrás inicial 0:24")
	check(s.countdown_caption() == "Entrada automática en 0:24 cuando los 5 estén listos", "Leyenda de la entrada automática")
	check(s.first_timers().size() == 2 and s.first_time_text().begins_with("Nox y Vela no conocen"), "Primera vez para Nox y Vela")
	check(s.affixes.size() == 2 and s.affixes[0]["name"] == "Grietas inestables", "Afijos de esta semana")
	check(s.route_votes("fast") == 3 and s.route_votes("loot") == 2 and near(s.route_ratio("fast"), 0.6), "Votación: rápida 3 (60 %) · botín 2")
	check(s.leading_route() == "fast" and s.voted_route() == "fast", "Ruta rápida en cabeza (tu voto)")
	check(s.set_options().map(func(o): return o["key"]) == ["F1", "F2", "F3"], "Conjuntos F1-F3")
	check(s.active_set_id() == "dano", "Kael lleva el conjunto Daño")
	check(LS.clock_text(24) == "0:24" and LS.clock_text(0.2) == "0:01" and LS.clock_text(75) == "1:15", "Formato de reloj")
	s.free()
	var bad: Node = LS.new()
	check(not bad.load_seed("res://nope.json") and bad.members.is_empty(), "Seed inexistente: sin datos")
	bad.free()


# --------------------------------------------------------------------------
# 4. Listo y cuenta atrás
# --------------------------------------------------------------------------
func _test_lobby_ready_and_countdown() -> void:
	print("-- 4. Ready check y cuenta atrás de 24 s")
	var s := _ls()
	var rc := []
	s.ready_changed.connect(func(id, on): rc.append([id, on]))
	var ar := []
	s.all_ready_changed.connect(func(on): ar.append(on))
	check(s.toggle_ready() == false and not s.is_ready("kael"), "toggle_ready quita tu «listo»")
	check(rc == [["kael", false]], "Señal ready_changed(kael, false)")
	check(s.toggle_ready() and s.is_ready("kael"), "toggle_ready vuelve a marcarte listo")
	s.tick(5.0)
	check(near(s.countdown, 24.0), "La cuenta atrás no avanza si faltan integrantes")
	check(not s.set_member_ready("brisa", true), "Brisa no puede marcarse mientras cambia de conjunto")
	check(not s.set_member_ready("nadie", true), "Integrante desconocido ignorado")
	s.tick(6.0)
	check(s.get_member("brisa")["status"] == LS.STATUS_PREPARING and s.get_member("brisa")["set"] == "Sanación", "Brisa termina el cambio a Sanación")
	check(s.get_member("brisa")["ilvl"] == 414 and s.role_line(s.get_member("brisa")) == "Sanadora · 414", "Brisa conserva su iLvl (los conjuntos F1-F3 son solo tuyos)")
	check(s.set_member_ready("brisa", true) and s.set_member_ready("vela", true), "Brisa y Vela se marcan listas")
	check(s.all_ready() and s.ready_count() == 5 and ar == [true], "Los 5 listos: all_ready_changed(true)")
	check(s.is_countdown_running() and s.countdown_caption().begins_with("Todos listos"), "La cuenta atrás corre")
	s.tick(7.0)
	check(near(s.countdown, 17.0) and s.countdown_text() == "0:17", "Tras 7 s: 0:17")
	s.set_member_ready("nox", false)
	check(not s.all_ready() and near(s.countdown, 24.0) and ar == [true, false], "Si alguien deja de estar listo, vuelve a 0:24")
	s.set_member_ready("nox", true)
	var entered := []
	s.entry_started.connect(func(id, info): entered.append([id, info]))
	s.tick(23.5)
	check(entered.is_empty() and s.countdown_text() == "0:01", "A 0,5 s del final aún espera (0:01)")
	s.tick(1.0)
	check(entered.size() == 1 and entered[0][0] == "ferrum_vault" and entered[0][1]["reason"] == "auto", "A los 24 s entra sola (reason auto)")
	check(s.state == LS.STATE_ENTERING and s.countdown_caption() == "Entrando en la mazmorra…", "Estado «entrando»")
	s.set_member_ready("kael", false)
	check(s.is_ready("kael"), "Tras entrar no se puede cambiar el «listo»")
	s.tick(5.0)
	check(entered.size() == 1, "No vuelve a entrar")
	s.reset()
	check(s.state == LS.STATE_WAITING and s.ready_count() == 3 and near(s.countdown, 24.0), "reset() vuelve al seed")
	s.ready_everyone()
	check(s.all_ready() and s.get_member("brisa")["set"] == "Sanación", "ready_everyone termina los cambios y marca a todos")
	s.free()


# --------------------------------------------------------------------------
# 5. Conjuntos F1-F3
# --------------------------------------------------------------------------
func _test_lobby_sets() -> void:
	print("-- 5. Cambio de conjunto F1-F3")
	var s := _ls()
	var changing := []
	var changed := []
	s.equipment_set_changing.connect(func(id, n): changing.append([id, n]))
	s.equipment_set_changed.connect(func(id, n): changed.append([id, n]))
	check(s.resolve_set("F2") == "tanque" and s.resolve_set("Sanación") == "sanacion" and s.resolve_set("dano") == "dano", "resolve_set acepta tecla, nombre e id")
	check(s.resolve_set("F9") == "", "Tecla sin conjunto")
	check(not s.set_equipment_set("Daño"), "Elegir el conjunto activo no hace nada")
	check(not s.set_equipment_set("F9"), "Conjunto desconocido rechazado")
	check(s.set_equipment_set("F2"), "F2 cambia a Tanque")
	var k: Dictionary = s.local_member()
	check(k["status"] == LS.STATUS_CHANGING and k["pending_set"] == "Tanque", "Kael: «Cambiando conjunto…» → Tanque")
	check(s.checklist(k)[2]["value"] == "→ Tanque", "Checklist: «→ Tanque»")
	check(changing == [["kael", "Tanque"]] and s.ready_count() == 2, "Señal de cambio y pierdes el «listo»")
	check(s.active_set_id() == "tanque", "El selector marca ya el conjunto pedido")
	check(not s.toggle_ready() and not s.is_ready("kael"), "No puedes marcarte listo mientras cambias")
	check(not s.set_equipment_set("F2"), "Repetir la misma tecla durante el cambio no hace nada")
	s.tick(1.0)
	check(k["status"] == LS.STATUS_CHANGING and near(k["swap_remaining"], 1.0), "A mitad del cambio (2 s)")
	s.tick(1.0)
	check(k["status"] == LS.STATUS_PREPARING and k["set"] == "Tanque" and k["set_id"] == "tanque", "Cambio terminado: Tanque")
	check(k["role"] == "tank" and k["ilvl"] == 404 and s.role_line(k) == "Tanque · 404", "Estadísticas actualizadas: Tanque · 404")
	check(changed == [["kael", "Tanque"]], "Señal equipment_set_changed")
	check(s.toggle_ready() and s.is_ready("kael"), "Tras el cambio te vuelves a marcar listo")
	check(s.set_equipment_set_by_key(2) and s.local_member()["pending_set"] == "Sanación", "F3 (índice 2) pide Sanación")
	check(s.set_equipment_set("F2") and k["status"] == LS.STATUS_PREPARING and k["pending_set"] == "", "Volver al conjunto que llevabas cancela el cambio")
	check(s.set_equipment_set_by_key(0), "F1 vuelve a Daño")
	s.tick(2.0)
	check(k["set"] == "Daño" and k["role"] == "dps" and k["ilvl"] == 412, "Daño · 412 de nuevo")
	check(not s.set_equipment_set_by_key(5), "Índice fuera de rango")
	s.set_swap_s = 0.0
	check(s.set_equipment_set("sanacion") and k["set"] == "Sanación" and k["role"] == "healer", "Con set_swap_s = 0 el cambio es instantáneo")
	check(s.role_line(k) == "Sanadora · 400", "Sanadora · 400")
	s.free()


# --------------------------------------------------------------------------
# 6. Inicio, votación, aprendizaje y abandono
# --------------------------------------------------------------------------
func _test_lobby_entry_and_extras() -> void:
	print("-- 6. Iniciar ahora, votación, modo aprendizaje y abandono")
	var s := _ls()
	var r: Dictionary = s.start_now()
	check(not r["ok"] and r["reason"] == "not_all_ready" and r["ready"] == 3, "Iniciar ahora exige a los 5 listos")
	check(s.start_dungeon_entry()["reason"] == "not_all_ready", "start_dungeon_entry también")
	s.leader = "toro"
	check(s.start_now()["reason"] == "not_leader" and not s.is_leader(), "Solo el líder puede iniciar ahora")
	s.leader = "kael"
	s.ready_everyone()
	var entered := []
	s.entry_started.connect(func(id, info): entered.append(info))
	r = s.start_now()
	check(r["ok"] and r["reason"] == "leader" and s.state == LS.STATE_ENTERING, "El líder inicia con todos listos")
	check(r["title"] == "Bóveda de Ferrum · Heroica" and r["route"] == "fast", "Info de entrada: mazmorra y ruta")
	check(r["learners"] == ["nox", "vela"] and r["learning_mode"], "Modo aprendizaje para Nox y Vela")
	check((r["members"] as Array).size() == 5 and entered.size() == 1, "5 integrantes en la entrada")
	check(s.start_now()["reason"] == "already_entering", "No se puede entrar dos veces")
	s.reset()
	r = s.start_dungeon_entry("debug", true)
	check(r["ok"] and r["reason"] == "debug", "force permite entrar sin todos listos")
	s.reset()
	var votes := []
	s.route_voted.connect(func(id, rt): votes.append([id, rt]))
	check(s.vote_route("loot"), "Kael vota la ruta del botín")
	check(s.route_votes("fast") == 2 and s.route_votes("loot") == 3 and s.voted_route() == "loot", "El voto se mueve (2 / 3)")
	check(s.leading_route() == "loot" and votes == [["kael", "loot"]], "Ahora lidera la ruta del botín")
	check(not s.vote_route("loot") and not s.vote_route("nada"), "Votos repetidos o rutas desconocidas rechazados")
	check(s.total_votes() == 5, "Siempre 5 votos")
	var lm := []
	s.learning_mode_changed.connect(func(on): lm.append(on))
	s.set_learning_mode(false)
	s.set_learning_mode(false)
	check(not s.learning_mode and lm == [false], "Modo aprendizaje desactivado (una señal)")
	s.ready_everyone()
	check(s.start_now()["learners"] == [], "Sin modo aprendizaje no hay aprendices")
	s.reset()
	var left := []
	s.group_left.connect(func(id): left.append(id))
	check(s.leave_group() and s.state == LS.STATE_LEFT and left == ["kael"], "Abandonar grupo")
	check(not s.leave_group() and s.start_dungeon_entry("x", true)["reason"] == "left_group", "Tras abandonar no se puede entrar")
	var snap: Dictionary = s.open_lobby("vado_hundido")
	check(snap["title"] == "Vado hundido · Normal" and snap["state"] == LS.STATE_WAITING, "open_lobby reabre otra mazmorra")
	check(s.open_lobby("ferrum_vault", "Mítica")["title"] == "Bóveda de Ferrum · Mítica", "open_lobby con dificultad")
	s.set_member_consumables("brisa", true)
	s.set_member_durability("nox", 100)
	check(s.readiness_warnings(s.get_member("brisa")).is_empty() and s.checklist(s.get_member("nox"))[1]["value"] == "100 %", "Brisa con tónicos y Nox reparado")
	s.set_member_durability("nox", 250)
	check(s.get_member("nox")["durability"] == 100, "Reparación limitada a 100 %")
	s.free()


# --------------------------------------------------------------------------
# 7. DungeonSummaryService: seed y cabecera
# --------------------------------------------------------------------------
func _test_summary_seed() -> void:
	print("-- 7. DungeonSummaryService: cabecera")
	var s := _ss()
	check(s.headline() == "Completada · Bóveda de Ferrum Heroica", "«Completada · Bóveda de Ferrum Heroica»")
	check(s.title_text() == "Bóveda de Ferrum · Heroica" and s.status_text == "Completada", "Título y estado")
	check(s.completion_text() == "31:42", "Tiempo 31:42")
	check(s.is_group_record(), "Récord del grupo (31:42 < 32:55)")
	check(SS.time_text(3725) == "1:02:05" and SS.time_text(59) == "0:59", "Formato de tiempo")
	check(s.members.size() == 5 and s.teammates().size() == 4, "5 integrantes, 4 compañeros")
	check(s.player_gear["weapon"] == 412 and s.player_gear["shoulders"] == 418, "Tu equipo: arma 412, hombreras 418")
	s.completion_s = 2000
	check(not s.is_group_record(), "Más lento que el mejor tiempo: sin récord")
	s.free()
	var bad: Node = SS.new()
	check(not bad.load_seed("res://nope.json") and bad.loot.is_empty(), "Seed inexistente: sin datos")
	bad.free()


# --------------------------------------------------------------------------
# 8. Botín inteligente
# --------------------------------------------------------------------------
func _test_summary_loot() -> void:
	print("-- 8. Botín inteligente")
	var s := _ss()
	check(s.loot.map(func(i): return i["id"]) == ["guja_ferrum", "hombreras_vado", "esquirlas"], "Guja, Hombreras y Esquirlas")
	check(s.upgrade_delta("guja_ferrum") == 8, "Guja: +8 de nivel de objeto")
	check(s.delta_text("guja_ferrum") == "▲ +8 nivel de objeto · +4,1 % daño", "«▲ +8 nivel de objeto · +4,1 % daño»")
	check(s.delta_color("guja_ferrum") == "#4fe39a", "Mejora en verde")
	check(s.highlighted_item() == "guja_ferrum", "La guja es la pieza destacada")
	check(s.item_actions("guja_ferrum").map(func(a): return a["label"]) == ["Equipar", "Comparar"], "Guja: Equipar · Comparar")
	check(s.item_actions("guja_ferrum")[0]["primary"], "Equipar es la acción principal")
	check(s.recipient_hint("guja_ferrum") == "", "Si es mejora para ti no se sugiere a otro")
	check(s.upgrade_delta("hombreras_vado") == 0 and s.delta_text("hombreras_vado") == "= mismo nivel que las tuyas", "Hombreras: «= mismo nivel que las tuyas»")
	check(s.delta_color("hombreras_vado") == "#9aa6ae", "Mismo nivel en gris")
	var b: Dictionary = s.best_recipient("hombreras_vado")
	check(b["member_id"] == "toro" and b["delta"] == 12, "Mejor destinatario: Toro (+12)")
	check(s.member_delta("hombreras_vado", "nox") == 8 and s.member_delta("hombreras_vado", "vela") == -2, "Deltas por compañero (Nox +8, Vela −2)")
	check(s.recipient_hint("hombreras_vado") == "Para Toro serían +12 de nivel de objeto.", "«Para Toro serían +12 de nivel de objeto.»")
	check(s.item_actions("hombreras_vado").map(func(a): return a["label"]) == ["Ofrecer a Toro", "Desguazar"], "Hombreras: Ofrecer a Toro · Desguazar")
	check(s.item_title(s.get_item("esquirlas")) == "Esquirlas ×120", "«Esquirlas ×120»")
	check(s.delta_text("esquirlas") == "al almacén del refugio", "Materiales: «al almacén del refugio»")
	check(s.item_actions("esquirlas").map(func(a): return a["label"]) == ["Enviar al refugio", "Guardar en mochila"], "Esquirlas: Enviar al refugio · Guardar en mochila")
	check(s.best_recipient("esquirlas").is_empty() and s.upgrade_delta("esquirlas") == 0, "Los materiales no se comparan")
	# Comparar.
	var cmp_sig := []
	s.item_compared.connect(func(id, c): cmp_sig.append(id))
	var c: Dictionary = s.compare("guja_ferrum")
	check(c["ok"] and c["current"] == 412 and c["new"] == 420 and c["delta"] == 8, "Comparar: 412 → 420 (+8)")
	check(c["stat"] == "+4,1 % daño" and s.get_item("guja_ferrum")["compared"] and cmp_sig == ["guja_ferrum"], "Comparación con estadística y señal")
	check(not s.compare("esquirlas")["ok"], "No se comparan materiales")
	# Equipar.
	var eq := []
	s.item_equipped.connect(func(id, slot, il): eq.append([id, slot, il]))
	var r: Dictionary = s.equip("guja_ferrum")
	check(r["ok"] and r["old"] == 412 and r["new"] == 420 and r["delta"] == 8, "Equipar la guja: 412 → 420")
	check(s.player_gear["weapon"] == 420 and s.get_member("kael")["gear"]["weapon"] == 420, "Tu arma pasa a 420")
	check(s.get_item("guja_ferrum")["state"] == SS.ITEM_EQUIPPED and s.item_state_text("guja_ferrum") == "Equipado ✓", "Estado «Equipado ✓»")
	check(eq == [["guja_ferrum", "weapon", 420]] and s.item_actions("guja_ferrum").is_empty(), "Señal y sin más acciones")
	check(s.equip("guja_ferrum")["reason"] == "already_equipped", "No se equipa dos veces")
	check(s.highlighted_item() == "", "Sin más mejoras pendientes")
	check(s.upgrade_delta("guja_ferrum") == 8 and s.delta_text("guja_ferrum").begins_with("▲ +8"), "La guja equipada conserva su comparación (+8)")
	check(s.recipient_hint("guja_ferrum") == "" and s.member_delta("guja_ferrum", "nox") == 15, "Sin pista para compañeros tras equiparla")
	# Ofrecer a Toro.
	var off := []
	s.item_offered.connect(func(id, m, d): off.append([id, m, d]))
	check(s.offer_to("hombreras_vado", "kael")["reason"] == "no_recipient", "No puedes ofrecerte la pieza a ti")
	check(s.offer_to("hombreras_vado", "nadie")["reason"] == "no_recipient", "Ni a alguien fuera del grupo")
	r = s.offer_to("hombreras_vado")
	check(r["ok"] and r["member_id"] == "toro" and r["delta"] == 12, "Ofrecer (sin destinatario) va a Toro con +12")
	check(off == [["hombreras_vado", "toro", 12]] and s.item_state_text("hombreras_vado") == "Ofrecido a Toro", "Estado «Ofrecido a Toro»")
	check(s.scrap("hombreras_vado")["reason"] == "already_offered", "Una pieza ofrecida no se desguaza")
	# Materiales.
	var routed := []
	s.material_routed.connect(func(id, d, q): routed.append([id, d, q]))
	check(s.store_in_bag("guja_ferrum")["reason"] == "not_material", "El equipo no se envía como material")
	r = s.send_to_shelter("esquirlas")
	check(r["ok"] and r["qty"] == 120 and routed == [["esquirlas", "shelter", 120]], "Esquirlas ×120 al refugio")
	check(s.item_state_text("esquirlas") == "Enviado al refugio ✓" and s.store_in_bag("esquirlas")["reason"] == "already_shelter", "Ya enviadas")
	check(s.pending_loot() == 0, "Todo el botín resuelto")
	# Desguazar / guardar / perform.
	s.reset()
	check(s.get_item("guja_ferrum")["state"] == SS.ITEM_NEW and s.player_gear["weapon"] == 412, "reset() restaura el botín y tu equipo")
	r = s.perform("hombreras_vado", "scrap")
	check(r["ok"] and r["shards"] == 18 and s.shards_from_scrap == 18, "Desguazar las hombreras: +18 esquirlas")
	check(s.item_state_text("hombreras_vado") == "Desguazado · +18 esquirlas", "Estado «Desguazado»")
	check(s.perform("esquirlas", "bag")["destination"] == SS.ITEM_BAG and s.item_state_text("esquirlas") == "Guardado en la mochila ✓", "Guardar en mochila")
	check(s.perform("guja_ferrum", "equip")["ok"] and s.perform("guja_ferrum", "bailar")["reason"] == "unknown_action", "perform equipa y rechaza acciones desconocidas")
	# Pieza peor que la tuya y sin destinatario.
	s.present({"loot": [{"id": "anillo", "name": "Anillo roto", "kind": "gear", "slot": "chest", "ilvl": 400, "color": "#9aa6ae", "tradeable": true}]})
	check(s.delta_text("anillo") == "▼ −10 nivel de objeto" and s.delta_color("anillo") == "#ff8a8a", "Pieza peor: «▼ −10» en rojo")
	check(s.best_recipient("anillo").is_empty() and s.item_actions("anillo").map(func(a): return a["id"]) == ["compare", "scrap"], "Sin destinatario: Comparar · Desguazar")
	s.present({"loot": [{"id": "ligada", "name": "Ligada", "kind": "gear", "slot": "shoulders", "ilvl": 418, "tradeable": false}]})
	check(s.offer_to("ligada", "toro")["reason"] == "not_tradeable", "Piezas ligadas no se pueden ofrecer")
	s.free()


# --------------------------------------------------------------------------
# 9. Momentos del grupo y elogios
# --------------------------------------------------------------------------
func _test_summary_moments() -> void:
	print("-- 9. Momentos del grupo y elogios")
	var s := _ss()
	var mo: Array = s.moments()
	check(mo.size() == 5, "5 momentos")
	check(mo[0]["name"] == "Toro" and mo[0]["text"] == "Bloqueó 14 golpes de mecánica", "Toro: «Bloqueó 14 golpes de mecánica»")
	check(mo[1]["text"] == "Salvó al grupo 3 veces al límite", "Brisa: «Salvó al grupo 3 veces al límite»")
	check(mo[2]["name"] == "Kael (tú)" and mo[2]["text"] == "11 interrupciones, ninguna perdida" and mo[2]["is_self"], "Kael (tú): «11 interrupciones, ninguna perdida»")
	check(mo[3]["text"] == "Primera vez aquí · cero muertes", "Nox: «Primera vez aquí · cero muertes»")
	check(mo[4]["text"] == "Encontró el cofre secreto", "Vela: «Encontró el cofre secreto»")
	check(mo.map(func(m): return m["initial"]) == ["T", "B", "K", "N", "V"], "Iniciales T B K N V")
	check(mo[0]["color"] == "#5aa9ff" and mo[4]["color"] == "#f5b546", "Colores de los círculos")
	var no_tables := true
	for m in mo:
		if str(m["text"]).to_lower().contains("dps") or str(m["text"]).to_lower().contains("daño total"):
			no_tables = false
	check(no_tables, "Sin tablas de daño: solo hitos positivos")
	check(s.is_praised("brisa") and s.praise_label("brisa") == "Elogiado ✓", "Brisa ya elogiada (como el HTML)")
	check(s.praise_label("toro") == "Elogiar" and s.praise_label("kael") == "", "Toro «Elogiar»; tú sin botón")
	check(s.praises_remaining() == 3, "Quedan 3 elogios")
	var sig := []
	s.praised.connect(func(id): sig.append(id))
	var r: Dictionary = s.praise("toro")
	check(r["ok"] and r["remaining"] == 2 and sig == ["toro"], "Elogiar a Toro")
	check(s.praise_label("toro") == "Elogiado ✓", "Toro pasa a «Elogiado ✓»")
	check(s.praise("toro")["reason"] == "already_praised", "Solo 1 elogio por compañero")
	check(s.praise("kael")["reason"] == "self", "No puedes elogiarte")
	check(s.praise("nadie")["reason"] == "unknown_member", "Desconocido rechazado")
	s.praise("nox")
	s.praise("vela")
	check(s.praises_remaining() == 0 and s.moments().filter(func(m): return m["praised"]).size() == 4, "Los 4 compañeros elogiados")
	check(sig == ["toro", "nox", "vela"], "Una señal por elogio")
	s.reset()
	check(s.praised_ids == ["brisa"], "reset() restaura los elogios del seed")
	s.present({"praised": ["kael", "toro", "toro", "x"]})
	check(s.praised_ids == ["toro"], "Elogios del seed filtrados (ni tú, ni repetidos, ni desconocidos)")
	s.free()


# --------------------------------------------------------------------------
# 10. Progreso
# --------------------------------------------------------------------------
func _test_summary_progress() -> void:
	print("-- 10. Tu progreso: XP, afinidades, Atlas, reputación y misiones")
	var s := _ss()
	check(s.xp_text() == "+18.400 XP", "«+18.400 XP»")
	check(s.level() == 32 and s.level_text() == "Nivel 32" and not s.leveled_up(), "Nivel 32 (sin subir)")
	check(near(s.xp_before_ratio(), 0.62) and near(s.xp_gain_ratio(), 0.16), "Barra: 62 % previo + 16 % ganado (como el HTML)")
	check(SS.thousands(1234567) == "1.234.567" and SS.thousands(350) == "350" and SS.thousands(-4500) == "-4.500", "Separador de miles «.»")
	var af: Array = s.affinities()
	check(af.size() == 3 and af.map(func(a): return a["name"]) == ["Vacío", "Pulso", "Calor"], "Afinidades: Vacío, Pulso, Calor")
	check(af.map(func(a): return a["text"]) == ["+2", "+1", "+1"], "Vacío +2, Pulso +1, Calor +1")
	check(af[0]["color"] == "#b47bff" and af[1]["color"] == "#5aa9ff" and af[2]["color"] == "#ff7a45", "Colores del Anexo B")
	for k in SS.ENERGIES:
		check(SS.ENERGIES[k]["color"] == T.ENERGIES[k]["color"], "Energía %s igual que hud_tokens" % k)
	var hints: Array = s.atlas_hints()
	check(hints.size() == 1 and hints[0]["text"] == "Usaste Vacío + Pulso 11 veces. Pista nueva en el Atlas.", "Pista del Atlas: Vacío + Pulso 11 veces")
	check(hints[0]["combo"] == "Vacío + Pulso" and s.atlas_threshold() == 10, "Umbral de 10 usos (Calor + Vacío ×4 no cuenta)")
	var rep: Array = s.reputation()
	check(rep.size() == 1 and rep[0]["label"] == "Reputación Ferrum" and rep[0]["text"] == "+350", "Reputación Ferrum +350")
	var q: Array = s.quests()
	check(q.size() == 1 and q[0]["label"] == "Misión «Mensaje para Ferrum»" and q[0]["status"] == "avanzó", "Misión «Mensaje para Ferrum» avanzó")
	s.present({"progress": {"xp_gained": 50000, "affinities": [{"energy": "vacio", "delta": 0}, {"energy": "nueva", "delta": 3}],
		"combos": [{"energies": ["calor", "eco"], "uses": 12}, {"energies": ["runa", "luz"], "uses": 30}], "reputation": [{"faction": "Umbral", "delta": 1200}]}})
	check(s.leveled_up() and s.new_level() == 33 and s.level_text() == "Nivel 32 → 33", "Subida de nivel: «Nivel 32 → 33»")
	check(near(s.xp_before_ratio() + s.xp_gain_ratio(), 1.0), "La barra se llena sin desbordar")
	af = s.affinities()
	check(af.size() == 1 and af[0]["name"] == "Nueva" and af[0]["color"] == "#c3ccd3", "Solo las que subieron; energías nuevas con color neutro")
	hints = s.atlas_hints()
	check(hints.size() == 2 and hints[0]["combo"] == "Runa + Luz" and hints[1]["combo"] == "Calor + Eco", "Varias pistas ordenadas por usos")
	check(s.reputation()[0]["text"] == "+1.200" and s.level() == 32, "Reputación +1.200 y el resto del seed se conserva")
	s.free()


# --------------------------------------------------------------------------
# 11. Salidas y datos externos
# --------------------------------------------------------------------------
func _test_summary_exits_and_present() -> void:
	print("-- 11. Salidas del resumen")
	var s := _ss()
	check(s.exit_options().map(func(o): return o["label"]) == ["Repetir con el mismo grupo", "Volver al refugio", "Salir al mundo"], "Tres salidas")
	check(s.exit_options()[0]["primary"] and not s.exit_options()[1]["primary"], "Repetir es la salida destacada")
	var ex := []
	s.exit_chosen.connect(func(c, i): ex.append([c, i]))
	var r: Dictionary = s.repeat_with_group()
	check(r["ok"] and r["choice"] == "repeat" and r["group"] == ["toro", "brisa", "kael", "nox", "vela"], "Repetir con el mismo grupo (5)")
	check(r["dungeon_id"] == "ferrum_vault" and r["pending_loot"] == 3 and ex.size() == 1, "Info de salida con botín pendiente")
	check(s.return_to_shelter()["choice"] == "shelter" and s.exit_to_world()["choice"] == "world", "Volver al refugio y salir al mundo")
	check(s.exit_choice == "world" and s.choose_exit("luna")["reason"] == "unknown_exit", "Salida desconocida rechazada")
	check(s.exit_to_world()["group"] == [], "Solo repetir lleva el grupo")
	var snap: Dictionary = s.present()
	check(snap["time"] == "31:42" and snap["record"] and snap["xp"] == 18400, "present() vacío = seed")
	snap = s.present({"dungeon": {"id": "vado_hundido", "name": "Vado hundido", "difficulty": ""}, "status": "Completada"})
	check(s.headline() == "Completada · Vado hundido" and s.title_text() == "Vado hundido", "Mazmorra sin dificultad")
	s.free()


# --------------------------------------------------------------------------
# 12. DungeonLobbyWindow
# --------------------------------------------------------------------------
func _test_lobby_window() -> void:
	print("-- 12. DungeonLobbyWindow")
	var s := _ls()
	var w = LobbyScene.instantiate()
	check(w.get_script() != null, "La escena tiene script (sin errores de parseo)")
	w.service = s
	root.add_child(w)
	w.initialize_window({})
	await _frames(2)
	check(w.window_id == "dungeon_lobby" and w.visible, "Ventana visible")
	check(s.get_parent() == w, "El servicio inyectado se adopta como hijo")
	check(w.header_caps.text == "ANTESALA" and w.header_caps.get_theme_color("font_color") == T.ACCENT_DEFAULT, "«ANTESALA» en cian")
	check(w.title_label_main.text == "Bóveda de Ferrum · Heroica" and w.title_label_main.get_theme_font_size("font_size") == 34, "Título de 34 px")
	check(w.countdown_label.text == "0:24" and w.caption_prefix.text == "Entrada automática en", "Cuenta atrás 0:24")
	check(w.caption_suffix.text == "cuando los 5 estén listos", "«cuando los 5 estén listos»")
	check(w.player_cards.size() == 5, "5 tarjetas de jugador")
	var toro: PanelContainer = w.player_cards[0]
	check(_text(toro, "Name") == "Toro" and _text(toro, "Role") == "Tanque · 418", "Tarjeta de Toro")
	check((toro.find_child("Role", true, false) as Label).get_theme_color("font_color") == Color("#5aa9ff"), "Rol en el color del tanque")
	check(toro.find_child("Avatar", true, false) is Control and toro.find_child("Avatar", true, false).custom_minimum_size == Vector2(40, 50), "Avatar chibi 40×50")
	check(_text(toro.find_child("Badge", true, false), "Text") == "Listo ✓", "Badge «Listo ✓»")
	check((toro.find_child("Badge", true, false) as PanelContainer).custom_minimum_size.y == 30, "Badge de 30 px")
	check(_text(toro.find_child("Check_durability", true, false), "Value") == "96 %", "Checklist de Toro: 96 %")
	var brisa: PanelContainer = w.player_cards[1]
	var bb := brisa.find_child("Badge", true, false).find_child("Text", true, false) as Label
	check(bb.text == "Cambiando conjunto…" and bb.get_theme_color("font_color") == Color("#f5c35b"), "Brisa: badge ámbar")
	check(_text(brisa.find_child("Check_set", true, false), "Value") == "→ Sanación", "Brisa: «→ Sanación»")
	check(_text(brisa.find_child("Check_consumables", true, false), "Value") == "sin tónicos", "Brisa: «sin tónicos»")
	var kael: PanelContainer = w.player_cards[2]
	check(_text(kael, "Name") == "Kael (tú)" and kael.get_meta("is_self"), "Tu tarjeta: «Kael (tú)»")
	var ksb := kael.get_theme_stylebox("panel") as StyleBoxFlat
	check(ksb.border_color == T.DUNGEON_SELF_EDGE and ksb.border_width_left == 2, "Tu tarjeta con borde cian")
	check((toro.get_theme_stylebox("panel") as StyleBoxFlat).border_color == T.DUNGEON_CARD_EDGE, "Las demás con borde tenue")
	check(not w.player_cards[3].tooltip_text.is_empty() and w.player_cards[3].tooltip_text.contains("41 %"), "Nox: aviso de reparación en la tarjeta")
	var nb := w.player_cards[4].find_child("Badge", true, false).find_child("Text", true, false) as Label
	check(nb.text == "Preparando…", "Vela: «Preparando…»")
	check(w.route_rows.size() == 2 and _text(w.route_rows[0], "Votes") == "3 votos", "Votación de ruta: 3 votos")
	check(near(w.route_rows[0].find_child("Bar", true, false).ratio, 0.6), "Barra de la ruta rápida al 60 %")
	check(w.first_caps.text == "PRIMERA VEZ PARA 2" and w.learning_switch.on, "«Primera vez para 2» con modo aprendizaje activo")
	check(w.set_buttons.size() == 3 and w.set_buttons[0].text == "F1 Daño" and w.set_buttons[2].text == "F3 Sanación", "Selector F1-F3")
	check(w.set_buttons[0].get_meta("active") and not w.set_buttons[1].get_meta("active"), "F1 activo")
	check(w.ready_button.text == "Cancelar listo [Espacio]", "Estás listo: «Cancelar listo [Espacio]»")
	check(w.start_button.visible and w.start_button.disabled, "«Iniciar ahora» visible para el líder pero desactivado")
	check(w.stage.size == T.CINEMA_DESIGN_SIZE, "Escenario 1440×810")
	check(near(w.cards_row.position.y, 150.0) and near(w.cards_row.position.x, 50.0), "Tarjetas en (50, 150)")
	# Teclado: Espacio.
	w._unhandled_key_input(_key(KEY_SPACE))
	await _frames(1)
	check(not s.is_ready("kael") and w.ready_button.text == "Marcar listo [Espacio]", "Espacio: «Marcar listo [Espacio]»")
	check(w.ready_button.get_meta("primary"), "Marcar listo destacado en cian")
	check(_text(w.player_cards[2].find_child("Badge", true, false), "Text") == "Preparando…", "Tu badge pasa a «Preparando…»")
	w.handle_key(KEY_R)
	check(s.is_ready("kael"), "R también marca listo")
	# F2.
	w._unhandled_key_input(_key(KEY_F2))
	await _frames(1)
	check(s.local_member()["pending_set"] == "Tanque" and w.set_buttons[1].get_meta("active"), "F2: cambia a Tanque")
	check(_text(w.player_cards[2].find_child("Badge", true, false), "Text") == "Cambiando conjunto…" and w.ready_button.disabled, "Cambiando: badge ámbar y listo desactivado")
	s.tick(2.0)
	await _frames(1)
	check(_text(w.player_cards[2], "Role") == "Tanque · 404" and _text(w.player_cards[2].find_child("Check_set", true, false), "Value") == "Tanque", "Tarjeta actualizada: Tanque · 404")
	w.handle_key(KEY_F1)
	s.tick(2.0)
	w.handle_key(KEY_F3)
	check(s.local_member()["pending_set"] == "Sanación", "F3: Sanación")
	w.handle_key(KEY_F1)
	await _frames(1)
	check(s.local_member()["set"] == "Daño" and s.local_member()["status"] == LS.STATUS_PREPARING, "F1 cancela y vuelve a Daño")
	# Todos listos: cuenta atrás.
	s.ready_everyone()
	await _frames(1)
	w._process(0.0)
	check(not w.start_button.disabled and w.start_button.get_meta("primary"), "Con los 5 listos «Iniciar ahora» se activa")
	check(w.caption_prefix.text == "Todos listos · entrada automática en", "La leyenda cambia")
	s.tick(10.0)
	w._process(0.0)
	check(w.countdown_label.text == "0:14" and w.countdown_label.get_theme_color("font_color") == T.ACCENT_DEFAULT, "La cuenta atrás avanza (0:14 en cian)")
	# Votar con clic y alternar modo aprendizaje.
	w.route_rows[1].pressed.emit()
	await _frames(1)
	check(s.voted_route() == "loot" and _text(w.route_rows[1], "Votes") == "3 votos", "Clic en la ruta del botín: voto movido")
	w.learning_switch.set_on(false)
	check(not s.learning_mode, "El interruptor desactiva el modo aprendizaje")
	# H refugio de bolsillo.
	var pocket := []
	w.pocket_shelter_requested.connect(func(): pocket.append(true))
	w.handle_key(KEY_H)
	check(pocket.size() == 1, "H pide el refugio de bolsillo")
	# Enter: iniciar ahora.
	var entered := []
	w.dungeon_entered.connect(func(id, info): entered.append(info))
	w._unhandled_key_input(_key(KEY_ENTER))
	await _frames(1)
	check(entered.size() == 1 and entered[0]["reason"] == "leader", "Enter: el líder inicia ahora")
	check(not w.visible and w.close_reason == "entered", "La antesala se cierra al entrar")
	# Reabrir y abandonar.
	w.initialize_window({})
	await _frames(1)
	check(w.visible and s.state == LS.STATE_WAITING and w.player_cards.size() == 5, "Reabrir: el grupo vuelve a esperar")
	var left := []
	w.lobby_left.connect(func(): left.append(true))
	w.leave_button.pressed.emit()
	await _frames(1)
	check(left.size() == 1 and not w.visible and w.close_reason == "left", "Abandonar grupo cierra la antesala")
	# Escalado.
	w.initialize_window({"dungeon_id": "ferrum_vault"})
	w.size = Vector2(1280, 720)
	w._layout()
	check(near(w.stage_scale, 1280.0 / 1440.0, 0.001), "Escalado uniforme a 1280×720")
	check(w.handle_key(KEY_Q) == false, "Teclas sin uso no se consumen")
	w.queue_free()
	await _frames(1)


# --------------------------------------------------------------------------
# 13. DungeonSummaryWindow
# --------------------------------------------------------------------------
func _test_summary_window() -> void:
	print("-- 13. DungeonSummaryWindow")
	var s := _ss()
	var w = SummaryScene.instantiate()
	check(w.get_script() != null, "La escena tiene script (sin errores de parseo)")
	w.service = s
	root.add_child(w)
	w.initialize_window({})
	await _frames(2)
	check(w.window_id == "dungeon_summary" and w.visible, "Ventana visible")
	check(w.status_caps.text == "COMPLETADA" and w.status_caps.get_theme_color("font_color") == T.DUNGEON_READY, "«COMPLETADA» en verde")
	check(w.title_main.text == "Bóveda de Ferrum · Heroica" and w.title_main.tooltip_text == "Completada · Bóveda de Ferrum Heroica", "Título y titular")
	check(_text(w.time_chip, "Text") == "31:42", "Chip «31:42»")
	check(w.record_chip.visible and _text(w.record_chip, "Text") == "Récord del grupo", "Chip dorado «Récord del grupo»")
	check((w.record_chip.find_child("Text", true, false) as Label).get_theme_color("font_color") == T.DUNGEON_RECORD, "Récord en dorado")
	# Columnas.
	check(w.loot_card.position == Vector2(50, 130) and w.loot_card.size == Vector2(420, 600), "Columna Tu botín: 420×600 en (50, 130)")
	check(w.moments_card.position == Vector2(490, 130) and w.moments_card.size == Vector2(460, 600), "Columna Momentos: 460×600 en (490, 130)")
	check(w.progress_card.position == Vector2(970, 130) and w.progress_card.size == Vector2(420, 600), "Columna Progreso: 420×600 en (970, 130)")
	# Botín.
	check(w.loot_rows.size() == 3, "3 piezas de botín")
	var g: PanelContainer = w.loot_rows[0]
	check(_text(g, "Name") == "Guja de Ferrum" and _text(g, "Delta") == "▲ +8 nivel de objeto · +4,1 % daño", "Guja con su comparador")
	check(g.get_meta("highlighted") and (g.get_theme_stylebox("panel") as StyleBoxFlat).border_color == T.ACCENT_DEFAULT, "Guja destacada con borde cian")
	check(g.find_child("Action_equip", true, false) != null and _text(g, "Action_equip") == "Equipar" and _text(g, "Action_compare") == "Comparar", "Botones Equipar y Comparar")
	var h: PanelContainer = w.loot_rows[1]
	check(_text(h, "Delta") == "= mismo nivel que las tuyas" and _text(h, "Hint") == "Para Toro serían +12 de nivel de objeto.", "Hombreras: mismo nivel y pista para Toro")
	check(_text(h, "Action_offer") == "Ofrecer a Toro" and _text(h, "Action_scrap") == "Desguazar", "Ofrecer a Toro · Desguazar")
	check((h.find_child("Action_offer", true, false) as Button).get_theme_color("font_color") == T.DUNGEON_OFFER_TEXT, "Ofrecer en azul #6cb8ff")
	var e: PanelContainer = w.loot_rows[2]
	check(_text(e, "Name") == "Esquirlas ×120" and _text(e, "Action_shelter") == "Enviar al refugio" and _text(e, "Action_bag") == "Guardar en mochila", "Esquirlas ×120: refugio o mochila")
	# Comparar y equipar con clic.
	var cmp := []
	w.comparison_shown.connect(func(id, c): cmp.append(id))
	(g.find_child("Action_compare", true, false) as Button).pressed.emit()
	await _frames(1)
	check(cmp == ["guja_ferrum"] and w.compare_label.visible and w.compare_label.text == "Arma: 412 → 420 (+8)", "Comparar muestra «Arma: 412 → 420 (+8)»")
	(w.loot_rows[0].find_child("Action_equip", true, false) as Button).pressed.emit()
	await _frames(1)
	check(s.get_item("guja_ferrum")["state"] == SS.ITEM_EQUIPPED and _text(w.loot_rows[0], "State") == "Equipado ✓", "Equipar: «Equipado ✓»")
	check(w.loot_rows[0].find_child("Action_equip", true, false) == null, "Sin botones tras equipar")
	check(_text(w.loot_rows[0], "Delta").begins_with("▲ +8") and w.loot_rows[0].find_child("Hint", true, false) == null, "Tras equipar: sigue «▲ +8» y sin pista")
	var acts := []
	w.loot_action.connect(func(id, a, r): acts.append([id, a, r["ok"]]))
	(w.loot_rows[1].find_child("Action_offer", true, false) as Button).pressed.emit()
	await _frames(1)
	check(acts == [["hombreras_vado", "offer", true]] and _text(w.loot_rows[1], "State") == "Ofrecido a Toro", "Ofrecer a Toro (intercambio directo)")
	(w.loot_rows[2].find_child("Action_shelter", true, false) as Button).pressed.emit()
	await _frames(1)
	check(_text(w.loot_rows[2], "State") == "Enviado al refugio ✓", "Esquirlas enviadas al refugio")
	# Momentos.
	check(w.moment_rows.size() == 5, "5 momentos del grupo")
	check(_text(w.moments_card, "Note") == "sin tablas de daño, solo lo que sumó", "«sin tablas de daño, solo lo que sumó»")
	check(_text(w.moment_rows[0], "Moment") == "Bloqueó 14 golpes de mecánica" and w.moment_rows[0].find_child("Initial", true, false).letter == "T", "Toro con su inicial")
	check(_text(w.moment_rows[2], "Name") == "Kael (tú)" and w.moment_rows[2].find_child("Praise", true, false) == null, "Tú sin botón de elogio")
	var bp := w.moment_rows[1].find_child("Praise", true, false) as Button
	check(bp.text == "Elogiado ✓" and bp.disabled and bp.get_theme_color("font_color") == Color("#4fe39a"), "Brisa: «Elogiado ✓» verde")
	var tp := w.moment_rows[0].find_child("Praise", true, false) as Button
	check(tp.text == "Elogiar" and not tp.disabled, "Toro: «Elogiar»")
	tp.pressed.emit()
	await _frames(1)
	var tp2 := w.moment_rows[0].find_child("Praise", true, false) as Button
	check(tp2.text == "Elogiado ✓" and tp2.disabled and tp2.get_theme_color("font_color") == T.DUNGEON_PRAISED, "Elogiar → «Elogiado ✓» #4fe39a")
	check(s.is_praised("toro") and s.praises_remaining() == 2, "El elogio queda registrado")
	check(w.praise_note_label.text == "Puedes dar 1 elogio por mazmorra a cada compañero.", "Nota de elogios")
	# Progreso.
	check(w.level_label.text == "Nivel 32" and w.xp_label.text == "+18.400 XP", "Nivel 32 · +18.400 XP")
	check(w.xp_label.get_theme_color("font_color") == T.DUNGEON_XP_TEXT, "XP en lila #c4b3ff")
	check(near(w.xp_bar.before, 0.62) and near(w.xp_bar.gain, 0.16), "Barra de XP 62 % + 16 %")
	check(w.affinity_box.get_child_count() == 3 and _text(w.affinity_box.get_child(0), "Name") == "Vacío" and _text(w.affinity_box.get_child(0), "Delta") == "+2", "Afinidades: Vacío +2…")
	check(w.atlas_box.visible and w.atlas_box.get_child(0).find_child("Text", true, false).get_meta("plain") == "Usaste Vacío + Pulso 11 veces. Pista nueva en el Atlas.", "Pista del Atlas")
	check(w.atlas_box.get_child(0).find_child("Text", true, false).text.contains("[b]Vacío + Pulso[/b]"), "La combinación va en negrita")
	check(_text(w.also_box.get_child(0), "Value") == "+350" and _text(w.also_box.get_child(1), "Key") == "Misión «Mensaje para Ferrum»", "Reputación +350 y misión")
	check(_text(w.also_box.get_child(1), "Value") == "avanzó", "Misión «avanzó»")
	check(w.repeat_button.text == "Repetir con el mismo grupo" and w.repeat_button.custom_minimum_size.y == 44, "Repetir (44 px)")
	check((w.repeat_button.get_theme_stylebox("normal") as StyleBoxFlat).bg_color == T.DUNGEON_REPEAT, "Repetir destacado en cian #46e3c1")
	check(w.shelter_button.text == "Volver al refugio" and w.world_button.text == "Salir al mundo", "Volver al refugio · Salir al mundo")
	# Salidas.
	var ex := []
	w.exit_selected.connect(func(c, i): ex.append(c))
	w.shelter_button.pressed.emit()
	await _frames(1)
	check(ex == ["shelter"] and not w.visible and w.close_reason == "shelter", "Volver al refugio cierra el resumen")
	w.initialize_window({"summary": {"completion_s": 2100}})
	await _frames(1)
	check(w.visible and not w.record_chip.visible and _text(w.time_chip, "Text") == "35:00", "Resumen a medida: 35:00 sin récord")
	check(_text(w.loot_rows[0], "Action_equip") == "Equipar", "Al reabrir el botín vuelve a estar pendiente")
	w.handle_key(KEY_E)
	await _frames(1)
	check(s.get_item("guja_ferrum")["state"] == SS.ITEM_EQUIPPED, "E equipa la mejora destacada")
	w._unhandled_key_input(_key(KEY_ENTER))
	await _frames(1)
	check(ex[-1] == "repeat" and not w.visible, "Enter: repetir con el mismo grupo")
	w.initialize_window({})
	w.handle_key(KEY_ESCAPE)
	await _frames(1)
	check(ex[-1] == "world" and not w.visible, "Esc: salir al mundo")
	w.size = Vector2(1920, 1080)
	w._layout()
	check(near(w.stage_scale, 1920.0 / 1440.0, 0.001), "Escalado uniforme a 1920×1080")
	check(SummaryWindowConst._slot_name("weapon") == "Arma" and SummaryWindowConst._slot_name("ring") == "Ring", "Nombres de ranura")
	w.queue_free()
	await _frames(1)
