extends Node

# InventoryController.gd
# Centraliza la lógica de negocio de inventario y la comunicación con el backend.
# Debe ser registrado como Autoload: "InventoryController".

signal item_move_completed(item_id, success)
signal item_rotation_completed(item_id, success)
signal item_removed_completed(item_id, success)
signal inventory_refresh_requested(state) # For atomic UI updates

func _ready():
	print("[InventoryController] Inicializado.")

## Solicitar movimiento de un ítem
func request_item_movement(item: InventoryItem, target_x: int, target_y: int, target_type: ShelterManager.InventoryType, target_container: Control) -> bool:
	if item == null: return false
	
	# Capturar estado previo para reversión
	var old_x = item.slot_x
	var old_y = item.slot_y
	var old_owner = item.inventory_owner
	var old_type = item.inventory_type
	var old_rotated = item.is_rotated
	var old_parent_item_id = item.parent_item_id
	
	# --- Validación anti-circularidad ---
	if target_container.has_method("get_container_item_id"):
		var dest_container_id = target_container.get_container_item_id()
		if item.is_container and _is_descendant_of(dest_container_id, item.item_id):
			print("[InventoryController] BLOQUEADO: Referencia circular detectada.")
			item.flash_error()
			return false
	
	# 1. Validación espacial
	if not target_container.can_place_item(item, target_x, target_y, target_type):
		item.flash_error()
		return false
		
	# 1.5 Validación de Solo-Lectura (Recuperación de muerte)
	if "is_read_only" in target_container and target_container.is_read_only:
		print("[InventoryController] BLOQUEADO: El contenedor de destino es de solo lectura.")
		item.flash_error()
		return false
	
	# 2. Ejecutar movimiento visual inmediato (optimistic update)
	target_container.place_item(item, target_x, target_y, target_type, false)
	
	# 3. Determinar parent_item_id para esta operación
	var new_parent_id = ""
	if target_container.has_method("get_container_item_id"):
		new_parent_id = target_container.get_container_item_id()
	item.parent_item_id = new_parent_id
	
	# 4. Persistence in Backend
	if item.item_id != "":
		# --- CASO ESPECIAL: SAQUEO DE CADÁVER (Death Echo) ---
		var source_id = old_owner.get_container_item_id() if old_owner.has_method("get_container_item_id") else ""
		if source_id.begins_with("loot_"):
			var echo_id = ""
			if "echo_id" in old_owner:
				echo_id = old_owner.echo_id
			else:
				# Fallback por si el ID es directo "loot_ECHOID"
				echo_id = source_id.replace("loot_", "")
				if "_" in echo_id:
					echo_id = echo_id.split("_")[0]
			
			var target_char_id = AuthManager.selected_character_id
			
			var is_secure = (target_type == ShelterManager.InventoryType.SECURE)
			
			print("[InventoryController] COLLECTING item from echo: ", echo_id, " to (%d,%d) secure=%s parent=%s" % [target_x, target_y, str(is_secure), new_parent_id])
			var res = await APIClient.collect_echo_item(echo_id, item.item_id, target_char_id, target_x, target_y, is_secure, new_parent_id)
			
			var res_data = res.get("data", {})
			if res_data.get("success", false):
				print("[InventoryController] Collection SUCCESS.")
				_reload_main_inventory()
				item_move_completed.emit(item.item_id, true)
				return true
			else:
				var err = res_data.get("error_message")
				if err == null: err = res_data.get("errorMessage", "Unknown")
				print("[InventoryController] Collection FAILED: ", err)
				item.flash_error()
				# Revert visual
				if is_instance_valid(old_owner):
					old_owner.place_item(item, old_x, old_y, old_type, false)
				item_move_completed.emit(item.item_id, false)
				return false
		
		# --- CASO NORMAL: Movimiento entre Inventario/Shelter/Mochilas ---
		var is_secure = (target_type == ShelterManager.InventoryType.SECURE)
		var char_id = AuthManager.selected_character_id
		
		# Si el contenedor destino tiene un personaje específico (ej: gestión de roster), usar ese
		if "target_char_id" in target_container and target_container.target_char_id != "":
			char_id = target_container.target_char_id
		
		# Si el item va directo al Shelter, se desvincula por completo del personaje
		if target_type == ShelterManager.InventoryType.SHELTER:
			char_id = ""
			is_secure = false # No puede ser seguro si está en el almacén de cuenta
		
		print("[InventoryController] Moviendo item='%s' a (%d,%d) parent='%s' char='%s' secure=%s" % [item.item_id, target_x, target_y, new_parent_id, char_id, str(is_secure)])
		
		var success = await ShelterManager.move_item(item.item_id, target_x, target_y, item.is_rotated, is_secure, char_id, new_parent_id)
		
		if not success:
			print("[InventoryController] FALLO en backend. Revirtiendo item='%s'" % item.item_id)
			item.flash_error()
			item.parent_item_id = old_parent_item_id
			if is_instance_valid(old_owner):
				item.is_rotated = old_rotated
				old_owner.place_item(item, old_x, old_y, old_type, false)
			else:
				_reload_main_inventory()
			item_move_completed.emit(item.item_id, false)
			return false
		
		print("[InventoryController] ÉXITO movimiento item='%s'. Cache parent_item_id='%s'" % [item.item_id, str(ShelterManager.all_items_cache.get(item.item_id, {}).get("parent_item_id", "N/A"))])
		item_move_completed.emit(item.item_id, true)
		return true
	else:
		# Ítem NUEVO desde el Catálogo Admin (item_id vacío)
		var def_id = item.get_meta("item_definition_id", "")
		if def_id != "":
			var is_secure = (target_type == ShelterManager.InventoryType.SECURE)
			var char_id = AuthManager.selected_character_id
			if target_type == ShelterManager.InventoryType.SHELTER:
				char_id = ""
			
			var success = await ShelterManager.admin_add_item(AuthManager.user_id, char_id, def_id, 1, target_x, target_y, is_secure)
			if success:
				_reload_main_inventory()
				item_move_completed.emit("", true)
				return true
			else:
				target_container.clear_occupancy(item)
				item.queue_free()
				item_move_completed.emit("", false)
				return false
	
	return false

