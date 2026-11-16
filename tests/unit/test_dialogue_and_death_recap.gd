extends SceneTree
## Suite headless (UI v2.4 Paso 13): Diálogo cinematográfico con PNJ y Muerte / recap táctico.
## Run: Godot --headless --path clients/godot-mmo-client -s tests/unit/test_dialogue_and_death_recap.gd
## Exit code 0 = todo PASS.

const DS = preload("res://shared-core/DialogueService.gd")
const DR = preload("res://shared-core/DeathRecapService.gd")
const QS = preload("res://shared-core/QuestService.gd")
const DialogueScene = preload("res://ui/windows/DialogueWindow/DialogueWindow.tscn")
const DeathScene = preload("res://ui/windows/DeathWindow/DeathWindow.tscn")
const DLG_SEED := "res://config/dialogue/dialogue_seed.json"
const DEATH_SEED := "res://config/death/death_recap_seed.json"

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
	print("== [TEST] Paso 13: Diálogo cinematográfico con PNJ y Muerte / recap táctico ==")
	_test_registry()
	await _test_orchestrator()
	_test_dialogue_seed_and_relation()
	_test_dialogue_fragments()
	_test_dialogue_options()
	_test_dialogue_quest()
	_test_dialogue_branch()
	_test_dialogue_lore()
	_test_dialogue_shop_and_lock()
	_test_dialogue_advance_and_errors()
	_test_dialogue_history_persistence()
	_test_death_seed_and_recap()
	_test_death_tips()
	_test_death_live_flow()
	_test_resurrection()
	_test_respawn_and_replay()
	_test_formatting()
	await _test_dialogue_window()
	await _test_death_window()
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


func _ds() -> Node:
	var s: Node = DS.new()
	s.load_seed(DLG_SEED)
	return s


func _dr() -> Node:
	var s: Node = DR.new()
	s.load_seed(DEATH_SEED)
	s.auto_tick = false
	return s


func _free(n) -> void:
	if is_instance_valid(n):
		if n is Node and (n as Node).is_inside_tree():
			(n as Node).queue_free()
		else:
			n.free()


func _key(code: int) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	return ev


# --------------------------------------------------------------------------
# 1. Registro de ventanas y autoloads
# --------------------------------------------------------------------------
func _test_registry() -> void:
	print("-- 1. UIWindowRegistry y autoloads")
	var Registry = load("res://ui/orchestration/UIWindowRegistry.gd")
	var UITypes = load("res://ui/types/UITypes.gd")
	var reg: Node = Registry.new()
	var expected := [
		["dialogue_window", "res://ui/windows/DialogueWindow/DialogueWindow.tscn", UITypes.WindowCategory.GAME_WINDOW, "GAME_WINDOW"],
		["death_window", "res://ui/windows/DeathWindow/DeathWindow.tscn", UITypes.WindowCategory.MODAL_OVERLAY, "MODAL_OVERLAY"],
	]
	for e in expected:
		var id: String = e[0]
		check(reg.is_registered(id), "Registrada: " + id)
		var meta = reg.get_metadata(id)
		check(meta != null and meta.scene_path == e[1], "%s -> %s" % [id, e[1]])
		check(meta != null and ResourceLoader.exists(meta.scene_path), "La escena de %s existe" % id)
		check(meta != null and meta.category == e[2], "%s es %s" % [id, e[3]])
		check(reg.get_shortcut_keys(id).is_empty(), "%s no roba atajos globales" % id)
	check(reg.get_window_for_key(KEY_L) == "quests_window" and reg.get_window_for_key(KEY_H) == "shelter", "L y H siguen en Misiones y Refugio")
	check(reg.is_registered("vendor_window") and reg.is_registered("marketplace_window"), "Destinos de la opción Tienda registrados (vendor/mercado)")
	reg.free()
	check(str(ProjectSettings.get_setting("autoload/DialogueService", "")) == "*res://shared-core/DialogueService.gd", "Autoload DialogueService registrado")
	check(str(ProjectSettings.get_setting("autoload/DeathRecapService", "")) == "*res://shared-core/DeathRecapService.gd", "Autoload DeathRecapService registrado")
	var ads := root.get_node_or_null("DialogueService")
	check(ads != null and ads.npcs.has("mira"), "Autoload DialogueService cargó su seed")
	check(ads != null and ads.quest_service == root.get_node_or_null("QuestService"), "DialogueService se vincula a QuestService")
	var adr := root.get_node_or_null("DeathRecapService")
	check(adr != null and adr.abilities.size() == 4 and adr.state == DR.STATE_ALIVE, "Autoload DeathRecapService cargó su seed y empieza vivo")
	var mirror := ProjectSettings.globalize_path("res://").path_join("../shared-core")
	for f in ["DialogueService.gd", "DeathRecapService.gd"]:
		var a := FileAccess.get_file_as_string("res://shared-core/" + f)
		var b := FileAccess.get_file_as_string(mirror.path_join(f))
		check(a != "" and a == b, "clients/shared-core/%s sincronizado con el cliente" % f)
	check(FileAccess.file_exists(DLG_SEED) and FileAccess.file_exists(DEATH_SEED), "Seeds de diálogo y muerte presentes")


func _test_orchestrator() -> void:
	print("-- 2. UIOrchestrator.open_dialogue / open_death_window")
	var orch := root.get_node_or_null("UIOrchestrator")
	check(orch != null, "Autoload UIOrchestrator presente")
	if orch == null:
		return
	check(orch.has_method("open_dialogue") and orch.has_method("open_death_window"), "UIOrchestrator expone open_dialogue y open_death_window")
	var w = orch.open_dialogue()
	await _frames(2)
	check(w != null and w.window_id == "dialogue_window", "open_dialogue() instancia DialogueWindow")
	check(w != null and w.service == root.get_node("DialogueService"), "DialogueWindow usa el autoload DialogueService")
	check(w != null and w.service.active_npc == "mira" and w.service.active_node == "intro", "Por defecto: Mira en el nodo «intro»")
	check(w != null and w.visible, "La ventana de diálogo está visible")
	check(w != null and w.get_parent() == orch.window_layer, "Se añade a la capa de ventanas")
	w = orch.open_dialogue("gildas", "")
	await _frames(1)
	check(w != null and w.service.active_npc == "gildas" and w.service.active_node == "intro", "open_dialogue(\"gildas\") cambia de interlocutor")
	w.handle_key(KEY_ESCAPE)
	await _frames(1)
	check(not w.visible and not w.service.is_active(), "Esc cierra la conversación abierta por el orquestador")
	w = orch.open_dialogue("mira", "lore_ferrum")
	await _frames(1)
	check(w.visible and w.service.active_node == "lore_ferrum", "open_dialogue(mira, lore_ferrum) reabre en el nodo pedido")
	w.close_dialogue()
	await _frames(1)

	var d = orch.open_death_window()
	await _frames(2)
	check(d != null and d.window_id == "death_window", "open_death_window() instancia DeathWindow")
	check(d != null and d.service == root.get_node("DeathRecapService"), "DeathWindow usa el autoload DeathRecapService")
	check(d != null and d.service.state == DR.STATE_DEAD and d.service.recap["events"].size() == 4, "Sin datos: recap del seed (4 impactos en 5 s)")
	d.service.auto_tick = false
	var custom := {"events": [{"t": -2.0, "name": "Mordisco", "amount": 4000}, {"t": 0.0, "name": "Zarpazo", "amount": 6000}], "max_health": 10000}
	d = orch.open_death_window(custom)
	await _frames(1)
	check(d.service.recap["events"].size() == 2 and d.service.recap["total"] == 10000, "open_death_window(recap) muestra el recap recibido")
	check(d.event_rows.size() == 2, "La tarjeta se reconstruye con los impactos recibidos")
	check(d.service.resurrection.is_empty() and not d.res_card.visible, "Sin resurrección en los datos: no hay tarjeta de resurrección")
	orch.close_window("death_window")
	d.service.reset()
	await _frames(1)
	check(not d.visible, "close_window oculta la pantalla de muerte")


