extends SceneTree
## Suite headless (UI v2.4 Paso 10): Equipo e inventario [C] — paperdoll, 16 estadísticas con
## deltas ▲/▼, conjuntos F1-F3, mochila con filtros/búsqueda y bolsa segura.
## Run: Godot --headless --path clients/godot-mmo-client -s tests/unit/test_equipment_window.gd
## Exit code 0 = todo PASS.

const ES = preload("res://shared-core/EquipmentService.gd")
const COM = preload("res://shared-core/CommerceService.gd")
const T = preload("res://ui/tokens/hud_tokens.gd")
const WindowScene = preload("res://ui/windows/EquipmentWindow/EquipmentWindow.tscn")
const SEED := "res://config/equipment/equipment_seed.json"

const MIN_CHECKS := 150
const GREEN := Color("#4fe39a")
const RED := Color("#ff4d4d")

var _fails: Array[String] = []
var _checks := 0


class FakeOrchestrator extends Node:
	var registry: Node
	var toggled: Array[String] = []

	func toggle_window(id: String, _params: Dictionary = {}) -> void:
		toggled.append(id)


func check(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_fails.append(msg)
		printerr("  FAIL: ", msg)
	else:
		print("  PASS: ", msg)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("== [TEST] Paso 10: Equipo e inventario [C] ==")
	await _test_registry_and_shortcut()
	await _test_menu_opens_window()
	_test_seed_model()
	_test_item_level()
	_test_stat_totals()
	_test_equip_unequip_model()
	await _test_window_layout_and_stats()
	await _test_window_paperdoll_and_drag()
	await _test_comparison()
	_test_sets_model()
	await _test_sets_window()
	_test_backpack_filters_model()
	await _test_backpack_window()
	check(_checks >= MIN_CHECKS, "Se ejecutaron todas las comprobaciones (%d >= %d)" % [_checks, MIN_CHECKS])
	print("== %d checks, %d fallos ==" % [_checks, _fails.size()])
	if _fails.is_empty():
		print("RESULTADO: 100% PASS")
		quit(0)
	else:
		for f in _fails:
			printerr("  - ", f)
		quit(1)


# --------------------------------------------------------------------------
# Utilidades
# --------------------------------------------------------------------------
func _key(code: int, ctrl := false) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	ev.ctrl_pressed = ctrl
	return ev


func _frames(n: int = 2) -> void:
	for i in n:
		await process_frame


func _new_service() -> Node:
	var s: Node = ES.new()
	s.load_seed(SEED)
	return s


func _new_window(svc: Node = null) -> Control:
	var w = WindowScene.instantiate()
	w.service = svc if svc else _new_service()
	var com: Node = COM.new()
	com.load_seed()
	w.commerce = com
	root.add_child(w)
	return w


func _free(n) -> void:
	if is_instance_valid(n):
		if n is Node and (n as Node).is_inside_tree():
			(n as Node).queue_free()
		else:
			n.free()


func _seed() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(SEED))


func _seed_items() -> Dictionary:
	var d := {}
	for it in _seed()["items"]:
		d[it["id"]] = it
	return d


# --------------------------------------------------------------------------
# 1. UIWindowRegistry: "inventory" [C] + compatibilidad
# --------------------------------------------------------------------------
func _test_registry_and_shortcut() -> void:
	print("-- 1. UIWindowRegistry: inventory [C], almacén clásico y UIInputRouter")
	var Registry = load("res://ui/orchestration/UIWindowRegistry.gd")
	var UITypes = load("res://ui/types/UITypes.gd")
	var reg: Node = Registry.new()
	check(reg.is_registered("inventory"), "Registrada: inventory")
	var meta = reg.get_metadata("inventory")
	check(meta != null and meta.scene_path == "res://ui/windows/EquipmentWindow/EquipmentWindow.tscn", "inventory -> EquipmentWindow.tscn")
	check(meta != null and ResourceLoader.exists(meta.scene_path), "La escena de EquipmentWindow existe")
	check(meta != null and meta.category == UITypes.WindowCategory.GAME_WINDOW, "inventory es GAME_WINDOW")
	check(reg.get_shortcut_keys("inventory") == [KEY_C], "inventory declara el atajo [KEY_C]")
	check(reg.get_window_for_key(KEY_C) == "inventory", "KEY_C -> inventory")
	check(reg.get_window_for_key(KEY_N) == "powers" and reg.get_window_for_key(KEY_L) == "quests_window", "N y L siguen en Poderes y Misiones")
	check(reg.is_registered("inventory_stash") and reg.get_metadata("inventory_stash").scene_path == "res://ui/windows/InventoryWindow/secure_slots_ui.tscn", "Almacén clásico disponible como inventory_stash")
	check(reg.resolve_route("inventory", {}) == "inventory", "inventory sin parámetros -> Equipo")
	check(reg.resolve_route("inventory", {"character_id": "c1"}) == "inventory", "inventory con character_id (sin contexto Refugio) -> Equipo")
	check(reg.resolve_route("inventory", {"is_shelter_context": true}) == "inventory_stash", "Compat: inventory + is_shelter_context (Refugio/Vendedor) -> almacén clásico")
	check(reg.resolve_route("inventory", {"is_shelter_context": false}) == "inventory", "is_shelter_context=false no enruta")
	check(reg.get_route_targets("inventory") == ["inventory_stash"], "Rutas declaradas de inventory")

	var router: Node = load("res://ui/orchestration/UIInputRouter.gd").new()
	var orch := FakeOrchestrator.new()
	orch.registry = reg
	check(router.handle_window_shortcut(_key(KEY_C), orch) and orch.toggled == ["inventory"], "UIInputRouter: [C] abre/cierra inventory")
	orch.toggled.clear()
	check(not router.handle_window_shortcut(_key(KEY_C, true), orch) and orch.toggled.is_empty(), "Ctrl+C no abre el Equipo")
	check(str(ProjectSettings.get_setting("autoload/EquipmentService", "")) == "*res://shared-core/EquipmentService.gd", "Autoload EquipmentService registrado")
	check(root.get_node_or_null("EquipmentService") != null and root.get_node("EquipmentService").get_item_level() > 0, "Autoload EquipmentService cargó su seed")
	router.free()
	orch.free()
	reg.free()
	await process_frame


