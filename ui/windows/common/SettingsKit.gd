extends RefCounted
## Piezas compartidas de Ajustes (MMO-Ajustes.html) y Editor de interfaz (MMO-Interfaz.html) —
## UI v2.4 Paso 16 · ADR 114. Complementa a CinematicKit/EntryKit:
##     const SK = preload("res://ui/windows/common/SettingsKit.gd")
##
## - `Switch`: interruptor `.sw` de 34×20 (on #46e3c1 · off #2a363d, botón blanco/gris).
## - `Shape`: forma de estado (círculo · triángulo · rombo · cuadrado) para «Formas además de colores».
## - `Meter`: barra de 8 px del «Rendimiento estimado en tu PC».
## - `style_slider()`: pista de 6 px #121a20, relleno de acento y botón blanco de 16 px.
## - `segmented()`: selector segmentado (#121a20 con la opción activa en #1c2a33).

const T = preload("res://ui/tokens/hud_tokens.gd")
const Kit = preload("res://ui/windows/common/CinematicKit.gd")

static var _knob_tex: Texture2D = null


## Tarjeta `.card` (#0d1216 radio 18, aro blanco 7 %, sombra profunda).
static func card(node_name: String, pad: int) -> PanelContainer:
	var sb := Kit.box(T.SETTINGS_CARD_BG, 18, 1, T.SETTINGS_CARD_EDGE)
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 24
	sb.shadow_offset = Vector2(0, 12)
	var p := Kit.panel(node_name, sb, pad)
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	return p


## `.sub` (#121a20 radio 12) con borde opcional.
static func sub(node_name: String, pad_x: int, pad_y: int, edge: Color = Color.TRANSPARENT, edge_w: float = 0.0) -> PanelContainer:
	var p := Kit.panel(node_name, Kit.box(T.SETTINGS_SUB_BG, 12, edge_w, edge), pad_x, pad_y)
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	return p


static func vbox(node_name: String, sep: int) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.name = node_name
	v.add_theme_constant_override("separation", sep)
	return v


static func hbox(node_name: String, sep: int) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.name = node_name
	h.add_theme_constant_override("separation", sep)
	return h


static func expand() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func vexpand() -> Control:
	var c := Control.new()
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## Botón chip `.chip` (28 px, #18242b, 13 px #c3ccd3) con estado activo opcional.
static func chip_button(node_name: String, text: String, height: int = 28, font_size: int = 13) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(0, height)
	b.add_theme_font_override("font", T.font("medium"))
	b.add_theme_font_size_override("font_size", font_size)
	set_chip_active(b, false)
	return b


## Estilo de chip: inactivo (#18242b) o activo (acento 14 % con aro 1,5 px de acento).
static func set_chip_active(b: Button, active: bool, accent_text: bool = false) -> void:
	var bg := Color(T.ACCENT_DEFAULT, 0.14) if active else T.BUTTON_BG
	var normal := Kit.box(bg, 8, 2 if active else 0, T.ACCENT_DEFAULT)
	normal.content_margin_left = 10
	normal.content_margin_right = 10
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = bg.lightened(0.06) if not active else Color(T.ACCENT_DEFAULT, 0.2)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("hover_pressed", hover)
	b.add_theme_stylebox_override("disabled", normal)
	b.add_theme_stylebox_override("focus", Kit.box(Color.TRANSPARENT, 8, 1, Color(T.ACCENT_DEFAULT, 0.6)))
	var fc := T.ACCENT_DEFAULT if accent_text else (T.TEXT if active else T.TEXT_KEY)
	for s in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(s, fc)
	b.set_meta("active", active)


## Selector segmentado: {panel, buttons:{id: Button}}. `items` = [[id, texto], …].
static func segmented(node_name: String, items: Array, expand_items: bool = false) -> Dictionary:
	var p := Kit.panel(node_name, Kit.box(T.SETTINGS_SUB_BG, 10), 3, 3)
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	var row := hbox("Row", 4 if expand_items else 3)
	p.add_child(row)
	var buttons := {}
	for it in items:
		var b := Button.new()
		b.name = "Seg_" + str(it[0])
		b.text = str(it[1])
		b.focus_mode = Control.FOCUS_ALL
		b.custom_minimum_size = Vector2(0, 28)
		b.add_theme_font_override("font", T.font("semibold"))
		b.add_theme_font_size_override("font_size", 13)
		if expand_items:
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
		buttons[str(it[0])] = b
		set_segment_active(b, false)
	return {"panel": p, "buttons": buttons}


static func set_segment_active(b: Button, active: bool) -> void:
	var bg := T.SETTINGS_ACTIVE_BG if active else Color(0, 0, 0, 0)
	var sb := Kit.box(bg, 8)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	var hover := sb.duplicate() as StyleBoxFlat
	hover.bg_color = T.SETTINGS_ACTIVE_BG if active else Color(1, 1, 1, 0.04)
	for st in ["normal", "disabled"]:
		b.add_theme_stylebox_override(st, sb)
	for st in ["hover", "pressed", "hover_pressed"]:
		b.add_theme_stylebox_override(st, hover)
	b.add_theme_stylebox_override("focus", Kit.box(Color.TRANSPARENT, 8, 1, Color(T.ACCENT_DEFAULT, 0.6)))
	var fc := T.TEXT if active else T.TEXT_SECONDARY
	for s in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(s, fc)
	b.set_meta("active", active)


