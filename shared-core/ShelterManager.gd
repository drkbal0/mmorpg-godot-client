extends Node

## ShelterManager.gd - Business logic for Shelter & Inventory
## Centralizes state management and API calls, decoupled from UI.

enum InventoryType { CHARACTER, SHELTER, SECURE }


signal shelter_updated(data: Dictionary)
signal inventory_updated(data: Array)
signal definitions_updated(data: Array)
signal building_created(building: Dictionary)
signal collection_success(building_id: String, result: Dictionary)
signal operation_failed(message: String)
signal world_transition_started

var shelter_data: Dictionary = {}
var shelter_inventory: Array = []
var character_inventory: Array = []
var all_items_cache: Dictionary = {} # Unified cache: item_id -> item_data
var building_definitions: Array = []
var admin_panel_instance: Control = null

func _ready():
	print("ShelterManager: Initialized.")


## Fetch full shelter state
func fetch_shelter() -> void:
	var res = await APIClient.get_request("/shelter")
	if res.get("code", 500) < 400:
		var data = res.get("data")
		if data is Dictionary:
			shelter_data = data
		else:
			shelter_data = {}
		shelter_updated.emit(shelter_data)
	else:
		operation_failed.emit(res.get("error", "Failed to fetch shelter"))

## Fetch building definitions (with local cache)
func fetch_definitions() -> Array:
	if building_definitions.size() > 0:
		return building_definitions
		
	var res = await APIClient.get_request("/shelter/definitions")
	if res.get("code", 500) < 400:
		var data = res.get("data")
		if data is Array:
			building_definitions = data
		else:
			building_definitions = []
		definitions_updated.emit(building_definitions)
		return building_definitions
	else:
		operation_failed.emit(res.get("error", "Failed to fetch definitions"))
		return []

## Fetch user inventory and enrich with metadata
## char_id: If null, fetches Shelter Stash. If provided, fetches character inventory.
func fetch_inventory(char_id: String = "") -> Array:
	var headers = {}
	if char_id != "":
		headers["X-Character-ID"] = char_id
		
	var res = await APIClient.get_request("/shelter/inventory", false, "", headers)
	if res.get("code", 500) < 400:
		var data = res.get("data")
		var target_array = []
		if data is Array:
			target_array = data
			
			# Enrich with metadata from ItemManager
			var item_ids = []
			for item in target_array:
				item_ids.append(item["item_definition_id"])
			
			if item_ids.size() > 0:
				var defs = await ItemManager.get_definitions_async(item_ids)
				var def_map = {}
				for d in defs:
					def_map[d["id"]] = d
				
				for item in target_array:
					var d = def_map.get(item["item_definition_id"])
					if d:
						item["display_name"] = d.get("name", "Unknown")
						item["icon_path"] = d.get("icon_path", "")
						item["rarity"] = d.get("rarity", "common")
						item["model_path"] = d.get("model_path", "")
						item["grid_width"] = d.get("grid_width", 1)
						item["grid_height"] = d.get("grid_height", 1)
						print("ShelterManager: Enriched item '%s' (%s) with size %dx%d" % [item.get("id"), item.get("display_name"), item["grid_width"], item["grid_height"]])
						item["inner_grid_width"] = d.get("inner_grid_width", 0)
						item["inner_grid_height"] = d.get("inner_grid_height", 0)
						
				# Update unified cache
				for it in target_array:
					var item_id = str(it.get("id"))
					all_items_cache[item_id] = it
			
			# Update isolated storage references
			if char_id == "":
				shelter_inventory = target_array
			else:
				character_inventory = target_array
				
		inventory_updated.emit(target_array)
		return target_array
	else:
		operation_failed.emit(res.get("error", "Failed to fetch inventory"))
		return []

var stack_limits: Dictionary = {
	"madera": 50,
	"wood": 50,
	"hierro": 30,
	"iron": 30,
	"piedra": 50,
	"stone": 50,
	"pocion": 10,
	"potion": 10
}

