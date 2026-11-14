extends "res://ui/templates/BaseWindow.gd"
## Refugio «El Nido» (tecla H) — UI v2.4 Paso 8 (§2.5, Anexos D y E).
## Referencias: design_ref/pantallas_html/MMO-Refugio.html (corte lateral),
## MMO-Construir.html (modo Construir · B), MMO-Produccion.html, MMO-Expediciones.html,
## MMO-Pispa.html y MMO-Mejoras.html.
##
## Todo el estado vive en `ShelterService` (shared-core/ShelterService.gd); la ventana
## solo pinta y traduce clics a llamadas del servicio.
## Sub-ventanas: Refugio (con modo Construir, B) · Producción · Expediciones · Pispa · Mejoras.

const T = preload("res://ui/tokens/hud_tokens.gd")
const MenuBarScene = preload("res://ui/menu/menu_bar.tscn")
const ShelterServiceScript = preload("res://shared-core/ShelterService.gd")
const SideCutViewScript = preload("res://ui/windows/ShelterWindow/ShelterSideCutView.gd")

signal subtab_changed(subtab_id: String)
signal build_mode_changed(on: bool)
signal cell_selected(floor_idx: int, col: int)
signal room_placed(result: Dictionary)
signal fix_applied(workshop_id: String, solution_id: String, result: Dictionary)
signal expedition_sent(result: Dictionary)

const MENU_TAB_ID := "refugio"
const WINDOW_SIZE := Vector2(1270, 680)
const SUBTABS: Array[Dictionary] = [
	{"id": "refugio", "label": "Refugio"},
	{"id": "produccion", "label": "Producción"},
	{"id": "expediciones", "label": "Expediciones"},
	{"id": "pispa", "label": "Pispa"},
	{"id": "mejoras", "label": "Mejoras"},
]
const BUILD_CATEGORIES: Array[Dictionary] = [
	{"id": "estaciones", "label": "Estaciones"},
	{"id": "huerto", "label": "Huerto"},
	{"id": "muebles", "label": "Muebles"},
	{"id": "decoracion", "label": "Decoración"},
]
const HEADER_ITEMS: Array[String] = ["esquirlas", "metal", "madera", "oro"]

## Servicio inyectable (tests). Si es null se usa /root/ShelterService o uno local.
var service: Node = null

var menu_bar: Node
var subnav_buttons: Dictionary = {}
var pages: Dictionary = {}
var current_subtab: String = ""
var status_label: Label
var collect_button: Button
var resource_labels: Dictionary = {}

# --- Refugio / Construir -----------------------------------------------------
var build_mode := false
var side_cut: Control
var selected_cell := Vector2i(1, 0)
var selected_char: String = ""
var placing_type: String = "telar"
var build_category: String = "estaciones"
var mode_live_button: Button
var mode_build_button: Button
var people_box: VBoxContainer
var away_box: VBoxContainer
var detail_box: VBoxContainer
var storage_box: VBoxContainer
var drawer: PanelContainer
var drawer_cards: HBoxContainer
var drawer_cat_buttons: Dictionary = {}
var catalog_cards: Dictionary = {}
var place_button: Button
var dig_button: Button
var upgrade_room_button: Button
var dividends_button: Button
var away_card: PanelContainer

# --- Producción --------------------------------------------------------------
var chain_view: Control
var jam_banner: PanelContainer
var jam_title: Label
var jam_message: Label
var jam_buttons_box: HBoxContainer
var fix_buttons: Dictionary = {}

# --- Expediciones ------------------------------------------------------------
var selected_expedition: String = "ruinas_ferrum"
var team: Array = []
var team_with_pispa := false
var duration_h: int = 4
var exp_list_box: VBoxContainer
var exp_title: Label
var exp_zone: Label
var exp_desc: Label
var team_box: HBoxContainer
var chance_label: Label
var chance_alt_label: Label
var factors_box: VBoxContainer
var rewards_box: VBoxContainer
var durations_box: HBoxContainer
var return_label: Label
var send_button: Button
var running_box: VBoxContainer
var finished_box: VBoxContainer
var decision_buttons: Dictionary = {}

# --- Pispa -------------------------------------------------------------------
var pispa_portrait: Control
var pispa_level_label: Label
var pispa_species_label: Label
var pispa_xp_bar: Control
var pispa_xp_label: Label
var pispa_next_label: Label
var pispa_affection: Control
var pispa_affection_label: Label
var pispa_traits_box: VBoxContainer
var pispa_follow: CheckButton
var target_buttons: Dictionary = {}
var targets_box: HBoxContainer
var trip_label: Label
var trip_time_label: Label
var trip_bar: Control
var bag_grid: Control
var bag_label: Label
var snack_label: Label
var feed_button: Button
var empty_bag_button: Button
var pet_button: Button
var nest_box: VBoxContainer
var journal_box: VBoxContainer

# --- Mejoras -----------------------------------------------------------------
var upgrade_grid: GridContainer
var upgrade_cells: Dictionary = {}   # "row:tier" -> Button
var goals_box: HBoxContainer
var works_box: VBoxContainer
var why_box: VBoxContainer
var level_title: Label
var level_bar: Control
var level_done_label: Label
var comfort_label: Label
var new_floor_button: Button

var _pages_root: HBoxContainer
var _built := false
var _refresh_queued := false


func _init() -> void:
	custom_minimum_size = WINDOW_SIZE
	size = WINDOW_SIZE
	theme = T.THEME
	add_theme_stylebox_override("panel", T.box(T.PANEL_BG, 14, 1, T.PANEL_EDGE))


func _ready() -> void:
	window_id = "shelter"
	_resolve_service()
	_build()
	super._ready()
	add_to_group("shelter_window")
	_connect_menu_bar()
	set_title("Refugio")
	select_subtab(SUBTABS[0]["id"] if current_subtab == "" else current_subtab)
	get_viewport().size_changed.connect(fit_to_viewport)
	fit_to_viewport.call_deferred()


## Igual que Poderes: si el menú común no cabe, pasa a modo compacto.
func fit_to_viewport() -> void:
	if not is_inside_tree() or menu_bar == null:
		return
	var vp_w := get_viewport_rect().size.x
	var margin := menu_bar.get_node_or_null("Margin") as MarginContainer
	var title := menu_bar.get_node_or_null("Margin/Row/Title") as Control
	if margin:
		margin.add_theme_constant_override("margin_left", int(T.MENU_BAR_PADDING_X))
		margin.add_theme_constant_override("margin_right", int(T.MENU_BAR_PADDING_X))
	if title:
		title.visible = true
	var compact: bool = menu_bar.get_combined_minimum_size().x + 2.0 > vp_w
	if compact:
		if margin:
			margin.add_theme_constant_override("margin_left", 8)
			margin.add_theme_constant_override("margin_right", 8)
		if title:
			title.visible = false
	set_meta("menu_compact", compact)
	reset_size()
	size.x = clampf(WINDOW_SIZE.x, get_combined_minimum_size().x, maxf(vp_w, get_combined_minimum_size().x))
	position.x = clampf(position.x, 0.0, maxf(0.0, vp_w - size.x))


func initialize_window(params: Dictionary) -> void:
	var sub := str(params.get("subtab", ""))
	if sub == "construir":
		select_subtab("refugio")
		set_build_mode(true)
	elif sub != "" and pages.has(sub):
		select_subtab(sub)


func _resolve_service() -> void:
	if service == null:
		service = get_node_or_null("/root/ShelterService")
	if service == null:
		service = ShelterServiceScript.new()
		service.name = "LocalShelterService"
		add_child(service)
	elif service.get_parent() == null:
		add_child(service)
	for sig in ["shelter_changed", "storage_changed", "pispa_changed"]:
		var cb := Callable(self, "_on_service_changed")
		if not service.is_connected(sig, cb):
			service.connect(sig, cb)


func _on_service_changed() -> void:
	if _refresh_queued:
		return
	_refresh_queued = true
	_deferred_refresh.call_deferred()


func _deferred_refresh() -> void:
	_refresh_queued = false
	refresh()


func _connect_menu_bar() -> void:
	menu_bar.set_active_tab(MENU_TAB_ID)
	var orch := get_node_or_null("/root/UIOrchestrator")
	if orch and orch.has_method("connect_menu_bar"):
		orch.connect_menu_bar(menu_bar)
	elif not menu_bar.close_requested.is_connected(_on_close_pressed):
		menu_bar.close_requested.connect(_on_close_pressed)


# ==========================================================================
# Construcción
# ==========================================================================
func _build() -> void:
	if _built:
		return
	_built = true
	var root := VBoxContainer.new()
	root.name = "Root"
	root.add_theme_constant_override("separation", 10)
	add_child(root)

	menu_bar = MenuBarScene.instantiate()
	menu_bar.name = "MenuBar"
	root.add_child(menu_bar)

	var body := MarginContainer.new()
	body.name = "Body"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "bottom"]:
		body.add_theme_constant_override("margin_" + side, 16)
	root.add_child(body)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	body.add_child(col)

	var header := HBoxContainer.new()
	header.name = "Header"
	header.add_theme_constant_override("separation", 8)
	col.add_child(header)
	var pill := PanelContainer.new()
	pill.name = "Subnav"
	var psb := T.box(T.SHELTER_CARD_BG, 12, 1, T.CODEX_CARD_BORDER)
	psb.set_content_margin_all(4)
	pill.add_theme_stylebox_override("panel", psb)
	header.add_child(pill)
	var subnav := HBoxContainer.new()
	subnav.add_theme_constant_override("separation", 2)
	pill.add_child(subnav)
	for st in SUBTABS:
		var b := _chip_button(st["label"], 14, 30)
		b.name = "Sub_" + st["id"]
		var sid: String = st["id"]
		b.pressed.connect(func() -> void: select_subtab(sid))
		subnav.add_child(b)
		subnav_buttons[sid] = b
	var title := _label("Refugio", 1, Color.TRANSPARENT)
	title.name = "TitleLabel"
	title.visible = false
	header.add_child(title)
	status_label = _label("", 12, T.TEXT_SECONDARY)
	status_label.name = "StatusLabel"
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status_label.clip_text = true
	header.add_child(status_label)
	for it in HEADER_ITEMS:
		var chip := PanelContainer.new()
		var csb := T.box(T.SHELTER_SUB_BG, 9, 1, T.CODEX_CARD_BORDER)
		csb.content_margin_left = 10
		csb.content_margin_right = 10
		csb.content_margin_top = 4
		csb.content_margin_bottom = 4
		chip.add_theme_stylebox_override("panel", csb)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		chip.add_child(row)
		var dot := SideCutViewScript.Dot.new()
		dot.custom_minimum_size = Vector2(10, 10)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dot.color = service.item_color(it)
		dot.diamond = true
		row.add_child(dot)
		var l := _label("0", 13, T.TEXT, "bold")
		l.tooltip_text = service.item_name(it)
		row.add_child(l)
		resource_labels[it] = l
		header.add_child(chip)
	collect_button = _primary_button("Recoger todo")
	collect_button.name = "CollectAll"
	collect_button.pressed.connect(collect_all)
	header.add_child(collect_button)

	_pages_root = HBoxContainer.new()
	_pages_root.name = "Pages"
	_pages_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_pages_root)
	pages["refugio"] = _build_shelter_page()
	pages["produccion"] = _build_production_page()
	pages["expediciones"] = _build_expeditions_page()
	pages["pispa"] = _build_pispa_page()
	pages["mejoras"] = _build_upgrades_page()
	for id in pages:
		var p: Control = pages[id]
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		p.size_flags_vertical = Control.SIZE_EXPAND_FILL
		p.visible = false
		_pages_root.add_child(p)


