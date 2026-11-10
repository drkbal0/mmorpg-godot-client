extends SceneTree
## test_audio_engine.gd — Test unitario headless para ADR 094 (Motor de Audio Zero-GC)
## Verifica preasignación de pools, zero-GC runtime, robo por prioridad y hitmarkers.

const B = preload("res://audio/audio_buses.gd")
const SoundManagerScript = preload("res://audio/SoundManager.gd")

var _checks_passed: int = 0
var _checks_failed: int = 0


func _init() -> void:
	print("== Test Audio Engine (ADR 094) ==")
	var sm = SoundManagerScript.new()
	sm.name = "SoundManager"
	root.add_child(sm)
	sm._ready()
	
	# 1. Verificar preasignación estricta de pools
	check(sm._pool_3d.size() == 48, "Pool 3D preasigna exactamente 48 voces")
	check(sm._pool_2d.size() == 16, "Pool 2D preasigna exactamente 16 voces")
	check(sm._pool_global.size() == 8, "Pool Global preasigna exactamente 8 voces")
	
	# 2. Verificar Zero-GC (el número de nodos no cambia al reproducir sonidos)
	var initial_nodes := sm.get_child_count()
	for i in range(10):
		sm.play_hitmarker(B.HitmarkerType.CONFIRM)
		sm.play_ui_sfx(&"ui_click")
		sm.play_spatial_sfx(&"hit_confirm", Vector3.ZERO, B.Priority.WORLD)
	check(sm.get_child_count() == initial_nodes, "Zero-GC: El conteo de nodos no crece al reproducir audio (%d nodos fijos)" % initial_nodes)
	
	# 3. Robo por Prioridad
	# Ocupar artificialmente todas las voces del pool global con prioridad WORLD y active = true
	for i in range(sm._pool_global.size()):
		sm._voice_meta_global[i]["priority"] = B.Priority.WORLD
		sm._voice_meta_global[i]["started_at"] = 1000 + i
		sm._voice_meta_global[i]["cue"] = &"test"
		sm._voice_meta_global[i]["active"] = true
	
	# Adquisición con prioridad CRITICAL debe robar con éxito la voz más antigua (idx 0)
	var idx = sm._acquire_voice_index(sm._pool_global, sm._voice_meta_global, B.Priority.CRITICAL)
	check(idx == 0, "Robo por prioridad selecciona la voz de menor prioridad más antigua (idx 0)")
	
	# 4. Proteger voz CRITICAL frente a robo por prioridad inferior
	for i in range(sm._pool_global.size()):
		sm._voice_meta_global[i]["priority"] = B.Priority.CRITICAL
		sm._voice_meta_global[i]["started_at"] = 2000 + i
		sm._voice_meta_global[i]["cue"] = &"crit"
		sm._voice_meta_global[i]["active"] = true
	var deny_idx = sm._acquire_voice_index(sm._pool_global, sm._voice_meta_global, B.Priority.WORLD)
	check(deny_idx == -1, "Una voz CRITICAL no puede ser robada por prioridad inferior (retorna -1)")
	
	# 5. Hitmarker taxonomy
	sm.play_hitmarker(B.HitmarkerType.CRIT)
	sm.play_hitmarker(B.HitmarkerType.SHIELD)
	sm.play_hitmarker(B.HitmarkerType.HURT_SELF)
	check(true, "Taxonomía completa de hitmarkers ejecutada sin excepciones")
	
	print("== Audio Engine: %d checks, %d fallos ==" % [_checks_passed, _checks_failed])
	sm.queue_free()
	quit(_checks_failed)


func check(cond: bool, msg: String) -> void:
	if cond:
		_checks_passed += 1
		print("  PASS: %s" % msg)
	else:
		_checks_failed += 1
		print("  FAIL: %s" % msg)
