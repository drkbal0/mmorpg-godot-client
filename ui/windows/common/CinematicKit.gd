extends RefCounted
## Piezas compartidas de las pantallas cinematográficas a pantalla completa (UI v2.4 Paso 13):
## Diálogo con PNJ (MMO-Dialogo.html) y Muerte y reaparición (MMO-Muerte.html).
##
## Ambas se maquetan sobre un «escenario» de 1440×810 (el lienzo del diseño HTML) que se escala
## de forma uniforme y se centra en el viewport (`fit_stage`). Uso:
##     const Kit = preload("res://ui/windows/common/CinematicKit.gd")

const T = preload("res://ui/tokens/hud_tokens.gd")
const SvgPath = preload("res://ui/icons/svg_path.gd")


## Escala y centra `stage` (tamaño de diseño) dentro de `area`. Devuelve la escala aplicada.
static func fit_stage(stage: Control, area: Vector2) -> float:
	var design := T.CINEMA_DESIGN_SIZE
	var s := minf(area.x / design.x, area.y / design.y)
	if s <= 0.0:
		s = 1.0
	stage.size = design
	stage.scale = Vector2(s, s)
	stage.position = ((area - design * s) * 0.5).floor()
	return s


static func label(text: String, font_size: int, color: Color, weight: String = "medium") -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", T.font(weight))
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Texto con sombra profunda (`.sh` del HTML: 0 1px 3px rgba(0,0,0,0.95)).
static func shadow(l: Label, size: int = 3) -> Label:
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 1 if size <= 3 else 2)
	l.add_theme_constant_override("shadow_outline_size", size)
	return l


static func caps(text: String, color: Color = T.TEXT_SECONDARY) -> Label:
	var l := label(text.to_upper(), 11, color, "semibold")
	var f := FontVariation.new()
	f.base_font = T.font("semibold")
	f.spacing_glyph = 2
	l.add_theme_font_override("font", f)
	return l


static func rich(font_size: int, color: Color, weight: String = "medium") -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_theme_font_override("normal_font", T.font(weight))
	r.add_theme_font_override("bold_font", T.font("bold"))
	r.add_theme_font_size_override("normal_font_size", font_size)
	r.add_theme_font_size_override("bold_font_size", font_size)
	r.add_theme_color_override("default_color", color)
	return r


