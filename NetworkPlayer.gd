extends Node3D
# Fix V7.1: Corrected viewport names and type hints for SubViewport compatibility.

## NetworkPlayer.gd - Jitter-Resistant Entity Interpolation
## Uses a state buffer with extrapolation to handle network lag.

var state_buffer: Array = []
var interpolation_delay: float = 0.2 # 200ms (4 server ticks) for maximum stability
var last_velocity: Vector3 = Vector3.ZERO
var extrapolation_limit: float = 0.2 # Allow up to 200ms of guessing
var sid: int = 0
var target_position: Vector3 
var current_server_time: float = -1.0

const world_hp_bar_scene = preload("res://ui/components/WorldHPBar/WorldHPBar.tscn")
const npc_indicator_scene = preload("res://ui/components/NpcIndicator/NpcIndicator.tscn")
var world_hp_bar_instance : Node3D
var npc_indicator_instance : Node3D

var hp_percent : int = 100
var _hp_initialized : bool = false
var max_hp : float = 1000.0:
	set(val):
		max_hp = val
		if world_hp_bar_instance:
			world_hp_bar_instance.set_max_hp(val)

var hitbox_debug_meshes: Array[MeshInstance3D] = []
var hitbox_debug_visible: bool = false

var head_shape_node: CollisionShape3D = null
var chest_shape_node: CollisionShape3D = null
var hips_shape_node: CollisionShape3D = null
var limbs_shape_node: CollisionShape3D = null

func _ready():
	target_position = position
	TargetManager.target_changed.connect(_on_target_changed)
	add_to_group("hitbox_debug")
	
	_ensure_collision()
	
	world_hp_bar_instance = world_hp_bar_scene.instantiate()
	add_child(world_hp_bar_instance)
	world_hp_bar_instance.setup(Color.RED)
	
	npc_indicator_instance = npc_indicator_scene.instantiate()
	add_child(npc_indicator_instance)
	npc_indicator_instance.visible = false
	# Default radii (will be updated via setup_attributes or network)
	npc_indicator_instance.setup(10.0, 2.0)
	
	# Move nameplate ABOVE the bar and make it BOLD/VISIBLE
	if has_node("Nameplate"):
		var nameplate = get_node("Nameplate") as Label3D
		nameplate.position = Vector3(0, 2.2, 0) # Higher up
		nameplate.font_size = 54 # Larger
		nameplate.outline_size = 18 # Much thicker outline for "bold" look
		nameplate.outline_modulate = Color.BLACK
		nameplate.no_depth_test = true
		nameplate.render_priority = 30
		nameplate.pixel_size = 0.009
		nameplate.shaded = false

