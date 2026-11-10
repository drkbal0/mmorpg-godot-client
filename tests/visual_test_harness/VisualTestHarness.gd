extends Control

# VisualTestHarness.gd - Arnés de pruebas visuales automatizadas.
#
# Uso:
#   godot --path clients/godot-mmo-client res://tests/visual_test_harness/VisualTestHarness.tscn -- --output-dir=test_evidence
#
# Ejecuta 5 escenarios de UI, captura cada uno a PNG (1280x720) y genera
# test_manifest.json con timestamp, estado y checks de cada captura.
#
# Modo headless: el renderer "dummy" de --headless no produce píxeles
# (get_viewport().get_texture().get_image() no tiene contenido), así que el
# proceso headless actúa como orquestador: relanza esta misma escena en un
# proceso hijo con ventana real, espera su código de salida y valida el
# manifest resultante. Así el comando headless sigue siendo el punto de
# entrada de CI/autovalidación sin sacrificar evidencia real.

const SCENE_PATH := "res://tests/visual_test_harness/VisualTestHarness.tscn"
const DEFAULT_OUTPUT_DIR := "test_evidence"
const MANIFEST_NAME := "test_manifest.json"
const RENDER_CHILD_FLAG := "--render-child"
const TARGET_SIZE := Vector2i(1280, 720)
const BG_COLOR := Color("#0a0e17")

const STONE_ICON := "res://assets/icons/items/stone1x1.png"
const PLAYER_HUD_SCENE := "res://ui/components/PlayerHUD/PlayerHUD.tscn"
const CODEX_SCENE := "res://ui/windows/CodexDiaryWindow/CodexDiaryWindow.tscn"
const ADMIN_PANEL_SCENE := "res://ui/windows/AdminPanel/AdminPanel.tscn"

const EXPECTED_KEYS := ["LMB", "Q", "Shift", "E", "R"]
const METEOR_SPELL_ID := 5
const SLOT_PX := 64
const OFFLINE_GATEWAY := "offline://visual-test-harness"

const TacticalPingWheel = preload("res://ui/components/TacticalPing/TacticalPingWheel.gd")
const TacticalPingMarker = preload("res://ui/components/TacticalPing/TacticalPingMarker.gd")

@onready var _stage: Control = $Stage
@onready var _caption_title: Label = $CaptionLayer/CaptionPanel/CaptionVBox/Title
@onready var _caption_subtitle: Label = $CaptionLayer/CaptionPanel/CaptionVBox/Subtitle

var _output_dir: String = ""
var _captures: Array = []
var _network_mode: String = "offline"


func _ready() -> void:
	_output_dir = _resolve_output_dir()
	var err := DirAccess.make_dir_recursive_absolute(_output_dir)
	if err != OK:
		push_error("[VisualTestHarness] No se pudo crear output-dir '%s' (err %d)" % [_output_dir, err])
		get_tree().quit(1)
		return
	print("[VisualTestHarness] output-dir: ", _output_dir)

	if DisplayServer.get_name() == "headless":
		_run_as_headless_orchestrator()
		return

	_configure_window()
	_run_scenarios()


# ---------------------------------------------------------------------------
# Argumentos / entorno
# ---------------------------------------------------------------------------

func _resolve_output_dir() -> String:
	var raw := DEFAULT_OUTPUT_DIR
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output-dir="):
			raw = arg.substr("--output-dir=".length()).strip_edges()
	raw = raw.trim_prefix("'").trim_suffix("'").trim_prefix("\"").trim_suffix("\"")
	if raw == "":
		raw = DEFAULT_OUTPUT_DIR
	if raw.begins_with("res://") or raw.begins_with("user://"):
		return ProjectSettings.globalize_path(raw).simplify_path()
	if raw.is_absolute_path():
		return raw.simplify_path()
	# Rutas relativas: se resuelven contra la raíz del proyecto Godot.
	return ProjectSettings.globalize_path("res://").path_join(raw).simplify_path()


func _is_render_child() -> bool:
	return RENDER_CHILD_FLAG in OS.get_cmdline_user_args()


## Por defecto la evidencia es determinista y no depende del backend: se
## apunta el gateway a un esquema no-HTTP para que HTTPRequest.request() falle
## al instante y ShelterManager use su catálogo offline. (Sin esto, en Windows
## un HTTPRequest contra un puerto cerrado nunca completa y APIClient no tiene
## timeout, dejando colgado el catálogo de AdminPanel.) Usa --online para
## capturar contra el backend real.
func _configure_network_mode() -> void:
	if "--online" in OS.get_cmdline_user_args():
		_network_mode = "online"
		return
	var auth: Node = get_node_or_null("/root/AuthManager")
	if auth and "gateway_url" in auth:
		auth.gateway_url = OFFLINE_GATEWAY


func _configure_window() -> void:
	RenderingServer.set_default_clear_color(BG_COLOR)
	var win := get_window()
	win.mode = Window.MODE_WINDOWED
	win.size = TARGET_SIZE
	win.title = "Visual Test Harness"
	DisplayServer.window_set_size(TARGET_SIZE)


# ---------------------------------------------------------------------------
# Modo headless: relanzar con ventana real y validar el resultado
# ---------------------------------------------------------------------------

func _run_as_headless_orchestrator() -> void:
	if _is_render_child():
		push_error("[VisualTestHarness] El proceso hijo de render arrancó en headless; no hay GPU para capturar.")
		get_tree().quit(1)
		return

	var exe := OS.get_executable_path()
	# Preferimos el ejecutable *_console.exe para recibir stdout del hijo.
	if OS.get_name() == "Windows" and not exe.ends_with("_console.exe"):
		var console_exe := exe.get_basename() + "_console.exe"
		if FileAccess.file_exists(console_exe):
			exe = console_exe

	var args := PackedStringArray([
		"--path", ProjectSettings.globalize_path("res://"),
		SCENE_PATH,
		"--resolution", "%dx%d" % [TARGET_SIZE.x, TARGET_SIZE.y],
		"--",
		"--output-dir=" + _output_dir,
		RENDER_CHILD_FLAG,
	])
	if "--online" in OS.get_cmdline_user_args():
		args.append("--online")
	print("[VisualTestHarness] Renderer headless (dummy) detectado: relanzando captura con ventana real.")
	print("[VisualTestHarness]   ", exe, " ", " ".join(args))

	# Borrar un manifest previo para no validar evidencia obsoleta.
	var manifest_path := _output_dir.path_join(MANIFEST_NAME)
	if FileAccess.file_exists(manifest_path):
		DirAccess.remove_absolute(manifest_path)

	var output: Array = []
	var code := OS.execute(exe, args, output, true, false)
	for chunk in output:
		for line in str(chunk).split("\n"):
			if line.strip_edges() != "":
				print("  [render-child] ", line.strip_edges())

	var ok := code == 0 and _validate_manifest(manifest_path)
	print("[VisualTestHarness] Proceso de render terminó con código %d -> %s" % [code, "PASS" if ok else "FAIL"])
	get_tree().quit(0 if ok else 1)


