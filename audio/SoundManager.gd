extends Node
## SoundManager.gd — Motor de Audio Espacial, Zero-GC Pooling y Hitmarkers (ADR 094)
## Preasigna pools fijos de AudioStreamPlayer (3D/2D/Global) en _ready().
## Cero instanciación dinámica en runtime para evitar picos de Garbage Collection.

const B = preload("res://audio/audio_buses.gd")
const AudioSettings = preload("res://audio/audio_settings.gd")

const POOL_SIZE_3D: int = 48
const POOL_SIZE_2D: int = 16
const POOL_SIZE_GLOBAL: int = 8

const MAX_VOICES_PER_CUE: int = 4
const CUE_DEBOUNCE_MS: int = 30
const MAX_DISTANCE_3D: float = 40.0

# Voces preasignadas
var _pool_3d: Array[AudioStreamPlayer3D] = []
var _voice_meta_3d: Array[Dictionary] = [] # { priority: int, started_at: int, cue: StringName }

var _pool_2d: Array[AudioStreamPlayer2D] = []
var _voice_meta_2d: Array[Dictionary] = []

var _pool_global: Array[AudioStreamPlayer] = []
var _voice_meta_global: Array[Dictionary] = []

# Control de ráfagas (voice limiting)
var _last_cue_time: Dictionary = {} # StringName -> int (msec)

# Librería de recursos en memoria
var _sfx_bank: Dictionary = {} # StringName -> AudioStream

# Estado de ducking
var _in_combat: bool = false
var _combat_timer: float = 0.0
var _ducking_tween: Tween = null

## Atenuación aplicada a la música durante el combate, relativa a la base del usuario.
const COMBAT_DUCK_DB: float = 6.0
## Volumen base del bus Music elegido por el usuario (dB). El ducking se calcula sobre él.
var user_music_base_db: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_and_apply_saved_volumes()
	_init_pools()
	_generate_procedural_fallbacks()


# -------------------------------------------------------------------------
# Boot pre-load de volúmenes (user://settings.cfg [audio])
# -------------------------------------------------------------------------

## Lee [audio] de user://settings.cfg y aplica los volúmenes a AudioServer.
## Sin archivo/sección los buses quedan en su valor por defecto (100% / 0 dB).
## Devuelve el número de buses aplicados.
func load_and_apply_saved_volumes() -> int:
	var saved := AudioSettings.load_saved_volumes()
	var applied := 0
	for bus in saved:
		if AudioSettings.apply_bus_volume(bus, saved[bus]):
			applied += 1
	var music_idx := AudioServer.get_bus_index(B.MUSIC)
	if music_idx >= 0:
		user_music_base_db = AudioServer.get_bus_volume_db(music_idx)
	return applied


## Actualiza la base de música del usuario (llamado desde OptionsMenu). Si hay combate
## activo, mantiene la atenuación relativa (base - COMBAT_DUCK_DB).
func set_user_music_base_db(db: float) -> void:
	user_music_base_db = db
	var music_idx := AudioServer.get_bus_index(B.MUSIC)
	if music_idx < 0:
		return
	if _ducking_tween and _ducking_tween.is_valid():
		_ducking_tween.kill()
	AudioServer.set_bus_volume_db(music_idx, get_music_target_db())


## Volumen objetivo actual del bus Music según el estado de combate.
func get_music_target_db() -> float:
	return user_music_base_db - COMBAT_DUCK_DB if _in_combat else user_music_base_db


func is_in_combat() -> bool:
	return _in_combat


func _init_pools() -> void:
	# 1. Pool 3D (48 voces espaciales)
	var root_3d := Node3D.new()
	root_3d.name = "Pool3D"
	add_child(root_3d)
	for i in range(POOL_SIZE_3D):
		var p := AudioStreamPlayer3D.new()
		p.name = "Voice3D_%02d" % i
		p.bus = B.SFX_WORLD
		p.max_distance = MAX_DISTANCE_3D
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.unit_size = 6.0
		root_3d.add_child(p)
		_pool_3d.append(p)
		_voice_meta_3d.append({"priority": B.Priority.WORLD, "started_at": 0, "cue": &"", "active": false})
	
	# 2. Pool 2D (16 voces para UI)
	var root_2d := Node2D.new()
	root_2d.name = "Pool2D"
	add_child(root_2d)
	for i in range(POOL_SIZE_2D):
		var p := AudioStreamPlayer2D.new()
		p.name = "Voice2D_%02d" % i
		p.bus = B.UI
		root_2d.add_child(p)
		_pool_2d.append(p)
		_voice_meta_2d.append({"priority": B.Priority.PLAYER, "started_at": 0, "cue": &"", "active": false})
	
	# 3. Pool Global / No Posicional (8 voces: hitmarkers, stingers)
	var root_global := Node.new()
	root_global.name = "PoolGlobal"
	add_child(root_global)
	for i in range(POOL_SIZE_GLOBAL):
		var p := AudioStreamPlayer.new()
		p.name = "VoiceGlobal_%02d" % i
		p.bus = B.SFX_CRITICAL
		root_global.add_child(p)
		_pool_global.append(p)
		_voice_meta_global.append({"priority": B.Priority.CRITICAL, "started_at": 0, "cue": &"", "active": false})


