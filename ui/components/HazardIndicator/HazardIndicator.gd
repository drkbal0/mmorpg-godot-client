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

func setup(p_offset: float):
	if mesh_instance:
		var mat = mesh_instance.get_active_material(0)
		if mat:
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			print("[HazardIndicator] Syncing pulse. Offset: %.2f, Scale: %.2f" % [p_offset, scale.x])
			_start_synchronized_pulse(mat, p_offset)
		else:
			push_error("[HazardIndicator] No material found on MeshInstance3D!")

func _start_synchronized_pulse(mat: Material, offset: float):
	# Match server 5s cycle: 0-2s ON, 2-5s OFF
	_pulse_cycle_sync(mat, offset)

func _pulse_cycle_sync(mat, offset: float):
	if !is_inside_tree() or !is_instance_valid(mat): return
	var tween = create_tween()
	
	if offset < 2.0:
		# Estamos en fase ON. Duración restante: 2.0 - offset
		var remaining_on = 2.0 - offset
		mat.emission_enabled = true
		mat.emission = Color(1, 0, 0)
		mat.albedo_color = Color(1, 0, 0, 0.7)
		mat.emission_energy_multiplier = 1.5
		
		# Solo hacemos el desvanecimiento al final si queda tiempo
		var fade_time = min(0.2, remaining_on)
		tween.tween_interval(max(0.0, remaining_on - fade_time))
		tween.tween_property(mat, "albedo_color", Color(1, 0, 0, 0.05), fade_time)
		tween.parallel().tween_property(mat, "emission_energy_multiplier", 0.0, fade_time)
		tween.tween_interval(3.0) # Fase OFF completa
	else:
		# Estamos en fase OFF. Duración restante: 3.0 - (offset - 2.0)
		var remaining_off = 5.0 - offset
		mat.emission_enabled = false
		mat.albedo_color = Color(1, 0, 0, 0.05)
		mat.emission_energy_multiplier = 0.0
		tween.tween_interval(max(0.0, remaining_off))
	
	# Al terminar, entrar en el bucle normal de 0
	tween.finished.connect(func(): _pulse_cycle_sync(mat, 0.0))
