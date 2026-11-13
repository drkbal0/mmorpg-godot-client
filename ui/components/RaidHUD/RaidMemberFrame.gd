@tool
extends Control
## Marco compacto de miembro de raid (MMO-Raid, 128×42) para el HUD de sanador.
##
## Capas (de abajo arriba), igual que design_ref/pantallas_html/MMO-Raid.html:
##   fondo rgba(7,10,12,.9) r8 → vida #3ccf73 segmentada (tramos de 10 %) →
##   curación entrante verde translúcido (tras la vida) → daño previsto en 3 s
##   achurado dorado a 135° (el último tramo de la vida que se va a perder) →
##   nombre / estado → rombos de efectos purificables → cuadrado de clase →
##   borde (rojo pulsante con aggro del jefe, turquesa si está seleccionado).
## Fuera de alcance de curación (> 40 m) el marco baja a 40 % de opacidad;
## muerto, a 60 %.
##
##   frame.setup({"name": "Toro", "class": "tanque", "hp": 580, "hp_max": 1000,
##                "predicted_damage": 300, "incoming_heal": 120, "aggro": true,
##                "dispels": ["magia"], "distance": 12.0})

const T = preload("res://ui/tokens/hud_tokens.gd")
const D = preload("res://ui/components/HUDv2/hud_draw.gd")

## clic izq. = sanar · clic der. = escudo · Shift+clic = purificar.
signal frame_clicked(member_id: String, button_index: int, shift: bool)

@export var member_id: String = ""
@export var player_name: String = "":
	set(v):
		player_name = v
		_changed()
@export var player_class: String = "":
	set(v):
		player_class = v
		_changed()
@export var hp: float = 100.0:
	set(v):
		hp = clampf(v, 0.0, hp_max)
		_changed()
@export var hp_max: float = 100.0:
	set(v):
		hp_max = maxf(1.0, v)
		hp = minf(hp, hp_max)
		_changed()
## Daño previsto en los próximos 3 s (RAID_PREDICTION_WINDOW).
@export var predicted_damage: float = 0.0:
	set(v):
		predicted_damage = maxf(0.0, v)
		_changed()
## Curación entrante (lanzamientos en curso + HoTs).
@export var incoming_heal: float = 0.0:
	set(v):
		incoming_heal = maxf(0.0, v)
		_changed()
## Tiene el aggro del jefe → borde rojo pulsante.
@export var has_aggro: bool = false:
	set(v):
		has_aggro = v
		_changed()
@export var selected: bool = false:
	set(v):
		selected = v
		_changed()
## Distancia al sanador en metros (> 40 m = fuera de alcance).
@export var distance: float = 0.0:
	set(v):
		distance = maxf(0.0, v)
		_changed()
## Claves de T.DISPEL_TYPES ("magia", "veneno", "enfermedad", "maldicion").
var dispels: Array[String] = []:
	set(v):
		dispels = v
		_changed()

var _pulse_phase: float = 0.0
## Nº de franjas del achurado dibujadas en el último _draw (para pruebas/QA).
var last_hatch_stripes: int = 0


func _init() -> void:
	custom_minimum_size = T.RAID_FRAME_SIZE
	size = T.RAID_FRAME_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP


func setup(data: Dictionary) -> void:
	member_id = str(data.get("id", data.get("name", member_id)))
	player_name = str(data.get("name", player_name))
	player_class = str(data.get("class", player_class))
	hp_max = float(data.get("hp_max", hp_max))
	hp = float(data.get("hp", hp))
	predicted_damage = float(data.get("predicted_damage", predicted_damage))
	incoming_heal = float(data.get("incoming_heal", incoming_heal))
	has_aggro = bool(data.get("aggro", has_aggro))
	distance = float(data.get("distance", distance))
	if data.has("dispels"):
		var arr: Array[String] = []
		for d in data["dispels"]:
			arr.append(str(d))
		dispels = arr


# --------------------------------------------------------------------------
# Cálculos (públicos para tooling y pruebas)
# --------------------------------------------------------------------------
func is_dead() -> bool:
	return hp <= 0.0


func is_out_of_range() -> bool:
	return distance > T.RAID_HEAL_RANGE


