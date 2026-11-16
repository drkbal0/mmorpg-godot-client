extends "res://ui/windows/common/MenuWindow.gd"
## Colecciones — UI v2.4 Paso 12 (design_ref/pantallas_html/MMO-Colecciones.html).
## Se abre desde el Códice (pestaña Códice activa en el menú común).
##
## Izquierda: «Colecciones», categorías con contador (Monturas 23/96 · Mascotas 41/150 ·
## Apariencias 212/900 · Logros 318/1.240 · Títulos 12/80) y «Diario del multiverso» con un
## anillo de exploración por universo (Verdalia 64 % · 41 secretos…).
## Centro: cuadrícula de 6 columnas filtrable por estado (Todas · Desbloqueadas · Por
## conseguir) y rareza, con orden «más cerca de conseguir». Las por conseguir con progreso
## llevan borde cian y barra; las que no tienes salen atenuadas; «Por descubrir» oculta el nombre.
## Derecha: ficha (icono grande con brillo de rareza, nombre, rareza, lore, cómo se consigue y
## acción principal «Invocar» / «Equipar…») y «Cerca de conseguir».
##
## Todo el estado vive en `CollectionsService` (inyectable como `service`).

const CollectionsServiceScript = preload("res://shared-core/CollectionsService.gd")
const SvgPath = preload("res://ui/icons/svg_path.gd")

signal category_changed(category: String)
signal item_selected(item_id: String)
signal action_performed(item_id: String, result: Dictionary)
signal window_requested(window_id: String, params: Dictionary)

const MENU_TAB_ID := "codice"
const GRID_COLUMNS := 6
const CELL_HEIGHT := 104
const CATEGORY_GLYPHS := {
	"mounts": "M4 15c2-5 6-7 10-7l3-3 1 4 3 2-2 2h-3l-2 5M7 15l-1 5M12 15l1 5",
	"pets": "M8 5a2 2 0 1 0 0 4a2 2 0 1 0 0-4M16 5a2 2 0 1 0 0 4a2 2 0 1 0 0-4M5 11a2 2 0 1 0 0 4a2 2 0 1 0 0-4M19 11a2 2 0 1 0 0 4a2 2 0 1 0 0-4M8 18c0-3 2-5 4-5s4 2 4 5c0 2-8 2-8 0z",
	"transmogs": "M8 3l4 2 4-2 5 4-3 3-2-1v11H8V9l-2 1-3-3z",
	"achievements": "M8 3h8v5a4 4 0 0 1-8 0zM5 4h3v3a3 3 0 0 1-3-3zM19 4h-3v3a3 3 0 0 0 3-3zM12 12v5M8 21h8M9 17h6",
	"titles": "M4 6h16v12H4zM8 10h8M8 14h5",
}
const HIDDEN_GLYPH := "M9 9a3 3 0 1 1 4 2.8c-.8.4-1 1-1 1.7V15M12 18v.5"

## Servicio inyectable (tests). Si es null se usa /root/CollectionsService o uno local.
var service: Node = null
var category: String = "mounts"
var state_filter: String = "all"
var rarity_filter: String = ""
var sort_id: String = "near"
var selected_id: String = ""

var category_buttons: Dictionary = {}   # category -> Button
var category_counters: Dictionary = {}  # category -> Label
var journal_box: VBoxContainer
var journal_rows: Dictionary = {}       # universe -> {ring, name, text}

var grid_title: Label
var grid_counter: Label
var sort_button: Button
var state_buttons: Dictionary = {}      # filter id -> Button
var rarity_buttons: Dictionary = {}     # "" | rarity -> Button
var grid: GridContainer
var cells: Dictionary = {}              # item_id -> Cell
var empty_label: Label

var detail_icon: BigIcon
var detail_name: Label
var detail_rarity: Label
var detail_state: PanelContainer
var detail_desc: Label
var detail_source: Label
var detail_req: Label
var detail_bar: Bar
var detail_preview: Label
var action_button: Button
var feedback_label: Label
var near_box: VBoxContainer
var near_rows: Array = []               # [{id, panel, cta}]

var _built := false
var _refresh_queued := false


func _ready() -> void:
	window_id = "collections_window"
	_resolve_service()
	_resolve_commerce()
	_build()
	super._ready()
	connect_menu_bar()
	refresh()