## Solicitar fusión/apilamiento de ítems del mismo tipo hasta max_stack
func request_stack_merge(src_item: InventoryItem, target_item: InventoryItem, _target_container: Control = null) -> bool:
	if not is_instance_valid(src_item) or not is_instance_valid(target_item):
		return false
	
	var max_st = target_item.max_stack
	if max_st <= 1:
		max_st = ShelterManager.get_item_max_stack(target_item.item_name)
		target_item.max_stack = max_st
		
	var space = max_st - target_item.quantity
	if space <= 0:
		src_item.flash_error()
		return false
		
	var to_transfer = min(src_item.quantity, space)
	target_item.quantity += to_transfer
	src_item.quantity -= to_transfer
	
	# Sincronizar en cache de ShelterManager
	if ShelterManager.all_items_cache.has(target_item.item_id):
		ShelterManager.all_items_cache[target_item.item_id]["quantity"] = target_item.quantity
	for it in ShelterManager.shelter_inventory:
		if str(it.get("id")) == target_item.item_id:
			it["quantity"] = target_item.quantity
			break
	for it in ShelterManager.character_inventory:
		if str(it.get("id")) == target_item.item_id:
			it["quantity"] = target_item.quantity
			break

	# Notificación visual
	if has_node("/root/UIOrchestrator"):
		var orch = get_node("/root/UIOrchestrator")
		if orch.has_method("show_toast"):
			orch.show_toast(
				"📦 RECURSOS APILADOS",
				"Se apilaron +%d %s (Total en casilla: x%d / %d)." % [to_transfer, target_item.item_name, target_item.quantity, max_st],
				Color(0.3, 0.95, 0.5)
			)

	if src_item.quantity <= 0:
		var src_owner = src_item.inventory_owner
		if is_instance_valid(src_owner) and src_owner.has_method("clear_occupancy"):
			src_owner.clear_occupancy(src_item)
		if src_item.item_id != "":
			ShelterManager.remove_item(src_item.item_id, src_item.inventory_type)
		src_item.queue_free()
	else:
		if ShelterManager.all_items_cache.has(src_item.item_id):
			ShelterManager.all_items_cache[src_item.item_id]["quantity"] = src_item.quantity
		for it in ShelterManager.shelter_inventory:
			if str(it.get("id")) == src_item.item_id:
				it["quantity"] = src_item.quantity
				break
		for it in ShelterManager.character_inventory:
			if str(it.get("id")) == src_item.item_id:
				it["quantity"] = src_item.quantity
				break
				
	_reload_main_inventory()
	return true

## Verificar si container_id es descendiente de potential_ancestor_id
func _is_descendant_of(container_id: String, potential_ancestor_id: String) -> bool:
	if container_id == "" or potential_ancestor_id == "":
		return false
	if container_id == potential_ancestor_id:
		return true
	
	var visited = {}
	var current_id = container_id
	while current_id != "":
		if visited.has(current_id):
			break
		visited[current_id] = true
		var item_data = ShelterManager.all_items_cache.get(current_id)
		if item_data == null:
			break
		var parent = str(item_data.get("parent_item_id", ""))
		if parent == potential_ancestor_id:
			return true
		current_id = parent
	
	return false

## Solicitar rotación de un ítem
func request_item_rotation(item: InventoryItem) -> bool:
	if not item.inventory_owner: return false
	
	var owner = item.inventory_owner
	owner.clear_occupancy(item)
	
	item.is_rotated = !item.is_rotated
	
	if owner.can_place_item(item, item.slot_x, item.slot_y, item.inventory_type):
		item.update_size()
		var success = await request_item_movement(item, item.slot_x, item.slot_y, item.inventory_type, owner)
		item_rotation_completed.emit(item.item_id, success)
		return success
	else:
		item.is_rotated = !item.is_rotated
		owner.place_item(item, item.slot_x, item.slot_y, item.inventory_type, false)
		item.update_size()
		item_rotation_completed.emit(item.item_id, false)
		return false

