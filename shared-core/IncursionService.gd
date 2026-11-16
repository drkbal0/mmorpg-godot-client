extends Node
## Incursiones con extracción — UI v2.4 Paso 12 (design_ref/pantallas_html/MMO-Incursiones.html,
## PROMPT_ANTIGRAVITY.md §2.2.7).
##
## Autoload `IncursionService` o instanciable con `.new()` + `load_seed()` (reloj manual: `tick`).
## Seed: res://config/incursions/incursions_seed.json
##
## Tres tipos canónicos:
## - Rápida «Grieta menor del Vado» (10–15 min, 1–3 jugadores, riesgo bajo): 1 salida al final;
##   si mueres pierdes el botín de dentro; desconexión protegida 3 min. «Entrar ahora».
## - Media «Bóveda de Ferrum» (30–40 min, 5 jugadores, riesgo medio): salida a mitad y al final;
##   si mueres tu grupo puede levantarte. «Ir a la antesala».
## - Larga «Las Minas Abisales» (2–4 h por tramos, 5–10 jugadores, riesgo alto): 3 campamentos
##   que guardan el progreso, fardo recuperable 30 min y bengala de extracción. «Planear con el gremio».
##
## Regla de extracción (§2.2.7): solo te llevas el botín si extraes — por una salida, con una
## bengala o al terminar. La Bolsa segura (3 ranuras) nunca se pierde. Si te desconectas dentro,
## tu personaje se queda ahí (salvo protección de la rápida o estando en un campamento).

signal selection_changed(incursion_id: String)
signal loadout_changed
signal run_started(incursion_id: String)
signal run_stage_changed(stage_index: int, kind: String)
signal run_ended(result: Dictionary)
signal entry_requested(incursion_id: String, action: String)

const DEFAULT_SEED_PATH := "res://config/incursions/incursions_seed.json"

const TIERS: Array[String] = ["quick", "medium", "long"]
const STAGE_KINDS: Array[String] = ["stage", "boss", "exit", "camp"]
const DEFAULT_SECURE_CAPACITY := 3
const DEFAULT_BUNDLE_S := 1800.0

const RISKS := {
	"low": {"name": "Riesgo bajo", "color": "#4fe39a"},
	"medium": {"name": "Riesgo medio", "color": "#f5c35b"},
	"high": {"name": "Riesgo alto", "color": "#ff8a8a"},
}
const TIER_COLORS := {"quick": "#4fe39a", "medium": "#f5c35b", "long": "#ff8a8a"}
const STAGE_COLORS := {"stage": "#3a4a54", "boss": "#ff6b6b", "exit": "#4fe39a", "camp": "#4fe39a"}
const STAGE_NAMES := {"stage": "Tramo", "boss": "Jefe", "exit": "Salida", "camp": "Campamento seguro"}

## Estados de la partida dentro de la incursión.
const RUN_NONE := "none"
const RUN_INSIDE := "inside"
const RUN_DOWNED := "downed"            # media: esperando a que el grupo te levante
const RUN_DISCONNECTED := "disconnected"
const RUN_EXTRACTED := "extracted"
const RUN_DEAD := "dead"

const RULE_TEXT := "Solo te llevas el botín si extraes: por una salida, con una bengala o al terminar. Si te desconectas dentro, tu personaje se queda ahí."

var incursions: Array[Dictionary] = []
var selected_id: String = ""
var recommended_id: String = ""

# Equipo que llevas («Qué llevas»).
var gold: int = 0
var durability: int = 100
var campfire_kits: int = 0
var flares: int = 0
var return_route: String = ""
var consumables: Dictionary = {}       # id -> cantidad
var secure_capacity: int = DEFAULT_SECURE_CAPACITY
var secure_bag: Array[String] = []     # ids de `carried`
var carried: Array[Dictionary] = []    # [{id, name, rarity, value}]
var party: Dictionary = {"ready": 0, "size": 1}

## Partida en curso (vacía si no hay). Ver `start_run`.
var run: Dictionary = {}
## Fardo de muerte de la larga (vacío si no hay): {incursion_id, items, loot, gold, expires_at}.
var bundle: Dictionary = {}
var last_result: Dictionary = {}
var clock: float = 0.0


