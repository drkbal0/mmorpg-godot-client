extends RefCounted
## Piezas del HUD de raid extendido — UI v2.4 Paso 17 · ADR 115 (MMO-Raid.html).
##
## - `MemberCard`: marco de integrante 128×42 (vida, escudo, curación entrante verde traslúcida, daño
##   previsto a 3 s con rayado ámbar a 135°, rombo violeta purificable, cuadrito de rol, textos y
##   borde reactivo rojo / cian / blanco 8 %). Clic izq., clic der. y Shift+clic.
## - `hatch()`: repeating-linear-gradient(135deg, A 0 4px, B 4px 8px) recortado a un rectángulo.
## - `HatchSwatch`, `Diamond`, `Swatch`: muestras de la leyenda.
## - `Meter`: barra redondeada con texto centrado opcional (jefe 43 %, vida y maná del sanador).
## - `Arrow`: flecha direccional SVG (M19 12H5M11 6l-6 6 6 6) con rotación.
## - `alert_box()`: tarjeta de la alerta táctica central.
## - `ConsoleShape`: trapecio grafito inferior (M380 811L420 690H1020L1060 811Z).
## - `AbilitySlot`: ranura 48×48 con velo y cifra de enfriamiento y la tecla abajo a la derecha.
##
## Uso: const RK = preload("res://ui/windows/common/RaidKit.gd")

const T = preload("res://ui/tokens/hud_tokens.gd")
const Kit = preload("res://ui/windows/common/CinematicKit.gd")
const D = preload("res://ui/components/HUDv2/hud_draw.gd")
const SvgPath = preload("res://ui/icons/svg_path.gd")

const TEXT_SHADOW := Color(0, 0, 0, 0.9)


static func label(text: String, font_size: int, color: Color, weight: String = "medium", node_name: String = "") -> Label:
	var l := Kit.shadow(Kit.label(text, font_size, color, weight), 2)
	if node_name != "":
		l.name = node_name
	return l


## Primitivas de dibujo compartidas (accesibles desde las clases internas como `Gfx.…`).
class Gfx:
	const TEXT_SHADOW := Color(0, 0, 0, 0.9)

	## Fondo B + franjas A en «/» (135°) recortadas a `area`. Devuelve el nº de franjas dibujadas.
	static func hatch(canvas: CanvasItem, area: Rect2, a: Color = T.RAID_PREDICTED_A, b: Color = T.RAID_PREDICTED_B, stripe: float = T.RAID_PREDICTED_STRIPE) -> int:
		if area.size.x <= 0.0 or area.size.y <= 0.0:
			return 0
		canvas.draw_rect(area, b)
		var clip := PackedVector2Array([area.position, Vector2(area.end.x, area.position.y), area.end, Vector2(area.position.x, area.end.y)])
		var h := area.size.y
		var w := stripe * sqrt(2.0)          # ancho horizontal de una franja a 45°
		var period := w * 2.0
		var x := area.position.x - fmod(area.position.x, period)
		var n := 0
		while x < area.end.x + h:
			var poly := PackedVector2Array([
				Vector2(x, area.position.y), Vector2(x + w, area.position.y),
				Vector2(x + w - h, area.end.y), Vector2(x - h, area.end.y)])
			for piece in Geometry2D.intersect_polygons(poly, clip):
				if piece.size() >= 3:
					canvas.draw_colored_polygon(piece, a)
					n += 1
			x += period
		return n


	static func diamond_points(center: Vector2, half_diag: float) -> PackedVector2Array:
		return PackedVector2Array([center + Vector2(0, -half_diag), center + Vector2(half_diag, 0),
			center + Vector2(0, half_diag), center + Vector2(-half_diag, 0)])


## Atajos estáticos del módulo (para quien usa `RK.hatch()` / `RK.diamond_points()`).
static func hatch(canvas: CanvasItem, area: Rect2, a: Color = T.RAID_PREDICTED_A, b: Color = T.RAID_PREDICTED_B, stripe: float = T.RAID_PREDICTED_STRIPE) -> int:
	return Gfx.hatch(canvas, area, a, b, stripe)


