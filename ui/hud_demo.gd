extends Control
## HUDv2 interactive demo. Background map + HUD driven by a Timer.
##
## Keys: Q W E R = cast ability · D F = summoner spells · H = take damage
##       1 2 3 = shape (trapecio / escalonada / curva) · C = cycle accent
##       L = level up · G = +300 gold

const ACCENTS: Array[Color] = [Color("#46e3c1"), Color("#5aa9ff"), Color("#f5b546"), Color("#ff6fa8")]
const SHAPES: Array[String] = ["trapecio", "escalonada", "curva"]
const ABILITY_DEFS := [
	{"rank": 3, "max": 5, "cost": 24, "cd": 6.0},
	{"rank": 1, "max": 5, "cost": 50, "cd": 12.0},
	{"rank": 1, "max": 5, "cost": 60, "cd": 9.0},
	{"rank": 0, "max": 3, "cost": 100, "cd": 80.0},
]
const FEED_SAMPLES := [
	["EST JimRising", "Campeón", "está en camino", false],
	["Ascendant", "Campeón", "Baliza de control", true],
	["xdfaster500", "Campeón", "Baliza de control", true],
	["Nyx", "Campeón", "ha comprado Filo infinito", true],
	["Kaelen", "Campeón", "necesita ayuda", false],
	["Mirelle", "Campeón", "está en camino", false],
]

@onready var hud = $HUD
@onready var timer: Timer = $Tick
@onready var help: Label = $Help

var hp := 612.0
var hp_max := 1003.0
var mana := 403.0
var mana_max := 403.0
var gold := 1665
var level := 5
var xp := 0.30
var accent_idx := 0
var shape_idx := 0
var game_seconds := 4 * 60 + 39
var _tick_count := 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 2026
	timer.timeout.connect(_on_tick)
	hud.recall_pressed.connect(func() -> void: _feed_local("vuelve a la base", false))
	hud.shop_pressed.connect(func() -> void: _feed_local("abre la tienda", false))
	_apply_initial_state()
	help.text = "Q W E R habilidades · D F hechizos · H daño · L nivel · G oro · 1/2/3 forma · C color"


func _apply_initial_state() -> void:
	hud.set_accent(ACCENTS[accent_idx])
	hud.set_shape(SHAPES[shape_idx])
	hud.set_level(level, xp)
	hud.set_health(hp, hp_max, 3.9)
	hud.set_mana(mana, mana_max)
	for i in ABILITY_DEFS.size():
		var a: Dictionary = ABILITY_DEFS[i]
		hud.set_ability(i, a.rank, a.max, a.cost, i == 3 and level < 6, 6, 0.0)
	hud.set_spell(0, 87.0)
	hud.set_spell(1, 39.0)
	hud.set_item(0, null, 23)
	for i in range(1, 6):
		hud.set_item(i, null, 0)
	hud.set_trinket(1)
	hud.set_gold(gold)
	hud.set_stats({
		"attack_damage": 89, "ability_power": 0,
		"attack_speed": 0.72, "crit": "0%",
		"armor_pen": "0 | 0%", "magic_pen": "0 | 0%",
		"life_steal": "0%", "omnivamp": "0%",
		"armor": 49, "magic_resist": 38,
		"tenacity": "0%", "heal_shield": "0%",
		"ability_haste": 10, "move_speed": 348,
		"attack_range": 175, "regen": "19 | 55",
	})
	hud.set_buffs([
		{"color": Color("#245a3e"), "stacks": 0, "name": "Regeneración"},
		{"color": Color("#5a2428"), "stacks": 0, "name": "Furia"},
		{"color": Color("#5a4a1e"), "stacks": 600, "name": "Escudo"},
		{"color": Color("#262e5a"), "stacks": 0, "name": "Celeridad"},
		{"color": Color("#1e4a4a"), "stacks": 0, "duration_fraction": 0.4, "name": "Visión"},
	])
	hud.push_feed("04:01", "EST JimRising", "Campeón", "está en camino", false)
	hud.push_feed("04:21", "Ascendant", "Campeón", "Baliza de control", true)
	hud.push_feed("04:39", "xdfaster500", "Campeón", "Baliza de control", true)


func _on_tick() -> void:
	_tick_count += 1
	# Health: passive regen with occasional damage bursts.
	if _rng.randf() < 0.12:
		hp -= _rng.randf_range(40.0, 140.0)
	hp = clampf(hp + 3.9 * timer.wait_time * 4.0, 1.0, hp_max)
	mana = clampf(mana + 2.0 * timer.wait_time * 4.0, 0.0, mana_max)
	hud.set_health(hp, hp_max, 3.9)
	hud.set_mana(mana, mana_max)
	# Every second: clock, gold, xp.
	if _tick_count % 4 == 0:
		game_seconds += 1
		gold += 2
		hud.set_gold(gold)
		xp += 0.02
		if xp >= 1.0:
			_level_up()
		hud.set_level(level, xp)
	# Bots cast abilities from time to time to show cooldowns.
	if _rng.randf() < 0.06:
		_cast(_rng.randi_range(0, 2))
	if _rng.randf() < 0.025:
		var s: Array = FEED_SAMPLES[_rng.randi_range(0, FEED_SAMPLES.size() - 1)]
		hud.push_feed(_clock(), s[0], s[1], s[2], s[3])


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_Q: _cast(0)
		KEY_W: _cast(1)
		KEY_E: _cast(2)
		KEY_R: _cast(3)
		KEY_D: hud.set_spell(0, 300.0)
		KEY_F: hud.set_spell(1, 180.0)
		KEY_H:
			hp = maxf(1.0, hp - 150.0)
			hud.set_health(hp, hp_max, 3.9)
		KEY_L: _level_up(); hud.set_level(level, xp)
		KEY_G:
			gold += 300
			hud.set_gold(gold)
		KEY_1, KEY_2, KEY_3:
			shape_idx = event.keycode - KEY_1
			hud.set_shape(SHAPES[shape_idx])
		KEY_C:
			accent_idx = (accent_idx + 1) % ACCENTS.size()
			hud.set_accent(ACCENTS[accent_idx])


func _cast(slot: int) -> void:
	var a: Dictionary = ABILITY_DEFS[slot]
	var node = hud.get_ability(slot)
	if node.locked or node.rank <= 0 or node.cooldown > 0.0 or mana < a.cost:
		return
	mana -= a.cost
	hud.set_mana(mana, mana_max)
	hud.set_ability(slot, node.rank, a.max, a.cost, false, 6, a.cd)


func _level_up() -> void:
	xp = 0.0
	level = mini(18, level + 1)
	hp_max += 95.0
	mana_max += 30.0
	for i in ABILITY_DEFS.size():
		var a: Dictionary = ABILITY_DEFS[i]
		var node = hud.get_ability(i)
		var rank: int = mini(a.max, node.rank + (1 if i == (level % 3) or (i == 3 and level == 6) else 0))
		hud.set_ability(i, rank, a.max, a.cost, i == 3 and level < 6, 6, node.cooldown)


func _feed_local(text: String, is_item: bool) -> void:
	hud.push_feed(_clock(), "Tú", "Campeón", text, is_item)


func _clock() -> String:
	return "%02d:%02d" % [int(game_seconds / 60.0), game_seconds % 60]
