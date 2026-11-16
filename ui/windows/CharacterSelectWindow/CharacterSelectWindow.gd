extends "res://ui/windows/common/EntryWindow.gd"
## Selección de personaje — UI v2.4 Paso 15 (design_ref/pantallas_html/MMO-Seleccion.html).
##
## - Fondo del reino con velo rgba(5,8,10,0.72); «[NOMBRE DEL JUEGO]» y «Reino Umbral · Español ·
##   24 ms · población alta».
## - Columna izquierda (320 px): tarjetas (avatar con aro del universo, nombre, clase, «Verdalia ·
##   hace 2 días», nivel). La activa lleva aro cian #46e3c1 de 2 px; los personajes especiales
##   (Anexo F) aro dorado de 1,5 px. «+ Crear personaje · 2 espacios libres».
## - Centro: silueta del personaje con respiración y pedestal cian, nombre (32 px), línea de clase
##   y estadísticas básicas.
## - Derecha (360 px): «Mientras no estabas» y «Continúa donde lo dejaste».
## - Pie: «Ir a El Nido [5]», «Entrar al mundo [Espacio]», chips Ajustes · Accesibilidad · Créditos ·
##   Borrar personaje (con confirmación «ESCRIBE EL NOMBRE PARA CONFIRMAR»).
##
## Teclado: ↑/↓ carrusel · Espacio/Enter entrar · Supr borrar · H El Nido · Esc cierra el diálogo.

signal world_entry(character: Dictionary, destination: Dictionary)
signal nest_requested
signal credits_requested

var title_label_main: Label
var realm_label: Label
var list_box: VBoxContainer
var character_cards: Array[PanelContainer] = []
var create_button: Button
var model: EK.Silhouette
var model_name: Label
var model_detail: Label
var stats_row: HBoxContainer
var away_card: PanelContainer
var continue_box: PanelContainer
var nest_button: Button
var enter_button: Button
var chips_row: HBoxContainer
var delete_chip: Button
var a11y_toggle: Button
var delete_dialog: Control
var delete_title: Label
var delete_input: LineEdit
var delete_confirm: Button
var delete_error: Label
var info_label: Label


func _screen_id() -> String:
	return "character_select"


func _screen() -> String:
	return AuthScript.SCREEN_SELECT


func _veil_base() -> float:
	return T.SELECT_VEIL.a


func _screen_title() -> String:
	var c: Dictionary = service.selected_character()
	return "Selección de personaje. %s" % c.get("name", "") if not c.is_empty() else "Selección de personaje"


func _service_signals() -> Array:
	return ["characters_changed", "character_selected", "session_changed"]


# ==========================================================================
# API
# ==========================================================================
func select(id: String) -> bool:
	return service.select_character(id)


func select_offset(step: int) -> bool:
	return service.select_offset(step)


func enter_world() -> Dictionary:
	var r: Dictionary = service.enter_world()
	if r.get("ok", false):
		world_entry.emit(r["character"], r["destination"])
		navigate("game_loading", {"keep_current": true})
	else:
		info_label.text = "Inicia sesión antes de entrar" if r.get("code", "") == "not_logged_in" else "Elige un personaje"
		info_label.visible = true
	return r


func create_character() -> Dictionary:
	var r: Dictionary = service.begin_creation()
	if r.get("ok", false):
		navigate("character_create", {"keep_current": true})
	else:
		info_label.text = str(r.get("message", ""))
		info_label.visible = true
	return r


func open_delete_dialog(id: String = "") -> Dictionary:
	var r: Dictionary = service.request_delete(id)
	if r.get("ok", false):
		delete_title.text = "Borrar a %s" % r["name"]
		delete_input.text = ""
		delete_input.placeholder_text = str(r["name"])
		delete_error.text = ""
		delete_dialog.visible = true
		_update_delete_button()
		if delete_input.is_inside_tree():
			delete_input.grab_focus()
	else:
		info_label.text = str(r.get("message", ""))
		info_label.visible = true
	return r


func type_delete_name(text: String) -> void:
	delete_input.text = text
	_update_delete_button()


