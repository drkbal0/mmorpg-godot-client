extends TextureRect
class_name InventoryItem

signal rotate_requested
signal container_open_requested(item_id, item_data)

var item_id: String
var item_name: String
var grid_width: int = 1
var grid_height: int = 1
var is_rotated: bool = false
var slot_x: int = -1
var slot_y: int = -1
var inventory_owner: Control = null
var inventory_type: int = 0
var parent_item_id: String = ""

# Stacking properties & visual badge
var quantity: int = 1:
	set(val):
		quantity = max(0, val)
		_update_stack_badge()

var max_stack: int = 1

var _stack_badge_panel: PanelContainer = null
var _stack_badge_label: Label = null

# Container properties
var is_container: bool = false
var inner_grid_width: int = 0
var inner_grid_height: int = 0

# Store the original texture path to handle rotation texture swaps
var _base_texture_path: String = ""

func _ready():
	mouse_filter = Control.MOUSE_FILTER_STOP
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	z_index = 1 # Relative to parent window
	
	if texture and _base_texture_path == "":
		_base_texture_path = texture.resource_path
	_create_or_update_stack_badge()
	update_size()

func update_size():
	if texture and _base_texture_path == "":
		_base_texture_path = texture.resource_path
		
	var w_slots = grid_width if !is_rotated else grid_height
	var h_slots = grid_height if !is_rotated else grid_width
	
	# Standard 64px slots
	var total_w = w_slots * 64
	var total_h = h_slots * 64
	
	custom_minimum_size = Vector2(total_w, total_h)
	size = custom_minimum_size
	
	# Reset
	rotation_degrees = 0
	pivot_offset = Vector2.ZERO
	
	# Texture orientation handling
	# For items with orientation variants, swap textures based on current orientation
	var has_variants = "1x2" in _base_texture_path or "2x1" in _base_texture_path
	
	if has_variants:
		var need_vertical = h_slots > w_slots
		var need_horizontal = w_slots > h_slots
		var need_square = w_slots == h_slots
		
		if not need_square:
			if need_vertical:
				var vertical_path = _base_texture_path
				if "1x2" in vertical_path:
					vertical_path = vertical_path.replace("1x2", "2x1")
				if FileAccess.file_exists(vertical_path):
					texture = load(vertical_path)
			elif need_horizontal:
				var horizontal_path = _base_texture_path
				if "2x1" in horizontal_path:
					horizontal_path = horizontal_path.replace("2x1", "1x2")
				if FileAccess.file_exists(horizontal_path):
					texture = load(horizontal_path)
	else:
		if is_rotated:
			rotation_degrees = 90
			pivot_offset = Vector2(total_w / 2.0, total_h / 2.0)
	
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_update_stack_badge()

func _create_or_update_stack_badge():
	if _stack_badge_panel == null or not is_instance_valid(_stack_badge_panel):
		_stack_badge_panel = PanelContainer.new()
		_stack_badge_panel.name = "StackBadge"
		_stack_badge_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_stack_badge_panel.z_index = 2
		
		var sb = StyleBoxFlat.new()
		sb.bg_color = Color(0.04, 0.06, 0.10, 0.90)
		sb.border_width_left = 1
		sb.border_width_top = 1
		sb.border_width_right = 1
		sb.border_width_bottom = 1
		sb.border_color = Color(0.85, 0.70, 0.20, 0.85)
		sb.corner_radius_top_left = 3
		sb.corner_radius_top_right = 3
		sb.corner_radius_bottom_right = 3
		sb.corner_radius_bottom_left = 3
		_stack_badge_panel.add_theme_stylebox_override("panel", sb)
		
		var margin = MarginContainer.new()
		margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		margin.add_theme_constant_override("margin_left", 3)
		margin.add_theme_constant_override("margin_right", 3)
		margin.add_theme_constant_override("margin_top", 0)
		margin.add_theme_constant_override("margin_bottom", 0)
		_stack_badge_panel.add_child(margin)
		
		_stack_badge_label = Label.new()
		_stack_badge_label.name = "CountLabel"
		_stack_badge_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_stack_badge_label.add_theme_font_size_override("font_size", 10)
		_stack_badge_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.5))
		_stack_badge_label.add_theme_color_override("font_outline_color", Color.BLACK)
		_stack_badge_label.add_theme_constant_override("outline_size", 3)
		margin.add_child(_stack_badge_label)
		
		add_child(_stack_badge_panel)
	
	_update_stack_badge()

