extends Node
## CraftingService — Fabricación y Forja del Refugio (UI v2.4 Paso 11).
## Referencia: design_ref/pantallas_html/MMO-Fabricacion.html · PROMPT_ANTIGRAVITY §2.1, §2.5 y Anexo E.
##
## - Profesiones: Herrería (`blacksmithing`), Alquimia (`alchemy`) y Cocina (`cooking`), cada
##   una con su maestría (p. ej. «Herrería de grieta» 142/300).
## - Recetas dirigidas por datos (`config/crafting/crafting_seed.json`): nivel requerido, tiempo
##   por unidad, materiales, rango de iLvl y distribución base de calidades
##   (normal · buena · rara · épica · legendaria; siempre suma 100).
## - Modificadores de calidad:
##     · Material mejorado (p. ej. Lingote ★★★ en lugar de ★★): mueve `shift` puntos a «Épica».
##     · Catalizador de grieta (opcional, 1 por lote): +15 puntos repartidos entre Épica y
##       Legendaria (2/3 y 1/3 si la receta admite legendaria; todo a Épica si no).
##   Los puntos se quitan de las calidades más bajas primero.
## - «Fabricar ahora» (`craft_now`) exige estar en un banco de trabajo y es inmediato.
## - «Añadir a la cola de la Forja» (`queue_craft_in_shelter`) consume los materiales al
##   encolar y trabaja en segundo plano: `tick(s)` (tiempo real en el autoload) y
##   `apply_offline(s)` (desconectado, tope de 12 h — §2.5 «Nunca castigar por no entrar»).
##   Lo terminado queda en la salida de la Forja hasta `collect_forge_output()`.
##
## Instanciable con `.new()` (tests, sin reloj real) y como autoload `CraftingService`.

const DEFAULT_SEED_PATH := "res://config/crafting/crafting_seed.json"

const PROFESSION_IDS: Array[String] = ["blacksmithing", "alchemy", "cooking"]
const QUALITY_ORDER: Array[String] = ["normal", "good", "rare", "epic", "legendary"]
const QUALITIES := {
	"normal": {"name": "Normal", "color": "#3a4a54"},
	"good": {"name": "Buena", "color": "#2b6a4a"},
	"rare": {"name": "Rara", "color": "#2b4a8a"},
	"epic": {"name": "Épica", "color": "#5b3a8a"},
	"legendary": {"name": "Legendaria", "color": "#8a6a2b"},
}
## Rarezas de objetos/recetas: borde cromático y color del nombre (MMO-Fabricacion.html).
const RARITY_ORDER: Array[String] = ["common", "uncommon", "rare", "epic", "legendary"]
const RARITIES := {
	"common": {"name": "común", "color": "#b8c3ca", "bg": "#121a20"},
	"uncommon": {"name": "poco común", "color": "#4fe39a", "bg": "#10221a"},
	"rare": {"name": "raro", "color": "#5aa9ff", "bg": "#101c30"},
	"epic": {"name": "épico", "color": "#b47bff", "bg": "#1a1430"},
	"legendary": {"name": "legendario", "color": "#f5a742", "bg": "#2a1d0c"},
}
const COLOR_OK := Color("#4fe39a")
const COLOR_BAD := Color("#ff8a8a")
const COLOR_MUTED := Color("#9aa6ae")
const COLOR_WARN := Color("#f5c35b")
const DEFAULT_OFFLINE_CAP_H := 12.0

signal crafted(recipe_id: String, results: Array)
signal queue_changed
signal job_completed(job: Dictionary)
signal inventory_changed
signal mastery_changed(profession: String, value: int)
signal forge_changed(level: int)

var at_workbench: bool = true
var forge: Dictionary = {}
var professions: Dictionary = {}          # id -> {id, name, mastery_name, mastery, mastery_max}
var materials: Dictionary = {}            # id -> {name, rarity, price, ...}
var modifiers: Dictionary = {}            # id -> {name, desc, epic_legendary_bonus}
var recipes: Dictionary = {}              # id -> Dictionary normalizado
var recipe_order: Array[String] = []
var inventory: Dictionary = {}            # mochila: material_id -> int
var bank: Dictionary = {}                 # banco del refugio: material_id -> int
var queue: Array[Dictionary] = []         # trabajos de la Forja (solo el primero avanza)
var forge_output: Array[Dictionary] = []  # terminado, esperando recogida
var crafted_items: Array[Dictionary] = [] # objetos fabricados ya en la mochila
## Reloj real: solo el autoload avanza la cola con `_process`.
var realtime: bool = false
var rng := RandomNumberGenerator.new()
var crafter_seal: String = "Tú"

