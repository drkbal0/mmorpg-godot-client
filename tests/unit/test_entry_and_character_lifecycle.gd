extends SceneTree
## Suite headless (UI v2.4 Paso 15 · ADR 113): Entrada, autenticación y ciclo de vida del personaje.
## Run: Godot --headless --path clients/godot-mmo-client -s tests/unit/test_entry_and_character_lifecycle.gd
## Exit code 0 = todo PASS.

const AS = preload("res://shared-core/AuthLifecycleService.gd")
const EK = preload("res://ui/windows/common/EntryKit.gd")
const T = preload("res://ui/tokens/hud_tokens.gd")
const LauncherScene = preload("res://ui/windows/LauncherWindow/LauncherWindow.tscn")
const LoginScene = preload("res://ui/windows/LoginWindow/LoginWindow.tscn")
const SelectScene = preload("res://ui/windows/CharacterSelectWindow/CharacterSelectWindow.tscn")
const CreateScene = preload("res://ui/windows/CharacterCreationWindow/CharacterCreationWindow.tscn")
const LoadingScene = preload("res://ui/windows/GameLoadingWindow/GameLoadingWindow.tscn")
const SEED := "res://config/auth/auth_lifecycle_seed.json"

const MIN_CHECKS := 350

var _fails: Array[String] = []
var _checks := 0
var _cfg_counter := 0
var _cfg_files: Array[String] = []


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
	print("== [TEST] Paso 15: Entrada, autenticación y ciclo de vida del personaje ==")
	_test_registry()
	await _test_orchestrator()
	_test_launcher_data()
	_test_install()
	_test_login()
	_test_session_persistence()
	_test_accessibility()
	_test_characters()
	_test_delete()
	_test_creation_steps()
	_test_names()
	_test_trial_and_confirm()
	_test_loading()
	await _test_launcher_window()
	await _test_login_window()
	await _test_select_window()
	await _test_create_window()
	await _test_loading_window()
	await _test_full_flow()
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


func _cfg_path() -> String:
	_cfg_counter += 1
	var p := "user://test_entry_lifecycle_%d.cfg" % _cfg_counter
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	_cfg_files.append(p)
	return p


func _svc() -> Node:
	var s: Node = AS.new()
	s.session_path = _cfg_path()
	s.load_seed(SEED)
	s.auto_tick = false
	s.sync_auth_manager = false
	s.tts_enabled = false
	return s


func _same(a: Color, b: Color) -> bool:
	return near(a.r, b.r) and near(a.g, b.g) and near(a.b, b.b) and near(a.a, b.a)


func _key(code: int, ctrl: bool = false, alt: bool = false) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	ev.ctrl_pressed = ctrl
	ev.alt_pressed = alt
	return ev


func _text(n: Node, child: String) -> String:
	var c := n.find_child(child, true, false)
	if c is Label:
		return (c as Label).text
	if c is Button:
		return (c as Button).text
	if c is LineEdit:
		return (c as LineEdit).text
	return ""


func _labels_text(n: Node) -> String:
	var out := ""
	if n is Label:
		out += (n as Label).text + "\n"
	elif n is Button:
		out += (n as Button).text + "\n"
	for c in n.get_children():
		out += _labels_text(c)
	return out


func _fc(l: Control) -> Color:
	return l.get_theme_color("font_color")


func _window(scene: PackedScene, svc: Node, size: Vector2 = Vector2(1440, 810)) -> Control:
	var w: Control = scene.instantiate()
	w.service = svc
	root.add_child(w)
	w.size = size
	await _frames(2)
	return w


# --------------------------------------------------------------------------
# 1. Registro, autoload, espejo y tokens
# --------------------------------------------------------------------------
func _test_registry() -> void:
	print("-- 1. UIWindowRegistry, autoload y tokens")
	var Registry = load("res://ui/orchestration/UIWindowRegistry.gd")
	var UITypes = load("res://ui/types/UITypes.gd")
	var reg: Node = Registry.new()
	check(UITypes.WindowLayer.SYSTEM_MODAL == UITypes.WindowCategory.SYSTEM_MODAL, "WindowLayer.SYSTEM_MODAL es alias de WindowCategory.SYSTEM_MODAL")
	check(UITypes.WindowLayer.TRANSITION == UITypes.WindowCategory.TRANSITION, "WindowLayer.TRANSITION es alias de WindowCategory.TRANSITION")
	check(UITypes.WindowCategory.SYSTEM_MODAL != UITypes.WindowCategory.FULL_SCREEN and UITypes.WindowCategory.TRANSITION != UITypes.WindowCategory.SYSTEM_MODAL, "SYSTEM_MODAL y TRANSITION son categorías nuevas y distintas")
	check(UITypes.WindowCategory.HUD == 0 and UITypes.WindowCategory.FULL_SCREEN == 6, "Las categorías existentes no cambian de valor")
	var expected := [
		["launcher", "res://ui/windows/LauncherWindow/LauncherWindow.tscn", UITypes.WindowLayer.SYSTEM_MODAL, "SYSTEM_MODAL"],
		["login", "res://ui/windows/LoginWindow/LoginWindow.tscn", UITypes.WindowLayer.SYSTEM_MODAL, "SYSTEM_MODAL"],
		["character_select", "res://ui/windows/CharacterSelectWindow/CharacterSelectWindow.tscn", UITypes.WindowLayer.SYSTEM_MODAL, "SYSTEM_MODAL"],
		["character_create", "res://ui/windows/CharacterCreationWindow/CharacterCreationWindow.tscn", UITypes.WindowLayer.SYSTEM_MODAL, "SYSTEM_MODAL"],
		["game_loading", "res://ui/windows/GameLoadingWindow/GameLoadingWindow.tscn", UITypes.WindowLayer.TRANSITION, "TRANSITION"],
	]
	for e in expected:
		var id: String = e[0]
		check(reg.is_registered(id), "Registrada: " + id)
		var meta = reg.get_metadata(id)
		check(meta != null and meta.scene_path == e[1], "%s -> %s" % [id, e[1]])
		check(meta != null and ResourceLoader.exists(meta.scene_path), "La escena de %s existe" % id)
		check(meta != null and meta.category == e[2], "%s es %s" % [id, e[3]])
		check(reg.get_shortcut_keys(id).is_empty(), "%s no declara atajos globales" % id)
	check(reg.get_window_for_key(KEY_N) == "powers" and reg.get_window_for_key(KEY_H) == "shelter", "N y H siguen en Poderes y Refugio")
	reg.free()
	check(str(ProjectSettings.get_setting("autoload/AuthLifecycleService", "")) == "*res://shared-core/AuthLifecycleService.gd", "Autoload AuthLifecycleService registrado")
	var al := root.get_node_or_null("AuthLifecycleService")
	check(al != null and al.characters.size() == 4, "El autoload cargó su seed (4 personajes)")
	var mirror := ProjectSettings.globalize_path("res://").path_join("../shared-core/AuthLifecycleService.gd")
	var a := FileAccess.get_file_as_string("res://shared-core/AuthLifecycleService.gd")
	var b := FileAccess.get_file_as_string(mirror)
	check(a != "" and a == b, "clients/shared-core/AuthLifecycleService.gd sincronizado con el cliente")
	check(FileAccess.file_exists(SEED), "Seed config/auth/auth_lifecycle_seed.json presente")
	check(T.CINEMA_DESIGN_SIZE == Vector2(1440, 810), "Tokens: lienzo canónico 1440×810")
	check(_same(T.ENTRY_PRIMARY, Color("#46e3c1")) and _same(T.ENTRY_PRIMARY_TEXT, Color("#071012")), "Tokens: botón principal #46e3c1 con texto #071012")
	check(_same(T.ENTRY_STEP_DONE, Color("#4fe39a")) and _same(T.ENTRY_STEP_ACTIVE, Color("#46e3c1")) and _same(T.ENTRY_STEP_PENDING, Color("#26333b")), "Tokens: pasos completado / activo / pendiente")
	check(near(T.LOGIN_VEIL.a, 0.62) and near(T.SELECT_VEIL.a, 0.72) and near(T.CREATE_VEIL.a, 0.78), "Tokens: velos 0,62 / 0,72 / 0,78")
	check(T.LOGIN_CARD_WIDTH == 420.0 and T.LOGIN_QR_SIZE == 132.0 and T.SELECT_LIST_WIDTH == 320.0, "Tokens: tarjeta 420 px, QR 132 px y lista 320 px")
	check(T.LOADING_SHADE_HEIGHT == 420.0 and near(T.LOADING_SHADE.a, 0.97), "Tokens: degradado de carga de 420 px a rgba(4,7,9,0.97)")
	check(_same(T.LAUNCHER_CHANGE_IMPROVEMENT, Color("#4fe39a")) and _same(T.LAUNCHER_CHANGE_BALANCE, Color("#f5c35b")) and _same(T.LAUNCHER_CHANGE_NOTE, Color("#9aa6ae")), "Tokens: viñetas de «Qué cambia para ti»")


# --------------------------------------------------------------------------
# 2. UIOrchestrator: apertura, capas y bloqueo de atajos
# --------------------------------------------------------------------------
func _test_orchestrator() -> void:
	print("-- 2. UIOrchestrator y UIInputRouter")
	var orch := root.get_node_or_null("UIOrchestrator")
	var router := root.get_node_or_null("UIInputRouter")
	check(orch != null and router != null, "UIOrchestrator y UIInputRouter disponibles")
	if orch == null:
		return
	var svc := root.get_node("AuthLifecycleService")
	svc.session_path = _cfg_path()
	svc.auto_tick = false
	svc.sync_auth_manager = false
	svc.tts_enabled = false
	svc.load_seed(SEED)
	svc.logged_in = false
	for m in ["open_launcher", "open_login", "open_character_select", "open_character_creation", "open_loading_screen", "is_entry_flow_active"]:
		check(orch.has_method(m), "UIOrchestrator.%s()" % m)
	check(not orch.is_entry_flow_active(), "Sin pantallas de entrada abiertas el flujo no bloquea")
	var l: Node = orch.open_launcher()
	await _frames(2)
	check(l != null and l.visible and orch.is_window_open("launcher"), "open_launcher() abre el Launcher")
	check(l.get_parent() == orch.window_layer, "El Launcher vive en la capa de ventanas")
	check(svc.flow_screen == AS.SCREEN_LAUNCHER, "Abrir el Launcher fija el flujo en «launcher»")
	check(orch.is_entry_flow_active(), "Con el Launcher visible el flujo de entrada está activo")
	check(router.is_entry_flow_blocking(orch), "UIInputRouter bloquea los atajos del mundo durante la entrada")
	var ev := _key(KEY_N)
	check(not router.handle_window_shortcut(ev, orch), "N no abre Poderes con una pantalla de entrada visible")
	check(not orch.is_window_open("powers"), "Poderes sigue cerrado")
	check(orch.is_mouse_over_ui(), "SYSTEM_MODAL bloquea el ratón hacia el mundo")
	var lg: Node = orch.open_login()
	await _frames(1)
	check(lg != null and lg.visible and svc.flow_screen == AS.SCREEN_LOGIN, "open_login() abre el inicio de sesión")
	var cs: Node = orch.open_character_select()
	await _frames(1)
	check(cs != null and cs.visible and svc.flow_screen == AS.SCREEN_SELECT, "open_character_select() abre la selección")
	var cc: Node = orch.open_character_creation()
	await _frames(1)
	check(cc != null and cc.visible and svc.flow_screen == AS.SCREEN_CREATE, "open_character_creation() abre la creación con un borrador nuevo")
	var gl: Node = orch.open_loading_screen({"destination_id": "boveda_ferrum"})
	await _frames(1)
	check(gl != null and gl.visible and svc.flow_screen == AS.SCREEN_LOADING, "open_loading_screen() abre la carga")
	check(str(svc.loading_destination.get("name", "")) == "Bóveda de Ferrum", "open_loading_screen(dest_data) usa el destino pedido")
	var layer: Node = orch.window_layer
	check(gl.get_index() == layer.get_child_count() - 1 or gl.get_index() > cc.get_index(), "La pantalla de carga (TRANSITION) queda encima de todo")
	orch.open_character_select()
	await _frames(1)
	check(gl.get_index() > cs.get_index(), "Reabrir una SYSTEM_MODAL no tapa la TRANSITION (orden del árbol)")
	check(gl.z_index > cs.z_index, "… ni en z_index (la carga se dibuja encima)")
	check(cs.get_index() > l.get_index(), "La SYSTEM_MODAL reabierta pasa delante de las otras de entrada")
	for id in ["launcher", "login", "character_select", "character_create", "game_loading"]:
		orch.close_window(id, true)
	await _frames(2)
	check(not orch.is_entry_flow_active(), "Cerradas las pantallas de entrada se liberan los atajos")
	check(not router.is_entry_flow_blocking(orch), "UIInputRouter vuelve a permitir atajos")


