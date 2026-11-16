extends Node
## Resumen de mazmorra — UI v2.4 Paso 14 (design_ref/pantallas_html/MMO-Resumen.html,
## PROMPT_ANTIGRAVITY.md §3 «Resumen de mazmorra», Anexo B «Energías»).
##
## Autoload `DungeonSummaryService` o instanciable con `.new()` + `load_seed()`.
## Seed: res://config/dungeons/dungeon_summary_seed.json
##
## Tres columnas canónicas:
## 1. Tu botín inteligente: compara cada pieza con la tuya («▲ +8 nivel de objeto · +4,1 % daño»
##    o «= mismo nivel que las tuyas») y detecta al compañero que más mejoraría («Para Toro serían
##    +12 de nivel de objeto» → «Ofrecer a Toro»). Acciones: equipar, comparar, ofrecer, desguazar;
##    materiales: enviar al refugio o guardar en la mochila.
## 2. Momentos del grupo (sin toxicidad): un hito positivo por compañero, sin tablas de daño, y
##    1 elogio por compañero y mazmorra («Elogiar» → «Elogiado ✓»). No puedes elogiarte.
## 3. Tu progreso: XP (barra con lo que tenías y lo ganado, con subida de nivel), afinidades que
##    subieron (Anexo B), pista del Atlas por combinaciones usadas, reputación y misiones.
##    Salidas: «Repetir con el mismo grupo», «Volver al refugio» y «Salir al mundo».

signal summary_changed
signal item_compared(item_id: String, comparison: Dictionary)
signal item_equipped(item_id: String, slot: String, ilvl: int)
signal item_offered(item_id: String, member_id: String, delta: int)
signal item_scrapped(item_id: String, shards: int)
signal material_routed(item_id: String, destination: String, qty: int)
signal praised(member_id: String)
signal exit_chosen(choice: String, info: Dictionary)

const DEFAULT_SEED_PATH := "res://config/dungeons/dungeon_summary_seed.json"

const ITEM_NEW := "new"
const ITEM_EQUIPPED := "equipped"
const ITEM_OFFERED := "offered"
const ITEM_SCRAPPED := "scrapped"
const ITEM_SHELTER := "shelter"
const ITEM_BAG := "bag"

const EXIT_REPEAT := "repeat"
const EXIT_SHELTER := "shelter"
const EXIT_WORLD := "world"
const EXIT_LABELS := {
	EXIT_REPEAT: "Repetir con el mismo grupo",
	EXIT_SHELTER: "Volver al refugio",
	EXIT_WORLD: "Salir al mundo",
}

const UP_COLOR := "#4fe39a"
const SAME_COLOR := "#9aa6ae"
const DOWN_COLOR := "#ff8a8a"
const PRAISED_COLOR := "#4fe39a"
const MINUS := "−"

## Anexo B (lista abierta; misma paleta que hud_tokens.ENERGIES).
const ENERGIES := {
	"vacio": {"name": "Vacío", "color": "#b47bff"},
	"calor": {"name": "Calor", "color": "#ff7a45"},
	"eco": {"name": "Eco", "color": "#7fe0ff"},
	"pulso": {"name": "Pulso", "color": "#5aa9ff"},
	"runa": {"name": "Runa", "color": "#f5b546"},
	"savia": {"name": "Savia", "color": "#4fe39a"},
	"hierro": {"name": "Hierro", "color": "#b8c3ca"},
	"marea": {"name": "Marea", "color": "#3f8fd6"},
	"sombra": {"name": "Sombra", "color": "#8a7aa8"},
	"luz": {"name": "Luz", "color": "#fff1a8"},
}

var dungeon_id: String = "ferrum_vault"
var dungeon_name: String = "Bóveda de Ferrum"
var difficulty: String = "Heroica"
var status_text: String = "Completada"
var completion_s: float = 0.0
var group_best_s: float = 0.0
var local_player: String = "kael"
var player_gear: Dictionary = {}      # slot -> ilvl equipado
var members: Array[Dictionary] = []   # {id, name, initial, color, gear, moment, stat}
var praised_ids: Array[String] = []
var loot: Array[Dictionary] = []
var progress: Dictionary = {}
var praise_note: String = ""
var moments_note: String = ""
var seed_data: Dictionary = {}

