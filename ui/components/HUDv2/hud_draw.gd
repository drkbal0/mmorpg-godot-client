extends RefCounted
## HUDv2 static drawing helpers: geometry, vector glyphs and text placement.
## Everything is procedural (no textures for frames or icons).


# --------------------------------------------------------------------------
# Geometry
# --------------------------------------------------------------------------
static func translated(points: PackedVector2Array, offset: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(points.size())
	for i in points.size():
		out[i] = points[i] + offset
	return out


static func circle_points(center: Vector2, radius: float, segments: int = 48) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in segments:
		var a := TAU * float(i) / float(segments)
		pts.append(center + Vector2(cos(a), sin(a)) * radius)
	return pts


static func rounded_rect_points(rect: Rect2, radius: float, segments: int = 6) -> PackedVector2Array:
	var r := minf(radius, minf(rect.size.x, rect.size.y) * 0.5)
	var x1 := rect.position.x
	var y1 := rect.position.y
	var x2 := rect.end.x
	var y2 := rect.end.y
	var corners := [
		[Vector2(x2 - r, y1 + r), -PI * 0.5],
		[Vector2(x2 - r, y2 - r), 0.0],
		[Vector2(x1 + r, y2 - r), PI * 0.5],
		[Vector2(x1 + r, y1 + r), PI],
	]
	var pts := PackedVector2Array()
	for c in corners:
		var center: Vector2 = c[0]
		var start: float = c[1]
		for i in segments + 1:
			var a := start + (PI * 0.5) * float(i) / float(segments)
			pts.append(center + Vector2(cos(a), sin(a)) * r)
	return pts


## Pie wedge starting at 12 o'clock and sweeping clockwise from `from_frac`
## to 1.0 of a full turn.
static func pie_points(center: Vector2, radius: float, from_frac: float, segments: int = 48) -> PackedVector2Array:
	var pts := PackedVector2Array([center])
	var start := -PI * 0.5 + TAU * clampf(from_frac, 0.0, 1.0)
	var end := -PI * 0.5 + TAU
	var steps := maxi(2, int(ceil(segments * (1.0 - from_frac))))
	for i in steps + 1:
		var a := lerpf(start, end, float(i) / float(steps))
		pts.append(center + Vector2(cos(a), sin(a)) * radius)
	return pts


static func cubic_points(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, steps: int = 16) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in steps + 1:
		pts.append(p0.bezier_interpolate(p1, p2, p3, float(i) / float(steps)))
	return pts


static func quadratic_points(p0: Vector2, p1: Vector2, p2: Vector2, steps: int = 32) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in steps + 1:
		var t := float(i) / float(steps)
		pts.append(p0.lerp(p1, t).lerp(p1.lerp(p2, t), t))
	return pts


## Open outline of a rectangle with rounded top corners, cut at `cut_y`
## (used for the stats tab border: left side -> top -> right side).
static func top_rounded_outline(rect: Rect2, radius: float, cut_y: float, segments: int = 8) -> PackedVector2Array:
	var r := minf(radius, rect.size.x * 0.5)
	var pts := PackedVector2Array([Vector2(rect.position.x, cut_y)])
	var tl := Vector2(rect.position.x + r, rect.position.y + r)
	var tr := Vector2(rect.end.x - r, rect.position.y + r)
	for i in segments + 1:
		var a := PI + (PI * 0.5) * float(i) / float(segments)
		pts.append(tl + Vector2(cos(a), sin(a)) * r)
	for i in segments + 1:
		var a := -PI * 0.5 + (PI * 0.5) * float(i) / float(segments)
		pts.append(tr + Vector2(cos(a), sin(a)) * r)
	pts.append(Vector2(rect.end.x, cut_y))
	return pts


## Mana "drop" (gota) polygon of size w x h centred at `center`.
static func drop_points(center: Vector2, size: Vector2, segments: int = 16) -> PackedVector2Array:
	var r := size.x * 0.5
	var tip := Vector2(center.x, center.y - size.y * 0.5)
	var c := Vector2(center.x, center.y + size.y * 0.5 - r)
	var d := c.y - tip.y
	var phi := acos(clampf(r / d, -1.0, 1.0))
	var pts := PackedVector2Array([tip])
	var a0 := -PI * 0.5 + phi
	var a1 := -PI * 0.5 + TAU - phi
	for i in segments + 1:
		var a := lerpf(a0, a1, float(i) / float(segments))
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	return pts


# --------------------------------------------------------------------------
# Composite draws
# --------------------------------------------------------------------------
## Dark radial cooldown overlay clipped to a rounded rect (or circle when
## radius >= half the size). `fraction` = remaining / total.
static func draw_cooldown(ci: CanvasItem, rect: Rect2, radius: float, fraction: float, color: Color) -> void:
	if fraction <= 0.001:
		return
	var clip := rounded_rect_points(rect, radius)
	if fraction >= 0.999:
		ci.draw_colored_polygon(clip, color)
		return
	var pie := pie_points(rect.get_center(), rect.size.length(), 1.0 - fraction)
	for poly in Geometry2D.intersect_polygons(pie, clip):
		if poly.size() >= 3:
			ci.draw_colored_polygon(poly, color)
	# Sweep edge highlight.
	var a := -PI * 0.5 + TAU * (1.0 - fraction)
	var c := rect.get_center()
	var edge := c + Vector2(cos(a), sin(a)) * rect.size.length()
	var hits := Geometry2D.intersect_polyline_with_polygon(PackedVector2Array([c, edge]), clip)
	for seg in hits:
		ci.draw_polyline(seg, Color(1, 1, 1, 0.18), 1.0, true)


static func baseline_for_center(font: Font, size: int, center_y: float) -> float:
	return center_y + (font.get_ascent(size) - font.get_descent(size)) * 0.5


## Draws text centred in `rect` (both axes). Optional 1px drop shadow.
static func draw_text_centered(ci: CanvasItem, font: Font, size: int, rect: Rect2, text: String, color: Color, shadow: bool = false) -> void:
	var y := baseline_for_center(font, size, rect.get_center().y)
	if shadow:
		ci.draw_string(font, Vector2(rect.position.x, y + 1), text, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, size, Color(0, 0, 0, 0.55))
	ci.draw_string(font, Vector2(rect.position.x, y), text, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, size, color)


static func draw_text_aligned(ci: CanvasItem, font: Font, size: int, rect: Rect2, text: String, color: Color, align: HorizontalAlignment) -> void:
	var y := baseline_for_center(font, size, rect.get_center().y)
	ci.draw_string(font, Vector2(rect.position.x, y), text, align, rect.size.x, size, color)


static func draw_ring(ci: CanvasItem, center: Vector2, radius: float, width: float, color: Color, from_frac: float = 0.0, to_frac: float = 1.0) -> void:
	if to_frac - from_frac <= 0.0005:
		return
	var a0 := -PI * 0.5 + TAU * from_frac
	var a1 := -PI * 0.5 + TAU * to_frac
	var segs := maxi(8, int(64.0 * (to_frac - from_frac)))
	ci.draw_arc(center, radius, a0, a1, segs, color, width, true)


# --------------------------------------------------------------------------
# Vector glyphs (icons)
# --------------------------------------------------------------------------
## kinds: slash, shield, dash, star, target, eye, diamond, user, recall, bag, coin
static func draw_glyph(ci: CanvasItem, kind: String, center: Vector2, size: float, color: Color, width: float = 2.0) -> void:
	var h := size * 0.5
	match kind:
		"slash":
			for i in 3:
				var off := (float(i) - 1.0) * size * 0.26
				ci.draw_line(center + Vector2(-h * 0.55 + off, h * 0.7), center + Vector2(h * 0.55 + off, -h * 0.7), color, width, true)
		"shield":
			var pts := PackedVector2Array([
				center + Vector2(0, -h), center + Vector2(h * 0.8, -h * 0.6),
				center + Vector2(h * 0.7, h * 0.2), center + Vector2(0, h),
				center + Vector2(-h * 0.7, h * 0.2), center + Vector2(-h * 0.8, -h * 0.6),
				center + Vector2(0, -h),
			])
			ci.draw_polyline(pts, color, width, true)
		"dash":
			ci.draw_line(center + Vector2(-h * 0.85, -h * 0.75), center + Vector2(-h * 0.85, h * 0.75), color, width, true)
			ci.draw_line(center + Vector2(-h * 0.45, 0), center + Vector2(h * 0.85, 0), color, width, true)
			ci.draw_polyline(PackedVector2Array([
				center + Vector2(h * 0.3, -h * 0.55), center + Vector2(h * 0.85, 0), center + Vector2(h * 0.3, h * 0.55)
			]), color, width, true)
		"star":
			var pts := PackedVector2Array()
			for i in 11:
				var r := h if i % 2 == 0 else h * 0.45
				var a := -PI * 0.5 + PI * float(i) / 5.0
				pts.append(center + Vector2(cos(a), sin(a)) * r)
			ci.draw_polyline(pts, color, width, true)
		"target":
			ci.draw_arc(center, h * 0.85, 0, TAU, 32, color, width, true)
			ci.draw_circle(center, h * 0.32, color)
		"eye":
			var top := quadratic_points(center + Vector2(-h, 0), center + Vector2(0, -h * 1.1), center + Vector2(h, 0), 16)
			var bottom := quadratic_points(center + Vector2(h, 0), center + Vector2(0, h * 1.1), center + Vector2(-h, 0), 16)
			top.append_array(bottom)
			ci.draw_polyline(top, color, width, true)
			ci.draw_circle(center, h * 0.32, color)
		"diamond":
			ci.draw_polyline(PackedVector2Array([
				center + Vector2(0, -h), center + Vector2(h * 0.75, 0), center + Vector2(0, h),
				center + Vector2(-h * 0.75, 0), center + Vector2(0, -h)
			]), color, width, true)
		"user":
			ci.draw_arc(center + Vector2(0, -h * 0.32), h * 0.36, 0, TAU, 32, color, width, true)
			ci.draw_arc(center + Vector2(0, h * 0.95), h * 0.78, PI * 1.08, PI * 1.92, 24, color, width, true)
		"recall":
			ci.draw_arc(center, h * 0.75, -PI * 0.35, PI * 1.45, 28, color, width, true)
			var tip := center + Vector2(cos(-PI * 0.35), sin(-PI * 0.35)) * h * 0.75
			ci.draw_polyline(PackedVector2Array([tip + Vector2(-h * 0.45, -h * 0.1), tip, tip + Vector2(-h * 0.05, h * 0.45)]), color, width, true)
		"bag":
			ci.draw_polyline(PackedVector2Array([
				center + Vector2(-h * 0.7, -h * 0.35), center + Vector2(h * 0.7, -h * 0.35),
				center + Vector2(h * 0.6, h * 0.8), center + Vector2(-h * 0.6, h * 0.8),
				center + Vector2(-h * 0.7, -h * 0.35)
			]), color, width, true)
			ci.draw_arc(center + Vector2(0, -h * 0.35), h * 0.35, PI, TAU, 12, color, width, true)
		"coin":
			ci.draw_circle(center, h, color)
			ci.draw_arc(center, h * 0.62, 0, TAU, 24, color.darkened(0.35), maxf(1.0, width * 0.6), true)
		_:
			ci.draw_circle(center, h * 0.4, color)
