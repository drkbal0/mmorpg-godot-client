extends "res://ui/windows/common/SystemWindow.gd"
## Ajustes — UI v2.4 Paso 16 · ADR 114 (design_ref/pantallas_html/MMO-Ajustes.html).
##
## Lienzo 1440×810 con la barra del menú común y tres columnas (top 88, alto 694):
## - Izquierda (300 px): «Ajustes», buscador en vivo (Ctrl K · «sombras» resalta Gráficos › Calidad
##   de sombras e Interfaz › Sombra del texto) y las 7 categorías; punto ámbar si hay advertencia
##   (atajo repetido en Controles).
## - Centro (700 px): opciones de la categoría en filas de 54 px con su valor (140 px), impacto en
##   fps («−8 fps» ámbar, «+12 fps» verde) y, en Gráficos, los presets Bajo · Medio · Alto · Ultra ·
##   Personal. Sonido: 5 buses con deslizador y silencio. Controles: teclas reasignables.
## - Derecha (352 px): «Rendimiento estimado en tu PC» (4 barras), tarjeta «Atajo repetido» con
##   solución en un clic («Montura → Z» · «Elegir otra»), tarjeta de confirmación de pantalla (15 s)
##   y el pie «3 cambios sin aplicar…» con «Deshacer» y «Aplicar».
##
## Teclado: Ctrl K buscar · Esc limpia la búsqueda / cancela la reasignación / cierra · F10 cierra ·
## Ctrl Enter aplicar · Ctrl Z deshacer el borrador.

const S = SettingsScript

signal category_selected(category: String)
signal option_chosen(category: String, key: String, value: Variant)

var category := S.CAT_GRAPHICS
var search_text := ""

var left_card: PanelContainer
var heading_label: Label
var search_edit: LineEdit
var search_summary_label: Label
var category_box: VBoxContainer
var category_buttons: Dictionary = {}          # id -> Button
var category_warnings: Dictionary = {}         # id -> Shape

var center_card: PanelContainer
var category_title: Label
var preset_bar: PanelContainer
var preset_buttons: Dictionary = {}            # id -> Button
var options_scroll: ScrollContainer
var options_box: VBoxContainer
var option_rows: Dictionary = {}               # key -> PanelContainer
var value_buttons: Dictionary = {}             # key -> Button (select/toggle)
var fps_labels: Dictionary = {}                # key -> Label
var hint_labels: Dictionary = {}               # key -> Label
var pending_dots: Dictionary = {}              # key -> Control
var sliders: Dictionary = {}                   # key -> HSlider
var slider_labels: Dictionary = {}             # key -> Label
var mute_buttons: Dictionary = {}              # bus -> Button
var key_buttons: Dictionary = {}               # action -> Button
var info_labels: Dictionary = {}               # key -> Label

var right_card: PanelContainer
var perf_box: VBoxContainer
var perf_rows: Array[Dictionary] = []          # {row, name, fps, meter, shape}
var perf_note: Label
var conflict_card: PanelContainer
var conflict_key: PanelContainer
var conflict_label: Label
var quick_fix_button: Button
var choose_other_button: Button
var confirm_card: PanelContainer
var confirm_label: Label
var keep_button: Button
var revert_button: Button
var pending_label: RichTextLabel
var undo_button: Button
var apply_button: Button

var _popup: PopupMenu
var _popup_key := ""
var _rebuilding := false


func _window_id() -> String:
	return "settings_window"


# ==========================================================================
# Ciclo de vida
# ==========================================================================
## params: {"category": "graphics", "search": "", "source": ...}
func initialize_window(params: Dictionary) -> void:
	if settings == null:
		_resolve_settings()
	var cat := str(params.get("category", category))
	if settings.category_ids().has(cat):
		category = cat
	if params.has("search"):
		search_text = str(params["search"])
		if search_edit:
			search_edit.text = search_text
	visible = true
	if _built:
		_rebuild_options()
		refresh()


