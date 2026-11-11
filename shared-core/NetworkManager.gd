# @context
# domain: networking/udp
# depends_on: [AuthManager.gd]
# doc_ref: docs/adr/014-godot-network-manager.md
# status: stable

extends Node

var udp_peer := PacketPeerUDP.new()
var server_ip : String
var server_port : int

var my_session_id : int = 0
var heartbeat_timer : float = 0.0
const HEARTBEAT_INTERVAL : float = 2.0

signal server_connected(session_id: int, hp_percent: int, max_hp: int)
signal players_state_broadcast(players_data: Array)
signal remote_player_disconnected(session_id: int)
signal kicked_from_server(reason: String)
signal player_position_corrected(new_pos: Vector3)
signal identity_received(session_id: int, name: String, hp_percent: int, max_hp: int)
signal player_state_updated(session_id: int, hp_percent: int, source_id: int)
signal connection_interrupted
signal connection_restored
signal static_entity_spawned(session_id: int, type: int, pos: Vector3, aggro: float, attack: float, max_hp: float, name: String)
signal attributes_updated(session_id: int, aggro: float, attack: float, speed: float, max_hp: float)
signal skill_spawned(projectile_id: int, caster_sid: int, spell_id: int, origin: Vector3, dir: Vector2, speed: float, server_tick: int)
signal combat_event_received(source_sid: int, target_sid: int, spell_id: int, damage: float, is_crit: bool, target_hp_percent: int)
signal echo_item_collected(echo_id: String, item_id: String, is_empty: bool)
signal zone_transition_received(zone_id: int, pos: Vector3)
signal hazard_sync_received(hazard_sid: int, phase: int, remaining_ms: int, total_ms: int)
## Fase 9.7 (ADR 099/100): convoy de extracción móvil y reanimación contextual.
signal extraction_beacon_received(beacon: Dictionary)
signal revive_sync_received(sync: Dictionary)

const ExtractionReviveCodec = preload("res://shared-core/ExtractionReviveCodec.gd")

var last_server_heartbeat : float = 0.0
const SERVER_TIMEOUT : float = 8.0 # If no packet from server in 8s, we are disconnected
var is_reconnecting : bool = false
var cached_static_entities: Dictionary = {}
var cached_identities: Dictionary = {}

var move_sequence: int = 0
const MAP_LIMIT: float = 512.0

func quantize_f32(v: float) -> int:
	var clamped = clamp(v, -MAP_LIMIT, MAP_LIMIT)
	return int(round((clamped * 32767.0) / MAP_LIMIT))

func dequantize_i16(q: int) -> float:
	return (float(q) * MAP_LIMIT) / 32767.0

func _ready():
	var udp_cfg = GameConfig.get_udp_server()
	server_ip = udp_cfg.get("host", "play.elbalo.lol")
	server_port = udp_cfg.get("port", 5000)
	print("NetworkManager: Initialized with Server=%s:%d (Production=%s)" % [
		server_ip, server_port, str(GameConfig.is_production_mode())
	])
	
	# Parse CLI arguments for tokens (dev/launcher bypass)
	for arg in OS.get_cmdline_args():
		if arg.begins_with("--token="):
			var token = arg.split("=")[1]
			print("CLI Token detected! Bypassing login.")
			AuthManager.auth_token = token
			AuthManager.fetch_profile() # Requerido para rellenar is_admin y is_premium
	
	last_server_heartbeat = Time.get_ticks_msec() / 1000.0

func connect_to_world(_unused_token: String = ""):
	var ticket = await AuthManager.fetch_world_ticket()
	if ticket != "":
		connect_with_ticket(ticket)

func get_resolved_server_ip() -> String:
	var target = server_ip.strip_edges()
	if target.is_valid_ip_address():
		return target
	var resolved = IP.resolve_hostname(target, IP.TYPE_IPV4)
	if resolved != "" and resolved.is_valid_ip_address():
		print("NetworkManager: Hostname '%s' resolved to IPv4 '%s'" % [target, resolved])
		return resolved
	push_error("NetworkManager: Failed to resolve hostname: '%s'" % target)
	return ""

