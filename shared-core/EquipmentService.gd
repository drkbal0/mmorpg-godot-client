extends Node
## EquipmentService — equipo activo, mochila, bolsa segura y conjuntos (UI v2.4 Paso 10).
## Referencia: design_ref/pantallas_html/MMO-Equipo.html · PROMPT_ANTIGRAVITY §2.1, §2.2 y Anexo A.
##
## - 13 ranuras de paperdoll (cabeza … arma secundaria). Los anillos aceptan la ranura «ring»
##   en `ring_1` y `ring_2`.
## - Nivel de objeto: `iLvl = suma(item_level de lo equipado) / ranuras_equipadas`.
## - Estadísticas totales = base del personaje + atributos de todas las piezas equipadas,
##   siempre con las 16 claves canónicas del Anexo A (`hud_tokens.STAT_KEYS`).
## - Comparación: `compare_item()` simula equipar un objeto de la mochila (o quitar el de una
##   ranura con `compare_unequip()`) y devuelve los deltas por estadística.
## - Conjuntos: «Daño» F1, «Tanque» F2, «Recolección» F3 (+ nuevos con «+»). Guardar captura
##   lo equipado; aplicar equipa lo que esté disponible en mochila/bolsa segura.
## - Bolsa segura: lo que está ahí no se pierde al morir en una zona peligrosa.
##
## Todo dirigido por datos (`config/equipment/equipment_seed.json`). Instanciable con `.new()`
## (tests) y como autoload `EquipmentService`.

const T = preload("res://ui/tokens/hud_tokens.gd")
const DEFAULT_SEED_PATH := "res://config/equipment/equipment_seed.json"

## Orden del paperdoll: izquierda (7) y derecha (6) del avatar.
const SLOT_ORDER: Array[String] = [
	"head", "neck", "shoulders", "chest", "waist", "legs", "feet",
	"wrists", "hands", "ring_1", "ring_2", "main_hand", "off_hand",
]
const LEFT_SLOTS: Array[String] = ["head", "neck", "shoulders", "chest", "waist", "legs", "feet"]
const RIGHT_SLOTS: Array[String] = ["wrists", "hands", "ring_1", "ring_2", "main_hand", "off_hand"]

## Ranura del paperdoll -> {name, accepts (campo `slot` del objeto), icon (path 24×24)}.
const SLOTS := {
	"head": {"name": "Cabeza", "accepts": "head", "icon": "M5 14a7 7 0 0 1 14 0v3H5zM9 17v3M15 17v3M12 4v3"},
	"neck": {"name": "Cuello", "accepts": "neck", "icon": "M6 4c0 6 2.5 9 6 9s6-3 6-9M12 13v3M12 16a3 3 0 1 0 0 6a3 3 0 1 0 0-6"},
	"shoulders": {"name": "Hombros", "accepts": "shoulders", "icon": "M3 14c0-4 3-7 7-7h4c4 0 7 3 7 7l-4 2-2-4H9l-2 4z"},
	"chest": {"name": "Pecho", "accepts": "chest", "icon": "M8 3l4 3 4-3 4 4-3 3v11H7V10L4 7zM12 6v15"},
	"waist": {"name": "Cintura", "accepts": "waist", "icon": "M3 10h18v5H3zM10 10v5h4v-5"},
	"legs": {"name": "Piernas", "accepts": "legs", "icon": "M7 3h10l-1 18h-3l-1-10-1 10H8z"},
	"feet": {"name": "Pies", "accepts": "feet", "icon": "M8 3v10l-4 4v3h9v-3l3-2h4v-3l-6-1V3z"},
	"wrists": {"name": "Muñecas", "accepts": "wrists", "icon": "M6 8h12v8H6zM6 12h12M9 8v8M15 8v8"},
	"hands": {"name": "Manos", "accepts": "hands", "icon": "M7 21v-8L5 9l2-1 2 3V4h2v7V3h2v8V4h2v8l1-3h2l-1 6-3 6z"},
	"ring_1": {"name": "Anillo 1", "accepts": "ring", "icon": "M12 8a6 6 0 1 0 0 12a6 6 0 1 0 0-12M9 3h6l-3 5z"},
	"ring_2": {"name": "Anillo 2", "accepts": "ring", "icon": "M12 8a6 6 0 1 0 0 12a6 6 0 1 0 0-12M9 3h6l-3 5z"},
	"main_hand": {"name": "Arma principal", "accepts": "main_hand", "icon": "M14 4h6v6L10 20l-6-6zM4 14l6 6M3 21l2-2"},
	"off_hand": {"name": "Arma secundaria", "accepts": "off_hand", "icon": "M12 3l7 3v6c0 4.5-3 7.5-7 9-4-1.5-7-4.5-7-9V6z"},
}

