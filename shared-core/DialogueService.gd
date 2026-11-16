extends Node
## Diálogo cinematográfico con PNJ — UI v2.4 Paso 13 (design_ref/pantallas_html/MMO-Dialogo.html,
## PROMPT_ANTIGRAVITY.md §3 «Diálogo con PNJ»).
##
## Autoload `DialogueService` o instanciable con `.new()` + `load_seed()`.
## Seed: res://config/dialogue/dialogue_seed.json
##
## Cada PNJ tiene un árbol de nodos. Un nodo tiene texto (uno o varios fragmentos narrativos que
## se revelan con Espacio) y hasta 4 opciones numeradas [1]–[4]. Tipos de opción:
## - quest    · acepta o entrega una misión (badge verde «Acepta misión · Hoja de la grieta ▲»).
## - branch   · rama alternativa con impacto en reputación (badge dorado).
## - lore     · pregunta de historia: al consultarla queda registrada y se atenúa a opacidad 0.5
##              con la nota «Ya lo preguntaste» (se puede volver a preguntar).
## - shop     · abre la tienda / suministros del PNJ o enlaza con el Mercado.
## - continue · avanzar / despedirse (sin badge).
##
## Relación con el PNJ: puntos 0–500 → Desconocido · Neutral · Amistoso · Aliado · Reverenciado,
## mostrada con 5 marcas (una cada 100 puntos). Historial de líneas y persistencia en `to_dict`.

signal dialogue_started(npc_id: String, node_id: String)
signal node_changed(npc_id: String, node_id: String)
signal fragment_advanced(index: int, total: int)
signal option_chosen(npc_id: String, option_id: String, result: Dictionary)
signal relation_changed(npc_id: String, points: int, level_id: String)
signal reputation_changed(faction_id: String, value: int)
signal quest_requested(quest_id: String, action: String)
signal shop_requested(npc_id: String, shop: Dictionary)
signal dialogue_ended(npc_id: String)
signal history_changed

const DEFAULT_SEED_PATH := "res://config/dialogue/dialogue_seed.json"
const DEFAULT_SAVE_PATH := "user://dialogue_state.json"

const MAX_OPTIONS := 4
const RELATION_TICKS := 5
const OPTION_TYPES: Array[String] = ["quest", "branch", "lore", "shop", "continue"]
const ASKED_NOTE := "Ya lo preguntaste"
const ASKED_OPACITY := 0.5
const HISTORY_LIMIT := 200

## Color del badge e icono por tipo (MMO-Dialogo.html).
const TYPE_STYLES := {
	"quest": {"badge": "#4fe39a", "icon_bg": "#8a6a2b", "icon": "M12 3l7 7-7 11-7-11z"},
	"branch": {"badge": "#f5c35b", "icon_bg": "#2b4a8a", "icon": "M12 8v.01M12 11v6M12 3a9 9 0 1 0 0 18a9 9 0 1 0 0-18"},
	"lore": {"badge": "#9aa6ae", "icon_bg": "#2b4a8a", "icon": "M12 8v.01M12 11v6M12 3a9 9 0 1 0 0 18a9 9 0 1 0 0-18"},
	"shop": {"badge": "#9aa6ae", "icon_bg": "#2a7a4a", "icon": "M6 8h12l-1 12H7zM9 8a3 3 0 0 1 6 0"},
	"continue": {"badge": "#9aa6ae", "icon_bg": "#3a4a54", "icon": "M9 6l6 6-6 6"},
}
const ASKED_COLOR := "#7c8992"
const LOCKED_COLOR := "#ff8a8a"

const DEFAULT_LEVELS: Array = [
	{"id": "unknown", "name": "Desconocido", "name_f": "Desconocida", "min": 0},
	{"id": "neutral", "name": "Neutral", "name_f": "Neutral", "min": 100},
	{"id": "friendly", "name": "Amistoso", "name_f": "Amistosa", "min": 200},
	{"id": "ally", "name": "Aliado", "name_f": "Aliada", "min": 300},
	{"id": "revered", "name": "Reverenciado", "name_f": "Reverenciada", "min": 400},
]

var relation_levels: Array = []
var relation_max: int = 500
var npcs: Dictionary = {}            # npc_id -> {id, name, title, gender, start, nodes}
var relations: Dictionary = {}       # npc_id -> puntos
var factions: Dictionary = {}        # faction_id -> {name, value}
var asked: Dictionary = {}           # npc_id -> Array[String] temas consultados
var visited: Dictionary = {}         # npc_id -> Array[String] nodos visitados
var accepted_quests: Array[String] = []
var history: Array[Dictionary] = []  # [{npc_id, speaker, text, kind}]

