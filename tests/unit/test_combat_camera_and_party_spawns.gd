extends SceneTree

# test_combat_camera_and_party_spawns.gd — Headless Unit Tests
# Verifica:
#  1. Habilidades en 3ª persona: la bola de fuego / hitscan ya no impactan al propio
#     avatar (exclusión de RIDs + spawn adelantado) y el haz sale a la altura del pecho.
#  2. get_ground_cursor_position() en 3ª persona es coherente apuntando abajo,
#     al horizonte y hacia arriba.
#  3. Escuadra de pruebas (Valerius, Sylvia, Kaelen) desplegada con nameplates amistosos,
#     Kaelen abatido y reanimable (ADR 100) y unión a Party Frames (4 miembros).
#  4. Cámara Top-Down estilo LoL (FOV 45, Pitch -58, Offset (0,18,11.25)) y bloqueo forzado.

const ReviveInteraction = preload("res://shared-core/ReviveInteraction.gd")
const Codec = preload("res://shared-core/ExtractionReviveCodec.gd")
const SENTINEL := Vector3(-999, -999, -999)

var _tests_run := 0
var _tests_passed := 0
var _tests_failed := 0
var _world: Node = null
var _lp: Node = null

func _init() -> void:
	call_deferred("_run_all_tests")

func _assert(condition: bool, test_name: String) -> void:
	_tests_run += 1
	if condition:
		_tests_passed += 1
		print("  [PASS] %s" % test_name)
	else:
		_tests_failed += 1
		printerr("  [FAIL] %s" % test_name)

