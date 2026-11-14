extends Control
## Corte lateral de «El Nido» (MMO-Refugio.html / MMO-Construir.html): la isla vista
## de lado. Arriba la superficie (huerto, nido de Pispa, escalera al patio y
## puerta-portal); debajo, los pisos de roca con sus cuartos. Mismo diseño en PC
## (horizontal) y en el refugio de bolsillo (`compact = true`).
##
## También define los controles dibujados que usa ShelterWindow: Dot, LegendSwatch,
## FillBar, Pips, Avatar, ChibiRow (arrastrable), MothPortrait (Pispa), BagGrid y
## ChainView (esquema de Producción).

const T = preload("res://ui/tokens/hud_tokens.gd")

signal cell_clicked(floor_idx: int, col: int)
signal character_dropped(char_id: String, floor_idx: int, col: int)

var service: Node = null
var build_mode := false
var selected_cell := Vector2i(-1, -1)
var placing_type: String = ""
var selected_char: String = ""
var compact := false
var animate := true

var _t := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	custom_minimum_size = Vector2(320, 260)


func _process(delta: float) -> void:
	if animate and is_visible_in_tree():
		_t += delta
		queue_redraw()


# --------------------------------------------------------------------------
# Geometría
# --------------------------------------------------------------------------
func _label_w() -> float:
	return 0.0 if compact else 46.0


func _gap() -> float:
	return 3.0 if compact else 6.0


func get_body_rect() -> Rect2:
	var pad := 8.0 if compact else 14.0
	var sky := size.y * (0.30 if compact else 0.24)
	var x := pad + _label_w()
	return Rect2(x, sky + 4.0, size.x - x - pad, size.y - sky - (14.0 if compact else 22.0))


func _row_h() -> float:
	var n: int = maxi(1, service.get_floor_count()) if service else 1
	return (get_body_rect().size.y - (n + 1) * _gap()) / n


func _col_w() -> float:
	var cols: int = service.cols if service else 6
	return (get_body_rect().size.x - (cols + 1) * _gap()) / cols


func get_cell_rect(f: int, c: int, span: int = 1) -> Rect2:
	var b := get_body_rect()
	var g := _gap()
	var cw := _col_w()
	return Rect2(b.position.x + g + c * (cw + g), b.position.y + g + f * (_row_h() + g), cw * span + g * (span - 1), _row_h())


func cell_at_point(p: Vector2) -> Vector2i:
	if service == null:
		return Vector2i(-1, -1)
	for f in service.get_floor_count():
		for c in service.cols:
			if get_cell_rect(f, c).has_point(p):
				return Vector2i(f, c)
	return Vector2i(-1, -1)


## Rect de la sala completa (doble = 2 celdas) que ocupa una celda.
func get_room_rect_at(f: int, c: int) -> Rect2:
	var r: Dictionary = service.get_room_at(f, c)
	if r.is_empty():
		return get_cell_rect(f, c)
	return get_cell_rect(int(r["floor"]), int(r["col"]), int(r["size"]))


# --------------------------------------------------------------------------
# Entrada: clic y arrastrar habitantes
# --------------------------------------------------------------------------
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var cell := cell_at_point(event.position)
		if cell.x >= 0:
			cell_clicked.emit(cell.x, cell.y)
			accept_event()


func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if not (data is Dictionary) or not data.has("char_id"):
		return false
	var cell := cell_at_point(at_position)
	return cell.x >= 0 and not service.get_room_at(cell.x, cell.y).is_empty()


func _drop_data(at_position: Vector2, data: Variant) -> void:
	var cell := cell_at_point(at_position)
	if cell.x >= 0:
		character_dropped.emit(str(data["char_id"]), cell.x, cell.y)


# --------------------------------------------------------------------------
# Dibujo
# --------------------------------------------------------------------------
func _draw() -> void:
	if service == null:
		return
	var w := size.x
	var h := size.y
	draw_rect(Rect2(Vector2.ZERO, size), T.SHELTER_SKY)
	# Estrellas deterministas.
	var seed_rng := RandomNumberGenerator.new()
	seed_rng.seed = 42
	for i in (12 if compact else 26):
		var p := Vector2(seed_rng.randf() * w, seed_rng.randf() * get_body_rect().position.y * 0.8)
		draw_circle(p, 1.0, T.SHELTER_STAR)
	_draw_island()
	_draw_surface()
	if not compact:
		for f in service.get_floor_count():
			var r := get_cell_rect(f, 0)
			_text(Vector2(4, r.position.y + 16), service.get_floor_name(f), 10, T.TEXT_MUTED, "semibold", _label_w() - 4)
	var drawn := {}
	for f in service.get_floor_count():
		for c in service.cols:
			var v: Dictionary = service.get_cell_view(f, c)
			if v["state"] == "room":
				if drawn.has(v["room"]):
					continue
				drawn[v["room"]] = true
				_draw_room(service.get_room(v["room"]))
			else:
				_draw_cell(v)
	if build_mode and placing_type != "" and selected_cell.x >= 0:
		_draw_preview()
	elif selected_cell.x >= 0 and not compact:
		var rr := get_room_rect_at(selected_cell.x, selected_cell.y)
		_rounded(rr, Color.TRANSPARENT, 10, 2, T.ACCENT_DEFAULT)