# --------------------------------------------------------------------------
# 3. Launcher: temporada, cambios, servidores, amigos y versión
# --------------------------------------------------------------------------
func _test_launcher_data() -> void:
	print("-- 3. Launcher (datos)")
	var s := _svc()
	check(s.window_title() == "[NOMBRE DEL JUEGO] Launcher", "Título de ventana «[NOMBRE DEL JUEGO] Launcher»")
	check(s.season["caps"] == "Temporada 1 · ya disponible", "Temporada: «Temporada 1 · ya disponible»")
	check(s.season["title"] == "La Brecha de Ferrum", "Temporada: «La Brecha de Ferrum»")
	check(str(s.season["text"]).begins_with("Un universo nuevo"), "Temporada: descripción narrativa")
	check(str(s.season["cover"]).ends_with("mapa-fondo.jpg"), "Temporada: portada")
	check(s.launcher_tabs.size() == 5, "5 pestañas en la barra lateral")
	var labels := []
	for t in s.launcher_tabs:
		labels.append(t["label"])
	check(labels == ["Inicio", "Novedades", "Notas del parche", "Instalación", "Soporte"], "Pestañas: Inicio · Novedades · Notas del parche · Instalación · Soporte")
	check(s.launcher_tab == "home" and s.launcher_tab_label() == "Inicio", "Pestaña inicial: Inicio")
	check(s.set_launcher_tab("install") and s.launcher_tab == "install", "Cambiar a Instalación")
	check(not s.set_launcher_tab("nope") and s.launcher_tab == "install", "Una pestaña inexistente no cambia nada")
	check(s.changes.size() == 3, "«Qué cambia para ti»: 3 puntos")
	var kinds := {"improvement": "#4fe39a", "balance": "#f5c35b", "note": "#9aa6ae"}
	for c in s.changes:
		check(s.change_color(str(c["kind"])) == kinds[c["kind"]], "Viñeta %s en %s" % [c["kind"], kinds[c["kind"]]])
	check(str(s.changes[0]["text"]).contains("Haz de grieta"), "Mejora: Haz de grieta +5 %")
	check(str(s.changes[1]["text"]).contains("Ancla única"), "Balance: tu build «Ancla única»")
	check(str(s.changes[2]["text"]).contains("órdenes del mercado"), "Nota: órdenes del mercado")
	check(s.servers.size() == 3, "3 servidores")
	var exp_lines := {"umbral": "24 ms · estable", "nexo_eu": "140 ms", "nexo_asia": "cola ~3 min"}
	var exp_colors := {"umbral": "#4fe39a", "nexo_eu": "#4fe39a", "nexo_asia": "#f5c35b"}
	for sv in s.servers:
		check(s.server_line(sv) == exp_lines[sv["id"]], "Servidor %s: «%s»" % [sv["name"], exp_lines[sv["id"]]])
		check(s.server_color(sv) == exp_colors[sv["id"]], "Servidor %s: punto %s" % [sv["name"], exp_colors[sv["id"]]])
	check(s.server_label(s.server("umbral")) == "Umbral (tu reino)", "Umbral marcado como «tu reino»")
	check(s.home_server_id() == "umbral" and s.selected_realm == "umbral", "El reino por defecto es Umbral")
	check(s.maintenance.contains("Mantenimiento el jueves"), "Aviso de mantenimiento programado")
	check(s.friends.size() == 3, "3 amigos activos")
	var names := []
	for f in s.friends:
		names.append(f["name"])
	check(names == ["Mira", "Toro", "Brisa"], "Amigos: Mira, Toro y Brisa")
	check(s.friend_color(s.friends[0]) == "#4fe39a" and s.friend_color(s.friends[2]) == "#f5c35b", "Aro verde en línea y ámbar ocupado")
	check(str(s.friends[2]["where"]) == "Bóveda de Ferrum", "Brisa juega en la Bóveda de Ferrum")
	check(s.friends_playing_text() == "4 amigos jugando ahora", "«4 amigos jugando ahora»")
	check(s.account_status_text() == "Llave de acceso activa", "Cuenta: «Llave de acceso activa»")
	check(s.version == "v1.0.4", "Versión del cliente v1.0.4")
	check(s.patch_notes_url.contains("v1.0.4"), "Enlace a las notas completas del parche")
	check(s.footer_status_text() == "Servidores estables · v1.0.4", "Pie: «Servidores estables · v1.0.4»")
	s.free()


func _test_install() -> void:
	print("-- 3b. Instalación progresiva y «Jugar ahora»")
	var s := _svc()
	check(s.download_line() == "Actualizando · 18,4 de 42 GB · 48 MB/s · 9 min", "Línea de descarga idéntica al HTML")
	var exp := ["Núcleo ✓", "Nexo ✓", "Verdalia ✓", "Ferrum 40 %", "Runavell en cola"]
	for i in s.packs.size():
		check(s.pack_label(s.packs[i]) == exp[i], "Paquete %d: «%s»" % [i, exp[i]])
	check(s.pack_fill_color(s.packs[0]) == "#46e3c1" and s.pack_fill_color(s.packs[3]) == "#5aa9ff" and s.pack_fill_color(s.packs[4]) == "#f5b546", "Barra: hecho #46e3c1 · bajando #5aa9ff · en cola #f5b546")
	check(s.pack_color(s.packs[3]) == "#5aa9ff" and s.pack_color(s.packs[4]) == "#7c8992", "Etiquetas: Ferrum azul y Runavell gris")
	check(s.can_play(), "Con Núcleo, Nexo y Verdalia ya se puede jugar")
	check(not s.install_complete(), "La instalación aún no está completa")
	check(s.play_hint() == "Ferrum y Runavell se terminan de bajar mientras juegas", "«Ferrum y Runavell se terminan de bajar mientras juegas»")
	check(near(s.install_ratio(), (2 + 1 + 2 + 0.8) / 9.0, 0.001), "Progreso total ponderado por paquete")
	s.tick(60.0)
	check(near(float(s.packs[3]["progress"]), 0.4 + 2.8125 / (42.0 * 2.0 / 9.0), 0.001), "1 min a 48 MB/s avanza Ferrum")
	check(near(float(s.download["done_gb"]), 18.4 + 2.8125, 0.001), "GB descargados actualizados")
	check(float(s.packs[4]["progress"]) == 0.0, "Runavell sigue en cola")
	s.toggle_install_pause()
	var before := float(s.packs[3]["progress"])
	s.tick(60.0)
	check(near(float(s.packs[3]["progress"]), before), "En pausa no avanza")
	check(s.download_line().begins_with("En pausa"), "Línea «En pausa»")
	s.toggle_install_pause()
	check(s.toggle_limit_while_playing() == false and s.toggle_limit_while_playing() == true, "«Limitar mientras juego» se alterna")
	s.tick(3600.0)
	check(s.install_complete() and near(float(s.download["done_gb"]), 42.0), "Tras 1 h todo instalado")
	check(s.pack_label(s.packs[4]) == "Runavell ✓", "Runavell ✓")
	check(s.play_hint() == "Todo listo para jugar", "«Todo listo para jugar»")
	check(s.download_line().begins_with("Todo instalado"), "Línea «Todo instalado»")
	var s2 := _svc()
	s2.packs[1]["progress"] = 0.5
	check(not s2.can_play(), "Si falta un paquete imprescindible no se puede jugar")
	check(s2.play()["code"] == "install_required", "play() avisa de lo que falta")
	s2.packs[1]["progress"] = 1.0
	s2.packs[0]["corrupt"] = true
	var r: Dictionary = s2.verify_integrity()
	check(r["ok"] and r["repaired"] == ["Núcleo"], "Comprobar integridad repara Núcleo")
	check(str(r["text"]).begins_with("Reparados: Núcleo"), "Resultado legible de la reparación")
	var r2: Dictionary = s2.verify_integrity()
	check(r2["repaired"].is_empty() and r2["checked"] == 4 and r2["text"] == "Integridad verificada · 4 paquetes correctos", "Segunda comprobación: 4 paquetes correctos")
	var flows := []
	s2.flow_changed.connect(func(sc: String) -> void: flows.append(sc))
	var p: Dictionary = s2.play()
	check(p["ok"] and p["screen"] == AS.SCREEN_LOGIN and s2.flow_screen == AS.SCREEN_LOGIN, "«Jugar ahora» sin sesión lleva al inicio de sesión")
	check(flows == [AS.SCREEN_LOGIN], "flow_changed(login)")
	check(not s2.go_to("nowhere"), "go_to rechaza pantallas desconocidas")
	s.free()
	s2.free()


# --------------------------------------------------------------------------
# 4. Login
# --------------------------------------------------------------------------
func _test_login() -> void:
	print("-- 4. Inicio de sesión")
	var s := _svc()
	var fails := []
	s.login_failed.connect(func(c: String, _m: String) -> void: fails.append(c))
	var r: Dictionary = s.login_with_passkey()
	check(r["ok"] and r["method"] == AS.METHOD_PASSKEY, "Entrar con llave de acceso")
	check(s.logged_in and s.auth_method == "passkey" and s.account_name == "Tu cuenta", "Sesión iniciada con la llave")
	check(s.flow_screen == AS.SCREEN_SELECT, "Tras iniciar sesión pasa a la selección")
	s.logout()
	check(not s.logged_in and s.flow_screen == AS.SCREEN_LOGIN, "Cerrar sesión vuelve al login")
	s.login_cfg["passkey_registered"] = false
	check(s.login_with_passkey()["code"] == "no_passkey", "Sin llave registrada no entra")
	check(s.account_status_text() == "Sin llave de acceso", "La cuenta muestra «Sin llave de acceso»")
	s.login_cfg["passkey_registered"] = true
	# QR
	var codes := []
	s.qr_refreshed.connect(func(c: String) -> void: codes.append(c))
	var code: String = s.start_qr_login()
	check(code.begins_with("UMB-") and code.length() == 10, "Código QR «UMB-XXXXXX»")
	check(near(s.qr_remaining, 120.0) and not s.qr_expired(), "El QR dura 120 s")
	var m: Array = s.qr_matrix()
	check(m.size() == 81, "Matriz QR 9×9")
	check(m[0] and m[1] and m[2] and not m[10] and m[8] and m[72], "Marcas de esquina del QR")
	check(s.qr_matrix(code) == m and s.qr_matrix("UMB-OTHER1") != m, "La matriz depende del código y es determinista")
	check(s.confirm_qr_from_mobile("UMB-NOPE00")["code"] == "qr_mismatch", "Un código ajeno no inicia sesión")
	s.tick(119.0)
	check(not s.qr_expired(), "A los 119 s el QR sigue vivo")
	s.tick(2.0)
	check(codes.size() == 2 and s.qr_code != code and s.qr_generation == 2, "Al caducar el QR se renueva solo")
	s.qr_auto_refresh = false
	var c2: String = s.qr_code
	s.tick(121.0)
	check(s.qr_expired() and s.confirm_qr_from_mobile(c2)["code"] == "qr_expired", "Sin renovación, el QR caducado no sirve")
	var c3: String = s.start_qr_login()
	var q: Dictionary = s.confirm_qr_from_mobile(c3)
	check(q["ok"] and s.auth_method == AS.METHOD_QR, "La app móvil confirma el QR («Entrar en el PC»)")
	check(s.qr_code == "", "El QR usado se invalida")
	s.logout()
	# Correo y contraseña
	check(s.login_with_credentials("no-es-correo", "brecha-2026")["code"] == "invalid_email", "Correo inválido")
	check(s.login_with_credentials("jugador@umbral.test", "corta")["code"] == "short_password", "Contraseña corta")
	check(s.failed_attempts == 0, "Los errores de formato no cuentan como intento")
	var bad: Dictionary = s.login_with_credentials("jugador@umbral.test", "incorrecta1")
	check(bad["code"] == "bad_credentials" and str(bad["message"]).contains("4 intentos restantes"), "Credenciales incorrectas: quedan 4 intentos")
	s.login_with_credentials("jugador@umbral.test", "incorrecta2")
	s.login_with_credentials("jugador@umbral.test", "incorrecta3")
	var b4: Dictionary = s.login_with_credentials("jugador@umbral.test", "incorrecta4")
	check(str(b4["message"]).contains("1 intento restante"), "Cuarto fallo: 1 intento restante")
	var b5: Dictionary = s.login_with_credentials("jugador@umbral.test", "incorrecta5")
	check(b5["code"] == "locked" and s.is_locked() and near(s.lockout_remaining, 30.0), "Quinto fallo: bloqueo de 30 s")
	check(s.login_with_credentials("jugador@umbral.test", "brecha-2026")["code"] == "locked", "Bloqueado incluso con la contraseña correcta")
	check(s.login_with_passkey()["ok"], "La llave de acceso sigue disponible durante el bloqueo")
	s.logout()
	s.tick(30.0)
	check(not s.is_locked() and s.failed_attempts == 0, "Tras 30 s se desbloquea")
	var ok: Dictionary = s.login_with_credentials("  JUGADOR@umbral.test ", "brecha-2026")
	check(ok["ok"] and s.auth_method == AS.METHOD_CREDENTIALS, "Correo sin distinguir mayúsculas ni espacios")
	check(fails.has("no_passkey") and fails.has("locked") and fails.has("qr_mismatch"), "login_failed emite los códigos")
	check(s.last_login_error.is_empty(), "Un acceso correcto limpia el error")
	# Reino
	check(s.realm_line() == "24 ms · sin cola", "Reino Umbral: «24 ms · sin cola»")
	check(s.select_realm("nexo_asia") and s.realm_line() == "cola ~3 min", "Nexo Asia: «cola ~3 min»")
	check(not s.select_realm("marte"), "Reino inexistente rechazado")
	s.select_realm("umbral")
	check(s.realm_header() == "Reino Umbral · Español · 24 ms · población alta", "Cabecera de reino de la selección")
	s.free()


