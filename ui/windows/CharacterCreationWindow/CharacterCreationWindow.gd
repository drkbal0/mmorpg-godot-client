extends "res://ui/windows/common/EntryWindow.gd"
## Creación de personaje en 4 pasos — UI v2.4 Paso 15 (design_ref/pantallas_html/MMO-Creacion.html).
##
## - Velo rgba(5,8,10,0.78). Barra superior de pasos 1-4 (Origen · Clase · Apariencia · Nombre):
##   círculo activo #46e3c1 con aro de 1,5 px, completado #4fe39a con «✓», pendiente #26333b.
##   Los pasos ya visitados se pueden pulsar.
## - Izquierda (360 px): «Origen: Verdalia · cambiar» (desplegable) y el contenido del paso:
##   orígenes con afinidad elemental (Anexo B) · cuadrícula de clases (rol, alcance/estilo,
##   «Recomendada para empezar») · controles de apariencia chibi · nombre con validación en vivo
##   y rasgo cósmico inicial.
## - Centro: silueta con pedestal del color del origen y tarjeta «Así se verá en tu refugio».
## - Derecha (360 px): detalle del paso (clase: puntuaciones de 5 segmentos, vídeo y
##   «Probar en el maniquí (5 min)»).
## - Pie: «Atrás», «Probar la clase» y el principal («Siguiente: …» / «Confirmar creación»).
##
## Teclado: Enter avanza/confirma · Esc vuelve atrás (en el paso 1 vuelve a la selección).

signal creation_confirmed(character: Dictionary)
signal creation_cancelled
signal trial_requested(info: Dictionary)

var steps_row: HBoxContainer
var step_pills: Array[Button] = []
var origin_chip: PanelContainer
var origin_dot: EK.Dot
var origin_label: Label
var origin_selector: OptionButton
var step_caps: Label
var content_box: VBoxContainer
var preview: EK.Silhouette
var chibi_card: PanelContainer
var chibi: EK.Chibi
var detail_card: PanelContainer
var back_button: Button
var try_button: Button
var next_button: Button
var error_label: Label
var name_input: LineEdit
var name_status: Label
var suggestion_button: Button
var last_confirm: Dictionary = {}

var _syncing := false


func _screen_id() -> String:
	return "character_create"


func _screen() -> String:
	return AuthScript.SCREEN_CREATE


func _veil_base() -> float:
	return T.CREATE_VEIL.a


func _screen_title() -> String:
	return "Creación de personaje. Paso %d de 4: %s" % [service.creation_step + 1, AuthScript.STEP_LABELS[service.creation_step]]


func _service_signals() -> Array:
	return ["creation_changed"]


## params: {"keep_current": true} conserva el borrador (lo abre la selección tras begin_creation).
func initialize_window(params: Dictionary) -> void:
	if service == null:
		_resolve_service()
	if not bool(params.get("keep_current", false)) and service.flow_screen != AuthScript.SCREEN_CREATE:
		service.begin_creation()
	super.initialize_window(params)


# ==========================================================================
# API
# ==========================================================================
func choose_origin(id: String) -> bool:
	return service.set_origin(id)


func choose_class(id: String) -> bool:
	return service.set_class(id)


func choose_trait(id: String) -> bool:
	return service.set_trait(id)


func type_name(text: String) -> Dictionary:
	if name_input != null and name_input.text != text:
		name_input.text = text
	return service.set_draft_name(text)


func cycle_appearance(key: String, step: int) -> int:
	return service.cycle_appearance(key, step)


func try_class() -> Dictionary:
	var r: Dictionary = service.try_dummy()
	if r.get("ok", false):
		trial_requested.emit(r)
	else:
		_show_error(str(r.get("message", "")))
	return r


func primary_action() -> Dictionary:
	if service.creation_step < AuthScript.STEP_LABELS.size() - 1:
		var ok: bool = service.next_step()
		if not ok:
			_show_error(_step_hint())
		return {"ok": ok, "step": service.creation_step}
	return confirm()


func confirm() -> Dictionary:
	last_confirm = service.confirm_creation()
	if last_confirm.get("ok", false):
		creation_confirmed.emit(last_confirm["character"])
		navigate("character_select")
	else:
		_show_error(str(last_confirm.get("message", "")))
	return last_confirm


