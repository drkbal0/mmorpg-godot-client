@tool
extends Control
## HUDv2 inventory pieces. One drawable component with four variants:
##  - ITEM:    48x48 tile (radius 12) of the 3x2 grid, icon + stacks.
##  - TRINKET: 44px circle (amuleto) with eye glyph and charges badge.
##  - BUTTON:  small "B" (recall) / "P" (shop) buttons; emits `pressed`.
##  - GOLD:    34px tall gold box with coin, tabular amount and income ring.

signal pressed

const T = preload("res://ui/hud_tokens.gd")
const D = preload("res://ui/components/HUDv2/hud_draw.gd")

enum Kind { ITEM, TRINKET, BUTTON, GOLD }

@export var kind: Kind = Kind.ITEM:
	set(value):
		kind = value
		_apply_kind()
		queue_redraw()

## ITEM: slot number shown top-left (1-based). BUTTON: the hotkey letter.
@export var label: String = "":
	set(value):
		label = value
		queue_redraw()

@export var icon: Texture2D:
	set(value):
		icon = value
		queue_redraw()

## Glyph for BUTTON variant (recall / bag) or placeholder item glyph.
@export var glyph: String = "diamond":
	set(value):
		glyph = value
		queue_redraw()

@export var stacks: int = 0:
	set(value):
		stacks = maxi(0, value)
		queue_redraw()

## TRINKET charges.
@export var charges: int = 0:
	set(value):
		charges = maxi(0, value)
		queue_redraw()

## GOLD amount.
@export var amount: int = 0:
	set(value):
		amount = maxi(0, value)
		queue_redraw()

## GOLD passive-income ring progress (0..1).
@export_range(0.0, 1.0, 0.001) var income_fraction: float = 0.0:
	set(value):
		income_fraction = clampf(value, 0.0, 1.0)
		queue_redraw()

@export var accent: Color = T.ACCENT_DEFAULT:
	set(value):
		accent = value
		queue_redraw()

var _hover := false


func _ready() -> void:
	_apply_kind()


func _apply_kind() -> void:
	if kind == Kind.BUTTON:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	else:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	match kind:
		Kind.ITEM:
			custom_minimum_size = Vector2(T.ITEM_SIZE, T.ITEM_SIZE)
		Kind.TRINKET:
			custom_minimum_size = Vector2(T.TRINKET_DIAMETER, T.TRINKET_DIAMETER)
		Kind.BUTTON:
			custom_minimum_size = Vector2(40, 22)
		Kind.GOLD:
			custom_minimum_size = Vector2(160, T.GOLD_BOX_HEIGHT)


func has_item() -> bool:
	return icon != null or stacks > 0


func _gui_input(event: InputEvent) -> void:
	if kind != Kind.BUTTON:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		pressed.emit()
		accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_ENTER or what == NOTIFICATION_MOUSE_EXIT:
		_hover = what == NOTIFICATION_MOUSE_ENTER
		queue_redraw()


func _draw() -> void:
	match kind:
		Kind.ITEM:
			_draw_item()
		Kind.TRINKET:
			_draw_trinket()
		Kind.BUTTON:
			_draw_button()
		Kind.GOLD:
			_draw_gold()


