extends RefCounted
## HUDv2 design tokens ("Final v2" MOBA bottom HUD).
##
## Single source of truth for colours, sizes, geometry and fonts used by every
## component in res://ui/components/HUDv2/. Load with:
##     const T = preload("res://ui/tokens/hud_tokens.gd")
## (preload instead of class_name so it resolves even before the global class
## cache exists, e.g. on a fresh `--headless` run.)

const THEME: Theme = preload("res://ui/theme/hud_theme.tres")
const SvgPath = preload("res://ui/icons/svg_path.gd")

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


# ==========================================================================
# UI v2.4 — Sistema de diseño común (design_ref/PROMPT_ANTIGRAVITY.md)
# ==========================================================================

# --------------------------------------------------------------------------
# Anexo A · 16 estadísticas canónicas (icono SVG 24×24 de trazo + color + texto)
# Regla 2.6: nunca se usa solo el color; siempre icono + color + texto.
# --------------------------------------------------------------------------
const STAT_ICON_VIEWBOX := 24
const STAT_ICON_STROKE := 2.2
## Tamaños canónicos: 16 px en el HUD, 20 px en comparaciones, 24 px en fichas.
const STAT_ICON_SIZE_HUD := 16
const STAT_ICON_SIZE_COMPARE := 20
const STAT_ICON_SIZE_CARD := 24
const STAT_ICON_SIZES: Array[int] = [STAT_ICON_SIZE_HUD, STAT_ICON_SIZE_COMPARE, STAT_ICON_SIZE_CARD]
const STAT_ICON_CONTEXTS := {
	"hud": STAT_ICON_SIZE_HUD,
	"compare": STAT_ICON_SIZE_COMPARE,
	"card": STAT_ICON_SIZE_CARD,
}

## Orden canónico (el mismo que design_ref/tokens_estadisticas.js).
const STAT_KEYS: Array[String] = [
	"dano", "poder", "armadura", "resmag", "velatq", "celeridad", "critico", "velmov",
	"penarm", "penmag", "robo", "omni", "alcance", "tenacidad", "curacion", "regen",
]