func back() -> void:
	if service.creation_step == 0:
		service.cancel_creation()
		creation_cancelled.emit()
		navigate("character_select")
	else:
		service.prev_step()


func go_to_step(i: int) -> bool:
	return service.goto_step(i)


func _step_hint() -> String:
	match service.creation_step:
		0:
			return "Elige un origen"
		1:
			return "Elige una clase"
		3:
			var v: Dictionary = service.validate_name(str(service.draft["name"]))
			return str(v["message"]) if not v["ok"] else "Elige un rasgo cósmico"
	return ""


func _show_error(msg: String) -> void:
	error_label.text = msg
	error_label.visible = msg != ""


func _handle_key(code: int, _ev: InputEventKey) -> bool:
	match code:
		KEY_ENTER, KEY_KP_ENTER:
			primary_action()
			return true
		KEY_ESCAPE:
			back()
			return true
	return false


# ==========================================================================
# Construcción
# ==========================================================================
func _build() -> void:
	steps_row = EK.hbox("Steps", 10)
	steps_row.alignment = BoxContainer.ALIGNMENT_CENTER
	place(steps_row, 0, 24, 0)
	step_pills.clear()
	for i in AuthScript.STEP_LABELS.size():
		var b := Button.new()
		b.name = "Step%d" % (i + 1)
		b.focus_mode = Control.FOCUS_ALL
		b.custom_minimum_size = Vector2(0, T.CREATE_STEP_HEIGHT)
		var idx := i
		b.pressed.connect(func() -> void: go_to_step(idx))
		var h := EK.hbox("Content", 8)
		h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		h.offset_left = 14
		h.offset_right = -14
		b.add_child(h)
		var circ := Kit.panel("Circle", Kit.box(T.ENTRY_STEP_PENDING, 10), 0, 0)
		circ.custom_minimum_size = Vector2(20, 20)
		circ.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var cl := Kit.label(str(i + 1), 12, T.TEXT_SECONDARY, "bold")
		cl.name = "Num"
		cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		circ.add_child(cl)
		h.add_child(circ)
		var l := Kit.label(AuthScript.STEP_LABELS[i], 14, T.TEXT_SECONDARY, "semibold")
		l.name = "Label"
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(l)
		b.custom_minimum_size.x = 14 + 20 + 8 + 14 + 8.0 * AuthScript.STEP_LABELS[i].length()
		steps_row.add_child(b)
		step_pills.append(b)

	var left := EK.vbox("Left", 10)
	place(left, 30, 90, -1, -1, T.CREATE_COLUMN_WIDTH)
	origin_chip = Kit.panel("OriginChip", Kit.box(Color(18 / 255.0, 26 / 255.0, 32 / 255.0, 0.92), 12), 12, 6)
	origin_chip.mouse_filter = Control.MOUSE_FILTER_PASS
	left.add_child(origin_chip)
	var oh := EK.hbox("Row", 10)
	origin_chip.add_child(oh)
	origin_dot = EK.Dot.new(Color.WHITE, 10.0)
	origin_dot.name = "Dot"
	origin_dot.custom_minimum_size = Vector2(10, 24)
	origin_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	oh.add_child(origin_dot)
	origin_label = Kit.label("", 14, T.TEXT)
	origin_label.name = "Text"
	origin_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	oh.add_child(origin_label)
	oh.add_child(EK.spacer())
	origin_selector = OptionButton.new()
	origin_selector.name = "OriginSelector"
	origin_selector.flat = true
	origin_selector.fit_to_longest_item = false
	origin_selector.focus_mode = Control.FOCUS_ALL
	origin_selector.add_theme_font_size_override("font_size", 12)
	for fc in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		origin_selector.add_theme_color_override(fc, T.ACCENT_DEFAULT)
	for o in service.origins:
		origin_selector.add_item(str(o["name"]))
	origin_selector.item_selected.connect(func(i: int) -> void:
		if not _syncing:
			choose_origin(str(service.origins[i]["id"])))
	origin_selector.tooltip_text = "Cambiar origen"
	oh.add_child(origin_selector)
	step_caps = Kit.shadow(Kit.caps("", T.TEXT_KEY))
	step_caps.name = "StepCaps"
	left.add_child(step_caps)
	content_box = EK.vbox("Content", 8)
	left.add_child(content_box)

	preview = EK.Silhouette.new(280, 490, 340)
	preview.name = "Preview"
	place(preview, 470, 100, -1, -1, 500)
	preview.custom_minimum_size = Vector2(500, 600)

	chibi_card = EK.card("ChibiCard", 10)
	place(chibi_card, 880, 600, -1, -1, 150)
	var cv := EK.vbox("Body", 4)
	cv.alignment = BoxContainer.ALIGNMENT_CENTER
	chibi_card.add_child(cv)
	chibi = EK.Chibi.new()
	chibi.name = "Chibi"
	cv.add_child(chibi)
	var ct := Kit.label("Así se verá en tu refugio", 11, T.TEXT_SECONDARY)
	ct.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ct.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cv.add_child(ct)

	detail_card = EK.card("Detail", 20)
	place(detail_card, -1, 90, 30, -1, T.CREATE_COLUMN_WIDTH)
	detail_card.add_child(EK.vbox("Body", 12))

	var actions := EK.hbox("Actions", 10)
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	place(actions, 0, -1, 0, 30)
	back_button = EK.button("Back", "Atrás", T.CREATE_ACTION_HEIGHT, 14, 22)
	back_button.pressed.connect(back)
	actions.add_child(back_button)
	try_button = EK.button("TryClass", "Probar la clase", T.CREATE_ACTION_HEIGHT, 14, 22)
	try_button.pressed.connect(func() -> void: try_class())
	actions.add_child(try_button)
	next_button = EK.button("Next", "", T.CREATE_ACTION_HEIGHT, 14, 28)
	EK.primary(next_button, 10, 28)
	next_button.pressed.connect(func() -> void: primary_action())
	actions.add_child(next_button)
	error_label = Kit.shadow(Kit.label("", 13, Color("#ff8a8a"), "semibold"))
	error_label.name = "Error"
	error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	error_label.visible = false
	place(error_label, 0, -1, 0, 86)


