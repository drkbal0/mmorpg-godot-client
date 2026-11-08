extends BaseWindow

# VendorWindow.gd - Puesto del Mercader de Supervivencia del Refugio
# Permite comprar insumos básicos y vender botín/chatarra extraída con saldo Silver e idempotencia.

@onready var items_container = find_child("VendorItemsContainer", true, false)
@onready var silver_label = find_child("SilverLabel", true, false)
@onready var tax_label = find_child("TaxLabel", true, false)
@onready var status_label = find_child("StatusLabel", true, false)

const SHELTER_SUPPLIES = [
	{"id": "1c19c50b-d8d4-47b3-8a1d-a5057eb99971", "name": "Poción de Vida Menor", "desc": "Restaura 30 HP al instante", "price": 45, "type": "Consumible", "w": 1, "h": 1},
	{"id": "cafc91c9-a7cb-444f-919a-5d55ba108c24", "name": "Poción de Maná", "desc": "Restaura 30 Maná al instante", "price": 45, "type": "Consumible", "w": 1, "h": 1},
	{"id": "df6bba60-cf32-46d9-bee2-cdcf27256d8c", "name": "Cuchillo", "desc": "Arma secundaria ligera 1x1", "price": 25, "type": "Equipo", "w": 1, "h": 1},
	{"id": "e4d262bf-ad4d-4bc0-91d4-c6290db2e43c", "name": "Lote de Madera (x5)", "desc": "Material de construcción", "price": 20, "type": "Material", "w": 1, "h": 1},
	{"id": "d6871f24-5b7d-4d73-8b70-eb85ccdad6b7", "name": "Lote de Hierro (x2)", "desc": "Metal reforzado", "price": 60, "type": "Material", "w": 1, "h": 1}
]

var player_silver: int = 500
var regional_tax_percent: float = 5.0 # Tasa regional de la zona

func _ready() -> void:
	window_id = "vendor_window"
	super._ready()
	set_title("PUESTO DE SUPERVIVENCIA (MERCADER DEL REFUGIO)")
	_populate_vendor_catalog()
	_update_wallet_display()

func initialize_window(params: Dictionary) -> void:
	if params.has("silver"):
		player_silver = params["silver"]
	if params.has("tax"):
		regional_tax_percent = params["tax"]
	_update_wallet_display()
	
	# Posicionamiento inteligente: Mercado a la izquierda, Almacén a la derecha (sin taparse)
	var vp = get_viewport_rect().size
	if vp.x > 0 and vp.y > 0:
		position = Vector2(40, max(50.0, (vp.y - 480.0) / 2.0))
		
	# Si el almacén no está abierto, abrirlo automáticamente a la derecha
	if UIOrchestrator and not UIOrchestrator.is_window_open("inventory"):
		var cid = AuthManager.selected_character_id if AuthManager else ""
		var inv_node = UIOrchestrator.open_window("inventory", {
			"character_id": cid,
			"is_shelter_context": true
		})
		if inv_node and inv_node is Control:
			inv_node.position = Vector2(510, max(50.0, (vp.y - 480.0) / 2.0))
			if "_has_been_moved" in inv_node:
				inv_node._has_been_moved = true

func _update_wallet_display() -> void:
	if silver_label:
		silver_label.text = "SALDO SILVER: " + str(player_silver)
	if tax_label:
		tax_label.text = "Impuesto Territorial: %.1f%% (Retención automática)" % regional_tax_percent

