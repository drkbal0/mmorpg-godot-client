extends "res://ui/templates/BaseWindow.gd"
## Base de las pantallas de Entrada (UI v2.4 Paso 15): Launcher, Inicio de sesión, Selección,
## Creación y Carga.
##
## - Pantalla completa: fondo «.scene» (mapa-fondo) + velo, y un escenario de 1440×810 (el lienzo
##   del HTML) escalado de forma uniforme y centrado en el viewport.
## - Estado en `AuthLifecycleService` (inyectable como `service`; si no hay autoload crea uno local).
## - Accesibilidad previa al ingreso aplicada a toda la pantalla (A− / A / A+, alto contraste) y
##   Ctrl+Alt+N (narrador) en todas las pantallas de entrada.
## - `navigate(id)`: si la abrió el orquestador, cierra esta pantalla y abre la siguiente.
##
## Subclases: `_screen_id()`, `_screen()`, `_veil_base()`, `_build()`, `refresh()`, `_handle_key()`.

const T = preload("res://ui/tokens/hud_tokens.gd")
const Kit = preload("res://ui/windows/common/CinematicKit.gd")
const EK = preload("res://ui/windows/common/EntryKit.gd")
const AuthScript = preload("res://shared-core/AuthLifecycleService.gd")

signal navigated(target_id: String, params: Dictionary)

## Servicio inyectable (tests). Si es null se usa /root/AuthLifecycleService o uno local.
var service: Node = null
var stage: Control
var background: Control
var veil: ColorRect
var stage_scale := 1.0
var last_navigation := ""
var a11y_bar: PanelContainer
var a11y_buttons: Dictionary = {}

var _built := false


func _init() -> void:
	theme = T.THEME
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	is_draggable = false


func _ready() -> void:
	window_id = _screen_id()
	_resolve_service()
	_build_frame()
	_build()
	super._ready()
	add_to_group("entry_screen")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(_layout)
	_layout()
	refresh()
	_announce_screen()


func center_on_screen() -> void:
	pass


# --- Virtuales -------------------------------------------------------------------
func _screen_id() -> String:
	return ""


## Pantalla del flujo del servicio que representa esta ventana.
func _screen() -> String:
	return ""


## Alfa base del velo (0 = sin velo).
func _veil_base() -> float:
	return 0.0


func _use_scene_background() -> bool:
	return true


func _screen_title() -> String:
	return ""


func _build() -> void:
	pass


func refresh() -> void:
	apply_accessibility()


func _handle_key(_keycode: int, _ev: InputEventKey) -> bool:
	return false


func _service_signals() -> Array:
	return []


func _on_service_changed(_a = null, _b = null) -> void:
	if _built:
		refresh()


# --- Servicio --------------------------------------------------------------------
func _resolve_service() -> void:
	if service == null and is_inside_tree():
		service = get_node_or_null("/root/AuthLifecycleService")
	if service == null:
		service = AuthScript.new()
		service.name = "LocalAuthLifecycleService"
		service.sync_auth_manager = false
		service.load_seed()
	if service.get_parent() == null:
		add_child(service)
	var cb_a11y := Callable(self, "_on_accessibility_changed")
	if not service.is_connected("accessibility_changed", cb_a11y):
		service.connect("accessibility_changed", cb_a11y)
	for sig in _service_signals():
		var cb := Callable(self, "_on_service_changed")
		if not service.is_connected(sig, cb):
			service.connect(sig, cb)


func _on_accessibility_changed() -> void:
	if not _built:
		return
	if veil != null:
		veil.color.a = service.veil_alpha(_veil_base())
	refresh()


func initialize_window(_params: Dictionary) -> void:
	if service == null:
		_resolve_service()
	if _screen() != "":
		service.go_to(_screen())
	visible = true
	if _built:
		refresh()


# --- Marco: fondo, velo y escenario -------------------------------------------------
func _build_frame() -> void:
	if _built:
		return
	_built = true
	if _use_scene_background():
		background = EK.scene_rect("Scene")
	else:
		var bg := ColorRect.new()
		bg.name = "Background"
		bg.color = T.LAUNCHER_BG
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		background = bg
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	veil = ColorRect.new()
	veil.name = "Veil"
	veil.color = Color(5 / 255.0, 8 / 255.0, 10 / 255.0, service.veil_alpha(_veil_base()))
	veil.visible = _veil_base() > 0.0
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(veil)
	stage = Control.new()
	stage.name = "Stage"
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.size = T.CINEMA_DESIGN_SIZE
	add_child(stage)


func _layout() -> void:
	if not _built:
		return
	var area := size if size.x > 0 else get_viewport_rect().size
	stage_scale = Kit.fit_stage(stage, area)


## Coloca `c` en el escenario con anclas: lado izquierdo/superior o derecho/inferior (px del diseño).
## Pasa -1 a los lados que no apliquen; los bloques anclados abajo crecen hacia arriba.
func place(c: Control, left: float, top: float, right: float = -1.0, bottom: float = -1.0, width: float = -1.0) -> void:
	if c.get_parent() == null:
		stage.add_child(c)
	var ax_l := 0.0 if left >= 0.0 else 1.0
	var ax_r := 1.0 if right >= 0.0 else (0.0 if left >= 0.0 else 1.0)
	var ay_t := 0.0 if top >= 0.0 else 1.0
	var ay_b := 1.0 if bottom >= 0.0 else (0.0 if top >= 0.0 else 1.0)
	c.anchor_left = ax_l
	c.anchor_right = ax_r
	c.anchor_top = ay_t
	c.anchor_bottom = ay_b
	if left >= 0.0:
		c.offset_left = left
		c.offset_right = (-right if right >= 0.0 else left + maxf(width, 0.0))
		c.grow_horizontal = Control.GROW_DIRECTION_END if right < 0.0 else Control.GROW_DIRECTION_BOTH
	else:
		c.offset_right = -right
		c.offset_left = -right - maxf(width, 0.0)
		c.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	if top >= 0.0:
		c.offset_top = top
		c.offset_bottom = -bottom if bottom >= 0.0 else top
		c.grow_vertical = Control.GROW_DIRECTION_END if bottom < 0.0 else Control.GROW_DIRECTION_BOTH
	else:
		c.offset_bottom = -bottom
		c.offset_top = -bottom
		c.grow_vertical = Control.GROW_DIRECTION_BEGIN