func _draw_island() -> void:
	var b := get_body_rect()
	var r := b.grow(4.0)
	var sb := T.box(T.SHELTER_ISLAND, 14, 2, T.SHELTER_ISLAND_EDGE)
	draw_style_box(sb, r)
	# Cola de roca de la isla flotante.
	var mid := r.position.x + r.size.x * 0.5
	var tail := PackedVector2Array([
		Vector2(r.position.x + r.size.x * 0.12, r.end.y - 2), Vector2(r.end.x - r.size.x * 0.12, r.end.y - 2),
		Vector2(mid + r.size.x * 0.10, r.end.y + (8.0 if compact else 14.0)), Vector2(mid - r.size.x * 0.10, r.end.y + (8.0 if compact else 14.0)),
	])
	draw_colored_polygon(tail, T.SHELTER_ISLAND_EDGE.darkened(0.35))


func _draw_surface() -> void:
	var b := get_body_rect()
	var gy := b.position.y - 4.0
	var x0 := b.position.x - 10.0
	var x1 := b.end.x + 10.0
	draw_rect(Rect2(x0, gy - 4, x1 - x0, 6), T.SHELTER_GRASS)
	var span := x1 - x0
	var fs := 9 if compact else 11
	# Huerto de azotea: brotes.
	var plots: Array = service.surface.get("plots", [])
	if not plots.is_empty():
		var p: Dictionary = plots[0]
		var px := x0 + span * 0.06
		var n := 5 if compact else 8
		var ready := float(p.get("progress_hours", 0.0)) >= float(p.get("grow_hours", 1.0))
		for i in n:
			var sx := px + i * (7.0 if compact else 12.0)
			var grow := clampf(float(p.get("progress_hours", 0.0)) / maxf(0.01, float(p.get("grow_hours", 1.0))), 0.25, 1.0)
			var hh := (8.0 if compact else 14.0) * grow
			draw_rect(Rect2(sx, gy - 4 - hh, 4.0 if not compact else 3.0, hh), T.HEALTH.darkened(0.1 if ready else 0.4))
		var lx := px + n * (3.5 if compact else 6.0)
		_text_c(Vector2(lx, gy - (22 if compact else 30)), str(p["name"]), fs, T.TEXT, "bold")
		if ready:
			_pill_c(Vector2(lx, gy - (36 if compact else 50)), "%d listas" % int(p["yield"]), T.ACCENT_DEFAULT, T.SHELTER_PILL_TEXT, fs)
	# Nido de Pispa: árbol.
	var tx := x0 + span * 0.38
	var th := (18.0 if compact else 48.0)
	draw_rect(Rect2(tx - 2, gy - 4 - th, 4, th), Color("#5a4632"))
	var cr := 9.0 if compact else 24.0
	draw_circle(Vector2(tx, gy - 4 - th - cr * 0.4), cr, Color("#1f3d2b"))
	if not compact:
		draw_set_transform(Vector2(tx + 12, gy - 4 - th + 4), 0.0, Vector2(1.0, 0.45))
		draw_circle(Vector2.ZERO, 11, Color("#8a6a42"))
		draw_set_transform_matrix(Transform2D.IDENTITY)
	var trip: Dictionary = service.pispa.get("trip", {})
	var top := gy - 4 - th - cr * 1.5
	_text_c(Vector2(tx, top - 2), "Nido de Pispa", fs, T.TEXT, "bold")
	if not trip.is_empty() and not compact:
		_pill_c(Vector2(tx, top - 26), service.format_hours(maxf(0.0, float(trip["end_h"]) - service.clock_h)), T.SLOT_READY, T.TEXT, fs)
	# Pispa revoloteando.
	var bob := sin(_t * 3.0) * 2.0
	_draw_mini_moth(Vector2(tx + cr + 12, gy - th * 0.6 + bob), 0.6 if compact else 1.0)
	# Escalera al patio.
	var sx2 := x0 + span * 0.60
	var bw := 22.0 if compact else 36.0
	var bh := 22.0 if compact else 36.0
	draw_style_box(T.box(T.SHELTER_SUB_BG, 6, 1, Color(1, 1, 1, 0.18)), Rect2(sx2 - bw * 0.5, gy - 4 - bh, bw, bh))
	draw_rect(Rect2(sx2 - bw * 0.18, gy - 4 - bh * 0.7, bw * 0.36, bh * 0.7), Color("#2fa58a"))
	_text_c(Vector2(sx2, gy - bh - 12), "Escalera al patio", fs, T.TEXT, "bold")
	if not compact:
		_pill_c(Vector2(sx2, gy - bh - 36), "Brisa de visita", Color("#1b2c4a"), Color("#a9c8ff"), fs)
	# Puerta-portal.
	var ptx := x0 + span * 0.88
	var pw := 22.0 if compact else 38.0
	var ph := 30.0 if compact else 52.0
	var base := Vector2(ptx, gy - 4)
	draw_rect(Rect2(base.x - pw * 0.5, base.y - ph + pw * 0.5, pw, ph - pw * 0.5), Color("#1d1430"))
	draw_circle(Vector2(base.x, base.y - ph + pw * 0.5), pw * 0.5, Color("#1d1430"))
	draw_arc(Vector2(base.x, base.y - ph + pw * 0.5), pw * 0.5, PI, TAU, 24, T.SHELTER_PORTAL, 4.0 if not compact else 2.5, true)
	draw_line(Vector2(base.x - pw * 0.5, base.y - ph + pw * 0.5), Vector2(base.x - pw * 0.5, base.y), T.SHELTER_PORTAL, 4.0 if not compact else 2.5)
	draw_line(Vector2(base.x + pw * 0.5, base.y - ph + pw * 0.5), Vector2(base.x + pw * 0.5, base.y), T.SHELTER_PORTAL, 4.0 if not compact else 2.5)
	_text_c(Vector2(ptx, gy - ph - 10), "Puerta-portal", fs, T.TEXT, "bold")
	if not service.get_pending_decisions().is_empty() and not compact:
		_pill_c(Vector2(ptx, gy - ph - 34), "¡Elige!", T.GOLD, T.TEXT_DARK, fs)


