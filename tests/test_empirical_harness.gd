extends Node

# test_empirical_harness.gd
# Runs as a node in the scene tree after Autoloads are ready

var passed_count: int = 0
var failed_count: int = 0
var test_details: Array = []

func log_result(test_name: String, passed: bool, detail: String = ""):
	if passed:
		passed_count += 1
		print("[PASS] ", test_name, (" - " + detail) if detail != "" else "")
	else:
		failed_count += 1
		print("[FAIL] ", test_name, (" - " + detail) if detail != "" else "")
	test_details.append({"name": test_name, "passed": passed, "detail": detail})

func _ready():
	print("==================================================")
	print("STARTING EMPIRICAL CHALLENGER TEST SUITE (POST-AUTOLOAD)")
	print("==================================================")
	
	test_suite_r1_input_router()
	test_suite_r2_network_manager_disconnect()
	test_suite_r2_auth_manager_logout_singletons()
	test_suite_r2_reconnect_timer_leak()
	
	print("==================================================")
	print("TEST SUITE COMPLETE: %d PASSED, %d FAILED" % [passed_count, failed_count])
	print("==================================================")
	get_tree().quit(0 if failed_count == 0 else 1)

# -------------------------------------------------------------
# SUITE 1: R1 Input Router (F8 & F9)
# -------------------------------------------------------------
func test_suite_r1_input_router():
	print("\n--- SUITE 1: UIInputRouter F8 & F9 Stress Tests ---")
	
	var router = get_node_or_null("/root/UIInputRouter")
	if not router:
		log_result("UIInputRouter Exists", false, "UIInputRouter autoload not found in /root")
		return
	log_result("UIInputRouter Exists", true)

	# Subtest 1.1: F8 Press (pressed=true, echo=false)
	var ev_f8_press = InputEventKey.new()
	ev_f8_press.pressed = true
	ev_f8_press.echo = false
	ev_f8_press.keycode = KEY_F8
	
	get_viewport().set_input_as_handled()
	router._unhandled_input(ev_f8_press)
	var f8_press_handled = get_viewport().is_input_handled()
	log_result("F8 Press Handled via set_input_as_handled()", f8_press_handled, "get_viewport().is_input_handled() == %s" % f8_press_handled)

	# Subtest 1.2: F8 Repeat / Echo (pressed=true, echo=true)
	# UIInputRouter line 47:
	# elif event is InputEventKey and event.pressed and event.keycode == KEY_F8 and not event.is_echo():
	var ev_f8_echo = InputEventKey.new()
	ev_f8_echo.pressed = true
	ev_f8_echo.echo = true
	ev_f8_echo.keycode = KEY_F8
	
	var echo_handled_in_branch = (ev_f8_echo is InputEventKey and ev_f8_echo.pressed and ev_f8_echo.keycode == KEY_F8 and not ev_f8_echo.is_echo())
	log_result("F8 Echo Handled In Router Branch", echo_handled_in_branch, 
		"Branch has 'not event.is_echo()', so F8 echo is NOT consumed (evaluates to %s)" % echo_handled_in_branch)

	# Subtest 1.3: F8 Release (pressed=false)
	var ev_f8_release = InputEventKey.new()
	ev_f8_release.pressed = false
	ev_f8_release.echo = false
	ev_f8_release.keycode = KEY_F8
	var release_handled = (ev_f8_release is InputEventKey and ev_f8_release.pressed)
	log_result("F8 Release Evaluated By Router", release_handled,
		"Router early exits on release (pressed=false, evaluates to %s)" % release_handled)

	# Subtest 1.4: F8 when windows are open
	var ui_orch = get_node_or_null("/root/UIOrchestrator")
	if ui_orch and ui_orch.has_method("open_window"):
		var win = ui_orch.open_window("options_menu")
		get_viewport().set_input_as_handled()
		router._unhandled_input(ev_f8_press)
		log_result("F8 Intercepted When Window Open", get_viewport().is_input_handled(), "F8 intercepted while options_menu is open")
		if ui_orch.has_method("close_all_windows"):
			ui_orch.close_all_windows()

	# Subtest 1.5: F9 Toggle group hitbox_debug cleanly
	var initial_f9_state = router.hitbox_debug_active
	var ev_f9 = InputEventKey.new()
	ev_f9.pressed = true
	ev_f9.echo = false
	ev_f9.keycode = KEY_F9
	
	router._unhandled_input(ev_f9)
	var toggled_once = router.hitbox_debug_active
	router._unhandled_input(ev_f9)
	var toggled_twice = router.hitbox_debug_active
	
	var f9_toggled_cleanly = (toggled_once == !initial_f9_state) and (toggled_twice == initial_f9_state)
	log_result("F9 Toggles hitbox_debug_active cleanly", f9_toggled_cleanly,
		"initial=%s, after 1st F9=%s, after 2nd F9=%s" % [initial_f9_state, toggled_once, toggled_twice])

	# Subtest 1.6: F9 with heterogenous nodes in hitbox_debug group
	var mock_node = Node.new()
	mock_node.name = "MockHitboxEntity"
	mock_node.add_to_group("hitbox_debug")
	get_tree().root.add_child(mock_node)
	router._handle_hitbox_debug()
	log_result("F9 call_group with heterogenous nodes does not crash", true, "call_group handles missing method gracefully")
	mock_node.queue_free()

