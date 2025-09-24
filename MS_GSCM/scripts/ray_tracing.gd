# ============================================================
# Ray-Tracing 
#
# All major parameters are exported and can be adjusted directly in the Godot Inspector.
#
# ⚠️ Note:
# - `mode0` and `mode1` are custom definitions by the author, designed for model comparison. 
# - You can delete one of them if it's useless for your work or change the modes to compare the effects of different simulation settings.
# ============================================================


extends Node3D
const C = 3.0e8   # Speed of light (m/s)

# ======= Simulation Parameters (exported, editable in Godot editor) =======
@export var transmitter: Node3D       # Transmitter node
@export var receiver: Node3D          # Receiver node
@export var Ground: Node3D            # Ground plane node
@export var scatter_group := "ScatterGroup"  # Group name for scatterers
@export var draw_threshold := -120    # Gain threshold (dB) for drawing paths
@export var num_subcarriers := 2048   # Number of subcarriers
@export var delta_f := 500e3          # Subcarrier spacing (Hz)
@export var base_ga_mode := 1         # Angular gain model for mode0 (0 = COST-IRACON angular gain model, 1 = our proposed gain model)
@export var base_gc_mode := 0         # Reflection coefficient model for mode0(0 = COST-IRACON empirical reflection gain, 1 = our proposed material-aware model)
@export var carrier_freq := 3.2e9     # Carrier frequency (Hz)
@export var sim_time := 30            # Simulation duration (seconds)
@export var MAX_ORD2_PAIRS = 500      # Max number of 2nd-order scatterer pairs
@export var metal_only := 0           # Enable to consider only paths with metallic scatterers (useful in scenes with large metal surfaces)
@export var diff_penalty_new = 12.0   # Penalty factor for angular mismatch
@export var ifdiffuse := 0            # Enable our very simple diffuse scattering modeling (0/1)
@export var difftole = 0.35           # Tolerance for angular difference (in rad)

# ======= Data Storage =======
var drawn_paths := []                # Currently drawn path objects
var recorded_H_LOS = []              # Recorded channel response (LOS)
var recorded_H_ground = []           # Recorded channel response (ground-reflected)
var recorded_H_NLOS_mode0 = []       # Recorded channel response (NLOS, mode 0)
var recorded_H_NLOS_mode1 = []       # Recorded channel response (NLOS, mode 1)
var time_elapsed = 0.0               # Elapsed simulation time
var has_exported = false             # Flag: results already exported

# ======= Scatterer Data & Path Caches =======
var scatter_data_ord1 = []           # First-order scatterers
var scatter_data_ord2 = []           # Second-order scatterers
var ord2_pairs = []                  # Valid scatterer pairs for 2nd order (we will later discuss what "valid" means)

# ======= Multithreading Control =======
var thread_lock := Mutex.new()       # Mutex for thread-safe operations
var thread_results = []              # Partial results from threads
var finished_threads = 0             # Number of finished threads

# ======= Environment Info =======
var space_state: PhysicsDirectSpaceState3D  # Physics state for ray queries
var ground_y = 0.0                          # Ground Y-coordinate


