@tool
extends Control
## HUDv2 inventory pieces. One drawable component with four variants:
##  - ITEM:    48x48 tile (radius 12) of the 3x2 grid, icon + stacks.
##  - TRINKET: 44px circle (amuleto) with eye glyph and charges badge.
##  - BUTTON:  small "B" (recall) / "P" (shop) buttons; emits `pressed`.
##  - GOLD:    34px tall gold box with coin, tabular amount and income ring.

signal pressed
signal item_assigned(slot_idx: int, item_name: String, item_id: String)
signal item_used(slot_idx: int, item_name: String, item_id: String)
signal item_cleared(slot_idx: int)

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
		_update_tooltip()
		queue_redraw()

@export var icon: Texture2D:
	set(value):
		icon = value
		queue_redraw()

@export var item_name: String = ""
@export var item_id: String = ""
@export var cooldown_remaining: float = 0.0
@export var cooldown_total: float = 0.0

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
	if kind == Kind.BUTTON or kind == Kind.ITEM:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	else:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	match kind:
		Kind.ITEM:
			custom_minimum_size = Vector2(T.ITEM_SIZE, T.ITEM_SIZE)
			_update_tooltip()
		Kind.TRINKET:
			custom_minimum_size = Vector2(T.TRINKET_DIAMETER, T.TRINKET_DIAMETER)
		Kind.BUTTON:
			custom_minimum_size = Vector2(40, 22)
		Kind.GOLD:
			custom_minimum_size = Vector2(160, T.GOLD_BOX_HEIGHT)


func has_item() -> bool:
	return icon != null or stacks > 0 or item_name != ""


func _process(delta: float) -> void:
	if kind == Kind.ITEM and cooldown_remaining > 0.0 and not Engine.is_editor_hint():
		cooldown_remaining = maxf(0.0, cooldown_remaining - delta)
		if cooldown_remaining <= 0.0 and stacks <= 0:
			clear_item()
		queue_redraw()


func _can_drop_data(_pos: Vector2, data: Variant) -> bool:
	if kind != Kind.ITEM:
		return false
	if data is Dictionary and data.get("type") == "inventory_item":
		var node = data.get("item_node")
		return is_instance_valid(node)
	return false


func _drop_data(_pos: Vector2, data: Variant) -> void:
	if not _can_drop_data(_pos, data):
		return
	var node = data.get("item_node")
	if not is_instance_valid(node):
		return
	var d_name: String = "Objeto"
	if node.get("item_name") != null:
		d_name = str(node.get("item_name"))
	elif node.has_meta("item_name"):
		d_name = str(node.get_meta("item_name"))
	
	var d_tex: Texture2D = null
	if node.get("texture") != null:
		d_tex = node.get("texture") as Texture2D
	elif node.has_meta("texture"):
		d_tex = node.get_meta("texture") as Texture2D
		
	var d_qty: int = 1
	if node.get("quantity") != null:
		d_qty = int(node.get("quantity"))
	elif node.has_meta("quantity"):
		d_qty = int(node.get_meta("quantity"))
		
	var d_id: String = ""
	if node.get("item_id") != null:
		d_id = str(node.get("item_id"))
	elif node.has_meta("item_id"):
		d_id = str(node.get_meta("item_id"))
		
	assign_item(d_name, d_tex, d_qty, d_id)


func assign_item(p_name: String, p_icon: Texture2D, p_stacks: int, p_id: String = "") -> void:
	item_name = p_name
	icon = p_icon
	stacks = p_stacks
	item_id = p_id
	_update_tooltip()
	queue_redraw()
	var idx := 0
	if label.is_valid_int():
		idx = label.to_int() - 1
	item_assigned.emit(idx, item_name, item_id)


func clear_item() -> void:
	item_name = ""
	icon = null
	stacks = 0
	item_id = ""
	cooldown_remaining = 0.0
	_update_tooltip()
	queue_redraw()
	var idx := 0
	if label.is_valid_int():
		idx = label.to_int() - 1
	item_cleared.emit(idx)


func use_item() -> bool:
	if not has_item() or cooldown_remaining > 0.0:
		return false
	var idx := 0
	if label.is_valid_int():
		idx = label.to_int() - 1
	item_used.emit(idx, item_name, item_id)
	start_cooldown(15.0)
	if stacks > 1:
		stacks -= 1
		_update_tooltip()
		queue_redraw()
	else:
		stacks = 0
		_update_tooltip()
		queue_redraw()
	return true


func start_cooldown(seconds: float) -> void:
	cooldown_total = maxf(0.1, seconds)
	cooldown_remaining = seconds
	queue_redraw()


func _update_tooltip() -> void:
	if kind != Kind.ITEM:
		return
	if has_item():
		tooltip_text = "%s (x%d)\n[Tecla %s o Clic para usar]\n[Clic derecho para desasignar]" % [item_name if item_name != "" else "Objeto", stacks, label]
	else:
		tooltip_text = "Ranura rápida [%s]\nArrastra consumibles desde el Inventario [I]" % label


func _gui_input(event: InputEvent) -> void:
	if kind == Kind.BUTTON:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			pressed.emit()
			accept_event()
	elif kind == Kind.ITEM:
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_LEFT:
				if has_item():
					use_item()
					accept_event()
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				if has_item():
					clear_item()
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
		var empty_border: Color = Color(accent, 0.4) if _hover else T.SLOT_EMPTY_BORDER
		draw_style_box(T.box(T.SLOT_EMPTY, T.ITEM_RADIUS, 1, empty_border), tile)
		if label != "":
			draw_string(T.font("bold"), Vector2(6, 13), label, HORIZONTAL_ALIGNMENT_LEFT, -1, T.FS_TINY, T.TEXT_KEY)
		return
	var border_col: Color = Color(accent, 0.7) if _hover else Color("#3c6aa8")
	draw_style_box(T.box(Color("#1f3b63"), T.ITEM_RADIUS, 1, border_col), tile)
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
	if cooldown_remaining > 0.0:
		var frac := clampf(cooldown_remaining / cooldown_total, 0.0, 1.0)
		D.draw_cooldown(self, tile.grow(-1), T.ITEM_RADIUS - 1, frac, T.COOLDOWN_OVERLAY)
		var cd_str := str(ceili(cooldown_remaining)) if cooldown_remaining >= 1.0 else "%.1f" % cooldown_remaining
		D.draw_text_centered(self, T.font("bold"), T.FS_BODY, tile, cd_str, T.TEXT, true)


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
