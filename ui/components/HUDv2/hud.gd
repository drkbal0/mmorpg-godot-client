extends Control
## HUDv2 "Final v2" — MOBA-style bottom HUD (1360x460, anchored bottom-centre).
##
## Public API (all methods are safe to call before or after _ready):
##   set_accent(color)                     set_shape("trapecio"|"escalonada"|"curva")
##   set_level(level, xp_fraction)         set_health(current, max_value, regen)
##   set_mana(current, max_value)
##   set_ability(slot 0..3, rank, max_rank, cost, locked, unlock_level, cooldown)
##   set_spell(slot 0=D 1=F, cooldown)     set_item(slot 0..5, icon, stacks)
##   set_trinket(charges)                  set_gold(amount)
##   set_stats({stat_id: value})           set_buffs([{color, stacks, ...}])
##   push_feed(time, player, champion, text, is_item)

signal recall_pressed
signal shop_pressed
signal item_used(slot: int, item_name: String, item_id: String)
signal item_assigned(slot: int, item_name: String, item_id: String)
signal item_cleared(slot: int)

const T = preload("res://ui/hud_tokens.gd")
const STAT_ROW_SCENE: PackedScene = preload("res://ui/components/HUDv2/stat_row.tscn")
const BUFF_SCENE: PackedScene = preload("res://ui/components/HUDv2/buff_icon.tscn")
const FEED_SCENE: PackedScene = preload("res://ui/components/HUDv2/feed_line.tscn")

const STATS_PAD := Vector2(10, 14)
const STATS_COL_W := 120.0
const STATS_COL_GAP := 12.0
const STATS_HEADER_H := 18.0

## Scale the HUD down (never up) when the viewport is narrower than 1360px.
@export var auto_fit: bool = true

@onready var shape_node = $Shape
@onready var portrait = $Portrait
@onready var passive = $Passive
@onready var abilities: Array = [$AbilityQ, $AbilityW, $AbilityE, $AbilityR]
@onready var spells: Array = [$SpellD, $SpellF]
@onready var health_bar = $HealthBar
@onready var mana_bar = $ManaBar
@onready var items: Array = [$Items/Item0, $Items/Item1, $Items/Item2, $Items/Item3, $Items/Item4, $Items/Item5]
@onready var trinket = $Trinket
@onready var btn_recall = $BtnRecall
@onready var btn_shop = $BtnShop
@onready var gold_box = $GoldBox
@onready var stats_root: Control = $Stats
@onready var buffs_root: HBoxContainer = $Buffs
@onready var feed_root: VBoxContainer = $Feed

var accent: Color = T.ACCENT_DEFAULT
var shape: String = T.SHAPE_TRAPECIO
var stat_rows: Dictionary = {}  # stat_id -> StatRow
var stat_values: Dictionary = {}
var gold: int = 0
var level: int = 1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_stats()
	btn_recall.pressed.connect(func() -> void: recall_pressed.emit())
	btn_shop.pressed.connect(func() -> void: shop_pressed.emit())
	set_accent(accent)
	set_shape(shape)
	get_viewport().size_changed.connect(_fit_to_viewport)
	_fit_to_viewport()


func _fit_to_viewport() -> void:
	pivot_offset = Vector2(T.HUD_SIZE.x * 0.5, T.HUD_SIZE.y)
	if not auto_fit:
		scale = Vector2.ONE
		return
	var vw := get_viewport_rect().size.x
	var s := minf(1.0, vw / T.HUD_SIZE.x)
	scale = Vector2(s, s)


func _process(_delta: float) -> void:
	# Passive gold income ring: purely cosmetic, one turn every 10 s.
	gold_box.income_fraction = fmod(Time.get_ticks_msec() / 10000.0, 1.0)


# --------------------------------------------------------------------------
# Public API
# --------------------------------------------------------------------------
func set_accent(color: Color) -> void:
	accent = color
	if not is_node_ready():
		return
	for n in [shape_node, portrait, passive, trinket, btn_recall, btn_shop, gold_box] + abilities + spells + items:
		n.accent = color


func set_shape(forma: String) -> void:
	shape = T.normalize_shape(forma)
	if not is_node_ready():
		return
	shape_node.shape = shape


func get_shape() -> String:
	return shape


func set_level(p_level: int, xp_fraction: float) -> void:
	level = maxi(1, p_level)
	if not is_node_ready():
		await ready
	portrait.level = level
	portrait.xp_fraction = xp_fraction


func set_health(current: float, max_value: float, regen: float) -> void:
	if not is_node_ready():
		await ready
	health_bar.set_values(current, max_value, regen)


func set_mana(current: float, max_value: float) -> void:
	if not is_node_ready():
		await ready
	mana_bar.set_values(current, max_value, 0.0)