func _resolve_settings() -> void:
	super._resolve_settings()
	var pairs := [
		["value_changed", "_on_settings_changed"], ["pending_changed", "_on_settings_changed"],
		["applied", "_on_settings_changed"], ["discarded", "_on_settings_changed"],
		["conflicts_changed", "_on_settings_changed"], ["display_confirm_started", "_on_settings_changed"],
		["display_confirm_tick", "_on_confirm_tick"], ["display_confirm_finished", "_on_settings_changed"],
		["preset_changed", "_on_settings_changed"], ["rebind_started", "_on_settings_changed"],
		["rebind_finished", "_on_rebind_finished"],
	]
	for p in pairs:
		var cb := Callable(self, p[1])
		if not settings.is_connected(p[0], cb):
			settings.connect(p[0], cb)


func _on_settings_changed(_a = null, _b = null, _c = null) -> void:
	if _built and not _rebuilding:
		refresh()


func _on_confirm_tick(remaining: float) -> void:
	if _built and confirm_label:
		confirm_label.text = "Se revierten solos en %d s" % int(ceil(remaining))


func _on_rebind_finished(_action: String, _key: String) -> void:
	if _built:
		refresh()


# ==========================================================================
# API (tests y atajos)
# ==========================================================================
func select_category(id: String) -> bool:
	if not settings.category_ids().has(id):
		return false
	category = id
	_rebuild_options()
	refresh()
	category_selected.emit(id)
	settings.announce(settings.category_label(id))
	return true


func set_search(text: String) -> void:
	search_text = text
	if search_edit and search_edit.text != text:
		search_edit.text = text
	var hits: Array = settings.search(text)
	if not hits.is_empty():
		var in_current := false
		for h in hits:
			if h["category"] == category:
				in_current = true
				break
		if not in_current:
			category = str(hits[0]["category"])
	_rebuild_options()
	refresh()


func focus_search() -> void:
	if search_edit and search_edit.is_inside_tree():
		search_edit.grab_focus()


func choose(cat: String, key: String, value: Variant) -> bool:
	var ok: bool = settings.set_value(cat, key, value)
	option_chosen.emit(cat, key, value)
	return ok


func choose_preset(id: String) -> bool:
	return settings.apply_preset(id)


func apply_changes() -> Array:
	return settings.apply()


func undo_changes() -> int:
	return settings.discard()


func keep_display() -> bool:
	return settings.keep_display()


func revert_display() -> bool:
	return settings.revert_display()


## «Montura → Z»
func quick_fix() -> bool:
	return settings.resolve_conflict()


## «Elegir otra»: abre Controles y espera la tecla para la acción a mover.
func choose_other_key() -> bool:
	var c: Array = settings.find_conflicts()
	if c.is_empty():
		return false
	var s: Dictionary = settings.suggest_resolution(c[0])
	if s.is_empty():
		return false
	if category != S.CAT_CONTROLS:
		select_category(S.CAT_CONTROLS)
	var ok: bool = settings.begin_rebind(str(s["action"]))
	refresh()
	if ok and option_rows.has(str(s["action"])):
		options_scroll.ensure_control_visible.call_deferred(option_rows[str(s["action"])])
	return ok


func start_rebind(action: String) -> bool:
	var ok: bool = settings.begin_rebind(action)
	refresh()
	return ok


func _handle_key(ev: InputEventKey) -> bool:
	var code := ev.keycode if ev.keycode != KEY_NONE else ev.physical_keycode
	if settings.rebinding_action != "":
		if code == KEY_ESCAPE:
			settings.cancel_rebind()
		else:
			settings.capture_key(code)
		refresh()
		return true
	if (ev.ctrl_pressed or ev.meta_pressed) and code == KEY_K:
		focus_search()
		return true
	if (ev.ctrl_pressed or ev.meta_pressed) and (code == KEY_ENTER or code == KEY_KP_ENTER):
		apply_changes()
		return true
	if (ev.ctrl_pressed or ev.meta_pressed) and code == KEY_Z:
		undo_changes()
		return true
	if code == KEY_ESCAPE and search_text != "":
		set_search("")
		return true
	return false