var _job_serial := 0


func _init() -> void:
	reset()


func _ready() -> void:
	if recipes.is_empty() and FileAccess.file_exists(DEFAULT_SEED_PATH):
		load_seed(DEFAULT_SEED_PATH)
	if get_parent() == get_tree().root and name == "CraftingService":
		realtime = true
		rng.randomize()
	set_process(realtime)


func _process(delta: float) -> void:
	if realtime and not queue.is_empty():
		tick(delta)


func reset() -> void:
	at_workbench = true
	forge = {"name": "Forja de tu refugio", "level": 1, "base_queue_slots": 2, "slots_per_level": 1, "offline_cap_h": DEFAULT_OFFLINE_CAP_H, "color": "#ff9a4d"}
	professions.clear()
	materials.clear()
	modifiers.clear()
	recipes.clear()
	recipe_order.clear()
	inventory.clear()
	bank.clear()
	queue.clear()
	forge_output.clear()
	crafted_items.clear()
	_job_serial = 0
	rng.seed = 1234


# ==========================================================================
# Datos
# ==========================================================================
func load_seed(path: String = DEFAULT_SEED_PATH) -> bool:
	if not FileAccess.file_exists(path):
		push_warning("[CraftingService] Seed no encontrado: " + path)
		return false
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY:
		push_warning("[CraftingService] Seed inválido: " + path)
		return false
	load_from_dict(data)
	return true


func load_from_dict(data: Dictionary) -> void:
	reset()
	at_workbench = bool(data.get("at_workbench", true))
	for k in data.get("forge", {}):
		forge[k] = data["forge"][k]
	for p in data.get("professions", []):
		var pid := str(p["id"])
		professions[pid] = {
			"id": pid, "name": str(p.get("name", pid)), "mastery_name": str(p.get("mastery_name", p.get("name", pid))),
			"mastery": int(p.get("mastery", 0)), "mastery_max": max(1, int(p.get("mastery_max", 300))),
		}
	for mid in data.get("materials", {}):
		var m: Dictionary = data["materials"][mid]
		materials[mid] = {"id": mid, "name": str(m.get("name", mid)), "rarity": str(m.get("rarity", "common")),
			"price": int(m.get("price", 0)), "stars": int(m.get("stars", 0)), "catalyst": bool(m.get("catalyst", false))}
	for mid in data.get("modifiers", {}):
		var md: Dictionary = data["modifiers"][mid]
		modifiers[mid] = {"id": mid, "name": str(md.get("name", mid)), "desc": str(md.get("desc", "")),
			"epic_legendary_bonus": int(md.get("epic_legendary_bonus", 0))}
	for r in data.get("recipes", []):
		_add_recipe(r)
	for k in data.get("inventory", {}):
		inventory[k] = int(data["inventory"][k])
	for k in data.get("bank", {}):
		bank[k] = int(data["bank"][k])
	for j in data.get("queue", []):
		var job := _make_job(str(j["recipe_id"]), int(j.get("qty", 1)), "", [])
		if job.is_empty():
			continue
		job["elapsed_s"] = clampf(float(j.get("elapsed_s", 0.0)), 0.0, float(job["duration_s"]))
		_update_done_units(job)
		queue.append(job)


