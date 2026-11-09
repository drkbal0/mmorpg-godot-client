extends CanvasLayer

# PlayerHUD.gd - Interfaz de Combate Estilo LoL / MOBA (ADR 093)
# Integra el retrato del campeón, barra segmentada de HP/Mana y barra de habilidades
# con enfriamiento radial circular dinámico perfectamente centrado y delimitado (clip_contents).

@onready var name_label = %NameLabel
@onready var hp_bar = %HPBar
@onready var hp_value_label = %HPValueLabel
@onready var mana_bar = %ManaBar
@onready var action_bar_container = %ActionBarContainer

var skill_slots: Dictionary = {} # spell_id -> Dictionary { panel, radial_overlay, cd_label, key_label, cfg, was_on_cooldown }
var _keybind_poll_timer: float = 0.0
var wings_overlay: Control = null

const SKILL_CONFIG = [
	{"id": 3, "action": "attack_primary", "fallback_key": "LMB", "key": "LMB", "name": "LÁSER", "color": Color(0.2, 0.9, 1.0), "base_cd": 0.2},
	{"id": 1, "action": "cast_spell_1", "fallback_key": "Q", "key": "Q", "name": "FUEGO", "color": Color(1.0, 0.45, 0.15), "base_cd": 1.2},
	{"id": 2, "action": "dash_evade", "fallback_key": "Shift", "key": "Shift", "name": "DASH", "color": Color(0.3, 0.75, 1.0), "base_cd": 4.0},
	{"id": 4, "action": "cast_spell_2", "fallback_key": "E", "key": "E", "name": "ESCUDO", "color": Color(0.1, 1.0, 0.7), "base_cd": 6.0},
	{"id": 5, "action": "cast_ultimate", "fallback_key": "R", "key": "R", "name": "METEORO", "color": Color(1.0, 0.25, 0.25), "base_cd": 12.0}
]

const HUDV2_SCENE = preload("res://ui/components/HUDv2/hud.tscn")
var hud_v2: Control = null

func _ready():
	if has_node("/root/UIOrchestrator"):
		var orch = get_node("/root/UIOrchestrator")
		orch.register_instance("player_hud", self)
		if orch.layout_persistence:
			if not orch.layout_persistence.hud_scale_changed.is_connected(apply_hud_scale):
				orch.layout_persistence.hud_scale_changed.connect(apply_hud_scale)
			apply_hud_scale(orch.layout_persistence.hud_scale)
	
	if has_node("/root/InputSettings"):
		var isettings = get_node("/root/InputSettings")
		if not isettings.bindings_updated.is_connected(update_keybind_labels):
			isettings.bindings_updated.connect(update_keybind_labels)
	
	_setup_wings_overlay()
	_populate_action_bar()
	_populate_item_hotbar()
	update_keybind_labels()
	_setup_hudv2()

func _setup_hudv2() -> void:
	var hud_margin = get_node_or_null("RootBottom/HUDMargin")
	var main_panel = hud_margin.get_node_or_null("MainPanel") if hud_margin else null
	if main_panel:
		main_panel.visible = false
	if wings_overlay:
		wings_overlay.visible = false
	
	var root_bottom = get_node_or_null("RootBottom")
	if not root_bottom: return
	
	hud_v2 = HUDV2_SCENE.instantiate()
	hud_v2.name = "HUDv2"
	root_bottom.add_child(hud_v2)
	hud_v2.anchors_preset = Control.PRESET_CENTER_BOTTOM
	hud_v2.anchor_left = 0.5
	hud_v2.anchor_right = 0.5
	hud_v2.anchor_top = 1.0
	hud_v2.anchor_bottom = 1.0
	hud_v2.offset_left = -680.0
	hud_v2.offset_top = -460.0
	hud_v2.offset_right = 680.0
	hud_v2.offset_bottom = 0.0
	
	hud_v2.set_health(1000.0, 1000.0, 3.9)
	hud_v2.set_mana(403.0, 403.0)
	hud_v2.set_level(5, 0.3)
	hud_v2.set_gold(1665)
	hud_v2.set_ability(0, 3, 5, 24, false, 6, 0.0)
	hud_v2.set_ability(1, 1, 5, 50, false, 6, 0.0)
	hud_v2.set_ability(2, 1, 5, 60, false, 6, 0.0)
	hud_v2.set_ability(3, 0, 3, 100, false, 6, 0.0)
	hud_v2.set_spell(0, 87.0)
	hud_v2.set_spell(1, 39.0)
	hud_v2.set_item(0, null, 23)
	hud_v2.set_trinket(1)
	hud_v2.set_stats({
		"attack_damage": 89, "ability_power": 0,
		"attack_speed": 0.72, "crit": "0%",
		"armor_pen": "0 | 0%", "magic_pen": "0 | 0%",
		"life_steal": "0%", "omnivamp": "0%",
		"armor": 49, "magic_resist": 38,
		"tenacity": "0%", "heal_shield": "0%",
		"ability_haste": 10, "move_speed": 348,
		"attack_range": 175, "regen": "19 | 55",
	})

