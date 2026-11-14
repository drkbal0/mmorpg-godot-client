extends "res://ui/templates/BaseWindow.gd"
## Poderes (tecla N) — UI v2.4 §2.4. Sub-ventanas: Crisol · Atlas · Constelación · Afinidades.
## Referencias: design_ref/pantallas_html/MMO-Talentos.html (Crisol), MMO-Atlas.html,
## MMO-Constelacion.html y design_ref/PROMPT_ANTIGRAVITY.md §2.4.
##
## Todo el estado vive en `PowersService` (shared-core/PowersService.gd); la
## ventana solo pinta y traduce clics a llamadas del servicio.
## - Crisol: 2 o 3 energías + forma + ritmo, «¡NUEVA!», pista de PNJ,
##   «Probar en el maniquí» y conjunto (1 Núcleo · 6 activos · 2 Ecos + resonancia).
## - Atlas: tabla N × N que crece sola, celdas descubierta / pista / «???» y
##   «Llevar al Crisol».
## - Constelación: árbol pasivo de la clase; nodos con coste, beneficio y
##   poderes del Crisol a los que afecta. «Abrir Crisol al lado» muestra
##   ambas sub-ventanas a la vez.
## - Afinidades: barra de nivel por energía (sube con el uso en combate).

const T = preload("res://ui/tokens/hud_tokens.gd")
const MenuBarScene = preload("res://ui/menu/menu_bar.tscn")
const PowersServiceScript = preload("res://shared-core/PowersService.gd")

signal subtab_changed(subtab_id: String)
signal power_composed(power: Dictionary)
signal dummy_tested(power: Dictionary, result: Dictionary)
signal power_equipped(result: Dictionary)
signal atlas_pair_selected(a: String, b: String)
signal constellation_node_selected(node_id: String)
signal point_assigned(node_id: String, result: Dictionary)

const MENU_TAB_ID := "poderes"
const WINDOW_SIZE := Vector2(1270, 680)
const SUBTABS: Array[Dictionary] = [
	{"id": "crisol", "label": "Crisol"},
	{"id": "atlas", "label": "Atlas"},
	{"id": "constelacion", "label": "Constelación"},
	{"id": "afinidades", "label": "Afinidades"},
]
const ATLAS_CELL := 34.0
const ATLAS_GAP := 4.0
const ATLAS_HEADER_W := 70.0

## Servicio inyectable (tests). Si es null se usa /root/PowersService o uno local.
var service: Node = null

var menu_bar: Node
var subnav_buttons: Dictionary = {}
var pages: Dictionary = {}
var current_subtab: String = ""
var side_subtab: String = ""          # sub-ventana abierta «al lado» ("" = ninguna)
var status_label: Label

# --- Crisol ----------------------------------------------------------------
var mixer: Array[String] = ["", "", ""]
var selected_form: String = "area"
var selected_rhythm: String = "canalizado"
var current_power: Dictionary = {}
var energy_query: String = ""
var energy_sort: String = "affinity"
var energy_rows: Dictionary = {}      # energy -> Button
var _energy_list_dirty := true
var energy_list: VBoxContainer
var energy_count_label: Label
var energy_search: LineEdit
var sort_buttons: Dictionary = {}
var crucible_view: CrucibleView
var crisol_subtitle: Label
var form_buttons: Dictionary = {}
var rhythm_buttons: Dictionary = {}
var result_card: PanelContainer
var result_name: Label
var new_badge: PanelContainer
var result_desc: Label
var result_potency: Label
var hint_label: Label
var hint_count_label: Label
var dummy_button: Button
var clear_button: Button
var equip_button: Button
var loadout_title: Label
var core_card: PanelContainer
var active_cards: Array[PanelContainer] = []
var echo_cards: Array[PanelContainer] = []
var resonance_bar: ResonanceBar
var resonance_label: Label
var _crisol_energies_col: Control
var _crisol_loadout_col: Control

# --- Atlas -----------------------------------------------------------------
var atlas_role: String = ""
var atlas_selected: Array[String] = ["pulso", "eco"]
var atlas_grid: GridContainer
var atlas_cells: Dictionary = {}      # pair_key -> AtlasCell
var atlas_stats_label: Label
var atlas_role_buttons: Dictionary = {}
var atlas_pair_title: HBoxContainer
var atlas_formulas_box: VBoxContainer
var atlas_untested_label: Label
var atlas_thirds_box: VBoxContainer
var bring_button: Button

# --- Constelación ----------------------------------------------------------
var selected_node: String = "v1"
var tree_view: ConstellationView
var points_label: Label
var focus_box: VBoxContainer
var builds_box: VBoxContainer
var share_label: Label
var history_label: Label
var node_title: Label
var node_rank_label: Label
var node_desc: Label
var node_affects_box: HFlowContainer
var node_affects_title: Label
var node_next_label: Label
var sim_current_label: Label
var sim_with_label: Label
var sim_current_bar: FillBar
var sim_with_bar: FillBar
var sim_delta_label: Label
var assign_button: Button
var side_button: Button
var _const_left_col: Control
var _const_right_col: Control

# --- Afinidades ------------------------------------------------------------
var affinity_rows: Dictionary = {}    # energy -> {bar, level, xp}
var affinity_grid: GridContainer
var affinity_top_label: Label

var _pages_root: HBoxContainer
var _built := false
var _refresh_queued := false


func _init() -> void:
	custom_minimum_size = WINDOW_SIZE
	size = WINDOW_SIZE
	theme = T.THEME
	add_theme_stylebox_override("panel", T.box(T.PANEL_BG, 14, 1, T.PANEL_EDGE))


func _ready() -> void:
	window_id = "powers"
	_resolve_service()
	_build()
	super._ready()
	add_to_group("powers_window")
	_connect_menu_bar()
	set_title("Poderes")
	select_subtab(SUBTABS[0]["id"] if current_subtab == "" else current_subtab)
	get_viewport().size_changed.connect(fit_to_viewport)
	fit_to_viewport.call_deferred()


## Igual que el Códice: si el menú común no cabe, pasa a modo compacto.
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
	if sub != "" and pages.has(sub):
		select_subtab(sub)


func _resolve_service() -> void:
	if service == null:
		service = get_node_or_null("/root/PowersService")
	if service == null:
		service = PowersServiceScript.new()
		service.name = "LocalPowersService"
		add_child(service)
	elif service.get_parent() == null:
		# Servicio inyectado sin dueño (tests/demo): la ventana lo adopta y lo libera con ella.
		add_child(service)
	for sig in ["energies_changed", "loadout_changed", "constellation_changed", "power_discovered", "affinity_changed"]:
		var cb := Callable(self, "_on_service_changed")
		if not service.is_connected(sig, cb):
			var argc := _signal_argc(sig)
			service.connect(sig, cb.unbind(argc) if argc > 0 else cb)


func _signal_argc(sig: String) -> int:
	match sig:
		"power_discovered", "affinity_changed":
			return 2
	return 0


func _on_service_changed() -> void:
	_energy_list_dirty = true
	if _refresh_queued:
		return
	_refresh_queued = true
	_deferred_refresh.call_deferred()


func _deferred_refresh() -> void:
	_refresh_queued = false
	if service and service.get_energy_count() + 1 != atlas_grid.columns:
		_rebuild_atlas_grid()
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
	header.add_theme_constant_override("separation", 12)
	col.add_child(header)
	var pill := PanelContainer.new()
	pill.name = "Subnav"
	var psb := T.box(T.POWERS_CARD_BG, 12, 1, T.CODEX_CARD_BORDER)
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
	var title := _label("Poderes", 1, Color.TRANSPARENT)
	title.name = "TitleLabel"
	title.visible = false
	header.add_child(title)
	status_label = _label("", 12, T.TEXT_SECONDARY)
	status_label.name = "StatusLabel"
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status_label.clip_text = true
	header.add_child(status_label)

	_pages_root = HBoxContainer.new()
	_pages_root.name = "Pages"
	_pages_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_pages_root.add_theme_constant_override("separation", 12)
	col.add_child(_pages_root)
	pages["crisol"] = _build_crisol_page()
	pages["atlas"] = _build_atlas_page()
	pages["constelacion"] = _build_constellation_page()
	pages["afinidades"] = _build_affinities_page()
	for id in ["constelacion", "crisol", "atlas", "afinidades"]:
		var p: Control = pages[id]
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		p.size_flags_vertical = Control.SIZE_EXPAND_FILL
		p.visible = false
		_pages_root.add_child(p)