# --------------------------------------------------------------------------
# 3. DialogueService: seed y relación
# --------------------------------------------------------------------------
func _test_dialogue_seed_and_relation() -> void:
	print("-- 3. DialogueService: seed, PNJ y relación")
	var s := _ds()
	check(s.npcs.size() == 2, "Seed con 2 PNJ (Mira y Gildas)")
	var mira: Dictionary = s.get_npc("mira")
	check(mira["name"] == "Mira" and mira["title"] == "Exploradora del Umbral", "Mira · Exploradora del Umbral")
	check(mira["gender"] == "f" and mira["start"] == "intro", "Mira: género f y nodo inicial intro")
	check((mira["nodes"] as Dictionary).size() == 5, "Árbol de Mira con 5 nodos")
	check(s.relation_levels.size() == 5, "5 niveles de relación")
	check(s.relation_levels.map(func(l): return l["id"]) == ["unknown", "neutral", "friendly", "ally", "revered"], "Desconocido · Neutral · Amistoso · Aliado · Reverenciado")
	check(s.get_relation("mira") == 340 and s.relation_level_id("mira") == "ally", "Mira: 340 puntos = Aliado")
	check(s.relation_name("mira") == "Aliada", "Nombre concordado: «Aliada»")
	check(s.relation_ticks("mira") == 3, "Medidor de Mira: 3 de 5 marcas (como el HTML)")
	check(s.relation_name("gildas") == "Neutral" and s.relation_ticks("gildas") == 1, "Gildas: Neutral con 1 marca")
	check(s.relation_level_index(0) == 0 and s.relation_level_index(99) == 0 and s.relation_level_index(100) == 1, "Umbral Desconocido/Neutral en 100")
	check(s.relation_level_index(299) == 2 and s.relation_level_index(300) == 3 and s.relation_level_index(450) == 4, "Umbrales Amistoso/Aliado/Reverenciado")
	var seen := []
	s.relation_changed.connect(func(n, p, l): seen.append([n, p, l]))
	s.change_relation("mira", 500)
	check(s.get_relation("mira") == 500 and s.relation_ticks("mira") == 5, "La relación se limita a 500 (5 marcas)")
	check(s.relation_name("mira") == "Reverenciada", "Mira reverenciada: «Reverenciada»")
	check(seen.size() == 1 and seen[0] == ["mira", 500, "revered"], "Señal relation_changed con nivel nuevo")
	check(s.history.size() == 1 and str(s.history[0]["text"]).contains("Reverenciada"), "El cambio de nivel queda en el historial")
	s.change_relation("mira", -900)
	check(s.get_relation("mira") == 0 and s.relation_name("mira") == "Desconocida", "La relación no baja de 0 (Desconocida)")
	check(s.change_relation("nadie", 50) == 0, "change_relation ignora PNJ desconocidos")
	check(s.level_meets("gildas", "neutral") and not s.level_meets("gildas", "friendly"), "level_meets compara con el nivel requerido")
	check(s.get_reputation("ferrum") == 0 and s.get_reputation("guardabosques") == 120, "Reputación inicial por facción")
	check(s.change_reputation("nueva", 5) == 5 and s.factions.has("nueva"), "Facción nueva creada al cambiar reputación")
	s.free()
	var bad: Node = DS.new()
	check(not bad.load_seed("res://config/dialogue/no_existe.json"), "load_seed falla con ruta inexistente")
	bad.free()


# --------------------------------------------------------------------------
# 4. Fragmentos narrativos
# --------------------------------------------------------------------------
func _test_dialogue_fragments() -> void:
	print("-- 4. Nodos y fragmentos narrativos")
	var s := _ds()
	var started := []
	s.dialogue_started.connect(func(n, node): started.append([n, node]))
	check(s.start("mira"), "start(mira)")
	check(started == [["mira", "intro"]], "Señal dialogue_started(mira, intro)")
	check(s.is_active() and s.active_node == "intro", "Conversación activa en intro")
	check(s.fragment_count() == 2, "Intro tiene 2 fragmentos")
	check(s.current_text() == "La grieta del Vado Roto no se cerrará sola.", "Primer fragmento visible")
	check(s.has_more_fragments(), "Quedan fragmentos")
	var adv := []
	s.fragment_advanced.connect(func(i, t): adv.append([i, t]))
	check(s.advance_fragment(), "advance_fragment revela el segundo")
	check(adv == [[1, 2]], "Señal fragment_advanced(1, 2)")
	check(s.current_text().begins_with("La grieta del Vado Roto no se cerrará sola. Si el Guardián cae"), "Texto acumulado de los dos fragmentos")
	check(s.current_text() == s.full_text(), "Todo revelado = texto completo")
	check(not s.has_more_fragments() and not s.advance_fragment(), "No hay más fragmentos")
	check(s.is_visited("mira", "intro"), "Nodo intro visitado")
	check(s.start("mira", "lore_guardian") and s.active_node == "lore_guardian", "start con nodo concreto")
	check(s.start("mira", "no_existe") and s.active_node == "intro", "Nodo inexistente: vuelve al inicial")
	check(not s.start("nadie"), "PNJ inexistente: start falla")
	s.free()


# --------------------------------------------------------------------------
# 5. Opciones decoradas (tipos, badges, «Ya lo preguntaste»)
# --------------------------------------------------------------------------
func _test_dialogue_options() -> void:
	print("-- 5. Opciones [1]–[4] por tipo")
	var s := _ds()
	s.start("mira", "intro")
	var o: Array = s.current_options()
	check(o.size() == 4, "Intro con 4 opciones")
	check(o.map(func(x): return x["key"]) == ["1", "2", "3", "4"], "Teclas 1–4")
	check(o.map(func(x): return x["type"]) == ["quest", "branch", "lore", "shop"], "Tipos: misión, rama, lore, tienda")
	check(o[0]["text"] == "Yo me encargo del Guardián.", "Opción 1: «Yo me encargo del Guardián.»")
	check(o[0]["badge"] == "Acepta misión · Hoja de la grieta ▲", "Badge de misión verde con recompensa")
	check(o[0]["badge_color"] == "#4fe39a" and o[0]["icon_bg"] == "#8a6a2b", "Misión: badge #4fe39a e icono #8a6a2b")
	check(o[1]["badge"] == "Rama alternativa · reputación con Ferrum" and o[1]["badge_color"] == "#f5c35b", "Rama alternativa con badge dorado")
	check(o[1]["icon_bg"] == "#2b4a8a", "Rama: icono #2b4a8a")
	check(o[2]["asked"] and o[2]["badge"] == "Ya lo preguntaste", "Lore ya consultado: «Ya lo preguntaste»")
	check(near(o[2]["opacity"], 0.5) and o[2]["badge_color"] == "#7c8992", "Lore consultado atenuado a 0.5")
	check(near(o[0]["opacity"], 1.0) and near(o[1]["opacity"], 1.0) and near(o[3]["opacity"], 1.0), "Resto de opciones a opacidad 1")
	check(o[3]["badge"] == "Tienda" and o[3]["icon_bg"] == "#2a7a4a", "Tienda: badge «Tienda» e icono #2a7a4a")
	check(not o.any(func(x): return x["locked"]), "Ninguna bloqueada para Mira")
	check(s.get_option(1)["id"] == "take_guardian" and s.get_option("supplies")["index"] == 4, "get_option por número y por id")
	check(s.get_option(5).is_empty() and s.get_option(0).is_empty(), "Números fuera de rango vacíos")
	check(DS.quest_badge({"quest_action": "turn_in", "reward": "Oro"}) == "Entrega misión · Oro ▲", "Badge de entrega de misión")
	check(DS.quest_badge({}) == "Acepta misión", "Badge de misión sin recompensa")
	var raw := {"npcs": [{"id": "x", "name": "X", "nodes": {"a": {"text": "t", "options": [{"type": "rara"}, {}, {}, {}, {}, {}]}}}]}
	var s2: Node = DS.new()
	s2.load_from_dict(raw)
	s2.start("x")
	check(s2.current_options().size() == 4, "Máximo 4 opciones por nodo")
	check(s2.current_options()[0]["type"] == "continue", "Tipo desconocido -> continue")
	check(s2.relation_levels.size() == 5, "Niveles por defecto sin seed")
	check(s2.get_relation("x") == 100, "Primer encuentro: de Desconocido a Neutral")
	s2.free()
	s.free()


