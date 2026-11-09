extends Control

# ShelterLobby.gd - Base de Operaciones y Hub de Gestión Estilo LoL (ADR 093 & ADR 099)
# Integra:
# 1. Navbar con pestañas [Campeones / Roster], [Estaciones & Farm], [Almacén], [Mercader], [Códice].
# 2. Sistema interactivo de Granja / Estaciones de Producción (Hierro, Madera, Piedra, Energía).
# 3. Selección y despliegue de campeones al Overworld.
# 4. Monedero y Perfil de Usuario persistente.

const CharacterCardScene = preload("res://ui/windows/ShelterWindow/CharacterCard.tscn")

@onready var roster_container = %RosterContainer
@onready var username_label = %UsernameLabel
@onready var account_type_label = %AccountTypeLabel
@onready var silver_badge = %SilverBadgeLabel
@onready var play_button = %PlayButton
@onready var stash_button = %StashButton
@onready var vendor_button = %VendorButton
@onready var codex_button = %CodexButton
@onready var selected_char_label = %SelectedCharLabel
@onready var roster_view = %RosterView
@onready var farm_view = %FarmView
@onready var roster_tab_btn = %RosterTabBtn
@onready var farm_tab_btn = %FarmTabBtn
@onready var stations_grid = %StationsGrid
@onready var harvest_all_btn = %HarvestAllBtn
@onready var energy_label = %EnergyLabel
@onready var notification_bar = %NotificationBar

var characters = []
var selected_character = null
var _is_loading = false
var player_silver = 500

# Estaciones de producción / Farm del Refugio
var farm_stations = [
	{
		"id": "station_iron_extractor",
		"name": "Extractor de Hierro Pesado",
		"type": "extractor",
		"produces": "Hierro",
		"item_def_name": "Hierro",
		"icon": "res://assets/icons/items/iron1x1.png",
		"rate": 60,
		"capacity": 100,
		"stored": 75,
		"energy_cost": 30,
		"level": 1
	},
	{
		"id": "station_wood_harvester",
		"name": "Recolector Forestal Automatizado",
		"type": "extractor",
		"produces": "Madera",
		"item_def_name": "Madera",
		"icon": "res://assets/icons/items/wood1x1.png",
		"rate": 90,
		"capacity": 150,
		"stored": 110,
		"energy_cost": 20,
		"level": 1
	},
	{
		"id": "station_stone_quarry",
		"name": "Cantera de Piedra Industrial",
		"type": "extractor",
		"produces": "Piedra",
		"item_def_name": "Piedra",
		"icon": "res://assets/icons/items/stone1x1.png",
		"rate": 40,
		"capacity": 200,
		"stored": 50,
		"energy_cost": 40,
		"level": 1
	},
	{
		"id": "station_power_matrix",
		"name": "Matriz Energética Solar & Eólica",
		"type": "generator",
		"produces": "Energía (+170 kW)",
		"item_def_name": "",
		"icon": "res://assets/icons/items/kit1x1.png",
		"rate": 170,
		"capacity": 0,
		"stored": 0,
		"energy_cost": 0,
		"level": 2
	}
]

func _ready():
	_setup_ui()
	_fetch_data()
	_setup_navbar()
	_populate_farm_stations()
	
	if not AuthManager.profile_fetched.is_connected(_setup_ui):
		AuthManager.profile_fetched.connect(_setup_ui)
	if not AuthManager.silver_updated.is_connected(_on_auth_silver_updated):
		AuthManager.silver_updated.connect(_on_auth_silver_updated)
		
	play_button.pressed.connect(_on_play_pressed)
	stash_button.pressed.connect(_on_stash_pressed)
	vendor_button.pressed.connect(_on_vendor_toggle)
	codex_button.pressed.connect(_on_codex_toggle)
	harvest_all_btn.pressed.connect(_on_harvest_all)
	var transfer_btn = get_node_or_null("%TransferSilverBtn")
	if transfer_btn:
		transfer_btn.pressed.connect(_open_transfer_silver_dialog)
	
	%ShowDebugBtn.pressed.connect(func(): %DebugPanel.visible = true)
	%CloseDebug.pressed.connect(func(): %DebugPanel.visible = false)
	
	# Tab switches
	roster_tab_btn.pressed.connect(func(): _switch_tab("roster"))
	farm_tab_btn.pressed.connect(func(): _switch_tab("farm"))
	_switch_tab("roster")
	
	# Asegurar fluidez máxima en el Refugio para que el modo Eco del 3D no ralentice la UI
	if Engine.max_fps > 0 and Engine.max_fps < 60:
		Engine.max_fps = 60

