@tool
extends Control
## HUDv2 stat row: 20px tall, icono vectorial SVG de 16 px (Anexo A, tokens
## `hud_tokens.gd` + `svg_path.gd`), nombre (dim) y valor tabular alineado a la
## derecha (Barlow 'tnum'). Si la stat no tiene icono canónico, cae al punto de color.

const T = preload("res://ui/tokens/hud_tokens.gd")
const D = preload("res://ui/components/HUDv2/hud_draw.gd")
const SvgPath = preload("res://ui/icons/svg_path.gd")

@export var stat_id: String = "":
	set(value):
		stat_id = value
		queue_redraw()

## Tamaño del icono vectorial (16 px en el HUD).
@export var icon_size: int = T.STAT_ROW_ICON:
	set(value):
		icon_size = maxi(8, value)
		queue_redraw()
@export var stat_name: String = "Stat":
	set(value):
		stat_name = value
		queue_redraw()

@export var value_text: String = "0":
	set(value):
		value_text = value
		queue_redraw()

@export var dot_color: Color = T.TEXT_SECONDARY:
	set(value):
		dot_color = value
		queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(120, T.STAT_ROW_HEIGHT)


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


## Checks if the stat value represents zero (e.g. 0, "0%", "0 | 0%").
## Spec: "Cero: #7c8992" -> zero values are dimmed.
static func is_zero_value(text: String) -> bool:
	var clean := text.replace("%", "").replace("|", "").replace("/", "").replace(" ", "").strip_edges()
	if clean.is_empty():
		return true
	for ch in clean:
		if ch != '0' and ch != '.' and ch != ',':
			return false
	return true


## Clave canónica del Anexo A ("attack_damage" -> "dano").
func get_icon_key() -> String:
	return T.canonical_stat_key(stat_id)


## Capas vectoriales del icono (vacío = sin icono, se usa el punto de color).
func get_icon_layers() -> Array:
	return T.stat_icon_layers(stat_id) if stat_id != "" else []


func has_vector_icon() -> bool:
	return not get_icon_layers().is_empty()


func get_value_color() -> Color:
	return T.TEXT_ZERO if is_zero_value(value_text) else T.TEXT


func _draw() -> void:
	var h := T.STAT_ROW_HEIGHT
	var cy := h * 0.5
	var lead := T.STAT_DOT
	var layers := get_icon_layers()
	if layers.is_empty():
		draw_circle(Vector2(T.STAT_DOT * 0.5 + 1.0, cy), T.STAT_DOT * 0.5, dot_color)
	else:
		var side := float(icon_size)
		SvgPath.draw_layers(self, layers, Rect2(Vector2(0.0, floorf(cy - side * 0.5)), Vector2(side, side)))
		lead = side
	# Non-overlapping dedicated name column and tabular right-aligned value column
	var name_rect := Rect2(lead + 5.0, 0, size.x - lead - 47.0, h)
	var val_rect := Rect2(size.x - 45.0, 0, 42.0, h)
	D.draw_text_aligned(self, T.font("medium"), T.FS_STAT_NAME, name_rect, stat_name, T.TEXT_SECONDARY, HORIZONTAL_ALIGNMENT_LEFT)
	D.draw_text_aligned(self, T.font("bold"), T.FS_STAT_VALUE, val_rect, value_text, get_value_color(), HORIZONTAL_ALIGNMENT_RIGHT)
