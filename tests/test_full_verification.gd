extends SceneTree

# test_full_verification.gd
# Deep automated verification of:
# 1. PlayerHUD LoL-Style action bar, 5 slots, dynamic keybinds, cooldown sweep, mana/hp bars
# 2. Inventory stacking: stack badge visibility, manual drag-and-drop merge
# 3. Shelter farm harvest stacking & detailed user feedback
# 4. Codex discovery flow, sheet context menu, consumption feedback, wiki publication sync

var all_passed: bool = true
var test_count: int = 0
var pass_count: int = 0

func log_result(test_name: String, ok: bool, details: String = ""):
	test_count += 1
	if ok:
		pass_count += 1
		print("[PASS] %s %s" % [test_name, details])
	else:
		all_passed = false
		printerr("[FAIL] %s %s" % [test_name, details])

func _init():
	_run_all_tests.call_deferred()

func _run_all_tests():
	await process_frame
	await process_frame
	
	print("\n=======================================================")
	print("  STARTING MMORPG DEEP VERIFICATION SUITE")
	print("=======================================================\n")
	
	await test_suite_player_hud()
	await test_suite_stacking_badge()
	await test_suite_manual_stack_merge()
	await test_suite_shelter_harvest_stacking()
	await test_suite_codex_secret_publishing()
	
	print("\n=======================================================")
	print("  VERIFICATION COMPLETE: %d / %d TESTS PASSED" % [pass_count, test_count])
	print("  ALL PASSED: %s" % str(all_passed))
	print("=======================================================\n")
	
	quit(0 if all_passed else 1)

# -----------------------------------------------------------------
# 1. PlayerHUD Suite
# -----------------------------------------------------------------
func test_suite_player_hud():
	print("--- SUITE 1: PlayerHUD LoL-Style Action Bar & Vitals ---")
	var isettings = root.get_node_or_null("InputSettings")
	if isettings:
		isettings.reset_to_defaults()
		
	var scene = load("res://ui/components/PlayerHUD/PlayerHUD.tscn")
	log_result("PlayerHUD scene loads", scene != null)
	if not scene: return
	
	var hud = scene.instantiate()
	root.add_child(hud)
	await process_frame
	await process_frame
	
	var container = hud.action_bar_container
	log_result("ActionBarContainer exists", container != null)
	log_result("ActionBarContainer has 5 slots", container.get_child_count() == 5, "count: %d" % container.get_child_count())
	
	var slots = hud.skill_slots
	log_result("All 5 skill slots registered in dictionary", slots.size() == 5, "slots: %s" % str(slots.keys()))
	
	for sid in [3, 1, 2, 4, 5]:
		var s = slots.get(sid)
		var has_elements = s != null and s.has("panel") and s.has("key_label") and s.has("radial_overlay") and s.has("cd_label")
		log_result("Slot %d structural integrity" % sid, has_elements)
		if has_elements:
			log_result("Slot %d min size >= 62x62" % sid, s["panel"].custom_minimum_size.x >= 62 and s["panel"].custom_minimum_size.y >= 62)
	
	# Verify dynamic keybind display
	var key_q = slots[1]["key_label"].text.strip_edges()
	log_result("Slot 1 (Fireball) keybind is 'Q'", key_q == "Q", "got: '%s'" % key_q)
	var key_shift = slots[2]["key_label"].text.strip_edges()
	log_result("Slot 2 (Dash) keybind is 'Shift'", key_shift == "Shift", "got: '%s'" % key_shift)
	var key_lmb = slots[3]["key_label"].text.strip_edges()
	log_result("Slot 3 (Laser) keybind is 'LMB'", key_lmb == "LMB", "got: '%s'" % key_lmb)
	
	# Test HP & Mana updates
	hud.setup("PioneroTest", 85.0)
	hud.update_mana(60.0)
	await process_frame
	log_result("NameLabel text updated", hud.name_label.text == "PioneroTest")
	log_result("ManaBar updated", hud.mana_bar != null and hud.mana_bar.value >= 0.0)
	
	# Cooldown trigger test
	var spell_mgr = root.get_node_or_null("SpellManager")
	if spell_mgr:
		spell_mgr.trigger_cooldown(1) # Fireball
		hud._process(0.01)
		await process_frame
		var rem = spell_mgr.get_cooldown_remaining(1)
		log_result("Cooldown active on spell 1", rem > 0.0, "remaining: %.2fs" % rem)
		log_result("Slot 1 cd_label visible during cooldown", slots[1]["cd_label"].visible)
	
	hud.queue_free()

