extends Node
## ShelterService — modelo del Refugio «El Nido» (Bolsillo del Umbral), UI v2.4 Paso 8.
## Referencias: design_ref/pantallas_html/MMO-Refugio.html, MMO-Construir.html,
## MMO-Produccion.html, MMO-Expediciones.html, MMO-Pispa.html, MMO-Mejoras.html,
## MMO-Vecindad.html y design_ref/PROMPT_ANTIGRAVITY.md §2.5, Anexos D y E.
##
## - Corte lateral: superficie (parcelas, nido de Pispa, escalera al patio, portal)
##   y pisos de roca con `cols` celdas cada uno. Celda: rock · empty · room · secret · locked.
## - Excavación (`dig`): roca → hueco. Las celdas «???» esconden una sala secreta
##   que, al excavar, entra al Códice (`KnowledgeService.discover_entry`).
## - Salas (`place_room`): coste, tiempo de obra, bonus por vecindad (tabla `affinity`)
##   y fusión automática: dos salas iguales contiguas → sala doble (+25 % eficiencia).
## - Habitantes chibi: `assign_worker` con eficiencia; en su sala ideal rinden +20 %.
##   Energía: trabajar cansa, descansar (más rápido con confort) recupera.
## - Producción: materias → talleres → productos → destino. `diagnose()` marca
##   atascos con causa y soluciones de 1 clic (`apply_fix`).
## - Expediciones: personajes secundarios, decisión durante el viaje y, si nadie
##   responde antes de que caduque, se elige la opción segura.
## - Pispa: busca lo que eliges (★ si lo pide tu misión), bolsa con límite y
##   «Vaciar bolsa al almacén».
## - Almacén central: recibe botín, producción y los dividendos de las inversiones
##   en PNJ (KnowledgeService.payout_collected) con desglose por PNJ.
## - Nunca castigar por no entrar: tope sin conexión de 12 h y nada se pierde
##   (lo que no cabe en el almacén va a `overflow`).
##
## Reloj virtual en horas (`clock_h`) que avanza con `tick(hours)`: los tests son
## deterministas. No depende de otros autoloads (se puede instanciar con `.new()`).

const DEFAULT_SEED_PATH := "res://config/shelter/shelter_seed.json"

const CELL_ROCK := "rock"
const CELL_EMPTY := "empty"
const CELL_ROOM := "room"
const CELL_SECRET := "secret"
const CELL_LOCKED := "locked"

const IDEAL_BONUS := 0.20          # «ideal +20 %»
const FUSION_BONUS := 0.25         # sala doble: +25 % de eficiencia
const TIRED_ENERGY := 25.0         # por debajo, rinde menos
const TIRED_FACTOR := 0.75
const ENERGY_DRAIN_PER_H := 6.0
const ENERGY_REST_PER_H := 10.0
const NEIGHBOR_BONUS_CAP := 30
const OFFLINE_CAP_HOURS := 12.0    # §2.5: tope de producción sin conexión
const DECISION_WINDOW_H := 1.0 / 3.0  # 20 min para decidir
const HELPER_SPEEDUP := 1.5        # un habitante ayudando en la obra
const RISK_MODIFIERS := {"bajo": 0, "medio": -10, "alto": -25}
const RISK_XP := {"bajo": 1.0, "medio": 1.2, "alto": 1.6}
const DURATION_LOOT := {1: 0.6, 2: 1.0, 4: 1.5, 8: 2.2}
const SUCCESS_BASE := 35
const SUCCESS_LEVEL_OK := 30
const SUCCESS_CLASS_OK := 15
const SUCCESS_PER_TABLE_LEVEL := 4
const SUCCESS_EXTRA_CHAR := 14
const SUCCESS_PISPA := 0
const PISPA_LOOT_BONUS := 0.10

signal shelter_changed
signal room_placed(uid: String, result: Dictionary)
signal rooms_fused(uid: String, room_type: String)
signal cell_dug(floor_idx: int, col: int, result: Dictionary)
signal secret_discovered(secret_id: String, room_uid: String)
signal worker_assigned(char_id: String, room_uid: String, efficiency: float)
signal storage_changed
signal dividend_received(source: String, amount: int)
signal expedition_sent(run_id: String)
signal expedition_event(run_id: String, event: Dictionary)
signal expedition_decided(run_id: String, option_id: String, auto: bool)
signal expedition_finished(run_id: String, result: Dictionary)
signal pispa_changed
signal pispa_returned(loot: Dictionary)
signal bottleneck_fixed(workshop_id: String, solution_id: String, result: Dictionary)
signal upgrade_finished(row_id: String, tier: int)

# --- Datos del seed ----------------------------------------------------------
var shelter_name: String = "El Nido"
var subtitle: String = ""
var cols: int = 6
var level_thresholds: Array = [0, 4, 8, 12, 16, 20]
var base_comfort: int = 20
var base_storage: int = 600
var items: Dictionary = {}
var catalog: Dictionary = {}
var decorations_catalog: Dictionary = {}
var affinity: Dictionary = {}
var comfort_synergy: Dictionary = {}
var dig_cost: Dictionary = {}
var new_floor_rule: Dictionary = {}
var raw_sources: Array = []
var workshops: Array = []
var destinations: Array = []
var expeditions_catalog: Array = []
var goals: Array = []
var mission_needs: Dictionary = {}
var dividend_sources: Dictionary = {}
var upgrade_slots: int = 2

# --- Estado ------------------------------------------------------------------
var clock_h: float = 0.0
var floors: Array = []            # [{name, cells:[{state, room, secret, requires_level}]}]
var rooms: Dictionary = {}        # uid -> room
var surface: Dictionary = {}      # {plots: [...], features: [...]}
var characters: Array = []
var decor: Array = []             # [{id, room}]
var storage: Dictionary = {}
var overflow: Dictionary = {}
var ready_by_room: Dictionary = {}  # uid -> {item: qty} («N listas»)
var dividend_ledger: Array = []   # [{source, npc_id, amount, at}]
var upgrades: Array = []
var active_expeditions: Array = []
var finished_expeditions: Array = []
var pispa: Dictionary = {}
var diverted: Dictionary = {}     # item -> qty/h desviado (p. ej. hierbas a Pispa)
var away_log: Array = []          # «Mientras no estabas»
var knowledge: Node = null        # KnowledgeService (opcional)
var rng := RandomNumberGenerator.new()
## Si >= 0, sustituye la tirada de éxito (0..100) de las expediciones (tests).
var roll_override: float = -1.0

var _uid_serial: int = 0
var _run_serial: int = 0
var _last_tx_index: int = 0


func _init() -> void:
	rng.seed = 1207
	if FileAccess.file_exists(DEFAULT_SEED_PATH):
		load_seed(DEFAULT_SEED_PATH)


func _ready() -> void:
	if knowledge == null:
		var ks := get_node_or_null("/root/KnowledgeService")
		if ks:
			connect_knowledge(ks)


# ==========================================================================
# Seed / persistencia
# ==========================================================================
func load_seed(path: String = DEFAULT_SEED_PATH) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("[ShelterService] No se pudo abrir %s" % path)
		return false
	var data = JSON.parse_string(f.get_as_text())
	if not (data is Dictionary):
		push_warning("[ShelterService] Seed inválido: %s" % path)
		return false
	load_from_seed(data)
	return true


func load_from_seed(data: Dictionary) -> void:
	shelter_name = str(data.get("name", "El Nido"))
	subtitle = str(data.get("subtitle", ""))
	cols = int(data.get("cols", 6))
	level_thresholds = (data.get("level_thresholds", level_thresholds) as Array).duplicate()
	base_comfort = int(data.get("base_comfort", 20))
	base_storage = int(data.get("base_storage", 600))
	items = (data.get("items", {}) as Dictionary).duplicate(true)
	catalog = (data.get("catalog", {}) as Dictionary).duplicate(true)
	decorations_catalog = (data.get("decorations", {}) as Dictionary).duplicate(true)
	affinity = (data.get("affinity", {}) as Dictionary).duplicate(true)
	comfort_synergy = (data.get("comfort_synergy", {}) as Dictionary).duplicate(true)
	dig_cost = (data.get("dig_cost", {}) as Dictionary).duplicate(true)
	new_floor_rule = (data.get("new_floor", {}) as Dictionary).duplicate(true)
	raw_sources = (data.get("raw_sources", []) as Array).duplicate(true)
	workshops = (data.get("workshops", []) as Array).duplicate(true)
	destinations = (data.get("destinations", []) as Array).duplicate(true)
	expeditions_catalog = (data.get("expeditions", []) as Array).duplicate(true)
	goals = (data.get("goals", []) as Array).duplicate(true)
	mission_needs = (data.get("mission_needs", {}) as Dictionary).duplicate(true)
	dividend_sources = (data.get("dividend_sources", {}) as Dictionary).duplicate(true)
	upgrade_slots = int(data.get("upgrade_slots", 2))

	clock_h = 0.0
	_uid_serial = 0
	_run_serial = 0
	rooms.clear()
	floors.clear()
	ready_by_room.clear()
	overflow.clear()
	diverted.clear()
	dividend_ledger.clear()
	away_log.clear()
	storage = {}
	for k in (data.get("storage", {}) as Dictionary):
		storage[k] = int(data["storage"][k])

	var fi := 0
	for fdata in data.get("floors", []):
		var floor_cells: Array = []
		for ci in cols:
			floor_cells.append({"state": CELL_ROCK, "room": ""})
		floors.append({"name": str(fdata.get("name", "Piso %d" % (fi + 1))), "cells": floor_cells})
		var cells_src: Array = fdata.get("cells", [])
		var c := 0
		while c < mini(cells_src.size(), cols):
			var cd: Dictionary = cells_src[c]
			if cd.has("room"):
				var size := int(cd.get("size", 1))
				var uid := _create_room(str(cd["room"]), fi, c, size, int(cd.get("level", 1)))
				var bh := float(cd.get("building_hours", 0.0))
				if bh > 0.0:
					rooms[uid]["status"] = "building"
					rooms[uid]["build_left_h"] = bh
				c += size
				continue
			var st := str(cd.get("state", CELL_ROCK))
			var cell: Dictionary = floor_cells[c]
			if st != CELL_ROOM:
				cell["state"] = st
			if cd.has("secret"):
				cell["secret"] = (cd["secret"] as Dictionary).duplicate(true)
			if cd.has("requires_level"):
				cell["requires_level"] = int(cd["requires_level"])
			c += 1
		fi += 1

	surface = (data.get("surface", {}) as Dictionary).duplicate(true)
	decor = []
	for d in data.get("decor", []):
		var cell := _cell_at(int(d["room"][0]), int(d["room"][1]))
		if not cell.is_empty() and cell["room"] != "":
			decor.append({"id": str(d["id"]), "room": cell["room"]})

	characters = []
	for ch in data.get("characters", []):
		var c2: Dictionary = (ch as Dictionary).duplicate(true)
		c2["level"] = int(c2.get("level", 1))
		c2["xp"] = int(c2.get("xp", 0))
		c2["energy"] = float(c2.get("energy", 80.0))
		c2["status"] = "idle"
		c2["room"] = ""
		c2["loan_hours"] = float(c2.get("loan_hours", 0.0))
		characters.append(c2)
		if ch.has("room") and ch["room"] is Array:
			var cell := _cell_at(int(ch["room"][0]), int(ch["room"][1]))
			if not cell.is_empty() and cell["room"] != "":
				assign_worker(str(c2["id"]), cell["room"])

	upgrades = []
	for row in data.get("upgrades", []):
		var r: Dictionary = (row as Dictionary).duplicate(true)
		for t in r["tiers"]:
			t["status"] = "done" if bool(t.get("done", false)) else ("in_progress" if t.has("in_progress_left") else "")
			t["left_h"] = float(t.get("in_progress_left", 0.0))
		upgrades.append(r)

	pispa = (data.get("pispa", {}) as Dictionary).duplicate(true)
	var bag: Array = []
	for slot in pispa.get("bag", []):
		bag.append({"item": str(slot[0]), "qty": int(slot[1])})
	pispa["bag"] = bag
	pispa["level"] = int(pispa.get("level", 1))
	pispa["xp"] = int(pispa.get("xp", 0))
	pispa["xp_next"] = int(pispa.get("xp_next", 500))
	pispa["affection"] = int(pispa.get("affection", 3))
	pispa["bag_capacity"] = int(pispa.get("bag_capacity", 20))
	pispa["stack_max"] = int(pispa.get("stack_max", 12))
	pispa["follow_in_world"] = bool(pispa.get("follow_in_world", false))
	pispa["on_expedition"] = ""
	pispa["snack_active"] = false
	pispa["last_pet_h"] = -999.0
	var tgt := str(pispa.get("target", "esquirlas"))
	pispa["target"] = tgt
	pispa["trip"] = {}
	_start_pispa_trip()
	if not (pispa["trip"] as Dictionary).is_empty():
		pispa["trip"]["start_h"] = clock_h - float(pispa.get("trip_elapsed_min", 0)) / 60.0
		pispa["trip"]["end_h"] = pispa["trip"]["start_h"] + _pispa_trip_hours(tgt)

	active_expeditions = []
	finished_expeditions = (data.get("finished_expeditions", []) as Array).duplicate(true)
	for a in data.get("active_expeditions", []):
		var res := send_expedition(str(a["exp_id"]), a["chars"], int(a.get("duration", 2)), false, true)
		if res.get("ok", false):
			var run := _find_run(res["run_id"])
			var el := float(a.get("elapsed", 0.0))
			run["start_h"] -= el
			run["end_h"] -= el
			run["event"]["appears_at"] = clock_h
			run["event"]["expires_at"] = clock_h + DECISION_WINDOW_H
	shelter_changed.emit()


