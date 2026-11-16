extends SceneTree
## Suite headless (UI v2.4 Paso 11): Fabricación / Forja del Refugio y Trato cara a cara P2P.
## Run: Godot --headless --path clients/godot-mmo-client -s tests/unit/test_crafting_and_trade.gd
## Exit code 0 = todo PASS.

const CS = preload("res://shared-core/CraftingService.gd")
const TS = preload("res://shared-core/TradeService.gd")
const KS = preload("res://shared-core/KnowledgeService.gd")
const COM = preload("res://shared-core/CommerceService.gd")
const SHS = preload("res://shared-core/ShelterService.gd")
const CraftingScene = preload("res://ui/windows/CraftingWindow/CraftingWindow.tscn")
const TradeScene = preload("res://ui/windows/TradeWindow/TradeWindow.tscn")
const CRAFT_SEED := "res://config/crafting/crafting_seed.json"
const TRADE_SEED := "res://config/trade/trade_seed.json"

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
	print("== [TEST] Paso 11: Fabricación (Forja del Refugio) y Trato cara a cara ==")
	_test_registry()
	await _test_orchestrator()
	_test_crafting_seed()
	_test_badges()
	_test_quality()
	_test_craft_now()
	_test_forge_queue()
	_test_offline_and_persistence()
	_test_buy_missing()
	await _test_crafting_window()
	_test_trade_session()
	_test_trade_mask_and_reveal()
	_test_trade_confirmation_rules()
	_test_trade_complete()
	await _test_trade_window()
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
	s.load_seed(CRAFT_SEED)
	return s


func _ks() -> Node:
	var k: Node = KS.new()
	k.register_entry("lugar_cueva_ambar", "lugares", {"name": "Cueva de ámbar"}, KS.KNOWN_SECRET)
	return k


func _ts(k: Node = null) -> Node:
	var t: Node = TS.new()
	t.load_seed(TRADE_SEED)
	t.knowledge = k if k else _ks()
	t.start_session("Sasha", {})
	return t


func _free(n) -> void:
	if is_instance_valid(n):
		if n is Node and (n as Node).is_inside_tree():
			(n as Node).queue_free()
		else:
			n.free()


func _sum(d: Dictionary) -> int:
	var s := 0
	for k in d:
		s += int(d[k])
	return s


# --------------------------------------------------------------------------
# 1. Registro de ventanas y autoloads
# --------------------------------------------------------------------------
func _test_registry() -> void:
	print("-- 1. UIWindowRegistry y autoloads")
	var Registry = load("res://ui/orchestration/UIWindowRegistry.gd")
	var UITypes = load("res://ui/types/UITypes.gd")
	var reg: Node = Registry.new()
	for pair in [["crafting_window", "res://ui/windows/CraftingWindow/CraftingWindow.tscn"], ["trade_window", "res://ui/windows/TradeWindow/TradeWindow.tscn"]]:
		var id: String = pair[0]
		check(reg.is_registered(id), "Registrada: " + id)
		var meta = reg.get_metadata(id)
		check(meta != null and meta.scene_path == pair[1], "%s -> %s" % [id, pair[1]])
		check(meta != null and ResourceLoader.exists(meta.scene_path), "La escena de %s existe" % id)
		check(meta != null and meta.category == UITypes.WindowCategory.GAME_WINDOW, "%s es GAME_WINDOW" % id)
		check(reg.get_shortcut_keys(id).is_empty(), "%s no roba atajos de teclado" % id)
		check(reg.resolve_route(id, {}) == id, "%s no tiene rutas de compatibilidad" % id)
	check(reg.get_window_for_key(KEY_H) == "shelter" and reg.get_window_for_key(KEY_C) == "inventory", "H y C siguen en Refugio y Equipo")
	check(reg.is_registered("marketplace_window"), "El Mercado sigue registrado (destino de «Buscar en mercado»)")
	reg.free()
	check(str(ProjectSettings.get_setting("autoload/CraftingService", "")) == "*res://shared-core/CraftingService.gd", "Autoload CraftingService registrado")
	check(str(ProjectSettings.get_setting("autoload/TradeService", "")) == "*res://shared-core/TradeService.gd", "Autoload TradeService registrado")
	var acs := root.get_node_or_null("CraftingService")
	check(acs != null and acs.recipes.size() >= 14, "Autoload CraftingService cargó su seed")
	check(acs != null and acs.realtime, "El autoload de Fabricación avanza la Forja en tiempo real")
	var ats := root.get_node_or_null("TradeService")
	check(ats != null and ats.items.has("corona_umbral"), "Autoload TradeService cargó su catálogo de precios")


func _test_orchestrator() -> void:
	print("-- 2. UIOrchestrator.open_crafting / open_trade")
	var orch := root.get_node_or_null("UIOrchestrator")
	check(orch != null, "Autoload UIOrchestrator presente")
	if orch == null:
		return
	check(orch.has_method("open_crafting") and orch.has_method("open_trade"), "UIOrchestrator expone open_crafting y open_trade")
	var w = orch.open_crafting("alchemy", "elixir_savia")
	await _frames(2)
	check(w != null and w.get_script() != null and w.window_id == "crafting_window", "open_crafting instancia CraftingWindow")
	check(w != null and w.profession == "alchemy", "open_crafting aplica la profesión (Alquimia)")
	check(w != null and w.selected_id == "elixir_savia", "open_crafting selecciona la receta pedida")
	check(orch.is_window_open("crafting_window"), "crafting_window queda abierta")
	var w2 = orch.open_crafting()
	await _frames(1)
	check(w2 == w and w.profession == "blacksmithing", "Reabrir con valores por defecto vuelve a Herrería en la misma instancia")
	orch.close_window("crafting_window", true)
	await _frames(1)
	check(not orch.is_window_open("crafting_window"), "close_window cierra Fabricación")
	var t = orch.open_trade("Sasha")
	await _frames(2)
	check(t != null and t.get_script() != null and t.window_id == "trade_window", "open_trade instancia TradeWindow")
	check(t != null and t.service.target_name == "Sasha" and t.service.active, "open_trade abre una sesión con Sasha")
	check(t != null and t.title_label_big.text == "Trato con Sasha", "Cabecera «Trato con Sasha»")
	var t2 = orch.open_trade("Toro", {"distance_m": 5, "reputation": "Nuevo", "remote_offer": {"items": [{"item_id": "seda", "qty": 2}], "gold": 10}})
	await _frames(2)
	check(t2 == t and t.service.target_name == "Toro", "open_trade con otro objetivo reinicia la sesión")
	check(t.subtitle_label.text == "Cara a cara · a 5 m · reputación: Nuevo", "target_data llega a la cabecera")
	check(t.service.market_value(TS.REMOTE) == 90, "target_data define la oferta de la contraparte (2 seda + 10 oro)")
	orch.close_window("trade_window", true)
	await _frames(1)
	check(not orch.is_window_open("trade_window"), "close_window cierra el Trato")


