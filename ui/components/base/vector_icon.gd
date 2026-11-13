@tool
extends Control
## Icono vectorial (UI v2.4). Dibuja con `_draw()` un icono SVG del viewBox 24×24
## sin texturas: estadísticas (Anexo A), monedas (sección 2.2) o capas propias.
##
##   icon.setup_stat("armadura", 20)      # 16 HUD · 20 comparación · 24 ficha
##   icon.setup_currency("prismas", 16)
##   icon.custom_layers = [{"d": "M4 4h16", "stroke": Color.WHITE, "width": 2.0}]

const T = preload("res://ui/tokens/hud_tokens.gd")
const SvgPath = preload("res://ui/icons/svg_path.gd")

const KIND_STAT := "stat"
const KIND_CURRENCY := "currency"
const KIND_CUSTOM := "custom"

@export_enum("stat", "currency", "custom") var icon_kind: String = KIND_STAT:
	set(v):
		icon_kind = v
		_refresh()

@export var icon_key: String = "":
	set(v):
		icon_key = v
		_refresh()

@export var icon_size: int = T.STAT_ICON_SIZE_HUD:
	set(v):
		icon_size = maxi(1, v)
		_refresh()

## Si alfa > 0, sustituye el color principal (p. ej. modos de daltonismo o estado deshabilitado).
@export var tint: Color = Color(0, 0, 0, 0):
	set(v):
		tint = v
		queue_redraw()

var custom_layers: Array = []:
	set(v):
		custom_layers = v
		if not v.is_empty():
			icon_kind = KIND_CUSTOM
		_refresh()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_refresh()


func setup_stat(key: String, size_px: int = T.STAT_ICON_SIZE_HUD) -> void:
	icon_kind = KIND_STAT
	icon_key = T.canonical_stat_key(key)
	icon_size = size_px


func setup_currency(key: String, size_px: int = 16) -> void:
	icon_kind = KIND_CURRENCY
	icon_key = key
	icon_size = size_px


## Capas efectivas a dibujar (vacío si la clave no existe).
func get_layers() -> Array:
	match icon_kind:
		KIND_STAT:
			return T.stat_icon_layers(icon_key)
		KIND_CURRENCY:
			return T.currency_icon_layers(icon_key)
		_:
			return custom_layers


func has_icon() -> bool:
	return not get_layers().is_empty()


func _refresh() -> void:
	custom_minimum_size = Vector2(icon_size, icon_size)
	queue_redraw()


func _draw() -> void:
	var layers := get_layers()
	if layers.is_empty():
		return
	var side := float(icon_size)
	var origin := ((size - Vector2(side, side)) * 0.5).floor()
	SvgPath.draw_layers(self, layers, Rect2(origin, Vector2(side, side)), tint)