var shards_from_scrap: int = 0
var exit_choice: String = ""
var last_exit: Dictionary = {}


func _ready() -> void:
	if seed_data.is_empty() and FileAccess.file_exists(DEFAULT_SEED_PATH):
		load_seed(DEFAULT_SEED_PATH)


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
	var d: Dictionary = data.get("dungeon", {})
	dungeon_id = str(d.get("id", "ferrum_vault"))
	dungeon_name = str(d.get("name", dungeon_id))
	difficulty = str(d.get("difficulty", ""))
	status_text = str(data.get("status", "Completada"))
	completion_s = maxf(0.0, float(data.get("completion_s", 0.0)))
	group_best_s = maxf(0.0, float(data.get("group_best_s", 0.0)))
	local_player = str(data.get("local_player", "kael"))
	player_gear = {}
	var pg: Dictionary = data.get("player_gear", {})
	for slot in pg:
		player_gear[str(slot)] = int(pg[slot])
	members.clear()
	for m in data.get("members", []):
		var gear := {}
		var mg: Dictionary = m.get("gear", {})
		for slot in mg:
			gear[str(slot)] = int(mg[slot])
		var nm := str(m.get("name", m.get("id", "?")))
		members.append({
			"id": str(m.get("id", "")), "name": nm, "initial": nm.left(1).to_upper(),
			"color": str(m.get("color", "#9aa6ae")), "gear": gear,
			"moment": str(m.get("moment", "")), "stat": (m.get("stat", {}) as Dictionary).duplicate(),
		})
	# Tu equipo también puede venir en la ficha del grupo.
	if player_gear.is_empty():
		player_gear = (get_member(local_player).get("gear", {}) as Dictionary).duplicate()
	praised_ids.clear()
	for p in data.get("praised", []):
		var pid := str(p)
		if can_praise(pid):
			praised_ids.append(pid)
	loot.clear()
	for it in data.get("loot", []):
		loot.append({
			"id": str(it.get("id", "")), "name": str(it.get("name", "")),
			"kind": str(it.get("kind", "gear")), "slot": str(it.get("slot", "")),
			"ilvl": int(it.get("ilvl", 0)), "qty": maxi(1, int(it.get("qty", 1))),
			"color": str(it.get("color", "#c3ccd3")), "stat": str(it.get("stat", "")),
			"tradeable": bool(it.get("tradeable", true)), "scrap_yield": int(it.get("scrap_yield", 0)),
			"destination": str(it.get("destination", "shelter")),
			"state": ITEM_NEW, "offered_to": "", "compared": false,
		})
	progress = (data.get("progress", {}) as Dictionary).duplicate(true)
	praise_note = str(data.get("praise_note", "Puedes dar 1 elogio por mazmorra a cada compañero."))
	moments_note = str(data.get("moments_note", "sin tablas de daño, solo lo que sumó"))
	shards_from_scrap = 0
	exit_choice = ""
	last_exit = {}


func reset() -> void:
	if not seed_data.is_empty():
		_apply(seed_data)


## Abre el resumen con datos externos (claves del seed; las ausentes salen del seed).
## Vacío = el resumen del seed.
func present(data: Dictionary = {}) -> Dictionary:
	if data.is_empty():
		reset()
		summary_changed.emit()
		return snapshot()
	var merged := seed_data.duplicate(true)
	for k in data:
		if k == "progress" and typeof(data[k]) == TYPE_DICTIONARY:
			var p: Dictionary = (merged.get("progress", {}) as Dictionary).duplicate(true)
			for pk in data[k]:
				p[pk] = data[k][pk]
			merged["progress"] = p
		else:
			merged[k] = data[k]
	_apply(merged)
	summary_changed.emit()
	return snapshot()


# ==========================================================================
# Cabecera
# ==========================================================================
func title_text() -> String:
	return dungeon_name if difficulty == "" else "%s · %s" % [dungeon_name, difficulty]


## «Completada · Bóveda de Ferrum Heroica»
func headline() -> String:
	return "%s · %s" % [status_text, dungeon_name if difficulty == "" else "%s %s" % [dungeon_name, difficulty]]


static func time_text(seconds: float) -> String:
	var s := maxi(0, roundi(seconds))
	if s >= 3600:
		return "%d:%02d:%02d" % [s / 3600, (s / 60) % 60, s % 60]
	return "%d:%02d" % [s / 60, s % 60]