## Estado serializable (servidor / app móvil comparten el mismo estado, Anexo D).
func to_dict() -> Dictionary:
	return {
		"clock_h": clock_h, "floors": floors.duplicate(true), "rooms": rooms.duplicate(true),
		"surface": surface.duplicate(true), "characters": characters.duplicate(true),
		"decor": decor.duplicate(true), "storage": storage.duplicate(), "overflow": overflow.duplicate(),
		"ready_by_room": ready_by_room.duplicate(true), "dividend_ledger": dividend_ledger.duplicate(true),
		"upgrades": upgrades.duplicate(true), "active_expeditions": active_expeditions.duplicate(true),
		"finished_expeditions": finished_expeditions.duplicate(true), "pispa": pispa.duplicate(true),
		"uid_serial": _uid_serial, "run_serial": _run_serial,
	}


func load_state(d: Dictionary) -> void:
	clock_h = float(d.get("clock_h", 0.0))
	floors = (d.get("floors", []) as Array).duplicate(true)
	rooms = (d.get("rooms", {}) as Dictionary).duplicate(true)
	surface = (d.get("surface", {}) as Dictionary).duplicate(true)
	characters = (d.get("characters", []) as Array).duplicate(true)
	decor = (d.get("decor", []) as Array).duplicate(true)
	storage = (d.get("storage", {}) as Dictionary).duplicate()
	overflow = (d.get("overflow", {}) as Dictionary).duplicate()
	ready_by_room = (d.get("ready_by_room", {}) as Dictionary).duplicate(true)
	dividend_ledger = (d.get("dividend_ledger", []) as Array).duplicate(true)
	upgrades = (d.get("upgrades", []) as Array).duplicate(true)
	active_expeditions = (d.get("active_expeditions", []) as Array).duplicate(true)
	finished_expeditions = (d.get("finished_expeditions", []) as Array).duplicate(true)
	pispa = (d.get("pispa", {}) as Dictionary).duplicate(true)
	_uid_serial = int(d.get("uid_serial", 0))
	_run_serial = int(d.get("run_serial", 0))
	shelter_changed.emit()


# ==========================================================================
# Corte lateral: pisos, celdas, excavación
# ==========================================================================
func get_floor_count() -> int:
	return floors.size()


func get_floor_name(f: int) -> String:
	return str(floors[f]["name"]) if f >= 0 and f < floors.size() else ""


func get_cell(f: int, c: int) -> Dictionary:
	var cell := _cell_at(f, c)
	return cell.duplicate(true) if not cell.is_empty() else {}


func _cell_at(f: int, c: int) -> Dictionary:
	if f < 0 or f >= floors.size() or c < 0 or c >= cols:
		return {}
	return floors[f]["cells"][c]


## Vista de una celda para la UI: estado, sala, «???», requisito de nivel.
func get_cell_view(f: int, c: int) -> Dictionary:
	var cell := _cell_at(f, c)
	if cell.is_empty():
		return {}
	var v := {"floor": f, "col": c, "state": cell["state"], "room": cell.get("room", "")}
	match str(cell["state"]):
		CELL_SECRET:
			var s: Dictionary = cell.get("secret", {})
			v["title"] = display_secret_name(str(s.get("id", "")))
			v["hint"] = str(s.get("hint", ""))
		CELL_LOCKED:
			v["title"] = "Cimientos"
			v["hint"] = "Más cuartos al subir El Nido a nivel %d" % int(cell.get("requires_level", 0))
		CELL_ROCK:
			v["title"] = "Roca"
			v["hint"] = "Excavar: %s" % format_cost(get_dig_cost(f))
		CELL_EMPTY:
			v["title"] = "Cuarto vacío"
			v["hint"] = "+ Amueblar"
	return v


func get_dig_cost(f: int) -> Dictionary:
	var out := {}
	for k in dig_cost:
		out[k] = int(round(float(dig_cost[k]) * (1.0 + 0.5 * f)))
	return out


func can_dig(f: int, c: int) -> Dictionary:
	var cell := _cell_at(f, c)
	if cell.is_empty():
		return {"ok": false, "reason": "out_of_bounds"}
	var st := str(cell["state"])
	if st == CELL_LOCKED:
		return {"ok": false, "reason": "requires_level", "requires_level": int(cell.get("requires_level", 0))}
	if st != CELL_ROCK and st != CELL_SECRET:
		return {"ok": false, "reason": "not_rock"}
	var cost := get_dig_cost(f)
	if not can_afford(cost):
		return {"ok": false, "reason": "cost", "cost": cost}
	return {"ok": true, "cost": cost, "secret": st == CELL_SECRET}


## Excava roca → hueco. Si era «???», descubre la sala secreta y la manda al Códice.
func dig(f: int, c: int) -> Dictionary:
	var chk := can_dig(f, c)
	if not chk["ok"]:
		return chk
	_pay(chk["cost"])
	var cell := _cell_at(f, c)
	var result := {"ok": true, "floor": f, "col": c, "cost": chk["cost"], "secret": false}
	if str(cell["state"]) == CELL_SECRET:
		var s: Dictionary = cell.get("secret", {})
		cell["state"] = CELL_EMPTY
		var uid := _create_room(str(s.get("room_type", "colmena")), f, c, 1, 1)
		rooms[uid]["secret_id"] = str(s.get("id", ""))
		cell.erase("secret")
		result["secret"] = true
		result["secret_id"] = str(s.get("id", ""))
		result["room_uid"] = uid
		result["name"] = str(s.get("name", "???"))
		if knowledge and knowledge.has_method("discover_entry"):
			result["codex"] = knowledge.discover_entry(str(s.get("id", "")), "lugares", {
				"name": str(s.get("name", "")), "hint": str(s.get("hint", "")),
				"description": "Sala secreta de %s, descubierta excavando el %s." % [shelter_name, get_floor_name(f)],
			})
		_log_away("Descubriste una sala secreta: %s" % result["name"])
		secret_discovered.emit(result["secret_id"], uid)
	else:
		cell["state"] = CELL_EMPTY
	cell_dug.emit(f, c, result)
	shelter_changed.emit()
	return result


## Excava un piso nuevo (todo roca) bajo el último. Requiere nivel del refugio.
func dig_new_floor() -> Dictionary:
	var req := int(new_floor_rule.get("requires_level", 5))
	if get_shelter_level() < req:
		return {"ok": false, "reason": "requires_level", "requires_level": req}
	var cost: Dictionary = new_floor_rule.get("cost", {})
	if not can_afford(cost):
		return {"ok": false, "reason": "cost", "cost": cost}
	_pay(cost)
	var cells: Array = []
	for ci in cols:
		cells.append({"state": CELL_ROCK, "room": ""})
	floors.append({"name": "Profundo %d" % (floors.size() - 2), "cells": cells})
	shelter_changed.emit()
	return {"ok": true, "floor": floors.size() - 1}


func display_secret_name(secret_id: String) -> String:
	if knowledge and knowledge.has_method("display_name"):
		return knowledge.display_name(secret_id)
	return "???"


# ==========================================================================
# Salas: catálogo, colocación, vecindad, fusión
# ==========================================================================
func get_room(uid: String) -> Dictionary:
	return rooms.get(uid, {})


func get_room_at(f: int, c: int) -> Dictionary:
	var cell := _cell_at(f, c)
	if cell.is_empty() or str(cell.get("room", "")) == "":
		return {}
	return rooms.get(cell["room"], {})


func find_rooms(room_type: String) -> Array:
	var out: Array = []
	for uid in rooms:
		if rooms[uid]["type"] == room_type:
			out.append(rooms[uid])
	return out


func room_name(uid: String) -> String:
	var r: Dictionary = rooms.get(uid, {})
	if r.is_empty():
		return ""
	var n := str(catalog.get(r["type"], {}).get("name", r["type"]))
	return n + (" doble" if int(r["size"]) > 1 else "")


func get_buildable_catalog(category: String = "") -> Array:
	var out: Array = []
	for type in catalog:
		var e: Dictionary = catalog[type]
		if not bool(e.get("buildable", true)):
			continue
		if category != "" and str(e.get("category", "")) != category:
			continue
		var v := e.duplicate(true)
		v["type"] = type
		v["kind"] = "room"
		v["affordable"] = can_afford(e.get("cost", {}))
		out.append(v)
	for id in decorations_catalog:
		var d: Dictionary = decorations_catalog[id]
		if category != "" and str(d.get("category", "")) != category:
			continue
		var v2 := d.duplicate(true)
		v2["type"] = id
		v2["kind"] = "decor"
		v2["affordable"] = can_afford(d.get("cost", {}))
		v2["locked"] = get_shelter_level() < int(d.get("requires_level", 0))
		out.append(v2)
	return out


func _create_room(type: String, f: int, c: int, size: int, level: int) -> String:
	_uid_serial += 1
	var uid := "r%d" % _uid_serial
	rooms[uid] = {
		"uid": uid, "type": type, "floor": f, "col": c, "size": size, "level": level,
		"status": "ready", "build_left_h": 0.0, "upgrade_left_h": 0.0, "workers": [], "fused": size > 1,
	}
	for i in size:
		var cell := _cell_at(f, c + i)
		if not cell.is_empty():
			cell["state"] = CELL_ROOM
			cell["room"] = uid
	return uid


