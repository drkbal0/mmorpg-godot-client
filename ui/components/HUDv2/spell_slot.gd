@tool
extends Control
## HUDv2 spell slot: 46x46 tile (radius 12). Either the passive (round glyph +
## "PASIVA" caption) or a summoner spell D/F with radial cooldown and
## "en espera" caption. Control size is 46x70.

const T = preload("res://ui/tokens/hud_tokens.gd")
const D = preload("res://ui/components/HUDv2/hud_draw.gd")

@export var is_passive: bool = false:
	set(value):
		is_passive = value
		queue_redraw()

@export var key_label: String = "D":
	set(value):
		key_label = value
		queue_redraw()

@export var tint: Color = T.SPELL_D_TINT:
	set(value):
		tint = value
		queue_redraw()

@export_enum("target", "diamond", "star", "dash", "shield", "slash") var icon_kind: String = "target":
	set(value):
		icon_kind = value
		queue_redraw()

@export var accent: Color = T.ACCENT_DEFAULT:
	set(value):
		accent = value
		queue_redraw()

var cooldown: float = 0.0
var cooldown_total: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(T.SPELL_SIZE, 70)


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


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or cooldown <= 0.0:
		return
	cooldown = maxf(0.0, cooldown - delta)
	if cooldown <= 0.0:
		cooldown_total = 0.0
	queue_redraw()


func _draw() -> void:
	var tile := Rect2(Vector2.ZERO, Vector2(T.SPELL_SIZE, T.SPELL_SIZE))
	var caption_rect := Rect2(-12, 52, T.SPELL_SIZE + 24, 14)

	if is_passive:
		# Spec: "Neutro (pasiva/retrato): #1a252c"
		draw_style_box(T.box(T.SLOT_NEUTRAL, T.SPELL_RADIUS, 1, T.SLOT_BORDER), tile)
		draw_circle(tile.get_center(), 14.0, T.WELL)
		D.draw_glyph(self, icon_kind, tile.get_center(), 18.0, T.TEXT, 2.0)
		D.draw_text_centered(self, T.font("header"), T.FS_TINY, caption_rect, "PASIVA", T.TEXT_SECONDARY)
		return

	var on_cd := cooldown > 0.0
	draw_style_box(T.box(tint, T.SPELL_RADIUS, 1, T.SLOT_BORDER if on_cd else Color(accent, 0.6)), tile)
	if on_cd:
		D.draw_cooldown(self, tile.grow(-1), T.SPELL_RADIUS - 1, get_cooldown_fraction(), T.COOLDOWN_OVERLAY)
		D.draw_text_centered(self, T.font("bold"), T.FS_COOLDOWN, tile.grow_individual(0, -4, 0, 0), str(ceili(cooldown)), T.TEXT, true)
		D.draw_text_centered(self, T.font("medium"), T.FS_SMALL, caption_rect, "en espera", T.TEXT_SECONDARY)
	else:
		D.draw_glyph(self, icon_kind, tile.get_center() + Vector2(0, 2), 18.0, T.TEXT, 2.0)
		D.draw_text_centered(self, T.font("medium"), T.FS_SMALL, caption_rect, "listo", Color(accent, 0.85))
	# Spec: "Letra tecla: #c3ccd3"
	draw_string(T.font("bold"), Vector2(6, 13), key_label, HORIZONTAL_ALIGNMENT_LEFT, -1, T.FS_TINY, T.TEXT_KEY)