## Helper: Límite máximo de apilamiento por tipo/nombre de ítem
func get_item_max_stack(name: String) -> int:
	var l = name.to_lower()
	for k in stack_limits.keys():
		if k in l:
			return stack_limits[k]
	# Equipo, armas, contenedores, mochilas y hojas de descubrimiento solo 1 por casilla
	return 1

## Fetch all item definitions (for Admin Panel catalog)
func fetch_all_item_definitions() -> Array:
	print("ShelterManager: Fetching item definitions...")
	var res = await APIClient.get_request("/shelter/items/definitions")
	print("ShelterManager: API Response code=", res.get("code"), " data_type=", typeof(res.get("data")))
	var defs: Array = []
	if res.get("code", 500) == 200 and res.get("data") is Array and res.get("data").size() > 0:
		defs = res.get("data")
		print("ShelterManager: Fetched ", defs.size(), " definitions.")
	else:
		print("ShelterManager: Using robust fallback definition catalog (Offline / Sandbox).")
		defs = _get_default_item_definitions()
		
	# Asegurar que Amuleto Vacío Ancestral y Hoja de Descubrimiento estén siempre presentes
	var has_amulet = false
	for d in defs:
		if d.get("name") == "Amuleto Vacío Ancestral":
			has_amulet = true
			break
	if not has_amulet:
		defs.append({
			"id": "00000000-0000-0000-0000-000000000088",
			"name": "Amuleto Vacío Ancestral",
			"description": "Un talismán milenario tallado en obsidiana con engastes arcanos inertes. Dicen las leyendas de los Primeros Exploradores que este receptáculo palpita tenuemente ante la presencia de singularidades cósmicas y grietas de dungeon.",
			"rarity": "legendary",
			"item_type": "equipment",
			"grid_width": 1,
			"grid_height": 1,
			"icon_path": "res://assets/icons/items/amulet1x1.png",
			"is_container": false,
			"inner_grid_width": 0,
			"inner_grid_height": 0
		})
	return defs

