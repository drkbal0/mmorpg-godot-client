@tool
extends PanelContainer
## Menú común superior UI v2.4 (sección 2.1). Reutilizado por todas las ventanas.
##
## Izquierda: «MENÚ» + pestañas con atajo visible
##   Equipo C · Poderes N · Misiones L · Mapa M · Códice J · Social O · Refugio H ·
##   Comercio P (submenú Mercado · Tienda · Pase de batalla).
## Derecha: búsqueda global (Ctrl K) · Oro · Prismas (+ abre la Tienda) ·
##   Ajustes (F10) · Cerrar (Esc).
##
## La barra NO abre ventanas: emite señales de navegación que
## `UIOrchestrator.connect_menu_bar()` traduce a `toggle_window()`.
## Todo dirigido por datos: `configure_tabs()` permite sustituir la tabla.

const T = preload("res://ui/tokens/hud_tokens.gd")
const VectorIcon = preload("res://ui/components/base/vector_icon.gd")
const CurrencyLabel = preload("res://ui/components/base/currency_label.gd")

## Pestaña o sub-pestaña elegida (por clic o atajo).
signal tab_selected(tab_id: String)
signal subtab_selected(tab_id: String, subtab_id: String)
## Petición de navegación para UIOrchestrator: id de ventana registrada + parámetros.
signal navigation_requested(window_id: String, params: Dictionary)
signal search_requested
signal shop_requested(source: String)
signal settings_requested
signal close_requested

## Tabla canónica de pestañas (sección 2.1). `window` = id en UIWindowRegistry.
const DEFAULT_TABS: Array[Dictionary] = [
	{"id": "equipo", "icon": "M12 4a4 4 0 1 0 0 8a4 4 0 1 0 0-8M4 21c0-4 3.6-7 8-7s8 3 8 7", "label": "Equipo", "key": KEY_C, "window": "inventory"},
	{"id": "poderes", "icon": "M12 3a3 3 0 1 0 0 6a3 3 0 1 0 0-6M6 15a3 3 0 1 0 0 6a3 3 0 1 0 0-6M18 15a3 3 0 1 0 0 6a3 3 0 1 0 0-6M10.6 8.6l-3.2 6.8M13.4 8.6l3.2 6.8M9 18h6", "label": "Poderes", "key": KEY_N, "window": "powers"},
	{"id": "misiones", "icon": "M4 5h16M4 10h16M4 15h10M4 20h7", "label": "Misiones", "key": KEY_L, "window": "quests_window"},
	{"id": "mapa", "icon": "M3 6l6-3 6 3 6-3v15l-6 3-6-3-6 3zM9 3v15M15 6v15", "label": "Mapa", "key": KEY_M, "window": "map_window"},
	{"id": "codice", "icon": "M2 4h7a3 3 0 0 1 3 3v14a2 2 0 0 0-2-2H2zM22 4h-7a3 3 0 0 0-3 3v14a2 2 0 0 1 2-2h8z", "label": "Códice", "key": KEY_J, "window": "codex_window"},
	{"id": "social", "icon": "M9 4a4 4 0 1 0 0 8a4 4 0 1 0 0-8M2 21c0-4 3-6.5 7-6.5s7 2.5 7 6.5M16 4.5a3.5 3.5 0 0 1 0 7M18 14.5c2.4.6 4 2.8 4 6.5", "label": "Social", "key": KEY_O, "window": "social_window"},
	{"id": "refugio", "icon": "M3 11l9-7 9 7M5 9.5V21h14V9.5M10 21v-6h4v6", "label": "Refugio", "key": KEY_H, "window": "shelter"},
	{"id": "comercio", "icon": "M6 7h12l-1 14H7zM9 7V5a3 3 0 0 1 6 0v2", "label": "Comercio", "key": KEY_P, "window": "marketplace_window",
		"subtabs": [
			{"id": "mercado", "label": "Mercado", "window": "marketplace_window"},
			{"id": "tienda", "label": "Tienda", "window": "shop_window", "under_construction": true},
			{"id": "pase", "label": "Pase de batalla", "window": "battle_pass_window", "under_construction": true},
		]},
]

