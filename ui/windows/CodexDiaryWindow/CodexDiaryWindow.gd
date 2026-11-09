extends BaseWindow

# CodexDiaryWindow.gd - Bitácora & Grimorio de Conocimiento In-Game (ADR 082)
# Diseño Master-Detail tipo RPG (Witcher/Hades): Lista filtrable a la izquierda y tomo detallado a la derecha.
# Resuelve:
# 1. Spawning de ítem físico "Hoja de Descubrimiento" en el Almacén.
# 2. Publicación autoritativa a nombre del Personaje seleccionado o Cuenta si no hay selección.
# 3. Soporte de consumo de hoja con desbloqueo y adjunción al libro.

@onready var diary_container = %DiaryEntriesContainer
@onready var detail_container = %DetailContainer
@onready var status_label = %CodexStatusLabel
@onready var stats_summary = %StatsSummaryLabel
@onready var search_input = %SearchInput
@onready var tabs_container = %HBoxTabs

var current_category: String = "TODOS"
var current_search: String = ""
var selected_entry_id: String = "item_amuleto_vacio"

var discoveries: Array[Dictionary] = [
	{
		"id": "npc_guardia_carmesi",
		"name": "Guardia Carmesí de la Cripta",
		"type": "CRIATURAS",
		"is_public": true,
		"is_acquired": true,
		"pioneer": "Aventurero_Alpha",
		"desc": "Humanoide corrupto que resguarda las catacumbas ancestrales. Lanza proyectiles ígneos a 12m y ejecuta barridos defensivos. Es vulnerable a daño de corte y disparos hitscan rápidos."
	},
	{
		"id": "item_daga_larga",
		"name": "Daga Larga Ancestral",
		"type": "ITEMS",
		"is_public": true,
		"is_acquired": true,
		"pioneer": "Explorador01",
		"desc": "Arma ágil 1x2 forjada en aleación arcana. Posee una cadencia de ataque relámpago con un +15% de probabilidad de evasión en combates cuerpo a cuerpo prolongados."
	},
	{
		"id": "item_amuleto_vacio",
		"name": "Amuleto Vacío Ancestral",
		"type": "ITEMS",
		"is_public": false,
		"is_acquired": false,
		"pioneer": null,
		"desc": "[CONOCIMIENTO OCULTO]: Receptáculo milenario tallado en obsidiana con engastes arcanos inertes. Mientras permanezca en secreto en tu bitácora, otorga un +5% de amplificación mágica elemental pasiva a todas tus habilidades."
	},
	{
		"id": "mecanica_singularidad_portal",
		"name": "Horizonte de Singularidad Cósmica",
		"type": "MECÁNICAS",
		"is_public": false,
		"is_acquired": false,
		"pioneer": null,
		"desc": "[CONOCIMIENTO OCULTO]: Canalizado de teletransporte y extracción de 10 segundos interrumpible por daño de combate. Otorga +5% de mitigación de daño físico dentro de un radio de 8 metros del portal."
	}
]

func is_secret_acquired(secret_id: String) -> bool:
	for entry in discoveries:
		if entry["id"] == secret_id or entry["name"] == secret_id or ("Hoja de Descubrimiento: " + entry["name"]) == secret_id:
			return entry.get("is_acquired", false) or entry.get("is_public", false)
	return false

func _ready() -> void:
	window_id = "codex_window"
	super._ready()
	add_to_group("codex_window")
	set_title("📜 CÓDICE DINÁMICO & GRIMORIO DE DESCUBRIMIENTOS (J)")
	center_on_screen()
	
	_setup_category_tabs()
	if search_input:
		search_input.text_changed.connect(_on_search_changed)
	
	_populate_list()
	_show_detail(selected_entry_id)

func _setup_category_tabs() -> void:
	if not tabs_container: return
	for child in tabs_container.get_children():
		child.queue_free()
		
	var categories = ["TODOS", "ITEMS", "CRIATURAS", "MECÁNICAS", "SECRETOS"]
	for cat in categories:
		var btn = Button.new()
		btn.text = cat
		btn.custom_minimum_size = Vector2(90, 28)
		btn.add_theme_font_size_override("font_size", 10)
		_style_tab_button(btn, cat == current_category)
		btn.pressed.connect(func():
			current_category = cat
			_setup_category_tabs()
			_populate_list()
		)
		tabs_container.add_child(btn)