func _on_f10() -> void:
	close_window()


func _input(event: InputEvent) -> void:
	# La reasignación captura cualquier tecla antes que los controles con foco.
	if settings == null or settings.rebinding_action == "" or not is_visible_in_tree():
		return
	if event is InputEventKey and event.pressed and not event.is_echo():
		if handle_key_event(event as InputEventKey):
			get_viewport().set_input_as_handled()


# ==========================================================================
# Construcción
# ==========================================================================
func _build() -> void:
	_build_left()
	_build_center()
	_build_right()
	_popup = PopupMenu.new()
	_popup.name = "ChoicePopup"
	_popup.id_pressed.connect(_on_popup_id)
	add_child(_popup)
	_rebuild_options()


func _build_left() -> void:
	left_card = SK.card("Categories", 18)
	place(left_card, T.SETTINGS_LEFT_X, T.SETTINGS_TOP, T.SETTINGS_LEFT_WIDTH, T.SETTINGS_CARD_HEIGHT)
	var v := SK.vbox("Body", 8)
	left_card.add_child(v)
	heading_label = Kit.label("Ajustes", 20, T.TEXT, "bold")
	heading_label.name = "Title"
	v.add_child(heading_label)
	search_edit = LineEdit.new()
	search_edit.name = "Search"
	search_edit.placeholder_text = "Buscar un ajuste  ·  Ctrl K"
	search_edit.custom_minimum_size = Vector2(0, 38)
	search_edit.clear_button_enabled = true
	search_edit.add_theme_font_override("font", T.font("medium"))
	search_edit.add_theme_font_size_override("font_size", 14)
	search_edit.add_theme_color_override("font_color", T.TEXT)
	search_edit.add_theme_color_override("font_placeholder_color", T.TEXT_MUTED)
	search_edit.add_theme_color_override("caret_color", T.ACCENT_DEFAULT)
	search_edit.right_icon = null
	SK.a11y_name(search_edit, "Buscar en los ajustes")
	search_edit.text_changed.connect(func(t: String) -> void: set_search(t))
	v.add_child(search_edit)
	search_summary_label = Kit.label("", 12, T.TEXT_SECONDARY)
	search_summary_label.name = "SearchSummary"
	search_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	search_summary_label.custom_minimum_size.x = 260
	v.add_child(search_summary_label)
	category_box = SK.vbox("CategoryList", 2)
	v.add_child(category_box)
	for c in settings.categories:
		var id := str(c["id"])
		var b := Button.new()
		b.name = "Cat_" + id
		b.focus_mode = Control.FOCUS_ALL
		b.custom_minimum_size = Vector2(0, T.SETTINGS_CATEGORY_HEIGHT)
		SK.a11y_name(b, str(c["label"]))
		var h := SK.hbox("Row", 8)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		h.offset_left = 12
		h.offset_right = -12
		b.add_child(h)
		var l := Kit.label(str(c["label"]), 15, T.TEXT_KEY, "semibold")
		l.name = "Label"
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(l)
		var dot := SK.Shape.new("circle", T.SETTINGS_WARN, 8.0)
		dot.name = "Warning"
		dot.visible = false
		h.add_child(dot)
		b.pressed.connect(func() -> void: select_category(id))
		category_box.add_child(b)
		category_buttons[id] = b
		category_warnings[id] = dot


func _build_center() -> void:
	center_card = SK.card("Options", 22)
	place(center_card, T.SETTINGS_CENTER_X, T.SETTINGS_TOP, T.SETTINGS_CENTER_WIDTH, T.SETTINGS_CARD_HEIGHT)
	var v := SK.vbox("Body", 12)
	center_card.add_child(v)
	var head := SK.hbox("Header", 12)
	head.custom_minimum_size.y = 34
	v.add_child(head)
	category_title = Kit.label("", 20, T.TEXT, "bold")
	category_title.name = "CategoryTitle"
	category_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(category_title)
	head.add_child(SK.expand())
	var items: Array = []
	for p in settings.graphics_presets:
		items.append([p["id"], p["label"]])
	var seg := SK.segmented("Presets", items)
	preset_bar = seg["panel"]
	preset_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	preset_buttons = seg["buttons"]
	for id in preset_buttons:
		var pid := str(id)
		(preset_buttons[pid] as Button).pressed.connect(func() -> void: choose_preset(pid))
		SK.a11y_name(preset_buttons[pid], "Preset gráfico " + settings.preset_label(pid))
	head.add_child(preset_bar)
	options_scroll = ScrollContainer.new()
	options_scroll.name = "Scroll"
	options_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	options_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(options_scroll)
	options_box = SK.vbox("OptionList", 12)
	options_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	options_scroll.add_child(options_box)


