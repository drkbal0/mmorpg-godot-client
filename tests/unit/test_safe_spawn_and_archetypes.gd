extends SceneTree

# test_safe_spawn_and_archetypes.gd — Headless Unit Tests (ADR 037 / ADR 081)
# Verifica: blindaje de spawn seguro del jugador local, presencia física de los 5
# arquetipos de Overworld (Gildas + 4 mobs) e interacción de Gildas -> marketplace_window.

# World.gd se carga en runtime: depende de autoloads que no existen al compilar el test.
var WorldScript: GDScript = null
const GildasMerchantScript = preload("res://world/GildasMerchant.gd")
const SpawnSafety = preload("res://shared-core/SpawnSafety.gd")
const SENTINEL := Vector3(-999, -999, -999)

var _tests_run := 0
var _tests_passed := 0
var _tests_failed := 0
var _world: Node = null

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

func _autoload(n: String) -> Node:
	return root.get_node_or_null(n)

func _run_all_tests() -> void:
	print("\n=== STARTING SAFE SPAWN & OVERWORLD ARCHETYPES TEST SUITE ===")

	WorldScript = load("res://World.gd")
	_assert(WorldScript != null and WorldScript.can_instantiate(), "World.gd compila y carga en runtime")
	test_resolve_safe_spawn_rules()

	# Escenario de depuración local: sin personaje, sin nombre y last_pos = sentinel.
	var auth = _autoload("AuthManager")
	_assert(auth != null, "AuthManager autoload disponible")
	if auth:
		auth.selected_character_id = ""
		auth.selected_character_name = ""
		auth.last_pos = SENTINEL
		auth.world_ticket = ""

	var scene: PackedScene = load("res://World.tscn")
	_assert(scene != null, "World.tscn carga correctamente")
	if scene:
		_world = scene.instantiate()
		root.add_child(_world)
		await process_frame
		await process_frame

		test_local_player_fallback_spawn(auth)
		test_overworld_archetypes()
		await test_gildas_interaction()

	print("\n=== SAFE SPAWN & ARCHETYPES RESULTS: %d/%d PASSED (%d FAILED) ===" % [
		_tests_passed, _tests_run, _tests_failed
	])
	quit(0 if _tests_failed == 0 else 1)

# ---------------------------------------------------------------------------

func test_resolve_safe_spawn_rules() -> void:
	print("\n[Test] resolve_safe_spawn()")
	_assert(WorldScript.resolve_safe_spawn(SENTINEL) == Vector3(0, 1, 0), "Sentinel (-999,-999,-999) -> (0,1,0)")
	_assert(WorldScript.resolve_safe_spawn(Vector3.ZERO) == Vector3(0, 1, 0), "Origen (0,0,0) -> (0,1,0)")
	_assert(WorldScript.resolve_safe_spawn(Vector3(800, 0, 0)) == Vector3(0, 1, 0), "Fuera de mapa (len² > 500000) -> (0,1,0)")
	_assert(WorldScript.resolve_safe_spawn(Vector3(12, 0, -7)) == Vector3(12, 1, -7), "y≈0 se eleva a y=1 conservando XZ")
	_assert(WorldScript.resolve_safe_spawn(Vector3(5, 3, 5)) == Vector3(5, 3, 5), "Posición válida se respeta")
	_assert(SpawnSafety.resolve(SENTINEL) == WorldScript.resolve_safe_spawn(SENTINEL), "World y Player comparten la misma regla (SpawnSafety)")

func test_local_player_fallback_spawn(auth: Node) -> void:
	print("\n[Test] Spawn local de fallback")
	var lp = _world.get("local_player")
	_assert(lp != null and is_instance_valid(lp), "local_player instanciado sin selected_character_id")
	if lp and is_instance_valid(lp):
		_assert(lp.get_parent() == _world, "local_player es hijo de World")
		_assert(lp.position.is_equal_approx(Vector3(0, 1, 0)), "local_player spawnea en (0,1,0) con last_pos sentinel (got %s)" % str(lp.position))
	if auth:
		_assert(auth.selected_character_name == "Aren", "Nombre por defecto 'Aren' aplicado")

func _check_archetype(node_name: String, pos: Vector3, col: Color, lvl: int, hostile: bool, scale_f: float, max_hp: float = -1.0) -> void:
	var n: Node3D = _world.get_node_or_null(node_name)
	_assert(n != null, "%s existe en el árbol de World" % node_name)
	if n == null:
		return
	_assert(n.position.is_equal_approx(pos), "%s en posición %s (got %s)" % [node_name, str(pos), str(n.position)])
	_assert(n.scale.is_equal_approx(Vector3.ONE * scale_f), "%s escala %.1fx" % [node_name, scale_f])
	var mesh := n.get_node_or_null("Mesh") as MeshInstance3D
	_assert(mesh != null and mesh.mesh is CapsuleMesh, "%s tiene malla cápsula visible" % node_name)
	if mesh:
		var mat := mesh.material_override as StandardMaterial3D
		_assert(mat != null and mat.albedo_color.is_equal_approx(col), "%s material de color correcto" % node_name)
		_assert(mesh.visible, "%s malla visible" % node_name)
	var colsh := n.get_node_or_null("Collision") as CollisionShape3D
	_assert(colsh != null and colsh.shape is CapsuleShape3D and not colsh.disabled, "%s colisión activa" % node_name)
	_assert(n is Area3D and (n as Area3D).collision_layer == 48, "%s en capas targetable/interactive (48)" % node_name)
	var np = n.get_meta("nameplate", null)
	_assert(np != null and is_instance_valid(np) and np.get_script() != null and str(np.get_script().resource_path).ends_with("WorldNameplate.gd"), "%s tiene WorldNameplate" % node_name)
	if np and is_instance_valid(np):
		_assert(np.unit_level == lvl, "%s nameplate nivel %d" % [node_name, lvl])
		_assert(np.is_hostile_unit == hostile, "%s nameplate %s" % [node_name, "hostil" if hostile else "amistoso"])
		if max_hp > 0.0:
			_assert(is_equal_approx(np.max_health, max_hp), "%s nameplate HP máx %.0f" % [node_name, max_hp])
	if hostile:
		var aura := n.get_node_or_null("Aura") as MeshInstance3D
		_assert(aura != null and aura.material_override is StandardMaterial3D, "%s tiene aura 3D" % node_name)
		if aura:
			var am := aura.material_override as StandardMaterial3D
			_assert(Color(am.albedo_color.r, am.albedo_color.g, am.albedo_color.b).is_equal_approx(col), "%s aura del color de dominancia" % node_name)

