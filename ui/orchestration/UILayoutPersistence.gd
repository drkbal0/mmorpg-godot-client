extends Node

# UILayoutPersistence.gd - Gestión de guardado/carga de posiciones de ventanas
# Propósito: Guardar dónde dejó el usuario las ventanas para mejorar la UX.

const SAVE_PATH = "user://layout_cache.json"
var layout_data: Dictionary = {}

signal zoom_changed(new_zoom: float)
var global_ui_zoom: float = 1.0

signal hud_scale_changed(new_scale: float)
var hud_scale: float = 1.0

func _ready():
	load_layout()

func load_layout():
	if FileAccess.file_exists(SAVE_PATH):
		var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
		var text = file.get_as_text()
		var json = JSON.parse_string(text)
		if json is Dictionary:
			layout_data = json
			if layout_data.has("_global_ui_zoom"):
				global_ui_zoom = float(layout_data["_global_ui_zoom"])
			if layout_data.has("_hud_scale"):
				hud_scale = float(layout_data["_hud_scale"])
		else:
			layout_data = {}
	else:
		layout_data = {}
	print("[UILayoutPersistence] Layout cargado. Zoom: %s, HUD Scale: %s" % [str(global_ui_zoom), str(hud_scale)])

func save_layout():
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(layout_data))

func get_window_position(window_id: String) -> Variant:
	if layout_data.has(window_id):
		var pos = layout_data[window_id]
		if pos is Dictionary and pos.has("x") and pos.has("y"):
			return Vector2(pos.x, pos.y)
	return null

func set_window_position(window_id: String, pos: Vector2):
	layout_data[window_id] = {"x": pos.x, "y": pos.y}
	save_layout()

func set_global_zoom(new_zoom: float):
	global_ui_zoom = new_zoom
	layout_data["_global_ui_zoom"] = new_zoom
	save_layout()
	zoom_changed.emit(global_ui_zoom)
	print("[UILayoutPersistence] Zoom global actualizado a: ", global_ui_zoom)

func set_hud_scale(new_scale: float):
	hud_scale = clamp(new_scale, 0.7, 1.3)
	layout_data["_hud_scale"] = hud_scale
	save_layout()
	hud_scale_changed.emit(hud_scale)
	print("[UILayoutPersistence] Escala HUD de combate actualizada a: ", hud_scale)

# Limpia posiciones de ventanas que ya no existen (ej: mochilas viejas)
# NOTA: Esto podría ejecutarse periódicamente o al inicio
func cleanup_stale_entries(active_ids: Array):
	var changed = false
	var keys = layout_data.keys()
	for key in keys:
		if key.begins_with("backpack_") and not key in active_ids:
			layout_data.erase(key)
			changed = true
	if changed:
		save_layout()