# --------------------------------------------------------------------------
# Refugio (corte lateral) + modo Construir
# --------------------------------------------------------------------------
func _build_shelter_page() -> Control:
	var page := HBoxContainer.new()
	page.name = "Page_refugio"
	page.add_theme_constant_override("separation", 12)

	# Izquierda: habitantes + «Mientras no estabas».
	var left := _vbox(10)
	left.custom_minimum_size.x = 214
	page.add_child(left)
	var people_card := _card("PeopleCard", 12)
	left.add_child(people_card)
	var pv := _vbox(6)
	people_card.add_child(pv)
	pv.add_child(_caps("HABITANTES · ARRÁSTRALOS"))
	people_box = _vbox(5)
	pv.add_child(people_box)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(spacer)
	away_card = _card("AwayCard", 12)
	left.add_child(away_card)
	away_box = _vbox(4)
	away_card.add_child(away_box)

	# Centro: modo + corte lateral + cajón de construir.
	var center := _vbox(8)
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_child(center)
	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 6)
	center.add_child(mode_row)
	mode_live_button = _chip_button("Vivir", 13, 28)
	mode_live_button.name = "ModeLive"
	mode_live_button.pressed.connect(func() -> void: set_build_mode(false))
	mode_row.add_child(mode_live_button)
	mode_build_button = _chip_button("Decorar y construir · B", 13, 28)
	mode_build_button.name = "ModeBuild"
	mode_build_button.pressed.connect(func() -> void: set_build_mode(true))
	mode_row.add_child(mode_build_button)
	var hint := _label("A D cambiar de sala · W S piso · arrastra un habitante a un cuarto", 11, T.TEXT_MUTED)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.clip_text = true
	mode_row.add_child(hint)

	side_cut = SideCutViewScript.new()
	side_cut.name = "SideCut"
	side_cut.service = service
	side_cut.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side_cut.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side_cut.cell_clicked.connect(_on_cell_clicked)
	side_cut.character_dropped.connect(_on_character_dropped)
	center.add_child(side_cut)

	drawer = _card("BuildDrawer", 10)
	drawer.visible = false
	center.add_child(drawer)
	var dv := _vbox(8)
	drawer.add_child(dv)
	var cat_row := HBoxContainer.new()
	cat_row.add_theme_constant_override("separation", 4)
	dv.add_child(cat_row)
	for c in BUILD_CATEGORIES:
		var cb := _chip_button(c["label"], 12, 26)
		cb.name = "Cat_" + c["id"]
		var cid: String = c["id"]
		cb.pressed.connect(func() -> void: set_build_category(cid))
		cat_row.add_child(cb)
		drawer_cat_buttons[cid] = cb
	var dnote := _label("Los muebles son las estaciones: colócalos y el cuarto cambia de función", 11, T.TEXT_MUTED)
	dnote.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dnote.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	dnote.clip_text = true
	cat_row.add_child(dnote)
	var scroll := ScrollContainer.new()
	scroll.name = "DrawerScroll"
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.custom_minimum_size = Vector2(0, 72)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dv.add_child(scroll)
	drawer_cards = HBoxContainer.new()
	drawer_cards.add_theme_constant_override("separation", 8)
	scroll.add_child(drawer_cards)

	# Derecha: detalle + almacén central.
	var right := _vbox(10)
	right.custom_minimum_size.x = 262
	page.add_child(right)
	var detail_card := _card("DetailCard", 14)
	detail_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(detail_card)
	var dcol := _vbox(6)
	detail_card.add_child(dcol)
	detail_box = _vbox(6)
	detail_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dcol.add_child(detail_box)
	dig_button = _ghost_button("Excavar")
	dig_button.name = "DigButton"
	dig_button.pressed.connect(dig_selected)
	dcol.add_child(dig_button)
	upgrade_room_button = _ghost_button("Mejorar sala")
	upgrade_room_button.name = "UpgradeRoomButton"
	upgrade_room_button.pressed.connect(upgrade_selected_room)
	dcol.add_child(upgrade_room_button)
	place_button = _primary_button("Colocar aquí")
	place_button.name = "PlaceButton"
	place_button.pressed.connect(place_selected)
	dcol.add_child(place_button)

	var storage_card := PanelContainer.new()
	storage_card.name = "StorageCard"
	var ssb := T.box(T.SHELTER_SUB_BG, 12, 1, Color(T.ACCENT_DEFAULT, 0.55))
	ssb.set_content_margin_all(12)
	storage_card.add_theme_stylebox_override("panel", ssb)
	right.add_child(storage_card)
	var sv := _vbox(4)
	storage_card.add_child(sv)
	storage_box = _vbox(3)
	sv.add_child(storage_box)
	dividends_button = _ghost_button("Cobrar dividendos")
	dividends_button.name = "DividendsButton"
	dividends_button.pressed.connect(collect_dividends)
	sv.add_child(dividends_button)
	return page


# --------------------------------------------------------------------------
# Producción
# --------------------------------------------------------------------------
func _build_production_page() -> Control:
	var page := _card("Page_produccion", 18)
	var v := _vbox(10)
	page.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	v.add_child(head)
	head.add_child(_label("Cadenas de producción", 20, T.TEXT, "bold"))
	var sub := _label("por hora · se actualiza en vivo", 12, T.TEXT_SECONDARY)
	sub.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(sub)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	for lg in [["Fluye bien", T.SHELTER_FLOW, false], ["Atasco", T.SHELTER_JAM, false], ["En construcción", T.ACCENT_DEFAULT, true]]:
		var sw := SideCutViewScript.LegendSwatch.new()
		sw.color = lg[1]
		sw.dashed = lg[2]
		sw.custom_minimum_size = Vector2(22, 14)
		sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(sw)
		head.add_child(_label(lg[0], 11, T.TEXT_SECONDARY))
	chain_view = SideCutViewScript.ChainView.new()
	chain_view.name = "ChainView"
	chain_view.service = service
	chain_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(chain_view)
	jam_banner = PanelContainer.new()
	jam_banner.name = "JamBanner"
	v.add_child(jam_banner)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	jam_banner.add_child(row)
	jam_title = _label("", 13, T.SHELTER_JAM, "bold")
	row.add_child(jam_title)
	jam_message = _label("", 12, T.TEXT_KEY)
	jam_message.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	jam_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(jam_message)
	jam_buttons_box = HBoxContainer.new()
	jam_buttons_box.add_theme_constant_override("separation", 6)
	row.add_child(jam_buttons_box)
	return page


# --------------------------------------------------------------------------
# Expediciones
# --------------------------------------------------------------------------
func _build_expeditions_page() -> Control:
	var page := HBoxContainer.new()
	page.name = "Page_expediciones"
	page.add_theme_constant_override("separation", 12)

	var left := _card("ExpList", 14)
	left.custom_minimum_size.x = 280
	page.add_child(left)
	var lv := _vbox(8)
	left.add_child(lv)
	var lh := HBoxContainer.new()
	lv.add_child(lh)
	var cap := _caps("DISPONIBLES HOY")
	cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lh.add_child(cap)
	lh.add_child(_label("nuevas en 9 h", 11, T.TEXT_MUTED))
	exp_list_box = _vbox(8)
	lv.add_child(exp_list_box)

	var center := _card("ExpDetail", 18)
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_child(center)
	var cv := _vbox(8)
	center.add_child(cv)
	var th := HBoxContainer.new()
	th.add_theme_constant_override("separation", 10)
	cv.add_child(th)
	exp_title = _label("", 22, T.TEXT, "bold")
	th.add_child(exp_title)
	exp_zone = _label("", 13, T.ALLY)
	exp_zone.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	th.add_child(exp_zone)
	exp_desc = _label("", 13, T.TEXT_KEY)
	exp_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cv.add_child(exp_desc)
	cv.add_child(_caps("EQUIPO"))
	team_box = HBoxContainer.new()
	team_box.add_theme_constant_override("separation", 8)
	cv.add_child(team_box)
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 24)
	cv.add_child(stats)
	var sl := _vbox(4)
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats.add_child(sl)
	sl.add_child(_caps("PROBABILIDAD DE ÉXITO"))
	var crow := HBoxContainer.new()
	crow.add_theme_constant_override("separation", 10)
	sl.add_child(crow)
	chance_label = _label("", 38, T.ACCENT_DEFAULT, "bold")
	crow.add_child(chance_label)
	chance_alt_label = _label("", 12, T.TEXT_SECONDARY)
	chance_alt_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	crow.add_child(chance_alt_label)
	factors_box = _vbox(3)
	sl.add_child(factors_box)
	var sr := _vbox(4)
	sr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats.add_child(sr)
	sr.add_child(_caps("RECOMPENSAS PROBABLES"))
	rewards_box = _vbox(3)
	sr.add_child(rewards_box)
	cv.add_child(_caps("DURACIÓN"))
	var drow := HBoxContainer.new()
	cv.add_child(drow)
	durations_box = HBoxContainer.new()
	durations_box.add_theme_constant_override("separation", 6)
	durations_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	drow.add_child(durations_box)
	return_label = _label("", 12, T.TEXT_SECONDARY)
	drow.add_child(return_label)
	var note := PanelContainer.new()
	var nsb := T.box(T.SHELTER_SUB_BG, 10)
	nsb.set_content_margin_all(10)
	note.add_theme_stylebox_override("panel", nsb)
	cv.add_child(note)
	var note_l := _label("Recibirás 1 decisión durante el viaje, en el juego o en la app. Si no contestas, elige el camino seguro.", 12, T.TEXT_KEY)
	note_l.name = "SafeNote"
	note_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_child(note_l)
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cv.add_child(fill)
	send_button = _primary_button("Enviar expedición")
	send_button.name = "SendExpedition"
	send_button.custom_minimum_size.y = 42
	send_button.pressed.connect(send_selected_expedition)
	cv.add_child(send_button)

	var right := _card("ExpRunning", 14)
	right.custom_minimum_size.x = 300
	page.add_child(right)
	var rv := _vbox(8)
	right.add_child(rv)
	rv.add_child(_caps("EN CURSO"))
	running_box = _vbox(8)
	rv.add_child(running_box)
	rv.add_child(_spacer(Vector2(0, 4)))
	rv.add_child(_caps("TERMINADAS"))
	finished_box = _vbox(6)
	rv.add_child(finished_box)
	return page


