extends "res://ui/windows/common/MenuWindow.gd"
## Trato cara a cara — UI v2.4 Paso 11 (design_ref/pantallas_html/MMO-Trato.html).
##
## Cabecera «Trato con Sasha · Cara a cara · a 3 m · reputación: Confiable», dos mitades
## simétricas («Tú das» / «Sasha da») con borde de rareza, procedencia y valor de mercado,
## mensaje inferior dinámico (máscara «???», espera de 3 s, balance) y botones
## «Cancelar» · «Pedir que lo enseñe» · «Confirmar».
##
## No lleva el menú común: es una tarjeta modal sobre el mundo. Usa los ayudantes
## visuales de MenuWindow. Todo el estado vive en `TradeService` (inyectable).

const TradeServiceScript = preload("res://shared-core/TradeService.gd")

signal confirmed_local
signal trade_closed(result: Dictionary)

const CARD_SIZE := Vector2(900, 600)
const GOLD_STEP := 50
const COLOR_CONFIRMED := Color("#4fe39a")

## Servicio inyectable (tests). Si es null se usa /root/TradeService o uno local.
var service: Node = null
## Códice inyectable (tests); si es null el servicio usa /root/KnowledgeService.
var knowledge: Node = null
## Si el servicio no tiene reloj real, la ventana avanza su espera de seguridad.
var drive_clock: bool = true

var title_label_big: Label
var subtitle_label: Label
var side_panels: Dictionary = {}      # side -> PanelContainer
var side_titles: Dictionary = {}      # side -> Label
var side_status: Dictionary = {}      # side -> Label
var side_rows: Dictionary = {}        # side -> VBoxContainer
var side_value: Dictionary = {}       # side -> Label
var row_nodes: Dictionary = {}        # side -> Array[{panel, name, subtitle, slot, view}]
var gold_label: Label
var gold_minus: Button
var gold_plus: Button
var info_panel: PanelContainer
var info_label: Label
var note_label: Label
var cancel_button: Button
var reveal_button: Button
var confirm_button: Button

var _built := false
var _refresh_queued := false


func _ready() -> void:
	window_id = "trade_window"
	custom_minimum_size = CARD_SIZE
	size = CARD_SIZE
	add_theme_stylebox_override("panel", T.box(T.SHELTER_CARD_BG, 18, 1, T.CODEX_CARD_BORDER))
	_resolve_service()
	_build()
	super._ready()
	if not service.active:
		service.start_session("Sasha", {})
	refresh()
	set_process(true)


func initialize_window(params: Dictionary) -> void:
	if service == null:
		return
	var tn := str(params.get("target_name", "Sasha"))
	var td: Dictionary = params.get("target_data", {})
	if not service.active or service.target_name != tn or not td.is_empty() \
			or service.state == TradeServiceScript.State.COMPLETED or service.state == TradeServiceScript.State.CANCELLED:
		service.start_session(tn, td)
	refresh()


func _resolve_service() -> void:
	if service == null:
		service = get_node_or_null("/root/TradeService")
	if service == null:
		service = TradeServiceScript.new()
		service.name = "LocalTradeService"
		service.load_seed()
		add_child(service)
	elif service.get_parent() == null:
		add_child(service)
	if knowledge != null:
		service.knowledge = knowledge
	for sig in ["offer_changed", "state_changed", "session_started", "item_revealed", "reveal_requested", "confirmations_reset", "trade_completed", "trade_cancelled"]:
		var cb := Callable(self, "_on_service_changed")
		if not service.is_connected(sig, cb):
			service.connect(sig, cb)
	if not service.cooldown_changed.is_connected(_on_cooldown):
		service.cooldown_changed.connect(_on_cooldown)


func _on_service_changed(_a = null) -> void:
	if _refresh_queued:
		return
	_refresh_queued = true
	_deferred_refresh.call_deferred()


func _deferred_refresh() -> void:
	_refresh_queued = false
	refresh()


func _on_cooldown(_r: float) -> void:
	_refresh_footer()


