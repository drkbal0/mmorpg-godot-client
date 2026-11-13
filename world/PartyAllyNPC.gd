extends Area3D

## PartyAllyNPC.gd — Aliado de escuadra local para pruebas de grupo (Party Frames + ADR 100).
##
## Un NPC amistoso que acepta automáticamente la invitación de grupo (por proximidad
## o con [F]). Si `is_downed` está activo entra en el grupo "downed_allies" para que
## ReviveInteraction le dé PRIORIDAD 1 a la reanimación asistida de 6 s, y corre un
## temporizador de desangrado de 30 s (en bucle: es un maniquí de entrenamiento).

const Codec = preload("res://shared-core/ExtractionReviveCodec.gd")

signal join_requested(ally: Area3D)
signal revived(ally: Area3D)
signal state_changed(ally: Area3D)

var ally_name: String = "Aliado"
var role: String = "warrior"
var level: int = 1
var max_hp: float = 1000.0
var hp: float = 1000.0
var session_id: int = 0
var in_party: bool = false

var is_downed: bool = false
var bleedout_remaining: float = 0.0
var revive_progress: float = 0.0 # 0..1
var is_being_revived: bool = false

var mesh: MeshInstance3D = null


func setup(p_name: String, p_role: String, p_level: int, p_max_hp: float, p_hp: float, p_sid: int, downed: bool = false) -> void:
	ally_name = p_name
	role = p_role
	level = p_level
	max_hp = p_max_hp
	hp = p_hp
	session_id = p_sid
	set_meta("session_id", p_sid)
	set_meta("local_mock", true) # sin servidor: la reanimación se simula en cliente
	set_meta("archetype_level", p_level)
	set_meta("archetype_hostile", false)
	set_meta("archetype_max_hp", p_max_hp)
	if downed:
		set_downed(true)


func set_downed(downed: bool) -> void:
	is_downed = downed
	if downed:
		hp = 0.0
		bleedout_remaining = Codec.BLEEDOUT_SEC
		revive_progress = 0.0
		add_to_group("downed_allies")
	else:
		bleedout_remaining = 0.0
		is_being_revived = false
		if is_in_group("downed_allies"):
			remove_from_group("downed_allies")
	_apply_pose()
	state_changed.emit(self)


## Postura visual: abatido = cápsula acostada a ras de suelo.
func _apply_pose() -> void:
	if mesh == null:
		return
	if is_downed:
		mesh.rotation_degrees = Vector3(90.0, 0.0, 0.0)
		mesh.position = Vector3(0.0, -0.6, 0.0)
	else:
		mesh.rotation_degrees = Vector3.ZERO
		mesh.position = Vector3.ZERO


## [F] sobre un aliado de pie (o fallback de proximidad): acepta la invitación.
func interact(_player: Node) -> void:
	if not in_party:
		join_requested.emit(self)


## Canalización local de reanimación (6 s). Devuelve true al completarse.
func advance_revive(delta: float) -> bool:
	if not is_downed:
		return false
	is_being_revived = true
	revive_progress = minf(revive_progress + delta / Codec.REVIVE_CHANNEL_SEC, 1.0)
	if revive_progress >= 1.0:
		complete_revive()
		return true
	return false


func cancel_revive() -> void:
	is_being_revived = false
	revive_progress = 0.0


func complete_revive() -> void:
	hp = roundf(max_hp * 0.3)
	set_downed(false)
	revived.emit(self)


func _process(delta: float) -> void:
	# ADR 100: el desangrado se pausa mientras alguien canaliza la reanimación.
	if is_downed and not is_being_revived:
		bleedout_remaining -= delta
		if bleedout_remaining <= 0.0:
			# Maniquí de entrenamiento: el contador se reinicia en vez de eliminarlo.
			bleedout_remaining = Codec.BLEEDOUT_SEC
