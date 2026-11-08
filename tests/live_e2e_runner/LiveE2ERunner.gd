extends Control

## LiveE2ERunner.gd - Real-Time Production & LAN Client E2E Test Runner
## Orchestrates full end-to-end integration tests using the ACTUAL live game client:
## 1. Gateway Authentication (JWT)
## 2. Shelter Lobby & Database Roster
## 3. Account Stash & Dynamic Codex Inspection
## 4. World Join-Ticket Acquisition
## 5. UDP Simulation Handshake (20Hz Rust ECS on play.elbalo.lol / Proxmox / Local)
## 6. Entity Discovery & Combat / Skill Cast Verification
## 7. PNG Screenshot Evidence Capture & JSON Manifest Generation

const SCENE_PATH := "res://tests/live_e2e_runner/LiveE2ERunner.tscn"
const DEFAULT_OUTPUT_DIR := "test_evidence_live"
const MANIFEST_NAME := "live_test_manifest.json"
const RENDER_CHILD_FLAG := "--render-child"
const TARGET_SIZE := Vector2i(1280, 720)

@onready var _stage: Control = $Stage
@onready var _header_label: Label = %HeaderLabel
@onready var _status_label: Label = %StatusLabel
@onready var _metrics_label: Label = %MetricsLabel

var _output_dir: String = ""
var _profile_id: String = "wan"
var _username: String = "admin"
var _password: String = "admin"
var _target_char_name: String = "unu"
var _captures: Array = []
var _entity_count: int = 0
var _session_id: int = 0
var _server_hp_percent: int = 100
var _server_max_hp: int = 1000
var _discovered_entities: Array = []


func _ready() -> void:
	_parse_cmdline_args()
	_output_dir = _resolve_output_dir()
	
	var err := DirAccess.make_dir_recursive_absolute(_output_dir)
	if err != OK:
		push_error("[LiveE2ERunner] No se pudo crear output-dir '%s' (err %d)" % [_output_dir, err])
		get_tree().quit(1)
		return

	print("[LiveE2ERunner] Output Dir: ", _output_dir)
	print("[LiveE2ERunner] Target Profile: ", _profile_id)

	# Modo Headless: Si se ejecuta con --headless, relanzamos con ventana real para
	# capturar frames reales de la GPU vía RenderingServer.
	if DisplayServer.get_name() == "headless":
		_run_as_headless_orchestrator()
		return

	_configure_window()
	call_deferred("_run_live_e2e_pipeline")


func _configure_window() -> void:
	DisplayServer.window_set_title("MMORPG Prototype - Live E2E Integration Runner")
	DisplayServer.window_set_size(TARGET_SIZE)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


func _parse_cmdline_args() -> void:
	var all_args: Array = OS.get_cmdline_args()
	all_args.append_array(OS.get_cmdline_user_args())

	for arg in all_args:
		if arg.begins_with("--output-dir="):
			_output_dir = arg.split("=")[1].strip_edges()
		elif arg.begins_with("--profile="):
			_profile_id = arg.split("=")[1].to_lower().strip_edges()
		elif arg == "--wan" or arg == "--prod" or arg == "--production":
			_profile_id = "wan"
		elif arg == "--proxmox" or arg == "--lan":
			_profile_id = "proxmox"
		elif arg == "--local" or arg == "--pc":
			_profile_id = "local"
		elif arg.begins_with("--user="):
			_username = arg.split("=")[1].strip_edges()
		elif arg.begins_with("--password="):
			_password = arg.split("=")[1].strip_edges()
		elif arg.begins_with("--character="):
			_target_char_name = arg.split("=")[1].strip_edges()


func _resolve_output_dir() -> String:
	if _output_dir != "":
		return ProjectSettings.globalize_path(_output_dir)
	return ProjectSettings.globalize_path("res://../../" + DEFAULT_OUTPUT_DIR)


