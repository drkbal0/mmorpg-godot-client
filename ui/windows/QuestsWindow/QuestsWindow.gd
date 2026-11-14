extends "res://ui/windows/common/MenuWindow.gd"
## Misiones [L] — UI v2.4 Paso 9 (design_ref/pantallas_html/MMO-Misiones.html).
##
## Izquierda: filtro de estado (Activas · Disponibles · Hechas), filtro de categoría
## (Principales · Secundarias · Diarias · Pionero) y lista agrupada con progreso.
## Centro: detalle (historia, objetivos «3/5», recompensas en oro/PX/objetos) con
## «Seguir en HUD», «Ver en el mapa» (abre `map_window` centrado en el objetivo) y
## «Abandonar»/«Aceptar».
## Derecha: lo que ves en el rastreador del HUD (máx. 3) y el planificador de sesión.
##
## Todo el estado vive en `QuestService`; las misiones de pionero salen de
## `KnowledgeService` (contratos en misión y ofertas pendientes).

const QuestServiceScript = preload("res://shared-core/QuestService.gd")

signal quest_selected(quest_id: String)
signal map_requested(params: Dictionary)
signal tracking_changed(quest_id: String, tracked: bool)

const MENU_TAB_ID := "misiones"
const STATE_FILTERS: Array[Dictionary] = [
	{"id": "active", "label": "Activas"},
	{"id": "available", "label": "Disponibles"},
	{"id": "completed", "label": "Hechas"},
]
const COLOR_XP := Color("#c39bff")

## Servicio inyectable (tests). Si es null se usa /root/QuestService o uno local.
var service: Node = null
var state_filter: String = "active"
var category_filter: String = ""
var selected_id: String = ""

var state_buttons: Dictionary = {}
var category_buttons: Dictionary = {}
var list_box: VBoxContainer
var list_rows: Dictionary = {}       # quest_id -> Button
var detail_box: VBoxContainer
var title_label_big: Label
var step_rows: Array = []            # [{label, count}]
var track_button: Button
var map_button: Button
var abandon_button: Button
var feedback_label: Label
var hud_box: VBoxContainer
var hud_count_label: Label
var plan_box: VBoxContainer
var empty_label: Label

var _built := false
var _refresh_queued := false


func _ready() -> void:
	window_id = "quests_window"
	_resolve_service()
	_resolve_commerce()
	_build()
	super._ready()
	connect_menu_bar()
	refresh()


func initialize_window(params: Dictionary) -> void:
	if params.has("state"):
		set_state_filter(str(params["state"]))
	if params.has("category"):
		set_category_filter(str(params["category"]))
	var qid := str(params.get("quest_id", ""))
	if qid != "" and service and not service.get_quest(qid).is_empty():
		var q: Dictionary = service.get_quest(qid)
		if q["state"] != state_filter:
			set_state_filter(q["state"])
		select_quest(qid)


func _resolve_service() -> void:
	if service == null:
		service = get_node_or_null("/root/QuestService")
	if service == null:
		service = QuestServiceScript.new()
		service.name = "LocalQuestService"
		service.load_seed()
		add_child(service)
		var ks := get_node_or_null("/root/KnowledgeService")
		if ks:
			service.connect_knowledge(ks)
	elif service.get_parent() == null:
		add_child(service)
	for sig in ["quests_changed", "tracked_changed"]:
		var cb := Callable(self, "_on_service_changed")
		if not service.is_connected(sig, cb):
			service.connect(sig, cb)


func _on_service_changed(_a = null) -> void:
	if _refresh_queued:
		return
	_refresh_queued = true
	_deferred_refresh.call_deferred()


func _deferred_refresh() -> void:
	_refresh_queued = false
	refresh()


