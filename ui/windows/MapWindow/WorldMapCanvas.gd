extends Control
## Lienzo 2D interactivo del mapa del mundo (UI v2.4 Paso 9 · MMO-Mapa.html).
## - Zoom con rueda / botones (+ −) centrado en el cursor y paneo arrastrando.
## - Niebla de guerra: regiones no exploradas tapadas con «???».
## - Marcadores por capa (misiones, PNJ, jefes, Refugio, secretos, postas, portales…).
## - Objetivo enfocado (desde Misiones › «Ver en el mapa») y ruta planificada.
## Todo el contenido sale de `WorldMapService`; el lienzo solo dibuja y traduce input.

const T = preload("res://ui/tokens/hud_tokens.gd")

signal marker_clicked(marker_id: String)
signal destination_requested(map_pos: Vector2)
signal view_changed(center: Vector2, zoom: float)

const MIN_ZOOM := 0.3
const MAX_ZOOM := 3.0
const WHEEL_STEP := 1.15
const BUTTON_STEP := 1.3
const PICK_RADIUS := 16.0
const DRAG_THRESHOLD := 4.0
const TERRAIN_SIZE := Vector2i(320, 208)

const KIND_COLORS := {
	"quest": Color("#f5c35b"), "npc": Color("#46e3c1"), "boss": Color("#ff6b6b"),
	"shelter": Color("#b78cff"), "secret": Color("#c39bff"), "post": Color("#6cb8ff"),
	"portal": Color("#b78cff"), "dungeon": Color("#9aa6ae"),
}
const KIND_LABELS := {
	"quest": "Misión", "npc": "PNJ", "boss": "Jefe", "shelter": "Refugio", "secret": "Secreto",
	"post": "Posta", "portal": "Portal", "dungeon": "Mazmorra",
}

var service: Node = null:
	set(v):
		if service and service.map_changed.is_connected(_on_map_changed):
			service.map_changed.disconnect(_on_map_changed)
		service = v
		if service:
			service.map_changed.connect(_on_map_changed)
			if not _centered_once:
				center = service.map_size * 0.5
		queue_redraw()

var zoom := 0.6
var center := Vector2(1000, 650)
var layers: Dictionary = {}
var selected_marker: String = ""
## Objetivo enfocado (Vector2) o null.
var focus_target: Variant = null
var focus_label: String = ""
## Ruta planificada (puntos en coordenadas de mapa).
var route_points: PackedVector2Array = PackedVector2Array()
var player_pos: Variant = null
## Marcadores extra (p. ej. objetivos de misiones rastreadas): {id, kind, name, pos}.
var extra_markers: Array = []

var zoom_in_button: Button
var zoom_out_button: Button

var _bg: Texture2D = null
var _dragging := false
var _press_pos := Vector2.ZERO
var _moved := false
var _centered_once := false
var _time := 0.0


func _init() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_CLICK
	custom_minimum_size = Vector2(300, 260)
	_bg = terrain_texture()
	var box := VBoxContainer.new()
	box.name = "ZoomButtons"
	box.add_theme_constant_override("separation", 6)
	box.anchor_left = 1.0
	box.anchor_right = 1.0
	box.anchor_top = 1.0
	box.anchor_bottom = 1.0
	box.offset_left = -48
	box.offset_right = -12
	box.offset_top = -88
	box.offset_bottom = -12
	add_child(box)
	zoom_in_button = _zoom_button("+", "Acercar")
	zoom_in_button.name = "ZoomIn"
	zoom_in_button.pressed.connect(func() -> void: zoom_at(BUTTON_STEP, size * 0.5))
	box.add_child(zoom_in_button)
	zoom_out_button = _zoom_button("−", "Alejar")
	zoom_out_button.name = "ZoomOut"
	zoom_out_button.pressed.connect(func() -> void: zoom_at(1.0 / BUTTON_STEP, size * 0.5))
	box.add_child(zoom_out_button)


static var _terrain_cache: Texture2D = null