# ==========================================================================
# Refresco
# ==========================================================================
func refresh() -> void:
	if not _built or service == null:
		return
	var step: int = service.creation_step
	var states: Array = service.step_states()
	for i in step_pills.size():
		_style_step(step_pills[i], str(states[i]["state"]), i)
	var o: Dictionary = service.origin(str(service.draft["origin"]))
	origin_dot.color = Color(str(o.get("color", "#9aa6ae")))
	origin_label.text = "Origen: %s" % o.get("name", "—")
	_syncing = true
	origin_selector.select(service.origins.find(o))
	origin_selector.text = "cambiar"
	_syncing = false
	step_caps.text = ["Elige tu origen", "Elige tu clase", "Elige tu apariencia", "Nombre y rasgo cósmico"][step].to_upper()
	var keep_focus := name_input != null and name_input.has_focus()
	Kit.clear(content_box)
	name_input = null
	name_status = null
	suggestion_button = null
	match step:
		0:
			_build_origins()
		1:
			_build_classes()
		2:
			_build_appearance()
		3:
			_build_name(keep_focus)
	_refresh_preview(o)
	_refresh_detail(step, o)
	back_button.text = "Atrás" if step > 0 else "Volver a la selección"
	try_button.visible = step == 1
	try_button.text = service.trial_button_text() if service.trial_active else "Probar la clase"
	try_button.disabled = str(service.draft["class_id"]) == ""
	next_button.text = service.primary_action_label()
	next_button.disabled = not service.can_advance()
	error_label.visible = false
	apply_accessibility()