func get_health_fraction() -> float:
	return clampf(hp / hp_max, 0.0, 1.0)


## Daño previsto acotado a la vida restante (no se puede perder más vida de la que hay).
func get_predicted_amount() -> float:
	return minf(predicted_damage, hp)


## Tramo achurado: [inicio, ancho] como fracción de la barra. Cubre el final
## de la vida actual, la parte que se perderá en los próximos 3 s.
func get_predicted_span() -> Vector2:
	var w := get_predicted_amount() / hp_max
	return Vector2(get_health_fraction() - w, w)


## Tramo verde translúcido de curación entrante: [inicio, ancho], recortado a la vida que falta.
func get_incoming_heal_span() -> Vector2:
	var w := clampf(incoming_heal, 0.0, hp_max - hp) / hp_max
	return Vector2(get_health_fraction(), w)


## Vida estimada al final de la ventana de predicción (vida − daño + curación).
func get_projected_health() -> float:
	return clampf(hp - predicted_damage + incoming_heal, 0.0, hp_max)


## El daño previsto mata si no llega curación suficiente.
func is_lethal_prediction() -> bool:
	return not is_dead() and predicted_damage >= hp + incoming_heal


func get_frame_alpha() -> float:
	if is_dead():
		return T.RAID_DEAD_ALPHA
	if is_out_of_range():
		return T.RAID_OUT_OF_RANGE_ALPHA
	return 1.0


func get_border_color() -> Color:
	if has_aggro:
		return T.RAID_AGGRO
	if selected:
		return T.RAID_SELECTED
	return T.RAID_FRAME_EDGE


func get_border_width() -> int:
	return 2 if (has_aggro or selected) else 1


## Alfa del borde de aggro (pulsa entre 0.55 y 1.0).
func get_aggro_pulse_alpha() -> float:
	return 0.55 + 0.45 * (0.5 + 0.5 * cos(_pulse_phase * TAU))


func get_status_text() -> String:
	if is_dead():
		return "Muerto · resucitar"
	if is_out_of_range():
		return "%d m" % roundi(distance)
	return "%d %%" % roundi(get_health_fraction() * 100.0)


func get_class_color() -> Color:
	return T.class_color(player_class)


