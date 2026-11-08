extends Node

# ItemManager.gd
# Manages item definitions with a local persistent cache on disk and a RAM-safe LRU cache.

# Unused signals removed for debugger cleanliness

const CACHE_DIR = "user://cache/items/"
const RAM_CACHE_LIMIT = 500 # Maximum number of definitions to keep in RAM

var ram_cache: Dictionary = {} # id (String) -> data (Dictionary)
var lru_order: Array = [] # List of IDs, newest at the back

var loading_queues: Dictionary = {} # id -> Array of Callables (callbacks)
var fetch_in_progress: bool = false

func _ready() -> void:
	# Ensure cache directory exists
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)

# Public API: Get item definitions asychronously (Batch)
func get_definitions_async(ids: Array) -> Array:
	var results = []
	var missing_ids = []
	
	for id in ids:
		if ram_cache.has(id):
			_update_lru(id)
			results.append(ram_cache[id])
		else:
			var disk_data = _load_from_disk(id)
			if disk_data:
				_add_to_ram(id, disk_data)
				results.append(disk_data)
			else:
				missing_ids.append(id)
	
	if missing_ids.size() > 0:
		var remote_defs = await fetch_definitions_remote(missing_ids)
		if remote_defs:
			results.append_array(remote_defs)
			
	return results

# Internal: Fetch from API
func fetch_definitions_remote(missing_ids: Array) -> Array:
	if missing_ids.size() == 0: return []
	
	# Group by ID to avoid duplicate requests for the same ID while fetching
	var final_results = []
	var ids_to_query = []
	for id in missing_ids:
		if not loading_queues.has(id):
			loading_queues[id] = []
			ids_to_query.append(id)
	
	if ids_to_query.size() > 0:
		var ids_param = ",".join(ids_to_query)
		var response = await APIClient.get_request("/shelter/items/definitions?ids=" + ids_param)
		
		if response.get("code", 500) == 200 and response.get("data") is Array:
			for item_data in response.get("data"):
				var id = item_data.get("id")
				if id:
					_save_to_disk(id, item_data)
					_add_to_ram(id, item_data)
					final_results.append(item_data)
		else:
			push_error("ItemManager: Failed to fetch remote definitions. Error: " + str(response.get("error", "Unknown")))
			return []

	return final_results

# --- RAM & Disk Utilities ---

func _add_to_ram(id: String, data: Dictionary) -> void:
	if ram_cache.size() >= RAM_CACHE_LIMIT:
		var oldest = lru_order.pop_front()
		ram_cache.erase(oldest)
	
	ram_cache[id] = data
	lru_order.append(id)

func _update_lru(id: String) -> void:
	lru_order.erase(id)
	lru_order.append(id)

func _load_from_disk(id: String) -> Variant:
	var path = CACHE_DIR + id + ".json"
	if FileAccess.file_exists(path):
		var file = FileAccess.open(path, FileAccess.READ)
		var content = file.get_as_text()
		var json = JSON.new()
		if json.parse(content) == OK:
			return json.data
	return null

func _save_to_disk(id: String, data: Dictionary) -> void:
	var path = CACHE_DIR + id + ".json"
	var file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))

func clear_cache() -> void:
	ram_cache.clear()
	lru_order.clear()
	var dir = DirAccess.open(CACHE_DIR)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir():
				dir.remove(file_name)
			file_name = dir.get_next()
	print("ItemManager: Local cache cleared")
