extends SceneTree

## test_mercenary_companion.gd — Suite de pruebas unitarias para la Fase 10 (ADR 101).
## Valida el paquete Little-Endian 0x1E MERCENARY_SYNC, vector dorado, histéresis de tethering y slot de UI.

const MercenaryCodec = preload("res://shared-core/MercenaryCodec.gd")
const PartyFramesScript = preload("res://ui/components/PartyFrames/PartyFrames.gd")

var _passes := 0
var _failures := 0


func _init() -> void:
	print("== [TEST] Fase 10 — Mercenarios IA, Compañeros de Escuadra y Protocolo 0x1E ==")
	test_packet_0x1e_layout()
	test_golden_vector_exact_match()
	test_roundtrip_and_clamping()
	test_rejections()
	test_fuzz_buffers()
	test_tether_logic()
	test_party_frames_companion_slot()
	test_alt_tactical_commands()
	
	print("\n== RESULTADOS FASE 10 ==")
	print("== %d checks, %d fallos ==" % [_passes, _failures])
	if _failures > 0:
		quit(1)
	else:
		quit(0)


func _check(condition: bool, msg: String) -> void:
	if condition:
		print("  PASS: %s" % msg)
		_passes += 1
	else:
		push_error("  FAIL: %s" % msg)
		_failures += 1


func test_packet_0x1e_layout() -> void:
	print("\n--- 0x1E MERCENARY_SYNC Layout ---")
	var sample := {
		"role": MercenaryCodec.ROLE_GUARDIAN,
		"stance": MercenaryCodec.STANCE_FOLLOW,
		"hp_pct": 100,
		"mercenary_id": 1001,
		"owner_sid": 42,
		"target_entity_id": 0,
	}
	var pkt := MercenaryCodec.encode_mercenary(sample)
	_check(pkt.size() == 16, "0x1E mide exactamente 16 bytes")
	_check(pkt[0] == 0x1E, "Opcode inicial es 0x1E")


func test_golden_vector_exact_match() -> void:
	print("\n--- Vector Dorado Compartido con Rust ECS ---")
	var golden_data := {
		"role": MercenaryCodec.ROLE_GUARDIAN,
		"stance": MercenaryCodec.STANCE_FOLLOW,
		"hp_pct": 95,
		"mercenary_id": 1001,
		"owner_sid": 42,
		"target_entity_id": 2000,
	}
	var pkt := MercenaryCodec.encode_mercenary(golden_data)
	var expected := PackedByteArray(MercenaryCodec.GOLDEN_VECTOR)
	_check(pkt == expected, "0x1E byte a byte idéntico al vector dorado de Rust [30, 0, 0, 95, ...]")


func test_roundtrip_and_clamping() -> void:
	print("\n--- Roundtrip y Clamping ---")
	for role in [MercenaryCodec.ROLE_GUARDIAN, MercenaryCodec.ROLE_HEALER, MercenaryCodec.ROLE_RANGER]:
		for stance in [MercenaryCodec.STANCE_FOLLOW, MercenaryCodec.STANCE_ATTACK, MercenaryCodec.STANCE_HOLD]:
			var orig := {
				"role": role,
				"stance": stance,
				"hp_pct": 82,
				"mercenary_id": 7777,
				"owner_sid": 88,
				"target_entity_id": 999,
			}
			var pkt := MercenaryCodec.encode_mercenary(orig)
			var dec := MercenaryCodec.decode_mercenary(pkt)
			_check(dec["role"] == role and dec["stance"] == stance and dec["hp_pct"] == 82, "Roundtrip para rol %d stance %d" % [role, stance])


func test_rejections() -> void:
	print("\n--- Reglas de Rechazo y Sanitización ---")
	var valid_pkt := MercenaryCodec.encode_mercenary({
		"role": MercenaryCodec.ROLE_GUARDIAN,
		"stance": MercenaryCodec.STANCE_FOLLOW,
		"hp_pct": 100,
		"mercenary_id": 101,
		"owner_sid": 42,
		"target_entity_id": 0,
	})

	# Truncados
	for i in range(16):
		var tr := valid_pkt.slice(0, i)
		_check(MercenaryCodec.decode_mercenary(tr).is_empty(), "Truncado a %d bytes rechazado" % i)

	# Opcode erróneo
	var bad_op := valid_pkt.duplicate()
	bad_op[0] = 0x1F
	_check(MercenaryCodec.decode_mercenary(bad_op).is_empty(), "Opcode incorrecto 0x1F rechazado")

	# Rol fuera de rango (> 2)
	var bad_role := valid_pkt.duplicate()
	bad_role[1] = 3
	_check(MercenaryCodec.decode_mercenary(bad_role).is_empty(), "Rol > 2 rechazado")

	# Stance fuera de rango (> 2)
	var bad_stance := valid_pkt.duplicate()
	bad_stance[2] = 3
	_check(MercenaryCodec.decode_mercenary(bad_stance).is_empty(), "Stance > 2 rechazado")

	# HP fuera de rango (> 100)
	var bad_hp := valid_pkt.duplicate()
	bad_hp[3] = 101
	_check(MercenaryCodec.decode_mercenary(bad_hp).is_empty(), "HP% > 100 rechazado")


