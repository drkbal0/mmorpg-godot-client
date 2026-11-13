extends Node

## World.gd - Root Controller for the MMO Game World
## Replaces legacy Main.gd, following UI Orchestration standards.

@onready var network_player_scene = preload("res://network_player.tscn")
@onready var player_scene = preload("res://player.tscn")
@onready var death_echo_scene = preload("res://world/DeathEcho.tscn")
@onready var hazard_scene = preload("res://ui/components/HazardIndicator/HazardIndicator.tscn")

var remote_players = {}
var remote_identities = {} # sid -> name
var remote_hp_cache = {} # sid -> {"hp": int, "max_hp": int}
var player_last_seen = {} # Track timeouts locally for ghosts
var local_player = null
var cached_local_hp = -1 # Cached HP from connect ACK (before player exists)
var cached_local_max_hp = -1
var active_projectiles = {} # projectile_id -> Node3D

var portal_zones: Dictionary = {} # sid -> {"pos": Vector3, "radius": float, "name": String, "target_zone": int}
var is_extracting: bool = false
var extraction_timer: float = 0.0
const EXTRACTION_DURATION: float = 10.0
var current_extracting_portal_sid: int = -1
var extraction_ui_layer: CanvasLayer = null
var extraction_bar: ProgressBar = null
var extraction_label: Label = null
var current_zone_id: int = 1
var debug_overlay_layer: CanvasLayer = null
var debug_overlay_label: Label = null
## F9 compacto: una sola línea de telemetría (XYZ | Zone | Yaw | FPS | Ping).
var debug_overlay_compact: bool = false
var portal_vortices: Array = [] # Rotating Black Hole component dicts

# --- Fase 9.7 (ADR 099/100): convoy de extracción móvil y reanimación contextual ---
const MobileExtractionConvoyScene = preload("res://world/MobileExtractionConvoy.tscn")
const ExtractionConvoyHUDScript = preload("res://ui/components/ExtractionHUD/ExtractionConvoyHUD.gd")
const ReviveProgressModalScript = preload("res://ui/modals/ReviveProgressModal.gd")
const RevivePlasmaBeamScript = preload("res://world/RevivePlasmaBeam3D.gd")
const ExtractionReviveCodec = preload("res://shared-core/ExtractionReviveCodec.gd")
var extraction_convoys: Dictionary = {} # beacon_id -> MobileExtractionConvoy
var convoy_hud: Control = null
var revive_modal: Control = null
var revive_beam: Node3D = null
var _convoy_latch: Dictionary = {} # beacon_id -> bool (histéresis 10 m / 11.5 m)
var _phase97_layer: CanvasLayer = null

# --- Fases 9.5 & 9.6: Pings Tácticos [G] y Visión Espectral de Ki [P] ---
const KiSpectralVisionScene = preload("res://ui/components/KiSpectralVision/KiSpectralVision.tscn")
const KiAuraProjectorScript = preload("res://ui/components/KiSpectralVision/KiAuraProjector.gd")
const TacticalPingWheelScene = preload("res://ui/components/TacticalPing/TacticalPingWheel.tscn")
const TacticalPingBeam3DScene = preload("res://world/TacticalPingBeam3D.gd")
const WorldNameplateScene = preload("res://ui/screenspace/WorldNameplate.tscn")

var ki_layer: CanvasLayer = null
var ki_vision: KiSpectralVision = null
var ki_projector: KiAuraProjector = null
var _ki_pulse_tween: Tween = null

var ping_layer: CanvasLayer = null
var ping_wheel: TacticalPingWheel = null
var overworld_archetypes: Array[Node3D] = []

func _ready():
	print("[World] Entry point reached. Initializing world state.")
	
	# 1. Connect Network Signals
	NetworkManager.server_connected.connect(_on_server_connected)
	NetworkManager.players_state_broadcast.connect(_on_players_state_broadcast)
	NetworkManager.remote_player_disconnected.connect(_on_remote_player_disconnected)
	NetworkManager.identity_received.connect(_on_identity_received)
	NetworkManager.kicked_from_server.connect(_on_kicked_from_server)
	NetworkManager.connection_interrupted.connect(_on_connection_interrupted)
	NetworkManager.connection_restored.connect(_on_connection_restored)
	NetworkManager.player_state_updated.connect(_on_player_state_updated)
	NetworkManager.static_entity_spawned.connect(_on_static_entity_spawned)
	NetworkManager.attributes_updated.connect(_on_attributes_updated)
	NetworkManager.skill_spawned.connect(_on_skill_spawned)
	NetworkManager.combat_event_received.connect(_on_combat_event_received)
	NetworkManager.echo_item_collected.connect(_on_echo_item_collected)
	NetworkManager.zone_transition_received.connect(_on_zone_transition_received)
	NetworkManager.extraction_beacon_received.connect(_on_extraction_beacon_received)
	NetworkManager.revive_sync_received.connect(_on_revive_sync_received)
	if NetworkManager.has_signal("tactical_ping_received"):
		NetworkManager.tactical_ping_received.connect(_on_tactical_ping_broadcast)
	
	AuthManager.profile_fetched.connect(_on_profile_loaded)
	
	# 2. UI Orchestration: Open HUD & Extraction UI
	_setup_hud()
	_setup_extraction_ui()
	_setup_debug_overlay()
	_build_map_topography()
	_setup_ping_and_ki_systems()
	_spawn_overworld_archetypes()
	add_to_group("hitbox_debug")
	
	# 3. Handle Spawn and Connection
	if AuthManager.selected_character_id != "":
		_on_profile_loaded()
	
	# Replay any identities and static entities cached before or during scene transition
	for sid in NetworkManager.cached_identities:
		var ident = NetworkManager.cached_identities[sid]
		_on_identity_received(sid, ident["name"], ident["hp_percent"], ident["max_hp"])
	for sid in NetworkManager.cached_static_entities:
		var e = NetworkManager.cached_static_entities[sid]
		_on_static_entity_spawned(e["sid"], e["type"], e["pos"], e["aggro"], e["attack"], e["max_hp"], e["name"])

	# Use ticket from AuthManager if provided by transition
	if AuthManager.world_ticket != "":
		print("[World] Connecting with transition ticket.")
		NetworkManager.connect_with_ticket(AuthManager.world_ticket)
		AuthManager.world_ticket = "" 
	elif AuthManager.selected_character_id != "" and not NetworkManager.udp_peer.is_socket_connected():
		print("[World] No transition ticket found. Auto-requesting ticket for character: ", AuthManager.selected_character_id)
		var t = await AuthManager.fetch_world_ticket()
		if t != "":
			NetworkManager.connect_with_ticket(t)
			AuthManager.world_ticket = ""
		else:
			push_error("[World] Failed to acquire world ticket for character: " + AuthManager.selected_character_id) 
	
	# Update Asset Management
	UpdateManager.asset_mounted.connect(_on_asset_mounted)

func _setup_hud():
	if UIOrchestrator:
		print("[World] Opening Player HUD via Orchestrator.")
		var hud = UIOrchestrator.open_window("player_hud")
		if hud and AuthManager.selected_character_name != "":
			hud.update_name(AuthManager.selected_character_name)
			hud.update_hp(100.0) # Initial default

func _on_profile_loaded():
	if local_player == null:
		print("[World] Spawning local player: ", AuthManager.selected_character_name)
		local_player = player_scene.instantiate()
		local_player.position = AuthManager.last_pos
		add_child(local_player)
		
		# Update HUD with final name if it was empty
		var hud = UIOrchestrator.registry.get_instance("player_hud")
		if hud:
			hud.update_name(AuthManager.selected_character_name)
			
		# Apply cached HP if connect ACK arrived before player was created
		if cached_local_hp >= 0:
			local_player.max_hp = cached_local_max_hp
			local_player.update_hp(cached_local_hp, -1, Vector3.ZERO)
			cached_local_hp = -1

func _on_server_connected(session_id: int, hp_percent: int, max_hp: int):
	print("[World] Server ACK received. Session ID: %d, HP: %d%%" % [session_id, hp_percent])
	if local_player and is_instance_valid(local_player):
		if "max_hp" in local_player:
			local_player.max_hp = max_hp
		if local_player.has_method("update_hp"):
			local_player.update_hp(hp_percent, -1, Vector3.ZERO)
	else:
		cached_local_hp = hp_percent
		cached_local_max_hp = max_hp
	
	# Sync HUD
	var hud = UIOrchestrator.registry.get_instance("player_hud")
	if hud:
		hud.update_hp(hp_percent)