func test_overworld_archetypes() -> void:
	print("\n[Test] Arquetipos de Overworld")
	var arch: Array = _world.get("overworld_archetypes")
	_assert(arch.size() == 5, "5 arquetipos registrados (got %d)" % arch.size())
	_check_archetype("NPC_Gildas", Vector3(4, 1, 4), Color(0.2, 0.5, 0.85), 25, false, 1.0)
	_check_archetype("Guardia_Carmesí", Vector3(-6, 1, 8), Color(0.95, 0.25, 0.25), 12, true, 1.0, 1200.0)
	_check_archetype("Explorador_Esmeralda", Vector3(-10, 1, 12), Color(0.15, 0.88, 0.45), 14, true, 1.0, 950.0)
	_check_archetype("Mago_del_Vacío", Vector3(-8, 1, 18), Color(0.68, 0.28, 0.98), 16, true, 1.0, 800.0)
	_check_archetype("Val'Gorath_el_Devorador", Vector3(0, 2.2, 24), Color(0.92, 0.72, 0.15), 50, true, 2.2, 100000.0)

	# Visibilidad desde el spawn seguro: todos dentro de 30 m del jugador.
	var lp = _world.get("local_player")
	if lp and is_instance_valid(lp):
		var all_near := true
		for a in arch:
			if is_instance_valid(a) and a.position.distance_to(lp.position) > 30.0:
				all_near = false
		_assert(all_near, "Todos los arquetipos a < 30 m del spawn seguro")

func test_gildas_interaction() -> void:
	print("\n[Test] Interacción con Gildas")
	var gildas = _world.get_node_or_null("NPC_Gildas")
	_assert(gildas != null and gildas.get_script() == GildasMerchantScript, "NPC_Gildas usa GildasMerchant.gd")
	if gildas == null:
		return
	_assert(gildas.is_in_group("interactable"), "Gildas pertenece al grupo 'interactable' (tecla [F])")
	_assert(gildas.has_method("interact"), "Gildas expone interact()")
	_assert(InputMap.has_action("interact"), "Acción 'interact' registrada en InputMap")
	if InputMap.has_action("interact"):
		var has_f := false
		for ev in InputMap.action_get_events("interact"):
			if ev is InputEventKey and (ev.keycode == KEY_F or ev.physical_keycode == KEY_F):
				has_f = true
		_assert(has_f, "Acción 'interact' mapeada a [F]")

	var ui = _autoload("UIOrchestrator")
	_assert(ui != null, "UIOrchestrator autoload disponible")
	if ui == null:
		return
	if ui.registry.get_instance("marketplace_window"):
		ui.close_window("marketplace_window")
		await process_frame

	# Proximidad: el jugador a 1 m de Gildas -> Player.gd resolvería [F] hacia Gildas
	var lp = _world.get("local_player")
	if lp and is_instance_valid(lp):
		lp.global_position = gildas.global_position + Vector3(1, 0, 0)
		var closest = null
		var best := 3.5
		for obj in _world.get_tree().get_nodes_in_group("interactable"):
			if is_instance_valid(obj) and obj.has_method("interact"):
				var d = lp.global_position.distance_to(obj.global_position)
				if d <= best:
					best = d
					closest = obj
		_assert(closest == gildas, "Resolución de proximidad [F] apunta a Gildas")

	var win = gildas.interact(lp)
	await process_frame
	var inst = ui.registry.get_instance("marketplace_window")
	_assert(win != null and inst != null and win == inst, "interact() abre marketplace_window via UIOrchestrator")
	_assert(inst != null and inst.visible, "marketplace_window visible tras interacción")

	# Atomicidad: segunda interacción NO la cierra ni duplica
	var win2 = gildas.interact(lp)
	await process_frame
	_assert(win2 == inst and ui.registry.get_instance("marketplace_window").visible, "Segunda interacción es idempotente (no toggle/duplicado)")

	# Clic izquierdo (picking físico) también abre la ventana
	ui.close_window("marketplace_window")
	await process_frame
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	gildas._input_event(null, click, gildas.global_position, Vector3.UP, 0)
	await process_frame
	var inst2 = ui.registry.get_instance("marketplace_window")
	_assert(inst2 != null and inst2.visible, "Clic izquierdo sobre Gildas abre marketplace_window")