# --------------------------------------------------------------------------
# Pispa
# --------------------------------------------------------------------------
func _build_pispa_page() -> Control:
	var page := HBoxContainer.new()
	page.name = "Page_pispa"
	page.add_theme_constant_override("separation", 12)

	var left := _card("PispaCard", 14)
	left.custom_minimum_size.x = 276
	page.add_child(left)
	var lv := _vbox(6)
	left.add_child(lv)
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", T.box(T.SHELTER_SUB_BG, 14))
	lv.add_child(frame)
	pispa_portrait = SideCutViewScript.MothPortrait.new()
	pispa_portrait.name = "PispaPortrait"
	pispa_portrait.custom_minimum_size = Vector2(0, 150)
	frame.add_child(pispa_portrait)
	var nrow := HBoxContainer.new()
	lv.add_child(nrow)
	var pname := _label("Pispa", 24, T.TEXT, "bold")
	pname.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nrow.add_child(pname)
	pispa_level_label = _label("", 12, T.TEXT_SECONDARY)
	pispa_level_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	nrow.add_child(pispa_level_label)
	pispa_species_label = _label("", 12, T.TEXT_SECONDARY)
	pispa_species_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lv.add_child(pispa_species_label)
	var xrow := HBoxContainer.new()
	lv.add_child(xrow)
	pispa_next_label = _label("", 11, T.TEXT_SECONDARY)
	pispa_next_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	xrow.add_child(pispa_next_label)
	pispa_xp_label = _label("", 11, T.TEXT_SECONDARY)
	xrow.add_child(pispa_xp_label)
	pispa_xp_bar = SideCutViewScript.FillBar.new()
	pispa_xp_bar.color = T.GOLD
	pispa_xp_bar.custom_minimum_size = Vector2(0, 6)
	lv.add_child(pispa_xp_bar)
	var arow := HBoxContainer.new()
	arow.add_theme_constant_override("separation", 8)
	lv.add_child(arow)
	arow.add_child(_label("Cariño", 12, T.TEXT_KEY))
	pispa_affection = SideCutViewScript.Pips.new()
	pispa_affection.custom_minimum_size = Vector2(120, 12)
	pispa_affection.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	arow.add_child(pispa_affection)
	pispa_affection_label = _label("", 12, Color("#ff8fb8"))
	arow.add_child(pispa_affection_label)
	lv.add_child(_caps("RASGOS"))
	pispa_traits_box = _vbox(6)
	lv.add_child(pispa_traits_box)
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lv.add_child(fill)
	pispa_follow = CheckButton.new()
	pispa_follow.name = "FollowToggle"
	pispa_follow.text = "Acompañarme en el mundo"
	pispa_follow.add_theme_font_size_override("font_size", 12)
	pispa_follow.toggled.connect(func(on: bool) -> void: service.set_pispa_follow(on))
	lv.add_child(pispa_follow)

	var center := _card("PispaCenter", 18)
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_child(center)
	var cv := _vbox(10)
	center.add_child(cv)
	var qh := HBoxContainer.new()
	cv.add_child(qh)
	var q := _label("¿Qué busca en el próximo viaje?", 19, T.TEXT, "bold")
	q.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	qh.add_child(q)
	qh.add_child(_label("sale sola cada vez que vuelve", 11, T.TEXT_SECONDARY))
	targets_box = HBoxContainer.new()
	targets_box.add_theme_constant_override("separation", 8)
	cv.add_child(targets_box)
	var trow := HBoxContainer.new()
	cv.add_child(trow)
	trip_label = _label("", 13, T.TEXT, "bold")
	trip_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	trow.add_child(trip_label)
	trip_time_label = _label("", 12, T.TEXT_SECONDARY)
	trow.add_child(trip_time_label)
	trip_bar = SideCutViewScript.FillBar.new()
	trip_bar.color = T.GOLD
	trip_bar.custom_minimum_size = Vector2(0, 6)
	cv.add_child(trip_bar)
	var brow := HBoxContainer.new()
	cv.add_child(brow)
	var bcap := _caps("BOLSA")
	bcap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	brow.add_child(bcap)
	bag_label = _label("", 12, T.GOLD)
	brow.add_child(bag_label)
	bag_grid = SideCutViewScript.BagGrid.new()
	bag_grid.name = "BagGrid"
	bag_grid.service = service
	bag_grid.custom_minimum_size = Vector2(0, 112)
	cv.add_child(bag_grid)
	var snack := PanelContainer.new()
	var snsb := T.box(T.SHELTER_SUB_BG, 10)
	snsb.set_content_margin_all(10)
	snack.add_theme_stylebox_override("panel", snsb)
	cv.add_child(snack)
	var snrow := HBoxContainer.new()
	snack.add_child(snrow)
	var snv := _vbox(2)
	snv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	snrow.add_child(snv)
	snv.add_child(_label("Darle un bocadillo", 13, T.TEXT, "bold"))
	snack_label = _label("", 11, T.TEXT_SECONDARY)
	snv.add_child(snack_label)
	feed_button = _ghost_button("Dar pan")
	feed_button.name = "FeedButton"
	feed_button.pressed.connect(func() -> void: _report(service.feed_pispa(), "Pispa come pan: el próximo viaje dura la mitad."))
	snrow.add_child(feed_button)
	var cfill := Control.new()
	cfill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cv.add_child(cfill)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	cv.add_child(actions)
	empty_bag_button = _primary_button("Vaciar bolsa al almacén")
	empty_bag_button.name = "EmptyBag"
	empty_bag_button.pressed.connect(empty_pispa_bag)
	actions.add_child(empty_bag_button)
	pet_button = _ghost_button("Acariciar")
	pet_button.name = "PetButton"
	pet_button.pressed.connect(func() -> void: _report(service.pet_pispa(), "A Pispa le encanta."))
	actions.add_child(pet_button)

	var right := _card("PispaRight", 14)
	right.custom_minimum_size.x = 300
	page.add_child(right)
	var rv := _vbox(8)
	right.add_child(rv)
	nest_box = _vbox(5)
	rv.add_child(nest_box)
	rv.add_child(_spacer(Vector2(0, 4)))
	rv.add_child(_caps("DIARIO DE HALLAZGOS"))
	journal_box = _vbox(6)
	rv.add_child(journal_box)
	return page


# --------------------------------------------------------------------------
# Mejoras
# --------------------------------------------------------------------------
func _build_upgrades_page() -> Control:
	var page := HBoxContainer.new()
	page.name = "Page_mejoras"
	page.add_theme_constant_override("separation", 12)

	var left := _card("UpgradePlan", 18)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_child(left)
	var lv := _vbox(10)
	left.add_child(lv)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	lv.add_child(head)
	head.add_child(_label("Plan de mejoras", 20, T.TEXT, "bold"))
	var sub := _label("ordenado según tus metas actuales", 12, T.TEXT_SECONDARY)
	sub.size_flags_vertical = Control.SIZE_SHRINK_END
	sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sub)
	goals_box = HBoxContainer.new()
	goals_box.add_theme_constant_override("separation", 6)
	head.add_child(goals_box)
	upgrade_grid = GridContainer.new()
	upgrade_grid.name = "UpgradeGrid"
	upgrade_grid.columns = 6
	upgrade_grid.add_theme_constant_override("h_separation", 6)
	upgrade_grid.add_theme_constant_override("v_separation", 6)
	lv.add_child(upgrade_grid)
	var legend := HBoxContainer.new()
	legend.add_theme_constant_override("separation", 14)
	lv.add_child(legend)
	for lg in [["Construido", T.SHELTER_DONE_BG], ["Siguiente recomendado", T.ACCENT_DEFAULT], ["Disponible", T.SHELTER_SUB_BG], ["Requiere nivel del refugio", T.SHELTER_LOCKED_BG]]:
		var sw := SideCutViewScript.Dot.new()
		sw.square = true
		sw.color = lg[1]
		sw.custom_minimum_size = Vector2(12, 12)
		sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		legend.add_child(sw)
		legend.add_child(_label(lg[0], 11, T.TEXT_SECONDARY))

	var right := _card("UpgradeSide", 14)
	right.custom_minimum_size.x = 320
	page.add_child(right)
	var rv := _vbox(8)
	right.add_child(rv)
	works_box = _vbox(6)
	rv.add_child(works_box)
	rv.add_child(_caps("POR QUÉ ESTE ORDEN"))
	why_box = _vbox(8)
	rv.add_child(why_box)
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rv.add_child(fill)
	level_title = _caps("")
	rv.add_child(level_title)
	var lrow := HBoxContainer.new()
	rv.add_child(lrow)
	var lt := _label("Mejoras hechas", 12, T.TEXT_SECONDARY)
	lt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lrow.add_child(lt)
	level_done_label = _label("", 12, T.TEXT_KEY)
	lrow.add_child(level_done_label)
	level_bar = SideCutViewScript.FillBar.new()
	level_bar.color = T.GOLD
	level_bar.custom_minimum_size = Vector2(0, 6)
	rv.add_child(level_bar)
	comfort_label = _label("", 12, T.TEXT_SECONDARY)
	comfort_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rv.add_child(comfort_label)
	new_floor_button = _ghost_button("Excavar un piso más")
	new_floor_button.name = "NewFloorButton"
	new_floor_button.pressed.connect(func() -> void: _report(service.dig_new_floor(), "Piso nuevo excavado: todo roca, a picar."))
	rv.add_child(new_floor_button)
	return page


# ==========================================================================
# Navegación
# ==========================================================================
func get_subtab_ids() -> Array[String]:
	var out: Array[String] = []
	for s in SUBTABS:
		out.append(s["id"])
	return out


func select_subtab(subtab_id: String) -> void:
	if subtab_id == "construir":
		select_subtab("refugio")
		set_build_mode(true)
		return
	if not pages.has(subtab_id):
		push_warning("[ShelterWindow] Sub-ventana desconocida: %s" % subtab_id)
		return
	current_subtab = subtab_id
	for id in pages:
		(pages[id] as Control).visible = id == subtab_id
	for id in subnav_buttons:
		(subnav_buttons[id] as Button).set_pressed_no_signal(id == subtab_id)
	menu_bar.set_active_tab(MENU_TAB_ID, subtab_id)
	refresh()
	subtab_changed.emit(subtab_id)


func set_build_mode(on: bool) -> void:
	build_mode = on
	if on and current_subtab != "refugio":
		current_subtab = "refugio"
		for id in pages:
			(pages[id] as Control).visible = id == "refugio"
		for id in subnav_buttons:
			(subnav_buttons[id] as Button).set_pressed_no_signal(id == "refugio")
	if on:
		# Al entrar, apunta al mejor hueco para lo que estás colocando.
		var spot: Dictionary = service.find_free_cell(placing_type)
		var cur: Dictionary = service.get_cell(selected_cell.x, selected_cell.y)
		if not spot.is_empty() and str(cur.get("state", "")) != "empty":
			selected_cell = Vector2i(int(spot["floor"]), int(spot["col"]))
	refresh()
	build_mode_changed.emit(on)


func set_build_category(cat: String) -> void:
	build_category = cat
	refresh()


func select_catalog_item(type: String) -> void:
	placing_type = type
	if build_mode:
		var cur: Dictionary = service.get_cell(selected_cell.x, selected_cell.y)
		var want_room: bool = service.decorations_catalog.has(type)
		if (want_room and str(cur.get("state", "")) != "room") or (not want_room and str(cur.get("state", "")) != "empty"):
			var spot: Dictionary = service.find_free_cell(type)
			if not want_room and not spot.is_empty():
				selected_cell = Vector2i(int(spot["floor"]), int(spot["col"]))
	refresh()


func select_cell(f: int, c: int) -> void:
	selected_cell = Vector2i(f, c)
	if selected_char != "" and not build_mode:
		var r: Dictionary = service.get_room_at(f, c)
		if not r.is_empty():
			assign_character(selected_char, r["uid"])
		selected_char = ""
	refresh()
	cell_selected.emit(f, c)