func _test_session_persistence() -> void:
	print("-- 4b. «Mantener la sesión en este equipo»")
	var s := _svc()
	check(s.keep_session, "Mantener la sesión viene marcado")
	s.select_realm("nexo_eu")
	s.login_with_passkey()
	check(s.has_saved_session(), "La sesión se guarda en el equipo")
	var s2: Node = AS.new()
	s2.session_path = s.session_path
	s2.load_seed(SEED)
	s2.auto_tick = false
	check(not s2.logged_in, "Un cliente nuevo arranca sin sesión")
	var p: Dictionary = s2.play()
	check(p["screen"] == AS.SCREEN_SELECT and s2.logged_in and s2.auth_method == AS.METHOD_SESSION, "«Jugar ahora» con sesión guardada va directo a la selección")
	check(s2.selected_realm == "nexo_eu", "Se recuerda el reino")
	s.set_keep_session(false)
	check(not s.has_saved_session(), "Desmarcar borra la sesión guardada")
	s.set_keep_session(true)
	check(s.has_saved_session(), "Volver a marcar la guarda")
	s.logout(true)
	check(not s.has_saved_session(), "Cerrar sesión la olvida")
	var s3 := _svc()
	s3.keep_session = false
	s3.login_with_passkey()
	check(not s3.has_saved_session(), "Sin «Mantener la sesión» no se guarda nada")
	s.free()
	s2.free()
	s3.free()


# --------------------------------------------------------------------------
# 5. Accesibilidad previa al ingreso
# --------------------------------------------------------------------------
func _test_accessibility() -> void:
	print("-- 5. Accesibilidad previa")
	var s := _svc()
	var said := []
	s.narrated.connect(func(t: String) -> void: said.append(t))
	var changed := [0]
	s.accessibility_changed.connect(func() -> void: changed[0] += 1)
	check(s.font_step == 1 and near(s.font_scale(), 1.0), "Tamaño A por defecto")
	check(AS.FONT_STEP_LABELS == ["A−", "A", "A+"], "Botones A− · A · A+")
	check(s.font_larger() and near(s.font_scale(), 1.16), "A+ agranda la letra")
	check(not s.font_larger(), "No pasa de A+")
	check(s.font_smaller() and s.font_smaller() and near(s.font_scale(), 0.88), "A− la reduce")
	check(not s.font_smaller() and s.font_step == 0, "No baja de A−")
	check(changed[0] == 3, "accessibility_changed por cada cambio real")
	check(said.is_empty(), "Con el narrador apagado no se lee nada")
	check(s.toggle_high_contrast() and near(s.veil_alpha(0.62), 0.82) and s.secondary_text_color() == "#eef2f4", "Alto contraste: velo más opaco y texto secundario claro")
	check(not s.toggle_high_contrast() and near(s.veil_alpha(0.62), 0.62), "Se desactiva")
	check(near(s.veil_alpha(0.78) if not s.high_contrast else 0.0, 0.78), "Sin alto contraste el velo es el del diseño")
	check(s.toggle_narrator() and said == ["Narrador activado"], "Narrador: «Narrador activado»")
	check(s.announce("Hola") and s.announcements[-1] == "Hola", "announce() lee con el narrador activo")
	s.set_font_step(1)
	check(said.has("Tamaño de letra A"), "El narrador anuncia los cambios de accesibilidad")
	check(not s.toggle_narrator() and said[-1] == "Narrador desactivado", "Al apagarlo dice «Narrador desactivado»")
	check(not s.announce("Silencio"), "Apagado no lee")
	check(s.colorblind_mode == "none" and s.colorblind_label() == "Daltonismo", "Daltonismo desactivado por defecto")
	var seq := []
	for i in 4:
		seq.append(s.cycle_colorblind_mode())
	check(seq == ["protanopia", "deuteranopia", "tritanopia", "none"], "Ciclo Protanopia → Deuteranopia → Tritanopia → ninguno")
	check(not s.set_colorblind_mode("acromatopsia"), "Modo desconocido rechazado")
	for mode in AS.COLORBLIND_MODES:
		s.set_colorblind_mode(mode)
		var pal: Dictionary = s.palette()
		check(pal.has("good") and pal.has("warn") and pal["good"] != pal["warn"], "Paleta %s distingue bien / aviso" % mode)
	s.set_colorblind_mode("deuteranopia")
	check(s.colorblind_label() == "Deuteranopia", "Etiqueta «Deuteranopia»")
	check(s.change_color("improvement") == "#5aa9ff" and s.server_color(s.server("nexo_asia")) == "#ffb347", "Con deuteranopia el verde pasa a azul y el ámbar a naranja")
	check(s.change_color("note") == "#9aa6ae", "Las notas neutras no cambian")
	s.set_colorblind_mode("protanopia")
	check(s.status_color("bad") == "#c88a2b", "Protanopia: rojo sustituido")
	s.set_high_contrast(true)
	s.set_font_step(2)
	var s2: Node = AS.new()
	s2.session_path = s.session_path
	s2.load_seed(SEED)
	check(s2.load_preferences(), "Las preferencias se guardan aunque no inicies sesión")
	check(s2.font_step == 2 and s2.high_contrast and s2.colorblind_mode == "protanopia", "Se recuperan A+, alto contraste y protanopia")
	# EntryKit aplica la escala y el contraste a toda la pantalla.
	var box := VBoxContainer.new()
	var l1 := Label.new()
	l1.add_theme_font_size_override("font_size", 20)
	l1.add_theme_color_override("font_color", T.TEXT_SECONDARY)
	box.add_child(l1)
	var b1 := Button.new()
	b1.add_theme_font_size_override("font_size", 14)
	box.add_child(b1)
	EK.apply_accessibility(box, s)
	check(l1.get_theme_font_size("font_size") == 23 and b1.get_theme_font_size("font_size") == 16, "A+ escala etiquetas y botones (20→23, 14→16)")
	check(_same(_fc(l1), T.TEXT), "Alto contraste aclara el texto secundario")
	s.set_font_step(0)
	s.set_high_contrast(false)
	EK.apply_accessibility(box, s)
	check(l1.get_theme_font_size("font_size") == 18 and _same(_fc(l1), T.TEXT_SECONDARY), "Sin acumular: A− parte del tamaño base (20→18) y el color vuelve")
	l1.add_theme_color_override("font_color", Color("#ff8a8a"))
	EK.apply_accessibility(box, s)
	check(_same(_fc(l1), Color("#ff8a8a")), "Un color cambiado por código se respeta como nuevo base")
	box.free()
	s.free()
	s2.free()


