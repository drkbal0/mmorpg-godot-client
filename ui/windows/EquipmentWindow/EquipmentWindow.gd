extends "res://ui/windows/common/MenuWindow.gd"
## Equipo e inventario [C] — UI v2.4 Paso 10 (design_ref/pantallas_html/MMO-Equipo.html).
##
## Columna 1 · Personaje: nombre, clase, nivel y Nivel de objeto (#46e3c1); conjuntos
##   F1 Daño · F2 Tanque · F3 Recolección · «+»; paperdoll de 13 ranuras con borde por
##   rareza a ambos lados del visor del personaje (arrastrar para girar, rueda para acercar).
## Columna 2 · Las 16 estadísticas canónicas (Anexo A) con `stat_row.tscn`. Al pasar el
##   ratón sobre un objeto de la mochila o una ranura se muestran los deltas
##   «▲ +N» verde (#4fe39a) / «▼ -N» rojo (#ff4d4d). Los ceros se atenúan a #7c8992.
## Columna 3 · Mochila: cuadrícula con arrastrar y soltar (vía InventoryController),
##   filtros Todo/Armas/Armaduras/Consumibles/Materiales, búsqueda en vivo (Ctrl+F),
##   bolsa segura (no se pierde al morir en zona peligrosa) y pie con Oro y Prismas.
##
## Registrada como "inventory" [C]. El estado vive en `EquipmentService`.

const EquipmentServiceScript = preload("res://shared-core/EquipmentService.gd")
const StatRowScene = preload("res://ui/components/base/stat_row.tscn")
const StatChip = preload("res://ui/components/base/stat_chip.gd")
const CurrencyLabel = preload("res://ui/components/base/currency_label.gd")
const VectorIcon = preload("res://ui/components/base/vector_icon.gd")
const SvgPath = preload("res://ui/icons/svg_path.gd")

signal item_hovered(item_id: String, source: String)
signal comparison_changed(comparison: Dictionary)
signal set_applied(set_id: String, result: Dictionary)

const MENU_TAB_ID := "equipo"
const ACCENT := Color("#46e3c1")
const DELTA_UP_COLOR := Color("#4fe39a")
const DELTA_DOWN_COLOR := Color("#ff4d4d")
const ZERO_COLOR := Color("#7c8992")
const GRID_COLUMNS := 8
const SLOT_SIZE := 48.0
const DOLL_SLOT_SIZE := 46.0
const SUMMARY_STATS: Array[String] = ["dano", "armadura", "celeridad", "critico"]

const CATEGORY_ICONS := {
	"consumable": "M9 3h6M10 3v5l-4 7a4 4 0 0 0 3.5 6h5A4 4 0 0 0 18 15l-4-7V3",
	"material": "M12 3l7 6-7 12-7-12zM5 9h14",
	"quest": "M6 3h10l3 3v15H6zM9 9h7M9 13h7M9 17h4",
}
const LOCK_ICON := "M7 11V8a5 5 0 0 1 10 0v3M5 11h14v10H5zM12 15v2"
const SEARCH_ICON := "M11 4a7 7 0 1 0 0 14a7 7 0 1 0 0-14M16 16l5 5"

## Servicio inyectable (tests). Si es null se usa /root/EquipmentService o uno local.
var service: Node = null
## Controlador inyectable (tests). Si es null se usa /root/InventoryController.
var controller: Node = null

var filter_id: String = "all"
var search_query: String = ""
## Objeto en comparación ("" = ninguno) y de dónde viene ("backpack"/"secure"/"slot").
var preview_item_id: String = ""
var preview_source: String = ""
var preview_slot: String = ""
var comparison: Dictionary = {}
var feedback_text: String = ""

# Columna 1
var name_label: Label
var subtitle_label: Label
var ilvl_label: Label
var set_buttons: Dictionary = {}       # set_id -> Button
var sets_row: HBoxContainer
var add_set_button: Button
var save_set_button: Button
var feedback_label: Label
var doll_slots: Dictionary = {}        # slot -> ItemSlot
var avatar: AvatarView
var summary_chips: Dictionary = {}     # stat -> StatChip
# Columna 2
var stat_rows: Dictionary = {}         # stat -> StatRow
var compare_title: Label
var compare_sub: Label
var compare_icon: ItemSlot
var compare_ilvl: Label
# Columna 3
var count_label: Label
var search_edit: LineEdit
var results_label: Label
var filter_buttons: Dictionary = {}    # filter_id -> Button
var grid: GridContainer
var grid_cells: Array = []             # ItemSlot
var secure_cells: Array = []           # ItemSlot
var gold_label: Node
var prisms_label: Node
var sort_button: Button

var _built := false
var _refresh_queued := false
var _clear_queued := false