func _update_stack_badge():
	if _stack_badge_panel == null or not is_instance_valid(_stack_badge_panel):
		return
		
	if quantity > 1:
		_stack_badge_panel.visible = true
		_stack_badge_label.text = "x" + str(quantity)
		var w_slots = grid_width if !is_rotated else grid_height
		var h_slots = grid_height if !is_rotated else grid_width
		var total_w = float(w_slots * 64)
		var total_h = float(h_slots * 64)
		
		# Dimensiones del panel de badge calculadas con precisión inmediata
		var min_sz = _stack_badge_panel.get_combined_minimum_size()
		var badge_w = max(min_sz.x, 24.0)
		var badge_h = max(min_sz.y, 18.0)
		if _stack_badge_panel.size.x > badge_w:
			badge_w = _stack_badge_panel.size.x
		if _stack_badge_panel.size.y > badge_h:
			badge_h = _stack_badge_panel.size.y
		_stack_badge_panel.size = Vector2(badge_w, badge_h)
			
		var target_visual_pos = Vector2(total_w - badge_w, total_h - badge_h)
		
		# Si el item tiene rotación activa (90°), compensamos la orientación y coordenadas
		# para que el badge "xN" SIEMPRE permanezca erguido (horizontal) y anclado abajo-derecha
		if rotation_degrees == 90.0:
			var center = Vector2(total_w / 2.0, total_h / 2.0)
			var d = target_visual_pos - center
			# Transformación inversa a la rotación del padre: R(-90°) * (dx, dy) = (dy, -dx)
			_stack_badge_panel.position = Vector2(center.x + d.y, center.y - d.x)
			_stack_badge_panel.rotation_degrees = -90.0
		else:
			_stack_badge_panel.position = target_visual_pos
			_stack_badge_panel.rotation_degrees = 0.0
	else:
		_stack_badge_panel.visible = false

func rotate_item():
	rotate_requested.emit()


func _gui_input(event):
	handle_direct_input(event)

func handle_direct_input(event):
	if event is InputEventMouseButton and event.pressed:
		if inventory_owner and inventory_owner.has_method("request_focus"):
			inventory_owner.request_focus()
		
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_show_context_menu()
		elif event.button_index == MOUSE_BUTTON_LEFT and event.double_click:
			_on_double_click()

func flash_error():
	var tween = create_tween()
	tween.tween_property(self, "modulate", Color(1, 0, 0, 1), 0.1)
	tween.tween_property(self, "modulate", Color(1, 1, 1, 1), 0.2)

func _show_context_menu():
	var menu = get_node_or_null("ContextMenu")
	if menu: 
		menu.queue_free()
		
	menu = PopupMenu.new()
	menu.name = "ContextMenu"
	add_child(menu)
	
	menu.add_item("Girar", 0)
	if is_container:
		menu.add_item("Abrir", 1)
		
	if quantity > 1:
		menu.add_item("✂️ Dividir Pila / Desagrupar", 4)
		
	var is_sheet = item_name.contains("Hoja de Descubrimiento") or item_name.contains("Hoja Oculta") or item_name.contains("Pergamino")
	if is_sheet:
		var sm = get_node_or_null("/root/ShelterManager")
		var cached = sm.all_items_cache.get(item_id, {}) if (sm and "all_items_cache" in sm) else {}
		var sec_id = cached.get("secret_id", "")
		if sec_id == "":
			if "Amuleto" in item_name: sec_id = "item_amuleto_vacio"
			elif "Singularidad" in item_name or "Portal" in item_name: sec_id = "mecanica_singularidad_portal"
			elif "Daga" in item_name: sec_id = "item_daga_larga"
			else: sec_id = "item_amuleto_vacio"
			
		var already_acquired = _is_secret_already_acquired(sec_id)
		if already_acquired:
			menu.add_item("📜 Descifrar Secreto (Ya aprendido)", 3)
		else:
			menu.add_item("📜 Descifrar Secreto (No adquirido)", 3)
		
	menu.add_item("Examinar", 2)
	
	menu.id_pressed.connect(_on_menu_id_pressed)
	menu.position = Vector2i(get_global_mouse_position())
	menu.popup()