func _style_tab_button(btn: Button, is_active: bool) -> void:
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.22, 0.35, 0.95) if is_active else Color(0.06, 0.08, 0.12, 0.8)
	sb.border_width_bottom = 2 if is_active else 0
	sb.border_color = Color(0.3, 0.8, 1.0)
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	btn.add_theme_stylebox_override("normal", sb)

func _on_search_changed(new_text: String) -> void:
	current_search = new_text.strip_edges().to_lower()
	_populate_list()

func _populate_list() -> void:
	if not diary_container: return
	for child in diary_container.get_children():
		child.queue_free()
		
	var public_count = 0
	var secret_count = 0
	
	for entry in discoveries:
		if entry["is_public"]:
			public_count += 1
		else:
			secret_count += 1
			
		# Filtro de categoría
		if current_category == "SECRETOS" and entry["is_public"]:
			continue
		elif current_category != "TODOS" and current_category != "SECRETOS" and entry.get("type", "").to_upper() != current_category:
			continue
			
		# Filtro de búsqueda
		if current_search != "":
			var matches_name = entry["name"].to_lower().contains(current_search)
			var matches_desc = entry["desc"].to_lower().contains(current_search)
			if not (matches_name or matches_desc):
				continue
				
		var is_acquired = entry.get("is_acquired", false) or entry.get("is_public", false)
		var prefix = "✓ " if entry["is_public"] else ("🔒 " if is_acquired else "❓ ")
		var status_text = ""
		if not entry["is_public"]:
			status_text = " [Aprendido]" if is_acquired else " [No adquirido]"
		var item_btn = Button.new()
		item_btn.text = prefix + entry["name"] + status_text
		item_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		item_btn.custom_minimum_size = Vector2(0, 36)
		item_btn.add_theme_font_size_override("font_size", 11)
		
		var is_selected = (entry["id"] == selected_entry_id)
		var sb = StyleBoxFlat.new()
		sb.bg_color = Color(0.14, 0.20, 0.30, 0.95) if is_selected else Color(0.07, 0.09, 0.14, 0.85)
		sb.border_width_left = 3
		sb.border_color = Color(0.2, 0.8, 1.0) if entry["is_public"] else Color(1.0, 0.75, 0.2)
		sb.corner_radius_top_left = 4
		sb.corner_radius_bottom_left = 4
		sb.corner_radius_top_right = 4
		sb.corner_radius_bottom_right = 4
		item_btn.add_theme_stylebox_override("normal", sb)
		
		var entry_id = entry["id"]
		item_btn.pressed.connect(func():
			selected_entry_id = entry_id
			_populate_list()
			_show_detail(entry_id)
		)
		diary_container.add_child(item_btn)
		
	if stats_summary:
		stats_summary.text = "Públicas: %d | Secretos Tácticos: %d" % [public_count, secret_count]

func _get_entry(entry_id: String) -> Dictionary:
	for e in discoveries:
		if e["id"] == entry_id:
			return e
	return {}

