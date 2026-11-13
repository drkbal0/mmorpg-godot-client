@tool
extends HBoxContainer
## Fila de estadística UI v2.4 (Equipo, comparaciones, tooltips, HUD).
## [icono SVG] [nombre o abreviatura] ........ [valor tabular] [▲/▼ delta]
##
## Regla 2.6: icono + color + texto; nunca solo el color. Los deltas llevan ▲▼
## además del verde/rojo. Sin textos fijos: todo llega por `setup()`.

const T = preload("res://ui/tokens/hud_tokens.gd")
const VectorIcon = preload("res://ui/components/base/vector_icon.gd")

signal hovered(stat_key: String)

@export var stat_key: String = "dano":
	set(v):
		stat_key = T.canonical_stat_key(v)
		_refresh()

@export var value_text: String = "0":
	set(v):
		value_text = v
		_refresh()

## 0 = sin delta. >0 sube, <0 baja.
@export var delta: float = 0.0:
	set(v):
		delta = v
		_refresh()

@export var delta_text: String = "":
	set(v):
		delta_text = v
		_refresh()

## false para estadísticas donde bajar es mejorar.
@export var higher_is_better: bool = true:
	set(v):
		higher_is_better = v
		_refresh()

@export var use_abbreviation: bool = false:
	set(v):
		use_abbreviation = v
		_refresh()

## "hud" (16 px) · "compare" (20 px) · "card" (24 px).
@export_enum("hud", "compare", "card") var icon_context: String = "hud":
	set(v):
		icon_context = v
		_refresh()

@onready var icon: VectorIcon = $Icon
@onready var name_label: Label = $Name
@onready var value_label: Label = $Value
@onready var delta_label: Label = $Delta


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	name_label.add_theme_font_override("font", T.font("medium"))
	value_label.add_theme_font_override("font", T.font("bold"))
	delta_label.add_theme_font_override("font", T.font("semibold"))
	mouse_entered.connect(func() -> void: hovered.emit(stat_key))
	_refresh()


## API de datos: setup("armadura", 142, +12) / setup("critico", "25 %", -5, {"abbr": true}).
func setup(key: String, value: Variant, delta_value: float = 0.0, opts: Dictionary = {}) -> void:
	stat_key = key
	value_text = format_value(value)
	delta = delta_value
	delta_text = str(opts.get("delta_text", ""))
	higher_is_better = bool(opts.get("higher_is_better", true))
	use_abbreviation = bool(opts.get("abbr", use_abbreviation))
	icon_context = str(opts.get("context", icon_context))


func set_value(value: Variant) -> void:
	value_text = format_value(value)


func set_delta(delta_value: float, text: String = "", better_when_higher: bool = true) -> void:
	higher_is_better = better_when_higher
	delta_text = text
	delta = delta_value


static func format_value(v: Variant) -> String:
	match typeof(v):
		TYPE_INT:
			return T.format_amount(v)
		TYPE_FLOAT:
			var f: float = v
			if is_equal_approx(f, roundf(f)):
				return T.format_amount(int(roundf(f)))
			return ("%.1f" % f).replace(".", ",")
		_:
			return str(v)


## Texto del delta con glifo: "▲ 12", "▼ 5"; vacío si delta = 0.
func get_delta_display() -> String:
	var style := T.delta_style(delta, higher_is_better)
	if style["glyph"] == "":
		return ""
	var amount := delta_text if delta_text != "" else format_value(absf(delta))
	return "%s %s" % [style["glyph"], amount]


func get_delta_color() -> Color:
	return T.delta_style(delta, higher_is_better)["color"]


func get_value_color() -> Color:
	return T.TEXT_ZERO if T.is_zero_stat_text(value_text) else T.TEXT


func get_display_name() -> String:
	var info := T.stat(stat_key)
	if info.is_empty():
		return "???"
	return info["abbr"] if use_abbreviation else info["name"]


func _refresh() -> void:
	if not is_node_ready():
		return
	var info := T.stat(stat_key)
	icon.setup_stat(stat_key, T.stat_icon_size(icon_context))
	name_label.text = get_display_name()
	name_label.add_theme_color_override("font_color", T.TEXT_SECONDARY)
	value_label.text = value_text
	value_label.add_theme_color_override("font_color", get_value_color())
	var dtxt := get_delta_display()
	delta_label.text = dtxt
	delta_label.visible = dtxt != ""
	delta_label.add_theme_color_override("font_color", get_delta_color())
	var spoken := "%s: %s" % [info.get("name", "???"), value_text]
	if dtxt != "":
		spoken += " (%s %s)" % ["mejora" if T.delta_style(delta, higher_is_better)["improves"] else "empeora", dtxt.substr(2)]
	tooltip_text = spoken
	if "accessibility_name" in self:
		set("accessibility_name", spoken)
