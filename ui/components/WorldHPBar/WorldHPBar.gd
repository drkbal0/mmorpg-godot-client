extends Node3D

@onready var viewport = $SubViewport
@onready var sprite = $Sprite3D

var hp_bar_3d : ProgressBar
var hp_bar_ghost : ProgressBar
var gloss_layer : ColorRect
var hp_stack : Control

var current_hp_percent : float = 100.0
var max_hp : float = 1000.0
var _hp_initialized : bool = false

func _ready():
	# Wait for first frame so viewport texture is ready
	pass

func setup(color: Color):
	_build_ui(color)
	sprite.texture = viewport.get_texture()

func set_max_hp(val: float):
	max_hp = val
	if hp_stack:
		call_deferred("_add_ticks", hp_stack, 262, 44)

func update_hp(new_hp_percent: float):
	var old_hp = current_hp_percent
	current_hp_percent = new_hp_percent
	
	if not _hp_initialized:
		_hp_initialized = true
		if hp_bar_3d: hp_bar_3d.value = new_hp_percent
		if hp_bar_ghost: hp_bar_ghost.value = new_hp_percent
		if gloss_layer:
			gloss_layer.size.x = (262.0 * new_hp_percent) / 100.0
		if hp_stack:
			call_deferred("_add_ticks", hp_stack, 262, 44)
		return
		
	if hp_bar_3d and hp_bar_ghost:
		var tween = create_tween()
		var ghost_sb = hp_bar_ghost.get_theme_stylebox("fill") as StyleBoxFlat
		
		if new_hp_percent < old_hp: # Damage (Ghost Orange)
			ghost_sb.bg_color = Color(1, 0.5, 0)
			hp_bar_3d.value = new_hp_percent
			tween.tween_interval(0.3)
			tween.tween_property(hp_bar_ghost, "value", new_hp_percent, 0.4).set_trans(Tween.TRANS_SINE)
		else: # Healed (Ghost Blue)
			ghost_sb.bg_color = Color(0, 0.5, 1)
			hp_bar_ghost.value = new_hp_percent
			tween.tween_interval(0.3)
			tween.tween_property(hp_bar_3d, "value", new_hp_percent, 0.4).set_trans(Tween.TRANS_SINE)
		
		if gloss_layer:
			var target_w = (262.0 * new_hp_percent) / 100.0
			var gloss_tween = create_tween()
			gloss_tween.tween_property(gloss_layer, "size:x", target_w, 0.4).set_trans(Tween.TRANS_SINE)

func _build_ui(base_color: Color):
	var frame_panel = PanelContainer.new()
	frame_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var sb_frame = StyleBoxFlat.new()
	sb_frame.bg_color = Color(0.1, 0.1, 0.1, 1.0)
	sb_frame.border_width_left = 4
	sb_frame.border_width_top = 4
	sb_frame.border_width_right = 4
	sb_frame.border_width_bottom = 4
	sb_frame.border_color = Color(0.3, 0.3, 0.3)
	sb_frame.set_corner_radius_all(6)
	frame_panel.add_theme_stylebox_override("panel", sb_frame)
	viewport.add_child(frame_panel)
	
	var main_hbox = HBoxContainer.new()
	main_hbox.add_theme_constant_override("separation", 0)
	frame_panel.add_child(main_hbox)
	
	var level_panel = PanelContainer.new()
	level_panel.custom_minimum_size = Vector2(50, 0)
	var sb_level = StyleBoxFlat.new()
	sb_level.bg_color = Color(0.05, 0.1, 0.15, 1.0)
	sb_level.border_width_right = 2
	sb_level.border_color = Color(0.3, 0.3, 0.3)
	sb_level.corner_radius_top_left = 2
	sb_level.corner_radius_bottom_left = 2
	level_panel.add_theme_stylebox_override("panel", sb_level)
	main_hbox.add_child(level_panel)
	
	var level_label = Label.new()
	level_label.text = "1"
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	level_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	level_label.add_theme_color_override("font_color", Color(0, 0.7, 1))
	level_label.add_theme_font_size_override("font_size", 24)
	level_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	level_panel.add_child(level_label)
	
	var bars_vbox = VBoxContainer.new()
	bars_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bars_vbox.add_theme_constant_override("separation", 0)
	main_hbox.add_child(bars_vbox)
	
	hp_stack = Control.new()
	hp_stack.name = "HPStack"
	hp_stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bars_vbox.add_child(hp_stack)
	
	var darker_color = base_color.darkened(0.2)
	
	hp_bar_ghost = ProgressBar.new()
	hp_bar_ghost.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hp_bar_ghost.show_percentage = false
	hp_bar_ghost.value = 100
	hp_stack.add_child(hp_bar_ghost)

	hp_bar_3d = ProgressBar.new()
	hp_bar_3d.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hp_bar_3d.show_percentage = false
	hp_bar_3d.value = 100
	hp_stack.add_child(hp_bar_3d)
	
	gloss_layer = ColorRect.new()
	gloss_layer.name = "GlossLayer"
	gloss_layer.color = Color(1, 1, 1, 0.25)
	gloss_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gloss_layer.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	gloss_layer.custom_minimum_size = Vector2(0, 18) 
	hp_stack.add_child(gloss_layer)
	
	var resource_bar = ColorRect.new()
	resource_bar.color = Color(0, 0.6, 1)
	resource_bar.custom_minimum_size = Vector2(0, 8)
	bars_vbox.add_child(resource_bar)
	
	var sb_ghost = StyleBoxFlat.new()
	sb_ghost.bg_color = Color(1, 0.5, 0)
	hp_bar_ghost.add_theme_stylebox_override("fill", sb_ghost)
	hp_bar_ghost.add_theme_stylebox_override("background", StyleBoxEmpty.new())

	var sb_bg = StyleBoxEmpty.new()
	hp_bar_3d.add_theme_stylebox_override("background", sb_bg)
	
	var sb_fill = StyleBoxFlat.new()
	sb_fill.bg_color = darker_color
	sb_fill.corner_radius_top_right = 2
	hp_bar_3d.add_theme_stylebox_override("fill", sb_fill)
	
	_add_ticks(hp_stack, 262, 44)

func _add_ticks(parent: Node, width: float, height: float):
	if parent.has_node("TicksContainer"):
		var old = parent.get_node("TicksContainer")
		parent.remove_child(old)
		old.queue_free()
		
	var ticks_container = Control.new()
	ticks_container.name = "TicksContainer"
	ticks_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ticks_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(ticks_container)
	
	var hp_per_tick = 100.0
	if max_hp <= 300:
		hp_per_tick = 25.0
	elif max_hp <= 600:
		hp_per_tick = 50.0
	var num_ticks = int(max_hp / hp_per_tick)
	for i in range(1, num_ticks):
		var line = ColorRect.new()
		if i % 10 == 0:
			line.color = Color(0, 0, 0, 0.8)
			line.custom_minimum_size = Vector2(3, height)
		elif i % 5 == 0:
			line.color = Color(0, 0, 0, 0.6)
			line.custom_minimum_size = Vector2(2, height * 0.7)
		else:
			line.color = Color(0, 0, 0, 0.4)
			line.custom_minimum_size = Vector2(1, height * 0.4)
			
		line.position = Vector2((width / (max_hp/hp_per_tick)) * i, 0)
		ticks_container.add_child(line)