func _build_right() -> void:
	right_card = SK.card("Side", 20)
	place(right_card, T.SETTINGS_RIGHT_X, T.SETTINGS_TOP, T.SETTINGS_RIGHT_WIDTH, T.SETTINGS_CARD_HEIGHT)
	var v := SK.vbox("Body", 12)
	right_card.add_child(v)
	v.add_child(Kit.caps("Rendimiento estimado en tu PC"))
	perf_box = SK.vbox("Performance", 12)
	v.add_child(perf_box)
	for i in settings.estimated_performance().size():
		var row := SK.vbox("Perf_%d" % i, 4)
		var h := SK.hbox("Head", 6)
		row.add_child(h)
		var n := Kit.label("", 14, T.TEXT)
		n.name = "Name"
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(n)
		var shp := SK.Shape.new("circle", T.SETTINGS_GOOD, 8.0)
		shp.name = "Shape"
		h.add_child(shp)
		var f := Kit.label("", 14, T.SETTINGS_GOOD, "bold")
		f.name = "Fps"
		h.add_child(f)
		var m := SK.Meter.new()
		m.name = "Meter"
		row.add_child(m)
		perf_box.add_child(row)
		perf_rows.append({"row": row, "name": n, "fps": f, "meter": m, "shape": shp})
	perf_note = Kit.label(settings.performance_note(), 12, T.TEXT_MUTED)
	perf_note.name = "PerfNote"
	perf_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	perf_note.custom_minimum_size.x = 300
	v.add_child(perf_note)

	conflict_card = SK.sub("ConflictCard", 14, 12, T.SETTINGS_WARN, 1.5)
	v.add_child(conflict_card)
	var cv := SK.vbox("Body", 8)
	conflict_card.add_child(cv)
	var ct := Kit.label("Atajo repetido", 14, T.SETTINGS_WARN, "bold")
	ct.name = "Title"
	cv.add_child(ct)
	var cm := SK.hbox("Message", 6)
	cv.add_child(cm)
	conflict_key = Kit.kbd("G")
	conflict_key.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	cm.add_child(conflict_key)
	conflict_label = Kit.label("", 13, T.TEXT_KEY)
	conflict_label.name = "Text"
	conflict_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	conflict_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cm.add_child(conflict_label)
	var cb := SK.hbox("Fixes", 6)
	cv.add_child(cb)
	quick_fix_button = SK.chip_button("QuickFix", "", 26)
	quick_fix_button.pressed.connect(func() -> void: quick_fix())
	cb.add_child(quick_fix_button)
	choose_other_button = SK.chip_button("ChooseOther", "Elegir otra", 26)
	choose_other_button.pressed.connect(func() -> void: choose_other_key())
	cb.add_child(choose_other_button)

	confirm_card = SK.sub("ConfirmCard", 14, 12, T.ACCENT_DEFAULT, 1.5)
	v.add_child(confirm_card)
	var fv := SK.vbox("Body", 8)
	confirm_card.add_child(fv)
	var ft := Kit.label("¿Mantener los cambios de pantalla?", 14, T.TEXT, "bold")
	ft.name = "Title"
	fv.add_child(ft)
	confirm_label = Kit.label("", 13, T.TEXT_KEY)
	confirm_label.name = "Countdown"
	fv.add_child(confirm_label)
	var fb := SK.hbox("Buttons", 8)
	fv.add_child(fb)
	keep_button = SK.button("Keep", "Mantener", 32, 13)
	SK.primary(keep_button)
	keep_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	keep_button.pressed.connect(func() -> void: keep_display())
	fb.add_child(keep_button)
	revert_button = SK.button("Revert", "Revertir", 32, 13)
	revert_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	revert_button.pressed.connect(func() -> void: revert_display())
	fb.add_child(revert_button)

	v.add_child(SK.vexpand())
	var foot := SK.vbox("Footer", 8)
	v.add_child(foot)
	pending_label = Kit.rich(13, T.TEXT_SECONDARY)
	pending_label.name = "Pending"
	pending_label.custom_minimum_size.x = 300
	foot.add_child(pending_label)
	var fbtn := SK.hbox("Buttons", 8)
	foot.add_child(fbtn)
	undo_button = SK.button("Undo", "Deshacer")
	undo_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	undo_button.pressed.connect(func() -> void: undo_changes())
	fbtn.add_child(undo_button)
	apply_button = SK.button("Apply", "Aplicar")
	SK.primary(apply_button)
	apply_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	apply_button.pressed.connect(func() -> void: apply_changes())
	fbtn.add_child(apply_button)


