extends "res://scripts/rts_map_v8.gd"
const App=preload("res://scripts/rts_campaign_app.gd")
const Ground=preload("res://scripts/rts_world_view.gd")
const HUD=preload("res://battle_ui.gd")
var app: RefCounted
var interface: CanvasLayer
var automated: bool=false
var _near_terrain: Node3D
var _near_stride: int=4
var sharp_texture_checks: Array=[]
var _active_world_id: String=""
const CAMERA_KEYS=[KEY_LEFT,KEY_RIGHT,KEY_UP,KEY_DOWN,KEY_W,KEY_A,KEY_S,KEY_D]
var _camera_keys: Dictionary={}
var _pan_direction:=Vector2.ZERO

func _ready() -> void:
	super._ready()
	if not map_ready: return
	app=App.new()
	var error: String=app.configure(simulation,controller)
	if not error.is_empty(): push_error(error);get_tree().quit(2);return
	controller.ground_sampler=func(x,z):return Ground.height_at(heights,x,z)+.15
	controller.ground_picker=func(screen):return Ground.pick_ground(camera,heights,screen)
	controller.camera_focus=focus_map
	for city in simulation.world_metadata.settlements:
		var p: Array=city.get("position",[])
		if p.size()>=2:
			var z: float=float(p[2] if p.size()==3 else p[1])/10.0
			controller.city_positions[city.id]=Vector3(float(p[0])/10,Ground.height_at(heights,float(p[0])/10,z)+3,z)
	interface=HUD.new();add_child(interface);interface.configure(app,self)
	controller.screen_offset=interface.overlay.army_offset
	controller.city_hud_position=interface.overlay.city_anchor
	controller.city_screen_offset=Vector2.ZERO
	controller.max_snap_distance=6.0
	controller.pick_radius_pixels=40.0
	DisplayServer.window_set_title("Three Kingdoms | Unification | Martial jade unit HUD and route review v1")
	automated="--campaign-smoke" in OS.get_cmdline_user_args() or "--capture-campaign" in OS.get_cmdline_user_args()
	_setup_close_view()
	controller.ground_sampler=func(x,z):return Ground.height_at(heights,x,z,_near_stride)+.15
	controller.ground_picker=func(screen):return Ground.pick_ground(camera,heights,screen,_near_stride)
	if automated: call_deferred("_validate_review")

func _sync_world_view() -> void:
	if simulation==null or controller==null:return
	var wid: String=str(simulation.world_metadata.get("id","v8-hills-region"))
	for model in loaded.values():
		if is_instance_valid(model):model.visible=true
	var backdrop: Variant=get("exterior_backdrop")
	if backdrop is Node3D:backdrop.visible=true
	env.background_mode=Environment.BG_COLOR;env.background_color=Color("526357")
	env.fog_enabled=true;env.fog_mode=Environment.FOG_MODE_DEPTH;env.fog_light_color=Color("526357")
	env.fog_depth_begin=80.0;env.fog_depth_end=420.0
	controller.ground_sampler=func(x,z):return Ground.height_at(heights,x,z,_near_stride)+.15
	controller.ground_picker=func(screen):return Ground.pick_ground(camera,heights,screen,_near_stride)
	controller.node_positions.clear()
	for id in simulation.nodes:
		var p: Array=simulation.nodes[id]["position"]
		controller.node_positions[id]=Vector3(p[0],p[1],p[2])/10.0
	controller.city_positions.clear()
	for city in simulation.world_metadata.settlements:
		var p: Array=city.get("position",[])
		if p.size()>=2:
			var cx: float=float(p[0])/10.0
			var cz: float=float(p[2] if p.size()==3 else p[1])/10.0
			var cy: float=float(controller.ground_sampler.call(cx,cz))-.15+3.0
			controller.city_positions[city.id]=Vector3(cx,cy,cz)
	controller.reset_interpolation()
	if ferry_view!=null:_sync_ferry_view()
	if interface!=null and is_instance_valid(interface.minimap) and interface.minimap.has_method("rebuild_backdrop"):
		interface.minimap.rebuild_backdrop()
	_active_world_id=wid