# --------------------------------------------------------------------------
# Crisol
# --------------------------------------------------------------------------
func _build_crisol_page() -> Control:
	var page := HBoxContainer.new()
	page.name = "CrisolPage"
	page.add_theme_constant_override("separation", 12)

	# Energías
	var left := _card("Energies")
	left.custom_minimum_size.x = 268
	page.add_child(left)
	_crisol_energies_col = left
	var lcol := _vbox(8)
	left.add_child(lcol)
	var lhead := HBoxContainer.new()
	lcol.add_child(lhead)
	var lt := _label("Energías", 18, T.TEXT, "bold")
	lt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lhead.add_child(lt)
	energy_count_label = _label("", 11, T.TEXT_SECONDARY)
	energy_count_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lhead.add_child(energy_count_label)
	energy_search = LineEdit.new()
	energy_search.name = "EnergySearch"
	energy_search.placeholder_text = "Buscar energía o efecto"
	energy_search.custom_minimum_size.y = 30
	energy_search.add_theme_font_size_override("font_size", 12)
	energy_search.add_theme_stylebox_override("normal", _input_box())
	energy_search.add_theme_stylebox_override("focus", T.box(T.WELL, 8, 1, T.ACCENT_DEFAULT))
	energy_search.text_changed.connect(func(t: String) -> void:
		energy_query = t
		_energy_list_dirty = true
		_refresh_crisol())
	lcol.add_child(energy_search)
	var sorts := HBoxContainer.new()
	sorts.add_theme_constant_override("separation", 4)
	lcol.add_child(sorts)
	for s in [["affinity", "Afinidad"], ["recent", "Uso reciente"], ["az", "A–Z"]]:
		var b := _chip_button(s[1], 11, 24)
		var sk: String = s[0]
		b.pressed.connect(func() -> void: set_energy_sort(sk))
		sorts.add_child(b)
		sort_buttons[sk] = b
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lcol.add_child(scroll)
	energy_list = _vbox(4)
	energy_list.name = "EnergyList"
	energy_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(energy_list)
	var foot := _label("La afinidad sube usando poderes de esa energía. Clic añade al crisol; clic derecho la quita.", 11, T.TEXT_SECONDARY)
	foot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lcol.add_child(foot)

	# Crisol central
	var center := _card("Crucible")
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_stretch_ratio = 2.0
	page.add_child(center)
	var ccol := _vbox(10)
	center.add_child(ccol)
	var chead := HBoxContainer.new()
	chead.add_theme_constant_override("separation", 10)
	ccol.add_child(chead)
	chead.add_child(_label("Crisol de resonancia", 18, T.TEXT, "bold"))
	crisol_subtitle = _label("", 11, T.TEXT_SECONDARY)
	crisol_subtitle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	crisol_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	crisol_subtitle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	crisol_subtitle.clip_text = true
	chead.add_child(crisol_subtitle)
	var mid := HBoxContainer.new()
	mid.add_theme_constant_override("separation", 14)
	ccol.add_child(mid)
	crucible_view = CrucibleView.new()
	crucible_view.name = "CrucibleView"
	crucible_view.custom_minimum_size = Vector2(230, 236)
	crucible_view.slot_clicked.connect(func(i: int) -> void: remove_energy_from_crucible(i))
	mid.add_child(crucible_view)
	var opts := _vbox(6)
	opts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_child(opts)
	opts.add_child(_caps("FORMA"))
	var forms := HFlowContainer.new()
	forms.add_theme_constant_override("h_separation", 6)
	forms.add_theme_constant_override("v_separation", 6)
	opts.add_child(forms)
	for f in PowersServiceScript.FORMS:
		var b := _chip_button(PowersServiceScript.FORM_LABELS[f], 12, 28)
		b.name = "Form_" + f
		var fk: String = f
		b.pressed.connect(func() -> void: set_form(fk))
		forms.add_child(b)
		form_buttons[f] = b
	opts.add_child(_caps("RITMO"))
	var rhythms := HFlowContainer.new()
	rhythms.add_theme_constant_override("h_separation", 6)
	opts.add_child(rhythms)
	for r in PowersServiceScript.RHYTHMS:
		var b := _chip_button(PowersServiceScript.RHYTHM_LABELS[r], 12, 28)
		b.name = "Rhythm_" + r
		var rk: String = r
		b.pressed.connect(func() -> void: set_rhythm(rk))
		rhythms.add_child(b)
		rhythm_buttons[r] = b
	result_card = PanelContainer.new()
	result_card.name = "ResultCard"
	opts.add_child(result_card)
	var rcol := _vbox(4)
	result_card.add_child(rcol)
	var rhead := HBoxContainer.new()
	rhead.add_theme_constant_override("separation", 8)
	rcol.add_child(rhead)
	result_name = _label("", 18, T.TEXT, "bold")
	result_name.name = "ResultName"
	rhead.add_child(result_name)
	new_badge = PanelContainer.new()
	new_badge.name = "NewBadge"
	new_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var nsb := T.box(T.POWERS_NEW_BG, 6)
	nsb.content_margin_left = 7
	nsb.content_margin_right = 7
	new_badge.add_theme_stylebox_override("panel", nsb)
	new_badge.add_child(_label("¡NUEVA!", 11, T.TEXT_DARK, "bold"))
	rhead.add_child(new_badge)
	result_desc = _label("", 12, T.TEXT_KEY)
	result_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result_desc.custom_minimum_size.x = 260
	rcol.add_child(result_desc)
	result_potency = _label("", 11, T.TEXT_SECONDARY)
	result_potency.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rcol.add_child(result_potency)

	var hint := PanelContainer.new()
	hint.name = "HintBar"
	var hsb := T.box(T.POWERS_SUB_BG, 10)
	hsb.set_content_margin_all(10)
	hint.add_theme_stylebox_override("panel", hsb)
	ccol.add_child(hint)
	var hrow := HBoxContainer.new()
	hrow.add_theme_constant_override("separation", 8)
	hint.add_child(hrow)
	hrow.add_child(_label("◆", 12, T.POWERS_HINT, "bold"))
	hint_label = _label("", 12, T.TEXT_KEY)
	hint_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hrow.add_child(hint_label)
	hint_count_label = _label("", 11, T.TEXT_SECONDARY)
	hrow.add_child(hint_count_label)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ccol.add_child(spacer)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	ccol.add_child(actions)
	dummy_button = _ghost_button("Probar en el maniquí")
	dummy_button.name = "DummyButton"
	dummy_button.pressed.connect(func() -> void: test_current_on_dummy())
	actions.add_child(dummy_button)
	clear_button = _ghost_button("Vaciar crisol")
	clear_button.name = "ClearButton"
	clear_button.pressed.connect(clear_crucible)
	actions.add_child(clear_button)
	var aspacer := Control.new()
	aspacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(aspacer)
	equip_button = _primary_button("Equipar")
	equip_button.name = "EquipButton"
	equip_button.pressed.connect(func() -> void: equip_current())
	actions.add_child(equip_button)

	# Conjunto
	var right := _card("Loadout")
	right.custom_minimum_size.x = 300
	page.add_child(right)
	_crisol_loadout_col = right
	var rc := _vbox(8)
	right.add_child(rc)
	var lh := HBoxContainer.new()
	rc.add_child(lh)
	loadout_title = _caps("CONJUNTO")
	loadout_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lh.add_child(loadout_title)
	lh.add_child(_keycap(str(service.loadout_key)))
	core_card = _slot_card(true)
	core_card.name = "CoreSlot"
	rc.add_child(core_card)
	var grid := GridContainer.new()
	grid.name = "ActiveSlots"
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	rc.add_child(grid)
	active_cards.clear()
	for i in PowersServiceScript.ACTIVE_SLOTS:
		var c := _slot_card(false)
		c.name = "Active_%d" % (i + 1)
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(c)
		active_cards.append(c)
	rc.add_child(_caps("ECOS PASIVOS"))
	var echoes := HBoxContainer.new()
	echoes.name = "EchoSlots"
	echoes.add_theme_constant_override("separation", 6)
	rc.add_child(echoes)
	echo_cards.clear()
	for i in PowersServiceScript.ECHO_SLOTS:
		var e := PanelContainer.new()
		e.name = "Echo_%d" % (i + 1)
		e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var esb := T.box(T.POWERS_SUB_BG, 8)
		esb.set_content_margin_all(8)
		e.add_theme_stylebox_override("panel", esb)
		var el := _label("", 12, T.TEXT_KEY)
		el.name = "Text"
		el.clip_text = true
		e.add_child(el)
		echoes.add_child(e)
		echo_cards.append(e)
	rc.add_child(_caps("RESONANCIA DEL CONJUNTO"))
	resonance_bar = ResonanceBar.new()
	resonance_bar.name = "ResonanceBar"
	resonance_bar.custom_minimum_size = Vector2(0, 10)
	rc.add_child(resonance_bar)
	resonance_label = _label("", 12, T.TEXT_KEY)
	resonance_label.name = "ResonanceLabel"
	resonance_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	resonance_label.custom_minimum_size.x = 260
	rc.add_child(resonance_label)
	return page