func _setup_navbar():
	_apply_button_theme(roster_tab_btn, Color(0.2, 0.45, 0.85))
	_apply_button_theme(farm_tab_btn, Color(0.85, 0.65, 0.15))
	_apply_button_theme(stash_button, Color(0.15, 0.35, 0.65))
	_apply_button_theme(vendor_button, Color(0.10, 0.50, 0.35))
	_apply_button_theme(codex_button, Color(0.65, 0.45, 0.10))
	_apply_button_theme(harvest_all_btn, Color(0.9, 0.7, 0.2))

func _switch_tab(tab_name: String):
	if tab_name == "roster":
		roster_view.visible = true
		farm_view.visible = false
		_highlight_tab(roster_tab_btn, true)
		_highlight_tab(farm_tab_btn, false)
	elif tab_name == "farm":
		roster_view.visible = false
		farm_view.visible = true
		_highlight_tab(roster_tab_btn, false)
		_highlight_tab(farm_tab_btn, true)
		_update_energy_display()

func _highlight_tab(btn: Button, active: bool):
	if active:
		btn.modulate = Color(1.2, 1.2, 1.2)
	else:
		btn.modulate = Color(0.8, 0.8, 0.8)

func _setup_ui():
	var u_name = AuthManager.username.to_upper() if AuthManager and AuthManager.username != "" else "AVENTURERO"
	username_label.text = u_name
	if AuthManager and AuthManager.is_premium:
		account_type_label.text = "Cuenta PREMIUM (5 Campeones)"
		account_type_label.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
	else:
		account_type_label.text = "Cuenta Básica (3 Campeones)"
	if AuthManager:
		player_silver = AuthManager.account_silver
		character_silver = AuthManager.character_silver
	silver_badge.text = "🪙 %d Silver" % player_silver

func _on_auth_silver_updated(acc: int, char_val: int):
	player_silver = acc
	character_silver = char_val
	if silver_badge:
		silver_badge.text = "🪙 %d Silver" % player_silver
	_update_transfer_modal_labels()