func connect_with_ticket(ticket: String):
	if ticket == "":
		push_error("MMO: Ticket is empty")
		return

	var resolved_ip = get_resolved_server_ip()
	if resolved_ip == "":
		push_error("MMO: Cannot connect, unable to resolve server host: " + server_ip)
		return

	print("Connecting to MMO Server with Ticket: %s" % ticket)
	print("Connecting to MMO Server at %s:%d (from %s)..." % [resolved_ip, server_port, server_ip])
	
	if udp_peer.is_socket_connected():
		udp_peer.close()
		
	var err = udp_peer.connect_to_host(resolved_ip, server_port)
	if err != OK:
		push_error("Error connecting to host: %s" % str(err))
	else:
		print("UDP Socket bound successfully to %s:%d." % [resolved_ip, server_port])
		
		# Send Connect packet with Efimero Ticket (UUID)
		var packet := PackedByteArray()
		packet.append(0x01) # Packet Type: Connect
		packet.append_array(ticket.to_utf8_buffer())
		udp_peer.put_packet(packet)
		print("Sent Connect Packet with Ticket.")

func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		disconnect_from_world()

func send_disconnect():
	if udp_peer and udp_peer.is_socket_connected():
		var packet = PackedByteArray()
		packet.append(0x04) # Packet Type: Disconnect
		udp_peer.put_packet(packet)
		print("Sent disconnect packet.")

## Desconexión limpia del mundo autoritativo (cierre de socket, parada de reconexión y reset de sesión)
func disconnect_from_world() -> void:
	is_reconnecting = false
	if udp_peer:
		if udp_peer.is_socket_connected():
			send_disconnect()
		udp_peer.close()
	my_session_id = 0
	move_sequence = 0
	heartbeat_timer = 0.0
	last_server_heartbeat = 0.0
	cached_static_entities.clear()
	cached_identities.clear()
	print("[NetworkManager] Desconexión limpia del mundo completada.")