func initialize_window(params: Dictionary) -> void:
	var c := str(params.get("category", ""))
	if c != "":
		set_category(c)
	var iid := str(params.get("item_id", ""))
	if iid != "" and service and service.has_item(iid):
		var it: Dictionary = service.get_item(iid)
		if it["category"] != category:
			set_category(it["category"])
		select_item(iid)


func _resolve_service() -> void:
	if service == null and is_inside_tree():
		service = get_node_or_null("/root/CollectionsService")
	if service == null:
		service = CollectionsServiceScript.new()
		service.name = "LocalCollectionsService"
		service.load_seed()
		add_child(service)
	elif service.get_parent() == null:
		add_child(service)
	for sig in ["collection_changed", "active_changed", "journal_changed", "item_unlocked", "progress_changed"]:
		var cb := Callable(self, "_on_service_changed")
		if not service.is_connected(sig, cb):
			service.connect(sig, cb)


func _on_service_changed(_a = null, _b = null, _c = null) -> void:
	if _refresh_queued or not is_inside_tree():
		return
	_refresh_queued = true
	_deferred_refresh.call_deferred()


func _deferred_refresh() -> void:
	_refresh_queued = false
	refresh()


# ==========================================================================
# Controles dibujados
# ==========================================================================
## Anillo de exploración (Diario del multiverso).
class Ring extends Control:
	var ratio := 0.0:
		set(v):
			ratio = clampf(v, 0.0, 1.0)
			queue_redraw()
	var color := Color("#46e3c1"):
		set(v):
			color = v
			queue_redraw()
	var track := Color("#1d272e")
	var thickness := 5.0

	func _init() -> void:
		custom_minimum_size = Vector2(44, 44)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - thickness * 0.5 - 1.0
		draw_arc(c, r, 0.0, TAU, 48, track, thickness, true)
		if ratio > 0.0:
			draw_arc(c, r, -PI * 0.5, -PI * 0.5 + TAU * ratio, maxi(4, int(48 * ratio)), color, thickness, true)


## Icono grande de la ficha con brillo de rareza.
class BigIcon extends Control:
	var border := Color("#9aa6ae"):
		set(v):
			border = v
			queue_redraw()
	var glyph := "":
		set(v):
			glyph = v
			queue_redraw()
	var dim := false:
		set(v):
			dim = v
			queue_redraw()

	func _init() -> void:
		custom_minimum_size = Vector2(76, 76)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _draw() -> void:
		if not dim:
			for i in 3:
				var g := StyleBoxFlat.new()
				g.bg_color = Color(border, 0.07 * (3 - i))
				g.set_corner_radius_all(22 + i * 3)
				var pad := 4.0 + i * 3.0
				draw_style_box(g, Rect2(Vector2(-pad, -pad), size + Vector2(pad, pad) * 2.0))
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("#121a20")
		sb.set_corner_radius_all(16)
		sb.border_color = border if not dim else Color(1, 1, 1, 0.12)
		sb.set_border_width_all(2)
		draw_style_box(sb, Rect2(Vector2.ZERO, size))
		if glyph != "":
			var side := minf(size.x, size.y) * 0.5
			var col := border if not dim else Color("#7c8992")
			SvgPath.draw_layers(self, [{"d": glyph, "stroke": col, "width": 1.8}], Rect2((size - Vector2(side, side)) * 0.5, Vector2(side, side)))