# ==========================================================================
# Controles propios
# ==========================================================================
## Casilla de objeto (mochila, bolsa segura o ranura del paperdoll).
class ItemSlot extends Control:
	var window: Node = null
	## "backpack" · "secure" · "slot" · "preview"
	var kind := "backpack"
	var slot_id := ""
	var index := -1
	var item_id := ""
	var rarity_color := Color(0, 0, 0, 0)
	var bg_color := T.SLOT_EMPTY
	var hovered := false
	var is_new := false
	var locked := false
	var icon: VectorIcon
	var qty_label: Label

	func _init() -> void:
		custom_minimum_size = Vector2(48, 48)
		mouse_filter = Control.MOUSE_FILTER_STOP
		focus_mode = Control.FOCUS_ALL
		icon = VectorIcon.new()
		icon.name = "Icon"
		icon.icon_size = 26
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(icon)
		qty_label = Label.new()
		qty_label.name = "Qty"
		qty_label.add_theme_font_override("font", T.font("bold"))
		qty_label.add_theme_font_size_override("font_size", 12)
		qty_label.add_theme_color_override("font_color", T.TEXT)
		qty_label.add_theme_constant_override("outline_size", 3)
		qty_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		qty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		qty_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		qty_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		qty_label.offset_right = -5
		qty_label.offset_bottom = 0
		qty_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(qty_label)
		mouse_entered.connect(func() -> void:
			hovered = true
			queue_redraw()
			if window:
				window._on_cell_hover(self))
		mouse_exited.connect(func() -> void:
			hovered = false
			queue_redraw()
			if window:
				window._on_cell_unhover(self))

	func set_icon(d: String, color: Color, size_px: int = 26) -> void:
		icon.icon_size = size_px
		icon.custom_layers = [{"d": d, "stroke": color, "width": 2.0}] if d != "" else []
		if d == "":
			icon.icon_kind = VectorIcon.KIND_CUSTOM
		icon.queue_redraw()

	func get_border_color() -> Color:
		if item_id != "":
			return rarity_color
		if locked:
			return Color(T.ACCENT_DEFAULT, 0.35)
		return T.SLOT_EMPTY_BORDER

	func _draw() -> void:
		var sb := StyleBoxFlat.new()
		sb.bg_color = bg_color
		sb.set_corner_radius_all(12 if size.x >= 44 else 10)
		var border := get_border_color()
		sb.border_color = T.ACCENT_DEFAULT if hovered else border
		sb.set_border_width_all(2 if (item_id != "" or hovered) else 1)
		draw_style_box(sb, Rect2(Vector2.ZERO, size))
		if is_new and item_id != "":
			draw_circle(Vector2(size.x - 8, 8), 3.5, T.ACCENT_DEFAULT)

	func _gui_input(event: InputEvent) -> void:
		if window == null or item_id == "":
			return
		if event is InputEventMouseButton and event.pressed:
			var mb := event as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_RIGHT or (mb.button_index == MOUSE_BUTTON_LEFT and mb.double_click):
				window._on_cell_activated(self)
				accept_event()

	func _get_drag_data(_at: Vector2) -> Variant:
		if window == null or item_id == "" or kind == "preview":
			return null
		# Solo durante un arrastre real del viewport (los tests llaman a _get_drag_data directamente).
		if get_viewport() and get_viewport().gui_is_dragging():
			var preview := ItemSlotPreview.new()
			preview.source = self
			preview.size = size
			set_drag_preview(preview)
		return {"type": "equipment_item", "item_id": item_id, "source": kind, "slot": slot_id, "index": index}

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		return window != null and kind != "preview" and window.can_drop(self, data)

	func _drop_data(_at: Vector2, data: Variant) -> void:
		if window:
			window.drop(self, data)


## Vista previa del arrastre (copia la casilla de origen).
class ItemSlotPreview extends Control:
	var source: Control

	func _draw() -> void:
		if not is_instance_valid(source):
			return
		var sb := StyleBoxFlat.new()
		sb.bg_color = source.bg_color
		sb.set_corner_radius_all(12)
		sb.border_color = source.get_border_color()
		sb.set_border_width_all(2)
		draw_style_box(sb, Rect2(Vector2.ZERO, size))
		var layers: Array = source.icon.get_layers()
		var side := 26.0
		SvgPath.draw_layers(self, layers, Rect2((size - Vector2(side, side)) * 0.5, Vector2(side, side)))


## Visor del personaje: silueta que gira al arrastrar y se acerca con la rueda.
class AvatarView extends Control:
	signal rotated(yaw: float)

	var yaw := 0.0
	var zoom := 1.0
	var accent := Color("#46e3c1")
	var _dragging := false
	var hint: Label

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		custom_minimum_size = Vector2(150, 300)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		size_flags_vertical = Control.SIZE_EXPAND_FILL
		hint = Label.new()
		hint.name = "Hint"
		hint.text = "Arrastra para girar · rueda para acercar"
		hint.add_theme_font_override("font", T.font("medium"))
		hint.add_theme_font_size_override("font_size", 11)
		hint.add_theme_color_override("font_color", T.TEXT_MUTED)
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		hint.offset_top = -30
		hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(hint)

	func rotate_by(delta_yaw: float) -> void:
		yaw = wrapf(yaw + delta_yaw, -PI, PI)
		rotated.emit(yaw)
		queue_redraw()

	func set_zoom(z: float) -> void:
		zoom = clampf(z, 0.8, 1.3)
		queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_LEFT:
				_dragging = mb.pressed
			elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				set_zoom(zoom + 0.05)
			elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				set_zoom(zoom - 0.05)
		elif event is InputEventMouseMotion and _dragging:
			rotate_by((event as InputEventMouseMotion).relative.x * 0.012)

	func _draw() -> void:
		var c := Vector2(size.x * 0.5, (size.y - 30.0) * 0.5 + 6.0)
		var h := minf(size.y - 60.0, 300.0) * zoom
		# Halo y suelo.
		draw_circle(c, h * 0.42, Color(accent, 0.05))
		draw_circle(c, h * 0.30, Color(accent, 0.05))
		var floor_pts := PackedVector2Array()
		for i in 32:
			var a := TAU * i / 32.0
			floor_pts.append(c + Vector2(cos(a) * h * 0.26, h * 0.5 + sin(a) * h * 0.045))
		draw_colored_polygon(floor_pts, Color(0, 0, 0, 0.45))
		# Silueta (se estrecha al girar: falso 3D).
		var sx := 0.55 + 0.45 * absf(cos(yaw))
		var body := Color("#1f2b33")
		var edge := Color("#6d7c86")
		var top := c.y - h * 0.5
		var head_c := Vector2(c.x, top + h * 0.09)
		var pts := PackedVector2Array([
			Vector2(-0.10, 0.17), Vector2(0.10, 0.17), Vector2(0.24, 0.24), Vector2(0.27, 0.50),
			Vector2(0.20, 0.52), Vector2(0.17, 0.32), Vector2(0.14, 0.55), Vector2(0.15, 0.98),
			Vector2(0.04, 0.98), Vector2(0.0, 0.62), Vector2(-0.04, 0.98), Vector2(-0.15, 0.98),
			Vector2(-0.14, 0.55), Vector2(-0.17, 0.32), Vector2(-0.20, 0.52), Vector2(-0.27, 0.50),
			Vector2(-0.24, 0.24),
		])
		var poly := PackedVector2Array()
		for p in pts:
			poly.append(Vector2(c.x + p.x * h * sx, top + p.y * h))
		draw_colored_polygon(poly, body)
		var outline := poly.duplicate()
		outline.append(poly[0])
		draw_polyline(outline, edge, 1.5, true)
		draw_circle(head_c, h * 0.075, body)
		draw_arc(head_c, h * 0.075, 0, TAU, 32, edge, 1.5, true)
		# Línea de giro: indica hacia dónde mira el personaje.
		var fx := sin(yaw) * h * 0.06
		draw_line(Vector2(c.x + fx, top + h * 0.25), Vector2(c.x + fx, top + h * 0.5), Color(accent, 0.55), 2.0, true)