func _process(delta: float) -> void:
	if drive_clock and visible and service and not service.realtime and service.in_cooldown():
		service.tick(delta)


# ==========================================================================
# Construcción
# ==========================================================================
func _build() -> void:
	if _built:
		return
	_built = true
	var m := MarginContainer.new()
	m.name = "Margin"
	for s in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + s, 22)
	add_child(m)
	var v := _vbox(12)
	v.name = "Root"
	m.add_child(v)
	var header := _hbox(10)
	header.name = "Header"
	v.add_child(header)
	title_label_big = _label("", 22, T.TEXT, "bold")
	title_label_big.name = "TitleLabel"
	header.add_child(title_label_big)
	subtitle_label = _label("", 13, T.TEXT_SECONDARY)
	subtitle_label.name = "Subtitle"
	subtitle_label.size_flags_vertical = Control.SIZE_SHRINK_END
	header.add_child(subtitle_label)
	var cols := _hbox(16)
	cols.name = "Columns"
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(cols)
	for side in TradeServiceScript.SIDES:
		cols.add_child(_build_side(side))
	info_panel = PanelContainer.new()
	info_panel.name = "InfoPanel"
	var isb := T.box(T.SHELTER_SUB_BG, 12, 1, Color(T.GOLD, 0.45))
	isb.content_margin_left = 14
	isb.content_margin_right = 14
	isb.content_margin_top = 9
	isb.content_margin_bottom = 9
	info_panel.add_theme_stylebox_override("panel", isb)
	info_label = _wrap_label("", 13, T.TEXT_KEY)
	info_label.name = "InfoLabel"
	info_panel.add_child(info_label)
	v.add_child(info_panel)
	var bottom := _hbox(10)
	bottom.name = "Buttons"
	v.add_child(bottom)
	note_label = _wrap_label("Si alguien cambia algo, las dos confirmaciones se borran y hay 3 s de espera.", 12, T.TEXT_SECONDARY)
	note_label.name = "SecurityNote"
	note_label.custom_minimum_size.x = 330
	bottom.add_child(note_label)
	cancel_button = _ghost_button("Cancelar", 14, 36)
	cancel_button.name = "CancelButton"
	cancel_button.pressed.connect(cancel_trade)
	bottom.add_child(cancel_button)
	reveal_button = _ghost_button("Pedir que lo enseñe", 14, 36)
	reveal_button.name = "RevealButton"
	reveal_button.pressed.connect(request_reveal)
	bottom.add_child(reveal_button)
	confirm_button = _primary_button("Confirmar", 14, 36)
	confirm_button.name = "ConfirmButton"
	confirm_button.custom_minimum_size.x = 130
	confirm_button.pressed.connect(press_confirm)
	bottom.add_child(confirm_button)


func _build_side(side: String) -> Control:
	var p := PanelContainer.new()
	p.name = "Side_" + side
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.size_flags_stretch_ratio = 1.0
	var v := _vbox(8)
	p.add_child(v)
	var top := _hbox(8)
	v.add_child(top)
	var t := _label("", 15, T.TEXT, "bold")
	t.name = "Title"
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(t)
	var st := _label("", 12, T.TEXT_SECONDARY, "bold")
	st.name = "Status"
	top.add_child(st)
	var rows := _vbox(8)
	rows.name = "Rows"
	v.add_child(rows)
	if side == TradeServiceScript.LOCAL:
		var gh := _hbox(6)
		gh.name = "GoldEditor"
		var gl := _label("Tu oro en el trato", 12, T.TEXT_SECONDARY)
		gl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		gh.add_child(gl)
		gold_minus = _ghost_button("−%d" % GOLD_STEP, 12, 26)
		gold_minus.name = "GoldMinus"
		gold_minus.pressed.connect(func() -> void: change_gold(-GOLD_STEP))
		gh.add_child(gold_minus)
		gold_label = _label("", 13, T.GOLD, "bold")
		gold_label.name = "GoldValue"
		gold_label.custom_minimum_size.x = 64
		gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		gh.add_child(gold_label)
		gold_plus = _ghost_button("+%d" % GOLD_STEP, 12, 26)
		gold_plus.name = "GoldPlus"
		gold_plus.pressed.connect(func() -> void: change_gold(GOLD_STEP))
		gh.add_child(gold_plus)
		v.add_child(gh)
	v.add_child(_spacer(Vector2.ZERO, false, true))
	var foot := _hbox(6)
	v.add_child(foot)
	var fl := _label("Valor de mercado", 13, T.TEXT_SECONDARY)
	fl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(fl)
	var val := _label("", 13, T.GOLD, "bold")
	val.name = "Value"
	foot.add_child(val)
	side_panels[side] = p
	side_titles[side] = t
	side_status[side] = st
	side_rows[side] = rows
	side_value[side] = val
	return p


