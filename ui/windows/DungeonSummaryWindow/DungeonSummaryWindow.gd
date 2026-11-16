extends "res://ui/templates/BaseWindow.gd"
## Resumen de mazmorra — UI v2.4 Paso 14 (design_ref/pantallas_html/MMO-Resumen.html).
##
## - Velo rgba(5,8,10,0.78) y escenario 1440×810 escalado al viewport.
## - Cabecera: «COMPLETADA» (verde), «Bóveda de Ferrum · Heroica» (34 px), chip «31:42» y chip
##   dorado «Récord del grupo».
## - 3 columnas de 600 px de alto:
##   · Tu botín (420 px): piezas con comparador de iLvl, la mejora destacada con borde cian,
##     «Equipar» / «Comparar», «Ofrecer a Toro» / «Desguazar» y materiales «Enviar al refugio» /
##     «Guardar en mochila».
##   · Momentos del grupo (460 px): un hito positivo por compañero y «Elogiar» → «Elogiado ✓».
##   · Tu progreso (420 px): nivel y XP (barra previa + ganada), afinidades (Anexo B), pista del
##     Atlas, reputación, misiones y las salidas «Repetir con el mismo grupo» (cian),
##     «Volver al refugio» y «Salir al mundo».
##
## Teclado: Enter repetir con el mismo grupo · E equipar la mejora destacada · Esc salir al mundo.
##
## El estado vive en `DungeonSummaryService` (inyectable como `service`).

const T = preload("res://ui/tokens/hud_tokens.gd")
const Kit = preload("res://ui/windows/common/CinematicKit.gd")
const SummaryServiceScript = preload("res://shared-core/DungeonSummaryService.gd")

signal exit_selected(choice: String, info: Dictionary)
signal loot_action(item_id: String, action: String, result: Dictionary)
signal comparison_shown(item_id: String, comparison: Dictionary)

## Servicio inyectable (tests). Si es null se usa /root/DungeonSummaryService o uno local.
var service: Node = null
var stage_scale := 1.0
var close_reason := ""

var veil: ColorRect
var stage: Control
var status_caps: Label
var title_main: Label
var time_chip: PanelContainer
var record_chip: PanelContainer
var loot_card: PanelContainer
var loot_box: VBoxContainer
var loot_rows: Array[PanelContainer] = []
var compare_label: Label
var moments_card: PanelContainer
var moments_box: VBoxContainer
var moment_rows: Array[PanelContainer] = []
var praise_note_label: Label
var progress_card: PanelContainer
var level_label: Label
var xp_label: Label
var xp_bar: XpBar
var affinity_box: VBoxContainer
var atlas_box: VBoxContainer
var also_box: VBoxContainer
var repeat_button: Button
var shelter_button: Button
var world_button: Button

var _built := false


func _init() -> void:
	theme = T.THEME
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	is_draggable = false


func _ready() -> void:
	window_id = "dungeon_summary"
	_resolve_service()
	_build()
	super._ready()
	add_to_group("dungeon_summary")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(_layout)
	_layout()
	refresh()


func center_on_screen() -> void:
	pass


## params: {"summary": {...}} (o el propio dict). Vacío = el resumen del seed.
func initialize_window(params: Dictionary) -> void:
	if service == null:
		_resolve_service()
	var data: Dictionary = params.get("summary", params if params.has("loot") or params.has("progress") or params.has("members") else {})
	service.present(data)
	close_reason = ""
	if compare_label:
		compare_label.visible = false
	visible = true
	refresh()


func _resolve_service() -> void:
	if service == null and is_inside_tree():
		service = get_node_or_null("/root/DungeonSummaryService")
	if service == null:
		service = SummaryServiceScript.new()
		service.name = "LocalDungeonSummaryService"
		service.load_seed()
	if service.get_parent() == null:
		add_child(service)
	if not service.is_connected("summary_changed", _on_service_changed):
		service.summary_changed.connect(_on_service_changed)
	if not service.is_connected("exit_chosen", _on_exit_chosen):
		service.exit_chosen.connect(_on_exit_chosen)


