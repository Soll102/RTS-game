extends RefCounted
## Transactional graph routing. Planning never changes an army's location.
const UNREACHABLE: int=2147483647

static func plan(sim: RefCounted, army: Dictionary, destination: String, blocked: Dictionary={}, stable_heading: bool=false) -> Dictionary:
	var start: String=army.node
	if not sim.nodes.has(start) or not sim.nodes.has(destination) or blocked.has(destination):return {"ok":false}
	var avoided: Dictionary=blocked.duplicate();avoided.erase(start)
	var backward: Dictionary=sim.find_path(start,destination,avoided)
	if int(army.edge_progress)==0 or army.route.is_empty():
		if not backward.ok:return {"ok":false}
		return {"ok":true,"node":start,"route":backward.route,"edge_progress":0}
	var next: String=army.route[0]
	var length: int=sim.nodes[start].edges[next]
	var progress: int=int(army.edge_progress)
	var forward: Dictionary={"ok":false,"distance":UNREACHABLE,"route":[]}
	if not blocked.has(next):forward=sim.find_path(next,destination,blocked)
	var forward_cost: int=length-progress+int(forward.distance) if forward.ok else UNREACHABLE
	# Reversing an unequal or one-way edge cannot preserve integer progress and
	# exact position. Finish that edge instead of relocating to another endpoint.
	var reversible: bool=sim.nodes[next].edges.get(start,-1)==length and not blocked.has(start)
	var backward_cost: int=progress+int(backward.distance) if backward.ok and reversible else UNREACHABLE
	if forward_cost==UNREACHABLE and backward_cost==UNREACHABLE:return {"ok":false}
	var margin: int=mini(8,maxi(1,length/10)) if stable_heading else 0
	if forward_cost!=UNREACHABLE and forward_cost<=backward_cost+margin:
		return {"ok":true,"node":start,"route":[next]+forward.route,"edge_progress":progress}
	return {"ok":true,"node":next,"route":[start]+backward.route,"edge_progress":length-progress}

static func commit(army: Dictionary, candidate: Dictionary) -> bool:
	if not candidate.get("ok",false):return false
	for key in ["node","route","edge_progress"]:army[key]=candidate[key]
	return true