## Conversación activa.
var active_npc: String = ""
var active_node: String = ""
var fragment_index: int = 0
var last_result: Dictionary = {}

## Servicio de misiones opcional (QuestService) para aceptar/entregar de verdad.
var quest_service: Node = null


func _ready() -> void:
	if npcs.is_empty() and FileAccess.file_exists(DEFAULT_SEED_PATH):
		load_seed(DEFAULT_SEED_PATH)
	if quest_service == null:
		quest_service = get_node_or_null("/root/QuestService")


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
	relation_levels = (data.get("relation_levels", DEFAULT_LEVELS) as Array).duplicate(true)
	if relation_levels.is_empty():
		relation_levels = DEFAULT_LEVELS.duplicate(true)
	relation_levels.sort_custom(func(a, b): return int(a.get("min", 0)) < int(b.get("min", 0)))
	relation_max = maxi(1, int(data.get("relation_max", 500)))
	npcs.clear()
	relations.clear()
	factions.clear()
	asked.clear()
	visited.clear()
	accepted_quests.clear()
	history.clear()
	for fid in (data.get("factions", {}) as Dictionary):
		var f: Dictionary = data["factions"][fid]
		factions[str(fid)] = {"name": str(f.get("name", fid)), "value": int(f.get("value", 0))}
	for raw in data.get("npcs", []):
		register_npc(raw)
	var st: Dictionary = data.get("state", {})
	for nid in (st.get("asked", {}) as Dictionary):
		for t in st["asked"][nid]:
			_add_unique(asked, str(nid), str(t))
	for nid in (st.get("visited", {}) as Dictionary):
		for n in st["visited"][nid]:
			_add_unique(visited, str(nid), str(n))
	active_npc = ""
	active_node = ""
	fragment_index = 0
	last_result = {}


func register_npc(raw: Dictionary) -> void:
	var id := str(raw.get("id", ""))
	if id == "":
		return
	var nodes := {}
	var raw_nodes: Dictionary = raw.get("nodes", {})
	for node_id in raw_nodes:
		nodes[str(node_id)] = _normalize_node(raw_nodes[node_id])
	var start := str(raw.get("start", "intro"))
	if not nodes.has(start) and not nodes.is_empty():
		start = nodes.keys()[0]
	npcs[id] = {
		"id": id,
		"name": str(raw.get("name", id)),
		"title": str(raw.get("title", "")),
		"gender": str(raw.get("gender", "m")),
		"portrait": str(raw.get("portrait", "silhouette")),
		"start": start,
		"nodes": nodes,
	}
	relations[id] = clampi(int(raw.get("relation", 0)), 0, relation_max)


func _normalize_node(raw: Dictionary) -> Dictionary:
	var fragments: Array[String] = []
	var t = raw.get("text", "")
	if t is Array:
		for f in t:
			if str(f) != "":
				fragments.append(str(f))
	elif str(t) != "":
		fragments.append(str(t))
	var options: Array[Dictionary] = []
	for o in raw.get("options", []):
		if options.size() >= MAX_OPTIONS:
			break
		var opt: Dictionary = (o as Dictionary).duplicate(true)
		opt["id"] = str(o.get("id", "opt_%d" % options.size()))
		var ty := str(o.get("type", "continue"))
		opt["type"] = ty if ty in OPTION_TYPES else "continue"
		opt["text"] = str(o.get("text", ""))
		opt["next"] = str(o.get("next", "")) if o.get("next") != null else ""
		opt["badge"] = str(o.get("badge", ""))
		opt["topic"] = str(o.get("topic", opt["next"] if opt["type"] == "lore" else ""))
		opt["relation"] = int(o.get("relation", 0))
		opt["reputation"] = (o.get("reputation", {}) as Dictionary).duplicate()
		opt["shop"] = (o.get("shop", {}) as Dictionary).duplicate()
		opt["requires_relation"] = str(o.get("requires_relation", ""))
		options.append(opt)
	return {"fragments": fragments, "options": options}


func _add_unique(d: Dictionary, key: String, value: String) -> bool:
	if not d.has(key):
		d[key] = []
	if (d[key] as Array).has(value):
		return false
	d[key].append(value)
	return true