# ==========================================================================
# Construcción
# ==========================================================================
func _build() -> void:
	if _built:
		return
	_built = true
	var col := build_frame(MENU_TAB_ID)
	var header := _hbox(8)
	header.name = "Header"
	col.add_child(header)
	var title := _label("Misiones", 1, Color.TRANSPARENT)
	title.name = "TitleLabel"
	title.visible = false
	header.add_child(title)

	var page := _hbox(12)
	page.name = "Page"
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(page)
	page.add_child(_build_list_column())
	page.add_child(_build_detail_column())
	page.add_child(_build_side_column())


func _build_list_column() -> Control:
	var card := _card("ListCard", 14)
	card.custom_minimum_size.x = 318
	var v := _vbox(8)
	card.add_child(v)
	var states := _hbox(6)
	states.name = "StateFilters"
	v.add_child(states)
	for s in STATE_FILTERS:
		var b := _chip_button(s["label"], 12, 28)
		b.name = "State_" + s["id"]
		var sid: String = s["id"]
		b.pressed.connect(func() -> void: set_state_filter(sid))
		states.add_child(b)
		state_buttons[sid] = b
	var cats := HFlowContainer.new()
	cats.name = "CategoryFilters"
	cats.add_theme_constant_override("h_separation", 4)
	cats.add_theme_constant_override("v_separation", 4)
	v.add_child(cats)
	var all_b := _chip_button("Todas", 11, 24)
	all_b.name = "Cat_all"
	all_b.pressed.connect(func() -> void: set_category_filter(""))
	cats.add_child(all_b)
	category_buttons[""] = all_b
	for c in service.categories:
		var label := str(c["label"]).replace("Misiones de ", "")
		var b2 := _chip_button(label, 11, 24)
		b2.name = "Cat_" + str(c["id"])
		var cid: String = c["id"]
		b2.pressed.connect(func() -> void: set_category_filter(cid))
		cats.add_child(b2)
		category_buttons[cid] = b2
	var scroll := ScrollContainer.new()
	scroll.name = "ListScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	list_box = _vbox(2)
	list_box.name = "QuestList"
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list_box)
	return card


func _build_detail_column() -> Control:
	var card := _card("DetailCard", 22)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := _vbox(10)
	card.add_child(v)
	var dscroll := ScrollContainer.new()
	dscroll.name = "DetailScroll"
	dscroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(dscroll)
	detail_box = _vbox(10)
	detail_box.name = "Detail"
	detail_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dscroll.add_child(detail_box)
	empty_label = _label("No hay misiones con este filtro.", 14, T.TEXT_MUTED)
	empty_label.visible = false
	v.add_child(empty_label)
	feedback_label = _label("", 12, T.TEXT_SECONDARY)
	feedback_label.name = "Feedback"
	v.add_child(feedback_label)
	var actions := _hbox(8)
	actions.name = "Actions"
	v.add_child(actions)
	track_button = _primary_button("Seguir en HUD")
	track_button.name = "TrackButton"
	track_button.pressed.connect(toggle_track_selected)
	actions.add_child(track_button)
	map_button = _ghost_button("Ver en el mapa")
	map_button.name = "MapButton"
	map_button.pressed.connect(view_on_map)
	actions.add_child(map_button)
	actions.add_child(_spacer(Vector2.ZERO, true))
	abandon_button = _danger_text_button("Abandonar")
	abandon_button.name = "AbandonButton"
	abandon_button.pressed.connect(_on_abandon_or_accept)
	actions.add_child(abandon_button)
	return card


