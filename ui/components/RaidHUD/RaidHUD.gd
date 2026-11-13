extends Control
## HUD de raid para sanador (design_ref/pantallas_html/MMO-Raid.html).
##
##  · 20 marcos compactos (4 grupos de 5 en columnas, 128×42) con vida
##    segmentada, daño previsto a 3 s (achurado), curación entrante, aggro
##    (borde rojo pulsante), purificables (rombos) y alcance (> 40 m atenuado).
##  · Telemetría del sanador: barra de maná + "Maná 52 % · dura ~1:40 a este ritmo".
##  · Alerta central de mecánica de jefe con flecha direccional y cuenta atrás.
##
## API:
##   set_roster([{name, class, hp, hp_max, ...}, ...])   (máx. 20)
##   update_member(id_o_índice, {hp, predicted_damage, incoming_heal, aggro, dispels, distance})
##   set_aggro_target(id)                         set_mana(actual, máx, gasto_por_s)
##   show_boss_alert("¡ALÉJATE DEL GRUPO EN {s}s!", 3.0, "away", "Terremoto rúnico")
##   RaidHUD.calculate_mana_longevity(maná, gasto_por_s) -> segundos

const T = preload("res://ui/tokens/hud_tokens.gd")
const SvgPath = preload("res://ui/icons/svg_path.gd")
const FRAME_SCENE: PackedScene = preload("res://ui/components/RaidHUD/RaidMemberFrame.tscn")
const BAR_SCENE: PackedScene = preload("res://ui/components/HUDv2/resource_bar.tscn")

signal heal_requested(member_id: String)
signal shield_requested(member_id: String)
signal dispel_requested(member_id: String)
signal boss_alert_finished

## Rotación de la flecha base (apunta a la izquierda) por dirección.
const ARROW_ROTATION := {
	"left": 0.0, "right": PI, "up": PI * 0.5, "down": -PI * 0.5,
	"away": PI * 0.5,   # alejarse del grupo: hacia fuera (arriba)
}

@export var raid_origin: Vector2 = Vector2(40, 290)

var frames: Array = []               # RaidMemberFrame × 20 (orden grupo-mayor)
var group_columns: Array[VBoxContainer] = []
var header: Label
var telemetry: Control
var mana_bar: Control
var mana_label: Label
var alert_panel: PanelContainer
var alert_arrow: Control
var alert_title: Label
var alert_sub: Label
var alert_count: Label

var mana: float = 0.0
var mana_max: float = 1.0
var mana_burn_rate: float = 0.0
var alert_template: String = ""
var alert_remaining: float = 0.0
var alert_direction: String = ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_raid_grid()
	_build_telemetry()
	_build_alert()


# --------------------------------------------------------------------------
# Roster
# --------------------------------------------------------------------------
func set_roster(members: Array) -> void:
	if members.size() > T.RAID_SIZE:
		push_warning("RaidHUD.set_roster: %d miembros, se muestran %d" % [members.size(), T.RAID_SIZE])
	for i in frames.size():
		var fr = frames[i]
		if i < members.size() and members[i] is Dictionary:
			fr.setup(members[i])
			fr.visible = true
		else:
			fr.visible = false
	header.text = "RAID · %d" % mini(members.size(), T.RAID_SIZE)


## `key`: índice 0..19 o id/nombre del miembro.
func update_member(key: Variant, data: Dictionary) -> bool:
	var fr = get_frame_by_id(str(key)) if typeof(key) == TYPE_STRING else get_frame(int(key))
	if fr == null:
		return false
	fr.setup(data)
	return true


## Solo un miembro tiene el aggro del jefe a la vez ("" lo quita a todos).
func set_aggro_target(member_id: String) -> void:
	for fr in frames:
		fr.has_aggro = member_id != "" and fr.member_id == member_id


func select_member(member_id: String) -> void:
	for fr in frames:
		fr.selected = member_id != "" and fr.member_id == member_id


func get_frame(index: int) -> Control:
	return frames[index] if index >= 0 and index < frames.size() else null


func get_frame_by_id(member_id: String) -> Control:
	for fr in frames:
		if fr.member_id == member_id or fr.player_name == member_id:
			return fr
	return null


func get_frame_count() -> int:
	return frames.size()


func get_visible_frame_count() -> int:
	var n := 0
	for fr in frames:
		if fr.visible:
			n += 1
	return n


