extends "res://ui/templates/BaseWindow.gd"
## Códice v2 (tecla J) — libro de conocimiento del jugador (UI v2.4, §2.3).
## Referencias: design_ref/pantallas_html/MMO-Codice.html, MMO-Inversiones.html y WEB-Wiki.html.
##
## Toda la información sale de `KnowledgeService` (autoload). La ventana nunca
## decide por su cuenta si algo se conoce: pide nombres con `display_name()`
## y las vistas enmascaradas con `get_entry_view()`.
##
## Sub-navegación: Entradas · Por decidir · Mis secretos · Publicados ·
## Inversiones · Propuestas a la wiki (en construcción).
## Barra superior: `menu_bar.tscn` con la pestaña «codice» activa.

const T = preload("res://ui/tokens/hud_tokens.gd")
const MenuBarScene = preload("res://ui/menu/menu_bar.tscn")
const KnowledgeServiceScript = preload("res://shared-core/KnowledgeService.gd")
const ConstructionBanner = preload("res://ui/components/base/under_construction_banner.gd")

signal subtab_changed(subtab_id: String)
signal decision_made(entry_id: String, result: Dictionary)
signal discovery_map_created(map_item: Dictionary)
signal payout_collected(amount: int)

const MENU_TAB_ID := "codice"
const WINDOW_SIZE := Vector2(1270, 680)  # menu_bar exige ~1263 px de ancho mínimo

## Sub-pestañas (datos). `badge` = contador dinámico mostrado como « · N».
const SUBTABS: Array[Dictionary] = [
	{"id": "entradas", "label": "Entradas"},
	{"id": "por_decidir", "label": "Por decidir", "badge": "pending"},
	{"id": "secretos", "label": "Mis secretos"},
	{"id": "publicados", "label": "Publicados"},
	{"id": "inversiones", "label": "Inversiones"},
	{"id": "propuestas", "label": "Propuestas a la wiki", "under_construction": true},
]

const STATUS_LABELS := {
	"active": ["Activo", T.CODEX_PUBLISHED],
	"low_traffic": ["Poco tráfico", T.CODEX_WARNING],
	"paused": ["Pausado · tienda cerrada", T.CODEX_SEEN],
	"mission": ["Misión", T.CODEX_SECRET],
}

## Servicio inyectable (tests). Si es null se usa el autoload /root/KnowledgeService.
var service: Node = null

var menu_bar: Node
var subnav_buttons: Dictionary = {}   # subtab_id -> Button
var pages: Dictionary = {}            # subtab_id -> Control
var current_subtab: String = ""
var current_category: String = ""     # "" = Todo
var current_query: String = ""
var selected_entry_id: String = ""
var status_label: Label

# Entradas
var category_buttons: Dictionary = {} # category_id ("" = todo) -> Button
var entries_grid: GridContainer
var entries_header: Label
var status_chips: Dictionary = {}     # secrets/published/pioneer/seen -> Label
var detail_box: VBoxContainer
var search_input: LineEdit
# Listas
var pending_list: VBoxContainer
var secrets_list: VBoxContainer
var published_list: VBoxContainer
# Modal de decisión
var decision_modal: Control
var decision_entry_id: String = ""
var decision_title: Label
var decision_keep_button: Button
var decision_publish_button: Button
var decision_map_button: Button
var decision_cancel_button: Button
var decision_reward_label: Label
# Inversiones
var kpi_labels: Dictionary = {}
var earnings_chart: EarningsChart
var investments_table: VBoxContainer
var payout_label: Label
var collect_button: Button
var offers_box: VBoxContainer
var notices_box: VBoxContainer
var map_sales_label: Label

var _pages_root: Control
var _built := false


func _init() -> void:
	custom_minimum_size = WINDOW_SIZE
	size = WINDOW_SIZE
	theme = T.THEME
	add_theme_stylebox_override("panel", _panel_box())
	_build()


func _ready() -> void:
	window_id = "codex_window"
	super._ready()
	add_to_group("codex_window")
	_resolve_service()
	_connect_menu_bar()
	set_title("Códice")
	select_subtab(SUBTABS[0]["id"] if current_subtab == "" else current_subtab)
	get_viewport().size_changed.connect(fit_to_viewport)
	fit_to_viewport.call_deferred()


## El menú común exige ~1263 px (más con cifras grandes de oro/Prismas). Si no
## cabe en el viewport, esta instancia pasa a modo compacto (márgenes 8 px y sin
## rótulo «MENÚ») y la ventana se limita al ancho disponible.
func fit_to_viewport() -> void:
	if not is_inside_tree() or menu_bar == null:
		return
	var vp_w := get_viewport_rect().size.x
	var margin := menu_bar.get_node_or_null("Margin") as MarginContainer
	var title := menu_bar.get_node_or_null("Margin/Row/Title") as Control
	if margin:
		margin.remove_theme_constant_override("margin_left")
		margin.remove_theme_constant_override("margin_right")
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
	var entry := str(params.get("entry_id", ""))
	if entry != "":
		show_entry(entry)


# ==========================================================================
# Servicio
# ==========================================================================
func _resolve_service() -> void:
	if service == null:
		service = get_node_or_null("/root/KnowledgeService")
	if service == null:
		service = KnowledgeServiceScript.new()
		service.name = "LocalKnowledgeService"
		add_child(service)
	for pair in [
		["visibility_changed", _on_service_changed_3],
		["pending_changed", _on_service_changed_1],
		["investments_changed", refresh],
		["notice_added", _on_service_changed_1],
		["gold_awarded", _on_gold_awarded],
	]:
		if not service.is_connected(pair[0], pair[1]):
			service.connect(pair[0], pair[1])


func _on_service_changed_1(_a = null) -> void:
	refresh.call_deferred()


func _on_service_changed_3(_a = null, _b = null, _c = null) -> void:
	refresh.call_deferred()