# ==========================================================================
# Ciclo de vida
# ==========================================================================
func _ready() -> void:
	window_id = "inventory"
	_resolve_service()
	_resolve_commerce()
	_build()
	super._ready()
	connect_menu_bar()
	if commerce and not commerce.wallet_changed.is_connected(_on_wallet_footer):
		commerce.wallet_changed.connect(_on_wallet_footer)
	refresh()


func initialize_window(params: Dictionary) -> void:
	if params.has("set"):
		apply_set(str(params["set"]))
	if params.has("filter"):
		set_filter(str(params["filter"]))
	if params.has("query"):
		set_search(str(params["query"]))


func _resolve_service() -> void:
	if service == null:
		service = get_node_or_null("/root/EquipmentService")
	if service == null:
		service = EquipmentServiceScript.new()
		service.name = "LocalEquipmentService"
		service.load_seed()
		add_child(service)
	elif service.get_parent() == null:
		add_child(service)
	for sig in ["backpack_changed", "stats_changed", "set_changed", "sets_updated", "equipment_changed"]:
		var cb := Callable(self, "_on_service_changed")
		if not service.is_connected(sig, cb):
			service.connect(sig, cb)
	# En vivo: los objetos con metadatos de equipo que lleguen del backend entran a la mochila.
	var ctrl := _controller()
	var auth := get_node_or_null("/root/AuthManager")
	if ctrl and ctrl.has_signal("inventory_refresh_requested") and auth and str(auth.get("auth_token")) != "":
		var cb2 := Callable(self, "_on_inventory_state")
		if not ctrl.is_connected("inventory_refresh_requested", cb2):
			ctrl.connect("inventory_refresh_requested", cb2)


func _controller() -> Node:
	if controller != null:
		return controller
	return get_node_or_null("/root/InventoryController")


func _on_inventory_state(state) -> void:
	if typeof(state) == TYPE_DICTIONARY and service:
		service.ingest_inventory_items(state.get("char_items", []))


func _on_service_changed(_a = null) -> void:
	if _refresh_queued:
		return
	_refresh_queued = true
	_deferred_refresh.call_deferred()


func _deferred_refresh() -> void:
	_refresh_queued = false
	refresh()


func _on_wallet_footer(_g: int = 0, _p: int = 0) -> void:
	_refresh_currencies()


# ==========================================================================
# Construcción
# ==========================================================================
func _build() -> void:
	if _built:
		return
	_built = true
	var col := build_frame(MENU_TAB_ID)
	var header := _hbox(0)
	header.name = "Header"
	header.custom_minimum_size.y = 0
	col.add_child(header)
	var title := _label("Equipo", 1, Color.TRANSPARENT)
	title.name = "TitleLabel"
	title.visible = false
	header.add_child(title)

	var page := _hbox(12)
	page.name = "Page"
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(page)
	page.add_child(_build_character_column())
	page.add_child(_build_stats_column())
	page.add_child(_build_backpack_column())