func _show_detail(entry_id: String) -> void:
	if not detail_container: return
	for child in detail_container.get_children():
		child.queue_free()
		
	var entry = _get_entry(entry_id)
	if entry.is_empty():
		var empty_lbl = Label.new()
		empty_lbl.text = "Selecciona una entrada del índice para visualizar sus secretos y notas de campo."
		empty_lbl.add_theme_color_override("font_color", Color(0.6, 0.7, 0.8))
		detail_container.add_child(empty_lbl)
		return
		
	# Card contenedor del Tomo
	var tome_panel = PanelContainer.new()
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.10, 0.16, 0.95)
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.border_color = Color(0.2, 0.65, 0.95, 0.75) if entry["is_public"] else Color(0.95, 0.7, 0.2, 0.85)
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_right = 8
	sb.corner_radius_bottom_left = 8
	tome_panel.add_theme_stylebox_override("panel", sb)
	
	var pad = MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 16)
	pad.add_theme_constant_override("margin_top", 14)
	pad.add_theme_constant_override("margin_right", 16)
	pad.add_theme_constant_override("margin_bottom", 14)
	tome_panel.add_child(pad)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	pad.add_child(vbox)
	
	# Cabecera: Título + Badge de Categoría
	var h_top = HBoxContainer.new()
	h_top.add_theme_constant_override("separation", 10)
	
	var cat_badge = Label.new()
	cat_badge.text = "[ %s ]" % entry.get("type", "GENERAL")
	cat_badge.add_theme_font_size_override("font_size", 11)
	cat_badge.add_theme_color_override("font_color", Color(0.35, 0.75, 1.0))
	h_top.add_child(cat_badge)
	
	var name_lbl = Label.new()
	name_lbl.text = entry["name"]
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 16)
	name_lbl.add_theme_color_override("font_color", Color.WHITE)
	h_top.add_child(name_lbl)
	vbox.add_child(h_top)
	
	# Banner de Estatus (Público vs Secreto)
	var banner = PanelContainer.new()
	var bsb = StyleBoxFlat.new()
	bsb.corner_radius_top_left = 4
	bsb.corner_radius_top_right = 4
	bsb.corner_radius_bottom_right = 4
	bsb.corner_radius_bottom_left = 4
	if entry["is_public"]:
		bsb.bg_color = Color(0.05, 0.22, 0.15, 0.9)
		bsb.border_color = Color(0.2, 0.85, 0.45)
		bsb.border_width_left = 2
	else:
		bsb.bg_color = Color(0.24, 0.16, 0.04, 0.9)
		bsb.border_color = Color(1.0, 0.75, 0.2)
		bsb.border_width_left = 2
	banner.add_theme_stylebox_override("panel", bsb)
	
	var b_margin = MarginContainer.new()
	b_margin.add_theme_constant_override("margin_left", 10)
	b_margin.add_theme_constant_override("margin_top", 6)
	b_margin.add_theme_constant_override("margin_right", 10)
	b_margin.add_theme_constant_override("margin_bottom", 6)
	banner.add_child(b_margin)
	
	var is_acquired = entry.get("is_acquired", false) or entry.get("is_public", false)
	var banner_lbl = Label.new()
	if entry["is_public"]:
		banner_lbl.text = "🏛️ DOMINIO PÚBLICO | Primer Descubridor Registrado: " + str(entry.get("pioneer", "Manual Oficial de Campo"))
		banner_lbl.add_theme_color_override("font_color", Color(0.4, 0.95, 0.6))
	elif is_acquired:
		banner_lbl.text = "🔒 CONOCIMIENTO OCULTO APRENDIDO | +5% Buff Táctico Activo en Personajes"
		banner_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	else:
		banner_lbl.text = "❓ CONOCIMIENTO OCULTO (NO ADQUIRIDO) | Clic derecho en una Hoja de Descubrimiento para asimilar"
		banner_lbl.add_theme_color_override("font_color", Color(0.75, 0.8, 0.9))
	banner_lbl.add_theme_font_size_override("font_size", 11)
	b_margin.add_child(banner_lbl)
	vbox.add_child(banner)
	
	# Descripción del lore y mecánicas
	var desc_lbl = Label.new()
	desc_lbl.text = entry["desc"]
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.add_theme_font_size_override("font_size", 12)
	desc_lbl.add_theme_color_override("font_color", Color(0.85, 0.88, 0.94))
	vbox.add_child(desc_lbl)
	
	# Footer de Acciones (El Dilema del Pionero)
	if not entry["is_public"]:
		var divider = HSeparator.new()
		vbox.add_child(divider)
		
		# Autor determinado para publicación
		var resolved_author = _get_resolved_author()
		var author_note = Label.new()
		author_note.text = "ℹ️ Autoría para Publicación Global: " + resolved_author["label"]
		author_note.add_theme_font_size_override("font_size", 10)
		author_note.add_theme_color_override("font_color", Color(0.6, 0.75, 0.9))
		vbox.add_child(author_note)
		
		var btn_row = HBoxContainer.new()
		btn_row.add_theme_constant_override("separation", 12)
		btn_row.alignment = BoxContainer.ALIGNMENT_END
		
		var craft_btn = Button.new()
		craft_btn.text = "📜 Craftear Hoja Oculta (Ítem en Almacén)"
		craft_btn.custom_minimum_size = Vector2(240, 36)
		craft_btn.add_theme_font_size_override("font_size", 11)
		_style_action_btn(craft_btn, Color(0.2, 0.45, 0.8))
		craft_btn.pressed.connect(func(): _on_craft_sheet(entry, craft_btn))
		btn_row.add_child(craft_btn)
		
		var pub_btn = Button.new()
		pub_btn.text = "🌟 Publicar al Mundo (+500 Silver)"
		pub_btn.custom_minimum_size = Vector2(220, 36)
		pub_btn.add_theme_font_size_override("font_size", 11)
		_style_action_btn(pub_btn, Color(0.8, 0.6, 0.1))
		if not is_acquired:
			pub_btn.disabled = true
			pub_btn.tooltip_text = "Debes asimilar este conocimiento en tu Códice antes de publicarlo al mundo."
			pub_btn.modulate = Color(0.6, 0.6, 0.6, 0.8)
		else:
			pub_btn.disabled = false
			pub_btn.tooltip_text = "Publica este conocimiento para que figure en la Wiki oficial y recibe +500 Silver."
		pub_btn.pressed.connect(func(): _on_publish_entry(entry, resolved_author["name"], pub_btn))
		btn_row.add_child(pub_btn)
		
		vbox.add_child(btn_row)
	else:
		var pub_note = Label.new()
		pub_note.text = "✓ Esta entidad ya ha sido revelada en la Wiki SSR pública del servidor. Todos los jugadores tienen acceso a su información de combate."
		pub_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		pub_note.add_theme_font_size_override("font_size", 11)
		pub_note.add_theme_color_override("font_color", Color(0.5, 0.8, 0.6))
		vbox.add_child(pub_note)
		
	detail_container.add_child(tome_panel)