# ==========================================================================
# Lista de opciones
# ==========================================================================
func _rebuild_options() -> void:
	if options_box == null:
		return
	_rebuilding = true
	Kit.clear(options_box)
	for d in [option_rows, value_buttons, fps_labels, hint_labels, pending_dots, sliders, slider_labels, mute_buttons, key_buttons, info_labels]:
		(d as Dictionary).clear()
	var last_group := ""
	for opt in settings.visible_options(category):
		var group := str(opt.get("group", ""))
		if group != "" and group != last_group:
			var gl := Kit.caps(group)
			gl.name = "Group_" + group
			options_box.add_child(gl)
			last_group = group
		options_box.add_child(_option_row(opt))
	_rebuilding = false


func _option_row(opt: Dictionary) -> PanelContainer:
	var key := str(opt["key"])
	var typ := str(opt.get("type", ""))
	var row := SK.sub("Row_" + key, 14, 0)
	row.custom_minimum_size = Vector2(0, T.SETTINGS_ROW_HEIGHT)
	var h := SK.hbox("H", 12)
	row.add_child(h)
	var tv := SK.vbox("Text", 0)
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(tv)
	var th := SK.hbox("TitleRow", 6)
	tv.add_child(th)
	var title := Kit.label(str(opt.get("label", key)), 15, T.TEXT, "semibold")
	title.name = "Title"
	th.add_child(title)
	var dot := SK.Shape.new("circle", T.ACCENT_DEFAULT, 6.0)
	dot.name = "PendingDot"
	dot.visible = false
	th.add_child(dot)
	pending_dots[key] = dot
	var hint := Kit.label(str(opt.get("hint", "")), 12, T.TEXT_SECONDARY)
	hint.name = "Hint"
	hint.visible = str(opt.get("hint", "")) != "" or typ == S.TYPE_KEY
	tv.add_child(hint)
	hint_labels[key] = hint
	var fps := Kit.label("", 12, T.SETTINGS_IDLE, "bold")
	fps.name = "Fps"
	fps.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(fps)
	fps_labels[key] = fps
	match typ:
		S.TYPE_SLIDER:
			var s := HSlider.new()
			s.name = "Slider"
			s.min_value = float(opt.get("min", 0))
			s.max_value = float(opt.get("max", 100))
			s.step = float(opt.get("step", 1))
			s.custom_minimum_size = Vector2(180, 16)
			s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			SK.style_slider(s)
			SK.a11y_name(s, str(opt.get("label", key)))
			s.set_value_no_signal(float(settings.get_value(category, key)))
			var cat := category
			s.value_changed.connect(func(val: float) -> void: choose(cat, key, val))
			h.add_child(s)
			sliders[key] = s
			var pl := Kit.label("", 14, T.TEXT_SECONDARY)
			pl.name = "Percent"
			pl.custom_minimum_size.x = 46
			pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			pl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			h.add_child(pl)
			slider_labels[key] = pl
			var bus := str(opt.get("bus", ""))
			if bus != "":
				var mb := SK.chip_button("Mute", "Silenciar", 30, 12)
				mb.custom_minimum_size.x = 86
				mb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				SK.a11y_name(mb, "Silenciar " + str(opt.get("label", bus)))
				mb.pressed.connect(func() -> void: settings.toggle_bus_mute(bus))
				h.add_child(mb)
				mute_buttons[bus] = mb
		S.TYPE_KEY:
			var kb := Button.new()
			kb.name = "Key"
			kb.focus_mode = Control.FOCUS_ALL
			kb.custom_minimum_size = Vector2(96, 32)
			kb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			kb.add_theme_font_override("font", T.font("bold"))
			kb.add_theme_font_size_override("font_size", 14)
			SK.a11y_name(kb, "Tecla de " + str(opt.get("label", key)))
			kb.pressed.connect(func() -> void: start_rebind(key))
			h.add_child(kb)
			key_buttons[key] = kb
		S.TYPE_INFO:
			var il := Kit.label("", 14, sem("good"), "semibold")
			il.name = "Info"
			il.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			h.add_child(il)
			info_labels[key] = il
		_:
			var vb := Button.new()
			vb.name = "Value"
			vb.focus_mode = Control.FOCUS_ALL
			vb.custom_minimum_size = Vector2(T.SETTINGS_VALUE_WIDTH, 32)
			vb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			_field_style(vb, false)
			var vh := SK.hbox("Row", 4)
			vh.mouse_filter = Control.MOUSE_FILTER_IGNORE
			vh.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			vh.offset_left = 10
			vh.offset_right = -10
			vb.add_child(vh)
			var vl := Kit.label("", 14, T.TEXT)
			vl.name = "Text"
			vl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			vl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			vl.clip_text = true
			vh.add_child(vl)
			var ch := Kit.label("▾", 14, T.SETTINGS_CHEVRON)
			ch.name = "Chevron"
			ch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			vh.add_child(ch)
			SK.a11y_name(vb, str(opt.get("label", key)))
			var cat2 := category
			vb.pressed.connect(func() -> void: _open_choices(cat2, key, vb))
			h.add_child(vb)
			value_buttons[key] = vb
	option_rows[key] = row
	return row


