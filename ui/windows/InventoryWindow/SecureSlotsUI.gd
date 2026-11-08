extends Control

@onready var main_vbox = $PanelContainer/MarginContainer/ScrollContainer/VBoxContainer
@onready var title_label = $PanelContainer/MarginContainer/ScrollContainer/VBoxContainer/Title

var character_grid: GridContainer
var shelter_grid: GridContainer
var secure_grid: GridContainer

var grid_data_character = {} # Vector2i -> Slot
var grid_data_shelter = {}   # Vector2i -> Slot
var grid_data_secure = {}    # Vector2i -> Slot

const SLOT_SIZE = 64
var character_size_x = 10
var character_size_y = 5
var shelter_size_x = 10
var shelter_size_y = 5 # Changed from 10 to 5 to avoid enormous UI
var secure_size_x = 3
var secure_size_y = 3

var target_char_id = ""
var is_shelter_context = false
var is_read_only = false
var is_character_dead = false

var _grid_initialized = false
var _loaded_for_char_id = ""
var _pending_grid_rebuild = false

var _is_dragging = false
var _has_been_moved = false
var _drag_offset = Vector2.ZERO

func _ready():
	add_to_group("inventory_ui")
	
	# Asegurar que la ventana inicia oculta
	if not visible:
		visible = false
	
	# Enable dragging via title
	title_label.mouse_filter = Control.MOUSE_FILTER_STOP
	title_label.gui_input.connect(_on_title_gui_input)
	
	# Habilitar arrastre por bordes (PanelContainer principal)
	var main_panel = $PanelContainer
	if main_panel:
		main_panel.gui_input.connect(_on_title_gui_input)
	
	visibility_changed.connect(_on_visibility_changed)
	
	# Escuchar solicitudes de refresco del controlador (Desacoplamiento ADR 069)
	if has_node("/root/InventoryController"):
		get_node("/root/InventoryController").inventory_refresh_requested.connect(render_inventory_state)
		
	set_process(true)

func _on_visibility_changed():
	# Solo auto-refrescar si la ventana ya fue configurada antes (ej: MMO)
	# initialize_window se encarga de pedir el refresh en el primer uso
	if visible and _grid_initialized:
		_request_data_refresh()

func _on_title_gui_input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			request_focus()
			_is_dragging = event.pressed
			if _is_dragging:
				_has_been_moved = true
				_drag_offset = get_global_mouse_position() - global_position
	elif event is InputEventMouseMotion and _is_dragging:
		var new_pos = get_global_mouse_position() - _drag_offset
		
		# Clamping (Protección de bordes) considerando la escala
		var vp_size = get_viewport_rect().size
		var scaled_size = size * scale
		new_pos.x = clamp(new_pos.x, 0, vp_size.x - scaled_size.x)
		new_pos.y = clamp(new_pos.y, 0, vp_size.y - scaled_size.y)
		
		global_position = new_pos

func request_focus():
	if has_node("/root/UIOrchestrator"):
		# Usamos el ID registrado en el WindowRegistry
		get_node("/root/UIOrchestrator").focus_window("inventory")
	else:
		# Fallback si el orquestador no está (ej: tests aislados)
		move_to_front()

func _process(_delta):
	var vp = get_viewport_rect().size
	if vp.y <= 0: return

	# 1. ESCALADO (Siempre activo)
	# Combinamos el escalado dinámico por resolución con el zoom global del usuario
	var target_h = 1100.0 
	var base_scale = min(1.0, (vp.y * 0.9) / target_h)
	var final_zoom = base_scale * UIOrchestrator.layout_persistence.global_ui_zoom
	
	scale = Vector2(final_zoom, final_zoom)
	pivot_offset = size / 2.0

	# 2. POSICIONAMIENTO
	if not _has_been_moved:
		# Centrar horizontalmente, fijo arriba
		position.x = (vp.x - size.x * final_zoom) / 2.0
		position.y = 20
	else:
		# Si ya fue movido, solo aplicamos clamping reactivo por si cambió la resolución/zoom
		var new_pos = global_position
		var scaled_size = size * final_zoom
		new_pos.x = clamp(new_pos.x, 0, max(0, vp.x - scaled_size.x))
		new_pos.y = clamp(new_pos.y, 0, max(0, vp.y - scaled_size.y))
		global_position = new_pos