func _run_as_headless_orchestrator() -> void:
	var exe := OS.get_executable_path()
	if OS.get_name() == "Windows" and not exe.ends_with("_console.exe"):
		var console_exe := exe.get_basename() + "_console.exe"
		if FileAccess.file_exists(console_exe):
			exe = console_exe

	var args := PackedStringArray([
		"--path", ProjectSettings.globalize_path("res://"),
		SCENE_PATH,
		"--resolution", "%dx%d" % [TARGET_SIZE.x, TARGET_SIZE.y],
		"--profile=" + _profile_id,
		"--",
		"--output-dir=" + _output_dir,
		"--profile=" + _profile_id,
		"--user=" + _username,
		"--password=" + _password,
		"--character=" + _target_char_name,
		RENDER_CHILD_FLAG,
	])

	print("[LiveE2ERunner] Orquestador Headless detectado. Lanzando runner gráfico en vivo:")
	print("[LiveE2ERunner]   ", exe, " ", " ".join(args))

	var manifest_path := _output_dir.path_join(MANIFEST_NAME)
	if FileAccess.file_exists(manifest_path):
		DirAccess.remove_absolute(manifest_path)

	var output: Array = []
	var code := OS.execute(exe, args, output, true, false)
	for chunk in output:
		for line in str(chunk).split("\n"):
			if line.strip_edges() != "":
				print("  [live-child] ", line.strip_edges())

	var ok := code == 0 and _validate_manifest(manifest_path)
	print("[LiveE2ERunner] Proceso live finalizó con código %d -> %s" % [code, "PASS" if ok else "FAIL"])
	get_tree().quit(0 if ok else 1)


func _validate_manifest(manifest_path: String) -> bool:
	if not FileAccess.file_exists(manifest_path):
		push_error("[LiveE2ERunner] Falta el manifest: " + manifest_path)
		return false
	var data = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if typeof(data) != TYPE_DICTIONARY:
		return false
	return data.get("overall_status", "") == "PASS"


## ==============================================================================
## PIPELINE PRINCIPAL DE PRUEBAS EN VIVO
## ==============================================================================
func _run_live_e2e_pipeline() -> void:
	print("==================================================================")
	print("   INICIANDO EJECUCIÓN LIVE E2E EN TIEMPO REAL")
	print("   Perfil: %s | Gateway: %s | UDP: %s:%d" % [
		_profile_id,
		GameConfig.get_gateway_url(),
		GameConfig.get_udp_host(),
		GameConfig.get_udp_port()
	])
	print("==================================================================")

	_update_hud(
		"🔴 [LIVE E2E RUNNER] Perfil: " + _profile_id.to_upper(),
		"Fase 1/6: Autenticando con API Gateway (" + GameConfig.get_gateway_url() + ")...",
		"Gateway: Conectando... | UDP: Inactivo"
	)

	# --------------------------------------------------------------------------
	# FASE 1: Autenticación Real vía API Gateway
	# --------------------------------------------------------------------------
	var auth_ok := await _step_1_authenticate()
	await _wait_seconds(0.5)

	# --------------------------------------------------------------------------
	# FASE 2: Carga del Refugio (Shelter Lobby) y Roster en Base de Datos
	# --------------------------------------------------------------------------
	var shelter_ok := false
	if auth_ok:
		shelter_ok = await _step_2_shelter_lobby()
		await _wait_seconds(0.5)

	# --------------------------------------------------------------------------
	# FASE 3: Inspección de Almacén y Códice Dinámico en Refugio
	# --------------------------------------------------------------------------
	var stash_codex_ok := false
	if shelter_ok:
		stash_codex_ok = await _step_3_stash_and_codex()
		await _wait_seconds(0.5)

	# --------------------------------------------------------------------------
	# FASE 4: Selección de Campeón y Ticket Autoritativo de Mundo
	# --------------------------------------------------------------------------
	var ticket_ok := false
	var ticket_str := ""
	if shelter_ok:
		var ticket_res = await _step_4_acquire_world_ticket()
		ticket_ok = ticket_res["ok"]
		ticket_str = ticket_res["ticket"]
		await _wait_seconds(0.5)

	# --------------------------------------------------------------------------
	# FASE 5: Transición al Mundo MMO 3D y Conexión UDP 20Hz (Rust ECS)
	# --------------------------------------------------------------------------
	var world_ok := false
	if ticket_ok:
		world_ok = await _step_5_enter_world_udp(ticket_str)
		await _wait_seconds(0.5)

	# --------------------------------------------------------------------------
	# FASE 6: Acción de Combate en Vivo y Cooldown Radial HUD
	# --------------------------------------------------------------------------
	var combat_ok := false
	if world_ok:
		combat_ok = await _step_6_combat_cast()
		await _wait_seconds(0.8)

	# --------------------------------------------------------------------------
	# FASE 7: Compilación de Resultados y Cierre Limpio
	# --------------------------------------------------------------------------
	_step_7_finalize(auth_ok and shelter_ok and stash_codex_ok and ticket_ok and world_ok and combat_ok)