# --------------------------------------------------------------------------
# 3. Modelo de Fabricación
# --------------------------------------------------------------------------
func _test_crafting_seed() -> void:
	print("-- 3. CraftingService: seed, profesiones y Forja")
	var s := _cs()
	check(s.professions.size() == 3, "3 profesiones")
	for pid in ["blacksmithing", "alchemy", "cooking"]:
		check(not s.get_profession(pid).is_empty(), "Profesión presente: " + pid)
	var b: Dictionary = s.get_profession("blacksmithing")
	check(b["name"] == "Herrería" and b["mastery_name"] == "Herrería de grieta", "Herrería de grieta")
	check(int(b["mastery"]) == 142 and int(b["mastery_max"]) == 300, "Maestría 142 / 300")
	check(is_equal_approx(float(b["ratio"]), 142.0 / 300.0), "Ratio de maestría 47 %")
	check(s.get_profession("alchemy")["name"] == "Alquimia" and s.get_profession("cooking")["name"] == "Cocina", "Alquimia y Cocina")
	check(s.list_recipes("blacksmithing").size() == 8, "8 recetas de Herrería")
	check(s.list_recipes("alchemy").size() == 3 and s.list_recipes("cooking").size() == 3, "3 de Alquimia y 3 de Cocina")
	check(s.list_recipes("blacksmithing")[0]["id"] == "hoja_grieta", "Orden del seed: Hoja de la grieta primero")
	check(s.forge_level() == 2, "Forja del refugio nivel 2")
	check(s.forge_banner() == "Forja de tu refugio · nivel 2 · trabaja aunque no estés", "Banner de la Forja")
	check(s.queue_slots() == 4, "Huecos de cola = 2 + nivel")
	s.set_forge_level(3)
	check(s.queue_slots() == 5 and s.forge_banner().contains("nivel 3"), "Subir la Forja da más huecos")
	check(is_equal_approx(s.offline_cap_s(), 12.0 * 3600.0), "Tope sin conexión 12 h")
	var r: Dictionary = s.get_recipe("hoja_grieta")
	check(r["name"] == "Hoja de la grieta" and r["profession"] == "blacksmithing" and int(r["level_req"]) == 120, "Receta: id, nombre, profesión, nivel requerido")
	check(is_equal_approx(float(r["time_s"]), 45.0), "Tiempo base 45 s por unidad")
	check(r["materials"].size() == 4 and r["materials"][0]["id"] == "lingote_ferrum" and int(r["materials"][0]["qty"]) == 2, "Materiales requeridos (id, cantidad)")
	check(s.recipe_subtitle("hoja_grieta") == "Arma · Nv. obj. 410–425 según calidad · 45 s por unidad", "Subtítulo con iLvl y tiempo")
	check(s.recipe_subtitle("clavos_runicos") == "Material · 6,5 s por unidad", "Subtítulo sin iLvl y con decimales")
	check(CS.rarity_color("epic") == Color("#b47bff") and CS.rarity_color("legendary") == Color("#f5a742"), "Colores de rareza (épico/legendario)")
	check(CS.rarity_color("rare") == Color("#5aa9ff") and CS.rarity_color("uncommon") == Color("#4fe39a") and CS.rarity_color("common") == Color("#b8c3ca"), "Colores de rareza (raro/poco común/común)")
	check(CS.quality_name("good") == "Buena" and CS.quality_name("epic") == "Épica" and CS.quality_name("legendary") == "Legendaria", "Nombres de calidad")
	check(s.have("esquirla_grieta") == 9 and s.have_inventory("esquirla_grieta") == 5 and s.have_bank("esquirla_grieta") == 4, "Materiales: mochila + banco")
	var sh: Node = SHS.new()
	sh.load_seed()
	var shelter_level := 0
	for room in sh.find_rooms("forja"):
		shelter_level = max(shelter_level, int(room["level"]))
	check(s.sync_with_shelter(sh) and s.forge_level() == shelter_level, "sync_with_shelter toma el nivel de la sala Forja del Refugio")
	check(not s.sync_with_shelter(null), "sync_with_shelter(null) no rompe")
	sh.free()
	s.free()


func _test_badges() -> void:
	print("-- 4. Disponibilidad de recetas (badges)")
	var s := _cs()
	var expect := {
		"hoja_grieta": ["can", "Puedes crear 1"],
		"guja_ferrum": ["missing", "Falta 1 material"],
		"coraza_vado": ["can", "Puedes crear 1"],
		"guanteletes_eco": ["missing", "Faltan 2 materiales"],
		"lingote_ferrum": ["can", "Puedes crear 18"],
		"clavos_runicos": ["can", "Puedes crear 40"],
		"yelmo_umbral": ["locked", "Receta: botín de raid"],
		"afilador_grieta": ["can", "Puedes crear 6"],
		"tonico_triple": ["can", "Puedes crear 3"],
		"elixir_savia": ["can", "Puedes crear 3"],
		"frasco_eco": ["mastery", "Requiere maestría 120"],
		"guiso_nido": ["can", "Puedes crear 4"],
		"pan_ambar": ["can", "Puedes crear 4"],
		"festin_raid": ["mastery", "Requiere maestría 80"],
	}
	for rid in expect:
		var b: Dictionary = s.recipe_badge(rid)
		check(b["state"] == expect[rid][0] and b["text"] == expect[rid][1], "%s -> «%s»" % [rid, expect[rid][1]])
	check(s.recipe_badge("hoja_grieta")["color"] == Color("#4fe39a"), "«Puedes crear» en verde")
	check(s.recipe_badge("guja_ferrum")["color"] == Color("#9aa6ae"), "«Faltan» en gris")
	check(s.max_craftable("guja_ferrum") == 0 and s.missing_units("guja_ferrum", 1) == 1, "Guja: falta 1 Núcleo de ferrum")
	check(s.missing_units("hoja_grieta", 3) == 4, "Hoja ×3: faltan 4 de cuero")
	var rows: Array = s.material_rows("hoja_grieta", 3)
	check(rows.size() == 4, "4 filas de materiales")
	check(rows[0]["have"] == 6 and rows[0]["need"] == 6 and rows[0]["ok"] and rows[0]["source"] == "inventario", "Lingote 6 / 6 · inventario")
	check(rows[1]["have"] == 9 and rows[1]["need"] == 9 and rows[1]["source"] == "inventario + banco", "Esquirla 9 / 9 · inventario + banco")
	check(rows[2]["have"] == 2 and rows[2]["need"] == 6 and not rows[2]["ok"] and rows[2]["source"] == "mercado · 22 c/u", "Cuero 2 / 6 · mercado · 22 c/u")
	check(rows[3]["have"] == 3 and rows[3]["need"] == 3, "Resina 3 / 3")
	check(s.material_rows("hoja_grieta", 0)[0]["need"] == 2, "Cantidad mínima 1")
	var grid: Array = s.get_material_grid()
	check(grid.size() == 16, "Cuadrícula: 16 materiales con existencias en la mochila")
	check(grid[0]["rarity"] == "epic", "Cuadrícula ordenada por rareza (épicos primero)")
	var ids: Array = grid.map(func(g): return g["id"])
	check(not ids.has("nucleo_ferrum") and not ids.has("lingote_ferrum_3"), "Sin existencias no aparecen en la cuadrícula")
	s.free()


func _test_quality() -> void:
	print("-- 5. Calidad probable, catalizador y material mejorado")
	var s := _cs()
	var base: Dictionary = s.quality_distribution("hoja_grieta")
	check(base == {"normal": 10, "good": 45, "rare": 35, "epic": 10, "legendary": 0}, "Base Hoja: Normal 10 · Buena 45 · Rara 35 · Épica 10")
	check(_sum(base) == 100, "La base suma 100")
	var cat: Dictionary = s.quality_distribution("hoja_grieta", "catalizador_grieta")
	check(_sum(cat) == 100, "Con catalizador suma 100")
	check(int(cat["epic"]) + int(cat["legendary"]) == int(base["epic"]) + int(base["legendary"]) + 15, "Catalizador: +15 % a épica + legendaria")
	check(int(cat["epic"]) == 20 and int(cat["legendary"]) == 5, "Reparto 10 épica / 5 legendaria")
	check(int(cat["normal"]) == 0 and int(cat["good"]) == 40, "Los puntos salen de las calidades más bajas")
	check(int(cat["rare"]) == 35, "Rara no cambia")
	var up: Dictionary = s.quality_distribution("hoja_grieta", "", ["lingote_ferrum"])
	check(int(up["epic"]) == 22 and _sum(up) == 100, "Lingote ★★★: Épica sube a 22 %")
	check(int(up["normal"]) == 0 and int(up["good"]) == 43, "La mejora resta de Normal y luego Buena")
	var both: Dictionary = s.quality_distribution("hoja_grieta", "catalizador_grieta", ["lingote_ferrum"])
	check(int(both["epic"]) == 32 and int(both["legendary"]) == 5 and _sum(both) == 100, "Mejora + catalizador se acumulan")
	check(s.quality_distribution("hoja_grieta", "", ["esquirla_grieta"]) == base, "Mejorar un material sin mejora no cambia nada")
	var cor: Dictionary = s.quality_distribution("coraza_vado", "catalizador_grieta")
	check(int(cor["epic"]) == 20 and int(cor["legendary"]) == 0 and _sum(cor) == 100, "Receta con tope épico: todo el bonus a Épica")
	check(not s.quality_allowed("coraza_vado", "legendary") and s.quality_allowed("coraza_vado", "epic"), "Calidades permitidas según la receta")
	check(not s.can_use_catalyst("lingote_ferrum") and s.can_use_catalyst("hoja_grieta"), "Catalizador solo en recetas con Épica")
	check(s.quality_distribution("lingote_ferrum", "catalizador_grieta") == s.quality_distribution("lingote_ferrum"), "Sin efecto donde no aplica")
	check(not s.can_use_catalyst("hoja_grieta", "inexistente"), "Modificador desconocido no aplica")
	var hint: Dictionary = s.upgrade_hint("hoja_grieta")
	check(hint.get("pct", 0) == 22 and hint.get("upgrade", "") == "lingote_ferrum_3", "Pista: cambiar el Lingote sube Épica a 22 %")
	check(str(hint.get("text", "")) == "Cambiar el Lingote de ferrum por calidad ★★★ sube «Épica» a 22 %.", "Texto de la pista")
	check(s.upgrade_hint("coraza_vado").is_empty(), "Sin pista si no hay material mejorable")
	check(s.ilvl_for_quality("hoja_grieta", "normal") == 410 and s.ilvl_for_quality("hoja_grieta", "legendary") == 425, "iLvl 410–425 según calidad")
	check(s.ilvl_for_quality("hoja_grieta", "epic") == 421 and s.ilvl_for_quality("hoja_grieta", "good") == 414, "iLvl intermedio interpolado")
	check(s.ilvl_for_quality("clavos_runicos", "good") == 0, "Materiales sin iLvl")
	check(s.roll_quality({"normal": 0, "good": 0, "rare": 0, "epic": 100, "legendary": 0}) == "epic", "Tirada con 100 % épica")
	s.rng.seed = 42
	var counts := {"normal": 0, "good": 0, "rare": 0, "epic": 0, "legendary": 0}
	for i in 4000:
		counts[s.roll_quality(cat)] += 1
	check(counts["normal"] == 0, "Nunca sale una calidad al 0 %")
	check(absf(counts["good"] / 4000.0 - 0.40) < 0.03, "Frecuencia Buena ≈ 40 %% (%d)" % counts["good"])
	check(absf(counts["epic"] / 4000.0 - 0.20) < 0.03, "Frecuencia Épica ≈ 20 %% (%d)" % counts["epic"])
	check(absf(counts["legendary"] / 4000.0 - 0.05) < 0.02, "Frecuencia Legendaria ≈ 5 %% (%d)" % counts["legendary"])
	s.free()