func _ready():
	# Initialize physics state and clear caches
	space_state = get_world_3d().direct_space_state
	scatter_data_ord1.clear()
	scatter_data_ord2.clear()
	ord2_pairs.clear()

	# Collect scatterer metadata from scene
	for scatter in get_tree().get_nodes_in_group(scatter_group):
		var order = scatter.get_meta("order", 1)         # Scatter order (1st/2nd)
		var pos = scatter.get_meta("true_pos")           # Scatter position (absolute position in the global coordinate system) 
		var n = scatter.get_meta("surface_normal", Vector3.UP)  # Surface normal
		if typeof(n) != TYPE_VECTOR3: n = Vector3.UP
		var material = scatter.get_meta("material_type", "concrete") # Material type, default to be concrete
		var building_name = scatter.get_meta("building_name", "")
		
		# Get material-dependent reflection coefficients, here mode0 uses the COST-IRACON empirical reflection gain
		var gc_mode0 = get_gc_from_material(material, base_gc_mode)
		var gc_mode1 = get_gc_from_material(material, 1)

		var data = {
			"pos": pos,
			"normal": n,
			"material": material,
			"gc0": gc_mode0,
			"gc1": gc_mode1,
			"building_name": building_name
		}

		# Store scatterer depending on order
		if order == 1:
			# If Metal Only is on, the simulation will only consider the paths which have at least one metal scatter
			if metal_only == 0 or building_name == "MetalicSurface":
				scatter_data_ord1.append(data)
		elif order == 2:
			scatter_data_ord2.append(data)

	# Build all possible 2nd-order scatterer pairs
	for i in range(scatter_data_ord2.size()):
		for j in range(scatter_data_ord2.size()):
			if i == j: continue
			var s1 = scatter_data_ord2[i]
			var s2 = scatter_data_ord2[j]
			# Skip if blocked
			if is_path_blocked(s1["pos"], s2["pos"]): continue
			# If metal_only=1, only allow metal-metal reflections
			if metal_only == 1 and s1["building_name"] != "MetalicSurface" and s2["building_name"] != "MetalicSurface":
				continue
			ord2_pairs.append([s1, s2])

	# Shuffle and limit to MAX_ORD2_PAIRS
	ord2_pairs.shuffle()
	var total_pairs = ord2_pairs.size()
	ord2_pairs = ord2_pairs.slice(0, min(total_pairs, MAX_ORD2_PAIRS))

	print("✅ Scatter data ready. Ord1:", scatter_data_ord1.size(), " Ord2 pairs:", ord2_pairs.size(), " from ", total_pairs)


func _physics_process(delta):
	# Each physics frame: compute paths and channel response
	if not transmitter or not receiver:
		print("TX or RX not defined!")
		return

	clear_previous_paths()            # Clear previously drawn paths
	compute_MPC_and_H_parallel()      # Run multipath computation in threads
	
	# Export results after sim_time has elapsed
	time_elapsed += delta
	if time_elapsed >= sim_time and not has_exported:
		export_H_to_file(recorded_H_LOS, "res://doc/H_LOS.txt")
		export_H_to_file(recorded_H_ground, "res://doc/H_ground.txt")
		export_H_to_file(recorded_H_NLOS_mode0, "res://doc/H_NLOS_mode0.txt")
		export_H_to_file(recorded_H_NLOS_mode1, "res://doc/H_NLOS_mode1.txt")
		has_exported = true


func compute_MPC_and_H_parallel():
	# Split subcarriers across multiple threads for parallel computation
	thread_results.clear()
	finished_threads = 0
	var tx_pos = transmitter.global_transform.origin
	var rx_pos = receiver.global_transform.origin
	
	# Ground reflection: mirror transmitter across ground plane
	var tx_mirror = Vector3(tx_pos.x, -tx_pos.y + 2 * ground_y, tx_pos.z)
	var dir = (rx_pos - tx_mirror).normalized()

	# Compute ground intersection point
	var ground_normal = Vector3(0.0, 1.0, 0.0)
	var gr_angle = acos(clamp(dir.dot(ground_normal), -1.0, 1.0))
	var ray_start = tx_mirror
	var ray_end = rx_pos
	var t0 = -ray_start.y / (ray_end.y - ray_start.y)
	var intersection_point = ray_start.lerp(ray_end, t0)

	# Check blocking for ground reflection
	var blocked1 = is_path_blocked(tx_pos, intersection_point)
	var blocked2 = is_path_blocked(intersection_point, rx_pos)

	# Split subcarriers into 8 threads
	var threads = []
	var subcarriers_per_thread = int(ceil(float(num_subcarriers) / 8))
	for t_index in range(8):
		var start_i = t_index * subcarriers_per_thread
		var end_i = min(num_subcarriers, start_i + subcarriers_per_thread)
		if start_i >= end_i:
			continue
		var t = Thread.new()
		var args = {
			"indices": Array(range(start_i, end_i)),
			"tx": tx_pos,
			"rx": rx_pos,
			"d_LOS": tx_pos.distance_to(rx_pos),
			"d_ground_re": tx_mirror.distance_to(rx_pos),
			"los_blocked": is_path_blocked(tx_pos, rx_pos),
			"ground_re_blocked": blocked1 or blocked2,
			"inter_point": intersection_point,
			"gr_angle": gr_angle
		}
		# Start thread
		t.start(Callable(self, "_compute_H_thread").bind(args))
		threads.append(t)
	
	# Wait for all threads
	for t in threads:
		t.wait_to_finish()
	
	# Collect thread results
	var H0_frame = []
	var H_ground_frame = []
	var H0_frame_NLOS = []
	var H1_frame_NLOS = []
	for partial in thread_results:
		for array in partial:
			H0_frame.append(array[0])
			H_ground_frame.append(array[1])
			H0_frame_NLOS.append(array[2])
			H1_frame_NLOS.append(array[3])
	recorded_H_LOS.append(H0_frame)
	recorded_H_ground.append(H_ground_frame)
	recorded_H_NLOS_mode0.append(H0_frame_NLOS)
	recorded_H_NLOS_mode1.append(H1_frame_NLOS)


