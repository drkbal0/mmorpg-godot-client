@tool
extends PanelContainer
class_name PartyMemberFrame

## Frame individual para un miembro del grupo (Party Member Frame).
## Dimensiones: ~220px de ancho por ~54px de alto.
## Visualiza: Icono/clase, nombre, distancia, badge de estado ('NORMAL', 'ABATIDO', 'MUERTO'),
## barra de HP animada con texto cur/max y barra de maná, siguiendo los tokens de hud_tokens.gd.

const T = preload("res://ui/tokens/hud_tokens.gd")
const D = preload("res://ui/components/HUDv2/hud_draw.gd")

signal clicked(player_id: int)
signal hovered(player_id: int, is_hovered: bool)

# --- Nodos UI ---
@onready var class_icon_ctrl: Control = %ClassIcon
@onready var icon_texture: TextureRect = %IconTexture
@onready var name_label: Label = %NameLabel
@onready var distance_label: Label = %DistanceLabel
@onready var status_badge: PanelContainer = %StatusBadge
@onready var status_label: Label = %StatusLabel
@onready var hp_bar: Control = %HPBar
@onready var mana_bar: Control = %ManaBar

# --- Propiedades de datos ---
@export var player_id: int = 0
@export var player_name: String = "Aliado":
	set(value):
		player_name = value
		if is_inside_tree() and name_label:
			name_label.text = player_name

@export var member_class: String = "warrior":
	set(value):
		member_class = value
		_update_class_visuals()

@export var class_icon: Texture2D = null:
	set(value):
		class_icon = value
		if is_inside_tree() and icon_texture:
			icon_texture.texture = class_icon
			if class_icon_ctrl:
				class_icon_ctrl.queue_redraw()

@export var current_hp: float = 1000.0:
	set(value):
		current_hp = value
		if is_inside_tree() and hp_bar:
			hp_bar.queue_redraw()

@export var max_hp: float = 1000.0:
	set(value):
		max_hp = maxf(1.0, value)
		if is_inside_tree() and hp_bar:
			hp_bar.queue_redraw()

@export var current_mana: float = 400.0:
	set(value):
		current_mana = value
		if is_inside_tree() and mana_bar:
			mana_bar.queue_redraw()

@export var max_mana: float = 400.0:
	set(value):
		max_mana = maxf(1.0, value)
		if is_inside_tree() and mana_bar:
			mana_bar.queue_redraw()

@export var distance: float = 0.0:
	set(value):
		distance = value
		_update_distance_label()

@export var status: String = "NORMAL"
@export var is_leader: bool = false:
	set(value):
		is_leader = value
		_update_leader_crown()
@export var is_downed: bool = false
@export var bleedout_seconds: float = 0.0

# --- Estado de animación interno ---
var _display_hp: float = 1000.0
var _trail_hp: float = 1000.0
var _last_rendered_display_hp: float = -1.0
var _hp_tween: Tween = null

var _display_mana: float = 400.0
var _mana_tween: Tween = null

var _flash_phase: float = 0.0
var _is_hovered: bool = false


func _ready() -> void:
	custom_minimum_size = Vector2(220, 54)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_STOP

	# Estilos tipográficos con cifras tabulares tnum
	if name_label:
		name_label.add_theme_font_override("font", T.font("semibold"))
		name_label.add_theme_font_size_override("font_size", 11)
		name_label.add_theme_color_override("font_color", T.TEXT)
		name_label.text = player_name

	if distance_label:
		distance_label.add_theme_font_override("font", T.font("medium"))
		distance_label.add_theme_font_size_override("font_size", 10)
		distance_label.add_theme_color_override("font_color", T.TEXT_SECONDARY)

	if status_label:
		status_label.add_theme_font_override("font", T.font("bold"))
		status_label.add_theme_font_size_override("font_size", 9)

	# Conectar llamadas de dibujado procedural
	if class_icon_ctrl and not class_icon_ctrl.draw.is_connected(_on_class_icon_draw):
		class_icon_ctrl.draw.connect(_on_class_icon_draw)

	if hp_bar and not hp_bar.draw.is_connected(_on_hp_bar_draw):
		hp_bar.draw.connect(_on_hp_bar_draw)

	if mana_bar and not mana_bar.draw.is_connected(_on_mana_bar_draw):
		mana_bar.draw.connect(_on_mana_bar_draw)

	# Conexión de eventos de ratón
	if not gui_input.is_connected(_on_gui_input):
		gui_input.connect(_on_gui_input)
	if not mouse_entered.is_connected(_on_mouse_entered):
		mouse_entered.connect(_on_mouse_entered)
	if not mouse_exited.is_connected(_on_mouse_exited):
		mouse_exited.connect(_on_mouse_exited)

	_update_leader_crown()

	# Sincronización inicial
	set_hp(current_hp, max_hp, true)
	set_mana(current_mana, max_mana, true)
	set_distance(distance)
	_update_class_visuals()
	_update_status_visuals()
	_update_frame_border()