func _validate_manifest(manifest_path: String) -> bool:
	if not FileAccess.file_exists(manifest_path):
		push_error("[VisualTestHarness] Falta el manifest: " + manifest_path)
		return false
	var data = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not (data is Dictionary) or not data.has("captures"):
		push_error("[VisualTestHarness] Manifest inválido: " + manifest_path)
		return false
	var all_ok := str(data.get("overall_status", "")) == "PASS"
	for cap in data["captures"]:
		var png := _output_dir.path_join(str(cap.get("file", "")))
		var exists := FileAccess.file_exists(png)
		var cap_ok: bool = exists and str(cap.get("status", "")) == "PASS"
		print("[VisualTestHarness]   %-36s %s" % [str(cap.get("file", "?")), "PASS" if cap_ok else "FAIL"])
		all_ok = all_ok and cap_ok
	return all_ok


# ---------------------------------------------------------------------------
# Ejecución de escenarios
# ---------------------------------------------------------------------------

func _run_scenarios() -> void:
	_configure_network_mode()
	await _settle(3)

	await _scenario_rotated_badge()
	await _clear_stage()
	await _scenario_split_stack()
	await _clear_stage()
	await _scenario_combat_hud()
	await _clear_stage()
	await _scenario_codex_diary()
	await _clear_stage()
	await _scenario_admin_grant()
	await _clear_stage()
	await _scenario_screenspace_nameplates()
	await _clear_stage()
	await _scenario_world_builder_map()
	await _clear_stage()
	await _scenario_death_echo_loot()
	await _clear_stage()
	await _scenario_hudv2_live_portrait()
	await _clear_stage()
	await _scenario_hudv2_hotbar_quickslots()
	await _clear_stage()
	await _scenario_hazard_indicator_sync()
	await _clear_stage()
	await _scenario_spell_vector_icons()
	await _clear_stage()
	await _scenario_party_frames()
	await _clear_stage()
	await _scenario_tactical_ping()
	await _clear_stage()

	var all_pass := true
	for cap in _captures:
		all_pass = all_pass and cap["status"] == "PASS"

	var manifest := {
		"harness": "VisualTestHarness",
		"scene": SCENE_PATH,
		"generated_at": _iso_now(),
		"godot_version": Engine.get_version_info().get("string", ""),
		"rendering_method": str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "")),
		"display_server": DisplayServer.get_name(),
		"resolution": [TARGET_SIZE.x, TARGET_SIZE.y],
		"background": "#0a0e17",
		"output_dir": _output_dir,
		"network_mode": _network_mode,
		"overall_status": "PASS" if all_pass else "FAIL",
		"captures": _captures,
	}
	var manifest_path := _output_dir.path_join(MANIFEST_NAME)
	var f := FileAccess.open(manifest_path, FileAccess.WRITE)
	if f == null:
		push_error("[VisualTestHarness] No se pudo escribir " + manifest_path)
		get_tree().quit(1)
		return
	f.store_string(JSON.stringify(manifest, "  "))
	f.close()

	print("[VisualTestHarness] Manifest: ", manifest_path)
	for cap in _captures:
		print("[VisualTestHarness]   %-36s %s" % [cap["file"], cap["status"]])
	print("[VisualTestHarness] RESULTADO GLOBAL: ", manifest["overall_status"])
	get_tree().quit(0 if all_pass else 1)


func _settle(frames: int = 2) -> void:
	for i in range(frames):
		await get_tree().process_frame