func _on_service_changed() -> void:
	if _built:
		refresh()


# ==========================================================================
# API
# ==========================================================================
func do_loot_action(item_id: String, action: String, member_id: String = "") -> Dictionary:
	var r: Dictionary = service.perform(item_id, action, member_id)
	if action == "compare" and r.get("ok", false):
		compare_label.text = "%s: %d → %d (%s)" % [_slot_name(str(r["slot"])), int(r["current"]), int(r["new"]),
			SummaryServiceScript.signed(int(r["delta"]))]
		compare_label.visible = true
		comparison_shown.emit(item_id, r)
	loot_action.emit(item_id, action, r)
	return r


func praise(member_id: String) -> Dictionary:
	return service.praise(member_id)


func choose_exit(choice: String) -> Dictionary:
	return service.choose_exit(choice)


func handle_key(keycode: int) -> bool:
	match keycode:
		KEY_ENTER, KEY_KP_ENTER:
			choose_exit(SummaryServiceScript.EXIT_REPEAT)
			return true
		KEY_E:
			var id: String = service.highlighted_item()
			if id != "":
				do_loot_action(id, "equip")
			return true
		KEY_ESCAPE:
			choose_exit(SummaryServiceScript.EXIT_WORLD)
			return true
	return false


func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not (event is InputEventKey) or not event.pressed or event.is_echo():
		return
	if handle_key((event as InputEventKey).keycode):
		get_viewport().set_input_as_handled()


func _orchestrator() -> Node:
	var orch := get_node_or_null("/root/UIOrchestrator")
	if orch != null and "window_layer" in orch and get_parent() == orch.window_layer:
		return orch
	return null


func _on_exit_chosen(choice: String, info: Dictionary) -> void:
	exit_selected.emit(choice, info)
	close_reason = choice
	if visible:
		_on_close_pressed()
		visible = false
	var orch := _orchestrator()
	if orch == null:
		return
	match choice:
		SummaryServiceScript.EXIT_REPEAT:
			if orch.has_method("open_dungeon_lobby"):
				orch.open_dungeon_lobby(str(info.get("dungeon_id", "ferrum_vault")))
		SummaryServiceScript.EXIT_SHELTER:
			orch.open_window("shelter")


static func _slot_name(slot: String) -> String:
	match slot:
		"weapon":
			return "Arma"
		"shoulders":
			return "Hombreras"
		"chest":
			return "Peto"
	return slot.capitalize()


