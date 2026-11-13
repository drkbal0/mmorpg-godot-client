@tool
extends Control
class_name TacticalPingWheel

## Rueda de Pings Tácticos Radial (ADR 097) — UX estilo MOBA.
## [G] pulsada abre la rueda centrada en el cursor; arrastrar más allá del DEADZONE
## (35 px) selecciona el cuadrante; soltar [G] o el clic izquierdo confirma (emite
## `ping_selected` + SFX); clic derecho cancela sin emitir.
##   ARRIBA    (-90°) PELIGRO      Rojo     #ff3344  lol_danger
##   IZQUIERDA (180°) DESAPARECIDO Amarillo #facc15  lol_missing
##   DERECHA   (0°)   EN CAMINO    Verde    #10b981  lol_omw
##   ABAJO     (90°)  ASISTIR      Azul     #0284c7  lol_assist

const T = preload("res://ui/tokens/hud_tokens.gd")
const D = preload("res://ui/components/HUDv2/hud_draw.gd")

## Valores de cable sincronizados con Rust protocol.rs PING_TYPE_* (0x1A).
enum PingType {
	MISSING = 0,    # Oeste / Izquierda (Amarillo ??) — Wire PING_TYPE_ATTACK
	DANGER = 1,     # Norte / Arriba (Rojo ¡PELIGRO!) — Wire PING_TYPE_DANGER
	ASSIST = 2,     # Sur / Abajo (Azul ASISTIR / VOY) — Wire PING_TYPE_ASSIST
	ON_MY_WAY = 3,  # Este / Derecha (Verde EN CAMINO) — Wire PING_TYPE_EXTRACT
	NONE = -1
}

signal ping_selected(type: int, ping_name: String)
signal cancelled()

const RADIUS_OUTER := 92.0
const RADIUS_INNER := 34.0
const DEADZONE := 35.0

const PING_CONFIG := [
	{
		"type": PingType.DANGER,
		"name": "PELIGRO",
		"color": Color("#ff3344"),
		"angle": -PI * 0.5,       # Norte (-90°)
		"glyph": "hazard",
		"sfx": &"lol_danger",
		"desc": "¡PELIGRO! Alerta de amenaza inminente"
	},
	{
		"type": PingType.ON_MY_WAY,
		"name": "EN CAMINO",
		"color": Color("#10b981"),
		"angle": 0.0,             # Este (0°)
		"glyph": "arrow_right",
		"sfx": &"lol_omw",
		"desc": "En camino al objetivo"
	},
	{
		"type": PingType.ASSIST,
		"name": "ASISTIR",
		"color": Color("#0284c7"),
		"angle": PI * 0.5,        # Sur (90°)
		"glyph": "shield",
		"sfx": &"lol_assist",
		"desc": "Asistir / Voy en apoyo"
	},
	{
		"type": PingType.MISSING,
		"name": "DESAPARECIDO",
		"color": Color("#facc15"),
		"angle": PI,              # Oeste (180°)
		"glyph": "question",
		"sfx": &"lol_missing",
		"desc": "Enemigo desaparecido (??)"
	}
]

var active_selection: int = PingType.NONE:
	set(value):
		if active_selection != value:
			active_selection = value
			queue_redraw()

var is_active: bool = false
var wheel_center: Vector2 = Vector2.ZERO
## Posición de pantalla (viewport) donde se abrió la rueda (centro del arrastre).
var open_screen_pos: Vector2 = Vector2.ZERO
## Último cue de SFX reproducido al confirmar (telemetría / tests headless).
var last_sfx_cue: StringName = &""


func _ready() -> void:
	custom_minimum_size = Vector2(240, 240)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	wheel_center = size * 0.5
	visible = false
	set_process(false)


## Abre la rueda centrada en la posición de pantalla indicada.
func open_at(screen_pos: Vector2) -> void:
	size = custom_minimum_size
	wheel_center = size * 0.5
	open_screen_pos = screen_pos
	global_position = screen_pos - wheel_center
	visible = true
	is_active = true
	active_selection = PingType.NONE
	set_process(true)
	queue_redraw()


## Actualiza la selección a partir de la posición actual del cursor (pantalla).
## Devuelve el cuadrante resultante (NONE si el arrastre no supera el DEADZONE).
func update_selection_from_screen(screen_pos: Vector2) -> int:
	if not is_active:
		return PingType.NONE
	active_selection = get_quadrant_from_offset(screen_pos - open_screen_pos)
	return active_selection


## Cierra la rueda. Si hay cuadrante válido emite `ping_selected` y reproduce su SFX;
## si el cursor sigue en el DEADZONE equivale a cancelar.
func close_and_confirm() -> int:
	if not is_active:
		return PingType.NONE
	set_process(false)
	var confirmed: int = active_selection
	is_active = false
	visible = false
	active_selection = PingType.NONE
	if confirmed != PingType.NONE:
		var cfg := get_ping_config(confirmed)
		_play_sfx(cfg.get("sfx", &""))
		ping_selected.emit(confirmed, str(cfg.get("name", "PING")))
	else:
		cancelled.emit()
	return confirmed


## Cancela la rueda sin emitir ping.
func cancel() -> void:
	if not is_active:
		return
	set_process(false)
	is_active = false
	visible = false
	active_selection = PingType.NONE
	cancelled.emit()


## Se usa _input (no _unhandled_input) para que, con la rueda abierta, los clics
## no lleguen a la selección de objetivos del mundo.
func _input(event: InputEvent) -> void:
	if not is_active:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			cancel()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if not event.pressed:
				update_selection_from_screen(event.position)
				if active_selection != PingType.NONE:
					close_and_confirm()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		update_selection_from_screen(event.position)


func _process(_delta: float) -> void:
	if not is_active or DisplayServer.get_name() == "headless":
		return
	update_selection_from_screen(get_viewport().get_mouse_position())


func _play_sfx(cue: StringName) -> void:
	if cue == &"":
		return
	last_sfx_cue = cue
	var tree := get_tree()
	if tree == null:
		return
	var sm := tree.root.get_node_or_null("SoundManager")
	if sm and sm.has_method("play_ui_sfx"):
		sm.play_ui_sfx(cue)


## Cuadrante a partir del desplazamiento cursor-centro (NONE dentro del DEADZONE).
static func get_quadrant_from_offset(offset: Vector2) -> int:
	if offset.length() <= DEADZONE:
		return PingType.NONE
	return get_quadrant_from_angle(offset.angle())


## Retorna el cuadrante angular según el ángulo del ratón respecto al centro.
static func get_quadrant_from_angle(angle: float) -> int:
	# Cuadrantes en cruz (45° de tolerancia por sector):
	# Norte (-90°): [-3PI/4, -PI/4) -> DANGER (Up, Red)
	# Este (0°):    [-PI/4, PI/4)   -> ON_MY_WAY (Right, Green)
	# Sur (90°):    [PI/4, 3PI/4)   -> ASSIST (Down, Blue)
	# Oeste (180°): resto           -> MISSING (Left, Yellow ??)
	if angle >= -PI * 0.75 and angle < -PI * 0.25:
		return PingType.DANGER
	elif angle >= -PI * 0.25 and angle < PI * 0.25:
		return PingType.ON_MY_WAY
	elif angle >= PI * 0.25 and angle < PI * 0.75:
		return PingType.ASSIST
	else:
		return PingType.MISSING


static func get_ping_color(p_type: int) -> Color:
	return get_ping_config(p_type).get("color", Color.WHITE)


static func get_ping_sfx(p_type: int) -> StringName:
	return get_ping_config(p_type).get("sfx", &"")


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
