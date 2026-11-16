extends "res://ui/templates/BaseWindow.gd"
## Diálogo cinematográfico con PNJ — UI v2.4 Paso 13 (design_ref/pantallas_html/MMO-Dialogo.html).
##
## Modo conversación: la interfaz (HUD) se oculta y vuelve al terminar.
## - Franjas de cine negras arriba (70 px) y abajo (40 px) y degradado inferior de 540 px.
## - Retrato del interlocutor a la izquierda (220×300, arco superior, silueta).
## - Cabecera: nombre (26 px), título (15 px) y «Relación ▮▮▮▯▯ Aliada» (5 marcas).
## - Texto del nodo a 21 px / 31 px de interlineado con cursor «▍» mientras quedan fragmentos.
## - Hasta 4 opciones numeradas [1]–[4] con icono por tipo y badge de impacto (misión verde,
##   rama dorada, «Ya lo preguntaste» atenuada a 0.5, Tienda). La resaltada lleva fondo cian 12 %
##   y borde #46e3c1.
## - Chips arriba a la derecha: Historial [H] · Avanzar [Espacio] · Subtítulos: grandes.
##
## Teclado: 1–4 eligen · ↑/↓ mueven el resaltado · Enter elige el resaltado · Espacio avanza
## (revela el siguiente fragmento, continúa o cierra) · H historial · Esc cierra la conversación.
##
## El estado vive en `DialogueService` (inyectable como `service`).

const T = preload("res://ui/tokens/hud_tokens.gd")
const Kit = preload("res://ui/windows/common/CinematicKit.gd")
const DialogueServiceScript = preload("res://shared-core/DialogueService.gd")

signal option_selected(option_id: String, result: Dictionary)
signal highlight_changed(index: int)
signal shop_opened(npc_id: String, shop: Dictionary)
signal conversation_closed(npc_id: String)
signal history_toggled(visible: bool)

const SUBTITLE_SIZES := {"normal": 18, "grandes": 21, "enormes": 25}
const MODE_HINT := "Modo conversación · la interfaz se oculta y vuelve al terminar"

## Servicio inyectable (tests). Si es null se usa /root/DialogueService o uno local.
var service: Node = null
var highlighted: int = 0                 # índice 0-based de la opción resaltada
var history_visible := false
var subtitle_size := "grandes"
var stage_scale := 1.0
var last_result: Dictionary = {}
var hud_hidden := false

var stage: Control
var top_bar: ColorRect
var bottom_bar: ColorRect
var shade: Control
var portrait: Control
var name_label: Label
var title_label_npc: Label
var relation_label: Label
var relation_ticks: Array[ColorRect] = []
var relation_box: HBoxContainer
var text_label: RichTextLabel
var options_box: VBoxContainer
var option_rows: Array[Button] = []
var feedback_label: Label
var controls_row: HBoxContainer
var history_chip: PanelContainer
var advance_chip: PanelContainer
var subtitles_chip: PanelContainer
var mode_label: Label
var history_panel: PanelContainer
var history_list: VBoxContainer

var _built := false
var _hidden_huds: Array[Node] = []


func _init() -> void:
	theme = T.THEME
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	is_draggable = false


func _ready() -> void:
	window_id = "dialogue_window"
	_resolve_service()
	_build()
	super._ready()
	add_to_group("dialogue_window")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(_layout)
	visibility_changed.connect(_on_visibility_changed)
	_layout()
	refresh()
	_set_hud_hidden(visible)


## Pantalla completa: no se recoloca como una ventana normal.
func center_on_screen() -> void:
	pass


func initialize_window(params: Dictionary) -> void:
	if service == null:
		_resolve_service()
	var npc := str(params.get("npc_id", ""))
	var node_id := str(params.get("dialogue_node_id", params.get("node_id", "")))
	if npc == "":
		npc = service.active_npc if service.is_active() else "mira"
	if params.has("subtitles"):
		set_subtitle_size(str(params["subtitles"]))
	if not service.is_active() or service.active_npc != npc or node_id != "":
		start_dialogue(npc, node_id)
	else:
		refresh()