# ==========================================================================
# Acciones
# ==========================================================================
func press_confirm() -> Dictionary:
	var S = TradeServiceScript.State
	if service.state == S.COMPLETED or service.state == S.CANCELLED:
		_close()
		return {"ok": true, "closed": true}
	if service.state == S.LOCKED_BOTH:
		var res: Dictionary = service.complete()
		refresh()
		return res
	if service.is_confirmed(TradeServiceScript.LOCAL):
		service.unconfirm(TradeServiceScript.LOCAL)
		refresh()
		return {"ok": true, "unconfirmed": true}
	var r: Dictionary = service.confirm(TradeServiceScript.LOCAL)
	if r["ok"]:
		confirmed_local.emit()
	refresh()
	return r


func cancel_trade() -> void:
	var S = TradeServiceScript.State
	if service.state != S.COMPLETED:
		service.cancel(TradeServiceScript.LOCAL)
	_close()


func request_reveal() -> bool:
	var ok: bool = service.request_reveal()
	refresh()
	return ok


func change_gold(delta: int) -> bool:
	var g := int(service.get_offer(TradeServiceScript.LOCAL).get("gold", 0))
	var ok: bool = service.set_gold(TradeServiceScript.LOCAL, clampi(g + delta, 0, int(service.local_gold)))
	refresh()
	return ok


func remove_local_item(index: int) -> bool:
	var ok: bool = service.remove_item(TradeServiceScript.LOCAL, index)
	refresh()
	return ok


func _close() -> void:
	trade_closed.emit(service.last_result)
	var orch := get_node_or_null("/root/UIOrchestrator")
	if orch and orch.has_method("get_window_instance") and orch.get_window_instance(window_id) == self:
		orch.close_window(window_id)
	else:
		visible = false


# ==========================================================================
# Refresco
# ==========================================================================
func refresh() -> void:
	if not _built or service == null:
		return
	title_label_big.text = service.header_text()
	subtitle_label.text = service.header_subtitle()
	for side in TradeServiceScript.SIDES:
		_refresh_side(side)
	if gold_label:
		gold_label.text = "%s oro" % fmt(int(service.get_offer(TradeServiceScript.LOCAL).get("gold", 0)))
		var editable: bool = service.can_modify()
		gold_minus.disabled = not editable or int(service.get_offer(TradeServiceScript.LOCAL).get("gold", 0)) <= 0
		gold_plus.disabled = not editable
	_refresh_footer()
	_fit.call_deferred()


## Tamaño de tarjeta fijo (900×600) salvo que el contenido pida más.
func _fit() -> void:
	if not is_inside_tree():
		return
	var m := get_combined_minimum_size()
	size = Vector2(maxf(CARD_SIZE.x, m.x), maxf(CARD_SIZE.y, m.y))