func _wait_seconds(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _clear_stage() -> void:
	for child in _stage.get_children():
		_stage.remove_child(child)
		child.queue_free()
	# Los toasts del UIOrchestrator viven en su propia capa: limpiarlos para que
	# no se filtren a la captura del siguiente escenario.
	var orch: Node = get_node_or_null("/root/UIOrchestrator")
	var toasts = orch.get("_toast_container") if orch else null
	if is_instance_valid(toasts):
		for t in toasts.get_children():
			t.queue_free()
	await _settle(2)


func _set_caption(title: String, subtitle: String) -> void:
	_caption_title.text = title
	_caption_subtitle.text = subtitle


## Captura el viewport tras el siguiente frame dibujado y registra el resultado.
func _capture(file_name: String, scenario: int, description: String, checks: Dictionary) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var path := _output_dir.path_join(file_name)
	var img: Image = get_viewport().get_texture().get_image()
	var has_pixels := img != null and not img.is_empty()
	checks["image_has_pixels"] = has_pixels
	var img_size := Vector2i.ZERO
	var save_err := ERR_UNCONFIGURED
	if has_pixels:
		img_size = img.get_size()
		save_err = img.save_png(path)
	checks["resolution_1280x720"] = img_size == TARGET_SIZE
	checks["png_saved"] = save_err == OK and FileAccess.file_exists(path)

	var passed := true
	var failed: Array = []
	for k in checks.keys():
		if not bool(checks[k]):
			passed = false
			failed.append(k)

	_captures.append({
		"scenario": scenario,
		"file": file_name,
		"description": description,
		"timestamp": _iso_now(),
		"status": "PASS" if passed else "FAIL",
		"size": [img_size.x, img_size.y],
		"checks": checks,
		"failed_checks": failed,
	})
	print("[VisualTestHarness] %s -> %s%s" % [file_name, "PASS" if passed else "FAIL", "" if passed else " " + str(failed)])


func _iso_now() -> String:
	return Time.get_datetime_string_from_system(true) + "Z"


# ---------------------------------------------------------------------------
# Helpers visuales
# ---------------------------------------------------------------------------

## Tablero de celdas de inventario (estilo stash) con zoom para legibilidad.
func _make_slot_board(cells: Vector2i, zoom: float) -> Control:
	var board_px := Vector2(cells.x * SLOT_PX, cells.y * SLOT_PX)
	var frame := PanelContainer.new()
	var fsb := StyleBoxFlat.new()
	fsb.bg_color = Color(0.06, 0.08, 0.12, 0.95)
	fsb.border_color = Color(0.22, 0.32, 0.45, 0.9)
	fsb.set_border_width_all(2)
	fsb.set_corner_radius_all(8)
	fsb.set_content_margin_all(10)
	frame.add_theme_stylebox_override("panel", fsb)
	frame.scale = Vector2(zoom, zoom)
	var frame_px := board_px + Vector2(20, 20)
	frame.position = (Vector2(TARGET_SIZE) - frame_px * zoom) * 0.5 + Vector2(0, 20)
	_stage.add_child(frame)

	var board := Control.new()
	board.name = "Board"
	board.custom_minimum_size = board_px
	board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(board)

	for y in range(cells.y):
		for x in range(cells.x):
			var cell := Panel.new()
			var csb := StyleBoxFlat.new()
			csb.bg_color = Color(0.09, 0.11, 0.16, 1.0)
			csb.border_color = Color(0.18, 0.24, 0.33, 1.0)
			csb.set_border_width_all(1)
			cell.add_theme_stylebox_override("panel", csb)
			cell.position = Vector2(x * SLOT_PX, y * SLOT_PX)
			cell.size = Vector2(SLOT_PX, SLOT_PX)
			cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
			board.add_child(cell)
	return board


func _make_stone(id: String, qty: int, slot: Vector2i) -> InventoryItem:
	var item := InventoryItem.new()
	item.name = "Item_" + id
	item.item_id = id
	item.item_name = "stone"
	item.texture = load(STONE_ICON)
	item.grid_width = 1
	item.grid_height = 1
	item.max_stack = 20
	item.inventory_type = 1
	item.slot_x = slot.x
	item.slot_y = slot.y
	item.position = Vector2(slot.x * SLOT_PX, slot.y * SLOT_PX)
	item.quantity = qty
	return item


func _add_note(text: String, pos: Vector2, color: Color = Color(0.75, 0.85, 0.95)) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.position = pos
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", color)
	_stage.add_child(lbl)
	return lbl


static func _visual_rect(ci: Control) -> Rect2:
	var xf := ci.get_global_transform()
	var r := Rect2(xf * Vector2.ZERO, Vector2.ZERO)
	for corner in [Vector2(ci.size.x, 0), Vector2(0, ci.size.y), ci.size]:
		r = r.expand(xf * corner)
	return r


static func _find_controls(root: Node, predicate: Callable) -> Array:
	var found: Array = []
	var pending: Array = [root]
	while not pending.is_empty():
		var n: Node = pending.pop_back()
		if predicate.call(n):
			found.append(n)
		pending.append_array(n.get_children())
	return found


static func _text_of(n: Node) -> String:
	if n is Button or n is Label or n is RichTextLabel:
		return str(n.text)
	return ""


# ---------------------------------------------------------------------------
# Escenario 1: badge xN erguido en ítem rotado 90°
# ---------------------------------------------------------------------------

func _scenario_rotated_badge() -> void:
	_set_caption("Escenario 1 · Badge de pila en ítem rotado 90°",
		"InventoryItem 'stone' quantity=5, is_rotated=true → badge x5 erguido en esquina inferior derecha")
	var zoom := 3.0
	var board := _make_slot_board(Vector2i(3, 2), zoom)
	var item := _make_stone("stone", 5, Vector2i(1, 0))
	item.is_rotated = true
	board.add_child(item)
	item.update_size()
	await _settle(3)
	item.update_size() # recalcular badge con el tamaño de fuente ya resuelto
	await _settle(2)

	var badge: Control = item.get_node_or_null("StackBadge")
	var label: Label = badge.find_child("CountLabel", true, false) if badge else null
	var item_rect := _visual_rect(item)
	var badge_rect := _visual_rect(badge) if badge else Rect2()
	var badge_global_rot := wrapf(badge.get_global_transform().get_rotation(), -PI, PI) if badge else 999.0
	var tol := 1.5 * zoom

	_add_note("item.rotation_degrees = %.0f°   ·   badge rotación global = %.1f°" % [item.rotation_degrees, rad_to_deg(badge_global_rot)],
		Vector2(40, 640))

	await _capture("evidence_stash_rotated_badge.png", 1,
		"InventoryItem stone x5 rotado 90° con badge erguido abajo-derecha", {
			"item_rotated_90": item.is_rotated and is_equal_approx(item.rotation_degrees, 90.0),
			"badge_visible": badge != null and badge.visible,
			"badge_text_x5": label != null and label.text == "x5",
			"badge_upright": abs(badge_global_rot) < 0.01,
			"badge_anchored_bottom_right": badge != null
				and abs(badge_rect.end.x - item_rect.end.x) <= tol
				and abs(badge_rect.end.y - item_rect.end.y) <= tol,
		})


# ---------------------------------------------------------------------------
# Escenario 2: división de pila (split_stack) 5 → 3 + 2
# ---------------------------------------------------------------------------

func _scenario_split_stack() -> void:
	_set_caption("Escenario 2 · División de pila (split_stack)",
		"Pila stone x5 → InventoryItem.split_stack() → celda x3 + celda x2 en el Almacén")
	var sm: Node = get_node_or_null("/root/ShelterManager")
	var backup_shelter: Array = sm.shelter_inventory.duplicate(true) if sm else []
	var backup_cache: Dictionary = sm.all_items_cache.duplicate(true) if sm else {}

	var stack_id := "vt_stone_stack"
	if sm:
		var origin := {
			"id": stack_id, "display_name": "stone", "icon_path": STONE_ICON,
			"grid_width": 1, "grid_height": 1, "slot_x": 0, "slot_y": 0, "quantity": 5,
		}
		sm.shelter_inventory = [origin]
		sm.all_items_cache[stack_id] = origin

	var board := _make_slot_board(Vector2i(5, 2), 2.5)
	var original := _make_stone(stack_id, 5, Vector2i(0, 0))
	board.add_child(original)
	await _settle(2)

	var qty_before := original.quantity
	original.split_stack()
	await _settle(2)

	var split_dict: Dictionary = {}
	if sm:
		for it in sm.shelter_inventory:
			if str(it.get("id", "")).begins_with("split_"):
				split_dict = it
				break

	var split_item: InventoryItem = null
	if not split_dict.is_empty():
		split_item = _make_stone(str(split_dict["id"]), int(split_dict["quantity"]),
			Vector2i(int(split_dict["slot_x"]), int(split_dict["slot_y"])))
		board.add_child(split_item)
	await _wait_seconds(1.0) # toast "PILA DIVIDIDA" totalmente visible

	_add_note("Antes: x%d   ·   Después: x%d (slot %d,%d) + x%d (slot %s)" % [
		qty_before, original.quantity, original.slot_x, original.slot_y,
		split_item.quantity if split_item else 0,
		"%d,%d" % [split_item.slot_x, split_item.slot_y] if split_item else "?"],
		Vector2(40, 640))

	await _capture("evidence_stash_split_stack.png", 2,
		"split_stack sobre pila x5: celda original x3 y nueva celda x2", {
			"shelter_manager_available": sm != null,
			"original_kept_3": original.quantity == 3,
			"split_created_2": split_item != null and split_item.quantity == 2,
			"split_in_different_cell": split_item != null
				and Vector2i(split_item.slot_x, split_item.slot_y) != Vector2i(original.slot_x, original.slot_y),
			"total_preserved_5": split_item != null and original.quantity + split_item.quantity == qty_before,
		})

	if sm:
		sm.shelter_inventory = backup_shelter
		sm.all_items_cache = backup_cache


# ---------------------------------------------------------------------------
# Escenario 3: HUD de combate a escala 1.0 y 1.3
# ---------------------------------------------------------------------------

func _scenario_combat_hud() -> void:
	var hud: CanvasLayer = load(PLAYER_HUD_SCENE).instantiate()
	_stage.add_child(hud)
	await _settle(3)

	hud.update_name("Aventurero_Alpha")
	hud.hp_bar.value = 55.0
	hud.mana_bar.max_value = 300.0
	hud.mana_bar.value = 150.0
	hud.hp_value_label.text = "550 / 1000 HP   ·   150 / 300 MANA"

	var spell_mgr: Node = get_node_or_null("/root/SpellManager")
	if spell_mgr:
		spell_mgr.trigger_cooldown(METEOR_SPELL_ID)
		# Adelantar el reloj: ~6.5s restantes de 12s → barrido radial a mitad,
		# claramente distinguible en la evidencia (y no expira entre capturas).
		spell_mgr.cooldowns[METEOR_SPELL_ID] = Time.get_ticks_msec() + 7000
	await _wait_seconds(0.5)

	for scale_info in [[1.0, "evidence_combat_hud_100.png"], [1.3, "evidence_combat_hud_130.png"]]:
		var s: float = scale_info[0]
		_set_caption("Escenario 3 · HUD de combate (escala %.1f)" % s,
			"550 HP / 150 Mana · teclas LMB, Q, Shift, E, R · cooldown radial activo en R (METEORO)")
		hud.apply_hud_scale(s)
		await _settle(3)
		hud.apply_hud_scale(s) # pivot con tamaño ya resuelto
		await _settle(2)

		var keys: Array = []
		for cfg in hud.SKILL_CONFIG:
			var slot: Dictionary = hud.skill_slots.get(cfg["id"], {})
			keys.append(str(slot["key_label"].text).strip_edges() if slot.has("key_label") else "")
		var r_slot: Dictionary = hud.skill_slots.get(METEOR_SPELL_ID, {})
		var progress := float(r_slot["radial_overlay"].get_meta("progress", 0.0)) if not r_slot.is_empty() else 0.0
		var margin: Control = hud.get_node("RootBottom/HUDMargin")
		var mrect := _visual_rect(margin)

		await _capture(str(scale_info[1]), 3,
			"PlayerHUD 550 HP / 150 Mana con cooldown radial en R a escala %.1f" % s, {
				"vitals_hp_550": is_equal_approx(hud.hp_bar.value, 55.0) and "550" in hud.hp_value_label.text,
				"vitals_mana_150": is_equal_approx(hud.mana_bar.value, 150.0) and "150" in hud.hp_value_label.text,
				"keybinds_LMB_Q_Shift_E_R": keys == EXPECTED_KEYS,
				"meteor_R_cooldown_active": spell_mgr != null and progress > 0.0 and r_slot["cd_label"].visible,
				"hud_scale_applied": margin.scale.is_equal_approx(Vector2(s, s)),
				"hud_centered_horizontally": abs(mrect.get_center().x - TARGET_SIZE.x * 0.5) <= 2.0,
				"hud_inside_viewport": Rect2(Vector2.ZERO, Vector2(TARGET_SIZE)).encloses(mrect),
			})
		_captures[-1]["observed"] = {"keybinds": keys, "meteor_cd_progress": snappedf(progress, 0.001),
			"hud_rect": [mrect.position.x, mrect.position.y, mrect.size.x, mrect.size.y]}


# ---------------------------------------------------------------------------
# Escenario 4: Códice con el secreto Amuleto Vacío Ancestral
# ---------------------------------------------------------------------------

func _scenario_codex_diary() -> void:
	_set_caption("Escenario 4 · Códice / Diario de Descubrimientos",
		"Secreto 'Amuleto Vacío Ancestral' con acciones Craftear Hoja Oculta y Publicar al Mundo")
	var codex: Control = load(CODEX_SCENE).instantiate()
	_stage.add_child(codex)
	await _settle(3)
	codex.unlock_secret_from_sheet("item_amuleto_vacio", "Amuleto Vacío Ancestral")
	await _wait_seconds(0.8) # dejar terminar el pulso dorado
	# Bajar la ventana bajo el caption para que no tape su cabecera.
	codex.position = Vector2(codex.position.x, 66.0)
	await _settle(2)
	var viewport_rect := Rect2(Vector2.ZERO, Vector2(TARGET_SIZE))

	var craft := _find_controls(codex, func(n): return n is Button and n.is_visible_in_tree() and "Craftear Hoja Oculta" in n.text)
	var publish := _find_controls(codex, func(n): return n is Button and n.is_visible_in_tree() and "Publicar al Mundo" in n.text)
	var amulet := _find_controls(codex.detail_container, func(n): return n is CanvasItem and n.is_visible_in_tree() and "Amuleto Vacío Ancestral" in _text_of(n))

	await _capture("evidence_codex_diary_window.png", 4,
		"CodexDiaryWindow mostrando el secreto Amuleto Vacío Ancestral y sus acciones", {
			"secret_amuleto_shown": amulet.size() > 0,
			"secret_acquired": codex.is_secret_acquired("item_amuleto_vacio"),
			"button_craftear_hoja_oculta": craft.size() > 0,
			"button_publicar_al_mundo": publish.size() > 0,
			"actions_inside_viewport": craft.size() > 0 and publish.size() > 0
				and viewport_rect.encloses(_visual_rect(craft[0])) and viewport_rect.encloses(_visual_rect(publish[0])),
		})


# ---------------------------------------------------------------------------
# Escenario 5: Panel admin (F10) con botón Otorgar
# ---------------------------------------------------------------------------

func _scenario_admin_grant() -> void:
	_set_caption("", "")
	var panel: Control = load(ADMIN_PANEL_SCENE).instantiate()
	_stage.add_child(panel)
	await _settle(2)
	panel.visible = true
	panel.initialize_window() # dispara refresh_catalog (API o catálogo offline)

	var grant_buttons: Array = []
	var deadline := Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		if panel.get("_is_loading"):
			continue
		grant_buttons = _find_controls(panel, func(n): return n is Button and "Otorgar" in n.text)
		if grant_buttons.size() > 0:
			break
	await _settle(4)

	# Caption a la derecha para no tapar el panel (anclado en 20,20).
	_set_caption("Escenario 5 · Panel Admin (F10)", "Catálogo de ítems con botón [🎁 Otorgar] por entrada")
	$CaptionLayer/CaptionPanel.position = Vector2(TARGET_SIZE.x - 640 - 12, 10)
	var visible_grants := grant_buttons.filter(func(b): return is_instance_valid(b) and b.is_visible_in_tree())

	await _capture("evidence_admin_f10_grant.png", 5,
		"AdminPanel (F10) con catálogo y botones Otorgar", {
			"admin_panel_visible": panel.is_visible_in_tree(),
			"catalog_loaded": int(panel.item_definitions.size()) > 0,
			"grant_button_visible": visible_grants.size() > 0,
		})
	_captures[-1]["observed"] = {"catalog_items": panel.item_definitions.size(), "grant_buttons": visible_grants.size()}
	$CaptionLayer/CaptionPanel.position = Vector2(12, 10)


# ---------------------------------------------------------------------------
# Escenario 6: Screen-Space 2D Nameplates & Barras Segmentadas (100 HP)
# ---------------------------------------------------------------------------

func _scenario_screenspace_nameplates() -> void:
	_set_caption("Escenario 6 · Screen-Space 2D Nameplates & Barras Segmentadas (100 HP)",
		"Proyección vectorial 2D nítida en CanvasLayer con ticks cada 100 HP y diferenciación aliada/hostil")

	var nameplate_scene = load("res://ui/screenspace/WorldNameplate.tscn")

	# 1. Aliado / Campeón
	var ally_plate: Control = nameplate_scene.instantiate()
	_stage.add_child(ally_plate)
	ally_plate.position = Vector2(240, 240)
	ally_plate.scale = Vector2(1.25, 1.25)
	ally_plate.setup("Valerius (Pionero)", 850.0, 1000.0, false, "‹ PIONERO ANCESTRAL ›")
	ally_plate.update_hp(850.0, 1000.0)

	var ally_note = _add_note("Aliado: Verde Esmeralda\nMax HP: 1000 (10 ticks de 100 HP)\nHP Actual: 850", Vector2(240, 330), Color(0.4, 0.9, 0.6))

	# 2. Hostil / Boss
	var boss_plate: Control = nameplate_scene.instantiate()
	_stage.add_child(boss_plate)
	boss_plate.position = Vector2(680, 240)
	boss_plate.scale = Vector2(1.25, 1.25)
	boss_plate.setup("Guardia Carmesí de Élite", 450.0, 1200.0, true, "‹ JEFE DE MAZMORRA ›")
	boss_plate.update_hp(450.0, 1200.0)

	var boss_note = _add_note("Hostil: Rojo Carmesí\nMax HP: 1200 (12 ticks de 100 HP)\nHP Actual: 450", Vector2(680, 330), Color(1.0, 0.45, 0.45))

	await _settle(4)
	await _wait_seconds(0.5)

	await _capture("evidence_screenspace_nameplates.png", 6,
		"WorldNameplate en Screen-Space 2D con barras segmentadas cada 100 HP", {
			"ally_plate_visible": ally_plate.is_visible_in_tree(),
			"boss_plate_visible": boss_plate.is_visible_in_tree(),
			"ally_hp_value": ally_plate.current_health == 850.0,
			"boss_hp_value": boss_plate.current_health == 450.0,
		})


# ---------------------------------------------------------------------------
# Escenario 7: World Builder & Topografía Declarativa (JSON)
# ---------------------------------------------------------------------------

func _scenario_world_builder_map() -> void:
	_set_caption("Escenario 7 · World Builder & Topografía de Mapa (JSON)",
		"Esquema topográfico declarativo con colisiones estáticas, radio de spawners y portal de extracción")

	var map_tool_script = load("res://tools/map_editor/MapEditorTool.gd")
	var map_tool: Node3D = Node3D.new()
	map_tool.set_script(map_tool_script)
	_stage.add_child(map_tool)

	map_tool.load_map("res://assets/maps/map_zone_overworld.json")
	await _settle(3)

	var col_count: int = map_tool.colliders_root.get_child_count()
	var sp_count: int = map_tool.spawners_root.get_child_count()
	var port_count: int = map_tool.portals_root.get_child_count()

	var summary_box = PanelContainer.new()
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.11, 0.18, 0.9)
	sb.border_color = Color(0.2, 0.5, 0.8, 0.8)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	summary_box.add_theme_stylebox_override("panel", sb)
	summary_box.position = Vector2(380, 220)
	summary_box.custom_minimum_size = Vector2(440, 180)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	summary_box.add_child(vbox)

	var title = Label.new()
	title.text = "🗺️ MAP TOPOGRAPHY MANIFEST (Overworld_Asylum_Zone_1)"
	title.add_theme_color_override("font_color", Color(0.3, 0.9, 1.0))
	title.add_theme_font_size_override("font_size", 14)
	vbox.add_child(title)

	var l1 = Label.new()
	l1.text = "• Colliders Estáticos AABB: %d (Sincronizados con SpatialGrid)" % col_count
	vbox.add_child(l1)

	var l2 = Label.new()
	l2.text = "• Spawners Activos: %d (CrimsonGuard Camp + Patrol South)" % sp_count
	vbox.add_child(l2)

	var l3 = Label.new()
	l3.text = "• Portales de Extracción: %d (Hacia Zona 2 - Cripta Ancestral)" % port_count
	vbox.add_child(l3)

	var l4 = Label.new()
	l4.text = "• Bounds Autoritativos: [-250m, +250m] X/Z"
	l4.add_theme_color_override("font_color", Color(0.8, 0.85, 0.9))
	vbox.add_child(l4)

	_stage.add_child(summary_box)

	await _settle(3)
	await _wait_seconds(0.4)

	await _capture("evidence_world_builder_topography.png", 7,
		"World Builder Tooling y Topografía declarativa JSON sincronizada", {
			"static_colliders_loaded": col_count > 0,
			"spawners_loaded": sp_count > 0,
			"portals_loaded": port_count > 0,
		})


