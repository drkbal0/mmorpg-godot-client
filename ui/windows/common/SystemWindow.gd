extends "res://ui/templates/BaseWindow.gd"
## Base de Ajustes y Editor de interfaz (UI v2.4 Paso 16 · ADR 114).
##
## - Pantalla completa: fondo «.scene» (mapa-fondo) a brillo 0,4 + velo rgba(6,9,11,0.5) y un
##   escenario de 1440×810 (el lienzo del HTML) escalado de forma uniforme y centrado.
## - Barra del menú común (MenuBar) arriba, a todo el ancho (64 px).
## - Estado en `SettingsService` (inyectable como `settings`; si no hay autoload crea uno local).
## - Accesibilidad aplicada a todo el escenario: texto grande 115 % y brillo de la interfaz.
## - Teclado común: F10 (Ajustes), Esc (cerrar). Las subclases amplían con `_handle_key()`.
##
## Subclases: `_window_id()`, `_build()`, `refresh()`, `_handle_key()`, `_on_f10()`.

const T = preload("res://ui/tokens/hud_tokens.gd")
const Kit = preload("res://ui/windows/common/CinematicKit.gd")
const EK = preload("res://ui/windows/common/EntryKit.gd")
const SK = preload("res://ui/windows/common/SettingsKit.gd")
const SettingsScript = preload("res://shared-core/SettingsService.gd")
const MenuBarScene = preload("res://ui/menu/menu_bar.tscn")

signal closed

## Servicio de ajustes inyectable (tests). Si es null se usa /root/SettingsService o uno local.
var settings: Node = null
var stage: Control
var background: Control
var veil: ColorRect
var menu_bar: Node
var stage_scale := 1.0

var _built := false


func _init() -> void:
	theme = T.THEME
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	is_draggable = false


func _ready() -> void:
	window_id = _window_id()
	_resolve_settings()
	_build_frame()
	_build()
	super._ready()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(_layout)
	_layout()
	_connect_menu()
	refresh()


func center_on_screen() -> void:
	pass


# --- Virtuales -------------------------------------------------------------------
func _window_id() -> String:
	return ""


func _build() -> void:
	pass


func refresh() -> void:
	apply_accessibility()


func _handle_key(_ev: InputEventKey) -> bool:
	return false


func _on_f10() -> void:
	pass


# --- Servicio ----------------------------------------------------------------------
func _resolve_settings() -> void:
	if settings == null and is_inside_tree():
		settings = get_node_or_null("/root/SettingsService")
	if settings == null:
		settings = SettingsScript.new()
		settings.name = "LocalSettingsService"
		settings.autosave = false
		settings.apply_to_engine = false
		settings.load_seed()
	if settings.get_parent() == null:
		add_child(settings)
	var cb := Callable(self, "_on_accessibility_changed")
	if not settings.is_connected("accessibility_changed", cb):
		settings.connect("accessibility_changed", cb)


func _on_accessibility_changed() -> void:
	if _built:
		refresh()


# --- Marco ---------------------------------------------------------------------------
func _build_frame() -> void:
	if _built:
		return
	_built = true
	background = EK.scene_rect("Scene")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.modulate = Color(T.SETTINGS_SCENE_BRIGHTNESS, T.SETTINGS_SCENE_BRIGHTNESS, T.SETTINGS_SCENE_BRIGHTNESS)
	add_child(background)
	veil = ColorRect.new()
	veil.name = "Veil"
	veil.color = T.SETTINGS_VEIL
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(veil)
	stage = Control.new()
	stage.name = "Stage"
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.size = T.CINEMA_DESIGN_SIZE
	add_child(stage)
	menu_bar = MenuBarScene.instantiate()
	menu_bar.name = "MenuBar"
	stage.add_child(menu_bar)
	if menu_bar is Control:
		(menu_bar as Control).set_anchors_preset(Control.PRESET_TOP_LEFT)
	menu_bar.position = Vector2.ZERO
	menu_bar.size = Vector2(T.CINEMA_DESIGN_SIZE.x, T.MENU_BAR_HEIGHT)


