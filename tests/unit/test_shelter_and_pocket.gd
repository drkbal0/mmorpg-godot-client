extends SceneTree
## Suite headless (UI v2.4 Paso 8): Refugio «El Nido» en corte lateral, modo Construir,
## Producción, Expediciones, Pispa, Mejoras, almacén central con dividendos de PNJ
## y Refugio de bolsillo + atajo [H].
## Run: Godot --headless --path clients/godot-mmo-client -s tests/unit/test_shelter_and_pocket.gd
## Exit code 0 = todo PASS.

const SS = preload("res://shared-core/ShelterService.gd")
const KS = preload("res://shared-core/KnowledgeService.gd")
const ShelterScene = preload("res://ui/windows/ShelterWindow/ShelterWindow.tscn")
const PocketScene = preload("res://ui/windows/ShelterWindow/ShelterPocket.tscn")

const MIN_CHECKS := 160

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
	print("== [TEST] Refugio «El Nido» (corte lateral, construir, producción, expediciones, Pispa) + bolsillo ==")
	await _test_registry_and_shortcut()
	_test_side_cut_model()
	_test_dig_and_secret()
	_test_build_fusion_and_neighbors()
	_test_workers_ideal()
	_test_production_and_bottlenecks()
	_test_expeditions()
	_test_pispa()
	_test_dividends()
	_test_upgrades_and_offline()
	await _test_window()
	await _test_pocket()
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


func _new_service() -> Node:
	var s: Node = SS.new()
	s.roll_override = 10.0
	return s


# --------------------------------------------------------------------------
func _test_registry_and_shortcut() -> void:
	print("-- Registro [H] -> shelter, menú común y UIInputRouter")
	var Registry = load("res://ui/orchestration/UIWindowRegistry.gd")
	var UITypes = load("res://ui/types/UITypes.gd")
	var reg: Node = Registry.new()
	check(reg.is_registered("shelter"), "UIWindowRegistry: «shelter» registrada")
	check(reg.get_metadata("shelter").scene_path == "res://ui/windows/ShelterWindow/ShelterWindow.tscn", "shelter -> ShelterWindow.tscn")
	check(ResourceLoader.exists(reg.get_metadata("shelter").scene_path), "La escena del Refugio existe")
	check(reg.get_metadata("shelter").category == UITypes.WindowCategory.GAME_WINDOW, "shelter es GAME_WINDOW")
	check(reg.get_shortcut_keys("shelter") == [KEY_H], "shelter -> [KEY_H]")
	check(reg.get_window_for_key(KEY_H) == "shelter", "KEY_H resuelve a «shelter»")
	check(reg.get_window_for_key(KEY_N) == "powers", "KEY_N sigue resolviendo a «powers»")
	check(reg.is_registered("shelter_pocket") and ResourceLoader.exists(reg.get_metadata("shelter_pocket").scene_path), "shelter_pocket registrada y su escena existe")
	check(reg.get_shortcut_keys("shelter_pocket") == [], "El bolsillo no roba la tecla H al refugio completo")
	check(reg.is_registered("shelter_lobby"), "El lobby de personajes sigue registrado")

	var bar = load("res://ui/menu/menu_bar.tscn").instantiate()
	root.add_child(bar)
	check(bar.get_tab("refugio")["window"] == "shelter" and bar.get_shortcut("refugio") == "H", "Menú: pestaña Refugio [H] -> shelter")
	var nav := [""]
	bar.navigation_requested.connect(func(w: String, _p: Dictionary) -> void: nav[0] = w)
	check(bar.handle_shortcut(_key(KEY_H)) and nav[0] == "shelter", "Menú: [H] navega a shelter")
	bar.queue_free()

	var router: Node = load("res://ui/orchestration/UIInputRouter.gd").new()
	var orch := FakeOrchestrator.new()
	orch.registry = reg
	check(router.handle_window_shortcut(_key(KEY_H), orch) and orch.toggled == ["shelter"], "UIInputRouter: [H] abre/cierra shelter")
	var ctrl_h := _key(KEY_H)
	ctrl_h.ctrl_pressed = true
	check(not router.handle_window_shortcut(ctrl_h, orch), "Ctrl+H no abre el Refugio")
	var echo := _key(KEY_H)
	echo.echo = true
	check(not router.handle_window_shortcut(echo, orch), "Eco de tecla ignorado")
	check(ProjectSettings.get_setting("autoload/ShelterService", "") == "*res://shared-core/ShelterService.gd", "ShelterService registrado como autoload")
	router.free()
	orch.free()
	reg.free()
	await process_frame


# --------------------------------------------------------------------------
func _test_side_cut_model() -> void:
	print("-- Modelo de corte lateral: superficie, pisos y celdas")
	var s: Node = _new_service()
	check(s.shelter_name == "El Nido", "El refugio se llama «El Nido»")
	check(s.get_floor_count() == 4 and s.cols == 6, "4 pisos × 6 celdas")
	check(s.get_floor_name(0) == "Piso 1" and s.get_floor_name(2) == "Sótano", "Pisos con nombre (Piso 1 … Sótano)")
	var plots: Array = s.surface["plots"]
	check(plots.size() == 2 and plots[0]["name"] == "Huerto de azotea", "Superficie: parcelas de cultivo")
	var feats: Array = s.surface["features"].map(func(f) -> String: return f["id"])
	check(feats.has("nido_pispa") and feats.has("portal") and feats.has("escalera"), "Superficie: nido, portal al mundo y escalera al patio")
	var states := {}
	for f in s.get_floor_count():
		for c in s.cols:
			var st: String = s.get_cell(f, c)["state"]
			states[st] = int(states.get(st, 0)) + 1
	for st in ["room", "empty", "rock", "secret", "locked"]:
		check(states.has(st), "Hay celdas en estado «%s»" % st)
	var dorm: Dictionary = s.get_room_at(0, 0)
	check(dorm["type"] == "dormitorio" and int(dorm["size"]) == 2 and s.get_room_at(0, 1)["uid"] == dorm["uid"], "La sala doble ocupa dos celdas")
	check(s.room_name(dorm["uid"]) == "Dormitorio doble", "Nombre de sala doble")
	check(s.get_cell(9, 0).is_empty() and s.get_cell(0, 99).is_empty(), "Celdas fuera de rango -> {}")
	var sv: Dictionary = s.get_cell_view(3, 0)
	check(sv["state"] == "secret" and sv["title"] == "???" and str(sv["hint"]).contains("zumbido"), "Celda secreta muestra «???» y la pista")
	check(s.get_cell_view(2, 5)["title"] == "Cimientos", "Celda bloqueada = «Cimientos»")
	check(s.get_shelter_level() == 4, "Nivel del refugio 4 (16 mejoras hechas)")
	var neigh: Array = s.get_neighbors(1, 0).map(func(r) -> String: return r["type"])
	check(neigh.has("taller_resina") and neigh.has("destilador") and neigh.has("dormitorio"), "Vecinos: izquierda/derecha y arriba/abajo")
	var d: Dictionary = s.to_dict()
	var s2: Node = _new_service()
	s2.load_state(d)
	check(s2.get_room_at(0, 0)["uid"] == dorm["uid"] and s2.get_floor_count() == 4, "to_dict / load_state conservan el corte lateral")
	s.free()
	s2.free()


