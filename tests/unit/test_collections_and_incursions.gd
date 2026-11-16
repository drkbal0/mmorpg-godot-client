extends SceneTree
## Suite headless (UI v2.4 Paso 12): Colecciones / Diario del multiverso e Incursiones con extracción.
## Run: Godot --headless --path clients/godot-mmo-client -s tests/unit/test_collections_and_incursions.gd
## Exit code 0 = todo PASS.

const CS = preload("res://shared-core/CollectionsService.gd")
const IS = preload("res://shared-core/IncursionService.gd")
const KS = preload("res://shared-core/KnowledgeService.gd")
const COM = preload("res://shared-core/CommerceService.gd")
const CollectionsScene = preload("res://ui/windows/CollectionsWindow/CollectionsWindow.tscn")
const IncursionsScene = preload("res://ui/windows/IncursionsWindow/IncursionsWindow.tscn")
const COLL_SEED := "res://config/collections/collections_seed.json"
const INC_SEED := "res://config/incursions/incursions_seed.json"

const MIN_CHECKS := 200

var _fails: Array[String] = []
var _checks := 0


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
	print("== [TEST] Paso 12: Colecciones (Diario del multiverso) e Incursiones con extracción ==")
	_test_registry()
	await _test_orchestrator()
	_test_collections_seed()
	_test_collections_lists()
	_test_journal()
	_test_unlock_and_progress()
	_test_cosmetics()
	_test_collections_persistence()
	await _test_collections_window()
	_test_incursion_types()
	_test_secure_bag_and_risk()
	_test_readiness()
	_test_run_extraction()
	_test_run_death_rules()
	_test_disconnect_and_entry()
	_test_incursion_persistence()
	await _test_incursions_window()
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


func _cs() -> Node:
	var s: Node = CS.new()
	s.load_seed(COLL_SEED)
	return s


func _is() -> Node:
	var s: Node = IS.new()
	s.load_seed(INC_SEED)
	return s


func _free(n) -> void:
	if is_instance_valid(n):
		if n is Node and (n as Node).is_inside_tree():
			(n as Node).queue_free()
		else:
			n.free()


func _ids(list: Array) -> Array:
	return list.map(func(v): return v["id"])


# --------------------------------------------------------------------------
# 1. Registro de ventanas y autoloads
# --------------------------------------------------------------------------
func _test_registry() -> void:
	print("-- 1. UIWindowRegistry y autoloads")
	var Registry = load("res://ui/orchestration/UIWindowRegistry.gd")
	var UITypes = load("res://ui/types/UITypes.gd")
	var reg: Node = Registry.new()
	for pair in [["collections_window", "res://ui/windows/CollectionsWindow/CollectionsWindow.tscn"], ["incursions_window", "res://ui/windows/IncursionsWindow/IncursionsWindow.tscn"]]:
		var id: String = pair[0]
		check(reg.is_registered(id), "Registrada: " + id)
		var meta = reg.get_metadata(id)
		check(meta != null and meta.scene_path == pair[1], "%s -> %s" % [id, pair[1]])
		check(meta != null and ResourceLoader.exists(meta.scene_path), "La escena de %s existe" % id)
		check(meta != null and meta.category == UITypes.WindowCategory.GAME_WINDOW, "%s es GAME_WINDOW" % id)
		check(reg.get_shortcut_keys(id).is_empty(), "%s no roba atajos de teclado" % id)
		check(reg.resolve_route(id, {}) == id, "%s no tiene rutas de compatibilidad" % id)
	check(reg.get_window_for_key(KEY_L) == "quests_window" and reg.get_window_for_key(KEY_C) == "inventory", "L y C siguen en Misiones y Equipo")
	check(reg.is_registered("map_window") and reg.is_registered("social_window"), "Destinos de los CTA registrados (Mapa, Social)")
	reg.free()
	check(str(ProjectSettings.get_setting("autoload/CollectionsService", "")) == "*res://shared-core/CollectionsService.gd", "Autoload CollectionsService registrado")
	check(str(ProjectSettings.get_setting("autoload/IncursionService", "")) == "*res://shared-core/IncursionService.gd", "Autoload IncursionService registrado")
	var acs := root.get_node_or_null("CollectionsService")
	check(acs != null and acs.items.size() >= 40, "Autoload CollectionsService cargó su seed")
	check(acs != null and acs.knowledge == root.get_node_or_null("KnowledgeService"), "El autoload de Colecciones se vincula al Códice (KnowledgeService)")
	var ais := root.get_node_or_null("IncursionService")
	check(ais != null and ais.incursions.size() == 3, "Autoload IncursionService cargó las 3 incursiones")
	check(FileAccess.file_exists("res://shared-core/CollectionsService.gd") and FileAccess.file_exists("res://shared-core/IncursionService.gd"), "Servicios en shared-core")
	var mirror := ProjectSettings.globalize_path("res://").path_join("../shared-core")
	for f in ["CollectionsService.gd", "IncursionService.gd"]:
		var a := FileAccess.get_file_as_string("res://shared-core/" + f)
		var b := FileAccess.get_file_as_string(mirror.path_join(f))
		check(a != "" and a == b, "clients/shared-core/%s sincronizado con el cliente" % f)


func _test_orchestrator() -> void:
	print("-- 2. UIOrchestrator.open_collections / open_incursions")
	var orch := root.get_node_or_null("UIOrchestrator")
	check(orch != null, "Autoload UIOrchestrator presente")
	if orch == null:
		return
	check(orch.has_method("open_collections") and orch.has_method("open_incursions"), "UIOrchestrator expone open_collections y open_incursions")
	var w = orch.open_collections("titles")
	await _frames(2)
	check(w != null and w.get_script() != null and w.window_id == "collections_window", "open_collections instancia CollectionsWindow")
	check(w != null and w.category == "titles", "open_collections aplica la categoría (Títulos)")
	check(w != null and w.grid_title.text == "Títulos", "La cuadrícula muestra Títulos")
	check(orch.is_window_open("collections_window"), "collections_window queda abierta")
	var w2 = orch.open_collections()
	await _frames(1)
	check(w2 == w and w.category == "mounts", "Reabrir sin parámetros vuelve a Monturas en la misma instancia")
	check(w.menu_bar.active_tab == "codice", "Colecciones marca la pestaña Códice del menú")
	orch.close_window("collections_window", true)
	await _frames(1)
	check(not orch.is_window_open("collections_window"), "close_window cierra Colecciones")
	var iw = orch.open_incursions("minas_abisales")
	await _frames(2)
	check(iw != null and iw.get_script() != null and iw.window_id == "incursions_window", "open_incursions instancia IncursionsWindow")
	check(iw != null and iw.selected_id == "minas_abisales", "open_incursions selecciona la incursión pedida")
	check(iw.menu_bar.active_tab == "misiones", "Incursiones marca la pestaña Misiones del menú")
	var iw2 = orch.open_incursions()
	await _frames(1)
	check(iw2 == iw and iw.selected_id == "minas_abisales", "Reabrir sin id conserva la selección")
	orch.close_window("incursions_window", true)
	await _frames(1)
	check(not orch.is_window_open("incursions_window"), "close_window cierra Incursiones")
	var ais := root.get_node_or_null("IncursionService")
	if ais:
		ais.select(ais.recommended_id)


# --------------------------------------------------------------------------
# 3. Colecciones: seed y categorías
# --------------------------------------------------------------------------
func _test_collections_seed() -> void:
	print("-- 3. CollectionsService: seed y categorías")
	var s := _cs()
	check(s.categories.size() == 5, "5 categorías canónicas")
	var expect := {"mounts": ["Monturas", "23/96"], "pets": ["Mascotas", "41/150"], "transmogs": ["Apariencias", "212/900"], "achievements": ["Logros", "318/1.240"], "titles": ["Títulos", "12/80"]}
	var order: Array = s.categories.map(func(c): return c["id"])
	check(order == ["mounts", "pets", "transmogs", "achievements", "titles"], "Orden: Monturas · Mascotas · Apariencias · Logros · Títulos")
	for cid in expect:
		check(s.category_name(cid) == expect[cid][0], "Nombre de categoría: " + expect[cid][0])
		check(s.counter_text(cid) == expect[cid][1], "Contador %s %s" % [expect[cid][0], expect[cid][1]])
	check(s.counter_long_text("mounts") == "23 de 96", "Cabecera «23 de 96»")
	check(is_equal_approx(s.completion_ratio("mounts"), 23.0 / 96.0), "Ratio de completado de Monturas")
	check(s.list_items("mounts", "all", "", "catalog").size() == 18, "18 monturas en la cuadrícula (como el HTML)")
	var names: Array = s.list_items("mounts", "all", "", "catalog").map(func(v): return v["name"])
	check(names.slice(0, 6) == ["Lobo de ceniza", "Grifo del vado", "Autómata de Ferrum", "Raya de grieta", "Ciervo rúnico", "Corcel del Nexo"], "Primera fila del HTML en orden de catálogo")
	check(names[6] == "Por descubrir" and names.count("Por descubrir") == 5, "5 casillas «Por descubrir»")
	check(s.is_unlocked("lobo_ceniza") and not s.is_unlocked("raya_grieta"), "Lobo tuyo, Raya por conseguir")
	check(s.is_hidden("secreto_montura_1"), "Secreto oculto")
	check(s.active_mount == "lobo_ceniza" and not s.mount_summoned, "Montura favorita del seed sin invocar")
	check(s.active_title == "titulo_pionero", "Título visible del seed: Pionero")
	check(CS.fmt(1240) == "1.240" and CS.fmt(96) == "96" and CS.fmt(1234567) == "1.234.567", "Separador de miles")
	check(CS.rarity_name("epic") == "Épica" and CS.rarity_color("legendary") == Color("#ffb547"), "Rareza: nombre y color")
	check(CS.source_label("raid") == "Raid" and CS.source_label("reputation") == "Reputación", "Etiquetas de procedencia")
	check(not s.has_category("nope") and s.get_item("nope").is_empty(), "Categoría / objeto inexistente")
	_free(s)


