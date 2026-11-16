extends Node
## Ajustes globales del juego — UI v2.4 Paso 16 · ADR 114
## (design_ref/pantallas_html/MMO-Ajustes.html y MMO-Interfaz.html, PROMPT_ANTIGRAVITY.md §2.1,
## §4 «Accesibilidad», Anexos A, B y D).
##
## Autoload `SettingsService` o instanciable con `.new()` + `load_seed()`.
## Seed: res://config/settings/settings_seed.json · Persistencia: user://settings.cfg
##
## Modelo:
## - 7 categorías canónicas: graphics · audio · controls · interface · accessibility · network ·
##   account. Cada opción del seed declara clave, tipo (select · toggle · slider · mute · key ·
##   info), valores válidos, impacto en fps y si es «de pantalla» (`confirm`).
## - Borrador + aplicados: `set_value()` deja el cambio pendiente («3 cambios sin aplicar»);
##   `apply()` lo confirma y lo persiste; `discard()` (Deshacer) lo descarta.
## - Cambios de pantalla (resolución, modo, escala): tras aplicarlos empieza una cuenta atrás de
##   15 s. Si no se pulsa «Mantener» (`keep_display()`), `tick()` los revierte solos.
## - Presets gráficos Bajo · Medio · Alto · Ultra · Personal (se detecta solo).
## - Rendimiento estimado en tu PC: sesiones reales del seed ajustadas por el impacto en fps del
##   borrador; el refugio queda limitado por «Límite de fps en el refugio».
## - Controles: detección en vivo de atajos repetidos («G abre Señales y también llama a la
##   montura.») con solución en un clic («Montura → Z»).
## - Accesibilidad: daltonismo (paleta semántica), texto grande 115 %, reducir movimiento (apaga
##   el desenfoque, sacudidas y destellos), narrador, avisos 3D y formas además de colores.
## - Sonido: 5 buses canónicos sincronizados con AudioServer (mismo formato [audio] que
##   `audio_settings.gd`, así SoundManager los recupera al arrancar).

signal value_changed(category: String, key: String, value: Variant)
signal pending_changed(count: int)
signal applied(keys: Array)
signal discarded(count: int)
signal conflicts_changed(conflicts: Array)
signal display_confirm_started(seconds: float)
signal display_confirm_tick(remaining: float)
signal display_confirm_finished(kept: bool)
signal accessibility_changed
signal preset_changed(preset_id: String)
signal rebind_started(action: String)
signal rebind_finished(action: String, key: String)
signal narrated(text: String)

const AudioSettings = preload("res://audio/audio_settings.gd")

const DEFAULT_SEED_PATH := "res://config/settings/settings_seed.json"
const DEFAULT_SAVE_PATH := "user://settings.cfg"

const CAT_GRAPHICS := "graphics"
const CAT_AUDIO := "audio"
const CAT_CONTROLS := "controls"
const CAT_INTERFACE := "interface"
const CAT_ACCESSIBILITY := "accessibility"
const CAT_NETWORK := "network"
const CAT_ACCOUNT := "account"
const CATEGORIES: Array[String] = [CAT_GRAPHICS, CAT_AUDIO, CAT_CONTROLS, CAT_INTERFACE, CAT_ACCESSIBILITY, CAT_NETWORK, CAT_ACCOUNT]

const PRESET_CUSTOM := "custom"
const PRESETS: Array[String] = ["low", "medium", "high", "ultra", PRESET_CUSTOM]

const BUSES: Array[String] = ["Master", "Music", "SFX", "Ambience", "UI"]
const AUDIO_MUTE_SECTION := "audio_mute"

const TYPE_SELECT := "select"
const TYPE_TOGGLE := "toggle"
const TYPE_SLIDER := "slider"
const TYPE_MUTE := "mute"
const TYPE_KEY := "key"
const TYPE_INFO := "info"

const LARGE_TEXT_SCALE := 1.15
const DEFAULT_CONFIRM_SECONDS := 15.0
const MINUS := "−"

const COLOR_GOOD := "#4fe39a"
const COLOR_WARN := "#f5c35b"
const COLOR_IDLE := "#9aa6ae"
const COLOR_BAD := "#ff6b6b"

## Teclas admitidas al reasignar (además de A-Z y 0-9).
const EXTRA_KEYS: Array[String] = ["F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12",
	"Esc", "Space", "Tab", "Shift", "Ctrl", "Alt", "Q", "E", "R", "T", "Y", "U", "I", "K", "B", "V", "X", "Z", "F"]
## Teclas candidatas para resolver conflictos cuando la acción no sugiere una.
const FREE_KEY_CANDIDATES: Array[String] = ["Z", "X", "V", "B", "T", "Y", "U", "K", "R", "F", "Q", "E", "7", "8", "9", "0"]

var seed_data: Dictionary = {}
var categories: Array[Dictionary] = []          # {id, label}
var options: Dictionary = {}                   # category -> Array[Dictionary]
var graphics_presets: Array[Dictionary] = []
var performance: Dictionary = {}
var network_status: Dictionary = {}
var palettes: Dictionary = {}
var shapes: Dictionary = {}
var confirm_seconds := DEFAULT_CONFIRM_SECONDS

