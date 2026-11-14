extends "res://ui/windows/common/MenuWindow.gd"
## Comercio › Tienda de Prismas — EN CONSTRUCCIÓN (UI v2.4 Paso 9 · §2.2 · MMO-Tienda.html).
##
## Estructura completa con la franja diagonal «EN CONSTRUCCIÓN»; el contenido sale de
## `CommerceService` (seed de datos). Reglas: solo apariencia y comodidad (los objetos
## con poder se rechazan al cargar), saldo de Prismas #7ee8ff con «+» para ver paquetes
## y el oro nunca se vende. Comprar devuelve `under_construction` mientras dure la obra.

const ConstructionBanner = preload("res://ui/components/base/under_construction_banner.gd")

signal category_selected(category_id: String)
signal prisms_plus_pressed
signal purchase_attempted(item_id: String, result: Dictionary)

const MENU_TAB_ID := "comercio"
const SUBTAB_ID := "tienda"

var category: String = "destacado"
var banner: Control
var category_buttons: Dictionary = {}
var grid: GridContainer
var grid_title: Label
var item_cards: Dictionary = {}
var prisms_label: Label
var plus_button: Button
var packs_box: VBoxContainer
var feedback_label: Label
var policy_label: Label

var _built := false


func _ready() -> void:
	window_id = "shop_window"
	_resolve_commerce()
	_build()
	super._ready()
	connect_menu_bar()
	refresh()


func initialize_window(params: Dictionary) -> void:
	if not _built:
		return
	if str(params.get("source", "")) == "prisms_plus" or str(params.get("category", "")) == "prismas":
		show_packs()
	elif params.has("category"):
		select_category(str(params["category"]))