func _test_collections_lists() -> void:
	print("-- 4. Cuadrícula: filtros, orden y vista oculta")
	var s := _cs()
	check(s.list_items("mounts", "unlocked").size() == 6, "Desbloqueadas: 6 monturas listadas")
	check(s.list_items("mounts", "missing").size() == 12, "Por conseguir: 12 (incluye «Por descubrir»)")
	check(s.list_items("mounts", "all", "epic").size() == 4, "Rareza épica: 4 (los secretos no revelan rareza)")
	check(s.list_items("mounts", "all", "legendary").size() == 1, "Rareza legendaria: solo Mantis (las ocultas no cuentan)")
	check(s.list_items("mounts", "unlocked", "rare").size() == 2, "Filtros combinados: raras desbloqueadas = 2")
	check(s.list_items("mounts", "missing", "common").is_empty(), "Sin resultados: lista vacía")
	var near := _ids(s.list_items("mounts", "all", "", "near"))
	check(near.slice(0, 6) == ["lobo_ceniza", "grifo_vado", "automata_ferrum", "corcel_nexo", "escarabajo_bronce", "jabali_guerra"], "Orden «más cerca»: primero las tuyas")
	check(near.slice(6, 9) == ["raya_grieta", "draco_joven", "mantis_cristal"], "…luego por progreso: Raya 80 %, Draco 60 %, Mantis 35 %")
	check(near.slice(9, 13) == ["ciervo_runico", "polilla_lunar", "tortuga_errante", "sierpe_eco"], "…luego por conseguir sin progreso")
	check(near.slice(13).all(func(id): return str(id).begins_with("secreto_")), "…y al final lo «Por descubrir»")
	var rar: Array = s.list_items("mounts", "all", "", "rarity")
	check(rar[0]["rarity"] == "legendary" and rar[1]["rarity"] == "epic", "Orden por rareza (legendaria primero)")
	var by_name: Array = s.list_items("mounts", "unlocked", "", "name")
	check(by_name[0]["name"] == "Autómata de Ferrum" and by_name[-1]["name"] == "Lobo de ceniza", "Orden alfabético")
	var hv: Dictionary = s.get_item_view("secreto_montura_1")
	check(hv["name"] == "Por descubrir" and hv["rarity"] == "" and hv["source_text"] == "???", "Lo oculto no revela nombre, rareza ni procedencia")
	check(hv["action"] == "none" and hv["cta"].is_empty(), "Lo oculto no tiene acción")
	var rv: Dictionary = s.get_item_view("raya_grieta")
	check(rv["progress_pct"] == 80 and rv["in_progress"] and rv["requirement"] == "Sella 8 de 10 grietas en Verdalia", "Raya de grieta 80 % · «Sella 8 de 10 grietas en Verdalia»")
	check(rv["source_label"] == "Mundo" and rv["rarity_name"] == "Épica", "Ficha: procedencia y rareza")
	check(rv["action"] == "cta" and rv["cta"]["label"] == "Ver grietas en el mapa", "Acción de lo que no tienes: CTA del HTML")
	check(s.get_item_view("draco_joven")["requirement"] == "Reputación con Guardabosques: Honorable", "Draco joven: requisito de reputación")
	check(s.get_item_view("mantis_cristal")["requirement"] == "Botín raro del Coloso de Runavell (1 vez por semana)", "Mantis: botín del Coloso")
	check(s.get_item_view("ciervo_runico")["progress_pct"] == 0 and not s.get_item_view("ciervo_runico")["in_progress"], "Sin progreso: 0 %")
	check(s.progress_ratio("lobo_ceniza") == 1.0, "Lo tuyo cuenta como 100 %")
	var nc: Array = s.near_completion(4)
	check(_ids(nc) == ["raya_grieta", "logro_turista", "draco_joven", "mantis_cristal"], "«Cerca de conseguir»: Raya, Turista del multiverso, Draco, Mantis")
	check(nc[1]["name"] == "Logro: Turista del multiverso" and nc[1]["progress_pct"] == 75, "Logro: Turista del multiverso 75 %")
	check(nc[1]["requirement"] == "Visita los 4 universos en un día · falta Runavell", "Turista: «falta Runavell»")
	check(nc[2]["cta"]["label"] == "Misiones que dan reputación" and nc[3]["cta"]["label"] == "Avisarme del evento", "CTA de Draco y Mantis")
	check(s.near_completion(0).size() > 4, "near_completion sin límite devuelve más")
	check(_ids(s.near_completion(10, "mounts")) == ["raya_grieta", "draco_joven", "mantis_cristal"], "near_completion por categoría")
	_free(s)


# --------------------------------------------------------------------------
# 5. Diario del multiverso
# --------------------------------------------------------------------------
func _test_journal() -> void:
	print("-- 5. Diario del multiverso vinculado al Códice")
	var s := _cs()
	var j: Array = s.journal()
	check(j.size() == 4, "4 universos (Verdalia, Ferrum, Runavell, Nexo)")
	check(j[0]["name"] == "Verdalia" and j[0]["text"] == "64 % · 41 secretos", "Verdalia 64 % · 41 secretos")
	check(j[1]["name"] == "Ferrum" and j[1]["text"] == "31 % · 18 secretos", "Ferrum 31 % · 18 secretos")
	check(j[2]["name"] == "Runavell" and j[2]["text"] == "12 % · 6 secretos", "Runavell 12 % · 6 secretos")
	check(j[3]["name"] == "Nexo" and j[3]["text"] == "88 % · 22 secretos", "Nexo 88 % · 22 secretos")
	check(Color(j[0]["color"]) == Color("#9fe36a") and Color(j[1]["color"]) == Color("#5aa9ff") and Color(j[2]["color"]) == Color("#f5b546"), "Colores de anillo del HTML")
	check(is_equal_approx(j[0]["ratio"], 0.64), "Ratio del anillo de Verdalia")
	var ks: Node = KS.new()
	var changed := [0]
	s.journal_changed.connect(func() -> void: changed[0] += 1)
	s.link_knowledge(ks)
	check(s.knowledge == ks and changed[0] >= 1, "link_knowledge vincula y avisa")
	check(s.universe_progress("runavell")["secrets"] == 6, "Códice vacío: sin cambios")
	for i in 3:
		ks.discover_entry("runa_%d" % i, "lugares", {"name": "Runa %d" % i, "universe": "runavell"})
	var p: Dictionary = s.universe_progress("runavell")
	check(p["explored"] == 27 and p["pct"] == 13, "3 descubrimientos suben la exploración (12 % -> 13 %)")
	check(p["secrets"] == 6, "Los pendientes de decidir aún no cuentan como secreto")
	for i in 3:
		ks.decide_entry("runa_%d" % i, false)
	check(s.universe_progress("runavell")["text"] == "13 % · 9 secretos", "Guardados como secreto: 9 secretos")
	ks.decide_entry("runa_0", true)
	check(s.universe_progress("runavell")["secrets"] == 8 and s.universe_progress("runavell")["explored"] == 27, "Publicar: deja de ser secreto pero sigue explorado")
	ks.mark_seen("runa_lejana", "lugares")
	check(s.universe_progress("runavell")["explored"] == 27, "«Visto de lejos» no cuenta")
	ks.discover_entry("sin_universo", "lugares", {"name": "X"})
	ks.decide_entry("sin_universo", false)
	check(s.universe_progress("verdalia")["secrets"] == 41, "Entradas sin universo no cuentan")
	check(changed[0] >= 5, "Cada cambio del Códice emite journal_changed")
	check(s.add_exploration("nexo", 50) and s.universe_progress("nexo")["pct"] == 100, "La exploración se topa al 100 %")
	check(not s.add_exploration("nope"), "Universo inexistente")
	check(s.universe_progress("nope").is_empty(), "Progreso de universo inexistente vacío")
	check(s.universe_progress("ferrum")["text"] == "31 % · 18 secretos", "Otros universos intactos")
	# Títulos concedidos por el Códice
	var before: int = s.unlocked_count("titles")
	ks.titles.append("Superviviente")
	check(s.sync_titles_from_knowledge() == 1 and s.is_unlocked("titulo_superviviente"), "Título del Códice desbloquea «Superviviente»")
	check(s.unlocked_count("titles") == before + 1, "Contador de títulos +1")
	s.link_knowledge(null)
	check(s.knowledge == null and s.universe_progress("runavell")["secrets"] == 6, "Desvincular vuelve a la base")
	ks.free()
	_free(s)