const STATS := {
	"dano": {"name": "Daño de ataque", "abbr": "DA", "color": "#ff9a4d",
		"path": "M14 4h6v6L10 20l-6-6zM4 14l6 6M3 21l2-2"},
	"poder": {"name": "Poder de habilidad", "abbr": "PH", "color": "#a58bff",
		"path": "M12 3v5M12 16v5M3 12h5M16 12h5M6 6l3 3M15 15l3 3M18 6l-3 3M9 15l-3 3"},
	"armadura": {"name": "Armadura", "abbr": "ARM", "color": "#e0b04a",
		"path": "M12 3l7 3v6c0 4.5-3 7.5-7 9-4-1.5-7-4.5-7-9V6z"},
	"resmag": {"name": "Resistencia mágica", "abbr": "RM", "color": "#4fc8ff",
		"path": "M12 3l8 4.5v9L12 21l-8-4.5v-9zM12 8l4 2.3v4.4L12 17l-4-2.3v-4.4z"},
	"velatq": {"name": "Velocidad de ataque", "abbr": "VA", "color": "#ffd36b",
		"path": "M5 6l6 6-6 6M12 6l6 6-6 6"},
	"celeridad": {"name": "Celeridad", "abbr": "CEL", "color": "#b8f0ff",
		"path": "M7 3h10M7 21h10M8 3c0 5 8 5 8 9s-8 4-8 9M16 3c0 5-8 5-8 9"},
	"critico": {"name": "Golpe crítico", "abbr": "CRÍT", "color": "#ff5d5d",
		"path": "M12 3v5M12 16v5M3 12h5M16 12h5M12 9a3 3 0 1 0 0 6a3 3 0 1 0 0-6"},
	"velmov": {"name": "Velocidad de movimiento", "abbr": "VM", "color": "#9fe36a",
		"path": "M3 17c4 0 6-2 8-6s5-6 10-6c-1 6-4 12-11 12H3zM8 14l4-4"},
	"penarm": {"name": "Penetración de armadura", "abbr": "PEN", "color": "#ff7a59",
		"path": "M3 21L21 3M15 3h6v6M6 9l-2 2 9 9 2-2"},
	"penmag": {"name": "Penetración mágica", "abbr": "PEN M", "color": "#d08bff",
		"path": "M3 21L13 11M13 11a4 4 0 1 1 4 4M17 7h.01"},
	"robo": {"name": "Robo de vida", "abbr": "RV", "color": "#ff4d7a",
		"path": "M12 3C9 7 6 10 6 14a6 6 0 0 0 12 0c0-4-3-7-6-11zM10 13l2 3 2-3"},
	"omni": {"name": "Omnivampirismo", "abbr": "OMNI", "color": "#e66bc4",
		"path": "M8 4C6 7 4 9 4 12a4 4 0 0 0 8 0c0-3-2-5-4-8zM16 8c-2 3-4 5-4 8a4 4 0 0 0 8 0c0-3-2-5-4-8z"},
	"alcance": {"name": "Alcance", "abbr": "ALC", "color": "#c3ccd3",
		"path": "M3 12h18M7 8l-4 4 4 4M17 8l4 4-4 4"},
	"tenacidad": {"name": "Tenacidad", "abbr": "TEN", "color": "#9a7bff",
		"path": "M12 7a2 2 0 1 0 0-4a2 2 0 1 0 0 4M12 7v14M5 14a7 7 0 0 0 14 0M8 11h8"},
	"curacion": {"name": "Curación y escudos", "abbr": "CUR", "color": "#4fe39a",
		"path": "M12 3l7 3v6c0 4.5-3 7.5-7 9-4-1.5-7-4.5-7-9V6zM12 9v6M9 12h6"},
	"regen": {"name": "Regeneración", "abbr": "REG", "color": "#6fe0a0",
		"path": "M12 20s-7-4.5-7-10a4 4 0 0 1 7-2.5A4 4 0 0 1 19 10c0 5.5-7 10-7 10zM12 10v5M9.5 12.5h5"},
}

## Puente HUD v1 (STAT_SCHEMA en inglés) → clave canónica del Anexo A.
const STAT_LEGACY_MAP := {
	"attack_damage": "dano", "ability_power": "poder", "attack_speed": "velatq",
	"crit": "critico", "armor_pen": "penarm", "magic_pen": "penmag",
	"life_steal": "robo", "omnivamp": "omni", "armor": "armadura",
	"magic_resist": "resmag", "tenacity": "tenacidad", "heal_shield": "curacion",
	"ability_haste": "celeridad", "move_speed": "velmov", "attack_range": "alcance",
	"regen": "regen",
}

## Fondo del chip/icono: color de la stat al 13 % (js: `s.c + '22'`).
const STAT_BG_ALPHA := 34.0 / 255.0

# Deltas ▲▼ (regla: mejoras/empeoramientos llevan glifo además del color).
const DELTA_UP := Color("#4fe39a")
const DELTA_DOWN := Color("#ff8a8a")
const DELTA_NEUTRAL := Color("#7c8992")
const DELTA_UP_GLYPH := "▲"
const DELTA_DOWN_GLYPH := "▼"