func _add_recipe(r: Dictionary) -> void:
	var rid := str(r["id"])
	var q := {}
	for k in QUALITY_ORDER:
		q[k] = int(r.get("qualities", {}).get(k, 0))
	var mats: Array[Dictionary] = []
	for m in r.get("materials", []):
		var entry := {"id": str(m["id"]), "qty": max(1, int(m.get("qty", 1)))}
		if m.has("upgrade"):
			entry["upgrade"] = {"id": str(m["upgrade"]["id"]), "shift": int(m["upgrade"].get("shift", 0))}
		mats.append(entry)
	var il: Array = r.get("ilvl", [0, 0])
	recipes[rid] = {
		"id": rid, "name": str(r.get("name", rid)), "profession": str(r.get("profession", "blacksmithing")),
		"type": str(r.get("type", "")), "rarity": str(r.get("rarity", "common")), "level_req": int(r.get("level_req", 1)),
		"time_s": maxf(0.1, float(r.get("time_s", 10.0))), "ilvl": [int(il[0]), int(il[1])],
		"mastery_xp": int(r.get("mastery_xp", 1)), "materials": mats, "qualities": q,
		"max_quality": str(r.get("max_quality", "legendary")), "locked": bool(r.get("locked", false)),
		"source": str(r.get("source", "")), "output_material": str(r.get("output_material", "")),
	}
	recipe_order.append(rid)


func get_recipe(recipe_id: String) -> Dictionary:
	return recipes.get(recipe_id, {})


func get_material(material_id: String) -> Dictionary:
	return materials.get(material_id, {})


func material_name(material_id: String) -> String:
	return str(materials.get(material_id, {}).get("name", material_id))


func get_profession(pid: String) -> Dictionary:
	var p: Dictionary = professions.get(pid, {})
	if p.is_empty():
		return {}
	var out := p.duplicate()
	out["ratio"] = float(p["mastery"]) / float(p["mastery_max"])
	return out