func select_character(char_id: String) -> void:
	selected_char = "" if selected_char == char_id else char_id
	if selected_char != "":
		var best: Dictionary = service.best_room_for(char_id)
		if not best.is_empty():
			_set_status("%s rinde más en %s%s. Pulsa un cuarto para asignarlo." % [
				service.get_character(char_id)["name"], service.room_name(best["uid"]), " (ideal +20 %)" if best["ideal"] else ""])
	refresh()


func assign_character(char_id: String, room_uid: String) -> Dictionary:
	var res: Dictionary = service.assign_worker(char_id, room_uid)
	if res.get("ok", false):
		_set_status("%s trabaja en %s · rinde %d %%%s" % [service.get_character(char_id)["name"], service.room_name(room_uid),
			int(round(float(res["efficiency"]) * 100.0)), " (ideal +20 %)" if res["ideal"] else ""])
	else:
		_set_status("No se puede asignar: %s" % _reason_text(str(res.get("reason", ""))))
	refresh()
	return res


func _on_cell_clicked(f: int, c: int) -> void:
	select_cell(f, c)


func _on_character_dropped(char_id: String, f: int, c: int) -> void:
	var r: Dictionary = service.get_room_at(f, c)
	selected_cell = Vector2i(f, c)
	if not r.is_empty():
		assign_character(char_id, r["uid"])


# ==========================================================================
# Acciones
# ==========================================================================
func collect_all() -> Dictionary:
	var res: Dictionary = service.collect_all()
	if res.get("ok", false):
		var parts := PackedStringArray()
		for it in res["items"]:
			parts.append("+%d %s" % [int(res["items"][it]), service.item_name(it).to_lower()])
		_set_status("Recogido: " + ", ".join(parts))
	else:
		_set_status("Todo al día: no hay nada que recoger.")
	refresh()
	return res


func collect_dividends() -> Dictionary:
	var res: Dictionary = service.collect_dividends()
	if res.get("ok", false):
		_set_status("+%d oro de dividendos en el almacén central." % int(res["amount"]))
	else:
		_set_status("No hay dividendos pendientes.")
	refresh()
	return res


func place_selected() -> Dictionary:
	var res: Dictionary = service.place_room(placing_type, selected_cell.x, selected_cell.y)
	if res.get("ok", false):
		if res.has("uid") and bool(res.get("fused", false)):
			_set_status("¡Sala doble! Dos %s juntas se fusionan: más capacidad y +25 %% de eficiencia." % service.catalog[placing_type]["name"])
		elif res.has("comfort"):
			_set_status("Decorado. Confort del depa: %d" % int(res["comfort"]))
		else:
			_set_status("Obra iniciada: %s · %s" % [service.catalog[placing_type]["name"], service.format_hours(float(res.get("build_hours", 0.0)))])
	else:
		_set_status("No cabe aquí: %s" % _reason_text(str(res.get("reason", ""))))
	room_placed.emit(res)
	refresh()
	return res


func dig_selected() -> Dictionary:
	var res: Dictionary = service.dig(selected_cell.x, selected_cell.y)
	if res.get("ok", false):
		if res.get("secret", false):
			_set_status("¡Sala secreta! «%s» entra en tu Códice (Por decidir)." % res["name"])
		else:
			_set_status("Hueco abierto en la roca. Ya puedes amueblarlo.")
	else:
		_set_status("No se puede excavar: %s" % _reason_text(str(res.get("reason", ""))))
	refresh()
	return res


func upgrade_selected_room() -> Dictionary:
	var r: Dictionary = service.get_room_at(selected_cell.x, selected_cell.y)
	if r.is_empty():
		return {"ok": false, "reason": "unknown_room"}
	var res: Dictionary = service.upgrade_room(r["uid"])
	_report(res, "Mejora en obra: sigue produciendo mientras tanto.")
	return res


func apply_fix(workshop_id: String, solution_id: String) -> Dictionary:
	var res: Dictionary = service.apply_fix(workshop_id, solution_id)
	_report(res, "Solución aplicada en 1 clic.")
	fix_applied.emit(workshop_id, solution_id, res)
	return res


func select_expedition(exp_id: String) -> void:
	selected_expedition = exp_id
	var e: Dictionary = service.get_expedition(exp_id)
	var durs: Array = e.get("durations", [2])
	if not durs.has(float(duration_h)) and not durs.has(duration_h):
		duration_h = int(durs[mini(1, durs.size() - 1)])
	team = team.filter(func(cid) -> bool: return _is_available(cid))
	if team.is_empty():
		var avail: Array = service.get_available_for_expedition()
		if not avail.is_empty():
			team = [avail[0]["id"]]
	refresh()


func set_team(ids: Array) -> void:
	team = ids.duplicate()
	refresh()


func add_team_member() -> void:
	for ch in service.get_available_for_expedition():
		if not team.has(ch["id"]):
			team.append(ch["id"])
			break
	refresh()


func set_duration(h: int) -> void:
	duration_h = h
	refresh()


func send_selected_expedition() -> Dictionary:
	var res: Dictionary = service.send_expedition(selected_expedition, team, duration_h, team_with_pispa)
	if res.get("ok", false):
		_set_status("Expedición en marcha · vuelve en %d h. Si no contestas, elige el camino seguro." % duration_h)
		team = []
		team_with_pispa = false
	else:
		_set_status("No se puede enviar: %s" % _reason_text(str(res.get("reason", ""))))
	expedition_sent.emit(res)
	select_expedition(selected_expedition)
	return res


func resolve_decision(run_id: String, option_id: String) -> Dictionary:
	var res: Dictionary = service.resolve_decision(run_id, option_id)
	_report(res, "Decisión enviada.")
	return res


func select_pispa_target(id: String) -> Dictionary:
	var res: Dictionary = service.set_pispa_target(id)
	_report(res, "Pispa buscará eso en el próximo viaje.")
	return res


func empty_pispa_bag() -> Dictionary:
	var res: Dictionary = service.empty_pispa_bag()
	_report(res, "Bolsa vaciada en el almacén central.")
	return res


func start_upgrade(row_id: String, tier: int) -> Dictionary:
	var res: Dictionary = service.start_upgrade(row_id, tier)
	_report(res, "Mejora en obra.")
	return res


func _report(res: Dictionary, ok_text: String) -> void:
	_set_status(ok_text if res.get("ok", false) else "No se puede: %s" % _reason_text(str(res.get("reason", ""))))
	refresh()


func _reason_text(reason: String) -> String:
	return {
		"cost": "faltan materiales", "rock": "es roca: excávala primero", "occupied": "ya hay una sala",
		"locked": "cimientos: sube el nivel de El Nido", "requires_level": "requiere más nivel del refugio",
		"not_rock": "no es roca", "full": "la sala está llena", "busy": "está ocupado",
		"no_slot": "ya hay 2 obras en marcha", "already_upgrading": "ya se está mejorando",
		"main_character": "tu personaje principal no viaja", "loaned": "es un personaje prestado",
		"no_characters": "añade a alguien al equipo", "pispa_busy": "Pispa ya está de viaje",
		"needs_room": "la decoración va dentro de un cuarto", "cooldown": "ya la acariciaste hace poco",
		"no_bread": "no te queda pan", "requires_nest": "mejora el nido", "previous_first": "antes, el nivel anterior",
		"no_space": "no hay huecos: excava", "nothing_to_collect": "nada pendiente",
	}.get(reason, reason)


func _is_available(cid: String) -> bool:
	for ch in service.get_available_for_expedition():
		if ch["id"] == cid:
			return true
	return false


func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not (event is InputEventKey) or not event.pressed or event.is_echo():
		return
	var k := event as InputEventKey
	if k.ctrl_pressed or k.alt_pressed or k.meta_pressed:
		return
	if current_subtab != "refugio":
		return
	var handled := true
	match k.keycode:
		KEY_B:
			set_build_mode(not build_mode)
		KEY_A:
			_move_selection(0, -1)
		KEY_D:
			_move_selection(0, 1)
		KEY_W:
			_move_selection(-1, 0)
		KEY_S:
			_move_selection(1, 0)
		KEY_SPACE:
			collect_all()
		_:
			handled = false
	if handled:
		get_viewport().set_input_as_handled()


func _move_selection(df: int, dc: int) -> void:
	var f := clampi(selected_cell.x + df, 0, service.get_floor_count() - 1)
	var c := clampi(selected_cell.y + dc, 0, service.cols - 1)
	var r: Dictionary = service.get_room_at(f, c)
	if dc != 0 and not r.is_empty() and int(r["col"]) == selected_cell.y and int(r["floor"]) == f and int(r["size"]) > 1 and dc > 0:
		c = clampi(int(r["col"]) + int(r["size"]), 0, service.cols - 1)
	select_cell(f, c)


# ==========================================================================
# Refresco
# ==========================================================================
func refresh() -> void:
	if not _built or service == null:
		return
	for it in resource_labels:
		(resource_labels[it] as Label).text = T.format_amount(service.get_item(it))
	var n: int = service.get_collectables().size()
	collect_button.text = "Recoger todo · %d" % n if n > 0 else "Todo al día"
	collect_button.disabled = n == 0
	if menu_bar and menu_bar.has_method("set_currencies"):
		menu_bar.set_currencies(service.get_item("oro"), 340)
	match current_subtab:
		"refugio":
			_refresh_shelter()
		"produccion":
			_refresh_production()
		"expediciones":
			_refresh_expeditions()
		"pispa":
			_refresh_pispa()
		"mejoras":
			_refresh_upgrades()


func _refresh_shelter() -> void:
	mode_live_button.set_pressed_no_signal(not build_mode)
	mode_build_button.set_pressed_no_signal(build_mode)
	drawer.visible = build_mode
	side_cut.build_mode = build_mode
	side_cut.selected_cell = selected_cell
	side_cut.placing_type = placing_type if build_mode else ""
	side_cut.selected_char = selected_char
	side_cut.queue_redraw()
	_refresh_people()
	_refresh_away()
	_refresh_detail()
	_refresh_storage()
	if build_mode:
		_refresh_drawer()