func _resolve_service() -> void:
	if service == null and is_inside_tree():
		service = get_node_or_null("/root/DialogueService")
	if service == null:
		service = DialogueServiceScript.new()
		service.name = "LocalDialogueService"
		service.load_seed()
	if service.get_parent() == null:
		add_child(service)
	for sig in ["node_changed", "fragment_advanced", "relation_changed", "history_changed"]:
		var cb := Callable(self, "_on_service_changed")
		if not service.is_connected(sig, cb):
			service.connect(sig, cb)
	if not service.is_connected("dialogue_ended", _on_dialogue_ended):
		service.dialogue_ended.connect(_on_dialogue_ended)
	if not service.is_connected("shop_requested", _on_shop_requested):
		service.shop_requested.connect(_on_shop_requested)


func _on_service_changed(_a = null, _b = null, _c = null) -> void:
	if _built:
		refresh()


# ==========================================================================
# API
# ==========================================================================
func start_dialogue(npc_id: String, node_id: String = "") -> bool:
	var ok: bool = service.start(npc_id, node_id)
	highlighted = 0
	last_result = {}
	if feedback_label:
		feedback_label.text = ""
	visible = true
	refresh()
	return ok


func options() -> Array[Dictionary]:
	return service.current_options() if service and service.is_active() else ([] as Array[Dictionary])


func set_highlight(index: int) -> void:
	var n := options().size()
	if n == 0:
		highlighted = 0
		return
	var i := clampi(index, 0, n - 1)
	if i != highlighted:
		highlighted = i
		highlight_changed.emit(i)
	_apply_option_styles()


func move_highlight(step: int) -> void:
	var n := options().size()
	if n == 0:
		return
	set_highlight(wrapi(highlighted + step, 0, n))


## Elige por número (1–4) o id de opción.
func choose(option_id_or_index) -> Dictionary:
	if not service.is_active():
		return {"ok": false, "reason": "not_active"}
	var r: Dictionary = service.choose(option_id_or_index)
	last_result = r
	if r.get("ok", false):
		highlighted = 0
		feedback_label.text = _feedback_text(r)
		option_selected.emit(str(r.get("option_id", "")), r)
	else:
		feedback_label.text = _error_text(r)
	if service.is_active():
		refresh()
	return r


func choose_highlighted() -> Dictionary:
	return choose(highlighted + 1)


## Espacio: siguiente fragmento, continuar o cerrar.
func advance() -> Dictionary:
	if not service.is_active():
		close_dialogue()
		return {"ok": true, "action": "closed"}
	var r: Dictionary = service.advance()
	if service.is_active():
		refresh()
	return r


func close_dialogue() -> void:
	if service and service.is_active():
		service.end_dialogue()   # → _on_dialogue_ended
	else:
		_finish(service.active_npc if service else "")


func toggle_history() -> void:
	history_visible = not history_visible
	history_panel.visible = history_visible
	_refresh_history()
	history_toggled.emit(history_visible)


func set_subtitle_size(size_id: String) -> void:
	if not SUBTITLE_SIZES.has(size_id):
		return
	subtitle_size = size_id
	if _built:
		text_label.add_theme_font_size_override("normal_font_size", SUBTITLE_SIZES[size_id])
		(subtitles_chip.find_child("Text", true, false) as Label).text = "Subtítulos: %s" % size_id


func cycle_subtitles() -> void:
	var keys := SUBTITLE_SIZES.keys()
	set_subtitle_size(keys[(keys.find(subtitle_size) + 1) % keys.size()])


func handle_key(keycode: int) -> bool:
	if not service:
		return false
	match keycode:
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_KP_1, KEY_KP_2, KEY_KP_3, KEY_KP_4:
			var idx := (keycode - KEY_KP_0) if keycode >= KEY_KP_0 and keycode <= KEY_KP_9 else (keycode - KEY_0)
			if idx <= options().size():
				set_highlight(idx - 1)
				choose(idx)
				return true
			return false
		KEY_UP:
			move_highlight(-1)
			return true
		KEY_DOWN:
			move_highlight(1)
			return true
		KEY_ENTER, KEY_KP_ENTER:
			if options().is_empty():
				advance()
			else:
				choose_highlighted()
			return true
		KEY_SPACE:
			advance()
			return true
		KEY_H:
			toggle_history()
			return true
		KEY_ESCAPE:
			if history_visible:
				toggle_history()
			else:
				close_dialogue()
			return true
	return false


func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not (event is InputEventKey) or not event.pressed or event.is_echo():
		return
	if handle_key((event as InputEventKey).keycode):
		get_viewport().set_input_as_handled()


