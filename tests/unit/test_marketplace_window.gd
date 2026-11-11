extends SceneTree

# test_marketplace_window.gd — Headless Unit Test Suite for MarketplaceWindow (Phase 9.6, ADR 097)
# Verifies: Accent insensitivity, category filtering, sorting, atomic escrow purchase and listing publishing.

const MarketplaceWindow = preload("res://ui/windows/MarketplaceWindow/MarketplaceWindow.gd")

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
	print("\n=== STARTING MARKETPLACE WINDOW TEST SUITE ===")
	
	test_accent_normalization()
	test_category_filtering()
	test_search_filtering()
	test_price_sorting()
	test_purchase_flow_sufficient_silver()
	test_purchase_flow_insufficient_silver()
	test_publish_listing_with_fee()
	test_tab_switching()
	
	print("\n=== MARKETPLACE WINDOW RESULTS: %d/%d PASSED (%d FAILED) ===" % [
		_tests_passed, _tests_run, _tests_failed
	])
	
	if _tests_failed == 0:
		quit(0)
	else:
		quit(1)

func _instantiate_window() -> MarketplaceWindow:
	var scene = load("res://ui/windows/MarketplaceWindow/MarketplaceWindow.tscn")
	var win: MarketplaceWindow = scene.instantiate() as MarketplaceWindow
	root.add_child(win)
	return win

func test_accent_normalization() -> void:
	print("\n--- Test: Accent Normalization ---")
	_assert(MarketplaceWindow.normalize_text("Poción") == "pocion", "Normalizes 'Poción' to 'pocion'")
	_assert(MarketplaceWindow.normalize_text("CORAZA MÁGICA") == "coraza magica", "Normalizes 'CORAZA MÁGICA'")
	_assert(MarketplaceWindow.normalize_text("Ítem Cósmico Ámbar Único") == "item cosmico ambar unico", "Normalizes all Spanish vowels with accents")
	_assert(MarketplaceWindow.normalize_text("Cañaña") == "canana", "Normalizes ñ to n")

func test_category_filtering() -> void:
	print("\n--- Test: Category Filtering ---")
	var win = _instantiate_window()
	
	win.active_category = MarketplaceWindow.Category.ALL
	var all_items = win.get_filtered_listings()
	_assert(all_items.size() == 6, "Category ALL returns all 6 default listings")
	
	win.active_category = MarketplaceWindow.Category.WEAPONS
	var weapons = win.get_filtered_listings()
	_assert(weapons.size() == 2, "Category WEAPONS returns 2 listings (Katana and Dagger)")
	for item in weapons:
		_assert(item["category"] == MarketplaceWindow.Category.WEAPONS, "Item %s has category WEAPONS" % item["name"])
		
	win.active_category = MarketplaceWindow.Category.CONSUMABLES
	var consumables = win.get_filtered_listings()
	_assert(consumables.size() == 2, "Category CONSUMABLES returns 2 listings (Potions/Elixirs)")
	
	win.queue_free()

func test_search_filtering() -> void:
	print("\n--- Test: Search Filtering ---")
	var win = _instantiate_window()
	
	# Búsqueda con acento omitido por el usuario: "pocion" debe encontrar "Poción de Vida Mayor"
	win.current_search_query = "pocion"
	win.active_category = MarketplaceWindow.Category.ALL
	var res = win.get_filtered_listings()
	_assert(res.size() == 1, "Query 'pocion' matches 'Poción de Vida Mayor'")
	_assert(res[0]["id"] == "list_003", "Matched item is list_003")
	
	# Búsqueda mayúscula
	win.current_search_query = "KATANA"
	var res2 = win.get_filtered_listings()
	_assert(res2.size() == 1 and res2[0]["id"] == "list_001", "Query 'KATANA' matches Katana")
	
	# Búsqueda vacía restablece lista completa
	win.current_search_query = "   "
	_assert(win.get_filtered_listings().size() == 6, "Whitespace search query returns full list")
	
	win.queue_free()