## Salas vecinas (izquierda/derecha en el piso y arriba/abajo en las mismas columnas).
func get_neighbors(f: int, c: int, size: int = 1, exclude_uid: String = "") -> Array:
	var seen := {}
	var out: Array = []
	var probes: Array = [[f, c - 1], [f, c + size]]
	for i in size:
		probes.append([f - 1, c + i])
		probes.append([f + 1, c + i])
	for p in probes:
		var r := get_room_at(int(p[0]), int(p[1]))
		if r.is_empty() or r["uid"] == exclude_uid or seen.has(r["uid"]):
			continue
		seen[r["uid"]] = true
		out.append(r)
	return out


## Bonus de producción por vecindad (sumando afinidades únicas, tope 30 %).
func neighbor_bonus_for(type: String, f: int, c: int, size: int = 1, exclude_uid: String = "") -> Dictionary:
	var table: Dictionary = affinity.get(type, {})
	var sources: Array = []
	var seen_types := {}
	var pct := 0
	for r in get_neighbors(f, c, size, exclude_uid):
		var nt: String = r["type"]
		if table.has(nt) and not seen_types.has(nt):
			seen_types[nt] = true
			pct += int(table[nt])
			sources.append({"type": nt, "name": str(catalog.get(nt, {}).get("name", nt)), "pct": int(table[nt])})
	return {"pct": mini(pct, NEIGHBOR_BONUS_CAP), "sources": sources}


func get_neighbor_bonus(uid: String) -> Dictionary:
	var r: Dictionary = rooms.get(uid, {})
	if r.is_empty():
		return {"pct": 0, "sources": []}
	return neighbor_bonus_for(r["type"], int(r["floor"]), int(r["col"]), int(r["size"]), uid)


## Previsualización del modo Construir: si cabe, bonus por vecindad, fusión y confort.
func preview_placement(type: String, f: int, c: int) -> Dictionary:
	if decorations_catalog.has(type):
		return _preview_decor(type, f, c)
	var e: Dictionary = catalog.get(type, {})
	var out := {"type": type, "floor": f, "col": c, "fits": false, "reason": "", "bonus_pct": 0, "sources": [],
		"merge": false, "comfort_before": get_comfort(), "comfort_after": get_comfort()}
	if e.is_empty() or not bool(e.get("buildable", true)):
		out["reason"] = "unknown_room"
		return out
	var cell := _cell_at(f, c)
	if cell.is_empty():
		out["reason"] = "out_of_bounds"
		return out
	var cost: Dictionary = e.get("cost", {})
	out["cost"] = cost
	out["affordable"] = can_afford(cost)
	out["build_hours"] = float(e.get("build_hours", 0))
	out["build_hours_helped"] = float(e.get("build_hours", 0)) / HELPER_SPEEDUP
	match str(cell["state"]):
		CELL_ROCK, CELL_SECRET:
			out["reason"] = "rock"
			return out
		CELL_LOCKED:
			out["reason"] = "locked"
			return out
		CELL_ROOM:
			out["reason"] = "occupied"
			return out
	var nb := neighbor_bonus_for(type, f, c)
	out["bonus_pct"] = nb["pct"]
	out["sources"] = nb["sources"]
	var mate := _merge_candidate(type, f, c)
	out["merge"] = not mate.is_empty()
	if out["merge"]:
		out["merge_with"] = mate["uid"]
	out["comfort_after"] = get_comfort() + int(e.get("comfort", 0)) + _synergy_for(type, f, c)
	out["fits"] = bool(out["affordable"])
	if not out["fits"]:
		out["reason"] = "cost"
	return out


func _preview_decor(id: String, f: int, c: int) -> Dictionary:
	var d: Dictionary = decorations_catalog[id]
	var r := get_room_at(f, c)
	var out := {"type": id, "kind": "decor", "floor": f, "col": c, "fits": false, "reason": "", "bonus_pct": 0, "sources": [],
		"merge": false, "cost": d.get("cost", {}), "comfort_before": get_comfort(), "comfort_after": get_comfort()}
	if get_shelter_level() < int(d.get("requires_level", 0)):
		out["reason"] = "requires_level"
		return out
	if r.is_empty():
		out["reason"] = "needs_room"
		return out
	out["affordable"] = can_afford(d.get("cost", {}))
	out["comfort_after"] = get_comfort() + int(d.get("comfort", 0))
	out["fits"] = bool(out["affordable"])
	out["reason"] = "" if out["fits"] else "cost"
	return out


func _merge_candidate(type: String, f: int, c: int) -> Dictionary:
	for nc in [c - 1, c + 1]:
		var r := get_room_at(f, nc)
		if not r.is_empty() and r["type"] == type and int(r["size"]) == 1:
			return r
	return {}


## Coloca una sala en un hueco. Paga, abre obra y fusiona si hay una igual al lado.
func place_room(type: String, f: int, c: int, helper_id: String = "") -> Dictionary:
	if decorations_catalog.has(type):
		return place_decoration(type, f, c)
	var pv := preview_placement(type, f, c)
	if not pv["fits"]:
		return {"ok": false, "reason": pv["reason"]}
	var e: Dictionary = catalog[type]
	_pay(e.get("cost", {}))
	var uid := _create_room(type, f, c, 1, 1)
	var hours := float(e.get("build_hours", 0))
	if helper_id != "" and not get_character(helper_id).is_empty():
		hours /= HELPER_SPEEDUP
	if hours > 0.0:
		rooms[uid]["status"] = "building"
		rooms[uid]["build_left_h"] = hours
	var result := {"ok": true, "uid": uid, "bonus_pct": pv["bonus_pct"], "fused": false, "build_hours": hours}
	var fused_uid := _try_fuse(uid)
	if fused_uid != "":
		result["fused"] = true
		result["uid"] = fused_uid
	room_placed.emit(result["uid"], result)
	shelter_changed.emit()
	return result


## Dos salas idénticas contiguas → una sala doble (más capacidad y +25 % eficiencia).
func _try_fuse(uid: String) -> String:
	var r: Dictionary = rooms[uid]
	if int(r["size"]) != 1:
		return ""
	var mate := _merge_candidate(r["type"], int(r["floor"]), int(r["col"]))
	if mate.is_empty() or mate["uid"] == uid:
		return ""
	var left: Dictionary = r if int(r["col"]) < int(mate["col"]) else mate
	var right: Dictionary = mate if left["uid"] == r["uid"] else r
	left["size"] = 2
	left["fused"] = true
	left["level"] = maxi(int(left["level"]), int(right["level"]))
	left["build_left_h"] = maxf(float(left["build_left_h"]), float(right["build_left_h"]))
	left["status"] = "building" if float(left["build_left_h"]) > 0.0 else "ready"
	for w in right["workers"]:
		if not (left["workers"] as Array).has(w):
			left["workers"].append(w)
			var ch := _char(w)
			if not ch.is_empty():
				ch["room"] = left["uid"]
	for d in decor:
		if d["room"] == right["uid"]:
			d["room"] = left["uid"]
	if ready_by_room.has(right["uid"]):
		for it in ready_by_room[right["uid"]]:
			_add_ready(left["uid"], it, int(ready_by_room[right["uid"]][it]))
		ready_by_room.erase(right["uid"])
	var cell := _cell_at(int(right["floor"]), int(right["col"]))
	cell["room"] = left["uid"]
	rooms.erase(right["uid"])
	rooms_fused.emit(left["uid"], left["type"])
	return left["uid"]


func place_decoration(id: String, f: int, c: int) -> Dictionary:
	var pv := _preview_decor(id, f, c)
	if not pv["fits"]:
		return {"ok": false, "reason": pv["reason"]}
	_pay(decorations_catalog[id].get("cost", {}))
	var r := get_room_at(f, c)
	decor.append({"id": id, "room": r["uid"]})
	shelter_changed.emit()
	return {"ok": true, "comfort": get_comfort(), "room": r["uid"]}


## Capacidad de obreros de una sala.
func room_capacity(uid: String) -> int:
	var r: Dictionary = rooms.get(uid, {})
	if r.is_empty():
		return 0
	return int(catalog.get(r["type"], {}).get("capacity", 1)) * int(r["size"])


## Mejorar una sala (nivel +1). Sigue produciendo durante la obra.
func room_upgrade_cost(uid: String) -> Dictionary:
	var r: Dictionary = rooms.get(uid, {})
	if r.is_empty():
		return {}
	var out := {}
	var base: Dictionary = catalog.get(r["type"], {}).get("cost", {})
	for k in base:
		out[k] = int(base[k]) * int(r["level"])
	return out


func room_upgrade_hours(uid: String) -> float:
	var r: Dictionary = rooms.get(uid, {})
	return float(catalog.get(r.get("type", ""), {}).get("build_hours", 2)) * int(r.get("level", 1))


func upgrade_room(uid: String) -> Dictionary:
	var r: Dictionary = rooms.get(uid, {})
	if r.is_empty():
		return {"ok": false, "reason": "unknown_room"}
	if float(r["upgrade_left_h"]) > 0.0:
		return {"ok": false, "reason": "already_upgrading"}
	if _busy_works() >= upgrade_slots:
		return {"ok": false, "reason": "no_slot"}
	var cost := room_upgrade_cost(uid)
	if not can_afford(cost):
		return {"ok": false, "reason": "cost", "cost": cost}
	_pay(cost)
	r["upgrade_left_h"] = room_upgrade_hours(uid)
	shelter_changed.emit()
	return {"ok": true, "hours": r["upgrade_left_h"], "to_level": int(r["level"]) + 1}


# ==========================================================================
# Confort
# ==========================================================================
func _synergy_for(type: String, f: int, c: int, size: int = 1, exclude_uid: String = "") -> int:
	var total := 0
	var table: Dictionary = comfort_synergy.get(type, {})
	for r in get_neighbors(f, c, size, exclude_uid):
		total += int(table.get(r["type"], 0))
		total += int(comfort_synergy.get(r["type"], {}).get(type, 0))
	return total


func get_comfort() -> int:
	var total := base_comfort
	var pairs := {}
	for uid in rooms:
		var r: Dictionary = rooms[uid]
		if r["status"] != "ready":
			continue
		total += int(catalog.get(r["type"], {}).get("comfort", 0)) * int(r["size"])
		var table: Dictionary = comfort_synergy.get(r["type"], {})
		for n in get_neighbors(int(r["floor"]), int(r["col"]), int(r["size"]), uid):
			var key := "%s|%s" % [uid, n["uid"]]
			if table.has(n["type"]) and not pairs.has(key):
				pairs[key] = true
				total += int(table[n["type"]])
	for d in decor:
		total += int(decorations_catalog.get(d["id"], {}).get("comfort", 0))
	return total


## Confort → descanso más rápido y un poco más de producción (+0,1 % por punto).
func comfort_production_bonus() -> float:
	return get_comfort() / 1000.0


# ==========================================================================
# Habitantes chibi
# ==========================================================================
func get_characters() -> Array:
	return characters


func get_character(id: String) -> Dictionary:
	return _char(id)


func _char(id: String) -> Dictionary:
	for c in characters:
		if c["id"] == id:
			return c
	return {}


func is_ideal(char_id: String, room_type: String) -> bool:
	return (_char(char_id).get("ideal_rooms", []) as Array).has(room_type)


