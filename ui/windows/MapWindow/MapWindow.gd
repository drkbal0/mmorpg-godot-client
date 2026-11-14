extends "res://ui/windows/common/MenuWindow.gd"
## Mapa del mundo y Viajes [M] — UI v2.4 Paso 9.
## Referencias: design_ref/pantallas_html/MMO-Mapa.html y MMO-Viajes.html.
##
## Página «Mapa»: regiones con niebla («???»), capas de marcadores, lienzo con zoom y
## paneo (`WorldMapCanvas`), ficha del marcador elegido y eventos próximos.
## Página «Viajar»: destinos (los atajos secretos solo si los conoces) y, por destino,
## las formas de llegar con tiempo, coste en oro y riesgo calculados de forma
## determinista por `WorldMapService`. No hay teletransporte.
##
## Abre con parámetros: {focus: Vector2, quest_id, title, poi} (desde Misiones) o
## {page: "viajar", destination}.

const WorldMapServiceScript = preload("res://shared-core/WorldMapService.gd")
const QuestServiceScript = preload("res://shared-core/QuestService.gd")
const CanvasScript = preload("res://ui/windows/MapWindow/WorldMapCanvas.gd")

signal page_changed(page_id: String)
signal travel_booked(result: Dictionary)

const MENU_TAB_ID := "mapa"
const PAGES: Array[Dictionary] = [
	{"id": "mapa", "label": "Mapa"},
	{"id": "viajar", "label": "Viajar"},
]
const LAYERS: Array[Dictionary] = [
	{"id": "quest", "label": "Misiones"},
	{"id": "npc", "label": "PNJ comerciantes"},
	{"id": "boss", "label": "Jefes"},
	{"id": "shelter", "label": "El Nido (Refugio)"},
	{"id": "secret", "label": "Mis secretos"},
	{"id": "post", "label": "Postas"},
	{"id": "portal", "label": "Portales"},
	{"id": "dungeon", "label": "Mazmorras"},
]
const SEGMENT_COLORS := {
	"wait": Color("#5b6770"), "safe": Color("#4fe39a"), "medium": Color("#f5c35b"), "high": Color("#ff6b6b"),
}
const RISK_COLORS := {"safe": Color("#4fe39a"), "medium": Color("#f5c35b"), "high": Color("#ff6b6b")}

var service: Node = null
## Diario de misiones (para pintar los objetivos rastreados). Opcional.
var quests: Node = null
var current_page: String = ""
var page_buttons: Dictionary = {}
var pages: Dictionary = {}

# --- Mapa ---
var canvas: Control
var breadcrumb: Label
var region_box: VBoxContainer
var layer_checks: Dictionary = {}
var info_box: VBoxContainer
var events_box: VBoxContainer
var travel_here_button: Button

# --- Viajar ---
var selected_destination: String = ""
var selected_mode: String = ""
var dest_box: VBoxContainer
var dest_rows: Dictionary = {}
var route_title: Label
var route_sub: Label
var options_box: VBoxContainer
var option_cards: Dictionary = {}
var book_button: Button
var trip_box: VBoxContainer
var travel_feedback: Label

var _built := false


func _ready() -> void:
	window_id = "map_window"
	_resolve_services()
	_resolve_commerce()
	_build()
	super._ready()
	connect_menu_bar()
	if current_page == "":
		set_page("mapa")
	refresh()


func initialize_window(params: Dictionary) -> void:
	if not _built:
		return
	var page := str(params.get("page", ""))
	if params.has("destination"):
		page = "viajar"
		select_destination(str(params["destination"]))
	if page != "":
		set_page(page)
	var focus = params.get("focus", null)
	if focus == null and str(params.get("poi", "")) != "":
		focus = service.resolve_poi(str(params["poi"]))
	if focus is Vector2:
		set_page("mapa")
		canvas.focus_on(focus, str(params.get("title", "")))
		var poi := str(params.get("poi", ""))
		if poi != "" and not service.find_marker(poi).is_empty():
			select_marker(poi)


