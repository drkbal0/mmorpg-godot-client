extends "res://ui/templates/BaseWindow.gd"
## Muerte y reaparición con recap táctico — UI v2.4 Paso 13 (design_ref/pantallas_html/MMO-Muerte.html).
##
## - Filtro del mundo: escala de grises y brillo 0.55 (`grayscale(1) brightness(0.55)`) + velo.
## - Título central «Has caído» (48 px, sombra profunda) y «El combate sigue · tu grupo aún puede ganar».
## - Tarjeta «Últimos 5 segundos»: impactos con tiempo relativo, importe en rojo, barra de daño,
##   chip ámbar «evitable» y caja de consejo táctico con borde cian.
## - Columna derecha: tarjeta «Brisa te está resucitando» (barra y «Listo en 1,6 s · aceptar
##   automáticamente ✓»), «Reaparecer en el punto de control 0:12», «Ver repetición de 10 s [R]»
##   y la nota «Sin penalización de equipo…».
##
## Teclado: R repetición · Enter acepta la resurrección (si espera) o reaparece (si ya puede) ·
## A alterna la aceptación automática · Esc oculta/muestra el recap para mirar el combate.
##
## El estado vive en `DeathRecapService` (inyectable como `service`).

const T = preload("res://ui/tokens/hud_tokens.gd")
const Kit = preload("res://ui/windows/common/CinematicKit.gd")
const DeathRecapServiceScript = preload("res://shared-core/DeathRecapService.gd")
const GrayscaleShader = preload("res://shaders/death_grayscale.gdshader")

signal replay_opened(seconds: float, events: Array)
signal respawn_chosen(result: Dictionary)
signal resurrection_accepted(caster: String)
signal recap_toggled(visible: bool)
signal death_screen_closed(reason: String)

const BULB_ICON := "M9 18h6M10 21h4M12 3a6 6 0 0 0-4 10.5c.7.7 1 1.5 1 2.5h6c0-1 .3-1.8 1-2.5A6 6 0 0 0 12 3"

## Servicio inyectable (tests). Si es null se usa /root/DeathRecapService o uno local.
var service: Node = null
var recap_visible := true
var stage_scale := 1.0
var close_reason := ""

var filter_rect: ColorRect
var stage: Control
var title_box: VBoxContainer
var title_text: Label
var subtitle_label: Label
var recap_card: PanelContainer
var recap_caps: Label
var events_box: VBoxContainer
var event_rows: Array[Control] = []
var tip_panel: PanelContainer
var tip_label: RichTextLabel
var options_col: VBoxContainer
var res_card: PanelContainer
var res_title: Label
var res_bar
var res_text: Label
var res_accept_button: Button
var respawn_button: Button
var respawn_time: Label
var replay_button: Button
var note_label: Label
var replay_label: Label

var _built := false
var _last_dynamic := ""


func _init() -> void:
	theme = T.THEME
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	is_draggable = false


func _ready() -> void:
	window_id = "death_window"
	_resolve_service()
	_build()
	super._ready()
	add_to_group("death_window")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(_layout)
	_layout()
	if service.state != DeathRecapServiceScript.STATE_DEAD:
		service.present()
	refresh()


func center_on_screen() -> void:
	pass


## params: {"recap": {...}} (o el propio dict de recap). Vacío = recap actual o el del seed.
func initialize_window(params: Dictionary) -> void:
	if service == null:
		_resolve_service()
	var data: Dictionary = params.get("recap", params if params.has("events") else {})
	service.present(data)
	recap_visible = true
	close_reason = ""
	visible = true
	refresh()


func _resolve_service() -> void:
	if service == null and is_inside_tree():
		service = get_node_or_null("/root/DeathRecapService")
	if service == null:
		service = DeathRecapServiceScript.new()
		service.name = "LocalDeathRecapService"
		service.load_seed()
	if service.get_parent() == null:
		add_child(service)
	for sig in ["died", "recap_changed", "resurrection_started", "resurrection_cancelled", "resurrection_ready", "respawn_ready", "auto_accept_changed"]:
		var cb := Callable(self, "_on_service_changed")
		if not service.is_connected(sig, cb):
			service.connect(sig, cb)
	if not service.is_connected("resurrected", _on_resurrected):
		service.resurrected.connect(_on_resurrected)
	if not service.is_connected("respawned", _on_respawned):
		service.respawned.connect(_on_respawned)