func list_recipes(profession: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for rid in recipe_order:
		if recipes[rid]["profession"] == profession:
			out.append(recipes[rid])
	return out


static func rarity_color(rarity: String) -> Color:
	return Color(RARITIES.get(rarity, RARITIES["common"])["color"])


static func rarity_bg(rarity: String) -> Color:
	return Color(RARITIES.get(rarity, RARITIES["common"])["bg"])


static func rarity_name(rarity: String) -> String:
	return str(RARITIES.get(rarity, RARITIES["common"])["name"])


static func quality_name(q: String) -> String:
	return str(QUALITIES.get(q, QUALITIES["normal"])["name"])


static func quality_color(q: String) -> Color:
	return Color(QUALITIES.get(q, QUALITIES["normal"])["color"])


# ==========================================================================
# Forja del Refugio
# ==========================================================================
func forge_level() -> int:
	return int(forge.get("level", 1))


func set_forge_level(level: int) -> void:
	forge["level"] = max(1, level)
	forge_changed.emit(forge_level())
	queue_changed.emit()


func queue_slots() -> int:
	return int(forge.get("base_queue_slots", 2)) + int(forge.get("slots_per_level", 1)) * forge_level()


func offline_cap_s() -> float:
	return float(forge.get("offline_cap_h", DEFAULT_OFFLINE_CAP_H)) * 3600.0


## «Forja de tu refugio · nivel 2 · trabaja aunque no estés»
func forge_banner() -> String:
	return "%s · nivel %d · trabaja aunque no estés" % [str(forge.get("name", "Forja de tu refugio")), forge_level()]


## Toma el nivel de la Forja del Refugio (sala «forja» de mayor nivel) si existe.
func sync_with_shelter(shelter: Node) -> bool:
	if shelter == null or not shelter.has_method("find_rooms"):
		return false
	var best := 0
	for r in shelter.find_rooms("forja"):
		best = max(best, int(r.get("level", 1)))
	if best <= 0:
		return false
	set_forge_level(best)
	return true


# ==========================================================================
# Materiales
# ==========================================================================
func have_inventory(material_id: String) -> int:
	return int(inventory.get(material_id, 0))


func have_bank(material_id: String) -> int:
	return int(bank.get(material_id, 0))


func have(material_id: String) -> int:
	return have_inventory(material_id) + have_bank(material_id)


func add_material(material_id: String, qty: int, to_bank: bool = false) -> void:
	if qty <= 0:
		return
	var d := bank if to_bank else inventory
	d[material_id] = int(d.get(material_id, 0)) + qty
	inventory_changed.emit()


## Consume de la mochila primero y luego del banco. false (sin cambios) si no alcanza.
func consume_material(material_id: String, qty: int) -> bool:
	if qty <= 0:
		return true
	if have(material_id) < qty:
		return false
	var from_inv: int = min(qty, have_inventory(material_id))
	inventory[material_id] = have_inventory(material_id) - from_inv
	var rest := qty - from_inv
	if rest > 0:
		bank[material_id] = have_bank(material_id) - rest
	inventory_changed.emit()
	return true


## Materiales efectivos de una receta: [{id, qty, base_id, upgraded}] (con mejoras aplicadas).
func effective_materials(recipe_id: String, upgrades: Array = []) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var r := get_recipe(recipe_id)
	for m in r.get("materials", []):
		var up: bool = m.has("upgrade") and upgrades.has(m["id"])
		out.append({"id": m["upgrade"]["id"] if up else m["id"], "qty": m["qty"], "base_id": m["id"], "upgraded": up})
	return out


func max_craftable(recipe_id: String, upgrades: Array = []) -> int:
	var r := get_recipe(recipe_id)
	if r.is_empty():
		return 0
	var best := 1 << 30
	for m in effective_materials(recipe_id, upgrades):
		best = min(best, have(m["id"]) / int(m["qty"]))
	return 0 if best == 1 << 30 else best


## Unidades de material que faltan para `qty` fabricaciones.
func missing_units(recipe_id: String, qty: int = 1, upgrades: Array = []) -> int:
	var total := 0
	for m in effective_materials(recipe_id, upgrades):
		total += max(0, int(m["qty"]) * qty - have(m["id"]))
	return total


## Filas de materiales del detalle: poseído / necesario y de dónde sale.
func material_rows(recipe_id: String, qty: int = 1, upgrades: Array = []) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	qty = max(1, qty)
	for m in effective_materials(recipe_id, upgrades):
		var mid: String = m["id"]
		var need: int = int(m["qty"]) * qty
		var inv := have_inventory(mid)
		var total := have(mid)
		var mat := get_material(mid)
		var source := "inventario"
		if inv < need:
			source = "inventario + banco" if total >= need else "mercado · %d c/u" % int(mat.get("price", 0))
		out.append({
			"id": mid, "base_id": m["base_id"], "upgraded": m["upgraded"], "name": material_name(mid),
			"rarity": str(mat.get("rarity", "common")), "have": total, "need": need, "ok": total >= need,
			"missing": max(0, need - total), "source": source, "price": int(mat.get("price", 0)),
		})
	return out


func missing_cost(recipe_id: String, qty: int = 1, upgrades: Array = []) -> int:
	var cost := 0
	for row in material_rows(recipe_id, qty, upgrades):
		cost += int(row["missing"]) * int(row["price"])
	return cost


## «Comprar lo que falta»: cobra en oro (CommerceService) y añade los materiales a la mochila.
func buy_missing(recipe_id: String, qty: int, commerce: Node, upgrades: Array = []) -> Dictionary:
	var cost := missing_cost(recipe_id, qty, upgrades)
	if cost <= 0:
		return {"ok": false, "reason": "nothing_missing", "cost": 0}
	if commerce == null or not commerce.has_method("spend_gold"):
		return {"ok": false, "reason": "no_wallet", "cost": cost}
	if not commerce.spend_gold(cost):
		return {"ok": false, "reason": "not_enough_gold", "cost": cost}
	for row in material_rows(recipe_id, qty, upgrades):
		if int(row["missing"]) > 0:
			inventory[row["id"]] = have_inventory(row["id"]) + int(row["missing"])
	inventory_changed.emit()
	return {"ok": true, "cost": cost}


## Cuadrícula de materiales disponibles en la mochila (rareza desc, nombre).
func get_material_grid() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for mid in inventory:
		var n := have_inventory(mid)
		if n <= 0:
			continue
		var mat := get_material(mid)
		out.append({"id": mid, "name": material_name(mid), "rarity": str(mat.get("rarity", "common")), "count": n,
			"catalyst": bool(mat.get("catalyst", false))})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ra := RARITY_ORDER.find(a["rarity"])
		var rb := RARITY_ORDER.find(b["rarity"])
		return ra > rb if ra != rb else str(a["name"]) < str(b["name"]))
	return out


