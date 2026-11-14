extends PanelContainer
## Refugio de bolsillo («Pocket Shelter») — UI v2.4 Paso 8, Anexo D.
## Mini-ventana de El Nido para colas, antesalas y pantallas de carga (tecla H).
## Muestra el corte lateral compacto y la «ronda de 2 minutos»: lista guiada con
## lo pendiente (recoger, decisiones de expedición, replantar, vaciar la bolsa de
## Pispa, atascos) y un estado final «Todo al día».

const T = preload("res://ui/tokens/hud_tokens.gd")
const ShelterServiceScript = preload("res://shared-core/ShelterService.gd")
const SideCutViewScript = preload("res://ui/windows/ShelterWindow/ShelterSideCutView.gd")

signal open_full_requested
signal round_action_done(item_id: String, result: Dictionary)
signal visibility_toggled(open: bool)

const POCKET_SIZE := Vector2(480, 430)

## Servicio inyectable (tests). Si es null se usa /root/ShelterService o uno local.
var service: Node = null
## En pantallas de carga / antesalas el bolsillo gestiona H él mismo.
var capture_shortcut := false

var mini_view: Control
var title_label: Label
var info_label: Label
var round_box: VBoxContainer
var round_buttons: Dictionary = {}
var open_full_button: Button
var _built := false


func _init() -> void:
	name = "ShelterPocket"
	custom_minimum_size = POCKET_SIZE
	theme = T.THEME
	var sb := T.box(Color(T.SHELTER_CARD_BG, 0.97), 16, 1, Color(T.ACCENT_DEFAULT, 0.45))
	sb.set_content_margin_all(14)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 18
	add_theme_stylebox_override("panel", sb)


func _ready() -> void:
	if service == null:
		service = get_node_or_null("/root/ShelterService")
	if service == null:
		service = ShelterServiceScript.new()
		service.name = "LocalShelterService"
		add_child(service)
	elif service.get_parent() == null:
		add_child(service)
	_build()
	if not service.shelter_changed.is_connected(refresh):
		service.shelter_changed.connect(refresh)
	refresh()


func _build() -> void:
	if _built:
		return
	_built = true
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	v.add_child(head)
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 0)
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(hv)
	title_label = _label("EL NIDO · DE BOLSILLO", 13, T.ACCENT_DEFAULT, "bold")
	hv.add_child(title_label)
	info_label = _label("", 11, T.TEXT_SECONDARY)
	hv.add_child(info_label)
	head.add_child(_keycap("H"))

	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", T.box(T.SHELTER_SKY, 12, 1, Color(1, 1, 1, 0.06)))
	v.add_child(frame)
	mini_view = SideCutViewScript.new()
	mini_view.name = "MiniSideCut"
	mini_view.service = service
	mini_view.compact = true
	mini_view.clip_contents = true
	mini_view.custom_minimum_size = Vector2(0, 190)
	mini_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(mini_view)

	var rh := HBoxContainer.new()
	v.add_child(rh)
	var cap := _label("RONDA DE 2 MINUTOS", 11, T.TEXT_SECONDARY, "bold")
	cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rh.add_child(cap)
	rh.add_child(_label("sin rachas · nada se pierde", 10, T.TEXT_MUTED))
	round_box = VBoxContainer.new()
	round_box.name = "Round"
	round_box.add_theme_constant_override("separation", 5)
	round_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(round_box)

	open_full_button = Button.new()
	open_full_button.name = "OpenFull"
	open_full_button.text = "Abrir El Nido completo"
	open_full_button.custom_minimum_size.y = 32
	open_full_button.add_theme_font_override("font", T.font("semibold"))
	open_full_button.add_theme_font_size_override("font_size", 12)
	open_full_button.add_theme_stylebox_override("normal", T.box(T.BUTTON_BG, 10, 1, T.BUTTON_BORDER))
	open_full_button.add_theme_stylebox_override("hover", T.box(T.SLOT_READY, 10, 1, T.BUTTON_BORDER))
	open_full_button.pressed.connect(func() -> void: open_full_requested.emit())
	v.add_child(open_full_button)