## Llamado por UIOrchestrator
func initialize_window(params: Dictionary):
	if not is_inside_tree(): await ready
	
	var old_char_id = target_char_id
	var old_context = is_shelter_context
	var old_is_dead = is_character_dead
	
	if params.has("character_id"):
		target_char_id = params["character_id"]
	if params.has("is_shelter_context"):
		is_shelter_context = params.get("is_shelter_context", false)
	if params.has("is_dead"):
		is_character_dead = params.get("is_dead", false)
	is_read_only = params.get("read_only", false)

	# SI EL REFUGIO ES UNA "BASE DE OPERACIONES":
	# La cuadrícula de Stash debe ser accesible siempre (Account-level), 
	# incluso sin personaje seleccionado. El character_id es opcional para este contexto.
	if not _grid_initialized or target_char_id != old_char_id or is_shelter_context != old_context or is_character_dead != old_is_dead:
		_pending_grid_rebuild = true
	
	if is_read_only:
		_setup_read_only_visual()
	
	# Pedir datos al controlador DESPUÉS de configurar los grids
	_request_data_refresh()

func _request_data_refresh():
	var char_id = target_char_id if target_char_id != "" else (AuthManager.selected_character_id if AuthManager else "")
	var state = await InventoryController.fetch_inventory_state(char_id)
	
	if not is_instance_valid(self) or not is_inside_tree(): return
	render_inventory_state(state)

func _setup_read_only_visual():
	var warning = Label.new()
	warning.text = "¡MODO RECUPERACIÓN! (Solo Extracción)"
	warning.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warning.add_theme_color_override("font_color", Color(1, 0.4, 0.4))
	main_vbox.add_child(warning)
	main_vbox.move_child(warning, 1) # Just below title

func setup_grid():
	_grid_initialized = true
	var no_char_selected = (target_char_id == "" and is_shelter_context)
	
	# LIMPIEZA DE MEMORIA
	grid_data_character.clear()
	grid_data_shelter.clear()
	grid_data_secure.clear()
	
	# Limpieza visual segura
	for child in main_vbox.get_children():
		if child == title_label: continue
		main_vbox.remove_child(child)
		child.queue_free()
	
	# 1. SETUP SHELTER STASH (Account-bound, Shared)
	_create_section("ALMACÉN DEL REFUGIO (Cuenta)", ShelterManager.InventoryType.SHELTER)
	
	# Si no hay personaje en el Shelter, solo mostramos el Stash
	if no_char_selected:
		custom_minimum_size = Vector2(850, 450)
		return
	
	# 2. SETUP SECURE CONTAINER
	main_vbox.add_child(HSeparator.new())
	if AuthManager.is_premium:
		secure_size_x = 10
		secure_size_y = 5
	else:
		secure_size_x = 3
		secure_size_y = 3
		
	var secure_title = "CONTENEDOR SEGURO " + ("(PREMIUM)" if AuthManager.is_premium else "(BÁSICO)")
	_create_section(secure_title, ShelterManager.InventoryType.SECURE)
	
	# 3. SETUP CHARACTER INVENTORY (Isolated per Character)
	if is_character_dead:
		_create_lost_inventory_warning()
	else:
		main_vbox.add_child(HSeparator.new())
		var char_title = "INVENTARIO DE PERSONAJE: " + AuthManager.selected_character_name
		_create_section(char_title, ShelterManager.InventoryType.CHARACTER)
	
	custom_minimum_size = Vector2(850, 800)