func _build_character_column() -> Control:
	var card := _card("CharacterCard", 14)
	card.custom_minimum_size.x = 380
	var v := _vbox(10)
	card.add_child(v)

	var head := _hbox(8)
	head.name = "CharHeader"
	v.add_child(head)
	var names := _vbox(2)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(names)
	name_label = _label("", 24, T.TEXT, "bold")
	name_label.name = "CharName"
	names.add_child(name_label)
	subtitle_label = _label("", 14, T.TEXT_SECONDARY)
	subtitle_label.name = "CharClass"
	names.add_child(subtitle_label)
	var il := _vbox(0)
	il.alignment = BoxContainer.ALIGNMENT_END
	head.add_child(il)
	var il_cap := _caps("Nivel de objeto")
	il_cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	il.add_child(il_cap)
	ilvl_label = _label("0", 30, ACCENT, "bold")
	ilvl_label.name = "ItemLevel"
	ilvl_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	il.add_child(ilvl_label)

	var sets_box := _vbox(6)
	sets_box.name = "Sets"
	v.add_child(sets_box)
	var sets_head := _hbox(6)
	sets_box.add_child(sets_head)
	var sc := _caps("Conjuntos de equipo")
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sets_head.add_child(sc)
	save_set_button = _ghost_button("Guardar", 11, 22)
	save_set_button.name = "SaveSet"
	save_set_button.tooltip_text = "Guarda lo que llevas en el conjunto activo"
	save_set_button.pressed.connect(func() -> void: save_active_set())
	sets_head.add_child(save_set_button)
	sets_row = _hbox(6)
	sets_row.name = "SetChips"
	sets_box.add_child(sets_row)
	feedback_label = _label("", 12, T.TEXT_SECONDARY)
	feedback_label.name = "Feedback"
	feedback_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	feedback_label.custom_minimum_size.x = 200
	sets_box.add_child(feedback_label)

	var doll := _hbox(6)
	doll.name = "Paperdoll"
	doll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(doll)
	var left := _vbox(6)
	left.name = "LeftSlots"
	doll.add_child(left)
	avatar = AvatarView.new()
	avatar.name = "Avatar"
	avatar.accent = ACCENT
	doll.add_child(avatar)
	var right := _vbox(6)
	right.name = "RightSlots"
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	doll.add_child(right)
	for s in EquipmentServiceScript.LEFT_SLOTS:
		left.add_child(_make_doll_slot(s))
	for s in EquipmentServiceScript.RIGHT_SLOTS:
		right.add_child(_make_doll_slot(s))

	var chips := HFlowContainer.new()
	chips.name = "Summary"
	chips.add_theme_constant_override("h_separation", 6)
	chips.add_theme_constant_override("v_separation", 6)
	v.add_child(chips)
	for k in SUMMARY_STATS:
		var chip := StatChip.new()
		chip.name = "Chip_" + k
		chip.show_abbreviation = true
		chips.add_child(chip)
		summary_chips[k] = chip
	return card


func _make_doll_slot(slot: String) -> ItemSlot:
	var c := ItemSlot.new()
	c.name = "Slot_" + slot
	c.window = self
	c.kind = "slot"
	c.slot_id = slot
	c.custom_minimum_size = Vector2(DOLL_SLOT_SIZE, DOLL_SLOT_SIZE)
	doll_slots[slot] = c
	return c


func _build_stats_column() -> Control:
	var card := _card("StatsCard", 14)
	card.custom_minimum_size.x = 352
	var v := _vbox(8)
	card.add_child(v)
	var head := _hbox(8)
	v.add_child(head)
	var t := _label("Estadísticas", 20, T.TEXT, "bold")
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	head.add_child(_caps("16 canónicas"))

	var cmp := _sub_card("Comparison", 8)
	cmp.custom_minimum_size.y = 64
	v.add_child(cmp)
	var ch := _hbox(10)
	cmp.add_child(ch)
	compare_icon = ItemSlot.new()
	compare_icon.name = "CompareIcon"
	compare_icon.kind = "preview"
	compare_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	compare_icon.custom_minimum_size = Vector2(44, 44)
	compare_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ch.add_child(compare_icon)
	var cv := _vbox(1)
	cv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cv.alignment = BoxContainer.ALIGNMENT_CENTER
	ch.add_child(cv)
	compare_title = _label("", 16, T.TEXT, "bold")
	compare_title.name = "CompareTitle"
	compare_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	compare_title.custom_minimum_size.x = 120
	cv.add_child(compare_title)
	compare_sub = _label("", 12, T.TEXT_SECONDARY)
	compare_sub.name = "CompareSub"
	compare_sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	compare_sub.custom_minimum_size.x = 120
	cv.add_child(compare_sub)
	compare_ilvl = _label("", 12, T.TEXT_SECONDARY, "semibold")
	compare_ilvl.name = "CompareItemLevel"
	cv.add_child(compare_ilvl)

	var table := _vbox(2)
	table.name = "StatTable"
	v.add_child(table)
	for i in T.STAT_KEYS.size():
		var k: String = T.STAT_KEYS[i]
		var bg := PanelContainer.new()
		bg.name = "Cell_" + k
		var sb := T.box(Color(1, 1, 1, 0.025) if i % 2 == 0 else Color(0, 0, 0, 0), 6)
		sb.content_margin_left = 8
		sb.content_margin_right = 8
		bg.add_theme_stylebox_override("panel", sb)
		table.add_child(bg)
		var row = StatRowScene.instantiate()
		row.name = "Stat_" + k
		row.custom_minimum_size = Vector2(0, 23)
		bg.add_child(row)
		row.setup(k, "0", 0.0, {"context": "hud"})
		stat_rows[k] = row
	return card


