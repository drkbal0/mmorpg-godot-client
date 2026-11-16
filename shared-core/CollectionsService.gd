extends Node
## Colecciones y Diario del multiverso — UI v2.4 Paso 12 (design_ref/pantallas_html/MMO-Colecciones.html).
##
## Autoload `CollectionsService` o instanciable con `.new()` + `load_seed()`.
## Seed: res://config/collections/collections_seed.json
##
## - Categorías canónicas: Monturas · Mascotas · Apariencias · Logros · Títulos, con contador
##   «desbloqueadas / total» (23/96, 41/150, 212/900, 318/1.240, 12/80). El seed solo lista una
##   parte del catálogo: el contador suma lo que el jugador tiene fuera de la lista (base) y lo
##   que se desbloquea dentro de ella.
## - Estados: `unlocked` (lo tienes), `locked` (por conseguir, con progreso opcional) y `hidden`
##   («Por descubrir»: nombre, rareza y procedencia ocultos hasta que lo encuentras).
## - Diario del multiverso: exploración y secretos por universo (Verdalia 64 % · 41 secretos…).
##   Vinculado a `KnowledgeService`: cada entrada conocida del Códice con `universe` suma un
##   punto de exploración y, si es un secreto propio, un secreto más.
## - Acciones: invocar montura, elegir mascota, equipar apariencia (por ranura) y título visible.

signal collection_changed(category: String)
signal item_unlocked(item_id: String)
signal progress_changed(item_id: String, current: int, target: int)
signal active_changed(kind: String, item_id: String)
signal journal_changed
signal event_reminder_set(event_id: String)

const DEFAULT_SEED_PATH := "res://config/collections/collections_seed.json"

const CATEGORY_IDS: Array[String] = ["mounts", "pets", "transmogs", "achievements", "titles"]
const STATES: Array[String] = ["unlocked", "locked", "hidden"]
const HIDDEN_NAME := "Por descubrir"

## Filtros de estado de la cuadrícula.
const STATE_FILTERS: Array[Dictionary] = [
	{"id": "all", "label": "Todas"},
	{"id": "unlocked", "label": "Desbloqueadas"},
	{"id": "missing", "label": "Por conseguir"},
]
## Órdenes de la cuadrícula («Ordenar: …»).
const SORTS: Array[Dictionary] = [
	{"id": "near", "label": "más cerca de conseguir"},
	{"id": "catalog", "label": "catálogo"},
	{"id": "rarity", "label": "rareza"},
	{"id": "name", "label": "nombre"},
]

const RARITIES := {
	"common": {"name": "Común", "color": "#9aa6ae", "bg": "#121a20"},
	"uncommon": {"name": "Poco común", "color": "#7bd88f", "bg": "#14241b"},
	"rare": {"name": "Rara", "color": "#5aa9ff", "bg": "#13203a"},
	"epic": {"name": "Épica", "color": "#cfa8ff", "bg": "#2a1d3a"},
	"legendary": {"name": "Legendaria", "color": "#ffb547", "bg": "#33240f"},
}
const RARITY_ORDER: Array[String] = ["common", "uncommon", "rare", "epic", "legendary"]

## Procedencia (método de obtención) -> etiqueta.
const SOURCE_LABELS := {
	"world": "Mundo", "quest": "Misión", "achievement": "Logro", "reputation": "Reputación",
	"raid": "Raid", "dungeon": "Mazmorra", "event": "Evento", "crafting": "Fabricación",
	"vendor": "Mercader", "pvp": "JcJ", "shelter": "Refugio", "incursion": "Incursión",
	"secret": "Secreto",
}

## Ranuras de apariencia.
const TRANSMOG_SLOTS := {
	"head": "Cabeza", "chest": "Torso", "back": "Espalda", "weapon": "Arma", "feet": "Pies",
}

var categories: Array[Dictionary] = []
var universes: Array[Dictionary] = []
var items: Dictionary = {}          # id -> Dictionary
var item_order: Array[String] = []  # orden del catálogo

var active_mount: String = ""
var mount_summoned: bool = false
var active_pet: String = ""
var active_title: String = ""
var active_transmog: Dictionary = {}   # slot -> item_id
var event_reminders: Array[String] = []