func refresh() -> void:
	if not _built or service == null:
		return
	var s: Dictionary = service.get_pocket_summary()
	info_label.text = "Nivel %d · Confort %d · Pispa: %s · Almacén %s" % [int(s["level"]), int(s["comfort"]), s["pispa"], s["storage"]]
	mini_view.queue_redraw()
	for c in round_box.get_children():
		round_box.remove_child(c)
		c.queue_free()
	round_buttons.clear()
	var items: Array = s["round"]
	if items.is_empty():
		var done := PanelContainer.new()
		done.name = "AllDone"
		var sb := T.box(Color(T.ACCENT_DEFAULT, 0.08), 10, 1, Color(T.ACCENT_DEFAULT, 0.6))
		sb.set_content_margin_all(12)
		done.add_theme_stylebox_override("panel", sb)
		var l := _label("Todo al día ✓  Vuelve cuando quieras: El Nido sigue solo.", 13, T.ACCENT_DEFAULT, "bold")
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		done.add_child(l)
		round_box.add_child(done)
		return
	for it in items.slice(0, 5):
		var row := PanelContainer.new()
		var rsb := T.box(T.SHELTER_SUB_BG, 9)
		rsb.content_margin_left = 10
		rsb.content_margin_right = 6
		rsb.content_margin_top = 4
		rsb.content_margin_bottom = 4
		row.add_theme_stylebox_override("panel", rsb)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 6)
		row.add_child(h)
		var col: Color = T.SHELTER_JAM if str(it["action"]) == "fix" else (T.GOLD if str(it["action"]) == "decision" else T.TEXT)
		var l2 := _label(str(it["label"]), 12, col, "semibold")
		l2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l2.clip_text = true
		h.add_child(l2)
		var id: String = it["id"]
		if str(it["action"]) == "decision":
			var run: Dictionary = service.get_run(str(it["run_id"]))
			for o in run.get("event", {}).get("options", []):
				var oid: String = o["id"]
				var ob := _small_button(str(o["label"]), bool(o.get("safe", false)))
				ob.name = "Opt_" + oid
				ob.pressed.connect(func() -> void: run_round_item(id, oid))
				h.add_child(ob)
				round_buttons[id + "/" + oid] = ob
		else:
			var verb: String = {"collect_all": "Recoger", "empty_bag": "Vaciar", "replant": "Replantar", "fix": "Arreglar"}.get(str(it["action"]), "Ir")
			var b := _small_button(verb, true)
			b.name = "Do_" + id.replace(":", "_")
			b.pressed.connect(func() -> void: run_round_item(id))
			h.add_child(b)
			round_buttons[id] = b
		round_box.add_child(row)


## Ejecuta un paso de la ronda. Para decisiones, `option_id` (vacío = opción segura).
func run_round_item(item_id: String, option_id: String = "") -> Dictionary:
	var item := {}
	for it in service.get_round_items():
		if it["id"] == item_id:
			item = it
	if item.is_empty():
		return {"ok": false, "reason": "unknown_item"}
	var res := {}
	match str(item["action"]):
		"collect_all":
			res = service.collect_all()
		"empty_bag":
			res = service.empty_pispa_bag()
		"replant":
			res = {"ok": service.replant(str(item["plot"]))}
		"fix":
			res = service.apply_fix(str(item["workshop"]), str(item["solution"]))
		"decision":
			var run: Dictionary = service.get_run(str(item["run_id"]))
			var oid: String = option_id if option_id != "" else service.safe_option(run.get("event", {}))
			res = service.resolve_decision(str(item["run_id"]), oid)
	round_action_done.emit(item_id, res)
	refresh()
	return res


func toggle() -> void:
	visible = not visible
	if visible:
		refresh()
	visibility_toggled.emit(visible)


## H sin modificadores abre/cierra el bolsillo (si `capture_shortcut`).
func handle_shortcut(event: InputEvent) -> bool:
	if not capture_shortcut or not (event is InputEventKey) or not event.pressed or event.is_echo():
		return false
	var k := event as InputEventKey
	if k.ctrl_pressed or k.alt_pressed or k.meta_pressed:
		return false
	var code := k.keycode if k.keycode != KEY_NONE else k.physical_keycode
	if code != KEY_H:
		return false
	toggle()
	return true


func _unhandled_key_input(event: InputEvent) -> void:
	if handle_shortcut(event):
		get_viewport().set_input_as_handled()


func _small_button(text: String, accent: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(0, 26)
	b.add_theme_font_override("font", T.font("semibold"))
	b.add_theme_font_size_override("font_size", 11)
	var bg: Color = T.ACCENT_DEFAULT if accent else T.BUTTON_BG
	var sb := T.box(bg, 8, 0 if accent else 1, T.BUTTON_BORDER)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	b.add_theme_stylebox_override("normal", sb)
	var hv := sb.duplicate() as StyleBoxFlat
	hv.bg_color = bg.lightened(0.12)
	b.add_theme_stylebox_override("hover", hv)
	b.add_theme_stylebox_override("pressed", hv)
	for s in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(s, T.SHELTER_PILL_TEXT if accent else T.TEXT)
	return b


func _keycap(text: String) -> PanelContainer:
	var cap := PanelContainer.new()
	var sb := T.box(T.BUTTON_BG, 5, 1, Color(1, 1, 1, 0.14))
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	cap.add_theme_stylebox_override("panel", sb)
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cap.add_child(_label(text, 11, T.TEXT_KEY, "bold"))
	return cap


func _label(text: String, font_size: int, color: Color, weight: String = "medium") -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", T.font(weight))
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