func _build_backpack_column() -> Control:
	var card := _card("BackpackCard", 14)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := _vbox(8)
	card.add_child(v)
	var head := _hbox(8)
	v.add_child(head)
	var t := _label("Inventario", 20, T.TEXT, "bold")
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	count_label = _label("0 / 0", 14, T.TEXT_SECONDARY, "semibold")
	count_label.name = "Count"
	head.add_child(count_label)

	var search := PanelContainer.new()
	search.name = "Search"
	var ssb := T.box(T.WELL, 10, 1, T.BUTTON_BORDER)
	ssb.content_margin_left = 10
	ssb.content_margin_right = 10
	search.add_theme_stylebox_override("panel", ssb)
	v.add_child(search)
	var sh := _hbox(8)
	search.add_child(sh)
	var sicon := VectorIcon.new()
	sicon.custom_layers = [{"d": SEARCH_ICON, "stroke": T.TEXT_SECONDARY, "width": 2.0}]
	sicon.icon_size = 16
	sicon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sh.add_child(sicon)
	search_edit = LineEdit.new()
	search_edit.name = "SearchEdit"
	search_edit.placeholder_text = "Buscar objetos… (Ctrl+F)"
	search_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search_edit.custom_minimum_size.y = 32
	search_edit.clear_button_enabled = true
	search_edit.add_theme_font_override("font", T.font("medium"))
	search_edit.add_theme_font_size_override("font_size", 13)
	for st in ["normal", "focus", "read_only"]:
		search_edit.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	search_edit.text_changed.connect(func(txt: String) -> void: set_search(txt))
	sh.add_child(search_edit)
	results_label = _label("", 12, ACCENT, "semibold")
	results_label.name = "Results"
	sh.add_child(results_label)

	var filters := _hbox(6)
	filters.name = "Filters"
	v.add_child(filters)
	for f in EquipmentServiceScript.FILTERS:
		var b := _chip_button(str(f["label"]), 12, 26)
		b.name = "Filter_" + str(f["id"])
		var fid: String = f["id"]
		b.pressed.connect(func() -> void: set_filter(fid))
		filters.add_child(b)
		filter_buttons[fid] = b

	grid = GridContainer.new()
	grid.name = "Grid"
	grid.columns = GRID_COLUMNS
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	v.add_child(grid)
	var cap: int = service.backpack_capacity if service else 40
	for i in cap:
		var c := ItemSlot.new()
		c.name = "Cell_%d" % i
		c.window = self
		c.kind = "backpack"
		c.index = i
		c.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
		grid.add_child(c)
		grid_cells.append(c)

	var secure_box := _sub_card("SecureBag", 8)
	var ssb2 := T.box(Color(T.ACCENT_DEFAULT, 0.05), 12, 1, Color(T.ACCENT_DEFAULT, 0.35))
	ssb2.set_content_margin_all(8)
	secure_box.add_theme_stylebox_override("panel", ssb2)
	v.add_child(secure_box)
	var sbh := _hbox(10)
	secure_box.add_child(sbh)
	var sv := _vbox(2)
	sv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sbh.add_child(sv)
	var lock_row := _hbox(6)
	sv.add_child(lock_row)
	var lock := VectorIcon.new()
	lock.custom_layers = [{"d": LOCK_ICON, "stroke": ACCENT, "width": 2.0}]
	lock.icon_size = 16
	lock_row.add_child(lock)
	lock_row.add_child(_label("Bolsa segura", 14, T.TEXT, "bold"))
	var sh2 := _wrap_label("Lo que guardes aquí no se pierde al morir en zonas peligrosas.", 11, T.TEXT_SECONDARY)
	sh2.name = "SecureHint"
	sv.add_child(sh2)
	var cells := _hbox(6)
	cells.name = "SecureCells"
	sbh.add_child(cells)
	var scap: int = service.secure_capacity if service else 3
	for i in scap:
		var c := ItemSlot.new()
		c.name = "Secure_%d" % i
		c.window = self
		c.kind = "secure"
		c.index = i
		c.locked = true
		c.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
		cells.add_child(c)
		secure_cells.append(c)

	var foot := _hbox(10)
	foot.name = "Footer"
	foot.size_flags_vertical = Control.SIZE_SHRINK_END
	v.add_child(foot)
	sort_button = _ghost_button("Ordenar  R", 12, 30)
	sort_button.name = "Sort"
	sort_button.pressed.connect(func() -> void: sort_backpack())
	foot.add_child(sort_button)
	foot.add_child(_spacer(Vector2.ZERO, true))
	gold_label = CurrencyLabel.new()
	gold_label.name = "Gold"
	foot.add_child(gold_label)
	prisms_label = CurrencyLabel.new()
	prisms_label.name = "Prisms"
	prisms_label.add_requested.connect(func(_k: String) -> void: open_other_window("shop_window", {"source": "equipment"}))
	foot.add_child(prisms_label)
	return card


func _rebuild_set_chips() -> void:
	_clear(sets_row)
	set_buttons.clear()
	for s in service.sets:
		var sid: String = s["id"]
		var label := str(s["name"]) + ("  " + str(s["key"]) if str(s["key"]) != "" else "")
		var b := _chip_button(label, 12, 28)
		b.name = "Set_" + sid
		b.tooltip_text = "Equipar «%s»%s" % [s["name"], (" [%s]" % s["key"]) if str(s["key"]) != "" else ""]
		b.pressed.connect(func() -> void: apply_set(sid))
		sets_row.add_child(b)
		set_buttons[sid] = b
	add_set_button = _chip_button("+", 13, 28)
	add_set_button.name = "AddSet"
	add_set_button.toggle_mode = false
	add_set_button.tooltip_text = "Nuevo conjunto con lo que llevas"
	add_set_button.disabled = service.sets.size() >= EquipmentServiceScript.MAX_SETS
	add_set_button.pressed.connect(func() -> void: create_set())
	sets_row.add_child(add_set_button)