func _test_craft_now() -> void:
	print("-- 6. Fabricar ahora (banco de trabajo)")
	var s := _cs()
	var crafted_sig := []
	s.crafted.connect(func(rid, res): crafted_sig.append([rid, res.size()]))
	var res: Dictionary = s.craft_now("hoja_grieta", 1)
	check(res["ok"] and res["results"].size() == 1, "Fabrica 1 Hoja de la grieta")
	check(s.have_inventory("lingote_ferrum") == 4 and s.have("cuero_curtido") == 0 and s.have("resina_verdalia") == 2, "Consume lingote, cuero y resina")
	check(s.have_inventory("esquirla_grieta") == 2 and s.have_bank("esquirla_grieta") == 4, "Consume primero de la mochila (esquirlas)")
	check(s.crafted_items.size() == 1 and s.crafted_items[0]["name"] == "Hoja de la grieta", "El objeto va a la mochila")
	var it: Dictionary = s.crafted_items[0]
	check(CS.QUALITY_ORDER.has(it["quality"]) and it["ilvl"] >= 410 and it["ilvl"] <= 425, "Calidad e iLvl dentro del rango")
	check(it["seal"] == "Tú", "Lleva el sello de artesano")
	check(int(s.get_profession("blacksmithing")["mastery"]) == 148, "Maestría +6")
	check(crafted_sig == [["hoja_grieta", 1]], "Señal crafted")
	check(s.craft_now("hoja_grieta", 1)["reason"] == "missing_materials", "Sin materiales no fabrica")
	check(s.craft_now("yelmo_umbral", 1)["reason"] == "recipe_locked", "Receta de raid bloqueada")
	check(s.craft_now("frasco_eco", 1)["reason"] == "mastery_too_low", "Maestría insuficiente")
	check(s.craft_now("nope", 1)["reason"] == "unknown_recipe", "Receta desconocida")
	check(s.craft_now("clavos_runicos", 0)["reason"] == "invalid_qty", "Cantidad inválida")
	check(s.craft_now("lingote_ferrum", 1, "catalizador_grieta")["reason"] == "catalyst_not_applicable", "Catalizador no aplicable")
	var esq_bank: int = s.have_bank("esquirla_grieta")
	s.consume_material("esquirla_grieta", 3)
	check(s.have_inventory("esquirla_grieta") == 0 and s.have_bank("esquirla_grieta") == esq_bank - 1, "consume_material salta al banco cuando la mochila no alcanza")
	check(not s.consume_material("esquirla_grieta", 999), "consume_material sin existencias falla sin cambios")
	var before: int = s.have("lingote_ferrum")
	var r2: Dictionary = s.craft_now("lingote_ferrum", 5)
	check(r2["ok"] and s.have("lingote_ferrum") == before + 5 and s.have("mineral_ferrum") == 39, "Lingotes: el resultado vuelve como material")
	var s2 := _cs()
	var r3: Dictionary = s2.craft_now("coraza_vado", 1, "catalizador_grieta")
	check(r3["ok"] and s2.have("catalizador_grieta") == 1, "El catalizador se consume (1 por lote)")
	s2.inventory["catalizador_grieta"] = 0
	s2.inventory["lingote_ferrum"] = 10
	s2.inventory["cuero_curtido"] = 10
	check(s2.craft_now("coraza_vado", 1, "catalizador_grieta")["reason"] == "missing_catalyst", "Sin catalizador no fabrica con él")
	s2.at_workbench = false
	check(s2.craft_now("coraza_vado", 1)["reason"] == "not_at_workbench", "«Fabricar ahora» exige banco de trabajo")
	check(s2.queue_craft_in_shelter("coraza_vado", 1)["ok"], "…pero la Forja del Refugio sí acepta el encargo")
	s.free()
	s2.free()


func _test_forge_queue() -> void:
	print("-- 7. Cola de la Forja del Refugio")
	var s := _cs()
	var v: Array = s.get_queue_view()
	check(v.size() == 3, "Cola inicial con 3 trabajos")
	check(v[0]["label"] == "Lingote de ferrum ×10" and v[0]["remaining_text"] == "00:42", "Lingote de ferrum ×10 · 00:42")
	check(is_equal_approx(float(v[0]["ratio"]), 0.7) and v[0]["active"], "Primer trabajo al 70 % y activo")
	check(v[1]["label"] == "Clavos rúnicos ×20" and v[1]["remaining_text"] == "02:10" and not v[1]["active"], "Clavos rúnicos ×20 · 02:10")
	check(v[2]["label"] == "Afilador de grieta ×2" and v[2]["remaining_text"] == "03:00", "Afilador de grieta ×2 · 03:00")
	check(is_equal_approx(s.eta_s(2), 42.0 + 130.0 + 180.0), "ETA acumulada del tercero")
	check(s.queue[0]["done_units"] == 7, "Unidades ya terminadas del primero (7/10)")
	var mineral: int = s.have("mineral_ferrum")
	var q: Dictionary = s.queue_craft_in_shelter("lingote_ferrum", 4)
	check(q["ok"] and s.queue.size() == 4, "Añadir a la cola de la Forja")
	check(s.have("mineral_ferrum") == mineral - 12, "Encolar consume los materiales al momento")
	check(s.queue_craft_in_shelter("clavos_runicos", 1)["reason"] == "queue_full", "Cola llena (4 / 4)")
	var completed := []
	s.job_completed.connect(func(j): completed.append(j["recipe_id"]))
	var done: Array = s.tick(10.0)
	check(done.is_empty() and s.get_queue_view()[0]["remaining_text"] == "00:32", "tick(10): 00:32 restantes")
	check(s.queue[0]["done_units"] == 7, "Las unidades avanzan por tiempo")
	done = s.tick(40.0)
	check(done.size() == 1 and completed == ["lingote_ferrum"], "Termina el primero y el sobrante pasa al siguiente")
	check(s.queue.size() == 3 and is_equal_approx(float(s.queue[0]["elapsed_s"]), 8.0), "El segundo ya lleva 8 s")
	check(s.forge_output.size() == 10, "10 lingotes esperan en la salida de la Forja")
	check(s.forge_output[0]["output_material"] == "lingote_ferrum", "Salida etiquetada con su material")
	var lingotes: int = s.have_inventory("lingote_ferrum")
	var got: Array = s.collect_forge_output()
	check(got.size() == 10 and s.have_inventory("lingote_ferrum") == lingotes + 10 and s.forge_output.is_empty(), "Recoger pasa los lingotes a la mochila")
	var job_id: String = s.queue[1]["job_id"]
	var piedra: int = s.have("piedra_afilar")
	var c: Dictionary = s.cancel_job(job_id)
	check(c["ok"] and int(c["refunded_units"]) == 2 and s.have("piedra_afilar") == piedra + 2, "Cancelar devuelve los materiales")
	check(s.queue.size() == 2, "El trabajo cancelado sale de la cola")
	check(not s.cancel_job("job_x")["ok"], "Cancelar un trabajo inexistente falla")
	check(s.queue_craft_in_shelter("hoja_grieta", 99)["reason"] == "missing_materials", "No se encola sin materiales")
	var qc: Dictionary = s.queue_craft_in_shelter("hoja_grieta", 1, "catalizador_grieta", ["lingote_ferrum"])
	check(qc["reason"] == "missing_materials", "Con el material mejorado hay que tenerlo (Lingote ★★★)")
	s.add_material("lingote_ferrum_3", 2)
	qc = s.queue_craft_in_shelter("hoja_grieta", 1, "catalizador_grieta", ["lingote_ferrum"])
	check(qc["ok"] and s.have("lingote_ferrum_3") == 0 and s.have("catalizador_grieta") == 1, "Encolar con mejora y catalizador los consume")
	s.tick(10000.0)
	check(s.queue.is_empty(), "Con tiempo suficiente la Forja vacía la cola")
	check(s.forge_output[-1]["recipe_id"] == "hoja_grieta" and int(s.forge_output[-1]["ilvl"]) >= 410, "La Hoja terminada en la Forja tiene iLvl")
	check(CS.format_time(42.0) == "00:42" and CS.format_time(130.0) == "02:10" and CS.format_time(3725.0) == "1:02:05", "format_time mm:ss y h:mm:ss")
	check(CS.format_time(41.2) == "00:42" and CS.format_time(-3.0) == "00:00", "format_time redondea hacia arriba y no es negativo")
	s.free()


