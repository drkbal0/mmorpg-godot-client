extends Node
## Editor de interfaz — UI v2.4 Paso 16 · ADR 114 (design_ref/pantallas_html/MMO-Interfaz.html,
## PROMPT_ANTIGRAVITY.md §2.1 y §4 «Accesibilidad»).
##
## Autoload `UIEditorService` o instanciable con `.new()` + `load_seed()`.
## Seed: res://config/ui_editor/ui_editor_seed.json · Persistencia: user://ui_layouts.cfg
##
## - 9 módulos editables del HUD sobre un lienzo de 944×531: Grupo, Objetivo, Línea de tiempo,
##   Minimapa, Misiones, Chat, Barra de acción, Retrato y Rendimiento.
## - Diseños por rol: Tanque · Sanador · Daño · Explorador · Raid 20 · Streamer (+ Social para la
##   ciudad). Cada diseño guarda sus propias ediciones. «Cambiar solo según el contenido»:
##   Mazmorra → Daño · Raid → Raid 20 · Mundo → Explorador · Ciudad → Social.
## - Edición espacial: posición libre o ajustada a la cuadrícula de 24 px, guías magnéticas de
##   alineación con otros módulos (línea rosa #ff6fa8 «alineado con Objetivo»), escala 50–150 % y
##   opacidad fuera de combate 0–100 %. «Probar en combate simulado» muestra todo al 100 %.
## - Códigos para compartir: serialización completa y verificable («HUD-XXX-XXX-…», 63 símbolos
##   base32 de Crockford con suma de control) y código corto registrado («HUD-7QK-D2M»).
## - Historial: `undo()` / `redo()` (Ctrl+Z · Ctrl+Y · Ctrl+Shift+Z).

signal layout_changed
signal module_changed(module_id: String)
signal selection_changed(module_id: String)
signal preset_changed(preset_id: String)
signal guides_changed(guides: Array)
signal history_changed(can_undo: bool, can_redo: bool)
signal code_imported(code: String, ok: bool)
signal combat_simulation_changed(active: bool)
signal auto_switch_changed(enabled: bool)

const DEFAULT_SEED_PATH := "res://config/ui_editor/ui_editor_seed.json"
const DEFAULT_SAVE_PATH := "user://ui_layouts.cfg"

const MODULE_IDS: Array[String] = ["group_frames", "target_frame", "timeline", "minimap", "quest_tracker",
	"chat_box", "action_bar", "player_portrait", "performance_meter"]
const ROLE_PRESETS: Array[String] = ["tank", "healer", "dps", "explorer", "raid20", "streamer"]
const CONTENT_TYPES: Array[String] = ["dungeon", "raid", "world", "city"]

const CODE_PREFIX := "HUD"
const CODE_ALPHABET := "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
const CODE_VERSION := 1
const CODE_SYMBOLS := 63
const SHORT_SYMBOLS := 6
const COORD_BITS := 10
const SCALE_BITS := 5
const OPACITY_BITS := 7
const CHECK_BITS := 10

const GUIDE_COLOR := Color("#ff6fa8")

var seed_data: Dictionary = {}
var canvas_size := Vector2(944, 531)
var grid := 24
var align_threshold := 8.0
var scale_min := 0.5
var scale_max := 1.5
var scale_step := 0.05
var history_limit := 50
var modules_def: Array[Dictionary] = []        # orden canónico: {id, label, detail, x, y, w, h, opacity}
var presets: Array[Dictionary] = []            # {id, label, context, chip, modules}
var content_presets: Dictionary = {}
var content_labels: Dictionary = {}
var shared_codes: Dictionary = {}              # "HUD-7QK-D2M" -> {preset} | {code}
var default_preset := "dps"

## preset -> {module_id -> {x, y, scale, opacity, visible, detail}}
var layouts: Dictionary = {}
var active_preset := "dps"
var selected := ""
var snap_to_grid := true
var auto_switch_by_content := true
var current_content := ""
var simulating_combat := false
var guides: Array[Dictionary] = []
var last_import_error := ""

var save_path := DEFAULT_SAVE_PATH
var autosave := true
var save_count := 0

var _undo: Array[Dictionary] = []
var _redo: Array[Dictionary] = []
var _dragging := ""


