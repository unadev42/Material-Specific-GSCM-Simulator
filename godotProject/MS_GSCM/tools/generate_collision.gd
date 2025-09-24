@tool
extends EditorScript

# ============================================================
# Auto Collision Body Generator
#
# This EditorScript automatically generates StaticBody3D +
# CollisionShape3D nodes for all MeshInstance3D nodes under
# the selected parent nodes (recursively).
#
# - You only need to select the parent node(s) in the SceneTree.
# - The script will traverse all children and grandchildren.
# - If a MeshInstance3D does not already have a collision body,
#   a StaticBody3D named "AutoStaticBody" will be created with
#   a CollisionShape3D named "AutoCollider" based on the mesh.
# - Ownership is assigned so the generated nodes are saved
#   with the scene.
# ============================================================

func _run():
	var selected_nodes = get_editor_interface().get_selection().get_selected_nodes()
	if selected_nodes.is_empty():
		push_error("Select a node！")
		return

	var count = 0
	for node in selected_nodes:
		count += _process_node_recursive(node)

	print("✅ Successfully generate ", count, " collision bodies。")

func _process_node_recursive(node: Node) -> int:
	var added = 0
	if node is MeshInstance3D and not _has_collision(node) and node.mesh:
		var shape = node.mesh.create_trimesh_shape()
		if shape:
			var body = StaticBody3D.new()
			body.name = "AutoStaticBody"

			var collider = CollisionShape3D.new()
			collider.name = "AutoCollider"
			collider.shape = shape

			body.add_child(collider)
			node.add_child(body)


			body.owner = node.owner
			collider.owner = node.owner

			added += 1

	for child in node.get_children():
		added += _process_node_recursive(child)

	return added

func _has_collision(node: Node3D) -> bool:
	for child in node.get_children():
		if child is StaticBody3D or child is CollisionShape3D:
			return true
	return false