func _on_gold_awarded(amount: int, _reason: String) -> void:
	if menu_bar and menu_bar.gold_label:
		menu_bar.gold_label.amount += amount
		fit_to_viewport.call_deferred()


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
	menu_bar.set_anchors_preset(Control.PRESET_TOP_LEFT)
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
	header.add_theme_constant_override("separation", 6)
	col.add_child(header)
	var title := _label("Códice", 18, T.TEXT, "bold")
	title.name = "TitleLabel"
	header.add_child(title)
	var subnav := HBoxContainer.new()
	subnav.name = "Subnav"
	subnav.add_theme_constant_override("separation", 4)
	subnav.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	subnav.alignment = BoxContainer.ALIGNMENT_END
	header.add_child(subnav)
	for st in SUBTABS:
		var b := Button.new()
		b.name = "Sub_" + st["id"]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_ALL
		b.custom_minimum_size.y = 32
		b.add_theme_font_override("font", T.font("semibold"))
		b.add_theme_font_size_override("font_size", 14)
		var sid: String = st["id"]
		b.pressed.connect(func() -> void: select_subtab(sid))
		subnav.add_child(b)
		subnav_buttons[sid] = b

	_pages_root = Control.new()
	_pages_root.name = "Pages"
	_pages_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_pages_root.clip_contents = true
	col.add_child(_pages_root)
	pages["entradas"] = _build_entries_page()
	pages["por_decidir"] = _build_list_page("PendingPage", "Descubrimientos recientes: decide si guardas el secreto o lo publicas en la wiki.")
	pending_list = pages["por_decidir"].get_meta("list")
	pages["secretos"] = _build_list_page("SecretsPage", "Solo tú conoces estos secretos. Crea «Mapas del hallazgo» para venderlos en el mercado.")
	secrets_list = pages["secretos"].get_meta("list")
	pages["publicados"] = _build_list_page("PublishedPage", "Entradas publicadas en la wiki web. Publicar es permanente.")
	published_list = pages["publicados"].get_meta("list")
	pages["inversiones"] = _build_investments_page()
	pages["propuestas"] = _build_proposals_page()
	for id in pages:
		var p: Control = pages[id]
		p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		p.visible = false
		_pages_root.add_child(p)

	status_label = _label("", 12, T.TEXT_SECONDARY)
	status_label.name = "StatusLabel"
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(status_label)

	decision_modal = _build_decision_modal()
	add_child(decision_modal)


func _build_entries_page() -> Control:
	var page := HBoxContainer.new()
	page.name = "EntriesPage"
	page.add_theme_constant_override("separation", 14)

	# Barra lateral: búsqueda, categorías y estado.
	var side := VBoxContainer.new()
	side.name = "Sidebar"
	side.custom_minimum_size.x = 220
	side.add_theme_constant_override("separation", 6)
	page.add_child(side)
	search_input = LineEdit.new()
	search_input.name = "Search"
	search_input.placeholder_text = "Buscar en tu Códice"
	search_input.clear_button_enabled = true
	search_input.text_changed.connect(func(t: String) -> void:
		current_query = t
		_refresh_entries())
	side.add_child(search_input)
	var cats := VBoxContainer.new()
	cats.name = "Categories"
	cats.add_theme_constant_override("separation", 2)
	side.add_child(cats)
	side.set_meta("categories", cats)
	side.add_child(_label("Estado", 12, T.TEXT_MUTED, "bold"))
	var chips := HFlowContainer.new()
	chips.name = "StatusChips"
	chips.add_theme_constant_override("h_separation", 6)
	chips.add_theme_constant_override("v_separation", 6)
	side.add_child(chips)
	for c in [["secrets", T.CODEX_SECRET], ["published", T.CODEX_PUBLISHED], ["pioneer", T.CODEX_PIONEER], ["seen", T.TEXT_SECONDARY]]:
		var chip := _chip("", c[1])
		chips.add_child(chip)
		status_chips[c[0]] = chip.get_meta("label")
	var note := _label("El total del mundo nunca se revela: siempre puede haber algo más por descubrir.", 11, T.TEXT_MUTED)
	note.name = "WorldTotalNote"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(note)

	# Rejilla de entradas.
	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.add_theme_constant_override("separation", 8)
	page.add_child(center)
	entries_header = _label("", 15, T.TEXT, "semibold")
	entries_header.name = "EntriesHeader"
	center.add_child(entries_header)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	center.add_child(scroll)
	entries_grid = GridContainer.new()
	entries_grid.name = "EntriesGrid"
	entries_grid.columns = 3
	entries_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	entries_grid.add_theme_constant_override("h_separation", 8)
	entries_grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(entries_grid)

	# Detalle.
	var detail_panel := PanelContainer.new()
	detail_panel.custom_minimum_size.x = 300
	detail_panel.add_theme_stylebox_override("panel", _card_box(T.CODEX_CARD_BG))
	page.add_child(detail_panel)
	detail_box = VBoxContainer.new()
	detail_box.name = "Detail"
	detail_box.add_theme_constant_override("separation", 8)
	detail_panel.add_child(detail_box)
	page.set_meta("categories", cats)
	return page


func _build_list_page(node_name: String, intro: String) -> Control:
	var page := VBoxContainer.new()
	page.name = node_name
	page.add_theme_constant_override("separation", 8)
	var l := _label(intro, 13, T.TEXT_SECONDARY)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(l)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)
	var list := VBoxContainer.new()
	list.name = "List"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	page.set_meta("list", list)
	return page