# ==========================================================================
# Disponibilidad (badges de la lista de recetas)
# ==========================================================================
func meets_level(recipe_id: String) -> bool:
	var r := get_recipe(recipe_id)
	if r.is_empty():
		return false
	return int(professions.get(r["profession"], {}).get("mastery", 0)) >= int(r["level_req"])


## {state: locked|mastery|can|missing, text, color, count}
func recipe_badge(recipe_id: String) -> Dictionary:
	var r := get_recipe(recipe_id)
	if r.is_empty():
		return {"state": "unknown", "text": "", "color": COLOR_MUTED, "count": 0}
	if bool(r["locked"]):
		var txt := "Receta: botín de raid" if r["source"] == "raid_loot" else "Receta bloqueada"
		return {"state": "locked", "text": txt, "color": COLOR_MUTED, "count": 0}
	if not meets_level(recipe_id):
		return {"state": "mastery", "text": "Requiere maestría %d" % int(r["level_req"]), "color": COLOR_WARN, "count": 0}
	var n := max_craftable(recipe_id)
	if n > 0:
		return {"state": "can", "text": "Puedes crear %d" % n, "color": COLOR_OK, "count": n}
	var miss := missing_units(recipe_id, 1)
	var t := "Falta 1 material" if miss == 1 else "Faltan %d materiales" % miss
	return {"state": "missing", "text": t, "color": COLOR_MUTED, "count": miss}


# ==========================================================================
# Calidad
# ==========================================================================
func quality_allowed(recipe_id: String, q: String) -> bool:
	var r := get_recipe(recipe_id)
	if r.is_empty():
		return false
	return QUALITY_ORDER.find(q) <= QUALITY_ORDER.find(str(r["max_quality"]))


func can_use_catalyst(recipe_id: String, catalyst_id: String = "catalizador_grieta") -> bool:
	return modifiers.has(catalyst_id) and quality_allowed(recipe_id, "epic")


## Distribución de calidad probable (puntos %, suma 100) con mejoras de material y catalizador.
func quality_distribution(recipe_id: String, catalyst_id: String = "", upgrades: Array = []) -> Dictionary:
	var r := get_recipe(recipe_id)
	var dist := {}
	for k in QUALITY_ORDER:
		dist[k] = 0
	if r.is_empty():
		return dist
	for k in QUALITY_ORDER:
		dist[k] = int(r["qualities"][k])
	var top := "epic" if quality_allowed(recipe_id, "epic") else str(r["max_quality"])
	for m in r["materials"]:
		if m.has("upgrade") and upgrades.has(m["id"]):
			_shift_to(dist, {top: int(m["upgrade"]["shift"])})
	if catalyst_id != "" and can_use_catalyst(recipe_id, catalyst_id):
		var bonus := int(modifiers[catalyst_id]["epic_legendary_bonus"])
		if quality_allowed(recipe_id, "legendary"):
			var leg := int(round(bonus / 3.0))
			_shift_to(dist, {"epic": bonus - leg, "legendary": leg})
		else:
			_shift_to(dist, {"epic": bonus})
	return dist


## Mueve puntos a las calidades `targets` quitándolos de las más bajas (que no sean objetivo).
func _shift_to(dist: Dictionary, targets: Dictionary) -> void:
	for t in targets:
		var want := int(targets[t])
		for k in QUALITY_ORDER:
			if want <= 0:
				break
			if targets.has(k):
				continue
			var take: int = min(want, int(dist[k]))
			dist[k] = int(dist[k]) - take
			dist[t] = int(dist[t]) + take
			want -= take


## Lanza una calidad según la distribución (rng del servicio, determinista en tests).
func roll_quality(dist: Dictionary) -> String:
	var roll := rng.randi_range(1, 100)
	var acc := 0
	for k in QUALITY_ORDER:
		acc += int(dist.get(k, 0))
		if roll <= acc:
			return k
	for i in range(QUALITY_ORDER.size() - 1, -1, -1):
		if int(dist.get(QUALITY_ORDER[i], 0)) > 0:
			return QUALITY_ORDER[i]
	return "normal"