## Casilla de la cuadrícula (botón con dibujo propio).
class Cell extends Button:
	var item_id := ""
	var item_name := ""
	var glyph := ""
	var rarity_color := Color("#9aa6ae")
	var unlocked := false
	var hidden_item := false
	var in_progress := false
	var progress := 0.0
	var active := false
	var selected := false:
		set(v):
			selected = v
			queue_redraw()

	func _init() -> void:
		toggle_mode = false
		focus_mode = Control.FOCUS_ALL
		custom_minimum_size = Vector2(80, 104)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		flat = true
		clip_text = true
		var empty := StyleBoxEmpty.new()
		for s in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
			add_theme_stylebox_override(s, empty)

	## Borde según estado (HTML): tuya → blanco 12 %; por conseguir con progreso → cian 1.5 px;
	## sin progreso / por descubrir → sin borde y opacidad 0.7. Elegida → cian 2 px.
	func border_color() -> Color:
		if selected:
			return Color("#46e3c1")
		if in_progress:
			return Color("#46e3c1")
		if unlocked:
			return Color(1, 1, 1, 0.12)
		return Color(0, 0, 0, 0)

	func cell_opacity() -> float:
		return 1.0 if (unlocked or in_progress or selected) else 0.7

	func _draw() -> void:
		var a := cell_opacity()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("#121a20") if not selected else Color("#16232a")
		sb.set_corner_radius_all(12)
		var bc := border_color()
		if bc.a > 0.0:
			sb.border_color = bc
			sb.set_border_width_all(2 if selected else (2 if in_progress else 1))
		draw_style_box(sb, Rect2(Vector2.ZERO, size))
		if is_hovered() and not selected:
			var hv := StyleBoxFlat.new()
			hv.bg_color = Color(1, 1, 1, 0.03)
			hv.set_corner_radius_all(12)
			draw_style_box(hv, Rect2(Vector2.ZERO, size))
		var gcol := (rarity_color if unlocked else Color("#7c8992"))
		gcol.a *= a
		var side := 30.0
		var gr := Rect2(Vector2((size.x - side) * 0.5, size.y * 0.5 - side + 2), Vector2(side, side))
		SvgPath.draw_layers(self, [{"d": glyph, "stroke": gcol, "width": 1.8}], gr)
		var f := get_theme_default_font()
		var fs := 12
		var txt := item_name
		var maxw := size.x - 8.0
		while txt.length() > 3 and f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > maxw:
			txt = txt.substr(0, txt.length() - 2) + "…"
			if txt.ends_with("……"):
				txt = txt.substr(0, txt.length() - 1)
		var tw := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var tcol := Color("#eef2f4") if unlocked else Color("#7c8992")
		tcol.a *= a
		draw_string(f, Vector2((size.x - tw) * 0.5, size.y * 0.5 + 22), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, tcol)
		if in_progress:
			var bar_r := Rect2(10, size.y - 11, size.x - 20, 3)
			var bg := StyleBoxFlat.new()
			bg.bg_color = Color("#26333b")
			bg.set_corner_radius_all(2)
			draw_style_box(bg, bar_r)
			var fg := StyleBoxFlat.new()
			fg.bg_color = Color("#46e3c1")
			fg.set_corner_radius_all(2)
			draw_style_box(fg, Rect2(bar_r.position, Vector2(maxf(3.0, bar_r.size.x * progress), 3)))
		if active:
			var c := Vector2(size.x - 13, 13)
			draw_circle(c, 7, Color("#46e3c1"))
			draw_polyline(PackedVector2Array([c + Vector2(-3.5, 0), c + Vector2(-1, 2.5), c + Vector2(3.5, -2.5)]), Color("#06231c"), 1.6, true)


# ==========================================================================
# Construcción
# ==========================================================================
func _build() -> void:
	if _built:
		return
	_built = true
	var col := build_frame(MENU_TAB_ID)
	var page := _hbox(14)
	page.name = "Page"
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(page)
	page.add_child(_build_left_column())
	page.add_child(_build_grid_column())
	page.add_child(_build_detail_column())


func _build_left_column() -> Control:
	var card := _card("CategoriesCard", 16)
	card.custom_minimum_size.x = 250
	var v := _vbox(8)
	card.add_child(v)
	var title := _label("Colecciones", 20, T.TEXT, "bold")
	title.name = "TitleLabel"
	v.add_child(title)
	var cats := _vbox(4)
	cats.name = "Categories"
	v.add_child(cats)
	for c in service.categories:
		var cid: String = c["id"]
		var b := _row_button("Cat_" + cid, 34)
		var h := _row_content(b, 6, 12)
		var nl := _label(str(c["name"]), 14, T.TEXT)
		nl.name = "Name"
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(nl)
		var cl := _label("", 12, T.TEXT_MUTED)
		cl.name = "Counter"
		cl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(cl)
		b.pressed.connect(set_category.bind(cid))
		cats.add_child(b)
		category_buttons[cid] = b
		category_counters[cid] = cl
	var jc := _caps("DIARIO DEL MULTIVERSO")
	jc.name = "JournalCaps"
	v.add_child(_spacer(Vector2(0, 4)))
	v.add_child(jc)
	journal_box = _vbox(10)
	journal_box.name = "Journal"
	v.add_child(journal_box)
	for u in service.universes:
		var row := _hbox(12)
		row.name = "Universe_" + str(u["id"])
		var ring := Ring.new()
		ring.name = "Ring"
		row.add_child(ring)
		var tv := _vbox(0)
		tv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(tv)
		var nl := _label(str(u["name"]), 15, T.TEXT, "semibold")
		nl.name = "Name"
		tv.add_child(nl)
		var tl := _label("", 12, T.TEXT_SECONDARY)
		tl.name = "Text"
		tv.add_child(tl)
		journal_box.add_child(row)
		journal_rows[u["id"]] = {"ring": ring, "name": nl, "text": tl, "row": row}
	return card


