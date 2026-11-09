extends CharacterBody3D
# Fix V7.1: Corrected viewport names and type hints for SubViewport compatibility.

enum CameraMode { TOP_DOWN, THIRD_PERSON }

@export var camera_mode: CameraMode = CameraMode.TOP_DOWN
@onready var network = NetworkManager
@onready var camera = $Camera3D

var last_sent_pos = Vector3.ZERO
var send_timer = 0.0
const SEND_RATE = 1.0 / 20.0 

const world_hp_bar_scene = preload("res://ui/components/WorldHPBar/WorldHPBar.tscn")
const player_hud_scene = preload("res://ui/components/PlayerHUD/PlayerHUD.tscn")
const screen_space_nameplate_scene = preload("res://ui/screenspace/WorldNameplate.tscn")

var player_hud_instance : Node
var world_hp_bar_instance : Node3D
var screenspace_nameplate_instance : Control = null

var hp_percent : float = 100.0
var max_hp : float = 1000.0 # Standard default
var _hp_initialized : bool = false

const SPEED = 5.0
const SPRINT_MULTIPLIER = 1.5
const JUMP_VELOCITY = 6.0
const DASH_SPEED = 15.0
var dash_timer = 0.0
var dash_duration = 0.0

# Third person variables
var mouse_sensitivity = 0.002
var is_dead = false
@onready var death_overlay = get_node_or_null("DeathOverlay")
var crosshair_layer: CanvasLayer = null

func _on_position_corrected(new_pos: Vector3):
	var dist = position.distance_to(new_pos)
	if dist > 1.5:
		position = new_pos
		velocity = Vector3.ZERO
		last_sent_pos = new_pos
	elif dist > 0.05:
		position = position.lerp(new_pos, 0.5)
		last_sent_pos = position

var is_crouching: bool = false
var crouch_factor: float = 0.0
var hitbox_debug_meshes: Array[MeshInstance3D] = []
var hitbox_debug_visible: bool = false

var head_shape_node: CollisionShape3D = null
var chest_shape_node: CollisionShape3D = null
var hips_shape_node: CollisionShape3D = null
var limbs_shape_node: CollisionShape3D = null

func _ready():
	randomize()
	add_to_group("hitbox_debug")
	# Set Nameplate from AuthManager
	if has_node("Nameplate"):
		var nameplate = $Nameplate as Label3D
		if AuthManager.selected_character_name != "":
			nameplate.text = AuthManager.selected_character_name
		elif AuthManager.username != "":
			nameplate.text = AuthManager.username
		nameplate.no_depth_test = true
		nameplate.render_priority = 30
		nameplate.outline_size = 18
		nameplate.outline_modulate = Color.BLACK
		nameplate.font_size = 54
		nameplate.pixel_size = 0.009
		nameplate.shaded = false
	
	if AuthManager.last_pos != Vector3(-999, -999, -999):
		position = AuthManager.last_pos
		if position == Vector3.ZERO: position.y = 1.0 
	else:
		position = Vector3(randf_range(-5.0, 5.0), 1.0, randf_range(-5.0, 5.0))
		
	setup_camera()
	_setup_crosshair()
	last_sent_pos = position
	send_position()
	if network: network.player_position_corrected.connect(_on_position_corrected)
	
	add_to_group("player")
	_setup_hud()
	
	world_hp_bar_instance = world_hp_bar_scene.instantiate()
	add_child(world_hp_bar_instance)
	world_hp_bar_instance.setup(Color.GREEN)
	
	# Next-Gen Screen-Space 2D Nameplate & 100 HP Segmented Bar
	if has_node("/root/ScreenSpaceManager"):
		screenspace_nameplate_instance = screen_space_nameplate_scene.instantiate()
		var p_name = AuthManager.selected_character_name if not AuthManager.selected_character_name.is_empty() else AuthManager.username
		if p_name.is_empty(): p_name = "Campeón"
		screenspace_nameplate_instance.setup(p_name, 1000.0, 1000.0, false, "‹ PIONERO ›", 18)
		ScreenSpaceManager.register_target(self, screenspace_nameplate_instance, Vector3(0, 2.3, 0))
		if has_node("Nameplate"):
			$Nameplate.visible = false
		if world_hp_bar_instance:
			world_hp_bar_instance.visible = false
	
	_ensure_collision()

