@tool
extends HBoxContainer
## Etiqueta de moneda UI v2.4: [icono vectorial] [cantidad tabular] (+).
## Oro (#f5c35b) se gana jugando; Prismas (#7ee8ff) se compran y llevan botón
## «+» que abre la Tienda (señal `add_requested`).

const T = preload("res://ui/tokens/hud_tokens.gd")
const VectorIcon = preload("res://ui/components/base/vector_icon.gd")

signal add_requested(currency_key: String)

@export_enum("oro", "prismas") var currency_key: String = "oro":
	set(v):
		currency_key = v
		_refresh()

@export var amount: int = 0:
	set(v):
		amount = v
		_refresh()

## null/auto: solo Prismas (moneda comprable) muestra «+».
@export_enum("auto", "show", "hide") var add_button_mode: String = "auto":
	set(v):
		add_button_mode = v
		_refresh()

@export var icon_size: int = 16:
	set(v):
		icon_size = v
		_refresh()

@export var font_size: int = T.FS_CURRENCY:
	set(v):
		font_size = v
		_refresh()

var icon: VectorIcon
var amount_label: Label
var add_button: Button


func _init() -> void:
	theme = T.THEME
	add_theme_constant_override("separation", 6)
	alignment = BoxContainer.ALIGNMENT_CENTER
	icon = VectorIcon.new()
	icon.name = "Icon"
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(icon)
	amount_label = Label.new()
	amount_label.name = "Amount"
	amount_label.add_theme_font_override("font", T.font("bold"))
	amount_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(amount_label)
	add_button = Button.new()
	add_button.name = "Add"
	add_button.text = "+"
	add_button.focus_mode = Control.FOCUS_ALL
	add_button.custom_minimum_size = Vector2(18, 18)
	add_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_button.add_theme_font_override("font", T.font("bold"))
	add_button.add_theme_font_size_override("font_size", 12)
	var sb := T.box(T.BUTTON_BG, 5, 1, Color(T.PRISMS, 0.35))
	add_button.add_theme_stylebox_override("normal", sb)
	add_button.add_theme_stylebox_override("hover", T.box(T.SLOT_READY, 5, 1, T.PRISMS))
	add_button.add_theme_stylebox_override("pressed", T.box(T.SLOT_READY, 5, 1, T.PRISMS))
	add_button.add_theme_stylebox_override("focus", T.box(Color.TRANSPARENT, 5, 1, T.PRISMS))
	add_button.pressed.connect(func() -> void: add_requested.emit(currency_key))
	add_child(add_button)
	_refresh()


func setup(key: String, value: int, mode: String = "auto") -> void:
	currency_key = key
	amount = value
	add_button_mode = mode


func set_amount(value: int) -> void:
	amount = value


func get_amount_text() -> String:
	return T.format_amount(amount)


func is_add_button_visible() -> bool:
	match add_button_mode:
		"show":
			return true
		"hide":
			return false
	return bool(T.currency(currency_key).get("purchasable", false))


func _refresh() -> void:
	if icon == null:
		return
	var info := T.currency(currency_key)
	icon.setup_currency(currency_key, icon_size)
	amount_label.text = get_amount_text()
	amount_label.add_theme_font_size_override("font_size", font_size)
	amount_label.add_theme_color_override("font_color", info.get("text_color", T.TEXT))
	add_button.visible = is_add_button_visible()
	add_button.add_theme_color_override("font_color", info.get("text_color", T.TEXT))
	var spoken := "%s: %s" % [info.get("name", "???"), get_amount_text()]
	tooltip_text = spoken
	if "accessibility_name" in self:
		set("accessibility_name", spoken)
	if "accessibility_name" in add_button:
		add_button.set("accessibility_name", "Comprar %s" % info.get("name", ""))