func _setup_wings_overlay() -> void:
	var hud_margin = get_node_or_null("RootBottom/HUDMargin")
	if not hud_margin: return
	if wings_overlay != null: return
	
	wings_overlay = Control.new()
	wings_overlay.name = "WingsOverlay"
	wings_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wings_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud_margin.add_child(wings_overlay)
	hud_margin.move_child(wings_overlay, 0)
	
	wings_overlay.draw.connect(_on_draw_wings)
	var main_panel = hud_margin.get_node_or_null("MainPanel")
	if main_panel:
		main_panel.resized.connect(func(): if is_instance_valid(wings_overlay): wings_overlay.queue_redraw())

func _on_draw_wings() -> void:
	var hud_margin = get_node_or_null("RootBottom/HUDMargin")
	if not hud_margin or not is_instance_valid(wings_overlay): return
	var panel = hud_margin.get_node_or_null("MainPanel")
	if not panel: return
	var r = panel.get_rect()
	if r.size.x <= 1.0 or r.size.y <= 1.0: return
	
	var wing_bg = Color(0.04, 0.05, 0.08, 0.96)
	var wing_gold = Color(0.78, 0.65, 0.32, 0.95)
	var wing_highlight = Color(0.95, 0.85, 0.45, 0.8)
	
	# Left Wing Polygon (Angled LoL Console Flank)
	var left_poly = PackedVector2Array([
		Vector2(r.position.x + 6.0, r.position.y + r.size.y * 0.40),
		Vector2(r.position.x - 42.0, r.position.y + r.size.y),
		Vector2(r.position.x + 16.0, r.position.y + r.size.y)
	])
	wings_overlay.draw_colored_polygon(left_poly, wing_bg)
	wings_overlay.draw_polyline(PackedVector2Array([left_poly[0], left_poly[1], left_poly[2]]), wing_gold, 2.5)
	wings_overlay.draw_line(left_poly[0], left_poly[1], wing_highlight, 1.2)
	
	# Right Wing Polygon (Angled LoL Console Flank)
	var right_poly = PackedVector2Array([
		Vector2(r.end.x - 6.0, r.position.y + r.size.y * 0.40),
		Vector2(r.end.x + 42.0, r.position.y + r.size.y),
		Vector2(r.end.x - 16.0, r.position.y + r.size.y)
	])
	wings_overlay.draw_colored_polygon(right_poly, wing_bg)
	wings_overlay.draw_polyline(PackedVector2Array([right_poly[0], right_poly[1], right_poly[2]]), wing_gold, 2.5)
	wings_overlay.draw_line(right_poly[0], right_poly[1], wing_highlight, 1.2)

func apply_hud_scale(scale_val: float) -> void:
	var hud_margin = get_node_or_null("RootBottom/HUDMargin")
	if hud_margin:
		hud_margin.pivot_offset = Vector2(hud_margin.size.x * 0.5, hud_margin.size.y)
		hud_margin.scale = Vector2(scale_val, scale_val)
	if is_instance_valid(hud_v2):
		hud_v2.pivot_offset = Vector2(680.0, 460.0)
		hud_v2.scale = Vector2(scale_val, scale_val)

