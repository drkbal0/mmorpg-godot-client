extends RefCounted
## Parser y rasterizador vectorial mínimo de `path d` SVG para iconos de UI v2.4.
##
## Convierte un trazo SVG (viewBox 24×24) en subtrayectos de puntos
## (`PackedVector2Array`) que se dibujan con `draw_polyline` /
## `draw_colored_polygon` desde `_draw()`. Así los iconos de estadísticas y
## monedas se renderizan nítidos a 16, 20 y 24 px sin texturas.
##
## Comandos soportados (absolutos y relativos): M L H V C S Q T A Z.
## Uso:
##     const SvgPath = preload("res://ui/icons/svg_path.gd")
##     var subpaths := SvgPath.parse("M12 3l7 3v6z")
##     SvgPath.draw_layers(self, layers, Rect2(0, 0, 16, 16))

const VIEWBOX := 24.0
const CURVE_SEGMENTS := 10
const ARC_SEGMENTS_PER_QUARTER := 6

static var _cache: Dictionary = {}
static var _number_regex: RegEx = null


## Devuelve un Array de Dictionary {"points": PackedVector2Array, "closed": bool}
## en coordenadas del viewBox. El resultado se cachea por cadena `d`.
static func parse(d: String) -> Array:
	if _cache.has(d):
		return _cache[d]
	var result := _parse_uncached(d)
	_cache[d] = result
	return result


static func _tokenize(d: String) -> Array:
	if _number_regex == null:
		_number_regex = RegEx.new()
		_number_regex.compile("[MmLlHhVvCcSsQqTtAaZz]|[+-]?(?:\\d+\\.?\\d*|\\.\\d+)(?:[eE][+-]?\\d+)?")
	var tokens: Array = []
	for m in _number_regex.search_all(d):
		var s: String = m.get_string()
		if s.length() == 1 and "MmLlHhVvCcSsQqTtAaZz".contains(s):
			tokens.append(s)
		else:
			tokens.append(float(s))
	return tokens