func _build_side_column() -> Control:
	var card := _card("SideCard", 18)
	card.custom_minimum_size.x = 330
	var v := _vbox(10)
	card.add_child(v)
	var hrow := _hbox(6)
	v.add_child(hrow)
	hrow.add_child(_caps("EN TU HUD"))
	hrow.add_child(_spacer(Vector2.ZERO, true))
	hud_count_label = _label("0/3", 12, T.TEXT_SECONDARY, "semibold")
	hud_count_label.name = "HudCount"
	hrow.add_child(hud_count_label)
	hud_box = _vbox(6)
	hud_box.name = "HudPreview"
	v.add_child(hud_box)
	v.add_child(_wrap_label("Hasta 3 misiones activas se muestran en el rastreador del HUD (se ocultan durante el combate).", 11, T.TEXT_MUTED))
	var sep := HSeparator.new()
	sep.add_theme_stylebox_override("separator", T.box(T.DIVIDER, 0))
	v.add_child(sep)
	v.add_child(_caps("PLANIFICADOR DE SESIÓN"))
	var pscroll := ScrollContainer.new()
	pscroll.name = "PlannerScroll"
	pscroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(pscroll)
	plan_box = _vbox(8)
	plan_box.name = "Planner"
	plan_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pscroll.add_child(plan_box)
	var route_b := _primary_button("Ver ruta en el mapa")
	route_b.name = "RouteButton"
	route_b.pressed.connect(func() -> void:
		var tracked: Array = service.get_tracked()
		if not tracked.is_empty():
			view_on_map(str(tracked[0])))
	v.add_child(route_b)
	return card


# ==========================================================================
# API
# ==========================================================================
func set_state_filter(state: String) -> void:
	state_filter = state
	_ensure_selection()
	refresh()


func set_category_filter(cat: String) -> void:
	category_filter = cat
	_ensure_selection()
	refresh()


func visible_quests() -> Array[Dictionary]:
	return service.list_quests(category_filter, state_filter)


func select_quest(id: String) -> void:
	selected_id = id
	if feedback_label:
		feedback_label.text = ""
	refresh()
	quest_selected.emit(id)


func _ensure_selection() -> void:
	var qs := visible_quests()
	for q in qs:
		if q["id"] == selected_id:
			return
	selected_id = str(qs[0]["id"]) if not qs.is_empty() else ""


## «Seguir en HUD» / «Dejar de seguir». Máx. 3 en el rastreador.
func toggle_track_selected() -> Dictionary:
	if selected_id == "":
		return {"ok": false, "reason": "no_selection"}
	var r: Dictionary = service.toggle_track(selected_id)
	if r.get("ok", false):
		feedback_label.text = "Rastreando en el HUD." if r.get("tracked", false) else "Ya no se muestra en el HUD."
		tracking_changed.emit(selected_id, bool(r.get("tracked", false)))
	elif r.get("reason", "") == "max_tracked":
		feedback_label.text = "Ya sigues %d misiones: deja de seguir una para añadir otra." % int(r.get("max", 3))
	elif r.get("reason", "") == "not_active":
		feedback_label.text = "Solo se pueden seguir misiones activas."
	refresh()
	return r


## «Ver en el mapa»: abre `map_window` con las coordenadas del objetivo.
func view_on_map(quest_id: String = "") -> Dictionary:
	var id := quest_id if quest_id != "" else selected_id
	if id == "":
		return {}
	var params: Dictionary = service.get_map_target(id)
	if params.is_empty():
		return {}
	params["source"] = "quests_window"
	map_requested.emit(params)
	open_other_window("map_window", params)
	return params


func _on_abandon_or_accept() -> void:
	var q: Dictionary = service.get_quest(selected_id)
	if q.is_empty():
		return
	if q["state"] == "active":
		var r: Dictionary = service.abandon(selected_id)
		feedback_label.text = "Misión abandonada: vuelve a Disponibles." if r.get("ok", false) else "Esta misión no se puede abandonar aquí."
	elif q["state"] == "available":
		var r2: Dictionary = service.accept(selected_id)
		if r2.get("ok", false):
			feedback_label.text = "Misión aceptada."
			set_state_filter("active")
			select_quest(selected_id)
			return
		feedback_label.text = "Decide la oferta desde el Códice › Inversiones." if q["category"] == "pionero" else "No se puede aceptar."
	_ensure_selection()
	refresh()