# --------------------------------------------------------------------------
# Atlas
# --------------------------------------------------------------------------
func _build_atlas_page() -> Control:
	var page := HBoxContainer.new()
	page.name = "AtlasPage"
	page.add_theme_constant_override("separation", 12)
	var main := _card("AtlasMain")
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_child(main)
	var mcol := _vbox(10)
	main.add_child(mcol)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	mcol.add_child(head)
	head.add_child(_label("Atlas de resonancias", 18, T.TEXT, "bold"))
	atlas_stats_label = _label("", 12, T.TEXT_SECONDARY)
	atlas_stats_label.name = "AtlasStats"
	atlas_stats_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	atlas_stats_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(atlas_stats_label)
	for role in ["", "dano", "control", "curacion"]:
		var b := _chip_button(PowersServiceScript.ROLE_LABELS[role], 12, 26)
		var rk: String = role
		b.pressed.connect(func() -> void: set_atlas_role(rk))
		head.add_child(b)
		atlas_role_buttons[role] = b
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mcol.add_child(body)
	var scroll := ScrollContainer.new()
	scroll.name = "AtlasScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.x = ATLAS_HEADER_W + 10 * (ATLAS_CELL + ATLAS_GAP) + 8
	body.add_child(scroll)
	atlas_grid = GridContainer.new()
	atlas_grid.name = "AtlasGrid"
	atlas_grid.add_theme_constant_override("h_separation", int(ATLAS_GAP))
	atlas_grid.add_theme_constant_override("v_separation", int(ATLAS_GAP))
	scroll.add_child(atlas_grid)
	var legend := _vbox(10)
	legend.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(legend)
	legend.add_child(_caps("CÓMO LEERLO"))
	for item in [
		[PowersServiceScript.CELL_DISCOVERED, "3", "Descubierta · nº de fórmulas", false],
		[PowersServiceScript.CELL_HINT, "?", "Tienes una pista", false],
		[PowersServiceScript.CELL_UNKNOWN, "???", "Sin descubrir", false],
		[PowersServiceScript.CELL_DISCOVERED, "2", "Diagonal: energía pura", true],
	]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		legend.add_child(row)
		var c := AtlasCell.new()
		c.custom_minimum_size = Vector2(ATLAS_CELL, ATLAS_CELL)
		c.focus_mode = Control.FOCUS_NONE
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ca := "pulso" if item[3] else "vacio"
		var cb := "pulso" if item[3] else "calor"
		c.setup({"state": item[0], "count": int(item[1]) if item[1].is_valid_int() else 0, "pure": item[3], "a": ca, "b": cb},
			T.energy_color(ca), T.energy_color(cb))
		row.add_child(c)
		var l := _label(item[2], 12, T.TEXT_KEY)
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(l)
	for txt in [
		"La tabla crece sola: si una temporada añade una energía nueva, aparece una fila y una columna más, sin rehacer nada.",
		"Las mezclas de 3 energías se ven al seleccionar una pareja, para no llenar la tabla.",
	]:
		var p := PanelContainer.new()
		var sb := T.box(T.POWERS_SUB_BG, 10)
		sb.set_content_margin_all(12)
		p.add_theme_stylebox_override("panel", sb)
		var l := _label(txt, 12, T.TEXT_KEY)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 220
		p.add_child(l)
		legend.add_child(p)

	var side := _card("AtlasDetail")
	side.custom_minimum_size.x = 320
	page.add_child(side)
	var scol := _vbox(8)
	side.add_child(scol)
	atlas_pair_title = HBoxContainer.new()
	atlas_pair_title.name = "PairTitle"
	atlas_pair_title.add_theme_constant_override("separation", 8)
	scol.add_child(atlas_pair_title)
	scol.add_child(_caps("FÓRMULAS CONOCIDAS"))
	atlas_formulas_box = _vbox(6)
	atlas_formulas_box.name = "Formulas"
	scol.add_child(atlas_formulas_box)
	atlas_untested_label = _label("", 12, T.TEXT_SECONDARY)
	atlas_untested_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	scol.add_child(atlas_untested_label)
	scol.add_child(_caps("CON UNA TERCERA ENERGÍA"))
	atlas_thirds_box = _vbox(6)
	atlas_thirds_box.name = "Thirds"
	scol.add_child(atlas_thirds_box)
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scol.add_child(sp)
	bring_button = _primary_button("Llevar al Crisol")
	bring_button.name = "BringButton"
	bring_button.pressed.connect(func() -> void: bring_to_crucible())
	scol.add_child(bring_button)
	return page


func _rebuild_atlas_grid() -> void:
	for c in atlas_grid.get_children():
		atlas_grid.remove_child(c)
		c.queue_free()
	atlas_cells.clear()
	var es: Array[String] = service.energies
	atlas_grid.columns = es.size() + 1
	atlas_grid.add_child(_spacer(Vector2(ATLAS_HEADER_W, 30)))
	for e in es:
		var h := _vbox(2)
		h.custom_minimum_size = Vector2(ATLAS_CELL, 30)
		var d := Dot.new()
		d.color = service.energy_color(e)
		d.custom_minimum_size = Vector2(ATLAS_CELL, 12)
		h.add_child(d)
		var l := _label(service.energy_name(e), 9, T.TEXT_SECONDARY)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.clip_text = true
		l.custom_minimum_size.x = ATLAS_CELL
		h.add_child(l)
		atlas_grid.add_child(h)
	for i in es.size():
		var rh := HBoxContainer.new()
		rh.custom_minimum_size = Vector2(ATLAS_HEADER_W, ATLAS_CELL)
		rh.add_theme_constant_override("separation", 6)
		var d := Dot.new()
		d.color = service.energy_color(es[i])
		d.custom_minimum_size = Vector2(10, ATLAS_CELL)
		rh.add_child(d)
		var l := _label(service.energy_name(es[i]), 11, T.TEXT_KEY)
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		rh.add_child(l)
		atlas_grid.add_child(rh)
		for j in es.size():
			if j < i:
				atlas_grid.add_child(_spacer(Vector2(ATLAS_CELL, ATLAS_CELL)))
				continue
			var cell := AtlasCell.new()
			cell.name = "Cell_%s_%s" % [es[i], es[j]]
			cell.custom_minimum_size = Vector2(ATLAS_CELL, ATLAS_CELL)
			var a: String = es[i]
			var b: String = es[j]
			cell.pressed.connect(func() -> void: select_atlas_pair(a, b))
			atlas_grid.add_child(cell)
			atlas_cells[service.pair_key(a, b)] = cell


# --------------------------------------------------------------------------
# Constelación
# --------------------------------------------------------------------------
func _build_constellation_page() -> Control:
	var page := HBoxContainer.new()
	page.name = "ConstellationPage"
	page.add_theme_constant_override("separation", 12)

	var left := _card("ConstLeft")
	left.custom_minimum_size.x = 268
	page.add_child(left)
	_const_left_col = left
	var lc := _vbox(7)
	left.add_child(lc)
	lc.add_child(_caps("CONSTELACIÓN DE CLASE · " + str(service.class_title).to_upper()))
	var bh := HBoxContainer.new()
	lc.add_child(bh)
	var bn := _label(str(service.build_name), 18, T.TEXT, "bold")
	bn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bh.add_child(bn)
	points_label = _label("", 14, T.ACCENT_DEFAULT, "bold")
	points_label.name = "PointsLabel"
	bh.add_child(points_label)
	focus_box = _vbox(2)
	lc.add_child(focus_box)
	for f in service.focus:
		var r := HBoxContainer.new()
		var fl := _label(str(f["label"]), 12, T.TEXT_KEY)
		fl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.add_child(fl)
		r.add_child(_label("%d %%" % int(f["pct"]), 12, T.TEXT_SECONDARY))
		focus_box.add_child(r)
		var bar := FillBar.new()
		bar.custom_minimum_size.y = 5
		bar.fill = Color(f["color"])
		bar.ratio = float(f["pct"]) / 100.0
		focus_box.add_child(bar)
	lc.add_child(_caps("BUILDS GUARDADAS"))
	builds_box = _vbox(5)
	lc.add_child(builds_box)
	var first := true
	for b in service.builds:
		var card := PanelContainer.new()
		var sb := T.box(T.POWERS_SUB_BG, 10, 1 if first else 0, T.ACCENT_DEFAULT)
		sb.content_margin_left = 10
		sb.content_margin_right = 10
		sb.content_margin_top = 5
		sb.content_margin_bottom = 5
		card.add_theme_stylebox_override("panel", sb)
		var row := HBoxContainer.new()
		card.add_child(row)
		var v := _vbox(0)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(v)
		v.add_child(_label(str(b["name"]), 13, T.TEXT, "bold"))
		v.add_child(_label(str(b["sub"]), 11, T.TEXT_SECONDARY))
		var kc := _keycap(str(b["key"]))
		kc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(kc)
		builds_box.add_child(card)
		first = false
	lc.add_child(_caps("COMPARTIR"))
	var sh := HBoxContainer.new()
	sh.add_theme_constant_override("separation", 6)
	lc.add_child(sh)
	var code := PanelContainer.new()
	code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var csb := T.box(T.POWERS_SUB_BG, 8)
	csb.content_margin_left = 10
	csb.content_margin_top = 4
	csb.content_margin_bottom = 4
	code.add_theme_stylebox_override("panel", csb)
	share_label = _label(str(service.share_code), 14, T.TEXT, "bold")
	code.add_child(share_label)
	sh.add_child(code)
	var copy := _ghost_button("Copiar")
	copy.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(share_label.text)
		_set_status("Código de build copiado: " + share_label.text))
	sh.add_child(copy)
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lc.add_child(sp)
	var hist := PanelContainer.new()
	var hsb := T.box(T.POWERS_SUB_BG, 10)
	hsb.set_content_margin_all(10)
	hist.add_theme_stylebox_override("panel", hsb)
	lc.add_child(hist)
	var hv := _vbox(2)
	hist.add_child(hv)
	history_label = _label("", 12, T.TEXT, "bold")
	hv.add_child(history_label)
	var undo := _label("Deshacer Ctrl Z · cambios gratis fuera de combate", 11, T.TEXT_SECONDARY)
	hv.add_child(undo)

	var center := _card("ConstTree")
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_stretch_ratio = 2.0
	page.add_child(center)
	var holder := Control.new()
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	holder.custom_minimum_size = Vector2(320, 420)
	center.add_child(holder)
	tree_view = ConstellationView.new()
	tree_view.name = "ConstellationView"
	tree_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tree_view.node_clicked.connect(func(id: String) -> void: select_node(id))
	holder.add_child(tree_view)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	top.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	holder.add_child(top)
	var rec := _ghost_button("Ver recomendada")
	rec.pressed.connect(func() -> void: select_node(_recommended_node()))
	top.add_child(rec)
	side_button = _chip_button("Abrir Crisol al lado", 12, 30)
	side_button.name = "SideButton"
	side_button.toggle_mode = true
	side_button.pressed.connect(func() -> void: toggle_crucible_beside())
	top.add_child(side_button)

	var right := _card("ConstNode")
	right.custom_minimum_size.x = 280
	page.add_child(right)
	_const_right_col = right
	var rc := _vbox(8)
	right.add_child(rc)
	rc.add_child(_caps("NODO SELECCIONADO"))
	node_title = _label("", 18, T.TEXT, "bold")
	node_title.name = "NodeTitle"
	rc.add_child(node_title)
	node_rank_label = _label("", 12, T.TEXT_SECONDARY)
	rc.add_child(node_rank_label)
	node_desc = _label("", 13, T.TEXT_KEY)
	node_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node_desc.custom_minimum_size.x = 240
	rc.add_child(node_desc)
	var aff := PanelContainer.new()
	var asb := T.box(T.POWERS_SUB_BG, 10)
	asb.set_content_margin_all(10)
	aff.add_theme_stylebox_override("panel", asb)
	rc.add_child(aff)
	var av := _vbox(6)
	aff.add_child(av)
	node_affects_title = _label("", 11, T.TEXT_SECONDARY)
	av.add_child(node_affects_title)
	node_affects_box = HFlowContainer.new()
	node_affects_box.name = "Affects"
	node_affects_box.add_theme_constant_override("h_separation", 6)
	node_affects_box.add_theme_constant_override("v_separation", 6)
	av.add_child(node_affects_box)
	var nxt := PanelContainer.new()
	nxt.add_theme_stylebox_override("panel", asb.duplicate())
	rc.add_child(nxt)
	node_next_label = _label("", 12, T.TEXT_KEY)
	nxt.add_child(node_next_label)
	rc.add_child(_caps("SIMULACIÓN · 60 S CONTRA MANIQUÍ"))
	sim_current_label = _label("", 12, T.TEXT_KEY)
	rc.add_child(sim_current_label)
	sim_current_bar = FillBar.new()
	sim_current_bar.custom_minimum_size.y = 6
	sim_current_bar.fill = Color("#46525a")
	rc.add_child(sim_current_bar)
	sim_with_label = _label("", 12, T.ACCENT_DEFAULT)
	rc.add_child(sim_with_label)
	sim_with_bar = FillBar.new()
	sim_with_bar.custom_minimum_size.y = 6
	sim_with_bar.fill = T.ACCENT_DEFAULT
	rc.add_child(sim_with_bar)
	sim_delta_label = _label("", 20, T.ACCENT_DEFAULT, "bold")
	rc.add_child(sim_delta_label)
	var sp2 := Control.new()
	sp2.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rc.add_child(sp2)
	assign_button = _primary_button("Asignar punto")
	assign_button.name = "AssignButton"
	assign_button.pressed.connect(func() -> void: assign_point())
	rc.add_child(assign_button)
	var arena := _ghost_button("Probar en la arena (sin coste)")
	arena.pressed.connect(func() -> void: _set_status("Arena de pruebas: los cambios no cuestan puntos."))
	rc.add_child(arena)
	return page