## Códice vinculado (KnowledgeService). Opcional.
var knowledge: Node = null
var player_name: String = "Tú"

var _base_unlocked: Dictionary = {}    # category -> dueños fuera de la lista del seed


func _ready() -> void:
	if items.is_empty() and FileAccess.file_exists(DEFAULT_SEED_PATH):
		load_seed(DEFAULT_SEED_PATH)
	if knowledge == null:
		var k := get_node_or_null("/root/KnowledgeService")
		if k:
			link_knowledge(k)


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
	categories.clear()
	universes.clear()
	items.clear()
	item_order.clear()
	_base_unlocked.clear()
	event_reminders.clear()
	for c in data.get("categories", []):
		categories.append({
			"id": str(c.get("id", "")),
			"name": str(c.get("name", c.get("id", ""))),
			"singular": str(c.get("singular", "")),
			"unlocked": int(c.get("unlocked", 0)),
			"total": int(c.get("total", 0)),
			"action": str(c.get("action", "none")),
		})
	for u in data.get("universes", []):
		universes.append({
			"id": str(u.get("id", "")),
			"name": str(u.get("name", u.get("id", ""))),
			"color": str(u.get("color", "#46e3c1")),
			"explored": int(u.get("explored", 0)),
			"total": maxi(1, int(u.get("total", 100))),
			"secrets": int(u.get("secrets", 0)),
		})
	for raw in data.get("items", []):
		register_item(raw)
	# Base: lo que el jugador tiene fuera de la lista (para cuadrar el contador del seed).
	for c in categories:
		var listed := _listed_unlocked(c["id"])
		_base_unlocked[c["id"]] = maxi(0, int(c["unlocked"]) - listed)
	var act: Dictionary = data.get("active", {})
	active_mount = ""
	mount_summoned = false
	active_pet = ""
	active_title = ""
	active_transmog = {}
	if is_unlocked(str(act.get("mount", ""))):
		active_mount = str(act["mount"])
	if is_unlocked(str(act.get("pet", ""))):
		active_pet = str(act["pet"])
	if is_unlocked(str(act.get("title", ""))):
		active_title = str(act["title"])
	var tm: Dictionary = act.get("transmog", {})
	for slot in tm:
		if is_unlocked(str(tm[slot])):
			active_transmog[str(slot)] = str(tm[slot])


func register_item(raw: Dictionary) -> void:
	var id := str(raw.get("id", ""))
	if id == "":
		return
	var it := raw.duplicate(true)
	it["id"] = id
	it["category"] = str(raw.get("category", "mounts"))
	it["name"] = str(raw.get("name", id))
	var rarity := str(raw.get("rarity", "common"))
	it["rarity"] = rarity if RARITIES.has(rarity) else "common"
	var st := str(raw.get("state", "locked"))
	it["state"] = st if st in STATES else "locked"
	it["progress"] = int(raw.get("progress", 0))
	it["target"] = int(raw.get("target", 0))
	it["description"] = str(raw.get("description", ""))
	it["requirement"] = str(raw.get("requirement", ""))
	it["universe"] = str(raw.get("universe", ""))
	it["source"] = (raw.get("source", {}) as Dictionary).duplicate(true)
	it["cta"] = (raw.get("cta", {}) as Dictionary).duplicate(true)
	if not items.has(id):
		item_order.append(id)
	items[id] = it


func _listed_unlocked(category: String) -> int:
	var n := 0
	for id in item_order:
		if items[id]["category"] == category and items[id]["state"] == "unlocked":
			n += 1
	return n


# ==========================================================================
# Consulta
# ==========================================================================
func get_category(category: String) -> Dictionary:
	for c in categories:
		if c["id"] == category:
			return c
	return {}


func category_name(category: String) -> String:
	return str(get_category(category).get("name", category))


func has_category(category: String) -> bool:
	return not get_category(category).is_empty()


func get_item(id: String) -> Dictionary:
	return items.get(id, {})


func has_item(id: String) -> bool:
	return items.has(id)


func is_unlocked(id: String) -> bool:
	return items.has(id) and items[id]["state"] == "unlocked"