func _field_style(b: Button, warn: bool) -> void:
	var edge := T.SETTINGS_WARN if warn else T.SETTINGS_FIELD_EDGE
	var sb := Kit.box(T.SETTINGS_FIELD_BG, 8, 1.5 if warn else 1.0, edge)
	var hover := Kit.box(T.SETTINGS_FIELD_BG.lightened(0.05), 8, 1.5 if warn else 1.0, Color(1, 1, 1, 0.2) if not warn else edge)
	for st in ["normal", "disabled"]:
		b.add_theme_stylebox_override(st, sb)
	for st in ["hover", "pressed", "hover_pressed"]:
		b.add_theme_stylebox_override(st, hover)
	b.add_theme_stylebox_override("focus", Kit.box(Color.TRANSPARENT, 8, 1, T.ACCENT_DEFAULT))
	for s in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(s, T.TEXT)


func _open_choices(cat: String, key: String, anchor: Control) -> void:
	if settings.is_locked(cat, key):
		return
	_popup.clear()
	_popup_key = cat + "/" + key
	var vals: Array = settings.choice_values(cat, key)
	for i in vals.size():
		var label: String = settings.choice_label(cat, key, vals[i])
		var fx: String = settings.fps_impact_text(cat, key, vals[i])
		_popup.add_radio_check_item(label + ("   " + fx if fx != "" else ""), i)
		_popup.set_item_checked(i, S._eq(vals[i], settings.get_value(cat, key)))
	if anchor.is_inside_tree():
		_popup.popup(Rect2i(Vector2i(anchor.get_screen_position() + Vector2(0, anchor.size.y * stage_scale)), Vector2i.ZERO))