# --------------------------------------------------------------------------
# Afinidades
# --------------------------------------------------------------------------
func _build_affinities_page() -> Control:
	var page := HBoxContainer.new()
	page.name = "AffinitiesPage"
	page.add_theme_constant_override("separation", 12)
	var main := _card("AffinityMain")
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_child(main)
	var col := _vbox(12)
	main.add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	var t := _label("Afinidades", 18, T.TEXT, "bold")
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	affinity_top_label = _label("", 12, T.TEXT_SECONDARY)
	affinity_top_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(affinity_top_label)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	affinity_grid = GridContainer.new()
	affinity_grid.name = "AffinityGrid"
	affinity_grid.columns = 2
	affinity_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	affinity_grid.add_theme_constant_override("h_separation", 16)
	affinity_grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(affinity_grid)

	var side := _card("AffinityInfo")
	side.custom_minimum_size.x = 320
	page.add_child(side)
	var sc := _vbox(10)
	side.add_child(sc)
	sc.add_child(_caps("CÓMO SUBE LA AFINIDAD"))
	for txt in [
		"Cada vez que usas un poder en combate, cada una de sus energías gana %d PX." % 25,
		"Una energía repetida en el mismo poder cuenta una sola vez.",
		"Pasar del nivel N al N+1 cuesta N × %d PX. Nivel máximo %d." % [PowersServiceScript.AFFINITY_XP_STEP, PowersServiceScript.AFFINITY_MAX_LEVEL],
		"La potencia de un poder del Crisol = Σ afinidad × %d, más la Constelación." % int(PowersServiceScript.POTENCY_PER_LEVEL),
	]:
		var l := _label("• " + txt, 12, T.TEXT_KEY)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 280
		sc.add_child(l)
	return page


func _rebuild_affinity_rows() -> void:
	for c in affinity_grid.get_children():
		affinity_grid.remove_child(c)
		c.queue_free()
	affinity_rows.clear()
	for e in service.energies:
		var card := PanelContainer.new()
		card.name = "Affinity_" + e
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var sb := T.box(T.POWERS_SUB_BG, 10)
		sb.set_content_margin_all(10)
		card.add_theme_stylebox_override("panel", sb)
		var v := _vbox(6)
		card.add_child(v)
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 8)
		v.add_child(r)
		var d := Dot.new()
		d.color = service.energy_color(e)
		d.custom_minimum_size = Vector2(14, 18)
		r.add_child(d)
		var n := _label(service.energy_name(e), 14, T.TEXT, "bold")
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.add_child(n)
		var lvl := _label("", 13, T.TEXT, "bold")
		r.add_child(lvl)
		var bar := FillBar.new()
		bar.custom_minimum_size.y = 8
		bar.fill = service.energy_color(e)
		v.add_child(bar)
		var xp := _label("", 11, T.TEXT_SECONDARY)
		v.add_child(xp)
		affinity_grid.add_child(card)
		affinity_rows[e] = {"bar": bar, "level": lvl, "xp": xp, "card": card}


# ==========================================================================
# Navegación
# ==========================================================================
func get_subtab_ids() -> Array[String]:
	var out: Array[String] = []
	for s in SUBTABS:
		out.append(s["id"])
	return out


func select_subtab(subtab_id: String) -> void:
	if not pages.has(subtab_id):
		push_warning("[PowersWindow] Sub-ventana desconocida: %s" % subtab_id)
		return
	current_subtab = subtab_id
	if side_subtab == subtab_id:
		side_subtab = ""
	_apply_page_visibility()
	menu_bar.set_active_tab(MENU_TAB_ID, subtab_id)
	refresh()
	subtab_changed.emit(subtab_id)


## Abre dos sub-ventanas a la vez (p. ej. Constelación + Crisol).
func open_side_by_side(primary: String, secondary: String) -> void:
	if not pages.has(primary) or not pages.has(secondary) or primary == secondary:
		return
	current_subtab = primary
	side_subtab = secondary
	_apply_page_visibility()
	refresh()
	subtab_changed.emit(primary)


func close_side() -> void:
	side_subtab = ""
	_apply_page_visibility()
	refresh()


func is_side_by_side() -> bool:
	return side_subtab != ""


func get_visible_subtabs() -> Array[String]:
	var out: Array[String] = []
	for id in ["constelacion", "crisol", "atlas", "afinidades"]:
		if (pages[id] as Control).visible:
			out.append(id)
	return out


func toggle_crucible_beside() -> void:
	if side_subtab == "crisol":
		close_side()
	else:
		open_side_by_side("constelacion", "crisol")


func _apply_page_visibility() -> void:
	var split := side_subtab != ""
	for id in pages:
		(pages[id] as Control).visible = id == current_subtab or id == side_subtab
	# En modo «al lado» cada sub-ventana oculta sus columnas secundarias.
	_crisol_energies_col.visible = not split
	_crisol_loadout_col.visible = not split
	_const_left_col.visible = not split
	_const_right_col.visible = true
	(pages["crisol"] as Control).size_flags_stretch_ratio = 1.0
	for id in subnav_buttons:
		(subnav_buttons[id] as Button).set_pressed_no_signal(id == current_subtab or id == side_subtab)
	if side_button:
		side_button.set_pressed_no_signal(side_subtab == "crisol")
		side_button.text = "Cerrar Crisol" if side_subtab == "crisol" else "Abrir Crisol al lado"


# ==========================================================================
# Refresco
# ==========================================================================
func refresh() -> void:
	if not _built or service == null:
		return
	if atlas_grid.columns != service.get_energy_count() + 1:
		_rebuild_atlas_grid()
	if affinity_rows.size() != service.get_energy_count():
		_rebuild_affinity_rows()
	_refresh_crisol()
	_refresh_atlas()
	_refresh_constellation()
	_refresh_affinities()


func _refresh_crisol() -> void:
	if _energy_list_dirty or energy_rows.is_empty():
		_refresh_energy_list()
	_style_energy_rows()
	for k in sort_buttons:
		(sort_buttons[k] as Button).set_pressed_no_signal(k == energy_sort)
	for f in form_buttons:
		(form_buttons[f] as Button).set_pressed_no_signal(f == selected_form)
	for r in rhythm_buttons:
		(rhythm_buttons[r] as Button).set_pressed_no_signal(r == selected_rhythm)
	current_power = get_current_power()
	var colors: Array[Color] = []
	var names: Array[String] = []
	for e in mixer:
		colors.append(service.energy_color(e) if e != "" else Color.TRANSPARENT)
		names.append(service.energy_name(e) if e != "" else "")
	crucible_view.set_slots(colors, names)
	var bonus := 0.0
	var bonus_energy := ""
	for e in mixer:
		if e != "" and service.get_constellation_bonus(e) > bonus:
			bonus = service.get_constellation_bonus(e)
			bonus_energy = e
	crisol_subtitle.text = "2 o 3 energías + forma + ritmo = un poder" + (" · tu Constelación suma +%d %% al %s" % [roundi(bonus), service.energy_name(bonus_energy)] if bonus_energy != "" else "")
	if current_power.get("ok", false):
		result_name.text = current_power["name"]
		new_badge.visible = current_power["is_new"]
		result_desc.text = current_power["description"]
		result_potency.text = current_power["breakdown"]
		result_card.add_theme_stylebox_override("panel", _result_box(T.POWERS_NEW if current_power["is_new"] else T.ACCENT_DEFAULT))
	else:
		result_name.text = "Crisol vacío" if _mixer_count() == 0 else "Falta una energía"
		new_badge.visible = false
		result_desc.text = "Añade 2 o 3 energías desde la lista y elige forma y ritmo."
		result_potency.text = ""
		result_card.add_theme_stylebox_override("panel", _result_box(Color(1, 1, 1, 0.08)))
	var hint: Dictionary = service.get_crucible_hint()
	hint_label.text = "Pista: " + str(hint.get("text", "no hay pistas pendientes."))
	hint_count_label.text = "%d pistas sin probar" % int(hint.get("untested", 0)) if not hint.is_empty() else ""
	var ok: bool = current_power.get("ok", false)
	dummy_button.disabled = not ok
	clear_button.disabled = _mixer_count() == 0
	var free_slot: int = service.first_free_active_slot()
	var equipped: bool = ok and service.get_loadout_keys(true).has(current_power["key"])
	equip_button.disabled = not ok or free_slot < 0 or equipped
	equip_button.text = "Equipado" if equipped else ("Equipar en la ranura %d" % (free_slot + 1) if free_slot >= 0 else "Conjunto lleno")
	_refresh_loadout(free_slot if ok and not equipped else -1)