# ==========================================================================
# Refresco
# ==========================================================================
func refresh() -> void:
	if not _built:
		return
	_ensure_selection()
	var counts: Dictionary = service.count_by_state()
	for s in STATE_FILTERS:
		var b: Button = state_buttons[s["id"]]
		var n := int(counts.get(s["id"], 0))
		b.text = "%s %d" % [s["label"], n] if s["id"] != "completed" else "%s %d" % [s["label"], n]
		b.set_pressed_no_signal(s["id"] == state_filter)
	for cid in category_buttons:
		(category_buttons[cid] as Button).set_pressed_no_signal(cid == category_filter)
	_refresh_list()
	_refresh_detail()
	_refresh_side()


func _refresh_list() -> void:
	_clear(list_box)
	list_rows.clear()
	var qs := visible_quests()
	var current_cat := ""
	for q in qs:
		if q["category"] != current_cat:
			current_cat = q["category"]
			var info: Dictionary = service.category_info(current_cat)
			var h := _hbox(6)
			h.name = "Group_" + current_cat
			var cap := _caps(str(info["label"]).to_upper(), service.category_color(current_cat))
			h.add_child(cap)
			h.add_child(_spacer(Vector2.ZERO, true))
			h.add_child(_label(str(info.get("note", "")), 11, T.TEXT_MUTED))
			if list_box.get_child_count() > 0:
				list_box.add_child(_spacer(Vector2(0, 6)))
			list_box.add_child(h)
		list_box.add_child(_quest_row(q))


func _quest_row(q: Dictionary) -> Button:
	var b := _row_button("Row_" + str(q["id"]), 46)
	b.button_pressed = q["id"] == selected_id
	var qid: String = q["id"]
	b.pressed.connect(func() -> void: select_quest(qid))
	b.tooltip_text = str(q["title"])
	var h := _row_content(b, 10, 8)
	var check := Panel.new()
	check.custom_minimum_size = Vector2(18, 18)
	check.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	check.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tracked: bool = q["tracked"]
	check.add_theme_stylebox_override("panel", T.box(T.ACCENT_DEFAULT if tracked else Color(0, 0, 0, 0), 5, 0 if tracked else 1, Color(1, 1, 1, 0.25)))
	check.name = "TrackMark"
	if tracked:
		var tick := _label("✓", 12, T.SHELTER_PILL_TEXT, "bold")
		tick.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tick.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tick.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		check.add_child(tick)
	h.add_child(check)
	var mid := _vbox(4)
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(mid)
	var t := _label(str(q["title"]), 13, T.TEXT, "semibold")
	t.clip_text = true
	t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	mid.add_child(t)
	mid.add_child(_bar(float(q["ratio"]), service.category_color(q["category"]), 3))
	var lvl := str(int(q["level"])) if int(q["level"]) > 0 else ("%d/%d" % [int(q["done_steps"]), int(q["total_steps"])])
	h.add_child(_label(lvl, 12, T.TEXT_SECONDARY))
	list_rows[qid] = b
	return b