func _style_step(b: Button, state: String, i: int) -> void:
	b.set_meta("state", state)
	var alpha := {"done": 0.9, "active": 0.95, "pending": 0.7}[state] as float
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb := Kit.box(Color(13 / 255.0, 18 / 255.0, 22 / 255.0, alpha), 18, 1.5 if state == "active" else 0.0, T.ENTRY_STEP_ACTIVE)
		if st == "focus":
			sb = Kit.box(Color.TRANSPARENT, 18, 2, T.ACCENT_DEFAULT)
		b.add_theme_stylebox_override(st, sb)
	var circ := b.find_child("Circle", true, false) as PanelContainer
	var num := circ.get_node("Num") as Label
	var lab := b.find_child("Label", true, false) as Label
	match state:
		"done":
			circ.add_theme_stylebox_override("panel", Kit.box(T.ENTRY_STEP_DONE, 10))
			num.text = "✓"
			num.add_theme_color_override("font_color", T.ENTRY_PRIMARY_TEXT)
			lab.add_theme_color_override("font_color", T.TEXT_SECONDARY)
		"active":
			circ.add_theme_stylebox_override("panel", Kit.box(T.ENTRY_STEP_ACTIVE, 10))
			num.text = str(i + 1)
			num.add_theme_color_override("font_color", T.ENTRY_PRIMARY_TEXT)
			lab.add_theme_color_override("font_color", T.TEXT)
		_:
			circ.add_theme_stylebox_override("panel", Kit.box(T.ENTRY_STEP_PENDING, 10))
			num.text = str(i + 1)
			num.add_theme_color_override("font_color", T.TEXT_SECONDARY)
			lab.add_theme_color_override("font_color", T.TEXT_MUTED)
	b.disabled = state == "pending"


func _grid() -> GridContainer:
	var g := GridContainer.new()
	g.name = "Grid"
	g.columns = 2
	g.add_theme_constant_override("h_separation", 8)
	g.add_theme_constant_override("v_separation", 8)
	content_box.add_child(g)
	return g


func _select_card(node_name: String, selected: bool, on_click: Callable) -> PanelContainer:
	var sb := Kit.box(T.ENTRY_CARD_BG, 18, 2.0 if selected else 1.0, T.ENTRY_SELECTED if selected else T.ENTRY_CARD_EDGE)
	var card := Kit.panel(node_name, sb, 12)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.set_meta("selected", selected)
	card.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			on_click.call())
	var v := EK.vbox("Body", 5)
	card.add_child(v)
	return card


func _badge(text: String, bg: Color) -> PanelContainer:
	var p := Kit.panel("Badge", Kit.box(bg, 5), 6, 0)
	p.custom_minimum_size.y = 18
	var l := Kit.label(text, 11, T.TEXT, "bold")
	l.name = "Text"
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p


func _build_origins() -> void:
	var g := _grid()
	for o in service.origins:
		var id := str(o["id"])
		var card := _select_card("Origin_%s" % id, id == str(service.draft["origin"]), func() -> void: choose_origin(id))
		var v: VBoxContainer = card.get_node("Body")
		var h := EK.hbox("Head", 8)
		v.add_child(h)
		var d := EK.Dot.new(Color(str(o["color"])), 10.0)
		d.custom_minimum_size = Vector2(10, 20)
		h.add_child(d)
		var n := Kit.label(str(o["name"]), 15, T.TEXT, "bold")
		n.name = "Name"
		h.add_child(n)
		var r := EK.hbox("Affinity", 6)
		v.add_child(r)
		var b := _badge(str(o["energy"]), Color(Color(str(o["energy_color"])), 0.28))
		b.name = "Energy"
		r.add_child(b)
		var t := Kit.label("afinidad primaria", 11, T.TEXT_SECONDARY)
		r.add_child(t)
		g.add_child(card)


func _build_classes() -> void:
	var g := _grid()
	for c in service.classes:
		var id := str(c["id"])
		var card := _select_card("Class_%s" % id, id == str(service.draft["class_id"]), func() -> void: choose_class(id))
		card.set_meta("role", c["role"])
		var v: VBoxContainer = card.get_node("Body")
		var n := Kit.label(str(c["name"]), 15, T.TEXT, "bold")
		n.name = "Name"
		v.add_child(n)
		var r := EK.hbox("Role", 6)
		v.add_child(r)
		var b := _badge(service.role_label(str(c["role"])), Color(service.role_color(str(c["role"]))))
		b.name = "RoleBadge"
		r.add_child(b)
		var st := Kit.label(str(c["style"]), 11, T.TEXT_SECONDARY)
		st.name = "Style"
		r.add_child(st)
		if bool(c.get("recommended", false)):
			var rec := Kit.label("Recomendada para empezar", 11, T.ACCENT_DEFAULT)
			rec.name = "Recommended"
			v.add_child(rec)
		g.add_child(card)


