@tool
extends Control
## HUDv2 feed line: rounded pill with "04:21  Player [Champion] text". Item
## announcements render the text in gold. Fades out after FEED_LIFETIME.

const T = preload("res://ui/hud_tokens.gd")
const D = preload("res://ui/components/HUDv2/hud_draw.gd")

const PAD_X := 9.0
const GAP := 6.0

var time_text: String = ""
var player: String = ""
var champion: String = ""
var text: String = ""
var is_item: bool = false
## Seconds before the line starts fading; <= 0 disables auto-expiry.
var lifetime: float = T.FEED_LIFETIME

var _age: float = 0.0
var _parts: Array[Dictionary] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_layout()


func setup(p_time: String, p_player: String, p_champion: String, p_text: String, p_is_item: bool) -> void:
	time_text = p_time
	player = p_player
	champion = p_champion
	text = p_text
	is_item = p_is_item
	_age = 0.0
	modulate.a = 1.0
	_layout()


func _layout() -> void:
	_parts.clear()
	if time_text != "":
		_parts.append({"t": time_text, "font": "medium", "color": T.TEXT_DIM})
	if player != "":
		_parts.append({"t": player, "font": "bold", "color": T.ALLY})
	if champion != "":
		_parts.append({"t": "[%s]" % champion, "font": "regular", "color": T.TEXT_DIM})
	if text != "":
		_parts.append({"t": text, "font": "medium", "color": T.GOLD_TEXT if is_item else T.TEXT})
	var x := PAD_X
	for p in _parts:
		var w: float = T.font(p.font).get_string_size(p.t, HORIZONTAL_ALIGNMENT_LEFT, -1, T.FS_FEED).x
		p["x"] = x
		x += w + GAP
	var width := x - GAP + PAD_X if not _parts.is_empty() else PAD_X * 2.0
	custom_minimum_size = Vector2(ceilf(width), T.FEED_LINE_HEIGHT)
	size = custom_minimum_size
	queue_redraw()


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or lifetime <= 0.0:
		return
	_age += delta
	if _age > lifetime:
		modulate.a = clampf(1.0 - (_age - lifetime) / T.FEED_FADE, 0.0, 1.0)
		if modulate.a <= 0.0:
			queue_free()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, custom_minimum_size)
	draw_style_box(T.box(T.FEED_BG, int(rect.size.y * 0.5), 1, Color(1, 1, 1, 0.06)), rect)
	var cy := rect.size.y * 0.5
	for p in _parts:
		var f: Font = T.font(p.font)
		draw_string(f, Vector2(p.x, D.baseline_for_center(f, T.FS_FEED, cy)), p.t, HORIZONTAL_ALIGNMENT_LEFT, -1, T.FS_FEED, p.color)