## Miembros cuyo daño previsto los mata si no se les cura (prioridad de triaje).
func get_lethal_members() -> Array[String]:
	var out: Array[String] = []
	for fr in frames:
		if fr.visible and fr.is_lethal_prediction():
			out.append(fr.member_id)
	return out


# --------------------------------------------------------------------------
# Telemetría de sanador
# --------------------------------------------------------------------------
## Segundos que dura el maná al ritmo de gasto actual. INF si no se gasta.
static func calculate_mana_longevity(current_mana: float, burn_rate_per_sec: float) -> float:
	if current_mana <= 0.0:
		return 0.0
	if burn_rate_per_sec <= 0.0:
		return INF
	return current_mana / burn_rate_per_sec


## 100 s -> "1:40"; 3725 s -> "1:02:05"; INF -> "∞".
static func format_longevity(seconds: float) -> String:
	if is_inf(seconds) or is_nan(seconds):
		return "∞"
	var s := maxi(0, floori(seconds))
	if s >= 3600:
		return "%d:%02d:%02d" % [s / 3600, (s % 3600) / 60, s % 60]
	return "%d:%02d" % [s / 60, s % 60]


func set_mana(current: float, max_value: float, burn_rate_per_sec: float) -> void:
	mana_max = maxf(1.0, max_value)
	mana = clampf(current, 0.0, mana_max)
	mana_burn_rate = maxf(0.0, burn_rate_per_sec)
	if not is_node_ready():
		return
	mana_bar.set_values(mana, mana_max, 0.0)
	mana_label.text = get_mana_text()


func get_mana_longevity() -> float:
	return calculate_mana_longevity(mana, mana_burn_rate)


func get_mana_text() -> String:
	var pct := roundi(mana / mana_max * 100.0)
	var life := get_mana_longevity()
	if is_inf(life):
		return "Maná %d %% · sin gasto" % pct
	return "Maná %d %% · dura ~%s a este ritmo" % [pct, format_longevity(life)]


# --------------------------------------------------------------------------
# Alerta de mecánica de jefe
# --------------------------------------------------------------------------
## `text` admite "{s}" para la cuenta atrás: "¡ALÉJATE DEL GRUPO EN {s}s!".
## `direction`: left | right | up | down | away | "" (sin flecha).
func show_boss_alert(text: String, seconds: float, direction: String = "", subtitle: String = "") -> void:
	alert_template = text
	alert_remaining = maxf(0.0, seconds)
	alert_direction = direction if ARROW_ROTATION.has(direction) else ""
	if not is_node_ready():
		await ready
	alert_sub.text = subtitle
	alert_sub.visible = subtitle != ""
	alert_arrow.visible = alert_direction != ""
	alert_arrow.queue_redraw()
	alert_panel.visible = alert_remaining > 0.0
	_refresh_alert()


func hide_boss_alert() -> void:
	alert_remaining = 0.0
	if is_node_ready():
		alert_panel.visible = false


func is_alert_visible() -> bool:
	return is_node_ready() and alert_panel.visible


func get_alert_countdown() -> int:
	return ceili(alert_remaining)


func get_alert_text() -> String:
	return alert_template.replace("{s}", str(get_alert_countdown()))


func get_alert_arrow_rotation() -> float:
	return ARROW_ROTATION.get(alert_direction, 0.0)


## Avanza la cuenta atrás (lo llama _process; público para pruebas deterministas).
func tick(delta: float) -> void:
	if alert_remaining <= 0.0:
		return
	alert_remaining = maxf(0.0, alert_remaining - delta)
	_refresh_alert()
	if alert_remaining <= 0.0:
		alert_panel.visible = false
		boss_alert_finished.emit()


func _process(delta: float) -> void:
	tick(delta)


func _refresh_alert() -> void:
	if not is_node_ready():
		return
	alert_title.text = get_alert_text()
	alert_count.text = str(get_alert_countdown())
	alert_panel.reset_size()
	alert_panel.position.x = (get_rect().size.x - alert_panel.size.x) * 0.5 if get_rect().size.x > 0.0 else 0.0


