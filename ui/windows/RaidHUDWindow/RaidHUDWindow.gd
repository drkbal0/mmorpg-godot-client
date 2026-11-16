extends Control
## HUD de raid extendido (sanador) — UI v2.4 Paso 17 · ADR 115 (design_ref/pantallas_html/MMO-Raid.html).
##
## Capa HUD sobre el mundo (no roba el foco ni bloquea el ratón fuera de los marcos). Escenario de
## 1440×810 escalado de forma uniforme y centrado:
## 1. Jefe (x 470…970, y 20): «Coloso de Runavell» · «Fase 2» (#f5c35b) · «04:12» y barra de 14 px
##    al 43 % (#e25555) con el porcentaje centrado.
## 2. Alerta táctica central (y 170): borde #ff6b6b, fondo rgba(58,29,34,.92), flecha direccional,
##    «Todos a la izquierda» (26 px), «Terremoto rúnico · también suena desde la derecha» y la
##    cuenta atrás gigante «3» (#ff8a8a).
## 3. Marcos de raid (x 40, y 290): «RAID · 20» + leyenda de click-casting, cuadrícula de 4 × 5
##    (2 × 5 en banda de 10) de 128×42 con 10 px entre columnas, y leyenda inferior (daño
##    previsto, curación entrante y purificable).
## 4. Consola compacta del sanador (x 453, bottom 16): trapecio grafito, vida 88 % y maná 52 % con
##    «Maná 52 % · dura ~1:40 a este ritmo», y 10 ranuras (1 … 0) con enfriamientos.
##
## Estado en `RaidService` (inyectable como `raid`; si no, /root/RaidService o uno local).
## Atajo global Ctrl+R (UIInputRouter → UIOrchestrator.toggle_raid_hud()).

const T = preload("res://ui/tokens/hud_tokens.gd")
const Kit = preload("res://ui/windows/common/CinematicKit.gd")
const EK = preload("res://ui/windows/common/EntryKit.gd")
const RK = preload("res://ui/windows/common/RaidKit.gd")
const RaidScript = preload("res://shared-core/RaidService.gd")

signal member_clicked(member_id: String, button_index: int, shift: bool)

## Servicio de raid inyectable (tests). Si es null se usa /root/RaidService o uno local.
var raid: Node = null
var window_id := "raid_hud"
## Fondo «.scene» + velo rgba(5,8,10,.25). Solo para vista previa / capturas: en el mundo se ve el 3D.
var show_backdrop := false
## Con `auto_tick` del servicio y `start_encounter` el temporizador corre solo.
var _has_been_moved := false

var backdrop: Control
var backdrop_veil: ColorRect
var stage: Control
var stage_scale := 1.0

var boss_box: VBoxContainer
var boss_name_label: Label
var boss_phase_label: Label
var boss_timer_label: Label
var boss_bar: RK.Meter

var alert_panel: PanelContainer
var alert_arrow: RK.Arrow
var alert_title: Label
var alert_subtitle: Label
var alert_count: Label

var raid_box: VBoxContainer
var header_label: Label
var legend_label: Label
var grid: HBoxContainer
var columns: Array[VBoxContainer] = []
var cards: Array = []                       # RK.MemberCard × 20 (orden grupo-mayor)
var legend_row: HBoxContainer
var legend_hatch: RK.HatchSwatch
var legend_heal: RK.Swatch
var legend_dispel: RK.Diamond

var console_shape: RK.ConsoleShape
var console_box: VBoxContainer
var hp_meter: RK.Meter
var mana_meter: RK.Meter
var slots: Array = []                       # RK.AbilitySlot × 10

var refresh_count := 0
var _built := false


func _init() -> void:
	theme = T.THEME
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
	_resolve_raid()
	_build()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(_layout)
	_layout()
	refresh()