# --- Navegación --------------------------------------------------------------------
## Solo enruta a otras ventanas si la abrió el orquestador.
func _orchestrator() -> Node:
	var orch := get_node_or_null("/root/UIOrchestrator")
	if orch != null and "window_layer" in orch and get_parent() == orch.window_layer:
		return orch
	return null


func navigate(target_id: String, params: Dictionary = {}) -> void:
	last_navigation = target_id
	navigated.emit(target_id, params)
	var orch := _orchestrator()
	if orch != null:
		orch.close_window(window_id)
		if target_id != "":
			orch.open_window(target_id, params)


# --- Teclado ---------------------------------------------------------------------
## Atajo común: Ctrl+Alt+N narrador. Luego delega en `_handle_key` de la pantalla.
func handle_key_event(ev: InputEventKey) -> bool:
	var code := ev.keycode if ev.keycode != KEY_NONE else ev.physical_keycode
	if code == KEY_N and ev.ctrl_pressed and ev.alt_pressed:
		service.toggle_narrator()
		return true
	return _handle_key(code, ev)


func handle_key(keycode: int) -> bool:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.pressed = true
	return handle_key_event(ev)


func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not (event is InputEventKey) or not event.pressed or event.is_echo():
		return
	if handle_key_event(event as InputEventKey):
		get_viewport().set_input_as_handled()


# --- Accesibilidad -------------------------------------------------------------------
func apply_accessibility() -> void:
	if stage != null:
		EK.apply_accessibility(stage, service)


func _announce_screen() -> void:
	var t := _screen_title()
	if t != "" and service != null:
		service.announce(t)


## Barra «Accesibilidad» (A− · A · A+ · Alto contraste · Narrador Ctrl Alt N · Daltonismo).
func build_a11y_bar() -> PanelContainer:
	var sb := Kit.box(T.LOGIN_A11Y_BG, 14, 1, Color(1, 1, 1, 0.08))
	a11y_bar = Kit.panel("Accessibility", sb, 10, 8)
	a11y_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	var h := EK.hbox("Row", 8)
	a11y_bar.add_child(h)
	var cap := Kit.caps("Accesibilidad")
	cap.name = "Caps"
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 6)
	m.add_theme_constant_override("margin_right", 6)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(cap)
	h.add_child(m)
	a11y_buttons.clear()
	var defs := [
		["FontSmaller", "A−", func() -> void: service.set_font_step(0)],
		["FontNormal", "A", func() -> void: service.set_font_step(1)],
		["FontLarger", "A+", func() -> void: service.set_font_step(2)],
		["HighContrast", "Alto contraste", func() -> void: service.toggle_high_contrast()],
		["Narrator", "Narrador", func() -> void: service.toggle_narrator()],
		["Colorblind", "Daltonismo", func() -> void: service.cycle_colorblind_mode()],
	]
	for d in defs:
		var b := Button.new()
		b.name = d[0]
		b.text = d[1]
		b.focus_mode = Control.FOCUS_ALL
		b.custom_minimum_size = Vector2(0, 28)
		b.add_theme_font_override("font", T.font("medium"))
		b.add_theme_font_size_override("font_size", 13)
		b.pressed.connect(d[2])
		if d[0] == "Narrator":
			var kb := Kit.kbd("Ctrl Alt N")
			kb.name = "Kbd"
			kb.mouse_filter = Control.MOUSE_FILTER_IGNORE
			kb.position = Vector2(70, 5)
			b.add_child(kb)
		h.add_child(b)
		a11y_buttons[d[0]] = b
	refresh_a11y_bar()
	return a11y_bar


func refresh_a11y_bar() -> void:
	if a11y_bar == null:
		return
	var active := {
		"FontSmaller": service.font_step == 0,
		"FontNormal": service.font_step == 1,
		"FontLarger": service.font_step == 2,
		"HighContrast": service.high_contrast,
		"Narrator": service.narrator,
		"Colorblind": service.colorblind_mode != "none",
	}
	for k in a11y_buttons:
		var b: Button = a11y_buttons[k]
		var on: bool = active[k]
		b.set_meta("active", on)
		b.toggle_mode = false
		var pad_r := 10
		if k == "Narrator":
			pad_r = 10 + 72
		for st in ["normal", "hover", "pressed", "focus"]:
			var bg: Color = T.LOGIN_A11Y_ACTIVE if on else T.BUTTON_BG
			if st == "hover":
				bg = bg.lightened(0.08)
			var s := Kit.box(bg, 8)
			if st == "focus":
				s = Kit.box(Color.TRANSPARENT, 8, 2, T.ACCENT_DEFAULT)
			s.content_margin_left = 10
			s.content_margin_right = pad_r
			b.add_theme_stylebox_override(st, s)
		for fc in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			b.add_theme_color_override(fc, T.TEXT if on else T.TEXT_KEY)
	(a11y_buttons["Colorblind"] as Button).text = service.colorblind_label()
	(a11y_buttons["HighContrast"] as Button).text = "Alto contraste" + (" ✓" if service.high_contrast else "")
	(a11y_buttons["Narrator"] as Button).tooltip_text = "Narrador de pantalla (Ctrl+Alt+N)"
