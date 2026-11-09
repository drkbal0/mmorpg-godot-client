@tool
extends Control
## HUDv2 stat row: 20px tall, 7px coloured dot, name (dim) and a right-aligned
## tabular value (Barlow 'tnum').

const T = preload("res://ui/hud_tokens.gd")
const D = preload("res://ui/components/HUDv2/hud_draw.gd")

@export var stat_id: String = ""
@export var stat_name: String = "Stat":
	set(value):
		stat_name = value
		queue_redraw()

@export var value_text: String = "0":
	set(value):
		value_text = value
		queue_redraw()

@export var dot_color: Color = T.TEXT_DIM:
	set(value):
		dot_color = value
		queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(130, T.STAT_ROW_HEIGHT)


## Accepts int, float or preformatted String values.
func set_value(v: Variant) -> void:
	value_text = format_value(v)


static func format_value(v: Variant) -> String:
	match typeof(v):
		TYPE_INT:
			return str(v)
		TYPE_FLOAT:
			var f: float = v
			if is_equal_approx(f, roundf(f)):
				return str(int(roundf(f)))
			return "%.2f" % f
		_:
			return str(v)


func _draw() -> void:
	var h := T.STAT_ROW_HEIGHT
	var cy := h * 0.5
	draw_circle(Vector2(T.STAT_DOT * 0.5 + 1.0, cy), T.STAT_DOT * 0.5, dot_color)
	var name_rect := Rect2(T.STAT_DOT + 7.0, 0, size.x - T.STAT_DOT - 7.0, h)
	D.draw_text_aligned(self, T.font("medium"), T.FS_STAT_NAME, name_rect, stat_name, T.TEXT_DIM, HORIZONTAL_ALIGNMENT_LEFT)
	D.draw_text_aligned(self, T.font("bold"), T.FS_STAT_VALUE, Rect2(0, 0, size.x, h), value_text, T.TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