# --------------------------------------------------------------------------
# 6. Misión
# --------------------------------------------------------------------------
func _test_dialogue_quest() -> void:
	print("-- 6. Opción de misión")
	var s := _ds()
	s.start("mira")
	var req := []
	s.quest_requested.connect(func(q, a): req.append([q, a]))
	var chosen := []
	s.option_chosen.connect(func(n, oid, r): chosen.append(oid))
	var r: Dictionary = s.choose(1)
	check(r["ok"] and r["type"] == "quest", "Elegir [1] acepta la misión")
	check(r["quest_id"] == "q_sellar_grieta" and r["quest_action"] == "accept", "Misión q_sellar_grieta aceptada")
	check(r["reward"] == "Hoja de la grieta", "Recompensa: Hoja de la grieta")
	check(s.accepted_quests == ["q_sellar_grieta"], "Registrada en accepted_quests")
	check(req == [["q_sellar_grieta", "accept"]], "Señal quest_requested")
	check(chosen == ["take_guardian"], "Señal option_chosen")
	check(s.get_relation("mira") == 360 and r["relation"] == 360, "La misión sube la relación (+20)")
	check(s.active_node == "accept_guardian" and not r["ended"], "Avanza a accept_guardian")
	check(s.history_for("mira").any(func(h): return h["kind"] == "player" and h["text"] == "Yo me encargo del Guardián."), "Tu respuesta queda en el historial")
	s.free()
	# Integración con QuestService (misión disponible).
	var qs: Node = QS.new()
	qs.load_seed()
	var s2: Node = DS.new()
	s2.quest_service = qs
	s2.load_from_dict({"npcs": [{"id": "caz", "name": "Cazadora", "relation": 200, "nodes": {"intro": {"text": "Lobos.",
		"options": [{"id": "q", "type": "quest", "text": "Acepto.", "quest_id": "q_lobos_ceniza", "reward": "Capa"}]}}}]})
	s2.start("caz")
	var r2: Dictionary = s2.choose("q")
	check(r2["ok"] and (r2.get("quest_service", {}) as Dictionary).get("ok", false), "QuestService.accept se llama al aceptar")
	check(qs.get_quest("q_lobos_ceniza")["state"] == "active", "q_lobos_ceniza pasa a activa")
	check(r2["ended"] and not s2.is_active(), "Sin nodo siguiente: la conversación termina")
	s2.free()
	qs.free()


# --------------------------------------------------------------------------
# 7. Rama alternativa
# --------------------------------------------------------------------------
func _test_dialogue_branch() -> void:
	print("-- 7. Rama alternativa y reputación")
	var s := _ds()
	s.start("mira")
	var reps := []
	s.reputation_changed.connect(func(f, v): reps.append([f, v]))
	var r: Dictionary = s.choose(2)
	check(r["ok"] and r["type"] == "branch", "Elegir [2]: rama alternativa")
	check(s.get_reputation("ferrum") == 15 and r["reputation"]["ferrum"] == 15, "Reputación con Ferrum +15")
	check(reps == [["ferrum", 15]], "Señal reputation_changed")
	check(s.active_node == "branch_open", "Avanza a branch_open")
	var o: Array = s.current_options()
	check(o.size() == 2 and o[1]["type"] == "continue" and o[1]["badge"] == "", "Rama: opción de volver sin badge")
	var ended := []
	s.dialogue_ended.connect(func(n): ended.append(n))
	r = s.choose("side_ferrum")
	check(s.get_reputation("ferrum") == 40 and s.get_reputation("guardabosques") == 100, "Ferrum +25 y Guardabosques −20")
	check(s.get_relation("mira") == 300 and s.relation_name("mira") == "Aliada", "Relación con Mira −40 (sigue Aliada)")
	check(r["ended"] and ended == ["mira"] and not s.is_active(), "La rama cierra la conversación")
	s.free()


# --------------------------------------------------------------------------
# 8. Lore («Ya lo preguntaste»)
# --------------------------------------------------------------------------
func _test_dialogue_lore() -> void:
	print("-- 8. Preguntas de lore")
	var s := _ds()
	s.start("mira")
	check(s.is_asked("mira", "lore_ferrum") and not s.is_asked("mira", "lore_guardian"), "Seed: Ferrum ya preguntado, Guardián no")
	var r: Dictionary = s.choose(3)
	check(r["ok"] and r["type"] == "lore" and not r["first_time"], "Volver a preguntar está permitido (no es la primera vez)")
	check(s.active_node == "lore_ferrum", "Muestra el nodo de lore")
	var o: Array = s.current_options()
	check(o[0]["type"] == "lore" and not o[0]["asked"] and near(o[0]["opacity"], 1.0), "«¿Y el Guardián?» aún sin preguntar")
	r = s.choose(1)
	check(r["first_time"] and s.is_asked("mira", "lore_guardian"), "Preguntar el Guardián lo registra")
	check(s.active_node == "lore_guardian", "Nodo lore_guardian")
	r = s.choose(1)
	check(s.active_node == "intro", "«Entendido.» vuelve a intro")
	s.start("mira", "accept_guardian")
	o = s.current_options()
	check(o[0]["asked"] and o[0]["badge"] == "Ya lo preguntaste" and near(o[0]["opacity"], 0.5), "El mismo tema en otro nodo también se atenúa")
	check(not s.is_asked("gildas", "lore_guardian"), "Lo preguntado es por PNJ")
	s.free()


# --------------------------------------------------------------------------
# 9. Tienda, Mercado y opciones bloqueadas
# --------------------------------------------------------------------------
func _test_dialogue_shop_and_lock() -> void:
	print("-- 9. Tienda / Mercado y requisitos de relación")
	var s := _ds()
	s.start("mira")
	var shops := []
	s.shop_requested.connect(func(n, sh): shops.append([n, sh]))
	var r: Dictionary = s.choose(4)
	check(r["ok"] and r["type"] == "shop", "Elegir [4]: tienda")
	check(shops.size() == 1 and shops[0][0] == "mira" and shops[0][1]["window"] == "vendor_window", "Despacha la apertura de vendor_window")
	check(shops[0][1]["vendor_id"] == "mira_suministros", "Con el vendedor de suministros de Mira")
	check(r["ended"] and not s.is_active(), "Abrir la tienda cierra la conversación")
	s.start("gildas")
	var o: Array = s.current_options()
	check(o[1]["badge"] == "Mercado" and o[1]["shop"]["market"], "Gildas enlaza con el Mercado")
	check(o[2]["locked"] and o[2]["badge"] == "Requiere relación: Amistoso", "Rumor bloqueado: requiere Amistoso")
	check(near(o[2]["opacity"], 0.5) and o[2]["badge_color"] == "#ff8a8a", "Bloqueada atenuada y en rojo")
	r = s.choose(3)
	check(not r["ok"] and r["reason"] == "relation_too_low" and s.active_node == "intro", "No se puede elegir una opción bloqueada")
	s.change_relation("gildas", 60)
	o = s.current_options()
	check(not o[2]["locked"] and o[2]["badge"] == "", "Con relación Amistoso se desbloquea")
	r = s.choose(3)
	check(r["ok"] and s.active_node == "rumor", "El rumor ya se puede preguntar")
	s.start("gildas")
	r = s.choose(2)
	check(shops[-1][1]["window"] == "marketplace_window", "Mercado: despacha marketplace_window")
	s.free()