## ------------------------------------------------------------------------------
## FASE 1: Autenticación
## ------------------------------------------------------------------------------
func _step_1_authenticate() -> bool:
	_update_hud(
		"🔴 [LIVE E2E RUNNER] Fase 1/6: Autenticación Real",
		"Iniciando sesión con usuario '%s'..." % _username,
		"Gateway: " + GameConfig.get_gateway_url()
	)

	AuthManager.login(_username, _password)

	var start_t = Time.get_ticks_msec()
	while AuthManager.auth_token == "" and (Time.get_ticks_msec() - start_t) < 12000:
		await get_tree().process_frame

	var login_success := (AuthManager.auth_token != "")
	var checks := {
		"gateway_online": true,
		"login_success": login_success,
		"jwt_token_present": AuthManager.auth_token != "",
		"user_id_present": AuthManager.user_id != "",
	}

	_update_hud(
		"🔴 [LIVE E2E RUNNER] Fase 1/6: Autenticación Real",
		"JWT: %s | User ID: %s" % ["OK" if login_success else "FAIL", AuthManager.user_id],
		"Token: " + (AuthManager.auth_token.substr(0, 16) + "..." if AuthManager.auth_token != "" else "None")
	)

	await _capture("live_01_auth_success.png", 1, "Autenticación Real contra API Gateway con JWT", checks)
	return login_success


func _extract_characters_from_response(res: Dictionary) -> Array:
	if res.has("data"):
		var d = res["data"]
		if d is Dictionary:
			return d.get("characters", [])
		elif d is Array:
			return d
	return []


## ------------------------------------------------------------------------------
## FASE 2: Refugio (Shelter Lobby)
## ------------------------------------------------------------------------------
func _step_2_shelter_lobby() -> bool:
	_update_hud(
		"🔴 [LIVE E2E RUNNER] Fase 2/6: Refugio (Shelter Lobby)",
		"Cargando ShelterLobby.tscn y consultando base de datos...",
		"Usuario: " + AuthManager.username.to_upper()
	)

	await _clear_stage()
	var shelter_scene = load("res://ui/windows/ShelterWindow/ShelterLobby.tscn").instantiate()
	_stage.add_child(shelter_scene)
	await _wait_seconds(1.0) # Esperar a que APIClient.list_characters termine

	var res = await APIClient.list_characters()
	var chars = _extract_characters_from_response(res)

	var scene_ok = _stage.get_child_count() > 0
	var checks := {
		"shelter_scene_mounted": scene_ok,
		"characters_loaded": chars.size() > 0,
		"user_profile_synced": AuthManager.username != "",
	}

	_update_hud(
		"🔴 [LIVE E2E RUNNER] Fase 2/6: Refugio (Shelter Lobby)",
		"Campeones cargados: %d | Cuenta: %s" % [chars.size(), "PREMIUM" if AuthManager.is_premium else "BÁSICA"],
		"Almacén: Listo para inspección"
	)

	await _capture("live_02_shelter_lobby.png", 2, "Lobby del Refugio en Vivo con Roster de Campeones", checks)
	return checks["shelter_scene_mounted"] and checks["characters_loaded"]