# -----------------------------------------------------------------
# 2. Inventory Item Stacking Badge Suite
# -----------------------------------------------------------------
func test_suite_stacking_badge():
	print("\n--- SUITE 2: Inventory Item Stacking Badge ---")
	var item = InventoryItem.new()
	item.item_name = "Madera"
	item.grid_width = 1
	item.grid_height = 1
	item.quantity = 1
	item.max_stack = 5
	root.add_child(item)
	await process_frame
	
	var badge = item.get_node_or_null("StackBadge")
	log_result("StackBadge exists on item", badge != null)
	log_result("StackBadge hidden when quantity = 1", badge != null and not badge.visible)
	
	item.quantity = 3
	await process_frame
	var lbl = badge.find_child("CountLabel", true, false) if badge else null
	log_result("StackBadge visible when quantity = 3", badge.visible)
	log_result("StackBadge text is 'x3'", lbl != null and lbl.text == "x3", "got: '%s'" % (lbl.text if lbl else ""))
	
	item.quantity = 5
	await process_frame
	log_result("StackBadge text is 'x5'", lbl != null and lbl.text == "x5", "got: '%s'" % (lbl.text if lbl else ""))
	
	# Rotated item: verify badge remains upright (global rotation 0) and bottom-right
	item.is_rotated = true
	item.update_size()
	await process_frame
	var badge_rot = rad_to_deg(badge.get_global_transform().get_rotation())
	log_result("Rotated item badge stays upright (global rot 0)", is_zero_approx(badge_rot), "got: %.1f deg" % badge_rot)
	log_result("Rotated item badge anchored bottom-right", badge.get_global_transform().origin.x >= 30.0 and badge.get_global_transform().origin.y >= 40.0)
	
	# Test stack splitting (quantity 5 -> 3 and 2)
	item.split_stack()
	await process_frame
	log_result("Stack split reduced original stack to 3", item.quantity == 3, "got: %d" % item.quantity)
	
	item.queue_free()

# -----------------------------------------------------------------
# 3. Manual Stack Merge Suite
# -----------------------------------------------------------------
func test_suite_manual_stack_merge():
	print("\n--- SUITE 3: Manual Drag & Drop Stack Merge ---")
	var slot1 = InventorySlot.new()
	slot1.slot_x = 0
	slot1.slot_y = 0
	root.add_child(slot1)
	
	var slot2 = InventorySlot.new()
	slot2.slot_x = 1
	slot2.slot_y = 0
	root.add_child(slot2)
	
	var item1 = InventoryItem.new()
	item1.item_id = "test_wood_1"
	item1.item_name = "Madera"
	item1.quantity = 2
	item1.max_stack = 5
	slot1.add_child(item1)
	slot1.is_occupied = true
	slot1.occupied_by = item1
	item1.inventory_owner = slot1
	
	var item2 = InventoryItem.new()
	item2.item_id = "test_wood_2"
	item2.item_name = "Madera"
	item2.quantity = 2
	item2.max_stack = 5
	slot2.add_child(item2)
	slot2.is_occupied = true
	slot2.occupied_by = item2
	item2.inventory_owner = slot2
	await process_frame
	
	# Verify slot1 detects merge compatibility with item2
	var can_merge = slot1._can_merge_with(item2, item1)
	log_result("InventorySlot detects compatible stack merge", can_merge)
	
	# Execute merge of item2 (qty 2) onto item1 (qty 2, max 5)
	var controller = root.get_node_or_null("InventoryController")
	if controller:
		var merge_ok = controller.request_stack_merge(item2, item1, slot1)
		await process_frame
		log_result("Stack merge executed successfully", merge_ok)
		log_result("Target stack quantity is now 4", item1.quantity == 4, "quantity: %d" % item1.quantity)
		log_result("Source item was consumed (qty <= 0)", item2.is_queued_for_deletion() or item2.quantity == 0)
	
	# Test partial overflow merge
	var item_base = InventoryItem.new()
	item_base.item_id = "test_iron_base"
	item_base.item_name = "Hierro"
	item_base.quantity = 2
	item_base.max_stack = 3
	root.add_child(item_base)
	
	var item_incoming = InventoryItem.new()
	item_incoming.item_id = "test_iron_in"
	item_incoming.item_name = "Hierro"
	item_incoming.quantity = 3
	item_incoming.max_stack = 3
	root.add_child(item_incoming)
	await process_frame
	
	if controller:
		controller.request_stack_merge(item_incoming, item_base, null)
		await process_frame
		log_result("Overflow merge caps target stack at max_stack (3)", item_base.quantity == 3, "got: %d" % item_base.quantity)
		log_result("Incoming stack retains remainder (2)", item_incoming.quantity == 2, "got: %d" % item_incoming.quantity)
		
	item_base.queue_free()
	item_incoming.queue_free()
	slot1.queue_free()
	slot2.queue_free()

