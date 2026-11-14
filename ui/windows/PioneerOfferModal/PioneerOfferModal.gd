extends "res://ui/templates/BaseWindow.gd"
## Oferta de inversión del pionero (UI v2.4 §2.3.7 · design_ref/pantallas_html/MMO-Oferta.html).
##
## Cuando el jugador es el PIONERO de una tienda o PNJ, el PNJ le ofrece ser
## socio: una misión especial solo para él que, al completarse, le da un % de
## TODAS las transacciones de cualquier jugador con ese PNJ.
##
## Izquierda: retrato + diálogo + 3 respuestas (teclas 1 · 2 · 3).
##   1 «Trato hecho»        -> KnowledgeService.accept_pioneer_offer (inicia la misión)
##   2 «Déjame pensarlo»    -> defer_pioneer_offer (se guarda 7 días en Códice › Inversiones)
##   3 «No me interesa»     -> reject_pioneer_offer (pasa al siguiente descubridor)
## Derecha: tarjeta de la oferta (misión, tu parte, estimado y condiciones claras).

const T = preload("res://ui/tokens/hud_tokens.gd")
const KnowledgeServiceScript = preload("res://shared-core/KnowledgeService.gd")

signal offer_decided(decision: String, result: Dictionary)

const DECISION_ACCEPT := "accept"
const DECISION_DEFER := "defer"
const DECISION_REJECT := "reject"
const THINK_DAYS := 7

## Condiciones claras (§2.3.7). Siempre visibles en la tarjeta.
const CONDITIONS: Array[String] = [
	"Cobras aunque no estés conectado; se acumula en el almacén de tu refugio.",
	"Puedes vender tu participación a otro jugador en el mercado.",
	"Si el puesto cierra por un evento, el contrato se pausa, no se pierde.",
	"Solo hay un socio por puesto: el pionero que lo acepta primero.",
]

## Oferta por defecto (demo / captura). En juego llega por `initialize_window({"offer": …})`.
const DEFAULT_OFFER := {
	"id": "offer_gildas_vado",
	"npc_id": "pnj_gildas",
	"npc_name": "Gildas",
	"npc_role": "Mercader del Vado",
	"shop_name": "Puesto de Gildas",
	"zone": "Vado Roto · Verdalia",
	"share": 0.02,
	"fee": 2000,
	"estimate_min": 300,
	"estimate_max": 900,
	"dialogue": "Eres la primera persona que encuentra mi puesto. Si me ayudas a traer mercancía, te doy una parte de todo lo que venda… a quien sea.",
	"mission": {
		"name": "Ruta de suministro",
		"steps": [
			{"label": "Provee 5 Cristales de Vacío", "goal": 5, "progress": 0},
			{"label": "Asegura la ruta comercial del Vado", "goal": 1, "progress": 0},
		],
	},
	"next_discoverer": "",
}

const OPTIONS: Array[Dictionary] = [
	{"id": DECISION_ACCEPT, "key": "1", "text": "Trato hecho. ¿Qué necesitas?", "hint": "Acepta la misión especial", "label": "Aceptar Misión"},
	{"id": DECISION_DEFER, "key": "2", "text": "Déjame pensarlo.", "hint": "La oferta se guarda 7 días en tu Códice", "label": "Pensarlo (7 días)"},
	{"id": DECISION_REJECT, "key": "3", "text": "No me interesa.", "hint": "Pasa al siguiente que la descubra", "label": "Rechazar"},
]

## Servicio inyectable (tests). Si es null se usa el autoload /root/KnowledgeService.
var service: Node = null
var offer: Dictionary = {}
var last_decision: String = ""
var last_result: Dictionary = {}

var accept_button: Button
var defer_button: Button
var reject_button: Button
var option_buttons: Dictionary = {}     # decision -> Button
var npc_name_label: Label
var npc_role_label: Label
var pioneer_badge: PanelContainer
var dialogue_label: Label
var offer_title_label: Label
var mission_name_label: Label
var mission_steps_box: VBoxContainer
var share_label: Label
var estimate_label: Label
var conditions_box: VBoxContainer
var status_label: Label
var offer_card: PanelContainer

var _built := false