func _resolve_services() -> void:
	if service == null:
		service = get_node_or_null("/root/WorldMapService")
	if service == null:
		service = WorldMapServiceScript.new()
		service.name = "LocalWorldMapService"
		service.load_seed()
		add_child(service)
		var ks := get_node_or_null("/root/KnowledgeService")
		if ks:
			service.connect_knowledge(ks)
	elif service.get_parent() == null:
		add_child(service)
	if quests == null:
		quests = get_node_or_null("/root/QuestService")
	if quests and not quests.tracked_changed.is_connected(_on_tracked_changed):
		quests.tracked_changed.connect(_on_tracked_changed)
	if not service.map_changed.is_connected(_on_map_changed):
		service.map_changed.connect(_on_map_changed)


func _on_tracked_changed(_ids: Array = []) -> void:
	_refresh_quest_markers()


func _on_map_changed() -> void:
	if _built:
		_refresh_regions()
		_refresh_destinations()


# ==========================================================================
# Construcción
# ==========================================================================
func _build() -> void:
	if _built:
		return
	_built = true
	var col := build_frame(MENU_TAB_ID)
	var header := _hbox(10)
	header.name = "Header"
	col.add_child(header)
	var pill := PanelContainer.new()
	pill.name = "Subnav"
	var psb := T.box(T.SHELTER_CARD_BG, 12, 1, T.CODEX_CARD_BORDER)
	psb.set_content_margin_all(4)
	pill.add_theme_stylebox_override("panel", psb)
	header.add_child(pill)
	var subnav := _hbox(2)
	pill.add_child(subnav)
	for p in PAGES:
		var b := _chip_button(p["label"], 14, 30)
		b.name = "Page_" + p["id"]
		var pid: String = p["id"]
		b.pressed.connect(func() -> void: set_page(pid))
		subnav.add_child(b)
		page_buttons[pid] = b
	var title := _label("Mapa", 1, Color.TRANSPARENT)
	title.name = "TitleLabel"
	title.visible = false
	header.add_child(title)
	breadcrumb = _label("", 13, T.TEXT_SECONDARY, "semibold")
	breadcrumb.name = "Breadcrumb"
	breadcrumb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	breadcrumb.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(breadcrumb)

	var pages_root := Control.new()
	pages_root.name = "Pages"
	pages_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(pages_root)
	pages["mapa"] = _build_map_page()
	pages["viajar"] = _build_travel_page()
	for id in pages:
		var pg: Control = pages[id]
		pg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		pg.visible = false
		pages_root.add_child(pg)