func _is_secret_already_acquired(sec_id: String) -> bool:
	var codex_inst = null
	if has_node("/root/UIOrchestrator"):
		var orch = get_node("/root/UIOrchestrator")
		if orch.has_method("get_window_instance"):
			codex_inst = orch.get_window_instance("codex_window")
		elif orch.registry:
			codex_inst = orch.registry.get_instance("codex_window")
	if not codex_inst:
		codex_inst = get_tree().get_first_node_in_group("codex_window")
		
	if codex_inst and codex_inst.has_method("is_secret_acquired"):
		return codex_inst.is_secret_acquired(sec_id)
	return false

func _on_menu_id_pressed(id):
	match id:
		0: rotate_item()
		1: _on_double_click()
		2: print("Item: ", item_name, " ID: ", item_id)
		3: _consume_sheet()
		4: split_stack()

func split_stack() -> void:
	if quantity <= 1:
		return
	
	var split_amount = int(quantity / 2) # Ej: 5 -> 2, 2 -> 1, 3 -> 1
	var keep_amount = quantity - split_amount # Ej: 5 -> 3, 2 -> 1, 3 -> 2
	
	var current_owner = inventory_owner
	var current_type = inventory_type
	var free_slot = Vector2i(-1, -1)
	
	# 1. Intentar buscar casilla libre en el contenedor local
	if current_owner:
		var max_x = 10
		var max_y = 5
		if current_owner.has_method("_get_grid_size"):
			var sz = current_owner._get_grid_size(current_type)
			max_x = int(sz.x)
			max_y = int(sz.y)
		elif "grid_width" in current_owner and "grid_height" in current_owner:
			max_x = int(current_owner.grid_width)
			max_y = int(current_owner.grid_height)
			
		for y in range(max_y):
			for x in range(max_x):
				var fits = true
				if "slot_data" in current_owner:
					for dy in range(grid_height):
						for dx in range(grid_width):
							var s = current_owner.slot_data.get(Vector2i(x + dx, y + dy))
							if s == null or s.is_occupied:
								fits = false
								break
						if not fits:
							break
				else:
					if (x == slot_x and y == slot_y) or not current_owner.can_place_item(self, x, y, current_type):
						fits = false
				if fits:
					free_slot = Vector2i(x, y)
					break
			if free_slot != Vector2i(-1, -1):
				break
	
	# 2. Si no cupo en el contenedor actual, intentar en el Almacén (Shelter Stash)
	if free_slot == Vector2i(-1, -1):
		var sm = get_node_or_null("/root/ShelterManager")
		if sm:
			var occupied = {}
			for it in sm.shelter_inventory:
				var sx = it.get("slot_x")
				var sy = it.get("slot_y")
				if sx != null and sy != null:
					var gw = it.get("grid_width", 1)
					var gh = it.get("grid_height", 1)
					for dy in range(gh):
						for dx in range(gw):
							occupied[Vector2i(int(sx) + dx, int(sy) + dy)] = true
			for y in range(5):
				for x in range(10):
					if not occupied.has(Vector2i(x, y)):
						free_slot = Vector2i(x, y)
						current_type = 1 # ShelterManager.InventoryType.SHELTER
						break
				if free_slot != Vector2i(-1, -1):
					break
	
	if free_slot == Vector2i(-1, -1):
		flash_error()
		if has_node("/root/UIOrchestrator"):
			var orch = get_node("/root/UIOrchestrator")
			if orch.has_method("show_toast"):
				orch.show_toast("⚠️ ALMACÉN LLENO", "No hay casillas libres para dividir la pila.", Color(1.0, 0.5, 0.2))
		return
	
	# Modificar cantidad de la pila original
	quantity = keep_amount
	_update_stack_badge()
	
	var sm = get_node_or_null("/root/ShelterManager")
	if sm:
		if sm.all_items_cache.has(item_id):
			sm.all_items_cache[item_id]["quantity"] = keep_amount
		for it in sm.shelter_inventory:
			if str(it.get("id")) == item_id:
				it["quantity"] = keep_amount
				break
		for it in sm.character_inventory:
			if str(it.get("id")) == item_id:
				it["quantity"] = keep_amount
				break
	
	# Crear nueva entidad para la porción separada
	var def_id = get_meta("item_definition_id", "")
	var new_item_id = "split_" + str(Time.get_ticks_msec()) + "_" + str(randi() % 1000)
	var auth = get_node_or_null("/root/AuthManager")
	var user_id = auth.user_id if auth and auth.user_id != "" else "local_user"
	var char_id = (auth.selected_character_id if auth else "") if current_type != 1 else ""
	
	var new_item_dict = {
		"id": new_item_id,
		"user_id": user_id,
		"character_id": char_id,
		"item_definition_id": def_id,
		"display_name": item_name,
		"icon_path": _base_texture_path,
		"rarity": "common",
		"item_type": "material",
		"grid_width": grid_width,
		"grid_height": grid_height,
		"slot_x": free_slot.x,
		"slot_y": free_slot.y,
		"is_rotated": false,
		"is_secure": (current_type == 2),
		"quantity": split_amount
	}
	
	if sm:
		sm.all_items_cache[new_item_id] = new_item_dict
		if current_type == 1:
			sm.shelter_inventory.append(new_item_dict)
		else:
			sm.character_inventory.append(new_item_dict)
		if def_id != "":
			sm.admin_add_item(user_id, char_id, def_id, split_amount, free_slot.x, free_slot.y, current_type == 2)
	
	if has_node("/root/UIOrchestrator"):
		var orch = get_node("/root/UIOrchestrator")
		if orch.has_method("show_toast"):
			orch.show_toast(
				"✂️ PILA DIVIDIDA",
				"%s dividida en pilas de x%d y x%d." % [item_name, keep_amount, split_amount],
				Color(0.4, 0.9, 1.0)
			)
			
	if has_node("/root/InventoryController"):
		get_node("/root/InventoryController").reload_inventory_data()
	else:
		var inv_uis = get_tree().get_nodes_in_group("inventory_ui")
		for inv in inv_uis:
			if inv.has_method("_request_data_refresh"):
				inv._request_data_refresh()
				
	if current_owner and is_instance_valid(current_owner):
		if item_id != "" and current_owner.has_method("reload_inventory"):
			current_owner.reload_inventory()
		elif current_owner.has_method("_request_data_refresh"):
			current_owner._request_data_refresh()

