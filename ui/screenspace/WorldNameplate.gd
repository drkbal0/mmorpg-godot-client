extends Control
class_name WorldNameplate

## WorldNameplate.gd - League of Legends & Solo Leveling Screen-Space Nameplate
## Features:
## - Left-side Level Badge (LoL / Solo Leveling style shield/box)
## - 100 HP minor ticks, 500 HP medium ticks, and 1000 HP major block separators ("cuadros")
## - Thin Resource/Mana bar underneath
## - Dual-layer damage response: instant drop + smooth orange ghost trailing
## - Hit flash on heavy/critical damage
## - High-contrast crisp typography (crisp outline, zero blur)
## - Background dimming support for modal menus

@onready var title_label: Label = $VBoxContainer/TitleLabel
@onready var name_label: Label = $VBoxContainer/NameLabel
@onready var level_badge: PanelContainer = $VBoxContainer/HealthFrame/LevelBadge
@onready var level_label: Label = $VBoxContainer/HealthFrame/LevelBadge/LevelLabel
@onready var hp_bar_bg: Panel = $VBoxContainer/HealthFrame/BarsVBox/HPStack/HPBarBG
@onready var hp_bar_ghost: ProgressBar = $VBoxContainer/HealthFrame/BarsVBox/HPStack/HPBarGhost
@onready var hp_bar_main: ProgressBar = $VBoxContainer/HealthFrame/BarsVBox/HPStack/HPBarMain
@onready var gloss_layer: ColorRect = $VBoxContainer/HealthFrame/BarsVBox/HPStack/GlossLayer
@onready var ticks_overlay: Control = $VBoxContainer/HealthFrame/BarsVBox/HPStack/TicksOverlay
@onready var resource_bar: ColorRect = $VBoxContainer/HealthFrame/BarsVBox/ResourceBar

var max_health: float = 1000.0
var current_health: float = 1000.0
var is_hostile_unit: bool = false
var unit_level: int = 1
var is_dead: bool = false
var _previous_hp_percent: float = 100.0
var _bg_opacity: float = 1.0


func _ensure_node_refs() -> void:
	if title_label == null:
		title_label = get_node_or_null("VBoxContainer/TitleLabel")
	if name_label == null:
		name_label = get_node_or_null("VBoxContainer/NameLabel")
	if level_badge == null:
		level_badge = get_node_or_null("VBoxContainer/HealthFrame/LevelBadge")
	if level_label == null:
		level_label = get_node_or_null("VBoxContainer/HealthFrame/LevelBadge/LevelLabel")
	if hp_bar_bg == null:
		hp_bar_bg = get_node_or_null("VBoxContainer/HealthFrame/BarsVBox/HPStack/HPBarBG")
	if hp_bar_ghost == null:
		hp_bar_ghost = get_node_or_null("VBoxContainer/HealthFrame/BarsVBox/HPStack/HPBarGhost")
	if hp_bar_main == null:
		hp_bar_main = get_node_or_null("VBoxContainer/HealthFrame/BarsVBox/HPStack/HPBarMain")
	if gloss_layer == null:
		gloss_layer = get_node_or_null("VBoxContainer/HealthFrame/BarsVBox/HPStack/GlossLayer")
	if ticks_overlay == null:
		ticks_overlay = get_node_or_null("VBoxContainer/HealthFrame/BarsVBox/HPStack/TicksOverlay")
	if resource_bar == null:
		resource_bar = get_node_or_null("VBoxContainer/HealthFrame/BarsVBox/ResourceBar")


func _ready() -> void:
	_ensure_node_refs()
	custom_minimum_size = Vector2(210, 52)
	size = custom_minimum_size
	if ticks_overlay and not ticks_overlay.draw.is_connected(_on_draw_ticks):
		ticks_overlay.draw.connect(_on_draw_ticks)


