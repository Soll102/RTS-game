extends RefCounted
const Rules=preload("res://scripts/rts_tactical_rules.gd")
const Orders=preload("res://scripts/rts_tactical_orders.gd")
const NavigationPlan=preload("res://scripts/rts_navigation_plan.gd")
const FRIENDLY_RADIUS={"infantry":22.0,"archers":22.0,"cavalry":36.0,"siege":28.0}

static func _enemy(sim: RefCounted, army: Dictionary, id: String) -> bool:
	return Orders.field_enemy(sim,army,id)

static func _acquire(sim: RefCounted, army: Dictionary) -> String:
	var radius: float=160.0 if army.unit_type=="archers" else Rules.ACQUIRE_RANGE
	var current: String=army.combat_target
	if _enemy(sim,army,current) and sim._point(army).distance_to(sim._point(sim.armies[current]))<=radius*1.5:return current
	var best: String="";var distance: float=radius
	for id in sim._sorted_ids(sim.armies):
		if not _enemy(sim,army,id):continue
		var length: float=sim._point(army).distance_to(sim._point(sim.armies[id]))
		if length<distance and sim.has_line_of_sight(army,sim.armies[id]):best=id;distance=length
	return best

static func _route(sim: RefCounted, army: Dictionary, destination: String, blocked: Dictionary={}) -> bool:
	# Chasing/recovery only replace route geometry, not order, siege or ferry state.
	return NavigationPlan.commit(army,NavigationPlan.plan(sim,army,destination,blocked,true))

static func _blockers(sim: RefCounted, army: Dictionary, destination: String) -> Dictionary:
	var blocked: Dictionary={}
	for other in sim.armies.values():
		if other.id==army.id or other.troops<=0 or other.transport_elapsed>0 or not other.get("resident_city","").is_empty():continue
		var friendly: bool=other.faction==army.faction
		if friendly and other.order.type!="hold" and not other.route.is_empty():continue
		var radius: float=_friendly_spacing(army,other) if friendly else 24.0
		# Include every nearby graph point: cavalry footprints can span several edges.
		for node in sim.nodes:
			var point: Array=sim.nodes[node].position
			if Vector2(point[0],point[2]).distance_to(sim._point(other))<radius:blocked[node]=true
	blocked.erase(army.node);blocked.erase(destination)
	return blocked

static func _separating(army: Dictionary, start: Vector2, next: Vector2, opponent: Vector2, min_dist: float=16.0) -> bool:
	if army.order.type in ["move","retreat"]:
		if next.distance_to(opponent)>=start.distance_to(opponent)-0.25:return true
		if next.distance_to(opponent)>=min_dist*0.6:return true
		return false
	return next.distance_squared_to(opponent)>start.distance_squared_to(opponent)+.001

static func _friendly_spacing(army: Dictionary, other: Dictionary) -> float:
	return float(FRIENDLY_RADIUS.get(army.unit_type,18.0))+float(FRIENDLY_RADIUS.get(other.unit_type,18.0))

static func _block_friendly_pair(id: String, other: String, p: Vector2, q: Vector2, a: Vector2, b: Vector2, allow_arrival_a: bool, allow_arrival_b: bool, blocked: Dictionary, sim: RefCounted) -> void:
	var delta_a: Vector2=a-p;var delta_b: Vector2=b-q
	var moving_a: bool=delta_a.length_squared()>.00001;var moving_b: bool=delta_b.length_squared()>.00001
	if not moving_a and not moving_b:return
	if moving_a and moving_b and delta_a.normalized().dot(delta_b.normalized())<.35:return
	var spacing: float=_friendly_spacing(sim.armies[id],sim.armies[other])
	if moving_a and not moving_b:
		if a.distance_to(q)<p.distance_to(q):
			if not allow_arrival_a and a.distance_to(q)<spacing:blocked[id]=true
			# Shared logical settlement/waypoint arrivals use presentation slots.
		return
	if moving_b and not moving_a:
		if b.distance_to(p)<q.distance_to(p):
			if not allow_arrival_b and b.distance_to(p)<spacing:blocked[other]=true
			# Preserve the same arrival rule regardless of stable ID ordering.
		return
	var direction: Vector2=delta_a+delta_b
	if direction.length_squared()<.00001:direction=delta_a if moving_a else delta_b
	direction=direction.normalized()
	var lead_a: float=p.dot(direction);var lead_b: float=q.dot(direction)
	var rear: String=other if lead_a>=lead_b else id
	if a.distance_to(b)<spacing*0.92:
		blocked[rear]=true
		if moving_a and moving_b:sim.armies[rear].stuck_ticks=0

