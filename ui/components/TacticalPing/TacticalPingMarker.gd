@tool
extends Control
class_name TacticalPingMarker

## Marcador táctico 2D proyectado en Screen-Space (ADR 097).
## Representa una señal visual en el mundo colocada por un miembro de la escuadra.
## Se auto-destruye tras 6.0 segundos.

const T = preload("res://ui/hud_tokens.gd")
const D = preload("res://ui/components/HUDv2/hud_draw.gd")

enum PingType {
	ATTACK = 0,
	DANGER = 1,
	EXTRACT = 2,
	ASSIST = 3
}

@export var ping_type: int = PingType.ATTACK:
	set(value):
		ping_type = value
		queue_redraw()

@export var sender_name: String = "Valerius":
	set(value):
		sender_name = value
		queue_redraw()

@export var distance_meters: float = 24.0:
	set(value):
		distance_meters = value
		queue_redraw()

@export var world_position: Vector3 = Vector3.ZERO
@export var auto_destroy: bool = true
@export var lifetime: float = 6.0

var _elapsed: float = 0.0
var _pulse_radius: float = 0.0
var _bounce_offset: float = -20.0
var _fade_alpha: float = 1.0


func _ready() -> void:
	custom_minimum_size = Vector2(140, 52)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Animación de caída con rebote
	_bounce_offset = -30.0
	var tw := create_tween()
	tw.tween_property(self, "_bounce_offset", 0.0, 0.45).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


func setup(p_type: int, p_sender: String, p_pos: Vector3, p_dist: float = 0.0) -> void:
	ping_type = p_type
	sender_name = p_sender
	world_position = p_pos
	distance_meters = p_dist
	_elapsed = 0.0
	_fade_alpha = 1.0
	queue_redraw()


func _process(delta: float) -> void:
	_elapsed += delta

	# Pulso de anillo de radar continuo
	_pulse_radius = fmod(_elapsed * 35.0, 40.0)

	# Desvanecimiento en los últimos 0.8s de vida
	if auto_destroy:
		if _elapsed >= lifetime - 0.8:
			_fade_alpha = clampf((lifetime - _elapsed) / 0.8, 0.0, 1.0)
		if _elapsed >= lifetime:
			queue_free()
			return

	queue_redraw()


func get_ping_color() -> Color:
	match ping_type:
		PingType.ATTACK:
			return Color("#ef4444")
		PingType.DANGER:
			return Color("#f59e0b")
		PingType.EXTRACT:
			return Color("#10b981")
		PingType.ASSIST:
			return Color("#06b6d4")
		_:
			return Color("#ffffff")


func get_ping_name() -> String:
	match ping_type:
		PingType.ATTACK:
			return "ATACAR"
		PingType.DANGER:
			return "PELIGRO"
		PingType.EXTRACT:
			return "EXTRAER"
		PingType.ASSIST:
			return "ASISTIR"
		_:
			return "PING"


func get_ping_glyph() -> String:
	match ping_type:
		PingType.ATTACK:
			return "target"
		PingType.DANGER:
			return "hazard"
		PingType.EXTRACT:
			return "recall"
		PingType.ASSIST:
			return "user"
		_:
			return "user"


func _draw() -> void:
	var col := get_ping_color()
	col.a *= _fade_alpha
	var c := Vector2(size.x * 0.5, size.y * 0.5 + _bounce_offset)

	# 1. Anillo de pulso expansivo en el punto de impacto
	if _pulse_radius > 4.0:
		var p_alpha := (1.0 - (_pulse_radius / 40.0)) * 0.6 * _fade_alpha
		draw_arc(c + Vector2(0, 16), _pulse_radius, 0, TAU, 32, Color(col.r, col.g, col.b, p_alpha), 1.5, true)

	# 2. Caja flotante del marcador
	var box_rect := Rect2(c.x - 62, c.y - 20, 124, 30)
	draw_style_box(T.box(T.PANEL_BG, 8, 1, Color(col, 0.7 * _fade_alpha)), box_rect)

	# 3. Icono del glifo
	var icon_center := Vector2(box_rect.position.x + 14, box_rect.get_center().y)
	D.draw_glyph(self, get_ping_glyph(), icon_center, 10.0, col, 1.8)

	# 4. Textos: Título y Emisor / Distancia
	var font_bold := T.font("bold")
	var font_med := T.font("medium")

	# Línea 1: [TIPO] EMISOR
	var title_text := "%s · %s" % [get_ping_name(), sender_name]
	var r_title := Rect2(box_rect.position.x + 28, box_rect.position.y + 2, 90, 14)
	D.draw_text_aligned(self, font_bold, 9, r_title, title_text, col, HORIZONTAL_ALIGNMENT_LEFT)

	# Línea 2: Distancia
	var dist_text := "%dm" % maxi(0, roundi(distance_meters))
	var r_dist := Rect2(box_rect.position.x + 28, box_rect.position.y + 15, 90, 12)
	D.draw_text_aligned(self, font_med, 8, r_dist, dist_text, Color(T.TEXT_SECONDARY, _fade_alpha), HORIZONTAL_ALIGNMENT_LEFT)

	# 5. Flecha / Chevrón apuntando al suelo
	var tip_y := c.y + 16
	var pts := PackedVector2Array([
		Vector2(c.x - 6, box_rect.end.y),
		Vector2(c.x + 6, box_rect.end.y),
		Vector2(c.x, tip_y)
	])
	draw_colored_polygon(pts, col)

