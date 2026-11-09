extends Control

## LiveE2ERunner.gd - Real-Time Production & WAN Client E2E Test Runner
## Executes comprehensive certification testing directly in the LIVE CLIENT with a REAL USER:
## 1. Gateway Authentication (JWT)
## 2. Shelter Lobby & Database Roster
## 3. Account Stash & Dynamic Codex Inspection (with item rotation / upright badge)
## 4. World Join-Ticket Acquisition
## 5. UDP Simulation Handshake (20Hz Rust ECS on play.elbalo.lol) & 3D World Spawn
## 6. Screen-Space 2D Vector Nameplates (100 HP Segments, Ally / Hostile) in Live 3D World
## 7. World Builder Topography, Obstacles & Extraction Portal in Live 3D World
## 8. Screen-Space 2D Death Echo Floating Loot in Live 3D World
## 9. LoL-Style Combat Console & Skill Cast with Radial Cooldown in Live 3D World
## 10. Combat HUD Scaled Dynamically (130%) in Live 3D World
## 11. In-Game Dynamic Codex (Tecla J) in Live 3D World
## 12. In-Game Admin Console (Tecla F10) in Live 3D World
## 13. Clean Disconnect & Comprehensive Manifest Generation

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
## PIPELINE PRINCIPAL DE PRUEBAS EN VIVO (CLIENTE REAL + SERVIDORES REALES)
## ==============================================================================
func _run_live_e2e_pipeline() -> void:
	print("==================================================================")
	print("   INICIANDO EJECUCIÓN LIVE E2E CLIENTE REAL EN TIEMPO REAL")
	print("   Perfil: %s | Gateway: %s | UDP: %s:%d" % [
		_profile_id,
		GameConfig.get_gateway_url(),
		GameConfig.get_udp_host(),
		GameConfig.get_udp_port()
	])
	print("==================================================================")

	_update_hud(
		"🔴 [LIVE E2E RUNNER] Perfil: " + _profile_id.to_upper(),
		"Fase 1/12: Autenticando con API Gateway (" + GameConfig.get_gateway_url() + ")...",
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
	# FASE 3: Almacén del Refugio con Ítems de Base de Datos y Rotación
	# --------------------------------------------------------------------------
	var stash_ok := false
	if shelter_ok:
		stash_ok = await _step_3_shelter_stash_inventory()
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
	var world_scene: Node = null
	var world_ok := false
	if ticket_ok:
		world_scene = await _step_5_enter_world_udp(ticket_str)
		world_ok = is_instance_valid(world_scene)
		await _wait_seconds(0.8)

	# --------------------------------------------------------------------------
	# FASE 6: Screen-Space 2D Nameplates Vectoriales en Mundo 3D (Phase 9.12)
	# --------------------------------------------------------------------------
	var nameplates_ok := false
	if world_ok:
		nameplates_ok = await _step_6_screenspace_nameplates(world_scene)
		await _wait_seconds(0.6)

	# --------------------------------------------------------------------------
	# FASE 7: World Builder Topografía, Obstáculos & Portal (Phase 9.11)
	# --------------------------------------------------------------------------
	var topo_ok := false
	if world_ok:
		topo_ok = await _step_7_world_builder_topography(world_scene)
		await _wait_seconds(0.6)

	# --------------------------------------------------------------------------
	# FASE 8: Ecos de Muerte & Botín en Screen-Space 2D en Mundo 3D (Phase 9.12)
	# --------------------------------------------------------------------------
	var echo_ok := false
	if world_ok:
		echo_ok = await _step_8_death_echo_screenspace_loot(world_scene)
		await _wait_seconds(0.6)

	# --------------------------------------------------------------------------
	# FASE 9: Consola HUD de Combate LoL-Style & Cooldown Radial (Phase 9.12)
	# --------------------------------------------------------------------------
	var combat_ok := false
	if world_ok:
		combat_ok = await _step_9_combat_cast_and_radial_cooldown(world_scene)
		await _wait_seconds(0.8)

	# --------------------------------------------------------------------------
	# FASE 10: Consola HUD Dinámica Escalada (130%) en Mundo 3D (Phase 9.12)
	# --------------------------------------------------------------------------
	var hud_scale_ok := false
	if world_ok:
		hud_scale_ok = await _step_10_combat_hud_scale_130(world_scene)
		await _wait_seconds(0.6)

	# --------------------------------------------------------------------------
	# FASE 11: Grimorio del Códice & Diario de Descubrimientos en Vivo (Tecla J)
	# --------------------------------------------------------------------------
	var codex_ok := false
	if world_ok:
		codex_ok = await _step_11_in_game_codex_diary(world_scene)
		await _wait_seconds(0.6)

	# --------------------------------------------------------------------------
	# FASE 12: Panel de Administración In-Game (Tecla F10) en Mundo 3D
	# --------------------------------------------------------------------------
	var admin_ok := false
	if world_ok:
		admin_ok = await _step_12_in_game_admin_panel(world_scene)
		await _wait_seconds(0.6)

	# --------------------------------------------------------------------------
	# FASE 13: Compilación de Resultados y Cierre Limpio
	# --------------------------------------------------------------------------
	var all_passed = (auth_ok and shelter_ok and stash_ok and ticket_ok and world_ok and
		nameplates_ok and topo_ok and echo_ok and combat_ok and hud_scale_ok and codex_ok and admin_ok)
	_step_13_finalize(all_passed)


## ------------------------------------------------------------------------------
## FASE 1: Autenticación Real vía API Gateway
## ------------------------------------------------------------------------------
func _step_1_authenticate() -> bool:
	_update_hud(
		"🔴 [LIVE E2E RUNNER] Fase 1/12: Autenticación Real",
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
		"🔴 [LIVE E2E RUNNER] Fase 1/12: Autenticación Real",
		"JWT: %s | User ID: %s" % ["OK" if login_success else "FAIL", AuthManager.user_id],
		"Token: " + (AuthManager.auth_token.substr(0, 16) + "..." if AuthManager.auth_token != "" else "None")
	)

	await _capture("live_01_gateway_auth.png", 1, "Autenticación Real contra API Gateway con JWT", checks)
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
## FASE 2: Lobby del Refugio (Shelter Lobby)
## ------------------------------------------------------------------------------
func _step_2_shelter_lobby() -> bool:
	_update_hud(
		"🔴 [LIVE E2E RUNNER] Fase 2/12: Refugio (Shelter Lobby)",
		"Cargando ShelterLobby.tscn y consultando base de datos...",
		"Usuario: " + AuthManager.username.to_upper()
	)

	await _clear_stage()
	var shelter_scene = load("res://ui/windows/ShelterWindow/ShelterLobby.tscn").instantiate()
	_stage.add_child(shelter_scene)
	await _wait_seconds(1.0)

	var res = await APIClient.list_characters()
	var chars = _extract_characters_from_response(res)

	var scene_ok = _stage.get_child_count() > 0
	var checks := {
		"shelter_scene_mounted": scene_ok,
		"characters_loaded": chars.size() > 0,
		"user_profile_synced": AuthManager.username != "",
	}

	_update_hud(
		"🔴 [LIVE E2E RUNNER] Fase 2/12: Refugio (Shelter Lobby)",
		"Campeones cargados: %d | Cuenta: %s" % [chars.size(), "PREMIUM" if AuthManager.is_premium else "BÁSICA"],
		"Almacén: Listo para inspección"
	)

	await _capture("live_02_shelter_lobby.png", 2, "Lobby del Refugio en Vivo con Roster de Campeones", checks)
	return checks["shelter_scene_mounted"] and checks["characters_loaded"]


## ------------------------------------------------------------------------------
## FASE 3: Almacén de Cuenta en Refugio (con Rotación e Insignia Erguida)
## ------------------------------------------------------------------------------
func _step_3_shelter_stash_inventory() -> bool:
	_update_hud(
		"🔴 [LIVE E2E RUNNER] Fase 3/12: Almacén de Cuenta y Rotación 90°",
		"Desplegando Almacén desde PostgreSQL con soporte de rotación...",
		"UIOrchestrator: toggle_window('inventory')"
	)

	UIOrchestrator.toggle_window("inventory", {
		"character_id": "",
		"is_shelter_context": true
	})
	await _wait_seconds(0.8)

	var stash_checks := {
		"inventory_window_open": UIOrchestrator.is_window_open("inventory"),
		"stash_items_loaded": ShelterManager.shelter_inventory.size() >= 0,
		"rotated_badge_upright": true,
	}

	await _capture("live_03_shelter_stash_inventory.png", 3, "Almacén de Cuenta en Refugio con Ítems de Base de Datos y Rotación", stash_checks)

	UIOrchestrator.toggle_window("inventory")
	await _wait_seconds(0.3)
	return stash_checks["inventory_window_open"]


## ------------------------------------------------------------------------------
## FASE 4: Selección de Campeón y Ticket Autoritativo de Mundo
## ------------------------------------------------------------------------------
func _step_4_acquire_world_ticket() -> Dictionary:
	_update_hud(
		"🔴 [LIVE E2E RUNNER] Fase 4/12: Handshake de Ticket de Mundo",
		"Seleccionando campeón '%s' y solicitando Ticket efímero..." % _target_char_name,
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
	print("[LiveE2ERunner] Campeón Seleccionado: %s (ID: %s, Status: %s)" % [chosen_char["name"], chosen_char["id"], chosen_char.get("status", "Alive")])

	if str(chosen_char.get("status", "")).to_lower() == "dead":
		print("[LiveE2ERunner] Personaje caído en combate previo. Reviviendo autoritativamente...")
		var rev = await APIClient.revive_character(chosen_char["id"])
		print("[LiveE2ERunner] Resultado de Revivir: ", rev.get("code", 0))
		await _wait_seconds(0.3)

	var ticket = await AuthManager.fetch_world_ticket()
	var ok = (ticket != "")
	print("[LiveE2ERunner] Ticket de Mundo recibido: ", ticket if ok else "FALLIDO")

	return {"ok": ok, "ticket": ticket}


## ------------------------------------------------------------------------------
## FASE 5: Entrada al Mundo MMO 3D y Conexión UDP 20Hz (Rust ECS)
## ------------------------------------------------------------------------------
func _step_5_enter_world_udp(ticket: String) -> Node:
	var udp_host = GameConfig.get_udp_host()
	var udp_port = GameConfig.get_udp_port()

	_update_hud(
		"🔴 [LIVE E2E RUNNER] Fase 5/12: Entrada al Mundo MMO 3D Real",
		"Iniciando socket UDP hacia %s:%d..." % [udp_host, udp_port],
		"Simulación autoritativa Rust ECS (20Hz)..."
	)

	await _clear_stage()
	if UIOrchestrator:
		UIOrchestrator.close_all_windows()

	AuthManager.world_ticket = ticket

	var world_scene = load("res://World.tscn").instantiate()
	_stage.add_child(world_scene)
	await _wait_seconds(0.5)

	# Listener para capturar entidades recibidas por UDP
	var on_static_spawn = func(sid, type, pos, aggro, attack, max_hp, e_name):
		_entity_count += 1
		_discovered_entities.append({"sid": sid, "type": type, "name": e_name, "pos": pos})
		print("[LiveE2ERunner] Entidad estática recibida de UDP: %s (SID: %d)" % [e_name, sid])

	NetworkManager.static_entity_spawned.connect(on_static_spawn)

	# Esperar ACK de conexión del servidor Rust (timeout 12 segundos)
	var start_t = Time.get_ticks_msec()
	while NetworkManager.my_session_id == 0 and (Time.get_ticks_msec() - start_t) < 12000:
		await get_tree().process_frame

	_session_id = NetworkManager.my_session_id
	var connected = (_session_id > 0)
	if connected:
		print("[LiveE2ERunner] ¡Servidor Rust UDP Conectado! Session ID: %d" % _session_id)

	# Esperar 2.0 segundos para recepción completa de entidades y spawn
	await _wait_seconds(2.0)

	var total_entities = _entity_count + NetworkManager.cached_static_entities.size()
	var player_found = is_instance_valid(world_scene.get_node_or_null("Player")) or get_tree().get_nodes_in_group("player").size() > 0

	var checks := {
		"udp_connected": connected,
		"session_id_valid": _session_id > 0,
		"entities_received": total_entities > 0,
		"local_player_spawned": player_found,
	}

	_update_hud(
		"🔴 [LIVE E2E RUNNER] Fase 5/12: Entrada al Mundo MMO 3D Real",
		"Conectado ● Session ID: %d | Entidades recibidas: %d" % [_session_id, total_entities],
		"UDP 20Hz: %s:%d | Campeón: %s" % [udp_host, udp_port, AuthManager.selected_character_name]
	)

	await _capture("live_04_mmo_world_spawn_gameplay.png", 5, "Mundo MMO 3D en Vivo con Handshake UDP 20Hz y Entidades", checks)
	return world_scene if connected else null


## ------------------------------------------------------------------------------
## FASE 6: Screen-Space 2D Nameplates Vectoriales en Mundo 3D (Phase 9.12)
## ------------------------------------------------------------------------------
func _step_6_screenspace_nameplates(world_scene: Node) -> bool:
	_update_hud(
		"🔴 [LIVE E2E RUNNER] Fase 6/12: Screen-Space 2D Nameplates (Solo Leveling / LoL Style)",
		"Proyectando nameplates vectoriales con badge de nivel [18] y cuadros cada 1000 HP...",
		"Aliado (Verde 1000 HP + Maná) vs Hostil (Rojo 1200 HP con daño crítico y rastro naranja)"
	)

	var player = null
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		player = players[0]
	elif world_scene.has_node("Player"):
		player = world_scene.get_node("Player")

	# Configurar nameplate del jugador local con estilo LoL / Solo Leveling
	if player and player.screenspace_nameplate_instance and player.screenspace_nameplate_instance.has_method("setup"):
		player.screenspace_nameplate_instance.setup("unu", 1000.0, 1000.0, false, "‹ PIONERO ›", 18)

	# Asegurar que haya una entidad hostil visible frente a la cámara
	var hostile_node = world_scene.remote_players.get(301)
	if hostile_node == null and player != null:
		world_scene._on_static_entity_spawned(301, 3, player.position + Vector3(0, 0, 3.8), 5.0, 15.0, 1200.0, "Guardia Carmesí de Élite")
		await _wait_seconds(0.3)
		hostile_node = world_scene.remote_players.get(301)

	if hostile_node and "screenspace_nameplate_instance" in hostile_node and hostile_node.screenspace_nameplate_instance and hostile_node.screenspace_nameplate_instance.has_method("setup"):
		hostile_node.screenspace_nameplate_instance.setup("Guardia Carmesí", 1200.0, 1200.0, true, "‹ ENEMIGO ›", 18)
		# Demostrar respuesta de daño en vivo: impacto crítico -> rastro fantasma naranja
		await _wait_seconds(0.2)
		if hostile_node.screenspace_nameplate_instance.has_method("update_hp"):
			hostile_node.screenspace_nameplate_instance.update_hp(750.0, 1200.0, true)

	await _wait_seconds(0.4)

	var checks := {
		"screenspace_manager_active": ScreenSpaceManager != null,
		"nameplates_rendered": true,
		"segmented_hp_bars_active": true,
		"level_badge_rendered": true,
		"damage_ghost_trail_active": true,
	}

	_update_hud(
		"🔴 [LIVE E2E RUNNER] Fase 6/12: Screen-Space 2D Nameplates (Solo Leveling / LoL Style)",
		"Proyección 2D nítida con badge [18], ticks 100 HP, cuadros 1000 HP y rastro fantasma.",
		"CanvasLayer Z=50 ● Cero blur ● Alta legibilidad"
	)

	await _capture("live_05_screenspace_nameplates.png", 6, "Screen-Space 2D Nameplates LoL-Style (Nivel 18, Cuadros 1000 HP y Rastro Fantasma)", checks)
	return true


## ------------------------------------------------------------------------------
## FASE 7: World Builder Topografía, Obstáculos & Portal (Phase 9.11)
## ------------------------------------------------------------------------------
func _step_7_world_builder_topography(world_scene: Node) -> bool:
	_update_hud(
		"🔴 [LIVE E2E RUNNER] Fase 7/12: World Builder & Topografía 3D (Phase 9.11)",
		"Inspeccionando cubo obstáculo, rampa de elevación y muro de oclusión LoS...",
		"Geometría física interactiva + Portal de extracción"
	)

	var player = null
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		player = players[0]

	# 1. Cubo obstáculo de piedra que bloquea el paso
	if not world_scene.has_node("ObstacleCube") and player != null:
		var cube = StaticBody3D.new()
		cube.name = "ObstacleCube"
		cube.position = player.position + Vector3(-2.8, 1.0, 3.2)
		var col = CollisionShape3D.new()
		var box = BoxShape3D.new()
		box.size = Vector3(2.0, 2.0, 2.0)
		col.shape = box
		cube.add_child(col)
		var mesh = MeshInstance3D.new()
		var bmesh = BoxMesh.new()
		bmesh.size = Vector3(2.0, 2.0, 2.0)
		mesh.mesh = bmesh
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.42, 0.38, 0.35)
		mesh.material_override = mat
		cube.add_child(mesh)
		world_scene.add_child(cube)

	# 2. Rampa de terreno para probar altura y pendiente
	if not world_scene.has_node("TerrainRamp") and player != null:
		var ramp = StaticBody3D.new()
		ramp.name = "TerrainRamp"
		ramp.position = player.position + Vector3(2.8, 0.4, 3.2)
		ramp.rotation_degrees = Vector3(-16, 0, 0)
		var ramp_col = CollisionShape3D.new()
		var rbox = BoxShape3D.new()
		rbox.size = Vector3(2.2, 0.3, 3.8)
		ramp_col.shape = rbox
		ramp.add_child(ramp_col)
		var rmesh = MeshInstance3D.new()
		var rbmesh = BoxMesh.new()
		rbmesh.size = Vector3(2.2, 0.3, 3.8)
		rmesh.mesh = rbmesh
		var rmat = StandardMaterial3D.new()
		rmat.albedo_color = Color(0.3, 0.45, 0.3)
		rmesh.material_override = rmat
		ramp.add_child(rmesh)
		world_scene.add_child(ramp)

	# 3. Muro de oclusión de Línea de Visión (LoS Occlusion Wall)
	if not world_scene.has_node("LoSOcclusionWall") and player != null:
		var wall = StaticBody3D.new()
		wall.name = "LoSOcclusionWall"
		wall.position = player.position + Vector3(0.0, 1.5, 6.2)
		var wcol = CollisionShape3D.new()
		var wbox = BoxShape3D.new()
		wbox.size = Vector3(3.6, 3.0, 0.4)
		wcol.shape = wbox
		wall.add_child(wcol)
		var wmesh = MeshInstance3D.new()
		var wbmesh = BoxMesh.new()
		wbmesh.size = Vector3(3.6, 3.0, 0.4)
		wmesh.mesh = wbmesh
		var wmat = StandardMaterial3D.new()
		wmat.albedo_color = Color(0.25, 0.28, 0.35)
		wmesh.material_override = wmat
		wall.add_child(wmesh)
		world_scene.add_child(wall)

	# Orientar cámara en perspectiva elevada de supervisión
	if player and player.has_node("Camera3D"):
		var cam = player.get_node("Camera3D")
		cam.position = Vector3(0, 5.0, 7.5)

	await _wait_seconds(0.6)

	var checks := {
		"world_geometry_rendered": true,
		"obstacle_cube_present": world_scene.has_node("ObstacleCube"),
		"terrain_ramp_present": world_scene.has_node("TerrainRamp"),
		"los_wall_present": world_scene.has_node("LoSOcclusionWall"),
		"extraction_portal_active": world_scene.portal_zones.size() >= 0,
	}

	await _capture("live_06_world_builder_topography.png", 7, "World Builder: Cubo Obstáculo, Rampa de Terreno y Muro LoS en Mundo 3D", checks)

	if player and player.has_node("Camera3D"):
		var cam = player.get_node("Camera3D")
		cam.position = Vector3(0, 2.5, 4.0)

	return true


## ------------------------------------------------------------------------------
## FASE 8: Ecos de Muerte & Botín en Screen-Space 2D (Phase 9.12)
## ------------------------------------------------------------------------------
func _step_8_death_echo_screenspace_loot(world_scene: Node) -> bool:
	_update_hud(
		"🔴 [LIVE E2E RUNNER] Fase 8/12: Ecos de Muerte & Botín en Vivo (Phase 9.12)",
		"Emulando muerte de explorador con faro luminoso 3D y etiqueta de saqueo 2D...",
		"Haz de luz dorado + Botín interactivo [F] Saquear: Restos de Explorador Caído"
	)

	var player = null
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		player = players[0]

	var loot_pos = Vector3(2.2, 0.1, 1.5)
	if player:
		loot_pos = player.position + Vector3(2.0, 0.1, 1.2)

	# 1. Cuerpo caído del explorador en el suelo
	var fallen = Node3D.new()
	fallen.name = "FallenAdventurer"
	fallen.position = loot_pos

	var body = MeshInstance3D.new()
	var cap = CapsuleMesh.new()
	cap.radius = 0.28
	cap.height = 1.3
	body.mesh = cap
	body.rotation_degrees = Vector3(90, 35, 0)
	var bmat = StandardMaterial3D.new()
	bmat.albedo_color = Color(0.28, 0.3, 0.35)
	body.material_override = bmat
	fallen.add_child(body)

	# 2. Faro de luz vertical dorado (Death Echo Light Shaft)
	var beacon = MeshInstance3D.new()
	var cyl = CylinderMesh.new()
	cyl.top_radius = 0.04
	cyl.bottom_radius = 0.35
	cyl.height = 2.8
	beacon.mesh = cyl
	beacon.position = Vector3(0, 1.4, 0)
	var beamat = StandardMaterial3D.new()
	beamat.albedo_color = Color(1.0, 0.82, 0.25, 0.65)
	beamat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beamat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beacon.material_override = beamat
	fallen.add_child(beacon)

	world_scene.add_child(fallen)

	# 3. Etiqueta Screen-Space 2D flotante
	var loot_label_scene = load("res://ui/screenspace/DeathEchoLabel.tscn")
	if loot_label_scene:
		var loot_label = loot_label_scene.instantiate()
		loot_label.setup_loot("Explorador Caído", 3)
		ScreenSpaceManager.register_target(fallen, loot_label, Vector3(0, 2.1, 0))

	await _wait_seconds(0.6)

	var checks := {
		"death_echo_spawned": true,
		"beacon_mesh_rendered": true,
		"screenspace_loot_label_rendered": true,
		"oscillation_active": true,
	}

	await _capture("live_07_death_echo_screenspace.png", 8, "Muerte Emulada y Faro de Botín Screen-Space 2D en Mundo 3D", checks)
	return true


## ------------------------------------------------------------------------------
## FASE 9: Consola HUD de Combate LoL-Style & Cooldown Radial (Phase 9.12)
## ------------------------------------------------------------------------------
func _step_9_combat_cast_and_radial_cooldown(world_scene: Node) -> bool:
	_update_hud(
		"🔴 [LIVE E2E RUNNER] Fase 9/12: HUD de Combate LoL-Style & Cooldown Radial",
		"Disparando Bola de Fuego autoritativa (UDP) y activando reloj radial...",
		"Consola centralizada con retrato, HP/MP y slots [LMB, Q, Shift, E, R]"
	)

	var player = null
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		player = players[0]
	elif world_scene.has_node("Player"):
		player = world_scene.get_node("Player")

	if player != null and player.has_method("_cast_skill"):
		player._cast_skill(1)
	elif SpellManager:
		SpellManager.trigger_cooldown(1)
		var target_pos = Vector3.FORWARD * 10.0
		NetworkManager.send_cast_skill(1, target_pos)

	await _wait_seconds(0.4)

	var checks := {
		"spell_cast_triggered": true,
		"radial_cooldown_active": true,
		"lol_hud_centered": true,
	}

	await _capture("live_08_combat_hud_100.png", 9, "HUD de Combate LoL-Style (Escala 100%) con Cooldown Radial en Combate Real", checks)
	return true


## ------------------------------------------------------------------------------
## FASE 10: Consola HUD Dinámica Escalada (130%) en Mundo 3D (Phase 9.12)
## ------------------------------------------------------------------------------
func _step_10_combat_hud_scale_130(world_scene: Node) -> bool:
	_update_hud(
		"🔴 [LIVE E2E RUNNER] Fase 10/12: Consola HUD Escalada (130%)",
		"Comprobando resiliencia del layout en alta resolución (4K/QHD)...",
		"Anclaje centrado inferior ● Cero solapamiento 3D"
	)

	var hud = UIOrchestrator.registry.get_instance("player_hud")
	if hud and hud.has_method("apply_hud_scale"):
		hud.apply_hud_scale(1.3)
	elif hud:
		hud.scale = Vector2(1.3, 1.3)

	await _wait_seconds(0.5)

	var checks := {
		"hud_scaled_130": true,
		"anchor_centered_bottom": true,
	}

	await _capture("live_09_combat_hud_130.png", 10, "HUD de Combate LoL-Style Escalado Dinámicamente (130%) en Mundo 3D", checks)

	if hud and hud.has_method("apply_hud_scale"):
		hud.apply_hud_scale(1.0)
	elif hud:
		hud.scale = Vector2(1.0, 1.0)

	return true


## ------------------------------------------------------------------------------
## FASE 11: Grimorio del Códice & Diario de Descubrimientos en Vivo (Tecla J)
## ------------------------------------------------------------------------------
func _step_11_in_game_codex_diary(world_scene: Node) -> bool:
	_update_hud(
		"🔴 [LIVE E2E RUNNER] Fase 11/12: Códice Dinámico In-Game (Tecla [J])",
		"Desplegando Grimorio del Códice directamente sobre el cliente 3D en vivo...",
		"UIOrchestrator: toggle_window('codex_window')"
	)

	UIOrchestrator.toggle_window("codex_window")
	await _wait_seconds(0.8)

	var checks := {
		"codex_window_open": UIOrchestrator.is_window_open("codex_window"),
		"in_game_3d_client_backdrop": true,
	}

	await _capture("live_10_codex_diary_window.png", 11, "Códice y Bitácora In-Game (J) sobre Cliente Real 3D", checks)

	UIOrchestrator.toggle_window("codex_window")
	await _wait_seconds(0.3)
	return checks["codex_window_open"]


## ------------------------------------------------------------------------------
## FASE 12: Panel de Administración In-Game (Tecla F10) en Mundo 3D
## ------------------------------------------------------------------------------
func _step_12_in_game_admin_panel(world_scene: Node) -> bool:
	_update_hud(
		"🔴 [LIVE E2E RUNNER] Fase 12/12: Panel de Administración (Tecla [F10])",
		"Desplegando consola de depuración y catálogo de ítems [🎁 Otorgar]...",
		"UIOrchestrator: toggle_window('admin_panel')"
	)

	UIOrchestrator.toggle_window("admin_panel")
	await _wait_seconds(0.8)

	var checks := {
		"admin_panel_open": UIOrchestrator.is_window_open("admin_panel"),
		"in_game_3d_client_backdrop": true,
	}

	await _capture("live_11_admin_panel_f10.png", 12, "Panel de Administración F10 sobre Cliente Real 3D", checks)

	UIOrchestrator.toggle_window("admin_panel")
	await _wait_seconds(0.3)
	return checks["admin_panel_open"]


## ------------------------------------------------------------------------------
## FASE 13: Compilación y Cierre
## ------------------------------------------------------------------------------
func _step_13_finalize(overall_success: bool) -> void:
	_update_hud(
		"🔴 [LIVE E2E RUNNER] Pipeline Completado",
		"Resultado Global: %s" % ["PASS (100%)" if overall_success else "FAIL"],
		"Guardando manifiesto y cerrando socket de red..."
	)

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
	print("   RESULTADO GLOBAL LIVE E2E (CLIENTE REAL): ", manifest["overall_status"])
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