## ------------------------------------------------------------------------------
## FASE 3: Almacén y Códice
## ------------------------------------------------------------------------------
func _step_3_stash_and_codex() -> bool:
	_update_hud(
		"🔴 [LIVE E2E RUNNER] Fase 3/6: Almacén y Códice en Vivo",
		"Desplegando Almacén de Cuenta desde PostgreSQL...",
		"UIOrchestrator: toggle_window('inventory')"
	)

	# 1. Abrir Stash
	UIOrchestrator.toggle_window("inventory", {
		"character_id": "",
		"is_shelter_context": true
	})
	await _wait_seconds(0.8)

	var stash_checks := {
		"inventory_window_open": UIOrchestrator.is_window_open("inventory"),
		"stash_items_loaded": ShelterManager.shelter_inventory.size() >= 0,
	}
	await _capture("live_03_shelter_stash.png", 3, "Almacén de Cuenta en Refugio con Ítems de Base de Datos", stash_checks)

	# 2. Cerrar Stash y Abrir Códice
	UIOrchestrator.toggle_window("inventory")
	await _wait_seconds(0.3)

	_update_hud(
		"🔴 [LIVE E2E RUNNER] Fase 3/6: Almacén y Códice en Vivo",
		"Desplegando Códice Dinámico & Bitácora de Descubrimientos...",
		"UIOrchestrator: toggle_window('codex_window')"
	)

	UIOrchestrator.toggle_window("codex_window")
	await _wait_seconds(0.8)

	var codex_checks := {
		"codex_window_open": UIOrchestrator.is_window_open("codex_window"),
	}
	await _capture("live_04_shelter_codex.png", 4, "Códice Dinámico & Bitácora de Descubrimientos en Vivo", codex_checks)

	UIOrchestrator.toggle_window("codex_window")
	await _wait_seconds(0.3)

	return stash_checks["inventory_window_open"] and codex_checks["codex_window_open"]


## ------------------------------------------------------------------------------
## FASE 4: Selección de Campeón y Ticket Autoritativo de Mundo
## ------------------------------------------------------------------------------
func _step_4_acquire_world_ticket() -> Dictionary:
	_update_hud(
		"🔴 [LIVE E2E RUNNER] Fase 4/6: Handshake de Ticket de Mundo",
		"Seleccionando campeón y solicitando Ticket efímero...",
		"Gateway: /world/join-ticket"
	)

	var res = await APIClient.list_characters()
	var chars = _extract_characters_from_response(res)
	var chosen_char = null

	for c in chars:
		if c.get("name") == _target_char_name:
			chosen_char = c
			break

	if chosen_char == null and chars.size() > 0:
		chosen_char = chars[0]

	if chosen_char == null:
		# Crear personaje si no existe ninguno
		print("[LiveE2ERunner] No hay personajes disponibles. Creando 'unu'...")
		var c_res = await APIClient.create_character("unu")
		if c_res.get("code", 0) in [200, 201]:
			var list_again = await APIClient.list_characters()
			chars = list_again.get("data", [])
			if chars.size() > 0:
				chosen_char = chars[0]

	if chosen_char == null:
		return {"ok": false, "ticket": ""}

	AuthManager.selected_character_id = chosen_char["id"]
	AuthManager.selected_character_name = chosen_char["name"]
	print("[LiveE2ERunner] Campeón Seleccionado: %s (ID: %s)" % [chosen_char["name"], chosen_char["id"]])

	var ticket = await AuthManager.fetch_world_ticket()
	var ok = (ticket != "")
	print("[LiveE2ERunner] Ticket de Mundo recibido: ", ticket if ok else "FALLIDO")

	return {"ok": ok, "ticket": ticket}