func _on_dialogue_ended(npc_id: String) -> void:
	_finish(npc_id)


func _finish(npc_id: String) -> void:
	_set_hud_hidden(false)
	conversation_closed.emit(npc_id)
	if visible:
		_on_close_pressed()
		visible = false   # también fuera del orquestador (tests, escenas sueltas)


func _on_shop_requested(npc_id: String, shop: Dictionary) -> void:
	shop_opened.emit(npc_id, shop)
	var target := str(shop.get("window", ""))
	var orch := get_node_or_null("/root/UIOrchestrator") if is_inside_tree() else null
	if orch and target != "" and orch.registry and orch.registry.is_registered(target):
		orch.open_window.call_deferred(target, shop.duplicate())


func _on_visibility_changed() -> void:
	_set_hud_hidden(visible)


## «La interfaz se oculta y vuelve al terminar»: oculta los HUD activos del orquestador.
func _set_hud_hidden(on: bool) -> void:
	if on == hud_hidden or not is_inside_tree():
		return
	hud_hidden = on
	if on:
		_hidden_huds.clear()
		var orch := get_node_or_null("/root/UIOrchestrator")
		if orch and orch.registry:
			for id in ["player_hud", "party_frames"]:
				var inst = orch.registry.get_instance(id)
				if inst is CanvasItem and inst.visible:
					inst.visible = false
					_hidden_huds.append(inst)
	else:
		for n in _hidden_huds:
			if is_instance_valid(n):
				n.visible = true
		_hidden_huds.clear()


func _feedback_text(r: Dictionary) -> String:
	match str(r.get("type", "")):
		"quest":
			var q := str(r.get("reward", ""))
			return "Misión aceptada" + (" · recompensa: %s" % q if q != "" else "")
		"branch":
			var parts: Array[String] = []
			for fid in (r.get("reputation", {}) as Dictionary):
				parts.append("%s %d" % [str(service.factions.get(fid, {}).get("name", fid)), int(r["reputation"][fid])])
			return "Reputación: " + ", ".join(parts) if not parts.is_empty() else ""
		"lore":
			return "Anotado en tu Códice" if r.get("first_time", false) else ""
		"shop":
			return "Abriendo " + ("el Mercado" if bool((r.get("shop", {}) as Dictionary).get("market", false)) else "la tienda")
	return ""


func _error_text(r: Dictionary) -> String:
	match str(r.get("reason", "")):
		"relation_too_low":
			return "Tu relación aún no es suficiente para eso."
		"invalid_option":
			return ""
	return ""