func _refresh_people() -> void:
	_clear(people_box)
	for ch in service.get_characters():
		var row := SideCutViewScript.ChibiRow.new()
		row.name = "Char_" + str(ch["id"])
		row.char_id = ch["id"]
		row.custom_minimum_size = Vector2(0, 42)
		row.toggle_mode = true
		row.set_pressed_no_signal(selected_char == ch["id"])
		var sb := T.box(T.SHELTER_SUB_BG, 10)
		sb.content_margin_left = 8
		row.add_theme_stylebox_override("normal", sb)
		var hover := sb.duplicate() as StyleBoxFlat
		hover.bg_color = T.SLOT_READY
		row.add_theme_stylebox_override("hover", hover)
		var on := T.box(T.POWERS_CHIP_ON, 10, 1, T.ACCENT_DEFAULT)
		row.add_theme_stylebox_override("pressed", on)
		row.add_theme_stylebox_override("hover_pressed", on)
		row.add_theme_stylebox_override("focus", T.box(Color.TRANSPARENT, 10, 1, Color(T.ACCENT_DEFAULT, 0.6)))
		var cid: String = ch["id"]
		row.pressed.connect(func() -> void: select_character(cid))
		var h := HBoxContainer.new()
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_theme_constant_override("separation", 8)
		h.set_anchors_preset(Control.PRESET_FULL_RECT)
		h.offset_left = 8
		row.add_child(h)
		var av := SideCutViewScript.Avatar.new()
		av.color = Color(str(ch.get("color", "#9aa6ae")))
		av.letter = str(ch["name"]).substr(0, 1)
		av.custom_minimum_size = Vector2(26, 26)
		av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(av)
		var v := _vbox(0)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(v)
		v.add_child(_label(str(ch["name"]), 13, T.TEXT, "bold"))
		var st := _char_status(ch)
		v.add_child(_label(st[0], 11, st[1]))
		people_box.add_child(row)
	# Pispa también vive aquí (no es obrera).
	var prow := HBoxContainer.new()
	prow.add_theme_constant_override("separation", 8)
	var pav := SideCutViewScript.Avatar.new()
	pav.color = T.GOLD
	pav.letter = "P"
	pav.custom_minimum_size = Vector2(26, 26)
	prow.add_child(pav)
	var pv := _vbox(0)
	prow.add_child(pv)
	pv.add_child(_label("Pispa", 13, T.TEXT, "bold"))
	var trip: Dictionary = service.pispa.get("trip", {})
	pv.add_child(_label("Recolectando · %s" % service.format_hours(maxf(0.0, float(trip["end_h"]) - service.clock_h)) if not trip.is_empty() else "En el nido", 11, T.TEXT_SECONDARY))
	people_box.add_child(prow)


func _char_status(ch: Dictionary) -> Array:
	match str(ch["status"]):
		"expedition":
			for run in service.active_expeditions:
				if (run["chars"] as Array).has(ch["id"]):
					return ["Expedición · %s" % service.format_hours(maxf(0.0, float(run["end_h"]) - service.clock_h)), T.GOLD]
			return ["Expedición", T.GOLD]
		"working":
			var r: Dictionary = service.get_room(str(ch["room"]))
			var ideal: bool = service.is_ideal(ch["id"], r.get("type", ""))
			var txt := "%s · %s" % [service.room_name(r["uid"]), "ideal +20 %" if ideal else "%d %%" % int(round(service.worker_efficiency(ch["id"], r["type"]) * 100.0))]
			if float(ch.get("loan_hours", 0.0)) > 0.0:
				txt += " · %s" % service.format_hours(float(ch["loan_hours"]))
			return [txt, T.ALLY if float(ch.get("loan_hours", 0.0)) > 0.0 else T.ACCENT_DEFAULT]
		"returned":
			return ["Volvió con su dueño", T.TEXT_MUTED]
	var lbl: String = service.ideal_label(ch["id"])
	return ["Descansando · " + lbl if lbl != "" else "Descansando", T.TEXT_SECONDARY]


func _refresh_away() -> void:
	_clear(away_box)
	away_box.add_child(_caps("MIENTRAS NO ESTABAS"))
	var lines: Array = service.away_log
	if lines.is_empty():
		lines = ["Pispa trajo una Pluma de grieta", "Brisa te prestó a Lía 8 h", "Torq espera que elijas camino"]
	for i in range(maxi(0, lines.size() - 4), lines.size()):
		var l := _label("•  " + str(lines[i]), 11, T.TEXT_KEY)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		away_box.add_child(l)


func _refresh_detail() -> void:
	_clear(detail_box)
	dig_button.visible = false
	upgrade_room_button.visible = false
	place_button.visible = false
	var f := selected_cell.x
	var c := selected_cell.y
	if build_mode:
		_refresh_build_detail(f, c)
		return
	var view: Dictionary = service.get_cell_view(f, c)
	if view.is_empty():
		return
	if view["state"] == "room":
		var r: Dictionary = service.get_room(view["room"])
		var e: Dictionary = service.catalog.get(r["type"], {})
		_detail_title(service.room_name(r["uid"]), "nivel %d" % int(r["level"]))
		var desc := _label(str(e.get("desc", "")), 12, T.TEXT_KEY)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		detail_box.add_child(desc)
		if r["status"] == "building":
			detail_box.add_child(_label("En obra · %s" % service.format_hours(float(r["build_left_h"])), 12, T.ACCENT_DEFAULT, "semibold"))
		if bool(r["fused"]):
			detail_box.add_child(_label("Sala doble · +25 %% eficiencia · capacidad %d" % service.room_capacity(r["uid"]), 12, T.ACCENT_DEFAULT))
		var workers: Array = r["workers"]
		detail_box.add_child(_caps("TRABAJAN AQUÍ · %d / %d" % [workers.size(), service.room_capacity(r["uid"])]))
		if workers.is_empty():
			detail_box.add_child(_label("Nadie. Arrastra un habitante o elígelo a la izquierda.", 11, T.TEXT_MUTED))
		for wid in workers:
			var eff: float = service.worker_efficiency(wid, r["type"])
			var ideal: bool = service.is_ideal(wid, r["type"])
			detail_box.add_child(_kv(str(service.get_character(wid)["name"]), "ideal +20 %" if ideal else "%d %%" % int(round(eff * 100.0)), T.ACCENT_DEFAULT if ideal else T.TEXT_KEY))
		var nb: Dictionary = service.get_neighbor_bonus(r["uid"])
		if int(nb["pct"]) > 0:
			var names := PackedStringArray()
			for s in nb["sources"]:
				names.append("%s +%d %%" % [s["name"], int(s["pct"])])
			var nl := _label("Vecindad: " + ", ".join(names), 12, T.ACCENT_DEFAULT)
			nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			detail_box.add_child(nl)
		var ready: int = service.get_ready_count(r["uid"])
		if ready > 0:
			detail_box.add_child(_label("%d listas para recoger" % ready, 12, T.GOLD, "semibold"))
		if float(r["upgrade_left_h"]) > 0.0:
			detail_box.add_child(_label("Mejorando a nivel %d · %s" % [int(r["level"]) + 1, service.format_hours(float(r["upgrade_left_h"]))], 12, T.GOLD))
		elif r["status"] == "ready" and not bool(e.get("secret", false)):
			detail_box.add_child(_caps("MEJORAR A NIVEL %d · %s" % [int(r["level"]) + 1, service.format_hours(service.room_upgrade_hours(r["uid"])).to_upper()]))
			var cost: Dictionary = service.room_upgrade_cost(r["uid"])
			for k in cost:
				detail_box.add_child(_cost_row(k, int(cost[k])))
			upgrade_room_button.visible = true
			upgrade_room_button.text = "Mejorar a nivel %d" % (int(r["level"]) + 1)
			upgrade_room_button.disabled = not service.can_afford(cost)
	else:
		_detail_title(str(view.get("title", "")), "")
		var hint := _label(str(view.get("hint", "")), 12, T.SHELTER_SECRET if view["state"] == "secret" else T.TEXT_KEY)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		detail_box.add_child(hint)
		if view["state"] in ["rock", "secret"]:
			var chk: Dictionary = service.can_dig(f, c)
			dig_button.visible = true
			dig_button.text = "Excavar (¿qué habrá?)" if view["state"] == "secret" else "Excavar"
			dig_button.disabled = not chk.get("ok", false)
			var cost2: Dictionary = service.get_dig_cost(f)
			for k in cost2:
				detail_box.add_child(_cost_row(k, int(cost2[k])))
		elif view["state"] == "empty":
			detail_box.add_child(_label("Pulsa B para amueblarlo.", 12, T.TEXT_SECONDARY))
	# Sugerencia ligada a una meta real (§2.5).
	if selected_char != "":
		var best: Dictionary = service.best_room_for(selected_char)
		if not best.is_empty():
			detail_box.add_child(_spacer(Vector2(0, 4)))
			detail_box.add_child(_caps("TE CONVIENE"))
			var sl := _label("%s rinde más en %s%s." % [service.get_character(selected_char)["name"], service.room_name(best["uid"]), " · ideal +20 %" if best["ideal"] else ""], 12, T.ACCENT_DEFAULT)
			sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			detail_box.add_child(sl)


func _refresh_build_detail(f: int, c: int) -> void:
	var is_decor: bool = service.decorations_catalog.has(placing_type)
	var e: Dictionary = service.decorations_catalog.get(placing_type, {}) if is_decor else service.catalog.get(placing_type, {})
	_detail_title(str(e.get("name", placing_type)), "decoración" if is_decor else "1 cuarto")
	var desc := _label(str(e.get("desc", "")), 12, T.TEXT_KEY)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_box.add_child(desc)
	var pv: Dictionary = service.preview_placement(placing_type, f, c)
	if not is_decor:
		detail_box.add_child(_caps("COSTE · %s CON 1 HABITANTE" % service.format_hours(float(e.get("build_hours", 0))).to_upper()))
	var cost: Dictionary = e.get("cost", {})
	for k in cost:
		detail_box.add_child(_cost_row(k, int(cost[k])))
	if not is_decor:
		detail_box.add_child(_kv("Con Lía ayudando", service.format_hours(float(pv.get("build_hours_helped", 0.0))), T.ALLY))
	for s in pv.get("sources", []):
		detail_box.add_child(_label("+%d %% por estar junto a %s" % [int(s["pct"]), s["name"]], 12, T.ACCENT_DEFAULT))
	if bool(pv.get("merge", false)):
		detail_box.add_child(_label("Se fusiona con la sala de al lado: sala doble (+25 %)", 12, T.ACCENT_DEFAULT, "semibold"))
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_box.add_child(fill)
	var cozy := PanelContainer.new()
	var csb := T.box(T.SHELTER_SUB_BG, 12, 1, Color(T.ACCENT_DEFAULT, 0.7))
	csb.set_content_margin_all(10)
	cozy.add_theme_stylebox_override("panel", csb)
	detail_box.add_child(cozy)
	var cv := _vbox(3)
	cozy.add_child(cv)
	cv.add_child(_caps("ACOGEDOR"))
	cv.add_child(_label("Confort del depa: %d → %d" % [int(pv["comfort_before"]), int(pv["comfort_after"])], 14, T.TEXT, "bold"))
	var cl := _label("Decorar sube el confort: tus personajes descansan más rápido y producen un poco más.", 11, T.TEXT_SECONDARY)
	cl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cv.add_child(cl)
	place_button.visible = true
	place_button.disabled = not bool(pv["fits"])
	place_button.text = "Colocar aquí" if pv["fits"] else "No cabe: %s" % _reason_text(str(pv["reason"]))


