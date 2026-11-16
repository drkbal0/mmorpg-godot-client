extends "res://ui/windows/common/MenuWindow.gd"
## Fabricación — UI v2.4 Paso 11 (design_ref/pantallas_html/MMO-Fabricacion.html).
## Se abre desde la Forja del Refugio (pestaña Refugio activa en el menú común).
##
## Izquierda: profesiones (Herrería · Alquimia · Cocina), banner de la Forja del refugio,
## maestría con barra y lista de recetas con borde de rareza y disponibilidad
## («Puedes crear 3», «Faltan 2 materiales», «Receta: botín de raid»).
## Centro: receta activa (icono con brillo de rareza, iLvl por calidad, tiempo), barra de
## calidad probable, pista de material mejorado, materiales poseído/necesario con «Buscar en
## mercado», ranura de catalizador, cantidad (−/+ · 1 · 5 · Máx), «Comprar lo que falta»,
## «Añadir a la cola de la Forja» y «Fabricar ahora».
## Derecha: cola de la Forja con temporizadores (sigue sin conexión) y cuadrícula de
## materiales de la mochila.
##
## Todo el estado vive en `CraftingService` (inyectable como `service`).

const CraftingServiceScript = preload("res://shared-core/CraftingService.gd")
const SvgPath = preload("res://ui/icons/svg_path.gd")

signal recipe_selected(recipe_id: String)
signal market_search_requested(query: String)
signal craft_finished(result: Dictionary)
signal queued(result: Dictionary)

const MENU_TAB_ID := "refugio"
const CATALYST_ID := "catalizador_grieta"
const FORGE_COLOR := Color("#ff9a4d")
const TYPE_ICONS := {
	"Arma": "M5 19L19 5M14 5h5v5M7 15l2 2",
	"Armadura": "M12 3l7 3v6c0 4.5-3 7.5-7 9-4-1.5-7-4.5-7-9V6z",
	"Material": "M4 15l8-4 8 4-8 4zM4 11l8-4 8 4",
	"Consumible": "M9 3h6M10 3v5l-5 9a2 2 0 0 0 2 3h10a2 2 0 0 0 2-3l-5-9V3",
	"Comida": "M4 12h16a8 8 0 0 1-16 0zM8 8c0-2 2-2 2-4M14 8c0-2 2-2 2-4",
}

## Servicio inyectable (tests). Si es null se usa /root/CraftingService o uno local.
var service: Node = null
var profession: String = "blacksmithing"
var selected_id: String = ""
var qty: int = 1
var use_catalyst: bool = false
var use_upgrade: bool = false

var profession_buttons: Dictionary = {}
var forge_banner_label: Label
var mastery_name_label: Label
var mastery_value_label: Label
var mastery_bar: Bar
var recipe_list: VBoxContainer
var recipe_rows: Dictionary = {}      # recipe_id -> Button
var recipe_badges: Dictionary = {}    # recipe_id -> Label

var detail_icon: ItemIcon
var detail_name_label: Label
var detail_sub_label: Label
var quality_bar: QualityBar
var hint_label: Label
var upgrade_button: Button
var materials_caps: Label
var materials_box: VBoxContainer
var material_row_nodes: Array = []    # [{id, panel, count, source, search}]
var catalyst_panel: PanelContainer
var catalyst_label: Label
var catalyst_button: Button
var qty_label: Label
var qty_minus: Button
var qty_plus: Button
var qty_presets: Dictionary = {}      # "1" | "5" | "max" -> Button
var buy_button: Button
var queue_button: Button
var craft_button: Button
var feedback_label: Label

var queue_caps: Label
var queue_box: VBoxContainer
var queue_rows: Array = []            # [{job_id, label, time, bar}]
var output_row: HBoxContainer
var output_label: Label
var collect_button: Button
var grid: GridContainer
var grid_cells: Array = []            # [ItemIcon]

var _built := false
var _refresh_queued := false
var _timer_accum := 0.0


func _ready() -> void:
	window_id = "crafting_window"
	_resolve_service()
	_resolve_commerce()
	_build()
	super._ready()
	connect_menu_bar()
	if selected_id == "":
		_select_first()
	refresh()
	set_process(true)


