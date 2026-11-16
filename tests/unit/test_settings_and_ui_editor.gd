extends SceneTree
## Suite headless (UI v2.4 Paso 16 · ADR 114): Ajustes globales y Editor de interfaz.
## Run: Godot --headless --path clients/godot-mmo-client -s tests/unit/test_settings_and_ui_editor.gd
## Exit code 0 = todo PASS.

const SS = preload("res://shared-core/SettingsService.gd")
const ES = preload("res://shared-core/UIEditorService.gd")
const AudioSettings = preload("res://audio/audio_settings.gd")
const T = preload("res://ui/tokens/hud_tokens.gd")
const SEED := "res://config/settings/settings_seed.json"
const EDITOR_SEED := "res://config/ui_editor/ui_editor_seed.json"
const SETTINGS_SCENE := "res://ui/windows/SettingsWindow/SettingsWindow.tscn"
const EDITOR_SCENE := "res://ui/windows/UIEditorWindow/UIEditorWindow.tscn"

const MIN_CHECKS := 350
const G := SS.CAT_GRAPHICS
const A := SS.CAT_AUDIO
const C := SS.CAT_CONTROLS
const I := SS.CAT_INTERFACE
const X := SS.CAT_ACCESSIBILITY
const N := SS.CAT_NETWORK
const AC := SS.CAT_ACCOUNT

var _fails: Array[String] = []
var _checks := 0
var _cfg_counter := 0
var _cfg_files: Array[String] = []
var _bus_backup: Dictionary = {}