func _ensure_collision():
	var area = get_node_or_null("Area3D")
	if !area:
		area = Area3D.new()
		area.name = "Area3D"
		add_child(area)
	
	# Clear old single box shape if present
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

func _setup_hud():
	# Request via Orchestrator to ensure registry tracking
	player_hud_instance = UIOrchestrator.open_window("player_hud")
	if player_hud_instance:
		player_hud_instance.setup($Nameplate.text, hp_percent)

func setup_camera():
	var hp_bar_node = null
	if world_hp_bar_instance: hp_bar_node = world_hp_bar_instance.get_node_or_null("Sprite3D")
	var namep = get_node_or_null("Nameplate")
	if camera_mode == CameraMode.TOP_DOWN:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		camera.top_level = true
		camera.position = position + Vector3(0, 10, 10)
		camera.rotation_degrees = Vector3(-45, 0, 0)
	else:
		camera.top_level = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		camera.position = Vector3(0, 2.5, 4.0)
		camera.rotation_degrees = Vector3(-15, 0, 0)
	
	if crosshair_layer:
		crosshair_layer.visible = (camera_mode == CameraMode.THIRD_PERSON)

func _setup_crosshair():
	if crosshair_layer: return
	crosshair_layer = CanvasLayer.new()
	crosshair_layer.name = "CrosshairLayer"
	crosshair_layer.layer = 15
	
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Reticle center dot
	var dot = ColorRect.new()
	dot.custom_minimum_size = Vector2(4, 4)
	dot.color = Color(0.2, 0.9, 1.0, 0.9) # Cyan glow reticle
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(dot)
	
	crosshair_layer.add_child(center)
	add_child(crosshair_layer)
	crosshair_layer.visible = (camera_mode == CameraMode.THIRD_PERSON)

func toggle_camera_mode():
	if camera_mode == CameraMode.TOP_DOWN:
		camera_mode = CameraMode.THIRD_PERSON
	else:
		camera_mode = CameraMode.TOP_DOWN
	setup_camera()
	print("[Player] Camera mode toggled to: ", camera_mode)

func _input(event):
	if is_dead: return # Block input on death
	if event is InputEventKey and event.is_echo(): return # Ignore key repeat echo

	# Cast Skill 3 (Hitscan Shot) on Primary Attack
	if event.is_action_pressed("attack_primary"):
		if not UIOrchestrator.is_mouse_over_ui():
			_cast_skill(3)

	# Cast Skill 1 (Fireball)
	if event.is_action_pressed("cast_spell_1"):
		if not UIOrchestrator.is_mouse_over_ui():
			_cast_skill(1)

	# Cast Skill 4 (Defensive Barrier)
	if event.is_action_pressed("cast_spell_2"):
		if not UIOrchestrator.is_mouse_over_ui():
			_cast_skill(4)

	# Cast Skill 5 (Meteor Strike)
	if event.is_action_pressed("cast_ultimate"):
		if not UIOrchestrator.is_mouse_over_ui():
			_cast_skill(5)

	# Dash / Evade
	if event.is_action_pressed("dash_evade"):
		_trigger_dash()

	# Contextual Interact
	if event.is_action_pressed("interact"):
		if not UIOrchestrator.is_mouse_over_ui():
			_try_interact()
		
	if event is InputEventMouseMotion and camera_mode == CameraMode.THIRD_PERSON:
		rotate_y(-event.relative.x * mouse_sensitivity)
		camera.rotate_x(-event.relative.y * mouse_sensitivity)
		camera.rotation.x = clamp(camera.rotation.x, -PI/3, PI/3)

func _trigger_dash():
	if SpellManager and not SpellManager.is_ready(2):
		return
	if dash_timer <= 0.0:
		if SpellManager:
			SpellManager.trigger_cooldown(2)
		dash_timer = 2.0 # Cooldown
		dash_duration = 0.25
		
		# Compute dash direction
		var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		if input_dir.is_zero_approx():
			input_dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
		var dash_dir = Vector3.ZERO
		if input_dir.length_squared() > 0.01:
			if camera_mode == CameraMode.TOP_DOWN:
				dash_dir = Vector3(input_dir.x, 0, input_dir.y).normalized()
			else:
				dash_dir = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
		else:
			var ground_cursor = get_ground_cursor_position()
			var to_cursor = ground_cursor - global_position
			to_cursor.y = 0.0
			if to_cursor.length_squared() > 1.0:
				dash_dir = to_cursor.normalized()
			else:
				dash_dir = -transform.basis.z
				dash_dir.y = 0.0
				dash_dir = dash_dir.normalized()
		
		var target = global_position + dash_dir * 8.0
		network.send_cast_skill(2, target)
		velocity = dash_dir * DASH_SPEED
		send_position()