## Textura de terreno procedural (ruido determinista, gris) que cada región tiñe con
## su color. Se genera una sola vez y se comparte entre lienzos.
static func terrain_texture() -> Texture2D:
	if _terrain_cache:
		return _terrain_cache
	var noise := FastNoiseLite.new()
	noise.seed = 1337
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.035
	noise.fractal_octaves = 4
	var detail := FastNoiseLite.new()
	detail.seed = 7
	detail.frequency = 0.18
	var img := Image.create(TERRAIN_SIZE.x, TERRAIN_SIZE.y, false, Image.FORMAT_RGB8)
	for y in TERRAIN_SIZE.y:
		for x in TERRAIN_SIZE.x:
			var n := noise.get_noise_2d(x, y) * 0.5 + 0.5
			var d := detail.get_noise_2d(x, y) * 0.5 + 0.5
			var v := clampf(0.42 + n * 0.55 + (d - 0.5) * 0.12, 0.0, 1.0)
			# Claros (vegetación rala / caminos) ligeramente más cálidos.
			img.set_pixel(x, y, Color(v * (1.0 + (n - 0.5) * 0.25), v, v * 0.92))
	_terrain_cache = ImageTexture.create_from_image(img)
	return _terrain_cache


func _zoom_button(text: String, spoken: String) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = spoken
	b.custom_minimum_size = Vector2(36, 36)
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_override("font", T.font("bold"))
	b.add_theme_font_size_override("font_size", 16)
	var sb := T.box(Color(T.PANEL_BG, 0.92), 9, 1, Color(1, 1, 1, 0.12))
	b.add_theme_stylebox_override("normal", sb)
	var hv := sb.duplicate() as StyleBoxFlat
	hv.bg_color = T.SLOT_READY
	b.add_theme_stylebox_override("hover", hv)
	b.add_theme_stylebox_override("pressed", hv)
	b.add_theme_color_override("font_color", T.TEXT)
	return b


func _process(delta: float) -> void:
	if focus_target != null and is_visible_in_tree():
		_time += delta
		queue_redraw()


func _on_map_changed() -> void:
	queue_redraw()


# ==========================================================================
# Transformaciones
# ==========================================================================
func world_to_screen(p: Vector2) -> Vector2:
	return (p - center) * zoom + size * 0.5


func screen_to_world(s: Vector2) -> Vector2:
	return (s - size * 0.5) / zoom + center


## Zoom manteniendo fijo el punto del mapa bajo `screen_pos`.
func zoom_at(factor: float, screen_pos: Vector2) -> void:
	var anchor := screen_to_world(screen_pos)
	zoom = clampf(zoom * factor, MIN_ZOOM, MAX_ZOOM)
	center = anchor - (screen_pos - size * 0.5) / zoom
	_clamp_center()
	_changed()


func set_zoom(z: float) -> void:
	zoom = clampf(z, MIN_ZOOM, MAX_ZOOM)
	_clamp_center()
	_changed()


func pan_by(screen_delta: Vector2) -> void:
	center -= screen_delta / zoom
	_clamp_center()
	_changed()


func center_on(p: Vector2, z: float = -1.0) -> void:
	_centered_once = true
	if z > 0.0:
		zoom = clampf(z, MIN_ZOOM, MAX_ZOOM)
	center = p
	_clamp_center()
	_changed()


## Ajusta el zoom para ver todo el mapa.
func fit_all() -> void:
	if service == null or size.x <= 0.0:
		return
	var ms: Vector2 = service.map_size
	zoom = clampf(minf(size.x / ms.x, size.y / ms.y), MIN_ZOOM, MAX_ZOOM)
	center = ms * 0.5
	_changed()


func _clamp_center() -> void:
	if service == null:
		return
	var ms: Vector2 = service.map_size
	center = Vector2(clampf(center.x, 0.0, ms.x), clampf(center.y, 0.0, ms.y))


func _changed() -> void:
	queue_redraw()
	view_changed.emit(center, zoom)


## Enfoca un objetivo (p. ej. «Ver en el mapa» desde Misiones).
func focus_on(p: Vector2, label: String = "", z: float = 1.4) -> void:
	focus_target = p
	focus_label = label
	center_on(p, z)


func clear_focus() -> void:
	focus_target = null
	focus_label = ""
	queue_redraw()


# ==========================================================================
# Marcadores
# ==========================================================================
func visible_markers() -> Array:
	if service == null:
		return []
	var out: Array = []
	if bool(layers.get("quest", true)):
		out.append_array(extra_markers)
	out.append_array(service.get_markers(layers))
	return out


func marker_at(screen_pos: Vector2) -> String:
	var best := ""
	var best_d := PICK_RADIUS
	for m in visible_markers():
		var d := world_to_screen(m["pos"]).distance_to(screen_pos)
		if d <= best_d:
			best_d = d
			best = str(m["id"])
	return best


func select_marker(id: String) -> void:
	selected_marker = id
	queue_redraw()


