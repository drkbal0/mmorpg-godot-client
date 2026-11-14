extends Node
## PowersService — modelo del sistema de Poderes (UI v2.4 §2.4).
## Referencias: design_ref/pantallas_html/MMO-Talentos.html (Crisol), MMO-Atlas.html,
## MMO-Constelacion.html y design_ref/pantallas.json (pantallas 4, 16 y 16b).
##
## - Energías: lista ABIERTA. Arranca con el Anexo B de `hud_tokens.gd` y
##   `add_energy()` añade más. El Atlas y el Crisol escalan solos (N × N).
## - Afinidad por energía: sube con el uso en combate (`record_combat_use`).
## - Crisol: un poder = 2 o 3 energías + forma + ritmo (`compose_power`).
##   Las combinaciones no descubiertas se marcan «¡NUEVA!».
## - Conjunto: 1 Núcleo, 6 activos y 2 Ecos pasivos, con bonus de resonancia
##   cuando una energía se repite en varios poderes.
## - Atlas: celdas energía × energía (diagonal = pura) en estado
##   descubierta (nº de fórmulas) · pista · desconocida.
## - Constelación: árbol pasivo de la clase; las ramas son energías y cada
##   nodo suma potencia a los poderes del Crisol que usan su energía.
##
## No depende de otros autoloads: se puede instanciar con `.new()` en tests.

const T = preload("res://ui/tokens/hud_tokens.gd")

const DEFAULT_SEED_PATH := "res://config/powers/powers_seed.json"

# --- Crisol -----------------------------------------------------------------
const MIN_ENERGIES := 2
const MAX_ENERGIES := 3
const FORMS: Array[String] = ["proyectil", "area", "cono", "aura", "trampa"]
const FORM_LABELS := {"proyectil": "Proyectil", "area": "Área", "cono": "Cono", "aura": "Aura", "trampa": "Trampa"}
const RHYTHMS: Array[String] = ["instantaneo", "canalizado", "retardado"]
const RHYTHM_LABELS := {"instantaneo": "Instantáneo", "canalizado": "Canalizado", "retardado": "Retardado"}
const ROLES: Array[String] = ["dano", "control", "curacion"]
const ROLE_LABELS := {"": "Todos los roles", "dano": "Daño", "control": "Control", "curacion": "Curación"}
const POTENCY_PER_LEVEL := 3.0

# --- Conjunto -----------------------------------------------------------------
const ACTIVE_SLOTS := 6
const ECHO_SLOTS := 2
const SLOT_CORE := "core"
const SLOT_ACTIVE := "active"
const SLOT_ECHO := "echo"
## Resonancia: una energía presente en >= RESONANCE_MIN poderes (Núcleo + activos)
## da RESONANCE_PCT_PER_POWER % por poder; con RESONANCE_SET_AT activa su efecto de conjunto.
const RESONANCE_MIN := 2
const RESONANCE_PCT_PER_POWER := 2
const RESONANCE_SET_AT := 5

# --- Afinidad ---------------------------------------------------------------
const AFFINITY_MAX_LEVEL := 20
const AFFINITY_XP_STEP := 100  # pasar de nivel L a L+1 cuesta L * 100 PX

# --- Atlas --------------------------------------------------------------------
const CELL_DISCOVERED := "discovered"
const CELL_HINT := "hint"
const CELL_UNKNOWN := "unknown"
const MASK := "???"

# --- Constelación ---------------------------------------------------------------
const NODE_ACTIVE := "active"
const NODE_AVAILABLE := "available"
const NODE_LOCKED := "locked"
const SIM_SECONDS := 60
const DPS_PER_POTENCY := 9.0

signal energies_changed
signal affinity_changed(energy: String, level: int)
signal affinity_level_up(energy: String, level: int)
signal power_discovered(combo_key: String, power: Dictionary)
signal loadout_changed
signal constellation_changed
signal dummy_test_requested(power: Dictionary, result: Dictionary)

## Energías activas (orden = orden del Atlas). key -> {name, color}
var energies: Array[String] = []
var energy_info: Dictionary = {}
var affinity_xp: Dictionary = {}       # energy -> PX acumulada
var last_used: Dictionary = {}         # energy -> contador de uso (para «Uso reciente»)
var _use_serial := 0