func _init() -> void:
	theme = T.THEME
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	is_draggable = false
	_build()
	set_offer(DEFAULT_OFFER)


func _ready() -> void:
	window_id = "pioneer_offer"
	super._ready()
	add_to_group("pioneer_offer_modal")
	_resolve_service()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## Modal a pantalla completa: no se recoloca como una ventana normal.
func center_on_screen() -> void:
	pass


func initialize_window(params: Dictionary) -> void:
	if params.has("offer"):
		set_offer(params["offer"])
	if params.has("next_discoverer"):
		offer["next_discoverer"] = str(params["next_discoverer"])


func _resolve_service() -> void:
	if service == null:
		service = get_node_or_null("/root/KnowledgeService")
	if service == null:
		service = KnowledgeServiceScript.new()
		service.name = "LocalKnowledgeService"
		add_child(service)


# ==========================================================================
# API
# ==========================================================================
func set_offer(data: Dictionary) -> void:
	offer = DEFAULT_OFFER.duplicate(true)
	for k in data:
		offer[k] = data[k] if not (data[k] is Dictionary or data[k] is Array) else data[k].duplicate(true)
	last_decision = ""
	last_result = {}
	_refresh()


## Texto de la cuota de socio: 0.02 -> "2 %", 0.015 -> "1,5 %".
static func share_text(share: float) -> String:
	var p := share * 100.0
	if is_equal_approx(p, roundf(p)):
		return "%d %%" % roundi(p)
	return ("%.1f %%" % p).replace(".", ",")


func get_share_percent() -> float:
	return float(offer.get("share", 0.0)) * 100.0


func get_mission_steps() -> Array:
	return (offer.get("mission", {}) as Dictionary).get("steps", [])


func get_condition_texts() -> Array[String]:
	return CONDITIONS.duplicate()


## Elige una respuesta: "accept" · "defer" · "reject". Devuelve el resultado del servicio.
func choose(decision: String) -> Dictionary:
	if service == null:
		_resolve_service()
	var result: Dictionary
	match decision:
		DECISION_ACCEPT:
			result = service.accept_pioneer_offer(offer)
		DECISION_DEFER:
			result = service.defer_pioneer_offer(offer)
		DECISION_REJECT:
			result = service.reject_pioneer_offer(offer, str(offer.get("next_discoverer", "")))
		_:
			result = {"ok": false, "reason": "invalid_decision"}
	last_decision = decision
	last_result = result
	status_label.text = _result_text(decision, result)
	status_label.add_theme_color_override("font_color", T.CODEX_PUBLISHED if result.get("ok", false) else T.CODEX_ALERT)
	offer_decided.emit(decision, result)
	if result.get("ok", false):
		_set_buttons_enabled(false)
	return result


func accept_offer() -> Dictionary:
	return choose(DECISION_ACCEPT)


func defer_offer() -> Dictionary:
	return choose(DECISION_DEFER)


func reject_offer() -> Dictionary:
	return choose(DECISION_REJECT)


func close_modal() -> void:
	_on_close_pressed()


func _result_text(decision: String, r: Dictionary) -> String:
	if not r.get("ok", false):
		match str(r.get("reason", "")):
			"post_has_partner":
				return "Este puesto ya tiene socio: solo hay uno por puesto."
			_:
				return "No se pudo completar (%s)." % r.get("reason", "?")
	match decision:
		DECISION_ACCEPT:
			return "Misión especial iniciada: «%s». Al completarla serás socio." % (offer.get("mission", {}) as Dictionary).get("name", "")
		DECISION_DEFER:
			return "Oferta guardada %d días en Códice › Inversiones." % int(r.get("expires_in_days", THINK_DAYS))
		DECISION_REJECT:
			var to := str(r.get("passed_to", ""))
			return "Oferta rechazada: pasa a %s." % (to if to != "" else "la siguiente persona que descubra el puesto")
	return ""


func _set_buttons_enabled(on: bool) -> void:
	for b in option_buttons.values():
		(b as Button).disabled = not on


