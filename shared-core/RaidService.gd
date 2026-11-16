extends Node
## HUD de raid extendido para sanador — UI v2.4 Paso 17 · ADR 115
## (design_ref/pantallas_html/MMO-Raid.html, PROMPT_ANTIGRAVITY.md §2.1, §4, Anexos A, B y D).
##
## Autoload `RaidService` o instanciable con `.new()` + `load_seed()`.
## Seed: res://config/raid/raid_seed.json (sin persistencia: es estado de combate).
##
## Modelo:
## - Banda de 10 (2 columnas × 5 filas) o 20 integrantes (4 × 5). Cada integrante: id, nombre,
##   rol (tank · healer · dps), clase, vida actual / máxima / %, curación entrante (% de la vida
##   máxima), daño previsto en los próximos 3 s (%), debuff purificable (rombo violeta),
##   distancia al sanador (> `heal_range_m` = fuera de alcance, opacidad 0,4 y «42 m»), caído
##   (opacidad 0,6 y «Muerto · resucitar»), objetivo seleccionado (borde cian) y peligro
##   inminente (borde rojo, prioridad sobre el cian).
## - Click-casting: clic izq. `heal_target()` · clic der. `shield_target()` · Shift+clic
##   `dispel_target()`. Sobre un caído, el clic izquierdo resucita (`resurrect_target()`).
## - Jefe «Coloso de Runavell»: vida, fases por umbral, temporizador de enrage determinista.
## - Alertas tácticas centrales con cuenta atrás y aviso estéreo (lado del que suena).
## - Telemetría del sanador: vida, maná, ritmo de gasto y «Maná 52 % · dura ~1:40 a este ritmo»,
##   y 10 habilidades (teclas 1 … 0) con enfriamientos.
##
## Todo avanza con `tick(delta)`. Con `auto_tick` y un encuentro en curso (`start_encounter()`)
## lo llama `_process`; los tests lo llaman a mano para ser deterministas.

signal changed
signal member_changed(member_id: String)
signal member_healed(member_id: String, amount: int)
signal member_shielded(member_id: String, amount: int)
signal member_dispelled(member_id: String)
signal member_died(member_id: String)
signal member_resurrected(member_id: String)
signal target_selected(member_id: String)
signal cast_failed(member_id: String, reason: String)
signal raid_size_changed(size: int)
signal boss_changed
signal boss_phase_changed(phase: int)
signal boss_enraged
signal alert_triggered(title: String, side: String)
signal alert_tick(count: int)
signal alert_cleared
signal alert_audio_cue(side: String, pan: float)
signal mana_changed(current: float, maximum: float)
signal encounter_changed(active: bool)

const DEFAULT_SEED_PATH := "res://config/raid/raid_seed.json"

const ROLES: Array[String] = ["tank", "healer", "dps"]
const SIZES: Array[int] = [10, 20]
const SIDES: Array[String] = ["left", "right", "center"]
const DIRECTIONS: Array[String] = ["left", "right", "up", "down"]

const ROLE_TANK := "tank"
const ROLE_HEALER := "healer"
const ROLE_DPS := "dps"

const STATUS_DEAD := "Muerto · resucitar"

const REASON_UNKNOWN := "unknown_member"
const REASON_DEAD := "dead"
const REASON_ALIVE := "alive"
const REASON_RANGE := "out_of_range"
const REASON_MANA := "no_mana"
const REASON_NO_DEBUFF := "no_debuff"
const REASON_FULL := "full_health"

var seed_data: Dictionary = {}
var raid_size := 20
var rows := 5
var columns_by_size := {10: 2, 20: 4}
var heal_range_m := 40.0
var role_defs: Dictionary = {}             # role -> {label, color}
var click_legend := ""
var heal_pct := 15.0
var heal_mana := 40.0
var shield_pct := 20.0
var shield_mana := 60.0
var dispel_mana := 30.0
var resurrect_pct := 30.0
var resurrect_mana := 100.0

## Orden canónico (grupo-mayor): 1-5 Grupo 1 … 16-20 Grupo 4.
var members: Array[Dictionary] = []
var selected_id := ""

# Jefe
var boss_name := ""
var boss_hp_percent := 100.0
var boss_phase := 1
var boss_phases: Array[Dictionary] = []    # {id, label, until_percent}
var boss_phase_color := Color("#f5c35b")
var boss_hp_color := Color("#e25555")
var enrage_total := 0.0
var enrage_remaining := 0.0
var enraged := false

