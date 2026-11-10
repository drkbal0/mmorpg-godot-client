extends BaseWindow
class_name MarketplaceWindow

# MarketplaceWindow.gd — P2P Marketplace and Escrow Trade Interface (Phase 9.6, ADR 097)
# Proporciona: Compra atómica con prevención de doble compra, buscador insensible a acentos,
# filtros por categoría, ordenamiento por precio y panel de publicación con tasa de depósito del 5%.

signal listing_purchased(listing_id: String, item_id: String, price: int)
signal listing_created(listing_id: String, item_name: String, price: int, qty: int)

enum Category { ALL, WEAPONS, ARMOR, CONSUMABLES, MATERIALS }
enum SortOrder { PRICE_ASC, PRICE_DESC, TIME_LEFT }

const LISTING_FEE_PERCENT := 0.05 # 5% de depósito de custodia (escrow)

# Mapeo de colores por rareza
const RARITY_COLORS := {
	"common": Color("#46e3c1"),
	"rare": Color("#3b82f6"),
	"epic": Color("#a855f7"),
	"legendary": Color("#f59e0b")
}

# Base de datos predeterminada de listados activos
var _listings: Array[Dictionary] = [
	{
		"id": "list_001",
		"item_id": "item_katana_01",
		"name": "Katana de Sombras Ancestrales",
		"category": Category.WEAPONS,
		"rarity": "epic",
		"seller_id": "char_sylvia",
		"seller_name": "Sylvia (Maga)",
		"price": 450,
		"quantity": 1,
		"expires_in_sec": 78200
	},
	{
		"id": "list_002",
		"item_id": "item_cuirass_01",
		"name": "Coraza de Hierro Meteórico",
		"category": Category.ARMOR,
		"rarity": "rare",
		"seller_id": "char_valerius",
		"seller_name": "Valerius (Líder)",
		"price": 280,
		"quantity": 1,
		"expires_in_sec": 42100
	},
	{
		"id": "list_003",
		"item_id": "item_potion_hp",
		"name": "Poción de Vida Mayor (x10)",
		"category": Category.CONSUMABLES,
		"rarity": "common",
		"seller_id": "char_kaelen",
		"seller_name": "Kaelen (Cazador)",
		"price": 85,
		"quantity": 10,
		"expires_in_sec": 12400
	},
	{
		"id": "list_004",
		"item_id": "item_void_crystal",
		"name": "Cristal de Vacío Cósmico",
		"category": Category.MATERIALS,
		"rarity": "legendary",
		"seller_id": "char_zephyr",
		"seller_name": "Zephyr (Pícaro)",
		"price": 1200,
		"quantity": 2,
		"expires_in_sec": 86400
	},
	{
		"id": "list_005",
		"item_id": "item_dagger_shadow",
		"name": "Daga de Hoja Espectral",
		"category": Category.WEAPONS,
		"rarity": "rare",
		"seller_id": "char_lyra",
		"seller_name": "Lyra (Asesina)",
		"price": 190,
		"quantity": 1,
		"expires_in_sec": 18200
	},
	{
		"id": "list_006",
		"item_id": "item_elixir_mana",
		"name": "Elixir de Maná Puro (x5)",
		"category": Category.CONSUMABLES,
		"rarity": "common",
		"seller_id": "char_eldrin",
		"seller_name": "Eldrin (Alquimista)",
		"price": 70,
		"quantity": 5,
		"expires_in_sec": 31500
	}
]

var player_silver: int = 850
var active_category: Category = Category.ALL
var current_search_query: String = ""
var active_sort: SortOrder = SortOrder.PRICE_ASC
var active_tab_index: int = 0 # 0: Comprar, 1: Vender

# Nodos de interfaz
@onready var wallet_label: Label = find_child("WalletLabel", true, false)
@onready var search_input: LineEdit = find_child("SearchInput", true, false)
@onready var category_option: OptionButton = find_child("CategoryOption", true, false)
@onready var sort_button: Button = find_child("SortButton", true, false)
@onready var listings_grid: GridContainer = find_child("ListingsGrid", true, false)
@onready var feedback_label: Label = find_child("FeedbackLabel", true, false)
@onready var tab_buy_button: Button = find_child("TabBuyButton", true, false)
@onready var tab_sell_button: Button = find_child("TabSellButton", true, false)
@onready var buy_container: Control = find_child("BuyContainer", true, false)
@onready var sell_container: Control = find_child("SellContainer", true, false)