func _build_investments_page() -> Control:
	var page := HBoxContainer.new()
	page.name = "InvestmentsPage"
	page.add_theme_constant_override("separation", 14)
	var main := VBoxContainer.new()
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", 10)
	page.add_child(main)

	var kpis := HBoxContainer.new()
	kpis.name = "KPIs"
	kpis.add_theme_constant_override("separation", 8)
	main.add_child(kpis)
	for k in [["today", "Hoy"], ["week", "Esta semana"], ["value", "Valor de tus participaciones"], ["published", "Conocimiento publicado"]]:
		var tile := PanelContainer.new()
		tile.name = "KPI_" + k[0]
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tile.add_theme_stylebox_override("panel", _card_box(T.CODEX_CARD_BG))
		var v := VBoxContainer.new()
		tile.add_child(v)
		v.add_child(_label(k[1], 12, T.TEXT_SECONDARY))
		var value := _label("0", 20, T.TEXT, "bold")
		value.name = "Value"
		v.add_child(value)
		var sub := _label("", 11, T.TEXT_MUTED)
		sub.name = "Sub"
		v.add_child(sub)
		kpis.add_child(tile)
		kpi_labels[k[0]] = value
		kpi_labels[k[0] + "_sub"] = sub

	var chart_card := PanelContainer.new()
	chart_card.add_theme_stylebox_override("panel", _card_box(T.CODEX_CARD_BG))
	main.add_child(chart_card)
	var chart_col := VBoxContainer.new()
	chart_card.add_child(chart_col)
	var ch := HBoxContainer.new()
	ch.add_child(_label("Ganancias de los últimos 14 días", 13, T.TEXT, "semibold"))
	var unit := _label("oro por día", 11, T.TEXT_MUTED)
	unit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	unit.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ch.add_child(unit)
	chart_col.add_child(ch)
	earnings_chart = EarningsChart.new()
	earnings_chart.name = "EarningsChart"
	earnings_chart.custom_minimum_size = Vector2(0, 120)
	chart_col.add_child(earnings_chart)

	var table_head := HBoxContainer.new()
	for h in [["Inversión", 0], ["Parte", 70], ["Tráfico", 120], ["Hoy", 70], ["Estado", 150]]:
		var hl := _label(h[0], 11, T.TEXT_MUTED, "bold")
		if h[1] == 0:
			hl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		else:
			hl.custom_minimum_size.x = h[1]
		table_head.add_child(hl)
	main.add_child(table_head)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main.add_child(scroll)
	investments_table = VBoxContainer.new()
	investments_table.name = "InvestmentsTable"
	investments_table.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	investments_table.add_theme_constant_override("separation", 4)
	scroll.add_child(investments_table)

	var side := VBoxContainer.new()
	side.custom_minimum_size.x = 300
	side.add_theme_constant_override("separation", 10)
	page.add_child(side)
	var payout_card := PanelContainer.new()
	payout_card.add_theme_stylebox_override("panel", _card_box(T.CODEX_CARD_BG, T.CODEX_PIONEER))
	side.add_child(payout_card)
	var pv := VBoxContainer.new()
	payout_card.add_child(pv)
	pv.add_child(_label("Por cobrar", 12, T.TEXT_SECONDARY))
	payout_label = _label("0 oro", 22, T.GOLD_TEXT, "bold")
	payout_label.name = "PayoutLabel"
	pv.add_child(payout_label)
	collect_button = _action_button("Cobrar al Refugio", T.CODEX_PIONEER, true)
	collect_button.name = "CollectButton"
	collect_button.tooltip_text = "Enviar al almacén del refugio"
	collect_button.pressed.connect(collect_investments)
	pv.add_child(collect_button)
	side.add_child(_label("Ofertas pendientes", 13, T.TEXT, "semibold"))
	offers_box = VBoxContainer.new()
	offers_box.name = "Offers"
	side.add_child(offers_box)
	side.add_child(_label("Avisos", 13, T.TEXT, "semibold"))
	notices_box = VBoxContainer.new()
	notices_box.name = "Notices"
	side.add_child(notices_box)
	side.add_child(_label("Mapas del hallazgo en venta", 13, T.TEXT, "semibold"))
	map_sales_label = _label("", 12, T.TEXT_SECONDARY)
	map_sales_label.name = "MapSales"
	side.add_child(map_sales_label)
	return page


func _build_proposals_page() -> Control:
	var page := VBoxContainer.new()
	page.name = "ProposalsPage"
	var banner := ConstructionBanner.new()
	banner.message = "Propón cambios a entradas publicadas: la comunidad vota y el pionero decide durante 48 h."
	page.add_child(banner)
	return page


func _build_decision_modal() -> Control:
	var overlay := ColorRect.new()
	overlay.name = "DecisionModal"
	overlay.color = Color(0, 0, 0, 0.62)
	overlay.visible = false
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(760, 0)
	panel.add_theme_stylebox_override("panel", _panel_box())
	center.add_child(panel)
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 20)
	panel.add_child(m)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	m.add_child(col)
	decision_title = _label("", 18, T.TEXT, "bold")
	decision_title.name = "DecisionTitle"
	col.add_child(decision_title)
	var who := _label("Eres el pionero. Los demás jugadores lo ven como «???».", 13, T.TEXT_SECONDARY)
	who.name = "DecisionWho"
	col.add_child(who)
	col.add_child(_label("¿Qué haces con este conocimiento?", 15, T.TEXT, "semibold"))

	var sides := HBoxContainer.new()
	sides.name = "Options"
	sides.add_theme_constant_override("separation", 12)
	col.add_child(sides)
	# Opción A — Guardar el secreto.
	var a := _option_card("OptionSecret", "Guardar el secreto", T.CODEX_SECRET, [
		"Solo tú ves su nombre, dónde aparece y qué hace.",
		"Tu mapa marca dónde lo encontraste.",
		"Puedes crear un «Mapa del hallazgo» y venderlo en el mercado.",
	])
	sides.add_child(a)
	decision_map_button = _action_button("Crear mapa del hallazgo · vender", T.CODEX_SECRET, false)
	decision_map_button.name = "MapButton"
	decision_map_button.pressed.connect(func() -> void: create_map_for(decision_entry_id))
	a.get_meta("body").add_child(decision_map_button)
	# Opción B — Publicar en la wiki.
	var b := _option_card("OptionPublish", "Publicar en la wiki", T.CODEX_PUBLISHED, [
		"Pionero en la wiki web (Hall of Fame) y un título.",
		"Bonus de oro inmediato.",
		"Después puedes proponer cambios a la entrada.",
	])
	sides.add_child(b)
	decision_reward_label = _label("", 13, T.GOLD_TEXT, "semibold")
	decision_reward_label.name = "Reward"
	b.get_meta("body").add_child(decision_reward_label)

	var warn := _label("Publicar es permanente. Guardar el secreto no: puedes publicarlo cuando quieras, pero si otro lo publica antes, pierdes el título de pionero de la wiki.", 12, T.CODEX_WARNING)
	warn.name = "PermanentWarning"
	warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(warn)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	buttons.alignment = BoxContainer.ALIGNMENT_END
	col.add_child(buttons)
	decision_cancel_button = _action_button("Decidir más tarde", T.TEXT_SECONDARY, false)
	decision_cancel_button.name = "CancelButton"
	decision_cancel_button.pressed.connect(close_decision)
	buttons.add_child(decision_cancel_button)
	decision_keep_button = _action_button("Guardar el secreto", T.CODEX_SECRET, false)
	decision_keep_button.name = "KeepButton"
	decision_keep_button.pressed.connect(func() -> void: confirm_decision(false))
	buttons.add_child(decision_keep_button)
	decision_publish_button = _action_button("Publicar", T.CODEX_PUBLISHED, true)
	decision_publish_button.name = "PublishButton"
	decision_publish_button.pressed.connect(func() -> void: confirm_decision(true))
	buttons.add_child(decision_publish_button)
	return overlay


