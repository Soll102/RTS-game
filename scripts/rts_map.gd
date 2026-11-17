extends Node3D
## Approved v6 map exploration. Army assets and battle display remain separate.

const IDS = ["TRB6-TERRAIN-001", "TRB6-RIVER-001", "TRB6-FOREST-001", "TRB6-CITY-001", "TRB6-GRASS-001", "TRB6-HOUSES-001"]

const SHOTS = [
	{"name": "01-overview", "title": "REGION OVERVIEW",
	 "target": Vector3(0, 3, 6), "eye": Vector3(46, 96, 132), "fov": 38.0},
	{"name": "02-city-river", "title": "CITY AND RIVER BANK",
	 "target": Vector3(26, 2, 26), "eye": Vector3(62, 46, 74), "fov": 40.0},
	{"name": "03-ridge-forest", "title": "RIDGE AND FOREST",
	 "target": Vector3(-46, 7, -40), "eye": Vector3(-4, 54, 26), "fov": 42.0},
	{"name": "04-low-angle", "title": "LOW ANGLE / DEPTH READ",
	 "target": Vector3(10, 5, 20), "eye": Vector3(74, 20, 96), "fov": 44.0},
	{"name": "05-terrain-closeup", "title": "TERRAIN CLOSE-UP",
	 "target": Vector3(-30, 4, 4), "eye": Vector3(-14, 12, 26), "fov": 46.0},
	{"name": "06-city-detail", "title": "CITY DETAIL",
	 "target": Vector3(26, 2, 26), "eye": Vector3(40, 20, 44), "fov": 40.0},
	{"name": "07-house-detail", "title": "HOUSE / CURVED TILES AND TIMBER FRAMES",
	 "target": Vector3(22, 1.6, 43), "eye": Vector3(27, 5.0, 48), "fov": 40.0},
	{"name": "08-castle-gate", "title": "CASTLE GATE / MASONRY AND EAVES",
	 "target": Vector3(26, 3.1, 33), "eye": Vector3(31.5, 7.0, 41.5), "fov": 40.0},
	{"name": "09-meadow-detail", "title": "MEADOW / GRASS BLADES AND SOIL",
	 "target": Vector3(-18, 1.0, 22), "eye": Vector3(-12, 3.0, 29), "fov": 46.0},
]


const MAP_DIR := "res://assets/map-v6/"
const GRID_WIDTH := 901
const GRID_DEPTH := 701
const CELL_SIZE := 0.4
const MIN_X := -180.0
const MAX_X := 180.0
const MIN_Z := -140.0
const MAX_Z := 140.0

var camera: Camera3D
var sun: DirectionalLight3D
var env: Environment
var target := Vector3.ZERO
var yaw := 0.0
var pitch := 0.6
var distance := 120.0
var loaded: Dictionary = {}
var heights := PackedFloat32Array()
var smoke := false
var failures: Array[String] = []
var checks := 0

# Keep the exact approved material/light settings from the reviewed map.
func _num(_prefix: String, fallback: float) -> float:
	return fallback

func _grade(_slot: int, fallback: float) -> float:
	return fallback

func _fog() -> float:
	return 0.0009

func _ready() -> void:
	smoke = "--map-smoke" in OS.get_cmdline_user_args()
	if not verify_assets():
		get_tree().quit(2)
		return
	var height_file := FileAccess.open(MAP_DIR + "terrain-heights.f32", FileAccess.READ)
	if height_file == null or height_file.get_length() != GRID_WIDTH * GRID_DEPTH * 4:
		push_error("Approved terrain height data is missing or invalid.")
		get_tree().quit(2)
		return
	heights = height_file.get_buffer(height_file.get_length()).to_float32_array()
	setup_world()
	for id in IDS:
		var scene := load(MAP_DIR + id + "-v6.glb") as PackedScene
		if scene == null:
			push_error("Approved map import failed: " + id)
			get_tree().quit(2)
			return
		var model := scene.instantiate() as Node3D
		add_child(model)
		model.name = id
		loaded[id] = model
		_bind_materials(model, id)
	apply_shot(0)
	DisplayServer.window_set_title("Three Kingdoms | v6 map | 1-9: views | WASD/MMB: pan | RMB: orbit | Wheel: zoom | Home: reset")
	if smoke:
		run_smoke()

