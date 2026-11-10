extends SubViewport
## LivePortrait3D - Renderizador 3D en vivo para el retrato circular del HUD (ADR 095)
## Genera una textura 256x256 con fondo transparente, estudio de 3 luces (Key, Fill, Rim)
## y modelo 3D del busto del jugador con animaciones sutiles de respiración y feedback de daño.

@export var studio_key_color: Color = Color("#90e0ef")
@export var studio_fill_color: Color = Color("#cfd8dc")
@export var studio_rim_color: Color = Color("#ffd166")

@onready var camera: Camera3D = $Camera3D
@onready var character_root: Node3D = $CharacterRoot
@onready var key_light: DirectionalLight3D = $Lights/KeyLight
@onready var fill_light: DirectionalLight3D = $Lights/FillLight
@onready var rim_light: DirectionalLight3D = $Lights/RimLight
@onready var head_mesh: MeshInstance3D = $CharacterRoot/HeadMesh
@onready var chest_mesh: MeshInstance3D = $CharacterRoot/ChestMesh
@onready var visor_mesh: MeshInstance3D = $CharacterRoot/VisorMesh

var _base_material: StandardMaterial3D = null
var _visor_material: StandardMaterial3D = null
var _damage_tween: Tween = null
var _is_flashing: bool = false


func _ready() -> void:
	size = Vector2i(256, 256)
	transparent_bg = true
	own_world_3d = true
	render_target_update_mode = SubViewport.UPDATE_ALWAYS
	
	_setup_materials()


func _setup_materials() -> void:
	# Material metálico/grafito oscuro estilo Nexo para la armadura
	_base_material = StandardMaterial3D.new()
	_base_material.albedo_color = Color("#1e293b")
	_base_material.metallic = 0.65
	_base_material.roughness = 0.28
	
	# Material emisivo cian para el visor / núcleo arcano
	_visor_material = StandardMaterial3D.new()
	_visor_material.albedo_color = Color("#38bdf8")
	_visor_material.emission_enabled = true
	_visor_material.emission = Color("#0284c7")
	_visor_material.emission_energy_multiplier = 2.4
	
	if head_mesh:
		head_mesh.material_override = _base_material
	if chest_mesh:
		chest_mesh.material_override = _base_material
	if visor_mesh:
		visor_mesh.material_override = _visor_material


func _process(_delta: float) -> void:
	if not character_root:
		return
	var t: float = Time.get_ticks_msec() * 0.001
	# Micro-respiración y bamboleo sutil de cámara/busto
	character_root.position.y = sin(t * 1.8) * 0.012
	character_root.rotation.y = sin(t * 0.8) * 0.04


## Dispara un destello visual cuando el jugador recibe daño
func flash_damage(tint: Color = Color(1.0, 0.25, 0.25), duration: float = 0.35) -> void:
	if not _base_material or _is_flashing:
		return
	_is_flashing = true
	if _damage_tween and _damage_tween.is_valid():
		_damage_tween.kill()
	
	_damage_tween = create_tween()
	var orig_color := Color("#1e293b")
	_damage_tween.tween_property(_base_material, "albedo_color", tint, 0.08)
	_damage_tween.tween_property(_base_material, "albedo_color", orig_color, duration - 0.08)
	_damage_tween.finished.connect(func() -> void: _is_flashing = false)


## Destello dorado al subir de nivel
func flash_level_up() -> void:
	if not _visor_material:
		return
	var tw := create_tween()
	var orig_vis := Color("#0284c7")
	tw.tween_property(_visor_material, "emission", Color("#f5c35b"), 0.2)
	tw.tween_property(_visor_material, "emission_energy_multiplier", 4.5, 0.2)
	tw.tween_property(_visor_material, "emission", orig_vis, 0.5)
	tw.tween_property(_visor_material, "emission_energy_multiplier", 2.4, 0.5)


## Permite enlazar un modelo o malla personalizada desde el Player principal
func set_custom_model(model_node: Node3D) -> void:
	if not character_root or not model_node:
		return
	for c in character_root.get_children():
		c.queue_free()
	var copy = model_node.duplicate()
	copy.transform = Transform3D.IDENTITY
	character_root.add_child(copy)
