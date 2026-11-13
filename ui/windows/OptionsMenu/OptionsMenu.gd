class_name OptionsMenu
extends CanvasLayer

const B = preload("res://audio/audio_buses.gd")

## Persistencia de ajustes de audio (Fase 9.13 - ADR 094)
const SETTINGS_PATH := "user://settings.cfg"
const AUDIO_SECTION := "audio"
const AUDIO_DEFAULT_VOLUME := 100.0
const AUDIO_MUTE_DB := -80.0
## Buses canónicos expuestos al jugador: [nombre de bus, etiqueta visible]
const AUDIO_BUS_ROWS := [
	[B.MASTER, "Volumen Maestro"],
	[B.MUSIC, "Música"],
	[B.SFX, "Efectos (SFX)"],
	[B.AMBIENCE, "Ambiente"],
	[B.UI, "Interfaz"],
]

## bus StringName -> HSlider / Label de porcentaje (expuestos para tests)
var audio_sliders: Dictionary = {}
var audio_percent_labels: Dictionary = {}

@onready var action_list = find_child("ActionList", true, false)

var is_listening = false
var target_action = ""
var target_button : Button = null

func _ready():
	visible = false
	
	var test_btn = find_child("TestLazyButton", true, false)
	if test_btn: test_btn.pressed.connect(_on_test_lazy)
	
	var shelter_btn = find_child("ReturnShelterButton", true, false)
	if shelter_btn: shelter_btn.pressed.connect(_on_return_to_shelter)
	
	var logout_btn = find_child("LogoutButton", true, false)
	if logout_btn: logout_btn.pressed.connect(_on_logout)
	
	var quit_btn = find_child("QuitButton", true, false)
	if quit_btn: quit_btn.pressed.connect(func(): get_tree().quit())
	
	var resume_btn = find_child("ResumeButton", true, false)
	if resume_btn: resume_btn.pressed.connect(_on_resume)
	
	if has_node("/root/InputSettings"):
		var isettings = get_node("/root/InputSettings")
		if not isettings.bindings_updated.is_connected(_populate_action_list):
			isettings.bindings_updated.connect(_populate_action_list)
	
	_populate_ui_settings()
	_setup_audio_settings()
	_populate_action_list()