func _build_appearance() -> void:
	for k in AuthScript.APPEARANCE_KEYS:
		var key: String = k
		var row := Kit.panel("Appearance_%s" % key, Kit.box(Color(T.ENTRY_SUB_BG, 0.92), 12), 10, 6)
		var h := EK.hbox("Row", 8)
		row.add_child(h)
		var l := Kit.label(service.appearance_label(key), 13, T.TEXT_SECONDARY)
		l.custom_minimum_size.x = 110
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(l)
		var prev := EK.button("Prev", "‹", 30, 16, 10)
		prev.pressed.connect(func() -> void: cycle_appearance(key, -1))
		h.add_child(prev)
		var opt: Dictionary = service.appearance_option(key)
		var vh := EK.hbox("Value", 6)
		vh.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vh.alignment = BoxContainer.ALIGNMENT_CENTER
		h.add_child(vh)
		if str(opt.get("color", "")) != "":
			var sw := EK.Dot.new(Color(str(opt["color"])), 12.0)
			sw.custom_minimum_size = Vector2(12, 22)
			vh.add_child(sw)
		var val := Kit.label(str(opt.get("name", "")), 14, T.TEXT, "semibold")
		val.name = "Text"
		val.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		vh.add_child(val)
		var next := EK.button("Next", "›", 30, 16, 10)
		next.pressed.connect(func() -> void: cycle_appearance(key, 1))
		h.add_child(next)
		content_box.add_child(row)
	var rnd := EK.button("Randomize", "Aleatorio", 34)
	rnd.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	rnd.pressed.connect(func() -> void: service.randomize_appearance())
	content_box.add_child(rnd)


func _build_name(keep_focus: bool) -> void:
	name_input = LineEdit.new()
	name_input.name = "NameInput"
	name_input.placeholder_text = "Nombre (3-16 letras o números)"
	name_input.max_length = 24
	name_input.custom_minimum_size = Vector2(0, 46)
	name_input.add_theme_font_override("font", T.font("semibold"))
	name_input.add_theme_font_size_override("font_size", 18)
	name_input.add_theme_color_override("font_color", T.TEXT)
	name_input.add_theme_color_override("font_placeholder_color", T.TEXT_MUTED)
	var sb := Kit.box(T.ENTRY_SUB_BG, 12, 1, Color(1, 1, 1, 0.1))
	sb.content_margin_left = 14
	name_input.add_theme_stylebox_override("normal", sb)
	var fsb := Kit.box(T.ENTRY_SUB_BG, 12, 2, T.ACCENT_DEFAULT)
	fsb.content_margin_left = 14
	name_input.add_theme_stylebox_override("focus", fsb)
	name_input.text = str(service.draft["name"])
	name_input.text_changed.connect(_on_name_changed)
	name_input.text_submitted.connect(func(_t: String) -> void: primary_action())
	content_box.add_child(name_input)
	name_status = Kit.shadow(Kit.label("", 13, T.TEXT_SECONDARY, "semibold"))
	name_status.name = "NameStatus"
	content_box.add_child(name_status)
	suggestion_button = EK.link("Suggestion", "", 13)
	suggestion_button.pressed.connect(func() -> void:
		var s: String = service.suggest_name(str(service.draft["name"]))
		if s != "":
			type_name(s))
	content_box.add_child(suggestion_button)
	_update_name_status()
	content_box.add_child(Kit.shadow(Kit.caps("Rasgo cósmico inicial", T.TEXT_KEY)))
	for t in service.traits:
		var id := str(t["id"])
		var card := _select_card("Trait_%s" % id, id == str(service.draft["trait_id"]), func() -> void: choose_trait(id))
		var v: VBoxContainer = card.get_node("Body")
		var h := EK.hbox("Head", 8)
		v.add_child(h)
		var d := EK.Dot.new(Color(str(t["color"])), 9.0, true)
		d.custom_minimum_size = Vector2(10, 20)
		h.add_child(d)
		var n := Kit.label(str(t["name"]), 14, T.TEXT, "bold")
		n.name = "Name"
		h.add_child(n)
		var e := Kit.label(str(t["energy"]), 11, Color(str(t["color"])))
		h.add_child(e)
		var tx := Kit.label(str(t["text"]), 12, T.TEXT_SECONDARY)
		tx.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(tx)
		content_box.add_child(card)
	if keep_focus and name_input.is_inside_tree():
		name_input.grab_focus()
		name_input.caret_column = name_input.text.length()