var formulas: Dictionary = {}          # combo_key -> {id, name, energies, form, rhythm, role, desc}
var formula_ids: Dictionary = {}       # id -> combo_key
var discovered: Dictionary = {}        # combo_key -> true
var pair_hints: Dictionary = {}        # pair_key -> texto
var trio_hints: Dictionary = {}        # trio_key -> texto
var resonance_sets: Dictionary = {}    # energy -> nombre del efecto de conjunto

## Conjunto activo: cada ranura guarda un combo_key ("" = vacía).
var loadout_name: String = "Daño"
var loadout_key: String = "F1"
var core_slot: String = ""
var active_slots: Array[String] = []
var echo_slots: Array[String] = []

# Constelación
var class_title: String = "Tejedor"
var build_name: String = ""
var total_points: int = 40
var focus: Array = []
var builds: Array = []
var share_code: String = ""
var branches: Array = []
var nodes: Array[Dictionary] = []
var _node_index: Dictionary = {}       # id -> índice en nodes
var history: Array[Dictionary] = []    # cambios en la constelación (deshacer)


func _init() -> void:
	reset()
	load_seed()


func reset() -> void:
	energies.clear()
	energy_info.clear()
	for k in T.ENERGY_KEYS:
		energies.append(k)
		energy_info[k] = {"name": T.ENERGIES[k]["name"], "color": Color(T.ENERGIES[k]["color"])}
	affinity_xp.clear()
	last_used.clear()
	for k in energies:
		affinity_xp[k] = 0
	formulas.clear()
	formula_ids.clear()
	discovered.clear()
	pair_hints.clear()
	trio_hints.clear()
	resonance_sets.clear()
	core_slot = ""
	active_slots.clear()
	active_slots.resize(ACTIVE_SLOTS)
	active_slots.fill("")
	echo_slots.clear()
	echo_slots.resize(ECHO_SLOTS)
	echo_slots.fill("")
	nodes.clear()
	_node_index.clear()
	history.clear()


# ==========================================================================
# Energías (lista abierta)
# ==========================================================================
func get_energy_count() -> int:
	return energies.size()


func has_energy(key: String) -> bool:
	return energy_info.has(key)


func energy_name(key: String) -> String:
	return str(energy_info[key]["name"]) if energy_info.has(key) else key


func energy_color(key: String) -> Color:
	return energy_info[key]["color"] if energy_info.has(key) else T.TEXT_SECONDARY


## Añade una energía nueva (p. ej. de temporada). El Atlas gana una fila y una columna.
func add_energy(key: String, display_name: String, color: Color) -> bool:
	if key == "" or energy_info.has(key):
		return false
	energies.append(key)
	energy_info[key] = {"name": display_name, "color": color}
	affinity_xp[key] = 0
	energies_changed.emit()
	return true


func energy_index(key: String) -> int:
	return energies.find(key)


## Orden canónico (el del Atlas) para que «calor+vacio» y «vacio+calor» sean lo mismo.
func sort_energies(list: Array) -> Array[String]:
	var out: Array[String] = []
	for e in list:
		out.append(str(e))
	out.sort_custom(func(a: String, b: String) -> bool:
		var ia := energy_index(a)
		var ib := energy_index(b)
		if ia == ib:
			return a < b
		if ia < 0:
			return false
		if ib < 0:
			return true
		return ia < ib)
	return out


func energies_key(list: Array) -> String:
	return "+".join(sort_energies(list))


func pair_key(a: String, b: String) -> String:
	return energies_key([a, b])


func combo_key(list: Array, form: String, rhythm: String) -> String:
	return "%s|%s|%s" % [energies_key(list), form, rhythm]


## Lista de energías filtrada y ordenada para el panel del Crisol.
## sort: "affinity" (nivel desc) · "recent" (uso reciente) · "az" (alfabético).
func list_energies(query: String = "", sort: String = "affinity") -> Array[String]:
	var q := query.strip_edges().to_lower()
	var out: Array[String] = []
	for k in energies:
		if q == "" or energy_name(k).to_lower().contains(q) or k.contains(q):
			out.append(k)
	match sort:
		"affinity":
			out.sort_custom(func(a: String, b: String) -> bool:
				var la := int(affinity_xp.get(a, 0))
				var lb := int(affinity_xp.get(b, 0))
				return la > lb if la != lb else energy_index(a) < energy_index(b))
		"recent":
			out.sort_custom(func(a: String, b: String) -> bool:
				var ua := int(last_used.get(a, 0))
				var ub := int(last_used.get(b, 0))
				return ua > ub if ua != ub else energy_index(a) < energy_index(b))
		"az":
			out.sort_custom(func(a: String, b: String) -> bool: return energy_name(a).naturalnocasecmp_to(energy_name(b)) < 0)
	return out