func initialize_window(params: Dictionary) -> void:
	var p := str(params.get("profession", ""))
	if p != "":
		set_profession(p)
	var rid := str(params.get("recipe_id", ""))
	if rid != "" and service and not service.get_recipe(rid).is_empty():
		var r: Dictionary = service.get_recipe(rid)
		if r["profession"] != profession:
			set_profession(r["profession"])
		select_recipe(rid)


func _resolve_service() -> void:
	if service == null:
		service = get_node_or_null("/root/CraftingService")
	if service == null:
		service = CraftingServiceScript.new()
		service.name = "LocalCraftingService"
		service.load_seed()
		add_child(service)
	elif service.get_parent() == null:
		add_child(service)
	for sig in ["queue_changed", "inventory_changed", "mastery_changed", "forge_changed", "crafted"]:
		var cb := Callable(self, "_on_service_changed")
		if not service.is_connected(sig, cb):
			service.connect(sig, cb)


func _on_service_changed(_a = null, _b = null) -> void:
	if _refresh_queued:
		return
	_refresh_queued = true
	_deferred_refresh.call_deferred()


func _deferred_refresh() -> void:
	_refresh_queued = false
	refresh()


func _process(delta: float) -> void:
	if not visible or service == null:
		return
	_timer_accum += delta
	if _timer_accum >= 0.25:
		_timer_accum = 0.0
		_refresh_queue()