func confirm_delete() -> Dictionary:
	var r: Dictionary = service.confirm_delete(delete_input.text)
	if r.get("ok", false):
		delete_dialog.visible = false
	else:
		delete_error.text = str(r.get("message", ""))
	return r


func close_delete_dialog() -> void:
	service.cancel_delete()
	delete_dialog.visible = false


func go_to_nest() -> void:
	nest_requested.emit()
	var orch := _orchestrator()
	if orch != null:
		orch.open_window("shelter_pocket")


func toggle_accessibility_bar() -> void:
	a11y_bar.visible = not a11y_bar.visible


func _handle_key(code: int, _ev: InputEventKey) -> bool:
	if delete_dialog.visible:
		match code:
			KEY_ESCAPE:
				close_delete_dialog()
				return true
			KEY_ENTER, KEY_KP_ENTER:
				confirm_delete()
				return true
		return false
	match code:
		KEY_UP, KEY_LEFT:
			select_offset(-1)
			return true
		KEY_DOWN, KEY_RIGHT:
			select_offset(1)
			return true
		KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
			enter_world()
			return true
		KEY_DELETE:
			open_delete_dialog()
			return true
		KEY_H:
			go_to_nest()
			return true
	return false


# ==========================================================================
# Construcción
# ==========================================================================
func _build() -> void:
	title_label_main = Kit.label(service.game_name, 22, T.ACCENT_DEFAULT, "bold")
	title_label_main.name = "GameName"
	var fv := FontVariation.new()
	fv.base_font = T.font("bold")
	fv.spacing_glyph = 6
	title_label_main.add_theme_font_override("font", fv)
	place(title_label_main, 40, 32)
	realm_label = Kit.label("", 14, T.TEXT_KEY)
	realm_label.name = "Realm"
	realm_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	place(realm_label, -1, 36, 40, -1, 600)

	list_box = EK.vbox("Characters", 10)
	place(list_box, T.SELECT_LIST_LEFT, T.SELECT_TOP, -1, -1, T.SELECT_LIST_WIDTH)

	var center := EK.vbox("Model", 4)
	center.alignment = BoxContainer.ALIGNMENT_END
	place(center, 520, T.SELECT_TOP, -1, -1, 400)
	model = EK.Silhouette.new(236, 420, 320)
	model.name = "Silhouette"
	model.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	center.add_child(model)
	model_name = Kit.label("", T.SELECT_NAME_SIZE, T.TEXT, "bold")
	model_name.name = "Name"
	model_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(model_name)
	model_detail = Kit.label("", 15, T.TEXT_SECONDARY)
	model_detail.name = "Detail"
	model_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(model_detail)
	stats_row = EK.hbox("Stats", 6)
	stats_row.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(stats_row)

	away_card = EK.card("Away", 20)
	place(away_card, -1, T.SELECT_TOP, 40, -1, T.SELECT_AWAY_WIDTH)
	away_card.add_child(EK.vbox("Body", 12))

	var actions := EK.hbox("Actions", 12)
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	place(actions, 0, -1, 0, 50)
	nest_button = EK.button("NestButton", "", T.SELECT_ENTER_HEIGHT, 17, 26)
	nest_button.custom_minimum_size.x = 190
	nest_button.pressed.connect(go_to_nest)
	var nb := _button_content(nest_button, "Ir a El Nido", 17, T.TEXT)
	var badge := Kit.panel("Badge", Kit.box(T.ACCENT_DEFAULT, 10), 7, 0)
	badge.custom_minimum_size = Vector2(20, 20)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bl := Kit.label("", 12, T.ENTRY_PRIMARY_TEXT, "bold")
	bl.name = "Count"
	bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.add_child(bl)
	nb.add_child(badge)
	actions.add_child(nest_button)
	enter_button = EK.button("EnterButton", "", T.SELECT_ENTER_HEIGHT, 20, 40)
	EK.primary(enter_button, 10, 40)
	enter_button.custom_minimum_size.x = 300
	enter_button.pressed.connect(enter_world)
	var eb := _button_content(enter_button, "Entrar al mundo", 20, T.ENTRY_PRIMARY_TEXT)
	var kb := Kit.kbd("Espacio", 20, 11)
	kb.name = "Kbd"
	kb.add_theme_stylebox_override("panel", Kit.box(Color(0, 0, 0, 0.2), 5))
	(kb.get_node("Key") as Label).add_theme_color_override("font_color", T.ENTRY_PRIMARY_TEXT)
	eb.add_child(kb)
	enter_button.set_meta("kbd", "Espacio")
	actions.add_child(enter_button)

	chips_row = EK.hbox("Chips", 8)
	place(chips_row, 40, -1, -1, 56)
	var settings := _chip_button("Settings", "Ajustes")
	settings.pressed.connect(func() -> void:
		var orch := _orchestrator()
		if orch != null:
			orch.open_window("options_menu"))
	a11y_toggle = _chip_button("AccessibilityChip", "Accesibilidad")
	a11y_toggle.pressed.connect(toggle_accessibility_bar)
	var credits := _chip_button("Credits", "Créditos")
	credits.pressed.connect(func() -> void: credits_requested.emit())
	delete_chip = _chip_button("DeleteCharacter", "Borrar personaje")
	delete_chip.add_theme_color_override("font_color", Color("#ff8a8a"))
	delete_chip.pressed.connect(func() -> void: open_delete_dialog())

	var bar := build_a11y_bar()
	bar.visible = false
	place(bar, 40, -1, -1, 96)

	info_label = Kit.label("", 13, Color("#ff8a8a"), "semibold")
	info_label.name = "Info"
	info_label.visible = false
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	place(info_label, 0, -1, 0, 116)

	_build_delete_dialog()