# ==========================================================================
# Afinidad
# ==========================================================================
## PX acumulada necesaria para ALCANZAR `level` (nivel 1 = 0 PX).
static func xp_for_level(level: int) -> int:
	var l := clampi(level, 1, AFFINITY_MAX_LEVEL)
	return AFFINITY_XP_STEP * l * (l - 1) / 2


static func level_for_xp(xp: int) -> int:
	var lvl := 1
	while lvl < AFFINITY_MAX_LEVEL and xp >= xp_for_level(lvl + 1):
		lvl += 1
	return lvl


func get_affinity_level(key: String) -> int:
	return level_for_xp(int(affinity_xp.get(key, 0)))


## {level, xp, into, needed, ratio, max}: progreso dentro del nivel actual.
func get_affinity_progress(key: String) -> Dictionary:
	var xp := int(affinity_xp.get(key, 0))
	var lvl := level_for_xp(xp)
	if lvl >= AFFINITY_MAX_LEVEL:
		return {"level": lvl, "xp": xp, "into": 0, "needed": 0, "ratio": 1.0, "max": true}
	var base := xp_for_level(lvl)
	var needed := xp_for_level(lvl + 1) - base
	var into := xp - base
	return {"level": lvl, "xp": xp, "into": into, "needed": needed, "ratio": float(into) / float(needed), "max": false}


func set_affinity(key: String, level: int, progress: float = 0.0) -> void:
	if not energy_info.has(key):
		return
	var lvl := clampi(level, 1, AFFINITY_MAX_LEVEL)
	var xp := xp_for_level(lvl)
	if lvl < AFFINITY_MAX_LEVEL:
		xp += int(floor((xp_for_level(lvl + 1) - xp) * clampf(progress, 0.0, 0.999)))
	affinity_xp[key] = xp
	affinity_changed.emit(key, lvl)


## Suma PX a una energía. Devuelve los niveles ganados.
func add_affinity_xp(key: String, amount: int) -> int:
	if not energy_info.has(key) or amount <= 0:
		return 0
	var before := get_affinity_level(key)
	affinity_xp[key] = int(affinity_xp.get(key, 0)) + amount
	_use_serial += 1
	last_used[key] = _use_serial
	var after := get_affinity_level(key)
	affinity_changed.emit(key, after)
	if after > before:
		affinity_level_up.emit(key, after)
	return after - before


## Uso de un poder en combate: cada energía del poder gana `xp_per_use` PX
## (una energía repetida en el mismo poder no cuenta doble).
func record_combat_use(power_energies: Array, xp_per_use: int = 25) -> Dictionary:
	var gained := {}
	var seen := {}
	for e in power_energies:
		var k := str(e)
		if seen.has(k):
			continue
		seen[k] = true
		gained[k] = add_affinity_xp(k, xp_per_use)
	return gained


# ==========================================================================
# Crisol
# ==========================================================================
## Valida y compone un poder. Devuelve {ok, reason?, key, name, energies, form,
## rhythm, role, is_new, potency, breakdown, description}.
func compose_power(power_energies: Array, form: String, rhythm: String) -> Dictionary:
	var list: Array[String] = []
	for e in power_energies:
		if str(e) != "":
			list.append(str(e))
	if list.size() < MIN_ENERGIES:
		return {"ok": false, "reason": "too_few_energies"}
	if list.size() > MAX_ENERGIES:
		return {"ok": false, "reason": "too_many_energies"}
	for e in list:
		if not energy_info.has(e):
			return {"ok": false, "reason": "unknown_energy", "energy": e}
	if not FORMS.has(form):
		return {"ok": false, "reason": "invalid_form"}
	if not RHYTHMS.has(rhythm):
		return {"ok": false, "reason": "invalid_rhythm"}
	var sorted := sort_energies(list)
	var key := combo_key(sorted, form, rhythm)
	var f: Dictionary = formulas.get(key, {})
	var pot := compute_potency(sorted)
	return {
		"ok": true, "key": key, "id": str(f.get("id", "")),
		"name": str(f.get("name", "")) if not f.is_empty() else procedural_name(sorted, form),
		"energies": sorted, "form": form, "rhythm": rhythm,
		"role": str(f.get("role", _guess_role(form))),
		"is_new": not discovered.has(key),
		"in_catalog": not f.is_empty(),
		"potency": pot["potency"], "breakdown": pot["breakdown"], "potency_parts": pot["parts"],
		"description": str(f.get("desc", "")) if f.get("desc", "") != "" else "%s · %s." % [FORM_LABELS[form], RHYTHM_LABELS[rhythm].to_lower()],
	}