func _try_interact():
	var from = global_position + Vector3(0, 1.0, 0)
	var forward = -transform.basis.z if camera_mode == CameraMode.THIRD_PERSON else (get_ground_cursor_position() - global_position).normalized()
	forward.y = 0.0
	if forward.length_squared() < 0.001:
		forward = -transform.basis.z
	forward = forward.normalized()
	
	var to = from + forward * 3.5 # 3.5m reach
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.collision_mask = 48 # Layers 5 & 6 (Targetable / Interactive)
	var result = space_state.intersect_ray(query)
	var interacted = false
	if result and result.collider:
		var target_obj = result.collider
		print("[Player] Interacting with: ", target_obj.name)
		if target_obj.has_method("interact"):
			target_obj.interact(self)
			interacted = true
		elif target_obj.get_parent() and target_obj.get_parent().has_method("interact"):
			target_obj.get_parent().interact(self)
			interacted = true

	# Fallback: Búsqueda por proximidad esférica de 3.5m si el raycast no impactó directamente
	if not interacted:
		var closest_target = null
		var min_dist = 3.5
		for obj in get_tree().get_nodes_in_group("interactable"):
			if is_instance_valid(obj) and obj.has_method("interact"):
				var d = global_position.distance_to(obj.global_position)
				if d <= min_dist:
					min_dist = d
					closest_target = obj
		if closest_target:
			print("[Player] Proximity interacting with: ", closest_target.name)
			closest_target.interact(self)

func _physics_process(delta):
	if is_dead: 
		velocity = Vector3.ZERO
		move_and_slide()
		return

	# Add Gravity
	if not is_on_floor():
		velocity.y -= 9.8 * delta
		
	if (Input.is_action_just_pressed("jump") or Input.is_action_just_pressed("ui_accept")) and is_on_floor():
		velocity.y = JUMP_VELOCITY
		
	if camera_mode == CameraMode.TOP_DOWN:
		var target_cam_pos = position + Vector3(0, 10, 10)
		camera.position = camera.position.lerp(target_cam_pos, delta * 5.0)
	
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if input_dir.is_zero_approx():
		input_dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var direction = Vector3.ZERO
	if camera_mode == CameraMode.TOP_DOWN:
		direction = Vector3(input_dir.x, 0, input_dir.y).normalized()
		if not UIOrchestrator.is_mouse_over_ui():
			look_at_cursor()
	else:
		direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	if dash_timer > 0.0:
		dash_timer -= delta
		
	if dash_duration > 0.0:
		dash_duration -= delta

	# Crouch handling via authoritative InputMap action
	var wants_crouch = Input.is_action_pressed("crouch")
	is_crouching = wants_crouch
	var target_factor = 1.0 if is_crouching else 0.0
	crouch_factor = lerp(crouch_factor, target_factor, delta * 12.0)

	# Adjust anatomical hitboxes during crouch
	if head_shape_node:
		head_shape_node.position.y = lerp(1.60, 0.85, crouch_factor)
	if chest_shape_node:
		chest_shape_node.position.y = lerp(1.15, 0.55, crouch_factor)
	if hips_shape_node:
		hips_shape_node.position.y = lerp(0.75, 0.35, crouch_factor)
	if limbs_shape_node:
		limbs_shape_node.position.y = lerp(0.35, 0.18, crouch_factor)

	# Visual crouch squat
	var mesh = get_node_or_null("MeshInstance3D")
	if mesh:
		mesh.scale.y = lerp(1.0, 0.65, crouch_factor)
		mesh.position.y = lerp(0.0, -0.35, crouch_factor)

	var current_speed = SPEED
	if is_crouching:
		current_speed = SPEED * 0.5
	if dash_duration > 0.0:
		current_speed = DASH_SPEED

	if direction:
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
	else:
		velocity.x = move_toward(velocity.x, 0, current_speed)
		velocity.z = move_toward(velocity.z, 0, current_speed)

	move_and_slide()

	send_timer += delta
	if send_timer >= SEND_RATE:
		send_timer = 0.0
		if position.distance_squared_to(last_sent_pos) > 0.001:
			send_position()
			last_sent_pos = position

