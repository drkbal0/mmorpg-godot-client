extends Node
## QuestService — diario de misiones del jugador (UI v2.4 Paso 9 · MMO-Misiones.html).
##
## Categorías: principal · secundaria · diaria · pionero. Las misiones de pionero NO
## viven en el seed: se derivan en vivo de `KnowledgeService` (contratos de inversión
## en estado «mission» y ofertas guardadas con «Déjame pensarlo»), así que el Códice y
## el diario de misiones nunca se contradicen.
##
## Estados: "available" (Disponibles) · "active" (Activas) · "completed" (Hechas).
## Rastreo: hasta `max_tracked` (3) misiones activas se reflejan en el rastreador del
## HUD (`bind_hud(hud)` → `hud.set_quests(get_hud_lines())`).
##
## Instanciable con `.new()` (tests) y registrado como autoload `QuestService`.

const DEFAULT_SEED_PATH := "res://config/quests/quests_seed.json"
const DEFAULT_MAX_TRACKED := 3
const STATES: Array[String] = ["active", "available", "completed"]
const PIONEER := "pionero"
const PIONEER_PREFIX := "pio_"

signal quests_changed
signal tracked_changed(ids: Array)
signal quest_completed(quest_id: String, rewards: Dictionary)
signal step_progressed(quest_id: String, step_index: int, progress: int, goal: int)

var max_tracked: int = DEFAULT_MAX_TRACKED
var categories: Array[Dictionary] = []
## Oro y PX concedidos al completar (el saldo real vive en la economía/CommerceService).
var gold_earned: int = 0
var xp_earned: int = 0

var _quests: Dictionary = {}       # id -> Dictionary (solo misiones del seed)
var _order: Array[String] = []
var _tracked: Array[String] = []
var _knowledge: Node = null
var _huds: Array = []


func _init() -> void:
	reset()


func _ready() -> void:
	if _quests.is_empty() and FileAccess.file_exists(DEFAULT_SEED_PATH):
		load_seed(DEFAULT_SEED_PATH)
	if _knowledge == null:
		var ks := get_node_or_null("/root/KnowledgeService")
		if ks:
			connect_knowledge(ks)


func reset() -> void:
	categories.clear()
	_quests.clear()
	_order.clear()
	_tracked.clear()
	gold_earned = 0
	xp_earned = 0
	max_tracked = DEFAULT_MAX_TRACKED


# ==========================================================================
# Datos
# ==========================================================================
func load_seed(path: String = DEFAULT_SEED_PATH) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var data = JSON.parse_string(f.get_as_text())
	if not (data is Dictionary):
		push_warning("[QuestService] Seed inválido: %s" % path)
		return false
	load_from_dict(data)
	return true


func load_from_dict(data: Dictionary) -> void:
	reset()
	max_tracked = int(data.get("max_tracked", DEFAULT_MAX_TRACKED))
	for c in data.get("categories", []):
		categories.append((c as Dictionary).duplicate(true))
	for q in data.get("quests", []):
		var d: Dictionary = (q as Dictionary).duplicate(true)
		d["state"] = str(d.get("state", "available"))
		var steps: Array = d.get("steps", [])
		for s in steps:
			s["goal"] = maxi(1, int(s.get("goal", 1)))
			s["progress"] = clampi(int(s.get("progress", 0)), 0, int(s["goal"]))
		d["steps"] = steps
		_quests[str(d["id"])] = d
		_order.append(str(d["id"]))
	for id in data.get("tracked", []):
		track(str(id))
	quests_changed.emit()


func to_dict() -> Dictionary:
	var qs: Array = []
	for id in _order:
		qs.append((_quests[id] as Dictionary).duplicate(true))
	return {"max_tracked": max_tracked, "categories": categories.duplicate(true), "quests": qs, "tracked": _tracked.duplicate()}


func category_info(cat_id: String) -> Dictionary:
	for c in categories:
		if c["id"] == cat_id:
			return c
	return {"id": cat_id, "label": cat_id.capitalize(), "color": "#9aa6ae"}


func category_color(cat_id: String) -> Color:
	return Color(str(category_info(cat_id).get("color", "#9aa6ae")))


# ==========================================================================
# Integración con KnowledgeService (misiones de pionero)
# ==========================================================================
func connect_knowledge(ks: Node) -> void:
	if ks == null or ks == _knowledge:
		return
	_knowledge = ks
	if ks.has_signal("investments_changed") and not ks.investments_changed.is_connected(_on_knowledge_changed):
		ks.investments_changed.connect(_on_knowledge_changed)
	quests_changed.emit()