func procedural_name(sorted: Array, form: String) -> String:
	var names: Array[String] = []
	var seen := {}
	for e in sorted:
		if not seen.has(e):
			seen[e] = true
			names.append(energy_name(e))
	var tail := names[0] if names.size() == 1 else ", ".join(names.slice(0, names.size() - 1)) + " y " + names[-1]
	return "%s de %s" % [FORM_LABELS.get(form, "Poder"), tail]


func _guess_role(form: String) -> String:
	match form:
		"aura":
			return "curacion"
		"trampa", "cono":
			return "control"
	return "dano"


## Potencia = Σ (afinidad × 3) × (1 + bonus de Constelación de esa energía + general).
## Una energía repetida en el poder cuenta una vez por aparición.
func compute_potency(power_energies: Array) -> Dictionary:
	var total := 0.0
	var parts: Array[Dictionary] = []
	var general := get_constellation_general_bonus()
	var shown := {}
	var bits: Array[String] = []
	for e in power_energies:
		var k := str(e)
		var lvl := get_affinity_level(k)
		var bonus := get_constellation_bonus(k) + general
		var v := lvl * POTENCY_PER_LEVEL * (1.0 + bonus / 100.0)
		total += v
		parts.append({"energy": k, "level": lvl, "bonus_pct": bonus, "value": v})
		if not shown.has(k):
			shown[k] = true
			bits.append("%s %d" % [energy_name(k), lvl])
	var potency := roundi(total)
	return {"potency": potency, "parts": parts, "breakdown": "Potencia %d = %s (tus afinidades)" % [potency, " + ".join(bits)]}


## Marca una combinación como descubierta (la deja de mostrar como «¡NUEVA!»).
func discover_power(power: Dictionary) -> bool:
	if not power.get("ok", false):
		return false
	var key := str(power["key"])
	if discovered.has(key):
		return false
	discovered[key] = true
	if not formulas.has(key):
		var id := "custom_%d" % formulas.size()
		formulas[key] = {"id": id, "name": power["name"], "energies": power["energies"], "form": power["form"], "rhythm": power["rhythm"], "role": power["role"], "desc": ""}
		formula_ids[id] = key
	power_discovered.emit(key, power)
	return true


func is_discovered(key: String) -> bool:
	return discovered.has(key)


## «Probar en el maniquí»: simula 60 s y descubre la combinación.
func test_on_dummy(power: Dictionary) -> Dictionary:
	if not power.get("ok", false):
		return {"ok": false, "reason": power.get("reason", "invalid_power")}
	var was_new: bool = not discovered.has(str(power["key"]))
	discover_power(power)
	var dps := roundi(float(power["potency"]) * DPS_PER_POTENCY)
	var result := {"ok": true, "was_new": was_new, "dps": dps, "seconds": SIM_SECONDS, "total": dps * SIM_SECONDS}
	dummy_test_requested.emit(power, result)
	return result


## Pista de PNJ para el Crisol: la primera pareja con pista aún sin descubrir.
func get_crucible_hint() -> Dictionary:
	var pending := get_untested_hints()
	if pending.is_empty():
		return {}
	return {"pair": pending[0], "text": pair_hints[pending[0]], "untested": pending.size()}


func get_untested_hints() -> Array[String]:
	var out: Array[String] = []
	for pk in pair_hints:
		var parts: PackedStringArray = str(pk).split("+")
		if parts.size() == 2 and get_atlas_cell(parts[0], parts[1])["state"] == CELL_HINT:
			out.append(pk)
	return out


# ==========================================================================
# Conjunto activo (1 Núcleo · 6 activos · 2 Ecos)
# ==========================================================================
func get_formula(key_or_id: String) -> Dictionary:
	if formulas.has(key_or_id):
		return formulas[key_or_id]
	if formula_ids.has(key_or_id):
		return formulas[formula_ids[key_or_id]]
	return {}


