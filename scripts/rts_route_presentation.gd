extends RefCounted
## Display geometry follows existing graph legs; it never computes a shortcut.

static func _ferry(a: String, b: String, crossings: Array) -> bool:
	for crossing in crossings:
		if a in crossing.nodes and b in crossing.nodes:return true
	return false

static func movement_legs(army: Dictionary, current: Vector3, positions: Dictionary, crossings: Array=[]) -> Array:
	if army.get("troops",0)<=0 or army.get("order",{}).get("type","")=="hold" or not army.get("route") is Array or army.route.is_empty():return []
	if not positions.has(army.node) or not positions.has(army.route[0]):return []
	var result: Array=[];var from: Vector3=current;var previous: String=army.node
	var origin: Vector3=positions[previous];var next: Vector3=positions[army.route[0]]
	var a:=Vector2(origin.x,origin.z);var b:=Vector2(next.x,next.z);var p:=Vector2(current.x,current.z)
	var vector: Vector2=b-a
	var projection: float=(p-a).dot(vector)/maxf(.00001,vector.length_squared())
	var on_edge: bool=projection>=-.001 and projection<=1.001 and p.distance_to(a+vector*projection)<.05
	# At a tick boundary the interpolated marker may still be on the previous edge.
	# Include its corner instead of drawing across the obstacle inside the turn.
	if not on_edge and p.distance_to(a)>.001:
		var kind: String="ground"
		for crossing in crossings:
			if previous not in crossing.nodes or not positions.has(crossing.nodes[0]) or not positions.has(crossing.nodes[1]):continue
			var start: Vector3=positions[crossing.nodes[0]];var end: Vector3=positions[crossing.nodes[1]]
			var edge:=Vector2(end.x-start.x,end.z-start.z);var point:=p-Vector2(start.x,start.z)
			var t: float=point.dot(edge)/maxf(.00001,edge.length_squared())
			if t>=0 and t<=1 and point.distance_to(edge*t)<.05:kind="ferry"
		result.append({"from":from,"to":origin,"kind":kind,"key":"lead"});from=origin
	for id in army.route:
		if not positions.has(id):break
		var to: Vector3=positions[id]
		if Vector2(from.x,from.z).distance_to(Vector2(to.x,to.z))>.001:
			result.append({"from":from,"to":to,"kind":"ferry" if _ferry(previous,id,crossings) else "ground","key":previous+"|"+str(id)})
		from=to;previous=id
	return result

static func sample_leg(leg: Dictionary, ground: Callable, spacing: float=2.0) -> PackedVector3Array:
	var a: Vector3=leg["from"];var b: Vector3=leg["to"]
	var count: int=clampi(ceili(Vector2(a.x,a.z).distance_to(Vector2(b.x,b.z))/maxf(.1,spacing)),1,256)
	var points:=PackedVector3Array()
	for i in range(count+1):
		var p: Vector3=a.lerp(b,float(i)/count)
		if leg.kind=="ferry":p.y=maxf(.32,float(ground.call(p.x,p.z))+.12) if ground.is_valid() else .32
		elif ground.is_valid():p.y=float(ground.call(p.x,p.z))+.12
		points.append(p)
	return points

static func clip_line(a: Vector2, b: Vector2, rect: Rect2) -> PackedVector2Array:
	var delta: Vector2=b-a;var lower: float=0;var upper: float=1
	var p: Array=[-delta.x,delta.x,-delta.y,delta.y]
	var q: Array=[a.x-rect.position.x,rect.end.x-a.x,a.y-rect.position.y,rect.end.y-a.y]
	for i in range(4):
		if absf(p[i])<.00001:
			if q[i]<0:return PackedVector2Array()
			continue
		var ratio: float=q[i]/p[i]
		if p[i]<0:lower=maxf(lower,ratio)
		else:upper=minf(upper,ratio)
		if lower>upper:return PackedVector2Array()
	return PackedVector2Array([a+delta*lower,a+delta*upper])