## Contenido centrado (texto + extras) dentro de un botón sin texto propio.
func _button_content(b: Button, text: String, font_size: int, color: Color) -> HBoxContainer:
	var h := EK.hbox("Content", 8)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	b.add_child(h)
	var l := Kit.label(text, font_size, color, "semibold")
	l.name = "Text"
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(l)
	return h


func _chip_button(node_name: String, text: String) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(0, 28)
	b.add_theme_font_override("font", T.font("medium"))
	b.add_theme_font_size_override("font_size", 13)
	for st in ["normal", "hover", "pressed", "focus"]:
		var sb := Kit.box(T.BUTTON_BG if st != "hover" else T.BUTTON_BG.lightened(0.08), 8)
		if st == "focus":
			sb = Kit.box(Color.TRANSPARENT, 8, 2, T.ACCENT_DEFAULT)
		sb.content_margin_left = 10
		sb.content_margin_right = 10
		b.add_theme_stylebox_override(st, sb)
	b.add_theme_color_override("font_color", T.TEXT_KEY)
	chips_row.add_child(b)
	return b


func _build_delete_dialog() -> void:
	delete_dialog = Control.new()
	delete_dialog.name = "DeleteDialog"
	delete_dialog.mouse_filter = Control.MOUSE_FILTER_STOP
	delete_dialog.visible = false
	delete_dialog.size = T.CINEMA_DESIGN_SIZE
	stage.add_child(delete_dialog)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.size = T.CINEMA_DESIGN_SIZE
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	delete_dialog.add_child(dim)
	var card := EK.card("Card", 24, Color("#ff6b6b"), 1.5)
	card.position = Vector2((T.CINEMA_DESIGN_SIZE.x - 440) * 0.5, 250)
	card.custom_minimum_size = Vector2(440, 0)
	delete_dialog.add_child(card)
	var v := EK.vbox("Body", 12)
	card.add_child(v)
	delete_title = Kit.label("", 24, T.TEXT, "bold")
	delete_title.name = "Title"
	v.add_child(delete_title)
	var warn := Kit.label("No se puede deshacer: su equipo, sus poderes y su progreso se pierden. Lo que guarda en el refugio se queda.", 14, T.TEXT_KEY)
	warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warn.custom_minimum_size.x = 392
	v.add_child(warn)
	var cap := Kit.caps("Escribe el nombre para confirmar", Color("#ff8a8a"))
	cap.name = "Prompt"
	v.add_child(cap)
	delete_input = LineEdit.new()
	delete_input.name = "NameInput"
	delete_input.custom_minimum_size = Vector2(0, 42)
	delete_input.add_theme_font_size_override("font_size", 16)
	var sb := Kit.box(T.ENTRY_SUB_BG, 10, 1, Color(1, 1, 1, 0.1))
	sb.content_margin_left = 12
	delete_input.add_theme_stylebox_override("normal", sb)
	var fsb := Kit.box(T.ENTRY_SUB_BG, 10, 2, Color("#ff6b6b"))
	fsb.content_margin_left = 12
	delete_input.add_theme_stylebox_override("focus", fsb)
	delete_input.text_changed.connect(func(_t: String) -> void: _update_delete_button())
	delete_input.text_submitted.connect(func(_t: String) -> void: confirm_delete())
	v.add_child(delete_input)
	delete_error = Kit.label("", 13, Color("#ff8a8a"))
	delete_error.name = "Error"
	v.add_child(delete_error)
	var row := EK.hbox("Buttons", 10)
	row.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(row)
	var cancel := EK.button("Cancel", "Cancelar", 40)
	cancel.pressed.connect(close_delete_dialog)
	row.add_child(cancel)
	delete_confirm = EK.button("Confirm", "Borrar personaje", 40)
	for st in ["normal", "hover", "pressed", "focus"]:
		delete_confirm.add_theme_stylebox_override(st, Kit.box(Color("#c0392b") if st != "hover" else Color("#d44a3c"), 10))
	delete_confirm.add_theme_stylebox_override("disabled", Kit.box(Color("#c0392b", 0.3), 10))
	delete_confirm.pressed.connect(confirm_delete)
	row.add_child(delete_confirm)


