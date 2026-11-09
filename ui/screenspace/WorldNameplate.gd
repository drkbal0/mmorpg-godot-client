extends Control
class_name WorldNameplate

## WorldNameplate.gd - Screen-Space 2D Vector Nameplate with 100 HP Segmented Bars
## Renders at native display resolution with smooth damage trailing and class/status badges.

@onready var title_label: Label = $VBoxContainer/TitleLabel
@onready var name_label: Label = $VBoxContainer/NameLabel
@onready var hp_bar_bg: Panel = $VBoxContainer/BarContainer/HPBarBG
@onready var hp_bar_ghost: ProgressBar = $VBoxContainer/BarContainer/HPBarGhost
@onready var hp_bar_main: ProgressBar = $VBoxContainer/BarContainer/HPBarMain
@onready var ticks_overlay: Control = $VBoxContainer/BarContainer/TicksOverlay

var max_health: float = 1000.0
var current_health: float = 1000.0
var is_hostile_unit: bool = false
var _previous_hp_percent: float = 100.0

func _ready() -> void:
	custom_minimum_size = Vector2(180, 50)
	size = custom_minimum_size
	ticks_overlay.draw.connect(_on_draw_ticks)

func setup(p_name: String, p_hp: float, p_max_hp: float, is_hostile: bool = false, p_title: String = "") -> void:
	is_hostile_unit = is_hostile
	max_health = maxf(p_max_hp, 1.0)
	current_health = clampf(p_hp, 0.0, max_health)
	_previous_hp_percent = (current_health / max_health) * 100.0

	name_label.text = p_name
	if is_hostile_unit:
		name_label.modulate = Color(1.0, 0.35, 0.35)
	else:
		name_label.modulate = Color(0.9, 0.95, 1.0)

	if not p_title.is_empty():
		title_label.text = p_title
		title_label.visible = true
	else:
		title_label.visible = false

	# Apply theme colors
	_apply_bar_colors()

	hp_bar_main.value = _previous_hp_percent
	hp_bar_ghost.value = _previous_hp_percent
	ticks_overlay.queue_redraw()

func _apply_bar_colors() -> void:
	var main_sb = hp_bar_main.get_theme_stylebox("fill")
	if main_sb is StyleBoxFlat:
		main_sb = main_sb.duplicate()
	else:
		main_sb = StyleBoxFlat.new()

	if is_hostile_unit:
		main_sb.bg_color = Color(0.95, 0.25, 0.25) # Crimson Red
	else:
		main_sb.bg_color = Color(0.18, 0.82, 0.45) # Emerald Green

	main_sb.corner_radius_top_left = 2
	main_sb.corner_radius_top_right = 2
	main_sb.corner_radius_bottom_left = 2
	main_sb.corner_radius_bottom_right = 2
	hp_bar_main.add_theme_stylebox_override("fill", main_sb)

func update_hp(new_hp: float, new_max: float = -1.0) -> void:
	if new_max > 0.0:
		max_health = new_max
	current_health = clampf(new_hp, 0.0, max_health)
	var new_percent = (current_health / max_health) * 100.0
	var old_percent = _previous_hp_percent
	_previous_hp_percent = new_percent

	var tween = create_tween()
	if new_percent < old_percent:
		# Taking damage: Main bar drops instantly, ghost catches up smoothly
		hp_bar_main.value = new_percent
		tween.tween_interval(0.2)
		tween.tween_property(hp_bar_ghost, "value", new_percent, 0.35).set_trans(Tween.TRANS_SINE)
	else:
		# Healing: Ghost jumps up instantly, main bar fills smoothly
		hp_bar_ghost.value = new_percent
		tween.tween_interval(0.1)
		tween.tween_property(hp_bar_main, "value", new_percent, 0.35).set_trans(Tween.TRANS_SINE)

	ticks_overlay.queue_redraw()

func _on_draw_ticks() -> void:
	if max_health <= 0.0:
		return

	var bar_w = ticks_overlay.size.x
	var bar_h = ticks_overlay.size.y
	var segment_value = 100.0 # 100 HP per tick
	var total_segments = int(max_health / segment_value)

	if total_segments <= 1 or total_segments > 60:
		return

	var tick_col = Color(0.05, 0.08, 0.12, 0.85) # High-contrast separator
	for i in range(1, total_segments):
		var frac = float(i) / float(total_segments)
		var x = frac * bar_w
		ticks_overlay.draw_line(Vector2(x, 0), Vector2(x, bar_h), tick_col, 1.5)