const SEARCH_WINDOW := "global_search"
const SETTINGS_WINDOW := "options_menu"
const SHOP_SUBTAB := "tienda"

const ICON_SEARCH := "M11 4a7 7 0 1 0 0 14a7 7 0 1 0 0-14M16.5 16.5L21 21"
const ICON_SETTINGS := "M12 8.5a3.5 3.5 0 1 0 0 7a3.5 3.5 0 1 0 0-7M12 2.5v2.5M12 19v2.5M2.5 12h2.5M19 12h2.5M5.3 5.3l1.8 1.8M16.9 16.9l1.8 1.8M5.3 18.7l1.8-1.8M16.9 7.1l1.8-1.8"

@export var title_text: String = "MENÚ":
	set(v):
		title_text = v
		if _title:
			_title.text = v

## Si es true la barra procesa sus atajos en `_unhandled_key_input`.
## Por defecto false: UIInputRouter sigue siendo el despachador global (ver
## docs/ui/tabla_validacion_roadmap_ui_v2.md por los conflictos P y F10).
@export var capture_shortcuts: bool = false

@export var accent: Color = T.ACCENT_DEFAULT:
	set(v):
		accent = v
		_apply_accent()

var tabs_data: Array[Dictionary] = []
var active_tab: String = ""
var active_subtab: Dictionary = {}  # tab_id -> subtab_id (última elegida)

var gold_label: CurrencyLabel
var prisms_label: CurrencyLabel
var search_button: Button
var settings_button: Button
var close_button: Button
var commerce_popup: PopupMenu

var _row: HBoxContainer
var _title: Label
var _tabs_box: HBoxContainer
var _tab_buttons: Dictionary = {}   # tab_id -> Button
var _underlines: Dictionary = {}    # tab_id -> ColorRect
var _popup_tab: String = ""


func _init() -> void:
	theme = T.THEME
	theme_type_variation = &"UIMenuBar"
	custom_minimum_size = Vector2(0, T.MENU_BAR_HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_static()
	configure_tabs(DEFAULT_TABS)


# --------------------------------------------------------------------------
# Construcción
# --------------------------------------------------------------------------
func _build_static() -> void:
	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.add_theme_constant_override("margin_left", int(T.MENU_BAR_PADDING_X))
	margin.add_theme_constant_override("margin_right", int(T.MENU_BAR_PADDING_X))
	add_child(margin)

	_row = HBoxContainer.new()
	_row.name = "Row"
	_row.add_theme_constant_override("separation", 4)
	margin.add_child(_row)

	_title = Label.new()
	_title.name = "Title"
	_title.text = title_text
	var title_font := FontVariation.new()
	title_font.base_font = T.font("bold")
	title_font.spacing_glyph = 3
	_title.add_theme_font_override("font", title_font)
	_title.add_theme_font_size_override("font_size", T.FS_MENU_TITLE)
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_row.add_child(_title)
	var title_gap := Control.new()
	title_gap.custom_minimum_size.x = 12
	_row.add_child(title_gap)

	_tabs_box = HBoxContainer.new()
	_tabs_box.name = "Tabs"
	_tabs_box.add_theme_constant_override("separation", 4)
	_row.add_child(_tabs_box)

	var spacer := Control.new()
	spacer.name = "Spacer"
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_child(spacer)

	var right := HBoxContainer.new()
	right.name = "Right"
	right.add_theme_constant_override("separation", 10)
	_row.add_child(right)

	search_button = _make_icon_button("Search", ICON_SEARCH, "Ctrl K", "Buscar en todo el juego")
	search_button.pressed.connect(request_search)
	right.add_child(search_button)

	gold_label = CurrencyLabel.new()
	gold_label.name = "Gold"
	gold_label.setup(T.CURRENCY_GOLD, 0)
	right.add_child(gold_label)

	prisms_label = CurrencyLabel.new()
	prisms_label.name = "Prisms"
	prisms_label.setup(T.CURRENCY_PRISMS, 0, "show")
	prisms_label.add_requested.connect(func(_k: String) -> void: request_shop("prisms_plus"))
	right.add_child(prisms_label)

	settings_button = _make_icon_button("Settings", ICON_SETTINGS, "", "Ajustes (F10)")
	settings_button.pressed.connect(request_settings)
	right.add_child(settings_button)

	close_button = _make_icon_button("Close", "", "Esc", "Cerrar (Esc)")
	close_button.pressed.connect(request_close)
	right.add_child(close_button)

	commerce_popup = PopupMenu.new()
	commerce_popup.name = "CommercePopup"
	commerce_popup.theme = T.THEME
	commerce_popup.id_pressed.connect(_on_popup_id_pressed)
	add_child(commerce_popup)


func _make_icon_button(node_name: String, icon_d: String, keycap: String, spoken: String) -> Button:
	var b := Button.new()
	b.name = node_name
	b.theme_type_variation = &"UIMenuButton"
	b.custom_minimum_size = Vector2(T.MENU_BUTTON_SIZE, T.MENU_BUTTON_SIZE)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.focus_mode = Control.FOCUS_ALL
	b.tooltip_text = spoken
	if "accessibility_name" in b:
		b.set("accessibility_name", spoken)
	var box := HBoxContainer.new()
	box.name = "Content"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 6)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	b.add_child(box)
	if icon_d != "":
		var ic := VectorIcon.new()
		ic.custom_layers = [{"d": icon_d, "stroke": T.TEXT_SECONDARY, "width": 1.8}]
		ic.icon_size = 16
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		box.add_child(ic)
	if keycap != "":
		box.add_child(_make_keycap(keycap))
	var min_w := 10.0 + (16.0 if icon_d != "" else 0.0) + (6.0 if icon_d != "" and keycap != "" else 0.0)
	if keycap != "":
		min_w += _keycap_width(keycap)
	b.custom_minimum_size.x = maxf(T.MENU_BUTTON_SIZE, min_w + 10.0)
	return b


