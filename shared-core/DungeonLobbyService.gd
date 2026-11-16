extends Node
## Antesala de mazmorra / incursión — UI v2.4 Paso 14 (design_ref/pantallas_html/MMO-Antesala.html,
## PROMPT_ANTIGRAVITY.md §3 «Antesala de mazmorra», Anexo D «Refugio de bolsillo» [H]).
##
## Autoload `DungeonLobbyService` o instanciable con `.new()` + `load_seed()` (reloj manual: `tick`).
## Seed: res://config/dungeons/dungeon_lobby_seed.json
##
## - Mazmorra y dificultad («Bóveda de Ferrum · Heroica»).
## - 5 integrantes con rol (Tanque / Sanadora / Daño), iLvl, arquetipo, avatar chibi, estado de
##   preparación («Listo ✓» verde, «Cambiando conjunto…» ámbar, «Preparando…» gris) y checklist
##   (consumibles, reparación del equipo y conjunto activo / «→ Sanación» si está cambiando).
## - Entrada automática: la cuenta atrás (24 s) solo avanza cuando los 5 están listos; si alguien
##   deja de estarlo se detiene y vuelve al máximo. Al llegar a 0 entra sola.
## - Acciones locales: `toggle_ready()`, `set_equipment_set()` (F1-F3: cambia el conjunto, el rol y
##   el iLvl tras `set_swap_s`; cambiar de conjunto te quita el «listo») y `start_dungeon_entry()`.
##   El líder puede «Iniciar ahora» (`start_now`) cuando todos están listos.
## - Extras del diseño: afijos de la semana, votación de ruta, «Primera vez para N» con modo
##   aprendizaje y aviso de El Nido en mini-ventana [H].

signal lobby_changed
signal member_changed(member_id: String)
signal ready_changed(member_id: String, is_ready: bool)
signal all_ready_changed(all_ready: bool)
signal countdown_changed(remaining: float)
signal equipment_set_changing(member_id: String, set_name: String)
signal equipment_set_changed(member_id: String, set_name: String)
signal entry_started(dungeon_id: String, info: Dictionary)
signal route_voted(member_id: String, route_id: String)
signal learning_mode_changed(enabled: bool)
signal group_left(member_id: String)

const DEFAULT_SEED_PATH := "res://config/dungeons/dungeon_lobby_seed.json"

const STATUS_READY := "ready"
const STATUS_CHANGING := "changing"
const STATUS_PREPARING := "preparing"

const STATE_WAITING := "waiting"
const STATE_ENTERING := "entering"
const STATE_LEFT := "left"

const DEFAULT_AUTO_ENTRY_S := 24.0
const DEFAULT_SET_SWAP_S := 2.0
const MAX_MEMBERS := 5

const READY_COLOR := "#4fe39a"
const READY_BG := "#4fe39a26"          # rgba(79,227,154,0.15)
const CHANGING_COLOR := "#f5c35b"
const CHANGING_BG := "#f5c35b26"       # rgba(245,195,91,0.15)
const PREPARING_COLOR := "#9aa6ae"
const PREPARING_BG := "#18242b"
const OK_COLOR := "#4fe39a"
const WARN_COLOR := "#f5c35b"
const BAD_COLOR := "#ff8a8a"
const NEUTRAL_COLOR := "#c3ccd3"
const DURABILITY_OK := 75
const DURABILITY_WARN := 50

const STATUS_LABELS := {
	STATUS_READY: "Listo ✓",
	STATUS_CHANGING: "Cambiando conjunto…",
	STATUS_PREPARING: "Preparando…",
}

var dungeon_id: String = "ferrum_vault"
var dungeon_name: String = "Bóveda de Ferrum"
var difficulty: String = "Heroica"
var dungeons: Dictionary = {}
var auto_entry_s: float = DEFAULT_AUTO_ENTRY_S
var set_swap_s: float = DEFAULT_SET_SWAP_S
var local_player: String = "kael"
var leader: String = "kael"
var roles: Dictionary = {}
var equipment_sets: Dictionary = {}     # set_id -> {id, name, role, key, ilvl}
var members: Array[Dictionary] = []
var affixes: Array[Dictionary] = []
var routes: Array[Dictionary] = []
var learning_mode: bool = true
var nest: Dictionary = {}
var seed_data: Dictionary = {}