# ==========================================================================
# Construcción
# ==========================================================================
func _build() -> void:
	if _built:
		return
	_built = true
	shade = _Shade.new()
	shade.name = "BottomShade"
	add_child(shade)
	top_bar = _bar("LetterboxTop")
	bottom_bar = _bar("LetterboxBottom")

	stage = Control.new()
	stage.name = "Stage"
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.size = T.CINEMA_DESIGN_SIZE
	add_child(stage)

	portrait = _Portrait.new()
	portrait.name = "Portrait"
	portrait.size = T.DIALOGUE_PORTRAIT_SIZE
	portrait.position = Vector2(160, T.CINEMA_DESIGN_SIZE.y - 120 - T.DIALOGUE_PORTRAIT_SIZE.y)
	stage.add_child(portrait)

	var box := VBoxContainer.new()
	box.name = "DialogueBox"
	box.add_theme_constant_override("separation", 14)
	box.anchor_left = 0.0
	box.anchor_right = 1.0
	box.anchor_top = 1.0
	box.anchor_bottom = 1.0
	box.offset_left = 410
	box.offset_right = -160
	box.offset_top = -120
	box.offset_bottom = -120
	box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	box.alignment = BoxContainer.ALIGNMENT_END
	stage.add_child(box)

	var head := HBoxContainer.new()
	head.name = "Header"
	head.add_theme_constant_override("separation", 12)
	box.add_child(head)
	name_label = Kit.label("", 26, T.TEXT, "bold")
	name_label.name = "NpcName"
	head.add_child(name_label)
	title_label_npc = Kit.label("", 15, T.TEXT_SECONDARY)
	title_label_npc.name = "NpcTitle"
	title_label_npc.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(title_label_npc)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(sp)
	relation_box = HBoxContainer.new()
	relation_box.name = "Relation"
	relation_box.add_theme_constant_override("separation", 8)
	relation_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(relation_box)
	relation_box.add_child(Kit.label("Relación", 13, T.TEXT_KEY))
	var ticks := HBoxContainer.new()
	ticks.name = "Ticks"
	ticks.add_theme_constant_override("separation", 3)
	ticks.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	relation_box.add_child(ticks)
	for i in DialogueServiceScript.RELATION_TICKS:
		var t := ColorRect.new()
		t.name = "Tick%d" % i
		t.custom_minimum_size = Vector2(18, 5)
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ticks.add_child(t)
		relation_ticks.append(t)
	relation_label = Kit.label("", 13, T.TEXT_KEY)
	relation_label.name = "RelationName"
	relation_box.add_child(relation_label)

	text_label = Kit.rich(T.DIALOGUE_TEXT_SIZE, T.TEXT)
	text_label.name = "Text"
	text_label.custom_minimum_size.x = 820
	text_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	text_label.add_theme_constant_override("line_separation", T.DIALOGUE_TEXT_LINE - T.DIALOGUE_TEXT_SIZE - 4)
	box.add_child(text_label)

	options_box = VBoxContainer.new()
	options_box.name = "Options"
	options_box.add_theme_constant_override("separation", 6)
	box.add_child(options_box)

	feedback_label = Kit.label("", 13, T.ACCENT_DEFAULT)
	feedback_label.name = "Feedback"
	box.add_child(feedback_label)

	# Controles (arriba a la derecha) y nota de modo (arriba a la izquierda).
	controls_row = HBoxContainer.new()
	controls_row.name = "Controls"
	controls_row.add_theme_constant_override("separation", 8)
	controls_row.anchor_left = 1.0
	controls_row.anchor_right = 1.0
	controls_row.offset_right = -40
	controls_row.offset_left = -40
	controls_row.offset_top = 90
	controls_row.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	stage.add_child(controls_row)
	history_chip = _control_chip("HistoryChip", "Historial", "H")
	advance_chip = _control_chip("AdvanceChip", "Avanzar", "Espacio")
	subtitles_chip = _control_chip("SubtitlesChip", "Subtítulos: %s" % subtitle_size, "")
	mode_label = Kit.shadow(Kit.label(MODE_HINT, 13, T.TEXT_SECONDARY))
	mode_label.name = "ModeHint"
	mode_label.position = Vector2(40, 90)
	stage.add_child(mode_label)

	history_panel = Kit.panel("HistoryPanel", Kit.box(Color(T.DEATH_CARD_BG, 0.94), 14, 1, Color(1, 1, 1, 0.07)), 14)
	history_panel.position = Vector2(1440 - 40 - 420, 132)
	history_panel.custom_minimum_size = Vector2(420, 0)
	history_panel.visible = false
	stage.add_child(history_panel)
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 6)
	history_panel.add_child(hv)
	hv.add_child(Kit.caps("Historial de la conversación"))
	history_list = VBoxContainer.new()
	history_list.name = "Lines"
	history_list.add_theme_constant_override("separation", 4)
	hv.add_child(history_list)
	set_subtitle_size(subtitle_size)


func _bar(node_name: String) -> ColorRect:
	var r := ColorRect.new()
	r.name = node_name
	r.color = Color.BLACK
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(r)
	return r


func _control_chip(node_name: String, text: String, key: String) -> PanelContainer:
	var c := Kit.chip(text, T.DIALOGUE_CHIP_BG)
	c.name = node_name
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	if key != "":
		(c.get_child(0) as HBoxContainer).add_child(Kit.kbd(key))
	controls_row.add_child(c)
	c.gui_input.connect(_on_chip_input.bind(node_name))
	return c


func _on_chip_input(ev: InputEvent, node_name: String) -> void:
	if not (ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT):
		return
	if node_name == "HistoryChip":
		toggle_history()
	elif node_name == "AdvanceChip":
		advance()
	elif node_name == "SubtitlesChip":
		cycle_subtitles()