# --------------------------------------------------------------------------
# Construcción
# --------------------------------------------------------------------------
func _label(text: String, weight: String, fs: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", T.font(weight))
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _build_raid_grid() -> void:
	var root := VBoxContainer.new()
	root.name = "Raid"
	root.position = raid_origin
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_theme_constant_override("separation", 10)
	add_child(root)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(head)
	header = _label("RAID · %d" % T.RAID_SIZE, "semibold", T.FS_SMALL, T.TEXT_KEY)
	header.name = "Header"
	head.add_child(header)
	head.add_child(_label("Clic: Sanar · Clic der.: Escudo · Shift+clic: Purificar", "medium", T.FS_BODY, T.TEXT_SECONDARY))
	var grid := HBoxContainer.new()
	grid.name = "Groups"
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.add_theme_constant_override("separation", int(T.RAID_FRAME_GAP.x))
	root.add_child(grid)
	for g in T.RAID_GROUPS:
		var col := VBoxContainer.new()
		col.name = "Group%d" % (g + 1)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_theme_constant_override("separation", int(T.RAID_FRAME_GAP.y))
		grid.add_child(col)
		group_columns.append(col)
		for m in T.RAID_GROUP_SIZE:
			var fr = FRAME_SCENE.instantiate()
			fr.name = "Member%d" % (g * T.RAID_GROUP_SIZE + m + 1)
			col.add_child(fr)
			fr.frame_clicked.connect(_on_frame_clicked)
			frames.append(fr)


func _build_telemetry() -> void:
	telemetry = VBoxContainer.new()
	telemetry.name = "HealerTelemetry"
	var grid_h := T.RAID_GROUP_SIZE * (T.RAID_FRAME_SIZE.y + T.RAID_FRAME_GAP.y) + 40.0
	telemetry.position = raid_origin + Vector2(0, grid_h)
	telemetry.custom_minimum_size = Vector2(T.RAID_GROUPS * (T.RAID_FRAME_SIZE.x + T.RAID_FRAME_GAP.x) - T.RAID_FRAME_GAP.x, 0)
	telemetry.mouse_filter = Control.MOUSE_FILTER_IGNORE
	telemetry.add_theme_constant_override("separation", 4)
	add_child(telemetry)
	mana_label = _label("", "semibold", T.FS_BODY, T.TEXT)
	mana_label.name = "ManaLongevity"
	telemetry.add_child(mana_label)
	mana_bar = BAR_SCENE.instantiate()
	mana_bar.name = "ManaBar"
	mana_bar.kind = "mana"
	mana_bar.custom_minimum_size = Vector2(0, 14)
	telemetry.add_child(mana_bar)
	set_mana(mana, mana_max, mana_burn_rate)


func _build_alert() -> void:
	alert_panel = PanelContainer.new()
	alert_panel.name = "BossAlert"
	alert_panel.position = Vector2(0, 170)
	alert_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := T.box(T.RAID_ALERT_BG, 16, 2, T.RAID_ALERT_EDGE)
	sb.content_margin_left = 26
	sb.content_margin_right = 26
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 20
	alert_panel.add_theme_stylebox_override("panel", sb)
	add_child(alert_panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	alert_panel.add_child(row)
	alert_arrow = Control.new()
	alert_arrow.name = "Arrow"
	alert_arrow.custom_minimum_size = Vector2(40, 40)
	alert_arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	alert_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	alert_arrow.draw.connect(_draw_alert_arrow)
	row.add_child(alert_arrow)
	var texts := VBoxContainer.new()
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.add_theme_constant_override("separation", 0)
	row.add_child(texts)
	alert_title = _label("", "bold", 26, T.TEXT)
	alert_title.name = "Title"
	texts.add_child(alert_title)
	alert_sub = _label("", "medium", 14, T.RAID_ALERT_SUB)
	texts.add_child(alert_sub)
	alert_count = _label("", "bold", 44, T.RAID_ALERT_COUNT)
	alert_count.name = "Countdown"
	row.add_child(alert_count)
	alert_panel.visible = false


func _draw_alert_arrow() -> void:
	var s := alert_arrow.size
	alert_arrow.draw_set_transform(s * 0.5, get_alert_arrow_rotation(), Vector2.ONE)
	SvgPath.draw_layers(alert_arrow, [{"d": T.RAID_ARROW_PATH, "stroke": T.RAID_ALERT_ICON, "width": 2.4}], Rect2(-s * 0.5, s))
	alert_arrow.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _on_frame_clicked(member_id: String, button_index: int, shift: bool) -> void:
	select_member(member_id)
	if shift:
		dispel_requested.emit(member_id)
	elif button_index == MOUSE_BUTTON_RIGHT:
		shield_requested.emit(member_id)
	else:
		heal_requested.emit(member_id)