static func diamond_points(center: Vector2, half_diag: float) -> PackedVector2Array:
	return Gfx.diamond_points(center, half_diag)


# ==========================================================================
# Marco de integrante
# ==========================================================================
class MemberCard extends Control:

	## clic izq. = sanar · clic der. = escudo · Shift+clic = purificar.
	signal clicked(member_id: String, button_index: int, shift: bool)

	var view: Dictionary = {}
	var member_id := ""
	var last_hatch_stripes := 0

	func _init() -> void:
		custom_minimum_size = T.RAID_FRAME_SIZE
		size = T.RAID_FRAME_SIZE
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	func setup(v: Dictionary) -> void:
		view = v
		member_id = str(v.get("id", ""))
		var nn := "Member_%s" % member_id
		if name != nn:
			name = nn
		modulate.a = float(v.get("opacity", 1.0))
		var spoken := "%s (%s): %s" % [v.get("name", ""), v.get("role", ""), v.get("status_text", "")]
		if v.get("has_priority_threat", false):
			spoken += " · en peligro"
		if float(v.get("projected_damage_3s", 0)) > 0.0:
			spoken += " · daño previsto %d %%" % roundi(float(v["projected_damage_3s"]))
		if int(v.get("shield", 0)) > 0:
			spoken += " · escudo %d" % int(v["shield"])
		if float(v.get("incoming_heal", 0)) > 0.0:
			spoken += " · curación entrante %d %%" % roundi(float(v["incoming_heal"]))
		if v.get("has_dispellable_debuff", false):
			spoken += " · purificable: %s" % v.get("debuff_name", "")
		tooltip_text = spoken
		queue_redraw()

	# --- Lecturas para tests / QA --------------------------------------
	func status_text() -> String:
		return str(view.get("status_text", ""))

	func border_state() -> String:
		return str(view.get("border", "normal"))

	func border_color() -> Color:
		match border_state():
			"threat":
				return T.RAID_AGGRO
			"selected":
				return T.RAID_SELECTED
		return T.RAID_FRAME_EDGE

	func border_width() -> int:
		return 1 if border_state() == "normal" else 2

	func hp_color() -> Color:
		return view.get("hp_color", T.RAID_HEALTH)

	func role_color() -> Color:
		return T.raid_role_color(str(view.get("role", "")))

	func has_diamond() -> bool:
		return bool(view.get("has_dispellable_debuff", false)) and not bool(view.get("is_dead", false))

	func inner_rect() -> Rect2:
		return Rect2(Vector2.ZERO, size)

	func _span_rect(span: Vector2) -> Rect2:
		var r := inner_rect()
		return Rect2(r.position.x + r.size.x * span.x, r.position.y, r.size.x * span.y, r.size.y)

	func hp_rect() -> Rect2:
		return _span_rect(view.get("hp_span", Vector2.ZERO))

	func heal_rect() -> Rect2:
		return _span_rect(view.get("heal_span", Vector2.ZERO))

	func damage_rect() -> Rect2:
		return _span_rect(view.get("damage_span", Vector2.ZERO))

	func shield_rect() -> Rect2:
		var r := _span_rect(view.get("shield_span", Vector2.ZERO))
		r.size.y = T.RAID_SHIELD_HEIGHT
		return r

	func diamond_center() -> Vector2:
		# right: 7px; top: 7px; 11×11 rotado 45° → centro a 7 + 5,5 de cada borde.
		return Vector2(size.x - 7.0 - T.RAID_DISPEL_SIZE * 0.5, 7.0 + T.RAID_DISPEL_SIZE * 0.5)

	func badge_rect() -> Rect2:
		return Rect2(size.x - 6.0 - T.RAID_ROLE_BADGE, size.y - 5.0 - T.RAID_ROLE_BADGE, T.RAID_ROLE_BADGE, T.RAID_ROLE_BADGE)

	# --- Entrada --------------------------------------------------------
	func _gui_input(event: InputEvent) -> void:
		var mb := event as InputEventMouseButton
		if mb and mb.pressed and (mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT):
			clicked.emit(member_id, mb.button_index, mb.shift_pressed)
			accept_event()

	# --- Dibujo ---------------------------------------------------------
	func _draw() -> void:
		var rect := Rect2(Vector2.ZERO, size)
		var r := T.RAID_FRAME_RADIUS
		draw_style_box(T.box(T.RAID_FRAME_BG, r), rect)
		var hp := hp_rect()
		if hp.size.x > 0.0:
			var hb := T.box(hp_color(), 0)
			hb.corner_radius_top_left = r
			hb.corner_radius_bottom_left = r
			if hp.size.x >= size.x - 0.5:
				hb.corner_radius_top_right = r
				hb.corner_radius_bottom_right = r
			draw_style_box(hb, Rect2(hp.position, Vector2(maxf(hp.size.x, float(r)), hp.size.y)))
		var heal := heal_rect()
		if heal.size.x > 0.0:
			draw_rect(heal, T.RAID_INCOMING_HEAL)
		var dmg := damage_rect()
		last_hatch_stripes = Gfx.hatch(self, dmg) if dmg.size.x > 0.0 else 0
		var sh := shield_rect()
		if sh.size.x > 0.0:
			draw_rect(sh, T.RAID_SHIELD)
		# Nombre (left 8 · top 5 · 13 px bold) y estado (left 8 · bottom 4 · 11 px #dbe4ea).
		var nm := str(view.get("name", ""))
		var bold := T.font("bold")
		var name_rect := Rect2(8, 4, size.x - 30, 17)
		D.draw_text_aligned(self, bold, 13, Rect2(name_rect.position + Vector2(0, 1), name_rect.size), nm, Gfx.TEXT_SHADOW, HORIZONTAL_ALIGNMENT_LEFT)
		D.draw_text_aligned(self, bold, 13, name_rect, nm, T.TEXT, HORIZONTAL_ALIGNMENT_LEFT)
		var st := status_text()
		var semi := T.font("semibold")
		var st_rect := Rect2(8, size.y - 18, size.x - 22, 14)
		D.draw_text_aligned(self, semi, T.FS_SMALL, Rect2(st_rect.position + Vector2(0, 1), st_rect.size), st, Gfx.TEXT_SHADOW, HORIZONTAL_ALIGNMENT_LEFT)
		D.draw_text_aligned(self, semi, T.FS_SMALL, st_rect, st, T.RAID_STATUS_TEXT, HORIZONTAL_ALIGNMENT_LEFT)
		# Rombo purificable (violeta con contorno #070a0c de 2 px).
		if has_diamond():
			var half := T.RAID_DISPEL_SIZE * 0.5 * sqrt(2.0)
			draw_colored_polygon(Gfx.diamond_points(diamond_center(), half + 2.0), T.WELL)
			draw_colored_polygon(Gfx.diamond_points(diamond_center(), half), T.RAID_DISPEL)
		# Cuadrito de rol (8×8, r2): azul tanque · verde sanador · naranja daño.
		draw_style_box(T.box(role_color(), 2), badge_rect())
		# Borde interior (box-shadow inset).
		var bw := border_width()
		draw_style_box(T.box(Color.TRANSPARENT, r, bw, border_color()), rect)