func verify_assets() -> bool:
	var file := FileAccess.open(MAP_DIR + "approved-assets.json", FileAccess.READ)
	if file == null:
		push_error("Approved map manifest is missing.")
		return false
	var entries = JSON.parse_string(file.get_as_text())
	if not entries is Array or entries.size() != 19:
		push_error("Approved map manifest is invalid.")
		return false
	for entry in entries:
		if not entry is Dictionary or entry.get("status") != "approved" or entry.get("version") != 6:
			push_error("Map requires exact v6 approval.")
			return false
		var path := MAP_DIR + str(entry.get("integrated_file", "")).get_file()
		if FileAccess.get_sha256(path) != entry.get("sha256"):
			push_error("Approved map file changed or is missing: " + path)
			return false
	return true

func terrain_height_at(x: float, z: float) -> float:
	var gx := clampf((x - MIN_X) / CELL_SIZE, 0, GRID_WIDTH - 1)
	var gz := clampf((z - MIN_Z) / CELL_SIZE, 0, GRID_DEPTH - 1)
	var ix := mini(int(gx), GRID_WIDTH - 2)
	var iz := mini(int(gz), GRID_DEPTH - 2)
	var a := lerpf(heights[iz * GRID_WIDTH + ix], heights[iz * GRID_WIDTH + ix + 1], gx - ix)
	var b := lerpf(heights[(iz + 1) * GRID_WIDTH + ix], heights[(iz + 1) * GRID_WIDTH + ix + 1], gx - ix)
	return lerpf(a, b, gz - iz)

func apply_shot(index: int) -> void:
	if index < 0 or index >= SHOTS.size():
		return
	var shot: Dictionary = SHOTS[index]
	target = shot.target
	camera.position = shot.eye
	camera.fov = shot.fov
	camera.look_at(target, Vector3.UP)
	var offset: Vector3 = camera.position - target
	distance = offset.length()
	yaw = atan2(offset.x, offset.z)
	pitch = asin(clampf(offset.y / distance, -1.0, 1.0))

func _orbit() -> void:
	pitch = clampf(pitch, deg_to_rad(6), deg_to_rad(85))
	distance = clampf(distance, 4.0, 420.0)
	var orbit_offset := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
	camera.position = target + orbit_offset
	# Camera must stay above the terrain, including when orbiting through a ridge.
	camera.position.y = maxf(camera.position.y, terrain_height_at(camera.position.x, camera.position.z) + 1.2)
	camera.look_at(target, Vector3.UP)

func pan(offset: Vector2) -> void:
	target.x = clampf(target.x + offset.x, MIN_X, MAX_X)
	target.z = clampf(target.z + offset.y, MIN_Z, MAX_Z)
	target.y = maxf(0.3, terrain_height_at(target.x, target.z)) + 1.0
	_orbit()

func _process(delta: float) -> void:
	if camera == null or smoke:
		return
	_pan_keyboard(delta)

func _pan_keyboard(delta: float) -> void:
	var direction := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT): direction.x -= 1
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT): direction.x += 1
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP): direction.y -= 1
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN): direction.y += 1
	if direction != Vector2.ZERO:
		var right := camera.global_basis.x
		var forward := Vector3(right.z, 0, -right.x)
		var offset := (right * direction.x - forward * direction.y).normalized() * delta * distance * 0.55
		pan(Vector2(offset.x, offset.z))