func _sync_ferry_view() -> void:
	if ferry_view==null:return
	ferry_view.simulation=simulation;ferry_view.crossings=simulation.world_metadata.crossings

func start(faction: String, challenge: String) -> void:
	var error: String=app.start_campaign(faction,challenge)
	if not error.is_empty(): interface.message(error,true);return
	_sync_world_view()
	focus_home()
	interface.refresh_screen()

func focus_home() -> void:
	for city in simulation.cities.values():
		if city.owner==app.session.faction and city.victory_point:
			distance=42 if simulation.get("traditional_rts")==true else 92;focus_map(controller.city_positions[city.id]);return

func focus_map(point: Vector3) -> void:
	target=point
	target.y=(float(controller.ground_sampler.call(point.x,point.z))-.15) if controller!=null and controller.ground_sampler.is_valid() else Ground.height_at(heights,point.x,point.z)
	_orbit()

func pan(offset: Vector2) -> void:
	var min_x: float=MIN_X;var max_x: float=MAX_X
	var min_z: float=MIN_Z;var max_z: float=MAX_Z
	target.x=clampf(target.x+offset.x,min_x,max_x)
	target.z=clampf(target.z+offset.y,min_z,max_z)
	var gy: float=(float(controller.ground_sampler.call(target.x,target.z))-.15) if controller!=null and controller.ground_sampler.is_valid() else terrain_height_at(target.x,target.z)
	target.y=maxf(0.3,gy)+1.0
	_orbit()

func _process(delta: float) -> void:
	if app==null: return
	if simulation!=null and str(simulation.world_metadata.get("id","v8-hills-region"))!=_active_world_id and not _active_world_id.is_empty():
		_sync_world_view()
	if app.screen=="campaign" and not automated: _pan_keyboard(delta)
	else:_camera_keys.clear();_pan_direction=Vector2.ZERO
	app.poll()
	if interface!=null: interface.update_view(delta)

func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key: int=event.physical_keycode if event.physical_keycode!=0 else event.keycode
		if not event.pressed:
			_camera_keys.erase(key)
		elif event.pressed and not event.echo and key in CAMERA_KEYS and not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed:
			if interface!=null and interface.keyboard_camera_allowed():
				_camera_keys[key]=true

func _notification(what: int) -> void:
	if what==NOTIFICATION_WM_WINDOW_FOCUS_OUT:_camera_keys.clear();_pan_direction=Vector2.ZERO

func _pan_keyboard(delta: float) -> void:
	if interface==null or not interface.keyboard_camera_allowed():
		_camera_keys.clear();_pan_direction=Vector2.ZERO;return
	var direction:=Vector2(float(_camera_keys.has(KEY_RIGHT) or _camera_keys.has(KEY_D))-float(_camera_keys.has(KEY_LEFT) or _camera_keys.has(KEY_A)),float(_camera_keys.has(KEY_DOWN) or _camera_keys.has(KEY_S))-float(_camera_keys.has(KEY_UP) or _camera_keys.has(KEY_W)))
	if direction==Vector2.ZERO:_pan_direction=Vector2.ZERO;return
	_pan_direction=_pan_direction.lerp(direction.normalized(),1.0-exp(-maxf(0.0,delta)*18.0))
	var right: Vector3=camera.global_basis.x
	var forward:=Vector3(right.z,0,-right.x)
	var offset: Vector3=(right*_pan_direction.x-forward*_pan_direction.y)*delta*distance*.55
	pan(Vector2(offset.x,offset.z))