## Botón primario «Aplicar» (#46e3c1, texto #071012).
static func primary(b: Button) -> void:
	for st in ["normal", "hover", "pressed", "focus"]:
		var c: Color = T.ACCENT_DEFAULT if st != "hover" else T.ACCENT_DEFAULT.lightened(0.12)
		b.add_theme_stylebox_override(st, Kit.box(c, 10))
	b.add_theme_stylebox_override("disabled", Kit.box(Color(T.ACCENT_DEFAULT, 0.3), 10))
	for fc in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(fc, T.SETTINGS_PRIMARY_TEXT)
	b.add_theme_color_override("font_disabled_color", Color(T.SETTINGS_PRIMARY_TEXT, 0.55))


## Botón `.btn` secundario.
static func button(node_name: String, text: String, height: int = 36, font_size: int = 14) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(0, height)
	Kit.button_styles(b, 10)
	b.add_theme_font_override("font", T.font("semibold"))
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", T.TEXT)
	b.add_theme_color_override("font_disabled_color", T.TEXT_MUTED)
	return b


## Pista 6 px #121a20, relleno de acento y botón blanco de 16 px.
static func style_slider(s: HSlider) -> void:
	var track := Kit.box(T.SETTINGS_SUB_BG, 3)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	s.add_theme_stylebox_override("slider", track)
	var fill := Kit.box(T.ACCENT_DEFAULT, 3)
	fill.content_margin_top = 3
	fill.content_margin_bottom = 3
	s.add_theme_stylebox_override("grabber_area", fill)
	s.add_theme_stylebox_override("grabber_area_highlight", fill)
	var knob := knob_texture()
	s.add_theme_icon_override("grabber", knob)
	s.add_theme_icon_override("grabber_highlight", knob)
	s.add_theme_icon_override("grabber_disabled", knob)
	s.custom_minimum_size.y = 16
	s.focus_mode = Control.FOCUS_ALL


static func knob_texture() -> Texture2D:
	if _knob_tex == null:
		var n := 16
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		var c := Vector2(n, n) * 0.5
		for y in n:
			for x in n:
				var d := Vector2(x + 0.5, y + 0.5).distance_to(c)
				var a := clampf(8.0 - d, 0.0, 1.0)
				img.set_pixel(x, y, Color(1, 1, 1, a))
		_knob_tex = ImageTexture.create_from_image(img)
	return _knob_tex


static func a11y_name(c: Control, text: String) -> void:
	if "accessibility_name" in c:
		c.set("accessibility_name", text)
	c.tooltip_text = text


## Interruptor `.sw` 34×20.
class Switch extends Button:
	func _init() -> void:
		toggle_mode = true
		focus_mode = Control.FOCUS_ALL
		custom_minimum_size = Vector2(34, 20)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		size_flags_horizontal = Control.SIZE_SHRINK_END
		flat = true
		for st in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
			add_theme_stylebox_override(st, StyleBoxEmpty.new())
		toggled.connect(func(_on: bool) -> void: queue_redraw())

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, Vector2(34, 20))
		var sb := StyleBoxFlat.new()
		sb.bg_color = T.ACCENT_DEFAULT if button_pressed else T.SETTINGS_SWITCH_OFF
		sb.set_corner_radius_all(10)
		sb.anti_aliasing = true
		draw_style_box(sb, r)
		var kx := 34.0 - 3.0 - 7.0 if button_pressed else 3.0 + 7.0
		draw_circle(Vector2(kx, 10), 7.0, Color.WHITE if button_pressed else T.TEXT_SECONDARY, true, -1.0, true)
		if has_focus():
			var f := StyleBoxFlat.new()
			f.draw_center = false
			f.set_border_width_all(1)
			f.border_color = Color(T.ACCENT_DEFAULT, 0.7)
			f.set_corner_radius_all(12)
			f.expand_margin_left = 2
			f.expand_margin_right = 2
			f.expand_margin_top = 2
			f.expand_margin_bottom = 2
			draw_style_box(f, r)


## Forma de estado (círculo · triángulo · rombo · cuadrado).
class Shape extends Control:
	var kind := "circle":
		set(v):
			kind = v
			queue_redraw()
	var color := Color.WHITE:
		set(v):
			color = v
			queue_redraw()

	func _init(k: String = "circle", c: Color = Color.WHITE, d: float = 9.0) -> void:
		kind = k
		color = c
		custom_minimum_size = Vector2(d, d)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _draw() -> void:
		var s := minf(size.x, size.y)
		var o := (size - Vector2(s, s)) * 0.5
		match kind:
			"triangle":
				draw_colored_polygon(PackedVector2Array([o + Vector2(s * 0.5, 0), o + Vector2(s, s), o + Vector2(0, s)]), color)
			"diamond":
				draw_colored_polygon(PackedVector2Array([o + Vector2(s * 0.5, 0), o + Vector2(s, s * 0.5), o + Vector2(s * 0.5, s), o + Vector2(0, s * 0.5)]), color)
			"square":
				draw_rect(Rect2(o + Vector2(s, s) * 0.1, Vector2(s, s) * 0.8), color)
			_:
				draw_circle(size * 0.5, s * 0.5, color, true, -1.0, true)


## Barra de rendimiento de 8 px (fondo #121a20).
class Meter extends Control:
	var ratio := 0.0:
		set(v):
			ratio = clampf(v, 0.0, 1.0)
			queue_redraw()
	var color := Color("#4fe39a"):
		set(v):
			color = v
			queue_redraw()

	func _init() -> void:
		custom_minimum_size = Vector2(40, 8)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var bg := StyleBoxFlat.new()
		bg.bg_color = T.SETTINGS_SUB_BG
		bg.set_corner_radius_all(4)
		draw_style_box(bg, Rect2(Vector2.ZERO, size))
		if ratio > 0.0:
			var fg := StyleBoxFlat.new()
			fg.bg_color = color
			fg.set_corner_radius_all(4)
			draw_style_box(fg, Rect2(Vector2.ZERO, Vector2(maxf(size.y, size.x * ratio), size.y)))