func _on_popup_id(idx: int) -> void:
	var parts := _popup_key.split("/")
	if parts.size() != 2:
		return
	var vals: Array = settings.choice_values(parts[0], parts[1])
	if idx >= 0 and idx < vals.size():
		choose(parts[0], parts[1], vals[idx])


# ==========================================================================
# Refresco
# ==========================================================================
func refresh() -> void:
	if not _built or settings == null:
		return
	_refresh_left()
	_refresh_center()
	_refresh_right()
	super.refresh()


func _refresh_left() -> void:
	search_summary_label.text = settings.search_summary(search_text)
	search_summary_label.visible = search_summary_label.text != ""
	var focus_edge := search_text != "" or (search_edit.is_inside_tree() and search_edit.has_focus())
	var sb := Kit.box(T.SETTINGS_FIELD_BG, 10, 1.5 if focus_edge else 1.0, T.ACCENT_DEFAULT if focus_edge else T.SETTINGS_FIELD_EDGE)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	search_edit.add_theme_stylebox_override("normal", sb)
	search_edit.add_theme_stylebox_override("focus", sb)
	for id in category_buttons:
		var b: Button = category_buttons[id]
		var on: bool = id == category
		var bg := T.SETTINGS_ACTIVE_BG if on else Color(0, 0, 0, 0)
		b.add_theme_stylebox_override("normal", Kit.box(bg, 10))
		b.add_theme_stylebox_override("hover", Kit.box(T.SETTINGS_ACTIVE_BG if on else Color(1, 1, 1, 0.04), 10))
		b.add_theme_stylebox_override("pressed", Kit.box(T.SETTINGS_ACTIVE_BG, 10))
		b.add_theme_stylebox_override("focus", Kit.box(Color.TRANSPARENT, 10, 1, Color(T.ACCENT_DEFAULT, 0.6)))
		var l := b.get_node("Row/Label") as Label
		l.add_theme_color_override("font_color", T.TEXT if on else T.TEXT_KEY)
		var w: SK.Shape = category_warnings[id]
		w.visible = settings.category_has_warning(id)
		w.color = sem("warn")
		w.kind = settings.shape_for("warn") if settings.shape_for("warn") != "" else "circle"
		b.set_meta("selected", on)


func _refresh_center() -> void:
	category_title.text = settings.category_label(category)
	preset_bar.visible = category == S.CAT_GRAPHICS
	var cur: String = settings.current_preset()
	for id in preset_buttons:
		SK.set_segment_active(preset_buttons[id], id == cur)
	var hits: Array[String] = settings.search_hits(search_text, category)
	for key in option_rows:
		var opt: Dictionary = settings.get_option(category, key)
		var row: PanelContainer = option_rows[key]
		var hit := hits.has(key)
		var conflict := false
		if category == S.CAT_CONTROLS:
			conflict = settings.actions_for_key(settings.get_binding(key)).size() > 1
		var edge := T.ACCENT_DEFAULT if hit else (sem("warn") if conflict else Color.TRANSPARENT)
		row.add_theme_stylebox_override("panel", _row_box(edge, 1.5 if (hit or conflict) else 0.0))
		row.set_meta("search_hit", hit)
		row.set_meta("conflict", conflict)
		var hint: Label = hint_labels[key]
		var lock: String = settings.lock_reason(category, key)
		if hit:
			hint.text = "Coincide con tu búsqueda"
		elif settings.rebinding_action == key:
			hint.text = "Pulsa una tecla… (Esc cancela)"
		elif conflict:
			hint.text = "Comparte tecla con otra acción"
		elif lock != "" and lock != "Solo lectura" and lock != "Reservada":
			hint.text = lock
		else:
			hint.text = str(opt.get("hint", "")) if category != S.CAT_CONTROLS else str(opt.get("group", ""))
		(pending_dots[key] as SK.Shape).visible = settings.has_pending(category, key)
		var fl: Label = fps_labels[key]
		fl.text = settings.fps_impact_text(category, key)
		fl.add_theme_color_override("font_color", sem_hex(settings.fps_impact_color(category, key)))
		if value_buttons.has(key):
			var vb: Button = value_buttons[key]
			(vb.get_node("Row/Text") as Label).text = settings.choice_label(category, key)
			vb.disabled = lock != ""
			(vb.get_node("Row/Chevron") as Label).visible = lock == ""
		if sliders.has(key):
			var s: HSlider = sliders[key]
			s.set_value_no_signal(float(settings.get_value(category, key)))
			(slider_labels[key] as Label).text = settings.choice_label(category, key)
			var bus := str(opt.get("bus", ""))
			if mute_buttons.has(bus):
				var muted: bool = settings.bus_muted(bus)
				var mb: Button = mute_buttons[bus]
				mb.text = "Silenciado" if muted else "Silenciar"
				SK.set_chip_active(mb, muted)
				s.modulate.a = 0.45 if muted else 1.0
		if key_buttons.has(key):
			var kb: Button = key_buttons[key]
			kb.text = "…" if settings.rebinding_action == key else settings.get_binding(key)
			_field_style(kb, conflict)
			kb.disabled = bool(opt.get("locked", false))
		if info_labels.has(key):
			var il: Label = info_labels[key]
			il.text = settings.choice_label(category, key)
			il.add_theme_color_override("font_color", sem("good") if str(settings.get_value(category, key)) == "active" else T.TEXT_SECONDARY)