# --------------------------------------------------------------------------
# 2. Menú común: pestaña Equipo [C] abre la ventana (UIOrchestrator real)
# --------------------------------------------------------------------------
func _test_menu_opens_window() -> void:
	print("-- 2. Menú común: pestaña Equipo [C] -> inventory")
	var bar = load("res://ui/menu/menu_bar.tscn").instantiate()
	root.add_child(bar)
	await process_frame
	var tab: Dictionary = bar.get_tab("equipo")
	check(str(tab.get("window", "")) == "inventory" and int(tab.get("key", 0)) == KEY_C, "Pestaña Equipo -> inventory con tecla C")
	var nav: Array = []
	bar.navigation_requested.connect(func(w: String, _p: Dictionary) -> void: nav.append(w))
	check(bar.handle_shortcut(_key(KEY_C)) and nav == ["inventory"], "Menú: [C] navega a inventory")

	var orch: Node = root.get_node_or_null("UIOrchestrator")
	check(orch != null, "UIOrchestrator (autoload) disponible")
	if orch == null:
		bar.queue_free()
		return
	orch.close_window("inventory", true)
	await process_frame
	orch.connect_menu_bar(bar)
	bar.select_tab("equipo")
	await _frames()
	check(orch.is_window_open("inventory"), "Pestaña Equipo abre la ventana inventory")
	var inst = orch.get_window_instance("inventory")
	check(inst != null and inst.get_script() == load("res://ui/windows/EquipmentWindow/EquipmentWindow.gd"), "La instancia es EquipmentWindow")
	check(inst != null and inst.window_id == "inventory" and inst.menu_bar.active_tab == "equipo", "La ventana marca la pestaña Equipo en su propio menú")
	check(inst != null and inst.stat_rows.size() == 16, "La ventana abierta muestra las 16 estadísticas")
	bar.select_tab("equipo")
	await process_frame
	check(not orch.is_window_open("inventory"), "Pulsar Equipo otra vez la cierra (toggle)")
	var router: Node = load("res://ui/orchestration/UIInputRouter.gd").new()
	check(router.handle_window_shortcut(_key(KEY_C), orch) and orch.is_window_open("inventory"), "[C] con UIOrchestrator real la abre")
	check(router.handle_window_shortcut(_key(KEY_C), orch) and not orch.is_window_open("inventory"), "[C] la cierra")
	router.free()

	# Compatibilidad: llamadas antiguas a "inventory" desde el Refugio / Vendedor.
	orch.toggle_window("inventory", {"character_id": "", "is_shelter_context": true})
	await _frames()
	var stash = orch.get_window_instance("inventory_stash")
	check(stash != null and stash.visible, "toggle_window(inventory, is_shelter_context) abre el almacén clásico")
	check(orch.get_window_instance("inventory") == null or not orch.get_window_instance("inventory").visible, "…sin abrir la ventana de Equipo")
	check(orch.is_window_open("inventory"), "is_window_open(inventory) cubre el almacén enrutado (Vendedor no lo duplica)")
	check(stash != null and stash.is_in_group("inventory_ui"), "El almacén sigue en el grupo inventory_ui")
	orch.close_window("inventory")
	await process_frame
	check(stash == null or not stash.visible, "close_window(inventory) también cierra el almacén (muerte del jugador)")
	orch.close_window("inventory", true)
	orch.close_window("inventory_stash", true)
	bar.queue_free()
	await _frames()


# --------------------------------------------------------------------------
# 3. Modelo: seed
# --------------------------------------------------------------------------
func _test_seed_model() -> void:
	print("-- 3. EquipmentService: seed")
	var s := _new_service()
	check(s.character["name"] == "Aren" and s.character["class"] == "Tejedor de grietas" and s.character["level"] == 32, "Personaje Aren · Tejedor de grietas · nivel 32")
	check(ES.SLOT_ORDER.size() == 13, "13 ranuras de paperdoll")
	var names: Array = ES.SLOT_ORDER.map(func(x: String) -> String: return ES.slot_name(x))
	for n in ["Cabeza", "Cuello", "Hombros", "Pecho", "Cintura", "Piernas", "Pies", "Muñecas", "Manos", "Anillo 1", "Anillo 2", "Arma principal", "Arma secundaria"]:
		check(names.has(n), "Ranura «%s»" % n)
	check(ES.LEFT_SLOTS.size() + ES.RIGHT_SLOTS.size() == 13, "Ranuras a ambos lados del avatar (7 + 6)")
	check(s.get_equipped_count() == 13, "13 piezas equipadas en el seed")
	check(s.backpack.size() == 18 and s.backpack_capacity == 40, "Mochila 18 / 40")
	check(s.secure.size() == 2 and s.secure_capacity == 3, "Bolsa segura 2 / 3")
	check(s.get_set_ids() == ["damage", "tank", "gathering"], "Conjuntos damage · tank · gathering")
	check(s.active_set == "damage", "Conjunto activo: damage")
	for r in ES.RARITY_ORDER:
		check(ES.RARITIES.has(r) and ES.rarity_color(r) != Color(0, 0, 0, 0), "Rareza %s con color" % r)
	s.free()


