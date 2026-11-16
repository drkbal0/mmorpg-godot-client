extends "res://ui/templates/BaseWindow.gd"
## Antesala de mazmorra / incursión — UI v2.4 Paso 14 (design_ref/pantallas_html/MMO-Antesala.html).
##
## - Velo rgba(5,8,10,0.74) sobre el mundo y escenario 1440×810 escalado al viewport.
## - Cabecera: «ANTESALA» (cian), «Bóveda de Ferrum · Heroica» (34 px negrita) y
##   «Entrada automática en 0:24 cuando los 5 estén listos».
## - 5 tarjetas de jugador: chibi, nombre (17 px), rol · iLvl en el color del rol, badge de estado
##   («Listo ✓» verde / «Cambiando conjunto…» ámbar / «Preparando…» gris) y checklist
##   (Consumibles, Reparación, Conjunto). La tuya lleva el borde cian de 1,5 px.
## - Preparación del grupo: afijos de la semana, votación de ruta (clic para votar) y
##   «Primera vez para N» con el interruptor de modo aprendizaje.
## - Pie: El Nido en mini-ventana [H], selector de conjunto F1-F3, «Abandonar grupo»,
##   «Iniciar ahora» (solo el líder, con todos listos) y «Marcar listo [Espacio]».
##
## Teclado: Espacio / R listo · F1-F3 conjunto · Enter iniciar ahora (líder) · H refugio de bolsillo ·
## Esc oculta la antesala (el grupo sigue esperando).
##
## El estado vive en `DungeonLobbyService` (inyectable como `service`).

const T = preload("res://ui/tokens/hud_tokens.gd")
const Kit = preload("res://ui/windows/common/CinematicKit.gd")
const LobbyServiceScript = preload("res://shared-core/DungeonLobbyService.gd")

signal dungeon_entered(dungeon_id: String, info: Dictionary)
signal pocket_shelter_requested
signal lobby_left
signal lobby_hidden

const NEST_ICON := "M12 1.5a10.5 10.5 0 1 0 .01 0M5 8.5h14l-2.5 5-3 2-1.5 4.5-1.5-4.5-3-2z"

## Servicio inyectable (tests). Si es null se usa /root/DungeonLobbyService o uno local.
var service: Node = null
var stage_scale := 1.0
var close_reason := ""

var veil: ColorRect
var stage: Control
var header_caps: Label
var title_label_main: Label
var caption_prefix: Label
var countdown_label: Label
var caption_suffix: Label
var cards_row: HBoxContainer
var player_cards: Array[PanelContainer] = []
var prep_row: HBoxContainer
var affix_box: VBoxContainer
var route_box: VBoxContainer
var route_rows: Array[Button] = []
var first_card: PanelContainer
var first_caps: Label
var first_text: Label
var learning_switch: Switch
var footer: HBoxContainer
var nest_panel: PanelContainer
var set_buttons: Array[Button] = []
var leave_button: Button
var start_button: Button
var ready_button: Button

var _built := false
var _last_dynamic := ""


func _init() -> void:
	theme = T.THEME
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	is_draggable = false


func _ready() -> void:
	window_id = "dungeon_lobby"
	_resolve_service()
	_build()
	super._ready()
	add_to_group("dungeon_lobby")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(_layout)
	_layout()
	refresh()


func center_on_screen() -> void:
	pass


## params: {"dungeon_id": "ferrum_vault", "difficulty": ""}. Reabre la antesala en espera.
func initialize_window(params: Dictionary) -> void:
	if service == null:
		_resolve_service()
	var id := str(params.get("dungeon_id", ""))
	if id != "" or service.state != LobbyServiceScript.STATE_WAITING:
		service.open_lobby(id if id != "" else service.dungeon_id, str(params.get("difficulty", "")))
	close_reason = ""
	visible = true
	refresh()