func _compute_H_thread(args: Dictionary):
	# Worker function: compute H(f) for assigned subcarriers
	var result = []
	var tx = args["tx"]
	var rx = args["rx"]

	# ===== Pre-calculate valid 1st-order paths =====
	var cached_paths_ord1 = []
	for data in scatter_data_ord1:
		var p = data["pos"]
		var n = data["normal"]
		var material = data["material"]
		# Skip if blocked
		if is_path_blocked(tx, p) or is_path_blocked(p, rx):
			continue
		var d1 = tx.distance_to(p)
		var d2 = p.distance_to(rx)
		# Angular gain (mode0 & mode1)
		var ga0 = compute_angular_gain(base_ga_mode, tx, rx, p, n, material)
		var ga1 = compute_angular_gain(1, tx, rx, p, n, material, diff_penalty_new, ifdiffuse, difftole)
		var gc0 = data["gc0"]
		var gc1 = data["gc1"]
		cached_paths_ord1.append({
			"d": d1 + d2,
			"gc_ga_mode0": min(gc0 * ga0, 1),
			"gc_ga_mode1": min(gc1 * ga1, 1),
			"p1": p
		})

	# ===== Pre-calculate valid 2nd-order paths =====
	var cached_paths_ord2 = []
	for pair in ord2_pairs:
		var s1 = pair[0]
		var s2 = pair[1]
		var p1 = s1["pos"]
		var p2 = s2["pos"]
		# Skip if blocked
		if is_path_blocked(tx, p1) or is_path_blocked(p2, rx):
			continue
		var d1 = tx.distance_to(p1)
		var d2 = p1.distance_to(p2)
		var d3 = p2.distance_to(rx)
		var material1 = s1["material"]
		var material2 = s2["material"]
		# Angular gains for two reflections
		var ga1_mode0 = compute_angular_gain(base_ga_mode, tx, p2, p1, s1["normal"], material1)
		var ga2_mode0 = compute_angular_gain(base_ga_mode, p1, rx, p2, s2["normal"], material2)
		var ga1_mode1 = compute_angular_gain(1, tx, p2, p1, s1["normal"], material1, diff_penalty_new, ifdiffuse, difftole)
		var ga2_mode1 = compute_angular_gain(1, p1, rx, p2, s2["normal"], material2, diff_penalty_new, ifdiffuse, difftole)
		var gc10 = s1["gc0"]
		var gc20 = s2["gc0"]
		var gc11 = s1["gc1"]
		var gc21 = s2["gc1"]
		cached_paths_ord2.append({
			"d": d1 + d2 + d3,
			"gc_ga_mode0": min(gc10 * gc20 * ga1_mode0 * ga2_mode0, 1),
			"gc_ga_mode1": min(gc11 * gc21 * ga1_mode1 * ga2_mode1, 1),
			"p1": p1,
			"p2": p2
		})
	
	# ===== Loop over assigned subcarriers =====
	for i in args["indices"]:
		var f_i = carrier_freq - num_subcarriers * 0.5 * delta_f + i * delta_f
		var g0 = C / (4 * PI * f_i)
		var H_fi0 = Vector2.ZERO
		var H_fi_ground = Vector2.ZERO
		var H_fi0_NLOS = Vector2.ZERO
		var H_fi1_NLOS = Vector2.ZERO
	
		# Direct LOS contribution
		if not args["los_blocked"]:
			var d_LOS = args["d_LOS"]
			var phase_LOS = -2 * PI * f_i * d_LOS / C
			var g_los = g0 / d_LOS
			H_fi0 += g_los * Vector2(cos(phase_LOS), sin(phase_LOS))
			if i == 0:
				call_deferred("draw_path", tx, rx, Color.BLUE)
	   
		# Ground reflection contribution
		if not args["ground_re_blocked"]:
			var d_ground_re = args["d_ground_re"]
			var gr_angle = args["gr_angle"]
			var inter_point = args["inter_point"]
			var phase_gr = -2 * PI * f_i * d_ground_re / C
			var gr_gain_val = gr_gain(gr_angle, f_i)
			var g_gr = g0 * gr_gain_val / d_ground_re 
			H_fi_ground += g_gr * Vector2(cos(phase_gr), sin(phase_gr))
			if i == 0:
				call_deferred("draw_path", tx, inter_point, Color.DARK_GREEN)
				call_deferred("draw_path", inter_point, rx, Color.DARK_GREEN)

		# 1st-order scatterer contributions
		for path in cached_paths_ord1:
			var d = path["d"]
			var g10 = g0 * path["gc_ga_mode0"] / d
			var g11 = g0 * path["gc_ga_mode1"] / d
			var phase = -2 * PI * f_i * d / C
			var contrib0 = g10 * Vector2(cos(phase), sin(phase))
			var contrib1 = g11 * Vector2(cos(phase), sin(phase))
			H_fi0_NLOS += contrib0
			H_fi1_NLOS += contrib1
			if i == 0 and 10 * log(g10) / log(10) > draw_threshold:
				call_deferred("draw_path", tx, path["p1"], Color.RED)
				call_deferred("draw_path", path["p1"], rx, Color.RED)
	
		# 2nd-order scatterer contributions
		for path in cached_paths_ord2:
			var d = path["d"]
			var g10 = g0 * path["gc_ga_mode0"] / d
			var g11 = g0 * path["gc_ga_mode1"] / d
			var phase = -2 * PI * f_i * d / C
			var contrib0 = g10 * Vector2(cos(phase), sin(phase))
			var contrib1 = g11 * Vector2(cos(phase), sin(phase))
			H_fi0_NLOS += contrib0
			H_fi1_NLOS += contrib1
			if i == 0 and 10 * log(g10) / log(10) > draw_threshold:
				call_deferred("draw_path", tx, path["p1"], Color.ORANGE)
				call_deferred("draw_path", path["p1"], path["p2"], Color.ORANGE)
				call_deferred("draw_path", path["p2"], rx, Color.ORANGE)
	
		# Store results for this subcarrier
		result.append([H_fi0, H_fi_ground, H_fi0_NLOS, H_fi1_NLOS])
	
	# Thread-safe append of results
	thread_lock.lock()
	thread_results.append(result)
	finished_threads += 1
	thread_lock.unlock()