## Rarezas: borde de la ranura y color del nombre.
const RARITIES := {
	"common": {"name": "Común", "color": "#9aa6ae", "bg": "#121a20"},
	"uncommon": {"name": "Poco común", "color": "#7bd88f", "bg": "#14241b"},
	"rare": {"name": "Raro", "color": "#5aa9ff", "bg": "#13203a"},
	"epic": {"name": "Épico", "color": "#cfa8ff", "bg": "#2a1d3a"},
	"legendary": {"name": "Legendario", "color": "#ffb547", "bg": "#33240f"},
}
const RARITY_ORDER: Array[String] = ["common", "uncommon", "rare", "epic", "legendary"]

## Filtros rápidos de la mochila (Todo · Armas · Armaduras · Consumibles · Materiales).
const FILTERS: Array[Dictionary] = [
	{"id": "all", "label": "Todo"},
	{"id": "weapon", "label": "Armas"},
	{"id": "armor", "label": "Armaduras"},
	{"id": "consumable", "label": "Consumibles"},
	{"id": "material", "label": "Materiales"},
]
const CATEGORY_NAMES := {
	"weapon": "Arma", "armor": "Armadura", "consumable": "Consumible", "material": "Material", "quest": "Misión",
}

## Estadísticas que se muestran como porcentaje.
const PERCENT_STATS: Array[String] = ["velatq", "celeridad", "critico", "robo", "omni", "tenacidad", "curacion"]

## Conjuntos por defecto (si el seed no trae ninguno) y su tecla.
const DEFAULT_SETS: Array[Dictionary] = [
	{"id": "damage", "name": "Daño", "key": "F1"},
	{"id": "tank", "name": "Tanque", "key": "F2"},
	{"id": "gathering", "name": "Recolección", "key": "F3"},
]
const SET_KEYS := {KEY_F1: "F1", KEY_F2: "F2", KEY_F3: "F3"}
const MAX_SETS := 6

const STOPWORDS: Array[String] = ["con", "de", "del", "la", "el", "los", "las", "y", "a", "en", "mayor", "menor", "que", "un", "una"]

signal equipment_changed(slot: String)
signal backpack_changed
signal stats_changed
signal set_changed(set_id: String)
signal sets_updated

var character: Dictionary = {"name": "", "class": "", "level": 1}
var base_stats: Dictionary = {}
var backpack_capacity: int = 40
var secure_capacity: int = 3

## Catálogo de objetos conocidos: id -> Dictionary normalizado.
var items: Dictionary = {}
## Ranura -> item_id ("" vacía).
var equipped: Dictionary = {}
## Orden de la mochila (item_id) y de la bolsa segura.
var backpack: Array[String] = []
var secure: Array[String] = []
## Conjuntos: Array de {id, name, key, slots: {slot: item_id}}.
var sets: Array[Dictionary] = []
var active_set: String = ""

var _custom_counter := 0


func _init() -> void:
	reset()


func _ready() -> void:
	if items.is_empty() and FileAccess.file_exists(DEFAULT_SEED_PATH):
		load_seed(DEFAULT_SEED_PATH)


func reset() -> void:
	character = {"name": "", "class": "", "level": 1}
	base_stats = empty_stats()
	items.clear()
	equipped.clear()
	for s in SLOT_ORDER:
		equipped[s] = ""
	backpack.clear()
	secure.clear()
	sets.clear()
	for d in DEFAULT_SETS:
		sets.append({"id": d["id"], "name": d["name"], "key": d["key"], "slots": {}})
	active_set = ""
	_custom_counter = 0


# ==========================================================================
# Carga
# ==========================================================================
func load_seed(path: String = DEFAULT_SEED_PATH) -> bool:
	if not FileAccess.file_exists(path):
		push_warning("[EquipmentService] Seed no encontrado: " + path)
		return false
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY:
		push_warning("[EquipmentService] Seed inválido: " + path)
		return false
	load_data(data)
	return true