func _test_dig_and_secret() -> void:
	print("-- Excavación y salas secretas «???» al Códice")
	var s: Node = _new_service()
	var ks: Node = KS.new()
	ks.wiki_sync_enabled = false
	s.knowledge = ks
	var metal0: int = s.get_item("metal")
	check(s.can_dig(1, 5)["ok"], "Se puede excavar roca")
	check(not s.can_dig(0, 2)["ok"] and s.can_dig(0, 2)["reason"] == "not_rock", "No se excava una sala")
	check(s.can_dig(2, 5)["reason"] == "requires_level", "Los cimientos piden nivel de El Nido")
	var cost: Dictionary = s.get_dig_cost(1)
	check(int(cost["metal"]) == 60, "Excavar el piso 2 cuesta más que el 1 (60 metal)")
	var r: Dictionary = s.dig(1, 5)
	check(r["ok"] and not r["secret"] and s.get_cell(1, 5)["state"] == "empty", "Roca → hueco libre")
	check(s.get_item("metal") == metal0 - 60, "Excavar cobra el coste")
	var r2: Dictionary = s.dig(1, 5)
	check(not r2["ok"], "No se excava dos veces")
	var got := [""]
	s.secret_discovered.connect(func(id: String, _uid: String) -> void: got[0] = id)
	check(ks.display_name("lugar_colmena_tapiada") == "???", "Antes de excavar el Códice dice «???»")
	var r3: Dictionary = s.dig(3, 0)
	check(r3["ok"] and r3["secret"] and r3["secret_id"] == "lugar_colmena_tapiada", "Excavar «???» descubre la sala secreta")
	check(got[0] == "lugar_colmena_tapiada", "Señal secret_discovered")
	check(s.get_room_at(3, 0)["type"] == "colmena", "La sala secreta aparece en el corte")
	check(ks.is_known("lugar_colmena_tapiada") and ks.is_pending("lugar_colmena_tapiada"), "Entra al Códice como secreto en «Por decidir»")
	check(ks.display_name("lugar_colmena_tapiada") == "Colmena antigua", "El Códice ya muestra su nombre")
	var poor: Node = _new_service()
	poor.storage["metal"] = 0
	check(poor.can_dig(1, 5)["reason"] == "cost", "Sin metal no se excava")
	check(not poor.dig_new_floor()["ok"] and poor.dig_new_floor()["reason"] == "requires_level", "Piso nuevo pide nivel 5")
	poor.free()
	s.free()
	ks.free()


func _test_build_fusion_and_neighbors() -> void:
	print("-- Construir: previsualización, bonus por vecindad y fusión de salas dobles")
	var s: Node = _new_service()
	# Hueco en Piso 1 (col 5) junto a la Sala; hueco en Piso 2 (col 4) junto al Almacén.
	var pv: Dictionary = s.preview_placement("telar", 1, 4)
	check(pv["fits"], "El Telar cabe en el hueco del Piso 2")
	check(int(pv["bonus_pct"]) == 5 and pv["sources"][0]["type"] == "almacen", "Bonus por vecindad: +5 % junto al Almacén")
	check(int(pv["comfort_after"]) > int(pv["comfort_before"]), "La previsualización muestra el confort que sube")
	check(float(pv["build_hours_helped"]) < float(pv["build_hours"]), "Con un habitante ayudando la obra es más corta")
	check(s.preview_placement("telar", 1, 5)["reason"] == "rock", "En roca no cabe")
	check(s.preview_placement("telar", 0, 2)["reason"] == "occupied", "Sobre una sala no cabe")
	check(s.preview_placement("telar", 2, 5)["reason"] == "locked", "En cimientos no cabe")
	check(s.preview_placement("colmena", 1, 4)["reason"] == "unknown_room", "Las salas secretas no se construyen")
	var nb_c: Dictionary = s.neighbor_bonus_for("cocina", 0, 2)
	check(int(nb_c["pct"]) == 15, "La Cocina junto a la Despensa: +15 %")
	var nb_cap: Dictionary = s.neighbor_bonus_for("cocina", 0, 2)
	check(int(nb_cap["pct"]) <= SS.NEIGHBOR_BONUS_CAP, "El bonus por vecindad tiene tope")
	var madera0: int = s.get_item("madera")
	var placed: Dictionary = s.place_room("telar", 1, 4)
	check(placed["ok"] and not placed["fused"], "Telar colocado")
	check(s.get_item("madera") == madera0 - 140, "Construir cobra madera")
	check(s.get_room(placed["uid"])["status"] == "building", "La sala nueva queda en obra")
	check(s.get_neighbor_bonus(placed["uid"])["pct"] == 5, "Bonus por vecindad de la sala colocada")
	# Fusión: excavar la roca de al lado y poner otro Telar.
	s.dig(1, 5)
	var fused_sig := [""]
	s.rooms_fused.connect(func(uid: String, _t: String) -> void: fused_sig[0] = uid)
	var pv2: Dictionary = s.preview_placement("telar", 1, 5)
	check(pv2["merge"], "La previsualización avisa de la fusión")
	var placed2: Dictionary = s.place_room("telar", 1, 5)
	check(placed2["ok"] and placed2["fused"], "Dos Telares contiguos se fusionan")
	var dbl: Dictionary = s.get_room(placed2["uid"])
	check(int(dbl["size"]) == 2 and dbl["fused"] and int(dbl["col"]) == 4, "Sala doble: 2 celdas desde la columna izquierda")
	check(s.get_room_at(1, 5)["uid"] == dbl["uid"], "Ambas celdas apuntan a la sala doble")
	check(s.find_rooms("telar").size() == 1, "Solo queda una sala (la doble)")
	check(s.room_capacity(dbl["uid"]) == 4, "Sala doble: el doble de capacidad")
	check(fused_sig[0] == dbl["uid"], "Señal rooms_fused")
	check(s.room_name(dbl["uid"]) == "Telar doble", "Nombre «Telar doble»")
	# Fusionar una sala de taller aumenta su producción (+25 %).
	var s2: Node = _new_service()
	var before: float = s2.workshop_capacity("molino")
	var spot: Dictionary = s2.get_room_at(2, 2)
	s2.dig(2, 4)
	var mol: Dictionary = s2.place_room("molino", 2, 4)
	check(mol["ok"] and not mol["fused"], "Un molino no contiguo no se fusiona")
	check(s2.find_rooms("molino").size() == 2 and spot["size"] == 1, "Dos molinos sueltos")
	s2.tick(4.0)
	s2.assign_worker("mira", mol["uid"])
	check(s2.workshop_capacity("molino") > before, "Más molinos = más capacidad")
	# Decoración: sube el confort sin ocupar celda.
	var c0: int = s.get_comfort()
	var dec: Dictionary = s.place_room("sillon", 0, 4)
	check(dec["ok"] and s.get_comfort() == c0 + 4, "Sillón y alfombra: +4 de confort")
	check(s.preview_placement("ventanal", 0, 4)["reason"] == "requires_level", "El Ventanal pide El Nido nivel 5")
	check(s.preview_placement("maceta", 3, 2)["reason"] == "needs_room", "La decoración va dentro de un cuarto")
	var cat: Array = s.get_buildable_catalog("estaciones")
	check(cat.any(func(e) -> bool: return e["type"] == "forja") and not cat.any(func(e) -> bool: return e["type"] == "colmena"), "Cajón «Estaciones»: Forja sí, sala secreta no")
	for t in ["forja", "taller", "almacen", "cocina", "despensa", "huerto", "dormitorio"]:
		check(s.catalog.has(t), "Catálogo de salas incluye %s" % t)
	s.free()
	s2.free()


