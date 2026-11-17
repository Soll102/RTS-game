extends RefCounted
## One authoritative allocator serves formations and food cargo with reusable boats.

static func initial(world: Dictionary) -> Dictionary:
	var result: Dictionary={}
	for entry in world.get("water_navigation",{}).get("fleet",[]):
		result[entry.id]={"id":entry.id,"water_node":entry.water_node,"bank":"","phase":"idle","path":[],"elapsed":0,"duration":0,"request":"","crossing":"","from_node":"","to_node":""}
	return result

static func request(sim: RefCounted, key: String) -> Dictionary:
	if key.begins_with("army:"):
		var id: String=key.trim_prefix("army:")
		if not sim.armies.has(id):return {}
		var a: Dictionary=sim.armies[id]
		if a.troops<=0 or a.route.is_empty() or (a.order.type=="hold" and a.transport_elapsed==0):return {}
		var c: Dictionary=sim._crossing_by_edge.get(sim._edge_key(a.node,a.route[0]),{})
		if c.is_empty():return {}
		return {"key":key,"kind":"army","id":id,"record":a,"crossing":c,"from":a.node,"to":a.route[0],"queued":a.transport_queued_tick}
	if key.begins_with("cargo:"):
		var id: String=key.trim_prefix("cargo:")
		for t in sim.transfers:
			if t.id!=id or t.leg>=t.route.size()-1:continue
			var c: Dictionary=sim._crossing_by_edge.get(sim._edge_key(t.route[t.leg],t.route[t.leg+1]),{})
			if c.is_empty() or (t.ferry_ticks==0 and sim.cities[t.destination].owner!=t.faction):return {}
			return {"key":key,"kind":"cargo","id":id,"record":t,"crossing":c,"from":t.route[t.leg],"to":t.route[t.leg+1],"queued":t.get("queued_tick",sim.tick)}
	return {}

static func dock(r: Dictionary, bank: String) -> String:
	return r.crossing.docks[r.crossing.nodes.find(bank)]

static func _start(sim: RefCounted, boat: Dictionary, r: Dictionary, occupied: bool) -> bool:
	if occupied:
		var busy: int=0
		for other in sim.vessels.values():
			if other.phase=="occupied" and other.crossing==r.crossing.id:busy+=1
		if busy>=int(r.crossing.capacity_formations):return false
		if r.kind=="cargo" and sim._logistics_blocked(r.from,r.to,r.record.faction):return false
	var destination: String=dock(r,r.to if occupied else r.from)
	var route: Dictionary=sim.river_navigation.route(boat.water_node,destination)
	if not route.ok:return false
	boat.phase="occupied" if occupied else "reposition"
	boat.path=route.route.duplicate();boat.elapsed=1
	boat.duration=int(r.crossing.travel_ticks) if occupied else maxi(2,ceili(float(route.distance)/2.0))
	boat.request=r.key;boat.crossing=r.crossing.id;boat.from_node=r.from;boat.to_node=r.to
	if occupied:
		if r.kind=="army":r.record.transport_elapsed=1;r.record.edge_progress=0
		else:r.record.ferry_ticks=1;r.record.ferry_id=r.crossing.id;r.record.state="Ferry transit";r.record.departed=true
		sim._emit("ferry_departed",{"boat":boat.id,"ferry":r.crossing.id,"occupant":r.key})
	else:sim._emit("boat_repositioning",{"boat":boat.id,"ferry":r.crossing.id,"occupant":r.key})
	return true

