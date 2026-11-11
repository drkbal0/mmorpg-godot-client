extends RefCounted

## ExtractionReviveCodec.gd — Codec Little-Endian de los paquetes de la Fase 9.7.
## Espejo exacto de runtimes/mmo-world/src/protocol.rs (mismas reglas de rechazo).
##
## 0x1C EXTRACTION_BEACON_SYNC (24 bytes, ADR 099):
##   [0x1C][beacon_id u32][pos_x f32][pos_y f32][pos_z f32][radius f32][remaining_ms u16][flags u8]
##   flags = players_inside_count (bits 0-6) | is_panic << 7
##   (La lista de campos del ADR suma 25 B; count y panic se empaquetan en 1 byte
##    para respetar el tamaño obligatorio de 24 B sin perder ningún campo.)
##
## 0x1D REVIVE_SYNC (16 bytes, ADR 100):
##   [0x1D][state u8][progress_pct u8][pad u8][downed_player_id u32][reviver_player_id u32][health_restored u16][reserved u16]
##   state: 0 = Started, 1 = Interrupted, 2 = Completed.
##   Cliente → servidor: el mismo layout como petición (0 = empezar, 1 = cancelar);
##   el servidor sustituye reviver_player_id por la sesión autenticada.

const OPCODE_EXTRACTION_BEACON_SYNC := 0x1C
const EXTRACTION_BEACON_SYNC_LEN := 24
const BEACON_MAX_PLAYERS_INSIDE := 0x7F
const BEACON_PANIC_BIT := 0x80

const OPCODE_REVIVE_SYNC := 0x1D
const REVIVE_SYNC_LEN := 16
const REVIVE_STARTED := 0
const REVIVE_INTERRUPTED := 1
const REVIVE_COMPLETED := 2

## Constantes de juego compartidas con Rust (extraction_convoy.rs / components.rs).
const CONVOY_RADIUS_NORMAL := 10.0
const CONVOY_RADIUS_PANIC := 4.0
const CONVOY_EXIT_CUSHION := 1.5
const CONVOY_GRACE_TICKS := 10
const CONVOY_EXTRACTION_MS := 10000
const REVIVE_RANGE_M := 2.5
const REVIVE_CHANNEL_SEC := 6.0
const BLEEDOUT_SEC := 30.0


static func encode_beacon(b: Dictionary) -> PackedByteArray:
	var w := StreamPeerBuffer.new()
	w.big_endian = false
	w.put_u8(OPCODE_EXTRACTION_BEACON_SYNC)
	w.put_u32(int(b.get("beacon_id", 0)))
	var pos: Vector3 = b.get("pos", Vector3.ZERO)
	w.put_float(pos.x)
	w.put_float(pos.y)
	w.put_float(pos.z)
	w.put_float(float(b.get("radius", CONVOY_RADIUS_NORMAL)))
	w.put_u16(clampi(int(b.get("remaining_ms", 0)), 0, 0xFFFF))
	var count := clampi(int(b.get("players_inside_count", 0)), 0, BEACON_MAX_PLAYERS_INSIDE)
	w.put_u8(count | (BEACON_PANIC_BIT if bool(b.get("is_panic", false)) else 0))
	return w.data_array


## Devuelve {} si el paquete es inválido (opcode, tamaño, NaN/Inf, radio <= 0).
static func decode_beacon(data: PackedByteArray) -> Dictionary:
	if data.size() < EXTRACTION_BEACON_SYNC_LEN or data[0] != OPCODE_EXTRACTION_BEACON_SYNC:
		return {}
	var r := StreamPeerBuffer.new()
	r.big_endian = false
	r.data_array = data.slice(0, EXTRACTION_BEACON_SYNC_LEN)
	r.seek(1)
	var beacon_id := r.get_u32()
	var pos := Vector3(r.get_float(), r.get_float(), r.get_float())
	var radius := r.get_float()
	if not (is_finite(pos.x) and is_finite(pos.y) and is_finite(pos.z)) or not is_finite(radius) or radius <= 0.0:
		return {}
	var remaining_ms := r.get_u16()
	var flags := r.get_u8()
	return {
		"beacon_id": beacon_id,
		"pos": pos,
		"radius": radius,
		"remaining_ms": remaining_ms,
		"players_inside_count": flags & BEACON_MAX_PLAYERS_INSIDE,
		"is_panic": (flags & BEACON_PANIC_BIT) != 0,
	}


static func encode_revive(s: Dictionary) -> PackedByteArray:
	var w := StreamPeerBuffer.new()
	w.big_endian = false
	w.put_u8(OPCODE_REVIVE_SYNC)
	w.put_u8(int(s.get("state", REVIVE_STARTED)))
	w.put_u8(clampi(int(s.get("progress_pct", 0)), 0, 100))
	w.put_u8(0) # pad
	w.put_u32(int(s.get("downed_player_id", 0)))
	w.put_u32(int(s.get("reviver_player_id", 0)))
	w.put_u16(clampi(int(s.get("health_restored", 0)), 0, 0xFFFF))
	w.put_u16(0) # reserved
	return w.data_array


## Devuelve {} si el paquete es inválido (estado > 2, progreso > 100, pad/reserved != 0).
static func decode_revive(data: PackedByteArray) -> Dictionary:
	if data.size() < REVIVE_SYNC_LEN or data[0] != OPCODE_REVIVE_SYNC:
		return {}
	if data[1] > REVIVE_COMPLETED or data[2] > 100 or data[3] != 0 or data[14] != 0 or data[15] != 0:
		return {}
	var r := StreamPeerBuffer.new()
	r.big_endian = false
	r.data_array = data.slice(0, REVIVE_SYNC_LEN)
	r.seek(4)
	var downed := r.get_u32()
	var reviver := r.get_u32()
	var hp := r.get_u16()
	return {
		"state": int(data[1]),
		"progress_pct": int(data[2]),
		"downed_player_id": downed,
		"reviver_player_id": reviver,
		"health_restored": hp,
	}


## "07.4s": dos dígitos enteros y una décima, como el HUD de extracción.
static func format_countdown(remaining_ms: float) -> String:
	var sec := maxf(remaining_ms, 0.0) / 1000.0
	return "%04.1fs" % sec


## Histéresis espacial (misma máquina que ConvoyOccupant::step en Rust, sin progreso):
## entra a r_in, solo sale más allá de r_out = r_in + 1.5 m.
static func hysteresis_inside(was_inside: bool, dist: float, radius: float) -> bool:
	if was_inside:
		return dist <= radius + CONVOY_EXIT_CUSHION
	return dist <= radius
