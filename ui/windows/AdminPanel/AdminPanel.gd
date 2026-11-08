extends Panel

# AdminPanel.gd - Visual catalog for item injection
# Drag items from here to any inventory slot to "admin-gift" them.

var catalog_grid: GridContainer = null
var item_definitions: Array = []
var _is_loading = false

var _is_dragging = false
var _has_been_moved = false
var _drag_offset = Vector2.ZERO

func _ready():
	visible = false
	custom_minimum_size = Vector2(500, 700)
	size = Vector2(500, 700)
	process_mode = Node.PROCESS_MODE_ALWAYS
	focus_mode = Control.FocusMode.FOCUS_ALL
	set_process(true)
	
	catalog_grid = find_child("CatalogGrid", true, false)
	
	# Connect UI Signals
	var title = find_child("Title", true, false)
	if title:
		title.gui_input.connect(_on_title_gui_input)
		
	var clear_btn = find_child("ClearCacheButton", true, false)
	if clear_btn:
		clear_btn.pressed.connect(ShelterManager.clear_item_cache)
		
	var refresh_btn = find_child("RefreshButton", true, false)
	if refresh_btn:
		refresh_btn.pressed.connect(refresh_catalog)
		
	var close_btn = find_child("CloseButton", true, false)
	if close_btn:
		close_btn.pressed.connect(func(): 
			if has_node("/root/UIOrchestrator"):
				get_node("/root/UIOrchestrator").close_window("admin_panel")
			else:
				hide()
		)

func initialize_window(_params = {}):
	# Este método es llamado por el Orquestador al abrirse
	if item_definitions.size() == 0:
		refresh_catalog()

func _on_title_gui_input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
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

func _process(_delta):
	var vp = get_viewport_rect().size
	if vp.y <= 0: return
	
	# 1. ESCALADO (Siempre activo)
	var target_h = 750.0 
	var base_scale = min(1.0, (vp.y * 0.9) / target_h)
	var final_zoom = base_scale * UIOrchestrator.layout_persistence.global_ui_zoom
	
	scale = Vector2(final_zoom, final_zoom)
	pivot_offset = size / 2.0
	
	# 2. POSICIONAMIENTO
	if _has_been_moved:
		# Clamping reactivo ante cambios de resolución/zoom
		var new_pos = global_position
		var scaled_size = size * final_zoom
		new_pos.x = clamp(new_pos.x, 0, max(0, vp.x - scaled_size.x))
		new_pos.y = clamp(new_pos.y, 0, max(0, vp.y - scaled_size.y))
		global_position = new_pos
	else:
		# Anchor to left with padding, Anchor to top
		global_position.x = 20
		global_position.y = 20

func _can_drop_data(_pos, data):
	# Solo permitimos dropear items que YA TIENEN ID (están en un inventario)
	return data is Dictionary and data.has("type") and data["type"] == "inventory_item" and str(data.item_node.item_id) != ""

func _drop_data(_pos, data):
	var item = data.item_node
	print("AdminPanel: Pidiendo eliminación de ítem ", item.item_name, " (", item.item_id, ") al controlador.")
	
	if has_node("/root/InventoryController"):
		get_node("/root/InventoryController").request_item_removal(item)
	else:
		# Fallback mínimo si el controlador no existe (ej: entorno limitado)
		item.queue_free()


