extends PanelContainer
class_name SubInventoryContainer

# SubInventoryContainer.gd - Floating UI for nested inventory (backpacks)

var target_container_id: String = ""
var container_name: String = ""
var grid_width: int = 5
var grid_height: int = 5
const SLOT_SIZE = 64 # Consistencia total con el inventario principal

var grid_node: GridContainer = null
var title_label: Label = null
var slot_data = {} # Vector2i -> InventorySlot

var _is_dragging = false
var _has_been_moved = false
var _drag_offset = Vector2.ZERO

var is_loot: bool = false
var echo_id: String = ""

func initialize_window(params = {}):
	if params.has("item_id"):
		target_container_id = params["item_id"]
	if params.has("name"):
		container_name = params["name"]
	if params.has("grid_width"):
		grid_width = params["grid_width"]
	if params.has("grid_height"):
		grid_height = params["grid_height"]
	if params.has("is_loot"):
		is_loot = params["is_loot"]
	if params.has("echo_id"):
		echo_id = params["echo_id"]
	
	# Calcular tamaño basado en SLOT_SIZE (52px) por slot + 5px de separación
	var content_w = grid_width * SLOT_SIZE + (grid_width - 1) * 5 + 20
	var content_h = grid_height * SLOT_SIZE + (grid_height - 1) * 5 + 65
	
	# Actualizar UI si ya está en el árbol
	if title_label:
		title_label.text = container_name.to_upper()
	
	if grid_node:
		# Forzar recalculado de tamaño
		custom_minimum_size = Vector2(content_w, content_h)
		size = custom_minimum_size
		grid_node.columns = grid_width
		setup_grid()
		load_items()

func _ready():
	var content_w = grid_width * SLOT_SIZE + (grid_width - 1) * 5 + 20
	var content_h = grid_height * SLOT_SIZE + (grid_height - 1) * 5 + 65
	custom_minimum_size = Vector2(content_w, content_h)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Permitir arrastre por los bordes conectando el panel principal
	gui_input.connect(_on_header_gui_input)
	
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.1, 0.1, 0.95)
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.border_color = Color(0.4, 0.4, 0.4, 1.0)
	add_theme_stylebox_override("panel", sb)
	
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	add_child(margin)
	
	var vbox = VBoxContainer.new()
	margin.add_child(vbox)
	
	# Header
	var header = HBoxContainer.new()
	vbox.add_child(header)
	
	title_label = Label.new()
	title_label.text = container_name.to_upper()
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.mouse_filter = Control.MOUSE_FILTER_STOP
	title_label.gui_input.connect(_on_header_gui_input)
	header.add_child(title_label)
	
	var close_btn = Button.new()
	close_btn.text = "X"
	close_btn.pressed.connect(_on_close_pressed)
	header.add_child(close_btn)
	
	vbox.add_child(HSeparator.new())
	
	# Grid
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)
	
	grid_node = GridContainer.new()
	grid_node.columns = grid_width
	grid_node.add_theme_constant_override("h_separation", 5)
	grid_node.add_theme_constant_override("v_separation", 5)
	scroll.add_child(grid_node)
	
	setup_grid()
	load_items()
	set_process(true)

func _process(_delta):
	var vp = get_viewport_rect().size
	if vp.y <= 0: return
	
	# 1. ESCALADO (Siempre activo)
	var target_h = 1100.0 
	var base_scale = min(1.0, (vp.y * 0.9) / target_h)
	var final_zoom = base_scale * UIOrchestrator.layout_persistence.global_ui_zoom
	
	scale = Vector2(final_zoom, final_zoom)
	pivot_offset = size / 2.0
	
	# 2. POSICIONAMIENTO (Clamping reactivo si fue movida)
	if _has_been_moved:
		var new_pos = global_position
		var scaled_size = size * final_zoom
		new_pos.x = clamp(new_pos.x, 0, max(0, vp.x - scaled_size.x))
		new_pos.y = clamp(new_pos.y, 0, max(0, vp.y - scaled_size.y))
		global_position = new_pos

func _on_header_gui_input(event):
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
		get_node("/root/UIOrchestrator").focus_instance("backpack_" + target_container_id, self)
	else:
		move_to_front()

func _on_focus_requested(event):
	if event is InputEventMouseButton and event.pressed:
		request_focus()

func setup_grid():
	# Limpiar slots viejos si existen
	if grid_node:
		for child in grid_node.get_children():
			child.queue_free()
	
	slot_data.clear()
	
	for y in range(grid_height):
		for x in range(grid_width):
			var slot = InventorySlot.new()
			slot.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
			slot.slot_x = x
			slot.slot_y = y
			slot.inventory_owner = self
			# Nested items don't have a specific type, but we can treat them as CHARACTER for logic
			slot.inventory_type = ShelterManager.InventoryType.CHARACTER
			grid_node.add_child(slot)
			slot_data[Vector2i(x, y)] = slot