func _on_players_state_broadcast(players_data: Array):
	var current_time = Time.get_ticks_msec()
	for pd in players_data:
		var sid = pd["sid"]
		var pos = pd["pos"]
		
		if sid == NetworkManager.my_session_id:
			continue
			
		if not remote_players.has(sid):
			# SID Range Check: 0x80000000+ are usually static entities. 
			# We don't want to spawn a default capsule player for them via position broadcast.
			if sid < 0x80000000:
				_spawn_remote_player(sid, pos)
		else:
			var entity = remote_players[sid]
			if entity.has_method("add_state"):
				entity.add_state(pos)
			elif "position" in entity:
				entity.position = pos
		player_last_seen[sid] = current_time

func _spawn_remote_player(sid: int, pos: Vector3):
	var new_player = network_player_scene.instantiate()
	add_child(new_player)
	new_player.position = pos
	var p_name = remote_identities.get(sid, "Player")
	new_player.update_nameplate(p_name, sid)
	new_player.add_state(pos)
	remote_players[sid] = new_player
	
	if remote_hp_cache.has(sid):
		var cached = remote_hp_cache[sid]
		new_player.max_hp = cached["max_hp"]
		new_player.update_hp(cached["hp"], -1, Vector3.ZERO)
		remote_hp_cache.erase(sid)

func _on_remote_player_disconnected(sid: int):
	remove_remote_player(sid)

func _on_static_entity_spawned(sid: int, type: int, pos: Vector3, aggro: float, attack: float, max_hp: float, p_name: String):
	if remote_players.has(sid): return
	
	print("[World] Spawning Static Type %d: %s at %s" % [type, p_name, str(pos)])
	
	if type == 0: # DeathEcho
		var echo = death_echo_scene.instantiate()
		add_child(echo)
		echo.position = pos
		echo.setup(sid, p_name)
		remote_players[sid] = echo
		
		# Ensure DeathEcho doesn't show standard metadata UI (HP bars)
		if echo.has_node("WorldHPBar"):
			echo.get_node("WorldHPBar").visible = false
	elif type == 2: # Hazard Indicator
		var h = hazard_scene.instantiate()
		add_child(h)
		h.position = pos
		h.scale = Vector3(aggro, 1.0, aggro) # Using aggro as radius for hazards
		var is_pulsing = (attack > 0.5) or (pos.x < 0.0)
		var server_offset = max_hp
		if h.has_method("setup"):
			h.setup(server_offset, is_pulsing)
		remote_players[sid] = h
	elif type == 3: # Hostile NPC
		var n = network_player_scene.instantiate()
		add_child(n)
		n.position = pos
		if n.has_method("update_nameplate"):
			n.update_nameplate(p_name, sid)
		if n.has_method("setup_attributes"):
			n.setup_attributes(aggro, attack, max_hp)
		# Tint red for hostile
		var mesh = n.get_node_or_null("MeshInstance3D")
		if mesh:
			var base_mat = mesh.get_active_material(0)
			var mat = base_mat.duplicate() if base_mat else StandardMaterial3D.new()
			mat.albedo_color = Color(1, 0.4, 0.4)
			mesh.set_surface_override_material(0, mat)
		remote_players[sid] = n
	elif type == 4: # Neutral NPC
		var n = network_player_scene.instantiate()
		add_child(n)
		n.position = pos
		if n.has_method("update_nameplate"):
			n.update_nameplate(p_name, sid)
		if n.has_method("setup_attributes"):
			n.setup_attributes(aggro, attack, max_hp)
		# Tint blue/green for neutral
		var mesh = n.get_node_or_null("MeshInstance3D")
		if mesh:
			var base_mat = mesh.get_active_material(0)
			var mat = base_mat.duplicate() if base_mat else StandardMaterial3D.new()
			mat.albedo_color = Color(0.4, 0.7, 1.0) # Light blue
			mesh.set_surface_override_material(0, mat)
		remote_players[sid] = n
	elif type == 5: # Portal / Extraction Zone -> Astrofísica Agujero Negro / Vórtice Gravitacional
		var portal = Node3D.new()
		portal.name = "PortalZone_%d" % sid
		portal.position = pos
		add_child(portal)

		portal_zones[sid] = {
			"pos": pos,
			"radius": aggro,
			"name": p_name,
			"target_zone": int(attack)
		}

		# 1. EVENT HORIZON (Horizonte de Sucesos) - Núcleo de absorción absoluta (Negro puro no reflectivo)
		var horizon = MeshInstance3D.new()
		var h_cyl = CylinderMesh.new()
		var horizon_radius = aggro * 0.42
		h_cyl.top_radius = horizon_radius
		h_cyl.bottom_radius = horizon_radius
		h_cyl.height = 0.05
		horizon.mesh = h_cyl
		var h_mat = StandardMaterial3D.new()
		h_mat.albedo_color = Color(0.005, 0.005, 0.008, 1.0) # Vacío gravitacional absoluto
		h_mat.roughness = 1.0
		h_mat.metallic = 0.0
		h_mat.emission_enabled = false
		horizon.set_surface_override_material(0, h_mat)
		horizon.position = Vector3(0, 0.02, 0)
		portal.add_child(horizon)

		# 2. PHOTON SPHERE RING (Anillo de Fotones) - Límite hiper-brillante donde la luz orbita el agujero
		var photon_ring = MeshInstance3D.new()
		var p_torus = TorusMesh.new()
		p_torus.inner_radius = max(0.1, horizon_radius - 0.08)
		p_torus.outer_radius = horizon_radius + 0.08
		photon_ring.mesh = p_torus
		var p_mat = StandardMaterial3D.new()
		p_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		p_mat.albedo_color = Color(0.9, 0.98, 1.0, 0.95) # Luz estelar atrapada
		p_mat.emission_enabled = true
		p_mat.emission = Color(0.4, 0.95, 1.0)
		p_mat.emission_energy_multiplier = 2.6
		photon_ring.set_surface_override_material(0, p_mat)
		photon_ring.position = Vector3(0, 0.04, 0)
		portal.add_child(photon_ring)

		# 3. ACCRETION DISK (Disco de Acreción en Espiral) - Plasma cósmico que gira hacia el centro
		var accretion_disk = MeshInstance3D.new()
		var a_torus = TorusMesh.new()
		a_torus.inner_radius = horizon_radius + 0.05
		a_torus.outer_radius = aggro * 0.85
		accretion_disk.mesh = a_torus
		var a_mat = StandardMaterial3D.new()
		a_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		a_mat.albedo_color = Color(0.65, 0.18, 0.95, 0.65) # Plasma violeta cósmico
		a_mat.emission_enabled = true
		a_mat.emission = Color(0.75, 0.22, 1.0)
		a_mat.emission_energy_multiplier = 1.5
		accretion_disk.set_surface_override_material(0, a_mat)
		accretion_disk.position = Vector3(0, 0.03, 0)
		portal.add_child(accretion_disk)

		# 4. GRAVITATIONAL LENSING OUTER WARP (Anillo de Deformación Gravitacional Exterior)
		var outer_warp = MeshInstance3D.new()
		var w_torus = TorusMesh.new()
		w_torus.inner_radius = max(0.1, aggro - 0.22)
		w_torus.outer_radius = aggro
		outer_warp.mesh = w_torus
		var w_mat = StandardMaterial3D.new()
		w_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		w_mat.albedo_color = Color(0.2, 0.85, 1.0, 0.8) # Borde gravitacional cian
		w_mat.emission_enabled = true
		w_mat.emission = Color(0.25, 0.88, 1.0)
		w_mat.emission_energy_multiplier = 1.8
		outer_warp.set_surface_override_material(0, w_mat)
		outer_warp.position = Vector3(0, 0.05, 0)
		portal.add_child(outer_warp)

		# 5. Registrar componentes para rotación orbital viva en _process
		portal_vortices.append({
			"portal": portal,
			"photon_ring": photon_ring,
			"accretion_disk": accretion_disk,
			"outer_warp": outer_warp
		})

		# 6. Floating 3D Label - High-contrast, no_depth_test, bold outline, enhanced pixel_size
		var label = Label3D.new()
		label.text = p_name
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.render_priority = 35
		label.modulate = Color(1.0, 1.0, 1.0) # Pure crisp white
		label.font_size = 56
		label.outline_size = 18
		label.outline_modulate = Color.BLACK
		label.pixel_size = 0.0095 # Physically larger in 3D world space
		label.shaded = false
		label.position = Vector3(0, 2.7, 0)
		portal.add_child(label)

		remote_players[sid] = portal
	player_last_seen[sid] = Time.get_ticks_msec()

func _on_attributes_updated(sid: int, aggro: float, attack: float, speed: float, max_hp: float):
	if remote_players.has(sid):
		var n = remote_players[sid]
		if n.has_method("update_attributes"):
			n.update_attributes(aggro, attack, speed, max_hp)