func completion_text() -> String:
	return time_text(completion_s)


func is_group_record() -> bool:
	return completion_s > 0.0 and (group_best_s <= 0.0 or completion_s < group_best_s)


# ==========================================================================
# 1. Botín inteligente
# ==========================================================================
func get_item(item_id: String) -> Dictionary:
	for it in loot:
		if it["id"] == item_id:
			return it
	return {}


func get_member(id: String) -> Dictionary:
	for m in members:
		if m["id"] == id:
			return m
	return {}


func teammates() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for m in members:
		if m["id"] != local_player:
			out.append(m)
	return out


func is_gear(it: Dictionary) -> bool:
	return str(it.get("kind", "")) == "gear"


func item_title(it: Dictionary) -> String:
	if not is_gear(it) and int(it["qty"]) > 1:
		return "%s ×%d" % [it["name"], int(it["qty"])]
	return str(it["name"])


## Diferencia de iLvl con lo que llevas en la ranura (0 si no es equipo). Una pieza ya equipada
## conserva la comparación con la que sustituyó.
func upgrade_delta(item_id: String) -> int:
	var it := get_item(item_id)
	if it.is_empty() or not is_gear(it):
		return 0
	if it["state"] == ITEM_EQUIPPED:
		return int(it["ilvl"]) - int(it.get("replaced_ilvl", it["ilvl"]))
	return int(it["ilvl"]) - int(player_gear.get(it["slot"], 0))


func member_delta(item_id: String, member_id: String) -> int:
	var it := get_item(item_id)
	var m := get_member(member_id)
	if it.is_empty() or m.is_empty() or not is_gear(it):
		return 0
	return int(it["ilvl"]) - int((m["gear"] as Dictionary).get(it["slot"], 0))


## Compañero al que más mejoraría la pieza: {member_id, name, delta} o {} si a nadie.
func best_recipient(item_id: String) -> Dictionary:
	var it := get_item(item_id)
	if it.is_empty() or not is_gear(it) or not it["tradeable"]:
		return {}
	var best := {}
	for m in teammates():
		var d := member_delta(item_id, str(m["id"]))
		if d > 0 and (best.is_empty() or d > int(best["delta"])):
			best = {"member_id": m["id"], "name": m["name"], "delta": d}
	return best


static func signed(n: int) -> String:
	return ("+%d" % n) if n >= 0 else ("%s%d" % [MINUS, absi(n)])


## Línea bajo el nombre: «▲ +8 nivel de objeto · +4,1 % daño», «= mismo nivel que las tuyas»…
func delta_text(item_id: String) -> String:
	var it := get_item(item_id)
	if it.is_empty():
		return ""
	if not is_gear(it):
		return "al almacén del refugio" if it["destination"] == "shelter" else "a tu mochila"
	var d := upgrade_delta(item_id)
	if d > 0:
		var s := "▲ %s nivel de objeto" % signed(d)
		return s if str(it["stat"]) == "" else "%s · %s" % [s, it["stat"]]
	if d == 0:
		return "= mismo nivel que %s" % _yours(str(it["slot"]))
	return "▼ %s nivel de objeto" % signed(d)


func delta_color(item_id: String) -> String:
	var it := get_item(item_id)
	if it.is_empty() or not is_gear(it):
		return SAME_COLOR
	var d := upgrade_delta(item_id)
	return UP_COLOR if d > 0 else (SAME_COLOR if d == 0 else DOWN_COLOR)


static func _yours(slot: String) -> String:
	match slot:
		"shoulders", "boots", "gloves", "bracers", "hombreras", "botas", "guantes":
			return "las tuyas"
		"chest", "weapon", "helm", "belt", "cloak", "peto", "arma", "yelmo":
			return "el tuyo"
	return "lo tuyo"


## «Para Toro serían +12 de nivel de objeto.» (solo si no es mejora para ti).
func recipient_hint(item_id: String) -> String:
	var st := str(get_item(item_id).get("state", ""))
	if st == ITEM_EQUIPPED or st == ITEM_SCRAPPED or upgrade_delta(item_id) > 0:
		return ""
	var b := best_recipient(item_id)
	if b.is_empty():
		return ""
	return "Para %s serían %s de nivel de objeto." % [b["name"], signed(int(b["delta"]))]