func _get_default_item_definitions() -> Array:
	return [
		{
			"id": "00000000-0000-0000-0000-000000000088",
			"name": "Amuleto Vacío Ancestral",
			"description": "Un talismán milenario tallado en obsidiana con engastes arcanos inertes. Dicen las leyendas de los Primeros Exploradores que este receptáculo palpita tenuemente ante la presencia de singularidades cósmicas y grietas de dungeon.",
			"rarity": "legendary",
			"item_type": "equipment",
			"grid_width": 1,
			"grid_height": 1,
			"icon_path": "res://assets/icons/items/amulet1x1.png",
			"is_container": false,
			"inner_grid_width": 0,
			"inner_grid_height": 0
		},
		{
			"id": "00000000-0000-0000-0000-000000000099",
			"name": "Hoja de Descubrimiento",
			"description": "Pergamino arcano que contiene conocimiento oculto. Clic derecho para descifrar y registrar en tu Códice.",
			"rarity": "rare",
			"item_type": "consumable",
			"grid_width": 1,
			"grid_height": 1,
			"icon_path": "res://assets/icons/items/scroll1x1.png",
			"is_container": false,
			"inner_grid_width": 0,
			"inner_grid_height": 0
		},
		{
			"id": "e4d262bf-ad4d-4bc0-91d4-c6290db2e43c",
			"name": "Madera",
			"description": "Recurso basico para construccion.",
			"rarity": "common",
			"item_type": "material",
			"grid_width": 1,
			"grid_height": 1,
			"icon_path": "res://assets/icons/items/wood1x1.png",
			"is_container": false
		},
		{
			"id": "d6871f24-5b7d-4d73-8b70-eb85ccdad6b7",
			"name": "Hierro",
			"description": "Metal refinado para estructuras.",
			"rarity": "uncommon",
			"item_type": "material",
			"grid_width": 1,
			"grid_height": 1,
			"icon_path": "res://assets/icons/items/iron1x1.png",
			"is_container": false
		},
		{
			"id": "3cae4f06-ae42-41db-a92e-beed4db961b3",
			"name": "Piedra",
			"description": "Mineral solido extraido de canteras.",
			"rarity": "common",
			"item_type": "material",
			"grid_width": 1,
			"grid_height": 1,
			"icon_path": "res://assets/icons/items/stone1x1.png",
			"is_container": false
		},
		{
			"id": "00000000-0000-0000-0000-000000000010",
			"name": "Daga Larga",
			"description": "Una hoja afilada y veloz.",
			"rarity": "uncommon",
			"item_type": "equipment",
			"grid_width": 1,
			"grid_height": 2,
			"icon_path": "res://assets/icons/items/dagger1x2.png",
			"is_container": false
		},
		{
			"id": "00000000-0000-0000-0000-000000000011",
			"name": "Cuchillo",
			"description": "Herramienta basica de supervivencia.",
			"rarity": "common",
			"item_type": "equipment",
			"grid_width": 1,
			"grid_height": 1,
			"icon_path": "res://assets/icons/items/minidager1x1.png",
			"is_container": false
		},
		{
			"id": "00000000-0000-0000-0000-000000000020",
			"name": "Mochila de Cuero",
			"description": "Aumenta tu capacidad de carga.",
			"rarity": "uncommon",
			"item_type": "equipment",
			"grid_width": 2,
			"grid_height": 2,
			"icon_path": "res://assets/icons/items/backpack.png",
			"is_container": true,
			"inner_grid_width": 4,
			"inner_grid_height": 4
		},
		{
			"id": "00000000-0000-0000-0000-000000000030",
			"name": "Pocion de Vida",
			"description": "Restaura HP de forma inmediata.",
			"rarity": "common",
			"item_type": "consumable",
			"grid_width": 1,
			"grid_height": 1,
			"icon_path": "res://assets/icons/items/lifepot1x1.png",
			"is_container": false
		},
		{
			"id": "00000000-0000-0000-0000-000000000031",
			"name": "Pocion de Mana",
			"description": "Restaura energia para habilidades.",
			"rarity": "common",
			"item_type": "consumable",
			"grid_width": 1,
			"grid_height": 1,
			"icon_path": "res://assets/icons/items/manapot1x1.png",
			"is_container": false
		}
	]

func clear_item_cache():
	ItemManager.clear_cache()
	print("ShelterManager: Item definition cache cleared.")

## Move an item to a new grid position (persists to backend DB)
func move_item(item_id: String, slot_x: int, slot_y: int, is_rotated: bool, is_secure: bool, char_id: String = "", parent_item_id: String = "") -> bool:
	var payload = {
		"item_id": item_id,
		"slot_x": slot_x,
		"slot_y": slot_y,
		"is_rotated": is_rotated,
		"is_secure": is_secure,
		"parent_item_id": "" if parent_item_id == "" else parent_item_id
	}
	var headers = {}
	if char_id != "":
		headers["X-Character-ID"] = char_id
		
	print("ShelterManager.move_item: item='%s' -> (%d,%d) parent='%s' char='%s' secure=%s" % [item_id, slot_x, slot_y, parent_item_id, char_id, str(is_secure)])
	
	var move_key = "move_" + item_id + "_" + str(Time.get_ticks_msec())
	var res = await APIClient.post_request("/shelter/inventory/move", payload, false, "", move_key, headers)
	
	print("ShelterManager.move_item: Response code=%s data=%s" % [str(res.get("code", "none")), str(res.get("data", res.get("error", "none")))])
	
	if res.get("code", 500) < 400:
		# Update local cache to keep UI in sync
		var item_data = all_items_cache.get(item_id)
		if item_data:
			item_data["slot_x"] = slot_x
			item_data["slot_y"] = slot_y
			item_data["is_rotated"] = is_rotated
			item_data["is_secure_slot"] = is_secure
			item_data["parent_item_id"] = parent_item_id
			print("ShelterManager.move_item: Cache UPDATED for '%s'. parent_item_id='%s'" % [item_id, parent_item_id])
		else:
			print("ShelterManager.move_item: WARNING - Item '%s' NOT FOUND in all_items_cache! Cache has %d items." % [item_id, all_items_cache.size()])
		
		# Also update the shallow isolated arrays if they contain the item
		for target_arr in [shelter_inventory, character_inventory]:
			for it in target_arr:
				if str(it.get("id")) == item_id:
					it["slot_x"] = slot_x
					it["slot_y"] = slot_y
					it["is_rotated"] = is_rotated
					it["is_secure_slot"] = is_secure
					it["parent_item_id"] = parent_item_id
					break
		return true
	else:
		var err_msg = res.get("error", "Failed to move item")
		operation_failed.emit(err_msg)
		print("ShelterManager: Move REJECTED: ", err_msg)
		return false