func setup(p_name: String, p_hp: float, p_max_hp: float, is_hostile: bool = false, p_title: String = "", p_level: int = 1) -> void:
	_ensure_node_refs()
	is_hostile_unit = is_hostile
	unit_level = maxi(p_level, 1)
	max_health = maxf(p_max_hp, 1.0)
	current_health = clampf(p_hp, 0.0, max_health)
	_previous_hp_percent = (current_health / max_health) * 100.0

	if name_label:
		name_label.text = p_name
		if is_hostile_unit:
			name_label.modulate = Color(1.0, 0.45, 0.45) # Crisp Crimson
		else:
			name_label.modulate = Color(0.95, 0.98, 1.0) # Crisp White

	if level_label:
		level_label.text = str(unit_level)
		if is_hostile_unit:
			level_label.modulate = Color(1.0, 0.4, 0.4)
		else:
			level_label.modulate = Color(0.3, 0.85, 1.0) # Cyan Pioneer glow

	if title_label:
		if not p_title.is_empty():
			title_label.text = p_title
			title_label.visible = true
			if is_hostile_unit:
				title_label.modulate = Color(1.0, 0.3, 0.3, 0.9)
			else:
				title_label.modulate = Color(0.4, 0.85, 1.0, 0.95)
		else:
			title_label.visible = false

	# Apply theme colors
	_apply_bar_colors()

	if hp_bar_main:
		hp_bar_main.value = _previous_hp_percent
	if hp_bar_ghost:
		hp_bar_ghost.value = _previous_hp_percent
	if resource_bar:
		resource_bar.visible = not is_hostile_unit # Only friendly / player shows mana
	if ticks_overlay:
		ticks_overlay.queue_redraw()

	# If dead (0 HP), fade out and hide smoothly
	var cur_pct = (current_health / max_health) * 100.0
	if cur_pct <= 0.0:
		is_dead = true
		visible = false
		modulate.a = 0.0
	else:
		is_dead = false
		if not visible:
			visible = true
			modulate.a = _bg_opacity


## Fase 9.7 (ADR 100): estado abatido. A diferencia de la muerte (0 HP oculta la
## placa), un aliado abatido sigue visible con su cuenta de sangrado "ABATIDO 18s".
var is_downed: bool = false

static func format_downed(bleedout_sec: float) -> String:
	return "ABATIDO %ds" % int(ceil(maxf(bleedout_sec, 0.0)))


func set_downed(bleedout_sec: float) -> void:
	_ensure_node_refs()
	is_downed = true
	is_dead = false
	current_health = 0.0
	_previous_hp_percent = 0.0
	visible = true
	modulate.a = _bg_opacity
	if hp_bar_main:
		hp_bar_main.value = 0.0
	if hp_bar_ghost:
		hp_bar_ghost.value = 0.0
	if title_label:
		title_label.text = format_downed(bleedout_sec)
		title_label.visible = true
		title_label.modulate = Color(1.0, 0.32, 0.32, 1.0)
	if name_label:
		name_label.modulate = Color(1.0, 0.75, 0.75)


func _apply_bar_colors() -> void:
	_ensure_node_refs()
	if hp_bar_main == null:
		return

	var main_sb = hp_bar_main.get_theme_stylebox("fill")
	if main_sb is StyleBoxFlat:
		main_sb = main_sb.duplicate()
	else:
		main_sb = StyleBoxFlat.new()

	if is_hostile_unit:
		main_sb.bg_color = Color(0.88, 0.18, 0.18) # LoL Crimson Enemy Red
	else:
		main_sb.bg_color = Color(0.12, 0.78, 0.42) # LoL Emerald Ally Green

	main_sb.corner_radius_top_left = 1
	main_sb.corner_radius_top_right = 1
	main_sb.corner_radius_bottom_left = 1
	main_sb.corner_radius_bottom_right = 1
	hp_bar_main.add_theme_stylebox_override("fill", main_sb)

	if hp_bar_ghost:
		var ghost_sb = hp_bar_ghost.get_theme_stylebox("fill")
		if ghost_sb is StyleBoxFlat:
			ghost_sb = ghost_sb.duplicate()
		else:
			ghost_sb = StyleBoxFlat.new()
		ghost_sb.bg_color = Color(0.98, 0.55, 0.15) # LoL Damage Orange Ghost
		hp_bar_ghost.add_theme_stylebox_override("fill", ghost_sb)