## Equipa un poder compuesto en una ranura. slot_type: "core" | "active" | "echo".
## Equipar descubre la combinación si era nueva.
func equip(slot_type: String, index: int, power: Dictionary) -> Dictionary:
	if not power.get("ok", false):
		return {"ok": false, "reason": "invalid_power"}
	match slot_type:
		SLOT_CORE:
			if index != 0:
				return {"ok": false, "reason": "invalid_slot"}
		SLOT_ACTIVE:
			if index < 0 or index >= ACTIVE_SLOTS:
				return {"ok": false, "reason": "invalid_slot"}
		SLOT_ECHO:
			if index < 0 or index >= ECHO_SLOTS:
				return {"ok": false, "reason": "invalid_slot"}
		_:
			return {"ok": false, "reason": "invalid_slot"}
	discover_power(power)
	var key := str(power["key"])
	# Un mismo poder no se equipa dos veces: se mueve a la nueva ranura.
	if core_slot == key:
		core_slot = ""
	for i in ACTIVE_SLOTS:
		if active_slots[i] == key:
			active_slots[i] = ""
	for i in ECHO_SLOTS:
		if echo_slots[i] == key:
			echo_slots[i] = ""
	match slot_type:
		SLOT_CORE:
			core_slot = key
		SLOT_ACTIVE:
			active_slots[index] = key
		SLOT_ECHO:
			echo_slots[index] = key
	loadout_changed.emit()
	return {"ok": true, "slot": slot_type, "index": index, "key": key}


func unequip(slot_type: String, index: int) -> bool:
	match slot_type:
		SLOT_CORE:
			if core_slot == "":
				return false
			core_slot = ""
		SLOT_ACTIVE:
			if index < 0 or index >= ACTIVE_SLOTS or active_slots[index] == "":
				return false
			active_slots[index] = ""
		SLOT_ECHO:
			if index < 0 or index >= ECHO_SLOTS or echo_slots[index] == "":
				return false
			echo_slots[index] = ""
		_:
			return false
	loadout_changed.emit()
	return true


func first_free_active_slot() -> int:
	for i in ACTIVE_SLOTS:
		if active_slots[i] == "":
			return i
	return -1


## Vista de una ranura: {key, name, energies, empty}.
func slot_view(key: String) -> Dictionary:
	if key == "":
		return {"key": "", "empty": true, "name": "", "energies": []}
	var f := get_formula(key)
	return {"key": key, "empty": false, "name": str(f.get("name", key)), "energies": f.get("energies", []), "form": f.get("form", ""), "rhythm": f.get("rhythm", "")}


## Poderes que cuentan para la resonancia: Núcleo + 6 activos.
func get_loadout_keys(include_echoes: bool = false) -> Array[String]:
	var out: Array[String] = []
	if core_slot != "":
		out.append(core_slot)
	for k in active_slots:
		if k != "":
			out.append(k)
	if include_echoes:
		for k in echo_slots:
			if k != "":
				out.append(k)
	return out


## Resonancia del conjunto. Devuelve una entrada por energía presente:
## {energy, count, bonus_pct, active, set_name, set_active, to_set}, ordenadas por count desc.
func get_resonance() -> Array[Dictionary]:
	var counts := {}
	for key in get_loadout_keys():
		var seen := {}
		for e in get_formula(key).get("energies", []):
			if seen.has(e):
				continue
			seen[e] = true
			counts[e] = int(counts.get(e, 0)) + 1
	var out: Array[Dictionary] = []
	for e in counts:
		var c: int = counts[e]
		var on := c >= RESONANCE_MIN
		out.append({
			"energy": e, "count": c, "active": on,
			"bonus_pct": c * RESONANCE_PCT_PER_POWER if on else 0,
			"set_name": str(resonance_sets.get(e, "Armonía de " + energy_name(e))),
			"set_active": c >= RESONANCE_SET_AT, "to_set": maxi(0, RESONANCE_SET_AT - c),
		})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["count"] > b["count"] if a["count"] != b["count"] else energy_index(a["energy"]) < energy_index(b["energy"]))
	return out


func get_resonance_bonus(energy: String) -> int:
	for r in get_resonance():
		if r["energy"] == energy:
			return int(r["bonus_pct"])
	return 0


