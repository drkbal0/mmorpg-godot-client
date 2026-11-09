@tool
extends Control
## HUDv2 background silhouette (1360x460 local space).
##
## Shapes: "trapecio" (18,461)(66,276)(1294,276)(1342,461), "escalonada"
## (stepped, stats block integrated) and "curva" (rounded shoulders + arched
## top). Multi-layer shadow: -2/-4/-6 px, black alpha 0.12/0.08/0.05.
## The StatsTab (rounded StyleBoxFlat) is drawn for Trapecio and Curva.

const T = preload("res://ui/hud_tokens.gd")
const D = preload("res://ui/components/HUDv2/hud_draw.gd")

@export_enum("trapecio", "escalonada", "curva") var shape: String = T.SHAPE_TRAPECIO:
	set(value):
		shape = T.normalize_shape(value)
		_outline_cache = PackedVector2Array()
		queue_redraw()

@export var accent: Color = T.ACCENT_DEFAULT:
	set(value):
		accent = value
		queue_redraw()

var _outline_cache := PackedVector2Array()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = T.HUD_SIZE


func has_stats_tab() -> bool:
	return shape != T.SHAPE_ESCALONADA


func get_stats_tab_radius() -> int:
	return int(T.STATS_TAB_RADIUS.get(shape, 16))


func get_outline() -> PackedVector2Array:
	if not _outline_cache.is_empty():
		return _outline_cache
	match shape:
		T.SHAPE_ESCALONADA:
			_outline_cache = PackedVector2Array(T.SHAPE_STEPPED_POINTS)
		T.SHAPE_CURVA:
			_outline_cache = _build_curve()
		_:
			_outline_cache = PackedVector2Array(T.SHAPE_TRAPEZOID_POINTS)
	return _outline_cache


## Smallest y of the silhouette's top edge at column `x` (for accent bar).
func top_y_at(x: float) -> float:
	var pts := get_outline()
	var best := INF
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		if (x < minf(a.x, b.x)) or (x > maxf(a.x, b.x)) or is_equal_approx(a.x, b.x):
			continue
		var y := lerpf(a.y, b.y, (x - a.x) / (b.x - a.x))
		best = minf(best, y)
	return best if best != INF else 276.0


func _build_curve() -> PackedVector2Array:
	var l: Array = T.CURVE_LEFT
	var t: Array = T.CURVE_TOP
	var r: Array = T.CURVE_RIGHT
	var pts := D.cubic_points(l[0], l[1], l[2], l[3], 18)
	var top := D.quadratic_points(t[0], t[1], t[2], 40)
	top.remove_at(0)
	pts.append_array(top)
	var right := D.cubic_points(r[0], r[1], r[2], r[3], 18)
	right.remove_at(0)
	pts.append_array(right)
	return pts


func _draw() -> void:
	var outline := get_outline()
	var tab := T.STATS_TAB_RECT
	var tab_radius := get_stats_tab_radius()
	var show_tab := has_stats_tab()

	# 1) Multi-layer shadow (outermost first).
	for layer in T.SHADOW_LAYERS:
		var shade := Color(0, 0, 0, layer.y)
		draw_colored_polygon(D.translated(outline, Vector2(0, layer.x)), shade)
		if show_tab:
			var sb := T.box(shade, tab_radius)
			sb.corner_radius_bottom_left = 0
			sb.corner_radius_bottom_right = 0
			draw_style_box(sb, Rect2(tab.position + Vector2(0, layer.x), tab.size))

	# 2) Silhouette fill: vertical gradient through per-vertex colours.
	var colors := PackedColorArray()
	colors.resize(outline.size())
	for i in outline.size():
		var f := clampf((outline[i].y - 190.0) / (461.0 - 190.0), 0.0, 1.0)
		colors[i] = T.PANEL_TOP.lerp(T.PANEL_BOTTOM, f)
	draw_polygon(outline, colors)
	# Edge highlight on sides + top (outline is open at the bottom).
	draw_polyline(outline, T.PANEL_EDGE, 1.0, true)

	# 3) Stats tab (StyleBoxFlat) for Trapecio / Curva.
	if show_tab:
		var sb_tab := T.box(T.PANEL_TAB, tab_radius)
		sb_tab.corner_radius_bottom_left = 0
		sb_tab.corner_radius_bottom_right = 0
		draw_style_box(sb_tab, tab)
		var tab_top_y := top_y_at(tab.position.x + 2.0)
		draw_polyline(D.top_rounded_outline(tab, tab_radius, tab_top_y), T.PANEL_EDGE, 1.0, true)

	# 4) Accent bar centred on the top edge, with soft glow.
	var bar := T.ACCENT_BAR_RECT
	var y := top_y_at(bar.get_center().x)
	bar.position.y = y
	for g in 3:
		var glow := Color(accent, 0.08 - g * 0.02)
		draw_rect(bar.grow_individual(4 + g * 3, 0, 4 + g * 3, 3 + g * 2), glow)
	draw_style_box(T.box(accent, 2), bar)

	# 5) Divider between action deck and inventory.
	draw_line(Vector2(T.DIVIDER_X, 296), Vector2(T.DIVIDER_X, 446), T.DIVIDER, 1.0)

	# 6) Mini round buttons left of the portrait.
	for c in T.MINI_BUTTONS:
		draw_circle(c, T.MINI_BUTTON_RADIUS, T.SLOT_BG_DEEP)
		draw_arc(c, T.MINI_BUTTON_RADIUS, 0, TAU, 32, T.SLOT_BORDER, 1.5, true)