# ==========================================================================
# Input
# ==========================================================================
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					zoom_at(WHEEL_STEP, mb.position)
					accept_event()
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					zoom_at(1.0 / WHEEL_STEP, mb.position)
					accept_event()
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE:
				if mb.pressed:
					_dragging = true
					_moved = false
					_press_pos = mb.position
				else:
					if _dragging and not _moved and mb.button_index == MOUSE_BUTTON_LEFT:
						var id := marker_at(mb.position)
						if id != "":
							select_marker(id)
							marker_clicked.emit(id)
					_dragging = false
				accept_event()
			MOUSE_BUTTON_RIGHT:
				if mb.pressed:
					destination_requested.emit(screen_to_world(mb.position))
					accept_event()
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		if _moved or mm.position.distance_to(_press_pos) > DRAG_THRESHOLD:
			_moved = true
			pan_by(mm.relative)
		accept_event()
	elif event is InputEventPanGesture:
		pan_by(-(event as InputEventPanGesture).delta * 20.0)
	elif event is InputEventMagnifyGesture:
		zoom_at((event as InputEventMagnifyGesture).factor, (event as InputEventMagnifyGesture).position)


# ==========================================================================
# Dibujo
# ==========================================================================
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#070b0d"))
	if service == null:
		return
	var font := T.font("bold")
	var font_m := T.font("semibold")
	var ms: Vector2 = service.map_size
	# --- Capa en coordenadas de mapa (transformada) ---------------------------
	var origin := size * 0.5 - center * zoom
	draw_set_transform(origin, 0.0, Vector2(zoom, zoom))
	draw_rect(Rect2(Vector2.ZERO, ms), Color("#0b1114"))
	var regions: Array = service.get_regions_view()
	for r in regions:
		var rect: Rect2 = r["rect"]
		if r["explored"]:
			if _bg:
				var ts := Vector2(_bg.get_size())
				var src := Rect2(rect.position / ms * ts, rect.size / ms * ts)
				draw_texture_rect_region(_bg, rect, src, (r["color"] as Color).lightened(0.18))
			else:
				draw_rect(rect, r["color"])
	# Niebla de guerra sobre lo no explorado.
	for r in regions:
		if not r["explored"]:
			var rect2: Rect2 = r["rect"]
			draw_rect(rect2, Color(0.035, 0.05, 0.06, 0.96))
			draw_rect(rect2, Color(r["color"], 0.10))
			_dashed_rect(rect2, Color(1, 1, 1, 0.10), 2.0 / zoom)
	for r in regions:
		if r["explored"]:
			draw_rect(r["rect"], Color(1, 1, 1, 0.07), false, 1.5 / zoom)
	# Ruta planificada (discontinua).
	if route_points.size() >= 2:
		for i in route_points.size() - 1:
			_dashed_line(route_points[i], route_points[i + 1], T.ACCENT_DEFAULT, 3.0 / zoom, 10.0 / zoom)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# --- Capa en pantalla (textos y marcadores a tamaño fijo) -----------------
	for r in regions:
		var rr: Rect2 = r["rect"]
		var c := world_to_screen(rr.get_center())
		if r["explored"]:
			if zoom >= 0.45:
				_text_center(font, str(r["display_name"]).to_upper(), world_to_screen(rr.position + Vector2(rr.size.x * 0.5, 22)), 11, Color(1, 1, 1, 0.55))
		else:
			_text_center(font, "???", c + Vector2(0, 8), int(clampf(26.0 * zoom + 8.0, 14, 40)), Color(1, 1, 1, 0.30))
			if zoom >= 0.5:
				_text_center(font_m, "Zona sin explorar", c + Vector2(0, 30), 11, Color(1, 1, 1, 0.28))
	for l in service.get_labels():
		if zoom >= 0.55:
			_text_center(font, l["text"], world_to_screen(l["pos"]), 12, Color(1, 1, 1, 0.75))
	for m in visible_markers():
		_draw_marker(m, font_m)
	if player_pos is Vector2:
		var pp := world_to_screen(player_pos)
		var tri := PackedVector2Array([pp + Vector2(0, -10), pp + Vector2(7, 8), pp + Vector2(0, 4), pp + Vector2(-7, 8)])
		draw_colored_polygon(tri, Color.WHITE)
	if focus_target is Vector2:
		var fp := world_to_screen(focus_target)
		var pulse := 0.5 + 0.5 * sin(_time * 4.0)
		draw_arc(fp, 16.0 + pulse * 6.0, 0, TAU, 40, Color(T.GOLD, 0.9 - pulse * 0.4), 2.5, true)
		draw_circle(fp, 7.0, T.GOLD)
		draw_arc(fp, 7.0, 0, TAU, 24, Color("#1a1205"), 2.0, true)
		if focus_label != "":
			_text_pill(font_m, focus_label, fp + Vector2(0, -32), T.GOLD)


