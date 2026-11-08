extends PanelContainer
class_name LootContainer

# LootContainer.gd - UI para saquear cadáveres (Death Echoes)

var echo_id: String = ""
var loot_name: String = ""
var grid_width: int = 10
var grid_height: int = 15

# Helper para soportar snake_case y camelCase de gRPC-gateway
func _get_field(dict: Dictionary, key: String, default = null):
	if dict.has(key): return dict[key]
	var camel = ""
	var parts = key.split("_")
	for i in range(parts.size()):
		if i == 0: camel += parts[i]
		else: camel += parts[i].capitalize()
	if dict.has(camel): return dict[camel]
	return default

const SLOT_SIZE = 64

var grid_node: GridContainer = null
var title_label: Label = null
var slot_data = {} # Vector2i -> InventorySlot

var _is_dragging = false
var _has_been_moved = false
var _drag_offset = Vector2.ZERO

func initialize_window(params = {}):
	if not is_inside_tree(): await ready
	
	if params.has("echo_id"):
		echo_id = params["echo_id"]
	if params.has("name"):
		loot_name = params["name"]
	
	setup_grid()
	fetch_loot()
	
	if title_label:
		title_label.text = "BOTÍN: " + loot_name.to_upper()

func _ready():
	custom_minimum_size = Vector2(400, 500)
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_on_header_gui_input)
	
	if NetworkManager and not NetworkManager.echo_item_collected.is_connected(_on_echo_item_collected):
		NetworkManager.echo_item_collected.connect(_on_echo_item_collected)
	
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.15, 0.05, 0.05, 0.9) # Darker red tint for looting
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.border_color = Color(0.6, 0.2, 0.2, 1.0)
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
	title_label.text = "BOTÍN: " + loot_name.to_upper()
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
	
	# Connect to zoom changes for stable scaling
	if UIOrchestrator and UIOrchestrator.layout_persistence:
		UIOrchestrator.layout_persistence.zoom_changed.connect(_on_zoom_changed)
	
	_update_scale()
	set_process(true)

func _on_zoom_changed(_new_zoom: float):
	_update_scale()

func _update_scale():
	var vp = get_viewport_rect().size
	if vp.y <= 0: return
	
	var target_h = 1100.0 
	var base_scale = min(1.0, (vp.y * 0.9) / target_h)
	
	var final_zoom = base_scale
	if UIOrchestrator and UIOrchestrator.layout_persistence:
		final_zoom *= UIOrchestrator.layout_persistence.global_ui_zoom
	
	scale = Vector2(final_zoom, final_zoom)
	pivot_offset = size / 2.0

func _process(_delta):
	var vp = get_viewport_rect().size
	if vp.y <= 0: return
	
	if _has_been_moved:
		var final_zoom = scale.x
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
		global_position = new_pos

func request_focus():
	if has_node("/root/UIOrchestrator"):
		get_node("/root/UIOrchestrator").focus_instance("loot_" + echo_id, self)

func setup_grid():
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
			slot.inventory_type = ShelterManager.InventoryType.CHARACTER # Loot area
			grid_node.add_child(slot)
			slot_data[Vector2i(x, y)] = slot

func fetch_loot():
	if echo_id == "": return
	
	print("[LootContainer] Fetching loot for: ", echo_id)
	var res = await APIClient.fetch_death_echo(echo_id)
	
	# La respuesta de APIClient viene en res["data"]
	if res.has("data"):
		var data = res["data"]
		# gRPC-Gateway mapea inv_width a inv_width o invWidth según el tag. 
		# Priorizar inv_width del eco si existe (dimensión del PJ muerto)
		grid_width = int(_get_field(data, "inv_width", 10))
		grid_height = int(_get_field(data, "inv_height", 15))
		
		print("[LootContainer] Rezizing grid to: ", grid_width, "x", grid_height)
		setup_grid()
		
		var items = data.get("items", [])
		for item_data in items:
			var pid = _get_field(item_data, "parent_item_id", "")
			if pid == null or str(pid) == "":
				_place_loot_item(item_data)
	elif res.has("items"): # Fallback por si la estructura es plana
		for item_data in res["items"]:
			if not item_data.has("parent_item_id") or item_data["parent_item_id"] == null or item_data["parent_item_id"] == "":
				_place_loot_item(item_data)
	
	# Cache items so they can be opened as containers if needed
	if res.has("data") and res["data"].has("items"):
		for item_data in res["data"]["items"]:
			var i_id = str(item_data.get("id", ""))
			var is_container = int(item_data.get("inner_grid_width", 0)) > 0
			ShelterManager.all_items_cache[i_id] = {
				"parent_item_id": item_data.get("parent_item_id", ""),
				"is_container": is_container,
				"inner_grid_width": int(item_data.get("inner_grid_width", 0)),
				"inner_grid_height": int(item_data.get("inner_grid_height", 0)),
				"item_definition_id": item_data.get("item_definition_id", ""),
				"display_name": item_data.get("display_name", "???")
			}