func _refresh_energy_list() -> void:
	_energy_list_dirty = false
	for c in energy_list.get_children():
		energy_list.remove_child(c)
		c.queue_free()
	energy_rows.clear()
	var list: Array[String] = service.list_energies(energy_query, energy_sort)
	energy_count_label.text = "%d energías" % service.get_energy_count()
	for e in list:
		var b := _energy_row(e)
		energy_list.add_child(b)
		energy_rows[e] = b


func _refresh_loadout(target_slot: int) -> void:
	loadout_title.text = "CONJUNTO «%s»" % str(service.loadout_name).to_upper()
	_fill_slot_card(core_card, service.slot_view(service.core_slot), "NÚCLEO · R", false)
	for i in active_cards.size():
		_fill_slot_card(active_cards[i], service.slot_view(service.active_slots[i]), str(i + 1), i == target_slot)
	for i in echo_cards.size():
		var v: Dictionary = service.slot_view(service.echo_slots[i])
		var l: Label = echo_cards[i].get_node("Text")
		l.text = v["name"] if not v["empty"] else "+ vacío"
		l.add_theme_color_override("font_color", T.TEXT_KEY if not v["empty"] else T.TEXT_MUTED)
	var res: Array[Dictionary] = service.get_resonance()
	var segs: Array = []
	for r in res:
		segs.append({"color": service.energy_color(r["energy"]), "weight": float(r["count"])})
	resonance_bar.set_segments(segs)
	resonance_label.text = service.resonance_summary()


func _refresh_atlas() -> void:
	var st: Dictionary = service.get_atlas_stats()
	atlas_stats_label.text = "%d de %d parejas · %d fórmulas conocidas" % [st["pairs_discovered"], st["pairs_total"], st["formulas_known"]]
	for r in atlas_role_buttons:
		(atlas_role_buttons[r] as Button).set_pressed_no_signal(r == atlas_role)
	var sel_key: String = service.pair_key(atlas_selected[0], atlas_selected[1])
	for pk in atlas_cells:
		var parts: PackedStringArray = str(pk).split("+")
		var a: String = parts[0]
		var b: String = parts[1] if parts.size() > 1 else parts[0]
		var cell: Dictionary = service.get_atlas_cell(a, b, atlas_role)
		var ac: AtlasCell = atlas_cells[pk]
		ac.selected = pk == sel_key
		ac.setup(cell, service.energy_color(a), service.energy_color(b))
	_refresh_pair_detail()


func _refresh_pair_detail() -> void:
	var a: String = atlas_selected[0]
	var b: String = atlas_selected[1]
	var det: Dictionary = service.get_pair_details(a, b)
	for c in atlas_pair_title.get_children():
		atlas_pair_title.remove_child(c)
		c.queue_free()
	for e in ([a] if a == b else [a, b]):
		if atlas_pair_title.get_child_count() > 0:
			var plus := _label("+", 12, T.TEXT_SECONDARY)
			plus.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			atlas_pair_title.add_child(plus)
		var d := Dot.new()
		d.color = service.energy_color(e)
		d.custom_minimum_size = Vector2(20, 24)
		atlas_pair_title.add_child(d)
		atlas_pair_title.add_child(_label(service.energy_name(e), 18, T.TEXT, "bold"))
	if a == b:
		atlas_pair_title.add_child(_label("(pura)", 12, T.TEXT_SECONDARY))
	for c in atlas_formulas_box.get_children():
		atlas_formulas_box.remove_child(c)
		c.queue_free()
	var cell: Dictionary = det["cell"]
	if det["formulas"].is_empty():
		var msg := "Pista: " + str(cell["hint"]) if cell["state"] == PowersServiceScript.CELL_HINT else "??? · aún no conoces fórmulas con esta pareja."
		var l := _label(msg, 12, T.POWERS_HINT if cell["state"] == PowersServiceScript.CELL_HINT else T.TEXT_MUTED)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 260
		atlas_formulas_box.add_child(l)
	for f in (det["formulas"] as Array).slice(0, 3):
		var p := PanelContainer.new()
		var sb := T.box(T.POWERS_SUB_BG, 10)
		sb.set_content_margin_all(10)
		p.add_theme_stylebox_override("panel", sb)
		var v := _vbox(2)
		p.add_child(v)
		v.add_child(_label(str(f["name"]), 13, T.TEXT, "bold"))
		var sub := str(f.get("desc", ""))
		if sub == "" or sub.length() > 46:
			sub = "%s · %s" % [PowersServiceScript.FORM_LABELS[f["form"]], PowersServiceScript.RHYTHM_LABELS[f["rhythm"]].to_lower()]
		v.add_child(_label(sub, 11, T.TEXT_SECONDARY))
		atlas_formulas_box.add_child(p)
	if (det["formulas"] as Array).size() > 3:
		atlas_formulas_box.add_child(_label("+%d fórmulas más" % ((det["formulas"] as Array).size() - 3), 11, T.TEXT_SECONDARY))
	atlas_untested_label.text = "%d formas más sin probar con esta pareja" % int(det["untested_forms"])
	for c in atlas_thirds_box.get_children():
		atlas_thirds_box.remove_child(c)
		c.queue_free()
	for t in det["thirds"]:
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 8)
		var d := Dot.new()
		d.color = service.energy_color(t["energy"])
		d.custom_minimum_size = Vector2(10, 18)
		r.add_child(d)
		var nl := _label("+ " + service.energy_name(t["energy"]), 12, T.TEXT_KEY)
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.add_child(nl)
		var txt := "sin descubrir"
		var col := T.TEXT_MUTED
		if t["state"] == PowersServiceScript.CELL_DISCOVERED:
			txt = "%s ✓" % t["name"]
			col = T.ACCENT_DEFAULT
		elif t["state"] == PowersServiceScript.CELL_HINT:
			txt = "pista: «%s»" % t["hint"]
			col = T.POWERS_HINT
		r.add_child(_label(txt, 12, col))
		atlas_thirds_box.add_child(r)


func _refresh_constellation() -> void:
	points_label.text = "%d / %d" % [service.get_spent_points(), service.total_points]
	history_label.text = "Historial · %d cambios" % service.history.size()
	tree_view.setup(service, selected_node)
	var n: Dictionary = service.get_star(selected_node)
	if n.is_empty():
		return
	var branch := str(n["branch"])
	var branch_name := "Rama del %s" % service.energy_name(branch) if branch != "" else "Tronco común"
	node_title.text = str(n["name"])
	node_rank_label.text = "Rango %d de %d · %s · coste %d %s" % [n["rank"], n["max_rank"], branch_name, n["cost"], "punto" if int(n["cost"]) == 1 else "puntos"]
	node_desc.text = service.node_description(selected_node)
	var affected: Array[String] = service.get_node_affected_powers(selected_node)
	node_affects_title.text = "Afecta a %d %s de tu Crisol" % [affected.size(), "poder" if affected.size() == 1 else "poderes"]
	for c in node_affects_box.get_children():
		node_affects_box.remove_child(c)
		c.queue_free()
	for p in affected:
		node_affects_box.add_child(_tag(p))
	var rank := int(n["rank"])
	if rank < int(n["max_rank"]):
		node_next_label.text = "Siguiente rango   %d → %d" % [service.node_value(n, rank) if rank > 0 else 0, service.node_value(n, rank + 1)]
	else:
		node_next_label.text = "Rango máximo alcanzado"
	var cur: int = service.simulate_dps()
	var with: int = service.simulate_dps(selected_node)
	var top := maxf(1.0, float(maxi(cur, with)) * 1.08)
	sim_current_label.text = "Actual   %s /s" % T.format_amount(cur)
	sim_with_label.text = "Con este punto   %s /s" % T.format_amount(with)
	sim_current_bar.ratio = cur / top
	sim_with_bar.ratio = with / top
	var delta := (float(with - cur) / float(cur) * 100.0) if cur > 0 else 0.0
	sim_delta_label.text = ("+%.1f %%" % delta).replace(".", ",") if delta > 0.0 else "Sin cambio"
	var st: String = service.get_node_state(selected_node)
	assign_button.disabled = rank >= int(n["max_rank"]) or st == PowersServiceScript.NODE_LOCKED or service.get_available_points() < int(n["cost"])
	assign_button.text = "Asignar punto (%d disponibles)" % service.get_available_points()


func _refresh_affinities() -> void:
	var best := ""
	for e in service.energies:
		if best == "" or service.get_affinity_level(e) > service.get_affinity_level(best):
			best = e
		var row: Dictionary = affinity_rows.get(e, {})
		if row.is_empty():
			continue
		var p: Dictionary = service.get_affinity_progress(e)
		(row["level"] as Label).text = "nv %d" % p["level"]
		(row["bar"] as FillBar).ratio = p["ratio"]
		(row["xp"] as Label).text = "Nivel máximo" if p["max"] else "%s / %s PX hasta nv %d" % [T.format_amount(p["into"]), T.format_amount(p["needed"]), int(p["level"]) + 1]
	affinity_top_label.text = "Mayor afinidad: %s (nv %d)" % [service.energy_name(best), service.get_affinity_level(best)] if best != "" else ""