# --------------------------------------------------------------------------
# 4. iLvl promedio exacto
# --------------------------------------------------------------------------
func _test_item_level() -> void:
	print("-- 4. Nivel de objeto = suma(nivel) / ranuras equipadas")
	var s := _new_service()
	var items := _seed_items()
	var total := 0
	var n := 0
	for slot in _seed()["equipped"]:
		total += int(items[_seed()["equipped"][slot]]["item_level"])
		n += 1
	check(total == 5356 and n == 13, "Seed: suma 5356 en 13 ranuras")
	check(is_equal_approx(s.get_item_level_exact(), 412.0) and s.get_item_level() == 412, "iLvl 5356 / 13 = 412")
	check(s.unequip("off_hand"), "Quitar arma secundaria (424)")
	check(is_equal_approx(s.get_item_level_exact(), 4932.0 / 12.0) and s.get_item_level() == 411, "iLvl 4932 / 12 = 411")
	check(s.unequip("main_hand"), "Quitar arma principal (424)")
	check(is_equal_approx(s.get_item_level_exact(), 4508.0 / 11.0) and s.get_item_level() == 409, "iLvl 4508 / 11 = 409,82 -> 409")
	check(s.equip("anillo_deriva", "ring_1")["ok"], "Equipar Anillo de la deriva (420) en vez del Anillo del umbral (404)")
	check(is_equal_approx(s.get_item_level_exact(), 4524.0 / 11.0), "iLvl recalculado tras el cambio (4524 / 11)")
	for slot in ES.SLOT_ORDER:
		s.unequip(slot)
	check(s.get_equipped_count() == 0 and s.get_item_level_exact() == 0.0 and s.get_item_level() == 0, "Sin nada equipado iLvl = 0 (sin dividir entre 0)")
	s.free()


# --------------------------------------------------------------------------
# 5. Suma de estadísticas
# --------------------------------------------------------------------------
func _test_stat_totals() -> void:
	print("-- 5. 16 estadísticas: base + piezas equipadas")
	var s := _new_service()
	var data := _seed()
	var items := _seed_items()
	var expected := {}
	for k in T.STAT_KEYS:
		expected[k] = float(data["base_stats"].get(k, 0))
	for slot in data["equipped"]:
		var st: Dictionary = items[data["equipped"][slot]].get("stats", {})
		for k in st:
			expected[k] += float(st[k])
	var totals: Dictionary = s.get_total_stats()
	check(totals.size() == 16, "Totales con las 16 claves canónicas")
	for k in T.STAT_KEYS:
		check(is_equal_approx(float(totals[k]), float(expected[k])), "%s = %s" % [k, str(expected[k])])
	check(is_equal_approx(totals["dano"], 502.0), "Daño 120 + 40 + 102 + 180 + 60 = 502")
	check(is_equal_approx(totals["armadura"], 598.0), "Armadura 140 + 60 + 45 + 110 + 25 + 70 + 20 + 30 + 98 = 598")
	check(is_equal_approx(totals["celeridad"], 9.7), "Celeridad 4 + 3 + 2,7 = 9,7 %")
	var gear: Dictionary = s.get_gear_stats()
	check(is_equal_approx(gear["dano"], 382.0) and is_equal_approx(gear["velmov"], 30.0), "Solo piezas: daño 382 · vel. mov. 30")
	check(totals["penmag"] == 0.0 and totals["omni"] == 0.0 and totals["curacion"] == 0.0, "Pen. mágica, omnivampirismo y curación a 0")
	s.unequip("main_hand")
	check(is_equal_approx(s.get_total_stats()["dano"], 322.0), "Quitar la Hoja de la grieta resta 180 de daño")
	check(ES.format_stat("dano", 1842.0) == "1.842" and ES.format_stat("celeridad", 5.8) == "5,8 %" and ES.format_stat("critico", 0.0) == "0 %", "Formato: 1.842 · 5,8 % · 0 %")
	s.free()