func _on_service_changed(_a = null, _b = null) -> void:
	if _built:
		refresh()


func _process(_delta: float) -> void:
	if _built and visible:
		_refresh_dynamic()


# ==========================================================================
# API
# ==========================================================================
func respawn() -> Dictionary:
	var r: Dictionary = service.respawn()
	respawn_chosen.emit(r)
	if not r.get("ok", false):
		_refresh_dynamic(true)
	return r


func open_replay() -> Dictionary:
	var r: Dictionary = service.request_replay()
	if r.get("ok", false):
		replay_label.text = "Repetición: %d impactos en %s s" % [(r["events"] as Array).size(), DeathRecapServiceScript._num(float(r["seconds"]))]
		replay_label.visible = true
		replay_opened.emit(float(r["seconds"]), r["events"])
	return r


func accept_resurrection() -> Dictionary:
	return service.accept_resurrection()


func toggle_auto_accept() -> void:
	service.set_auto_accept(not bool(service.resurrection.get("auto_accept", false)))
	refresh()


func set_recap_visible(on: bool) -> void:
	recap_visible = on
	recap_card.visible = on
	recap_toggled.emit(on)


func handle_key(keycode: int) -> bool:
	match keycode:
		KEY_R:
			open_replay()
			return true
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			if service.resurrection_state() == DeathRecapServiceScript.RES_READY:
				accept_resurrection()
			else:
				respawn()
			return true
		KEY_A:
			toggle_auto_accept()
			return true
		KEY_ESCAPE:
			set_recap_visible(not recap_visible)
			return true
	return false


func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not (event is InputEventKey) or not event.pressed or event.is_echo():
		return
	if handle_key((event as InputEventKey).keycode):
		get_viewport().set_input_as_handled()


func _on_resurrected(caster: String) -> void:
	resurrection_accepted.emit(caster)
	_close("resurrected")


func _on_respawned(_point: String) -> void:
	_close("respawned")


func _close(reason: String) -> void:
	close_reason = reason
	death_screen_closed.emit(reason)
	if visible:
		_on_close_pressed()
		visible = false