## Solicitar eliminación de un ítem (Admin)
func request_item_removal(item: InventoryItem):
	if item == null: return
	
	var item_id = item.item_id
	var type = item.inventory_type
	var owner = item.inventory_owner
	
	if item_id == "": 
		item.queue_free()
		return
	
	if owner:
		owner.clear_occupancy(item)
	item.hide()
	
	var success = await ShelterManager.remove_item(item_id, type)
	
	if success:
		item.queue_free()
		_reload_main_inventory()
	else:
		item.show()
		if owner:
			owner.place_item(item, item.slot_x, item.slot_y, type, false)
		item.flash_error()
	
	item_removed_completed.emit(item_id, success)

## Solicitar recarga del inventario principal (Shelter/Stash)
func reload_inventory_data():
	var char_id = AuthManager.selected_character_id
	var state = await fetch_inventory_state(char_id)
	inventory_refresh_requested.emit(state)

## Descargar el estado completo de inventarios (Stash + Personaje)
## CENTRALIZADO AQUÍ PARA EVITAR RACE CONDITIONS EN LAS VISTAS
func fetch_inventory_state(char_id: String) -> Dictionary:
	var state = {
		"stash_items": [],
		"char_items": []
	}
	
	if AuthManager.auth_token == "":
		state.stash_items = ShelterManager.shelter_inventory.duplicate()
		state.char_items = ShelterManager.character_inventory.duplicate()
		return state
		
	# 1. Almacén de Cuenta (Siempre se pide)
	var stash = await ShelterManager.fetch_inventory("")
	if stash.is_empty() and not ShelterManager.shelter_inventory.is_empty():
		state.stash_items = ShelterManager.shelter_inventory.duplicate()
	else:
		# Preservar items locales generados recientemente que aún no se reflejan en DB
		var backend_ids = {}
		for item in stash:
			backend_ids[str(item.get("id"))] = true
		for local_item in ShelterManager.shelter_inventory:
			var lid = str(local_item.get("id"))
			if not backend_ids.has(lid):
				stash.append(local_item)
		state.stash_items = stash
		ShelterManager.shelter_inventory = stash
	
	# 2. Almacén de Personaje (Solo si hay selección)
	if char_id != "":
		var chars = await ShelterManager.fetch_inventory(char_id)
		if chars.is_empty() and not ShelterManager.character_inventory.is_empty():
			state.char_items = ShelterManager.character_inventory.duplicate()
		else:
			var char_backend_ids = {}
			for item in chars:
				char_backend_ids[str(item.get("id"))] = true
			for local_char_item in ShelterManager.character_inventory:
				var lcid = str(local_char_item.get("id"))
				if not char_backend_ids.has(lcid):
					chars.append(local_char_item)
			state.char_items = chars
			ShelterManager.character_inventory = chars
		
	return state

func _reload_main_inventory():
	reload_inventory_data()

## Client-Compute: Auto-Organizar Grilla (2D Bin Packing Greedy Best-Fit)
func auto_sort_items(items: Array, grid_w: int, grid_h: int) -> Array:
	var sorted_items = items.duplicate()
	sorted_items.sort_custom(func(a, b):
		var area_a = (a.grid_width if "grid_width" in a else 1) * (a.grid_height if "grid_height" in a else 1)
		var area_b = (b.grid_width if "grid_width" in b else 1) * (b.grid_height if "grid_height" in b else 1)
		return area_a > area_b
	)
	
	var occupied: Array = []
	for y in range(grid_h):
		var row: Array = []
		for x in range(grid_w):
			row.append(false)
		occupied.append(row)
		
	var placements: Array = []
	
	for it in sorted_items:
		var placed = false
		var w = it.grid_width if "grid_width" in it else 1
		var h = it.grid_height if "grid_height" in it else 1
		var i_id = it.item_id if "item_id" in it else (it.id if "id" in it else "")
		
		for rot in [false, true]:
			var test_w = h if rot else w
			var test_h = w if rot else h
			if test_w > grid_w or test_h > grid_h:
				continue
				
			for y in range(grid_h - test_h + 1):
				for x in range(grid_w - test_w + 1):
					var can_fit = true
					for dy in range(test_h):
						for dx in range(test_w):
							if occupied[y + dy][x + dx]:
								can_fit = false
								break
						if not can_fit: break
						
					if can_fit:
						for dy in range(test_h):
							for dx in range(test_w):
								occupied[y + dy][x + dx] = true
						placements.append({
							"item_id": i_id,
							"slot_x": x,
							"slot_y": y,
							"is_rotated": rot
						})
						placed = true
						break
				if placed: break
			if placed: break
			
	return placements