func _test_workers_ideal() -> void:
	print("-- Habitantes chibi: asignación y «ideal +20 %»")
	var s: Node = _new_service()
	check(s.get_characters().size() == 5, "5 habitantes chibi")
	check(s.get_character("ysolde")["status"] == "working", "Ysolde trabaja")
	check(s.get_character("torq")["status"] == "expedition", "Torq está de expedición")
	var ideal: float = s.worker_efficiency("ysolde", "destilador")
	var plain: float = s.worker_efficiency("ysolde", "forja")
	check(is_equal_approx(ideal, 1.2) and is_equal_approx(plain, 1.0), "Sala ideal ×1,2 / otra ×1,0")
	check(is_equal_approx(ideal / plain, 1.0 + SS.IDEAL_BONUS), "Diferencia exacta: +20 %")
	check(s.ideal_label("ysolde") == "Huerto · ideal +20 %", "Etiqueta «Huerto · ideal +20 %»")
	var mesa: Dictionary = s.find_rooms("mesa_mapas")[0]
	var res: Dictionary = s.assign_worker("mira", mesa["uid"])
	check(res["ok"] and res["ideal"] and int(res["bonus_pct"]) == 20, "Mira en la Mesa de mapas: ideal +20 %")
	check(s.get_character("mira")["room"] == mesa["uid"] and (mesa["workers"] as Array).has("mira"), "Asignada a la sala")
	check(not (s.find_rooms("forja")[0]["workers"] as Array).has("mira"), "Se mueve: deja su sala anterior")
	check(s.assign_worker("torq", mesa["uid"])["reason"] == "busy", "Quien está de expedición no trabaja")
	var res2: Dictionary = s.assign_worker("kael", mesa["uid"])
	check(not res2["ok"] and res2["reason"] == "full", "Sala llena (capacidad 1)")
	var best: Dictionary = s.best_room_for("lia")
	check(not best.is_empty(), "best_room_for devuelve una sala")
	var sug: Array = s.suggest_assignments()
	check(sug.any(func(x) -> bool: return x["char"] == "ysolde" and x["ideal"]), "Reparto sugerido: Ysolde en su sala ideal")
	# Energía y descanso con confort.
	var ys: Dictionary = s.get_character("ysolde")
	ys["energy"] = 20.0
	check(is_equal_approx(s.worker_efficiency("ysolde", "destilador"), 1.2 * SS.TIRED_FACTOR), "Agotada rinde menos")
	s.unassign_worker("ysolde")
	check(s.get_character("ysolde")["status"] == "idle", "Sin sala: descansa")
	s.tick(2.0)
	check(float(ys["energy"]) > 20.0 + SS.ENERGY_REST_PER_H * 2.0, "El confort acelera el descanso")
	var kael: Dictionary = s.get_character("kael")
	var e0 := float(kael["energy"])
	s.tick(1.0)
	check(float(kael["energy"]) < e0, "Trabajar cansa")
	check(s.comfort_production_bonus() > 0.0, "El confort da un poco más de producción")
	s.free()