func _draw_mini_moth(c: Vector2, s: float) -> void:
	draw_set_transform(c, 0.0, Vector2(s, s))
	draw_circle(Vector2(-5, -1), 5, Color("#f0b04a"))
	draw_circle(Vector2(5, -1), 5, Color("#f0b04a"))
	draw_circle(Vector2(0, 0), 3, Color("#f7e6c4"))
	draw_set_transform_matrix(Transform2D.IDENTITY)


func _room_subtitle(r: Dictionary) -> Array:
	var type: String = r["type"]
	if r["status"] == "building":
		return ["En obra · %s" % service.format_hours(float(r["build_left_h"])), T.ACCENT_DEFAULT]
	for w in service.workshops:
		if w["room_type"] == type:
			var st: Dictionary = service.workshop_status(w["id"])
			var out_item: String = (w["outputs"] as Dictionary).keys()[0]
			var rate := float(st.get("output_rate", 0.0))
			if st["status"] == "jam":
				return ["%s · atascada" % service.item_name(out_item), T.SHELTER_JAM]
			return ["%s · %d /h" % [service.item_name(out_item), int(round(rate))], T.TEXT_SECONDARY]
	match type:
		"despensa", "almacen":
			return ["%d / %d · compartida" % [service.get_storage_used(), service.get_storage_capacity()], T.TEXT_SECONDARY]
		"dormitorio":
			return ["Descanso ×%.1f · XP extra al volver" % (1.0 + service.get_comfort() / 100.0), T.TEXT_SECONDARY]
		"mesa_mapas":
			return ["Expediciones · %d fuera" % service.active_expeditions.size(), T.TEXT_SECONDARY]
	return [str(service.catalog.get(type, {}).get("desc", "")), T.TEXT_SECONDARY]