func _frames(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame

func _run_all_tests() -> void:
	print("\n=== STARTING COMBAT CAMERA & PARTY ALLIES TEST SUITE ===")

	var auth = root.get_node_or_null("AuthManager")
	if auth:
		auth.selected_character_id = ""
		auth.selected_character_name = ""
		auth.last_pos = SENTINEL
		auth.world_ticket = ""

	var scene: PackedScene = load("res://World.tscn")
	_assert(scene != null, "World.tscn carga correctamente")
	if scene == null:
		quit(1)
		return
	_world = scene.instantiate()
	root.add_child(_world)
	await _frames(4)

	_lp = _world.get("local_player")
	_assert(_lp != null and is_instance_valid(_lp), "local_player instanciado")
	if _lp == null:
		quit(1)
		return
	_lp.global_position = Vector3(0, 1, 0)
	_lp.rotation = Vector3.ZERO
	await _frames(3)

	test_fireball_not_self_hit()
	test_hitscan_chest_origin()
	await test_third_person_cursor()
	test_party_allies_spawned()
	test_kaelen_downed()
	await test_party_join_and_revive()
	test_top_down_camera()

	print("\n=== COMBAT CAMERA & PARTY RESULTS: %d/%d PASSED (%d FAILED) ===" % [
		_tests_passed, _tests_run, _tests_failed
	])
	quit(0 if _tests_failed == 0 else 1)

# ---------------------------------------------------------------------------

func test_fireball_not_self_hit() -> void:
	print("\n[Test] Bola de fuego no impacta al lanzador")
	var origin: Vector3 = _lp.global_position
	var space: PhysicsDirectSpaceState3D = _lp.get_world_3d().direct_space_state

	# Reproducción del bug: el origen autoritativo del servidor llega ligeramente
	# DETRÁS del avatar predicho (corriendo hacia delante en 3ª persona); sin
	# exclusiones el rayo entra en la cápsula propia y la bola explota en la cara.
	var lag_origin: Vector3 = origin + Vector3(0, 0, 0.6)
	var raw := PhysicsRayQueryParameters3D.create(lag_origin, lag_origin + Vector3.FORWARD * 25.0)
	raw.collide_with_areas = false
	var raw_hit: Dictionary = space.intersect_ray(raw)
	_assert(not raw_hit.is_empty() and raw_hit.collider == _lp and lag_origin.distance_to(raw_hit.position) < 0.5, "Repro: rayo SIN exclusión impacta al propio jugador a <0.5 m")

	var p_lag: Node3D = _world._spawn_fireball_projectile(4241, lag_origin, Vector2(0, -1), 20.0, -1)
	_assert(p_lag != null and absf((p_lag.get_meta("target_pos") as Vector3).z - (-14.0)) < 0.2, "Con origen retrasado la bola atraviesa al lanzador y llega al pilar")

	var excl: Array = _world._projectile_excludes(-1)
	_assert(excl.has(_lp.get_rid()), "Exclusiones incluyen el RID del local_player")
	var area = _lp.get_node_or_null("Area3D")
	_assert(area != null and excl.has(area.get_rid()), "Exclusiones incluyen las hitboxes (Area3D) del jugador")

	# Disparo hacia -Z: el pilar norte (0,2,-15) está a ~14 m.
	var p: Node3D = _world._spawn_fireball_projectile(4242, origin, Vector2(0, -1), 20.0, -1)
	_assert(p != null and is_instance_valid(p), "Proyectil instanciado")
	if p == null:
		return
	var spawn: Vector3 = p.get_meta("spawn_origin")
	var target: Vector3 = p.get_meta("target_pos")
	_assert(is_equal_approx(origin.distance_to(spawn), 0.9), "Spawn adelantado 0.9 m respecto a la cápsula (got %.2f)" % origin.distance_to(spawn))
	_assert(spawn.distance_to(target) > 5.0, "No explota en la cara: recorre %.1f m" % spawn.distance_to(target))
	_assert(p.get_meta("hit_obstacle") == true and absf(target.z - (-14.0)) < 0.2, "Impacta el pilar norte en z≈-14 (got %s)" % str(target))

	# Disparo hacia +X sin obstáculos: alcance completo de 25 m.
	var p2: Node3D = _world._spawn_fireball_projectile(4243, origin, Vector2(1, 0), 20.0, -1)
	_assert(p2 != null and p2.get_meta("hit_obstacle") == false, "Sin obstáculos: vuela el alcance completo (sin impacto propio)")

func test_hitscan_chest_origin() -> void:
	print("\n[Test] Hitscan a la altura del pecho")
	var origin: Vector3 = _lp.global_position
	var beam: Node3D = _world._spawn_hitscan_tracer(origin, Vector2(1, 0), -1)
	_assert(beam != null, "Haz trazador instanciado")
	if beam == null:
		return
	var b0: Vector3 = beam.get_meta("beam_origin")
	var b1: Vector3 = beam.get_meta("beam_end")
	_assert(absf(b0.y - 1.2) < 0.05, "Origen del haz a 1.2 m sobre el suelo (got y=%.2f)" % b0.y)
	_assert(b0.distance_to(b1) > 10.0, "El haz no queda bloqueado por el propio avatar (%.1f m)" % b0.distance_to(b1))
	_assert(absf(b1.y - b0.y) < 0.01 and b1.x > b0.x, "El haz se proyecta hacia el objetivo (+X)")
	# Sin suelo bajo el origen: se asume posición base y se suma 1.2.
	var air: Vector3 = _world._chest_origin(Vector3(0, 50, 0), [] as Array[RID])
	_assert(air.is_equal_approx(Vector3(0, 51.2, 0)), "Fallback sin suelo: origen + (0,1.2,0)")

func test_third_person_cursor() -> void:
	print("\n[Test] get_ground_cursor_position() en 3ª persona")
	_lp.set_forced_camera_top_down(false)
	_lp.camera_mode = _lp.CameraMode.THIRD_PERSON
	_lp.setup_camera()
	_lp.global_position = Vector3(0, 1, 0)
	_lp.rotation = Vector3.ZERO
	await _frames(2)
	var cam: Camera3D = _lp.camera
	var forward: Vector3 = -_lp.global_transform.basis.z

	# a) Apuntando hacia abajo: intersección con el suelo por delante.
	cam.rotation_degrees = Vector3(-35, 0, 0)
	await _frames(1)
	var down: Vector3 = _lp.get_ground_cursor_position()
	_assert(absf(down.y) < 0.1, "Abajo: punto sobre el suelo y≈0 (got %s)" % str(down))
	_assert((down - _lp.global_position).dot(forward) > 0.0, "Abajo: punto por delante del avatar")

	# b) Horizonte: antes t<=0 -> fallback. Ahora rayo hacia delante (pilar norte z≈-14).
	cam.rotation_degrees = Vector3(0, 0, 0)
	await _frames(1)
	var hz: Vector3 = _lp.get_ground_cursor_position()
	_assert(absf(hz.z - (-14.0)) < 0.3 and absf(hz.x) < 1.0, "Horizonte: impacta el pilar norte (got %s)" % str(hz))
	_assert(hz.is_finite() and (hz - _lp.global_position).dot(forward) > 0.0, "Horizonte: punto coherente por delante")

	# c) Hacia arriba sin nada en la mira: from + dir * 60.
	cam.rotation_degrees = Vector3(30, 0, 0)
	await _frames(1)
	var from := cam.project_ray_origin(root.get_visible_rect().size / 2.0)
	var up: Vector3 = _lp.get_ground_cursor_position()
	_assert(absf(from.distance_to(up) - 60.0) < 0.5, "Arriba: fallback a 60 m en la mira (got %.1f m)" % from.distance_to(up))
	_assert(up.y > from.y and (up - _lp.global_position).dot(forward) > 0.0, "Arriba: punto por delante y por encima (no detrás de la cámara)")

	# d) Girado hacia +X (sin obstáculos cercanos) apuntando abajo.
	_lp.rotation_degrees = Vector3(0, -90, 0)
	cam.rotation_degrees = Vector3(-30, 0, 0)
	await _frames(1)
	var side: Vector3 = _lp.get_ground_cursor_position()
	_assert(side.x > 0.5 and absf(side.y) < 0.1, "Girado: el cursor sigue la orientación del avatar (got %s)" % str(side))

	_lp.rotation = Vector3.ZERO
	cam.rotation_degrees = Vector3(-15, 0, 0)
	_lp.camera_mode = _lp.CameraMode.TOP_DOWN
	_lp.setup_camera()

func _check_ally(node_name: String, ally_name: String, lvl: int, hp: float, max_hp: float) -> Node3D:
	var n: Node3D = _world.get_node_or_null(node_name)
	_assert(n != null, "%s existe en el árbol de World" % node_name)
	if n == null:
		return null
	var d: float = n.position.distance_to(Vector3(0, 1, 0))
	_assert(d >= 8.0 and d <= 12.0, "%s a %.1f m del spawn (8-12 m)" % [node_name, d])
	_assert(n.ally_name == ally_name and n.level == lvl, "%s nivel %d" % [node_name, lvl])
	_assert(is_equal_approx(n.max_hp, max_hp) and is_equal_approx(n.hp, hp), "%s HP %d/%d" % [node_name, int(hp), int(max_hp)])
	_assert(n is Area3D and (n as Area3D).collision_layer == 48, "%s en capas targetable/interactive (48)" % node_name)
	_assert(n.has_method("interact") and n.is_in_group("interactable"), "%s interactuable" % node_name)
	var np = n.get_meta("nameplate", null)
	_assert(np != null and is_instance_valid(np), "%s tiene WorldNameplate" % node_name)
	if np:
		_assert(np.is_hostile_unit == false, "%s nameplate amistoso (nivel a la izquierda)" % node_name)
		_assert(np.unit_level == lvl, "%s nameplate nivel %d" % [node_name, lvl])
		_assert(is_equal_approx(np.max_health, max_hp), "%s nameplate HP máx %d" % [node_name, int(max_hp)])
	return n

func test_party_allies_spawned() -> void:
	print("\n[Test] Escuadra de pruebas desplegada")
	var allies: Array = _world.get("party_allies")
	_assert(allies.size() == 3, "3 aliados registrados (got %d)" % allies.size())
	_check_ally("Aliado_Valerius", "Valerius", 15, 2400.0, 2400.0)
	_check_ally("Aliada_Sylvia", "Sylvia", 14, 1600.0, 1600.0)
	_check_ally("Aliado_Kaelen", "Kaelen", 13, 0.0, 1200.0)
	var arch: Array = _world.get("overworld_archetypes")
	_assert(arch.size() == 5, "Arquetipos de Overworld intactos (5)")

func test_kaelen_downed() -> void:
	print("\n[Test] Kaelen abatido y reanimable")
	var k: Node3D = _world.get_node_or_null("Aliado_Kaelen")
	if k == null:
		_assert(false, "Kaelen presente")
		return
	_assert(k.is_downed, "Kaelen is_downed = true")
	_assert(k.is_in_group(ReviveInteraction.DOWNED_GROUP), "Kaelen en grupo 'downed_allies'")
	_assert(k.bleedout_remaining > 25.0 and k.bleedout_remaining <= Codec.BLEEDOUT_SEC, "Bleedout activo ~30 s (got %.1f)" % k.bleedout_remaining)
	_assert(ReviveInteraction.session_id_of(k) >= 900000 and k.has_meta("local_mock"), "Kaelen con session_id local de prueba")
	var mesh: MeshInstance3D = k.get_node_or_null("Mesh")
	_assert(mesh != null and is_equal_approx(mesh.rotation_degrees.x, 90.0), "Malla de Kaelen acostada (90°)")
	var np = k.get_meta("nameplate", null)
	_assert(np != null and np.is_downed and str(np.title_label.text).begins_with("ABATIDO"), "Nameplate muestra 'ABATIDO Ns'")
	var choice := ReviveInteraction.resolve(k.global_position + Vector3(1.5, 0, 0), [k], _world.get_tree().get_nodes_in_group("interactable"))
	_assert(choice["kind"] == ReviveInteraction.KIND_REVIVE and choice["node"] == k, "[F] a 1.5 m resuelve REANIMAR Kaelen (prioridad 1)")
	var v: Node3D = _world.get_node_or_null("Aliado_Valerius")
	_assert(v != null and not v.is_in_group(ReviveInteraction.DOWNED_GROUP), "Valerius NO está abatido")

func test_party_join_and_revive() -> void:
	print("\n[Test] Unión al grupo (Party Frames) y reanimación asistida de 6 s")
	var v: Node3D = _world.get_node_or_null("Aliado_Valerius")
	# Auto-aceptación por proximidad (<= 6 m).
	_lp.global_position = v.global_position + Vector3(0, 0, -3.0)
	await _frames(25)
	_assert(v.in_party, "Valerius acepta automáticamente la invitación por proximidad")

	var joined: int = _world.join_all_party_allies()
	_assert(joined == 2, "Sylvia y Kaelen se unen al grupo (got %d)" % joined)
	var pf = _world.get_party_frames()
	_assert(pf != null and pf.get_member_frames().size() == 3, "Party Frames muestra 3 aliados (+ jugador local = 4 miembros)")
	var ids: Array = _world.get("party_member_ids")
	_assert(ids.size() == 3, "party_member_ids contiene 3 aliados")

	var k: Node3D = _world.get_node_or_null("Aliado_Kaelen")
	var kf = pf.get_member_frame(k.session_id) if pf else null
	_assert(kf != null and kf.is_downed, "Frame de Kaelen en estado ABATIDO")

	# [F] junto a Kaelen: reanimación local (sin servidor).
	_lp.global_position = k.global_position + Vector3(0, 0, 1.5)
	await _frames(2)
	var started: bool = _lp.handle_interact_pressed()
	_assert(started and _lp.reviving_sid == k.session_id, "[F] inicia la reanimación de Kaelen")
	var modal = _world.get("revive_modal")
	_assert(modal != null and modal.is_channelling and modal.target_name == "Kaelen", "Modal 'Reanimando a Kaelen' visible")
	_world._process_party_allies(3.0)
	_assert(k.is_downed and absf(k.revive_progress - 0.5) < 0.01, "A los 3 s: 50%% de progreso, aún abatido")
	_world._process_party_allies(3.05)
	_assert(not k.is_downed, "A los 6 s: Kaelen reanimado")
	_assert(is_equal_approx(k.hp, 360.0), "Kaelen vuelve con 30%% de vida (360/1200)")
	_assert(not k.is_in_group(ReviveInteraction.DOWNED_GROUP), "Kaelen sale de 'downed_allies'")
	_assert(_lp.reviving_sid == 0, "reviving_sid del jugador se limpia")
	_assert(kf != null and not kf.is_downed, "Frame de Kaelen vuelve a estado NORMAL")
	_assert(is_equal_approx(k.get_node("Mesh").rotation_degrees.x, 0.0), "Kaelen se pone de pie")

	_lp.global_position = Vector3(0, 1, 0)

func test_top_down_camera() -> void:
	print("\n[Test] Cámara Top-Down estilo LoL")
	_lp.camera_mode = _lp.CameraMode.TOP_DOWN
	_lp.setup_camera()
	var cam: Camera3D = _lp.camera
	_assert(is_equal_approx(cam.fov, 45.0), "FOV 45° (got %.1f)" % cam.fov)
	_assert(absf(cam.rotation_degrees.x - (-58.0)) < 0.01, "Pitch -58° (got %.2f)" % cam.rotation_degrees.x)
	_assert(_lp.LOL_CAM_OFFSET.is_equal_approx(Vector3(0.0, 18.0, 11.25)), "Offset (0, 18, 11.25)")
	_assert(cam.position.is_equal_approx(_lp.position + Vector3(0.0, 18.0, 11.25)), "Cámara colocada en posición + offset")

	_lp.camera_mode = _lp.CameraMode.THIRD_PERSON
	_lp.setup_camera()
	_lp.set_forced_camera_top_down(true)
	_assert(_lp.camera_mode == _lp.CameraMode.TOP_DOWN and _lp.is_camera_top_down_forced(), "set_forced_camera_top_down(true) fuerza Top-Down")
	_lp.toggle_camera_mode()
	_assert(_lp.camera_mode == _lp.CameraMode.TOP_DOWN, "Con vista forzada no se puede alternar a 3ª persona")
	_assert(is_equal_approx(cam.fov, 45.0) and absf(cam.rotation_degrees.x + 58.0) < 0.01, "Vista forzada mantiene FOV 45 / Pitch -58")
	_lp.set_forced_camera_top_down(false)
	_lp.toggle_camera_mode()
	_assert(_lp.camera_mode == _lp.CameraMode.THIRD_PERSON, "Sin bloqueo vuelve a alternar a 3ª persona")
	_lp.toggle_camera_mode()