func _layout() -> void:
	if not _built:
		return
	var area := size if size.x > 0 else get_viewport_rect().size
	stage_scale = Kit.fit_stage(stage, area)
	var s := area.y / T.CINEMA_DESIGN_SIZE.y
	top_bar.position = Vector2.ZERO
	top_bar.size = Vector2(area.x, round(T.DIALOGUE_LETTERBOX_TOP * s))
	bottom_bar.size = Vector2(area.x, round(T.DIALOGUE_LETTERBOX_BOTTOM * s))
	bottom_bar.position = Vector2(0, area.y - bottom_bar.size.y)
	shade.size = Vector2(area.x, T.DIALOGUE_SHADE_HEIGHT * s)
	shade.position = Vector2(0, area.y - shade.size.y)


# ==========================================================================
# Refresco
# ==========================================================================
func refresh() -> void:
	if not _built or service == null:
		return
	var npc: Dictionary = service.get_npc(service.active_npc)
	name_label.text = str(npc.get("name", ""))
	title_label_npc.text = str(npc.get("title", ""))
	var lit: int = service.relation_ticks(service.active_npc) if not npc.is_empty() else 0
	for i in relation_ticks.size():
		relation_ticks[i].color = T.DIALOGUE_RELATION_ON if i < lit else T.DIALOGUE_RELATION_OFF
	relation_label.text = service.relation_name(service.active_npc) if not npc.is_empty() else ""
	var txt: String = service.current_text()
	text_label.text = _escape(txt) + (" [color=#%s]▍[/color]" % T.DIALOGUE_CURSOR.to_html(false) if service.has_more_fragments() else "")
	_rebuild_options()
	if history_visible:
		_refresh_history()


func _escape(s: String) -> String:
	return s.replace("[", "[lb]")


func _rebuild_options() -> void:
	var opts := options()
	if highlighted >= opts.size():
		highlighted = maxi(0, opts.size() - 1)
	Kit.clear(options_box)
	option_rows.clear()
	for o in opts:
		var row := _option_row(o)
		options_box.add_child(row)
		option_rows.append(row)
	_apply_option_styles()


func _option_row(o: Dictionary) -> Button:
	var b := Button.new()
	b.name = "Option%d" % int(o["index"])
	b.custom_minimum_size = Vector2(0, T.DIALOGUE_OPTION_HEIGHT)
	b.focus_mode = Control.FOCUS_NONE
	b.set_meta("option_id", o["id"])
	b.set_meta("type", o["type"])
	b.set_meta("asked", o["asked"])
	b.set_meta("locked", o["locked"])
	b.tooltip_text = "%s [%s]" % [o["text"], o["key"]]
	var h := HBoxContainer.new()
	h.name = "Row"
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 14
	h.offset_right = -14
	h.add_theme_constant_override("separation", 12)
	b.add_child(h)
	var k := Kit.kbd(str(o["key"]), 22, 12)
	h.add_child(k)
	var ic = Kit.Icon.new(str(o["icon"]))
	ic.name = "Icon"
	ic.bg = Color(str(o["icon_bg"]))
	h.add_child(ic)
	var t := Kit.label(str(o["text"]), 17, T.TEXT, "semibold")
	t.name = "Text"
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	t.clip_text = true
	h.add_child(t)
	var badge := Kit.label(str(o["badge"]), 13, Color(str(o["badge_color"])))
	badge.name = "Badge"
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(badge)
	b.modulate.a = float(o["opacity"])
	var idx: int = int(o["index"])
	b.pressed.connect(func() -> void:
		set_highlight(idx - 1)
		choose(idx))
	b.mouse_entered.connect(func() -> void: set_highlight(idx - 1))
	return b


func _apply_option_styles() -> void:
	for i in option_rows.size():
		var b := option_rows[i]
		var active := i == highlighted
		var sb := Kit.box(T.DIALOGUE_OPTION_ACTIVE_BG if active else T.DIALOGUE_OPTION_BG, 12, 1.5 if active else 0.0, T.DIALOGUE_OPTION_ACTIVE_EDGE)
		if active:
			sb.shadow_color = Color(T.DIALOGUE_OPTION_ACTIVE_EDGE, 0.25)
			sb.shadow_size = 6
		for st in ["normal", "hover", "pressed", "focus"]:
			b.add_theme_stylebox_override(st, sb)
		b.set_meta("active", active)


func _refresh_history() -> void:
	Kit.clear(history_list)
	var lines: Array = service.history
	for h in lines.slice(maxi(0, lines.size() - 12)):
		var who := str(h["speaker"])
		var color := T.TEXT_KEY if h["kind"] == "npc" else (T.ACCENT_DEFAULT if h["kind"] == "player" else T.TEXT_MUTED)
		var l := Kit.label(("%s: %s" % [who, h["text"]]) if who != "" else str(h["text"]), 13, color)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 390
		history_list.add_child(l)


