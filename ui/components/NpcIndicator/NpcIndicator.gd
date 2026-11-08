extends Node3D

@onready var aggro_mesh = get_node_or_null("AggroMesh")
@onready var attack_mesh = get_node_or_null("AttackMesh")

func _ready():
	# Initial visibility
	if aggro_mesh: aggro_mesh.visible = false
	if attack_mesh: attack_mesh.visible = false

func setup(aggro_radius: float, attack_radius: float):
	if aggro_mesh:
		aggro_mesh.scale = Vector3(aggro_radius, 1.0, aggro_radius)
		aggro_mesh.visible = aggro_radius > 0
	if attack_mesh:
		attack_mesh.scale = Vector3(attack_radius, 1.0, attack_radius)
		attack_mesh.visible = attack_radius > 0