func _keycap_width(text: String) -> float:
	var f := T.font("bold")
	return f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, T.FS_KEYCAP).x + 8.0


func _make_keycap(text: String) -> PanelContainer:
	var cap := PanelContainer.new()
	cap.name = "Keycap"
	cap.theme_type_variation = &"UIMenuKeycap"
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cap.custom_minimum_size = Vector2(T.MENU_KEYCAP_HEIGHT, T.MENU_KEYCAP_HEIGHT)
	var l := Label.new()
	l.name = "Text"
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", T.font("bold"))
	l.add_theme_font_size_override("font_size", T.FS_KEYCAP)
	l.add_theme_color_override("font_color", T.TEXT_KEY)
	l.add_theme_color_override("font_shadow_color", Color.TRANSPARENT)
	cap.add_child(l)
	return cap


## Sustituye la tabla de pestañas (datos). Cada entrada: id, label, key (Key), window, icon? (path SVG 24), subtabs?.
func configure_tabs(tabs: Array) -> void:
	tabs_data.clear()
	for t in tabs:
		tabs_data.append((t as Dictionary).duplicate(true))
	for child in _tabs_box.get_children():
		_tabs_box.remove_child(child)
		child.queue_free()
	_tab_buttons.clear()
	_underlines.clear()
	for t in tabs_data:
		var b := _make_tab_button(t)
		_tabs_box.add_child(b)
		_tab_buttons[t["id"]] = b
		if t.has("subtabs") and not (t["subtabs"] as Array).is_empty():
			active_subtab[t["id"]] = t["subtabs"][0]["id"]
	if active_tab != "" and not _tab_buttons.has(active_tab):
		active_tab = ""
	_update_active_visuals()
	_apply_accent()


