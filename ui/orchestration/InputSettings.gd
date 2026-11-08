extends Node

## InputSettings.gd - Gestión de persistencia de mapeo universal de controles
## Soporta remapeo de teclas de teclado y botones de mouse por jugador con guardado persistente.

const SETTINGS_PATH = "user://settings.json"

signal bindings_updated

# Acciones soportadas y sus bindings por defecto
# formato: {"type": "key"|"mouse", "code": int}
var default_bindings = {
	"move_forward": {"type": "key", "code": KEY_W},
	"move_back": {"type": "key", "code": KEY_S},
	"move_left": {"type": "key", "code": KEY_A},
	"move_right": {"type": "key", "code": KEY_D},
	"attack_primary": {"type": "mouse", "code": MOUSE_BUTTON_LEFT},
	"cast_spell_1": {"type": "key", "code": KEY_Q},
	"cast_spell_2": {"type": "key", "code": KEY_E},
	"cast_ultimate": {"type": "key", "code": KEY_R},
	"jump": {"type": "key", "code": KEY_SPACE},
	"crouch": {"type": "key", "code": KEY_CTRL},
	"dash_evade": {"type": "key", "code": KEY_SHIFT},
	"interact": {"type": "key", "code": KEY_F},
	"toggle_camera": {"type": "key", "code": KEY_V},
	"quick_slot_1": {"type": "key", "code": KEY_1},
	"quick_slot_2": {"type": "key", "code": KEY_2},
	"quick_slot_3": {"type": "key", "code": KEY_3},
	"quick_slot_4": {"type": "key", "code": KEY_4},
	"toggle_inventory": {"type": "key", "code": KEY_I},
	"toggle_codex": {"type": "key", "code": KEY_J},
	"toggle_admin": {"type": "key", "code": KEY_F10},
	"toggle_db_admin": {"type": "key", "code": KEY_F11},
	"toggle_hitbox_debug": {"type": "key", "code": KEY_F9},
	"ui_cancel": {"type": "key", "code": KEY_ESCAPE}
}

var current_bindings: Dictionary = {}

func _ready() -> void:
	load_settings()
	apply_bindings()

func load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		current_bindings = default_bindings.duplicate(true)
		save_settings()
		return

	var file = FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	var json = JSON.parse_string(file.get_as_text())
	if json is Dictionary:
		current_bindings = json
		# Migración de viejos formatos que guardaban solo int
		for action in default_bindings.keys():
			if not current_bindings.has(action):
				current_bindings[action] = default_bindings[action].duplicate()
			elif current_bindings[action] is int or current_bindings[action] is float:
				current_bindings[action] = {"type": "key", "code": int(current_bindings[action])}
	else:
		current_bindings = default_bindings.duplicate(true)

func save_settings() -> void:
	var file = FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(current_bindings, "\t"))

func apply_bindings() -> void:
	for action in current_bindings.keys():
		var bind_info = current_bindings[action]
		_update_input_map(action, bind_info)
	bindings_updated.emit()

func update_binding(action: String, arg1, arg2 = null) -> void:
	var bind_type = "key"
	var code = 0
	if arg2 != null:
		bind_type = str(arg1)
		code = int(arg2)
	else:
		if typeof(arg1) == TYPE_STRING:
			bind_type = arg1
			code = 0
		else:
			bind_type = "key"
			code = int(arg1)

	# Limpieza 1-a-1 estricta: Si otra acción usaba esta misma tecla/botón, desvincularla
	if code > 0:
		for other_action in current_bindings.keys():
			if other_action != action:
				var other_bind = current_bindings[other_action]
				if other_bind is Dictionary and other_bind.get("type", "key") == bind_type and int(other_bind.get("code", 0)) == code:
					current_bindings[other_action] = {"type": bind_type, "code": 0}
					_update_input_map(other_action, current_bindings[other_action])
					print("[InputSettings] Desvinculada acción previa '%s' para mantener rebind 1-a-1 limpio." % other_action)

	current_bindings[action] = {"type": bind_type, "code": code}
	_update_input_map(action, current_bindings[action])
	save_settings()
	bindings_updated.emit()
	print("[InputSettings] Acción '%s' remapeada a [%s: %d]" % [action, bind_type, code])

func reset_to_defaults() -> void:
	current_bindings = default_bindings.duplicate(true)
	apply_bindings()
	save_settings()
	print("[InputSettings] Todos los controles restablecidos a predeterminados.")

func _update_input_map(action: String, bind_info: Dictionary) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)

	InputMap.action_erase_events(action)

	var bind_type = bind_info.get("type", "key")
	var code = int(bind_info.get("code", 0))

	if bind_type == "key" and code > 0:
		var ev = InputEventKey.new()
		ev.physical_keycode = code
		ev.keycode = code
		InputMap.action_add_event(action, ev)
	elif bind_type == "mouse" and code > 0:
		var ev = InputEventMouseButton.new()
		ev.button_index = code
		InputMap.action_add_event(action, ev)

func get_key_name(action: String) -> String:
	var bind_info = current_bindings.get(action, {})
	if bind_info.is_empty(): return "None"
	var btype = bind_info.get("type", "key")
	var code = int(bind_info.get("code", 0))
	if btype == "mouse":
		match code:
			MOUSE_BUTTON_LEFT: return "Clic Izq"
			MOUSE_BUTTON_RIGHT: return "Clic Der"
			MOUSE_BUTTON_MIDDLE: return "Clic Central"
			_: return "Mouse " + str(code)
	elif btype == "key":
		if code == 0: return "None"
		return OS.get_keycode_string(code)
	return "None"