# ==========================================================================
# PNJ y relación
# ==========================================================================
func get_npc(npc_id: String) -> Dictionary:
	return npcs.get(npc_id, {})


func has_node_id(npc_id: String, node_id: String) -> bool:
	return (get_npc(npc_id).get("nodes", {}) as Dictionary).has(node_id)


func get_node_data(npc_id: String, node_id: String) -> Dictionary:
	return (get_npc(npc_id).get("nodes", {}) as Dictionary).get(node_id, {})


func get_relation(npc_id: String) -> int:
	return int(relations.get(npc_id, 0))


func relation_level_index(points: int) -> int:
	var idx := 0
	for i in relation_levels.size():
		if points >= int(relation_levels[i].get("min", 0)):
			idx = i
	return idx


func relation_level(npc_id: String) -> Dictionary:
	return relation_levels[relation_level_index(get_relation(npc_id))]


func relation_level_id(npc_id: String) -> String:
	return str(relation_level(npc_id).get("id", ""))


## Nombre del nivel concordado con el género del PNJ («Aliada» para Mira).
func relation_name(npc_id: String) -> String:
	var lvl := relation_level(npc_id)
	if str(get_npc(npc_id).get("gender", "m")) == "f":
		return str(lvl.get("name_f", lvl.get("name", "")))
	return str(lvl.get("name", ""))


## Marcas encendidas de las 5 del medidor: una cada (max / 5) puntos.
func relation_ticks(npc_id: String) -> int:
	var step := float(relation_max) / RELATION_TICKS
	return clampi(int(floor(get_relation(npc_id) / step)), 0, RELATION_TICKS)


func change_relation(npc_id: String, delta: int) -> int:
	if not npcs.has(npc_id) or delta == 0:
		return get_relation(npc_id)
	var before := relation_level_id(npc_id)
	relations[npc_id] = clampi(get_relation(npc_id) + delta, 0, relation_max)
	relation_changed.emit(npc_id, relations[npc_id], relation_level_id(npc_id))
	if before != relation_level_id(npc_id):
		_log(npc_id, "", "Relación con %s: %s" % [get_npc(npc_id)["name"], relation_name(npc_id)], "system")
	return relations[npc_id]


func level_meets(npc_id: String, level_id: String) -> bool:
	if level_id == "":
		return true
	for i in relation_levels.size():
		if str(relation_levels[i]["id"]) == level_id:
			return relation_level_index(get_relation(npc_id)) >= i
	return true


func get_reputation(faction_id: String) -> int:
	return int((factions.get(faction_id, {}) as Dictionary).get("value", 0))


func change_reputation(faction_id: String, delta: int) -> int:
	if not factions.has(faction_id):
		factions[faction_id] = {"name": faction_id.capitalize(), "value": 0}
	factions[faction_id]["value"] = int(factions[faction_id]["value"]) + delta
	reputation_changed.emit(faction_id, factions[faction_id]["value"])
	return factions[faction_id]["value"]


# ==========================================================================
# Conversación
# ==========================================================================
func is_active() -> bool:
	return active_npc != ""


func start(npc_id: String, node_id: String = "") -> bool:
	if not npcs.has(npc_id):
		return false
	var nid := node_id if node_id != "" else str(npcs[npc_id]["start"])
	if not has_node_id(npc_id, nid):
		nid = str(npcs[npc_id]["start"])
	active_npc = npc_id
	last_result = {}
	if relation_level_id(npc_id) == "unknown" and get_relation(npc_id) == 0:
		change_relation(npc_id, int(relation_levels[1].get("min", 100)) if relation_levels.size() > 1 else 0)
	dialogue_started.emit(npc_id, nid)
	_enter(nid)
	return true


func _enter(node_id: String) -> void:
	active_node = node_id
	fragment_index = 0
	_add_unique(visited, active_npc, node_id)
	var frags := current_fragments()
	if not frags.is_empty():
		_log(active_npc, str(get_npc(active_npc)["name"]), frags[0], "npc")
	node_changed.emit(active_npc, node_id)


func current_node() -> Dictionary:
	return get_node_data(active_npc, active_node)


func current_fragments() -> Array:
	return current_node().get("fragments", [])


func fragment_count() -> int:
	return current_fragments().size()


func has_more_fragments() -> bool:
	return fragment_index < fragment_count() - 1


