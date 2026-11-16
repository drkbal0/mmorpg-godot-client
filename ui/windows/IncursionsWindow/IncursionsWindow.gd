extends "res://ui/windows/common/MenuWindow.gd"
## Incursiones — UI v2.4 Paso 12 (design_ref/pantallas_html/MMO-Incursiones.html).
## Se abre desde Misiones (pestaña Misiones activa en el menú común).
##
## Izquierda: tres tarjetas (Rápida · Media · Larga) con etiqueta de tipo en su color, nombre,
## chips de duración / jugadores / riesgo, descripción, filas (Botín, Extracción o Campamentos,
## Si mueres, y la fila propia de cada tipo), barra «Etapas y puntos de extracción» (tramo gris,
## jefe rojo, salida/campamento verde) y su botón («Entrar ahora» · «Ir a la antesala» ·
## «Planear con el gremio»). La elegida lleva borde cian y botón principal.
## Derecha «Qué llevas»: Bolsa segura (3 ranuras, nunca se pierde) frente a lo que está en
## riesgo si mueres, tu equipo (pulsar mete/saca de la bolsa), checklist de preparación y la
## regla de extracción y desconexión.
##
## Todo el estado vive en `IncursionService` (inyectable como `service`).

const IncursionServiceScript = preload("res://shared-core/IncursionService.gd")
const CollectionsServiceScript = preload("res://shared-core/CollectionsService.gd")

signal incursion_selected(incursion_id: String)
signal entry_result(incursion_id: String, result: Dictionary)
signal lobby_requested(incursion_id: String)
signal guild_plan_requested(incursion_id: String)

const MENU_TAB_ID := "misiones"
const STATUS_COLORS := {"ok": Color("#4fe39a"), "warn": Color("#f5c35b"), "missing": Color("#ff6b6b")}

## Servicio inyectable (tests). Si es null se usa /root/IncursionService o uno local.
var service: Node = null
var selected_id: String = ""

var cards: Dictionary = {}          # incursion_id -> {panel, cta, rows:{key: Label}, stage_bar, hint}
var bag_panel: PanelContainer
var bag_title: Label
var bag_text: Label
var risk_panel: PanelContainer
var risk_title: Label
var risk_text: Label
var risk_value: Label
var gear_flow: HFlowContainer
var gear_buttons: Dictionary = {}   # item_id -> Button
var prep_box: VBoxContainer
var prep_rows: Dictionary = {}      # row id -> {label, value}
var rule_label: Label
var feedback_label: Label

var _built := false
var _refresh_queued := false


func _ready() -> void:
	window_id = "incursions_window"
	_resolve_service()
	_resolve_commerce()
	selected_id = service.selected_id
	_build()
	super._ready()
	connect_menu_bar()
	refresh()


func initialize_window(params: Dictionary) -> void:
	var iid := str(params.get("incursion_id", ""))
	if iid != "" and service and not service.get_incursion(iid).is_empty():
		select_incursion(iid)


func _resolve_service() -> void:
	if service == null and is_inside_tree():
		service = get_node_or_null("/root/IncursionService")
	if service == null:
		service = IncursionServiceScript.new()
		service.name = "LocalIncursionService"
		service.load_seed()
		add_child(service)
	elif service.get_parent() == null:
		add_child(service)
	for sig in ["selection_changed", "loadout_changed", "run_started", "run_ended", "run_stage_changed"]:
		var cb := Callable(self, "_on_service_changed")
		if not service.is_connected(sig, cb):
			service.connect(sig, cb)


func _on_service_changed(_a = null, _b = null) -> void:
	if _refresh_queued or not is_inside_tree():
		return
	_refresh_queued = true
	_deferred_refresh.call_deferred()


func _deferred_refresh() -> void:
	_refresh_queued = false
	if service and service.selected_id != selected_id and not service.get_incursion(service.selected_id).is_empty():
		selected_id = service.selected_id
	refresh()