# --------------------------------------------------------------------------
# 6. Equipar / desequipar (modelo)
# --------------------------------------------------------------------------
func _test_equip_unequip_model() -> void:
	print("-- 6. Paperdoll: equipar y desequipar en ranuras válidas")
	var s := _new_service()
	var changed: Array = []
	s.equipment_changed.connect(func(slot: String) -> void: changed.append(slot))
	check(s.equip("anillo_deriva", "head")["reason"] == "invalid_slot", "Un anillo no entra en Cabeza")
	check(s.equip("pocion_vida")["reason"] == "not_equippable", "Una poción no se equipa")
	check(s.equip("no_existe")["reason"] == "unknown_item", "Objeto desconocido rechazado")
	check(s.valid_slots_for("anillo_deriva") == ["ring_1", "ring_2"], "Anillos: Anillo 1 y Anillo 2")
	check(s.default_slot_for("anillo_deriva") == "ring_1", "Por defecto reemplaza el anillo de menor nivel (Umbral 404)")
	var bi: int = s.backpack.find("anillo_deriva")
	var r: Dictionary = s.equip("anillo_deriva", "ring_1")
	check(r["ok"] and r["replaced_id"] == "anillo_umbral", "Equipar Anillo de la deriva en Anillo 1")
	check(s.equipped["ring_1"] == "anillo_deriva" and s.backpack[bi] == "anillo_umbral", "Intercambio: el anillo viejo ocupa su casilla de la mochila")
	check(changed.has("ring_1"), "equipment_changed(ring_1)")
	check(not s.get_item("anillo_deriva")["new"], "Al equiparlo deja de ser «nuevo»")
	check(s.equip("anillo_deriva", "ring_2")["ok"] and s.equipped["ring_2"] == "anillo_deriva" and s.equipped["ring_1"] == "sello_tejedor", "Mover entre Anillo 1 y Anillo 2 intercambia")
	var size0: int = s.backpack.size()
	check(s.unequip("head") and s.equipped["head"] == "" and s.backpack.size() == size0 + 1 and s.backpack.has("yelmo_grieta"), "Desequipar Cabeza: vuelve a la mochila")
	check(not s.unequip("head"), "Desequipar una ranura vacía no hace nada")
	check(s.equip("yelmo_bastion")["ok"] and s.equipped["head"] == "yelmo_bastion" and s.backpack.size() == size0, "Equipar en ranura vacía saca el objeto de la mochila")
	check(s.equip("nucleo_grieta")["reason"] == "not_equippable", "Material de la bolsa segura no se equipa")
	# Mochila llena: no se puede quitar nada.
	s.backpack_capacity = s.backpack.size()
	check(not s.unequip("chest") and s.equipped["chest"] == "coraza_tejida", "Mochila llena: no se puede desequipar")
	s.backpack_capacity = 40
	check(s.move_to_secure("anillo_umbral") and s.is_secure("anillo_umbral"), "Mochila -> bolsa segura")
	check(not s.move_to_secure("cristal_vacio"), "Bolsa segura llena (3/3)")
	var lost: Array = s.preview_death_loss(true)
	check(not lost.has("anillo_umbral") and not lost.has("nucleo_grieta") and lost.has("cristal_vacio"), "Al morir en zona peligrosa la bolsa segura se conserva")
	check(s.preview_death_loss(false).is_empty(), "En zona segura no se pierde nada")
	check(s.equip("anillo_umbral", "ring_1")["ok"] and s.secure.has("sello_tejedor"), "Equipar desde la bolsa segura: el reemplazado ocupa su hueco")
	check(s.move_from_secure("sello_tejedor") and s.backpack.has("sello_tejedor"), "Bolsa segura -> mochila")
	s.free()


# --------------------------------------------------------------------------
# 7. Ventana: layout, cabecera, 16 stat_row, monedas
# --------------------------------------------------------------------------
func _test_window_layout_and_stats() -> void:
	print("-- 7. Ventana: personaje, iLvl, 16 estadísticas y monedas")
	var w := _new_window()
	await _frames()
	check(w.window_id == "inventory" and w.menu_bar.active_tab == "equipo", "Ventana inventory con la pestaña Equipo activa")
	check(w.name_label.text == "Aren" and w.subtitle_label.text == "Nivel 32 · Tejedor de grietas", "Cabecera: Aren · Nivel 32 · Tejedor de grietas")
	check(w.ilvl_label.text == "412", "Nivel de objeto 412")
	check(w.ilvl_label.get_theme_color("font_color") == Color("#46e3c1"), "iLvl en #46e3c1")
	var page: Node = w.content.get_node("Page")
	check(page.get_child_count() == 3 and page.get_child(0).name == "CharacterCard" and page.get_child(1).name == "StatsCard" and page.get_child(2).name == "BackpackCard", "3 columnas: Personaje · Estadísticas · Mochila")
	check(w.doll_slots.size() == 13, "Paperdoll con 13 ranuras")
	check(w.avatar != null and w.avatar.hint.text.contains("Arrastra para girar"), "Visor del personaje con indicador de arrastre")
	var yaw0: float = w.avatar.yaw
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = true
	w.avatar._gui_input(mb)
	var mm := InputEventMouseMotion.new()
	mm.relative = Vector2(40, 0)
	w.avatar._gui_input(mm)
	check(not is_equal_approx(w.avatar.yaw, yaw0), "Arrastrar sobre el visor gira al personaje")
	check(w.stat_rows.size() == 16, "16 filas de estadística")
	var table: Node = w.content.find_child("StatTable", true, false)
	var order: Array = []
	for cell in table.get_children():
		var row = cell.get_child(0)
		order.append(row.stat_key)
		check(row.scene_file_path == "res://ui/components/base/stat_row.tscn", "Fila %s es instancia de stat_row.tscn" % row.stat_key)
	check(order == Array(T.STAT_KEYS), "Orden canónico del Anexo A")
	var row_d = w.get_stat_row("dano")
	check(row_d.value_label.text == "502" and row_d.name_label.text == "Daño de ataque", "Daño de ataque 502")
	check(w.get_stat_row("armadura").value_label.text == "598", "Armadura 598")
	check(w.get_stat_row("celeridad").value_label.text == "9,7 %", "Celeridad 9,7 %")
	check(w.get_stat_row("velmov").value_label.text == "365", "Vel. movimiento 335 + 30 = 365")
	for k in ["penmag", "omni", "curacion"]:
		var r = w.get_stat_row(k)
		check(r.value_label.get_theme_color("font_color") == Color("#7c8992"), "%s en cero atenuado a #7c8992 (%s)" % [k, r.value_label.text])
	check(row_d.value_label.get_theme_color("font_color") == T.TEXT, "Valores no nulos en color de texto normal")
	check(w.get_stat_row("dano").delta_label.text == "", "Sin hover no hay deltas")
	check(w.summary_chips.size() == 4 and w.summary_chips["dano"].value_label.text == "502", "Resumen con stat_chip (Daño 502)")
	check(w.gold_label.amount_label.text == "12.480" and w.prisms_label.amount_label.text == "340", "Pie: Oro 12.480 · Prismas 340")
	check(w.gold_label.icon.get_layers()[0].get("fill", Color.BLACK) == Color("#f5c35b"), "Oro con icono #f5c35b")
	check(T.PRISMS == Color("#7ee8ff") and w.prisms_label.add_button.visible, "Prismas #7ee8ff con «+»")
	check(w.count_label.text == "18 / 40", "Contador de mochila 18 / 40")
	w.queue_free()
	await _frames()


