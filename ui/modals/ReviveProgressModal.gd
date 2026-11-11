extends Control
class_name ReviveProgressModal

## ReviveProgressModal.gd — Canalización de reanimación contextual [F] (Fase 9.7, ADR 100).
##
## Anillo de canalización circular + rótulo "Reanimando a Kaelen [65%]".
## La canalización dura 6 s (120 ticks a 20 Hz). El progreso avanza localmente
## desde el REVIVE_SYNC Started y se re-sincroniza con progress_pct de cada 0x1D;
## Interrupted lo cierra en rojo y Completed en verde.

const T = preload("res://ui/hud_tokens.gd")
const D = preload("res://ui/components/HUDv2/hud_draw.gd")
const Codec = preload("res://shared-core/ExtractionReviveCodec.gd")

const COLOR_CHANNEL := Color("#3dff8a")
const COLOR_INTERRUPTED := Color("#ff4655")
const PANEL_SIZE := Vector2(380, 84)
const RING_RADIUS := 26.0

signal finished(success: bool)

var target_name: String = ""
var downed_sid: int = 0
var progress: float = 0.0 # 0..1
var duration_sec: float = Codec.REVIVE_CHANNEL_SEC
var is_channelling: bool = false
var was_interrupted: bool = false
var _fade := 0.0
var _t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = PANEL_SIZE
	size = PANEL_SIZE
	visible = false


static func format_label(p_name: String, pct: int) -> String:
	return "Reanimando a %s [%d%%]" % [p_name, clampi(pct, 0, 100)]


func start(p_name: String, p_downed_sid: int = 0, start_pct: int = 0) -> void:
	target_name = p_name
	downed_sid = p_downed_sid
	progress = clampf(start_pct / 100.0, 0.0, 1.0)
	is_channelling = true
	was_interrupted = false
	_fade = 0.0
	visible = true
	queue_redraw()


func set_progress_pct(pct: float) -> void:
	progress = clampf(pct / 100.0, 0.0, 1.0)
	queue_redraw()


func get_progress_pct() -> int:
	return int(floor(progress * 100.0 + 0.0001))


func get_label_text() -> String:
	return format_label(target_name, get_progress_pct())


func interrupt() -> void:
	if not is_channelling:
		return
	is_channelling = false
	was_interrupted = true
	_fade = 0.6
	finished.emit(false)


func complete() -> void:
	is_channelling = false
	was_interrupted = false
	progress = 1.0
	_fade = 0.6
	finished.emit(true)


## Aplica un REVIVE_SYNC decodificado (ExtractionReviveCodec.decode_revive).
func apply_revive_sync(s: Dictionary, p_name: String = "") -> void:
	match int(s.get("state", -1)):
		Codec.REVIVE_STARTED:
			start(p_name if p_name != "" else target_name, int(s.get("downed_player_id", 0)), int(s.get("progress_pct", 0)))
		Codec.REVIVE_INTERRUPTED:
			interrupt()
		Codec.REVIVE_COMPLETED:
			complete()


func _process(delta: float) -> void:
	_t += delta
	if is_channelling:
		progress = minf(progress + delta / duration_sec, 1.0)
	elif _fade > 0.0:
		_fade -= delta
		if _fade <= 0.0:
			visible = false
	queue_redraw()


func _draw() -> void:
	var col := COLOR_INTERRUPTED if was_interrupted else COLOR_CHANNEL
	var rect := Rect2(Vector2.ZERO, PANEL_SIZE)
	draw_style_box(T.box(Color(0.02, 0.05, 0.04, 0.86), 12, 2, Color(col, 0.8)), rect)

	# Anillo de canalización circular a la izquierda.
	var c := Vector2(44, PANEL_SIZE.y * 0.5)
	draw_circle(c, RING_RADIUS + 7.0, Color(0, 0, 0, 0.45))
	D.draw_ring(self, c, RING_RADIUS, 6.0, Color(1, 1, 1, 0.08))
	D.draw_ring(self, c, RING_RADIUS, 6.0, col, 0.0, progress)
	# Cruz médica pulsante en el centro.
	var k := 0.75 + 0.25 * sin(_t * TAU * 1.5)
	draw_rect(Rect2(c - Vector2(3, 10), Vector2(6, 20)), Color(col, k))
	draw_rect(Rect2(c - Vector2(10, 3), Vector2(20, 6)), Color(col, k))

	var bold := T.font("bold")
	var label := get_label_text() if not was_interrupted else "Reanimación interrumpida"
	var text_x := 86.0
	var text_w := PANEL_SIZE.x - text_x - 14.0
	draw_string(bold, Vector2(text_x, 34), label, HORIZONTAL_ALIGNMENT_LEFT, text_w, 17, T.TEXT)
	# Barra lineal secundaria (mismo progreso) y ayuda de control.
	var bar := Rect2(text_x, 44, text_w, 6)
	draw_style_box(T.box(T.BAR_BG, 3), bar)
	if progress > 0.0:
		draw_style_box(T.box(col, 3), Rect2(bar.position, Vector2(bar.size.x * progress, bar.size.y)))
	draw_string(T.font("medium"), Vector2(text_x, 70), "Mantén [F] · No recibas daño · ≤ 2.5 m",
		HORIZONTAL_ALIGNMENT_LEFT, text_w, 11, T.TEXT_SECONDARY)