# ==========================================================================
# Controles dibujados
# ==========================================================================
## «Etapas y puntos de extracción»: una píldora por etapa con el color de su tipo.
class StageBar extends Control:
	var kinds: Array = []:
		set(v):
			kinds = v
			queue_redraw()
	var current := -1:
		set(v):
			current = v
			queue_redraw()

	func _init() -> void:
		custom_minimum_size = Vector2(80, 8)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func segment_rects() -> Array:
		var out: Array = []
		var n := kinds.size()
		if n == 0:
			return out
		var gap := 4.0
		var w := (size.x - gap * (n - 1)) / n
		for i in n:
			out.append(Rect2(i * (w + gap), 0, w, size.y))
		return out

	func _draw() -> void:
		var rects := segment_rects()
		for i in rects.size():
			var sb := StyleBoxFlat.new()
			sb.bg_color = IncursionServiceScript.stage_color(kinds[i])
			sb.set_corner_radius_all(int(size.y * 0.5))
			if i == current:
				sb.border_color = Color.WHITE
				sb.set_border_width_all(1)
			draw_style_box(sb, rects[i])


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
	var cards_row := _hbox(14)
	cards_row.name = "Cards"
	cards_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_child(cards_row)
	for inc in service.incursions:
		cards_row.add_child(_build_card(inc))
	page.add_child(_build_loadout_column())


func _card_style(selected: bool) -> StyleBoxFlat:
	var sb := T.box(T.SHELTER_CARD_BG, 18, 2 if selected else 1, T.ACCENT_DEFAULT if selected else Color(1, 1, 1, 0.07))
	sb.set_content_margin_all(18)
	return sb


func _build_card(inc: Dictionary) -> Control:
	var iid: String = inc["id"]
	var p := PanelContainer.new()
	p.name = "Card_" + iid
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.custom_minimum_size.x = 200
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.add_theme_stylebox_override("panel", _card_style(false))
	p.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			select_incursion(iid))
	var v := _vbox(10)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(v)
	var tier := _caps(str(inc.get("tier_label", "")).to_upper(), IncursionServiceScript.tier_color(inc["tier"]))
	tier.name = "Tier"
	v.add_child(tier)
	var nm := _wrap_label(str(inc["name"]), 22, T.TEXT, "bold")
	nm.name = "Name"
	v.add_child(nm)
	var tags := HFlowContainer.new()
	tags.name = "Tags"
	tags.add_theme_constant_override("h_separation", 6)
	tags.add_theme_constant_override("v_separation", 6)
	tags.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for t in service.tags(iid):
		var chip := _badge(t, T.TEXT_KEY, T.POWERS_CHIP_BG, 12)
		chip.name = "Tag"
		tags.add_child(chip)
	v.add_child(tags)
	var desc := _wrap_label(str(inc.get("description", "")), 13, T.TEXT_KEY)
	desc.name = "Description"
	v.add_child(desc)
	var rows := {}
	for r in service.card_rows(iid):
		var h := _hbox(8)
		h.name = "Row_" + str(r["key"])
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var l := _label(str(r["label"]), 13, T.TEXT_SECONDARY)
		h.add_child(l)
		var val := _label("", 13, T.TEXT, "bold")
		val.name = "Value"
		val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		val.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		val.custom_minimum_size.x = 60
		h.add_child(val)
		v.add_child(h)
		rows[r["key"]] = val
	var sv := _vbox(4)
	sv.name = "Stages"
	v.add_child(sv)
	sv.add_child(_label("Etapas y puntos de extracción", 12, T.TEXT_SECONDARY))
	var bar := StageBar.new()
	bar.name = "StageBar"
	bar.kinds = inc["stages"].duplicate()
	sv.add_child(bar)
	var legend := _label("", 11, T.TEXT_MUTED)
	legend.name = "StageLegend"
	sv.add_child(legend)
	v.add_child(_spacer(Vector2.ZERO, false, true))
	var hint := _wrap_label("", 12, T.TEXT_SECONDARY)
	hint.name = "Hint"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(hint)
	var cta := _ghost_button(str(inc["cta"].get("label", "Entrar")), 14, 42)
	cta.name = "Cta"
	cta.pressed.connect(press_cta.bind(iid))
	v.add_child(cta)
	cards[iid] = {"panel": p, "cta": cta, "rows": rows, "stage_bar": bar, "legend": legend, "hint": hint}
	return p