func look_at_cursor():
	var target = get_ground_cursor_position()
	var look_target = Vector3(target.x, position.y, target.z)
	if look_target.distance_to(position) > 0.1:
		look_at(look_target, Vector3.UP)

func get_ground_cursor_position() -> Vector3:
	var screen_pos = get_viewport().get_visible_rect().size / 2.0 if camera_mode == CameraMode.THIRD_PERSON else get_viewport().get_mouse_position()
	var ray_length = 100.0
	var from = camera.project_ray_origin(screen_pos)
	var dir = camera.project_ray_normal(screen_pos)
	var to = from + dir * ray_length
	
	# Raycast to directly detect targetable entities (Layers 5 & 6)
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.collision_mask = 48 # Layers 5 & 6 (Targetable Entities)
	var result = space_state.intersect_ray(query)
	if result:
		return result.position
		
	# Ground plane intersection (y = 0)
	var denom = dir.y
	if abs(denom) > 0.0001:
		var t = -from.y / denom
		if t > 0.0 and t < ray_length:
			return from + dir * t
			
	return from + dir * 50.0

func _cast_skill(skill_id: int):
	if SpellManager and not SpellManager.is_ready(skill_id):
		return
	if SpellManager:
		SpellManager.trigger_cooldown(skill_id)
	var target = get_ground_cursor_position()
	network.send_cast_skill(skill_id, target)


func send_position():
	network.send_move(position, rotation.y)

func update_hp(new_hp_percent: float, _source_id: int, source_pos: Vector3):
	hp_percent = new_hp_percent
	
	if not _hp_initialized:
		_hp_initialized = true
		if world_hp_bar_instance: world_hp_bar_instance.update_hp(new_hp_percent)
		return
	
	if world_hp_bar_instance: world_hp_bar_instance.update_hp(new_hp_percent)
	if screenspace_nameplate_instance: screenspace_nameplate_instance.update_hp(new_hp_percent * 10.0, 1000.0)
	if player_hud_instance: player_hud_instance.update_hp(new_hp_percent)
	
	if hp_percent <= 0 and not is_dead:
		_on_death(source_pos)
	
	# Hit effects (Flash)
	var mesh = $MeshInstance3D
	var mat = mesh.get_surface_override_material(0)
	if mat == null:
		mat = StandardMaterial3D.new()
		mesh.set_surface_override_material(0, mat)
	
	var flash_tween = create_tween()
	flash_tween.tween_property(mat, "albedo_color", Color.RED, 0.05)
	flash_tween.tween_property(mat, "albedo_color", Color.WHITE, 0.1).set_delay(0.05)
	
	if source_pos != Vector3.ZERO and not is_dead:
		var knock_dir = (global_position - source_pos).normalized()
		knock_dir.y = 0
		mesh.position += knock_dir * 0.3
		var mesh_tween = create_tween()
		mesh_tween.tween_property(mesh, "position", Vector3.ZERO, 0.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _on_death(source_pos: Vector3):
	print("Player: DEATH DETECTED.")
	is_dead = true
	velocity = Vector3.ZERO
	
	# Apply Grey/Dark tint via Overlay
	if death_overlay:
		death_overlay.visible = true
		var t = create_tween()
		t.tween_property(death_overlay.get_node("ColorRect"), "color:a", 0.6, 2.0).from(0.0)
	
	# Close interactive windows (Inventory, Backpacks)
	if UIOrchestrator:
		UIOrchestrator.close_window("inventory")
		# We don't close the HUD yet, to let the player see 0 HP.
		# The cleanup will happen when returning to shelter.
	
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	
	# Visual Knockback on death
	if source_pos != Vector3.ZERO:
		var mesh = $MeshInstance3D
		var knock_dir = (global_position - source_pos).normalized()
		knock_dir.y = 0
		var mesh_tween = create_tween()
		mesh_tween.tween_property(mesh, "position", knock_dir * 0.5, 0.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		mesh_tween.tween_property(mesh, "rotation:x", deg_to_rad(90), 0.5) # Falling down

func _exit_tree() -> void:
	if has_node("/root/ScreenSpaceManager") and ScreenSpaceManager.instance:
		ScreenSpaceManager.instance.unregister_target(self)