func _resolve_service() -> void:
	if service == null and is_inside_tree():
		service = get_node_or_null("/root/DungeonLobbyService")
	if service == null:
		service = LobbyServiceScript.new()
		service.name = "LocalDungeonLobbyService"
		service.load_seed()
	if service.get_parent() == null:
		add_child(service)
	for sig in ["lobby_changed", "member_changed", "all_ready_changed", "route_voted", "learning_mode_changed"]:
		var cb := Callable(self, "_on_service_changed")
		if not service.is_connected(sig, cb):
			service.connect(sig, cb)
	if not service.is_connected("entry_started", _on_entry_started):
		service.entry_started.connect(_on_entry_started)
	if not service.is_connected("group_left", _on_group_left):
		service.group_left.connect(_on_group_left)


func _on_service_changed(_a = null, _b = null) -> void:
	if _built:
		refresh()


func _process(_delta: float) -> void:
	if _built and visible:
		_refresh_dynamic()


# ==========================================================================
# API
# ==========================================================================
func toggle_ready() -> bool:
	return service.toggle_ready()


func select_set(index: int) -> bool:
	return service.set_equipment_set_by_key(index)


func start_now() -> Dictionary:
	var r: Dictionary = service.start_now()
	if not r.get("ok", false):
		_refresh_dynamic(true)
	return r


func leave_group() -> bool:
	return service.leave_group()


func open_pocket_shelter() -> void:
	pocket_shelter_requested.emit()
	var orch := _orchestrator()
	if orch != null:
		orch.open_window("shelter_pocket")


func handle_key(keycode: int) -> bool:
	match keycode:
		KEY_SPACE, KEY_R:
			toggle_ready()
			return true
		KEY_F1:
			select_set(0)
			return true
		KEY_F2:
			select_set(1)
			return true
		KEY_F3:
			select_set(2)
			return true
		KEY_ENTER, KEY_KP_ENTER:
			start_now()
			return true
		KEY_H:
			open_pocket_shelter()
			return true
		KEY_ESCAPE:
			_close("hidden")
			lobby_hidden.emit()
			return true
	return false


func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not (event is InputEventKey) or not event.pressed or event.is_echo():
		return
	if handle_key((event as InputEventKey).keycode):
		get_viewport().set_input_as_handled()


## Solo enruta a otras ventanas si la abrió el orquestador.
func _orchestrator() -> Node:
	var orch := get_node_or_null("/root/UIOrchestrator")
	if orch != null and "window_layer" in orch and get_parent() == orch.window_layer:
		return orch
	return null


func _on_entry_started(id: String, info: Dictionary) -> void:
	dungeon_entered.emit(id, info)
	_close("entered")


func _on_group_left(_member_id: String) -> void:
	lobby_left.emit()
	_close("left")


func _close(reason: String) -> void:
	close_reason = reason
	if visible:
		_on_close_pressed()
		visible = false