# --------------------------------------------------------------------------
# 6. Selección de personaje
# --------------------------------------------------------------------------
func _test_characters() -> void:
	print("-- 6. Selección de personaje")
	var s := _svc()
	var ids := []
	for c in s.characters:
		ids.append(c["id"])
	check(ids == ["kael", "ysolde", "torq", "aurel"], "Orden: Kael, Ysolde, Torq y Aurel (especial al final)")
	check(s.selected_character_id == "kael", "Kael seleccionado al entrar (el más reciente)")
	var exp := {
		"kael": ["Kael", "32", "Tejedor de grietas", "Verdalia · hace 2 días", "#9fe36a", "Tejedor de grietas · nivel 32 · nivel de objeto 412"],
		"ysolde": ["Ysolde", "18", "Guardiana rúnica", "Runavell · hace 1 semana", "#f5b546", "Guardiana rúnica · nivel 18 · nivel de objeto 240"],
		"torq": ["Torq", "45", "Herrero de Ferrum", "Ferrum · hace 3 semanas", "#5aa9ff", "Herrero de Ferrum · nivel 45 · nivel de objeto 455"],
		"aurel": ["Aurel", "", "Narrador · personaje especial", "Asignado por el equipo · 27 días", "#f5c35b", "Narrador · personaje especial · 27 días restantes"],
	}
	for id in exp:
		var c: Dictionary = s.character(id)
		var e: Array = exp[id]
		check(c["name"] == e[0], "%s: nombre" % e[0])
		check(s.character_level_text(c) == e[1], "%s: nivel «%s»" % [e[0], e[1]])
		check(s.character_subtitle(c) == e[2], "%s: «%s»" % [e[0], e[2]])
		check(s.character_meta_line(c) == e[3], "%s: «%s»" % [e[0], e[3]])
		check(s.character_color(c) == e[4], "%s: color %s" % [e[0], e[4]])
		check(s.character_detail_line(c) == e[5], "%s: línea de detalle" % e[0])
	check(bool(s.character("aurel")["special"]) and not bool(s.character("kael")["special"]), "Aurel es personaje especial (Anexo F)")
	check(s.max_slots == 6 and s.used_slots() == 4 and s.free_slots() == 2, "6 ranuras, 4 usadas")
	check(s.free_slots_text() == "2 espacios libres", "«2 espacios libres»")
	for d in [[0, "hoy"], [1, "ayer"], [3, "hace 3 días"], [7, "hace 1 semana"], [14, "hace 2 semanas"], [30, "hace 1 mes"], [95, "hace 3 meses"]]:
		check(s.last_played_text(d[0]) == d[1], "Última vez: %d días → «%s»" % d)
	var sel := []
	s.character_selected.connect(func(id: String) -> void: sel.append(id))
	check(s.select_character("torq") and s.selected_character()["name"] == "Torq", "Seleccionar a Torq")
	check(not s.select_character("nadie") and s.selected_character_id == "torq", "Un id desconocido no cambia la selección")
	check(s.select_offset(1) and s.selected_character_id == "aurel", "Carrusel: siguiente → Aurel")
	check(s.select_offset(1) and s.selected_character_id == "kael", "El carrusel es circular")
	check(s.select_offset(-1) and s.selected_character_id == "aurel", "Carrusel: anterior")
	check(sel == ["torq", "aurel", "kael", "aurel"], "character_selected en cada cambio")
	s.select_character("kael")
	var rows: Array = s.character_stats_rows(s.selected_character())
	check(rows.size() == 5, "Kael: 5 estadísticas básicas")
	check(rows[0]["value"] == "32" and rows[1]["value"] == "412" and rows[2]["value"] == "4.820", "Nivel 32, nivel de objeto 412, vida 4.820")
	var ar: Array = s.character_stats_rows(s.character("aurel"))
	check(ar.size() == 3 and ar[0]["value"] == "Narrador" and ar[2]["value"] == "no hace daño", "Aurel: plantilla Narrador y no hace daño")
	check(s.continue_info()["title"] == "Sellar la grieta menor · 2/3", "«Continúa donde lo dejaste»: Sellar la grieta menor · 2/3")
	check(s.continue_info()["text"] == "Vado Roto, Verdalia · 40 m de tu posición", "Ubicación de la misión pendiente")
	check(s.away.size() == 4 and s.away[0]["title"] == "Tu refugio tiene 5 cosas listas", "«Mientras no estabas»: 4 avisos")
	check(s.nest_ready == 5, "El Nido con 5 cosas listas")
	check(AS.fmt_int(4820) == "4.820" and AS.fmt_int(1234567) == "1.234.567" and AS.fmt_int(-5000) == "-5.000" and AS.fmt_int(12) == "12", "Formato de miles con punto")
	check(AS.fmt_dec(18.4) == "18,4" and AS.fmt_dec(42.0) == "42", "Formato decimal con coma")
	check(AS.fmt_clock(300) == "5:00" and AS.fmt_clock(61.2) == "1:02", "Formato de reloj")
	check(s.enter_world()["code"] == "not_logged_in", "Sin sesión no se entra al mundo")
	s.login_with_passkey()
	var entries := []
	s.world_entry_requested.connect(func(c: Dictionary, d: Dictionary) -> void: entries.append([c["id"], d["destination_id"]]))
	s.select_character("ysolde")
	var r: Dictionary = s.enter_world()
	check(r["ok"] and r["destination"]["name"] == "Puerto de Runavell", "Ysolde entra en el Puerto de Runavell")
	check(s.flow_screen == AS.SCREEN_LOADING and s.loading_active, "Entrar al mundo abre la carga")
	check(entries == [["ysolde", "puerto_runavell"]], "world_entry_requested(personaje, destino)")
	check(int(s.character("ysolde")["last_played_days"]) == 0, "Ysolde queda como jugada hoy")
	check(s.last_world_entry["character"]["id"] == "ysolde", "last_world_entry guarda la entrada")
	s.free()


func _test_delete() -> void:
	print("-- 6b. Borrar personaje con nombre tecleado")
	var s := _svc()
	var deleted := []
	s.character_deleted.connect(func(id: String) -> void: deleted.append(id))
	var ra: Dictionary = s.request_delete("aurel")
	check(not ra["ok"] and ra["code"] == "special", "Aurel (especial) no se puede borrar")
	check(not s.can_delete("aurel") and s.can_delete("torq"), "can_delete distingue especiales")
	check(s.request_delete("nadie")["code"] == "not_found", "Personaje inexistente")
	check(s.confirm_delete("Torq")["code"] == "no_request", "Sin petición previa no se borra")
	var r: Dictionary = s.request_delete("torq")
	check(r["ok"] and r["prompt"] == "ESCRIBE EL NOMBRE PARA CONFIRMAR", "Petición: «ESCRIBE EL NOMBRE PARA CONFIRMAR»")
	check(not s.delete_confirm_matches("torq") and not s.delete_confirm_matches("Tor"), "El nombre debe coincidir exactamente")
	check(s.delete_confirm_matches(" Torq "), "Se ignoran espacios a los lados")
	check(s.confirm_delete("TORQ")["code"] == "name_mismatch" and s.characters.size() == 4, "Nombre en mayúsculas: no borra")
	check(s.confirm_delete("Torq")["ok"] and s.characters.size() == 3 and s.character("torq").is_empty(), "Torq borrado")
	check(deleted == ["torq"] and s.free_slots() == 3, "character_deleted y 3 espacios libres")
	check(s.selected_character_id == "kael", "La selección se mantiene en Kael")
	s.select_character("ysolde")
	s.request_delete()
	s.confirm_delete("Ysolde")
	check(s.selected_character_id == "aurel", "Al borrar el seleccionado pasa al siguiente")
	s.request_delete("kael")
	s.cancel_delete()
	check(s.pending_delete_id == "" and s.character("kael").size() > 0, "Cancelar no borra")
	s.free()


# --------------------------------------------------------------------------
# 7. Creación en 4 pasos
# --------------------------------------------------------------------------
func _test_creation_steps() -> void:
	print("-- 7. Creación: pasos, orígenes, clases y apariencia")
	var s := _svc()
	check(s.origins.size() == 4, "4 orígenes")
	var exp := {"verdalia": ["Verdalia", "Savia", "#4fe39a"], "ferrum": ["Ferrum", "Hierro", "#b8c3ca"], "runavell": ["Runavell", "Runa", "#f5b546"], "umbral": ["Umbral", "Vacío", "#b47bff"]}
	for id in exp:
		var o: Dictionary = s.origin(id)
		check(o["name"] == exp[id][0] and o["energy"] == exp[id][1] and o["energy_color"] == exp[id][2], "Origen %s: afinidad %s %s (Anexo B)" % exp[id])
	check(s.classes.size() == 6, "6 clases jugables")
	var cls := {
		"rift_weaver": ["Tejedor de grietas", "Daño", "distancia", false],
		"rune_guardian": ["Guardiana rúnica", "Tanque", "cuerpo a cuerpo", true],
		"wandering_druid": ["Druida errante", "Sanador", "área", false],
		"shadow_blade": ["Hoja de sombra", "Asesino", "cuerpo a cuerpo", false],
	}
	for id in cls:
		var c: Dictionary = s.class_data(id)
		var e: Array = cls[id]
		check(c["name"] == e[0], "Clase %s" % e[0])
		check(s.role_label(str(c["role"])) == e[1], "%s: rol %s" % [e[0], e[1]])
		check(c["range"] == e[2], "%s: alcance %s" % [e[0], e[2]])
		check(bool(c.get("recommended", false)) == e[3], "%s: recomendada = %s" % [e[0], str(e[3])])
		check((c["ratings"] as Dictionary).size() == 4 and str(c["style"]) != "", "%s: estilo y 4 puntuaciones" % e[0])
	check(s.recommended_class_id() == "rune_guardian", "Guardiana rúnica, recomendada para empezar")
	check(s.role_color("damage") == "#8a3a2b" and s.role_color("tank") == "#2b4a8a" and s.role_color("healer") == "#2a7a4a", "Colores de rol del HTML")
	check(s.begin_creation()["ok"] and s.flow_screen == AS.SCREEN_CREATE, "Empezar la creación")
	check(s.creation_step == 0 and s.draft["origin"] == "verdalia" and s.draft["class_id"] == "", "Borrador: Verdalia, sin clase")
	var st: Array = s.step_states()
	check(st.size() == 4 and st[0]["state"] == "active" and st[1]["state"] == "pending", "Paso 1 activo, resto pendiente")
	check(st[0]["label"] == "Origen" and st[3]["label"] == "Nombre", "Pasos: Origen · Clase · Apariencia · Nombre")
	check(s.primary_action_label() == "Siguiente: clase", "Botón «Siguiente: clase»")
	check(not s.set_origin("marte") and s.set_origin("ferrum") and s.draft["origin"] == "ferrum", "Elegir origen Ferrum")
	check(s.next_step() and s.creation_step == 1, "Avanzar a Clase")
	check(s.primary_action_label() == "Siguiente: apariencia", "Botón «Siguiente: apariencia»")
	check(not s.can_advance() and not s.next_step(), "Sin clase no avanza")
	check(not s.set_class("narrator"), "El Narrador no es una clase elegible")
	check(s.set_class("rift_weaver") and s.next_step() and s.creation_step == 2, "Con clase pasa a Apariencia")
	st = s.step_states()
	check(st[0]["state"] == "done" and st[1]["state"] == "done" and st[2]["state"] == "active" and st[3]["state"] == "pending", "Origen y Clase completados")
	check(s.goto_step(0) and s.creation_step == 0, "Volver a un paso visitado")
	st = s.step_states()
	check(st[0]["state"] == "active" and st[1]["state"] == "done" and st[2]["state"] == "done", "Los pasos visitados siguen completados")
	check(not s.goto_step(3), "No se salta a un paso no visitado")
	s.goto_step(2)
	for k in AS.APPEARANCE_KEYS:
		check(s.appearance_count(k) >= 3, "Apariencia «%s»: %d opciones" % [s.appearance_label(k), s.appearance_count(k)])
	check(s.appearance_label("hair_color") == "Color de pelo" and s.appearance_label("outfit") == "Atuendo inicial", "Etiquetas de apariencia")
	check(s.cycle_appearance("hair_color", 1) == 1 and s.appearance_option("hair_color")["name"] == "Cobre", "Pelo → Cobre")
	check(s.cycle_appearance("hair_color", -2) == 5 and s.appearance_option("hair_color")["name"] == "Cian", "El ciclo da la vuelta (Cian)")
	check(not s.set_appearance("eye_color", 99) and s.set_appearance("eye_color", 3), "Índice fuera de rango rechazado")
	var col: Dictionary = s.appearance_colors()
	check(col["body"] == "#8a3a2b" and col["hair"] == "#46e3c1" and col["eyes"] == "#2b4a8a", "Chibi: cuerpo del color de la clase, pelo cian, ojos azules")
	s.set_appearance("outfit", 1)
	check(s.appearance_colors()["body"] == "#5d6d77", "El atuendo «Cota ligera» cambia el cuerpo")
	s.set_appearance("body", 2)
	check(near(float(s.appearance_colors()["scale"]), 1.12), "Cuerpo robusto")
	var a1: Dictionary = (s.randomize_appearance(42) as Dictionary).duplicate()
	var a2: Dictionary = (s.randomize_appearance(42) as Dictionary).duplicate()
	check(a1 == a2, "Aleatorio con semilla es reproducible")
	check(s.next_step() and s.creation_step == 3 and s.primary_action_label() == "Confirmar creación", "Paso 4: «Confirmar creación»")
	check(s.traits.size() == 4, "4 rasgos cósmicos iniciales")
	check(not s.set_trait("nada") and s.set_trait("persistent_echo"), "Elegir rasgo «Eco persistente»")
	check(s.trait_data("threshold_spark")["energy"] == "Vacío", "Rasgo con energía del Anexo B")
	check(not s.can_advance(), "Sin nombre válido no se confirma")
	s.set_draft_name("Vaelis")
	check(s.can_advance(), "Nombre válido + rasgo: listo para confirmar")
	check(not s.next_step(), "No hay paso 5")
	check(s.prev_step() and s.creation_step == 2, "Atrás desde el paso 4")
	s.cancel_creation()
	check(s.flow_screen == AS.SCREEN_SELECT and s.draft["class_id"] == "", "Cancelar descarta el borrador y vuelve a la selección")
	s.free()


