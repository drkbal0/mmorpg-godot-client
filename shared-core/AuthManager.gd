extends Node

var auth_token: String = ""
var refresh_token: String = ""
var user_id: String = ""
var username: String = ""
var last_pos: Vector3 = Vector3(-999, -999, -999)
var selected_character_id: String = ""
var selected_character_name: String = ""
var world_ticket: String = ""
var is_premium: bool = false
var is_admin: bool = false
var account_silver: int = 500
var character_silver: int = 0

var gateway_url: String = ""

func _ready():
	gateway_url = GameConfig.get_gateway_url()
	print("AuthManager: Initialized with Gateway URL: ", gateway_url)

var _temp_password: String = "" # Temporary storage for auto-login after register

signal auth_success
signal auth_failed(message)
signal profile_fetched
signal ticket_fetched(ticket: String)
signal password_updated
signal silver_updated(account: int, character: int)

func set_silver(p_account: int, p_character: int) -> void:
	account_silver = p_account
	character_silver = p_character
	silver_updated.emit(account_silver, character_silver)

func transfer_silver(amount: int, to_character: bool) -> int:
	if amount <= 0: return 0
	var moved = 0
	if to_character:
		moved = mini(amount, account_silver)
		account_silver -= moved
		character_silver += moved
	else:
		moved = mini(amount, character_silver)
		character_silver -= moved
		account_silver += moved
	silver_updated.emit(account_silver, character_silver)
	
	# Background persist to backend if online and character selected
	if selected_character_id != "" and auth_token != "":
		_persist_silver_transfer(moved, to_character)
	return moved

func _persist_silver_transfer(amount: int, to_character: bool) -> void:
	if amount <= 0: return
	var from_id = "stash" if to_character else selected_character_id
	var to_id = selected_character_id if to_character else "stash"
	var body = {
		"from_character_id": from_id,
		"to_character_id": to_id,
		"amount_silver": amount,
		"zone_id": 1
	}
	APIClient.post_request("/wallet/transfer", body, false)

func fetch_silver_balances() -> Dictionary:
	if auth_token == "":
		return {"account_silver": account_silver, "character_silver": character_silver}
	
	var stash_res = await APIClient.get_request("/wallet/stash")
	if stash_res.get("code", 500) == 200 and stash_res.has("data"):
		var s_data = stash_res.get("data")
		account_silver = int(s_data.get("silver_balance", s_data.get("balance_silver", account_silver)))
	
	if selected_character_id != "":
		var char_res = await APIClient.get_request("/wallet/" + selected_character_id)
		if char_res.get("code", 500) == 200 and char_res.has("data"):
			var c_data = char_res.get("data")
			character_silver = int(c_data.get("silver_balance", c_data.get("balance_silver", character_silver)))
	
	silver_updated.emit(account_silver, character_silver)
	return {"account_silver": account_silver, "character_silver": character_silver}

func fetch_profile():
	if auth_token == "":
		return
		
	var res = await APIClient.get_request("/profile/me")
	
	# Always reset to avoid persistence from previous session/login
	is_admin = false
	is_premium = false
	
	if res.get("code", 500) == 200 and res.has("data"):
		var json = res.get("data")
		last_pos.x = json.get("last_pos_x", json.get("lastPosX", 0.0))
		last_pos.y = json.get("last_pos_y", json.get("lastPosY", 0.0))
		last_pos.z = json.get("last_pos_z", json.get("lastPosZ", 0.0))
		is_premium = json.get("is_premium", json.get("isPremium", false))
		is_admin = json.get("is_admin", json.get("isAdmin", false))
		print("AuthManager: Loaded profile. Admin: ", is_admin, " Premium: ", is_premium)
		profile_fetched.emit()
	else:
		print("Error al cargar perfil del usuario (o token inválido)")
		profile_fetched.emit()
	


func register(p_username, p_email, p_password):
	username = p_username
	_temp_password = p_password
	
	# Registration MUST be idempotent to prevent duplicate accounts
	var registration_key = "reg_" + p_username + "_" + str(Time.get_ticks_msec())
	
	var res = await APIClient.post_request("/auth/register", {
		"username": p_username,
		"email": p_email,
		"password": p_password
	}, true, "", registration_key)
	
	_on_register_completed(0, res.get("code", 500), [], JSON.stringify(res.get("data", {})) if res.has("data") else res.get("error", ""))

func login(p_username, p_password):
	# reset state on login attempt
	is_admin = false
	is_premium = false
	auth_token = ""
	user_id = ""
	
	username = p_username # Store for nameplate
	
	# Login is technically state-changing (sessions/logs), 
	# but deterministic keys are harder here. We'll use a time-based one for now.
	var login_key = "login_" + p_username + "_" + str(Time.get_ticks_msec())
	
	var res = await APIClient.post_request("/auth/login", {
		"username": p_username,
		"password": p_password
	}, true, "", login_key)
	
	_on_login_completed(0, res.get("code", 500), [], JSON.stringify(res.get("data", {})) if res.has("data") else res.get("error", ""))

func _on_register_completed(_result, response_code, _headers, body_str):
	var json = null
	if body_str.begins_with("{") or body_str.begins_with("["):
		json = JSON.parse_string(body_str)
	
	if response_code == 200:
		print("Registration successful, auto-logging in...")
		login(username, _temp_password)
		_temp_password = "" # Clear after use
	else:
		var error_msg = "Error al registrar"
		if json != null and json is Dictionary and json.has("error"):
			error_msg = json.get("error")
		elif body_str != "":
			error_msg = body_str
		auth_failed.emit(error_msg)

