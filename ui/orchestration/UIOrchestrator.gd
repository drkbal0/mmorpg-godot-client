extends Node

# Autoload Facade para la orquestación de UI
# Propósito: Única interfaz para abrir/cerrar ventanas en el cliente.

const UITypes = preload("res://ui/types/UITypes.gd")
const WindowRegistry = preload("res://ui/orchestration/UIWindowRegistry.gd")
const FocusManager = preload("res://ui/orchestration/UIFocusManager.gd")
const LayoutPersistence = preload("res://ui/orchestration/UILayoutPersistence.gd")

var registry: WindowRegistry
var focus_manager: FocusManager
var layout_persistence: LayoutPersistence

var window_layer: CanvasLayer
var drag_layer: CanvasLayer

var _active_drag_visual: Control = null
var _active_drag_offset: Vector2 = Vector2.ZERO

func _ready() -> void:
	# Inicializar componentes internos
	registry = WindowRegistry.new()
	add_child(registry)
	
	focus_manager = FocusManager.new()
	add_child(focus_manager)
	
	layout_persistence = LayoutPersistence.new()
	add_child(layout_persistence)
	
	# Capa dedicada para ventanas (ADR 069 - Capacidad de capas)
	window_layer = CanvasLayer.new()
	window_layer.name = "WindowLayer"
	window_layer.layer = 10 
	add_child(window_layer)
	
	drag_layer = CanvasLayer.new()
	drag_layer.name = "DragLayer"
	drag_layer.layer = 100 # Máxima prioridad para arrastre
	add_child(drag_layer)
	
	# --- CICLO DE VIDA ---
	set_process(true)
	
	print("[UIOrchestrator] Inicializado correctamente.")

func _input(event: InputEvent) -> void:
	if is_instance_valid(_active_drag_visual) and event is InputEventMouseMotion:
		drag_layer.offset = event.position

func _process(_delta):
	# Si hay un arrastre activo, la capa de drag completa sigue al ratón
	if is_instance_valid(_active_drag_visual):
		drag_layer.offset = drag_layer.get_viewport().get_mouse_position()
	else:
		drag_layer.offset = Vector2.ZERO

# --- API Pública ---

func start_drag_follow(visual: Control, offset: Vector2 = Vector2.ZERO) -> void:
	if is_instance_valid(_active_drag_visual):
		_active_drag_visual.queue_free()
	
	_active_drag_visual = visual
	_active_drag_offset = offset
	
	if visual.get_parent():
		visual.get_parent().remove_child(visual)
	drag_layer.add_child(visual)
	
	# Sincronizar offset de capa inmediatamente para evitar teleport de 1 frame
	drag_layer.offset = drag_layer.get_viewport().get_mouse_position()
	
	# El visual se posiciona en -offset para que el ratón (que es el 0,0 de la capa) 
	# coincida con el punto exacto donde se hizo click (en píxeles de pantalla).
	visual.position = -offset
	print("[UIOrchestrator] Drag iniciado con offset global: ", offset)

func stop_drag_follow() -> void:
	if is_instance_valid(_active_drag_visual):
		_active_drag_visual.queue_free()
	_active_drag_visual = null

func open_window(id: String, params: Dictionary = {}, custom_instance_id: String = "") -> Node:
	var registry_id = id
	var instance_id = custom_instance_id if custom_instance_id != "" else id
	var persistence_key = _get_scoped_id(instance_id)
	
	if not registry.is_registered(registry_id):
		push_error("[UIOrchestrator] Error: Ventana no registrada: " + registry_id)
		return null
	
	var meta = registry.get_metadata(registry_id)
	var instance = registry.get_instance(instance_id)
	var is_new = instance == null
	
	if is_new:
		# Lazy loading e instanciación
		if meta.scene_path == "":
			push_warning("[UIOrchestrator] Ventana " + id + " no tiene scene_path definida.")
			return null
			
		var scene = load(meta.scene_path)
		if scene is PackedScene:
			instance = scene.instantiate()
		elif scene is GDScript:
			# Caso especial para AdminPanel.gd que construye su propia UI
			instance = scene.new()
		
		# Inyectar parámetros antes de que entre al árbol (previo a _ready)
		# Determinar dónde añadir la instancia (CanvasLayer según categoría)
		window_layer.add_child(instance)
		registry.set_instance(instance_id, instance)
		
		# IMPORTANTE: Se llama initialize_window DESPUÉS de add_child para que 
		# las variables @onready (ej: main_vbox) ya estén listas.
		if instance.has_method("initialize_window"):
			instance.initialize_window(params)
	else:
		# Si ya existe, re-inicializar parámetros si el método está disponible
		if instance.has_method("initialize_window"):
			instance.initialize_window(params)
	
	# Restaurar posición persistente o Smart Spawn
	if instance is Control:
		var saved_pos = layout_persistence.get_window_position(persistence_key)
		var vp_size = instance.get_viewport_rect().size
		
		if saved_pos != null:
			# Aplicar Clamping de Seguridad (Safe Load)
			var scaled_size = instance.size * (instance.scale * layout_persistence.global_ui_zoom)
			saved_pos.x = clamp(saved_pos.x, 0, max(0, vp_size.x - scaled_size.x))
			saved_pos.y = clamp(saved_pos.y, 0, max(0, vp_size.y - scaled_size.y))
			instance.global_position = saved_pos
			if "_has_been_moved" in instance:
				instance._has_been_moved = true
		elif is_new:
			# Smart Spawning inicial (solo si es nueva y no tiene persistencia)
			if custom_instance_id != "": 
				var mouse_pos = instance.get_global_mouse_position()
				var target_pos = mouse_pos - Vector2(100, 20)
				var scaled_size = instance.size * (instance.scale * layout_persistence.global_ui_zoom)
				target_pos.x = clamp(target_pos.x, 0, max(0, vp_size.x - scaled_size.x))
				target_pos.y = clamp(target_pos.y, 0, max(0, vp_size.y - scaled_size.y))
				instance.global_position = target_pos
	
	instance.visible = true
	
	# Skip focus for HUD or non-interactive elements
	if meta.category != UITypes.WindowCategory.HUD:
		focus_manager.request_focus(instance_id, instance)
		
	return instance