func _make_tab_button(t: Dictionary) -> Button:
	var b := Button.new()
	b.name = "Tab_" + str(t["id"])
	b.theme_type_variation = &"UIMenuTab"
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size.y = T.MENU_BAR_HEIGHT
	var key_text := key_label(int(t.get("key", KEY_NONE)))
	var spoken := "%s (%s)" % [t["label"], key_text] if key_text != "" else str(t["label"])
	b.tooltip_text = spoken
	if "accessibility_name" in b:
		b.set("accessibility_name", spoken)
	var box := HBoxContainer.new()
	box.name = "Content"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 6)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	b.add_child(box)
	var icon_d := str(t.get("icon", ""))
	if icon_d != "":
		var ic := VectorIcon.new()
		ic.name = "Icon"
		ic.custom_layers = [{"d": icon_d, "stroke": T.MENU_TAB_TEXT, "width": 1.5}]
		ic.icon_size = 16
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		box.add_child(ic)
	var name_label := Label.new()
	name_label.name = "Label"
	name_label.text = str(t["label"])
	name_label.add_theme_font_override("font", T.font("semibold"))
	name_label.add_theme_font_size_override("font_size", T.FS_MENU_TAB)
	name_label.add_theme_color_override("font_color", T.MENU_TAB_TEXT)
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(name_label)
	if key_text != "":
		box.add_child(_make_keycap(key_text))
	var label_w := T.font("semibold").get_string_size(name_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, T.FS_MENU_TAB).x
	var icon_w := 22.0 if icon_d != "" else 0.0
	b.custom_minimum_size.x = 22.0 + label_w + icon_w + (6.0 + _keycap_width(key_text) if key_text != "" else 0.0)
	var underline := ColorRect.new()
	underline.name = "Underline"
	underline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	underline.anchor_left = 0.0
	underline.anchor_right = 1.0
	underline.anchor_top = 1.0
	underline.anchor_bottom = 1.0
	underline.offset_top = -T.MENU_TAB_UNDERLINE
	underline.visible = false
	b.add_child(underline)
	_underlines[t["id"]] = underline
	var tab_id: String = t["id"]
	b.pressed.connect(func() -> void: select_tab(tab_id))
	return b


# --------------------------------------------------------------------------
# API pública
# --------------------------------------------------------------------------
func get_tab_ids() -> Array[String]:
	var out: Array[String] = []
	for t in tabs_data:
		out.append(t["id"])
	return out


func get_tab(tab_id: String) -> Dictionary:
	for t in tabs_data:
		if t["id"] == tab_id:
			return t
	return {}


func get_tab_button(tab_id: String) -> Button:
	return _tab_buttons.get(tab_id, null)


func get_subtabs(tab_id: String) -> Array:
	return get_tab(tab_id).get("subtabs", [])


## Atajo canónico de una pestaña ("C", "N", …) o "" si no tiene.
func get_shortcut(tab_id: String) -> String:
	return key_label(int(get_tab(tab_id).get("key", KEY_NONE)))


static func key_label(keycode: int) -> String:
	if keycode == KEY_NONE:
		return ""
	return OS.get_keycode_string(keycode)


## Marca la pestaña activa sin emitir señales (cada ventana declara la suya).
func set_active_tab(tab_id: String, subtab_id: String = "") -> void:
	if tab_id != "" and not _tab_buttons.has(tab_id):
		push_warning("[MenuBar] Pestaña desconocida: %s" % tab_id)
		return
	active_tab = tab_id
	if subtab_id != "":
		active_subtab[tab_id] = subtab_id
	_update_active_visuals()


## Selecciona una pestaña como si el usuario la pulsara.
## Las pestañas con sub-pestañas (Comercio) abren su submenú y navegan a la última sub-pestaña usada.
func select_tab(tab_id: String) -> void:
	var t := get_tab(tab_id)
	if t.is_empty():
		push_warning("[MenuBar] Pestaña desconocida: %s" % tab_id)
		return
	active_tab = tab_id
	_update_active_visuals()
	tab_selected.emit(tab_id)
	var subs: Array = t.get("subtabs", [])
	if subs.is_empty():
		navigation_requested.emit(str(t.get("window", tab_id)), {"tab": tab_id})
	else:
		open_submenu(tab_id)
		select_subtab(tab_id, active_subtab.get(tab_id, subs[0]["id"]))


func select_subtab(tab_id: String, subtab_id: String) -> void:
	var sub := _find_subtab(tab_id, subtab_id)
	if sub.is_empty():
		push_warning("[MenuBar] Sub-pestaña desconocida: %s/%s" % [tab_id, subtab_id])
		return
	active_tab = tab_id
	active_subtab[tab_id] = subtab_id
	_update_active_visuals()
	subtab_selected.emit(tab_id, subtab_id)
	navigation_requested.emit(str(sub.get("window", subtab_id)), {
		"tab": tab_id, "subtab": subtab_id,
		"under_construction": bool(sub.get("under_construction", false)),
	})