# ==========================================================================
# API · Crisol
# ==========================================================================
func _mixer_count() -> int:
	var n := 0
	for e in mixer:
		if e != "":
			n += 1
	return n


func get_mixer_energies() -> Array[String]:
	var out: Array[String] = []
	for e in mixer:
		if e != "":
			out.append(e)
	return out


func get_current_power() -> Dictionary:
	return service.compose_power(get_mixer_energies(), selected_form, selected_rhythm)


## Añade una energía al primer hueco libre (la 3.ª es opcional). false si está lleno.
func add_energy_to_crucible(key: String) -> bool:
	if not service.has_energy(key):
		return false
	for i in mixer.size():
		if mixer[i] == "":
			mixer[i] = key
			_after_crucible_change()
			return true
	_set_status("El crisol admite como máximo %d energías." % PowersServiceScript.MAX_ENERGIES)
	return false


func remove_energy_from_crucible(slot: int) -> bool:
	if slot < 0 or slot >= mixer.size() or mixer[slot] == "":
		return false
	mixer[slot] = ""
	# Compacta: los huecos quedan siempre al final.
	var kept := get_mixer_energies()
	for i in mixer.size():
		mixer[i] = kept[i] if i < kept.size() else ""
	_after_crucible_change()
	return true


func remove_energy_key(key: String) -> bool:
	for i in range(mixer.size() - 1, -1, -1):
		if mixer[i] == key:
			return remove_energy_from_crucible(i)
	return false


func set_crucible(list: Array, form: String = "", rhythm: String = "") -> void:
	for i in mixer.size():
		mixer[i] = str(list[i]) if i < list.size() else ""
	if form != "":
		selected_form = form
	if rhythm != "":
		selected_rhythm = rhythm
	_after_crucible_change()


func clear_crucible() -> void:
	for i in mixer.size():
		mixer[i] = ""
	_after_crucible_change()


func set_form(form: String) -> bool:
	if not PowersServiceScript.FORMS.has(form):
		return false
	selected_form = form
	_after_crucible_change()
	return true


func set_rhythm(rhythm: String) -> bool:
	if not PowersServiceScript.RHYTHMS.has(rhythm):
		return false
	selected_rhythm = rhythm
	_after_crucible_change()
	return true


func set_energy_sort(sort: String) -> void:
	energy_sort = sort
	_energy_list_dirty = true
	_refresh_crisol()


func _after_crucible_change() -> void:
	if not _built:
		return
	_refresh_crisol()
	if current_power.get("ok", false):
		power_composed.emit(current_power)


func test_current_on_dummy() -> Dictionary:
	var p := get_current_power()
	var r: Dictionary = service.test_on_dummy(p)
	if r.get("ok", false):
		_set_status("Maniquí · %s: %s daño/s durante %d s%s." % [p["name"], T.format_amount(r["dps"]), r["seconds"], " · ¡combinación descubierta!" if r["was_new"] else ""])
	dummy_tested.emit(p, r)
	refresh()
	return r


func equip_current(slot_type: String = PowersServiceScript.SLOT_ACTIVE, index: int = -1) -> Dictionary:
	var p := get_current_power()
	var idx := index
	if idx < 0 and slot_type == PowersServiceScript.SLOT_ACTIVE:
		idx = service.first_free_active_slot()
		if idx < 0:
			return {"ok": false, "reason": "no_free_slot"}
	var r: Dictionary = service.equip(slot_type, maxi(idx, 0), p)
	if r.get("ok", false):
		_set_status("%s equipado en la ranura %d." % [p["name"], idx + 1])
	power_equipped.emit(r)
	refresh()
	return r


# ==========================================================================
# API · Atlas
# ==========================================================================
func select_atlas_pair(a: String, b: String) -> void:
	if not service.has_energy(a) or not service.has_energy(b):
		return
	var s: Array[String] = service.sort_energies([a, b])
	atlas_selected = s
	_refresh_atlas()
	atlas_pair_selected.emit(s[0], s[1])


func set_atlas_role(role: String) -> void:
	atlas_role = role
	_refresh_atlas()


func get_atlas_cell_button(a: String, b: String) -> AtlasCell:
	return atlas_cells.get(service.pair_key(a, b), null)


## «Llevar al Crisol»: carga la pareja seleccionada (pura = la misma dos veces).
func bring_to_crucible() -> Dictionary:
	set_crucible([atlas_selected[0], atlas_selected[1]])
	select_subtab("crisol")
	_set_status("%s + %s en el Crisol: elige forma y ritmo." % [service.energy_name(atlas_selected[0]), service.energy_name(atlas_selected[1])])
	return current_power


# ==========================================================================
# API · Constelación
# ==========================================================================
func select_node(node_id: String) -> void:
	if service.get_star(node_id).is_empty():
		return
	selected_node = node_id
	_refresh_constellation()
	constellation_node_selected.emit(node_id)


func assign_point() -> Dictionary:
	var r: Dictionary = service.allocate_point(selected_node)
	if r.get("ok", false):
		_set_status("%s sube a rango %d." % [service.get_star(selected_node)["name"], r["rank"]])
	else:
		_set_status("No se puede asignar: %s." % {"max_rank": "rango máximo", "locked": "nodo bloqueado", "not_enough_points": "faltan puntos"}.get(r.get("reason", ""), str(r.get("reason", ""))))
	point_assigned.emit(selected_node, r)
	refresh()
	return r


func _recommended_node() -> String:
	for n in service.nodes:
		if service.get_node_state(n["id"]) != PowersServiceScript.NODE_LOCKED and int(n["rank"]) < int(n["max_rank"]) and float(n.get("potency_pct", 0)) > 0:
			return n["id"]
	return selected_node


func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not (event is InputEventKey) or not event.pressed:
		return
	var k := event as InputEventKey
	if k.keycode == KEY_Z and k.ctrl_pressed and (pages["constelacion"] as Control).visible:
		if service.undo_last():
			_set_status("Cambio deshecho.")
			refresh()
		get_viewport().set_input_as_handled()


# ==========================================================================
# Helpers de UI
# ==========================================================================
func _set_status(msg: String) -> void:
	if status_label:
		status_label.text = msg


func _energy_row(e: String) -> Button:
	var b := Button.new()
	b.name = "Energy_" + e
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(0, 36)
	b.tooltip_text = "%s · nv %d (clic: añadir al crisol)" % [service.energy_name(e), service.get_affinity_level(e)]
	var col: Color = service.energy_color(e)
	b.add_theme_stylebox_override("focus", T.box(Color.TRANSPARENT, 9, 1, T.ACCENT_DEFAULT))
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 8
	row.offset_right = -8
	row.add_theme_constant_override("separation", 10)
	b.add_child(row)
	var d := Dot.new()
	d.color = col
	d.radius_ratio = 0.5
	d.custom_minimum_size = Vector2(20, 36)
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(d)
	var v := _vbox(3)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(v)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(top)
	var n := _label(service.energy_name(e), 12, T.TEXT, "semibold")
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(n)
	top.add_child(_label("nv %d" % service.get_affinity_level(e), 11, T.TEXT_SECONDARY))
	var bar := FillBar.new()
	bar.custom_minimum_size.y = 3
	bar.fill = col
	bar.ratio = float(service.get_affinity_level(e)) / float(PowersServiceScript.AFFINITY_MAX_LEVEL)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(bar)
	b.pressed.connect(func() -> void: add_energy_to_crucible(e))
	b.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_RIGHT:
			remove_energy_key(e))
	return b


func _style_energy_rows() -> void:
	for e in energy_rows:
		var b: Button = energy_rows[e]
		var in_mixer := mixer.has(e)
		var col: Color = service.energy_color(e)
		var normal := T.box(Color(col, 0.10) if in_mixer else Color.TRANSPARENT, 9, 2 if in_mixer else 0, col)
		b.add_theme_stylebox_override("normal", normal)
		b.add_theme_stylebox_override("hover", T.box(T.POWERS_SUB_BG, 9, 2 if in_mixer else 0, col))
		b.add_theme_stylebox_override("pressed", normal)
		b.set_meta("in_crucible", in_mixer)


func _slot_card(core: bool) -> PanelContainer:
	var p := PanelContainer.new()
	var row := HBoxContainer.new()
	row.name = "Row"
	row.add_theme_constant_override("separation", 8)
	p.add_child(row)
	if core:
		var icon := PanelContainer.new()
		icon.custom_minimum_size = Vector2(38, 38)
		icon.add_theme_stylebox_override("panel", T.box(Color("#2a1f3a"), 8))
		row.add_child(icon)
	var v := _vbox(3)
	v.name = "Info"
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(v)
	var n := _label("", 13 if core else 12, T.TEXT, "bold")
	n.name = "Name"
	n.clip_text = true
	v.add_child(n)
	var dots := DotRow.new()
	dots.name = "Dots"
	dots.custom_minimum_size = Vector2(60, 10)
	v.add_child(dots)
	var k := _label("", 10, T.OFFER_GOLD if core else T.TEXT_SECONDARY)
	k.name = "Key"
	k.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(k)
	p.set_meta("core", core)
	return p