func setup(data: Dictionary) -> void:
	player_id = int(data.get("id", data.get("player_id", 0)))
	player_name = str(data.get("name", data.get("player_name", "Aliado")))
	if is_inside_tree() and name_label:
		name_label.text = player_name

	var cls_val = data.get("class", data.get("class_name", data.get("character_class", "warrior")))
	if cls_val is Texture2D:
		class_icon = cls_val
		member_class = "custom"
	else:
		member_class = str(cls_val)
		class_icon = data.get("icon", null)

	var p_max_hp: float = float(data.get("max_hp", 1000.0))
	var p_hp: float = float(data.get("hp", data.get("current_hp", p_max_hp)))
	set_hp(p_hp, p_max_hp, true)

	var p_max_mana: float = float(data.get("max_mana", 400.0))
	var p_mana: float = float(data.get("mana", data.get("current_mana", p_max_mana)))
	set_mana(p_mana, p_max_mana, true)

	var dist: float = float(data.get("distance", data.get("dist", 0.0)))
	set_distance(dist)

	is_leader = bool(data.get("is_leader", false))

	var downed: bool = bool(data.get("is_downed", false))
	var timer_sec: float = float(data.get("timer_sec", data.get("downed_timer", 0.0)))
	var raw_status: String = str(data.get("status", "ABATIDO" if downed else "NORMAL"))

	if downed or raw_status.to_upper() in ["ABATIDO", "DOWNED"]:
		set_downed(true, timer_sec if timer_sec > 0.0 else 20.0)
	else:
		set_status(raw_status)


func set_hp(p_hp: float, p_max: float, immediate: bool = false) -> void:
	max_hp = maxf(1.0, p_max)
	current_hp = clampf(p_hp, 0.0, max_hp)

	if immediate or not is_inside_tree() or Engine.is_editor_hint():
		_display_hp = current_hp
		_trail_hp = current_hp
		_last_rendered_display_hp = _display_hp
		if hp_bar:
			hp_bar.queue_redraw()
		return

	# Daño recibido: estela conserva valor alto para decaer suavemente
	if current_hp < _display_hp:
		_trail_hp = maxf(_trail_hp, _display_hp)
	else:
		# Curación: estela acompaña de inmediato
		_trail_hp = current_hp

	# Animación suave de barra HP vía Tween
	if _hp_tween and _hp_tween.is_valid():
		_hp_tween.kill()

	_hp_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_hp_tween.tween_property(self, "_display_hp", current_hp, 0.28)

	# Transición automática a MUERTO si cae a 0 sin estar abatido
	if current_hp <= 0.0 and not is_downed and status != "MUERTO":
		set_status("MUERTO")
	elif current_hp > 0.0 and status == "MUERTO":
		set_status("NORMAL")


func set_mana(p_mana: float, p_max: float, immediate: bool = false) -> void:
	max_mana = maxf(1.0, p_max)
	current_mana = clampf(p_mana, 0.0, max_mana)

	if immediate or not is_inside_tree() or Engine.is_editor_hint():
		_display_mana = current_mana
		if mana_bar:
			mana_bar.queue_redraw()
		return

	if _mana_tween and _mana_tween.is_valid():
		_mana_tween.kill()

	_mana_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_mana_tween.tween_property(self, "_display_mana", current_mana, 0.25)


func set_distance(dist: float) -> void:
	distance = dist