# --------------------------------------------------------------------------
# 10. Avanzar (Espacio) y errores
# --------------------------------------------------------------------------
func _test_dialogue_advance_and_errors() -> void:
	print("-- 10. Avanzar y errores")
	var s := _ds()
	check(s.choose(1)["reason"] == "not_active", "choose sin conversación activa")
	check(s.advance()["reason"] == "not_active", "advance sin conversación activa")
	s.start("mira", "lore_guardian")
	var r: Dictionary = s.advance()
	check(r["ok"] and r["action"] == "fragment", "Espacio revela el siguiente fragmento")
	r = s.advance()
	check(r["ok"] and r["action"] == "continue" and s.active_node == "intro", "Espacio con una sola opción «continue» avanza")
	s.reveal_all()
	r = s.advance()
	check(not r["ok"] and r["reason"] == "choice_required", "Con varias opciones hay que elegir")
	check(s.choose(9)["reason"] == "invalid_option", "Opción inexistente")
	s.load_from_dict({"npcs": [{"id": "m", "name": "M", "nodes": {"a": {"text": ["uno", "dos"]}}}]})
	s.start("m")
	s.advance()
	r = s.advance()
	check(r["action"] == "closed" and not s.is_active(), "Nodo sin opciones: Espacio cierra")
	s.start("m")
	s.end_dialogue()
	check(not s.is_active() and s.active_node == "", "end_dialogue limpia el estado")
	s.free()


# --------------------------------------------------------------------------
# 11. Historial y persistencia
# --------------------------------------------------------------------------
func _test_dialogue_history_persistence() -> void:
	print("-- 11. Historial y persistencia")
	var s := _ds()
	s.start("mira")
	s.choose(3)
	s.choose(1)
	var hist: Array = s.history_for("mira")
	check(hist.size() >= 4, "Historial con líneas del PNJ y del jugador")
	check(hist[0]["speaker"] == "Mira" and hist[0]["kind"] == "npc", "Primera línea: Mira")
	check(hist.any(func(h): return h["speaker"] == "Tú"), "Líneas del jugador como «Tú»")
	check(s.history_for("gildas").is_empty(), "Filtro por PNJ")
	var d: Dictionary = s.to_dict()
	check(d["asked"]["mira"].has("lore_guardian") and d["visited"]["mira"].has("lore_guardian"), "to_dict guarda preguntas y nodos visitados")
	var s2 := _ds()
	s2.from_dict(d)
	check(s2.is_asked("mira", "lore_guardian") and s2.is_visited("mira", "lore_guardian"), "from_dict restaura preguntas y visitas")
	check(s2.history.size() == s.history.size(), "from_dict restaura el historial")
	check(s2.get_relation("mira") == s.get_relation("mira"), "from_dict restaura la relación")
	var path := "user://test_dialogue_state.json"
	s.change_reputation("ferrum", 7)
	s.accepted_quests.append("q_x")
	check(s.save_state(path), "save_state escribe el archivo")
	var s3 := _ds()
	check(s3.load_state(path), "load_state lee el archivo")
	check(s3.get_reputation("ferrum") == 7 and s3.accepted_quests == ["q_x"], "Persistencia de reputación y misiones aceptadas")
	check(not s3.load_state("user://no_existe_dialogo.json"), "load_state sin archivo devuelve false")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	for i in DS.HISTORY_LIMIT + 10:
		s.history.append({"npc_id": "x", "speaker": "", "text": "", "kind": "system"})
	s._log("x", "", "fin", "system")
	check(s.history.size() == DS.HISTORY_LIMIT, "El historial se limita a %d líneas" % DS.HISTORY_LIMIT)
	s.free()
	s2.free()
	s3.free()


# --------------------------------------------------------------------------
# 12. DeathRecapService: recap de 5 s
# --------------------------------------------------------------------------
func _test_death_seed_and_recap() -> void:
	print("-- 12. DeathRecapService: seed y recap de los últimos 5 s")
	var s := _dr()
	check(s.abilities.size() == 4 and s.max_health == 15200 and near(s.window_s, 5.0), "Seed: 4 habilidades, vida 15.200, ventana 5 s")
	check(s.title == "Has caído" and s.subtitle == "El combate sigue · tu grupo aún puede ganar", "Título y subtítulo")
	check(s.note == "Sin penalización de equipo. Morir en una raid nunca te quita progreso.", "Nota de seguridad")
	check(s.state == DR.STATE_ALIVE and s.recap.is_empty(), "Empieza vivo y sin recap")
	var died := []
	s.died.connect(func(r): died.append(r))
	var r: Dictionary = s.present_seed()
	check(died.size() == 1 and s.state == DR.STATE_DEAD, "present_seed muere y emite died")
	var ev: Array = r["events"]
	check(ev.size() == 4, "4 impactos en los últimos 5 s (el de −7,5 s queda fuera)")
	check(ev.map(func(e): return e["time_text"]) == ["−4,8 s", "−3,1 s", "−1,0 s", "0 s"], "Tiempos relativos −4,8 · −3,1 · −1,0 · 0 s")
	check(ev.map(func(e): return e["label"]) == ["Sangrado ×3", "Golpe del Coloso", "Terremoto rúnico", "Esquirla perdida"], "Nombres (Sangrado ×3)")
	check(ev.map(func(e): return e["amount_text"]) == ["1.100", "6.400", "8.200", "2.900"], "Importes 1.100 · 6.400 · 8.200 · 2.900")
	check(ev.map(func(e): return e["avoidable"]) == [false, false, true, true], "Terremoto y Esquirla evitables")
	check(r["total"] == 18600 and r["total_text"] == "18.600", "Daño total 18.600")
	check(near(ev[0]["percent"], 5.91) and near(ev[1]["percent"], 34.41) and near(ev[2]["percent"], 44.09) and near(ev[3]["percent"], 15.59), "% del daño por impacto")
	var sum := 0.0
	for e in ev:
		sum += float(e["percent"])
	check(near(sum, 100.0), "Los porcentajes suman 100")
	check(near(ev[0]["bar_ratio"], 0.072) and near(ev[1]["bar_ratio"], 0.421) and near(ev[2]["bar_ratio"], 0.539) and near(ev[3]["bar_ratio"], 0.191), "Barras sobre la vida máxima (8 · 42 · 54 · 19 %)")
	check(r["avoidable_total"] == 11100 and near(r["avoidable_percent"], 59.68), "Evitable: 11.100 (59,7 %)")
	var by: Array = r["by_ability"]
	check(by.size() == 4 and by[0]["ability"] == "terremoto_runico", "Desglose por habilidad ordenado (terremoto primero)")
	check(by[3]["ability"] == "sangrado" and by[3]["hits"] == 3, "Sangrado con 3 golpes")
	check(near(s.damage_percent("golpe_coloso"), 34.41) and s.damage_percent("nada") == 0.0, "damage_percent por habilidad")
	check(r["killing_blow"]["ability"] == "esquirla_perdida", "Golpe de gracia: Esquirla perdida")
	check(r["overkill"] == 3400, "Sobredaño 3.400")
	check(s.avoidable_events().size() == 2, "avoidable_events: 2")
	check(s.is_avoidable("terremoto_runico") and not s.is_avoidable("sangrado") and not s.is_avoidable("desconocida"), "is_avoidable por habilidad")
	check(r["note"] == s.note and r["title"] == "Has caído", "El recap lleva título y nota")
	s.free()