func _test_production_and_bottlenecks() -> void:
	print("-- Cadenas de producción y cuellos de botella")
	var s: Node = _new_service()
	var g: Dictionary = s.get_production_graph()
	check(g["raw"].size() == 5 and g["workshops"].size() == 4 and g["products"].size() == 4 and g["destinations"].size() == 4, "Grafo materias → talleres → productos → destino")
	var kinds: Array = g["destinations"].map(func(d) -> String: return d["kind"])
	for k in ["market", "mission", "upgrade", "pispa"]:
		check(kinds.has(k), "Destino «%s»" % k)
	check(g["edges"].any(func(e) -> bool: return e["from"] == "raw:hierbas" and e["to"] == "shop:destileria" and e["status"] == "jam"), "Arista atascada marcada en rojo (jam)")
	check(g["edges"].any(func(e) -> bool: return e["status"] == "building"), "Arista en construcción (taller de resina)")
	check(s.workshop_status("taller_resina")["status"] == "building", "Taller de resina en obra")
	check(s.workshop_status("forja")["status"] == "ok", "La forja fluye")
	var jams: Array = s.diagnose()
	check(jams.size() == 1 and jams[0]["workshop"] == "destileria", "Un atasco: la Destilería")
	check(jams[0]["cause"] == "capacity", "Causa: capacidad")
	check(str(jams[0]["message"]).contains("hierbas esperan") and str(jams[0]["message"]).contains("tónicos"), "Mensaje con causa legible")
	var sol_ids: Array = jams[0]["solutions"].map(func(x) -> String: return x["id"])
	check(sol_ids == ["upgrade", "build_second", "divert"], "3 soluciones: mejorar, construir 2.ª, mandar a Pispa")
	check(str(jams[0]["solutions"][0]["label"]) == "Mejorar a nivel 3", "Etiqueta «Mejorar a nivel 3»")
	# Solución 1: mejorar (obra) → tras la obra el atasco desaparece.
	var fix: Dictionary = s.apply_fix("destileria", "upgrade")
	check(fix["ok"] and int(fix["to_level"]) == 3, "1 clic: mejora en obra")
	check(s.diagnose()[0]["resolving"], "Mientras dura la obra el atasco figura «resolviéndose»")
	s.tick(float(fix["hours"]) + 0.1)
	check(int(s.find_rooms("destilador")[0]["level"]) == 3, "La Destilería sube a nivel 3")
	check(s.diagnose().filter(func(b) -> bool: return b["workshop"] == "destileria").is_empty(), "Atasco resuelto")
	# Solución 2: desviar hierbas a Pispa.
	var s2: Node = _new_service()
	var fx2: Dictionary = s2.apply_fix("destileria", "divert")
	check(fx2["ok"] and float(fx2["per_hour"]) > 0.0 and s2.pispa["target"] == "hierbas", "Mandar hierbas a Pispa: desvía el excedente")
	check(s2.raw_rate("hierbas") < 22.0, "Llegan menos hierbas a la Destilería")
	# Solución 3: construir una segunda.
	var s3: Node = _new_service()
	var fx3: Dictionary = s3.apply_fix("destileria", "build_second")
	check(fx3["ok"] and s3.find_rooms("destilador").size() == 2, "Construir una 2.ª Destilería")
	# Sin obreros.
	var s4: Node = _new_service()
	s4.unassign_worker("ysolde")
	var j4: Array = s4.diagnose()
	check(j4.any(func(b) -> bool: return b["cause"] == "no_worker"), "Sin obreros = atasco «no_worker»")
	var fx4: Dictionary = s4.apply_fix("destileria", "assign")
	check(fx4["ok"] and s4.workshop_capacity("destileria") > 0.0, "1 clic: asigna al mejor habitante libre")
	check(fx4["ideal"], "…y elige a quien rinde ideal (+20 %)")
	# Producción con el tiempo.
	var s5: Node = _new_service()
	var h0: int = s5.get_item("hierbas")
	var sum: Dictionary = s5.tick(2.0)
	check(int(sum["produced"]["hierbas"]) == 44, "Materias primas: 22 hierbas/h")
	check(s5.get_item("hierbas") > h0, "Las hierbas se acumulan (esperan)")
	var dest_uid: String = s5.find_rooms("destilador")[0]["uid"]
	check(s5.get_ready_count(dest_uid) > 0, "Los tónicos quedan «listos» en la sala")
	var col: Array = s5.get_collectables()
	check(col.any(func(c) -> bool: return c["kind"] == "room"), "Recoger todo incluye la sala")
	var t0: int = s5.get_item("tonicos")
	var got: Dictionary = s5.collect_all()
	check(got["ok"] and s5.get_item("tonicos") > t0 and s5.get_ready_count(dest_uid) == 0, "Recoger todo → almacén central")
	# Almacén lleno: nada se pierde.
	var s6: Node = _new_service()
	var free: int = s6.get_storage_capacity() - s6.get_storage_used()
	var acc: int = s6.deposit("madera", free + 50)
	check(acc == free and int(s6.overflow["madera"]) == 50, "Almacén lleno: lo que sobra va aparte (nada se pierde)")
	check(s6.diagnose().any(func(b) -> bool: return b["cause"] == "storage_full"), "Atasco «almacén lleno» con solución")
	for x in [s, s2, s3, s4, s5, s6]:
		x.free()


func _test_expeditions() -> void:
	print("-- Expediciones: envío, eventos y resolución segura")
	var s: Node = _new_service()
	check(s.expeditions_catalog.size() == 4, "4 expediciones disponibles")
	var avail: Array = s.get_available_for_expedition().map(func(c) -> String: return c["id"])
	check(not avail.has("kael"), "El personaje principal no viaja")
	check(not avail.has("lia"), "Los personajes prestados no viajan")
	check(not avail.has("torq"), "Quien ya está fuera no está disponible")
	check(avail.has("ysolde") and avail.has("mira"), "Secundarios disponibles: Ysolde y Mira")
	var ch: Dictionary = s.success_chance("ruinas_ferrum", ["ysolde"])
	check(int(ch["pct"]) == 78, "Ruinas de Ferrum con Ysolde: 78 %")
	var labels: Array = ch["factors"].map(func(f) -> String: return f["label"])
	check(labels.has("Nivel adecuado") and labels.has("Clase recomendada") and labels.has("Riesgo medio"), "Factores de éxito visibles")
	check(int(s.success_chance("ruinas_ferrum", ["ysolde", "mira"])["pct"]) == 92, "Con 2 personajes: 92 %")
	check(int(s.success_chance("grieta_profunda", ["mira"])["pct"]) < 40, "Grieta profunda con 1 personaje de nivel bajo: arriesgado")
	check(s.send_expedition("ruinas_ferrum", ["kael"], 4)["reason"] == "main_character", "No se envía al principal")
	check(s.send_expedition("ruinas_ferrum", ["lia"], 4)["reason"] == "loaned", "No se envía un prestado")
	check(s.send_expedition("ruinas_ferrum", ["ysolde"], 3)["reason"] == "bad_duration", "Duración no ofrecida")
	check(s.send_expedition("ruinas_ferrum", [], 4)["reason"] == "no_characters", "Sin equipo no sale")
	var sent_sig := [""]
	s.expedition_sent.connect(func(id: String) -> void: sent_sig[0] = id)
	var r: Dictionary = s.send_expedition("ruinas_ferrum", ["ysolde"], 4)
	check(r["ok"] and sent_sig[0] == r["run_id"], "Expedición enviada")
	check(s.get_character("ysolde")["status"] == "expedition" and s.get_character("ysolde")["room"] == "", "Ysolde deja su sala y se va")
	check(s.send_expedition("bosque_fosil", ["ysolde"], 2)["reason"] == "busy", "No puede ir a dos sitios")
	# Decisión de Torq (seed): la contestamos nosotros.
	var pend: Array = s.get_pending_decisions()
	check(pend.size() == 1 and pend[0]["event"]["title"] == "Bifurcación", "Torq espera que elijas camino")
	check(str(pend[0]["event"]["text"]).begins_with("Torq encontró"), "El evento nombra al personaje")
	var dec: Dictionary = s.resolve_decision(pend[0]["run_id"], "tunel")
	check(dec["ok"] and not dec["auto"] and not dec["safe"], "Elegir el túnel (arriesgado) a mano")
	check(s.get_run(pend[0]["run_id"])["loot_mult"] == 1.5, "El túnel da +50 % botín")
	check(s.resolve_decision(pend[0]["run_id"], "puente")["reason"] == "no_pending_decision", "Una decisión no se contesta dos veces")
	# Decisión de Ysolde: no contestamos → camino seguro automático.
	var auto_sig := [false]
	s.expedition_decided.connect(func(_id: String, opt: String, auto: bool) -> void:
		if auto:
			auto_sig[0] = opt == "puente")
	var finished := []
	s.expedition_finished.connect(func(_id: String, res: Dictionary) -> void: finished.append(res))
	var sum: Dictionary = s.tick(2.2)
	check(not s.get_pending_decisions().is_empty() or int(sum["auto_decisions"]) > 0, "A mitad de viaje aparece la decisión de Ysolde")
	var sum2: Dictionary = s.tick(1.0)
	check(int(sum["auto_decisions"]) + int(sum2["auto_decisions"]) >= 1 and auto_sig[0], "Sin respuesta: elige la opción segura (puente)")
	var run: Dictionary = s.get_run(r["run_id"])
	check(not run.is_empty() and run["event"]["auto"] and run["event"]["choice"] == "puente", "Registrado como decisión automática")
	var lvl0: int = int(s.get_character("ysolde")["level"])
	var metal0: int = s.get_item("metal")
	s.tick(2.0)
	check(finished.size() == 2, "Las dos expediciones vuelven")
	var ys_res: Dictionary = finished.filter(func(x) -> bool: return x["run_id"] == r["run_id"])[0]
	check(ys_res["outcome"] == "success" and ys_res["auto"], "Éxito con decisión automática")
	check(int(s.get_character("ysolde")["level"]) > lvl0, "Ysolde sube de nivel (XP de expedición)")
	check(s.get_item("metal") > metal0, "El botín llega al almacén")
	check(s.get_character("ysolde")["status"] == "idle", "Ysolde vuelve a casa")
	check(s.finished_expeditions[0]["run_id"] != "", "Aparece en «Terminadas»")
	# Fallo: vuelve con 20 % y sin penalización.
	var s2: Node = _new_service()
	s2.roll_override = 99.0
	var r2: Dictionary = s2.send_expedition("biblioteca_runica", ["mira"], 4)
	check(int(r2["success_pct"]) == 73, "Biblioteca rúnica con Mira: 73 %")
	s2.tick(4.1)
	var fin: Dictionary = s2.finished_expeditions.filter(func(x) -> bool: return x.get("run_id", "") == r2["run_id"])[0]
	check(fin["outcome"] == "fail" and str(fin["summary"]).contains("sin penalización"), "Fallida: sin penalización")
	check(int(fin["loot"]["esquirlas"]) == 9, "Fallida: vuelve con el 20 % del botín")
	# Pispa en la expedición.
	var s3: Node = _new_service()
	var r3: Dictionary = s3.send_expedition("bosque_fosil", ["mira"], 2, true)
	check(r3["ok"] and not s3.is_pispa_searching(), "Pispa acompaña: no recolecta mientras tanto")
	check(s3.send_expedition("biblioteca_runica", ["ysolde"], 4, true)["reason"] == "pispa_busy", "Pispa no va a dos expediciones")
	for x in [s, s2, s3]:
		x.free()