func _test_names() -> void:
	print("-- 7b. Validación estricta de nombre")
	var s := _svc()
	var cases := [
		["", "empty"], ["   ", "empty"], ["Al", "too_short"], ["Ana", "ok"], ["Abcdefghijklmnop", "ok"],
		["Abcdefghijklmnopq", "too_long"], ["Kael Dos", "invalid_chars"], ["Kaël", "invalid_chars"], ["Rin-Ko", "invalid_chars"],
		["Ñandú", "ok"], ["Lyra2", "ok"], ["9Lives", "starts_with_digit"], ["Pendejo99", "profanity"],
		["Id1ota", "profanity"], ["XxMierdaxX", "profanity"], ["Admin", "reserved"], ["Nexo", "reserved"],
		["Mira", "taken"], ["mira", "taken"], ["MÍRA", "taken"], ["Kael", "taken"], ["Torq", "taken"], ["Vaelis", "ok"],
		["Ysolde2", "ok"], ["Aurel", "taken"], ["Sasha", "taken"],
	]
	for c in cases:
		var v: Dictionary = s.validate_name(c[0])
		check(v["code"] == c[1], "Nombre «%s» → %s" % c)
	check(s.validate_name("Al")["message"] == "Mínimo 3 caracteres", "Mensaje «Mínimo 3 caracteres»")
	check(s.validate_name("Abcdefghijklmnopq")["message"] == "Máximo 16 caracteres", "Mensaje «Máximo 16 caracteres»")
	check(s.validate_name("Vaelis")["message"] == "Disponible ✓", "Mensaje «Disponible ✓»")
	check(s.validate_name("  Vaelis ")["name"] == "Vaelis", "Se recortan los espacios de los lados")
	check(s.suggest_name("Mira") == "Mira2" and s.suggest_name("Kael") == "Kael2", "Sugerencia para nombres ocupados")
	check(s.suggest_name("Abcdefghijklmnop").length() == 16, "La sugerencia respeta el máximo de 16")
	check(s.is_name_available("Vaelis") and not s.is_name_available("brisa"), "Disponibilidad en el servidor")
	s.free()


func _test_trial_and_confirm() -> void:
	print("-- 7c. Maniquí (5 min) y confirmación")
	var s := _svc()
	var events := []
	s.trial_started.connect(func(c: String) -> void: events.append("start:" + c))
	s.trial_finished.connect(func(c: String) -> void: events.append("end:" + c))
	s.begin_creation()
	check(s.try_dummy()["code"] == "no_class", "Sin clase no hay maniquí")
	check(s.try_dummy("narrator")["code"] == "no_class", "El Narrador no se prueba")
	check(s.trial_button_text() == "Probar en el maniquí (5 min)", "Botón «Probar en el maniquí (5 min)»")
	var r: Dictionary = s.try_dummy("shadow_blade")
	check(r["ok"] and near(float(r["duration_s"]), 300.0) and r["arena"] == "Arena del maniquí", "Maniquí de 5 minutos con Hoja de sombra")
	check(s.trial_active and s.trial_class_id == "shadow_blade", "Prueba en curso")
	s.tick(100.0)
	check(s.trial_button_text() == "En el maniquí · 3:20", "Quedan 3:20")
	s.tick(200.0)
	check(not s.trial_active and events == ["start:shadow_blade", "end:shadow_blade"], "La prueba termina sola a los 5 min")
	# Confirmar
	s.set_origin("umbral")
	s.next_step()
	s.set_class("wandering_druid")
	s.next_step()
	s.next_step()
	s.set_trait("deep_root")
	s.set_draft_name("Mira")
	var bad: Dictionary = s.confirm_creation()
	check(not bad["ok"] and bad["message"] == "Ya existe un personaje con ese nombre", "No confirma con nombre ocupado")
	s.set_draft_name("Vaelis")
	var created := []
	s.character_created.connect(func(c: Dictionary) -> void: created.append(c["id"]))
	var ok: Dictionary = s.confirm_creation()
	check(ok["ok"], "Confirmar creación")
	var c: Dictionary = ok["character"]
	check(c["name"] == "Vaelis" and c["level"] == 1 and c["class_id"] == "wandering_druid" and c["origin"] == "umbral", "Vaelis, Druida errante de Umbral, nivel 1")
	check(c["trait_id"] == "deep_root" and (c["appearance"] as Dictionary).size() == 5, "Guarda rasgo y apariencia")
	check(s.characters.size() == 5 and s.characters[0]["id"] == c["id"], "Aparece la primera (jugada hoy)")
	check(s.selected_character_id == c["id"] and created == [c["id"]], "Queda seleccionada y se emite character_created")
	check(s.free_slots() == 1 and s.flow_screen == AS.SCREEN_SELECT, "1 espacio libre y vuelta a la selección")
	check(s.character_meta_line(c) == "Umbral · hoy", "«Umbral · hoy»")
	check(c["continue"]["destination"] == "vado_roto", "Su primer destino sale del origen")
	check(s.draft["name"] == "" and s.creation_step == 0, "El borrador se reinicia")
	check(s.validate_name("Vaelis")["code"] == "taken", "Su nombre ya está ocupado")
	s.begin_creation()
	s.next_step()
	s.set_class("engineer")
	s.next_step()
	s.next_step()
	s.set_trait("steady_pulse")
	s.set_draft_name("Ingrid")
	check(s.confirm_creation()["ok"] and s.free_slots() == 0, "Sexta ranura ocupada")
	check(s.free_slots_text() == "sin espacios libres", "«sin espacios libres»")
	check(s.begin_creation()["code"] == "no_slots", "Sin ranuras no se puede crear")
	var s2 := _svc()
	s2.begin_creation()
	var inc: Dictionary = s2.confirm_creation()
	check(not inc["ok"] and inc["code"] == "step_1", "Confirmar un borrador incompleto indica el paso pendiente")
	s.free()
	s2.free()


# --------------------------------------------------------------------------
# 8. Pantalla de carga táctica
# --------------------------------------------------------------------------
func _test_loading() -> void:
	print("-- 8. Pantalla de carga táctica")
	var s := _svc()
	var prog := []
	var done := []
	s.loading_progressed.connect(func(p: float) -> void: prog.append(p))
	s.loading_finished.connect(func(d: Dictionary) -> void: done.append(d["destination_id"]))
	var d: Dictionary = s.begin_loading()
	check(d["destination_id"] == "vado_roto" and d["name"] == "Vado Roto", "Destino por defecto: Vado Roto")
	check(d["universe"] == "Verdalia" and s.loading_subtitle() == "Verdalia · tu objetivo: derrota al Guardián del Umbral", "«Verdalia · tu objetivo: derrota al Guardián del Umbral»")
	check(d["quote"] == "El vado no se rompió: lo partieron desde el otro lado." and d["quote_source"] == "Diario de Mira, día 12", "Cita de lore del Diario de Mira")
	var tips: Array = s.loading_tips()
	check(tips.size() == 3, "3 consejos tácticos")
	check(str(tips[0]["text"]).begins_with("A los 8 s abre una Grieta") and tips[0]["color"] == "#ff6b6b", "Consejo 1: Grieta a los 8 s (rojo)")
	check(str(tips[1]["text"]).contains("Corte de fase [4]") and tips[1]["color"] == "#46e3c1", "Consejo 2: Corte de fase [4] (cian)")
	check(str(tips[2]["text"]).begins_with("Fase 2 al 50 %") and tips[2]["color"] == "#5aa9ff", "Consejo 3: Fase 2 al 50 % (azul)")
	check(tips.all(func(t): return t["shape"] == "diamond"), "Viñetas en rombo")
	var acts: Array = s.loading_activities()
	check(acts.size() == 3, "3 actividades en espera")
	check(acts[0]["text"] == "Cambiar conjunto" and acts[0]["key"] == "F1–F3", "«Cambiar conjunto F1–F3»")
	check(acts[1]["text"] == "Revisar poderes" and acts[1]["key"] == "N", "«Revisar poderes N»")
	check(bool(acts[2]["party"]) and acts[2]["value"] == "3/5" and acts[2]["suffix"] == "ya dentro", "«Tu grupo: 3/5 ya dentro»")
	check(s.loading_percent() == 0 and s.loading_eta_text() == "0 % · unos 21 s", "0 % · unos 21 s")
	check(s.loading_stage_text() == "Conectando con el reino Umbral", "Etapa 1: «Conectando con el reino Umbral»")
	s.set_loading_progress(0.3)
	check(s.loading_stage_text() == "Sincronizando a Kael", "Etapa 2: «Sincronizando a Kael»")
	s.set_loading_progress(0.72)
	check(s.loading_stage_text() == "Cargando el terreno de Verdalia", "Etapa 3: «Cargando el terreno de Verdalia»")
	check(s.loading_eta_text() == "72 % · unos 6 s", "«72 % · unos 6 s» (como el HTML)")
	s.set_loading_progress(0.95)
	check(s.loading_stage_text() == "Preparando el encuentro" and s.loading_eta_text() == "95 % · unos 2 s", "Etapa 4: «Preparando el encuentro» · unos 2 s")
	s.set_loading_progress(0.97)
	check(s.loading_eta_text() == "97 % · casi listo", "En el último segundo: «casi listo»")
	s.set_party_inside(9)
	check(s.loading_activities()[2]["value"] == "5/5", "El grupo dentro no supera el tamaño")
	s.tick(10.0)
	check(near(s.loading_progress, 1.0) and not s.loading_active, "El reloj completa la carga")
	check(done == ["vado_roto"] and s.flow_screen == AS.SCREEN_WORLD, "loading_finished y flujo «in_world»")
	check(s.loading_stage_text() == "Listo · entrando en Vado Roto" and s.loading_eta_text() == "100 % · listo", "100 % · listo")
	check(prog.size() >= 4 and prog[-1] == 1.0, "loading_progressed acompaña al progreso")
	var d2: Dictionary = s.begin_loading({"destination_id": "puerto_runavell"})
	check(d2["name"] == "Puerto de Runavell" and s.loading_tips().size() == 3, "Destino con 2 consejos: se completa con uno general")
	check(str(s.loading_tips()[2]["text"]).contains("refugio de bolsillo"), "Consejo general: refugio de bolsillo [H]")
	check(s.loading_activities().size() == 1, "Jugando solo no hay chip de grupo")
	var d3: Dictionary = s.begin_loading({"destination_id": "no_existe", "name": "Mazmorra secreta", "duration_s": 4.0})
	check(d3["destination_id"] == "vado_roto" and d3["name"] == "Mazmorra secreta", "Los datos de dest_data sobrescriben los del seed")
	s.tick(2.0)
	check(s.loading_percent() == 50, "Duración personalizada (4 s → 50 % a los 2 s)")
	s.free()