func _unhandled_input(event: InputEvent) -> void:
	if camera == null:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = maxf(4.0, distance * 0.9)
			_orbit()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = minf(420.0, distance / 0.9)
			_orbit()
	if event is InputEventMouseMotion:
		if event.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
			var viewport_height := maxf(get_viewport().get_visible_rect().size.y, 1.0)
			var scale := distance * tan(deg_to_rad(camera.fov * 0.5)) * 2.0 / viewport_height
			var right := camera.global_basis.x
			var forward := Vector3(right.z, 0, -right.x)
			var offset: Vector3 = (-right * event.relative.x + forward * event.relative.y) * scale
			pan(Vector2(offset.x, offset.z))
		elif event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			yaw -= event.relative.x * 0.005
			pitch += event.relative.y * 0.004
			_orbit()
	if event is InputEventKey and event.pressed and not event.echo:
		var key: int = event.keycode if event.keycode != 0 else event.physical_keycode
		if key == KEY_ESCAPE: get_tree().quit()
		elif key == KEY_HOME: apply_shot(0)
		elif key >= KEY_1 and key <= KEY_9: apply_shot(key - KEY_1)

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("MAP CHECK FAILED: " + message)

func _key(code: int) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)

func _check_keyboard_pan() -> void:
	# Inject physical keys through Godot and check against the camera's screen axes.
	for heading in [0.0, PI * 0.5, PI, PI * 1.5]:
		for code in [KEY_W, KEY_UP, KEY_S, KEY_DOWN, KEY_A, KEY_LEFT, KEY_D, KEY_RIGHT]:
			apply_shot(0)
			yaw = heading
			_orbit()
			var screen_right := camera.global_basis.x
			var screen_up := camera.global_basis.y
			var previous_target := target
			var event := InputEventKey.new()
			event.keycode = code
			event.physical_keycode = code
			event.pressed = true
			Input.parse_input_event(event)
			Input.flush_buffered_events()
			_pan_keyboard(0.1)
			event = event.duplicate()
			event.pressed = false
			Input.parse_input_event(event)
			Input.flush_buffered_events()
			var movement := target - previous_target
			movement.y = 0.0
			var expected := screen_up if code in [KEY_W, KEY_UP, KEY_S, KEY_DOWN] else screen_right
			if code in [KEY_S, KEY_DOWN, KEY_A, KEY_LEFT]: expected = -expected
			_check(movement.dot(expected) > 0.01, "Keyboard %s follows screen at yaw %.2f" % [OS.get_keycode_string(code), heading])
			previous_target = target
			_pan_keyboard(0.1)
			_check(target.is_equal_approx(previous_target), "Keyboard release stops pan")

