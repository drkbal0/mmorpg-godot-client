extends CanvasLayer

## ScreenSpaceManager.gd - Next-Gen Screen-Space 2D Projection Engine
## Projects high-resolution 2D widgets (Nameplates, Segmented HP bars, Loot Labels)
## onto CanvasLayer (Z=50) using camera.unproject_position().
## Eliminates SubViewport overhead, perspective blur, and Label3D pixelation.

static var instance: CanvasLayer = null

var tracked_targets: Dictionary = {} # Node3D -> Dictionary {control, offset, max_distance}
var _cached_cam: Camera3D = null
var _frame_counter: int = 0

func _init() -> void:
	layer = 50
	if instance == null:
		instance = self

func _ready() -> void:
	if instance == null:
		instance = self

func _exit_tree() -> void:
	if instance == self:
		instance = null

## Registers a 3D node to have an attached Screen-Space 2D control
func register_target(target: Node3D, control: Control, offset: Vector3 = Vector3(0, 2.2, 0), max_dist: float = 45.0) -> void:
	if not is_instance_valid(target) or not is_instance_valid(control):
		return
	
	if control.get_parent() != self:
		add_child(control)
		
	control.visible = false
	tracked_targets[target] = {
		"control": control,
		"offset": offset,
		"max_dist": max_dist
	}

## Unregisters and optionally frees the projected control
func unregister_target(target: Node3D, free_control: bool = true) -> void:
	if tracked_targets.has(target):
		var entry = tracked_targets[target]
		var ctrl = entry.get("control")
		tracked_targets.erase(target)
		if free_control and is_instance_valid(ctrl):
			ctrl.queue_free()

func has_target(target: Node3D) -> bool:
	return tracked_targets.has(target)

func get_control_for_target(target: Node3D) -> Control:
	if tracked_targets.has(target):
		return tracked_targets[target].get("control")
	return null

func _process(_delta: float) -> void:
	if tracked_targets.is_empty():
		return

	# Cache camera reference, update occasionally or if null
	_frame_counter += 1
	if _cached_cam == null or _frame_counter % 30 == 0 or not is_instance_valid(_cached_cam) or not _cached_cam.current:
		var vp = get_viewport()
		if vp:
			_cached_cam = vp.get_camera_3d()

	if _cached_cam == null or not is_instance_valid(_cached_cam):
		return

	var cam_pos = _cached_cam.global_position
	var dead_targets: Array = []

	for target in tracked_targets.keys():
		if not is_instance_valid(target):
			dead_targets.append(target)
			continue

		var entry = tracked_targets[target]
		var ctrl: Control = entry["control"]
		if not is_instance_valid(ctrl):
			dead_targets.append(target)
			continue

		var world_pos: Vector3 = target.global_position + entry["offset"]

		# 1. Frustum Check (Behind Camera)
		if _cached_cam.is_position_behind(world_pos):
			if ctrl.visible:
				ctrl.visible = false
			continue

		# 2. Max Distance Check
		var dist_sq = cam_pos.distance_squared_to(world_pos)
		var max_d: float = entry["max_dist"]
		if dist_sq > max_d * max_d:
			if ctrl.visible:
				ctrl.visible = false
			continue

		var dist = sqrt(dist_sq)

		# 3. 2D Screen Projection
		var screen_pos = _cached_cam.unproject_position(world_pos)

		# 4. Subtle distance scaling for visual depth without pixelation
		var scale_factor = clampf(1.0 - (dist / max_d) * 0.3, 0.7, 1.0)
		ctrl.scale = Vector2(scale_factor, scale_factor)

		# Center control horizontally and anchor bottom
		var effective_size = ctrl.size * scale_factor
		ctrl.position = Vector2(
			screen_pos.x - effective_size.x * 0.5,
			screen_pos.y - effective_size.y
		)

		# 5. Dynamic Z-Index for proper overlapping depth
		ctrl.z_index = clampi(int(900.0 - dist), 0, 999)

		if not ctrl.visible:
			ctrl.visible = true

	# Clean up any despawned targets
	for dead in dead_targets:
		unregister_target(dead, true)