# --------------------------------------------------------------------------
# 9. Ventanas
# --------------------------------------------------------------------------
func _test_launcher_window() -> void:
	print("-- 9a. LauncherWindow")
	var s := _svc()
	var w: Control = await _window(LauncherScene, s)
	check(w.get_script() != null and w.window_id == "launcher", "LauncherWindow instanciada (window_id launcher)")
	check(near(w.stage_scale, 1.0) and w.stage.size == Vector2(1440, 810), "Lienzo 1440×810 a escala 1")
	check(_text(w.titlebar, "GameName") == "[NOMBRE DEL JUEGO]" and _text(w.titlebar, "Subtitle") == "Launcher", "Barra de ventana «[NOMBRE DEL JUEGO] Launcher»")
	check(_text(w.titlebar, "Minimize") == "–" and _text(w.titlebar, "Maximize") == "□" and _text(w.titlebar, "Close") == "×", "Controles – □ ×")
	check(near(w.titlebar.size.y, 36.0) and near(w.sidebar.size.x, 230.0), "Barra de 36 px y lateral de 230 px")
	check(w.tab_buttons.size() == 5 and bool((w.tab_buttons["home"] as Button).get_meta("active")), "5 pestañas con Inicio activa")
	check(_text(w.account_card, "Title") == "Tu cuenta" and _text(w.account_card, "Status") == "Llave de acceso activa", "Tarjeta de cuenta")
	check(w.friends_button.text == "4 amigos jugando ahora", "Botón de amigos «4 amigos jugando ahora»")
	check(w.version_label.text == "v1.0.4" and w.integrity_button.text == "Comprobar integridad", "Versión y comprobación de integridad")
	check(w.season_caps.text == "TEMPORADA 1 · YA DISPONIBLE" and w.season_title.text == "La Brecha de Ferrum", "Portada con la temporada")
	check(w.season_title.get_theme_font_size("font_size") == 44, "Título de temporada de 44 px")
	check(near(w.cover.size.y, 330.0), "Portada de 330 px")
	check(w.cards_row.visible and w.cards_row.get_child_count() == 3, "3 tarjetas en Inicio")
	check(near(w.changes_card.size_flags_stretch_ratio, 1.3), "«Qué cambia para ti» ocupa 1,3fr")
	var ch: VBoxContainer = w.changes_card.get_node("Body")
	var dots := []
	for i in 3:
		var row := ch.find_child("Change_%d" % i, true, false)
		dots.append((row.get_node("Dot") as EK.Dot).color.to_html(false))
	check(dots == ["4fe39a", "f5c35b", "9aa6ae"], "Viñetas cromáticas #4fe39a · #f5c35b · #9aa6ae")
	check(ch.find_child("PatchNotes", true, false) != null, "«Ver notas completas»")
	var sv: VBoxContainer = w.servers_card.get_node("Body")
	check(_text(sv.find_child("Server_umbral", true, false), "Ping") == "24 ms · estable", "Umbral · 24 ms · estable")
	check(_text(sv.find_child("Server_nexo_asia", true, false), "Ping") == "cola ~3 min", "Nexo Asia · cola ~3 min")
	check(_text(sv, "Maintenance").contains("jueves"), "Aviso de mantenimiento en la tarjeta")
	var fr: VBoxContainer = w.friends_card.get_node("Body")
	var brisa := fr.find_child("Friend_brisa", true, false)
	check(brisa != null and _same((brisa.get_node("Avatar") as EK.Avatar).ring, Color("#f5c35b")), "Brisa con aro ámbar")
	check(_text(fr.find_child("Friend_mira", true, false), "Where") == "En el Nexo", "Mira · En el Nexo")
	check(w.play_button.text == "Jugar ahora" and bool(w.play_button.get_meta("primary")), "Botón «Jugar ahora» principal")
	var sb := w.play_button.get_theme_stylebox("normal") as StyleBoxFlat
	check(sb != null and _same(sb.bg_color, Color("#46e3c1")), "«Jugar ahora» en #46e3c1")
	check(w.play_button.custom_minimum_size.y == 56 and w.play_button.get_theme_font_size("font_size") == 20, "56 px de alto y 20 px de letra")
	check(not w.play_button.disabled, "Se puede jugar con lo imprescindible")
	check(w.download_label.text == "Actualizando · 18,4 de 42 GB · 48 MB/s · 9 min", "Pie: línea de descarga")
	check(w.play_hint.text == "Ferrum y Runavell se terminan de bajar mientras juegas", "Pie: aviso de paquetes pendientes")
	check(w.install_bar.segments.size() == 5 and w.pack_labels.get_child_count() == 5, "Barra segmentada de 5 paquetes")
	check(_text(w.pack_labels, "Pack_ferrum") == "Ferrum 40 %", "Etiqueta «Ferrum 40 %»")
	check(w.limit_button.text == "Limitar mientras juego ✓", "«Limitar mientras juego ✓»")
	w.pause_button.pressed.emit()
	w._process(0.0)
	check(s.install_paused and w.pause_button.text == "Reanudar", "Pausar la descarga")
	w.pause_button.pressed.emit()
	check(w.handle_key_event(_key(KEY_4)) and s.launcher_tab == "install", "Tecla 4 → Instalación")
	await _frames(1)
	check(w.tab_panel.visible and not w.cards_row.visible, "Instalación muestra su panel")
	check(w.tab_panel.find_child("Pack_runavell", true, false) != null, "Lista de paquetes en Instalación")
	(w.tab_panel.find_child("VerifyIntegrity", true, false) as Button).pressed.emit()
	await _frames(1)
	check(w.integrity_label.visible and w.integrity_label.text.begins_with("Integridad verificada"), "Resultado de integridad en la barra lateral")
	var urls := []
	w.patch_notes_requested.connect(func(u: String) -> void: urls.append(u))
	w.open_patch_notes()
	check(s.launcher_tab == "patch_notes" and urls.size() == 1, "«Ver notas completas» abre Notas del parche")
	check(_labels_text(w.tab_panel).contains("VERSIÓN V1.0.4"), "Notas del parche con la versión")
	w.select_tab("home")
	w.toggle_friends()
	check(bool(w.friends_card.get_meta("highlight")), "El botón de amigos resalta la tarjeta Amigos")
	var acts := []
	w.window_action.connect(func(a: String) -> void: acts.append(a))
	(w.titlebar.find_child("Minimize", true, false) as Button).pressed.emit()
	check(acts == ["minimize"] and w.last_window_action == "minimize", "– minimiza (simulado)")
	var plays := []
	w.play_requested.connect(func(sc: String) -> void: plays.append(sc))
	check(w.handle_key_event(_key(KEY_ENTER)), "Enter = Jugar ahora")
	check(plays == [AS.SCREEN_LOGIN] and w.last_navigation == "login", "Sin sesión navega al inicio de sesión")
	w.size = Vector2(1280, 720)
	await _frames(1)
	check(near(w.stage_scale, 720.0 / 810.0, 0.002), "El lienzo se escala al viewport (1280×720)")
	w.queue_free()
	await _frames(1)


func _test_login_window() -> void:
	print("-- 9b. LoginWindow")
	var s := _svc()
	var w: Control = await _window(LoginScene, s)
	check(w.window_id == "login", "LoginWindow instanciada")
	check(w.background is TextureRect or w.background is ColorRect, "Fondo cinemático")
	check(w.veil.visible and near(w.veil.color.a, 0.62), "Velo oscuro 0,62")
	check(w.logo_label.text == "[NOMBRE]" and w.logo_label.get_theme_font_size("font_size") == 54, "«[NOMBRE]» 54 px")
	check(w.tagline_label.text.begins_with("Cuatro universos"), "Lema")
	check(near(w.login_card.size.x, 420.0, 1.0), "Tarjeta de 420 px")
	check(near(w.login_card.position.x + w.login_card.size.x, 1440 - 90, 1.0) and near(w.login_card.position.y, 130.0), "Tarjeta a 90 px de la derecha y 130 px arriba")
	check(w.welcome_label.text == "Bienvenido de vuelta", "«Bienvenido de vuelta»")
	check(w.passkey_button.text == "Entrar con llave de acceso" and bool(w.passkey_button.get_meta("primary")), "Botón «Entrar con llave de acceso»")
	check(w.passkey_button.custom_minimum_size.y == 48 and w.passkey_button.find_child("KeyIcon", true, false) != null, "48 px con icono de llave")
	check(w.qr.custom_minimum_size == Vector2(132, 132), "QR de 132×132")
	check(w.qr.modules.size() == 81 and w.qr.dark_count() > 20, "QR con 9×9 módulos")
	check(str(w.qr.get_meta("code")) == s.qr_code and s.qr_code != "", "El QR muestra el código vivo")
	check(w.qr_text.text.contains("«Entrar en el PC»"), "Ayuda «Entrar en el PC»")
	check(w.qr_timer.text.contains(s.qr_code), "Temporizador del QR con el código")
	check(not w.credentials_box.visible and w.credentials_link.text == "Usar correo y contraseña", "Correo y contraseña plegado")
	w.toggle_credentials()
	check(w.credentials_box.visible and w.email_input != null and w.password_input.secret, "Formulario de correo desplegado (contraseña oculta)")
	var r: Dictionary = w.login_credentials("jugador@umbral.test", "malamala1")
	check(not r["ok"] and w.error_label.visible and w.error_label.text.contains("incorrectos"), "Error de credenciales visible")
	check(w.handle_key_event(_key(KEY_ESCAPE)) and not w.credentials_box.visible, "Esc pliega el formulario")
	check(w.keep_check.on and _text(w.login_card, "KeepSession") == "" and w.keep_label.text == "Mantener la sesión en este equipo", "«Mantener la sesión en este equipo» marcado")
	w.keep_check.toggled.emit(false)
	check(not s.keep_session, "Desmarcar la casilla")
	w.keep_check.toggled.emit(true)
	check(w.realm_name.text == "Umbral" and w.realm_status.text == "24 ms · sin cola", "Selector de reino «Umbral · 24 ms · sin cola»")
	check(w.cycle_realm() == "nexo_eu" and w.realm_status.text == "140 ms · sin cola", "Cambiar de reino")
	w.cycle_realm()
	check(s.selected_realm == "nexo_asia" and w.realm_status.text == "cola ~3 min", "Reino con cola")
	w.cycle_realm()
	check(w.a11y_buttons.size() == 6, "Barra de accesibilidad con 6 controles")
	var texts := []
	for k in ["FontSmaller", "FontNormal", "FontLarger", "HighContrast", "Narrator", "Colorblind"]:
		texts.append((w.a11y_buttons[k] as Button).text)
	check(texts == ["A−", "A", "A+", "Alto contraste", "Narrador", "Daltonismo"], "A− · A · A+ · Alto contraste · Narrador · Daltonismo")
	check(_text(w.a11y_buttons["Narrator"], "Key") == "Ctrl Alt N", "Narrador con atajo Ctrl Alt N")
	check(bool((w.a11y_buttons["FontNormal"] as Button).get_meta("active")), "A activo por defecto")
	(w.a11y_buttons["FontLarger"] as Button).pressed.emit()
	check(s.font_step == 2 and w.welcome_label.get_theme_font_size("font_size") == 30, "A+ agranda la tarjeta (26→30)")
	check(bool((w.a11y_buttons["FontLarger"] as Button).get_meta("active")), "A+ marcado")
	(w.a11y_buttons["FontNormal"] as Button).pressed.emit()
	check(w.welcome_label.get_theme_font_size("font_size") == 26, "A vuelve al tamaño del diseño")
	(w.a11y_buttons["HighContrast"] as Button).pressed.emit()
	check(s.high_contrast and near(w.veil.color.a, 0.82), "Alto contraste oscurece el velo")
	check(_same(_fc(w.qr_text), T.TEXT), "Alto contraste aclara el texto secundario")
	(w.a11y_buttons["HighContrast"] as Button).pressed.emit()
	check(_same(_fc(w.qr_text), T.TEXT_SECONDARY) and near(w.veil.color.a, 0.62), "Y se revierte")
	check(w.handle_key_event(_key(KEY_N, true, true)) and s.narrator, "Ctrl+Alt+N activa el narrador")
	check(bool((w.a11y_buttons["Narrator"] as Button).get_meta("active")), "Narrador marcado")
	check(not w.handle_key_event(_key(KEY_N)), "N a secas no hace nada en el login")
	w.handle_key_event(_key(KEY_N, true, true))
	(w.a11y_buttons["Colorblind"] as Button).pressed.emit()
	check(s.colorblind_mode == "protanopia" and (w.a11y_buttons["Colorblind"] as Button).text == "Protanopia", "Daltonismo → Protanopia")
	s.set_colorblind_mode("none")
	check(w.footer_label.text == "Servidores estables · v1.0.4", "Pie «Servidores estables · v1.0.4»")
	var logins := []
	w.logged_in.connect(func(m: String) -> void: logins.append(m))
	check(w.handle_key_event(_key(KEY_ENTER)), "Enter = llave de acceso")
	check(logins == ["passkey"] and w.last_navigation == "character_select", "Tras entrar navega a la selección")
	s.logout()
	var q: Dictionary = w.scan_qr_from_mobile()
	check(q["ok"] and logins[-1] == "qr", "Escanear el QR desde la app inicia sesión")
	w.queue_free()
	await _frames(1)


