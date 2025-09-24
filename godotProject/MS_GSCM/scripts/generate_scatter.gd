extends Node3D

@export var density := 2.0  # 每平方米多少个散射体

var total_scatter_points := 0

func _ready():
	print("🟢 Scatter Generator Ready!")

	var buildings_parent = get_node("map_4_osm_buildings")
	if buildings_parent:
		print("✅ 找到 map_4_osm_buildings，子节点数量: ", buildings_parent.get_child_count())
		for child in buildings_parent.get_children():
			print("  🔎 检查子节点: ", child.name)
			if child is MeshInstance3D:
				print("    ✅ 是 MeshInstance3D")
				if child.has_meta("material_type"):
					print("    ✅ 有 material_type")
					process_building(child)
				else:
					print("    ⚠️ 没有 material_type")
	else:
		push_error("❌ 未找到 map_4_osm_buildings 节点")
		return

func process_building(mesh_instance):
	print("➡️ 开始处理建筑: ", mesh_instance.name)
	print("Processing building: ", mesh_instance.name)
	var material_string = mesh_instance.get_meta("material_type")

	if mesh_instance.mesh is ArrayMesh:
		for surface in range(mesh_instance.mesh.get_surface_count()):
			var arrays = mesh_instance.mesh.surface_get_arrays(surface)
			var vertices = arrays[Mesh.ARRAY_VERTEX]
			var indices = arrays[Mesh.ARRAY_INDEX]

			for i in range(0, indices.size(), 6):
				var quad_vertices = []
				quad_vertices.append(vertices[indices[i]])
				quad_vertices.append(vertices[indices[i + 1]])
				quad_vertices.append(vertices[indices[i + 2]])
				quad_vertices.append(vertices[indices[i + 5]])

				generate_scatter_band(quad_vertices, mesh_instance, material_string)
				print("  ✅ 面处理完成")

func generate_scatter_band(quad_vertices, parent_node, material_string):
	var scatter_mesh = BoxMesh.new()
	scatter_mesh.size = Vector3(0.05, 0.05, 0.05)
	var area_center_y = 1.5
	var band_half_height = 0.75

	var plane = Plane(quad_vertices[0], quad_vertices[1], quad_vertices[2])
	var normal = plane.normal
	print("  🔍 法线: ", normal)
	if abs(normal.y) > 0.1:
		return  # 忽略非竖直面

	var area1 = 0.5 * ((quad_vertices[1] - quad_vertices[0]).cross(quad_vertices[2] - quad_vertices[0])).length()
	var area2 = 0.5 * ((quad_vertices[2] - quad_vertices[0]).cross(quad_vertices[3] - quad_vertices[0])).length()

	var total_area = area1 + area2

	print("  🔸 面积: ", total_area, ", 生成点数: ", int(total_area * density))
	var total_points = int(total_area * density)

	for j in range(total_points):
		var p = sample_point_in_quad(quad_vertices[0], quad_vertices[1], quad_vertices[2], quad_vertices[3])
		if abs(p.y - area_center_y) > band_half_height:
			continue

		var scatter_instance = MeshInstance3D.new()
		scatter_instance.mesh = scatter_mesh
		scatter_instance.translation = p
		scatter_instance.set_meta("material_type", material_string)
		scatter_instance.owner = get_tree().edited_scene_root
		parent_node.add_child(scatter_instance)
		total_scatter_points += 1
		print("    📦 散射体添加于: ", p)

func _exit_tree():
	print("
🧾 统计完成 ✅
--------------------------")
	print("✅ 总共生成散射体点数量: ", total_scatter_points)
	print("--------------------------")

func sample_point_in_quad(a, b, c, d) -> Vector3:
	var u = randf()
	var v = randf()
	var ab = a.linear_interpolate(b, u)
	var dc = d.linear_interpolate(c, u)
	return ab.linear_interpolate(dc, v)