func _ready() -> void:
	if incursions.is_empty() and FileAccess.file_exists(DEFAULT_SEED_PATH):
		load_seed(DEFAULT_SEED_PATH)


func _process(delta: float) -> void:
	if not run.is_empty() or not bundle.is_empty():
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
	incursions.clear()
	for raw in data.get("incursions", []):
		register_incursion(raw)
	recommended_id = str(data.get("recommended", ""))
	if get_incursion(recommended_id).is_empty() and not incursions.is_empty():
		recommended_id = incursions[0]["id"]
	selected_id = recommended_id
	set_loadout(data.get("loadout", {}))
	run = {}
	bundle = {}
	last_result = {}
	clock = 0.0


func register_incursion(raw: Dictionary) -> void:
	var inc := raw.duplicate(true)
	inc["id"] = str(raw.get("id", ""))
	if inc["id"] == "":
		return
	var tier := str(raw.get("tier", "quick"))
	inc["tier"] = tier if tier in TIERS else "quick"
	inc["name"] = str(raw.get("name", inc["id"]))
	inc["risk"] = str(raw.get("risk", "low")) if RISKS.has(str(raw.get("risk", ""))) else "low"
	var pl: Array = raw.get("players", [1, 1])
	inc["players"] = [int(pl[0]), int(pl[1] if pl.size() > 1 else pl[0])]
	var dm: Array = raw.get("duration_min", [0, 0])
	inc["duration_min"] = [int(dm[0]), int(dm[1] if dm.size() > 1 else dm[0])]
	var st: Array[String] = []
	for k in raw.get("stages", []):
		st.append(str(k) if str(k) in STAGE_KINDS else "stage")
	inc["stages"] = st
	inc["camps"] = st.count("camp")
	inc["flare_allowed"] = bool(raw.get("flare_allowed", false))
	inc["risk_scope"] = (raw.get("risk_scope", ["inside_loot"]) as Array).duplicate()
	inc["requirements"] = (raw.get("requirements", {}) as Dictionary).duplicate(true)
	inc["cta"] = (raw.get("cta", {}) as Dictionary).duplicate(true)
	inc["disconnect_protection_s"] = int(raw.get("disconnect_protection_s", 0))
	inc["bundle_s"] = float(raw.get("bundle_s", DEFAULT_BUNDLE_S))
	for i in incursions.size():
		if incursions[i]["id"] == inc["id"]:
			incursions[i] = inc
			return
	incursions.append(inc)


func set_loadout(l: Dictionary) -> void:
	gold = int(l.get("gold", 0))
	durability = clampi(int(l.get("durability", 100)), 0, 100)
	campfire_kits = int(l.get("campfire_kits", 0))
	flares = int(l.get("flares", 0))
	return_route = str(l.get("return_route", ""))
	consumables = (l.get("consumables", {}) as Dictionary).duplicate(true)
	secure_capacity = maxi(0, int(l.get("secure_capacity", DEFAULT_SECURE_CAPACITY)))
	carried.clear()
	for it in l.get("carried", []):
		carried.append({"id": str(it.get("id", "")), "name": str(it.get("name", it.get("id", ""))),
			"rarity": str(it.get("rarity", "common")), "value": int(it.get("value", 0))})
	secure_bag.clear()
	for id in l.get("secure_bag", []):
		if secure_bag.size() < secure_capacity and has_carried(str(id)) and not secure_bag.has(str(id)):
			secure_bag.append(str(id))
	party = (l.get("party", {"ready": 0, "size": 1}) as Dictionary).duplicate()
	loadout_changed.emit()


## Toma el oro del monedero (CommerceService) si se quiere sincronizar.
func sync_gold(amount: int) -> void:
	gold = maxi(0, amount)
	loadout_changed.emit()


# ==========================================================================
# Tipos de incursión
# ==========================================================================
func get_incursion(id: String) -> Dictionary:
	for inc in incursions:
		if inc["id"] == id:
			return inc
	return {}


func get_by_tier(tier: String) -> Dictionary:
	for inc in incursions:
		if inc["tier"] == tier:
			return inc
	return {}


