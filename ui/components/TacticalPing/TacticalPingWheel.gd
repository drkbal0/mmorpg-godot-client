@tool
extends Control
class_name TacticalPingWheel

## Rueda de Pings Tácticos Radial (ADR 097).
## Desplegada manteniendo pulsada la tecla 'G', permite seleccionar con el ratón
## entre 4 cuadrantes: ATTACK (Norte), DANGER (Este), EXTRACT (Sur) y ASSIST (Oeste).

const T = preload("res://ui/hud_tokens.gd")
const D = preload("res://ui/components/HUDv2/hud_draw.gd")

enum PingType {
	ATTACK = 0,
	DANGER = 1,
	ASSIST = 2,   # Sincronizado con Rust PING_TYPE_ASSIST (protocolo 0x1A)
	EXTRACT = 3,
	NONE = -1
}

signal ping_selected(type: int, ping_name: String)
signal cancelled()

const RADIUS_OUTER := 92.0
const RADIUS_INNER := 34.0
const DEADZONE := 18.0

const PING_CONFIG := [
	{
		"type": PingType.ATTACK,
		"name": "ATACAR",
		"color": Color("#ef4444"), # Carmesí
		"angle": -PI * 0.5,       # Norte (-90°)
		"glyph": "target",
		"desc": "Foco de daño prioritario"
	},
	{
		"type": PingType.DANGER,
		"name": "PELIGRO",
		"color": Color("#f59e0b"), # Ámbar
		"angle": 0.0,             # Este (0°)
		"glyph": "hazard",
		"desc": "Amenaza hostil inminente"
	},
	{
		"type": PingType.EXTRACT,
		"name": "EXTRAER",
		"color": Color("#10b981"), # Esmeralda
		"angle": PI * 0.5,        # Sur (90°)
		"glyph": "recall",
		"desc": "Punto de repliegue y portal"
	},
	{
		"type": PingType.ASSIST,
		"name": "ASISTIR",
		"color": Color("#06b6d4"), # Cian
		"angle": PI,              # Oeste (180°)
		"glyph": "user",
		"desc": "Solicitud de apoyo o cura"
	}
]

var active_selection: int = PingType.NONE:
	set(value):
		if active_selection != value:
			active_selection = value
			queue_redraw()

var is_active: bool = false
var wheel_center: Vector2 = Vector2.ZERO


func _ready() -> void:
	custom_minimum_size = Vector2(240, 240)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	wheel_center = size * 0.5
	visible = false
	set_process(false)


## Abre la rueda centrada en la posición de pantalla indicada.
func open_at(screen_pos: Vector2) -> void:
	global_position = screen_pos - size * 0.5
	visible = true
	is_active = true
	active_selection = PingType.NONE
	if DisplayServer.get_name() != "headless":
		set_process(true)
	queue_redraw()


## Cierra la rueda y emite la señal de selección si hay un cuadrante válido.
func close_and_confirm() -> int:
	set_process(false)
	var confirmed: int = active_selection
	is_active = false
	visible = false
	if confirmed != PingType.NONE:
		var cfg = get_ping_config(confirmed)
		ping_selected.emit(confirmed, str(cfg.get("name", "PING")))
	else:
		cancelled.emit()
	return confirmed


## Cancela la rueda sin emitir ping.
func cancel() -> void:
	set_process(false)
	is_active = false
	visible = false
	active_selection = PingType.NONE
	cancelled.emit()


func _process(_delta: float) -> void:
	if not is_active:
		return
	if DisplayServer.get_name() == "headless":
		return

	var mpos := get_local_mouse_position()
	var offset := mpos - wheel_center
	var dist := offset.length()

	if dist < DEADZONE:
		active_selection = PingType.NONE
		return

	# Calcular ángulo normalizado en [-PI, PI]
	var angle := offset.angle()
	active_selection = get_quadrant_from_angle(angle)


## Retorna el cuadrante angular según el ángulo del ratón respecto al centro.
static func get_quadrant_from_angle(angle: float) -> int:
	# Cuadrantes en cruz (45° de tolerancia por sector):
	# Norte (-90°): [-3PI/4, -PI/4]
	# Este (0°):    [-PI/4, PI/4]
	# Sur (90°):    [PI/4, 3PI/4]
	# Oeste (180°): resto
	if angle >= -PI * 0.75 and angle < -PI * 0.25:
		return PingType.ATTACK
	elif angle >= -PI * 0.25 and angle < PI * 0.25:
		return PingType.DANGER
	elif angle >= PI * 0.25 and angle < PI * 0.75:
		return PingType.EXTRACT
	else:
		return PingType.ASSIST