func _on_double_click():
	if is_container:
		print("InventoryItem: Emitiendo peticion de mochila: ", item_name)
		container_open_requested.emit(item_id, {
			"item_id": item_id,
			"name": item_name,
			"grid_width": inner_grid_width,
			"grid_height": inner_grid_height
		})
	elif item_name.contains("Hoja de Descubrimiento") or item_name.contains("Hoja Oculta"):
		_consume_sheet()

func _consume_sheet():
	print("[InventoryItem] Consumiendo Hoja de Descubrimiento: ", item_name)
	
	var sm = get_node_or_null("/root/ShelterManager")
	var cached = sm.all_items_cache.get(item_id, {}) if (sm and "all_items_cache" in sm) else {}
	var secret_id = cached.get("secret_id", "")
	if secret_id == "":
		if "Amuleto" in item_name:
			secret_id = "item_amuleto_vacio"
		elif "Singularidad" in item_name or "Portal" in item_name:
			secret_id = "mecanica_singularidad_portal"
		elif "Daga" in item_name:
			secret_id = "item_daga_larga"
		else:
			secret_id = "item_amuleto_vacio"
			
	var raw_secret_name = cached.get("secret_name", item_name)
	var secret_name = raw_secret_name.replace("Hoja de Descubrimiento: ", "").replace("Hoja de Descubrimiento", "Amuleto Vacío Ancestral")
	if secret_name.strip_edges() == "":
		secret_name = "Amuleto Vacío Ancestral"
	
	# Desbloquear en CodexDiaryWindow
	var codex_inst = null
	if has_node("/root/UIOrchestrator"):
		var orch = get_node("/root/UIOrchestrator")
		if orch.has_method("get_window_instance"):
			codex_inst = orch.get_window_instance("codex_window")
		elif orch.registry:
			codex_inst = orch.registry.get_instance("codex_window")
		
		# Si el códice no estaba abierto o instanciado, abrirlo para mostrar el progreso
		if not codex_inst or not codex_inst.visible:
			codex_inst = orch.open_window("codex_window")
			
	if not codex_inst:
		codex_inst = get_tree().get_first_node_in_group("codex_window")
		
	if codex_inst and codex_inst.has_method("unlock_secret_from_sheet"):
		codex_inst.unlock_secret_from_sheet(secret_id, secret_name)
		
	# Feedback sonoro / banner en ShelterLobby y Toast ineludible en pantalla
	if has_node("/root/UIOrchestrator"):
		var orch = get_node("/root/UIOrchestrator")
		if orch.has_method("show_toast"):
			orch.show_toast(
				"📜 SECRETO ANCESTRAL DESCIFRADO",
				"Has adquirido el conocimiento de '%s'. +5%% Buff Pasivo Activo en tu Códice." % secret_name,
				Color(1.0, 0.82, 0.2)
			)
		var lobby = orch.get_window_instance("shelter_lobby") if orch.has_method("get_window_instance") else null
		if lobby and lobby.has_method("_notify"):
			lobby._notify("✨ ¡Secreto Ancestral Descifrado! '%s' registrado en tu Códice (+5%% Buff Pasivo Activo)." % secret_name)
		
	# Consumir del inventario / almacén
	if sm and sm.has_method("remove_item"):
		sm.remove_item(item_id, inventory_type)
	
	# Efecto visual de desvanecimiento dorado
	var tween = create_tween()
	tween.tween_property(self, "modulate", Color(1.5, 1.3, 0.3, 0.0), 0.25)
	await tween.finished
	
	# Forzar refresco en todas las interfaces de inventario abiertas
	var inv_uis = get_tree().get_nodes_in_group("inventory_ui")
	for inv in inv_uis:
		if inv.has_method("_request_data_refresh"):
			inv._request_data_refresh()
			
	queue_free()