func _option_card(node_name: String, title: String, accent: Color, bullets: Array) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = node_name
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", _card_box(T.CODEX_CARD_BG, accent))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	card.add_child(v)
	v.add_child(_label(title, 15, accent, "bold"))
	for line in bullets:
		var l := _label("•  " + str(line), 12, T.TEXT_SECONDARY)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(l)
	card.set_meta("body", v)
	return card


# ==========================================================================
# Navegación
# ==========================================================================
func get_subtab_ids() -> Array[String]:
	var out: Array[String] = []
	for st in SUBTABS:
		out.append(st["id"])
	return out


func select_subtab(subtab_id: String) -> void:
	if not pages.has(subtab_id):
		push_warning("[Codex] Sub-pestaña desconocida: %s" % subtab_id)
		return
	current_subtab = subtab_id
	for id in pages:
		(pages[id] as Control).visible = id == subtab_id
	refresh()
	subtab_changed.emit(subtab_id)


func select_category(category_id: String) -> void:
	current_category = category_id
	_refresh_entries()


func refresh() -> void:
	if service == null:
		return
	_refresh_subnav()
	match current_subtab:
		"entradas": _refresh_entries()
		"por_decidir": _refresh_pending()
		"secretos": _refresh_secrets()
		"publicados": _refresh_published()
		"inversiones": _refresh_investments()
	if decision_modal.visible and decision_entry_id != "":
		_fill_decision(decision_entry_id)


func _refresh_subnav() -> void:
	var pending_n := int(service.get_status_counts()["pending"])
	for st in SUBTABS:
		var b: Button = subnav_buttons[st["id"]]
		var text := str(st["label"])
		if st.get("badge", "") == "pending" and pending_n > 0:
			text += " · %d" % pending_n
		b.text = text
		var on: bool = st["id"] == current_subtab
		b.set_pressed_no_signal(on)
		b.add_theme_stylebox_override("normal", _subnav_box(T.CODEX_SUBNAV_ACTIVE if on else Color.TRANSPARENT))
		b.add_theme_stylebox_override("pressed", _subnav_box(T.CODEX_SUBNAV_ACTIVE))
		b.add_theme_stylebox_override("hover", _subnav_box(T.CODEX_SUBNAV_ACTIVE))
		b.add_theme_stylebox_override("focus", T.box(Color.TRANSPARENT, T.CODEX_SUBNAV_RADIUS, 2, T.ACCENT_DEFAULT))
		var col: Color = T.TEXT if on else T.TEXT_SECONDARY
		if st.get("badge", "") == "pending" and pending_n > 0 and not on:
			col = T.CODEX_WARNING
		for state in ["font_color", "font_pressed_color", "font_hover_color", "font_focus_color"]:
			b.add_theme_color_override(state, col)


# ==========================================================================
# Entradas
# ==========================================================================
func _refresh_entries() -> void:
	var cats: VBoxContainer = pages["entradas"].get_meta("categories")
	_clear(cats)
	category_buttons.clear()
	var all_items: Array = [{"id": "", "label": "Todo"}]
	all_items.append_array(service.categories)
	for c in all_items:
		var cid: String = c["id"]
		var b := Button.new()
		b.name = "Cat_" + (cid if cid != "" else "todo")
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.toggle_mode = true
		b.set_pressed_no_signal(cid == current_category)
		# Solo descubrimientos propios: nunca el total del mundo.
		b.text = "%s   %d" % [c["label"], service.count_discovered(cid)]
		b.add_theme_stylebox_override("normal", T.box(T.CODEX_SUBNAV_ACTIVE if cid == current_category else Color.TRANSPARENT, 8))
		b.add_theme_stylebox_override("pressed", T.box(T.CODEX_SUBNAV_ACTIVE, 8))
		b.add_theme_color_override("font_color", T.TEXT if cid == current_category else T.TEXT_SECONDARY)
		b.pressed.connect(func() -> void: select_category(cid))
		cats.add_child(b)
		category_buttons[cid] = b
	var sc: Dictionary = service.get_status_counts()
	(status_chips["secrets"] as Label).text = "Mis secretos %d" % sc["secrets"]
	(status_chips["published"] as Label).text = "Publicados %d" % sc["published"]
	(status_chips["pioneer"] as Label).text = "Soy pionero %d" % sc["pioneer"]
	(status_chips["seen"] as Label).text = "Vistos de lejos %d" % sc["seen"]

	var cat_label: String = "Todo" if current_category == "" else service.category_label(current_category)
	entries_header.text = "%s · %d descubiertos" % [cat_label, service.count_discovered(current_category)]
	_clear(entries_grid)

	var shown: Array = service.list_entries(current_category, current_query)
	var still_listed := false
	for view in shown:
		if view["id"] == selected_entry_id:
			still_listed = true
			break
	if not still_listed:
		selected_entry_id = shown[0]["id"] if not shown.is_empty() else ""
	for view in shown:
		entries_grid.add_child(_entry_card(view))
	_show_detail(selected_entry_id)


