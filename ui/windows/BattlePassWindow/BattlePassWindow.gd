extends "res://ui/windows/common/MenuWindow.gd"
## Comercio › Pase de batalla — EN CONSTRUCCIÓN (UI v2.4 Paso 9 · §2.2 · MMO-Pase.html).
##
## Franja diagonal «EN CONSTRUCCIÓN» + estructura completa dirigida por datos:
## 50 niveles con pista gratuita y pista del pase, hitos destacados (cada 5 niveles),
## barra de XP, desafíos semanales y tabla de XP por actividad. La XP se gana con
## CUALQUIER actividad (también refugio y expediciones) y lo ganado no caduca.
## Estado en `CommerceService`.

const ConstructionBanner = preload("res://ui/components/base/under_construction_banner.gd")

signal reward_claimed(level: int, track: String, result: Dictionary)

const MENU_TAB_ID := "comercio"
const SUBTAB_ID := "pase"
const PASS_COLOR := Color("#c39bff")
const CELL_SIZE := Vector2(100, 84)

var banner: Control
var level_label: Label
var xp_label: Label
var xp_bar: Bar
var season_label: Label
var days_label: Label
var track_scroll: ScrollContainer
var track_row: HBoxContainer
var level_columns: Dictionary = {}   # level -> VBoxContainer
var free_cells: Dictionary = {}      # level -> Button
var premium_cells: Dictionary = {}   # level -> Button
var challenges_box: VBoxContainer
var activity_box: GridContainer
var unlock_button: Button
var feedback_label: Label

var _built := false


func _ready() -> void:
	window_id = "battle_pass_window"
	_resolve_commerce()
	_build()
	super._ready()
	connect_menu_bar()
	for sig in ["pass_xp_gained", "pass_reward_claimed"]:
		var cb := Callable(self, "_on_pass_changed")
		if not commerce.is_connected(sig, cb):
			commerce.connect(sig, cb)
	refresh()
	scroll_to_level.call_deferred(int(commerce.level))


func _on_pass_changed(_a = null, _b = null, _c = null) -> void:
	refresh()


func _build() -> void:
	if _built:
		return
	_built = true
	var col := build_frame(MENU_TAB_ID, SUBTAB_ID)
	var header := _hbox(14)
	header.name = "Header"
	col.add_child(header)
	header.add_child(_commerce_subnav(SUBTAB_ID))
	var title := _label("Pase de batalla", 1, Color.TRANSPARENT)
	title.name = "TitleLabel"
	title.visible = false
	header.add_child(title)
	banner = ConstructionBanner.new()
	banner.name = "ConstructionBanner"
	banner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	banner.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	banner.message = str(commerce.pass_banner)
	header.add_child(banner)

	var card := _card("PassCard", 22)
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(card)
	var v := _vbox(12)
	card.add_child(v)

	var top := _hbox(16)
	v.add_child(top)
	var tl := _vbox(2)
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(tl)
	season_label = _caps("PASE DE BATALLA · TEMPORADA 1", PASS_COLOR)
	season_label.name = "Season"
	tl.add_child(season_label)
	var nh := _hbox(10)
	tl.add_child(nh)
	nh.add_child(_label(str(commerce.season_name), 24, T.TEXT, "bold"))
	days_label = _label("", 13, T.TEXT_SECONDARY)
	days_label.size_flags_vertical = Control.SIZE_SHRINK_END
	nh.add_child(days_label)
	var tr := _vbox(6)
	tr.custom_minimum_size.x = 360
	top.add_child(tr)
	var lh := _hbox(6)
	tr.add_child(lh)
	level_label = _label("Nivel 1", 14, T.TEXT, "bold")
	level_label.name = "Level"
	level_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lh.add_child(level_label)
	xp_label = _label("", 12, T.TEXT_SECONDARY)
	xp_label.name = "XP"
	lh.add_child(xp_label)
	xp_bar = _bar(0.0, PASS_COLOR, 7)
	xp_bar.name = "XPBar"
	tr.add_child(xp_bar)

	var track := _hbox(10)
	v.add_child(track)
	var labels := _vbox(6)
	labels.custom_minimum_size.x = 70
	track.add_child(labels)
	labels.add_child(_label("Nivel", 12, T.TEXT_SECONDARY))
	var gl := _label("Gratis", 13, T.TEXT, "bold")
	gl.custom_minimum_size.y = CELL_SIZE.y
	gl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	labels.add_child(gl)
	var pl := _label("Pase", 13, PASS_COLOR, "bold")
	pl.custom_minimum_size.y = CELL_SIZE.y
	pl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	labels.add_child(pl)
	track_scroll = ScrollContainer.new()
	track_scroll.name = "TrackScroll"
	track_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	track_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	track_scroll.custom_minimum_size.y = CELL_SIZE.y * 2 + 40
	track.add_child(track_scroll)
	track_row = _hbox(8)
	track_row.name = "Track"
	track_scroll.add_child(track_row)

	var bottom := _hbox(16)
	bottom.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(bottom)
	var left := _vbox(8)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(left)
	left.add_child(_caps("DESAFÍOS DE LA SEMANA"))
	challenges_box = _vbox(6)
	challenges_box.name = "Challenges"
	left.add_child(challenges_box)
	left.add_child(_caps("XP POR ACTIVIDAD · CUALQUIER COSA CUENTA"))
	activity_box = GridContainer.new()
	activity_box.name = "ActivityXP"
	activity_box.columns = 4
	activity_box.add_theme_constant_override("h_separation", 14)
	activity_box.add_theme_constant_override("v_separation", 2)
	left.add_child(activity_box)

	var note := _card("PolicyNote", 14, Color(0, 0, 0, 0), Color(T.GOLD, 0.55), 14)
	note.custom_minimum_size.x = 440
	bottom.add_child(note)
	var nv := _vbox(8)
	note.add_child(nv)
	nv.add_child(_caps("POR VALIDAR CON EL ROADMAP", T.GOLD))
	var pol := _wrap_label(str(commerce.pass_policy), 12, T.TEXT_KEY)
	pol.name = "Policy"
	nv.add_child(pol)
	nv.add_child(_spacer(Vector2.ZERO, false, true))
	feedback_label = _label("", 11, T.TEXT_SECONDARY)
	feedback_label.name = "Feedback"
	feedback_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nv.add_child(feedback_label)
	unlock_button = _ghost_button("Desbloquear el pase")
	unlock_button.name = "UnlockButton"
	unlock_button.pressed.connect(_on_unlock)
	nv.add_child(unlock_button)


