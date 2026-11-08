extends SceneTree

# test_additional_deep_verification.gd
# Deep verification of:
# 1. 1-to-1 clean key remapping (unbinding previous action)
# 2. HUD Scale slider dynamic real-time scaling and persistence
# 3. Stack badge rotation on multi-cell items (1x2 -> 2x1)
# 4. Admin granting of Amuleto Vacío Ancestral from F10 / DatabaseAdminWindow

var all_passed = true

func log_res(test_name: String, ok: bool, details: String = ""):
	if ok:
		print("[PASS] %s %s" % [test_name, details])
	else:
		all_passed = false
		printerr("[FAIL] %s %s" % [test_name, details])

func _init():
	_run.call_deferred()

func _run():
	await process_frame
	await process_frame
	print("\n=== STARTING ADDITIONAL DEEP VERIFICATION ===")
	
	# Test 1: 1-to-1 Clean Key Remapping
	print("\n--- TEST 1: 1-to-1 Clean Key Remapping ---")
	var isettings = root.get_node_or_null("InputSettings")
	log_res("InputSettings available", isettings != null)
	if isettings:
		isettings.reset_to_defaults()
		log_res("cast_spell_1 is initially Q", isettings.current_bindings["cast_spell_1"]["code"] == KEY_Q)
		log_res("cast_spell_2 is initially E", isettings.current_bindings["cast_spell_2"]["code"] == KEY_E)
		
		# Rebind cast_spell_1 to E (which was previously bound to cast_spell_2)
		isettings.update_binding("cast_spell_1", "key", KEY_E)
		log_res("cast_spell_1 rebound to E", isettings.current_bindings["cast_spell_1"]["code"] == KEY_E)
		log_res("cast_spell_2 was unbound (code 0) to maintain 1-to-1", isettings.current_bindings["cast_spell_2"]["code"] == 0)
		
		# Reset back to defaults
		isettings.reset_to_defaults()
		log_res("Settings cleanly reset to defaults", isettings.current_bindings["cast_spell_1"]["code"] == KEY_Q and isettings.current_bindings["cast_spell_2"]["code"] == KEY_E)

	# Test 2: HUD Scale Slider & Real-time scaling
	print("\n--- TEST 2: HUD Scale Slider & Real-time Scaling ---")
	var orch = root.get_node_or_null("UIOrchestrator")
	log_res("UIOrchestrator available", orch != null)
	if orch and orch.layout_persistence:
		var scene = load("res://ui/components/PlayerHUD/PlayerHUD.tscn")
		var hud = scene.instantiate()
		root.add_child(hud)
		await process_frame
		
		var hud_margin = hud.get_node_or_null("RootBottom/HUDMargin")
		log_res("HUDMargin exists", hud_margin != null)
		
		orch.layout_persistence.set_hud_scale(1.25)
		await process_frame
		log_res("HUD scale updated to 1.25 in persistence", is_equal_approx(orch.layout_persistence.hud_scale, 1.25))
		log_res("HUDMargin scale matches 1.25 in real time", is_equal_approx(hud_margin.scale.x, 1.25) and is_equal_approx(hud_margin.scale.y, 1.25), "scale: %s" % str(hud_margin.scale))
		
		# Reset to 1.0
		orch.layout_persistence.set_hud_scale(1.0)
		hud.queue_free()

	# Test 3: Multi-cell Stack Badge Rotation (1x2 and 2x1)
	print("\n--- TEST 3: Multi-cell Stack Badge Rotation ---")
	var item_tall = InventoryItem.new()
	item_tall.item_name = "Pergamino"
	item_tall.grid_width = 1
	item_tall.grid_height = 2
	item_tall.quantity = 4
	item_tall.max_stack = 10
	root.add_child(item_tall)
	await process_frame
	
	var badge = item_tall.get_node("StackBadge")
	log_res("Tall item badge exists", badge != null)
	
	# Rotate to 2x1
	item_tall.is_rotated = true
	item_tall.update_size()
	await process_frame
	
	var rot = rad_to_deg(badge.get_global_transform().get_rotation())
	log_res("Rotated 1x2 item badge rotation is 0°", is_zero_approx(rot), "got: %.1f deg" % rot)
	log_res("Rotated 1x2 item badge anchored near (100, 46)", badge.get_global_transform().origin.x >= 95.0 and badge.get_global_transform().origin.y >= 40.0, "pos: %s" % str(badge.get_global_transform().origin))
	item_tall.queue_free()

	# Test 4: Admin Granting of Amuleto Vacío Ancestral
	print("\n--- TEST 4: Admin Granting Amuleto Vacío Ancestral ---")
	var sm = root.get_node_or_null("ShelterManager")
	log_res("ShelterManager available", sm != null)
	if sm:
		sm.shelter_inventory.clear()
		sm.all_items_cache.clear()
		
		# Grant Amuleto Vacío Ancestral
		var amulet_uuid = "00000000-0000-0000-0000-000000000088"
		await sm.admin_add_item("test_user", "", amulet_uuid, 1, 0, 0, false)
		
		log_res("Shelter inventory has 1 item after admin grant", sm.shelter_inventory.size() == 1)
		if sm.shelter_inventory.size() > 0:
			var it = sm.shelter_inventory[0]
			log_res("Granted item display_name is 'Amuleto Vacío Ancestral'", it["display_name"] == "Amuleto Vacío Ancestral", "got: '%s'" % it["display_name"])
			log_res("Granted item definition ID is correct", it["item_definition_id"] == amulet_uuid)
			log_res("Granted item is present in all_items_cache", sm.all_items_cache.has(str(it["id"])))
	
	# Test 5: Stack Splitting In-Container Non-Overlapping Slot
	print("\n--- TEST 5: Stack Splitting Clean Placement ---")
	var SubInvClass = load("res://ui/windows/InventoryWindow/SubInventoryContainer.gd")
	var container = SubInvClass.new()
	container.grid_width = 5
	container.grid_height = 5
	root.add_child(container)
	
	for y in range(5):
		for x in range(5):
			var slot = InventorySlot.new()
			slot.slot_x = x
			slot.slot_y = y
			container.slot_data[Vector2i(x, y)] = slot
			container.add_child(slot)
			
	var item_stack = InventoryItem.new()
	item_stack.item_name = "Madera"
	item_stack.grid_width = 1
	item_stack.grid_height = 1
	item_stack.quantity = 4
	container.place_item(item_stack, 0, 0, 0, false)
	
	item_stack.split_stack()
	await process_frame
	
	log_res("Original stack remaining is 2", item_stack.quantity == 2, "got: %d" % item_stack.quantity)
	log_res("Original stack stays at slot (0, 0)", item_stack.slot_x == 0 and item_stack.slot_y == 0)
	
	# Check that split stack was placed in a different slot (not 0, 0)
	var split_item_slot = Vector2i(-1, -1)
	if sm:
		for it in sm.character_inventory:
			if str(it.get("id")).begins_with("split_"):
				split_item_slot = Vector2i(int(it.get("slot_x", -1)), int(it.get("slot_y", -1)))
				break
	log_res("Split stack placed in different free slot (1, 0)", split_item_slot == Vector2i(1, 0), "got: %s" % str(split_item_slot))
	container.queue_free()

	print("\n=== ADDITIONAL VERIFICATION COMPLETE: ALL PASSED: %s ===" % str(all_passed))
	quit(0 if all_passed else 1)