func get_action_display_key(action_name: String, fallback: String) -> String:
	if not InputMap.has_action(action_name):
		return fallback
	var events = InputMap.action_get_events(action_name)
	for ev in events:
		if ev is InputEventMouseButton:
			match ev.button_index:
				MOUSE_BUTTON_LEFT: return "LMB"
				MOUSE_BUTTON_RIGHT: return "RMB"
				MOUSE_BUTTON_MIDDLE: return "MMB"
				MOUSE_BUTTON_WHEEL_UP: return "MW_UP"
				MOUSE_BUTTON_WHEEL_DOWN: return "MW_DN"
				_: return "M" + str(ev.button_index)
		elif ev is InputEventKey:
			var code = ev.physical_keycode if ev.physical_keycode != 0 else ev.keycode
			if code != 0:
				var key_str = OS.get_keycode_string(code)
				if key_str == "Shift": return "Shift"
				if key_str == "Space": return "Space"
				if key_str == "Control": return "Ctrl"
				if key_str == "Alt": return "Alt"
				return key_str.to_upper()
	return fallback

func update_keybind_labels() -> void:
	for sid in skill_slots.keys():
		var slot = skill_slots[sid]
		var action_name = slot["cfg"].get("action", "")
		var fallback = slot["cfg"].get("fallback_key", "??")
		var display_key = get_action_display_key(action_name, fallback)
		if slot.has("key_label") and is_instance_valid(slot["key_label"]):
			slot["key_label"].text = " " + display_key + " "

func _populate_action_bar():
	if not action_bar_container: return
	
	for child in action_bar_container.get_children():
		child.queue_free()
	skill_slots.clear()
	
	for cfg in SKILL_CONFIG:
		var sid = cfg["id"]
		var slot = _create_slot(cfg)
		action_bar_container.add_child(slot["panel"])
		skill_slots[sid] = slot
	update_keybind_labels()

func _populate_item_hotbar() -> void:
	var hotbar = get_node_or_null("%ItemHotbarContainer")
	if not hotbar: return
	for child in hotbar.get_children():
		child.queue_free()
	
	var default_items = [
		{"key": "1", "name": "Poción Vida", "icon": "res://assets/icons/items/lifepot1x1.png", "count": 5},
		{"key": "2", "name": "Poción Maná", "icon": "res://assets/icons/items/manapot1x1.png", "count": 5},
		{"key": "3", "name": "Pergamino", "icon": "res://assets/icons/items/scroll1x1.png", "count": 1},
		{"key": "4", "name": "Cuchillo", "icon": "res://assets/icons/items/minidager1x1.png", "count": 1},
		{"key": "5", "name": "Amuleto", "icon": "res://assets/icons/items/amulet1x1.png", "count": 1},
		{"key": "6", "name": "Mochila", "icon": "res://assets/icons/items/backpack.png", "count": 1}
	]
	for it in default_items:
		var slot = _create_item_slot(it)
		hotbar.add_child(slot)

func _create_item_slot(data: Dictionary) -> PanelContainer:
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(34, 34)
	panel.clip_contents = true
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.08, 0.12, 0.95)
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = Color(0.75, 0.62, 0.32, 0.95)
	sb.corner_radius_top_left = 3
	sb.corner_radius_top_right = 3
	sb.corner_radius_bottom_right = 3
	sb.corner_radius_bottom_left = 3
	panel.add_theme_stylebox_override("panel", sb)

	var icon_tex: Texture2D = null
	if FileAccess.file_exists(data.get("icon", "")):
		icon_tex = load(data.get("icon"))

	var tr = TextureRect.new()
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.texture = icon_tex
	tr.custom_minimum_size = Vector2(26, 26)
	tr.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	tr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	panel.add_child(tr)

	var key_lbl = Label.new()
	key_lbl.text = " " + data.get("key", "")
	key_lbl.add_theme_font_size_override("font_size", 9)
	key_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35, 0.95))
	key_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	key_lbl.add_theme_constant_override("outline_size", 2)
	key_lbl.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	key_lbl.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	panel.add_child(key_lbl)

	if data.get("count", 1) > 1:
		var cnt_lbl = Label.new()
		cnt_lbl.text = "x" + str(data.get("count")) + " "
		cnt_lbl.add_theme_font_size_override("font_size", 9)
		cnt_lbl.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0, 0.9))
		cnt_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
		cnt_lbl.add_theme_constant_override("outline_size", 2)
		cnt_lbl.size_flags_horizontal = Control.SIZE_SHRINK_END
		cnt_lbl.size_flags_vertical = Control.SIZE_SHRINK_END
		panel.add_child(cnt_lbl)

	return panel