func _test_pispa() -> void:
	print("-- Pispa: búsqueda, bolsa y almacén")
	var s: Node = _new_service()
	var targets: Array = s.get_pispa_targets()
	var hier: Dictionary = targets.filter(func(t) -> bool: return t["id"] == "hierbas")[0]
	check(hier["mission_star"] and str(hier["mission_text"]).begins_with("★"), "★ en lo que pide tu misión (hierbas)")
	check(targets.filter(func(t) -> bool: return t["id"] == "ferrum")[0]["locked"], "Materiales de Ferrum: bloqueado hasta el nido 4")
	check(s.set_pispa_target("ferrum")["reason"] == "requires_nest", "No se elige un objetivo bloqueado")
	check(s.set_pispa_target("nada")["reason"] == "unknown_target", "Objetivo desconocido")
	check(s.set_pispa_target("esquirlas")["ok"] and s.pispa["target"] == "esquirlas", "Configurar búsqueda: esquirlas")
	check(s.pispa_bag_capacity() == 20 and s.pispa_bag_used() == 14, "Bolsa 14 / 20")
	check(s.is_pispa_searching(), "Pispa está de viaje")
	var trips := [0]
	s.pispa_returned.connect(func(_l: Dictionary) -> void: trips[0] += 1)
	s.tick(1.0)
	check(trips[0] >= 1, "Pispa vuelve con botín")
	check(s.pispa_bag_items() > 0, "El botín va a la bolsa")
	check(str(s.pispa["journal"][0]["text"]).contains("×"), "Diario de hallazgos actualizado")
	# Apilado y límite.
	var s2: Node = _new_service()
	(s2.pispa["bag"] as Array).clear()
	check(s2.add_to_pispa_bag("esquirlas", 30) == 30 and s2.pispa_bag_used() == 3, "Apila hasta 12 por hueco")
	check(s2.add_to_pispa_bag("hierbas", 12 * 30) == 12 * 17, "Si no cabe, se queda fuera")
	check(s2.is_pispa_bag_full(), "Bolsa llena")
	s2.pispa["trip"] = {}
	s2.tick(1.0)
	check(not s2.is_pispa_searching(), "Con la bolsa llena deja de buscar")
	var esq0: int = s2.get_item("esquirlas")
	var emptied: Dictionary = s2.empty_pispa_bag()
	check(emptied["ok"] and int(emptied["items"]["esquirlas"]) == 30, "«Vaciar bolsa al almacén»")
	check(s2.get_item("esquirlas") == esq0 + 30 and s2.pispa_bag_used() == 0, "El botín entra al almacén central")
	check(s2.is_pispa_searching(), "Con la bolsa vacía vuelve a salir sola")
	# Bocadillo y cariño.
	var trip: Dictionary = s2.pispa["trip"]
	var left := float(trip["end_h"]) - float(s2.clock_h)
	var pan0: int = s2.get_item("pan")
	check(s2.feed_pispa()["ok"] and s2.get_item("pan") == pan0 - 1, "Darle pan gasta 1 pan")
	check(is_equal_approx(float(s2.pispa["trip"]["end_h"]) - float(s2.clock_h), left * 0.5), "El viaje dura la mitad")
	s2.storage["pan"] = 0
	check(s2.feed_pispa()["reason"] == "no_bread", "Sin pan no hay bocadillo")
	var aff0: int = int(s2.pispa["affection"])
	check(s2.pet_pispa()["ok"] and int(s2.pispa["affection"]) == mini(5, aff0 + 1), "Acariciar sube el cariño")
	check(s2.pet_pispa()["reason"] == "cooldown", "Una caricia cada 4 h")
	check(SS.affection_label(5) == "muy feliz", "Cariño 5 = «muy feliz»")
	s2.set_pispa_follow(true)
	check(not s2.is_pispa_searching(), "Acompañarme en el mundo: no busca")
	s2.set_pispa_follow(false)
	check(s2.is_pispa_searching(), "Al volver al nido sale de nuevo")
	# Nido 4 desbloquea +6 huecos y Ferrum.
	var s3: Node = _new_service()
	s3.storage["seda"] = 10
	var up: Dictionary = s3.start_upgrade("nido_pispa", 3)
	check(up["ok"], "Mejorar el nido (Bolsa +6)")
	s3.tick(float(up["hours"]) + 0.1)
	check(s3.get_nest_level() == 4 and s3.pispa_bag_capacity() == 26, "Nido 4: bolsa 26")
	check(s3.set_pispa_target("ferrum")["ok"], "Nido 4: búsqueda de Ferrum desbloqueada")
	for x in [s, s2, s3]:
		x.free()