func set_ability(slot: int, rank: int, max_rank: int, cost: int, locked: bool, unlock_level: int, cooldown: float) -> void:
	if slot < 0 or slot >= 4:
		push_error("HUDv2.set_ability: slot fuera de rango (%d)" % slot)
		return
	if not is_node_ready():
		await ready
	var a = abilities[slot]
	a.max_rank = max_rank
	a.rank = rank
	a.cost = cost
	a.locked = locked
	a.unlock_level = unlock_level
	a.set_cooldown(cooldown)


func set_spell(slot: int, cooldown: float) -> void:
	if slot < 0 or slot >= 2:
		push_error("HUDv2.set_spell: slot fuera de rango (%d)" % slot)
		return
	if not is_node_ready():
		await ready
	spells[slot].set_cooldown(cooldown)


func set_item(slot: int, icon: Texture2D, stacks: int) -> void:
	if slot < 0 or slot >= 6:
		push_error("HUDv2.set_item: slot fuera de rango (%d)" % slot)
		return
	if not is_node_ready():
		await ready
	items[slot].icon = icon
	items[slot].stacks = stacks


func set_trinket(charges: int) -> void:
	if not is_node_ready():
		await ready
	trinket.charges = charges


func set_gold(amount: int) -> void:
	gold = maxi(0, amount)
	if not is_node_ready():
		await ready
	gold_box.amount = gold


## `stats` maps stat ids (see HUDTokens.STAT_SCHEMA) to int/float/String.
func set_stats(stats: Dictionary) -> void:
	for k in stats:
		stat_values[str(k)] = stats[k]
	if not is_node_ready():
		return  # applied in _build_stats()
	_apply_stats()


## `buffs`: Array of Dictionaries {color, icon, stacks, duration_fraction, debuff, name}.
func set_buffs(buffs: Array) -> void:
	if not is_node_ready():
		await ready
	for c in buffs_root.get_children():
		buffs_root.remove_child(c)
		c.queue_free()
	for b in buffs:
		var icon_node = BUFF_SCENE.instantiate()
		buffs_root.add_child(icon_node)
		icon_node.setup(b if b is Dictionary else {})


func push_feed(time: String, player: String, champion: String, text: String, is_item: bool) -> void:
	if not is_node_ready():
		await ready
	var line = FEED_SCENE.instantiate()
	line.setup(time, player, champion, text, is_item)
	feed_root.add_child(line)
	while feed_root.get_child_count() > T.FEED_MAX_LINES:
		var old := feed_root.get_child(0)
		feed_root.remove_child(old)
		old.queue_free()


# --------------------------------------------------------------------------
# Accessors (useful for tests / tooling)
# --------------------------------------------------------------------------
func get_ability(slot: int) -> Control:
	return abilities[slot]


func get_spell(slot: int) -> Control:
	return spells[slot]


func get_item(slot: int) -> Control:
	return items[slot]


func get_feed_count() -> int:
	return feed_root.get_child_count()


func get_buff_count() -> int:
	return buffs_root.get_child_count()


# --------------------------------------------------------------------------
# Stats panel
# --------------------------------------------------------------------------
func _build_stats() -> void:
	var y := STATS_PAD.y
	for s in T.STAT_SECTIONS.size():
		var header := Label.new()
		header.name = "Header%d" % s
		header.text = T.STAT_SECTIONS[s]
		header.position = Vector2(STATS_PAD.x, y)
		header.size = Vector2(STATS_COL_W * 2 + STATS_COL_GAP, 16)
		header.add_theme_font_override("font", T.font("header"))
		header.add_theme_font_size_override("font_size", T.FS_TINY)
		header.add_theme_color_override("font_color", T.TEXT_SECONDARY)
		header.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stats_root.add_child(header)
		y += STATS_HEADER_H - 4.0
		var row_y := [y, y]
		for def in T.STAT_SCHEMA:
			if def.section != s:
				continue
			var row = STAT_ROW_SCENE.instantiate()
			row.name = "Stat_" + def.id
			row.stat_id = def.id
			row.stat_name = def.label
			row.dot_color = def.color
			var col: int = def.col
			row.position = Vector2(STATS_PAD.x + col * (STATS_COL_W + STATS_COL_GAP), row_y[col])
			row.size = Vector2(STATS_COL_W, T.STAT_ROW_HEIGHT)
			row_y[col] += T.STAT_ROW_HEIGHT
			stats_root.add_child(row)
			stat_rows[def.id] = row
		y = maxf(row_y[0], row_y[1]) + 4.0
	_apply_stats()


func _apply_stats() -> void:
	for id in stat_values:
		if stat_rows.has(id):
			stat_rows[id].set_value(stat_values[id])
		else:
			push_warning("HUDv2.set_stats: stat desconocido '%s'" % id)