func _refresh_drawer() -> void:
	for id in drawer_cat_buttons:
		(drawer_cat_buttons[id] as Button).set_pressed_no_signal(id == build_category)
	_clear(drawer_cards)
	catalog_cards.clear()
	for e in service.get_buildable_catalog(build_category):
		var b := Button.new()
		b.name = "Item_" + str(e["type"])
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_ALL
		b.custom_minimum_size = Vector2(150, 70)
		b.set_pressed_no_signal(e["type"] == placing_type)
		var sb := T.box(T.SHELTER_SUB_BG, 10)
		var on := T.box(T.POWERS_CHIP_ON, 10, 2, T.ACCENT_DEFAULT)
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", T.box(T.SLOT_READY, 10))
		b.add_theme_stylebox_override("pressed", on)
		b.add_theme_stylebox_override("hover_pressed", on)
		b.add_theme_stylebox_override("focus", T.box(Color.TRANSPARENT, 10, 1, Color(T.ACCENT_DEFAULT, 0.6)))
		b.disabled = bool(e.get("locked", false))
		var t: String = e["type"]
		b.pressed.connect(func() -> void: select_catalog_item(t))
		var v := _vbox(1)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.set_anchors_preset(Control.PRESET_FULL_RECT)
		v.offset_left = 10
		v.offset_top = 7
		v.offset_right = -8
		b.add_child(v)
		var dim := bool(e.get("locked", false))
		v.add_child(_label(str(e["name"]), 13, T.TEXT_MUTED if dim else T.TEXT, "bold"))
		var d := _label(str(e.get("desc", "")), 10, T.TEXT_MUTED)
		d.clip_text = true
		v.add_child(d)
		var cost_txt: String = "El Nido nivel %d" % int(e.get("requires_level", 0)) if dim else service.format_cost(e.get("cost", {}))
		v.add_child(_label(cost_txt, 11, T.TEXT_MUTED if dim else (T.TEXT_KEY if e["affordable"] else T.SHELTER_JAM), "semibold"))
		drawer_cards.add_child(b)
		catalog_cards[t] = b
	if catalog_cards.has(placing_type):
		var sc := drawer_cards.get_parent() as ScrollContainer
		var sel: Control = catalog_cards[placing_type]
		sc.ensure_control_visible.call_deferred(sel)


func _refresh_storage() -> void:
	_clear(storage_box)
	var head := HBoxContainer.new()
	storage_box.add_child(head)
	var cap := _caps("ALMACÉN CENTRAL")
	cap.add_theme_color_override("font_color", T.ACCENT_DEFAULT)
	cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(cap)
	head.add_child(_label("%d / %d" % [service.get_storage_used(), service.get_storage_capacity()], 11, T.SHELTER_JAM if service.is_storage_full() else T.TEXT_SECONDARY))
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	storage_box.add_child(top)
	for it in ["tonicos", "lingotes", "pan", "hierbas"]:
		top.add_child(_label("%s %d" % [service.item_name(it).split(" ")[0], service.get_item(it)], 11, T.TEXT_KEY))
	var totals: Dictionary = service.get_dividend_totals()
	var title := _label("Dividendos de tus inversiones", 12, T.TEXT, "bold")
	storage_box.add_child(title)
	if totals.is_empty():
		storage_box.add_child(_label("Aún no has cobrado aquí.", 11, T.TEXT_MUTED))
	for src in totals:
		storage_box.add_child(_kv(str(src), "+%s oro" % T.format_amount(int(totals[src])), T.GOLD))
	var pend: int = service.pending_dividends()
	dividends_button.text = "Cobrar dividendos · %d" % pend if pend > 0 else "Sin dividendos pendientes"
	dividends_button.disabled = pend <= 0


func _refresh_production() -> void:
	chain_view.queue_redraw()
	_clear(jam_buttons_box)
	fix_buttons.clear()
	var jams: Array = service.diagnose()
	if jams.is_empty():
		jam_banner.add_theme_stylebox_override("panel", _banner_box(T.ACCENT_DEFAULT))
		jam_title.text = "Todo fluye"
		jam_title.add_theme_color_override("font_color", T.ACCENT_DEFAULT)
		jam_message.text = "Ninguna cadena atascada. Lo que sobra va al almacén central."
		return
	var b: Dictionary = jams[0]
	jam_banner.add_theme_stylebox_override("panel", _banner_box(T.SHELTER_JAM))
	jam_title.text = "Atasco en la %s" % b["name"] if str(b["name"]).ends_with("a") else "Atasco en %s" % b["name"]
	jam_title.add_theme_color_override("font_color", T.SHELTER_JAM)
	jam_message.text = str(b["message"]) + ("" if jams.size() == 1 else "  (+%d más)" % (jams.size() - 1))
	for s in b["solutions"]:
		var btn := _ghost_button(str(s["label"]))
		btn.name = "Fix_" + str(s["id"])
		if bool(s.get("primary", false)):
			btn.add_theme_color_override("font_color", T.ACCENT_DEFAULT)
		btn.disabled = bool(b["resolving"])
		var wid: String = b["workshop"]
		var sid: String = s["id"]
		btn.pressed.connect(func() -> void: apply_fix(wid, sid))
		jam_buttons_box.add_child(btn)
		fix_buttons[sid] = btn


func _refresh_expeditions() -> void:
	if team.is_empty() and str(selected_expedition) != "":
		var avail: Array = service.get_available_for_expedition()
		if not avail.is_empty():
			team = [avail[0]["id"]]
	_clear(exp_list_box)
	for e in service.expeditions_catalog:
		var b := Button.new()
		b.name = "Exp_" + str(e["id"])
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(0, 80)
		b.set_pressed_no_signal(e["id"] == selected_expedition)
		b.add_theme_stylebox_override("normal", T.box(T.SHELTER_SUB_BG, 12))
		b.add_theme_stylebox_override("hover", T.box(T.SLOT_READY, 12))
		var on := T.box(T.SHELTER_SUB_BG, 12, 2, T.ACCENT_DEFAULT)
		b.add_theme_stylebox_override("pressed", on)
		b.add_theme_stylebox_override("hover_pressed", on)
		var eid: String = e["id"]
		b.pressed.connect(func() -> void: select_expedition(eid))
		var v := _vbox(2)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.set_anchors_preset(Control.PRESET_FULL_RECT)
		v.offset_left = 12
		v.offset_top = 10
		v.offset_right = -10
		b.add_child(v)
		var h := HBoxContainer.new()
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(h)
		var nm := _label(str(e["name"]), 14, T.TEXT, "bold")
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(nm)
		h.add_child(_risk_tag(str(e["risk"])))
		var durs := PackedStringArray()
		for d in e["durations"]:
			durs.append(str(int(d)))
		var rew := PackedStringArray()
		for it in e["rewards"]:
			rew.append(service.item_name(it).to_lower())
		v.add_child(_label("%s h · %s" % ["–".join(durs), ", ".join(rew)], 11, T.TEXT_SECONDARY))
		var rec := "Cualquier personaje" if (e.get("recommended_roles", []) as Array).is_empty() else "Recomendado: " + " o ".join(PackedStringArray(e["recommended_roles"]))
		if int(e.get("min_chars", 1)) > 1:
			rec = "Nivel %d+ · %d personajes" % [int(e["recommended_level"]), int(e["min_chars"])]
		v.add_child(_label(rec, 11, T.TEXT_KEY))
		exp_list_box.add_child(b)

	var e2: Dictionary = service.get_expedition(selected_expedition)
	exp_title.text = str(e2.get("name", ""))
	exp_zone.text = "%s · riesgo %s" % [e2.get("zone", ""), e2.get("risk", "")]
	exp_desc.text = str(e2.get("desc", ""))
	_clear(team_box)
	for cid in team:
		var ch: Dictionary = service.get_character(cid)
		var card := Button.new()
		card.name = "Team_" + str(cid)
		card.custom_minimum_size = Vector2(190, 58)
		var on2 := T.box(T.SHELTER_SUB_BG, 12, 2, T.ACCENT_DEFAULT)
		card.add_theme_stylebox_override("normal", on2)
		card.add_theme_stylebox_override("hover", on2)
		card.add_theme_stylebox_override("pressed", on2)
		card.tooltip_text = "Quitar del equipo"
		var rid: String = cid
		card.pressed.connect(func() -> void:
			team.erase(rid)
			refresh())
		var hh := HBoxContainer.new()
		hh.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hh.set_anchors_preset(Control.PRESET_FULL_RECT)
		hh.offset_left = 12
		hh.add_theme_constant_override("separation", 10)
		card.add_child(hh)
		var av := SideCutViewScript.Avatar.new()
		av.color = Color(str(ch.get("color", "#9aa6ae")))
		av.letter = str(ch.get("name", "?")).substr(0, 1)
		av.custom_minimum_size = Vector2(30, 30)
		av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hh.add_child(av)
		var vv := _vbox(0)
		vv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hh.add_child(vv)
		vv.add_child(_label(str(ch.get("name", "")), 13, T.TEXT, "bold"))
		vv.add_child(_label("%s · nivel %d" % [ch.get("role", ""), int(ch.get("level", 1))], 11, T.TEXT_SECONDARY))
		team_box.add_child(card)
	if team.size() < 3:
		var add := _ghost_button("+ Añadir personaje")
		add.name = "AddMember"
		add.custom_minimum_size = Vector2(170, 58)
		add.disabled = service.get_available_for_expedition().size() <= team.size()
		add.pressed.connect(add_team_member)
		team_box.add_child(add)
	var pis := _chip_button("+ Pispa (opcional)\n+10 % botín, pero no recolecta", 11, 58)
	pis.name = "PispaToggle"
	pis.set_pressed_no_signal(team_with_pispa)
	pis.toggled.connect(func(on: bool) -> void:
		team_with_pispa = on
		refresh())
	team_box.add_child(pis)

	var ch_res: Dictionary = service.success_chance(selected_expedition, team, team_with_pispa)
	chance_label.text = "%d %%" % int(ch_res["pct"]) if not team.is_empty() else "—"
	var alt := ""
	if team.size() == 1:
		var others: Array = service.get_available_for_expedition().filter(func(c) -> bool: return not team.has(c["id"]))
		if not others.is_empty():
			alt = "con 2 personajes: %d %%" % int(service.success_chance(selected_expedition, [team[0], others[0]["id"]])["pct"])
	chance_alt_label.text = alt
	_clear(factors_box)
	for fct in ch_res["factors"]:
		var v2 := int(fct["value"])
		factors_box.add_child(_kv(str(fct["label"]), ("+%d" % v2) if v2 > 0 else str(v2), T.ACCENT_DEFAULT if v2 > 0 else T.SHELTER_JAM))
	_clear(rewards_box)
	for it in e2.get("rewards", {}):
		var pair: Array = e2["rewards"][it]
		rewards_box.add_child(_kv(service.item_name(it), "%d–%d" % [int(pair[0]), int(pair[1])], T.TEXT))
	var rare: Dictionary = e2.get("rare", {})
	if not rare.is_empty():
		rewards_box.add_child(_kv(service.item_name(rare["item"]), "%d %%" % int(rare["pct"]), T.SHELTER_SECRET))
	if not team.is_empty():
		var lv_txt := PackedStringArray()
		for cid in team:
			lv_txt.append(str(service.get_character(cid).get("name", "")))
		var xp: int = service.expedition_xp(selected_expedition, duration_h)
		var lvl: int = int(service.get_character(team[0]).get("level", 1))
		rewards_box.add_child(_kv("XP para " + " y ".join(lv_txt), "≈ %.1f nivel" % (float(xp) / float(service.xp_to_next(lvl))), T.SHELTER_SECRET))
	_clear(durations_box)
	for d in e2.get("durations", []):
		var dh := int(d)
		var lbl := "%d h" % dh
		if dh == 4:
			lbl += " · más botín"
		elif dh == 8:
			lbl += " · noche"
		var db := _chip_button(lbl, 12, 30)
		db.name = "Dur_%d" % dh
		db.set_pressed_no_signal(dh == duration_h)
		db.pressed.connect(func() -> void: set_duration(dh))
		durations_box.add_child(db)
	return_label.text = "Vuelve en %d h" % duration_h
	send_button.disabled = team.is_empty()

	_clear(running_box)
	decision_buttons.clear()
	if service.active_expeditions.is_empty():
		running_box.add_child(_label("Nadie de viaje.", 12, T.TEXT_MUTED))
	for run in service.active_expeditions:
		var names := PackedStringArray()
		for cid in run["chars"]:
			names.append(str(service.get_character(cid).get("name", "")))
		running_box.add_child(_kv("%s · %s" % [" y ".join(names), run["name"]], service.format_hours(maxf(0.0, float(run["end_h"]) - service.clock_h)), T.TEXT_SECONDARY))
		var bar := SideCutViewScript.FillBar.new()
		bar.color = T.ALLY
		bar.value = service.run_progress(run)
		bar.custom_minimum_size = Vector2(0, 5)
		running_box.add_child(bar)
	for d in service.get_pending_decisions():
		var ev: Dictionary = d["event"]
		var card2 := PanelContainer.new()
		card2.name = "Decision_" + str(d["run_id"])
		var dsb := T.box(Color(T.GOLD, 0.06), 12, 2, T.GOLD)
		dsb.set_content_margin_all(12)
		card2.add_theme_stylebox_override("panel", dsb)
		running_box.add_child(card2)
		var dv := _vbox(6)
		card2.add_child(dv)
		var dh2 := HBoxContainer.new()
		dv.add_child(dh2)
		var dt := _label(str(ev["title"]), 14, T.GOLD, "bold")
		dt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		dh2.add_child(dt)
		dh2.add_child(_label("expira en %s" % service.format_hours(float(d["expires_in_h"])), 11, T.TEXT_SECONDARY))
		var txt := _label(str(ev["text"]), 12, T.TEXT_KEY)
		txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		dv.add_child(txt)
		for o in ev["options"]:
			var ob := Button.new()
			ob.name = "Opt_" + str(o["id"])
			ob.custom_minimum_size = Vector2(0, 38)
			ob.alignment = HORIZONTAL_ALIGNMENT_LEFT
			ob.text = "  %s" % o["label"]
			ob.add_theme_font_override("font", T.font("semibold"))
			ob.add_theme_font_size_override("font_size", 13)
			ob.add_theme_stylebox_override("normal", T.box(T.SHELTER_SUB_BG, 10, 1, T.BUTTON_BORDER))
			ob.add_theme_stylebox_override("hover", T.box(T.SLOT_READY, 10, 1, T.BUTTON_BORDER))
			ob.add_theme_stylebox_override("pressed", T.box(T.SLOT_READY, 10, 1, T.GOLD))
			var tag := _label(str(o["detail"]) + "  ", 11, T.ACCENT_DEFAULT if bool(o.get("safe", false)) else T.GOLD, "semibold")
			tag.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
			tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			tag.offset_left = -170
			tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
			ob.add_child(tag)
			var rid2: String = d["run_id"]
			var oid: String = o["id"]
			ob.pressed.connect(func() -> void: resolve_decision(rid2, oid))
			dv.add_child(ob)
			decision_buttons[oid] = ob
	_clear(finished_box)
	var shown := 0
	for fin in service.finished_expeditions:
		if shown >= 4:
			break
		shown += 1
		var oc := str(fin.get("outcome", "success"))
		var row := _vbox(1)
		var hr := HBoxContainer.new()
		row.add_child(hr)
		var fl := _label(str(fin.get("name", "")), 13, T.TEXT, "bold")
		fl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		fl.clip_text = true
		hr.add_child(fl)
		var oc_txt: String = {"success": "Éxito", "partial": "Éxito parcial", "fail": "Fallida"}.get(oc, oc)
		hr.add_child(_label(oc_txt + (" · auto" if bool(fin.get("auto", false)) else ""), 12, {"success": T.HEALTH, "partial": T.GOLD, "fail": T.SHELTER_JAM}.get(oc, T.TEXT)))
		var sm := _label(str(fin.get("summary", "")), 11, T.TEXT_SECONDARY)
		sm.clip_text = true
		row.add_child(sm)
		finished_box.add_child(row)