# --------------------------------------------------------------------------
# 6. Desbloqueo y progreso
# --------------------------------------------------------------------------
func _test_unlock_and_progress() -> void:
	print("-- 6. Desbloqueo de monturas, mascotas y títulos")
	var s := _cs()
	var unlocked: Array = []
	s.item_unlocked.connect(func(id: String) -> void: unlocked.append(id))
	var r: Dictionary = s.add_progress("raya_grieta", 1)
	check(r["ok"] and not r["unlocked"] and r["progress"] == 9, "Raya: 9 de 10")
	check(s.requirement_text("raya_grieta") == "Sella 9 de 10 grietas en Verdalia", "El requisito se actualiza con el progreso")
	check(s.progress_pct("raya_grieta") == 90, "90 %")
	r = s.add_progress("raya_grieta", 5)
	check(r["unlocked"] and r["progress"] == 10, "Al llegar al objetivo se desbloquea (sin pasarse)")
	check(s.is_unlocked("raya_grieta") and unlocked.has("raya_grieta"), "item_unlocked emitido")
	check(s.counter_text("mounts") == "24/96", "Monturas 24/96")
	check(s.add_progress("raya_grieta")["reason"] == "already_unlocked", "No se progresa lo que ya tienes")
	check(s.add_progress("ciervo_runico")["reason"] == "no_progress", "Sin objetivo: no hay progreso")
	check(s.add_progress("nope")["reason"] == "unknown_item", "Objeto inexistente")
	check(s.unlock("ciervo_runico")["ok"] and s.counter_text("mounts") == "25/96", "Desbloqueo directo (botín)")
	check(s.unlock("ciervo_runico")["reason"] == "already_unlocked", "No se desbloquea dos veces")
	# Mascota
	check(s.unlock("cangrejo_grieta")["ok"] and s.counter_text("pets") == "42/150", "Mascota desbloqueada: 42/150")
	s.add_progress("pispa_bebe", 2)
	check(s.requirement_text("pispa_bebe") == "Completa 3 de 5 expediciones de Pispa", "Mascota con progreso")
	# Logro -> título
	r = s.add_progress("logro_turista", 1)
	check(r["unlocked"] and s.is_unlocked("logro_turista"), "Logro Turista del multiverso conseguido")
	check(s.is_unlocked("titulo_turista") and unlocked.has("titulo_turista"), "El logro concede su título")
	check(s.counter_text("achievements") == "319/1.240" and s.counter_text("titles") == "13/80", "Logros 319/1.240 y Títulos 13/80")
	# Revelar lo oculto
	check(s.reveal("secreto_montura_2") and s.get_item_view("secreto_montura_2")["name"] == "Medusa celeste", "Revelar: pasa a «Por conseguir» con su nombre")
	check(not s.reveal("secreto_montura_2") and not s.reveal("lobo_ceniza"), "Solo se revela lo oculto")
	check(s.counter_text("mounts") == "25/96", "Revelar no cuenta como desbloqueo")
	check(_ids(s.near_completion(4)).has("draco_joven") and not _ids(s.near_completion(10)).has("raya_grieta"), "Lo conseguido sale de «Cerca de conseguir»")
	_free(s)


# --------------------------------------------------------------------------
# 7. Cosméticos activos
# --------------------------------------------------------------------------
func _test_cosmetics() -> void:
	print("-- 7. Invocar montura, mascota, apariencia y título")
	var s := _cs()
	var events: Array = []
	s.active_changed.connect(func(kind: String, id: String) -> void: events.append([kind, id]))
	check(s.action_for("lobo_ceniza") == "summon" and CS.action_label("summon") == "Invocar", "Montura tuya: «Invocar»")
	var r: Dictionary = s.summon_mount("grifo_vado")
	check(r["ok"] and r["flying"] and s.active_mount == "grifo_vado" and s.mount_summoned, "Invocar el Grifo (voladora)")
	check(s.action_for("grifo_vado") == "dismiss" and s.action_for("lobo_ceniza") == "summon", "La invocada pasa a «Desmontar»")
	check(s.summon_mount("raya_grieta")["reason"] == "locked", "No se invoca lo que no tienes")
	check(s.summon_mount("zorro_chispa")["reason"] == "wrong_category", "Una mascota no es montura")
	check(s.dismiss_mount()["ok"] and not s.mount_summoned and s.dismiss_mount()["reason"] == "not_summoned", "Desmontar")
	check(s.set_active_pet("zorro_chispa")["ok"] and s.active_pet == "zorro_chispa", "Mascota activa: Zorro chispa")
	check(s.action_for("zorro_chispa") == "unpet" and s.action_for("gato_forja") == "pet", "Acciones de mascota")
	check(s.set_active_pet("pispa_bebe")["reason"] == "locked", "Mascota bloqueada")
	check(s.set_active_pet("")["ok"] and s.active_pet == "", "Guardar mascota")
	r = s.equip_transmog("capucha_vado")
	check(r["ok"] and r["slot"] == "head" and s.active_transmog["head"] == "capucha_vado", "Apariencia en Cabeza")
	check(s.equip_transmog("manto_ceniza")["slot"] == "back" and s.active_transmog.size() == 2, "Apariencias en ranuras distintas")
	s.unlock("secreto_apariencia_1")
	r = s.equip_transmog("secreto_apariencia_1")
	check(r["ok"] and r["replaced"] == "capucha_vado" and s.active_transmog["head"] == "secreto_apariencia_1", "Misma ranura: sustituye a la anterior")
	check(s.equip_transmog("botas_runicas")["reason"] == "locked", "Apariencia bloqueada")
	check(s.action_for("manto_ceniza") == "untransmog" and s.clear_transmog("back")["ok"] and not s.active_transmog.has("back"), "Quitar apariencia")
	check(s.clear_transmog("back")["reason"] == "empty_slot", "Ranura vacía")
	check(s.equip_title("titulo_sellagrietas")["ok"] and s.display_name_with_title("Kael") == "Kael Sellagrietas", "Título equipado: «Kael Sellagrietas»")
	check(s.equip_title("titulo_pionero")["ok"] and s.display_name_with_title("Kael") == "Kael, Pionero", "«Kael, Pionero»")
	check(s.equip_title("titulo_turista")["reason"] == "locked", "Título bloqueado")
	check(s.equip_title("")["ok"] and s.display_name_with_title("Kael") == "Kael", "Sin título")
	check(s.is_active("capucha_vado") == false and s.is_active("secreto_apariencia_1"), "is_active")
	check(events.size() >= 10, "active_changed emitido en cada cambio (%d)" % events.size())
	# perform_action / CTA
	check(s.perform_action("lobo_ceniza")["ok"] and s.mount_summoned and s.active_mount == "lobo_ceniza", "perform_action invoca")
	check(s.perform_action("lobo_ceniza")["ok"] and not s.mount_summoned, "perform_action desmonta")
	r = s.perform_action("raya_grieta")
	check(r["ok"] and r["open_window"] == "map_window" and r["params"]["layer"] == "grietas", "CTA «Ver grietas en el mapa» abre el Mapa")
	r = s.perform_action("mantis_cristal")
	check(r["ok"] and r["reminder"] and s.event_reminders == ["coloso_runavell"], "CTA «Avisarme del evento»")
	check(s.perform_action("mantis_cristal")["reason"] == "already_set", "No se duplica el aviso")
	check(s.perform_action("secreto_montura_1")["reason"] == "no_action", "Lo oculto no tiene acción")
	check(s.action_for("logro_pionero") == "none" and CS.action_label("none") == "Conseguido", "Logros: sin acción («Conseguido»)")
	check(CS.action_label("cta", {"label": "Ruta al portal"}) == "Ruta al portal", "Etiqueta de CTA")
	_free(s)


func _test_collections_persistence() -> void:
	print("-- 8. Persistencia de Colecciones")
	var s := _cs()
	s.add_progress("raya_grieta", 2)
	s.add_progress("draco_joven", 10)
	s.summon_mount("raya_grieta")
	s.set_active_pet("gato_forja")
	s.equip_transmog("coraza_engranajes")
	s.equip_title("titulo_vecino")
	s.set_event_reminder("coloso_runavell")
	s.add_exploration("ferrum", 10)
	var d: Dictionary = s.to_dict()
	var s2 := _cs()
	s2.load_state(d)
	check(s2.is_unlocked("raya_grieta") and s2.counter_text("mounts") == "24/96", "Desbloqueos restaurados")
	check(s2.get_item("draco_joven")["progress"] == 70, "Progreso restaurado")
	check(s2.active_mount == "raya_grieta" and s2.mount_summoned, "Montura invocada restaurada")
	check(s2.active_pet == "gato_forja" and s2.active_transmog.get("chest", "") == "coraza_engranajes", "Mascota y apariencia restauradas")
	check(s2.display_name_with_title("Kael") == "Kael del Nido", "Título restaurado")
	check(s2.event_reminders == ["coloso_runavell"] and s2.universe_progress("ferrum")["pct"] == 36, "Avisos y exploración restaurados")
	s2.load_state({"active": {"mount": "polilla_lunar", "title": "titulo_turista"}})
	check(s2.active_mount == "" and s2.active_title == "", "No se restaura algo activo que no tienes")
	_free(s)
	_free(s2)