# ==========================================================================
# Controles dibujados
# ==========================================================================
## Ranura de objeto: fondo, borde de rareza (y brillo opcional), glifo SVG y contador.
class ItemIcon extends Control:
	var border := Color("#b8c3ca"):
		set(v):
			border = v
			queue_redraw()
	var bg := Color("#121a20"):
		set(v):
			bg = v
			queue_redraw()
	var glyph := "":
		set(v):
			glyph = v
			queue_redraw()
	var glyph_color := Color("#dcc3ff")
	var radius := 8
	var border_width := 1.5
	var glow := false
	var count_text := "":
		set(v):
			count_text = v
			queue_redraw()
	var item_id := ""

	func _init() -> void:
		custom_minimum_size = Vector2(30, 30)
		mouse_filter = Control.MOUSE_FILTER_PASS
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _draw() -> void:
		if glow:
			for i in 3:
				var g := StyleBoxFlat.new()
				g.bg_color = Color(border, 0.07 * (3 - i))
				g.set_corner_radius_all(radius + 6 + i * 3)
				var pad := 4.0 + i * 3.0
				draw_style_box(g, Rect2(Vector2(-pad, -pad), size + Vector2(pad, pad) * 2.0))
		var sb := StyleBoxFlat.new()
		sb.bg_color = bg
		sb.set_corner_radius_all(radius)
		sb.border_color = border
		sb.set_border_width_all(int(ceil(border_width)))
		draw_style_box(sb, Rect2(Vector2.ZERO, size))
		if glyph != "":
			var side := minf(size.x, size.y) * 0.5
			SvgPath.draw_layers(self, [{"d": glyph, "stroke": glyph_color, "width": 1.8}], Rect2((size - Vector2(side, side)) * 0.5, Vector2(side, side)))
		if count_text != "":
			var f := get_theme_default_font()
			var fs := 11
			var w := f.get_string_size(count_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var pos := Vector2(size.x - w - 4, size.y - 4)
			draw_string_outline(f, pos, count_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(0, 0, 0, 0.9))
			draw_string(f, pos, count_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("#eef2f4"))


## Barra de calidad probable: segmentos por calidad con su porcentaje.
class QualityBar extends Control:
	var dist := {}:
		set(v):
			dist = v
			queue_redraw()
	var order: Array = []
	var names := {}
	var colors := {}

	func _init() -> void:
		custom_minimum_size = Vector2(200, 34)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func segments() -> Array:
		var out: Array = []
		var x := 0.0
		for k in order:
			var pct := int(dist.get(k, 0))
			if pct <= 0:
				continue
			var w := size.x * pct / 100.0
			out.append({"quality": k, "pct": pct, "rect": Rect2(x, 0, w, size.y)})
			x += w
		return out

	func _draw() -> void:
		var bgsb := StyleBoxFlat.new()
		bgsb.bg_color = Color("#070a0c")
		bgsb.set_corner_radius_all(10)
		draw_style_box(bgsb, Rect2(Vector2.ZERO, size))
		var segs := segments()
		var f := get_theme_default_font()
		for i in segs.size():
			var s: Dictionary = segs[i]
			var r: Rect2 = s["rect"]
			var sb := StyleBoxFlat.new()
			sb.bg_color = colors.get(s["quality"], Color("#3a4a54"))
			sb.corner_radius_top_left = 10 if i == 0 else 0
			sb.corner_radius_bottom_left = 10 if i == 0 else 0
			sb.corner_radius_top_right = 10 if i == segs.size() - 1 else 0
			sb.corner_radius_bottom_right = 10 if i == segs.size() - 1 else 0
			draw_style_box(sb, r)
			var full := "%s %d %%" % [names.get(s["quality"], s["quality"]), s["pct"]]
			var short := "%d %%" % s["pct"]
			var fs := 13
			var txt := full if f.get_string_size(full, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 10 < r.size.x else short
			if f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 4 > r.size.x:
				continue
			var tw := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(f, Vector2(r.position.x + (r.size.x - tw) * 0.5, r.size.y * 0.5 + fs * 0.36), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("#eef2f4"))


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
	var title := _label("Fabricación", 1, Color.TRANSPARENT)
	title.name = "TitleLabel"
	title.visible = false
	header.add_child(title)
	var page := _hbox(14)
	page.name = "Page"
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(page)
	page.add_child(_build_recipes_column())
	page.add_child(_build_detail_column())
	page.add_child(_build_queue_column())


func _build_recipes_column() -> Control:
	var card := _card("RecipesCard", 14)
	card.custom_minimum_size.x = 286
	var v := _vbox(8)
	card.add_child(v)
	var profs := _hbox(6)
	profs.name = "Professions"
	v.add_child(profs)
	for pid in CraftingServiceScript.PROFESSION_IDS:
		var p: Dictionary = service.get_profession(pid)
		var b := _chip_button(str(p.get("name", pid)), 13, 28)
		b.name = "Prof_" + pid
		b.pressed.connect(set_profession.bind(pid))
		profs.add_child(b)
		profession_buttons[pid] = b
	var banner := PanelContainer.new()
	banner.name = "ForgeBanner"
	var bsb := T.box(T.SHELTER_SUB_BG, 10, 1, Color(FORGE_COLOR, 0.4))
	bsb.content_margin_left = 10
	bsb.content_margin_right = 10
	bsb.content_margin_top = 7
	bsb.content_margin_bottom = 7
	banner.add_theme_stylebox_override("panel", bsb)
	var bh := _hbox(8)
	banner.add_child(bh)
	var sq := ColorRect.new()
	sq.color = FORGE_COLOR
	sq.custom_minimum_size = Vector2(8, 8)
	sq.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bh.add_child(sq)
	forge_banner_label = _wrap_label("", 12, T.TEXT_KEY)
	forge_banner_label.name = "ForgeBannerLabel"
	bh.add_child(forge_banner_label)
	v.add_child(banner)
	var mrow := _hbox(6)
	mastery_name_label = _label("", 13, T.TEXT)
	mastery_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mrow.add_child(mastery_name_label)
	mastery_value_label = _label("", 13, T.TEXT_SECONDARY)
	mrow.add_child(mastery_value_label)
	v.add_child(mrow)
	mastery_bar = _bar(0.0, T.ACCENT_DEFAULT, 6)
	mastery_bar.bg = T.SHELTER_SUB_BG
	v.add_child(mastery_bar)
	var scroll := ScrollContainer.new()
	scroll.name = "RecipeScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	recipe_list = _vbox(2)
	recipe_list.name = "RecipeList"
	recipe_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(recipe_list)
	return card


func _build_detail_column() -> Control:
	var card := _card("DetailCard", 18)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := _vbox(9)
	card.add_child(v)
	var head := _hbox(16)
	v.add_child(head)
	detail_icon = ItemIcon.new()
	detail_icon.name = "DetailIcon"
	detail_icon.custom_minimum_size = Vector2(72, 72)
	detail_icon.radius = 16
	detail_icon.border_width = 2.0
	detail_icon.glow = true
	head.add_child(detail_icon)
	var hv := _vbox(2)
	hv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(hv)
	detail_name_label = _label("", 26, T.TEXT, "bold")
	detail_name_label.name = "DetailName"
	hv.add_child(detail_name_label)
	detail_sub_label = _label("", 14, T.TEXT_SECONDARY)
	detail_sub_label.name = "DetailSubtitle"
	hv.add_child(detail_sub_label)
	v.add_child(_caps("CALIDAD PROBABLE CON TUS MATERIALES"))
	quality_bar = QualityBar.new()
	quality_bar.name = "QualityBar"
	quality_bar.order = CraftingServiceScript.QUALITY_ORDER.duplicate()
	for q in CraftingServiceScript.QUALITY_ORDER:
		quality_bar.names[q] = CraftingServiceScript.quality_name(q)
		quality_bar.colors[q] = CraftingServiceScript.quality_color(q)
	v.add_child(quality_bar)
	var hint_row := _hbox(8)
	v.add_child(hint_row)
	hint_label = _wrap_label("", 13, T.TEXT_KEY)
	hint_label.name = "UpgradeHint"
	hint_row.add_child(hint_label)
	upgrade_button = _chip_button("Usar ★★★", 12, 26)
	upgrade_button.name = "UpgradeToggle"
	upgrade_button.toggled.connect(set_use_upgrade)
	hint_row.add_child(upgrade_button)
	materials_caps = _caps("MATERIALES")
	v.add_child(materials_caps)
	materials_box = _vbox(5)
	materials_box.name = "Materials"
	v.add_child(materials_box)
	catalyst_panel = _sub_card("CatalystSlot", 8)
	var ch := _hbox(10)
	catalyst_panel.add_child(ch)
	var cslot := ItemIcon.new()
	cslot.name = "CatalystIcon"
	cslot.border = CraftingServiceScript.rarity_color("epic")
	cslot.bg = T.WELL
	cslot.glyph = "M12 3l3 6 6 3-6 3-3 6-3-6-6-3 6-3z"
	cslot.glyph_color = Color("#dcc3ff")
	ch.add_child(cslot)
	catalyst_label = _wrap_label("", 13, T.TEXT_KEY)
	catalyst_label.name = "CatalystLabel"
	ch.add_child(catalyst_label)
	catalyst_button = _chip_button("Añadir", 12, 28)
	catalyst_button.name = "CatalystToggle"
	catalyst_button.toggled.connect(set_use_catalyst)
	ch.add_child(catalyst_button)
	v.add_child(catalyst_panel)
	v.add_child(_spacer(Vector2.ZERO, false, true))
	var actions := _hbox(8)
	actions.name = "Actions"
	v.add_child(actions)
	var stepper := PanelContainer.new()
	stepper.add_theme_stylebox_override("panel", T.box(T.SHELTER_SUB_BG, 10))
	var sh := _hbox(0)
	stepper.add_child(sh)
	qty_minus = _ghost_button("−", 18, 38)
	qty_minus.name = "QtyMinus"
	qty_minus.custom_minimum_size.x = 36
	qty_minus.pressed.connect(func() -> void: set_qty(qty - 1))
	sh.add_child(qty_minus)
	qty_label = _label("1", 18, T.TEXT, "bold")
	qty_label.name = "QtyLabel"
	qty_label.custom_minimum_size.x = 34
	qty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	qty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	qty_label.size_flags_vertical = Control.SIZE_FILL
	sh.add_child(qty_label)
	qty_plus = _ghost_button("+", 18, 38)
	qty_plus.name = "QtyPlus"
	qty_plus.custom_minimum_size.x = 36
	qty_plus.pressed.connect(func() -> void: set_qty(qty + 1))
	sh.add_child(qty_plus)
	actions.add_child(stepper)
	for key in ["1", "5", "max"]:
		var pb := _chip_button("Máx" if key == "max" else key, 13, 38)
		pb.name = "Qty_" + key
		pb.toggle_mode = false
		var k: String = key
		pb.pressed.connect(func() -> void: set_qty_preset(k))
		actions.add_child(pb)
		qty_presets[key] = pb
	buy_button = _ghost_button("Comprar lo que falta", 13, 38)
	buy_button.name = "BuyMissing"
	buy_button.pressed.connect(buy_missing)
	actions.add_child(_spacer(Vector2.ZERO, true))
	actions.add_child(buy_button)
	var actions2 := _hbox(8)
	actions2.name = "Actions2"
	v.add_child(actions2)
	feedback_label = _wrap_label("", 12, T.TEXT_SECONDARY)
	feedback_label.name = "Feedback"
	actions2.add_child(feedback_label)
	queue_button = _ghost_button("Añadir a la cola de la Forja", 13, 38)
	queue_button.name = "QueueButton"
	queue_button.pressed.connect(queue_in_forge)
	actions2.add_child(queue_button)
	craft_button = _primary_button("Fabricar ahora", 14, 38)
	craft_button.name = "CraftButton"
	craft_button.pressed.connect(craft_now)
	actions2.add_child(craft_button)
	return card


func _build_queue_column() -> Control:
	var card := _card("QueueCard", 16)
	card.custom_minimum_size.x = 300
	var v := _vbox(10)
	card.add_child(v)
	queue_caps = _caps("COLA DE LA FORJA")
	queue_caps.name = "QueueCaps"
	v.add_child(queue_caps)
	queue_box = _vbox(10)
	queue_box.name = "Queue"
	v.add_child(queue_box)
	var note := _wrap_label("La cola sigue aunque cierres esta ventana o salgas a explorar (hasta 12 h sin conexión).", 12, T.TEXT_MUTED)
	note.name = "QueueNote"
	v.add_child(note)
	output_row = _hbox(8)
	output_row.name = "ForgeOutput"
	output_label = _label("", 13, T.SHELTER_BUILD_OK, "semibold")
	output_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	output_row.add_child(output_label)
	collect_button = _ghost_button("Recoger", 12, 28)
	collect_button.name = "CollectButton"
	collect_button.pressed.connect(collect_output)
	output_row.add_child(collect_button)
	v.add_child(output_row)
	v.add_child(_caps("MATERIALES EN LA MOCHILA"))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	grid = GridContainer.new()
	grid.name = "MaterialGrid"
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(grid)
	return card


# ==========================================================================
# Estado
# ==========================================================================
func set_profession(pid: String) -> void:
	if service == null or service.get_profession(pid).is_empty():
		return
	profession = pid
	selected_id = ""
	use_catalyst = false
	use_upgrade = false
	_select_first()
	refresh()


func _select_first() -> void:
	if service == null:
		return
	var list: Array = service.list_recipes(profession)
	selected_id = str(list[0]["id"]) if not list.is_empty() else ""
	qty = 1


func select_recipe(rid: String) -> void:
	if service == null or service.get_recipe(rid).is_empty():
		return
	if selected_id != rid:
		use_catalyst = false
		use_upgrade = false
	selected_id = rid
	qty = clampi(qty, 1, max(1, service.max_craftable(rid, _upgrades())))
	refresh()
	recipe_selected.emit(rid)


func _upgrades() -> Array:
	if not use_upgrade or selected_id == "":
		return []
	var h: Dictionary = service.upgrade_hint(selected_id)
	return [h["material"]] if not h.is_empty() else []


func _catalyst() -> String:
	return CATALYST_ID if use_catalyst else ""


func set_qty(n: int) -> void:
	qty = clampi(n, 1, 99)
	refresh()


## «1», «5» o «Máx» (lo máximo que permiten los materiales, mínimo 1).
func set_qty_preset(key: String) -> void:
	if key == "max":
		set_qty(max(1, service.max_craftable(selected_id, _upgrades())))
	else:
		set_qty(int(key))


func set_use_catalyst(on: bool) -> void:
	use_catalyst = on and selected_id != "" and service.can_use_catalyst(selected_id, CATALYST_ID)
	refresh()


func set_use_upgrade(on: bool) -> void:
	use_upgrade = on and selected_id != "" and not service.upgrade_hint(selected_id).is_empty()
	refresh()


func craft_now() -> Dictionary:
	var res: Dictionary = service.craft_now(selected_id, qty, _catalyst(), _upgrades())
	if res["ok"]:
		var names: Array[String] = []
		for it in res["results"]:
			names.append(str(it["quality_name"]))
		_set_feedback("Fabricado ×%d · %s" % [qty, ", ".join(names)], T.SHELTER_BUILD_OK)
		use_catalyst = false
	else:
		_set_feedback(_reason_text(res["reason"]), Color("#ff8a8a"))
	refresh()
	craft_finished.emit(res)
	return res


func queue_in_forge() -> Dictionary:
	var res: Dictionary = service.queue_craft_in_shelter(selected_id, qty, _catalyst(), _upgrades())
	if res["ok"]:
		_set_feedback("Añadido a la Forja: %s ×%d" % [service.get_recipe(selected_id)["name"], qty], T.SHELTER_BUILD_OK)
		use_catalyst = false
	else:
		_set_feedback(_reason_text(res["reason"]), Color("#ff8a8a"))
	refresh()
	queued.emit(res)
	return res


func buy_missing() -> Dictionary:
	var res: Dictionary = service.buy_missing(selected_id, qty, commerce, _upgrades())
	if res["ok"]:
		_set_feedback("Comprado lo que faltaba por %s oro" % fmt(int(res["cost"])), T.GOLD)
	else:
		_set_feedback(_reason_text(res["reason"]), Color("#ff8a8a"))
	refresh()
	return res


## «Buscar en mercado»: abre el Mercado filtrado por el material.
func search_market(material_id: String) -> void:
	var q: String = service.material_name(material_id)
	market_search_requested.emit(q)
	open_other_window("marketplace_window", {"query": q, "material_id": material_id})


func collect_output() -> void:
	var got: Array = service.collect_forge_output()
	_set_feedback("Recogido de la Forja: %d" % got.size(), T.SHELTER_BUILD_OK)
	refresh()


func cancel_job(job_id: String) -> void:
	service.cancel_job(job_id)
	refresh()


func _set_feedback(t: String, c: Color) -> void:
	if feedback_label:
		feedback_label.text = t
		feedback_label.add_theme_color_override("font_color", c)


static func _reason_text(reason: String) -> String:
	match reason:
		"not_at_workbench": return "Necesitas un banco de trabajo. Usa la cola de la Forja del refugio."
		"missing_materials": return "Te faltan materiales."
		"missing_catalyst": return "No te quedan catalizadores."
		"catalyst_not_applicable": return "Esta receta no admite catalizador."
		"queue_full": return "La cola de la Forja está llena. Mejora la Forja para más huecos."
		"recipe_locked": return "Receta bloqueada: se consigue como botín de raid."
		"mastery_too_low": return "Tu maestría es demasiado baja."
		"not_enough_gold": return "No tienes oro suficiente."
		"nothing_missing": return "No falta nada."
		"no_wallet": return "Mercado no disponible."
	return reason


# ==========================================================================
# Refresco
# ==========================================================================
func refresh() -> void:
	if not _built or service == null:
		return
	for pid in profession_buttons:
		profession_buttons[pid].set_pressed_no_signal(pid == profession)
	forge_banner_label.text = service.forge_banner()
	var p: Dictionary = service.get_profession(profession)
	mastery_name_label.text = str(p.get("mastery_name", ""))
	mastery_value_label.text = "%d / %d" % [int(p.get("mastery", 0)), int(p.get("mastery_max", 1))]
	mastery_bar.ratio = float(p.get("ratio", 0.0))
	_refresh_recipes()
	_refresh_detail()
	_refresh_queue()
	_refresh_grid()


func _refresh_recipes() -> void:
	_clear(recipe_list)
	recipe_rows.clear()
	recipe_badges.clear()
	for r in service.list_recipes(profession):
		var rid: String = r["id"]
		var b := _row_button("Recipe_" + rid, 46)
		b.button_pressed = rid == selected_id
		b.pressed.connect(select_recipe.bind(rid))
		var h := _row_content(b, 10, 10)
		var ic := ItemIcon.new()
		ic.border = CraftingServiceScript.rarity_color(r["rarity"])
		ic.glyph = TYPE_ICONS.get(r["type"], "")
		ic.glyph_color = Color(ic.border, 0.85)
		h.add_child(ic)
		var tv := _vbox(0)
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(tv)
		var nl := _label(r["name"], 14, CraftingServiceScript.rarity_color(r["rarity"]), "semibold")
		nl.name = "Name"
		tv.add_child(nl)
		var badge: Dictionary = service.recipe_badge(rid)
		var bl := _label(badge["text"], 12, badge["color"])
		bl.name = "Badge"
		tv.add_child(bl)
		recipe_list.add_child(b)
		recipe_rows[rid] = b
		recipe_badges[rid] = bl


func _refresh_detail() -> void:
	var r: Dictionary = service.get_recipe(selected_id)
	var has := not r.is_empty()
	if not has:
		detail_name_label.text = "Sin recetas"
		detail_sub_label.text = ""
		quality_bar.dist = {}
		_clear(materials_box)
		material_row_nodes.clear()
		for b in [craft_button, queue_button, buy_button]:
			b.disabled = true
		return
	var rc := CraftingServiceScript.rarity_color(r["rarity"])
	detail_icon.border = rc
	detail_icon.bg = CraftingServiceScript.rarity_bg(r["rarity"])
	detail_icon.glyph = TYPE_ICONS.get(r["type"], "")
	detail_icon.glyph_color = rc.lightened(0.45)
	detail_name_label.text = r["name"]
	detail_name_label.add_theme_color_override("font_color", rc.lightened(0.25))
	detail_sub_label.text = service.recipe_subtitle(selected_id)
	var ups := _upgrades()
	var cat := _catalyst()
	quality_bar.dist = service.quality_distribution(selected_id, cat, ups)
	var hint: Dictionary = service.upgrade_hint(selected_id, cat)
	hint_label.visible = not hint.is_empty()
	upgrade_button.visible = not hint.is_empty()
	if not hint.is_empty():
		hint_label.text = ("Usando %s." % service.material_name(hint["upgrade"])) if use_upgrade else str(hint["text"])
		upgrade_button.set_pressed_no_signal(use_upgrade)
	materials_caps.text = "MATERIALES PARA %d %s" % [qty, "UNIDAD" if qty == 1 else "UNIDADES"]
	_clear(materials_box)
	material_row_nodes.clear()
	for row in service.material_rows(selected_id, qty, ups):
		materials_box.add_child(_material_row(row))
	var cat_ok: bool = service.can_use_catalyst(selected_id, CATALYST_ID)
	var cat_have: int = service.have(CATALYST_ID)
	var md: Dictionary = service.modifiers.get(CATALYST_ID, {})
	catalyst_panel.visible = not md.is_empty()
	if not md.is_empty():
		if cat_ok:
			catalyst_label.text = "%s (opcional) · %s · tienes %d" % [md["name"], md["desc"], cat_have]
		else:
			catalyst_label.text = "%s · no aplica a esta receta" % md["name"]
		catalyst_button.disabled = not cat_ok or (cat_have <= 0 and not use_catalyst)
		catalyst_button.set_pressed_no_signal(use_catalyst)
		catalyst_button.text = "Quitar" if use_catalyst else "Añadir"
		var csb := T.box(T.SHELTER_SUB_BG, 12, 1, Color(CraftingServiceScript.rarity_color("epic"), 0.8 if use_catalyst else 0.0))
		csb.set_content_margin_all(8)
		catalyst_panel.add_theme_stylebox_override("panel", csb)
	qty_label.text = str(qty)
	qty_minus.disabled = qty <= 1
	var can_n: int = service.max_craftable(selected_id, ups)
	var cost: int = service.missing_cost(selected_id, qty, ups)
	buy_button.text = "Comprar lo que falta · %s" % fmt(cost) if cost > 0 else "Comprar lo que falta"
	buy_button.disabled = cost <= 0
	var valid: bool = not bool(r["locked"]) and service.meets_level(selected_id) and can_n >= qty
	craft_button.text = "Fabricar ahora ×%d" % qty
	craft_button.disabled = not valid or not service.at_workbench
	craft_button.tooltip_text = "" if service.at_workbench else "Necesitas un banco de trabajo"
	queue_button.disabled = not valid or service.queue.size() >= service.queue_slots()


func _material_row(row: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.name = "Mat_" + str(row["id"])
	var sb := T.box(T.SHELTER_SUB_BG, 10)
	sb.content_margin_left = 10
	sb.content_margin_right = 8
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	panel.add_theme_stylebox_override("panel", sb)
	var h := _hbox(10)
	panel.add_child(h)
	var ic := ItemIcon.new()
	ic.custom_minimum_size = Vector2(26, 26)
	ic.bg = T.WELL
	ic.border = CraftingServiceScript.rarity_color(row["rarity"])
	h.add_child(ic)
	var nl := _label(row["name"], 14, T.TEXT)
	nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(nl)
	var src := _label(row["source"], 12, T.TEXT_SECONDARY)
	src.name = "Source"
	h.add_child(src)
	var cnt := _label("%d / %d" % [int(row["have"]), int(row["need"])], 14, T.HEALTH if row["ok"] else Color("#ff8a8a"), "bold")
	cnt.name = "Count"
	cnt.custom_minimum_size.x = 62
	cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(cnt)
	var sbtn := _ghost_button("Buscar en mercado", 11, 26)
	sbtn.name = "Search"
	sbtn.pressed.connect(search_market.bind(str(row["id"])))
	h.add_child(sbtn)
	material_row_nodes.append({"id": row["id"], "panel": panel, "count": cnt, "source": src, "search": sbtn, "ok": row["ok"]})
	return panel


func _refresh_queue() -> void:
	if queue_box == null:
		return
	var view: Array = service.get_queue_view()
	queue_caps.text = "COLA DE LA FORJA · %d / %d" % [view.size(), service.queue_slots()]
	if queue_rows.size() == view.size() and _same_jobs(view):
		for i in view.size():
			queue_rows[i]["time"].text = view[i]["remaining_text"]
			queue_rows[i]["bar"].ratio = float(view[i]["ratio"])
	else:
		_clear(queue_box)
		queue_rows.clear()
		for j in view:
			var row := _vbox(5)
			row.name = "Job_" + str(j["job_id"])
			var top := _hbox(6)
			row.add_child(top)
			var l := _label(j["label"], 14, T.TEXT, "semibold")
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			top.add_child(l)
			var t := _label(j["remaining_text"], 13, T.TEXT_SECONDARY)
			t.name = "Time"
			top.add_child(t)
			var x := _ghost_button("×", 12, 20)
			x.name = "Cancel"
			x.tooltip_text = "Cancelar y devolver materiales"
			x.custom_minimum_size.x = 22
			x.pressed.connect(cancel_job.bind(str(j["job_id"])))
			top.add_child(x)
			var bar := _bar(float(j["ratio"]), T.ACCENT_DEFAULT, 5)
			bar.bg = T.SHELTER_SUB_BG
			row.add_child(bar)
			queue_box.add_child(row)
			queue_rows.append({"job_id": j["job_id"], "label": l, "time": t, "bar": bar})
		if view.is_empty():
			queue_box.add_child(_label("La Forja está libre.", 13, T.TEXT_MUTED))
	var out_n: int = service.forge_output.size()
	output_row.visible = out_n > 0
	output_label.text = "Listo en la Forja: %d" % out_n


func _same_jobs(view: Array) -> bool:
	for i in view.size():
		if queue_rows[i]["job_id"] != view[i]["job_id"]:
			return false
	return true


func _refresh_grid() -> void:
	_clear(grid)
	grid_cells.clear()
	for m in service.get_material_grid():
		var c := ItemIcon.new()
		c.name = "Cell_" + str(m["id"])
		c.custom_minimum_size = Vector2(40, 40)
		c.border = CraftingServiceScript.rarity_color(m["rarity"])
		c.bg = T.WELL
		c.count_text = str(m["count"])
		c.item_id = m["id"]
		c.tooltip_text = "%s ×%d" % [m["name"], int(m["count"])]
		if m["catalyst"]:
			c.glyph = "M12 3l3 6 6 3-6 3-3 6-3-6-6-3 6-3z"
			c.glyph_color = Color("#dcc3ff")
		grid.add_child(c)
		grid_cells.append(c)