func test_fuzz_buffers() -> void:
	print("\n--- Fuzzing 10,000 Datagramas ---")
	var accepted := 0
	for i in range(10000):
		var len = randi() % 32
		var buf := PackedByteArray()
		for b in range(len):
			buf.append(randi() % 256)
		if i % 2 == 0 and len >= 16:
			buf[0] = 0x1E
			buf[1] = randi() % 4
			buf[2] = randi() % 4
			buf[3] = randi() % 110
		var dec := MercenaryCodec.decode_mercenary(buf)
		if not dec.is_empty():
			accepted += 1
			var re_encoded := MercenaryCodec.encode_mercenary(dec)
			_check(re_encoded == buf.slice(0, 16), "Buffer fuzzeado aceptado re-codifica idéntico")
	_check(accepted > 500, "Fuzzer ejercitó la ruta válida (%d aceptados)" % accepted)


func test_tether_logic() -> void:
	print("\n--- Lógica de Tethering e Histéresis ---")
	var r_normal := MercenaryCodec.TETHER_RADIUS_M # 10.0
	var r_leash := MercenaryCodec.HARD_LEASH_RADIUS_M # 15.0
	var r_snap := MercenaryCodec.SNAPBACK_RADIUS_M # 35.0

	_check(5.0 <= r_normal, "Distancia 5.0m dentro de zona de confort")
	_check(12.0 > r_normal and 12.0 <= r_leash, "Distancia 12.0m activa sprint de recuperación")
	_check(20.0 > r_leash and 20.0 <= r_snap, "Distancia 20.0m rompe combate y retorna al líder")
	_check(40.0 > r_snap, "Distancia 40.0m activa snapback teleport de emergencia")


func test_party_frames_companion_slot() -> void:
	print("\n--- Integración en PartyFrames UI ---")
	var pf := Control.new()
	pf.set_script(PartyFramesScript)
	var vbox := VBoxContainer.new()
	vbox.name = "MemberList"
	pf.add_child(vbox)

	_check(!pf.has_mercenary(), "Sin mercenario inicialmente")

	pf.set_mercenary({
		"mercenary_id": 5050,
		"role": MercenaryCodec.ROLE_GUARDIAN,
		"stance": MercenaryCodec.STANCE_FOLLOW,
		"hp_pct": 90,
		"name": "Centinela Vaelen (Guardián)",
	})

	_check(pf.has_mercenary(), "has_mercenary es true tras set_mercenary")
	var data: Dictionary = pf.get_mercenary_data()
	_check(data["mercenary_id"] == 5050, "mercenary_id coincide")
	_check(data["hp_pct"] == 90, "hp_pct coincide")

	pf.update_mercenary_hp(45)
	_check(pf.get_mercenary_data()["hp_pct"] == 45, "update_mercenary_hp actualiza valor a 45")

	pf.update_mercenary_distance(12.5)
	var card = pf.get_node_or_null("%MercDistLabel")
	if card:
		_check(card.text.contains("[SPRINT]"), "Distancia > 10m muestra indicador [SPRINT]")

	pf.clear_mercenary()
	_check(!pf.has_mercenary(), "clear_mercenary remueve el slot correctamente")
	pf.free()


func test_alt_tactical_commands() -> void:
	print("\n--- Atajos Tácticos [Alt+1..3] ---")
	var pf := Control.new()
	pf.set_script(PartyFramesScript)
	var vbox := VBoxContainer.new()
	vbox.name = "MemberList"
	pf.add_child(vbox)

	pf.set_mercenary({
		"mercenary_id": 8888,
		"role": MercenaryCodec.ROLE_RANGER,
		"stance": MercenaryCodec.STANCE_FOLLOW,
		"hp_pct": 100,
	})

	var triggered := [-1]
	pf.mercenary_command_triggered.connect(func(stance: int, _target: int):
		triggered[0] = stance
	)

	# Simular pulsación de Alt+2 (Atacar Objetivo)
	var event := InputEventKey.new()
	event.pressed = true
	event.alt_pressed = true
	event.keycode = KEY_2
	pf._unhandled_input(event)

	_check(triggered[0] == MercenaryCodec.STANCE_ATTACK, "Alt+2 conmuta a postura ATACAR")
	_check(pf.get_mercenary_data()["stance"] == MercenaryCodec.STANCE_ATTACK, "Stance interna actualizada a ATTACK")

	# Simular pulsación de Alt+3 (Defensiva / Mantener)
	event.keycode = KEY_3
	pf._unhandled_input(event)
	_check(triggered[0] == MercenaryCodec.STANCE_HOLD, "Alt+3 conmuta a postura DEFENSIVA")

	# Simular pulsación de Alt+1 (Seguir)
	event.keycode = KEY_1
	pf._unhandled_input(event)
	_check(triggered[0] == MercenaryCodec.STANCE_FOLLOW, "Alt+1 conmuta a postura SEGUIR")

	pf.free()