## Eficiencia de un habitante en un tipo de sala: 1,0 base, ×1,2 en su sala ideal,
## ×0,75 si está agotado (energía < 25).
func worker_efficiency(char_id: String, room_type: String) -> float:
	var ch := _char(char_id)
	if ch.is_empty():
		return 0.0
	var eff := 1.0 + (IDEAL_BONUS if is_ideal(char_id, room_type) else 0.0)
	if float(ch.get("energy", 100.0)) < TIRED_ENERGY:
		eff *= TIRED_FACTOR
	return eff


## Texto para la lista de habitantes: «Huerto · ideal +20 %».
func ideal_label(char_id: String) -> String:
	var ch := _char(char_id)
	var ideal: Array = ch.get("ideal_rooms", [])
	if ideal.is_empty():
		return ""
	return "%s · ideal +%d %%" % [str(catalog.get(ideal[0], {}).get("name", ideal[0])), int(IDEAL_BONUS * 100)]


func can_work(char_id: String) -> bool:
	var ch := _char(char_id)
	return not ch.is_empty() and ch["status"] in ["idle", "working", "resting"]


func assign_worker(char_id: String, room_uid: String) -> Dictionary:
	var ch := _char(char_id)
	var r: Dictionary = rooms.get(room_uid, {})
	if ch.is_empty() or r.is_empty():
		return {"ok": false, "reason": "unknown"}
	if not can_work(char_id):
		return {"ok": false, "reason": "busy", "status": ch["status"]}
	if (r["workers"] as Array).has(char_id):
		return {"ok": true, "efficiency": worker_efficiency(char_id, r["type"]), "ideal": is_ideal(char_id, r["type"])}
	if (r["workers"] as Array).size() >= room_capacity(room_uid):
		return {"ok": false, "reason": "full"}
	unassign_worker(char_id)
	r["workers"].append(char_id)
	ch["room"] = room_uid
	ch["status"] = "working"
	var eff := worker_efficiency(char_id, r["type"])
	worker_assigned.emit(char_id, room_uid, eff)
	shelter_changed.emit()
	return {"ok": true, "efficiency": eff, "ideal": is_ideal(char_id, r["type"]),
		"bonus_pct": int(round((eff - 1.0) * 100.0))}


func unassign_worker(char_id: String) -> void:
	var ch := _char(char_id)
	if ch.is_empty():
		return
	var prev := str(ch.get("room", ""))
	if prev != "" and rooms.has(prev):
		(rooms[prev]["workers"] as Array).erase(char_id)
	ch["room"] = ""
	if ch["status"] == "working":
		ch["status"] = "idle"


## Mejor sala disponible para un habitante (prioriza su sala ideal con hueco).
func best_room_for(char_id: String) -> Dictionary:
	var best := {}
	var best_eff := -1.0
	for uid in rooms:
		var r: Dictionary = rooms[uid]
		if r["status"] != "ready" or not _is_work_room(r["type"]):
			continue
		var has_space := (r["workers"] as Array).has(char_id) or (r["workers"] as Array).size() < room_capacity(uid)
		if not has_space:
			continue
		var eff := worker_efficiency(char_id, r["type"])
		# Desempate: la primera sala ideal de su lista.
		var ideal_list: Array = _char(char_id).get("ideal_rooms", [])
		var score := eff + (0.01 * (ideal_list.size() - ideal_list.find(r["type"])) if ideal_list.has(r["type"]) else 0.0)
		if score > best_eff:
			best_eff = score
			best = {"uid": uid, "type": r["type"], "efficiency": eff, "ideal": is_ideal(char_id, r["type"])}
	return best


## Reparto óptimo (voraz): primero los habitantes con sala ideal libre.
func suggest_assignments() -> Array:
	var out: Array = []
	var occupancy := {}
	for uid in rooms:
		occupancy[uid] = (rooms[uid]["workers"] as Array).size()
	for ch in characters:
		if not can_work(ch["id"]):
			continue
		var best_uid := ""
		var best_eff := 0.0
		for uid in rooms:
			var r: Dictionary = rooms[uid]
			if r["status"] != "ready" or not _is_work_room(r["type"]):
				continue
			var mine := (r["workers"] as Array).has(ch["id"])
			if not mine and int(occupancy[uid]) >= room_capacity(uid):
				continue
			var eff := worker_efficiency(ch["id"], r["type"])
			if eff > best_eff:
				best_eff = eff
				best_uid = uid
		if best_uid != "":
			out.append({"char": ch["id"], "room": best_uid, "efficiency": best_eff, "ideal": best_eff > 1.0 + 0.001})
			if not (rooms[best_uid]["workers"] as Array).has(ch["id"]):
				occupancy[best_uid] = int(occupancy[best_uid]) + 1
	return out


func _is_work_room(type: String) -> bool:
	for w in workshops:
		if w["room_type"] == type:
			return true
	return type in ["taller", "huerto", "mesa_mapas", "cocina", "telar"]


# ==========================================================================
# Almacén central
# ==========================================================================
func get_storage_capacity() -> int:
	var cap := base_storage
	for uid in rooms:
		var r: Dictionary = rooms[uid]
		var s := int(catalog.get(r["type"], {}).get("storage", 0))
		if s > 0:
			var mult := float(r["size"]) * (1.0 + FUSION_BONUS if r["fused"] else 1.0)
			cap += int(s * mult * int(r["level"]))
	for row in upgrades:
		for t in row["tiers"]:
			if t.get("status", "") == "done":
				cap += int(t.get("storage", 0))
	return cap


## Total almacenado (sin contar oro ni esquirlas, que son monedas de refugio).
func get_storage_used() -> int:
	var used := 0
	for k in storage:
		if k in ["oro", "esquirlas"]:
			continue
		used += int(storage[k])
	return used


func get_item(item: String) -> int:
	return int(storage.get(item, 0))


func item_name(item: String) -> String:
	return str(items.get(item, {}).get("name", item.capitalize()))


func item_color(item: String) -> Color:
	return Color(str(items.get(item, {}).get("color", "#c3ccd3")))


## Mete en el almacén. Lo que no cabe va a `overflow` (nada se pierde).
func deposit(item: String, qty: int, _source: String = "") -> int:
	if qty <= 0:
		return 0
	var accepted := qty
	if not (item in ["oro", "esquirlas"]):
		var free := maxi(0, get_storage_capacity() - get_storage_used())
		accepted = mini(qty, free)
		if accepted < qty:
			overflow[item] = int(overflow.get(item, 0)) + (qty - accepted)
	if accepted > 0:
		storage[item] = int(storage.get(item, 0)) + accepted
	storage_changed.emit()
	return accepted


func withdraw(item: String, qty: int) -> bool:
	if int(storage.get(item, 0)) < qty:
		return false
	storage[item] = int(storage[item]) - qty
	storage_changed.emit()
	return true


func is_storage_full() -> bool:
	return get_storage_used() >= get_storage_capacity()


func can_afford(cost: Dictionary) -> bool:
	for k in cost:
		if int(storage.get(k, 0)) < int(cost[k]):
			return false
	return true


func _pay(cost: Dictionary) -> void:
	for k in cost:
		storage[k] = int(storage.get(k, 0)) - int(cost[k])
	storage_changed.emit()


func format_cost(cost: Dictionary) -> String:
	var parts := PackedStringArray()
	for k in cost:
		parts.append("%d %s" % [int(cost[k]), item_name(k).to_lower()])
	return " · ".join(parts) if not parts.is_empty() else "gratis"


# --- Dividendos de inversiones en PNJ (KnowledgeService) ----------------------
func connect_knowledge(ks: Node) -> void:
	knowledge = ks
	if ks == null:
		return
	if ks.has_signal("payout_collected") and not ks.payout_collected.is_connected(_on_payout_collected):
		ks.payout_collected.connect(_on_payout_collected)
	_last_tx_index = (ks.get("transactions") as Array).size() if ks.get("transactions") is Array else 0


## «Cobrar al Refugio» del Códice o de aquí: KnowledgeService envía lo pendiente.
func collect_dividends() -> Dictionary:
	if knowledge == null or not knowledge.has_method("collect_to_shelter"):
		return {"ok": false, "reason": "no_knowledge_service", "amount": 0}
	return knowledge.collect_to_shelter()


func pending_dividends() -> int:
	return int(knowledge.get("pending_payout")) if knowledge and knowledge.get("pending_payout") != null else 0


func _on_payout_collected(amount: int) -> void:
	# Desglose por PNJ a partir de las transacciones registradas desde el último cobro.
	var by_source := {}
	var txs: Array = knowledge.get("transactions") if knowledge else []
	for i in range(mini(_last_tx_index, txs.size()), txs.size()):
		var t: Dictionary = txs[i]
		if str(t.get("type", "")) != "investment":
			continue
		var inv: Dictionary = knowledge.get_investment(str(t.get("investment", ""))) if knowledge.has_method("get_investment") else {}
		var npc := str(inv.get("npc_id", t.get("investment", "")))
		by_source[npc] = int(by_source.get(npc, 0)) + int(t.get("cut", 0))
	_last_tx_index = txs.size()
	var assigned := 0
	for npc in by_source:
		assigned += int(by_source[npc])
	if assigned < amount:
		by_source["otros"] = int(by_source.get("otros", 0)) + (amount - assigned)
	for npc in by_source:
		receive_dividend(npc, int(by_source[npc]))


## Ingreso de un dividendo en el almacén central (oro).
func receive_dividend(npc_id: String, amount: int) -> void:
	if amount <= 0:
		return
	var label := dividend_source_name(npc_id)
	deposit("oro", amount, "dividendo")
	dividend_ledger.append({"npc_id": npc_id, "source": label, "amount": amount, "at_h": clock_h})
	_log_away("+%d oro de dividendos (%s)" % [amount, label])
	dividend_received.emit(label, amount)


func dividend_source_name(npc_id: String) -> String:
	if dividend_sources.has(npc_id):
		return str(dividend_sources[npc_id])
	if knowledge and knowledge.get("investments") is Array:
		for inv in knowledge.investments:
			if str(inv.get("npc_id", "")) == npc_id:
				return str(inv.get("npc_name", inv.get("name", npc_id)))
	return "Inversiones" if npc_id == "otros" else npc_id


func get_dividend_totals() -> Dictionary:
	var out := {}
	for e in dividend_ledger:
		out[e["source"]] = int(out.get(e["source"], 0)) + int(e["amount"])
	return out


# ==========================================================================
# Producción: cadenas y cuellos de botella
# ==========================================================================
func _workshop(id: String) -> Dictionary:
	for w in workshops:
		if w["id"] == id:
			return w
	return {}


func get_workshop_rooms(id: String) -> Array:
	var w := _workshop(id)
	return find_rooms(str(w.get("room_type", "")))


## Ritmo de llegada de una materia prima (por hora), incluido el boost de salas.
func raw_rate(item: String) -> float:
	var rate := 0.0
	for s in raw_sources:
		if s["id"] == item:
			rate += float(s["rate"])
	for uid in rooms:
		var r: Dictionary = rooms[uid]
		if r["status"] != "ready":
			continue
		var boost: Dictionary = catalog.get(r["type"], {}).get("raw_boost", {})
		if boost.has(item):
			rate += float(boost[item]) * int(r["level"]) * int(r["size"])
	return maxf(0.0, rate - float(diverted.get(item, 0.0)))