# ==========================================================================
# Construcción
# ==========================================================================
func _build() -> void:
	if _built:
		return
	_built = true
	veil = ColorRect.new()
	veil.name = "Veil"
	veil.color = T.DUNGEON_LOBBY_VEIL
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(veil)

	stage = Control.new()
	stage.name = "Stage"
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.size = T.CINEMA_DESIGN_SIZE
	add_child(stage)

	# Cabecera.
	var head := VBoxContainer.new()
	head.name = "HeaderBlock"
	head.add_theme_constant_override("separation", 4)
	head.position = Vector2(50, 34)
	stage.add_child(head)
	header_caps = Kit.caps("Antesala", T.ACCENT_DEFAULT)
	header_caps.name = "Caps"
	head.add_child(header_caps)
	title_label_main = Kit.label("", T.DUNGEON_TITLE_SIZE, T.TEXT, "bold")
	title_label_main.name = "DungeonTitle"
	head.add_child(title_label_main)
	var cap := HBoxContainer.new()
	cap.name = "Caption"
	cap.add_theme_constant_override("separation", 4)
	head.add_child(cap)
	caption_prefix = Kit.label("", 15, T.TEXT_SECONDARY)
	caption_prefix.name = "Prefix"
	cap.add_child(caption_prefix)
	countdown_label = Kit.label("", 15, T.TEXT, "bold")
	countdown_label.name = "Countdown"
	cap.add_child(countdown_label)
	caption_suffix = Kit.label("", 15, T.TEXT_SECONDARY)
	caption_suffix.name = "Suffix"
	cap.add_child(caption_suffix)

	# Tarjetas del grupo.
	cards_row = HBoxContainer.new()
	cards_row.name = "Group"
	cards_row.add_theme_constant_override("separation", int(T.DUNGEON_GRID_GAP))
	cards_row.position = Vector2(T.DUNGEON_GRID_LEFT, T.DUNGEON_GRID_TOP)
	cards_row.size = Vector2(T.CINEMA_DESIGN_SIZE.x - T.DUNGEON_GRID_LEFT * 2, 0)
	stage.add_child(cards_row)

	# Preparación del grupo.
	prep_row = HBoxContainer.new()
	prep_row.name = "Preparation"
	prep_row.add_theme_constant_override("separation", int(T.DUNGEON_GRID_GAP))
	prep_row.position = Vector2(T.DUNGEON_GRID_LEFT, 384)
	prep_row.size = Vector2(T.CINEMA_DESIGN_SIZE.x - T.DUNGEON_GRID_LEFT * 2, 0)
	stage.add_child(prep_row)
	var aff := _card("Affixes", 1.2)
	prep_row.add_child(aff)
	affix_box = aff.get_node("Body")
	var votes := _card("RouteVote", 1.0)
	prep_row.add_child(votes)
	route_box = votes.get_node("Body")
	first_card = _card("FirstTime", 1.0, true)
	prep_row.add_child(first_card)
	var fb: VBoxContainer = first_card.get_node("Body")
	first_caps = Kit.caps("", T.ACCENT_DEFAULT)
	first_caps.name = "Caps"
	fb.add_child(first_caps)
	first_text = Kit.label("", 13, T.TEXT_KEY)
	first_text.name = "Text"
	first_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	first_text.custom_minimum_size.x = 290
	fb.add_child(first_text)
	var lm := HBoxContainer.new()
	lm.name = "LearningMode"
	fb.add_child(lm)
	var lml := Kit.label("Modo aprendizaje", 14, T.TEXT)
	lml.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lm.add_child(lml)
	learning_switch = Switch.new()
	learning_switch.name = "Switch"
	learning_switch.toggled.connect(func(on: bool) -> void: service.set_learning_mode(on))
	lm.add_child(learning_switch)

	# Pie de controles.
	footer = HBoxContainer.new()
	footer.name = "Footer"
	footer.add_theme_constant_override("separation", 12)
	footer.position = Vector2(T.DUNGEON_GRID_LEFT, T.CINEMA_DESIGN_SIZE.y - 34 - T.DUNGEON_FOOTER_HEIGHT)
	footer.size = Vector2(T.CINEMA_DESIGN_SIZE.x - T.DUNGEON_GRID_LEFT * 2, T.DUNGEON_FOOTER_HEIGHT)
	stage.add_child(footer)
	nest_panel = Kit.panel("Nest", Kit.box(Color(13 / 255.0, 18 / 255.0, 22 / 255.0, 0.95), 12, 1, Color(1, 1, 1, 0.1)), 14, 0)
	nest_panel.custom_minimum_size.y = T.DUNGEON_FOOTER_HEIGHT
	nest_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	nest_panel.tooltip_text = "Refugio de bolsillo [H]"
	nest_panel.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			open_pocket_shelter())
	footer.add_child(nest_panel)
	var nh := HBoxContainer.new()
	nh.add_theme_constant_override("separation", 10)
	nh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nest_panel.add_child(nh)
	var ni = Kit.Icon.new(NEST_ICON, Vector2(26, 26))
	ni.name = "Icon"
	ni.stroke = T.ACCENT_DEFAULT
	ni.icon_size = 26
	ni.width = 1.6
	nh.add_child(ni)
	var nv := VBoxContainer.new()
	nv.add_theme_constant_override("separation", 0)
	nv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	nv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nh.add_child(nv)
	var nt := Kit.label("", 13, T.TEXT, "bold")
	nt.name = "Title"
	nv.add_child(nt)
	var ns := Kit.label("", 12, T.TEXT_SECONDARY)
	ns.name = "Text"
	nv.add_child(ns)
	nh.add_child(Kit.kbd("H"))

	var sets := HBoxContainer.new()
	sets.name = "Sets"
	sets.add_theme_constant_override("separation", 6)
	footer.add_child(sets)
	for i in 3:
		var b := Button.new()
		b.name = "Set%d" % (i + 1)
		b.custom_minimum_size = Vector2(0, T.DUNGEON_FOOTER_HEIGHT)
		b.toggle_mode = false
		Kit.button_styles(b, 10)
		b.add_theme_font_override("font", T.font("semibold"))
		b.add_theme_font_size_override("font_size", 14)
		var idx := i
		b.pressed.connect(func() -> void: select_set(idx))
		_pad(b, 12)
		sets.add_child(b)
		set_buttons.append(b)

	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	footer.add_child(sp)

	leave_button = _footer_button("Leave", "Abandonar grupo")
	leave_button.pressed.connect(leave_group)
	footer.add_child(leave_button)
	start_button = _footer_button("StartNow", "Iniciar ahora")
	start_button.tooltip_text = "Solo el líder · con los 5 listos [Enter]"
	start_button.pressed.connect(start_now)
	footer.add_child(start_button)
	ready_button = _footer_button("Ready", "Marcar listo [Espacio]")
	ready_button.add_theme_font_size_override("font_size", 18)
	ready_button.custom_minimum_size.x = 250
	ready_button.pressed.connect(toggle_ready)
	footer.add_child(ready_button)