## Valores aplicados: category -> {key -> value}
var applied_values: Dictionary = {}
## Borrador: "category/key" -> value (solo los que difieren de lo aplicado)
var pending: Dictionary = {}

var save_path := DEFAULT_SAVE_PATH
var autosave := true
## Aplica al motor (AudioServer, escala 3D, ventana). Las ventanas de sistema solo fuera de headless.
var apply_to_engine := true
## Avanza la cuenta atrás de pantalla con `_process`. Los tests usan `tick()` a mano.
var auto_tick := true
var save_count := 0

## Cuenta atrás de seguridad de los cambios de pantalla.
var confirm_active := false
var confirm_remaining := 0.0
var confirm_snapshot: Dictionary = {}          # "category/key" -> valor previo

## Reasignación de tecla en curso ("" = ninguna).
var rebinding_action := ""
## Lo último aplicado al motor (para la UI y los tests).
var runtime_state: Dictionary = {}
var last_narration := ""
var narration_log: Array[String] = []

var _opt_index: Dictionary = {}                # "category/key" -> Dictionary
var _last_conflict_sig := ""


func _ready() -> void:
	if seed_data.is_empty():
		load_seed()
		load_saved()
		apply_runtime_all()
	set_process(true)


func _process(delta: float) -> void:
	if auto_tick and confirm_active:
		tick(delta)


# ==========================================================================
# Seed
# ==========================================================================
func load_seed(path: String = DEFAULT_SEED_PATH) -> bool:
	if not FileAccess.file_exists(path):
		push_warning("[SettingsService] Seed no encontrado: %s" % path)
		return false
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY:
		push_warning("[SettingsService] Seed inválido: %s" % path)
		return false
	load_from_dict(data)
	return true


func load_from_dict(data: Dictionary) -> void:
	seed_data = data.duplicate(true)
	confirm_seconds = float(data.get("confirm_seconds", DEFAULT_CONFIRM_SECONDS))
	categories.clear()
	for c in data.get("categories", []):
		categories.append({"id": str(c.get("id", "")), "label": str(c.get("label", ""))})
	options.clear()
	_opt_index.clear()
	var raw: Dictionary = data.get("options", {})
	for cat in CATEGORIES:
		var list: Array[Dictionary] = []
		for o in raw.get(cat, []):
			var opt: Dictionary = _norm(o)
			opt["category"] = cat
			list.append(opt)
			_opt_index[_k(cat, str(opt["key"]))] = opt
		options[cat] = list
	graphics_presets.clear()
	for p in data.get("graphics_presets", []):
		graphics_presets.append(_norm(p))
	performance = _norm(data.get("performance", {}))
	network_status = _norm(data.get("network_status", {}))
	palettes = (data.get("palettes", {}) as Dictionary).duplicate(true)
	shapes = (data.get("shapes", {}) as Dictionary).duplicate(true)
	reset_to_defaults(false)


## Vuelve a los valores por defecto del seed (sin borrador ni cuenta atrás).
func reset_to_defaults(emit := true) -> void:
	applied_values.clear()
	for cat in CATEGORIES:
		var d := {}
		for o in options.get(cat, []):
			d[str(o["key"])] = _norm(o.get("default"))
		applied_values[cat] = d
	pending.clear()
	confirm_active = false
	confirm_remaining = 0.0
	confirm_snapshot.clear()
	rebinding_action = ""
	_last_conflict_sig = _conflict_signature(find_conflicts())
	if emit:
		pending_changed.emit(0)
		accessibility_changed.emit()


# ==========================================================================
# Consulta del esquema
# ==========================================================================
func category_ids() -> Array[String]:
	var out: Array[String] = []
	for c in categories:
		out.append(str(c["id"]))
	return out


func category_label(cat: String) -> String:
	for c in categories:
		if c["id"] == cat:
			return str(c["label"])
	return cat


func has_option(cat: String, key: String) -> bool:
	return _opt_index.has(_k(cat, key))


func get_option(cat: String, key: String) -> Dictionary:
	return _opt_index.get(_k(cat, key), {})