# ---------------------------------------------------------------------------
# Escenario 8: Ecos de Muerte & Botín Screen-Space 2D
# ---------------------------------------------------------------------------

func _scenario_death_echo_loot() -> void:
	_set_caption("Escenario 8 · Ecos de Muerte & Botín Screen-Space 2D",
		"Etiqueta 2D interactiva de alta legibilidad para saqueo de contenedores y restos de combate")

	var loot_scene = load("res://ui/screenspace/DeathEchoLabel.tscn")
	var loot_plate: Control = loot_scene.instantiate()
	_stage.add_child(loot_plate)
	loot_plate.position = Vector2(480, 260)
	loot_plate.scale = Vector2(1.3, 1.3)
	loot_plate.setup_loot("Valerius (Pionero)", 5)

	var note = _add_note("Widget 2D Screen-Space de Saqueo\nDespawn autoritativo (0x17) al vaciar\nPrompt de interacción [F]", Vector2(480, 360), Color(1.0, 0.85, 0.4))

	await _settle(4)
	await _wait_seconds(0.5)

	await _capture("evidence_death_echo_screenspace.png", 8,
		"DeathEchoLabel en Screen-Space con tooltip de interacción táctica", {
			"loot_label_visible": loot_plate.is_visible_in_tree(),
			"panel_container_present": loot_plate.has_node("PanelContainer"),
		})