func _card(node_name: String, ratio: float, accent: bool = false) -> PanelContainer:
	var sb := Kit.box(T.DUNGEON_CARD_BG, T.DUNGEON_CARD_RADIUS, 1.5 if accent else 1.0, T.DUNGEON_SELF_EDGE if accent else T.DUNGEON_CARD_EDGE)
	if accent:
		sb.set_border_width_all(2)
	var p := Kit.panel(node_name, sb, 16)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.size_flags_stretch_ratio = ratio
	var v := VBoxContainer.new()
	v.name = "Body"
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)
	return p


func _footer_button(node_name: String, text: String) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.custom_minimum_size = Vector2(0, T.DUNGEON_FOOTER_HEIGHT)
	b.focus_mode = Control.FOCUS_NONE
	Kit.button_styles(b, 10)
	b.add_theme_font_override("font", T.font("semibold"))
	b.add_theme_font_size_override("font_size", 14)
	b.add_theme_color_override("font_color", T.TEXT)
	_pad(b)
	return b


## Margen horizontal de 14 px en todos los estilos del botón (`.btn` padding 0 14px).
static func _pad(b: Button, x: int = 14) -> void:
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb := b.get_theme_stylebox(st)
		if sb is StyleBoxFlat:
			(sb as StyleBoxFlat).content_margin_left = x
			(sb as StyleBoxFlat).content_margin_right = x


func _primary(b: Button, on: bool) -> void:
	if on:
		for st in ["normal", "hover", "pressed", "focus"]:
			var c: Color = T.ACCENT_DEFAULT if st != "hover" else T.ACCENT_DEFAULT.lightened(0.12)
			b.add_theme_stylebox_override(st, Kit.box(c, 10))
		b.add_theme_stylebox_override("disabled", Kit.box(Color(T.ACCENT_DEFAULT, 0.35), 10))
		for fc in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			b.add_theme_color_override(fc, T.DUNGEON_REPEAT_TEXT)
	else:
		Kit.button_styles(b, 10)
		for fc in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			b.add_theme_color_override(fc, T.TEXT)
	_pad(b, 34 if b == ready_button else 14)
	b.set_meta("primary", on)


