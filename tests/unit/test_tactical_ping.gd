extends SceneTree
## Headless unit test for Tactical Ping System (Wheel & Marker).
## Run: Godot --headless --path clients/godot-mmo-client -s res://tests/unit/test_tactical_ping.gd
## Exit code 0 = all pass.

const TacticalPingWheel = preload("res://ui/components/TacticalPing/TacticalPingWheel.gd")
const TacticalPingMarker = preload("res://ui/components/TacticalPing/TacticalPingMarker.gd")

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


func _run() -> void:
	print("== [TEST] Tactical Ping Suite Iniciada ==")

	# -------------------------------------------------------------------------
	# 1. Pruebas de TacticalPingWheel (Rueda Radial)
	# -------------------------------------------------------------------------
	print("\n--- 1. Pruebas de TacticalPingWheel ---")
	var wheel_scene: PackedScene = load("res://ui/components/TacticalPing/TacticalPingWheel.tscn")
	check(wheel_scene != null, "TacticalPingWheel.tscn carga correctamente")

	var wheel: TacticalPingWheel = wheel_scene.instantiate() as TacticalPingWheel
	check(wheel != null, "TacticalPingWheel instanciado como clase")
	root.add_child(wheel)
	await process_frame

	check(wheel.custom_minimum_size == Vector2(240, 240), "custom_minimum_size es 240x240")
	check(wheel.visible == false, "Rueda inicia oculta por defecto")

	# Abrir en posición (400, 300)
	wheel.open_at(Vector2(400, 300))
	check(wheel.visible == true, "open_at hace visible la rueda")
	check(wheel.is_active == true, "is_active es true tras abrir")
	check(wheel.global_position == Vector2(280, 180), "Centrado en el punto solicitado (400-120, 300-120)")

	# -------------------------------------------------------------------------
	# 2. Resolución de Cuadrantes Angulares (Disposición LoL Solicitada)
	# -------------------------------------------------------------------------
	print("\n--- 2. Resolución de Cuadrantes Angulares ---")
	# Norte (-90°) -> DANGER (Rojo LoL)
	var q_north = TacticalPingWheel.get_quadrant_from_angle(-PI * 0.5)
	check(q_north == TacticalPingWheel.PingType.DANGER, "Ángulo -90° (Norte) resuelve a DANGER (1)")

	# Este (0°) -> ON_MY_WAY (Verde LoL)
	var q_east = TacticalPingWheel.get_quadrant_from_angle(0.0)
	check(q_east == TacticalPingWheel.PingType.ON_MY_WAY, "Ángulo 0° (Este) resuelve a ON_MY_WAY (3)")

	# Sur (90°) -> ASSIST (Azul LoL)
	var q_south = TacticalPingWheel.get_quadrant_from_angle(PI * 0.5)
	check(q_south == TacticalPingWheel.PingType.ASSIST, "Ángulo 90° (Sur) resuelve a ASSIST (2, protocolo Rust 0x1A)")

	# Oeste (180°) -> MISSING (Amarillo LoL ??)
	var q_west = TacticalPingWheel.get_quadrant_from_angle(PI)
	check(q_west == TacticalPingWheel.PingType.MISSING, "Ángulo 180° (Oeste) resuelve a MISSING (0, protocolo Rust 0x1A)")

	# Cuadrantes diagonales limítrofes
	check(TacticalPingWheel.get_quadrant_from_angle(-PI * 0.6) == TacticalPingWheel.PingType.DANGER, "-108° resuelve a DANGER")
	check(TacticalPingWheel.get_quadrant_from_angle(PI * 0.2) == TacticalPingWheel.PingType.ON_MY_WAY, "36° resuelve a ON_MY_WAY")
	check(TacticalPingWheel.get_quadrant_from_angle(PI * 0.6) == TacticalPingWheel.PingType.ASSIST, "108° resuelve a ASSIST")
	check(TacticalPingWheel.get_quadrant_from_angle(-PI * 0.85) == TacticalPingWheel.PingType.MISSING, "-153° resuelve a MISSING")

	# Confirmación y Emisión de Señal
	wheel.active_selection = TacticalPingWheel.PingType.DANGER
	var event_data := {"type": -1, "name": "", "cancelled": false}
	wheel.ping_selected.connect(func(t: int, n: String):
		event_data["type"] = t
		event_data["name"] = n
	)

	var confirmed = wheel.close_and_confirm()
	check(confirmed == TacticalPingWheel.PingType.DANGER, "close_and_confirm retorna DANGER")
	check(wheel.visible == false, "close_and_confirm oculta la rueda")
	check(event_data["type"] == TacticalPingWheel.PingType.DANGER, "Señal ping_selected emitió tipo DANGER")
	check(event_data["name"] == "PELIGRO", "Señal ping_selected emitió nombre 'PELIGRO'")

	# Cancelación sin selección
	wheel.open_at(Vector2(500, 500))
	wheel.active_selection = TacticalPingWheel.PingType.NONE
	wheel.cancelled.connect(func(): event_data["cancelled"] = true)
	wheel.cancel()
	check(wheel.visible == false, "cancel() oculta la rueda")
	check(event_data["cancelled"] == true, "cancel() emite señal cancelled")

	# -------------------------------------------------------------------------
	# 3. Pruebas de TacticalPingMarker (Marcador 2D en Pantalla)
	# -------------------------------------------------------------------------
	print("\n--- 3. Pruebas de TacticalPingMarker ---")
	var marker_scene: PackedScene = load("res://ui/components/TacticalPing/TacticalPingMarker.tscn")
	check(marker_scene != null, "TacticalPingMarker.tscn carga correctamente")

	var marker: TacticalPingMarker = marker_scene.instantiate() as TacticalPingMarker
	check(marker != null, "TacticalPingMarker instanciado como clase")
	root.add_child(marker)
	await process_frame

	marker.setup(TacticalPingMarker.PingType.DANGER, "Sylvia", Vector3(10, 0, 25), 32.5)
	check(marker.ping_type == TacticalPingMarker.PingType.DANGER, "ping_type asignado a DANGER")
	check(marker.sender_name == "Sylvia", "sender_name asignado a 'Sylvia'")
	check(marker.distance_meters == 32.5, "distance_meters asignado a 32.5m")
	check(marker.get_ping_name() == "PELIGRO", "Nombre resuelto a 'PELIGRO'")
	check(marker.get_ping_color() == Color("#f59e0b"), "Color ámbar resuelto (#f59e0b)")
	check(marker.get_ping_glyph() == "hazard", "Glifo de peligro resuelto a 'hazard'")

	# Pruebas de colores para los demás tipos
	marker.ping_type = TacticalPingMarker.PingType.ATTACK
	check(marker.get_ping_color() == Color("#ef4444"), "ATTACK color carmesí (#ef4444)")

	marker.ping_type = TacticalPingMarker.PingType.EXTRACT
	check(marker.get_ping_color() == Color("#10b981"), "EXTRACT color esmeralda (#10b981)")

	marker.ping_type = TacticalPingMarker.PingType.ASSIST
	check(marker.get_ping_color() == Color("#06b6d4"), "ASSIST color cian (#06b6d4)")

	# Valores de cable sincronizados con Rust (protocol.rs PING_TYPE_*, opcode 0x1A)
	print("
--- 3. Paridad de PingType con el protocolo Rust 0x1A ---")
	check(TacticalPingWheel.PingType.ATTACK == 0, "Wheel ATTACK == 0 (PING_TYPE_ATTACK)")
	check(TacticalPingWheel.PingType.DANGER == 1, "Wheel DANGER == 1 (PING_TYPE_DANGER)")
	check(TacticalPingWheel.PingType.ASSIST == 2, "Wheel ASSIST == 2 (PING_TYPE_ASSIST)")
	check(TacticalPingWheel.PingType.EXTRACT == 3, "Wheel EXTRACT == 3 (PING_TYPE_EXTRACT)")
	check(TacticalPingMarker.PingType.ASSIST == TacticalPingWheel.PingType.ASSIST, "Marker y Wheel comparten ASSIST")
	check(TacticalPingMarker.PingType.EXTRACT == TacticalPingWheel.PingType.EXTRACT, "Marker y Wheel comparten EXTRACT")
	check(TacticalPingWheel.get_ping_config(3)["name"] == "EXTRAER", "get_ping_config(3) resuelve EXTRAER")
	check(TacticalPingWheel.get_ping_config(2)["name"] == "ASISTIR", "get_ping_config(2) resuelve ASISTIR")

	# Limpieza
	wheel.queue_free()
	marker.queue_free()
	await process_frame

	print("\n== RESULTADOS ==")
	print("== %d checks, %d fallos ==" % [_checks, _fails.size()])
	quit(0 if _fails.is_empty() else 1)