func _ready() -> void:
	if seed_data.is_empty():
		load_seed()
		load_saved()


# ==========================================================================
# Seed
# ==========================================================================
func load_seed(path: String = DEFAULT_SEED_PATH) -> bool:
	if not FileAccess.file_exists(path):
		push_warning("[UIEditorService] Seed no encontrado: %s" % path)
		return false
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY:
		return false
	load_from_dict(data)
	return true


func load_from_dict(data: Dictionary) -> void:
	seed_data = data.duplicate(true)
	var c: Dictionary = data.get("canvas", {})
	canvas_size = Vector2(float(c.get("width", 944)), float(c.get("height", 531)))
	grid = int(data.get("grid", 24))
	align_threshold = float(data.get("align_threshold", 8))
	scale_min = float(data.get("scale_min", 0.5))
	scale_max = float(data.get("scale_max", 1.5))
	scale_step = float(data.get("scale_step", 0.05))
	history_limit = int(data.get("history_limit", 50))
	modules_def.clear()
	var by_id := {}
	for m in data.get("modules", []):
		by_id[str(m.get("id", ""))] = m
	for id in MODULE_IDS:
		var m: Dictionary = by_id.get(id, {})
		modules_def.append({"id": id, "label": str(m.get("label", id)), "detail": str(m.get("detail", "")),
			"x": float(m.get("x", 0)), "y": float(m.get("y", 0)), "w": float(m.get("w", 100)), "h": float(m.get("h", 60)),
			"opacity": float(m.get("opacity", 1.0))})
	presets.clear()
	for p in data.get("presets", []):
		presets.append({"id": str(p.get("id", "")), "label": str(p.get("label", "")), "context": str(p.get("context", "")),
			"chip": bool(p.get("chip", true)), "modules": (p.get("modules", {}) as Dictionary).duplicate(true)})
	content_presets = (data.get("content_presets", {}) as Dictionary).duplicate(true)
	content_labels = (data.get("content_labels", {}) as Dictionary).duplicate(true)
	shared_codes = (data.get("shared_codes", {}) as Dictionary).duplicate(true)
	default_preset = str(data.get("default_preset", "dps"))
	reset_all(str(data.get("default_selected", "")))


## Todos los diseños vuelven al seed (sin historial).
func reset_all(select_id: String = "") -> void:
	layouts.clear()
	for p in presets:
		layouts[p["id"]] = pristine_layout(str(p["id"]))
	active_preset = default_preset if layouts.has(default_preset) else (str(presets[0]["id"]) if presets.size() > 0 else "")
	selected = select_id if MODULE_IDS.has(select_id) else ""
	snap_to_grid = true
	auto_switch_by_content = true
	current_content = ""
	simulating_combat = false
	guides = alignment_guides(selected)
	_undo.clear()
	_redo.clear()
	_dragging = ""


# ==========================================================================
# Diseños por rol
# ==========================================================================
func preset_ids(chips_only: bool = false) -> Array[String]:
	var out: Array[String] = []
	for p in presets:
		if not chips_only or bool(p["chip"]):
			out.append(str(p["id"]))
	return out


func has_preset(id: String) -> bool:
	return layouts.has(id)


func preset_label(id: String) -> String:
	for p in presets:
		if p["id"] == id:
			return str(p["label"])
	return id


## «Daño · mazmorra»
func preset_context(id: String = "") -> String:
	var pid := id if id != "" else active_preset
	for p in presets:
		if p["id"] == pid:
			return str(p["context"]) if str(p["context"]) != "" else str(p["label"])
	return pid


func _preset_index(id: String) -> int:
	for i in presets.size():
		if presets[i]["id"] == id:
			return i
	return -1


## Diseño del seed para un preset (módulos base + sus cambios), ya ajustado al lienzo.
func pristine_layout(id: String) -> Dictionary:
	var overrides: Dictionary = {}
	for p in presets:
		if p["id"] == id:
			overrides = p["modules"]
	var out := {}
	for d in modules_def:
		var mid: String = d["id"]
		var o: Dictionary = overrides.get(mid, {})
		var m := {"x": float(o.get("x", d["x"])), "y": float(o.get("y", d["y"])),
			"scale": clampf(float(o.get("scale", 1.0)), scale_min, scale_max),
			"opacity": clampf(float(o.get("opacity", d["opacity"])), 0.0, 1.0),
			"visible": bool(o.get("visible", true)),
			"detail": str(o.get("detail", d["detail"]))}
		var sz := Vector2(float(d["w"]), float(d["h"])) * float(m["scale"])
		m["x"] = clampf(float(m["x"]), 0.0, maxf(0.0, canvas_size.x - sz.x))
		m["y"] = clampf(float(m["y"]), 0.0, maxf(0.0, canvas_size.y - sz.y))
		out[mid] = m
	return out


