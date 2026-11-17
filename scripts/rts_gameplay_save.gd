extends RefCounted
const River=preload("res://scripts/rts_river_navigation.gd")
const Boats=preload("res://scripts/rts_boat_transport.gd")

static func migrate(legacy: Dictionary) -> Dictionary:
	var world: Dictionary=River.load_world()
	var river:=River.new();river.configure(world)
	var data: Dictionary=legacy.duplicate(true)
	data.format_version=12;data.battle_state.revision=5;data.nodes=world.nodes.duplicate(true)
	world.erase("nodes");data.campaign.world=world
	data.battle_state.vessels=Boats.initial(world)
	var gates: Dictionary={};var edges: Dictionary={};var occupied: Dictionary={}
	for s in world.settlements:gates[s.id]=s.get("gate_nodes",[s.node])
	for c in world.crossings:edges[_edge_key(c.nodes[0],c.nodes[1])]=c
	for id in data.cities:data.cities[id].gate_nodes=gates[id].duplicate()
	for command in data.command_queue:
		if command.type=="siege":command.gate_node=data.cities[command.target].node
	var passengers: Array=[]
	for id in data.armies:
		var a: Dictionary=data.armies[id]
		for order in [a.order,a.deferred_order]:
			if order.get("type")=="siege":order.gate_node=data.cities[order.target].node
		if a.transport_elapsed>0:
			passengers.append({"key":"army:"+id,"from":a.node,"to":a.route[0],"elapsed":a.transport_elapsed})
		elif a.edge_progress>0 and not a.route.is_empty():
			var c: Dictionary=edges.get(_edge_key(a.node,a.route[0]),{})
			if not c.is_empty() and str(c.id).begins_with("river-repair-"):
				a.transport_id=c.id;a.transport_elapsed=maxi(1,int(a.edge_progress));a.transport_queued_tick=data.tick
				if a.transport_elapsed==1:a.edge_progress=0
				passengers.append({"key":"army:"+id,"from":a.node,"to":a.route[0],"elapsed":a.transport_elapsed})
	for t in data.battle_state.transfers:
		t.queued_tick=0
		if t.ferry_ticks>0:passengers.append({"key":"cargo:"+t.id,"from":t.route[t.leg],"to":t.route[t.leg+1],"elapsed":t.ferry_ticks})
	passengers.sort_custom(func(a,b):return str(a.key)<str(b.key))
	for passenger in passengers:
		var c: Dictionary=edges[_edge_key(passenger.from,passenger.to)]
		var id: String=c.id if data.battle_state.vessels.has(c.id) and not occupied.has(c.id) else "legacy-passenger-"+passenger.key.replace(":","-")
		occupied[id]=true
		var start: String=c.docks[c.nodes.find(passenger.from)];var finish: String=c.docks[c.nodes.find(passenger.to)]
		var path: Dictionary=river.route(start,finish)
		if not path.ok:return {"error":"Legacy passenger has no valid boat route.","data":{}}
		data.battle_state.vessels[id]={"id":id,"water_node":start,"bank":"","phase":"occupied","path":path.route,"elapsed":passenger.elapsed,"duration":c.travel_ticks,"request":passenger.key,"crossing":c.id,"from_node":passenger.from,"to_node":passenger.to}
	return {"error":"","data":data}

static func _edge_key(a: String,b: String) -> String:
	return a+"|"+b if a<b else b+"|"+a
