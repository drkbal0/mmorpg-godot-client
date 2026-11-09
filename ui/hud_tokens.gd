extends RefCounted
## HUDv2 design tokens ("Final v2" MOBA bottom HUD).
##
## Single source of truth for colours, sizes, geometry and fonts used by every
## component in res://ui/components/HUDv2/. Load with:
##     const T = preload("res://ui/hud_tokens.gd")
## (preload instead of class_name so it resolves even before the global class
## cache exists, e.g. on a fresh `--headless` run.)

const THEME: Theme = preload("res://ui/hud_theme.tres")

# --------------------------------------------------------------------------
# Canvas
# --------------------------------------------------------------------------
const HUD_SIZE := Vector2(1360, 460)

# --------------------------------------------------------------------------
# Colours
# --------------------------------------------------------------------------
const ACCENT_DEFAULT := Color("#3fd9b0")

const PANEL_TOP := Color(0.086, 0.110, 0.133, 0.97)      # #161c22
const PANEL_BOTTOM := Color(0.055, 0.071, 0.086, 0.98)   # #0e1216
const PANEL_TAB := Color(0.078, 0.098, 0.118, 0.97)      # #141a1e
const PANEL_EDGE := Color(1, 1, 1, 0.07)
const DIVIDER := Color(1, 1, 1, 0.06)

const SLOT_BG := Color("#1a2229")
const SLOT_BG_DEEP := Color("#0f1418")
const SLOT_BORDER := Color("#2c3640")
const SLOT_LOCKED := Color("#141a1f")
const COOLDOWN_OVERLAY := Color(0.02, 0.03, 0.04, 0.72)

const TEXT := Color("#e9eef3")
const TEXT_DIM := Color("#8b97a4")
const TEXT_MUTED := Color("#5d6873")
const TEXT_DARK := Color("#0b1013")

const HEALTH := Color("#3fca6b")
const HEALTH_TRAIL := Color("#d9f5e2")
const HEALTH_REGEN := Color("#86e3a3")
const HEALTH_TICK := Color(0.04, 0.12, 0.07, 0.55)
const MANA := Color("#3b82f0")
const MANA_COST := Color("#62a6ff")
const BAR_BG := Color("#0b0f12")

const GOLD := Color("#f2b63d")
const GOLD_TEXT := Color("#ffd27a")
const ALLY := Color("#6fb4ff")
const FEED_BG := Color(0.05, 0.07, 0.09, 0.80)

const SPELL_D_TINT := Color("#16243a")
const SPELL_F_TINT := Color("#2a1a12")

## Multi-layer drop shadow for silhouettes: [y offset px, black alpha].
const SHADOW_LAYERS: Array[Vector2] = [Vector2(-6, 0.05), Vector2(-4, 0.08), Vector2(-2, 0.12)]

# --------------------------------------------------------------------------
# Shapes
# --------------------------------------------------------------------------
const SHAPE_TRAPECIO := "trapecio"
const SHAPE_ESCALONADA := "escalonada"
const SHAPE_CURVA := "curva"
const SHAPES: Array[String] = [SHAPE_TRAPECIO, SHAPE_ESCALONADA, SHAPE_CURVA]

const SHAPE_TRAPEZOID_POINTS: Array[Vector2] = [
	Vector2(18, 461), Vector2(66, 276), Vector2(1294, 276), Vector2(1342, 461),
]

## Stepped silhouette: low left step (portrait), main deck, raised stats block.
const SHAPE_STEPPED_POINTS: Array[Vector2] = [
	Vector2(18, 461), Vector2(52, 316), Vector2(196, 316), Vector2(218, 276),
	Vector2(940, 276), Vector2(958, 206), Vector2(976, 190), Vector2(1266, 190),
	Vector2(1284, 206), Vector2(1342, 461),
]

## Curve silhouette control data: rounded shoulders + gentle arched top.
const CURVE_LEFT := [Vector2(18, 461), Vector2(28, 318), Vector2(52, 284), Vector2(140, 282)]
const CURVE_TOP := [Vector2(140, 282), Vector2(680, 262), Vector2(1220, 282)]
const CURVE_RIGHT := [Vector2(1220, 282), Vector2(1308, 284), Vector2(1332, 318), Vector2(1342, 461)]

const STATS_TAB_RECT := Rect2(962, 190, 318, 270)
const STATS_TAB_RADIUS := {SHAPE_TRAPECIO: 16, SHAPE_CURVA: 26, SHAPE_ESCALONADA: 0}

const ACCENT_BAR_RECT := Rect2(600, 276, 124, 3)
const DIVIDER_X := 706.0
const MINI_BUTTONS := [Vector2(88, 366), Vector2(88, 397), Vector2(88, 428)]
const MINI_BUTTON_RADIUS := 11.0

