@tool
extends Control
class_name PartyFrames

## Contenedor de Party Frames para MMORPG (HUD de Grupo).
## Aloja hasta 3 marcos de miembros del grupo en un VBoxContainer vertical,
## gestionando la sincronización de vida, maná, estado abatido, distancias y clics.

const T = preload("res://ui/hud_tokens.gd")
const PartyMemberFrame = preload("res://ui/components/PartyFrames/PartyMemberFrame.gd")
const MEMBER_FRAME_SCENE = preload("res://ui/components/PartyFrames/PartyMemberFrame.tscn")
const MAX_PARTY_MEMBERS := 3

signal member_clicked(player_id: int)
signal member_hovered(player_id: int, is_hovered: bool)

@onready var member_list: VBoxContainer = %MemberList

var _frames_by_id: Dictionary = {} # int -> PartyMemberFrame


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
