extends "res://ui/windows/common/EntryWindow.gd"
## Pantalla de carga táctica — UI v2.4 Paso 15 (design_ref/pantallas_html/MMO-Carga.html).
##
## - Fondo del destino con degradado inferior de 420 px a negro grafito rgba(4,7,9,0.97).
## - Arriba a la derecha: cita de lore en cursiva («El vado no se rompió…» · Diario de Mira, día 12).
## - Bloque inferior: «Destino» · «Vado Roto» (40 px) · «Verdalia · tu objetivo: …» a la izquierda;
##   tarjeta «Antes de llegar» con 3 consejos tácticos (rombos de color) al centro; chips «Mientras
##   carga» (Cambiar conjunto F1–F3 · Revisar poderes N · Tu grupo: 3/5 ya dentro) a la derecha.
## - Barra de progreso (6 px) con etapa («Cargando el terreno de Verdalia») y «72 % · unos 6 s».
##
## Teclado: H abre el refugio de bolsillo (Anexo D). Al llegar al 100 % emite `world_ready` y se
## cierra sola.

signal world_ready(destination: Dictionary)
signal pocket_shelter_requested

var shade: TextureRect
var quote_box: VBoxContainer
var quote_label: Label
var quote_source: Label
var destination_box: VBoxContainer
var destination_name: Label
var destination_sub: Label
var tips_card: PanelContainer
var tips_box: VBoxContainer
var activities_box: VBoxContainer
var progress_box: VBoxContainer
var stage_label: Label
var eta_label: Label
var progress_bar
var finished := false

var _last_dynamic := ""
var _dest_key := ""


func _screen_id() -> String:
	return "game_loading"


func _screen() -> String:
	return AuthScript.SCREEN_LOADING


func _screen_title() -> String:
	return "Cargando %s" % service.loading_destination.get("name", "")


func _service_signals() -> Array:
	return []


## params: {"destination": {...}} inicia una carga nueva; {"keep_current": true} (o sin datos con una
## carga en curso) muestra la que ya preparó `enter_world()`.
func initialize_window(params: Dictionary) -> void:
	if service == null:
		_resolve_service()
	var dest: Dictionary = params.get("destination", {})
	var keep := bool(params.get("keep_current", false))
	if not dest.is_empty() or (not keep and not service.loading_active):
		service.begin_loading(dest)
	finished = false
	visible = true
	if _built:
		refresh()


func _ready() -> void:
	super._ready()
	if not service.is_connected("loading_finished", _on_loading_finished):
		service.loading_finished.connect(_on_loading_finished)
	if service.loading_destination.is_empty():
		service.begin_loading({})
		refresh()


func _process(_delta: float) -> void:
	if _built and visible:
		_refresh_dynamic()


func open_pocket_shelter() -> void:
	pocket_shelter_requested.emit()
	var orch := _orchestrator()
	if orch != null:
		orch.open_window("shelter_pocket")


func _handle_key(code: int, _ev: InputEventKey) -> bool:
	if code == KEY_H:
		open_pocket_shelter()
		return true
	return false


func _on_loading_finished(dest: Dictionary) -> void:
	if finished:
		return
	finished = true
	_refresh_dynamic(true)
	world_ready.emit(dest)
	navigate("")


