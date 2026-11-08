extends Node

## SpellManager.gd - Catálogo de Habilidades y Gestión de Cooldowns
## Dominio: Combat / Spells
## Provee acceso O(1) a definiciones de habilidades con caché en disco y seguimiento de cooldowns.

signal spell_definitions_loaded
signal cooldown_started(spell_id: int, duration: float)
signal cooldown_ended(spell_id: int)

const CACHE_PATH = "user://cache/spells.json"

var spells: Dictionary = {} # id (int) -> Dictionary
var cooldowns: Dictionary = {} # id (int) -> end_time_msec (float)

func _ready() -> void:
	_init_preseeded_spells()
	_load_from_disk()
	_fetch_remote_definitions()

func _init_preseeded_spells() -> void:
	# Catálogo pre-calentado en cliente alineado con PostgreSQL y Rust ECS
	spells[1] = {
		"id": 1,
		"code_name": "fireball_skillshot",
		"display_name": "Bola de Fuego",
		"description": "Lanza un orbe ardiente balístico que detona al impactar.",
		"shape": "Projectile",
		"base_damage": 35.0,
		"speed": 18.0,
		"radius": 0.6,
		"max_range": 25.0,
		"cooldown_ms": 1200,
		"cost_amount": 15.0,
		"cost_type": "mana",
		"vfx_scene_path": "res://assets/vfx/spells/fireball.tscn",
		"icon_path": "res://assets/icons/spells/fireball.png"
	}
	spells[2] = {
		"id": 2,
		"code_name": "blink_dash",
		"display_name": "Destello Arcano",
		"description": "Teletransporte táctico instantáneo hacia la dirección del cursor.",
		"shape": "SelfDash",
		"base_damage": 0.0,
		"speed": 25.0,
		"radius": 1.0,
		"max_range": 8.0,
		"cooldown_ms": 4000,
		"cost_amount": 25.0,
		"cost_type": "stamina",
		"vfx_scene_path": "res://assets/vfx/spells/blink.tscn",
		"icon_path": "res://assets/icons/spells/blink.png"
	}
	spells[3] = {
		"id": 3,
		"code_name": "hitscan_shot",
		"display_name": "Disparo Preciso",
		"description": "Ataque primario de alta cadencia mediante haz láser instantáneo.",
		"shape": "Hitscan",
		"base_damage": 22.0,
		"speed": 0.0,
		"radius": 0.35,
		"max_range": 45.0,
		"cooldown_ms": 200,
		"cost_amount": 5.0,
		"cost_type": "stamina",
		"vfx_scene_path": "res://assets/vfx/spells/hitscan.tscn",
		"icon_path": "res://assets/icons/spells/hitscan.png"
	}
	spells[4] = {
		"id": 4,
		"code_name": "defensive_barrier",
		"display_name": "Barrera Arcana",
		"description": "Escudo de energía cinético que mitiga daño entrante por 4 segundos.",
		"shape": "SelfBuff",
		"base_damage": 0.0,
		"speed": 0.0,
		"radius": 2.0,
		"max_range": 0.0,
		"cooldown_ms": 6000,
		"cost_amount": 20.0,
		"cost_type": "stamina",
		"vfx_scene_path": "res://assets/vfx/spells/barrier.tscn",
		"icon_path": "res://assets/icons/spells/barrier.png"
	}
	spells[5] = {
		"id": 5,
		"code_name": "meteor_strike",
		"display_name": "Impacto Cósmico",
		"description": "Habilidad definitiva: Invoca un meteoro ardiente en el área seleccionada.",
		"shape": "AoECircle",
		"base_damage": 65.0,
		"speed": 15.0,
		"radius": 3.5,
		"max_range": 20.0,
		"cooldown_ms": 12000,
		"cost_amount": 35.0,
		"cost_type": "mana",
		"vfx_scene_path": "res://assets/vfx/spells/meteor.tscn",
		"icon_path": "res://assets/icons/spells/meteor.png"
	}

func get_spell(spell_id: int) -> Dictionary:
	return spells.get(spell_id, {})

func get_all_spells() -> Array:
	return spells.values()

func is_ready(spell_id: int) -> bool:
	var now = Time.get_ticks_msec()
	var end_time = cooldowns.get(spell_id, 0.0)
	return now >= end_time

func get_cooldown_remaining(spell_id: int) -> float:
	var now = Time.get_ticks_msec()
	var end_time = cooldowns.get(spell_id, 0.0)
	if now >= end_time:
		return 0.0
	return (end_time - now) / 1000.0

func trigger_cooldown(spell_id: int) -> void:
	var def = get_spell(spell_id)
	if def.is_empty(): return
	var cd_ms = def.get("cooldown_ms", 1000)
	var now = Time.get_ticks_msec()
	cooldowns[spell_id] = now + cd_ms
	cooldown_started.emit(spell_id, cd_ms / 1000.0)

func _process(_delta: float) -> void:
	var now = Time.get_ticks_msec()
	var to_erase = []
	for id in cooldowns.keys():
		if now >= cooldowns[id]:
			to_erase.append(id)
	for id in to_erase:
		cooldowns.erase(id)
		cooldown_ended.emit(id)

func _fetch_remote_definitions() -> void:
	if not APIClient: return
	var response = await APIClient.get_request("/shelter/spells/definitions")
	if response.get("code", 500) == 200 and response.get("data") is Array:
		for item in response.get("data"):
			var id = int(item.get("id", 0))
			if id > 0:
				spells[id] = item
		_save_to_disk()
		spell_definitions_loaded.emit()

func _load_from_disk() -> void:
	if FileAccess.file_exists(CACHE_PATH):
		var file = FileAccess.open(CACHE_PATH, FileAccess.READ)
		var json = JSON.new()
		if json.parse(file.get_as_text()) == OK and json.data is Dictionary:
			for k in json.data.keys():
				spells[int(k)] = json.data[k]

func _save_to_disk() -> void:
	DirAccess.make_dir_recursive_absolute("user://cache/")
	var file = FileAccess.open(CACHE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(spells))
