extends Control
class_name KiAuraProjector

## KiAuraProjector.gd — Proyección screen-space de auras de Ki (Phase 9.6, ADR 098).
##
## Va en el MISMO CanvasLayer que KiSpectralVision, como hermano posterior al
## ShaderRect: el post-proceso lee la pantalla antes de que este nodo dibuje,
## así que las auras conservan su color puro sobre el mundo desaturado, mientras
## el HUD (CanvasLayer superior) queda intacto.


## Frecuencia del pulso; se sincroniza con KiSpectralVision.get_pulse_frequency().
var pulse_hz: float = 1.2
var _t: float = 0.0
## [{"node": Node3D, "color": Color, "label": String, "radius": float, "height": float}]
var _targets: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func track(node: Node3D, color: Color, label: String, radius_m: float = 1.1, height_m: float = 1.0) -> void:
	_targets.append({"node": node, "color": color, "label": label, "radius": radius_m, "height": height_m})


func clear_targets() -> void:
	_targets.clear()
	queue_redraw()


func tracked_count() -> int:
	return _targets.size()


## Número de auras dentro del frustum en el último frame (para auditoría).
var visible_count: int = 0


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	visible_count = 0
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var pulse := 0.5 + 0.5 * sin(TAU * pulse_hz * _t)
	var font := get_theme_default_font()
	for t in _targets:
		var node: Node3D = t["node"]
		if not is_instance_valid(node) or not node.is_inside_tree():
			continue
		var center3d: Vector3 = node.global_position + Vector3(0, float(t["height"]), 0)
		if cam.is_position_behind(center3d):
			continue
		var c := cam.unproject_position(center3d)
		var edge := cam.unproject_position(center3d + cam.global_transform.basis.x * float(t["radius"]))
		var r := maxf(8.0, c.distance_to(edge))
		var col: Color = t["color"]
		visible_count += 1

		# Halo volumétrico: capas concéntricas con alfa decreciente.
		for i in range(10, 0, -1):
			var k := float(i) / 10.0
			draw_circle(c, r * (0.55 + 0.95 * k), Color(col, 0.035 + 0.02 * pulse))
		# Núcleo de silueta.
		draw_circle(c, r * 0.5, Color(col.lightened(0.35), 0.22 + 0.12 * pulse))
		# Anillo de resonancia que respira con el pulso de combate.
		draw_arc(c, r * (1.15 + 0.25 * pulse), 0.0, TAU, 64, Color(col, 0.85 - 0.45 * pulse), 2.5, true)
		draw_arc(c, r * 0.95, 0.0, TAU, 64, Color(col.lightened(0.5), 0.9), 1.5, true)

		# Etiqueta del atributo dominante.
		var label: String = t["label"]
		var fs := 12
		var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		# Debajo del aura: arriba ya están los nameplates de la entidad.
		var lp := Vector2(c.x - tw * 0.5, c.y + r * 1.55 + 14.0)
		draw_rect(Rect2(lp + Vector2(-6, -13), Vector2(tw + 12, 18)), Color(0.02, 0.03, 0.05, 0.75))
		draw_rect(Rect2(lp + Vector2(-6, -13), Vector2(tw + 12, 18)), Color(col, 0.9), false, 1.0)
		draw_string(font, lp, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col.lightened(0.2))