## Capacidad del taller en ciclos/h sumando todas sus salas listas con obreros.
func workshop_capacity(id: String) -> float:
	var w := _workshop(id)
	if w.is_empty():
		return 0.0
	var cap := 0.0
	for r in get_workshop_rooms(id):
		if r["status"] != "ready":
			continue
		var workers := 0.0
		for cid in r["workers"]:
			workers += worker_efficiency(cid, r["type"])
		if workers <= 0.0:
			continue
		var staff := minf(workers, 1.0 + 0.5 * (room_capacity(r["uid"]) - 1)) if workers > 1.0 else workers
		var size_mult := float(r["size"]) * (1.0 + FUSION_BONUS if r["fused"] else 1.0)
		var nb := float(get_neighbor_bonus(r["uid"])["pct"]) / 100.0
		cap += float(w["base_rate"]) * int(r["level"]) * size_mult * staff * (1.0 + nb)
	return cap * (1.0 + comfort_production_bonus())


func _workshop_supply(w: Dictionary) -> float:
	var supply := INF
	for it in w["inputs"]:
		supply = minf(supply, raw_rate(it) / float(w["inputs"][it]))
	return 0.0 if supply == INF else supply


func _demand_for(item: String) -> float:
	var d := 0.0
	for dest in destinations:
		d += float(dest.get("demand", {}).get(item, 0))
	return d


func _workshop_demand(w: Dictionary) -> float:
	var d := 0.0
	for it in w["outputs"]:
		d = maxf(d, _demand_for(it) / float(w["outputs"][it]))
	return d


func workshop_status(id: String) -> Dictionary:
	var w := _workshop(id)
	var rs := get_workshop_rooms(id)
	var out := {"id": id, "name": w.get("name", id), "status": "ok", "usage": 0.0, "capacity": 0.0,
		"supply": 0.0, "demand": 0.0, "building_left_h": 0.0, "upgrading": false}
	if rs.is_empty():
		out["status"] = "missing"
		return out
	var all_building := true
	for r in rs:
		if r["status"] == "ready":
			all_building = false
		else:
			out["building_left_h"] = maxf(float(out["building_left_h"]), float(r["build_left_h"]))
		if float(r["upgrade_left_h"]) > 0.0:
			out["upgrading"] = true
			out["upgrade_left_h"] = float(r["upgrade_left_h"])
	if all_building:
		out["status"] = "building"
		return out
	var cap := workshop_capacity(id)
	var supply := _workshop_supply(w)
	var demand := _workshop_demand(w)
	out["capacity"] = cap
	out["supply"] = supply
	out["demand"] = demand
	out["output_rate"] = minf(cap, supply)
	out["usage"] = 1.0 if cap <= 0.0 else clampf(supply / cap, 0.0, 1.0)
	if cap <= 0.0:
		out["status"] = "jam"
		out["cause"] = "no_worker"
	elif supply > cap + 0.01 and demand > cap + 0.01:
		out["status"] = "jam"
		out["cause"] = "capacity"
	elif demand > supply + 0.01 and supply < cap:
		out["status"] = "jam"
		out["cause"] = "input_shortage"
	return out


## Diagnóstico reactivo: atascos con causa legible y soluciones de 1 clic.
func diagnose() -> Array:
	var out: Array = []
	for w in workshops:
		var st := workshop_status(w["id"])
		if st["status"] != "jam":
			continue
		var b := {"workshop": w["id"], "name": w["name"], "cause": st["cause"], "resolving": bool(st["upgrading"]), "solutions": []}
		var first_in := str((w["inputs"] as Dictionary).keys()[0])
		var first_out := str((w["outputs"] as Dictionary).keys()[0])
		var rs := get_workshop_rooms(w["id"])
		var main: Dictionary = rs[0]
		match st["cause"]:
			"capacity":
				var waiting := get_item(first_in)
				b["message"] = "%d %s esperan. Tu misión y el mercado piden más %s de los que salen." % [
					waiting, item_name(first_in).to_lower(), item_name(first_out).to_lower()]
				b["solutions"].append({"id": "upgrade", "label": "Mejorar a nivel %d" % (int(main["level"]) + 1), "primary": true})
				b["solutions"].append({"id": "build_second", "label": "Construir una 2.ª"})
				b["solutions"].append({"id": "divert", "label": "Mandar %s a Pispa" % item_name(first_in).to_lower(), "item": first_in})
			"no_worker":
				b["message"] = "Nadie trabaja en %s: la cadena está parada." % w["name"]
				b["solutions"].append({"id": "assign", "label": "Asignar al mejor habitante", "primary": true})
			"input_shortage":
				var short := _shortest_input(w)
				b["message"] = "Falta %s: llega menos de lo que piden tus metas." % item_name(short).to_lower()
				b["solutions"].append({"id": "pispa_target", "label": "Pispa busca %s" % item_name(short).to_lower(), "item": short, "primary": true})
		if b["resolving"]:
			b["message"] += " Mejora en obra: %s." % format_hours(float(st.get("upgrade_left_h", 0.0)))
		out.append(b)
	if is_storage_full():
		out.append({"workshop": "almacen", "name": "Almacén", "cause": "storage_full", "resolving": false,
			"message": "El almacén está lleno: lo que sobra espera aparte, nada se pierde.",
			"solutions": [{"id": "expand_storage", "label": "Construir otro almacén", "primary": true}]})
	return out


func _shortest_input(w: Dictionary) -> String:
	var best := ""
	var best_v := INF
	for it in w["inputs"]:
		var v := raw_rate(it) / float(w["inputs"][it])
		if v < best_v:
			best_v = v
			best = it
	return best


## Aplica la solución de 1 clic de un atasco.
func apply_fix(workshop_id: String, solution_id: String) -> Dictionary:
	var result := {"ok": false, "reason": "unknown_solution"}
	var w := _workshop(workshop_id)
	var rs := get_workshop_rooms(workshop_id)
	match solution_id:
		"upgrade":
			if not rs.is_empty():
				result = upgrade_room(rs[0]["uid"])
		"build_second":
			var spot := find_free_cell(str(w.get("room_type", "")))
			if spot.is_empty():
				result = {"ok": false, "reason": "no_space"}
			else:
				result = place_room(str(w["room_type"]), int(spot["floor"]), int(spot["col"]))
		"divert":
			var item := str((w["inputs"] as Dictionary).keys()[0])
			var st := workshop_status(workshop_id)
			var excess := maxf(0.0, (float(st["supply"]) - float(st["capacity"])) * float(w["inputs"][item]))
			diverted[item] = float(diverted.get(item, 0.0)) + excess
			if not _pispa_target(item).is_empty():
				set_pispa_target(item)
			result = {"ok": true, "item": item, "per_hour": excess}
		"assign":
			var best_char := ""
			var best_eff := 0.0
			var room: Dictionary = rs[0] if not rs.is_empty() else {}
			for ch in characters:
				if room.is_empty() or not can_work(ch["id"]) or str(ch.get("room", "")) != "":
					continue
				var eff := worker_efficiency(ch["id"], room["type"])
				if eff > best_eff:
					best_eff = eff
					best_char = ch["id"]
			result = assign_worker(best_char, room["uid"]) if best_char != "" else {"ok": false, "reason": "no_free_worker"}
		"pispa_target":
			var short := _shortest_input(w)
			result = set_pispa_target(short)
		"expand_storage":
			var spot2 := find_free_cell("almacen")
			result = place_room("almacen", int(spot2["floor"]), int(spot2["col"])) if not spot2.is_empty() else {"ok": false, "reason": "no_space"}
	bottleneck_fixed.emit(workshop_id, solution_id, result)
	shelter_changed.emit()
	return result


## Hueco libre preferido para un tipo de sala (el de más bonus por vecindad).
func find_free_cell(type: String) -> Dictionary:
	var best := {}
	var best_score := -1
	for f in floors.size():
		for c in cols:
			if str(_cell_at(f, c)["state"]) != CELL_EMPTY:
				continue
			var score := int(neighbor_bonus_for(type, f, c)["pct"]) + (50 if not _merge_candidate(type, f, c).is_empty() else 0)
			if score > best_score:
				best_score = score
				best = {"floor": f, "col": c, "score": score}
	return best


## Grafo para el esquema de Producción: columnas materias → talleres → productos → destino.
func get_production_graph() -> Dictionary:
	var raw: Array = []
	for s in raw_sources:
		raw.append({"id": s["id"], "name": item_name(s["id"]), "detail": "%d /h · %s" % [int(round(raw_rate(s["id"]))), s["source"]], "color": item_color(s["id"])})
	var shops: Array = []
	var products: Array = []
	var edges: Array = []
	for w in workshops:
		var st := workshop_status(w["id"])
		var detail := ""
		match st["status"]:
			"building":
				detail = "construyendo · %s" % format_hours(float(st["building_left_h"]))
			"missing":
				detail = "sin sala"
			"jam":
				detail = "%d %% · atascada" % int(round(float(st["usage"]) * 100.0)) if st["cause"] == "capacity" else ("sin obreros" if st["cause"] == "no_worker" else "falta materia")
			_:
				detail = "%d %% de uso" % int(round(float(st["usage"]) * 100.0))
		shops.append({"id": w["id"], "name": w["name"], "detail": detail, "status": st["status"], "color": Color(str(catalog.get(w["room_type"], {}).get("color", "#9aa6ae")))})
		var edge_status := "jam" if st["status"] == "jam" else ("building" if st["status"] == "building" else "ok")
		for it in w["inputs"]:
			edges.append({"from": "raw:" + it, "to": "shop:" + w["id"], "status": edge_status})
		for it in w["outputs"]:
			var rate := float(st.get("output_rate", 0.0)) * float(w["outputs"][it])
			var pd := "pronto" if st["status"] == "building" else "%d /h" % int(round(rate))
			products.append({"id": it, "name": item_name(it), "detail": pd, "status": edge_status if edge_status == "building" else "ok", "color": item_color(it)})
			edges.append({"from": "shop:" + w["id"], "to": "prod:" + it, "status": edge_status})
	var dests: Array = []
	for d in destinations:
		var highlight: bool = d["kind"] == "mission"
		dests.append({"id": d["id"], "name": d["name"], "detail": d.get("detail", ""), "kind": d["kind"], "highlight": highlight})
		for it in d.get("demand", {}):
			var shop_jam := false
			var building := false
			for w in workshops:
				if (w["outputs"] as Dictionary).has(it):
					var st2 := workshop_status(w["id"])
					shop_jam = st2["status"] == "jam"
					building = st2["status"] == "building"
			edges.append({"from": "prod:" + it, "to": "dest:" + d["id"], "status": "jam" if shop_jam and highlight else ("building" if building else "ok")})
	return {"raw": raw, "workshops": shops, "products": products, "destinations": dests, "edges": edges}


# ==========================================================================
# Tiempo: producción, obras, descanso, expediciones, Pispa
# ==========================================================================
## Avanza el reloj virtual. Devuelve un resumen de lo ocurrido.
func tick(hours: float) -> Dictionary:
	var summary := {"hours": hours, "produced": {}, "finished_runs": [], "auto_decisions": 0, "pispa_trips": 0}
	if hours <= 0.0:
		return summary
	# Pasos de como mucho 15 min para que los eventos caigan en orden.
	var left := hours
	while left > 0.0001:
		var step := minf(left, 0.25)
		_step(step, summary)
		left -= step
	shelter_changed.emit()
	return summary