## Texto de resumen de la resonancia dominante (como en el diseño).
func resonance_summary() -> String:
	var res := get_resonance()
	if res.is_empty() or not res[0]["active"]:
		return "Repite una energía en 2 poderes para activar su resonancia."
	var r: Dictionary = res[0]
	var txt := "%s aparece en %d poderes: +%d %% de potencia." % [energy_name(r["energy"]), r["count"], r["bonus_pct"]]
	if r["set_active"]:
		txt += " «%s» activo." % r["set_name"]
	elif r["to_set"] == 1:
		txt += " Un %d.º activaría «%s»." % [RESONANCE_SET_AT, r["set_name"]]
	else:
		txt += " Con %d activarías «%s»." % [RESONANCE_SET_AT, r["set_name"]]
	return txt


## Potencia de un poder equipado incluyendo la resonancia de su mejor energía.
func get_loadout_power_potency(key: String) -> int:
	var f := get_formula(key)
	if f.is_empty():
		return 0
	var base: int = compute_potency(f["energies"])["potency"]
	var best := 0
	for e in f["energies"]:
		best = maxi(best, get_resonance_bonus(e))
	return roundi(base * (1.0 + best / 100.0))


# ==========================================================================
# Atlas (N × N)
# ==========================================================================
## Fórmulas DESCUBIERTAS de exactamente esa pareja (diagonal: energía pura a+a).
func get_pair_formulas(a: String, b: String) -> Array[Dictionary]:
	var ek := pair_key(a, b)
	var out: Array[Dictionary] = []
	for key in discovered:
		if str(key).get_slice("|", 0) == ek:
			out.append(get_formula(key))
	out.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return str(x.get("name", "")) < str(y.get("name", "")))
	return out


## Estado de una celda: {state, count, hint, pure, a, b}.
func get_atlas_cell(a: String, b: String, role: String = "") -> Dictionary:
	var pk := pair_key(a, b)
	var found := get_pair_formulas(a, b)
	if role != "":
		found = found.filter(func(f: Dictionary) -> bool: return f.get("role", "") == role)
	var cell := {"a": a, "b": b, "pair": pk, "pure": a == b, "count": found.size(), "hint": ""}
	if not found.is_empty():
		cell["state"] = CELL_DISCOVERED
	elif pair_hints.has(pk) and role == "":
		cell["state"] = CELL_HINT
		cell["hint"] = pair_hints[pk]
	else:
		cell["state"] = CELL_UNKNOWN
	return cell


## Matriz N × N completa (filas y columnas = `energies`). Simétrica.
func get_atlas_matrix(role: String = "") -> Array:
	var rows: Array = []
	for a in energies:
		var row: Array = []
		for b in energies:
			row.append(get_atlas_cell(a, b, role))
		rows.append(row)
	return rows


## Texto que la UI muestra para una celda.
static func cell_label(cell: Dictionary) -> String:
	match str(cell.get("state", CELL_UNKNOWN)):
		CELL_DISCOVERED:
			return str(cell["count"])
		CELL_HINT:
			return "?"
	return MASK


## {pairs_total, pairs_discovered, formulas_known}. pairs_total = N(N+1)/2.
func get_atlas_stats() -> Dictionary:
	var n := energies.size()
	var pairs := 0
	for i in n:
		for j in range(i, n):
			if get_atlas_cell(energies[i], energies[j])["state"] == CELL_DISCOVERED:
				pairs += 1
	return {"pairs_total": n * (n + 1) / 2, "pairs_discovered": pairs, "formulas_known": discovered.size()}


## Detalle de una pareja para el panel lateral del Atlas.
func get_pair_details(a: String, b: String) -> Dictionary:
	var known := get_pair_formulas(a, b)
	var used_forms := {}
	for f in known:
		used_forms[f["form"]] = true
	var thirds: Array[Dictionary] = []
	for c in energies:
		if c == a or c == b:
			continue
		var trio := energies_key([a, b, c])
		var found_name := ""
		for key in discovered:
			if str(key).get_slice("|", 0) == trio:
				found_name = str(get_formula(key).get("name", ""))
				break
		var state := CELL_DISCOVERED if found_name != "" else (CELL_HINT if trio_hints.has(trio) else CELL_UNKNOWN)
		thirds.append({"energy": c, "state": state, "name": found_name, "hint": str(trio_hints.get(trio, ""))})
	thirds.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		var order := {CELL_DISCOVERED: 0, CELL_HINT: 1, CELL_UNKNOWN: 2}
		return order[x["state"]] < order[y["state"]] if x["state"] != y["state"] else energy_index(x["energy"]) < energy_index(y["energy"]))
	return {
		"a": a, "b": b, "cell": get_atlas_cell(a, b), "formulas": known,
		"untested_forms": FORMS.size() - used_forms.size(), "thirds": thirds.slice(0, 4),
	}