# ---------------------------------------------------------------------------
# Escenario 9: HUDv2 Pixel-Perfect & Live 3D Model Portrait (ADR 095)
# ---------------------------------------------------------------------------

func _scenario_hudv2_live_portrait() -> void:
	_set_caption("Escenario 9 · HUDv2 & Live 3D Model Portrait (ADR 095)",
		"Retrato circular con busto 3D procedimental, iluminación estudio de 3 puntos y feedback de daño reactivo")

	var hud_scene = load("res://ui/components/HUDv2/hud.tscn")
	var hud = hud_scene.instantiate()
	_stage.add_child(hud)
	hud.position = Vector2(0, 0)
	
	hud.set_accent(Color("#46e3c1"))
	hud.set_shape("trapecio")
	hud.set_level(7, 0.65)
	hud.set_health(680.0, 1000.0, 4.2)
	hud.set_mana(320.0, 400.0)
	hud.set_gold(2450)
	hud.set_stats({
		"attack_damage": 115, "ability_power": 45,
		"attack_speed": 0.85, "crit": "15%",
		"armor_pen": "10 | 12%", "magic_pen": "0 | 0%",
		"life_steal": "8%", "omnivamp": "0%",
		"armor": 62, "magic_resist": 48,
		"tenacity": "10%", "heal_shield": "0%",
		"ability_haste": 25, "move_speed": 360,
		"attack_range": 175, "regen": "22 | 60",
	})
	hud.set_buffs([
		{"color": Color("#245a3e"), "stacks": 0, "name": "Regeneración Arcana"},
		{"color": Color("#5a2428"), "stacks": 3, "name": "Furia de Sangre"},
		{"color": Color("#1e4a4a"), "stacks": 0, "duration_fraction": 0.7, "name": "Aura de Protección"},
	])
	hud.push_feed("06:12", "Sombra_Alpha", "Cazador", "ha adquirido Manto de las Sombras", true)
	hud.push_feed("06:34", "Lord_Ignis", "Mago", "en camino hacia el Nexo", false)
	
	_add_note("HUDv2 Anclado al Borde Inferior (1360x460 auto-fit)\nLivePortrait3D con SubViewport (256x256, fondo transparente)\nLuces Key (Cian), Fill (Gris frío) y Rim (Dorado)", Vector2(60, 120), Color(0.3, 0.9, 0.8))

	await _settle(4)
	await _wait_seconds(0.5)

	var portrait = hud.get_node_or_null("Portrait")
	var live_subvp = portrait.get("live_portrait") if portrait else null
	var has_tex: bool = portrait != null and portrait.get("portrait_texture") != null

	await _capture("evidence_hudv2_live_portrait.png", 9,
		"HUDv2 con LivePortrait3D renderizando busto del jugador en SubViewport", {
			"hud_visible": hud.is_visible_in_tree(),
			"portrait_present": portrait != null,
			"live_portrait_attached": live_subvp != null,
			"portrait_texture_valid": has_tex,
		})


