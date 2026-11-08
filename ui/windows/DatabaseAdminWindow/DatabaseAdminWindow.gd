extends Panel

# DatabaseAdminWindow.gd
# Real-time database inspector & regional tax governance viewer.

@onready var items_tree: Tree = $VBox/TabContainer/Items/ItemsTree
@onready var spells_tree: Tree = $VBox/TabContainer/Spells/SpellsTree
@onready var wallets_tree: Tree = $VBox/TabContainer/Wallets/WalletsTree
@onready var taxes_tree: Tree = $VBox/TabContainer/Taxes/TaxesTree

@onready var lbl_items_count: Label = $VBox/SummaryHBox/ItemsCount
@onready var lbl_spells_count: Label = $VBox/SummaryHBox/SpellsCount
@onready var lbl_wallets_count: Label = $VBox/SummaryHBox/WalletsCount
@onready var lbl_status: Label = $VBox/FooterHBox/StatusLabel
@onready var search_edit: LineEdit = $VBox/FilterHBox/SearchEdit

var cached_data: Dictionary = {}
var _is_dragging = false
var _has_been_moved = false
var _drag_offset = Vector2.ZERO

func _ready():
	custom_minimum_size = Vector2(750, 550)
	size = Vector2(750, 550)
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	$VBox/HeaderHBox/Title.gui_input.connect(_on_title_gui_input)
	$VBox/HeaderHBox/CloseButton.pressed.connect(func():
		if has_node("/root/UIOrchestrator"):
			get_node("/root/UIOrchestrator").close_window("database_admin")
		else:
			hide()
	)
	
	$VBox/FooterHBox/RefreshButton.pressed.connect(refresh_database_overview)
	search_edit.text_changed.connect(_on_search_changed)

	_setup_trees()
	
	if items_tree:
		items_tree.item_activated.connect(_on_item_tree_activated)
		
		# Botón explícito para otorgar ítem seleccionado
		var items_tab = $VBox/TabContainer/Items
		if items_tab:
			var grant_btn = Button.new()
			grant_btn.text = "🎁 Otorgar Ítem Seleccionado al Almacén"
			grant_btn.custom_minimum_size = Vector2(0, 32)
			grant_btn.pressed.connect(_on_grant_button_pressed)
			items_tab.add_child(grant_btn)

func initialize_window(_params = {}):
	refresh_database_overview()

func _on_item_tree_activated():
	_on_grant_button_pressed()

func _on_grant_button_pressed():
	if not items_tree: return
	var selected = items_tree.get_selected()
	if not selected:
		lbl_status.text = "Selecciona un ítem de la lista para otorgarlo."
		return
		
	var item_def_id = selected.get_text(0)
	var item_name = selected.get_text(1)
	_grant_item_by_definition(item_def_id, item_name)

func _grant_item_by_definition(item_def_id: String, item_name: String) -> void:
	var sm = get_node_or_null("/root/ShelterManager")
	if not sm: return
	
	var user_id = AuthManager.user_id if AuthManager and AuthManager.user_id != "" else "local_user"
	
	var occupied = {}
	for it in sm.shelter_inventory:
		var sx = it.get("slot_x")
		var sy = it.get("slot_y")
		if sx != null and sy != null:
			var gw = it.get("grid_width", 1)
			var gh = it.get("grid_height", 1)
			for dy in range(gh):
				for dx in range(gw):
					occupied[Vector2i(int(sx) + dx, int(sy) + dy)] = true
					
	var free_slot = Vector2i(-1, -1)
	for y in range(5):
		for x in range(10):
			if not occupied.has(Vector2i(x, y)):
				free_slot = Vector2i(x, y)
				break
		if free_slot != Vector2i(-1, -1):
			break
			
	if free_slot == Vector2i(-1, -1):
		lbl_status.text = "Error: Almacén lleno, no hay casillas libres."
		if has_node("/root/UIOrchestrator"):
			var orch = get_node("/root/UIOrchestrator")
			if orch.has_method("show_toast"):
				orch.show_toast("⚠️ ALMACÉN LLENO", "No hay espacio en el Almacén para otorgar el ítem.", Color(1.0, 0.5, 0.2))
		return
		
	await sm.admin_add_item(user_id, "", item_def_id, 1, free_slot.x, free_slot.y, false)
	lbl_status.text = "🎁 '%s' otorgado exitosamente en (%d, %d)." % [item_name, free_slot.x, free_slot.y]
	
	if has_node("/root/UIOrchestrator"):
		var orch = get_node("/root/UIOrchestrator")
		if orch.has_method("show_toast"):
			orch.show_toast("🎁 ÍTEM ADMIN OTORGADO", "'%s' añadido a tu Almacén del Refugio." % item_name, Color(0.3, 0.95, 0.5))
			
	if has_node("/root/InventoryController"):
		get_node("/root/InventoryController").reload_inventory_data()
	else:
		var inv_uis = get_tree().get_nodes_in_group("inventory_ui")
		for inv in inv_uis:
			if inv.has_method("_request_data_refresh"):
				inv._request_data_refresh()

