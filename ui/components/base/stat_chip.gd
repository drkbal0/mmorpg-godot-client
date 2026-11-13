@tool
extends PanelContainer
## Chip compacto de estadística UI v2.4 para tooltips, fichas y comparaciones.
## [icono] [valor] (opcional: abreviatura). Fondo = color de la stat al 13 %.
## Se construye por código (sin .tscn) para poder crearse en tooltips:
##     var chip := StatChip.new(); chip.setup("critico", "25 %")

const T = preload("res://ui/tokens/hud_tokens.gd")
const VectorIcon = preload("res://ui/components/base/vector_icon.gd")

@export var stat_key: String = "dano":
	set(v):
		stat_key = T.canonical_stat_key(v)
		_refresh()

@export var value_text: String = "0":
	set(v):
		value_text = v
		_refresh()

@export var show_abbreviation: bool = false:
	set(v):
		show_abbreviation = v
		_refresh()

@export_enum("hud", "compare", "card") var icon_context: String = "hud":
	set(v):
		icon_context = v
		_refresh()

var icon: VectorIcon
var abbr_label: Label
var value_label: Label
var _row: HBoxContainer


func _init() -> void:
	theme = T.THEME
	theme_type_variation = &"StatChip"
	mouse_filter = Control.MOUSE_FILTER_PASS
	_row = HBoxContainer.new()
	_row.name = "Row"
	_row.add_theme_constant_override("separation", 5)
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_row)
	icon = VectorIcon.new()
	icon.name = "Icon"
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_row.add_child(icon)
	abbr_label = Label.new()
	abbr_label.name = "Abbr"
	abbr_label.add_theme_font_override("font", T.font("semibold"))
	abbr_label.add_theme_font_size_override("font_size", T.FS_SMALL)
	_row.add_child(abbr_label)
	value_label = Label.new()
	value_label.name = "Value"
	value_label.add_theme_font_override("font", T.font("bold"))
	value_label.add_theme_font_size_override("font_size", T.FS_BODY)
	_row.add_child(value_label)
	_refresh()


func setup(key: String, value: Variant, opts: Dictionary = {}) -> void:
	stat_key = key
	value_text = str(value) if typeof(value) != TYPE_INT else T.format_amount(value)
	show_abbreviation = bool(opts.get("abbr", show_abbreviation))
	icon_context = str(opts.get("context", icon_context))


func get_background_color() -> Color:
	return T.stat(stat_key).get("bg", Color(T.TEXT_SECONDARY, T.STAT_BG_ALPHA))


func _refresh() -> void:
	if icon == null:
		return
	var info := T.stat(stat_key)
	icon.setup_stat(stat_key, T.stat_icon_size(icon_context))
	abbr_label.text = info.get("abbr", "???")
	abbr_label.visible = show_abbreviation
	abbr_label.add_theme_color_override("font_color", info.get("color", T.TEXT_SECONDARY))
	value_label.text = value_text
	value_label.add_theme_color_override("font_color", T.TEXT_ZERO if T.is_zero_stat_text(value_text) else T.TEXT)
	var sb := T.box(get_background_color(), 8)
	sb.content_margin_left = 6
	sb.content_margin_right = 8
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	add_theme_stylebox_override("panel", sb)
	var spoken := "%s: %s" % [info.get("name", "???"), value_text]
	tooltip_text = spoken
	if "accessibility_name" in self:
		set("accessibility_name", spoken)