## params: {"raid_size": 10 | 20, "backdrop": bool, "start_encounter": bool, "select": id}
func initialize_window(params: Dictionary) -> void:
	_resolve_raid()
	if params.has("backdrop"):
		show_backdrop = bool(params["backdrop"])
	if params.has("raid_size"):
		raid.set_raid_size(int(params["raid_size"]))
	if params.has("select"):
		raid.select_target(str(params["select"]))
	if bool(params.get("start_encounter", false)):
		raid.start_encounter()
	visible = true
	if _built:
		_layout()
		refresh()


func _resolve_raid() -> void:
	if raid == null and is_inside_tree():
		raid = get_node_or_null("/root/RaidService")
	if raid == null:
		raid = RaidScript.new()
		raid.name = "LocalRaidService"
		raid.auto_tick = false
		raid.load_seed()
	if raid.get_parent() == null:
		add_child(raid)
	var cb := Callable(self, "_on_raid_changed")
	if not raid.is_connected("changed", cb):
		raid.connect("changed", cb)


func _on_raid_changed(_a = null) -> void:
	if _built and is_visible_in_tree():
		refresh()


func _exit_tree() -> void:
	var cb := Callable(self, "_on_raid_changed")
	if raid != null and is_instance_valid(raid) and raid.is_connected("changed", cb):
		raid.disconnect("changed", cb)


# ==========================================================================
# API (tests, atajos y orquestador)
# ==========================================================================
func get_card(member_id: String) -> Control:
	for c in cards:
		if c.member_id == member_id and c.visible:
			return c
	return null


func visible_card_count() -> int:
	var n := 0
	for c in cards:
		if c.visible:
			n += 1
	return n


func column_count() -> int:
	var n := 0
	for col in columns:
		if col.visible:
			n += 1
	return n


## Simula un clic sobre el marco de un integrante (clic izq. / der., Shift).
func click_member(member_id: String, button_index: int = MOUSE_BUTTON_LEFT, shift: bool = false) -> bool:
	if get_card(member_id) == null:
		return false
	return _on_card_clicked(member_id, button_index, shift)


func set_raid_size(n: int) -> bool:
	return raid.set_raid_size(n)


## Rectángulos de los cuatro bloques en coordenadas del escenario (auditoría de solapes).
func layout_rects() -> Dictionary:
	return {
		"boss": Rect2(boss_box.position, boss_box.size),
		"alert": Rect2(alert_panel.position, alert_panel.size) if alert_panel.visible else Rect2(),
		"raid": Rect2(raid_box.position, raid_box.size),
		"console": Rect2(console_box.position, console_box.size),
	}


# ==========================================================================
# Construcción
# ==========================================================================
func _build() -> void:
	if _built:
		return
	_built = true
	backdrop = EK.scene_rect("Scene")
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	backdrop_veil = ColorRect.new()
	backdrop_veil.name = "SceneVeil"
	backdrop_veil.color = T.RAID_SCENE_VEIL
	backdrop_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop_veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop_veil)
	stage = Control.new()
	stage.name = "Stage"
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.size = T.CINEMA_DESIGN_SIZE
	add_child(stage)
	_build_console_shape()
	_build_boss()
	_build_alert()
	_build_raid()
	_build_console()


func _build_boss() -> void:
	boss_box = VBoxContainer.new()
	boss_box.name = "Boss"
	boss_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	boss_box.add_theme_constant_override("separation", 6)
	boss_box.position = T.RAID_BOSS_ORIGIN
	boss_box.custom_minimum_size = Vector2(T.RAID_BOSS_WIDTH, 0)
	boss_box.size = Vector2(T.RAID_BOSS_WIDTH, 0)
	stage.add_child(boss_box)
	var row := HBoxContainer.new()
	row.name = "TitleRow"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	boss_box.add_child(row)
	boss_name_label = RK.label("", 17, T.TEXT, "bold", "BossName")
	row.add_child(boss_name_label)
	boss_phase_label = RK.label("", 13, T.RAID_BOSS_PHASE, "medium", "BossPhase")
	boss_phase_label.size_flags_vertical = Control.SIZE_SHRINK_END
	row.add_child(boss_phase_label)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(sp)
	boss_timer_label = RK.label("", 13, T.TEXT, "medium", "EnrageTimer")
	boss_timer_label.size_flags_vertical = Control.SIZE_SHRINK_END
	row.add_child(boss_timer_label)
	boss_bar = RK.Meter.new(T.RAID_BOSS_BAR_HEIGHT, T.RAID_BOSS_HP, T.RAID_BOSS_BAR_BG)
	boss_bar.name = "BossBar"
	boss_bar.text_size = 12
	boss_box.add_child(boss_bar)


