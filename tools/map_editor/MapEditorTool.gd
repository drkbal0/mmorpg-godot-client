@tool
extends Node3D
class_name MapEditorTool

## MapEditorTool.gd - Visual in-engine World Builder and Map Topography Editor
## Synchronizes declarative JSON zone topography (colliders, spawners, extraction portals)
## between Godot 4 visual scenes and authoritative Rust ECS SpatialGrid.

@export_file("*.json") var map_file_path: String = "res://assets/maps/map_zone_overworld.json"
@export var grid_snap_size: float = 1.0
@export var auto_reload: bool = false:
	set(v):
		if v:
			load_map(map_file_path)

@export_group("Actions")
@export var reload_button: bool = false:
	set(_v):
		load_map(map_file_path)

@export var export_button: bool = false:
	set(_v):
		export_map(map_file_path)

var current_map_data: Dictionary = {}
var colliders_root: Node3D
var spawners_root: Node3D
var portals_root: Node3D

func _ready() -> void:
	_setup_hierarchy()
	if not map_file_path.is_empty():
		load_map(map_file_path)

func _setup_hierarchy() -> void:
	colliders_root = get_node_or_null("Colliders")
	if not colliders_root:
		colliders_root = Node3D.new()
		colliders_root.name = "Colliders"
		add_child(colliders_root)

	spawners_root = get_node_or_null("Spawners")
	if not spawners_root:
		spawners_root = Node3D.new()
		spawners_root.name = "Spawners"
		add_child(spawners_root)

	portals_root = get_node_or_null("ExtractionPortals")
	if not portals_root:
		portals_root = Node3D.new()
		portals_root.name = "ExtractionPortals"
		add_child(portals_root)

func load_map(path: String) -> bool:
	_setup_hierarchy()
	if not FileAccess.file_exists(path):
		push_warning("MapEditorTool: File does not exist: %s" % path)
		return false

	var f = FileAccess.open(path, FileAccess.READ)
	if not f:
		push_error("MapEditorTool: Could not open file: %s" % path)
		return false

	var text = f.get_as_text()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("MapEditorTool: Invalid JSON map format in %s" % path)
		return false

	current_map_data = parsed
	_clear_visuals()
	_build_visuals()
	print("MapEditorTool: Successfully loaded zone %s (ID: %s) with %d colliders, %d spawners, %d portals." % [
		current_map_data.get("zone_name", "Unknown"),
		str(current_map_data.get("zone_id", 0)),
		current_map_data.get("static_colliders", []).size(),
		current_map_data.get("spawners", []).size(),
		current_map_data.get("extraction_portals", []).size()
	])
	return true

func _clear_visuals() -> void:
	for root in [colliders_root, spawners_root, portals_root]:
		if is_instance_valid(root):
			for child in root.get_children():
				child.queue_free()

func _build_visuals() -> void:
	# 1. Static Colliders
	var colliders = current_map_data.get("static_colliders", [])
	for col in colliders:
		_create_collider_node(col)

	# 2. Spawners
	var spawners = current_map_data.get("spawners", [])
	for sp in spawners:
		_create_spawner_node(sp)

	# 3. Extraction Portals
	var portals = current_map_data.get("extraction_portals", [])
	for p in portals:
		_create_portal_node(p)

func _create_collider_node(col_data: Dictionary) -> void:
	var id_name = col_data.get("id", "collider")
	var pos_arr = col_data.get("pos", [0.0, 0.0, 0.0])
	var size_arr = col_data.get("size", [2.0, 2.0, 2.0])
	var yaw = col_data.get("yaw", 0.0)

	var node = StaticBody3D.new()
	node.name = id_name
	node.position = Vector3(pos_arr[0], pos_arr[1], pos_arr[2])
	node.rotation.y = yaw

	var col_shape = CollisionShape3D.new()
	var box_shape = BoxShape3D.new()
	box_shape.size = Vector3(size_arr[0], size_arr[1], size_arr[2])
	col_shape.shape = box_shape
	node.add_child(col_shape)

	var mesh_inst = MeshInstance3D.new()
	var box_mesh = BoxMesh.new()
	box_mesh.size = box_shape.size
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.45, 0.65, 0.85)
	mat.roughness = 0.7
	mesh_inst.mesh = box_mesh
	mesh_inst.material_override = mat
	node.add_child(mesh_inst)

	colliders_root.add_child(node)

