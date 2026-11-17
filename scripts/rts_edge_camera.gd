extends RefCounted
## Target stays on the playable map; the frustum may see the reviewed exterior backdrop.
## Zoom is one fixed interval, never repeatedly shrunk to fit the terrain rectangle.
const MIN_DISTANCE:=12.0
const MAX_DISTANCE:=420.0
const LEGACY=preload("res://scripts/rts_camera_bounds.gd")

static func constrain(camera: Camera3D, desired: Vector3, heading: float, elevation: float, zoom: float, bounds: Rect2, _floor_y: float, terrain: Callable) -> Dictionary:
	var target:=Vector3(clampf(desired.x,bounds.position.x,bounds.end.x),desired.y,clampf(desired.z,bounds.position.y,bounds.end.y))
	var pitch: float=clampf(elevation,maxf(deg_to_rad(40),deg_to_rad(camera.fov*.5+6)),deg_to_rad(78))
	var distance: float=clampf(zoom,MIN_DISTANCE,MAX_DISTANCE)
	if terrain.is_valid():target.y=float(terrain.call(target.x,target.z))+1.0
	var eye: Vector3=target+Vector3(sin(heading)*cos(pitch),sin(pitch),cos(heading)*cos(pitch))*distance
	# Terrain is only sampled inside its real footprint; the exterior is decorative.
	if terrain.is_valid() and bounds.grow(.01).has_point(Vector2(eye.x,eye.z)):
		eye.y=maxf(eye.y,float(terrain.call(eye.x,eye.z))+1.2)
	camera.position=eye;camera.look_at(target,Vector3.UP)
	return {"target":target,"pitch":pitch,"distance":distance,"center_on_map":true,"zoom_at_limit":distance==MIN_DISTANCE or distance==MAX_DISTANCE}

static func footprint(camera: Camera3D, floor_y: float) -> Array:return LEGACY.footprint(camera,floor_y)
