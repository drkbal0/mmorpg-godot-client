extends RefCounted
## Piezas compartidas de las pantallas de Entrada (UI v2.4 Paso 15): Launcher, Inicio de sesión,
## Selección, Creación y Carga. Complementa a CinematicKit (lienzo 1440×810, etiquetas, cajas…).
##     const EK = preload("res://ui/windows/common/EntryKit.gd")

const T = preload("res://ui/tokens/hud_tokens.gd")
const Kit = preload("res://ui/windows/common/CinematicKit.gd")
const SP = preload("res://ui/icons/svg_path.gd")

const SCENE_PATH := "res://design_ref/assets/mapa-fondo.jpg"
const SCENE_FALLBACK := Color("#26331f")
## Silueta del personaje (viewBox 150×260 del HTML).
const SILHOUETTE_BODY := "M40 82c6-12 18-18 35-18s29 6 35 18l10 70-18 4-6-40-4 98H58l-4-98-6 40-18-4z"
const CHIBI_HAIR := [
	"M5 11a10 10 0 0 1 20 0c-3-3-7-4-10-4s-7 1-10 4z",
	"M5 11a10 10 0 0 1 20 0c-3-3-7-4-10-4s-7 1-10 4zM22 8l5 9-3 1z",
	"M7 7a9 9 0 0 1 16 0c-3-2-5-2-8-2s-5 0-8 2z",
	"M4 13a11 11 0 0 1 22 0l0 8-3-1 0-7c-2-3-5-5-8-5s-6 2-8 5l0 7-3 1z",
]

static var _scene_tex: Texture2D = null


## Fondo «.scene» del diseño (mapa-fondo.jpg) sin depender del importador.
static func scene_texture() -> Texture2D:
	if _scene_tex == null:
		var img := Image.load_from_file(ProjectSettings.globalize_path(SCENE_PATH))
		if img != null and not img.is_empty():
			_scene_tex = ImageTexture.create_from_image(img)
	return _scene_tex


static func scene_rect(node_name: String = "Scene") -> Control:
	var tex := scene_texture()
	if tex == null:
		var c := ColorRect.new()
		c.name = node_name
		c.color = SCENE_FALLBACK
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return c
	var tr := TextureRect.new()
	tr.name = node_name
	tr.texture = tex
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


## Degradado vertical (offsets 0 = arriba … 1 = abajo).
static func vgradient(node_name: String, stops: Array) -> TextureRect:
	var g := Gradient.new()
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for st in stops:
		offs.append(float(st[0]))
		cols.append(st[1])
	g.offsets = offs
	g.colors = cols
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 4
	gt.height = 256
	var tr := TextureRect.new()
	tr.name = node_name
	tr.texture = gt
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


## Estilo de botón principal (#46e3c1, texto #071012, sin borde).
static func primary(b: Button, radius: int = 10, pad_x: int = 22) -> void:
	for st in ["normal", "hover", "pressed", "focus"]:
		var c: Color = T.ENTRY_PRIMARY if st != "hover" else T.ENTRY_PRIMARY.lightened(0.12)
		var sb := Kit.box(c, radius)
		sb.content_margin_left = pad_x
		sb.content_margin_right = pad_x
		b.add_theme_stylebox_override(st, sb)
	var d := Kit.box(Color(T.ENTRY_PRIMARY, 0.35), radius)
	d.content_margin_left = pad_x
	d.content_margin_right = pad_x
	b.add_theme_stylebox_override("disabled", d)
	for fc in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(fc, T.ENTRY_PRIMARY_TEXT)
	b.add_theme_color_override("font_disabled_color", Color(T.ENTRY_PRIMARY_TEXT, 0.6))
	b.set_meta("primary", true)


## Botón `.btn` secundario con alto y relleno horizontal.
static func button(node_name: String, text: String, height: int = 36, font_size: int = 14, pad_x: int = 14) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.custom_minimum_size = Vector2(0, height)
	b.focus_mode = Control.FOCUS_ALL
	Kit.button_styles(b, 10)
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb := b.get_theme_stylebox(st)
		if sb is StyleBoxFlat:
			(sb as StyleBoxFlat).content_margin_left = pad_x
			(sb as StyleBoxFlat).content_margin_right = pad_x
	b.add_theme_font_override("font", T.font("semibold"))
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", T.TEXT)
	b.set_meta("primary", false)
	return b


