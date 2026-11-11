extends Node3D
class_name MobileExtractionConvoy

## MobileExtractionConvoy.gd — Convoy de extracción móvil (Fase 9.7, ADR 099).
##
## Representación 3D del componente Rust `MovingExtractionZone`:
##   * Transporte blindado procedural (casco, cabina, 6 ruedas, blindaje lateral)
##     con baliza vertical de luz y luz puntual.
##   * Anillos concéntricos 3D (TorusMesh) como nodo hijo nativo "CaptureRings":
##     se mueven con el convoy. Cian #00f0ff en normal (r = 10 m) y ámbar/rojo en
##     pánico (r = 4 m, combate a <= 15 m del convoy).
##   * Interpola hacia la posición autoritativa (0x1C a 20 Hz) para que el render a
##     144 FPS no tiemble; la cuenta atrás se descuenta localmente entre syncs para
##     mostrar décimas suaves y se re-sincroniza con cada paquete.

const Codec = preload("res://shared-core/ExtractionReviveCodec.gd")

const COLOR_NORMAL := Color("#00f0ff")
const COLOR_PANIC := Color("#ff6a1a") # ámbar/rojo
const COLOR_PANIC_HOT := Color("#ff2a2a")
const RING_FRACTIONS := [1.0, 0.66, 0.33]
## Velocidad de convergencia de la interpolación (1/s).
const FOLLOW_RATE := 12.0

signal countdown_changed(remaining_ms: float)
signal panic_changed(is_panic: bool)

@export var beacon_id: int = 0
@export var radius: float = Codec.CONVOY_RADIUS_NORMAL:
	set(v):
		radius = maxf(v, 0.1)
		_rebuild_rings()
@export var is_panic: bool = false:
	set(v):
		var changed := v != is_panic
		is_panic = v
		radius = Codec.CONVOY_RADIUS_PANIC if v else Codec.CONVOY_RADIUS_NORMAL
		_apply_ring_color()
		if changed:
			panic_changed.emit(v)

var players_inside_count: int = 0
## Cuenta atrás interpolada localmente (ms). 0 = nadie canalizando.
var remaining_ms: float = 0.0
var server_position: Vector3 = Vector3.ZERO
var _has_server_pos := false
var _rings_root: Node3D = null
var _rings: Array[MeshInstance3D] = []
var _disc: MeshInstance3D = null
var _ring_mat: StandardMaterial3D = null
var _beacon_mat: StandardMaterial3D = null
var _beacon_light: OmniLight3D = null
var _t := 0.0


func _ready() -> void:
	_build_vehicle()
	_build_beacon()
	_rings_root = Node3D.new()
	_rings_root.name = "CaptureRings"
	add_child(_rings_root)
	_ring_mat = _emissive(COLOR_NORMAL, 0.85, 3.5)
	_rebuild_rings()
	_apply_ring_color()


## Aplica un paquete 0x1C decodificado (ExtractionReviveCodec.decode_beacon).
func apply_beacon_sync(b: Dictionary) -> void:
	if b.is_empty():
		return
	beacon_id = int(b.get("beacon_id", beacon_id))
	server_position = b.get("pos", server_position)
	if not _has_server_pos:
		global_position = server_position
		_has_server_pos = true
	is_panic = bool(b.get("is_panic", false))
	radius = float(b.get("radius", radius))
	players_inside_count = int(b.get("players_inside_count", 0))
	remaining_ms = float(b.get("remaining_ms", 0))
	countdown_changed.emit(remaining_ms)


func _process(delta: float) -> void:
	_t += delta
	if _has_server_pos:
		global_position = global_position.lerp(server_position, 1.0 - exp(-FOLLOW_RATE * delta))
	if remaining_ms > 0.0:
		remaining_ms = maxf(remaining_ms - delta * 1000.0, 0.0)
		countdown_changed.emit(remaining_ms)
	# Pulso de los anillos: lento en normal, rápido y rojo-ámbar en pánico.
	if _ring_mat:
		var hz := 3.0 if is_panic else 0.8
		var k := 0.5 + 0.5 * sin(_t * TAU * hz)
		if is_panic:
			_ring_mat.emission = COLOR_PANIC.lerp(COLOR_PANIC_HOT, k)
		_ring_mat.emission_energy_multiplier = 2.6 + 1.6 * k
	if _beacon_light:
		_beacon_light.light_energy = 2.2 + 1.2 * (0.5 + 0.5 * sin(_t * TAU * (2.0 if is_panic else 0.7)))


func get_ring_color() -> Color:
	return COLOR_PANIC if is_panic else COLOR_NORMAL


func get_ring_count() -> int:
	return _rings.size()


## Radio exterior real del anillo mayor (centro del tubo del toro).
func get_outer_ring_radius() -> float:
	if _rings.is_empty():
		return 0.0
	var t: TorusMesh = _rings[0].mesh
	return (t.inner_radius + t.outer_radius) * 0.5


func get_countdown_text() -> String:
	return Codec.format_countdown(remaining_ms)