func _test_dividends() -> void:
	print("-- Almacén central: dividendos de PNJ (Gildas, Torin)")
	var s: Node = _new_service()
	var ks: Node = KS.new()
	ks.wiki_sync_enabled = false
	s.connect_knowledge(ks)
	ks.add_investment({"id": "inv_gildas", "npc_id": "pnj_gildas", "name": "Puesto de Gildas", "share": 0.02, "status": "active"})
	ks.add_investment({"id": "inv_torin", "npc_id": "pnj_torin", "name": "Forja de Torin", "share": 0.03, "status": "active"})
	check(ks.record_transaction("inv_gildas", 10000) == 200, "Gildas: 2 % de 10.000 = 200")
	check(ks.record_transaction("inv_torin", 5000) == 150, "Torin: 3 % de 5.000 = 150")
	check(s.pending_dividends() == 350, "350 oro pendientes")
	check(s.get_collectables().any(func(c) -> bool: return c["kind"] == "dividends"), "«Recoger todo» incluye los dividendos")
	var oro0: int = s.get_item("oro")
	var sig := []
	s.dividend_received.connect(func(src: String, amt: int) -> void: sig.append([src, amt]))
	var res: Dictionary = s.collect_dividends()
	check(res["ok"] and int(res["amount"]) == 350 and res["destination"] == "shelter_storage", "KnowledgeService manda 350 al almacén del refugio")
	check(s.get_item("oro") == oro0 + 350, "El oro se acumula en el almacén central")
	var totals: Dictionary = s.get_dividend_totals()
	check(int(totals.get("Gildas", 0)) == 200 and int(totals.get("Torin", 0)) == 150, "Desglose por PNJ: Gildas 200 · Torin 150")
	check(sig.size() == 2, "Señal dividend_received por cada PNJ")
	check(ks.pending_payout == 0 and s.pending_dividends() == 0, "Ya no queda nada pendiente")
	check(not s.collect_dividends()["ok"], "Cobrar dos veces no duplica")
	# Cobro iniciado desde el Códice («Cobrar al Refugio») también llega aquí.
	ks.record_transaction("inv_gildas", 5000)
	ks.collect_to_shelter()
	check(int(s.get_dividend_totals()["Gildas"]) == 300, "«Cobrar al Refugio» desde el Códice también llega al almacén")
	check(s.dividend_ledger.size() == 3, "Libro de dividendos con 3 ingresos")
	# Recoger todo cobra dividendos.
	ks.record_transaction("inv_torin", 1000)
	var all: Dictionary = s.collect_all()
	check(int(all["items"].get("oro", 0)) == 30, "«Recoger todo» cobra los dividendos (30)")
	var s2: Node = _new_service()
	check(not s2.collect_dividends()["ok"] and s2.collect_dividends()["reason"] == "no_knowledge_service", "Sin KnowledgeService no rompe")
	s.free()
	s2.free()
	ks.free()


func _test_upgrades_and_offline() -> void:
	print("-- Mejoras, nivel del refugio, confort y tope sin conexión")
	var s: Node = _new_service()
	check(s.upgrades.size() == 8, "8 líneas de mejora")
	check(s.upgrades_done() == 16 and s.next_level_threshold() == 20, "Mejoras hechas 16 / 20")
	var rec: Array = s.get_recommended_upgrades()
	check(rec.size() == 3 and rec[0]["name"] == "Invernadero 3", "Orden recomendado por metas: Invernadero 3 primero")
	check(rec[1]["why"] != rec[0]["why"], "Cada recomendación explica su porqué")
	check(s.tier_status(0, 0) == "done" and s.tier_status(0, 2) == "recommended" and s.tier_status(0, 4) == "locked", "Estados: hecho / recomendado / requiere nivel")
	check(s.tier_status(0, 3) == "next", "Un nivel espera al anterior")
	check(s.tier_status(3, 3) == "in_progress", "Destilador «Flujo» en obra")
	check(s.start_upgrade("invernadero", 3)["reason"] == "previous_first", "No se salta niveles")
	check(s.start_upgrade("invernadero", 4)["reason"] == "requires_level", "Bloqueado por nivel del refugio")
	var ok: Dictionary = s.start_upgrade("invernadero", 2)
	check(ok["ok"], "Empieza «Resina»")
	check(s.get_works_in_progress().size() == 2, "Obras en marcha 2 de 2")
	check(s.start_upgrade("dormitorio", 1)["reason"] == "no_slot", "Solo 2 obras a la vez")
	var lvl_sig := []
	s.upgrade_finished.connect(func(row: String, t: int) -> void: lvl_sig.append([row, t]))
	s.tick(3.1)
	check(lvl_sig.size() == 2 and s.upgrades_done() == 18, "Las obras terminan con el tiempo")
	s.storage["madera"] = 9999
	s.storage["metal"] = 9999
	s.storage["esquirlas"] = 9999
	for row in ["dormitorio", "almacen"]:
		var t := 1 if row == "dormitorio" else 2
		s.start_upgrade(row, t)
	s.tick(4.0)
	check(s.get_shelter_level() == 5, "Con 20 mejoras: El Nido nivel 5")
	check(s.get_cell(2, 5)["state"] == "rock", "Nivel 5 convierte cimientos en roca excavable")
	check(s.dig_new_floor()["ok"] and s.get_floor_count() == 5, "Nivel 5: se excava un piso más")
	check(s.preview_placement("ventanal", 0, 4)["fits"], "Nivel 5: el Ventanal ya se puede colocar")
	# Tope sin conexión 12 h.
	var s2: Node = _new_service()
	var off: Dictionary = s2.apply_offline(30.0)
	check(off["capped"] and is_equal_approx(float(off["hours"]), SS.OFFLINE_CAP_HOURS), "Sin conexión: tope de 12 h")
	check(int(off["produced"]["hierbas"]) == 22 * 12, "Producción de 12 h, no de 30")
	check(not (off["away_log"] as Array).is_empty(), "Resumen «Mientras no estabas»")
	check(s2.get_character("lia")["status"] == "returned", "Lía vuelve con Brisa al acabar el préstamo")
	var round: Array = s2.get_round_items()
	check(round.any(func(r) -> bool: return r["action"] == "collect_all"), "Ronda de 2 minutos: recoger")
	s2.collect_all()
	s2.empty_pispa_bag()
	var p: Dictionary = s2.get_pocket_summary()
	check(p.has("round") and p.has("comfort") and p.has("pispa"), "Resumen del bolsillo")
	for x in [s, s2]:
		x.free()