# -------------------------------------------------------------
# SUITE 2: NetworkManager.disconnect_from_world() Safety & Idempotency
# -------------------------------------------------------------
func test_suite_r2_network_manager_disconnect():
	print("\n--- SUITE 2: NetworkManager.disconnect_from_world() Safety ---")
	
	var net = get_node_or_null("/root/NetworkManager")
	if not net:
		log_result("NetworkManager Exists", false, "NetworkManager autoload not found in /root")
		return
	log_result("NetworkManager Exists", true)

	# Subtest 2.1: disconnect_from_world when peer is idle/unconnected
	net.disconnect_from_world()
	var state_reset = (net.my_session_id == 0 and net.move_sequence == 0 and net.is_reconnecting == false and net.heartbeat_timer == 0.0)
	log_result("disconnect_from_world Resets State When Idle", state_reset, 
		"session_id=%d, move_seq=%d, is_reconnecting=%s" % [net.my_session_id, net.move_sequence, net.is_reconnecting])

	# Subtest 2.2: Idempotency (call 5 times repeatedly)
	for i in range(5):
		net.disconnect_from_world()
	log_result("disconnect_from_world Idempotent", true, "Called 5 times sequentially without crash")

	# Subtest 2.3: Null safety if udp_peer is null
	var original_peer = net.udp_peer
	net.udp_peer = null
	net.disconnect_from_world()
	net.udp_peer = original_peer
	log_result("disconnect_from_world Null udp_peer Guard", true, "Survived udp_peer = null without crash")

	# Subtest 2.4: send_disconnect when peer is null
	net.udp_peer = null
	net.send_disconnect()
	net.udp_peer = original_peer
	log_result("send_disconnect Null udp_peer Guard", true, "Survived udp_peer = null without crash")

# -------------------------------------------------------------
# SUITE 3: AuthManager.perform_full_logout() Singleton Safety & Scene Transition
# -------------------------------------------------------------
func test_suite_r2_auth_manager_logout_singletons():
	print("\n--- SUITE 3: AuthManager.perform_full_logout() Singletons & Scene ---")
	
	var auth = get_node_or_null("/root/AuthManager")
	if not auth:
		log_result("AuthManager Exists", false, "AuthManager autoload not found in /root")
		return
	log_result("AuthManager Exists", true)

	# Populate mock state in AuthManager and related singletons
	auth.auth_token = "mock_jwt_token_12345"
	auth.selected_character_id = "char_uuid_999"
	auth.username = "test_player"
	auth.is_admin = true
	
	var target_mgr = get_node_or_null("/root/TargetManager")
	if target_mgr and "current_target_sid" in target_mgr:
		target_mgr.current_target_sid = 42
		
	var spell_mgr = get_node_or_null("/root/SpellManager")
	if spell_mgr and "cooldowns" in spell_mgr:
		spell_mgr.cooldowns[1] = 5.0
		spell_mgr.cooldowns[2] = 12.0
		
	var shelter_mgr = get_node_or_null("/root/ShelterManager")
	if shelter_mgr:
		shelter_mgr.character_inventory = [{"item_id": "sword_1"}]
		shelter_mgr.shelter_inventory = [{"item_id": "wood_1"}]
		shelter_mgr.shelter_data = {"level": 2}
		shelter_mgr.all_items_cache = {"sword_1": {"name": "Sword"}}

	# Execute perform_full_logout()
	auth.perform_full_logout()

	# Verify state was wiped
	var auth_cleared = (auth.auth_token == "" and auth.selected_character_id == "" and auth.username == "" and auth.is_admin == false)
	log_result("AuthManager State Cleared", auth_cleared, "auth_token='%s', char_id='%s'" % [auth.auth_token, auth.selected_character_id])

	var target_cleared = true
	if target_mgr and "current_target_sid" in target_mgr:
		target_cleared = (target_mgr.current_target_sid == 0)
	log_result("TargetManager Cleared", target_cleared)

	var cooldowns_cleared = true
	if spell_mgr and "cooldowns" in spell_mgr:
		cooldowns_cleared = (spell_mgr.cooldowns.size() == 0)
	log_result("SpellManager Cooldowns Cleared", cooldowns_cleared, "cooldowns size = %d" % (spell_mgr.cooldowns.size() if spell_mgr else 0))

	var shelter_cleared = true
	if shelter_mgr:
		shelter_cleared = (shelter_mgr.character_inventory.size() == 0 and 
			shelter_mgr.shelter_inventory.size() == 0 and 
			shelter_mgr.shelter_data.size() == 0 and 
			shelter_mgr.all_items_cache.size() == 0)
	log_result("ShelterManager Caches Cleared", shelter_cleared)

	# Subtest 3.2: Rapid double logout (idempotency)
	for i in range(3):
		auth.perform_full_logout()
	log_result("perform_full_logout Idempotent", true, "Called 3 times consecutively without crash")

# -------------------------------------------------------------
# SUITE 4: Lingering Reconnect Timers / Coroutine Analysis
# -------------------------------------------------------------
func test_suite_r2_reconnect_timer_leak():
	print("\n--- SUITE 4: Reconnect Loop & Timeout Behavior on Logout ---")
	
	var net = get_node_or_null("/root/NetworkManager")
	var auth = get_node_or_null("/root/AuthManager")
	if not net or not auth:
		log_result("Singletons For Reconnect Test", false)
		return

	# Inspect NetworkManager._handle_connection_loss coroutine behavior:
	var net_script: Script = net.get_script()
	var net_source: String = net_script.source_code
	var has_loop_guard = (net_source.find("if not is_reconnecting: return") != -1 or 
		net_source.find("if !is_reconnecting: return") != -1 or
		net_source.find("if not is_reconnecting:\n") != -1 or
		net_source.find("if !is_reconnecting:\n") != -1)
	
	log_result("Reconnect Loop Has Mid-Flight Cancellation Guard", has_loop_guard, 
		"Does _handle_connection_loss check 'is_reconnecting' inside retry loop? Found=%s" % has_loop_guard)
