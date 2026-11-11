extends Control
class_name BossEncounterFrame

# BossEncounterFrame.gd — World Boss & Raid Encounter HUD (Phase 9.6, ADR 098)
# Displays segmented boss health, phase transitions, enrage countdown, active boss cast bar,
# and real-time player threat table percentage with aggro warning alerts.

signal phase_changed(new_phase: int)
signal enrage_triggered()
signal aggro_status_changed(holding_aggro: bool)

# Constantes de diseño Hextech
const COLOR_HEALTH_NORMAL := Color("#e03b3b") # Rojo Carmesí
const COLOR_HEALTH_GHOST := Color("#f59e0b")  # Ámbar de Daño Reciente
const COLOR_CAST_BAR := Color("#46e3c1")      # Cian Nexo
const COLOR_THREAT_SAFE := Color("#3b82f6")   # Azul Seguro (< 80%)
const COLOR_THREAT_DANGER := Color("#f59e0b") # Ámbar Alerta (80% - 99%)
const COLOR_THREAT_AGGRO := Color("#ef4444")  # Rojo Crítico (100% / Holding Aggro)

# Variables de estado del encuentro
var boss_id: int = 5001
var boss_name: String = "Val'Gorath, Devorador de Almas"
var current_hp: float = 100000.0
var max_hp: float = 100000.0
var current_phase: int = 1
var max_phases: int = 3
var enrage_timer_sec: int = 300
var is_enraged: bool = false

var is_casting: bool = false
var cast_spell_name: String = ""
var cast_progress: float = 0.0 # 0.0 a 1.0

var player_threat_pct: int = 0 # 0 a 100%
var is_holding_aggro: bool = false

# Nodos de interfaz
@onready var name_label: Label = find_child("BossNameLabel", true, false)
@onready var phase_badge: Label = find_child("PhaseBadge", true, false)
@onready var enrage_label: Label = find_child("EnrageLabel", true, false)
@onready var hp_bar: ProgressBar = find_child("HealthProgressBar", true, false)
@onready var hp_ghost_bar: ProgressBar = find_child("GhostProgressBar", true, false)
@onready var hp_text: Label = find_child("HealthTextLabel", true, false)
@onready var cast_container: Control = find_child("CastContainer", true, false)
@onready var cast_bar: ProgressBar = find_child("CastProgressBar", true, false)
@onready var cast_label: Label = find_child("CastSpellLabel", true, false)
@onready var threat_bar: ProgressBar = find_child("ThreatProgressBar", true, false)
@onready var threat_label: Label = find_child("ThreatTextLabel", true, false)
@onready var aggro_warning_badge: PanelContainer = find_child("AggroWarningBadge", true, false)

func _ready() -> void:
	_update_header_display()
	_update_hp_display()
	_update_threat_display()
	_update_cast_display()

func setup_boss(id: int, b_name: String, m_hp: float, phases: int = 3, enrage_sec: int = 300) -> void:
	boss_id = id
	boss_name = b_name
	max_hp = max(1.0, m_hp)
	current_hp = max_hp
	max_phases = max(1, phases)
	current_phase = 1
	enrage_timer_sec = enrage_sec
	is_enraged = false
	_update_header_display()
	_update_hp_display()

func set_hp(new_hp: float) -> void:
	current_hp = clamp(new_hp, 0.0, max_hp)
	_update_hp_display()

func set_phase(new_phase: int) -> void:
	if current_phase != new_phase:
		current_phase = clamp(new_phase, 1, max_phases)
		_update_header_display()
		phase_changed.emit(current_phase)

func tick_enrage(delta_sec: float) -> void:
	if is_enraged: return
	enrage_timer_sec = max(0, enrage_timer_sec - int(round(delta_sec)))
	_update_enrage_display()
	if enrage_timer_sec <= 0:
		is_enraged = true
		enrage_triggered.emit()
		if enrage_label:
			enrage_label.text = "⚠️ ¡BOSS ENFURECIDO (+300% DAÑO)!"
			enrage_label.add_theme_color_override("font_color", COLOR_THREAT_AGGRO)

func start_cast(spell_name: String, _duration_sec: float) -> void:
	is_casting = true
	cast_spell_name = spell_name
	cast_progress = 0.0
	_update_cast_display()

func update_cast_progress(progress_ratio: float) -> void:
	cast_progress = clamp(progress_ratio, 0.0, 1.0)
	if cast_bar:
		cast_bar.value = cast_progress * 100.0
	if cast_progress >= 1.0:
		stop_cast()

func stop_cast() -> void:
	is_casting = false
	cast_progress = 0.0
	cast_spell_name = ""
	_update_cast_display()

func set_threat(threat_pct: int, holding_aggro: bool) -> void:
	player_threat_pct = clamp(threat_pct, 0, 100)
	var was_holding = is_holding_aggro
	is_holding_aggro = holding_aggro
	_update_threat_display()
	if was_holding != is_holding_aggro:
		aggro_status_changed.emit(is_holding_aggro)

func _update_header_display() -> void:
	if name_label:
		name_label.text = "⚔️ %s" % boss_name.to_upper()
	if phase_badge:
		phase_badge.text = "FASE %d / %d" % [current_phase, max_phases]
	_update_enrage_display()

func _update_enrage_display() -> void:
	if not enrage_label or is_enraged: return
	var mins = enrage_timer_sec / 60
	var secs = enrage_timer_sec % 60
	enrage_label.text = "⏱️ ENFURECIMIENTO: %02d:%02d" % [mins, secs]
	if enrage_timer_sec < 60:
		enrage_label.add_theme_color_override("font_color", COLOR_THREAT_DANGER)
	else:
		enrage_label.add_theme_color_override("font_color", Color(0.75, 0.85, 0.95))

func _update_hp_display() -> void:
	var pct = (current_hp / max_hp) * 100.0
	if hp_bar:
		hp_bar.value = pct
	if hp_ghost_bar:
		hp_ghost_bar.value = pct
	if hp_text:
		hp_text.text = "%s / %s HP (%.1f%%)" % [_format_number(int(current_hp)), _format_number(int(max_hp)), pct]

func _update_cast_display() -> void:
	if cast_container:
		cast_container.visible = is_casting
	if cast_label:
		cast_label.text = "CANALIZANDO: [%s]" % cast_spell_name.to_upper()
	if cast_bar:
		cast_bar.value = cast_progress * 100.0

func _update_threat_display() -> void:
	if threat_bar:
		threat_bar.value = player_threat_pct
	if threat_label:
		threat_label.text = "AMENAZA: %d%%" % player_threat_pct
	if aggro_warning_badge:
		aggro_warning_badge.visible = is_holding_aggro
		
	# Colorear barra de amenaza
	var color := COLOR_THREAT_SAFE
	if is_holding_aggro or player_threat_pct >= 100:
		color = COLOR_THREAT_AGGRO
	elif player_threat_pct >= 80:
		color = COLOR_THREAT_DANGER
		
	if threat_label:
		threat_label.add_theme_color_override("font_color", color)

static func _format_number(n: int) -> String:
	var s = str(n)
	var res = ""
	var count = 0
	for i in range(s.length() - 1, -1, -1):
		res = s[i] + res
		count += 1
		if count % 3 == 0 and i > 0:
			res = "," + res
	return res