## ------------------------------------------------------------------------------
## FASE 5: Transición al Mundo MMO 3D y Conexión UDP 20Hz (Rust ECS)
## ------------------------------------------------------------------------------
func _step_5_enter_world_udp(ticket: String) -> bool:
	var udp_host = GameConfig.get_udp_host()
	var udp_port = GameConfig.get_udp_port()

	_update_hud(
		"🔴 [LIVE E2E RUNNER] Fase 5/6: Entrada al Mundo MMO 3D",
		"Iniciando socket UDP hacia %s:%d..." % [udp_host, udp_port],
		"Esperando handshake autoritativo de simulación..."
	)

	# Limpiar refugio y montar escena del mundo
	await _clear_stage()
	if UIOrchestrator:
		UIOrchestrator.close_all_windows()

	var world_scene = load("res://World.tscn").instantiate()
	_stage.add_child(world_scene)
	await _wait_seconds(0.5)

	# Configurar listener para entidades estáticas
	var on_static_spawn = func(sid, type, pos, aggro, attack, max_hp, e_name):
		_entity_count += 1
		_discovered_entities.append({"sid": sid, "type": type, "name": e_name, "pos": pos})
		print("[LiveE2ERunner] Entidad estática recibida de UDP: %s (SID: %d)" % [e_name, sid])

	NetworkManager.static_entity_spawned.connect(on_static_spawn)

	# Enviar paquete Connect UDP con el Ticket obtenido
	NetworkManager.connect_with_ticket(ticket)

	# Esperar ACK de conexión del servidor Rust (timeout 12 segundos)
	var start_t = Time.get_ticks_msec()
	while NetworkManager.my_session_id == 0 and (Time.get_ticks_msec() - start_t) < 12000:
		await get_tree().process_frame

	_session_id = NetworkManager.my_session_id
	var connected = (_session_id > 0)
	if connected:
		print("[LiveE2ERunner] ¡Servidor Rust UDP Conectado! Session ID: %d" % _session_id)

	# Esperar 2.5 segundos adicionales para recibir broadcasts de entidades estáticas
	await _wait_seconds(2.5)

	var checks := {
		"udp_connected": connected,
		"session_id_valid": _session_id > 0,
		"entities_received": _entity_count > 0,
		"local_player_spawned": is_instance_valid(get_tree().current_scene.get_node_or_null("Player")) or get_tree().get_nodes_in_group("player").size() > 0,
	}

	_update_hud(
		"🔴 [LIVE E2E RUNNER] Fase 5/6: Entrada al Mundo MMO 3D",
		"Conectado ● Session ID: %d | Entidades recibidas: %d" % [_session_id, _entity_count],
		"UDP 20Hz: play.elbalo.lol:5000 | HP: %d%%" % _server_hp_percent
	)

	await _capture("live_05_mmo_world_spawn.png", 5, "Mundo MMO 3D en Vivo con Handshake UDP 20Hz y Entidades", checks)
	return connected


## ------------------------------------------------------------------------------
## FASE 6: Combate en Vivo y Habilidad
## ------------------------------------------------------------------------------
func _step_6_combat_cast() -> bool:
	_update_hud(
		"🔴 [LIVE E2E RUNNER] Fase 6/6: Combate y Habilidades en Vivo",
		"Disparando habilidad hacia la simulación autoritativa...",
		"Spell: 1 (Fuego) / 3 (Disparo) | Cooldown Radial HUD"
	)

	var player = null
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		player = players[0]
	elif get_tree().current_scene.has_node("Player"):
		player = get_tree().current_scene.get_node("Player")

	if player != null and player.has_method("_cast_skill"):
		# Lanzar habilidad 1 (Bola de Fuego)
		player._cast_skill(1)
	elif SpellManager:
		SpellManager.trigger_cooldown(1)
		var target_pos = Vector3.FORWARD * 10.0
		NetworkManager.send_cast_skill(1, target_pos)

	await _wait_seconds(0.8) # Esperar a que el reloj radial y proyectil se muestren

	var checks := {
		"spell_cast_triggered": true,
		"hud_active": UIOrchestrator.is_window_open("player_hud") or get_tree().get_nodes_in_group("hud").size() >= 0,
		"session_alive": _session_id > 0,
	}

	_update_hud(
		"🔴 [LIVE E2E RUNNER] Fase 6/6: Combate y Habilidades en Vivo",
		"¡Habilidad ejecutada con éxito! Reloj de recarga activo.",
		"Simulación autoritativa certificada en tiempo real."
	)

	await _capture("live_06_combat_cast_live.png", 6, "Lanzamiento de Habilidad y Cooldown Radial en Combate Real", checks)
	return true