func _create_section(title: String, type: ShelterManager.InventoryType) -> Control:
	var label = Label.new()
	label.text = title
	if type == ShelterManager.InventoryType.SECURE and AuthManager.is_premium:
		label.add_theme_color_override("font_color", Color(1, 0.8, 0))
	main_vbox.add_child(label)
	
	var panel = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(panel)
	
	var grid = GridContainer.new()
	grid.add_theme_constant_override("h_separation", 5)
	grid.add_theme_constant_override("v_separation", 5)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(grid)
	
	var target_data = null
	var size_x = 0
	var size_y = 0
	
	match type:
		ShelterManager.InventoryType.CHARACTER:
			size_x = character_size_x
			size_y = character_size_y
			character_grid = grid
			target_data = grid_data_character
		ShelterManager.InventoryType.SHELTER:
			size_x = shelter_size_x
			size_y = shelter_size_y
			shelter_grid = grid
			target_data = grid_data_shelter
		ShelterManager.InventoryType.SECURE:
			size_x = secure_size_x
			size_y = secure_size_y
			secure_grid = grid
			target_data = grid_data_secure
			
	if target_data == null: return panel
			
	grid.columns = size_x
	for y in range(size_y):
		for x in range(size_x):
			var slot = InventorySlot.new()
			slot.slot_x = x
			slot.slot_y = y
			slot.inventory_owner = self 
			slot.inventory_type = type
			grid.add_child(slot)
			target_data[Vector2i(x, y)] = slot
			
	return panel

func _create_lost_inventory_warning():
	main_vbox.add_child(HSeparator.new())
	var label = Label.new()
	label.text = "⚠️ INVENTARIO PRINCIPAL PERDIDO (PERSONAJE MUERTO)"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color(1, 0.4, 0.4))
	main_vbox.add_child(label)
	
	var desc = Label.new()
	desc.text = "Debes saquear tu Death Echo en el mundo para recuperar estos objetos."
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.add_theme_font_size_override("font_size", 14)
	main_vbox.add_child(desc)

func can_place_item(item: InventoryItem, x: int, y: int, type: ShelterManager.InventoryType) -> bool:
	var w = item.grid_width if !item.is_rotated else item.grid_height
	var h = item.grid_height if !item.is_rotated else item.grid_width
	
	var target_grid = _get_grid_data(type)
	var max_size = _get_grid_size(type)
	
	# Seguridad: No permitir mover a grids de personaje si no hay selección en el Shelter
	if is_shelter_context and target_char_id == "":
		if type == ShelterManager.InventoryType.CHARACTER or type == ShelterManager.InventoryType.SECURE:
			return false
	
	if x < 0 or y < 0 or x + w > max_size.x or y + h > max_size.y:
		return false
	
	for iy in range(y, y + h):
		for ix in range(x, x + w):
			var slot = target_grid.get(Vector2i(ix, iy))
			if slot == null or (slot.is_occupied and slot.occupied_by != item):
				return false
	return true

func place_item(item: InventoryItem, x: int, y: int, type: ShelterManager.InventoryType, _persist: bool = true):
	if item.inventory_owner != null and item.slot_x != -1:
		item.inventory_owner.clear_occupancy(item)
	
	item.inventory_owner = self
	item.slot_x = x
	item.slot_y = y
	item.inventory_type = type
	
	var w = item.grid_width if !item.is_rotated else item.grid_height
	var h = item.grid_height if !item.is_rotated else item.grid_width
	var target_grid = _get_grid_data(type)
	
	for iy in range(y, y + h):
		for ix in range(x, x + w):
			var slot = target_grid.get(Vector2i(ix, iy))
			if slot:
				slot.is_occupied = true
				slot.occupied_by = item
	
	var anchor_slot = target_grid.get(Vector2i(x, y))
	if not is_instance_valid(anchor_slot): return
	
	if item.get_parent() != anchor_slot:
		if item.get_parent(): item.get_parent().remove_child(item)
		anchor_slot.add_child(item)
	
	item.position = Vector2.ZERO
	item.update_size()


func clear_occupancy(item: InventoryItem):
	var w = item.grid_width if !item.is_rotated else item.grid_height
	var h = item.grid_height if !item.is_rotated else item.grid_width
	var target_grid = _get_grid_data(item.inventory_type)
	
	for iy in range(item.slot_y, item.slot_y + h):
		for ix in range(item.slot_x, item.slot_x + w):
			var slot = target_grid.get(Vector2i(ix, iy))
			if slot and slot.occupied_by == item:
				slot.is_occupied = false
				slot.occupied_by = null

func _get_grid_data(type: ShelterManager.InventoryType) -> Dictionary:
	match type:
		ShelterManager.InventoryType.CHARACTER: return grid_data_character
		ShelterManager.InventoryType.SHELTER: return grid_data_shelter
		ShelterManager.InventoryType.SECURE: return grid_data_secure
	return {}