# --------------------------------------------------------------------------
# 9. Ventana de Colecciones
# --------------------------------------------------------------------------
func _test_collections_window() -> void:
	print("-- 9. CollectionsWindow")
	var s := _cs()
	root.add_child(s)
	var ks: Node = KS.new()
	root.add_child(ks)
	s.link_knowledge(ks)
	var com: Node = COM.new()
	com.load_seed()
	root.add_child(com)
	var w = CollectionsScene.instantiate()
	w.service = s
	w.commerce = com
	root.add_child(w)
	await _frames(2)
	check(w.get_script() != null and w.window_id == "collections_window", "Ventana instanciada")
	check(w.size.x >= 1270 and w.size.y >= 680, "Tamaño del marco común (1270×680)")
	check(w.menu_bar != null and w.menu_bar.active_tab == "codice", "Pestaña Códice activa")
	check(w.get_node_or_null("Root/Body/Content/Page/CategoriesCard") != null and w.get_node_or_null("Root/Body/Content/Page/GridCard") != null and w.get_node_or_null("Root/Body/Content/Page/DetailCard") != null, "3 columnas: categorías · cuadrícula · ficha")
	check(w.find_child("TitleLabel", true, false).text == "Colecciones", "Título «Colecciones»")
	check(w.category_buttons.size() == 5, "5 botones de categoría")
	check(w.category_counters["mounts"].text == "23/96" and w.category_counters["achievements"].text == "318/1.240", "Contadores en la columna izquierda")
	check(w.category_buttons["mounts"].button_pressed and not w.category_buttons["pets"].button_pressed, "Monturas activa")
	check(w.journal_rows.size() == 4, "Diario: 4 universos")
	check(w.journal_rows["verdalia"]["text"].text == "64 % · 41 secretos" and is_equal_approx(w.journal_rows["verdalia"]["ring"].ratio, 0.64), "Anillo de Verdalia 64 %")
	check(w.journal_rows["runavell"]["ring"].color == Color("#f5b546"), "Color del anillo de Runavell")
	check(w.grid_title.text == "Monturas" and w.grid_counter.text == "23 de 96", "Cabecera «Monturas 23 de 96»")
	check(w.sort_button.text == "Ordenar: más cerca de conseguir", "«Ordenar: más cerca de conseguir»")
	check(w.grid.columns == 6 and w.cells.size() == 18, "Cuadrícula de 6 columnas con 18 casillas")
	check(w.selected_id == "lobo_ceniza", "Se selecciona la primera casilla")
	var cr = w.cells["raya_grieta"]
	check(cr.in_progress and is_equal_approx(cr.progress, 0.8) and cr.border_color() == Color("#46e3c1"), "Raya: borde cian y barra 80 %")
	check(w.cells["ciervo_runico"].cell_opacity() < 1.0 and w.cells["ciervo_runico"].border_color().a == 0.0, "Sin progreso: atenuada y sin borde")
	check(w.cells["lobo_ceniza"].border_color() == Color("#46e3c1") and w.cells["grifo_vado"].border_color() == Color(1, 1, 1, 0.12), "Tuya: borde blanco tenue (la elegida, cian)")
	check(w.cells["secreto_montura_1"].item_name == "Por descubrir", "Casilla oculta «Por descubrir»")
	# Ficha
	check(w.detail_name.text == "Lobo de ceniza" and w.detail_rarity.text.begins_with("Rara · Montura"), "Ficha: nombre y rareza")
	check(w.action_button.text == "Invocar" and not w.action_button.disabled and w.action_button.get_meta("style") == "primary", "Botón principal «Invocar»")
	check(w.detail_source.text == "Misión · Misión «El último aullido» · Bosque fósil", "Ficha: cómo se consigue")
	var res: Dictionary = w.press_action()
	await _frames(1)
	check(res["ok"] and s.mount_summoned and s.active_mount == "lobo_ceniza", "Pulsar «Invocar» invoca la montura")
	check(w.action_button.text == "Desmontar" and w.feedback_label.text == "Lobo de ceniza invocada.", "Botón pasa a «Desmontar» con aviso")
	check(w.cells["lobo_ceniza"].active, "Casilla marcada como activa")
	w.select_item("raya_grieta")
	check(w.detail_name.text == "Raya de grieta" and w.detail_req.visible and w.detail_req.text == "Sella 8 de 10 grietas en Verdalia", "Ficha de algo por conseguir con requisito")
	check(w.detail_bar.visible and is_equal_approx(w.detail_bar.ratio, 0.8), "Barra de progreso en la ficha")
	check(w.action_button.text == "Ver grietas en el mapa" and w.action_button.get_meta("style") == "ghost", "Acción secundaria: CTA del HTML")
	check((w.detail_state.get_node("Text") as Label).text == "Por conseguir · 80 %", "Estado «Por conseguir · 80 %»")
	var req_win := [""]
	w.window_requested.connect(func(id: String, _p: Dictionary) -> void: req_win[0] = id)
	w.press_action()
	await _frames(1)
	check(req_win[0] == "map_window", "El CTA pide abrir el Mapa")
	var orch := root.get_node_or_null("UIOrchestrator")
	if orch:
		check(orch.is_window_open("map_window"), "…y el orquestador lo abre")
		orch.close_window("map_window", true)
		await _frames(1)
	w.select_item("secreto_montura_1")
	check(w.detail_name.text == "Por descubrir" and w.action_button.disabled and w.detail_source.text == "???", "Ficha oculta sin acción")
	# Filtros
	w.set_state_filter("unlocked")
	check(w.cells.size() == 6 and w.state_buttons["unlocked"].button_pressed, "Filtro «Desbloqueadas»: 6")
	w.set_state_filter("missing")
	check(w.cells.size() == 12, "Filtro «Por conseguir»: 12")
	w.set_state_filter("all")
	w.set_rarity_filter("epic")
	check(w.cells.size() == 4 and w.rarity_buttons["epic"].button_pressed and not w.rarity_buttons[""].button_pressed, "Filtro de rareza épica: 4")
	w.set_state_filter("unlocked")
	check(w.cells.size() == 1 and w.cells.has("grifo_vado"), "Filtros combinados: épicas tuyas = Grifo")
	w.set_state_filter("missing")
	w.set_rarity_filter("common")
	check(w.cells.is_empty() and w.empty_label.visible, "Sin resultados: mensaje vacío")
	w.set_rarity_filter("")
	w.set_state_filter("all")
	check(w.cells.size() == 18 and not w.empty_label.visible, "Quitar filtros")
	w.cycle_sort()
	check(w.sort_id == "catalog" and w.sort_button.text == "Ordenar: catálogo", "Ciclar orden: catálogo")
	check(w.grid.get_child(3).item_id == "raya_grieta", "Orden de catálogo como el HTML")
	w.cycle_sort()
	w.cycle_sort()
	w.cycle_sort()
	check(w.sort_id == "near", "El ciclo vuelve a «más cerca de conseguir»")
	check(w.grid.get_child(0).item_id == "lobo_ceniza" and w.grid.get_child(6).item_id == "raya_grieta", "Orden «más cerca» en la cuadrícula")
	# Cerca de conseguir
	check(w.near_rows.size() == 4 and _ids(w.near_rows) == ["raya_grieta", "logro_turista", "draco_joven", "mantis_cristal"], "«Cerca de conseguir»: 4 tarjetas del HTML")
	var mantis_row: Dictionary = w.near_rows[3]
	check(mantis_row["cta"] != null and mantis_row["cta"].text == "Avisarme del evento", "Chip «Avisarme del evento»")
	var rr: Dictionary = w.press_near_cta("mantis_cristal")
	await _frames(1)
	check(rr["ok"] and s.event_reminders.has("coloso_runavell") and w.feedback_label.text == "Te avisaremos cuando empiece el evento.", "El chip activa el aviso")
	# Categorías
	var cat_ev := [""]
	w.category_changed.connect(func(c: String) -> void: cat_ev[0] = c)
	w.set_category("titles")
	await _frames(1)
	check(cat_ev[0] == "titles" and w.grid_title.text == "Títulos" and w.grid_counter.text == "12 de 80", "Cambiar a Títulos")
	check(w.category_buttons["titles"].button_pressed and not w.category_buttons["mounts"].button_pressed, "Botón de Títulos activo")
	check(w.selected_id == "titulo_pionero", "Primera casilla de Títulos (equipado)")
	check(w.action_button.text == "Quitar título" and w.detail_preview.visible and w.detail_preview.text == "Se verá así: «Tú, Pionero»", "Título equipado: vista previa y «Quitar título»")
	w.select_item("titulo_sellagrietas")
	check(w.detail_preview.text == "Se verá así: «Tú Sellagrietas»" and s.active_title == "titulo_pionero", "La vista previa no cambia el título equipado")
	w.press_action()
	await _frames(1)
	check(s.active_title == "titulo_sellagrietas" and w.feedback_label.text == "Ahora te verán como «Tú Sellagrietas».", "«Equipar título»")
	w.set_category("pets")
	w.select_item("gato_forja")
	check(w.action_button.text == "Llevar conmigo", "Mascota: «Llevar conmigo»")
	w.press_action()
	check(s.active_pet == "gato_forja", "Mascota activa desde la ventana")
	w.set_category("transmogs")
	w.select_item("coraza_engranajes")
	check(w.action_button.text == "Equipar apariencia" and w.detail_rarity.text.contains("Torso"), "Apariencia: ranura en la ficha")
	w.press_action()
	check(s.active_transmog.get("chest", "") == "coraza_engranajes", "Apariencia equipada desde la ventana")
	w.set_category("achievements")
	w.select_item("logro_pionero")
	check(w.action_button.text == "Conseguido" and w.action_button.disabled, "Logro conseguido: botón inactivo")
	w.set_category("nope")
	check(w.category == "achievements", "Categoría inválida ignorada")
	# Reacciones a cambios del servicio
	w.set_category("mounts")
	s.add_progress("draco_joven", 40)
	await _frames(2)
	check(w.category_counters["mounts"].text == "24/96" and w.cells["draco_joven"].unlocked, "Al desbloquear se refrescan contador y casilla")
	ks.discover_entry("sello_ferrum", "lugares", {"name": "Sello", "universe": "ferrum"})
	ks.decide_entry("sello_ferrum", false)
	await _frames(2)
	check(w.journal_rows["ferrum"]["text"].text == "31 % · 19 secretos", "El Diario reacciona al Códice")
	w.initialize_window({"item_id": "zorro_chispa"})
	check(w.category == "pets" and w.selected_id == "zorro_chispa", "initialize_window con item_id cambia de categoría y selecciona")
	w.queue_free()
	await _frames(1)
	s.queue_free()
	ks.queue_free()
	com.queue_free()
	await _frames(1)