func update_hp(new_hp: float, new_max: float = -1.0, is_crit: bool = false) -> void:
	_ensure_node_refs()
	if new_max > 0.0:
		max_health = new_max
	current_health = clampf(new_hp, 0.0, max_health)
	var new_percent = (current_health / max_health) * 100.0
	var old_percent = _previous_hp_percent
	_previous_hp_percent = new_percent

	if not is_inside_tree():
		if hp_bar_main: hp_bar_main.value = new_percent
		if hp_bar_ghost: hp_bar_ghost.value = new_percent
		return

	var tween = create_tween()
	if new_percent < old_percent:
		# Taking damage: main bar drops instantly, ghost trails smoothly
		if hp_bar_main:
			hp_bar_main.value = new_percent

			# Critical hit flash effect (flash white-gold then back to base)
			if is_crit or (old_percent - new_percent) > 15.0:
				var flash_tween = create_tween()
				hp_bar_main.modulate = Color(2.0, 2.0, 1.8) # Intense HDR hit flash
				flash_tween.tween_property(hp_bar_main, "modulate", Color.WHITE, 0.18)

		if hp_bar_ghost:
			tween.tween_interval(0.25)
			tween.tween_property(hp_bar_ghost, "value", new_percent, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	else:
		# Healing: ghost bar instantly updates, main bar fills up
		if hp_bar_ghost:
			hp_bar_ghost.value = new_percent
		if hp_bar_main:
			tween.tween_property(hp_bar_main, "value", new_percent, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	if ticks_overlay:
		ticks_overlay.queue_redraw()

	# If dead (0 HP), fade out and hide smoothly
	var cur_pct = (current_health / max_health) * 100.0
	if cur_pct <= 0.0:
		is_dead = true
		visible = false
		modulate.a = 0.0
	else:
		is_dead = false
		if not visible:
			visible = true
			modulate.a = _bg_opacity


## Sets background opacity when menus / modals are open
func set_dim_opacity(alpha: float) -> void:
	_bg_opacity = clampf(alpha, 0.0, 1.0)
	modulate.a = _bg_opacity


## Renders LoL-style health bar ticks:
## - 100 HP minor tick: thin black line (1px, 45% height)
## - 500 HP medium tick: medium black line (2px, 70% height)
## - 1000 HP major separator: thick black line (3px, 100% height) -> creates the iconic LoL "cuadros"
func _on_draw_ticks() -> void:
	if max_health <= 0.0 or ticks_overlay == null:
		return

	var bar_w = ticks_overlay.size.x
	var bar_h = ticks_overlay.size.y
	if bar_w <= 1.0 or bar_h <= 1.0:
		return

	# Paso adaptativo: 100 HP por defecto; si los ticks quedarían a < 3 px
	# (p. ej. un World Boss de 100k HP) se escala x10 para no ennegrecer la barra.
	var hp_step = 100.0
	while hp_step < max_health and (hp_step / max_health) * bar_w < 3.0:
		hp_step *= 10.0
	var major_step = hp_step * 10.0
	var medium_step = hp_step * 5.0
	var total_ticks = int(max_health / hp_step)

	for i in range(1, total_ticks):
		var hp_val = i * hp_step
		var x = (hp_val / max_health) * bar_w

		if is_zero_approx(fmod(hp_val, major_step)):
			# 1000 HP Major Separator (LoL Chunk / Cuadro)
			ticks_overlay.draw_line(
				Vector2(x, 0.0),
				Vector2(x, bar_h),
				Color(0.0, 0.0, 0.0, 1.0),
				2.5
			)
		elif is_zero_approx(fmod(hp_val, medium_step)):
			# 500 HP Medium Tick
			ticks_overlay.draw_line(
				Vector2(x, 0.0),
				Vector2(x, bar_h),
				Color(0.04, 0.04, 0.05, 0.9),
				1.5
			)
		else:
			# 100 HP Minor Tick
			ticks_overlay.draw_line(
				Vector2(x, 0.0),
				Vector2(x, bar_h),
				Color(0.05, 0.06, 0.08, 0.75),
				1.0
			)