func test_price_sorting() -> void:
	print("\n--- Test: Price Sorting ---")
	var win = _instantiate_window()
	win.active_category = MarketplaceWindow.Category.ALL
	win.current_search_query = ""
	
	# Ascendente: primero el más barato (70 silver)
	win.active_sort = MarketplaceWindow.SortOrder.PRICE_ASC
	var asc = win.get_filtered_listings()
	_assert(asc[0]["price"] == 70, "Ascending sort first item has price 70")
	_assert(asc[asc.size() - 1]["price"] == 1200, "Ascending sort last item has price 1200")
	
	# Descendente: primero el más caro (1200 silver)
	win.active_sort = MarketplaceWindow.SortOrder.PRICE_DESC
	var desc = win.get_filtered_listings()
	_assert(desc[0]["price"] == 1200, "Descending sort first item has price 1200")
	_assert(desc[desc.size() - 1]["price"] == 70, "Descending sort last item has price 70")
	
	win.queue_free()

func test_purchase_flow_sufficient_silver() -> void:
	print("\n--- Test: Purchase Flow With Sufficient Silver ---")
	var win = _instantiate_window()
	win.player_silver = 500
	
	# Comprar Coraza (280 silver)
	var target_item = win._listings[1] # list_002, price 280
	var signal_data := {"fired": false, "id": "", "price": 0}
	win.listing_purchased.connect(func(lid, _iid, p):
		signal_data["fired"] = true
		signal_data["id"] = lid
		signal_data["price"] = p
	)
	
	var success = win._execute_purchase(target_item)
	_assert(success == true, "Purchase executed successfully")
	_assert(win.player_silver == 220, "Wallet correctly deducted (500 - 280 = 220 Silver)")
	_assert(signal_data["fired"] == true, "listing_purchased signal emitted")
	_assert(signal_data["id"] == "list_002", "Purchased listing ID matches")
	_assert(signal_data["price"] == 280, "Purchased price matches")
	
	# El listado fue eliminado de la lista activa
	_assert(win._listings.size() == 5, "Listings count decreased by 1")
	var found := false
	for item in win._listings:
		if item["id"] == "list_002":
			found = true
	_assert(not found, "Purchased listing removed from marketplace")
	
	win.queue_free()

func test_purchase_flow_insufficient_silver() -> void:
	print("\n--- Test: Purchase Flow With Insufficient Silver ---")
	var win = _instantiate_window()
	win.player_silver = 100
	
	var expensive_item = win._listings[0] # Katana, price 450
	var success = win._execute_purchase(expensive_item)
	_assert(success == false, "Purchase rejected due to insufficient silver")
	_assert(win.player_silver == 100, "Wallet balance remained untouched")
	_assert(win._listings.size() == 6, "Listings list remains intact")
	
	win.queue_free()

func test_publish_listing_with_fee() -> void:
	print("\n--- Test: Publish Listing With 5% Escrow Fee ---")
	var win = _instantiate_window()
	win.player_silver = 1000
	
	win.sell_item_input.text = "Escudo de Obsidiana Reforzado"
	win.sell_price_input.value = 200.0
	win.sell_qty_input.value = 2.0
	# Total = 400 silver. Tasa 5% = 20 silver.
	
	var initial_count = win._listings.size()
	win._on_publish_pressed()
	
	_assert(win.player_silver == 980, "Escrow fee of 20 silver deducted from wallet (1000 - 20 = 980)")
	_assert(win._listings.size() == initial_count + 1, "New listing added to marketplace")
	_assert(win._listings[0]["name"] == "Escudo de Obsidiana Reforzado", "New listing is at top")
	_assert(win._listings[0]["price"] == 400, "Total price is 400 silver")
	_assert(win.active_tab_index == 0, "Window automatically switched back to buy tab")
	
	win.queue_free()

func test_tab_switching() -> void:
	print("\n--- Test: Tab Switching ---")
	var win = _instantiate_window()
	
	win._switch_tab(1)
	_assert(win.active_tab_index == 1, "Switched to tab 1 (Sell)")
	_assert(win.buy_container.visible == false, "Buy container is hidden")
	_assert(win.sell_container.visible == true, "Sell container is visible")
	
	win._switch_tab(0)
	_assert(win.active_tab_index == 0, "Switched to tab 0 (Buy)")
	_assert(win.buy_container.visible == true, "Buy container is visible")
	_assert(win.sell_container.visible == false, "Sell container is hidden")
	
	win.queue_free()