func _update_delete_button() -> void:
	delete_confirm.disabled = not service.delete_confirm_matches(delete_input.text)


# ==========================================================================
# Refresco
# ==========================================================================
func refresh() -> void:
	if not _built or service == null:
		return
	realm_label.text = service.realm_header()
	_rebuild_list()
	var c: Dictionary = service.selected_character()
	model.visible = not c.is_empty()
	model_name.text = str(c.get("name", "Sin personajes"))
	model_detail.text = service.character_detail_line(c) if not c.is_empty() else "Crea tu primer personaje"
	if not c.is_empty():
		var col: Dictionary = service.appearance_colors(c["appearance"], str(c["class_id"]))
		model.accent_body = Color(str(col["body"]))
		model.ring = T.ENTRY_SPECIAL if bool(c["special"]) else T.ACCENT_DEFAULT
	Kit.clear(stats_row)
	for s in service.character_stats_rows(c):
		var chip := Kit.chip("%s %s" % [s["label"], s["value"]])
		chip.name = "Stat"
		stats_row.add_child(chip)
	_rebuild_away(c)
	var badge := nest_button.find_child("Badge", true, false) as Control
	badge.visible = service.nest_ready > 0
	(badge.get_node("Count") as Label).text = str(service.nest_ready)
	enter_button.disabled = c.is_empty() or not service.logged_in
	delete_chip.disabled = not service.can_delete(service.selected_character_id)
	delete_chip.tooltip_text = "Los personajes especiales los retira el equipo" if delete_chip.disabled and not c.is_empty() else "Borrar el personaje seleccionado"
	info_label.visible = false
	refresh_a11y_bar()
	apply_accessibility()