func _on_knowledge_changed() -> void:
	# Un contrato que deja de existir no puede seguir rastreado.
	for id in _tracked.duplicate():
		if get_quest(id).is_empty() or get_quest(id)["state"] != "active":
			_tracked.erase(id)
			tracked_changed.emit(_tracked.duplicate())
			_push_huds()
	quests_changed.emit()


## Misiones derivadas de los contratos y ofertas del pionero.
func _pioneer_quests() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _knowledge == null:
		return out
	for inv in _knowledge.investments:
		var status := str(inv.get("status", ""))
		if status != "mission" and not inv.has("mission_steps"):
			continue
		var total := maxi(1, int(inv.get("mission_steps", 1)))
		var step := clampi(int(inv.get("mission_step", total if status != "mission" else 0)), 0, total)
		var labels: Array = []
		var mission: Dictionary = inv.get("mission", {})
		for s in mission.get("steps", []):
			labels.append(str((s as Dictionary).get("label", "")))
		var steps: Array = []
		for i in total:
			var label: String = labels[i] if i < labels.size() and labels[i] != "" else "Encargo %d del socio" % (i + 1)
			steps.append({"label": label, "goal": 1, "progress": 1 if i < step else 0})
		var nm := str(inv.get("name", inv.get("npc_id", "")))
		out.append({
			"id": PIONEER_PREFIX + str(inv["id"]), "category": PIONEER, "badge": "Pionero · Inversión",
			"title": str(mission.get("name", "Socio de %s" % nm)), "level": 0, "zone": str(inv.get("zone", "")),
			"group": 1, "state": "active" if status == "mission" else "completed", "est_min": 10,
			"story": "Descubriste %s antes que nadie. Completa la misión especial y el contrato empezará a pagar %s de cada venta a tu Refugio." % [nm, _pct(float(inv.get("share", 0.0)))],
			"steps": steps,
			"rewards": {"gold": 0, "xp": 0, "investment": nm, "share": float(inv.get("share", 0.0))},
			"target": {"zone": str(inv.get("zone", "")), "poi": str(inv.get("npc_id", "")), "map_pos": inv.get("map_pos", [])},
			"investment_id": str(inv["id"]),
		})
	for o in _knowledge.offers:
		var nm2 := str(o.get("name", o.get("shop_name", "")))
		var steps2: Array = []
		for i in maxi(1, int(o.get("mission_steps", 1))):
			steps2.append({"label": "Encargo %d del socio" % (i + 1), "goal": 1, "progress": 0})
		out.append({
			"id": PIONEER_PREFIX + str(o["id"]), "category": PIONEER, "badge": "Pionero · Oferta",
			"title": "Oferta: %s" % nm2, "level": 0, "zone": str(o.get("zone", "")), "group": 1,
			"state": "available", "est_min": 10,
			"story": "%s te ofrece ser socio (%s de cada venta). Tienes %d días para decidir; si no te interesa, pasará al siguiente descubridor." % [nm2, _pct(float(o.get("share", 0.0))), int(o.get("expires_in_days", 7))],
			"steps": steps2, "rewards": {"gold": 0, "xp": 0, "investment": nm2, "share": float(o.get("share", 0.0))},
			"target": {"zone": str(o.get("zone", "")), "poi": str(o.get("npc_id", "")), "map_pos": []},
			"offer_id": str(o["id"]), "expires_in_days": int(o.get("expires_in_days", 7)),
		})
	return out


static func _pct(share: float) -> String:
	var v := share * 100.0
	var s := ("%.1f" % v).trim_suffix(".0").replace(".", ",")
	return s + " %"


# ==========================================================================
# Consulta
# ==========================================================================
func _all() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in _order:
		out.append(_quests[id])
	out.append_array(_pioneer_quests())
	return out


## Vista de una misión (copia) con progreso calculado. {} si no existe.
func get_quest(id: String) -> Dictionary:
	if _quests.has(id):
		return _view(_quests[id])
	if id.begins_with(PIONEER_PREFIX):
		for q in _pioneer_quests():
			if q["id"] == id:
				return _view(q)
	return {}


func _view(q: Dictionary) -> Dictionary:
	var v := q.duplicate(true)
	var p := _progress_of(v)
	v["done_steps"] = p["done"]
	v["total_steps"] = p["total"]
	v["ratio"] = p["ratio"]
	v["tracked"] = _tracked.has(str(v["id"]))
	v["category_label"] = str(category_info(str(v["category"]))["label"])
	return v