# --------------------------------------------------------------------------
# 8. Ventana: paperdoll, rareza, arrastrar/soltar via InventoryController
# --------------------------------------------------------------------------
func _test_window_paperdoll_and_drag() -> void:
	print("-- 8. Ventana: paperdoll, bordes por rareza y arrastrar/soltar")
	var w := _new_window()
	await _frames()
	var svc: Node = w.service
	var ctrl: Node = root.get_node_or_null("InventoryController")
	check(ctrl != null and ctrl.has_method("request_equip") and ctrl.has_method("request_unequip"), "InventoryController expone request_equip/request_unequip")
	var moves: Array = []
	if ctrl:
		ctrl.equipment_move_completed.connect(func(iid, slot, ok) -> void: moves.append([iid, slot, ok]))
	var head = w.doll_slots["head"]
	check(head.item_id == "yelmo_grieta" and head.rarity_color == ES.rarity_color("epic"), "Cabeza: Yelmo de la grieta con borde épico")
	check(w.doll_slots["main_hand"].rarity_color == ES.rarity_color("legendary"), "Arma principal con borde legendario")
	check(w.doll_slots["waist"].get_border_color() == ES.rarity_color("uncommon"), "Cintura con borde poco común")
	var payload := {"type": "equipment_item", "item_id": "anillo_deriva", "source": "backpack", "slot": "", "index": 0}
	check(not head._can_drop_data(Vector2.ZERO, payload), "Drop: un anillo no se acepta en Cabeza")
	check(w.doll_slots["ring_2"]._can_drop_data(Vector2.ZERO, payload), "Drop: el anillo se acepta en Anillo 2")
	w.doll_slots["ring_2"]._drop_data(Vector2.ZERO, payload)
	check(svc.equipped["ring_2"] == "anillo_deriva" and w.doll_slots["ring_2"].item_id == "anillo_deriva", "Soltar en Anillo 2 lo equipa y refresca la ranura")
	check(moves.size() == 1 and moves[0] == ["anillo_deriva", "ring_2", true], "InventoryController emitió equipment_move_completed")
	check(svc.backpack.has("sello_tejedor"), "El Sello del tejedor vuelve a la mochila")
	# Ranura -> mochila (desequipar).
	var from_slot := {"type": "equipment_item", "item_id": "yelmo_grieta", "source": "slot", "slot": "head", "index": -1}
	var cell0 = w.grid_cells[0]
	check(cell0._can_drop_data(Vector2.ZERO, from_slot), "La mochila acepta piezas del paperdoll")
	cell0._drop_data(Vector2.ZERO, from_slot)
	check(svc.equipped["head"] == "" and svc.backpack[0] == "yelmo_grieta" and w.grid_cells[0].item_id == "yelmo_grieta", "Soltar en la mochila desequipa en esa casilla")
	check(w.doll_slots["head"].item_id == "" and w.ilvl_label.text == str(svc.get_item_level()), "Ranura vacía e iLvl actualizado")
	# Doble clic / clic derecho = equipar.
	w._on_cell_activated(w.grid_cells[0])
	check(svc.equipped["head"] == "yelmo_grieta", "Activar (doble clic) un objeto de la mochila lo equipa")
	w._on_cell_activated(w.doll_slots["feet"])
	check(svc.equipped["feet"] == "" and svc.backpack.has("botas_marea"), "Activar (clic derecho) una ranura la vacía")
	# Mochila -> bolsa segura.
	var idx: int = svc.filter_backpack().find("cristal_vacio")
	var to_secure := {"type": "equipment_item", "item_id": "cristal_vacio", "source": "backpack", "slot": "", "index": idx}
	check(w.secure_cells[2]._can_drop_data(Vector2.ZERO, to_secure), "La bolsa segura acepta objetos de la mochila")
	w.secure_cells[2]._drop_data(Vector2.ZERO, to_secure)
	check(svc.is_secure("cristal_vacio") and w.secure_cells[2].item_id == "cristal_vacio", "Objeto en la bolsa segura")
	check(not w.secure_cells[0]._can_drop_data(Vector2.ZERO, {"type": "equipment_item", "item_id": "lingote_hierro", "source": "backpack"}), "Bolsa segura llena: no acepta más")
	check(not cell0._can_drop_data(Vector2.ZERO, {"type": "inventory_item"}), "Payloads ajenos se rechazan")
	var drag = w.grid_cells[1]._get_drag_data(Vector2.ZERO)
	check(typeof(drag) == TYPE_DICTIONARY and drag["type"] == "equipment_item" and drag["source"] == "backpack" and drag["item_id"] == w.grid_cells[1].item_id, "Arrastrar desde la mochila genera el payload equipment_item")
	w.queue_free()
	await _frames()


