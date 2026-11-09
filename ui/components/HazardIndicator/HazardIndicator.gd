extends Node3D

@onready var mesh_instance = $MeshInstance3D

func _ready():
	# Esperar a que World.gd llame a setup(offset) para sincronizar
	if mesh_instance:
		var mat = mesh_instance.get_active_material(0)
		if mat:
			# Inicialmente invisible hasta recibir el offset
			mat = mat.duplicate()
			mesh_instance.set_surface_override_material(0, mat)
			mat.albedo_color.a = 0.0
			mat.emission_enabled = false

func setup(p_offset: float = 0.0, is_pulsing: bool = true):
	if mesh_instance:
		var mat = mesh_instance.get_active_material(0)
		if mat:
			mat = mat.duplicate()
			mesh_instance.set_surface_override_material(0, mat)
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			if not is_pulsing:
				# Static Hazard: permanently ON
				mat.albedo_color = Color(1.0, 0.15, 0.15, 0.6)
				mat.emission_enabled = true
				mat.emission = Color(1.0, 0.1, 0.1)
				mat.emission_energy_multiplier = 1.2
				return

			var norm_offset = fposmod(p_offset, 5.0)
			print("[HazardIndicator] Syncing pulse. Offset: %.2f (Norm: %.2f), Scale: %.2f" % [p_offset, norm_offset, scale.x])
			_start_synchronized_pulse(mat, norm_offset)
		else:
			push_error("[HazardIndicator] No material found on MeshInstance3D!")

func _start_synchronized_pulse(mat: Material, offset: float):
	# Match server 5s cycle: 0-2s ON, 2-5s OFF
	_pulse_cycle_sync(mat, offset)

func _pulse_cycle_sync(mat, offset: float):
	if !is_inside_tree() or !is_instance_valid(mat): return
	var tween = create_tween()
	
	# Ciclo autoritativo de 5s sincronizado con Rust ECS:
	# - Fase de Recarga / Apagado (3.0s): Daño 0, contorno tenue y seguro (alpha 0.08, sin emisión)
	# - Fase Activa / Detonación (2.0s): Daño activo, fuego carmesí ardiente (alpha 0.85, emisión HDR 2.5)
	if offset < 3.0:
		var remaining_safe = 3.0 - offset
		mat.emission_enabled = false
		mat.albedo_color = Color(0.9, 0.15, 0.15, 0.08)
		mat.emission_energy_multiplier = 0.0
		
		tween.tween_interval(remaining_safe)
		tween.tween_callback(func():
			if is_instance_valid(mat):
				mat.emission_enabled = true
				mat.emission = Color(1.0, 0.1, 0.1)
				mat.albedo_color = Color(1.0, 0.1, 0.1, 0.85)
				mat.emission_energy_multiplier = 2.5
		)
		tween.tween_interval(2.0)
	else:
		var remaining_active = 5.0 - offset
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.1, 0.1)
		mat.albedo_color = Color(1.0, 0.1, 0.1, 0.85)
		mat.emission_energy_multiplier = 2.5
		tween.tween_interval(remaining_active)
	
	tween.finished.connect(func(): _pulse_cycle_sync(mat, 0.0))