func ilvl_for_quality(recipe_id: String, q: String) -> int:
	var r := get_recipe(recipe_id)
	if r.is_empty() or int(r["ilvl"][1]) <= 0:
		return 0
	var t := float(max(0, QUALITY_ORDER.find(q))) / float(QUALITY_ORDER.size() - 1)
	return int(round(lerpf(float(r["ilvl"][0]), float(r["ilvl"][1]), t)))


## «Arma · Nv. obj. 410–425 según calidad · 45 s por unidad»
func recipe_subtitle(recipe_id: String) -> String:
	var r := get_recipe(recipe_id)
	if r.is_empty():
		return ""
	var parts: Array[String] = [str(r["type"])]
	if int(r["ilvl"][1]) > 0:
		parts.append("Nv. obj. %d–%d según calidad" % [int(r["ilvl"][0]), int(r["ilvl"][1])])
	parts.append("%s s por unidad" % _fmt_seconds_short(float(r["time_s"])))
	return " · ".join(parts)


## Pista de mejora: {material, upgrade, quality, pct, text} o {} si la receta no tiene.
func upgrade_hint(recipe_id: String, catalyst_id: String = "") -> Dictionary:
	var r := get_recipe(recipe_id)
	for m in r.get("materials", []):
		if not m.has("upgrade"):
			continue
		var top := "epic" if quality_allowed(recipe_id, "epic") else str(r["max_quality"])
		var pct := int(quality_distribution(recipe_id, catalyst_id, [m["id"]])[top])
		var base_name := material_name(m["id"]).replace(" ★★", "")
		var up_mat := get_material(m["upgrade"]["id"])
		var stars := "★".repeat(int(up_mat.get("stars", 3)))
		return {"material": m["id"], "upgrade": m["upgrade"]["id"], "quality": top, "pct": pct,
			"text": "Cambiar el %s por calidad %s sube «%s» a %d %%." % [base_name, stars, quality_name(top), pct]}
	return {}


# ==========================================================================
# Fabricar
# ==========================================================================
func _validate(recipe_id: String, qty: int, catalyst_id: String, upgrades: Array) -> String:
	var r := get_recipe(recipe_id)
	if r.is_empty():
		return "unknown_recipe"
	if bool(r["locked"]):
		return "recipe_locked"
	if not meets_level(recipe_id):
		return "mastery_too_low"
	if qty < 1:
		return "invalid_qty"
	if max_craftable(recipe_id, upgrades) < qty:
		return "missing_materials"
	if catalyst_id != "":
		if not can_use_catalyst(recipe_id, catalyst_id):
			return "catalyst_not_applicable"
		var need := 1
		for m in effective_materials(recipe_id, upgrades):
			if m["id"] == catalyst_id:
				need += int(m["qty"]) * qty
		if have(catalyst_id) < need:
			return "missing_catalyst"
	return ""


func _consume_for(recipe_id: String, qty: int, catalyst_id: String, upgrades: Array) -> void:
	for m in effective_materials(recipe_id, upgrades):
		consume_material(m["id"], int(m["qty"]) * qty)
	if catalyst_id != "":
		consume_material(catalyst_id, 1)


func _produce(recipe_id: String, qty: int, catalyst_id: String, upgrades: Array) -> Array[Dictionary]:
	var r := get_recipe(recipe_id)
	var dist := quality_distribution(recipe_id, catalyst_id, upgrades)
	var out: Array[Dictionary] = []
	for i in qty:
		var q := roll_quality(dist)
		out.append({"recipe_id": recipe_id, "name": r["name"], "quality": q, "quality_name": quality_name(q),
			"ilvl": ilvl_for_quality(recipe_id, q), "rarity": r["rarity"], "seal": crafter_seal,
			"output_material": r["output_material"]})
	return out


func _gain_mastery(recipe_id: String, qty: int) -> void:
	var r := get_recipe(recipe_id)
	var p: Dictionary = professions.get(r["profession"], {})
	if p.is_empty():
		return
	p["mastery"] = min(int(p["mastery_max"]), int(p["mastery"]) + int(r["mastery_xp"]) * qty)
	mastery_changed.emit(r["profession"], int(p["mastery"]))


