extends Node

## APIClient.gd - Unified HTTP Client for Platform Backend
## Centralizes JWT injection, error handling, and telemetery.

signal request_failed(endpoint: String, code: int, message: String)
signal unauthorized_access # Emitted on 401

func _ready():
	print("APIClient: Initialized.")

## Generic GET request
func get_request(endpoint: String, is_public: bool = false, base_url_override: String = "", custom_headers: Dictionary = {}) -> Dictionary:
	return await _do_request(endpoint, HTTPClient.METHOD_GET, "", is_public, base_url_override, "", custom_headers)

## Generic POST request
func post_request(endpoint: String, body: Dictionary = {}, is_public: bool = false, base_url_override: String = "", idempotency_key: String = "", custom_headers: Dictionary = {}) -> Dictionary:
	var body_json = JSON.stringify(body)
	return await _do_request(endpoint, HTTPClient.METHOD_POST, body_json, is_public, base_url_override, idempotency_key, custom_headers)

func _do_request(endpoint: String, method: int, body: String = "", is_public: bool = false, base_url_override: String = "", idempotency_key: String = "", custom_headers: Dictionary = {}) -> Dictionary:
	var http = HTTPRequest.new()
	add_child(http)
	
	# Auto-generate idempotency key for state-changing methods if missing
	if idempotency_key == "" and method != HTTPClient.METHOD_GET and method != HTTPClient.METHOD_HEAD:
		idempotency_key = "auto_" + str(Time.get_ticks_msec()) + "_" + str(randi())
	
	var base_url = AuthManager.gateway_url if AuthManager.gateway_url != "" else GameConfig.get_gateway_url()
	if base_url_override != "":
		base_url = base_url_override
		
	var url = base_url + endpoint
	var headers = [
		"Content-Type: application/json",
		"X-Client-Integrity: " + ClientSecurity.get_client_hash()
	]
	
	if not is_public:
		headers.append("Authorization: Bearer " + AuthManager.auth_token)
	
	if idempotency_key != "":
		headers.append("X-Idempotency-Key: " + idempotency_key)
	
	for key in custom_headers.keys():
		headers.append(key + ": " + str(custom_headers[key]))
	
	var start_time = Time.get_ticks_msec()
	var err = http.request(url, headers, method, body)
	
	if err != OK:
		print("APIClient Error: Failed to initiate request to ", url)
		http.queue_free()
		return {"error": "Connection failed"}
		
	var result = await http.request_completed
	var elapsed = Time.get_ticks_msec() - start_time
	
	# result = [result, response_code, headers, body]
	var response_code = result[1]
	var response_body = result[3].get_string_from_utf8()
	
	http.queue_free()
	
	# Telemetry / Debug
	print("APIClient: [%d] %s (%dms)" % [response_code, endpoint, elapsed])
	
	var json = null
	if response_body.begins_with("{") or response_body.begins_with("["):
		json = JSON.parse_string(response_body)
	
	if response_code == 401:
		unauthorized_access.emit()
		return {"error": "Unauthorized"}
		
	if response_code >= 400:
		var err_msg = "API Error"
		if json and json.has("error"):
			err_msg = json["error"]
		request_failed.emit(endpoint, response_code, err_msg)
		return {"error": err_msg, "code": response_code}
		
	return {"data": json, "code": response_code}

## Character Management
func list_characters() -> Dictionary:
	return await get_request("/profile/characters")

func create_character(char_name: String) -> Dictionary:
	return await post_request("/profile/characters", {"name": char_name})

func delete_character(id: String) -> Dictionary:
	return await _do_request("/profile/characters/" + id, HTTPClient.METHOD_DELETE)

func revive_character(id: String) -> Dictionary:
	return await post_request("/profile/characters/" + id + "/revive", {})

## World Ticket with Character
func get_world_ticket(character_id: String, x: float = 0.0, y: float = 0.0, z: float = 0.0) -> Dictionary:
	return await post_request("/world/join-ticket", {
		"character_id": character_id,
		"x": x,
		"y": y,
		"z": z
	})

func fetch_death_echo(echo_id: String) -> Dictionary:
	return await get_request("/profile/echoes/" + echo_id)

func collect_echo_item(echo_id: String, item_id: String, target_character_id: String, slot_x: int = 0, slot_y: int = 0, secure: bool = false, parent_item_id: String = "") -> Dictionary:
	var body = {
		"target_character_id": target_character_id,
		"slot_x": slot_x,
		"slot_y": slot_y,
		"secure": secure,
		"parent_item_id": parent_item_id
	}
	return await post_request("/profile/echoes/" + echo_id + "/collect/" + item_id, body)