func _test_offline_and_persistence() -> void:
	print("-- 8. Sin conexión (tope 12 h) y persistencia")
	var s := _cs()
	var r: Dictionary = s.apply_offline(60.0)
	check(is_equal_approx(float(r["applied_s"]), 60.0) and not r["capped"], "1 min desconectado se aplica entero")
	check(r["completed"].size() == 1 and s.queue.size() == 2, "La Forja trabaja sin el jugador")
	var s2 := _cs()
	s2.inventory["mineral_ferrum"] = 999999
	for i in 1:
		s2.queue_craft_in_shelter("lingote_ferrum", 9000)
	var r2: Dictionary = s2.apply_offline(48.0 * 3600.0)
	check(r2["capped"] and is_equal_approx(float(r2["applied_s"]), 12.0 * 3600.0), "Tope de 12 h sin conexión")
	check(not s2.queue.is_empty(), "Lo que excede el tope sigue en cola: nada se pierde")
	var s3 := _cs()
	var d: Dictionary = s3.to_dict(1000)
	check(d["saved_at"] == 1000 and d["queue"].size() == 3 and d["forge_level"] == 2, "to_dict guarda cola, nivel y hora")
	var s4 := _cs()
	s4.queue.clear()
	var lr: Dictionary = s4.load_state(d, 1000 + 172)
	check(is_equal_approx(float(lr["applied_s"]), 172.0), "load_state aplica el tiempo fuera (172 s)")
	check(s4.queue.size() == 1 and s4.queue[0]["recipe_id"] == "afilador_grieta", "Al volver: lingotes y clavos terminados")
	check(s4.forge_output.size() == 30, "30 piezas esperando en la Forja")
	check(int(s4.get_profession("blacksmithing")["mastery"]) == 142 + 10 + 20, "La maestría sube con lo fabricado en segundo plano")
	for x in [s, s2, s3, s4]:
		x.free()


func _test_buy_missing() -> void:
	print("-- 9. Comprar lo que falta")
	var s := _cs()
	check(s.missing_cost("hoja_grieta", 3) == 88, "Hoja ×3: faltan 4 cueros · 88 oro")
	check(s.missing_cost("hoja_grieta", 1) == 0, "Hoja ×1: no falta nada")
	check(s.buy_missing("hoja_grieta", 1, null)["reason"] == "nothing_missing", "Nada que comprar")
	check(s.buy_missing("hoja_grieta", 3, null)["reason"] == "no_wallet", "Sin cartera no compra")
	var com: Node = COM.new()
	com.load_seed()
	var gold: int = com.gold
	var r: Dictionary = s.buy_missing("hoja_grieta", 3, com)
	check(r["ok"] and int(r["cost"]) == 88 and com.gold == gold - 88, "Compra y cobra 88 oro")
	check(s.have("cuero_curtido") == 6 and s.max_craftable("hoja_grieta") == 3, "Ahora puedes crear 3")
	com.gold = 5
	s.inventory["cuero_curtido"] = 0
	check(s.buy_missing("hoja_grieta", 3, com)["reason"] == "not_enough_gold", "Sin oro suficiente no compra")
	check(s.have("cuero_curtido") == 0, "…y no añade nada")
	com.free()
	s.free()