func close_window(id: String, free_instance: bool = false) -> void:
	var instance = registry.get_instance(id)
	if instance:
		# Guardar posición si ha sido movida
		if instance is Control:
			var needs_save = true
			if "_has_been_moved" in instance:
				needs_save = instance._has_been_moved
			
			if needs_save:
				# Si la ventana se auto-posiciona por _process (como el inventario inicial)
				# solo queremos guardar si el usuario la movió manualmente.
				var persistence_key = _get_scoped_id(id)
				layout_persistence.set_window_position(persistence_key, instance.global_position)
		
		instance.visible = false
		if free_instance:
			registry.remove_instance(id)
			instance.queue_free()
			print("[UIOrchestrator] Ventana liberada: ", id)
		else:
			print("[UIOrchestrator] Ventana oculta: ", id)

func _get_scoped_id(id: String) -> String:
	# Si es una mochila, el id ya contiene el ID de item único (backpack_<item_id>)
	# por lo que es intrínsecamente global. No loScopeamos más.
	if id.begins_with("backpack_") or id == "admin_panel":
		return id
		
	if AuthManager.selected_character_id != "":
		return "char_" + AuthManager.selected_character_id + "_" + id
	elif AuthManager.user_id != "":
		return "user_" + AuthManager.user_id + "_" + id
	return id

func toggle_window(id: String, params: Dictionary = {}, custom_instance_id: String = "") -> void:
	var instance = registry.get_instance(id)
	if instance and instance.visible:
		close_window(id)
	else:
		open_window(id, params, custom_instance_id)

func focus_window(id: String) -> void:
	var instance = registry.get_instance(id)
	if instance:
		focus_manager.request_focus(id, instance)

func focus_instance(id: String, node: Node) -> void:
	if node:
		focus_manager.request_focus(id, node)

func register_instance(id: String, node: Node) -> void:
	if registry:
		registry.set_instance(id, node)

func is_window_open(id: String) -> bool:
	var instance = registry.get_instance(id)
	return instance != null and instance.visible

func is_mouse_over_ui() -> bool:
	# Si hay un menú contextual abierto, cuenta como UI
	if is_instance_valid(_active_context_menu) and _active_context_menu.visible:
		var mouse_pos = get_viewport().get_mouse_position()
		if Rect2(_active_context_menu.position, _active_context_menu.size).has_point(mouse_pos):
			return true
			
	var all_ids = registry.get_all_instance_ids()
	for id in all_ids:
		var instance = registry.get_instance(id)
		if instance and (instance is Control or instance is CanvasLayer) and instance.visible:
			var meta = registry.get_metadata(id)
			# Ignorar HUD
			if meta != null and meta.category == UITypes.WindowCategory.HUD:
				continue
				
			# Si es una ventana Modal o Full Screen, bloquea todo input al mundo 3D
			if meta != null and (meta.category == UITypes.WindowCategory.MODAL_OVERLAY or meta.category == UITypes.WindowCategory.FULL_SCREEN or meta.modal_policy != UITypes.ModalPolicy.NONE):
				return true
				
			if instance is Control:
				var mouse_pos = instance.get_global_mouse_position()
				if instance.get_global_rect().has_point(mouse_pos):
					return true
				
	return false

func bring_to_front(id: String) -> void:
	focus_window(id)

func get_window_instance(id: String) -> Node:
	if registry:
		return registry.get_instance(id)
	return null

## Cierra y libera TODAS las ventanas activas.
## Debe llamarse antes de cualquier transición de escena.
func close_all_windows() -> void:
	var all_ids = registry.get_all_instance_ids()
	for id in all_ids:
		close_window(id, true)
	if is_instance_valid(_active_context_menu):
		_active_context_menu.queue_free()
	print("[UIOrchestrator] Todas las ventanas cerradas y liberadas.")

var _active_context_menu: PopupMenu = null