func _create_slot(cfg: Dictionary) -> Dictionary:
	var slot_panel = PanelContainer.new()
	slot_panel.custom_minimum_size = Vector2(62, 62)
	# clip_contents es crítico para evitar desbordes visuales hacia la derecha en R o entre ranuras
	slot_panel.clip_contents = true
	
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.10, 0.14, 0.95)
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.border_color = cfg["color"] * 0.75
	sb.corner_radius_top_left = 6
	sb.corner_radius_top_right = 6
	sb.corner_radius_bottom_right = 6
	sb.corner_radius_bottom_left = 6
	slot_panel.add_theme_stylebox_override("panel", sb)
	
	var content = Control.new()
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.clip_contents = true
	slot_panel.add_child(content)
	
	# Keybind badge (Top-Left)
	var key_badge = PanelContainer.new()
	key_badge.position = Vector2(4, 4)
	var ksb = StyleBoxFlat.new()
	ksb.bg_color = Color(0.02, 0.04, 0.06, 0.85)
	ksb.corner_radius_top_left = 3
	ksb.corner_radius_top_right = 3
	ksb.corner_radius_bottom_right = 3
	ksb.corner_radius_bottom_left = 3
	key_badge.add_theme_stylebox_override("panel", ksb)
	
	var action_name = cfg.get("action", "")
	var fallback_key = cfg.get("fallback_key", cfg.get("key", "??"))
	var display_key = get_action_display_key(action_name, fallback_key)
	var key_label = Label.new()
	key_label.text = " " + display_key + " "
	key_label.add_theme_font_size_override("font_size", 10)
	key_label.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	key_badge.add_child(key_label)
	content.add_child(key_badge)
	
	# Skill Name (Center)
	var name_lbl = Label.new()
	name_lbl.text = cfg["name"]
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_lbl.position = Vector2(0, 18)
	name_lbl.size = Vector2(62, 26)
	name_lbl.add_theme_font_size_override("font_size", 11)
	name_lbl.add_theme_color_override("font_color", cfg["color"])
	name_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	name_lbl.add_theme_constant_override("outline_size", 4)
	content.add_child(name_lbl)
	
	# Radial Cooldown Sweep Overlay (Procedural Vector Draw)
	var radial_overlay = Control.new()
	radial_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	radial_overlay.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	radial_overlay.size_flags_vertical = Control.SIZE_EXPAND_FILL
	radial_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	radial_overlay.clip_contents = true
	radial_overlay.set_meta("progress", 0.0)
	
	radial_overlay.draw.connect(func():
		var p = float(radial_overlay.get_meta("progress", 0.0))
		if p <= 0.005: return
		var sz = radial_overlay.size
		if sz.x <= 1.0 or sz.y <= 1.0:
			sz = slot_panel.size
		if sz.x <= 1.0 or sz.y <= 1.0:
			sz = Vector2(62, 62)
		var center = sz * 0.5
		# Radio exacto para cubrir esquinas de la celda: sqrt(w^2 + h^2) / 2
		var radius = ceil(sz.length() * 0.5) + 1.0
		var points = PackedVector2Array([center])
		var colors = PackedColorArray()
		var num_steps = 40
		var start_ang = -PI * 0.5 # 12 en punto
		var sweep_ang = p * TAU
		for i in range(num_steps + 1):
			var a = start_ang + (float(i) / float(num_steps)) * sweep_ang
			points.append(center + Vector2(cos(a), sin(a)) * radius)
		colors.resize(points.size())
		colors.fill(Color(0.02, 0.03, 0.06, 0.82))
		radial_overlay.draw_polygon(points, colors)
		
		# Aguja / línea sutil del reloj de enfriamiento (confinada al radio interior de la celda)
		var lead_ang = start_ang + sweep_ang
		var inner_rad = min(center.x, center.y) - 1.0
		var lead_pt = center + Vector2(cos(lead_ang), sin(lead_ang)) * inner_rad
		radial_overlay.draw_line(center, lead_pt, Color(1.0, 1.0, 1.0, 0.5), 1.5)
	)
	content.add_child(radial_overlay)
	
	# Cooldown timer text
	var cd_label = Label.new()
	cd_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	cd_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cd_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cd_label.add_theme_font_size_override("font_size", 16)
	cd_label.add_theme_color_override("font_color", Color.WHITE)
	cd_label.add_theme_color_override("font_outline_color", Color.BLACK)
	cd_label.add_theme_constant_override("outline_size", 6)
	cd_label.visible = false
	content.add_child(cd_label)
	
	return {
		"panel": slot_panel,
		"stylebox": sb,
		"radial_overlay": radial_overlay,
		"cd_label": cd_label,
		"key_label": key_label,
		"cfg": cfg,
		"was_on_cd": false
	}