# --------------------------------------------------------------------------
# 10. CraftingWindow
# --------------------------------------------------------------------------
func _test_crafting_window() -> void:
	print("-- 10. CraftingWindow (3 columnas)")
	var s := _cs()
	var com: Node = COM.new()
	com.load_seed()
	var w = CraftingScene.instantiate()
	w.service = s
	w.commerce = com
	root.add_child(w)
	await _frames(2)
	check(w.get_script() != null and w.window_id == "crafting_window", "CraftingWindow con script")
	check(w.size.x <= 1280.0 and w.size.y <= 720.0, "Cabe en 1280×720 (%s)" % str(w.size))
	check(w.menu_bar != null and w.menu_bar.get("active_tab") == "refugio", "Menú común con Refugio activo")
	check(w.find_child("RecipesCard", true, false) != null and w.find_child("DetailCard", true, false) != null and w.find_child("QueueCard", true, false) != null, "Tres columnas: recetas, detalle y cola")
	check(w.profession_buttons.size() == 3 and w.profession_buttons["blacksmithing"].button_pressed, "Selector de profesiones (Herrería activa)")
	check(w.profession_buttons["alchemy"].text == "Alquimia" and w.profession_buttons["cooking"].text == "Cocina", "Chips Alquimia y Cocina")
	check(w.forge_banner_label.text == "Forja de tu refugio · nivel 2 · trabaja aunque no estés", "Banner de la Forja")
	check(w.mastery_name_label.text == "Herrería de grieta" and w.mastery_value_label.text == "142 / 300", "Maestría 142 / 300")
	check(is_equal_approx(w.mastery_bar.ratio, 142.0 / 300.0), "Barra de maestría")
	check(w.recipe_rows.size() == 8, "8 recetas en la lista")
	check(w.selected_id == "hoja_grieta" and w.recipe_rows["hoja_grieta"].button_pressed, "Primera receta seleccionada")
	check(w.recipe_badges["lingote_ferrum"].text == "Puedes crear 18", "Badge «Puedes crear 18»")
	check(w.recipe_badges["guanteletes_eco"].text == "Faltan 2 materiales", "Badge «Faltan 2 materiales»")
	check(w.recipe_badges["yelmo_umbral"].text == "Receta: botín de raid", "Badge «Receta: botín de raid»")
	var name_lbl: Label = w.recipe_rows["hoja_grieta"].find_child("Name", true, false)
	check(name_lbl != null and name_lbl.get_theme_color("font_color") == CS.rarity_color("epic"), "Nombre con color de rareza")
	check(w.detail_name_label.text == "Hoja de la grieta", "Detalle: nombre")
	check(w.detail_sub_label.text == "Arma · Nv. obj. 410–425 según calidad · 45 s por unidad", "Detalle: tipo, iLvl y tiempo")
	check(w.detail_icon.border == CS.rarity_color("epic") and w.detail_icon.glow, "Icono grande con brillo de rareza")
	check(w.quality_bar.dist == s.quality_distribution("hoja_grieta"), "Barra de calidad probable")
	var segs: Array = w.quality_bar.segments()
	check(segs.size() == 4 and segs[1]["quality"] == "good" and segs[1]["pct"] == 45, "4 tramos (Buena 45 %)")
	check(w.hint_label.visible and w.hint_label.text.contains("22 %"), "Pista del material mejorado")
	check(w.material_row_nodes.size() == 4, "4 materiales")
	check(w.material_row_nodes[0]["count"].text == "6 / 2", "Contador poseído / necesario (×1)")
	check(w.material_row_nodes[0]["search"].text == "Buscar en mercado", "Botón «Buscar en mercado»")
	check(w.catalyst_panel.visible and not w.catalyst_button.disabled, "Ranura de catalizador disponible")
	check(w.qty_presets.has("1") and w.qty_presets.has("5") and w.qty_presets.has("max"), "Selector de cantidad 1 · 5 · Máx")
	check(w.craft_button.text == "Fabricar ahora ×1" and not w.craft_button.disabled, "«Fabricar ahora ×1» activo")
	check(w.queue_button.text == "Añadir a la cola de la Forja", "«Añadir a la cola de la Forja»")
	check(not w.queue_button.disabled, "Cola con hueco (3 / 4): botón activo")
	check(w.queue_rows.size() == 3, "Columna derecha: 3 trabajos en la Forja")
	check(w.queue_rows[0]["time"].text == "00:42" and is_equal_approx(w.queue_rows[0]["bar"].ratio, 0.7), "Temporizador 00:42 y barra 70 %")
	check(w.queue_caps.text == "COLA DE LA FORJA · 3 / 4", "Cabecera de la cola con huecos")
	check(w.grid_cells.size() == 16, "Cuadrícula de materiales de la mochila")
	check(w.grid_cells[0].border == CS.rarity_color("epic") and w.grid_cells[0].count_text == "2", "Celda con borde de rareza y cantidad")
	# Cantidad
	w.set_qty(3)
	check(w.qty_label.text == "3" and w.materials_caps.text == "MATERIALES PARA 3 UNIDADES", "Cantidad 3")
	check(w.material_row_nodes[2]["count"].text == "2 / 6" and w.material_row_nodes[2]["count"].get_theme_color("font_color") == Color("#ff8a8a"), "Cuero 2 / 6 en rojo")
	check(w.craft_button.disabled and w.queue_button.disabled, "Sin materiales para ×3: acciones desactivadas")
	check(w.buy_button.text == "Comprar lo que falta · 88" and not w.buy_button.disabled, "«Comprar lo que falta · 88»")
	w.set_qty_preset("max")
	check(w.qty == 1, "«Máx» = lo que permiten los materiales (1)")
	w.set_qty_preset("5")
	check(w.qty == 5, "Preset 5")
	w.set_qty(0)
	check(w.qty == 1 and w.qty_minus.disabled, "La cantidad nunca baja de 1")
	# Catalizador y mejora
	w.set_use_catalyst(true)
	check(w.use_catalyst and w.quality_bar.dist == s.quality_distribution("hoja_grieta", "catalizador_grieta"), "Catalizador: la barra se actualiza (+15 %)")
	check(w.catalyst_button.text == "Quitar", "Botón del catalizador pasa a «Quitar»")
	w.set_use_upgrade(true)
	check(int(w.quality_bar.dist["epic"]) == 32, "Mejora + catalizador: Épica 32 %")
	check(w.material_row_nodes[0]["id"] == "lingote_ferrum_3" and w.material_row_nodes[0]["count"].text == "0 / 2", "Con la mejora pide Lingote ★★★")
	w.set_use_upgrade(false)
	# Buscar en mercado
	var searched := []
	w.market_search_requested.connect(func(q): searched.append(q))
	w.search_market("cuero_curtido")
	check(searched == ["Cuero curtido"], "«Buscar en mercado» emite la búsqueda del material")
	# Fabricar
	var res: Dictionary = w.craft_now()
	check(res["ok"] and s.crafted_items.size() == 1, "Fabricar ahora desde la ventana")
	check(not w.use_catalyst and s.have("catalizador_grieta") == 1, "El catalizador se gasta y se quita de la ranura")
	check(w.recipe_badges["hoja_grieta"].text == "Faltan 2 materiales", "El badge se recalcula tras fabricar («Faltan 2 materiales»)")
	check(w.feedback_label.text.begins_with("Fabricado ×1"), "Mensaje de resultado")
	# Cola
	w.select_recipe("lingote_ferrum")
	w.set_qty(4)
	var qr: Dictionary = w.queue_in_forge()
	check(qr["ok"] and w.queue_rows.size() == 4, "Añadir a la cola desde la ventana")
	check(w.queue_button.disabled, "Cola llena: botón desactivado")
	check(w.queue_in_forge()["reason"] == "queue_full", "Cola llena: no encola")
	s.tick(42.0)
	w.refresh()
	check(w.queue_rows.size() == 3 and w.output_row.visible and w.output_label.text == "Listo en la Forja: 10", "Al terminar aparece «Listo en la Forja»")
	w.collect_output()
	check(not w.output_row.visible and s.forge_output.is_empty(), "Recoger vacía la salida")
	w.cancel_job(s.queue[-1]["job_id"])
	check(w.queue_rows.size() == 2, "Cancelar desde la ventana")
	# Profesiones e initialize_window
	w.set_profession("alchemy")
	check(w.profession == "alchemy" and w.recipe_rows.size() == 3 and w.selected_id == "tonico_triple", "Cambiar a Alquimia")
	check(w.mastery_name_label.text == "Alquimia de savia" and w.profession_buttons["alchemy"].button_pressed, "Maestría de Alquimia")
	check(w.recipe_badges["frasco_eco"].text == "Requiere maestría 120", "Badge de maestría insuficiente")
	w.select_recipe("tonico_triple")
	check(w.catalyst_button.disabled and w.catalyst_label.text.contains("no aplica"), "Catalizador no aplica a Tónico triple")
	w.initialize_window({"recipe_id": "festin_raid"})
	check(w.profession == "cooking" and w.selected_id == "festin_raid", "initialize_window salta a la profesión de la receta")
	check(w.craft_button.disabled, "Receta sin maestría: no se puede fabricar")
	w.initialize_window({"profession": "blacksmithing", "recipe_id": "yelmo_umbral"})
	check(w.selected_id == "yelmo_umbral" and w.craft_button.disabled and w.queue_button.disabled, "Receta de raid: bloqueada")
	s.at_workbench = false
	w.select_recipe("clavos_runicos")
	check(w.craft_button.disabled and not w.queue_button.disabled, "Sin banco: solo la cola de la Forja")
	w.queue_free()
	await _frames(1)
	_free(com)
	_free(s)


