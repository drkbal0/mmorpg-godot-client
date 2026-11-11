extends Control
class_name KiSpectralVision

# KiSpectralVision.gd — Ki Spectral Vision Controller and Stat Aura Decoder (Phase 9.6, ADR 098)
# Controls post-processing desaturation pass and computes entity chromatic auras based on combat attributes.

signal vision_toggled(active: bool)

# Paleta cromática de auras de Ki
const COLOR_STRENGTH := Color("#ff3344")     # Carmesí Guerrero (Físico / Burst)
const COLOR_AGILITY := Color("#00f0a0")      # Esmeralda Ágil (Destreza / Resistencia)
const COLOR_INTELLIGENCE := Color("#a040ff") # Púrpura Espectral (Magia / Mente)
const COLOR_BOSS := Color("#ffcc00")         # Oro Celestial (Boss / Élite Corrupto)
const COLOR_NEUTRAL := Color("#7c8992")      # Grafito Neutro (Inerte / Sin Atributos)

const MAX_PENETRATION_METERS := 8.0

@export var is_active: bool = false
@export var desaturation: float = 0.85
@export var is_in_combat: bool = false

@onready var color_rect: ColorRect = find_child("ShaderRect", true, false)
@onready var state_badge: Label = find_child("StateBadge", true, false)

var _pulse_accumulator: float = 0.0

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	_apply_shader_state()

func _process(delta: float) -> void:
	if not is_active: return
	_pulse_accumulator += delta
	if color_rect and color_rect.material:
		var mat = color_rect.material as ShaderMaterial
		if mat:
			mat.set_shader_parameter("pulse_time", _pulse_accumulator)
			mat.set_shader_parameter("pulse_speed", get_pulse_frequency(is_in_combat))

func toggle_vision() -> bool:
	set_vision_active(not is_active)
	return is_active

func set_vision_active(active: bool) -> void:
	is_active = active
	_apply_shader_state()
	vision_toggled.emit(is_active)

func _apply_shader_state() -> void:
	if color_rect:
		color_rect.visible = is_active
		if color_rect.material:
			var mat = color_rect.material as ShaderMaterial
			if mat:
				mat.set_shader_parameter("vision_active", is_active)
				mat.set_shader_parameter("desaturation", desaturation)
	if state_badge:
		state_badge.visible = is_active
		state_badge.text = "👁️ PULSO DE VISIÓN DE KI [P]: ACTIVO"

## Determina el color cromático del aura de una entidad según sus atributos dominantes
static func get_aura_color(strength: float, agility: float, intelligence: float, is_boss: bool = false) -> Color:
	if is_boss:
		return COLOR_BOSS
		
	var max_val = max(strength, max(agility, intelligence))
	if max_val <= 0.0:
		return COLOR_NEUTRAL
		
	# Resolución de empates: Fuerza > Agilidad > Inteligencia
	if strength >= agility and strength >= intelligence:
		return COLOR_STRENGTH
	elif agility >= intelligence:
		return COLOR_AGILITY
	else:
		return COLOR_INTELLIGENCE

## Devuelve la frecuencia de parpadeo y resonancia según el estado de combate
static func get_pulse_frequency(is_in_combat: bool) -> float:
	return 4.0 if is_in_combat else 1.2

## Valida si la visión de Ki penetra un obstáculo o muro
static func can_detect_through_wall(wall_thickness_meters: float) -> bool:
	return wall_thickness_meters >= 0.0 and wall_thickness_meters <= MAX_PENETRATION_METERS