func is_preset_modified(id: String = "") -> bool:
	var pid := id if id != "" else active_preset
	if not layouts.has(pid):
		return false
	return not _layouts_equal(layouts[pid], pristine_layout(pid))


## Cambia el diseño activo (deshacible). Devuelve false si no existe.
func apply_preset(id: String, record: bool = true) -> bool:
	if not layouts.has(id):
		return false
	if id == active_preset:
		return true
	if record:
		_push_history()
	active_preset = id
	guides.clear()
	guides_changed.emit(guides)
	preset_changed.emit(id)
	layout_changed.emit()
	_autosave()
	return true


## Restaura el diseño del seed (deshacible).
func reset_preset(id: String = "") -> bool:
	var pid := id if id != "" else active_preset
	if not layouts.has(pid):
		return false
	_push_history()
	layouts[pid] = pristine_layout(pid)
	guides.clear()
	layout_changed.emit()
	_autosave()
	return true


func set_auto_switch(enabled: bool) -> void:
	if auto_switch_by_content == enabled:
		return
	auto_switch_by_content = enabled
	auto_switch_changed.emit(enabled)
	_autosave()


## El juego avisa del tipo de contenido (dungeon · raid · world · city). Con «Cambiar solo según
## el contenido» activo cambia al diseño asociado. Devuelve el diseño activo resultante.
func on_content_changed(content: String) -> String:
	current_content = content
	if auto_switch_by_content and content_presets.has(content):
		apply_preset(str(content_presets[content]), false)
	return active_preset


## «Mazmorra → Daño · Raid → Raid 20 · Mundo → Explorador · Ciudad → Social»
func content_rule_text() -> String:
	var parts: PackedStringArray = []
	for c in CONTENT_TYPES:
		if content_presets.has(c):
			parts.append("%s → %s" % [str(content_labels.get(c, c.capitalize())), preset_label(str(content_presets[c]))])
	return " · ".join(parts)


# ==========================================================================
# Módulos
# ==========================================================================
func module_def(id: String) -> Dictionary:
	for d in modules_def:
		if d["id"] == id:
			return d
	return {}


func module_label(id: String) -> String:
	return str(module_def(id).get("label", id))


func module(id: String) -> Dictionary:
	return (layouts.get(active_preset, {}) as Dictionary).get(id, {})


func module_base_size(id: String) -> Vector2:
	var d := module_def(id)
	return Vector2(float(d.get("w", 0)), float(d.get("h", 0)))


func module_rect(id: String) -> Rect2:
	var m := module(id)
	if m.is_empty():
		return Rect2()
	return Rect2(Vector2(float(m["x"]), float(m["y"])), module_base_size(id) * float(m["scale"]))


func module_scale(id: String) -> float:
	return float(module(id).get("scale", 1.0))


func module_opacity(id: String) -> float:
	return float(module(id).get("opacity", 1.0))


func is_module_visible(id: String) -> bool:
	return bool(module(id).get("visible", true))


## Opacidad que se ve ahora: 100 % en combate (o en el combate simulado).
func effective_opacity(id: String, in_combat: bool = false) -> float:
	if in_combat or simulating_combat:
		return 1.0
	return module_opacity(id)


func visible_modules() -> Array[String]:
	var out: Array[String] = []
	for id in MODULE_IDS:
		if is_module_visible(id):
			out.append(id)
	return out


## Texto secundario del módulo: tamaño del seleccionado («340 × 64 · 100 %»), opacidad del chat o
## el detalle del diseño («5 marcos», «2 filas × 10»…).
func module_detail(id: String) -> String:
	var m := module(id)
	if m.is_empty():
		return ""
	if id == selected:
		var sz := module_rect(id).size
		return "%d × %d · %d %%" % [roundi(sz.x), roundi(sz.y), roundi(float(m["scale"]) * 100.0)]
	if id == "chat_box":
		return "%d %% fuera de combate" % roundi(float(m["opacity"]) * 100.0)
	return str(m.get("detail", ""))