func _layout() -> void:
	if not _built:
		return
	var area := size if size.x > 0 else get_viewport_rect().size
	stage_scale = Kit.fit_stage(stage, area)


# ==========================================================================
# Refresco
# ==========================================================================
func refresh() -> void:
	if not _built or service == null:
		return
	title_label_main.text = service.title_text()
	_rebuild_cards()
	_rebuild_affixes()
	_rebuild_routes()
	var ft: Array = service.first_timers()
	first_card.visible = true
	first_caps.text = ("Primera vez para %d" % ft.size()).to_upper() if not ft.is_empty() else "TODOS CONOCEN LA RUTA"
	first_text.text = service.first_time_text()
	learning_switch.set_on(service.learning_mode, false)
	(nest_panel.find_child("Title", true, false) as Label).text = str(service.nest.get("title", "El Nido en mini-ventana"))
	(nest_panel.find_child("Text", true, false) as Label).text = str(service.nest.get("text", "Ábrelo mientras esperas"))
	var opts: Array = service.set_options()
	for i in set_buttons.size():
		var b := set_buttons[i]
		b.visible = i < opts.size()
		if i < opts.size():
			b.text = "%s %s" % [opts[i]["key"], opts[i]["name"]]
			var active: bool = str(opts[i]["id"]) == service.active_set_id()
			b.set_meta("active", active)
			b.add_theme_color_override("font_color", T.ACCENT_DEFAULT if active else T.TEXT_KEY)
			b.add_theme_stylebox_override("normal", Kit.box(T.BUTTON_BG, 10, 2 if active else 1, T.ACCENT_DEFAULT if active else T.BUTTON_BORDER))
			_pad(b, 12)
	_refresh_dynamic(true)


func _rebuild_cards() -> void:
	Kit.clear(cards_row)
	player_cards.clear()
	for m in service.members:
		var is_self: bool = service.is_local(str(m["id"]))
		var sb := Kit.box(T.DUNGEON_CARD_BG, T.DUNGEON_CARD_RADIUS, 2.0 if is_self else 1.0, T.DUNGEON_SELF_EDGE if is_self else T.DUNGEON_CARD_EDGE)
		sb.shadow_color = Color(0, 0, 0, 0.45) if is_self else Color(0, 0, 0, 0)
		sb.shadow_size = 24 if is_self else 0
		sb.shadow_offset = Vector2(0, 12)
		var card := Kit.panel("Player_%s" % m["id"], sb, 16)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.set_meta("member_id", m["id"])
		card.set_meta("is_self", is_self)
		card.set_meta("status", m["status"])
		var v := VBoxContainer.new()
		v.name = "Body"
		v.add_theme_constant_override("separation", 10)
		card.add_child(v)
		var h := HBoxContainer.new()
		h.name = "Head"
		h.add_theme_constant_override("separation", 10)
		v.add_child(h)
		var av := Chibi.new()
		av.name = "Avatar"
		av.body = Color(str(m["avatar_body"]))
		av.hair = Color(str(m["avatar_hair"]))
		h.add_child(av)
		var nv := VBoxContainer.new()
		nv.add_theme_constant_override("separation", 0)
		nv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(nv)
		var nl := Kit.label(service.display_name(m), 17, T.TEXT, "bold")
		nl.name = "Name"
		nv.add_child(nl)
		var rl := Kit.label(service.role_line(m), 12, Color(service.role_color(str(m["role"]))))
		rl.name = "Role"
		rl.tooltip_text = str(m["archetype"])
		nv.add_child(rl)
		var st: Dictionary = service.status_style(m)
		var badge := Kit.panel("Badge", Kit.box(Color(str(st["bg"])), 8), 6, 0)
		badge.custom_minimum_size.y = T.DUNGEON_BADGE_HEIGHT
		var bl := Kit.label(str(st["text"]), 13, Color(str(st["color"])), "bold")
		bl.name = "Text"
		bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		bl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		badge.add_child(bl)
		v.add_child(badge)
		for row in service.checklist(m):
			var r := HBoxContainer.new()
			r.name = "Check_%s" % row["id"]
			v.add_child(r)
			var k := Kit.label(str(row["label"]), 13, T.TEXT_SECONDARY)
			k.name = "Label"
			k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			r.add_child(k)
			var val := Kit.label(str(row["value"]), 13, Color(str(row["color"])), "semibold")
			val.name = "Value"
			r.add_child(val)
		var warn: Array = service.readiness_warnings(m)
		if not warn.is_empty():
			card.tooltip_text = "\n".join(warn)
			card.mouse_filter = Control.MOUSE_FILTER_PASS
		cards_row.add_child(card)
		player_cards.append(card)