func _deliver_to_inventory(results: Array) -> void:
	for it in results:
		if str(it.get("output_material", "")) != "":
			inventory[it["output_material"]] = have_inventory(it["output_material"]) + 1
		else:
			crafted_items.append(it)
	inventory_changed.emit()


## «Fabricar ahora»: inmediato, solo en un banco de trabajo.
func craft_now(recipe_id: String, qty: int = 1, catalyst_id: String = "", upgrades: Array = []) -> Dictionary:
	if not at_workbench:
		return {"ok": false, "reason": "not_at_workbench"}
	var err := _validate(recipe_id, qty, catalyst_id, upgrades)
	if err != "":
		return {"ok": false, "reason": err}
	_consume_for(recipe_id, qty, catalyst_id, upgrades)
	var results := _produce(recipe_id, qty, catalyst_id, upgrades)
	_deliver_to_inventory(results)
	_gain_mastery(recipe_id, qty)
	crafted.emit(recipe_id, results)
	return {"ok": true, "results": results}


func _make_job(recipe_id: String, qty: int, catalyst_id: String, upgrades: Array) -> Dictionary:
	var r := get_recipe(recipe_id)
	if r.is_empty():
		return {}
	_job_serial += 1
	return {
		"job_id": "job_%d" % _job_serial, "recipe_id": recipe_id, "name": r["name"], "qty": qty,
		"time_s": float(r["time_s"]), "duration_s": float(r["time_s"]) * qty, "elapsed_s": 0.0,
		"done_units": 0, "catalyst": catalyst_id, "upgrades": upgrades.duplicate(),
	}


## «Añadir a la cola de la Forja»: consume los materiales ahora y trabaja en segundo plano.
func queue_craft_in_shelter(recipe_id: String, qty: int = 1, catalyst_id: String = "", upgrades: Array = []) -> Dictionary:
	if queue.size() >= queue_slots():
		return {"ok": false, "reason": "queue_full"}
	var err := _validate(recipe_id, qty, catalyst_id, upgrades)
	if err != "":
		return {"ok": false, "reason": err}
	_consume_for(recipe_id, qty, catalyst_id, upgrades)
	var job := _make_job(recipe_id, qty, catalyst_id, upgrades)
	queue.append(job)
	queue_changed.emit()
	return {"ok": true, "job_id": job["job_id"], "job": job}


## Cancela un trabajo y devuelve los materiales de las unidades no terminadas.
func cancel_job(job_id: String) -> Dictionary:
	for i in queue.size():
		var job: Dictionary = queue[i]
		if job["job_id"] != job_id:
			continue
		var left := int(job["qty"]) - int(job["done_units"])
		for m in effective_materials(job["recipe_id"], job["upgrades"]):
			add_material(m["id"], int(m["qty"]) * left)
		if str(job["catalyst"]) != "" and int(job["done_units"]) == 0:
			add_material(job["catalyst"], 1)
		if int(job["done_units"]) > 0:
			forge_output.append_array(_produce(job["recipe_id"], int(job["done_units"]), job["catalyst"], job["upgrades"]))
		queue.remove_at(i)
		queue_changed.emit()
		return {"ok": true, "refunded_units": left}
	return {"ok": false, "reason": "unknown_job"}


func _update_done_units(job: Dictionary) -> void:
	job["done_units"] = min(int(job["qty"]), int(floor((float(job["elapsed_s"]) + 0.0001) / float(job["time_s"]))))


## Avanza la Forja `seconds`. Solo trabaja el primero de la cola; el sobrante pasa al siguiente.
## Devuelve los trabajos terminados.
func tick(seconds: float) -> Array[Dictionary]:
	var done: Array[Dictionary] = []
	var remaining := maxf(0.0, seconds)
	while remaining > 0.0 and not queue.is_empty():
		var job: Dictionary = queue[0]
		var need := float(job["duration_s"]) - float(job["elapsed_s"])
		if remaining + 0.0001 >= need:
			remaining -= need
			job["elapsed_s"] = float(job["duration_s"])
			job["done_units"] = int(job["qty"])
			job["results"] = _produce(job["recipe_id"], int(job["qty"]), job["catalyst"], job["upgrades"])
			forge_output.append_array(job["results"])
			_gain_mastery(job["recipe_id"], int(job["qty"]))
			queue.remove_at(0)
			done.append(job)
			job_completed.emit(job)
		else:
			job["elapsed_s"] = float(job["elapsed_s"]) + remaining
			_update_done_units(job)
			remaining = 0.0
	if not done.is_empty():
		queue_changed.emit()
	return done