## Abre un menú contextual único. Si ya hay uno abierto, lo cierra.
func open_context_menu(options: Array, pos: Vector2, callback: Callable) -> PopupMenu:
	if is_instance_valid(_active_context_menu):
		_active_context_menu.queue_free()
	
	_active_context_menu = PopupMenu.new()
	_active_context_menu.name = "GlobalContextMenu"
	window_layer.add_child(_active_context_menu)
	
	for i in range(options.size()):
		var opt = options[i]
		_active_context_menu.add_item(opt["label"], i)
		if opt.has("color"):
			_active_context_menu.set_item_metadata(i, opt.get("metadata"))
			# Use icons or modulation for coloring
			_active_context_menu.set_item_icon_modulate(i, opt["color"])
			# modulate the whole item text color if possible
	
	_active_context_menu.id_pressed.connect(callback)
	_active_context_menu.position = Vector2i(pos)
	_active_context_menu.popup()
	
	# Auto-close on mouse click outside (default behavior of PopupMenu)
	return _active_context_menu

## Muestra una notificación banner / toast flotante y llamativa en la parte superior-central
var _toast_container: VBoxContainer = null

func show_toast(title: String, message: String, accent_color: Color = Color(1.0, 0.85, 0.3), duration: float = 3.5) -> void:
	if not is_instance_valid(window_layer): return
	
	if not is_instance_valid(_toast_container):
		_toast_container = VBoxContainer.new()
		_toast_container.name = "ToastContainer"
		_toast_container.set_anchors_preset(Control.PRESET_TOP_WIDE)
		_toast_container.offset_top = 28.0
		_toast_container.offset_bottom = 200.0
		_toast_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_toast_container.add_theme_constant_override("separation", 8)
		_toast_container.alignment = BoxContainer.ALIGNMENT_BEGIN
		window_layer.add_child(_toast_container)
		
	var toast = PanelContainer.new()
	toast.custom_minimum_size = Vector2(440, 60)
	toast.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.08, 0.12, 0.96)
	sb.border_width_left = 3
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 2
	sb.border_color = accent_color
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_right = 8
	sb.corner_radius_bottom_left = 8
	sb.shadow_size = 10
	sb.shadow_color = Color(0, 0, 0, 0.7)
	toast.add_theme_stylebox_override("panel", sb)
	
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 10)
	toast.add_child(margin)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	margin.add_child(vbox)
	
	var title_lbl = Label.new()
	title_lbl.text = title
	title_lbl.add_theme_font_size_override("font_size", 12)
	title_lbl.add_theme_color_override("font_color", accent_color)
	title_lbl.add_theme_constant_override("outline_size", 2)
	title_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	vbox.add_child(title_lbl)
	
	var msg_lbl = Label.new()
	msg_lbl.text = message
	msg_lbl.add_theme_font_size_override("font_size", 11)
	msg_lbl.add_theme_color_override("font_color", Color(0.92, 0.95, 1.0))
	msg_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(msg_lbl)
	
	_toast_container.add_child(toast)
	
	# Animación: aparición con pulso y deslizamiento
	toast.modulate = Color(1, 1, 1, 0)
	toast.scale = Vector2(0.9, 0.9)
	toast.pivot_offset = Vector2(220, 30)
	
	var tw = toast.create_tween()
	tw.set_parallel(true)
	tw.tween_property(toast, "modulate:a", 1.0, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(toast, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	
	# Desvanecimiento tras duration
	tw.chain().tween_interval(duration)
	tw.chain().tween_property(toast, "modulate:a", 0.0, 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_callback(toast.queue_free)


# --- UI v2.4: Menú común superior (res://ui/menu/menu_bar.tscn) ---

## Señal informativa: el menú pidió una ventana que aún no está registrada
## (p. ej. Tienda / Pase en construcción, Poderes, Misiones…).
signal menu_navigation_unhandled(window_id: String, params: Dictionary)

var _menu_bars: Array = []


## Conecta una barra de menú a la orquestación. Idempotente.
func connect_menu_bar(bar: Node) -> void:
	if bar == null or _menu_bars.has(bar):
		return
	_menu_bars.append(bar)
	bar.navigation_requested.connect(_on_menu_navigation_requested)
	bar.close_requested.connect(_on_menu_close_requested)
	bar.tree_exiting.connect(func() -> void: _menu_bars.erase(bar))


## Traduce una petición de navegación del menú a `toggle_window()`.
## Devuelve true si la ventana está registrada y se abrió/cerró.
func _on_menu_navigation_requested(window_id: String, params: Dictionary = {}) -> bool:
	if registry == null or not registry.is_registered(window_id):
		push_warning("[UIOrchestrator] Menú: ventana sin registrar '%s' (pendiente de fase UI v2.4)." % window_id)
		menu_navigation_unhandled.emit(window_id, params)
		return false
	toggle_window(window_id, params)
	return true


func _on_menu_close_requested() -> void:
	if focus_manager == null:
		return
	var top_id: String = focus_manager.current_focus_id
	if top_id != "" and top_id != "player_hud" and is_window_open(top_id):
		close_window(top_id)