func _populate_farm_stations():
	if not stations_grid: return
	for child in stations_grid.get_children():
		child.queue_free()
		
	for station in farm_stations:
		var card = PanelContainer.new()
		card.custom_minimum_size = Vector2(230, 260)
		
		var sb = StyleBoxFlat.new()
		sb.bg_color = Color(0.07, 0.09, 0.13, 0.95)
		sb.border_width_left = 2
		sb.border_width_top = 2
		sb.border_width_right = 2
		sb.border_width_bottom = 2
		sb.border_color = Color(0.85, 0.7, 0.25) if station["type"] == "generator" else Color(0.25, 0.4, 0.6)
		sb.corner_radius_top_left = 8
		sb.corner_radius_top_right = 8
		sb.corner_radius_bottom_right = 8
		sb.corner_radius_bottom_left = 8
		card.add_theme_stylebox_override("panel", sb)
		
		var pad = MarginContainer.new()
		pad.add_theme_constant_override("margin_left", 12)
		pad.add_theme_constant_override("margin_top", 12)
		pad.add_theme_constant_override("margin_right", 12)
		pad.add_theme_constant_override("margin_bottom", 12)
		card.add_child(pad)
		
		var vbox = VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 10)
		pad.add_child(vbox)
		
		# Top row: icon + title
		var h_top = HBoxContainer.new()
		h_top.add_theme_constant_override("separation", 8)
		
		var icon_rect = TextureRect.new()
		icon_rect.custom_minimum_size = Vector2(36, 36)
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		if ResourceLoader.exists(station["icon"]):
			icon_rect.texture = load(station["icon"])
		h_top.add_child(icon_rect)
		
		var title_vbox = VBoxContainer.new()
		var name_lbl = Label.new()
		name_lbl.text = station["name"]
		name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_lbl.add_theme_font_size_override("font_size", 11)
		title_vbox.add_child(name_lbl)
		
		var tier_lbl = Label.new()
		tier_lbl.text = "Módulo Nivel %d" % station["level"]
		tier_lbl.add_theme_font_size_override("font_size", 9)
		tier_lbl.add_theme_color_override("font_color", Color(0.5, 0.7, 0.9))
		title_vbox.add_child(tier_lbl)
		h_top.add_child(title_vbox)
		vbox.add_child(h_top)
		
		# Stats
		var stats_lbl = Label.new()
		if station["type"] == "generator":
			stats_lbl.text = "Generación Continua:\n+170 kW hacia la red local"
			stats_lbl.add_theme_color_override("font_color", Color(0.4, 0.9, 0.6))
		else:
			stats_lbl.text = "Producción: %d/h\nConsumo: -%d kW" % [station["rate"], station["energy_cost"]]
			stats_lbl.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
		stats_lbl.add_theme_font_size_override("font_size", 10)
		vbox.add_child(stats_lbl)
		
		# Bar and action
		if station["type"] != "generator":
			var pbar = ProgressBar.new()
			pbar.custom_minimum_size = Vector2(0, 14)
			pbar.max_value = station["capacity"]
			pbar.value = station["stored"]
			pbar.show_percentage = false
			vbox.add_child(pbar)
			
			var cap_lbl = Label.new()
			cap_lbl.text = "Almacenado: %d / %d" % [station["stored"], station["capacity"]]
			cap_lbl.add_theme_font_size_override("font_size", 9)
			cap_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			vbox.add_child(cap_lbl)
			
			var col_btn = Button.new()
			col_btn.text = "⛏️ Recolectar (%d)" % station["stored"]
			col_btn.custom_minimum_size = Vector2(0, 32)
			col_btn.add_theme_font_size_override("font_size", 10)
			_apply_button_theme(col_btn, Color(0.2, 0.6, 0.45))
			col_btn.disabled = (station["stored"] <= 0)
			col_btn.pressed.connect(_on_collect_station.bind(station))
			vbox.add_child(col_btn)
		else:
			var active_lbl = Label.new()
			active_lbl.text = "⚡ OPERANDO AL 100%\nSuministrando energía limpia a todos los extractores del refugio."
			active_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			active_lbl.add_theme_font_size_override("font_size", 10)
			active_lbl.add_theme_color_override("font_color", Color(0.3, 0.95, 0.6))
			vbox.add_child(active_lbl)
			
		stations_grid.add_child(card)

func _update_energy_display():
	var total_gen = 170
	var total_cons = 30 + 20 + 40 # 90 kW
	var balance = total_gen - total_cons
	energy_label.text = "⚡ RED ELÉCTRICA: Generación: +%d kW | Consumo: -%d kW | Superávit: +%d kW [ESTABLE]" % [total_gen, total_cons, balance]