## Botón plano que actúa como enlace (#46e3c1).
static func link(node_name: String, text: String, font_size: int = 13, color: Color = T.ACCENT_DEFAULT) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.flat = true
	b.focus_mode = Control.FOCUS_ALL
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		var e := StyleBoxEmpty.new()
		b.add_theme_stylebox_override(st, e)
	b.add_theme_font_override("font", T.font("medium"))
	b.add_theme_font_size_override("font_size", font_size)
	for fc in ["font_color", "font_focus_color", "font_pressed_color"]:
		b.add_theme_color_override(fc, color)
	b.add_theme_color_override("font_hover_color", Color("#9af0dc"))
	return b


## Tarjeta `.card` (#0d1216, radio 18, aro blanco 7 % o borde de acento).
static func card(node_name: String, pad: int = 18, edge: Color = T.ENTRY_CARD_EDGE, edge_w: float = 1.0) -> PanelContainer:
	var sb := Kit.box(T.ENTRY_CARD_BG, 18, edge_w, edge)
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 24
	sb.shadow_offset = Vector2(0, 12)
	return Kit.panel(node_name, sb, pad)


static func vbox(node_name: String, sep: int = 10) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.name = node_name
	v.add_theme_constant_override("separation", sep)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return v


static func hbox(node_name: String, sep: int = 10) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.name = node_name
	h.add_theme_constant_override("separation", sep)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return h


static func spacer() -> Control:
	var s := Control.new()
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return s


## Viñeta + texto (fila de «Qué cambia para ti», «Antes de llegar», «Mientras no estabas»).
static func bullet_row(node_name: String, color: Color, text: String, font_size: int = 14, diamond: bool = false, dot_size: float = 7.0) -> HBoxContainer:
	var h := hbox(node_name, 10)
	var d := Dot.new(color, dot_size, diamond)
	d.name = "Dot"
	d.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	d.custom_minimum_size = Vector2(dot_size + 2, font_size + 5)
	h.add_child(d)
	var l := Kit.label(text, font_size, T.TEXT_KEY)
	l.name = "Text"
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	return h


# ==========================================================================
# Accesibilidad previa al ingreso (tamaño de letra y alto contraste)
# ==========================================================================
## Recorre `root` y escala los tamaños de letra según el servicio; con alto contraste los textos
## secundarios (#9aa6ae / #7c8992) pasan a #eef2f4.
static func apply_accessibility(root: Node, svc: Object) -> void:
	if root == null or svc == null:
		return
	var scale: float = svc.font_scale()
	var hc: bool = svc.high_contrast
	_apply_rec(root, scale, hc)


static func _apply_rec(n: Node, scale: float, hc: bool) -> void:
	if n is Label or n is Button or n is LineEdit:
		var c := n as Control
		if c.has_theme_font_size_override("font_size"):
			_scale_size(c, "font_size", scale)
		if n is Label and c.has_theme_color_override("font_color"):
			var cur := c.get_theme_color("font_color")
			# Si el código cambió el color desde la última pasada, ese es el nuevo color base.
			if not c.has_meta("a11y_fc") or not cur.is_equal_approx(c.get_meta("a11y_set_fc", cur)):
				c.set_meta("a11y_fc", cur)
			var base: Color = c.get_meta("a11y_fc")
			var secondary := base.is_equal_approx(T.TEXT_SECONDARY) or base.is_equal_approx(T.TEXT_MUTED)
			var out := T.TEXT if (hc and secondary) else base
			c.add_theme_color_override("font_color", out)
			c.set_meta("a11y_set_fc", out)
	elif n is RichTextLabel:
		var r := n as RichTextLabel
		if r.has_theme_font_size_override("normal_font_size"):
			var fs := _scale_size(r, "normal_font_size", scale)
			r.add_theme_font_size_override("bold_font_size", fs)
	for ch in n.get_children():
		_apply_rec(ch, scale, hc)