func load_items():
	# Use the unified cache instead of the partial inventory list
	for item_data in ShelterManager.all_items_cache.values():
		var pid = item_data.get("parent_item_id")
		if pid != null and str(pid) == target_container_id:
			_try_place_item(item_data)

func _try_place_item(item_data: Dictionary):
	# Using logic from SecureSlotsUI for consistency
	var item = InventoryItem.new()
	item.item_id = str(item_data.get("id", ""))
	item.item_name = item_data.get("display_name", item_data.get("item_name", "Unknown"))
	item.grid_width = int(item_data.get("grid_width", 1))
	item.grid_height = int(item_data.get("grid_height", 1))
	item.is_rotated = item_data.get("is_rotated", false)
	item.parent_item_id = str(item_data.get("parent_item_id", ""))
	item.is_container = item_data.get("is_container", false)
	item.inner_grid_width = int(item_data.get("inner_grid_width", 0))
	item.inner_grid_height = int(item_data.get("inner_grid_height", 0))
	item.quantity = int(item_data.get("quantity", 1))
	item.max_stack = ShelterManager.get_item_max_stack(item.item_name)
	
	var icon = item_data.get("icon_path", "")
	if typeof(icon) == TYPE_STRING and icon != "" and FileAccess.file_exists(icon):
		item.texture = load(icon)
	else:
		var placeholder = PlaceholderTexture2D.new()
		placeholder.size = Vector2(64 * item.grid_width, 64 * item.grid_height)
		item.texture = placeholder

	item.rotate_requested.connect(func():
		if has_node("/root/InventoryController"):
			get_node("/root/InventoryController").request_item_rotation(item)
	)

	var sx = int(item_data.get("slot_x", 0))
	var sy = int(item_data.get("slot_y", 0))
	
	if can_place_item(item, sx, sy, item.inventory_type):
		place_item(item, sx, sy, item.inventory_type, false)

func can_place_item(item: InventoryItem, x: int, y: int, _type):
	var w = item.grid_width if !item.is_rotated else item.grid_height
	var h = item.grid_height if !item.is_rotated else item.grid_width
	
	if x < 0 or y < 0 or x + w > grid_width or y + h > grid_height:
		return false
	
	for iy in range(y, y + h):
		for ix in range(x, x + w):
			var slot = slot_data.get(Vector2i(ix, iy))
			if slot == null or (slot.is_occupied and slot.occupied_by != item):
				return false
	return true

func get_container_item_id() -> String:
	if is_loot:
		return "loot_" + echo_id + "_" + target_container_id
	return target_container_id

func place_item(item: InventoryItem, x: int, y: int, _type, _persist: bool = true):
	if item.inventory_owner != null and item.slot_x != -1:
		item.inventory_owner.clear_occupancy(item)
	
	item.inventory_owner = self
	item.slot_x = x
	item.slot_y = y
	
	var w = item.grid_width if !item.is_rotated else item.grid_height
	var h = item.grid_height if !item.is_rotated else item.grid_width
	
	for iy in range(y, y + h):
		for ix in range(x, x + w):
			var slot = slot_data.get(Vector2i(ix, iy))
			if slot:
				slot.is_occupied = true
				slot.occupied_by = item
	
	var anchor_slot = slot_data[Vector2i(x, y)]
	if item.get_parent() != anchor_slot:
		if item.get_parent(): item.get_parent().remove_child(item)
		anchor_slot.add_child(item)
		if !item.container_open_requested.is_connected(_on_container_open_requested):
			item.container_open_requested.connect(_on_container_open_requested)
	
	item.position = Vector2.ZERO
	item.update_size()

func reload_inventory():
	# Limpiar todos los ítems visuales actuales
	for key in slot_data:
		var slot = slot_data[key]
		for child in slot.get_children():
			if child is InventoryItem:
				child.queue_free()
		slot.is_occupied = false
		slot.occupied_by = null
	# Re-cargar desde el caché
	load_items()


func _on_container_open_requested(item_id, item_data):
	if has_node("/root/UIOrchestrator"):
		if is_loot:
			item_data["is_loot"] = true
			item_data["echo_id"] = echo_id
		get_node("/root/UIOrchestrator").open_window("backpack", item_data, "backpack_" + item_id)

func _on_close_pressed():
	if has_node("/root/UIOrchestrator"):
		get_node("/root/UIOrchestrator").close_window("backpack_" + target_container_id, true)
	else:
		queue_free()

func clear_occupancy(item: InventoryItem):
	var w = item.grid_width if !item.is_rotated else item.grid_height
	var h = item.grid_height if !item.is_rotated else item.grid_width
	
	for iy in range(item.slot_y, item.slot_y + h):
		for ix in range(item.slot_x, item.slot_x + w):
			var slot = slot_data.get(Vector2i(ix, iy))
			if slot and slot.occupied_by == item:
				slot.is_occupied = false
				slot.occupied_by = null
