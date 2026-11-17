extends RefCounted
## Stable, collision-free local destinations for a selected group of formations.
## Every candidate uses the same traversability mask as find_path(), so a short
## point is never rejected by the click validator while Dijkstra still uses it.

const MAX_DETOUR = 100.0  # 10 m in logical units (10 units/metre)
const CLUSTER_RADIUS = 16.0
const SPREAD = 5.5
const MIN_SPACING = 5.0

static func _open(sim: RefCounted, id: String) -> bool:
	if sim.has_method("is_navigation_open"):return sim.is_navigation_open(id)
	return sim.nodes.has(id) and bool(sim.nodes[id].get("passable",true))

static func plan(control: Node3D, target: String) -> Dictionary:
	var sim=control.simulation
	var positions: Dictionary=control.node_positions
	var ids: Array=control.selected_armies.duplicate()
	if ids.is_empty():return {"error":"Select an army first.","assignments":{}}
	if not sim.nodes.has(target) or not _open(sim,target):
		return {"error":"Move target is blocked or does not exist.","assignments":{}}
	# Grow a local, land-connected cluster of destinations. A ferry edge must
	# never split one click between opposite banks of the same river.
	var candidates: Array=[target];var visited: Dictionary={target:true};var cursor: int=0
	while cursor<candidates.size() and candidates.size()<128:
		var current: String=candidates[cursor];cursor+=1
		for neighbor in sim._sorted_ids(sim.nodes[current].edges):
			if visited.has(neighbor) or not _open(sim,neighbor):continue
			if positions[neighbor].distance_to(positions[target])>CLUSTER_RADIUS:continue
			if sim._crossing_by_edge.has(sim._edge_key(current,neighbor)):continue
			visited[neighbor]=true;candidates.append(neighbor)
	var center:=Vector3.ZERO
	for id in ids:center+=control.army_position(id)
	center/=float(ids.size())
	var forward: Vector3=positions[target]-center;forward.y=0
	if forward.length_squared()<.01:forward=Vector3.FORWARD
	forward=forward.normalized();var side:=Vector3(-forward.z,0,forward.x)
	ids.sort_custom(func(a,b):
		var x: float=(control.army_position(a)-center).dot(side)
		var y: float=(control.army_position(b)-center).dot(side)
		return str(a)<str(b) if is_equal_approx(x,y) else x<y)
	# Validate the entire group before assigning anything. The old code treated
	# an unreachable target as distance 0 and fell back to that invalid target.
	var options: Array=[]
	for index in range(ids.size()):
		var id: String=ids[index]
		if not sim.armies.has(id):return {"error":"Formation is no longer available.","assignments":{}}
		var tree: Dictionary=sim.find_routes_from(sim.armies[id].node)
		if not tree.distance.has(target):
			return {"error":"No valid route for the entire movement group.","assignments":{}}
		var target_dist: float=float(tree.distance[target])
		var desired: Vector3=positions[target]+side*(float(index)-float(ids.size()-1)*.5)*SPREAD
		for candidate in candidates:
			if not _open(sim,candidate) or not tree.distance.has(candidate):continue
			var detour: float=float(tree.distance[candidate])-target_dist
			if detour>MAX_DETOUR:continue
			var cost: float=positions[candidate].distance_squared_to(desired)+maxf(0.0,detour)*5.0
			options.append({"army":id,"node":candidate,"cost":cost})
	options.sort_custom(func(a,b):
		if is_equal_approx(a.cost,b.cost):return str(a.army)+"|"+str(a.node)<str(b.army)+"|"+str(b.node)
		return a.cost<b.cost)
	# Global greedy assignment: each formation gets at most one node and each
	# node at most one formation. Pass 2 relaxes spacing only, never validity.
	var assignments: Dictionary={};var used: Dictionary={}
	for spacing in [MIN_SPACING,-1.0]:
		for option in options:
			var army_id: String=option.army;var node: String=option.node
			if assignments.has(army_id) or used.has(node):continue
			if spacing>0.0:
				var crowded: bool=false
				for other in used:
					if positions[other].distance_to(positions[node])<spacing:crowded=true;break
				if crowded:continue
			assignments[army_id]=node;used[node]=true
		if assignments.size()==ids.size():break
	# Last resort: the click target is open and reachable for every formation, so
	# sharing it is safe. No formation is ever sent to an invalid destination.
	for id in ids:
		if not assignments.has(id):assignments[id]=target
	return {"error":"","assignments":assignments}