## Vuelta tras estar fuera: tope de 12 h (§2.5) y resumen «Mientras no estabas».
func apply_offline(hours: float) -> Dictionary:
	away_log.clear()
	var h := minf(hours, OFFLINE_CAP_HOURS)
	var s := tick(h)
	s["capped"] = hours > OFFLINE_CAP_HOURS
	s["away_log"] = away_log.duplicate()
	return s


func _step(dt: float, summary: Dictionary) -> void:
	clock_h += dt
	# Obras de salas y mejoras de sala.
	for uid in rooms.keys():
		var r: Dictionary = rooms[uid]
		if r["status"] == "building":
			r["build_left_h"] = maxf(0.0, float(r["build_left_h"]) - dt)
			if r["build_left_h"] <= 0.0:
				r["status"] = "ready"
				_log_away("Terminó la obra: %s" % room_name(uid))
		if float(r["upgrade_left_h"]) > 0.0:
			r["upgrade_left_h"] = maxf(0.0, float(r["upgrade_left_h"]) - dt)
			if r["upgrade_left_h"] <= 0.0:
				r["level"] = int(r["level"]) + 1
				_log_away("%s sube a nivel %d" % [room_name(uid), int(r["level"])])
	# Mejoras del árbol.
	for row in upgrades:
		var tiers: Array = row["tiers"]
		for i in tiers.size():
			var t: Dictionary = tiers[i]
			if t.get("status", "") == "in_progress":
				t["left_h"] = maxf(0.0, float(t["left_h"]) - dt)
				if t["left_h"] <= 0.0:
					t["status"] = "done"
					_apply_upgrade_effect(row, i)
					upgrade_finished.emit(row["id"], i)
	# Materias primas al almacén.
	for s in raw_sources:
		var it: String = s["id"]
		var amount := raw_rate(it) * dt
		_accumulate(summary, it, amount)
	# Talleres: consumen del almacén, el producto queda «listo» en la sala.
	for w in workshops:
		var cap := workshop_capacity(w["id"]) * dt
		if cap <= 0.0:
			continue
		var crafts := cap
		for it in w["inputs"]:
			crafts = minf(crafts, float(get_item(it)) / float(w["inputs"][it]))
		var whole := int(floor(crafts + float(w.get("_carry", 0.0))))
		w["_carry"] = crafts + float(w.get("_carry", 0.0)) - whole
		if whole <= 0:
			continue
		for it in w["inputs"]:
			withdraw(it, whole * int(w["inputs"][it]))
		var rs := get_workshop_rooms(w["id"])
		var target_uid := ""
		for r in rs:
			if r["status"] == "ready":
				target_uid = r["uid"]
				break
		for it in w["outputs"]:
			_add_ready(target_uid, it, whole * int(w["outputs"][it]))
	# Parcelas de la superficie.
	for p in surface.get("plots", []):
		p["progress_hours"] = minf(float(p.get("grow_hours", 1.0)), float(p.get("progress_hours", 0.0)) + dt)
	# Energía de los habitantes.
	var rest_mult := 1.0 + get_comfort() / 100.0
	for ch in characters:
		match ch["status"]:
			"working":
				ch["energy"] = maxf(0.0, float(ch["energy"]) - ENERGY_DRAIN_PER_H * dt)
			"idle", "resting":
				ch["energy"] = minf(100.0, float(ch["energy"]) + ENERGY_REST_PER_H * rest_mult * dt)
		if float(ch.get("loan_hours", 0.0)) > 0.0:
			ch["loan_hours"] = maxf(0.0, float(ch["loan_hours"]) - dt)
			if ch["loan_hours"] <= 0.0:
				unassign_worker(ch["id"])
				ch["status"] = "returned"
				_log_away("%s volvió con su dueño" % ch["name"])
	_step_expeditions(summary)
	_step_pispa(summary)


func _accumulate(summary: Dictionary, item: String, amount: float) -> void:
	var key := "_frac_" + item
	var total := amount + float(summary.get(key, 0.0))
	var whole := int(floor(total))
	summary[key] = total - whole
	if whole > 0:
		deposit(item, whole, "produccion")
		summary["produced"][item] = int(summary["produced"].get(item, 0)) + whole


func _add_ready(uid: String, item: String, qty: int) -> void:
	if qty <= 0:
		return
	if uid == "":
		deposit(item, qty)
		return
	if not ready_by_room.has(uid):
		ready_by_room[uid] = {}
	ready_by_room[uid][item] = int(ready_by_room[uid].get(item, 0)) + qty


func get_ready_count(uid: String) -> int:
	var total := 0
	for it in ready_by_room.get(uid, {}):
		total += int(ready_by_room[uid][it])
	return total


## Fuentes con algo para recoger («Recoger todo · N»).
func get_collectables() -> Array:
	var out: Array = []
	for uid in ready_by_room:
		var n := get_ready_count(uid)
		if n > 0 and rooms.has(uid):
			out.append({"kind": "room", "id": uid, "label": "%s · %d listas" % [room_name(uid), n], "qty": n})
	for p in surface.get("plots", []):
		if float(p.get("progress_hours", 0.0)) >= float(p.get("grow_hours", 1.0)):
			out.append({"kind": "plot", "id": p["id"], "label": "%s · %d listas" % [p["name"], int(p["yield"])], "qty": int(p["yield"])})
	if pispa_bag_used() > 0:
		out.append({"kind": "pispa", "id": "pispa", "label": "Bolsa de Pispa · %d" % pispa_bag_items(), "qty": pispa_bag_items()})
	if pending_dividends() > 0:
		out.append({"kind": "dividends", "id": "dividends", "label": "Dividendos · %d oro" % pending_dividends(), "qty": pending_dividends()})
	return out


## «Recoger todo»: salas, parcelas, bolsa de Pispa y dividendos → almacén central.
func collect_all() -> Dictionary:
	var got := {}
	var sources := 0
	for c in get_collectables():
		sources += 1
		match c["kind"]:
			"room":
				for it in ready_by_room[c["id"]]:
					var q := int(ready_by_room[c["id"]][it])
					deposit(it, q, "sala")
					got[it] = int(got.get(it, 0)) + q
				ready_by_room.erase(c["id"])
			"plot":
				for p in surface["plots"]:
					if p["id"] == c["id"]:
						deposit(str(p["crop"]), int(p["yield"]), "parcela")
						got[p["crop"]] = int(got.get(p["crop"], 0)) + int(p["yield"])
						p["progress_hours"] = 0.0
			"pispa":
				var bag := empty_pispa_bag()
				for it in bag["items"]:
					got[it] = int(got.get(it, 0)) + int(bag["items"][it])
			"dividends":
				var res := collect_dividends()
				if res.get("ok", false):
					got["oro"] = int(got.get("oro", 0)) + int(res["amount"])
	shelter_changed.emit()
	return {"ok": sources > 0, "sources": sources, "items": got}


func _log_away(text: String) -> void:
	away_log.append(text)
	if away_log.size() > 12:
		away_log.pop_front()


static func format_hours(h: float) -> String:
	var mins := int(round(h * 60.0))
	if mins < 60:
		return "%d min" % mins
	return "%d:%02d h" % [mins / 60, mins % 60]


# ==========================================================================
# Expediciones
# ==========================================================================
func get_expedition(exp_id: String) -> Dictionary:
	for e in expeditions_catalog:
		if e["id"] == exp_id:
			return e
	return {}


func get_table_level() -> int:
	var lvl := 0
	for r in find_rooms("mesa_mapas"):
		lvl = maxi(lvl, int(r["level"]))
	return lvl


## Personajes secundarios disponibles (el principal no viaja; los prestados tampoco).
func get_available_for_expedition() -> Array:
	var out: Array = []
	for ch in characters:
		if bool(ch.get("is_player", false)) or str(ch.get("loaned_by", "")) != "":
			continue
		if ch["status"] in ["expedition", "returned"]:
			continue
		out.append(ch)
	return out


## Probabilidad de éxito y sus factores (MMO-Expediciones: 78 % → 92 % con 2).
func success_chance(exp_id: String, char_ids: Array, with_pispa: bool = false) -> Dictionary:
	var e := get_expedition(exp_id)
	var factors: Array = []
	if e.is_empty() or char_ids.is_empty():
		return {"pct": 0, "factors": factors}
	var pct := SUCCESS_BASE
	var avg := 0.0
	var class_ok := false
	for cid in char_ids:
		var ch := _char(cid)
		avg += float(ch.get("level", 1))
		if (e.get("recommended_roles", []) as Array).has(ch.get("role", "")):
			class_ok = true
	avg /= char_ids.size()
	if avg >= float(e.get("recommended_level", 1)):
		pct += SUCCESS_LEVEL_OK
		factors.append({"label": "Nivel adecuado", "value": SUCCESS_LEVEL_OK})
	else:
		var pen := -int(round((float(e["recommended_level"]) - avg) * 2.0))
		pct += pen
		factors.append({"label": "Nivel bajo", "value": pen})
	if class_ok or (e.get("recommended_roles", []) as Array).is_empty():
		pct += SUCCESS_CLASS_OK
		factors.append({"label": "Clase recomendada", "value": SUCCESS_CLASS_OK})
	var tl := get_table_level()
	if tl > 0:
		pct += tl * SUCCESS_PER_TABLE_LEVEL
		factors.append({"label": "Mesa de expediciones nv %d" % tl, "value": tl * SUCCESS_PER_TABLE_LEVEL})
	var risk := int(RISK_MODIFIERS.get(e.get("risk", "medio"), 0))
	if risk != 0:
		pct += risk
		factors.append({"label": "Riesgo %s" % e["risk"], "value": risk})
	if char_ids.size() >= 2:
		pct += SUCCESS_EXTRA_CHAR * (char_ids.size() - 1)
		factors.append({"label": "%d personajes" % char_ids.size(), "value": SUCCESS_EXTRA_CHAR * (char_ids.size() - 1)})
	if char_ids.size() < int(e.get("min_chars", 1)):
		pct -= 30
		factors.append({"label": "Faltan personajes", "value": -30})
	return {"pct": clampi(pct, 5, 98), "factors": factors}


func expedition_xp(exp_id: String, duration_h: int) -> int:
	var e := get_expedition(exp_id)
	return int(round(duration_h * 60.0 * float(RISK_XP.get(e.get("risk", "medio"), 1.0))))


static func xp_to_next(level: int) -> int:
	return 100 + level * 10


func expedition_return_time(duration_h: int) -> float:
	return clock_h + duration_h


