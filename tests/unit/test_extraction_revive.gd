extends SceneTree
## Headless unit test — Fase 9.7 (ADR 099 convoy de extracción móvil / ADR 100 reanimación [F]).
## Run: Godot --headless --path clients/godot-mmo-client -s res://tests/unit/test_extraction_revive.gd
## Exit code 0 = all pass.

const Codec = preload("res://shared-core/ExtractionReviveCodec.gd")
const ReviveInteraction = preload("res://shared-core/ReviveInteraction.gd")
const MobileExtractionConvoy = preload("res://world/MobileExtractionConvoy.gd")
const ExtractionConvoyHUD = preload("res://ui/components/ExtractionHUD/ExtractionConvoyHUD.gd")
const ReviveProgressModal = preload("res://ui/modals/ReviveProgressModal.gd")
const RevivePlasmaBeam3D = preload("res://world/RevivePlasmaBeam3D.gd")
const MarketplaceWindow = preload("res://ui/windows/MarketplaceWindow/MarketplaceWindow.gd")

## Vectores dorados idénticos a los de runtimes/mmo-world/src/protocol.rs.
const GOLDEN_BEACON := [28, 68, 51, 34, 17, 0, 0, 72, 65, 0, 0, 128, 63, 0, 0, 33, 194, 0, 0, 32, 65, 232, 28, 131]
const GOLDEN_REVIVE := [29, 2, 65, 0, 13, 12, 11, 10, 77, 0, 0, 0, 52, 18, 0, 0]

var _fails: Array[String] = []
var _checks := 0


