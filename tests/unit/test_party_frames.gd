extends SceneTree
## Headless unit test for PartyFrames and PartyMemberFrame.
## Run: Godot --headless --path clients/godot-mmo-client -s res://tests/unit/test_party_frames.gd
## Exit code 0 = all pass.

const T = preload("res://ui/hud_tokens.gd")
const PartyMemberFrame = preload("res://ui/components/PartyFrames/PartyMemberFrame.gd")
const PartyFrames = preload("res://ui/components/PartyFrames/PartyFrames.gd")

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
	print("== [TEST] Party Frames Suite Iniciada ==")

	# -------------------------------------------------------------------------
	# 1. Instanciación y Métricas de PartyMemberFrame
	# -------------------------------------------------------------------------
	print("\n--- 1. Pruebas de PartyMemberFrame ---")
	var member_scene: PackedScene = load("res://ui/components/PartyFrames/PartyMemberFrame.tscn")
	check(member_scene != null, "PartyMemberFrame.tscn carga correctamente")

	var member_frame: PartyMemberFrame = member_scene.instantiate() as PartyMemberFrame
	check(member_frame != null, "PartyMemberFrame instanciado como clase PartyMemberFrame")
	root.add_child(member_frame)
	await process_frame

	check(member_frame.custom_minimum_size == Vector2(220, 54), "PartyMemberFrame custom_minimum_size es 220x54")
	check(member_frame.name_label != null, "NameLabel existe y es accesible")
	check(member_frame.distance_label != null, "DistanceLabel existe y es accesible")
	check(member_frame.status_badge != null, "StatusBadge existe y es accesible")
	check(member_frame.status_label != null, "StatusLabel existe y es accesible")
	check(member_frame.hp_bar != null, "HPBar existe y es accesible")
	check(member_frame.mana_bar != null, "ManaBar existe y es accesible")

	# -------------------------------------------------------------------------
	# 2. Configuración y Formato de Datos del Miembro
	# -------------------------------------------------------------------------
	print("\n--- 2. Configuración de Datos y Distancia ---")
	member_frame.setup({
		"id": 101,
		"name": "Valerius",
		"class": "guardian",
		"hp": 850.0,
		"max_hp": 1000.0,
		"mana": 250.0,
		"max_mana": 400.0,
		"distance": 18.4,
		"status": "NORMAL"
	})
	await process_frame

	check(member_frame.player_id == 101, "player_id asignado correctamente (101)")
	check(member_frame.player_name == "Valerius", "player_name asignado (Valerius)")
	check(member_frame.name_label.text == "Valerius", "NameLabel.text refleja el nombre")
	check(member_frame.member_class == "guardian", "member_class es guardian")
	check(member_frame.distance_label.text == "18m", "Distancia formateada correctamente: '18m'")

	# Prueba de formateo a distancias mayores y negativas
	member_frame.set_distance(1240.0)
	check(member_frame.distance_label.text == "1.2km", "Distancia kilométrica formateada: '1.2km'")
	member_frame.set_distance(-5.0)
	check(member_frame.distance_label.text == "--", "Distancia negativa formateada: '--'")
	member_frame.set_distance(42.0)
	check(member_frame.distance_label.text == "42m", "Distancia media formateada: '42m'")

	# -------------------------------------------------------------------------
	# 3. Salud (HP) y Maná con Animación Suave (Tween)
	# -------------------------------------------------------------------------
	print("\n--- 3. Vida, Maná y Animaciones Suaves ---")
	check(is_equal_approx(member_frame.current_hp, 850.0), "HP actual inicial = 850")
	check(is_equal_approx(member_frame.max_hp, 1000.0), "HP max inicial = 1000")
	check(is_equal_approx(member_frame.current_mana, 250.0), "Mana actual inicial = 250")

	# Daño recibido con animación
	member_frame.set_hp(400.0, 1000.0)
	check(is_equal_approx(member_frame.current_hp, 400.0), "Target current_hp actualizado a 400")
	check(member_frame._trail_hp >= 400.0, "Damage trail se mantiene por encima tras daño")
	check(member_frame._hp_tween != null and member_frame._hp_tween.is_valid(), "HP Tween creado para interpolación suave")

	# Esperar finalización del tween para verificar convergencia
	if member_frame._hp_tween and member_frame._hp_tween.is_valid():
		await member_frame._hp_tween.finished

	check(is_equal_approx(member_frame._display_hp, 400.0), "Display HP interpoló suavemente hasta 400.0")

	# Maná actualizado
	member_frame.set_mana(350.0, 400.0)
	check(is_equal_approx(member_frame.current_mana, 350.0), "Mana actualizado a 350")
	if member_frame._mana_tween and member_frame._mana_tween.is_valid():
		await member_frame._mana_tween.finished
	check(is_equal_approx(member_frame._display_mana, 350.0), "Display Mana interpoló suavemente a 350.0")

	# -------------------------------------------------------------------------
	# 4. Estado de Abatido (Downed) y Desangrado
	# -------------------------------------------------------------------------
	print("\n--- 4. Estado ABATIDO con Badge Rojo Parpadeante ---")
	check(member_frame.status == "NORMAL", "Estado inicial es NORMAL")
	check(member_frame.status_label.text == "NORMAL", "StatusLabel muestra 'NORMAL'")

	# Entrar en estado abatido con 15 segundos
	member_frame.set_downed(true, 15.0)
	await process_frame

	check(member_frame.is_downed == true, "is_downed es true")
	check(member_frame.status == "ABATIDO", "status es 'ABATIDO'")
	check(member_frame.bleedout_seconds <= 15.0 and member_frame.bleedout_seconds > 14.0, "Cuenta regresiva de desangrado activa")
	check(member_frame.status_label.text.begins_with("ABATIDO"), "StatusLabel muestra texto de ABATIDO")

	# Simular avance en tiempo y parpadeo
	var initial_phase = member_frame._flash_phase
	for i in range(10):
		await process_frame
	check(member_frame._flash_phase > initial_phase, "Fase de parpadeo roja incrementando continuamente")

	# Recuperar de abatido
	member_frame.set_downed(false)
	await process_frame
	check(member_frame.is_downed == false, "is_downed vuelve a false")
	check(member_frame.status == "NORMAL", "Status recupera 'NORMAL'")
	check(member_frame.status_label.text == "NORMAL", "StatusLabel muestra 'NORMAL'")

	# Estado MUERTO
	member_frame.set_status("MUERTO")
	await process_frame
	check(member_frame.status == "MUERTO", "status es 'MUERTO'")
	check(member_frame.status_label.text == "MUERTO", "StatusLabel muestra 'MUERTO'")
	check(is_equal_approx(member_frame.current_hp, 0.0), "HP pasa a 0 al morir")

	# -------------------------------------------------------------------------
	# 5. Pruebas del Contenedor PartyFrames (Hasta 3 Miembros)
	# -------------------------------------------------------------------------
	print("\n--- 5. Pruebas de Contenedor PartyFrames ---")
	var party_scene: PackedScene = load("res://ui/components/PartyFrames/PartyFrames.tscn")
	check(party_scene != null, "PartyFrames.tscn carga correctamente")

	var party: PartyFrames = party_scene.instantiate() as PartyFrames
	check(party != null, "PartyFrames instanciado como clase PartyFrames")
	root.add_child(party)
	await process_frame

	check(party.member_list != null, "MemberList (VBoxContainer) existe")
	check(party.custom_minimum_size == Vector2(220, 174), "PartyFrames custom_minimum_size es 220x174")

	# Cargar 4 miembros: debe truncar y mantener exactamente 3 miembros
	var party_data: Array[Dictionary] = [
		{"id": 1, "name": "Aethelgard", "class": "warrior", "hp": 1200.0, "max_hp": 1200.0, "mana": 300.0, "max_mana": 300.0, "distance": 12.0},
		{"id": 2, "name": "Sylvia", "class": "mage", "hp": 750.0, "max_hp": 800.0, "mana": 600.0, "max_mana": 600.0, "distance": 24.5},
		{"id": 3, "name": "Kaelen", "class": "ranger", "hp": 900.0, "max_hp": 950.0, "mana": 350.0, "max_mana": 350.0, "distance": 5.0},
		{"id": 4, "name": "ExceedingMember", "class": "rogue", "hp": 500.0, "max_hp": 500.0, "mana": 200.0, "max_mana": 200.0, "distance": 80.0}
	]

	party.set_party_members(party_data)
	await process_frame

	var active_frames = party.get_member_frames()
	check(active_frames.size() == 3, "PartyFrames contiene exactamente 3 miembros (máximo 3)")
	check(party.get_member_frame(1) != null, "Miembro 1 (Aethelgard) existe")
	check(party.get_member_frame(2) != null, "Miembro 2 (Sylvia) existe")
	check(party.get_member_frame(3) != null, "Miembro 3 (Kaelen) existe")
	check(party.get_member_frame(4) == null, "Miembro 4 no fue añadido (excede límite)")

	# -------------------------------------------------------------------------
	# 6. API Pública de Actualización Remota en PartyFrames
	# -------------------------------------------------------------------------
	print("\n--- 6. API Pública de PartyFrames ---")
	party.update_member_hp(1, 600.0, 1200.0)
	check(is_equal_approx(party.get_member_frame(1).current_hp, 600.0), "update_member_hp actualizó HP del jugador 1")

	party.update_member_distance(2, 35.0)
	check(party.get_member_frame(2).distance_label.text == "35m", "update_member_distance actualizó distancia del jugador 2")

	party.update_member_downed(3, true, 20.0)
	check(party.get_member_frame(3).is_downed == true, "update_member_downed activó abatido en jugador 3")
	check(party.get_member_frame(3).status == "ABATIDO", "Jugador 3 tiene estado 'ABATIDO'")

	party.update_member_mana(1, 150.0, 300.0)
	check(is_equal_approx(party.get_member_frame(1).current_mana, 150.0), "update_member_mana actualizó maná del jugador 1")

	# Limpiar grupo
	party.clear_party()
	await process_frame
	check(party.get_member_frames().size() == 0, "clear_party vació correctamente todos los miembros")

	# Limpieza de nodos
	member_frame.queue_free()
	party.queue_free()
	await process_frame

	print("\n== RESULTADOS ==")
	print("== %d checks, %d fallos ==" % [_checks, _fails.size()])
	quit(0 if _fails.is_empty() else 1)