## ¿El punto está dentro de la zona? Usa la misma histéresis 10 m / 11.5 m que Rust.
func is_inside(world_point: Vector3, was_inside: bool) -> bool:
	var d := Vector2(world_point.x - global_position.x, world_point.z - global_position.z).length()
	return Codec.hysteresis_inside(was_inside, d, radius)


# ---------------------------------------------------------------------------
# Construcción procedural
# ---------------------------------------------------------------------------

func _rebuild_rings() -> void:
	if _rings_root == null:
		return
	for r in _rings:
		r.queue_free()
	_rings.clear()
	if _disc:
		_disc.queue_free()
		_disc = null
	for f in RING_FRACTIONS:
		var mi := MeshInstance3D.new()
		var torus := TorusMesh.new()
		var rr: float = radius * f
		var tube := 0.09 if f == 1.0 else 0.06
		torus.inner_radius = rr - tube
		torus.outer_radius = rr + tube
		torus.rings = 96
		torus.ring_segments = 8
		mi.mesh = torus
		mi.position.y = 0.06
		mi.material_override = _ring_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_rings_root.add_child(mi)
		_rings.append(mi)
	# Disco translúcido del área de captura.
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = 0.02
	cyl.radial_segments = 64
	disc.mesh = cyl
	disc.position.y = 0.03
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.albedo_color = Color(get_ring_color(), 0.10)
	disc.material_override = dm
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rings_root.add_child(disc)
	_disc = disc


func _apply_ring_color() -> void:
	if _ring_mat == null:
		return
	var c := get_ring_color()
	_ring_mat.albedo_color = Color(c, 0.85)
	_ring_mat.emission = c
	if _beacon_mat:
		_beacon_mat.albedo_color = Color(c, 0.55)
		_beacon_mat.emission = c
	if _beacon_light:
		_beacon_light.light_color = c
	if _disc and _disc.material_override:
		(_disc.material_override as StandardMaterial3D).albedo_color = Color(c, 0.10)


func _build_vehicle() -> void:
	var hull := StandardMaterial3D.new()
	hull.albedo_color = Color(0.22, 0.26, 0.3)
	hull.metallic = 0.6
	hull.roughness = 0.45
	var armor := StandardMaterial3D.new()
	armor.albedo_color = Color(0.36, 0.38, 0.33)
	armor.metallic = 0.4
	armor.roughness = 0.6
	var tyre := StandardMaterial3D.new()
	tyre.albedo_color = Color(0.06, 0.06, 0.07)
	tyre.roughness = 0.9
	var glass := _emissive(COLOR_NORMAL, 0.9, 1.2)

	var body := Node3D.new()
	body.name = "ArmoredConvoy"
	add_child(body)
	_box(body, Vector3(0, 1.15, 0), Vector3(2.6, 1.3, 5.4), hull)          # casco
	_box(body, Vector3(0, 2.05, 1.7), Vector3(2.3, 0.9, 1.7), hull)        # cabina
	_box(body, Vector3(0, 2.1, 2.56), Vector3(2.0, 0.45, 0.04), glass)     # parabrisas
	_box(body, Vector3(0, 1.95, -1.1), Vector3(2.4, 0.5, 2.6), armor)      # módulo de carga
	for side in [-1.0, 1.0]:
		_box(body, Vector3(side * 1.36, 1.1, 0), Vector3(0.12, 0.9, 4.8), armor) # faldones blindados
		for z in [-1.8, 0.0, 1.8]:
			var wheel := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.55
			cyl.bottom_radius = 0.55
			cyl.height = 0.4
			wheel.mesh = cyl
			wheel.material_override = tyre
			wheel.rotation_degrees = Vector3(0, 0, 90)
			wheel.position = Vector3(side * 1.25, 0.55, z)
			wheel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			body.add_child(wheel)
	var plate := Label3D.new()
	plate.text = "CONVOY · EXTRACCIÓN"
	plate.font_size = 48
	plate.pixel_size = 0.006
	plate.outline_size = 10
	plate.modulate = Color("#e6fbff")
	plate.position = Vector3(0, 1.4, 2.72)
	body.add_child(plate)


func _build_beacon() -> void:
	_beacon_mat = _emissive(COLOR_NORMAL, 0.55, 4.0)
	var mast := MeshInstance3D.new()
	mast.name = "BeaconMast"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.08
	cyl.bottom_radius = 0.2
	cyl.height = 14.0
	mast.mesh = cyl
	mast.position = Vector3(0, 2.5 + 7.0, -1.1)
	mast.material_override = _beacon_mat
	mast.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mast)
	var core := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.03
	cm.bottom_radius = 0.06
	cm.height = 14.0
	core.mesh = cm
	core.position = mast.position
	core.material_override = _emissive(Color(0.85, 1.0, 1.0), 0.95, 8.0)
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(core)
	_beacon_light = OmniLight3D.new()
	_beacon_light.name = "BeaconLight"
	_beacon_light.light_color = COLOR_NORMAL
	_beacon_light.light_energy = 2.8
	_beacon_light.omni_range = 12.0
	_beacon_light.position = Vector3(0, 3.4, -1.1)
	add_child(_beacon_light)


func _box(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)
	return mi


static func _emissive(col: Color, alpha: float, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(col, alpha)
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = energy
	return m