func _ensure_collision():
	var area = get_node_or_null("Area3D")
	if !area:
		area = Area3D.new()
		area.name = "Area3D"
		add_child(area)
	
	for child in area.get_children():
		child.queue_free()
	hitbox_debug_meshes.clear()

	# 1. Head Hitbox (Sphere, radius 0.16m, multiplier 1.5)
	head_shape_node = CollisionShape3D.new()
	head_shape_node.name = "HeadHitbox"
	var head_sphere = SphereShape3D.new()
	head_sphere.radius = 0.16
	head_shape_node.shape = head_sphere
	head_shape_node.position = Vector3(0, 1.60, 0)
	head_shape_node.set_meta("hitbox_multiplier", 1.5)
	head_shape_node.set_meta("hitbox_name", "Head")
	area.add_child(head_shape_node)
	_create_hitbox_debug_mesh(head_shape_node, head_sphere, Color(1.0, 0.2, 0.2, 0.45))

	# 2. Chest / Torso Hitbox (Capsule, radius 0.22m, height 0.45m, multiplier 1.0)
	chest_shape_node = CollisionShape3D.new()
	chest_shape_node.name = "ChestHitbox"
	var chest_cap = CapsuleShape3D.new()
	chest_cap.radius = 0.22
	chest_cap.height = 0.45
	chest_shape_node.shape = chest_cap
	chest_shape_node.position = Vector3(0, 1.15, 0)
	chest_shape_node.set_meta("hitbox_multiplier", 1.0)
	chest_shape_node.set_meta("hitbox_name", "Chest")
	area.add_child(chest_shape_node)
	_create_hitbox_debug_mesh(chest_shape_node, chest_cap, Color(0.2, 0.7, 1.0, 0.45))

	# 3. Hips / Pelvis Hitbox (Capsule, radius 0.20m, height 0.30m, multiplier 1.0)
	hips_shape_node = CollisionShape3D.new()
	hips_shape_node.name = "HipsHitbox"
	var hips_cap = CapsuleShape3D.new()
	hips_cap.radius = 0.20
	hips_cap.height = 0.30
	hips_shape_node.shape = hips_cap
	hips_shape_node.position = Vector3(0, 0.75, 0)
	hips_shape_node.set_meta("hitbox_multiplier", 1.0)
	hips_shape_node.set_meta("hitbox_name", "Hips")
	area.add_child(hips_shape_node)
	_create_hitbox_debug_mesh(hips_shape_node, hips_cap, Color(0.2, 1.0, 0.3, 0.45))

	# 4. Limbs Hitbox (Capsule, radius 0.12m, height 0.60m, multiplier 0.75)
	limbs_shape_node = CollisionShape3D.new()
	limbs_shape_node.name = "LimbsHitbox"
	var limbs_cap = CapsuleShape3D.new()
	limbs_cap.radius = 0.12
	limbs_cap.height = 0.60
	limbs_shape_node.shape = limbs_cap
	limbs_shape_node.position = Vector3(0, 0.35, 0)
	limbs_shape_node.set_meta("hitbox_multiplier", 0.75)
	limbs_shape_node.set_meta("hitbox_name", "Limbs")
	area.add_child(limbs_shape_node)
	_create_hitbox_debug_mesh(limbs_shape_node, limbs_cap, Color(1.0, 0.85, 0.2, 0.45))

	area.collision_layer = 16 # Layer 5: Targetable Entity
	area.collision_mask = 0
	
	if !area.input_event.is_connected(_on_input_event):
		area.input_event.connect(_on_input_event)

func _create_hitbox_debug_mesh(parent_shape: CollisionShape3D, shape_res: Shape3D, color: Color):
	var mesh_inst = MeshInstance3D.new()
	mesh_inst.name = "DebugMesh"
	
	if shape_res is SphereShape3D:
		var sph = SphereMesh.new()
		sph.radius = shape_res.radius
		sph.height = shape_res.radius * 2.0
		mesh_inst.mesh = sph
	elif shape_res is CapsuleShape3D:
		var cap = CapsuleMesh.new()
		cap.radius = shape_res.radius
		cap.height = shape_res.height
		mesh_inst.mesh = cap
		
	var mat = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true
	mat.render_priority = 10
	mesh_inst.material_override = mat
	mesh_inst.visible = hitbox_debug_visible
	
	parent_shape.add_child(mesh_inst)
	hitbox_debug_meshes.append(mesh_inst)

func set_hitbox_debug_visible(vis: bool):
	hitbox_debug_visible = vis
	for m in hitbox_debug_meshes:
		if is_instance_valid(m):
			m.visible = vis

func _on_input_event(_camera, event, _position, _normal, _shape_idx):
	if UIOrchestrator.is_mouse_over_ui():
		return
		
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if TargetManager.current_target_sid == sid:
			_show_context_menu()

func _show_context_menu():
	if sid == 0: return
	
	var options = [
		{"label": "Examinar", "color": Color.WHITE},
	]
	
	if AuthManager.is_admin:
		options.append({"label": "--- ADMIN TOOLS ---", "color": Color.ORANGE_RED})
		options.append({"label": "Editar Atributos", "color": Color.YELLOW, "metadata": "admin_edit"})
	
	UIOrchestrator.open_context_menu(options, get_viewport().get_mouse_position(), _on_menu_id_pressed)

func _on_menu_id_pressed(id: int):
	match id:
		0: # Examinar
			print("[NetworkPlayer] Examinando SID: %d" % sid)
		2: # Editar Atributos (Index 2 because of separator)
			_open_admin_edit()