# --------------------------------------------------------------------------
# Component metrics
# --------------------------------------------------------------------------
const PORTRAIT_INNER_DIAMETER := 84.0
const PORTRAIT_RING_RADIUS := 49.0
const PORTRAIT_RING_WIDTH := 5.0
const LEVEL_PILL_SIZE := Vector2(36, 22)

const ABILITY_SIZE := 62.0
const ABILITY_RADIUS := 14
const ABILITY_BORDER := 2
const COST_DROP_SIZE := Vector2(9, 12)

const SPELL_SIZE := 46.0
const SPELL_RADIUS := 12

const ITEM_SIZE := 48.0
const ITEM_RADIUS := 12
const ITEM_GAP := 8.0
const ITEM_COLUMNS := 3
const ITEM_ROWS := 2
const TRINKET_DIAMETER := 44.0
const GOLD_BOX_HEIGHT := 34.0

const STAT_ROW_HEIGHT := 20.0
const STAT_DOT := 7.0

const BUFF_SIZE := 28.0
const BUFF_RADIUS := 8

const FEED_LINE_HEIGHT := 24.0
const FEED_MAX_LINES := 5
const FEED_LIFETIME := 14.0
const FEED_FADE := 1.5

# --------------------------------------------------------------------------
# Font sizes
# --------------------------------------------------------------------------
const FS_TINY := 10
const FS_SMALL := 11
const FS_BODY := 13
const FS_BAR := 13
const FS_LARGE := 18
const FS_GOLD := 20
const FS_COOLDOWN := 22
const FS_FEED := 15
const FS_STAT_NAME := 13
const FS_STAT_VALUE := 14

# --------------------------------------------------------------------------
# Stats schema: id -> label, colour, section, column
# --------------------------------------------------------------------------
const STAT_SECTIONS: Array[String] = ["OFENSIVA", "DEFENSA", "UTILIDAD"]
const STAT_SCHEMA: Array[Dictionary] = [
	{"id": "attack_damage", "label": "Daño ataque", "color": Color("#f0a03c"), "section": 0, "col": 0},
	{"id": "ability_power", "label": "Poder hab.", "color": Color("#b07cf0"), "section": 0, "col": 1},
	{"id": "attack_speed", "label": "Vel. ataque", "color": Color("#f0d05a"), "section": 0, "col": 0},
	{"id": "crit", "label": "Crítico", "color": Color("#f06a5a"), "section": 0, "col": 1},
	{"id": "armor_pen", "label": "Pen. armad.", "color": Color("#e8783c"), "section": 0, "col": 0},
	{"id": "magic_pen", "label": "Pen. mágica", "color": Color("#c878f0"), "section": 0, "col": 1},
	{"id": "life_steal", "label": "Robo vida", "color": Color("#e85a6a"), "section": 0, "col": 0},
	{"id": "omnivamp", "label": "Omnivamp.", "color": Color("#e870b0"), "section": 0, "col": 1},
	{"id": "armor", "label": "Armadura", "color": Color("#e8b44c"), "section": 1, "col": 0},
	{"id": "magic_resist", "label": "Res. mágica", "color": Color("#5ac8e8"), "section": 1, "col": 1},
	{"id": "tenacity", "label": "Tenacidad", "color": Color("#a98cf0"), "section": 1, "col": 0},
	{"id": "heal_shield", "label": "Cur./escudo", "color": Color("#6ad89a"), "section": 1, "col": 1},
	{"id": "ability_haste", "label": "Celeridad", "color": Color("#d8dde3"), "section": 2, "col": 0},
	{"id": "move_speed", "label": "Vel. mov.", "color": Color("#d8dde3"), "section": 2, "col": 1},
	{"id": "attack_range", "label": "Alcance", "color": Color("#d8dde3"), "section": 2, "col": 0},
	{"id": "regen", "label": "Regen.", "color": Color("#5ad87a"), "section": 2, "col": 1},
]


# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------
## Returns a theme font: "regular", "medium", "semibold", "bold" or "header".
## All of them are FontVariations with tabular digits (opentype 'tnum').
static func font(weight: String = "medium") -> Font:
	if THEME.has_font(weight, "HUDFonts"):
		return THEME.get_font(weight, "HUDFonts")
	return THEME.default_font


static func normalize_shape(value: String) -> String:
	var v := value.strip_edges().to_lower()
	match v:
		"trapecio", "trapezoid", "trapeze":
			return SHAPE_TRAPECIO
		"escalonada", "escalonado", "stepped", "steps":
			return SHAPE_ESCALONADA
		"curva", "curve", "curved":
			return SHAPE_CURVA
	push_warning("HUDv2: forma desconocida '%s', usando trapecio" % value)
	return SHAPE_TRAPECIO


## StyleBoxFlat factory used by every slot/panel.
static func box(bg: Color, radius: int, border: int = 0, border_color: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.corner_detail = 8
	sb.anti_aliasing = true
	if border > 0:
		sb.set_border_width_all(border)
		sb.border_color = border_color
	return sb
