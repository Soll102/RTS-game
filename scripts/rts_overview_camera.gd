extends RefCounted
## The farthest view is the closest distance that fits the map's complete bounds.
const MIN_DISTANCE:=12.0

static func elevation(camera: Camera3D, pitch: float) -> float:
	return clampf(pitch,maxf(deg_to_rad(40),deg_to_rad(camera.fov*.5+6)),deg_to_rad(78))

static func fit_distance(camera: Camera3D, heading: float, pitch: float, bounds: Rect2, low_y: float, high_y: float, center_y: float) -> float:
	var viewport: Vector2=camera.get_viewport().get_visible_rect().size
	var aspect: float=maxf(.1,viewport.x/maxf(1,viewport.y))
	var tangent: float=tan(deg_to_rad(camera.fov*.5))
	var tan_y: float=tangent if camera.keep_aspect==Camera3D.KEEP_HEIGHT else tangent/aspect
	var tan_x: float=tangent*aspect if camera.keep_aspect==Camera3D.KEEP_HEIGHT else tangent
	# Keep a small screen margin for border geometry/labels, not large exterior space.
	tan_x*=.94;tan_y*=.88
	var back:=Vector3(sin(heading)*cos(pitch),sin(pitch),cos(heading)*cos(pitch))
	var right:=Vector3(cos(heading),0,-sin(heading));var up:=back.cross(right)
	var center:=Vector3(bounds.get_center().x,center_y,bounds.get_center().y)
	var required: float=MIN_DISTANCE
	for x in [bounds.position.x,bounds.end.x]:
		for z in [bounds.position.y,bounds.end.y]:
			for y in [low_y,high_y]:
				var relative:=Vector3(x,y,z)-center
				var toward_eye: float=relative.dot(back)
				required=maxf(required,toward_eye+maxf(absf(relative.dot(right))/tan_x,absf(relative.dot(up))/tan_y))
	return required

static func constrain(camera: Camera3D, desired: Vector3, heading: float, requested_pitch: float, zoom: float, bounds: Rect2, low_y: float, high_y: float, terrain: Callable) -> Dictionary:
	var near_pitch: float=elevation(camera,requested_pitch)
	var far_pitch: float=maxf(near_pitch,deg_to_rad(65))
	var viewport: Vector2=camera.get_viewport().get_visible_rect().size
	# Align the long map axis with the long screen axis at overview, avoiding
	# the unnecessary distance needed to fit a diagonal rectangle.
	var base_heading: float=0.0 if viewport.x>=viewport.y else PI*.5
	var far_heading: float=base_heading+roundf((heading-base_heading)/PI)*PI
	var center: Vector2=bounds.get_center()
	var center_y: float=float(terrain.call(center.x,center.y))+1.0
	var maximum: float=fit_distance(camera,far_heading,far_pitch,bounds,low_y,high_y,center_y)
	var distance: float=clampf(zoom,MIN_DISTANCE,maximum)
	var transition: float=smoothstep(maximum*.70,maximum,distance)
	var freedom: float=1.0-transition
	var pitch: float=lerpf(near_pitch,far_pitch,transition)
	var actual_heading: float=lerp_angle(heading,far_heading,transition)
	var half: Vector2=bounds.size*.5*freedom
	var target:=Vector3(clampf(desired.x,center.x-half.x,center.x+half.x),0,clampf(desired.z,center.y-half.y,center.y+half.y))
	target.y=float(terrain.call(target.x,target.z))+1.0
	var eye:=target+Vector3(sin(actual_heading)*cos(pitch),sin(pitch),cos(actual_heading)*cos(pitch))*distance
	if bounds.grow(.01).has_point(Vector2(eye.x,eye.z)):eye.y=maxf(eye.y,float(terrain.call(eye.x,eye.z))+1.2)
	camera.position=eye;camera.look_at(target,Vector3.UP)
	return {"target":target,"pitch":pitch,"heading":actual_heading,"distance":distance,"maximum":maximum,"pan_freedom":freedom}
