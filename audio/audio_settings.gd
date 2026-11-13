extends RefCounted
## audio_settings.gd — Helper estático de persistencia de volúmenes (Fase 9.13 - ADR 094)
## Fuente única de verdad para leer user://settings.cfg [audio] y aplicar volúmenes a
## los buses de AudioServer. Lo usan SoundManager (boot pre-load) y OptionsMenu.

const B = preload("res://audio/audio_buses.gd")

const SETTINGS_PATH := "user://settings.cfg"
const AUDIO_SECTION := "audio"
const DEFAULT_VOLUME := 100.0
const MUTE_DB := -80.0
## Buses persistidos/expuestos al jugador.
const PERSISTED_BUSES: Array[StringName] = [B.MASTER, B.MUSIC, B.SFX, B.AMBIENCE, B.UI]


## Convierte un porcentaje 0-100 a dB (0 -> MUTE_DB).
static func percent_to_db(value: float) -> float:
	if value <= 0.0:
		return MUTE_DB
	return linear_to_db(value / 100.0)


## Lee la sección [audio]. Devuelve { bus: float 0-100 } solo con las claves presentes
## en el archivo. Diccionario vacío si el archivo no existe o no tiene sección [audio].
static func load_saved_volumes(path: String = SETTINGS_PATH) -> Dictionary:
	var result := {}
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK or not cfg.has_section(AUDIO_SECTION):
		return result
	for bus in PERSISTED_BUSES:
		if cfg.has_section_key(AUDIO_SECTION, String(bus)):
			result[bus] = clampf(float(cfg.get_value(AUDIO_SECTION, String(bus), DEFAULT_VOLUME)), 0.0, 100.0)
	return result


## Aplica un porcentaje 0-100 al bus indicado (0 = mute). Devuelve false si el bus no existe.
static func apply_bus_volume(bus: StringName, value: float) -> bool:
	var idx := AudioServer.get_bus_index(bus)
	if idx < 0:
		return false
	AudioServer.set_bus_mute(idx, value <= 0.0)
	AudioServer.set_bus_volume_db(idx, percent_to_db(value))
	return true


## Guarda los volúmenes { bus: float } en [audio], conservando otras secciones.
static func save_volumes(volumes: Dictionary, path: String = SETTINGS_PATH) -> Error:
	var cfg := ConfigFile.new()
	cfg.load(path)
	for bus in volumes.keys():
		cfg.set_value(AUDIO_SECTION, String(bus), int(round(volumes[bus])))
	return cfg.save(path)