# --------------------------------------------------------------------------
# 13. Consejos tácticos
# --------------------------------------------------------------------------
func _test_death_tips() -> void:
	print("-- 13. Generador de consejos tácticos")
	var s := _dr()
	s.present_seed()
	var tip: Dictionary = s.recap["tip"]
	check(tip["kind"] == "defensive" and tip["defensive"] == "escudo" and tip["ability"] == "terremoto_runico", "Consejo: escudo listo contra el terremoto")
	check(tip["text"] == "Tu escudo [Shift+4] estaba listo y habría absorbido el terremoto. Muévete a la izquierda cuando aparezca la alerta roja.", "Texto exacto del consejo del diseño")
	check(tip["segments"].size() == 3 and tip["segments"][1]["key"] == "⇧4", "Segmentos con la tecla ⇧4")
	var changed := []
	s.recap_changed.connect(func(r): changed.append(r))
	s.set_defensive_ready("escudo", false)
	tip = s.recap["tip"]
	check(changed.size() == 1, "Cambiar un defensivo recalcula el recap")
	check(tip["kind"] == "avoidable" and tip["text"] == "Esquivar el terremoto te habría ahorrado 8.200 de daño. Muévete a la izquierda cuando aparezca la alerta roja.", "Sin escudo: cuánto ahorrarías esquivando")
	s.set_defensive_ready("pocion", true)
	check(s.recap["tip"]["kind"] == "avoidable", "La poción (3.000) no absorbe el terremoto (8.200)")
	s.set_defensive_ready("escudo", true)
	check(s.recap["tip"]["defensive"] == "escudo", "Elige el defensivo listo que basta")
	s.present({"events": [{"t": -3.0, "ability": "sangrado", "amount": 3000, "hits": 5}, {"t": 0.0, "ability": "golpe_coloso", "amount": 4000}]})
	tip = s.recap["tip"]
	check(tip["kind"] == "dot" and tip["text"].begins_with("Sangrado te hizo 3.000 en 5 golpes"), "Sangrado ≥ 30 %: consejo de disipar")
	s.present({"events": [{"t": -2.0, "ability": "golpe_coloso", "amount": 9000}, {"t": 0.0, "ability": "golpe_coloso", "amount": 9000}]})
	tip = s.recap["tip"]
	check(tip["kind"] == "sustained" and tip["text"].contains("18.000"), "Sin evitables: daño sostenido")
	check(s.recap["by_ability"].size() == 1 and s.recap["by_ability"][0]["hits"] == 2, "Desglose agrupa la misma habilidad")
	s.present({"events": [{"t": -9.0, "ability": "golpe_coloso", "amount": 100}]})
	check(s.recap["events"].is_empty() and s.recap["tip"]["kind"] == "none", "Nada en los últimos 5 s: consejo neutro")
	s.present({"events": [{"t": 0.0, "amount": 500}], "tip": "Consejo propio"})
	check(s.recap["tip"]["kind"] == "custom" and s.recap["tip"]["text"] == "Consejo propio", "Consejo personalizado desde los datos")
	s.present({"events": [{"t": -1.0, "name": "Lluvia ácida", "amount": 2000, "avoidable": true, "hint": "Sal del charco."}]})
	check(s.recap["events"][0]["name"] == "Lluvia ácida" and s.recap["events"][0]["avoidable"], "Habilidad nueva por nombre con flag evitable")
	check(s.recap["tip"]["text"].ends_with("Sal del charco."), "El consejo usa la pista de la habilidad nueva")
	check(s.abilities.has("terremoto_runico") and s.seed_data.has("events"), "present conserva el seed original")
	s.free()


# --------------------------------------------------------------------------
# 14. Flujo en vivo (record_damage + die + tick)
# --------------------------------------------------------------------------
func _test_death_live_flow() -> void:
	print("-- 14. Registro en vivo")
	var s := _dr()
	s.tick(10.0)
	s.record_damage("golpe_coloso", 1000)
	s.tick(5.0)
	s.record_damage("terremoto_runico", 5000)
	s.tick(1.0)
	s.record_damage("sangrado", 300, 2)
	check(s.damage_log.size() == 3 and near(s.damage_log[0]["at"], 10.0), "record_damage usa el reloj")
	var r: Dictionary = s.die()
	check(near(s.death_at, 16.0) and r["events"].size() == 2, "die(): solo entra lo de los últimos 5 s (el golpe de −6 s queda fuera)")
	check(r["events"][0]["time_text"] == "−1,0 s" and r["events"][1]["time_text"] == "0 s", "Tiempos relativos al momento de morir")
	check(r["events"][1]["label"] == "Sangrado ×2", "Golpes múltiples")
	check(near(s.respawn_remaining, 12.0), "La cuenta atrás empieza en 12 s")
	s.reset()
	for i in 50:
		s.tick(1.0)
		s.record_damage("sangrado", 10)
	check(s.damage_log.size() <= int(DR.LOG_KEEP_S) + 1, "El registro descarta lo de hace más de 30 s")
	s.tick(-1.0)
	check(near(s.clock, 50.0), "tick ignora deltas negativos")
	s.free()


# --------------------------------------------------------------------------
# 15. Resurrección
# --------------------------------------------------------------------------
func _test_resurrection() -> void:
	print("-- 15. Canalización de resurrección")
	var s := _dr()
	check(not s.start_resurrection("Brisa", 4.0), "No se puede resucitar a alguien vivo")
	s.present_seed()
	check(s.is_resurrecting() and s.resurrection["caster"] == "Brisa", "Brisa está resucitando")
	check(near(s.resurrection_progress(), 0.6) and near(s.resurrection_remaining(), 1.6), "Progreso 60 % · 1,6 s restantes")
	check(s.resurrection_title() == "Brisa te está resucitando", "«Brisa te está resucitando»")
	check(s.resurrection_text() == "Listo en 1,6 s · aceptar automáticamente ✓", "«Listo en 1,6 s · aceptar automáticamente ✓»")
	var prog := []
	s.resurrection_progressed.connect(func(p, rem): prog.append(p))
	var res := []
	s.resurrected.connect(func(c): res.append(c))
	s.tick(1.0)
	check(near(s.resurrection_remaining(), 0.6) and prog.size() == 1, "tick avanza la canalización")
	check(s.resurrection_text() == "Listo en 0,6 s · aceptar automáticamente ✓", "Texto actualizado")
	s.tick(1.0)
	check(res == ["Brisa"] and s.state == DR.STATE_REVIVED, "Aceptación automática: resucitas al terminar")
	check(s.resurrection_state() == DR.RES_ACCEPTED and s.resurrection_title() == "Resucitado por Brisa", "Estado aceptado")
	s.tick(5.0)
	check(s.state == DR.STATE_REVIVED, "Vivo: tick no cambia nada")
	# Sin aceptación automática.
	s.present_seed()
	s.set_auto_accept(false)
	check(s.resurrection_text().ends_with("✗"), "Aceptación automática desactivada (✗)")
	var ready := []
	s.resurrection_ready.connect(func(c): ready.append(c))
	check(s.accept_resurrection()["reason"] == "not_ready", "No se acepta antes de terminar")
	s.tick(2.0)
	check(ready == ["Brisa"] and s.resurrection_state() == DR.RES_READY and s.state == DR.STATE_DEAD, "Termina y espera tu aceptación")
	check(s.resurrection_title() == "Brisa te ha resucitado", "«Brisa te ha resucitado»")
	check(s.accept_resurrection()["ok"] and s.state == DR.STATE_REVIVED, "Aceptar te devuelve al combate")
	# Activar la automática cuando ya está lista.
	s.present_seed()
	s.set_auto_accept(false)
	s.tick(2.0)
	s.set_auto_accept(true)
	check(s.state == DR.STATE_DEAD, "Activar la automática tras terminar no revive sola (ya está lista)")
	# Rechazar e interrumpir.
	s.present_seed()
	var cancels := []
	s.resurrection_cancelled.connect(func(c, why): cancels.append(why))
	check(s.decline_resurrection()["ok"] and s.resurrection_state() == DR.RES_DECLINED, "Rechazar la resurrección")
	check(s.resurrection_title() == "Rechazaste la resurrección", "Título tras rechazar")
	check(not s.decline_resurrection()["ok"], "No se rechaza dos veces")
	s.present_seed()
	check(s.cancel_resurrection() and s.resurrection_state() == DR.RES_CANCELLED, "El lanzador puede ser interrumpido")
	check(s.resurrection_title() == "Brisa ha dejado de resucitarte" and s.resurrection_text() == "Lanzamiento interrumpido", "Textos de interrupción")
	check(cancels == ["declined", "interrupted"], "Señales resurrection_cancelled con motivo")
	check(not s.cancel_resurrection(), "Nada que interrumpir")
	s.tick(5.0)
	check(s.state == DR.STATE_DEAD, "Interrumpida: sigues muerto")
	check(s.start_resurrection("Sasha", 2.0, true) and s.resurrection["caster"] == "Sasha", "Otro aliado puede empezar a resucitarte")
	s.tick(2.0)
	check(s.state == DR.STATE_REVIVED, "Sasha te resucita")
	s.free()