func _refresh_detail() -> void:
	_clear(detail_box)
	step_rows.clear()
	var q: Dictionary = service.get_quest(selected_id) if selected_id != "" else {}
	empty_label.visible = q.is_empty()
	track_button.visible = not q.is_empty()
	map_button.visible = not q.is_empty()
	abandon_button.visible = not q.is_empty()
	if q.is_empty():
		title_label_big = null
		return
	var badges := _hbox(6)
	badges.name = "Badges"
	detail_box.add_child(badges)
	var cat_color: Color = service.category_color(q["category"])
	badges.add_child(_badge(str(q.get("badge", q["category_label"])), cat_color))
	if int(q["level"]) > 0:
		badges.add_child(_badge("Nivel %d" % int(q["level"]), T.TEXT_KEY, T.BUTTON_BG))
	if str(q["zone"]) != "":
		badges.add_child(_badge(str(q["zone"]), T.TEXT_KEY, T.BUTTON_BG))
	if int(q.get("group", 1)) > 1:
		badges.add_child(_badge("Grupo recomendado: %d" % int(q["group"]), T.TEXT_KEY, T.BUTTON_BG))
	title_label_big = _label(str(q["title"]), 26, T.TEXT, "bold")
	title_label_big.name = "QuestTitle"
	detail_box.add_child(title_label_big)

	var story := _sub_card("Story", 14)
	detail_box.add_child(story)
	var sv := _vbox(6)
	story.add_child(sv)
	sv.add_child(_caps("LO QUE PASÓ HASTA AHORA"))
	sv.add_child(_wrap_label(str(q.get("story", "")), 13, T.TEXT_KEY))

	detail_box.add_child(_caps("OBJETIVOS"))
	var steps_box := _vbox(6)
	steps_box.name = "Steps"
	detail_box.add_child(steps_box)
	for s in q["steps"]:
		var done: bool = int(s["progress"]) >= int(s["goal"])
		var row := _hbox(10)
		steps_box.add_child(row)
		var box := Panel.new()
		box.custom_minimum_size = Vector2(18, 18)
		box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		box.add_theme_stylebox_override("panel", T.box(Color("#4fe39a") if done else Color(0, 0, 0, 0), 5, 0 if done else 1, Color(1, 1, 1, 0.3)))
		row.add_child(box)
		var l := _label(str(s["label"]), 14, T.TEXT_SECONDARY if done else T.TEXT)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var c := _label(QuestServiceScript.step_text(s), 14, T.TEXT_SECONDARY if done else T.TEXT, "semibold")
		c.name = "Count"
		row.add_child(c)
		step_rows.append({"label": l, "count": c})

	var rw: Dictionary = q.get("rewards", {})
	var choice: Array = rw.get("choice", [])
	detail_box.add_child(_caps("RECOMPENSAS · ELIGE UNA" if not choice.is_empty() else "RECOMPENSAS"))
	if not choice.is_empty():
		var crow := _hbox(10)
		detail_box.add_child(crow)
		for i in choice.size():
			crow.add_child(_reward_card(choice[i], i == 0))
	var line := _hbox(14)
	line.name = "RewardLine"
	detail_box.add_child(line)
	if int(rw.get("xp", 0)) > 0:
		line.add_child(_amount(fmt(int(rw["xp"])), "PX", COLOR_XP))
	if int(rw.get("gold", 0)) > 0:
		line.add_child(_amount(fmt(int(rw["gold"])), "oro", T.GOLD))
	for it in rw.get("items", []):
		line.add_child(_amount("%s ×%d" % [it["name"], int(it.get("qty", 1))], "", T.TEXT))
	if str(rw.get("reputation", "")) != "":
		line.add_child(_label("+ reputación con %s" % rw["reputation"], 13, T.TEXT_SECONDARY))
	if rw.has("investment"):
		line.add_child(_amount(QuestServiceScript._pct(float(rw.get("share", 0.0))), "de cada venta de %s" % rw["investment"], T.CODEX_PIONEER))

	var tracked: bool = q["tracked"]
	track_button.text = "Dejar de seguir" if tracked else "Seguir en HUD"
	track_button.disabled = q["state"] != "active"
	map_button.disabled = service.get_map_target(selected_id).is_empty()
	match str(q["state"]):
		"active":
			abandon_button.text = "Abandonar"
			abandon_button.visible = q["category"] != "pionero"
		"available":
			abandon_button.text = "Aceptar"
			abandon_button.visible = true
		_:
			abandon_button.visible = false