# ==========================================================================
# Constelación
# ==========================================================================
func get_star(id: String) -> Dictionary:
	return nodes[_node_index[id]] if _node_index.has(id) else {}


func get_spent_points() -> int:
	var s := 0
	for n in nodes:
		s += int(n["rank"]) * int(n["cost"])
	return s


func get_available_points() -> int:
	return total_points - get_spent_points()


func _requirements_met(n: Dictionary) -> bool:
	for r in n.get("requires", []):
		if int(get_star(r).get("rank", 0)) <= 0:
			return false
	return true


func get_node_state(id: String) -> String:
	var n := get_star(id)
	if n.is_empty():
		return NODE_LOCKED
	if int(n["rank"]) > 0:
		return NODE_ACTIVE
	return NODE_AVAILABLE if _requirements_met(n) else NODE_LOCKED


## Asigna un punto. Devuelve {ok, reason?, rank}.
func allocate_point(id: String) -> Dictionary:
	var n := get_star(id)
	if n.is_empty():
		return {"ok": false, "reason": "unknown_node"}
	if int(n["rank"]) >= int(n["max_rank"]):
		return {"ok": false, "reason": "max_rank"}
	if not _requirements_met(n):
		return {"ok": false, "reason": "locked"}
	if get_available_points() < int(n["cost"]):
		return {"ok": false, "reason": "not_enough_points"}
	n["rank"] = int(n["rank"]) + 1
	history.append({"node": id, "delta": 1})
	constellation_changed.emit()
	return {"ok": true, "rank": n["rank"]}


## Quita un punto (no se puede si deja huérfano a un hijo con rango).
func refund_point(id: String) -> Dictionary:
	var n := get_star(id)
	if n.is_empty() or int(n["rank"]) <= 0:
		return {"ok": false, "reason": "no_rank"}
	if int(n["rank"]) == 1:
		for other in nodes:
			if (other.get("requires", []) as Array).has(id) and int(other["rank"]) > 0:
				return {"ok": false, "reason": "has_dependents"}
	n["rank"] = int(n["rank"]) - 1
	history.append({"node": id, "delta": -1})
	constellation_changed.emit()
	return {"ok": true, "rank": n["rank"]}


## Deshacer (Ctrl Z): revierte el último cambio.
func undo_last() -> bool:
	if history.is_empty():
		return false
	var h: Dictionary = history.pop_back()
	var n := get_star(h["node"])
	n["rank"] = int(n["rank"]) - int(h["delta"])
	constellation_changed.emit()
	return true


## Bonus de potencia (%) que la Constelación da a los poderes con `energy` (solo su rama).
func get_constellation_bonus(energy: String) -> float:
	var b := 0.0
	for n in nodes:
		if n["branch"] == energy:
			b += int(n["rank"]) * float(n.get("potency_pct", 0))
	return b


## Bonus general (nodos sin rama: raíz y tronco) que suma a todos los poderes.
func get_constellation_general_bonus() -> float:
	var b := 0.0
	for n in nodes:
		if n["branch"] == "":
			b += int(n["rank"]) * float(n.get("potency_pct", 0))
	return b


## Valor mostrado en la descripción de un nodo para un rango.
func node_value(n: Dictionary, rank: int) -> int:
	var per := int(n.get("value_per_rank", n.get("potency_pct", 0)))
	return per * maxi(rank, 1)


func node_description(id: String, rank: int = -1) -> String:
	var n := get_star(id)
	if n.is_empty():
		return ""
	var r := int(n["rank"]) if rank < 0 else rank
	return str(n["desc"]).replace("{v}", str(node_value(n, r)))


## Poderes del Crisol (conjunto + descubiertos) a los que afecta un nodo.
## Nodos sin rama afectan a todos los poderes del conjunto.
func get_node_affected_powers(id: String) -> Array[String]:
	var n := get_star(id)
	var out: Array[String] = []
	if n.is_empty():
		return out
	var branch := str(n["branch"])
	for key in get_loadout_keys(true):
		var f := get_formula(key)
		if branch == "" or (f.get("energies", []) as Array).has(branch):
			if not out.has(f["name"]):
				out.append(f["name"])
	return out