func _style_action_btn(btn: Button, accent: Color) -> void:
	var sb = StyleBoxFlat.new()
	sb.bg_color = accent * 0.4
	sb.bg_color.a = 0.95
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = accent
	sb.corner_radius_top_left = 5
	sb.corner_radius_top_right = 5
	sb.corner_radius_bottom_right = 5
	sb.corner_radius_bottom_left = 5
	btn.add_theme_stylebox_override("normal", sb)

func _get_resolved_author() -> Dictionary:
	if AuthManager:
		if AuthManager.selected_character_name != "":
			return {
				"name": AuthManager.selected_character_name,
				"label": "Campeón Seleccionado: '%s'" % AuthManager.selected_character_name
			}
		elif AuthManager.username != "":
			return {
				"name": AuthManager.username,
				"label": "Cuenta de Usuario: '%s' (Sin campeón activo en Shelter)" % AuthManager.username
			}
	return {
		"name": "Pionero Anónimo",
		"label": "Pionero de la Orden"
	}

func _on_publish_entry(entry: Dictionary, author_name: String, pub_btn: Button = null) -> void:
	if pub_btn:
		pub_btn.disabled = true
		
	entry["is_public"] = true
	entry["is_acquired"] = true
	entry["pioneer"] = author_name
	
	# Sincronizar autoritativamente con la Wiki Web viva (Next.js / SSR)
	_sync_publish_to_web(entry["id"], author_name)
	
	# Acreditar recompensa de +500 Silver de First Discoverer Bounty
	if has_node("/root/UIOrchestrator"):
		var orch = get_node("/root/UIOrchestrator")
		var lobby = orch.get_window_instance("shelter_lobby") if orch.has_method("get_window_instance") else null
		if lobby and "player_silver" in lobby:
			lobby.player_silver += 500
			if lobby.silver_badge:
				lobby.silver_badge.text = "🪙 %d Silver" % lobby.player_silver
		if lobby and lobby.has_method("_notify"):
			lobby._notify("🌟 ¡Entidad Revelada al Mundo! '%s' publicado por '%s' (+500 Silver)." % [entry["name"], author_name])
		if orch.has_method("show_toast"):
			orch.show_toast(
				"🌟 ¡PUBLICADO AL MUNDO!",
				"'%s' revelado por %s. +500 Silver de recompensa acreditados." % [entry["name"], author_name],
				Color(1.0, 0.85, 0.2)
			)
				
	_populate_list()
	_show_detail(entry["id"])
	play_golden_pulse()
	_set_status("¡Publicado al mundo a nombre de '%s'! Has recibido +500 Silver de First Discoverer Bounty y figura en la Wiki pública." % author_name)
	print("[Codex] Entidad %s publicada al dominio global por %s (+500 Silver)." % [entry["id"], author_name])

func _sync_publish_to_web(slug: String, author_name: String) -> void:
	# 1. Petición HTTP a la API de la Wiki Web viva
	var http = HTTPRequest.new()
	add_child(http)
	var url = GameConfig.get_web_url() + "/api/wiki/publish"
	var headers = ["Content-Type: application/json"]
	var payload = JSON.stringify({"slug": slug, "pioneer": author_name})
	http.request(url, headers, HTTPClient.METHOD_POST, payload)
	http.request_completed.connect(func(_result, response_code, _hdr, _body):
		print("[Codex] Web Wiki Sync HTTP result: code %d" % response_code)
		http.queue_free()
	)