func _populate_ui_settings():
	# 1. Intentar encontrar el TabContainer para añadir una pestaña nueva
	var tab_container : TabContainer = null
	if action_list:
		var p = action_list.get_parent()
		while p != null:
			if p is TabContainer:
				tab_container = p
				break
			p = p.get_parent()
	
	var ui_container = find_child("UISettingsList", true, false)
	
	if not ui_container and tab_container:
		# Crear la pestaña "Interfaz"
		var tab_panel = MarginContainer.new()
		tab_panel.name = "Interfaz"
		tab_panel.add_theme_constant_override("margin_top", 20)
		tab_panel.add_theme_constant_override("margin_left", 20)
		tab_panel.add_theme_constant_override("margin_right", 20)
		tab_panel.add_theme_constant_override("margin_bottom", 20)
		
		var scroll = ScrollContainer.new()
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		tab_panel.add_child(scroll)
		
		var main_vbox = VBoxContainer.new()
		main_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(main_vbox)
		
		var header = Label.new()
		header.text = "AJUSTES DE ESCALADO"
		header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		main_vbox.add_child(header)
		
		ui_container = HBoxContainer.new()
		ui_container.name = "UISettingsList"
		ui_container.alignment = BoxContainer.ALIGNMENT_CENTER
		ui_container.add_theme_constant_override("separation", 15)
		main_vbox.add_child(ui_container)
		
		var info = Label.new()
		info.text = "Ajusta el tamaño global de las ventanas (Inventario, Mochilas, etc.)"
		info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		info.modulate = Color(0.7, 0.7, 0.7) # Grisáceo
		main_vbox.add_child(info)
		
		# Separador
		main_vbox.add_child(HSeparator.new())
		
		# ESCALADO DEL HUD DE COMBATE (LoL-Style Bar)
		var hud_header = Label.new()
		hud_header.text = "ESCALA DEL HUD DE COMBATE (LoL-Style Action Bar)"
		hud_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		main_vbox.add_child(hud_header)
		
		var hud_scale_row = HBoxContainer.new()
		hud_scale_row.alignment = BoxContainer.ALIGNMENT_CENTER
		hud_scale_row.add_theme_constant_override("separation", 15)
		main_vbox.add_child(hud_scale_row)
		
		var cur_hud_s = 1.0
		if has_node("/root/UIOrchestrator") and UIOrchestrator.layout_persistence:
			cur_hud_s = UIOrchestrator.layout_persistence.hud_scale
			
		var hud_slider = HSlider.new()
		hud_slider.min_value = 0.7
		hud_slider.max_value = 1.3
		hud_slider.step = 0.05
		hud_slider.value = cur_hud_s
		hud_slider.custom_minimum_size = Vector2(220, 24)
		hud_scale_row.add_child(hud_slider)
		
		var hud_lbl = Label.new()
		hud_lbl.text = "%d%%" % int(round(cur_hud_s * 100))
		hud_lbl.custom_minimum_size = Vector2(50, 0)
		hud_scale_row.add_child(hud_lbl)
		
		hud_slider.value_changed.connect(func(v):
			hud_lbl.text = "%d%%" % int(round(v * 100))
			if has_node("/root/UIOrchestrator") and UIOrchestrator.layout_persistence:
				UIOrchestrator.layout_persistence.set_hud_scale(v)
		)
		
		var hud_info = Label.new()
		hud_info.text = "Ajusta en tiempo real la escala de la barra inferior de habilidades, vida y maná."
		hud_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hud_info.modulate = Color(0.7, 0.7, 0.7)
		main_vbox.add_child(hud_info)
		
		# Separador
		main_vbox.add_child(HSeparator.new())
		
		# 2. RENDIMIENTO & MODO AHORRO (FPS DEL MUNDO 3D)
		var fps_header = Label.new()
		fps_header.text = "RENDIMIENTO & MODO AHORRO (FPS DEL MUNDO 3D)"
		fps_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		main_vbox.add_child(fps_header)
		
		var fps_container = HBoxContainer.new()
		fps_container.name = "FPSContainer"
		fps_container.alignment = BoxContainer.ALIGNMENT_CENTER
		fps_container.add_theme_constant_override("separation", 15)
		main_vbox.add_child(fps_container)
		
		var fps_options = [
			{"label": "V-Sync (Auto)", "fps": 0},
			{"label": "60 FPS", "fps": 60},
			{"label": "30 FPS", "fps": 30},
			{"label": "Modo Eco 3D (15)", "fps": 15}
		]
		
		for opt in fps_options:
			var btn = Button.new()
			btn.text = opt["label"]
			btn.custom_minimum_size = Vector2(110, 0)
			btn.toggle_mode = true
			if Engine.max_fps == opt["fps"]:
				btn.button_pressed = true
			btn.pressed.connect(func():
				for other in fps_container.get_children():
					if other != btn: other.button_pressed = false
				btn.button_pressed = true
				Engine.max_fps = opt["fps"]
				print("[OptionsMenu] Max FPS del motor ajustado a: ", opt["fps"])
			)
			fps_container.add_child(btn)
			
		var fps_info = Label.new()
		fps_info.text = "El Modo Eco optimiza el consumo de batería y GPU durante la simulación 3D en el Overworld. El Refugio mantiene alta fidelidad visual."
		fps_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fps_info.modulate = Color(0.6, 0.8, 0.7)
		main_vbox.add_child(fps_info)
		
		# Separador
		main_vbox.add_child(HSeparator.new())
		
		# 3. ESCALA DE RENDERIZADO 3D (3D SCALING)
		var scale_header = Label.new()
		scale_header.text = "CALIDAD VISUAL 3D (ESCALA DE VIEWPORT)"
		scale_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		main_vbox.add_child(scale_header)
		
		var scale_container = HBoxContainer.new()
		scale_container.alignment = BoxContainer.ALIGNMENT_CENTER
		scale_container.add_theme_constant_override("separation", 15)
		main_vbox.add_child(scale_container)
		
		var scale_options = [0.5, 0.75, 1.0]
		for s in scale_options:
			var btn = Button.new()
			btn.text = str(s * 100) + "%"
			btn.custom_minimum_size = Vector2(80, 0)
			btn.toggle_mode = true
			var current_scale = get_viewport().scaling_3d_scale
			if abs(current_scale - s) < 0.05:
				btn.button_pressed = true
			btn.pressed.connect(func():
				for other in scale_container.get_children():
					if other != btn: other.button_pressed = false
				btn.button_pressed = true
				get_viewport().scaling_3d_scale = s
				print("[OptionsMenu] Viewport Scaling 3D ajustado a: ", s)
			)
			scale_container.add_child(btn)
		
		tab_container.add_child(tab_panel)
		# Mover la pestaña para que no sea la última si hay botones de cerrar abajo?
		# En el screen parece que General/Controles son los únicos.
	
	if ui_container:
		for child in ui_container.get_children():
			child.queue_free()
			
		var zooms = [0.75, 1.0, 1.25, 1.5]
		for z in zooms:
			var btn = Button.new()
			btn.text = str(z * 100) + "%"
			btn.custom_minimum_size = Vector2(80, 0)
			btn.toggle_mode = true
			if abs(UIOrchestrator.layout_persistence.global_ui_zoom - z) < 0.01:
				btn.button_pressed = true
			
			btn.pressed.connect(func():
				# Desmarcar otros botones
				for other in ui_container.get_children():
					if other != btn: other.button_pressed = false
				btn.button_pressed = true
				UIOrchestrator.layout_persistence.set_global_zoom(z)
			)
			ui_container.add_child(btn)