# --------------------------------------------------------------------------
# 9. Comparación reactiva ▲/▼
# --------------------------------------------------------------------------
func _test_comparison() -> void:
	print("-- 9. Comparación de equipo: deltas ▲ verde / ▼ rojo al hacer hover")
	var s := _new_service()
	var c: Dictionary = s.compare_item("anillo_deriva")
	check(c["ok"] and c["slot"] == "ring_1" and c["replaced_id"] == "anillo_umbral", "Anillo de la deriva vs Anillo del umbral (ring_1)")
	check(is_equal_approx(c["deltas"]["celeridad"], 3.1), "Celeridad ▲ 3,1 %")
	check(is_equal_approx(c["deltas"]["dano"], 40.0), "Daño ▲ 40")
	check(is_equal_approx(c["deltas"]["critico"], 0.0), "Crítico = 0")
	check(is_equal_approx(c["deltas"]["armadura"], -38.0), "Armadura ▼ 38")
	check(c["deltas"].size() == 16, "Deltas para las 16 estadísticas")
	check(is_equal_approx(c["ilvl_after"], (5356.0 - 404.0 + 420.0) / 13.0), "iLvl simulado (5372 / 13)")
	check(s.equipped["ring_1"] == "anillo_umbral", "Comparar no equipa nada")
	var c2: Dictionary = s.compare_item("escudo_bastion")
	check(c2["replaced_id"] == "daga_vacio" and is_equal_approx(c2["deltas"]["armadura"], 160.0) and is_equal_approx(c2["deltas"]["dano"], -60.0), "Escudo de bastión vs Daga: armadura +160, daño -60")
	check(not s.compare_item("pocion_vida")["ok"], "Consumibles no se comparan")
	var u: Dictionary = s.compare_unequip("ring_2")
	check(u["ok"] and u["mode"] == "unequip" and is_equal_approx(u["deltas"]["poder"], -30.0) and is_equal_approx(u["deltas"]["robo"], -2.0), "Hover en ranura: quitar el Sello resta poder 30 y robo 2")
	s.free()

	var w := _new_window()
	await _frames()
	var changes: Array = []
	w.comparison_changed.connect(func(cmp: Dictionary) -> void: changes.append(cmp))
	var cell = null
	for cl in w.grid_cells:
		if cl.item_id == "anillo_deriva":
			cell = cl
	check(cell != null, "Anillo de la deriva visible en la mochila")
	w._on_cell_hover(cell)
	check(w.preview_item_id == "anillo_deriva" and changes.size() == 1, "Hover sobre la casilla activa la comparación")
	var rd = w.get_stat_row("dano")
	check(rd.delta_label.text == "▲ +40" and rd.delta_label.get_theme_color("font_color") == GREEN, "Daño «▲ +40» en #4fe39a")
	var ra = w.get_stat_row("armadura")
	check(ra.delta_label.text == "▼ -38" and ra.delta_label.get_theme_color("font_color") == RED, "Armadura «▼ -38» en #ff4d4d")
	var rc = w.get_stat_row("celeridad")
	check(rc.delta_label.text == "▲ +3,1 %" and rc.delta_label.get_theme_color("font_color") == GREEN, "Celeridad «▲ +3,1 %»")
	check(w.get_stat_row("critico").delta_label.text == "", "Crítico sin cambio: sin delta")
	check(rd.value_label.text == "502", "El valor actual se mantiene junto al delta")
	check(w.compare_title.text == "Anillo de la deriva" and w.compare_sub.text == "Contra lo que llevas: Anillo del umbral (404)", "Cabecera: Anillo de la deriva contra Anillo del umbral (404)")
	check(w.compare_title.get_theme_color("font_color") == ES.rarity_color("epic"), "Nombre en color de rareza épica")
	check(w.compare_ilvl.text.begins_with("Nv. obj. 412 → 413"), "iLvl 412 → 413 (%s)" % w.compare_ilvl.text)
	w._on_cell_unhover(cell)
	await _frames()
	check(w.preview_item_id == "" and w.get_stat_row("dano").delta_label.text == "", "Al salir del objeto desaparecen los deltas")
	# Hover sobre una ranura del paperdoll.
	w._on_cell_hover(w.doll_slots["ring_2"])
	var rp = w.get_stat_row("poder")
	check(rp.delta_label.text == "▼ -30" and rp.delta_label.get_theme_color("font_color") == RED, "Hover en Anillo 2: Poder «▼ -30»")
	check(w.compare_sub.text.begins_with("Si te quitas"), "Cabecera de quitar pieza")
	w.clear_preview()
	# E equipa lo que se compara.
	w.preview_item("escudo_bastion")
	check(w.get_stat_row("tenacidad").delta_label.text == "▲ +10 %", "Escudo: Tenacidad «▲ +10 %»")
	check(w.handle_key(_key(KEY_E)) and w.service.equipped["off_hand"] == "escudo_bastion", "[E] equipa el objeto en comparación")
	w.queue_free()
	await _frames()