func open_submenu(tab_id: String) -> void:
	var subs := get_subtabs(tab_id)
	commerce_popup.clear()
	_popup_tab = tab_id
	for i in subs.size():
		var label := str(subs[i]["label"])
		if subs[i].get("under_construction", false):
			label += "  ·  en construcción"
		commerce_popup.add_radio_check_item(label, i)
		commerce_popup.set_item_checked(i, subs[i]["id"] == active_subtab.get(tab_id, ""))
	if is_inside_tree() and is_visible_in_tree() and DisplayServer.get_name() != "headless":
		var b: Button = _tab_buttons.get(tab_id)
		var at: Vector2 = get_screen_position()
		if b:
			at = b.get_screen_position() + Vector2(0, b.size.y)
		commerce_popup.popup(Rect2i(Vector2i(at), Vector2i.ZERO))


func set_currencies(gold: int, prisms: int) -> void:
	gold_label.amount = gold
	prisms_label.amount = prisms


func request_search() -> void:
	search_requested.emit()
	navigation_requested.emit(SEARCH_WINDOW, {"source": "menu_bar"})


## Prismas «+» abre la Tienda (Comercio › Tienda).
func request_shop(source: String = "menu_bar") -> void:
	shop_requested.emit(source)
	if not _find_subtab("comercio", SHOP_SUBTAB).is_empty():
		select_subtab("comercio", SHOP_SUBTAB)


func request_settings() -> void:
	settings_requested.emit()
	navigation_requested.emit(SETTINGS_WINDOW, {"source": "menu_bar"})


func request_close() -> void:
	close_requested.emit()


## Procesa un atajo de teclado. Devuelve true si lo consumió.
## Ctrl+K búsqueda · F10 ajustes · Esc cerrar · letras de pestaña (sin modificadores).
func handle_shortcut(event: InputEvent) -> bool:
	if not (event is InputEventKey) or not event.is_pressed() or event.is_echo():
		return false
	var k := event as InputEventKey
	var code := k.keycode if k.keycode != KEY_NONE else k.physical_keycode
	if code == KEY_K and (k.ctrl_pressed or k.meta_pressed):
		request_search()
		return true
	if k.ctrl_pressed or k.alt_pressed or k.meta_pressed:
		return false
	match code:
		KEY_F10:
			request_settings()
			return true
		KEY_ESCAPE:
			request_close()
			return true
	for t in tabs_data:
		if int(t.get("key", KEY_NONE)) == code:
			select_tab(t["id"])
			return true
	return false


func _unhandled_key_input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or not capture_shortcuts or not is_visible_in_tree():
		return
	if handle_shortcut(event):
		get_viewport().set_input_as_handled()


# --------------------------------------------------------------------------
# Internos
# --------------------------------------------------------------------------
func _find_subtab(tab_id: String, subtab_id: String) -> Dictionary:
	for s in get_subtabs(tab_id):
		if s["id"] == subtab_id:
			return s
	return {}


func _on_popup_id_pressed(idx: int) -> void:
	var subs := get_subtabs(_popup_tab)
	if idx >= 0 and idx < subs.size():
		select_subtab(_popup_tab, subs[idx]["id"])


func _update_active_visuals() -> void:
	for id in _tab_buttons:
		var b: Button = _tab_buttons[id]
		var on: bool = id == active_tab
		b.set_pressed_no_signal(on)
		var lbl := b.get_node_or_null("Content/Label") as Label
		if lbl:
			lbl.add_theme_color_override("font_color", T.MENU_TAB_TEXT_ACTIVE if on else T.MENU_TAB_TEXT)
		var tab_icon := b.get_node_or_null("Content/Icon") as VectorIcon
		if tab_icon:
			tab_icon.tint = T.MENU_TAB_TEXT_ACTIVE if on else Color(0, 0, 0, 0)
		var u: ColorRect = _underlines.get(id)
		if u:
			u.visible = on


func _apply_accent() -> void:
	if _title:
		_title.add_theme_color_override("font_color", accent)
	for id in _underlines:
		(_underlines[id] as ColorRect).color = accent
