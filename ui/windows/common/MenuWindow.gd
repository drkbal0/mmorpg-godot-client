extends "res://ui/templates/BaseWindow.gd"
## Base de las ventanas de juego con el menú común (UI v2.4 §2.1) — Paso 9.
## Construye el marco (menú superior + cuerpo con márgenes), conecta el menú con
## `UIOrchestrator`, pinta el saldo de Oro/Prismas desde `CommerceService` y aporta
## los ayudantes visuales compartidos (tarjetas, chips, botones, barras, puntos).
##
## Subclases: QuestsWindow [L], MapWindow [M], SocialWindow [O], ShopWindow y
## BattlePassWindow (Comercio [P]).

const T = preload("res://ui/tokens/hud_tokens.gd")
const MenuBarScene = preload("res://ui/menu/menu_bar.tscn")
const CommerceServiceScript = preload("res://shared-core/CommerceService.gd")

const WINDOW_SIZE := Vector2(1270, 680)

var menu_bar: Node
var content: VBoxContainer
## Economía inyectable (tests). Si es null se usa /root/CommerceService o uno local.
var commerce: Node = null

var _menu_tab: String = ""
var _menu_subtab: String = ""
var _frame_built := false


func _init() -> void:
	custom_minimum_size = WINDOW_SIZE
	size = WINDOW_SIZE
	theme = T.THEME
	add_theme_stylebox_override("panel", T.box(T.PANEL_BG, 14, 1, T.PANEL_EDGE))


## Construye menú + cuerpo. Devuelve el VBox de contenido.
func build_frame(tab_id: String, subtab_id: String = "") -> VBoxContainer:
	if _frame_built:
		return content
	_frame_built = true
	_menu_tab = tab_id
	_menu_subtab = subtab_id
	var root := VBoxContainer.new()
	root.name = "Root"
	root.add_theme_constant_override("separation", 10)
	add_child(root)
	menu_bar = MenuBarScene.instantiate()
	menu_bar.name = "MenuBar"
	root.add_child(menu_bar)
	var body := MarginContainer.new()
	body.name = "Body"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "bottom"]:
		body.add_theme_constant_override("margin_" + side, 16)
	root.add_child(body)
	content = VBoxContainer.new()
	content.name = "Content"
	content.add_theme_constant_override("separation", 10)
	body.add_child(content)
	return content


func _resolve_commerce() -> void:
	if commerce == null and is_inside_tree():
		commerce = get_node_or_null("/root/CommerceService")
	if commerce == null:
		commerce = CommerceServiceScript.new()
		commerce.name = "LocalCommerceService"
		commerce.load_seed()
		add_child(commerce)
	elif commerce.get_parent() == null:
		add_child(commerce)
	if not commerce.wallet_changed.is_connected(_on_wallet_changed):
		commerce.wallet_changed.connect(_on_wallet_changed)


func _on_wallet_changed(_g: int = 0, _p: int = 0) -> void:
	if menu_bar and commerce:
		menu_bar.set_currencies(int(commerce.gold), int(commerce.prisms))


## Conecta el menú con UIOrchestrator y marca la pestaña activa.
func connect_menu_bar() -> void:
	if menu_bar == null:
		return
	menu_bar.set_active_tab(_menu_tab, _menu_subtab)
	_on_wallet_changed()
	var orch := get_node_or_null("/root/UIOrchestrator")
	if orch and orch.has_method("connect_menu_bar"):
		orch.connect_menu_bar(menu_bar)
	elif not menu_bar.close_requested.is_connected(_on_close_pressed):
		menu_bar.close_requested.connect(_on_close_pressed)
	if not get_viewport().size_changed.is_connected(fit_to_viewport):
		get_viewport().size_changed.connect(fit_to_viewport)
	fit_to_viewport.call_deferred()


## Si el menú común no cabe, pasa a modo compacto (igual que Poderes y Refugio).
func fit_to_viewport() -> void:
	if not is_inside_tree() or menu_bar == null:
		return
	var vp_w := get_viewport_rect().size.x
	var margin := menu_bar.get_node_or_null("Margin") as MarginContainer
	var title := menu_bar.get_node_or_null("Margin/Row/Title") as Control
	if margin:
		margin.add_theme_constant_override("margin_left", int(T.MENU_BAR_PADDING_X))
		margin.add_theme_constant_override("margin_right", int(T.MENU_BAR_PADDING_X))
	if title:
		title.visible = true
	var compact: bool = menu_bar.get_combined_minimum_size().x + 2.0 > vp_w
	if compact:
		if margin:
			margin.add_theme_constant_override("margin_left", 8)
			margin.add_theme_constant_override("margin_right", 8)
		if title:
			title.visible = false
	set_meta("menu_compact", compact)
	reset_size()
	size.x = clampf(WINDOW_SIZE.x, get_combined_minimum_size().x, maxf(vp_w, get_combined_minimum_size().x))
	position.x = clampf(position.x, 0.0, maxf(0.0, vp_w - size.x))