# --------------------------------------------------------------------------
# 10. Conjuntos (modelo)
# --------------------------------------------------------------------------
func _test_sets_model() -> void:
	print("-- 10. Conjuntos: guardar y alternar F1/F2/F3")
	var s := _new_service()
	var damage_loadout: Dictionary = s.equipped.duplicate()
	check(s.set_for_key(KEY_F1) == "damage" and s.set_for_key(KEY_F2) == "tank" and s.set_for_key(KEY_F3) == "gathering", "F1 Daño · F2 Tanque · F3 Recolección")
	check(s.set_for_key(KEY_F4) == "", "F4 no es un conjunto")
	var r: Dictionary = s.handle_set_key(KEY_F2)
	check(r["ok"] and s.active_set == "tank", "F2 activa Tanque")
	check(s.equipped["head"] == "yelmo_bastion" and s.equipped["chest"] == "coraza_bastion" and s.equipped["off_hand"] == "escudo_bastion" and s.equipped["main_hand"] == "mandoble_hierro", "Tanque equipa yelmo, coraza, escudo y mandoble")
	check(r["equipped"].size() == 4 and r["missing"].is_empty(), "4 piezas cambiadas, ninguna falta")
	check(s.backpack.has("yelmo_grieta") and s.backpack.has("hoja_grieta"), "Las piezas de Daño vuelven a la mochila")
	check(is_equal_approx(s.get_total_stats()["armadura"], 598.0 - 60 - 110 + 90 + 190 + 160), "Armadura del Tanque recalculada")
	s.handle_set_key(KEY_F1)
	check(s.active_set == "damage" and s.equipped == damage_loadout, "F1 restaura exactamente el conjunto Daño")
	s.handle_set_key(KEY_F3)
	check(s.active_set == "gathering" and s.equipped["main_hand"] == "pico_ambar" and s.equipped["hands"] == "guantes_recolector" and s.equipped["feet"] == "botas_sendero" and s.equipped["neck"] == "amuleto_luz", "F3 equipa Recolección")
	s.handle_set_key(KEY_F1)
	# Guardar: cambiar un anillo y guardar en Daño.
	s.equip("anillo_deriva", "ring_1")
	check(s.save_set("damage") and s.get_set("damage")["slots"]["ring_1"] == "anillo_deriva", "Guardar Daño con el Anillo de la deriva")
	s.handle_set_key(KEY_F2)
	s.handle_set_key(KEY_F1)
	check(s.equipped["ring_1"] == "anillo_deriva", "Daño recuerda el anillo guardado")
	check(s.get_set("damage")["slots"].size() == 13, "Guardar captura las 13 ranuras")
	var sid: String = s.create_set("Jefe")
	check(sid != "" and s.get_set(sid)["name"] == "Jefe" and s.get_set(sid)["slots"].size() == 13 and s.active_set == sid, "«+» crea un conjunto nuevo con lo equipado")
	check(s.sets.size() == 4, "4 conjuntos")
	while s.sets.size() < ES.MAX_SETS:
		s.create_set()
	check(s.create_set() == "", "Máximo de %d conjuntos" % ES.MAX_SETS)
	s.get_set("tank")["slots"]["neck"] = "no_existe"
	var r2: Dictionary = s.apply_set("tank")
	check(r2["missing"] == ["no_existe"], "Piezas que ya no tienes se informan como faltantes")
	check(not s.apply_set("nope")["ok"], "Conjunto desconocido rechazado")
	s.free()


# --------------------------------------------------------------------------
# 11. Conjuntos (ventana)
# --------------------------------------------------------------------------
func _test_sets_window() -> void:
	print("-- 11. Ventana: selector de conjuntos F1/F2/F3 y «+»")
	var w := _new_window()
	await _frames()
	check(w.set_buttons.size() == 3 and w.add_set_button != null, "Chips Daño · Tanque · Recolección y «+»")
	check(w.set_buttons["damage"].text == "Daño  F1" and w.set_buttons["tank"].text == "Tanque  F2" and w.set_buttons["gathering"].text == "Recolección  F3", "Chips con su tecla F1/F2/F3")
	check(w.set_buttons["damage"].button_pressed and not w.set_buttons["tank"].button_pressed, "Daño activo")
	var applied: Array = []
	w.set_applied.connect(func(sid: String, _r: Dictionary) -> void: applied.append(sid))
	check(w.handle_key(_key(KEY_F2)), "F2 consumido por la ventana")
	await _frames()
	check(applied == ["tank"] and w.set_buttons["tank"].button_pressed and not w.set_buttons["damage"].button_pressed, "F2 cambia a Tanque y marca el chip")
	check(w.doll_slots["off_hand"].item_id == "escudo_bastion", "El paperdoll muestra el escudo")
	check(w.get_stat_row("armadura").value_label.text == T.format_amount(int(w.service.get_total_stats()["armadura"])), "Las estadísticas reflejan el Tanque")
	check(w.feedback_label.text == "Conjunto «Tanque» equipado · 4 piezas", "Aviso: Conjunto «Tanque» equipado · 4 piezas")
	check(w.ilvl_label.text == str(w.service.get_item_level()), "iLvl del Tanque")
	w.set_buttons["damage"].emit_signal("pressed")
	await _frames()
	check(w.service.active_set == "damage" and w.doll_slots["off_hand"].item_id == "daga_vacio", "Clic en Daño vuelve al conjunto Daño")
	w.add_set_button.emit_signal("pressed")
	await _frames()
	check(w.set_buttons.size() == 4 and w.service.sets.size() == 4, "«+» añade un chip de conjunto nuevo")
	w.handle_key(_key(KEY_F1))
	w.service.equip("anillo_deriva", "ring_1")
	check(w.save_active_set() and w.service.get_set("damage")["slots"]["ring_1"] == "anillo_deriva", "Guardar desde la ventana")
	var ctrl_f2 := _key(KEY_F2, true)
	check(not w.handle_key(ctrl_f2), "Ctrl+F2 no cambia de conjunto")
	w.queue_free()
	await _frames()