func _build_loadout_column() -> Control:
	var card := _card("LoadoutCard", 18)
	card.custom_minimum_size.x = 340
	var v := _vbox(9)
	card.add_child(v)
	v.add_child(_caps("QUÉ LLEVAS"))
	bag_panel = _tinted_sub("SecureBag", Color("#4fe39a"))
	var bv := _vbox(4)
	bag_panel.add_child(bv)
	bag_title = _label("", 14, Color("#4fe39a"), "bold")
	bag_title.name = "Title"
	bv.add_child(bag_title)
	bag_text = _wrap_label("", 12, T.TEXT_KEY)
	bag_text.name = "Text"
	bv.add_child(bag_text)
	v.add_child(bag_panel)
	risk_panel = _tinted_sub("AtRisk", Color("#ff6b6b"))
	var rv := _vbox(4)
	risk_panel.add_child(rv)
	risk_title = _label("En riesgo si mueres", 14, Color("#ff8a8a"), "bold")
	risk_title.name = "Title"
	rv.add_child(risk_title)
	risk_text = _wrap_label("", 12, T.TEXT_KEY)
	risk_text.name = "Text"
	rv.add_child(risk_text)
	risk_value = _wrap_label("", 11, T.TEXT_SECONDARY)
	risk_value.name = "Value"
	rv.add_child(risk_value)
	v.add_child(risk_panel)
	var gl := _label("Tu equipo · pulsa para meter o sacar de la bolsa", 11, T.TEXT_MUTED)
	gl.name = "GearCaption"
	v.add_child(gl)
	gear_flow = HFlowContainer.new()
	gear_flow.name = "Gear"
	gear_flow.add_theme_constant_override("h_separation", 5)
	gear_flow.add_theme_constant_override("v_separation", 5)
	v.add_child(gear_flow)
	var pc := _caps("PREPARACIÓN")
	v.add_child(_spacer(Vector2(0, 2)))
	v.add_child(pc)
	prep_box = _vbox(5)
	prep_box.name = "Preparation"
	v.add_child(prep_box)
	for r in service.readiness():
		var h := _hbox(8)
		h.name = "Prep_" + str(r["id"])
		var l := _label(str(r["label"]), 13, T.TEXT_KEY)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(l)
		var val := _label("", 13, T.TEXT, "bold")
		val.name = "Value"
		h.add_child(val)
		prep_box.add_child(h)
		prep_rows[r["id"]] = {"label": l, "value": val, "row": h}
	feedback_label = _wrap_label("", 12, T.TEXT_SECONDARY)
	feedback_label.name = "Feedback"
	v.add_child(feedback_label)
	v.add_child(_spacer(Vector2.ZERO, false, true))
	var rule := _sub_card("Rule", 12)
	rule_label = _wrap_label(IncursionServiceScript.RULE_TEXT, 12, T.TEXT_KEY)
	rule_label.name = "Text"
	rule.add_child(rule_label)
	v.add_child(rule)
	return card


func _tinted_sub(node_name: String, tint: Color) -> PanelContainer:
	var p := PanelContainer.new()
	p.name = node_name
	var sb := T.box(T.SHELTER_SUB_BG, 12, 1, Color(tint, 0.45))
	sb.set_content_margin_all(12)
	p.add_theme_stylebox_override("panel", sb)
	return p


# ==========================================================================
# Interacción
# ==========================================================================
func select_incursion(id: String) -> void:
	if service == null or service.get_incursion(id).is_empty():
		return
	selected_id = id
	service.select(id)
	refresh()
	incursion_selected.emit(id)


func press_cta(id: String) -> Dictionary:
	select_incursion(id)
	var inc: Dictionary = service.get_incursion(id)
	var pmin: int = int(inc["players"][0])
	var r: Dictionary = service.request_entry(id, pmin)
	match str(r.get("action", "")):
		"lobby":
			lobby_requested.emit(id)
		"guild":
			guild_plan_requested.emit(id)
			open_other_window("social_window", {"tab": "guild", "plan": id})
	feedback_label.text = _feedback_text(inc, r)
	feedback_label.add_theme_color_override("font_color", T.TEXT_SECONDARY if r.get("ok", false) else Color("#ff8a8a"))
	entry_result.emit(id, r)
	refresh()
	return r