func load_data(data: Dictionary) -> void:
	reset()
	var ch: Dictionary = data.get("character", {})
	character = {
		"name": str(ch.get("name", "")),
		"class": str(ch.get("class", "")),
		"level": int(ch.get("level", 1)),
	}
	backpack_capacity = int(data.get("backpack_capacity", backpack_capacity))
	secure_capacity = int(data.get("secure_capacity", secure_capacity))
	var bs: Dictionary = data.get("base_stats", {})
	for k in bs:
		var ck := T.canonical_stat_key(str(k))
		if base_stats.has(ck):
			base_stats[ck] = float(bs[k])
	for raw in data.get("items", []):
		add_item_definition(raw)
	var eq: Dictionary = data.get("equipped", {})
	for slot in eq:
		var iid := str(eq[slot])
		if equipped.has(slot) and items.has(iid) and can_equip_in(iid, slot):
			equipped[slot] = iid
	for iid in data.get("backpack", []):
		if items.has(str(iid)) and backpack.size() < backpack_capacity:
			backpack.append(str(iid))
	for iid in data.get("secure", []):
		if items.has(str(iid)) and secure.size() < secure_capacity:
			secure.append(str(iid))
	var seed_sets: Array = data.get("sets", [])
	if not seed_sets.is_empty():
		sets.clear()
		for s in seed_sets:
			var slots := {}
			var src: Dictionary = s.get("slots", {})
			for slot in src:
				if SLOTS.has(slot):
					slots[slot] = str(src[slot])
			sets.append({"id": str(s.get("id", "")), "name": str(s.get("name", "")), "key": str(s.get("key", "")), "slots": slots})
	active_set = str(data.get("active_set", sets[0]["id"] if not sets.is_empty() else ""))
	_emit_all()


## Normaliza y registra un objeto. Devuelve su id ("" si no es válido).
func add_item_definition(raw: Dictionary) -> String:
	var iid := str(raw.get("id", ""))
	if iid == "":
		return ""
	var stats := {}
	var src: Dictionary = raw.get("stats", {})
	for k in src:
		var ck := T.canonical_stat_key(str(k))
		if T.has_stat(ck):
			stats[ck] = float(src[k])
	var rarity := str(raw.get("rarity", "common"))
	if not RARITIES.has(rarity):
		rarity = "common"
	var slot := str(raw.get("slot", ""))
	var category := str(raw.get("category", "weapon" if slot in ["main_hand", "off_hand"] else ("armor" if slot != "" else "material")))
	items[iid] = {
		"id": iid,
		"name": str(raw.get("name", iid)),
		"slot": slot,
		"category": category,
		"rarity": rarity,
		"item_level": int(raw.get("item_level", 0)),
		"quantity": int(raw.get("quantity", 1)),
		"new": bool(raw.get("new", false)),
		"stats": stats,
	}
	return iid


## Adaptador de `InventoryController.fetch_inventory_state()` / `ShelterManager.character_inventory`:
## solo incorpora objetos con metadatos de equipo (slot o stats). Devuelve los ids añadidos.
func ingest_inventory_items(list: Array) -> Array[String]:
	var added: Array[String] = []
	for raw in list:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = raw
		var props: Dictionary = d.get("properties", {}) if typeof(d.get("properties", {})) == TYPE_DICTIONARY else {}
		var slot := str(d.get("equip_slot", props.get("equip_slot", "")))
		var stats = d.get("stats", props.get("stats", {}))
		if slot == "" and (typeof(stats) != TYPE_DICTIONARY or stats.is_empty()):
			continue
		var iid := add_item_definition({
			"id": str(d.get("id", "")),
			"name": str(d.get("item_name", d.get("name", ""))),
			"slot": slot,
			"rarity": str(d.get("rarity", props.get("rarity", "common"))),
			"item_level": int(d.get("item_level", props.get("item_level", 0))),
			"quantity": int(d.get("quantity", 1)),
			"stats": stats if typeof(stats) == TYPE_DICTIONARY else {},
		})
		if iid != "" and not is_equipped(iid) and not backpack.has(iid) and not secure.has(iid) and backpack.size() < backpack_capacity:
			backpack.append(iid)
			added.append(iid)
	if not added.is_empty():
		backpack_changed.emit()
	return added


func _emit_all() -> void:
	backpack_changed.emit()
	stats_changed.emit()
	sets_updated.emit()
	set_changed.emit(active_set)


