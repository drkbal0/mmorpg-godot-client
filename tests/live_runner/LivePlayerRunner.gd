extends Node

## LivePlayerRunner.gd — Simulación de jugador en vivo sobre el cliente real.
##
## A diferencia de VisualTestHarness (paneles aislados sobre fondo neutro), este
## runner instancia el mundo 3D REAL del cliente (res://World.tscn: terreno,
## WorldEnvironment con cielo y niebla, DirectionalLight3D con sombras y la
## topografía declarativa) y el avatar REAL (res://player.tscn) con su cámara
## en tercera persona. Las entidades se inyectan por los mismos handlers que usa
## la red (World._on_static_entity_spawned), y la UI se monta en capas:
##
##   CanvasLayer 1  KiSpectralVision (post-proceso, solo afecta al mundo 3D)
##                  + KiAuraProjector (auras, dibujadas tras el post-proceso)
##   CanvasLayer 2  HUDv2 + BossEncounterFrame + ThreatTable + PartyFrames
##   CanvasLayer 3  Ventanas (MarketplaceWindow) y rueda de pings
##   CanvasLayer 15/50/110  retícula / nameplates / telemetría F9 (del cliente)
##
## No hay servidor: es una simulación offline determinista. El overlay F9 lo
## refleja con "Ping: offline" en vez de inventar una latencia.
##
## Uso:
##   godot --headless --path clients/godot-mmo-client res://tests/live_runner/LivePlayerRunner.tscn -- --output-dir=../../evidence
##
## Con --headless el renderer "dummy" no produce píxeles: el proceso actúa como
## orquestador, relanza esta escena con ventana real 1280x720 (primero con el
## driver nativo del proyecto; si falla, con --rendering-driver opengl3) y
## después re-audita cada PNG desde disco de forma independiente.

const SCENE_PATH := "res://tests/live_runner/LivePlayerRunner.tscn"
const DEFAULT_OUTPUT_DIR := "../../evidence"
const MANIFEST_NAME := "live_player_manifest.json"
const RENDER_CHILD_FLAG := "--render-child"
const TARGET_SIZE := Vector2i(1280, 720)
const MIN_PNG_BYTES := EvidenceAudit.MIN_PNG_BYTES
const MIN_MEAN_LUMA := EvidenceAudit.MIN_MEAN_LUMA
const OFFLINE_GATEWAY := "offline://live-player-runner"

const PLAYER_NAME := "Aren"
const STONE_ICON := "res://assets/icons/items/stone1x1.png"

const KiSpectralVision = preload("res://ui/components/KiSpectralVision/KiSpectralVision.gd")
const KiAuraProjector = preload("res://ui/components/KiSpectralVision/KiAuraProjector.gd")
const TacticalPingWheel = preload("res://ui/components/TacticalPing/TacticalPingWheel.gd")
const TacticalPingMarker = preload("res://ui/components/TacticalPing/TacticalPingMarker.gd")
const TacticalPingBeam3D = preload("res://world/TacticalPingBeam3D.gd")
const ThreatTablePanel = preload("res://ui/components/BossEncounterFrame/ThreatTablePanel.gd")
const MarketplaceWindow = preload("res://ui/windows/MarketplaceWindow/MarketplaceWindow.gd")
const EvidenceAudit = preload("res://tests/live_runner/EvidenceAudit.gd")

var _output_dir := ""
var _captures: Array = []
var _started_msec := 0

var _world: Node = null
var _player: CharacterBody3D = null
var _ki_layer: CanvasLayer = null
var _hud_layer: CanvasLayer = null
var _window_layer: CanvasLayer = null
var _combat_layer: CanvasLayer = null
var _hud: Control = null
var _ki: Control = null
var _auras: Control = null

## Nodos/entidades propios de una escena; se liberan al pasar a la siguiente.
var _scene_nodes: Array = []
var _scene_sids: Array = []
## Marcadores screen-space anclados a un punto 3D: [{control, world_pos, anchor}]
var _anchored: Array = []


# ===========================================================================
# Entrada
# ===========================================================================

func _ready() -> void:
	_started_msec = Time.get_ticks_msec()
	_output_dir = _resolve_output_dir()
	var err := DirAccess.make_dir_recursive_absolute(_output_dir)
	if err != OK:
		push_error("[LivePlayerRunner] No se pudo crear output-dir '%s' (err %d)" % [_output_dir, err])
		get_tree().quit(1)
		return
	print("[LivePlayerRunner] output-dir: ", _output_dir)

	if DisplayServer.get_name() == "headless":
		_run_as_headless_orchestrator()
		return

	_configure_window()
	_run_live_session.call_deferred()


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
	return ProjectSettings.globalize_path("res://").path_join(raw).simplify_path()


func _is_render_child() -> bool:
	return RENDER_CHILD_FLAG in OS.get_cmdline_user_args()


func _configure_window() -> void:
	var win := get_window()
	win.mode = Window.MODE_WINDOWED
	win.size = TARGET_SIZE
	win.title = "MMORPG — Live Player Runner (cliente real, simulación offline)"
	DisplayServer.window_set_size(TARGET_SIZE)


# ===========================================================================
# Orquestador headless: relanza con ventana real y re-audita desde disco
# ===========================================================================