## Texto visible: fragmentos ya revelados unidos por un espacio.
func current_text() -> String:
	var frags := current_fragments()
	var shown: Array = frags.slice(0, mini(fragment_index + 1, frags.size()))
	return " ".join(PackedStringArray(shown))


func full_text() -> String:
	return " ".join(PackedStringArray(current_fragments()))


## Revela el siguiente fragmento. Devuelve false si ya estaba todo visible.
func advance_fragment() -> bool:
	if not has_more_fragments():
		return false
	fragment_index += 1
	_log(active_npc, str(get_npc(active_npc)["name"]), current_fragments()[fragment_index], "npc")
	fragment_advanced.emit(fragment_index, fragment_count())
	return true


func reveal_all() -> void:
	while advance_fragment():
		pass


## Opciones del nodo actual decoradas para la vista: key, asked, opacity, badge, colores, locked.
func current_options() -> Array[Dictionary]:
	return options_for(active_npc, active_node)


func options_for(npc_id: String, node_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var i := 0
	for o in get_node_data(npc_id, node_id).get("options", []):
		i += 1
		out.append(_decorate(npc_id, o, i))
	return out


func _decorate(npc_id: String, o: Dictionary, index: int) -> Dictionary:
	var v := o.duplicate(true)
	var ty: String = o["type"]
	var style: Dictionary = TYPE_STYLES.get(ty, TYPE_STYLES["continue"])
	v["index"] = index
	v["key"] = str(index)
	v["icon"] = style["icon"]
	v["icon_bg"] = style["icon_bg"]
	v["badge_color"] = style["badge"]
	v["asked"] = ty == "lore" and is_asked(npc_id, str(o["topic"]))
	v["locked"] = not level_meets(npc_id, str(o.get("requires_relation", "")))
	v["opacity"] = ASKED_OPACITY if (v["asked"] or v["locked"]) else 1.0
	if v["locked"]:
		var need := str(o["requires_relation"])
		var nm := need
		for l in relation_levels:
			if str(l["id"]) == need:
				nm = str(l["name_f"] if str(get_npc(npc_id).get("gender", "m")) == "f" else l["name"])
		v["badge"] = "Requiere relación: %s" % nm
		v["badge_color"] = LOCKED_COLOR
	elif v["asked"]:
		v["badge"] = ASKED_NOTE
		v["badge_color"] = ASKED_COLOR
	elif ty == "quest" and str(v["badge"]) == "":
		v["badge"] = quest_badge(o)
	elif ty == "shop" and str(v["badge"]) == "":
		v["badge"] = "Mercado" if bool((o.get("shop", {}) as Dictionary).get("market", false)) else "Tienda"
	return v


static func quest_badge(o: Dictionary) -> String:
	var verb := "Entrega misión" if str(o.get("quest_action", "accept")) == "turn_in" else "Acepta misión"
	var reward := str(o.get("reward", ""))
	return "%s · %s ▲" % [verb, reward] if reward != "" else verb


func is_asked(npc_id: String, topic: String) -> bool:
	return topic != "" and (asked.get(npc_id, []) as Array).has(topic)


func is_visited(npc_id: String, node_id: String) -> bool:
	return (visited.get(npc_id, []) as Array).has(node_id)


func get_option(option_id_or_index) -> Dictionary:
	var opts := current_options()
	if typeof(option_id_or_index) == TYPE_INT:
		var i: int = option_id_or_index
		return opts[i - 1] if i >= 1 and i <= opts.size() else {}
	for o in opts:
		if o["id"] == str(option_id_or_index):
			return o
	return {}


## Elige una opción por id o por número (1–4). Aplica relación, reputación, misión o tienda
## y avanza al nodo siguiente (o termina la conversación si `next` está vacío).
func choose(option_id_or_index) -> Dictionary:
	if not is_active():
		return {"ok": false, "reason": "not_active"}
	var o := get_option(option_id_or_index)
	if o.is_empty():
		return {"ok": false, "reason": "invalid_option"}
	if o["locked"]:
		return {"ok": false, "reason": "relation_too_low", "option_id": o["id"]}
	var npc := active_npc
	var result := {"ok": true, "option_id": o["id"], "type": o["type"], "next": o["next"], "ended": false}
	reveal_all()
	_log(npc, "Tú", str(o["text"]), "player")
	match str(o["type"]):
		"quest":
			var qid := str(o.get("quest_id", ""))
			var action := str(o.get("quest_action", "accept"))
			result["quest_id"] = qid
			result["quest_action"] = action
			result["reward"] = str(o.get("reward", ""))
			if action == "accept" and qid != "" and not accepted_quests.has(qid):
				accepted_quests.append(qid)
			if quest_service and qid != "":
				if action == "accept" and quest_service.has_method("accept"):
					result["quest_service"] = quest_service.accept(qid)
			quest_requested.emit(qid, action)
		"branch":
			result["reputation"] = {}
			for fid in (o["reputation"] as Dictionary):
				result["reputation"][fid] = change_reputation(str(fid), int(o["reputation"][fid]))
		"lore":
			result["first_time"] = _add_unique(asked, npc, str(o["topic"]))
		"shop":
			result["shop"] = (o["shop"] as Dictionary).duplicate()
			shop_requested.emit(npc, result["shop"])
	if int(o["relation"]) != 0:
		result["relation"] = change_relation(npc, int(o["relation"]))
	last_result = result
	option_chosen.emit(npc, str(o["id"]), result)
	var next := str(o["next"])
	if str(o["type"]) == "shop" and next == "":
		end_dialogue()
		result["ended"] = true
	elif next == "" or not has_node_id(npc, next):
		end_dialogue()
		result["ended"] = true
	else:
		_enter(next)
	return result


## Espacio: revela el siguiente fragmento; si ya está todo y el nodo no tiene opciones
## (o solo una de tipo «continue»), avanza con ella; si no hay a dónde ir, cierra.
func advance() -> Dictionary:
	if not is_active():
		return {"ok": false, "reason": "not_active"}
	if advance_fragment():
		return {"ok": true, "action": "fragment", "index": fragment_index}
	var opts := current_options()
	if opts.is_empty():
		end_dialogue()
		return {"ok": true, "action": "closed"}
	if opts.size() == 1 and opts[0]["type"] == "continue":
		var r := choose(1)
		r["action"] = "continue"
		return r
	return {"ok": false, "reason": "choice_required"}


func end_dialogue() -> void:
	if not is_active():
		return
	var npc := active_npc
	active_npc = ""
	active_node = ""
	fragment_index = 0
	dialogue_ended.emit(npc)


# ==========================================================================
# Historial y persistencia
# ==========================================================================
func _log(npc_id: String, speaker: String, text: String, kind: String) -> void:
	history.append({"npc_id": npc_id, "speaker": speaker, "text": text, "kind": kind})
	while history.size() > HISTORY_LIMIT:
		history.pop_front()
	history_changed.emit()


func history_for(npc_id: String = "") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for h in history:
		if npc_id == "" or h["npc_id"] == npc_id:
			out.append(h)
	return out


func to_dict() -> Dictionary:
	var fac := {}
	for fid in factions:
		fac[fid] = int(factions[fid]["value"])
	return {
		"relations": relations.duplicate(),
		"reputation": fac,
		"asked": asked.duplicate(true),
		"visited": visited.duplicate(true),
		"accepted_quests": accepted_quests.duplicate(),
		"history": history.duplicate(true),
	}


func from_dict(d: Dictionary) -> void:
	for nid in (d.get("relations", {}) as Dictionary):
		if npcs.has(str(nid)):
			relations[str(nid)] = clampi(int(d["relations"][nid]), 0, relation_max)
	for fid in (d.get("reputation", {}) as Dictionary):
		if not factions.has(str(fid)):
			factions[str(fid)] = {"name": str(fid).capitalize(), "value": 0}
		factions[str(fid)]["value"] = int(d["reputation"][fid])
	asked.clear()
	for nid in (d.get("asked", {}) as Dictionary):
		for t in d["asked"][nid]:
			_add_unique(asked, str(nid), str(t))
	visited.clear()
	for nid in (d.get("visited", {}) as Dictionary):
		for n in d["visited"][nid]:
			_add_unique(visited, str(nid), str(n))
	accepted_quests.clear()
	for q in d.get("accepted_quests", []):
		accepted_quests.append(str(q))
	history.clear()
	for h in d.get("history", []):
		history.append((h as Dictionary).duplicate())
	history_changed.emit()


func save_state(path: String = DEFAULT_SAVE_PATH) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(to_dict()))
	f.close()
	return true


func load_state(path: String = DEFAULT_SAVE_PATH) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY:
		return false
	from_dict(data)
	return true