# --------------------------------------------------------------------------
func _changed() -> void:
	modulate.a = get_frame_alpha()
	var spoken := "%s (%s): %s" % [player_name, player_class, get_status_text()]
	if has_aggro:
		spoken += " · tiene el aggro del jefe"
	if predicted_damage > 0.0:
		spoken += " · daño previsto %d" % roundi(predicted_damage)
	if incoming_heal > 0.0:
		spoken += " · curación entrante %d" % roundi(incoming_heal)
	for d in dispels:
		spoken += " · purificable: %s" % T.DISPEL_TYPES.get(d, {"name": d})["name"]
	tooltip_text = spoken
	queue_redraw()


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or not has_aggro:
		return
	_pulse_phase = fmod(_pulse_phase + delta * T.RAID_AGGRO_PULSE_HZ, 1.0)
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and (mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT):
		frame_clicked.emit(member_id, mb.button_index, mb.shift_pressed)
		accept_event()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var r := T.RAID_FRAME_RADIUS
	draw_style_box(T.box(T.RAID_FRAME_BG, r), rect)
	var inner := rect.grow(-1)
	var bw := inner.size.x

	# Vida.
	var f := get_health_fraction()
	if f > 0.0:
		var hb := T.box(T.RAID_HEALTH, 0)
		hb.corner_radius_top_left = r - 1
		hb.corner_radius_bottom_left = r - 1
		if f >= 0.999:
			hb.corner_radius_top_right = r - 1
			hb.corner_radius_bottom_right = r - 1
		draw_style_box(hb, Rect2(inner.position, Vector2(maxf(bw * f, float(r)), inner.size.y)))

	# Curación entrante (verde translúcido, a continuación de la vida).
	var heal := get_incoming_heal_span()
	if heal.y > 0.0:
		draw_rect(_span_rect(inner, heal), T.RAID_INCOMING_HEAL)

	# Daño previsto (achurado dorado 135°).
	var pred := get_predicted_span()
	last_hatch_stripes = 0
	if pred.y > 0.0:
		_draw_hatch(_span_rect(inner, pred))

	# Segmentos cada 10 % sobre la vida.
	for i in range(1, T.RAID_HEALTH_SEGMENTS):
		var x := inner.position.x + bw * float(i) / T.RAID_HEALTH_SEGMENTS
		if x < inner.position.x + bw * f:
			draw_line(Vector2(x, inner.position.y + 2), Vector2(x, inner.end.y - 2), T.HEALTH_TICK, 1.0)

	# Textos (sombra 0 1 2 #000).
	var shadow := Color(0, 0, 0, 0.9)
	var name_font := T.font("bold")
	var name_rect := Rect2(8, 3, size.x - 40, 18)
	D.draw_text_aligned(self, name_font, 13, Rect2(name_rect.position + Vector2(0, 1), name_rect.size), player_name, shadow, HORIZONTAL_ALIGNMENT_LEFT)
	D.draw_text_aligned(self, name_font, 13, name_rect, player_name, T.TEXT, HORIZONTAL_ALIGNMENT_LEFT)
	var st_rect := Rect2(8, size.y - 18, size.x - 24, 15)
	var st_font := T.font("semibold")
	D.draw_text_aligned(self, st_font, T.FS_SMALL, Rect2(st_rect.position + Vector2(0, 1), st_rect.size), get_status_text(), shadow, HORIZONTAL_ALIGNMENT_LEFT)
	D.draw_text_aligned(self, st_font, T.FS_SMALL, st_rect, get_status_text(), Color("#dbe4ea"), HORIZONTAL_ALIGNMENT_LEFT)

	# Rombos de efectos purificables (arriba a la derecha, hacia la izquierda).
	var dsz := T.RAID_DISPEL_SIZE
	for i in dispels.size():
		var c := Vector2(size.x - 7.0 - dsz * 0.5 - i * (dsz + 5.0), 7.0 + dsz * 0.5)
		_draw_diamond(c, dsz * 0.5 * sqrt(2.0) + 2.0, T.WELL)
		_draw_diamond(c, dsz * 0.5 * sqrt(2.0), T.dispel_color(dispels[i]))

	# Cuadrado de clase (abajo a la derecha).
	draw_style_box(T.box(get_class_color(), 2), Rect2(size.x - 14, size.y - 13, 8, 8))

	# Borde: aggro (rojo pulsante) / seleccionado / neutro.
	var bc := get_border_color()
	if has_aggro:
		bc.a = get_aggro_pulse_alpha()
	draw_style_box(T.box(Color.TRANSPARENT, r, get_border_width(), bc), rect)


func _span_rect(inner: Rect2, span: Vector2) -> Rect2:
	return Rect2(inner.position.x + inner.size.x * span.x, inner.position.y, inner.size.x * span.y, inner.size.y)


## repeating-linear-gradient(135deg, A 0 4px, B 4px 8px): fondo B + franjas A
## en "/" recortadas al tramo.
func _draw_hatch(area: Rect2) -> void:
	if area.size.x <= 0.0:
		return
	draw_rect(area, T.RAID_PREDICTED_B)
	var clip := PackedVector2Array([area.position, Vector2(area.end.x, area.position.y), area.end, Vector2(area.position.x, area.end.y)])
	var h := area.size.y
	var w := T.RAID_PREDICTED_STRIPE * sqrt(2.0)   # ancho horizontal de una franja
	var period := w * 2.0
	var x := area.position.x - fmod(area.position.x, period)
	while x < area.end.x + h:
		var poly := PackedVector2Array([
			Vector2(x, area.position.y), Vector2(x + w, area.position.y),
			Vector2(x + w - h, area.end.y), Vector2(x - h, area.end.y)])
		for piece in Geometry2D.intersect_polygons(poly, clip):
			if piece.size() >= 3:
				draw_colored_polygon(piece, T.RAID_PREDICTED_A)
				last_hatch_stripes += 1
		x += period


func _draw_diamond(c: Vector2, rad: float, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -rad), c + Vector2(rad, 0), c + Vector2(0, rad), c + Vector2(-rad, 0)]), col)