func _process(delta: float) -> void:
	if _in_combat:
		_combat_timer -= delta
		if _combat_timer <= 0.0:
			_set_combat_ducking(false)


# -------------------------------------------------------------------------
# Adquisición de Voces con Robo por Prioridad (Zero-GC)
# -------------------------------------------------------------------------

func play_spatial_sfx(cue: StringName, pos: Vector3, priority: int = B.Priority.WORLD, bus_override: StringName = &"") -> AudioStreamPlayer3D:
	var stream: AudioStream = _get_stream(cue)
	if not stream:
		return null
	
	# Rate-limiting / Debounce por cue
	var now := Time.get_ticks_msec()
	if _last_cue_time.has(cue) and (now - _last_cue_time[cue]) < CUE_DEBOUNCE_MS:
		return null
	
	# Conteo de instancias activas del mismo cue (máximo 4)
	var active_count := 0
	for meta in _voice_meta_3d:
		if meta["cue"] == cue:
			active_count += 1
	if active_count >= MAX_VOICES_PER_CUE:
		return null
	
	var idx := _acquire_voice_index(_pool_3d, _voice_meta_3d, priority)
	if idx < 0:
		return null # No hay voz disponible con prioridad inferior
	
	var player := _pool_3d[idx]
	if player.is_inside_tree():
		player.global_position = pos
	player.stream = stream
	player.bus = bus_override if bus_override != &"" else (B.SFX_CRITICAL if priority == B.Priority.CRITICAL else B.SFX_WORLD)
	player.pitch_scale = randf_range(0.96, 1.04)
	
	_voice_meta_3d[idx] = {"priority": priority, "started_at": now, "cue": cue, "active": true}
	_last_cue_time[cue] = now
	
	if player.is_inside_tree():
		player.play()
	return player


func play_ui_sfx(cue: StringName, priority: int = B.Priority.PLAYER) -> AudioStreamPlayer2D:
	var stream: AudioStream = _get_stream(cue)
	if not stream:
		return null
	
	var now := Time.get_ticks_msec()
	var idx := _acquire_voice_index(_pool_2d, _voice_meta_2d, priority)
	if idx < 0:
		return null
	
	var player := _pool_2d[idx]
	player.stream = stream
	player.bus = B.UI
	_voice_meta_2d[idx] = {"priority": priority, "started_at": now, "cue": cue, "active": true}
	if player.is_inside_tree():
		player.play()
	return player


func play_hitmarker(type: int) -> void:
	var cue: StringName = &"hit_confirm"
	match type:
		B.HitmarkerType.CONFIRM: cue = &"hit_confirm"
		B.HitmarkerType.CRIT: cue = &"hit_crit"
		B.HitmarkerType.KILL: cue = &"hit_kill"
		B.HitmarkerType.SHIELD: cue = &"hit_shield"
		B.HitmarkerType.HURT_SELF: cue = &"hurt_self"
	
	var stream: AudioStream = _get_stream(cue)
	if not stream:
		return
	
	var now := Time.get_ticks_msec()
	var idx := _acquire_voice_index(_pool_global, _voice_meta_global, B.Priority.CRITICAL)
	if idx < 0:
		return
	
	var player := _pool_global[idx]
	player.stream = stream
	player.bus = B.SFX_CRITICAL
	_voice_meta_global[idx] = {"priority": B.Priority.CRITICAL, "started_at": now, "cue": cue, "active": true}
	if player.is_inside_tree():
		player.play()
	
	_trigger_combat_activity()


func _acquire_voice_index(pool: Array, meta: Array, req_priority: int) -> int:
	# 1. Buscar voz no activa (playing == false y active == false)
	for i in range(pool.size()):
		var is_playing = pool[i].playing if pool[i].is_inside_tree() else false
		if not is_playing and not meta[i].get("active", false):
			return i
	
	# 2. Si el pool está lleno, robar la voz de menor prioridad más antigua
	var best_idx: int = -1
	var lowest_priority: int = req_priority # Solo robar si la voz actual tiene prioridad menor
	var oldest_time: int = 0x7FFFFFFF
	
	for i in range(pool.size()):
		var p: int = meta[i]["priority"]
		var st: int = meta[i]["started_at"]
		if p < lowest_priority:
			lowest_priority = p
			oldest_time = st
			best_idx = i
		elif p == lowest_priority and st < oldest_time and p < req_priority:
			oldest_time = st
			best_idx = i
	
	if best_idx >= 0:
		if pool[best_idx].is_inside_tree():
			pool[best_idx].stop()
		meta[best_idx]["active"] = false
		return best_idx
	
	return -1