# ==========================================================================
# Construcción
# ==========================================================================
func _build() -> void:
	if _built:
		return
	_built = true
	veil = ColorRect.new()
	veil.name = "Veil"
	veil.color = T.DUNGEON_SUMMARY_VEIL
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(veil)

	stage = Control.new()
	stage.name = "Stage"
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.size = T.CINEMA_DESIGN_SIZE
	add_child(stage)

	# Cabecera.
	var head := HBoxContainer.new()
	head.name = "HeaderBlock"
	head.add_theme_constant_override("separation", 18)
	head.position = Vector2(50, 34)
	stage.add_child(head)
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 4)
	head.add_child(hv)
	status_caps = Kit.caps("", T.DUNGEON_READY)
	status_caps.name = "Status"
	hv.add_child(status_caps)
	title_main = Kit.label("", T.DUNGEON_TITLE_SIZE, T.TEXT, "bold")
	title_main.name = "DungeonTitle"
	hv.add_child(title_main)
	time_chip = Kit.chip("", T.BUTTON_BG, T.TEXT_KEY, 30, 14)
	time_chip.name = "TimeChip"
	time_chip.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(time_chip)
	record_chip = Kit.chip("Récord del grupo", T.DUNGEON_RECORD_BG, T.DUNGEON_RECORD, 30, 14)
	record_chip.name = "RecordChip"
	record_chip.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(record_chip)

	# Columna 1 · Tu botín.
	loot_card = _column("Loot", T.DUNGEON_LOOT_X, T.DUNGEON_LOOT_WIDTH)
	var lv: VBoxContainer = loot_card.get_node("Body")
	lv.add_child(Kit.caps("Tu botín"))
	loot_box = VBoxContainer.new()
	loot_box.name = "Items"
	loot_box.add_theme_constant_override("separation", 12)
	lv.add_child(loot_box)
	compare_label = Kit.label("", 12, T.ACCENT_DEFAULT)
	compare_label.name = "Comparison"
	compare_label.visible = false
	lv.add_child(compare_label)

	# Columna 2 · Momentos del grupo.
	moments_card = _column("Moments", T.DUNGEON_MOMENTS_X, T.DUNGEON_MOMENTS_WIDTH, 10)
	var mv: VBoxContainer = moments_card.get_node("Body")
	var mh := HBoxContainer.new()
	mh.name = "Head"
	mv.add_child(mh)
	var mc := Kit.caps("Momentos del grupo")
	mc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mh.add_child(mc)
	var mn := Kit.label("", 12, T.TEXT_MUTED)
	mn.name = "Note"
	mh.add_child(mn)
	moments_box = VBoxContainer.new()
	moments_box.name = "Rows"
	moments_box.add_theme_constant_override("separation", 10)
	mv.add_child(moments_box)
	praise_note_label = Kit.label("", 12, T.TEXT_MUTED)
	praise_note_label.name = "PraiseNote"
	mv.add_child(praise_note_label)

	# Columna 3 · Tu progreso.
	progress_card = _column("Progress", T.DUNGEON_PROGRESS_X, T.DUNGEON_PROGRESS_WIDTH)
	var pv: VBoxContainer = progress_card.get_node("Body")
	pv.add_child(Kit.caps("Tu progreso"))
	var xpv := VBoxContainer.new()
	xpv.name = "Xp"
	xpv.add_theme_constant_override("separation", 5)
	pv.add_child(xpv)
	var xh := HBoxContainer.new()
	xpv.add_child(xh)
	level_label = Kit.label("", 14, T.TEXT)
	level_label.name = "Level"
	level_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	xh.add_child(level_label)
	xp_label = Kit.label("", 14, T.DUNGEON_XP_TEXT)
	xp_label.name = "XpGained"
	xh.add_child(xp_label)
	xp_bar = XpBar.new()
	xp_bar.name = "XpBar"
	xpv.add_child(xp_bar)
	var ac := Kit.caps("Afinidades que subieron")
	pv.add_child(_spaced(ac))
	affinity_box = VBoxContainer.new()
	affinity_box.name = "Affinities"
	affinity_box.add_theme_constant_override("separation", 8)
	pv.add_child(affinity_box)
	atlas_box = VBoxContainer.new()
	atlas_box.name = "Atlas"
	atlas_box.add_theme_constant_override("separation", 8)
	pv.add_child(atlas_box)
	pv.add_child(_spaced(Kit.caps("También")))
	also_box = VBoxContainer.new()
	also_box.name = "Also"
	also_box.add_theme_constant_override("separation", 8)
	pv.add_child(also_box)
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pv.add_child(fill)
	var exits := VBoxContainer.new()
	exits.name = "Exits"
	exits.add_theme_constant_override("separation", 8)
	pv.add_child(exits)
	repeat_button = _btn("Repeat", SummaryServiceScript.EXIT_LABELS[SummaryServiceScript.EXIT_REPEAT], 44)
	for st in ["normal", "hover", "pressed", "focus"]:
		repeat_button.add_theme_stylebox_override(st, Kit.box(T.DUNGEON_REPEAT if st != "hover" else T.DUNGEON_REPEAT.lightened(0.12), 10))
	for fc in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		repeat_button.add_theme_color_override(fc, T.DUNGEON_REPEAT_TEXT)
	repeat_button.pressed.connect(func() -> void: choose_exit(SummaryServiceScript.EXIT_REPEAT))
	exits.add_child(repeat_button)
	var eh := HBoxContainer.new()
	eh.add_theme_constant_override("separation", 8)
	exits.add_child(eh)
	shelter_button = _btn("Shelter", SummaryServiceScript.EXIT_LABELS[SummaryServiceScript.EXIT_SHELTER], 36)
	shelter_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shelter_button.pressed.connect(func() -> void: choose_exit(SummaryServiceScript.EXIT_SHELTER))
	eh.add_child(shelter_button)
	world_button = _btn("World", SummaryServiceScript.EXIT_LABELS[SummaryServiceScript.EXIT_WORLD], 36)
	world_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	world_button.pressed.connect(func() -> void: choose_exit(SummaryServiceScript.EXIT_WORLD))
	eh.add_child(world_button)