## DPS simulado del conjunto (60 s contra maniquí). `extra_node` simula +1 rango.
func simulate_dps(extra_node: String = "") -> int:
	var n := get_star(extra_node)
	var bumped := false
	if not n.is_empty() and int(n["rank"]) < int(n["max_rank"]):
		n["rank"] = int(n["rank"]) + 1
		bumped = true
	var total := 0.0
	for key in get_loadout_keys():
		total += get_loadout_power_potency(key) * DPS_PER_POTENCY
	if bumped:
		n["rank"] = int(n["rank"]) - 1
	return roundi(total)


# ==========================================================================
# Seed / persistencia
# ==========================================================================
func load_seed(path: String = DEFAULT_SEED_PATH) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("[PowersService] Sin semilla en %s" % path)
		return false
	var data: Variant = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		push_warning("[PowersService] Semilla inválida: %s" % path)
		return false
	load_from_dict(data)
	return true


func load_from_dict(data: Dictionary) -> void:
	for k in data.get("affinities", {}):
		var a: Dictionary = data["affinities"][k]
		set_affinity(k, int(a.get("level", 1)), float(a.get("progress", 0.0)))
	for fd in data.get("formulas", []):
		var es: Array = fd.get("e", [])
		var key := combo_key(es, str(fd.get("f", "")), str(fd.get("r", "")))
		formulas[key] = {
			"id": str(fd["id"]), "name": str(fd["name"]), "energies": sort_energies(es),
			"form": str(fd["f"]), "rhythm": str(fd["r"]), "role": str(fd.get("role", "dano")),
			"desc": str(fd.get("d", "")),
		}
		formula_ids[str(fd["id"])] = key
		if fd.get("known", false):
			discovered[key] = true
	for pk in data.get("pair_hints", {}):
		var parts: PackedStringArray = str(pk).split("+")
		pair_hints[pair_key(parts[0], parts[1])] = str(data["pair_hints"][pk])
	for tk in data.get("trio_hints", {}):
		trio_hints[energies_key(Array(str(tk).split("+")))] = str(data["trio_hints"][tk])
	resonance_sets = (data.get("resonance_sets", {}) as Dictionary).duplicate()
	var lo: Dictionary = data.get("loadout", {})
	loadout_name = str(lo.get("name", loadout_name))
	loadout_key = str(lo.get("key", loadout_key))
	core_slot = formula_ids.get(str(lo.get("core", "")), "")
	var act: Array = lo.get("actives", [])
	for i in ACTIVE_SLOTS:
		active_slots[i] = formula_ids.get(str(act[i]), "") if i < act.size() else ""
	var ech: Array = lo.get("echoes", [])
	for i in ECHO_SLOTS:
		echo_slots[i] = formula_ids.get(str(ech[i]), "") if i < ech.size() else ""
	var c: Dictionary = data.get("constellation", {})
	class_title = str(c.get("class_name", class_title))
	build_name = str(c.get("build_name", ""))
	total_points = int(c.get("total_points", total_points))
	focus = (c.get("focus", []) as Array).duplicate(true)
	builds = (c.get("builds", []) as Array).duplicate(true)
	share_code = str(c.get("share_code", ""))
	branches = (c.get("branches", []) as Array).duplicate(true)
	nodes.clear()
	_node_index.clear()
	for nd in c.get("nodes", []):
		var n: Dictionary = (nd as Dictionary).duplicate(true)
		n["rank"] = int(n.get("rank", 0))
		n["max_rank"] = int(n.get("max_rank", 1))
		n["cost"] = int(n.get("cost", 1))
		n["branch"] = str(n.get("branch", ""))
		n["keystone"] = bool(n.get("keystone", false))
		_node_index[n["id"]] = nodes.size()
		nodes.append(n)
	loadout_changed.emit()
	constellation_changed.emit()


func to_dict() -> Dictionary:
	var ranks := {}
	for n in nodes:
		ranks[n["id"]] = n["rank"]
	return {
		"affinity_xp": affinity_xp.duplicate(), "discovered": discovered.keys(),
		"core": core_slot, "actives": active_slots.duplicate(), "echoes": echo_slots.duplicate(),
		"constellation_ranks": ranks,
	}