# ==========================================================================
# Construcción
# ==========================================================================
func _build() -> void:
	var s := T.LOADING_SHADE
	shade = EK.vgradient("Shade", [[0.0, Color(s, 0.0)], [0.5, Color(s, 0.85)], [1.0, Color(s, s.a)]])
	place(shade, 0, -1, 0, 0)
	shade.offset_top = -T.LOADING_SHADE_HEIGHT

	quote_box = EK.vbox("Quote", 2)
	quote_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	place(quote_box, -1, 46, 50, -1, 420)
	quote_label = Kit.shadow(Kit.label("", 16, T.ENTRY_TEXT_SOFT))
	quote_label.name = "Text"
	var it := FontVariation.new()
	it.base_font = T.font("medium")
	it.variation_transform = Transform2D(Vector2(1, 0), Vector2(0.2, 1), Vector2.ZERO)
	quote_label.add_theme_font_override("font", it)
	quote_label.set_meta("italic", true)
	quote_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	quote_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	quote_label.custom_minimum_size.x = 420
	quote_box.add_child(quote_label)
	quote_source = Kit.shadow(Kit.label("", 13, T.TEXT_SECONDARY))
	quote_source.name = "Source"
	quote_source.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	quote_box.add_child(quote_source)

	destination_box = EK.vbox("Destination", 8)
	place(destination_box, 60, -1, -1, 120, 540)
	destination_box.add_child(Kit.caps("Destino", T.ACCENT_DEFAULT))
	destination_name = Kit.shadow(Kit.label("", T.LOADING_TITLE_SIZE, T.TEXT, "bold"))
	destination_name.name = "Name"
	destination_box.add_child(destination_name)
	destination_sub = Kit.shadow(Kit.label("", 16, T.TEXT_KEY))
	destination_sub.name = "Objective"
	destination_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	destination_box.add_child(destination_sub)

	tips_card = EK.card("Tips", 18)
	place(tips_card, 620, -1, -1, 120, T.LOADING_TIPS_WIDTH)
	tips_box = EK.vbox("Body", 10)
	tips_card.add_child(tips_box)

	activities_box = EK.vbox("Activities", 8)
	place(activities_box, -1, -1, 60, 120, T.LOADING_ACTIVITIES_WIDTH)

	progress_box = EK.vbox("Progress", 8)
	place(progress_box, 60, -1, 60, 48)
	var row := EK.hbox("Row", 8)
	progress_box.add_child(row)
	stage_label = Kit.shadow(Kit.label("", 13, T.TEXT_KEY))
	stage_label.name = "Stage"
	stage_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(stage_label)
	eta_label = Kit.shadow(Kit.label("", 13, T.TEXT_KEY))
	eta_label.name = "Eta"
	row.add_child(eta_label)
	progress_bar = Kit.Bar.new(6.0)
	progress_bar.name = "Bar"
	progress_bar.track = T.LOADING_TRACK
	progress_bar.fill = T.ACCENT_DEFAULT
	progress_box.add_child(progress_bar)


# ==========================================================================
# Refresco
# ==========================================================================
func refresh() -> void:
	if not _built or service == null:
		return
	var d: Dictionary = service.loading_destination
	quote_label.text = "«%s»" % d.get("quote", "") if str(d.get("quote", "")) != "" else ""
	quote_source.text = str(d.get("quote_source", ""))
	quote_box.visible = quote_label.text != ""
	destination_name.text = str(d.get("name", ""))
	destination_sub.text = service.loading_subtitle()
	Kit.clear(tips_box)
	tips_box.add_child(Kit.caps("Antes de llegar"))
	var tips: Array = service.loading_tips()
	for i in tips.size():
		var t: Dictionary = tips[i]
		var r := EK.bullet_row("Tip_%d" % i, Color(str(t.get("color", "#46e3c1"))), str(t.get("text", "")), 14, str(t.get("shape", "diamond")) == "diamond", 8.0)
		tips_box.add_child(r)
	_rebuild_activities()
	_refresh_dynamic(true)
	apply_accessibility()


func _rebuild_activities() -> void:
	Kit.clear(activities_box)
	activities_box.add_child(Kit.shadow(Kit.caps("Mientras carga", T.TEXT_KEY)))
	var acts: Array = service.loading_activities()
	for i in acts.size():
		var a: Dictionary = acts[i]
		var chip := Kit.chip(str(a["text"]), T.LOADING_CHIP_BG)
		chip.name = "Activity_%d" % i
		chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		var h: HBoxContainer = chip.get_child(0)
		if a.has("key"):
			var kb := Kit.kbd(str(a["key"]))
			h.add_child(kb)
			chip.set_meta("key", a["key"])
		if bool(a.get("party", false)):
			var val := Kit.label(str(a["value"]), 13, Color(service.status_color("good")), "semibold")
			val.name = "Value"
			val.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			h.add_child(val)
			var suf := Kit.label(str(a["suffix"]), 13, T.TEXT_KEY)
			suf.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			h.add_child(suf)
			chip.set_meta("party", true)
		activities_box.add_child(chip)


func _refresh_dynamic(force: bool = false) -> void:
	var dk := "%s|%s" % [service.loading_destination.get("destination_id", ""), service.loading_destination.get("name", "")]
	if dk != _dest_key:
		_dest_key = dk
		if not force:
			refresh()
			return
	var key := "%d|%s|%s" % [service.loading_percent(), service.loading_eta_text(), str(service.loading_destination.get("party_inside", 0))]
	if key == _last_dynamic and not force:
		return
	var party_changed := _last_dynamic.get_slice("|", 2) != key.get_slice("|", 2)
	_last_dynamic = key
	stage_label.text = service.loading_stage_text()
	eta_label.text = service.loading_eta_text()
	progress_bar.ratio = service.loading_progress
	if party_changed and not force:
		_rebuild_activities()
		apply_accessibility()