# ==========================================================================
# Consultas
# ==========================================================================
static func empty_stats() -> Dictionary:
	var d := {}
	for k in T.STAT_KEYS:
		d[k] = 0.0
	return d


func get_item(item_id: String) -> Dictionary:
	return items.get(item_id, {})


func get_equipped(slot: String) -> Dictionary:
	return get_item(str(equipped.get(slot, "")))


func is_equipped(item_id: String) -> bool:
	return item_id != "" and equipped.values().has(item_id)


func slot_of(item_id: String) -> String:
	for s in SLOT_ORDER:
		if equipped[s] == item_id:
			return s
	return ""


func get_equipped_count() -> int:
	var n := 0
	for s in SLOT_ORDER:
		if equipped[s] != "":
			n += 1
	return n


## Media exacta: suma(item_level) / ranuras_equipadas (0 si no hay nada).
func get_item_level_exact() -> float:
	var n := get_equipped_count()
	if n == 0:
		return 0.0
	var total := 0
	for s in SLOT_ORDER:
		if equipped[s] != "":
			total += int(items[equipped[s]]["item_level"])
	return float(total) / float(n)


## iLvl mostrado (entero, redondeo hacia abajo como en los MMO).
func get_item_level() -> int:
	return int(floor(get_item_level_exact() + 0.0001))


static func slot_name(slot: String) -> String:
	return str(SLOTS.get(slot, {}).get("name", slot))


static func slot_icon(slot: String) -> String:
	return str(SLOTS.get(slot, {}).get("icon", ""))


static func rarity_color(rarity: String) -> Color:
	return Color(RARITIES.get(rarity, RARITIES["common"])["color"])


static func rarity_bg(rarity: String) -> Color:
	return Color(RARITIES.get(rarity, RARITIES["common"])["bg"])


static func rarity_name(rarity: String) -> String:
	return str(RARITIES.get(rarity, RARITIES["common"])["name"])


func is_equippable(item_id: String) -> bool:
	return str(get_item(item_id).get("slot", "")) != ""


## ¿Puede ir el objeto en esa ranura del paperdoll?
func can_equip_in(item_id: String, slot: String) -> bool:
	var it := get_item(item_id)
	if it.is_empty() or not SLOTS.has(slot):
		return false
	return str(it["slot"]) != "" and str(it["slot"]) == str(SLOTS[slot]["accepts"])


## Ranuras compatibles para un objeto (anillo -> ring_1, ring_2).
func valid_slots_for(item_id: String) -> Array[String]:
	var out: Array[String] = []
	for s in SLOT_ORDER:
		if can_equip_in(item_id, s):
			out.append(s)
	return out


## Ranura destino por defecto: la vacía compatible, o la de menor nivel de objeto.
func default_slot_for(item_id: String) -> String:
	var options := valid_slots_for(item_id)
	if options.is_empty():
		return ""
	var current := slot_of(item_id)
	if current != "":
		return current
	var best := options[0]
	var best_lvl := 1 << 30
	for s in options:
		if equipped[s] == "":
			return s
		var lvl := int(items[equipped[s]]["item_level"])
		if lvl < best_lvl:
			best_lvl = lvl
			best = s
	return best


# ==========================================================================
# Estadísticas y comparación
# ==========================================================================
## Base + todas las piezas de `loadout` (slot -> item_id). Por defecto lo equipado.
func compute_stats(loadout: Dictionary = {}) -> Dictionary:
	var src: Dictionary = equipped if loadout.is_empty() else loadout
	var total := empty_stats()
	for k in base_stats:
		total[k] += float(base_stats[k])
	for s in src:
		var iid := str(src[s])
		if iid == "" or not items.has(iid):
			continue
		var st: Dictionary = items[iid]["stats"]
		for k in st:
			total[k] += float(st[k])
	return total


func get_total_stats() -> Dictionary:
	return compute_stats()


## Suma solo de las piezas equipadas (sin base).
func get_gear_stats() -> Dictionary:
	var total := empty_stats()
	for s in SLOT_ORDER:
		var iid: String = equipped[s]
		if iid == "":
			continue
		var st: Dictionary = items[iid]["stats"]
		for k in st:
			total[k] += float(st[k])
	return total


static func _diff(after: Dictionary, before: Dictionary) -> Dictionary:
	var d := {}
	for k in T.STAT_KEYS:
		d[k] = snappedf(float(after.get(k, 0.0)) - float(before.get(k, 0.0)), 0.001)
	return d