## Abre otra ventana registrada a través del orquestador (si existe).
func open_other_window(window_id: String, params: Dictionary = {}) -> bool:
	var orch := get_node_or_null("/root/UIOrchestrator")
	if orch and orch.has_method("open_window") and orch.registry and orch.registry.is_registered(window_id):
		orch.open_window(window_id, params)
		return true
	return false


# ==========================================================================
# Controles dibujados
# ==========================================================================
## Barra de progreso redondeada.
class Bar extends Control:
	var ratio := 0.0:
		set(v):
			ratio = clampf(v, 0.0, 1.0)
			queue_redraw()
	var color := Color("#46e3c1"):
		set(v):
			color = v
			queue_redraw()
	var bg := Color("#070a0c")

	func _init() -> void:
		custom_minimum_size = Vector2(40, 5)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var r := size.y * 0.5
		_pill(Rect2(Vector2.ZERO, size), bg, r)
		if ratio > 0.0:
			_pill(Rect2(Vector2.ZERO, Vector2(maxf(size.y, size.x * ratio), size.y)), color, r)

	func _pill(rect: Rect2, c: Color, r: float) -> void:
		var sb := StyleBoxFlat.new()
		sb.bg_color = c
		sb.set_corner_radius_all(int(r))
		draw_style_box(sb, rect)


## Barra segmentada de una ruta de viaje.
class SegmentBar extends Control:
	var segments: Array = []:
		set(v):
			segments = v
			queue_redraw()
	var colors := {}

	func _init() -> void:
		custom_minimum_size = Vector2(60, 5)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var x := 0.0
		var gap := 4.0
		for i in segments.size():
			var s: Dictionary = segments[i]
			var w := size.x * float(s["ratio"]) - (gap if i < segments.size() - 1 else 0.0)
			var sb := StyleBoxFlat.new()
			sb.bg_color = colors.get(s["kind"], Color("#46e3c1"))
			sb.set_corner_radius_all(int(size.y * 0.5))
			draw_style_box(sb, Rect2(x, 0, maxf(2.0, w), size.y))
			x += size.x * float(s["ratio"])


## Punto (estado online, capa del mapa…) o rombo.
class Dot extends Control:
	var color := Color.WHITE:
		set(v):
			color = v
			queue_redraw()
	var ring := Color(0, 0, 0, 0)

	func _init() -> void:
		custom_minimum_size = Vector2(8, 8)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _draw() -> void:
		var r := minf(size.x, size.y) * 0.5
		draw_circle(size * 0.5, r, color)
		if ring.a > 0.0:
			draw_arc(size * 0.5, r, 0, TAU, 24, ring, 1.5, true)


# ==========================================================================
# Ayudantes de construcción
# ==========================================================================
func _card(node_name: String, margin: int = 16, bg: Color = T.SHELTER_CARD_BG, border: Color = T.CODEX_CARD_BORDER, radius: int = 16) -> PanelContainer:
	var p := PanelContainer.new()
	p.name = node_name
	var sb := T.box(bg, radius, 1, border)
	sb.set_content_margin_all(margin)
	p.add_theme_stylebox_override("panel", sb)
	return p


func _sub_card(node_name: String, margin: int = 10) -> PanelContainer:
	return _card(node_name, margin, T.SHELTER_SUB_BG, T.CODEX_CARD_BORDER, 12)


func _vbox(sep: int) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


func _hbox(sep: int) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


func _spacer(sz: Vector2 = Vector2.ZERO, expand_h: bool = false, expand_v: bool = false) -> Control:
	var c := Control.new()
	c.custom_minimum_size = sz
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if expand_h:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if expand_v:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c


func _label(text: String, font_size: int, color: Color, weight: String = "medium") -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", T.font(weight))
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _wrap_label(text: String, font_size: int, color: Color, weight: String = "medium") -> Label:
	var l := _label(text, font_size, color, weight)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.custom_minimum_size.x = 60
	return l


func _caps(text: String, color: Color = T.TEXT_SECONDARY) -> Label:
	var l := _label(text, 11, color, "bold")
	var f := FontVariation.new()
	f.base_font = T.font("bold")
	f.spacing_glyph = 2
	l.add_theme_font_override("font", f)
	return l


func _badge(text: String, fg: Color, bg: Color = Color(0, 0, 0, 0), font_size: int = 11) -> PanelContainer:
	var p := PanelContainer.new()
	var bgc := bg if bg.a > 0.0 else Color(fg, 0.14)
	var sb := T.box(bgc, 7)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	p.add_theme_stylebox_override("panel", sb)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := _label(text, font_size, fg, "semibold")
	l.name = "Text"
	p.add_child(l)
	return p