func run_smoke() -> void:
	for frame in range(8): await get_tree().process_frame
	var rendered := DisplayServer.get_name() != "headless"
	var output := ProjectSettings.globalize_path("res://../reports/v6-play-validation")
	DirAccess.make_dir_recursive_absolute(output)
	_check(loaded.size() == 6, "All six map models load")
	_check(heights.size() == 631601, "Height grid matches approved mesh")
	_check_keyboard_pan()
	for i in range(SHOTS.size()):
		_key(KEY_1 + i)
		await get_tree().process_frame
		_check(target.is_equal_approx(SHOTS[i].target) and camera.position.is_equal_approx(SHOTS[i].eye), "View %d input" % (i + 1))
		if rendered:
			for frame in range(4): await get_tree().process_frame
			await RenderingServer.frame_post_draw
			_check(get_viewport().get_texture().get_image().save_png(output + "/%s-engine.png" % SHOTS[i].name) == OK, "Capture view %d" % (i + 1))
	var wheel := InputEventMouseButton.new()
	wheel.pressed = true
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	var before := distance
	Input.parse_input_event(wheel)
	await get_tree().process_frame
	_check(distance < before, "Wheel zoom input")
	for i in range(100): _unhandled_input(wheel)
	_check(is_equal_approx(distance, 4.0), "Minimum zoom clamps")
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	for i in range(100): _unhandled_input(wheel)
	_check(is_equal_approx(distance, 420.0), "Maximum zoom clamps")
	_key(KEY_HOME)
	await get_tree().process_frame
	var motion := InputEventMouseMotion.new()
	motion.button_mask = MOUSE_BUTTON_MASK_MIDDLE
	motion.relative = Vector2(140, 65)
	before = target.x
	Input.parse_input_event(motion)
	await get_tree().process_frame
	_check(not is_equal_approx(before, target.x), "Mouse pan input")
	motion.button_mask = MOUSE_BUTTON_MASK_RIGHT
	motion.relative = Vector2(70, -35)
	before = yaw
	Input.parse_input_event(motion)
	await get_tree().process_frame
	_check(not is_equal_approx(before, yaw), "Mouse orbit input")
	for corner in [Vector2(-10000,-10000), Vector2(10000,-10000), Vector2(10000,10000), Vector2(-10000,10000)]:
		pan(corner)
		await get_tree().process_frame
		_check(absf(target.x) == MAX_X and absf(target.z) == MAX_Z and camera.position.is_finite(), "Full-map corner clamp")
	for z in range(-130, 131, 20):
		for x in range(-170, 171, 20):
			target = Vector3(x, terrain_height_at(x,z), z)
			pitch = 0.0
			distance = 12
			_orbit()
			_check(camera.position.y >= terrain_height_at(camera.position.x, camera.position.z) + 1.19, "Camera terrain clearance")
	_key(KEY_HOME)
	await get_tree().process_frame
	_check(target.is_equal_approx(SHOTS[0].target) and camera.position.is_equal_approx(SHOTS[0].eye), "Home resets pose")
	var samples: Array[float] = []
	if rendered:
		DisplayServer.window_set_size(Vector2i(960,600))
		for frame in range(4): await get_tree().process_frame
		_check(get_viewport().get_visible_rect().size.is_equal_approx(Vector2(960,600)), "Window resize")
		DisplayServer.window_set_size(Vector2i(1600,1000))
		for frame in range(8): await get_tree().process_frame
		await RenderingServer.frame_post_draw
		_check(get_viewport().get_texture().get_image().save_png(output + "/v6-map-engine.png") == OK, "Save real engine capture")
		var previous := Time.get_ticks_usec()
		for frame in range(300):
			await get_tree().process_frame
			var now := Time.get_ticks_usec()
			samples.append((now - previous) / 1000.0)
			previous = now
		samples.sort()
	var report := {"checks":checks, "failures":failures, "engine":Engine.get_version_info(),
		"renderer":RenderingServer.get_current_rendering_method(), "rendered":rendered,
		"generated_at_utc":Time.get_datetime_string_from_system(true),
		"runtime_sha256":FileAccess.get_sha256("res://scripts/rts_map.gd"),
		"gpu":RenderingServer.get_video_adapter_name(), "cpu":OS.get_processor_name(),
		"memory_static_bytes":OS.get_static_memory_usage(),
		"timing_scope":"Stationary overview after warmup; frame intervals, not isolated GPU time",
		"scope":"Approved v6 map exploration; no armies, campaign display or full-China map",
		"frame_samples":samples.size(), "viewport":[1600,1000]}
	if not samples.is_empty():
		report["median_frame_ms"] = samples[samples.size()/2]
		report["p95_frame_ms"] = samples[int(samples.size()*0.95)]
	var report_file := FileAccess.open(output + ("/rendered-map.json" if rendered else "/headless-map.json"), FileAccess.WRITE)
	if report_file == null:
		push_error("Could not save map validation.")
		get_tree().quit(3)
		return
	report_file.store_string(JSON.stringify(report, "\t"))
	print("%s: %d map checks; rendered=%s" % ["PASS" if failures.is_empty() else "FAIL", checks, rendered])
	get_tree().quit(0 if failures.is_empty() else 1)