## Opciones visibles de una categoría (las `hidden` — p. ej. muteo — se pintan dentro de su fila).
func visible_options(cat: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for o in options.get(cat, []):
		if not bool(o.get("hidden", false)):
			out.append(o)
	return out


func option_keys(cat: String) -> Array[String]:
	var out: Array[String] = []
	for o in options.get(cat, []):
		out.append(str(o["key"]))
	return out


func choice_values(cat: String, key: String) -> Array:
	var out: Array = []
	for ch in get_option(cat, key).get("choices", []):
		out.append(ch["value"])
	return out


func choice_label(cat: String, key: String, value: Variant = null) -> String:
	var opt := get_option(cat, key)
	if opt.is_empty():
		return ""
	var v: Variant = get_value(cat, key) if value == null else _norm(value)
	match str(opt.get("type", "")):
		TYPE_SLIDER:
			return "%d %%" % int(round(float(v)))
		TYPE_KEY:
			return str(v)
		TYPE_MUTE:
			return "Silenciado" if bool(v) else "Activo"
	for ch in opt.get("choices", []):
		if _eq(ch["value"], v):
			return str(ch["label"])
	return str(v)


# ==========================================================================
# Valores (borrador / aplicados)
# ==========================================================================
## Valor efectivo en la UI: el del borrador si existe, si no el aplicado.
func get_value(cat: String, key: String) -> Variant:
	var k := _k(cat, key)
	if pending.has(k):
		return pending[k]
	return get_applied(cat, key)


func get_applied(cat: String, key: String) -> Variant:
	return (applied_values.get(cat, {}) as Dictionary).get(key)


## Valor que realmente gobierna el juego (aplicado + bloqueos de accesibilidad).
func effective_value(cat: String, key: String) -> Variant:
	if cat == CAT_GRAPHICS and key == "motion_blur" and bool(get_applied(CAT_ACCESSIBILITY, "reduce_motion")):
		return false
	return get_applied(cat, key)


func is_valid_value(cat: String, key: String, value: Variant) -> bool:
	var opt := get_option(cat, key)
	if opt.is_empty() or value == null:
		return false
	var v: Variant = _norm(value)
	match str(opt.get("type", "")):
		TYPE_SLIDER:
			if not (v is int or v is float):
				return false
			return float(v) >= float(opt.get("min", 0)) - 0.0001 and float(v) <= float(opt.get("max", 100)) + 0.0001
		TYPE_MUTE:
			return v is bool
		TYPE_TOGGLE:
			return v is bool
		TYPE_KEY:
			return v is String and is_valid_key_name(v)
		_:
			for ch in opt.get("choices", []):
				if _eq(ch["value"], v):
					return true
			return false


## Opción bloqueada (no editable ahora mismo) y su motivo.
func is_locked(cat: String, key: String) -> bool:
	return lock_reason(cat, key) != ""


func lock_reason(cat: String, key: String) -> String:
	var opt := get_option(cat, key)
	if opt.is_empty():
		return "Opción desconocida"
	if str(opt.get("type", "")) == TYPE_INFO:
		return "Solo lectura"
	if bool(opt.get("locked", false)):
		return "Reservada"
	if cat == CAT_GRAPHICS and key == "motion_blur" and bool(get_value(CAT_ACCESSIBILITY, "reduce_motion")):
		return "Apagado por «Reducir movimiento»"
	return ""


## Cambia un valor en el borrador. Devuelve false si no es válido o está bloqueado.
func set_value(cat: String, key: String, value: Variant) -> bool:
	if not is_valid_value(cat, key, value) or is_locked(cat, key):
		return false
	var v: Variant = _norm(value)
	var opt := get_option(cat, key)
	if str(opt.get("type", "")) == TYPE_SLIDER:
		var step := float(opt.get("step", 1))
		v = clampf(snappedf(float(v), step), float(opt.get("min", 0)), float(opt.get("max", 100)))
		v = _norm(v)
	var k := _k(cat, key)
	var before: Variant = get_value(cat, key)
	if _eq(v, get_applied(cat, key)):
		pending.erase(k)
	else:
		pending[k] = v
	# Reducir movimiento fuerza el desenfoque apagado también en el borrador.
	if cat == CAT_ACCESSIBILITY and key == "reduce_motion" and bool(v):
		if bool(get_value(CAT_GRAPHICS, "motion_blur")):
			var kb := _k(CAT_GRAPHICS, "motion_blur")
			if _eq(false, get_applied(CAT_GRAPHICS, "motion_blur")):
				pending.erase(kb)
			else:
				pending[kb] = false
	if not _eq(before, v):
		value_changed.emit(cat, key, v)
		if cat == CAT_AUDIO:
			_apply_audio_bus(str(opt.get("bus", "")))
		if cat == CAT_GRAPHICS and graphics_presets.size() > 0:
			preset_changed.emit(current_preset())
	pending_changed.emit(pending_count())
	_check_conflicts()
	return true


## Cambia y aplica al instante solo esa opción (toggles del editor de interfaz, muteo…).
func set_and_apply(cat: String, key: String, value: Variant) -> bool:
	if not set_value(cat, key, value):
		return false
	var keys: Array = [_k(cat, key)]
	if cat == CAT_ACCESSIBILITY and key == "reduce_motion":
		keys.append(_k(CAT_GRAPHICS, "motion_blur"))
	apply(keys)
	return true


func toggle(cat: String, key: String) -> bool:
	return set_value(cat, key, not bool(get_value(cat, key)))


## Pasa a la siguiente (o anterior) opción de una lista. Devuelve el nuevo valor.
func cycle(cat: String, key: String, dir: int = 1) -> Variant:
	var vals := choice_values(cat, key)
	if vals.is_empty():
		return get_value(cat, key)
	var idx := 0
	for i in vals.size():
		if _eq(vals[i], get_value(cat, key)):
			idx = i
			break
	var n := posmod(idx + dir, vals.size())
	set_value(cat, key, vals[n])
	return get_value(cat, key)


func pending_count() -> int:
	return pending.size()


func has_pending(cat: String = "", key: String = "") -> bool:
	if cat == "":
		return not pending.is_empty()
	if key != "":
		return pending.has(_k(cat, key))
	for k in pending:
		if str(k).begins_with(cat + "/"):
			return true
	return false


func pending_keys() -> Array[String]:
	var out: Array[String] = []
	for k in pending:
		out.append(str(k))
	out.sort()
	return out


## Hay cambios de pantalla en el borrador (los que se deshacen solos en 15 s).
func pending_display_changes() -> int:
	var n := 0
	for k in pending:
		if bool(_opt_index.get(k, {}).get("confirm", false)):
			n += 1
	return n


## «3 cambios sin aplicar · los de pantalla se deshacen solos si no confirmas en 15 s»
func pending_summary() -> String:
	var n := pending_count()
	if n == 0:
		return "Sin cambios pendientes"
	var head := "%d %s sin aplicar" % [n, "cambio" if n == 1 else "cambios"]
	return "%s · los de pantalla se deshacen solos si no confirmas en %d s" % [head, int(confirm_seconds)]


## Confirma el borrador (o solo `only_keys` "category/key"). Devuelve las claves aplicadas.
func apply(only_keys: Array = []) -> Array:
	var keys: Array = []
	for k in pending_keys():
		if only_keys.is_empty() or only_keys.has(k):
			keys.append(k)
	if keys.is_empty():
		return []
	var snapshot := {}
	var touched_a11y := false
	for k in keys:
		var parts: PackedStringArray = str(k).split("/")
		var cat := parts[0]
		var key := parts[1]
		var opt: Dictionary = _opt_index.get(k, {})
		if bool(opt.get("confirm", false)):
			snapshot[k] = confirm_snapshot.get(k, get_applied(cat, key))
		(applied_values[cat] as Dictionary)[key] = pending[k]
		pending.erase(k)
		if cat == CAT_ACCESSIBILITY:
			touched_a11y = true
	for k in keys:
		apply_runtime(str(k).split("/")[0], str(k).split("/")[1])
	if autosave:
		save()
	if not snapshot.is_empty():
		for k in snapshot:
			confirm_snapshot[k] = snapshot[k]
		confirm_active = true
		confirm_remaining = confirm_seconds
		display_confirm_started.emit(confirm_seconds)
	applied.emit(keys)
	pending_changed.emit(pending_count())
	if touched_a11y:
		accessibility_changed.emit()
	_check_conflicts()
	return keys


## Deshacer: descarta todo el borrador. Devuelve cuántos cambios se descartaron.
func discard() -> int:
	var n := pending.size()
	if n == 0:
		return 0
	var buses := {}
	var touched_graphics := false
	for k in pending:
		var parts: PackedStringArray = str(k).split("/")
		if parts[0] == CAT_AUDIO:
			buses[str(_opt_index.get(k, {}).get("bus", ""))] = true
		if parts[0] == CAT_GRAPHICS:
			touched_graphics = true
	pending.clear()
	for b in buses:
		_apply_audio_bus(b)
	discarded.emit(n)
	pending_changed.emit(0)
	if touched_graphics:
		preset_changed.emit(current_preset())
	_check_conflicts()
	return n


## «Mantener»: confirma los cambios de pantalla y detiene la cuenta atrás.
func keep_display() -> bool:
	if not confirm_active:
		return false
	confirm_active = false
	confirm_remaining = 0.0
	confirm_snapshot.clear()
	display_confirm_finished.emit(true)
	return true


## Revierte ya los cambios de pantalla aplicados (botón «Revertir» o fin de la cuenta atrás).
func revert_display() -> bool:
	if not confirm_active:
		return false
	confirm_active = false
	confirm_remaining = 0.0
	for k in confirm_snapshot:
		var parts: PackedStringArray = str(k).split("/")
		(applied_values[parts[0]] as Dictionary)[parts[1]] = confirm_snapshot[k]
		pending.erase(k)
		apply_runtime(parts[0], parts[1])
	confirm_snapshot.clear()
	if autosave:
		save()
	display_confirm_finished.emit(false)
	pending_changed.emit(pending_count())
	preset_changed.emit(current_preset())
	return true


## Reloj manual (tests) o desde `_process`.
func tick(delta: float) -> void:
	if not confirm_active:
		return
	confirm_remaining = maxf(0.0, confirm_remaining - delta)
	display_confirm_tick.emit(confirm_remaining)
	if confirm_remaining <= 0.0:
		revert_display()


func confirm_text() -> String:
	if not confirm_active:
		return ""
	return "¿Mantener los cambios de pantalla? Se revierten en %d s" % int(ceil(confirm_remaining))


# ==========================================================================
# Búsqueda en vivo (Ctrl K)
# ==========================================================================
## Resultados de `query`: [{category, key, label, category_label, path}].
func search(query: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var tokens: Array[String] = []
	for t in normalize(query).split(" ", false):
		tokens.append(t)
	if tokens.is_empty():
		return out
	for cat in category_ids():
		for o in options.get(cat, []):
			if bool(o.get("hidden", false)):
				continue
			var hay := normalize("%s %s %s" % [o.get("label", ""), o.get("group", ""), " ".join(PackedStringArray(o.get("keywords", [])))])
			var ok := true
			for t in tokens:
				if not _token_match(hay, t):
					ok = false
					break
			if ok:
				out.append({"category": cat, "key": str(o["key"]), "label": str(o["label"]),
					"category_label": category_label(cat),
					"path": "%s › %s" % [category_label(cat), str(o["label"])]})
	return out


## «2 resultados: Gráficos › Calidad de sombras · Interfaz › Sombra del texto»
func search_summary(query: String) -> String:
	if normalize(query) == "":
		return ""
	var r := search(query)
	if r.is_empty():
		return "Sin resultados para «%s»" % query.strip_edges()
	var paths: PackedStringArray = []
	for x in r:
		paths.append(str(x["path"]))
	return "%d %s: %s" % [r.size(), "resultado" if r.size() == 1 else "resultados", " · ".join(paths)]


func search_hits(query: String, cat: String) -> Array[String]:
	var out: Array[String] = []
	for r in search(query):
		if r["category"] == cat:
			out.append(str(r["key"]))
	return out


static func normalize(s: String) -> String:
	var t := s.to_lower().strip_edges()
	var from := "áàäâéèëêíìïîóòöôúùüûñç"
	var to := "aaaaeeeeiiiioooouuuunc"
	for i in from.length():
		t = t.replace(from[i], to[i])
	var clean := ""
	for ch in t:
		clean += ch if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or ch == " " else " "
	while clean.contains("  "):
		clean = clean.replace("  ", " ")
	return clean.strip_edges()


static func _token_match(hay: String, token: String) -> bool:
	if hay.contains(token):
		return true
	# Plurales sencillos: «sombras» encuentra «sombra», «efectos» → «efecto».
	if token.length() > 4 and token.ends_with("es") and hay.contains(token.left(token.length() - 2)):
		return true
	if token.length() > 3 and token.ends_with("s") and hay.contains(token.left(token.length() - 1)):
		return true
	return false


# ==========================================================================
# Gráficos: presets e impacto en fps
# ==========================================================================
func preset_ids() -> Array[String]:
	var out: Array[String] = []
	for p in graphics_presets:
		out.append(str(p["id"]))
	return out


func preset_label(id: String) -> String:
	for p in graphics_presets:
		if p["id"] == id:
			return str(p["label"])
	return id


## Preset que coincide con el borrador actual o «custom» (Personal).
func current_preset() -> String:
	for p in graphics_presets:
		var vals: Dictionary = p.get("values", {})
		if vals.is_empty():
			continue
		var all := true
		for key in vals:
			if not _eq(get_value(CAT_GRAPHICS, key), vals[key]):
				all = false
				break
		if all:
			return str(p["id"])
	return PRESET_CUSTOM


## Aplica un preset al borrador. «custom» no cambia nada. Devuelve false si no existe.
func apply_preset(id: String) -> bool:
	if id == PRESET_CUSTOM:
		return true
	for p in graphics_presets:
		if p["id"] == id:
			var vals: Dictionary = p.get("values", {})
			for key in vals:
				if key == "motion_blur" and is_locked(CAT_GRAPHICS, key):
					continue
				set_value(CAT_GRAPHICS, key, vals[key])
			preset_changed.emit(current_preset())
			return true
	return false


## Impacto en fps de una opción con un valor (por defecto, el del borrador).
func fps_impact(cat: String, key: String, value: Variant = null) -> int:
	var opt := get_option(cat, key)
	var v: Variant = get_value(cat, key) if value == null else _norm(value)
	for ch in opt.get("choices", []):
		if _eq(ch["value"], v):
			return int(ch.get("fps", 0))
	return 0


## «−8 fps» / «+12 fps» / "" (sin impacto).
func fps_impact_text(cat: String, key: String, value: Variant = null) -> String:
	var n := fps_impact(cat, key, value)
	if n == 0:
		return ""
	return "%s%d fps" % ["+" if n > 0 else MINUS, absi(n)]


func fps_impact_color(cat: String, key: String, value: Variant = null) -> String:
	var n := fps_impact(cat, key, value)
	if n > 0:
		return COLOR_GOOD
	if n < 0:
		return COLOR_WARN
	return COLOR_IDLE


func _total_fps_delta(use_pending: bool) -> int:
	var total := 0
	for o in options.get(CAT_GRAPHICS, []):
		var key := str(o["key"])
		var v: Variant = get_value(CAT_GRAPHICS, key) if use_pending else get_applied(CAT_GRAPHICS, key)
		if key == "motion_blur" and bool(get_value(CAT_ACCESSIBILITY, "reduce_motion") if use_pending else get_applied(CAT_ACCESSIBILITY, "reduce_motion")):
			v = false
		total += fps_impact(CAT_GRAPHICS, key, v)
	return total


## Diferencia de fps estimada entre el borrador y lo aplicado (lo medido en tus sesiones).
func pending_fps_delta() -> int:
	return _total_fps_delta(true) - _total_fps_delta(false)


## [{id, label, fps, ratio, color, capped}] — «Rendimiento estimado en tu PC».
func estimated_performance() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var max_fps := float(performance.get("max_fps", 150))
	var good := int(performance.get("good_fps", 110))
	var warn := int(performance.get("warn_fps", 60))
	var delta := pending_fps_delta()
	for s in performance.get("scenarios", []):
		var fps := maxi(1, int(s.get("fps", 0)) + delta)
		var capped := false
		var cap_key := str(s.get("capped_by", ""))
		if cap_key != "":
			var cap := int(get_value(CAT_GRAPHICS, cap_key))
			if cap > 0 and fps >= cap:
				fps = cap
				capped = true
		var color := COLOR_IDLE if capped else (COLOR_GOOD if fps >= good else (COLOR_WARN if fps >= warn else COLOR_BAD))
		out.append({"id": str(s.get("id", "")), "label": str(s.get("label", "")), "fps": fps,
			"ratio": clampf(float(fps) / max_fps, 0.0, 1.0), "color": color, "capped": capped})
	return out


func performance_note() -> String:
	return str(performance.get("note", ""))


# ==========================================================================
# Controles: atajos repetidos y reasignación
# ==========================================================================
func get_binding(action: String) -> String:
	return str(get_value(CAT_CONTROLS, action))


func action_label(action: String) -> String:
	return str(get_option(CAT_CONTROLS, action).get("label", action))


func actions_for_key(key: String) -> Array[String]:
	var out: Array[String] = []
	for o in options.get(CAT_CONTROLS, []):
		if str(get_value(CAT_CONTROLS, str(o["key"]))).to_upper() == key.to_upper():
			out.append(str(o["key"]))
	return out


## [{key, actions:[...]}] con las teclas asignadas a más de una acción (en vivo, sobre el borrador).
func find_conflicts() -> Array[Dictionary]:
	var by_key := {}
	var order: Array[String] = []
	for o in options.get(CAT_CONTROLS, []):
		var action := str(o["key"])
		var key := str(get_value(CAT_CONTROLS, action))
		if key == "":
			continue
		var norm := key.to_upper()
		if not by_key.has(norm):
			by_key[norm] = {"key": key, "actions": []}
			order.append(norm)
		(by_key[norm]["actions"] as Array).append(action)
	var out: Array[Dictionary] = []
	for norm in order:
		if (by_key[norm]["actions"] as Array).size() > 1:
			out.append(by_key[norm])
	return out


func has_conflicts() -> bool:
	return not find_conflicts().is_empty()


## «G abre Señales y también llama a la montura.»
func conflict_message(conflict: Dictionary) -> String:
	var acts: Array = conflict.get("actions", [])
	if acts.size() < 2:
		return ""
	var verbs: PackedStringArray = []
	for a in acts:
		verbs.append(str(get_option(CAT_CONTROLS, str(a)).get("verb", action_label(str(a)))))
	var tail := " y también ".join(verbs.slice(1))
	return "%s %s y también %s." % [str(conflict.get("key", "")), verbs[0], tail]


## Acción que conviene mover y tecla libre: {action, key, label:"Montura → Z"}.
func suggest_resolution(conflict: Dictionary) -> Dictionary:
	var acts: Array = conflict.get("actions", [])
	if acts.size() < 2:
		return {}
	var mover := str(acts[acts.size() - 1])
	for a in acts:
		if str(get_option(CAT_CONTROLS, str(a)).get("suggested", "")) != "":
			mover = str(a)
			break
	var candidates: Array[String] = []
	var sug := str(get_option(CAT_CONTROLS, mover).get("suggested", ""))
	if sug != "":
		candidates.append(sug)
	candidates.append_array(FREE_KEY_CANDIDATES)
	for k in candidates:
		if actions_for_key(k).is_empty():
			return {"action": mover, "key": k, "label": "%s → %s" % [action_label(mover), k]}
	return {}


## Solución en un clic («Montura → Z»). Devuelve true si se resolvió.
func resolve_conflict(conflict: Dictionary = {}) -> bool:
	var c := conflict
	if c.is_empty():
		var all := find_conflicts()
		if all.is_empty():
			return false
		c = all[0]
	var s := suggest_resolution(c)
	if s.is_empty():
		return false
	return rebind(str(s["action"]), str(s["key"]))


## Asigna `key` a `action` (en el borrador). Esc queda reservada para cerrar ventanas.
func rebind(action: String, key: String) -> bool:
	var opt := get_option(CAT_CONTROLS, action)
	if opt.is_empty() or bool(opt.get("locked", false)):
		return false
	var k := canonical_key_name(key)
	if k == "" or k == "Esc":
		return false
	return set_value(CAT_CONTROLS, action, k)


## «Elegir otra»: espera la siguiente tecla para `action`.
func begin_rebind(action: String) -> bool:
	var opt := get_option(CAT_CONTROLS, action)
	if opt.is_empty() or bool(opt.get("locked", false)):
		return false
	rebinding_action = action
	rebind_started.emit(action)
	return true


func cancel_rebind() -> void:
	rebinding_action = ""


## Tecla capturada durante la reasignación. Esc cancela. Devuelve true si se asignó.
func capture_key(keycode: int) -> bool:
	if rebinding_action == "":
		return false
	var action := rebinding_action
	if keycode == KEY_ESCAPE:
		rebinding_action = ""
		return false
	var name := key_name_from_keycode(keycode)
	var ok := rebind(action, name)
	rebinding_action = ""
	if ok:
		rebind_finished.emit(action, name)
	return ok


static func key_name_from_keycode(keycode: int) -> String:
	if keycode == KEY_ESCAPE:
		return "Esc"
	var s := OS.get_keycode_string(keycode)
	match s:
		"Escape":
			return "Esc"
		"Control":
			return "Ctrl"
	return s


static func keycode_from_name(name: String) -> int:
	var n := canonical_key_name(name)
	match n:
		"Esc":
			return KEY_ESCAPE
		"Ctrl":
			return KEY_CTRL
		"":
			return KEY_NONE
	return OS.find_keycode_from_string(n)


static func canonical_key_name(name: String) -> String:
	var n := name.strip_edges()
	if n == "":
		return ""
	var up := n.to_upper()
	if up == "ESC" or up == "ESCAPE":
		return "Esc"
	if up == "CTRL" or up == "CONTROL":
		return "Ctrl"
	if up.length() == 1:
		var c := up[0]
		if (c >= "A" and c <= "Z") or (c >= "0" and c <= "9"):
			return up
		return ""
	for k in EXTRA_KEYS:
		if k.to_upper() == up:
			return k
	return ""


static func is_valid_key_name(name: String) -> bool:
	return canonical_key_name(name) != "" and canonical_key_name(name) == name


func category_has_warning(cat: String) -> bool:
	if cat == CAT_CONTROLS:
		return has_conflicts()
	return false


# ==========================================================================
# Accesibilidad
# ==========================================================================
func text_scale() -> float:
	return LARGE_TEXT_SCALE if bool(get_applied(CAT_ACCESSIBILITY, "large_text")) else 1.0


## Compatibilidad con EntryKit.apply_accessibility (escala de letra + alto contraste).
func font_scale() -> float:
	return text_scale()


var high_contrast: bool:
	get:
		return false


func reduce_motion() -> bool:
	return bool(get_applied(CAT_ACCESSIBILITY, "reduce_motion"))


func camera_shake_enabled() -> bool:
	return not reduce_motion()


func flashes_enabled() -> bool:
	return not reduce_motion()


func motion_blur_enabled() -> bool:
	return bool(effective_value(CAT_GRAPHICS, "motion_blur"))


func color_mode() -> String:
	return str(get_applied(CAT_ACCESSIBILITY, "color_mode"))


## Color semántico (good · warn · bad · info) según el modo de daltonismo.
func semantic_color(kind: String, mode: String = "") -> Color:
	var m := mode if mode != "" else color_mode()
	var pal: Dictionary = palettes.get(m, palettes.get("normal", {}))
	return Color(str(pal.get(kind, "#eef2f4")))


## Forma que acompaña al color si «Formas además de colores» está activo ("" si no).
func shape_for(kind: String) -> String:
	if not bool(get_applied(CAT_ACCESSIBILITY, "shapes_with_colors")):
		return ""
	return str(shapes.get(kind, ""))


func narrator_enabled() -> bool:
	return bool(get_applied(CAT_ACCESSIBILITY, "narrator"))


## Lee un texto si el narrador está activo (AccessKit/voz en off). Devuelve true si se narró.
func announce(text: String) -> bool:
	if not narrator_enabled() or text == "":
		return false
	last_narration = text
	narration_log.append(text)
	narrated.emit(text)
	return true


func directional_audio_enabled() -> bool:
	return bool(get_applied(CAT_ACCESSIBILITY, "directional_audio"))


# ==========================================================================
# Sonido
# ==========================================================================
func bus_volume(bus: String) -> float:
	return float(get_value(CAT_AUDIO, "volume_" + bus.to_lower()))


func bus_muted(bus: String) -> bool:
	return bool(get_value(CAT_AUDIO, "mute_" + bus.to_lower()))


func set_bus_volume(bus: String, value: float) -> bool:
	return set_value(CAT_AUDIO, "volume_" + bus.to_lower(), value)


func set_bus_muted(bus: String, muted: bool) -> bool:
	return set_value(CAT_AUDIO, "mute_" + bus.to_lower(), muted)


func toggle_bus_mute(bus: String) -> bool:
	return set_bus_muted(bus, not bus_muted(bus))


## Volumen efectivo (0 si está silenciado) que se envía a AudioServer.
func bus_effective_volume(bus: String) -> float:
	return 0.0 if bus_muted(bus) else bus_volume(bus)


func _apply_audio_bus(bus: String) -> void:
	if bus == "" or not apply_to_engine:
		return
	var vol := bus_effective_volume(bus)
	if AudioSettings.apply_bus_volume(StringName(bus), vol):
		runtime_state["bus_" + bus] = vol


# ==========================================================================
# Aplicación al motor
# ==========================================================================
func apply_runtime_all() -> void:
	for cat in CATEGORIES:
		for key in option_keys(cat):
			apply_runtime(cat, key)


func apply_runtime(cat: String, key: String) -> void:
	match cat:
		CAT_AUDIO:
			_apply_audio_bus(str(get_option(cat, key).get("bus", "")))
		CAT_GRAPHICS:
			_apply_graphics(key)
		CAT_ACCESSIBILITY:
			runtime_state["text_scale"] = text_scale()
			runtime_state["reduce_motion"] = reduce_motion()
			runtime_state["motion_blur"] = motion_blur_enabled()
			runtime_state["color_mode"] = color_mode()
		CAT_NETWORK:
			if key == "telemetry_rate":
				runtime_state["telemetry_hz"] = int(get_applied(cat, key))
			elif key == "realm":
				runtime_state["realm"] = str(get_applied(cat, key))
		_:
			pass


func _apply_graphics(key: String) -> void:
	var v: Variant = get_applied(CAT_GRAPHICS, key)
	match key:
		"resolution_scale":
			runtime_state["scaling_3d_scale"] = float(v) / 100.0
			if apply_to_engine and is_inside_tree():
				get_viewport().scaling_3d_scale = float(v) / 100.0
		"ui_brightness":
			runtime_state["ui_brightness"] = float(v) / 100.0
		"shelter_fps_limit":
			runtime_state["shelter_fps_limit"] = int(v)
		"motion_blur":
			runtime_state["motion_blur"] = motion_blur_enabled()
		"display_mode":
			runtime_state["display_mode"] = str(v)
			if _can_touch_window():
				match str(v):
					"windowed":
						DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
					"borderless":
						DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
					"fullscreen":
						DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		"resolution":
			runtime_state["resolution"] = str(v)
			if _can_touch_window() and str(get_applied(CAT_GRAPHICS, "display_mode")) == "windowed":
				var parts := str(v).split("x")
				if parts.size() == 2:
					DisplayServer.window_set_size(Vector2i(int(parts[0]), int(parts[1])))
		_:
			runtime_state[key] = v


func _can_touch_window() -> bool:
	return apply_to_engine and is_inside_tree() and DisplayServer.get_name() != "headless" and not OS.has_feature("editor_hint")


# ==========================================================================
# Persistencia (user://settings.cfg)
# ==========================================================================
## Guarda lo aplicado conservando otras secciones del archivo. [audio] usa el formato de
## audio_settings.gd (bus → entero 0-100) para que SoundManager lo lea al arrancar.
func save(path: String = "") -> Error:
	var p := path if path != "" else save_path
	var cfg := ConfigFile.new()
	cfg.load(p)
	for cat in CATEGORIES:
		for key in option_keys(cat):
			var opt := get_option(cat, key)
			var v: Variant = get_applied(cat, key)
			if cat == CAT_AUDIO:
				var bus := str(opt.get("bus", ""))
				if str(opt.get("type", "")) == TYPE_MUTE:
					cfg.set_value(AUDIO_MUTE_SECTION, bus, bool(v))
				else:
					cfg.set_value(AudioSettings.AUDIO_SECTION, bus, int(round(float(v))))
			elif str(opt.get("type", "")) != TYPE_INFO:
				cfg.set_value(cat, key, v)
	cfg.set_value("meta", "version", int(seed_data.get("version", 1)))
	var err := cfg.save(p)
	if err == OK:
		save_count += 1
	return err


## Carga lo guardado (valores inválidos se ignoran). Devuelve cuántos valores se cargaron.
func load_saved(path: String = "") -> int:
	var p := path if path != "" else save_path
	var cfg := ConfigFile.new()
	if cfg.load(p) != OK:
		return 0
	var n := 0
	for cat in CATEGORIES:
		for key in option_keys(cat):
			var opt := get_option(cat, key)
			var section := cat
			var skey := key
			if cat == CAT_AUDIO:
				skey = str(opt.get("bus", ""))
				section = AUDIO_MUTE_SECTION if str(opt.get("type", "")) == TYPE_MUTE else AudioSettings.AUDIO_SECTION
			if not cfg.has_section_key(section, skey):
				continue
			var v: Variant = _norm(cfg.get_value(section, skey))
			if is_valid_value(cat, key, v):
				(applied_values[cat] as Dictionary)[key] = v
				n += 1
	if bool(get_applied(CAT_ACCESSIBILITY, "reduce_motion")):
		(applied_values[CAT_GRAPHICS] as Dictionary)["motion_blur"] = false
	pending.clear()
	_last_conflict_sig = _conflict_signature(find_conflicts())
	accessibility_changed.emit()
	return n


## Snapshot serializable de lo aplicado (para depuración y tests).
func snapshot() -> Dictionary:
	return applied_values.duplicate(true)


# ==========================================================================
# Internos
# ==========================================================================
static func _k(cat: String, key: String) -> String:
	return "%s/%s" % [cat, key]


## JSON entrega números como float: 80.0 → 80 para comparar y mostrar.
static func _norm(v: Variant) -> Variant:
	if v is float and is_equal_approx(v, round(v)) and absf(v) < 1e9:
		return int(v)
	if v is Dictionary:
		var d := {}
		for k in v:
			d[k] = _norm(v[k])
		return d
	if v is Array:
		var a: Array = []
		for x in v:
			a.append(_norm(x))
		return a
	return v


static func _eq(a: Variant, b: Variant) -> bool:
	if (a is int or a is float) and (b is int or b is float):
		return is_equal_approx(float(a), float(b))
	if typeof(a) != typeof(b):
		return false
	return a == b


func _conflict_signature(c: Array) -> String:
	var parts: PackedStringArray = []
	for x in c:
		parts.append("%s:%s" % [x["key"], ",".join(PackedStringArray(x["actions"]))])
	return "|".join(parts)


func _check_conflicts() -> void:
	var c := find_conflicts()
	var sig := _conflict_signature(c)
	if sig != _last_conflict_sig:
		_last_conflict_sig = sig
		conflicts_changed.emit(c)