func _on_name_changed(text: String) -> void:
	# Validación en vivo sin reconstruir el formulario (no se pierde el foco).
	service.draft["name"] = text
	_update_name_status()
	next_button.disabled = not service.can_advance()
	_refresh_detail(service.creation_step, service.origin(str(service.draft["origin"])))
	apply_accessibility()


func _update_name_status() -> void:
	if name_status == null:
		return
	var v: Dictionary = service.validate_name(str(service.draft["name"]))
	name_status.text = str(v["message"])
	name_status.set_meta("code", v["code"])
	var col := Color(service.status_color("good")) if v["ok"] else (T.TEXT_SECONDARY if v["code"] == "empty" else Color(service.status_color("bad")))
	name_status.add_theme_color_override("font_color", col)
	var sug := ""
	if v["code"] == "taken":
		sug = service.suggest_name(str(v["name"]))
	suggestion_button.text = "Usar «%s»" % sug if sug != "" else ""
	suggestion_button.visible = sug != ""


func _refresh_preview(o: Dictionary) -> void:
	var col: Dictionary = service.appearance_colors()
	var ring := Color(str(o.get("color", "#46e3c1")))
	preview.ring = ring
	preview.accent_body = Color(str(col["body"])) if service.creation_step >= 1 and str(service.draft["class_id"]) != "" else Color(0, 0, 0, 0)
	chibi.body = Color(str(col["body"]))
	chibi.hair = Color(str(col["hair"]))
	chibi.eyes = Color(str(col["eyes"]))
	chibi.hair_style = int(col["hair_style"])
	chibi.body_scale = float(col["scale"])
	chibi.shadow = Color(ring, 0.5)


func _rating_row(label: String, value: int) -> HBoxContainer:
	var h := EK.hbox("Rating", 10)
	var l := Kit.label(label, 13, T.TEXT_SECONDARY)
	l.custom_minimum_size.x = 100
	h.add_child(l)
	var s := EK.Segments.new(value)
	s.name = "Segments"
	h.add_child(s)
	h.set_meta("value", value)
	return h