func toggle_secure(item_id: String) -> Dictionary:
	var r: Dictionary
	if service.is_secured(item_id):
		r = service.remove_from_secure_bag(item_id)
	else:
		r = service.put_in_secure_bag(item_id)
	if not r.get("ok", false):
		feedback_label.text = "La bolsa segura está llena (3 / 3): saca algo antes." if r.get("reason", "") == "bag_full" else "No se puede cambiar la bolsa dentro de una incursión."
		feedback_label.add_theme_color_override("font_color", Color("#ff8a8a"))
	else:
		feedback_label.text = ""
	refresh()
	return r


func _feedback_text(inc: Dictionary, r: Dictionary) -> String:
	if not r.get("ok", false):
		match str(r.get("reason", "")):
			"not_ready":
				var names: Array[String] = []
				for b in r.get("blockers", []):
					names.append(_prep_label(str(b)))
				return "Te falta: %s." % ", ".join(names)
			"already_inside":
				return "Ya estás dentro de una incursión."
			"party_size":
				return "Necesitas %s." % service.players_text(inc["id"])
		return "No se pudo entrar."
	match str(r.get("action", "")):
		"lobby":
			return "Antesala de %s · tu grupo: %d / %d listos." % [inc["name"], int(r["party"].get("ready", 0)), int(r["party"].get("size", 1))]
		"guild":
			return "Planificación con el gremio abierta para %s." % inc["name"]
	return "Entrando en %s…" % inc["name"]


func _prep_label(id: String) -> String:
	for r in service.readiness(selected_id):
		if r["id"] == id:
			return str(r["label"])
	return id


# ==========================================================================
# Refresco
# ==========================================================================
func refresh() -> void:
	if not _built or service == null:
		return
	if service.get_incursion(selected_id).is_empty():
		selected_id = service.selected_id
	_refresh_cards()
	_refresh_loadout()


func _refresh_cards() -> void:
	for iid in cards:
		var c: Dictionary = cards[iid]
		var sel: bool = iid == selected_id
		c["panel"].add_theme_stylebox_override("panel", _card_style(sel))
		for r in service.card_rows(iid):
			var lbl: Label = c["rows"].get(r["key"])
			if lbl:
				lbl.text = str(r["value"])
				lbl.add_theme_color_override("font_color", Color("#4fe39a") if r["good"] else T.TEXT)
		var inc: Dictionary = service.get_incursion(iid)
		var inside: bool = service.in_run() and service.run["incursion_id"] == iid
		c["stage_bar"].current = int(service.run["stage"]) if inside else -1
		var counts := {"exit": 0, "camp": 0, "boss": 0}
		for k in inc["stages"]:
			if counts.has(k):
				counts[k] += 1
		var parts: Array[String] = ["%d etapas" % inc["stages"].size()]
		if counts["boss"] > 0:
			parts.append("%d jefe%s" % [counts["boss"], "" if counts["boss"] == 1 else "s"])
		if counts["exit"] > 0:
			parts.append("%d salida%s" % [counts["exit"], "" if counts["exit"] == 1 else "s"])
		if counts["camp"] > 0:
			parts.append("%d campamentos" % counts["camp"])
		if inc["flare_allowed"]:
			parts.append("bengala")
		c["legend"].text = " · ".join(parts)
		var cta: Button = c["cta"]
		if inside:
			cta.text = "Dentro · etapa %d / %d" % [int(service.run["stage"]) + 1, inc["stages"].size()]
			cta.disabled = true
		else:
			cta.text = str(inc["cta"].get("label", "Entrar"))
			cta.disabled = service.in_run()
		if sel:
			_style_primary(cta)
		else:
			_style_ghost(cta)
		var b: Array = service.blockers(iid)
		var hint: Label = c["hint"]
		if not b.is_empty() and not inside:
			var names: Array[String] = []
			for id in b:
				names.append(_prep_label_for(iid, id))
			hint.text = "Falta: " + ", ".join(names)
			hint.add_theme_color_override("font_color", Color("#ff8a8a"))
			hint.visible = true
		else:
			hint.text = str(inc["cta"].get("hint", ""))
			hint.add_theme_color_override("font_color", T.TEXT_MUTED)
			hint.visible = hint.text != "" and hint.text != cta.text


