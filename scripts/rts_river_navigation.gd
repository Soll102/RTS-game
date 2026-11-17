extends RefCounted
## Navigation derived from the approved river triangles, never from its shading texture.
const CURRENT_PATH="res://data/v8-world-next.json"
const LEGACY_PATH="res://data/v8-world.json"
static var _world_cache: Dictionary={}
var nodes: Dictionary={}
var components: Dictionary={}
var polygons: Array=[]
var spans: Dictionary={}
var _routes: Dictionary={}

static func load_world(legacy: bool=false, _world_id: String="") -> Dictionary:
	var path: String=LEGACY_PATH if legacy else CURRENT_PATH
	if _world_cache.has(path):return _world_cache[path].duplicate(true)
	var data=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary:return {}
	data.sha256=FileAccess.get_sha256(path)
	_world_cache[path]=data
	return data.duplicate(true)

## One authoritative traversability mask used by routing, click snapping and
## group destination assignment. Previously the click validator rejected 205
## nodes (an inflated wall/formation footprint) while Dijkstra only looked at
## the `passable` flag, so routing happily used the "blocked" short cut and
## valid short destinations were rejected. Walls are now tested at the node
## centre; water uses the compact formation footprint (half = 1 m = 10 units).
## Gates, settlements, ferry endpoints and docks stay usable by design.
static func blocked_nodes(world: Dictionary, graph: Dictionary) -> Dictionary:
	var blocked: Dictionary={}
	var spans: Dictionary=world.get("water_spans",{})
	var walls: Array=world.get("los_walls",[])
	var reserved: Dictionary={}
	for settlement in world.get("settlements",[]):
		reserved[str(settlement.get("node",""))]=true
		for gate in settlement.get("gate_nodes",[]):reserved[str(gate)]=true
	for crossing in world.get("crossings",[]):
		for endpoint in crossing.get("nodes",[]):reserved[str(endpoint)]=true
		for dock in crossing.get("docks",[]):reserved[str(dock)]=true
	for id in graph:
		if reserved.has(str(id)):continue
		var node: Dictionary=graph[id]
		if not bool(node.get("passable",true)):blocked[id]=true;continue
		var p: Array=node.get("position",[])
		if p.size()<3:continue
		var x: float=float(p[0]);var z: float=float(p[2])
		if _water_at(spans,x,z) or not _dry_footprint(spans,x,z,10.0) or _wall_at(walls,x,z):blocked[id]=true
	return blocked

static func _water_at(spans: Dictionary, x: float, z: float) -> bool:
	for column in [floori(x),ceili(x)]:
		for interval in spans.get(str(column),[]):
			if interval is Array and interval.size()>=2 and z>=float(interval[0]) and z<=float(interval[1]):return true
	return false

static func _dry_footprint(spans: Dictionary, x: float, z: float, half: float) -> bool:
	var count: int=ceili(half*2.0/20.0)+1
	for i in range(count):
		for j in range(count):
			var px: float=x-half+minf(float(i)*20.0,half*2.0)
			var pz: float=z-half+minf(float(j)*20.0,half*2.0)
			if _water_at(spans,px,pz):return false
	return true

static func _wall_at(walls: Array, x: float, z: float) -> bool:
	for wall in walls:
		if wall is Array and wall.size()>=4 and absf(x-float(wall[0]))<=float(wall[2]) and absf(z-float(wall[1]))<=float(wall[3]):return true
	return false

func configure(world: Dictionary) -> void:
	var navigation: Dictionary=world.get("water_navigation",{})
	nodes=navigation.get("nodes",{});components=navigation.get("components",{});spans=world.get("water_spans",{});polygons.clear();_routes.clear()
	for loop in world.get("water_polygons",[]):
		var polygon:=PackedVector2Array()
		for p in loop:polygon.append(Vector2(p[0],p[1]))
		polygons.append(polygon)

func contains(point: Vector2) -> bool:
	for column in [floori(point.x),ceili(point.x)]:
		for interval in spans.get(str(column),[]):
			if point.y>=interval[0] and point.y<=interval[1]:return true
	return false

func dry_footprint(point: Vector2, half: Vector2) -> bool:
	for x in range(ceili(half.x*2/20)+1):
		for z in range(ceili(half.y*2/20)+1):
			var p:=point-half+Vector2(minf(x*20,half.x*2),minf(z*20,half.y*2))
			if contains(p):return false
	return true

func position(id: String) -> Vector3:
	var p: Array=nodes[id].position
	return Vector3(p[0],p[1],p[2])

func route(start: String, destination: String) -> Dictionary:
	var key: String=start+"|"+destination
	if _routes.has(key):return _routes[key]
	if not nodes.has(start) or not nodes.has(destination) or components.get(start)!=components.get(destination):return {"ok":false,"route":[],"distance":0}
	if start==destination:return {"ok":true,"route":[start],"distance":0}
	var distances: Dictionary={start:0};var previous: Dictionary={};var open: Array=[start];var visited: Dictionary={}
	while not open.is_empty():
		open.sort_custom(func(a,b):return str(a)<str(b) if distances[a]==distances[b] else distances[a]<distances[b])
		var current: String=open.pop_front()
		if visited.has(current):continue
		visited[current]=true
		if current==destination:break
		var neighbors: Array=nodes[current].edges.keys();neighbors.sort()
		for other in neighbors:
			var distance: int=int(distances[current])+int(nodes[current].edges[other])
			if not distances.has(other) or distance<int(distances[other]):
				distances[other]=distance;previous[other]=current;open.append(other)
	if not distances.has(destination):return {"ok":false,"route":[],"distance":0}
	var result: Array=[destination];var cursor: String=destination
	while cursor!=start:cursor=previous[cursor];result.push_front(cursor)
	var data: Dictionary={"ok":true,"route":result,"distance":int(distances[destination])}
	if _routes.size()>=256:_routes.erase(_routes.keys()[0])
	_routes[key]=data
	return data

func sample(path: Array, progress: float) -> Vector3:
	if path.is_empty():return Vector3.ZERO
	var lengths: Array=[];var total: float=0.0
	for i in range(path.size()-1):
		var length: float=position(path[i]).distance_to(position(path[i+1]));lengths.append(length);total+=length
	var remaining: float=clampf(progress,0,1)*total
	for i in range(lengths.size()):
		if remaining<=float(lengths[i]):return position(path[i]).lerp(position(path[i+1]),remaining/maxf(.001,float(lengths[i])))
		remaining-=float(lengths[i])
	return position(path[-1])