# --------------------------------------------------------------------------
# 11. TradeService
# --------------------------------------------------------------------------
func _test_trade_session() -> void:
	print("-- 11. TradeService: sesión y valor de mercado")
	var t := _ts()
	check(t.active and t.state == TS.State.EDITING, "Sesión activa en EDITING")
	check(TS.state_key(t.state) == "EDITING" and TS.STATE_KEYS.size() == 6, "Claves de estado")
	for k in ["EDITING", "CONFIRMED_LOCAL", "CONFIRMED_REMOTE", "LOCKED_BOTH", "COMPLETED"]:
		check(TS.STATE_KEYS.has(k), "Estado " + k)
	check(t.header_text() == "Trato con Sasha", "Cabecera")
	check(t.header_subtitle() == "Cara a cara · a 3 m · reputación: Confiable", "Distancia y reputación")
	check(t.get_offer(TS.LOCAL)["items"].size() == 2 and t.get_offer(TS.LOCAL)["gold"] == 150, "Tú das: mapa, lingotes y 150 oro")
	check(t.get_offer(TS.REMOTE)["items"].size() == 3, "Sasha da: 3 objetos")
	check(t.market_value(TS.LOCAL) == 1410, "Valor de mercado de tu oferta: 1.410")
	check(t.market_value(TS.REMOTE) == 2500, "Valor de mercado de Sasha: 2.500")
	check(t.balance() == 1090, "Balance 1.090 a tu favor")
	check(TS.fmt(1410) == "1.410" and TS.fmt(12480) == "12.480" and TS.fmt(90) == "90" and TS.fmt(1000000) == "1.000.000", "Formato con separador de miles")
	var lv: Array = t.view_offer(TS.LOCAL)
	check(lv.size() == 3 and lv[2]["is_gold"] and lv[2]["display_name"] == "150 oro", "La fila de oro aparece al final")
	check(lv[0]["display_name"] == "Mapa del hallazgo: Cueva de ámbar" and lv[0]["subtitle"] == "Tu secreto · Sasha verá la ubicación", "Mapa del hallazgo: «Tu secreto · Sasha verá la ubicación»")
	check(lv[0]["border_color"] == Color("#c39bff"), "Borde de secreto")
	check(lv[1]["display_name"] == "Lingote de ferrum ★★ ×6" and lv[1]["subtitle"] == "De tu taller", "Lingotes «De tu taller»")
	check(lv[1]["border_color"] == Color("#4fe39a") and lv[2]["border_color"] == Color("#f5c35b"), "Bordes poco común y oro")
	var rv: Array = t.view_offer(TS.REMOTE)
	check(rv.size() == 3, "Sin oro de Sasha: 3 filas")
	check(rv[1]["display_name"] == "Seda ×5" and rv[1]["subtitle"] == "La necesitas para el Nido de Pispa" and rv[1]["subtitle_color"] == Color("#4fe39a"), "Seda: «La necesitas para el Nido de Pispa» en verde")
	check(rv[2]["display_name"] == "Tónico triple ×3" and rv[2]["subtitle"] == "", "Tónico triple ×3")
	check(t.view_item(TS.REMOTE, 9).is_empty(), "view_item fuera de rango")
	var t2: Node = TS.new()
	t2.load_seed(TRADE_SEED)
	t2.start_session("Toro", {"distance_m": 2.5, "reputation": "Nuevo", "remote_offer": {"items": [{"item_id": "inexistente"}, {"item_id": "seda", "qty": 1}]}})
	check(t2.header_subtitle() == "Cara a cara · a 2.5 m · reputación: Nuevo", "Distancia con decimales")
	check(t2.get_offer(TS.REMOTE)["items"].size() == 1, "Objetos desconocidos se ignoran")
	check(t2.balance() == 40, "Balance de la sesión personalizada")
	check(t2.info_text().contains("40 oro a tu favor"), "Mensaje con el balance")
	t2.set_gold(TS.LOCAL, 40)
	check(t2.info_text().contains("equilibrado"), "Trato equilibrado")
	t2.set_gold(TS.LOCAL, 100)
	check(t2.info_text().contains("60 oro en tu contra"), "Trato en contra")
	t.free()
	t2.free()


func _test_trade_mask_and_reveal() -> void:
	print("-- 12. Máscara «???» del Códice y «Pedir que lo enseñe»")
	var k := _ks()
	var t := _ts(k)
	var v: Dictionary = t.view_item(TS.REMOTE, 0)
	check(v["masked"] and v["name"] == "???" and v["display_name"] == "???", "Objeto no descubierto se muestra como «???»")
	check(v["subtitle"] == "Objeto que no has descubierto · épico", "«Objeto que no has descubierto · épico»")
	check(v["border_color"] == Color("#b47bff"), "Conserva el borde de rareza épica")
	check(v["name_color"] == Color("#c39bff") and v["icon_text"] == "?", "Nombre en violeta secreto e icono «?»")
	check(v["value"] == 2000, "El valor de mercado cuenta aunque esté oculto")
	check(not t.is_masked(TS.LOCAL, "corona_umbral"), "Lo tuyo nunca se enmascara")
	check(not t.is_masked(TS.REMOTE, "seda"), "Sin entrada de Códice no se enmascara")
	check(t.has_masked_remote() and t.masked_remote_ids() == ["corona_umbral"], "Lista de objetos ocultos")
	check(t.info_text() == "Te ofrecen algo que no conoces («???»). Verás su nombre solo si aceptas, o si Sasha te lo enseña antes. El trato está 1.090 oro a tu favor según el mercado.", "Mensaje inferior del HTML")
	k.learn_entry("item_corona_umbral", "objetos", {"name": "Corona del umbral"})
	check(not t.is_masked(TS.REMOTE, "corona_umbral") and t.view_item(TS.REMOTE, 0)["name"] == "Corona del umbral", "Si ya lo conoces en tu Códice se ve el nombre")
	var k2 := _ks()
	var t2 := _ts(k2)
	t2.confirm(TS.LOCAL)
	var req := []
	t2.reveal_requested.connect(func(ids): req.append(ids))
	check(t2.request_reveal() and t2.reveal_pending and req == [["corona_umbral"]], "«Pedir que lo enseñe» lanza la petición")
	check(t2.is_confirmed(TS.LOCAL) and not t2.in_cooldown(), "Pedir que lo enseñe NO borra confirmaciones")
	check(t2.info_text().begins_with("Has pedido a Sasha"), "Mensaje de petición pendiente")
	check(not t2.reveal_remote_item("seda_inexistente"), "No se revela lo que no está en la oferta")
	check(t2.reveal_remote_item("corona_umbral"), "Sasha lo enseña")
	var rv: Dictionary = t2.view_item(TS.REMOTE, 0)
	check(not rv["masked"] and rv["name"] == "Corona del umbral" and rv["subtitle"] == "Te lo enseñó Sasha · épico", "Revelado: nombre y «Te lo enseñó Sasha»")
	check(k2.get_visibility("item_corona_umbral") == KS.SEEN, "Queda «Visto de lejos» en tu Códice")
	check(not k2.is_known("item_corona_umbral"), "…pero no descubierto hasta aceptar")
	check(not t2.has_masked_remote() and not t2.reveal_pending, "Ya no quedan «???»")
	check(not t2.request_reveal(), "Nada más que pedir")
	check(not t2.reveal_remote_item("corona_umbral"), "No se revela dos veces")
	check(t2.is_confirmed(TS.LOCAL), "Revelar tampoco borra confirmaciones")
	var t3: Node = TS.new()
	t3.load_seed(TRADE_SEED)
	t3.start_session("Sasha", {})
	check(t3.is_masked(TS.REMOTE, "corona_umbral"), "Sin Códice disponible todo lo que tiene entrada es «???»")
	for x in [t, k, t2, k2, t3]:
		x.free()


