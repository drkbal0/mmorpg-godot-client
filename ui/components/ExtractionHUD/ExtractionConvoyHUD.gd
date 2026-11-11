extends Control
class_name ExtractionConvoyHUD

## ExtractionConvoyHUD.gd — Banner superior del convoy de extracción (Fase 9.7, ADR 099).
##
##   CONVOY DE EXTRACCIÓN EN MOVIMIENTO - TIEMPO RESTANTE: 07.4s
##
## Barra de canalización de 10 s con décimas suaves: el valor se descuenta cada
## frame y se re-sincroniza con cada 0x1C (20 Hz). En pánico (radio 4 m) el
## acento pasa de cian a ámbar/rojo y se añade el aviso de radio contraído.

const T = preload("res://ui/hud_tokens.gd")
const Codec = preload("res://shared-core/ExtractionReviveCodec.gd")

const COLOR_NORMAL := Color("#00f0ff")
const COLOR_PANIC := Color("#ff6a1a")
const PANEL_SIZE := Vector2(640, 74)

var remaining_ms: float = 0.0
var total_ms: float = float(Codec.CONVOY_EXTRACTION_MS)
var is_panic: bool = false
var players_inside: int = 0
var radius_m: float = Codec.CONVOY_RADIUS_NORMAL
var is_channelling: bool = false
var _t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = PANEL_SIZE
	size = PANEL_SIZE
	visible = false


## Sincroniza con el convoy (señal countdown_changed o un 0x1C decodificado).
func apply_beacon(b: Dictionary) -> void:
	is_panic = bool(b.get("is_panic", false))
	radius_m = float(b.get("radius", radius_m))
	players_inside = int(b.get("players_inside_count", players_inside))
	set_remaining_ms(float(b.get("remaining_ms", 0)))


func set_remaining_ms(ms: float) -> void:
	remaining_ms = clampf(ms, 0.0, total_ms)
	is_channelling = remaining_ms > 0.0
	visible = is_channelling
	queue_redraw()


func get_title_text() -> String:
	return "CONVOY DE EXTRACCIÓN EN MOVIMIENTO - TIEMPO RESTANTE: %s" % Codec.format_countdown(remaining_ms)


func get_progress() -> float:
	return 1.0 - remaining_ms / total_ms if total_ms > 0.0 else 0.0


func _process(delta: float) -> void:
	_t += delta
	if is_channelling and remaining_ms > 0.0:
		remaining_ms = maxf(remaining_ms - delta * 1000.0, 0.0)
	queue_redraw()


func _draw() -> void:
	var accent := COLOR_PANIC if is_panic else COLOR_NORMAL
	var rect := Rect2(Vector2.ZERO, PANEL_SIZE)
	draw_style_box(T.box(Color(0.03, 0.05, 0.07, 0.88), 10, 2, Color(accent, 0.85)), rect)
	# Glow superior pulsante.
	var pulse := 0.5 + 0.5 * sin(_t * TAU * (3.0 if is_panic else 1.0))
	draw_rect(Rect2(10, 1, PANEL_SIZE.x - 20, 3), Color(accent, 0.35 + 0.45 * pulse))

	var bold := T.font("bold")
	var med := T.font("medium")
	draw_string(bold, Vector2(18, 28), get_title_text(), HORIZONTAL_ALIGNMENT_LEFT, PANEL_SIZE.x - 36, 16, T.TEXT)

	# Barra de canalización.
	var bar := Rect2(18, 40, PANEL_SIZE.x - 36, 10)
	draw_style_box(T.box(T.BAR_BG, 5, 1, Color(1, 1, 1, 0.08)), bar)
	var fill := Rect2(bar.position, Vector2(bar.size.x * get_progress(), bar.size.y))
	if fill.size.x > 1.0:
		draw_style_box(T.box(accent, 5), fill)

	var sub := "Radio %.1f m · %d en la zona · mantente dentro del anillo" % [radius_m, players_inside]
	if is_panic:
		sub = "¡PÁNICO! Combate a ≤15 m · radio contraído a %.1f m · %d en la zona" % [radius_m, players_inside]
	draw_string(med, Vector2(18, 66), sub, HORIZONTAL_ALIGNMENT_LEFT, PANEL_SIZE.x - 36, 12, Color(accent, 0.95) if is_panic else T.TEXT_SECONDARY)