func is_hidden(id: String) -> bool:
	return items.has(id) and items[id]["state"] == "hidden"


## Desbloqueadas del jugador en la categoría (incluye las que no están en la lista).
func unlocked_count(category: String) -> int:
	return int(_base_unlocked.get(category, 0)) + _listed_unlocked(category)


func total_count(category: String) -> int:
	return int(get_category(category).get("total", 0))


## «23/96» (con separador de miles: «318/1.240»).
func counter_text(category: String) -> String:
	return "%s/%s" % [fmt(unlocked_count(category)), fmt(total_count(category))]


## «23 de 96» (cabecera de la cuadrícula).
func counter_long_text(category: String) -> String:
	return "%s de %s" % [fmt(unlocked_count(category)), fmt(total_count(category))]


func completion_ratio(category: String) -> float:
	var t := total_count(category)
	return 0.0 if t <= 0 else float(unlocked_count(category)) / float(t)


## Progreso 0..1 de un objeto por conseguir (1.0 si ya es tuyo).
func progress_ratio(id: String) -> float:
	var it := get_item(id)
	if it.is_empty():
		return 0.0
	if it["state"] == "unlocked":
		return 1.0
	if int(it["target"]) <= 0:
		return 0.0
	return clampf(float(it["progress"]) / float(it["target"]), 0.0, 1.0)


func progress_pct(id: String) -> int:
	return int(floor(progress_ratio(id) * 100.0 + 0.0001))


func requirement_text(id: String) -> String:
	var it := get_item(id)
	if it.is_empty():
		return ""
	var tpl := str(it.get("requirement_template", ""))
	if tpl != "" and int(it["target"]) > 0:
		return tpl.format({"current": int(it["progress"]), "target": int(it["target"])})
	return str(it["requirement"])


## Vista pública: oculta nombre/rareza/procedencia de lo «Por descubrir».
func get_item_view(id: String) -> Dictionary:
	var it := get_item(id)
	if it.is_empty():
		return {}
	var hidden: bool = it["state"] == "hidden"
	var src: Dictionary = it["source"]
	var view := {
		"id": id,
		"category": it["category"],
		"state": it["state"],
		"hidden": hidden,
		"unlocked": it["state"] == "unlocked",
		"name": HIDDEN_NAME if hidden else str(it["name"]),
		"rarity": "" if hidden else str(it["rarity"]),
		"rarity_name": "???" if hidden else rarity_name(str(it["rarity"])),
		"description": "Aún no tienes pistas. Explora, abre salas «???» o pregunta en el Códice." if hidden else str(it["description"]),
		"source_type": "secret" if hidden else str(src.get("type", "")),
		"source_label": "???" if hidden else source_label(str(src.get("type", ""))),
		"source_text": "???" if hidden else str(src.get("text", "")),
		"universe": "" if hidden else str(it["universe"]),
		"progress": int(it["progress"]),
		"target": int(it["target"]),
		"progress_ratio": 0.0 if hidden else progress_ratio(id),
		"progress_pct": 0 if hidden else progress_pct(id),
		"in_progress": not hidden and it["state"] == "locked" and int(it["target"]) > 0 and int(it["progress"]) > 0,
		"requirement": "" if hidden else requirement_text(id),
		"cta": {} if hidden else (it["cta"] as Dictionary).duplicate(true),
		"slot": str(it.get("slot", "")),
		"active": is_active(id),
		"action": action_for(id),
	}
	return view


## Lista filtrada y ordenada de la categoría.
## `state_filter`: all | unlocked | missing (locked + hidden). `rarity`: "" = todas
## (con rareza elegida, lo «Por descubrir» no aparece: su rareza es secreta).
func list_items(category: String, state_filter: String = "all", rarity: String = "", sort_id: String = "near") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var idx := 0
	for id in item_order:
		var it: Dictionary = items[id]
		if it["category"] != category:
			continue
		idx += 1
		match state_filter:
			"unlocked":
				if it["state"] != "unlocked":
					continue
			"missing":
				if it["state"] == "unlocked":
					continue
		if rarity != "" and (it["state"] == "hidden" or it["rarity"] != rarity):
			continue
		var v := get_item_view(id)
		v["catalog_index"] = idx
		out.append(v)
	out.sort_custom(_sorter(sort_id))
	return out