## Simula equipar `item_id` (en `slot` o la ranura por defecto).
## {ok, item_id, slot, replaced_id, before, after, deltas, ilvl_before, ilvl_after}
func compare_item(item_id: String, slot: String = "") -> Dictionary:
	var target := slot if slot != "" else default_slot_for(item_id)
	if target == "" or not can_equip_in(item_id, target):
		return {"ok": false, "item_id": item_id, "slot": target, "deltas": empty_stats()}
	var loadout := equipped.duplicate()
	var prev_slot := slot_of(item_id)
	var replaced := str(loadout[target])
	if prev_slot != "" and prev_slot != target:
		loadout[prev_slot] = replaced
	loadout[target] = item_id
	return _comparison(item_id, target, replaced if replaced != item_id else "", loadout)


## Simula quitar la pieza de `slot` (hover sobre una ranura equipada).
func compare_unequip(slot: String) -> Dictionary:
	var iid := str(equipped.get(slot, ""))
	if iid == "":
		return {"ok": false, "item_id": "", "slot": slot, "deltas": empty_stats()}
	var loadout := equipped.duplicate()
	loadout[slot] = ""
	var res := _comparison("", slot, iid, loadout)
	res["item_id"] = iid
	res["mode"] = "unequip"
	return res


func _comparison(item_id: String, slot: String, replaced: String, loadout: Dictionary) -> Dictionary:
	var before := get_total_stats()
	var after := compute_stats(loadout)
	# compute_stats() con un dict vacío usaría lo equipado: si quitamos todo, base pura.
	if _is_empty_loadout(loadout):
		after = compute_stats({"_": ""})
	return {
		"ok": true,
		"mode": "equip",
		"item_id": item_id,
		"slot": slot,
		"replaced_id": replaced,
		"before": before,
		"after": after,
		"deltas": _diff(after, before),
		"ilvl_before": get_item_level_exact(),
		"ilvl_after": _ilvl_of(loadout),
	}


func _is_empty_loadout(loadout: Dictionary) -> bool:
	for s in loadout:
		if str(loadout[s]) != "":
			return false
	return true


func _ilvl_of(loadout: Dictionary) -> float:
	var n := 0
	var total := 0
	for s in loadout:
		var iid := str(loadout[s])
		if iid != "" and items.has(iid):
			n += 1
			total += int(items[iid]["item_level"])
	return float(total) / float(n) if n > 0 else 0.0


static func is_percent_stat(key: String) -> bool:
	return PERCENT_STATS.has(T.canonical_stat_key(key))


## «1.842», «5,8 %», «0 %». Enteros con separador de miles; decimales con coma.
static func format_stat(key: String, value: float) -> String:
	var txt: String
	if is_equal_approx(value, roundf(value)):
		txt = T.format_amount(int(roundf(value)))
	else:
		txt = ("%.1f" % value).replace(".", ",")
	return txt + (" %" if is_percent_stat(key) else "")


# ==========================================================================
# Equipar / desequipar
# ==========================================================================
## Equipa desde la mochila, la bolsa segura u otra ranura. La pieza que había en la ranura
## vuelve a la posición de origen (intercambio), así nunca falta hueco.
## {ok, reason, slot, replaced_id}
func equip(item_id: String, slot: String = "") -> Dictionary:
	if not items.has(item_id):
		return {"ok": false, "reason": "unknown_item", "slot": slot}
	if not is_equippable(item_id):
		return {"ok": false, "reason": "not_equippable", "slot": slot}
	var target := slot if slot != "" else default_slot_for(item_id)
	if not can_equip_in(item_id, target):
		return {"ok": false, "reason": "invalid_slot", "slot": target}
	var replaced: String = equipped[target]
	if replaced == item_id:
		return {"ok": true, "reason": "already_equipped", "slot": target, "replaced_id": ""}
	var from_slot := slot_of(item_id)
	var bi := backpack.find(item_id)
	var si := secure.find(item_id)
	if from_slot == "" and bi < 0 and si < 0:
		return {"ok": false, "reason": "not_owned", "slot": target}
	if from_slot != "":
		# Mover entre ranuras compatibles (anillo 1 <-> anillo 2).
		if replaced != "" and not can_equip_in(replaced, from_slot):
			return {"ok": false, "reason": "invalid_swap", "slot": target}
		equipped[from_slot] = replaced
	elif bi >= 0:
		if replaced != "":
			backpack[bi] = replaced
		else:
			backpack.remove_at(bi)
	else:
		if replaced != "":
			secure[si] = replaced
		else:
			secure.remove_at(si)
	equipped[target] = item_id
	items[item_id]["new"] = false
	equipment_changed.emit(target)
	if from_slot != "":
		equipment_changed.emit(from_slot)
	backpack_changed.emit()
	stats_changed.emit()
	return {"ok": true, "reason": "", "slot": target, "replaced_id": replaced}