static func _parse_uncached(d: String) -> Array:
	var tokens := _tokenize(d)
	var subpaths: Array = []
	var current := PackedVector2Array()
	var closed := false
	var pos := Vector2.ZERO
	var start := Vector2.ZERO
	var last_ctrl := Vector2.ZERO
	var last_cmd := ""
	var cmd := ""
	var i := 0

	while i < tokens.size():
		var tok = tokens[i]
		if tok is String:
			cmd = tok
			i += 1
			if cmd == "Z" or cmd == "z":
				if current.size() > 0:
					subpaths.append({"points": current, "closed": true})
				current = PackedVector2Array()
				closed = false
				pos = start
				last_cmd = cmd
				continue
		elif cmd == "":
			i += 1
			continue

		var rel := cmd == cmd.to_lower()
		var base := pos if rel else Vector2.ZERO
		match cmd.to_upper():
			"M":
				if i + 1 >= tokens.size():
					break
				if current.size() > 0:
					subpaths.append({"points": current, "closed": closed})
				current = PackedVector2Array()
				closed = false
				pos = base + Vector2(tokens[i], tokens[i + 1])
				start = pos
				current.append(pos)
				i += 2
				# Pares implícitos tras M se tratan como L (SVG spec).
				cmd = "l" if rel else "L"
			"L":
				if i + 1 >= tokens.size():
					break
				pos = base + Vector2(tokens[i], tokens[i + 1])
				_ensure_start(current, start)
				current.append(pos)
				i += 2
			"H":
				pos = Vector2((pos.x if rel else 0.0) + float(tokens[i]), pos.y)
				_ensure_start(current, start)
				current.append(pos)
				i += 1
			"V":
				pos = Vector2(pos.x, (pos.y if rel else 0.0) + float(tokens[i]))
				_ensure_start(current, start)
				current.append(pos)
				i += 1
			"C":
				if i + 5 >= tokens.size():
					break
				var c1: Vector2 = base + Vector2(tokens[i], tokens[i + 1])
				var c2: Vector2 = base + Vector2(tokens[i + 2], tokens[i + 3])
				var p: Vector2 = base + Vector2(tokens[i + 4], tokens[i + 5])
				_ensure_start(current, start)
				_cubic(current, pos, c1, c2, p)
				last_ctrl = c2
				pos = p
				i += 6
			"S":
				if i + 3 >= tokens.size():
					break
				var c1s: Vector2 = pos
				if last_cmd.to_upper() == "C" or last_cmd.to_upper() == "S":
					c1s = pos * 2.0 - last_ctrl
				var c2s: Vector2 = base + Vector2(tokens[i], tokens[i + 1])
				var ps: Vector2 = base + Vector2(tokens[i + 2], tokens[i + 3])
				_ensure_start(current, start)
				_cubic(current, pos, c1s, c2s, ps)
				last_ctrl = c2s
				pos = ps
				i += 4
			"Q":
				if i + 3 >= tokens.size():
					break
				var q: Vector2 = base + Vector2(tokens[i], tokens[i + 1])
				var pq: Vector2 = base + Vector2(tokens[i + 2], tokens[i + 3])
				_ensure_start(current, start)
				_quad(current, pos, q, pq)
				last_ctrl = q
				pos = pq
				i += 4
			"T":
				if i + 1 >= tokens.size():
					break
				var qt: Vector2 = pos
				if last_cmd.to_upper() == "Q" or last_cmd.to_upper() == "T":
					qt = pos * 2.0 - last_ctrl
				var pt: Vector2 = base + Vector2(tokens[i], tokens[i + 1])
				_ensure_start(current, start)
				_quad(current, pos, qt, pt)
				last_ctrl = qt
				pos = pt
				i += 2
			"A":
				if i + 6 >= tokens.size():
					break
				var rx: float = absf(tokens[i])
				var ry: float = absf(tokens[i + 1])
				var rot: float = tokens[i + 2]
				var large: bool = float(tokens[i + 3]) != 0.0
				var sweep: bool = float(tokens[i + 4]) != 0.0
				var pa: Vector2 = base + Vector2(tokens[i + 5], tokens[i + 6])
				_ensure_start(current, start)
				_arc(current, pos, rx, ry, rot, large, sweep, pa)
				pos = pa
				i += 7
			_:
				i += 1
		last_cmd = cmd
	if current.size() > 0:
		subpaths.append({"points": current, "closed": closed})
	return subpaths


static func _ensure_start(current: PackedVector2Array, start: Vector2) -> void:
	if current.is_empty():
		current.append(start)


static func _cubic(out: PackedVector2Array, p0: Vector2, c1: Vector2, c2: Vector2, p3: Vector2) -> void:
	for s in range(1, CURVE_SEGMENTS + 1):
		var t := float(s) / CURVE_SEGMENTS
		out.append(p0.bezier_interpolate(c1, c2, p3, t))


static func _quad(out: PackedVector2Array, p0: Vector2, q: Vector2, p2: Vector2) -> void:
	for s in range(1, CURVE_SEGMENTS + 1):
		var t := float(s) / CURVE_SEGMENTS
		out.append(p0.lerp(q, t).lerp(q.lerp(p2, t), t))


