# ============================================================
# This EditorScript automatically attaches the "Building.gd" script
# to all selected MeshInstance3D nodes (and their children) in the editor(not nessesary but I'm lazy).
#
# - Run this script after selecting one or more nodes in the SceneTree.
# - It will recursively traverse all children.
# - If a MeshInstance3D does not already have a script, "Building.gd"
#   will be attached to it. So the node will be added
#   to the material group and its `material_type` property will be
#   initialized as "concrete".
# ============================================================

@tool
extends EditorScript

func _run():
	var selected_nodes = get_editor_interface().get_selection().get_selected_nodes()
	if selected_nodes.is_empty():
		push_error("Select a node！")
		return

	var building_script = load("res://scripts/Building.gd")
	if building_script == null:
		push_error("CANNOT find Building.gd！")
		return

	var count = 0
	for node in selected_nodes:
		count += _process_node_recursive(node, building_script)

	print("✅ Successfully attach the script to ", count, " nodes。")

func _process_node_recursive(node: Node, script: Script) -> int:
	var added = 0
	if node is MeshInstance3D and node.get_script() == null:
		node.set_script(script)
		node.material_type = "concrete"
		added += 1

	for child in node.get_children():
		added += _process_node_recursive(child, script)
	return added