func _bind_materials(node: Node, id: String) -> void:
	if node is MeshInstance3D:
		if id == "TRB6-TERRAIN-001":
			var m := ShaderMaterial.new()
			m.shader = load("res://assets/map-v6/terrain.gdshader")
			m.set_shader_parameter("albedo_tex", load("res://assets/map-v6/TRB6-TERRAIN-001-albedo.png"))
			m.set_shader_parameter("normal_tex", load("res://assets/map-v6/TRB6-TERRAIN-001-normal.png"))
			m.set_shader_parameter("rough_tex", load("res://assets/map-v6/TRB6-TERRAIN-001-roughness.png"))
			m.set_shader_parameter("grain_tex", load("res://assets/map-v6/grain.png"))
			m.set_shader_parameter("grass_detail_tex", load("res://assets/map-v6/grass-detail.png"))
			m.set_shader_parameter("grass_detail_strength", _num("--gds=", 0.62))
			m.set_shader_parameter("grain_strength", _num("--gs=", 0.085))
			m.set_shader_parameter("grain_scale_c", _num("--gsc=", 2.60))
			m.set_shader_parameter("normal_strength", _num("--nstr=", 0.48))
			m.set_shader_parameter("grade_sat", _grade(3, 1.00))
			m.set_shader_parameter("grade_tint", Vector3(_grade(4, 1.00), _grade(5, 1.00), _grade(6, 1.00)))
			node.material_override = m
			# terrain never casts on itself in compatibility mode: shadow acne
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		elif id == "TRB6-GRASS-001":
			var gr := ShaderMaterial.new()
			gr.shader = load("res://assets/map-v6/grass.gdshader")
			gr.set_shader_parameter("card_tex", load("res://assets/map-v6/grass-card.png"))
			gr.set_shader_parameter("ground_tex", load("res://assets/map-v6/TRB6-TERRAIN-001-albedo.png"))
			gr.set_shader_parameter("grain_tex", load("res://assets/map-v6/grain.png"))
			gr.set_shader_parameter("fade_start", _num("--gfade=", 80.0))
			gr.set_shader_parameter("fade_end", _num("--gfade2=", 160.0))
			node.material_override = gr
			# alpha cards in the shadow pass cost more than they add
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		elif id == "TRB6-RIVER-001":
			var w := ShaderMaterial.new()
			w.shader = load("res://assets/map-v6/river.gdshader")
			w.set_shader_parameter("depth_tex", load("res://assets/map-v6/TRB6-RIVER-001-depth.png"))
			w.set_shader_parameter("grain_tex", load("res://assets/map-v6/grain.png"))
			node.material_override = w
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		else:
			for surface in range(node.mesh.get_surface_count()):
				var p := ShaderMaterial.new()
				if id == "TRB6-FOREST-001" and surface == 1:
					p.shader = load("res://assets/map-v6/foliage.gdshader")
					p.set_shader_parameter("leaf_tex", load("res://assets/map-v6/leaf-cluster.png"))
				else:
					p.shader = load("res://assets/map-v6/prop.gdshader")
					p.set_shader_parameter("grain_tex", load("res://assets/map-v6/grain.png"))
					p.set_shader_parameter("rough", 0.94)
					p.set_shader_parameter("grain_strength", _num("--pgs=", 0.32))
					if id == "TRB6-CITY-001" or id == "TRB6-HOUSES-001":
						p.set_shader_parameter("material_kind", 1 if surface == 0 else (2 if surface == 1 else (3 if surface == 2 else (4 if surface == 3 else 0))))
				node.set_surface_override_material(surface, p)

	for child in node.get_children():
		_bind_materials(child, id)


func setup_world() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color("92b6c8")
	sm.sky_horizon_color = Color("c1ccd0")
	sm.ground_horizon_color = Color("b7c1be")
	sm.ground_bottom_color = Color("8c9895")
	sm.sun_angle_max = 1.0
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("c4cbd0")
	env.ambient_light_energy = _num("--amb=", 0.80)
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	# LINEAR tonemap: the filmic curve was lifting every shadow and blowing the
	# whole frame towards 200/255, which is what read as "plastic".
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = _num("--exp=", 1.0)
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color("a4aeb4")
	env.fog_light_energy = 0.62
	env.fog_density = _fog()
	env.fog_sky_affect = 0.30
	env.adjustment_enabled = true
	env.adjustment_saturation = _grade(0, 1.0)
	env.adjustment_contrast = _grade(1, 1.02)
	env.adjustment_brightness = _grade(2, 1.0)
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)

	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -54, 0)
	sun.light_color = Color("fff7e9")
	sun.light_energy = 0.85
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 420.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 0.6
	add_child(sun)

	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.near = 0.1
	camera.far = 1400.0
	add_child(camera)
	camera.make_current()