# ==========================================================================
# Construcción
# ==========================================================================
func _build() -> void:
	if _built:
		return
	_built = true
	filter_rect = ColorRect.new()
	filter_rect.name = "GrayscaleFilter"
	filter_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	filter_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var mat := ShaderMaterial.new()
	mat.shader = GrayscaleShader
	mat.set_shader_parameter("grayscale", 1.0)
	mat.set_shader_parameter("brightness", T.DEATH_BRIGHTNESS)
	mat.set_shader_parameter("tint", T.DEATH_TINT)
	filter_rect.material = mat
	add_child(filter_rect)

	stage = Control.new()
	stage.name = "Stage"
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.size = T.CINEMA_DESIGN_SIZE
	add_child(stage)

	# Título central.
	title_box = VBoxContainer.new()
	title_box.name = "Title"
	title_box.add_theme_constant_override("separation", 6)
	title_box.position = Vector2(0, 90)
	title_box.size = Vector2(T.CINEMA_DESIGN_SIZE.x, 0)
	stage.add_child(title_box)
	title_text = Kit.shadow(Kit.label("", T.DEATH_TITLE_SIZE, T.TEXT, "bold"), 8)
	title_text.name = "TitleText"
	title_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var tv := FontVariation.new()
	tv.base_font = T.font("bold")
	tv.spacing_glyph = 2
	title_text.add_theme_font_override("font", tv)
	title_box.add_child(title_text)
	subtitle_label = Kit.shadow(Kit.label("", 16, T.TEXT_KEY))
	subtitle_label.name = "Subtitle"
	subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_box.add_child(subtitle_label)

	# Tarjeta «Últimos 5 segundos».
	var csb := Kit.box(T.DEATH_CARD_BG, 18, 1, Color(1, 1, 1, 0.07))
	csb.shadow_color = Color(0, 0, 0, 0.45)
	csb.shadow_size = 24
	csb.shadow_offset = Vector2(0, 12)
	recap_card = Kit.panel("RecapCard", csb, 20)
	recap_card.position = Vector2(330, 220)
	recap_card.custom_minimum_size = Vector2(460, 0)
	recap_card.size = Vector2(460, 0)
	stage.add_child(recap_card)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 12)
	recap_card.add_child(rv)
	recap_caps = Kit.caps("Últimos 5 segundos")
	recap_caps.name = "Caps"
	rv.add_child(recap_caps)
	events_box = VBoxContainer.new()
	events_box.name = "Events"
	events_box.add_theme_constant_override("separation", 12)
	rv.add_child(events_box)
	tip_panel = Kit.panel("TipBox", Kit.box(T.DEATH_SUB_BG, 12, 1, T.DEATH_TIP_EDGE), 14, 12)
	rv.add_child(tip_panel)
	var th := HBoxContainer.new()
	th.add_theme_constant_override("separation", 10)
	tip_panel.add_child(th)
	var bulb = Kit.Icon.new(BULB_ICON, Vector2(20, 20))
	bulb.name = "Bulb"
	bulb.stroke = T.ACCENT_DEFAULT
	bulb.icon_size = 20
	bulb.width = 2.0
	bulb.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	th.add_child(bulb)
	tip_label = Kit.rich(14, T.TEXT_KEY)
	tip_label.name = "TipText"
	tip_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tip_label.add_theme_constant_override("line_separation", 4)
	th.add_child(tip_label)

	# Columna de opciones.
	options_col = VBoxContainer.new()
	options_col.name = "Options"
	options_col.add_theme_constant_override("separation", 10)
	options_col.position = Vector2(810, 220)
	options_col.custom_minimum_size = Vector2(300, 0)
	options_col.size = Vector2(300, 0)
	stage.add_child(options_col)
	var rsb := Kit.box(T.DEATH_CARD_BG, 18, 1.5, T.DEATH_RES_EDGE)
	rsb.shadow_color = Color(0, 0, 0, 0.45)
	rsb.shadow_size = 24
	rsb.shadow_offset = Vector2(0, 12)
	res_card = Kit.panel("ResurrectionCard", rsb, 16)
	options_col.add_child(res_card)
	var resv := VBoxContainer.new()
	resv.add_theme_constant_override("separation", 8)
	res_card.add_child(resv)
	res_title = Kit.label("", 16, T.TEXT, "bold")
	res_title.name = "ResTitle"
	resv.add_child(res_title)
	res_bar = Kit.Bar.new(8.0)
	res_bar.name = "ResBar"
	res_bar.fill = T.ACCENT_DEFAULT
	res_bar.track = T.DEATH_SUB_BG
	resv.add_child(res_bar)
	res_text = Kit.label("", 13, T.TEXT_SECONDARY)
	res_text.name = "ResText"
	res_text.tooltip_text = "Pulsa (o [A]) para alternar la aceptación automática"
	res_text.mouse_filter = Control.MOUSE_FILTER_STOP
	res_text.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			toggle_auto_accept())
	resv.add_child(res_text)
	var ra := HBoxContainer.new()
	ra.add_theme_constant_override("separation", 8)
	resv.add_child(ra)
	res_accept_button = Button.new()
	res_accept_button.name = "Accept"
	res_accept_button.text = "Aceptar [Enter]"
	res_accept_button.custom_minimum_size = Vector2(0, 32)
	Kit.button_styles(res_accept_button, 8)
	res_accept_button.add_theme_color_override("font_color", T.ACCENT_DEFAULT)
	res_accept_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	res_accept_button.pressed.connect(accept_resurrection)
	res_accept_button.visible = false
	ra.add_child(res_accept_button)

	respawn_button = Kit.split_button("Respawn", "")
	respawn_time = Kit.label("", 14, T.TEXT_SECONDARY, "semibold")
	respawn_time.name = "Time"
	respawn_time.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	respawn_button.get_node("Row").add_child(respawn_time)
	respawn_button.pressed.connect(respawn)
	options_col.add_child(respawn_button)

	replay_button = Kit.split_button("Replay", "")
	replay_button.get_node("Row").add_child(Kit.kbd("R"))
	replay_button.pressed.connect(open_replay)
	options_col.add_child(replay_button)

	replay_label = Kit.label("", 12, T.ACCENT_DEFAULT)
	replay_label.name = "ReplayStatus"
	replay_label.visible = false
	options_col.add_child(replay_label)

	var nm := MarginContainer.new()
	nm.add_theme_constant_override("margin_left", 4)
	nm.add_theme_constant_override("margin_right", 4)
	options_col.add_child(nm)
	note_label = Kit.label("", 12, T.TEXT_SECONDARY)
	note_label.name = "Note"
	note_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note_label.custom_minimum_size.x = 292
	nm.add_child(note_label)