func _refresh_side(side: String) -> void:
	side_titles[side].text = "Tú das" if side == TradeServiceScript.LOCAL else "%s da" % service.target_name
	var conf: bool = service.is_confirmed(side) or service.state == TradeServiceScript.State.COMPLETED
	side_status[side].text = service.status_text(side)
	side_status[side].add_theme_color_override("font_color", COLOR_CONFIRMED if conf else T.TEXT_SECONDARY)
	var sb := T.box(T.SHELTER_SUB_BG, 12, 2 if conf else 0, COLOR_CONFIRMED if conf else Color.TRANSPARENT)
	sb.set_content_margin_all(16)
	side_panels[side].add_theme_stylebox_override("panel", sb)
	side_value[side].text = "%s oro" % fmt(int(service.market_value(side)))
	var box: VBoxContainer = side_rows[side]
	_clear(box)
	var nodes: Array = []
	var views: Array = service.view_offer(side)
	for i in views.size():
		var vw: Dictionary = views[i]
		nodes.append(_item_row(side, i, vw))
		box.add_child(nodes[-1]["panel"])
	if views.is_empty():
		box.add_child(_label("No ofrece nada todavía.", 13, T.TEXT_MUTED))
	row_nodes[side] = nodes


func _item_row(side: String, index: int, vw: Dictionary) -> Dictionary:
	var p := PanelContainer.new()
	p.name = "Row_%d" % index
	var sb := T.box(T.SLOT_EMPTY, 10)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 7
	sb.content_margin_bottom = 7
	p.add_theme_stylebox_override("panel", sb)
	var h := _hbox(10)
	p.add_child(h)
	var slot := PanelContainer.new()
	slot.name = "Slot"
	slot.custom_minimum_size = Vector2(36, 36)
	slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slot.add_theme_stylebox_override("panel", T.box(T.WELL, 9, 2, vw["border_color"]))
	var q := _label(str(vw["icon_text"]), 16, Color("#56646d"), "bold")
	q.name = "Glyph"
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	q.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	slot.add_child(q)
	h.add_child(slot)
	var tv := _vbox(1)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(tv)
	var n := _label(vw["display_name"], 14, vw["name_color"], "bold")
	n.name = "Name"
	n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	n.clip_text = true
	tv.add_child(n)
	var s := _label(vw["subtitle"], 12, vw["subtitle_color"])
	s.name = "Subtitle"
	s.visible = str(vw["subtitle"]) != ""
	tv.add_child(s)
	if side == TradeServiceScript.LOCAL and not bool(vw["is_gold"]) and service.can_modify():
		var x := _ghost_button("×", 12, 24)
		x.name = "Remove"
		x.tooltip_text = "Quitar del trato (borra las dos confirmaciones)"
		x.custom_minimum_size.x = 26
		x.pressed.connect(remove_local_item.bind(index))
		h.add_child(x)
	return {"panel": p, "name": n, "subtitle": s, "slot": slot, "view": vw}


func _refresh_footer() -> void:
	if not _built or service == null:
		return
	info_label.text = service.info_text()
	var S = TradeServiceScript.State
	var st: int = service.state
	reveal_button.visible = service.has_masked_remote()
	reveal_button.disabled = service.reveal_pending or st == S.LOCKED_BOTH or st == S.COMPLETED or st == S.CANCELLED
	reveal_button.text = "Esperando a que lo enseñe…" if service.reveal_pending else "Pedir que lo enseñe"
	cancel_button.disabled = st == S.COMPLETED or st == S.CANCELLED
	match st:
		S.COMPLETED, S.CANCELLED:
			confirm_button.text = "Cerrar"
			confirm_button.disabled = false
		S.LOCKED_BOTH:
			confirm_button.text = "Cerrar trato ✓"
			confirm_button.disabled = false
		_:
			if service.is_confirmed(TradeServiceScript.LOCAL):
				confirm_button.text = "Quitar confirmación"
				confirm_button.disabled = false
			elif service.in_cooldown():
				confirm_button.text = "Confirmar (%d s)" % int(ceil(service.cooldown_remaining))
				confirm_button.disabled = true
			else:
				confirm_button.text = "Confirmar"
				confirm_button.disabled = not service.can_confirm(TradeServiceScript.LOCAL)
