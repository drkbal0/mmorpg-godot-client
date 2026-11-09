@tool
extends Control
## HUDv2 buff/debuff icon: 28x28, radius 8. Colour tile (or texture), stack
## count and an optional remaining-duration sweep.

const T = preload("res://ui/hud_tokens.gd")
const D = preload("res://ui/components/HUDv2/hud_draw.gd")

@export var color: Color = Color("#2b6a5c"):
	set(value):
		color = value
		queue_redraw()

@export var icon: Texture2D:
	set(value):
		icon = value
		queue_redraw()

@export var stacks: int = 0:
	set(value):
		stacks = value
		queue_redraw()

## 0 = no sweep; otherwise elapsed part of the duration is darkened.
@export_range(0.0, 1.0, 0.001) var duration_fraction: float = 0.0:
	set(value):
		duration_fraction = clampf(value, 0.0, 1.0)
		queue_redraw()

@export var is_debuff: bool = false:
	set(value):
		is_debuff = value
		queue_redraw()

@export var buff_name: String = ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	custom_minimum_size = Vector2(T.BUFF_SIZE, T.BUFF_SIZE)
	size = custom_minimum_size


## Configure from a dictionary: {color, icon, stacks, duration_fraction, debuff, name}.
func setup(data: Dictionary) -> void:
	color = data.get("color", color)
	icon = data.get("icon", null)
	stacks = int(data.get("stacks", 0))
	duration_fraction = float(data.get("duration_fraction", 0.0))
	is_debuff = bool(data.get("debuff", false))
	buff_name = str(data.get("name", ""))
	tooltip_text = buff_name


func _draw() -> void:
	var tile := Rect2(Vector2.ZERO, Vector2(T.BUFF_SIZE, T.BUFF_SIZE))
	var border := Color("#c04848") if is_debuff else Color(1, 1, 1, 0.14)
	draw_style_box(T.box(color, T.BUFF_RADIUS, 1, border), tile)
	if icon:
		draw_texture_rect(icon, tile.grow(-4), false)
	if duration_fraction > 0.0:
		D.draw_cooldown(self, tile.grow(-1), T.BUFF_RADIUS - 1, duration_fraction, Color(0, 0, 0, 0.45))
	if stacks > 0:
		var font := T.font("bold")
		var r := Rect2(0, 14, T.BUFF_SIZE - 3, 13)
		var y := D.baseline_for_center(font, T.FS_SMALL, r.get_center().y)
		draw_string(font, Vector2(r.position.x, y + 1), str(stacks), HORIZONTAL_ALIGNMENT_RIGHT, r.size.x, T.FS_SMALL, Color(0, 0, 0, 0.7))
		draw_string(font, Vector2(r.position.x, y), str(stacks), HORIZONTAL_ALIGNMENT_RIGHT, r.size.x, T.FS_SMALL, T.TEXT)