# --- Pestaña Sonido (Fase 9.13 - ADR 094) ---

func _find_tab_container() -> TabContainer:
	if action_list:
		var p = action_list.get_parent()
		while p != null:
			if p is TabContainer:
				return p
			p = p.get_parent()
	return find_child("TabContainer", true, false) as TabContainer

func _setup_audio_settings() -> void:
	var tab_container := _find_tab_container()
	if tab_container == null or tab_container.has_node("Sonido"):
		return

	var tab_panel := MarginContainer.new()
	tab_panel.name = "Sonido"
	for side in ["margin_top", "margin_left", "margin_right", "margin_bottom"]:
		tab_panel.add_theme_constant_override(side, 20)

	var vbox := VBoxContainer.new()
	vbox.name = "AudioSettingsList"
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 12)
	tab_panel.add_child(vbox)

	var header := Label.new()
	header.text = "VOLUMEN DE AUDIO"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(header)

	var saved := _load_audio_settings()

	for row_def in AUDIO_BUS_ROWS:
		var bus: StringName = row_def[0]
		var row := HBoxContainer.new()
		row.name = "AudioRow_%s" % bus
		row.add_theme_constant_override("separation", 12)
		vbox.add_child(row)

		var name_lbl := Label.new()
		name_lbl.text = row_def[1]
		name_lbl.custom_minimum_size = Vector2(140, 0)
		row.add_child(name_lbl)

		var slider := HSlider.new()
		slider.name = "VolumeSlider_%s" % bus
		slider.min_value = 0
		slider.max_value = 100
		slider.step = 1
		slider.custom_minimum_size = Vector2(200, 24)
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(slider)

		var pct_lbl := Label.new()
		pct_lbl.name = "VolumePercent_%s" % bus
		pct_lbl.custom_minimum_size = Vector2(50, 0)
		pct_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(pct_lbl)

		audio_sliders[bus] = slider
		audio_percent_labels[bus] = pct_lbl

		# Aplicar el valor persistido sin re-guardar, y conectar después.
		var value: float = saved.get(bus, AUDIO_DEFAULT_VOLUME)
		slider.set_value_no_signal(value)
		_apply_bus_volume(bus, slider.value)
		slider.value_changed.connect(_on_audio_slider_changed.bind(bus))

	var info := Label.new()
	info.text = "Los cambios se aplican al instante y se guardan automáticamente."
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.modulate = Color(0.7, 0.7, 0.7)
	vbox.add_child(info)

	tab_container.add_child(tab_panel)

func _on_audio_slider_changed(value: float, bus: StringName) -> void:
	_apply_bus_volume(bus, value)
	_save_audio_settings()

func _apply_bus_volume(bus: StringName, value: float) -> void:
	var pct_lbl: Label = audio_percent_labels.get(bus)
	if pct_lbl:
		pct_lbl.text = "%d%%" % int(round(value))
	var idx := AudioServer.get_bus_index(bus)
	if idx < 0:
		push_warning("[OptionsMenu] Bus de audio inexistente: %s" % bus)
		return
	if value <= 0.0:
		AudioServer.set_bus_mute(idx, true)
		AudioServer.set_bus_volume_db(idx, AUDIO_MUTE_DB)
	else:
		AudioServer.set_bus_mute(idx, false)
		AudioServer.set_bus_volume_db(idx, linear_to_db(value / 100.0))

func _load_audio_settings() -> Dictionary:
	var result := {}
	var cfg := ConfigFile.new()
	var has_file := cfg.load(SETTINGS_PATH) == OK
	for row_def in AUDIO_BUS_ROWS:
		var bus: StringName = row_def[0]
		var v = cfg.get_value(AUDIO_SECTION, String(bus), AUDIO_DEFAULT_VOLUME) if has_file else AUDIO_DEFAULT_VOLUME
		result[bus] = clampf(float(v), 0.0, 100.0)
	return result