func _process(delta: float):
	_keybind_poll_timer += delta
	if _keybind_poll_timer >= 0.5:
		_keybind_poll_timer = 0.0
		update_keybind_labels()

	var spell_mgr = get_node_or_null("/root/SpellManager")
	if not spell_mgr: return
	
	if is_instance_valid(hud_v2) and spell_mgr:
		var q_cd = spell_mgr.get_cooldown_remaining(1)
		var r_cd = spell_mgr.get_cooldown_remaining(5)
		hud_v2.set_ability(0, 3, 5, 24, false, 6, q_cd)
		hud_v2.set_ability(3, 0, 3, 100, false, 6, r_cd)

	for sid in skill_slots.keys():
		var slot = skill_slots[sid]
		var rem = spell_mgr.get_cooldown_remaining(sid)
		var base_cd = float(slot["cfg"].get("base_cd", 2.0))
		if spell_mgr.has_method("get_spell"):
			var sdef = spell_mgr.get_spell(sid)
			if sdef.has("cooldown_ms") and sdef["cooldown_ms"] > 0:
				base_cd = float(sdef["cooldown_ms"]) / 1000.0
		
		if rem > 0.05:
			slot["was_on_cd"] = true
			var progress = clamp(rem / base_cd, 0.0, 1.0)
			slot["radial_overlay"].set_meta("progress", progress)
			slot["radial_overlay"].queue_redraw()
			
			slot["cd_label"].visible = true
			slot["cd_label"].text = "%.1f" % rem
		else:
			slot["radial_overlay"].set_meta("progress", 0.0)
			slot["radial_overlay"].queue_redraw()
			slot["cd_label"].visible = false
			
			# Destello luminoso / pulso al quedar lista
			if slot["was_on_cd"]:
				slot["was_on_cd"] = false
				_flash_slot_ready(slot)

func _flash_slot_ready(slot: Dictionary):
	var sb: StyleBoxFlat = slot["stylebox"]
	var orig_color: Color = slot["cfg"]["color"] * 0.75
	var flash_color = Color(1.0, 1.0, 0.6, 1.0) # Destello dorado
	
	var tween = create_tween()
	tween.tween_property(sb, "border_color", flash_color, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(sb, "border_color", orig_color, 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

func setup(p_name: String, p_hp: float):
	update_name(p_name)
	update_hp(p_hp)

func update_name(new_name: String):
	if name_label:
		name_label.text = new_name

func update_hp(new_hp_percent: float):
	if hp_bar:
		var tween = create_tween()
		tween.tween_property(hp_bar, "value", new_hp_percent, 0.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if hp_value_label:
		var cur_val = int(round(new_hp_percent * 10))
		hp_value_label.text = "%d / 1000 HP (%d%%)" % [cur_val, int(round(new_hp_percent))]
	if is_instance_valid(hud_v2):
		hud_v2.set_health(new_hp_percent * 10.0, 1000.0, 3.9)

func update_mana(new_mana_percent: float):
	if mana_bar:
		var tween = create_tween()
		tween.tween_property(mana_bar, "value", new_mana_percent, 0.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if is_instance_valid(hud_v2):
		hud_v2.set_mana(new_mana_percent * 10.0, 1000.0)