func _build() -> void:
	if _built:
		return
	_built = true
	var col := build_frame(MENU_TAB_ID, SUBTAB_ID)
	var header := _hbox(14)
	header.name = "Header"
	col.add_child(header)
	header.add_child(_commerce_subnav(SUBTAB_ID))
	var title := _label("Tienda", 1, Color.TRANSPARENT)
	title.name = "TitleLabel"
	title.visible = false
	header.add_child(title)
	banner = ConstructionBanner.new()
	banner.name = "ConstructionBanner"
	banner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	banner.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	banner.message = str(commerce.shop_banner)
	header.add_child(banner)

	var page := _hbox(12)
	page.name = "Page"
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(page)

	var left := _card("CategoriesCard", 16)
	left.custom_minimum_size.x = 230
	page.add_child(left)
	var lv := _vbox(6)
	left.add_child(lv)
	lv.add_child(_label("Tienda", 20, T.TEXT, "bold"))
	lv.add_child(_spacer(Vector2(0, 4)))
	for c in commerce.shop_categories:
		var b := _chip_button(str(c["label"]), 13, 34)
		b.name = "Cat_" + str(c["id"])
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var cid: String = c["id"]
		b.pressed.connect(func() -> void:
			if cid == "prismas":
				show_packs()
			else:
				select_category(cid))
		lv.add_child(b)
		category_buttons[cid] = b

	var center := _card("CatalogCard", 18)
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_child(center)
	var cv := _vbox(12)
	center.add_child(cv)
	grid_title = _caps("DESTACADO DE LA SEMANA")
	grid_title.name = "GridTitle"
	cv.add_child(grid_title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	cv.add_child(scroll)
	grid = GridContainer.new()
	grid.name = "Catalog"
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(grid)
	feedback_label = _label("", 12, T.TEXT_SECONDARY)
	feedback_label.name = "Feedback"
	cv.add_child(feedback_label)

	var right := _card("WalletCard", 18)
	right.custom_minimum_size.x = 300
	page.add_child(right)
	var rv := _vbox(10)
	right.add_child(rv)
	rv.add_child(_caps("TUS PRISMAS"))
	var ph := _hbox(8)
	rv.add_child(ph)
	var gem := _dot(T.PRISMS, 14)
	ph.add_child(gem)
	prisms_label = _label("0", 30, T.PRISMS, "bold")
	prisms_label.name = "PrismsAmount"
	prisms_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ph.add_child(prisms_label)
	plus_button = _ghost_button("+", 18, 34)
	plus_button.name = "PrismsPlus"
	plus_button.tooltip_text = "Adquirir Prismas"
	plus_button.custom_minimum_size.x = 40
	plus_button.add_theme_color_override("font_color", T.PRISMS)
	plus_button.pressed.connect(show_packs)
	ph.add_child(plus_button)
	rv.add_child(_wrap_label("Moneda que se compra con dinero real. El oro se gana jugando y no se puede comprar.", 11, T.TEXT_SECONDARY))
	rv.add_child(_caps("PAQUETES DE PRISMAS"))
	packs_box = _vbox(6)
	packs_box.name = "Packs"
	rv.add_child(packs_box)
	rv.add_child(_spacer(Vector2.ZERO, false, true))
	var note := _card("PolicyNote", 12, Color(0, 0, 0, 0), Color(T.GOLD, 0.55), 12)
	var nv := _vbox(6)
	note.add_child(nv)
	nv.add_child(_caps("POR VALIDAR CON EL ROADMAP", T.GOLD))
	policy_label = _wrap_label(str(commerce.shop_policy), 11, T.TEXT_KEY)
	policy_label.name = "Policy"
	nv.add_child(policy_label)
	rv.add_child(note)


# ==========================================================================
# API
# ==========================================================================
func select_category(cat: String) -> void:
	category = cat
	refresh()
	category_selected.emit(cat)


## «+» de Prismas: muestra los paquetes (compra real todavía en construcción).
func show_packs() -> void:
	category = "prismas"
	var r: Dictionary = commerce.request_prisms()
	feedback_label.text = "La compra de Prismas aún está en construcción: los paquetes son una propuesta." if r.get("reason", "") == "under_construction" else ""
	prisms_plus_pressed.emit()
	refresh()


func buy(item_id: String) -> Dictionary:
	var r: Dictionary = commerce.buy_item(item_id)
	if r.get("reason", "") == "under_construction":
		feedback_label.text = "La tienda está en construcción: todavía no se puede comprar."
	elif r.get("ok", false):
		feedback_label.text = "¡Comprado!"
	else:
		feedback_label.text = "No se pudo comprar."
	purchase_attempted.emit(item_id, r)
	refresh()
	return r


# ==========================================================================
# Refresco
# ==========================================================================
func refresh() -> void:
	if not _built:
		return
	for cid in category_buttons:
		(category_buttons[cid] as Button).set_pressed_no_signal(cid == category)
	prisms_label.text = fmt(int(commerce.prisms))
	_clear(grid)
	item_cards.clear()
	if category == "prismas":
		grid_title.text = "PAQUETES DE PRISMAS"
		for p in commerce.shop_packs:
			grid.add_child(_pack_card(p))
	else:
		var label := "DESTACADO DE LA SEMANA"
		for c in commerce.shop_categories:
			if c["id"] == category and category != "destacado":
				label = str(c["label"]).to_upper()
		grid_title.text = label
		for it in commerce.list_shop_items(category):
			grid.add_child(_item_card(it))
	_clear(packs_box)
	for p in commerce.shop_packs:
		var h := _hbox(6)
		packs_box.add_child(h)
		h.add_child(_dot(T.PRISMS, 8))
		var txt := "%s Prismas" % fmt(int(p["prisms"]))
		if int(p.get("bonus", 0)) > 0:
			txt += " + %s" % fmt(int(p["bonus"]))
		var l := _label(txt, 12, T.PRISMS_TEXT, "semibold")
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(l)
		h.add_child(_label(str(p.get("price_real", "—")), 12, T.TEXT_SECONDARY))


func _item_card(it: Dictionary) -> PanelContainer:
	var color := Color(str(it.get("color", "#9aa6ae")))
	var card := _sub_card("Item_" + str(it["id"]), 12)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := _vbox(8)
	card.add_child(v)
	var preview := Panel.new()
	preview.name = "Preview"
	preview.custom_minimum_size = Vector2(0, 92)
	preview.add_theme_stylebox_override("panel", T.box(Color(color, 0.10), 10, 1, Color(color, 0.35)))
	v.add_child(preview)
	var gl := _label("◆", 34, Color(color, 0.75), "bold")
	gl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	gl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	preview.add_child(gl)
	var kind := _badge(CommerceServiceScript.kind_label(str(it["kind"])), T.ACCENT_DEFAULT if it["kind"] == "cosmetic" else T.ALLY)
	kind.name = "Kind"
	kind.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	v.add_child(kind)
	var nm := _label(str(it["name"]), 13, T.TEXT, "semibold")
	nm.clip_text = true
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(nm)
	if str(it.get("note", "")) != "":
		v.add_child(_label(str(it["note"]), 10, T.TEXT_MUTED))
	var h := _hbox(6)
	v.add_child(h)
	var price := _label("◆ %s" % fmt(int(it.get("price_prisms", 0))), 14, T.PRISMS, "bold")
	price.name = "Price"
	price.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(price)
	var b := _ghost_button("Comprar", 12, 28)
	b.name = "Buy"
	b.tooltip_text = "En construcción"
	var iid: String = it["id"]
	b.pressed.connect(func() -> void: buy(iid))
	h.add_child(b)
	item_cards[iid] = card
	return card


func _pack_card(p: Dictionary) -> PanelContainer:
	var card := _sub_card("Pack_" + str(p["id"]), 14)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := _vbox(6)
	card.add_child(v)
	v.add_child(_label("◆ %s" % fmt(int(p["prisms"])), 22, T.PRISMS, "bold"))
	if int(p.get("bonus", 0)) > 0:
		v.add_child(_badge("+%s de regalo" % fmt(int(p["bonus"])), T.PRISMS))
	v.add_child(_label(str(p.get("price_real", "—")), 14, T.TEXT, "semibold"))
	var b := _ghost_button("Próximamente", 12, 28)
	b.disabled = true
	v.add_child(b)
	return card