func _process(delta):
	# Handle heartbeats
	heartbeat_timer += delta
	if heartbeat_timer >= HEARTBEAT_INTERVAL:
		heartbeat_timer = 0.0
		send_heartbeat()

	# Detect timeout
	var now = Time.get_ticks_msec() / 1000.0
	if my_session_id > 0 and not is_reconnecting:
		if now - last_server_heartbeat > SERVER_TIMEOUT:
			_handle_connection_loss()

	while udp_peer.get_available_packet_count() > 0:
		var packet = udp_peer.get_packet()
		last_server_heartbeat = now
		if packet.size() > 0:
			var packet_type = packet[0]
			var reader = StreamPeerBuffer.new()
			reader.data_array = packet
			reader.big_endian = false # RUST SENDS LITTLE ENDIAN (to_le_bytes)
			reader.seek(1) # Skip opcode
			
			if packet_type == 0x01: # Connect Ack
				my_session_id = reader.get_u32()
				var hp_percent = reader.get_u8()
				var max_hp = reader.get_u32()
				push_warning("MMO: Connected! Assigned Session ID: %d, HP: %d%%, MaxHP: %d" % [my_session_id, hp_percent, max_hp])
				server_connected.emit(my_session_id, hp_percent, max_hp)
				
			elif packet_type == 0x03: # State Broadcast
				# Payload: [0x03] [Count (u16)] [ {sid(4), qx(2), qy(2), qz(2), yaw(1)} ] = 11 bytes per entity
				if packet.size() >= 3:
					var count = reader.get_u16()
					
					var players_data = []
					for _i in range(count):
						if reader.get_available_bytes() >= 11:
							var sid = reader.get_u32()
							var qx = reader.get_16()
							var qy = reader.get_16()
							var qz = reader.get_16()
							var yaw_u8 = reader.get_u8()
							
							var x = dequantize_i16(qx)
							var y = dequantize_i16(qy)
							var z = dequantize_i16(qz)
							var yaw = (float(yaw_u8) / 255.0) * (2.0 * PI) - PI
							
							players_data.append({
								"sid": sid,
								"pos": Vector3(x, y, z),
								"yaw": yaw
							})
					players_state_broadcast.emit(players_data)

			elif packet_type == 0x04: # Server Disconnect Notify
				var sid = reader.get_u32()
				push_warning("MMO: Remote player %d disconnected." % sid)
				remote_player_disconnected.emit(sid)
				
			elif packet_type == 0x05: # Server Kick
				my_session_id = 0
				udp_peer.close()
				var kick_reason = "Alguien más se ha conectado con tu cuenta en otro dispositivo."
				if reader.get_available_bytes() >= 4:
					var _kick_sid = reader.get_u32()
					if reader.get_available_bytes() >= 1:
						var reason_code = reader.get_u8()
						if reason_code == 1:
							kick_reason = "character_death"
						elif reason_code == 2:
							kick_reason = "Tu sesión ha expirado por inactividad."
				push_error("MMO: Kicked from server! Reason: %s" % kick_reason)
				kicked_from_server.emit(kick_reason)

			elif packet_type == 0x06: # Snapback (Position correction)
				var x = reader.get_float()
				var y = reader.get_float()
				var z = reader.get_float()
				push_warning("MMO: Server forced snapback to %s" % str(Vector3(x, y, z)))
				player_position_corrected.emit(Vector3(x, y, z))
				
			elif packet_type == 0x07: # Identity Update (sid -> name)
				var sid = reader.get_u32()
				var hp_percent = reader.get_u8()
				var max_hp = reader.get_u32()
				var name_len = reader.get_u8()
				var p_name = packet.slice(reader.get_position(), reader.get_position() + name_len).get_string_from_utf8()
				cached_identities[sid] = {"name": p_name, "hp_percent": hp_percent, "max_hp": max_hp}
				identity_received.emit(sid, p_name, hp_percent, max_hp)
				# print("NetworkManager: Received Identity for SID %d -> %s" % [sid, p_name])

			elif packet_type == 0x08: # State Update (HP, source_id)
				var sid = reader.get_u32()
				var hp_percent = reader.get_u8()
				var source_id = reader.get_u32()
				player_state_updated.emit(sid, hp_percent, source_id)
				
			elif packet_type == 0x09: # Spawn Static (sid, type, x,y,z, aggro, attack, max_hp, name)
				var sid = reader.get_u32()
				var type = reader.get_u8()
				var x = reader.get_float()
				var y = reader.get_float()
				var z = reader.get_float()
				var aggro = reader.get_float()
				var attack = reader.get_float()
				var max_hp = reader.get_float()
				var n_len = reader.get_u8()
				var p_name = packet.slice(reader.get_position(), reader.get_position() + n_len).get_string_from_utf8()
				
				cached_static_entities[sid] = {
					"sid": sid,
					"type": type,
					"pos": Vector3(x, y, z),
					"aggro": aggro,
					"attack": attack,
					"max_hp": max_hp,
					"name": p_name
				}
				static_entity_spawned.emit(sid, type, Vector3(x, y, z), aggro, attack, max_hp, p_name)

			elif packet_type == 0x0B: # Attributes Update (sid, aggro, attack, speed, max_hp)
				var sid = reader.get_u32()
				var aggro = reader.get_float()
				var attack = reader.get_float()
				var speed = reader.get_float()
				var max_hp = reader.get_float()
				attributes_updated.emit(sid, aggro, attack, speed, max_hp)

			elif packet_type == 0x0D: # Skill Spawn (Dead-Reckoning)
				var projectile_id = reader.get_u32()
				var caster_sid = reader.get_u32()
				var spell_id = reader.get_u16()
				var ox = reader.get_float()
				var oy = reader.get_float()
				var oz = reader.get_float()
				var dx = reader.get_float()
				var dz = reader.get_float()
				var spd = reader.get_float()
				var s_tick = reader.get_u32()
				skill_spawned.emit(projectile_id, caster_sid, spell_id, Vector3(ox, oy, oz), Vector2(dx, dz), spd, s_tick)

			elif packet_type == 0x0E: # Combat Event (Damage Float / Feedback)
				var source_sid = reader.get_u32()
				var target_sid = reader.get_u32()
				var spell_id = reader.get_u16()
				var damage = reader.get_float()
				var is_crit = (reader.get_u8() == 1)
				var hp_percent = reader.get_u8()
				combat_event_received.emit(source_sid, target_sid, spell_id, damage, is_crit, hp_percent)

			elif packet_type == 0x0F: # Zone Transfer (Dimension Teleport)
				var target_zone_id = reader.get_u32()
				var x = reader.get_float()
				var y = reader.get_float()
				var z = reader.get_float()
				push_warning("MMO: Server transferred player to Zone %d at %s" % [target_zone_id, str(Vector3(x, y, z))])
				zone_transition_received.emit(target_zone_id, Vector3(x, y, z))

			elif packet_type == 0x16: # Echo Item Collected (Real-time Loot Sync)
				if packet.size() >= 3:
					var echo_len = reader.get_u8()
					var echo_id = packet.slice(reader.get_position(), reader.get_position() + echo_len).get_string_from_utf8()
					reader.seek(reader.get_position() + echo_len)
					if reader.get_available_bytes() >= 1:
						var item_len = reader.get_u8()
						var item_id = packet.slice(reader.get_position(), reader.get_position() + item_len).get_string_from_utf8()
						reader.seek(reader.get_position() + item_len)
						var is_empty = false
						if reader.get_available_bytes() >= 1:
							is_empty = (reader.get_u8() == 1)
						echo_item_collected.emit(echo_id, item_id, is_empty)
			elif packet_type == 0x19: # Hazard Sync (ADR 094 / Fase 9.13)
				# Layout LE: [0x19][hazard_sid u32][phase u8][remaining_ms u32][phase_total_ms u32]
				if packet.size() >= 14:
					var hazard_sid = reader.get_u32()
					var phase = reader.get_u8()
					var remaining_ms = reader.get_u32()
					var total_ms = reader.get_u32()
					hazard_sync_received.emit(hazard_sid, phase, remaining_ms, total_ms)
			elif packet_type == ExtractionReviveCodec.OPCODE_EXTRACTION_BEACON_SYNC: # 0x1C (ADR 099)
				var beacon := ExtractionReviveCodec.decode_beacon(packet)
				if not beacon.is_empty():
					extraction_beacon_received.emit(beacon)
			elif packet_type == ExtractionReviveCodec.OPCODE_REVIVE_SYNC: # 0x1D (ADR 100)
				var rsync := ExtractionReviveCodec.decode_revive(packet)
				if not rsync.is_empty():
					revive_sync_received.emit(rsync)

