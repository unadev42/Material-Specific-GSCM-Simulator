# ============================================================
# Scatterer Generation Node
#
# This node should be manually placed near a wall surface.
# At runtime, it will automatically attach itself to the nearest wall
# and randomly generate scatterers within a defined area and density.
#
# The material type and surface normal of the wall are stored as meta data
# in each scatterer. These meta data are later used by the ray-tracing process.
# ============================================================

extends Marker3D  
@export var scatter_density_ord1 := 0.2   # Density of first-order scatterers
@export var scatter_density_ord2 := 0.2   # Density of second-order scatterers
@export var scatter_group := "ScatterGroup"   # Group name to which all generated scatterers will belong
@export var ray_length := 10.0            # Length of the probing rays used to detect nearby surfaces
@export var area_size := Vector2(20, 3)   # Size of the local area (width × height) within which scatterers are distributed
@export var environment_mesh: Node3D      # Reference to the environment mesh used for surface detection
var matal_density_factor = 1.0            # Multiplier applied to scatterer density when surface material is metal (which you may further investigate)

var surface_normal = Vector3.ZERO 		  # Initialize the surface normals

func _ready():
	if not environment_mesh:
		print("Error: No environment mesh assigned!")
		return

	var space_state = get_world_3d().direct_space_state

	# Cast rays in four horizontal directions to find the nearest wall
	var directions = [
		Vector3(ray_length, 0, 0),
		Vector3(-ray_length, 0, 0),
		Vector3(0, 0, ray_length),
		Vector3(0, 0, -ray_length)
	]

	var hit_position = Vector3.ZERO
	var hit_normal = Vector3.ZERO
	var hit_collider = null
	var building_name = ""
	var found_surface = false

	for dir in directions:
		var query = PhysicsRayQueryParameters3D.create(
			global_transform.origin, global_transform.origin + dir
		)
		query.collision_mask = 1

		var result = space_state.intersect_ray(query)
		if result and "position" in result and "normal" in result:
			# Attach to detected surface
			hit_position = result["position"]
			hit_normal = result["normal"]
			hit_collider = result["collider"]
			building_name = hit_collider.name if hit_collider else ""
			found_surface = true
			break

	if found_surface:
		surface_normal = hit_normal
		print("Marker3D attached at:", hit_position, "| Normal:", surface_normal, "| Building:", building_name)

		# Determine surface material type
		var mat_type = get_material_type_from_node(hit_collider)
		var density_multiplier = 1.0
		if mat_type == "metal":
			# On metallic surfaces, optionally adjust scatter density
			density_multiplier = matal_density_factor
			#print("Metal surface detected, adjusting scatter density...")

		# Apply density multiplier to scatter densities
		var adjusted_density_ord1 = scatter_density_ord1 * density_multiplier
		var adjusted_density_ord2 = scatter_density_ord2 * density_multiplier

		# Build local coordinate system aligned with surface
		var right = Vector3.ZERO
		var up = Vector3.ZERO

		if abs(surface_normal.y) > 0.99:
			right = Vector3.RIGHT
			up = Vector3.FORWARD
		else:
			right = surface_normal.cross(Vector3.UP).normalized()
			up = right.cross(surface_normal).normalized()

		# ===== Generate first-order scatterers =====
		var total_scatters = int(area_size.x * area_size.y * adjusted_density_ord1)
		print("Generating ", total_scatters, " first order scatter points...")

		for i in range(total_scatters):
			# Randomly offset inside defined area rectangle
			var local_x = randf_range(-area_size.x / 2, area_size.x / 2)
			var local_y = randf_range(-area_size.y / 2, area_size.y / 2)
			var scatter_pos = hit_position + hit_normal * 0.1 + right * local_x + up * local_y

			var scatter = Marker3D.new()
			scatter.global_transform.origin = scatter_pos
			scatter.set_meta("surface_normal", surface_normal)
			scatter.set_meta("order", 1)              # First-order scatterer
			scatter.set_meta("true_pos", scatter_pos) # Absolute position
			scatter.set_meta("building_name", building_name)

			if hit_collider:
				scatter.set_meta("material_type", mat_type)  # Save surface material type

			scatter.add_to_group(scatter_group)
			add_child(scatter)
			create_visual_marker(scatter_pos, Color.RED, scatter)  # Red marker for ord1

		# ===== Generate second-order scatterers =====
		var total_secondary = int(area_size.x * area_size.y * adjusted_density_ord2)
		print("Generating ", total_secondary, " second-order scatter points...")

		for i in range(total_secondary):
			var local_x2 = randf_range(-area_size.x / 2, area_size.x / 2)
			var local_y2 = randf_range(-area_size.y / 2, area_size.y / 2)
			var scatter_pos2 = hit_position + hit_normal * 0.1 + right * local_x2 + up * local_y2

			var scatter2 = Marker3D.new()
			scatter2.global_transform.origin = scatter_pos2
			scatter2.set_meta("surface_normal", surface_normal)
			scatter2.set_meta("order", 2)              # Second-order scatterer
			scatter2.set_meta("true_pos", scatter_pos2)
			scatter2.set_meta("building_name", building_name)

			if hit_collider:
				scatter2.set_meta("material_type", mat_type)

			scatter2.add_to_group(scatter_group)
			add_child(scatter2)
			create_visual_marker(scatter_pos2, Color.YELLOW, scatter2)  # Yellow marker for ord2
	else:
		print("Warning: No surface found for scatter!")


func get_material_type_from_node(node: Node) -> String:
	# Traverse up node hierarchy to identify material group
	var current = node
	while current:
		if current.is_in_group("material_concrete"):
			return "concrete"
		elif current.is_in_group("material_metal"):
			return "metal"
		elif current.is_in_group("material_glass"):
			return "glass"
		current = current.get_parent()
	return "concrete"


func create_visual_marker(pos: Vector3, color: Color, parent: Node):
	# Create a small sphere mesh to visualize scatterer position
	var mesh_instance = MeshInstance3D.new()
	var sphere_mesh = SphereMesh.new()
	sphere_mesh.radius = 0.2
	sphere_mesh.height = 0.2

	mesh_instance.mesh = sphere_mesh
	mesh_instance.transform.origin = parent.to_local(pos)

	var material = StandardMaterial3D.new()
	material.albedo_color = color
	mesh_instance.material_override = material

	parent.add_child(mesh_instance)