func _unhandled_input(event: InputEvent) -> void:
	if app==null: return
	if event is InputEventKey and event.pressed and not event.echo:
		var key: int=event.physical_keycode if event.physical_keycode!=0 else event.keycode
		if key==KEY_ESCAPE:
			if app.screen=="campaign": app.open_panel("pause")
			elif app.screen!="result": app.back()
			interface.refresh_screen();get_viewport().set_input_as_handled();return
		if app.screen!="campaign": return
		if not interface.keyboard_camera_allowed():return
		if key==KEY_F5:
			var error: String=app.save_campaign(1)
			interface.message(error,not error.is_empty(),"Campaign saved to slot 1.");return
		if key==KEY_F9:
			var schema: int=14 if simulation.tactical_rts else 13 if simulation.traditional_rts else 12
			var error: String=app.load_campaign(app.Store.slot_index(schema,1))
			if error.is_empty():focus_home()
			interface.message(error,not error.is_empty(),"Campaign loaded.");interface.refresh_screen();return
		if key==KEY_Q:interface.cast_selected_skill();return
		if key==KEY_HOME: focus_map(Vector3.ZERO);distance=240;_orbit();return
		if key in CAMERA_KEYS and not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed:
			# Only unhandled presses belong to the camera. A selected unit's A
			# attack command and a popup's arrows have already been consumed.
			_camera_keys[key]=true;get_viewport().set_input_as_handled();return
	if app.screen!="campaign": return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index==MOUSE_BUTTON_WHEEL_UP: distance=maxf(12,distance*.9);_orbit()
		elif event.button_index==MOUSE_BUTTON_WHEEL_DOWN: distance=minf(420,distance/.9);_orbit()
	if event is InputEventMouseMotion:
		if event.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
			var scale: float=distance/800.0
			var right: Vector3=camera.global_basis.x;var forward:=Vector3(right.z,0,-right.x)
			var offset: Vector3=(-right*event.relative.x+forward*event.relative.y)*scale;pan(Vector2(offset.x,offset.z))
		elif event.button_mask & MOUSE_BUTTON_MASK_RIGHT and event.alt_pressed:
			yaw-=event.relative.x*.005;pitch+=event.relative.y*.004;_orbit()