func _rebuild_affixes() -> void:
	Kit.clear(affix_box)
	affix_box.add_child(Kit.caps("Afijos de esta semana"))
	for a in service.affixes:
		var v := VBoxContainer.new()
		v.name = "Affix"
		v.add_theme_constant_override("separation", 2)
		v.add_child(Kit.label(str(a["name"]), 14, Color(str(a["color"])), "bold"))
		var t := Kit.label(str(a["text"]), 12, T.TEXT_SECONDARY)
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(t)
		affix_box.add_child(v)


func _rebuild_routes() -> void:
	Kit.clear(route_box)
	route_rows.clear()
	route_box.add_child(Kit.caps("Votación de ruta"))
	var mine: String = service.voted_route()
	for r in service.routes:
		var b := Button.new()
		b.name = "Route_%s" % r["id"]
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size.y = 32
		b.tooltip_text = "Votar «%s»" % r["name"]
		b.set_meta("route_id", r["id"])
		for st in ["normal", "hover", "pressed", "focus"]:
			b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
		var rid := str(r["id"])
		b.pressed.connect(func() -> void: service.vote_route(rid))
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 4)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		b.add_child(v)
		var h := HBoxContainer.new()
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(h)
		var n := Kit.label(str(r["name"]) + ("  ✓" if rid == mine else ""), 14, T.TEXT, "semibold")
		n.name = "Name"
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(n)
		var c: int = service.route_votes(rid)
		var vl := Kit.label("%d %s" % [c, "voto" if c == 1 else "votos"], 14, T.TEXT_SECONDARY)
		vl.name = "Votes"
		h.add_child(vl)
		var bar = Kit.Bar.new(6.0)
		bar.name = "Bar"
		bar.track = T.DUNGEON_SUB_BG
		bar.fill = Color(str(r["color"]))
		bar.ratio = service.route_ratio(rid)
		v.add_child(bar)
		route_box.add_child(b)
		route_rows.append(b)


