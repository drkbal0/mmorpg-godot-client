extends SceneTree
## test_options_sound.gd — Test headless de la pestaña 'Sonido' del OptionsMenu (Fase 9.13 - ADR 094)
## Verifica: pestaña existe, 5 sliders canónicos, aplicación en AudioServer, mute en 0
## y persistencia en user://settings.cfg (guardado + recarga en una nueva instancia).
## Extensión (mejoras auditoría DeepSeek Flash): guardado diferido (drag_ended + debounce),
## boot pre-load de volúmenes en SoundManager._ready() y ducking relativo a la base del usuario.

const B = preload("res://audio/audio_buses.gd")
## Carga diferida (no preload): OptionsMenu.gd referencia autoloads (UIOrchestrator) como
## identificadores globales, que en modo -s solo existen tras registrarse los autoloads.
const OPTIONS_MENU_SCENE_PATH := "res://ui/windows/OptionsMenu/OptionsMenu.tscn"
var OptionsMenuScene: PackedScene
const SETTINGS_PATH := "user://settings.cfg"
const BUSES: Array[StringName] = [B.MASTER, B.MUSIC, B.SFX, B.AMBIENCE, B.UI]
const SOUND_MANAGER_PATH := "res://audio/SoundManager.gd"

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
	_reset_buses()  # partir de 0 dB aunque el autoload haya pre-cargado un settings.cfg real

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

	# --- 2. Mover sliders: aplica en AudioServer al instante; guarda al soltar ---
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

	# Guardado diferido: value_changed NO escribe en disco de inmediato.
	check(menu.audio_save_count == 0, "[I/O] value_changed no escribe en disco al instante")
	check(not FileAccess.file_exists(SETTINGS_PATH), "[I/O] settings.cfg aún no existe antes de soltar el slider")
	check(menu.has_pending_audio_save(), "[I/O] Hay guardado pendiente tras value_changed")
	# Simular que el usuario suelta el control: drag_ended persiste una sola vez.
	for bus in targets:
		menu.audio_sliders[bus].drag_ended.emit(true)
	check(menu.audio_save_count == 1, "[I/O] drag_ended persiste con una única escritura (got %d)" % menu.audio_save_count)
	check(not menu.has_pending_audio_save(), "[I/O] Sin guardado pendiente tras drag_ended")

	var cfg := ConfigFile.new()
	check(cfg.load(SETTINGS_PATH) == OK, "settings.cfg creado en user://")
	check(cfg.has_section("audio"), "settings.cfg contiene sección [audio]")
	for bus in targets:
		check(int(cfg.get_value("audio", String(bus), -1)) == targets[bus], "[%s] Persistido = %d" % [bus, targets[bus]])

	# Arrastre continuo: decenas de value_changed -> 0 escrituras hasta drag_ended.
	var amb: HSlider = menu.audio_sliders[B.AMBIENCE]
	var amb_idx := AudioServer.get_bus_index(B.AMBIENCE)
	var saves_before: int = menu.audio_save_count
	amb.drag_started.emit()
	for v in range(26, 56):
		amb.value = v
	check(menu.audio_save_count == saves_before, "[I/O] 30 value_changed durante arrastre: 0 escrituras")
	check(absf(AudioServer.get_bus_volume_db(amb_idx) - linear_to_db(0.55)) < 0.01, "[I/O] AudioServer se actualiza en tiempo real durante el arrastre")
	check(menu.audio_percent_labels[B.AMBIENCE].text == "55%", "[I/O] Label se actualiza en tiempo real durante el arrastre")
	await create_timer(menu.AUDIO_SAVE_DEBOUNCE_SEC + 0.2).timeout
	check(menu.audio_save_count == saves_before, "[I/O] El debounce no dispara mientras se arrastra")
	amb.drag_ended.emit(true)
	check(menu.audio_save_count == saves_before + 1, "[I/O] drag_ended tras arrastre: exactamente 1 escritura")
	cfg = ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	check(int(cfg.get_value("audio", String(B.AMBIENCE), -1)) == 55, "[I/O] Valor final del arrastre persistido (55)")

	# Cambio sin arrastre (teclado/rueda): el debounce agrupa en 1 escritura.
	saves_before = menu.audio_save_count
	for v in [54, 53, 52, 25]:
		amb.value = v
	check(menu.audio_save_count == saves_before, "[I/O] Cambios sin arrastre no escriben antes del debounce")
	await create_timer(menu.AUDIO_SAVE_DEBOUNCE_SEC + 0.3).timeout
	check(menu.audio_save_count == saves_before + 1, "[I/O] Debounce agrupa 4 cambios en 1 escritura")
	cfg = ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	check(int(cfg.get_value("audio", String(B.AMBIENCE), -1)) == 25, "[I/O] Debounce persiste el último valor (25)")

	# Re-activar un bus silenciado
	menu.audio_sliders[B.SFX].value = 40
	var sfx_idx := AudioServer.get_bus_index(B.SFX)
	check(not AudioServer.is_bus_mute(sfx_idx) and absf(AudioServer.get_bus_volume_db(sfx_idx) - linear_to_db(0.4)) < 0.01, "[SFX] Subir de 0 a 40 quita el mute")
	# Cerrar el menú con cambios pendientes los persiste (_exit_tree).
	check(menu.has_pending_audio_save(), "[I/O] Cambio SFX=40 pendiente antes de cerrar")
	menu.free()

	# --- 3. Recarga: nueva instancia lee settings.cfg ---
	# Resetear AudioServer para comprobar que la carga lo re-aplica.
	_reset_buses()
	var expected := {B.MASTER: 80, B.MUSIC: 50, B.SFX: 40, B.AMBIENCE: 25, B.UI: 100}
	var menu2 = await _spawn_menu()
	for bus in expected:
		var slider: HSlider = menu2.audio_sliders.get(bus)
		check(slider != null and int(slider.value) == expected[bus], "[%s] Recarga slider = %d" % [bus, expected[bus]])
		var i := AudioServer.get_bus_index(bus)
		check(absf(AudioServer.get_bus_volume_db(i) - linear_to_db(expected[bus] / 100.0)) < 0.01, "[%s] Recarga aplica volumen en AudioServer" % bus)
	menu2.free()

	await _test_boot_preload(expected)
	await _test_relative_ducking()

	_restore_environment()

	print("== OptionsMenu Sonido: %d checks OK, %d fallos ==" % [_checks_passed, _checks_failed])
	quit(0 if _checks_failed == 0 else 1)