## Pieza destacada: la que es mejora para ti con mayor delta.
func highlighted_item() -> String:
	var best := ""
	var best_d := 0
	for it in loot:
		if is_gear(it) and it["state"] == ITEM_NEW:
			var d := upgrade_delta(str(it["id"]))
			if d > best_d:
				best_d = d
				best = str(it["id"])
	return best


## Acciones disponibles para la pieza: [{id, label, primary}].
func item_actions(item_id: String) -> Array[Dictionary]:
	var it := get_item(item_id)
	var out: Array[Dictionary] = []
	if it.is_empty() or it["state"] != ITEM_NEW:
		return out
	if not is_gear(it):
		out.append({"id": "shelter", "label": "Enviar al refugio", "primary": it["destination"] == "shelter"})
		out.append({"id": "bag", "label": "Guardar en mochila", "primary": it["destination"] == "bag"})
		return out
	if upgrade_delta(item_id) > 0:
		out.append({"id": "equip", "label": "Equipar", "primary": true})
		out.append({"id": "compare", "label": "Comparar", "primary": false})
		return out
	var b := best_recipient(item_id)
	if not b.is_empty():
		out.append({"id": "offer", "label": "Ofrecer a %s" % b["name"], "primary": false, "member_id": b["member_id"]})
	else:
		out.append({"id": "compare", "label": "Comparar", "primary": false})
	out.append({"id": "scrap", "label": "Desguazar", "primary": false})
	return out


## Texto de estado tras resolver la pieza («Equipado ✓», «Ofrecido a Toro», …).
func item_state_text(item_id: String) -> String:
	var it := get_item(item_id)
	match str(it.get("state", "")):
		ITEM_EQUIPPED:
			return "Equipado ✓"
		ITEM_OFFERED:
			return "Ofrecido a %s" % get_member(str(it["offered_to"])).get("name", it["offered_to"])
		ITEM_SCRAPPED:
			return "Desguazado · +%d esquirlas" % int(it["scrap_yield"])
		ITEM_SHELTER:
			return "Enviado al refugio ✓"
		ITEM_BAG:
			return "Guardado en la mochila ✓"
	return ""


func compare(item_id: String) -> Dictionary:
	var it := get_item(item_id)
	if it.is_empty() or not is_gear(it):
		return {"ok": false, "reason": "not_gear"}
	it["compared"] = true
	var cmp := {
		"ok": true, "item_id": item_id, "slot": it["slot"],
		"current": int(player_gear.get(it["slot"], 0)), "new": int(it["ilvl"]),
		"delta": upgrade_delta(item_id), "stat": it["stat"], "text": delta_text(item_id),
		"best_recipient": best_recipient(item_id),
	}
	item_compared.emit(item_id, cmp)
	return cmp


func equip(item_id: String) -> Dictionary:
	var it := get_item(item_id)
	if it.is_empty() or not is_gear(it):
		return {"ok": false, "reason": "not_gear"}
	if it["state"] != ITEM_NEW:
		return {"ok": false, "reason": "already_" + str(it["state"])}
	var old := int(player_gear.get(it["slot"], 0))
	it["replaced_ilvl"] = old
	player_gear[it["slot"]] = int(it["ilvl"])
	var me := get_member(local_player)
	if not me.is_empty():
		(me["gear"] as Dictionary)[it["slot"]] = int(it["ilvl"])
	it["state"] = ITEM_EQUIPPED
	item_equipped.emit(item_id, str(it["slot"]), int(it["ilvl"]))
	summary_changed.emit()
	return {"ok": true, "slot": it["slot"], "old": old, "new": int(it["ilvl"]), "delta": int(it["ilvl"]) - old}


## Ofrece la pieza a un compañero (intercambio directo). "" = el que más mejora.
func offer_to(item_id: String, member_id: String = "") -> Dictionary:
	var it := get_item(item_id)
	if it.is_empty() or not is_gear(it):
		return {"ok": false, "reason": "not_gear"}
	if it["state"] != ITEM_NEW:
		return {"ok": false, "reason": "already_" + str(it["state"])}
	if not it["tradeable"]:
		return {"ok": false, "reason": "not_tradeable"}
	var target := member_id
	if target == "":
		target = str(best_recipient(item_id).get("member_id", ""))
	if target == "" or target == local_player or get_member(target).is_empty():
		return {"ok": false, "reason": "no_recipient"}
	var d := member_delta(item_id, target)
	it["state"] = ITEM_OFFERED
	it["offered_to"] = target
	item_offered.emit(item_id, target, d)
	summary_changed.emit()
	return {"ok": true, "member_id": target, "delta": d}