# --------------------------------------------------------------------------
func _test_window() -> void:
	print("-- ShelterWindow: sub-pestañas, construir, producción, expediciones, Pispa, mejoras")
	var w = ShelterScene.instantiate()
	check(w.get_script() != null, "ShelterWindow tiene script")
	var s: Node = _new_service()
	var ks: Node = KS.new()
	ks.wiki_sync_enabled = false
	s.connect_knowledge(ks)
	w.service = s
	root.add_child(w)
	await process_frame
	check(w.window_id == "shelter" and w.is_in_group("shelter_window"), "window_id = shelter")
	check(w.get_subtab_ids() == ["refugio", "produccion", "expediciones", "pispa", "mejoras"], "5 sub-pestañas")
	check(w.menu_bar.active_tab == "refugio", "Menú común con la pestaña Refugio activa")
	check(w.current_subtab == "refugio" and w.pages["refugio"].visible, "Arranca en el corte lateral")
	check(w.side_cut != null and w.side_cut.get_cell_rect(0, 0).size.x > 20.0, "El corte lateral tiene celdas visibles")
	var texts: String = _all_texts(w)
	check(texts.contains("Kael (tú)") and texts.contains("Ysolde"), "Lista de habitantes")
	check(texts.contains("Huerto · ideal +20 %") or texts.contains("ideal +20 %"), "La lista indica «ideal +20 %»")
	check(texts.contains("ALMACÉN CENTRAL"), "Tarjeta del almacén central")
	check(w.collect_button.text.begins_with("Recoger todo · "), "Botón «Recoger todo · N»")
	# Celda de sala → detalle.
	w.select_cell(1, 0)
	texts = _all_texts(w.detail_box)
	check(texts.contains("Taller") and texts.contains("nivel 2") and texts.contains("MEJORAR A NIVEL 3"), "Detalle del Taller con coste de mejora")
	# Celda de roca → excavar.
	w.select_cell(1, 5)
	check(w.dig_button.visible and not w.dig_button.disabled, "Roca: botón Excavar")
	var dug: Dictionary = w.dig_selected()
	check(dug["ok"] and s.get_cell(1, 5)["state"] == "empty", "Excavar desde la ventana")
	# Asignar con clic (habitante → cuarto).
	w.select_character("mira")
	check(w.selected_char == "mira" and w.status_label.text.contains("Mesa de mapas"), "Al elegir habitante sugiere su sala ideal")
	var mesa: Dictionary = s.find_rooms("mesa_mapas")[0]
	w.select_cell(int(mesa["floor"]), int(mesa["col"]))
	check(s.get_character("mira")["room"] == mesa["uid"] and w.status_label.text.contains("ideal +20 %"), "Clic en el cuarto: asignada (ideal +20 %)")
	# Arrastrar y soltar.
	check(w.side_cut._can_drop_data(w.side_cut.get_cell_rect(0, 2).get_center(), {"char_id": "kael"}), "Se puede soltar un habitante sobre un cuarto")
	check(not w.side_cut._can_drop_data(w.side_cut.get_cell_rect(3, 2).get_center(), {"char_id": "kael"}), "No sobre roca")
	# Modo Construir con B.
	var ev := _key(KEY_B)
	w._unhandled_key_input(ev)
	check(w.build_mode and w.drawer.visible, "[B] abre el modo Construir y el cajón inferior")
	check(w.catalog_cards.has("telar") and w.catalog_cards.has("forja"), "Cajón «Estaciones» con Telar y Forja")
	w.select_catalog_item("telar")
	w.select_cell(1, 4)
	texts = _all_texts(w.detail_box)
	check(texts.contains("Telar") and texts.contains("Confort del depa:") and texts.contains("por estar junto a"), "Detalle: coste, confort y bonus por vecindad")
	check(w.place_button.visible and not w.place_button.disabled and w.place_button.text == "Colocar aquí", "«Colocar aquí» habilitado (cabe)")
	w.select_cell(3, 2)
	check(w.place_button.disabled and w.place_button.text.begins_with("No cabe"), "En roca: «No cabe»")
	w.select_cell(1, 4)
	var placed: Dictionary = w.place_selected()
	check(placed["ok"] and s.get_room_at(1, 4)["type"] == "telar", "Colocar el Telar desde el cajón")
	w.select_cell(1, 5)
	var placed2: Dictionary = w.place_selected()
	check(placed2["fused"] and w.status_label.text.contains("Sala doble"), "Segundo Telar contiguo → «¡Sala doble!»")
	w.set_build_category("decoracion")
	check(w.catalog_cards.has("sillon") and w.catalog_cards["ventanal"].disabled, "Decoración: Ventanal bloqueado por nivel")
	w._unhandled_key_input(_key(KEY_B))
	check(not w.build_mode and not w.drawer.visible, "[B] vuelve a «Vivir»")
	# Producción.
	w.select_subtab("produccion")
	check(w.pages["produccion"].visible and w.menu_bar.active_subtab.get("refugio", "") == "produccion", "Sub-pestaña Producción")
	check(w.jam_title.text.contains("Destilería") and w.jam_message.text.contains("hierbas esperan"), "Banner de atasco en rojo con su causa")
	check(w.fix_buttons.has("upgrade") and w.fix_buttons.has("build_second") and w.fix_buttons.has("divert"), "3 botones de solución en 1 clic")
	s.storage["metal"] = 999
	s.storage["madera"] = 999
	w.fix_buttons["upgrade"].pressed.emit()
	check(int(s.find_rooms("destilador")[0]["upgrade_left_h"] * 100) > 0, "Pulsar «Mejorar a nivel 3» inicia la obra")
	check(w.fix_buttons["upgrade"].disabled, "Mientras se resuelve, los botones quedan desactivados")
	await process_frame
	w.chain_view.queue_redraw()
	await process_frame
	check(w.chain_view.node_rects.has("shop:destileria") and w.chain_view.node_rects.has("dest:mision_hierbas"), "El esquema dibuja talleres y destinos")
	# Expediciones.
	w.select_subtab("expediciones")
	w.select_expedition("ruinas_ferrum")
	check(w.team == ["ysolde"], "Equipo por defecto: el primer secundario libre")
	check(w.chance_label.text == "78 %" and w.chance_alt_label.text.contains("92 %"), "78 % (con 2 personajes: 92 %)")
	check(w.decision_buttons.has("tunel") and w.decision_buttons.has("puente"), "Decisión de Torq con sus dos caminos")
	w.decision_buttons["puente"].pressed.emit()
	check(s.get_pending_decisions().is_empty(), "Decidir desde la ventana")
	w.set_duration(8)
	w.add_team_member()
	check(w.team.size() == 2 and w.chance_label.text == "92 %", "Añadir personaje sube el éxito a 92 %")
	var sent: Dictionary = w.send_selected_expedition()
	check(sent["ok"] and s.active_expeditions.size() == 2, "Enviar expedición desde la ventana")
	texts = _all_texts(w.pages["expediciones"])
	check(texts.contains("EN CURSO") and texts.contains("TERMINADAS") and texts.contains("Ruinas de Ferrum"), "Paneles «En curso» y «Terminadas»")
	# Pispa.
	w.select_subtab("pispa")
	check(w.target_buttons.has("hierbas") and _all_texts(w.target_buttons["hierbas"]).contains("★"), "Objetivo con ★ de misión")
	w.target_buttons["sorpresa"].pressed.emit()
	check(s.pispa["target"] == "sorpresa", "Elegir búsqueda «Sorpresa»")
	check(w.bag_label.text.begins_with("%d / 20" % s.pispa_bag_used()), "Bolsa «N / 20»")
	var esq0: int = s.get_item("esquirlas")
	w.empty_bag_button.pressed.emit()
	check(s.pispa_bag_used() == 0 and s.get_item("esquirlas") > esq0, "«Vaciar bolsa al almacén» desde la ventana")
	check(w.empty_bag_button.disabled, "Con la bolsa vacía el botón se desactiva")
	# Mejoras.
	w.select_subtab("mejoras")
	check(w.upgrade_cells.has("invernadero:2") and w.upgrade_cells.has("entrenamiento:4"), "Rejilla de mejoras 8 × 5")
	check(_all_texts(w.upgrade_cells["invernadero:2"]).contains("①"), "Siguiente recomendado con su número")
	check(w.level_title.text == "NIVEL DEL REFUGIO 4 → 5" and w.level_done_label.text == "16 / 20", "Nivel del refugio 4 → 5 · 16 / 20")
	check(w.comfort_label.text.begins_with("Confort global"), "Confort global visible")
	# Dividendos en el almacén (ventana).
	ks.add_investment({"id": "inv_gildas", "npc_id": "pnj_gildas", "name": "Puesto de Gildas", "share": 0.02, "status": "active"})
	ks.record_transaction("inv_gildas", 10000)
	w.select_subtab("refugio")
	check(w.dividends_button.text == "Cobrar dividendos · 200" and not w.dividends_button.disabled, "Botón «Cobrar dividendos · 200»")
	w.collect_dividends()
	check(_all_texts(w.pages["refugio"]).contains("Gildas") and s.get_item("oro") >= 200, "El almacén muestra el dividendo de Gildas")
	# Recoger todo.
	var col: Dictionary = w.collect_all()
	check(col["ok"] and w.status_label.text.begins_with("Recogido"), "«Recoger todo» desde la cabecera")
	w.initialize_window({"subtab": "construir"})
	check(w.build_mode and w.current_subtab == "refugio", "initialize_window({subtab: construir})")
	w.queue_free()
	await process_frame
	ks.free()


