extends SceneTree
## Suite headless (UI v2.4 Paso 17 · ADR 115): HUD de raid extendido (10/20), mecánicas de sanador
## y consolidación de las ventanas de UI v2.4.
## Run: Godot --headless --path clients/godot-mmo-client -s tests/unit/test_raid_hud_and_consolidation.gd
## Exit code 0 = todo PASS.

const RS = preload("res://shared-core/RaidService.gd")
const T = preload("res://ui/tokens/hud_tokens.gd")
const RK = preload("res://ui/windows/common/RaidKit.gd")
const SEED := "res://config/raid/raid_seed.json"
const EDITOR_SEED := "res://config/ui_editor/ui_editor_seed.json"
const SCENE := "res://ui/windows/RaidHUDWindow/RaidHUDWindow.tscn"
const MIN_CHECKS := 450
const CATEGORY_HUD := 0
const CATEGORY_GAME := 1

## Roster de MMO-Raid.html: [id, nombre, rol, grupo, hp %, curación entrante, daño previsto,
## purificable, distancia, caído, seleccionado, peligro].
const ROSTER := [
	["toro", "Toro", "tank", 1, 58, 12, 30, false, 12, false, false, true],
	["brisa", "Brisa", "healer", 1, 92, 0, 0, false, 0, false, false, false],
	["kael", "Kael", "dps", 1, 61, 0, 20, false, 18, false, false, false],
	["nox", "Nox", "dps", 1, 40, 18, 0, true, 14, false, true, false],
	["vela", "Vela", "dps", 1, 100, 0, 0, false, 42, false, false, false],
	["ulric", "Ulric", "tank", 2, 88, 0, 0, false, 10, false, false, false],
	["sasha", "Sasha", "healer", 2, 74, 0, 0, false, 22, false, false, false],
	["dren", "Dren", "dps", 2, 30, 0, 22, false, 8, false, false, false],
	["ivo", "Ivo", "dps", 2, 0, 0, 0, false, 16, true, false, false],
	["lune", "Lune", "dps", 2, 95, 0, 0, false, 25, false, false, false],
	["mira", "Mira", "healer", 3, 100, 0, 0, false, 20, false, false, false],
	["joao", "Joao", "dps", 3, 66, 0, 0, true, 11, false, false, false],
	["aren", "Aren", "dps", 3, 81, 0, 0, false, 19, false, false, false],
	["pim", "Pim", "dps", 3, 52, 0, 25, false, 9, false, false, false],
	["kora", "Kora", "dps", 3, 90, 0, 0, false, 27, false, false, false],
	["tess", "Tess", "healer", 4, 77, 0, 0, false, 24, false, false, false],
	["bram", "Bram", "dps", 4, 45, 0, 30, false, 7, false, false, false],
	["oda", "Oda", "dps", 4, 100, 0, 0, false, 30, false, false, false],
	["rhea", "Rhea", "dps", 4, 63, 0, 0, false, 21, false, false, false],
	["finn", "Finn", "dps", 4, 88, 0, 0, false, 15, false, false, false],
]

## Ventanas de UI v2.4 que conviven con el HUD de raid (16 + raid_hud = 17).
const COEXIST := ["inventory", "powers", "shelter", "quests_window", "map_window", "social_window",
	"crafting_window", "trade_window", "collections_window", "incursions_window", "dialogue_window",
	"death_window", "dungeon_lobby", "dungeon_summary", "settings_window", "ui_editor"]

var _fails: Array[String] = []
var _checks := 0
var _tmp_files: Array[String] = []