func _build_grid_column() -> Control:
	var card := _card("GridCard", 18)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := _vbox(12)
	card.add_child(v)
	var head := _hbox(8)
	head.name = "GridHeader"
	v.add_child(head)
	grid_title = _label("", 18, T.TEXT, "bold")
	grid_title.name = "GridTitle"
	head.add_child(grid_title)
	grid_counter = _label("", 13, T.TEXT_SECONDARY)
	grid_counter.name = "GridCounter"
	grid_counter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(grid_counter)
	head.add_child(_spacer(Vector2.ZERO, true))
	sort_button = _chip_button("", 13, 28)
	sort_button.name = "SortButton"
	sort_button.toggle_mode = false
	sort_button.pressed.connect(cycle_sort)
	head.add_child(sort_button)
	var filters := _hbox(6)
	filters.name = "Filters"
	v.add_child(filters)
	for f in CollectionsServiceScript.STATE_FILTERS:
		var b := _chip_button(str(f["label"]), 12, 26)
		b.name = "State_" + str(f["id"])
		b.pressed.connect(set_state_filter.bind(str(f["id"])))
		filters.add_child(b)
		state_buttons[f["id"]] = b
	filters.add_child(_spacer(Vector2(6, 0)))
	var all_r := _chip_button("Toda rareza", 12, 26)
	all_r.name = "Rarity_all"
	all_r.pressed.connect(set_rarity_filter.bind(""))
	filters.add_child(all_r)
	rarity_buttons[""] = all_r
	for r in CollectionsServiceScript.RARITY_ORDER:
		var rb := _chip_button("", 12, 26)
		rb.name = "Rarity_" + r
		rb.tooltip_text = CollectionsServiceScript.rarity_name(r)
		rb.custom_minimum_size.x = 26
		var cc := CenterContainer.new()
		cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cc.add_child(_dot(CollectionsServiceScript.rarity_color(r), 10))
		rb.add_child(cc)
		rb.pressed.connect(set_rarity_filter.bind(r))
		filters.add_child(rb)
		rarity_buttons[r] = rb
	var scroll := ScrollContainer.new()
	scroll.name = "GridScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var sv := _vbox(0)
	sv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(sv)
	grid = GridContainer.new()
	grid.name = "Grid"
	grid.columns = GRID_COLUMNS
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sv.add_child(grid)
	empty_label = _wrap_label("Nada que mostrar con estos filtros.", 13, T.TEXT_MUTED)
	empty_label.name = "EmptyLabel"
	empty_label.visible = false
	sv.add_child(empty_label)
	return card