func _refresh_detail(step: int, o: Dictionary) -> void:
	var v: VBoxContainer = detail_card.get_node("Body")
	Kit.clear(v)
	detail_card.set_meta("step", step)
	match step:
		0:
			v.add_child(_title(str(o.get("name", ""))))
			v.add_child(_para(str(o.get("text", ""))))
			var aff := Kit.panel("Affinity", Kit.box(T.ENTRY_SUB_BG, 12, 1, Color(Color(str(o.get("energy_color", "#46e3c1"))), 0.4)), 12, 10)
			var av := EK.vbox("Body", 4)
			aff.add_child(av)
			av.add_child(Kit.caps("Afinidad elemental primaria"))
			var eh := EK.hbox("Energy", 8)
			av.add_child(eh)
			var d := EK.Dot.new(Color(str(o.get("energy_color", "#46e3c1"))), 10.0)
			d.custom_minimum_size = Vector2(10, 22)
			eh.add_child(d)
			var en := Kit.label(str(o.get("energy", "")), 18, Color(str(o.get("energy_color", "#46e3c1"))), "bold")
			en.name = "EnergyName"
			eh.add_child(en)
			av.add_child(_para("Tu primera energía en el Crisol. La afinidad sube usándola.", 13))
			v.add_child(aff)
		1:
			var c: Dictionary = service.class_data(str(service.draft["class_id"]))
			if c.is_empty():
				v.add_child(_title("Elige una clase"))
				v.add_child(_para("Cada clase tiene un rol, un alcance y un estilo. Puedes probarla en el maniquí antes de crearla."))
				var rid: String = service.recommended_class_id()
				if rid != "":
					v.add_child(_para("Recomendada para empezar: %s" % service.class_data(rid).get("name", ""), 13, T.ACCENT_DEFAULT))
				return
			v.add_child(_title(str(c["name"])))
			v.add_child(_para(str(c["text"])))
			var meta := Kit.label("%s · %s · %s" % [service.role_label(str(c["role"])), c["range"], c["style"]], 13, T.TEXT_KEY, "semibold")
			meta.name = "Meta"
			v.add_child(meta)
			for k in AuthScript.RATING_KEYS:
				var row := _rating_row(AuthScript.RATING_LABELS[k], int((c.get("ratings", {}) as Dictionary).get(k, 0)))
				row.name = "Rating_%s" % k
				v.add_child(row)
			var video := Kit.panel("Video", Kit.box(T.ENTRY_SUB_BG, 12), 0, 0)
			video.custom_minimum_size.y = 150
			var vv := EK.vbox("Body", 6)
			vv.alignment = BoxContainer.ALIGNMENT_CENTER
			video.add_child(vv)
			var play = Kit.Icon.new("M10 8l6 4-6 4z", Vector2(36, 36))
			play.bg = Color(1, 1, 1, 0.1)
			play.radius = 18
			play.icon_size = 22
			play.stroke = T.TEXT
			play.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			vv.add_child(play)
			var vt := Kit.label("Combate de 20 s con esta clase", 12, T.TEXT_SECONDARY)
			vt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			vv.add_child(vt)
			v.add_child(video)
			var note := Kit.panel("TrialNote", Kit.box(T.ENTRY_SUB_BG, 12, 1, Color(70 / 255.0, 227 / 255.0, 193 / 255.0, 0.35)), 12, 10)
			var nv := EK.vbox("Body", 8)
			note.add_child(nv)
			nv.add_child(_para("Puedes jugarla 5 minutos en una arena antes de crearla.", 13, T.TEXT_KEY))
			var tb := EK.button("TryDummy", service.trial_button_text() if service.trial_active else "Probar en el maniquí (5 min)", 34)
			tb.pressed.connect(func() -> void: try_class())
			nv.add_child(tb)
			v.add_child(note)
		2:
			v.add_child(_title("Apariencia"))
			v.add_child(_para("Tu personaje vive en el refugio en versión chibi. Todo es cosmético y se puede cambiar en la barbería."))
			for k in AuthScript.APPEARANCE_KEYS:
				v.add_child(_kv(service.appearance_label(k), str(service.appearance_option(k).get("name", ""))))
		3:
			v.add_child(_title("Resumen"))
			var c: Dictionary = service.class_data(str(service.draft["class_id"]))
			var t: Dictionary = service.trait_data(str(service.draft["trait_id"]))
			var nv: Dictionary = service.validate_name(str(service.draft["name"]))
			v.add_child(_kv("Origen", "%s · %s" % [o.get("name", "—"), o.get("energy", "")]))
			v.add_child(_kv("Clase", str(c.get("name", "—"))))
			v.add_child(_kv("Rol", service.role_label(str(c.get("role", ""))) if not c.is_empty() else "—"))
			v.add_child(_kv("Rasgo", str(t.get("name", "Sin elegir"))))
			v.add_child(_kv("Nombre", str(nv["name"]) if nv["ok"] else "—"))
			v.add_child(_para("Ranuras: %s" % service.free_slots_text(), 13))


func _title(text: String) -> Label:
	var l := Kit.label(text, 24, T.TEXT, "bold")
	l.name = "Title"
	return l


func _para(text: String, font_size: int = 14, color: Color = T.TEXT_KEY) -> Label:
	var l := Kit.label(text, font_size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = T.CREATE_COLUMN_WIDTH - 40
	return l


func _kv(k: String, val: String) -> HBoxContainer:
	var h := EK.hbox("Row", 8)
	var kl := Kit.label(k, 13, T.TEXT_SECONDARY)
	kl.custom_minimum_size.x = 110
	h.add_child(kl)
	var vl := Kit.label(val, 14, T.TEXT, "semibold")
	vl.name = "Value"
	h.add_child(vl)
	return h