func _row_box(edge: Color, w: float) -> StyleBoxFlat:
	var sb := Kit.box(T.SETTINGS_SUB_BG, 12, w, edge)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	return sb


func _refresh_right() -> void:
	var perf: Array = settings.estimated_performance()
	for i in mini(perf.size(), perf_rows.size()):
		var p: Dictionary = perf[i]
		var r: Dictionary = perf_rows[i]
		var col := sem_hex(str(p["color"]))
		(r["name"] as Label).text = str(p["label"])
		(r["fps"] as Label).text = "%d fps" % int(p["fps"])
		(r["fps"] as Label).add_theme_color_override("font_color", col)
		(r["meter"] as SK.Meter).ratio = float(p["ratio"])
		(r["meter"] as SK.Meter).color = col
		var shp: SK.Shape = r["shape"]
		var kind := kind_of_hex(str(p["color"]))
		var sh: String = settings.shape_for(kind) if not bool(p["capped"]) else ""
		shp.visible = sh != ""
		shp.kind = sh if sh != "" else "circle"
		shp.color = col
		(r["row"] as Control).set_meta("fps", int(p["fps"]))
	var conflicts: Array = settings.find_conflicts()
	conflict_card.visible = not conflicts.is_empty()
	if not conflicts.is_empty():
		var c: Dictionary = conflicts[0]
		var msg: String = settings.conflict_message(c)
		(conflict_key.get_node("Key") as Label).text = str(c["key"])
		conflict_label.text = msg.substr(str(c["key"]).length()).strip_edges()
		var s: Dictionary = settings.suggest_resolution(c)
		quick_fix_button.text = str(s.get("label", "Resolver"))
		quick_fix_button.disabled = s.is_empty()
		conflict_card.add_theme_stylebox_override("panel", _sub_edge(sem("warn")))
		(conflict_card.get_node("Body/Title") as Label).add_theme_color_override("font_color", sem("warn"))
	confirm_card.visible = settings.confirm_active
	confirm_label.text = "Se revierten solos en %d s" % int(ceil(settings.confirm_remaining))
	var n: int = settings.pending_count()
	if n == 0:
		pending_label.text = "Sin cambios pendientes"
	else:
		var rest: String = settings.pending_summary().substr(str(n).length())
		pending_label.text = "[b][color=#eef2f4]%d[/color][/b]%s" % [n, rest]
	undo_button.disabled = n == 0
	apply_button.disabled = n == 0


func _sub_edge(edge: Color) -> StyleBoxFlat:
	var sb := Kit.box(T.SETTINGS_SUB_BG, 12, 1.5, edge)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	return sb
