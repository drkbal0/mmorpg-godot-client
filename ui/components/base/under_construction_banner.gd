@tool
extends Control
## Franja «EN CONSTRUCCIÓN» (UI v2.4, sección 2.2) para Tienda y Pase de batalla.
## Franjas diagonales a 135° (14 px ámbar 18 % / 14 px grafito), borde ámbar al
## 50 %, insignia «EN CONSTRUCCIÓN» y mensaje configurable por datos.

const T = preload("res://ui/tokens/hud_tokens.gd")

@export var badge_text: String = "EN CONSTRUCCIÓN":
	set(v):
		badge_text = v
		_refresh()

@export var message: String = "":
	set(v):
		message = v
		_refresh()

var badge: PanelContainer
var badge_label: Label
var message_label: Label
var _row: HBoxContainer


func _init() -> void:
	theme = T.THEME
	clip_contents = true
	custom_minimum_size = Vector2(320, T.CONSTRUCTION_HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	_row = HBoxContainer.new()
	_row.name = "Row"
	_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.add_theme_constant_override("separation", 12)
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_row)
	badge = PanelContainer.new()
	badge.name = "Badge"
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sb := T.box(T.CONSTRUCTION_BADGE_BG, 6)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	badge.add_theme_stylebox_override("panel", sb)
	_row.add_child(badge)
	badge_label = Label.new()
	badge_label.name = "BadgeLabel"
	badge_label.custom_minimum_size.y = 24
	badge_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge_label.add_theme_font_override("font", T.font("header"))
	badge_label.add_theme_font_size_override("font_size", 13)
	badge_label.add_theme_color_override("font_color", T.CONSTRUCTION_BADGE_TEXT)
	badge_label.add_theme_color_override("font_shadow_color", Color.TRANSPARENT)
	badge.add_child(badge_label)
	message_label = Label.new()
	message_label.name = "Message"
	message_label.add_theme_font_override("font", T.font("semibold"))
	message_label.add_theme_font_size_override("font_size", 14)
	message_label.add_theme_color_override("font_color", T.TEXT)
	# Sin overrun: con recorte el Label pierde su ancho mínimo y el HBox lo colapsa.
	# El desbordamiento lo recorta `clip_contents` del propio banner.
	_row.add_child(message_label)
	_refresh()


func setup(data: Dictionary) -> void:
	badge_text = str(data.get("badge", badge_text))
	message = str(data.get("message", message))


func _refresh() -> void:
	if badge_label == null:
		return
	badge_label.text = badge_text
	message_label.text = message
	message_label.visible = message != ""
	var spoken := badge_text if message == "" else "%s. %s" % [badge_text, message]
	tooltip_text = spoken
	if "accessibility_name" in self:
		set("accessibility_name", spoken)
	queue_redraw()


## Polígono del rectángulo redondeado del fondo.
func _rounded_rect_polygon(rect: Rect2, radius: float, seg: int = 6) -> PackedVector2Array:
	var r := minf(radius, minf(rect.size.x, rect.size.y) * 0.5)
	var pts := PackedVector2Array()
	var corners := [
		[rect.position + Vector2(rect.size.x - r, r), -PI * 0.5],
		[rect.position + Vector2(rect.size.x - r, rect.size.y - r), 0.0],
		[rect.position + Vector2(r, rect.size.y - r), PI * 0.5],
		[rect.position + Vector2(r, r), PI],
	]
	for c in corners:
		for k in seg + 1:
			var a: float = c[1] + (PI * 0.5) * float(k) / seg
			pts.append(c[0] + Vector2(cos(a), sin(a)) * r)
	return pts


## Número de franjas ámbar dibujadas (útil para validar en tests).
func stripe_count() -> int:
	var period := T.CONSTRUCTION_STRIPE * 2.0
	return int(ceil((size.x + size.y) / period)) + 1


func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var rect := Rect2(Vector2.ZERO, size)
	var bg := _rounded_rect_polygon(rect, T.CONSTRUCTION_RADIUS)
	draw_colored_polygon(bg, T.CONSTRUCTION_STRIPE_B)
	# repeating-linear-gradient(135deg, ámbar 0 14px, grafito 14px 28px)
	var w := T.CONSTRUCTION_STRIPE
	var period := w * 2.0
	var h := size.y
	for i in stripe_count():
		var x0 := -h + i * period
		var stripe := PackedVector2Array([
			Vector2(x0, h), Vector2(x0 + w, h), Vector2(x0 + w + h, 0), Vector2(x0 + h, 0),
		])
		for clipped in Geometry2D.intersect_polygons(stripe, bg):
			draw_colored_polygon(clipped, T.CONSTRUCTION_STRIPE_A)
	var edge := bg.duplicate()
	edge.append(bg[0])
	draw_polyline(edge, T.CONSTRUCTION_EDGE, 1.0, true)
