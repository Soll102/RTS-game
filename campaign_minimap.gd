extends Control
const T=preload("res://ui_tokens.gd")
const Ground=preload("res://scripts/rts_world_view.gd")
var app: RefCounted
var map: Node3D
var backdrop: ImageTexture
var _drag: bool=false
var interface: CanvasLayer
var _cached_corners: Array=[]
var _cached_cam_xform: Transform3D
var _cached_rect: Rect2
var _world_bounds:=Rect2(-180,-140,360,280)
var _backdrop_world_id: String=""

func configure(value: RefCounted, scene: Node3D) -> void:
	app=value;map=scene
	mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
	tooltip_text="Left: move camera\nRight: move selected troops\nShift+Right: queue destination"
	rebuild_backdrop()

func rebuild_backdrop() -> void:
	if map==null or map.simulation==null:return
	var wid: String=str(map.simulation.world_metadata.get("id","v8-hills-region"))
	if wid==_backdrop_world_id and backdrop!=null:return
	_backdrop_world_id=wid
	_world_bounds=Rect2(-180,-140,360,280)
	var img:=Image.create(180,140,false,Image.FORMAT_RGB8)
	for z in range(140):
		for x in range(180):
			var wx: float=_world_bounds.position.x+(float(x)/180.0)*_world_bounds.size.x
			var wz: float=_world_bounds.position.y+(float(z)/140.0)*_world_bounds.size.y
			var h: float=float(map.controller.ground_sampler.call(wx,wz))-.15 if map.controller!=null and map.controller.ground_sampler.is_valid() else Ground.height_at(map.heights,wx,wz)
			img.set_pixel(x,z,Color("38545e") if h<.2 else Color("304439").lerp(Color("82916c"),clampf(h/25.0,.15,.65)))
	backdrop=ImageTexture.create_from_image(img)
	_cached_corners.clear();queue_redraw()

func _draw() -> void:
	if app==null or map==null or map.simulation==null or map.controller==null:return
	if backdrop==null or str(map.simulation.world_metadata.get("id","v8-hills-region"))!=_backdrop_world_id:rebuild_backdrop()
	if backdrop==null:return
	draw_texture_rect(backdrop,terrain_rect(),false)
	for city in map.simulation.cities.values():
		if not map.controller.node_positions.has(city.node):continue
		var p: Vector2=_screen(map.controller.node_positions[city.node])
		draw_circle(p,6,T.WORLD_BASE)
		_mark(p,city.owner,4.0 if city.victory_point else 2.5)
	for id in map.simulation.armies:
		if map.simulation.armies[id].troops<=0:continue
		var point:=_screen(map.controller.army_position(id))
		draw_circle(point,4,T.WORLD_BASE);_mark(point,map.simulation.armies[id].faction,2.5)
	for id in map.controller.selected_armies:
		if not map.simulation.armies.has(id):continue
		var destination: String=map.simulation._target_node(map.simulation.armies[id].order)
		if map.controller.node_positions.has(destination):
			var point: Vector2=_screen(map.controller.node_positions[destination]);draw_circle(point,4,T.WORLD_BASE);draw_arc(point,3,0,TAU,12,T.ACCENT,1.4,true)
	var viewport: Vector2=get_viewport().get_visible_rect().size
	var rect: Rect2=interface.map_rect() if interface!=null else Rect2(Vector2(0,56),viewport-Vector2(0,56))
	if _cached_corners.is_empty() or map.camera.global_transform!=_cached_cam_xform or rect!=_cached_rect:
		_cached_cam_xform=map.camera.global_transform
		_cached_rect=rect
		_cached_corners.clear()
		for p in [rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)]:
			var hit=map.controller.ground_picker.call(p) if map.controller!=null and map.controller.ground_picker.is_valid() else Ground.pick_ground(map.camera,map.heights,p)
			if hit!=null:_cached_corners.append(_screen(hit))
		if _cached_corners.size()==4:_cached_corners.append(_cached_corners[0])
	if _cached_corners.size()==5:
		draw_polyline(PackedVector2Array(_cached_corners),T.WORLD_MUTED,1.5,true)
	draw_rect(terrain_rect(),T.DOCK_RULE,false,1)

func _screen(p: Vector3) -> Vector2:
	var rect: Rect2=terrain_rect()
	return rect.position+Vector2((p.x-_world_bounds.position.x)/_world_bounds.size.x*rect.size.x,(p.z-_world_bounds.position.y)/_world_bounds.size.y*rect.size.y)

func _focus(p: Vector2) -> void:
	map.focus_map(_world(p))

func _world(p: Vector2) -> Vector3:
	var rect: Rect2=terrain_rect()
	var point:=Vector3(clampf((p.x-rect.position.x)/rect.size.x,0,1)*_world_bounds.size.x+_world_bounds.position.x,0,clampf((p.y-rect.position.y)/rect.size.y,0,1)*_world_bounds.size.y+_world_bounds.position.y)
	point.y=float(map.controller.ground_sampler.call(point.x,point.z)) if map.controller!=null and map.controller.ground_sampler.is_valid() else Ground.height_at(map.heights,point.x,point.z)
	return point

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_RIGHT and event.pressed and terrain_rect().has_point(event.position):
		var point: Vector3=_world(event.position)
		var target: Dictionary={"kind":"node","id":map.controller.nearest_node(point),"position":point}
		if map.controller.issue_context_order(target,event.shift_pressed).is_empty():map.controller.context_order_accepted.emit(target)
		accept_event();return
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		_drag=event.pressed and terrain_rect().has_point(event.position)
		if _drag:_focus(event.position)
		accept_event()
	if event is InputEventMouseMotion and _drag:_focus(event.position);accept_event()

func _mark(point: Vector2, faction: String, radius: float) -> void:
	var color: Color=T.FACTION[faction]
	if faction=="wei":draw_rect(Rect2(point-Vector2.ONE*radius,Vector2.ONE*radius*2),color)
	elif faction=="shu":draw_colored_polygon(PackedVector2Array([point+Vector2(0,-radius),point+Vector2(radius,radius),point+Vector2(-radius,radius)]),color)
	else:draw_circle(point,radius,color)

func terrain_rect() -> Rect2:
	# World bounds are360x280m; preserve the same9:7 ratio at every viewport size.
	var width: float=minf(size.x,size.y*9.0/7.0)
	var height: float=width*7.0/9.0
	return Rect2((size-Vector2(width,height))*.5,Vector2(width,height))