func send_expedition(exp_id: String, char_ids: Array, duration_h: int, with_pispa: bool = false, _from_seed: bool = false) -> Dictionary:
	var e := get_expedition(exp_id)
	if e.is_empty():
		return {"ok": false, "reason": "unknown_expedition"}
	if char_ids.is_empty():
		return {"ok": false, "reason": "no_characters"}
	if not (e.get("durations", []) as Array).has(float(duration_h)) and not (e.get("durations", []) as Array).has(duration_h):
		return {"ok": false, "reason": "bad_duration"}
	for cid in char_ids:
		var ch := _char(cid)
		if ch.is_empty():
			return {"ok": false, "reason": "unknown_character", "char": cid}
		if bool(ch.get("is_player", false)):
			return {"ok": false, "reason": "main_character", "char": cid}
		if str(ch.get("loaned_by", "")) != "":
			return {"ok": false, "reason": "loaned", "char": cid}
		if ch["status"] == "expedition":
			return {"ok": false, "reason": "busy", "char": cid}
	if with_pispa and str(pispa.get("on_expedition", "")) != "":
		return {"ok": false, "reason": "pispa_busy"}
	var chance := success_chance(exp_id, char_ids, with_pispa)
	_run_serial += 1
	var run_id := "x%d" % _run_serial
	var ids: Array = []
	for cid in char_ids:
		ids.append(str(cid))
		unassign_worker(cid)
		var traveler := _char(cid)
		traveler["status"] = "expedition"
	var names := PackedStringArray()
	for cid in ids:
		names.append(str(_char(cid)["name"]))
	var ev: Dictionary = (e.get("event", {}) as Dictionary).duplicate(true)
	if not ev.is_empty():
		ev["text"] = str(ev.get("text", "")).replace("{who}", " y ".join(names))
		ev["appears_at"] = clock_h + duration_h * 0.5
		ev["expires_at"] = clock_h + duration_h * 0.5 + DECISION_WINDOW_H
		ev["choice"] = ""
		ev["auto"] = false
	var run := {"run_id": run_id, "exp_id": exp_id, "name": e["name"], "chars": ids, "duration": duration_h,
		"start_h": clock_h, "end_h": clock_h + duration_h, "success_pct": chance["pct"], "with_pispa": with_pispa,
		"event": ev, "loot_mult": 1.0, "success_delta": 0}
	active_expeditions.append(run)
	if with_pispa:
		pispa["on_expedition"] = run_id
		pispa["trip"] = {}
	expedition_sent.emit(run_id)
	shelter_changed.emit()
	return {"ok": true, "run_id": run_id, "success_pct": chance["pct"], "returns_at": run["end_h"]}


func _find_run(run_id: String) -> Dictionary:
	for r in active_expeditions:
		if r["run_id"] == run_id:
			return r
	return {}


func get_run(run_id: String) -> Dictionary:
	return _find_run(run_id)


func run_progress(run: Dictionary) -> float:
	var dur := float(run["end_h"]) - float(run["start_h"])
	return 1.0 if dur <= 0.0 else clampf((clock_h - float(run["start_h"])) / dur, 0.0, 1.0)


## Decisiones abiertas ahora mismo (en el juego o en la app móvil).
func get_pending_decisions() -> Array:
	var out: Array = []
	for run in active_expeditions:
		var ev: Dictionary = run.get("event", {})
		if ev.is_empty() or str(ev.get("choice", "")) != "":
			continue
		if clock_h >= float(ev["appears_at"]) - 0.0001:
			out.append({"run_id": run["run_id"], "event": ev, "who": run["chars"], "expires_in_h": maxf(0.0, float(ev["expires_at"]) - clock_h)})
	return out


func resolve_decision(run_id: String, option_id: String, auto: bool = false) -> Dictionary:
	var run := _find_run(run_id)
	if run.is_empty():
		return {"ok": false, "reason": "unknown_run"}
	var ev: Dictionary = run.get("event", {})
	if ev.is_empty() or str(ev.get("choice", "")) != "":
		return {"ok": false, "reason": "no_pending_decision"}
	var opt := {}
	for o in ev["options"]:
		if o["id"] == option_id:
			opt = o
	if opt.is_empty():
		return {"ok": false, "reason": "unknown_option"}
	ev["choice"] = option_id
	ev["auto"] = auto
	run["loot_mult"] = float(opt.get("loot_mult", 1.0))
	run["success_delta"] = int(opt.get("success_delta", 0))
	run["success_pct"] = clampi(int(run["success_pct"]) + int(run["success_delta"]), 5, 98)
	expedition_decided.emit(run_id, option_id, auto)
	shelter_changed.emit()
	return {"ok": true, "option": option_id, "auto": auto, "safe": bool(opt.get("safe", false))}


func safe_option(ev: Dictionary) -> String:
	for o in ev.get("options", []):
		if bool(o.get("safe", false)):
			return o["id"]
	return str(ev["options"][0]["id"]) if not (ev.get("options", []) as Array).is_empty() else ""


func _step_expeditions(summary: Dictionary) -> void:
	for run in active_expeditions.duplicate():
		var ev: Dictionary = run.get("event", {})
		if not ev.is_empty() and str(ev.get("choice", "")) == "":
			if not bool(ev.get("_announced", false)) and clock_h >= float(ev["appears_at"]):
				ev["_announced"] = true
				expedition_event.emit(run["run_id"], ev)
			if clock_h >= float(ev["expires_at"]):
				# Sin respuesta: el personaje elige el camino seguro.
				resolve_decision(run["run_id"], safe_option(ev), true)
				summary["auto_decisions"] = int(summary["auto_decisions"]) + 1
				_log_away("%s eligió el camino seguro" % _char(run["chars"][0]).get("name", ""))
		if clock_h >= float(run["end_h"]) - 0.0001:
			summary["finished_runs"].append(_finish_expedition(run))


func _finish_expedition(run: Dictionary) -> Dictionary:
	var e := get_expedition(run["exp_id"])
	var ev: Dictionary = run.get("event", {})
	if not ev.is_empty() and str(ev.get("choice", "")) == "":
		resolve_decision(run["run_id"], safe_option(ev), true)
	var roll := roll_override if roll_override >= 0.0 else rng.randf() * 100.0
	var pct := int(run["success_pct"])
	var outcome := "success" if roll < pct else ("partial" if roll < pct + 15 else "fail")
	var mult := float(DURATION_LOOT.get(int(run["duration"]), 1.0)) * float(run["loot_mult"])
	if run["with_pispa"]:
		mult *= 1.0 + PISPA_LOOT_BONUS
	match outcome:
		"partial":
			mult *= 0.6
		"fail":
			mult *= 0.2
	var loot := {}
	for it in e.get("rewards", {}):
		var rng_pair: Array = e["rewards"][it]
		var base := (float(rng_pair[0]) + float(rng_pair[1])) * 0.5
		loot[it] = int(round(base * mult))
	var rare: Dictionary = e.get("rare", {})
	if outcome == "success" and not rare.is_empty():
		var rare_roll := roll if roll_override >= 0.0 else rng.randf() * 100.0
		if rare_roll < float(rare.get("pct", 0)):
			loot[rare["item"]] = 1
	for it in loot:
		deposit(it, int(loot[it]), "expedicion")
	var xp := expedition_xp(run["exp_id"], int(run["duration"]))
	if outcome == "fail":
		xp = int(xp * 0.5)
	var levels := {}
	var names := PackedStringArray()
	for cid in run["chars"]:
		var ch := _char(cid)
		if ch.is_empty():
			continue
		names.append(str(ch["name"]))
		var before := int(ch["level"])
		ch["xp"] = int(ch["xp"]) + xp
		while int(ch["xp"]) >= xp_to_next(int(ch["level"])):
			ch["xp"] = int(ch["xp"]) - xp_to_next(int(ch["level"]))
			ch["level"] = int(ch["level"]) + 1
		levels[cid] = int(ch["level"]) - before
		ch["status"] = "idle"
	if run["with_pispa"]:
		pispa["on_expedition"] = ""
	active_expeditions.erase(run)
	var parts := PackedStringArray()
	for it in loot:
		parts.append("+%d %s" % [int(loot[it]), item_name(it).to_lower()])
	var result := {"run_id": run["run_id"], "outcome": outcome, "loot": loot, "xp": xp, "levels": levels,
		"name": "%s · %s" % [" y ".join(names), run["name"]], "auto": bool(ev.get("auto", false)),
		"summary": " · ".join(parts) + (" · sin penalización" if outcome == "fail" else "")}
	finished_expeditions.push_front(result)
	_log_away("%s volvió: %s" % [" y ".join(names), {"success": "éxito", "partial": "éxito parcial", "fail": "fallida"}[outcome]])
	expedition_finished.emit(run["run_id"], result)
	return result


# ==========================================================================
# Pispa: mascota recolectora
# ==========================================================================
func get_nest_level() -> int:
	for row in upgrades:
		if row["id"] == "nido_pispa":
			var n := 0
			for t in row["tiers"]:
				if t.get("status", "") == "done":
					n += 1
			return n
	return 1


func _pispa_target(id: String) -> Dictionary:
	for t in pispa.get("targets", []):
		if t["id"] == id:
			return t
	return {}


## Objetivos con ★ si la misión actual pide ese recurso; bloqueados por nivel del nido.
func get_pispa_targets() -> Array:
	var out: Array = []
	for t in pispa.get("targets", []):
		var v: Dictionary = t.duplicate(true)
		var mi := str(t.get("mission_item", ""))
		v["mission_star"] = mi != "" and int(mission_needs.get(mi, 0)) > 0
		v["mission_text"] = "★ Tu misión pide %d más" % int(mission_needs.get(mi, 0)) if v["mission_star"] else ""
		v["locked"] = get_nest_level() < int(t.get("requires_nest", 0))
		v["selected"] = t["id"] == pispa.get("target", "")
		out.append(v)
	return out


func set_pispa_target(id: String) -> Dictionary:
	var t := _pispa_target(id)
	if t.is_empty():
		return {"ok": false, "reason": "unknown_target"}
	if get_nest_level() < int(t.get("requires_nest", 0)):
		return {"ok": false, "reason": "requires_nest", "requires_nest": int(t["requires_nest"])}
	pispa["target"] = id
	# El cambio se aplica en el próximo viaje; si está en casa, sale ya.
	if (pispa.get("trip", {}) as Dictionary).is_empty():
		_start_pispa_trip()
	pispa_changed.emit()
	return {"ok": true, "target": id, "minutes": int(t["minutes"])}


func _pispa_trip_hours(id: String) -> float:
	var t := _pispa_target(id)
	var h := float(t.get("minutes", 30)) / 60.0
	return h


func pispa_bag_capacity() -> int:
	var cap := int(pispa.get("bag_capacity", 20))
	var nb: Dictionary = pispa.get("nest_bonus", {})
	for lvl in nb:
		if get_nest_level() >= int(lvl):
			cap += int(nb[lvl].get("bag", 0))
	return cap


func pispa_bag_used() -> int:
	return (pispa.get("bag", []) as Array).size()


func pispa_bag_items() -> int:
	var n := 0
	for s in pispa.get("bag", []):
		n += int(s["qty"])
	return n


func is_pispa_bag_full() -> bool:
	return pispa_bag_used() >= pispa_bag_capacity()


func is_pispa_searching() -> bool:
	return not (pispa.get("trip", {}) as Dictionary).is_empty()


func _start_pispa_trip() -> bool:
	if bool(pispa.get("follow_in_world", false)) or str(pispa.get("on_expedition", "")) != "" or is_pispa_bag_full():
		pispa["trip"] = {}
		return false
	var tgt := str(pispa.get("target", "esquirlas"))
	var hours := _pispa_trip_hours(tgt)
	if bool(pispa.get("snack_active", false)):
		hours *= 0.5
		pispa["snack_active"] = false
	pispa["trip"] = {"target": tgt, "start_h": clock_h, "end_h": clock_h + hours}
	return true