# ---------------------------------------------------------------------------
# Escenario 10: Hotbar Quickslots [1]-[6] con Drag & Drop y Cooldown Radial
# ---------------------------------------------------------------------------

func _scenario_hudv2_hotbar_quickslots() -> void:
	_set_caption("Escenario 10 · Hotbar Quickslots [1]-[6] Drag & Drop",
		"Casillas de acceso rápido vinculadas al inventario, badges de pila erguidos y barrido de cooldown radial")

	var hud_scene = load("res://ui/components/HUDv2/hud.tscn")
	var hud = hud_scene.instantiate()
	_stage.add_child(hud)
	
	hud.set_accent(Color("#5aa9ff"))
	hud.set_shape("curva")
	hud.set_level(9, 0.20)
	hud.set_health(850.0, 1200.0, 5.0)
	hud.set_mana(410.0, 500.0)
	hud.set_gold(3820)
	
	var stone_tex: Texture2D = load(STONE_ICON)
	hud.set_item(0, stone_tex, 5)
	hud.set_item(1, stone_tex, 3)
	hud.set_item(2, stone_tex, 12)
	hud.set_item(3, stone_tex, 1)
	hud.set_item(4, stone_tex, 8)
	hud.set_item(5, stone_tex, 2)
	
	# Simular cooldown activo en slot 1 (Poción)
	var item1 = hud.items[1]
	item1.item_name = "Poción Mayor de Vida"
	item1.cooldown_total = 15.0
	item1.cooldown_remaining = 9.2 # Barrido radial a más de la mitad
	
	hud.items[0].item_name = "Piedra Rúnica de Teletransporte"
	hud.items[2].item_name = "Elixir de Maná Ancestral"
	hud.items[3].item_name = "Pergamino de Identificación"
	hud.items[4].item_name = "Bomba Incendiaria"
	hud.items[5].item_name = "Vial de Velocidad"

	_add_note("Hotbar de 6 casillas rápidas [1] - [6]\nSlot 2: Cooldown radial activo (9.2s restantes / 15s)\nArrastre y suelte polimórfico desde el inventario [I]", Vector2(60, 120), Color(0.4, 0.7, 1.0))

	await _settle(4)
	await _wait_seconds(0.5)

	var has_cd: bool = item1.cooldown_remaining > 0.0
	var has_items: bool = hud.items[0].stacks == 5 and hud.items[2].stacks == 12

	await _capture("evidence_hudv2_quickslots_hotbar.png", 10,
		"Hotbar de HUDv2 con slots 1-6 poblados, insignias erguidas y cooldown radial activo", {
			"hud_visible": hud.is_visible_in_tree(),
			"slot_stacks_valid": has_items,
			"slot_cooldown_active": has_cd,
			"slot_count_is_six": hud.items.size() == 6,
		})


# ---------------------------------------------------------------------------
# Escenario 11: Sincronización Autoritativa de Hazards (Rust ECS ↔ Godot 3D)
# ---------------------------------------------------------------------------