func _build_detail_column() -> Control:
	var card := _card("DetailCard", 18)
	card.custom_minimum_size.x = 304
	var v := _vbox(8)
	card.add_child(v)
	var head := _hbox(14)
	v.add_child(head)
	detail_icon = BigIcon.new()
	detail_icon.name = "DetailIcon"
	head.add_child(detail_icon)
	var hv := _vbox(2)
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(hv)
	detail_name = _wrap_label("", 19, T.TEXT, "bold")
	detail_name.name = "DetailName"
	hv.add_child(detail_name)
	detail_rarity = _label("", 13, T.TEXT_SECONDARY, "semibold")
	detail_rarity.name = "DetailRarity"
	hv.add_child(detail_rarity)
	detail_state = _badge("", T.ACCENT_DEFAULT)
	detail_state.name = "DetailState"
	detail_state.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	hv.add_child(detail_state)
	detail_desc = _wrap_label("", 13, T.TEXT_KEY)
	detail_desc.name = "DetailDescription"
	v.add_child(detail_desc)
	v.add_child(_caps("CÓMO SE CONSIGUE"))
	detail_source = _wrap_label("", 13, T.TEXT)
	detail_source.name = "DetailSource"
	v.add_child(detail_source)
	detail_req = _wrap_label("", 12, T.TEXT_SECONDARY)
	detail_req.name = "DetailRequirement"
	v.add_child(detail_req)
	detail_bar = _bar(0.0, T.ACCENT_DEFAULT, 4)
	detail_bar.name = "DetailBar"
	v.add_child(detail_bar)
	detail_preview = _wrap_label("", 12, T.TEXT_SECONDARY)
	detail_preview.name = "DetailPreview"
	v.add_child(detail_preview)
	action_button = _primary_button("", 14, 38)
	action_button.name = "ActionButton"
	action_button.pressed.connect(press_action)
	v.add_child(action_button)
	feedback_label = _wrap_label("", 12, T.TEXT_SECONDARY)
	feedback_label.name = "Feedback"
	v.add_child(feedback_label)
	var sep := ColorRect.new()
	sep.color = Color(1, 1, 1, 0.06)
	sep.custom_minimum_size.y = 1
	v.add_child(sep)
	v.add_child(_caps("CERCA DE CONSEGUIR"))
	var scroll := ScrollContainer.new()
	scroll.name = "NearScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	near_box = _vbox(8)
	near_box.name = "Near"
	near_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(near_box)
	return card


# ==========================================================================
# Interacción
# ==========================================================================
func set_category(c: String) -> void:
	if service == null or not service.has_category(c):
		return
	var changed := c != category
	category = c
	if changed:
		selected_id = ""
		if feedback_label:
			feedback_label.text = ""
	if _built:
		refresh()
	if changed:
		category_changed.emit(c)


func set_state_filter(f: String) -> void:
	state_filter = f
	refresh()


func set_rarity_filter(r: String) -> void:
	rarity_filter = r
	refresh()


func cycle_sort() -> void:
	var ids: Array = CollectionsServiceScript.SORTS.map(func(s): return s["id"])
	sort_id = ids[(ids.find(sort_id) + 1) % ids.size()]
	refresh()


func set_sort(s: String) -> void:
	sort_id = s
	refresh()


func select_item(id: String) -> void:
	if service == null or not service.has_item(id):
		return
	selected_id = id
	if feedback_label:
		feedback_label.text = ""
	refresh()
	item_selected.emit(id)


## Acción principal de la ficha. Con `cta` abre la ventana indicada (mapa, misiones…).
func press_action() -> Dictionary:
	if selected_id == "":
		return {"ok": false, "reason": "no_selection"}
	var id := selected_id
	var action: String = service.action_for(id)
	var r: Dictionary = service.perform_action(id)
	if r.get("ok", false) and r.has("open_window") and str(r["open_window"]) != "":
		window_requested.emit(str(r["open_window"]), r.get("params", {}))
		open_other_window(str(r["open_window"]), r.get("params", {}))
	feedback_label.text = _feedback_text(action, r)
	feedback_label.add_theme_color_override("font_color", T.TEXT_SECONDARY if r.get("ok", false) else Color("#ff8a8a"))
	action_performed.emit(id, r)
	refresh()
	return r


## Pulsar el chip de una fila «Cerca de conseguir».
func press_near_cta(id: String) -> Dictionary:
	if service == null or not service.has_item(id):
		return {"ok": false}
	selected_id = id
	if service.get_item(id)["category"] != category:
		category = service.get_item(id)["category"]
	return press_action()


func _feedback_text(action: String, r: Dictionary) -> String:
	if not r.get("ok", false):
		match str(r.get("reason", "")):
			"locked":
				return "Todavía no lo tienes."
			"already_set":
				return "Ya te avisaremos de ese evento."
		return "No se pudo completar."
	var name_ := str(service.get_item_view(selected_id).get("name", ""))
	match action:
		"summon":
			return "%s invocada." % name_
		"dismiss":
			return "Has desmontado."
		"pet":
			return "%s te acompaña." % name_
		"unpet":
			return "Mascota guardada."
		"transmog":
			return "Apariencia equipada: %s." % name_
		"untransmog":
			return "Apariencia retirada."
		"title":
			return "Ahora te verán como «%s»." % service.display_name_with_title()
		"untitle":
			return "Sin título visible."
		"cta":
			if r.get("reminder", false):
				return "Te avisaremos cuando empiece el evento."
			return "Abriendo…"
	return ""


