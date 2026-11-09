@tool
extends Control
## HUDv2 ability slot: 62x62 tile (radius 14, 2px accent border), key label,
## vector icon, rank pips, mana cost (9x12 drop + number) and a radial
## cooldown overlay. Control size is 62x100 (tile + pips + cost).

const T = preload("res://ui/hud_tokens.gd")
const D = preload("res://ui/components/HUDv2/hud_draw.gd")

@export var key_label: String = "Q":
	set(value):
		key_label = value
		queue_redraw()

@export_enum("slash", "shield", "dash", "star", "target", "diamond") var icon_kind: String = "slash":
	set(value):
		icon_kind = value
		queue_redraw()

@export var rank: int = 1:
	set(value):
		rank = maxi(0, value)
		queue_redraw()

@export var max_rank: int = 5:
	set(value):
		max_rank = maxi(1, value)
		queue_redraw()

@export var cost: int = 0:
	set(value):
		cost = maxi(0, value)
		queue_redraw()

@export var locked: bool = false:
	set(value):
		locked = value
		queue_redraw()

@export var unlock_level: int = 6:
	set(value):
		unlock_level = value
		queue_redraw()

@export var accent: Color = T.ACCENT_DEFAULT:
	set(value):
		accent = value
		queue_redraw()

## Remaining cooldown seconds (ticks down on its own).
var cooldown: float = 0.0
## Total of the current cooldown, used for the radial fraction.
var cooldown_total: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(T.ABILITY_SIZE, 100)


## Starts / syncs the cooldown. A value larger than the remaining time starts a
## new cooldown (and becomes the total); a smaller one just re-syncs.
func set_cooldown(seconds: float) -> void:
	seconds = maxf(0.0, seconds)
	if seconds > cooldown + 0.05 or cooldown_total <= 0.0:
		cooldown_total = seconds
	cooldown = seconds
	queue_redraw()


func get_cooldown_fraction() -> float:
	if cooldown_total <= 0.0:
		return 0.0
	return clampf(cooldown / cooldown_total, 0.0, 1.0)


func is_ready() -> bool:
	return not locked and rank > 0 and cooldown <= 0.0


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or cooldown <= 0.0:
		return
	cooldown = maxf(0.0, cooldown - delta)
	if cooldown <= 0.0:
		cooldown_total = 0.0
	queue_redraw()


func _draw() -> void:
	var tile := Rect2(Vector2.ZERO, Vector2(T.ABILITY_SIZE, T.ABILITY_SIZE))
	var learned := rank > 0 and not locked

	# Tile background + border.
	# Spec: "Tile habilidad lista: #1c2a33. Bloqueada: #11181d. Neutro (pasiva/retrato): #1a252c."
	var border_color := accent if learned else (T.SLOT_BORDER if locked else Color(accent, 0.35))
	var bg := T.SLOT_LOCKED if locked else (T.SLOT_READY if learned else T.SLOT_NEUTRAL)
	draw_style_box(T.box(bg, T.ABILITY_RADIUS, T.ABILITY_BORDER, border_color), tile)
	if learned:
		# Inner sheen.
		draw_style_box(T.box(Color(accent, 0.07), T.ABILITY_RADIUS - 3), tile.grow(-4))

	# Icon.
	var icon_color := T.TEXT if learned else T.TEXT_MUTED
	var icon_center := tile.get_center() + (Vector2(0, -5) if locked else Vector2.ZERO)
	D.draw_glyph(self, icon_kind, icon_center, 24.0, icon_color, 2.2)
	if locked:
		D.draw_text_centered(self, T.font("semibold"), T.FS_SMALL, Rect2(0, 38, T.ABILITY_SIZE, 16), "Nv. %d" % unlock_level, T.TEXT_SECONDARY)

	# Cooldown overlay + seconds.
	var frac := get_cooldown_fraction()
	if frac > 0.0 and not locked:
		D.draw_cooldown(self, tile.grow(-T.ABILITY_BORDER), T.ABILITY_RADIUS - T.ABILITY_BORDER, frac, T.COOLDOWN_OVERLAY)
		var txt := ("%.1f" % cooldown) if cooldown < 1.0 else str(ceili(cooldown))
		D.draw_text_centered(self, T.font("bold"), T.FS_COOLDOWN, tile, txt, T.TEXT, true)

	# Key label (top-left) - Spec: "Letra tecla: #c3ccd3".
	draw_string(T.font("bold"), Vector2(7, 14), key_label, HORIZONTAL_ALIGNMENT_LEFT, -1, T.FS_SMALL, T.TEXT_KEY)

	# Rank pips.
	var gap := 3.0
	var pip_w := (T.ABILITY_SIZE - 8.0 - gap * float(max_rank - 1)) / float(max_rank)
	for i in max_rank:
		var pip := Rect2(4.0 + i * (pip_w + gap), 68.0, pip_w, 4.0)
		var on := i < rank and not locked
		draw_style_box(T.box(accent if on else Color(1, 1, 1, 0.10), 2), pip)

	# Mana cost: drop 9x12 + number, centred under the tile.
	if cost > 0:
		var font := T.font("semibold")
		var txt := str(cost)
		var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, T.FS_BODY).x
		var total := T.COST_DROP_SIZE.x + 4.0 + tw
		var x0 := (T.ABILITY_SIZE - total) * 0.5
		var cy := 87.0
		draw_colored_polygon(D.drop_points(Vector2(x0 + T.COST_DROP_SIZE.x * 0.5, cy), T.COST_DROP_SIZE), T.MANA_COST)
		draw_string(font, Vector2(x0 + T.COST_DROP_SIZE.x + 4.0, D.baseline_for_center(font, T.FS_BODY, cy)), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, T.FS_BODY, T.TEXT)