func _update_distance_label() -> void:
	if not is_inside_tree() or not distance_label:
		return
	if distance < 0.0:
		distance_label.text = "--"
	elif distance < 1000.0:
		distance_label.text = "%dm" % maxi(0, roundi(distance))
	else:
		distance_label.text = "%.1fkm" % (distance / 1000.0)


func set_downed(p_downed: bool, timer_sec: float = 0.0) -> void:
	is_downed = p_downed
	if is_downed:
		bleedout_seconds = timer_sec if timer_sec > 0.0 else 20.0
		status = "ABATIDO"
	else:
		bleedout_seconds = 0.0
		if status == "ABATIDO":
			status = "NORMAL" if current_hp > 0.0 else "MUERTO"
	_update_status_visuals()


func set_status(p_status: String) -> void:
	var upper := p_status.strip_edges().to_upper()
	match upper:
		"ABATIDO", "DOWNED":
			status = "ABATIDO"
			is_downed = true
			if bleedout_seconds <= 0.0:
				bleedout_seconds = 20.0
		"MUERTO", "DEAD":
			status = "MUERTO"
			is_downed = false
			bleedout_seconds = 0.0
			current_hp = 0.0
			_display_hp = 0.0
			_trail_hp = 0.0
		_:
			status = "NORMAL"
			is_downed = false
			bleedout_seconds = 0.0
	_update_status_visuals()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	# Decaimiento suave de la estela de daño de HP
	if _trail_hp > _display_hp:
		_trail_hp = move_toward(_trail_hp, _display_hp, delta * (max_hp * 0.45))
		if hp_bar:
			hp_bar.queue_redraw()

	# Redibujado de HP al animarse
	if not is_equal_approx(_display_hp, _last_rendered_display_hp):
		_last_rendered_display_hp = _display_hp
		if hp_bar:
			hp_bar.queue_redraw()

	# Redibujado continuo de maná si está interpolando
	if mana_bar and _mana_tween and _mana_tween.is_valid():
		mana_bar.queue_redraw()

	# Manejo del estado ABATIDO (pulsación roja y cuenta regresiva de desangrado)
	if is_downed:
		_flash_phase += delta * 8.0
		bleedout_seconds = maxf(0.0, bleedout_seconds - delta)
		if bleedout_seconds <= 0.0:
			set_status("MUERTO")
		else:
			_update_downed_flash_visuals()


func _update_downed_flash_visuals() -> void:
	if not is_inside_tree() or not status_badge or not status_label:
		return
	var pulse := 0.45 + 0.55 * absf(sin(_flash_phase))
	var badge_sb := T.box(Color(0.85, 0.12, 0.12, pulse * 0.95), 4, 1, Color(1.0, 0.35, 0.35, pulse))
	status_badge.add_theme_stylebox_override("panel", badge_sb)

	status_label.text = "ABATIDO %ds" % maxi(0, int(ceil(bleedout_seconds)))
	status_label.add_theme_color_override("font_color", Color.WHITE)

	# Borde del panel en alerta roja pulsante
	var frame_sb := T.box(T.PANEL_BG, 8, 1, Color(0.95, 0.2, 0.2, pulse * 0.8))
	add_theme_stylebox_override("panel", frame_sb)

	if hp_bar:
		hp_bar.queue_redraw()


## Corona dorada vectorial delante del nombre del líder de escuadra.
func _update_leader_crown() -> void:
	if not is_inside_tree() or not name_label:
		return
	var row := name_label.get_parent()
	var crown: Control = row.get_node_or_null("LeaderCrown")
	if is_leader and crown == null:
		crown = Control.new()
		crown.name = "LeaderCrown"
		crown.custom_minimum_size = Vector2(14, 12)
		crown.mouse_filter = Control.MOUSE_FILTER_IGNORE
		crown.tooltip_text = "Líder de escuadra"
		crown.draw.connect(_draw_leader_crown.bind(crown))
		row.add_child(crown)
		row.move_child(crown, name_label.get_index())
	elif not is_leader and crown != null:
		crown.queue_free()