func select_module(id: String) -> bool:
	if id != "" and not MODULE_IDS.has(id):
		return false
	if selected == id:
		return true
	selected = id
	guides = alignment_guides(id) if id != "" else ([] as Array[Dictionary])
	selection_changed.emit(id)
	guides_changed.emit(guides)
	return true


## Módulo bajo un punto del lienzo (el de encima primero) o "".
func module_at(point: Vector2) -> String:
	for i in range(MODULE_IDS.size() - 1, -1, -1):
		var id := MODULE_IDS[i]
		if is_module_visible(id) and module_rect(id).has_point(point):
			return id
	return ""


func set_snap(enabled: bool) -> void:
	snap_to_grid = enabled
	_autosave()


func snap_value(v: float) -> float:
	return roundf(v / float(grid)) * float(grid)


func clamp_position(id: String, pos: Vector2, scale_override: float = -1.0) -> Vector2:
	var s := scale_override if scale_override > 0.0 else module_scale(id)
	var sz := module_base_size(id) * s
	return Vector2(clampf(pos.x, 0.0, maxf(0.0, canvas_size.x - sz.x)), clampf(pos.y, 0.0, maxf(0.0, canvas_size.y - sz.y)))


## Posición final para `raw` (cuadrícula + guías magnéticas + límites) y guías activas.
## `magnet = false` (flechas) ignora la cuadrícula y el imán. {pos: Vector2, guides: Array}
func resolve_position(id: String, raw: Vector2, magnet: bool = true) -> Dictionary:
	var sz := module_rect(id).size
	var pos := raw
	var out_guides: Array[Dictionary] = []
	if magnet:
		if snap_to_grid:
			pos = Vector2(snap_value(raw.x), snap_value(raw.y))
		var gx := _best_alignment(id, Rect2(raw, sz), "x")
		if not gx.is_empty():
			pos.x = raw.x + float(gx["offset"])
		var gy := _best_alignment(id, Rect2(raw, sz), "y")
		if not gy.is_empty():
			pos.y = raw.y + float(gy["offset"])
	pos = clamp_position(id, pos)
	# Las guías se recalculan sobre la posición final (exactas).
	for axis in ["x", "y"]:
		var g := _best_alignment(id, Rect2(pos, sz), axis, 0.5)
		if not g.is_empty():
			out_guides.append(g)
	return {"pos": pos, "guides": out_guides}