func _column(node_name: String, x: float, w: float, sep: int = 12) -> PanelContainer:
	var sb := Kit.box(T.DUNGEON_CARD_BG, T.DUNGEON_CARD_RADIUS, 1, T.DUNGEON_CARD_EDGE)
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 24
	sb.shadow_offset = Vector2(0, 12)
	var p := Kit.panel(node_name, sb, 20)
	p.position = Vector2(x, T.DUNGEON_COLUMN_TOP)
	p.custom_minimum_size = Vector2(w, T.DUNGEON_COLUMN_HEIGHT)
	p.size = Vector2(w, T.DUNGEON_COLUMN_HEIGHT)
	stage.add_child(p)
	var v := VBoxContainer.new()
	v.name = "Body"
	v.add_theme_constant_override("separation", sep)
	p.add_child(v)
	return p


func _spaced(c: Control) -> Control:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_top", 4)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(c)
	return m


func _btn(node_name: String, text: String, h: int) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.custom_minimum_size.y = h
	b.focus_mode = Control.FOCUS_NONE
	Kit.button_styles(b, 10)
	b.add_theme_font_override("font", T.font("semibold"))
	b.add_theme_font_size_override("font_size", 14)
	b.add_theme_color_override("font_color", T.TEXT)
	return b


## Botón con forma de chip (28 px, radio 8).
func _chip_button(node_name: String, text: String, bg: Color, fg: Color) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.custom_minimum_size.y = 28
	b.focus_mode = Control.FOCUS_NONE
	var n := Kit.box(bg, 8)
	n.content_margin_left = 10
	n.content_margin_right = 10
	b.add_theme_stylebox_override("normal", n)
	var hv := n.duplicate()
	hv.bg_color = bg.lightened(0.1) if bg.a > 0.0 else Color(1, 1, 1, 0.06)
	b.add_theme_stylebox_override("hover", hv)
	b.add_theme_stylebox_override("pressed", hv)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("disabled", n)
	b.add_theme_font_override("font", T.font("medium"))
	b.add_theme_font_size_override("font_size", 13)
	for fc in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color"]:
		b.add_theme_color_override(fc, fg)
	return b


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
	status_caps.text = str(service.status_text).to_upper()
	title_main.text = service.title_text()
	title_main.tooltip_text = service.headline()
	(time_chip.find_child("Text", true, false) as Label).text = service.completion_text()
	record_chip.visible = service.is_group_record()
	_rebuild_loot()
	_rebuild_moments()
	(moments_card.find_child("Note", true, false) as Label).text = service.moments_note
	praise_note_label.text = service.praise_note
	_refresh_progress()