# --- 4. Boot pre-load: SoundManager._ready() aplica user://settings.cfg ---
func _test_boot_preload(expected: Dictionary) -> void:
	print("-- Boot pre-load SoundManager --")
	_reset_buses()
	var sm = await _spawn_sound_manager()
	for bus in expected:
		var i := AudioServer.get_bus_index(bus)
		check(absf(AudioServer.get_bus_volume_db(i) - linear_to_db(expected[bus] / 100.0)) < 0.01,
			"[Boot][%s] _ready() aplica %d%% desde settings.cfg" % [bus, expected[bus]])
	check(absf(sm.user_music_base_db - linear_to_db(0.5)) < 0.01, "[Boot] user_music_base_db = base Music guardada (%.2f dB)" % sm.user_music_base_db)
	sm.free()

	# Valor 0 guardado -> bus silenciado al arrancar.
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("audio", String(B.UI), 0)
	cfg.save(SETTINGS_PATH)
	_reset_buses()
	sm = await _spawn_sound_manager()
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index(B.UI)), "[Boot][UI] Valor 0 guardado silencia el bus al arrancar")
	sm.free()
	cfg.set_value("audio", String(B.UI), 100)
	cfg.save(SETTINGS_PATH)

	# Sin settings.cfg: buses en su valor por defecto (0 dB, sin mute).
	var bytes := FileAccess.get_file_as_bytes(SETTINGS_PATH)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_PATH))
	_reset_buses()
	sm = await _spawn_sound_manager()
	var all_default := true
	for bus in BUSES:
		var i := AudioServer.get_bus_index(bus)
		if not is_equal_approx(AudioServer.get_bus_volume_db(i), 0.0) or AudioServer.is_bus_mute(i):
			all_default = false
	check(all_default, "[Boot] Sin settings.cfg los buses quedan a 100% / 0 dB")
	check(is_equal_approx(sm.user_music_base_db, 0.0), "[Boot] Sin settings.cfg user_music_base_db = 0 dB")
	check(sm.load_and_apply_saved_volumes() == 0, "[Boot] Sin settings.cfg no se aplica ningún bus")
	sm.free()

	# settings.cfg sin sección [audio]: tampoco toca los buses.
	var other := ConfigFile.new()
	other.set_value("video", "vsync", true)
	other.save(SETTINGS_PATH)
	sm = await _spawn_sound_manager()
	check(sm.load_and_apply_saved_volumes() == 0, "[Boot] settings.cfg sin [audio] no aplica buses")
	sm.free()

	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()