func _get_drag_data(pos):
	if inventory_owner and inventory_owner.has_method("request_focus"):
		inventory_owner.request_focus()
		
	var w = grid_width if !is_rotated else grid_height
	var h = grid_height if !is_rotated else grid_width

	# --- UX IMPROVEMENTS (Scale & Offset Centrado V5) ---
	var preview_proxy = Control.new()
	
	# Capturamos la escala GLOBAL (que incluye el zoom del orquestador)
	var global_s = get_global_transform().get_scale()
	if global_s.x <= 0.01: global_s = Vector2.ONE
	
	var actual_preview = TextureRect.new()
	actual_preview.name = "DragVisual_" + item_name
	actual_preview.texture = texture
	actual_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	actual_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	actual_preview.size = Vector2(w * 64, h * 64)
	actual_preview.scale = global_s # Escala visual idéntica
	actual_preview.modulate.a = 0.75
	actual_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	actual_preview.pivot_offset = actual_preview.size * 0.5
	if is_rotated:
		actual_preview.rotation_degrees = 90
	
	# Offset perfectamente centrado para que el cursor agarre el ítem por el centro de la celda
	var center_offset = Vector2(float(w * 64) * global_s.x * 0.5, float(h * 64) * global_s.y * 0.5)
	
	preview_proxy.set_meta("visual", actual_preview)
	preview_proxy.set_meta("click_offset", center_offset)
	preview_proxy.set_script(load("res://ui/orchestration/DragProxy.gd"))
	
	set_drag_preview(preview_proxy)
	
	var drag_node = self
	if item_id == "" or item_id == null:
		drag_node = self.duplicate()
		drag_node.inventory_owner = null
	
	return {
		"type": "inventory_item",
		"item_node": drag_node,
		"original_slot": Vector2(slot_x, slot_y),
		"inventory_type": inventory_type
	}