# --------------------------------------------------------------------------
# 16. Reaparición y repetición
# --------------------------------------------------------------------------
func _test_respawn_and_replay() -> void:
	print("-- 16. Reaparición y repetición de 10 s")
	var s := _dr()
	check(s.respawn()["reason"] == "not_dead" and s.request_replay()["reason"] == "alive", "Vivo: ni reaparecer ni repetición")
	s.present_seed()
	check(s.respawn_label() == "Reaparecer en el punto de control", "Punto de control por defecto")
	check(s.respawn_countdown_text() == "0:12" and not s.can_respawn(), "0:12 y aún no se puede reaparecer")
	var r: Dictionary = s.respawn()
	check(not r["ok"] and r["reason"] == "cooldown" and near(r["remaining"], 12.0), "Reaparecer antes de tiempo: cooldown")
	var ready := []
	s.respawn_ready.connect(func(): ready.append(true))
	s.cancel_resurrection()
	s.tick(6.5)
	check(s.respawn_countdown_text() == "0:06", "Cuenta atrás 0:06")
	s.tick(6.0)
	check(s.can_respawn() and ready.size() == 1 and s.respawn_countdown_text() == "Ahora", "A los 12 s se puede reaparecer")
	var sp := []
	s.respawned.connect(func(p): sp.append(p))
	r = s.respawn()
	check(r["ok"] and r["point"] == "checkpoint" and not r["equipment_penalty"], "Reaparece en el punto de control sin penalización")
	check(sp == ["checkpoint"] and s.state == DR.STATE_RESPAWNED, "Señal respawned")
	check(not s.has_equipment_penalty(), "Nunca hay penalización de equipo")
	s.present_seed()
	check(s.set_respawn_point("camp") and s.respawn_label() == "Reaparecer en el campamento", "Campamento como punto de reaparición")
	check(not s.set_respawn_point("luna"), "Punto desconocido rechazado")
	s.tick(12.0)
	check(s.state == DR.STATE_REVIVED, "(la resurrección del seed llega antes que la cuenta atrás)")
	s.present_seed()
	s.set_auto_accept(false)
	s.tick(12.0)
	check(s.resurrection_state() == DR.RES_READY and s.can_respawn(), "Resurrección pendiente y reaparición disponibles a la vez")
	r = s.respawn()
	check(r["ok"] and s.resurrection_state() == DR.RES_READY, "Reaparecer con una resurrección pendiente")
	s.present_seed()
	var reps := []
	s.replay_requested.connect(func(sec, evs): reps.append([sec, evs.size()]))
	r = s.request_replay()
	check(r["ok"] and near(r["seconds"], 10.0) and r["events"].size() == 5, "Repetición de 10 s con 5 impactos (incluye −7,5 s)")
	check(reps == [[10.0, 5]] and s.last_replay == r, "Señal replay_requested")
	check(s.replay_label() == "Ver repetición de 10 s", "«Ver repetición de 10 s»")
	s.free()


func _test_formatting() -> void:
	print("-- 17. Formato")
	check(DR.format_offset(-4.8) == "−4,8 s" and DR.format_offset(0.0) == "0 s" and DR.format_offset(-0.01) == "0 s", "format_offset")
	check(DR.format_offset(-10.0) == "−10,0 s" and DR.format_offset(1.5) == "+1,5 s", "format_offset con decenas y positivos")
	check(DR.format_countdown(12.0) == "0:12" and DR.format_countdown(75.0) == "1:15" and DR.format_countdown(0.2) == "0:01" and DR.format_countdown(0.0) == "0:00", "format_countdown")
	check(DR.format_amount(8200) == "8.200" and DR.format_amount(1234567) == "1.234.567" and DR.format_amount(900) == "900" and DR.format_amount(-1500) == "-1.500", "format_amount")
	check(DR._num(1.6) == "1,6" and DR._num(10.0) == "10", "_num con coma decimal")


