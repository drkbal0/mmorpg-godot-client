extends Node

# UIInputRouter.gd - Despachador central de atajos de teclado
# Propósito: Centralizar ESC, I, V, F10 y evitar conflictos entre escenas.

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS # Funciona incluso en pausa si es necesario

func _unhandled_input(event: InputEvent):
	# Solo procesamos eventos de teclado presionados
	if not (event is InputEventKey and event.pressed):
		return

	# USANDO ACCIONES DEL INPUTMAP (pre-mapeadas en InputSettings)
	
	# 1. ESC / CANCELAR
	if event.is_action_pressed("ui_cancel"):
		_handle_esc()
		get_viewport().set_input_as_handled()
		
	# 2. INVENTARIO (I)
	elif event.is_action_pressed("toggle_inventory"):
		_handle_inventory()
		get_viewport().set_input_as_handled()

	# 2.5 CÓDICE DINÁMICO & BITÁCORA (J)
	elif event.is_action_pressed("toggle_codex") or (event is InputEventKey and event.pressed and event.keycode == KEY_J and not event.is_echo()):
		_handle_codex()
		get_viewport().set_input_as_handled()
		
	# 3. CÁMARA (V)
	elif event.is_action_pressed("toggle_camera"):
		_handle_camera()
		get_viewport().set_input_as_handled()
		
	# 4. ADMIN (F10)
	elif event.is_action_pressed("toggle_admin"):
		_handle_admin()
		get_viewport().set_input_as_handled()

	# 5. DATABASE ADMIN INSPECTOR (F11)
	elif event.is_action_pressed("toggle_db_admin"):
		_handle_db_admin()
		get_viewport().set_input_as_handled()

	# 6. HITBOX DEBUG VISUALIZER (F9)
	elif (event.is_action_pressed("toggle_hitbox_debug") or (event is InputEventKey and event.pressed and event.keycode == KEY_F9)) and not event.is_echo():
		_handle_hitbox_debug()
		get_viewport().set_input_as_handled()

	# 7. DEPRECATED / DESACTIVADO (F8)
	elif event is InputEventKey and event.pressed and event.keycode == KEY_F8 and not event.is_echo():
		print("[UIInputRouter] F8 ignorado: El atajo fue desactivado. Usa F9 para alternar hitboxes.")
		get_viewport().set_input_as_handled()

func _handle_esc():
	if not UIOrchestrator: 
		return
	
	# Jerarquía de cierre:
	# 1. Si hay ventanas abiertas, cerrar la de mayor FOCO.
	var top_window_id = UIOrchestrator.focus_manager.current_focus_id
	
	if top_window_id != "" and UIOrchestrator.is_window_open(top_window_id):
		# No queremos cerrar el HUD del jugador con ESC
		if top_window_id == "player_hud":
			_toggle_options()
			return
			
		UIOrchestrator.close_window(top_window_id)
		print("[UIInputRouter] ESC: Cerrada ventana ", top_window_id)
	else:
		# 2. Si no hay ventanas, Toggle de Opciones
		_toggle_options()

func _toggle_options():
	if UIOrchestrator:
		UIOrchestrator.toggle_window("options_menu")

func _handle_inventory():
	if AuthManager.auth_token != "":
		UIOrchestrator.toggle_window("inventory")

func _handle_codex():
	if UIOrchestrator:
		UIOrchestrator.toggle_window("codex_window")

func _handle_camera():
	var player = get_tree().get_first_node_in_group("player")
	if player:
		if player.has_method("toggle_camera_mode"):
			player.toggle_camera_mode()
		elif player.has_method("setup_camera"):
			player.camera_mode = 1 if player.camera_mode == 0 else 0
			player.setup_camera()

func _handle_admin():
	if AuthManager.auth_token != "" and AuthManager.is_admin:
		UIOrchestrator.toggle_window("admin_panel")
	else:
		print("[UIInputRouter] F10 ignorado o no autenticado.")

func _handle_db_admin():
	if AuthManager.auth_token != "" and AuthManager.is_admin:
		UIOrchestrator.toggle_window("database_admin")
	else:
		print("[UIInputRouter] F11 ignorado o no autenticado como admin.")

var hitbox_debug_active: bool = false

func _handle_hitbox_debug():
	hitbox_debug_active = !hitbox_debug_active
	print("[UIInputRouter] F9: Hitbox Debug toggled to: ", hitbox_debug_active)
	get_tree().call_group("hitbox_debug", "set_hitbox_debug_visible", hitbox_debug_active)