func _layout() -> void:
	if not _built:
		return
	var area := size if size.x > 0 else get_viewport_rect().size
	stage_scale = Kit.fit_stage(stage, area)


# ==========================================================================
# Refresco
# ==========================================================================
func refresh() -> void:
	if not _built or service == null:
		return
	var r: Dictionary = service.recap
	title_text.text = str(r.get("title", service.title))
	subtitle_label.text = str(r.get("subtitle", service.subtitle))
	recap_caps.text = ("Últimos %s segundos" % DeathRecapServiceScript._num(float(r.get("window_s", service.window_s)))).to_upper()
	_rebuild_events(r.get("events", []))
	tip_label.text = tip_bbcode(r.get("tip", {}))
	tip_panel.visible = not (r.get("tip", {}) as Dictionary).is_empty()
	(respawn_button.find_child("Text", true, false) as Label).text = service.respawn_label()
	(replay_button.find_child("Text", true, false) as Label).text = service.replay_label()
	note_label.text = str(r.get("note", service.note))
	recap_card.visible = recap_visible
	_refresh_dynamic(true)


static func tip_bbcode(tip: Dictionary) -> String:
	var out := ""
	for s in tip.get("segments", []):
		if s.has("key"):
			out += "[bgcolor=#18242b][color=#dbe4ea][b] %s [/b][/color][/bgcolor]" % str(s["key"])
		else:
			out += str(s["text"]).replace("[", "[lb]")
	return out


func _rebuild_events(evs: Array) -> void:
	Kit.clear(events_box)
	event_rows.clear()
	for e in evs:
		var v := VBoxContainer.new()
		v.name = "Event%d" % event_rows.size()
		v.add_theme_constant_override("separation", 4)
		v.set_meta("avoidable", e["avoidable"])
		v.set_meta("ability", e["ability"])
		var h := HBoxContainer.new()
		h.name = "Row"
		h.add_theme_constant_override("separation", 10)
		v.add_child(h)
		var t := Kit.label(str(e["time_text"]), 12, T.TEXT_MUTED)
		t.name = "Time"
		t.custom_minimum_size.x = 40
		h.add_child(t)
		var n := Kit.label(str(e["label"]), 15, T.TEXT, "semibold")
		n.name = "Name"
		h.add_child(n)
		if e["avoidable"]:
			var c := Kit.chip("evitable", T.DEATH_AVOIDABLE_BG, T.DEATH_AVOIDABLE, 20, 11)
			c.name = "Avoidable"
			c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			h.add_child(c)
		var sp := Control.new()
		sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(sp)
		var a := Kit.label(str(e["amount_text"]), 15, T.DEATH_DAMAGE, "bold")
		a.name = "Amount"
		h.add_child(a)
		var bm := MarginContainer.new()
		bm.add_theme_constant_override("margin_left", 50)
		v.add_child(bm)
		var bar = Kit.Bar.new(5.0)
		bar.name = "Bar"
		bar.fill = T.DEATH_BAR
		bar.track = T.DEATH_SUB_BG
		bar.ratio = float(e["bar_ratio"])
		bar.tooltip_text = "%d %% del daño recibido" % roundi(float(e["percent"]))
		bm.add_child(bar)
		events_box.add_child(v)
		event_rows.append(v)


func _refresh_dynamic(force: bool = false) -> void:
	var rs: String = service.resurrection_state()
	var key := "%s|%.2f|%s|%s|%s" % [rs, service.resurrection_remaining(), service.respawn_countdown_text(), service.state, str(service.resurrection.get("auto_accept", false))]
	if key == _last_dynamic and not force:
		return
	_last_dynamic = key
	res_card.visible = rs != DeathRecapServiceScript.RES_NONE
	res_title.text = service.resurrection_title()
	res_bar.ratio = service.resurrection_progress()
	res_text.text = service.resurrection_text()
	var casting: bool = rs == DeathRecapServiceScript.RES_CASTING
	res_bar.fill = T.ACCENT_DEFAULT if casting or rs == DeathRecapServiceScript.RES_READY or rs == DeathRecapServiceScript.RES_ACCEPTED else T.TEXT_MUTED
	res_accept_button.visible = rs == DeathRecapServiceScript.RES_READY
	respawn_time.text = service.respawn_countdown_text()
	respawn_button.disabled = not service.can_respawn()
	respawn_time.add_theme_color_override("font_color", T.ACCENT_DEFAULT if service.can_respawn() else T.TEXT_SECONDARY)