## Filtro: `category` "" = todas; `state` "" = todos. Orden: recomendadas primero,
## luego el orden del seed (pionero al final).
func list_quests(category: String = "", state: String = "active") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var all := _all()
	for i in all.size():
		var q: Dictionary = all[i]
		if category != "" and q["category"] != category:
			continue
		if state != "" and q["state"] != state:
			continue
		var v := _view(q)
		v["_order"] = i
		out.append(v)
	var cat_rank := {}
	for i in categories.size():
		cat_rank[categories[i]["id"]] = i
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ra := int(cat_rank.get(a["category"], 99))
		var rb := int(cat_rank.get(b["category"], 99))
		if ra != rb:
			return ra < rb
		return int(a["_order"]) < int(b["_order"]))
	return out


func list_recommended() -> Array[Dictionary]:
	return list_quests("", "active").filter(func(q: Dictionary) -> bool: return bool(q.get("recommended", false)))


func count_by_state() -> Dictionary:
	var c := {"active": 0, "available": 0, "completed": 0}
	for q in _all():
		c[q["state"]] = int(c.get(q["state"], 0)) + 1
	return c


func count_by_category(state: String = "active") -> Dictionary:
	var c := {}
	for cat in categories:
		c[cat["id"]] = 0
	for q in _all():
		if state == "" or q["state"] == state:
			c[q["category"]] = int(c.get(q["category"], 0)) + 1
	return c


func _progress_of(q: Dictionary) -> Dictionary:
	var steps: Array = q.get("steps", [])
	var done := 0
	var sum := 0.0
	for s in steps:
		var g := maxi(1, int(s.get("goal", 1)))
		var p := clampi(int(s.get("progress", 0)), 0, g)
		if p >= g:
			done += 1
		sum += float(p) / float(g)
	var total := steps.size()
	return {"done": done, "total": total, "ratio": (sum / total) if total > 0 else 0.0}


## Texto de un paso: «3/5».
static func step_text(step: Dictionary) -> String:
	return "%d/%d" % [int(step.get("progress", 0)), int(step.get("goal", 1))]


## Primer paso sin completar (o el último si todo está hecho).
func current_step(id: String) -> Dictionary:
	var q := get_quest(id)
	if q.is_empty():
		return {}
	var steps: Array = q["steps"]
	for s in steps:
		if int(s["progress"]) < int(s["goal"]):
			return s
	return steps.back() if not steps.is_empty() else {}


# ==========================================================================
# Mutación
# ==========================================================================
func accept(id: String) -> Dictionary:
	if not _quests.has(id):
		return {"ok": false, "reason": "unknown_or_external"}
	var q: Dictionary = _quests[id]
	if q["state"] != "available":
		return {"ok": false, "reason": "not_available"}
	q["state"] = "active"
	quests_changed.emit()
	return {"ok": true}


## Avanza un paso. Al completar todos los pasos, la misión pasa a «completed»,
## entrega recompensas y sale del rastreador del HUD.
## Las de pionero delegan en `KnowledgeService.advance_offer_mission`.
func advance_step(id: String, step_index: int = -1, amount: int = 1) -> Dictionary:
	if id.begins_with(PIONEER_PREFIX) and not _quests.has(id):
		return _advance_pioneer(id)
	if not _quests.has(id):
		return {"ok": false, "reason": "unknown_quest"}
	var q: Dictionary = _quests[id]
	if q["state"] != "active":
		return {"ok": false, "reason": "not_active"}
	var steps: Array = q["steps"]
	if step_index < 0:
		for i in steps.size():
			if int(steps[i]["progress"]) < int(steps[i]["goal"]):
				step_index = i
				break
	if step_index < 0 or step_index >= steps.size():
		return {"ok": false, "reason": "invalid_step"}
	var s: Dictionary = steps[step_index]
	s["progress"] = clampi(int(s["progress"]) + amount, 0, int(s["goal"]))
	step_progressed.emit(id, step_index, int(s["progress"]), int(s["goal"]))
	var completed := int(_progress_of(q)["done"]) == steps.size()
	if completed:
		_complete(q)
	quests_changed.emit()
	_push_huds()
	return {"ok": true, "progress": int(s["progress"]), "goal": int(s["goal"]), "completed": completed}


func _advance_pioneer(id: String) -> Dictionary:
	var q := get_quest(id)
	if q.is_empty() or _knowledge == null or not q.has("investment_id"):
		return {"ok": false, "reason": "not_in_mission"}
	var r: Dictionary = _knowledge.advance_offer_mission(str(q["investment_id"]))
	if r.get("ok", false) and r.get("completed", false):
		_tracked.erase(id)
		tracked_changed.emit(_tracked.duplicate())
		quest_completed.emit(id, q["rewards"])
	_push_huds()
	return r


