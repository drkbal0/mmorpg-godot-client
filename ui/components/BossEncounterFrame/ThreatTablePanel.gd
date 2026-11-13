extends PanelContainer
class_name ThreatTablePanel

## ThreatTablePanel.gd — Tabla de amenaza del World Boss (Phase 9.6, ADR 098).
## Lista ordenada de los N jugadores con más amenaza, con el % relativo al
## Top 1 (misma fórmula que ThreatTable::get_player_threat_pct en Rust).

const T = preload("res://ui/tokens/hud_tokens.gd")
const COLOR_SELF := Color("#ef4444")
const COLOR_TANK := Color("#3b82f6")
const COLOR_DEFAULT := Color("#f59e0b")
const MAX_ROWS := 5

var _rows_box: VBoxContainer
var entries: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(250, 0)
	add_theme_stylebox_override("panel", T.box(Color(0.04, 0.05, 0.08, 0.9), 8, 1, Color(0.88, 0.23, 0.23, 0.75)))
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	add_child(margin)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	margin.add_child(vb)
	var title := Label.new()
	title.text = "TABLA DE AMENAZA · VAL'GORATH"
	title.add_theme_font_override("font", T.font("bold"))
	title.add_theme_font_size_override("font_size", 10)
	title.add_theme_color_override("font_color", Color("#ef4444"))
	vb.add_child(title)
	_rows_box = VBoxContainer.new()
	_rows_box.add_theme_constant_override("separation", 3)
	vb.add_child(_rows_box)
	if not entries.is_empty():
		set_entries(entries)


## entries: [{"name": String, "threat": float, "is_self": bool, "role": String}]
func set_entries(p_entries: Array) -> void:
	entries = p_entries.duplicate(true)
	entries.sort_custom(func(a, b): return float(a["threat"]) > float(b["threat"]))
	if _rows_box == null:
		return
	for c in _rows_box.get_children():
		c.queue_free()
	var top := float(entries[0]["threat"]) if not entries.is_empty() else 0.0
	for i in range(mini(entries.size(), MAX_ROWS)):
		_rows_box.add_child(_make_row(i + 1, entries[i], top))


func get_threat_pct(index: int) -> int:
	if index >= entries.size() or entries.is_empty():
		return 0
	var top := float(entries[0]["threat"])
	return 0 if top <= 0.0 else clampi(int(float(entries[index]["threat"]) / top * 100.0), 0, 100)


func _make_row(rank: int, e: Dictionary, top: float) -> Control:
	var pct := 0.0 if top <= 0.0 else clampf(float(e["threat"]) / top, 0.0, 1.0)
	var is_self := bool(e.get("is_self", false))
	var col := COLOR_SELF if is_self else (COLOR_TANK if str(e.get("role", "")) == "tank" else COLOR_DEFAULT)

	var row := Control.new()
	row.custom_minimum_size = Vector2(234, 20)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var bar_bg := ColorRect.new()
	bar_bg.color = Color(1, 1, 1, 0.05)
	bar_bg.position = Vector2(0, 0)
	bar_bg.size = Vector2(234, 20)
	row.add_child(bar_bg)
	var bar := ColorRect.new()
	bar.color = Color(col, 0.38 if is_self else 0.26)
	bar.position = Vector2(0, 0)
	bar.size = Vector2(234.0 * pct, 20)
	row.add_child(bar)

	var name_lbl := Label.new()
	name_lbl.text = "%d. %s%s" % [rank, str(e["name"]), "  (TÚ)" if is_self else ""]
	name_lbl.position = Vector2(6, 2)
	name_lbl.add_theme_font_override("font", T.font("bold" if is_self else "semibold"))
	name_lbl.add_theme_font_size_override("font_size", 10)
	name_lbl.add_theme_color_override("font_color", Color.WHITE if is_self else Color(0.85, 0.9, 0.95))
	row.add_child(name_lbl)

	var val_lbl := Label.new()
	val_lbl.text = "%s  %d%%" % [_fmt(int(e["threat"])), int(round(pct * 100.0))]
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_lbl.position = Vector2(120, 2)
	val_lbl.size = Vector2(108, 16)
	val_lbl.add_theme_font_override("font", T.font("bold"))
	val_lbl.add_theme_font_size_override("font_size", 10)
	val_lbl.add_theme_color_override("font_color", col.lightened(0.25))
	row.add_child(val_lbl)
	return row


static func _fmt(n: int) -> String:
	var s := str(n)
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return out
