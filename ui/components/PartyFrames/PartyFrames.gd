@tool
extends Control
class_name PartyFrames

## Contenedor de Party Frames para MMORPG (HUD de Grupo).
## Aloja hasta 3 marcos de miembros del grupo en un VBoxContainer vertical,
## gestionando la sincronización de vida, maná, estado abatido, distancias y clics.

const T = preload("res://ui/hud_tokens.gd")
const PartyMemberFrame = preload("res://ui/components/PartyFrames/PartyMemberFrame.gd")
const MEMBER_FRAME_SCENE = preload("res://ui/components/PartyFrames/PartyMemberFrame.tscn")
const MercenaryCodec = preload("res://shared-core/MercenaryCodec.gd")
const MAX_PARTY_MEMBERS := 3

signal member_clicked(player_id: int)
signal member_hovered(player_id: int, is_hovered: bool)
signal mercenary_command_triggered(stance: int, target_id: int)

@onready var member_list: VBoxContainer = %MemberList

var _frames_by_id: Dictionary = {} # int -> PartyMemberFrame
var _mercenary_card: PanelContainer = null
var _mercenary_data: Dictionary = {}
var _mercenary_distance: float = 3.5


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(220, 174)

	# Integración con UIOrchestrator si existe como autoload
	if has_node("/root/UIOrchestrator"):
		var orch = get_node("/root/UIOrchestrator")
		orch.register_instance("party_frames", self)


## Inicializa o reemplaza la lista completa de miembros del grupo (hasta un máximo de 3).
func set_party_members(members: Array[Dictionary]) -> void:
	clear_party()
	var limit: int = mini(members.size(), MAX_PARTY_MEMBERS)
	for i in range(limit):
		add_party_member(members[i])


## Añade un miembro individual si no se ha alcanzado el límite de 3.
func add_party_member(member_data: Dictionary) -> PartyMemberFrame:
	if not is_instance_valid(member_list):
		return null

	if member_list.get_child_count() >= MAX_PARTY_MEMBERS:
		push_warning("[PartyFrames] Máximo de miembros alcanzado (%d)" % MAX_PARTY_MEMBERS)
		return null

	var frame := MEMBER_FRAME_SCENE.instantiate() as PartyMemberFrame
	member_list.add_child(frame)
	frame.setup(member_data)

	_frames_by_id[frame.player_id] = frame
	frame.clicked.connect(_on_frame_clicked)
	frame.hovered.connect(_on_frame_hovered)
	return frame


## Actualiza la salud de un miembro por su player_id.
func update_member_hp(player_id: int, hp: float, max_hp: float) -> void:
	if _frames_by_id.has(player_id):
		var frame: PartyMemberFrame = _frames_by_id[player_id]
		if is_instance_valid(frame):
			frame.set_hp(hp, max_hp)


## Actualiza el estado de abatido (downed) y el tiempo restante de desangrado.
func update_member_downed(player_id: int, is_downed: bool, timer_sec: float) -> void:
	if _frames_by_id.has(player_id):
		var frame: PartyMemberFrame = _frames_by_id[player_id]
		if is_instance_valid(frame):
			frame.set_downed(is_downed, timer_sec)


## Actualiza la distancia en metros entre el jugador local y el miembro del grupo.
func update_member_distance(player_id: int, dist: float) -> void:
	if _frames_by_id.has(player_id):
		var frame: PartyMemberFrame = _frames_by_id[player_id]
		if is_instance_valid(frame):
			frame.set_distance(dist)


## Actualiza el maná de un miembro por su player_id.
func update_member_mana(player_id: int, mana: float, max_mana: float) -> void:
	if _frames_by_id.has(player_id):
		var frame: PartyMemberFrame = _frames_by_id[player_id]
		if is_instance_valid(frame):
			frame.set_mana(mana, max_mana)


## Actualiza el estado explícito ('NORMAL', 'ABATIDO', 'MUERTO') de un miembro.
func update_member_status(player_id: int, status_str: String) -> void:
	if _frames_by_id.has(player_id):
		var frame: PartyMemberFrame = _frames_by_id[player_id]
		if is_instance_valid(frame):
			frame.set_status(status_str)