static func box(bg: Color, radius: int, border: float = 0.0, border_color: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	if border > 0.0:
		sb.border_color = border_color
		sb.set_border_width_all(int(ceil(border)))
	sb.anti_aliasing = true
	return sb


static func panel(node_name: String, sb: StyleBoxFlat, margin_x: int = 0, margin_y: int = -1) -> PanelContainer:
	var p := PanelContainer.new()
	p.name = node_name
	sb.content_margin_left = margin_x
	sb.content_margin_right = margin_x
	sb.content_margin_top = margin_x if margin_y < 0 else margin_y
	sb.content_margin_bottom = margin_x if margin_y < 0 else margin_y
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


## Tecla `.kbd` del diseño (#18242b, borde blanco 14 %, texto #dbe4ea 11 px bold).
static func kbd(text: String, height: int = 18, font_size: int = 11) -> PanelContainer:
	var p := panel("Kbd", box(T.BUTTON_BG, 5, 1, Color(1, 1, 1, 0.14)), 4, 0)
	p.custom_minimum_size = Vector2(height, height)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var l := label(text, font_size, Color("#dbe4ea"), "bold")
	l.name = "Key"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p


## Chip `.chip` (28 px, #18242b, texto 13 px #c3ccd3).
static func chip(text: String, bg: Color = T.BUTTON_BG, fg: Color = T.TEXT_KEY, height: int = 28, font_size: int = 13) -> PanelContainer:
	var p := panel("Chip", box(bg, 8), 10, 0)
	p.custom_minimum_size.y = height
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(h)
	var l := label(text, font_size, fg)
	l.name = "Text"
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(l)
	return p


## Botón `.btn` (#18242b, borde blanco 8 %, 14 px semibold).
static func button_styles(b: Button, radius: int = 10) -> void:
	b.add_theme_stylebox_override("normal", box(T.BUTTON_BG, radius, 1, T.BUTTON_BORDER))
	b.add_theme_stylebox_override("hover", box(T.BUTTON_BG.lightened(0.08), radius, 1, Color(1, 1, 1, 0.16)))
	b.add_theme_stylebox_override("pressed", box(T.BUTTON_BG.lightened(0.12), radius, 1, T.ACCENT_DEFAULT))
	b.add_theme_stylebox_override("disabled", box(Color(T.BUTTON_BG, 0.6), radius, 1, Color(1, 1, 1, 0.05)))
	b.add_theme_stylebox_override("focus", box(Color.TRANSPARENT, radius, 2, T.ACCENT_DEFAULT))


## Fila `[ texto ............ valor ]` dentro de un botón de 48 px (botones de la muerte).
static func split_button(node_name: String, text: String, height: int = 48) -> Button:
	var b := Button.new()
	b.name = node_name
	b.custom_minimum_size = Vector2(0, height)
	b.focus_mode = Control.FOCUS_ALL
	button_styles(b)
	var h := HBoxContainer.new()
	h.name = "Row"
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 14
	h.offset_right = -14
	h.add_theme_constant_override("separation", 8)
	b.add_child(h)
	var l := label(text, 14, T.TEXT, "semibold")
	l.name = "Text"
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(l)
	return b


static func clear(n: Node) -> void:
	for c in n.get_children():
		n.remove_child(c)
		c.queue_free()


# ==========================================================================
# Controles dibujados
# ==========================================================================
## Barra redondeada (pista + relleno 0..1).
class Bar extends Control:
	var track := Color("#121a20"):
		set(v):
			track = v
			queue_redraw()
	var fill := Color("#e25555"):
		set(v):
			fill = v
			queue_redraw()
	var ratio := 0.0:
		set(v):
			ratio = clampf(v, 0.0, 1.0)
			queue_redraw()

	func _init(h: float = 5.0) -> void:
		custom_minimum_size = Vector2(10, h)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func fill_width() -> float:
		return size.x * ratio

	func _draw() -> void:
		var r := size.y * 0.5
		var sb := StyleBoxFlat.new()
		sb.bg_color = track
		sb.set_corner_radius_all(int(ceil(r)))
		draw_style_box(sb, Rect2(Vector2.ZERO, size))
		if ratio > 0.0:
			var fb := StyleBoxFlat.new()
			fb.bg_color = fill
			fb.set_corner_radius_all(int(ceil(r)))
			draw_style_box(fb, Rect2(0, 0, maxf(size.y, size.x * ratio), size.y))


## Icono SVG (viewBox 24) sobre un fondo redondeado opcional.
class Icon extends Control:
	const SP = preload("res://ui/icons/svg_path.gd")
	var path := "":
		set(v):
			path = v
			queue_redraw()
	var stroke := Color.WHITE
	var bg := Color(0, 0, 0, 0):
		set(v):
			bg = v
			queue_redraw()
	var radius := 6
	var icon_size := 13.0
	var width := 2.4

	func _init(d: String = "", sz: Vector2 = Vector2(22, 22)) -> void:
		path = d
		custom_minimum_size = sz
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if bg.a > 0.0:
			var sb := StyleBoxFlat.new()
			sb.bg_color = bg
			sb.set_corner_radius_all(radius)
			draw_style_box(sb, Rect2(Vector2.ZERO, size))
		if path == "":
			return
		var s := minf(icon_size, minf(size.x, size.y))
		var rect := Rect2((size - Vector2(s, s)) * 0.5, Vector2(s, s))
		SP.draw_layers(self, [{"d": path, "stroke": stroke, "width": width}], rect)