func _prep_label_for(iid: String, id: String) -> String:
	for r in service.readiness(iid):
		if r["id"] == id:
			return str(r["label"])
	return id


func _style_primary(b: Button) -> void:
	var normal := T.box(T.ACCENT_DEFAULT, 10)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = T.ACCENT_DEFAULT.lightened(0.15)
	var disabled := T.box(Color(T.ACCENT_DEFAULT, 0.3), 10)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("disabled", disabled)
	for s in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(s, Color("#071012"))
	b.add_theme_color_override("font_disabled_color", Color("#071012", 0.7))
	b.set_meta("style", "primary")


func _style_ghost(b: Button) -> void:
	var normal := T.box(T.BUTTON_BG, 10)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = T.SLOT_READY
	var disabled := T.box(Color(T.BUTTON_BG, 0.5), 10)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("disabled", disabled)
	for s in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(s, T.TEXT)
	b.add_theme_color_override("font_disabled_color", T.TEXT_MUTED)
	b.set_meta("style", "ghost")


func _refresh_loadout() -> void:
	var bag: Dictionary = service.secure_bag_status()
	bag_title.text = bag["title"]
	bag_text.text = bag["text"]
	var risk: Dictionary = service.at_risk(selected_id)
	risk_text.text = risk["text"]
	if int(risk["total_value"]) > 0:
		risk_value.text = "Valor en riesgo: %s oro en equipo · %s oro · a salvo en la bolsa: %s" % [fmt(int(risk["items_value"])), fmt(int(risk["gold"])), fmt(int(risk["secured_value"]))]
	else:
		risk_value.text = "Tu equipo y tu oro vuelven contigo. A salvo en la bolsa: %s" % fmt(int(risk["secured_value"]))
	if risk["revivable"]:
		risk_value.text += " · tu grupo puede levantarte"
	elif risk["recoverable"]:
		risk_value.text += " · fardo recuperable 30 min"
	_clear(gear_flow)
	gear_buttons.clear()
	for it in service.carried:
		var secured: bool = service.is_secured(it["id"])
		var b := _chip_button(str(it["name"]), 12, 24)
		b.name = "Gear_" + str(it["id"])
		b.button_pressed = secured
		b.tooltip_text = "En la bolsa segura" if secured else "En riesgo si mueres"
		var rc := CollectionsServiceScript.rarity_color(str(it.get("rarity", "common")))
		var normal := T.box(T.POWERS_CHIP_BG, 8, 1, Color(rc, 0.35))
		normal.content_margin_left = 8
		normal.content_margin_right = 8
		var on := T.box(Color("#4fe39a", 0.14), 8, 1, Color("#4fe39a", 0.8))
		on.content_margin_left = 8
		on.content_margin_right = 8
		b.add_theme_stylebox_override("normal", normal)
		b.add_theme_stylebox_override("hover", normal)
		b.add_theme_stylebox_override("pressed", on)
		b.add_theme_stylebox_override("hover_pressed", on)
		for s in ["font_pressed_color", "font_hover_pressed_color"]:
			b.add_theme_color_override(s, Color("#4fe39a"))
		b.disabled = service.in_run()
		var iid: String = it["id"]
		b.pressed.connect(func() -> void: toggle_secure(iid))
		gear_flow.add_child(b)
		gear_buttons[iid] = b
	for r in service.readiness(selected_id):
		var row: Dictionary = prep_rows.get(r["id"], {})
		if row.is_empty():
			continue
		row["value"].text = str(r["value"])
		var col: Color = STATUS_COLORS.get(r["status"], T.TEXT)
		if r["id"] == "durability":
			col = IncursionServiceScript.durability_color(int(r["have"])) if r["status"] != "missing" else STATUS_COLORS["missing"]
		if r["id"] == "return_route" and r["status"] == "ok":
			col = T.TEXT
		if r["status"] == "warn" and r["id"] in ["campfire_kit", "flare"]:
			col = T.TEXT_SECONDARY
		row["value"].add_theme_color_override("font_color", col)