func _test_select_window() -> void:
	print("-- 9c. CharacterSelectWindow")
	var s := _svc()
	var w: Control = await _window(SelectScene, s)
	check(w.window_id == "character_select" and near(w.veil.color.a, 0.72), "Selección con velo 0,72")
	check(w.title_label_main.text == "[NOMBRE DEL JUEGO]" and w.realm_label.text == "Reino Umbral · Español · 24 ms · población alta", "Cabecera con nombre y reino")
	check(w.character_cards.size() == 4 and w.list_box.get_child_count() == 5, "4 tarjetas + «Crear personaje»")
	check(near(w.list_box.size.x, 320.0, 1.0) and near(w.list_box.position.x, 40.0), "Columna de 320 px a 40 px")
	var kael: PanelContainer = w.character_cards[0]
	var ksb := kael.get_theme_stylebox("panel") as StyleBoxFlat
	check(bool(kael.get_meta("selected")) and _same(ksb.border_color, Color("#46e3c1")) and ksb.border_width_left == 2, "Kael activo con aro cian #46e3c1 de 2 px")
	var aurel: PanelContainer = w.character_cards[3]
	var asb := aurel.get_theme_stylebox("panel") as StyleBoxFlat
	check(bool(aurel.get_meta("special")) and _same(asb.border_color, Color("#f5c35b")), "Aurel con aro dorado")
	check(_text(kael, "Level") == "32" and _text(kael, "Class") == "Tejedor de grietas" and _text(kael, "Meta") == "Verdalia · hace 2 días", "Tarjeta de Kael: 32 · Tejedor de grietas · Verdalia · hace 2 días")
	check(_same(_fc(kael.find_child("Meta", true, false)), Color("#9fe36a")), "Línea de Kael en verde Verdalia")
	check(_text(w.character_cards[1], "Meta") == "Runavell · hace 1 semana" and _text(w.character_cards[2], "Level") == "45", "Ysolde y Torq")
	check(_text(aurel, "Class") == "Narrador · personaje especial" and _text(aurel, "Meta") == "Asignado por el equipo · 27 días" and _text(aurel, "Level") == "", "Aurel: Narrador, 27 días, sin nivel")
	check(_text(w.create_button, "Text") == "+ Crear personaje" and _text(w.create_button, "Slots") == "· 2 espacios libres", "«+ Crear personaje · 2 espacios libres»")
	check(w.model_name.text == "Kael" and w.model_name.get_theme_font_size("font_size") == 32, "Modelo: «Kael» 32 px")
	check(w.model_detail.text == "Tejedor de grietas · nivel 32 · nivel de objeto 412", "Línea del modelo")
	check(w.stats_row.get_child_count() == 5, "5 chips de estadísticas")
	check(_labels_text(w.stats_row).contains("Vida 4.820"), "Chip «Vida 4.820»")
	check(w.model.breathing, "El modelo respira")
	var s0: float = w.model.breath_scale()
	w.model._process(0.9)
	check(not near(w.model.breath_scale(), s0, 0.0001) and w.model.breath_phase > 0.0, "La respiración anima la silueta")
	check(_same(w.model.ring, Color("#46e3c1")), "Pedestal cian")
	var away: VBoxContainer = w.away_card.get_node("Body")
	check(_labels_text(away).contains("MIENTRAS NO ESTABAS") and away.find_child("Away_3", true, false) != null, "«Mientras no estabas» con 4 avisos")
	check(_text(w.continue_box, "Title") == "Sellar la grieta menor · 2/3", "«Continúa donde lo dejaste»")
	check(near(w.away_card.size.x, 360.0, 1.0), "Tarjeta derecha de 360 px")
	check(_text(w.enter_button, "Text") == "Entrar al mundo" and _text(w.enter_button, "Key") == "Espacio", "«Entrar al mundo [Espacio]»")
	check(bool(w.enter_button.get_meta("primary")) and w.enter_button.custom_minimum_size.y == 56, "Botón principal de 56 px")
	check(w.enter_button.disabled, "Sin sesión «Entrar al mundo» está desactivado")
	check(_text(w.nest_button, "Count") == "5", "«Ir a El Nido» con 5 cosas listas")
	check(w.chips_row.get_child_count() == 4, "Chips Ajustes · Accesibilidad · Créditos · Borrar personaje")
	check(w.handle_key_event(_key(KEY_DOWN)) and s.selected_character_id == "ysolde", "↓ selecciona a Ysolde")
	await _frames(1)
	check(w.model_name.text == "Ysolde" and bool(w.character_cards[1].get_meta("selected")), "El modelo y el aro siguen a la selección")
	check(w.handle_key_event(_key(KEY_UP)) and s.selected_character_id == "kael", "↑ vuelve a Kael")
	w.select("aurel")
	await _frames(1)
	check(w.delete_chip.disabled and _same(w.model.ring, Color("#f5c35b")), "Aurel: no se puede borrar y pedestal dorado")
	w.select("torq")
	check(w.handle_key_event(_key(KEY_DELETE)) and w.delete_dialog.visible, "Supr abre la confirmación de borrado")
	check(w.delete_title.text == "Borrar a Torq" and _text(w.delete_dialog, "Prompt") == "ESCRIBE EL NOMBRE PARA CONFIRMAR", "«ESCRIBE EL NOMBRE PARA CONFIRMAR»")
	check(w.delete_confirm.disabled, "Borrar desactivado hasta escribir el nombre")
	w.type_delete_name("torq")
	check(w.delete_confirm.disabled, "Con «torq» sigue desactivado")
	w.type_delete_name("Torq")
	check(not w.delete_confirm.disabled, "Con «Torq» se activa")
	check(w.handle_key_event(_key(KEY_ESCAPE)) and not w.delete_dialog.visible and s.pending_delete_id == "", "Esc cancela")
	w.open_delete_dialog("torq")
	w.type_delete_name("Torq")
	var dr: Dictionary = w.confirm_delete()
	await _frames(1)
	check(dr["ok"] and not w.delete_dialog.visible and w.character_cards.size() == 3, "Torq borrado desde el diálogo")
	check(_text(w.create_button, "Slots") == "· 3 espacios libres", "«3 espacios libres»")
	var nests := [0]
	w.nest_requested.connect(func() -> void: nests[0] += 1)
	check(w.handle_key_event(_key(KEY_H)) and nests[0] == 1, "H → Ir a El Nido")
	w.toggle_accessibility_bar()
	check(w.a11y_bar.visible, "El chip Accesibilidad muestra la barra")
	s.login_with_passkey()
	await _frames(1)
	check(not w.enter_button.disabled, "Con sesión se puede entrar")
	var entries := []
	w.world_entry.connect(func(c: Dictionary, d: Dictionary) -> void: entries.append([c["id"], d["name"]]))
	w.select("kael")
	check(w.handle_key_event(_key(KEY_SPACE)), "Espacio = Entrar al mundo")
	check(entries == [["kael", "Vado Roto"]] and w.last_navigation == "game_loading", "Kael entra a Vado Roto y navega a la carga")
	var s2 := _svc()
	var w2: Control = await _window(SelectScene, s2)
	w2.create_character()
	check(w2.last_navigation == "character_create" and s2.flow_screen == AS.SCREEN_CREATE, "«+ Crear personaje» abre la creación")
	w.queue_free()
	w2.queue_free()
	await _frames(1)


func _test_create_window() -> void:
	print("-- 9d. CharacterCreationWindow")
	var s := _svc()
	var w: Control = await _window(CreateScene, s)
	w.initialize_window({})
	await _frames(1)
	check(w.window_id == "character_create" and near(w.veil.color.a, 0.78), "Creación con velo 0,78")
	check(w.step_pills.size() == 4, "Barra de 4 pasos")
	var states := []
	for p in w.step_pills:
		states.append(p.get_meta("state"))
	check(states == ["active", "pending", "pending", "pending"], "Paso 1 activo")
	check(_text(w.step_pills[0], "Label") == "Origen" and _text(w.step_pills[3], "Label") == "Nombre", "Etiquetas de pasos")
	var c0 := w.step_pills[0].find_child("Circle", true, false) as PanelContainer
	check(_same((c0.get_theme_stylebox("panel") as StyleBoxFlat).bg_color, Color("#46e3c1")), "Círculo activo #46e3c1")
	var a0 := w.step_pills[0].get_theme_stylebox("normal") as StyleBoxFlat
	check(a0.border_width_left == 2 and _same(a0.border_color, Color("#46e3c1")), "Aro de 1,5 px en el paso activo")
	check(w.step_pills[2].disabled, "Los pasos pendientes no se pueden pulsar")
	check(w.origin_label.text == "Origen: Verdalia" and _same(w.origin_dot.color, Color("#9fe36a")), "«Origen: Verdalia»")
	check(w.origin_selector.item_count == 4 and w.origin_selector.text == "cambiar", "Desplegable «cambiar» con 4 orígenes")
	check(w.content_box.find_child("Origin_ferrum", true, false) != null and bool(w.content_box.find_child("Origin_verdalia", true, false).get_meta("selected")), "Tarjetas de origen con Verdalia elegida")
	check(_text(w.detail_card, "EnergyName") == "Savia", "Detalle: afinidad elemental primaria Savia")
	w.origin_selector.item_selected.emit(2)
	await _frames(1)
	check(s.draft["origin"] == "runavell" and w.origin_label.text == "Origen: Runavell", "El desplegable cambia el origen")
	check(_text(w.detail_card, "EnergyName") == "Runa" and _same(w.preview.ring, Color("#f5b546")), "Runa y pedestal ámbar")
	check(w.next_button.text == "Siguiente: clase" and bool(w.next_button.get_meta("primary")), "Botón «Siguiente: clase»")
	check(w.back_button.text == "Volver a la selección" and not w.try_button.visible, "Atrás vuelve a la selección en el paso 1")
	check(w.handle_key_event(_key(KEY_ENTER)) and s.creation_step == 1, "Enter avanza a Clase")
	await _frames(1)
	states = []
	for p in w.step_pills:
		states.append(p.get_meta("state"))
	check(states == ["done", "active", "pending", "pending"], "Origen completado, Clase activa")
	check(_text(w.step_pills[0], "Num") == "✓" and _same((w.step_pills[0].find_child("Circle", true, false).get_theme_stylebox("panel") as StyleBoxFlat).bg_color, Color("#4fe39a")), "Completado: ✓ en #4fe39a")
	var grid := w.content_box.find_child("Grid", true, false) as GridContainer
	check(grid != null and grid.columns == 2 and grid.get_child_count() == 6, "Cuadrícula de 6 clases en 2 columnas")
	var guard := grid.find_child("Class_rune_guardian", true, false)
	check(_text(guard, "Recommended") == "Recomendada para empezar", "Guardiana rúnica: «Recomendada para empezar»")
	check(_text(guard.find_child("RoleBadge", true, false), "Text") == "Tanque", "Badge de rol «Tanque»")
	check(_text(grid.find_child("Class_rift_weaver", true, false), "Style") == "distancia · media", "Tejedor: «distancia · media»")
	check(_text(grid.find_child("Class_shadow_blade", true, false).find_child("RoleBadge", true, false), "Text") == "Asesino", "Hoja de sombra: «Asesino»")
	check(w.next_button.disabled and w.try_button.visible and w.try_button.disabled, "Sin clase: siguiente y probar desactivados")
	check(_text(w.detail_card, "Title") == "Elige una clase", "Detalle invita a elegir")
	w.choose_class("rift_weaver")
	await _frames(1)
	check(_text(w.detail_card, "Title") == "Tejedor de grietas", "Detalle del Tejedor de grietas")
	var rd = w.detail_card.find_child("Rating_damage", true, false)
	check(rd != null and int(rd.get_meta("value")) == 4 and (rd.get_node("Segments") as EK.Segments).value == 4, "Daño 4/5")
	check(int(w.detail_card.find_child("Rating_survival", true, false).get_meta("value")) == 2, "Supervivencia 2/5")
	check(w.detail_card.find_child("Video", true, false) != null, "Vídeo «Combate de 20 s con esta clase»")
	check(_text(w.detail_card, "TryDummy") == "Probar en el maniquí (5 min)", "«Probar en el maniquí (5 min)»")
	check(not w.next_button.disabled and w.next_button.text == "Siguiente: apariencia", "Con clase: «Siguiente: apariencia»")
	var trials := []
	w.trial_requested.connect(func(r: Dictionary) -> void: trials.append(r["class_id"]))
	(w.detail_card.find_child("TryDummy", true, false) as Button).pressed.emit()
	await _frames(1)
	check(trials == ["rift_weaver"] and s.trial_active, "El maniquí empieza")
	check(_text(w.detail_card, "TryDummy") == "En el maniquí · 5:00" and w.try_button.text == "En el maniquí · 5:00", "Botones con el tiempo restante")
	check(w.preview.accent_body.a > 0.0, "La silueta toma el color de la clase")
	w.primary_action()
	await _frames(1)
	check(s.creation_step == 2 and w.content_box.find_child("Appearance_hair_color", true, false) != null, "Paso Apariencia con controles")
	var rows := 0
	for k in AS.APPEARANCE_KEYS:
		if w.content_box.find_child("Appearance_%s" % k, true, false) != null:
			rows += 1
	check(rows == 5, "5 controles: cuerpo, peinado, color de pelo, ojos y atuendo")
	(w.content_box.find_child("Appearance_hair_color", true, false).find_child("Next", true, false) as Button).pressed.emit()
	await _frames(1)
	check(_text(w.content_box.find_child("Appearance_hair_color", true, false), "Text") == "Cobre" and _same(w.chibi.hair, Color("#8a4a20")), "Pelo Cobre en el chibi")
	w.cycle_appearance("hair_style", 1)
	await _frames(1)
	check(w.chibi.hair_style == 1 and _text(w.content_box.find_child("Appearance_hair_style", true, false), "Text") == "Coleta", "Peinado Coleta")
	check(_labels_text(w.detail_card).contains("Coleta"), "El detalle resume la apariencia")
	check(_labels_text(w.chibi_card).contains("Así se verá en tu refugio"), "«Así se verá en tu refugio»")
	w.primary_action()
	await _frames(1)
	check(s.creation_step == 3 and w.name_input != null, "Paso Nombre con campo de texto")
	check(w.next_button.text == "Confirmar creación" and w.next_button.disabled, "«Confirmar creación» desactivado")
	w.name_input.text = "Kael"
	w.name_input.text_changed.emit("Kael")
	check(w.name_status.text == "Ya existe un personaje con ese nombre" and str(w.name_status.get_meta("code")) == "taken", "Validación en vivo: ocupado")
	check(w.suggestion_button.visible and w.suggestion_button.text == "Usar «Kael2»", "Sugerencia «Kael2»")
	w.name_input.text_changed.emit("Ka")
	check(w.name_status.get_meta("code") == "too_short", "En vivo: demasiado corto")
	w.name_input.text_changed.emit("Kael Dos")
	check(w.name_status.get_meta("code") == "invalid_chars" and _same(_fc(w.name_status), Color("#ff6b6b")), "En vivo: caracteres inválidos en rojo")
	w.type_name("Vaelis")
	await _frames(1)
	check(w.name_status.text == "Disponible ✓" and _same(_fc(w.name_status), Color("#4fe39a")), "«Disponible ✓» en verde")
	check(w.next_button.disabled, "Falta el rasgo")
	check(w.content_box.find_child("Trait_persistent_echo", true, false) != null, "Tarjetas de rasgo cósmico")
	w.choose_trait("threshold_spark")
	await _frames(1)
	check(not w.next_button.disabled and bool(w.content_box.find_child("Trait_threshold_spark", true, false).get_meta("selected")), "Rasgo elegido: se puede confirmar")
	check(_labels_text(w.detail_card).contains("Chispa del Umbral") and _labels_text(w.detail_card).contains("Vaelis"), "Resumen con rasgo y nombre")
	check(w.handle_key_event(_key(KEY_ESCAPE)) and s.creation_step == 2, "Esc vuelve un paso")
	w.go_to_step(3)
	await _frames(1)
	check(s.creation_step == 3 and w.name_input.text == "Vaelis", "Pulsar el paso 4 conserva el nombre")
	var confirmed := []
	w.creation_confirmed.connect(func(c: Dictionary) -> void: confirmed.append(c["name"]))
	var r: Dictionary = w.primary_action()
	check(r["ok"] and confirmed == ["Vaelis"] and w.last_navigation == "character_select", "Confirmar creación vuelve a la selección")
	check(s.characters.size() == 5 and s.selected_character()["name"] == "Vaelis", "Vaelis creado y seleccionado")
	w.initialize_window({})
	await _frames(1)
	check(s.creation_step == 0 and s.flow_screen == AS.SCREEN_CREATE, "Reabrir empieza un borrador nuevo")
	var cancels := [0]
	w.creation_cancelled.connect(func() -> void: cancels[0] += 1)
	w.back()
	check(cancels[0] == 1 and s.flow_screen == AS.SCREEN_SELECT, "Atrás en el paso 1 cancela")
	w.queue_free()
	await _frames(1)


