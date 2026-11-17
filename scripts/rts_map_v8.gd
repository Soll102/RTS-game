extends "res://scripts/rts_map_v8_base.gd"
## Exact approved v8 Low view plus validated campaign state. New visuals gated.
const ChunkMesh=preload("res://scripts/rts_terrain_chunks.gd")
const Scenario=preload("res://scripts/commander_scenario.gd")
const Controller=preload("res://scripts/rts_controller.gd")
const FerryView=preload("res://scripts/rts_ferry_view.gd")
var simulation: RefCounted
var controller: Node3D
var validation_busy: bool=false
var map_ready: bool=false
var views: Array=[]
var ferry_view: Node3D

func _ready() -> void:
	validation_busy="--map-smoke" in OS.get_cmdline_user_args() or "--capture-v8" in OS.get_cmdline_user_args()
	if not verify_v8(): get_tree().quit(2); return
	heights=FileAccess.get_file_as_bytes(MAP_DIR+"terrain-heights.f32").to_float32_array()
	if heights.size()!=GRID_WIDTH*GRID_DEPTH: push_error("Invalid v8 height data."); get_tree().quit(2); return
	camera_floor_y=heights[0]-2
	for height in heights:camera_floor_y=minf(camera_floor_y,height-2)
	setup_world()
	var terrain: Node3D=load("res://render-cache/terrain-stride4.scn").instantiate() if ResourceLoader.exists("res://render-cache/terrain-stride4.scn") else ChunkMesh.create(heights,4)
	add_child(terrain); loaded["TRB6-TERRAIN-001"]=terrain
	_bind_materials(terrain,"TRB6-TERRAIN-001")
	sun.shadow_enabled=false
	get_viewport().msaa_3d=Viewport.MSAA_DISABLED
	get_viewport().mesh_lod_threshold=4.0
	var resources: Array=JSON.parse_string(FileAccess.get_file_as_string(MAP_DIR+"scene-resources.json"))
	var vegetation: Array=JSON.parse_string(FileAccess.get_file_as_string(MAP_DIR+"vegetation-chunks.json"))
	for item in resources:
		if item["type"] in ["TRB6-TERRAIN-001","TRB6-FOREST-001","TRB6-GRASS-001"]: continue
		var resource_error: String=_load_v8_model(item)
		if not resource_error.is_empty(): push_error(resource_error);get_tree().quit(2);return
	for item in vegetation:
		var vegetation_error: String=_load_v8_model(item)
		if not vegetation_error.is_empty(): push_error(vegetation_error);get_tree().quit(2);return
	# The frozen review view poses, represented as data by the integration tool.
	views=JSON.parse_string(FileAccess.get_file_as_string(MAP_DIR+"views.json"))
	apply_shot(0)
	simulation=Scenario.create()
	if simulation==null: get_tree().quit(2); return
	simulation.paused=true
	controller=Controller.new()
	var positions: Dictionary={}
	for id in simulation.nodes:
		var p: Array=simulation.nodes[id]["position"]
		positions[id]=Vector3(p[0],p[1],p[2])/10.0
	var error: String=controller.configure(simulation,positions,{},"gameplay",[])
	if not error.is_empty(): push_error(error); get_tree().quit(2); return
	controller.controls_enabled=false
	controller.set_process(false)
	add_child(controller); controller.attach_camera(camera)
	if not validation_busy:
		ferry_view=FerryView.new()
		add_child(ferry_view)
		var ferry_error: String=ferry_view.configure(simulation)
		if not ferry_error.is_empty(): push_error(ferry_error);get_tree().quit(2);return
	map_ready=true
	get_viewport().size_changed.connect(_orbit)
	_orbit()
	DisplayServer.window_set_title("Three Kingdoms | Approved v8 Map | Low | Campaign visuals pending review")
	if "--map-smoke" in OS.get_cmdline_user_args(): _run_v8_validation()
	elif "--capture-v8" in OS.get_cmdline_user_args(): _capture_v8()

func verify_v8() -> bool:
	var approval=JSON.parse_string(FileAccess.get_file_as_string(MAP_DIR+"approval.json"))
	if not approval is Dictionary or approval.get("status")!="approved" or approval.get("revision")!="hills-v2": push_error("V8 exact map approval is required."); return false
	var entries=JSON.parse_string(FileAccess.get_file_as_string(MAP_DIR+"approved-assets.json"))
	if not entries is Array or entries.size()!=265: push_error("V8 integration manifest is invalid."); return false
	for e in entries:
		if FileAccess.get_sha256(MAP_DIR+str(e["integrated_file"]).get_file())!=e["sha256"]:
			push_error("Approved v8 file changed: "+str(e["id"])); return false
	return true