func refresh_catalog():
	if _is_loading: return
	_is_loading = true
	var grid = find_child("CatalogGrid", true, false)
	if not grid:
		print("AdminPanel: CatalogGrid node NOT FOUND during refresh!")
		_is_loading = false
		return
		
	for child in grid.get_children():
		child.queue_free()
	
	item_definitions = await ShelterManager.fetch_all_item_definitions()
	print("AdminPanel: Refreshing with ", item_definitions.size(), " items.")
	
	for def in item_definitions:
		var container = VBoxContainer.new()
		container.custom_minimum_size = Vector2(100, 130) # More room
		container.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		grid.add_child(container)
		
		# Wrapper for the item to handle centering
		var item_wrapper = Control.new()
		item_wrapper.custom_minimum_size = Vector2(96, 96) # Larger visual slot
		item_wrapper.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		container.add_child(item_wrapper)

		# Create a visual representation of the item for dragging
		var item = InventoryItem.new()
		item.item_id = "" # Empty ID signals it's a NEW item from catalog
		item.item_name = def.get("name", "Unknown")
		item.grid_width = int(def.get("grid_width", 1))
		item.grid_height = int(def.get("grid_height", 1))
		
		# Metadata for dragging
		item.set_meta("item_definition_id", def.get("id"))
		
		var icon_path = def.get("icon_path", "")
		if icon_path == null: icon_path = ""
		
		if str(icon_path) != "" and FileAccess.file_exists(str(icon_path)):
			item.texture = load(str(icon_path))
		else:
			# Use placeholder if icon is missing
			var p = PlaceholderTexture2D.new()
			p.size = Vector2(64, 64)
			item.texture = p
			
		item.update_size()
		# Scale to fit the 96x96 area
		var target_size = 96.0
		var scale_val = min(target_size / item.size.x, target_size / item.size.y)
		item.scale = Vector2(scale_val, scale_val)
		
		# Center the scaled item within the 96x96 wrapper if it's smaller than the wrapper in one dimension
		item.position = (Vector2(target_size, target_size) - (item.size * scale_val)) / 2
		item.pivot_offset = Vector2.ZERO 
		
		item_wrapper.add_child(item)
		
		# Name Label
		var label = Label.new()
		label.text = item.item_name
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override("font_size", 10)
		container.add_child(label)
		
		# Botón para otorgar directamente al inventario/almacén con 1 clic
		var grant_btn = Button.new()
		grant_btn.text = "🎁 Otorgar"
		grant_btn.custom_minimum_size = Vector2(0, 22)
		grant_btn.add_theme_font_size_override("font_size", 9)
		grant_btn.pressed.connect(func(): _grant_catalog_item(def))
		container.add_child(grant_btn)
		
		# Tooltip
		container.tooltip_text = item.item_name + " (" + str(item.grid_width) + "x" + str(item.grid_height) + ") - Arrastra o pulsa Otorgar"

	_is_loading = false

func _grant_catalog_item(def: Dictionary) -> void:
	var item_def_id = def.get("id", "")
	var item_name = def.get("name", "Objeto")
	if item_def_id == "": return
	
	var user_id = AuthManager.user_id if AuthManager and AuthManager.user_id != "" else "local_user"
	
	var occupied = {}
	for it in ShelterManager.shelter_inventory:
		var sx = it.get("slot_x")
		var sy = it.get("slot_y")
		if sx != null and sy != null:
			var gw = it.get("grid_width", 1)
			var gh = it.get("grid_height", 1)
			for dy in range(gh):
				for dx in range(gw):
					occupied[Vector2i(int(sx) + dx, int(sy) + dy)] = true
					
	var free_slot = Vector2i(-1, -1)
	for y in range(5):
		for x in range(10):
			if not occupied.has(Vector2i(x, y)):
				free_slot = Vector2i(x, y)
				break
		if free_slot != Vector2i(-1, -1):
			break
			
	if free_slot == Vector2i(-1, -1):
		if has_node("/root/UIOrchestrator"):
			var orch = get_node("/root/UIOrchestrator")
			if orch.has_method("show_toast"):
				orch.show_toast("⚠️ ALMACÉN LLENO", "No hay casillas libres para conceder el ítem.", Color(1.0, 0.5, 0.2))
		return
		
	await ShelterManager.admin_add_item(user_id, "", item_def_id, 1, free_slot.x, free_slot.y, false)
	
	if has_node("/root/UIOrchestrator"):
		var orch = get_node("/root/UIOrchestrator")
		if orch.has_method("show_toast"):
			orch.show_toast("🎁 ÍTEM CONCEDIDO", "'%s' otorgado al Almacén del Refugio." % item_name, Color(0.3, 0.95, 0.5))
			
	if has_node("/root/InventoryController"):
		get_node("/root/InventoryController").reload_inventory_data()
	else:
		var inv_uis = get_tree().get_nodes_in_group("inventory_ui")
		for inv in inv_uis:
			if inv.has_method("_request_data_refresh"):
				inv._request_data_refresh()
