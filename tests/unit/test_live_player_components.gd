extends SceneTree
## Headless unit test de las piezas añadidas para el LivePlayerRunner (Fase 9.5/9.6):
## ThreatTablePanel, KiAuraProjector, MarketplaceWindow.escrow_split, corona de
## líder y badge de loot en PartyFrames, segmentos/estilo de BossEncounterFrame,
## ticks adaptativos de WorldNameplate, TacticalPingBeam3D y telemetría F9 de World.
## Run: Godot --headless --path clients/godot-mmo-client -s res://tests/unit/test_live_player_components.gd
## Exit code 0 = all pass.

const ThreatTablePanel = preload("res://ui/components/BossEncounterFrame/ThreatTablePanel.gd")
const KiAuraProjector = preload("res://ui/components/KiSpectralVision/KiAuraProjector.gd")
const MarketplaceWindow = preload("res://ui/windows/MarketplaceWindow/MarketplaceWindow.gd")
const TacticalPingBeam3D = preload("res://world/TacticalPingBeam3D.gd")
const EvidenceAudit = preload("res://tests/live_runner/EvidenceAudit.gd")

var _fails: Array[String] = []
var _checks := 0


func _check(name: String, cond: bool, detail: String = "") -> void:
	_checks += 1
	if cond:
		print("  [PASS] ", name)
	else:
		_fails.append(name)
		printerr("  [FAIL] ", name, "  ", detail)


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	print("\n=== LIVE PLAYER COMPONENTS ===")

	# --- ThreatTablePanel ---------------------------------------------------
	var table: ThreatTablePanel = ThreatTablePanel.new()
	root.add_child(table)
	table.set_entries([
		{"name": "Valerius", "threat": 1800, "role": "tank"},
		{"name": "Aren", "threat": 2450, "is_self": true},
		{"name": "Kaelen", "threat": 610},
	])
	_check("threat: ordena descendente", table.entries[0]["name"] == "Aren" and table.entries[2]["name"] == "Kaelen")
	_check("threat: top1 = 100%", table.get_threat_pct(0) == 100)
	_check("threat: 1800/2450 = 73%", table.get_threat_pct(1) == 73, str(table.get_threat_pct(1)))
	_check("threat: índice fuera de rango = 0", table.get_threat_pct(9) == 0)
	_check("threat: formato miles", ThreatTablePanel._fmt(2450) == "2,450" and ThreatTablePanel._fmt(100000) == "100,000")
	table.set_entries([])
	_check("threat: tabla vacía sin crash", table.get_threat_pct(0) == 0)
	table.queue_free()

	# --- MarketplaceWindow.escrow_split (misma fórmula que Go CalculateTax) ---
	var ok_split := true
	for total in range(0, 5001):
		var sp: Dictionary = MarketplaceWindow.escrow_split(total)
		if sp["fee"] + sp["net"] != total or sp["fee"] != (total * 5) / 100:
			ok_split = false
			break
	_check("escrow: fee+net==total y fee=floor(5%) en 0..5000", ok_split)
	_check("escrow: 1200 -> 60 / 1140", MarketplaceWindow.escrow_split(1200) == {"fee": 60, "net": 1140})

	# --- PartyFrames: corona + loot policy ---------------------------------
	var party: PartyFrames = (load("res://ui/components/PartyFrames/PartyFrames.tscn") as PackedScene).instantiate()
	root.add_child(party)
	var members: Array[Dictionary] = [
		{"id": 1, "name": "Valerius", "class": "guardian", "is_leader": true},
		{"id": 2, "name": "Sylvia", "class": "mage"},
	]
	party.set_party_members(members)
	await process_frame
	var lead := party.get_member_frame(1)
	var other := party.get_member_frame(2)
	_check("party: líder con corona", lead.is_leader and lead.find_child("LeaderCrown", true, false) != null)
	_check("party: no-líder sin corona", not other.is_leader and other.find_child("LeaderCrown", true, false) == null)
	lead.is_leader = false
	await process_frame
	_check("party: quitar liderazgo elimina corona", lead.find_child("LeaderCrown", true, false) == null or lead.find_child("LeaderCrown", true, false).is_queued_for_deletion())
	party.set_loot_policy("round_robin")
	var badge_lbl: Label = party.get_node("LootPolicyBadge/LootPolicyLabel")
	_check("party: badge Round-Robin", party.loot_policy == "ROUND_ROBIN" and "ROUND-ROBIN" in badge_lbl.text)
	party.set_loot_policy("FREE_FOR_ALL")
	_check("party: badge reutilizado (FFA)", "FREE-FOR-ALL" in badge_lbl.text and party.get_children().filter(func(c): return c.name == "LootPolicyBadge").size() == 1)
	_check("party: badge no cuenta como miembro", party.get_all_frames().size() == 2)
	party.queue_free()

	# --- BossEncounterFrame: segmentos y barras coloreadas --------------------
	var frame: BossEncounterFrame = (load("res://ui/components/BossEncounterFrame/BossEncounterFrame.tscn") as PackedScene).instantiate()
	root.add_child(frame)
	frame.setup_boss(1, "Val'Gorath", 100000.0, 3, 300)
	_check("boss: 100k HP -> 10 segmentos", frame.get_segment_count() == 10)
	frame.setup_boss(1, "Mini", 25000.0)
	_check("boss: 25k HP -> 3 segmentos", frame.get_segment_count() == 3)
	var fill := frame.hp_bar.get_theme_stylebox("fill") as StyleBoxFlat
	_check("boss: barra de vida roja", fill != null and fill.bg_color == BossEncounterFrame.COLOR_HEALTH_NORMAL)
	var cfill := frame.cast_bar.get_theme_stylebox("fill") as StyleBoxFlat
	_check("boss: barra de casteo cian", cfill != null and cfill.bg_color == BossEncounterFrame.COLOR_CAST_BAR)
	frame.set_threat(100, true)
	var tfill := frame.threat_bar.get_theme_stylebox("fill") as StyleBoxFlat
	_check("boss: amenaza 100% en rojo", tfill.bg_color == BossEncounterFrame.COLOR_THREAT_AGGRO)
	frame.set_threat(85, false)
	_check("boss: amenaza 85% en ámbar", tfill.bg_color == BossEncounterFrame.COLOR_THREAT_DANGER)
	var default_fill := ProgressBar.new().get_theme_stylebox("fill")
	_check("boss: no muta el stylebox global del tema", default_fill != tfill)
	frame.queue_free()

	# --- WorldNameplate: ticks adaptativos -----------------------------------
	var plate = (load("res://ui/screenspace/WorldNameplate.tscn") as PackedScene).instantiate()
	root.add_child(plate)
	plate.setup("Boss", 100000.0, 100000.0, true)
	await process_frame
	plate.ticks_overlay.queue_redraw()
	await process_frame
	_check("nameplate: setup con 100k HP sin errores", is_equal_approx(plate.max_health, 100000.0))
	plate.queue_free()

	# --- KiAuraProjector -------------------------------------------------------
	var vp := SubViewport.new()
	vp.size = Vector2i(640, 360)
	root.add_child(vp)
	var cam := Camera3D.new()
	vp.add_child(cam)
	cam.position = Vector3(0, 2, 6)
	cam.current = true
	var target := Node3D.new()
	vp.add_child(target)
	target.position = Vector3(0, 1, 0)
	var behind := Node3D.new()
	vp.add_child(behind)
	behind.position = Vector3(0, 1, 20) # detrás de la cámara
	var proj: KiAuraProjector = KiAuraProjector.new()
	vp.add_child(proj)
	proj.track(target, KiSpectralVision.COLOR_STRENGTH, "FUERZA")
	proj.track(behind, KiSpectralVision.COLOR_AGILITY, "AGILIDAD")
	_check("ki aura: 2 objetivos registrados", proj.tracked_count() == 2)
	proj._draw()
	_check("ki aura: descarta objetivos tras la cámara", proj.visible_count == 1, str(proj.visible_count))
	proj.clear_targets()
	_check("ki aura: clear_targets", proj.tracked_count() == 0)
	vp.queue_free()

	# --- TacticalPingBeam3D ------------------------------------------------------
	var beam: TacticalPingBeam3D = TacticalPingBeam3D.new()
	beam.ping_type = 1
	root.add_child(beam)
	await process_frame
	var light: OmniLight3D = null
	for c in beam.get_children():
		if c is OmniLight3D:
			light = c
	_check("ping beam: pilar + núcleo + anillo + luz", beam.get_child_count() == 4 and light != null)
	_check("ping beam: color PELIGRO (ámbar)", light.light_color == TacticalPingBeam3D.PING_COLORS[1])
	beam.queue_free()

	# --- World: telemetría F9 compacta ------------------------------------------
	var world = (load("res://World.tscn") as PackedScene).instantiate()
	root.add_child(world)
	await process_frame
	var line: String = world.get_telemetry_line()
	var re := RegEx.new()
	re.compile("^XYZ: \\(-?\\d+\\.\\d, -?\\d+\\.\\d, -?\\d+\\.\\d\\) \\| Zone: \\d+ \\(.+\\) \\| Yaw: \\d+° \\| FPS: \\d+ \\| Ping: (offline|--|\\d+ms)$")
	_check("F9: formato 'XYZ | Zone | Yaw | FPS | Ping'", re.search(line) != null, line)
	_check("F9: sin socket -> Ping: offline", line.ends_with("Ping: offline"), line)
	world.debug_overlay_compact = true
	world.set_hitbox_debug_visible(true)
	world._update_debug_overlay()
	_check("F9: modo compacto = una línea", world.debug_overlay_label.text == world.get_telemetry_line())
	world.queue_free()

	# --- Auditoría de luminancia del runner -------------------------------------
	var black := Image.create(1280, 720, false, Image.FORMAT_RGB8)
	black.fill(Color("#0a0e17"))
	_check("audit: frame #0a0e17 por debajo de 0.08", EvidenceAudit.mean_luma(black) < 0.08)
	var grey := Image.create(1280, 720, false, Image.FORMAT_RGB8)
	grey.fill(Color(0.5, 0.5, 0.5))
	_check("audit: gris medio ~0.5", absf(EvidenceAudit.mean_luma(grey) - 0.5) < 0.01)

	await process_frame
	print("== %d checks, %d fallos ==" % [_checks, _fails.size()])
	quit(0 if _fails.is_empty() else 1)