func _on_player_state_updated(sid: int, hp_percent: int, source_id: int):
	var source_pos = Vector3.ZERO
	if source_id == NetworkManager.my_session_id:
		if local_player and is_instance_valid(local_player): source_pos = local_player.position
	elif remote_players.has(source_id) and is_instance_valid(remote_players[source_id]):
		source_pos = remote_players[source_id].position
		
	if sid == NetworkManager.my_session_id:
		if is_extracting and local_player and is_instance_valid(local_player) and hp_percent < local_player.current_hp:
			_interrupt_extraction_by_damage()
		if local_player and is_instance_valid(local_player):
			local_player.update_hp(hp_percent, source_id, source_pos)
		var hud = UIOrchestrator.registry.get_instance("player_hud")
		if hud: hud.update_hp(hp_percent)
	elif remote_players.has(sid) and is_instance_valid(remote_players[sid]):
		if remote_players[sid].has_method("update_hp"):
			remote_players[sid].update_hp(hp_percent, source_id, source_pos)

func _on_kicked_from_server(reason: String):
	# Use UIOrchestrator for popups if possible, but keep simple for now
	var dialog = AcceptDialog.new()
	if reason == "character_death":
		dialog.title = "HAS MUERTO"
		dialog.dialog_text = "Has sucumbido ante los peligros del mundo.\nRegresarás al refugio."
		dialog.get_ok_button().text = "Regresar al Refugio"
		
		# Immediately hide local player to avoid "ghost" white model
		if local_player:
			local_player.visible = false
			local_player.queue_free()
			local_player = null
	else:
		dialog.title = "Desconectado"
		dialog.dialog_text = reason
	
	add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(func():
		if reason == "character_death":
			SceneManager.change_scene_async("res://ui/windows/ShelterWindow/ShelterLobby.tscn")
		else:
			SceneManager.change_scene_async("res://login_screen.tscn")
	)


func remove_remote_player(sid: int):
	if remote_players.has(sid):
		remote_players[sid].queue_free()
		remote_players.erase(sid)
	var alt_sid = sid ^ 0x20000000
	if remote_players.has(alt_sid):
		remote_players[alt_sid].queue_free()
		remote_players.erase(alt_sid)
	player_last_seen.erase(sid)
	player_last_seen.erase(alt_sid)
	remote_identities.erase(sid)
	remote_identities.erase(alt_sid)

func despawn_death_echo_by_id(p_echo_id: String):
	for sid in remote_players.keys():
		var node = remote_players[sid]
		if is_instance_valid(node) and "echo_id" in node and node.echo_id == p_echo_id:
			print("[World] Despawning empty DeathEcho with ID: ", p_echo_id)
			remove_remote_player(sid)
			break

func _on_echo_item_collected(echo_id: String, _item_id: String, is_empty: bool = false):
	if is_empty:
		despawn_death_echo_by_id(echo_id)

func _on_identity_received(sid: int, p_name: String, hp_percent: int, max_hp: int):
	remote_identities[sid] = p_name
	remote_hp_cache[sid] = {"hp": hp_percent, "max_hp": max_hp}
	if remote_players.has(sid):
		if remote_players[sid].has_method("update_nameplate"):
			remote_players[sid].update_nameplate(p_name, sid)
		if remote_players[sid].has_method("update_hp"):
			remote_players[sid].max_hp = max_hp
			remote_players[sid].update_hp(hp_percent, -1, Vector3.ZERO)

func _on_asset_mounted(asset_id: String):
	print("[World] Asset Mounted: ", asset_id)

func _on_connection_interrupted():
	print("[World] Connection Lost.")

func _on_connection_restored():
	print("[World] Connection Restored.")

func _unhandled_input(event):
	# La rueda de Pings Tácticos [G] se enruta de forma centralizada en UIInputRouter
	# (open/confirm/cancel_tactical_ping_wheel).
	if event is InputEventKey and not event.is_echo():
		if event.keycode == KEY_P and event.pressed:
			trigger_ki_spectral_pulse()
			get_viewport().set_input_as_handled()
			return

	if UIOrchestrator.is_mouse_over_ui():
		return
		
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_try_select_target()

func _try_select_target():
	var camera = get_viewport().get_camera_3d()
	if !camera: return
	
	var mouse_pos = get_viewport().get_visible_rect().size / 2.0 if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else get_viewport().get_mouse_position()
	var from = camera.project_ray_origin(mouse_pos)
	var to = from + camera.project_ray_normal(mouse_pos) * 1000.0
	
	var space_state = get_viewport().get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = true
	query.collide_with_bodies = false # Ignore physics bodies (Layers 1-3)
	query.collision_mask = 48 # Layer 5 (16) + Layer 6 (32) = 48
	if local_player and is_instance_valid(local_player):
		var excludes: Array[RID] = [local_player.get_rid()]
		var area = local_player.get_node_or_null("Area3D")
		if area and area is CollisionObject3D:
			excludes.append(area.get_rid())
		query.exclude = excludes
	var result = space_state.intersect_ray(query)
	
	if result:
		var hit_node = result.collider
		print("[Targeting] Hit: ", hit_node.name, " (", hit_node.get_parent().name, ")")
		# Search upwards for sid
		var node = hit_node
		while node != null and node != self:
			if "sid" in node:
				TargetManager.select_target(node.sid)
				return
			node = node.get_parent()
			
	# If clicked on nothing or non-entity, clear target
	TargetManager.clear_target()

func _exit_tree():
	TargetManager.clear_target()

func _on_skill_spawned(projectile_id: int, caster_sid: int, spell_id: int, origin: Vector3, dir: Vector2, speed: float, _server_tick: int):
	match spell_id:
		1: # Fireball ballistic projectile
			_spawn_fireball_projectile(projectile_id, origin, dir, speed)
		2: # Blink Dash (Movement ability: quick start ring, no projectile)
			_spawn_dash_trail(origin)
		3: # Hitscan Instant Beam
			_spawn_hitscan_tracer(origin, dir)
		4: # Defensive Barrier (E)
			_spawn_barrier_vfx(projectile_id, caster_sid, origin)
		5: # Impacto Cósmico / Meteor Strike (R)
			_spawn_meteor_vfx(projectile_id, origin)
		_:
			_spawn_fireball_projectile(projectile_id, origin, dir, speed)

func _spawn_fireball_projectile(projectile_id: int, origin: Vector3, dir: Vector2, speed: float):
	var p = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.35
	sphere.height = 0.7
	p.mesh = sphere
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.45, 0.1) # Fireball orange
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.35, 0.0)
	mat.emission_energy_multiplier = 4.0
	p.set_surface_override_material(0, mat)
	
	p.position = origin
	add_child(p)
	
	var move_speed = max(speed, 5.0)
	var move_dir = Vector3(dir.x, 0, dir.y).normalized()
	if move_dir.length_squared() < 0.001:
		move_dir = Vector3.FORWARD
	var max_range = 25.0
	var nominal_target = origin + move_dir * max_range
	var target_pos = nominal_target
	var hit_obstacle = false
	
	# Raycast contra terreno y obstáculos estáticos del mundo (Cubo, Rampa, Muro LoS)
	var vp = get_viewport()
	var w3d = vp.find_world_3d() if vp else null
	var space_state = w3d.direct_space_state if w3d else null
	if space_state:
		var ray_query = PhysicsRayQueryParameters3D.create(origin, nominal_target)
		ray_query.collide_with_bodies = true
		ray_query.collide_with_areas = false
		var hit_dict = space_state.intersect_ray(ray_query)
		if not hit_dict.is_empty():
			target_pos = hit_dict.position
			hit_obstacle = true
	
	var travel_dist = origin.distance_to(target_pos)
	var duration = max(travel_dist / move_speed, 0.05)
	
	var tween = create_tween()
	tween.tween_property(p, "position", target_pos, duration)
	tween.tween_callback(func():
		active_projectiles.erase(projectile_id)
		if is_instance_valid(p): p.queue_free()
		_spawn_fireball_impact_blast(target_pos, hit_obstacle)
	)
	
	active_projectiles[projectile_id] = p

func _spawn_fireball_impact_blast(pos: Vector3, hit_obstacle: bool):
	var blast = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.3
	sphere.height = 0.6
	blast.mesh = sphere
	
	var mat = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.5, 0.1, 0.9)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.4, 0.0) if not hit_obstacle else Color(1.0, 0.8, 0.2)
	mat.emission_energy_multiplier = 5.0 if hit_obstacle else 3.0
	blast.set_surface_override_material(0, mat)
	
	blast.position = pos
	add_child(blast)
	
	var tween = create_tween()
	tween.set_parallel(true)
	var target_scale = Vector3(2.4, 2.4, 2.4) if hit_obstacle else Vector3(1.5, 1.5, 1.5)
	tween.tween_property(blast, "scale", target_scale, 0.24).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.24)
	tween.chain().tween_callback(func():
		if is_instance_valid(blast):
			blast.queue_free()
	)