# Alerta
var alert_active := false
var alert_title := ""
var alert_subtitle := ""
var alert_duration := 0.0
var alert_remaining := 0.0
var alert_side := "center"
var alert_direction := ""

# Sanador
var healer_hp_percent := 100.0
var mana_current := 0.0
var mana_max := 1.0
var mana_burn_per_sec := 0.0
var abilities: Array[Dictionary] = []      # {key, name, color, cooldown, cooldown_total, mana}

var auto_tick := true
var encounter_active := false


func _ready() -> void:
	if seed_data.is_empty():
		load_seed()


func _process(delta: float) -> void:
	if auto_tick and encounter_active:
		tick(delta)


# ==========================================================================
# Seed
# ==========================================================================
func load_seed(path: String = DEFAULT_SEED_PATH) -> bool:
	if not FileAccess.file_exists(path):
		push_warning("[RaidService] Seed no encontrado: %s" % path)
		return false
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY:
		push_warning("[RaidService] Seed inválido: %s" % path)
		return false
	load_from_dict(data)
	return true


func load_from_dict(data: Dictionary) -> void:
	seed_data = data.duplicate(true)
	rows = int(data.get("rows", 5))
	heal_range_m = float(data.get("heal_range_m", 40))
	columns_by_size = {}
	var cbs: Dictionary = data.get("columns_by_size", {"10": 2, "20": 4})
	for k in cbs:
		columns_by_size[int(k)] = int(cbs[k])
	role_defs = (data.get("roles", {}) as Dictionary).duplicate(true)
	var cc: Dictionary = data.get("click_casting", {})
	click_legend = str(cc.get("legend", "Clic: Sanar · Clic der.: Escudo · Shift+clic: Purificar"))
	heal_pct = float(cc.get("heal_pct", 15))
	heal_mana = float(cc.get("heal_mana", 40))
	shield_pct = float(cc.get("shield_pct", 20))
	shield_mana = float(cc.get("shield_mana", 60))
	dispel_mana = float(cc.get("dispel_mana", 30))
	resurrect_pct = float(cc.get("resurrect_pct", 30))
	resurrect_mana = float(cc.get("resurrect_mana", 100))

	members.clear()
	selected_id = ""
	for m in data.get("members", []):
		var mem := _member_from_seed(m)
		members.append(mem)
		if mem["is_selected"] and selected_id == "":
			selected_id = mem["id"]
	for mem in members:
		mem["is_selected"] = mem["id"] == selected_id

	var b: Dictionary = data.get("boss", {})
	boss_name = str(b.get("name", ""))
	boss_hp_percent = clampf(float(b.get("hp_percent", 100)), 0.0, 100.0)
	boss_phases.clear()
	for p in b.get("phases", []):
		boss_phases.append({"id": int(p.get("id", boss_phases.size() + 1)), "label": str(p.get("label", "Fase %d" % (boss_phases.size() + 1))),
			"until_percent": float(p.get("until_percent", 0))})
	boss_phase = int(b.get("phase", 1))
	boss_phase_color = Color(str(b.get("phase_color", "#f5c35b")))
	boss_hp_color = Color(str(b.get("hp_color", "#e25555")))
	enrage_total = float(b.get("enrage_seconds", 0))
	enrage_remaining = enrage_total
	enraged = false

	var a: Dictionary = data.get("alert", {})
	alert_active = false
	if not a.is_empty():
		trigger_alert(str(a.get("title", "")), str(a.get("subtitle", "")), float(a.get("duration_sec", 3)),
			str(a.get("side", "center")), str(a.get("direction", "")), false)

	var h: Dictionary = data.get("healer", {})
	healer_hp_percent = clampf(float(h.get("hp_percent", 100)), 0.0, 100.0)
	mana_max = maxf(1.0, float(h.get("mana_max", 1000)))
	mana_current = clampf(float(h.get("mana_current", mana_max)), 0.0, mana_max)
	mana_burn_per_sec = maxf(0.0, float(h.get("mana_burn_per_sec", 0)))

	abilities.clear()
	for ab in data.get("abilities", []):
		abilities.append({"key": str(ab.get("key", "")), "name": str(ab.get("name", "")), "color": str(ab.get("color", "#1a2e22")),
			"cooldown": maxf(0.0, float(ab.get("cooldown", 0))), "cooldown_total": maxf(0.0, float(ab.get("cooldown_total", 0))),
			"mana": float(ab.get("mana", 0))})

	encounter_active = false
	set_raid_size(int(data.get("raid_size", 20)), false)
	changed.emit()