func _fill_slot_card(p: PanelContainer, view: Dictionary, key_text: String, target: bool) -> void:
	var core: bool = p.get_meta("core", false)
	var border := T.OFFER_GOLD if core else (T.ACCENT_DEFAULT if target else Color.TRANSPARENT)
	var sb := T.box(T.POWERS_SUB_BG, 10, 2 if (core or target) else 0, border)
	sb.set_content_margin_all(9)
	p.add_theme_stylebox_override("panel", sb)
	var n: Label = p.get_node("Row/Info/Name")
	n.text = view["name"] if not view["empty"] else ("Ranura libre" if not target else "→ " + str(current_power.get("name", "")))
	n.add_theme_color_override("font_color", T.ACCENT_DEFAULT if target else (T.TEXT if not view["empty"] else T.TEXT_MUTED))
	var cols: Array[Color] = []
	var src: Array = view["energies"] if not view["empty"] else (current_power.get("energies", []) if target else [])
	for e in src:
		cols.append(service.energy_color(e))
	(p.get_node("Row/Info/Dots") as DotRow).set_colors(cols)
	(p.get_node("Row/Key") as Label).text = key_text
	p.set_meta("slot_key", view["key"])


func _tag(text: String) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := T.box(T.POWERS_CHIP_BG, 6)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	p.add_theme_stylebox_override("panel", sb)
	p.add_child(_label(text, 11, T.TEXT_KEY))
	return p


func _card(node_name: String) -> PanelContainer:
	var p := PanelContainer.new()
	p.name = node_name
	var sb := T.box(T.POWERS_CARD_BG, 16, 1, T.CODEX_CARD_BORDER)
	sb.set_content_margin_all(16)
	p.add_theme_stylebox_override("panel", sb)
	return p


func _result_box(border: Color) -> StyleBoxFlat:
	var sb := T.box(T.POWERS_SUB_BG, 12, 2, border)
	sb.set_content_margin_all(12)
	return sb


func _input_box() -> StyleBoxFlat:
	var sb := T.box(T.WELL, 8, 1, Color(1, 1, 1, 0.08))
	sb.content_margin_left = 10
	return sb


func _vbox(sep: int) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


func _spacer(sz: Vector2) -> Control:
	var c := Control.new()
	c.custom_minimum_size = sz
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _keycap(text: String) -> PanelContainer:
	var cap := PanelContainer.new()
	var sb := T.box(T.BUTTON_BG, 5, 1, Color(1, 1, 1, 0.14))
	sb.content_margin_left = 5
	sb.content_margin_right = 5
	cap.add_theme_stylebox_override("panel", sb)
	cap.add_child(_label(text, 10, T.TEXT_KEY, "bold"))
	return cap


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
		b.add_theme_color_override(s, T.POWERS_PRIMARY_TEXT)
	b.add_theme_color_override("font_disabled_color", Color(T.POWERS_PRIMARY_TEXT, 0.6))
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
	return l


# ==========================================================================
# Controles dibujados
# ==========================================================================
## Círculo de energía.
class Dot extends Control:
	var color: Color = Color.WHITE:
		set(v):
			color = v
			queue_redraw()
	var radius_ratio := 0.42

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var r := minf(size.x, size.y) * radius_ratio
		draw_circle(size * 0.5, r, color, true, -1.0, true)


## Fila de puntos de energía (ranuras del conjunto).
class DotRow extends Control:
	var colors: Array[Color] = []

	func set_colors(c: Array[Color]) -> void:
		colors = c
		queue_redraw()

	func _draw() -> void:
		var r := size.y * 0.5
		for i in colors.size():
			draw_circle(Vector2(r + i * (r * 2.0 + 3.0), r), r, colors[i], true, -1.0, true)


## Barra de progreso plana (fondo pozo + relleno de color).
class FillBar extends Control:
	const TK = preload("res://ui/tokens/hud_tokens.gd")
	var fill: Color = Color.WHITE:
		set(v):
			fill = v
			queue_redraw()
	var ratio: float = 0.0:
		set(v):
			ratio = clampf(v, 0.0, 1.0)
			queue_redraw()

	func _draw() -> void:
		var rad := int(size.y * 0.5)
		draw_style_box(TK.box(TK.WELL, rad), Rect2(Vector2.ZERO, size))
		if ratio > 0.0:
			draw_style_box(TK.box(fill, rad), Rect2(Vector2.ZERO, Vector2(maxf(size.y, size.x * ratio), size.y)))


## Barra apilada de resonancia (un tramo por energía, ancho = nº de poderes).
class ResonanceBar extends Control:
	const TK = preload("res://ui/tokens/hud_tokens.gd")
	var segments: Array = []

	func set_segments(s: Array) -> void:
		segments = s
		queue_redraw()

	func _draw() -> void:
		draw_style_box(TK.box(TK.WELL, int(size.y * 0.5)), Rect2(Vector2.ZERO, size))
		var total := 0.0
		for s in segments:
			total += float(s["weight"])
		if total <= 0.0:
			return
		var x := 0.0
		for i in segments.size():
			var w := size.x * float(segments[i]["weight"]) / total
			var sb := TK.box(segments[i]["color"], 0)
			var rad := int(size.y * 0.5)
			if i == 0:
				sb.corner_radius_top_left = rad
				sb.corner_radius_bottom_left = rad
			if i == segments.size() - 1:
				sb.corner_radius_top_right = rad
				sb.corner_radius_bottom_right = rad
			draw_style_box(sb, Rect2(x, 0, w, size.y))
			x += w