## Create a building by its definition ID
func create_building(definition_id: String, position: Vector3) -> void:
	var payload = {
		"building_definition_id": definition_id,
		"pos_x": position.x,
		"pos_y": position.y,
		"pos_z": position.z,
		"rot_x": 0, "rot_y": 0, "rot_z": 0, "rot_w": 1
	}
	
	var build_key = "build_" + definition_id + "_" + str(Time.get_ticks_msec())
	var res = await APIClient.post_request("/shelter/buildings", payload, false, "", build_key)
	var data = res.get("data")
	if data is Dictionary:
		building_created.emit(data)
		fetch_shelter() # Refresh local state
	else:
		operation_failed.emit(res.get("error", "Failed to create building"))

## Collect resources from a specific building
func collect_resource(building_id: String) -> void:
	var collect_key = "collect_" + building_id + "_" + str(Time.get_ticks_msec())
	var res = await APIClient.post_request("/shelter/buildings/" + building_id + "/collect", {}, false, "", collect_key)
	var data = res.get("data")
	if data is Dictionary:
		collection_success.emit(building_id, data)
		fetch_inventory() # Refresh inventory after collection
	else:
		operation_failed.emit(res.get("error", "Failed to collect resource"))

## Transition from Shelter to MMO World
func transition_to_world() -> void:
	world_transition_started.emit()
	
	# 1. Get Ticket
	var ticket = await AuthManager.fetch_world_ticket()
	if ticket == "":
		return
		
	# 2. Start Async Load of World Scene
	# Transition to World scene
	SceneManager.change_scene_async("res://World.tscn")
	
	# 3. Wait for load to finish and scene tree to mount
	await SceneManager.load_finished
	await Engine.get_main_loop().process_frame
	
	# 4. Connect Network with Ticket if not already connected by World._ready
	if NetworkManager and AuthManager.world_ticket != "":
		NetworkManager.connect_with_ticket(AuthManager.world_ticket)
		AuthManager.world_ticket = ""

## Helper: Get definition by type string
func get_definition_by_type(type: String) -> Dictionary:
	for def in building_definitions:
		if def.get("building_type") == type:
			return def
	return {}