func _test_pocket() -> void:
	print("-- Refugio de bolsillo (antesalas / pantallas de carga)")
	var s: Node = _new_service()
	var p = PocketScene.instantiate()
	p.service = s
	p.capture_shortcut = true
	root.add_child(p)
	await process_frame
	check(p.mini_view != null and p.mini_view.compact, "Mini corte lateral compacto")
	check(p.info_label.text.contains("Nivel 4") and p.info_label.text.contains("Confort"), "Cabecera con nivel y confort")
	check(p.round_buttons.has("collect"), "Ronda: «Recoger»")
	check(p.round_buttons.keys().any(func(k) -> bool: return str(k).begins_with("decision:")), "Ronda: decisión de expedición con sus opciones")
	check(p.round_buttons.has("jam:destileria"), "Ronda: atasco con «Arreglar»")
	var dk: String = ""
	for k in p.round_buttons:
		if str(k).begins_with("decision:") and str(k).ends_with("/puente"):
			dk = k
	p.round_buttons[dk].pressed.emit()
	check(s.get_pending_decisions().is_empty(), "Decidir desde el bolsillo")
	p.run_round_item("collect")
	p.run_round_item("jam:destileria")
	for it in s.get_round_items():
		p.run_round_item(it["id"])
	check(s.get_round_items().is_empty(), "Ronda completada")
	await process_frame
	check(p.round_box.get_node_or_null("AllDone") != null and _all_texts(p.round_box).contains("Todo al día"), "Estado final «Todo al día»")
	check(p.handle_shortcut(_key(KEY_H)) and not p.visible, "[H] cierra el bolsillo")
	check(p.handle_shortcut(_key(KEY_H)) and p.visible, "[H] lo vuelve a abrir")
	var ctrl_h := _key(KEY_H)
	ctrl_h.ctrl_pressed = true
	check(not p.handle_shortcut(ctrl_h), "Ctrl+H no lo abre")
	p.capture_shortcut = false
	check(not p.handle_shortcut(_key(KEY_H)), "Fuera de colas/carga no captura H")
	var opened := [false]
	p.open_full_requested.connect(func() -> void: opened[0] = true)
	p.open_full_button.pressed.emit()
	check(opened[0], "«Abrir El Nido completo»")
	p.queue_free()
	await process_frame
	# Pantalla de carga con el bolsillo integrado.
	var ls = load("res://loading_screen.tscn").instantiate()
	root.add_child(ls)
	await process_frame
	check(ls.shelter_pocket != null and not ls.shelter_pocket.visible and ls.shelter_pocket.capture_shortcut, "La pantalla de carga trae el bolsillo (oculto, H)")
	ls.shelter_pocket.handle_shortcut(_key(KEY_H))
	check(ls.shelter_pocket.visible, "[H] en la pantalla de carga abre el bolsillo")
	ls.queue_free()
	await process_frame