func _on_collect_station(station: Dictionary):
	var amount = station["stored"]
	if amount <= 0: return
	
	var res = await _deposit_farm_item_in_stash(station["item_def_name"], amount, false)
	var deposited = res.get("total_deposited", 0)
	var surplus = res.get("lost_qty", 0)
	
	station["stored"] = surplus # El remanente permanece guardado en la estación
	_populate_farm_stations()
	
	if surplus > 0:
		var warn_msg = "¡Almacén lleno! Se depositaron %d unidades y el sobrante (%d) permanece guardado en la estación." % [deposited, surplus]
		_notify(warn_msg)
		if has_node("/root/UIOrchestrator"):
			var orch = get_node("/root/UIOrchestrator")
			if orch.has_method("show_toast"):
				orch.show_toast("⚠️ ALMACÉN LLENO", warn_msg, Color(1.0, 0.6, 0.2))
		return
		
	var max_st = res.get("max_stack", 1)
	var msg = ""
	if res.get("stacked_qty", 0) > 0 and res.get("new_slot_qty", 0) == 0:
		msg = "🌾 Cosecha: +%d %s (Apilado en slot existente de tu Almacén, máx x%d)." % [deposited, station["produces"], max_st]
	elif res.get("new_slot_qty", 0) > 0 and res.get("stacked_qty", 0) == 0:
		msg = "🌾 Cosecha: +%d %s (Nuevo slot x%d/%d en tu Almacén)." % [deposited, station["produces"], res["new_slot_qty"], max_st]
	else:
		msg = "🌾 Cosecha: +%d %s (%d apilados en slot existente + %d en nuevo slot, máx x%d)." % [deposited, station["produces"], res["stacked_qty"], res["new_slot_qty"], max_st]
	
	_notify(msg)
	if has_node("/root/UIOrchestrator"):
		var orch = get_node("/root/UIOrchestrator")
		if orch.has_method("show_toast"):
			orch.show_toast(
				"🌾 COSECHA COMPLETADA",
				msg.replace("🌾 Cosecha: ", ""),
				Color(0.3, 0.95, 0.5)
			)
	print("[ShelterLobby] Recolectados %d de %s." % [amount, station["produces"]])

func _on_harvest_all():
	if harvest_all_btn:
		harvest_all_btn.disabled = true
	var total_collected = 0
	var total_stacked = 0
	var total_new = 0
	var total_surplus = 0
	for station in farm_stations:
		if station["type"] != "generator" and station["stored"] > 0:
			var amt = station["stored"]
			var res = await _deposit_farm_item_in_stash(station["item_def_name"], amt, true)
			var dep = res.get("total_deposited", 0)
			var surplus = res.get("lost_qty", 0)
			station["stored"] = surplus # El remanente permanece guardado en la estación
			total_collected += dep
			total_stacked += res.get("stacked_qty", 0)
			total_new += res.get("new_slot_qty", 0)
			total_surplus += surplus
			
	_populate_farm_stations()
	
	# Refrescar ventanas de inventario una sola vez con todos los ítems ya consolidados
	var inv_uis = get_tree().get_nodes_in_group("inventory_ui")
	for inv in inv_uis:
		if inv.has_method("_request_data_refresh"):
			await inv._request_data_refresh()
			
	if harvest_all_btn:
		harvest_all_btn.disabled = false
		
	if total_surplus > 0:
		var warn_msg = "¡Almacén lleno! Se depositaron %d unidades y el sobrante (%d) permanece guardado en la estación." % [total_collected, total_surplus]
		_notify(warn_msg)
		if has_node("/root/UIOrchestrator"):
			var orch = get_node("/root/UIOrchestrator")
			if orch.has_method("show_toast"):
				orch.show_toast("⚠️ ALMACÉN LLENO", warn_msg, Color(1.0, 0.6, 0.2))
	elif total_collected > 0:
		var summary_msg = "🌾 ¡Cosecha Total! Se transfirieron %d materias primas (%d apiladas en slots existentes, %d en nuevos slots)." % [total_collected, total_stacked, total_new]
		_notify(summary_msg)
		if has_node("/root/UIOrchestrator"):
			var orch = get_node("/root/UIOrchestrator")
			if orch.has_method("show_toast"):
				orch.show_toast(
					"🌾 COSECHA TOTAL DEL REFUGIO",
					"%d materias primas recolectadas (%d apiladas, %d en nuevos slots)." % [total_collected, total_stacked, total_new],
					Color(0.3, 0.95, 0.5)
				)
	else:
		_notify("ℹ️ No hay recursos pendientes por cosechar en este momento.")