func send_heartbeat():
	if udp_peer.is_socket_connected():
		var packet = PackedByteArray()
		packet.append(0x00) # Heartbeat
		udp_peer.put_packet(packet)

func send_move(pos: Vector3, yaw: float = 0.0):
	if udp_peer.is_socket_connected() and my_session_id > 0:
		var packet = PackedByteArray()
		packet.append(0x02) # Move
		
		var writer = StreamPeerBuffer.new()
		writer.big_endian = false
		writer.resize(11)
		writer.put_u32(move_sequence)
		writer.put_16(quantize_f32(pos.x))
		writer.put_16(quantize_f32(pos.y))
		writer.put_16(quantize_f32(pos.z))
		
		# Convert yaw from radians to u8 (0-255) mapping -PI to PI
		var yaw_mapped = clamp(yaw, -PI, PI)
		var yaw_u8 = int(((yaw_mapped + PI) / (2.0 * PI)) * 255.0)
		writer.put_u8(yaw_u8)
		
		packet.append_array(writer.data_array)
		udp_peer.put_packet(packet)
		move_sequence += 1

func send_packet(packet: PackedByteArray) -> Error:
	if not udp_peer.is_socket_connected():
		return ERR_UNCONFIGURED
	return udp_peer.put_packet(packet)

func _handle_connection_loss():
	print("NetworkManager: Connection lost (timeout). Attempting silent reconnect...")
	is_reconnecting = true
	connection_interrupted.emit()
	
	# Attempt to verify session first
	var is_valid = await AuthManager.verify_session()
	if not is_valid:
		print("NetworkManager: Session expired. Cannot reconnect silently.")
		is_reconnecting = false
		kicked_from_server.emit("Tu sesión ha expirado.")
		return
		
	# Try to get a new ticket and reconnect
	# We retry up to 3 times
	for i in range(3):
		print("NetworkManager: Reconnect attempt %d..." % (i+1))
		var ticket = await AuthManager.fetch_world_ticket()
		if ticket != "":
			connect_with_ticket(ticket)
			# Wait a bit for the connect_ack
			await get_tree().create_timer(2.0).timeout
			if my_session_id > 0:
				print("NetworkManager: Reconnected successfully!")
				is_reconnecting = false
				connection_restored.emit()
				return
		await get_tree().create_timer(2.0).timeout
		
	print("NetworkManager: Reconnect failed after multiple attempts.")
	is_reconnecting = false
	kicked_from_server.emit("Error de conexión persistente.")