func _get_grid_size(type: ShelterManager.InventoryType) -> Vector2i:
	match type:
		ShelterManager.InventoryType.CHARACTER: return Vector2i(character_size_x, character_size_y)
		ShelterManager.InventoryType.SHELTER: return Vector2i(shelter_size_x, shelter_size_y)
		ShelterManager.InventoryType.SECURE: return Vector2i(secure_size_x, secure_size_y)
	return Vector2i.ZERO

## Método central de renderizado - Atómico y Sin parpadeo
func render_inventory_state(state: Dictionary):
	if not is_instance_valid(self): return
	
	# 1. Si la estructura cambió (ej: selección de PJ), reconstruimos los grids AHORA
	# justo antes de poner los nuevos ítems.
	if _pending_grid_rebuild:
		setup_grid()
		_pending_grid_rebuild = false
	
	# 2. Recopilar ítems actuales (los ocultamos pero NO los borramos todavía)
	var old_items = _collect_all_items()
	for item in old_items:
		if is_instance_valid(item):
			item.hide()
	
	# 2. Limpiar ocupancia de slots (sin borrar los nodos)
	for grid_dict in [grid_data_character, grid_data_shelter, grid_data_secure]:
		for key in grid_dict:
			var slot = grid_dict[key]
			if is_instance_valid(slot):
				slot.is_occupied = false
				slot.occupied_by = null
	
	# 3. Renderizar nuevos ítems (visibles desde el primer frame)
	var stash_items = state.get("stash_items", [])
	for item_data in stash_items:
		var pid = item_data.get("parent_item_id")
		if pid != null and str(pid) != "": continue
		
		# Contexto STASH: Todo es SHELTER a menos que sea SECURE
		var type = ShelterManager.InventoryType.SHELTER
		if item_data.get("is_secure_slot", false):
			type = ShelterManager.InventoryType.SECURE
			
		_try_place_backend_item(item_data, type)
	
	var char_items = state.get("char_items", [])
	for item_data in char_items:
		var pid = item_data.get("parent_item_id")
		if pid != null and str(pid) != "": continue
		
		# Contexto CHARACTER: Todo es CHARACTER a menos que sea SECURE
		var target_type = ShelterManager.InventoryType.CHARACTER
		if item_data.get("is_secure_slot", false):
			target_type = ShelterManager.InventoryType.SECURE
		
		# Renderizamos siempre para evitar confusión durante el looteo de recuperación
		_try_place_backend_item(item_data, target_type)
	
	# 4. Ahora sí liberamos los ítems viejos (ya no son visibles y hay nuevos en su lugar)
	for item in old_items:
		if is_instance_valid(item):
			item.queue_free()
	
	_loaded_for_char_id = target_char_id

## Recopilar todos los ítems actuales sin modificar el estado del grid
func _collect_all_items() -> Array:
	var items = []
	var seen_ids = {}
	for grid_dict in [grid_data_character, grid_data_shelter, grid_data_secure]:
		for key in grid_dict:
			var slot = grid_dict[key]
			if not is_instance_valid(slot): continue
			for child in slot.get_children():
				if child is InventoryItem:
					var inst_id = child.get_instance_id()
					if not seen_ids.has(inst_id):
						seen_ids[inst_id] = true
						items.append(child)
	return items

func reload_inventory():
	_request_data_refresh()

func toggle():
	visible = !visible
	if visible:
		if not _grid_initialized: setup_grid()
		_request_data_refresh()

func _clear_all_items():
	var cleared_ids = {}
	for grid_dict in [grid_data_character, grid_data_shelter, grid_data_secure]:
		for key in grid_dict:
			var slot = grid_dict[key]
			if not is_instance_valid(slot): continue
			
			for child in slot.get_children():
				if child is InventoryItem:
					var inst_id = child.get_instance_id()
					if not cleared_ids.has(inst_id):
						cleared_ids[inst_id] = true
						child.queue_free()
			slot.is_occupied = false
			slot.occupied_by = null