## Obtiene el nodo frame correspondiente a un player_id, o null si no existe.
func get_member_frame(player_id: int) -> PartyMemberFrame:
	var f = _frames_by_id.get(player_id, null)
	if f != null and is_instance_valid(f):
		return f as PartyMemberFrame
	return null


## Obtiene todos los frames activos actualmente.
func get_member_frames() -> Array[PartyMemberFrame]:
	var result: Array[PartyMemberFrame] = []
	if is_instance_valid(member_list):
		for child in member_list.get_children():
			if child is PartyMemberFrame and is_instance_valid(child):
				result.append(child)
	return result


func get_all_frames() -> Array[PartyMemberFrame]:
	return get_member_frames()


## Badge de política de botín de la escuadra ("FREE_FOR_ALL" | "ROUND_ROBIN"),
## dibujado justo encima de la lista de miembros.
var loot_policy: String = ""

func set_loot_policy(policy: String) -> void:
	loot_policy = policy.to_upper()
	var badge: PanelContainer = get_node_or_null("LootPolicyBadge")
	if badge == null:
		badge = PanelContainer.new()
		badge.name = "LootPolicyBadge"
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.add_theme_stylebox_override("panel", T.box(Color(0.05, 0.09, 0.12, 0.92), 4, 1, Color("#46e3c1")))
		var lbl := Label.new()
		lbl.name = "LootPolicyLabel"
		lbl.add_theme_font_override("font", T.font("bold"))
		lbl.add_theme_font_size_override("font_size", 9)
		lbl.add_theme_color_override("font_color", Color("#46e3c1"))
		badge.add_child(lbl)
		add_child(badge)
		badge.position = Vector2(0, -22)
	var label_text := "BOTÍN: ROUND-ROBIN (TURNOS)" if loot_policy == "ROUND_ROBIN" else "BOTÍN: LIBRE (FREE-FOR-ALL)"
	(badge.get_node("LootPolicyLabel") as Label).text = "  ◆ " + label_text + "  "


## Limpia y libera todos los frames actuales del grupo.
func clear_party() -> void:
	_frames_by_id.clear()
	if is_instance_valid(member_list):
		for child in member_list.get_children():
			child.queue_free()


func _on_frame_clicked(p_id: int) -> void:
	member_clicked.emit(p_id)


func _on_frame_hovered(p_id: int, is_hovered: bool) -> void:
	member_hovered.emit(p_id, is_hovered)


# ==============================================================================
# Fase 10 (ADR 101): Mercenario IA y Compañero de Escuadra
# ==============================================================================

## Configura o actualiza los datos del mercenario contratado.
func set_mercenary(data: Dictionary) -> void:
	_mercenary_data = data.duplicate()
	if not _mercenary_data.has("mercenary_id"):
		_mercenary_data["mercenary_id"] = 1001
	if not _mercenary_data.has("role"):
		_mercenary_data["role"] = MercenaryCodec.ROLE_GUARDIAN
	if not _mercenary_data.has("stance"):
		_mercenary_data["stance"] = MercenaryCodec.STANCE_FOLLOW
	if not _mercenary_data.has("hp_pct"):
		_mercenary_data["hp_pct"] = 100
	if not _mercenary_data.has("name"):
		var role_str = MercenaryCodec.role_to_string(int(_mercenary_data["role"]))
		_mercenary_data["name"] = "Centinela Vaelen (%s)" % role_str
	_build_or_update_mercenary_card()


func has_mercenary() -> bool:
	return not _mercenary_data.is_empty() and is_instance_valid(_mercenary_card)


func get_mercenary_data() -> Dictionary:
	return _mercenary_data


func update_mercenary_hp(hp_pct: int) -> void:
	if not has_mercenary():
		return
	_mercenary_data["hp_pct"] = clampi(hp_pct, 0, 100)
	_build_or_update_mercenary_card()


func update_mercenary_stance(stance: int) -> void:
	if not has_mercenary():
		return
	_mercenary_data["stance"] = clampi(stance, 0, MercenaryCodec.STANCE_HOLD)
	_build_or_update_mercenary_card()