func _spawn_dash_trail(origin: Vector3):
	var ring = MeshInstance3D.new()
	var torus = TorusMesh.new()
	torus.inner_radius = 0.3
	torus.outer_radius = 0.6
	ring.mesh = torus
	
	var mat = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.2, 0.8, 1.0, 0.8)
	mat.emission_enabled = true
	mat.emission = Color(0.0, 0.9, 1.0)
	mat.emission_energy_multiplier = 4.0
	ring.set_surface_override_material(0, mat)
	
	ring.position = origin + Vector3(0, 0.2, 0)
	add_child(ring)
	
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(ring, "scale", Vector3(2.0, 0.2, 2.0), 0.25)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.25)
	tween.chain().tween_callback(func():
		if is_instance_valid(ring): ring.queue_free()
	)

func _spawn_barrier_vfx(projectile_id: int, caster_sid: int, origin: Vector3):
	var dome = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 1.6
	sphere.height = 3.2
	dome.mesh = sphere
	
	var mat = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(0.1, 0.7, 1.0, 0.35)
	mat.emission_enabled = true
	mat.emission = Color(0.2, 0.8, 1.0)
	mat.emission_energy_multiplier = 2.5
	mat.roughness = 0.1
	dome.set_surface_override_material(0, mat)
	
	if local_player and is_instance_valid(local_player) and caster_sid == NetworkManager.my_session_id:
		local_player.add_child(dome)
		dome.position = Vector3(0, 1.0, 0)
	elif remote_players.has(caster_sid) and is_instance_valid(remote_players[caster_sid]):
		remote_players[caster_sid].add_child(dome)
		dome.position = Vector3(0, 1.0, 0)
	else:
		dome.position = origin + Vector3(0, 1.0, 0)
		add_child(dome)
	
	dome.scale = Vector3(0.2, 0.2, 0.2)
	var tween = create_tween()
	tween.tween_property(dome, "scale", Vector3.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(3.5)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.4)
	tween.parallel().tween_property(dome, "scale", Vector3(1.3, 1.3, 1.3), 0.4)
	tween.chain().tween_callback(func():
		active_projectiles.erase(projectile_id)
		if is_instance_valid(dome): dome.queue_free()
	)
	
	active_projectiles[projectile_id] = dome

func _spawn_meteor_vfx(projectile_id: int, target_ground: Vector3):
	var meteor = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.9
	sphere.height = 1.8
	meteor.mesh = sphere
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.2, 0.05)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.4, 0.0)
	mat.emission_energy_multiplier = 6.0
	meteor.set_surface_override_material(0, mat)
	
	var start_pos = target_ground + Vector3(0, 22.0, 0)
	meteor.position = start_pos
	add_child(meteor)
	
	var tween = create_tween()
	tween.tween_property(meteor, "position", target_ground, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(func():
		active_projectiles.erase(projectile_id)
		if is_instance_valid(meteor): meteor.queue_free()
		_spawn_meteor_impact_blast(target_ground)
	)
	
	active_projectiles[projectile_id] = meteor

func _spawn_meteor_impact_blast(ground_pos: Vector3):
	var blast = MeshInstance3D.new()
	var b_sphere = SphereMesh.new()
	b_sphere.radius = 2.0
	b_sphere.height = 4.0
	blast.mesh = b_sphere
	
	var b_mat = StandardMaterial3D.new()
	b_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	b_mat.albedo_color = Color(1.0, 0.5, 0.1, 0.9)
	b_mat.emission_enabled = true
	b_mat.emission = Color(1.0, 0.6, 0.1)
	b_mat.emission_energy_multiplier = 8.0
	blast.set_surface_override_material(0, b_mat)
	blast.position = ground_pos + Vector3(0, 0.5, 0)
	add_child(blast)
	
	var shockwave = MeshInstance3D.new()
	var torus = TorusMesh.new()
	torus.inner_radius = 2.8
	torus.outer_radius = 3.5
	shockwave.mesh = torus
	
	var s_mat = StandardMaterial3D.new()
	s_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	s_mat.albedo_color = Color(1.0, 0.3, 0.0, 0.8)
	s_mat.emission_enabled = true
	s_mat.emission = Color(1.0, 0.2, 0.0)
	s_mat.emission_energy_multiplier = 6.0
	shockwave.set_surface_override_material(0, s_mat)
	shockwave.position = ground_pos + Vector3(0, 0.1, 0)
	shockwave.scale = Vector3(0.2, 0.2, 0.2)
	add_child(shockwave)
	
	var t = create_tween()
	t.set_parallel(true)
	t.tween_property(blast, "scale", Vector3(1.8, 1.8, 1.8), 0.3)
	t.tween_property(b_mat, "albedo_color:a", 0.0, 0.3)
	t.tween_property(shockwave, "scale", Vector3(1.2, 1.0, 1.2), 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(s_mat, "albedo_color:a", 0.0, 0.4)
	t.chain().tween_callback(func():
		if is_instance_valid(blast): blast.queue_free()
		if is_instance_valid(shockwave): shockwave.queue_free()
	)

func _spawn_hitscan_tracer(origin: Vector3, dir: Vector2):
	var max_dist = 45.0
	var beam_dir = Vector3(dir.x, 0.0, dir.y).normalized()
	if beam_dir.length_squared() < 0.001:
		beam_dir = Vector3.FORWARD
	var beam_end = origin + beam_dir * max_dist
	var dist = origin.distance_to(beam_end)
	if dist < 0.1: return
	
	var mid = (origin + beam_end) * 0.5
	
	var beam = MeshInstance3D.new()
	var cyl = CylinderMesh.new()
	cyl.top_radius = 0.03
	cyl.bottom_radius = 0.03
	cyl.height = dist
	beam.mesh = cyl
	
	var mat = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.1, 0.85, 1.0, 0.95) # High-energy Cyan laser
	mat.emission_enabled = true
	mat.emission = Color(0.2, 0.9, 1.0)
	mat.emission_energy_multiplier = 7.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam.set_surface_override_material(0, mat)
	
	add_child(beam)
	
	var up_axis = Vector3.UP
	if abs(beam_dir.dot(up_axis)) > 0.99:
		up_axis = Vector3.FORWARD
	beam.look_at_from_position(mid, mid + beam_dir, up_axis)
	beam.rotate_object_local(Vector3.RIGHT, deg_to_rad(-90))
	
	# Muzzle spark at origin
	var flash = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.12
	sphere.height = 0.24
	flash.mesh = sphere
	flash.set_surface_override_material(0, mat)
	flash.position = origin
	add_child(flash)
	
	var tween = create_tween()
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.08)
	tween.parallel().tween_property(beam, "scale", Vector3(0.05, 1.0, 0.05), 0.08)
	tween.parallel().tween_property(flash, "scale", Vector3.ZERO, 0.05)
	tween.tween_callback(func():
		if is_instance_valid(beam): beam.queue_free()
		if is_instance_valid(flash): flash.queue_free()
	)

func _on_combat_event_received(source_sid: int, target_sid: int, spell_id: int, damage: float, is_crit: bool, target_hp_percent: int):
	# Si es Impacto Cósmico (Meteoro - Spell 5), sincronizar daño con el impacto del meteoro (0.45s)
	if spell_id == 5:
		await get_tree().create_timer(0.45).timeout

	print("[Combat] Hit detected on SID %d: -%.1f dmg (HP: %d%%)" % [target_sid, damage, target_hp_percent])
	
	var source_pos = Vector3.ZERO
	if remote_players.has(source_sid) and is_instance_valid(remote_players[source_sid]):
		source_pos = remote_players[source_sid].global_position
	elif local_player and is_instance_valid(local_player) and source_sid == NetworkManager.my_session_id:
		source_pos = local_player.global_position

	var target_node = null
	if local_player and is_instance_valid(local_player) and target_sid == NetworkManager.my_session_id:
		target_node = local_player
		local_player.update_hp(target_hp_percent, source_sid, source_pos)
		if is_extracting and damage > 0.0:
			_interrupt_extraction_by_damage()
	elif remote_players.has(target_sid) and is_instance_valid(remote_players[target_sid]):
		target_node = remote_players[target_sid]
		if target_node.has_method("update_hp"):
			target_node.update_hp(target_hp_percent, source_sid, source_pos)
			
	var spawn_pos = Vector3(0, 2, 8)
	if is_instance_valid(target_node):
		spawn_pos = target_node.global_position + Vector3(0, 2.0, 0)
	elif source_pos != Vector3.ZERO:
		spawn_pos = source_pos + Vector3(0, 2.0, 3.0)
	_spawn_floating_damage(spawn_pos, damage, is_crit)