func _member_from_seed(m: Dictionary) -> Dictionary:
	var max_hp := maxi(1, int(m.get("max_hp", 1000)))
	var pct := clampf(float(m.get("hp_percent", 100)), 0.0, 100.0)
	var dead := bool(m.get("is_dead", false)) or pct <= 0.0
	var role := str(m.get("role", ROLE_DPS))
	if not ROLES.has(role):
		role = ROLE_DPS
	var mem := {
		"id": str(m.get("id", str(m.get("name", "")).to_lower())),
		"name": str(m.get("name", "")),
		"role": role,
		"class_name": str(m.get("class_name", "")),
		"group": int(m.get("group", 1)),
		"max_hp": max_hp,
		"current_hp": 0 if dead else int(round(max_hp * pct / 100.0)),
		"hp_percent": 0,
		"incoming_heal": clampf(float(m.get("incoming_heal", 0)), 0.0, 100.0),
		"projected_damage_3s": clampf(float(m.get("projected_damage_3s", 0)), 0.0, 100.0),
		"has_dispellable_debuff": bool(m.get("has_dispellable_debuff", false)),
		"debuff_name": str(m.get("debuff_name", "Magia" if bool(m.get("has_dispellable_debuff", false)) else "")),
		"distance_meters": maxf(0.0, float(m.get("distance_meters", 0))),
		"is_dead": dead,
		"is_selected": bool(m.get("is_selected", false)),
		"has_priority_threat": bool(m.get("has_priority_threat", false)),
		"shield": 0,
	}
	_recompute(mem)
	return mem


func _recompute(mem: Dictionary) -> void:
	mem["current_hp"] = clampi(int(mem["current_hp"]), 0, int(mem["max_hp"]))
	if int(mem["current_hp"]) <= 0:
		mem["is_dead"] = true
	if mem["is_dead"]:
		mem["current_hp"] = 0
		mem["incoming_heal"] = 0.0
		mem["projected_damage_3s"] = 0.0
		mem["shield"] = 0
	mem["hp_percent"] = int(round(float(mem["current_hp"]) / float(mem["max_hp"]) * 100.0))
	mem["out_of_range"] = float(mem["distance_meters"]) > heal_range_m


# ==========================================================================
# Banda
# ==========================================================================
## 10 → 2 columnas × 5 filas (grupos 1-2) · 20 → 4 × 5. Devuelve false si el tamaño no es válido.
func set_raid_size(size: int, emit := true) -> bool:
	if not SIZES.has(size):
		return false
	raid_size = size
	if selected_id != "" and member_index(selected_id) >= raid_size:
		select_target("")
	if emit:
		raid_size_changed.emit(raid_size)
		changed.emit()
	return true


func grid_columns() -> int:
	return int(columns_by_size.get(raid_size, raid_size / rows))


func grid_rows() -> int:
	return rows


func header_text() -> String:
	return "Raid · %d" % visible_members().size()


## Integrantes mostrados según el tamaño de banda (orden grupo-mayor).
func visible_members() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in mini(raid_size, members.size()):
		out.append(members[i])
	return out


func member_ids() -> Array[String]:
	var out: Array[String] = []
	for m in visible_members():
		out.append(str(m["id"]))
	return out


func member_index(id: String) -> int:
	for i in members.size():
		if members[i]["id"] == id:
			return i
	return -1


func get_member(id: String) -> Dictionary:
	var i := member_index(id)
	return members[i] if i >= 0 else {}


func has_member(id: String) -> bool:
	var i := member_index(id)
	return i >= 0 and i < raid_size