func _build_alert() -> void:
	var a := RK.alert_box()
	alert_panel = a["panel"]
	alert_arrow = a["arrow"]
	alert_title = a["title"]
	alert_subtitle = a["subtitle"]
	alert_count = a["count"]
	stage.add_child(alert_panel)
	alert_panel.resized.connect(_center_alert)


func _build_raid() -> void:
	raid_box = VBoxContainer.new()
	raid_box.name = "RaidFrames"
	raid_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	raid_box.add_theme_constant_override("separation", 10)
	raid_box.position = T.RAID_GRID_ORIGIN
	stage.add_child(raid_box)
	var head := HBoxContainer.new()
	head.name = "Header"
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_theme_constant_override("separation", 10)
	raid_box.add_child(head)
	header_label = Kit.shadow(Kit.caps("Raid · 20", T.RAID_HEADER), 2)
	header_label.name = "RaidHeader"
	header_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(header_label)
	legend_label = RK.label(raid.click_legend, 13, T.RAID_LEGEND, "medium", "ClickLegend")
	head.add_child(legend_label)
	grid = HBoxContainer.new()
	grid.name = "Grid"
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.add_theme_constant_override("separation", int(T.RAID_FRAME_GAP.x))
	raid_box.add_child(grid)
	for g in T.RAID_GROUPS:
		var col := VBoxContainer.new()
		col.name = "Group%d" % (g + 1)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_theme_constant_override("separation", int(T.RAID_FRAME_GAP.y))
		grid.add_child(col)
		columns.append(col)
		for m in T.RAID_GROUP_SIZE:
			var card := RK.MemberCard.new()
			col.add_child(card)
			card.clicked.connect(_on_card_clicked)
			cards.append(card)
	legend_row = HBoxContainer.new()
	legend_row.name = "Legend"
	legend_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	legend_row.add_theme_constant_override("separation", 14)
	raid_box.add_child(legend_row)
	legend_hatch = RK.HatchSwatch.new()
	legend_heal = RK.Swatch.new(Color(T.RAID_INCOMING_HEAL, 0.45))
	legend_dispel = RK.Diamond.new(T.RAID_DISPEL, 9.0)
	for pair in [[legend_hatch, "Daño previsto (3 s)"], [legend_heal, "Curación entrante"], [legend_dispel, "Purificable"]]:
		var item := HBoxContainer.new()
		item.mouse_filter = Control.MOUSE_FILTER_IGNORE
		item.add_theme_constant_override("separation", 6)
		item.add_child(pair[0])
		item.add_child(RK.label(pair[1], 12, T.RAID_HEADER, "medium"))
		legend_row.add_child(item)


func _build_console_shape() -> void:
	console_shape = RK.ConsoleShape.new()
	console_shape.name = "HealerConsoleShape"
	console_shape.position = Vector2.ZERO
	console_shape.size = T.CINEMA_DESIGN_SIZE
	stage.add_child(console_shape)