## Mezclador del Crisol: 3 orbes (el 3.º opcional) alrededor de un núcleo partido por colores.
class CrucibleView extends Control:
	const TK = preload("res://ui/tokens/hud_tokens.gd")
	signal slot_clicked(index: int)
	const ANGLES := [-90.0, 150.0, 30.0]
	var colors: Array[Color] = []
	var names: Array[String] = []

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func set_slots(c: Array[Color], n: Array[String]) -> void:
		colors = c
		names = n
		queue_redraw()

	func ring_radius() -> float:
		return minf(size.x, size.y - 24.0) * 0.40

	func slot_center(i: int) -> Vector2:
		var c := Vector2(size.x * 0.5, (size.y - 16.0) * 0.5 + 4.0)
		var a := deg_to_rad(ANGLES[i])
		return c + Vector2(cos(a), sin(a)) * ring_radius()

	func slot_radius(i: int) -> float:
		return ring_radius() * (0.34 if i < 2 else 0.27)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			for i in 3:
				if event.position.distance_to(slot_center(i)) <= slot_radius(i):
					slot_clicked.emit(i)
					accept_event()
					return

	func _draw() -> void:
		var c := Vector2(size.x * 0.5, (size.y - 16.0) * 0.5 + 4.0)
		var rr := ring_radius()
		# Anillo punteado
		var segs := 72
		for i in segs:
			if i % 2 == 0:
				var a0 := TAU * i / segs
				var a1 := TAU * (i + 1) / segs
				draw_line(c + Vector2(cos(a0), sin(a0)) * rr, c + Vector2(cos(a1), sin(a1)) * rr, Color(TK.ACCENT_DEFAULT, 0.45), 1.5, true)
		# Núcleo partido por energías
		var filled: Array[Color] = []
		for col in colors:
			if col.a > 0.0:
				filled.append(col)
		var core_r := rr * 0.5
		if filled.is_empty():
			draw_circle(c, core_r, TK.POWERS_SUB_BG, true, -1.0, true)
		else:
			var n := filled.size()
			for i in n:
				var pts := PackedVector2Array([c])
				var start := -PI * 0.5 + TAU * i / n
				for k in 25:
					var a := start + (TAU / n) * k / 24.0
					pts.append(c + Vector2(cos(a), sin(a)) * core_r)
				draw_colored_polygon(pts, filled[i].darkened(0.45))
			# Glifo en espiral
			var sp := PackedVector2Array()
			for k in 40:
				var t := float(k) / 39.0
				var a := t * TAU * 1.4
				sp.append(c + Vector2(cos(a), sin(a)) * core_r * 0.35 * t)
			draw_polyline(sp, Color(1, 1, 1, 0.85), 2.0, true)
		draw_arc(c, core_r, 0, TAU, 64, Color(1, 1, 1, 0.15), 1.5, true)
		var f := TK.font("bold")
		for i in 3:
			var p := slot_center(i)
			var r := slot_radius(i)
			var has: bool = i < colors.size() and colors[i].a > 0.0
			if has:
				for g in 4:
					draw_circle(p, r + 8 - g * 2, Color(colors[i], 0.08 + g * 0.04), true, -1.0, true)
				draw_circle(p, r, colors[i], true, -1.0, true)
				var nm: String = names[i] if i < names.size() else ""
				var tw := f.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
				draw_string(f, p + Vector2(-tw * 0.5, r + 16), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, TK.TEXT)
			else:
				draw_circle(p, r, TK.POWERS_CARD_BG, true, -1.0, true)
				draw_arc(p, r, 0, TAU, 48, Color(1, 1, 1, 0.25), 1.5, true)
				var plus := "+"
				var pw := f.get_string_size(plus, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
				draw_string(f, p + Vector2(-pw * 0.5, 6), plus, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, TK.TEXT_SECONDARY)
				var lab := "Opcional" if i == 2 else "Energía"
				var lw := f.get_string_size(lab, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
				draw_string(f, p + Vector2(-lw * 0.5, r + 14), lab, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, TK.TEXT_SECONDARY)


## Celda del Atlas: descubierta (diagonal de 2 colores + nº), pista («?»), desconocida («???»).
class AtlasCell extends Button:
	const TK = preload("res://ui/tokens/hud_tokens.gd")
	const PS = preload("res://shared-core/PowersService.gd")
	var cell: Dictionary = {}
	var color_a: Color = Color.WHITE
	var color_b: Color = Color.WHITE
	var selected := false

	func _init() -> void:
		flat = true
		focus_mode = Control.FOCUS_ALL
		var empty := StyleBoxEmpty.new()
		for s in ["normal", "hover", "pressed", "focus", "disabled"]:
			add_theme_stylebox_override(s, empty)

	func setup(c: Dictionary, a: Color, b: Color) -> void:
		cell = c
		color_a = a
		color_b = b
		text = ""
		tooltip_text = _tooltip()
		set_meta("cell_text", get_cell_text())
		queue_redraw()

	func get_state() -> String:
		return str(cell.get("state", PS.CELL_UNKNOWN))

	func get_cell_text() -> String:
		return PS.cell_label(cell)

	func _tooltip() -> String:
		var st := get_state()
		if st == PS.CELL_DISCOVERED:
			return "%d fórmulas descubiertas" % int(cell.get("count", 0))
		if st == PS.CELL_HINT:
			return "Pista: " + str(cell.get("hint", ""))
		return "??? · sin descubrir"

	static func rounded_rect(sz: Vector2, rad: float) -> PackedVector2Array:
		var pts := PackedVector2Array()
		var centers := [Vector2(sz.x - rad, rad), Vector2(sz.x - rad, sz.y - rad), Vector2(rad, sz.y - rad), Vector2(rad, rad)]
		for c in 4:
			for k in 7:
				var a := -PI * 0.5 + PI * 0.5 * c + PI * 0.5 * k / 6.0
				pts.append(centers[c] + Vector2(cos(a), sin(a)) * rad)
		return pts

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var rad := 7
		var st := get_state()
		var f := TK.font("bold")
		var txt := get_cell_text()
		var txt_col := TK.TEXT
		var fs := 13
		if st == PS.CELL_DISCOVERED:
			if bool(cell.get("pure", false)):
				draw_style_box(TK.box(TK.POWERS_CELL_PURE, rad, 1, Color(1, 1, 1, 0.10)), r)
			else:
				# Diagonal: arriba-izquierda = energía de la fila, abajo-derecha = columna.
				var rounded := rounded_rect(size, rad)
				var big := maxf(size.x, size.y) * 2.0
				var tl := Geometry2D.intersect_polygons(rounded, PackedVector2Array([Vector2(-1, -1), Vector2(size.x + 1, -1), Vector2(-1, size.y + 1)]))
				var br := Geometry2D.intersect_polygons(rounded, PackedVector2Array([Vector2(size.x + 1, -1), Vector2(big, big), Vector2(-1, size.y + 1)]))
				for poly in tl:
					draw_colored_polygon(poly, color_a.darkened(0.35))
				for poly in br:
					draw_colored_polygon(poly, color_b.darkened(0.35))
		elif st == PS.CELL_HINT:
			draw_style_box(TK.box(TK.POWERS_CELL_UNKNOWN, rad, 2, TK.POWERS_HINT), r)
			txt_col = TK.POWERS_HINT
			fs = 12
		else:
			draw_style_box(TK.box(TK.POWERS_CELL_UNKNOWN, rad, 1, Color(1, 1, 1, 0.05)), r)
			txt_col = Color(TK.TEXT_MUTED, 0.45)
			fs = 9
		if selected:
			draw_style_box(TK.box(Color.TRANSPARENT, rad, 2, Color.WHITE), r)
		if has_focus():
			draw_style_box(TK.box(Color.TRANSPARENT, rad, 1, TK.ACCENT_DEFAULT), r.grow(2))
		var ts := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		draw_string(f, Vector2((size.x - ts.x) * 0.5, (size.y + fs * 0.75) * 0.5), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, txt_col)


## Árbol de la Constelación: estrellas, aristas, nodos (activo, disponible, bloqueado, piedra angular).
class ConstellationView extends Control:
	const TK = preload("res://ui/tokens/hud_tokens.gd")
	const PS = preload("res://shared-core/PowersService.gd")
	signal node_clicked(id: String)
	const BASE_R := 13.0
	var svc: Node = null
	var selected_id := ""

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		clip_contents = true

	func setup(service: Node, sel: String) -> void:
		svc = service
		selected_id = sel
		queue_redraw()

	func node_pos(n: Dictionary) -> Vector2:
		var at: Array = n.get("at", [0.5, 0.5])
		var area := Rect2(16, 44, size.x - 32, size.y - 80)
		return area.position + Vector2(float(at[0]) * area.size.x, float(at[1]) * area.size.y)

	func node_radius(n: Dictionary) -> float:
		return BASE_R * float(n.get("size", 1.0))

	func node_at(p: Vector2) -> String:
		if svc == null:
			return ""
		for n in svc.nodes:
			if p.distance_to(node_pos(n)) <= node_radius(n) + 4.0:
				return n["id"]
		return ""

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var id := node_at(event.position)
			if id != "":
				node_clicked.emit(id)
				accept_event()

	func _get_tooltip(at: Vector2) -> String:
		var id := node_at(at)
		if id == "" or svc == null:
			return ""
		var n: Dictionary = svc.get_star(id)
		return "%s · %d/%d · coste %d" % [n["name"], n["rank"], n["max_rank"], n["cost"]]

	func _draw() -> void:
		draw_style_box(TK.box(TK.POWERS_TREE_BG, 12), Rect2(Vector2.ZERO, size))
		var rng := RandomNumberGenerator.new()
		rng.seed = 4242
		for i in 26:
			draw_circle(Vector2(rng.randf() * size.x, rng.randf() * size.y), rng.randf_range(0.6, 1.3), Color(1, 1, 1, rng.randf_range(0.15, 0.4)))
		if svc == null:
			return
		var f := TK.font("bold")
		# Aristas
		for n in svc.nodes:
			for req in n.get("requires", []):
				var parent: Dictionary = svc.get_star(req)
				if parent.is_empty():
					continue
				var a := node_pos(parent)
				var b := node_pos(n)
				if int(n["rank"]) > 0 and int(parent["rank"]) > 0:
					draw_line(a, b, TK.POWERS_EDGE_ACTIVE, 2.5, true)
				else:
					draw_dashed_line(a, b, TK.POWERS_EDGE_LOCKED, 1.5, 4.0, true, true)
		# Etiquetas de rama
		for br in svc.branches:
			var at: Array = br["at"]
			var area := Rect2(16, 44, size.x - 32, size.y - 80)
			var p := area.position + Vector2(float(at[0]) * area.size.x, float(at[1]) * area.size.y)
			var txt := str(br["label"]).to_upper()
			var tw := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
			draw_string(f, p - Vector2(tw * 0.5, 0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, TK.energy_color(br["energy"]).lightened(0.15))
		# Nodos
		for n in svc.nodes:
			var p := node_pos(n)
			var r := node_radius(n)
			var st: String = svc.get_node_state(n["id"])
			var key: bool = n.get("keystone", false)
			var label := str(n["rank"])
			var txt_col := TK.TEXT_DARK
			if n["id"] == selected_id:
				for g in 4:
					draw_circle(p, r + 12 - g * 3, Color(TK.POWERS_NODE_ACTIVE, 0.06 + g * 0.03), true, -1.0, true)
			if key and int(n["rank"]) == 0:
				draw_circle(p, r, TK.POWERS_TREE_BG, true, -1.0, true)
				draw_arc(p, r, 0, TAU, 48, TK.POWERS_NODE_KEYSTONE if st != PS.NODE_LOCKED else Color(TK.POWERS_NODE_KEYSTONE, 0.75), 2.5, true)
				label = ""
			elif st == PS.NODE_ACTIVE:
				draw_circle(p, r + 3, Color(TK.POWERS_NODE_ACTIVE, 0.25), true, -1.0, true)
				draw_circle(p, r, TK.POWERS_NODE_ACTIVE, true, -1.0, true)
			elif st == PS.NODE_AVAILABLE:
				draw_circle(p, r, TK.POWERS_TREE_BG, true, -1.0, true)
				draw_arc(p, r, 0, TAU, 48, TK.POWERS_NODE_ACTIVE, 2.0, true)
				txt_col = TK.POWERS_NODE_ACTIVE
			else:
				draw_circle(p, r, TK.POWERS_NODE_LOCKED, true, -1.0, true)
				txt_col = TK.TEXT_MUTED
			if n["id"] == selected_id:
				draw_arc(p, r + 2, 0, TAU, 48, Color.WHITE, 2.0, true)
			if label != "":
				var fs := 12 if r > BASE_R else 10
				var ts := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
				draw_string(f, p + Vector2(-ts.x * 0.5, fs * 0.38), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, txt_col)
		# Etiqueta del nodo seleccionado
		var sel: Dictionary = svc.get_star(selected_id)
		if not sel.is_empty():
			var sp := node_pos(sel)
			var txt := "%s · %d/%d" % [sel["name"], sel["rank"], sel["max_rank"]]
			var ts := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11)
			var box := Rect2(sp + Vector2(-ts.x * 0.5 - 10 - 40, -node_radius(sel) - 34), Vector2(ts.x + 20, 24))
			box.position.x = clampf(box.position.x, 4, size.x - box.size.x - 4)
			draw_style_box(TK.box(TK.POWERS_CARD_BG, 8, 1, TK.POWERS_NODE_ACTIVE), box)
			draw_string(f, box.position + Vector2(10, 16), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, TK.TEXT)
		# Leyenda
		var lx := 18.0
		var ly := size.y - 18.0
		for item in [[TK.POWERS_NODE_ACTIVE, "Activo", 0], [TK.POWERS_NODE_ACTIVE, "Disponible", 1], [TK.POWERS_NODE_LOCKED, "Bloqueado", 0], [TK.POWERS_NODE_KEYSTONE, "Piedra angular", 1]]:
			if item[2] == 0:
				draw_circle(Vector2(lx + 5, ly - 4), 5, item[0], true, -1.0, true)
			else:
				draw_arc(Vector2(lx + 5, ly - 4), 5, 0, TAU, 24, item[0], 1.5, true)
			draw_string(f, Vector2(lx + 16, ly), item[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, TK.TEXT_SECONDARY)
			lx += 22 + f.get_string_size(item[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 14