# ==========================================================================
# Refresco
# ==========================================================================
func refresh() -> void:
	if not _built or service == null:
		return
	_refresh_categories()
	_refresh_journal()
	_refresh_grid()
	_refresh_detail()
	_refresh_near()


func _refresh_categories() -> void:
	for cid in category_buttons:
		category_buttons[cid].set_pressed_no_signal(cid == category)
		category_counters[cid].text = service.counter_text(cid)
		category_counters[cid].add_theme_color_override("font_color", T.TEXT_SECONDARY if cid == category else T.TEXT_MUTED)


func _refresh_journal() -> void:
	for u in service.journal():
		var row: Dictionary = journal_rows.get(u["id"], {})
		if row.is_empty():
			continue
		row["ring"].ratio = u["ratio"]
		row["ring"].color = Color(u["color"])
		row["text"].text = u["text"]


func visible_items() -> Array[Dictionary]:
	return service.list_items(category, state_filter, rarity_filter, sort_id)


func _refresh_grid() -> void:
	grid_title.text = service.category_name(category)
	grid_counter.text = service.counter_long_text(category)
	var sort_label := ""
	for s in CollectionsServiceScript.SORTS:
		if s["id"] == sort_id:
			sort_label = s["label"]
	sort_button.text = "Ordenar: " + sort_label
	for f in state_buttons:
		state_buttons[f].set_pressed_no_signal(f == state_filter)
	for r in rarity_buttons:
		rarity_buttons[r].set_pressed_no_signal(r == rarity_filter)
	_clear(grid)
	cells.clear()
	var list := visible_items()
	for v in list:
		var c := Cell.new()
		c.name = "Cell_" + str(v["id"])
		c.item_id = v["id"]
		c.item_name = v["name"]
		c.hidden_item = v["hidden"]
		c.unlocked = v["unlocked"]
		c.in_progress = v["in_progress"]
		c.progress = v["progress_ratio"]
		c.active = v["active"]
		c.glyph = HIDDEN_GLYPH if v["hidden"] else str(CATEGORY_GLYPHS.get(category, CATEGORY_GLYPHS["mounts"]))
		c.rarity_color = CollectionsServiceScript.rarity_color(v["rarity"]) if not v["hidden"] else T.TEXT_MUTED
		c.tooltip_text = v["name"]
		c.custom_minimum_size.y = CELL_HEIGHT
		c.pressed.connect(select_item.bind(str(v["id"])))
		grid.add_child(c)
		cells[v["id"]] = c
	if selected_id == "" or not cells.has(selected_id):
		if selected_id == "" or service.get_item(selected_id).get("category", "") != category:
			selected_id = str(list[0]["id"]) if not list.is_empty() else ""
	for id in cells:
		cells[id].selected = id == selected_id
	empty_label.visible = list.is_empty()