# --------------------------------------------------------------------------
# 18. DialogueWindow
# --------------------------------------------------------------------------
func _test_dialogue_window() -> void:
	print("-- 18. DialogueWindow (letterbox, opciones y teclado)")
	var s := _ds()
	var w = DialogueScene.instantiate()
	check(w.get_script() != null, "DialogueWindow.tscn con script")
	w.service = s
	root.add_child(w)
	w.initialize_window({"npc_id": "mira", "dialogue_node_id": "intro"})
	await _frames(3)
	var vp: Vector2 = w.get_viewport_rect().size
	var k: float = vp.y / 810.0
	check(s.get_parent() == w, "El servicio inyectado se cuelga de la ventana")
	check(w.visible and s.active_node == "intro", "Ventana visible en intro")
	check(near(w.top_bar.size.y, round(70 * k), 1.0) and w.top_bar.color == Color.BLACK, "Franja superior negra de 70 px (escalada)")
	check(near(w.bottom_bar.size.y, round(40 * k), 1.0) and near(w.bottom_bar.position.y + w.bottom_bar.size.y, vp.y, 1.0), "Franja inferior negra de 40 px pegada abajo")
	check(near(w.shade.size.y, 540 * k, 1.0) and w.shade.alpha_at(0.0) > 0.96 and w.shade.alpha_at(1.0) < 0.01, "Degradado inferior de 540 px")
	check(near(w.stage.scale.x, minf(vp.x / 1440.0, vp.y / 810.0)), "Escenario 1440×810 escalado al viewport")
	check(w.portrait.size == Vector2(220, 300) and near(w.portrait.position.x, 160), "Retrato 220×300 a la izquierda")
	check(w.portrait.shape().size() > 40, "Retrato con arco superior")
	check(w.name_label.text == "Mira" and w.name_label.get_theme_font_size("font_size") == 26, "Nombre «Mira» a 26 px")
	check(w.title_label_npc.text == "Exploradora del Umbral", "Subtítulo «Exploradora del Umbral»")
	check(w.relation_label.text == "Aliada", "Relación: Aliada")
	var lit: int = w.relation_ticks.filter(func(t): return t.color == Color("#46e3c1")).size()
	check(w.relation_ticks.size() == 5 and lit == 3, "Medidor de 5 segmentos con 3 encendidos")
	check(w.text_label.get_theme_font_size("normal_font_size") == 21, "Texto a 21 px")
	check(w.text_label.text.begins_with("La grieta del Vado Roto") and w.text_label.text.contains("▍"), "Texto con cursor ▍ mientras quedan fragmentos")
	check(w.option_rows.size() == 4, "4 filas de opciones")
	check(w.option_rows[0].get_meta("active") and not w.option_rows[1].get_meta("active"), "La opción 1 empieza resaltada (cian)")
	var sb: StyleBoxFlat = w.option_rows[0].get_theme_stylebox("normal")
	check(sb.border_color == Color("#46e3c1") and sb.border_width_left == 2, "Borde cian #46e3c1 en la resaltada")
	check(near(sb.bg_color.a, 0.12) and near(sb.bg_color.g, 227 / 255.0), "Fondo cian al 12 %")
	var sb2: StyleBoxFlat = w.option_rows[1].get_theme_stylebox("normal")
	check(sb2.border_width_left == 0 and near(sb2.bg_color.a, 0.85), "Fondo rgba(18,26,32,0.85) en las demás")
	check(near(w.option_rows[2].modulate.a, 0.5) and near(w.option_rows[0].modulate.a, 1.0), "«Ya lo preguntaste» a opacidad 0.5")
	check((w.option_rows[0].find_child("Badge", true, false) as Label).text == "Acepta misión · Hoja de la grieta ▲", "Badge de misión en la fila 1")
	check((w.option_rows[2].find_child("Badge", true, false) as Label).text == "Ya lo preguntaste", "Badge «Ya lo preguntaste» en la fila 3")
	check((w.option_rows[3].find_child("Badge", true, false) as Label).text == "Tienda", "Badge «Tienda» en la fila 4")
	check((w.option_rows[0].find_child("Key", true, false) as Label).text == "1" and (w.option_rows[3].find_child("Key", true, false) as Label).text == "4", "Teclas [1]…[4]")
	check((w.option_rows[0].find_child("Icon", true, false)).bg == Color("#8a6a2b"), "Icono temático de misión")
	check(w.option_rows[0].custom_minimum_size.y == 46, "Filas de 46 px")
	check(w.mode_label.text == DialogueWindowConst.MODE_HINT, "Nota «Modo conversación…»")
	check(w.history_chip != null and w.advance_chip != null and w.subtitles_chip != null, "Chips Historial [H] · Avanzar [Espacio] · Subtítulos")
	check((w.subtitles_chip.find_child("Text", true, false) as Label).text == "Subtítulos: grandes", "«Subtítulos: grandes»")
	# Teclado: flechas.
	var hl := []
	w.highlight_changed.connect(func(i): hl.append(i))
	check(w.handle_key(KEY_DOWN) and w.highlighted == 1, "↓ mueve el resaltado a la opción 2")
	check(w.option_rows[1].get_meta("active") and not w.option_rows[0].get_meta("active"), "El estilo activo sigue al resaltado")
	w.handle_key(KEY_UP)
	w.handle_key(KEY_UP)
	check(w.highlighted == 3 and hl == [1, 0, 3], "↑ da la vuelta a la última opción")
	# Espacio: fragmento.
	w._unhandled_key_input(_key(KEY_SPACE))
	check(s.fragment_index == 1 and not w.text_label.text.contains("▍"), "Espacio revela el siguiente fragmento (sin cursor)")
	check(w.text_label.text.contains("perderemos el nuestro hacia ellos"), "Texto completo visible")
	# 3: lore.
	var sel := []
	w.option_selected.connect(func(oid, r): sel.append(oid))
	w._unhandled_key_input(_key(KEY_3))
	await _frames(1)
	check(sel == ["ask_ferrum"] and s.active_node == "lore_ferrum", "[3] pregunta por Ferrum")
	check(w.option_rows.size() == 2 and w.highlighted == 0, "Nuevo nodo con 2 opciones y resaltado reiniciado")
	# Enter elige el resaltado.
	w.handle_key(KEY_DOWN)
	w.handle_key(KEY_ENTER)
	await _frames(1)
	check(s.active_node == "intro", "Enter elige la opción resaltada (volver a la grieta)")
	# H: historial.
	var ht := []
	w.history_toggled.connect(func(v): ht.append(v))
	w.handle_key(KEY_H)
	check(w.history_panel.visible and w.history_list.get_child_count() > 0, "H abre el historial con líneas")
	w.handle_key(KEY_ESCAPE)
	check(not w.history_panel.visible and s.is_active() and ht == [true, false], "Esc con el historial abierto solo lo cierra")
	w.cycle_subtitles()
	check(w.subtitle_size == "enormes" and w.text_label.get_theme_font_size("normal_font_size") == 25, "Subtítulos ajustables")
	w.set_subtitle_size("grandes")
	# 2: rama alternativa con feedback.
	w.handle_key(KEY_2)
	await _frames(1)
	check(s.active_node == "branch_open" and w.feedback_label.text.contains("Ferrum 15"), "[2] rama: feedback de reputación")
	# Tecla fuera de rango.
	check(not w.handle_key(KEY_4), "[4] no existe en un nodo de 2 opciones")
	check(not w.handle_key(KEY_Z), "Teclas sin función no se consumen")
	# 1 vuelve; 4 abre tienda y cierra.
	w.handle_key(KEY_2)
	await _frames(1)
	check(s.active_node == "intro", "Volver a intro")
	var shops := []
	w.shop_opened.connect(func(n, sh): shops.append(sh["window"]))
	var closed := []
	w.conversation_closed.connect(func(n): closed.append(n))
	w.handle_key(KEY_KP_4)
	await _frames(1)
	check(shops == ["vendor_window"], "[4] (teclado numérico) abre la tienda")
	check(closed == ["mira"] and not w.visible and not s.is_active(), "La conversación termina y la ventana se oculta")
	# Reabrir y Esc.
	w.initialize_window({"npc_id": "mira"})
	await _frames(1)
	check(w.visible and s.active_node == "intro", "initialize_window reabre la conversación")
	check(w.relation_label.text == "Aliada", "Relación refrescada")
	w._unhandled_key_input(_key(KEY_ESCAPE))
	await _frames(1)
	check(not w.visible and not s.is_active() and closed.size() == 2, "Esc cierra la conversación")
	# Espacio en una despedida sin opciones cierra.
	w.start_dialogue("mira", "lore_guardian")
	w.handle_key(KEY_SPACE)
	w.handle_key(KEY_SPACE)
	await _frames(1)
	check(s.active_node == "intro" and w.visible, "Espacio continúa con la única opción")
	# Clic en una opción.
	w.option_rows[0].pressed.emit()
	await _frames(1)
	check(s.active_node == "accept_guardian" and s.accepted_quests.has("q_sellar_grieta"), "Clic en la opción 1 acepta la misión")
	check(w.feedback_label.text.begins_with("Misión aceptada"), "Feedback «Misión aceptada»")
	check(w.relation_label.text == "Aliada" and s.get_relation("mira") > 340, "La relación sube al aceptar")
	# Bloqueada en la ventana.
	w.start_dialogue("gildas")
	await _frames(1)
	check(w.name_label.text == "Gildas" and w.relation_label.text == "Neutral", "Gildas · Neutral")
	w.handle_key(KEY_3)
	check(s.active_node == "intro" and w.feedback_label.text.contains("relación"), "Opción bloqueada: aviso y sin avanzar")
	w.close_dialogue()
	w.queue_free()
	await _frames(1)