func _reward_card(item: Dictionary, selected: bool) -> PanelContainer:
	var color := Color(str(item.get("color", "#9aa6ae")))
	var p := _card("Reward", 10, T.SHELTER_SUB_BG, Color(T.ACCENT_DEFAULT, 0.9) if selected else T.CODEX_CARD_BORDER, 12)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var h := _hbox(10)
	p.add_child(h)
	var icon := Panel.new()
	icon.custom_minimum_size = Vector2(38, 38)
	icon.add_theme_stylebox_override("panel", T.box(T.WELL, 9, 2, color))
	h.add_child(icon)
	var v := _vbox(2)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(v)
	v.add_child(_label(str(item["name"]), 13, color, "semibold"))
	v.add_child(_label(str(item.get("note", "")), 11, T.DELTA_UP if str(item.get("note", "")).begins_with("▲") else T.TEXT_SECONDARY))
	return p


func _amount(value: String, unit: String, color: Color) -> HBoxContainer:
	var h := _hbox(4)
	h.add_child(_label(value, 14, color, "bold"))
	if unit != "":
		h.add_child(_label(unit, 13, T.TEXT_SECONDARY))
	return h


func _refresh_side() -> void:
	_clear(hud_box)
	var tracked: Array = service.get_tracked()
	hud_count_label.text = "%d/%d" % [tracked.size(), int(service.max_tracked)]
	var lines: Array = service.get_hud_lines()
	if tracked.is_empty():
		hud_box.add_child(_label("Ninguna misión rastreada.", 12, T.TEXT_MUTED))
	for i in tracked.size():
		var q: Dictionary = service.get_quest(str(tracked[i]))
		var row := _sub_card("Hud_" + str(tracked[i]), 10)
		hud_box.add_child(row)
		var v := _vbox(4)
		row.add_child(v)
		var hl := _label("◆ " + (str(lines[i]) if i < lines.size() else str(q.get("title", ""))), 12, T.TEXT, "semibold")
		hl.clip_text = true
		hl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		v.add_child(hl)
		v.add_child(_bar(float(q.get("ratio", 0.0)), service.category_color(str(q.get("category", ""))), 3))

	_clear(plan_box)
	var plan: Dictionary = service.plan_session()
	var steps: Array = plan["steps"]
	plan_box.add_child(_label("%d misiones → 1 ruta" % steps.size(), 16, T.TEXT, "bold"))
	for i in steps.size():
		var h := _hbox(10)
		plan_box.add_child(h)
		var num := PanelContainer.new()
		var nsb := T.box(T.GOLD, 11)
		num.add_theme_stylebox_override("panel", nsb)
		num.custom_minimum_size = Vector2(22, 22)
		num.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var nl := _label(str(i + 1), 11, T.TEXT_DARK, "bold")
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		num.add_child(nl)
		h.add_child(num)
		var v2 := _vbox(0)
		h.add_child(v2)
		v2.add_child(_label(str(steps[i]["title"]), 13, T.TEXT, "semibold"))
		v2.add_child(_label("%s · %d min" % [steps[i]["zone"], int(steps[i]["est_min"])], 11, T.TEXT_SECONDARY))
	var stats := _hbox(8)
	plan_box.add_child(stats)
	stats.add_child(_stat_tile("Tiempo", "%d min" % int(plan["minutes"]), T.TEXT))
	stats.add_child(_stat_tile("PX total", fmt(int(plan["xp"])), COLOR_XP))
	stats.add_child(_stat_tile("PX/hora", fmt(int(plan["xp_per_hour"])), T.ACCENT_DEFAULT))


func _stat_tile(cap: String, value: String, color: Color) -> PanelContainer:
	var p := _sub_card("Stat", 8)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := _vbox(0)
	p.add_child(v)
	v.add_child(_label(cap, 11, T.TEXT_SECONDARY))
	v.add_child(_label(value, 17, color, "bold"))
	return p


func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not (event is InputEventKey) or not event.pressed or event.is_echo():
		return
	if (event as InputEventKey).keycode == KEY_T and not (event as InputEventKey).ctrl_pressed:
		toggle_track_selected()
		get_viewport().set_input_as_handled()