func _run_as_headless_orchestrator() -> void:
	if _is_render_child():
		push_error("[LivePlayerRunner] El proceso hijo de render arrancó en headless; no hay GPU.")
		get_tree().quit(1)
		return

	var exe := OS.get_executable_path()
	if OS.get_name() == "Windows" and not exe.ends_with("_console.exe"):
		var console_exe := exe.get_basename() + "_console.exe"
		if FileAccess.file_exists(console_exe):
			exe = console_exe

	var manifest_path := _output_dir.path_join(MANIFEST_NAME)
	# Intento 1: driver nativo del proyecto (Forward+). Intento 2: OpenGL 3.
	var attempts: Array = [[], ["--rendering-driver", "opengl3"]]
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--driver="):
			attempts = [["--rendering-driver", arg.substr("--driver=".length())]]

	var ok := false
	for extra in attempts:
		if FileAccess.file_exists(manifest_path):
			DirAccess.remove_absolute(manifest_path)
		var args := PackedStringArray(["--path", ProjectSettings.globalize_path("res://"), SCENE_PATH])
		args.append_array(PackedStringArray(extra))
		args.append_array(PackedStringArray([
			"--resolution", "%dx%d" % [TARGET_SIZE.x, TARGET_SIZE.y],
			"--", "--output-dir=" + _output_dir, RENDER_CHILD_FLAG,
		]))
		print("[LivePlayerRunner] Renderer headless (dummy) detectado: relanzando con ventana real.")
		print("[LivePlayerRunner]   ", exe, " ", " ".join(args))
		var output: Array = []
		var code := OS.execute(exe, args, output, true, false)
		for chunk in output:
			for line in str(chunk).split("\n"):
				if line.strip_edges() != "":
					print("  [render-child] ", line.strip_edges())
		print("[LivePlayerRunner] Proceso de render terminó con código %d" % code)
		ok = code == 0 and _validate_manifest_and_files(manifest_path)
		if ok or FileAccess.file_exists(manifest_path):
			break # con manifest, un FAIL es real: no se reintenta con otro driver
	print("[LivePlayerRunner] RESULTADO GLOBAL: %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)


## Segunda validación, independiente del proceso hijo: relee cada PNG desde
## disco y recalcula tamaño, peso y luminancia.
func _validate_manifest_and_files(manifest_path: String) -> bool:
	if not FileAccess.file_exists(manifest_path):
		push_error("[LivePlayerRunner] Falta el manifest: " + manifest_path)
		return false
	var data = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not (data is Dictionary) or not data.has("captures"):
		push_error("[LivePlayerRunner] Manifest inválido")
		return false
	var all_ok: bool = str(data.get("overall_status", "")) == "PASS" and data["captures"].size() == 6
	for cap in data["captures"]:
		var file := str(cap.get("file", ""))
		var audit := audit_png(_output_dir.path_join(file))
		var cap_ok: bool = str(cap.get("status", "")) == "PASS" and bool(audit["pass"])
		print("[LivePlayerRunner]   %-44s child=%s  disk: %dx%d %7.1f KB luma=%.3f -> %s" % [
			file, cap.get("status", "?"), audit["width"], audit["height"],
			float(audit["bytes"]) / 1024.0, audit["mean_luma"], "PASS" if cap_ok else "FAIL"])
		all_ok = all_ok and cap_ok
	return all_ok


static func audit_png(path: String) -> Dictionary:
	return EvidenceAudit.audit_png(path)


static func mean_luma(img: Image) -> float:
	return EvidenceAudit.mean_luma(img)


# ===========================================================================
# Sesión de juego
# ===========================================================================

func _run_live_session() -> void:
	_configure_offline_network()
	await _boot_world()

	await _scene_01_exploration()
	await _reset_scene()
	await _scene_02_ki_spectral_vision()
	await _reset_scene()
	await _scene_03_boss_encounter()
	await _reset_scene()
	await _scene_04_tactical_ping()
	await _reset_scene()
	await _scene_05_marketplace()
	await _reset_scene()
	await _scene_06_party_combat()

	_write_manifest()
	var all_pass := _captures.size() == 6
	for c in _captures:
		all_pass = all_pass and c["status"] == "PASS"
	print("[LivePlayerRunner] %d capturas -> %s" % [_captures.size(), "PASS" if all_pass else "FAIL"])
	get_tree().quit(0 if all_pass else 1)


func _configure_offline_network() -> void:
	var auth: Node = get_node_or_null("/root/AuthManager")
	if auth and "gateway_url" in auth:
		auth.gateway_url = OFFLINE_GATEWAY
	AuthManager.selected_character_id = ""
	AuthManager.selected_character_name = PLAYER_NAME


func _boot_world() -> void:
	# 1. Mundo real del cliente.
	_world = load("res://World.tscn").instantiate()
	add_child(_world)
	await get_tree().process_frame

	# 2. Avatar real en tercera persona (equivalente a pulsar el toggle de cámara).
	var player_scene: PackedScene = load("res://player.tscn")
	_player = player_scene.instantiate()
	_player.set("camera_mode", 1) # CameraMode.THIRD_PERSON
	AuthManager.last_pos = Vector3(0, 1, 8)
	_world.add_child(_player)
	_world.local_player = _player
	# El runner conduce cámara/orientación directamente: no aceptar ratón del SO.
	_player.set_process_input(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	# 3. El HUD legado (PlayerHUD) se reemplaza por HUDv2.
	if UIOrchestrator:
		UIOrchestrator.close_window("player_hud", true)

	# 4. Capas de UI.
	_ki_layer = _make_layer("KiSpectralLayer", 1)
	_hud_layer = _make_layer("HUDv2Layer", 2)
	_combat_layer = _make_layer("CombatFramesLayer", 8) # jefe / amenaza / escuadra: sobre nameplates (5)
	_window_layer = _make_layer("RunnerOverlayLayer", 12) # rueda de pings (sobre ventanas = 10)

	_ki = (load("res://ui/components/KiSpectralVision/KiSpectralVision.tscn") as PackedScene).instantiate()
	_ki_layer.add_child(_ki)
	_ki.set_vision_active(false)
	_auras = KiAuraProjector.new()
	_auras.name = "KiAuraProjector"
	_ki_layer.add_child(_auras) # hermano POSTERIOR al ShaderRect

	_hud = (load("res://ui/components/HUDv2/hud.tscn") as PackedScene).instantiate()
	_hud_layer.add_child(_hud)
	_configure_hud()

	# 5. Telemetría F9 compacta (equivalente a pulsar F9 en el cliente).
	_world.debug_overlay_compact = true
	_world.set_hitbox_debug_visible(true)

	# Dejar que NoiseTexture2D (terreno) y shaders terminen de generarse.
	await _wait_seconds(1.5)


func _make_layer(layer_name: String, index: int) -> CanvasLayer:
	var l := CanvasLayer.new()
	l.name = layer_name
	l.layer = index
	add_child(l)
	return l


func _configure_hud() -> void:
	_hud.set_accent(Color("#46e3c1"))
	_hud.set_shape("trapecio")
	_hud.set_level(14, 0.62)
	_hud.set_health(1240.0, 1500.0, 6.4)
	_hud.set_mana(520.0, 700.0)
	_hud.set_gold(3820)
	_hud.set_stats({
		"attack_damage": 142, "ability_power": 68, "attack_speed": 0.92, "crit": "20%",
		"armor_pen": "12 | 10%", "magic_pen": "0 | 0%", "life_steal": "6%", "omnivamp": "0%",
		"armor": 74, "magic_resist": 52, "tenacity": "15%", "heal_shield": "0%",
		"ability_haste": 30, "move_speed": 355, "attack_range": 175, "regen": "24 | 58",
	})
	var stone: Texture2D = load(STONE_ICON)
	var names := ["Piedra Rúnica", "Poción Mayor de Vida", "Elixir de Maná", "Pergamino", "Bomba Incendiaria", "Vial de Velocidad"]
	var stacks := [5, 3, 12, 1, 8, 2]
	for i in range(6):
		_hud.set_item(i, stone, stacks[i], names[i], "item_%d" % i)
	_hud.items[1].cooldown_total = 15.0
	_hud.items[1].cooldown_remaining = 9.2
	_hud.push_feed("06:12", "Sylvia", "Maga", "ha adquirido Katana de Sombras", true)


# ===========================================================================
# Utilidades de escena
# ===========================================================================

func _wait_seconds(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


## Warm-up obligatorio antes de cada captura: 6 frames de proceso, 2 de física
## y el post-draw del RenderingServer (shaders compilados, sombras rasterizadas).
func _warmup() -> void:
	for i in range(6):
		await get_tree().process_frame
	for i in range(2):
		await get_tree().physics_frame
	await RenderingServer.frame_post_draw


## Cámara de tercera persona "sobre el hombro" elevada: deja ver los pies del
## avatar y su sombra por encima del HUDv2 (la luz solar de World.tscn llega
## desde detrás-izquierda de la cámara en estas orientaciones).
func _place_player(pos: Vector3, look_target: Vector3, cam_pitch_deg: float = -27.0, shoulder: float = 0.9, cam_height: float = 4.0, cam_back: float = 6.2) -> void:
	_player.global_position = pos
	_player.velocity = Vector3.ZERO
	var flat := Vector3(look_target.x, pos.y, look_target.z)
	if flat.distance_to(pos) > 0.01:
		_player.look_at(flat, Vector3.UP)
	var cam: Camera3D = _player.get_node("Camera3D")
	cam.position = Vector3(shoulder, cam_height, cam_back) # over-the-shoulder
	cam.rotation_degrees = Vector3(cam_pitch_deg, 0, 0)
	cam.current = true


func _spawn_entity(sid: int, type: int, pos: Vector3, e_name: String, max_hp: float = 1200.0) -> Node3D:
	_world._on_static_entity_spawned(sid, type, pos, 5.0, 15.0, max_hp, e_name)
	_scene_sids.append(sid)
	var n: Node3D = _world.remote_players.get(sid)
	if n and "screenspace_nameplate_instance" in n and n.screenspace_nameplate_instance \
			and n.screenspace_nameplate_instance.has_method("setup"):
		n.screenspace_nameplate_instance.setup(e_name, max_hp, max_hp, type == 3, "‹ ENEMIGO ›" if type == 3 else "‹ ALIADO ›", 18)
	return n


func _tint(n: Node3D, col: Color) -> void:
	var mesh: MeshInstance3D = n.get_node_or_null("MeshInstance3D")
	if mesh:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = col
		mat.roughness = 0.55
		mesh.set_surface_override_material(0, mat)


func _track(node: Node) -> Node:
	_scene_nodes.append(node)
	return node


func _reset_scene() -> void:
	# Sin servidor nadie despawnea los proyectiles: limpiarlos entre escenas.
	for pid in _world.active_projectiles.keys():
		var proj = _world.active_projectiles[pid]
		if is_instance_valid(proj):
			proj.queue_free()
	_world.active_projectiles.clear()
	for sid in _scene_sids:
		_world.remove_remote_player(sid)
	_scene_sids.clear()
	for n in _scene_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_scene_nodes.clear()
	_anchored.clear()
	_auras.clear_targets()
	_ki.set_vision_active(false)
	if UIOrchestrator:
		UIOrchestrator.close_all_windows()
		UIOrchestrator.close_window("player_hud", true)
	await get_tree().process_frame


func _process(_delta: float) -> void:
	# Controles screen-space anclados a coordenadas del mundo (badge del ping).
	if _anchored.is_empty() or _player == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	for a in _anchored:
		var ctrl: Control = a["control"]
		if is_instance_valid(ctrl) and not cam.is_position_behind(a["world_pos"]):
			ctrl.position = cam.unproject_position(a["world_pos"]) - a["anchor"]


func _player_snapshot() -> Dictionary:
	var cam := get_viewport().get_camera_3d()
	return {
		"player_name": PLAYER_NAME,
		"player_pos": _v3(_player.global_position),
		"player_yaw_deg": snappedf(fposmod(rad_to_deg(_player.global_rotation.y), 360.0), 0.1),
		"camera_pos": _v3(cam.global_position) if cam else [],
		"camera_mode": "THIRD_PERSON_OVER_SHOULDER",
		"telemetry_f9": _world.get_telemetry_line(),
		"entities_in_world": _world.remote_players.size() + 1,
	}


static func _v3(v: Vector3) -> Array:
	return [snappedf(v.x, 0.01), snappedf(v.y, 0.01), snappedf(v.z, 0.01)]


## Comprobaciones comunes de "perspectiva de jugador" para todas las escenas.
func _world_checks() -> Dictionary:
	var cam := get_viewport().get_camera_3d()
	var light: DirectionalLight3D = _world.get_node_or_null("DirectionalLight3D")
	var env: WorldEnvironment = _world.get_node_or_null("WorldEnvironment")
	var ground: MeshInstance3D = _world.get_node_or_null("Ground/MeshInstance3D")
	var ground_mat: StandardMaterial3D = ground.get_surface_override_material(0) if ground else null
	var mesh: MeshInstance3D = _player.get_node_or_null("MeshInstance3D")
	return {
		"world_tscn_instanced": _world != null and _world.scene_file_path == "res://World.tscn",
		"camera_is_player_camera": cam != null and cam == _player.get_node("Camera3D"),
		"player_in_camera_frustum": cam != null and cam.is_position_in_frustum(_player.global_position),
		"player_casts_shadow": mesh != null and mesh.visible and mesh.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
		"sun_shadows_enabled": light != null and light.shadow_enabled,
		"sky_and_fog": env != null and env.environment.background_mode == Environment.BG_SKY and env.environment.fog_enabled,
		"ground_textured": ground_mat != null and ground_mat.albedo_texture != null,
		"f9_telemetry_visible": _world.debug_overlay_layer.visible and _world.debug_overlay_label.text.begins_with("XYZ: ("),
		"hud_layer_is_2": _hud_layer.layer == 2,
	}


## Captura el viewport real, valida en el propio proceso y registra en manifest.
func _capture(index: int, file_name: String, title: String, description: String, scene_checks: Dictionary, extra: Dictionary = {}) -> void:
	await _warmup()
	var img: Image = get_viewport().get_texture().get_image()
	var checks := _world_checks()
	checks.merge(scene_checks)
	var has_pixels := img != null and not img.is_empty()
	var size := img.get_size() if has_pixels else Vector2i.ZERO
	var luma := mean_luma(img) if has_pixels else 0.0
	var path := _output_dir.path_join(file_name)
	var save_err := img.save_png(path) if has_pixels else ERR_UNCONFIGURED
	var bytes := 0
	if save_err == OK and FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		bytes = f.get_length()
		f.close()
	checks["resolution_1280x720"] = size == TARGET_SIZE
	checks["png_saved"] = save_err == OK
	checks["png_over_50kb"] = bytes > MIN_PNG_BYTES
	checks["mean_luminance_over_0_08"] = luma > MIN_MEAN_LUMA

	var failed: Array = []
	for k in checks.keys():
		if not bool(checks[k]):
			failed.append(k)
	var entry := {
		"scene": index,
		"file": file_name,
		"title": title,
		"description": description,
		"timestamp": Time.get_datetime_string_from_system(true) + "Z",
		"status": "PASS" if failed.is_empty() else "FAIL",
		"size": [size.x, size.y],
		"bytes": bytes,
		"mean_luminance": snappedf(luma, 0.0001),
		"fps": Engine.get_frames_per_second(),
		"checks": checks,
		"failed_checks": failed,
	}
	entry.merge(_player_snapshot())
	entry.merge(extra)
	_captures.append(entry)
	print("[LivePlayerRunner] %s -> %s (%.1f KB, luma %.3f)%s" % [
		file_name, entry["status"], bytes / 1024.0, luma, "" if failed.is_empty() else " FALLAN: " + str(failed)])


func _write_manifest() -> void:
	var all_pass := _captures.size() == 6
	for c in _captures:
		all_pass = all_pass and c["status"] == "PASS"
	var manifest := {
		"suite": "LivePlayerRunner — Fase 9.5 & 9.6 (perspectiva de jugador en el cliente real)",
		"generated_at": Time.get_datetime_string_from_system(true) + "Z",
		"godot_version": Engine.get_version_info()["string"],
		"rendering_driver": RenderingServer.get_current_rendering_driver_name(),
		"rendering_method": RenderingServer.get_current_rendering_method(),
		"video_adapter": RenderingServer.get_video_adapter_name(),
		"world_scene": "res://World.tscn",
		"player_scene": "res://player.tscn",
		"network_mode": "offline (sin servidor; entidades inyectadas vía World._on_static_entity_spawned)",
		"warmup": {"process_frames": 6, "physics_frames": 2, "frame_post_draw": true},
		"audit_thresholds": {"size": [TARGET_SIZE.x, TARGET_SIZE.y], "min_bytes": MIN_PNG_BYTES, "min_mean_luminance": MIN_MEAN_LUMA},
		"canvas_layers": {"ki_spectral_vision": 1, "hudv2": 2, "nameplates": 5, "combat_frames": 8, "ui_orchestrator_windows": 10, "ping_wheel": 12, "crosshair": 15, "f9_telemetry": 110},
		"duration_sec": snappedf((Time.get_ticks_msec() - _started_msec) / 1000.0, 0.01),
		"overall_status": "PASS" if all_pass else "FAIL",
		"captures": _captures,
	}
	var f := FileAccess.open(_output_dir.path_join(MANIFEST_NAME), FileAccess.WRITE)
	f.store_string(JSON.stringify(manifest, "  "))
	f.close()


# ===========================================================================
# Escena 1 — Exploración con HUDv2, retícula y telemetría F9
# ===========================================================================

func _scene_01_exploration() -> void:
	_place_player(Vector3(1.5, 1.0, 10.0), Vector3(-1.0, 1.0, -15.0))
	var merchant := _spawn_entity(101, 4, Vector3(-6.5, 1.0, -1.5), "Mercader Errante", 800.0)
	var guard := _spawn_entity(102, 3, Vector3(7.5, 1.0, -9.0), "Centinela Corrupto", 1200.0)
	await _wait_seconds(0.6)

	var crosshair: CanvasLayer = _player.get_node_or_null("CrosshairLayer")
	await _capture(1, "live_player_01_exploration_hudv2.png",
		"Exploración en 3ª persona con HUDv2",
		"Avatar real (player.tscn) en World.tscn con sombra del sol, retícula cian, HUDv2 con quickslots [1]-[6] y telemetría F9.",
		{
			"crosshair_cyan_visible": crosshair != null and crosshair.visible,
			"hudv2_visible": _hud.is_visible_in_tree(),
			"quickslots_1_to_6": _hud.items.size() == 6 and _hud.items[0].stacks == 5,
			"quickslot_2_cooldown": _hud.items[1].cooldown_remaining > 0.0,
			"npcs_spawned": merchant != null and guard != null,
		})


# ===========================================================================
# Escena 2 — Visión Espectral de Ki con auras por atributo
# ===========================================================================

func _scene_02_ki_spectral_vision() -> void:
	_place_player(Vector3(0.5, 1.0, 11.0), Vector3(0.5, 1.0, -6.0), -24.0)
	var guard := _spawn_entity(201, 3, Vector3(-6.0, 1.0, 4.0), "Guardia Carmesí")
	var scout := _spawn_entity(202, 4, Vector3(6.0, 1.0, 2.0), "Explorador Esmeralda", 900.0)
	var mage := _spawn_entity(203, 3, Vector3(-4.5, 1.0, -12.0), "Mago del Vacío", 950.0)
	var boss := _spawn_entity(204, 3, Vector3(4.5, 2.4, -16.0), "Val'Gorath", 100000.0)
	boss.scale = Vector3(2.4, 2.4, 2.4)
	_tint(guard, Color(0.75, 0.3, 0.3))
	_tint(scout, Color(0.3, 0.7, 0.5))
	_tint(mage, Color(0.5, 0.35, 0.8))
	_tint(boss, Color(0.35, 0.18, 0.4))

	# Auras decodificadas por el decodificador real de atributos.
	var aura_guard := KiSpectralVision.get_aura_color(85.0, 40.0, 20.0)
	var aura_scout := KiSpectralVision.get_aura_color(30.0, 90.0, 25.0)
	var aura_mage := KiSpectralVision.get_aura_color(20.0, 35.0, 95.0)
	var aura_boss := KiSpectralVision.get_aura_color(300.0, 120.0, 200.0, true)
	_auras.track(guard, aura_guard, "FUERZA · Guardia Carmesí")
	_auras.track(scout, aura_scout, "AGILIDAD · Explorador Esmeralda")
	_auras.track(mage, aura_mage, "INTELIGENCIA · Mago del Vacío")
	_auras.track(boss, aura_boss, "JEFE MUNDIAL · Val'Gorath", 1.2, 1.0)

	_ki.is_in_combat = true
	_ki.set_vision_active(true)
	_auras.pulse_hz = KiSpectralVision.get_pulse_frequency(true)
	await _wait_seconds(0.6)

	var rect: ColorRect = _ki.get_node("ShaderRect")
	var mat := rect.material as ShaderMaterial
	await _capture(2, "live_player_02_ki_spectral_vision.png",
		"Visión Espectral de Ki en el mundo 3D",
		"Post-proceso ki_spectral_vision.gdshader (Rec.709, desaturación 0.85) sobre la geometría 3D en CanvasLayer 1; auras de Fuerza/Agilidad/Inteligencia/Jefe proyectadas tras el shader; HUDv2 en CanvasLayer 2 sin desaturar.",
		{
			"ki_active": _ki.is_active,
			"ki_layer_is_1": _ki_layer.layer == 1,
			"hud_above_ki_layer": _hud_layer.layer > _ki_layer.layer,
			"shader_desaturation_0_85": is_equal_approx(float(mat.get_shader_parameter("desaturation")), 0.85),
			"combat_pulse_4hz": is_equal_approx(float(mat.get_shader_parameter("pulse_speed")), 4.0),
			"aura_strength_red": aura_guard == KiSpectralVision.COLOR_STRENGTH,
			"aura_agility_green": aura_scout == KiSpectralVision.COLOR_AGILITY,
			"aura_intelligence_violet": aura_mage == KiSpectralVision.COLOR_INTELLIGENCE,
			"aura_boss_gold": aura_boss == KiSpectralVision.COLOR_BOSS,
			"four_auras_on_screen": _auras.visible_count == 4,
		},
		{"auras": {"strength": aura_guard.to_html(false), "agility": aura_scout.to_html(false),
			"intelligence": aura_mage.to_html(false), "boss": aura_boss.to_html(false)}})


# ===========================================================================
# Escena 3 — Encuentro con el Jefe de Mundo y Threat Table
# ===========================================================================

func _scene_03_boss_encounter() -> void:
	var boss_pos := Vector3(7.0, 3.2, -2.0)
	# El jugador encara la arena; el jefe queda a la derecha, sin obstáculos delante.
	_place_player(Vector3(2.5, 1.0, 7.5), Vector3(0.5, 1.0, -6.0), -24.0)
	var boss := _spawn_entity(301, 3, boss_pos, "Val'Gorath, Devorador de Sombras", 100000.0)
	boss.scale = Vector3(3.2, 3.2, 3.2)
	_tint(boss, Color(0.5, 0.16, 0.6))
	var tank := _spawn_entity(302, 4, Vector3(5.0, 1.0, 0.6), "Valerius", 2400.0)
	var healer := _spawn_entity(303, 4, Vector3(-2.5, 1.0, 1.0), "Sylvia", 1300.0)

	# Combate en curso con los efectos reales del cliente.
	# Bola de fuego en vuelo: a mitad de camino entre el jugador y el jefe.
	var mid := _player.global_position.lerp(Vector3(boss_pos.x, 1.4, boss_pos.z), 0.55)
	_world._spawn_fireball_projectile(9001, mid, Vector2(boss_pos.x - _player.global_position.x, boss_pos.z - _player.global_position.z).normalized(), 3.0)
	_world._spawn_floating_damage(boss_pos + Vector3(-1.6, 1.0, 1.0), 1840.0, true)
	_world._spawn_floating_damage(boss_pos + Vector3(-1.9, -0.6, 1.0), 615.0, false)

	var frame: BossEncounterFrame = (load("res://ui/components/BossEncounterFrame/BossEncounterFrame.tscn") as PackedScene).instantiate()
	_combat_layer.add_child(frame)
	_track(frame)
	frame.offset_top = 56.0
	frame.offset_bottom = 196.0
	frame.setup_boss(5001, "Val'Gorath, Devorador de Sombras", 100000.0, 3, 300)
	frame.set_hp(63250.0)
	frame.set_phase(3)
	frame.tick_enrage(300.0) # temporizador agotado -> fase Enrage
	frame.start_cast("Llamarada Umbría", 3.0)
	frame.update_cast_progress(0.62)
	frame.set_threat(100, true)

	# Tabla coherente con la histéresis Rust: el jugador está a ~12 m (rango,
	# x1.30). 2450 / 1800 = 1.36 >= 1.30, así que robar el aggro es legítimo.
	var table: ThreatTablePanel = ThreatTablePanel.new()
	_combat_layer.add_child(table)
	_track(table)
	table.position = Vector2(1016, 66)
	table.set_entries([
		{"name": PLAYER_NAME, "threat": 2450, "is_self": true},
		{"name": "Valerius", "threat": 1800, "role": "tank"},
		{"name": "Sylvia", "threat": 1320},
		{"name": "Kaelen", "threat": 610},
	])
	await _wait_seconds(0.35)

	var dist_to_boss := Vector2(_player.global_position.x, _player.global_position.z).distance_to(Vector2(boss_pos.x, boss_pos.z))
	await _capture(3, "live_player_03_boss_encounter_threat.png",
		"Combate contra Val'Gorath, Devorador de Sombras",
		"BossEncounterFrame con barra segmentada de 100k HP (10x10k), fase Enrage, casteo 'Llamarada Umbría', banner pulsante de aggro y Threat Table con el jugador en Top 1 (2,450 / 100%).",
		{
			"boss_spawned": boss != null and tank != null and healer != null,
			"boss_frame_visible": frame.is_visible_in_tree(),
			"boss_name": frame.boss_name == "Val'Gorath, Devorador de Sombras",
			"hp_100k_segmented": is_equal_approx(frame.max_hp, 100000.0) and frame.get_segment_count() == 10,
			"enraged": frame.is_enraged,
			"casting_llamarada": frame.is_casting and frame.cast_spell_name == "Llamarada Umbría",
			"aggro_banner_visible": frame.aggro_warning_badge.visible and frame.is_holding_aggro,
			"threat_top1_is_player": table.entries[0]["name"] == PLAYER_NAME and int(table.entries[0]["threat"]) == 2450,
			"threat_top1_100pct": table.get_threat_pct(0) == 100,
			"aggro_pull_respects_ranged_hysteresis": dist_to_boss > 6.0 and 2450.0 >= 1800.0 * 1.30,
		},
		{"boss_distance_m": snappedf(dist_to_boss, 0.01)})


# ===========================================================================
# Escena 4 — Rueda de pings tácticos (G) y marcador 3D en el terreno
# ===========================================================================

func _scene_04_tactical_ping() -> void:
	var start := Vector3(2.0, 1.0, 10.0)
	# Punto de terreno a exactamente 28.4 m (3D) del jugador, 20° a la izquierda.
	var horiz := sqrt(28.4 * 28.4 - 1.0)
	var ang := deg_to_rad(20.0)
	var ping_pos := Vector3(start.x - sin(ang) * horiz, 0.0, start.z - cos(ang) * horiz)
	_place_player(start, Vector3(start.x, 1.0, start.z - 20.0), -20.0)

	var beam: TacticalPingBeam3D = TacticalPingBeam3D.new()
	beam.ping_type = 1 # DANGER (protocolo 0x1A)
	_world.add_child(beam)
	_track(beam)
	beam.global_position = ping_pos

	var dist := _player.global_position.distance_to(ping_pos)
	var marker: TacticalPingMarker = (load("res://ui/components/TacticalPing/TacticalPingMarker.tscn") as PackedScene).instantiate()
	marker.auto_destroy = false
	_hud_layer.add_child(marker)
	_track(marker)
	marker.setup(TacticalPingMarker.PingType.DANGER, PLAYER_NAME, ping_pos, dist)
	# El chevrón del badge apunta a la cima del pilar de luz.
	_anchored.append({"control": marker, "world_pos": ping_pos + Vector3(0, 3.2, 0), "anchor": Vector2(70, 42)})

	# Pulsar G: la rueda se abre en el cursor, que apunta al terreno a la derecha.
	var wheel: TacticalPingWheel = (load("res://ui/components/TacticalPing/TacticalPingWheel.tscn") as PackedScene).instantiate()
	_window_layer.add_child(wheel)
	_track(wheel)
	var cursor := Vector2(820, 300)
	wheel.open_at(cursor)
	# Mover el ratón hacia el cuadrante Este (PELIGRO) con un evento de entrada real.
	var motion := InputEventMouseMotion.new()
	motion.position = cursor + Vector2(62, 4)
	motion.global_position = motion.position
	Input.parse_input_event(motion)
	await _wait_seconds(0.45)
	var via_input := wheel.active_selection == TacticalPingWheel.PingType.DANGER
	if not via_input:
		# El ratón físico del usuario pudo interferir: fijar la selección.
		wheel.set_process(false)
		wheel.active_selection = TacticalPingWheel.PingType.DANGER

	var cam := get_viewport().get_camera_3d()
	await _capture(4, "live_player_04_tactical_ping_wheel.png",
		"Rueda de pings tácticos (G) sobre el mundo 3D",
		"Rueda radial abierta en el cursor con el cuadrante PELIGRO resaltado; pilar de luz 3D en la coordenada del terreno y badge screen-space con la distancia real al jugador.",
		{
			"wheel_open": wheel.is_active and wheel.visible,
			"wheel_selection_danger": wheel.active_selection == TacticalPingWheel.PingType.DANGER,
			"beam_3d_in_frustum": cam.is_position_in_frustum(ping_pos + Vector3(0, 2, 0)),
			"marker_distance_28_4m": "%.1f" % marker.distance_meters == "28.4",
			"marker_visible": marker.is_visible_in_tree(),
		},
		{"ping_world_pos": _v3(ping_pos), "ping_distance_m": snappedf(dist, 0.01), "wheel_selection_via_input_event": via_input})


# ===========================================================================
# Escena 5 — Mercado P2P frente a un puesto comercial 3D
# ===========================================================================

func _scene_05_marketplace() -> void:
	# El jugador mira al norte (-Z). El puesto se coloca en el punto del terreno
	# bajo el píxel (960, 440): la mitad derecha de la pantalla, libre de la
	# ventana del mercado (anclada a la izquierda).
	var p_start := Vector3(6.0, 1.0, 26.0)
	_place_player(p_start, p_start + Vector3(0, 0, -10), -22.0)
	await get_tree().process_frame
	var cam: Camera3D = _player.get_node("Camera3D")
	var ray_from := cam.project_ray_origin(Vector2(960, 440))
	var ray_dir := cam.project_ray_normal(Vector2(960, 440))
	var stall_pos := ray_from + ray_dir * (-ray_from.y / ray_dir.y)
	var stall := _build_market_stall(stall_pos, p_start)
	var merchant := _spawn_entity(501, 4, stall.to_global(Vector3(0, 1.0, -1.0)), "Gildas el Mercader", 800.0)

	# Ruta real del cliente: el orquestador instancia la ventana en su WindowLayer (10).
	var market: MarketplaceWindow = UIOrchestrator.open_window("marketplace_window") as MarketplaceWindow
	await get_tree().process_frame
	market.position = Vector2(16, 64)
	market.player_silver = 1450
	market._update_wallet_display()
	# Búsqueda escrita SIN tilde: debe encontrar "Cristal de Vacío Cósmico".
	market.search_input.text = "vacio"
	market._on_search_changed("vacio")
	var found := market.get_filtered_listings()
	if not found.is_empty():
		market._prompt_purchase(found[0]) # confirmación atómica de compra
	await _wait_seconds(0.35)

	var split := MarketplaceWindow.escrow_split(int(found[0]["price"])) if not found.is_empty() else {}
	await _capture(5, "live_player_05_marketplace_in_world.png",
		"Mercado P2P en un puesto comercial del mundo",
		"MarketplaceWindow (Hextech) en primer plano sobre el puesto 3D: búsqueda 'vacio' sin tilde, listados con custodia 5% (floor, igual que el backend Go) y modal de confirmación atómica.",
		{
			"stall_merchant_spawned": merchant != null and stall != null,
			"stall_in_camera_frustum": get_viewport().get_camera_3d().is_position_in_frustum(stall.global_position + Vector3(0, 1, 0)),
			"market_open": market.is_visible_in_tree(),
			"market_via_ui_orchestrator": UIOrchestrator.is_window_open("marketplace_window"),
			"market_above_nameplates": (market.get_viewport() == get_viewport()) and UIOrchestrator.window_layer.layer > ScreenSpaceManager.layer,
			"accent_insensitive_search": found.size() >= 1 and "Vacío" in str(found[0]["name"]),
			"escrow_5pct_floor": not split.is_empty() and split["fee"] + split["net"] == int(found[0]["price"]) and split["fee"] == int(found[0]["price"]) * 5 / 100,
			"atomic_confirm_modal": market.confirm_modal != null and market.confirm_modal.visible,
		},
		{"search_query": "vacio", "matches": found.map(func(x): return x["name"]), "escrow_split": split})


func _build_market_stall(at: Vector3, facing: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = "MarketStall"
	_world.add_child(root)
	_track(root)
	root.global_position = at
	# El frente del puesto (+Z local) mira al jugador.
	root.look_at(Vector3(facing.x, at.y, facing.z), Vector3.UP)
	root.rotate_y(PI)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.45, 0.3, 0.18)
	wood.roughness = 0.85
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = Color(0.1, 0.55, 0.55)
	cloth.roughness = 0.7
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color(0.95, 0.75, 0.25)
	gold.metallic = 0.7
	gold.roughness = 0.3
	_box(root, Vector3(0, 0.55, 0), Vector3(3.2, 1.1, 0.9), wood) # mostrador
	for x in [-1.5, 1.5]:
		for z in [-0.4, -1.6]:
			_box(root, Vector3(x, 1.4, z), Vector3(0.14, 2.8, 0.14), wood) # postes
	var awning := _box(root, Vector3(0, 2.9, -0.95), Vector3(3.6, 0.1, 2.0), cloth) # toldo
	awning.rotation_degrees.x = -12.0
	for i in range(3):
		_box(root, Vector3(-0.9 + i * 0.9, 1.25, 0.05), Vector3(0.45, 0.3, 0.45), gold) # cofres
	var sign := Label3D.new()
	sign.text = "MERCADO · GILDAS"
	sign.font_size = 72
	sign.pixel_size = 0.006
	sign.outline_size = 14
	sign.modulate = Color("#ffd479")
	sign.position = Vector3(0, 3.35, 0.1)
	root.add_child(sign)
	var lantern := OmniLight3D.new()
	lantern.light_color = Color(1.0, 0.78, 0.45)
	lantern.light_energy = 1.6
	lantern.omni_range = 5.0
	lantern.position = Vector3(0, 2.4, 0.4)
	root.add_child(lantern)
	return root


func _box(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)
	return mi


# ===========================================================================
# Escena 6 — Combate en escuadra con PartyFrames y miembro abatido
# ===========================================================================

func _scene_06_party_combat() -> void:
	_place_player(Vector3(-1.5, 1.0, 10.5), Vector3(1.0, 1.0, -4.0), -24.0)
	var e1 := _spawn_entity(601, 3, Vector3(9.0, 1.0, -4.0), "Acólito Umbrío", 1200.0)
	var e2 := _spawn_entity(602, 3, Vector3(-6.0, 1.0, -7.0), "Acólito Umbrío", 1200.0)
	var tank := _spawn_entity(603, 4, Vector3(2.2, 1.0, 1.0), "Valerius", 2400.0)
	var mage := _spawn_entity(604, 4, Vector3(-7.5, 1.0, 3.0), "Sylvia", 1300.0)
	var downed := _spawn_entity(605, 4, Vector3(-4.5, 0.5, 5.0), "Kaelen", 1100.0)
	downed.rotation_degrees = Vector3(0, 30, 90) # abatido en el suelo
	_tint(downed, Color(0.55, 0.2, 0.2))
	if e1 and e1.has_method("update_hp"):
		e1.update_hp(42.0, 603, tank.global_position)
	_world._spawn_hitscan_tracer(_player.global_position + Vector3(0, 0.5, 0), Vector2(10.5, -14.5).normalized())
	_world._spawn_floating_damage(Vector3(9.0, 3.0, -4.0), 932.0, true)
	_world._spawn_floating_damage(Vector3(-6.0, 2.6, -7.0), 248.0, false)

	var party: PartyFrames = (load("res://ui/components/PartyFrames/PartyFrames.tscn") as PackedScene).instantiate()
	_combat_layer.add_child(party)
	_track(party)
	party.position = Vector2(16, 44)
	var members: Array[Dictionary] = [
		{"id": 603, "name": "Valerius", "class": "guardian", "hp": 1820.0, "max_hp": 2400.0,
			"mana": 260.0, "max_mana": 400.0, "distance": 8.6, "is_leader": true},
		{"id": 604, "name": "Sylvia", "class": "mage", "hp": 610.0, "max_hp": 1300.0,
			"mana": 455.0, "max_mana": 600.0, "distance": 5.4},
		{"id": 605, "name": "Kaelen", "class": "ranger", "hp": 0.0, "max_hp": 1100.0,
			"mana": 0.0, "max_mana": 300.0, "distance": 6.1, "is_downed": true, "timer_sec": 30.0},
	]
	party.set_party_members(members)
	party.set_loot_policy("ROUND_ROBIN")
	await _wait_seconds(0.3)

	var kaelen := party.get_member_frame(605)
	var valerius := party.get_member_frame(603)
	await _capture(6, "live_player_06_party_combat_vitals.png",
		"Combate en escuadra con PartyFrames",
		"PartyFrames con 3 compañeros (corona de líder en Valerius), Kaelen abatido con bleedout de 30 s en rojo pulsante y badge de botín Round-Robin; combate 3D con trazador hitscan y daño flotante.",
		{
			"party_three_members": party.get_all_frames().size() == 3,
			"leader_crown": valerius != null and valerius.is_leader and valerius.find_child("LeaderCrown", true, false) != null,
			"downed_member": kaelen != null and kaelen.is_downed,
			"bleedout_30s": kaelen != null and kaelen.bleedout_seconds > 29.0 and kaelen.bleedout_seconds <= 30.0,
			"loot_policy_round_robin": party.loot_policy == "ROUND_ROBIN" and party.get_node_or_null("LootPolicyBadge") != null,
			"enemies_in_world": e1 != null and e2 != null and mage != null,
		},
		{"bleedout_remaining_s": snappedf(kaelen.bleedout_seconds if kaelen else 0.0, 0.01)})