# --------------------------------------------------------------------------
# Sección 2.2 · Dos monedas (Oro se gana jugando; Prismas se compran)
# --------------------------------------------------------------------------
const CURRENCY_GOLD := "oro"
const CURRENCY_PRISMS := "prismas"
const CURRENCY_KEYS: Array[String] = [CURRENCY_GOLD, CURRENCY_PRISMS]
const CURRENCIES := {
	"oro": {
		"name": "Oro", "color": "#f5c35b", "text_color": "#f5c35b",
		"purchasable": false, "earnable": true,
		"icon": [
			{"d": "M3 12a9 9 0 1 0 18 0a9 9 0 1 0 -18 0z", "fill": "#f5c35b"},
			{"d": "M6.5 12a5.5 5.5 0 1 0 11 0a5.5 5.5 0 1 0 -11 0z", "stroke": "#a3772a", "width": 1.8},
		],
	},
	"prismas": {
		"name": "Prismas", "color": "#7ee8ff", "text_color": "#a8f0ff",
		"purchasable": true, "earnable": false,
		"icon": [
			{"d": "M12 2l8 7-8 13-8-13z", "fill": "#7ee8ff"},
			{"d": "M4 9h16M12 2v20", "stroke": "#0d1216", "width": 1.2},
		],
	},
}
const PRISMS := Color("#7ee8ff")
const PRISMS_TEXT := Color("#a8f0ff")
## Separador de miles del diseño ("12.480").
const THOUSANDS_SEPARATOR := "."

# --------------------------------------------------------------------------
# Anexo B · Energías iniciales (lista abierta: añadir aquí escala Crisol/Atlas)
# --------------------------------------------------------------------------
const ENERGY_KEYS: Array[String] = [
	"vacio", "calor", "eco", "pulso", "runa", "savia", "hierro", "marea", "sombra", "luz",
]
const ENERGIES := {
	"vacio": {"name": "Vacío", "color": "#b47bff"},
	"calor": {"name": "Calor", "color": "#ff7a45"},
	"eco": {"name": "Eco", "color": "#7fe0ff"},
	"pulso": {"name": "Pulso", "color": "#5aa9ff"},
	"runa": {"name": "Runa", "color": "#f5b546"},
	"savia": {"name": "Savia", "color": "#4fe39a"},
	"hierro": {"name": "Hierro", "color": "#b8c3ca"},
	"marea": {"name": "Marea", "color": "#3f8fd6"},
	"sombra": {"name": "Sombra", "color": "#8a7aa8"},
	"luz": {"name": "Luz", "color": "#fff1a8"},
}

# --------------------------------------------------------------------------
# Menú común (barra superior, 64 px; design_ref/pantallas_html/MMO-*.html)
# --------------------------------------------------------------------------
const MENU_BAR_HEIGHT := 64.0
const MENU_BAR_PADDING_X := 24.0
const MENU_BAR_BG := Color(9 / 255.0, 13 / 255.0, 16 / 255.0, 0.92)
const MENU_BAR_EDGE := Color(1, 1, 1, 0.07)
const MENU_TAB_TEXT := Color("#9aa6ae")
const MENU_TAB_TEXT_ACTIVE := Color("#eef2f4")
const MENU_TAB_UNDERLINE := 2.0
const MENU_KEYCAP_HEIGHT := 16.0
const MENU_BUTTON_SIZE := 34.0
const FS_MENU_TITLE := 13
const FS_MENU_TAB := 14
const FS_KEYCAP := 10
const FS_CURRENCY := 15

# Franja «EN CONSTRUCCIÓN» (Tienda y Pase; MMO-Tienda.html / MMO-Pase.html)
const CONSTRUCTION_HEIGHT := 36.0
const CONSTRUCTION_RADIUS := 10
const CONSTRUCTION_STRIPE := 14.0
const CONSTRUCTION_STRIPE_A := Color(245 / 255.0, 195 / 255.0, 91 / 255.0, 0.18)
const CONSTRUCTION_STRIPE_B := Color(13 / 255.0, 18 / 255.0, 22 / 255.0, 0.9)
const CONSTRUCTION_EDGE := Color(245 / 255.0, 195 / 255.0, 91 / 255.0, 0.5)
const CONSTRUCTION_BADGE_BG := Color("#f5c35b")
const CONSTRUCTION_BADGE_TEXT := Color("#1a1205")


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


# --------------------------------------------------------------------------
# Helpers UI v2.4
# --------------------------------------------------------------------------
static var _zero_regex: RegEx = null