func admin_add_item(target_user_id: String, target_char_id: String, item_def_id: String, quantity: int, x: int, y: int, is_secure: bool) -> bool:
	var target_list = character_inventory if target_char_id != "" else shelter_inventory
	var existing_item = null
	for it in target_list:
		if int(it.get("slot_x", -1)) == x and int(it.get("slot_y", -1)) == y:
			existing_item = it
			break
			
	if not existing_item:
		var def_data = {}
		for d in building_definitions:
			if d.get("id") == item_def_id:
				def_data = d
				break
		if def_data.is_empty():
			for d in _get_default_item_definitions():
				if d.get("id") == item_def_id:
					def_data = d
					break
		if def_data.is_empty() and item_def_id == "00000000-0000-0000-0000-000000000088":
			def_data = {
				"id": "00000000-0000-0000-0000-000000000088",
				"name": "Amuleto Vacío Ancestral",
				"rarity": "legendary",
				"item_type": "equipment",
				"grid_width": 1,
				"grid_height": 1,
				"icon_path": "res://assets/icons/items/amulet1x1.png"
			}
			
		var item_id = "admin_" + str(Time.get_ticks_msec()) + "_" + str(randi() % 1000)
		var item_dict = {
			"id": item_id,
			"user_id": target_user_id,
			"character_id": target_char_id,
			"item_definition_id": item_def_id,
			"display_name": def_data.get("name", "Objeto"),
			"icon_path": def_data.get("icon_path", ""),
			"rarity": def_data.get("rarity", "common"),
			"item_type": def_data.get("item_type", "misc"),
			"grid_width": int(def_data.get("grid_width", 1)),
			"grid_height": int(def_data.get("grid_height", 1)),
			"slot_x": x,
			"slot_y": y,
			"is_rotated": false,
			"is_secure": is_secure,
			"quantity": quantity
		}
		target_list.append(item_dict)
		all_items_cache[item_id] = item_dict

	if target_user_id == "" or not AuthManager or AuthManager.auth_token == "":
		return true

	var body = {
		"user_id": target_user_id,
		"character_id": target_char_id,
		"item_definition_id": item_def_id,
		"quantity": quantity,
		"slot_x": x,
		"slot_y": y,
		"is_secure_slot": is_secure,
		"is_rotated": false,
		"parent_item_id": ""
	}
	
	var res = await APIClient.post_request("/admin/inventory/add", body)
	if res.has("data") or res.get("code") == 201:
		print("Admin: Item added successfully in backend")
		return true
	
	print("Admin: Warning: Backend add returned code ", res.get("code"), " but local item was registered.")
	return true

func admin_remove_item(target_user_id: String, target_char_id: String, inventory_item_id: String) -> bool:
	if target_user_id == "" or not AuthManager or AuthManager.auth_token == "":
		return true
	var body = {
		"user_id": target_user_id,
		"character_id": target_char_id,
		"item_id": inventory_item_id
	}
	
	var res = await APIClient.post_request("/admin/inventory/remove", body)
	if res.has("data") or res.get("code") == 200:
		print("Admin: Item removed successfully")
		return true
	
	print("Admin: Failed to remove item: ", res.get("error", "Unknown error"))
	return false

func admin_resize_inventory(target_char_id: String, width: int, height: int) -> bool:
	var body = {
		"character_id": target_char_id,
		"width": width,
		"height": height
	}
	
	var res = await APIClient.post_request("/admin/inventory/resize", body)
	if res.has("data") or res.get("code") == 200:
		print("Admin: Inventory resized successfully")
		return true
	
	print("Admin: Failed to resize inventory: ", res.get("error", "Unknown error"))
	return false

## Generic removal helper for items and admin actions
func remove_item(inventory_item_id: String, type: ShelterManager.InventoryType) -> bool:
	var target_uid = AuthManager.user_id if AuthManager else ""
	var target_cid = ""
	if type == ShelterManager.InventoryType.CHARACTER and AuthManager:
		target_cid = AuthManager.selected_character_id
	
	# Purge from local memory caches unconditionally
	for i in range(shelter_inventory.size() - 1, -1, -1):
		if str(shelter_inventory[i].get("id")) == inventory_item_id:
			shelter_inventory.remove_at(i)
			break
	for i in range(character_inventory.size() - 1, -1, -1):
		if str(character_inventory[i].get("id")) == inventory_item_id:
			character_inventory.remove_at(i)
			break
	all_items_cache.erase(inventory_item_id)
	
	# If we are admin or connected, notify the backend
	if AuthManager and AuthManager.is_admin and target_uid != "":
		return await admin_remove_item(target_uid, target_cid, inventory_item_id)
	
	return true