static func _scale_size(c: Control, prop: String, scale: float) -> int:
	var cur := c.get_theme_font_size(prop)
	if not c.has_meta("a11y_fs") or cur != int(c.get_meta("a11y_set_fs", cur)):
		c.set_meta("a11y_fs", cur)
	var out := maxi(8, roundi(int(c.get_meta("a11y_fs")) * scale))
	c.add_theme_font_size_override(prop, out)
	c.set_meta("a11y_set_fs", out)
	return out


## Nombre accesible (AccessKit, Godot 4.5+) si la propiedad existe.
static func a11y_name(c: Control, text: String) -> void:
	if "accessibility_name" in c:
		c.set("accessibility_name", text)


# ==========================================================================
# Controles dibujados
# ==========================================================================
## Punto redondo o rombo (los consejos tácticos van en rombo rotado 45°).
class Dot extends Control:
	var color := Color.WHITE:
		set(v):
			color = v
			queue_redraw()
	var dot := 7.0
	var diamond := false

	func _init(c: Color = Color.WHITE, s: float = 7.0, is_diamond: bool = false) -> void:
		color = c
		dot = s
		diamond = is_diamond
		custom_minimum_size = Vector2(s, s)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var cy := minf(size.y * 0.5, dot * 0.5 + 6.0)
		var ctr := Vector2(size.x * 0.5, cy)
		if diamond:
			var h := dot * 0.72
			draw_colored_polygon(PackedVector2Array([ctr + Vector2(0, -h), ctr + Vector2(h, 0), ctr + Vector2(0, h), ctr + Vector2(-h, 0)]), color)
		else:
			draw_circle(ctr, dot * 0.5, color, true, -1.0, true)


## Avatar redondo (#1a252c) con aro de color de 2 px.
class Avatar extends Control:
	var ring := Color("#4fe39a"):
		set(v):
			ring = v
			queue_redraw()
	var fill := Color("#1a252c")
	var diameter := 28.0

	func _init(d: float = 28.0, ring_color: Color = Color("#4fe39a")) -> void:
		diameter = d
		ring = ring_color
		custom_minimum_size = Vector2(d + 4, d + 4)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		draw_circle(c, diameter * 0.5 + 2.0, ring, true, -1.0, true)
		draw_circle(c, diameter * 0.5, fill, true, -1.0, true)


## Casilla `18×18` redondeada (cian marcada).
class CheckSquare extends Control:
	signal toggled(on: bool)
	var on := true:
		set(v):
			on = v
			queue_redraw()

	func _init() -> void:
		custom_minimum_size = Vector2(18, 18)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			on = not on
			toggled.emit(on)
			accept_event()

	func _draw() -> void:
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(5)
		sb.anti_aliasing = true
		if on:
			sb.bg_color = Color("#46e3c1")
		else:
			sb.bg_color = Color("#18242b")
			sb.border_color = Color(1, 1, 1, 0.2)
			sb.set_border_width_all(1)
		draw_style_box(sb, Rect2(Vector2.ZERO, Vector2(18, 18)))
		if on:
			draw_polyline(PackedVector2Array([Vector2(4.5, 9.5), Vector2(7.8, 12.6), Vector2(13.5, 5.8)]), Color("#071012"), 2.0, true)


## Código QR 132×132 (fondo #eef2f4, padding 8, rejilla N×N con huecos de 2 px).
class QRCode extends Control:
	var modules: Array[bool] = []:
		set(v):
			modules = v
			queue_redraw()
	var grid := 9
	var dark := Color("#0d1216")
	var light := Color("#eef2f4")
	var expired := false:
		set(v):
			expired = v
			queue_redraw()

	func _init() -> void:
		custom_minimum_size = Vector2(132, 132)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func dark_count() -> int:
		var n := 0
		for m in modules:
			if m:
				n += 1
		return n

	func _draw() -> void:
		var sb := StyleBoxFlat.new()
		sb.bg_color = light
		sb.set_corner_radius_all(12)
		sb.anti_aliasing = true
		draw_style_box(sb, Rect2(Vector2.ZERO, Vector2(132, 132)))
		var pad := 8.0
		var gap := 2.0
		var cell := (132.0 - pad * 2.0 - gap * (grid - 1)) / grid
		for i in mini(modules.size(), grid * grid):
			if modules[i]:
				var x := i % grid
				var y := i / grid
				draw_rect(Rect2(pad + x * (cell + gap), pad + y * (cell + gap), cell, cell), Color(dark, 0.25) if expired else dark)