# ==========================================================================
# Refresco
# ==========================================================================
func refresh() -> void:
	if not _built or service == null:
		return
	var ch: Dictionary = service.character
	name_label.text = str(ch.get("name", ""))
	subtitle_label.text = "Nivel %d · %s" % [int(ch.get("level", 1)), str(ch.get("class", ""))]
	ilvl_label.text = str(service.get_item_level())
	if set_buttons.size() != service.sets.size():
		_rebuild_set_chips()
	for sid in set_buttons:
		var on: bool = sid == service.active_set
		var b: Button = set_buttons[sid]
		b.set_pressed_no_signal(on)
		var st := T.box(Color(ACCENT, 0.14), 8, 1, ACCENT) if on else T.box(T.POWERS_CHIP_BG, 8)
		st.content_margin_left = 10
		st.content_margin_right = 10
		b.add_theme_stylebox_override("pressed", st)
		b.add_theme_stylebox_override("hover_pressed", st)
	feedback_label.text = feedback_text
	for slot in doll_slots:
		_fill_cell(doll_slots[slot], str(service.equipped.get(slot, "")), slot)
	_refresh_grid()
	_refresh_stats()
	_refresh_currencies()


func _refresh_grid() -> void:
	var shown: Array[String] = service.filter_backpack(filter_id, search_query)
	for i in grid_cells.size():
		_fill_cell(grid_cells[i], shown[i] if i < shown.size() else "")
	for i in secure_cells.size():
		_fill_cell(secure_cells[i], service.secure[i] if i < service.secure.size() else "")
	count_label.text = "%d / %d" % [service.backpack.size(), service.backpack_capacity]
	results_label.text = ("%d resultado%s" % [shown.size(), "" if shown.size() == 1 else "s"]) if search_query.strip_edges() != "" else ""
	for fid in filter_buttons:
		var b: Button = filter_buttons[fid]
		b.set_pressed_no_signal(fid == filter_id)
		var label := ""
		for f in EquipmentServiceScript.FILTERS:
			if f["id"] == fid:
				label = str(f["label"])
		b.text = "%s %d" % [label, service.count_for_filter(fid)]


func _fill_cell(c: ItemSlot, item_id: String, slot: String = "") -> void:
	c.item_id = item_id
	var it: Dictionary = service.get_item(item_id) if item_id != "" else {}
	if it.is_empty():
		c.item_id = ""
		c.rarity_color = Color(0, 0, 0, 0)
		c.bg_color = T.SLOT_EMPTY if c.kind != "slot" else Color("#121a20")
		c.is_new = false
		c.qty_label.text = ""
		if c.kind == "slot":
			c.set_icon(EquipmentServiceScript.slot_icon(slot), Color(T.TEXT_MUTED, 0.55), 22)
			c.tooltip_text = "%s · vacío" % EquipmentServiceScript.slot_name(slot)
		elif c.kind == "secure":
			c.set_icon(LOCK_ICON, Color(ACCENT, 0.35), 18)
			c.tooltip_text = "Bolsa segura · vacía"
		else:
			c.set_icon("", Color.TRANSPARENT)
			c.tooltip_text = ""
	else:
		var rc := EquipmentServiceScript.rarity_color(str(it["rarity"]))
		c.rarity_color = rc
		c.bg_color = EquipmentServiceScript.rarity_bg(str(it["rarity"]))
		c.is_new = bool(it.get("new", false))
		c.set_icon(item_icon(item_id), rc, 24 if c.kind == "slot" else 26)
		var q := int(it.get("quantity", 1))
		c.qty_label.text = str(q) if q > 1 else ""
		c.tooltip_text = _item_tooltip(item_id, slot)
	c.queue_redraw()


func item_icon(item_id: String) -> String:
	var it: Dictionary = service.get_item(item_id)
	var s := str(it.get("slot", ""))
	if s == "ring":
		return EquipmentServiceScript.slot_icon("ring_1")
	if s != "":
		return EquipmentServiceScript.slot_icon(s)
	return str(CATEGORY_ICONS.get(it.get("category", ""), CATEGORY_ICONS["material"]))


func _item_tooltip(item_id: String, slot: String = "") -> String:
	var it: Dictionary = service.get_item(item_id)
	var lines: Array[String] = [str(it["name"])]
	var meta := EquipmentServiceScript.rarity_name(str(it["rarity"]))
	if str(it["slot"]) != "":
		meta += " · %s · Nv. obj. %d" % [EquipmentServiceScript.slot_name(slot if slot != "" else service.default_slot_for(item_id)), int(it["item_level"])]
	else:
		meta += " · " + str(EquipmentServiceScript.CATEGORY_NAMES.get(it["category"], ""))
	lines.append(meta)
	for k in T.STAT_KEYS:
		if it["stats"].has(k):
			lines.append("%s %s" % [T.stat(k)["name"], _signed(k, float(it["stats"][k]))])
	if service.is_secure(item_id):
		lines.append("En la bolsa segura: no se pierde al morir")
	return "\n".join(lines)


static func _signed(key: String, v: float) -> String:
	return ("+" if v >= 0.0 else "-") + EquipmentServiceScript.format_stat(key, absf(v))


func _refresh_stats() -> void:
	var totals: Dictionary = service.get_total_stats()
	var deltas: Dictionary = comparison.get("deltas", {}) if comparison.get("ok", false) else {}
	for k in stat_rows:
		var row = stat_rows[k]
		row.set_value(EquipmentServiceScript.format_stat(k, float(totals[k])))
		var d := float(deltas.get(k, 0.0))
		if is_zero_approx(d):
			row.set_delta(0.0, "")
		else:
			row.set_delta(d, _signed(k, d))
		_style_delta(row, d)
	for k in summary_chips:
		summary_chips[k].setup(k, EquipmentServiceScript.format_stat(k, float(totals[k])), {"abbr": true})
	_refresh_compare_header()