func _sorter(sort_id: String) -> Callable:
	match sort_id:
		"catalog":
			return func(a: Dictionary, b: Dictionary) -> bool: return a["catalog_index"] < b["catalog_index"]
		"name":
			return func(a: Dictionary, b: Dictionary) -> bool:
				if a["hidden"] != b["hidden"]:
					return not a["hidden"]
				if a["name"] != b["name"]:
					return str(a["name"]).naturalnocasecmp_to(str(b["name"])) < 0
				return a["catalog_index"] < b["catalog_index"]
		"rarity":
			return func(a: Dictionary, b: Dictionary) -> bool:
				var ra := RARITY_ORDER.find(a["rarity"])
				var rb := RARITY_ORDER.find(b["rarity"])
				if ra != rb:
					return ra > rb
				return a["catalog_index"] < b["catalog_index"]
	# near: tuyas · por conseguir con progreso (más avanzadas primero) · sin progreso · por descubrir.
	return func(a: Dictionary, b: Dictionary) -> bool:
		var ga := _near_group(a)
		var gb := _near_group(b)
		if ga != gb:
			return ga < gb
		if ga == 1 and a["progress_ratio"] != b["progress_ratio"]:
			return a["progress_ratio"] > b["progress_ratio"]
		return a["catalog_index"] < b["catalog_index"]


func _near_group(v: Dictionary) -> int:
	if v["unlocked"]:
		return 0
	if v["hidden"]:
		return 3
	return 1 if v["in_progress"] else 2


## «Cerca de conseguir»: por conseguir con progreso, más avanzadas primero.
## `category` "" = todas las categorías.
func near_completion(limit: int = 4, category: String = "") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in item_order:
		var it: Dictionary = items[id]
		if category != "" and it["category"] != category:
			continue
		var v := get_item_view(id)
		if v["in_progress"]:
			out.append(v)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["progress_ratio"] != b["progress_ratio"]:
			return a["progress_ratio"] > b["progress_ratio"]
		return item_order.find(a["id"]) < item_order.find(b["id"]))
	if limit > 0 and out.size() > limit:
		out.resize(limit)
	return out


# ==========================================================================
# Diario del multiverso
# ==========================================================================
func link_knowledge(k: Node) -> void:
	if knowledge and knowledge != k:
		_disconnect_knowledge()
	knowledge = k
	if k == null:
		journal_changed.emit()
		return
	for sig in ["entry_discovered", "visibility_changed"]:
		if k.has_signal(sig):
			var cb := Callable(self, "_on_knowledge_changed")
			if not k.is_connected(sig, cb):
				k.connect(sig, cb)
	sync_titles_from_knowledge()
	journal_changed.emit()


func _disconnect_knowledge() -> void:
	for sig in ["entry_discovered", "visibility_changed"]:
		var cb := Callable(self, "_on_knowledge_changed")
		if knowledge.has_signal(sig) and knowledge.is_connected(sig, cb):
			knowledge.disconnect(sig, cb)


func _on_knowledge_changed(_a = null, _b = null, _c = null) -> void:
	sync_titles_from_knowledge()
	journal_changed.emit()


## Entradas del Códice conocidas por universo: {universe: {"known": n, "secrets": n}}.
func knowledge_counts() -> Dictionary:
	var out := {}
	if knowledge == null or not knowledge.has_method("list_entries"):
		return out
	for e in knowledge.list_entries():
		var u := str(e.get("universe", ""))
		if u == "" or int(e["visibility"]) < 2:   # KNOWN_SECRET o más
			continue
		if not out.has(u):
			out[u] = {"known": 0, "secrets": 0}
		out[u]["known"] += 1
		if int(e["visibility"]) == 2 and not bool(e.get("pending", false)):
			out[u]["secrets"] += 1
	return out


func get_universe(universe_id: String) -> Dictionary:
	for u in universes:
		if u["id"] == universe_id:
			return u
	return {}