# -----------------------------------------------------------------
# 4. Shelter Farm Harvest Stacking Suite
# -----------------------------------------------------------------
func test_suite_shelter_harvest_stacking():
	print("\n--- SUITE 4: Shelter Farm Harvest Stacking & Reporting ---")
	var sm = root.get_node_or_null("ShelterManager")
	if not sm:
		log_result("ShelterManager autoload available", false)
		return
	
	# Clear test inventory
	sm.shelter_inventory.clear()
	sm.all_items_cache.clear()
	
	var lobby_scene = load("res://ui/windows/ShelterWindow/ShelterLobby.tscn")
	var lobby = lobby_scene.instantiate()
	root.add_child(lobby)
	await process_frame
	
	# Step 1: Deposit 30 Madera (Initial stack, max 50)
	var res1 = await lobby._deposit_farm_item_in_stash("Madera", 30, true)
	log_result("First harvest deposited 30 Madera", res1["total_deposited"] == 30)
	log_result("First harvest placed in 1 new slot", res1["new_slot_qty"] == 30 and res1["stacked_qty"] == 0)
	log_result("Shelter inventory has 1 item", sm.shelter_inventory.size() == 1)
	log_result("Slot 0 quantity is 30", sm.shelter_inventory[0]["quantity"] == 30)
	
	# Step 2: Deposit 25 more Madera (Should fill first stack to 50, remainder 5 in new slot)
	var res2 = await lobby._deposit_farm_item_in_stash("Madera", 25, true)
	log_result("Second harvest deposited 25 Madera", res2["total_deposited"] == 25)
	log_result("Second harvest stacked 20 into existing slot", res2["stacked_qty"] == 20, "stacked: %d" % res2["stacked_qty"])
	log_result("Second harvest created new slot with 5", res2["new_slot_qty"] == 5, "new: %d" % res2["new_slot_qty"])
	log_result("Shelter inventory has 2 items now", sm.shelter_inventory.size() == 2)
	log_result("Stack 1 is capped at 50", sm.shelter_inventory[0]["quantity"] == 50)
	log_result("Stack 2 has remaining 5", sm.shelter_inventory[1]["quantity"] == 5)
	
	# Step 3: Deposit 35 Hierro (Max stack 30: 1 stack of 30, 1 stack of 5)
	var res3 = await lobby._deposit_farm_item_in_stash("Hierro", 35, true)
	log_result("Third harvest deposited 35 Hierro", res3["total_deposited"] == 35)
	log_result("Shelter inventory has 4 items total", sm.shelter_inventory.size() == 4)
	
	var iron_stacks = []
	for it in sm.shelter_inventory:
		if it["display_name"] == "Hierro":
			iron_stacks.append(it["quantity"])
	iron_stacks.sort()
	log_result("Hierro capped at max_stack 30 (stacks: [5, 30])", iron_stacks == [5, 30], "got: %s" % str(iron_stacks))
	
	# Step 4: Overflow Protection test (fill stash and verify surplus is preserved in lost_qty)
	for y in range(5):
		for x in range(10):
			var free_s = lobby._find_free_stash_slot(1, 1)
			if free_s != Vector2i(-1, -1):
				sm.shelter_inventory.append({
					"slot_x": free_s.x, "slot_y": free_s.y, "grid_width": 1, "grid_height": 1,
					"display_name": "Relleno", "quantity": 1
				})
	var overflow_res = await lobby._deposit_farm_item_in_stash("Piedra", 10, true)
	log_result("Overflow detected when stash full (remanente retenido)", overflow_res["lost_qty"] == 10 and overflow_res["total_deposited"] == 0)
	
	lobby.queue_free()

# -----------------------------------------------------------------
# 5. Codex Secret & Publishing Suite
# -----------------------------------------------------------------
func test_suite_codex_secret_publishing():
	print("\n--- SUITE 5: Codex Secret Flow & Web Publishing ---")
	var codex_scene = load("res://ui/windows/CodexDiaryWindow/CodexDiaryWindow.tscn")
	var codex = codex_scene.instantiate()
	root.add_child(codex)
	await process_frame
	
	# Verify secret starts unacquired
	var is_acq_init = codex.is_secret_acquired("item_amuleto_vacio")
	log_result("Amuleto Vacío initially unacquired", not is_acq_init)
	
	# Consume Discovery Scroll -> unlock secret
	codex.unlock_secret_from_sheet("item_amuleto_vacio", "Amuleto Vacío Ancestral")
	await process_frame
	var is_acq_after = codex.is_secret_acquired("item_amuleto_vacio")
	log_result("Amuleto Vacío acquired after reading sheet", is_acq_after)
	
	# Publish entry to World (+500 Silver)
	var target_entry = null
	for e in codex.discoveries:
		if e["id"] == "item_amuleto_vacio":
			target_entry = e
			break
	log_result("Found Amuleto Vacío entry in Codex", target_entry != null)
	
	if target_entry:
		codex._on_publish_entry(target_entry, "PioneroDeepSeek")
		await process_frame
		log_result("Entry marked as public", target_entry["is_public"])
		log_result("Pioneer attributed to PioneroDeepSeek", target_entry["pioneer"] == "PioneroDeepSeek")
		
		# Verify disk file updated with is_public: true
		var md_path = "docs/wiki_data/item_amuleto_vacio.md"
		if FileAccess.file_exists(md_path):
			var f = FileAccess.open(md_path, FileAccess.READ)
			var content = f.get_as_text()
			f.close()
			log_result("Wiki file updated with is_public: true", "is_public: true" in content)
			log_result("Wiki file contains pioneer name", "PioneroDeepSeek" in content)
	
	codex.queue_free()