# ==========================================================================
# API
# ==========================================================================
func claim(level: int, track: String = "free") -> Dictionary:
	var r: Dictionary = commerce.claim_reward(level, track)
	match str(r.get("reason", "")):
		"":
			feedback_label.text = "Recompensa reclamada: %s. Es tuya para siempre." % r.get("reward", "")
		"level_not_reached":
			feedback_label.text = "Llega al nivel %d para reclamarla." % level
		"premium_locked":
			feedback_label.text = "La pista del pase se desbloquea con Prismas (en construcción)."
		"already_claimed":
			feedback_label.text = "Ya la reclamaste."
	reward_claimed.emit(level, track, r)
	refresh()
	return r


func _on_unlock() -> void:
	var r: Dictionary = commerce.unlock_premium()
	feedback_label.text = "El pase está en construcción: precio en Prismas por definir." if r.get("reason", "") == "under_construction" else ("Pase desbloqueado." if r.get("ok", false) else "No se pudo desbloquear.")


func scroll_to_level(level: int) -> void:
	if not level_columns.has(level) or track_scroll == null:
		return
	# Posición calculada (no depende de que el contenedor ya se haya maquetado).
	var step := CELL_SIZE.x + float(track_row.get_theme_constant("separation"))
	var x := maxf(0.0, (level - 1) * step - step * 4.0)
	_set_scroll(x)


## Fija el desplazamiento aunque la pista se acabe de reconstruir (sin maquetar aún,
## el ScrollContainer recortaría el valor a 0).
func _set_scroll(x: float) -> void:
	var bar := track_scroll.get_h_scroll_bar()
	bar.max_value = maxf(bar.max_value, x + track_scroll.size.x)
	track_scroll.scroll_horizontal = int(x)


