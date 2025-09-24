# ============================================================
# Trajectory Playback Script
#
# This script loads a TX/RX trajectory from a CSV file and replays
# it in the Godot scene by moving the assigned TX and RX nodes.
#
# - The CSV file should contain columns for TX and RX coordinates.
# - Trajectories are interpolated (10 Hz → 60 Hz) for smoother playback.
# - The original TX position is taken as a reference (origin),
#   and all movements are scaled relative to it.
# - The TX and RX nodes will always be kept at a fixed height.
# Parameters such as `scale_factor`, `playback_speed`, and
# the trajectory file path can be adjusted in the Inspector.
# ⚠️:
# If you want to reuse this script with different datasets,
# make sure the coordinate mapping (CSV column order → Godot axes)
# is correctly adapted to match your data format！
# ============================================================


extends Node3D

# === Parameters adjustable in the Inspector ===
@export var tx_car_path : NodePath        # NodePath for the TX car object
@export var rx_car_path : NodePath        # NodePath for the RX car object
@export var scale_factor := 1.0           # Scaling factor applied to all trajectory coordinates
@export var trajectory_csv := "res://doc/trajectory.csv"  # Path to the CSV file containing TX/RX trajectories
@export var playback_speed := 1.0         # (Reserved) playback speed factor

# === Internal variables ===
var trajectory_data := []                 # Interpolated trajectory data (list of Tx/Rx positions)
var tx_origin_data : Vector2              # Reference origin of TX in the CSV (2D)
var tx_origin_godot : Vector3             # Reference origin of TX in Godot world (3D)
var fixed_height := 0.0                   # Fixed height (Y) for TX and RX nodes

var current_index := 0                    # Current playback frame index
var timer := 0.0                          # Timer (not used yet)

func _ready():
	load_trajectory(trajectory_csv)        # Load trajectory from CSV when scene starts

func load_trajectory(path):
	var tx_car = get_node(tx_car_path)
	tx_origin_godot = tx_car.global_position  # Store original TX position in Godot
	fixed_height = tx_origin_godot.y          # Lock TX/RX movement to this Y height

	var file = FileAccess.open(path, FileAccess.READ)
	var header = true

	var raw_data = []   # Raw trajectory data before interpolation
	while not file.eof_reached():
		var line = file.get_line()
		if header:                      # Skip the CSV header line
			header = false
			continue
		var values = line.split(",")
		if values.size() == 6:
			# Extract TX (lat/lon) and RX (lat/lon) → store as 2D coordinates
			var tx2d = Vector2(float(values[1]), float(values[0])) 
			var rx2d = Vector2(float(values[4]), float(values[3])) 
			raw_data.append({ "tx2d": tx2d, "rx2d": rx2d })
	file.close()

	# --- Interpolation stage (10 Hz → 60 Hz) ---
	if raw_data.size() == 0:
		return
	
	tx_origin_data = raw_data[0]["tx2d"]  # Reference TX coordinate from CSV

	var insert_factor = 6                 # Interpolate 6 steps between each point
	for i in range(raw_data.size() - 1):
		var tx2d_0 = raw_data[i]["tx2d"]
		var rx2d_0 = raw_data[i]["rx2d"]
		var tx2d_1 = raw_data[i+1]["tx2d"]
		var rx2d_1 = raw_data[i+1]["rx2d"]

		for k in range(insert_factor):
			var alpha = float(k) / insert_factor  
			var tx2d_interp = tx2d_0.lerp(tx2d_1, alpha)
			var rx2d_interp = rx2d_0.lerp(rx2d_1, alpha)

			# Convert from CSV-relative 2D → Godot 3D coordinates
			var offset_tx = (tx2d_interp - tx_origin_data) * scale_factor
			var offset_rx = (rx2d_interp - tx_origin_data) * scale_factor

			var data_point = {
				"Tx": tx_origin_godot + Vector3(offset_tx.x, 0.0, offset_tx.y),
				"Rx": tx_origin_godot + Vector3(offset_rx.x, 0.0, offset_rx.y)
			}
			trajectory_data.append(data_point)

	# Append the last CSV point to trajectory
	var tx2d_last = raw_data[-1]["tx2d"]
	var rx2d_last = raw_data[-1]["rx2d"]
	var offset_tx_last = (tx2d_last - tx_origin_data) * scale_factor
	var offset_rx_last = (rx2d_last - tx_origin_data) * scale_factor
	var data_point_last = {
		"Tx": tx_origin_godot + Vector3(offset_tx_last.x, 0.0, offset_tx_last.y),
		"Rx": tx_origin_godot + Vector3(offset_rx_last.x, 0.0, offset_rx_last.y)
	}
	trajectory_data.append(data_point_last)
	print("interlerp over")


func _physics_process(delta):
	# Playback loop: move TX and RX along trajectory
	if trajectory_data.is_empty():
		return
	if current_index >= trajectory_data.size():
		return

	var tx_car = get_node(tx_car_path)
	var rx_car = get_node(rx_car_path)

	var tx_pos = trajectory_data[current_index]["Tx"]
	var rx_pos = trajectory_data[current_index]["Rx"]

	# Keep TX and RX fixed at the reference height
	tx_pos.y = fixed_height
	rx_pos.y = fixed_height

	# Update positions
	tx_car.global_position = tx_pos
	rx_car.global_position = rx_pos
	
	current_index += 1
