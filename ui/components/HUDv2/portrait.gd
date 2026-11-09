@tool
extends Control
## HUDv2 portrait: XP ring (_draw arc), 84px inner circle and a 36x22 level
## pill filled with the accent colour.

const T = preload("res://ui/hud_tokens.gd")
const D = preload("res://ui/components/HUDv2/hud_draw.gd")

@export var level: int = 1:
	set(value):
		level = maxi(1, value)
		queue_redraw()

@export_range(0.0, 1.0, 0.001) var xp_fraction: float = 0.0:
	set(value):
		xp_fraction = clampf(value, 0.0, 1.0)
		queue_redraw()

@export var accent: Color = T.ACCENT_DEFAULT:
	set(value):
		accent = value
		queue_redraw()

## Optional champion picture; mapped into the inner circle with UVs.
@export var portrait_texture: Texture2D:
	set(value):
		portrait_texture = value
		queue_redraw()

## Displayed XP fraction, eased toward `xp_fraction` for smooth fills.
var _shown_xp: float = -1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(110, 122)


func _process(delta: float) -> void:
	if _shown_xp < 0.0 or Engine.is_editor_hint():
		_shown_xp = xp_fraction
		return
	if not is_equal_approx(_shown_xp, xp_fraction):
		# Level-up wraps (fraction dropped): snap; otherwise ease.
		_shown_xp = xp_fraction if xp_fraction < _shown_xp else move_toward(_shown_xp, xp_fraction, delta * 0.8)
		queue_redraw()


func get_ring_center() -> Vector2:
	return Vector2(size.x * 0.5, T.PORTRAIT_RING_RADIUS + 6.0)


func _draw() -> void:
	var c := get_ring_center()
	var shown := xp_fraction if _shown_xp < 0.0 else _shown_xp

	# Outer disc + XP track and progress.
	draw_circle(c, T.PORTRAIT_RING_RADIUS + T.PORTRAIT_RING_WIDTH * 0.5 + 2.0, T.SLOT_BG_DEEP)
	D.draw_ring(self, c, T.PORTRAIT_RING_RADIUS, T.PORTRAIT_RING_WIDTH, Color(1, 1, 1, 0.07))
	D.draw_ring(self, c, T.PORTRAIT_RING_RADIUS, T.PORTRAIT_RING_WIDTH, accent, 0.0, shown)
	if shown > 0.0 and shown < 1.0:
		var a := -PI * 0.5 + TAU * shown
		draw_circle(c + Vector2(cos(a), sin(a)) * T.PORTRAIT_RING_RADIUS, T.PORTRAIT_RING_WIDTH * 0.5, accent.lightened(0.35))

	# Inner circle (84 px).
	var r := T.PORTRAIT_INNER_DIAMETER * 0.5
	if portrait_texture:
		var pts := D.circle_points(c, r, 48)
		var uvs := PackedVector2Array()
		for p in pts:
			uvs.append((p - (c - Vector2(r, r))) / (r * 2.0))
		draw_polygon(pts, PackedColorArray([Color.WHITE]), uvs, portrait_texture)
	else:
		draw_circle(c, r, T.SLOT_BG)
		draw_circle(c, r - 6.0, T.SLOT_BG_DEEP.lerp(T.SLOT_BG, 0.5))
		D.draw_glyph(self, "user", c + Vector2(0, 2), r * 0.95, T.TEXT_DIM, 2.0)
	draw_arc(c, r, 0, TAU, 64, T.SLOT_BORDER, 1.5, true)

	# Level pill 36x22 in accent.
	var pill := Rect2(Vector2(c.x - T.LEVEL_PILL_SIZE.x * 0.5, c.y + T.PORTRAIT_RING_RADIUS - 11.0), T.LEVEL_PILL_SIZE)
	draw_style_box(T.box(T.SLOT_BG_DEEP, 12), pill.grow(2))
	draw_style_box(T.box(accent, 11), pill)
	D.draw_text_centered(self, T.font("bold"), T.FS_BODY + 1, pill, str(level), T.TEXT_DARK)