func _draw_marker(m: Dictionary, font: Font) -> void:
	var p := world_to_screen(m["pos"])
	if p.x < -40 or p.y < -40 or p.x > size.x + 40 or p.y > size.y + 40:
		return
	var kind := str(m["kind"])
	var col: Color = KIND_COLORS.get(kind, Color.WHITE)
	var sel: bool = m["id"] == selected_marker
	var dark := Color("#0b1114")
	match kind:
		"boss":
			var d := PackedVector2Array([p + Vector2(0, -11), p + Vector2(11, 0), p + Vector2(0, 11), p + Vector2(-11, 0)])
			draw_colored_polygon(d, col)
			draw_polyline(d + PackedVector2Array([d[0]]), dark, 2.0, true)
			draw_circle(p, 3.0, dark)
		"shelter":
			var house := PackedVector2Array([p + Vector2(-9, -1), p + Vector2(0, -10), p + Vector2(9, -1), p + Vector2(9, 9), p + Vector2(-9, 9)])
			draw_colored_polygon(house, col)
			draw_rect(Rect2(p + Vector2(-2.5, 2), Vector2(5, 7)), dark)
		"secret":
			var star := PackedVector2Array()
			for i in 10:
				var a := -PI * 0.5 + i * PI / 5.0
				star.append(p + Vector2(cos(a), sin(a)) * (10.0 if i % 2 == 0 else 4.5))
			draw_colored_polygon(star, col)
		"portal":
			draw_arc(p, 9.0, 0, TAU, 28, col, 3.0, true)
			draw_circle(p, 4.0, Color(col, 0.5))
		"dungeon":
			draw_rect(Rect2(p - Vector2(8, 8), Vector2(16, 16)), col)
			draw_rect(Rect2(p - Vector2(3, 1), Vector2(6, 9)), dark)
		"npc":
			draw_circle(p, 9.0, col)
			draw_circle(p, 9.0, dark, false, 2.0, true)
			_text_center(T.font("bold"), "!", p + Vector2(0, 5), 13, dark)
		_:
			draw_circle(p, 6.5, col)
			draw_circle(p, 6.5, dark, false, 2.0, true)
	if sel:
		draw_arc(p, 15.0, 0, TAU, 32, Color.WHITE, 2.0, true)
	if zoom >= 0.75 or sel or kind in ["boss", "shelter"] or (kind == "secret" and zoom >= 0.9):
		_text_shadowed(font, str(m["name"]), p + Vector2(14, 5), 12, Color(col.lightened(0.35), 1.0))


func _text_center(font: Font, text: String, pos: Vector2, fs: int, color: Color) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, pos - Vector2(w * 0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)


func _text_shadowed(font: Font, text: String, pos: Vector2, fs: int, color: Color) -> void:
	draw_string(font, pos + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.8))
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)


func _text_pill(font: Font, text: String, pos: Vector2, color: Color) -> void:
	var fs := 12
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var rect := Rect2(pos - Vector2(w * 0.5 + 10, 14), Vector2(w + 20, 22))
	draw_style_box(T.box(Color(0.03, 0.05, 0.06, 0.92), 8, 1, Color(color, 0.8)), rect)
	draw_string(font, Vector2(rect.position.x + 10, rect.position.y + 15), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)


func _dashed_line(a: Vector2, b: Vector2, color: Color, width: float, dash: float) -> void:
	var length := a.distance_to(b)
	if length <= 0.0:
		return
	var dir := (b - a) / length
	var t := 0.0
	while t < length:
		var e := minf(t + dash, length)
		draw_line(a + dir * t, a + dir * e, color, width, true)
		t += dash * 1.8


func _dashed_rect(r: Rect2, color: Color, width: float) -> void:
	var d := 12.0 / zoom
	_dashed_line(r.position, r.position + Vector2(r.size.x, 0), color, width, d)
	_dashed_line(r.position + Vector2(r.size.x, 0), r.end, color, width, d)
	_dashed_line(r.end, r.position + Vector2(0, r.size.y), color, width, d)
	_dashed_line(r.position + Vector2(0, r.size.y), r.position, color, width, d)