## «▲ +N» verde #4fe39a / «▼ -N» rojo #ff4d4d; columna de delta de ancho fijo.
func _style_delta(row, d: float) -> void:
	row.delta_label.custom_minimum_size.x = 78
	row.delta_label.visible = true
	if is_zero_approx(d):
		row.delta_label.text = ""
		return
	row.delta_label.add_theme_color_override("font_color", DELTA_UP_COLOR if d > 0.0 else DELTA_DOWN_COLOR)
	row.value_label.add_theme_color_override("font_color", row.get_value_color())


func _refresh_compare_header() -> void:
	if not comparison.get("ok", false):
		_fill_cell(compare_icon, "")
		compare_icon.set_icon(SEARCH_ICON, Color(T.TEXT_MUTED, 0.6), 20)
		compare_title.text = "Comparar equipo"
		compare_title.add_theme_color_override("font_color", T.TEXT)
		compare_sub.text = "Pasa el ratón por un objeto o una ranura"
		compare_ilvl.text = ""
		return
	var iid := str(comparison.get("item_id", ""))
	var it: Dictionary = service.get_item(iid)
	_fill_cell(compare_icon, iid)
	compare_title.text = str(it.get("name", ""))
	compare_title.add_theme_color_override("font_color", EquipmentServiceScript.rarity_color(str(it.get("rarity", "common"))))
	var slot := str(comparison.get("slot", ""))
	if comparison.get("mode", "") == "unequip":
		compare_sub.text = "Si te quitas: %s (%s)" % [it.get("name", ""), EquipmentServiceScript.slot_name(slot)]
	else:
		var rep := str(comparison.get("replaced_id", ""))
		if rep != "":
			var r: Dictionary = service.get_item(rep)
			compare_sub.text = "Contra lo que llevas: %s (%d)" % [r.get("name", ""), int(r.get("item_level", 0))]
		else:
			compare_sub.text = "%s vacía · se equipa sin reemplazo" % EquipmentServiceScript.slot_name(slot)
	var a := int(floor(float(comparison.get("ilvl_before", 0.0)) + 0.0001))
	var b := int(floor(float(comparison.get("ilvl_after", 0.0)) + 0.0001))
	var glyph := "▲" if b > a else ("▼" if b < a else "=")
	compare_ilvl.text = "Nv. obj. %d → %d  %s" % [a, b, glyph]
	compare_ilvl.add_theme_color_override("font_color", DELTA_UP_COLOR if b > a else (DELTA_DOWN_COLOR if b < a else T.TEXT_SECONDARY))


func _refresh_currencies() -> void:
	if gold_label == null or commerce == null:
		return
	gold_label.setup("oro", int(commerce.gold), "hide")
	prisms_label.setup("prismas", int(commerce.prisms), "show")


# ==========================================================================
# API pública (UI, atajos y tests)
# ==========================================================================
func set_filter(fid: String) -> void:
	var valid := false
	for f in EquipmentServiceScript.FILTERS:
		valid = valid or f["id"] == fid
	filter_id = fid if valid else "all"
	if _built:
		_refresh_grid()


func set_search(q: String) -> void:
	search_query = q
	if search_edit and search_edit.text != q:
		search_edit.text = q
	if _built:
		_refresh_grid()


func focus_search() -> void:
	if search_edit:
		search_edit.grab_focus()
		search_edit.select_all()


## Ids visibles en la cuadrícula (filtro + búsqueda).
func get_visible_items() -> Array[String]:
	return service.filter_backpack(filter_id, search_query)


## Simula el hover sobre un objeto de la mochila/bolsa segura (comparación reactiva).
func preview_item(item_id: String, source: String = "backpack") -> Dictionary:
	_clear_queued = false
	preview_item_id = item_id
	preview_source = source
	preview_slot = ""
	comparison = service.compare_item(item_id) if service.is_equippable(item_id) else {}
	_refresh_stats()
	item_hovered.emit(item_id, source)
	comparison_changed.emit(comparison)
	return comparison


## Simula el hover sobre una ranura del paperdoll (deltas de quitarse la pieza).
func preview_equipped_slot(slot: String) -> Dictionary:
	_clear_queued = false
	preview_slot = slot
	preview_source = "slot"
	preview_item_id = str(service.equipped.get(slot, ""))
	comparison = service.compare_unequip(slot)
	_refresh_stats()
	item_hovered.emit(preview_item_id, "slot")
	comparison_changed.emit(comparison)
	return comparison


func clear_preview() -> void:
	preview_item_id = ""
	preview_source = ""
	preview_slot = ""
	comparison = {}
	if _built:
		_refresh_stats()
	comparison_changed.emit(comparison)


## Texto y color del delta de una stat en pantalla («▲ +40», verde).
func get_stat_row(key: String):
	return stat_rows.get(key)


func equip_item(item_id: String, slot: String = "") -> Dictionary:
	var ctrl := _controller()
	var res: Dictionary
	if ctrl and ctrl.has_method("request_equip"):
		res = ctrl.request_equip(service, item_id, slot)
	else:
		res = service.equip(item_id, slot)
	if res.get("ok", false):
		feedback_text = "Equipado: %s" % service.get_item(item_id).get("name", "")
	_after_move()
	return res