func _on_craft_sheet(entry: Dictionary, craft_btn: Button = null) -> void:
	if craft_btn:
		craft_btn.disabled = true
		
	var user_id = AuthManager.user_id if AuthManager and AuthManager.user_id != "" else "local_user"
	var free_slot = _find_free_stash_slot(1, 1)
	
	if free_slot == Vector2i(-1, -1):
		_set_status("¡Error: Almacén lleno! Libera una casilla 1x1 en tu Almacén para guardar la Hoja de Descubrimiento.")
		if craft_btn:
			craft_btn.disabled = false
		return
		
	var sheet_id = "sheet_" + entry["id"] + "_" + str(Time.get_ticks_msec())
	var sheet_item = {
		"id": sheet_id,
		"user_id": user_id,
		"character_id": "",
		"item_definition_id": "00000000-0000-0000-0000-000000000099",
		"display_name": "Hoja de Descubrimiento: " + entry["name"],
		"icon_path": "res://assets/icons/items/scroll1x1.png",
		"rarity": "rare",
		"item_type": "consumable",
		"grid_width": 1,
		"grid_height": 1,
		"slot_x": free_slot.x,
		"slot_y": free_slot.y,
		"is_rotated": false,
		"is_secure": false,
		"secret_id": entry["id"],
		"secret_name": entry["name"]
	}
	
	# Inyectar en ShelterManager inventario y cache local
	ShelterManager.shelter_inventory.append(sheet_item)
	ShelterManager.all_items_cache[sheet_id] = sheet_item
	
	# Petición asíncrona de persistencia si el backend está activo — ESPERAR para evitar carrera
	await ShelterManager.admin_add_item(user_id, "", sheet_item["item_definition_id"], 1, free_slot.x, free_slot.y, false)
	
	# Forzar actualización en ventanas de inventario abiertas una vez persistido
	var inv_uis = get_tree().get_nodes_in_group("inventory_ui")
	for inv in inv_uis:
		if inv.has_method("_request_data_refresh"):
			await inv._request_data_refresh()
			
	if craft_btn:
		craft_btn.disabled = false
			
	_set_status("¡Hoja física de descubrimiento para '%s' crafteada y depositada en Almacén (%d,%d)! Clic derecho sobre ella para consumirla." % [entry["name"], free_slot.x, free_slot.y])
	print("[Codex] Hoja de descubrimiento física creada para %s en (%d,%d)." % [entry["id"], free_slot.x, free_slot.y])

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

func play_golden_pulse() -> void:
	if detail_container and detail_container.get_child_count() > 0:
		var panel = detail_container.get_child(0)
		var orig_mod = panel.modulate
		var tween = create_tween()
		tween.tween_property(panel, "modulate", Color(2.2, 1.9, 0.5, 1.0), 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(panel, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tween.tween_property(panel, "modulate", Color(1.8, 1.5, 0.4, 1.0), 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(panel, "modulate", orig_mod, 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

# Método público consumido al hacer clic derecho en una Hoja de Descubrimiento desde el inventario
func unlock_secret_from_sheet(secret_id: String, secret_name: String) -> void:
	var target_entry = null
	for entry in discoveries:
		if entry["id"] == secret_id or entry["name"] == secret_name or entry["name"] in secret_name:
			target_entry = entry
			break
			
	if target_entry == null:
		target_entry = {
			"id": secret_id,
			"name": secret_name if secret_name != "" else "Misterio Arcano Asimilado",
			"type": "ITEMS",
			"is_public": false,
			"is_acquired": true,
			"pioneer": null,
			"desc": "[CONOCIMIENTO OCULTO]: Desbloqueado mediante la lectura de una Hoja de Descubrimiento física. Otorga +5% de buff pasivo a tu Códice personal."
		}
		discoveries.append(target_entry)
	else:
		target_entry["is_acquired"] = true
		
	selected_entry_id = target_entry["id"]
	_populate_list()
	_show_detail(target_entry["id"])
	play_golden_pulse()
	_set_status("¡Conocimiento Asimilado! Has descifrado '%s' y añadido su secreto a tu Códice." % target_entry["name"])

func _set_status(msg: String) -> void:
	if status_label:
		status_label.text = msg