func check(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_fails.append(msg)
		printerr("  FAIL: ", msg)
	else:
		print("  PASS: ", msg)


func _initialize() -> void:
	_run.call_deferred()


func _bytes(arr: Array) -> PackedByteArray:
	var p := PackedByteArray()
	for v in arr:
		p.append(v)
	return p


func _run() -> void:
	print("== [TEST] Fase 9.7 — Extracción en caravana y reanimación [F] ==")
	_test_beacon_codec()
	_test_revive_codec()
	_test_fuzz()
	_test_countdown_and_hysteresis()
	await _test_convoy_node()
	await _test_hud_and_modal()
	await _test_revive_priority()
	await _test_plasma_beam()
	_test_escrow_parity()

	print("\n== RESULTADOS ==")
	print("== %d checks, %d fallos ==" % [_checks, _fails.size()])
	quit(0 if _fails.is_empty() else 1)


func _test_beacon_codec() -> void:
	print("\n--- 0x1C EXTRACTION_BEACON_SYNC ---")
	var b := {"beacon_id": 0x11223344, "pos": Vector3(12.5, 1.0, -40.25), "radius": 10.0,
		"remaining_ms": 7400, "players_inside_count": 3, "is_panic": true}
	var pkt := Codec.encode_beacon(b)
	check(pkt.size() == 24, "0x1C mide exactamente 24 bytes")
	check(pkt == _bytes(GOLDEN_BEACON), "0x1C byte a byte igual al vector dorado de Rust")
	var d := Codec.decode_beacon(pkt)
	check(d.get("beacon_id") == 0x11223344 and d.get("pos") == Vector3(12.5, 1.0, -40.25), "0x1C roundtrip id/pos")
	check(d.get("remaining_ms") == 7400 and d.get("players_inside_count") == 3 and d.get("is_panic") == true, "0x1C roundtrip remaining/count/panic")
	check(Codec.decode_beacon(pkt.slice(0, 23)).is_empty(), "0x1C truncado a 23 B rechazado")
	var bad := pkt.duplicate()
	bad.encode_float(17, 0.0)
	check(Codec.decode_beacon(bad).is_empty(), "0x1C con radio 0 rechazado")
	bad = pkt.duplicate()
	bad.encode_float(5, NAN)
	check(Codec.decode_beacon(bad).is_empty(), "0x1C con pos NaN rechazado")
	var many := Codec.encode_beacon({"players_inside_count": 999, "radius": 4.0})
	var dm := Codec.decode_beacon(many)
	check(dm.get("players_inside_count") == 127 and dm.get("is_panic") == false, "count satura a 127 sin invadir el bit de pánico")


func _test_revive_codec() -> void:
	print("\n--- 0x1D REVIVE_SYNC ---")
	var s := {"state": Codec.REVIVE_COMPLETED, "progress_pct": 65, "downed_player_id": 0x0A0B0C0D,
		"reviver_player_id": 77, "health_restored": 0x1234}
	var pkt := Codec.encode_revive(s)
	check(pkt.size() == 16, "0x1D mide exactamente 16 bytes")
	check(pkt == _bytes(GOLDEN_REVIVE), "0x1D byte a byte igual al vector dorado de Rust")
	var d := Codec.decode_revive(pkt)
	check(d == s, "0x1D roundtrip completo")
	for case in [[1, 3], [2, 101], [3, 1], [14, 1], [15, 255]]:
		var bad := pkt.duplicate()
		bad[case[0]] = case[1]
		check(Codec.decode_revive(bad).is_empty(), "0x1D byte %d = %d rechazado" % case)
	check(Codec.decode_revive(pkt.slice(0, 15)).is_empty(), "0x1D truncado rechazado")
	var req := Codec.decode_revive(Codec.encode_revive({"state": Codec.REVIVE_INTERRUPTED, "downed_player_id": 605}))
	check(req["state"] == 1 and req["reviver_player_id"] == 0, "petición de cancelación: reviver_id viaja en 0 (lo fija el servidor)")


func _test_fuzz() -> void:
	print("\n--- Fuzz 20,000 buffers (cliente) ---")
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x97
	var ok := true
	var accepted := 0
	for i in range(20000):
		var n := rng.randi_range(0, 32)
		var buf := PackedByteArray()
		buf.resize(n)
		for j in range(n):
			buf[j] = rng.randi_range(0, 255)
		if n > 0:
			buf[0] = Codec.OPCODE_EXTRACTION_BEACON_SYNC if i % 2 == 0 else Codec.OPCODE_REVIVE_SYNC
		var b := Codec.decode_beacon(buf)
		if not b.is_empty():
			accepted += 1
			ok = ok and Codec.encode_beacon(b) == buf.slice(0, 24)
		var r := Codec.decode_revive(buf)
		if not r.is_empty():
			accepted += 1
			ok = ok and Codec.encode_revive(r) == buf.slice(0, 16)
	check(ok, "Todo buffer aceptado se re-codifica byte a byte idéntico")
	check(accepted > 100, "El fuzz también ejercita la ruta de aceptación (%d)" % accepted)


func _test_countdown_and_hysteresis() -> void:
	print("\n--- Cuenta atrás e histéresis ---")
	check(Codec.format_countdown(7400) == "07.4s", "7400 ms -> '07.4s'")
	check(Codec.format_countdown(10000) == "10.0s", "10000 ms -> '10.0s'")
	check(Codec.format_countdown(-5) == "00.0s", "negativo -> '00.0s'")
	check(not Codec.hysteresis_inside(false, 10.5, 10.0), "fuera: 10.5 m no entra (r_in = 10)")
	check(Codec.hysteresis_inside(false, 10.0, 10.0), "fuera: 10.0 m entra")
	check(Codec.hysteresis_inside(true, 11.5, 10.0), "dentro: 11.5 m sigue dentro (r_out = 11.5)")
	check(not Codec.hysteresis_inside(true, 11.6, 10.0), "dentro: 11.6 m sale")
	check(Codec.hysteresis_inside(true, 5.5, 4.0) and not Codec.hysteresis_inside(true, 5.6, 4.0), "pánico: r_out = 5.5 m")


func _test_convoy_node() -> void:
	print("\n--- MobileExtractionConvoy (3D) ---")
	var scene: PackedScene = load("res://world/MobileExtractionConvoy.tscn")
	check(scene != null, "MobileExtractionConvoy.tscn carga")
	var c: MobileExtractionConvoy = scene.instantiate()
	root.add_child(c)
	await process_frame
	var rings := c.get_node_or_null("CaptureRings")
	check(rings != null and rings.get_parent() == c, "CaptureRings es nodo 3D hijo nativo del convoy (se mueve con él)")
	check(c.get_ring_count() == 3, "3 anillos concéntricos")
	check(is_equal_approx(c.get_outer_ring_radius(), 10.0), "anillo exterior a 10 m")
	check(c.get_ring_color() == Color("#00f0ff"), "anillos cian #00f0ff en normal")
	check(c.get_node_or_null("BeaconMast") != null and c.get_node_or_null("BeaconLight") != null, "baliza vertical con luz")
	c.apply_beacon_sync({"beacon_id": 9701, "pos": Vector3(4, 0, -6), "radius": 4.0, "remaining_ms": 7400, "players_inside_count": 1, "is_panic": true})
	await process_frame
	check(c.is_panic and is_equal_approx(c.get_outer_ring_radius(), 4.0), "pánico: radio contraído a 4 m")
	check(c.get_ring_color() != Color("#00f0ff"), "pánico: anillos ámbar/rojo")
	check(c.global_position.distance_to(Vector3(4, 0, -6)) < 0.01, "primer sync coloca el convoy en la posición del servidor")
	check(c.remaining_ms <= 7400.0 and c.remaining_ms > 7000.0, "cuenta atrás se descuenta localmente entre syncs")
	c.apply_beacon_sync({"beacon_id": 9701, "pos": Vector3(14, 0, -6), "radius": 10.0, "remaining_ms": 0, "is_panic": false})
	for i in range(5):
		await process_frame
	check(c.global_position.x > 4.0 and c.global_position.x < 14.0, "interpolación suave hacia la nueva posición (sin teletransporte)")
	check(c.is_inside(c.global_position + Vector3(10.0, 0, 0), false), "is_inside usa r_in = 10 m")
	check(c.is_inside(c.global_position + Vector3(11.4, 0, 0), true), "is_inside usa r_out = 11.5 m si ya estaba dentro")
	c.queue_free()


func _test_hud_and_modal() -> void:
	print("\n--- HUD de extracción y modal de reanimación ---")
	var hud: ExtractionConvoyHUD = ExtractionConvoyHUD.new()
	root.add_child(hud)
	await process_frame
	check(not hud.visible, "HUD oculto sin canalización")
	hud.apply_beacon({"remaining_ms": 7400, "radius": 10.0, "players_inside_count": 2, "is_panic": false})
	check(hud.visible, "HUD visible al canalizar")
	check(hud.get_title_text() == "CONVOY DE EXTRACCIÓN EN MOVIMIENTO - TIEMPO RESTANTE: 07.4s", "Título exacto con '07.4s'")
	check(is_equal_approx(hud.get_progress(), 0.26), "Barra al 26% (2.6 s de 10 s)")
	hud.queue_free()

	var modal: ReviveProgressModal = ReviveProgressModal.new()
	root.add_child(modal)
	await process_frame
	check(ReviveProgressModal.format_label("Kaelen", 65) == "Reanimando a Kaelen [65%]", "Rótulo 'Reanimando a Kaelen [65%]'")
	modal.apply_revive_sync({"state": Codec.REVIVE_STARTED, "downed_player_id": 605, "progress_pct": 0}, "Kaelen")
	check(modal.visible and modal.is_channelling and modal.target_name == "Kaelen", "Started abre la canalización")
	modal.set_progress_pct(65)
	check(modal.get_label_text() == "Reanimando a Kaelen [65%]", "Progreso 65% reflejado en el rótulo")
	var results: Array = []
	modal.finished.connect(func(ok): results.append(ok))
	modal.apply_revive_sync({"state": Codec.REVIVE_INTERRUPTED})
	check(not modal.is_channelling and modal.was_interrupted and results == [false], "Interrupted cierra en rojo")
	modal.apply_revive_sync({"state": Codec.REVIVE_STARTED, "downed_player_id": 605}, "Kaelen")
	modal.apply_revive_sync({"state": Codec.REVIVE_COMPLETED})
	check(modal.get_progress_pct() == 100 and results == [false, true], "Completed llena el anillo al 100%")
	check(is_equal_approx(modal.duration_sec, 6.0), "Canalización de 6 s (120 ticks)")
	modal.queue_free()

	var plate_scene: PackedScene = load("res://ui/screenspace/WorldNameplate.tscn")
	var plate = plate_scene.instantiate()
	root.add_child(plate)
	await process_frame
	plate.setup("Kaelen", 0.0, 1100.0, false, "‹ ALIADO ›", 18)
	check(not plate.visible, "Nameplate: 0 HP sin estado abatido se oculta (muerte)")
	plate.set_downed(17.2)
	check(plate.visible and plate.is_downed, "Nameplate: abatido sigue visible a 0 HP")
	check(plate.title_label.text == "ABATIDO 18s", "Nameplate: 'ABATIDO 18s' (ceil del sangrado)")
	plate.queue_free()


func _make_node(pos: Vector3, group: String, with_interact: bool = false) -> Node3D:
	var n: Node3D
	if with_interact:
		var s := GDScript.new()
		s.source_code = "extends Node3D\nvar used := 0\nfunc interact(_p):\n\tused += 1\n"
		s.reload()
		n = Node3D.new()
		n.set_script(s)
	else:
		n = Node3D.new()
	root.add_child(n)
	n.global_position = pos
	n.add_to_group(group)
	return n


func _test_revive_priority() -> void:
	print("\n--- Prioridad de [F]: reanimar > cofre / DeathEcho ---")
	var chest := _make_node(Vector3(0.8, 0, 0), ReviveInteraction.INTERACT_GROUP, true)
	var echo := _make_node(Vector3(0, 0, 0.5), ReviveInteraction.INTERACT_GROUP, true)
	var kaelen := _make_node(Vector3(2.4, 0, 0), ReviveInteraction.DOWNED_GROUP)
	kaelen.set_meta("session_id", 605)
	await process_frame
	var r := ReviveInteraction.resolve_in_tree(self, Vector3.ZERO)
	check(r["kind"] == "revive" and r["node"] == kaelen, "Aliado a 2.4 m gana a cofre (0.8 m) y DeathEcho (0.5 m)")
	check(ReviveInteraction.session_id_of(kaelen) == 605, "session_id del abatido resuelto")
	kaelen.global_position = Vector3(2.6, 0, 0)
	r = ReviveInteraction.resolve_in_tree(self, Vector3.ZERO)
	check(r["kind"] == "interact" and r["node"] == echo, "Aliado a 2.6 m (fuera de 2.5 m): [F] cae al interactuable más cercano")
	kaelen.global_position = Vector3(2.5, 0, 0)
	check(ReviveInteraction.resolve_in_tree(self, Vector3.ZERO)["kind"] == "revive", "Exactamente 2.5 m es alcance válido")
	for n in [chest, echo, kaelen]:
		n.queue_free()
	await process_frame
	check(ReviveInteraction.resolve_in_tree(self, Vector3.ZERO)["kind"] == "none", "Sin objetivos: 'none'")

	# Player real: handle_interact_pressed consume [F] para reanimar y NO toca el cofre.
	var player_scene: PackedScene = load("res://player.tscn")
	var player: CharacterBody3D = player_scene.instantiate()
	root.add_child(player)
	player.set_process_input(false)
	await process_frame
	player.global_position = Vector3(50, 1, 50)
	var chest2 := _make_node(Vector3(50.5, 1, 50), ReviveInteraction.INTERACT_GROUP, true)
	var ally := _make_node(Vector3(52, 1, 50), ReviveInteraction.DOWNED_GROUP)
	ally.set_meta("session_id", 777)
	var requested: Array = []
	player.revive_requested.connect(func(n): requested.append(n))
	var consumed: bool = player.handle_interact_pressed()
	check(consumed and player.reviving_sid == 777 and requested == [ally], "Player: [F] inicia la reanimación y consume el evento")
	for i in range(30):
		await physics_frame
	check(player.is_crouching and player.get_node("MeshInstance3D").scale.y < 0.8, "Player: se arrodilla mientras canaliza la reanimación")
	check(chest2.used == 0, "Player: el cofre NO recibe la pulsación")
	var released: Array = []
	player.revive_released.connect(func(sid): released.append(sid))
	player.handle_interact_released()
	check(player.reviving_sid == 0 and released == [777], "Player: soltar [F] cancela (0x1D state=1)")
	ally.queue_free()
	await process_frame
	consumed = player.handle_interact_pressed()
	check(not consumed and chest2.used == 1, "Player: sin aliado abatido, [F] abre el cofre")
	player.is_pinned = true
	player.velocity = Vector3(5, 0, 0)
	await physics_frame
	await physics_frame
	check(player.velocity == Vector3.ZERO, "Player: is_pinned congela la velocidad del abatido")
	player.queue_free()
	chest2.queue_free()


func _test_plasma_beam() -> void:
	print("\n--- Haz de plasma verde ---")
	var a := Node3D.new()
	var b := Node3D.new()
	root.add_child(a)
	root.add_child(b)
	a.global_position = Vector3(0, 0, 0)
	b.global_position = Vector3(2, 0, 0)
	var beam: RevivePlasmaBeam3D = RevivePlasmaBeam3D.new()
	root.add_child(beam)
	beam.setup(a, b)
	await process_frame
	var pa := Vector3(0, 0, 0) + beam.source_offset
	var pb := Vector3(2, 0, 0) + beam.target_offset
	check(absf(beam.get_length() - pa.distance_to(pb)) < 0.001, "Longitud del haz = distancia entre pecho y abatido")
	check(beam.global_position.distance_to((pa + pb) * 0.5) < 0.01, "Haz centrado entre ambos")
	check(RevivePlasmaBeam3D.COLOR_PLASMA == Color("#3dff8a"), "Plasma verde #3dff8a")
	b.global_position = Vector3(0, 0, 2)
	await process_frame
	check(beam.global_position.z > 0.9, "El haz sigue a los personajes cada frame")
	for n in [a, b, beam]:
		n.queue_free()


func _test_escrow_parity() -> void:
	print("\n--- Custodia: aritmética entera del backend Go ---")
	var ok := true
	for total in [1, 19, 20, 21, 99, 100, 1200, 12345, 999999, 2147483647]:
		var fee: int = MarketplaceWindow.listing_deposit(total)
		ok = ok and fee == (total * 5) / 100
		var sp: Dictionary = MarketplaceWindow.escrow_split(total)
		ok = ok and sp["fee"] == fee and sp["fee"] + sp["net"] == total
	check(ok, "listing_deposit == floor(price * 5 / 100) y fee + net == price")
	check(MarketplaceWindow.listing_deposit(19) == 0, "19 silver -> depósito 0 (antes ceil/min 1 daba 1)")
	check(MarketplaceWindow.listing_deposit(1200) == 60, "1200 silver -> 60")
	check(MarketplaceWindow.listing_deposit(0) == 0 and MarketplaceWindow.listing_deposit(-5) == 0, "<= 0 -> 0")