func _open_admin_edit():
	var dialog = ConfirmationDialog.new()
	dialog.title = "Admin: Editar NPC (SID: %d)" % sid
	
	var grid = GridContainer.new()
	grid.columns = 2
	
	var lbl_aggro = Label.new()
	lbl_aggro.text = "Radio Aggro:"
	grid.add_child(lbl_aggro)
	var edit_aggro = SpinBox.new()
	edit_aggro.step = 0.5
	edit_aggro.value = 15.0
	grid.add_child(edit_aggro)
	
	var lbl_speed = Label.new()
	lbl_speed.text = "Velocidad:"
	grid.add_child(lbl_speed)
	var edit_speed = SpinBox.new()
	edit_speed.step = 0.1
	edit_speed.value = 4.5
	grid.add_child(edit_speed)
	
	dialog.add_child(grid)
	dialog.confirmed.connect(func():
		NetworkManager.send_admin_edit_npc(sid, edit_aggro.value, 2.0, edit_speed.value, 5.0)
	)
	
	add_child(dialog)
	dialog.popup_centered(Vector2(300, 200))

func _on_target_changed(new_sid: int):
	var meshes = find_children("*", "MeshInstance3D", true, false)
	if meshes.size() == 0: return
	var mesh = meshes[0]
		# print("[NetworkPlayer] NO MESH FOUND FOR SID: ", sid)
	
	# print("[NetworkPlayer] Target changed. New SID: ", new_sid, " My SID: ", sid)
	
	if new_sid != 0 and new_sid == sid:
		var mat = mesh.material_override
		if !mat: mat = mesh.get_surface_override_material(0)
		if !mat: mat = mesh.get_active_material(0)
		
		if mat: mat = mat.duplicate()
		else: mat = StandardMaterial3D.new()
		
		if mesh.material_override: mesh.material_override = mat
		else: mesh.set_surface_override_material(0, mat)
		
		var outline_color = Color.YELLOW
		var is_npc = (sid & 0x80000000) != 0
		if is_npc: 
			outline_color = Color.RED
			if npc_indicator_instance: npc_indicator_instance.visible = true
		
		var outline_mat = StandardMaterial3D.new()
		outline_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		outline_mat.albedo_color = outline_color
		outline_mat.cull_mode = BaseMaterial3D.CULL_FRONT
		outline_mat.grow = true
		outline_mat.grow_amount = 0.05
		mat.next_pass = outline_mat
	else:
		if mesh.material_override: mesh.material_override.next_pass = null
		mesh.set_surface_override_material(0, null)
		if npc_indicator_instance: npc_indicator_instance.visible = false

func setup_attributes(aggro: float, attack: float, p_max_hp: float):
	max_hp = p_max_hp
	if npc_indicator_instance:
		npc_indicator_instance.setup(aggro, attack)

func update_attributes(aggro: float, attack: float, _speed: float, p_max_hp: float):
	max_hp = p_max_hp
	if npc_indicator_instance:
		# Use Tweens for smooth visual feedback of radius changes
		var t = create_tween().set_parallel(true)
		# Assuming NpcIndicator has methods to set these or we access them.
		# For now, we'll just call setup again, but ideally we'd tween.
		# If NpcIndicator is a scene with meshes, we'd tween their scale.
		npc_indicator_instance.setup(aggro, attack)
		
		# Pulse effect to show attributes changed
		var pulse_tween = create_tween()
		pulse_tween.tween_property(npc_indicator_instance, "scale", Vector3(1.1, 1.1, 1.1), 0.1).from(Vector3.ONE)
		pulse_tween.tween_property(npc_indicator_instance, "scale", Vector3.ONE, 0.1).set_delay(0.1)



func _process(_delta):
	var current_time = Time.get_ticks_msec() / 1000.0
	var render_time = current_time - interpolation_delay
	
	if state_buffer.size() < 2:
		# Not enough data yet, stay at the latest known or initial
		if state_buffer.size() == 1:
			_safe_set_pos(state_buffer[0]["p"])
		return

	# Remove old states that are no longer useful for interpolation
	# We keep at least 2 states so we can always interpolate or extrapolate from the last segment
	while state_buffer.size() > 2 and state_buffer[1]["t"] < render_time:
		state_buffer.pop_front()

	var s0 = state_buffer[0]
	var s1 = state_buffer[1]
	
	if render_time < s0["t"]:
		# We are ahead of our buffer (packets arriving late or rendering too early)
		_safe_set_pos(s0["p"])
	elif render_time < s1["t"]:
		# --- INTERPOLATION ---
		var time_diff = s1["t"] - s0["t"]
		if time_diff > 0.0001:
			var interpolation_factor = clamp((render_time - s0["t"]) / time_diff, 0.0, 1.0)
			_safe_set_pos(s0["p"].lerp(s1["p"], interpolation_factor))
			last_velocity = (s1["p"] - s0["p"]) / time_diff
		else:
			_safe_set_pos(s1["p"])
	else:
		# --- EXTRAPOLATION ---
		# We ran out of buffer!
		var time_past = render_time - s1["t"]
		# Only extrapolate if there's meaningful movement (avoids micro-shaking when still)
		if time_past < extrapolation_limit and last_velocity.length_squared() > 0.01:
			var predicted_pos = s1["p"] + (last_velocity * time_past)
			_safe_set_pos(predicted_pos)
		else:
			_safe_set_pos(s1["p"])