## Integrantes de un grupo (1..4) entre los visibles.
func group_members(group: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for m in visible_members():
		if int(m["group"]) == group:
			out.append(m)
	return out


## Columna y fila (0-based) de un integrante en la cuadrícula: columna = grupo, fila = puesto.
func grid_cell(id: String) -> Vector2i:
	var i := member_index(id)
	if i < 0 or i >= raid_size:
		return Vector2i(-1, -1)
	return Vector2i(i / rows, i % rows)


func members_by_role(role: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for m in visible_members():
		if m["role"] == role:
			out.append(m)
	return out


func role_counts() -> Dictionary:
	var out := {ROLE_TANK: 0, ROLE_HEALER: 0, ROLE_DPS: 0}
	for m in visible_members():
		out[m["role"]] += 1
	return out


func role_color(role: String) -> Color:
	return Color(str((role_defs.get(role, {}) as Dictionary).get("color", "#9aa6ae")))


func role_label(role: String) -> String:
	return str((role_defs.get(role, {}) as Dictionary).get("label", role))


func alive_count() -> int:
	var n := 0
	for m in visible_members():
		if not m["is_dead"]:
			n += 1
	return n


func dead_members() -> Array[String]:
	var out: Array[String] = []
	for m in visible_members():
		if m["is_dead"]:
			out.append(str(m["id"]))
	return out


## Vida media de los vivos (0-100).
func average_hp_percent() -> float:
	var total := 0.0
	var n := 0
	for m in visible_members():
		if not m["is_dead"]:
			total += float(m["hp_percent"])
			n += 1
	return total / n if n > 0 else 0.0


## Importa un grupo de PartyFrames / PartyService ({name, class, role, hp, max_hp}) como
## Grupo 1 de la banda (los demás grupos se conservan). Sin `role` válido se asume daño.
func load_party_members(party: Array) -> int:
	var n := 0
	for i in mini(party.size(), rows):
		var p = party[i]
		if typeof(p) != TYPE_DICTIONARY or i >= members.size():
			continue
		var max_hp := maxi(1, int(p.get("max_hp", p.get("hp_max", 1000))))
		var hp := int(p.get("hp", p.get("current_hp", max_hp)))
		var mem := members[i]
		mem["id"] = str(p.get("id", str(p.get("name", mem["id"])).to_lower()))
		mem["name"] = str(p.get("name", mem["name"]))
		mem["class_name"] = str(p.get("class", p.get("class_name", mem["class_name"])))
		var role := str(p.get("role", ROLE_DPS))
		mem["role"] = role if ROLES.has(role) else ROLE_DPS
		mem["max_hp"] = max_hp
		mem["current_hp"] = hp
		mem["is_dead"] = hp <= 0
		mem["group"] = 1
		_recompute(mem)
		n += 1
	changed.emit()
	return n


# ==========================================================================
# Estado por integrante (cálculos de barras y presentación)
# ==========================================================================
func is_out_of_range(id: String) -> bool:
	var m := get_member(id)
	return not m.is_empty() and float(m["distance_meters"]) > heal_range_m


func is_dead(id: String) -> bool:
	var m := get_member(id)
	return not m.is_empty() and bool(m["is_dead"])


## Vida: [inicio, ancho] en fracción de barra (0..1).
func hp_span(id: String) -> Vector2:
	var m := get_member(id)
	return Vector2(0.0, float(m.get("hp_percent", 0)) / 100.0)


## Curación entrante: a continuación de la vida, recortada a la vida que falta.
func incoming_heal_span(id: String) -> Vector2:
	var m := get_member(id)
	if m.is_empty():
		return Vector2.ZERO
	var hp := float(m["hp_percent"])
	return Vector2(hp, clampf(float(m["incoming_heal"]), 0.0, 100.0 - hp)) / 100.0


## Daño previsto (3 s): el último tramo de la vida actual (no puede superar la vida que queda).
func projected_damage_span(id: String) -> Vector2:
	var m := get_member(id)
	if m.is_empty():
		return Vector2.ZERO
	var hp := float(m["hp_percent"])
	var dmg := minf(float(m["projected_damage_3s"]), hp)
	return Vector2(hp - dmg, dmg) / 100.0


## Escudo de absorción: franja superior desde la izquierda (fracción de la vida máxima).
func shield_span(id: String) -> Vector2:
	var m := get_member(id)
	if m.is_empty():
		return Vector2.ZERO
	return Vector2(0.0, clampf(float(m["shield"]) / float(m["max_hp"]), 0.0, 1.0))


## Vida estimada a 3 s (vida − daño previsto + curación entrante), 0..100.
func projected_hp_percent(id: String) -> float:
	var m := get_member(id)
	if m.is_empty() or m["is_dead"]:
		return 0.0
	return clampf(float(m["hp_percent"]) - float(m["projected_damage_3s"]) + float(m["incoming_heal"]), 0.0, 100.0)


## El daño previsto lo mata si no llega curación suficiente.
func is_lethal(id: String) -> bool:
	var m := get_member(id)
	if m.is_empty() or m["is_dead"]:
		return false
	return float(m["projected_damage_3s"]) > 0.0 and float(m["projected_damage_3s"]) >= float(m["hp_percent"]) + float(m["incoming_heal"])


## Prioridad de triaje del sanador: vivos y a tiro, de menor a mayor vida prevista a 3 s.
func triage_order() -> Array[String]:
	var list: Array = []
	for m in visible_members():
		if not m["is_dead"] and not m["out_of_range"]:
			list.append([projected_hp_percent(m["id"]), member_index(m["id"]), str(m["id"])])
	list.sort_custom(func(a, b) -> bool: return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	var out: Array[String] = []
	for e in list:
		out.append(e[2])
	return out


## «58 %» · «42 m» (fuera de alcance) · «Muerto · resucitar».
func status_text(id: String) -> String:
	var m := get_member(id)
	if m.is_empty():
		return ""
	if m["is_dead"]:
		return STATUS_DEAD
	if m["out_of_range"]:
		return "%d m" % roundi(float(m["distance_meters"]))
	return "%d %%" % int(m["hp_percent"])


## Opacidad del marco: caído 0,6 · fuera de alcance 0,4 · normal 1.
func frame_opacity(id: String) -> float:
	var m := get_member(id)
	if m.is_empty():
		return 1.0
	if m["is_dead"]:
		return 0.6
	if m["out_of_range"]:
		return 0.4
	return 1.0


## "threat" (rojo #ff6b6b, 2 px) > "selected" (cian #46e3c1, 2 px) > "normal" (blanco 8 %, 1 px).
func border_state(id: String) -> String:
	var m := get_member(id)
	if m.is_empty():
		return "normal"
	if m["has_priority_threat"]:
		return "threat"
	if m["is_selected"]:
		return "selected"
	return "normal"


## Relleno de vida: verde #3ccf73, o violeta #7a5bd0 si lleva un debuff purificable.
func hp_fill_color(id: String) -> Color:
	var m := get_member(id)
	return Color("#7a5bd0") if not m.is_empty() and m["has_dispellable_debuff"] else Color("#3ccf73")


## Vista plana para la UI (copia con los campos derivados).
func member_view(id: String) -> Dictionary:
	var m := get_member(id)
	if m.is_empty():
		return {}
	var v := m.duplicate()
	v["status_text"] = status_text(id)
	v["opacity"] = frame_opacity(id)
	v["border"] = border_state(id)
	v["hp_color"] = hp_fill_color(id)
	v["role_color"] = role_color(str(m["role"]))
	v["hp_span"] = hp_span(id)
	v["heal_span"] = incoming_heal_span(id)
	v["damage_span"] = projected_damage_span(id)
	v["shield_span"] = shield_span(id)
	v["lethal"] = is_lethal(id)
	return v


# ==========================================================================
# Mutaciones de integrantes
# ==========================================================================
func _set_field(id: String, key: String, value) -> bool:
	var m := get_member(id)
	if m.is_empty():
		return false
	m[key] = value
	_recompute(m)
	member_changed.emit(id)
	changed.emit()
	return true


func set_member_distance(id: String, meters: float) -> bool:
	return _set_field(id, "distance_meters", maxf(0.0, meters))


func set_incoming_heal(id: String, percent: float) -> bool:
	return _set_field(id, "incoming_heal", clampf(percent, 0.0, 100.0))


func set_projected_damage(id: String, percent: float) -> bool:
	return _set_field(id, "projected_damage_3s", clampf(percent, 0.0, 100.0))


func set_debuff(id: String, active: bool, debuff_name: String = "Magia") -> bool:
	var m := get_member(id)
	if m.is_empty():
		return false
	m["debuff_name"] = debuff_name if active else ""
	return _set_field(id, "has_dispellable_debuff", active)


## Solo un integrante en peligro prioritario a la vez ("" lo quita a todos).
func set_priority_threat(id: String) -> void:
	for m in members:
		m["has_priority_threat"] = id != "" and m["id"] == id
	changed.emit()


func select_target(id: String) -> bool:
	if id != "" and not has_member(id):
		return false
	selected_id = id
	for m in members:
		m["is_selected"] = id != "" and m["id"] == id
	target_selected.emit(id)
	changed.emit()
	return true


## Aplica daño (el escudo absorbe primero). Devuelve la vida perdida.
func damage_member(id: String, amount: int) -> int:
	var m := get_member(id)
	if m.is_empty() or m["is_dead"] or amount <= 0:
		return 0
	var absorbed := mini(int(m["shield"]), amount)
	m["shield"] = int(m["shield"]) - absorbed
	var lost := mini(amount - absorbed, int(m["current_hp"]))
	m["current_hp"] = int(m["current_hp"]) - lost
	_recompute(m)
	if m["is_dead"]:
		member_died.emit(id)
	member_changed.emit(id)
	changed.emit()
	return lost


## Resuelve la predicción de 3 s: aplica el daño previsto y la curación entrante.
func resolve_prediction(id: String) -> void:
	var m := get_member(id)
	if m.is_empty() or m["is_dead"]:
		return
	var dmg := int(round(float(m["projected_damage_3s"]) / 100.0 * float(m["max_hp"])))
	var heal := int(round(float(m["incoming_heal"]) / 100.0 * float(m["max_hp"])))
	m["projected_damage_3s"] = 0.0
	m["incoming_heal"] = 0.0
	if dmg > 0:
		damage_member(id, dmg)
	if heal > 0 and not m["is_dead"]:
		m["current_hp"] = int(m["current_hp"]) + heal
		_recompute(m)
	member_changed.emit(id)
	changed.emit()


# ==========================================================================
# Click-casting del sanador
# ==========================================================================
## Clic izq. = sanar (o resucitar si está caído) · clic der. = escudo · Shift+clic = purificar.
func handle_click(id: String, button_index: int, shift: bool = false) -> bool:
	if shift and button_index == MOUSE_BUTTON_LEFT:
		return dispel_target(id)
	if button_index == MOUSE_BUTTON_RIGHT:
		return shield_target(id)
	if button_index == MOUSE_BUTTON_LEFT:
		if is_dead(id):
			return resurrect_target(id)
		return heal_target(id)
	return false


func _can_cast(id: String, mana_cost: float, need_alive := true) -> String:
	var m := get_member(id)
	if m.is_empty() or not has_member(id):
		return REASON_UNKNOWN
	if need_alive and m["is_dead"]:
		return REASON_DEAD
	if not need_alive and not m["is_dead"]:
		return REASON_ALIVE
	if m["out_of_range"]:
		return REASON_RANGE
	if mana_current < mana_cost:
		return REASON_MANA
	return ""


func _fail(id: String, reason: String) -> bool:
	cast_failed.emit(id, reason)
	return false


func _spend(cost: float) -> void:
	if cost <= 0.0:
		return
	mana_current = maxf(0.0, mana_current - cost)
	mana_changed.emit(mana_current, mana_max)


## Curación rápida (heal_pct de la vida máxima) y selección del objetivo. Con la vida llena falla
## (`full_health`) sin gastar maná.
func heal_target(id: String) -> bool:
	if has_member(id):
		select_target(id)
	var why := _can_cast(id, heal_mana)
	if why != "":
		return _fail(id, why)
	var m := get_member(id)
	if int(m["current_hp"]) >= int(m["max_hp"]):
		return _fail(id, REASON_FULL)
	var amount := mini(int(round(heal_pct / 100.0 * float(m["max_hp"]))), int(m["max_hp"]) - int(m["current_hp"]))
	_spend(heal_mana)
	m["current_hp"] = int(m["current_hp"]) + amount
	_recompute(m)
	member_healed.emit(id, amount)
	member_changed.emit(id)
	changed.emit()
	return true


## Barrera de absorción (shield_pct de la vida máxima, se acumula hasta el 100 %).
func shield_target(id: String) -> bool:
	if has_member(id):
		select_target(id)
	var why := _can_cast(id, shield_mana)
	if why != "":
		return _fail(id, why)
	var m := get_member(id)
	var amount := int(round(shield_pct / 100.0 * float(m["max_hp"])))
	amount = mini(amount, int(m["max_hp"]) - int(m["shield"]))
	_spend(shield_mana)
	m["shield"] = int(m["shield"]) + amount
	member_shielded.emit(id, amount)
	member_changed.emit(id)
	changed.emit()
	return true


## Purifica el debuff (solo si tiene `has_dispellable_debuff`).
func dispel_target(id: String) -> bool:
	if has_member(id):
		select_target(id)
	var why := _can_cast(id, dispel_mana)
	if why != "":
		return _fail(id, why)
	var m := get_member(id)
	if not m["has_dispellable_debuff"]:
		return _fail(id, REASON_NO_DEBUFF)
	_spend(dispel_mana)
	m["has_dispellable_debuff"] = false
	m["debuff_name"] = ""
	_recompute(m)
	member_dispelled.emit(id)
	member_changed.emit(id)
	changed.emit()
	return true


## Resucita a un caído con resurrect_pct de su vida máxima.
func resurrect_target(id: String) -> bool:
	if has_member(id):
		select_target(id)
	var why := _can_cast(id, resurrect_mana, false)
	if why != "":
		return _fail(id, why)
	var m := get_member(id)
	_spend(resurrect_mana)
	m["is_dead"] = false
	m["current_hp"] = maxi(1, int(round(resurrect_pct / 100.0 * float(m["max_hp"]))))
	_recompute(m)
	member_resurrected.emit(id)
	member_changed.emit(id)
	changed.emit()
	return true


# ==========================================================================
# Jefe
# ==========================================================================
func boss_phase_label(phase: int = -1) -> String:
	var p := boss_phase if phase < 0 else phase
	for d in boss_phases:
		if int(d["id"]) == p:
			return str(d["label"])
	return "Fase %d" % p


func boss_phase_count() -> int:
	return boss_phases.size()


## Pasa a la fase siguiente (no más allá de la última). Devuelve la fase resultante.
func advance_boss_phase() -> int:
	if boss_phase < boss_phase_count():
		boss_phase += 1
		boss_phase_changed.emit(boss_phase)
		boss_changed.emit()
		changed.emit()
	return boss_phase


## Daño al jefe en puntos porcentuales. Cambia de fase sola al cruzar cada umbral.
func damage_boss(percent: float) -> float:
	if percent <= 0.0:
		return boss_hp_percent
	boss_hp_percent = clampf(boss_hp_percent - percent, 0.0, 100.0)
	while boss_phase < boss_phase_count() and boss_hp_percent <= _phase_until(boss_phase):
		advance_boss_phase()
	boss_changed.emit()
	changed.emit()
	return boss_hp_percent


func _phase_until(phase: int) -> float:
	for d in boss_phases:
		if int(d["id"]) == phase:
			return float(d["until_percent"])
	return 0.0


func is_boss_defeated() -> bool:
	return boss_hp_percent <= 0.0


func boss_hp_text() -> String:
	return "%d %%" % roundi(boss_hp_percent)


static func format_clock(seconds: float) -> String:
	var s := maxi(0, ceili(seconds - 0.0001))
	return "%02d:%02d" % [s / 60, s % 60]


## «04:12»
func get_enrage_time_formatted() -> String:
	return format_clock(enrage_remaining)


# ==========================================================================
# Alertas tácticas centrales
# ==========================================================================
## `side`: lado del que suena el aviso (left · right · center). `direction`: hacia dónde moverse;
## vacío = el lado contrario al aviso («suena desde la derecha» → «todos a la izquierda»).
func trigger_alert(title: String, subtitle: String, duration_sec: float, side: String = "center", direction: String = "", emit := true) -> void:
	alert_title = title
	alert_subtitle = subtitle
	alert_duration = maxf(0.0, duration_sec)
	alert_remaining = alert_duration
	alert_side = side if SIDES.has(side) else "center"
	if direction == "" or not DIRECTIONS.has(direction):
		direction = {"right": "left", "left": "right"}.get(alert_side, "")
	alert_direction = direction
	alert_active = alert_remaining > 0.0
	if emit:
		alert_triggered.emit(alert_title, alert_side)
		alert_audio_cue.emit(alert_side, alert_pan())
		changed.emit()


func clear_alert() -> void:
	if not alert_active and alert_remaining <= 0.0:
		return
	alert_active = false
	alert_remaining = 0.0
	alert_cleared.emit()
	changed.emit()


## Número grande de la cuenta atrás (3 · 2 · 1).
func get_alert_countdown() -> int:
	return ceili(alert_remaining - 0.0001) if alert_active else 0


## Panorama estéreo del aviso: −1 izquierda · 0 centro · +1 derecha.
func alert_pan() -> float:
	match alert_side:
		"left":
			return -1.0
		"right":
			return 1.0
	return 0.0


## Ganancias de potencia constante por canal ({left, right}, 0..1).
func alert_stereo_gains() -> Dictionary:
	var a := (alert_pan() + 1.0) * PI * 0.25
	return {"left": cos(a), "right": sin(a)}


## Rotación de la flecha base (apunta a la izquierda) en radianes.
func alert_arrow_rotation() -> float:
	return {"left": 0.0, "right": PI, "up": PI * 0.5, "down": -PI * 0.5}.get(alert_direction, 0.0)


# ==========================================================================
# Sanador: maná, proyección y habilidades
# ==========================================================================
func mana_percent() -> int:
	return roundi(mana_current / mana_max * 100.0)


func set_mana(current: float, maximum: float = -1.0) -> void:
	if maximum > 0.0:
		mana_max = maximum
	mana_current = clampf(current, 0.0, mana_max)
	mana_changed.emit(mana_current, mana_max)
	changed.emit()


func set_mana_burn_rate(per_sec: float) -> void:
	mana_burn_per_sec = maxf(0.0, per_sec)
	changed.emit()


## Segundos que dura el maná al ritmo actual (INF si no se gasta, 0 sin maná).
func mana_duration_seconds() -> float:
	if mana_current <= 0.0:
		return 0.0
	if mana_burn_per_sec <= 0.0:
		return INF
	return mana_current / mana_burn_per_sec


## 100 → «1:40» · 3725 → «1:02:05» · INF → «∞».
static func format_duration(seconds: float) -> String:
	if is_inf(seconds) or is_nan(seconds):
		return "∞"
	var s := maxi(0, floori(seconds))
	if s >= 3600:
		return "%d:%02d:%02d" % [s / 3600, (s % 3600) / 60, s % 60]
	return "%d:%02d" % [s / 60, s % 60]


## «Maná 52 % · dura ~1:40 a este ritmo» (o «· sin gasto»).
func mana_projection_text() -> String:
	var life := mana_duration_seconds()
	if is_inf(life):
		return "Maná %d %% · sin gasto" % mana_percent()
	return "Maná %d %% · dura ~%s a este ritmo" % [mana_percent(), format_duration(life)]


func set_healer_hp(percent: float) -> void:
	healer_hp_percent = clampf(percent, 0.0, 100.0)
	changed.emit()


func ability_count() -> int:
	return abilities.size()


func ability(index: int) -> Dictionary:
	return abilities[index] if index >= 0 and index < abilities.size() else {}


## Índice de la habilidad de una tecla («1» … «0»), -1 si no existe.
func ability_index_for_key(key: String) -> int:
	for i in abilities.size():
		if abilities[i]["key"] == key:
			return i
	return -1


func is_ability_ready(index: int) -> bool:
	var a := ability(index)
	return not a.is_empty() and float(a["cooldown"]) <= 0.0


## «6» · «22» · «1:40» · «» si está lista.
static func format_cooldown(seconds: float) -> String:
	if seconds <= 0.0:
		return ""
	var s := ceili(seconds - 0.0001)
	if s >= 60:
		return "%d:%02d" % [s / 60, s % 60]
	return str(s)


func ability_cooldown_text(index: int) -> String:
	var a := ability(index)
	return format_cooldown(float(a.get("cooldown", 0.0)))


## Usa la habilidad (si está lista y hay maná) y arranca su enfriamiento.
func use_ability(index: int) -> bool:
	var a := ability(index)
	if a.is_empty() or not is_ability_ready(index) or mana_current < float(a["mana"]):
		return false
	_spend(float(a["mana"]))
	a["cooldown"] = float(a["cooldown_total"])
	changed.emit()
	return true


# ==========================================================================
# Simulación
# ==========================================================================
func start_encounter() -> void:
	if encounter_active:
		return
	encounter_active = true
	encounter_changed.emit(true)


func stop_encounter() -> void:
	if not encounter_active:
		return
	encounter_active = false
	encounter_changed.emit(false)


## Avanza el enrage, la cuenta atrás de la alerta y los enfriamientos (determinista).
func tick(delta: float) -> void:
	if delta <= 0.0:
		return
	if enrage_remaining > 0.0:
		enrage_remaining = maxf(0.0, enrage_remaining - delta)
		if enrage_remaining <= 0.0 and not enraged:
			enraged = true
			boss_enraged.emit()
	if alert_active:
		var before := get_alert_countdown()
		alert_remaining = maxf(0.0, alert_remaining - delta)
		if alert_remaining <= 0.0:
			alert_active = false
			alert_cleared.emit()
		elif get_alert_countdown() != before:
			alert_tick.emit(get_alert_countdown())
	for a in abilities:
		if float(a["cooldown"]) > 0.0:
			a["cooldown"] = maxf(0.0, float(a["cooldown"]) - delta)
	changed.emit()