func _deposit_farm_item_in_stash(item_name: String, quantity: int, skip_refresh: bool = false) -> Dictionary:
	var user_id = AuthManager.user_id if AuthManager and AuthManager.user_id != "" else "local_user"
	var max_stack = ShelterManager.get_item_max_stack(item_name)
	var remaining = quantity
	var stacked_qty = 0
	var new_slot_qty = 0
	var sync_batch: Array = []
	
	var icon_p = "res://assets/icons/items/" + item_name.to_lower() + "1x1.png"
	var def_id = "d6871f24-5b7d-4d73-8b70-eb85ccdad6b7"
	if item_name == "Hierro": 
		icon_p = "res://assets/icons/items/iron1x1.png"
		def_id = "d6871f24-5b7d-4d73-8b70-eb85ccdad6b7"
	elif item_name == "Madera": 
		icon_p = "res://assets/icons/items/wood1x1.png"
		def_id = "e4d262bf-ad4d-4bc0-91d4-c6290db2e43c"
	elif item_name == "Piedra": 
		icon_p = "res://assets/icons/items/stone1x1.png"
		def_id = "3cae4f06-ae42-41db-a92e-beed4db961b3"
	
	# 1. Intentar apilar en stacks existentes en el Almacén que tengan cupo disponible
	for it in ShelterManager.shelter_inventory:
		if remaining <= 0: break
		var it_name = it.get("display_name", "")
		var it_def_id = it.get("item_definition_id", "")
		if it_name == item_name or it_def_id == def_id:
			var cur_q = int(it.get("quantity", 1))
			var space = max_stack - cur_q
			if space > 0:
				var to_add = min(space, remaining)
				it["quantity"] = cur_q + to_add
				remaining -= to_add
				stacked_qty += to_add
				ShelterManager.all_items_cache[str(it.get("id"))] = it
				sync_batch.append({
					"user_id": user_id,
					"def_id": it["item_definition_id"],
					"quantity": to_add,
					"x": int(it["slot_x"]),
					"y": int(it["slot_y"])
				})

	# 2. Si todavía queda remanente, ubicar en nuevos slots libres respetando el límite max_stack
	while remaining > 0:
		var free_slot = _find_free_stash_slot(1, 1)
		if free_slot == Vector2i(-1, -1):
			break
			
		var stack_qty = min(remaining, max_stack)
		remaining -= stack_qty
		new_slot_qty += stack_qty
		var item_id = "farm_" + item_name.to_lower() + "_" + str(Time.get_ticks_msec()) + "_" + str(randi() % 1000)
		
		var item_dict = {
			"id": item_id,
			"user_id": user_id,
			"character_id": "",
			"item_definition_id": def_id,
			"display_name": item_name,
			"icon_path": icon_p,
			"rarity": "common",
			"item_type": "material",
			"grid_width": 1,
			"grid_height": 1,
			"slot_x": free_slot.x,
			"slot_y": free_slot.y,
			"is_rotated": false,
			"is_secure": false,
			"quantity": stack_qty
		}
		
		ShelterManager.shelter_inventory.append(item_dict)
		ShelterManager.all_items_cache[item_id] = item_dict
		sync_batch.append({
			"user_id": user_id,
			"def_id": item_dict["item_definition_id"],
			"quantity": stack_qty,
			"x": free_slot.x,
			"y": free_slot.y
		})

	# Sincronización asíncrona sin bloquear el hilo principal de la UI
	if not sync_batch.is_empty():
		_async_sync_harvest_batch(sync_batch)
	
	if not skip_refresh:
		var inv_uis = get_tree().get_nodes_in_group("inventory_ui")
		for inv in inv_uis:
			if inv.has_method("_request_data_refresh"):
				await inv._request_data_refresh()
				
	return {
		"item_name": item_name,
		"total_deposited": quantity - remaining,
		"stacked_qty": stacked_qty,
		"new_slot_qty": new_slot_qty,
		"max_stack": max_stack,
		"lost_qty": remaining
	}