func _safe_set_pos(new_pos: Vector3):
	if new_pos.is_finite():
		position = new_pos
	else:
		push_error("NetworkPlayer: Attempted to set non-finite position! Check network data or velocity.")

func update_nameplate(p_name: String, p_sid: int):
	sid = p_sid
	$Nameplate.text = "%s (SID: %d)" % [p_name, sid]

func add_state(pos: Vector3):
	if not pos.is_finite():
		push_error("NetworkPlayer: Received non-finite position from network.")
		return
	
	var now = Time.get_ticks_msec() / 1000.0
	
	# --- Perfect Timestamp Reconstruction ---
	# The server sends packets at exactly 20Hz (50ms intervals).
	# Network jitter makes them arrive at unpredictable times.
	# We reconstruct the perfect server timeline to guarantee smooth interpolation.
	
	if current_server_time < 0.0 or state_buffer.is_empty():
		current_server_time = now
	else:
		# Advance by exactly 1 server tick (50ms)
		current_server_time += 0.05 
		
		# Prevent infinite clock drift between client and server
		var time_diff = now - current_server_time
		if abs(time_diff) > 0.25: # Hard reset if we drift by more than 250ms (huge lag spike)
			current_server_time = now
		else:
			# Softly pull the virtual clock towards real arrival time to maintain sync
			current_server_time = lerp(current_server_time, now, 0.1)
	
	state_buffer.append({"t": current_server_time, "p": pos})
	
	if state_buffer.size() > 20: 
		state_buffer.pop_front()

func update_hp(new_hp_percent: float, _source_id: int, source_pos: Vector3):
	var old_hp = hp_percent
	hp_percent = new_hp_percent
	
	if not _hp_initialized:
		_hp_initialized = true
		if world_hp_bar_instance: world_hp_bar_instance.update_hp(new_hp_percent)
		return
	
	# 1. Update World HP Bar with Effects
	if world_hp_bar_instance:
		world_hp_bar_instance.update_hp(new_hp_percent)
		
	# Hide dead characters so they don't overlap with Death Echoes
	var was_dead = !visible or old_hp <= 0
	visible = new_hp_percent > 0
	if new_hp_percent <= 0:
		if TargetManager.current_target_sid == sid:
			TargetManager.clear_target()
		var area = get_node_or_null("Area3D")
		if area: 
			area.monitoring = false
			area.monitorable = false
	else:
		var area = get_node_or_null("Area3D")
		if area: 
			area.monitoring = true
			area.monitorable = true
		if was_dead:
			# Revived! Reset interpolation buffer so it immediately snaps to spawn position
			state_buffer.clear()
			current_server_time = -1.0
			last_velocity = Vector3.ZERO
	
	# 2. Hit Flash (Mesh) - only when taking damage
	if new_hp_percent < old_hp:
		var mesh = get_node_or_null("MeshInstance3D")
		if mesh:
			var mat = mesh.get_surface_override_material(0)
			if mat == null:
				mat = StandardMaterial3D.new()
				mesh.set_surface_override_material(0, mat)
			
			var orig_color = mat.albedo_color
			var flash_tween = create_tween()
			flash_tween.tween_property(mat, "albedo_color", Color.RED, 0.05)
			flash_tween.tween_property(mat, "albedo_color", orig_color, 0.1).set_delay(0.05)
			
			# 3. Knockback
			if source_pos != Vector3.ZERO:
				var knock_dir = (global_position - source_pos).normalized()
				knock_dir.y = 0
				mesh.position += knock_dir * 0.3
				var mesh_tween = create_tween()
				mesh_tween.tween_property(mesh, "position", Vector3.ZERO, 0.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
