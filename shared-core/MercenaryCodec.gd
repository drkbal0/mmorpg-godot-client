extends RefCounted

## MercenaryCodec.gd — Codec Little-Endian de los paquetes de la Fase 10 (ADR 101).
## Espejo exacto de runtimes/mmo-world/src/protocol.rs (mismas reglas de rechazo).
##
## 0x1E MERCENARY_SYNC (16 bytes, ADR 101):
##   [0x1E][role u8][stance u8][hp_pct u8][mercenary_id u32 LE][owner_sid u32 LE][target_entity_id u32 LE]
##
## Constantes de Rol:
##   0 = GUARDIAN
##   1 = HEALER
##   2 = RANGER
##
## Constantes de Postura Táctica:
##   0 = FOLLOW
##   1 = ATTACK_TARGET
##   2 = HOLD_POSITION

const OPCODE_MERCENARY_SYNC := 0x1E
const MERCENARY_SYNC_LEN := 16

const ROLE_GUARDIAN := 0
const ROLE_HEALER := 1
const ROLE_RANGER := 2

const STANCE_FOLLOW := 0
const STANCE_ATTACK := 1
const STANCE_HOLD := 2

## Distancias de anclaje (ADR 101)
const TETHER_RADIUS_M := 10.0
const HARD_LEASH_RADIUS_M := 15.0
const SNAPBACK_RADIUS_M := 35.0

## Golden vector compartido byte-a-byte con Rust (protocol.rs / tests)
const GOLDEN_VECTOR := [30, 0, 0, 95, 233, 3, 0, 0, 42, 0, 0, 0, 208, 7, 0, 0]


static func encode_mercenary(m: Dictionary) -> PackedByteArray:
	var w := StreamPeerBuffer.new()
	w.big_endian = false
	w.put_u8(OPCODE_MERCENARY_SYNC)
	w.put_u8(clampi(int(m.get("role", ROLE_GUARDIAN)), 0, ROLE_RANGER))
	w.put_u8(clampi(int(m.get("stance", STANCE_FOLLOW)), 0, STANCE_HOLD))
	w.put_u8(clampi(int(m.get("hp_pct", 100)), 0, 100))
	w.put_u32(int(m.get("mercenary_id", 0)))
	w.put_u32(int(m.get("owner_sid", 0)))
	w.put_u32(int(m.get("target_entity_id", 0)))
	return w.data_array


static func decode_mercenary(data: PackedByteArray) -> Dictionary:
	if data.size() < MERCENARY_SYNC_LEN or data[0] != OPCODE_MERCENARY_SYNC:
		return {}
	if data[1] > ROLE_RANGER or data[2] > STANCE_HOLD or data[3] > 100:
		return {}
	var r := StreamPeerBuffer.new()
	r.big_endian = false
	r.data_array = data
	r.get_u8() # opcode
	var role := r.get_u8()
	var stance := r.get_u8()
	var hp_pct := r.get_u8()
	var mercenary_id := r.get_u32()
	var owner_sid := r.get_u32()
	var target_entity_id := r.get_u32()
	return {
		"role": role,
		"stance": stance,
		"hp_pct": hp_pct,
		"mercenary_id": mercenary_id,
		"owner_sid": owner_sid,
		"target_entity_id": target_entity_id,
	}


static func role_to_string(role: int) -> String:
	match role:
		ROLE_HEALER:
			return "Sanador"
		ROLE_RANGER:
			return "Tirador"
		_:
			return "Guardián"


static func stance_to_string(stance: int) -> String:
	match stance:
		STANCE_ATTACK:
			return "Atacar"
		STANCE_HOLD:
			return "Defensiva"
		_:
			return "Seguir"