## Mete botín en la bolsa: apila hasta `stack_max`; si no cabe, se queda fuera.
func add_to_pispa_bag(item: String, qty: int) -> int:
	var bag: Array = pispa["bag"]
	var stack_max := int(pispa.get("stack_max", 12))
	var left := qty
	for s in bag:
		if left <= 0:
			break
		if s["item"] == item and int(s["qty"]) < stack_max:
			var add := mini(left, stack_max - int(s["qty"]))
			s["qty"] = int(s["qty"]) + add
			left -= add
	while left > 0 and bag.size() < pispa_bag_capacity():
		var add2 := mini(left, stack_max)
		bag.append({"item": item, "qty": add2})
		left -= add2
	return qty - left


func _step_pispa(summary: Dictionary) -> void:
	var trip: Dictionary = pispa.get("trip", {})
	if trip.is_empty():
		_start_pispa_trip()
		return
	if clock_h < float(trip["end_h"]) - 0.0001:
		return
	var t := _pispa_target(str(trip["target"]))
	var loot := {}
	for it in t.get("loot", {}):
		var pair: Array = t["loot"][it]
		var q := rng.randi_range(int(pair[0]), int(pair[1]))
		for tr in pispa.get("traits", []):
			q = int(round(q * (1.0 + float(tr.get("bonus", {}).get(it, 0.0)))))
		loot[it] = q
	var rare: Dictionary = t.get("rare", {})
	if not rare.is_empty() and rng.randf() * 100.0 < float(rare.get("pct", 0)):
		loot[rare["item"]] = 1
	var kept := {}
	for it in loot:
		var k := add_to_pispa_bag(it, int(loot[it]))
		if k > 0:
			kept[it] = k
	for it in kept:
		(pispa["journal"] as Array).push_front({"text": "%s ×%d" % [item_name(it), int(kept[it])], "when": "hace un momento", "color": "#" + item_color(it).to_html(false)})
	if (pispa["journal"] as Array).size() > 12:
		(pispa["journal"] as Array).resize(12)
	pispa["xp"] = int(pispa["xp"]) + 40
	while int(pispa["xp"]) >= int(pispa["xp_next"]):
		pispa["xp"] = int(pispa["xp"]) - int(pispa["xp_next"])
		pispa["level"] = int(pispa["level"]) + 1
		pispa["xp_next"] = int(pispa["xp_next"]) + 150
	summary["pispa_trips"] = int(summary["pispa_trips"]) + 1
	pispa["trip"] = {}
	pispa_returned.emit(kept)
	# «Sale sola cada vez que vuelve», salvo que la bolsa esté llena.
	_start_pispa_trip()
	pispa_changed.emit()


## «Vaciar bolsa al almacén».
func empty_pispa_bag() -> Dictionary:
	var moved := {}
	for s in pispa.get("bag", []):
		moved[s["item"]] = int(moved.get(s["item"], 0)) + int(s["qty"])
	for it in moved:
		deposit(it, int(moved[it]), "pispa")
	(pispa["bag"] as Array).clear()
	if (pispa.get("trip", {}) as Dictionary).is_empty():
		_start_pispa_trip()
	pispa_changed.emit()
	return {"ok": not moved.is_empty(), "items": moved}


## «Darle un bocadillo»: el próximo viaje dura la mitad (gasta 1 pan).
func feed_pispa() -> Dictionary:
	if not withdraw("pan", 1):
		return {"ok": false, "reason": "no_bread"}
	pispa["snack_active"] = true
	var trip: Dictionary = pispa.get("trip", {})
	if not trip.is_empty():
		var left := float(trip["end_h"]) - clock_h
		trip["end_h"] = clock_h + left * 0.5
		pispa["snack_active"] = false
	pispa_changed.emit()
	return {"ok": true, "bread_left": get_item("pan")}


## «Acariciar»: +1 cariño (máx. 5), una vez cada 4 h.
func pet_pispa() -> Dictionary:
	if clock_h - float(pispa.get("last_pet_h", -999.0)) < 4.0:
		return {"ok": false, "reason": "cooldown", "affection": int(pispa["affection"])}
	pispa["last_pet_h"] = clock_h
	pispa["affection"] = mini(5, int(pispa["affection"]) + 1)
	pispa_changed.emit()
	return {"ok": true, "affection": int(pispa["affection"])}


func set_pispa_follow(on: bool) -> void:
	pispa["follow_in_world"] = on
	if on:
		pispa["trip"] = {}
	else:
		_start_pispa_trip()
	pispa_changed.emit()


static func affection_label(a: int) -> String:
	return ["arisca", "tímida", "tranquila", "contenta", "feliz", "muy feliz"][clampi(a, 0, 5)]


# ==========================================================================
# Mejoras y nivel del refugio
# ==========================================================================
func upgrades_done() -> int:
	var n := 0
	for row in upgrades:
		for t in row["tiers"]:
			if t.get("status", "") == "done":
				n += 1
	return n


func get_shelter_level() -> int:
	var done := upgrades_done()
	var lvl := 1
	for i in level_thresholds.size():
		if done >= int(level_thresholds[i]):
			lvl = i + 1
	return lvl


func next_level_threshold() -> int:
	var lvl := get_shelter_level()
	return int(level_thresholds[lvl]) if lvl < level_thresholds.size() else upgrades_done()


func _busy_works() -> int:
	var n := 0
	for row in upgrades:
		for t in row["tiers"]:
			if t.get("status", "") == "in_progress":
				n += 1
	for uid in rooms:
		if float(rooms[uid]["upgrade_left_h"]) > 0.0:
			n += 1
	return n


func get_works_in_progress() -> Array:
	var out: Array = []
	for row in upgrades:
		var tiers: Array = row["tiers"]
		for i in tiers.size():
			if tiers[i].get("status", "") == "in_progress":
				out.append({"label": "%s · nivel %d" % [row["name"], i + 1], "left_h": float(tiers[i]["left_h"]),
					"total_h": float(tiers[i].get("hours", 1.0)), "kind": "upgrade"})
	for uid in rooms:
		if float(rooms[uid]["upgrade_left_h"]) > 0.0:
			out.append({"label": "%s · nivel %d" % [room_name(uid), int(rooms[uid]["level"]) + 1], "left_h": float(rooms[uid]["upgrade_left_h"]),
				"total_h": room_upgrade_hours(uid), "kind": "room"})
	return out


## Estado de cada nivel: done · in_progress · recommended · available · next · locked.
func tier_status(row_idx: int, tier_idx: int) -> String:
	var row: Dictionary = upgrades[row_idx]
	var t: Dictionary = row["tiers"][tier_idx]
	var st := str(t.get("status", ""))
	if st == "done" or st == "in_progress":
		return st
	if get_shelter_level() < int(t.get("requires_level", 0)):
		return "locked"
	if tier_idx > 0 and str(row["tiers"][tier_idx - 1].get("status", "")) != "done":
		return "next"
	for rec in get_recommended_upgrades():
		if rec["row"] == row_idx and rec["tier"] == tier_idx:
			return "recommended"
	return "available"


## Orden sugerido según las metas reales del jugador (§2.5).
func get_recommended_upgrades() -> Array:
	var out: Array = []
	for g in goals:
		for ri in upgrades.size():
			var tiers: Array = upgrades[ri]["tiers"]
			for ti in tiers.size():
				var t: Dictionary = tiers[ti]
				if str(t.get("goal", "")) == g["id"] and str(t.get("status", "")) == "" and (ti == 0 or tiers[ti - 1].get("status", "") == "done"):
					out.append({"row": ri, "tier": ti, "name": "%s %d" % [upgrades[ri]["name"], ti + 1], "why": str(t.get("why", g["why"])), "goal": g["id"], "effect": t.get("effect", "")})
	return out


func start_upgrade(row_id: String, tier_idx: int) -> Dictionary:
	var ri := -1
	for i in upgrades.size():
		if upgrades[i]["id"] == row_id:
			ri = i
	if ri < 0 or tier_idx < 0 or tier_idx >= (upgrades[ri]["tiers"] as Array).size():
		return {"ok": false, "reason": "unknown_upgrade"}
	var st := tier_status(ri, tier_idx)
	if st in ["done", "in_progress"]:
		return {"ok": false, "reason": st}
	if st == "locked":
		return {"ok": false, "reason": "requires_level"}
	if st == "next":
		return {"ok": false, "reason": "previous_first"}
	if _busy_works() >= upgrade_slots:
		return {"ok": false, "reason": "no_slot"}
	var t: Dictionary = upgrades[ri]["tiers"][tier_idx]
	var cost: Dictionary = t.get("cost", {})
	if not can_afford(cost):
		return {"ok": false, "reason": "cost", "cost": cost}
	_pay(cost)
	t["status"] = "in_progress"
	t["left_h"] = float(t.get("hours", 1.0))
	shelter_changed.emit()
	return {"ok": true, "hours": t["left_h"]}


func _apply_upgrade_effect(row: Dictionary, tier_idx: int) -> void:
	_log_away("Mejora terminada: %s %d" % [row["name"], tier_idx + 1])
	# Subir de nivel el refugio desbloquea cimientos.
	var lvl := get_shelter_level()
	for fl in floors:
		for cell in fl["cells"]:
			if cell["state"] == CELL_LOCKED and lvl >= int(cell.get("requires_level", 99)):
				cell["state"] = CELL_ROCK


# ==========================================================================
# Refugio de bolsillo (Anexo D): ronda de 2 minutos
# ==========================================================================
## Lista guiada de lo pendiente. Vacía → «Todo al día».
func get_round_items() -> Array:
	var out: Array = []
	var col := get_collectables()
	if not col.is_empty():
		out.append({"id": "collect", "label": "Recoger todo · %d" % col.size(), "action": "collect_all"})
	for d in get_pending_decisions():
		out.append({"id": "decision:" + d["run_id"], "label": "%s: %s" % [d["event"]["title"], _char(d["who"][0]).get("name", "")],
			"action": "decision", "run_id": d["run_id"], "expires_in_h": d["expires_in_h"]})
	for p in surface.get("plots", []):
		if float(p.get("progress_hours", 0.0)) <= 0.0:
			out.append({"id": "replant:" + p["id"], "label": "Replantar %s" % p["name"], "action": "replant", "plot": p["id"]})
	if pispa_bag_used() >= int(pispa_bag_capacity() * 0.7):
		out.append({"id": "pispa_bag", "label": "Vaciar la bolsa de Pispa (%d / %d)" % [pispa_bag_used(), pispa_bag_capacity()], "action": "empty_bag"})
	for b in diagnose():
		if not b["resolving"]:
			out.append({"id": "jam:" + b["workshop"], "label": "Atasco en %s" % b["name"], "action": "fix", "workshop": b["workshop"],
				"solution": (b["solutions"][0] as Dictionary)["id"] if not (b["solutions"] as Array).is_empty() else ""})
	return out


func replant(plot_id: String) -> bool:
	for p in surface.get("plots", []):
		if p["id"] == plot_id:
			p["progress_hours"] = 0.01
			return true
	return false


func get_pocket_summary() -> Dictionary:
	var items_round := get_round_items()
	var trip: Dictionary = pispa.get("trip", {})
	return {
		"name": shelter_name, "level": get_shelter_level(), "comfort": get_comfort(),
		"ready": get_collectables().size(), "round": items_round, "all_done": items_round.is_empty(),
		"pispa": "Recolectando · %s" % format_hours(maxf(0.0, float(trip.get("end_h", clock_h)) - clock_h)) if not trip.is_empty() else ("Bolsa llena" if is_pispa_bag_full() else "En el nido"),
		"expeditions": active_expeditions.size(), "storage": "%d / %d" % [get_storage_used(), get_storage_capacity()],
		"gold": get_item("oro"),
	}
