extends Node
## SocialService — amigos, grupo, gremio y vecindad de El Nido (UI v2.4 Paso 9).
## Referencias: design_ref/pantallas_html/MMO-Social.html, MMO-Vecindad.html y
## PROMPT_ANTIGRAVITY Anexo E (patio común = punto de aparición, vecinos en casa,
## proyectos vecinales y mudanza gratis semanal para vivir con amigos).
##
## - Amigos: estado online/ausente/offline, nivel y zona. «Invitar al grupo» alimenta
##   `party_frames` (máx. `max_party` contando al jugador). «Prestar habitante» manda un
##   personaje SECUNDARIO de tu Refugio (`ShelterService`) al de un amigo durante unas horas.
## - Gremio: ficha, rango, miembros conectados y cofre comunal con donaciones de oro.
## - Vecindad: edificio con depas (luz encendida = en casa), patio, proyectos y mudanza.
##
## Reloj en días (`day`) inyectable para tests. Instanciable con `.new()` y autoload
## `SocialService`.

const DEFAULT_SEED_PATH := "res://config/social/social_seed.json"
const STATUS_ORDER := {"online": 0, "away": 1, "offline": 2}

signal social_changed
signal party_changed(members: Array)
signal party_invite_sent(friend_id: String)
signal inhabitant_lent(char_id: String, friend_id: String, hours: float)
signal inhabitant_returned(char_id: String)
signal guild_donation(amount: int, chest_gold: int)
signal project_contributed(project_id: String, amount: int, progress: int)
signal moved(neighborhood_id: String, free: bool)

var player: Dictionary = {}
var friends: Array[Dictionary] = []
var party: Array[String] = []
var max_party: int = 4
var loan_hours: float = 8.0
var loans: Array[Dictionary] = []
var guild: Dictionary = {}
var neighborhood: Dictionary = {}
## Día actual (reloj de juego). La mudanza gratis se renueva cada `move_cooldown_days`.
var day: int = 0
## Servicio del Refugio inyectable (tests). Si es null se usa /root/ShelterService.
var shelter: Node = null

var _party_frames: Array = []


func _init() -> void:
	reset()


func _ready() -> void:
	if friends.is_empty() and FileAccess.file_exists(DEFAULT_SEED_PATH):
		load_seed(DEFAULT_SEED_PATH)


func reset() -> void:
	player = {}
	friends.clear()
	party.clear()
	loans.clear()
	guild = {}
	neighborhood = {}
	day = 0


func load_seed(path: String = DEFAULT_SEED_PATH) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var data = JSON.parse_string(f.get_as_text())
	if not (data is Dictionary):
		push_warning("[SocialService] Seed inválido: %s" % path)
		return false
	load_from_dict(data)
	return true


func load_from_dict(data: Dictionary) -> void:
	reset()
	player = (data.get("player", {}) as Dictionary).duplicate(true)
	max_party = int(data.get("max_party", 4))
	loan_hours = float(data.get("loan_hours", 8.0))
	for fr in data.get("friends", []):
		friends.append((fr as Dictionary).duplicate(true))
	for id in data.get("party", []):
		if not get_friend(str(id)).is_empty():
			party.append(str(id))
	guild = (data.get("guild", {}) as Dictionary).duplicate(true)
	neighborhood = (data.get("neighborhood", {}) as Dictionary).duplicate(true)
	social_changed.emit()


func _shelter() -> Node:
	if shelter == null and is_inside_tree():
		shelter = get_node_or_null("/root/ShelterService")
	return shelter


# ==========================================================================
# Amigos
# ==========================================================================
func get_friend(id: String) -> Dictionary:
	for fr in friends:
		if fr["id"] == id:
			return fr
	return {}


## Conectados primero (online → ausente → desconectado), luego por nivel desc.
func list_friends(status_filter: String = "") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for fr in friends:
		if status_filter == "online" and fr["status"] == "offline":
			continue
		if status_filter == "offline" and fr["status"] != "offline":
			continue
		var v := fr.duplicate(true)
		v["in_party"] = party.has(str(fr["id"]))
		v["online"] = fr["status"] != "offline"
		out.append(v)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var sa := int(STATUS_ORDER.get(a["status"], 3))
		var sb := int(STATUS_ORDER.get(b["status"], 3))
		if sa != sb:
			return sa < sb
		if int(a["level"]) != int(b["level"]):
			return int(a["level"]) > int(b["level"])
		return str(a["name"]) < str(b["name"]))
	return out


func count_online() -> int:
	var n := 0
	for fr in friends:
		if fr["status"] != "offline":
			n += 1
	return n


static func status_label(status: String) -> String:
	match status:
		"online":
			return "En línea"
		"away":
			return "Ausente"
	return "Desconectado"