func _draw_leader_crown(crown: Control) -> void:
	var w := crown.size.x
	var h := crown.size.y
	var base_y := h * 0.5 + 4.0
	var pts := PackedVector2Array([
		Vector2(1, base_y), Vector2(1, base_y - 7), Vector2(w * 0.28, base_y - 3.5),
		Vector2(w * 0.5, base_y - 9), Vector2(w * 0.72, base_y - 3.5),
		Vector2(w - 1, base_y - 7), Vector2(w - 1, base_y),
	])
	crown.draw_colored_polygon(pts, Color("#ffcc33"))
	var outline := pts.duplicate()
	outline.append(pts[0])
	crown.draw_polyline(outline, Color("#7a5200"), 1.0, true)
	crown.draw_circle(Vector2(w * 0.5, base_y - 9), 1.4, Color("#fff2b3"))


func _update_status_visuals() -> void:
	if not is_inside_tree() or not status_badge or not status_label:
		return

	match status:
		"ABATIDO":
			_update_downed_flash_visuals()
		"MUERTO":
			var sb := T.box(Color(0.28, 0.08, 0.08, 0.9), 4, 1, Color(0.5, 0.15, 0.15, 0.7))
			status_badge.add_theme_stylebox_override("panel", sb)
			status_label.text = "MUERTO"
			status_label.add_theme_color_override("font_color", Color(0.9, 0.4, 0.4))
			modulate = Color(0.7, 0.7, 0.7, 0.85)
			_update_frame_border()
		_: # NORMAL
			var sb := T.box(Color(0.08, 0.12, 0.15, 0.75), 4, 1, Color(0.18, 0.3, 0.26, 0.5))
			status_badge.add_theme_stylebox_override("panel", sb)
			status_label.text = "NORMAL"
			status_label.add_theme_color_override("font_color", T.HEALTH)
			modulate = Color.WHITE
			_update_frame_border()

	if hp_bar:
		hp_bar.queue_redraw()
	if mana_bar:
		mana_bar.queue_redraw()
	if class_icon_ctrl:
		class_icon_ctrl.queue_redraw()


func _update_class_visuals() -> void:
	if not is_inside_tree():
		return
	if icon_texture:
		icon_texture.texture = class_icon
	if class_icon_ctrl:
		class_icon_ctrl.queue_redraw()


func _update_frame_border() -> void:
	if is_downed:
		return
	var border_col := T.PANEL_EDGE
	if _is_hovered:
		border_col = Color(1, 1, 1, 0.22)
	elif status == "MUERTO":
		border_col = Color(0.4, 0.1, 0.1, 0.5)

	var sb := T.box(T.PANEL_BG, 8, 1, border_col)
	add_theme_stylebox_override("panel", sb)


# --- DIBUJADO PROCEDURAL (CanvasItem Callbacks) ---

func _on_class_icon_draw() -> void:
	if not class_icon_ctrl:
		return
	var rect := Rect2(Vector2.ZERO, class_icon_ctrl.size)
	var radius := 6

	var bg_col := T.SLOT_NEUTRAL if status != "MUERTO" else T.WELL
	var border_col := T.SLOT_BORDER if status != "MUERTO" else Color(0.4, 0.1, 0.1, 0.5)
	class_icon_ctrl.draw_style_box(T.box(bg_col, radius, 1, border_col), rect)

	# Si no hay textura cargada, dibujamos el glifo vectorial de la clase
	if icon_texture == null or icon_texture.texture == null:
		var c := rect.get_center()
		var glyph_size := 18.0
		var info := _get_class_info(member_class)
		var col: Color = info["color"] if status != "MUERTO" else Color(0.5, 0.5, 0.5)
		var glyph: String = info["glyph"]

		if glyph == "cross":
			var h := glyph_size * 0.5
			var width := 2.5
			class_icon_ctrl.draw_line(c - Vector2(0, h * 0.75), c + Vector2(0, h * 0.75), col, width, true)
			class_icon_ctrl.draw_line(c - Vector2(h * 0.75, 0), c + Vector2(h * 0.75, 0), col, width, true)
		else:
			D.draw_glyph(class_icon_ctrl, glyph, c, glyph_size, col, 2.0)