func _refresh_pispa() -> void:
	var p: Dictionary = service.pispa
	pispa_level_label.text = "nivel %d" % int(p["level"])
	pispa_species_label.text = str(p.get("species", ""))
	pispa_next_label.text = "Hasta nivel %d" % (int(p["level"]) + 1)
	pispa_xp_label.text = "%d / %d" % [int(p["xp"]), int(p["xp_next"])]
	pispa_xp_bar.value = float(p["xp"]) / maxf(1.0, float(p["xp_next"]))
	pispa_affection.value = int(p["affection"])
	pispa_affection.queue_redraw()
	pispa_affection_label.text = service.affection_label(int(p["affection"]))
	_clear(pispa_traits_box)
	for tr in p.get("traits", []):
		var card := PanelContainer.new()
		var sb := T.box(T.SHELTER_SUB_BG, 10)
		sb.set_content_margin_all(10)
		card.add_theme_stylebox_override("panel", sb)
		var v := _vbox(1)
		card.add_child(v)
		v.add_child(_label(str(tr["name"]), 13, T.TEXT, "bold"))
		v.add_child(_label(str(tr["desc"]), 11, T.TEXT_SECONDARY))
		pispa_traits_box.add_child(card)
	pispa_follow.set_pressed_no_signal(bool(p.get("follow_in_world", false)))

	_clear(targets_box)
	target_buttons.clear()
	for t in service.get_pispa_targets():
		if bool(t["locked"]) and t["id"] != p["target"]:
			continue
		var b := Button.new()
		b.name = "Target_" + str(t["id"])
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(0, 86)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.set_pressed_no_signal(bool(t["selected"]))
		b.add_theme_stylebox_override("normal", T.box(T.SHELTER_SUB_BG, 12))
		b.add_theme_stylebox_override("hover", T.box(T.SLOT_READY, 12))
		var on := T.box(T.SHELTER_SUB_BG, 12, 2, T.ACCENT_DEFAULT)
		b.add_theme_stylebox_override("pressed", on)
		b.add_theme_stylebox_override("hover_pressed", on)
		var tid: String = t["id"]
		b.pressed.connect(func() -> void: select_pispa_target(tid))
		var v2 := _vbox(3)
		v2.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v2.set_anchors_preset(Control.PRESET_FULL_RECT)
		v2.offset_left = 14
		v2.offset_top = 12
		b.add_child(v2)
		var h := HBoxContainer.new()
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_theme_constant_override("separation", 8)
		v2.add_child(h)
		var dot := SideCutViewScript.Dot.new()
		dot.diamond = true
		dot.color = Color(str(t.get("color", "#46e3c1")))
		dot.custom_minimum_size = Vector2(12, 12)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(dot)
		h.add_child(_label(str(t["name"]), 15, T.TEXT, "bold"))
		v2.add_child(_label(str(t["desc"]), 11, T.TEXT_SECONDARY))
		if bool(t["mission_star"]):
			v2.add_child(_label(str(t["mission_text"]), 11, T.ACCENT_DEFAULT, "semibold"))
		elif str(t.get("note", "")) != "":
			v2.add_child(_label(str(t["note"]), 11, T.TEXT_SECONDARY))
		targets_box.add_child(b)
		target_buttons[tid] = b
	var trip: Dictionary = p.get("trip", {})
	if trip.is_empty():
		trip_label.text = "En el nido" if not service.is_pispa_bag_full() else "Bolsa llena: deja de buscar"
		trip_time_label.text = "acompañándote" if bool(p.get("follow_in_world", false)) else ""
		trip_bar.value = 0.0
	else:
		var tt: Dictionary = service._pispa_target(str(trip["target"]))
		trip_label.text = "Viaje actual · %s" % tt.get("name", "")
		trip_time_label.text = "vuelve en %s" % service.format_hours(maxf(0.0, float(trip["end_h"]) - service.clock_h))
		var dur := float(trip["end_h"]) - float(trip["start_h"])
		trip_bar.value = clampf((service.clock_h - float(trip["start_h"])) / maxf(0.001, dur), 0.0, 1.0)
	bag_label.text = "%d / %d · si se llena, deja de buscar" % [service.pispa_bag_used(), service.pispa_bag_capacity()]
	bag_grid.queue_redraw()
	snack_label.text = "El próximo viaje dura la mitad · tienes %d panes de Verdalia" % service.get_item("pan")
	feed_button.disabled = service.get_item("pan") <= 0
	empty_bag_button.disabled = service.pispa_bag_used() == 0

	_clear(nest_box)
	var nl: int = service.get_nest_level()
	nest_box.add_child(_caps("NIDO · NIVEL %d → %d" % [nl, nl + 1]))
	var next_tier := {}
	for row in service.upgrades:
		if row["id"] == "nido_pispa" and nl < (row["tiers"] as Array).size():
			next_tier = row["tiers"][nl]
	for line in ["+6 espacios en la bolsa", "Nueva búsqueda: materiales de Ferrum", "Pispa puede traer 2 objetos raros por semana"]:
		nest_box.add_child(_label("+  " + line, 12, T.TEXT_KEY))
	if not next_tier.is_empty():
		var need := PackedStringArray()
		for k in next_tier.get("cost", {}):
			need.append("%s %d/%d" % [service.item_name(k), service.get_item(k), int(next_tier["cost"][k])])
		nest_box.add_child(_kv("Necesitas", " · ".join(need), T.TEXT_KEY if service.can_afford(next_tier.get("cost", {})) else T.SHELTER_JAM))
	_clear(journal_box)
	for j in (p.get("journal", []) as Array).slice(0, 6):
		var row2 := HBoxContainer.new()
		row2.add_theme_constant_override("separation", 10)
		var sq := SideCutViewScript.Dot.new()
		sq.square = true
		sq.outline = true
		sq.color = Color(str(j.get("color", "#46e3c1")))
		sq.custom_minimum_size = Vector2(26, 26)
		row2.add_child(sq)
		var jv := _vbox(0)
		row2.add_child(jv)
		jv.add_child(_label(str(j["text"]), 13, Color(str(j.get("color", "#46e3c1"))), "bold"))
		jv.add_child(_label(str(j.get("when", "")), 11, T.TEXT_SECONDARY))
		journal_box.add_child(row2)