func _spawn_floating_damage(pos: Vector3, damage: float, is_crit: bool):
	if pos == Vector3.ZERO: return
	var label = Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.render_priority = 30
	label.outline_size = 14
	label.outline_modulate = Color.BLACK

	if damage <= 0.0:
		label.text = "¡BLOQUEADO!"
		label.modulate = Color(0.2, 0.95, 1.0) # Electric cyan
		label.font_size = 48
	else:
		label.text = "-%.0f" % damage
		label.modulate = Color(1.0, 0.85, 0.1) if is_crit else Color(1.0, 0.35, 0.35)
		label.font_size = 60 if is_crit else 46

	label.position = pos + Vector3(randf_range(-0.3, 0.3), randf_range(0.0, 0.3), randf_range(-0.3, 0.3))
	add_child(label)
	
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y + 1.4, 0.85).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.85).set_delay(0.25)
	tween.chain().tween_callback(func():
		if is_instance_valid(label): label.queue_free()
	)


func _process(delta: float) -> void:
	_process_portal_extraction(delta)
	_update_debug_overlay()
	_process_portal_vortices(delta)

func set_hitbox_debug_visible(is_visible: bool) -> void:
	if debug_overlay_layer:
		debug_overlay_layer.visible = is_visible

func _setup_extraction_ui() -> void:
	extraction_ui_layer = CanvasLayer.new()
	extraction_ui_layer.layer = 95
	add_child(extraction_ui_layer)
	
	var center = CenterContainer.new()
	center.anchors_preset = Control.PRESET_TOP_WIDE
	center.offset_top = 70
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	extraction_ui_layer.add_child(center)
	
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(380, 65)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.08, 0.16, 0.92)
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.border_color = Color(0.25, 0.85, 1.0, 0.95)
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)
	
	extraction_label = Label.new()
	extraction_label.text = "Teletransportando..."
	extraction_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	extraction_label.add_theme_font_size_override("font_size", 15)
	extraction_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	vbox.add_child(extraction_label)
	
	extraction_bar = ProgressBar.new()
	extraction_bar.custom_minimum_size = Vector2(340, 14)
	extraction_bar.max_value = EXTRACTION_DURATION
	extraction_bar.show_percentage = false
	var bar_fill = StyleBoxFlat.new()
	bar_fill.bg_color = Color(0.2, 0.8, 1.0)
	bar_fill.corner_radius_top_left = 4
	bar_fill.corner_radius_top_right = 4
	bar_fill.corner_radius_bottom_left = 4
	bar_fill.corner_radius_bottom_right = 4
	extraction_bar.add_theme_stylebox_override("fill", bar_fill)
	vbox.add_child(extraction_bar)
	
	extraction_ui_layer.visible = false

func _process_portal_extraction(delta: float) -> void:
	if not local_player or not is_instance_valid(local_player): return
	var p_pos = local_player.global_position
	
	var inside_portal_sid = -1
	var inside_portal_data = null
	
	for sid in portal_zones.keys():
		var pdata = portal_zones[sid]
		var dist = Vector2(p_pos.x - pdata["pos"].x, p_pos.z - pdata["pos"].z).length()
		if dist <= pdata["radius"]:
			inside_portal_sid = sid
			inside_portal_data = pdata
			break
			
	if inside_portal_sid != -1:
		if not is_extracting or current_extracting_portal_sid != inside_portal_sid:
			is_extracting = true
			current_extracting_portal_sid = inside_portal_sid
			extraction_timer = 0.0
			if extraction_ui_layer:
				extraction_ui_layer.visible = true
				extraction_bar.value = 0.0
				extraction_label.text = "Teletransportando a %s... (10s)" % inside_portal_data["name"]
				extraction_label.modulate = Color(1, 1, 1)
		else:
			extraction_timer += delta
			var remaining = max(0.0, EXTRACTION_DURATION - extraction_timer)
			if extraction_bar:
				extraction_bar.value = extraction_timer
			if extraction_label:
				extraction_label.text = "Teletransportando a %s... (%.1fs)" % [inside_portal_data["name"], remaining]
	else:
		if is_extracting:
			_cancel_extraction("Teletransporte cancelado (saliste de la zona)")

func _interrupt_extraction_by_damage() -> void:
	if not is_extracting: return
	extraction_timer = 0.0
	if extraction_bar:
		extraction_bar.value = 0.0
		var tw = create_tween()
		tw.tween_property(extraction_bar, "modulate", Color(2.5, 0.2, 0.2), 0.1)
		tw.tween_property(extraction_bar, "modulate", Color(1.0, 1.0, 1.0), 0.25)
	if extraction_label:
		extraction_label.text = "¡DAÑO RECIBIDO! Canalizado Reiniciado (10.0s)"
		extraction_label.modulate = Color(1.0, 0.2, 0.2)

func _cancel_extraction(msg: String = "") -> void:
	if not is_extracting and not (extraction_ui_layer and extraction_ui_layer.visible): return
	is_extracting = false
	current_extracting_portal_sid = -1
	extraction_timer = 0.0
	if extraction_ui_layer:
		if msg != "":
			extraction_label.text = msg
			extraction_label.modulate = Color(1.0, 0.35, 0.35) if "interrumpido" in msg.to_lower() else Color(1.0, 0.85, 0.2)
			var tw = create_tween()
			tw.tween_interval(1.2)
			tw.tween_callback(func():
				if not is_extracting and extraction_ui_layer:
					extraction_ui_layer.visible = false
			)
		else:
			extraction_ui_layer.visible = false

func _on_zone_transition_received(new_zone_id: int, target_pos: Vector3) -> void:
	print("[World] ZONE TRANSITION to Zone %d at %s" % [new_zone_id, str(target_pos)])
	current_zone_id = new_zone_id
	
	# 1. Clean up old zone entities so no ghosts remain
	for sid in remote_players.keys():
		var node = remote_players[sid]
		if is_instance_valid(node):
			node.queue_free()
	remote_players.clear()
	player_last_seen.clear()
	remote_identities.clear()
	remote_hp_cache.clear()
	portal_zones.clear()
	portal_vortices.clear()
	_cancel_extraction("¡Teletransporte Exitoso!")
	
	# 2. Position local player
	if local_player and is_instance_valid(local_player):
		local_player.position = target_pos
		if local_player.has_method("setup_camera"):
			local_player.setup_camera()
			
	# 3. Flash visual transition banner
	_show_zone_transfer_flash(new_zone_id)

func _show_zone_transfer_flash(new_zone_id: int) -> void:
	var flash_layer = CanvasLayer.new()
	flash_layer.layer = 120
	add_child(flash_layer)
	
	var rect = ColorRect.new()
	rect.anchors_preset = Control.PRESET_FULL_RECT
	rect.color = Color(0.2, 0.8, 1.0, 0.6)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash_layer.add_child(rect)
	
	var banner = Label.new()
	banner.anchors_preset = Control.PRESET_CENTER
	banner.text = "HAS ENTRADO A: CRIPTA ANCESTRAL (ZONA 2)" if new_zone_id == 2 else "HAS RETORNADO A: OVERWORLD (ZONA 1)"
	banner.add_theme_font_size_override("font_size", 28)
	banner.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	flash_layer.add_child(banner)
	
	var tw = create_tween()
	tw.set_parallel(true)
	tw.tween_property(rect, "color:a", 0.0, 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(banner, "modulate:a", 0.0, 1.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT).set_delay(0.6)
	tw.chain().tween_callback(func():
		flash_layer.queue_free()
	)


func _setup_debug_overlay() -> void:
	debug_overlay_layer = CanvasLayer.new()
	debug_overlay_layer.layer = 110 # Above standard HUD
	add_child(debug_overlay_layer)
	
	var margin = MarginContainer.new()
	margin.anchors_preset = Control.PRESET_TOP_RIGHT
	margin.anchor_left = 1.0
	margin.anchor_right = 1.0
	margin.offset_left = -340
	margin.grow_horizontal = Control.GROW_DIRECTION_BEGIN # la línea de telemetría crece hacia la izquierda
	margin.offset_top = 15
	margin.offset_right = -15
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	debug_overlay_layer.add_child(margin)
	
	var panel = PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.03, 0.05, 0.78)
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = Color(0.2, 0.85, 0.35, 0.85) # Minecraft F3 / Matrix Green style
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	panel.add_theme_stylebox_override("panel", sb)
	margin.add_child(panel)
	
	var inner = MarginContainer.new()
	inner.add_theme_constant_override("margin_left", 10)
	inner.add_theme_constant_override("margin_right", 10)
	inner.add_theme_constant_override("margin_top", 8)
	inner.add_theme_constant_override("margin_bottom", 8)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(inner)
	
	debug_overlay_label = Label.new()
	debug_overlay_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	debug_overlay_label.add_theme_font_size_override("font_size", 12)
	debug_overlay_label.add_theme_color_override("font_color", Color(0.85, 1.0, 0.85))
	debug_overlay_label.text = "[DEBUG F9] Coordenadas y Estado"
	inner.add_child(debug_overlay_label)
	
	debug_overlay_layer.visible = false