static func get_ping_config(p_type: int) -> Dictionary:
	for cfg in PING_CONFIG:
		if cfg["type"] == p_type:
			return cfg
	return {}


func _draw() -> void:
	var c := wheel_center

	# Sombra exterior difusa
	draw_circle(c, RADIUS_OUTER + 8.0, Color(0, 0, 0, 0.45))

	# Fondo general del anillo
	D.draw_ring(self, c, (RADIUS_OUTER + RADIUS_INNER) * 0.5, (RADIUS_OUTER - RADIUS_INNER), T.PANEL_BG)
	draw_arc(c, RADIUS_OUTER, 0, TAU, 64, T.PANEL_EDGE, 1.5, true)
	draw_arc(c, RADIUS_INNER, 0, TAU, 48, T.DIVIDER, 1.0, true)

	# Separadores diagonales en cruz (45°, 135°, 225°, 315°)
	var angles := [-PI * 0.75, -PI * 0.25, PI * 0.25, PI * 0.75]
	for a in angles:
		var p1 := c + Vector2(cos(a), sin(a)) * RADIUS_INNER
		var p2 := c + Vector2(cos(a), sin(a)) * RADIUS_OUTER
		draw_line(p1, p2, Color(1, 1, 1, 0.12), 1.5)

	# Dibujar cada uno de los 4 cuadrantes
	for cfg in PING_CONFIG:
		var ptype: int = cfg["type"]
		var col: Color = cfg["color"]
		var is_selected := (active_selection == ptype)

		# Arco o cuña iluminada si está seleccionado
		if is_selected:
			var start_a: float = cfg["angle"] - PI * 0.23
			var end_a: float = cfg["angle"] + PI * 0.23
			# Cuña poligonal suave
			var wedge_pts := PackedVector2Array()
			var segs := 16
			for i in range(segs + 1):
				var a := lerpf(start_a, end_a, float(i) / float(segs))
				wedge_pts.append(c + Vector2(cos(a), sin(a)) * RADIUS_OUTER)
			for i in range(segs, -1, -1):
				var a := lerpf(start_a, end_a, float(i) / float(segs))
				wedge_pts.append(c + Vector2(cos(a), sin(a)) * RADIUS_INNER)
			draw_colored_polygon(wedge_pts, Color(col, 0.35))
			draw_arc(c, RADIUS_OUTER, start_a, end_a, segs, col, 2.5, true)

		# Posición del icono y texto
		var icon_pos := c + Vector2(cos(cfg["angle"]), sin(cfg["angle"])) * 62.0
		var icon_col := col if is_selected else col.lerp(T.TEXT_SECONDARY, 0.5)
		D.draw_glyph(self, cfg["glyph"], icon_pos, 14.0, icon_col, 2.0)

		# Nombre de la acción
		var label_pos := c + Vector2(cos(cfg["angle"]), sin(cfg["angle"])) * 78.0
		var font := T.font("bold" if is_selected else "medium")
		var fs := 10 if is_selected else 9
		var txt_col := Color.WHITE if is_selected else T.TEXT_SECONDARY
		var r := Rect2(label_pos - Vector2(36, 8), Vector2(72, 16))
		D.draw_text_centered(self, font, fs, r, cfg["name"], txt_col, true)

	# Círculo central (Deadzone)
	draw_circle(c, RADIUS_INNER, T.WELL)
	draw_arc(c, RADIUS_INNER, 0, TAU, 32, Color(1, 1, 1, 0.15), 1.0, true)

	# Si hay selección activa, mostrar indicador en el centro
	if active_selection != PingType.NONE:
		var sel_cfg = get_ping_config(active_selection)
		draw_circle(c, RADIUS_INNER - 4.0, Color(sel_cfg["color"], 0.22))
		D.draw_glyph(self, sel_cfg["glyph"], c + Vector2(0, -4), 11.0, sel_cfg["color"], 2.0)
		var r_name := Rect2(c.x - 30, c.y + 4, 60, 14)
		D.draw_text_centered(self, T.font("bold"), 8, r_name, sel_cfg["name"], sel_cfg["color"], true)
	else:
		# Cursor en deadzone
		D.draw_text_centered(self, T.font("regular"), 9, Rect2(c.x - 25, c.y - 7, 50, 14), "PING", T.TEXT_ZERO, false)