static func step(sim: RefCounted) -> void:
	sim.movement_traces.clear()
	var ids: Array=sim._sorted_ids(sim.armies)
	for id in ids:sim.movement_traces[id]=[sim.army_position_units(sim.armies[id])]
	var locked: Dictionary=sim._handle_ferries()
	var budget: Dictionary={};var destinations: Dictionary={};var moved: Dictionary={}
	for id in ids:
		var army: Dictionary=sim.armies[id]
		if army.troops<=0 or locked.has(id):continue
		if army.order.type=="hold":
			if not army.waypoints.is_empty():Orders.advance(sim,army)
			if army.order.type=="hold":army.stuck_ticks=0;continue
		if army.order.type=="attack" and not _enemy(sim,army,army.order.target):
			Orders.advance(sim,army);continue
		var destination: String=sim._target_node(army.order)
		if destination.is_empty() or (army.order.type=="siege" and sim.cities[army.order.target].owner==army.faction):
			Orders.advance(sim,army);continue
		if army.order.type=="attack_move":army.combat_target=_acquire(sim,army)
		elif army.order.type=="attack":army.combat_target=army.order.target if _enemy(sim,army,army.order.target) else ""
		else:army.combat_target=""
		if not army.combat_target.is_empty():
			var enemy: Dictionary=sim.armies[army.combat_target]
			if sim._in_range(army,enemy):army.stuck_ticks=0;continue
			if not enemy.route.is_empty() and int(enemy.edge_progress)>0 and enemy.node==army.node:
				destination=enemy.route[0]
			else:
				destination=enemy.node
		if army.route.is_empty() and destination!=army.node:
			_route(sim,army,destination)
		elif sim.tick%Rules.REPATH_TICKS==0 and not army.route.is_empty() and army.route.back()!=destination:
			_route(sim,army,destination)
		if army.stuck_ticks>=16 and sim.tick%8==0:
			var rerouted: bool=_route(sim,army,destination,_blockers(sim,army,destination))
			if not rerouted:_route(sim,army,destination)
		var terrain: String=sim.nodes[army.node].get("terrain","plain")
		var spd: int=maxi(1,int(army.movement_per_tick)*70/100) if army.unit_type=="cavalry" and terrain in ["forest","hill"] else int(army.movement_per_tick)
		if army.get("routed",false):spd=maxi(1,spd*75/100)
		# Fractional carry slows the average march without rewriting unit profiles
		# or the integer-only save schema.
		budget[id]=sim.march_budget(id,spd)
		destinations[id]=destination
	var rounds: int=0
	for amount in budget.values():rounds=maxi(rounds,mini(8,int(amount)))
	for round_index in range(rounds):
		var proposals: Dictionary={};var positions: Dictionary={};var buckets: Dictionary={}
		for id in ids:
			var army: Dictionary=sim.armies[id]
			if army.troops<=0:continue
			var proposal: Dictionary={"node":army.node,"route":army.route.duplicate(),"edge_progress":army.edge_progress}
			if int(budget.get(id,0))>round_index and not army.route.is_empty():
				var next: String=army.route[0]
				if not sim._crossing_by_edge.has(sim._edge_key(army.node,next)):
					proposal.edge_progress+=1
					if proposal.edge_progress>=int(sim.nodes[army.node].edges[next]):proposal.node=proposal.route.pop_front();proposal.edge_progress=0
			proposals[id]=proposal;positions[id]=sim._point(army)
			var cell:=Vector2i(floori(positions[id].x/16),floori(positions[id].y/16))
			if not buckets.has(cell):buckets[cell]=[]
			buckets[cell].append(id)
		var blocked: Dictionary={}
		for id in proposals:
			if locked.has(id):continue
			var army: Dictionary=sim.armies[id];var p: Vector2=positions[id]
			var cell:=Vector2i(floori(p.x/16),floori(p.y/16))
			for x in range(-4,5):
				for z in range(-4,5):
					for other in buckets.get(cell+Vector2i(x,z),[]):
						if str(other)<=str(id) or locked.has(other):continue
						var q: Vector2=positions[other];var a: Vector2=sim._proposal_point(proposals[id]);var b: Vector2=sim._proposal_point(proposals[other])
						if sim.armies[other].faction==army.faction:
							var arrive_a: bool=proposals[other].route.is_empty() and str(destinations.get(id,""))==str(proposals[other].node)
							var arrive_b: bool=proposals[id].route.is_empty() and str(destinations.get(other,""))==str(proposals[id].node)
							if a.distance_to(b)<_friendly_spacing(army,sim.armies[other]):_block_friendly_pair(id,other,p,q,a,b,arrive_a,arrive_b,blocked,sim)
							continue
						var relative: Vector2=p-q;var delta: Vector2=(a-b)-relative
						var t: float=clampf(-relative.dot(delta)/maxf(delta.length_squared(),.00001),0,1)
						var is_engaging: bool=(army.order.type=="attack" and army.order.target==other) or (sim.armies[other].order.type=="attack" and sim.armies[other].order.target==id)
						var min_dist: float=18.0 if is_engaging else sim.MELEE_RANGE
						if (relative+t*delta).length()>min_dist:continue
						if not _separating(army,p,a,q,min_dist):blocked[id]=true
						if not _separating(sim.armies[other],q,b,p,min_dist):blocked[other]=true
		for id in proposals:
			if blocked.has(id):continue
			var army: Dictionary=sim.armies[id];var proposal: Dictionary=proposals[id]
			if army.node!=proposal.node:
				var p: Array=sim.nodes[proposal.node].position;sim.movement_traces[id].append(Vector3(p[0],p[1],p[2]))
			if army.node!=proposal.node or army.edge_progress!=proposal.edge_progress:moved[id]=true
			for key in ["node","route","edge_progress"]:army[key]=proposal[key]
	for id in ids:
		var army: Dictionary=sim.armies[id]
		# A zero-budget tick is a deliberate pace gap, not a collision stall.
		if int(budget.get(id,0))>0:army.stuck_ticks=0 if moved.has(id) or army.route.is_empty() else mini(100,int(army.stuck_ticks)+1)
		if army.route.is_empty() and army.order.type in ["move","retreat","attack_move"] and army.combat_target.is_empty():Orders.advance(sim,army)
		sim.movement_traces[id].append(sim.army_position_units(army))
	sim._refresh_contacts()