## Silueta grande del personaje (viewBox 150×260) con «respiración» y pedestal brillante.
class Silhouette extends Control:
	var fill := Color("#1a252c"):
		set(v):
			fill = v
			queue_redraw()
	var stroke := Color("#2c3b44")
	var ring := Color("#46e3c1"):
		set(v):
			ring = v
			queue_redraw()
	var body_w := 260.0
	var body_h := 460.0
	var pedestal_w := 320.0
	var breathing := true
	var breath_phase := 0.0
	var breath_amount := 0.012
	var accent_body := Color(0, 0, 0, 0):
		set(v):
			accent_body = v
			queue_redraw()

	func _init(w: float = 260.0, h: float = 460.0, ped: float = 320.0) -> void:
		body_w = w
		body_h = h
		pedestal_w = ped
		custom_minimum_size = Vector2(maxf(w, ped), h + 20)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_process(true)

	func breath_scale() -> float:
		return 1.0 + sin(breath_phase) * breath_amount if breathing else 1.0

	func _process(delta: float) -> void:
		if breathing and is_visible_in_tree():
			breath_phase = fmod(breath_phase + delta * TAU / 3.6, TAU)
			queue_redraw()

	func _draw() -> void:
		var base := Vector2(size.x * 0.5, size.y - 20.0)
		# Pedestal: elipse con aro y halo.
		var ped_h := 40.0
		for i in 4:
			var grow := 4.0 + i * 7.0
			_ellipse(base, pedestal_w * 0.5 + grow, ped_h * 0.5 + grow * 0.5, Color(ring, 0.07 - i * 0.015), true)
		_ellipse(base, pedestal_w * 0.5, ped_h * 0.5, Color(ring, 0.08), true)
		_ellipse(base, pedestal_w * 0.5, ped_h * 0.5, ring, false)
		# Cuerpo (escalado al alto) con respiración vertical.
		var s := body_h / 260.0
		var bs := breath_scale()
		var origin := Vector2(base.x - 75.0 * s, base.y - body_h * bs)
		var xf := func(p: Vector2) -> Vector2: return origin + Vector2(p.x * s, p.y * s * bs)
		draw_circle(xf.call(Vector2(75, 40)), 22.0 * s, fill, true, -1.0, true)
		draw_circle(xf.call(Vector2(75, 40)), 22.0 * s, stroke, false, 2.0, true)
		var body_col := fill if accent_body.a <= 0.0 else fill.lerp(accent_body, 0.35)
		for sp in SP.parse(SILHOUETTE_BODY):
			var pts := PackedVector2Array()
			for p in sp["points"]:
				pts.append(xf.call(p))
			if pts.size() >= 3 and pts[0].is_equal_approx(pts[pts.size() - 1]):
				pts = pts.slice(0, pts.size() - 1)
			if pts.size() >= 3 and Geometry2D.triangulate_polygon(pts).size() > 0:
				draw_colored_polygon(pts, body_col)
				var closed := pts.duplicate()
				closed.append(pts[0])
				draw_polyline(closed, stroke, 2.0, true)

	func _ellipse(c: Vector2, rx: float, ry: float, col: Color, filled: bool) -> void:
		var pts := PackedVector2Array()
		for i in 49:
			var a := TAU * i / 48.0
			pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
		if filled:
			draw_colored_polygon(pts.slice(0, 48), col)
		else:
			draw_polyline(pts, col, 2.0, true)