func _update_debug_overlay() -> void:
	if not debug_overlay_layer or not debug_overlay_layer.visible or not debug_overlay_label:
		return
		
	var px = 0.0
	var py = 0.0
	var pz = 0.0
	var yaw_deg = 0.0
	var facing = "Sur (Z+)"
	
	if local_player and is_instance_valid(local_player):
		px = local_player.global_position.x
		py = local_player.global_position.y
		pz = local_player.global_position.z
		yaw_deg = rad_to_deg(local_player.rotation.y)
		
		var norm_yaw = fposmod(yaw_deg + 180.0, 360.0) - 180.0
		if abs(norm_yaw) < 45.0:
			facing = "Norte (Z-)"
		elif norm_yaw >= 45.0 and norm_yaw < 135.0:
			facing = "Este (X+)"
		elif norm_yaw <= -45.0 and norm_yaw > -135.0:
			facing = "Oeste (X-)"
		else:
			facing = "Sur (Z+)"
			
	var zone_str = "Overworld (Zona 1)" if current_zone_id == 1 else ("Cripta Ancestral (Zona 2)" if current_zone_id == 2 else "Zona %d" % current_zone_id)
	var fps = Engine.get_frames_per_second()
	var entities_count = remote_players.size() + 1
	var sid = NetworkManager.my_session_id
	
	var net_prof = GameConfig.get_active_profile_summary() if GameConfig.has_method("get_active_profile_summary") else ""
	
	if debug_overlay_compact:
		debug_overlay_label.text = get_telemetry_line()
		return

	debug_overlay_label.text = (
		"== MMORPG 3D [DEBUG F9] ==\n" +
		get_telemetry_line() + "\n" +
		"Perfil: %s\n" % net_prof +
		"Mapa: %s\n" % zone_str +
		"XYZ: %.2f / %.2f / %.2f\n" % [px, py, pz] +
		"Facing: %s (%.1f°)\n" % [facing, yaw_deg] +
		"FPS: %d | Red: UDP 20Hz\n" % fps +
		"Session ID: %d | Entidades: %d\n" % [sid, entities_count] +
		"Hitboxes: ACTIVAS (Rayos X)"
	)

## Línea compacta de telemetría F9:
## "XYZ: (x, y, z) | Zone: N (Nombre) | Yaw: N° | FPS: N | Ping: N ms"
## El ping solo se muestra si NetworkManager expone una medición RTT real
## ("rtt_ms"); sin socket UDP conectado se informa "offline".
func get_telemetry_line() -> String:
	var p := Vector3.ZERO
	var yaw := 0.0
	if local_player and is_instance_valid(local_player):
		p = local_player.global_position
		yaw = fposmod(rad_to_deg(local_player.global_rotation.y), 360.0)
	var ping_str := "offline"
	if NetworkManager.udp_peer and NetworkManager.udp_peer.is_socket_connected() and NetworkManager.my_session_id > 0:
		var rtt = NetworkManager.get("rtt_ms")
		ping_str = ("%dms" % int(rtt)) if rtt != null else "--"
	return "XYZ: (%.1f, %.1f, %.1f) | Zone: %d (%s) | Yaw: %d° | FPS: %d | Ping: %s" % [
		p.x, p.y, p.z, current_zone_id, get_zone_display_name(current_zone_id),
		int(round(yaw)) % 360, int(Engine.get_frames_per_second()), ping_str]

func get_zone_display_name(zone_id: int) -> String:
	match zone_id:
		1: return "Overworld"
		2: return "Cripta Ancestral"
		_: return "Dungeon Shard"

func _process_portal_vortices(delta: float) -> void:
	for vortex in portal_vortices:
		if not is_instance_valid(vortex.get("portal")):
			continue
		if vortex.has("photon_ring") and is_instance_valid(vortex["photon_ring"]):
			vortex["photon_ring"].rotate_y(delta * 2.2)
		if vortex.has("accretion_disk") and is_instance_valid(vortex["accretion_disk"]):
			vortex["accretion_disk"].rotate_y(delta * 0.95)
		if vortex.has("outer_warp") and is_instance_valid(vortex["outer_warp"]):
			vortex["outer_warp"].rotate_y(-delta * 0.55)

func _build_map_topography() -> void:
	var path = "res://assets/maps/map_zone_overworld.json"
	var colliders = []
	
	if FileAccess.file_exists(path):
		var file = FileAccess.open(path, FileAccess.READ)
		if file:
			var content = file.get_as_text()
			var json = JSON.parse_string(content)
			if typeof(json) == TYPE_DICTIONARY and json.has("static_colliders"):
				colliders = json["static_colliders"]

	# Garantizar siempre presencia de obstáculos tácticos y topografía en el mapa principal
	if colliders.is_empty():
		print("[World] Usando topografía declarativa predeterminada para el Overworld.")
		colliders = [
			{"id": "obstacle_cube_spawn", "type": "box", "pos": [4.0, 1.0, 4.0], "size": [2.0, 2.0, 2.0], "yaw": 0.0},
			{"id": "terrain_ramp_test", "type": "ramp", "pos": [-6.0, 0.75, 8.0], "size": [3.0, 1.5, 6.0], "yaw": 0.0},
			{"id": "los_wall_cover", "type": "box", "pos": [10.0, 2.0, -6.0], "size": [1.2, 4.0, 10.0], "yaw": 0.0},
			{"id": "ruin_pillar_north", "type": "box", "pos": [0.0, 2.0, -15.0], "size": [2.0, 4.0, 2.0], "yaw": 0.0},
			{"id": "ruin_wall_east", "type": "box", "pos": [18.0, 1.5, 5.0], "size": [1.0, 3.0, 8.0], "yaw": 0.0},
			{"id": "shelter_gate_arch", "type": "box", "pos": [-10.0, 2.5, 0.0], "size": [1.5, 5.0, 6.0], "yaw": 1.5708}
		]

	print("[World] Building %d static map obstacles..." % colliders.size())

	for col in colliders:
		var node_id = str(col.get("id", "StaticObstacle"))
		if has_node(node_id):
			continue

		var body = StaticBody3D.new()
		body.name = node_id
		var pos_arr = col.get("pos", [0, 0, 0])
		body.position = Vector3(pos_arr[0], pos_arr[1], pos_arr[2])
		body.rotation.y = col.get("yaw", 0.0)

		var ctype = col.get("type", "box")
		var s_arr = col.get("size", [2, 2, 2])
		var size = Vector3(s_arr[0], s_arr[1], s_arr[2])

		var cshape = CollisionShape3D.new()
		var bshape = BoxShape3D.new()
		bshape.size = size
		cshape.shape = bshape
		body.add_child(cshape)

		var mesh_inst = MeshInstance3D.new()
		var bmesh = BoxMesh.new()
		bmesh.size = size
		mesh_inst.mesh = bmesh

		var mat = StandardMaterial3D.new()
		if ctype == "ramp":
			body.rotation_degrees.x = -16.0 # Slanted ramp angle
			mat.albedo_color = Color(0.28, 0.44, 0.28) # Mossy stone green
			mat.roughness = 0.8
		elif "pillar" in node_id:
			mat.albedo_color = Color(0.48, 0.44, 0.4) # Ancient Sandstone
			mat.roughness = 0.9
		elif "wall" in node_id:
			mat.albedo_color = Color(0.25, 0.28, 0.35) # Dark castle brick
			mat.roughness = 0.7
		else:
			mat.albedo_color = Color(0.35, 0.38, 0.42) # Reinforced Granite Cube
			mat.roughness = 0.6
		mesh_inst.material_override = mat
		mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		body.add_child(mesh_inst)

		add_child(body)


# ===========================================================================
# Fase 9.7 — Convoy de extracción móvil (0x1C) y reanimación contextual (0x1D)
# ===========================================================================