func compute_angular_gain(mode, tx: Vector3, rx: Vector3, scatter: Vector3, normal: Vector3, material := "", penalty_factor :float= 12.0, diffuse :float= 0.0, difftole:float = 0.35) -> float:
	
	# Compute angular gain based on reflection geometry
	var incoming = (tx - scatter).normalized()
	var outgoing = (rx - scatter).normalized()
	var theta01 = acos(clamp(incoming.dot(normal), -1.0, 1.0))
	var theta02 = acos(clamp(outgoing.dot(normal), -1.0, 1.0))
	var theta1 = PI * 0.5 - acos(clamp(incoming.dot(normal), -1.0, 1.0))
	var theta2 = PI * 0.5 - acos(clamp(outgoing.dot(normal), -1.0, 1.0))
	var dot_product = incoming.dot(normal)
	# In a 3D scene, use the theoretical reflection direction (from incident vector) and compare it with the actual outgoing direction to compute the angle difference.
	var theo_out = (2.0 * dot_product * normal - incoming).normalized()
	var theta_diff = acos(clamp(theo_out.dot(outgoing), -1.0, 1.0))
	var difftole_0 = 0.35
	
	# Penalties
	var I1 = float(abs(theta_diff) > difftole_0)
	var I2 = float(abs(theta01) > 1.22)
	var I3 = float(abs(theta02) > 1.22)
	var pe = penalty_factor
	
	# This penalty factor is mainly used when diffuse mode is enabled.
	# It applies much stronger attenuation for large incident angles, 
	# where diffuse scattering is unlikely to occur.
	# In diffuse mode, we normally apply a smooth penalty based on
	# the difference between incident and outgoing angles.
	# However, if the incident angle exceeds the grazing threshold,
	# we assume no diffuse scattering occurs. 
	# In that case, paths with large angle differences are heavily suppressed.
	var pe_for_bigangle = pow(12, I2)
	if diffuse == 1.0:
		pe = pe_for_bigangle
	
	if mode == 0:
		# COST-IRACON penalty function
		return exp(
			- pe * (abs(theta_diff) - difftole_0) * I1
			- 12.0 * (abs(theta01) - 1.22) * I2
			- 12.0 * (abs(theta02) - 1.22) * I3
		)
	elif mode == 1:
		# Fresnel based angular gain formula
		if theta01 >= 0 and theta02 >= 0:
			var angle_deg1 = rad_to_deg(theta01)
			var angle_deg2 = rad_to_deg(theta02)
			var mean_angle = 0.5 * (angle_deg1 + angle_deg2)
			var ga = 1.0 + 1.44 * pow(mean_angle / 90.0, 6.96)
			var penalty = exp(- pe * (abs(theta_diff) - difftole_0) * I1)
			return ga * penalty
	return 1.0