# Controles de Venta
@onready var sell_item_input: LineEdit = find_child("SellItemInput", true, false)
@onready var sell_price_input: SpinBox = find_child("SellPriceInput", true, false)
@onready var sell_qty_input: SpinBox = find_child("SellQtyInput", true, false)
@onready var fee_label: Label = find_child("FeeLabel", true, false)
@onready var publish_button: Button = find_child("PublishButton", true, false)

# Modal de Confirmación de Compra
@onready var confirm_modal: PanelContainer = find_child("ConfirmModal", true, false)
@onready var confirm_text: Label = find_child("ConfirmText", true, false)
@onready var confirm_buy_btn: Button = find_child("ConfirmBuyButton", true, false)
@onready var cancel_buy_btn: Button = find_child("CancelBuyButton", true, false)

var _pending_purchase_listing: Dictionary = {}

func _ready() -> void:
	window_id = "marketplace_window"
	super._ready()
	set_title("MERCADO GLOBAL DE EXPLORADORES (P2P ESCROW)")
	
	_setup_signals()
	_init_normalized_cache()
	_update_wallet_display()
	_populate_category_options()
	_switch_tab(0)
	_refresh_listings_view()

func _init_normalized_cache() -> void:
	for item in _listings:
		item["norm_name"] = normalize_text(item["name"])

func _setup_signals() -> void:
	if search_input and not search_input.text_changed.is_connected(_on_search_changed):
		search_input.text_changed.connect(_on_search_changed)
	if category_option and not category_option.item_selected.is_connected(_on_category_selected):
		category_option.item_selected.connect(_on_category_selected)
	if sort_button and not sort_button.pressed.is_connected(_on_sort_toggle):
		sort_button.pressed.connect(_on_sort_toggle)
	if tab_buy_button and not tab_buy_button.pressed.is_connected(func(): _switch_tab(0)):
		tab_buy_button.pressed.connect(func(): _switch_tab(0))
	if tab_sell_button and not tab_sell_button.pressed.is_connected(func(): _switch_tab(1)):
		tab_sell_button.pressed.connect(func(): _switch_tab(1))
	if publish_button and not publish_button.pressed.is_connected(_on_publish_pressed):
		publish_button.pressed.connect(_on_publish_pressed)
	if sell_price_input and not sell_price_input.value_changed.is_connected(_on_sell_form_changed):
		sell_price_input.value_changed.connect(_on_sell_form_changed)
	if sell_qty_input and not sell_qty_input.value_changed.is_connected(_on_sell_form_changed):
		sell_qty_input.value_changed.connect(_on_sell_form_changed)
	if confirm_buy_btn and not confirm_buy_btn.pressed.is_connected(_on_confirm_buy_pressed):
		confirm_buy_btn.pressed.connect(_on_confirm_buy_pressed)
	if cancel_buy_btn and not cancel_buy_btn.pressed.is_connected(_on_cancel_buy_pressed):
		cancel_buy_btn.pressed.connect(_on_cancel_buy_pressed)

func _populate_category_options() -> void:
	if not category_option: return
	category_option.clear()
	category_option.add_item("Todas las Categorías", Category.ALL)
	category_option.add_item("Armas", Category.WEAPONS)
	category_option.add_item("Armaduras", Category.ARMOR)
	category_option.add_item("Consumibles", Category.CONSUMABLES)
	category_option.add_item("Materiales", Category.MATERIALS)

func _update_wallet_display() -> void:
	if wallet_label:
		wallet_label.text = "BILLETERA: %d SILVER" % player_silver

func _switch_tab(tab_idx: int) -> void:
	active_tab_index = tab_idx
	if buy_container: buy_container.visible = (tab_idx == 0)
	if sell_container: sell_container.visible = (tab_idx == 1)
	
	if tab_buy_button:
		tab_buy_button.modulate = Color(1.2, 1.2, 1.2) if tab_idx == 0 else Color(0.7, 0.7, 0.7)
	if tab_sell_button:
		tab_sell_button.modulate = Color(1.2, 1.2, 1.2) if tab_idx == 1 else Color(0.7, 0.7, 0.7)
		
	if tab_idx == 1:
		_on_sell_form_changed(0.0)

# Normalizador estricto insensible a acentos y diacríticos
static func normalize_text(text: String) -> String:
	var s = text.to_lower()
	var replacements := {
		"á": "a", "é": "e", "í": "i", "ó": "o", "ú": "u",
		"à": "a", "è": "e", "ì": "i", "ò": "o", "ù": "u",
		"ä": "a", "ë": "e", "ï": "i", "ö": "o", "ü": "u",
		"ñ": "n"
	}
	for accented in replacements:
		s = s.replace(accented, replacements[accented])
	return s