static func has_stat(key: String) -> bool:
	return STATS.has(canonical_stat_key(key))


## Acepta clave canónica ("dano") o legacy del HUD v1 ("attack_damage").
static func canonical_stat_key(key: String) -> String:
	if STATS.has(key):
		return key
	return STAT_LEGACY_MAP.get(key, key)


## Devuelve {key, name, abbr, color: Color, bg: Color, path}; vacío si no existe.
static func stat(key: String) -> Dictionary:
	var k := canonical_stat_key(key)
	if not STATS.has(k):
		return {}
	var src: Dictionary = STATS[k]
	var c := Color(src["color"])
	return {
		"key": k, "name": src["name"], "abbr": src["abbr"], "color": c,
		"bg": Color(c, STAT_BG_ALPHA), "path": src["path"],
	}


static func stat_color(key: String) -> Color:
	var k := canonical_stat_key(key)
	return Color(STATS[k]["color"]) if STATS.has(k) else TEXT_SECONDARY


## Capas de icono (formato SvgPath.draw_layers) de una estadística.
static func stat_icon_layers(key: String) -> Array:
	var k := canonical_stat_key(key)
	if not STATS.has(k):
		return []
	return [{"d": STATS[k]["path"], "stroke": Color(STATS[k]["color"]), "width": STAT_ICON_STROKE}]


## Tamaño en px para un contexto ("hud" 16, "compare" 20, "card" 24) o tamaño canónico directo.
static func stat_icon_size(context: Variant) -> int:
	if typeof(context) == TYPE_INT and STAT_ICON_SIZES.has(context):
		return context
	return STAT_ICON_CONTEXTS.get(str(context), STAT_ICON_SIZE_HUD)


## Trazo pre-escalado a `size_px`. Array de PackedVector2Array (uno por subtrayecto).
static func stat_icon_polylines(key: String, size_px: int) -> Array:
	var k := canonical_stat_key(key)
	if not STATS.has(k):
		return []
	var s := float(size_px) / STAT_ICON_VIEWBOX
	var out: Array = []
	for sp in SvgPath.parse(STATS[k]["path"]):
		var pts := PackedVector2Array()
		for p in sp["points"]:
			pts.append(p * s)
		out.append(pts)
	return out


static func currency(key: String) -> Dictionary:
	if not CURRENCIES.has(key):
		return {}
	var src: Dictionary = CURRENCIES[key]
	return {
		"key": key, "name": src["name"], "color": Color(src["color"]),
		"text_color": Color(src["text_color"]), "purchasable": src["purchasable"],
		"earnable": src["earnable"],
	}


static func currency_icon_layers(key: String) -> Array:
	if not CURRENCIES.has(key):
		return []
	var out: Array = []
	for layer in CURRENCIES[key]["icon"]:
		var l: Dictionary = layer.duplicate()
		if l.has("fill"):
			l["fill"] = Color(l["fill"])
		if l.has("stroke"):
			l["stroke"] = Color(l["stroke"])
		out.append(l)
	return out


static func energy(key: String) -> Dictionary:
	if not ENERGIES.has(key):
		return {}
	return {"key": key, "name": ENERGIES[key]["name"], "color": Color(ENERGIES[key]["color"])}


static func energy_color(key: String) -> Color:
	return Color(ENERGIES[key]["color"]) if ENERGIES.has(key) else TEXT_SECONDARY


## Formato tabular de cantidades: 12480 -> "12.480"; -1500 -> "-1.500".
static func format_amount(value: int) -> String:
	var neg := value < 0
	var digits := str(absi(value))
	var out := ""
	var count := 0
	for idx in range(digits.length() - 1, -1, -1):
		out = digits[idx] + out
		count += 1
		if count % 3 == 0 and idx > 0:
			out = THOUSANDS_SEPARATOR + out
	return ("-" if neg else "") + out