# ==========================================================================
# Leyenda
# ==========================================================================
class HatchSwatch extends Control:
	var stripes := 0

	func _init() -> void:
		custom_minimum_size = Vector2(14, 8)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		stripes = Gfx.hatch(self, Rect2(Vector2.ZERO, size), Color(T.RAID_PREDICTED_A, 0.85), T.RAID_PREDICTED_B, 3.0)


class Swatch extends Control:
	var color := Color.WHITE

	func _init(c: Color = Color.WHITE, s: Vector2 = Vector2(14, 8)) -> void:
		color = c
		custom_minimum_size = s
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), color)


class Diamond extends Control:
	var color := Color("#b47bff")
	var side := 9.0

	func _init(c: Color = Color("#b47bff"), s: float = 9.0) -> void:
		color = c
		side = s
		var d := ceilf(s * sqrt(2.0))
		custom_minimum_size = Vector2(d, d)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_colored_polygon(Gfx.diamond_points(size * 0.5, side * 0.5 * sqrt(2.0)), color)


# ==========================================================================
# Barras
# ==========================================================================
## Pista redondeada + relleno 0..1 + texto centrado opcional (sombra 0 1 2 #000).
class Meter extends Control:
	var track := Color("#070a0c")
	var fill := Color("#3ccf73")
	var ratio := 0.0
	var text := ""
	var text_size := 11
	var radius := 7

	func _init(h: float = 14.0, fill_color: Color = Color("#3ccf73"), track_color: Color = Color("#070a0c")) -> void:
		custom_minimum_size = Vector2(10, h)
		fill = fill_color
		track = track_color
		radius = int(h * 0.5)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_value(r: float, t: String = "") -> void:
		ratio = clampf(r, 0.0, 1.0)
		text = t
		queue_redraw()

	func fill_width() -> float:
		return size.x * ratio

	func _draw() -> void:
		draw_style_box(T.box(track, radius), Rect2(Vector2.ZERO, size))
		if ratio > 0.0:
			var fb := T.box(fill, 0)
			fb.corner_radius_top_left = radius
			fb.corner_radius_bottom_left = radius
			if ratio >= 0.999:
				fb.corner_radius_top_right = radius
				fb.corner_radius_bottom_right = radius
			draw_style_box(fb, Rect2(0, 0, maxf(fill_width(), float(radius)), size.y))
		if text != "":
			var f := T.font("bold")
			var r := Rect2(Vector2.ZERO, size)
			D.draw_text_aligned(self, f, text_size, Rect2(r.position + Vector2(0, 1), r.size), text, Color(0, 0, 0, 0.95), HORIZONTAL_ALIGNMENT_CENTER)
			D.draw_text_aligned(self, f, text_size, r, text, T.TEXT, HORIZONTAL_ALIGNMENT_CENTER)