func scrap(item_id: String) -> Dictionary:
	var it := get_item(item_id)
	if it.is_empty() or not is_gear(it):
		return {"ok": false, "reason": "not_gear"}
	if it["state"] != ITEM_NEW:
		return {"ok": false, "reason": "already_" + str(it["state"])}
	it["state"] = ITEM_SCRAPPED
	shards_from_scrap += int(it["scrap_yield"])
	item_scrapped.emit(item_id, int(it["scrap_yield"]))
	summary_changed.emit()
	return {"ok": true, "shards": int(it["scrap_yield"])}


func send_to_shelter(item_id: String) -> Dictionary:
	return _route_material(item_id, ITEM_SHELTER)


func store_in_bag(item_id: String) -> Dictionary:
	return _route_material(item_id, ITEM_BAG)


func _route_material(item_id: String, dest: String) -> Dictionary:
	var it := get_item(item_id)
	if it.is_empty() or is_gear(it):
		return {"ok": false, "reason": "not_material"}
	if it["state"] != ITEM_NEW:
		return {"ok": false, "reason": "already_" + str(it["state"])}
	it["state"] = dest
	material_routed.emit(item_id, dest, int(it["qty"]))
	summary_changed.emit()
	return {"ok": true, "destination": dest, "qty": int(it["qty"])}


## Ejecuta una acción de `item_actions` por id.
func perform(item_id: String, action: String, member_id: String = "") -> Dictionary:
	match action:
		"equip":
			return equip(item_id)
		"compare":
			return compare(item_id)
		"offer":
			return offer_to(item_id, member_id)
		"scrap":
			return scrap(item_id)
		"shelter":
			return send_to_shelter(item_id)
		"bag":
			return store_in_bag(item_id)
	return {"ok": false, "reason": "unknown_action"}


func pending_loot() -> int:
	var n := 0
	for it in loot:
		if it["state"] == ITEM_NEW:
			n += 1
	return n


# ==========================================================================
# 2. Momentos del grupo y elogios
# ==========================================================================
func moments() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for m in members:
		out.append({
			"member_id": m["id"], "name": display_name(m), "initial": m["initial"], "color": m["color"],
			"text": m["moment"], "is_self": m["id"] == local_player,
			"praised": praised_ids.has(str(m["id"])),
		})
	return out


func display_name(m: Dictionary) -> String:
	return "%s (tú)" % m["name"] if m["id"] == local_player else str(m["name"])


func can_praise(member_id: String) -> bool:
	return member_id != local_player and not get_member(member_id).is_empty() and not praised_ids.has(member_id)


func is_praised(member_id: String) -> bool:
	return praised_ids.has(member_id)


## 1 elogio por compañero y mazmorra.
func praise(member_id: String) -> Dictionary:
	if member_id == local_player:
		return {"ok": false, "reason": "self"}
	if get_member(member_id).is_empty():
		return {"ok": false, "reason": "unknown_member"}
	if praised_ids.has(member_id):
		return {"ok": false, "reason": "already_praised"}
	praised_ids.append(member_id)
	praised.emit(member_id)
	summary_changed.emit()
	return {"ok": true, "member_id": member_id, "remaining": praises_remaining()}


## «Elogiar», «Elogiado ✓» o "" (tú).
func praise_label(member_id: String) -> String:
	if member_id == local_player:
		return ""
	return "Elogiado ✓" if praised_ids.has(member_id) else "Elogiar"


func praises_remaining() -> int:
	return teammates().size() - praised_ids.size()


# ==========================================================================
# 3. Progreso
# ==========================================================================
static func thousands(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "." + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if n < 0 else "") + s + out


func level() -> int:
	return int(progress.get("level", 1))


func xp_to_next() -> int:
	return maxi(1, int(progress.get("xp_to_next", 1)))


func xp_before() -> int:
	return clampi(int(progress.get("xp_before", 0)), 0, xp_to_next())