func _setup_trees():
	# Items Tree
	if items_tree:
		items_tree.columns = 6
		items_tree.hide_root = true
		items_tree.set_column_title(0, "ID")
		items_tree.set_column_title(1, "Name")
		items_tree.set_column_title(2, "Category")
		items_tree.set_column_title(3, "Rarity")
		items_tree.set_column_title(4, "Size")
		items_tree.set_column_title(5, "Durability")
		items_tree.column_titles_visible = true

	# Spells Tree
	if spells_tree:
		spells_tree.columns = 7
		spells_tree.hide_root = true
		spells_tree.set_column_title(0, "ID")
		spells_tree.set_column_title(1, "Name")
		spells_tree.set_column_title(2, "Shape")
		spells_tree.set_column_title(3, "Cooldown")
		spells_tree.set_column_title(4, "Damage")
		spells_tree.set_column_title(5, "Range")
		spells_tree.set_column_title(6, "Speed")
		spells_tree.column_titles_visible = true

	# Wallets Tree
	if wallets_tree:
		wallets_tree.columns = 4
		wallets_tree.hide_root = true
		wallets_tree.set_column_title(0, "Character Name")
		wallets_tree.set_column_title(1, "Silver (Soft)")
		wallets_tree.set_column_title(2, "Gold (Premium)")
		wallets_tree.set_column_title(3, "Character ID")
		wallets_tree.column_titles_visible = true

	# Taxes Tree
	if taxes_tree:
		taxes_tree.columns = 5
		taxes_tree.hide_root = true
		taxes_tree.set_column_title(0, "Zone ID")
		taxes_tree.set_column_title(1, "Tax Rate %")
		taxes_tree.set_column_title(2, "Accumulated Silver")
		taxes_tree.set_column_title(3, "Reigning Guild")
		taxes_tree.set_column_title(4, "Last Payout")
		taxes_tree.column_titles_visible = true

func refresh_database_overview():
	lbl_status.text = "Fetching live overview from Gateway..."
	
	var res = await APIClient.get_request("/admin/db/overview")
	if res.has("error"):
		lbl_status.text = "Error: " + str(res["error"])
		return

	if res.has("data") and res["data"] is Dictionary:
		cached_data = res["data"]
	else:
		cached_data = res

	_render_data(search_edit.text.strip_edges().to_lower())
	lbl_status.text = "Synchronized at " + Time.get_time_string_from_system()

func _on_search_changed(new_text: String):
	_render_data(new_text.strip_edges().to_lower())

func _render_data(filter_text: String):
	if cached_data.is_empty(): return

	# 1. Summaries
	lbl_items_count.text = "Total Items: %d" % cached_data.get("total_items", 0)
	lbl_spells_count.text = "Total Spells: %d" % cached_data.get("total_spells", 0)
	lbl_wallets_count.text = "Total Wallets: %d" % cached_data.get("total_wallets", 0)

	# 2. Items Tree
	if items_tree:
		items_tree.clear()
		var root = items_tree.create_item()
		var items = cached_data.get("recent_item_catalog", [])
		for itm in items:
			var name_str = str(itm.get("name", ""))
			if filter_text != "" and not name_str.to_lower().contains(filter_text) and not str(itm.get("id")).contains(filter_text):
				continue
			var item = items_tree.create_item(root)
			item.set_text(0, str(itm.get("id", "")))
			item.set_text(1, name_str)
			item.set_text(2, str(itm.get("category", "")))
			item.set_text(3, str(itm.get("rarity", "")))
			item.set_text(4, "%dx%d" % [itm.get("width", 1), itm.get("height", 1)])
			item.set_text(5, str(itm.get("durability", 100)))

	# 3. Spells Tree
	if spells_tree:
		spells_tree.clear()
		var root = spells_tree.create_item()
		var spells = cached_data.get("recent_spells_catalog", [])
		for spl in spells:
			var name_str = str(spl.get("name", ""))
			if filter_text != "" and not name_str.to_lower().contains(filter_text) and not str(spl.get("id")).contains(filter_text):
				continue
			var item = spells_tree.create_item(root)
			item.set_text(0, str(spl.get("id", "")))
			item.set_text(1, name_str)
			item.set_text(2, str(spl.get("shape", "")))
			item.set_text(3, "%d ms" % spl.get("cooldown_ms", 0))
			item.set_text(4, "%.1f" % spl.get("damage", 0.0))
			item.set_text(5, "%.1fm" % spl.get("range", 0.0))
			item.set_text(6, "%.1f m/s" % spl.get("speed", 0.0))

	# 4. Wallets Tree
	if wallets_tree:
		wallets_tree.clear()
		var root = wallets_tree.create_item()
		var wallets = cached_data.get("recent_wallets_catalog", [])
		for w in wallets:
			var name_str = str(w.get("character_name", ""))
			if filter_text != "" and not name_str.to_lower().contains(filter_text):
				continue
			var item = wallets_tree.create_item(root)
			item.set_text(0, name_str)
			item.set_text(1, "%d Silver" % w.get("silver", 0))
			item.set_text(2, "%d Gold" % w.get("gold", 0))
			item.set_text(3, str(w.get("character_id", "")))

	# 5. Taxes Tree
	if taxes_tree:
		taxes_tree.clear()
		var root = taxes_tree.create_item()
		var taxes = cached_data.get("regional_tax_reserves", [])
		for t in taxes:
			var item = taxes_tree.create_item(root)
			item.set_text(0, "Zone %d" % t.get("zone_id", 0))
			item.set_text(1, "%.2f%%" % t.get("tax_rate_percent", 0.0))
			item.set_text(2, "%d Silver" % t.get("accumulated_silver", 0))
			var guild = t.get("reigning_guild_id", "")
			item.set_text(3, guild if guild != "" else "Unclaimed (Neutral)")
			item.set_text(4, str(t.get("last_payout_at", "Never")))

func _on_title_gui_input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_is_dragging = event.pressed
			if _is_dragging:
				_has_been_moved = true
				_drag_offset = get_global_mouse_position() - global_position
	elif event is InputEventMouseMotion and _is_dragging:
		var new_pos = get_global_mouse_position() - _drag_offset
		var vp_size = get_viewport_rect().size
		new_pos.x = clamp(new_pos.x, 0, vp_size.x - size.x)
		new_pos.y = clamp(new_pos.y, 0, vp_size.y - size.y)
		global_position = new_pos