# --- 5. Ducking relativo a la base del usuario ---
func _test_relative_ducking() -> void:
	print("-- Ducking relativo --")
	var sm = root.get_node_or_null("SoundManager")
	check(sm != null, "[Duck] Autoload SoundManager presente")
	if sm == null:
		return
	var music_idx := AudioServer.get_bus_index(B.MUSIC)
	_reset_buses()
	sm.load_and_apply_saved_volumes()  # Music = 50% -> ~-6.02 dB
	var base: float = linear_to_db(0.5)
	check(absf(sm.user_music_base_db - base) < 0.01, "[Duck] Base de usuario cargada (%.2f dB)" % base)

	sm.play_hitmarker(B.HitmarkerType.CONFIRM)
	check(sm.is_in_combat(), "[Duck] Hitmarker activa el estado de combate")
	await create_timer(0.35).timeout
	check(absf(AudioServer.get_bus_volume_db(music_idx) - (base - 6.0)) < 0.05,
		"[Duck] En combate Music = base - 6 dB (%.2f, esperado %.2f)" % [AudioServer.get_bus_volume_db(music_idx), base - 6.0])

	# Cambiar el volumen de música desde Opciones en pleno combate respeta el ducking.
	var menu = await _spawn_menu()
	menu.audio_sliders[B.MUSIC].value = 25
	var base25: float = linear_to_db(0.25)
	check(absf(sm.user_music_base_db - base25) < 0.01, "[Duck] OptionsMenu actualiza user_music_base_db")
	check(absf(AudioServer.get_bus_volume_db(music_idx) - (base25 - 6.0)) < 0.01,
		"[Duck] Cambio de Music en combate mantiene -6 dB relativos (%.2f)" % AudioServer.get_bus_volume_db(music_idx))
	menu.audio_sliders[B.MUSIC].drag_ended.emit(true)
	menu.free()

	# Salir de combate: restaura exactamente a la base del usuario, no a 0 dB.
	sm._combat_timer = 0.0
	await create_timer(0.9).timeout
	check(not sm.is_in_combat(), "[Duck] Fin del combate tras expirar el temporizador")
	var restored := AudioServer.get_bus_volume_db(music_idx)
	check(absf(restored - base25) < 0.01, "[Duck] Al salir de combate restaura a la base del usuario (%.2f dB)" % restored)
	check(absf(restored) > 1.0, "[Duck] No restaura a 0 dB rígido")

	# Base a 100% (0 dB): ducking a -6 dB y restauración a 0 dB.
	sm.set_user_music_base_db(0.0)
	sm._trigger_combat_activity()
	await create_timer(0.35).timeout
	check(absf(AudioServer.get_bus_volume_db(music_idx) + 6.0) < 0.05, "[Duck] Base 0 dB -> combate a -6 dB")
	sm._combat_timer = 0.0
	await create_timer(0.9).timeout
	check(absf(AudioServer.get_bus_volume_db(music_idx)) < 0.01, "[Duck] Base 0 dB -> restaura a 0 dB")


func _spawn_sound_manager() -> Node:
	var sm = (load(SOUND_MANAGER_PATH) as GDScript).new()
	sm.name = "SoundManagerBootTest"
	root.add_child(sm)
	await process_frame
	return sm


func _reset_buses() -> void:
	for bus in BUSES:
		var i := AudioServer.get_bus_index(bus)
		AudioServer.set_bus_volume_db(i, 0.0)
		AudioServer.set_bus_mute(i, false)


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
	var sm = root.get_node_or_null("SoundManager")
	if sm:
		sm.user_music_base_db = AudioServer.get_bus_volume_db(AudioServer.get_bus_index(B.MUSIC))


func check(cond: bool, msg: String) -> void:
	if cond:
		_checks_passed += 1
		print("  [PASS] ", msg)
	else:
		_checks_failed += 1
		printerr("  [FAIL] ", msg)