func _rebuild_loot() -> void:
	Kit.clear(loot_box)
	loot_rows.clear()
	var hl: String = service.highlighted_item()
	for it in service.loot:
		var id := str(it["id"])
		var is_hl := id == hl
		var sb := Kit.box(T.DUNGEON_SUB_BG, 12, 2 if is_hl else 0, T.ACCENT_DEFAULT)
		var p := Kit.panel("Item_%s" % id, sb, 12)
		p.set_meta("item_id", id)
		p.set_meta("highlighted", is_hl)
		p.set_meta("state", it["state"])
		var v := VBoxContainer.new()
		v.name = "Body"
		v.add_theme_constant_override("separation", 8)
		p.add_child(v)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 10)
		v.add_child(h)
		var icon := Kit.panel("Icon", Kit.box(T.TEXT_DARK, 10, 2, Color(str(it["color"]))))
		icon.custom_minimum_size = Vector2(44, 44)
		h.add_child(icon)
		var nv := VBoxContainer.new()
		nv.add_theme_constant_override("separation", 0)
		nv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(nv)
		var nl := Kit.label(service.item_title(it), 15, Color(str(it["color"])), "bold")
		nl.name = "Name"
		nv.add_child(nl)
		var dl := Kit.label(service.delta_text(id), 12, Color(service.delta_color(id)))
		dl.name = "Delta"
		nv.add_child(dl)
		var hint: String = service.recipient_hint(id)
		if hint != "":
			var hl_lab := Kit.label(hint, 12, T.TEXT_KEY)
			hl_lab.name = "Hint"
			v.add_child(hl_lab)
		var acts := HBoxContainer.new()
		acts.name = "Actions"
		acts.add_theme_constant_override("separation", 6)
		v.add_child(acts)
		if it["state"] != SummaryServiceScript.ITEM_NEW:
			var sl := Kit.label(service.item_state_text(id), 13, T.DUNGEON_PRAISED, "semibold")
			sl.name = "State"
			acts.add_child(sl)
		for a in service.item_actions(id):
			var bg: Color = T.DUNGEON_REPEAT if a["primary"] and service.is_gear(it) else T.BUTTON_BG
			var fg: Color = T.DUNGEON_REPEAT_TEXT if a["primary"] and service.is_gear(it) else T.TEXT_KEY
			if a["id"] == "offer":
				fg = T.DUNGEON_OFFER_TEXT
			elif a["id"] == "shelter" or (a["primary"] and not service.is_gear(it)):
				fg = T.TEXT
			var b := _chip_button("Action_%s" % a["id"], str(a["label"]), bg, fg)
			var act := str(a["id"])
			var mid := str(a.get("member_id", ""))
			b.pressed.connect(func() -> void: do_loot_action(id, act, mid))
			acts.add_child(b)
		loot_box.add_child(p)
		loot_rows.append(p)


func _rebuild_moments() -> void:
	Kit.clear(moments_box)
	moment_rows.clear()
	for m in service.moments():
		var p := Kit.panel("Moment_%s" % m["member_id"], Kit.box(T.DUNGEON_SUB_BG, 12), 12, 10)
		p.set_meta("member_id", m["member_id"])
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 12)
		p.add_child(h)
		var av := InitialBadge.new()
		av.name = "Initial"
		av.letter = str(m["initial"])
		av.color = Color(str(m["color"]))
		h.add_child(av)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 0)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(v)
		var nl := Kit.label(str(m["name"]), 14, T.TEXT, "bold")
		nl.name = "Name"
		v.add_child(nl)
		var tl := Kit.label(str(m["text"]), 13, T.TEXT_KEY)
		tl.name = "Moment"
		v.add_child(tl)
		if not m["is_self"]:
			var done: bool = m["praised"]
			var b := _chip_button("Praise", service.praise_label(str(m["member_id"])),
				T.DUNGEON_PRAISED_BG if done else T.BUTTON_BG, T.DUNGEON_PRAISED if done else T.TEXT)
			b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			b.disabled = done
			var mid := str(m["member_id"])
			b.pressed.connect(func() -> void: praise(mid))
			h.add_child(b)
		moments_box.add_child(p)
		moment_rows.append(p)