# --------------------------------------------------------------------------
# 10. Incursiones: tipos
# --------------------------------------------------------------------------
func _test_incursion_types() -> void:
	print("-- 10. IncursionService: tipos de incursión")
	var s := _is()
	check(s.incursions.size() == 3, "3 tipos canónicos")
	check(_ids(s.incursions) == ["grieta_menor_vado", "boveda_ferrum", "minas_abisales"], "Rápida · Media · Larga")
	var q: Dictionary = s.get_by_tier("quick")
	var m: Dictionary = s.get_by_tier("medium")
	var l: Dictionary = s.get_by_tier("long")
	check(q["name"] == "Grieta menor del Vado" and q["tier_label"] == "Incursión rápida", "Rápida: Grieta menor del Vado")
	check(m["name"] == "Bóveda de Ferrum" and m["tier_label"] == "Incursión media", "Media: Bóveda de Ferrum")
	check(l["name"] == "Las Minas Abisales" and l["tier_label"] == "Incursión larga", "Larga: Las Minas Abisales")
	check(s.tags("grieta_menor_vado") == ["10–15 min", "1–3 jugadores", "Riesgo bajo"], "Chips de la rápida")
	check(s.tags("boveda_ferrum") == ["30–40 min", "5 jugadores", "Riesgo medio"], "Chips de la media")
	check(s.tags("minas_abisales") == ["2–4 h, por tramos", "5–10 jugadores", "Riesgo alto"], "Chips de la larga")
	check(q["duration_min"] == [10, 15] and m["duration_min"] == [30, 40] and l["duration_min"] == [120, 240], "Duraciones en minutos")
	check(q["players"] == [1, 3] and m["players"] == [5, 5] and l["players"] == [5, 10], "Jugadores")
	check(IS.tier_color("quick") == Color("#4fe39a") and IS.tier_color("medium") == Color("#f5c35b") and IS.tier_color("long") == Color("#ff8a8a"), "Colores de tipo del HTML")
	check(IS.risk_name("high") == "Riesgo alto" and IS.risk_color("low") == Color("#4fe39a"), "Riesgo: nombre y color")
	check(s.recommended_id == "boveda_ferrum" and s.selected_id == "boveda_ferrum", "La media es la recomendada (borde cian)")
	check(q["cta"]["label"] == "Entrar ahora" and m["cta"]["label"] == "Ir a la antesala" and l["cta"]["label"] == "Planear con el gremio", "Botones del HTML")
	check(q["cta"]["hint"] == "Entrar solo o en grupo" and m["cta"]["hint"] == "Buscar grupo", "Pistas: «Entrar solo o en grupo» / «Buscar grupo»")
	# Etapas
	check(q["stages"] == ["stage", "stage", "exit"], "Rápida: 2 tramos y 1 salida al final")
	check(m["stages"] == ["stage", "boss", "exit", "boss", "exit"], "Media: salida a mitad y al final")
	check(l["stages"].size() == 9 and l["camps"] == 3, "Larga: 9 etapas con 3 campamentos")
	check(s.extraction_points("grieta_menor_vado") == [2] and s.extraction_points("boveda_ferrum") == [2, 4], "Puntos de extracción")
	check(s.extraction_points("minas_abisales").is_empty() and s.camp_points("minas_abisales") == [1, 4, 7], "Larga: sin salidas fijas, campamentos 1/4/7")
	check(not q["flare_allowed"] and not m["flare_allowed"] and l["flare_allowed"], "Bengala: solo en la larga")
	var st: Array = s.stages("boveda_ferrum")
	check(st[1]["color"] == Color("#ff6b6b") and st[2]["color"] == Color("#4fe39a") and st[0]["color"] == Color("#3a4a54"), "Colores de etapa (tramo, jefe, salida)")
	check(st[2]["extraction"] and not st[1]["extraction"] and s.stages("minas_abisales")[1]["safe"], "Etapa: extracción / segura")
	check(IS.stage_name("camp") == "Campamento seguro", "Nombre de etapa")
	# Filas de la tarjeta
	var qr: Array = s.card_rows("grieta_menor_vado")
	check(qr.map(func(r): return r["label"]) == ["Botín", "Extracción", "Si mueres", "Desconexión protegida"], "Filas de la rápida")
	check(qr[0]["value"] == "esquirlas, 1 objeto raro" and qr[1]["value"] == "1 salida al final" and qr[2]["value"] == "pierdes el botín de dentro" and qr[3]["value"] == "3 min", "Valores de la rápida")
	var mr: Array = s.card_rows("boveda_ferrum")
	check(mr[1]["value"] == "a mitad y al final" and mr[2]["value"] == "tu grupo puede levantarte" and mr[3]["value"] == "3 / 5 listos", "Valores de la media (grupo 3 / 5 listos)")
	var lr: Array = s.card_rows("minas_abisales")
	check(lr[1]["label"] == "Campamentos" and lr[1]["value"] == "3 (guardan progreso)" and lr[1]["good"], "Larga: «3 (guardan progreso)» en verde")
	check(lr[2]["value"] == "fardo recuperable 30 min" and lr[3]["value"] == "tienes 1" and lr[3]["good"], "Larga: fardo 30 min y bengala")
	s.add_flares(-1)
	check(s.card_rows("minas_abisales")[3]["value"] == "no tienes" and not s.card_rows("minas_abisales")[3]["good"], "Sin bengala: «no tienes»")
	check(s.select("minas_abisales") and s.get_selected()["tier"] == "long", "Seleccionar la larga")
	check(not s.select("nope") and s.selected_id == "minas_abisales", "Seleccionar inexistente no cambia nada")
	check(s.players_text("grieta_menor_vado") == "1–3 jugadores", "players_text")
	_free(s)