func _create_spawner_node(sp_data: Dictionary) -> void:
	var id_name = sp_data.get("id", "spawner")
	var archetype = sp_data.get("archetype", "Mob")
	var pos_arr = sp_data.get("pos", [0.0, 0.0, 0.0])
	var radius = sp_data.get("radius", 5.0)

	var node = Node3D.new()
	node.name = id_name
	node.position = Vector3(pos_arr[0], pos_arr[1], pos_arr[2])

	# Visual indicator: Cylinder ring
	var mesh_inst = MeshInstance3D.new()
	var cyl_mesh = CylinderMesh.new()
	cyl_mesh.top_radius = radius
	cyl_mesh.bottom_radius = radius
	cyl_mesh.height = 0.1
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.2, 0.2, 0.35)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_inst.mesh = cyl_mesh
	mesh_inst.material_override = mat
	node.add_child(mesh_inst)

	var marker = Label3D.new()
	marker.text = "[SPAWNER: %s]\nRadius: %.1fm" % [archetype, radius]
	marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	marker.position.y = 1.5
	marker.modulate = Color(1.0, 0.4, 0.4)
	node.add_child(marker)

	spawners_root.add_child(node)

func _create_portal_node(portal_data: Dictionary) -> void:
	var id_name = portal_data.get("id", "portal")
	var dest_zone = portal_data.get("dest_zone", 2)
	var pos_arr = portal_data.get("pos", [0.0, 0.0, 0.0])
	var radius = portal_data.get("radius", 3.5)

	var node = Node3D.new()
	node.name = id_name
	node.position = Vector3(pos_arr[0], pos_arr[1], pos_arr[2])

	var mesh_inst = MeshInstance3D.new()
	var torus_mesh = TorusMesh.new()
	torus_mesh.inner_radius = radius - 0.2
	torus_mesh.outer_radius = radius
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.0, 0.8, 1.0, 0.9)
	mat.emission_enabled = true
	mat.emission = Color(0.0, 0.8, 1.0)
	mat.emission_energy_multiplier = 2.0
	mesh_inst.mesh = torus_mesh
	mesh_inst.material_override = mat
	node.add_child(mesh_inst)

	var marker = Label3D.new()
	marker.text = "⚡ EXTRACTION PORTAL\nDest Zone: %d (Radius: %.1fm)" % [dest_zone, radius]
	marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	marker.position.y = 2.0
	marker.modulate = Color(0.2, 1.0, 1.0)
	node.add_child(marker)

	portals_root.add_child(node)

func snap_to_grid(pos: Vector3) -> Vector3:
	if grid_snap_size <= 0.0:
		return pos
	return Vector3(
		snappedf(pos.x, grid_snap_size),
		snappedf(pos.y, grid_snap_size),
		snappedf(pos.z, grid_snap_size)
	)

func export_map(path: String) -> bool:
	_setup_hierarchy()
	var out_data = current_map_data.duplicate(true)
	if out_data.is_empty():
		out_data["zone_id"] = 1
		out_data["zone_name"] = "Exported_Zone"
		out_data["bounds"] = {"min_x": -250.0, "max_x": 250.0, "min_z": -250.0, "max_z": 250.0}

	# Serialize colliders from tree
	var col_list: Array = []
	for child in colliders_root.get_children():
		if child is StaticBody3D:
			var box_shape: BoxShape3D
			for sub in child.get_children():
				if sub is CollisionShape3D and sub.shape is BoxShape3D:
					box_shape = sub.shape
					break
			var sz = [2.0, 2.0, 2.0]
			if box_shape:
				sz = [box_shape.size.x, box_shape.size.y, box_shape.size.z]
			col_list.append({
				"id": child.name,
				"type": "box",
				"pos": [child.position.x, child.position.y, child.position.z],
				"size": sz,
				"yaw": child.rotation.y
			})
	out_data["static_colliders"] = col_list

	var f = FileAccess.open(path, FileAccess.WRITE)
	if not f:
		push_error("MapEditorTool: Could not open file for writing: %s" % path)
		return false

	var json_str = JSON.stringify(out_data, "\t")
	f.store_string(json_str)
	print("MapEditorTool: Successfully exported %s with %d colliders." % [path, col_list.size()])
	return true
