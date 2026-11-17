extends "res://campaign_game.gd"
const OverviewCamera=preload("res://scripts/rts_overview_camera.gd")
var overview_maximum: float=420.0
var overview_pan_freedom: float=1.0
var _camera_high: float=0.0
var _camera_low: float=0.0
var _desired_pitch: float=.6
var _last_camera_pitch: float=NAN
var _desired_yaw: float=0.0
var _last_camera_yaw: float=NAN
var _zoom_goal: float=NAN
var _camera_extents_ready: bool=false
var _camera_height_count: int=0

func _process(delta: float) -> void:
	super._process(delta)
	if app==null or app.screen!="campaign":_zoom_goal=NAN;return
	if not is_finite(_zoom_goal):return
	# The fit maximum can shrink after a resize; re-clamp so the goal can
	# still converge instead of forcing _orbit() to run on every frame.
	if is_finite(overview_maximum):_zoom_goal=clampf(_zoom_goal,12.0,overview_maximum)
	distance=lerpf(distance,_zoom_goal,1.0-exp(-maxf(0.0,delta)*20.0))
	if absf(distance-_zoom_goal)<.01:distance=_zoom_goal;_zoom_goal=NAN
	_orbit()

func focus_map(point: Vector3) -> void:
	_zoom_goal=NAN;_pan_direction=Vector2.ZERO
	super.focus_map(point)

func _request_zoom(factor: float) -> void:
	_zoom_goal=clampf((_zoom_goal if is_finite(_zoom_goal) else distance)*factor,12.0,overview_maximum)

func verify_v8() -> bool:
	var manifest=JSON.parse_string(FileAccess.get_file_as_string("res://release-integrity.json"))
	var acceptance=JSON.parse_string(FileAccess.get_file_as_string("res://campaign-acceptance.json"))
	if not manifest is Dictionary or manifest.get("scope")!="installed_campaign":push_error("Installed game integrity is missing.");return false
	if not acceptance is Dictionary or acceptance.get("status")!="accepted_as_is" or acceptance.get("approval_message","").is_empty():push_error("Human acceptance record is missing.");return false
	if not manifest.get("files") is Array or manifest.files.is_empty():push_error("Installed dependencies are missing.");return false
	for row in manifest.files:
		if FileAccess.get_sha256("res://"+row.file)!=row.sha256:push_error("Installed dependency changed: "+row.file);return false
	return true

func _ready() -> void:
	super._ready()
	if map_ready:DisplayServer.window_set_title("Three Kingdoms | Unification")

func _orbit() -> void:
	if camera==null or heights.is_empty():return
	if not _camera_extents_ready or _camera_height_count!=heights.size():
		_camera_low=heights[0]
		_camera_high=heights[0]
		for height in heights:
			_camera_low=minf(_camera_low,height)
			_camera_high=maxf(_camera_high,height)
		_camera_height_count=heights.size()
		_camera_extents_ready=true
	if is_finite(pitch) and (not is_finite(_last_camera_pitch) or not is_equal_approx(pitch,_last_camera_pitch)):_desired_pitch=pitch
	if is_finite(yaw) and (not is_finite(_last_camera_yaw) or not is_equal_approx(yaw,_last_camera_yaw)):_desired_yaw=yaw
	var bounds: Rect2=Rect2(MIN_X,MIN_Z,MAX_X-MIN_X,MAX_Z-MIN_Z)
	# A perfectly flat heightfield must still give the fit solver a vertical span.
	var cam_high: float=maxf(_camera_high,_camera_low+1.0)
	var surface_cb: Callable=_camera_surface_height
	var value: Dictionary=OverviewCamera.constrain(camera,target,_desired_yaw,_desired_pitch,distance,bounds,_camera_low,cam_high,surface_cb)
	target=value.target;pitch=value.pitch;yaw=value.heading;distance=value.distance;overview_maximum=value.maximum;overview_pan_freedom=value.pan_freedom
	_last_camera_pitch=pitch
	_last_camera_yaw=yaw
	get_viewport().msaa_3d=Viewport.MSAA_DISABLED;get_viewport().screen_space_aa=Viewport.SCREEN_SPACE_AA_DISABLED
	if _near_terrain!=null:
		_near_stride=2 if distance<60 else 4
		_near_terrain.visible=_near_stride==2;loaded["TRB6-TERRAIN-001"].visible=_near_stride==4

func _unhandled_input(event: InputEvent) -> void:
	if app!=null and app.screen=="campaign" and event is InputEventMouseButton and event.pressed:
		if event.button_index==MOUSE_BUTTON_WHEEL_UP:_request_zoom(.9);return
		if event.button_index==MOUSE_BUTTON_WHEEL_DOWN:_request_zoom(1.0/.9);return
	super._unhandled_input(event)