# ==========================================================================
# Grupo (party_frames)
# ==========================================================================
func can_invite(friend_id: String) -> Dictionary:
	var fr := get_friend(friend_id)
	if fr.is_empty():
		return {"ok": false, "reason": "unknown_friend"}
	if party.has(friend_id):
		return {"ok": false, "reason": "already_in_party"}
	if fr["status"] == "offline":
		return {"ok": false, "reason": "offline"}
	if party.size() + 1 >= max_party:
		return {"ok": false, "reason": "party_full"}
	return {"ok": true}


func invite_to_party(friend_id: String) -> Dictionary:
	var chk := can_invite(friend_id)
	if not chk["ok"]:
		return chk
	party.append(friend_id)
	var fr := get_friend(friend_id)
	fr["activity"] = "En tu grupo"
	party_invite_sent.emit(friend_id)
	_party_updated()
	return {"ok": true, "party_size": party.size() + 1}


func remove_from_party(friend_id: String) -> bool:
	if not party.has(friend_id):
		return false
	party.erase(friend_id)
	_party_updated()
	return true


## Datos para `PartyFrames.set_party_members()` (ids enteros estables).
func get_party_members_data() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in party:
		var fr := get_friend(id)
		if fr.is_empty():
			continue
		out.append({"id": 1000 + friends.find(fr), "name": str(fr["name"]), "class": str(fr.get("class", "warrior")),
			"level": int(fr["level"]), "hp": 100.0, "max_hp": 100.0, "friend_id": id})
	return out


## Enlaza un `PartyFrames` (o cualquier nodo con `set_party_members`). Se actualiza solo.
func bind_party_frames(pf: Object) -> void:
	if pf == null or not pf.has_method("set_party_members"):
		return
	if not _party_frames.has(pf):
		_party_frames.append(pf)
	pf.set_party_members(get_party_members_data())


func _party_updated() -> void:
	var data := get_party_members_data()
	for pf in _party_frames.duplicate():
		if is_instance_valid(pf):
			pf.set_party_members(data)
		else:
			_party_frames.erase(pf)
	party_changed.emit(party.duplicate())
	social_changed.emit()


# ==========================================================================
# Prestar habitante (Refugio ↔ amigo)
# ==========================================================================
## Habitantes que se pueden prestar: secundarios propios que no estén de expedición,
## prestados por otro ni ya prestados.
func get_lendable_inhabitants() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var s := _shelter()
	if s == null:
		return out
	for ch in s.get_characters():
		if bool(ch.get("is_player", false)) or str(ch.get("loaned_by", "")) != "":
			continue
		if str(ch.get("status", "")) in ["expedition", "returned", "lent_out"]:
			continue
		out.append(ch)
	return out


func lend_inhabitant(friend_id: String, char_id: String, hours: float = -1.0) -> Dictionary:
	var fr := get_friend(friend_id)
	if fr.is_empty():
		return {"ok": false, "reason": "unknown_friend"}
	var s := _shelter()
	if s == null:
		return {"ok": false, "reason": "no_shelter"}
	var ch: Dictionary = s.get_character(char_id)
	if ch.is_empty():
		return {"ok": false, "reason": "unknown_inhabitant"}
	if bool(ch.get("is_player", false)):
		return {"ok": false, "reason": "main_character"}
	if str(ch.get("loaned_by", "")) != "":
		return {"ok": false, "reason": "borrowed_from_other"}
	if str(ch.get("status", "")) == "lent_out":
		return {"ok": false, "reason": "already_lent"}
	if str(ch.get("status", "")) in ["expedition", "returned"]:
		return {"ok": false, "reason": "busy"}
	var h := loan_hours if hours <= 0.0 else hours
	s.unassign_worker(char_id)
	ch["status"] = "lent_out"
	ch["lent_to"] = str(fr["name"])
	loans.append({"char_id": char_id, "char_name": str(ch.get("name", char_id)), "friend_id": friend_id,
		"friend_name": str(fr["name"]), "hours_left": h})
	inhabitant_lent.emit(char_id, friend_id, h)
	if s.has_signal("shelter_changed"):
		s.shelter_changed.emit()
	social_changed.emit()
	return {"ok": true, "hours": h, "friend": str(fr["name"])}


## Avanza los préstamos; al terminar el habitante vuelve a casa (idle).
func tick_loans(hours: float) -> Array[String]:
	var back: Array[String] = []
	var s := _shelter()
	for l in loans.duplicate():
		l["hours_left"] = maxf(0.0, float(l["hours_left"]) - hours)
		if float(l["hours_left"]) <= 0.0:
			loans.erase(l)
			back.append(str(l["char_id"]))
			if s:
				var ch: Dictionary = s.get_character(str(l["char_id"]))
				if not ch.is_empty():
					ch["status"] = "idle"
					ch.erase("lent_to")
			inhabitant_returned.emit(str(l["char_id"]))
	if not back.is_empty():
		social_changed.emit()
	return back


# ==========================================================================
# Gremio
# ==========================================================================
func guild_members_online() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for m in guild.get("members", []):
		if bool(m.get("online", false)):
			out.append(m)
	return out