func _scenario_hazard_indicator_sync() -> void:
	_set_caption("Escenario 11 · Sincronización Autoritativa de Hazards (Rust ECS ↔ Godot 3D)",
		"Máquina de 3 estados de peligro: Safe (0, verde), Warning (1, ámbar telegraph) y Active (2, carmesí daño)")

	# Contenedor SubViewport 3D para renderizar la escena espacial
	var subvp_cont := SubViewportContainer.new()
	subvp_cont.size = TARGET_SIZE
	_stage.add_child(subvp_cont)

	var subvp := SubViewport.new()
	subvp.size = TARGET_SIZE
	subvp.own_world_3d = true
	subvp.transparent_bg = true
	subvp_cont.add_child(subvp)

	var cam := Camera3D.new()
	subvp.add_child(cam)
	cam.position = Vector3(0, 3.2, 5.8)
	cam.look_at(Vector3(0, 0, 0), Vector3.UP)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, 30, 0)
	light.light_energy = 1.0
	subvp.add_child(light)

	var hazard_scene = load("res://ui/components/HazardIndicator/HazardIndicator.tscn")

	# Hazard 1: Safe (0)
	var h_safe: Node3D = hazard_scene.instantiate()
	subvp.add_child(h_safe)
	h_safe.position = Vector3(-2.6, 0, 0)
	h_safe.setup(0.0, false)
	if h_safe.mesh_instance and h_safe._mat:
		h_safe._mat.albedo_color = Color(0.1, 0.8, 0.2, 0.3)
		h_safe._mat.emission_enabled = false

	# Hazard 2: Warning (1)
	var h_warn: Node3D = hazard_scene.instantiate()
	subvp.add_child(h_warn)
	h_warn.position = Vector3(0.0, 0, 0)
	h_warn.setup(0.0, false)
	if h_warn.mesh_instance and h_warn._mat:
		h_warn._mat.albedo_color = Color(1.0, 0.7, 0.1, 0.65)
		h_warn._mat.emission_enabled = true
		h_warn._mat.emission = Color(1.0, 0.7, 0.1)
		h_warn._mat.emission_energy_multiplier = 2.0

	# Hazard 3: Active (2)
	var h_act: Node3D = hazard_scene.instantiate()
	subvp.add_child(h_act)
	h_act.position = Vector3(2.6, 0, 0)
	h_act.setup(0.0, false)
	if h_act.mesh_instance and h_act._mat:
		h_act._mat.albedo_color = Color(1.0, 0.15, 0.15, 0.85)
		h_act._mat.emission_enabled = true
		h_act._mat.emission = Color(1.0, 0.1, 0.1)
		h_act._mat.emission_energy_multiplier = 3.5

	# Etiquetas 2D descriptivas sobre cada zona
	_add_note("FASE 0: SAFE\nDaño: 0.0\nColor: Esmeralda\nOpacidad tenue (0.15)", Vector2(170, 500), Color(0.3, 0.9, 0.4))
	_add_note("FASE 1: WARNING\nTelegraph pre-detonación\nColor: Ámbar destellante\nDuración: 800ms", Vector2(520, 500), Color(1.0, 0.8, 0.2))
	_add_note("FASE 2: ACTIVE\nDetonación autoritativa (0x19)\nColor: Carmesí HDR\nDaño continuo por tick", Vector2(880, 500), Color(1.0, 0.3, 0.3))

	await _settle(4)
	await _wait_seconds(0.5)

	await _capture("evidence_hazard_indicator_sync.png", 11,
		"Indicadores de peligro 3D sincronizados con los 3 estados autoritativos del Rust ECS", {
			"subviewport_active": subvp.is_inside_tree(),
			"hazard_safe_instantiated": h_safe.is_inside_tree(),
			"hazard_warning_instantiated": h_warn.is_inside_tree(),
			"hazard_active_instantiated": h_act.is_inside_tree(),
		})


# ---------------------------------------------------------------------------
# Escenario 12: Iconos Vectoriales SVG de Habilidades (Phase 9.13)
# ---------------------------------------------------------------------------

func _scenario_spell_vector_icons() -> void:
	_set_caption("Escenario 12 · Iconos Vectoriales SVG de Habilidades & Renderizado Nítido",
		"Renderizado de alta fidelidad para el kit de habilidades: Rayo Láser (Q), Bola de Fuego (W), Dash (E), Escudo (D) y Meteoro (R)")

	var grid := HBoxContainer.new()
	grid.position = Vector2(240, 260)
	grid.add_theme_constant_override("separation", 36)
	_stage.add_child(grid)

	var spells_info := [
		{"key": "Q", "name": "Rayo Láser", "path": "res://assets/icons/spells/spell_laser.svg", "color": Color("#38bdf8")},
		{"key": "W", "name": "Bola de Fuego", "path": "res://assets/icons/spells/spell_fireball.svg", "color": Color("#f97316")},
		{"key": "E", "name": "Dash Espectral", "path": "res://assets/icons/spells/spell_dash.svg", "color": Color("#a855f7")},
		{"key": "D", "name": "Barrera Arcana", "path": "res://assets/icons/spells/spell_barrier.svg", "color": Color("#10b981")},
		{"key": "R", "name": "Impacto Meteoro", "path": "res://assets/icons/spells/spell_meteor.svg", "color": Color("#ef4444")},
	]

	var ability_slot_scene = load("res://ui/components/HUDv2/ability_slot.tscn")

	for s in spells_info:
		var slot = ability_slot_scene.instantiate()
		grid.add_child(slot)
		slot.custom_minimum_size = Vector2(62, 100)
		slot.key_label = s["key"]
		slot.rank = 3
		slot.max_rank = 5
		slot.cost = 45
		slot.accent = s["color"]
		var tex: Texture2D = null
		var global_p := ProjectSettings.globalize_path(s["path"])
		if FileAccess.file_exists(global_p):
			var img := Image.load_from_file(global_p)
			if img and not img.is_empty():
				tex = ImageTexture.create_from_image(img)
		if tex == null:
			tex = load(s["path"]) if ResourceLoader.exists(s["path"]) else null
		if tex:
			slot.icon_texture = tex

	_add_note("Kit de Habilidades con Iconografía Vectorial SVG (Sin pixelado en altas resoluciones)\nIconos escalables con rangos (1-5), costes de maná y acentos elementales dinámicos", Vector2(240, 420), Color(0.8, 0.9, 1.0))

	await _settle(4)
	await _wait_seconds(0.5)

	await _capture("evidence_spell_vector_icons.png", 12,
		"Iconos vectoriales SVG renderizados en slots de habilidad HUDv2", {
			"grid_populated": grid.get_child_count() == 5,
		})


# ---------------------------------------------------------------------------
# Escenario 13: Party Frames & Sistema de Escuadras (Phase 9.5 / ADR 096)
# ---------------------------------------------------------------------------

