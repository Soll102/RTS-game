extends RefCounted
## A downward frustum is contained by a floor below the entire heightfield.
## If eye and floor footprint are inside this convex rectangle, terrain hits
## before that floor cannot expose the background outside the map.

static func footprint(camera: Camera3D, floor_y: float) -> Array:
	var viewport: Vector2=camera.get_viewport().get_visible_rect().size
	var result: Array=[Vector2(camera.global_position.x,camera.global_position.z)]
	for point in [Vector2.ZERO,Vector2(viewport.x,0),viewport,Vector2(0,viewport.y)]:
		var origin: Vector3=camera.project_ray_origin(point);var ray: Vector3=camera.project_ray_normal(point)
		if ray.y>=-.00001:return []
		var distance: float=(floor_y-origin.y)/ray.y
		if distance<=0:return []
		var hit: Vector3=origin+ray*distance
		result.append(Vector2(hit.x,hit.z))
	return result

static func contained(camera: Camera3D, bounds: Rect2, floor_y: float, tolerance: float=.01) -> bool:
	var points: Array=footprint(camera,floor_y)
	if points.size()!=5:return false
	var expanded: Rect2=bounds.grow(tolerance)
	for point in points:
		if not expanded.has_point(point):return false
	return true

static func constrain(camera: Camera3D, desired: Vector3, yaw: float, pitch: float, distance: float, bounds: Rect2, floor_y: float, terrain: Callable) -> Dictionary:
	var target: Vector3=desired
	pitch=clampf(pitch,maxf(deg_to_rad(40),deg_to_rad(camera.fov*.5+6)),deg_to_rad(78))
	distance=clampf(distance,12,420)
	for attempt in range(24):
		target.x=clampf(target.x,bounds.position.x,bounds.end.x);target.z=clampf(target.z,bounds.position.y,bounds.end.y)
		if terrain.is_valid():target.y=float(terrain.call(target.x,target.z))+1
		var offset:=Vector3(sin(yaw)*cos(pitch),sin(pitch),cos(yaw)*cos(pitch))*distance
		camera.position=target+offset
		if terrain.is_valid():camera.position.y=maxf(camera.position.y,float(terrain.call(camera.position.x,camera.position.z))+1.2)
		camera.look_at(target,Vector3.UP)
		var points: Array=footprint(camera,floor_y)
		if points.is_empty():pitch=deg_to_rad(65);distance*=.85;continue
		var low: Vector2=points[0];var high: Vector2=points[0]
		for point in points:low=low.min(point);high=high.max(point)
		var extent: Vector2=high-low
		if extent.x>bounds.size.x-.2 or extent.y>bounds.size.y-.2:
			distance=maxf(12,distance*.8);continue
		var shift:=Vector2.ZERO
		if low.x<bounds.position.x:shift.x=bounds.position.x-low.x+.05
		elif high.x>bounds.end.x:shift.x=bounds.end.x-high.x-.05
		if low.y<bounds.position.y:shift.y=bounds.position.y-low.y+.05
		elif high.y>bounds.end.y:shift.y=bounds.end.y-high.y-.05
		if shift.is_zero_approx():return {"target":target,"pitch":pitch,"distance":distance,"contained":true}
		target.x+=shift.x;target.z+=shift.y
	# Deterministic safe recovery if steep terrain makes an edge correction oscillate.
	target=Vector3(bounds.get_center().x,0,bounds.get_center().y)
	if terrain.is_valid():target.y=float(terrain.call(target.x,target.z))+1
	pitch=deg_to_rad(70);distance=12
	camera.position=target+Vector3(0,sin(pitch),cos(pitch))*distance
	if terrain.is_valid():camera.position.y=maxf(camera.position.y,float(terrain.call(camera.position.x,camera.position.z))+1.2)
	camera.look_at(target,Vector3.UP)
	return {"target":target,"pitch":pitch,"distance":distance,"contained":contained(camera,bounds,floor_y)}