static func step(sim: RefCounted) -> Dictionary:
	var locked: Dictionary={};var assigned: Dictionary={}
	for id in sim._sorted_ids(sim.vessels):
		var boat: Dictionary=sim.vessels[id]
		if boat.phase=="idle":continue
		var r: Dictionary=request(sim,boat.request)
		if boat.request.begins_with("army:"):locked[boat.request.trim_prefix("army:")]=true
		boat.elapsed+=1
		if boat.elapsed<boat.duration:
			if boat.phase=="occupied" and not r.is_empty():
				if r.kind=="army":
					r.record.transport_elapsed=boat.elapsed
					var length: int=sim.nodes[r.from].edges[r.to]
					r.record.edge_progress=mini(length-1,length*boat.elapsed/boat.duration)
				else:r.record.ferry_ticks=boat.elapsed
			assigned[boat.request]=true
			continue
		# The vessel docks before the passenger's transport state is cleared.
		boat.water_node=boat.path[-1];boat.path=[];boat.elapsed=0;boat.duration=0
		if boat.phase in ["occupied","empty"]:
			boat.bank=boat.to_node
			if not r.is_empty():
				if r.kind=="army":
					r.record.node=r.record.route.pop_front();r.record.edge_progress=0
					r.record.transport_id="";r.record.transport_elapsed=0
					sim._emit("ferry_arrived",{"army":r.id,"boat":boat.id,"ferry":boat.crossing})
					if not r.record.deferred_order.is_empty():
						var order: Dictionary=r.record.deferred_order.duplicate();r.record.deferred_order={}
						if not sim._set_order(r.record,order):sim._hold(r.record)
				else:
					r.record.leg+=1;r.record.progress=0;r.record.ferry_ticks=0;r.record.ferry_id="";r.record.queued_tick=0;r.record.state="In transit"
			boat.request=""
		else:boat.bank=boat.from_node
		boat.phase="idle"
	var waiting: Array=[]
	for id in sim._sorted_ids(sim.armies):
		var a: Dictionary=sim.armies[id]
		if a.troops<=0 or a.route.is_empty() or a.order.type=="hold":continue
		var c: Dictionary=sim._crossing_by_edge.get(sim._edge_key(a.node,a.route[0]),{})
		if c.is_empty():continue
		locked[id]=true
		if a.transport_id.is_empty():a.transport_id=c.id;a.transport_queued_tick=sim.tick;sim._emit("ferry_queued",{"army":id,"ferry":c.id})
		if a.transport_elapsed==0:waiting.append(request(sim,"army:"+id))
	for t in sim.transfers:
		if t.leg>=t.route.size()-1 or t.ferry_ticks>0:continue
		var r: Dictionary=request(sim,"cargo:"+str(t.id))
		if r.is_empty() or sim._logistics_blocked(r.from,r.to,t.faction):continue
		if int(t.get("queued_tick",0))==0:t.queued_tick=sim.tick;r.queued=sim.tick
		t.state="Waiting for boat";waiting.append(r)
	waiting.sort_custom(func(a,b):return str(a.key)<str(b.key) if a.queued==b.queued else a.queued<b.queued)
	for boat in sim.vessels.values():
		if not boat.request.is_empty():assigned[boat.request]=true
	# Serve the oldest requests with the nearest available physical boat, not
	# whichever vessel happens to sort first by ID on the other side of the map.
	var free: Array=[]
	for id in sim._sorted_ids(sim.vessels):
		var boat: Dictionary=sim.vessels[id]
		if boat.phase!="idle":continue
		var pending: Dictionary=request(sim,boat.request)
		# Blockaded Food keeps its resources and queue age, but must not hold an
		# idle vessel hostage. Sailing vessels finish their current physical trip.
		if not pending.is_empty() and pending.kind=="cargo" and sim._logistics_blocked(pending.from,pending.to,pending.record.faction):pending={}
		if pending.is_empty():boat.request="";free.append(id)
	for r in waiting:
		if assigned.has(r.key):continue
		var chosen: String="";var distance: int=2147483647
		for id in free:
			var boat: Dictionary=sim.vessels[id]
			var route: Dictionary=sim.river_navigation.route(boat.water_node,dock(r,r.from))
			if route.ok and int(route.distance)<distance:chosen=id;distance=int(route.distance)
		if chosen.is_empty():continue
		sim.vessels[chosen].request=r.key;assigned[r.key]=true;free.erase(chosen)
	for id in sim._sorted_ids(sim.vessels):
		var boat: Dictionary=sim.vessels[id]
		if boat.phase!="idle":continue
		var r: Dictionary=request(sim,boat.request)
		if r.is_empty():continue
		if boat.water_node!=dock(r,r.from):_start(sim,boat,r,false)
		elif sim.tick%int(r.crossing.departure_interval_ticks)==0:_start(sim,boat,r,true)
	return locked

static func cancel_reservation(sim: RefCounted,key: String) -> void:
	for boat in sim.vessels.values():
		if boat.request!=key:continue
		boat.request=""
		if boat.phase=="occupied":boat.phase="empty"
		elif boat.phase=="reposition":
			boat.phase="empty"
			var previous: String=boat.from_node;boat.from_node=boat.to_node;boat.to_node=previous

static func position(sim: RefCounted, boat: Dictionary, alpha: float=0.0) -> Vector3:
	if boat.phase=="idle":return sim.river_navigation.position(boat.water_node)
	return sim.river_navigation.sample(boat.path,clampf((float(boat.elapsed)+alpha)/maxi(1,int(boat.duration)),0,1))