func xp_gained() -> int:
	return maxi(0, int(progress.get("xp_gained", 0)))


## «+18.400 XP»
func xp_text() -> String:
	return "+%s XP" % thousands(xp_gained())


func leveled_up() -> bool:
	return xp_before() + xp_gained() >= xp_to_next()


func new_level() -> int:
	return level() + (1 if leveled_up() else 0)


## Barra: proporción previa (oscura) y ganada (clara) dentro del nivel actual.
func xp_before_ratio() -> float:
	return float(xp_before()) / float(xp_to_next())


func xp_gain_ratio() -> float:
	return minf(1.0 - xp_before_ratio(), float(xp_gained()) / float(xp_to_next()))


## «Nivel 32» o «Nivel 32 → 33».
func level_text() -> String:
	return "Nivel %d" % level() if not leveled_up() else "Nivel %d → %d" % [level(), new_level()]


static func energy_info(id: String) -> Dictionary:
	return ENERGIES.get(id, {"name": id.capitalize(), "color": "#c3ccd3"})


## [{energy, name, color, delta, text}] solo con las que subieron.
func affinities() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for a in progress.get("affinities", []):
		var d := int(a.get("delta", 0))
		if d <= 0:
			continue
		var e := str(a.get("energy", ""))
		var info := energy_info(e)
		out.append({"energy": e, "name": info["name"], "color": info["color"], "delta": d, "text": "+%d" % d})
	return out


func atlas_threshold() -> int:
	return maxi(1, int(progress.get("atlas_hint_threshold", 10)))


## Pistas del Atlas por combinaciones que llegaron al umbral, de más a menos usos.
func atlas_hints() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c in progress.get("combos", []):
		var uses := int(c.get("uses", 0))
		if uses < atlas_threshold():
			continue
		var names: Array = (c.get("energies", []) as Array).map(func(e): return str(energy_info(str(e))["name"]))
		var combo := " + ".join(names)
		out.append({"energies": c.get("energies", []), "combo": combo, "uses": uses,
			"text": "Usaste %s %d veces. Pista nueva en el Atlas." % [combo, uses]})
	out.sort_custom(func(a, b): return int(a["uses"]) > int(b["uses"]))
	return out


func reputation() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for r in progress.get("reputation", []):
		var d := int(r.get("delta", 0))
		out.append({"faction": str(r.get("faction", "")), "delta": d,
			"label": "Reputación %s" % r.get("faction", ""), "text": signed(d) if d < 0 else "+%s" % thousands(d)})
	return out


func quests() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for q in progress.get("quests", []):
		out.append({"name": str(q.get("name", "")), "status": str(q.get("status", "avanzó")),
			"label": "Misión «%s»" % q.get("name", "")})
	return out


# ==========================================================================
# Salidas
# ==========================================================================
func exit_options() -> Array[Dictionary]:
	return [
		{"id": EXIT_REPEAT, "label": EXIT_LABELS[EXIT_REPEAT], "primary": true},
		{"id": EXIT_SHELTER, "label": EXIT_LABELS[EXIT_SHELTER], "primary": false},
		{"id": EXIT_WORLD, "label": EXIT_LABELS[EXIT_WORLD], "primary": false},
	]


func choose_exit(choice: String) -> Dictionary:
	if not EXIT_LABELS.has(choice):
		return {"ok": false, "reason": "unknown_exit"}
	exit_choice = choice
	last_exit = {
		"ok": true, "choice": choice, "dungeon_id": dungeon_id, "difficulty": difficulty,
		"group": members.map(func(m): return str(m["id"])) if choice == EXIT_REPEAT else [],
		"pending_loot": pending_loot(),
	}
	exit_chosen.emit(choice, last_exit)
	return last_exit


func repeat_with_group() -> Dictionary:
	return choose_exit(EXIT_REPEAT)


func return_to_shelter() -> Dictionary:
	return choose_exit(EXIT_SHELTER)


func exit_to_world() -> Dictionary:
	return choose_exit(EXIT_WORLD)


func snapshot() -> Dictionary:
	return {
		"dungeon_id": dungeon_id, "headline": headline(), "time": completion_text(), "record": is_group_record(),
		"loot": loot.duplicate(true), "praised": praised_ids.duplicate(), "xp": xp_gained(), "level": level(),
	}