func check(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_fails.append(msg)
		printerr("  FAIL: ", msg)
	else:
		print("  PASS: ", msg)


func near(a: float, b: float, eps: float = 0.01) -> bool:
	return absf(a - b) <= eps


func vnear(a: Vector2, b: Vector2, eps: float = 0.01) -> bool:
	return near(a.x, b.x, eps) and near(a.y, b.y, eps)


func cnear(a: Color, b: Color, eps: float = 0.01) -> bool:
	return near(a.r, b.r, eps) and near(a.g, b.g, eps) and near(a.b, b.b, eps) and near(a.a, b.a, eps)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("== [TEST] Paso 17: HUD de raid extendido y consolidación ==")
	await process_frame
	_prepare_autoloads()
	await _test_registry()
	await _test_orchestrator()
	_test_roster()
	_test_incoming_heal()
	_test_projected_damage()
	_test_dispel()
	_test_range()
	_test_dead()
	_test_click_casting()
	_test_boss()
	_test_alerts()
	_test_mana()
	await _test_window_grid()
	await _test_window_boss()
	await _test_window_alert()
	await _test_window_console()
	await _test_coexistence()
	for f in _tmp_files:
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
		print("RESULTADO: FAIL")
		quit(1)


# --------------------------------------------------------------------------
# Utilidades
# --------------------------------------------------------------------------
func _frames(n: int = 2) -> void:
	for i in n:
		await process_frame


func _tmp(tag: String) -> String:
	var p := "user://test_step17_%s_%d.cfg" % [tag, _tmp_files.size()]
	_tmp_files.append(p)
	return p


## Autoloads aislados: sin reloj automático ni escritura en los ficheros del usuario.
func _prepare_autoloads() -> void:
	var rs := root.get_node_or_null("RaidService")
	if rs != null:
		rs.auto_tick = false
	var es := root.get_node_or_null("UIEditorService")
	if es != null:
		es.save_path = _tmp("layouts")
		es.load_seed(EDITOR_SEED)
	var ss := root.get_node_or_null("SettingsService")
	if ss != null:
		ss.save_path = _tmp("settings")
		ss.apply_to_engine = false
		ss.auto_tick = false


func _svc() -> Node:
	var r: Node = RS.new()
	r.auto_tick = false
	r.load_seed(SEED)
	root.add_child(r)
	return r


func _window(r: Node, params: Dictionary = {}) -> Node:
	var w = load(SCENE).instantiate()
	w.raid = r
	root.add_child(w)
	w.initialize_window(params)
	return w


func _free(n: Node) -> void:
	if is_instance_valid(n):
		n.queue_free()


func _key(code: int, ctrl: bool = false, shift: bool = false, echo: bool = false) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	ev.ctrl_pressed = ctrl
	ev.shift_pressed = shift
	ev.echo = echo
	return ev


## Posición de un control respecto al escenario 1440×810.
func _stage_pos(c: Control, stage: Control) -> Vector2:
	var p := Vector2.ZERO
	var n: Node = c
	while n != null and n != stage:
		if n is Control:
			p += (n as Control).position
		n = n.get_parent()
	return p


# --------------------------------------------------------------------------
# 1. Registro, tokens y capa
# --------------------------------------------------------------------------
func _test_registry() -> void:
	print("-- 1. Registro en UIWindowRegistry, tokens y capa")
	var orch := root.get_node_or_null("UIOrchestrator")
	check(orch != null, "UIOrchestrator disponible")
	check(root.get_node_or_null("RaidService") != null, "Autoload RaidService registrado")
	check(ProjectSettings.get_setting("autoload/RaidService", "") == "*res://shared-core/RaidService.gd", "project.godot declara el autoload RaidService")
	check(FileAccess.file_exists(SEED), "Seed config/raid/raid_seed.json")
	check(typeof(JSON.parse_string(FileAccess.get_file_as_string(SEED))) == TYPE_DICTIONARY, "El seed es JSON válido")
	var mirror := ProjectSettings.globalize_path("res://").path_join("../shared-core/RaidService.gd")
	check(FileAccess.file_exists(mirror) and FileAccess.get_file_as_string(mirror) == FileAccess.get_file_as_string("res://shared-core/RaidService.gd"), "RaidService.gd reflejado byte a byte en clients/shared-core")
	if orch == null:
		return
	var reg = orch.registry
	check(reg.is_registered("raid_hud"), "raid_hud registrada")
	var meta = reg.get_metadata("raid_hud")
	check(meta.category == CATEGORY_HUD, "raid_hud en la capa HUD (convive sin robar el foco)")
	check(meta.scene_path == SCENE, "Ruta de escena del HUD de raid")
	check(ResourceLoader.exists(SCENE), "La escena RaidHUDWindow.tscn existe")
	check(reg.get_shortcut_combos("raid_hud") == [{"keycode": KEY_R, "ctrl": true, "shift": false, "alt": false}], "raid_hud declara el atajo Ctrl+R")
	check(reg.get_window_for_combo(KEY_R, true) == "raid_hud", "Ctrl+R resuelve a raid_hud")
	check(reg.get_window_for_combo(KEY_R, false) == "", "R sin Ctrl no resuelve a ninguna ventana por combinación")
	check(reg.get_window_for_combo(KEY_R, true, true) == "", "Ctrl+Shift+R no es el atajo del raid")
	check(reg.get_window_for_combo(KEY_R, true, false, true) == "", "Ctrl+Alt+R no es el atajo del raid")
	check(reg.get_window_for_key(KEY_R) == "", "La R sola sigue libre para la habilidad definitiva")
	check(reg.get_shortcut_keys("raid_hud") == [], "Sin atajos de tecla sola para raid_hud")
	for m in ["open_raid_hud", "toggle_raid_hud", "is_raid_hud_open", "close_raid_hud", "is_party_swapped_for_raid"]:
		check(orch.has_method(m), "UIOrchestrator.%s()" % m)
	for id in ["party_frames", "settings_window", "ui_editor", "options_menu", "inventory", "powers", "death_window"]:
		check(reg.is_registered(id), "Se conserva el registro de %s" % id)
	check(reg.get_window_for_key(KEY_F10) == "settings_window", "F10 sigue en Ajustes")
	# Tokens visuales
	check(T.RAID_FRAME_SIZE == Vector2(128, 42), "Token: marco 128×42")
	check(T.RAID_FRAME_GAP == Vector2(10, 3), "Token: 10 px entre columnas y 3 px entre filas")
	check(T.RAID_GROUPS == 4 and T.RAID_GROUP_SIZE == 5 and T.RAID_SIZE == 20, "Token: 4 grupos de 5 (20)")
	check(T.RAID_FRAME_RADIUS == 8, "Token: radio 8")
	check(cnear(T.RAID_FRAME_BG, Color(7 / 255.0, 10 / 255.0, 12 / 255.0, 0.9)), "Token: fondo rgba(7,10,12,.9)")
	check(cnear(T.RAID_FRAME_EDGE, Color(1, 1, 1, 0.08)), "Token: borde blanco 8 %")
	check(T.RAID_HEALTH == Color("#3ccf73"), "Token: vida #3ccf73")
	check(cnear(T.RAID_INCOMING_HEAL, Color(60 / 255.0, 207 / 255.0, 115 / 255.0, 0.35)), "Token: curación entrante rgba(60,207,115,.35)")
	check(cnear(T.RAID_PREDICTED_A, Color(245 / 255.0, 195 / 255.0, 91 / 255.0, 0.75)), "Token: rayado ámbar .75")
	check(cnear(T.RAID_PREDICTED_B, Color(245 / 255.0, 195 / 255.0, 91 / 255.0, 0.2)), "Token: rayado ámbar .2")
	check(T.RAID_PREDICTED_STRIPE == 4.0, "Token: franjas de 4 px (periodo 8)")
	check(T.RAID_AGGRO == Color("#ff6b6b"), "Token: peligro #ff6b6b")
	check(T.RAID_SELECTED == Color("#46e3c1"), "Token: seleccionado #46e3c1")
	check(T.RAID_DISPEL == Color("#b47bff"), "Token: rombo purificable #b47bff")
	check(T.RAID_DEBUFF_FILL == Color("#7a5bd0"), "Token: vida con debuff #7a5bd0")
	check(T.RAID_ROLE_TANK == Color("#5aa9ff") and T.RAID_ROLE_HEALER == Color("#4fe39a") and T.RAID_ROLE_DPS == Color("#ff9a4d"), "Token: colores de rol")
	check(T.raid_role_color("tank") == T.RAID_ROLE_TANK and T.raid_role_color("healer") == T.RAID_ROLE_HEALER and T.raid_role_color("dps") == T.RAID_ROLE_DPS, "raid_role_color() por rol")
	check(T.raid_role_color("x") == T.TEXT_SECONDARY, "raid_role_color() con rol desconocido")
	check(T.RAID_BOSS_ORIGIN == Vector2(470, 20) and T.RAID_BOSS_WIDTH == 500.0, "Token: jefe en x 470…970, y 20")
	check(T.RAID_BOSS_BAR_HEIGHT == 14.0 and T.RAID_BOSS_HP == Color("#e25555") and T.RAID_BOSS_PHASE == Color("#f5c35b"), "Token: barra de jefe 14 px #e25555 y fase #f5c35b")
	check(T.RAID_ALERT_TOP == 170.0, "Token: alerta en y 170")
	check(cnear(T.RAID_ALERT_BG, Color(58 / 255.0, 29 / 255.0, 34 / 255.0, 0.92)) and T.RAID_ALERT_EDGE == Color("#ff6b6b"), "Token: alerta rgba(58,29,34,.92) con borde #ff6b6b")
	check(T.RAID_ALERT_COUNT == Color("#ff8a8a") and T.RAID_ALERT_SUB == Color("#ffc9c9") and T.RAID_ALERT_ICON == Color("#ffb3b3"), "Token: colores de la alerta")
	check(T.RAID_GRID_ORIGIN == Vector2(40, 290), "Token: marcos en x 40, y 290")
	check(T.RAID_CONSOLE_POINTS == [Vector2(380, 811), Vector2(420, 690), Vector2(1020, 690), Vector2(1060, 811)], "Token: trapecio M380 811L420 690H1020L1060 811Z")
	check(cnear(T.RAID_CONSOLE_BG, Color(13 / 255.0, 18 / 255.0, 22 / 255.0, 0.97)), "Token: consola #0d1216 @ .97")
	check(T.RAID_CONSOLE_RECT.position.x == 453.0 and T.RAID_CONSOLE_RECT.end.y == 794.0 and T.RAID_CONSOLE_RECT.size.x == 534.0, "Token: consola x 453, bottom 16, 534 de ancho")
	check(T.RAID_SLOT_SIZE == 48.0 and T.RAID_SLOT_GAP == 6.0 and T.RAID_SLOT_RADIUS == 11, "Token: ranuras 48×48, gap 6, radio 11")
	check(T.RAID_HEAL_RANGE == 40.0 and T.RAID_OUT_OF_RANGE_ALPHA == 0.4 and T.RAID_DEAD_ALPHA == 0.6, "Token: alcance 40 m, opacidades 0,4 y 0,6")
	await _frames(1)


# --------------------------------------------------------------------------
# 2. Orquestador: apertura, alternancia y conmutación grupo ↔ raid
# --------------------------------------------------------------------------
func _test_orchestrator() -> void:
	print("-- 2. UIOrchestrator: apertura, alternancia y conmutación entre grupo y raid")
	var orch := root.get_node_or_null("UIOrchestrator")
	var router := root.get_node_or_null("UIInputRouter")
	var rs := root.get_node_or_null("RaidService")
	var es := root.get_node_or_null("UIEditorService")
	if orch == null or rs == null:
		check(false, "Autoloads disponibles")
		return
	rs.load_seed(SEED)
	var events: Array = []
	orch.raid_hud_toggled.connect(func(o: bool) -> void: events.append(o))
	check(not orch.is_raid_hud_open(), "Arranca cerrado")
	var w: Node = orch.open_raid_hud()
	await _frames(2)
	check(w != null and orch.is_raid_hud_open(), "open_raid_hud() lo abre")
	check(w.get_parent() == orch.window_layer, "En la capa de ventanas del orquestador")
	check(w.raid == rs, "Usa el autoload RaidService")
	check(orch.focus_manager.current_focus_id != "raid_hud", "No roba el foco (capa HUD)")
	check(not w.show_backdrop, "Sin fondo de vista previa en el mundo")
	check(w.mouse_filter == Control.MOUSE_FILTER_IGNORE, "No bloquea el ratón fuera de los marcos")
	check(events == [true], "raid_hud_toggled(true)")
	if es != null:
		check(es.active_preset == "raid20", "UIEditorService pasa al diseño Raid 20 (contenido «raid»)")
		check(es.current_content == "raid", "UIEditorService registra el contenido raid")
	orch.toggle_raid_hud()
	await _frames(1)
	check(not orch.is_raid_hud_open(), "toggle_raid_hud() lo cierra")
	check(events == [true, false], "raid_hud_toggled(false)")
	orch.toggle_raid_hud()
	check(orch.is_raid_hud_open(), "toggle_raid_hud() lo vuelve a abrir")
	check(orch.get_window_instance("raid_hud") == w, "Reutiliza la misma instancia")
	orch.close_raid_hud()
	check(not orch.is_raid_hud_open(), "close_raid_hud()")
	if router != null:
		check(router.handle_window_shortcut(_key(KEY_R, true), orch), "Ctrl+R consumido por el router")
		await _frames(1)
		check(orch.is_raid_hud_open(), "Ctrl+R abre el HUD de raid")
		check(router.handle_window_shortcut(_key(KEY_R, true), orch) and not orch.is_raid_hud_open(), "Ctrl+R otra vez lo cierra")
		check(not router.handle_window_shortcut(_key(KEY_R), orch), "R sola no abre el raid")
		check(not router.handle_window_shortcut(_key(KEY_R, true, true), orch), "Ctrl+Shift+R no abre el raid")
		check(not router.handle_window_shortcut(_key(KEY_R, true, false, true), orch), "Ctrl+R con eco se ignora")
		check(not orch.is_raid_hud_open(), "Sigue cerrado tras los atajos no válidos")
		check(router.handle_window_shortcut(_key(KEY_N), orch) and orch.is_window_open("powers"), "Los atajos de tecla sola siguen funcionando (N)")
		orch.close_window("powers")
	# Conmutación grupo ↔ raid
	orch.open_window("party_frames")
	await _frames(1)
	check(orch.is_window_open("party_frames"), "Marcos de grupo abiertos")
	orch.open_raid_hud({"raid_size": 10})
	await _frames(2)
	check(not orch.is_window_open("party_frames"), "Al abrir el raid se ocultan los marcos de grupo")
	check(orch.is_party_swapped_for_raid(), "is_party_swapped_for_raid()")
	check(w.visible_card_count() == 10 and w.column_count() == 2, "Parámetro raid_size 10 → 2 columnas × 5")
	orch.close_raid_hud()
	await _frames(1)
	check(orch.is_window_open("party_frames"), "Al cerrar el raid vuelven los marcos de grupo")
	check(not orch.is_party_swapped_for_raid(), "Conmutación restablecida")
	orch.close_window("party_frames")
	orch.open_raid_hud({"raid_size": 20})
	check(not orch.is_window_open("party_frames"), "Sin marcos de grupo abiertos, el raid no los abre")
	check(not orch.is_party_swapped_for_raid(), "…ni marca la conmutación")
	check(w.visible_card_count() == 20 and w.column_count() == 4, "raid_size 20 → 4 columnas × 5")
	orch.open_window("party_frames")
	orch.close_all_windows()
	await _frames(2)
	check(not orch.is_raid_hud_open() and not orch.is_window_open("party_frames"), "close_all_windows no reabre los marcos de grupo")
	check(not orch.is_party_swapped_for_raid(), "close_all_windows limpia la conmutación")
	rs.load_seed(SEED)


# --------------------------------------------------------------------------
# 3. Carga de 20 integrantes, roles y estadísticas
# --------------------------------------------------------------------------
func _test_roster() -> void:
	print("-- 3. RaidService: 20 integrantes, roles y estadísticas")
	var r := _svc()
	check(r.members.size() == 20 and r.raid_size == 20, "20 integrantes en banda de 20")
	check(r.visible_members().size() == 20, "20 visibles")
	check(r.grid_columns() == 4 and r.grid_rows() == 5, "Cuadrícula 4 × 5")
	check(r.header_text() == "Raid · 20", "Cabecera «Raid · 20»")
	check(r.click_legend == "Clic: Sanar · Clic der.: Escudo · Shift+clic: Purificar", "Leyenda de click-casting")
	var ids: Array = []
	for i in ROSTER.size():
		var e: Array = ROSTER[i]
		var m: Dictionary = r.members[i]
		ids.append(m["id"])
		check(m["id"] == e[0] and m["name"] == e[1], "Puesto %d: %s" % [i + 1, e[1]])
		check(m["role"] == e[2], "%s: rol %s" % [e[1], e[2]])
		check(int(m["group"]) == e[3], "%s: grupo %d" % [e[1], e[3]])
		check(int(m["hp_percent"]) == e[4], "%s: %d %% de vida" % [e[1], e[4]])
		check(int(m["current_hp"]) == roundi(int(m["max_hp"]) * e[4] / 100.0), "%s: vida actual coherente con la máxima" % e[1])
		check(str(m["class_name"]) != "", "%s: clase declarada" % e[1])
		check(r.grid_cell(e[0]) == Vector2i(i / 5, i % 5), "%s: columna %d, fila %d" % [e[1], i / 5 + 1, i % 5 + 1])
	var unique := {}
	for id in ids:
		unique[id] = true
	check(unique.size() == 20, "Ids únicos")
	check(r.role_counts() == {"tank": 2, "healer": 4, "dps": 14}, "2 tanques · 4 sanadores · 14 de daño")
	check(r.members_by_role("tank").size() == 2 and r.members_by_role("tank")[0]["name"] == "Toro", "Tanques: Toro y Ulric")
	check(r.role_label("tank") == "Tanque" and r.role_label("healer") == "Sanador" and r.role_label("dps") == "Daño", "Etiquetas de rol")
	check(r.role_color("tank") == T.RAID_ROLE_TANK and r.role_color("healer") == T.RAID_ROLE_HEALER and r.role_color("dps") == T.RAID_ROLE_DPS, "Colores de rol del seed = tokens")
	for g in range(1, 5):
		check(r.group_members(g).size() == 5, "Grupo %d: 5 integrantes" % g)
	check(r.alive_count() == 19, "19 vivos")
	check(near(r.average_hp_percent(), 1400.0 / 19.0, 0.01), "Vida media de los vivos 73,68 % (1400 / 19)")
	check(r.member_index("finn") == 19 and r.member_index("nadie") == -1, "member_index()")
	check(r.get_member("nadie").is_empty(), "get_member() de un desconocido")
	# Banda de 10
	var changed := []
	r.raid_size_changed.connect(func(s: int) -> void: changed.append(s))
	check(r.set_raid_size(10), "set_raid_size(10)")
	check(r.visible_members().size() == 10 and r.grid_columns() == 2, "Banda de 10: 2 columnas × 5 filas")
	check(r.header_text() == "Raid · 10", "Cabecera «Raid · 10»")
	check(r.member_ids()[9] == "lune" and not r.has_member("mira"), "Banda de 10 = grupos 1 y 2")
	check(r.grid_cell("mira") == Vector2i(-1, -1), "Fuera de la banda de 10 no tiene celda")
	check(r.group_members(3).is_empty(), "Grupo 3 oculto en banda de 10")
	check(not r.set_raid_size(15) and r.raid_size == 10, "Tamaño no válido (15) rechazado")
	check(r.set_raid_size(20) and changed == [10, 20], "raid_size_changed(10, 20)")
	# Compatibilidad con marcos de grupo (PartyFrames / PartyService)
	var n: int = r.load_party_members([{"name": "Ana", "class": "guerrero", "role": "tank", "hp": 700, "max_hp": 1000},
		{"name": "Beto", "class": "mago", "hp": 0, "max_hp": 800}])
	check(n == 2, "load_party_members importa 2 integrantes del grupo")
	check(r.members[0]["name"] == "Ana" and r.members[0]["role"] == "tank" and int(r.members[0]["hp_percent"]) == 70, "Grupo importado: Ana, tanque, 70 %")
	check(r.members[1]["is_dead"] and r.members[1]["role"] == "dps", "Grupo importado: Beto caído, rol por defecto daño")
	check(r.members[2]["name"] == "Kael", "El resto de la banda se conserva")
	_free(r)


# --------------------------------------------------------------------------
# 4. Curación entrante
# --------------------------------------------------------------------------
func _test_incoming_heal() -> void:
	print("-- 4. RaidService: curación entrante (incoming_heal) y barras")
	var r := _svc()
	for e in ROSTER:
		var m: Dictionary = r.get_member(e[0])
		check(near(float(m["incoming_heal"]), e[5]), "%s: curación entrante %d %%" % [e[1], e[5]])
		var span: Vector2 = r.incoming_heal_span(e[0])
		check(vnear(span, Vector2(e[4], minf(e[5], 100 - e[4])) / 100.0), "%s: tramo verde a partir de la vida (left %d %%)" % [e[1], e[4]])
	check(vnear(r.incoming_heal_span("toro"), Vector2(0.58, 0.12)), "Toro: left 58 %, width 12 %")
	check(vnear(r.incoming_heal_span("nox"), Vector2(0.40, 0.18)), "Nox: left 40 %, width 18 %")
	check(r.set_incoming_heal("lune", 30), "set_incoming_heal()")
	check(vnear(r.incoming_heal_span("lune"), Vector2(0.95, 0.05)), "La curación entrante se recorta a la vida que falta (95 % + 5 %)")
	check(r.set_incoming_heal("vela", 50) and r.incoming_heal_span("vela").y == 0.0, "Con la vida llena no se dibuja")
	check(r.set_incoming_heal("kael", 150) and near(float(r.get_member("kael")["incoming_heal"]), 100.0), "Se acota a 100 %")
	check(not r.set_incoming_heal("nadie", 10), "Integrante desconocido")
	check(near(r.projected_hp_percent("nox"), 58.0), "Nox: vida prevista 40 + 18 = 58 %")
	check(near(r.projected_hp_percent("toro"), 40.0), "Toro: vida prevista 58 − 30 + 12 = 40 %")
	check(r.projected_hp_percent("ivo") == 0.0, "Caído: vida prevista 0")
	check(r.incoming_heal_span("nadie") == Vector2.ZERO, "Sin integrante, sin tramo")
	var v: Dictionary = r.member_view("toro")
	check(v.has("heal_span") and vnear(v["heal_span"], Vector2(0.58, 0.12)), "member_view expone heal_span")
	r.resolve_prediction("nox")
	check(int(r.get_member("nox")["hp_percent"]) == 58 and r.get_member("nox")["incoming_heal"] == 0.0, "Resolver la predicción aplica la curación entrante")
	_free(r)


# --------------------------------------------------------------------------
# 5. Daño previsto a 3 s y rayado
# --------------------------------------------------------------------------
func _test_projected_damage() -> void:
	print("-- 5. RaidService: daño previsto a 3 s y rayado ámbar")
	var r := _svc()
	var expected := {"toro": Vector2(0.28, 0.30), "kael": Vector2(0.41, 0.20), "dren": Vector2(0.08, 0.22), "pim": Vector2(0.27, 0.25), "bram": Vector2(0.15, 0.30)}
	for e in ROSTER:
		check(near(float(r.get_member(e[0])["projected_damage_3s"]), e[6]), "%s: daño previsto %d %%" % [e[1], e[6]])
		var span: Vector2 = r.projected_damage_span(e[0])
		if expected.has(e[0]):
			check(vnear(span, expected[e[0]]), "%s: rayado left %d %% width %d %% (último tramo de la vida)" % [e[1], roundi(expected[e[0]].x * 100), roundi(expected[e[0]].y * 100)])
		else:
			check(span.y == 0.0, "%s: sin rayado" % e[1])
	check(not r.is_lethal("toro"), "Toro: 30 % de daño con 58 % de vida no es letal")
	check(r.set_projected_damage("dren", 80), "set_projected_damage()")
	check(vnear(r.projected_damage_span("dren"), Vector2(0.0, 0.30)), "El daño previsto no supera la vida restante")
	check(r.is_lethal("dren"), "Dren: daño previsto letal")
	check(r.triage_order()[0] == "dren", "Triaje: Dren primero")
	var tri: Array = r.triage_order()
	check(not tri.has("ivo") and not tri.has("vela"), "Triaje excluye caídos y fuera de alcance")
	check(tri.size() == 18, "Triaje: 18 integrantes atendibles")
	r.resolve_prediction("bram")
	check(int(r.get_member("bram")["hp_percent"]) == 15 and r.projected_damage_span("bram").y == 0.0, "Resolver la predicción aplica el daño (45 − 30 = 15 %)")
	check(r.set_projected_damage("oda", -5) and r.get_member("oda")["projected_damage_3s"] == 0.0, "Daño negativo acotado a 0")
	var v: Dictionary = r.member_view("pim")
	check(vnear(v["damage_span"], Vector2(0.27, 0.25)) and not v["lethal"], "member_view expone damage_span y lethal")
	# Rayado (repeating-linear-gradient 135deg, 4 px / 8 px)
	var probe := Control.new()
	root.add_child(probe)
	check(RK.hatch(probe, Rect2()) == 0, "hatch() sin área no dibuja")
	_free(probe)
	check(T.RAID_PREDICTION_WINDOW == 3.0, "Ventana de predicción de 3 s")
	_free(r)


# --------------------------------------------------------------------------
# 6. Debuffs purificables
# --------------------------------------------------------------------------
func _test_dispel() -> void:
	print("-- 6. RaidService: debuffs purificables y rombos")
	var r := _svc()
	for e in ROSTER:
		var m: Dictionary = r.get_member(e[0])
		check(bool(m["has_dispellable_debuff"]) == e[7], "%s: purificable = %s" % [e[1], str(e[7])])
		check(r.hp_fill_color(e[0]) == (T.RAID_DEBUFF_FILL if e[7] else T.RAID_HEALTH), "%s: relleno %s" % [e[1], "violeta" if e[7] else "verde"])
	check(r.get_member("nox")["debuff_name"] == "Magia", "Nox: debuff Magia")
	check(r.set_debuff("kael", true, "Veneno"), "set_debuff(kael)")
	check(r.get_member("kael")["has_dispellable_debuff"] and r.get_member("kael")["debuff_name"] == "Veneno", "Kael purificable (Veneno)")
	check(r.set_debuff("kael", false) and r.get_member("kael")["debuff_name"] == "", "Quitar el debuff")
	check(not r.set_debuff("nadie", true), "Integrante desconocido")
	var got := []
	r.member_dispelled.connect(func(id: String) -> void: got.append(id))
	check(r.dispel_target("nox"), "Purificar a Nox")
	check(not r.get_member("nox")["has_dispellable_debuff"] and r.hp_fill_color("nox") == T.RAID_HEALTH, "Nox vuelve al verde")
	check(got == ["nox"], "member_dispelled(nox)")
	_free(r)


# --------------------------------------------------------------------------
# 7. Alcance y atenuación
# --------------------------------------------------------------------------
func _test_range() -> void:
	print("-- 7. RaidService: rango y atenuación (> 40 m, opacidad 0,4)")
	var r := _svc()
	check(r.heal_range_m == 40.0, "Alcance de curación 40 m")
	for e in ROSTER:
		var out: bool = e[8] > 40
		check(r.is_out_of_range(e[0]) == out, "%s a %d m: %s" % [e[1], e[8], "fuera de alcance" if out else "a tiro"])
	check(r.status_text("vela") == "42 m", "Vela: «42 m»")
	check(r.frame_opacity("vela") == 0.4, "Vela: opacidad 0,4")
	check(r.set_member_distance("kael", 35.0) and not r.is_out_of_range("kael"), "35 m: a tiro")
	check(r.set_member_distance("kael", 40.0) and not r.is_out_of_range("kael"), "40 m justos: a tiro")
	check(r.set_member_distance("kael", 40.5) and r.is_out_of_range("kael"), "40,5 m: fuera")
	check(r.status_text("kael") == "41 m" and r.frame_opacity("kael") == 0.4, "Kael: «41 m» y opacidad 0,4")
	check(r.set_member_distance("kael", 10.0) and r.status_text("kael") == "61 %", "De vuelta a tiro muestra su vida")
	check(r.set_member_distance("vela", -3.0) and r.get_member("vela")["distance_meters"] == 0.0, "Distancia negativa acotada a 0")
	r.set_member_distance("vela", 42.0)
	var fails := []
	r.cast_failed.connect(func(id: String, why: String) -> void: fails.append([id, why]))
	var mana: float = r.mana_current
	check(not r.heal_target("vela"), "No se puede sanar fuera de alcance")
	check(fails == [["vela", RS.REASON_RANGE]], "cast_failed(vela, out_of_range)")
	check(r.mana_current == mana, "Sin gasto de maná")
	check(r.selected_id == "vela", "…pero el clic selecciona el objetivo")
	check(r.is_out_of_range("nadie") == false, "Desconocido: no está fuera de alcance")
	_free(r)


# --------------------------------------------------------------------------
# 8. Integrantes caídos
# --------------------------------------------------------------------------
func _test_dead() -> void:
	print("-- 8. RaidService: integrantes caídos y aviso de resurrección")
	var r := _svc()
	for e in ROSTER:
		check(r.is_dead(e[0]) == e[9], "%s: %s" % [e[1], "caído" if e[9] else "vivo"])
	check(r.status_text("ivo") == "Muerto · resucitar", "Ivo: «Muerto · resucitar»")
	check(r.frame_opacity("ivo") == 0.6, "Ivo: opacidad 0,6")
	check(r.dead_members() == ["ivo"], "Caídos: [ivo]")
	check(int(r.get_member("ivo")["current_hp"]) == 0, "Ivo: 0 de vida")
	check(r.hp_span("ivo").y == 0.0 and r.incoming_heal_span("ivo").y == 0.0 and r.projected_damage_span("ivo").y == 0.0, "Ivo: sin barras")
	var fails := []
	r.cast_failed.connect(func(id: String, why: String) -> void: fails.append(why))
	check(not r.heal_target("ivo") and fails.back() == RS.REASON_DEAD, "No se puede sanar a un caído")
	check(not r.shield_target("ivo") and fails.back() == RS.REASON_DEAD, "Ni escudarlo")
	check(not r.resurrect_target("dren") and fails.back() == RS.REASON_ALIVE, "No se resucita a un vivo")
	var died := []
	r.member_died.connect(func(id: String) -> void: died.append(id))
	var lost: int = r.damage_member("dren", 5000)
	check(lost == 300 and r.is_dead("dren"), "Daño letal: Dren cae (pierde sus 300)")
	check(died == ["dren"], "member_died(dren)")
	check(r.status_text("dren") == "Muerto · resucitar" and r.get_member("dren")["projected_damage_3s"] == 0.0, "Al caer se limpian predicciones")
	check(r.damage_member("dren", 10) == 0, "Un caído no recibe más daño")
	check(r.alive_count() == 18, "18 vivos")
	var res := []
	r.member_resurrected.connect(func(id: String) -> void: res.append(id))
	check(r.resurrect_target("ivo"), "Resucitar a Ivo")
	check(not r.is_dead("ivo") and int(r.get_member("ivo")["hp_percent"]) == 30, "Ivo vuelve con 30 %")
	check(res == ["ivo"] and r.frame_opacity("ivo") == 1.0, "member_resurrected(ivo) y opacidad 1")
	check(near(r.mana_current, 420.0), "Resucitar cuesta 100 de maná")
	check(r.handle_click("dren", MOUSE_BUTTON_LEFT) and not r.is_dead("dren"), "Clic izq. sobre un caído lo resucita")
	_free(r)


# --------------------------------------------------------------------------
# 9. Click-casting
# --------------------------------------------------------------------------
func _test_click_casting() -> void:
	print("-- 9. RaidService: click-casting (clic izq., clic der., Shift+clic)")
	var r := _svc()
	check(r.selected_id == "nox" and r.get_member("nox")["is_selected"], "Objetivo inicial: Nox")
	var healed := []
	var shielded := []
	var dispelled := []
	var selected := []
	r.member_healed.connect(func(id: String, amount: int) -> void: healed.append([id, amount]))
	r.member_shielded.connect(func(id: String, amount: int) -> void: shielded.append([id, amount]))
	r.member_dispelled.connect(func(id: String) -> void: dispelled.append(id))
	r.target_selected.connect(func(id: String) -> void: selected.append(id))
	# Clic izquierdo: sanar
	check(r.handle_click("dren", MOUSE_BUTTON_LEFT), "Clic izq. sobre Dren")
	check(int(r.get_member("dren")["hp_percent"]) == 45, "Dren: 30 → 45 % (+15 %)")
	check(healed == [["dren", 150]], "member_healed(dren, 150)")
	check(selected.back() == "dren" and r.selected_id == "dren", "target_selected(dren)")
	var n_sel := 0
	for m in r.members:
		if m["is_selected"]:
			n_sel += 1
	check(n_sel == 1 and not r.get_member("nox")["is_selected"], "Un solo objetivo seleccionado")
	check(near(r.mana_current, 480.0), "Sanar cuesta 40 de maná (520 → 480)")
	check(r.border_state("dren") == "selected", "Dren: borde cian")
	check(r.border_state("toro") == "threat", "Toro: el rojo de peligro tiene prioridad")
	r.select_target("toro")
	check(r.border_state("toro") == "threat", "Toro seleccionado sigue en rojo (peligro inminente)")
	check(r.heal_target("toro") and int(r.get_member("toro")["current_hp"]) == 870 + 225, "Sanar al tanque: +15 % de 1500 (225)")
	check(not r.heal_target("oda"), "Con la vida llena no se cura")
	check(near(r.mana_current, 440.0), "…y no gasta maná (440)")
	r.set_projected_damage("lune", 0)
	check(r.heal_target("lune") and int(r.get_member("lune")["hp_percent"]) == 100, "La curación se acota a la vida máxima (95 → 100 %)")
	check(healed.back() == ["lune", 50], "member_healed(lune, 50): solo lo que faltaba")
	# Clic derecho: escudo
	check(r.handle_click("pim", MOUSE_BUTTON_RIGHT), "Clic der. sobre Pim")
	check(int(r.get_member("pim")["shield"]) == 200, "Pim: escudo de 200 (20 %)")
	check(shielded == [["pim", 200]], "member_shielded(pim, 200)")
	check(r.selected_id == "pim", "El escudo también selecciona")
	check(vnear(r.shield_span("pim"), Vector2(0, 0.2)), "Franja de escudo al 20 %")
	check(r.damage_member("pim", 150) == 0 and int(r.get_member("pim")["shield"]) == 50, "El escudo absorbe 150 de daño")
	check(r.damage_member("pim", 100) == 50 and int(r.get_member("pim")["hp_percent"]) == 47, "Lo que sobra va a la vida (52 → 47 %)")
	# Shift+clic: purificar
	var mana_before: float = r.mana_current
	check(r.handle_click("joao", MOUSE_BUTTON_LEFT, true), "Shift+clic sobre Joao")
	check(dispelled == ["joao"] and not r.get_member("joao")["has_dispellable_debuff"], "member_dispelled(joao)")
	check(near(r.mana_current, mana_before - 30.0), "Purificar cuesta 30 de maná")
	check(int(r.get_member("joao")["hp_percent"]) == 66, "Purificar no cura")
	var fails := []
	r.cast_failed.connect(func(id: String, why: String) -> void: fails.append(why))
	check(not r.handle_click("kael", MOUSE_BUTTON_LEFT, true) and fails.back() == RS.REASON_NO_DEBUFF, "Shift+clic sin debuff: falla (no_debuff)")
	check(not r.handle_click("kael", MOUSE_BUTTON_MIDDLE), "Botón central: sin acción")
	check(not r.handle_click("nadie", MOUSE_BUTTON_LEFT) and fails.back() == RS.REASON_UNKNOWN, "Integrante desconocido: unknown_member")
	# Sin maná
	r.set_mana(10)
	check(not r.heal_target("kael") and fails.back() == RS.REASON_MANA, "Sin maná no se cura (no_mana)")
	check(not r.shield_target("kael") and fails.back() == RS.REASON_MANA, "Sin maná no se escuda")
	check(r.mana_current == 10.0, "El maná no baja de lo disponible")
	# Banda de 10: los de fuera no son seleccionables
	r.set_mana(1000)
	r.set_raid_size(10)
	check(not r.select_target("mira") and not r.heal_target("mira"), "En banda de 10 no se puede curar a Mira (grupo 3)")
	r.select_target("finn")
	check(r.selected_id == "kael", "Seleccionar fuera de la banda no cambia el objetivo (Kael)")
	r.select_target("")
	check(r.selected_id == "" and not r.get_member("kael")["is_selected"], "select_target(\"\") limpia la selección")
	r.set_priority_threat("kael")
	check(r.border_state("kael") == "threat" and r.border_state("toro") == "normal", "set_priority_threat mueve el peligro a Kael")
	r.set_priority_threat("")
	check(r.border_state("kael") == "normal", "set_priority_threat(\"\") lo quita")
	_free(r)


# --------------------------------------------------------------------------
# 10. Jefe colosal
# --------------------------------------------------------------------------
func _test_boss() -> void:
	print("-- 10. RaidService: barra de jefe colosal, fases y enrage")
	var r := _svc()
	check(r.boss_name == "Coloso de Runavell", "Nombre: «Coloso de Runavell»")
	check(r.boss_phase == 2 and r.boss_phase_label() == "Fase 2", "Fase 2")
	check(r.boss_phase_count() == 3, "3 fases")
	check(r.boss_phase_label(1) == "Fase 1" and r.boss_phase_label(3) == "Fase 3", "Etiquetas de fase")
	check(r.boss_phase_color == Color("#f5c35b"), "Color de fase #f5c35b")
	check(r.boss_hp_color == Color("#e25555"), "Vida en #e25555")
	check(r.boss_hp_percent == 43.0 and r.boss_hp_text() == "43 %", "Vida 43 %")
	check(r.get_enrage_time_formatted() == "04:12", "Enrage «04:12»")
	check(RS.format_clock(60) == "01:00" and RS.format_clock(0) == "00:00" and RS.format_clock(605) == "10:05", "format_clock()")
	r.tick(1.0)
	check(r.get_enrage_time_formatted() == "04:11", "tick(1) → «04:11»")
	r.tick(0.5)
	check(r.get_enrage_time_formatted() == "04:11", "Medio segundo no cambia el reloj (redondeo hacia arriba)")
	r.tick(0.5)
	check(r.get_enrage_time_formatted() == "04:10", "…y otro medio sí («04:10»)")
	var phases := []
	r.boss_phase_changed.connect(func(p: int) -> void: phases.append(p))
	check(r.damage_boss(5) == 38.0 and r.boss_phase == 2, "Daño 5 → 38 %, sigue en Fase 2")
	check(r.damage_boss(8) == 30.0 and r.boss_phase == 3, "Al cruzar el 30 % pasa a Fase 3")
	check(phases == [3], "boss_phase_changed(3)")
	check(r.advance_boss_phase() == 3, "No hay fase después de la última")
	check(r.damage_boss(0) == 30.0, "Daño 0 no cambia nada")
	check(r.damage_boss(200) == 0.0 and r.is_boss_defeated(), "Jefe derrotado (0 %)")
	var r2 := _svc()
	check(r2.advance_boss_phase() == 3 and r2.boss_phase_label() == "Fase 3", "advance_boss_phase(): 2 → 3")
	var enr := []
	r2.boss_enraged.connect(func() -> void: enr.append(1))
	r2.tick(251.0)
	check(not r2.enraged and r2.get_enrage_time_formatted() == "00:01", "A 1 s del enrage")
	r2.tick(1.0)
	check(r2.enraged and r2.get_enrage_time_formatted() == "00:00", "Enrage alcanzado")
	r2.tick(5.0)
	check(enr.size() == 1, "boss_enraged se emite una sola vez")
	# Simulación automática
	var r3 := _svc()
	r3.auto_tick = true
	r3._process(1.0)
	check(r3.get_enrage_time_formatted() == "04:12", "Sin encuentro en curso el reloj no corre")
	r3.start_encounter()
	r3._process(2.0)
	check(r3.encounter_active and r3.get_enrage_time_formatted() == "04:10", "Con encuentro en curso corre solo")
	r3.stop_encounter()
	r3._process(2.0)
	check(not r3.encounter_active and r3.get_enrage_time_formatted() == "04:10", "stop_encounter() lo detiene")
	_free(r)
	_free(r2)
	_free(r3)


# --------------------------------------------------------------------------
# 11. Alertas tácticas
# --------------------------------------------------------------------------
func _test_alerts() -> void:
	print("-- 11. RaidService: alertas tácticas con audio direccional y cuenta atrás")
	var r := _svc()
	check(r.alert_active, "Alerta activa del seed")
	check(r.alert_title == "Todos a la izquierda", "Título «Todos a la izquierda»")
	check(r.alert_subtitle == "Terremoto rúnico · también suena desde la derecha", "Subtítulo del terremoto rúnico")
	check(r.get_alert_countdown() == 3, "Cuenta atrás «3»")
	check(r.alert_side == "right" and r.alert_direction == "left", "Suena desde la derecha · moverse a la izquierda")
	check(r.alert_pan() == 1.0, "Pan estéreo +1 (derecha)")
	var g: Dictionary = r.alert_stereo_gains()
	check(near(g["right"], 1.0) and near(g["left"], 0.0), "Ganancias: derecha 1, izquierda 0")
	check(r.alert_arrow_rotation() == 0.0, "Flecha hacia la izquierda (rotación 0)")
	var ticks := []
	var cleared := []
	r.alert_tick.connect(func(c: int) -> void: ticks.append(c))
	r.alert_cleared.connect(func() -> void: cleared.append(1))
	r.tick(1.0)
	check(r.get_alert_countdown() == 2 and ticks == [2], "tick(1) → «2»")
	r.tick(0.4)
	check(r.get_alert_countdown() == 2 and ticks == [2], "0,4 s después sigue en «2»")
	r.tick(0.6)
	check(r.get_alert_countdown() == 1 and ticks == [2, 1], "→ «1»")
	r.tick(1.0)
	check(not r.alert_active and r.get_alert_countdown() == 0, "Al llegar a 0 la alerta se retira")
	check(cleared.size() == 1, "alert_cleared")
	var cues := []
	var trig := []
	r.alert_audio_cue.connect(func(side: String, pan: float) -> void: cues.append([side, pan]))
	r.alert_triggered.connect(func(t: String, side: String) -> void: trig.append([t, side]))
	r.trigger_alert("Separaos", "Orbes de runa", 5.0, "left")
	check(r.alert_active and r.get_alert_countdown() == 5, "trigger_alert de 5 s")
	check(r.alert_direction == "right" and r.alert_arrow_rotation() == PI, "Suena por la izquierda → moverse a la derecha (flecha girada 180°)")
	check(r.alert_pan() == -1.0, "Pan −1 (izquierda)")
	check(cues == [["left", -1.0]], "alert_audio_cue(left, −1)")
	check(trig == [["Separaos", "left"]], "alert_triggered(Separaos, left)")
	r.trigger_alert("Agrupaos", "", 2.0, "center", "up")
	check(r.alert_pan() == 0.0 and r.alert_direction == "up", "Centro con dirección explícita «up»")
	g = r.alert_stereo_gains()
	check(near(g["left"], 0.7071, 0.001) and near(g["right"], 0.7071, 0.001), "Centro: potencia constante (0,707 · 0,707)")
	check(near(r.alert_arrow_rotation(), PI * 0.5), "Flecha hacia arriba")
	r.trigger_alert("X", "", 1.0, "abajo")
	check(r.alert_side == "center" and r.alert_direction == "", "Lado no válido → centro sin flecha")
	r.clear_alert()
	check(not r.alert_active and cleared.size() == 2, "clear_alert()")
	r.clear_alert()
	check(cleared.size() == 2, "clear_alert() es idempotente")
	r.trigger_alert("Nada", "", 0.0, "right")
	check(not r.alert_active, "Duración 0 no muestra alerta")
	_free(r)


# --------------------------------------------------------------------------
# 12. Maná y habilidades
# --------------------------------------------------------------------------
func _test_mana() -> void:
	print("-- 12. RaidService: proyección de gasto de maná y habilidades")
	var r := _svc()
	check(r.mana_current == 520.0 and r.mana_max == 1000.0, "Maná 520 / 1000")
	check(r.mana_percent() == 52, "52 %")
	check(near(r.mana_burn_per_sec, 5.2), "Ritmo de gasto 5,2/s")
	check(near(r.mana_duration_seconds(), 100.0), "Dura 100 s")
	check(r.mana_projection_text() == "Maná 52 % · dura ~1:40 a este ritmo", "«Maná 52 % · dura ~1:40 a este ritmo»")
	check(r.healer_hp_percent == 88.0, "Vida del sanador 88 %")
	check(RS.format_duration(100) == "1:40" and RS.format_duration(3725) == "1:02:05" and RS.format_duration(INF) == "∞", "format_duration()")
	check(RS.format_duration(59.9) == "0:59", "format_duration redondea hacia abajo")
	var mc := []
	r.mana_changed.connect(func(c: float, m: float) -> void: mc.append(c))
	r.set_mana(260)
	check(r.mana_projection_text() == "Maná 26 % · dura ~0:50 a este ritmo", "Con 260: «dura ~0:50»")
	check(mc == [260.0], "mana_changed(260)")
	r.set_mana_burn_rate(0)
	check(r.mana_projection_text() == "Maná 26 % · sin gasto", "Sin gasto")
	check(is_inf(r.mana_duration_seconds()), "Duración infinita sin gasto")
	r.set_mana(0)
	check(r.mana_duration_seconds() == 0.0, "Sin maná dura 0")
	r.set_mana(2000)
	check(r.mana_current == 1000.0, "El maná se acota al máximo")
	r.set_mana(500, 2000)
	check(r.mana_max == 2000.0 and r.mana_percent() == 25, "set_mana con nuevo máximo")
	r.set_healer_hp(150)
	check(r.healer_hp_percent == 100.0, "Vida del sanador acotada a 100")
	# Habilidades
	var r2 := _svc()
	check(r2.ability_count() == 10, "10 habilidades")
	var keys := ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
	var cds := ["", "", "", "6", "", "22", "", "1:40", "", ""]
	var colors := ["#1a2e22", "#1a2e22", "#1d2f55", "#2a1d3a", "#1a2e22", "#1c3a3a", "#1d2f55", "#4a3a1c", "#1a2e22", "#4a1d22"]
	for i in 10:
		var a: Dictionary = r2.ability(i)
		check(a["key"] == keys[i], "Ranura %d: tecla %s" % [i + 1, keys[i]])
		check(r2.ability_cooldown_text(i) == cds[i], "Ranura %d: enfriamiento «%s»" % [i + 1, cds[i]])
		check(Color(a["color"]) == Color(colors[i]), "Ranura %d: color %s" % [i + 1, colors[i]])
		check(r2.ability_index_for_key(keys[i]) == i, "Tecla %s → ranura %d" % [keys[i], i + 1])
	check(r2.ability(10).is_empty() and r2.ability_index_for_key("x") == -1, "Fuera de rango")
	check(RS.format_cooldown(6) == "6" and RS.format_cooldown(22) == "22" and RS.format_cooldown(100) == "1:40" and RS.format_cooldown(0) == "", "format_cooldown()")
	check(RS.format_cooldown(5.2) == "6", "Enfriamiento redondeado hacia arriba")
	check(not r2.use_ability(3), "Purificar (4) en enfriamiento no se puede usar")
	r2.tick(6.0)
	check(r2.is_ability_ready(3) and r2.ability_cooldown_text(3) == "", "Tras 6 s está lista")
	check(r2.ability_cooldown_text(5) == "16", "Marea de vida: 22 → 16")
	check(r2.ability_cooldown_text(7) == "1:34", "Himno: 1:40 → 1:34")
	check(r2.use_ability(3) and r2.ability_cooldown_text(3) == "8", "Usar Purificar arranca su enfriamiento (8)")
	check(near(r2.mana_current, 490.0), "…y gasta 30 de maná")
	r2.set_mana(0)
	check(not r2.use_ability(0), "Sin maná no se usa Sanación rápida")
	check(r2.use_ability(9), "Último aliento no cuesta maná")
	_free(r)
	_free(r2)


# --------------------------------------------------------------------------
# 13. Ventana: cuadrícula de 20 celdas
# --------------------------------------------------------------------------
func _test_window_grid() -> void:
	print("-- 13. RaidHUDWindow: 20 celdas, 4 columnas y estilos")
	var r := _svc()
	var w = _window(r, {"backdrop": true})
	await _frames(3)
	check(w.stage != null and w.stage.size == Vector2(1440, 810), "Escenario 1440×810")
	check(w.show_backdrop and w.backdrop.visible and w.backdrop_veil.visible, "Vista previa con fondo y velo")
	check(cnear(w.backdrop_veil.color, Color(5 / 255.0, 8 / 255.0, 10 / 255.0, 0.25)), "Velo rgba(5,8,10,.25)")
	check(w.cards.size() == 20 and w.visible_card_count() == 20, "20 celdas visibles")
	check(w.column_count() == 4, "4 columnas")
	for c in w.columns:
		var n := 0
		for k in c.get_children():
			if k.visible:
				n += 1
		check(n == 5, "%s: 5 celdas" % c.name)
	check(w.header_label.text == "RAID · 20", "Cabecera «RAID · 20»")
	check(w.legend_label.text == "Clic: Sanar · Clic der.: Escudo · Shift+clic: Purificar", "Leyenda de click-casting en la cabecera")
	check(vnear(w.raid_box.position, Vector2(40, 290)), "Marcos en x 40, y 290")
	var c0: Control = w.get_card("toro")
	var p0: Vector2 = _stage_pos(c0, w.stage)
	for i in ROSTER.size():
		var e: Array = ROSTER[i]
		var card: Control = w.get_card(e[0])
		check(card != null and card.size == Vector2(128, 42), "%s: celda 128×42" % e[1])
		if card == null:
			continue
		var p: Vector2 = _stage_pos(card, w.stage)
		check(vnear(p - p0, Vector2((i / 5) * 138, (i % 5) * 45)), "%s: columna %d, fila %d (gap 10 · 3)" % [e[1], i / 5 + 1, i % 5 + 1])
		check(card.status_text() == r.status_text(e[0]), "%s: estado «%s»" % [e[1], r.status_text(e[0])])
		check(near(card.modulate.a, r.frame_opacity(e[0])), "%s: opacidad %.1f" % [e[1], r.frame_opacity(e[0])])
		var bs: String = "threat" if e[11] else ("selected" if e[10] else "normal")
		check(card.border_state() == bs, "%s: borde %s" % [e[1], bs])
		check(card.role_color() == T.raid_role_color(e[2]), "%s: cuadrito de rol %s" % [e[1], e[2]])
		check(card.hp_color() == (T.RAID_DEBUFF_FILL if e[7] else T.RAID_HEALTH), "%s: color de vida" % e[1])
		check(near(card.hp_rect().size.x, 128.0 * e[4] / 100.0, 0.05), "%s: relleno de vida %d px" % [e[1], roundi(128.0 * e[4] / 100.0)])
		check(card.has_diamond() == e[7], "%s: rombo %s" % [e[1], "visible" if e[7] else "oculto"])
		check((card.last_hatch_stripes > 0) == (e[6] > 0), "%s: rayado %s" % [e[1], "dibujado" if e[6] > 0 else "ausente"])
		check(card.mouse_filter == Control.MOUSE_FILTER_STOP, "%s: celda clicable" % e[1])
	check(w.get_card("toro").border_color() == T.RAID_AGGRO and w.get_card("toro").border_width() == 2, "Toro: borde rojo de 2 px")
	check(w.get_card("nox").border_color() == T.RAID_SELECTED and w.get_card("nox").border_width() == 2, "Nox: borde cian de 2 px")
	check(w.get_card("kael").border_color() == T.RAID_FRAME_EDGE and w.get_card("kael").border_width() == 1, "Kael: borde blanco 8 % de 1 px")
	check(vnear(w.get_card("toro").heal_rect().position, Vector2(128 * 0.58, 0), 0.05) and near(w.get_card("toro").heal_rect().size.x, 128 * 0.12, 0.05), "Toro: curación entrante desde 58 % y 12 % de ancho")
	check(near(w.get_card("toro").damage_rect().position.x, 128 * 0.28, 0.05) and near(w.get_card("toro").damage_rect().size.x, 128 * 0.30, 0.05), "Toro: rayado desde 28 % y 30 % de ancho")
	check(vnear(w.get_card("nox").diamond_center(), Vector2(128 - 7 - 5.5, 7 + 5.5)), "Rombo a 7 px de la esquina superior derecha")
	check(w.get_card("nox").badge_rect() == Rect2(114, 29, 8, 8), "Cuadrito de rol 8×8 a 6 · 5 px de la esquina inferior derecha")
	check(w.get_card("ivo").status_text() == "Muerto · resucitar", "Ivo muestra «Muerto · resucitar»")
	check(w.get_card("vela").status_text() == "42 m", "Vela muestra «42 m»")
	check(w.get_card("toro").tooltip_text.contains("en peligro") and w.get_card("nox").tooltip_text.contains("purificable"), "Texto accesible por celda")
	# Leyenda inferior
	check(w.legend_row.get_child_count() == 3, "Leyenda: 3 muestras")
	check(w.legend_hatch.stripes > 0 and w.legend_hatch.custom_minimum_size == Vector2(14, 8), "Muestra de daño previsto rayada (14×8)")
	check(cnear(w.legend_heal.color, Color(60 / 255.0, 207 / 255.0, 115 / 255.0, 0.45)), "Muestra de curación rgba(60,207,115,.45)")
	check(w.legend_dispel.color == T.RAID_DISPEL, "Muestra de purificable violeta")
	var legend_texts := []
	for item in w.legend_row.get_children():
		legend_texts.append(item.get_child(1).text)
	check(legend_texts == ["Daño previsto (3 s)", "Curación entrante", "Purificable"], "Textos de la leyenda")
	# Clic real sobre una celda
	var clicks := []
	w.member_clicked.connect(func(id: String, b: int, s: bool) -> void: clicks.append([id, b, s]))
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	w.get_card("dren")._gui_input(ev)
	await _frames(1)
	check(clicks == [["dren", MOUSE_BUTTON_LEFT, false]], "Clic izq. sobre la celda de Dren")
	check(int(r.get_member("dren")["hp_percent"]) == 45 and w.get_card("dren").status_text() == "45 %", "La celda se refresca tras la curación (45 %)")
	check(w.get_card("dren").border_state() == "selected" and w.get_card("nox").border_state() == "normal", "El cian pasa a Dren")
	var ev2 := InputEventMouseButton.new()
	ev2.button_index = MOUSE_BUTTON_LEFT
	ev2.pressed = true
	ev2.shift_pressed = true
	w.get_card("joao")._gui_input(ev2)
	await _frames(1)
	check(not w.get_card("joao").has_diamond() and w.get_card("joao").hp_color() == T.RAID_HEALTH, "Shift+clic sobre Joao quita el rombo")
	check(w.click_member("pim", MOUSE_BUTTON_RIGHT) and w.get_card("pim").shield_rect().size.x > 0.0, "Clic der. sobre Pim dibuja la franja de escudo")
	check(near(w.get_card("pim").shield_rect().size.y, 3.0), "Franja de escudo de 3 px")
	check(not w.click_member("nadie"), "click_member de un desconocido")
	# Banda de 10
	check(w.set_raid_size(10), "set_raid_size(10)")
	await _frames(2)
	check(w.visible_card_count() == 10 and w.column_count() == 2, "Banda de 10: 10 celdas en 2 columnas")
	check(w.header_label.text == "RAID · 10", "Cabecera «RAID · 10»")
	check(w.get_card("mira") == null and w.get_card("lune") != null, "Grupos 3 y 4 ocultos")
	check(not w.click_member("mira"), "No se puede clicar a quien no está en la banda")
	w.set_raid_size(20)
	await _frames(2)
	check(w.visible_card_count() == 20 and w.column_count() == 4, "De vuelta a 20")
	var rc: int = w.refresh_count
	r.set_member_distance("kael", 50)
	check(w.refresh_count > rc and w.get_card("kael").status_text() == "50 m", "La ventana se refresca con la señal changed")
	_free(w)
	_free(r)
	await _frames(1)


# --------------------------------------------------------------------------
# 14. Ventana: barra del jefe
# --------------------------------------------------------------------------
func _test_window_boss() -> void:
	print("-- 14. RaidHUDWindow: barra de jefe, fase y 43 %")
	var r := _svc()
	var w = _window(r)
	await _frames(3)
	check(w.boss_name_label.text == "Coloso de Runavell", "Nombre del jefe")
	check(w.boss_name_label.get_theme_font_size("font_size") == 17, "Nombre a 17 px")
	check(w.boss_phase_label.text == "Fase 2", "Badge «Fase 2»")
	check(w.boss_phase_label.get_theme_color("font_color") == Color("#f5c35b"), "Fase en #f5c35b")
	check(w.boss_timer_label.text == "04:12", "Temporizador «04:12»")
	check(vnear(w.boss_box.position, Vector2(470, 20)), "Bloque del jefe en x 470, y 20")
	check(near(w.boss_box.size.x, 500.0), "500 px de ancho (470 … 970)")
	check(near(w.boss_bar.size.y, 14.0), "Barra de 14 px")
	check(near(w.boss_bar.ratio, 0.43), "Barra al 43 %")
	check(near(w.boss_bar.fill_width(), 215.0, 0.5), "Relleno de 215 px")
	check(w.boss_bar.fill == Color("#e25555"), "Relleno #e25555")
	check(cnear(w.boss_bar.track, Color(7 / 255.0, 10 / 255.0, 12 / 255.0, 0.9)), "Pista rgba(7,10,12,.9)")
	check(w.boss_bar.text == "43 %" and w.boss_bar.text_size == 12, "«43 %» centrado a 12 px")
	var tx: float = w.boss_timer_label.position.x + w.boss_timer_label.size.x
	check(near(tx, 500.0, 1.0), "El temporizador queda alineado a la derecha")
	r.damage_boss(13)
	await _frames(1)
	check(w.boss_phase_label.text == "Fase 3" and w.boss_bar.text == "30 %", "Tras el daño: «Fase 3» y «30 %»")
	r.tick(12.0)
	check(w.boss_timer_label.text == "04:00", "El temporizador avanza («04:00»)")
	r.tick(240.0)
	check(w.boss_timer_label.text == "00:00" and w.boss_timer_label.get_theme_color("font_color") == T.RAID_AGGRO, "Enrage: «00:00» en rojo")
	_free(w)
	_free(r)
	await _frames(1)


# --------------------------------------------------------------------------
# 15. Ventana: alerta táctica
# --------------------------------------------------------------------------
func _test_window_alert() -> void:
	print("-- 15. RaidHUDWindow: alerta táctica central y cuenta atrás")
	var r := _svc()
	var w = _window(r)
	await _frames(3)
	check(w.alert_panel.visible, "Alerta visible")
	check(w.alert_title.text == "Todos a la izquierda", "«Todos a la izquierda»")
	check(w.alert_title.get_theme_font_size("font_size") == 26, "Título a 26 px")
	check(w.alert_subtitle.text == "Terremoto rúnico · también suena desde la derecha", "Descripción del terremoto")
	check(w.alert_subtitle.get_theme_color("font_color") == Color("#ffc9c9"), "Descripción en #ffc9c9")
	check(w.alert_count.text == "3", "Número gigante «3»")
	check(w.alert_count.get_theme_font_size("font_size") == 44 and w.alert_count.get_theme_color("font_color") == Color("#ff8a8a"), "«3» a 44 px en #ff8a8a")
	check(w.alert_arrow.visible and w.alert_arrow.arrow_rotation == 0.0, "Flecha hacia la izquierda")
	check(w.alert_arrow.color == Color("#ffb3b3") and w.alert_arrow.size == Vector2(40, 40), "Flecha 40×40 en #ffb3b3")
	check(near(w.alert_panel.position.y, 170.0), "Alerta en y 170")
	check(near(w.alert_panel.position.x + w.alert_panel.size.x * 0.5, 720.0, 1.0), "Centrada en X")
	var sb: StyleBoxFlat = w.alert_panel.get_theme_stylebox("panel")
	check(sb != null and sb.border_color == Color("#ff6b6b") and sb.border_width_left == 2, "Borde #ff6b6b de 2 px")
	check(sb != null and cnear(sb.bg_color, T.RAID_ALERT_BG), "Fondo rgba(58,29,34,.92)")
	check(sb != null and sb.corner_radius_top_left == 16 and sb.content_margin_left == 26 and sb.content_margin_top == 14, "Radio 16 y padding 14 · 26")
	check(sb != null and sb.shadow_size >= 20 and sb.shadow_offset.y == 10.0, "Sombra profunda (0 10 40)")
	check(w.alert_panel.mouse_filter == Control.MOUSE_FILTER_IGNORE, "La alerta no bloquea clics")
	r.tick(1.0)
	check(w.alert_count.text == "2", "Cuenta atrás «2»")
	r.tick(1.0)
	check(w.alert_count.text == "1", "Cuenta atrás «1»")
	r.tick(1.0)
	check(not w.alert_panel.visible, "Se oculta al terminar")
	r.trigger_alert("Separaos", "Orbes de runa", 4.0, "left")
	await _frames(1)
	check(w.alert_panel.visible and w.alert_title.text == "Separaos" and w.alert_count.text == "4", "Nueva alerta «Separaos» con «4»")
	check(near(w.alert_arrow.arrow_rotation, PI), "Flecha hacia la derecha")
	check(near(w.alert_panel.position.x + w.alert_panel.size.x * 0.5, 720.0, 1.0), "Sigue centrada con otro texto")
	r.trigger_alert("Quietos", "", 2.0, "center")
	await _frames(1)
	check(not w.alert_subtitle.visible and not w.alert_arrow.visible, "Sin subtítulo ni dirección: se ocultan")
	r.clear_alert()
	check(not w.alert_panel.visible, "clear_alert() la oculta")
	_free(w)
	_free(r)
	await _frames(1)


# --------------------------------------------------------------------------
# 16. Ventana: consola compacta del sanador
# --------------------------------------------------------------------------
func _test_window_console() -> void:
	print("-- 16. RaidHUDWindow: consola inferior compacta, maná y 10 ranuras")
	var r := _svc()
	var w = _window(r)
	await _frames(3)
	check(w.console_shape.points() == PackedVector2Array([Vector2(380, 811), Vector2(420, 690), Vector2(1020, 690), Vector2(1060, 811)]), "Trapecio del HUD v2 (380/420/1020/1060)")
	check(w.console_shape.bounds() == Rect2(380, 690, 680, 121), "Trapecio de 680 × 121")
	check(w.console_shape.mouse_filter == Control.MOUSE_FILTER_IGNORE, "El trapecio no bloquea clics")
	check(vnear(w.console_box.position, Vector2(453, 724)), "Consola en x 453 (bottom 16)")
	check(near(w.console_box.size.x, 534.0), "534 px de ancho")
	check(near(w.console_box.position.y + w.console_box.size.y, 794.0, 0.5), "Termina a 16 px del borde inferior")
	check(near(w.hp_meter.ratio, 0.88) and w.hp_meter.fill == Color("#3ccf73"), "Vida 88 % en verde")
	check(near(w.mana_meter.ratio, 0.52) and w.mana_meter.fill == Color("#3f82f2"), "Maná 52 % en azul")
	check(w.mana_meter.text == "Maná 52 % · dura ~1:40 a este ritmo", "Texto predictivo de maná")
	check(near(w.hp_meter.size.y, 14.0) and near(w.mana_meter.size.y, 14.0), "Barras de 14 px")
	check(near(w.hp_meter.size.x, 265.0, 0.5) and near(w.mana_meter.size.x, 265.0, 0.5), "Dos barras de 265 px (gap 4)")
	check(w.slots.size() == 10, "10 ranuras")
	var keys := ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
	var cds := ["", "", "", "6", "", "22", "", "1:40", "", ""]
	var x0: float = w.slots[0].position.x
	for i in 10:
		var s = w.slots[i]
		check(s.key == keys[i], "Ranura %d: tecla «%s»" % [i + 1, keys[i]])
		check(s.cooldown_text == cds[i], "Ranura %d: enfriamiento «%s»" % [i + 1, cds[i]])
		check(s.on_cooldown() == (cds[i] != ""), "Ranura %d: velo %s" % [i + 1, "activo" if cds[i] != "" else "inactivo"])
		check(s.size == Vector2(48, 48), "Ranura %d: 48×48" % (i + 1))
		check(near(s.position.x - x0, i * 54.0, 0.5), "Ranura %d: separación de 6 px" % (i + 1))
		check(s.bg == Color(r.ability(i)["color"]), "Ranura %d: color del seed" % (i + 1))
	check(w.slots[3].tooltip_text.contains("Purificar"), "Nombre de la habilidad en la ayuda")
	r.tick(6.0)
	check(w.slots[3].cooldown_text == "" and w.slots[5].cooldown_text == "16" and w.slots[7].cooldown_text == "1:34", "Los enfriamientos bajan con tick(6)")
	r.heal_target("dren")
	check(w.mana_meter.text == "Maná 48 % · dura ~1:32 a este ritmo", "Tras sanar: «Maná 48 % · dura ~1:32»")
	check(near(w.mana_meter.ratio, 0.48), "Barra de maná al 48 %")
	r.set_healer_hp(40)
	check(near(w.hp_meter.ratio, 0.40), "Vida del sanador al 40 %")
	_free(w)
	_free(r)
	await _frames(1)


# --------------------------------------------------------------------------
# 17. Coexistencia y transiciones de las 17 ventanas de UI v2.4
# --------------------------------------------------------------------------
func _test_coexistence() -> void:
	print("-- 17. Auditoría de coexistencia de las 17 ventanas de UI v2.4")
	var orch := root.get_node_or_null("UIOrchestrator")
	var router := root.get_node_or_null("UIInputRouter")
	var rs := root.get_node_or_null("RaidService")
	if orch == null or rs == null:
		check(false, "Autoloads disponibles")
		return
	rs.load_seed(SEED)
	check(COEXIST.size() + 1 == 17, "17 ventanas auditadas (16 + raid_hud)")
	for id in COEXIST:
		check(orch.registry.is_registered(id), "%s registrada" % id)
	var raid: Node = orch.open_raid_hud()
	await _frames(2)
	# Solapes internos del HUD de raid (px del escenario)
	var rects: Dictionary = raid.layout_rects()
	var names := ["boss", "alert", "raid", "console"]
	var full := Rect2(0, 0, 1440, 810)
	for a in names:
		check(rects[a].size.x > 0.0 and full.encloses(rects[a]), "Bloque %s dentro del lienzo 1440×810" % a)
	for i in names.size():
		for j in range(i + 1, names.size()):
			check(not rects[names[i]].intersects(rects[names[j]]), "Sin solape: %s / %s" % [names[i], names[j]])
	check(not rects["raid"].intersects(raid.console_shape.bounds()), "Los marcos de raid no invaden el trapecio")
	# Solo las celdas, ranuras y botones reciben el ratón
	var stoppers := 0
	var stack: Array = [raid]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Control and (n as Control).mouse_filter == Control.MOUSE_FILTER_STOP:
			stoppers += 1
		stack.append_array(n.get_children())
	check(stoppers == 20, "Solo las 20 celdas detienen el ratón (%d)" % stoppers)
	var raid_z: int = raid.z_index
	for id in COEXIST:
		var inst: Node = orch.open_window(id)
		await _frames(1)
		check(inst != null and orch.is_window_open(id), "%s se abre con el raid activo" % id)
		check(orch.is_raid_hud_open(), "%s: el HUD de raid sigue abierto" % id)
		check(orch.focus_manager.current_focus_id == id, "%s: recibe el foco" % id)
		check(orch.focus_manager.current_focus_id != "raid_hud", "%s: sin fuga de foco al raid" % id)
		if inst is CanvasItem:
			check((inst as CanvasItem).z_index > raid_z, "%s: por encima del HUD de raid" % id)
		orch.close_window(id)
		await _frames(1)
		check(not orch.is_window_open(id) and orch.is_raid_hud_open(), "%s: al cerrarla el raid sigue visible" % id)
	# Varias ventanas a la vez sobre el raid
	orch.open_window("inventory")
	orch.open_window("powers")
	await _frames(1)
	check(orch.is_window_open("inventory") and orch.is_window_open("powers") and orch.is_raid_hud_open(), "Inventario + Poderes + raid conviven")
	check(orch.focus_manager.current_focus_id == "powers", "El foco va a la última abierta")
	orch.focus_window("raid_hud")
	check(orch.focus_manager.current_focus_id == "powers" or orch.focus_manager.current_focus_id == "raid_hud", "focus_window sobre el HUD no rompe el gestor")
	orch.close_window("inventory")
	orch.close_window("powers")
	check(orch.is_raid_hud_open(), "El raid sobrevive al cierre de las demás")
	# Ctrl+R alterna aunque haya ventanas encima
	orch.open_window("map_window")
	await _frames(1)
	if router != null:
		check(router.handle_window_shortcut(_key(KEY_R, true), orch) and not orch.is_raid_hud_open(), "Ctrl+R cierra el raid con el Mapa abierto")
		check(orch.is_window_open("map_window") and orch.focus_manager.current_focus_id == "map_window", "El Mapa conserva el foco")
		check(router.handle_window_shortcut(_key(KEY_R, true), orch) and orch.is_raid_hud_open(), "Ctrl+R lo reabre")
	orch.close_window("map_window")
	# Flujo de entrada: bloquea Ctrl+R
	orch.open_window("launcher")
	await _frames(1)
	check(orch.is_entry_flow_active(), "Launcher activo (flujo de entrada)")
	if router != null:
		check(not router.handle_window_shortcut(_key(KEY_R, true), orch), "Ctrl+R bloqueado durante el flujo de entrada")
		check(orch.is_raid_hud_open(), "El raid no cambia durante el flujo de entrada")
	orch.close_window("launcher")
	await _frames(1)
	check(not orch.is_entry_flow_active(), "Flujo de entrada cerrado")
	# Cierre global
	orch.close_all_windows()
	await _frames(2)
	check(not orch.is_raid_hud_open(), "close_all_windows cierra el raid")
	var leaked := 0
	for id in orch.registry.get_all_instance_ids():
		var inst = orch.registry.get_instance(id)
		if inst != null and inst.visible:
			leaked += 1
	check(leaked == 0, "Ninguna ventana queda visible tras close_all_windows")
	check(orch.open_raid_hud() != null and orch.is_raid_hud_open(), "El raid se puede volver a abrir tras liberar")
	orch.close_all_windows()
	await _frames(2)