func unequip_slot(slot: String, index: int = -1) -> bool:
	var ctrl := _controller()
	var ok: bool
	if ctrl and ctrl.has_method("request_unequip"):
		ok = ctrl.request_unequip(service, slot, index)
	else:
		ok = service.unequip(slot, index)
	if not ok:
		feedback_text = "Mochila llena: no se puede quitar %s" % EquipmentServiceScript.slot_name(slot)
	_after_move()
	return ok


func move_secure(item_id: String, to_secure: bool) -> bool:
	var ctrl := _controller()
	var ok: bool
	if ctrl and ctrl.has_method("request_secure_move"):
		ok = ctrl.request_secure_move(service, item_id, to_secure)
	else:
		ok = service.move_to_secure(item_id) if to_secure else service.move_from_secure(item_id)
	_after_move()
	return ok


func _after_move() -> void:
	if preview_item_id != "":
		if preview_source == "slot":
			if str(service.equipped.get(preview_slot, "")) != "":
				preview_equipped_slot(preview_slot)
			else:
				clear_preview()
		elif service.backpack.has(preview_item_id) or service.secure.has(preview_item_id):
			preview_item(preview_item_id, preview_source)
		else:
			clear_preview()
	refresh()


func apply_set(set_id: String) -> Dictionary:
	var res: Dictionary = service.apply_set(set_id)
	if res.get("ok", false):
		var s: Dictionary = service.get_set(set_id)
		var n: int = res["equipped"].size()
		feedback_text = "Conjunto «%s» equipado · %d pieza%s" % [s.get("name", ""), n, "" if n == 1 else "s"]
		if not res["missing"].is_empty():
			feedback_text += " · faltan %d" % res["missing"].size()
	clear_preview()
	refresh()
	set_applied.emit(set_id, res)
	return res


func save_active_set() -> bool:
	var ok: bool = service.save_set(service.active_set)
	if ok:
		feedback_text = "Guardado en «%s»" % service.get_set(service.active_set).get("name", "")
	refresh()
	return ok


func create_set() -> String:
	var sid: String = service.create_set()
	feedback_text = ("Nuevo conjunto «%s»" % service.get_set(sid)["name"]) if sid != "" else "Máximo de conjuntos alcanzado"
	refresh()
	return sid


func sort_backpack() -> void:
	service.sort_backpack()
	refresh()


## F1/F2/F3 conjuntos · Ctrl+F búsqueda · R ordenar · E equipar el objeto en comparación.
func handle_key(event: InputEvent) -> bool:
	if not (event is InputEventKey) or not event.pressed or event.is_echo():
		return false
	var k := event as InputEventKey
	var code := k.keycode if k.keycode != KEY_NONE else k.physical_keycode
	if code == KEY_F and (k.ctrl_pressed or k.meta_pressed):
		focus_search()
		return true
	if k.ctrl_pressed or k.alt_pressed or k.meta_pressed:
		return false
	if search_edit and search_edit.has_focus():
		return false
	var sid: String = service.set_for_key(code)
	if sid != "":
		apply_set(sid)
		return true
	if code == KEY_R:
		sort_backpack()
		return true
	if code == KEY_E and preview_item_id != "" and preview_source != "slot":
		equip_item(preview_item_id)
		return true
	return false


func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if handle_key(event):
		get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	# Ctrl+F antes de que el LineEdit u otro control lo consuma.
	if is_visible_in_tree() and event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_F and (event as InputEventKey).ctrl_pressed:
		focus_search()
		get_viewport().set_input_as_handled()


# ==========================================================================
# Hover y arrastrar/soltar (llamados por ItemSlot)
# ==========================================================================
func _on_cell_hover(c: ItemSlot) -> void:
	if c.item_id == "":
		return
	if c.kind == "slot":
		preview_equipped_slot(c.slot_id)
	else:
		preview_item(c.item_id, c.kind)


func _on_cell_unhover(_c: ItemSlot) -> void:
	_clear_queued = true
	_deferred_clear.call_deferred()


func _deferred_clear() -> void:
	if _clear_queued:
		_clear_queued = false
		clear_preview()


## Doble clic / clic derecho: equipar desde la mochila o quitar desde la ranura.
func _on_cell_activated(c: ItemSlot) -> void:
	match c.kind:
		"slot":
			unequip_slot(c.slot_id)
		"backpack", "secure":
			if service.is_equippable(c.item_id):
				equip_item(c.item_id)


func can_drop(target: ItemSlot, data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY or str(data.get("type", "")) != "equipment_item":
		return false
	var iid := str(data.get("item_id", ""))
	var src := str(data.get("source", ""))
	match target.kind:
		"slot":
			return service.can_equip_in(iid, target.slot_id)
		"backpack":
			if src == "slot":
				return service.backpack.size() < service.backpack_capacity
			return src == "secure" or (src == "backpack" and filter_id == "all" and search_query == "")
		"secure":
			return src == "backpack" and service.secure.size() < service.secure_capacity
	return false


func drop(target: ItemSlot, data: Variant) -> void:
	if not can_drop(target, data):
		return
	var iid := str(data["item_id"])
	var src := str(data["source"])
	match target.kind:
		"slot":
			equip_item(iid, target.slot_id)
		"backpack":
			if src == "slot":
				unequip_slot(str(data["slot"]), mini(target.index, service.backpack.size()))
			elif src == "secure":
				move_secure(iid, false)
			else:
				service.move_in_backpack(iid, target.index)
				refresh()
		"secure":
			move_secure(iid, true)
