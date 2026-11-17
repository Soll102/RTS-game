extends RefCounted
## A quiet ground destination ring and one route-aligned chevron.
const MOVE_COLOR:=Color("e6c56f")
const ACTION_COLOR:=Color("e9ad96")
const MOVE_EDGE:=Color("392711")
const ACTION_EDGE:=Color("4b211a")
const DURATION_MSEC:=1300
const ARROW_COUNT:=1
const Geo=preload("res://overlay_geometry.gd")

static func empty_metrics() -> Dictionary:
	return {"groups":0,"arrows":0,"blocked_arrows":0,"ring_segments":0,"anchors":[],"tips":[],"polygons":[],"ring":[],"color":Color.TRANSPARENT,"progress":1.0}

static func progress(started_msec: int, now_msec: int) -> float:
	return clampf(float(now_msec-started_msec)/DURATION_MSEC,0,1)

static func opacity(phase: float) -> float:
	return clampf(phase/.05,0,1)*(1.0-smoothstep(.60,1.0,phase))

static func sample(camera: Camera3D, sampler: Callable, center: Vector3, started_msec: int, now_msec: int, action: String, direction: Vector3=Vector3.FORWARD) -> Dictionary:
	var result:=empty_metrics()
	if camera==null or not sampler.is_valid() or not center.is_finite():return result
	var phase:=progress(started_msec,now_msec);result.progress=phase
	if now_msec<started_msec or phase>=1 or camera.is_position_behind(center):return result
	var alpha:=opacity(phase)
	if alpha<=.001:return result
	result.color=Color(MOVE_COLOR if action=="Move" else ACTION_COLOR,alpha)
	result.edge=Color(MOVE_EDGE if action=="Move" else ACTION_EDGE,alpha);result.groups=1
	var right:=camera.global_basis.x;right.y=0;right=right.normalized()
	var back:=Vector3(-right.z,0,right.x)
	var screen:=camera.unproject_position(center)
	var pixels_per_metre: float=maxf(.1,camera.unproject_position(center+right).distance_to(screen))
	var radius: float=clampf(18.0/pixels_per_metre,.55,2.6)
	for index in range(49):
		var angle: float=TAU*index/48.0
		var point: Vector3=center+(right*cos(angle)+back*sin(angle))*radius
		point.y=float(sampler.call(point.x,point.z))+.14
		if camera.is_position_behind(point):return empty_metrics()
		result.ring.append(camera.unproject_position(point))
	direction.y=0
	if direction.length_squared()<.0001:direction=Vector3.FORWARD
	direction=direction.normalized();var side:=Vector3(-direction.z,0,direction.x)
	var polygon:=PackedVector2Array()
	for point in [center+direction*radius*.7,center-direction*radius*.4+side*radius*.48,center-direction*radius*.13,center-direction*radius*.4-side*radius*.48]:
		point.y=float(sampler.call(point.x,point.z))+.16
		polygon.append(camera.unproject_position(point))
	result.anchors.append(center);result.tips.append(center+direction*radius*.7);result.polygons.append(polygon)
	return result

static func draw(canvas: Control, camera: Camera3D, sampler: Callable, center: Vector3, started_msec: int, now_msec: int, action: String, viewport: Rect2, blockers: Array, direction: Vector3=Vector3.FORWARD) -> Dictionary:
	var result:=sample(camera,sampler,center,started_msec,now_msec,action,direction)
	for index in range(maxi(0,result.ring.size()-1)):
		for part in Geo.visible_line(result.ring[index],result.ring[index+1],viewport,blockers):
			canvas.draw_line(part[0],part[1],result.edge,3.2,true)
			canvas.draw_line(part[0],part[1],result.color,1.5,true);result.ring_segments+=1
	for polygon in result.polygons:
		var bounds:=Rect2(polygon[0],Vector2.ZERO)
		for point in polygon:bounds=bounds.expand(point)
		if not Geo.visible_box(bounds.grow(2),viewport,blockers):result.blocked_arrows+=1;continue
		canvas.draw_colored_polygon(polygon,result.color)
		var outline: PackedVector2Array=polygon.duplicate();outline.append(polygon[0]);canvas.draw_polyline(outline,result.edge,1.2,true)
		result.arrows+=1
	if result.arrows==0 and result.ring_segments==0:result.groups=0
	return result