var state: String = STATE_WAITING
var countdown: float = DEFAULT_AUTO_ENTRY_S
var auto_tick: bool = true
var last_entry: Dictionary = {}
var _was_all_ready := false


func _ready() -> void:
	if seed_data.is_empty() and FileAccess.file_exists(DEFAULT_SEED_PATH):
		load_seed(DEFAULT_SEED_PATH)


func _process(delta: float) -> void:
	if auto_tick and state == STATE_WAITING and not members.is_empty():
		tick(delta)


# ==========================================================================
# Carga
# ==========================================================================
func load_seed(path: String = DEFAULT_SEED_PATH) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY:
		return false
	load_from_dict(data)
	return true


func load_from_dict(data: Dictionary) -> void:
	seed_data = data.duplicate(true)
	_apply(data)


func _apply(data: Dictionary) -> void:
	dungeons = (data.get("dungeons", {}) as Dictionary).duplicate(true)
	var d: Dictionary = data.get("dungeon", {})
	dungeon_id = str(d.get("id", "ferrum_vault"))
	dungeon_name = str(d.get("name", dungeons.get(dungeon_id, {}).get("name", dungeon_id)))
	difficulty = str(d.get("difficulty", dungeons.get(dungeon_id, {}).get("difficulty", "")))
	auto_entry_s = maxf(1.0, float(data.get("auto_entry_s", DEFAULT_AUTO_ENTRY_S)))
	set_swap_s = maxf(0.0, float(data.get("set_swap_s", DEFAULT_SET_SWAP_S)))
	local_player = str(data.get("local_player", "kael"))
	leader = str(data.get("leader", local_player))
	roles = (data.get("roles", {
		"tank": {"name": "Tanque", "color": "#5aa9ff"},
		"healer": {"name": "Sanadora", "color": "#4fe39a"},
		"dps": {"name": "Daño", "color": "#ff9a4d"},
	}) as Dictionary).duplicate(true)
	equipment_sets.clear()
	for sid in (data.get("equipment_sets", {}) as Dictionary):
		var s: Dictionary = data["equipment_sets"][sid]
		equipment_sets[str(sid)] = {
			"id": str(sid), "name": str(s.get("name", sid)), "role": str(s.get("role", "dps")),
			"key": str(s.get("key", "")), "ilvl": int(s.get("ilvl", 0)),
		}
	members.clear()
	for m in data.get("members", []):
		if members.size() >= MAX_MEMBERS:
			break
		members.append(_member_from(m))
	affixes.clear()
	for a in data.get("affixes", []):
		affixes.append({"name": str(a.get("name", "")), "color": str(a.get("color", "#b8c3ca")), "text": str(a.get("text", ""))})
	routes.clear()
	for r in data.get("routes", []):
		var votes: Array[String] = []
		for v in r.get("votes", []):
			votes.append(str(v))
		routes.append({"id": str(r.get("id", "")), "name": str(r.get("name", "")), "color": str(r.get("color", "#46e3c1")), "votes": votes})
	learning_mode = bool(data.get("learning_mode", true))
	nest = (data.get("nest", {}) as Dictionary).duplicate(true)
	state = STATE_WAITING
	countdown = auto_entry_s
	last_entry = {}
	_was_all_ready = all_ready()