# --------------------------------------------------------------------------
# 11. Bolsa segura y riesgo
# --------------------------------------------------------------------------
func _test_secure_bag_and_risk() -> void:
	print("-- 11. Bolsa segura vs objetos en riesgo")
	var s := _is()
	var b: Dictionary = s.secure_bag_status()
	check(b["capacity"] == 3 and b["used"] == 3 and b["full"], "Bolsa segura 3 / 3")
	check(b["title"] == "Bolsa segura · 3 / 3", "Título «Bolsa segura · 3 / 3»")
	check(b["text"] == "Hoja de la grieta · Anillo de la deriva · Llave oxidada", "Contenido del HTML")
	check(s.carried.size() == 7 and s.gold == 1240, "7 objetos y 1.240 oro")
	var r: Dictionary = s.at_risk("boveda_ferrum")
	check(r["text"] == "El resto del equipo, 1.240 oro y todo el botín que encuentres dentro.", "Texto «En riesgo si mueres» del HTML")
	check(r["item_count"] == 4 and r["items_value"] == 2520 and r["gold"] == 1240 and r["total_value"] == 3760, "Riesgo en la media: 4 objetos (2.520) + 1.240 oro")
	check(r["secured_value"] == 2750, "Valor a salvo en la bolsa: 2.750")
	check(not r["items"].any(func(it): return s.is_secured(it["id"])), "Nada de la bolsa segura está en riesgo")
	check(r["revivable"] and not r["recoverable"] and r["inside_loot"], "Media: tu grupo puede levantarte")
	var rq: Dictionary = s.at_risk("grieta_menor_vado")
	check(rq["item_count"] == 0 and rq["gold"] == 0 and rq["text"].begins_with("Solo el botín"), "Rápida: solo el botín de dentro")
	check(s.at_risk("minas_abisales")["recoverable"], "Larga: fardo recuperable")
	check(s.at_risk()["total_value"] == 3760, "Sin id: usa la seleccionada (media)")
	check(s.put_in_secure_bag("coraza_vado")["reason"] == "bag_full", "Bolsa llena: no cabe la Coraza")
	check(s.put_in_secure_bag("hoja_grieta")["reason"] == "already_secured", "Ya está en la bolsa")
	check(s.put_in_secure_bag("nope")["reason"] == "not_carried", "No lo llevas")
	check(s.remove_from_secure_bag("llave_oxidada")["ok"] and s.secure_bag_status()["used"] == 2, "Sacar la Llave: 2 / 3")
	check(s.remove_from_secure_bag("llave_oxidada")["reason"] == "not_secured", "No estaba en la bolsa")
	check(s.put_in_secure_bag("coraza_vado")["ok"] and s.is_secured("coraza_vado"), "Meter la Coraza")
	r = s.at_risk("boveda_ferrum")
	check(r["items_value"] == 1320 and r["secured_value"] == 3950 and r["item_count"] == 4, "Ahora arriesgas 1.320 y aseguras 3.950")
	check(s.swap_secure("coraza_vado", "yelmo_ferrum")["ok"] and s.is_secured("yelmo_ferrum") and not s.is_secured("coraza_vado"), "Cambiar un objeto de la bolsa")
	check(s.swap_secure("botas_vado", "capa_ceniza")["reason"] == "not_secured", "swap: el que sale debe estar en la bolsa")
	check(s.swap_secure("yelmo_ferrum", "hoja_grieta")["reason"] == "invalid_item", "swap: el que entra no puede estar ya")
	s.secure_bag.clear()
	check(s.secure_bag_status()["text"].begins_with("Vacía"), "Bolsa vacía: texto de ayuda")
	_free(s)


# --------------------------------------------------------------------------
# 12. Preparación
# --------------------------------------------------------------------------
func _test_readiness() -> void:
	print("-- 12. Checklist de preparación")
	var s := _is()
	var rows: Array = s.readiness("boveda_ferrum")
	check(rows.map(func(r): return r["label"]) == ["Consumibles", "Reparación", "Kit de fogata", "Bengala de extracción", "Ruta de vuelta"], "5 filas del HTML")
	check(rows[0]["value"] == "✓" and rows[1]["value"] == "82 %" and rows[2]["value"] == "1" and rows[3]["value"] == "1" and rows[4]["value"] == "caravana a 240 m", "Valores del HTML (✓, 82 %, 1, 1, caravana a 240 m)")
	check(rows.all(func(r): return r["status"] == "ok"), "Todo listo")
	check(s.is_ready("boveda_ferrum") and s.is_ready("minas_abisales") and s.is_ready("grieta_menor_vado"), "Lista para las 3")
	check(s.consumables_total() == 7, "7 consumibles")
	check(IS.durability_color(82) == Color("#4fe39a") and IS.durability_color(45) == Color("#f5c35b") and IS.durability_color(20) == Color("#ff6b6b"), "Color de reparación por tramos")
	s.set_durability(41)
	check(s.blockers("minas_abisales") == ["durability"] and s.blockers("boveda_ferrum") == ["durability"], "41 %: no basta para media (50) ni larga (60)")
	check(s.is_ready("grieta_menor_vado") and s.readiness("grieta_menor_vado")[1]["status"] == "warn", "…pero sí para la rápida (aviso)")
	s.set_durability(100)
	s.add_flares(-1)
	s.add_campfire_kits(-1)
	check(s.blockers("minas_abisales") == ["campfire_kit", "flare"], "Larga sin kit ni bengala: bloqueada")
	check(s.is_ready("boveda_ferrum"), "La media no exige kit ni bengala")
	check(s.readiness("boveda_ferrum")[3]["status"] == "warn" and not s.readiness("boveda_ferrum")[3]["required"], "Sin bengala en la media: solo aviso")
	var sm: Dictionary = s.readiness_summary("minas_abisales")
	check(not sm["ready"] and sm["ok"] == 3 and sm["total"] == 5, "Resumen: 3 / 5 y no lista")
	s.consumables.clear()
	s.add_consumable("tonico_triple", 1)
	check(s.blockers("boveda_ferrum") == ["consumables"] and s.readiness("boveda_ferrum")[0]["value"] == "1 / 2", "1 consumible: falta para la media (1 / 2)")
	check(s.is_ready("grieta_menor_vado"), "…basta para la rápida")
	s.add_consumable("tonico_triple", -1)
	check(not s.consumables.has("tonico_triple") and s.blockers("grieta_menor_vado") == ["consumables"], "Sin consumibles: ni la rápida")
	s.return_route = ""
	check(s.readiness()[4]["status"] == "warn" and s.readiness()[4]["value"] == "sin ruta", "Sin ruta de vuelta: aviso")
	s.set_party(5, 5)
	check(s.card_rows("boveda_ferrum")[3]["value"] == "5 / 5 listos", "Grupo listo 5 / 5")
	_free(s)


# --------------------------------------------------------------------------
# 13. Partida: extracción
# --------------------------------------------------------------------------
func _test_run_extraction() -> void:
	print("-- 13. Etapas y extracción (salida, bengala, al terminar)")
	var s := _is()
	check(s.start_run("grieta_menor_vado", 4)["reason"] == "party_size", "Rápida: máximo 3 jugadores")
	check(s.start_run("boveda_ferrum", 3)["reason"] == "party_size", "Media: 5 jugadores")
	check(s.start_run("nope")["reason"] == "unknown_incursion", "Incursión inexistente")
	var r: Dictionary = s.start_run("grieta_menor_vado", 1)
	check(r["ok"] and s.in_run() and s.current_stage_kind() == "stage", "Entrar en la rápida (solo)")
	check(s.start_run("grieta_menor_vado", 1)["reason"] == "already_inside", "No se entra dos veces")
	check(s.put_in_secure_bag("coraza_vado")["reason"] == "inside_incursion", "Dentro no se toca la bolsa segura")
	check(s.extract()["reason"] == "no_exit_here" and not s.can_extract(), "Sin salida en el primer tramo")
	check(s.use_flare()["reason"] == "flare_not_allowed", "La rápida no admite bengala")
	s.add_loot({"id": "esquirla", "name": "Esquirla de grieta", "value": 35, "rarity": "rare"})
	s.add_loot_gold(80)
	check(s.inside_loot_value() == 115, "Botín de dentro: 115")
	check(s.advance_stage()["kind"] == "stage" and s.advance_stage()["kind"] == "exit", "Avanzar hasta la salida")
	check(s.can_extract(), "En la salida se puede extraer")
	var ended := [{}]
	s.run_ended.connect(func(res: Dictionary) -> void: ended[0] = res)
	r = s.extract()
	check(r["ok"] and r["outcome"] == "extracted" and r["method"] == "exit", "Extracción por la salida")
	check(r["kept_loot"].size() == 1 and r["kept_gold"] == 80 and s.gold == 1320, "Te llevas el botín y el oro")
	check(s.has_carried("esquirla") and s.get_carried("esquirla")["rarity"] == "rare", "El botín pasa a tu equipo")
	check(not s.in_run() and ended[0].get("outcome", "") == "extracted", "run_ended emitido; ya no estás dentro")
	check(s.extract()["reason"] == "not_inside" and s.advance_stage()["reason"] == "not_inside", "Fuera: no hay acciones de partida")
	# Media: salida a mitad
	s.start_run("boveda_ferrum", 5)
	s.advance_stage()
	check(s.current_stage_kind() == "boss" and not s.can_extract(), "Media: jefe en la etapa 2")
	s.advance_stage()
	check(s.can_extract() and s.extract()["ok"], "Media: extraer en la salida a mitad")
	# Larga: bengala
	s.start_run("minas_abisales", 6)
	var a: Dictionary = s.advance_stage()
	check(a["kind"] == "camp" and a["checkpoint"] == 1, "Larga: campamento guarda el progreso (punto 1)")
	check(not s.can_extract() and s.extract()["reason"] == "no_exit_here", "Un campamento no es salida")
	s.add_loot({"id": "reliquia", "name": "Reliquia abisal", "value": 900, "rarity": "epic"})
	check(s.can_use_flare(), "Con bengala se puede extraer")
	r = s.use_flare()
	check(r["ok"] and r["method"] == "flare" and s.flares == 0 and s.has_carried("reliquia"), "Bengala: extraes donde estés y se gasta")
	check(s.start_run("minas_abisales", 6)["reason"] == "not_ready", "Sin bengala no se entra en la larga")
	s.add_flares(1)
	check(s.start_run("minas_abisales", 6)["ok"], "Con bengala, sí")
	s.add_flares(-1)
	check(s.use_flare()["reason"] == "no_flare" and not s.can_use_flare(), "Sin bengala no hay extracción de emergencia")
	for i in 8:
		s.advance_stage()
	check(s.run["stage"] == 8 and s.run["checkpoint"] == 7, "Último tramo; último campamento en 7")
	r = s.advance_stage()
	check(r["ok"] and r["method"] == "completed" and not s.in_run(), "Al terminar la última etapa se extrae («al terminar»)")
	_free(s)