func _async_sync_harvest_batch(batch: Array) -> void:
	for task in batch:
		ShelterManager.admin_add_item(task["user_id"], "", task["def_id"], task["quantity"], task["x"], task["y"], false)

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

func _notify(msg: String):
	if notification_bar:
		notification_bar.text = "  🔔 " + msg
		var tw = create_tween()
		tw.tween_property(notification_bar, "modulate", Color(1.4, 1.3, 0.4, 1.0), 0.15)
		tw.tween_property(notification_bar, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.45)
	print("[ShelterLobby] " + msg)

func _fetch_data():
	if _is_loading: return
	_set_loading(true)
	
	await get_tree().create_timer(0.3).timeout
	var res = await APIClient.list_characters()
	_set_loading(false)
	
	if res.has("data"):
		var data = res["data"]
		if data is Dictionary:
			characters = data.get("characters", [])
		elif data is Array:
			characters = data
		else:
			characters = []
		_populate_roster()

func _populate_roster():
	for child in roster_container.get_children():
		child.queue_free()
	
	for char_data in characters:
		var card = CharacterCardScene.instantiate()
		roster_container.add_child(card)
		card.setup(char_data)
		card.selected.connect(_on_character_selected)
		card.revive_requested.connect(_on_character_revive)
		card.delete_requested.connect(_on_character_delete)
	
	var limit = 5 if (AuthManager and AuthManager.is_premium) else 3
	if characters.size() < limit:
		_add_create_button()

func _add_create_button():
	var btn = Button.new()
	btn.text = "+\nCREAR\nNUEVO"
	btn.custom_minimum_size = Vector2(180, 240)
	btn.pressed.connect(_on_create_new_pressed)
	roster_container.add_child(btn)

func _on_character_selected(char_data: Dictionary):
	if selected_character and selected_character["id"] == char_data["id"]:
		selected_character = null
		selected_char_label.text = "Ningún campeón seleccionado"
		play_button.disabled = true
		play_button.modulate = Color(0.5, 0.5, 0.5)
		for card in roster_container.get_children():
			if card.has_method("set_highlight"):
				card.set_highlight(false)
		return

	selected_character = char_data
	selected_char_label.text = "Seleccionado: " + char_data["name"] + " (ID: " + char_data["id"] + ")"
	
	var status = char_data.get("status", "")
	var is_dead = status in ["Dead", "Muerto"]
	var is_on_expedition = status in ["OnExpedition", "Expedición"]
	
	if is_on_expedition:
		play_button.disabled = true
		play_button.modulate = Color(0.8, 0.6, 0.2)
		play_button.text = "⏳ EN EXPEDICIÓN OFFLINE"
	elif is_dead:
		play_button.disabled = true
		play_button.modulate = Color(0.5, 0.5, 0.5)
		play_button.text = "💀 CAMPEÓN CAÍDO (REVIVIR)"
	else:
		play_button.disabled = false
		play_button.modulate = Color(1, 1, 1)
		play_button.text = "🚪 SALIR AL ASILO DE AVENTUREROS (OVERWORLD)"
	
	for card in roster_container.get_children():
		if card.has_method("set_highlight"):
			card.set_highlight(card.character_data["id"] == char_data["id"])

func _on_character_revive(char_data: Dictionary):
	var res = await APIClient.revive_character(char_data["id"])
	if res.get("code") == 200:
		_notify("¡" + char_data["name"] + " ha vuelto a la vida!")
		_fetch_data()

