extends Node3D

@onready var mesh_instance = $MeshInstance3D

var _mat: StandardMaterial3D = null
var _is_pulsing: bool = false
var _origin_msec: int = 0
var _configured: bool = false

var hazard_sid: int = 0
var current_phase: int = 0 # 0=Safe, 1=Warning, 2=Active
var phase_remaining_ms: int = 0
var phase_total_ms: int = 0
var last_sync_time: int = 0
var is_authoritative_synced: bool = false

func _ready():
	set_process(true)
	if has_node("/root/NetworkManager"):
		var net = get_node("/root/NetworkManager")
		if not net.hazard_sync_received.is_connected(_on_hazard_sync):
			net.hazard_sync_received.connect(_on_hazard_sync)
	if mesh_instance:
		var base_mat = mesh_instance.get_active_material(0)
		if base_mat:
			_mat = base_mat.duplicate() as StandardMaterial3D
		else:
			_mat = StandardMaterial3D.new()
		_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mesh_instance.set_surface_override_material(0, _mat)
		_mat.albedo_color = Color(0.9, 0.1, 0.1, 0.08)
		_mat.emission_enabled = false

func setup(p_offset: float = 0.0, is_pulsing: bool = true):
	_is_pulsing = is_pulsing
	_configured = true
	
	if not _mat and mesh_instance:
		var base_mat = mesh_instance.get_active_material(0)
		_mat = base_mat.duplicate() if base_mat else StandardMaterial3D.new()
		_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mesh_instance.set_surface_override_material(0, _mat)

	if not _is_pulsing:
		# Static Hazard: permanently ON
		if _mat:
			_mat.albedo_color = Color(1.0, 0.15, 0.15, 0.65)
			_mat.emission_enabled = true
			_mat.emission = Color(1.0, 0.1, 0.1)
			_mat.emission_energy_multiplier = 1.5
		return

	# Pulsing Hazard: Ciclo autoritativo de 5.0s sincronizado con Rust ECS:
	# [0.0, 2.0): ON (Daño activo). Parpadeo carmesí ardiente HDR.
	# [2.0, 4.2): OFF (Recarga segura, Daño 0). Contorno tenue translúcido.
	# [4.2, 5.0): TELEGRAPH (Aviso previo a detonación). Parpadeo ámbar.
	var norm_offset = fposmod(p_offset, 5.0)
	_origin_msec = Time.get_ticks_msec() - int(norm_offset * 1000.0)
	print("[HazardIndicator] Setup sync: offset %.2f s (origin_msec: %d, scale: %.2f)" % [norm_offset, _origin_msec, scale.x])

func _on_hazard_sync(p_sid: int, p_phase: int, p_remaining: int, p_total: int) -> void:
	if hazard_sid != 0 and p_sid != hazard_sid:
		return
	current_phase = p_phase
	phase_remaining_ms = p_remaining
	phase_total_ms = p_total
	last_sync_time = Time.get_ticks_msec()
	is_authoritative_synced = true

func _process(_delta):
	if not _configured or not _mat: return
	if not _is_pulsing: return

	var now = Time.get_ticks_msec()
	
	if is_authoritative_synced:
		var elapsed_since_sync = now - last_sync_time
		var rem_ms = max(0, phase_remaining_ms - elapsed_since_sync)
		
		# Sincronización estricta por fases de Rust ECS
		if current_phase == 2: # Active (2.0s daño activo)
			var blink = 0.6 + 0.4 * sin(float(now) * 0.024)
			_mat.emission_enabled = true
			_mat.emission = Color(1.0, 0.12, 0.08)
			_mat.emission_energy_multiplier = 1.8 + 2.2 * blink
			_mat.albedo_color = Color(1.0, 0.08, 0.08, 0.55 + 0.35 * blink)
		elif current_phase == 1: # Warning (1.0s aviso previo telegrafiado)
			var warn_blink = 0.5 + 0.5 * sin(float(now) * 0.02)
			_mat.emission_enabled = true
			_mat.emission = Color(1.0, 0.5, 0.05)
			_mat.emission_energy_multiplier = 1.0 + 1.8 * warn_blink
			_mat.albedo_color = Color(1.0, 0.45, 0.05, 0.25 + 0.35 * warn_blink)
		else: # Safe (2.0s daño 0)
			_mat.emission_enabled = false
			_mat.emission_energy_multiplier = 0.0
			_mat.albedo_color = Color(0.6, 0.12, 0.12, 0.08)
		return

	# Fallback local determinista si no hay conexión al servidor
	var elapsed_sec = fposmod(float(now - _origin_msec) / 1000.0, 5.0)

	if elapsed_sec < 2.0:
		# --- FASE 1: ACTIVA / ON (0.0s a 2.0s) -> DAÑO AUTORITATIVO ACTIVO ---
		# Parpadeo estroboscópico de peligro en rojo ardiente carmesí (frecuencia ~8 Hz)
		var blink = 0.6 + 0.4 * sin(elapsed_sec * 24.0)
		_mat.emission_enabled = true
		_mat.emission = Color(1.0, 0.12, 0.08)
		_mat.emission_energy_multiplier = 1.8 + 2.2 * blink # Destello HDR de 1.8 a 4.0
		_mat.albedo_color = Color(1.0, 0.08, 0.08, 0.55 + 0.35 * blink)
	elif elapsed_sec < 4.0:
		# --- FASE 2: APAGADA / OFF (2.0s a 4.0s) -> DAÑO 0 (ZONA SEGURA) ---
		# Contorno apagado y translúcido sin emisión
		_mat.emission_enabled = false
		_mat.emission_energy_multiplier = 0.0
		_mat.albedo_color = Color(0.6, 0.12, 0.12, 0.08)
	else:
		# --- FASE 3: TELEGRAFO / PRE-DETONACIÓN (4.0s a 5.0s) -> AVISO ---
		# Parpadeo de advertencia en ámbar/naranja (1.0s antes de encender)
		var warn_blink = 0.5 + 0.5 * sin((elapsed_sec - 4.0) * 20.0)
		_mat.emission_enabled = true
		_mat.emission = Color(1.0, 0.5, 0.05)
		_mat.emission_energy_multiplier = 1.0 + 1.8 * warn_blink
		_mat.albedo_color = Color(1.0, 0.45, 0.05, 0.25 + 0.35 * warn_blink)