# -------------------------------------------------------------------------
# Ducking Dinámico (ADR 094 Sección 2)
# -------------------------------------------------------------------------

func _trigger_combat_activity() -> void:
	_combat_timer = 4.0
	if not _in_combat:
		_set_combat_ducking(true)


func _set_combat_ducking(active: bool) -> void:
	_in_combat = active
	var music_bus_idx := AudioServer.get_bus_index(B.MUSIC)
	if music_bus_idx < 0:
		return
	
	if _ducking_tween and _ducking_tween.is_valid():
		_ducking_tween.kill()
	
	_ducking_tween = create_tween()
	# Relativo a la base del usuario: base - 6 dB en combate, restaurar exactamente a base al salir.
	var target_db: float = get_music_target_db()
	var dur: float = 0.12 if active else 0.6
	_ducking_tween.tween_method(func(vol: float) -> void:
		AudioServer.set_bus_volume_db(music_bus_idx, vol)
	, AudioServer.get_bus_volume_db(music_bus_idx), target_db, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


# -------------------------------------------------------------------------
# Fallback Procedural de Audio (Wav Generator sin assets externos pesados)
# -------------------------------------------------------------------------

func _generate_procedural_fallbacks() -> void:
	# Hitmarker agudo (confirm)
	_sfx_bank[&"hit_confirm"] = _create_synthetic_beep(880.0, 0.06, 0.5)
	# Golpe crítico (bip doble agudo)
	_sfx_bank[&"hit_crit"] = _create_synthetic_beep(1320.0, 0.09, 0.7)
	# Kill confirmed
	_sfx_bank[&"hit_kill"] = _create_synthetic_beep(440.0, 0.22, 0.8)
	# Impacto en escudo / barrera
	_sfx_bank[&"hit_shield"] = _create_synthetic_beep(520.0, 0.12, 0.6)
	# Daño propio (grave seco)
	_sfx_bank[&"hurt_self"] = _create_synthetic_beep(180.0, 0.14, 0.9)
	# Clics UI
	_sfx_bank[&"ui_click"] = _create_synthetic_beep(960.0, 0.03, 0.3)
	# Hazard warning riser
	_sfx_bank[&"hazard_warning"] = _create_synthetic_beep(330.0, 0.8, 0.6)

	# Tactical LoL-Style Pings
	_sfx_bank[&"ping_danger"] = _create_synthetic_beep(880.0, 0.22, 0.75)
	_sfx_bank[&"ping_missing"] = _create_synthetic_beep(587.33, 0.26, 0.65)
	_sfx_bank[&"ping_on_my_way"] = _create_synthetic_beep(659.25, 0.20, 0.70)
	_sfx_bank[&"ping_assist"] = _create_synthetic_beep(493.88, 0.24, 0.70)

	# Combat Spells & Skills
	_sfx_bank[&"spell_fireball"] = _create_synthetic_beep(280.0, 0.35, 0.70)
	_sfx_bank[&"spell_hitscan"] = _create_synthetic_beep(1200.0, 0.08, 0.60)
	_sfx_bank[&"spell_barrier"] = _create_synthetic_beep(550.0, 0.40, 0.50)
	_sfx_bank[&"ki_pulse"] = _create_synthetic_beep(220.0, 0.50, 0.45)
	_sfx_bank[&"extraction_hum"] = _create_synthetic_beep(110.0, 1.20, 0.35)


func _create_synthetic_beep(freq: float, duration_sec: float, max_vol: float = 0.5) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_8_BITS
	wav.mix_rate = 22050
	wav.stereo = false
	
	var total_samples := int(wav.mix_rate * duration_sec)
	var data := PackedByteArray()
	data.resize(total_samples)
	
	var phase_step := (TAU * freq) / float(wav.mix_rate)
	var cur_phase := 0.0
	
	for i in range(total_samples):
		var env := 1.0 - (float(i) / float(total_samples)) # Decay lineal
		var s := sin(cur_phase) * env * max_vol
		cur_phase += phase_step
		# Cuantizar a byte con signo (rango -128 a 127)
		var byte_val := int(clamp(s * 127.0, -128.0, 127.0))
		data[i] = byte_val & 0xFF
	
	wav.data = data
	return wav


func _get_stream(cue: StringName) -> AudioStream:
	if _sfx_bank.has(cue):
		return _sfx_bank[cue]
	return null