func _test_trade_confirmation_rules() -> void:
	print("-- 13. Doble confirmación simétrica y espera de 3 s")
	var t := _ts()
	var states := []
	var resets := []
	t.state_changed.connect(func(s): states.append(s))
	t.confirmations_reset.connect(func(side): resets.append(side))
	check(t.can_confirm(TS.LOCAL) and t.can_confirm(TS.REMOTE), "Al empezar ambos pueden confirmar")
	check(t.status_text(TS.LOCAL) == "Sin confirmar", "«Sin confirmar»")
	var r: Dictionary = t.confirm(TS.LOCAL)
	check(r["ok"] and t.state == TS.State.CONFIRMED_LOCAL, "Confirmas tú -> CONFIRMED_LOCAL")
	check(t.status_text(TS.LOCAL) == "Confirmado ✓", "«Confirmado ✓»")
	check(t.confirm(TS.LOCAL)["reason"] == "already_confirmed", "No se confirma dos veces")
	check(t.unconfirm(TS.LOCAL) and t.state == TS.State.EDITING, "Retirar tu confirmación -> EDITING")
	check(not t.in_cooldown(), "Retirar la confirmación no activa la espera")
	t.confirm(TS.REMOTE)
	check(t.state == TS.State.CONFIRMED_REMOTE, "Confirma Sasha -> CONFIRMED_REMOTE")
	t.confirm(TS.LOCAL)
	check(t.state == TS.State.LOCKED_BOTH, "Ambos -> LOCKED_BOTH")
	check(not t.can_modify(), "LOCKED_BOTH bloquea las ofertas")
	check(not t.set_gold(TS.LOCAL, 10) and not t.add_item(TS.REMOTE, "seda") and not t.remove_item(TS.LOCAL, 0), "Con LOCKED_BOTH nadie puede cambiar nada")
	check(t.market_value(TS.LOCAL) == 1410 and t.is_confirmed(TS.LOCAL) and t.is_confirmed(TS.REMOTE), "…y las confirmaciones siguen")
	check(not t.unconfirm(TS.LOCAL), "LOCKED_BOTH no se deshace con unconfirm (solo cancelar)")
	check(t.confirm(TS.REMOTE)["reason"] == "locked", "Confirmar bloqueado")
	check(states == [TS.State.CONFIRMED_LOCAL, TS.State.EDITING, TS.State.CONFIRMED_REMOTE, TS.State.LOCKED_BOTH], "Secuencia de estados")
	# Regla estricta: cualquier cambio borra AMBAS confirmaciones y activa 3 s.
	var cases := [
		["local añade objeto", func(x): return x.add_item(TS.LOCAL, "esquirla_grieta", 2)],
		["local quita objeto", func(x): return x.remove_item(TS.LOCAL, 1)],
		["local cambia cantidad", func(x): return x.set_item_qty(TS.LOCAL, 1, 3)],
		["local cambia oro", func(x): return x.set_gold(TS.LOCAL, 200)],
		["Sasha añade objeto", func(x): return x.add_item(TS.REMOTE, "seda", 1)],
		["Sasha quita objeto", func(x): return x.remove_item(TS.REMOTE, 2)],
		["Sasha cambia cantidad", func(x): return x.set_item_qty(TS.REMOTE, 1, 9)],
		["Sasha cambia oro", func(x): return x.set_gold(TS.REMOTE, 75)],
	]
	for c in cases:
		# Con LOCKED_BOTH el cambio se rechaza.
		var x := _ts()
		x.confirm(TS.LOCAL)
		x.confirm(TS.REMOTE)
		var ok: bool = c[1].call(x)
		# Antes del bloqueo: confirma el OTRO lado y quien cambia borra su confirmación.
		var y := _ts()
		y.confirm(TS.REMOTE if c[0].begins_with("local") else TS.LOCAL)
		var had: bool = y.is_confirmed(TS.LOCAL) or y.is_confirmed(TS.REMOTE)
		var changed: bool = c[1].call(y)
		check(not ok and changed and had, "%s: permitido antes del bloqueo y rechazado con LOCKED_BOTH" % c[0])
		check(not y.is_confirmed(TS.LOCAL) and not y.is_confirmed(TS.REMOTE) and y.state == TS.State.EDITING, "%s: se borran AMBAS confirmaciones" % c[0])
		check(is_equal_approx(y.cooldown_remaining, 3.0) and y.confirm_block_reason(TS.LOCAL) == "cooldown" and y.confirm_block_reason(TS.REMOTE) == "cooldown", "%s: 3 s de espera para los dos" % c[0])
		x.free()
		y.free()
	var z := _ts()
	z.confirm(TS.LOCAL)
	z.set_gold(TS.REMOTE, 10)
	var zr := []
	z.confirmations_reset.connect(func(side): zr.append(side))
	z.tick(1.0)
	check(is_equal_approx(z.cooldown_remaining, 2.0) and not z.can_confirm(TS.LOCAL), "Tras 1 s quedan 2 s")
	check(z.info_text().contains("espera 2 s"), "El mensaje muestra la espera")
	z.tick(1.9)
	check(not z.can_confirm(TS.LOCAL), "A los 2,9 s aún no")
	z.tick(0.1)
	check(not z.in_cooldown() and z.can_confirm(TS.LOCAL), "A los 3 s ya se puede confirmar")
	z.confirm(TS.LOCAL)
	z.tick(0.5)
	z.set_gold(TS.LOCAL, 10)
	check(zr == [TS.LOCAL], "confirmations_reset indica quién cambió la oferta")
	z.tick(1.5)
	z.set_item_qty(TS.LOCAL, 1, 7)
	check(is_equal_approx(z.cooldown_remaining, 3.0), "Un nuevo cambio reinicia la espera completa")
	check(z.reset_count == 3, "Contador de cambios")
	check(not z.set_gold(TS.LOCAL, 10), "Poner el mismo oro no es un cambio")
	check(is_equal_approx(z.cooldown_remaining, 3.0) and z.reset_count == 3, "…y no reinicia nada")
	check(not z.set_gold(TS.LOCAL, z.local_gold + 1), "No puedes ofrecer más oro del que tienes")
	check(not z.set_gold(TS.LOCAL, -5), "Oro negativo no")
	check(not z.set_item_qty(TS.LOCAL, 1, 0) and not z.remove_item(TS.LOCAL, 9) and not z.add_item(TS.LOCAL, "nope"), "Cambios inválidos rechazados")
	check(not z.add_item("tercero", "seda"), "Lado desconocido rechazado")
	var before: int = z.get_offer(TS.LOCAL)["items"].size()
	z.add_item(TS.LOCAL, "lingote_ferrum", 2, {"tag": "workshop"})
	check(z.get_offer(TS.LOCAL)["items"].size() == before and int(z.get_offer(TS.LOCAL)["items"][1]["qty"]) == 9, "Añadir lo mismo suma cantidad")
	var e: Node = TS.new()
	e.load_seed(TRADE_SEED)
	e.start_session("Nadie", {"remote_offer": {"items": []}})
	check(e.confirm_block_reason(TS.LOCAL) == "empty_trade", "Un trato vacío no se confirma")
	check(e.confirm_block_reason("x") == "invalid_side", "Lado inválido")
	var n: Node = TS.new()
	check(n.confirm_block_reason(TS.LOCAL) == "no_session" and not n.can_modify(), "Sin sesión no se confirma ni modifica")
	check(n.complete()["reason"] == "not_locked", "Sin bloqueo no se completa")
	check(t.cancel(TS.REMOTE) and t.state == TS.State.CANCELLED and not t.is_confirmed(TS.LOCAL), "Cancelar desde LOCKED_BOTH")
	check(t.info_text() == "Trato cancelado. Nadie entregó nada.", "Mensaje de cancelación")
	check(not t.cancel() and t.complete()["reason"] == "not_locked", "Cancelado no se completa ni se cancela dos veces")
	for x in [t, z, e, n]:
		x.free()


func _test_trade_complete() -> void:
	print("-- 14. Cerrar el trato: oro, Códice y Mapa del hallazgo")
	var k := _ks()
	var t := _ts(k)
	var gold: int = t.local_gold
	var done := []
	t.trade_completed.connect(func(r): done.append(r))
	t.confirm(TS.LOCAL)
	t.confirm(TS.REMOTE)
	check(t.info_text().begins_with("Los dos habéis confirmado"), "Mensaje de bloqueo")
	var r: Dictionary = t.complete()
	check(r["ok"] and t.state == TS.State.COMPLETED, "LOCKED_BOTH -> COMPLETED")
	check(done.size() == 1, "Señal trade_completed")
	check(r["gold_delta"] == -150 and t.local_gold == gold - 150, "Pagas 150 oro")
	check(r["received"].size() == 3 and r["given"].size() == 2, "Recibes 3 objetos y das 2")
	check(k.is_known("item_corona_umbral") and r["learned"].has("item_corona_umbral"), "Lo «???» aceptado entra en tu Códice")
	check(k.display_name("item_corona_umbral") == "Corona del umbral", "…con su nombre")
	check(not t.is_masked(TS.REMOTE, "corona_umbral") and t.view_item(TS.REMOTE, 0)["name"] == "Corona del umbral", "Tras aceptar se ve el nombre")
	check(r["maps_sold"] == ["lugar_cueva_ambar"], "Vendes el Mapa del hallazgo: Sasha verá la ubicación")
	check(t.status_text(TS.LOCAL) == "Hecho ✓", "Estado «Hecho ✓»")
	check(t.info_text().begins_with("Trato cerrado con Sasha"), "Mensaje de trato cerrado")
	check(not t.can_modify() and t.complete()["reason"] == "not_locked", "Completado no se repite")
	# Comprar un Mapa del hallazgo: revela el secreto en tu mapa y Códice.
	var k2: Node = KS.new()
	var b: Node = TS.new()
	b.load_seed(TRADE_SEED)
	b.knowledge = k2
	b.start_session("Orla", {"remote_offer": {"items": [{"item_id": "mapa_cueva_ambar", "qty": 1}]}, "local_offer": {"gold": 900}})
	check(b.view_item(TS.REMOTE, 0)["subtitle"] == "Verás la ubicación en tu mapa y Códice", "Comprar mapa: «Verás la ubicación…»")
	check(b.balance() == 0, "Precio justo: 900 oro")
	b.confirm(TS.REMOTE)
	b.confirm(TS.LOCAL)
	var br: Dictionary = b.complete()
	check(br["learned"].has("lugar_cueva_ambar") and k2.is_known("lugar_cueva_ambar"), "El comprador aprende el secreto")
	var entry: Dictionary = k2.get_entry_view("lugar_cueva_ambar")
	check(str(entry.get("name", "")) == "Cueva de ámbar", "…con su nombre en el Códice")
	check(k2._entries["lugar_cueva_ambar"].get("location", {}).get("zone", "") == "Bosque fósil", "…y la ubicación para su mapa")
	check(br["gold_delta"] == -900, "Pagas 900 oro")
	for x in [t, k, k2, b]:
		x.free()