# ==========================================================================
# Dibujo
# ==========================================================================
## Retrato: arco superior (radio 110) y esquinas inferiores de 18 px, borde #2c3b44 y silueta.
class _Portrait extends Control:
	const TK = preload("res://ui/tokens/hud_tokens.gd")
	const SP = preload("res://ui/icons/svg_path.gd")

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func shape() -> PackedVector2Array:
		var w := size.x
		var h := size.y
		var r := w * 0.5
		var pts := PackedVector2Array()
		pts.append(Vector2(0, h - 18))
		for i in 33:
			var a := PI + PI * float(i) / 32.0
			pts.append(Vector2(r + cos(a) * r, r + sin(a) * r))
		for i in 9:
			var a := float(i) / 8.0 * PI * 0.5
			pts.append(Vector2(w - 18 + cos(a) * 18, h - 18 + sin(a) * 18))
		for i in 9:
			var a := PI * 0.5 + float(i) / 8.0 * PI * 0.5
			pts.append(Vector2(18 + cos(a) * 18, h - 18 + sin(a) * 18))
		return pts

	func _draw() -> void:
		var pts := shape()
		draw_colored_polygon(pts, TK.DIALOGUE_PORTRAIT_BG)
		var outline := pts.duplicate()
		outline.append(pts[0])
		draw_polyline(outline, TK.DIALOGUE_PORTRAIT_EDGE, 2.0, true)
		# Silueta del HTML: viewBox 48×64 dibujado a 120×160 centrado.
		var sil := Rect2((size - Vector2(120, 160)) * 0.5, Vector2(120, 160))
		var k := sil.size.x / 48.0
		draw_arc(sil.position + Vector2(24, 18) * k, 10 * k, 0, TAU, 48, TK.DIALOGUE_PORTRAIT_LINE, 1.6 * k, true)
		var body := PackedVector2Array()
		for i in 25:
			var t := float(i) / 24.0
			# Curvas cúbicas M6 62 c2-16 9-24 18-24 / s16 8 18 24
			var p: Vector2
			if t <= 0.5:
				p = _bez(Vector2(6, 62), Vector2(8, 46), Vector2(15, 38), Vector2(24, 38), t * 2.0)
			else:
				p = _bez(Vector2(24, 38), Vector2(33, 38), Vector2(40, 46), Vector2(42, 62), (t - 0.5) * 2.0)
			body.append(sil.position + p * k)
		draw_polyline(body, TK.DIALOGUE_PORTRAIT_LINE, 1.6 * k, true)

	func _bez(p0: Vector2, c1: Vector2, c2: Vector2, p3: Vector2, t: float) -> Vector2:
		var u := 1.0 - t
		return p0 * u * u * u + c1 * 3.0 * u * u * t + c2 * 3.0 * u * t * t + p3 * t * t * t


## Degradado inferior: de rgba(4,7,9,0.97) abajo (0–55 % → 0.9) a transparente arriba.
class _Shade extends Control:
	const TK = preload("res://ui/tokens/hud_tokens.gd")

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func alpha_at(y_from_bottom_ratio: float) -> float:
		var t := clampf(y_from_bottom_ratio, 0.0, 1.0)
		if t <= 0.55:
			return lerpf(0.97, 0.9, t / 0.55)
		return lerpf(0.9, 0.0, (t - 0.55) / 0.45)

	## Dos tramos lineales (0 → 55 % → 100 %) con colores por vértice: sin bandas.
	func _draw() -> void:
		var w := size.x
		var h := size.y
		var knee := h * (1.0 - 0.55)
		var c_top := Color(TK.DIALOGUE_SHADE, alpha_at(1.0))
		var c_knee := Color(TK.DIALOGUE_SHADE, alpha_at(0.55))
		var c_bot := Color(TK.DIALOGUE_SHADE, alpha_at(0.0))
		draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, knee), Vector2(0, knee)]),
			PackedColorArray([c_top, c_top, c_knee, c_knee]))
		draw_polygon(PackedVector2Array([Vector2(0, knee), Vector2(w, knee), Vector2(w, h), Vector2(0, h)]),
			PackedColorArray([c_knee, c_knee, c_bot, c_bot]))