func _layout() -> void:
	if not _built:
		return
	var area := size if size.x > 0 else get_viewport_rect().size
	stage_scale = Kit.fit_stage(stage, area)
	if menu_bar is Control:
		(menu_bar as Control).size = Vector2(T.CINEMA_DESIGN_SIZE.x, T.MENU_BAR_HEIGHT)


## Coloca `c` en el escenario (px del diseño 1440×810).
func place(c: Control, x: float, y: float, w: float, h: float) -> void:
	if c.get_parent() == null:
		stage.add_child(c)
	c.position = Vector2(x, y)
	c.custom_minimum_size = Vector2(w, h)
	c.size = Vector2(w, h)


func _connect_menu() -> void:
	if menu_bar == null:
		return
	var commerce := get_node_or_null("/root/CommerceService") if is_inside_tree() else null
	if commerce != null and "gold" in commerce:
		menu_bar.set_currencies(int(commerce.gold), int(commerce.prisms))
	else:
		menu_bar.set_currencies(12480, 340)
	var orch := _orchestrator()
	if orch != null and orch.has_method("connect_menu_bar"):
		orch.connect_menu_bar(menu_bar)
	else:
		if not menu_bar.close_requested.is_connected(close_window):
			menu_bar.close_requested.connect(close_window)
		if not menu_bar.settings_requested.is_connected(_on_f10):
			menu_bar.settings_requested.connect(_on_f10)


## Solo enruta a otras ventanas si la abrió el orquestador.
func _orchestrator() -> Node:
	var orch := get_node_or_null("/root/UIOrchestrator") if is_inside_tree() else null
	if orch != null and "window_layer" in orch and get_parent() == orch.window_layer:
		return orch
	return null


func close_window() -> void:
	var orch := _orchestrator()
	if orch != null:
		orch.close_window(window_id)
	else:
		visible = false
	closed.emit()


# --- Teclado -------------------------------------------------------------------------
func handle_key_event(ev: InputEventKey) -> bool:
	if _handle_key(ev):
		return true
	var code := ev.keycode if ev.keycode != KEY_NONE else ev.physical_keycode
	if ev.ctrl_pressed or ev.alt_pressed or ev.meta_pressed:
		return false
	match code:
		KEY_ESCAPE:
			close_window()
			return true
		KEY_F10:
			_on_f10()
			return true
	return false


func handle_key(keycode: int, ctrl: bool = false, shift: bool = false) -> bool:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.pressed = true
	ev.ctrl_pressed = ctrl
	ev.shift_pressed = shift
	return handle_key_event(ev)


func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not (event is InputEventKey) or not event.pressed or event.is_echo():
		return
	if handle_key_event(event as InputEventKey):
		get_viewport().set_input_as_handled()


# --- Accesibilidad ---------------------------------------------------------------------
func apply_accessibility() -> void:
	if stage == null or settings == null:
		return
	EK.apply_accessibility(stage, settings)
	var b := float(settings.get_applied(SettingsScript.CAT_GRAPHICS, "ui_brightness")) / 100.0
	if b <= 0.0:
		b = 1.0
	stage.modulate = Color(b, b, b, 1.0)


## Color semántico según el modo de daltonismo (good · warn · bad · info).
func sem(kind: String) -> Color:
	return settings.semantic_color(kind) if settings != null else Color.WHITE


## Traduce los colores canónicos del servicio a la paleta de daltonismo activa.
func sem_hex(hex: String) -> Color:
	match hex:
		SettingsScript.COLOR_GOOD:
			return sem("good")
		SettingsScript.COLOR_WARN:
			return sem("warn")
		SettingsScript.COLOR_BAD:
			return sem("bad")
	return Color(hex)


static func kind_of_hex(hex: String) -> String:
	match hex:
		SettingsScript.COLOR_GOOD:
			return "good"
		SettingsScript.COLOR_WARN:
			return "warn"
		SettingsScript.COLOR_BAD:
			return "bad"
	return "info"