func _member_from(m: Dictionary) -> Dictionary:
	var c: Dictionary = m.get("consumables", {"ok": true, "text": "✓"})
	var av: Dictionary = m.get("avatar", {})
	var status := str(m.get("status", STATUS_PREPARING))
	if not STATUS_LABELS.has(status):
		status = STATUS_PREPARING
	var mem := {
		"id": str(m.get("id", "")),
		"name": str(m.get("name", "")),
		"archetype": str(m.get("archetype", "")),
		"role": str(m.get("role", "dps")),
		"role_name": str(m.get("role_name", "")),
		"ilvl": int(m.get("ilvl", 0)),
		"status": status,
		"consumables_ok": bool(c.get("ok", true)),
		"consumables_text": str(c.get("text", "✓" if bool(c.get("ok", true)) else "faltan")),
		"durability": clampi(int(m.get("durability", 100)), 0, 100),
		"set": str(m.get("set", "")),
		"set_id": str(m.get("set_id", "")),
		"pending_set": str(m.get("pending_set", "")),
		"pending_set_id": str(m.get("pending_set_id", "")),
		"swap_remaining": maxf(0.0, float(m.get("swap_remaining", 0.0))),
		"avatar_body": str(av.get("body", "#2b4a8a")),
		"avatar_hair": str(av.get("hair", "#5a3a20")),
		"first_time": bool(m.get("first_time", false)),
	}
	if mem["set_id"] == "":
		mem["set_id"] = _set_id_by_name(mem["set"])
	if status == STATUS_CHANGING and mem["pending_set"] == "":
		mem["status"] = STATUS_PREPARING
	if status == STATUS_CHANGING and mem["swap_remaining"] <= 0.0:
		mem["swap_remaining"] = set_swap_s
	return mem


func reset() -> void:
	if not seed_data.is_empty():
		_apply(seed_data)


## Abre la antesala de otra mazmorra (id del seed, dificultad opcional). Conserva el grupo y
## devuelve a todos a la espera.
func open_lobby(id: String = "ferrum_vault", diff: String = "") -> Dictionary:
	reset()
	if id != "" and id != dungeon_id:
		dungeon_id = id
		var d: Dictionary = dungeons.get(id, {})
		dungeon_name = str(d.get("name", id.capitalize()))
		difficulty = str(d.get("difficulty", difficulty))
	if diff != "":
		difficulty = diff
	lobby_changed.emit()
	return snapshot()


# ==========================================================================
# Consultas
# ==========================================================================
func title_text() -> String:
	return dungeon_name if difficulty == "" else "%s · %s" % [dungeon_name, difficulty]


func get_member(id: String) -> Dictionary:
	for m in members:
		if m["id"] == id:
			return m
	return {}


func member_index(id: String) -> int:
	for i in members.size():
		if members[i]["id"] == id:
			return i
	return -1


func local_member() -> Dictionary:
	return get_member(local_player)


func is_local(id: String) -> bool:
	return id == local_player


func is_leader(id: String = "") -> bool:
	return (local_player if id == "" else id) == leader


func display_name(m: Dictionary) -> String:
	return "%s (tú)" % m["name"] if is_local(str(m["id"])) else str(m["name"])


func role_name(m: Dictionary) -> String:
	if str(m.get("role_name", "")) != "":
		return str(m["role_name"])
	return str(roles.get(m["role"], {}).get("name", str(m["role"]).capitalize()))


func role_color(role: String) -> String:
	return str(roles.get(role, {}).get("color", NEUTRAL_COLOR))


## «Tanque · 418»
func role_line(m: Dictionary) -> String:
	return "%s · %d" % [role_name(m), int(m["ilvl"])]


func is_ready(id: String) -> bool:
	return str(get_member(id).get("status", "")) == STATUS_READY


func ready_count() -> int:
	var n := 0
	for m in members:
		if m["status"] == STATUS_READY:
			n += 1
	return n


func all_ready() -> bool:
	return members.size() == MAX_MEMBERS and ready_count() == members.size()


func status_label(m: Dictionary) -> String:
	return str(STATUS_LABELS.get(m["status"], STATUS_LABELS[STATUS_PREPARING]))


## {text, color, bg} del badge de estado.
func status_style(m: Dictionary) -> Dictionary:
	match str(m["status"]):
		STATUS_READY:
			return {"text": status_label(m), "color": READY_COLOR, "bg": READY_BG}
		STATUS_CHANGING:
			return {"text": status_label(m), "color": CHANGING_COLOR, "bg": CHANGING_BG}
	return {"text": status_label(m), "color": PREPARING_COLOR, "bg": PREPARING_BG}


static func durability_color(pct: int) -> String:
	if pct >= DURABILITY_OK:
		return OK_COLOR
	if pct >= DURABILITY_WARN:
		return WARN_COLOR
	return BAD_COLOR