func select(id: String) -> bool:
	if get_incursion(id).is_empty():
		return false
	if selected_id != id:
		selected_id = id
		selection_changed.emit(id)
	return true


func get_selected() -> Dictionary:
	return get_incursion(selected_id)


static func risk_name(risk: String) -> String:
	return str(RISKS.get(risk, RISKS["low"])["name"])


static func risk_color(risk: String) -> Color:
	return Color(RISKS.get(risk, RISKS["low"])["color"])


static func tier_color(tier: String) -> Color:
	return Color(TIER_COLORS.get(tier, "#4fe39a"))


static func stage_color(kind: String) -> Color:
	return Color(STAGE_COLORS.get(kind, "#3a4a54"))


static func stage_name(kind: String) -> String:
	return str(STAGE_NAMES.get(kind, kind))


func players_text(id: String) -> String:
	var p: Array = get_incursion(id).get("players", [1, 1])
	return "%d jugador%s" % [p[0], "" if p[0] == 1 else "es"] if p[0] == p[1] else "%d–%d jugadores" % [p[0], p[1]]


## Chips de la tarjeta: duración · jugadores · riesgo.
func tags(id: String) -> Array[String]:
	var inc := get_incursion(id)
	if inc.is_empty():
		return []
	return [str(inc.get("duration_text", "")), players_text(id), risk_name(inc["risk"])]


