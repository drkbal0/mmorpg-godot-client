extends RefCounted

## TacticalPingCodec.gd — Codec Little-Endian del paquete 0x1A TACTICAL_PING (ADR 097).
## Espejo exacto de runtimes/mmo-world/src/protocol.rs (build/parse_tactical_ping).
##
## Layout (22 bytes):
##   [0x1A][player_id u32 LE][ping_type u8][x f32 LE][y f32 LE][z f32 LE][target_entity_id u32 LE]
##
## ping_type (valor de cable, compartido con TacticalPingWheel.PingType):
##   0 = MISSING (Rust PING_TYPE_ATTACK)   1 = DANGER
##   2 = ASSIST                            3 = ON_MY_WAY (Rust PING_TYPE_EXTRACT)

const OPCODE_TACTICAL_PING := 0x1A
const TACTICAL_PING_LEN := 22
const MAX_PING_TYPE := 3


## Construye el paquete 0x1A. `player_id` es reclamado por el cliente; el servidor
## lo sobrescribe con el sid autenticado antes de re-difundir.
static func encode(player_id: int, ping_type: int, world_pos: Vector3, target_entity_id: int = 0) -> PackedByteArray:
	var w := StreamPeerBuffer.new()
	w.big_endian = false
	w.put_u8(OPCODE_TACTICAL_PING)
	w.put_u32(player_id)
	w.put_u8(clampi(ping_type, 0, MAX_PING_TYPE))
	w.put_float(world_pos.x)
	w.put_float(world_pos.y)
	w.put_float(world_pos.z)
	w.put_u32(target_entity_id)
	return w.data_array


## Decodifica un paquete 0x1A. Devuelve {} si el opcode es incorrecto, el paquete está
## truncado, el tipo es desconocido o las coordenadas no son finitas (mismas reglas que Rust).
static func decode(packet: PackedByteArray) -> Dictionary:
	if packet.size() < TACTICAL_PING_LEN or packet[0] != OPCODE_TACTICAL_PING or packet[5] > MAX_PING_TYPE:
		return {}
	var r := StreamPeerBuffer.new()
	r.big_endian = false
	r.data_array = packet
	r.seek(1)
	var sender_sid := r.get_u32()
	var ping_type := r.get_u8()
	var pos := Vector3(r.get_float(), r.get_float(), r.get_float())
	if not (is_finite(pos.x) and is_finite(pos.y) and is_finite(pos.z)):
		return {}
	var target := r.get_u32()
	return {
		"sender_sid": sender_sid,
		"ping_type": ping_type,
		"world_pos": pos,
		"target_entity_id": target,
	}
