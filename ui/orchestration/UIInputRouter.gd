extends Node

# UIInputRouter.gd - Despachador central de atajos de teclado
# Propósito: Centralizar ESC, I, V, F10, G (pings tácticos) y evitar conflictos entre escenas.

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS # Funciona incluso en pausa si es necesario

func _unhandled_input(event: InputEvent):
	# 0. RUEDA DE PINGS TÁCTICOS (G) — necesita también eventos de soltar y clic derecho,
	#    por eso se evalúa antes del filtro de "solo teclas pulsadas".
	if handle_tactical_ping_input(event, get_tree().current_scene if get_tree() else null):
		get_viewport().set_input_as_handled()
		return

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

	# 7. VISIÓN ESPECTRAL DE KI PULSO (P)
	elif (event.is_action_pressed("toggle_ki_vision") or (event is InputEventKey and event.pressed and event.keycode == KEY_P)) and not event.is_echo():
		_handle_ki_pulse()
		get_viewport().set_input_as_handled()

	# 8. DEPRECATED / DESACTIVADO (F8)
	elif event is InputEventKey and event.pressed and event.keycode == KEY_F8 and not event.is_echo():
		print("[UIInputRouter] F8 ignorado: El atajo fue desactivado. Usa F9 para alternar hitboxes.")
		get_viewport().set_input_as_handled()

## Atajo centralizado [G] de la Rueda de Pings Tácticos (ADR 097):
##   - G pulsada (sin eco): abre la rueda en la posición actual del cursor.
##   - G soltada: si la rueda está abierta, confirma el cuadrante seleccionado.
##   - Clic derecho con la rueda abierta: cancela inmediatamente.
## `world` debe exponer open/confirm/cancel_tactical_ping_wheel (World.gd).
## `cursor_override` (tests/replays) sustituye a la posición real del ratón.
## Devuelve true si el evento fue consumido.
func handle_tactical_ping_input(event: InputEvent, world: Node, cursor_override: Variant = null) -> bool:
	if world == null or not world.has_method("open_tactical_ping_wheel"):
		return false
	if event is InputEventKey and event.keycode == KEY_G:
		if event.is_echo():
			return world.is_tactical_ping_wheel_open()
		if event.pressed:
			return world.open_tactical_ping_wheel(_cursor_position(world, cursor_override))
		if world.is_tactical_ping_wheel_open():
			world.confirm_tactical_ping_wheel(_cursor_position(world, cursor_override))
			return true
		return false
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		return world.cancel_tactical_ping_wheel()
	return false

func _cursor_position(world: Node, cursor_override: Variant = null) -> Vector2:
	if cursor_override is Vector2:
		return cursor_override
	var vp: Viewport = world.get_viewport() if world.is_inside_tree() else null
	return vp.get_mouse_position() if vp else Vector2.ZERO

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

func _handle_ki_pulse():
	var world = get_tree().current_scene
	if world and world.has_method("trigger_ki_spectral_pulse"):
		world.trigger_ki_spectral_pulse()
	else:
		print("[UIInputRouter] P: Ki spectral pulse no disponible en la escena actual.")