# --------------------------------------------------------------------------
# 12. Mochila: filtros y búsqueda (modelo)
# --------------------------------------------------------------------------
func _test_backpack_filters_model() -> void:
	print("-- 12. Mochila: filtros por categoría y búsqueda")
	var s := _new_service()
	check(ES.FILTERS.map(func(f) -> String: return f["label"]) == ["Todo", "Armas", "Armaduras", "Consumibles", "Materiales"], "Filtros Todo · Armas · Armaduras · Consumibles · Materiales")
	check(s.count_for_filter("all") == 18, "Todo: 18")
	check(s.filter_backpack("weapon") == ["mandoble_hierro", "baculo_pulso", "escudo_bastion", "pico_ambar"], "Armas: 4")
	check(s.count_for_filter("armor") == 6, "Armaduras: 6")
	check(s.filter_backpack("consumable") == ["pocion_vida", "elixir_celeridad", "racion_viaje"], "Consumibles: 3")
	check(s.filter_backpack("material") == ["cristal_vacio", "lingote_hierro", "fibra_savia", "fragmento_runa"], "Materiales: 4")
	check(s.filter_backpack("all", "anillos con celeridad") == ["anillo_deriva"], "«anillos con celeridad» -> Anillo de la deriva")
	check(s.filter_backpack("all", "pocion") == ["pocion_vida"] and s.filter_backpack("all", "POCIÓN") == ["pocion_vida"], "Búsqueda sin tildes ni mayúsculas")
	check(s.filter_backpack("all", "bastión").size() == 3, "«bastión» -> 3 piezas")
	check(s.filter_backpack("weapon", "bastion") == ["escudo_bastion"], "Filtro + búsqueda combinados")
	check(s.filter_backpack("all", "épico").size() == s.filter_backpack("all").filter(func(i): return s.get_item(i)["rarity"] == "epic").size(), "Búsqueda por rareza")
	check(s.filter_backpack("all", "penetracion magica") == ["baculo_pulso"], "Búsqueda por estadística")
	check(s.filter_backpack("all", "zzz").is_empty(), "Sin resultados")
	check(s.filter_backpack("all", "   ").size() == 18, "Búsqueda vacía = todo")
	s.sort_backpack()
	check(s.get_item(s.backpack[0])["category"] == "weapon" and s.get_item(s.backpack[s.backpack.size() - 1])["category"] == "quest", "Ordenar [R]: armas primero, misión al final")
	check(s.move_in_backpack("carta_torin", 0) and s.backpack[0] == "carta_torin", "Reordenar dentro de la mochila")
	var added: Array = s.ingest_inventory_items([
		{"id": "srv_1", "item_name": "Hacha del servidor", "equip_slot": "main_hand", "rarity": "rare", "item_level": 399, "stats": {"attack_damage": 90}},
		{"id": "srv_2", "item_name": "Piedra sin metadatos"},
	])
	check(added == ["srv_1"] and s.get_item("srv_1")["stats"].get("dano", 0.0) == 90.0, "Adaptador del backend: solo objetos con metadatos de equipo (claves legacy -> canónicas)")
	s.free()


# --------------------------------------------------------------------------
# 13. Mochila (ventana)
# --------------------------------------------------------------------------
func _test_backpack_window() -> void:
	print("-- 13. Ventana: cuadrícula, pestañas, buscador y bolsa segura")
	var w := _new_window()
	await _frames()
	check(w.grid_cells.size() == 40 and w.grid.columns == 8, "Cuadrícula 8 × 5 (40 casillas)")
	check(w.grid_cells[0].item_id == "anillo_deriva" and w.grid_cells[17].item_id == "carta_torin" and w.grid_cells[18].item_id == "", "La mochila se pinta en orden")
	check(w.grid_cells[10].qty_label.text == "12", "Pila de Poción de vida ×12")
	check(w.grid_cells[0].is_new, "Objeto nuevo con punto de aviso")
	check(w.filter_buttons.size() == 5 and w.filter_buttons["all"].text == "Todo 18" and w.filter_buttons["weapon"].text == "Armas 4", "Pestañas con contador (Todo 18 · Armas 4)")
	w.filter_buttons["weapon"].emit_signal("pressed")
	check(w.filter_id == "weapon" and w.get_visible_items().size() == 4 and w.grid_cells[3].item_id == "pico_ambar" and w.grid_cells[4].item_id == "", "Pestaña Armas: 4 objetos")
	check(w.filter_buttons["weapon"].button_pressed and not w.filter_buttons["all"].button_pressed, "Pestaña Armas marcada")
	w.set_filter("consumable")
	check(w.get_visible_items() == ["pocion_vida", "elixir_celeridad", "racion_viaje"], "Pestaña Consumibles")
	w.set_filter("all")
	w.search_edit.text = "anillos con celeridad"
	w.search_edit.text_changed.emit("anillos con celeridad")
	check(w.search_query == "anillos con celeridad" and w.get_visible_items() == ["anillo_deriva"], "Buscador en tiempo real")
	check(w.results_label.text == "1 resultado" and w.results_label.get_theme_color("font_color") == Color("#46e3c1"), "«1 resultado» en acento")
	check(w.grid_cells[0].item_id == "anillo_deriva" and w.grid_cells[1].item_id == "", "La cuadrícula muestra solo coincidencias")
	w.set_filter("material")
	w.set_search("runa")
	check(w.get_visible_items() == ["fragmento_runa"], "Filtro Materiales + «runa»")
	w.set_search("")
	w.set_filter("all")
	check(w.results_label.text == "" and w.get_visible_items().size() == 18, "Limpiar búsqueda")
	check(w.handle_key(_key(KEY_F, true)) and w.search_edit.has_focus(), "Ctrl+F enfoca el buscador")
	check(not w.handle_key(_key(KEY_F2)), "Escribiendo en el buscador F2 no cambia de conjunto")
	w.search_edit.release_focus()
	check(w.secure_cells.size() == 3 and w.secure_cells[0].item_id == "nucleo_grieta" and w.secure_cells[2].item_id == "", "Bolsa segura destacada: 2 / 3")
	check(w.secure_cells[2].locked and w.secure_cells[2].get_border_color() == Color(T.ACCENT_DEFAULT, 0.35), "Casilla segura vacía con borde de acento")
	check(w.content.find_child("SecureHint", true, false).text.contains("no se pierde al morir"), "Texto: no se pierde al morir en zonas peligrosas")
	w.initialize_window({"filter": "armor", "query": "bastion"})
	check(w.get_visible_items() == ["coraza_bastion", "yelmo_bastion"], "initialize_window(filter, query)")
	w.set_search("")
	w.set_filter("all")
	w.handle_key(_key(KEY_R))
	check(w.service.get_item(w.grid_cells[0].item_id)["category"] == "weapon", "[R] ordena la mochila")
	w.queue_free()
	await _frames()