## Guías de alineación exactas del módulo en su posición actual.
func alignment_guides(id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if id == "" or module(id).is_empty():
		return out
	var r := module_rect(id)
	for axis in ["x", "y"]:
		var g := _best_alignment(id, r, axis, 0.5)
		if not g.is_empty():
			out.append(g)
	return out


func _edges(r: Rect2, axis: String) -> Array[float]:
	if axis == "x":
		return [r.position.x, r.get_center().x, r.end.x]
	return [r.position.y, r.get_center().y, r.end.y]


func _gap(a: Rect2, b: Rect2, axis: String) -> float:
	# Distancia en el eje perpendicular (para desempatar: el vecino más cercano gana).
	if axis == "x":
		return maxf(0.0, maxf(a.position.y - b.end.y, b.position.y - a.end.y))
	return maxf(0.0, maxf(a.position.x - b.end.x, b.position.x - a.end.x))


func _best_alignment(id: String, r: Rect2, axis: String, threshold: float = -1.0) -> Dictionary:
	var th := threshold if threshold >= 0.0 else align_threshold
	var best := {}
	var best_d := INF
	var best_gap := INF
	var names := ["left", "center", "right"] if axis == "x" else ["top", "center", "bottom"]
	var mine := _edges(r, axis)
	for oid in MODULE_IDS:
		if oid == id or not is_module_visible(oid):
			continue
		var orect := module_rect(oid)
		var theirs := _edges(orect, axis)
		var gap := _gap(r, orect, axis)
		for i in 3:
			for j in 3:
				# Bordes con bordes del mismo tipo o centro con centro (como las guías de diseño).
				if (i == 1) != (j == 1):
					continue
				var d := theirs[j] - mine[i]
				var ad := absf(d)
				if ad > th:
					continue
				if ad < best_d - 0.01 or (absf(ad - best_d) <= 0.01 and gap < best_gap - 0.01):
					best_d = ad
					best_gap = gap
					best = {"axis": axis, "at": theirs[j], "offset": d, "target": oid, "edge": names[i],
						"label": "alineado con %s" % module_label(oid), "color": GUIDE_COLOR}
	return best


## Mueve un módulo (deshacible). Devuelve la posición final.
func move_module(id: String, raw: Vector2, record: bool = true, magnet: bool = true) -> Vector2:
	if module(id).is_empty():
		return Vector2.ZERO
	var res := resolve_position(id, raw, magnet)
	var pos: Vector2 = res["pos"]
	var m := module(id)
	if record and (not is_equal_approx(float(m["x"]), pos.x) or not is_equal_approx(float(m["y"]), pos.y)):
		_push_history()
	m["x"] = pos.x
	m["y"] = pos.y
	guides = res["guides"]
	guides_changed.emit(guides)
	module_changed.emit(id)
	layout_changed.emit()
	if record:
		_autosave()
	return pos


## Arrastre: un solo paso de historial por gesto.
func begin_drag(id: String) -> bool:
	if module(id).is_empty() or not is_module_visible(id):
		return false
	_push_history()
	_dragging = id
	select_module(id)
	return true


func drag_to(raw: Vector2) -> Vector2:
	if _dragging == "":
		return Vector2.ZERO
	return move_module(_dragging, raw, false)


func end_drag() -> String:
	var id := _dragging
	_dragging = ""
	if id != "":
		# Si el gesto no movió nada, el paso de historial sobra.
		if not _undo.is_empty() and _layouts_equal(_undo.back()["layout"], layouts[active_preset]) and _undo.back()["preset"] == active_preset:
			_undo.pop_back()
			history_changed.emit(can_undo(), can_redo())
		_autosave()
	return id


func is_dragging() -> bool:
	return _dragging != ""


## Flechas: una celda con cuadrícula, 1 px sin ella (sin imán: el ajuste fino manda).
func nudge(id: String, dir: Vector2) -> Vector2:
	var step := float(grid) if snap_to_grid else 1.0
	return move_module(id, module_rect(id).position + dir * step, true, false)


func set_module_scale(id: String, s: float) -> float:
	var m := module(id)
	if m.is_empty():
		return 0.0
	var v := clampf(snappedf(s, scale_step), scale_min, scale_max)
	if is_equal_approx(v, float(m["scale"])):
		return v
	_push_history()
	m["scale"] = v
	var p := clamp_position(id, Vector2(float(m["x"]), float(m["y"])), v)
	m["x"] = p.x
	m["y"] = p.y
	module_changed.emit(id)
	layout_changed.emit()
	_autosave()
	return v


func set_module_opacity(id: String, o: float) -> float:
	var m := module(id)
	if m.is_empty():
		return 0.0
	var v := clampf(snappedf(o, 0.01), 0.0, 1.0)
	if is_equal_approx(v, float(m["opacity"])):
		return v
	_push_history()
	m["opacity"] = v
	module_changed.emit(id)
	layout_changed.emit()
	_autosave()
	return v


func set_module_visible(id: String, v: bool) -> bool:
	var m := module(id)
	if m.is_empty() or bool(m["visible"]) == v:
		return false
	_push_history()
	m["visible"] = v
	module_changed.emit(id)
	layout_changed.emit()
	_autosave()
	return true


func simulate_combat(active: bool) -> void:
	if simulating_combat == active:
		return
	simulating_combat = active
	combat_simulation_changed.emit(active)


# ==========================================================================
# Historial
# ==========================================================================
func _snapshot() -> Dictionary:
	return {"preset": active_preset, "layout": (layouts.get(active_preset, {}) as Dictionary).duplicate(true)}


func _restore(s: Dictionary) -> void:
	active_preset = str(s["preset"])
	layouts[active_preset] = (s["layout"] as Dictionary).duplicate(true)
	guides = alignment_guides(selected)
	guides_changed.emit(guides)
	preset_changed.emit(active_preset)
	layout_changed.emit()


func _push_history() -> void:
	_undo.append(_snapshot())
	while _undo.size() > history_limit:
		_undo.pop_front()
	_redo.clear()
	history_changed.emit(can_undo(), can_redo())


func can_undo() -> bool:
	return not _undo.is_empty()


func can_redo() -> bool:
	return not _redo.is_empty()


func history_size() -> int:
	return _undo.size()


func undo() -> bool:
	if _undo.is_empty():
		return false
	_redo.append(_snapshot())
	_restore(_undo.pop_back())
	history_changed.emit(can_undo(), can_redo())
	_autosave()
	return true


func redo() -> bool:
	if _redo.is_empty():
		return false
	_undo.append(_snapshot())
	_restore(_redo.pop_back())
	history_changed.emit(can_undo(), can_redo())
	_autosave()
	return true


## Ctrl+Z deshacer · Ctrl+Y / Ctrl+Shift+Z rehacer. Devuelve true si consumió el evento.
func handle_shortcut(event: InputEvent) -> bool:
	if not (event is InputEventKey) or not event.pressed or event.is_echo():
		return false
	var k := event as InputEventKey
	if not (k.ctrl_pressed or k.meta_pressed):
		return false
	var code := k.keycode if k.keycode != KEY_NONE else k.physical_keycode
	if code == KEY_Z and k.shift_pressed:
		return redo() or true
	if code == KEY_Z:
		return undo() or true
	if code == KEY_Y:
		return redo() or true
	return false


# ==========================================================================
# Códigos para compartir
# ==========================================================================
## Código completo y autocontenido del diseño activo («HUD-XXX-XXX-…»).
func export_code(preset_id: String = "") -> String:
	var pid := preset_id if preset_id != "" else active_preset
	return encode_layout(pid, layouts.get(pid, {}))


## Código corto para la interfaz (chip «HUD-7QK-D2M»). Si el diseño está sin tocar y el seed lo
## registra, devuelve ese; si no, deriva uno del código completo y lo registra.
func share_code(preset_id: String = "") -> String:
	var pid := preset_id if preset_id != "" else active_preset
	if not is_preset_modified(pid):
		for code in shared_codes:
			var e: Dictionary = shared_codes[code]
			if str(e.get("preset", "")) == pid and not e.has("code"):
				return str(code)
	var full := export_code(pid)
	var short := short_code_for(full)
	shared_codes[short] = {"code": full}
	return short


## «HUD-ABC-DEF»: 30 bits derivados del código completo.
static func short_code_for(full_code: String) -> String:
	var h := 2166136261
	for i in full_code.length():
		h = ((h ^ full_code.unicode_at(i)) * 16777619) & 0xFFFFFFFF
	var s := ""
	for i in SHORT_SYMBOLS:
		s += CODE_ALPHABET[(h >> (5 * i)) & 31]
	return "%s-%s-%s" % [CODE_PREFIX, s.substr(0, 3), s.substr(3, 3)]


static func _bits_put(bits: Array[int], value: int, n: int) -> void:
	for i in range(n - 1, -1, -1):
		bits.append((value >> i) & 1)


static func _bits_get(bits: Array[int], at: int, n: int) -> int:
	var v := 0
	for i in n:
		v = (v << 1) | bits[at + i]
	return v


static func _checksum(bits: Array[int]) -> int:
	var h := 7
	for b in bits:
		h = (h * 31 + b + 3) % 1021
	return h


func encode_layout(preset_id: String, layout: Dictionary) -> String:
	var bits: Array[int] = []
	_bits_put(bits, CODE_VERSION, 4)
	_bits_put(bits, maxi(0, _preset_index(preset_id)), 3)
	_bits_put(bits, 1 if snap_to_grid else 0, 1)
	for id in MODULE_IDS:
		var m: Dictionary = layout.get(id, {})
		_bits_put(bits, 1 if bool(m.get("visible", true)) else 0, 1)
		_bits_put(bits, clampi(roundi(float(m.get("x", 0))), 0, 1023), COORD_BITS)
		_bits_put(bits, clampi(roundi(float(m.get("y", 0))), 0, 1023), COORD_BITS)
		_bits_put(bits, clampi(roundi((float(m.get("scale", 1.0)) - scale_min) / scale_step), 0, 31), SCALE_BITS)
		_bits_put(bits, clampi(roundi(float(m.get("opacity", 1.0)) * 100.0), 0, 100), OPACITY_BITS)
	_bits_put(bits, _checksum(bits), CHECK_BITS)
	while bits.size() % 5 != 0:
		bits.append(0)
	var sym := ""
	for i in range(0, bits.size(), 5):
		sym += CODE_ALPHABET[_bits_get(bits, i, 5)]
	var groups: PackedStringArray = [CODE_PREFIX]
	for i in range(0, sym.length(), 3):
		groups.append(sym.substr(i, 3))
	return "-".join(groups)


## Normaliza (mayúsculas, sin guiones; O→0, I/L→1). "" si hay símbolos inválidos.
static func normalize_code(code: String) -> String:
	var c := code.strip_edges().to_upper().replace(" ", "")
	if c.begins_with(CODE_PREFIX):
		c = c.substr(CODE_PREFIX.length())
	c = c.replace("-", "").replace("O", "0").replace("I", "1").replace("L", "1")
	for ch in c:
		if not CODE_ALPHABET.contains(ch):
			return ""
	return c


## {ok, preset, layout, snap, error}
func decode_code(code: String) -> Dictionary:
	var sym := normalize_code(code)
	if sym == "":
		return {"ok": false, "error": "Código con símbolos no válidos"}
	if sym.length() != CODE_SYMBOLS:
		return {"ok": false, "error": "Longitud de código incorrecta"}
	var bits: Array[int] = []
	for ch in sym:
		_bits_put(bits, CODE_ALPHABET.find(ch), 5)
	var payload_len := 8 + MODULE_IDS.size() * (1 + COORD_BITS * 2 + SCALE_BITS + OPACITY_BITS)
	var payload: Array[int] = bits.slice(0, payload_len)
	var check := _bits_get(bits, payload_len, CHECK_BITS)
	if check != _checksum(payload):
		return {"ok": false, "error": "El código no es válido (suma de control)"}
	var at := 0
	var version := _bits_get(bits, at, 4)
	at += 4
	if version != CODE_VERSION:
		return {"ok": false, "error": "Versión de código no compatible"}
	var pidx := _bits_get(bits, at, 3)
	at += 3
	if pidx >= presets.size():
		return {"ok": false, "error": "Diseño desconocido"}
	var snap := _bits_get(bits, at, 1) == 1
	at += 1
	var layout := {}
	for id in MODULE_IDS:
		var vis := _bits_get(bits, at, 1) == 1
		at += 1
		var x := _bits_get(bits, at, COORD_BITS)
		at += COORD_BITS
		var y := _bits_get(bits, at, COORD_BITS)
		at += COORD_BITS
		var si := _bits_get(bits, at, SCALE_BITS)
		at += SCALE_BITS
		var op := _bits_get(bits, at, OPACITY_BITS)
		at += OPACITY_BITS
		if op > 100:
			return {"ok": false, "error": "Opacidad fuera de rango"}
		var s := snappedf(scale_min + si * scale_step, 0.01)
		if s > scale_max + 0.001:
			return {"ok": false, "error": "Escala fuera de rango"}
		var base := module_base_size(id) * s
		if x + base.x > canvas_size.x + 1.0 or y + base.y > canvas_size.y + 1.0:
			return {"ok": false, "error": "Módulo fuera del lienzo"}
		var d := module_def(id)
		layout[id] = {"x": float(x), "y": float(y), "scale": s, "opacity": op / 100.0, "visible": vis,
			"detail": str(_detail_override(str(presets[pidx]["id"]), id, str(d.get("detail", ""))))}
	return {"ok": true, "preset": str(presets[pidx]["id"]), "layout": layout, "snap": snap}


func _detail_override(pid: String, id: String, fallback: String) -> String:
	for p in presets:
		if p["id"] == pid:
			return str((p["modules"] as Dictionary).get(id, {}).get("detail", fallback))
	return fallback


## Importa un código corto registrado o uno completo (deshacible). {ok, preset, error}
func import_code(code: String) -> Dictionary:
	var c := code.strip_edges().to_upper()
	var r := {}
	if shared_codes.has(c):
		var e: Dictionary = shared_codes[c]
		if e.has("code"):
			r = decode_code(str(e["code"]))
		elif layouts.has(str(e.get("preset", ""))):
			r = {"ok": true, "preset": str(e["preset"]), "layout": pristine_layout(str(e["preset"])), "snap": snap_to_grid}
		else:
			r = {"ok": false, "error": "Código desconocido"}
	elif normalize_code(c).length() == SHORT_SYMBOLS:
		r = {"ok": false, "error": "Código desconocido"}
	else:
		r = decode_code(c)
	if not r.get("ok", false):
		last_import_error = str(r.get("error", "Código no válido"))
		code_imported.emit(code, false)
		return {"ok": false, "error": last_import_error}
	_push_history()
	active_preset = str(r["preset"])
	layouts[active_preset] = r["layout"]
	snap_to_grid = bool(r.get("snap", snap_to_grid))
	last_import_error = ""
	guides = alignment_guides(selected)
	guides_changed.emit(guides)
	preset_changed.emit(active_preset)
	layout_changed.emit()
	code_imported.emit(code, true)
	_autosave()
	return {"ok": true, "preset": active_preset}


# ==========================================================================
# Persistencia (user://ui_layouts.cfg)
# ==========================================================================
func save(path: String = "") -> Error:
	var p := path if path != "" else save_path
	var cfg := ConfigFile.new()
	cfg.set_value("editor", "active_preset", active_preset)
	cfg.set_value("editor", "snap_to_grid", snap_to_grid)
	cfg.set_value("editor", "auto_switch", auto_switch_by_content)
	cfg.set_value("editor", "version", int(seed_data.get("version", 1)))
	for pid in layouts:
		for id in MODULE_IDS:
			var m: Dictionary = (layouts[pid] as Dictionary).get(id, {})
			cfg.set_value("layout_" + str(pid), id, {"x": m.get("x", 0.0), "y": m.get("y", 0.0), "scale": m.get("scale", 1.0),
				"opacity": m.get("opacity", 1.0), "visible": m.get("visible", true)})
	var err := cfg.save(p)
	if err == OK:
		save_count += 1
	return err


## Carga diseños guardados (validando límites). Devuelve cuántos módulos se cargaron.
func load_saved(path: String = "") -> int:
	var p := path if path != "" else save_path
	var cfg := ConfigFile.new()
	if cfg.load(p) != OK:
		return 0
	var n := 0
	for pid in layouts:
		var section := "layout_" + str(pid)
		if not cfg.has_section(section):
			continue
		for id in MODULE_IDS:
			var v = cfg.get_value(section, id, null)
			if typeof(v) != TYPE_DICTIONARY:
				continue
			var m: Dictionary = (layouts[pid] as Dictionary)[id]
			var s := clampf(float(v.get("scale", 1.0)), scale_min, scale_max)
			var sz := module_base_size(id) * s
			m["scale"] = s
			m["x"] = clampf(float(v.get("x", m["x"])), 0.0, maxf(0.0, canvas_size.x - sz.x))
			m["y"] = clampf(float(v.get("y", m["y"])), 0.0, maxf(0.0, canvas_size.y - sz.y))
			m["opacity"] = clampf(float(v.get("opacity", 1.0)), 0.0, 1.0)
			m["visible"] = bool(v.get("visible", true))
			n += 1
	var ap := str(cfg.get_value("editor", "active_preset", active_preset))
	if layouts.has(ap):
		active_preset = ap
	snap_to_grid = bool(cfg.get_value("editor", "snap_to_grid", snap_to_grid))
	auto_switch_by_content = bool(cfg.get_value("editor", "auto_switch", auto_switch_by_content))
	_undo.clear()
	_redo.clear()
	layout_changed.emit()
	return n


func _autosave() -> void:
	if autosave:
		save()


static func _layouts_equal(a: Dictionary, b: Dictionary) -> bool:
	for id in MODULE_IDS:
		var x: Dictionary = a.get(id, {})
		var y: Dictionary = b.get(id, {})
		for f in ["x", "y", "scale", "opacity"]:
			if not is_equal_approx(float(x.get(f, 0.0)), float(y.get(f, 0.0))):
				return false
		if bool(x.get("visible", true)) != bool(y.get("visible", true)):
			return false
	return true