## Dona oro al cofre comunal. `gold_available` < 0 = no comprobar (lo cobra la economía).
func donate_to_guild(amount: int, gold_available: int = -1) -> Dictionary:
	if guild.is_empty():
		return {"ok": false, "reason": "no_guild"}
	if amount <= 0:
		return {"ok": false, "reason": "invalid_amount"}
	if gold_available >= 0 and amount > gold_available:
		return {"ok": false, "reason": "not_enough_gold"}
	guild["chest_gold"] = int(guild.get("chest_gold", 0)) + amount
	var entries: Array = guild.get("donations", [])
	entries.push_front({"name": str(player.get("name", "Tú")) + " (tú)", "amount": amount})
	guild["donations"] = entries
	guild["my_donated"] = int(guild.get("my_donated", 0)) + amount
	guild_donation.emit(amount, int(guild["chest_gold"]))
	social_changed.emit()
	return {"ok": true, "chest_gold": int(guild["chest_gold"])}


# ==========================================================================
# Vecindad
# ==========================================================================
## Depas del edificio como rejilla [piso][unidad]; el del jugador marcado `is_player`.
func get_building() -> Array:
	var floors := int(neighborhood.get("floors", 0))
	var units := int(neighborhood.get("units_per_floor", 0))
	var grid: Array = []
	for f in floors:
		var row: Array = []
		for u in units:
			row.append({"floor": f, "unit": u, "owner": "", "home": false, "rent": false, "friend": false, "guild": false, "is_player": false})
		grid.append(row)
	for a in neighborhood.get("apartments", []):
		var f2 := int(a["floor"])
		var u2 := int(a["unit"])
		if f2 < floors and u2 < units:
			var cell: Dictionary = grid[f2][u2]
			for k in a:
				cell[k] = a[k]
	var pu: Array = neighborhood.get("player_unit", [])
	if pu.size() == 2 and int(pu[0]) < floors and int(pu[1]) < units:
		var me: Dictionary = grid[int(pu[0])][int(pu[1])]
		me["owner"] = "Tú · " + str(player.get("name", ""))
		me["home"] = true
		me["is_player"] = true
		me["rent"] = false
		me["comfort"] = int(neighborhood.get("player_comfort", 0))
	return grid


## Vecinos con la luz encendida (en casa), sin contar al jugador.
func neighbors_at_home() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row in get_building():
		for cell in row:
			if bool(cell["home"]) and not bool(cell["is_player"]) and str(cell["owner"]) != "":
				out.append(cell)
	return out


func list_projects() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p in neighborhood.get("projects", []):
		var v: Dictionary = (p as Dictionary).duplicate(true)
		v["ratio"] = clampf(float(p["progress"]) / maxf(1.0, float(p["goal"])), 0.0, 1.0)
		v["done"] = int(p["progress"]) >= int(p["goal"])
		out.append(v)
	return out


func contribute_project(project_id: String, amount: int) -> Dictionary:
	if amount <= 0:
		return {"ok": false, "reason": "invalid_amount"}
	for p in neighborhood.get("projects", []):
		if p["id"] == project_id:
			if int(p["progress"]) >= int(p["goal"]):
				return {"ok": false, "reason": "already_done"}
			p["progress"] = mini(int(p["goal"]), int(p["progress"]) + amount)
			var done: bool = int(p["progress"]) >= int(p["goal"])
			project_contributed.emit(project_id, amount, int(p["progress"]))
			social_changed.emit()
			return {"ok": true, "progress": int(p["progress"]), "done": done}
	return {"ok": false, "reason": "unknown_project"}


func days_until_free_move() -> int:
	var cd := int(neighborhood.get("move_cooldown_days", 7))
	var last := int(neighborhood.get("last_move_day", -1000))
	return maxi(0, last + cd - day)


func can_move_free() -> bool:
	return days_until_free_move() == 0


## Mudanza: gratis una vez por semana; el depa viaja contigo tal cual.
func move_to(neighborhood_id: String) -> Dictionary:
	var target := {}
	for n in neighborhood.get("other_neighborhoods", []):
		if n["id"] == neighborhood_id:
			target = n
	if target.is_empty():
		return {"ok": false, "reason": "unknown_neighborhood"}
	if int(target.get("free_units", 0)) <= 0:
		return {"ok": false, "reason": "no_free_units"}
	if not can_move_free():
		return {"ok": false, "reason": "weekly_limit", "days_left": days_until_free_move()}
	var old := {"id": neighborhood.get("id", ""), "name": neighborhood.get("name", ""), "friends": [], "free_units": 1}
	var others: Array = neighborhood.get("other_neighborhoods", [])
	others.erase(target)
	others.append(old)
	neighborhood["id"] = target["id"]
	neighborhood["name"] = target["name"]
	neighborhood["last_move_day"] = day
	neighborhood["friends_here"] = (target.get("friends", []) as Array).duplicate()
	moved.emit(str(target["id"]), true)
	social_changed.emit()
	return {"ok": true, "free": true, "neighborhood": str(target["name"]), "next_free_in_days": days_until_free_move()}


func advance_days(n: int) -> void:
	day += n
	social_changed.emit()
