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
# Color de acento por defecto "Nexo": #46e3c1 (alternativas: #5aa9ff, #f5b546, #ff6fa8).
const ACCENT_DEFAULT := Color("#46e3c1")
const ACCENT_ALTERNATIVES: Array[Color] = [
	Color("#46e3c1"),  # Nexo
	Color("#5aa9ff"),  # Alternativa azul
	Color("#f5b546"),  # Alternativa dorada
	Color("#ff6fa8"),  # Alternativa rosa
]

# Panel forma: #0d1216, alfa 0.97. Borde de la forma: blanco al 9% (Color(1,1,1,0.09)), 1.5 px.
const PANEL_BG := Color(Color("#0d1216"), 0.97)               # #0d1216 @ 0.97
const PANEL_TOP := Color(0.066, 0.088, 0.108, 0.97)          # gradiente sutil
const PANEL_BOTTOM := Color(Color("#0d1216"), 0.97)          # #0d1216
const PANEL_TAB := Color(0.060, 0.080, 0.098, 0.97)
const PANEL_EDGE := Color(1, 1, 1, 0.09)                      # blanco al 9%
const PANEL_EDGE_WIDTH := 1.5                                 # 1.5 px
const DIVIDER := Color(1, 1, 1, 0.06)

# Tile habilidad lista: #1c2a33. Bloqueada: #11181d. Neutro (pasiva/retrato): #1a252c.
const SLOT_READY := Color("#1c2a33")
const SLOT_LOCKED := Color("#11181d")
const SLOT_NEUTRAL := Color("#1a252c")

# Ranura vacía: #0a0f13 + borde blanco al 6% de 1px.
const SLOT_EMPTY := Color("#0a0f13")
const SLOT_EMPTY_BORDER := Color(1, 1, 1, 0.06)

# Pozo: #070a0c. Botón: #18242b + borde blanco al 8%.
const WELL := Color("#070a0c")
const BUTTON_BG := Color("#18242b")
const BUTTON_BORDER := Color(1, 1, 1, 0.08)

const SLOT_BORDER := Color(1, 1, 1, 0.12)
const COOLDOWN_OVERLAY := Color(0.02, 0.03, 0.04, 0.72)

# Aliases retrocompatibles
const SLOT_BG := SLOT_READY
const SLOT_BG_DEEP := WELL

# Texto: #eef2f4. Secundario: #9aa6ae. Cero: #7c8992. Letra tecla: #c3ccd3.
const TEXT := Color("#eef2f4")
const TEXT_SECONDARY := Color("#9aa6ae")
const TEXT_DIM := Color("#9aa6ae")                            # alias retrocompatible
const TEXT_ZERO := Color("#7c8992")
const TEXT_KEY := Color("#c3ccd3")
const TEXT_MUTED := Color("#7c8992")
const TEXT_DARK := Color("#070a0c")

# Vida: #3ccf73 · regeneración #a9f0c3.
const HEALTH := Color("#3ccf73")
const HEALTH_TRAIL := Color("#d9f5e2")
const HEALTH_REGEN := Color("#a9f0c3")
const HEALTH_TICK := Color(0.04, 0.12, 0.07, 0.55)

# Maná: #3f82f2 · coste de maná #8fbaff.
const MANA := Color("#3f82f2")
const MANA_COST := Color("#8fbaff")
const BAR_BG := Color("#070a0c")

# Oro: #f5c35b. Aliado: #6cb8ff.
const GOLD := Color("#f5c35b")
const GOLD_TEXT := Color("#f5c35b")
const ALLY := Color("#6cb8ff")
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

## Stepped silhouette: low left step (portrait), main deck, raised stats block (x=988 a 1260).
const SHAPE_STEPPED_POINTS: Array[Vector2] = [
	Vector2(18, 461), Vector2(52, 316), Vector2(196, 316), Vector2(218, 276),
	Vector2(952, 276), Vector2(970, 206), Vector2(988, 190), Vector2(1260, 190),
	Vector2(1278, 206), Vector2(1296, 276), Vector2(1342, 461),
]

## Curve silhouette control data: rounded shoulders + gentle arched top.
const CURVE_LEFT := [Vector2(18, 461), Vector2(28, 318), Vector2(52, 284), Vector2(140, 282)]
const CURVE_TOP := [Vector2(140, 282), Vector2(680, 262), Vector2(1220, 282)]
const CURVE_RIGHT := [Vector2(1220, 282), Vector2(1308, 284), Vector2(1332, 318), Vector2(1342, 461)]

# Estadísticas en pestaña más alta a la derecha (x=988, bottom=14, ancho 272).
# Altura HUD = 460 -> bottom a 14 px = 446. De 190 a 446 = 256 px.
const STATS_TAB_RECT := Rect2(988, 190, 272, 256)
# Radios: ... pestaña stats 18 (arriba).
const STATS_TAB_RADIUS := 18

const ACCENT_BAR_RECT := Rect2(600, 276, 124, 3)
const DIVIDER_X := 706.0
const MINI_BUTTONS := [Vector2(88, 366), Vector2(88, 397), Vector2(88, 428)]
const MINI_BUTTON_RADIUS := 11.0

# --------------------------------------------------------------------------
# Component metrics & Radios
# Radios: tile habilidad 14, tile chico 12, ranura 12, buff 8, botón 8,
#         caja oro 10, barras 10 (vida) y 7 (maná), pestaña stats 18 (arriba).
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
const BUTTON_RADIUS := 8
const GOLD_BOX_RADIUS := 10
const GOLD_BOX_HEIGHT := 34.0

const HEALTH_BAR_RADIUS := 10
const MANA_BAR_RADIUS := 7

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
	{"id": "attack_damage", "label": "Atq. físico", "color": Color("#f0a03c"), "section": 0, "col": 0},
	{"id": "ability_power", "label": "Poder hab.", "color": Color("#b07cf0"), "section": 0, "col": 1},
	{"id": "attack_speed", "label": "Vel. ataque", "color": Color("#f0d05a"), "section": 0, "col": 0},
	{"id": "crit", "label": "Crítico", "color": Color("#f06a5a"), "section": 0, "col": 1},
	{"id": "armor_pen", "label": "Pen. arm.", "color": Color("#e8783c"), "section": 0, "col": 0},
	{"id": "magic_pen", "label": "Pen. mág.", "color": Color("#c878f0"), "section": 0, "col": 1},
	{"id": "life_steal", "label": "Robo vida", "color": Color("#e85a6a"), "section": 0, "col": 0},
	{"id": "omnivamp", "label": "Omnivamp.", "color": Color("#e870b0"), "section": 0, "col": 1},
	{"id": "armor", "label": "Armadura", "color": Color("#e8b44c"), "section": 1, "col": 0},
	{"id": "magic_resist", "label": "Res. mág.", "color": Color("#5ac8e8"), "section": 1, "col": 1},
	{"id": "tenacity", "label": "Tenacidad", "color": Color("#a98cf0"), "section": 1, "col": 0},
	{"id": "heal_shield", "label": "Cur./esc.", "color": Color("#6ad89a"), "section": 1, "col": 1},
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