# --------------------------------------------------------------------------
# 15. TradeWindow
# --------------------------------------------------------------------------
func _test_trade_window() -> void:
	print("-- 15. TradeWindow")
	var k := _ks()
	var t := _ts(k)
	var w = TradeScene.instantiate()
	w.service = t
	w.knowledge = k
	w.drive_clock = false
	root.add_child(w)
	await _frames(3)
	check(w.get_script() != null and w.window_id == "trade_window", "TradeWindow con script")
	check(w.size == Vector2(900, 600), "Tarjeta 900×600 (%s)" % str(w.size))
	check(w.title_label_big.text == "Trato con Sasha", "Título")
	check(w.subtitle_label.text == "Cara a cara · a 3 m · reputación: Confiable", "Distancia y reputación")
	check(w.side_titles[TS.LOCAL].text == "Tú das" and w.side_titles[TS.REMOTE].text == "Sasha da", "Mitades «Tú das» / «Sasha da»")
	check(w.side_status[TS.LOCAL].text == "Sin confirmar" and w.side_status[TS.REMOTE].text == "Sin confirmar", "Ambos sin confirmar")
	check(w.row_nodes[TS.LOCAL].size() == 3 and w.row_nodes[TS.REMOTE].size() == 3, "3 filas por lado")
	var masked: Dictionary = w.row_nodes[TS.REMOTE][0]
	check(masked["name"].text == "???" and masked["subtitle"].text == "Objeto que no has descubierto · épico", "Fila «???» con su texto")
	check(masked["name"].get_theme_color("font_color") == Color("#c39bff"), "«???» en violeta")
	var slot_sb: StyleBoxFlat = masked["slot"].get_theme_stylebox("panel")
	check(slot_sb.border_color == Color("#b47bff"), "Borde de rareza épica en la ranura")
	check(w.row_nodes[TS.LOCAL][1]["subtitle"].text == "De tu taller", "Procedencia «De tu taller»")
	check(w.row_nodes[TS.LOCAL][0]["subtitle"].text == "Tu secreto · Sasha verá la ubicación", "«Tu secreto · Sasha verá la ubicación»")
	check(w.side_value[TS.LOCAL].text == "1.410 oro" and w.side_value[TS.REMOTE].text == "2.500 oro", "Valor de mercado al pie de cada columna")
	check(w.info_label.text == t.info_text() and w.info_label.text.contains("1.090 oro a tu favor"), "Mensaje informativo dinámico")
	check(w.reveal_button.visible and not w.reveal_button.disabled and w.reveal_button.text == "Pedir que lo enseñe", "«Pedir que lo enseñe»")
	check(w.cancel_button.text == "Cancelar" and w.confirm_button.text == "Confirmar" and not w.confirm_button.disabled, "«Cancelar» y «Confirmar»")
	var cbox: StyleBoxFlat = w.confirm_button.get_theme_stylebox("normal")
	check(cbox.bg_color == Color("#46e3c1"), "Confirmar con acento cian")
	check(w.gold_label.text == "150 oro", "Editor de tu oro")
	# Sasha confirma
	t.confirm(TS.REMOTE)
	w.refresh()
	check(w.side_status[TS.REMOTE].text == "Confirmado ✓", "Sasha: «Confirmado ✓»")
	var rsb: StyleBoxFlat = w.side_panels[TS.REMOTE].get_theme_stylebox("panel")
	check(rsb.border_color == Color("#4fe39a") and rsb.border_width_left == 2, "Columna confirmada con borde verde")
	# Tú cambias el oro -> se borran ambas y 3 s
	check(w.change_gold(50), "+50 oro desde la ventana")
	check(not t.is_confirmed(TS.REMOTE) and w.side_status[TS.REMOTE].text == "Sin confirmar", "Tu cambio borra la confirmación de Sasha")
	check(w.confirm_button.disabled and w.confirm_button.text == "Confirmar (3 s)", "Botón en espera «Confirmar (3 s)»")
	check(w.info_label.text.contains("las confirmaciones se borraron"), "El mensaje avisa del reinicio")
	check(w.side_value[TS.LOCAL].text == "1.460 oro", "Valor actualizado")
	var r: Dictionary = w.press_confirm()
	check(not r["ok"] and r["reason"] == "cooldown", "No se confirma durante la espera")
	t.tick(3.0)
	await _frames(1)
	check(not w.confirm_button.disabled and w.confirm_button.text == "Confirmar", "Tras 3 s se reactiva")
	# Pedir que lo enseñe
	check(w.request_reveal() and w.reveal_button.disabled and w.reveal_button.text == "Esperando a que lo enseñe…", "Petición enviada")
	t.reveal_remote_item("corona_umbral")
	await _frames(1)
	check(w.row_nodes[TS.REMOTE][0]["name"].text == "Corona del umbral", "Al enseñarlo se ve el nombre")
	check(not w.reveal_button.visible, "Sin «???» se oculta el botón")
	# Doble confirmación
	r = w.press_confirm()
	check(r["ok"] and t.state == TS.State.CONFIRMED_LOCAL and w.confirm_button.text == "Quitar confirmación", "Confirmas: «Quitar confirmación»")
	w.press_confirm()
	check(t.state == TS.State.EDITING and w.confirm_button.text == "Confirmar", "Quitar tu confirmación")
	w.press_confirm()
	t.confirm(TS.REMOTE)
	await _frames(1)
	check(t.state == TS.State.LOCKED_BOTH, "LOCKED_BOTH")
	check(w.side_status[TS.LOCAL].text == "Confirmado ✓" and w.side_status[TS.REMOTE].text == "Confirmado ✓", "Ambos «Confirmado ✓»")
	check(w.confirm_button.text == "Cerrar trato ✓" and not w.confirm_button.disabled, "Botón «Cerrar trato ✓»")
	check(w.gold_plus.disabled and w.gold_minus.disabled, "Oro bloqueado")
	check(w.row_nodes[TS.LOCAL][0]["panel"].find_child("Remove", true, false) == null, "Sin botón de quitar con el trato bloqueado")
	var cr: Dictionary = w.press_confirm()
	check(cr["ok"] and t.state == TS.State.COMPLETED, "Cerrar trato -> COMPLETED")
	check(w.confirm_button.text == "Cerrar" and w.cancel_button.disabled, "Trato hecho: «Cerrar»")
	check(k.is_known("item_corona_umbral"), "La Corona entra en tu Códice")
	w.queue_free()
	await _frames(1)
	# Quitar un objeto propio desde la ventana con Sasha confirmada
	var k2 := _ks()
	var t2 := _ts(k2)
	var w2 = TradeScene.instantiate()
	w2.service = t2
	w2.knowledge = k2
	w2.drive_clock = false
	root.add_child(w2)
	await _frames(2)
	t2.confirm(TS.REMOTE)
	check(w2.remove_local_item(1), "Quitar los lingotes desde la ventana")
	check(not t2.is_confirmed(TS.REMOTE) and t2.in_cooldown(), "Quitar también borra las confirmaciones")
	check(w2.row_nodes[TS.LOCAL].size() == 2 and w2.side_value[TS.LOCAL].text == "1.050 oro", "Fila y valor actualizados")
	var closed := []
	w2.trade_closed.connect(func(res): closed.append(res))
	w2.cancel_trade()
	check(t2.state == TS.State.CANCELLED and closed.size() == 1 and not w2.visible, "Cancelar cancela y cierra")
	w2.queue_free()
	await _frames(1)
	for x in [k, t, k2, t2]:
		_free(x)