## Flecha de la alerta (viewBox 24, trazo 2,4 #ffb3b3). La base apunta a la izquierda.
class Arrow extends Control:
	var arrow_rotation := 0.0
	var color := Color("#ffb3b3")

	func _init() -> void:
		custom_minimum_size = Vector2(40, 40)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_rotation_rad(r: float) -> void:
		arrow_rotation = r
		queue_redraw()

	func _draw() -> void:
		var s := size
		draw_set_transform(s * 0.5, arrow_rotation, Vector2.ONE)
		SvgPath.draw_layers(self, [{"d": T.RAID_ARROW_PATH, "stroke": color, "width": 2.4}], Rect2(-s * 0.5, s))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Tarjeta de alerta: {panel, arrow, title, subtitle, count}.
static func alert_box() -> Dictionary:
	var sb := T.box(T.RAID_ALERT_BG, T.RAID_ALERT_RADIUS, 2, T.RAID_ALERT_EDGE)
	sb.content_margin_left = 26
	sb.content_margin_right = 26
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 20
	sb.shadow_offset = Vector2(0, 10)
	var panel := PanelContainer.new()
	panel.name = "TacticalAlert"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", sb)
	var row := HBoxContainer.new()
	row.name = "Row"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 16)
	panel.add_child(row)
	var arrow := Arrow.new()
	arrow.name = "Arrow"
	arrow.color = T.RAID_ALERT_ICON
	row.add_child(arrow)
	var texts := VBoxContainer.new()
	texts.name = "Texts"
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.add_theme_constant_override("separation", 0)
	texts.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(texts)
	var title := label("", 26, T.TEXT, "bold", "Title")
	texts.add_child(title)
	var sub := label("", 14, T.RAID_ALERT_SUB, "medium", "Subtitle")
	texts.add_child(sub)
	var count := label("", 44, T.RAID_ALERT_COUNT, "bold", "Countdown")
	count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# margin-left: 8px sobre el gap de 16.
	var count_wrap := MarginContainer.new()
	count_wrap.name = "CountWrap"
	count_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	count_wrap.add_theme_constant_override("margin_left", 8)
	count_wrap.add_child(count)
	row.add_child(count_wrap)
	return {"panel": panel, "arrow": arrow, "title": title, "subtitle": sub, "count": count}