## Checklist de la tarjeta: [{id, label, value, color}] (Consumibles, Reparación, Conjunto).
func checklist(m: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.append({"id": "consumables", "label": "Consumibles", "value": str(m["consumables_text"]),
		"color": OK_COLOR if m["consumables_ok"] else WARN_COLOR})
	out.append({"id": "durability", "label": "Reparación", "value": "%d %%" % int(m["durability"]),
		"color": durability_color(int(m["durability"]))})
	if m["status"] == STATUS_CHANGING and str(m["pending_set"]) != "":
		out.append({"id": "set", "label": "Conjunto", "value": "→ %s" % m["pending_set"], "color": CHANGING_COLOR})
	else:
		out.append({"id": "set", "label": "Conjunto", "value": str(m["set"]), "color": NEUTRAL_COLOR})
	return out


## Avisos de preparación (no bloquean el «listo»): sin consumibles o equipo muy dañado.
func readiness_warnings(m: Dictionary) -> Array[String]:
	var w: Array[String] = []
	if not m["consumables_ok"]:
		w.append("Consumibles: %s" % m["consumables_text"])
	if int(m["durability"]) < DURABILITY_WARN:
		w.append("Reparación al %d %%" % int(m["durability"]))
	return w


func first_timers() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for m in members:
		if m["first_time"]:
			out.append(m)
	return out


## «Nox y Vela no conocen esta mazmorra. …»
func first_time_text() -> String:
	var names: Array = first_timers().map(func(m): return str(m["name"]))
	if names.is_empty():
		return "Todo el grupo conoce esta mazmorra."
	var who := ""
	if names.size() == 1:
		who = names[0]
	else:
		who = ", ".join(names.slice(0, names.size() - 1)) + " y " + names[-1]
	var verb := "no conoce" if names.size() == 1 else "no conocen"
	var tail := "él" if names.size() == 1 else "ellos"
	return "%s %s esta mazmorra. Activa avisos de mecánicas solo para %s." % [who, verb, tail]


static func clock_text(seconds: float) -> String:
	var s := maxi(0, ceili(seconds - 0.0001))
	return "%d:%02d" % [s / 60, s % 60]


func countdown_text() -> String:
	return clock_text(countdown)


## «Entrada automática en 0:24 cuando los 5 estén listos» (o «… en 0:17» si ya corre).
func countdown_caption() -> String:
	if state == STATE_ENTERING:
		return "Entrando en la mazmorra…"
	if all_ready():
		return "Todos listos · entrada automática en %s" % countdown_text()
	return "Entrada automática en %s cuando los %d estén listos" % [countdown_text(), MAX_MEMBERS]


func is_countdown_running() -> bool:
	return state == STATE_WAITING and all_ready()


## Conjuntos del jugador local ordenados por tecla (F1, F2, F3).
func set_options() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for sid in equipment_sets:
		out.append(equipment_sets[sid])
	out.sort_custom(func(a, b): return str(a["key"]) < str(b["key"]))
	return out


func _set_id_by_name(set_name: String) -> String:
	for sid in equipment_sets:
		if str(equipment_sets[sid]["name"]).to_lower() == set_name.to_lower():
			return sid
	return ""


## Acepta id («sanacion»), nombre («Sanación») o tecla («F3»).
func resolve_set(set_name: String) -> String:
	if equipment_sets.has(set_name):
		return set_name
	for sid in equipment_sets:
		var s: Dictionary = equipment_sets[sid]
		if str(s["key"]).to_lower() == set_name.to_lower() or str(s["name"]).to_lower() == set_name.to_lower():
			return sid
	return ""


func active_set_id() -> String:
	var m := local_member()
	if m.is_empty():
		return ""
	if m["status"] == STATUS_CHANGING and str(m["pending_set_id"]) != "":
		return str(m["pending_set_id"])
	return str(m["set_id"])


func route_votes(route_id: String) -> int:
	for r in routes:
		if r["id"] == route_id:
			return (r["votes"] as Array).size()
	return 0


func total_votes() -> int:
	var n := 0
	for r in routes:
		n += (r["votes"] as Array).size()
	return n


func route_ratio(route_id: String) -> float:
	var t := total_votes()
	return 0.0 if t == 0 else float(route_votes(route_id)) / float(t)


func leading_route() -> String:
	var best := ""
	var best_n := -1
	for r in routes:
		var n := (r["votes"] as Array).size()
		if n > best_n:
			best_n = n
			best = str(r["id"])
	return best


func voted_route(member_id: String = "") -> String:
	var id := local_player if member_id == "" else member_id
	for r in routes:
		if (r["votes"] as Array).has(id):
			return str(r["id"])
	return ""


func snapshot() -> Dictionary:
	return {
		"dungeon_id": dungeon_id, "title": title_text(), "state": state,
		"countdown": countdown, "countdown_text": countdown_text(),
		"ready": ready_count(), "all_ready": all_ready(),
		"members": members.duplicate(true), "route": leading_route(), "learning_mode": learning_mode,
	}


# ==========================================================================
# Acciones
# ==========================================================================
## Cambia el «listo» del jugador local. Durante un cambio de conjunto no se puede marcar.
func toggle_ready() -> bool:
	var m := local_member()
	if m.is_empty():
		return false
	return set_member_ready(local_player, m["status"] != STATUS_READY)


## Estado de cualquier integrante (sincronización de red / IA del grupo).
func set_member_ready(member_id: String, on: bool) -> bool:
	if state != STATE_WAITING:
		return is_ready(member_id)
	var i := member_index(member_id)
	if i < 0:
		return false
	var m := members[i]
	if m["status"] == STATUS_CHANGING:
		return false
	var next := STATUS_READY if on else STATUS_PREPARING
	if m["status"] != next:
		m["status"] = next
		ready_changed.emit(member_id, on)
		member_changed.emit(member_id)
		_check_all_ready()
	return on


## Marca listos a todos los que puedan (los que cambian de conjunto lo terminan primero).
func ready_everyone() -> void:
	for m in members:
		if m["status"] == STATUS_CHANGING:
			_finish_swap(m)
		set_member_ready(str(m["id"]), true)


## Cambia el conjunto del jugador local (id, nombre o F1-F3). El cambio tarda `set_swap_s`:
## mientras tanto se ve «Cambiando conjunto…» y «→ Sanación». Al terminar se actualizan el
## rol y el iLvl, y hay que volver a marcarse listo.
func set_equipment_set(set_name: String, member_id: String = "") -> bool:
	var id := local_player if member_id == "" else member_id
	var sid := resolve_set(set_name)
	var i := member_index(id)
	if sid == "" or i < 0 or state != STATE_WAITING:
		return false
	var m := members[i]
	var target: Dictionary = equipment_sets[sid]
	if m["status"] != STATUS_CHANGING and str(m["set_id"]) == sid:
		return false
	if m["status"] == STATUS_CHANGING and str(m["pending_set_id"]) == sid:
		return false
	var was_ready: bool = m["status"] == STATUS_READY
	if str(m["set_id"]) == sid:
		# Vuelve al conjunto que ya llevaba: cancela el cambio.
		m["status"] = STATUS_PREPARING
		m["pending_set"] = ""
		m["pending_set_id"] = ""
		m["swap_remaining"] = 0.0
		member_changed.emit(id)
		equipment_set_changed.emit(id, str(m["set"]))
		_check_all_ready()
		return true
	m["status"] = STATUS_CHANGING
	m["pending_set"] = str(target["name"])
	m["pending_set_id"] = sid
	m["swap_remaining"] = set_swap_s
	if was_ready:
		ready_changed.emit(id, false)
	equipment_set_changing.emit(id, str(target["name"]))
	member_changed.emit(id)
	_check_all_ready()
	if set_swap_s <= 0.0:
		_finish_swap(m)
	return true


func set_equipment_set_by_key(index: int) -> bool:
	var opts := set_options()
	if index < 0 or index >= opts.size():
		return false
	return set_equipment_set(str(opts[index]["id"]))


func _finish_swap(m: Dictionary) -> void:
	var sid := str(m["pending_set_id"])
	if sid == "":
		sid = _set_id_by_name(str(m["pending_set"]))
	if sid != "" and equipment_sets.has(sid):
		var s: Dictionary = equipment_sets[sid]
		m["set_id"] = sid
		m["set"] = str(s["name"])
		m["role"] = str(s["role"])
		m["role_name"] = ""
		# `equipment_sets` son los conjuntos del jugador local: su iLvl solo se aplica a él.
		# Los compañeros conservan el suyo (llegará por red).
		if is_local(str(m["id"])) and int(s["ilvl"]) > 0:
			m["ilvl"] = int(s["ilvl"])
	elif str(m["pending_set"]) != "":
		m["set"] = str(m["pending_set"])
	m["pending_set"] = ""
	m["pending_set_id"] = ""
	m["swap_remaining"] = 0.0
	m["status"] = STATUS_PREPARING
	equipment_set_changed.emit(str(m["id"]), str(m["set"]))
	member_changed.emit(str(m["id"]))


func set_member_consumables(member_id: String, ok: bool, text: String = "") -> void:
	var m := get_member(member_id)
	if m.is_empty():
		return
	m["consumables_ok"] = ok
	m["consumables_text"] = text if text != "" else ("✓" if ok else "faltan")
	member_changed.emit(member_id)


func set_member_durability(member_id: String, pct: int) -> void:
	var m := get_member(member_id)
	if m.is_empty():
		return
	m["durability"] = clampi(pct, 0, 100)
	member_changed.emit(member_id)


func vote_route(route_id: String, member_id: String = "") -> bool:
	var id := local_player if member_id == "" else member_id
	var target := {}
	for r in routes:
		if r["id"] == route_id:
			target = r
	if target.is_empty() or member_index(id) < 0:
		return false
	if (target["votes"] as Array).has(id):
		return false
	for r in routes:
		(r["votes"] as Array).erase(id)
	(target["votes"] as Array).append(id)
	route_voted.emit(id, route_id)
	lobby_changed.emit()
	return true


func set_learning_mode(on: bool) -> void:
	if learning_mode == on:
		return
	learning_mode = on
	learning_mode_changed.emit(on)


## «Iniciar ahora» del líder: entra sin esperar la cuenta atrás si todos están listos.
func start_now() -> Dictionary:
	if not is_leader():
		return {"ok": false, "reason": "not_leader"}
	return start_dungeon_entry("leader")


## Dispara la transición a la mazmorra. Exige que los 5 estén listos (salvo `force`).
func start_dungeon_entry(reason: String = "manual", force: bool = false) -> Dictionary:
	if state == STATE_ENTERING:
		return {"ok": false, "reason": "already_entering"}
	if state == STATE_LEFT:
		return {"ok": false, "reason": "left_group"}
	if not force and not all_ready():
		return {"ok": false, "reason": "not_all_ready", "ready": ready_count()}
	state = STATE_ENTERING
	last_entry = {
		"ok": true, "reason": reason, "dungeon_id": dungeon_id, "title": title_text(),
		"route": leading_route(), "learning_mode": learning_mode,
		"learners": first_timers().map(func(m): return str(m["id"])) if learning_mode else [],
		"members": members.map(func(m): return {"id": m["id"], "role": m["role"], "ilvl": m["ilvl"], "set": m["set"]}),
	}
	entry_started.emit(dungeon_id, last_entry)
	lobby_changed.emit()
	return last_entry


func leave_group() -> bool:
	if state != STATE_WAITING:
		return false
	state = STATE_LEFT
	group_left.emit(local_player)
	lobby_changed.emit()
	return true


# ==========================================================================
# Reloj
# ==========================================================================
func tick(delta: float) -> void:
	if state != STATE_WAITING or delta <= 0.0:
		return
	for m in members:
		if m["status"] == STATUS_CHANGING:
			m["swap_remaining"] = maxf(0.0, float(m["swap_remaining"]) - delta)
			if float(m["swap_remaining"]) <= 0.0:
				_finish_swap(m)
				_check_all_ready()
	if all_ready():
		var before := countdown
		countdown = maxf(0.0, countdown - delta)
		if ceili(before) != ceili(countdown):
			countdown_changed.emit(countdown)
		if countdown <= 0.0:
			start_dungeon_entry("auto")


func _check_all_ready() -> void:
	var now := all_ready()
	if now != _was_all_ready:
		_was_all_ready = now
		if not now:
			countdown = auto_entry_s
			countdown_changed.emit(countdown)
		all_ready_changed.emit(now)