func update_mercenary_distance(dist_m: float) -> void:
	_mercenary_distance = maxf(0.0, dist_m)
	if has_mercenary():
		var dist_lbl: Label = _mercenary_card.get_node_or_null("%MercDistLabel")
		if dist_lbl:
			var sprint_tag = " [SPRINT]" if _mercenary_distance > MercenaryCodec.TETHER_RADIUS_M else ""
			dist_lbl.text = "%.1fm%s" % [_mercenary_distance, sprint_tag]
			if _mercenary_distance > MercenaryCodec.TETHER_RADIUS_M:
				dist_lbl.add_theme_color_override("font_color", Color("#ffb830"))
			else:
				dist_lbl.add_theme_color_override("font_color", Color("#7f9bb3"))


func clear_mercenary() -> void:
	_mercenary_data.clear()
	if is_instance_valid(_mercenary_card):
		_mercenary_card.queue_free()
		_mercenary_card = null


func _build_or_update_mercenary_card() -> void:
	if not is_instance_valid(_mercenary_card):
		_mercenary_card = PanelContainer.new()
		_mercenary_card.name = "MercenaryCard"
		_mercenary_card.custom_minimum_size = Vector2(220, 62)
		_mercenary_card.mouse_filter = Control.MOUSE_FILTER_STOP
		_mercenary_card.add_theme_stylebox_override("panel", T.box(Color(0.04, 0.08, 0.12, 0.95), 4, 1, Color("#ffb830")))

		var vbox := VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 2)
		_mercenary_card.add_child(vbox)

		# Fila superior: Badge de rol + Nombre + Distancia
		var top_row := HBoxContainer.new()
		vbox.add_child(top_row)

		var role_badge := Label.new()
		role_badge.name = "MercRoleBadge"
		role_badge.unique_name_in_owner = true
		role_badge.add_theme_font_override("font", T.font("bold"))
		role_badge.add_theme_font_size_override("font_size", 10)
		role_badge.add_theme_color_override("font_color", Color("#3dff8a"))
		top_row.add_child(role_badge)

		var name_lbl := Label.new()
		name_lbl.name = "MercNameLabel"
		name_lbl.unique_name_in_owner = true
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.add_theme_font_override("font", T.font("bold"))
		name_lbl.add_theme_font_size_override("font_size", 10)
		name_lbl.add_theme_color_override("font_color", Color.WHITE)
		top_row.add_child(name_lbl)

		var dist_lbl := Label.new()
		dist_lbl.name = "MercDistLabel"
		dist_lbl.unique_name_in_owner = true
		dist_lbl.add_theme_font_override("font", T.font("regular"))
		dist_lbl.add_theme_font_size_override("font_size", 9)
		dist_lbl.add_theme_color_override("font_color", Color("#7f9bb3"))
		top_row.add_child(dist_lbl)

		# Barra de vida
		var hp_bar := ProgressBar.new()
		hp_bar.name = "MercHPBar"
		hp_bar.unique_name_in_owner = true
		hp_bar.custom_minimum_size = Vector2(0, 10)
		hp_bar.show_percentage = false
		hp_bar.min_value = 0
		hp_bar.max_value = 100
		hp_bar.add_theme_stylebox_override("background", T.box(Color(0.02, 0.04, 0.06, 0.8), 2, 0, Color.TRANSPARENT))
		hp_bar.add_theme_stylebox_override("fill", T.box(Color("#00f0ff"), 2, 0, Color.TRANSPARENT))
		vbox.add_child(hp_bar)

		# Fila inferior: Estado de Postura táctica e indicación de atajos [Alt+1/2/3]
		var bot_row := HBoxContainer.new()
		vbox.add_child(bot_row)

		var stance_lbl := Label.new()
		stance_lbl.name = "MercStanceLabel"
		stance_lbl.unique_name_in_owner = true
		stance_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stance_lbl.add_theme_font_override("font", T.font("bold"))
		stance_lbl.add_theme_font_size_override("font_size", 9)
		bot_row.add_child(stance_lbl)

		var cmd_hint := Label.new()
		cmd_hint.text = "[Alt+1..3]"
		cmd_hint.add_theme_font_override("font", T.font("regular"))
		cmd_hint.add_theme_font_size_override("font_size", 8)
		cmd_hint.add_theme_color_override("font_color", Color("#7f9bb3"))
		bot_row.add_child(cmd_hint)

		# Añadir a la lista de party después de los miembros
		if is_instance_valid(member_list):
			member_list.add_child(_mercenary_card)
		else:
			add_child(_mercenary_card)

	# Actualizar valores visuales
	var role_badge: Label = _mercenary_card.get_node_or_null("%MercRoleBadge")
	var name_lbl: Label = _mercenary_card.get_node_or_null("%MercNameLabel")
	var dist_lbl: Label = _mercenary_card.get_node_or_null("%MercDistLabel")
	var hp_bar: ProgressBar = _mercenary_card.get_node_or_null("%MercHPBar")
	var stance_lbl: Label = _mercenary_card.get_node_or_null("%MercStanceLabel")

	var role: int = int(_mercenary_data.get("role", MercenaryCodec.ROLE_GUARDIAN))
	var stance: int = int(_mercenary_data.get("stance", MercenaryCodec.STANCE_FOLLOW))
	var hp_pct: int = int(_mercenary_data.get("hp_pct", 100))

	if role_badge:
		match role:
			MercenaryCodec.ROLE_HEALER:
				role_badge.text = "[S] "
				role_badge.add_theme_color_override("font_color", Color("#3dff8a"))
			MercenaryCodec.ROLE_RANGER:
				role_badge.text = "[T] "
				role_badge.add_theme_color_override("font_color", Color("#c084fc"))
			_:
				role_badge.text = "[G] "
				role_badge.add_theme_color_override("font_color", Color("#ffb830"))

	if name_lbl:
		name_lbl.text = str(_mercenary_data.get("name", "Compañero IA"))

	if dist_lbl:
		var sprint_tag = " [SPRINT]" if _mercenary_distance > MercenaryCodec.TETHER_RADIUS_M else ""
		dist_lbl.text = "%.1fm%s" % [_mercenary_distance, sprint_tag]

	if hp_bar:
		hp_bar.value = hp_pct
		var fill_color = Color("#00f0ff")
		if hp_pct < 30:
			fill_color = Color("#ff3366")
		elif hp_pct < 60:
			fill_color = Color("#ffb830")
		hp_bar.add_theme_stylebox_override("fill", T.box(fill_color, 2, 0, Color.TRANSPARENT))

	if stance_lbl:
		match stance:
			MercenaryCodec.STANCE_ATTACK:
				stance_lbl.text = "ORDEN: [Alt+2] ATACAR"
				stance_lbl.add_theme_color_override("font_color", Color("#ff3366"))
			MercenaryCodec.STANCE_HOLD:
				stance_lbl.text = "ORDEN: [Alt+3] DEFENSIVA"
				stance_lbl.add_theme_color_override("font_color", Color("#ffb830"))
			_:
				stance_lbl.text = "ORDEN: [Alt+1] SEGUIR"
				stance_lbl.add_theme_color_override("font_color", Color("#00f0ff"))


## Captura de comandos tácticos con teclado [Alt+1], [Alt+2], [Alt+3]
func _unhandled_input(event: InputEvent) -> void:
	if not has_mercenary():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.alt_pressed:
			var target_stance := -1
			if event.keycode == KEY_1 or event.physical_keycode == KEY_1:
				target_stance = MercenaryCodec.STANCE_FOLLOW
			elif event.keycode == KEY_2 or event.physical_keycode == KEY_2:
				target_stance = MercenaryCodec.STANCE_ATTACK
			elif event.keycode == KEY_3 or event.physical_keycode == KEY_3:
				target_stance = MercenaryCodec.STANCE_HOLD

			if target_stance >= 0:
				var merc_id: int = int(_mercenary_data.get("mercenary_id", 0))
				var target_id: int = int(_mercenary_data.get("target_entity_id", 0))
				update_mercenary_stance(target_stance)
				mercenary_command_triggered.emit(target_stance, target_id)
				if is_inside_tree():
					if has_node("/root/NetworkManager"):
						var nm = get_node("/root/NetworkManager")
						if nm.has_method("send_mercenary_command"):
							nm.send_mercenary_command(merc_id, target_stance, target_id)
					var vp = get_viewport()
					if vp:
						vp.set_input_as_handled()
