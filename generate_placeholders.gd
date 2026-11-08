extends SceneTree

func _init():
	print("Generating 3D Placeholders...")
	
	# Create directories if they don't exist
	var dir = DirAccess.open("res://")
	dir.make_dir_recursive("res://assets/placeholders")
	dir.make_dir_recursive("res://assets/placeholders/environment")
	dir.make_dir_recursive("res://assets/placeholders/characters")
	
	# 1. Ground Grass
	var ground = CSGBox3D.new()
	ground.name = "GroundGrass"
	ground.size = Vector3(10, 0.1, 10)
	ground.use_collision = true
	ground.collision_layer = 1
	var mat_grass = StandardMaterial3D.new()
	mat_grass.albedo_color = Color(0.2, 0.6, 0.2)
	ground.material = mat_grass
	save_scene(ground, "res://assets/placeholders/environment/tile_ground_grass.tscn")
	
	# 2. Pine Tree
	var tree = Node3D.new()
	tree.name = "PineTree"
	var trunk = CSGCylinder3D.new()
	trunk.radius = 0.4
	trunk.height = 2.0
	trunk.position.y = 1.0
	var mat_wood = StandardMaterial3D.new()
	mat_wood.albedo_color = Color(0.4, 0.2, 0.1)
	trunk.material = mat_wood
	var leaves = CSGCylinder3D.new()
	leaves.cone = true
	leaves.radius = 1.5
	leaves.height = 3.0
	leaves.position.y = 2.5
	leaves.material = mat_grass
	tree.add_child(trunk)
	trunk.owner = tree
	tree.add_child(leaves)
	leaves.owner = tree
	
	# Static Body for tree
	var tree_body = StaticBody3D.new()
	var tree_shape = CollisionShape3D.new()
	var cyl_shape = CylinderShape3D.new()
	cyl_shape.radius = 0.4
	cyl_shape.height = 2.0
	tree_shape.shape = cyl_shape
	tree_shape.position.y = 1.0
	tree_body.add_child(tree_shape)
	tree.add_child(tree_body)
	tree_body.owner = tree
	tree_shape.owner = tree
	
	save_scene(tree, "res://assets/placeholders/environment/prop_tree_pine_01.tscn")
	
	# 3. Large Rock
	var rock = CSGSphere3D.new()
	rock.name = "LargeRock"
	rock.radius = 1.5
	rock.radial_segments = 8
	rock.rings = 6
	rock.use_collision = true
	var mat_rock = StandardMaterial3D.new()
	mat_rock.albedo_color = Color(0.5, 0.5, 0.5)
	rock.material = mat_rock
	save_scene(rock, "res://assets/placeholders/environment/prop_rock_large.tscn")
	
	print("Done generating placeholders!")
	quit()

func save_scene(node: Node, path: String):
	var packed = PackedScene.new()
	packed.pack(node)
	ResourceSaver.save(packed, path)