## Valor que debe atenuarse a TEXT_ZERO (misma regex que tokens_estadisticas.js).
static func is_zero_stat_text(text: String) -> bool:
	if _zero_regex == null:
		_zero_regex = RegEx.new()
		_zero_regex.compile("^0([ ,.]0+)?\\s?%?$|^0 \\| 0 ?%$")
	return _zero_regex.search(text.strip_edges()) != null


## Devuelve {glyph, color, improves} para un delta (>0 sube, <0 baja).
## `higher_is_better=false` invierte la semántica (p. ej. costes o enfriamientos).
static func delta_style(delta: float, higher_is_better: bool = true) -> Dictionary:
	if is_zero_approx(delta):
		return {"glyph": "", "color": DELTA_NEUTRAL, "improves": false}
	var up := delta > 0.0
	var good := up == higher_is_better
	return {
		"glyph": DELTA_UP_GLYPH if up else DELTA_DOWN_GLYPH,
		"color": DELTA_UP if good else DELTA_DOWN,
		"improves": good,
	}


# ==========================================================================
# Paso 4 UI v2.4 · HUD de combate reactivo (MMO-HUD) y HUD de raid (MMO-Raid)
# ==========================================================================
# Modo Combate / Exploración.
const COMBAT_CHAT_ALPHA := 0.60                     # chat/feed atenuado en combate
const EXPLORATION_CHAT_ALPHA := 1.0
const COMBAT_FADE_TIME := 0.25                      # s (solo cosmético; el valor final se fija al instante)

# Escudo absorbente sobre la barra de vida (MMO-HUD: rgba(255,255,255,0.55)).
const SHIELD := Color(1, 1, 1, 0.55)
const SHIELD_TEXT := Color("#e8edf0")

# Interrupción: brillo dorado en habilidades de corte/aturdimiento.
const INTERRUPT_GLOW := Color("#f5c35b")
const INTERRUPT_GLOW_WIDTH := 3
const INTERRUPT_PULSE_HZ := 2.0

# Icono vectorial de stat dentro del panel de atributos del HUDv2.
const STAT_ROW_ICON := STAT_ICON_SIZE_HUD           # 16 px

# --- Raid ------------------------------------------------------------------
const RAID_SIZE := 20
const RAID_GROUPS := 4
const RAID_GROUP_SIZE := 5
const RAID_FRAME_SIZE := Vector2(128, 42)
const RAID_FRAME_GAP := Vector2(10, 3)
const RAID_FRAME_RADIUS := 8
const RAID_FRAME_BG := Color(7 / 255.0, 10 / 255.0, 12 / 255.0, 0.9)
const RAID_FRAME_EDGE := Color(1, 1, 1, 0.08)
const RAID_HEALTH := HEALTH                         # #3ccf73
const RAID_HEALTH_SEGMENTS := 10                    # tramos de 10 %
const RAID_INCOMING_HEAL := Color(60 / 255.0, 207 / 255.0, 115 / 255.0, 0.35)
const RAID_PREDICTED_A := Color(245 / 255.0, 195 / 255.0, 91 / 255.0, 0.75)
const RAID_PREDICTED_B := Color(245 / 255.0, 195 / 255.0, 91 / 255.0, 0.20)
const RAID_PREDICTED_STRIPE := 4.0                  # px por franja (patrón 135°, periodo 8 px)
const RAID_PREDICTION_WINDOW := 3.0                 # s
const RAID_AGGRO := Color("#ff6b6b")
const RAID_AGGRO_PULSE_HZ := 1.5
const RAID_SELECTED := ACCENT_DEFAULT
const RAID_HEAL_RANGE := 40.0                       # m
const RAID_OUT_OF_RANGE_ALPHA := 0.4
const RAID_DEAD_ALPHA := 0.6
const RAID_DISPEL_SIZE := 11.0
const RAID_ALERT_BG := Color(58 / 255.0, 29 / 255.0, 34 / 255.0, 0.92)
const RAID_ALERT_EDGE := Color("#ff6b6b")
const RAID_ALERT_ICON := Color("#ffb3b3")
const RAID_ALERT_SUB := Color("#ffc9c9")
const RAID_ALERT_COUNT := Color("#ff8a8a")
const RAID_ARROW_PATH := "M19 12H5M11 6l-6 6 6 6"   # flecha (apunta a la izquierda)

