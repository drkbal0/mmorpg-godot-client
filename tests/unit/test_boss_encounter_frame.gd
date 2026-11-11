extends SceneTree

# test_boss_encounter_frame.gd — Headless Unit Test Suite for BossEncounterFrame (Phase 9.6, ADR 098)
# Verifies: Boss health calculation, phase shifts, enrage countdown, cast bar lifecycle, and threat aggro alerts.

const BossEncounterFrame = preload("res://ui/components/BossEncounterFrame/BossEncounterFrame.gd")

var _tests_run := 0
var _tests_passed := 0
var _tests_failed := 0

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

func _run_all_tests() -> void:
	print("\n=== STARTING BOSS ENCOUNTER FRAME TEST SUITE ===")
	
	test_initialization_and_setup()
	test_health_scaling_and_clamp()
	test_phase_transitions_and_signals()
	test_enrage_countdown_and_trigger()
	test_cast_bar_lifecycle()
	test_threat_table_and_aggro_warning()
	
	print("\n=== BOSS ENCOUNTER FRAME RESULTS: %d/%d PASSED (%d FAILED) ===" % [
		_tests_passed, _tests_run, _tests_failed
	])
	
	if _tests_failed == 0:
		quit(0)
	else:
		quit(1)

func _instantiate_frame() -> BossEncounterFrame:
	var scene = load("res://ui/components/BossEncounterFrame/BossEncounterFrame.tscn")
	var frame: BossEncounterFrame = scene.instantiate() as BossEncounterFrame
	root.add_child(frame)
	return frame

func test_initialization_and_setup() -> void:
	print("\n--- Test: Initialization and Setup ---")
	var frame = _instantiate_frame()
	frame.setup_boss(9901, "Aethelgard el Desterrado", 150000.0, 4, 360)
	
	_assert(frame.boss_id == 9901, "Boss ID correctly assigned")
	_assert(frame.boss_name == "Aethelgard el Desterrado", "Boss name correctly assigned")
	_assert(frame.max_hp == 150000.0, "Max HP is 150,000")
	_assert(frame.current_hp == 150000.0, "Current HP initialized to max")
	_assert(frame.current_phase == 1, "Starts in phase 1")
	_assert(frame.max_phases == 4, "Configured with 4 phases")
	_assert(frame.enrage_timer_sec == 360, "Enrage timer set to 360 seconds (6 mins)")
	_assert(frame.name_label.text.contains("AETHELGARD"), "Label contains uppercase boss name")
	_assert(frame.phase_badge.text == "FASE 1 / 4", "Phase badge displays 'FASE 1 / 4'")
	
	frame.queue_free()

func test_health_scaling_and_clamp() -> void:
	print("\n--- Test: Health Scaling and Clamping ---")
	var frame = _instantiate_frame()
	frame.setup_boss(101, "Test Boss", 200000.0)
	
	# Daño al 50%
	frame.set_hp(100000.0)
	_assert(frame.current_hp == 100000.0, "Current HP set to 100,000")
	_assert(frame.hp_bar.value == 50.0, "Health progress bar value is 50%")
	_assert(frame.hp_text.text.contains("50.0%"), "Health text shows 50.0%")
	
	# Clamp superior (no exceder max_hp)
	frame.set_hp(350000.0)
	_assert(frame.current_hp == 200000.0, "Clamps to max_hp (200,000)")
	_assert(frame.hp_bar.value == 100.0, "Bar at 100%")
	
	# Clamp inferior (no bajar de 0)
	frame.set_hp(-500.0)
	_assert(frame.current_hp == 0.0, "Clamps to 0.0")
	_assert(frame.hp_bar.value == 0.0, "Bar at 0%")
	
	frame.queue_free()

func test_phase_transitions_and_signals() -> void:
	print("\n--- Test: Phase Transitions and Signals ---")
	var frame = _instantiate_frame()
	frame.setup_boss(101, "Test Boss", 100000.0, 3)
	
	var emitted_phase := {"phase": 0}
	frame.phase_changed.connect(func(p): emitted_phase["phase"] = p)
	
	frame.set_phase(2)
	_assert(frame.current_phase == 2, "Phase changed to 2")
	_assert(frame.phase_badge.text == "FASE 2 / 3", "Badge reflects Phase 2")
	_assert(emitted_phase["phase"] == 2, "phase_changed signal emitted with phase 2")
	
	# Ignorar misma fase
	emitted_phase["phase"] = 0
	frame.set_phase(2)
	_assert(emitted_phase["phase"] == 0, "No signal emitted when setting identical phase")
	
	frame.queue_free()

