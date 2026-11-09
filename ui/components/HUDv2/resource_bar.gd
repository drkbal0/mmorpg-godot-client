@tool
extends Control
## HUDv2 resource bar (health / mana). Rounded StyleBoxFlat track and fill,
## 100-HP segment ticks, damage trail, centred tabular "cur / max" text and a
## regen readout on the right (health only).

const T = preload("res://ui/hud_tokens.gd")
const D = preload("res://ui/components/HUDv2/hud_draw.gd")

@export_enum("health", "mana") var kind: String = "health":
	set(value):
		kind = value
		queue_redraw()

@export var current: float = 100.0:
	set(value):
		current = value
		queue_redraw()

@export var max_value: float = 100.0:
	set(value):
		max_value = maxf(1.0, value)
		queue_redraw()

@export var regen: float = 0.0:
	set(value):
		regen = value
		queue_redraw()

## Units per segment tick (0 disables).
@export var tick_step: float = 100.0

var _trail: float = -1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_values(p_current: float, p_max: float, p_regen: float = 0.0) -> void:
	max_value = p_max
	current = clampf(p_current, 0.0, max_value)
	regen = p_regen


func get_fraction() -> float:
	return clampf(current / max_value, 0.0, 1.0)


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var f := get_fraction()
	if _trail < f:
		_trail = f
		queue_redraw()
	elif _trail > f:
		_trail = move_toward(_trail, f, delta * 0.35)
		queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var radius := int(minf(5.0, rect.size.y * 0.5))
	var col := T.HEALTH if kind == "health" else T.MANA
	var f := get_fraction()
	draw_style_box(T.box(T.BAR_BG, radius, 1, Color(1, 1, 1, 0.06)), rect)

	var inner := rect.grow(-1)
	if _trail > f + 0.001:
		var tr := Rect2(inner.position, Vector2(inner.size.x * _trail, inner.size.y))
		draw_style_box(T.box(Color(T.HEALTH_TRAIL if kind == "health" else T.MANA.lightened(0.5), 0.55), radius - 1), tr)
	if f > 0.0:
		var fill := Rect2(inner.position, Vector2(maxf(inner.size.x * f, float(radius * 2)), inner.size.y))
		draw_style_box(T.box(col, radius - 1), fill)
		draw_rect(Rect2(fill.position + Vector2(2, 1), Vector2(fill.size.x - 4, 1)), Color(1, 1, 1, 0.18))
		# Segment ticks over the filled part.
		if kind == "health" and tick_step > 0.0 and max_value / tick_step <= 60.0:
			var n := int(floor(current / tick_step))
			for i in range(1, n + 1):
				var x := inner.position.x + inner.size.x * (i * tick_step / max_value)
				if x < fill.end.x - 1.0:
					draw_line(Vector2(x, inner.position.y + 1), Vector2(x, inner.end.y - 1), T.HEALTH_TICK, 1.0)

	var fs := T.FS_BAR if rect.size.y >= 18.0 else T.FS_SMALL
	var txt := "%d / %d" % [roundi(current), roundi(max_value)]
	D.draw_text_centered(self, T.font("semibold"), fs, rect, txt, T.TEXT, true)
	if kind == "health" and regen != 0.0:
		var rr := Rect2(rect.size.x - 60, 0, 52, rect.size.y)
		D.draw_text_aligned(self, T.font("semibold"), fs, rr, ("+%.1f" if regen > 0.0 else "%.1f") % regen, T.HEALTH_REGEN, HORIZONTAL_ALIGNMENT_RIGHT)