## Quita la pieza de la ranura y la deja en la mochila (o en `index` si se indica).
func unequip(slot: String, index: int = -1) -> bool:
	var iid := str(equipped.get(slot, ""))
	if iid == "" or backpack.size() >= backpack_capacity:
		return false
	equipped[slot] = ""
	if index >= 0 and index <= backpack.size():
		backpack.insert(index, iid)
	else:
		backpack.append(iid)
	equipment_changed.emit(slot)
	backpack_changed.emit()
	stats_changed.emit()
	return true


## Mochila <-> bolsa segura.
func move_to_secure(item_id: String) -> bool:
	var bi := backpack.find(item_id)
	if bi < 0 or secure.size() >= secure_capacity:
		return false
	backpack.remove_at(bi)
	secure.append(item_id)
	backpack_changed.emit()
	return true


func move_from_secure(item_id: String) -> bool:
	var si := secure.find(item_id)
	if si < 0 or backpack.size() >= backpack_capacity:
		return false
	secure.remove_at(si)
	backpack.append(item_id)
	backpack_changed.emit()
	return true


func is_secure(item_id: String) -> bool:
	return secure.has(item_id)


## Lo que se perdería al morir en una zona peligrosa: la mochila salvo la bolsa segura.
## (No muta: la pérdida real la resuelve el servidor.)
func preview_death_loss(dangerous_zone: bool = true) -> Array[String]:
	var out: Array[String] = []
	if not dangerous_zone:
		return out
	for iid in backpack:
		out.append(iid)
	return out


## Reordena la mochila (arrastrar dentro de la cuadrícula).
func move_in_backpack(item_id: String, to_index: int) -> bool:
	var bi := backpack.find(item_id)
	if bi < 0:
		return false
	backpack.remove_at(bi)
	backpack.insert(clampi(to_index, 0, backpack.size()), item_id)
	backpack_changed.emit()
	return true


## Ordenar [R]: equipo por rareza y nivel, luego consumibles, materiales y misión.
func sort_backpack() -> void:
	var cat_rank := {"weapon": 0, "armor": 1, "consumable": 2, "material": 3, "quest": 4}
	backpack.sort_custom(func(a: String, b: String) -> bool:
		var ia: Dictionary = items[a]
		var ib: Dictionary = items[b]
		var ca: int = cat_rank.get(ia["category"], 9)
		var cb: int = cat_rank.get(ib["category"], 9)
		if ca != cb:
			return ca < cb
		var ra := RARITY_ORDER.find(ia["rarity"])
		var rb := RARITY_ORDER.find(ib["rarity"])
		if ra != rb:
			return ra > rb
		if ia["item_level"] != ib["item_level"]:
			return ia["item_level"] > ib["item_level"]
		return str(ia["name"]) < str(ib["name"]))
	backpack_changed.emit()


# ==========================================================================
# Filtros y búsqueda
# ==========================================================================
func matches_filter(item_id: String, filter_id: String) -> bool:
	if filter_id == "" or filter_id == "all":
		return true
	return str(get_item(item_id).get("category", "")) == filter_id


func count_for_filter(filter_id: String) -> int:
	var n := 0
	for iid in backpack:
		if matches_filter(iid, filter_id):
			n += 1
	return n


static func normalize_text(s: String) -> String:
	var out := s.to_lower()
	var map := {"á": "a", "é": "e", "í": "i", "ó": "o", "ú": "u", "ü": "u", "ñ": "n"}
	for k in map:
		out = out.replace(k, map[k])
	return out


func _haystack(item_id: String) -> String:
	var it := get_item(item_id)
	var parts: Array[String] = [str(it.get("name", "")), str(CATEGORY_NAMES.get(it.get("category", ""), "")), rarity_name(str(it.get("rarity", "")))]
	var slot := str(it.get("slot", ""))
	if slot != "":
		for s in valid_slots_for(item_id):
			parts.append(slot_name(s))
		if slot == "ring":
			parts.append("anillo")
	for k in it.get("stats", {}):
		var info := T.stat(k)
		parts.append(str(info.get("name", "")))
		parts.append(str(info.get("abbr", "")))
	return normalize_text(" ".join(parts))