func _on_login_completed(_result, response_code, _headers, body_str):
	# Robustez: Solo intentar parsear si el contenido parece JSON (comienza con { o [)
	# Esto evita el error rojo de Godot "Parse JSON failed" cuando el server responde "Unauthorized" plana.
	var json = null
	if body_str.begins_with("{") or body_str.begins_with("["):
		json = JSON.parse_string(body_str)
	
	if response_code == 200 and json != null:
		auth_token = json.get("access_token", "")
		user_id = json.get("user_id", "")
		auth_success.emit()
		fetch_profile() # Ensure we get is_admin/is_premium ASAP
	else:
		var error_msg = "Credenciales inválidas"
		if json != null and json is Dictionary and json.has("error"):
			error_msg = json.get("error")
		elif body_str != "":
			error_msg = body_str
		auth_failed.emit(error_msg)

func fetch_world_ticket():
	# Auto-connect removed, now handled by ChampionSelect -> Main flow
	if selected_character_id == "":
		print("AuthManager: No character selected for world ticket!")
		return ""
		
	var ticket_key = "ticket_" + user_id + "_" + str(Time.get_ticks_msec())
	var body = {
		"character_id": selected_character_id,
		"x": last_pos.x if last_pos.x != -999 else 0.0,
		"y": last_pos.y if last_pos.y != -999 else 0.0,
		"z": last_pos.z if last_pos.z != -999 else 0.0
	}
	var res = await APIClient.post_request("/world/join-ticket", body, false, "", ticket_key)
	if res.has("data"):
		var ticket = res["data"].get("ticket", "")
		world_ticket = ticket
		ticket_fetched.emit(ticket)
		return ticket
	else:
		var err_msg = res.get("error", "Failed to fetch world ticket")
		auth_failed.emit(err_msg)
		return ""

func verify_session() -> bool:
	if auth_token == "": return false
	var res = await APIClient.get_request("/auth/verify")
	return res.get("code", 500) == 200

func update_password(p_username, p_new_password):
	var key = "upd_" + p_username + "_" + str(Time.get_ticks_msec())
	var res = await APIClient.post_request("/auth/update-password", {
		"username": p_username,
		"password": p_new_password
	}, true, "", key)
	
	if res.get("code", 500) == 200:
		password_updated.emit()
		return true
	else:
		auth_failed.emit(res.get("error", "Error al actualizar contraseña"))
		return false

func logout():
	auth_token = ""
	refresh_token = ""
	user_id = ""
	username = ""
	selected_character_id = ""
	selected_character_name = ""
	world_ticket = ""
	is_admin = false
	is_premium = false
	account_silver = 500
	character_silver = 0
	last_pos = Vector3(-999, -999, -999)
	print("AuthManager: Session logged out and reset.")

## Flujo integral de cierre de sesión: desconexión autoritativa, purga de estado y retorno a pantalla de login
func perform_full_logout() -> void:
	print("[AuthManager] Iniciando proceso integral de cierre de sesión...")
	
	# 1. Desconexión limpia de red del mundo
	var net = get_node_or_null("/root/NetworkManager")
	if net:
		if net.has_method("disconnect_from_world"):
			net.disconnect_from_world()
		elif net.has_method("send_disconnect"):
			net.send_disconnect()
	
	# 2. Deselección de objetivo activo
	var target_mgr = get_node_or_null("/root/TargetManager")
	if target_mgr and target_mgr.has_method("clear_target"):
		target_mgr.clear_target()
	
	# 3. Limpieza de tiempos de reutilización (cooldowns)
	var spell_mgr = get_node_or_null("/root/SpellManager")
	if spell_mgr and "cooldowns" in spell_mgr and spell_mgr.cooldowns is Dictionary:
		spell_mgr.cooldowns.clear()
	
	# 4. Limpieza de memorias intermedias y cachés de Shelter/Inventario
	var shelter_mgr = get_node_or_null("/root/ShelterManager")
	if shelter_mgr:
		if "character_inventory" in shelter_mgr and shelter_mgr.character_inventory is Array:
			shelter_mgr.character_inventory.clear()
		if "shelter_inventory" in shelter_mgr and shelter_mgr.shelter_inventory is Array:
			shelter_mgr.shelter_inventory.clear()
		if "shelter_data" in shelter_mgr and shelter_mgr.shelter_data is Dictionary:
			shelter_mgr.shelter_data.clear()
		if "all_items_cache" in shelter_mgr and shelter_mgr.all_items_cache is Dictionary:
			shelter_mgr.all_items_cache.clear()
	
	# 5. Cancelación de arrastre UI y cierre de ventanas modales
	var ui_orch = get_node_or_null("/root/UIOrchestrator")
	if ui_orch:
		if ui_orch.has_method("stop_drag_follow"):
			ui_orch.stop_drag_follow()
		if ui_orch.has_method("close_all_windows"):
			ui_orch.close_all_windows()
	
	# 6. Reseteo de variables de sesión en memoria
	logout()
	
	# 7. Transición asíncrona a la pantalla de Login
	var scene_mgr = get_node_or_null("/root/SceneManager")
	if scene_mgr and scene_mgr.has_method("change_scene_async"):
		scene_mgr.change_scene_async("res://login_screen.tscn")
	else:
		get_tree().change_scene_to_file("res://login_screen.tscn")