# ==========================================================================
# Refresco
# ==========================================================================
func refresh() -> void:
	if not _built:
		return
	season_label.text = "PASE DE BATALLA · TEMPORADA %d" % int(commerce.season)
	days_label.text = "%d días restantes" % int(commerce.days_left)
	level_label.text = "Nivel %d" % int(commerce.level)
	xp_label.text = "%s / %s XP del pase" % [fmt(int(commerce.xp)), fmt(int(commerce.xp_per_level))]
	xp_bar.ratio = commerce.pass_ratio()
	unlock_button.text = "Desbloquear el pase · %s Prismas" % (fmt(int(commerce.premium_price)) if int(commerce.premium_price) > 0 else "—")
	var keep_scroll := track_scroll.scroll_horizontal
	_clear(track_row)
	level_columns.clear()
	free_cells.clear()
	premium_cells.clear()
	for lv in commerce.get_pass_levels():
		track_row.add_child(_level_column(lv))
	_set_scroll(keep_scroll)
	_clear(challenges_box)
	for c in commerce.challenges:
		var row := _sub_card("Challenge", 10)
		challenges_box.add_child(row)
		var h := _hbox(10)
		row.add_child(h)
		var l := _label(str(c["label"]), 12, T.TEXT)
		l.custom_minimum_size.x = 250
		h.add_child(l)
		h.add_child(_bar(float(c["progress"]) / maxf(1.0, float(c["goal"])), PASS_COLOR, 5))
		h.add_child(_label("%d/%d · +%s XP" % [int(c["progress"]), int(c["goal"]), fmt(int(c["xp"]))], 11, T.TEXT_SECONDARY))
	_clear(activity_box)
	var acts: Dictionary = commerce.activity_xp
	for k in acts:
		if k == "default":
			continue
		activity_box.add_child(_label("%s +%d" % [str(k).capitalize(), int(acts[k])], 11, T.TEXT_KEY))
	activity_box.add_child(_label("Otra cosa +%d" % int(acts.get("default", 0)), 11, T.TEXT_KEY))


func _level_column(lv: Dictionary) -> VBoxContainer:
	var l := int(lv["level"])
	var current := l == int(commerce.level)
	var col := _vbox(6)
	col.name = "Level_%d" % l
	var num := _label(str(l), 13, PASS_COLOR if current else (T.GOLD if lv["milestone"] else T.TEXT_KEY), "bold")
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(num)
	var f := _cell(lv, "free", current)
	col.add_child(f)
	var p := _cell(lv, "premium", current)
	col.add_child(p)
	level_columns[l] = col
	free_cells[l] = f
	premium_cells[l] = p
	return col


func _cell(lv: Dictionary, track: String, current: bool) -> Button:
	var l := int(lv["level"])
	var premium := track == "premium"
	var claimed: bool = lv["claimed_premium"] if premium else lv["claimed_free"]
	var reached: bool = lv["reached"]
	var milestone: bool = lv["milestone"]
	var b := Button.new()
	b.name = ("Premium_%d" if premium else "Free_%d") % l
	b.custom_minimum_size = CELL_SIZE
	b.focus_mode = Control.FOCUS_ALL
	b.clip_text = true
	var bg := Color("#160f22") if premium else Color("#0f151a")
	var border := Color(1, 1, 1, 0.07)
	if milestone:
		border = Color(T.GOLD, 0.55)
	if current:
		border = PASS_COLOR
	var sb := T.box(bg, 10, 2 if current or milestone else 1, border)
	sb.set_content_margin_all(6)
	b.add_theme_stylebox_override("normal", sb)
	var hv := sb.duplicate() as StyleBoxFlat
	hv.bg_color = bg.lightened(0.06)
	b.add_theme_stylebox_override("hover", hv)
	b.add_theme_stylebox_override("pressed", hv)
	b.add_theme_stylebox_override("focus", T.box(Color.TRANSPARENT, 10, 1, T.ACCENT_DEFAULT))
	b.tooltip_text = "%s · nivel %d%s" % [lv[track], l, " · hito" if milestone else ""]
	var v := _vbox(2)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 6
	v.offset_right = -6
	v.offset_top = 6
	v.offset_bottom = -6
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	b.add_child(v)
	var icon := _label("✓" if claimed else ("★" if milestone else "◆"), 16 if milestone else 12, T.DELTA_UP if claimed else (T.GOLD if milestone else (PASS_COLOR if premium else T.TEXT_MUTED)), "bold")
	icon.name = "Icon"
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(icon)
	var txt := _label(str(lv[track]), 9, T.TEXT_KEY if reached else T.TEXT_MUTED, "semibold")
	txt.name = "Reward"
	txt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	txt.custom_minimum_size.x = CELL_SIZE.x - 12
	txt.max_lines_visible = 3
	v.add_child(txt)
	if not reached:
		b.modulate = Color(1, 1, 1, 0.55)
	var tr := track
	b.pressed.connect(func() -> void: claim(l, tr))
	return b