func _refresh_progress() -> void:
	level_label.text = service.level_text()
	xp_label.text = service.xp_text()
	xp_bar.before = service.xp_before_ratio()
	xp_bar.gain = service.xp_gain_ratio()
	xp_bar.tooltip_text = "%s / %s XP" % [SummaryServiceScript.thousands(service.xp_before() + service.xp_gained()),
		SummaryServiceScript.thousands(service.xp_to_next())]
	Kit.clear(affinity_box)
	for a in service.affinities():
		var h := HBoxContainer.new()
		h.name = "Affinity_%s" % a["energy"]
		h.add_theme_constant_override("separation", 8)
		var dot := InitialBadge.new()
		dot.letter = ""
		dot.diameter = 14
		dot.color = Color(str(a["color"]))
		h.add_child(dot)
		var n := Kit.label(str(a["name"]), 14, T.TEXT)
		n.name = "Name"
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(n)
		var d := Kit.label(str(a["text"]), 14, T.DUNGEON_READY, "bold")
		d.name = "Delta"
		h.add_child(d)
		affinity_box.add_child(h)
	Kit.clear(atlas_box)
	for hint in service.atlas_hints():
		var p := Kit.panel("AtlasHint", Kit.box(T.DUNGEON_SUB_BG, 12, 1, T.DUNGEON_ATLAS_EDGE), 12, 10)
		var r := Kit.rich(13, T.TEXT_KEY)
		r.name = "Text"
		r.text = "Usaste [color=#eef2f4][b]%s[/b][/color] %d veces. Pista nueva en el Atlas." % [str(hint["combo"]), int(hint["uses"])]
		r.set_meta("plain", hint["text"])
		p.add_child(r)
		atlas_box.add_child(p)
	atlas_box.visible = atlas_box.get_child_count() > 0
	Kit.clear(also_box)
	for rep in service.reputation():
		also_box.add_child(_kv("Rep_%s" % rep["faction"], str(rep["label"]), str(rep["text"]), T.TEXT))
	for q in service.quests():
		also_box.add_child(_kv("Quest", str(q["label"]), str(q["status"]), T.DUNGEON_READY))


func _kv(node_name: String, k: String, v: String, vc: Color) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.name = node_name
	var kl := Kit.label(k, 14, T.TEXT_SECONDARY)
	kl.name = "Key"
	kl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(kl)
	var vl := Kit.label(v, 14, vc, "bold")
	vl.name = "Value"
	h.add_child(vl)
	return h


# ==========================================================================
# Controles dibujados
# ==========================================================================
## Círculo con inicial (34 px) o punto de color (afinidades, 14 px).
class InitialBadge extends Control:
	const T = preload("res://ui/tokens/hud_tokens.gd")
	var letter := ""
	var color := Color("#5aa9ff")
	var diameter := 34:
		set(v):
			diameter = v
			custom_minimum_size = Vector2(v, v)

	func _init() -> void:
		custom_minimum_size = Vector2(34, 34)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var r := minf(size.x, size.y) * 0.5
		draw_circle(size * 0.5, r, color, true, -1.0, true)
		if letter != "":
			var f := T.font("bold")
			var fs := 13
			var w := f.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var asc := f.get_ascent(fs)
			var desc := f.get_descent(fs)
			draw_string(f, Vector2((size.x - w) * 0.5, (size.y + asc - desc) * 0.5), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("#071012"))


## Barra de XP: lo que tenías (#5b4a9a) y lo ganado (#9a7bff) sobre la pista #121a20.
class XpBar extends Control:
	var before := 0.0:
		set(v):
			before = clampf(v, 0.0, 1.0)
			queue_redraw()
	var gain := 0.0:
		set(v):
			gain = clampf(v, 0.0, 1.0)
			queue_redraw()

	func _init() -> void:
		custom_minimum_size = Vector2(10, 8)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_PASS

	func _draw() -> void:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("#121a20")
		sb.set_corner_radius_all(4)
		draw_style_box(sb, Rect2(Vector2.ZERO, size))
		if before > 0.0:
			var b := StyleBoxFlat.new()
			b.bg_color = Color("#5b4a9a")
			b.set_corner_radius_all(4)
			draw_style_box(b, Rect2(0, 0, maxf(size.y, size.x * before), size.y))
		if gain > 0.0:
			draw_rect(Rect2(size.x * before, 0, size.x * minf(gain, 1.0 - before), size.y), Color("#9a7bff"))