## Efectos purificables (rombos). Siempre color + nombre (regla 2.6).
const DISPEL_TYPES := {
	"magia": {"name": "Magia", "color": "#b47bff"},
	"veneno": {"name": "Veneno", "color": "#6fdc5a"},
	"enfermedad": {"name": "Enfermedad", "color": "#c8a25a"},
	"maldicion": {"name": "Maldición", "color": "#ff6bd0"},
}

## Color de clase (cuadradito inferior derecho del marco de raid).
const CLASS_COLORS := {
	"guerrero": "#5aa9ff", "tanque": "#5aa9ff", "sanador": "#4fe39a",
	"mago": "#ff9a4d", "arquero": "#9fe36a", "picaro": "#ffd36b", "brujo": "#b47bff",
}


static func dispel_color(kind: String) -> Color:
	return Color(DISPEL_TYPES[kind]["color"]) if DISPEL_TYPES.has(kind) else Color(DISPEL_TYPES["magia"]["color"])


static func class_color(cls: String) -> Color:
	var k := cls.strip_edges().to_lower()
	return Color(CLASS_COLORS[k]) if CLASS_COLORS.has(k) else TEXT_SECONDARY


# --------------------------------------------------------------------------
# Códice v2 · conocimiento descubrible (MMO-Codice.html / MMO-Inversiones.html)
# --------------------------------------------------------------------------
const CODEX_SECRET := Color("#c39bff")        # SECRETO / Mis secretos
const CODEX_PUBLISHED := Color("#4fe39a")     # PUBLICADO
const CODEX_PIONEER := Color("#f5c35b")       # PIONERO (oro)
const CODEX_SEEN := Color("#7c8992")          # VISTO (de lejos)
const CODEX_KNOWN := Color("#9aa6ae")         # CONOCIDO
const CODEX_SEEN_BG := Color("#18242b")
const CODEX_CARD_BG := Color("#121a20")
const CODEX_CARD_BORDER := Color(1, 1, 1, 0.07)
const CODEX_SUBNAV_ACTIVE := Color("#1c2a33")
const CODEX_WARNING := Color("#ffb86b")
const CODEX_ALERT := Color("#ff8a8a")
const CODEX_CARD_RADIUS := 12
const CODEX_BADGE_RADIUS := 10
const CODEX_SUBNAV_RADIUS := 9
const CODEX_CHART_BAR := Color("#f5c35b")     # serie única: oro por día
const CODEX_CHART_BAR_DIM := Color(Color("#f5c35b"), 0.55)
const CODEX_CHART_BASELINE := Color(1, 1, 1, 0.12)

## Estilo de insignia por visibilidad/estado (texto, fondo).
const CODEX_BADGES := {
	"pioneer": {"text": "PIONERO", "color": "#f5c35b", "bg": Color(245 / 255.0, 195 / 255.0, 91 / 255.0, 0.18)},
	"published": {"text": "PUBLICADO", "color": "#4fe39a", "bg": Color(79 / 255.0, 227 / 255.0, 154 / 255.0, 0.15)},
	"known_secret": {"text": "SECRETO", "color": "#c39bff", "bg": Color(195 / 255.0, 155 / 255.0, 255 / 255.0, 0.18)},
	"pending": {"text": "POR DECIDIR", "color": "#ffb86b", "bg": Color(255 / 255.0, 184 / 255.0, 107 / 255.0, 0.16)},
	"seen": {"text": "VISTO", "color": "#7c8992", "bg": Color("#18242b")},
	"unknown": {"text": "???", "color": "#7c8992", "bg": Color("#18242b")},
}