func gr_gain(gr_angle, freq) -> float:
	# Fresnel reflection coefficient for ground reflection
	var f = freq * pow(10, -9)
	var neta0 = 15 * pow(f, -0.1)
	var sigma = 0.035 * pow(f, 1.63) 
	var neta1 = 17.98 * sigma / f
	var neta = Complex.new(neta0, -1 * neta1)
	var sin2 = pow(sin(gr_angle), 2)
	var diff = neta.sub_real(sin2)
	var sqrt_term = complex_sqrt(diff)
	var cos_angle = Complex.new(cos(gr_angle), 0.0)
	var R_TE = (cos_angle.sub(sqrt_term)).div(cos_angle.add(sqrt_term))
	var neta_cos = neta.mul_real(cos(gr_angle))
	var R_TM = (neta_cos.sub(sqrt_term)).div(neta_cos.add(sqrt_term))
	var sum_squares = R_TE.pow_real(2).add(R_TM.pow_real(2))
	var avg = sum_squares.mul_real(0.5)
	var R = complex_sqrt(avg)
	var result = R.abs()
	if result > 1.0:
		print("exceeding error")
	return result


func complex_sqrt(z: Complex) -> Complex:
	# Complex square root
	var r = z.abs()
	var theta = atan2(z.im, z.re)
	var sqrt_r = sqrt(r)
	var half_theta = theta / 2.0
	return Complex.new(sqrt_r * cos(half_theta), sqrt_r * sin(half_theta))


func is_path_blocked(start, end) -> bool:
	# Check if a line-of-sight path between start and end is blocked by obstacles
	if space_state == null:
		print("⚠️ space_state isn't initialized！")
		return true
	var query = PhysicsRayQueryParameters3D.create(start, end)
	query.collision_mask = (1 << 0) | (1 << 1)
	query.exclude = [Ground]
	var result = space_state.intersect_ray(query)
	return result != {}


func get_gc_from_material(material: String, material_mode: int) -> float:
	# Get reflection coefficient based on material type & mode
	if material_mode == 0:
		return randf_range(0.139, 0.984)
	elif material_mode == 1:
		match material:
			"metal": return randf_range(0.99, 1.0)
			"glass": return randf_range(0.3, 0.55)
			"concrete": return randf_range(0.25, 0.5)
			_: return 0.375
	return 0.375
	

func draw_path(start, end, color):
	# Draw a line between two points with a given color
	var line = MeshInstance3D.new()
	var mesh = ImmediateMesh.new()
	line.mesh = mesh
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true  
	line.material_override = mat
	add_child(line)
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(start)
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(end)
	mesh.surface_end()
	drawn_paths.append(line)


func clear_previous_paths():
	# Remove all previously drawn paths each frame
	for path in drawn_paths:
		path.queue_free()
	drawn_paths.clear()


func export_H_to_file(H_all, path):
	# Export recorded channel responses to CSV file
	var file = FileAccess.open(path, FileAccess.WRITE)
	if not file:
		print("❌ Cannot open file: ", path)
		return
	file.store_line("Real1,Imag1,...,RealN,ImagN")
	for frame_H in H_all:
		var line = []
		for H_f in frame_H:
			line.append(str(H_f.x))
			line.append(str(H_f.y))
		file.store_line(",".join(line))
	file.close()
	print("✅ Exported: ", path)