func _draw_item() -> void:
	var tile := Rect2(Vector2.ZERO, Vector2(T.ITEM_SIZE, T.ITEM_SIZE))
	if not has_item():
		# Spec: "Ranura vacía: #0a0f13 + borde blanco al 6% de 1px."
		draw_style_box(T.box(T.SLOT_EMPTY, T.ITEM_RADIUS, 1, T.SLOT_EMPTY_BORDER), tile)
		if label != "":
			draw_string(T.font("bold"), Vector2(6, 13), label, HORIZONTAL_ALIGNMENT_LEFT, -1, T.FS_TINY, T.TEXT_KEY)
		return
	draw_style_box(T.box(Color("#1f3b63"), T.ITEM_RADIUS, 1, Color("#3c6aa8")), tile)
	if icon:
		var inner := tile.grow(-5)
		draw_texture_rect(icon, inner, false)
	else:
		D.draw_glyph(self, glyph, tile.get_center(), 22.0, T.TEXT, 2.0)
	if label != "":
		draw_string(T.font("bold"), Vector2(6, 13), label, HORIZONTAL_ALIGNMENT_LEFT, -1, T.FS_TINY, T.TEXT_KEY)
	if stacks > 1:
		var r := Rect2(0, T.ITEM_SIZE - 17, T.ITEM_SIZE - 5, 14)
		var font := T.font("bold")
		var y := D.baseline_for_center(font, T.FS_BODY, r.get_center().y)
		draw_string(font, Vector2(r.position.x, y + 1), str(stacks), HORIZONTAL_ALIGNMENT_RIGHT, r.size.x, T.FS_BODY, Color(0, 0, 0, 0.6))
		draw_string(font, Vector2(r.position.x, y), str(stacks), HORIZONTAL_ALIGNMENT_RIGHT, r.size.x, T.FS_BODY, T.TEXT)


func _draw_trinket() -> void:
	var r := T.TRINKET_DIAMETER * 0.5
	var c := Vector2(r, r)
	var has_charges := charges > 0
	draw_circle(c, r, T.SLOT_NEUTRAL)
	draw_arc(c, r - 1.0, 0, TAU, 48, accent if has_charges else T.SLOT_BORDER, 2.0, true)
	D.draw_glyph(self, "eye", c, 20.0, T.GOLD if has_charges else T.TEXT_MUTED, 2.0)
	# Charges badge (top-right, overflowing the circle).
	var bc := c + Vector2(r * 0.78, -r * 0.78)
	draw_circle(bc, 9.0, T.WELL)
	draw_circle(bc, 7.5, accent if has_charges else T.SLOT_BORDER)
	D.draw_text_centered(self, T.font("bold"), T.FS_TINY, Rect2(bc - Vector2(8, 8), Vector2(16, 16)), str(charges), T.TEXT_DARK)
	# Slot number under the circle-left like the grid's 4th column.
	if label != "":
		draw_string(T.font("bold"), Vector2(-9, T.TRINKET_DIAMETER + 1), label, HORIZONTAL_ALIGNMENT_LEFT, -1, T.FS_TINY, T.TEXT_KEY)


func _draw_button() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	# Spec: "Botón: #18242b + borde blanco al 8%." "Radios: ... botón 8"
	var border := accent if _hover else T.BUTTON_BORDER
	draw_style_box(T.box(T.BUTTON_BG, T.BUTTON_RADIUS, 1, border), rect)
	D.draw_glyph(self, glyph, Vector2(13, rect.size.y * 0.5), 11.0, accent, 1.6)
	D.draw_text_aligned(self, T.font("bold"), T.FS_SMALL, Rect2(21, 0, rect.size.x - 23, rect.size.y), label, T.TEXT_KEY, HORIZONTAL_ALIGNMENT_LEFT)


func _draw_gold() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	# Spec: "caja oro 10", "Oro: #f5c35b", "Pozo: #070a0c"
	draw_style_box(T.box(T.WELL, T.GOLD_BOX_RADIUS, 1, Color(T.GOLD, 0.35)), rect)
	var cy := rect.size.y * 0.5
	D.draw_glyph(self, "coin", Vector2(17, cy), 12.0, T.GOLD, 2.0)
	var font := T.font("bold")
	draw_string(font, Vector2(31, D.baseline_for_center(font, T.FS_GOLD, cy)), str(amount), HORIZONTAL_ALIGNMENT_LEFT, -1, T.FS_GOLD, T.GOLD)
	# Passive income ring on the right.
	var rc := Vector2(rect.size.x - 18, cy)
	D.draw_ring(self, rc, 8.0, 3.0, Color(1, 1, 1, 0.08))
	D.draw_ring(self, rc, 8.0, 3.0, accent, 0.0, income_fraction)