func _try_place_backend_item(item_data: Dictionary, type: ShelterManager.InventoryType):
	var item = _create_inventory_item(item_data)
	item.inventory_type = type
	var sx_raw = item_data.get("slot_x")
	var sy_raw = item_data.get("slot_y")
	var sx = int(sx_raw) if sx_raw != null else 0
	var sy = int(sy_raw) if sy_raw != null else 0
	if can_place_item(item, sx, sy, type):
		place_item(item, sx, sy, type, false)
		print("SecureSlotsUI: PLACED item '%s' (%s) at (%d,%d) Type=%d" % [item.item_id, item.item_name, sx, sy, type])
	else:
		print("SecureSlotsUI: REJECTED item '%s' (%s) at (%d,%d) due to conflict/bounds" % [item.item_id, item.item_name, sx, sy])
		item.queue_free()

func _create_inventory_item(item_data: Dictionary) -> InventoryItem:
	var item = InventoryItem.new()
	item.item_id = str(item_data.get("id", ""))
	item.item_name = item_data.get("display_name", item_data.get("item_name", "Unknown"))
	var gw_raw = item_data.get("grid_width")
	var gh_raw = item_data.get("grid_height")
	item.grid_width = int(gw_raw) if gw_raw != null else 1
	item.grid_height = int(gh_raw) if gh_raw != null else 1
	item.is_rotated = item_data.get("is_rotated", false)
	item.parent_item_id = str(item_data.get("parent_item_id", ""))
	item.is_container = item_data.get("is_container", false)
	item.inner_grid_width = int(item_data.get("inner_grid_width", 0))
	item.inner_grid_height = int(item_data.get("inner_grid_height", 0))
	item.quantity = int(item_data.get("quantity", 1))
	item.max_stack = ShelterManager.get_item_max_stack(item.item_name)
	
	item.container_open_requested.connect(_on_container_open_requested)
	item.rotate_requested.connect(func(): 
		if has_node("/root/InventoryController"):
			get_node("/root/InventoryController").request_item_rotation(item)
	)
	
	var icon = item_data.get("icon_path", "")
	if typeof(icon) == TYPE_STRING and icon != "" and ResourceLoader.exists(icon):
		item.texture = load(icon)
	else:
		item.texture = _get_sleek_fallback_texture(item_data.get("name", ""), item.grid_width, item.grid_height)
	return item

func _get_sleek_fallback_texture(item_name: String, gw: int, gh: int) -> ImageTexture:
	var w = max(64, gw * 64)
	var h = max(64, gh * 64)
	var img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	var bg_col = Color(0.12, 0.16, 0.22, 0.95)
	var border_col = Color(0.25, 0.45, 0.75, 1.0)
	if "Madera" in item_name or "Wood" in item_name:
		bg_col = Color(0.28, 0.18, 0.10, 0.95)
		border_col = Color(0.60, 0.40, 0.25, 1.0)
	elif "Hierro" in item_name or "Iron" in item_name:
		bg_col = Color(0.18, 0.22, 0.28, 0.95)
		border_col = Color(0.50, 0.65, 0.85, 1.0)
	elif "Piedra" in item_name or "Stone" in item_name:
		bg_col = Color(0.22, 0.24, 0.26, 0.95)
		border_col = Color(0.55, 0.58, 0.62, 1.0)
	elif "Kit" in item_name or "Silo" in item_name:
		bg_col = Color(0.10, 0.22, 0.26, 0.95)
		border_col = Color(0.10, 0.80, 0.90, 1.0)
	img.fill(bg_col)
	for x in range(w):
		img.set_pixel(x, 0, border_col)
		img.set_pixel(x, 1, border_col)
		img.set_pixel(x, h - 1, border_col)
		img.set_pixel(x, h - 2, border_col)
	for y in range(h):
		img.set_pixel(0, y, border_col)
		img.set_pixel(1, y, border_col)
		img.set_pixel(w - 1, y, border_col)
		img.set_pixel(w - 2, y, border_col)
	return ImageTexture.create_from_image(img)

func _on_container_open_requested(item_id, item_data):
	if has_node("/root/UIOrchestrator"):
		var orchestrator = get_node("/root/UIOrchestrator")
		orchestrator.open_window("backpack", item_data, "backpack_" + item_id)
		var instance = orchestrator.registry.get_instance("backpack_" + item_id)
		if instance and instance.visible and instance.global_position == Vector2.ZERO:
			instance.global_position = get_global_mouse_position() - Vector2(100, 100)