func _chip_button(text: String, font_size: int = 13, height: int = 30) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size.y = height
	b.add_theme_font_override("font", T.font("semibold"))
	b.add_theme_font_size_override("font_size", font_size)
	var normal := T.box(T.POWERS_CHIP_BG, 8)
	normal.content_margin_left = 10
	normal.content_margin_right = 10
	var on := T.box(T.SLOT_READY, 8, 1, Color(1, 1, 1, 0.10))
	on.content_margin_left = 10
	on.content_margin_right = 10
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = T.SLOT_READY
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", on)
	b.add_theme_stylebox_override("hover_pressed", on)
	b.add_theme_stylebox_override("focus", T.box(Color.TRANSPARENT, 8, 1, Color(T.ACCENT_DEFAULT, 0.6)))
	for s in ["font_color", "font_hover_color", "font_focus_color"]:
		b.add_theme_color_override(s, T.TEXT_SECONDARY)
	for s in ["font_pressed_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(s, T.TEXT)
	return b


func _ghost_button(text: String, font_size: int = 13, height: int = 34) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size.y = height
	b.add_theme_font_override("font", T.font("semibold"))
	b.add_theme_font_size_override("font_size", font_size)
	var normal := T.box(T.BUTTON_BG, 10, 1, T.BUTTON_BORDER)
	normal.content_margin_left = 14
	normal.content_margin_right = 14
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = T.SLOT_READY
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(T.BUTTON_BG, 0.5)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("disabled", disabled)
	b.add_theme_stylebox_override("focus", T.box(Color.TRANSPARENT, 10, 1, T.ACCENT_DEFAULT))
	for s in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(s, T.TEXT)
	b.add_theme_color_override("font_disabled_color", T.TEXT_MUTED)
	return b


func _primary_button(text: String, font_size: int = 13, height: int = 34) -> Button:
	var b := _ghost_button(text, font_size, height)
	var normal := T.box(T.ACCENT_DEFAULT, 10)
	normal.content_margin_left = 16
	normal.content_margin_right = 16
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = T.ACCENT_DEFAULT.lightened(0.15)
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(T.ACCENT_DEFAULT, 0.25)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("disabled", disabled)
	for s in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(s, T.SHELTER_PILL_TEXT)
	b.add_theme_color_override("font_disabled_color", Color(T.SHELTER_PILL_TEXT, 0.6))
	return b


func _danger_text_button(text: String) -> Button:
	var b := _ghost_button(text)
	for s in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(s, Color("#ff8a8a"))
	return b


## Fila clicable (lista): Button plano con contenido propio.
func _row_button(node_name: String, height: int = 44) -> Button:
	var b := Button.new()
	b.name = node_name
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size.y = height
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var normal := T.box(Color(0, 0, 0, 0), 10)
	var hover := T.box(Color(1, 1, 1, 0.035), 10)
	var on := T.box(Color(T.ACCENT_DEFAULT, 0.06), 10, 1, Color(T.ACCENT_DEFAULT, 0.85))
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", on)
	b.add_theme_stylebox_override("hover_pressed", on)
	b.add_theme_stylebox_override("focus", T.box(Color.TRANSPARENT, 10, 1, Color(T.ACCENT_DEFAULT, 0.5)))
	return b


func _row_content(b: Button, sep: int = 10, margin_x: int = 10) -> HBoxContainer:
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_theme_constant_override("margin_left", margin_x)
	m.add_theme_constant_override("margin_right", margin_x)
	b.add_child(m)
	var h := _hbox(sep)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(h)
	return h


func _bar(ratio: float, color: Color, height: int = 4) -> Bar:
	var b := Bar.new()
	b.ratio = ratio
	b.color = color
	b.custom_minimum_size.y = height
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return b


func _dot(color: Color, d: float = 8.0) -> Dot:
	var dt := Dot.new()
	dt.color = color
	dt.custom_minimum_size = Vector2(d, d)
	return dt


func _clear(n: Node) -> void:
	if n == null:
		return
	for c in n.get_children():
		n.remove_child(c)
		c.queue_free()


static func fmt(n: int) -> String:
	return T.format_amount(n)


## Sub-navegación de Comercio (Mercado · Tienda · Pase de batalla) compartida.
func _commerce_subnav(active: String) -> PanelContainer:
	var pill := PanelContainer.new()
	pill.name = "CommerceSubnav"
	var psb := T.box(T.SHELTER_CARD_BG, 12, 1, T.CODEX_CARD_BORDER)
	psb.set_content_margin_all(4)
	pill.add_theme_stylebox_override("panel", psb)
	var row := _hbox(2)
	pill.add_child(row)
	for s in menu_bar.get_subtabs("comercio"):
		var b := _chip_button(str(s["label"]), 13, 30)
		b.name = "Sub_" + str(s["id"])
		b.button_pressed = s["id"] == active
		var sid: String = s["id"]
		b.pressed.connect(func() -> void:
			b.set_pressed_no_signal(sid == active)
			if sid != active:
				menu_bar.select_subtab("comercio", sid))
		row.add_child(b)
	return pill