func _build_map_page() -> Control:
	var page := _hbox(12)
	page.name = "Page_mapa"
	# Izquierda: regiones + capas.
	var left := _card("RegionsCard", 14)
	left.custom_minimum_size.x = 270
	page.add_child(left)
	var lv := _vbox(8)
	left.add_child(lv)
	lv.add_child(_caps("REGIONES"))
	region_box = _vbox(2)
	region_box.name = "Regions"
	var rscroll := ScrollContainer.new()
	rscroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	region_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rscroll.add_child(region_box)
	lv.add_child(rscroll)
	lv.add_child(_caps("CAPAS"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 0)
	lv.add_child(grid)
	for l in LAYERS:
		var cb := CheckButton.new()
		cb.name = "Layer_" + l["id"]
		cb.text = l["label"]
		cb.button_pressed = true
		cb.add_theme_font_override("font", T.font("medium"))
		cb.add_theme_font_size_override("font_size", 11)
		cb.add_theme_color_override("font_color", T.TEXT_KEY)
		cb.add_theme_color_override("font_pressed_color", T.TEXT)
		cb.add_theme_color_override("font_hover_pressed_color", T.TEXT)
		cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var lid: String = l["id"]
		cb.toggled.connect(func(on: bool) -> void: set_layer(lid, on))
		grid.add_child(cb)
		layer_checks[lid] = cb

	# Centro: lienzo.
	var center := _card("CanvasCard", 0, Color("#070b0d"), T.CODEX_CARD_BORDER, 16)
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.clip_contents = true
	page.add_child(center)
	canvas = CanvasScript.new()
	canvas.name = "WorldMapCanvas"
	canvas.service = service
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas.marker_clicked.connect(select_marker)
	canvas.destination_requested.connect(_on_destination_requested)
	center.add_child(canvas)
	var hint := _label("Rueda: zoom · arrastra: mover · clic derecho: fijar destino", 11, T.TEXT_SECONDARY)
	hint.name = "CanvasHint"
	hint.position = Vector2(14, 10)
	canvas.add_child(hint)
	var legend := _hbox(10)
	legend.name = "Legend"
	legend.anchor_top = 1.0
	legend.anchor_bottom = 1.0
	legend.offset_left = 14
	legend.offset_top = -30
	legend.offset_bottom = -12
	canvas.add_child(legend)
	for k in ["quest", "npc", "boss", "shelter", "secret"]:
		legend.add_child(_dot(CanvasScript.KIND_COLORS[k], 8))
		legend.add_child(_label(CanvasScript.KIND_LABELS[k], 11, T.TEXT_KEY))

	# Derecha: selección + eventos.
	var right := _card("InfoCard", 16)
	right.custom_minimum_size.x = 280
	page.add_child(right)
	var rv := _vbox(10)
	right.add_child(rv)
	rv.add_child(_caps("SELECCIÓN"))
	info_box = _vbox(6)
	info_box.name = "MarkerInfo"
	rv.add_child(info_box)
	travel_here_button = _primary_button("Viajar aquí")
	travel_here_button.name = "TravelHere"
	travel_here_button.visible = false
	travel_here_button.pressed.connect(_on_travel_here)
	rv.add_child(travel_here_button)
	var sep := HSeparator.new()
	sep.add_theme_stylebox_override("separator", T.box(T.DIVIDER, 0))
	rv.add_child(sep)
	rv.add_child(_caps("EVENTOS PRÓXIMOS"))
	events_box = _vbox(10)
	events_box.name = "Events"
	rv.add_child(events_box)
	return page


func _build_travel_page() -> Control:
	var page := _hbox(12)
	page.name = "Page_viajar"
	var left := _card("DestCard", 16)
	left.custom_minimum_size.x = 280
	page.add_child(left)
	var lv := _vbox(8)
	left.add_child(lv)
	lv.add_child(_label("Viajar", 20, T.TEXT, "bold"))
	lv.add_child(_wrap_label("No hay teletransporte: eliges cómo llegar.", 12, T.TEXT_SECONDARY))
	lv.add_child(_caps("DESTINOS"))
	dest_box = _vbox(6)
	dest_box.name = "Destinations"
	lv.add_child(dest_box)

	var center := _card("RouteCard", 20)
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_child(center)
	var cv := _vbox(10)
	center.add_child(cv)
	var th := _hbox(10)
	cv.add_child(th)
	route_title = _label("", 20, T.TEXT, "bold")
	route_title.name = "RouteTitle"
	th.add_child(route_title)
	route_sub = _label("", 12, T.TEXT_SECONDARY)
	route_sub.size_flags_vertical = Control.SIZE_SHRINK_END
	th.add_child(route_sub)
	options_box = _vbox(10)
	options_box.name = "Options"
	options_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cv.add_child(options_box)
	travel_feedback = _label("", 12, T.TEXT_SECONDARY)
	travel_feedback.name = "TravelFeedback"
	cv.add_child(travel_feedback)
	var actions := _hbox(8)
	cv.add_child(actions)
	var invite := _ghost_button("Invitar al grupo al viaje")
	invite.name = "InviteTrip"
	invite.pressed.connect(func() -> void: travel_feedback.text = "Invitación enviada al grupo: viajaréis juntos.")
	actions.add_child(invite)
	actions.add_child(_spacer(Vector2.ZERO, true))
	book_button = _primary_button("Reservar")
	book_button.name = "BookButton"
	book_button.pressed.connect(book_selected)
	actions.add_child(book_button)

	var right := _card("DuringCard", 16)
	right.custom_minimum_size.x = 290
	page.add_child(right)
	var rv := _vbox(8)
	right.add_child(rv)
	rv.add_child(_caps("DURANTE EL VIAJE"))
	for it in [
		["Ventana de El Nido", "Gestiona tu depa mientras la caravana avanza."],
		["Charla de viaje", "Chat con los pasajeros; buen sitio para armar grupo."],
		["Eventos de ruta", "Una rueda rota o un asalto: decides si ayudas."],
		["Bajar antes", "Puedes saltar en cualquier punto del camino."],
	]:
		var c := _sub_card("During", 10)
		var v := _vbox(2)
		c.add_child(v)
		v.add_child(_label(it[0], 13, T.TEXT, "semibold"))
		v.add_child(_wrap_label(it[1], 11, T.TEXT_SECONDARY))
		rv.add_child(c)
	trip_box = _vbox(6)
	trip_box.name = "Trip"
	rv.add_child(trip_box)
	rv.add_child(_spacer(Vector2.ZERO, false, true))
	var note := _card("DisconnectNote", 10, Color(0, 0, 0, 0), Color(T.GOLD, 0.5), 10)
	note.add_child(_wrap_label("Si te desconectas en una caravana, tu personaje llega a la posta y queda en zona segura.", 11, T.TEXT_KEY))
	rv.add_child(note)
	return page


# ==========================================================================
# API
# ==========================================================================
func set_page(page_id: String) -> void:
	if not pages.has(page_id):
		return
	current_page = page_id
	for id in pages:
		(pages[id] as Control).visible = id == page_id
		(page_buttons[id] as Button).set_pressed_no_signal(id == page_id)
	if page_id == "viajar" and selected_destination == "":
		var ds: Array = service.list_destinations()
		if not ds.is_empty():
			select_destination(str(ds[0]["id"]))
	refresh()
	page_changed.emit(page_id)


func set_layer(kind: String, on: bool) -> void:
	canvas.layers[kind] = on
	if layer_checks.has(kind):
		(layer_checks[kind] as CheckButton).set_pressed_no_signal(on)
	if not on and selected_marker_kind() == kind:
		select_marker("")
	canvas.queue_redraw()


func selected_marker_kind() -> String:
	if canvas.selected_marker == "":
		return ""
	for m in canvas.visible_markers():
		if m["id"] == canvas.selected_marker:
			return str(m["kind"])
	return str(service.find_marker(canvas.selected_marker).get("kind", ""))


func select_marker(id: String) -> void:
	canvas.select_marker(id)
	_refresh_info()


func _marker_by_id(id: String) -> Dictionary:
	for m in canvas.visible_markers():
		if m["id"] == id:
			return m
	return {}


func _destination_for_marker(id: String) -> String:
	for d in service.list_destinations():
		if str(d.get("poi", "")) == id:
			return str(d["id"])
	return ""


func _on_travel_here() -> void:
	var dest := _destination_for_marker(canvas.selected_marker)
	if dest != "":
		select_destination(dest)
		set_page("viajar")


func _on_destination_requested(map_pos: Vector2) -> void:
	canvas.focus_on(map_pos, "Destino fijado", canvas.zoom)


func select_destination(dest_id: String) -> void:
	selected_destination = dest_id
	var opts: Array = service.get_travel_options(dest_id)
	selected_mode = ""
	for o in opts:
		if o["available"]:
			selected_mode = str(o["mode"])
			break
	if _built:
		travel_feedback.text = ""
		_refresh_destinations()
		_refresh_route()


func select_mode(mode_id: String) -> void:
	selected_mode = mode_id
	_refresh_route()


## Reserva el modo elegido. Cobra el oro en `CommerceService` (el oro no se compra).
func book_selected() -> Dictionary:
	var gold := int(commerce.gold) if commerce else -1
	var r: Dictionary = service.book_travel(selected_destination, selected_mode, gold)
	if r.get("ok", false):
		if commerce and int(r["cost"]) > 0:
			commerce.spend_gold(int(r["cost"]))
		travel_feedback.text = "Viaje reservado: %d min · %s oro · %s." % [int(r["time_min"]), fmt(int(r["cost"])), str(r["risk_label"]).to_lower()]
	else:
		travel_feedback.text = _reason_text(str(r.get("reason", "")))
	travel_booked.emit(r)
	_refresh_route()
	_refresh_trip()
	return r


static func _reason_text(reason: String) -> String:
	match reason:
		"not_enough_gold":
			return "No tienes oro suficiente para este viaje."
		"origin_not_safe":
			return "Solo desde una zona segura (posta, ciudad o el patio)."
		"secret_unknown":
			return "Aún no conoces este atajo."
		"already_travelling":
			return "Ya estás de viaje."
		"no_teleport", "mode_required":
			return "Elige cómo llegar: no hay teletransporte."
	return "No se puede viajar así ahora."


# ==========================================================================
# Refresco
# ==========================================================================
func refresh() -> void:
	if not _built:
		return
	var loc: Dictionary = service.get_location(service.current_location)
	var rid: String = service.region_at(canvas.center)
	var region_name := str(service.get_region(rid).get("name", "")) if rid != "" and service.is_explored(rid) else "???"
	breadcrumb.text = "%s  ›  Estás en %s" % [region_name, str(loc.get("name", service.current_location))]
	_refresh_regions()
	_refresh_quest_markers()
	_refresh_info()
	_refresh_events()
	_refresh_destinations()
	_refresh_route()
	_refresh_trip()


func _refresh_regions() -> void:
	_clear(region_box)
	for r in service.get_regions_view():
		var b := _row_button("Region_" + str(r["id"]), 44)
		b.toggle_mode = false
		var rr: Rect2 = r["rect"]
		var center_pos := rr.get_center()
		var explored: bool = r["explored"]
		b.pressed.connect(func() -> void: canvas.center_on(center_pos, 0.9))
		region_box.add_child(b)
		var h := _row_content(b, 8, 8)
		h.add_child(_dot(r["color"].lightened(0.4) if explored else Color(1, 1, 1, 0.25), 8))
		var v := _vbox(3)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(v)
		var nh := _hbox(6)
		v.add_child(nh)
		var nm := _label(str(r["display_name"]), 13, T.TEXT if explored else T.TEXT_MUTED, "semibold")
		nm.name = "RegionName"
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nm.clip_text = true
		nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		nm.tooltip_text = "%s · %s" % [r["display_name"], r["kind"]] if explored else "Zona sin explorar"
		nh.add_child(nm)
		v.add_child(_bar(float(r["explored_pct"]) / 100.0, r["color"].lightened(0.45), 3))
		var pct := _label("%d %%" % int(r["explored_pct"]), 11, T.TEXT_SECONDARY)
		pct.custom_minimum_size.x = 34
		pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		h.add_child(pct)


func _refresh_quest_markers() -> void:
	var extra: Array = []
	var pts := PackedVector2Array()
	if quests:
		for id in quests.get_tracked():
			var t: Dictionary = quests.get_map_target(str(id))
			var pos = t.get("focus", null)
			if pos == null and str(t.get("poi", "")) != "":
				pos = service.resolve_poi(str(t["poi"]))
			if pos is Vector2:
				extra.append({"id": "quest:" + str(id), "kind": "quest", "name": str(t["title"]), "subtitle": "Misión rastreada · " + str(t["zone"]), "region": service.region_at(pos), "pos": pos})
				pts.append(pos)
	canvas.extra_markers = extra
	canvas.route_points = pts
	canvas.queue_redraw()


func _refresh_info() -> void:
	_clear(info_box)
	var m := _marker_by_id(canvas.selected_marker) if canvas.selected_marker != "" else {}
	if m.is_empty():
		info_box.add_child(_wrap_label("Haz clic en un marcador del mapa para ver qué hay allí.", 12, T.TEXT_MUTED))
		travel_here_button.visible = false
		return
	var col: Color = CanvasScript.KIND_COLORS.get(m["kind"], T.TEXT)
	info_box.add_child(_badge(str(CanvasScript.KIND_LABELS.get(m["kind"], m["kind"])), col))
	var nm := _label(str(m["name"]), 18, T.TEXT, "bold")
	nm.name = "MarkerName"
	info_box.add_child(nm)
	info_box.add_child(_wrap_label(str(m.get("subtitle", "")), 12, T.TEXT_SECONDARY))
	var dest := _destination_for_marker(str(m["id"]))
	travel_here_button.visible = dest != ""


func _refresh_events() -> void:
	_clear(events_box)
	for e in service.events:
		var h := _hbox(10)
		events_box.add_child(h)
		h.add_child(_label(str(e["time"]), 13, T.TEXT, "bold"))
		var v := _vbox(2)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(v)
		v.add_child(_label(str(e["name"]), 13, Color(str(e.get("color", "#eef2f4"))), "semibold"))
		v.add_child(_label(str(e["note"]), 11, T.TEXT_SECONDARY))
		var b := _ghost_button(str(e["action"]), 11, 24)
		b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		v.add_child(b)


func _refresh_destinations() -> void:
	if dest_box == null:
		return
	_clear(dest_box)
	dest_rows.clear()
	for d in service.list_destinations():
		var b := _row_button("Dest_" + str(d["id"]), 50)
		b.button_pressed = d["id"] == selected_destination
		var did: String = d["id"]
		b.pressed.connect(func() -> void: select_destination(did))
		dest_box.add_child(b)
		var h := _row_content(b, 8, 10)
		var v := _vbox(1)
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(v)
		v.add_child(_label(str(d["name"]), 13, T.TEXT, "semibold"))
		v.add_child(_label(str(d.get("subtitle", "")), 11, T.CODEX_SECRET if d.has("secret") else T.TEXT_SECONDARY))
		dest_rows[did] = b


func _refresh_route() -> void:
	if options_box == null:
		return
	_clear(options_box)
	option_cards.clear()
	var d: Dictionary = service.get_destination(selected_destination)
	if d.is_empty():
		route_title.text = ""
		route_sub.text = ""
		book_button.disabled = true
		return
	var loc: Dictionary = service.get_location(service.current_location)
	route_title.text = "%s → %s" % [str(loc.get("name", service.current_location)), str(d["name"])]
	var km := float(d.get("distance_km", 0.0))
	route_sub.text = ("%s km" % str(snappedf(km, 0.1)).replace(".", ",")) + (" · cruza una brecha" if d.get("crosses_breach", false) else "")
	for o in service.get_travel_options(selected_destination):
		options_box.add_child(_option_card(o))
	var sel: Dictionary = service.compute_route(selected_destination, selected_mode) if selected_mode != "" else {}
	if sel.get("ok", false) and sel["available"]:
		book_button.disabled = not service.active_trip.is_empty()
		var verb := "Reservar %s" % str(sel["name"]).to_lower()
		if int(sel["departure_min"]) > 0:
			verb += " · sale en %d min" % int(sel["departure_min"])
		book_button.text = verb
	else:
		book_button.disabled = true
		book_button.text = "Elige cómo llegar"


func _option_card(o: Dictionary) -> Button:
	var b := _row_button("Mode_" + str(o["mode"]), 86)
	var sb := T.box(T.SHELTER_SUB_BG, 12, 1, T.CODEX_CARD_BORDER)
	b.add_theme_stylebox_override("normal", sb)
	b.button_pressed = o["mode"] == selected_mode
	b.disabled = not o["available"]
	var mid: String = o["mode"]
	b.pressed.connect(func() -> void: select_mode(mid))
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right"]:
		m.add_theme_constant_override("margin_" + side, 14)
	m.add_theme_constant_override("margin_top", 10)
	m.add_theme_constant_override("margin_bottom", 10)
	b.add_child(m)
	var v := _vbox(7)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(v)
	var top := _hbox(10)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(top)
	top.add_child(_label(str(o["name"]), 15, T.TEXT if o["available"] else T.TEXT_MUTED, "bold"))
	var rc: Color = RISK_COLORS.get(o["risk_level"], T.TEXT)
	var badge := _badge(str(o["risk_label"]), rc)
	badge.name = "Risk"
	top.add_child(badge)
	top.add_child(_spacer(Vector2.ZERO, true))
	var tl := _label("%d min" % int(o["time_min"]), 18, T.TEXT, "bold")
	tl.name = "Time"
	top.add_child(tl)
	var cl := _label(("%s oro" % fmt(int(o["cost"]))) if int(o["cost"]) > 0 else "gratis", 12, T.GOLD if int(o["cost"]) > 0 else T.TEXT_SECONDARY, "semibold")
	cl.name = "Cost"
	cl.custom_minimum_size.x = 64
	cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top.add_child(cl)
	var seg := SegmentBar.new()
	seg.colors = SEGMENT_COLORS
	seg.segments = o["segments"]
	seg.custom_minimum_size.y = 5
	seg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(seg)
	var desc := str(o["desc"])
	if not o["available"]:
		desc = _reason_text(str(o["reason"]))
	var dl := _label(desc, 11, T.TEXT_SECONDARY)
	dl.clip_text = true
	dl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(dl)
	option_cards[mid] = b
	return b


func _refresh_trip() -> void:
	if trip_box == null:
		return
	_clear(trip_box)
	var trip: Dictionary = service.active_trip
	if trip.is_empty():
		return
	var c := _sub_card("ActiveTrip", 10)
	trip_box.add_child(c)
	var v := _vbox(4)
	c.add_child(v)
	v.add_child(_caps("EN CAMINO", T.ACCENT_DEFAULT))
	var d: Dictionary = service.get_destination(str(trip["destination"]))
	v.add_child(_label("%s · %s" % [str(trip["name"]), str(d.get("name", ""))], 13, T.TEXT, "semibold"))
	v.add_child(_bar(service.trip_progress(), T.ACCENT_DEFAULT, 4))