func _save_audio_settings() -> void:
	var cfg := ConfigFile.new()
	# Conservar otras secciones que pudieran existir en settings.cfg.
	cfg.load(SETTINGS_PATH)
	for bus in audio_sliders.keys():
		cfg.set_value(AUDIO_SECTION, String(bus), int(round(audio_sliders[bus].value)))
	var err := cfg.save(SETTINGS_PATH)
	if err != OK:
		push_warning("[OptionsMenu] No se pudo guardar %s (error %d)" % [SETTINGS_PATH, err])

func _input(event: InputEvent):
	if is_listening and event.is_pressed():
		if event is InputEventKey:
			_on_key_captured(event.keycode)
			get_viewport().set_input_as_handled()
		elif event is InputEventMouseButton:
			_on_mouse_captured(event.button_index)
			get_viewport().set_input_as_handled()

func _populate_action_list():
	if not action_list: return
	
	# Limpiar lista anterior
	for child in action_list.get_children():
		child.queue_free()
	
	var actions = InputSettings.current_bindings.keys()
	
	for action in actions:
		# SEGURIDAD: Solo mostrar toggle_admin si el usuario es admin
		if action == "toggle_admin" and not AuthManager.is_admin:
			continue
			
		var row = HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		var label = Label.new()
		label.text = action.replace("_", " ").capitalize()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		var btn = Button.new()
		btn.text = InputSettings.get_key_name(action)
		btn.custom_minimum_size = Vector2(150, 0)
		btn.pressed.connect(_start_listening.bind(action, btn))
		
		row.add_child(label)
		row.add_child(btn)
		action_list.add_child(row)
		
	# Botón para restablecer todos los controles a predeterminados
	action_list.add_child(HSeparator.new())
	var reset_row = HBoxContainer.new()
	reset_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var reset_btn = Button.new()
	reset_btn.text = "🔄 Restablecer Controles a Predeterminados"
	reset_btn.custom_minimum_size = Vector2(250, 30)
	reset_btn.pressed.connect(func():
		InputSettings.reset_to_defaults()
		_populate_action_list()
	)
	reset_row.add_child(reset_btn)
	action_list.add_child(reset_row)

func _start_listening(action: String, btn: Button):
	if is_listening: return
	
	is_listening = true
	target_action = action
	target_button = btn
	
	btn.text = "--- PULSA TECLA O CLIC ---"
	btn.modulate = Color(1, 1, 0) # Highlight yellow

func _on_key_captured(keycode: int):
	# No permitir remapear a ESC (mantenemos ESC para cerrar)
	if keycode == KEY_ESCAPE and target_action != "ui_cancel":
		_cancel_listening()
		return
		
	var act = target_action
	is_listening = false
	target_action = ""
	target_button = null
	
	InputSettings.update_binding(act, "key", keycode)
	_populate_action_list()

func _on_mouse_captured(button_index: int):
	var act = target_action
	is_listening = false
	target_action = ""
	target_button = null
	
	InputSettings.update_binding(act, "mouse", button_index)
	_populate_action_list()

func _cancel_listening():
	if target_button:
		target_button.text = InputSettings.get_key_name(target_action)
		target_button.modulate = Color(1, 1, 1)
	is_listening = false
	target_action = ""
	target_button = null

# --- Botones Originales ---

func _on_test_lazy():
	print("OptionsMenu: Requesting new dynamic test asset from server...")
	var gen_key = "gen_test_" + str(Time.get_ticks_msec())
	var gen_response = await APIClient.post_request("/api/update/generate_test", {}, true, UpdateManager.update_service_url, gen_key)
	
	if gen_response.has("data") and gen_response["data"].has("id"):
		var new_asset_id = gen_response["data"]["id"]
		print("OptionsMenu: Server generated asset ID: ", new_asset_id)
		await UpdateManager.check_for_updates()
		UpdateManager.request_asset(new_asset_id)
	else:
		print("OptionsMenu Error: Failed to generate dynamic test asset.")

func _on_return_to_shelter():
	print("OptionsMenu: Returning to Shelter...")
	_cancel_listening()
	if NetworkManager:
		NetworkManager.disconnect_from_world()
	
	if has_node("/root/UIOrchestrator"):
		get_node("/root/UIOrchestrator").close_all_windows()
	
	SceneManager.change_scene_async("res://ui/windows/ShelterWindow/ShelterLobby.tscn")

func _on_logout():
	print("OptionsMenu: Logging out and returning to login screen...")
	_cancel_listening()
	if AuthManager:
		AuthManager.perform_full_logout()
	elif SceneManager:
		SceneManager.change_scene_async("res://login_screen.tscn")

func _on_resume():
	_cancel_listening()
	if has_node("/root/UIOrchestrator"):
		get_node("/root/UIOrchestrator").close_window("options_menu")
	else:
		visible = false