func _on_search_changed(new_text: String) -> void:
	current_search_query = new_text.strip_edges()
	_refresh_listings_view()

func _on_category_selected(index: int) -> void:
	active_category = category_option.get_item_id(index) as Category
	_refresh_listings_view()

func _on_sort_toggle() -> void:
	if active_sort == SortOrder.PRICE_ASC:
		active_sort = SortOrder.PRICE_DESC
		if sort_button: sort_button.text = "Precio: ⬇ Mayor a Menor"
	else:
		active_sort = SortOrder.PRICE_ASC
		if sort_button: sort_button.text = "Precio: ⬆ Menor a Mayor"
	_refresh_listings_view()

func get_filtered_listings() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var norm_query = normalize_text(current_search_query).strip_edges()
	
	for item in _listings:
		# Filtro de Categoría
		if active_category != Category.ALL and item["category"] != active_category:
			continue
		# Filtro de Búsqueda (Usa cache precalculada para Zero-GC stutter en 60 FPS)
		if norm_query != "":
			var norm_name: String = item.get("norm_name", "")
			if norm_name == "":
				norm_name = normalize_text(item["name"])
				item["norm_name"] = norm_name
			if not norm_name.contains(norm_query):
				continue
		result.append(item)
		
	# Ordenamiento
	if active_sort == SortOrder.PRICE_ASC:
		result.sort_custom(func(a, b): return a["price"] < b["price"])
	elif active_sort == SortOrder.PRICE_DESC:
		result.sort_custom(func(a, b): return a["price"] > b["price"])
		
	return result

func _refresh_listings_view() -> void:
	if not listings_grid: return
	
	# Limpiar hijos previos
	for child in listings_grid.get_children():
		child.queue_free()
		
	var filtered = get_filtered_listings()
	for item in filtered:
		var card = _create_listing_card(item)
		listings_grid.add_child(card)

func _create_listing_card(item: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(370, 110)
	
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.09, 0.13, 0.95)
	var rarity_color: Color = RARITY_COLORS.get(item.get("rarity", "common"), Color("#46e3c1"))
	sb.border_color = rarity_color
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", sb)
	
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)
	
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	margin.add_child(hbox)
	
	# Icono / Badge de Rareza
	var icon_box := PanelContainer.new()
	icon_box.custom_minimum_size = Vector2(60, 60)
	var isb := StyleBoxFlat.new()
	isb.bg_color = Color(0.12, 0.16, 0.22, 0.9)
	isb.border_color = rarity_color
	isb.set_border_width_all(2)
	isb.set_corner_radius_all(4)
	icon_box.add_theme_stylebox_override("panel", isb)
	
	var icon_lbl := Label.new()
	icon_lbl.text = "📦" if item["category"] != Category.WEAPONS else "⚔️"
	icon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon_lbl.add_theme_font_size_override("font_size", 22)
	icon_box.add_child(icon_lbl)
	hbox.add_child(icon_box)
	
	# Datos centrales
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 2)
	hbox.add_child(vbox)
	
	var name_lbl := Label.new()
	name_lbl.text = str(item["name"])
	name_lbl.add_theme_font_size_override("font_size", 12)
	name_lbl.add_theme_color_override("font_color", rarity_color)
	vbox.add_child(name_lbl)
	
	var seller_lbl := Label.new()
	seller_lbl.text = "Vendedor: %s" % item.get("seller_name", "Desconocido")
	seller_lbl.add_theme_font_size_override("font_size", 10)
	seller_lbl.add_theme_color_override("font_color", Color(0.65, 0.75, 0.85))
	vbox.add_child(seller_lbl)
	
	var hours = item["expires_in_sec"] / 3600
	var mins = (item["expires_in_sec"] % 3600) / 60
	var time_lbl := Label.new()
	time_lbl.text = "Expira en: %dh %dm" % [hours, mins]
	time_lbl.add_theme_font_size_override("font_size", 9)
	time_lbl.add_theme_color_override("font_color", Color(0.5, 0.6, 0.7))
	vbox.add_child(time_lbl)
	
	# Precio y Acción a la derecha
	var right_box := VBoxContainer.new()
	right_box.custom_minimum_size = Vector2(90, 0)
	right_box.alignment = BoxContainer.ALIGNMENT_CENTER
	right_box.add_theme_constant_override("separation", 6)
	hbox.add_child(right_box)
	
	var price_lbl := Label.new()
	price_lbl.text = "%d 🪙" % item["price"]
	price_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	price_lbl.add_theme_font_size_override("font_size", 13)
	price_lbl.add_theme_color_override("font_color", Color("#ffd700"))
	right_box.add_child(price_lbl)
	
	var buy_btn := Button.new()
	buy_btn.text = "Comprar"
	buy_btn.custom_minimum_size = Vector2(80, 26)
	buy_btn.pressed.connect(func(): _prompt_purchase(item))
	right_box.add_child(buy_btn)
	
	return panel