## Chibi del refugio (viewBox 30×38): sombra, cuerpo, cara, peinado y ojos.
class Chibi extends Control:
	const SKIN := Color("#f1d3b8")
	var body := Color("#8a3a2b"):
		set(v):
			body = v
			queue_redraw()
	var hair := Color("#2b1d14"):
		set(v):
			hair = v
			queue_redraw()
	var eyes := Color("#1a1a1a"):
		set(v):
			eyes = v
			queue_redraw()
	var shadow := Color(159 / 255.0, 227 / 255.0, 106 / 255.0, 0.5):
		set(v):
			shadow = v
			queue_redraw()
	var hair_style := 0:
		set(v):
			hair_style = v
			queue_redraw()
	var body_scale := 1.0:
		set(v):
			body_scale = v
			queue_redraw()

	func _init(sz: Vector2 = Vector2(44, 56)) -> void:
		custom_minimum_size = sz
		size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var s := minf(size.x / 30.0, size.y / 38.0)
		var o := (size - Vector2(30, 38) * s) * 0.5
		var sh := PackedVector2Array()
		for i in 32:
			var a := TAU * i / 32.0
			sh.append(o + Vector2(15 + cos(a) * 10, 36 + sin(a) * 2.5) * s)
		draw_colored_polygon(sh, shadow)
		var bw := 16.0 * body_scale
		var sb := StyleBoxFlat.new()
		sb.bg_color = body
		sb.set_corner_radius_all(int(7 * s))
		sb.anti_aliasing = true
		draw_style_box(sb, Rect2(o + Vector2(15 - bw * 0.5, 18) * s, Vector2(bw, 16) * s))
		draw_circle(o + Vector2(15, 12) * s, 10 * s, SKIN, true, -1.0, true)
		var d: String = CHIBI_HAIR[clampi(hair_style, 0, CHIBI_HAIR.size() - 1)]
		for sp in SP.parse(d):
			var pts := PackedVector2Array()
			for p in sp["points"]:
				pts.append(o + p * s)
			if pts.size() >= 3 and pts[0].is_equal_approx(pts[pts.size() - 1]):
				pts = pts.slice(0, pts.size() - 1)
			if pts.size() >= 3 and Geometry2D.triangulate_polygon(pts).size() > 0:
				draw_colored_polygon(pts, hair)
		draw_circle(o + Vector2(11.5, 13) * s, 1.4 * s, eyes, true, -1.0, true)
		draw_circle(o + Vector2(18.5, 13) * s, 1.4 * s, eyes, true, -1.0, true)


## Barra de 5 segmentos (puntuaciones de clase: Daño, Control, Supervivencia, Dificultad).
class Segments extends Control:
	var value := 0:
		set(v):
			value = v
			queue_redraw()
	var total := 5
	var on := Color("#46e3c1")
	var off := Color("#26333b")

	func _init(v: int = 0) -> void:
		value = v
		custom_minimum_size = Vector2(60, 6)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var gap := 3.0
		var w := (size.x - gap * (total - 1)) / total
		for i in total:
			var sb := StyleBoxFlat.new()
			sb.bg_color = on if i < value else off
			sb.set_corner_radius_all(3)
			draw_style_box(sb, Rect2(i * (w + gap), 0, w, 6))


## Barra segmentada de instalación: [{flex, ratio, color}] con huecos de 4 px.
class SegmentedBar extends Control:
	var segments: Array = []:
		set(v):
			segments = v
			queue_redraw()
	var track := Color("#121a20")

	func _init() -> void:
		custom_minimum_size = Vector2(100, 12)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var total := 0.0
		for s in segments:
			total += float(s["flex"])
		if total <= 0.0:
			return
		var gap := 4.0
		var avail := size.x - gap * (segments.size() - 1)
		var x := 0.0
		for s in segments:
			var w := avail * float(s["flex"]) / total
			var sb := StyleBoxFlat.new()
			sb.bg_color = track
			sb.set_corner_radius_all(4)
			draw_style_box(sb, Rect2(x, 0, w, size.y))
			var r := clampf(float(s["ratio"]), 0.0, 1.0)
			if r > 0.0:
				var fb := StyleBoxFlat.new()
				fb.bg_color = s["color"]
				fb.set_corner_radius_all(4 if r >= 1.0 else 0)
				fb.corner_radius_top_left = 4
				fb.corner_radius_bottom_left = 4
				draw_style_box(fb, Rect2(x, 0, w * r, size.y))
			x += w + gap