func _on_character_delete(char_data: Dictionary):
	var dialog = ConfirmationDialog.new()
	dialog.title = "ELIMINAR CAMPEÓN"
	dialog.dialog_text = "¿Eliminar a " + char_data["name"] + "? Acción permanente."
	add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(func():
		var res = await APIClient.delete_character(char_data["id"])
		var code = res.get("code", 0)
		if code == 200 or code == 201:
			_fetch_data()
		dialog.queue_free()
	)
	dialog.canceled.connect(func(): dialog.queue_free())

func _on_play_pressed():
	if not selected_character: return
	AuthManager.selected_character_id = selected_character["id"]
	AuthManager.selected_character_name = selected_character["name"]
	ShelterManager.transition_to_world()

func _on_stash_pressed():
	var cid = selected_character["id"] if selected_character else ""
	var is_dead = selected_character.get("status", "") in ["Dead", "Muerto"] if selected_character else false
	UIOrchestrator.toggle_window("inventory", {
		"character_id": cid,
		"is_shelter_context": true,
		"is_dead": is_dead
	})

func _on_vendor_toggle():
	if UIOrchestrator:
		UIOrchestrator.toggle_window("vendor_window")

func _on_codex_toggle():
	if UIOrchestrator:
		UIOrchestrator.toggle_window("codex_window")

func _on_create_new_pressed():
	var dialog = ConfirmationDialog.new()
	dialog.title = "NUEVO CAMPEÓN"
	var vbox = VBoxContainer.new()
	var label = Label.new()
	label.text = "Nombre del nuevo personaje:"
	vbox.add_child(label)
	var input = LineEdit.new()
	input.placeholder_text = "Nombre"
	vbox.add_child(input)
	dialog.add_child(vbox)
	add_child(dialog)
	dialog.popup_centered(Vector2i(300, 150))
	
	dialog.confirmed.connect(func():
		var final_name = input.text.strip_edges()
		if final_name != "":
			var res = await APIClient.create_character(final_name)
			var code = res.get("code", 0)
			if code == 200 or code == 201:
				_fetch_data()
		dialog.queue_free()
	)
	dialog.canceled.connect(func(): dialog.queue_free())

func _set_loading(active: bool):
	_is_loading = active
	play_button.disabled = active or selected_character == null
	stash_button.disabled = active

func _apply_button_theme(btn: Button, accent_color: Color) -> void:
	var sb = StyleBoxFlat.new()
	sb.bg_color = accent_color * 0.45
	sb.bg_color.a = 0.9
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = accent_color
	sb.corner_radius_top_left = 6
	sb.corner_radius_top_right = 6
	sb.corner_radius_bottom_right = 6
	sb.corner_radius_bottom_left = 6
	btn.add_theme_stylebox_override("normal", sb)
	
	var sb_hover = sb.duplicate()
	sb_hover.bg_color = accent_color * 0.7
	sb_hover.border_color = accent_color.lightened(0.2)
	btn.add_theme_stylebox_override("hover", sb_hover)

var character_silver: int = 0
var transfer_modal: Control = null