func _on_hp_bar_draw() -> void:
	if not hp_bar:
		return
	var rect := Rect2(Vector2.ZERO, hp_bar.size)
	var radius := 3

	# Fondo
	hp_bar.draw_style_box(T.box(T.BAR_BG, radius, 1, Color(1, 1, 1, 0.07)), rect)

	var inner := rect.grow(-1)
	var frac := clampf(_display_hp / max_hp, 0.0, 1.0)
	var trail_frac := clampf(_trail_hp / max_hp, 0.0, 1.0)

	# Estela de daño (damage trail)
	if trail_frac > frac + 0.001 and status != "MUERTO":
		var trail_rect := Rect2(inner.position, Vector2(inner.size.x * trail_frac, inner.size.y))
		hp_bar.draw_style_box(T.box(Color(T.HEALTH_TRAIL, 0.45), radius), trail_rect)

	# Relleno principal de HP
	if frac > 0.0 and status != "MUERTO":
		var fill_color := T.HEALTH
		if is_downed:
			fill_color = Color("#e8653c") # Color ámbar/peligro al estar abatido
		var fill_width := maxf(inner.size.x * frac, float(radius * 2))
		var fill_rect := Rect2(inner.position, Vector2(fill_width, inner.size.y))
		hp_bar.draw_style_box(T.box(fill_color, radius), fill_rect)

		# Brillo especular superior
		hp_bar.draw_rect(Rect2(fill_rect.position + Vector2(2, 1), Vector2(maxf(0.0, fill_rect.size.x - 4), 1)), Color(1, 1, 1, 0.22))

	# Texto cur / max centrado con cifras tabulares y sombra de caída
	var txt: String
	if status == "MUERTO":
		txt = "0 / %d" % roundi(max_hp)
	else:
		txt = "%d / %d" % [roundi(_display_hp), roundi(max_hp)]
	D.draw_text_centered(hp_bar, T.font("semibold"), 10, rect, txt, T.TEXT, true)


func _on_mana_bar_draw() -> void:
	if not mana_bar:
		return
	var rect := Rect2(Vector2.ZERO, mana_bar.size)
	var radius := 2

	# Fondo de barra de maná
	mana_bar.draw_style_box(T.box(T.BAR_BG, radius, 1, Color(1, 1, 1, 0.05)), rect)

	var inner := rect.grow(-1)
	var frac := clampf(_display_mana / max_mana, 0.0, 1.0)

	if frac > 0.0 and status != "MUERTO":
		var fill_width := maxf(inner.size.x * frac, float(radius * 2))
		var fill_rect := Rect2(inner.position, Vector2(fill_width, inner.size.y))
		mana_bar.draw_style_box(T.box(T.MANA, radius), fill_rect)
		# Brillo especular superior sutil
		mana_bar.draw_rect(Rect2(fill_rect.position + Vector2(1, 0.5), Vector2(maxf(0.0, fill_rect.size.x - 2), 0.5)), Color(1, 1, 1, 0.2))


func _get_class_info(p_class: String) -> Dictionary:
	var c := p_class.strip_edges().to_lower()
	match c:
		"warrior", "guerrero", "fighter", "berserker":
			return {"glyph": "slash", "color": Color("#f06a5a")}
		"guardian", "tank", "paladin", "protector":
			return {"glyph": "shield", "color": Color("#5aa9ff")}
		"mage", "mago", "wizard", "sorcerer", "warlock":
			return {"glyph": "star", "color": Color("#b07cf0")}
		"ranger", "cazador", "hunter", "archer":
			return {"glyph": "target", "color": Color("#5ad87a")}
		"rogue", "picaro", "assassin", "ninja":
			return {"glyph": "dash", "color": Color("#f0a03c")}
		"priest", "sacerdote", "healer", "cleric", "curador":
			return {"glyph": "cross", "color": Color("#46e3c1")}
		"scout", "explorador":
			return {"glyph": "eye", "color": Color("#5ac8e8")}
		_:
			return {"glyph": "user", "color": T.ACCENT_DEFAULT}


# --- Eventos de entrada de ratón ---

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit(player_id)


func _on_mouse_entered() -> void:
	_is_hovered = true
	_update_frame_border()
	hovered.emit(player_id, true)


func _on_mouse_exited() -> void:
	_is_hovered = false
	_update_frame_border()
	hovered.emit(player_id, false)