func _rebuild_list() -> void:
	Kit.clear(list_box)
	character_cards.clear()
	for c in service.characters:
		var id := str(c["id"])
		var selected: bool = id == service.selected_character_id
		var special := bool(c["special"])
		var edge := T.ENTRY_SELECTED if selected else (T.ENTRY_SPECIAL if special else T.ENTRY_CARD_EDGE)
		var w := 2.0 if selected else (1.5 if special else 1.0)
		var sb := Kit.box(T.ENTRY_CARD_BG, 18, w, edge)
		sb.shadow_color = Color(0, 0, 0, 0.45)
		sb.shadow_size = 24 if selected else 0
		sb.shadow_offset = Vector2(0, 12)
		var card := Kit.panel("Character_%s" % id, sb, 16, 14)
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		card.set_meta("character_id", id)
		card.set_meta("selected", selected)
		card.set_meta("special", special)
		card.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				if (ev as InputEventMouseButton).double_click:
					select(id)
					enter_world()
				else:
					select(id))
		EK.a11y_name(card, "%s, %s" % [c["name"], service.character_meta_line(c)])
		var h := EK.hbox("Row", 12)
		card.add_child(h)
		var av := EK.Avatar.new(48, Color(service.character_color(c)))
		av.name = "Avatar"
		h.add_child(av)
		var v := EK.vbox("Text", 2)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(v)
		var n := Kit.label(str(c["name"]), 18, T.TEXT, "bold")
		n.name = "Name"
		v.add_child(n)
		var cl := Kit.label(service.character_subtitle(c), 13, T.TEXT_SECONDARY)
		cl.name = "Class"
		v.add_child(cl)
		var meta := Kit.label(service.character_meta_line(c), 12, Color(service.character_color(c)))
		meta.name = "Meta"
		v.add_child(meta)
		var lv := Kit.label(service.character_level_text(c), 22, T.TEXT_KEY, "bold")
		lv.name = "Level"
		lv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(lv)
		list_box.add_child(card)
		character_cards.append(card)
	create_button = Button.new()
	create_button.name = "CreateCharacter"
	create_button.custom_minimum_size = Vector2(0, 64)
	create_button.focus_mode = Control.FOCUS_ALL
	for st in ["normal", "hover", "pressed", "focus"]:
		var e := Color(1, 1, 1, 0.18) if st != "focus" else T.ACCENT_DEFAULT
		create_button.add_theme_stylebox_override(st, Kit.box(Color(1, 1, 1, 0.03) if st == "hover" else Color(0, 0, 0, 0), 18, 1.5, e))
	create_button.add_theme_stylebox_override("disabled", Kit.box(Color(0, 0, 0, 0), 18, 1, Color(1, 1, 1, 0.08)))
	create_button.pressed.connect(create_character)
	create_button.disabled = service.free_slots() <= 0
	var row := EK.hbox("Row", 8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	create_button.add_child(row)
	var t := Kit.label("+ Crear personaje", 15, T.TEXT_KEY)
	t.name = "Text"
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(t)
	var slots := Kit.label("· " + service.free_slots_text(), 15, T.TEXT_MUTED)
	slots.name = "Slots"
	slots.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slots)
	list_box.add_child(create_button)


func _rebuild_away(c: Dictionary) -> void:
	var v: VBoxContainer = away_card.get_node("Body")
	Kit.clear(v)
	v.add_child(Kit.caps("Mientras no estabas"))
	for i in service.away.size():
		var a: Dictionary = service.away[i]
		var row := EK.hbox("Away_%d" % i, 10)
		var d := EK.Dot.new(Color(str(a["color"])), 8.0)
		d.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		d.custom_minimum_size = Vector2(8, 20)
		row.add_child(d)
		var tv := EK.vbox("Text", 2)
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(tv)
		var tt := Kit.label(str(a["title"]), 15, T.TEXT, "semibold")
		tt.name = "Title"
		tv.add_child(tt)
		var tx := Kit.label(str(a["text"]), 13, T.TEXT_SECONDARY)
		tx.name = "Text"
		tx.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tv.add_child(tx)
		v.add_child(row)
	var cont: Dictionary = service.continue_info(c) if not c.is_empty() else {}
	continue_box = Kit.panel("Continue", Kit.box(T.ENTRY_SUB_BG, 12, 1, T.ACCENT_DEFAULT), 14, 12)
	continue_box.visible = not cont.is_empty()
	var cv := EK.vbox("Body", 4)
	continue_box.add_child(cv)
	cv.add_child(Kit.caps("Continúa donde lo dejaste", T.ACCENT_DEFAULT))
	var ct := Kit.label(str(cont.get("title", "")), 15, T.TEXT, "semibold")
	ct.name = "Title"
	cv.add_child(ct)
	var cx := Kit.label(str(cont.get("text", "")), 13, T.TEXT_SECONDARY)
	cx.name = "Text"
	cv.add_child(cx)
	v.add_child(continue_box)