func _phase97_ui_layer() -> CanvasLayer:
	if _phase97_layer == null:
		_phase97_layer = CanvasLayer.new()
		_phase97_layer.name = "Phase97Layer"
		_phase97_layer.layer = 9 # sobre nameplates (5) y marcos de combate (8), bajo ventanas (10)
		add_child(_phase97_layer)
	return _phase97_layer


func get_convoy_hud() -> Control:
	if convoy_hud == null:
		convoy_hud = ExtractionConvoyHUDScript.new()
		convoy_hud.name = "ExtractionConvoyHUD"
		_phase97_ui_layer().add_child(convoy_hud)
		# Centrado bajo la franja superior (el panel F9 ocupa la esquina superior derecha).
		convoy_hud.position = Vector2((get_viewport().get_visible_rect().size.x - ExtractionConvoyHUDScript.PANEL_SIZE.x) * 0.5, 58)
	return convoy_hud


func get_revive_modal() -> Control:
	if revive_modal == null:
		revive_modal = ReviveProgressModalScript.new()
		revive_modal.name = "ReviveProgressModal"
		_phase97_ui_layer().add_child(revive_modal)
		var vp := get_viewport().get_visible_rect().size
		# Bajo la retícula y sobre el HUDv2: no tapa a los personajes del centro.
		revive_modal.position = Vector2((vp.x - ReviveProgressModalScript.PANEL_SIZE.x) * 0.5, vp.y * 0.5 + 92)
	return revive_modal


func _on_extraction_beacon_received(b: Dictionary) -> void:
	var bid := int(b.get("beacon_id", 0))
	var convoy = extraction_convoys.get(bid)
	if convoy == null or not is_instance_valid(convoy):
		convoy = MobileExtractionConvoyScene.instantiate()
		convoy.name = "Convoy_%d" % bid
		add_child(convoy)
		extraction_convoys[bid] = convoy
	convoy.apply_beacon_sync(b)
	# El HUD solo se muestra al jugador local que está dentro (misma histéresis que Rust).
	if local_player and is_instance_valid(local_player):
		var inside: bool = convoy.is_inside(local_player.global_position, bool(_convoy_latch.get(bid, false)))
		_convoy_latch[bid] = inside
		var hud := get_convoy_hud()
		if inside:
			hud.apply_beacon(b)
		else:
			hud.set_remaining_ms(0)


func _on_revive_sync_received(s: Dictionary) -> void:
	var me := NetworkManager.my_session_id
	var downed_sid := int(s.get("downed_player_id", 0))
	var reviver_sid := int(s.get("reviver_player_id", 0))
	var state := int(s.get("state", -1))
	var downed_node: Node3D = local_player if downed_sid == me else remote_players.get(downed_sid)
	var reviver_node: Node3D = local_player if reviver_sid == me else remote_players.get(reviver_sid)

	# ADR 100 §5: el abatido queda inmovilizado mientras le reaniman.
	if downed_sid == me and local_player and "is_pinned" in local_player:
		local_player.is_pinned = state == ExtractionReviveCodec.REVIVE_STARTED

	if reviver_sid == me:
		var target_name := str(remote_identities.get(downed_sid, "aliado"))
		get_revive_modal().apply_revive_sync(s, target_name)

	if state == ExtractionReviveCodec.REVIVE_STARTED and downed_node and reviver_node:
		_clear_revive_beam()
		revive_beam = RevivePlasmaBeamScript.new()
		revive_beam.name = "RevivePlasmaBeam"
		add_child(revive_beam)
		revive_beam.setup(reviver_node, downed_node)
	elif state != ExtractionReviveCodec.REVIVE_STARTED:
		_clear_revive_beam()
		if state == ExtractionReviveCodec.REVIVE_COMPLETED and downed_node and downed_node.is_in_group("downed_allies"):
			downed_node.remove_from_group("downed_allies")


func _clear_revive_beam() -> void:
	if revive_beam and is_instance_valid(revive_beam):
		revive_beam.queue_free()
	revive_beam = null


# -------------------------------------------------------------------------
# Fases 9.5 & 9.6: Tactical Pings [G], Ki Spectral Pulse [P], Live Archetypes
# -------------------------------------------------------------------------

func _setup_ping_and_ki_systems() -> void:
	# 1. Ki Spectral Vision Layer (CanvasLayer 1: directly above 3D world, below HUD)
	ki_layer = CanvasLayer.new()
	ki_layer.name = "KiSpectralVisionLayer"
	ki_layer.layer = 1
	add_child(ki_layer)

	ki_vision = KiSpectralVisionScene.instantiate()
	ki_layer.add_child(ki_vision)
	ki_vision.set_vision_active(false)

	ki_projector = KiAuraProjectorScript.new()
	ki_projector.name = "KiAuraProjector"
	ki_layer.add_child(ki_projector)
	ki_projector.visible = false

	# 2. Tactical Ping Wheel Layer (CanvasLayer 15: top overlay)
	ping_layer = CanvasLayer.new()
	ping_layer.name = "TacticalPingLayer"
	ping_layer.layer = 15
	add_child(ping_layer)

	ping_wheel = TacticalPingWheelScene.instantiate()
	ping_wheel.name = "TacticalPingWheel"
	ping_layer.add_child(ping_wheel)
	ping_wheel.ping_selected.connect(_on_tactical_ping_confirmed)