func _refresh_upgrades() -> void:
	_clear(goals_box)
	var first := true
	for g in service.goals:
		var gb := _chip_button(str(g["label"]), 12, 28)
		gb.set_pressed_no_signal(first)
		first = false
		goals_box.add_child(gb)
	var plus := _chip_button("+ meta", 12, 28)
	goals_box.add_child(plus)
	_clear(upgrade_grid)
	upgrade_cells.clear()
	upgrade_grid.add_child(_label("Sala", 12, T.TEXT_SECONDARY))
	for i in 5:
		upgrade_grid.add_child(_label("Nivel %d" % (i + 1), 12, T.TEXT_SECONDARY))
	var rec_order := {}
	var rec: Array = service.get_recommended_upgrades()
	for i in rec.size():
		rec_order["%d:%d" % [rec[i]["row"], rec[i]["tier"]]] = i + 1
	for ri in service.upgrades.size():
		var row: Dictionary = service.upgrades[ri]
		var name_row := HBoxContainer.new()
		name_row.add_theme_constant_override("separation", 8)
		name_row.custom_minimum_size = Vector2(170, 0)
		var dot := SideCutViewScript.Dot.new()
		dot.square = true
		dot.color = Color(str(row.get("color", "#9aa6ae")))
		dot.custom_minimum_size = Vector2(9, 9)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		name_row.add_child(dot)
		var nl := _label(str(row["name"]), 13, T.TEXT, "semibold")
		nl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		name_row.add_child(nl)
		upgrade_grid.add_child(name_row)
		var tiers: Array = row["tiers"]
		for ti in 5:
			if ti >= tiers.size():
				upgrade_grid.add_child(Control.new())
				continue
			var t: Dictionary = tiers[ti]
			var st: String = service.tier_status(ri, ti)
			var b := Button.new()
			b.name = "Up_%s_%d" % [row["id"], ti]
			b.custom_minimum_size = Vector2(122, 42)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.focus_mode = Control.FOCUS_ALL
			var bg: Color = T.SHELTER_SUB_BG
			var edge := Color(1, 1, 1, 0.05)
			var bw := 1
			var sub_txt := ""
			var sub_col: Color = T.TEXT_SECONDARY
			var title_col: Color = T.TEXT_KEY
			match st:
				"done":
					bg = T.SHELTER_DONE_BG
					sub_txt = "hecho"
					title_col = T.TEXT
				"in_progress":
					edge = T.GOLD
					bw = 2
					sub_txt = "en obra · %s" % service.format_hours(float(t["left_h"]))
					sub_col = T.GOLD
					title_col = T.TEXT
				"recommended":
					edge = T.ACCENT_DEFAULT
					bw = 2
					var key := "%d:%d" % [ri, ti]
					sub_txt = "%s %s" % [["①", "②", "③", "④"][mini(3, int(rec_order.get(key, 1)) - 1)], t.get("effect", "")]
					sub_col = T.ACCENT_DEFAULT
					title_col = T.TEXT
				"locked":
					bg = T.SHELTER_LOCKED_BG
					sub_txt = "refugio nv %d" % int(t.get("requires_level", 0))
					sub_col = T.TEXT_MUTED
					title_col = T.TEXT_MUTED
				_:
					sub_txt = service.format_cost(t.get("cost", {})) if t.has("cost") else ""
			var sb := T.box(bg, 9, bw, edge)
			b.add_theme_stylebox_override("normal", sb)
			var hv := sb.duplicate() as StyleBoxFlat
			hv.bg_color = bg.lightened(0.06)
			b.add_theme_stylebox_override("hover", hv)
			b.add_theme_stylebox_override("pressed", hv)
			b.add_theme_stylebox_override("focus", T.box(Color.TRANSPARENT, 9, 1, Color(T.ACCENT_DEFAULT, 0.6)))
			var rid: String = row["id"]
			var tix := ti
			b.pressed.connect(func() -> void: start_upgrade(rid, tix))
			var v := _vbox(0)
			v.mouse_filter = Control.MOUSE_FILTER_IGNORE
			v.set_anchors_preset(Control.PRESET_FULL_RECT)
			v.offset_left = 8
			v.offset_top = 5
			v.offset_right = -4
			b.add_child(v)
			v.add_child(_label(str(t["name"]), 12, title_col, "bold"))
			if sub_txt != "":
				var sl := _label(sub_txt, 10, sub_col)
				sl.clip_text = true
				v.add_child(sl)
			upgrade_grid.add_child(b)
			upgrade_cells["%s:%d" % [row["id"], ti]] = b

	_clear(works_box)
	var works: Array = service.get_works_in_progress()
	works_box.add_child(_caps("OBRAS EN MARCHA · %d DE %d" % [works.size(), service.upgrade_slots]))
	for w in works:
		works_box.add_child(_kv(str(w["label"]), service.format_hours(float(w["left_h"])), T.TEXT))
		var bar := SideCutViewScript.FillBar.new()
		bar.color = T.ACCENT_DEFAULT
		bar.value = 1.0 - float(w["left_h"]) / maxf(0.01, float(w["total_h"]))
		bar.custom_minimum_size = Vector2(0, 5)
		works_box.add_child(bar)
		works_box.add_child(_label("Sigue produciendo mientras se mejora.", 11, T.TEXT_SECONDARY))
	if works.size() < service.upgrade_slots:
		var slot := PanelContainer.new()
		var ssb := T.box(Color.TRANSPARENT, 10, 1, Color(1, 1, 1, 0.18))
		ssb.set_content_margin_all(10)
		slot.add_theme_stylebox_override("panel", ssb)
		var sl2 := _label("Hueco libre · elige una mejora", 12, T.TEXT_KEY)
		sl2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slot.add_child(sl2)
		works_box.add_child(slot)
	_clear(why_box)
	for i in rec.size():
		var r: Dictionary = rec[i]
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 10)
		var num := SideCutViewScript.Avatar.new()
		num.color = T.ACCENT_DEFAULT
		num.letter = str(i + 1)
		num.custom_minimum_size = Vector2(22, 22)
		h.add_child(num)
		var v3 := _vbox(1)
		v3.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(v3)
		v3.add_child(_label(str(r["name"]), 13, T.TEXT, "bold"))
		var wl := _label(str(r["why"]), 11, T.TEXT_SECONDARY)
		wl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v3.add_child(wl)
		why_box.add_child(h)
	var lvl: int = service.get_shelter_level()
	level_title.text = "NIVEL DEL REFUGIO %d → %d" % [lvl, lvl + 1]
	var done: int = service.upgrades_done()
	var nxt: int = service.next_level_threshold()
	level_done_label.text = "%d / %d" % [done, nxt]
	level_bar.value = float(done) / maxf(1.0, float(nxt))
	comfort_label.text = "Confort global %d · descanso ×%.2f · producción +%.1f %%. Al nivel %d: una sala nueva y una cama más." % [
		service.get_comfort(), 1.0 + service.get_comfort() / 100.0, service.comfort_production_bonus() * 100.0, lvl + 1]
	new_floor_button.disabled = lvl < int(service.new_floor_rule.get("requires_level", 5))
	new_floor_button.text = "Excavar un piso más" if not new_floor_button.disabled else "Excavar un piso más · nivel %d" % int(service.new_floor_rule.get("requires_level", 5))


# ==========================================================================
# Helpers de UI
# ==========================================================================
func _set_status(msg: String) -> void:
	if status_label:
		status_label.text = msg


func _clear(n: Node) -> void:
	for c in n.get_children():
		n.remove_child(c)
		c.queue_free()


func _detail_title(text: String, right: String) -> void:
	var h := HBoxContainer.new()
	detail_box.add_child(h)
	var t := _label(text, 20, T.TEXT, "bold")
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.clip_text = true
	t.name = "DetailTitle"
	h.add_child(t)
	if right != "":
		var r := _label(right, 12, T.TEXT_SECONDARY)
		r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(r)


func _kv(k: String, v: String, color: Color) -> HBoxContainer:
	var h := HBoxContainer.new()
	var kl := _label(k, 12, T.TEXT_KEY)
	kl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	kl.clip_text = true
	h.add_child(kl)
	h.add_child(_label(v, 12, color, "bold"))
	return h


func _cost_row(item: String, need: int) -> HBoxContainer:
	var have: int = service.get_item(item)
	return _kv(service.item_name(item), "%s / %s" % [T.format_amount(need), T.format_amount(have)], T.HEALTH if have >= need else T.SHELTER_JAM)


func _risk_tag(risk: String) -> PanelContainer:
	var col: Color = {"bajo": T.HEALTH, "medio": T.GOLD, "alto": T.SHELTER_JAM}.get(risk, T.TEXT_KEY)
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := T.box(Color(col, 0.12), 6)
	sb.content_margin_left = 7
	sb.content_margin_right = 7
	p.add_theme_stylebox_override("panel", sb)
	p.add_child(_label(risk, 11, col, "semibold"))
	return p


func _banner_box(col: Color) -> StyleBoxFlat:
	var sb := T.box(Color(col, 0.06), 12, 1, Color(col, 0.6))
	sb.set_content_margin_all(12)
	return sb


func _card(node_name: String, margin: int = 16) -> PanelContainer:
	var p := PanelContainer.new()
	p.name = node_name
	var sb := T.box(T.SHELTER_CARD_BG, 16, 1, T.CODEX_CARD_BORDER)
	sb.set_content_margin_all(margin)
	p.add_theme_stylebox_override("panel", sb)
	return p


func _vbox(sep: int) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


func _spacer(sz: Vector2) -> Control:
	var c := Control.new()
	c.custom_minimum_size = sz
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _chip_button(text: String, font_size: int, height: int) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size.y = height
	b.add_theme_font_override("font", T.font("semibold"))
	b.add_theme_font_size_override("font_size", font_size)
	var normal := T.box(T.POWERS_CHIP_BG, 8)
	normal.content_margin_left = 10
	normal.content_margin_right = 10
	var on := T.box(T.POWERS_CHIP_ON, 8, 1, T.ACCENT_DEFAULT)
	on.content_margin_left = 10
	on.content_margin_right = 10
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = T.SLOT_READY
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", on)
	b.add_theme_stylebox_override("hover_pressed", on)
	b.add_theme_stylebox_override("focus", T.box(Color.TRANSPARENT, 8, 1, Color(T.ACCENT_DEFAULT, 0.6)))
	for s in ["font_color", "font_hover_color", "font_focus_color"]:
		b.add_theme_color_override(s, T.TEXT_KEY)
	b.add_theme_color_override("font_pressed_color", T.TEXT)
	b.add_theme_color_override("font_hover_pressed_color", T.TEXT)
	return b


func _ghost_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size.y = 34
	b.add_theme_font_override("font", T.font("semibold"))
	b.add_theme_font_size_override("font_size", 13)
	var normal := T.box(T.BUTTON_BG, 10, 1, T.BUTTON_BORDER)
	normal.content_margin_left = 14
	normal.content_margin_right = 14
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = T.SLOT_READY
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(T.BUTTON_BG, 0.5)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("disabled", disabled)
	b.add_theme_stylebox_override("focus", T.box(Color.TRANSPARENT, 10, 1, T.ACCENT_DEFAULT))
	for s in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(s, T.TEXT)
	b.add_theme_color_override("font_disabled_color", T.TEXT_MUTED)
	return b


func _primary_button(text: String) -> Button:
	var b := _ghost_button(text)
	var normal := T.box(T.ACCENT_DEFAULT, 10)
	normal.content_margin_left = 16
	normal.content_margin_right = 16
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = T.ACCENT_DEFAULT.lightened(0.15)
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(T.ACCENT_DEFAULT, 0.25)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("disabled", disabled)
	for s in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(s, T.SHELTER_PILL_TEXT)
	b.add_theme_color_override("font_disabled_color", Color(T.SHELTER_PILL_TEXT, 0.6))
	return b


func _caps(text: String) -> Label:
	var l := _label(text, 11, T.TEXT_SECONDARY, "bold")
	var f := FontVariation.new()
	f.base_font = T.font("bold")
	f.spacing_glyph = 2
	l.add_theme_font_override("font", f)
	return l


func _label(text: String, font_size: int, color: Color, weight: String = "medium") -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", T.font(weight))
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