# --------------------------------------------------------------------------
# 19. DeathWindow
# --------------------------------------------------------------------------
func _test_death_window() -> void:
	print("-- 19. DeathWindow (recap, resurrección, R y Esc)")
	var s := _dr()
	var w = DeathScene.instantiate()
	check(w.get_script() != null, "DeathWindow.tscn con script")
	w.service = s
	root.add_child(w)
	w.initialize_window({})
	await _frames(3)
	check(s.state == DR.STATE_DEAD and w.visible, "Muestra el recap del seed")
	var mat: ShaderMaterial = w.filter_rect.material
	check(mat != null and mat.shader != null, "Filtro del mundo con shader")
	check(near(mat.get_shader_parameter("grayscale"), 1.0) and near(mat.get_shader_parameter("brightness"), 0.55), "grayscale(1) brightness(0.55)")
	check(mat.shader.code.contains("hint_screen_texture"), "El filtro lee la pantalla de detrás")
	check(w.title_text.text == "Has caído" and w.title_text.get_theme_font_size("font_size") == 48, "«Has caído» a 48 px")
	check(w.title_text.get_theme_constant("shadow_outline_size") >= 6, "Título con sombra profunda")
	check(w.subtitle_label.text == "El combate sigue · tu grupo aún puede ganar", "Subtítulo")
	check(w.recap_caps.text == "ÚLTIMOS 5 SEGUNDOS", "Cabecera «Últimos 5 segundos»")
	check(near(w.recap_card.position.x, 330) and near(w.recap_card.position.y, 220) and w.recap_card.custom_minimum_size.x == 460, "Tarjeta izquierda en (330, 220) de 460 px")
	check(near(w.options_col.position.x, 810) and w.options_col.custom_minimum_size.x == 300, "Columna de opciones en x 810 de 300 px")
	check(w.event_rows.size() == 4, "4 impactos en la tarjeta")
	var times: Array = w.event_rows.map(func(r): return (r.find_child("Time", true, false) as Label).text)
	check(times == ["−4,8 s", "−3,1 s", "−1,0 s", "0 s"], "Timestamps en la tarjeta")
	var amounts: Array = w.event_rows.map(func(r): return (r.find_child("Amount", true, false) as Label).text)
	check(amounts == ["1.100", "6.400", "8.200", "2.900"], "Importes en rojo")
	check((w.event_rows[0].find_child("Amount", true, false) as Label).get_theme_color("font_color") == Color("#ff8a8a"), "Importe #ff8a8a")
	var chips: Array = w.event_rows.filter(func(r): return r.find_child("Avoidable", true, false) != null)
	check(chips.size() == 2 and chips[0].get_meta("ability") == "terremoto_runico", "Chips «evitable» en Terremoto y Esquirla")
	var chip_lbl: Label = chips[0].find_child("Avoidable", true, false).find_child("Text", true, false)
	check(chip_lbl.text == "evitable" and chip_lbl.get_theme_color("font_color") == Color("#f5c35b"), "Chip ámbar #f5c35b")
	var bar = w.event_rows[2].find_child("Bar", true, false)
	check(bar != null and near(bar.ratio, 0.539) and bar.fill == Color("#e25555"), "Barra roja del terremoto al 54 %")
	check(w.tip_panel.visible and w.tip_label.text.contains("⇧4") and w.tip_label.text.contains("escudo"), "Consejo con la tecla ⇧4")
	var tsb: StyleBoxFlat = w.tip_panel.get_theme_stylebox("panel")
	check(near(tsb.border_color.g, 227 / 255.0) and tsb.border_width_left >= 1, "Caja de consejo con borde cian")
	check(w.res_card.visible and w.res_title.text == "Brisa te está resucitando", "Tarjeta «Brisa te está resucitando»")
	check(near(w.res_bar.ratio, 0.6) and w.res_text.text == "Listo en 1,6 s · aceptar automáticamente ✓", "Barra al 60 % y «Listo en 1,6 s»")
	var rsb: StyleBoxFlat = w.res_card.get_theme_stylebox("panel")
	check(rsb.border_color == Color("#46e3c1"), "Tarjeta de resurrección con borde cian")
	check((w.respawn_button.find_child("Text", true, false) as Label).text == "Reaparecer en el punto de control" and w.respawn_time.text == "0:12", "«Reaparecer en el punto de control 0:12»")
	check(w.respawn_button.disabled and w.respawn_button.custom_minimum_size.y == 48, "Botón de 48 px bloqueado durante la cuenta atrás")
	check((w.replay_button.find_child("Text", true, false) as Label).text == "Ver repetición de 10 s" and (w.replay_button.find_child("Key", true, false) as Label).text == "R", "«Ver repetición de 10 s [R]»")
	check(w.note_label.text == "Sin penalización de equipo. Morir en una raid nunca te quita progreso.", "Leyenda de protección de equipo")
	# R
	var rep := []
	w.replay_opened.connect(func(sec, evs): rep.append([sec, evs.size()]))
	w._unhandled_key_input(_key(KEY_R))
	check(rep == [[10.0, 5]] and w.replay_label.visible, "R abre la repetición de 10 s")
	# Esc
	var tog := []
	w.recap_toggled.connect(func(v): tog.append(v))
	w._unhandled_key_input(_key(KEY_ESCAPE))
	check(not w.recap_card.visible and w.visible, "Esc oculta el recap (la pantalla sigue)")
	w.handle_key(KEY_ESCAPE)
	check(w.recap_card.visible and tog == [false, true], "Esc lo vuelve a mostrar")
	# Enter durante la cuenta atrás.
	var rc := []
	w.respawn_chosen.connect(func(r): rc.append(r))
	w.handle_key(KEY_ENTER)
	check(rc.size() == 1 and not rc[0]["ok"] and s.state == DR.STATE_DEAD, "Enter antes de tiempo no reaparece")
	# A: aceptación manual y Enter acepta.
	w.handle_key(KEY_A)
	check(not s.resurrection["auto_accept"] and w.res_text.text.ends_with("✗"), "A desactiva la aceptación automática")
	s.tick(1.0)
	w._process(0.0)
	check(near(w.res_bar.ratio, 0.85) and w.res_text.text.begins_with("Listo en 0,6 s"), "La barra avanza con el tiempo")
	check(w.respawn_time.text == "0:11", "Cuenta atrás 0:11")
	s.tick(1.0)
	await _frames(1)
	check(w.res_accept_button.visible and w.res_title.text == "Brisa te ha resucitado", "Terminada: botón Aceptar visible")
	var acc := []
	w.resurrection_accepted.connect(func(c): acc.append(c))
	var closed := []
	w.death_screen_closed.connect(func(r): closed.append(r))
	w.handle_key(KEY_ENTER)
	await _frames(1)
	check(acc == ["Brisa"] and s.state == DR.STATE_REVIVED, "Enter acepta la resurrección")
	check(closed == ["resurrected"] and not w.visible and w.close_reason == "resurrected", "La pantalla se cierra al resucitar")
	# Reaparecer tras la cuenta atrás.
	w.initialize_window({})
	await _frames(1)
	check(w.visible and s.state == DR.STATE_DEAD and w.recap_card.visible, "Nueva muerte: la pantalla vuelve")
	s.cancel_resurrection()
	await _frames(1)
	check(w.res_title.text == "Brisa ha dejado de resucitarte" and near(w.res_bar.ratio, 0.6), "Resurrección interrumpida en la tarjeta")
	s.tick(12.0)
	w._process(0.0)
	check(not w.respawn_button.disabled and w.respawn_time.text == "Ahora", "A los 12 s: «Ahora» y botón activo")
	w.respawn_button.pressed.emit()
	await _frames(1)
	check(s.state == DR.STATE_RESPAWNED and closed[-1] == "respawned" and not w.visible, "Clic en reaparecer: reapareces y se cierra")
	# Recap a medida sin resurrección.
	w.initialize_window({"recap": {"events": [{"t": -0.5, "name": "Caída", "amount": 20000}], "max_health": 10000,
		"respawn": {"seconds": 0, "point": "camp"}}})
	await _frames(1)
	check(w.event_rows.size() == 1 and not w.res_card.visible, "Recap a medida: 1 impacto y sin resurrección")
	check(near((w.event_rows[0].find_child("Bar", true, false)).ratio, 1.0), "La barra se limita al 100 %")
	check((w.respawn_button.find_child("Text", true, false) as Label).text == "Reaparecer en el campamento" and not w.respawn_button.disabled, "Campamento disponible al instante")
	check(DeathWindowConst.tip_bbcode({"segments": [{"text": "a[b]"}, {"key": "R"}]}).contains("[lb]b]") , "tip_bbcode escapa corchetes")
	w.handle_key(KEY_SPACE)
	await _frames(1)
	check(s.state == DR.STATE_RESPAWNED and not w.visible, "Espacio reaparece cuando está disponible")
	w.queue_free()
	await _frames(1)


const DialogueWindowConst = preload("res://ui/windows/DialogueWindow/DialogueWindow.gd")
const DeathWindowConst = preload("res://ui/windows/DeathWindow/DeathWindow.gd")
