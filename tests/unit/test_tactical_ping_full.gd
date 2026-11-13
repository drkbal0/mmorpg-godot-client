extends SceneTree
## Headless test — UX completo de la Rueda de Pings Tácticos [G] + Auras 3D (ADR 097).
## Run: Godot --headless --path clients/godot-mmo-client -s res://tests/unit/test_tactical_ping_full.gd
## Exit code 0 = all pass.

const TacticalPingWheel = preload("res://ui/components/TacticalPing/TacticalPingWheel.gd")
const TacticalPingBeam3D = preload("res://world/TacticalPingBeam3D.gd")
const TacticalPingCodec = preload("res://shared-core/TacticalPingCodec.gd")

const PT = TacticalPingWheel.PingType

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


func _key_g(pressed: bool, echo: bool = false) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = KEY_G
	ev.pressed = pressed
	ev.echo = echo
	return ev


func _mouse_button(button: int, pressed: bool, pos: Vector2 = Vector2.ZERO) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = pressed
	ev.position = pos
	return ev


func _run() -> void:
	print("== [TEST] Tactical Ping UX + Auras 3D (ADR 097) ==")

	# ------------------------------------------------------------------
	print("\n--- 1. Apertura de la rueda en coordenadas del cursor ---")
	var wheel: TacticalPingWheel = (load("res://ui/components/TacticalPing/TacticalPingWheel.tscn") as PackedScene).instantiate()
	root.add_child(wheel)
	await process_frame
	check(wheel.visible == false and wheel.is_active == false, "Rueda inicia oculta e inactiva")
	check(TacticalPingWheel.DEADZONE == 35.0, "DEADZONE = 35 px")
	wheel.open_at(Vector2(400, 300))
	check(wheel.visible and wheel.is_active, "open_at muestra y activa la rueda")
	check(wheel.open_screen_pos == Vector2(400, 300), "open_screen_pos registra el cursor (400,300)")
	check(wheel.global_position + wheel.wheel_center == Vector2(400, 300), "La rueda queda centrada en el cursor")
	check(wheel.active_selection == PT.NONE, "Sin selección al abrir")

	# ------------------------------------------------------------------
	print("\n--- 2. Cuadrantes (4 ángulos) y DEADZONE ---")
	check(TacticalPingWheel.get_quadrant_from_angle(-PI * 0.5) == PT.DANGER, "-90° (Norte) -> PELIGRO")
	check(TacticalPingWheel.get_quadrant_from_angle(PI) == PT.MISSING, "180° (Oeste) -> DESAPARECIDO")
	check(TacticalPingWheel.get_quadrant_from_angle(0.0) == PT.ON_MY_WAY, "0° (Este) -> EN CAMINO")
	check(TacticalPingWheel.get_quadrant_from_angle(PI * 0.5) == PT.ASSIST, "90° (Sur) -> ASISTIR")
	check(TacticalPingWheel.get_quadrant_from_angle(-PI) == PT.MISSING, "-180° (Oeste) -> DESAPARECIDO")

	var c := Vector2(400, 300)
	check(wheel.update_selection_from_screen(c + Vector2(0, -20)) == PT.NONE, "Arrastre 20 px (< DEADZONE) -> sin selección")
	check(wheel.update_selection_from_screen(c + Vector2(0, -35)) == PT.NONE, "Arrastre 35 px (= DEADZONE) -> sin selección")
	check(wheel.update_selection_from_screen(c + Vector2(0, -60)) == PT.DANGER, "Arrastre arriba 60 px -> PELIGRO")
	check(wheel.update_selection_from_screen(c + Vector2(-60, 0)) == PT.MISSING, "Arrastre izquierda 60 px -> DESAPARECIDO")
	check(wheel.update_selection_from_screen(c + Vector2(60, 0)) == PT.ON_MY_WAY, "Arrastre derecha 60 px -> EN CAMINO")
	check(wheel.update_selection_from_screen(c + Vector2(0, 60)) == PT.ASSIST, "Arrastre abajo 60 px -> ASISTIR")
	check(wheel.active_selection == PT.ASSIST, "active_selection refleja el último cuadrante")

	# Configuración visual / sonora por cuadrante
	check(TacticalPingWheel.get_ping_color(PT.DANGER) == Color("#ff3344"), "PELIGRO rojo #ff3344")
	check(TacticalPingWheel.get_ping_color(PT.MISSING) == Color("#facc15"), "DESAPARECIDO amarillo #facc15")
	check(TacticalPingWheel.get_ping_color(PT.ON_MY_WAY) == Color("#10b981"), "EN CAMINO verde #10b981")
	check(TacticalPingWheel.get_ping_color(PT.ASSIST) == Color("#0284c7"), "ASISTIR azul #0284c7")
	check(TacticalPingWheel.get_ping_sfx(PT.DANGER) == &"lol_danger", "SFX PELIGRO = lol_danger")
	check(TacticalPingWheel.get_ping_sfx(PT.MISSING) == &"lol_missing", "SFX DESAPARECIDO = lol_missing")
	check(TacticalPingWheel.get_ping_sfx(PT.ON_MY_WAY) == &"lol_omw", "SFX EN CAMINO = lol_omw")
	check(TacticalPingWheel.get_ping_sfx(PT.ASSIST) == &"lol_assist", "SFX ASISTIR = lol_assist")
	var sm := root.get_node_or_null("SoundManager")
	if sm:
		for cue in [&"lol_danger", &"lol_missing", &"lol_omw", &"lol_assist"]:
			check(sm._get_stream(cue) != null, "SoundManager registra el cue '%s'" % cue)

	# ------------------------------------------------------------------
	print("\n--- 3. Confirmación (emite ping_selected + SFX) ---")
	var got := {"type": -99, "name": "", "count": 0, "cancelled": 0}
	wheel.ping_selected.connect(func(t: int, n: String):
		got["type"] = t
		got["name"] = n
		got["count"] += 1
	)
	wheel.cancelled.connect(func(): got["cancelled"] += 1)

	wheel.update_selection_from_screen(c + Vector2(0, -80))
	var confirmed := wheel.close_and_confirm()
	check(confirmed == PT.DANGER, "close_and_confirm retorna PELIGRO")
	check(got["count"] == 1 and got["type"] == PT.DANGER and got["name"] == "PELIGRO", "ping_selected(DANGER, 'PELIGRO') emitido una vez")
	check(wheel.last_sfx_cue == &"lol_danger", "Reproduce SFX lol_danger al confirmar")
	check(not wheel.visible and not wheel.is_active, "Rueda cerrada tras confirmar")
	check(wheel.close_and_confirm() == PT.NONE and got["count"] == 1, "Confirmar con la rueda cerrada no re-emite")

	# Confirmar dentro del DEADZONE = cancelar sin emitir
	wheel.open_at(c)
	wheel.update_selection_from_screen(c + Vector2(5, 5))
	wheel.close_and_confirm()
	check(got["count"] == 1 and got["cancelled"] == 1, "Soltar dentro del DEADZONE cancela sin emitir")

	# Soltar clic izquierdo con cuadrante seleccionado confirma
	wheel.open_at(c)
	wheel._input(_mouse_button(MOUSE_BUTTON_LEFT, false, c + Vector2(-70, 3)))
	check(got["count"] == 2 and got["type"] == PT.MISSING, "Soltar clic izquierdo al Oeste confirma DESAPARECIDO")
	check(wheel.last_sfx_cue == &"lol_missing", "Reproduce SFX lol_missing")

	# ------------------------------------------------------------------
	print("\n--- 4. Cancelación por clic derecho ---")
	wheel.open_at(c)
	wheel.update_selection_from_screen(c + Vector2(80, 0))
	wheel._input(_mouse_button(MOUSE_BUTTON_RIGHT, true, c + Vector2(80, 0)))
	check(not wheel.is_active and not wheel.visible, "Clic derecho cierra la rueda")
	check(got["count"] == 2 and got["cancelled"] == 2, "Clic derecho cancela sin emitir ping_selected")
	check(wheel.active_selection == PT.NONE, "Selección reiniciada tras cancelar")
	wheel.queue_free()
	await process_frame

	# ------------------------------------------------------------------
	print("\n--- 5. UIInputRouter [G] + World.gd: aura y baliza 3D ---")
	var world = (load("res://World.tscn") as PackedScene).instantiate()
	root.add_child(world)
	await process_frame
	check(world.ping_wheel != null, "World crea la TacticalPingWheel")
	check(world.has_method("open_tactical_ping_wheel") and world.has_method("_on_tactical_ping_broadcast"), "World expone API de enrutado y handler 0x1A")

	var cam := Camera3D.new()
	world.add_child(cam)
	cam.position = Vector3(0, 20, 10)
	cam.look_at(Vector3.ZERO)
	cam.make_current()
	var player := Node3D.new()
	player.name = "LocalPlayerStub"
	world.add_child(player)
	world.local_player = player

	# Autoload real (project.godot) — se evita preload: el script referencia otros autoloads.
	var router = root.get_node_or_null("UIInputRouter")
	check(router != null and router.has_method("handle_tactical_ping_input"), "UIInputRouter autoload expone handle_tactical_ping_input")

	var emitted := {"type": -99, "count": 0}
	world.ping_wheel.ping_selected.connect(func(t: int, _n: String):
		emitted["type"] = t
		emitted["count"] += 1
	)

	var cursor := Vector2(640, 360)
	check(router.handle_tactical_ping_input(_key_g(true), world, cursor) == true, "Router: G pulsada consumida")
	check(world.is_tactical_ping_wheel_open(), "Router: G pulsada abre la rueda")
	check(world.ping_wheel.open_screen_pos == cursor, "Router: rueda abierta en el cursor")
	check(router.handle_tactical_ping_input(_key_g(true, true), world, cursor) == true and world.ping_wheel.open_screen_pos == cursor, "Router: eco de G no reabre la rueda")

	var beams_before := _count_beams(world)
	check(router.handle_tactical_ping_input(_key_g(false), world, cursor + Vector2(0, 90)) == true, "Router: G soltada consumida")
	check(not world.is_tactical_ping_wheel_open(), "Router: G soltada cierra la rueda")
	check(emitted["count"] == 1 and emitted["type"] == PT.ASSIST, "Router: arrastre abajo + soltar G confirma ASISTIR")
	check(_count_beams(world) == beams_before + 1, "World: baliza TacticalPingBeam3D proyectada")
	var beam := _last_beam(world)
	check(beam != null and beam.ping_type == PT.ASSIST, "Baliza con ping_type ASISTIR")
	if beam:
		check(absf(beam.position.y) < 0.05, "Baliza en el suelo (y≈0) bajo el cursor")
		var has_light := false
		var has_cyl := false
		for ch in beam.get_children():
			if ch is OmniLight3D:
				has_light = true
			if ch is MeshInstance3D and ch.mesh is CylinderMesh and (ch.material_override as StandardMaterial3D).emission_enabled:
				has_cyl = true
		check(has_light and has_cyl, "Baliza con luz puntual + cilindro emissive")

	var aura := player.get_node_or_null("TacticalPingAura") as MeshInstance3D
	check(aura != null, "Aura temporal instanciada en el jugador local")
	if aura:
		check(aura.mesh is TorusMesh, "Aura con forma de aro (TorusMesh)")
		check(aura.get_meta("ping_color") == Color("#0284c7"), "Aura del color del ping (azul ASISTIR)")
		check(is_equal_approx(float(aura.get_meta("duration")), 2.5), "Aura dura 2.5 s")
		check((aura.material_override as StandardMaterial3D).emission_enabled, "Aura con material emissive")
	check(is_equal_approx(world.PING_BEAM_DURATION, 5.0), "Baliza dura 5 s")

	# Clic derecho vía router con la rueda abierta cancela
	router.handle_tactical_ping_input(_key_g(true), world, cursor)
	check(router.handle_tactical_ping_input(_mouse_button(MOUSE_BUTTON_RIGHT, true), world, cursor) == true, "Router: clic derecho consumido con rueda abierta")
	check(not world.is_tactical_ping_wheel_open() and emitted["count"] == 1, "Router: clic derecho cancela sin emitir")
	check(router.handle_tactical_ping_input(_mouse_button(MOUSE_BUTTON_RIGHT, true), world, cursor) == false, "Router: clic derecho sin rueda no se consume")
	check(router.handle_tactical_ping_input(_key_g(false), world, cursor) == false, "Router: soltar G sin rueda no se consume")

	# ------------------------------------------------------------------
	print("\n--- 6. Red 0x1A: codec + ping remoto ---")
	var pkt := TacticalPingCodec.encode(77, PT.DANGER, Vector3(3.5, 0.0, -8.25), 0)
	check(pkt.size() == 22 and pkt[0] == 0x1A and pkt[5] == PT.DANGER, "Codec: paquete 22 bytes [0x1A]..[type]")
	var dec := TacticalPingCodec.decode(pkt)
	check(dec.get("sender_sid") == 77 and dec.get("ping_type") == PT.DANGER and dec.get("world_pos") == Vector3(3.5, 0.0, -8.25), "Codec: roundtrip LE")
	check(TacticalPingCodec.decode(pkt.slice(0, 21)).is_empty(), "Codec: rechaza paquete truncado")
	var bad := pkt.duplicate()
	bad[5] = 9
	check(TacticalPingCodec.decode(bad).is_empty(), "Codec: rechaza ping_type desconocido")

	var remote := Node3D.new()
	remote.name = "RemoteStub"
	world.add_child(remote)
	world.remote_players[77] = remote
	beams_before = _count_beams(world)
	world._on_tactical_ping_broadcast(dec)
	var r_aura := remote.get_node_or_null("TacticalPingAura")
	check(r_aura != null and r_aura.get_meta("ping_color") == Color("#ff3344"), "Remoto: aura roja en el jugador emisor (sender_sid 77)")
	check(_count_beams(world) == beams_before + 1, "Remoto: baliza 3D proyectada")
	var rb := _last_beam(world)
	check(rb != null and rb.position == Vector3(3.5, 0.0, -8.25) and rb.ping_type == PT.DANGER, "Remoto: baliza en las coordenadas recibidas")
	world._on_tactical_ping_broadcast({"sender_sid": 999, "ping_type": PT.MISSING, "world_pos": Vector3(1, 0, 1)})
	check(_count_beams(world) == beams_before + 2, "Remoto desconocido: baliza sin aura (sin crash)")

	# Limpieza
	world.remote_players.erase(77)
	world.queue_free()
	await process_frame

	print("\n== RESULTADOS ==")
	print("== %d checks, %d fallos ==" % [_checks, _fails.size()])
	quit(0 if _fails.is_empty() else 1)


func _count_beams(world: Node) -> int:
	var n := 0
	for ch in world.get_children():
		if ch is TacticalPingBeam3D and not ch.is_queued_for_deletion():
			n += 1
	return n


func _last_beam(world: Node) -> TacticalPingBeam3D:
	var last: TacticalPingBeam3D = null
	for ch in world.get_children():
		if ch is TacticalPingBeam3D:
			last = ch
	return last