## Etapas con su tipo y color (barra «Etapas y puntos de extracción»).
func stages(id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var inc := get_incursion(id)
	for i in (inc.get("stages", []) as Array).size():
		var k: String = inc["stages"][i]
		out.append({"index": i, "kind": k, "name": stage_name(k), "color": stage_color(k),
			"extraction": k == "exit", "safe": k == "camp"})
	return out


## Puntos donde se puede extraer: salidas, y además «al terminar» (última etapa).
func extraction_points(id: String) -> Array[int]:
	var out: Array[int] = []
	var st: Array = get_incursion(id).get("stages", [])
	for i in st.size():
		if st[i] == "exit":
			out.append(i)
	return out


func camp_points(id: String) -> Array[int]:
	var out: Array[int] = []
	var st: Array = get_incursion(id).get("stages", [])
	for i in st.size():
		if st[i] == "camp":
			out.append(i)
	return out


## Filas de detalle de la tarjeta (Botín · Extracción/Campamentos · Si mueres · extra).
func card_rows(id: String) -> Array[Dictionary]:
	var inc := get_incursion(id)
	if inc.is_empty():
		return []
	var rows: Array[Dictionary] = [{"key": "loot", "label": "Botín", "value": str(inc.get("loot", "")), "good": false}]
	if int(inc["camps"]) > 0:
		rows.append({"key": "camps", "label": "Campamentos", "value": "%d (guardan progreso)" % inc["camps"], "good": true})
	else:
		rows.append({"key": "extraction", "label": "Extracción", "value": str(inc.get("extraction", "")), "good": false})
	rows.append({"key": "death", "label": "Si mueres", "value": str(inc.get("death_text", "")), "good": false})
	match inc["tier"]:
		"quick":
			rows.append({"key": "disconnect", "label": "Desconexión protegida", "value": "%d min" % int(inc["disconnect_protection_s"] / 60), "good": false})
		"medium":
			rows.append({"key": "party", "label": "Tu grupo", "value": "%d / %d listos" % [int(party.get("ready", 0)), int(party.get("size", 1))], "good": false})
		"long":
			rows.append({"key": "flare", "label": "Bengala de extracción", "value": "tienes %d" % flares if flares > 0 else "no tienes", "good": flares > 0})
	return rows


# ==========================================================================
# Bolsa segura y riesgo
# ==========================================================================
func has_carried(item_id: String) -> bool:
	return not get_carried(item_id).is_empty()


func get_carried(item_id: String) -> Dictionary:
	for it in carried:
		if it["id"] == item_id:
			return it
	return {}


func is_secured(item_id: String) -> bool:
	return secure_bag.has(item_id)


func secure_bag_status() -> Dictionary:
	var names: Array[String] = []
	for id in secure_bag:
		names.append(str(get_carried(id).get("name", id)))
	return {
		"used": secure_bag.size(),
		"capacity": secure_capacity,
		"full": secure_bag.size() >= secure_capacity,
		"items": secure_bag.duplicate(),
		"names": names,
		"title": "Bolsa segura · %d / %d" % [secure_bag.size(), secure_capacity],
		"text": " · ".join(names) if not names.is_empty() else "Vacía: elige hasta %d objetos que nunca perderás." % secure_capacity,
	}


func put_in_secure_bag(item_id: String) -> Dictionary:
	if not run.is_empty():
		return {"ok": false, "reason": "inside_incursion"}
	if not has_carried(item_id):
		return {"ok": false, "reason": "not_carried"}
	if is_secured(item_id):
		return {"ok": false, "reason": "already_secured"}
	if secure_bag.size() >= secure_capacity:
		return {"ok": false, "reason": "bag_full"}
	secure_bag.append(item_id)
	loadout_changed.emit()
	return {"ok": true, "item_id": item_id}


func remove_from_secure_bag(item_id: String) -> Dictionary:
	if not run.is_empty():
		return {"ok": false, "reason": "inside_incursion"}
	if not is_secured(item_id):
		return {"ok": false, "reason": "not_secured"}
	secure_bag.erase(item_id)
	loadout_changed.emit()
	return {"ok": true, "item_id": item_id}


## Cambia un objeto de la bolsa por otro (bolsa llena).
func swap_secure(out_id: String, in_id: String) -> Dictionary:
	if not is_secured(out_id):
		return {"ok": false, "reason": "not_secured"}
	if not has_carried(in_id) or is_secured(in_id):
		return {"ok": false, "reason": "invalid_item"}
	if not run.is_empty():
		return {"ok": false, "reason": "inside_incursion"}
	secure_bag[secure_bag.find(out_id)] = in_id
	loadout_changed.emit()
	return {"ok": true}


## Lo que se pierde si mueres en `incursion_id` ("" = la seleccionada) sin extraer.
func at_risk(incursion_id: String = "") -> Dictionary:
	var inc := get_incursion(incursion_id if incursion_id != "" else selected_id)
	var scope: Array = inc.get("risk_scope", ["inside_loot"])
	var risk_items: Array[Dictionary] = []
	var value := 0
	if scope.has("equipment"):
		for it in carried:
			if not is_secured(it["id"]):
				risk_items.append(it.duplicate())
				value += int(it["value"])
	var safe_value := 0
	for id in secure_bag:
		safe_value += int(get_carried(id).get("value", 0))
	var risk_gold := gold if scope.has("gold") else 0
	var text := ""
	if scope.has("equipment") and scope.has("gold"):
		text = "El resto del equipo, %s oro y todo el botín que encuentres dentro." % fmt(risk_gold)
	elif scope.has("equipment"):
		text = "El resto del equipo y todo el botín que encuentres dentro."
	else:
		text = "Solo el botín que encuentres dentro. Tu equipo y tu oro vuelven contigo."
	return {
		"items": risk_items,
		"item_count": risk_items.size(),
		"items_value": value,
		"gold": risk_gold,
		"total_value": value + risk_gold,
		"inside_loot": true,
		"secured_value": safe_value,
		"recoverable": inc.get("death_rule", "") == "bundle",
		"revivable": inc.get("death_rule", "") == "party_revive",
		"text": text,
	}


# ==========================================================================
# Preparación
# ==========================================================================
func consumables_total() -> int:
	var n := 0
	for k in consumables:
		n += int(consumables[k])
	return n


static func durability_color(pct: int) -> Color:
	if pct >= 60:
		return Color("#4fe39a")
	if pct >= 30:
		return Color("#f5c35b")
	return Color("#ff6b6b")


## Checklist «Preparación» para la incursión. Cada fila: {id, label, value, status, required}.
## status: ok | warn | missing. `required` = bloquea la entrada si falta.
func readiness(incursion_id: String = "") -> Array[Dictionary]:
	var inc := get_incursion(incursion_id if incursion_id != "" else selected_id)
	var req: Dictionary = inc.get("requirements", {})
	var rows: Array[Dictionary] = []
	var need_c := int(req.get("consumables", 0))
	var have_c := consumables_total()
	rows.append({"id": "consumables", "label": "Consumibles", "value": "✓" if have_c >= need_c and have_c > 0 else "%d / %d" % [have_c, need_c],
		"status": "ok" if have_c >= need_c and have_c > 0 else ("missing" if have_c < need_c else "warn"), "required": need_c > 0, "have": have_c, "need": need_c})
	var need_d := int(req.get("durability", 0))
	rows.append({"id": "durability", "label": "Reparación", "value": "%d %%" % durability,
		"status": "ok" if durability >= need_d and durability >= 60 else ("warn" if durability >= need_d else "missing"),
		"required": need_d > 0, "have": durability, "need": need_d})
	var need_k := int(req.get("campfire_kit", 0))
	rows.append({"id": "campfire_kit", "label": "Kit de fogata", "value": str(campfire_kits),
		"status": "ok" if campfire_kits >= maxi(1, need_k) else ("missing" if need_k > 0 else "warn"), "required": need_k > 0, "have": campfire_kits, "need": need_k})
	var need_f := int(req.get("flare", 0))
	rows.append({"id": "flare", "label": "Bengala de extracción", "value": str(flares),
		"status": "ok" if flares >= maxi(1, need_f) else ("missing" if need_f > 0 else "warn"), "required": need_f > 0, "have": flares, "need": need_f})
	rows.append({"id": "return_route", "label": "Ruta de vuelta", "value": return_route if return_route != "" else "sin ruta",
		"status": "ok" if return_route != "" else "warn", "required": false})
	return rows


## Lo que impide entrar (filas `required` con estado `missing`).
func blockers(incursion_id: String = "") -> Array[String]:
	var out: Array[String] = []
	for r in readiness(incursion_id):
		if r["required"] and r["status"] == "missing":
			out.append(r["id"])
	return out


func is_ready(incursion_id: String = "") -> bool:
	return blockers(incursion_id).is_empty()


func readiness_summary(incursion_id: String = "") -> Dictionary:
	var rows := readiness(incursion_id)
	var ok := 0
	for r in rows:
		if r["status"] == "ok":
			ok += 1
	return {"ok": ok, "total": rows.size(), "ready": is_ready(incursion_id), "blockers": blockers(incursion_id)}


func add_consumable(id: String, n: int = 1) -> void:
	consumables[id] = maxi(0, int(consumables.get(id, 0)) + n)
	if int(consumables[id]) == 0:
		consumables.erase(id)
	loadout_changed.emit()


func set_durability(pct: int) -> void:
	durability = clampi(pct, 0, 100)
	loadout_changed.emit()


func add_flares(n: int) -> void:
	flares = maxi(0, flares + n)
	loadout_changed.emit()


func add_campfire_kits(n: int) -> void:
	campfire_kits = maxi(0, campfire_kits + n)
	loadout_changed.emit()


func set_party(ready: int, size: int) -> void:
	party = {"ready": clampi(ready, 0, maxi(1, size)), "size": maxi(1, size)}
	loadout_changed.emit()


# ==========================================================================
# Entrada (botón de la tarjeta)
# ==========================================================================
## «Entrar ahora» (enter: entra ya) · «Ir a la antesala» (lobby) · «Planear con el gremio» (guild).
func request_entry(incursion_id: String, party_size: int = 1) -> Dictionary:
	var inc := get_incursion(incursion_id)
	if inc.is_empty():
		return {"ok": false, "reason": "unknown_incursion"}
	select(incursion_id)
	var action := str(inc["cta"].get("action", "enter"))
	entry_requested.emit(incursion_id, action)
	match action:
		"enter":
			return start_run(incursion_id, party_size)
		"lobby":
			return {"ok": true, "action": "lobby", "incursion_id": incursion_id, "party": party.duplicate(), "ready": is_ready(incursion_id)}
		"guild":
			return {"ok": true, "action": "guild", "incursion_id": incursion_id, "open_window": "social_window", "ready": is_ready(incursion_id)}
	return {"ok": false, "reason": "unknown_action"}


# ==========================================================================
# Partida dentro (simulación cliente del flujo de extracción)
# ==========================================================================
func start_run(incursion_id: String, party_size: int = 1) -> Dictionary:
	var inc := get_incursion(incursion_id)
	if inc.is_empty():
		return {"ok": false, "reason": "unknown_incursion"}
	if not run.is_empty():
		return {"ok": false, "reason": "already_inside"}
	var pl: Array = inc["players"]
	if party_size < int(pl[0]) or party_size > int(pl[1]):
		return {"ok": false, "reason": "party_size", "min": pl[0], "max": pl[1]}
	var b := blockers(incursion_id)
	if not b.is_empty():
		return {"ok": false, "reason": "not_ready", "blockers": b}
	run = {
		"incursion_id": incursion_id,
		"stage": 0,
		"loot": [],
		"loot_gold": 0,
		"state": RUN_INSIDE,
		"checkpoint": -1,
		"party_size": party_size,
		"started_at": clock,
		"disconnected_at": -1.0,
		"downed_at": -1.0,
	}
	selected_id = incursion_id
	run_started.emit(incursion_id)
	run_stage_changed.emit(0, inc["stages"][0])
	return {"ok": true, "incursion_id": incursion_id, "stage": 0}


func in_run() -> bool:
	return not run.is_empty()


func current_stage_kind() -> String:
	if run.is_empty():
		return ""
	var st: Array = get_incursion(run["incursion_id"])["stages"]
	return str(st[clampi(int(run["stage"]), 0, st.size() - 1)])


func add_loot(item: Dictionary) -> bool:
	if run.is_empty() or run["state"] != RUN_INSIDE:
		return false
	run["loot"].append({"id": str(item.get("id", "")), "name": str(item.get("name", item.get("id", ""))),
		"rarity": str(item.get("rarity", "common")), "value": int(item.get("value", 0))})
	return true


func add_loot_gold(amount: int) -> bool:
	if run.is_empty() or run["state"] != RUN_INSIDE:
		return false
	run["loot_gold"] = int(run["loot_gold"]) + maxi(0, amount)
	return true


func inside_loot_value() -> int:
	if run.is_empty():
		return 0
	var v := int(run["loot_gold"])
	for it in run["loot"]:
		v += int(it["value"])
	return v


## Avanza a la siguiente etapa. Al pasar la última, se termina (extracción «al terminar»).
func advance_stage() -> Dictionary:
	if run.is_empty() or run["state"] != RUN_INSIDE:
		return {"ok": false, "reason": "not_inside"}
	var st: Array = get_incursion(run["incursion_id"])["stages"]
	if int(run["stage"]) >= st.size() - 1:
		return _finish_extraction("completed")
	run["stage"] = int(run["stage"]) + 1
	var kind: String = st[run["stage"]]
	if kind == "camp":
		run["checkpoint"] = run["stage"]
	run_stage_changed.emit(run["stage"], kind)
	return {"ok": true, "stage": run["stage"], "kind": kind, "checkpoint": run["checkpoint"]}


func can_extract() -> bool:
	return not run.is_empty() and run["state"] == RUN_INSIDE and current_stage_kind() == "exit"


## Extracción por una salida (etapa «exit»).
func extract() -> Dictionary:
	if run.is_empty() or run["state"] != RUN_INSIDE:
		return {"ok": false, "reason": "not_inside"}
	if current_stage_kind() != "exit":
		return {"ok": false, "reason": "no_exit_here"}
	return _finish_extraction("exit")


func can_use_flare() -> bool:
	return not run.is_empty() and run["state"] == RUN_INSIDE and bool(get_incursion(run["incursion_id"])["flare_allowed"]) and flares > 0


## Bengala de extracción: extrae donde estés (solo donde se permite) y se gasta.
func use_flare() -> Dictionary:
	if run.is_empty() or run["state"] != RUN_INSIDE:
		return {"ok": false, "reason": "not_inside"}
	if not bool(get_incursion(run["incursion_id"])["flare_allowed"]):
		return {"ok": false, "reason": "flare_not_allowed"}
	if flares <= 0:
		return {"ok": false, "reason": "no_flare"}
	flares -= 1
	loadout_changed.emit()
	return _finish_extraction("flare")


func _finish_extraction(method: String) -> Dictionary:
	var loot: Array = run["loot"].duplicate(true)
	var lg := int(run["loot_gold"])
	gold += lg
	for it in loot:
		carried.append({"id": it["id"], "name": it["name"], "rarity": it.get("rarity", "common"), "value": it["value"]})
	last_result = {"ok": true, "outcome": RUN_EXTRACTED, "method": method, "incursion_id": run["incursion_id"],
		"kept_loot": loot, "kept_gold": lg, "lost_items": [], "lost_gold": 0, "lost_loot": []}
	run = {}
	loadout_changed.emit()
	run_ended.emit(last_result)
	return last_result


## Muerte dentro. Aplica la regla del tipo:
## - lose_inside_loot (rápida): pierdes el botín de dentro; tu equipo vuelve contigo.
## - party_revive (media): quedas abatido; tu grupo puede levantarte (`revive`) o caes (`bleed_out`).
## - bundle (larga): dejas un fardo con lo que estaba en riesgo, recuperable 30 min.
func die() -> Dictionary:
	if run.is_empty() or run["state"] != RUN_INSIDE:
		return {"ok": false, "reason": "not_inside"}
	var inc := get_incursion(run["incursion_id"])
	match str(inc.get("death_rule", "lose_inside_loot")):
		"party_revive":
			run["state"] = RUN_DOWNED
			run["downed_at"] = clock
			return {"ok": true, "outcome": RUN_DOWNED, "revivable": true}
		"bundle":
			return _die_with_bundle(inc)
	return _die_final(inc)


## La media: un compañero te levanta.
func revive() -> Dictionary:
	if run.is_empty() or run["state"] != RUN_DOWNED:
		return {"ok": false, "reason": "not_downed"}
	if int(run["party_size"]) <= 1:
		return {"ok": false, "reason": "no_party"}
	run["state"] = RUN_INSIDE
	run["downed_at"] = -1.0
	return {"ok": true, "outcome": RUN_INSIDE}


## La media: nadie te levanta (el grupo cae o te rindes): pierdes lo que estaba en riesgo.
func bleed_out() -> Dictionary:
	if run.is_empty() or run["state"] != RUN_DOWNED:
		return {"ok": false, "reason": "not_downed"}
	return _die_final(get_incursion(run["incursion_id"]))


func _lost_items_for(inc: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if (inc.get("risk_scope", []) as Array).has("equipment"):
		for it in carried:
			if not is_secured(it["id"]):
				out.append(it.duplicate())
	return out


func _die_final(inc: Dictionary) -> Dictionary:
	var lost := _lost_items_for(inc)
	var lost_gold := gold if (inc.get("risk_scope", []) as Array).has("gold") else 0
	for it in lost:
		_remove_carried(it["id"])
	gold -= lost_gold
	last_result = {"ok": true, "outcome": RUN_DEAD, "incursion_id": inc["id"], "kept_loot": [], "kept_gold": 0,
		"lost_loot": run["loot"].duplicate(true), "lost_loot_gold": int(run["loot_gold"]),
		"lost_items": lost, "lost_gold": lost_gold, "secured": secure_bag.duplicate(), "bundle": false}
	run = {}
	loadout_changed.emit()
	run_ended.emit(last_result)
	return last_result


func _die_with_bundle(inc: Dictionary) -> Dictionary:
	var lost := _lost_items_for(inc)
	var lost_gold := gold
	for it in lost:
		_remove_carried(it["id"])
	gold = 0
	bundle = {"incursion_id": inc["id"], "items": lost, "loot": run["loot"].duplicate(true),
		"loot_gold": int(run["loot_gold"]), "gold": lost_gold, "expires_at": clock + float(inc["bundle_s"]),
		"stage": int(run["stage"])}
	# Reapareces en el último campamento (o en la entrada) sin el botín.
	run["loot"] = []
	run["loot_gold"] = 0
	run["stage"] = maxi(0, int(run["checkpoint"]))
	loadout_changed.emit()
	return {"ok": true, "outcome": "bundle_dropped", "bundle_expires_in": float(inc["bundle_s"]),
		"respawn_stage": run["stage"], "secured": secure_bag.duplicate()}


func bundle_time_left() -> float:
	return 0.0 if bundle.is_empty() else maxf(0.0, float(bundle["expires_at"]) - clock)


## Recuperar el fardo (dentro de los 30 min).
func recover_bundle() -> Dictionary:
	if bundle.is_empty():
		return {"ok": false, "reason": "no_bundle"}
	if clock > float(bundle["expires_at"]):
		return _expire_bundle()
	for it in bundle["items"]:
		carried.append(it)
	gold += int(bundle["gold"])
	if not run.is_empty():
		for it in bundle["loot"]:
			run["loot"].append(it)
		run["loot_gold"] = int(run["loot_gold"]) + int(bundle["loot_gold"])
	var r := {"ok": true, "recovered_items": (bundle["items"] as Array).size(), "recovered_gold": int(bundle["gold"])}
	bundle = {}
	loadout_changed.emit()
	return r


func _expire_bundle() -> Dictionary:
	var lost: Dictionary = bundle.duplicate(true)
	bundle = {}
	last_result = {"ok": true, "outcome": "bundle_lost", "lost_items": lost["items"], "lost_gold": lost["gold"], "lost_loot": lost["loot"]}
	loadout_changed.emit()
	return {"ok": false, "reason": "bundle_expired", "lost": lost}


## Desconexión dentro: el personaje se queda ahí.
## - Rápida: protegida durante `disconnect_protection_s` (3 min).
## - Larga en campamento: el progreso queda guardado (puedes volver otro día).
func disconnect_inside() -> Dictionary:
	if run.is_empty() or run["state"] != RUN_INSIDE:
		return {"ok": false, "reason": "not_inside"}
	var inc := get_incursion(run["incursion_id"])
	run["state"] = RUN_DISCONNECTED
	run["disconnected_at"] = clock
	var at_camp := current_stage_kind() == "camp"
	run["safe_camp"] = at_camp
	return {"ok": true, "protected_s": int(inc["disconnect_protection_s"]), "safe_camp": at_camp,
		"character_stays": true, "progress_saved": at_camp}


## Reconexión. `exposed` = estuvo dentro sin protección (fuera de campamento y pasada la protección).
func reconnect() -> Dictionary:
	if run.is_empty() or run["state"] != RUN_DISCONNECTED:
		return {"ok": false, "reason": "not_disconnected"}
	var inc := get_incursion(run["incursion_id"])
	var away := clock - float(run["disconnected_at"])
	var protected_s := float(inc["disconnect_protection_s"])
	var safe: bool = bool(run.get("safe_camp", false)) or (protected_s > 0.0 and away <= protected_s)
	run["state"] = RUN_INSIDE
	run["disconnected_at"] = -1.0
	return {"ok": true, "away_s": away, "protected": safe, "exposed": not safe, "stage": run["stage"]}


func tick(dt: float) -> void:
	clock += maxf(0.0, dt)
	if not bundle.is_empty() and clock > float(bundle["expires_at"]):
		_expire_bundle()


func _remove_carried(item_id: String) -> void:
	for i in carried.size():
		if carried[i]["id"] == item_id:
			carried.remove_at(i)
			return


# ==========================================================================
# Persistencia
# ==========================================================================
func to_dict() -> Dictionary:
	return {
		"selected": selected_id,
		"loadout": {"gold": gold, "durability": durability, "campfire_kits": campfire_kits, "flares": flares,
			"return_route": return_route, "consumables": consumables.duplicate(), "secure_capacity": secure_capacity,
			"secure_bag": secure_bag.duplicate(), "carried": carried.duplicate(true), "party": party.duplicate()},
		"run": run.duplicate(true),
		"bundle": bundle.duplicate(true),
		"clock": clock,
	}


func load_state(d: Dictionary) -> void:
	set_loadout(d.get("loadout", {}))
	run = (d.get("run", {}) as Dictionary).duplicate(true)
	bundle = (d.get("bundle", {}) as Dictionary).duplicate(true)
	clock = float(d.get("clock", 0.0))
	if not select(str(d.get("selected", ""))):
		selected_id = recommended_id


static func fmt(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "." + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out