func _entry_card(view: Dictionary) -> Button:
	var card := Button.new()
	card.name = "Entry_" + str(view["id"])
	card.custom_minimum_size = Vector2(0, 74)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.focus_mode = Control.FOCUS_ALL
	var selected: bool = view["id"] == selected_entry_id
	var sb := _card_box(T.CODEX_CARD_BG, T.ACCENT_DEFAULT if selected else Color.TRANSPARENT)
	card.add_theme_stylebox_override("normal", sb)
	card.add_theme_stylebox_override("hover", _card_box(T.CODEX_SUBNAV_ACTIVE))
	card.add_theme_stylebox_override("pressed", sb)
	card.set_meta("entry_id", view["id"])
	card.set_meta("display_name", view["name"])
	card.tooltip_text = "%s — %s" % [view["name"], badge_key(view)]
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 10)
	v.add_theme_constant_override("separation", 3)
	card.add_child(v)
	v.add_child(_badge(badge_key(view)))
	var n := _label(view["name"], 14, T.TEXT if view["visibility"] >= service.KNOWN_SECRET else T.CODEX_SEEN, "semibold")
	n.name = "Name"
	n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(n)
	var sub := _label(str(view["subtitle"]), 11, T.TEXT_MUTED)
	sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(sub)
	var id: String = view["id"]
	card.pressed.connect(func() -> void: show_entry(id))
	return card


## Clave de insignia para una vista de entrada.
static func badge_key(view: Dictionary) -> String:
	if view.get("pending", false):
		return "pending"
	if view.get("is_pioneer", false):
		return "pioneer"
	return str(view.get("visibility_key", "unknown"))


func show_entry(entry_id: String) -> void:
	selected_entry_id = entry_id
	if current_subtab == "entradas":
		_refresh_entries()
	else:
		_show_detail(entry_id)


func _show_detail(entry_id: String) -> void:
	if detail_box == null:
		return
	_clear(detail_box)
	if entry_id == "":
		detail_box.add_child(_label("Aún no has descubierto nada en esta categoría.", 13, T.TEXT_MUTED))
		return
	var view: Dictionary = service.get_entry_view(entry_id)
	detail_box.add_child(_badge(badge_key(view)))
	var title := _label(view["name"], 18, T.TEXT, "bold")
	title.name = "DetailName"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_box.add_child(title)
	detail_box.add_child(_label(service.category_label(str(view["category"])) if view["category"] != service.MASK else service.MASK, 12, T.TEXT_MUTED))
	var v: int = view["visibility"]
	if v == service.SEEN:
		_detail_text("Visto de lejos: %s" % view["hint"], T.TEXT_SECONDARY)
		_detail_text("Encuéntralo de cerca para descubrir su nombre y sus detalles.", T.TEXT_MUTED)
		return
	if str(view["description"]) != "":
		_detail_text(view["description"], T.TEXT_SECONDARY)
	var loc: Dictionary = view["location"]
	if not loc.is_empty() and v == service.KNOWN_SECRET:
		_detail_text("Dónde aparece: %s" % loc.get("zone", "—"), T.TEXT)
	if v == service.PUBLISHED:
		var who := "Tú eres el pionero" if view["is_pioneer"] else "Pionero: %s" % view["pioneer_name"]
		_detail_text("%s · publicado el %s" % [who, service.format_date(view["published_at"])], T.CODEX_PIONEER if view["is_pioneer"] else T.TEXT_SECONDARY)
		var wiki := _action_button("Ver en la wiki", T.CODEX_PUBLISHED, false)
		wiki.name = "WikiButton"
		wiki.tooltip_text = view["wiki_url"]
		wiki.pressed.connect(func() -> void: open_wiki(entry_id))
		detail_box.add_child(wiki)
	elif view["pending"]:
		var decide := _action_button("Decidir: ¿secreto o wiki?", T.CODEX_WARNING, true)
		decide.name = "DecideButton"
		decide.pressed.connect(func() -> void: open_decision(entry_id))
		detail_box.add_child(decide)
	elif v == service.KNOWN_SECRET:
		if not view["exclusive"]:
			_detail_text("Ya no es exclusivo: otro jugador también lo conoce.", T.CODEX_ALERT)
		var mk := _action_button("Crear Mapa del Hallazgo", T.CODEX_SECRET, true)
		mk.name = "MapButton"
		mk.pressed.connect(func() -> void: create_map_for(entry_id))
		detail_box.add_child(mk)
		var pub := _action_button("Publicar en la wiki", T.CODEX_PUBLISHED, false)
		pub.name = "PublishButton"
		pub.pressed.connect(func() -> void: open_decision(entry_id))
		detail_box.add_child(pub)