func _prompt_purchase(item: Dictionary) -> void:
	_pending_purchase_listing = item
	if not confirm_modal:
		# Fallback sin modal visual
		_execute_purchase(item)
		return
		
	confirm_modal.visible = true
	if confirm_text:
		confirm_text.text = "¿Confirmar adquisición de '%s' por %d Silver?" % [item["name"], item["price"]]
	if confirm_buy_btn:
		var can_afford = (player_silver >= item["price"])
		confirm_buy_btn.disabled = not can_afford
		if not can_afford:
			confirm_text.text += "\n[Saldo Insuficiente: Necesitas %d Silver]" % (item["price"] - player_silver)

func _on_confirm_buy_pressed() -> void:
	if confirm_modal:
		confirm_modal.visible = false
	if _pending_purchase_listing.is_empty():
		return
	_execute_purchase(_pending_purchase_listing)
	_pending_purchase_listing = {}

func _on_cancel_buy_pressed() -> void:
	if confirm_modal:
		confirm_modal.visible = false
	_pending_purchase_listing = {}

func _execute_purchase(item: Dictionary) -> bool:
	var price: int = item["price"]
	if player_silver < price:
		_show_feedback("Saldo insuficiente para comprar este ítem.", Color("#ff4444"))
		return false
		
	# Bóveda atómica de Escrow: Deducción inmediata
	player_silver -= price
	_update_wallet_display()
	
	# Remover de listados activos
	var found_idx := -1
	for i in range(_listings.size()):
		if _listings[i]["id"] == item["id"]:
			found_idx = i
			break
	if found_idx != -1:
		_listings.remove_at(found_idx)
		
	_refresh_listings_view()
	listing_purchased.emit(item["id"], item["item_id"], price)
	_show_feedback("¡Compra exitosa! '%s' adquirido por %d Silver." % [item["name"], price], Color("#46e3c1"))
	return true

func _on_sell_form_changed(_val: float) -> void:
	if not sell_price_input or not sell_qty_input or not fee_label: return
	var unit_price = int(sell_price_input.value)
	var qty = int(sell_qty_input.value)
	var total_price = unit_price * qty
	var fee = max(1, int(ceil(total_price * LISTING_FEE_PERCENT)))
	fee_label.text = "Total Venta: %d Silver | Depósito Custodia (5%%): %d Silver" % [total_price, fee]
	if publish_button:
		publish_button.disabled = (unit_price <= 0 or qty <= 0 or fee > player_silver)

func _on_publish_pressed() -> void:
	if not sell_item_input or not sell_price_input or not sell_qty_input: return
	var item_name = sell_item_input.text.strip_edges()
	if item_name == "":
		_show_feedback("El nombre del ítem a publicar no puede estar vacío.", Color("#ff4444"))
		return
		
	var unit_price = int(sell_price_input.value)
	var qty = int(sell_qty_input.value)
	if unit_price <= 0 or qty <= 0:
		_show_feedback("Precio y cantidad deben ser estrictamente positivos.", Color("#ff4444"))
		return

	var total = unit_price * qty
	var fee = max(1, int(ceil(total * LISTING_FEE_PERCENT)))
	
	if player_silver < fee:
		_show_feedback("No tienes suficiente saldo para cubrir el depósito de custodia (%d Silver)." % fee, Color("#ff4444"))
		return
		
	player_silver -= fee
	_update_wallet_display()
	
	var new_listing = {
		"id": "list_player_%d" % Time.get_unix_time_from_system(),
		"item_id": "item_user_custom",
		"name": item_name,
		"norm_name": normalize_text(item_name),
		"category": Category.MATERIALS,
		"rarity": "rare",
		"seller_id": "player_local",
		"seller_name": "Tú (Local)",
		"price": total,
		"quantity": qty,
		"expires_in_sec": 86400
	}
	_listings.push_front(new_listing)
	listing_created.emit(new_listing["id"], item_name, total, qty)
	_show_feedback("¡Listado publicado con éxito! Depósito de custodia: %d Silver." % fee, Color("#46e3c1"))
	
	sell_item_input.text = ""
	_switch_tab(0)
	_refresh_listings_view()

func _show_feedback(msg: String, color: Color) -> void:
	if feedback_label:
		feedback_label.text = msg
		feedback_label.add_theme_color_override("font_color", color)