static func validate(data: Dictionary) -> String:
	var state: Dictionary=data.battle_state
	if not state.get("vessels") is Dictionary:return "Save vessel state is missing."
	var world: Dictionary=data.campaign.world;var navigation: Dictionary=world.get("water_navigation",{})
	var water: Dictionary=navigation.get("nodes",{})
	var expected: Dictionary={}
	for entry in navigation.get("fleet",[]):expected[entry.id]=true
	var crossings: Dictionary={}
	for c in world.get("crossings",[]):crossings[c.id]=c
	var occupants: Dictionary={}
	if state.vessels.size()>expected.size()+data.armies.size()+24:return "Save vessel budget is exceeded."
	for id in state.vessels:
		var boat=state.vessels[id]
		if not id is String or not boat is Dictionary or boat.get("id")!=id or not water.has(boat.get("water_node","")):return "Save vessel identity or location is invalid."
		if not expected.has(id):
			var legacy_army: String=str(id).trim_prefix("legacy-passenger-army-")
			var legacy_cargo: String=str(id).trim_prefix("legacy-passenger-cargo-food-")
			var army_valid: bool=str(id).begins_with("legacy-passenger-army-") and data.armies.has(legacy_army)
			var cargo_valid: bool=str(id).begins_with("legacy-passenger-cargo-food-") and legacy_cargo.is_valid_int() and legacy_cargo.to_int()>0 and legacy_cargo.to_int()<=int(state.serial)
			if not army_valid and not cargo_valid:return "Save contains an unknown vessel."
		for key in ["bank","request","crossing","from_node","to_node"]:
			if not boat.get(key) is String:return "Save vessel string is invalid."
		if not boat.get("path") is Array or not boat.get("elapsed") is int or not boat.get("duration") is int or boat.elapsed<0 or boat.duration<0:return "Save vessel progress is invalid."
		if boat.get("phase") not in ["idle","reposition","occupied","empty"]:return "Save vessel phase is invalid."
		if not boat.bank.is_empty() and not data.nodes.has(boat.bank):return "Save vessel bank is invalid."
		if not boat.request.is_empty():
			if occupants.has(boat.request):return "Save passenger reserved two boats."
			occupants[boat.request]=boat
			if boat.request.begins_with("army:"):
				if not data.armies.has(boat.request.trim_prefix("army:")):return "Save boat reserves a missing formation."
			elif boat.request.begins_with("cargo:"):
				var found: bool=false
				for t in state.transfers:
					if t.id==boat.request.trim_prefix("cargo:"):found=true;break
				if not found:return "Save boat reserves missing cargo."
			else:return "Save boat passenger type is invalid."
		if boat.phase=="idle":
			if not boat.bank.is_empty():
				if not crossings.has(boat.crossing) or boat.bank not in crossings[boat.crossing].nodes:return "Save idle boat is not at a service bank."
				var c: Dictionary=crossings[boat.crossing]
				if boat.water_node!=c.docks[c.nodes.find(boat.bank)]:return "Save idle boat is away from its recorded dock."
			if boat.elapsed!=0 or boat.duration!=0 or not boat.path.is_empty():return "Idle vessel has an active trip."
			continue
		if not crossings.has(boat.crossing) or boat.elapsed<1 or boat.elapsed>=boat.duration or (boat.request.is_empty() and boat.phase!="empty") or boat.path.is_empty() or boat.path[0]!=boat.water_node:return "Save vessel trip is invalid."
		var c: Dictionary=crossings[boat.crossing]
		if boat.from_node not in c.nodes or boat.to_node not in c.nodes or boat.from_node==boat.to_node:return "Save vessel endpoints are invalid."
		var arrival: String=boat.to_node if boat.phase in ["occupied","empty"] else boat.from_node
		if boat.path[-1]!=c.docks[c.nodes.find(arrival)]:return "Save vessel lands at a different dock."
		for i in range(boat.path.size()):
			if not water.has(boat.path[i]):return "Save vessel leaves navigable water."
			if i>0 and not water[boat.path[i-1]].edges.has(boat.path[i]):return "Save vessel water path is disconnected."
		if boat.phase=="occupied" and boat.duration!=c.travel_ticks:return "Save loaded vessel timetable is invalid."
	for entry in navigation.get("fleet",[]):
		if not state.vessels.has(entry.id):return "Save is missing a physical vessel."
	var passengers: Dictionary={}
	for a in data.armies.values():
		if a.transport_elapsed>0:passengers["army:"+a.id]={"elapsed":a.transport_elapsed,"crossing":a.transport_id,"from":a.node,"to":a.route[0]}
	for t in state.transfers:
		if t.ferry_ticks>0:passengers["cargo:"+t.id]={"elapsed":t.ferry_ticks,"crossing":t.ferry_id,"from":t.route[t.leg],"to":t.route[t.leg+1]}
	for key in passengers:
		if not occupants.has(key):return "Save passenger has no boat."
		var boat: Dictionary=occupants[key];var p: Dictionary=passengers[key]
		if boat.phase!="occupied" or boat.elapsed!=p.elapsed or boat.crossing!=p.crossing or boat.from_node!=p.from or boat.to_node!=p.to:return "Save boat and passenger disagree."
	for key in occupants:
		if occupants[key].phase=="occupied" and not passengers.has(key):return "Save occupied boat has no passenger."
	return ""