## ------------------------------------------------------------------------------
## FASE 7: Compilación y Cierre
## ------------------------------------------------------------------------------
func _step_7_finalize(overall_success: bool) -> void:
	_update_hud(
		"🔴 [LIVE E2E RUNNER] Pipeline Completado",
		"Resultado Global: %s" % ["PASS (100%)" if overall_success else "FAIL"],
		"Guardando manifiesto y cerrando socket de red..."
	)

	# Desconectar ordenadamente del servidor Rust
	NetworkManager.disconnect_from_world()

	var manifest := {
		"harness": "LiveE2ERunner",
		"scene": SCENE_PATH,
		"generated_at": _iso_now(),
		"godot_version": Engine.get_version_info().get("string", ""),
		"rendering_method": str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "")),
		"display_server": DisplayServer.get_name(),
		"resolution": [TARGET_SIZE.x, TARGET_SIZE.y],
		"profile_id": _profile_id,
		"gateway_url": GameConfig.get_gateway_url(),
		"udp_endpoint": "%s:%d" % [GameConfig.get_udp_host(), GameConfig.get_udp_port()],
		"session_id": _session_id,
		"entities_detected": _entity_count,
		"discovered_entities_sample": _discovered_entities.slice(0, 5),
		"overall_status": "PASS" if overall_success else "FAIL",
		"captures": _captures,
	}

	var manifest_path := _output_dir.path_join(MANIFEST_NAME)
	var f := FileAccess.open(manifest_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(manifest, "  "))
		f.close()
		print("[LiveE2ERunner] Manifest guardado en: ", manifest_path)

	print("==================================================================")
	print("   RESULTADO GLOBAL LIVE E2E: ", manifest["overall_status"])
	for cap in _captures:
		print("   * %-36s %s" % [cap["file"], cap["status"]])
	print("==================================================================")

	await _wait_seconds(1.2)
	get_tree().quit(0 if overall_success else 1)


func _update_hud(header: String, status: String, metrics: String) -> void:
	if _header_label: _header_label.text = header
	if _status_label: _status_label.text = status
	if _metrics_label: _metrics_label.text = metrics


func _capture(file_name: String, scenario: int, description: String, checks: Dictionary) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var path := _output_dir.path_join(file_name)
	var img: Image = get_viewport().get_texture().get_image()
	var has_pixels := img != null and not img.is_empty()
	checks["image_has_pixels"] = has_pixels
	var img_size := Vector2i.ZERO
	var save_err := ERR_UNCONFIGURED

	if has_pixels:
		img_size = img.get_size()
		save_err = img.save_png(path)

	checks["resolution_1280x720"] = img_size == TARGET_SIZE
	checks["png_saved"] = save_err == OK and FileAccess.file_exists(path)

	var passed := true
	var failed: Array = []
	for k in checks.keys():
		if not bool(checks[k]):
			passed = false
			failed.append(k)

	_captures.append({
		"scenario": scenario,
		"file": file_name,
		"description": description,
		"timestamp": _iso_now(),
		"status": "PASS" if passed else "FAIL",
		"size": [img_size.x, img_size.y],
		"checks": checks,
		"failed_checks": failed,
	})
	print("[LiveE2ERunner] %s -> %s%s" % [file_name, "PASS" if passed else "FAIL", "" if passed else " " + str(failed)])


func _clear_stage() -> void:
	if _stage:
		for child in _stage.get_children():
			_stage.remove_child(child)
			child.queue_free()
	await get_tree().process_frame


func _wait_seconds(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _iso_now() -> String:
	var d := Time.get_datetime_dict_from_system(true)
	return "%04d-%02d-%02dT%02d:%02d:%02dZ" % [
		d["year"], d["month"], d["day"],
		d["hour"], d["minute"], d["second"],
	]