# ==========================================================================
# Consola inferior del sanador
# ==========================================================================
## Trapecio grafito (mismo contorno que el HUD v2) dibujado sobre el escenario 1440×810.
class ConsoleShape extends Control:

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func points() -> PackedVector2Array:
		return PackedVector2Array(T.RAID_CONSOLE_POINTS)

	func bounds() -> Rect2:
		var pts := points()
		var r := Rect2(pts[0], Vector2.ZERO)
		for p in pts:
			r = r.expand(p)
		return r

	func _draw() -> void:
		var pts := points()
		# drop-shadow(0 -6px 22px rgba(0,0,0,.5)) aproximada con capas desplazadas hacia arriba.
		for i in range(4, 0, -1):
			var off := Vector2(0, -6.0 * i / 4.0)
			var grow := 5.5 * i
			var sh := PackedVector2Array([pts[0] + off + Vector2(-grow, 0), pts[1] + off + Vector2(-grow * 0.5, -grow),
				pts[2] + off + Vector2(grow * 0.5, -grow), pts[3] + off + Vector2(grow, 0)])
			draw_colored_polygon(sh, Color(0, 0, 0, 0.5 / 4.0 / i))
		draw_colored_polygon(pts, T.RAID_CONSOLE_BG)
		var outline := pts.duplicate()
		outline.append(pts[0])
		draw_polyline(outline, T.RAID_CONSOLE_EDGE, T.RAID_CONSOLE_EDGE_WIDTH, true)


## Ranura de habilidad 48×48 (r11): color, velo de enfriamiento con cifra (16 px) y tecla.
class AbilitySlot extends Control:
	var key := ""
	var bg := Color("#1a2e22")
	var cooldown_text := ""
	var ability_name := ""

	func _init() -> void:
		custom_minimum_size = Vector2(T.RAID_SLOT_SIZE, T.RAID_SLOT_SIZE)
		size = custom_minimum_size
		mouse_filter = Control.MOUSE_FILTER_PASS

	func setup(k: String, color: Color, cd_text: String, n: String = "") -> void:
		key = k
		bg = color
		cooldown_text = cd_text
		ability_name = n
		tooltip_text = "%s [%s]%s" % [n, k, (" · %s" % cd_text) if cd_text != "" else ""]
		queue_redraw()

	func on_cooldown() -> bool:
		return cooldown_text != ""

	func _draw() -> void:
		var rect := Rect2(Vector2.ZERO, size)
		draw_style_box(T.box(bg, T.RAID_SLOT_RADIUS), rect)
		if on_cooldown():
			draw_style_box(T.box(T.RAID_SLOT_CD_VEIL, T.RAID_SLOT_RADIUS), rect)
			D.draw_text_aligned(self, T.font("bold"), 16, rect, cooldown_text, T.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
		D.draw_text_aligned(self, T.font("bold"), T.FS_SMALL, Rect2(0, size.y - 16, size.x - 4, 14), key, T.RAID_STATUS_TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
		draw_style_box(T.box(Color.TRANSPARENT, T.RAID_SLOT_RADIUS, 1, T.RAID_SLOT_EDGE), rect)