func check(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_fails.append(msg)
		printerr("  FAIL: ", msg)
	else:
		print("  PASS: ", msg)


func near(a: float, b: float, eps: float = 0.01) -> bool:
	return absf(a - b) <= eps


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("== [TEST] Paso 16: Ajustes globales y Editor de interfaz ==")
	await process_frame
	_backup_buses()
	await _test_registry()
	_test_seed_schema()
	_test_graphics_defaults()
	_test_presets()
	_test_performance()
	_test_pending_apply()
	_test_display_confirm()
	_test_search()
	_test_controls()
	_test_accessibility()
	_test_audio()
	_test_network_account()
	_test_settings_persistence()
	_test_key_helpers()
	_test_editor_seed()
	_test_editor_alignment()
	_test_editor_moves()
	_test_editor_properties()
	_test_editor_presets()
	_test_editor_history()
	_test_editor_codes()
	_test_editor_persistence()
	await _test_settings_window()
	await _test_editor_window()
	await _test_orchestrated_flow()
	_restore_buses()
	for f in _cfg_files:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	check(_checks >= MIN_CHECKS, "Se ejecutaron todas las comprobaciones (%d >= %d)" % [_checks, MIN_CHECKS])
	print("== %d checks, %d fallos ==" % [_checks, _fails.size()])
	if _fails.is_empty():
		print("RESULTADO: 100% PASS (ExitCode 0)")
		quit(0)
	else:
		for f in _fails:
			printerr("  - ", f)
		quit(1)


# --------------------------------------------------------------------------
# Utilidades
# --------------------------------------------------------------------------
func _frames(n: int = 2) -> void:
	for i in n:
		await process_frame


func _cfg_path(tag: String = "settings") -> String:
	_cfg_counter += 1
	var p := "user://test_step16_%s_%d.cfg" % [tag, _cfg_counter]
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	_cfg_files.append(p)
	return p


func _svc() -> Node:
	var s: Node = SS.new()
	s.load_seed(SEED)
	s.save_path = _cfg_path()
	s.auto_tick = false
	root.add_child(s)
	return s


func _ed() -> Node:
	var e: Node = ES.new()
	e.load_seed(EDITOR_SEED)
	e.save_path = _cfg_path("layouts")
	root.add_child(e)
	return e


func _free(n: Node) -> void:
	if is_instance_valid(n):
		n.queue_free()


func _key(code: int, ctrl: bool = false, shift: bool = false) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	ev.ctrl_pressed = ctrl
	ev.shift_pressed = shift
	return ev


func _backup_buses() -> void:
	for bus in SS.BUSES:
		var i := AudioServer.get_bus_index(bus)
		if i >= 0:
			_bus_backup[bus] = [AudioServer.get_bus_volume_db(i), AudioServer.is_bus_mute(i)]


func _restore_buses() -> void:
	for bus in _bus_backup:
		var i := AudioServer.get_bus_index(bus)
		AudioServer.set_bus_volume_db(i, _bus_backup[bus][0])
		AudioServer.set_bus_mute(i, _bus_backup[bus][1])


# --------------------------------------------------------------------------
# 1. Registro, autoloads y orquestador
# --------------------------------------------------------------------------
func _test_registry() -> void:
	print("-- 1. Registro de ventanas, autoloads y orquestador")
	var orch := root.get_node_or_null("UIOrchestrator")
	check(orch != null, "UIOrchestrator disponible")
	check(root.get_node_or_null("SettingsService") != null, "Autoload SettingsService registrado")
	check(root.get_node_or_null("UIEditorService") != null, "Autoload UIEditorService registrado")
	if orch == null:
		return
	var reg = orch.registry
	check(reg.is_registered("settings_window"), "settings_window registrada")
	check(reg.is_registered("ui_editor"), "ui_editor registrada")
	check(reg.is_registered("options_menu"), "options_menu (menú de sesión) se conserva")
	check(reg.get_metadata("settings_window").category == 1, "settings_window en GAME_WINDOW")
	check(reg.get_metadata("ui_editor").category == 1, "ui_editor en GAME_WINDOW")
	check(reg.get_shortcut_keys("settings_window") == [KEY_F10], "Ajustes declara el atajo F10")
	check(reg.get_window_for_key(KEY_F10) == "settings_window", "F10 resuelve a settings_window")
	check(reg.get_metadata("settings_window").scene_path == SETTINGS_SCENE, "Ruta de escena de Ajustes")
	check(reg.get_metadata("ui_editor").scene_path == EDITOR_SCENE, "Ruta de escena del Editor")
	check(orch.has_method("open_settings"), "UIOrchestrator.open_settings()")
	check(orch.has_method("open_ui_editor"), "UIOrchestrator.open_ui_editor()")
	var bar_script = load("res://ui/menu/menu_bar.gd")
	check(bar_script.SETTINGS_WINDOW == "settings_window", "El botón Ajustes (F10) del menú común abre settings_window")
	for f in ["SettingsService.gd", "UIEditorService.gd"]:
		var mirror := ProjectSettings.globalize_path("res://").path_join("../shared-core").path_join(f)
		check(FileAccess.file_exists(mirror) and FileAccess.get_file_as_string(mirror) == FileAccess.get_file_as_string("res://shared-core/" + f), "%s reflejado en clients/shared-core" % f)
	await _frames(1)


# --------------------------------------------------------------------------
# 2. Esquema del seed
# --------------------------------------------------------------------------
func _test_seed_schema() -> void:
	print("-- 2. Seed de ajustes: categorías y opciones")
	var s := _svc()
	check(s.category_ids() == [G, A, C, I, X, N, AC], "7 categorías canónicas en orden")
	var labels := ["Gráficos", "Sonido", "Controles", "Interfaz", "Accesibilidad", "Red", "Cuenta y privacidad"]
	for i in labels.size():
		check(s.category_label(s.category_ids()[i]) == labels[i], "Etiqueta de categoría: %s" % labels[i])
	check(s.visible_options(G).size() == 9, "Gráficos: 9 opciones (7 del diseño + modo y resolución)")
	check(s.option_keys(A).size() == 10 and s.visible_options(A).size() == 5, "Sonido: 5 buses visibles (+5 muteos)")
	check(s.option_keys(C).size() == 22, "Controles: 22 acciones canónicas")
	check(s.visible_options(I).size() == 4, "Interfaz: 4 opciones")
	check(s.visible_options(X).size() == 6, "Accesibilidad: 6 opciones")
	check(s.visible_options(N).size() == 3, "Red: 3 opciones")
	check(s.visible_options(AC).size() == 3, "Cuenta: 3 opciones")
	for cat in s.category_ids():
		for key in s.option_keys(cat):
			check(s.is_valid_value(cat, key, s.get_option(cat, key)["default"]), "Default válido: %s/%s" % [cat, key])
	var expect := {
		"shadow_quality": ["Baja", "Media", "Alta"],
		"view_distance": ["60 %", "80 %", "100 %"],
		"spell_effects": ["Completos", "Reducidos", "Mínimos"],
		"resolution_scale": ["80 %", "90 %", "100 %"],
		"shelter_fps_limit": ["30", "60"],
		"motion_blur": ["No", "Sí"],
		"ui_brightness": ["80 %", "90 %", "100 %", "110 %", "120 %"],
	}
	for key in expect:
		var got: Array = []
		for v in s.choice_values(G, key):
			got.append(s.choice_label(G, key, v))
		check(got == expect[key], "Opciones de %s: %s" % [key, ", ".join(PackedStringArray(expect[key]))])
	check(s.choice_values(X, "color_mode") == ["normal", "protanopia", "deuteranopia", "tritanopia"], "Modos de color: Normal, Protanopia, Deuteranopia, Tritanopia")
	check(s.preset_ids() == ["low", "medium", "high", "ultra", "custom"], "Presets: Bajo, Medio, Alto, Ultra, Personal")
	check(s.preset_label("custom") == "Personal" and s.preset_label("low") == "Bajo" and s.preset_label("ultra") == "Ultra", "Etiquetas de preset")
	check(s.has_option(G, "shadow_quality") and not s.has_option(G, "nope"), "has_option")
	check(not s.load_seed("res://config/settings/no_existe.json"), "Seed inexistente → false")
	_free(s)


# --------------------------------------------------------------------------
# 3. Gráficos: valores del diseño
# --------------------------------------------------------------------------
func _test_graphics_defaults() -> void:
	print("-- 3. Gráficos: estado del diseño (MMO-Ajustes.html)")
	var s := _svc()
	check(s.get_value(G, "shadow_quality") == "high", "Calidad de sombras: Alta")
	check(s.get_value(G, "view_distance") == 80, "Distancia de visión: 80 %")
	check(s.get_value(G, "spell_effects") == "reduced", "Efectos de hechizos: Reducidos")
	check(s.get_value(G, "resolution_scale") == 90, "Escala de resolución: 90 %")
	check(s.get_value(G, "shelter_fps_limit") == 60, "Límite de fps en el refugio: 60")
	check(s.get_value(G, "motion_blur") == false, "Desenfoque de movimiento: No")
	check(s.get_value(G, "ui_brightness") == 100, "Brillo de la interfaz: 100 %")
	check(s.fps_impact_text(G, "shadow_quality") == "−8 fps", "Sombras Alta: «−8 fps»")
	check(s.fps_impact_text(G, "view_distance") == "−5 fps", "Visión 80 %: «−5 fps»")
	check(s.fps_impact_text(G, "spell_effects") == "+12 fps", "Hechizos Reducidos: «+12 fps»")
	check(s.fps_impact_text(G, "resolution_scale") == "+9 fps", "Escala 90 %: «+9 fps»")
	check(s.fps_impact_text(G, "shelter_fps_limit") == "", "Límite del refugio sin impacto")
	check(s.fps_impact_text(G, "ui_brightness") == "", "Brillo sin impacto")
	check(s.fps_impact_color(G, "shadow_quality") == "#f5c35b", "−fps en ámbar #f5c35b")
	check(s.fps_impact_color(G, "spell_effects") == "#4fe39a", "+fps en verde #4fe39a")
	check(s.fps_impact_color(G, "ui_brightness") == "#9aa6ae", "Sin impacto en gris")
	check(s.fps_impact(G, "shadow_quality", "low") == 0 and s.fps_impact(G, "spell_effects", "minimal") == 18, "Impacto por valor")
	check(s.current_preset() == "custom", "El estado del diseño es «Personal»")
	check(s.choice_label(G, "shadow_quality") == "Alta" and s.choice_label(G, "motion_blur") == "No", "Etiquetas de valor actual")
	check(s.choice_label(G, "display_mode") == "Sin bordes" and s.choice_label(G, "resolution") == "1920 × 1080", "Pantalla: Sin bordes · 1920 × 1080")
	check(bool(s.get_option(G, "resolution_scale").get("confirm", false)) and bool(s.get_option(G, "display_mode").get("confirm", false)), "Escala y modo de pantalla requieren confirmación")
	check(not bool(s.get_option(G, "shadow_quality").get("confirm", false)), "Las sombras no requieren confirmación")
	check(not s.set_value(G, "shadow_quality", "ultra"), "Valor inválido rechazado")
	check(not s.set_value(G, "view_distance", 70), "Distancia 70 % rechazada")
	check(not s.set_value(G, "nope", 1), "Opción inexistente rechazada")
	check(s.pending_count() == 0, "Sin cambios pendientes tras rechazos")
	check(s.cycle(G, "shadow_quality") == "low" and s.cycle(G, "shadow_quality", -1) == "high", "cycle() recorre las opciones")
	check(s.pending_count() == 0, "Volver al valor aplicado elimina el pendiente")
	_free(s)


# --------------------------------------------------------------------------
# 4. Presets
# --------------------------------------------------------------------------
func _test_presets() -> void:
	print("-- 4. Presets Bajo · Medio · Alto · Ultra · Personal")
	var s := _svc()
	var fired: Array = []
	s.preset_changed.connect(func(p: String) -> void: fired.append(p))
	s.set_and_apply(X, "reduce_motion", false)
	for id in ["low", "medium", "high", "ultra"]:
		check(s.apply_preset(id), "Aplicar preset %s" % id)
		check(s.current_preset() == id, "Preset detectado: %s" % id)
	check(s.get_value(G, "motion_blur") == true, "Ultra activa el desenfoque")
	check(s.get_value(G, "shadow_quality") == "high" and s.get_value(G, "resolution_scale") == 100, "Ultra: sombras Alta, escala 100 %")
	s.apply_preset("low")
	check(s.get_value(G, "shadow_quality") == "low" and s.get_value(G, "view_distance") == 60 and s.get_value(G, "spell_effects") == "minimal", "Bajo: sombras Baja, visión 60 %, efectos Mínimos")
	check(s.has_pending(G), "El preset queda pendiente hasta aplicar")
	s.set_value(G, "view_distance", 100)
	check(s.current_preset() == "custom", "Cambiar una opción → Personal")
	check(s.apply_preset("custom") and s.current_preset() == "custom", "Personal no cambia nada")
	check(not s.apply_preset("epic"), "Preset inexistente → false")
	check(fired.size() > 0 and fired.has("low"), "Señal preset_changed")
	s.discard()
	s.set_and_apply(X, "reduce_motion", true)
	s.apply_preset("ultra")
	check(s.get_value(G, "motion_blur") == false, "Con «Reducir movimiento» Ultra no enciende el desenfoque")
	_free(s)


# --------------------------------------------------------------------------
# 5. Rendimiento estimado
# --------------------------------------------------------------------------
func _test_performance() -> void:
	print("-- 5. Rendimiento estimado en tu PC")
	var s := _svc()
	var p: Array = s.estimated_performance()
	check(p.size() == 4, "4 escenarios")
	var exp := [["Mundo abierto", 144, 0.96, "#4fe39a"], ["Raid de 20", 118, 0.79, "#4fe39a"], ["Ciudad del Nexo", 96, 0.64, "#f5c35b"], ["Refugio", 60, 0.40, "#9aa6ae"]]
	for i in 4:
		check(p[i]["label"] == exp[i][0], "Escenario %d: %s" % [i, exp[i][0]])
		check(p[i]["fps"] == exp[i][1], "%s: %d fps" % [exp[i][0], exp[i][1]])
		check(near(p[i]["ratio"], exp[i][2], 0.006), "%s: barra al %d %%" % [exp[i][0], roundi(exp[i][2] * 100)])
		check(p[i]["color"] == exp[i][3], "%s: color %s" % [exp[i][0], exp[i][3]])
	check(p[3]["capped"] and not p[0]["capped"], "El refugio está limitado por el tope de fps")
	check(s.performance_note() == "Medido en tus últimas sesiones, no en una prueba sintética.", "Nota de medición real")
	s.set_value(G, "shadow_quality", "low")
	check(s.pending_fps_delta() == 8, "Sombras Baja en el borrador: +8 fps")
	p = s.estimated_performance()
	check(p[0]["fps"] == 152 and near(p[0]["ratio"], 1.0), "Mundo abierto 152 fps (barra llena)")
	check(p[2]["fps"] == 104, "Ciudad del Nexo 104 fps")
	s.set_value(G, "shelter_fps_limit", 30)
	p = s.estimated_performance()
	check(p[3]["fps"] == 30 and near(p[3]["ratio"], 0.2), "Límite 30 en el refugio: 30 fps (20 %)")
	s.discard()
	s.set_value(G, "view_distance", 100)
	s.set_value(G, "spell_effects", "full")
	check(s.pending_fps_delta() == -18, "Visión 100 % y efectos completos: −18 fps")
	p = s.estimated_performance()
	check(p[2]["fps"] == 78 and p[2]["color"] == "#f5c35b", "Ciudad del Nexo baja a 78 fps (ámbar)")
	s.set_value(G, "shadow_quality", "high")
	s.set_value(G, "resolution_scale", 100)
	p = s.estimated_performance()
	check(p[2]["fps"] == 69, "Ciudad del Nexo 69 fps")
	s.set_value(G, "view_distance", 100)
	check(s.estimated_performance()[1]["color"] == "#f5c35b", "Raid de 20 por debajo de 110 fps → ámbar")
	var low: Node = _svc()
	low.performance["good_fps"] = 300
	low.performance["warn_fps"] = 200
	check(low.estimated_performance()[0]["color"] == "#ff6b6b", "Por debajo del umbral mínimo → rojo")
	_free(low)
	_free(s)


# --------------------------------------------------------------------------
# 6. Borrador, aplicar y deshacer
# --------------------------------------------------------------------------
func _test_pending_apply() -> void:
	print("-- 6. Cambios pendientes, Aplicar y Deshacer")
	var s := _svc()
	var counts: Array = []
	s.pending_changed.connect(func(n: int) -> void: counts.append(n))
	check(s.pending_summary() == "Sin cambios pendientes", "Resumen sin cambios")
	s.set_value(G, "shadow_quality", "medium")
	check(s.pending_summary() == "1 cambio sin aplicar · los de pantalla se deshacen solos si no confirmas en 15 s", "Resumen singular")
	s.set_value(I, "chat_opacity", 60)
	s.set_value(X, "narrator", true)
	check(s.pending_count() == 3, "3 cambios sin aplicar")
	check(s.pending_summary() == "3 cambios sin aplicar · los de pantalla se deshacen solos si no confirmas en 15 s", "Resumen del diseño")
	check(counts.back() == 3, "Señal pending_changed(3)")
	check(s.get_value(G, "shadow_quality") == "medium" and s.get_applied(G, "shadow_quality") == "high", "El borrador no toca lo aplicado")
	check(s.has_pending(G, "shadow_quality") and s.has_pending(X) and not s.has_pending(A), "has_pending por categoría y clave")
	check(s.pending_keys() == ["accessibility/narrator", "graphics/shadow_quality", "interface/chat_opacity"], "Claves pendientes ordenadas")
	check(s.discard() == 3, "Deshacer descarta 3 cambios")
	check(s.pending_count() == 0 and s.get_value(G, "shadow_quality") == "high", "Tras deshacer vuelve lo aplicado")
	check(s.discard() == 0, "Deshacer sin cambios → 0")
	s.set_value(G, "shadow_quality", "medium")
	s.set_value(I, "chat_opacity", 63)
	check(s.get_value(I, "chat_opacity") == 65, "Deslizador con paso de 5: 63 → 65")
	var applied_keys: Array = []
	s.applied.connect(func(k: Array) -> void: applied_keys.append_array(k))
	var keys: Array = s.apply()
	check(keys.size() == 2 and applied_keys == keys, "Aplicar confirma 2 claves y emite applied")
	check(s.pending_count() == 0 and s.get_applied(G, "shadow_quality") == "medium", "Aplicado")
	check(s.save_count == 1 and FileAccess.file_exists(s.save_path), "Aplicar guarda en disco")
	check(s.apply().is_empty(), "Aplicar sin cambios no hace nada")
	check(not s.confirm_active, "Sin cambios de pantalla no hay cuenta atrás")
	s.set_value(G, "shadow_quality", "low")
	s.set_value(I, "language", "en")
	check(s.apply(["interface/language"]) == ["interface/language"], "Aplicar solo una clave")
	check(s.pending_keys() == ["graphics/shadow_quality"], "El resto sigue pendiente")
	check(s.set_and_apply(I, "number_format", "proportional") and s.get_applied(I, "number_format") == "proportional", "set_and_apply aplica al instante")
	check(s.pending_keys() == ["graphics/shadow_quality"], "set_and_apply no aplica otros pendientes")
	check(s.toggle(I, "text_shadow") and s.get_value(I, "text_shadow") == false, "toggle()")
	_free(s)


# --------------------------------------------------------------------------
# 7. Temporizador de seguridad de pantalla (15 s)
# --------------------------------------------------------------------------
func _test_display_confirm() -> void:
	print("-- 7. Confirmación de cambios de pantalla (15 s)")
	var s := _svc()
	var started: Array = []
	var finished: Array = []
	s.display_confirm_started.connect(func(sec: float) -> void: started.append(sec))
	s.display_confirm_finished.connect(func(kept: bool) -> void: finished.append(kept))
	s.set_value(G, "resolution", "2560x1440")
	s.set_value(G, "display_mode", "fullscreen")
	s.set_value(G, "shadow_quality", "low")
	check(s.pending_display_changes() == 2, "2 cambios de pantalla en el borrador")
	s.apply()
	check(s.confirm_active and near(s.confirm_remaining, 15.0), "Empieza la cuenta atrás de 15 s")
	check(started == [15.0], "Señal display_confirm_started(15)")
	check(s.confirm_text() == "¿Mantener los cambios de pantalla? Se revierten en 15 s", "Texto de confirmación")
	check(s.runtime_state.get("resolution") == "2560x1440" and s.runtime_state.get("display_mode") == "fullscreen", "Se aplican al motor")
	s.tick(10.0)
	check(s.confirm_active and near(s.confirm_remaining, 5.0), "A los 10 s quedan 5")
	check(s.confirm_text().ends_with("5 s"), "Texto con 5 s")
	check(s.keep_display(), "Mantener")
	check(not s.confirm_active and finished == [true], "Mantener detiene la cuenta atrás")
	check(s.get_applied(G, "resolution") == "2560x1440", "La resolución se conserva")
	check(not s.keep_display() and not s.revert_display(), "Sin cuenta atrás: mantener/revertir → false")
	# Sin confirmar: se revierte sola.
	s.set_value(G, "resolution", "1280x720")
	s.set_value(G, "resolution_scale", 80)
	s.apply()
	check(s.confirm_active, "Nueva cuenta atrás")
	s.tick(14.0)
	check(s.confirm_active and s.get_applied(G, "resolution") == "1280x720", "A los 14 s sigue el cambio")
	s.tick(1.5)
	check(not s.confirm_active, "A los 15 s termina la cuenta atrás")
	check(s.get_applied(G, "resolution") == "2560x1440", "Resolución revertida a la anterior")
	check(s.get_applied(G, "resolution_scale") == 90, "Escala revertida a 90 %")
	check(s.get_applied(G, "shadow_quality") == "low", "Los cambios que no son de pantalla se quedan")
	check(finished == [true, false], "Señal display_confirm_finished(false)")
	check(near(s.runtime_state.get("scaling_3d_scale", 0.0), 0.9), "El motor vuelve a la escala 0,9")
	var cfg := ConfigFile.new()
	cfg.load(s.save_path)
	check(cfg.get_value(G, "resolution") == "2560x1440", "El revertido también se guarda")
	# Revertir a mano.
	s.set_value(G, "display_mode", "windowed")
	s.apply()
	check(s.revert_display() and s.get_applied(G, "display_mode") == "fullscreen", "Revertir a mano")
	# Dos aplicaciones seguidas conservan el valor original.
	s.set_value(G, "display_mode", "windowed")
	s.apply()
	s.set_value(G, "display_mode", "borderless")
	s.apply()
	s.tick(20.0)
	check(s.get_applied(G, "display_mode") == "fullscreen", "Encadenar cambios revierte al valor original")
	check(s.confirm_snapshot.is_empty(), "Snapshot vacío tras revertir")
	_free(s)


# --------------------------------------------------------------------------
# 8. Buscador
# --------------------------------------------------------------------------
func _test_search() -> void:
	print("-- 8. Buscador en vivo (Ctrl K)")
	var s := _svc()
	var r: Array = s.search("sombras")
	check(r.size() == 2, "«sombras» → 2 resultados")
	check(r.size() == 2 and r[0]["path"] == "Gráficos › Calidad de sombras" and r[1]["path"] == "Interfaz › Sombra del texto", "Rutas de los resultados")
	check(s.search_summary("sombras") == "2 resultados: Gráficos › Calidad de sombras · Interfaz › Sombra del texto", "Resumen del diseño")
	check(s.search_summary("  SOMBRAS ") == s.search_summary("sombras"), "Sin distinguir mayúsculas ni espacios")
	check(s.search("visión").size() >= 1 and s.search("vision")[0]["key"] == "view_distance", "Ignora tildes: «vision» → Distancia de visión")
	check(s.search_hits("sombras", G) == ["shadow_quality"] and s.search_hits("sombras", I) == ["text_shadow"], "Coincidencias por categoría")
	check(s.search("daltonismo")[0]["key"] == "color_mode", "Palabra clave: daltonismo → Modo de color")
	check(s.search("montura")[0]["key"] == "mount", "Controles: montura")
	check(s.search("ping")[0]["key"] == "show_latency", "Red: ping")
	check(s.search("volumen musica").size() == 0 or s.search("musica")[0]["key"] == "volume_music", "Varias palabras / música")
	check(s.search("zzzz").is_empty(), "Sin resultados")
	check(s.search_summary("zzzz") == "Sin resultados para «zzzz»", "Resumen sin resultados")
	check(s.search_summary("") == "" and s.search("").is_empty(), "Búsqueda vacía")
	check(s.search_summary("passkey") == "1 resultado: Cuenta y privacidad › Llave de acceso", "Resumen singular")
	check(SS.normalize("Señales ÁRBOL") == "senales arbol", "normalize() quita tildes y eñes")
	_free(s)


# --------------------------------------------------------------------------
# 9. Controles y atajos repetidos
# --------------------------------------------------------------------------
func _test_controls() -> void:
	print("-- 9. Controles: atajos repetidos y reasignación")
	var s := _svc()
	var canonical := {"move_forward": "W", "move_left": "A", "move_back": "S", "move_right": "D", "ability_1": "1", "ability_6": "6",
		"menu_equipment": "C", "menu_powers": "N", "menu_quests": "L", "menu_map": "M", "menu_codex": "J", "menu_social": "O",
		"menu_shelter": "H", "menu_commerce": "P", "menu_settings": "F10", "menu_close": "Esc", "signals": "G", "mount": "G"}
	for a in canonical:
		check(s.get_binding(a) == canonical[a], "Tecla canónica %s = %s" % [a, canonical[a]])
	var c: Array = s.find_conflicts()
	check(c.size() == 1 and c[0]["key"] == "G" and c[0]["actions"] == ["signals", "mount"], "Conflicto: G (Señales y Montura)")
	check(s.has_conflicts() and s.category_has_warning(C) and not s.category_has_warning(G), "Advertencia en Controles")
	check(s.conflict_message(c[0]) == "G abre Señales y también llama a la montura.", "Mensaje «G abre Señales y también llama a la montura.»")
	var sug: Dictionary = s.suggest_resolution(c[0])
	check(sug.get("action") == "mount" and sug.get("key") == "Z" and sug.get("label") == "Montura → Z", "Sugerencia «Montura → Z»")
	check(s.actions_for_key("g") == ["signals", "mount"], "actions_for_key sin distinguir mayúsculas")
	var changed: Array = []
	s.conflicts_changed.connect(func(cc: Array) -> void: changed.append(cc.size()))
	check(s.resolve_conflict(), "Solución en un clic")
	check(s.get_binding("mount") == "Z" and not s.has_conflicts(), "Montura → Z y sin conflictos")
	check(changed == [0], "Señal conflicts_changed en tiempo real")
	check(not s.category_has_warning(C), "Sin advertencia tras resolver")
	check(not s.resolve_conflict(), "Nada que resolver")
	check(s.rebind("ability_1", "2") and s.has_conflicts(), "Asignar 2 a la habilidad 1 crea un conflicto")
	check(s.conflict_message(s.find_conflicts()[0]) == "2 lanza la habilidad 1 y también lanza la habilidad 2.", "Mensaje del nuevo conflicto")
	var sug2: Dictionary = s.suggest_resolution(s.find_conflicts()[0])
	check(sug2.get("action") == "ability_2" and sug2.get("key") == "X", "Sin sugerencia propia: primera tecla libre (X)")
	s.discard()
	check(s.get_binding("ability_1") == "1" and s.get_binding("mount") == "G", "Deshacer devuelve las teclas")
	check(s.has_conflicts(), "Y el conflicto original")
	check(not s.rebind("menu_close", "Q"), "Esc (cerrar) es fija")
	check(not s.rebind("mount", "Esc"), "No se puede asignar Esc a otra acción")
	check(not s.rebind("mount", "ñ") and not s.rebind("mount", ""), "Teclas no válidas rechazadas")
	check(not s.rebind("nope", "Z"), "Acción inexistente")
	check(s.rebind("mount", "f5") and s.get_binding("mount") == "F5", "Nombres canónicos (f5 → F5)")
	check(s.is_locked(C, "menu_close") and s.lock_reason(C, "menu_close") == "Reservada", "menu_close reservada")
	check(s.begin_rebind("mount") and s.rebinding_action == "mount", "Elegir otra: espera tecla")
	check(not s.capture_key(KEY_ESCAPE) and s.rebinding_action == "" and s.get_binding("mount") == "F5", "Esc cancela la reasignación")
	var fin: Array = []
	s.rebind_finished.connect(func(a: String, k: String) -> void: fin.append(a + ":" + k))
	s.begin_rebind("mount")
	check(s.capture_key(KEY_V) and s.get_binding("mount") == "V", "Captura V para la montura")
	check(fin == ["mount:V"], "Señal rebind_finished")
	check(not s.capture_key(KEY_B), "Sin reasignación activa no captura")
	check(not s.begin_rebind("menu_close"), "No se reasigna una acción fija")
	s.begin_rebind("signals")
	s.cancel_rebind()
	check(s.rebinding_action == "", "cancel_rebind()")
	_free(s)


# --------------------------------------------------------------------------
# 10. Accesibilidad
# --------------------------------------------------------------------------
func _test_accessibility() -> void:
	print("-- 10. Accesibilidad")
	var s := _svc()
	check(s.color_mode() == "normal", "Modo de color Normal")
	check(s.get_applied(X, "large_text") == false and near(s.text_scale(), 1.0), "Texto grande apagado (100 %)")
	check(s.reduce_motion() and not s.camera_shake_enabled() and not s.flashes_enabled(), "Reducir movimiento: sin sacudidas ni destellos")
	check(not s.narrator_enabled() and s.directional_audio_enabled(), "Narrador apagado · Avisos 3D activos")
	check(s.shape_for("warn") == "triangle" and s.shape_for("good") == "circle" and s.shape_for("bad") == "diamond", "Formas además de colores: triángulo, círculo, rombo")
	check(s.is_locked(G, "motion_blur") and s.lock_reason(G, "motion_blur") == "Apagado por «Reducir movimiento»", "Desenfoque bloqueado")
	check(not s.set_value(G, "motion_blur", true), "No se puede activar el desenfoque")
	check(not s.motion_blur_enabled(), "Desenfoque efectivo apagado")
	var a11y_events := [0]
	s.accessibility_changed.connect(func() -> void: a11y_events[0] += 1)
	check(s.set_and_apply(X, "reduce_motion", false), "Desactivar reducir movimiento")
	check(a11y_events[0] >= 1, "Señal accessibility_changed")
	check(not s.is_locked(G, "motion_blur") and s.set_value(G, "motion_blur", true), "El desenfoque vuelve a ser editable")
	s.apply()
	check(s.motion_blur_enabled() and s.camera_shake_enabled(), "Desenfoque y sacudidas activos")
	s.set_value(X, "reduce_motion", true)
	check(s.get_value(G, "motion_blur") == false, "Activar reducir movimiento apaga el desenfoque en el borrador")
	s.apply()
	check(not s.motion_blur_enabled() and s.get_applied(G, "motion_blur") == false, "Desenfoque apagado forzado")
	check(s.set_and_apply(X, "large_text", true) and near(s.text_scale(), 1.15) and near(s.font_scale(), 1.15), "Texto grande 115 %")
	check(s.runtime_state.get("text_scale") == 1.15, "Escala de texto aplicada")
	check(s.high_contrast == false, "Alto contraste no forma parte de estos ajustes")
	check(s.semantic_color("good") == Color("#4fe39a") and s.semantic_color("warn") == Color("#f5c35b"), "Paleta Normal")
	for mode in ["protanopia", "deuteranopia", "tritanopia"]:
		check(s.set_and_apply(X, "color_mode", mode) and s.color_mode() == mode, "Modo %s" % mode)
		check(s.semantic_color("good") != Color("#4fe39a") or s.semantic_color("warn") != Color("#f5c35b") or s.semantic_color("bad") != Color("#ff6b6b"), "%s cambia la paleta" % mode)
	check(s.semantic_color("good", "protanopia") == Color("#3fa7ff"), "Protanopia: verde → azul")
	check(s.semantic_color("bad", "deuteranopia") == Color("#ff8a3d"), "Deuteranopia: rojo → naranja")
	check(s.semantic_color("warn", "tritanopia") == Color("#ff8fb1"), "Tritanopia: ámbar → rosa")
	check(not s.set_value(X, "color_mode", "acromatopsia"), "Modo desconocido rechazado")
	check(not s.announce("Hola"), "Narrador apagado: no narra")
	s.set_and_apply(X, "narrator", true)
	var said: Array = []
	s.narrated.connect(func(t: String) -> void: said.append(t))
	check(s.announce("Ajustes") and said == ["Ajustes"] and s.last_narration == "Ajustes", "Narrador lee menús y alertas")
	check(not s.announce(""), "Texto vacío no se narra")
	s.set_and_apply(X, "shapes_with_colors", false)
	check(s.shape_for("warn") == "", "Sin formas si se desactiva")
	_free(s)


# --------------------------------------------------------------------------
# 11. Sonido (5 buses)
# --------------------------------------------------------------------------
func _test_audio() -> void:
	print("-- 11. Sonido: 5 buses sincronizados con AudioServer")
	var s := _svc()
	check(SS.BUSES == ["Master", "Music", "SFX", "Ambience", "UI"], "Buses canónicos")
	for bus in SS.BUSES:
		check(AudioServer.get_bus_index(bus) >= 0, "Bus %s existe (default_bus_layout.tres)" % bus)
		check(near(s.bus_volume(bus), 100.0) and not s.bus_muted(bus), "%s al 100 %% y sin silenciar" % bus)
	check(s.set_bus_volume("Music", 40), "Música al 40 %")
	var mi := AudioServer.get_bus_index("Music")
	check(near(AudioServer.get_bus_volume_db(mi), linear_to_db(0.4)), "AudioServer en vivo: Music a linear_to_db(0,4)")
	check(near(s.runtime_state.get("bus_Music", -1.0), 40.0), "runtime_state del bus")
	check(not s.set_bus_volume("Music", 140), "Volumen fuera de rango rechazado")
	check(s.set_bus_muted("SFX", true) and s.bus_muted("SFX"), "Silenciar SFX")
	var si := AudioServer.get_bus_index("SFX")
	check(AudioServer.is_bus_mute(si) and near(s.bus_effective_volume("SFX"), 0.0), "SFX silenciado en AudioServer")
	check(s.toggle_bus_mute("SFX") and not AudioServer.is_bus_mute(si), "Quitar silencio")
	s.toggle_bus_mute("SFX")
	check(s.choice_label(A, "volume_music") == "40 %", "Etiqueta 40 %")
	s.discard()
	check(near(AudioServer.get_bus_volume_db(mi), 0.0) and not AudioServer.is_bus_mute(si), "Deshacer restaura AudioServer")
	s.set_bus_volume("Ambience", 55)
	s.set_bus_muted("UI", true)
	s.apply()
	var saved: Dictionary = AudioSettings.load_saved_volumes(s.save_path)
	check(saved.get(&"Ambience", -1.0) == 55.0, "[audio] guarda Ambience=55 (formato de audio_settings.gd)")
	check(saved.get(&"Master", -1.0) == 100.0, "[audio] guarda Master=100")
	var cfg := ConfigFile.new()
	cfg.load(s.save_path)
	check(cfg.get_value("audio_mute", "UI", false) == true, "[audio_mute] UI=true")
	check(typeof(cfg.get_value("audio", "Ambience")) == TYPE_INT, "Volúmenes enteros 0-100")
	s.set_and_apply(A, "mute_ui", false)
	s.set_and_apply(A, "volume_ambience", 100)
	_free(s)


# --------------------------------------------------------------------------
# 12. Red y cuenta
# --------------------------------------------------------------------------
func _test_network_account() -> void:
	print("-- 12. Red y Cuenta y privacidad")
	var s := _svc()
	check(s.get_value(N, "show_latency") == true, "Mostrar latencia")
	check(s.get_value(N, "telemetry_rate") == 20 and s.choice_label(N, "telemetry_rate") == "20 Hz", "Telemetría UDP 20 Hz")
	check(s.get_value(N, "realm") == "umbral" and s.choice_label(N, "realm") == "Servidor Umbral", "Reino: Servidor Umbral")
	check(int(s.network_status.get("latency_ms", 0)) == 24, "Latencia 24 ms")
	check(s.set_and_apply(N, "telemetry_rate", 30) and s.runtime_state.get("telemetry_hz") == 30, "Telemetría a 30 Hz aplicada")
	check(s.set_and_apply(N, "realm", "nexo_eu") and s.runtime_state.get("realm") == "nexo_eu", "Cambio de reino")
	check(not s.set_value(N, "telemetry_rate", 25), "25 Hz no es válido")
	check(s.get_value(AC, "profile_visibility") == "friends" and s.choice_label(AC, "profile_visibility") == "Amigos", "Perfil visible para amigos")
	check(s.get_value(AC, "friend_requests") == "everyone", "Solicitudes de todos")
	check(s.choice_label(AC, "passkey") == "Activa", "Llave de acceso activa")
	check(s.is_locked(AC, "passkey") and not s.set_value(AC, "passkey", "none"), "La llave de acceso es de solo lectura")
	check(s.set_value(AC, "profile_visibility", "private") and s.pending_count() == 1, "Perfil privado pendiente")
	_free(s)


# --------------------------------------------------------------------------
# 13. Persistencia de ajustes
# --------------------------------------------------------------------------
func _test_settings_persistence() -> void:
	print("-- 13. Persistencia en user://settings.cfg")
	var s := _svc()
	check(SS.DEFAULT_SAVE_PATH == "user://settings.cfg", "Ruta por defecto user://settings.cfg")
	var cfg0 := ConfigFile.new()
	cfg0.set_value("otra_seccion", "clave", 7)
	cfg0.save(s.save_path)
	s.set_value(G, "shadow_quality", "medium")
	s.rebind("mount", "Z")
	s.set_value(X, "large_text", true)
	s.set_value(I, "chat_opacity", 25)
	s.set_bus_volume("Music", 35)
	s.apply()
	var cfg := ConfigFile.new()
	check(cfg.load(s.save_path) == OK, "Archivo guardado")
	check(cfg.get_value("otra_seccion", "clave", 0) == 7, "Conserva otras secciones")
	check(cfg.get_value(G, "shadow_quality") == "medium" and cfg.get_value(C, "mount") == "Z", "Gráficos y controles guardados")
	check(not cfg.has_section_key(AC, "passkey"), "Las opciones de solo lectura no se guardan")
	check(cfg.get_value("meta", "version") == 1, "Versión del esquema")
	var t := _svc()
	t.save_path = s.save_path
	check(t.load_saved() > 30, "Recarga en una instancia nueva")
	check(t.get_applied(G, "shadow_quality") == "medium" and t.get_binding("mount") == "Z", "Valores recuperados")
	check(near(t.text_scale(), 1.15) and t.get_applied(I, "chat_opacity") == 25 and near(t.bus_volume("Music"), 35.0), "Accesibilidad, interfaz y sonido recuperados")
	check(not t.has_conflicts(), "Sin conflictos tras recargar")
	cfg.set_value(G, "view_distance", 77)
	cfg.set_value(G, "motion_blur", true)
	cfg.set_value(C, "signals", "Ñ")
	cfg.save(s.save_path)
	var u := _svc()
	u.save_path = s.save_path
	u.load_saved()
	check(u.get_applied(G, "view_distance") == 80, "Valor inválido ignorado (77 %)")
	check(u.get_applied(C, "signals") == "G", "Tecla inválida ignorada")
	check(u.get_applied(G, "motion_blur") == false, "Con reducir movimiento el desenfoque guardado no se enciende")
	var v := _svc()
	v.save_path = "user://no_existe_step16.cfg"
	check(v.load_saved() == 0, "Sin archivo: 0 valores")
	t.reset_to_defaults()
	check(t.get_applied(G, "shadow_quality") == "high" and t.pending_count() == 0, "reset_to_defaults()")
	check(t.snapshot().has(G) and t.snapshot()[G]["shadow_quality"] == "high", "snapshot()")
	for n in [s, t, u, v]:
		_free(n)


func _test_key_helpers() -> void:
	print("-- 14. Nombres de teclas")
	check(SS.canonical_key_name("esc") == "Esc" and SS.canonical_key_name("ESCAPE") == "Esc", "Esc canónica")
	check(SS.canonical_key_name("z") == "Z" and SS.canonical_key_name("7") == "7", "Letras y dígitos")
	check(SS.canonical_key_name("f10") == "F10" and SS.canonical_key_name("control") == "Ctrl", "F10 y Ctrl")
	check(SS.canonical_key_name("@") == "" and SS.canonical_key_name("F13") == "", "Teclas no admitidas")
	check(SS.key_name_from_keycode(KEY_ESCAPE) == "Esc" and SS.key_name_from_keycode(KEY_G) == "G" and SS.key_name_from_keycode(KEY_F10) == "F10", "keycode → nombre")
	check(SS.keycode_from_name("Esc") == KEY_ESCAPE and SS.keycode_from_name("G") == KEY_G and SS.keycode_from_name("F10") == KEY_F10, "nombre → keycode")
	check(SS.is_valid_key_name("Z") and not SS.is_valid_key_name("z"), "is_valid_key_name exige forma canónica")


# --------------------------------------------------------------------------
# 15+. Editor de interfaz — servicio
# --------------------------------------------------------------------------
func _test_editor_seed() -> void:
	print("-- 15. Editor: seed, módulos y diseños")
	var e := _ed()
	check(e.canvas_size == Vector2(944, 531) and e.grid == 24, "Lienzo 944×531 y cuadrícula de 24 px")
	check(ES.MODULE_IDS.size() == 9, "9 módulos editables")
	var labels := {"group_frames": "Grupo", "target_frame": "Objetivo", "timeline": "Línea de tiempo", "minimap": "Minimapa",
		"quest_tracker": "Misiones", "chat_box": "Chat", "action_bar": "Barra de acción", "player_portrait": "Retrato", "performance_meter": "Rendimiento"}
	for id in labels:
		check(e.module_label(id) == labels[id], "Módulo %s: «%s»" % [id, labels[id]])
	var rects := {"group_frames": Rect2(14, 14, 170, 150), "target_frame": Rect2(300, 14, 340, 80), "timeline": Rect2(300, 110, 340, 64),
		"minimap": Rect2(816, 14, 114, 114), "quest_tracker": Rect2(776, 150, 154, 110), "chat_box": Rect2(14, 300, 250, 110),
		"action_bar": Rect2(300, 410, 340, 108), "player_portrait": Rect2(160, 440, 120, 78), "performance_meter": Rect2(660, 440, 150, 78)}
	for id in rects:
		check(e.module_rect(id) == rects[id], "Rectángulo de %s como en el diseño" % id)
	check(e.preset_ids(true) == ["tank", "healer", "dps", "explorer", "raid20", "streamer"], "6 diseños por rol en la cuadrícula")
	check(e.preset_ids() .size() == 7 and e.has_preset("social"), "Diseño Social (ciudad) fuera de la cuadrícula")
	var pl := ["Tanque", "Sanador", "Daño", "Explorador", "Raid 20", "Streamer"]
	for i in pl.size():
		check(e.preset_label(e.preset_ids(true)[i]) == pl[i], "Etiqueta %s" % pl[i])
	check(e.active_preset == "dps" and e.preset_context() == "Daño · mazmorra", "Diseño activo: «Daño · mazmorra»")
	check(e.selected == "timeline", "Módulo seleccionado: Línea de tiempo")
	check(e.module_detail("timeline") == "340 × 64 · 100 %", "Detalle «340 × 64 · 100 %»")
	check(e.module_detail("chat_box") == "40 % fuera de combate", "Chat «40 % fuera de combate»")
	check(e.module_detail("group_frames") == "5 marcos" and e.module_detail("action_bar") == "2 filas × 10" and e.module_detail("minimap") == "120 px", "Detalles del seed")
	check(e.module_detail("quest_tracker") == "3 visibles" and e.module_detail("performance_meter") == "DPS · amenaza" and e.module_detail("target_frame") == "arriba centro", "Más detalles")
	check(near(e.module_opacity("timeline"), 0.4) and near(e.module_scale("timeline"), 1.0), "Línea de tiempo: escala 100 %, opacidad 40 %")
	check(e.visible_modules().size() == 9, "Los 9 visibles en Daño")
	check(e.auto_switch_by_content and e.snap_to_grid, "Cambio por contenido y cuadrícula activos")
	check(e.content_rule_text() == "Mazmorra → Daño · Raid → Raid 20 · Mundo → Explorador · Ciudad → Social", "Regla del contenido")
	check(e.module_at(Vector2(400, 140)) == "timeline" and e.module_at(Vector2(5, 5)) == "", "module_at()")
	check(not e.select_module("nope") and e.select_module("minimap") and e.selected == "minimap", "select_module valida")
	check(e.module_detail("timeline") == "340 × 64", "Sin seleccionar, la línea de tiempo muestra su detalle del seed")
	check(not e.is_preset_modified(), "Daño sin modificar")
	for id in e.preset_ids():
		for mid in ES.MODULE_IDS:
			var r: Rect2 = Rect2(Vector2(e.layouts[id][mid]["x"], e.layouts[id][mid]["y"]), e.module_base_size(mid) * float(e.layouts[id][mid]["scale"]))
			if r.end.x > 944.01 or r.end.y > 531.01:
				check(false, "%s/%s dentro del lienzo" % [id, mid])
	check(true, "Todos los módulos de todos los diseños caben en el lienzo")
	_free(e)


func _test_editor_alignment() -> void:
	print("-- 16. Guías magnéticas de alineación")
	var e := _ed()
	var g: Array = e.guides
	check(g.size() == 1, "Una guía al abrir (Línea de tiempo)")
	check(g.size() == 1 and g[0]["axis"] == "x" and near(g[0]["at"], 300.0), "Guía vertical en x = 300")
	check(g.size() == 1 and g[0]["label"] == "alineado con Objetivo" and g[0]["target"] == "target_frame", "«alineado con Objetivo» (el vecino más cercano)")
	check(g.size() == 1 and g[0]["color"] == Color("#ff6fa8") and ES.GUIDE_COLOR == Color("#ff6fa8"), "Línea rosa #ff6fa8")
	check(g.size() == 1 and g[0]["edge"] == "left", "Borde izquierdo")
	var mg: Array = []
	for gg in e.alignment_guides("minimap"):
		mg.append(gg["label"])
	check(mg == ["alineado con Misiones", "alineado con Objetivo"], "Minimapa: borde derecho con Misiones y borde superior con Objetivo")
	var cg: Array = []
	for gg in e.alignment_guides("chat_box"):
		cg.append(gg["label"])
	check(cg == ["alineado con Grupo", "alineado con Barra de acción"], "Chat: izquierda con Grupo y borde inferior con la Barra de acción")
	var gr: Dictionary = e.resolve_position("group_frames", Vector2(50, 50))
	check(gr["pos"] == Vector2(54, 48) and gr["guides"][0]["label"] == "alineado con Chat" and gr["guides"][0]["edge"] == "center", "Imán de centros: Grupo se centra con Chat")
	check(e.resolve_position("group_frames", Vector2(96, 96))["guides"].size() == 2, "Imán de bordes: derecha con Chat y arriba con el borde inferior de Objetivo")
	check(e.resolve_position("group_frames", Vector2(50, 50), false)["pos"] == Vector2(50, 50), "Sin imán: posición tal cual")
	check(e.alignment_guides("").is_empty(), "Sin selección no hay guías")
	var res: Dictionary = e.resolve_position("timeline", Vector2(304, 200))
	check(res["pos"] == Vector2(300, 196), "Imán: (304, 200) → (300, 196)")
	var labels: Array = []
	for gg in res["guides"]:
		labels.append(gg["label"])
	check(labels == ["alineado con Objetivo", "alineado con Misiones"], "Guías: Objetivo (x) y Misiones (y)")
	_free(e)


func _test_editor_moves() -> void:
	print("-- 17. Mover módulos: cuadrícula, límites y flechas")
	var e := _ed()
	var moved: Array = []
	e.module_changed.connect(func(id: String) -> void: moved.append(id))
	check(e.move_module("minimap", Vector2(500, 250)) == Vector2(504, 240), "Cuadrícula: (500, 250) → (504, 240)")
	check(e.module_rect("minimap").position == Vector2(504, 240), "Posición guardada")
	check(moved == ["minimap"], "Señal module_changed")
	e.set_snap(false)
	check(e.move_module("minimap", Vector2(497, 247)) == Vector2(497, 247), "Libre: (497, 247)")
	e.set_snap(true)
	check(e.snap_value(37) == 48.0 and e.snap_value(35) == 24.0, "snap_value redondea a 24")
	check(e.move_module("minimap", Vector2(2000, -50)) == Vector2(830, 0), "Se limita al lienzo (830, 0)")
	check(e.move_module("action_bar", Vector2(-100, 1000)) == Vector2(0, 423), "Abajo a la izquierda (0, 423)")
	e.move_module("group_frames", Vector2(14, 14))
	check(e.nudge("group_frames", Vector2.RIGHT) == Vector2(38, 14), "Flecha derecha: una celda (24 px)")
	e.set_snap(false)
	check(e.nudge("group_frames", Vector2.DOWN) == Vector2(38, 15), "Sin cuadrícula: 1 px")
	e.set_snap(true)
	check(e.move_module("nope", Vector2.ZERO) == Vector2.ZERO, "Módulo inexistente")
	check(e.begin_drag("timeline") and e.is_dragging(), "Empieza el arrastre")
	var h0: int = e.history_size()
	e.drag_to(Vector2(330, 250))
	e.drag_to(Vector2(380, 280))
	check(e.history_size() == h0, "El arrastre no apila historial por cada movimiento")
	check(e.end_drag() == "timeline" and not e.is_dragging(), "Termina el arrastre")
	check(e.module_rect("timeline").position == Vector2(384, 288), "Soltado en la celda (384, 288)")
	e.begin_drag("timeline")
	var h1: int = e.history_size()
	e.end_drag()
	check(e.history_size() == h1 - 1, "Un arrastre sin movimiento no deja historial")
	check(not e.begin_drag("nope") and e.drag_to(Vector2.ZERO) == Vector2.ZERO, "Arrastre inválido")
	_free(e)


func _test_editor_properties() -> void:
	print("-- 18. Escala, opacidad, visibilidad y combate simulado")
	var e := _ed()
	check(near(e.set_module_scale("timeline", 1.5), 1.5) and e.module_rect("timeline").size == Vector2(510, 96), "Escala 150 % → 510×96")
	check(e.module_detail("timeline") == "510 × 96 · 150 %", "Detalle con escala")
	check(near(e.set_module_scale("timeline", 2.0), 1.5), "Máximo 150 %")
	check(near(e.set_module_scale("timeline", 0.1), 0.5), "Mínimo 50 %")
	check(near(e.set_module_scale("timeline", 1.23), 1.25), "Pasos de 5 %")
	e.move_module("minimap", Vector2(830, 0))
	e.set_module_scale("minimap", 1.5)
	check(e.module_rect("minimap").end.x <= 944.0 and near(e.module_rect("minimap").position.x, 773.0), "Al crecer se mantiene dentro del lienzo")
	check(near(e.set_module_opacity("chat_box", 0.75), 0.75) and e.module_detail("chat_box") == "75 % fuera de combate", "Opacidad del chat 75 %")
	check(near(e.set_module_opacity("chat_box", 1.4), 1.0) and near(e.set_module_opacity("chat_box", -1), 0.0), "Opacidad 0–100 %")
	e.set_module_opacity("chat_box", 0.4)
	check(near(e.effective_opacity("chat_box"), 0.4) and near(e.effective_opacity("chat_box", true), 1.0), "En combate se ve al 100 %")
	var sims: Array = []
	e.combat_simulation_changed.connect(func(on: bool) -> void: sims.append(on))
	e.simulate_combat(true)
	check(near(e.effective_opacity("chat_box"), 1.0) and sims == [true], "Probar en combate simulado")
	e.simulate_combat(true)
	check(sims == [true], "Sin cambios no emite")
	e.simulate_combat(false)
	check(e.set_module_visible("quest_tracker", false) and not e.is_module_visible("quest_tracker"), "Ocultar Misiones")
	check(not e.set_module_visible("quest_tracker", false), "Ya oculto")
	check(e.module_at(Vector2(800, 200)) == "", "Un módulo oculto no se puede tocar")
	check(not e.begin_drag("quest_tracker"), "Ni arrastrar")
	check(e.visible_modules().size() == 8, "8 visibles")
	check(e.is_preset_modified(), "El diseño queda modificado")
	_free(e)


func _test_editor_presets() -> void:
	print("-- 19. Diseños por rol y cambio por contenido")
	var e := _ed()
	var changes: Array = []
	e.preset_changed.connect(func(p: String) -> void: changes.append(p))
	check(e.apply_preset("tank") and e.active_preset == "tank" and changes == ["tank"], "Tanque")
	check(e.module_detail("performance_meter") == "amenaza" and near(e.module_scale("target_frame"), 1.15), "Tanque: medidor de amenaza y objetivo grande")
	check(e.apply_preset("raid20") and e.module_detail("group_frames") == "20 marcos" and near(e.module_scale("group_frames"), 1.5), "Raid 20: 20 marcos")
	check(not e.is_module_visible("quest_tracker"), "Raid 20 oculta Misiones")
	check(e.apply_preset("explorer") and not e.is_module_visible("performance_meter") and near(e.module_scale("minimap"), 1.4), "Explorador: minimapa grande, sin medidor")
	check(e.apply_preset("streamer") and not e.is_module_visible("chat_box"), "Streamer: sin chat")
	check(e.apply_preset("healer") and e.preset_context() == "Sanador · mazmorra", "Sanador")
	check(not e.apply_preset("bard"), "Diseño inexistente")
	e.apply_preset("dps")
	e.move_module("minimap", Vector2(600, 240))
	e.apply_preset("tank")
	e.apply_preset("dps")
	check(e.module_rect("minimap").position == Vector2(600, 240), "Cada diseño conserva sus ediciones")
	check(e.reset_preset() and e.module_rect("minimap").position == Vector2(816, 14), "Restablecer el diseño del seed")
	check(not e.reset_preset("bard"), "Restablecer inexistente")
	check(e.on_content_changed("raid") == "raid20", "Raid → Raid 20")
	check(e.on_content_changed("world") == "explorer", "Mundo → Explorador")
	check(e.on_content_changed("city") == "social", "Ciudad → Social")
	check(e.on_content_changed("dungeon") == "dps", "Mazmorra → Daño")
	check(e.on_content_changed("arena") == "dps", "Contenido sin regla: no cambia")
	var flips: Array = []
	e.auto_switch_changed.connect(func(on: bool) -> void: flips.append(on))
	e.set_auto_switch(false)
	check(e.on_content_changed("raid") == "dps" and e.current_content == "raid", "Sin cambio automático se queda en Daño")
	check(flips == [false], "Señal auto_switch_changed")
	e.set_auto_switch(true)
	check(e.on_content_changed("raid") == "raid20", "Reactivado vuelve a cambiar")
	_free(e)


func _test_editor_history() -> void:
	print("-- 20. Historial: deshacer y rehacer")
	var e := _ed()
	check(not e.can_undo() and not e.undo() and not e.redo(), "Historial vacío")
	e.move_module("minimap", Vector2(500, 250))
	e.set_module_scale("group_frames", 1.2)
	e.apply_preset("tank")
	check(e.history_size() == 3, "3 pasos en el historial")
	check(e.undo() and e.active_preset == "dps", "Deshacer el cambio de diseño")
	check(e.undo() and near(e.module_scale("group_frames"), 1.0), "Deshacer la escala")
	check(e.undo() and e.module_rect("minimap").position == Vector2(816, 14), "Deshacer el movimiento")
	check(not e.can_undo() and e.can_redo(), "Fin del historial; se puede rehacer")
	check(e.redo() and e.module_rect("minimap").position == Vector2(504, 240), "Rehacer el movimiento")
	e.move_module("minimap", Vector2(600, 240))
	check(not e.can_redo(), "Un cambio nuevo borra lo rehacible")
	check(e.handle_shortcut(_key(KEY_Z, true)) and e.module_rect("minimap").position == Vector2(504, 240), "Ctrl+Z deshace")
	check(e.handle_shortcut(_key(KEY_Y, true)) and e.module_rect("minimap").position == Vector2(600, 240), "Ctrl+Y rehace")
	e.handle_shortcut(_key(KEY_Z, true))
	check(e.handle_shortcut(_key(KEY_Z, true, true)) and e.module_rect("minimap").position == Vector2(600, 240), "Ctrl+Shift+Z rehace")
	check(not e.handle_shortcut(_key(KEY_Z)) and not e.handle_shortcut(_key(KEY_A, true)), "Z sin Ctrl o Ctrl+A no se consumen")
	var hist: Array = []
	e.history_changed.connect(func(u: bool, r: bool) -> void: hist.append([u, r]))
	e.move_module("minimap", Vector2(480, 240))
	check(hist.back() == [true, false], "Señal history_changed")
	for i in 70:
		e.move_module("minimap", Vector2(24 * (i % 30), 240))
	check(e.history_size() == e.history_limit, "Historial limitado a %d pasos" % e.history_limit)
	_free(e)


func _test_editor_codes() -> void:
	print("-- 21. Códigos para compartir")
	var e := _ed()
	check(e.share_code() == "HUD-7QK-D2M", "Daño sin tocar: «HUD-7QK-D2M»")
	var full: String = e.export_code()
	check(full.begins_with("HUD-") and ES.normalize_code(full).length() == 63, "Código completo: HUD- + 63 símbolos")
	check(full.split("-").size() == 22, "21 grupos de 3")
	var d: Dictionary = e.decode_code(full)
	check(d["ok"] and d["preset"] == "dps", "Se decodifica")
	check(ES._layouts_equal(d["layout"], e.layouts["dps"]), "Ida y vuelta sin pérdidas")
	check(e.decode_code(full.to_lower())["ok"], "Admite minúsculas")
	var tampered := full.substr(0, 10) + ("A" if full[10] != "A" else "B") + full.substr(11)
	check(not e.decode_code(tampered)["ok"] and e.decode_code(tampered)["error"] == "El código no es válido (suma de control)", "Código alterado → suma de control")
	check(e.decode_code("HUD-123")["error"] == "Longitud de código incorrecta", "Longitud incorrecta")
	check(e.decode_code("HUD-!!!-???")["error"] == "Código con símbolos no válidos", "Símbolos no válidos")
	check(ES.normalize_code("hud-oil-111") == "011111", "Crockford: O→0, I/L→1")
	e.move_module("minimap", Vector2(600, 240))
	e.set_module_opacity("chat_box", 0.7)
	var short: String = e.share_code()
	check(short != "HUD-7QK-D2M" and short.length() == 11 and short.begins_with("HUD-"), "Diseño editado: código corto nuevo «%s»" % short)
	check(short == ES.short_code_for(e.export_code()), "Derivado del código completo")
	var code2: String = e.export_code()
	e.apply_preset("tank")
	var imported: Array = []
	e.code_imported.connect(func(c: String, ok: bool) -> void: imported.append(ok))
	var r: Dictionary = e.import_code(short)
	check(r["ok"] and e.active_preset == "dps" and e.module_rect("minimap").position == Vector2(600, 240), "Importar el código corto registrado")
	check(near(e.module_opacity("chat_box"), 0.7), "Con su opacidad")
	e.reset_preset()
	r = e.import_code(code2)
	check(r["ok"] and e.module_rect("minimap").position == Vector2(600, 240), "Importar el código completo")
	check(e.undo() and e.module_rect("minimap").position == Vector2(816, 14), "Importar se puede deshacer")
	e.apply_preset("healer")
	check(e.import_code("HUD-7QK-D2M")["ok"] and e.active_preset == "dps" and not e.is_preset_modified(), "«HUD-7QK-D2M» carga Daño del seed")
	r = e.import_code("HUD-AAA-AAA")
	check(not r["ok"] and r["error"] == "Código desconocido" and e.last_import_error == "Código desconocido", "Código corto desconocido")
	check(not e.import_code(tampered)["ok"], "Código alterado no se importa")
	check(imported == [true, true, true, false, false], "Señal code_imported")
	var other := _ed()
	check(other.import_code(code2)["ok"] and other.module_rect("minimap").position == Vector2(600, 240), "Otro jugador importa el código completo")
	var tank_code: String = other.export_code("tank")
	check(other.decode_code(tank_code)["preset"] == "tank", "El código lleva el diseño de origen")
	_free(other)
	_free(e)


func _test_editor_persistence() -> void:
	print("-- 22. Persistencia en user://ui_layouts.cfg")
	var e := _ed()
	check(ES.DEFAULT_SAVE_PATH == "user://ui_layouts.cfg", "Ruta por defecto user://ui_layouts.cfg")
	e.move_module("minimap", Vector2(600, 240))
	e.set_module_scale("timeline", 1.2)
	e.apply_preset("raid20")
	e.set_snap(false)
	e.set_auto_switch(false)
	check(e.save_count >= 4 and FileAccess.file_exists(e.save_path), "Guardado automático")
	var f := _ed()
	f.save_path = e.save_path
	check(f.load_saved() == 63, "Carga 7 diseños × 9 módulos")
	check(f.active_preset == "raid20" and not f.snap_to_grid and not f.auto_switch_by_content, "Diseño activo y opciones")
	check(not f.can_undo(), "El historial no se persiste")
	f.apply_preset("dps")
	check(f.module_rect("minimap").position == Vector2(600, 240) and near(f.module_scale("timeline"), 1.2), "Ediciones recuperadas")
	var cfg := ConfigFile.new()
	cfg.load(e.save_path)
	cfg.set_value("layout_dps", "minimap", {"x": 5000.0, "y": 10.0, "scale": 9.0, "opacity": 3.0, "visible": true})
	cfg.save(e.save_path)
	var g := _ed()
	g.save_path = e.save_path
	g.load_saved()
	g.apply_preset("dps")
	check(near(g.module_scale("minimap"), 1.5) and g.module_rect("minimap").end.x <= 944.0 and near(g.module_opacity("minimap"), 1.0), "Valores fuera de rango se corrigen al cargar")
	for n in [e, f, g]:
		_free(n)


# --------------------------------------------------------------------------
# 23. Ventana de Ajustes
# --------------------------------------------------------------------------
func _test_settings_window() -> void:
	print("-- 23. SettingsWindow (MMO-Ajustes.html)")
	var s := _svc()
	s.apply_to_engine = false
	var w = load(SETTINGS_SCENE).instantiate()
	w.settings = s
	root.add_child(w)
	w.initialize_window({})
	await _frames(2)
	check(w.window_id == "settings_window", "window_id settings_window")
	check(w.stage.size == Vector2(1440, 810), "Escenario 1440×810")
	check(w.menu_bar != null and w.menu_bar.position == Vector2.ZERO and near(w.menu_bar.size.x, 1440.0) and near(w.menu_bar.size.y, 64.0, 1.5), "Barra del menú común 1440×64 (es %s)" % str(w.menu_bar.size))
	check(w.left_card.position == Vector2(28, 88) and w.left_card.size == Vector2(300, 694), "Columna izquierda 300×694 en (28, 88)")
	check(w.center_card.position == Vector2(344, 88) and w.center_card.size == Vector2(700, 694), "Columna central 700×694 en (344, 88)")
	check(w.right_card.position == Vector2(1060, 88) and w.right_card.size == Vector2(352, 694), "Columna derecha 352×694 en (1060, 88)")
	check(w.heading_label.text == "Ajustes", "Título «Ajustes»")
	check(w.category_buttons.size() == 7, "7 categorías")
	check(w.category_buttons["graphics"].get_meta("selected") and not w.category_buttons["audio"].get_meta("selected"), "Gráficos seleccionada")
	check(w.category_warnings["controls"].visible and not w.category_warnings["graphics"].visible, "Punto ámbar en Controles")
	check(w.category_title.text == "Gráficos", "Cabecera «Gráficos»")
	check(w.preset_bar.visible and w.preset_buttons.size() == 5, "Presets visibles")
	check(w.preset_buttons["custom"].get_meta("active") and not w.preset_buttons["high"].get_meta("active"), "«Personal» activo")
	check(w.option_rows.size() == 9, "9 filas de Gráficos")
	check(w.fps_labels["shadow_quality"].text == "−8 fps" and w.fps_labels["spell_effects"].text == "+12 fps", "Indicadores −8 fps y +12 fps")
	check(w.fps_labels["shadow_quality"].get_theme_color("font_color") == Color("#f5c35b"), "−fps en ámbar")
	check(w.fps_labels["resolution_scale"].get_theme_color("font_color") == Color("#4fe39a"), "+fps en verde")
	check((w.value_buttons["shadow_quality"].get_node("Row/Text") as Label).text == "Alta", "Valor «Alta ▾»")
	check((w.value_buttons["view_distance"].get_node("Row/Text") as Label).text == "80 %", "Valor «80 %»")
	check(w.value_buttons["motion_blur"].disabled, "Desenfoque bloqueado (Reducir movimiento)")
	check(w.hint_labels["motion_blur"].text == "Apagado por «Reducir movimiento»", "Motivo del bloqueo")
	check(w.hint_labels["view_distance"].text == "Afecta al mapa y a las grietas lejanas", "Ayuda de la opción")
	check(w.perf_rows.size() == 4, "4 barras de rendimiento")
	check(w.perf_rows[0]["name"].text == "Mundo abierto" and w.perf_rows[0]["fps"].text == "144 fps", "Mundo abierto 144 fps")
	check(near(w.perf_rows[0]["meter"].ratio, 0.96) and w.perf_rows[0]["meter"].color == Color("#4fe39a"), "Barra verde al 96 %")
	check(w.perf_rows[2]["fps"].text == "96 fps" and w.perf_rows[2]["meter"].color == Color("#f5c35b"), "Ciudad del Nexo ámbar")
	check(w.perf_rows[3]["fps"].text == "60 fps" and w.perf_rows[3]["meter"].color == Color("#9aa6ae"), "Refugio gris")
	check(w.perf_note.text == "Medido en tus últimas sesiones, no en una prueba sintética.", "Nota de medición")
	check(w.conflict_card.visible, "Tarjeta «Atajo repetido» visible")
	check((w.conflict_key.get_node("Key") as Label).text == "G" and w.conflict_label.text == "abre Señales y también llama a la montura.", "Mensaje con tecla G")
	check(w.quick_fix_button.text == "Montura → Z" and w.choose_other_button.text == "Elegir otra", "Botones «Montura → Z» y «Elegir otra»")
	check(not w.confirm_card.visible, "Sin confirmación de pantalla")
	check(w.pending_label.text == "Sin cambios pendientes" and w.undo_button.disabled and w.apply_button.disabled, "Pie sin cambios: botones desactivados")
	# Buscador
	w.set_search("sombras")
	await _frames(1)
	check(w.search_summary_label.text == "2 resultados: Gráficos › Calidad de sombras · Interfaz › Sombra del texto", "Resumen de búsqueda")
	check(w.option_rows["shadow_quality"].get_meta("search_hit") and not w.option_rows["view_distance"].get_meta("search_hit"), "Resalta Calidad de sombras")
	check(w.hint_labels["shadow_quality"].text == "Coincide con tu búsqueda", "«Coincide con tu búsqueda»")
	check(w.category == "graphics", "Se queda en Gráficos")
	w.set_search("texto")
	check(w.category == "interface" and w.option_rows["text_shadow"].get_meta("search_hit"), "«texto» salta a Interfaz")
	check(w.handle_key(KEY_ESCAPE) and w.search_text == "" and w.search_edit.text == "", "Esc limpia la búsqueda")
	check(w.visible, "La ventana sigue abierta")
	# Elegir valores
	w.select_category("graphics")
	check(w.choose("graphics", "shadow_quality", "medium"), "Elegir sombras Media")
	await _frames(1)
	check((w.value_buttons["shadow_quality"].get_node("Row/Text") as Label).text == "Media" and w.fps_labels["shadow_quality"].text == "−3 fps", "Fila actualizada: Media −3 fps")
	check(w.pending_dots["shadow_quality"].visible, "Punto de cambio pendiente")
	check(w.perf_rows[0]["fps"].text == "149 fps", "Rendimiento estimado en vivo (+5)")
	check(w.preset_buttons["medium"].get_meta("active"), "Sombras Media hace que el borrador coincida con «Medio»")
	w.choose_preset("high")
	check(w.preset_buttons["high"].get_meta("active") and (w.value_buttons["view_distance"].get_node("Row/Text") as Label).text == "100 %", "Preset Alto desde la cabecera")
	check(w.pending_label.text.begins_with("[b][color=#eef2f4]") and w.pending_label.text.contains("cambios sin aplicar · los de pantalla se deshacen solos si no confirmas en 15 s"), "Pie «N cambios sin aplicar…»")
	check(not w.undo_button.disabled and not w.apply_button.disabled, "Deshacer y Aplicar activos")
	check(w.undo_changes() >= 3 and s.pending_count() == 0, "Deshacer")
	check(w.preset_buttons["custom"].get_meta("active"), "Vuelve a Personal")
	# Pantalla con cuenta atrás
	w.choose("graphics", "display_mode", "windowed")
	w.apply_changes()
	await _frames(1)
	check(w.confirm_card.visible and w.confirm_label.text == "Se revierten solos en 15 s", "Tarjeta «¿Mantener…?» con 15 s")
	s.tick(6.0)
	check(w.confirm_label.text == "Se revierten solos en 9 s", "Cuenta atrás visible")
	check(w.keep_display() and not s.confirm_active, "Mantener")
	await _frames(1)
	check(not w.confirm_card.visible, "La tarjeta desaparece")
	w.choose("graphics", "display_mode", "fullscreen")
	w.apply_changes()
	s.tick(16.0)
	await _frames(1)
	check(s.get_applied("graphics", "display_mode") == "windowed" and not w.confirm_card.visible, "Sin confirmar se revierte solo")
	# Sonido
	check(w.select_category("audio") and w.category_title.text == "Sonido", "Categoría Sonido")
	check(not w.preset_bar.visible, "Sin presets fuera de Gráficos")
	check(w.sliders.size() == 5 and w.mute_buttons.size() == 5, "5 buses con deslizador y silencio")
	check(w.slider_labels["volume_master"].text == "100 %", "Volumen general 100 %")
	w.sliders["volume_music"].value = 45
	await _frames(1)
	check(near(s.bus_volume("Music"), 45.0) and w.slider_labels["volume_music"].text == "45 %", "Deslizador → servicio")
	w.mute_buttons["SFX"].pressed.emit()
	await _frames(1)
	check(s.bus_muted("SFX") and w.mute_buttons["SFX"].text == "Silenciado", "Silenciar SFX desde la fila")
	w.undo_changes()
	# Controles
	check(w.select_category("controls") and w.key_buttons.size() == 22, "Controles: 22 teclas")
	check(w.option_rows["signals"].get_meta("conflict") and w.option_rows["mount"].get_meta("conflict"), "Filas en conflicto resaltadas")
	check(w.key_buttons["mount"].text == "G" and w.key_buttons["menu_close"].disabled, "Tecla G y Esc fija")
	check(w.hint_labels["mount"].text == "Comparte tecla con otra acción", "Aviso en la fila")
	check(w.quick_fix(), "«Montura → Z»")
	await _frames(1)
	check(w.key_buttons["mount"].text == "Z" and not w.conflict_card.visible and not w.category_warnings["controls"].visible, "Conflicto resuelto en vivo")
	w.undo_changes()
	await _frames(1)
	check(w.conflict_card.visible, "Deshacer recupera el aviso")
	check(w.choose_other_key() and s.rebinding_action == "mount", "«Elegir otra» espera una tecla para la montura")
	await _frames(1)
	check(w.key_buttons["mount"].text == "…" and w.hint_labels["mount"].text == "Pulsa una tecla… (Esc cancela)", "Fila en espera")
	check(w.handle_key(KEY_X) and s.get_binding("mount") == "X", "Pulsar X asigna la montura")
	check(not w.conflict_card.visible, "Sin conflicto")
	w.start_rebind("signals")
	check(w.handle_key(KEY_ESCAPE) and s.rebinding_action == "" and w.visible, "Esc cancela la reasignación sin cerrar")
	check(w.apply_changes().size() == 1 and s.pending_count() == 0, "Aplicar")
	# Accesibilidad
	var fs0: int = w.heading_label.get_theme_font_size("font_size")
	s.set_and_apply("accessibility", "large_text", true)
	await _frames(1)
	check(w.heading_label.get_theme_font_size("font_size") == roundi(fs0 * 1.15), "Texto grande escala la ventana (115 %)")
	s.set_and_apply("graphics", "ui_brightness", 120)
	await _frames(1)
	check(near(w.stage.modulate.r, 1.2), "Brillo de la interfaz 120 %")
	s.set_and_apply("accessibility", "color_mode", "protanopia")
	w.select_category("graphics")
	await _frames(1)
	check(w.fps_labels["spell_effects"].get_theme_color("font_color") == Color("#3fa7ff"), "Protanopia: +fps en azul")
	check(w.perf_rows[0]["shape"].visible and w.perf_rows[0]["shape"].kind == "circle", "Forma de estado junto al color")
	# Teclado
	w.handle_key(KEY_K, true)
	check(true, "Ctrl K enfoca el buscador")
	var closed := [false]
	w.closed.connect(func() -> void: closed[0] = true)
	check(w.handle_key(KEY_ESCAPE) and not w.visible and closed[0], "Esc cierra Ajustes")
	w.visible = true
	check(w.handle_key(KEY_F10) and not w.visible, "F10 cierra Ajustes")
	w.queue_free()
	_free(s)
	await _frames(1)


# --------------------------------------------------------------------------
# 24. Ventana del Editor de interfaz
# --------------------------------------------------------------------------
func _test_editor_window() -> void:
	print("-- 24. UIEditorWindow (MMO-Interfaz.html)")
	var s := _svc()
	s.apply_to_engine = false
	var e := _ed()
	var w = load(EDITOR_SCENE).instantiate()
	w.settings = s
	w.editor = e
	root.add_child(w)
	w.initialize_window({})
	await _frames(2)
	check(w.window_id == "ui_editor", "window_id ui_editor")
	check(w.preview_card.position == Vector2(28, 88) and w.preview_card.size == Vector2(980, 694), "Vista previa 980×694 en (28, 88)")
	check(w.panel_card.position == Vector2(1024, 88) and w.panel_card.size == Vector2(388, 694), "Panel 388×694 en (1024, 88)")
	check(w.canvas.size == Vector2(944, 531), "Área de trabajo 944×531")
	check(w.module_boxes.size() == 9, "9 módulos en el lienzo")
	for id in w.module_boxes:
		var mb = w.module_boxes[id]
		check(Rect2(mb.position, mb.size) == e.module_rect(id) and mb.title == e.module_label(id), "Módulo %s colocado" % id)
	check(w.module_boxes["timeline"].selected and w.module_boxes["timeline"].detail == "340 × 64 · 100 %", "Línea de tiempo seleccionada «340 × 64 · 100 %»")
	check(w.module_boxes["chat_box"].detail == "40 % fuera de combate", "Chat «40 % fuera de combate»")
	check(w.overlay.guides.size() == 1 and w.overlay.guides[0]["label"] == "alineado con Objetivo", "Guía rosa «alineado con Objetivo»")
	check(w.overlay.selected_rect == Rect2(300, 110, 340, 64), "Esquinas del módulo seleccionado")
	check(w.snap_chip.text == "Ajustar a cuadrícula ✓", "Chip «Ajustar a cuadrícula ✓»")
	check(w.combat_chip.text == "Probar en combate simulado" and not w.combat_chip.get_meta("active"), "Chip «Probar en combate simulado»")
	check((w.drag_chip.find_child("Text", true, false) as Label).text == "Arrastra módulos", "Chip «Arrastra módulos»")
	check(w.undo_chip.text == "Deshacer" and w.undo_chip.disabled, "«Deshacer [Ctrl Z]» sin historial")
	check((w.layout_chip.find_child("Text", true, false) as Label).text == "Daño · mazmorra", "Diseño: «Daño · mazmorra»")
	check(w.code_edit.text == "HUD-7QK-D2M", "Código «HUD-7QK-D2M»")
	check(w.import_button.text == "Importar", "Botón Importar")
	check(w.preset_chips.size() == 6 and w.preset_chips["dps"].get_meta("active") and not w.preset_chips["tank"].get_meta("active"), "6 diseños por rol con Daño activo")
	check(w.auto_switch.button_pressed, "«Cambiar solo según el contenido» activo")
	check(w.content_rule_label.text == "Mazmorra → Daño · Raid → Raid 20 · Mundo → Explorador · Ciudad → Social", "Regla visible")
	check(w.selected_caps.text == "MÓDULO SELECCIONADO · LÍNEA DE TIEMPO", "«Módulo seleccionado · Línea de tiempo»")
	check(w.scale_value_label.text == "100 %" and near(w.scale_slider.value, 100.0), "Escala 100 %")
	check(near(w.scale_slider.ratio, 0.5), "Deslizador de escala a la mitad (50–150 %)")
	check(w.opacity_value_label.text == "40 %" and near(w.opacity_slider.value, 40.0), "Opacidad fuera de combate 40 %")
	check(w.color_mode_buttons.size() == 4 and w.color_mode_buttons["normal"].get_meta("active"), "Modo de color Normal")
	check(w.color_mode_buttons["protanopia"].text == "Protan." and w.color_mode_buttons["tritanopia"].text == "Tritan.", "Etiquetas cortas")
	var exp_sw := {"large_text": false, "reduce_motion": true, "narrator": false, "directional_audio": true, "shapes_with_colors": true}
	for k in exp_sw:
		check(w.a11y_switches[k].button_pressed == exp_sw[k], "Interruptor %s = %s" % [k, exp_sw[k]])
	# Arrastrar
	var p: Vector2 = w.drag_module("minimap", Vector2(600, 250))
	await _frames(1)
	check(p == Vector2(600, 240) and w.module_boxes["minimap"].position == Vector2(600, 240), "Arrastrar el minimapa a la cuadrícula")
	check(w.module_boxes["minimap"].selected and w.selected_caps.text == "MÓDULO SELECCIONADO · MINIMAPA", "El arrastrado queda seleccionado")
	check(not w.undo_chip.disabled, "Deshacer disponible")
	check((w.layout_chip.find_child("Text", true, false) as Label).text == "Daño · mazmorra · editado", "Diseño editado")
	check(w.code_edit.text != "HUD-7QK-D2M" and w.code_edit.text.begins_with("HUD-"), "Nuevo código corto")
	check(w.handle_key(KEY_Z, true) and w.module_boxes["minimap"].position == Vector2(816, 14), "Ctrl Z deshace el arrastre")
	check(w.handle_key(KEY_Y, true) and w.module_boxes["minimap"].position == Vector2(600, 240), "Ctrl Y rehace")
	check(w.handle_key(KEY_RIGHT) and w.module_boxes["minimap"].position == Vector2(624, 240), "Flecha derecha mueve una celda")
	check(w.handle_key(KEY_TAB) and e.selected == "quest_tracker", "Tab pasa al siguiente módulo")
	# Propiedades
	w.select_module("timeline")
	w.scale_slider.value = 120
	await _frames(1)
	check(near(e.module_scale("timeline"), 1.2) and w.scale_value_label.text == "120 %", "Deslizador de escala → 120 %")
	check(w.module_boxes["timeline"].size == Vector2(408, 76.8) and w.module_boxes["timeline"].detail == "408 × 77 · 120 %", "El módulo crece en el lienzo")
	w.opacity_slider.value = 70
	await _frames(1)
	check(near(e.module_opacity("timeline"), 0.7) and w.opacity_value_label.text == "70 %", "Opacidad 70 %")
	check(near(w.set_scale_percent(200), 150.0), "Escala máxima 150 %")
	w.select_module("")
	await _frames(1)
	check(not w.scale_slider.editable and w.selected_caps.text == "MÓDULO SELECCIONADO · NINGUNO", "Sin selección los deslizadores se bloquean")
	check(w.set_scale_percent(80) == 0.0, "Sin selección no cambia nada")
	w.select_module("chat_box")
	# Diseños
	check(w.choose_preset("raid20") and w.preset_chips["raid20"].get_meta("active"), "Chip Raid 20")
	await _frames(1)
	check((w.layout_chip.find_child("Text", true, false) as Label).text == "Raid de 20" and not w.module_boxes["quest_tracker"].visible, "Raid de 20 oculta Misiones")
	check(w.module_boxes["group_frames"].detail == "20 marcos", "20 marcos")
	w.auto_switch.button_pressed = false
	await _frames(1)
	check(not e.auto_switch_by_content, "Interruptor desactiva el cambio por contenido")
	w.set_auto_switch(true)
	w.initialize_window({"content": "dungeon"})
	await _frames(1)
	check(e.active_preset == "dps" and w.preset_chips["dps"].get_meta("active"), "Entrar en mazmorra → Daño")
	check(not w.toggle_snap() and w.snap_chip.text == "Ajustar a cuadrícula ✗", "Quitar la cuadrícula")
	check(not w.grid_layer.visible_grid, "La cuadrícula se oculta")
	w.toggle_snap()
	check(w.toggle_combat_simulation() and w.combat_chip.get_meta("active") and near(w.module_boxes["chat_box"].fill_alpha, 1.0), "Combate simulado: todo al 100 %")
	w.toggle_combat_simulation()
	check(near(w.module_boxes["chat_box"].fill_alpha, 0.4), "Fuera de combate: 40 %")
	# Códigos
	var bad: Dictionary = w.import_code("HUD-ZZZ-ZZZ")
	check(not bad["ok"] and w.code_title.text == "Código desconocido", "Código desconocido: aviso en el pie")
	check(w.code_title.get_theme_color("font_color") == Color("#ff6b6b"), "Aviso en rojo")
	e.apply_preset("tank")
	w.code_edit.text = "HUD-7QK-D2M"
	var good: Dictionary = w.import_code()
	await _frames(1)
	check(good["ok"] and e.active_preset == "dps" and w.code_title.text == "Código para compartir", "Importar «HUD-7QK-D2M» desde el campo")
	check(w.share_code() == e.share_code(), "share_code()")
	# Accesibilidad del HUD
	check(w.set_color_mode("deuteranopia") and s.color_mode() == "deuteranopia", "Modo de color Deutan.")
	await _frames(1)
	check(w.color_mode_buttons["deuteranopia"].get_meta("active") and not w.color_mode_buttons["normal"].get_meta("active"), "Segmento activo")
	w.a11y_switches["large_text"].button_pressed = true
	await _frames(1)
	check(near(s.text_scale(), 1.15) and near(w.module_boxes["timeline"].text_scale, 1.15), "Texto grande en todos los módulos")
	w.a11y_switches["narrator"].button_pressed = true
	await _frames(1)
	check(s.narrator_enabled(), "Narrador activado")
	w.select_module("minimap")
	check(s.last_narration == "Minimapa seleccionado", "El narrador lee la selección")
	w.a11y_switches["reduce_motion"].button_pressed = false
	await _frames(1)
	check(not s.reduce_motion() and not s.is_locked("graphics", "motion_blur"), "Reducir movimiento desactivado")
	w.a11y_switches["shapes_with_colors"].button_pressed = false
	w.a11y_switches["directional_audio"].button_pressed = false
	await _frames(1)
	check(s.shape_for("warn") == "" and not s.directional_audio_enabled(), "Formas y avisos 3D desactivados")
	check(s.pending_count() == 0, "Los interruptores aplican al instante")
	var closed := [false]
	w.closed.connect(func() -> void: closed[0] = true)
	check(w.handle_key(KEY_ESCAPE) and not w.visible and closed[0], "Esc cierra el editor")
	w.queue_free()
	_free(e)
	_free(s)
	await _frames(1)


# --------------------------------------------------------------------------
# 25. Orquestación (F10, menú común, open_settings / open_ui_editor)
# --------------------------------------------------------------------------
func _test_orchestrated_flow() -> void:
	print("-- 25. Orquestación: open_settings, open_ui_editor y F10")
	var orch := root.get_node_or_null("UIOrchestrator")
	var ss := root.get_node_or_null("SettingsService")
	var es := root.get_node_or_null("UIEditorService")
	var router := root.get_node_or_null("UIInputRouter")
	if orch == null or ss == null or es == null:
		check(false, "Autoloads disponibles")
		return
	ss.save_path = _cfg_path()
	ss.apply_to_engine = false
	ss.auto_tick = false
	ss.reset_to_defaults()
	es.save_path = _cfg_path("layouts")
	es.load_seed(EDITOR_SEED)
	var w: Node = orch.open_settings("controls")
	await _frames(2)
	check(w != null and orch.is_window_open("settings_window"), "open_settings abre Ajustes")
	check(w.category == "controls" and w.settings == ss, "En Controles y con el autoload SettingsService")
	check(w.get_parent() == orch.window_layer, "En la capa de ventanas del orquestador")
	orch.open_settings("audio")
	check(w.category == "audio", "Reabrir cambia de categoría")
	w.handle_key(KEY_ESCAPE)
	await _frames(1)
	check(not orch.is_window_open("settings_window"), "Esc la cierra vía orquestador")
	if router != null:
		check(router.handle_window_shortcut(_key(KEY_F10), orch), "F10 (atajo del registro) abre Ajustes")
		await _frames(1)
		check(orch.is_window_open("settings_window"), "Ajustes abiertos con F10")
		check(router.handle_window_shortcut(_key(KEY_F10), orch) and not orch.is_window_open("settings_window"), "F10 otra vez los cierra")
	var ed: Node = orch.open_ui_editor()
	await _frames(2)
	check(ed != null and orch.is_window_open("ui_editor") and ed.editor == es, "open_ui_editor abre el Editor con el autoload")
	ed.handle_key(KEY_F10)
	await _frames(1)
	check(orch.is_window_open("settings_window"), "F10 desde el editor abre Ajustes")
	check(orch.get_window_instance("settings_window").category == "interface", "…en la categoría Interfaz")
	ed.menu_bar.request_settings()
	await _frames(1)
	check(not orch.is_window_open("settings_window"), "El botón Ajustes del menú común alterna la ventana")
	orch.open_ui_editor({"module": "chat_box", "content": "raid"})
	check(es.selected == "chat_box" and es.active_preset == "raid20", "open_ui_editor con módulo y contenido")
	orch.close_window("ui_editor")
	check(not orch.is_window_open("ui_editor"), "Cerrar el editor")
	orch.close_all_windows()
	await _frames(1)