func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not (event is InputEventKey) or not event.pressed or event.is_echo():
		return
	var k := event as InputEventKey
	var map := {KEY_1: DECISION_ACCEPT, KEY_2: DECISION_DEFER, KEY_3: DECISION_REJECT, KEY_KP_1: DECISION_ACCEPT, KEY_KP_2: DECISION_DEFER, KEY_KP_3: DECISION_REJECT}
	if map.has(k.keycode) and not (option_buttons[map[k.keycode]] as Button).disabled:
		choose(map[k.keycode])
		get_viewport().set_input_as_handled()
	elif k.keycode == KEY_ESCAPE:
		close_modal()
		get_viewport().set_input_as_handled()


# ==========================================================================
# Construcción
# ==========================================================================
func _build() -> void:
	if _built:
		return
	_built = true
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = T.OFFER_DIM
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var shade := _GradientShade.new()
	shade.name = "BottomShade"
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)

	# --- Diálogo (abajo a la izquierda) ------------------------------------
	var dialog := HBoxContainer.new()
	dialog.name = "Dialog"
	dialog.add_theme_constant_override("separation", 28)
	dialog.anchor_left = 0.0
	dialog.anchor_right = 0.62
	dialog.anchor_top = 1.0
	dialog.anchor_bottom = 1.0
	dialog.offset_left = 60
	dialog.offset_right = 0
	dialog.offset_top = -300
	dialog.offset_bottom = -50
	dialog.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(dialog)

	var portrait := _Portrait.new()
	portrait.name = "Portrait"
	portrait.custom_minimum_size = Vector2(180, 250)
	portrait.size_flags_vertical = Control.SIZE_SHRINK_END
	dialog.add_child(portrait)

	var talk := VBoxContainer.new()
	talk.name = "Talk"
	talk.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	talk.alignment = BoxContainer.ALIGNMENT_END
	talk.add_theme_constant_override("separation", 10)
	dialog.add_child(talk)

	var name_row := HBoxContainer.new()
	name_row.name = "NameRow"
	name_row.add_theme_constant_override("separation", 10)
	talk.add_child(name_row)
	npc_name_label = _label("", 24, T.TEXT, "bold")
	npc_name_label.name = "NpcName"
	name_row.add_child(npc_name_label)
	npc_role_label = _label("", 14, T.TEXT_SECONDARY)
	npc_role_label.name = "NpcRole"
	npc_role_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_row.add_child(npc_role_label)
	pioneer_badge = PanelContainer.new()
	pioneer_badge.name = "PioneerBadge"
	pioneer_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bsb := T.box(T.OFFER_GOLD_BG, 10)
	bsb.content_margin_left = 9
	bsb.content_margin_right = 9
	bsb.content_margin_top = 2
	bsb.content_margin_bottom = 2
	pioneer_badge.add_theme_stylebox_override("panel", bsb)
	pioneer_badge.add_child(_label("Eres su pionero", 12, T.OFFER_GOLD, "bold"))
	name_row.add_child(pioneer_badge)

	dialogue_label = _label("", 18, T.TEXT)
	dialogue_label.name = "Dialogue"
	dialogue_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialogue_label.custom_minimum_size.x = 420
	talk.add_child(dialogue_label)

	for opt in OPTIONS:
		var b := _option_button(opt)
		talk.add_child(b)
		option_buttons[opt["id"]] = b
	accept_button = option_buttons[DECISION_ACCEPT]
	defer_button = option_buttons[DECISION_DEFER]
	reject_button = option_buttons[DECISION_REJECT]

	status_label = _label("", 13, T.TEXT_SECONDARY)
	status_label.name = "StatusLabel"
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	talk.add_child(status_label)

	# --- Tarjeta de la oferta (arriba a la derecha) ------------------------
	offer_card = PanelContainer.new()
	offer_card.name = "OfferCard"
	var csb := T.box(T.OFFER_CARD_BG, T.OFFER_CARD_RADIUS, 2, T.OFFER_GOLD_EDGE)
	csb.set_content_margin_all(20)
	offer_card.add_theme_stylebox_override("panel", csb)
	offer_card.anchor_left = 1.0
	offer_card.anchor_right = 1.0
	offer_card.offset_left = -440
	offer_card.offset_right = -40
	offer_card.offset_top = 40
	offer_card.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	add_child(offer_card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	offer_card.add_child(col)
	col.add_child(_caps("OFERTA DE INVERSIÓN", T.OFFER_GOLD))
	offer_title_label = _label("", 20, T.TEXT, "bold")
	offer_title_label.name = "OfferTitle"
	col.add_child(offer_title_label)

	var mission := _sub_panel("Mission")
	col.add_child(mission)
	var mcol := VBoxContainer.new()
	mcol.add_theme_constant_override("separation", 5)
	mission.add_child(mcol)
	mcol.add_child(_label("Misión especial · solo para ti", 12, T.TEXT_SECONDARY))
	mission_name_label = _label("", 15, T.TEXT, "bold")
	mission_name_label.name = "MissionName"
	mcol.add_child(mission_name_label)
	mission_steps_box = VBoxContainer.new()
	mission_steps_box.name = "MissionSteps"
	mission_steps_box.add_theme_constant_override("separation", 4)
	mcol.add_child(mission_steps_box)

	var kpis := HBoxContainer.new()
	kpis.name = "Kpis"
	kpis.add_theme_constant_override("separation", 8)
	col.add_child(kpis)
	var share_box := _kpi("Tu parte", "de cada compra o venta", T.OFFER_GOLD)
	kpis.add_child(share_box)
	share_label = share_box.get_meta("value")
	var est_box := _kpi("Estimado hoy", "oro al día según tráfico", T.TEXT)
	kpis.add_child(est_box)
	estimate_label = est_box.get_meta("value")

	col.add_child(_caps("CONDICIONES CLARAS", T.TEXT_SECONDARY))
	conditions_box = VBoxContainer.new()
	conditions_box.name = "Conditions"
	conditions_box.add_theme_constant_override("separation", 6)
	col.add_child(conditions_box)
	for c in CONDITIONS:
		var l := _label("• " + c, 12, T.TEXT_KEY)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 360
		conditions_box.add_child(l)


func _refresh() -> void:
	if not _built:
		return
	npc_name_label.text = str(offer.get("npc_name", ""))
	npc_role_label.text = str(offer.get("npc_role", ""))
	dialogue_label.text = str(offer.get("dialogue", ""))
	var first := str(offer.get("npc_name", ""))
	offer_title_label.text = "Socio del puesto de %s" % first if first != "" else str(offer.get("shop_name", ""))
	var m: Dictionary = offer.get("mission", {})
	mission_name_label.text = str(m.get("name", ""))
	for c in mission_steps_box.get_children():
		mission_steps_box.remove_child(c)
		c.queue_free()
	var i := 0
	for s in m.get("steps", []):
		i += 1
		mission_steps_box.add_child(_row("Paso %d: %s" % [i, s.get("label", "")], "%d/%d" % [int(s.get("progress", 0)), int(s.get("goal", 1))]))
	if int(offer.get("fee", 0)) > 0:
		mission_steps_box.add_child(_row("Paga la cuota de socio", "%s oro" % T.format_amount(int(offer["fee"]))))
	share_label.text = share_text(float(offer.get("share", 0.0)))
	estimate_label.text = "%s–%s" % [T.format_amount(int(offer.get("estimate_min", 0))), T.format_amount(int(offer.get("estimate_max", 0)))]
	status_label.text = ""
	_set_buttons_enabled(true)


func _option_button(opt: Dictionary) -> Button:
	var b := Button.new()
	b.name = "Option_" + str(opt["id"])
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(0, 44)
	b.tooltip_text = "%s (%s)" % [opt["label"], opt["key"]]
	b.set_meta("decision", opt["id"])
	var primary: bool = opt["id"] == DECISION_ACCEPT
	var normal := T.box(T.OFFER_GOLD_BG if primary else T.OFFER_OPTION_BG, 10, 2 if primary else 1, T.OFFER_GOLD_EDGE if primary else Color(1, 1, 1, 0.06))
	var hover := T.box(T.OFFER_GOLD_BG, 10, 2, T.OFFER_GOLD_EDGE)
	var disabled := T.box(Color(T.OFFER_OPTION_BG, 0.5), 10, 1, Color(1, 1, 1, 0.04))
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("disabled", disabled)
	b.add_theme_stylebox_override("focus", T.box(Color.TRANSPARENT, 10, 2, T.OFFER_GOLD))
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 12
	row.offset_right = -14
	row.add_theme_constant_override("separation", 12)
	b.add_child(row)
	var cap := PanelContainer.new()
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var capsb := T.box(T.BUTTON_BG, 5, 1, Color(1, 1, 1, 0.14))
	capsb.content_margin_left = 6
	capsb.content_margin_right = 6
	cap.add_theme_stylebox_override("panel", capsb)
	cap.add_child(_label(str(opt["key"]), 11, T.TEXT_KEY, "bold"))
	row.add_child(cap)
	var t := _label(str(opt["text"]), 15, T.TEXT, "bold")
	t.name = "Text"
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(t)
	var h := _label(str(opt["hint"]), 12, T.OFFER_GOLD if primary else T.TEXT_SECONDARY)
	h.name = "Hint"
	h.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(h)
	var decision: String = opt["id"]
	b.pressed.connect(func() -> void: choose(decision))
	return b


func _sub_panel(node_name: String) -> PanelContainer:
	var p := PanelContainer.new()
	p.name = node_name
	var sb := T.box(T.OFFER_SUB_BG, T.OFFER_SUB_RADIUS)
	sb.set_content_margin_all(12)
	p.add_theme_stylebox_override("panel", sb)
	return p


func _kpi(title: String, sub: String, color: Color) -> PanelContainer:
	var p := _sub_panel("Kpi_" + title.replace(" ", "_"))
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	p.add_child(v)
	v.add_child(_label(title, 12, T.TEXT_SECONDARY))
	var value := _label("", 24, color, "bold")
	value.name = "Value"
	v.add_child(value)
	v.add_child(_label(sub, 11, T.TEXT_SECONDARY))
	p.set_meta("value", value)
	return p


func _row(left: String, right: String) -> HBoxContainer:
	var r := HBoxContainer.new()
	var l := _label(left, 13, T.TEXT_KEY)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(l)
	r.add_child(_label(right, 13, T.TEXT_SECONDARY))
	return r


func _caps(text: String, color: Color) -> Label:
	var l := _label(text, 11, color, "bold")
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
# Dibujo
# ==========================================================================
## Retrato en arco (silueta vectorial; el arte final del PNJ lo sustituye).
class _Portrait extends Control:
	const TK = preload("res://ui/tokens/hud_tokens.gd")

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var r := w * 0.5
		var pts := PackedVector2Array()
		pts.append(Vector2(0, h - 18))
		for i in 33:
			var a := PI + PI * float(i) / 32.0
			pts.append(Vector2(r + cos(a) * r, r + sin(a) * r))
		pts.append(Vector2(w, h - 18))
		for i in 9:
			var a := float(i) / 8.0 * PI * 0.5
			pts.append(Vector2(w - 18 + cos(a) * 18, h - 18 + sin(a) * 18))
		for i in 9:
			var a := PI * 0.5 + float(i) / 8.0 * PI * 0.5
			pts.append(Vector2(18 + cos(a) * 18, h - 18 + sin(a) * 18))
		draw_colored_polygon(pts, TK.OFFER_PORTRAIT_BG)
		var outline := pts.duplicate()
		outline.append(pts[0])
		draw_polyline(outline, Color(TK.OFFER_GOLD, 0.45), 2.0, true)
		var head := Vector2(r, h * 0.42)
		draw_arc(head, w * 0.13, 0, TAU, 40, TK.OFFER_PORTRAIT_LINE, 3.0, true)
		draw_arc(Vector2(r, h * 0.83), w * 0.24, PI * 1.05, PI * 1.95, 40, TK.OFFER_PORTRAIT_LINE, 3.0, true)


## Degradado oscuro inferior (lectura del diálogo sobre el mundo).
class _GradientShade extends Control:
	func _draw() -> void:
		var steps := 24
		var top := size.y * 0.45
		for i in steps:
			var y0 := top + (size.y - top) * float(i) / steps
			var y1 := top + (size.y - top) * float(i + 1) / steps
			draw_rect(Rect2(0, y0, size.x, y1 - y0 + 1), Color(0.02, 0.03, 0.04, 0.55 * float(i + 1) / steps))