## Coincidencia por palabras (sin tildes, singular/plural, sin palabras vacías).
func matches_query(item_id: String, query: String) -> bool:
	var q := normalize_text(query).strip_edges()
	if q == "":
		return true
	var hay := _haystack(item_id)
	for tok in q.split(" ", false):
		if STOPWORDS.has(tok) or tok.is_valid_float():
			continue
		tok = tok.trim_suffix("%")
		if tok == "":
			continue
		if hay.contains(tok):
			continue
		if tok.length() > 4 and tok.ends_with("es") and hay.contains(tok.left(tok.length() - 2)):
			continue
		if tok.length() > 3 and tok.ends_with("s") and hay.contains(tok.left(tok.length() - 1)):
			continue
		return false
	return true


## Mochila filtrada por categoría y texto (en el orden de la mochila).
func filter_backpack(filter_id: String = "all", query: String = "") -> Array[String]:
	var out: Array[String] = []
	for iid in backpack:
		if matches_filter(iid, filter_id) and matches_query(iid, query):
			out.append(iid)
	return out


# ==========================================================================
# Conjuntos de equipo
# ==========================================================================
func get_set(set_id: String) -> Dictionary:
	for s in sets:
		if s["id"] == set_id:
			return s
	return {}


func get_set_ids() -> Array[String]:
	var out: Array[String] = []
	for s in sets:
		out.append(str(s["id"]))
	return out


## F1 -> "damage", F2 -> "tank", F3 -> "gathering" ("" si no hay).
func set_for_key(keycode: int) -> String:
	var label := str(SET_KEYS.get(keycode, ""))
	if label == "":
		return ""
	for s in sets:
		if s["key"] == label:
			return s["id"]
	return ""


## Guarda lo equipado ahora mismo en el conjunto.
func save_set(set_id: String) -> bool:
	for s in sets:
		if s["id"] == set_id:
			var slots := {}
			for slot in SLOT_ORDER:
				if equipped[slot] != "":
					slots[slot] = equipped[slot]
			s["slots"] = slots
			active_set = set_id
			sets_updated.emit()
			set_changed.emit(set_id)
			return true
	return false


## «+»: crea un conjunto nuevo con lo equipado. Devuelve su id ("" si se llegó al máximo).
func create_set(set_name: String = "") -> String:
	if sets.size() >= MAX_SETS:
		return ""
	_custom_counter += 1
	var sid := "custom_%d" % _custom_counter
	while not get_set(sid).is_empty():
		_custom_counter += 1
		sid = "custom_%d" % _custom_counter
	sets.append({"id": sid, "name": set_name if set_name != "" else "Conjunto %d" % sets.size(), "key": "", "slots": {}})
	save_set(sid)
	return sid


## Equipa las piezas del conjunto que estén disponibles (mochila, bolsa segura u otra ranura).
## Las ranuras que el conjunto no define se quedan como están.
## {ok, set_id, equipped: [slot], missing: [item_id]}
func apply_set(set_id: String) -> Dictionary:
	var s := get_set(set_id)
	if s.is_empty():
		return {"ok": false, "set_id": set_id, "equipped": [], "missing": []}
	var done: Array[String] = []
	var missing: Array[String] = []
	var slots: Dictionary = s["slots"]
	for slot in SLOT_ORDER:
		if not slots.has(slot):
			continue
		var iid := str(slots[slot])
		if iid == "" or equipped[slot] == iid:
			continue
		var owned := items.has(iid) and (is_equipped(iid) or backpack.has(iid) or secure.has(iid))
		if not owned:
			missing.append(iid)
			continue
		if equip(iid, slot)["ok"]:
			done.append(slot)
		else:
			missing.append(iid)
	active_set = set_id
	set_changed.emit(set_id)
	return {"ok": true, "set_id": set_id, "equipped": done, "missing": missing}


## Atajo F1/F2/F3. Devuelve el resultado de apply_set o {} si la tecla no es de conjunto.
func handle_set_key(keycode: int) -> Dictionary:
	var sid := set_for_key(keycode)
	if sid == "":
		return {}
	return apply_set(sid)
