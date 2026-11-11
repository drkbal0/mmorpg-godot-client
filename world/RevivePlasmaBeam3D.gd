extends Node3D
class_name RevivePlasmaBeam3D

## RevivePlasmaBeam3D.gd — Haz médico de plasma verde entre reanimador y abatido
## (Fase 9.7, ADR 100). Se re-orienta cada frame entre los dos nodos, pulsa con
## el progreso de canalización y añade luces en ambos extremos.

const COLOR_PLASMA := Color("#3dff8a")

var source: Node3D = null
var target: Node3D = null
## Pecho del reanimador arrodillado (origen del CharacterBody en el centro de la cápsula).
var source_offset := Vector3(0, 0.25, 0)
## Torso del abatido tendido en el suelo.
var target_offset := Vector3(0, 0.05, 0)
var progress: float = 0.0

var _beam: MeshInstance3D
var _core: MeshInstance3D
var _glow: MeshInstance3D
var _mat: StandardMaterial3D
var _src_light: OmniLight3D
var _dst_light: OmniLight3D
var _t := 0.0


func _ready() -> void:
	_mat = _emissive(COLOR_PLASMA, 0.6, 5.0)
	_glow = _make_cyl(0.30, _emissive(COLOR_PLASMA, 0.16, 2.0))
	_beam = _make_cyl(0.13, _mat)
	_core = _make_cyl(0.035, _emissive(Color(0.85, 1.0, 0.9), 0.95, 9.0))
	_src_light = _make_light()
	_dst_light = _make_light()
	_update_geometry()


func setup(p_source: Node3D, p_target: Node3D) -> void:
	source = p_source
	target = p_target
	_update_geometry()


func get_length() -> float:
	if not _endpoints_valid():
		return 0.0
	return (source.global_position + source_offset).distance_to(target.global_position + target_offset)


func _endpoints_valid() -> bool:
	return is_instance_valid(source) and is_instance_valid(target) and source.is_inside_tree() and target.is_inside_tree()


func _process(delta: float) -> void:
	_t += delta
	_update_geometry()
	if _mat:
		var k := 0.5 + 0.5 * sin(_t * TAU * (2.0 + 4.0 * progress))
		_mat.emission_energy_multiplier = 3.5 + 3.0 * k


func _update_geometry() -> void:
	if _beam == null or not _endpoints_valid() or not is_inside_tree():
		return
	var a := source.global_position + source_offset
	var b := target.global_position + target_offset
	var len := a.distance_to(b)
	if len < 0.01:
		return
	global_position = (a + b) * 0.5
	var dir := (b - a) / len
	# El eje Y del cilindro se alinea con el segmento a→b.
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var x := up.cross(dir).normalized()
	var z := x.cross(dir).normalized()
	global_basis = Basis(x, dir, z)
	for m in [_glow, _beam, _core]:
		(m.mesh as CylinderMesh).height = len
	_src_light.global_position = a
	_dst_light.global_position = b


func _make_cyl(r: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = r
	cyl.bottom_radius = r
	cyl.height = 1.0
	cyl.radial_segments = 12
	mi.mesh = cyl
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _make_light() -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = COLOR_PLASMA
	l.light_energy = 2.4
	l.omni_range = 3.5
	add_child(l)
	return l


static func _emissive(col: Color, alpha: float, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(col, alpha)
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = energy
	return m