func _build_console() -> void:
	var r := T.RAID_CONSOLE_RECT
	console_box = VBoxContainer.new()
	console_box.name = "HealerConsole"
	console_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	console_box.add_theme_constant_override("separation", 8)
	console_box.position = r.position
	console_box.custom_minimum_size = Vector2(r.size.x, 0)
	console_box.size = r.size
	stage.add_child(console_box)
	var bars := HBoxContainer.new()
	bars.name = "Bars"
	bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bars.add_theme_constant_override("separation", 4)
	console_box.add_child(bars)
	hp_meter = RK.Meter.new(T.RAID_CONSOLE_BAR_HEIGHT, T.HEALTH, T.WELL)
	hp_meter.name = "HealerHP"
	bars.add_child(hp_meter)
	mana_meter = RK.Meter.new(T.RAID_CONSOLE_BAR_HEIGHT, T.MANA, T.WELL)
	mana_meter.name = "HealerMana"
	bars.add_child(mana_meter)
	var row := HBoxContainer.new()
	row.name = "Abilities"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", int(T.RAID_SLOT_GAP))
	console_box.add_child(row)
	for i in 10:
		var s := RK.AbilitySlot.new()
		s.name = "Slot%d" % (i + 1)
		row.add_child(s)
		slots.append(s)


func _layout() -> void:
	if not _built:
		return
	var area := size if size.x > 0 else get_viewport_rect().size
	stage_scale = Kit.fit_stage(stage, area)
	_center_alert()


func _center_alert() -> void:
	if alert_panel == null:
		return
	alert_panel.reset_size()
	alert_panel.position = Vector2(roundf((T.CINEMA_DESIGN_SIZE.x - alert_panel.size.x) * 0.5), T.RAID_ALERT_TOP)


# ==========================================================================
# Refresco
# ==========================================================================
func refresh() -> void:
	if not _built or raid == null:
		return
	refresh_count += 1
	backdrop.visible = show_backdrop
	backdrop_veil.visible = show_backdrop
	_refresh_boss()
	_refresh_alert()
	_refresh_raid()
	_refresh_console()


func _refresh_boss() -> void:
	boss_name_label.text = raid.boss_name
	boss_phase_label.text = raid.boss_phase_label()
	boss_phase_label.add_theme_color_override("font_color", raid.boss_phase_color)
	boss_timer_label.text = raid.get_enrage_time_formatted()
	boss_timer_label.add_theme_color_override("font_color", T.RAID_AGGRO if raid.enraged else T.TEXT)
	boss_bar.fill = raid.boss_hp_color
	boss_bar.set_value(raid.boss_hp_percent / 100.0, raid.boss_hp_text())


func _refresh_alert() -> void:
	alert_panel.visible = raid.alert_active
	if not raid.alert_active:
		return
	alert_title.text = raid.alert_title
	alert_subtitle.text = raid.alert_subtitle
	alert_subtitle.visible = raid.alert_subtitle != ""
	alert_count.text = str(raid.get_alert_countdown())
	alert_arrow.visible = raid.alert_direction != ""
	alert_arrow.set_rotation_rad(raid.alert_arrow_rotation())
	_center_alert()


func _refresh_raid() -> void:
	header_label.text = raid.header_text().to_upper()
	legend_label.text = raid.click_legend
	var ncols: int = raid.grid_columns()
	var views: Array = []
	for m in raid.visible_members():
		views.append(raid.member_view(str(m["id"])))
	for c in columns.size():
		columns[c].visible = c < ncols
	for i in cards.size():
		var card = cards[i]
		if i < views.size():
			card.setup(views[i])
			card.visible = true
		else:
			card.visible = false


func _refresh_console() -> void:
	hp_meter.set_value(raid.healer_hp_percent / 100.0)
	mana_meter.set_value(raid.mana_current / raid.mana_max, raid.mana_projection_text())
	for i in slots.size():
		var a: Dictionary = raid.ability(i)
		if a.is_empty():
			slots[i].visible = false
			continue
		slots[i].visible = true
		slots[i].setup(str(a["key"]), Color(str(a["color"])), raid.ability_cooldown_text(i), str(a["name"]))


func _on_card_clicked(member_id: String, button_index: int, shift: bool) -> bool:
	member_clicked.emit(member_id, button_index, shift)
	return raid.handle_click(member_id, button_index, shift)