## Progreso de un universo: explorado, %, secretos (seed + Códice vinculado).
func universe_progress(universe_id: String) -> Dictionary:
	var u := get_universe(universe_id)
	if u.is_empty():
		return {}
	var kc: Dictionary = knowledge_counts().get(universe_id, {"known": 0, "secrets": 0})
	var explored := mini(int(u["total"]), int(u["explored"]) + int(kc["known"]))
	var pct := int(floor(float(explored) * 100.0 / float(u["total"]) + 0.0001))
	var secrets := int(u["secrets"]) + int(kc["secrets"])
	return {
		"id": universe_id,
		"name": u["name"],
		"color": u["color"],
		"explored": explored,
		"total": u["total"],
		"ratio": float(explored) / float(u["total"]),
		"pct": pct,
		"secrets": secrets,
		"text": "%d %% · %d %s" % [pct, secrets, "secreto" if secrets == 1 else "secretos"],
	}


func journal() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for u in universes:
		out.append(universe_progress(u["id"]))
	return out


## Explora puntos de un universo sin pasar por el Códice (zonas, mapas, viajes).
func add_exploration(universe_id: String, points: int = 1) -> bool:
	for u in universes:
		if u["id"] == universe_id:
			u["explored"] = clampi(int(u["explored"]) + points, 0, int(u["total"]))
			journal_changed.emit()
			return true
	return false


## Los títulos que concede el Códice (KnowledgeService.titles, p. ej. «Pionero») se desbloquean.
func sync_titles_from_knowledge() -> int:
	if knowledge == null or not ("titles" in knowledge):
		return 0
	var n := 0
	for t in knowledge.titles:
		for id in item_order:
			var it: Dictionary = items[id]
			if it["category"] == "titles" and it["state"] != "unlocked" and str(it["name"]) == str(t):
				_unlock(id)
				n += 1
	return n


# ==========================================================================
# Desbloqueo y progreso
# ==========================================================================
## Hallazgo de algo «Por descubrir»: pasa a «Por conseguir» con su nombre y rareza.
func reveal(id: String) -> bool:
	if not is_hidden(id):
		return false
	items[id]["state"] = "locked"
	collection_changed.emit(items[id]["category"])
	return true


## Suma progreso. Al llegar al objetivo se desbloquea. Devuelve {ok, unlocked, progress, target}.
func add_progress(id: String, amount: int = 1) -> Dictionary:
	var it := get_item(id)
	if it.is_empty():
		return {"ok": false, "reason": "unknown_item"}
	if it["state"] == "unlocked":
		return {"ok": false, "reason": "already_unlocked"}
	if int(it["target"]) <= 0:
		return {"ok": false, "reason": "no_progress"}
	if it["state"] == "hidden":
		reveal(id)
	it["progress"] = clampi(int(it["progress"]) + amount, 0, int(it["target"]))
	progress_changed.emit(id, it["progress"], it["target"])
	var done := int(it["progress"]) >= int(it["target"])
	if done:
		_unlock(id)
	else:
		collection_changed.emit(it["category"])
	return {"ok": true, "unlocked": done, "progress": it["progress"], "target": it["target"]}


## Desbloqueo directo (botín, compra, recompensa del servidor).
func unlock(id: String) -> Dictionary:
	if not items.has(id):
		return {"ok": false, "reason": "unknown_item"}
	if is_unlocked(id):
		return {"ok": false, "reason": "already_unlocked"}
	_unlock(id)
	return {"ok": true, "id": id}


func _unlock(id: String) -> void:
	var it: Dictionary = items[id]
	it["state"] = "unlocked"
	if int(it["target"]) > 0:
		it["progress"] = it["target"]
	item_unlocked.emit(id)
	collection_changed.emit(it["category"])
	# Un logro puede conceder un título.
	var reward := str(it.get("reward_title", ""))
	if reward != "" and items.has(reward) and not is_unlocked(reward):
		_unlock(reward)