func _open_transfer_silver_dialog():
	if transfer_modal and is_instance_valid(transfer_modal):
		transfer_modal.visible = true
		_update_transfer_modal_labels()
		return
	
	transfer_modal = PanelContainer.new()
	transfer_modal.name = "TransferSilverModal"
	transfer_modal.custom_minimum_size = Vector2(360, 240)
	transfer_modal.set_anchors_preset(Control.PRESET_CENTER)
	transfer_modal.offset_left = -180
	transfer_modal.offset_top = -120
	transfer_modal.offset_right = 180
	transfer_modal.offset_bottom = 120
	
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.08, 0.12, 0.98)
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.border_color = Color(0.85, 0.72, 0.35, 0.95)
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_right = 8
	sb.corner_radius_bottom_left = 8
	sb.shadow_size = 18
	sb.shadow_color = Color(0, 0, 0, 0.85)
	transfer_modal.add_theme_stylebox_override("panel", sb)
	
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 12)
	transfer_modal.add_child(margin)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)
	
	var title = Label.new()
	title.text = "🏛️ ADMINISTRADOR DE MONEDAS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	vbox.add_child(title)
	
	var sep = HSeparator.new()
	vbox.add_child(sep)
	
	var stash_lbl = Label.new()
	stash_lbl.name = "StashBalanceLbl"
	stash_lbl.text = "🪙 Alijo de Cuenta (Refugio): %d Silver" % player_silver
	stash_lbl.add_theme_font_size_override("font_size", 11)
	vbox.add_child(stash_lbl)
	
	var char_name = selected_character.get("name", "Campeón") if selected_character else "Campeón Activo"
	var char_lbl = Label.new()
	char_lbl.name = "CharBalanceLbl"
	char_lbl.text = "🎒 Billetera de %s: %d Silver" % [char_name, character_silver]
	char_lbl.add_theme_font_size_override("font_size", 11)
	vbox.add_child(char_lbl)
	
	var grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 6)
	vbox.add_child(grid)
	
	var btn_to_char = Button.new()
	btn_to_char.text = "⬇ Dar 100 al Personaje"
	btn_to_char.pressed.connect(func(): _transfer_silver(100, true))
	grid.add_child(btn_to_char)
	
	var btn_to_stash = Button.new()
	btn_to_stash.text = "⬆ Depositar 100 al Alijo"
	btn_to_stash.pressed.connect(func(): _transfer_silver(100, false))
	grid.add_child(btn_to_stash)
	
	var btn_all_char = Button.new()
	btn_all_char.text = "⬇ Todo al Personaje"
	btn_all_char.pressed.connect(func(): _transfer_silver(player_silver, true))
	grid.add_child(btn_all_char)
	
	var btn_all_stash = Button.new()
	btn_all_stash.text = "⬆ Todo al Alijo"
	btn_all_stash.pressed.connect(func(): _transfer_silver(character_silver, false))
	grid.add_child(btn_all_stash)
	
	var close_btn = Button.new()
	close_btn.text = "✕ Cerrar"
	close_btn.pressed.connect(func(): transfer_modal.visible = false)
	vbox.add_child(close_btn)
	
	add_child(transfer_modal)

func _transfer_silver(amount: int, to_character: bool):
	if amount <= 0: return
	var moved = 0
	if AuthManager:
		moved = AuthManager.transfer_silver(amount, to_character)
		player_silver = AuthManager.account_silver
		character_silver = AuthManager.character_silver
	else:
		if to_character:
			moved = mini(amount, player_silver)
			player_silver -= moved
			character_silver += moved
		else:
			moved = mini(amount, character_silver)
			character_silver -= moved
			player_silver += moved
	
	if to_character:
		_notify("Transferidos %d de Silver a la billetera del campeón." % moved)
	else:
		_notify("Depositados %d de Silver al alijo de cuenta del refugio." % moved)
	if silver_badge:
		silver_badge.text = "🪙 %d Silver" % player_silver
	_update_transfer_modal_labels()

func _update_transfer_modal_labels():
	if not transfer_modal or not is_instance_valid(transfer_modal): return
	var s_lbl = transfer_modal.find_child("StashBalanceLbl", true, false)
	if s_lbl: s_lbl.text = "🪙 Alijo de Cuenta (Refugio): %d Silver" % player_silver
	var c_lbl = transfer_modal.find_child("CharBalanceLbl", true, false)
	var char_name = selected_character.get("name", "Campeón") if selected_character else "Campeón Activo"
	if c_lbl: c_lbl.text = "🎒 Billetera de %s: %d Silver" % [char_name, character_silver]