func _test_loading_window() -> void:
	print("-- 9e. GameLoadingWindow")
	var s := _svc()
	var w: Control = await _window(LoadingScene, s)
	w.initialize_window({"destination": {"destination_id": "vado_roto"}})
	await _frames(1)
	check(w.window_id == "game_loading" and not w.veil.visible, "Carga sin velo (el fondo es el destino)")
	check(near(w.shade.size.y, 420.0, 1.0) and near(w.shade.position.y + w.shade.size.y, 810.0, 1.0), "Degradado inferior de 420 px")
	check(w.destination_name.text == "Vado Roto" and w.destination_name.get_theme_font_size("font_size") == 40, "«Vado Roto» 40 px")
	check(w.destination_sub.text == "Verdalia · tu objetivo: derrota al Guardián del Umbral", "Universo y objetivo")
	check(_labels_text(w.destination_box).contains("DESTINO"), "Caps «Destino»")
	check(w.quote_label.text == "«El vado no se rompió: lo partieron desde el otro lado.»" and bool(w.quote_label.get_meta("italic")), "Cita de lore en cursiva")
	check(w.quote_source.text == "Diario de Mira, día 12", "Fuente de la cita")
	check(near(w.quote_box.position.x + w.quote_box.size.x, 1440 - 50, 1.0) and near(w.quote_box.position.y, 46.0), "Cita arriba a la derecha")
	check(_labels_text(w.tips_box).contains("ANTES DE LLEGAR"), "Tarjeta «Antes de llegar»")
	var tip_colors := []
	for i in 3:
		var row = w.tips_box.find_child("Tip_%d" % i, true, false)
		var d := row.get_node("Dot") as EK.Dot
		check(d.diamond, "Consejo %d con rombo" % (i + 1))
		tip_colors.append(d.color.to_html(false))
	check(tip_colors == ["ff6b6b", "46e3c1", "5aa9ff"], "Iconos de color de los 3 consejos")
	check(near(w.tips_card.size.x, 460.0, 1.0) and near(w.tips_card.position.x, 620.0), "Tarjeta de 460 px a 620 px")
	check(_labels_text(w.activities_box).contains("MIENTRAS CARGA"), "Chips «Mientras carga»")
	check(w.activities_box.find_child("Activity_0", true, false).get_meta("key") == "F1–F3", "«Cambiar conjunto F1–F3»")
	check(w.activities_box.find_child("Activity_1", true, false).get_meta("key") == "N", "«Revisar poderes N»")
	var party = w.activities_box.find_child("Activity_2", true, false)
	check(party != null and bool(party.get_meta("party")) and _text(party, "Value") == "3/5", "«Tu grupo: 3/5 ya dentro»")
	check(_same(_fc(party.find_child("Value", true, false)), Color("#4fe39a")), "3/5 en verde")
	s.set_loading_progress(0.72)
	w._process(0.0)
	check(w.stage_label.text == "Cargando el terreno de Verdalia" and w.eta_label.text == "72 % · unos 6 s", "«Cargando el terreno de Verdalia» · «72 % · unos 6 s»")
	check(near(w.progress_bar.ratio, 0.72), "Barra al 72 %")
	check(_same(w.progress_bar.fill, Color("#46e3c1")) and near(w.progress_bar.custom_minimum_size.y, 6.0), "Barra cian de 6 px")
	s.set_party_inside(4)
	w._process(0.0)
	check(_text(w.activities_box.find_child("Activity_2", true, false), "Value") == "4/5", "El chip del grupo se actualiza (4/5)")
	var shelters := [0]
	w.pocket_shelter_requested.connect(func() -> void: shelters[0] += 1)
	check(w.handle_key_event(_key(KEY_H)) and shelters[0] == 1, "H abre el refugio de bolsillo (Anexo D)")
	var ready := []
	w.world_ready.connect(func(d: Dictionary) -> void: ready.append(d["name"]))
	s.set_loading_progress(1.0)
	await _frames(1)
	check(ready == ["Vado Roto"] and w.finished, "Al 100 % emite world_ready")
	check(w.eta_label.text == "100 % · listo" and near(w.progress_bar.ratio, 1.0), "Barra al 100 % · listo")
	check(s.flow_screen == AS.SCREEN_WORLD, "El flujo llega a «in_world»")
	w.initialize_window({"destination": {"destination_id": "puerto_runavell"}})
	await _frames(1)
	check(w.destination_name.text == "Puerto de Runavell" and w.activities_box.find_child("Activity_1", true, false) == null, "Otro destino: sus datos y sin chip de grupo")
	w.queue_free()
	await _frames(1)


# --------------------------------------------------------------------------
# 10. Flujo completo vía UIOrchestrator
# --------------------------------------------------------------------------
func _test_full_flow() -> void:
	print("-- 10. Flujo completo launcher → login → selección → creación → carga → mundo")
	var orch := root.get_node_or_null("UIOrchestrator")
	var svc := root.get_node_or_null("AuthLifecycleService")
	if orch == null or svc == null:
		check(false, "Orquestador y servicio disponibles")
		return
	svc.session_path = _cfg_path()
	svc.load_seed(SEED)
	svc.logged_in = false
	svc.auto_tick = false
	svc.flow_screen = AS.SCREEN_LAUNCHER
	var l: Node = orch.open_launcher()
	await _frames(1)
	l.play()
	await _frames(1)
	check(not orch.is_window_open("launcher") and orch.is_window_open("login"), "Jugar ahora: Launcher → Login")
	var lg: Node = orch.get_window_instance("login")
	lg.login_passkey()
	await _frames(1)
	check(not orch.is_window_open("login") and orch.is_window_open("character_select"), "Llave de acceso: Login → Selección")
	var cs: Node = orch.get_window_instance("character_select")
	cs.create_character()
	await _frames(1)
	check(orch.is_window_open("character_create") and not orch.is_window_open("character_select"), "Crear personaje: Selección → Creación")
	var cc: Node = orch.get_window_instance("character_create")
	check(svc.creation_step == 0 and svc.flow_screen == AS.SCREEN_CREATE, "La creación conserva el borrador recién empezado")
	cc.choose_origin("ferrum")
	cc.primary_action()
	cc.choose_class("rune_guardian")
	cc.primary_action()
	cc.primary_action()
	cc.type_name("Brunhild")
	cc.choose_trait("steady_pulse")
	await _frames(1)
	var r: Dictionary = cc.primary_action()
	await _frames(1)
	check(r["ok"] and orch.is_window_open("character_select") and not orch.is_window_open("character_create"), "Confirmar: Creación → Selección")
	check(svc.selected_character()["name"] == "Brunhild", "Brunhild seleccionada")
	cs = orch.get_window_instance("character_select")
	cs.enter_world()
	await _frames(1)
	check(orch.is_window_open("game_loading") and not orch.is_window_open("character_select"), "Entrar al mundo: Selección → Carga")
	var gl: Node = orch.get_window_instance("game_loading")
	check(str(svc.loading_destination["name"]) == "Bóveda de Ferrum" and gl.destination_name.text == "Bóveda de Ferrum", "Su origen Ferrum la lleva a la Bóveda de Ferrum")
	check(orch.is_entry_flow_active(), "Durante la carga los atajos del mundo siguen bloqueados")
	svc.tick(30.0)
	await _frames(2)
	check(not orch.is_window_open("game_loading") and svc.flow_screen == AS.SCREEN_WORLD, "Al terminar la carga se cierra sola: en el mundo")
	check(not orch.is_entry_flow_active(), "En el mundo los atajos vuelven a funcionar")
	orch.close_all_windows()
	await _frames(1)