# ==========================================================================
# Cosméticos activos
# ==========================================================================
## Acción principal de la ficha: summon | dismiss | pet | unpet | transmog | untransmog |
## title | untitle | cta | none.
func action_for(id: String) -> String:
	var it := get_item(id)
	if it.is_empty() or it["state"] == "hidden":
		return "none"
	if it["state"] != "unlocked":
		return "cta" if not (it["cta"] as Dictionary).is_empty() else "none"
	match it["category"]:
		"mounts":
			return "dismiss" if (active_mount == id and mount_summoned) else "summon"
		"pets":
			return "unpet" if active_pet == id else "pet"
		"transmogs":
			return "untransmog" if active_transmog.get(str(it.get("slot", "")), "") == id else "transmog"
		"titles":
			return "untitle" if active_title == id else "title"
	return "none"


static func action_label(action: String, cta: Dictionary = {}) -> String:
	match action:
		"summon":
			return "Invocar"
		"dismiss":
			return "Desmontar"
		"pet":
			return "Llevar conmigo"
		"unpet":
			return "Guardar mascota"
		"transmog":
			return "Equipar apariencia"
		"untransmog":
			return "Quitar apariencia"
		"title":
			return "Equipar título"
		"untitle":
			return "Quitar título"
		"cta":
			return str(cta.get("label", "Cómo conseguirlo"))
	return "Conseguido"


func is_active(id: String) -> bool:
	if id == "":
		return false
	return id == active_mount or id == active_pet or id == active_title or active_transmog.values().has(id)


func _require(id: String, category: String) -> Dictionary:
	var it := get_item(id)
	if it.is_empty():
		return {"ok": false, "reason": "unknown_item"}
	if it["category"] != category:
		return {"ok": false, "reason": "wrong_category"}
	if it["state"] != "unlocked":
		return {"ok": false, "reason": "locked"}
	return {"ok": true}


## Invoca la montura (y la deja como favorita). `flying` informativo para el HUD.
func summon_mount(id: String) -> Dictionary:
	var r := _require(id, "mounts")
	if not r["ok"]:
		return r
	active_mount = id
	mount_summoned = true
	active_changed.emit("mount", id)
	collection_changed.emit("mounts")
	return {"ok": true, "id": id, "flying": bool(items[id].get("flying", false))}


func dismiss_mount() -> Dictionary:
	if not mount_summoned:
		return {"ok": false, "reason": "not_summoned"}
	mount_summoned = false
	active_changed.emit("mount", "")
	collection_changed.emit("mounts")
	return {"ok": true}


func set_active_pet(id: String) -> Dictionary:
	if id == "":
		active_pet = ""
		active_changed.emit("pet", "")
		collection_changed.emit("pets")
		return {"ok": true, "id": ""}
	var r := _require(id, "pets")
	if not r["ok"]:
		return r
	active_pet = id
	active_changed.emit("pet", id)
	collection_changed.emit("pets")
	return {"ok": true, "id": id}


## Equipa una apariencia en su ranura (sustituye a la anterior de esa ranura).
func equip_transmog(id: String) -> Dictionary:
	var r := _require(id, "transmogs")
	if not r["ok"]:
		return r
	var slot := str(items[id].get("slot", ""))
	if not TRANSMOG_SLOTS.has(slot):
		return {"ok": false, "reason": "invalid_slot"}
	var prev := str(active_transmog.get(slot, ""))
	active_transmog[slot] = id
	active_changed.emit("transmog", id)
	collection_changed.emit("transmogs")
	return {"ok": true, "id": id, "slot": slot, "replaced": prev}


func clear_transmog(slot: String) -> Dictionary:
	if not active_transmog.has(slot):
		return {"ok": false, "reason": "empty_slot"}
	active_transmog.erase(slot)
	active_changed.emit("transmog", "")
	collection_changed.emit("transmogs")
	return {"ok": true, "slot": slot}


func equip_title(id: String) -> Dictionary:
	if id == "":
		active_title = ""
		active_changed.emit("title", "")
		collection_changed.emit("titles")
		return {"ok": true, "id": ""}
	var r := _require(id, "titles")
	if not r["ok"]:
		return r
	active_title = id
	active_changed.emit("title", id)
	collection_changed.emit("titles")
	return {"ok": true, "id": id}


