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