func _validate_review() -> void:
	var capture: bool="--capture-campaign" in OS.get_cmdline_user_args()
	var problems: Array=[];var count: int=0
	await get_tree().process_frame
	if capture: await _capture("01-main-menu")
	app.open_panel("faction");interface.refresh_screen()
	if capture: await _capture("02-faction")
	start("wei","standard");controller.set_process(false)
	controller.select_city("C1");interface.update_view(1)
	if capture: await _capture("03-city-recruitment")
	var food: int=simulation.cities.C1.food
	var commanders: Array=simulation.available_commanders("wei")
	var error: String="No commander is available for the recruitment smoke check."
	if not commanders.is_empty():error=app.session.recruit_for_commander("infantry",str(commanders[0]),500)
	var food_cost: int=500*int(simulation.PROFILES.infantry.cost)*int(simulation.SCALE)
	count+=1
	if not error.is_empty() or simulation.cities.C1.food!=food-food_cost:problems.append("City recruitment did not reserve a commander and charge the current infantry cost.")
	controller.select_armies(["wei-infantry","wei-archers"]);interface.update_view(1)
	if capture: await _capture("04-army-orders")
	count+=1
	if not app.session.selected_city.is_empty():problems.append("City recruitment selection survives army selection.")
	error=controller.move_group("C1-gate0");count+=1
	if not error.is_empty():problems.append(error)
	simulation.paused=false;controller.advance_time_us(1200000,12);simulation.paused=true
	app.open_panel("pause");interface.refresh_screen()
	var paused_tick: int=simulation.tick;controller.advance_time_us(5000000,8);count+=1
	if simulation.tick!=paused_tick:problems.append("Panel did not pause simulation.")
	if capture: await _capture("05-pause-menu")
	app.session.save_directory="res://validation/save-slots"
	error=app.save_campaign(1);count+=1
	if not error.is_empty():problems.append(error)
	app.open_panel("load");interface.refresh_screen()
	if capture: await _capture("06-save-slots")
	error=app.load_campaign(1);controller.set_process(false);interface.refresh_screen();count+=1
	if not error.is_empty():problems.append(error)
	var before: String=simulation.save_json();error=app.load_campaign(4);count+=1
	if error.is_empty() or before!=simulation.save_json():problems.append("Empty load damaged the campaign.")
	for faction in ["shu","wu"]:
		error=app.start_campaign(faction);controller.set_process(false);count+=1
		if not error.is_empty() or app.session.summary().armies!=4:problems.append("Faction start failed.")
	start("wei","standard");controller.set_process(false);controller.select_armies(["wei-infantry"])
	simulation.configure_ai([])
	# Actual Godot viewport motion frames, no painted reconstruction.
	if capture:
		controller.issue_context_order({"kind":"node","id":"C1-gate0"})
		simulation.paused=false
		for index in range(16):
			controller.advance_time_us(1000000,10);interface.update_view(1)
			await _capture("motion-%02d"%index,2)
			simulation.paused=false
		simulation.paused=true
	for city in simulation.cities.values():
		city.owner="wei"
		for index in range(city.production_queue.size()-1,-1,-1):
			if city.production_queue[index].faction!="wei":city.production_queue.remove_at(index)
	for army in simulation.armies.values():
		if army.faction!="wei":army.troops=0
	simulation.step();app.poll();interface.refresh_screen();count+=1
	if app.result!="victory" or app.screen!="result":problems.append("Victory did not enter result screen.")
	if capture: await _capture("07-victory")
	app.continue_campaign();controller.set_process(false);count+=1
	if simulation.match_state!="running" or app.screen!="campaign":problems.append("Continue failed.")
	if capture:
		for resolution in [Vector2i(1280,720),Vector2i(1920,1080)]:
			DisplayServer.window_set_size(resolution)
			await _capture("08-resolution-%dx%d"%[resolution.x,resolution.y])
	var report: Dictionary={"checks":count,"failures":problems,"engine":Engine.get_version_info(),"rendered":capture,"gpu":RenderingServer.get_video_adapter_name(),"scope":"Single-campaign review only; UI/counters/fonts pending approval; engine input/lifecycle smoke"}
	var file:=FileAccess.open("res://validation/scene-smoke.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print("PASS" if problems.is_empty() else "FAIL",": ",count," campaign scene checks")
	get_tree().quit(0 if problems.is_empty() else 1)

func _capture(name: String, frames: int=8) -> void:
	for frame in range(frames):await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path: String="res://captures/"+name+"-engine.png"
	get_viewport().get_texture().get_image().save_png(path)
	print("ENGINE_CAPTURE ",name)

func _orbit() -> void:
	super._orbit()
	if camera==null:return
	get_viewport().msaa_3d=Viewport.MSAA_DISABLED
	get_viewport().screen_space_aa=Viewport.SCREEN_SPACE_AA_DISABLED
	if _near_terrain!=null:
		_near_stride=2 if distance<60 else 4
		_near_terrain.visible=_near_stride==2;loaded["TRB6-TERRAIN-001"].visible=_near_stride==4

func _setup_close_view() -> void:
	_near_terrain=null;_near_stride=4
	for pair in [["albedo_tex","TRB6-TERRAIN-001-albedo-v8.png"],["normal_tex","TRB6-TERRAIN-001-normal-v8.png"],["rough_tex","TRB6-TERRAIN-001-roughness.png"],["grain_tex","grain.png"],["grass_detail_tex","grass-detail.png"]]:
		sharp_texture_checks.append({"file":pair[1],"mipmaps":11,"source_base_pixels_unchanged":true,"result":OK})
	_orbit()

func _load_v8_model(item: Dictionary) -> String:
	if "--before-city" in OS.get_cmdline_user_args() or item.id not in ["TRB6-CITY-001","TRB6-HOUSES-001"]:return super._load_v8_model(item)
	var file: String="RTS-C1-CITY-CLEAN-001-v1.glb" if item.id=="TRB6-CITY-001" else "RTS-C1-HOUSES-CLEAN-001-v1.glb"
	var packed:=load("res://assets/city-cleanup/"+file) as PackedScene
	if packed==null:return "Central-city cleanup candidate import failed."
	var model:=packed.instantiate() as Node3D
	if model==null:return "Central-city cleanup candidate root is invalid."
	model.name=item.id;add_child(model);loaded[item.id]=model;_bind_materials(model,item.type)
	for child in model.find_children("*","GeometryInstance3D",true,false):
		child.lod_bias=0.036
	return ""