func send_admin_edit_npc(target_sid: int, aggro: float, attack: float, speed: float, damage: float):
	if udp_peer.is_socket_connected() and my_session_id > 0:
		var packet = PackedByteArray()
		packet.append(0x0A) # AdminEditNpc
		
		var writer = StreamPeerBuffer.new()
		writer.big_endian = false
		writer.resize(20)
		writer.put_u32(target_sid)
		writer.put_float(aggro)
		writer.put_float(attack)
		writer.put_float(speed)
		writer.put_float(damage)
		
		packet.append_array(writer.data_array)
		udp_peer.put_packet(packet)

func send_cast_skill(skill_id: int, target_pos: Vector3, target_sid: int = 0):
	if udp_peer.is_socket_connected() and my_session_id > 0:
		var packet = PackedByteArray()
		packet.append(0x0C) # CastSkill
		
		var writer = StreamPeerBuffer.new()
		writer.big_endian = false
		writer.resize(10)
		writer.put_u16(skill_id)
		writer.put_16(quantize_f32(target_pos.x))
		writer.put_16(quantize_f32(target_pos.z))
		writer.put_u32(target_sid)
		
		packet.append_array(writer.data_array)
		udp_peer.put_packet(packet)

func send_despawn_echo(echo_id: String) -> void:
	if udp_peer.is_socket_connected() and my_session_id > 0:
		var packet = PackedByteArray()
		packet.append(0x17) # OPCODE_DESPAWN_ECHO
		var utf8 = echo_id.to_utf8_buffer()
		packet.append(mini(utf8.size(), 255))
		packet.append_array(utf8)
		udp_peer.put_packet(packet)
		print("[NetworkManager] Sent authoritative DespawnEcho request for ID: ", echo_id)

## Petición de reanimación (0x1D, ADR 100). cancel=false al pulsar [F], true al soltarla.
## reviver_player_id viaja como 0: el servidor lo sustituye por la sesión autenticada.
func send_revive_request(downed_sid: int, cancel: bool) -> void:
	if udp_peer.is_socket_connected() and my_session_id > 0:
		udp_peer.put_packet(ExtractionReviveCodec.encode_revive({
			"state": ExtractionReviveCodec.REVIVE_INTERRUPTED if cancel else ExtractionReviveCodec.REVIVE_STARTED,
			"downed_player_id": downed_sid,
		}))