func _place_loot_item(item_data: Dictionary):
	var item = InventoryItem.new()
	item.item_id = str(_get_field(item_data, "id", ""))
	item.item_name = _get_field(item_data, "display_name", "???")
	item.grid_width = int(_get_field(item_data, "grid_width", 1))
	item.grid_height = int(_get_field(item_data, "grid_height", 1))
	item.is_container = int(_get_field(item_data, "inner_grid_width", 0)) > 0
	item.inner_grid_width = int(_get_field(item_data, "inner_grid_width", 0))
	item.inner_grid_height = int(_get_field(item_data, "inner_grid_height", 0))
	item.is_rotated = _get_field(item_data, "is_rotated", false)
	item.quantity = int(_get_field(item_data, "quantity", 1))
	item.max_stack = ShelterManager.get_item_max_stack(item.item_name)
	item.set_meta("item_definition_id", _get_field(item_data, "item_definition_id", ""))
	
	var icon = _get_field(item_data, "icon_path", "")
	if icon != "" and FileAccess.file_exists(icon):
		item.texture = load(icon)
	
	var sx = int(_get_field(item_data, "slot_x", 0))
	var sy = int(_get_field(item_data, "slot_y", 0))
	
	if !item.container_open_requested.is_connected(_on_container_open_requested):
		item.container_open_requested.connect(_on_container_open_requested)
		
	place_item(item, sx, sy, item.inventory_type, false)

func _on_container_open_requested(item_id, item_data):
	if has_node("/root/UIOrchestrator"):
		# Inyectamos el contexto de botín para que la mochila sepa que es del eco
		item_data["is_loot"] = true
		item_data["echo_id"] = echo_id
		get_node("/root/UIOrchestrator").open_window("backpack", item_data, "backpack_" + item_id)

func place_item(item: InventoryItem, x: int, y: int, _type, _persist: bool = true):
	if item.inventory_owner != null:
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
	if item.get_parent(): item.get_parent().remove_child(item)
	anchor_slot.add_child(item)
	item.position = Vector2.ZERO

func clear_occupancy(item: InventoryItem):
	var w = item.grid_width if !item.is_rotated else item.grid_height
	var h = item.grid_height if !item.is_rotated else item.grid_width
	for iy in range(item.slot_y, item.slot_y + h):
		for ix in range(item.slot_x, item.slot_x + w):
			var slot = slot_data.get(Vector2i(ix, iy))
			if slot and slot.occupied_by == item:
				slot.is_occupied = false
				slot.occupied_by = null
	_check_empty_and_close()

func can_place_item(item: InventoryItem, x: int, y: int, _type) -> bool:
	# El saqueo es unidireccional: del cadáver al jugador.
	# Solo permitimos "colocar" si el ítem ya pertenece a este contenedor (ej: carga inicial o reordenamiento si se permitiera)
	if item.inventory_owner != self:
		return false
		
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
	return "loot_" + echo_id

func _on_close_pressed():
	if NetworkManager and NetworkManager.echo_item_collected.is_connected(_on_echo_item_collected):
		NetworkManager.echo_item_collected.disconnect(_on_echo_item_collected)
	if has_node("/root/UIOrchestrator"):
		get_node("/root/UIOrchestrator").close_window("loot_" + echo_id, true)
	else:
		queue_free()

func _on_echo_item_collected(p_echo_id: String, p_item_id: String, p_is_empty: bool = false):
	if p_echo_id != echo_id: return
	print("[LootContainer] Item %s collected remotely from echo %s (is_empty=%s), updating UI..." % [p_item_id, p_echo_id, str(p_is_empty)])
	
	var found_item: InventoryItem = null
	for slot in slot_data.values():
		if slot and slot.is_occupied and is_instance_valid(slot.occupied_by):
			if slot.occupied_by.item_id == p_item_id:
				found_item = slot.occupied_by
				break
				
	if found_item:
		clear_occupancy(found_item)
		found_item.queue_free()

	if p_is_empty:
		var world = get_tree().current_scene
		if world and world.has_method("despawn_death_echo_by_id"):
			world.despawn_death_echo_by_id(echo_id)
		if NetworkManager and NetworkManager.has_method("send_despawn_echo"):
			NetworkManager.send_despawn_echo(echo_id)
		_on_close_pressed()
	else:
		_check_empty_and_close()

func _check_empty_and_close():
	# Small delay to let any active local drag or drop settle
	await get_tree().process_frame
	var has_items = false
	for slot in slot_data.values():
		if slot and slot.is_occupied and is_instance_valid(slot.occupied_by):
			has_items = true
			break
	if not has_items and not slot_data.is_empty():
		print("[LootContainer] Container %s is completely empty. Closing window and despawning echo." % echo_id)
		var world = get_tree().current_scene
		if world and world.has_method("despawn_death_echo_by_id"):
			world.despawn_death_echo_by_id(echo_id)
		if NetworkManager and NetworkManager.has_method("send_despawn_echo"):
			NetworkManager.send_despawn_echo(echo_id)
		_on_close_pressed()
