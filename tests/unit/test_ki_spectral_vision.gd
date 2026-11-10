extends SceneTree

# test_ki_spectral_vision.gd — Headless Unit Test Suite for Ki Spectral Vision (Phase 9.6, ADR 098)
# Verifies: Aura chromatic mapping, tie-break rules, boss priority, LoS wall penetration, and toggle state.

const KiSpectralVision = preload("res://ui/components/KiSpectralVision/KiSpectralVision.gd")

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
	print("\n=== STARTING KI SPECTRAL VISION TEST SUITE ===")
	
	test_aura_chromatic_mapping()
	test_tie_breaking_order()
	test_boss_priority()
	test_pulse_frequency()
	test_wall_penetration_limits()
	test_vision_toggle_and_signals()
	
	print("\n=== KI SPECTRAL VISION RESULTS: %d/%d PASSED (%d FAILED) ===" % [
		_tests_passed, _tests_run, _tests_failed
	])
	
	if _tests_failed == 0:
		quit(0)
	else:
		quit(1)

func test_aura_chromatic_mapping() -> void:
	print("\n--- Test: Aura Chromatic Mapping ---")
	# Warrior with high Strength
	var c_str = KiSpectralVision.get_aura_color(50.0, 15.0, 10.0, false)
	_assert(c_str == KiSpectralVision.COLOR_STRENGTH, "Strength dominant yields Crimson Red aura")
	
	# Rogue/Scout with high Agility
	var c_agi = KiSpectralVision.get_aura_color(15.0, 60.0, 20.0, false)
	_assert(c_agi == KiSpectralVision.COLOR_AGILITY, "Agility dominant yields Emerald Cyan aura")
	
	# Mage with high Intelligence
	var c_int = KiSpectralVision.get_aura_color(10.0, 15.0, 75.0, false)
	_assert(c_int == KiSpectralVision.COLOR_INTELLIGENCE, "Intelligence dominant yields Spectral Violet aura")
	
	# Zero stats (Inert object)
	var c_zero = KiSpectralVision.get_aura_color(0.0, 0.0, 0.0, false)
	_assert(c_zero == KiSpectralVision.COLOR_NEUTRAL, "Zero attributes yields Neutral Graphite")

func test_tie_breaking_order() -> void:
	print("\n--- Test: Tie Breaking Order (Strength > Agility > Intelligence) ---")
	# Strength vs Agility tie
	var tie_str_agi = KiSpectralVision.get_aura_color(40.0, 40.0, 10.0, false)
	_assert(tie_str_agi == KiSpectralVision.COLOR_STRENGTH, "Tie between Strength and Agility favors Strength")
	
	# Agility vs Intelligence tie
	var tie_agi_int = KiSpectralVision.get_aura_color(10.0, 35.0, 35.0, false)
	_assert(tie_agi_int == KiSpectralVision.COLOR_AGILITY, "Tie between Agility and Intelligence favors Agility")
	
	# Three-way tie
	var tie_three = KiSpectralVision.get_aura_color(30.0, 30.0, 30.0, false)
	_assert(tie_three == KiSpectralVision.COLOR_STRENGTH, "Three-way tie favors Strength")

func test_boss_priority() -> void:
	print("\n--- Test: Boss Priority ---")
	# Even if boss has 999 Intelligence, boss flag forces Gold
	var c_boss = KiSpectralVision.get_aura_color(10.0, 10.0, 999.0, true)
	_assert(c_boss == KiSpectralVision.COLOR_BOSS, "Boss entity always displays Radiant Gold aura")

func test_pulse_frequency() -> void:
	print("\n--- Test: Pulse Frequency ---")
	_assert(KiSpectralVision.get_pulse_frequency(true) == 4.0, "In-combat pulse frequency is 4.0 Hz")
	_assert(KiSpectralVision.get_pulse_frequency(false) == 1.2, "Out-of-combat pulse frequency is 1.2 Hz")

func test_wall_penetration_limits() -> void:
	print("\n--- Test: Wall Penetration Limits ---")
	_assert(KiSpectralVision.can_detect_through_wall(1.5) == true, "Penetrates 1.5m thin wall")
	_assert(KiSpectralVision.can_detect_through_wall(8.0) == true, "Penetrates exactly 8.0m boundary")
	_assert(KiSpectralVision.can_detect_through_wall(8.1) == false, "Blocked by 8.1m thick barrier")
	_assert(KiSpectralVision.can_detect_through_wall(25.0) == false, "Blocked by 25m mountain structure")
	_assert(KiSpectralVision.can_detect_through_wall(-1.0) == false, "Rejects negative thickness")

func test_vision_toggle_and_signals() -> void:
	print("\n--- Test: Vision Toggle and UI Nodes ---")
	var scene = load("res://ui/components/KiSpectralVision/KiSpectralVision.tscn")
	var node: KiSpectralVision = scene.instantiate() as KiSpectralVision
	root.add_child(node)
	
	node.is_active = false
	node._apply_shader_state()
	_assert(node.color_rect.visible == false, "ShaderRect hidden when inactive")
	_assert(node.state_badge.visible == false, "StateBadge hidden when inactive")
	
	var signal_data := {"emitted": false, "state": false}
	node.vision_toggled.connect(func(active: bool):
		signal_data["emitted"] = true
		signal_data["state"] = active
	)
	
	var res = node.toggle_vision()
	_assert(res == true, "toggle_vision returned true")
	_assert(node.is_active == true, "node.is_active is true")
	_assert(node.color_rect.visible == true, "ShaderRect visible when active")
	_assert(node.state_badge.visible == true, "StateBadge visible when active")
	_assert(signal_data["emitted"] == true, "vision_toggled signal was emitted")
	_assert(signal_data["state"] == true, "vision_toggled carried true state")
	
	# Toggle back to false
	node.toggle_vision()
	_assert(node.is_active == false, "Toggled back to inactive")
	_assert(node.color_rect.visible == false, "ShaderRect hidden again")
	
	node.queue_free()