func test_enrage_countdown_and_trigger() -> void:
	print("\n--- Test: Enrage Countdown and Trigger ---")
	var frame = _instantiate_frame()
	frame.setup_boss(101, "Test Boss", 100000.0, 3, 70)
	
	# Tick de 20s -> 50s restantes (< 60s umbral de alerta)
	frame.tick_enrage(20.0)
	_assert(frame.enrage_timer_sec == 50, "Timer decremented to 50 seconds")
	_assert(frame.is_enraged == false, "Boss is not enraged yet")
	
	var enrage_signal_fired := {"val": false}
	frame.enrage_triggered.connect(func(): enrage_signal_fired["val"] = true)
	
	# Tick final que agota el temporizador
	frame.tick_enrage(55.0)
	_assert(frame.enrage_timer_sec == 0, "Timer hits 0")
	_assert(frame.is_enraged == true, "Boss entered enraged state")
	_assert(enrage_signal_fired["val"] == true, "enrage_triggered signal fired")
	_assert(frame.enrage_label.text.contains("ENFURECIDO"), "Enrage label shows warning text")
	
	frame.queue_free()

func test_cast_bar_lifecycle() -> void:
	print("\n--- Test: Cast Bar Lifecycle ---")
	var frame = _instantiate_frame()
	_assert(frame.cast_container.visible == false, "Cast container initially hidden")
	
	frame.start_cast("Lluvia de Meteoros Aniquiladora", 4.0)
	_assert(frame.is_casting == true, "is_casting is true")
	_assert(frame.cast_container.visible == true, "Cast container visible during cast")
	_assert(frame.cast_label.text.contains("LLUVIA DE METEOROS"), "Spell name displayed in cast label")
	
	frame.update_cast_progress(0.65)
	_assert(is_equal_approx(frame.cast_bar.value, 65.0), "Cast progress bar value is 65%")
	
	# Completar casteo al 100%
	frame.update_cast_progress(1.0)
	_assert(frame.is_casting == false, "Cast finishes and is_casting becomes false")
	_assert(frame.cast_container.visible == false, "Cast container hidden after completion")
	
	frame.queue_free()

func test_threat_table_and_aggro_warning() -> void:
	print("\n--- Test: Threat Table and Aggro Warning ---")
	var frame = _instantiate_frame()
	
	var aggro_signal := {"fired": false, "state": false}
	frame.aggro_status_changed.connect(func(h):
		aggro_signal["fired"] = true
		aggro_signal["state"] = h
	)
	
	# Jugador con 45% de amenaza (Seguro)
	frame.set_threat(45, false)
	_assert(frame.player_threat_pct == 45, "Threat set to 45%")
	_assert(frame.threat_bar.value == 45.0, "Threat bar value is 45%")
	_assert(frame.aggro_warning_badge.visible == false, "Aggro warning hidden when safe")
	
	# Jugador supera al tanque y jala el aggro al 100%
	frame.set_threat(100, true)
	_assert(frame.is_holding_aggro == true, "is_holding_aggro is true")
	_assert(frame.aggro_warning_badge.visible == true, "Aggro warning badge is visible")
	_assert(aggro_signal["fired"] == true, "aggro_status_changed emitted")
	_assert(aggro_signal["state"] == true, "Carried true aggro state")
	
	# Tanque recupera el aggro con Taunt
	aggro_signal["fired"] = false
	frame.set_threat(70, false)
	_assert(frame.is_holding_aggro == false, "Lost aggro")
	_assert(frame.aggro_warning_badge.visible == false, "Warning badge hidden again")
	_assert(aggro_signal["fired"] == true, "aggro_status_changed emitted on drop")
	_assert(aggro_signal["state"] == false, "Carried false aggro state")
	
	frame.queue_free()