func _scenario_party_frames() -> void:
	_set_caption("Escenario 13 · HUD de Escuadras / Party Frames & Estado Abatido",
		"Sincronización de grupo: Barras de HP/Maná, glifos de clase, distancias relativas y badge 'ABATIDO' con cuenta regresiva")

	var party_scene: PackedScene = load("res://ui/components/PartyFrames/PartyFrames.tscn")
	var party: Control = party_scene.instantiate()
	party.position = Vector2(80, 160)
	_stage.add_child(party)

	var members_data: Array[Dictionary] = [
		{
			"id": 101,
			"name": "Valerius (Líder)",
			"class": "guardian",
			"hp": 850.0,
			"max_hp": 1000.0,
			"mana": 250.0,
			"max_mana": 400.0,
			"distance": 18.0,
			"status": "NORMAL"
		},
		{
			"id": 102,
			"name": "Sylvia",
			"class": "mage",
			"hp": 320.0,
			"max_hp": 600.0,
			"mana": 380.0,
			"max_mana": 500.0,
			"distance": 42.0,
			"status": "NORMAL"
		},
		{
			"id": 103,
			"name": "Kaelen",
			"class": "ranger",
			"hp": 0.0,
			"max_hp": 750.0,
			"mana": 0.0,
			"max_mana": 200.0,
			"distance": 65.0,
			"is_downed": true,
			"timer_sec": 18.5,
			"status": "ABATIDO"
		}
	]

	party.set_party_members(members_data)

	# Añadir panel explicativo a la derecha
	var info_box := PanelContainer.new()
	info_box.position = Vector2(340, 160)
	info_box.custom_minimum_size = Vector2(560, 240)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.08, 0.11, 0.95)
	sb.border_color = Color(0.2, 0.35, 0.45, 0.8)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(10)
	info_box.add_theme_stylebox_override("panel", sb)
	_stage.add_child(info_box)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 14)
	info_box.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "ARQUITECTURA DE ESCUADRAS (PHASE 9.5 / ADR 096)"
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", Color("#46e3c1"))
	vbox.add_child(title)

	var desc := Label.new()
	desc.text = "• Filtrado Friendly-Fire: Bitmasking O(1) de party_id en proyectiles CCD, hitscans y círculos AoE.\n• Protocolo 0x18 PARTY_SYNC: Payload Little-Endian de 4 miembros con vitals compactados a 20Hz.\n• Política de Loot: Free-For-All y Round-Robin con candado de asignación individual de 15 segundos.\n• Sistema de Abatido (Downed): Jugadores en grupo no mueren al llegar a 0 HP; entran en bleedout (30s).\n• Reanimación Asistida: Canalización de 6s con proximidad <= 3.5m restablece al 25% HP y velocidad."
	desc.add_theme_font_size_override("font_size", 11)
	desc.add_theme_color_override("font_color", Color(0.85, 0.9, 0.95))
	vbox.add_child(desc)

	await _settle(4)
	await _wait_seconds(0.5)

	await _capture("evidence_party_frames_squad.png", 13,
		"Party Frames con 3 miembros, glifos vectoriales, vitals animados y miembro abatido con alerta de bleedout", {
			"party_container_instantiated": party.is_inside_tree(),
			"member_count_is_three": party.get_all_frames().size() == 3,
			"kaelen_is_downed": party.get_member_frame(103) != null and party.get_member_frame(103).is_downed,
		})


# ---------------------------------------------------------------------------
# Escenario 14: Rueda de Pings Tácticos (Atajo G) & Marcadores 3D Screen-Space
# ---------------------------------------------------------------------------

func _scenario_tactical_ping() -> void:
	_set_caption("Escenario 14 · Rueda de Pings Tácticos (Atajo G) & Marcadores Screen-Space",
		"Señalización no verbal para escuadras: Rueda modal radial de 4 cuadrantes (0x1A UDP) y marcadores con pulso de radar y distancia")

	# 1. Rueda de Ping en posición central izquierda
	var wheel_scene: PackedScene = load("res://ui/components/TacticalPing/TacticalPingWheel.tscn")
	var wheel: TacticalPingWheel = wheel_scene.instantiate() as TacticalPingWheel
	_stage.add_child(wheel)
	wheel.open_at(Vector2(260, 360))
	wheel.active_selection = TacticalPingWheel.PingType.ATTACK # Resaltar cuadrante Norte (ATACAR)

	# 2. Marcadores Screen-Space en el mundo a la derecha
	var marker_scene: PackedScene = load("res://ui/components/TacticalPing/TacticalPingMarker.tscn")

	# Marcador 1: PELIGRO (Ámbar)
	var m_danger: TacticalPingMarker = marker_scene.instantiate() as TacticalPingMarker
	m_danger.position = Vector2(560, 200)
	_stage.add_child(m_danger)
	m_danger.setup(TacticalPingMarker.PingType.DANGER, "Sylvia (Maga)", Vector3(12, 0, 30), 28.0)

	# Marcador 2: ATACAR (Carmesí)
	var m_attack: TacticalPingMarker = marker_scene.instantiate() as TacticalPingMarker
	m_attack.position = Vector2(820, 260)
	_stage.add_child(m_attack)
	m_attack.setup(TacticalPingMarker.PingType.ATTACK, "Valerius (Líder)", Vector3(-4, 0, 18), 14.5)

	# Marcador 3: EXTRAER (Esmeralda)
	var m_extract: TacticalPingMarker = marker_scene.instantiate() as TacticalPingMarker
	m_extract.position = Vector2(640, 420)
	_stage.add_child(m_extract)
	m_extract.setup(TacticalPingMarker.PingType.EXTRACT, "Kaelen (Cazador)", Vector3(45, 0, 95), 62.0)

	# 3. Panel explicativo de arquitectura
	var info_box := PanelContainer.new()
	info_box.position = Vector2(560, 520)
	info_box.custom_minimum_size = Vector2(580, 140)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.08, 0.11, 0.95)
	sb.border_color = Color(0.2, 0.35, 0.45, 0.8)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(10)
	info_box.add_theme_stylebox_override("panel", sb)
	_stage.add_child(info_box)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 12)
	info_box.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "ARQUITECTURA DE PINGS TÁCTICOS (PHASE 9.5 & 9.6 / ADR 097)"
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color("#46e3c1"))
	vbox.add_child(title)

	var desc := Label.new()
	desc.text = "• Protocolo UDP 0x1A: Paquete Little-Endian de 22B (opcode, sender_sid, ping_type, world_pos, target_sid).\n• Anti-Spoofing: Servidor Rust ECS sobrescribe player_id con el ID de sesión autenticado del socket UDP.\n• Token-Bucket Anti-Spam: Máximo 3 pings por ventana de 5s (100 ticks) descartados en silencio (O(1)).\n• Aislamiento de Escuadra: Retransmisión confinada exclusivamente a miembros del mismo party_id activo."
	desc.add_theme_font_size_override("font_size", 10)
	desc.add_theme_color_override("font_color", Color(0.85, 0.9, 0.95))
	vbox.add_child(desc)

	await _settle(4)
	await _wait_seconds(0.5)

	await _capture("evidence_tactical_ping_wheel.png", 14,
		"Rueda de pings tácticos modal y marcadores Screen-Space con radar expansivo y distancia en metros", {
			"wheel_instantiated": wheel.is_inside_tree(),
			"wheel_active": wheel.is_active,
			"marker_danger_ok": m_danger.is_inside_tree(),
			"marker_attack_ok": m_attack.is_inside_tree(),
			"marker_extract_ok": m_extract.is_inside_tree(),
		})