func _populate_vendor_catalog() -> void:
	if not items_container: return
	
	for child in items_container.get_children():
		child.queue_free()
		
	for item in SHELTER_SUPPLIES:
		var card = PanelContainer.new()
		var sb = StyleBoxFlat.new()
		sb.bg_color = Color(0.08, 0.10, 0.14, 0.90)
		sb.border_width_left = 1
		sb.border_width_top = 1
		sb.border_width_right = 1
		sb.border_width_bottom = 1
		sb.border_color = Color(0.2, 0.4, 0.6, 0.6)
		sb.corner_radius_top_left = 6
		sb.corner_radius_top_right = 6
		sb.corner_radius_bottom_right = 6
		sb.corner_radius_bottom_left = 6
		card.add_theme_stylebox_override("panel", sb)
		
		var pad = MarginContainer.new()
		pad.add_theme_constant_override("margin_left", 10)
		pad.add_theme_constant_override("margin_top", 8)
		pad.add_theme_constant_override("margin_right", 10)
		pad.add_theme_constant_override("margin_bottom", 8)
		card.add_child(pad)
		
		var hbox = HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 12)
		pad.add_child(hbox)
		
		# Info Vbox
		var vbox = VBoxContainer.new()
		vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		var name_lbl = Label.new()
		name_lbl.text = item["name"]
		name_lbl.add_theme_font_size_override("font_size", 13)
		name_lbl.add_theme_color_override("font_color", Color(0.3, 0.9, 1.0))
		vbox.add_child(name_lbl)
		
		var desc_lbl = Label.new()
		desc_lbl.text = item["desc"]
		desc_lbl.add_theme_font_size_override("font_size", 11)
		desc_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		vbox.add_child(desc_lbl)
		
		hbox.add_child(vbox)
		
		# Price & Buy button
		var price_box = VBoxContainer.new()
		price_box.alignment = BoxContainer.ALIGNMENT_CENTER
		
		var final_price = int(ceil(float(item["price"]) * (1.0 + regional_tax_percent / 100.0)))
		var p_lbl = Label.new()
		p_lbl.text = "%d Silver" % final_price
		p_lbl.add_theme_font_size_override("font_size", 12)
		p_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
		p_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		price_box.add_child(p_lbl)
		
		var buy_btn = Button.new()
		buy_btn.text = "COMPRAR"
		buy_btn.custom_minimum_size = Vector2(85, 28)
		buy_btn.pressed.connect(_on_buy_item.bind(item, final_price))
		price_box.add_child(buy_btn)
		
		hbox.add_child(price_box)
		items_container.add_child(card)

func _on_buy_item(item: Dictionary, price: int) -> void:
	if player_silver < price:
		_show_status("¡Silver insuficiente para comprar " + item["name"] + "!", Color(1.0, 0.3, 0.3))
		return
	
	_show_status("Procesando compra de " + item["name"] + "...", Color(0.8, 0.8, 1.0))
	
	# 1. Buscar primer espacio libre en el Almacén del Refugio (10 columnas x 5 filas)
	var free_slot = _find_free_stash_slot(item.get("w", 1), item.get("h", 1))
	if free_slot == Vector2i(-1, -1):
		_show_status("¡Almacén lleno! No hay espacio libre para " + item["name"] + ".", Color(1.0, 0.4, 0.4))
		return
		
	var user_id = AuthManager.user_id if AuthManager and AuthManager.user_id != "" else ""
	var success = await ShelterManager.admin_add_item(user_id, "", item["id"], 1, free_slot.x, free_slot.y, false)
	
	if success:
		player_silver -= price
		_update_wallet_display()
		_show_status("Comprado: %s (-%d Silver). ¡Guardado en Almacén (%d,%d)!" % [item["name"], price, free_slot.x, free_slot.y], Color(0.3, 1.0, 0.5))
		print("[VendorWindow] Compra exitosa: %s por %d Silver en (%d,%d)" % [item["name"], price, free_slot.x, free_slot.y])
		
		# Refrescar datos en ShelterManager y forzar re-render visual en el inventario abierto
		await ShelterManager.fetch_inventory("")
		var inv_uis = get_tree().get_nodes_in_group("inventory_ui")
		for inv in inv_uis:
			if inv.has_method("_request_data_refresh"):
				inv._request_data_refresh()
	else:
		_show_status("Error en el servidor al almacenar el ítem.", Color(1.0, 0.3, 0.3))

func _find_free_stash_slot(w: int, h: int) -> Vector2i:
	var occupied = {}
	for it in ShelterManager.shelter_inventory:
		var sx = it.get("slot_x")
		var sy = it.get("slot_y")
		if sx != null and sy != null:
			var gw = it.get("grid_width", 1)
			var gh = it.get("grid_height", 1)
			for dy in range(gh):
				for dx in range(gw):
					occupied[Vector2i(int(sx) + dx, int(sy) + dy)] = true
					
	for y in range(5):
		for x in range(10):
			var fits = true
			for dy in range(h):
				for dx in range(w):
					var check_pos = Vector2i(x + dx, y + dy)
					if check_pos.x >= 10 or check_pos.y >= 5 or occupied.has(check_pos):
						fits = false
						break
				if not fits: break
			if fits:
				return Vector2i(x, y)
	return Vector2i(-1, -1)

func _show_status(msg: String, color: Color) -> void:
	if status_label:
		status_label.text = msg
		status_label.add_theme_color_override("font_color", color)