# --------------------------------------------------------------------------
# 14. Partida: reglas de muerte
# --------------------------------------------------------------------------
func _test_run_death_rules() -> void:
	print("-- 14. Muerte: botín de dentro, grupo y fardo")
	var s := _is()
	# Rápida
	s.start_run("grieta_menor_vado", 1)
	s.add_loot({"id": "x", "name": "X", "value": 100})
	s.add_loot_gold(50)
	var r: Dictionary = s.die()
	check(r["outcome"] == "dead" and r["lost_loot"].size() == 1 and r["lost_loot_gold"] == 50, "Rápida: pierdes el botín de dentro")
	check(r["lost_items"].is_empty() and r["lost_gold"] == 0 and s.carried.size() == 7 and s.gold == 1240, "…tu equipo y tu oro vuelven contigo")
	check(s.die()["reason"] == "not_inside", "Morir fuera no aplica")
	# Media
	s.start_run("boveda_ferrum", 5)
	s.add_loot({"id": "plano", "name": "Plano", "value": 300})
	r = s.die()
	check(r["outcome"] == "downed" and r["revivable"] and s.run["state"] == IS.RUN_DOWNED, "Media: quedas abatido")
	check(not s.add_loot({"id": "y"}) and s.advance_stage()["reason"] == "not_inside", "Abatido no puedes lootear ni avanzar")
	check(s.revive()["ok"] and s.run["state"] == IS.RUN_INSIDE and s.run["loot"].size() == 1, "Tu grupo te levanta y conservas el botín")
	check(s.revive()["reason"] == "not_downed", "No se levanta a quien está en pie")
	s.die()
	r = s.bleed_out()
	check(r["outcome"] == "dead" and r["lost_items"].size() == 4 and r["lost_gold"] == 1240, "Nadie te levanta: pierdes el resto del equipo y el oro")
	check(s.carried.size() == 3 and s.gold == 0, "Solo quedan los 3 objetos de la bolsa segura")
	check(s.secure_bag.all(func(id): return s.has_carried(id)), "La Bolsa segura es inmune a la pérdida")
	check(r["secured"] == ["hoja_grieta", "anillo_deriva", "llave_oxidada"], "El resultado lista lo asegurado")
	check(s.bleed_out()["reason"] == "not_downed", "bleed_out sin partida")
	# Larga: fardo
	var s2 := _is()
	s2.start_run("minas_abisales", 5)
	s2.advance_stage()
	s2.advance_stage()
	s2.add_loot({"id": "reliquia", "name": "Reliquia", "value": 900})
	r = s2.die()
	check(r["outcome"] == "bundle_dropped" and is_equal_approx(r["bundle_expires_in"], 1800.0), "Larga: dejas un fardo recuperable 30 min")
	check(r["respawn_stage"] == 1 and s2.run["stage"] == 1 and s2.in_run(), "Reapareces en el último campamento")
	check(s2.carried.size() == 3 and s2.gold == 0 and s2.run["loot"].is_empty(), "El fardo se lleva equipo en riesgo, oro y botín")
	check(s2.bundle["items"].size() == 4 and s2.bundle["gold"] == 1240 and s2.bundle["loot"].size() == 1, "Contenido del fardo")
	s2.tick(600.0)
	check(is_equal_approx(s2.bundle_time_left(), 1200.0), "Quedan 20 min para recuperarlo")
	r = s2.recover_bundle()
	check(r["ok"] and r["recovered_items"] == 4 and s2.carried.size() == 7 and s2.gold == 1240 and s2.run["loot"].size() == 1, "Recuperar el fardo devuelve todo")
	check(s2.recover_bundle()["reason"] == "no_bundle", "No hay fardo que recuperar")
	s2.die()
	s2.tick(1801.0)
	check(s2.bundle.is_empty() and s2.last_result["outcome"] == "bundle_lost" and s2.carried.size() == 3, "Pasados 30 min el fardo se pierde")
	check(s2.secure_bag.all(func(id): return s2.has_carried(id)), "La bolsa segura sobrevive también al fardo perdido")
	_free(s)
	_free(s2)


# --------------------------------------------------------------------------
# 15. Desconexión y entrada
# --------------------------------------------------------------------------
func _test_disconnect_and_entry() -> void:
	print("-- 15. Desconexión dentro y botones de entrada")
	var s := _is()
	s.start_run("grieta_menor_vado", 2)
	var r: Dictionary = s.disconnect_inside()
	check(r["ok"] and r["protected_s"] == 180 and r["character_stays"], "Rápida: desconexión protegida 3 min; el personaje se queda")
	s.tick(100.0)
	r = s.reconnect()
	check(r["ok"] and r["protected"] and not r["exposed"] and is_equal_approx(r["away_s"], 100.0), "Vuelves a los 100 s: protegido")
	s.disconnect_inside()
	s.tick(200.0)
	check(s.reconnect()["exposed"], "Pasados 3 min: tu personaje estuvo expuesto")
	check(s.reconnect()["reason"] == "not_disconnected", "reconnect sin desconexión")
	s.run = {}
	s.start_run("minas_abisales", 5)
	s.advance_stage()
	r = s.disconnect_inside()
	check(r["safe_camp"] and r["progress_saved"], "Larga en campamento: el progreso queda guardado")
	s.tick(86400.0)
	r = s.reconnect()
	check(r["protected"] and r["stage"] == 1, "Vuelves otro día al mismo campamento")
	s.advance_stage()
	check(not s.disconnect_inside()["safe_camp"], "Fuera del campamento no hay seguridad")
	s.run = {}
	check(IS.RULE_TEXT == "Solo te llevas el botín si extraes: por una salida, con una bengala o al terminar. Si te desconectas dentro, tu personaje se queda ahí.", "Regla del HTML")
	# request_entry
	var asked := [""]
	s.entry_requested.connect(func(id: String, action: String) -> void: asked[0] = action)
	r = s.request_entry("boveda_ferrum")
	check(r["ok"] and r["action"] == "lobby" and r["party"]["ready"] == 3 and asked[0] == "lobby", "Media: «Ir a la antesala»")
	r = s.request_entry("minas_abisales")
	check(r["ok"] and r["action"] == "guild" and r["open_window"] == "social_window", "Larga: «Planear con el gremio» abre Social")
	check(s.selected_id == "minas_abisales" and not s.in_run(), "Planear no entra")
	r = s.request_entry("grieta_menor_vado", 1)
	check(r["ok"] and s.in_run() and s.run["incursion_id"] == "grieta_menor_vado", "Rápida: «Entrar ahora» entra")
	s.run = {}
	s.set_durability(10)
	r = s.request_entry("grieta_menor_vado", 1)
	check(not r["ok"] and r["reason"] == "not_ready" and r["blockers"] == ["durability"], "Sin preparación no se entra")
	check(s.request_entry("nope")["reason"] == "unknown_incursion", "request_entry inexistente")
	_free(s)


func _test_incursion_persistence() -> void:
	print("-- 16. Persistencia de Incursiones")
	var s := _is()
	s.select("minas_abisales")
	s.start_run("minas_abisales", 5)
	s.advance_stage()
	s.remove_from_secure_bag("llave_oxidada") # dentro: no permitido
	var d: Dictionary = s.to_dict()
	var s2 := _is()
	s2.load_state(d)
	check(s2.selected_id == "minas_abisales" and s2.in_run() and s2.run["stage"] == 1 and s2.run["checkpoint"] == 1, "Partida y campamento restaurados")
	check(s2.secure_bag.size() == 3 and s2.carried.size() == 7 and s2.gold == 1240, "Equipo y bolsa restaurados")
	s2.load_state({"selected": "nope"})
	check(s2.selected_id == s2.recommended_id, "Selección inválida: vuelve a la recomendada")
	_free(s)
	_free(s2)