func trigger_ki_spectral_pulse() -> void:
	if not ki_vision or not ki_projector: return
	if _ki_pulse_tween and _ki_pulse_tween.is_valid():
		_ki_pulse_tween.kill()

	if has_node("/root/SoundManager"):
		var sm = get_node("/root/SoundManager")
		sm.play_ui_sfx(&"ki_pulse")

	ki_vision.set_vision_active(true)
	ki_projector.visible = true
	ki_vision.desaturation = 0.0

	_ki_pulse_tween = create_tween()
	# 1. Smoothly fade in to 0.85 over 0.4s
	_ki_pulse_tween.tween_property(ki_vision, "desaturation", 0.85, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# 2. Hold pulse for 4.5 seconds
	_ki_pulse_tween.tween_interval(4.5)
	# 3. Smoothly fade back out to 0.0 over 0.6s
	_ki_pulse_tween.tween_property(ki_vision, "desaturation", 0.0, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_ki_pulse_tween.tween_callback(func():
		ki_vision.set_vision_active(false)
		ki_projector.visible = false
	)
	print("[World] Ki Spectral Vision pulse activated for 5.5s.")


## Duraciones de feedback del ping táctico (ADR 097).
const PING_AURA_DURATION := 2.5
const PING_BEAM_DURATION := 5.0


## API de enrutado para UIInputRouter ([G] pulsada): abre la rueda en el cursor.
func open_tactical_ping_wheel(screen_pos: Vector2) -> bool:
	if ping_wheel == null or ping_wheel.is_active:
		return false
	ping_wheel.open_at(screen_pos)
	return true


## [G] soltada: confirma el cuadrante seleccionado (o cancela si sigue en el DEADZONE).
func confirm_tactical_ping_wheel(screen_pos: Vector2) -> int:
	if ping_wheel == null or not ping_wheel.is_active:
		return TacticalPingWheel.PingType.NONE
	ping_wheel.update_selection_from_screen(screen_pos)
	return ping_wheel.close_and_confirm()


## Clic derecho con la rueda abierta: cancela sin emitir.
func cancel_tactical_ping_wheel() -> bool:
	if ping_wheel == null or not ping_wheel.is_active:
		return false
	ping_wheel.cancel()
	return true


func is_tactical_ping_wheel_open() -> bool:
	return ping_wheel != null and ping_wheel.is_active


## Ping local confirmado por la rueda. El SFX lo reproduce la propia rueda al confirmar
## (feedback inmediato, sin duplicarlo aquí); World añade aura + baliza 3D + red 0x1A.
func _on_tactical_ping_confirmed(type: int, ping_name: String) -> void:
	var screen_pos: Vector2 = ping_wheel.open_screen_pos if ping_wheel else get_viewport().get_mouse_position()
	var ground_pos := _ground_position_at_screen(screen_pos)

	_apply_tactical_ping_fx(local_player, type, ground_pos, false)

	# Network broadcast (Protocol 0x1A)
	if NetworkManager and NetworkManager.has_method("send_tactical_ping"):
		NetworkManager.send_tactical_ping(type, ground_pos, 0)

	print("[World] Tactical ping emitted: %s (Type %d) at %s" % [ping_name, type, str(ground_pos)])


## Ping táctico recibido de la red (0x1A re-difundido por el servidor).
## Ubica al emisor por su sender_sid, le activa el aura y proyecta la baliza.
func _on_tactical_ping_broadcast(ping: Dictionary) -> void:
	var sender_sid := int(ping.get("sender_sid", 0))
	var type := int(ping.get("ping_type", TacticalPingWheel.PingType.DANGER))
	var pos: Vector3 = ping.get("world_pos", Vector3.ZERO)
	var sender: Node3D = null
	if remote_players.has(sender_sid) and is_instance_valid(remote_players[sender_sid]):
		sender = remote_players[sender_sid] as Node3D
	_apply_tactical_ping_fx(sender, type, pos, true)


## Feedback compartido local/remoto: aura temporal en el emisor, baliza 3D en el
## suelo y (opcional) SFX del cuadrante vía SoundManager. Devuelve la baliza creada.
func _apply_tactical_ping_fx(owner_node: Node3D, type: int, ground_pos: Vector3, play_sfx: bool) -> Node3D:
	var col := TacticalPingWheel.get_ping_color(type)

	if play_sfx:
		var sm = get_node_or_null("/root/SoundManager")
		if sm and sm.has_method("play_ui_sfx"):
			sm.play_ui_sfx(TacticalPingWheel.get_ping_sfx(type))

	if owner_node and is_instance_valid(owner_node):
		_spawn_temporary_player_aura(owner_node, col, PING_AURA_DURATION)

	var beam: Node3D = TacticalPingBeam3DScene.new()
	beam.name = "TacticalPingBeam3D"
	beam.ping_type = type
	beam.position = ground_pos
	add_child(beam, true)
	get_tree().create_timer(PING_BEAM_DURATION).timeout.connect(func():
		if is_instance_valid(beam):
			beam.queue_free()
	)
	return beam


## Punto del suelo 3D bajo una posición de pantalla: raycast físico y, si no hay
## colisión, intersección con el plano y = 0.
func _ground_position_at_screen(screen_pos: Vector2) -> Vector3:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return local_player.global_position if local_player and is_instance_valid(local_player) else Vector3.ZERO
	var from := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	var world_3d := get_viewport().get_world_3d()
	var space_state: PhysicsDirectSpaceState3D = world_3d.direct_space_state if world_3d else null
	if space_state:
		var query := PhysicsRayQueryParameters3D.create(from, from + dir * 500.0)
		query.collide_with_bodies = true
		query.collide_with_areas = false
		if local_player and local_player is CollisionObject3D:
			query.exclude = [local_player.get_rid()]
		var hit: Dictionary = space_state.intersect_ray(query)
		if not hit.is_empty():
			return hit.position
	if absf(dir.y) > 0.0001:
		var t := -from.y / dir.y
		if t > 0.0:
			return from + dir * t
	return from + dir * 15.0


## Aro/aura luminosa temporal anclada al jugador (local o remoto) del color del ping.
func _spawn_temporary_player_aura(p_node: Node3D, col: Color, dur: float) -> MeshInstance3D:
	var ring := MeshInstance3D.new()
	ring.name = "TacticalPingAura"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.9
	torus.outer_radius = 1.25
	ring.mesh = torus
	ring.position.y = 0.08
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(col, 0.9)
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 3.5
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	ring.material_override = mat
	ring.set_meta("ping_color", col)
	ring.set_meta("duration", dur)
	p_node.add_child(ring, true)

	# Expansión + desvanecimiento; el tween vive en el aro (muere con el jugador).
	var tw := ring.create_tween().set_parallel(true)
	tw.tween_property(ring, "scale", Vector3(1.6, 1.0, 1.6), dur).from(Vector3(0.6, 1.0, 0.6)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(ring.queue_free)
	return ring


func _spawn_overworld_archetypes() -> void:
	for a in overworld_archetypes:
		if is_instance_valid(a):
			a.queue_free()
	overworld_archetypes.clear()

	# 1. Gildas el Mercader (Puesto Comercial P2P)
	var gildas = Area3D.new()
	gildas.name = "NPC_Gildas"
	gildas.position = Vector3(4.0, 1.0, 4.0)
	gildas.collision_layer = 48
	gildas.collision_mask = 48
	gildas.add_to_group("interactable")
	var gildas_col = CollisionShape3D.new()
	var gildas_shape = CapsuleShape3D.new()
	gildas_shape.radius = 0.45
	gildas_shape.height = 1.8
	gildas_col.shape = gildas_shape
	gildas.add_child(gildas_col)

	var gildas_mesh = MeshInstance3D.new()
	var g_cap = CapsuleMesh.new()
	g_cap.radius = 0.4
	g_cap.height = 1.8
	gildas_mesh.mesh = g_cap
	var g_mat = StandardMaterial3D.new()
	g_mat.albedo_color = Color(0.2, 0.5, 0.85)
	g_mat.roughness = 0.4
	gildas_mesh.material_override = g_mat
	gildas.add_child(gildas_mesh)

	var gildas_script = load("res://world/GildasMerchant.gd")
	if gildas_script:
		gildas.set_script(gildas_script)
	add_child(gildas)
	overworld_archetypes.append(gildas)

	if has_node("/root/ScreenSpaceManager"):
		var np = WorldNameplateScene.instantiate()
		np.setup("Gildas el Mercader", 1000.0, 1000.0, false, "‹ MERCADO P2P ›", 25)
		ScreenSpaceManager.register_target(gildas, np, Vector3(0, 2.2, 0))

	# 2. Guardia Carmesí (Fuerza / Red Aura #ff3344, Nivel 12)
	var carmesi = _create_mock_mob("Guardia Carmesí", Vector3(-6.0, 1.0, 8.0), Color(0.95, 0.25, 0.25), 12, 1200.0, "‹ DOMINANCIA FUERZA ›")
	if ki_projector:
		ki_projector.track(carmesi, KiSpectralVision.COLOR_STRENGTH, "Guardia Carmesí", 1.2, 1.0)

	# 3. Explorador Esmeralda (Agilidad / Green Aura #00ff88, Nivel 14)
	var esmeralda = _create_mock_mob("Explorador Esmeralda", Vector3(-10.0, 1.0, 12.0), Color(0.15, 0.88, 0.45), 14, 950.0, "‹ DOMINANCIA AGILIDAD ›")
	if ki_projector:
		ki_projector.track(esmeralda, KiSpectralVision.COLOR_AGILITY, "Explorador Esmeralda", 1.2, 1.0)

	# 4. Mago del Vacío (Inteligencia / Void Purple #aa44ff, Nivel 16)
	var vacio = _create_mock_mob("Mago del Vacío", Vector3(-8.0, 1.0, 18.0), Color(0.68, 0.28, 0.98), 16, 800.0, "‹ DOMINANCIA INTELIGENCIA ›")
	if ki_projector:
		ki_projector.track(vacio, KiSpectralVision.COLOR_INTELLIGENCE, "Mago del Vacío", 1.2, 1.0)

	# 5. Val'Gorath (Jefe Mundial / Celestial Gold #ffd700, Nivel 50)
	var boss = _create_mock_mob("Val'Gorath el Devorador", Vector3(0.0, 2.2, 24.0), Color(0.92, 0.72, 0.15), 50, 100000.0, "‹ JEFE MUNDIAL - FASE 3/3 ›", 2.2)
	if ki_projector:
		ki_projector.track(boss, KiSpectralVision.COLOR_BOSS, "Val'Gorath", 2.6, 2.2)

	print("[World] %d Arquetipos de Overworld desplegados correctamente." % overworld_archetypes.size())


func _create_mock_mob(p_name: String, pos: Vector3, col: Color, lvl: int, hp: float, title: String, mob_scale: float = 1.0) -> Node3D:
	var mob = Area3D.new()
	mob.name = p_name.replace(" ", "_")
	mob.position = pos
	mob.scale = Vector3.ONE * mob_scale
	mob.collision_layer = 48
	mob.collision_mask = 48
	mob.add_to_group("hitbox_debug")

	var col_shape = CollisionShape3D.new()
	var cap = CapsuleShape3D.new()
	cap.radius = 0.4 * mob_scale
	cap.height = 1.8 * mob_scale
	col_shape.shape = cap
	mob.add_child(col_shape)

	var mesh_inst = MeshInstance3D.new()
	var c_mesh = CapsuleMesh.new()
	c_mesh.radius = 0.38 * mob_scale
	c_mesh.height = 1.8 * mob_scale
	mesh_inst.mesh = c_mesh
	var mat = StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = 0.5
	mesh_inst.material_override = mat
	mob.add_child(mesh_inst)

	add_child(mob)
	overworld_archetypes.append(mob)

	# Hostile nameplate -> Nivel a la DERECHA
	if has_node("/root/ScreenSpaceManager"):
		var np = WorldNameplateScene.instantiate()
		np.setup(p_name, hp, hp, true, title, lvl)
		ScreenSpaceManager.register_target(mob, np, Vector3(0, 2.2 * mob_scale, 0))

	return mob

