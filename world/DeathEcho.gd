extends Node3D

var echo_id: String
var user_id: String
var username: String
var sid: int = 0

func _ready():
	add_to_group("interactable")
	_ensure_collision()
	TargetManager.target_changed.connect(_on_target_changed)

func interact(_caller = null):
	_open_inventory()

func _ensure_collision():
	var area = get_node_or_null("Area3D")
	if !area:
		area = Area3D.new()
		area.name = "Area3D"
		add_child(area)
	
	# Recursive search for ANY MeshInstance3D
	var meshes = find_children("*", "MeshInstance3D", true, false)
	if meshes.size() == 0: return
	var mesh = meshes[0]
	
	var shape = area.get_node_or_null("CollisionShape3D")
	if !shape:
		shape = CollisionShape3D.new()
		area.add_child(shape)
	
	var aabb = mesh.get_aabb()
	var box = BoxShape3D.new()
	box.size = aabb.size * mesh.scale * 1.2
	shape.shape = box
	shape.position = aabb.get_center() * mesh.scale
	
	area.collision_layer = 32 # Layer 6: Interactable Object
	area.collision_mask = 0
	
	if !area.input_event.is_connected(_on_input_event):
		area.input_event.connect(_on_input_event)

func setup(p_sid: int, p_raw_name: String):
	sid = p_sid
	var sid_str = str(p_sid)
	if "|" in p_raw_name:
		var parts = p_raw_name.split("|")
		echo_id = parts[0]
		username = parts[1]
	else:
		echo_id = sid_str # Fallback
		username = p_raw_name
	
	var display_name = username
	if display_name.length() > 20 and "-" in display_name:
		display_name = "Restos de Explorador Caído"
	else:
		display_name = "Restos de: " + username

	# 1. 3D Legacy Nameplate fallback
	var nameplate = get_node_or_null("Nameplate") as Label3D
	if nameplate:
		nameplate.text = display_name
		nameplate.font_size = 52
		nameplate.outline_size = 16
		nameplate.outline_modulate = Color.BLACK
		nameplate.pixel_size = 0.009
		nameplate.no_depth_test = true
		nameplate.render_priority = 25
		nameplate.shaded = false
		nameplate.modulate = Color(1.0, 0.9, 0.6) # Amber gold tone for loot clarity

	# 2. Add visual golden light beacon shaft
	if not has_node("LootBeacon"):
		var beacon = MeshInstance3D.new()
		beacon.name = "LootBeacon"
		var cyl = CylinderMesh.new()
		cyl.top_radius = 0.06
		cyl.bottom_radius = 0.16
		cyl.height = 3.5
		beacon.mesh = cyl
		beacon.position = Vector3(0, 1.75, 0)
		var bmat = StandardMaterial3D.new()
		bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bmat.albedo_color = Color(1.0, 0.82, 0.2, 0.8)
		bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		beacon.material_override = bmat
		add_child(beacon)

	# 3. Screen-Space 2D Loot Label projection
	if has_node("/root/ScreenSpaceManager"):
		var echo_lbl_scene = load("res://ui/screenspace/DeathEchoLabel.tscn")
		if echo_lbl_scene:
			var echo_lbl = echo_lbl_scene.instantiate()
			echo_lbl.setup_loot(display_name, 3)
			ScreenSpaceManager.register_target(self, echo_lbl, Vector3(0, 1.8, 0))
			if nameplate:
				nameplate.visible = false

func _exit_tree() -> void:
	if has_node("/root/ScreenSpaceManager") and ScreenSpaceManager.instance:
		ScreenSpaceManager.instance.unregister_target(self)

func _on_input_event(_camera, event, _position, _normal, _shape_idx):
	if UIOrchestrator.is_mouse_over_ui():
		return
		
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if TargetManager.current_target_sid == sid:
			_show_context_menu()

func _on_target_changed(new_sid: int):
	var meshes = find_children("*", "MeshInstance3D", true, false)
	if meshes.size() == 0: return
	var mesh = meshes[0]
	
	if new_sid != 0 and new_sid == sid:
		var mat = mesh.material_override
		if !mat: mat = mesh.get_surface_override_material(0)
		if !mat: mat = mesh.get_active_material(0)
		
		if mat: mat = mat.duplicate()
		else: mat = StandardMaterial3D.new()
		
		if mesh.material_override: mesh.material_override = mat
		else: mesh.set_surface_override_material(0, mat)
		
		var outline_mat = StandardMaterial3D.new()
		outline_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		outline_mat.albedo_color = Color.WHITE
		outline_mat.cull_mode = BaseMaterial3D.CULL_FRONT
		outline_mat.grow = true
		outline_mat.grow_amount = 0.05
		mat.next_pass = outline_mat
	else:
		if mesh.material_override: mesh.material_override.next_pass = null
		mesh.set_surface_override_material(0, null)

func _show_context_menu():
	var options = [
		{"label": "Abrir", "color": Color.WHITE},
		{"label": "Examinar", "color": Color.WHITE},
	]
	UIOrchestrator.open_context_menu(options, get_viewport().get_mouse_position(), _on_menu_id_pressed)

func _on_menu_id_pressed(id: int):
	match id:
		0: 
			_open_inventory()
		1: 
			_examine()

func _open_inventory():
	print("[DeathEcho] Opening loot window for: ", echo_id)
	if has_node("/root/UIOrchestrator"):
		get_node("/root/UIOrchestrator").open_window("loot_window", {
			"echo_id": echo_id,
			"name": username
		}, "loot_" + echo_id)

func _examine():
	print("[DeathEcho] Examinando: Los restos mortales de ", username, ". (ID: ", echo_id, ")")
	# Puedes integrarlo con una consola de chat in-game si la hay.