func _draw_room(r: Dictionary) -> void:
	var rect := get_cell_rect(int(r["floor"]), int(r["col"]), int(r["size"]))
	var e: Dictionary = service.catalog.get(r["type"], {})
	var col := Color(str(e.get("color", "#9aa6ae")))
	var secret := str(r.get("secret_id", "")) != ""
	var jam := false
	for w in service.workshops:
		if w["room_type"] == r["type"] and service.workshop_status(w["id"])["status"] == "jam":
			jam = true
	var bg: Color = T.SHELTER_SECRET_BG if secret else T.SHELTER_ROOM_BG
	if r["status"] == "building":
		_rounded(rect, Color(T.ACCENT_DEFAULT, 0.05), 10, 0, Color.TRANSPARENT)
		_dashed_rect(rect.grow(-1), Color(T.ACCENT_DEFAULT, 0.8))
	else:
		_rounded(rect, bg, 10, 1, T.SHELTER_JAM if jam else (T.SHELTER_SECRET if secret else T.SHELTER_ROOM_EDGE))
	var pad := 6.0 if compact else 10.0
	var fs := 9 if compact else 13
	var sq := 6.0 if compact else 8.0
	draw_style_box(T.box(col, 2), Rect2(rect.position + Vector2(pad, pad + (2 if compact else 4)), Vector2(sq, sq)))
	var title: String = service.room_name(r["uid"])
	if r["type"] == "destilador" and int(r["floor"]) >= 2:
		title = "Sótano: destilería" if not compact else title
	var tx := rect.position.x + pad + sq + 6
	var ty := rect.position.y + pad + fs
	var tw := _text(Vector2(tx, ty), title, fs, T.TEXT, "bold", rect.size.x - (tx - rect.position.x) - pad - 30)
	_text(Vector2(tx + tw + 5, ty), "nv %d" % int(r["level"]), fs - 3, T.TEXT_MUTED, "medium", 40)
	if not compact:
		var sub := _room_subtitle(r)
		_text(Vector2(rect.position.x + pad, ty + 18), sub[0], 11, sub[1], "medium", rect.size.x - pad * 2)
		if int(r["size"]) > 1:
			_text(Vector2(rect.position.x + pad, ty + 34), "Sala doble · +25 %", 10, T.ACCENT_DEFAULT, "semibold", rect.size.x - pad * 2)
	# Chibis trabajando.
	var workers: Array = r["workers"]
	for i in workers.size():
		var ch: Dictionary = service.get_character(workers[i])
		var cs := 0.65 if compact else 1.0
		var cx := rect.end.x - pad - 8 * cs - i * 20 * cs
		var bob := absf(sin(_t * 4.0 + i * 1.7)) * 2.0 * cs
		_draw_chibi(Vector2(cx, rect.end.y - 4 - bob), Color(str(ch.get("color", "#9aa6ae"))), cs, selected_char == ch.get("id", ""))
	# Burbujas.
	var ready: int = service.get_ready_count(r["uid"])
	if ready > 0:
		_pill_c(Vector2(rect.end.x - (22 if compact else 34), rect.end.y + (1 if compact else 2)), "%d listas" % ready, T.ACCENT_DEFAULT, T.SHELTER_PILL_TEXT, 8 if compact else 10)
	if float(r["upgrade_left_h"]) > 0.0 and not compact:
		_pill_c(Vector2(rect.position.x + rect.size.x * 0.5, rect.position.y - 7), "▲ mejorando", T.GOLD, T.TEXT_DARK, 10)


func _draw_chibi(feet: Vector2, col: Color, s: float, highlight: bool) -> void:
	var body := Rect2(feet.x - 5 * s, feet.y - 11 * s, 10 * s, 11 * s)
	draw_style_box(T.box(col.darkened(0.25), int(3 * s)), body)
	var head := Vector2(feet.x, feet.y - 17 * s)
	draw_circle(head, 6.5 * s, Color("#f1c79b"), true, -1.0, true)
	draw_arc(head, 6.5 * s, PI * 1.05, TAU * 0.98, 12, col, 4.0 * s, true)
	draw_circle(head + Vector2(-2.2, 0.5) * s, 0.9 * s, T.TEXT_DARK)
	draw_circle(head + Vector2(2.2, 0.5) * s, 0.9 * s, T.TEXT_DARK)
	if highlight:
		draw_arc(feet + Vector2(0, -10 * s), 13 * s, 0, TAU, 20, T.ACCENT_DEFAULT, 1.5, true)