func _refresh_detail() -> void:
	var v: Dictionary = service.get_item_view(selected_id) if selected_id != "" else {}
	var has := not v.is_empty()
	for n in [detail_icon, detail_name, detail_rarity, detail_state, detail_desc, detail_source, action_button]:
		n.visible = has
	if not has:
		detail_req.visible = false
		detail_bar.visible = false
		detail_preview.visible = false
		return
	var rc: Color = CollectionsServiceScript.rarity_color(v["rarity"]) if not v["hidden"] else T.TEXT_MUTED
	detail_icon.border = rc
	detail_icon.dim = not v["unlocked"]
	detail_icon.glyph = HIDDEN_GLYPH if v["hidden"] else str(CATEGORY_GLYPHS.get(v["category"], ""))
	detail_name.text = v["name"]
	var cat: Dictionary = service.get_category(v["category"])
	var slot_txt := ""
	if v["slot"] != "" and CollectionsServiceScript.TRANSMOG_SLOTS.has(v["slot"]):
		slot_txt = " · " + str(CollectionsServiceScript.TRANSMOG_SLOTS[v["slot"]])
	detail_rarity.text = "%s · %s%s" % [v["rarity_name"], str(cat.get("singular", "")).capitalize(), slot_txt]
	detail_rarity.add_theme_color_override("font_color", rc)
	var st_text := ""
	var st_col := T.ACCENT_DEFAULT
	if v["hidden"]:
		st_text = "Por descubrir"
		st_col = T.TEXT_MUTED
	elif v["unlocked"]:
		st_text = "Activa ✓" if v["active"] else "Desbloqueada"
		st_col = Color("#4fe39a")
	elif v["in_progress"]:
		st_text = "Por conseguir · %d %%" % v["progress_pct"]
	else:
		st_text = "Por conseguir"
		st_col = T.TEXT_SECONDARY
	var stl := detail_state.get_node("Text") as Label
	stl.text = st_text
	stl.add_theme_color_override("font_color", st_col)
	var ssb := T.box(Color(st_col, 0.14), 7)
	ssb.content_margin_left = 8
	ssb.content_margin_right = 8
	ssb.content_margin_top = 2
	ssb.content_margin_bottom = 2
	detail_state.add_theme_stylebox_override("panel", ssb)
	detail_desc.text = v["description"]
	detail_source.text = "%s · %s" % [v["source_label"], v["source_text"]] if not v["hidden"] else "???"
	detail_req.visible = v["requirement"] != "" and not v["unlocked"]
	detail_req.text = v["requirement"]
	detail_bar.visible = v["in_progress"]
	detail_bar.ratio = v["progress_ratio"]
	detail_preview.visible = v["category"] == "titles" and not v["hidden"]
	if detail_preview.visible:
		var keep: String = service.active_title
		service.active_title = selected_id
		detail_preview.text = "Se verá así: «%s»" % service.display_name_with_title()
		service.active_title = keep
	var action: String = v["action"]
	action_button.text = CollectionsServiceScript.action_label(action, v["cta"])
	action_button.disabled = action == "none"
	action_button.visible = true
	if action in ["dismiss", "unpet", "untransmog", "untitle", "cta"]:
		_style_ghost(action_button)
	else:
		_style_primary(action_button)


func _style_primary(b: Button) -> void:
	var normal := T.box(T.ACCENT_DEFAULT, 10)
	normal.content_margin_left = 16
	normal.content_margin_right = 16
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = T.ACCENT_DEFAULT.lightened(0.15)
	var disabled := T.box(T.BUTTON_BG, 10, 1, T.BUTTON_BORDER)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("disabled", disabled)
	for s in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(s, T.SHELTER_PILL_TEXT)
	b.add_theme_color_override("font_disabled_color", T.TEXT_MUTED)
	b.set_meta("style", "primary")


func _style_ghost(b: Button) -> void:
	var normal := T.box(T.BUTTON_BG, 10, 1, T.BUTTON_BORDER)
	normal.content_margin_left = 14
	normal.content_margin_right = 14
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = T.SLOT_READY
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	for s in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(s, T.TEXT)
	b.set_meta("style", "ghost")


func _refresh_near() -> void:
	_clear(near_box)
	near_rows.clear()
	for v in service.near_completion(4):
		var p := _sub_card("Near_" + str(v["id"]), 10)
		var pv := _vbox(5)
		p.add_child(pv)
		var top := _hbox(6)
		pv.add_child(top)
		var nl := _wrap_label(str(v["name"]), 14, T.TEXT, "semibold")
		nl.name = "Name"
		top.add_child(nl)
		var pl := _label("%d %%" % v["progress_pct"], 13, T.ACCENT_DEFAULT, "semibold")
		pl.name = "Pct"
		top.add_child(pl)
		var rl := _wrap_label(str(v["requirement"]), 12, T.TEXT_SECONDARY)
		rl.name = "Requirement"
		pv.add_child(rl)
		pv.add_child(_bar(v["progress_ratio"], T.ACCENT_DEFAULT, 4))
		var cta: Button = null
		if not (v["cta"] as Dictionary).is_empty():
			cta = _chip_button(str(v["cta"].get("label", "")), 12, 22)
			cta.name = "Cta"
			cta.toggle_mode = false
			cta.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			cta.pressed.connect(press_near_cta.bind(str(v["id"])))
			pv.add_child(cta)
		near_box.add_child(p)
		near_rows.append({"id": v["id"], "panel": p, "cta": cta})