func _detail_text(text: String, color: Color) -> void:
	var l := _label(text, 13, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_box.add_child(l)


## Nombres que se ven ahora mismo en la rejilla (QA del enmascaramiento).
func get_visible_entry_names() -> Dictionary:
	var out := {}
	for c in entries_grid.get_children():
		if c.is_queued_for_deletion():
			continue
		out[c.get_meta("entry_id")] = c.get_meta("display_name")
	return out


# ==========================================================================
# Por decidir / Mis secretos / Publicados
# ==========================================================================
func _refresh_pending() -> void:
	_clear(pending_list)
	var items: Array = service.get_pending()
	if items.is_empty():
		pending_list.add_child(_label("No tienes descubrimientos por decidir.", 13, T.TEXT_MUTED))
	for view in items:
		var id: String = view["id"]
		var row := _row_card("Pending_" + id, view, "Descubierto el %s" % service.format_date(view["discovered_at"]))
		var b := _action_button("Decidir", T.CODEX_WARNING, true)
		b.name = "DecideButton"
		b.pressed.connect(func() -> void: open_decision(id))
		row.get_meta("actions").add_child(b)
		pending_list.add_child(row)


func _refresh_secrets() -> void:
	_clear(secrets_list)
	var items: Array = service.get_secrets()
	if items.is_empty():
		secrets_list.add_child(_label("No guardas ningún secreto todavía.", 13, T.TEXT_MUTED))
	for view in items:
		var id: String = view["id"]
		var loc: Dictionary = view["location"]
		var sub := "%s · %s" % [service.category_label(view["category"]), loc.get("zone", "ubicación desconocida")]
		if not view["exclusive"]:
			sub += " · ya no es exclusivo"
		var row := _row_card("Secret_" + id, view, sub)
		var mk := _action_button("Crear Mapa del Hallazgo", T.CODEX_SECRET, true)
		mk.name = "MapButton"
		mk.disabled = loc.is_empty()
		mk.pressed.connect(func() -> void: create_map_for(id))
		row.get_meta("actions").add_child(mk)
		var pub := _action_button("Publicar", T.CODEX_PUBLISHED, false)
		pub.name = "PublishButton"
		pub.pressed.connect(func() -> void: open_decision(id))
		row.get_meta("actions").add_child(pub)
		secrets_list.add_child(row)


func _refresh_published() -> void:
	_clear(published_list)
	var items: Array = service.get_published()
	if items.is_empty():
		published_list.add_child(_label("Aún no has publicado nada en la wiki.", 13, T.TEXT_MUTED))
	for view in items:
		var id: String = view["id"]
		var who := "Pionero: tú" if view["is_pioneer"] else "Pionero: %s" % view["pioneer_name"]
		var sync := "sincronizado con la wiki" if view["wiki_synced"] else "pendiente de sincronizar"
		var row := _row_card("Published_" + id, view, "%s · %s · %s" % [who, service.format_date(view["published_at"]), sync])
		var wiki := _action_button("Ver en la wiki", T.CODEX_PUBLISHED, false)
		wiki.name = "WikiButton"
		wiki.tooltip_text = view["wiki_url"]
		wiki.pressed.connect(func() -> void: open_wiki(id))
		row.get_meta("actions").add_child(wiki)
		published_list.add_child(row)


func _row_card(node_name: String, view: Dictionary, subtitle: String) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = node_name
	card.add_theme_stylebox_override("panel", _card_box(T.CODEX_CARD_BG))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	card.add_child(h)
	var badge := _badge(badge_key(view))
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(badge)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	var n := _label(view["name"], 14, T.TEXT, "semibold")
	n.name = "Name"
	v.add_child(n)
	v.add_child(_label(subtitle, 11, T.TEXT_MUTED))
	var actions := HBoxContainer.new()
	actions.name = "Actions"
	actions.add_theme_constant_override("separation", 6)
	h.add_child(actions)
	card.set_meta("actions", actions)
	return card


# ==========================================================================
# Decisión (modal lado a lado)
# ==========================================================================
func open_decision(entry_id: String) -> bool:
	if not service.is_known(entry_id) or service.get_visibility(entry_id) == service.PUBLISHED:
		return false
	decision_entry_id = entry_id
	_fill_decision(entry_id)
	decision_modal.visible = true
	decision_keep_button.grab_focus.call_deferred()
	return true


func _fill_decision(entry_id: String) -> void:
	var view: Dictionary = service.get_entry_view(entry_id)
	decision_title.text = "%s · %s" % [view["name"], view["subtitle"]] if str(view["subtitle"]) != "" else str(view["name"])
	var bonus: int = view["publish_bonus"]
	decision_reward_label.text = "+%s oro · título «%s»" % [fmt_int(bonus), view["pioneer_title"]]
	decision_publish_button.text = "Publicar · +%s" % fmt_int(bonus)
	decision_keep_button.text = "Guardar el secreto" if view["pending"] else "Seguir guardándolo"
	decision_map_button.disabled = (view["location"] as Dictionary).is_empty()


func close_decision() -> void:
	decision_modal.visible = false
	decision_entry_id = ""


## Aplica la decisión del modal. publish=false guarda el secreto; true publica.
func confirm_decision(publish: bool) -> Dictionary:
	var id := decision_entry_id
	if id == "":
		return {"ok": false, "reason": "no_entry"}
	var name_before: String = service.display_name(id)
	var res: Dictionary = service.decide_entry(id, publish)
	close_decision()
	if res.get("ok", false):
		if publish:
			_set_status("«%s» publicado en la wiki. Eres su pionero: +%s oro y título «%s»." % [name_before, fmt_int(res["gold"]), res["title"]])
			_toast("PUBLICADO EN LA WIKI", "«%s» · +%s oro" % [name_before, fmt_int(res["gold"])], T.CODEX_PUBLISHED)
		else:
			_set_status("Guardas el secreto de «%s». Puedes crear Mapas del hallazgo para venderlos." % name_before)
	else:
		_set_status("No se pudo aplicar la decisión (%s)." % res.get("reason", "?"))
	refresh()
	decision_made.emit(id, res)
	return res


# ==========================================================================
# Acciones
# ==========================================================================
func create_map_for(entry_id: String) -> Dictionary:
	var res: Dictionary = service.generate_discovery_map(entry_id)
	if res.get("ok", false):
		var item: Dictionary = res["item"]
		_set_status("%s creado: coordenadas %s en %s. Ya puedes venderlo en el Mercado." % [item["display_name"], str(item["coords"]), item["zone"]])
		discovery_map_created.emit(item)
	else:
		var reasons := {
			"already_published": "ya es público en la wiki",
			"not_a_known_secret": "no es un secreto que conozcas",
			"no_location": "no tiene una ubicación registrada",
		}
		_set_status("No se puede crear el mapa: %s." % reasons.get(res.get("reason", ""), "error"))
	refresh()
	return res


func collect_investments() -> Dictionary:
	var res: Dictionary = service.collect_to_shelter()
	if res.get("ok", false):
		_set_status("Enviados %s oro al almacén del refugio." % fmt_int(res["amount"]))
		payout_collected.emit(int(res["amount"]))
	else:
		_set_status("No hay ganancias por cobrar.")
	refresh()
	return res


func open_wiki(entry_id: String) -> void:
	var url: String = service.wiki_url(entry_id)
	if DisplayServer.get_name() != "headless":
		OS.shell_open(url)
	_set_status("Wiki: %s" % url)


# ==========================================================================
# Inversiones
# ==========================================================================
func _refresh_investments() -> void:
	var s: Dictionary = service.get_investment_summary()
	(kpi_labels["today"] as Label).text = "+" + fmt_int(s["today"])
	var arrow := "▲" if s["change_pct"] >= 0.0 else "▼"
	(kpi_labels["today_sub"] as Label).text = "%s %d %% vs. ayer" % [arrow, roundi(absf(s["change_pct"]))]
	(kpi_labels["week"] as Label).text = "+" + fmt_int(s["week"])
	(kpi_labels["week_sub"] as Label).text = "%d puestos activos" % s["active_count"]
	(kpi_labels["value"] as Label).text = fmt_int(s["portfolio_value"])
	(kpi_labels["value_sub"] as Label).text = "precio de mercado"
	(kpi_labels["published"] as Label).text = str(s["published_count"])
	(kpi_labels["published_sub"] as Label).text = "entradas en la wiki"
	earnings_chart.set_values(s["history"])
	payout_label.text = "%s oro" % fmt_int(s["pending_payout"])
	collect_button.disabled = int(s["pending_payout"]) <= 0

	_clear(investments_table)
	for inv in service.investments:
		investments_table.add_child(_investment_row(inv))
	_clear(offers_box)
	if service.offers.is_empty():
		offers_box.add_child(_label("Sin ofertas pendientes.", 12, T.TEXT_MUTED))
	for o in service.offers:
		var l := _label("%s · %s · misión: %d pasos · expira en %d días" % [o.get("name", "?"), _pct(float(o.get("share", 0.0))), int(o.get("mission_steps", 1)), int(o["expires_in_days"])], 12, T.TEXT_SECONDARY)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		offers_box.add_child(l)
	_clear(notices_box)
	if service.notices.is_empty():
		notices_box.add_child(_label("Sin avisos.", 12, T.TEXT_MUTED))
	for n in service.notices.slice(0, 3):
		var t := _label(str(n.get("title", "")), 12, T.CODEX_ALERT, "semibold")
		notices_box.add_child(t)
		var b := _label(str(n.get("body", "")), 11, T.TEXT_SECONDARY)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		notices_box.add_child(b)
	var ms: Dictionary = service.map_sales
	map_sales_label.text = "%d publicados · %d vendidos · +%s oro" % [ms.get("listed", 0), ms.get("sold", 0), fmt_int(int(ms.get("gold", 0)))]


func _investment_row(inv: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = "Inv_" + str(inv["id"])
	card.add_theme_stylebox_override("panel", _card_box(T.CODEX_CARD_BG))
	var h := HBoxContainer.new()
	card.add_child(h)
	var nv := VBoxContainer.new()
	nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nv.add_child(_label(str(inv.get("name", "")), 13, T.TEXT, "semibold"))
	nv.add_child(_label(str(inv.get("zone", "")), 11, T.TEXT_MUTED))
	h.add_child(nv)
	var earning: bool = service.is_investment_earning(inv)
	var share := _label(_pct(float(inv["share"])) if float(inv["share"]) > 0.0 else "—", 13, T.TEXT)
	share.custom_minimum_size.x = 70
	h.add_child(share)
	var bar := ProgressBar.new()
	bar.name = "Traffic"
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(110, 8)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.max_value = 1.0
	bar.value = float(inv.get("traffic", 0.0))
	bar.tooltip_text = "Tráfico %d %%" % roundi(bar.value * 100.0)
	bar.add_theme_stylebox_override("background", T.box(T.WELL, 4))
	bar.add_theme_stylebox_override("fill", T.box(T.ACCENT_DEFAULT, 4))
	var bar_wrap := CenterContainer.new()
	bar_wrap.custom_minimum_size.x = 120
	bar_wrap.add_child(bar)
	h.add_child(bar_wrap)
	var today: int = int((inv["history"] as Array)[-1])
	var today_l := _label("+" + fmt_int(today) if earning and today > 0 else "—", 13, T.GOLD_TEXT if earning else T.TEXT_MUTED, "semibold")
	today_l.name = "Today"
	today_l.custom_minimum_size.x = 70
	h.add_child(today_l)
	var st: String = inv.get("status", "active")
	var st_info: Array = STATUS_LABELS.get(st, [st, T.TEXT_SECONDARY])
	var st_text: String = st_info[0]
	if st == "mission":
		st_text = "Misión %d/%d" % [int(inv.get("mission_step", 0)), int(inv.get("mission_steps", 1))]
	var st_l := _label(st_text, 12, st_info[1], "semibold")
	st_l.custom_minimum_size.x = 150
	h.add_child(st_l)
	return card


# ==========================================================================
# Compatibilidad con el Códice v1 (InventoryItem: Hojas de descubrimiento)
# ==========================================================================
func is_secret_acquired(secret_id: String) -> bool:
	return service != null and service.is_known(secret_id)


func unlock_secret_from_sheet(secret_id: String, secret_name: String) -> void:
	if service == null:
		_resolve_service()
	service.learn_entry(secret_id, "objetos", {"name": secret_name} if secret_name != "" else {})
	selected_entry_id = secret_id
	select_subtab("entradas")
	_set_status("Conocimiento asimilado: «%s» añadido a tu Códice." % service.display_name(secret_id, secret_name))


# ==========================================================================
# Helpers
# ==========================================================================
func _set_status(msg: String) -> void:
	if status_label:
		status_label.text = msg


func _toast(title: String, body: String, color: Color) -> void:
	var orch := get_node_or_null("/root/UIOrchestrator")
	if orch and orch.has_method("show_toast"):
		orch.show_toast(title, body, color)


static func fmt_int(n: int) -> String:
	var neg := n < 0
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "." + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if neg else "") + s + out


static func _pct(share: float) -> String:
	var p := share * 100.0
	if is_equal_approx(p, roundf(p)):
		return "%d %%" % roundi(p)
	return ("%.1f %%" % p).replace(".", ",")


func _clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


func _label(text: String, font_size: int, color: Color, weight: String = "medium") -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", T.font(weight))
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


func _badge(key: String) -> PanelContainer:
	var info: Dictionary = T.CODEX_BADGES.get(key, T.CODEX_BADGES["unknown"])
	var p := PanelContainer.new()
	p.name = "Badge"
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var sb := T.box(info["bg"], T.CODEX_BADGE_RADIUS)
	sb.content_margin_left = 7
	sb.content_margin_right = 7
	p.add_theme_stylebox_override("panel", sb)
	var l := _label(info["text"], 11, Color(info["color"]), "bold")
	l.name = "Text"
	p.add_child(l)
	p.set_meta("badge_key", key)
	return p


func _chip(text: String, color: Color) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := T.box(T.CODEX_SEEN_BG, 12)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	p.add_theme_stylebox_override("panel", sb)
	var l := _label(text, 12, color)
	p.add_child(l)
	p.set_meta("label", l)
	return p


func _action_button(text: String, accent: Color, primary: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size.y = 32
	b.add_theme_font_override("font", T.font("semibold"))
	b.add_theme_font_size_override("font_size", 13)
	var bg := Color(accent, 0.22) if primary else T.BUTTON_BG
	var normal := T.box(bg, 8, 1, Color(accent, 0.55))
	normal.content_margin_left = 12
	normal.content_margin_right = 12
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(accent, 0.32)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("focus", T.box(Color.TRANSPARENT, 8, 2, accent))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(state, accent if primary else T.TEXT)
	return b


func _card_box(bg: Color, border: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var sb := T.box(bg, T.CODEX_CARD_RADIUS, 1, border if border.a > 0.0 else T.CODEX_CARD_BORDER)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb


func _subnav_box(bg: Color) -> StyleBoxFlat:
	var sb := T.box(bg, T.CODEX_SUBNAV_RADIUS)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	return sb


func _panel_box() -> StyleBoxFlat:
	return T.box(T.PANEL_BG, 14, 1, T.PANEL_EDGE)


# ==========================================================================
# Gráfico de ganancias (serie única, 14 barras, oro por día)
# ==========================================================================
class EarningsChart extends Control:
	const TK = preload("res://ui/tokens/hud_tokens.gd")
	const GAP := 2.0          # separación entre barras
	const RADIUS := 4         # extremo redondeado (anclado a la base)
	const LABEL_SPACE := 16.0

	var values: Array = []

	func _init() -> void:
		tooltip_text = "Ganancias diarias"  # activa _get_tooltip por barra
		mouse_filter = Control.MOUSE_FILTER_PASS

	func set_values(v: Array) -> void:
		values = v.duplicate()
		queue_redraw()

	func get_max() -> int:
		var m := 0
		for x in values:
			m = maxi(m, int(x))
		return m

	func bar_rect(i: int) -> Rect2:
		var n := values.size()
		if n == 0:
			return Rect2()
		var plot_h := size.y - LABEL_SPACE
		var w := (size.x - GAP * (n - 1)) / n
		var m := maxf(1.0, float(get_max()))
		var h := maxf(2.0, plot_h * float(values[i]) / m) if int(values[i]) > 0 else 0.0
		return Rect2(i * (w + GAP), LABEL_SPACE + plot_h - h, w, h)

	func _draw() -> void:
		var n := values.size()
		if n == 0:
			return
		draw_line(Vector2(0, size.y - 0.5), Vector2(size.x, size.y - 0.5), TK.CODEX_CHART_BASELINE, 1.0)
		for i in n:
			var r := bar_rect(i)
			if r.size.y <= 0.0:
				continue
			var sb := StyleBoxFlat.new()
			sb.bg_color = TK.CODEX_CHART_BAR if i == n - 1 else TK.CODEX_CHART_BAR_DIM
			sb.corner_radius_top_left = RADIUS
			sb.corner_radius_top_right = RADIUS
			sb.anti_aliasing = true
			draw_style_box(sb, r)
		# Etiqueta directa solo del último valor (hoy).
		var last := bar_rect(n - 1)
		var f := TK.font("bold")
		var txt := "+" + _thousands(int(values[n - 1]))
		var tw := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		draw_string(f, Vector2(minf(last.position.x + last.size.x - tw, size.x - tw), last.position.y - 4), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, TK.TEXT)

	static func _thousands(v: int) -> String:
		var s := str(absi(v))
		var out := ""
		while s.length() > 3:
			out = "." + s.substr(s.length() - 3) + out
			s = s.substr(0, s.length() - 3)
		return ("-" if v < 0 else "") + s + out

	func _get_tooltip(at: Vector2) -> String:
		for i in values.size():
			var r := bar_rect(i)
			if at.x >= r.position.x and at.x <= r.end.x:
				var days_ago := values.size() - 1 - i
				var when := "Hoy" if days_ago == 0 else ("Ayer" if days_ago == 1 else "Hace %d días" % days_ago)
				return "%s: +%s oro" % [when, _thousands(int(values[i]))]
		return ""