func _draw_cell(v: Dictionary) -> void:
	var rect := get_cell_rect(int(v["floor"]), int(v["col"]))
	var pad := 6.0 if compact else 10.0
	var fs := 9 if compact else 12
	match str(v["state"]):
		"rock":
			_rounded(rect, T.SHELTER_ROCK, 10, 0, Color.TRANSPARENT)
			var step := 10.0 if compact else 14.0
			var x := rect.position.x + 4
			while x < rect.end.x - 6:
				var y := rect.position.y + 6 + fmod(x * 0.7, step)
				while y < rect.end.y - 6:
					draw_line(Vector2(x, y), Vector2(x + 4, y - 3), T.SHELTER_ROCK_LINE, 1.0)
					y += step
				x += step
			if not compact:
				_text(rect.position + Vector2(pad, pad + fs), "Roca", fs, T.TEXT_MUTED, "semibold", rect.size.x - pad * 2)
				_text(rect.position + Vector2(pad, pad + fs + 16), "Excavar · %s" % service.format_cost(service.get_dig_cost(int(v["floor"]))), 10, T.TEXT_MUTED, "medium", rect.size.x - pad * 2)
		"empty":
			_rounded(rect, Color(0, 0, 0, 0.15), 10, 0, Color.TRANSPARENT)
			_dashed_rect(rect.grow(-1), Color(T.ACCENT_DEFAULT, 0.55) if build_mode else Color(1, 1, 1, 0.2))
			if not compact:
				_text_c(Vector2(rect.get_center().x, rect.get_center().y - 2), "+ Amueblar", fs, T.TEXT_KEY, "semibold")
				_text_c(Vector2(rect.get_center().x, rect.get_center().y + 14), "Cuarto vacío", 10, T.TEXT_MUTED, "medium")
		"secret":
			_rounded(rect, T.SHELTER_SECRET_BG, 10, 1, Color(T.SHELTER_SECRET, 0.7))
			draw_style_box(T.box(T.SHELTER_SECRET, 2), Rect2(rect.position + Vector2(pad, pad + 3), Vector2(7, 7)))
			_text(rect.position + Vector2(pad + 13, pad + fs), str(v.get("title", "???")), fs + 1, T.SHELTER_SECRET, "bold", rect.size.x - pad * 2)
			if not compact:
				_wrap(Rect2(rect.position + Vector2(pad, pad + fs + 8), rect.size - Vector2(pad * 2, pad + fs + 8)), str(v.get("hint", "")), 10, T.TEXT_KEY)
		"locked":
			_rounded(rect, T.SHELTER_LOCKED_BG, 10, 1, Color(1, 1, 1, 0.04))
			if not compact:
				draw_style_box(T.box(Color(1, 1, 1, 0.12), 2), Rect2(rect.position + Vector2(pad, pad + 3), Vector2(7, 7)))
				_text(rect.position + Vector2(pad + 13, pad + fs), "Cimientos", fs, Color(T.TEXT_MUTED, 0.7), "semibold", rect.size.x - pad * 2)
				_wrap(Rect2(rect.position + Vector2(pad, pad + fs + 8), rect.size - Vector2(pad * 2, pad + fs + 8)), str(v.get("hint", "")), 10, Color(T.TEXT_MUTED, 0.6))


func _draw_preview() -> void:
	var f := selected_cell.x
	var c := selected_cell.y
	var pv: Dictionary = service.preview_placement(placing_type, f, c)
	var is_decor: bool = service.decorations_catalog.has(placing_type)
	var rect := get_room_rect_at(f, c) if is_decor else get_cell_rect(f, c)
	var ok := bool(pv["fits"])
	var edge: Color = T.SHELTER_BUILD_OK if ok else T.SHELTER_BUILD_BAD
	if not is_decor:
		_rounded(rect, T.SHELTER_ROOM_BG, 10, 0, Color.TRANSPARENT)
		_rounded(rect, T.SHELTER_BUILD_BG if ok else Color(T.SHELTER_BUILD_BAD, 0.10), 10, 2, edge)
		var e: Dictionary = service.catalog.get(placing_type, {})
		var pad := 10.0
		draw_style_box(T.box(Color(str(e.get("color", "#46e3c1"))), 2), Rect2(rect.position + Vector2(pad, pad + 4), Vector2(8, 8)))
		_text(rect.position + Vector2(pad + 14, pad + 13), str(e.get("name", placing_type)), 13, T.TEXT, "bold", rect.size.x - pad * 2 - 14)
		var lines := PackedStringArray()
		for s in pv.get("sources", []):
			lines.append("+%d %% junto a %s" % [int(s["pct"]), s["name"]])
		if bool(pv.get("merge", false)):
			lines.append("Se fusiona: sala doble")
		if lines.is_empty():
			lines.append("Sin vecinos afines")
		_wrap(Rect2(rect.position + Vector2(pad, pad + 22), rect.size - Vector2(pad * 2, pad + 22)), " · ".join(lines), 11, T.ACCENT_DEFAULT if ok else T.SHELTER_BUILD_BAD)
	else:
		_rounded(rect, Color.TRANSPARENT, 10, 2, edge)
	_pill_c(Vector2(rect.end.x - 30, rect.position.y - 4), "Cabe ✓" if ok else "No cabe", edge, T.SHELTER_PILL_TEXT if ok else T.TEXT, 10)


# --------------------------------------------------------------------------
# Primitivas
# --------------------------------------------------------------------------
func _rounded(rect: Rect2, bg: Color, radius: int, border: int, border_col: Color) -> void:
	draw_style_box(T.box(bg, radius if not compact else maxi(4, radius / 2), border, border_col), rect)


func _dashed_rect(rect: Rect2, col: Color) -> void:
	var pts := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y), rect.position]
	for i in 4:
		draw_dashed_line(pts[i], pts[i + 1], col, 1.5, 5.0, true, true)


