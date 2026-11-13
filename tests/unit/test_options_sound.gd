extends SceneTree
## test_options_sound.gd — Test headless de la pestaña 'Sonido' del OptionsMenu (Fase 9.13 - ADR 094)
## Verifica: pestaña existe, 5 sliders canónicos, aplicación en AudioServer, mute en 0
## y persistencia en user://settings.cfg (guardado + recarga en una nueva instancia).

const B = preload("res://audio/audio_buses.gd")
## Carga diferida (no preload): OptionsMenu.gd referencia autoloads (UIOrchestrator) como
## identificadores globales, que en modo -s solo existen tras registrarse los autoloads.
const OPTIONS_MENU_SCENE_PATH := "res://ui/windows/OptionsMenu/OptionsMenu.tscn"
var OptionsMenuScene: PackedScene
const SETTINGS_PATH := "user://settings.cfg"
const BUSES: Array[StringName] = [B.MASTER, B.MUSIC, B.SFX, B.AMBIENCE, B.UI]

var _checks_passed: int = 0
var _checks_failed: int = 0
var _backup_bytes: PackedByteArray = PackedByteArray()
var _had_backup: bool = false
var _bus_state: Dictionary = {}


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	print("== Test OptionsMenu: pestaña Sonido (Fase 9.13 - ADR 094) ==")
	await process_frame  # asegurar autoloads listos en root
	OptionsMenuScene = load(OPTIONS_MENU_SCENE_PATH)
	check(OptionsMenuScene != null, "OptionsMenu.tscn carga correctamente")

	_backup_environment()

	# --- 1. Sin settings.cfg: todo por defecto a 100 ---
	var menu = await _spawn_menu()
	var tabs: TabContainer = menu.find_child("TabContainer", true, false)
	check(tabs != null, "TabContainer existe en OptionsMenu")
	var sound_tab: Control = tabs.get_node_or_null("Sonido") if tabs else null
	check(sound_tab != null, "Pestaña 'Sonido' existe en el TabContainer")
	check(sound_tab is MarginContainer, "Pestaña 'Sonido' es un MarginContainer")
	if tabs and sound_tab:
		check(tabs.get_tab_title(sound_tab.get_index()) == "Sonido", "Título de la pestaña es 'Sonido'")
		check(sound_tab.find_child("AudioSettingsList", true, false) is VBoxContainer, "Pestaña contiene VBoxContainer de ajustes")

	for bus in BUSES:
		var slider: HSlider = sound_tab.find_child("VolumeSlider_%s" % bus, true, false) if sound_tab else null
		var lbl: Label = sound_tab.find_child("VolumePercent_%s" % bus, true, false) if sound_tab else null
		var idx := AudioServer.get_bus_index(bus)
		check(slider != null, "[%s] HSlider existe" % bus)
		check(lbl != null, "[%s] Label de porcentaje existe" % bus)
		check(idx >= 0, "[%s] Bus existe en AudioServer" % bus)
		if slider == null or lbl == null or idx < 0:
			continue
		check(slider.min_value == 0 and slider.max_value == 100 and slider.step == 1, "[%s] Rango 0-100 paso 1" % bus)
		check(slider.value == 100, "[%s] Default 100 sin settings.cfg" % bus)
		check(lbl.text == "100%", "[%s] Label inicial '100%%'" % bus)
		check(is_equal_approx(AudioServer.get_bus_volume_db(idx), 0.0) and not AudioServer.is_bus_mute(idx), "[%s] AudioServer a 0 dB y sin mute" % bus)

	# --- 2. Mover sliders: aplica en AudioServer y guarda ---
	var targets := {B.MASTER: 80, B.MUSIC: 50, B.SFX: 0, B.AMBIENCE: 25, B.UI: 100}
	for bus in targets:
		var slider: HSlider = menu.audio_sliders.get(bus)
		if slider: slider.value = targets[bus]

	for bus in targets:
		var idx := AudioServer.get_bus_index(bus)
		var v: int = targets[bus]
		var lbl: Label = menu.audio_percent_labels.get(bus)
		check(lbl != null and lbl.text == "%d%%" % v, "[%s] Label actualizado a %d%%" % [bus, v])
		if v == 0:
			check(AudioServer.is_bus_mute(idx), "[%s] Valor 0 silencia el bus" % bus)
		else:
			check(not AudioServer.is_bus_mute(idx), "[%s] Valor %d no silenciado" % [bus, v])
			check(absf(AudioServer.get_bus_volume_db(idx) - linear_to_db(v / 100.0)) < 0.01,
				"[%s] volume_db = linear_to_db(%d/100) (%.2f dB)" % [bus, v, AudioServer.get_bus_volume_db(idx)])

	var cfg := ConfigFile.new()
	check(cfg.load(SETTINGS_PATH) == OK, "settings.cfg creado en user://")
	check(cfg.has_section("audio"), "settings.cfg contiene sección [audio]")
	for bus in targets:
		check(int(cfg.get_value("audio", String(bus), -1)) == targets[bus], "[%s] Persistido = %d" % [bus, targets[bus]])

	# Re-activar un bus silenciado
	menu.audio_sliders[B.SFX].value = 40
	var sfx_idx := AudioServer.get_bus_index(B.SFX)
	check(not AudioServer.is_bus_mute(sfx_idx) and absf(AudioServer.get_bus_volume_db(sfx_idx) - linear_to_db(0.4)) < 0.01, "[SFX] Subir de 0 a 40 quita el mute")
	menu.free()

	# --- 3. Recarga: nueva instancia lee settings.cfg ---
	# Resetear AudioServer para comprobar que la carga lo re-aplica.
	for bus in BUSES:
		var i := AudioServer.get_bus_index(bus)
		AudioServer.set_bus_volume_db(i, 0.0)
		AudioServer.set_bus_mute(i, false)
	var expected := {B.MASTER: 80, B.MUSIC: 50, B.SFX: 40, B.AMBIENCE: 25, B.UI: 100}
	var menu2 = await _spawn_menu()
	for bus in expected:
		var slider: HSlider = menu2.audio_sliders.get(bus)
		check(slider != null and int(slider.value) == expected[bus], "[%s] Recarga slider = %d" % [bus, expected[bus]])
		var i := AudioServer.get_bus_index(bus)
		check(absf(AudioServer.get_bus_volume_db(i) - linear_to_db(expected[bus] / 100.0)) < 0.01, "[%s] Recarga aplica volumen en AudioServer" % bus)
	menu2.free()

	_restore_environment()

	print("== OptionsMenu Sonido: %d checks OK, %d fallos ==" % [_checks_passed, _checks_failed])
	quit(0 if _checks_failed == 0 else 1)


func _spawn_menu() -> Node:
	var m = OptionsMenuScene.instantiate()
	root.add_child(m)
	await process_frame
	return m


func _backup_environment() -> void:
	if FileAccess.file_exists(SETTINGS_PATH):
		_had_backup = true
		_backup_bytes = FileAccess.get_file_as_bytes(SETTINGS_PATH)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_PATH))
	for bus in BUSES:
		var i := AudioServer.get_bus_index(bus)
		if i >= 0:
			_bus_state[bus] = [AudioServer.get_bus_volume_db(i), AudioServer.is_bus_mute(i)]


func _restore_environment() -> void:
	if _had_backup:
		var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
		f.store_buffer(_backup_bytes)
		f.close()
	elif FileAccess.file_exists(SETTINGS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_PATH))
	for bus in _bus_state:
		var i := AudioServer.get_bus_index(bus)
		AudioServer.set_bus_volume_db(i, _bus_state[bus][0])
		AudioServer.set_bus_mute(i, _bus_state[bus][1])


func check(cond: bool, msg: String) -> void:
	if cond:
		_checks_passed += 1
		print("  [PASS] ", msg)
	else:
		_checks_failed += 1
		printerr("  [FAIL] ", msg)