## Conversión endpoint → centro (SVG 1.1, apéndice F.6).
static func _arc(out: PackedVector2Array, p0: Vector2, rx: float, ry: float, rot_deg: float,
		large: bool, sweep: bool, p1: Vector2) -> void:
	if p0.is_equal_approx(p1):
		return
	if rx < 0.0001 or ry < 0.0001:
		out.append(p1)
		return
	var phi := deg_to_rad(rot_deg)
	var cphi := cos(phi)
	var sphi := sin(phi)
	var dx := (p0.x - p1.x) * 0.5
	var dy := (p0.y - p1.y) * 0.5
	var x1p := cphi * dx + sphi * dy
	var y1p := -sphi * dx + cphi * dy
	var lam := (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
	if lam > 1.0:
		var sl := sqrt(lam)
		rx *= sl
		ry *= sl
	var num := rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
	var den := rx * rx * y1p * y1p + ry * ry * x1p * x1p
	var coef := 0.0
	if den > 0.0:
		coef = sqrt(maxf(0.0, num / den))
	if large == sweep:
		coef = -coef
	var cxp := coef * (rx * y1p / ry)
	var cyp := coef * -(ry * x1p / rx)
	var cx := cphi * cxp - sphi * cyp + (p0.x + p1.x) * 0.5
	var cy := sphi * cxp + cphi * cyp + (p0.y + p1.y) * 0.5
	var v1 := Vector2((x1p - cxp) / rx, (y1p - cyp) / ry)
	var v2 := Vector2((-x1p - cxp) / rx, (-y1p - cyp) / ry)
	var theta1 := atan2(v1.y, v1.x)
	var dtheta := v1.angle_to(v2)
	if not sweep and dtheta > 0.0:
		dtheta -= TAU
	elif sweep and dtheta < 0.0:
		dtheta += TAU
	var segs := maxi(2, int(ceil(absf(dtheta) / (PI * 0.5) * ARC_SEGMENTS_PER_QUARTER)))
	for s in range(1, segs + 1):
		var a := theta1 + dtheta * float(s) / segs
		var ex := rx * cos(a)
		var ey := ry * sin(a)
		out.append(Vector2(cphi * ex - sphi * ey + cx, sphi * ex + cphi * ey + cy))
	# Garantiza que el último punto coincide exactamente con el destino.
	out[out.size() - 1] = p1


## Bounding box (en coordenadas del viewBox) de todos los puntos de `d`.
static func bounds(d: String) -> Rect2:
	var rect := Rect2()
	var first := true
	for sp in parse(d):
		for p in sp["points"]:
			if first:
				rect = Rect2(p, Vector2.ZERO)
				first = false
			else:
				rect = rect.expand(p)
	return rect


## Dibuja capas de icono en `canvas` dentro de `rect` (escala uniforme del viewBox 24).
## Cada capa: {"d": String, "fill": Color|null, "stroke": Color|null, "width": float}.
## `tint` (si no es transparente) sustituye el color de trazo/relleno de la capa principal.
static func draw_layers(canvas: CanvasItem, layers: Array, rect: Rect2, tint: Color = Color(0, 0, 0, 0)) -> void:
	var s: float = minf(rect.size.x, rect.size.y) / VIEWBOX
	var off := rect.position + (rect.size - Vector2(VIEWBOX, VIEWBOX) * s) * 0.5
	for li in layers.size():
		var layer: Dictionary = layers[li]
		var use_tint := li == 0 and tint.a > 0.0
		for sp in parse(layer.get("d", "")):
			var pts := PackedVector2Array()
			for p in sp["points"]:
				pts.append(off + p * s)
			var fill = layer.get("fill", null)
			if fill != null and pts.size() >= 3:
				var fc: Color = tint if use_tint else fill
				var poly := pts
				if poly[0].is_equal_approx(poly[poly.size() - 1]):
					poly = poly.slice(0, poly.size() - 1)
				if Geometry2D.triangulate_polygon(poly).size() > 0:
					canvas.draw_colored_polygon(poly, fc)
			var stroke = layer.get("stroke", null)
			if stroke != null:
				var sc: Color = tint if use_tint else stroke
				var w: float = maxf(0.75, float(layer.get("width", 2.0)) * s)
				_stroke(canvas, pts, sp["closed"], sc, w)


static func _stroke(canvas: CanvasItem, pts: PackedVector2Array, closed: bool, color: Color, width: float) -> void:
	if pts.size() == 0:
		return
	var r := width * 0.5
	# Subtrayecto degenerado (p. ej. "h.01"): punto redondo.
	var length := 0.0
	for k in range(1, pts.size()):
		length += pts[k].distance_to(pts[k - 1])
	if length < 0.5:
		canvas.draw_circle(pts[0], r, color, true, -1.0, true)
		return
	var line := pts
	if closed and not pts[0].is_equal_approx(pts[pts.size() - 1]):
		line = pts.duplicate()
		line.append(pts[0])
	canvas.draw_polyline(line, color, width, true)
	# stroke-linejoin / stroke-linecap = round (como en el diseño). En trazos
	# finos (< 1.5 px) los discos engordan el detalle: se omiten.
	if width < 1.5:
		return
	for k in line.size():
		canvas.draw_circle(line[k], r, color, true, -1.0, true)