# --------------------------------------------------------------------------
# 17. Ventana de Incursiones
# --------------------------------------------------------------------------
func _test_incursions_window() -> void:
	print("-- 17. IncursionsWindow")
	var s := _is()
	root.add_child(s)
	var com: Node = COM.new()
	com.load_seed()
	root.add_child(com)
	var w = IncursionsScene.instantiate()
	w.service = s
	w.commerce = com
	root.add_child(w)
	await _frames(2)
	check(w.get_script() != null and w.window_id == "incursions_window", "Ventana instanciada")
	check(w.menu_bar.active_tab == "misiones", "Pestaña Misiones activa")
	check(w.cards.size() == 3 and w.get_node_or_null("Root/Body/Content/Page/Cards") != null and w.get_node_or_null("Root/Body/Content/Page/LoadoutCard") != null, "3 tarjetas + columna «Qué llevas»")
	check(w.selected_id == "boveda_ferrum", "La media viene seleccionada")
	var mc: Dictionary = w.cards["boveda_ferrum"]
	var sb: StyleBoxFlat = mc["panel"].get_theme_stylebox("panel")
	check(sb.border_color == Color("#46e3c1") and sb.border_width_left == 2, "Tarjeta elegida con borde cian")
	check(mc["cta"].text == "Ir a la antesala" and mc["cta"].get_meta("style") == "primary", "Botón principal en la elegida")
	check(w.cards["grieta_menor_vado"]["cta"].text == "Entrar ahora" and w.cards["grieta_menor_vado"]["cta"].get_meta("style") == "ghost", "«Entrar ahora» secundario")
	check(w.cards["minas_abisales"]["cta"].text == "Planear con el gremio", "«Planear con el gremio»")
	var qp: Control = w.cards["grieta_menor_vado"]["panel"]
	check((qp.find_child("Tier", true, false) as Label).text == "INCURSIÓN RÁPIDA" and (qp.find_child("Name", true, false) as Label).text == "Grieta menor del Vado", "Cabecera de la rápida")
	check(qp.find_child("Tags", true, false).get_child_count() == 3, "3 chips en la tarjeta")
	check(w.cards["grieta_menor_vado"]["rows"]["disconnect"].text == "3 min", "Fila «Desconexión protegida 3 min»")
	check(mc["rows"]["party"].text == "3 / 5 listos", "Fila «Tu grupo 3 / 5 listos»")
	check(w.cards["minas_abisales"]["rows"]["camps"].text == "3 (guardan progreso)" and w.cards["minas_abisales"]["rows"]["flare"].text == "tienes 1", "Filas de la larga")
	check(w.cards["minas_abisales"]["stage_bar"].kinds.size() == 9 and mc["stage_bar"].kinds == ["stage", "boss", "exit", "boss", "exit"], "Barras de etapas")
	check(mc["stage_bar"].segment_rects().size() == 5, "Una píldora por etapa")
	check(mc["legend"].text == "5 etapas · 2 jefes · 2 salidas" and w.cards["minas_abisales"]["legend"].text.ends_with("bengala"), "Leyenda de etapas")
	check(w.bag_title.text == "Bolsa segura · 3 / 3" and w.bag_text.text == "Hoja de la grieta · Anillo de la deriva · Llave oxidada", "Bolsa segura del HTML")
	check(w.risk_title.text == "En riesgo si mueres" and w.risk_text.text == "El resto del equipo, 1.240 oro y todo el botín que encuentres dentro.", "En riesgo si mueres (HTML)")
	check(w.risk_value.text.contains("2.520") and w.risk_value.text.contains("tu grupo puede levantarte"), "Desglose del valor en riesgo")
	check(w.gear_buttons.size() == 7 and w.gear_buttons["hoja_grieta"].button_pressed and not w.gear_buttons["coraza_vado"].button_pressed, "Tu equipo: 7, los asegurados marcados")
	check(w.prep_rows.size() == 5 and w.prep_rows["consumables"]["value"].text == "✓" and w.prep_rows["durability"]["value"].text == "82 %", "Preparación: ✓ y 82 %")
	check(w.prep_rows["return_route"]["value"].text == "caravana a 240 m", "Ruta de vuelta")
	check(w.prep_rows["durability"]["value"].get_theme_color("font_color") == Color("#4fe39a"), "82 % en verde")
	check(w.rule_label.text == IS.RULE_TEXT, "Regla de extracción y desconexión")
	# Bolsa desde la ventana
	var tr: Dictionary = w.toggle_secure("coraza_vado")
	check(not tr["ok"] and w.feedback_label.text.contains("llena"), "Bolsa llena: aviso")
	w.toggle_secure("llave_oxidada")
	await _frames(1)
	check(w.bag_title.text == "Bolsa segura · 2 / 3" and not w.gear_buttons["llave_oxidada"].button_pressed, "Sacar la Llave desde la ventana")
	w.toggle_secure("coraza_vado")
	await _frames(1)
	check(w.bag_text.text == "Hoja de la grieta · Anillo de la deriva · Coraza del vado" and w.risk_value.text.contains("1.320"), "Meter la Coraza: baja el valor en riesgo")
	# Selección
	var sel := [""]
	w.incursion_selected.connect(func(id: String) -> void: sel[0] = id)
	w.select_incursion("grieta_menor_vado")
	check(sel[0] == "grieta_menor_vado" and s.selected_id == "grieta_menor_vado", "Seleccionar la rápida (servicio y señal)")
	check(w.risk_text.text.begins_with("Solo el botín"), "El riesgo cambia con la incursión")
	check(w.cards["grieta_menor_vado"]["cta"].get_meta("style") == "primary" and mc["cta"].get_meta("style") == "ghost", "El botón principal sigue a la selección")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	w.cards["minas_abisales"]["panel"].gui_input.emit(click)
	check(w.selected_id == "minas_abisales", "Clic en la tarjeta la selecciona")
	# Preparación con bloqueos
	s.add_flares(-1)
	s.add_campfire_kits(-1)
	s.set_durability(41)
	await _frames(2)
	var lh: Label = w.cards["minas_abisales"]["hint"]
	check(lh.visible and lh.text == "Falta: Reparación, Kit de fogata, Bengala de extracción", "Pista de bloqueos en la larga")
	check(w.cards["boveda_ferrum"]["hint"].text == "Falta: Reparación", "…y en la media")
	check(w.prep_rows["flare"]["value"].text == "0" and w.prep_rows["flare"]["value"].get_theme_color("font_color") == Color("#ff6b6b"), "Bengala 0 en rojo (requerida)")
	check(w.prep_rows["durability"]["value"].get_theme_color("font_color") == Color("#ff6b6b"), "Reparación insuficiente en rojo")
	check(w.cards["minas_abisales"]["rows"]["flare"].text == "no tienes", "La tarjeta refleja la falta de bengala")
	var res: Dictionary = w.press_cta("boveda_ferrum")
	check(res["ok"] and res["action"] == "lobby" and not res["ready"], "La antesala se abre aunque falte preparación")
	check(w.feedback_label.text == "Antesala de Bóveda de Ferrum · tu grupo: 3 / 5 listos.", "Aviso de la antesala")
	s.set_durability(90)
	s.add_flares(1)
	s.add_campfire_kits(1)
	await _frames(2)
	check(not w.cards["minas_abisales"]["hint"].text.begins_with("Falta"), "Preparado: sin bloqueos")
	var guild := [""]
	w.guild_plan_requested.connect(func(id: String) -> void: guild[0] = id)
	res = w.press_cta("minas_abisales")
	await _frames(1)
	check(res["action"] == "guild" and guild[0] == "minas_abisales", "«Planear con el gremio» emite la señal")
	var orch := root.get_node_or_null("UIOrchestrator")
	if orch:
		check(orch.is_window_open("social_window"), "…y abre Social")
		orch.close_window("social_window", true)
		await _frames(1)
	# Entrar ahora
	res = w.press_cta("grieta_menor_vado")
	await _frames(2)
	check(res["ok"] and s.in_run(), "«Entrar ahora» entra en la rápida")
	check(w.cards["grieta_menor_vado"]["cta"].text == "Dentro · etapa 1 / 3" and w.cards["grieta_menor_vado"]["cta"].disabled, "Botón «Dentro · etapa 1 / 3»")
	check(w.cards["boveda_ferrum"]["cta"].disabled and w.cards["minas_abisales"]["cta"].disabled, "No se puede entrar en otra")
	check(w.gear_buttons["coraza_vado"].disabled, "Dentro no se toca la bolsa")
	check(w.cards["grieta_menor_vado"]["stage_bar"].current == 0 and w.feedback_label.text == "Entrando en Grieta menor del Vado…", "Etapa actual marcada")
	s.advance_stage()
	await _frames(2)
	check(w.cards["grieta_menor_vado"]["cta"].text == "Dentro · etapa 2 / 3", "La ventana sigue el avance")
	s.advance_stage()
	s.extract()
	await _frames(2)
	check(not w.cards["grieta_menor_vado"]["cta"].disabled and w.cards["grieta_menor_vado"]["cta"].text == "Entrar ahora", "Tras extraer vuelve «Entrar ahora»")
	s.set_durability(5)
	await _frames(1)
	res = w.press_cta("grieta_menor_vado")
	check(not res["ok"] and w.feedback_label.text == "Te falta: Reparación.", "Sin preparación: «Te falta: Reparación.»")
	w.initialize_window({"incursion_id": "boveda_ferrum"})
	check(w.selected_id == "boveda_ferrum", "initialize_window selecciona")
	w.initialize_window({"incursion_id": "nope"})
	check(w.selected_id == "boveda_ferrum", "initialize_window ignora ids inválidos")
	w.queue_free()
	await _frames(1)
	s.queue_free()
	com.queue_free()
	await _frames(1)