## Tiempo desconectado: la Forja sigue trabajando con tope de 12 h (nada se pierde).
func apply_offline(seconds: float) -> Dictionary:
	var cap := offline_cap_s()
	var applied := clampf(seconds, 0.0, cap)
	var done := tick(applied)
	return {"applied_s": applied, "capped": seconds > cap, "completed": done}


## Recoge lo terminado en la Forja hacia la mochila.
func collect_forge_output() -> Array[Dictionary]:
	var out := forge_output.duplicate()
	forge_output.clear()
	_deliver_to_inventory(out)
	return out


func job_remaining_s(job: Dictionary) -> float:
	return maxf(0.0, float(job["duration_s"]) - float(job["elapsed_s"]))


## Tiempo hasta que termina el trabajo i (contando los anteriores de la cola).
func eta_s(index: int) -> float:
	var t := 0.0
	for i in min(index + 1, queue.size()):
		t += job_remaining_s(queue[i])
	return t


func get_queue_view() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in queue.size():
		var job: Dictionary = queue[i]
		var rem := job_remaining_s(job)
		out.append({"job_id": job["job_id"], "recipe_id": job["recipe_id"], "label": "%s ×%d" % [job["name"], int(job["qty"])],
			"remaining_s": rem, "remaining_text": format_time(rem), "eta_s": eta_s(i),
			"ratio": float(job["elapsed_s"]) / maxf(0.001, float(job["duration_s"])), "active": i == 0,
			"rarity": str(get_recipe(job["recipe_id"]).get("rarity", "common"))})
	return out


## mm:ss (o h:mm:ss a partir de una hora). Redondea hacia arriba.
static func format_time(seconds: float) -> String:
	var s := int(ceil(maxf(0.0, seconds) - 0.0001))
	if s >= 3600:
		return "%d:%02d:%02d" % [s / 3600, (s % 3600) / 60, s % 60]
	return "%02d:%02d" % [s / 60, s % 60]


static func _fmt_seconds_short(s: float) -> String:
	return str(int(s)) if is_equal_approx(s, round(s)) else ("%.1f" % s).replace(".", ",")


# ==========================================================================
# Persistencia (offline)
# ==========================================================================
func to_dict(saved_at: int = -1) -> Dictionary:
	var profs := {}
	for pid in professions:
		profs[pid] = int(professions[pid]["mastery"])
	return {
		"saved_at": saved_at if saved_at >= 0 else int(Time.get_unix_time_from_system()),
		"forge_level": forge_level(), "inventory": inventory.duplicate(), "bank": bank.duplicate(),
		"queue": queue.duplicate(true), "forge_output": forge_output.duplicate(true), "mastery": profs,
		"job_serial": _job_serial,
	}


## Restaura el estado y aplica el tiempo transcurrido desde `saved_at` como tiempo desconectado.
func load_state(d: Dictionary, now_unix: int = -1) -> Dictionary:
	forge["level"] = int(d.get("forge_level", forge_level()))
	inventory = (d.get("inventory", {}) as Dictionary).duplicate()
	bank = (d.get("bank", {}) as Dictionary).duplicate()
	queue.clear()
	for j in d.get("queue", []):
		queue.append((j as Dictionary).duplicate(true))
	forge_output.clear()
	for o in d.get("forge_output", []):
		forge_output.append((o as Dictionary).duplicate(true))
	for pid in d.get("mastery", {}):
		if professions.has(pid):
			professions[pid]["mastery"] = int(d["mastery"][pid])
	_job_serial = int(d.get("job_serial", _job_serial))
	var now := now_unix if now_unix >= 0 else int(Time.get_unix_time_from_system())
	var away: int = max(0, now - int(d.get("saved_at", now)))
	var res := apply_offline(float(away))
	queue_changed.emit()
	inventory_changed.emit()
	return res