func _fit(text: String, font: Font, fs: int, max_w: float) -> String:
	if max_w <= 0.0 or font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= max_w:
		return text
	var t := text
	while t.length() > 1 and font.get_string_size(t + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > max_w:
		t = t.substr(0, t.length() - 1)
	return t + "…"


## Texto en `pos` (línea base). Devuelve el ancho dibujado.
func _text(pos: Vector2, text: String, fs: int, col: Color, weight: String = "medium", max_w: float = -1.0) -> float:
	var font := T.font(weight)
	var t := _fit(text, font, fs, max_w)
	draw_string(font, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	return font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x


func _text_c(center_base: Vector2, text: String, fs: int, col: Color, weight: String = "medium") -> void:
	var font := T.font(weight)
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, Vector2(center_base.x - w * 0.5, center_base.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _pill_c(center: Vector2, text: String, bg: Color, fg: Color, fs: int = 10) -> void:
	var font := T.font("bold")
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var r := Rect2(center.x - tw * 0.5 - 7, center.y - fs * 0.5 - 4, tw + 14, fs + 8)
	draw_style_box(T.box(bg, int(r.size.y * 0.5)), r)
	draw_string(font, Vector2(r.position.x + 7, r.position.y + fs + 2), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, fg)


func _wrap(rect: Rect2, text: String, fs: int, col: Color) -> void:
	var font := T.font("medium")
	var words := text.split(" ")
	var line := ""
	var y := rect.position.y + fs
	for wd in words:
		var cand := wd if line == "" else line + " " + wd
		if font.get_string_size(cand, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > rect.size.x and line != "":
			draw_string(font, Vector2(rect.position.x, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
			y += fs + 4
			line = wd
			if y > rect.end.y:
				return
		else:
			line = cand
	if line != "" and y <= rect.end.y + fs:
		draw_string(font, Vector2(rect.position.x, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


# ==========================================================================
# Controles auxiliares
# ==========================================================================
## Punto / rombo / cuadrado de color.
class Dot extends Control:
	const TK = preload("res://ui/tokens/hud_tokens.gd")
	var color: Color = Color.WHITE:
		set(v):
			color = v
			queue_redraw()
	var diamond := false
	var square := false
	var outline := false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var s := minf(size.x, size.y)
		var c := size * 0.5
		if diamond:
			var r := s * 0.5
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)]), color)
		elif square:
			var rect := Rect2(c - Vector2(s, s) * 0.5, Vector2(s, s))
			if outline:
				draw_style_box(TK.box(Color(color, 0.08), int(s * 0.25), 2, color), rect)
			else:
				draw_style_box(TK.box(color, int(s * 0.25)), rect)
		else:
			draw_circle(c, s * 0.42, color, true, -1.0, true)


class LegendSwatch extends Control:
	const TK = preload("res://ui/tokens/hud_tokens.gd")
	var color: Color = Color.WHITE
	var dashed := false

	func _draw() -> void:
		var y := size.y * 0.5
		if dashed:
			draw_dashed_line(Vector2(0, y), Vector2(size.x, y), color, 2.0, 4.0, true, true)
		else:
			draw_line(Vector2(0, y), Vector2(size.x, y), color, 2.0, true)


class FillBar extends Control:
	const TK = preload("res://ui/tokens/hud_tokens.gd")
	var color: Color = Color("#46e3c1")
	var value := 0.0:
		set(v):
			value = clampf(v, 0.0, 1.0)
			queue_redraw()

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var r := int(size.y * 0.5)
		draw_style_box(TK.box(TK.WELL, r), Rect2(Vector2.ZERO, size))
		if value > 0.0:
			draw_style_box(TK.box(color, r), Rect2(Vector2.ZERO, Vector2(maxf(size.y, size.x * value), size.y)))


## Cariño de Pispa: 5 cápsulas.
class Pips extends Control:
	const TK = preload("res://ui/tokens/hud_tokens.gd")
	var value := 0
	var count := 5
	var color: Color = Color("#ff8fb8")

	func _draw() -> void:
		var gap := 4.0
		var w := (size.x - gap * (count - 1)) / count
		for i in count:
			var r := Rect2(i * (w + gap), size.y * 0.25, w, size.y * 0.5)
			draw_style_box(TK.box(color if i < value else Color(1, 1, 1, 0.12), int(r.size.y * 0.5)), r)


class Avatar extends Control:
	const TK = preload("res://ui/tokens/hud_tokens.gd")
	var color: Color = Color.WHITE
	var letter := "?"

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var s := minf(size.x, size.y)
		draw_circle(size * 0.5, s * 0.5, color, true, -1.0, true)
		var font := TK.font("bold")
		var fs := int(s * 0.45)
		var tw := font.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, Vector2(size.x * 0.5 - tw * 0.5, size.y * 0.5 + fs * 0.36), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, TK.TEXT_DARK)


## Fila de habitante: se puede arrastrar a un cuarto del corte lateral.
class ChibiRow extends Button:
	const TK = preload("res://ui/tokens/hud_tokens.gd")
	var char_id := ""

	func _get_drag_data(_at_position: Vector2) -> Variant:
		var l := Label.new()
		l.text = text if text != "" else char_id
		set_drag_preview(l)
		return {"char_id": char_id}


## Retrato de Pispa (polilla de las grietas).
class MothPortrait extends Control:
	const TK = preload("res://ui/tokens/hud_tokens.gd")
	var t := 0.0

	func _process(delta: float) -> void:
		if is_visible_in_tree():
			t += delta
			queue_redraw()

	func _draw() -> void:
		var c := size * 0.5 + Vector2(0, sin(t * 2.0) * 3.0 - 6)
		var s := minf(size.x, size.y) / 150.0
		draw_set_transform(c + Vector2(0, 58 * s - sin(t * 2.0) * 3.0), 0.0, Vector2(1.0, 0.18))
		draw_circle(Vector2.ZERO, 48 * s, Color(0, 0, 0, 0.35))
		draw_set_transform_matrix(Transform2D.IDENTITY)
		var flap := 1.0 + sin(t * 6.0) * 0.06
		for side in [-1.0, 1.0]:
			draw_set_transform(c + Vector2(side * 36 * s, -8 * s), side * 0.35, Vector2(flap, 0.8))
			draw_circle(Vector2.ZERO, 36 * s, Color("#f0b04a"))
			draw_set_transform_matrix(Transform2D.IDENTITY)
			draw_set_transform(c + Vector2(side * 30 * s, 22 * s), -side * 0.4, Vector2(flap, 0.7))
			draw_circle(Vector2.ZERO, 24 * s, Color("#e8893a"))
			draw_set_transform_matrix(Transform2D.IDENTITY)
			draw_circle(c + Vector2(side * 40 * s, -6 * s), 8 * s, Color("#7fd6b5"))
			draw_line(c + Vector2(side * 6 * s, -40 * s), c + Vector2(side * 20 * s, -66 * s), Color("#3a2a1e"), 2.0 * s, true)
			draw_circle(c + Vector2(side * 20 * s, -66 * s), 5 * s, Color("#46e3c1"))
		draw_set_transform(c, 0.0, Vector2(0.62, 1.0))
		draw_circle(Vector2(0, 0), 30 * s, Color("#f7e6c4"))
		draw_set_transform_matrix(Transform2D.IDENTITY)
		draw_circle(c + Vector2(-8, -12) * s, 4.5 * s, Color("#1a1410"))
		draw_circle(c + Vector2(8, -12) * s, 4.5 * s, Color("#1a1410"))
		draw_circle(c + Vector2(-7, -13.5) * s, 1.4 * s, Color.WHITE)
		draw_circle(c + Vector2(9, -13.5) * s, 1.4 * s, Color.WHITE)
		draw_style_box(TK.box(Color("#8a5a32"), int(4 * s), 1, Color("#5a3a20")), Rect2(c + Vector2(-17, 12) * s, Vector2(34, 18) * s))


## Bolsa de Pispa: rejilla de huecos (10 por fila) con cantidad.
class BagGrid extends Control:
	const TK = preload("res://ui/tokens/hud_tokens.gd")
	var service: Node = null
	const PER_ROW := 10

	func _draw() -> void:
		if service == null:
			return
		var cap: int = service.pispa_bag_capacity()
		var bag: Array = service.pispa.get("bag", [])
		var rows := int(ceil(cap / float(PER_ROW)))
		var gap := 6.0
		var cell := minf((size.x - gap * (PER_ROW - 1)) / PER_ROW, (size.y - gap * (rows - 1)) / maxf(1.0, rows))
		var font := TK.font("bold")
		for i in cap:
			var r := Rect2((i % PER_ROW) * (cell + gap), (i / PER_ROW) * (cell + gap), cell, cell)
			if i < bag.size():
				var col: Color = service.item_color(bag[i]["item"])
				draw_style_box(TK.box(TK.SHELTER_SUB_BG, 7, 1, Color(col, 0.75)), r)
				var q := str(int(bag[i]["qty"]))
				var tw := font.get_string_size(q, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
				draw_string(font, r.end - Vector2(tw + 5, 5), q, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, TK.TEXT)
				draw_circle(r.position + Vector2(cell * 0.38, cell * 0.38), cell * 0.14, Color(col, 0.85))
			else:
				draw_style_box(TK.box(TK.WELL, 7, 1, Color(1, 1, 1, 0.04)), r)


## Esquema de Producción: materias → talleres → productos → destino.
class ChainView extends Control:
	const TK = preload("res://ui/tokens/hud_tokens.gd")
	var service: Node = null
	const HEADERS := ["MATERIAS PRIMAS", "TALLERES", "PRODUCTOS", "DESTINO"]
	var node_rects: Dictionary = {}

	func _draw() -> void:
		if service == null:
			return
		var g: Dictionary = service.get_production_graph()
		var col_w := size.x / 4.0
		var node_w := minf(col_w * 0.78, 230.0)
		var top := 26.0
		var rows := maxi(5, (g["raw"] as Array).size())
		var pitch := minf(78.0, (size.y - top) / rows)
		var node_h := minf(52.0, pitch - 12.0)
		var font := TK.font("bold")
		for i in 4:
			draw_string(_caps_font(), Vector2(i * col_w + 8, 12), HEADERS[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, TK.TEXT_SECONDARY)
		node_rects.clear()
		var row_y := {}
		var raw: Array = g["raw"]
		for i in raw.size():
			row_y["raw:" + str(raw[i]["id"])] = float(i)
		for w in service.workshops:
			var acc := 0.0
			var n := 0
			for it in w["inputs"]:
				acc += float(row_y.get("raw:" + it, 0.0))
				n += 1
			row_y["shop:" + str(w["id"])] = acc / maxf(1.0, n)
			for it in w["outputs"]:
				row_y["prod:" + it] = row_y["shop:" + str(w["id"])]
		var last := -10.0
		for d in g["destinations"]:
			var acc2 := 0.0
			var n2 := 0
			for it in service.destinations.filter(func(x) -> bool: return x["id"] == d["id"])[0].get("demand", {}):
				acc2 += float(row_y.get("prod:" + it, 0.0))
				n2 += 1
			var y := maxf(acc2 / maxf(1.0, n2), last + 1.0)
			row_y["dest:" + str(d["id"])] = y
			last = y
		var groups := [["raw", g["raw"]], ["shop", g["workshops"]], ["prod", g["products"]], ["dest", g["destinations"]]]
		for gi in groups.size():
			for nd in groups[gi][1]:
				var key: String = groups[gi][0] + ":" + str(nd["id"])
				var y2 := top + float(row_y.get(key, 0.0)) * pitch
				node_rects[key] = Rect2(gi * col_w + 8, y2, node_w, node_h)
		# Aristas primero.
		for e in g["edges"]:
			if not node_rects.has(e["from"]) or not node_rects.has(e["to"]):
				continue
			var a: Rect2 = node_rects[e["from"]]
			var b: Rect2 = node_rects[e["to"]]
			var p0 := Vector2(a.end.x, a.get_center().y)
			var p3 := Vector2(b.position.x, b.get_center().y)
			var dx := (p3.x - p0.x) * 0.5
			var pts := PackedVector2Array()
			for k in 25:
				var t := k / 24.0
				pts.append(p0.bezier_interpolate(p0 + Vector2(dx, 0), p3 - Vector2(dx, 0), p3, t))
			match str(e["status"]):
				"jam":
					draw_polyline(pts, TK.SHELTER_JAM, 2.0, true)
				"building":
					for k in range(0, pts.size() - 1, 2):
						draw_line(pts[k], pts[k + 1], TK.ACCENT_DEFAULT, 2.0, true)
				_:
					draw_polyline(pts, TK.SHELTER_FLOW, 2.0, true)
		# Nodos.
		for gi in groups.size():
			for nd in groups[gi][1]:
				var key2: String = groups[gi][0] + ":" + str(nd["id"])
				var r: Rect2 = node_rects[key2]
				var st := str(nd.get("status", "ok"))
				var bg: Color = TK.SHELTER_SUB_BG
				var edge := Color(1, 1, 1, 0.08)
				var bw := 1
				var detail_col: Color = TK.TEXT_SECONDARY
				if st == "jam":
					bg = TK.SHELTER_JAM_BG
					edge = TK.SHELTER_JAM
					detail_col = TK.SHELTER_JAM
				elif st == "building":
					edge = TK.ACCENT_DEFAULT
					detail_col = TK.ACCENT_DEFAULT
				if bool(nd.get("highlight", false)):
					edge = TK.ACCENT_DEFAULT
					detail_col = TK.ACCENT_DEFAULT
				draw_style_box(TK.box(bg, 10, bw, edge), r)
				var dcol: Color = nd.get("color", TK.GOLD) if nd.has("color") else (TK.GOLD if nd.get("kind", "") != "upgrade" else TK.TEXT_KEY)
				if st == "jam":
					dcol = TK.SHELTER_JAM
				var c := Vector2(r.position.x + 16, r.get_center().y)
				draw_colored_polygon(PackedVector2Array([c + Vector2(0, -5), c + Vector2(5, 0), c + Vector2(0, 5), c + Vector2(-5, 0)]), dcol)
				draw_string(font, Vector2(r.position.x + 30, r.position.y + r.size.y * 0.5 - 2), str(nd["name"]), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 38, 13, TK.TEXT)
				draw_string(TK.font("medium"), Vector2(r.position.x + 30, r.position.y + r.size.y * 0.5 + 14), str(nd["detail"]), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 38, 11, detail_col)

	func _caps_font() -> Font:
		var f := FontVariation.new()
		f.base_font = TK.font("bold")
		f.spacing_glyph = 2
		return f