func _load_v8_model(item: Dictionary) -> String:
	var packed:=load(MAP_DIR+str(item["file"]).get_file()) as PackedScene
	if packed==null: return "V8 model import failed. Import the project before playing: "+str(item["file"])
	var instance: Node=packed.instantiate()
	if not instance is Node3D:
		if instance!=null: instance.free()
		return "V8 model root must be Node3D: "+str(item["file"])
	var model: Node3D=instance
	model.name=item["id"]; add_child(model); loaded[item["id"]]=model
	_bind_materials(model,item["type"])
	if item["type"]=="TRB6-FOREST-001":
		for child in model.get_children():
			if child is GeometryInstance3D:
				child.lod_bias=0.02
				child.visibility_range_end=220.0
	if item.has("center") and item["type"]=="TRB6-GRASS-001":
		for child in model.get_children():
			if child is GeometryInstance3D:
				child.lod_bias=0.05
				child.visibility_range_end=68.0
	if item["type"] in ["TRB6-CITY-001","TRB6-HOUSES-001"]:
		for child in model.find_children("*","GeometryInstance3D",true,false):
			child.lod_bias=0.036
	return ""

func apply_shot(index: int) -> void:
	if index<0 or index>=views.size() or camera==null: return
	var shot: Dictionary=views[index]
	var p: Array=shot["target"]; target=Vector3(p[0],p[1],p[2])
	var e: Array=shot.get("eye",[])
	if e.is_empty(): target.y=terrain_height_at(target.x,target.z)+1.2; camera.position=target+Vector3(22,18,27)
	else: camera.position=Vector3(e[0],e[1],e[2])
	camera.fov=shot["fov"]; camera.look_at(target,Vector3.UP)
	var offset:=camera.position-target; distance=offset.length()
	yaw=atan2(offset.x,offset.z); pitch=asin(clampf(offset.y/distance,-1,1))
	_orbit()

func _process(delta: float) -> void:
	if not validation_busy and map_ready: super._process(delta)

func _unhandled_input(event: InputEvent) -> void:
	if validation_busy: return
	super._unhandled_input(event)

func _report_path() -> String:
	return ProjectSettings.globalize_path("res://../reports/v8-gameplay-validation")

func _capture_v8() -> void:
	DirAccess.make_dir_recursive_absolute(_report_path())
	for index in [0,1,4,16,18]:
		apply_shot(index)
		for frame in range(12): await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var path:=_report_path()+"/v8-"+str(views[index]["name"])+"-engine.png"
		get_viewport().get_texture().get_image().save_png(path)
		print("ENGINE_CAPTURE ",path)
	get_tree().quit()

func _run_v8_validation() -> void:
	var errors: Array=[]
	if loaded.size()!=124: errors.append("Unexpected v8 model/chunk count.")
	if simulation.cities.size()!=11 or simulation.armies.size()!=12: errors.append("Invalid campaign setup.")
	if not simulation.paused or controller.controls_enabled: errors.append("Unreviewed campaign display is enabled.")
	var terrain: Node3D=loaded["TRB6-TERRAIN-001"]
	if terrain.get_child_count()!=63: errors.append("Terrain chunk count is invalid.")
	for index in range(views.size()):
		apply_shot(index)
		if not camera.position.is_finite() or not target.is_finite(): errors.append("Invalid camera pose.")
	_check_keyboard_pan()
	errors.append_array(failures)
	var report: Dictionary={"failures":errors,"engine":Engine.get_version_info(),"map_bundle":"TRB8-HILLS-005 v8 / hills-v2",
		"scope":"Exact approved Low map plus paused campaign state; no unapproved army/HUD/boat visual",
		"models":loaded.size(),"terrain_chunks":terrain.get_child_count(),"views":views.size(),"navigation_nodes":simulation.nodes.size(),
		"settlements":simulation.cities.size(),"armies_data_only":simulation.armies.size(),"ferries_data_only":simulation.world_metadata["crossings"].size(),
		"keyboard_camera_checks":checks,
		"gpu":RenderingServer.get_video_adapter_name()}
	DirAccess.make_dir_recursive_absolute(_report_path())
	var file:=FileAccess.open(_report_path()+"/map-smoke.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	print("PASS" if errors.is_empty() else "FAIL",": v8 map + world validation ",JSON.stringify(report))
	get_tree().quit(0 if errors.is_empty() else 1)