## Nombre visible del personaje con el título equipado («Tú, Pionero»).
func display_name_with_title(char_name: String = "") -> String:
	var n := char_name if char_name != "" else player_name
	if active_title == "" or not items.has(active_title):
		return n
	var tpl := str(items[active_title].get("display", "{name}, " + str(items[active_title]["name"])))
	return tpl.format({"name": n})


## Ejecuta la acción principal de la ficha. Para `cta` devuelve la ventana/acción a abrir.
func perform_action(id: String) -> Dictionary:
	var a := action_for(id)
	match a:
		"summon":
			return summon_mount(id)
		"dismiss":
			return dismiss_mount()
		"pet":
			return set_active_pet(id)
		"unpet":
			return set_active_pet("")
		"transmog":
			return equip_transmog(id)
		"untransmog":
			return clear_transmog(str(items[id].get("slot", "")))
		"title":
			return equip_title(id)
		"untitle":
			return equip_title("")
		"cta":
			var cta: Dictionary = items[id]["cta"]
			if str(cta.get("action", "")) == "notify_event":
				return set_event_reminder(str(cta.get("event_id", "")))
			return {"ok": true, "open_window": str(cta.get("window", "")), "params": (cta.get("params", {}) as Dictionary).duplicate(true)}
	return {"ok": false, "reason": "no_action"}


## «Avisarme del evento».
func set_event_reminder(event_id: String) -> Dictionary:
	if event_id == "":
		return {"ok": false, "reason": "invalid_event"}
	if event_reminders.has(event_id):
		return {"ok": false, "reason": "already_set", "event_id": event_id}
	event_reminders.append(event_id)
	event_reminder_set.emit(event_id)
	return {"ok": true, "event_id": event_id, "reminder": true}


# ==========================================================================
# Persistencia
# ==========================================================================
func to_dict() -> Dictionary:
	var states := {}
	for id in item_order:
		states[id] = {"state": items[id]["state"], "progress": items[id]["progress"]}
	var explored := {}
	for u in universes:
		explored[u["id"]] = u["explored"]
	return {
		"items": states,
		"explored": explored,
		"active": {"mount": active_mount, "summoned": mount_summoned, "pet": active_pet, "title": active_title, "transmog": active_transmog.duplicate()},
		"reminders": event_reminders.duplicate(),
	}


func load_state(d: Dictionary) -> void:
	var st: Dictionary = d.get("items", {})
	for id in st:
		if items.has(id):
			var s := str(st[id].get("state", items[id]["state"]))
			items[id]["state"] = s if s in STATES else items[id]["state"]
			items[id]["progress"] = int(st[id].get("progress", items[id]["progress"]))
	var ex: Dictionary = d.get("explored", {})
	for u in universes:
		if ex.has(u["id"]):
			u["explored"] = clampi(int(ex[u["id"]]), 0, int(u["total"]))
	var a: Dictionary = d.get("active", {})
	active_mount = str(a.get("mount", "")) if is_unlocked(str(a.get("mount", ""))) else ""
	mount_summoned = bool(a.get("summoned", false)) and active_mount != ""
	active_pet = str(a.get("pet", "")) if is_unlocked(str(a.get("pet", ""))) else ""
	active_title = str(a.get("title", "")) if is_unlocked(str(a.get("title", ""))) else ""
	active_transmog = {}
	var tm: Dictionary = a.get("transmog", {})
	for slot in tm:
		if is_unlocked(str(tm[slot])):
			active_transmog[str(slot)] = str(tm[slot])
	event_reminders.clear()
	for e in d.get("reminders", []):
		event_reminders.append(str(e))
	for c in CATEGORY_IDS:
		collection_changed.emit(c)
	journal_changed.emit()


# ==========================================================================
# Utilidades
# ==========================================================================
static func rarity_color(rarity: String) -> Color:
	return Color(RARITIES.get(rarity, RARITIES["common"])["color"])


static func rarity_bg(rarity: String) -> Color:
	return Color(RARITIES.get(rarity, RARITIES["common"])["bg"])


static func rarity_name(rarity: String) -> String:
	return str(RARITIES.get(rarity, RARITIES["common"])["name"])


static func source_label(source_type: String) -> String:
	return str(SOURCE_LABELS.get(source_type, source_type.capitalize()))


static func fmt(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "." + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out
