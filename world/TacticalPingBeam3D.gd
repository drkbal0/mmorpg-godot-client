extends Node3D
class_name TacticalPingBeam3D

## TacticalPingBeam3D.gd — Marcador táctico en el mundo 3D (Phase 9.5, ADR 097).
## Pilar de luz vertical + anillo en el suelo + luz puntual en la coordenada
## del terreno donde se confirmó el ping (0x1A TACTICAL_PING).

const PING_COLORS := [
	Color("#facc15"), # 0 MISSING ?? (Yellow)
	Color("#ff3344"), # 1 DANGER (Red Alert)
	Color("#0284c7"), # 2 ASSIST (Blue)
	Color("#10b981"), # 3 ON_MY_WAY (Green)
]

@export var ping_type: int = 0
@export var beam_height: float = 16.0

var _ring: MeshInstance3D
var _t: float = 0.0


func _ready() -> void:
	var col: Color = PING_COLORS[clampi(ping_type, 0, PING_COLORS.size() - 1)]

	var beam := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.10
	cyl.bottom_radius = 0.22
	cyl.height = beam_height
	beam.mesh = cyl
	beam.position.y = beam_height * 0.5
	beam.material_override = _emissive(col, 0.55, 4.0)
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beam)

	var core := MeshInstance3D.new()
	var core_mesh := CylinderMesh.new()
	core_mesh.top_radius = 0.035
	core_mesh.bottom_radius = 0.06
	core_mesh.height = beam_height
	core.mesh = core_mesh
	core.position.y = beam_height * 0.5
	core.material_override = _emissive(col.lightened(0.6), 0.95, 8.0)
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(core)

	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.9
	torus.outer_radius = 1.15
	_ring.mesh = torus
	_ring.position.y = 0.05
	_ring.material_override = _emissive(col, 0.85, 3.0)
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)

	var light := OmniLight3D.new()
	light.light_color = col
	light.light_energy = 2.5
	light.omni_range = 7.0
	light.position.y = 1.0
	add_child(light)


func _process(delta: float) -> void:
	_t += delta
	if _ring:
		var s := 1.0 + 0.25 * sin(_t * TAU * 1.2)
		_ring.scale = Vector3(s, 1.0, s)


static func _emissive(col: Color, alpha: float, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(col, alpha)
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = energy
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m