func _refresh_dynamic(force: bool = false) -> void:
	var swap := ""
	for m in service.members:
		if m["status"] == LobbyServiceScript.STATUS_CHANGING:
			swap += "%s%.1f" % [m["id"], m["swap_remaining"]]
	var key := "%s|%s|%s|%d|%s" % [service.state, service.countdown_text(), str(service.all_ready()), service.ready_count(), swap]
	if key == _last_dynamic and not force:
		return
	_last_dynamic = key
	var running: bool = service.is_countdown_running()
	if service.state == LobbyServiceScript.STATE_ENTERING:
		caption_prefix.text = "Entrando en la mazmorra…"
		countdown_label.text = ""
		caption_suffix.text = ""
	elif running:
		caption_prefix.text = "Todos listos · entrada automática en"
		countdown_label.text = service.countdown_text()
		caption_suffix.text = ""
	else:
		caption_prefix.text = "Entrada automática en"
		countdown_label.text = service.countdown_text()
		caption_suffix.text = "cuando los %d estén listos" % LobbyServiceScript.MAX_MEMBERS
	countdown_label.add_theme_color_override("font_color", T.ACCENT_DEFAULT if running else T.TEXT)
	var me: Dictionary = service.local_member()
	var is_ready: bool = not me.is_empty() and me["status"] == LobbyServiceScript.STATUS_READY
	var changing: bool = not me.is_empty() and me["status"] == LobbyServiceScript.STATUS_CHANGING
	ready_button.text = "Cancelar listo [Espacio]" if is_ready else "Marcar listo [Espacio]"
	ready_button.disabled = changing or service.state != LobbyServiceScript.STATE_WAITING
	_primary(ready_button, not is_ready)
	start_button.visible = service.is_leader()
	start_button.disabled = not service.all_ready() or service.state != LobbyServiceScript.STATE_WAITING
	_primary(start_button, service.all_ready() and service.is_leader())
	leave_button.disabled = service.state != LobbyServiceScript.STATE_WAITING


# ==========================================================================
# Controles dibujados
# ==========================================================================
## Avatar chibi del diseño (viewBox 30×38 → 40×50): cuerpo, cara, pelo y ojos.
class Chibi extends Control:
	const SP = preload("res://ui/icons/svg_path.gd")
	const HAIR := "M5 11a10 10 0 0 1 20 0c-3-3-7-4-10-4s-7 1-10 4z"
	const SKIN := Color("#f1d3b8")
	const EYES := Color("#1a1a1a")
	var body := Color("#2b4a8a")
	var hair := Color("#5a3a20")

	func _init() -> void:
		custom_minimum_size = Vector2(40, 50)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var s := minf(size.x / 30.0, size.y / 38.0)
		var o := (size - Vector2(30, 38) * s) * 0.5
		var sb := StyleBoxFlat.new()
		sb.bg_color = body
		sb.set_corner_radius_all(int(7 * s))
		sb.anti_aliasing = true
		draw_style_box(sb, Rect2(o + Vector2(7, 18) * s, Vector2(16, 16) * s))
		draw_circle(o + Vector2(15, 12) * s, 10 * s, SKIN, true, -1.0, true)
		for sp in SP.parse(HAIR):
			var pts := PackedVector2Array()
			for p in sp["points"]:
				pts.append(o + p * s)
			if pts.size() >= 3 and pts[0].is_equal_approx(pts[pts.size() - 1]):
				pts = pts.slice(0, pts.size() - 1)
			if pts.size() >= 3 and Geometry2D.triangulate_polygon(pts).size() > 0:
				draw_colored_polygon(pts, hair)
		draw_circle(o + Vector2(11.5, 13) * s, 1.4 * s, EYES, true, -1.0, true)
		draw_circle(o + Vector2(18.5, 13) * s, 1.4 * s, EYES, true, -1.0, true)


## Interruptor `.sw` (34×20, botón blanco de 14 px; cian si está activo).
class Switch extends Control:
	signal toggled(on: bool)
	var on := true

	func _init() -> void:
		custom_minimum_size = Vector2(34, 20)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	func set_on(v: bool, emit: bool = true) -> void:
		if on == v:
			return
		on = v
		queue_redraw()
		if emit:
			toggled.emit(on)

	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			set_on(not on)
			accept_event()

	func _draw() -> void:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("#46e3c1") if on else Color("#18242b")
		sb.set_corner_radius_all(10)
		sb.anti_aliasing = true
		draw_style_box(sb, Rect2(Vector2.ZERO, Vector2(34, 20)))
		var x := 34.0 - 3.0 - 7.0 if on else 3.0 + 7.0
		draw_circle(Vector2(x, 10), 7, Color.WHITE if on else Color("#9aa6ae"), true, -1.0, true)