func _complete(q: Dictionary) -> void:
	q["state"] = "completed"
	var rw: Dictionary = q.get("rewards", {})
	gold_earned += int(rw.get("gold", 0))
	xp_earned += int(rw.get("xp", 0))
	if _tracked.has(str(q["id"])):
		_tracked.erase(str(q["id"]))
		tracked_changed.emit(_tracked.duplicate())
	quest_completed.emit(str(q["id"]), rw.duplicate(true))


func abandon(id: String) -> Dictionary:
	if not _quests.has(id):
		return {"ok": false, "reason": "unknown_or_external"}
	var q: Dictionary = _quests[id]
	if q["state"] != "active":
		return {"ok": false, "reason": "not_active"}
	q["state"] = "available"
	for s in q["steps"]:
		s["progress"] = 0
	untrack(id)
	quests_changed.emit()
	return {"ok": true}


# ==========================================================================
# Rastreo en el HUD (máx. 3)
# ==========================================================================
func get_tracked() -> Array[String]:
	return _tracked.duplicate()


func is_tracked(id: String) -> bool:
	return _tracked.has(id)


func track(id: String) -> Dictionary:
	var q := get_quest(id)
	if q.is_empty():
		return {"ok": false, "reason": "unknown_quest"}
	if q["state"] != "active":
		return {"ok": false, "reason": "not_active"}
	if _tracked.has(id):
		return {"ok": true, "already": true}
	if _tracked.size() >= max_tracked:
		return {"ok": false, "reason": "max_tracked", "max": max_tracked}
	_tracked.append(id)
	tracked_changed.emit(_tracked.duplicate())
	_push_huds()
	return {"ok": true}


func untrack(id: String) -> bool:
	if not _tracked.has(id):
		return false
	_tracked.erase(id)
	tracked_changed.emit(_tracked.duplicate())
	_push_huds()
	return true


func toggle_track(id: String) -> Dictionary:
	if _tracked.has(id):
		untrack(id)
		return {"ok": true, "tracked": false}
	var r := track(id)
	r["tracked"] = r.get("ok", false)
	return r


## Líneas del rastreador del HUD: «Título · 3/5 Cristales de Vacío».
func get_hud_lines() -> Array[String]:
	var out: Array[String] = []
	for id in _tracked:
		var q := get_quest(id)
		if q.is_empty():
			continue
		var s := current_step(id)
		var line := str(q["title"])
		if not s.is_empty():
			if int(s["goal"]) > 1:
				line += " · %s %s" % [step_text(s), s["label"]]
			else:
				line += " · " + str(s["label"])
		out.append(line)
	return out


## Conecta un HUD (`set_quests(Array)`) al rastreador. Se actualiza solo.
func bind_hud(hud: Object) -> void:
	if hud == null or not hud.has_method("set_quests"):
		return
	if not _huds.has(hud):
		_huds.append(hud)
	hud.set_quests(get_hud_lines())


func _push_huds() -> void:
	var lines := get_hud_lines()
	for h in _huds.duplicate():
		if is_instance_valid(h):
			h.set_quests(lines)
		else:
			_huds.erase(h)


# ==========================================================================
# Mapa / ruta de sesión
# ==========================================================================
## Destino de la misión en coordenadas del mapa del mundo (Vector2) o null.
func get_map_target(id: String) -> Dictionary:
	var q := get_quest(id)
	if q.is_empty():
		return {}
	var t: Dictionary = q.get("target", {})
	var mp: Array = t.get("map_pos", [])
	var out := {"quest_id": id, "zone": str(t.get("zone", "")), "poi": str(t.get("poi", "")), "title": str(q["title"])}
	if mp.size() >= 2:
		out["focus"] = Vector2(float(mp[0]), float(mp[1]))
	return out


## Planificador de sesión con las misiones rastreadas: tiempo y PX totales.
func plan_session() -> Dictionary:
	var minutes := 0
	var xp := 0
	var steps: Array = []
	for id in _tracked:
		var q := get_quest(id)
		if q.is_empty():
			continue
		minutes += int(q.get("est_min", 0))
		xp += int((q.get("rewards", {}) as Dictionary).get("xp", 0))
		steps.append({"id": id, "title": q["title"], "zone": q["zone"], "est_min": int(q.get("est_min", 0))})
	var per_hour := int(round(float(xp) * 60.0 / float(minutes))) if minutes > 0 else 0
	return {"steps": steps, "minutes": minutes, "xp": xp, "xp_per_hour": per_hour}
