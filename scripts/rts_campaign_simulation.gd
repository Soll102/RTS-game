extends "res://scripts/rts_simulation.gd"
var _compact_supply_inputs: Dictionary={}
## Spatial campaign rules; pure state. Legacy graph fixtures remain in the base.

const CampaignAI = preload("res://scripts/rts_campaign_ai.gd")
const RiverMask=preload("res://scripts/rts_river_navigation.gd")
const TacticalMovement=preload("res://scripts/rts_tactical_movement.gd")
const TacticalOrderQueue=preload("res://scripts/rts_tactical_orders.gd")
const NavigationPlan=preload("res://scripts/rts_navigation_plan.gd")
const CAMPAIGN_FORMAT = 5
const MELEE_RANGE = 16
const ARCHER_RANGE = 120
const COMBAT_INTERVAL = 10
const FOOD_INTERVAL = 100
const PROFILES = {
	"infantry":{"movement":2,"cost":2,"training":180,"siege":4},
	"archers":{"movement":2,"cost":3,"training":220,"siege":2},
	"cavalry":{"movement":4,"cost":4,"training":280,"siege":2},
	"siege":{"movement":1,"cost":6,"training":340,"siege":12}}
var world_metadata: Dictionary = {}
var match_state: String = "running"
var continued: bool = false
var _contacts: Dictionary = {}
var _crossing_by_edge: Dictionary = {}
var _settlement_route_cache: Dictionary = {}
var _reverse_routes: Dictionary = {}
var movement_traces: Dictionary={}
## `impassable_nodes` and `is_navigation_open()` live on the base simulation so
## every routing/destination caller shares the exact same traversability rule.
var navigation_mask_ready: bool=false

func _rebuild_navigation_mask(world: Dictionary) -> void:
	var fresh: Dictionary=RiverMask.blocked_nodes(world,nodes)
	march_credit.clear()
	# Same-world loads keep their warmed route caches; a changed world rebuilds
	# them so no stale path can bypass an obstacle or discard a shorter route.
	if navigation_mask_ready and fresh==impassable_nodes:return
	impassable_nodes=fresh;navigation_mask_ready=true
	_compact_paths.clear();_compact_route_trees.clear()
	_settlement_route_cache.clear();_reverse_routes.clear()

func configure(world: Dictionary, initial_armies: Array, initial_cities: Array, initial_seed: int = 1) -> String:
	var error: String = _validate_world(world)
	if not error.is_empty(): return error
	if _contains_fractional_number(world): return "Campaign world state requires integer coordinate units."
	var canonical_world: Dictionary=_integer_data(world)
	error = super.configure(canonical_world, initial_armies, initial_cities, initial_seed)
	if not error.is_empty(): return error
	_settlement_route_cache.clear();_reverse_routes.clear()
	world_metadata = canonical_world.duplicate(true)
	world_metadata.erase("nodes")
	match_state = "running"
	continued = false
	for army in armies.values(): _initialize_army(army)
	_rebuild_crossings()
	_rebuild_navigation_mask(canonical_world)
	return ""

func _validate_world(world: Dictionary) -> String:
	if not world.get("id") is String or world["id"].is_empty() or not _integer_at_least(world.get("revision"),1): return "Campaign world identity is invalid."
	if not world.get("nodes") is Dictionary or not world.get("crossings",[]) is Array: return "Campaign world graph is invalid."
	var graph_error: String = _validate_graph(world["nodes"])
	if not graph_error.is_empty(): return graph_error
	for node in world["nodes"].values():
		if not node is Dictionary or not node.get("position") is Array or node["position"].size()!=3: return "Campaign node needs an integer position."
		for v in node["position"]:
			if not (v is int or v is float) or not is_finite(float(v)) or float(v)!=floor(float(v)): return "Campaign position is invalid."
	var crossing_ids: Dictionary = {}
	var crossing_edges: Dictionary = {}
	for crossing in world.get("crossings",[]):
		if not crossing is Dictionary or not crossing.get("id") is String or crossing["id"].is_empty() or crossing_ids.has(crossing["id"]): return "Ferry identity is invalid."
		crossing_ids[crossing["id"]]=true
		if crossing.get("type")!="ferry" or not crossing.get("nodes") is Array or crossing["nodes"].size()!=2: return "Ferry route is invalid."
		var ends: Array = crossing["nodes"]
		if not ends[0] is String or not ends[1] is String or ends[0]==ends[1]: return "Ferry endpoints are invalid."
		if not world["nodes"].has(ends[0]) or not world["nodes"].has(ends[1]) or not world["nodes"][ends[0]]["edges"].has(ends[1]) or not world["nodes"][ends[1]]["edges"].has(ends[0]): return "Ferry endpoints are disconnected."
		var edge: String = _edge_key(ends[0], ends[1])
		if crossing_edges.has(edge): return "Ferry edge is duplicated."
		crossing_edges[edge]=true
		for k in ["capacity_formations","departure_interval_ticks","travel_ticks"]:
			if not _integer_at_least(crossing.get(k),1): return "Ferry schedule is invalid."
		if crossing["travel_ticks"]<2: return "Ferry travel needs at least two simulation ticks."
	if not world.get("los_walls",[]) is Array: return "Line-of-sight walls are invalid."
	for wall in world.get("los_walls",[]):
		if not wall is Array or wall.size()!=4: return "Line-of-sight wall is invalid."
		for v in wall:
			if not (v is int or v is float) or not is_finite(float(v)): return "Line-of-sight wall is invalid."
		if wall[2]<=0 or wall[3]<=0: return "Line-of-sight wall dimensions are invalid."
	var grid = world.get("los_grid",{})
	if not grid is Dictionary: return "Line-of-sight grid is invalid."
	if not grid.is_empty():
		for k in ["width","depth"]:
			if not _integer_at_least(grid.get(k),2): return "Line-of-sight grid dimensions are invalid."
		if not _integer_at_least(grid.get("step"),1) or not grid.get("minimum") is Array or grid["minimum"].size()!=2: return "Line-of-sight grid coordinates are invalid."
		if not grid.get("heights") is Array or grid["heights"].size()!=grid["width"]*grid["depth"]: return "Line-of-sight grid heights are invalid."
		for v in grid["minimum"]+grid["heights"]:
			if not (v is int or v is float) or not is_finite(float(v)): return "Line-of-sight grid height is invalid."
	return ""

func _initialize_army(army: Dictionary) -> void:
	army["routed"]=false
	army["rout_until"]=0
	army["engaged_ids"]=[]
	army["transport_id"]=""
	army["transport_elapsed"]=0
	army["transport_queued_tick"]=0
	army["deferred_order"]={}

func _edge_key(a: String,b: String) -> String:
	return a+"|"+b if a<b else b+"|"+a

func _rebuild_crossings() -> void:
	_crossing_by_edge.clear()
	for crossing in world_metadata.get("crossings",[]):
		_crossing_by_edge[_edge_key(crossing["nodes"][0],crossing["nodes"][1])]=crossing

func army_position_units(army: Dictionary) -> Vector3:
	var p: Array = nodes[army["node"]]["position"]
	var origin := Vector3(p[0],p[1],p[2])
	if army["route"].is_empty(): return origin
	var next: String = army["route"][0]
	var q: Array = nodes[next]["position"]
	return origin.lerp(Vector3(q[0],q[1],q[2]),float(army["edge_progress"])/float(nodes[army["node"]]["edges"][next]))

func _point(army: Dictionary) -> Vector2:
	var p := army_position_units(army)
	return Vector2(p.x,p.z)

func _hold(army: Dictionary) -> void:
	# Stopping on an edge retains location; never snaps to its origin node.
	army["order"]={"type":"hold","target":""}
	if int(army["edge_progress"])==0 or int(army["troops"])==0:
		army["route"]=[]
		army["edge_progress"]=0
		army["transport_id"]=""
		army["transport_elapsed"]=0
		army["deferred_order"]={}
	army["siege_state"]="aborted" if army.get("siege_state") in ["approaching","besieging","breached","contested"] else "none"

func submit_command(command: Dictionary) -> String:
	if match_state=="finished": return "Campaign finished. Choose Continue to issue orders."
	for id in command.get("army_ids",[]):
		if armies.has(id) and armies[id].get("routed",false) and command.get("type")!="stance": return "Army is routing and cannot receive movement orders."
	return super.submit_command(command)

func _set_order(army: Dictionary,order: Dictionary) -> bool:
	if not army["transport_id"].is_empty() and int(army["transport_elapsed"])>0:
		army["deferred_order"]=order.duplicate()
		return true
	if order["type"]=="hold":
		_hold(army)
		return true
	var destination: String = _target_node(order)
	if destination.is_empty(): return false
	if not NavigationPlan.commit(army,NavigationPlan.plan(self,army,destination)):return false
	army["order"]=order.duplicate()
	army["transport_id"]=""
	army["transport_elapsed"]=0
	army["siege_state"]="approaching" if order["type"]=="siege" else "none"
	return true

func _apply_commands() -> void:
	if get("tactical_rts")==true:TacticalOrderQueue.apply(self);return
	for command in command_queue:
		var ids: Array=command["army_ids"].duplicate(); ids.sort()
		for id in ids:
			var army: Dictionary=armies[id]
			if int(army["troops"])<=0: continue
			if command["type"]=="stance":
				army["stance"]=command["target"]
				_emit("stance_changed",{"army":id,"stance":command["target"]})
			else:
				var order: Dictionary={"type":command.type,"target":command.target}
				if command.has("gate_node"):order.gate_node=command.gate_node
				if not _set_order(army,order):_emit("order_failed",{"army":id,"reason":"No valid route."})
	command_queue.clear()

func step(count: int = 1) -> void:
	for _index in range(maxi(0,count)):
		if match_state=="finished": break
		tick+=1
		if (tick-1)%CampaignAI.DECISION_INTERVAL_TICKS==0:
			for faction in ai_factions: CampaignAI.decide(self,faction)
		_apply_commands()
		_move_armies()
		_update_supply(tick%FOOD_INTERVAL==0)
		if tick%COMBAT_INTERVAL==0:
			_resolve_battles()
			_resolve_sieges()
		_update_routs()
		_update_production()
		_update_victory()
		_update_supply(false)
		_refresh_contacts()

func advance_real_time_us(elapsed_us: int,max_ticks: int=0) -> int:
	if match_state=="finished": return 0
	return super.advance_real_time_us(elapsed_us,max_ticks)

func continue_campaign() -> void:
	if match_state=="finished":
		match_state="running"
		continued=true
		paused=false
		winner=""

func _update_victory() -> void:
	if continued: return
	super._update_victory()
	if not winner.is_empty():
		match_state="finished"
		paused=true

func _handle_ferries() -> Dictionary:
	var busy: Dictionary={}
	var locked: Dictionary={}
	for id in _sorted_ids(armies):
		var army: Dictionary=armies[id]
		if int(army["troops"])<=0: continue
		if not army["transport_id"].is_empty() and int(army["transport_elapsed"])>0:
			locked[id]=true
			var crossing: Dictionary=_crossing_by_edge[_edge_key(army["node"],army["route"][0])]
			busy[crossing["id"]]=int(busy.get(crossing["id"],0))+1
			army["transport_elapsed"]+=1
			var length: int=nodes[army["node"]]["edges"][army["route"][0]]
			army["edge_progress"]=mini(length-1,int(length*int(army["transport_elapsed"])/int(crossing["travel_ticks"])))
			if int(army["transport_elapsed"])>=int(crossing["travel_ticks"]):
				army["node"]=army["route"].pop_front()
				army["edge_progress"]=0
				army["transport_id"]=""
				army["transport_elapsed"]=0
				_emit("ferry_arrived",{"army":id,"ferry":crossing["id"]})
				if not army["deferred_order"].is_empty():
					var deferred: Dictionary=army["deferred_order"].duplicate(); army["deferred_order"]={}
					if not _set_order(army,deferred): _hold(army)
	var waiting: Array=[]
	for id in _sorted_ids(armies):
		var army: Dictionary=armies[id]
		if locked.has(id) or int(army["troops"])<=0 or army["route"].is_empty() or army["order"]["type"]=="hold": continue
		var key: String=_edge_key(army["node"],army["route"][0])
		if not _crossing_by_edge.has(key): continue
		var crossing: Dictionary=_crossing_by_edge[key]
		locked[id]=true
		if army["transport_id"].is_empty():
			army["transport_id"]=crossing["id"]
			army["transport_queued_tick"]=tick
			_emit("ferry_queued",{"army":id,"ferry":crossing["id"]})
		waiting.append(id)
	waiting.sort_custom(func(a,b): return str(a)<str(b) if armies[a]["transport_queued_tick"]==armies[b]["transport_queued_tick"] else int(armies[a]["transport_queued_tick"])<int(armies[b]["transport_queued_tick"]))
	for id in waiting:
		var army: Dictionary=armies[id]
		var crossing: Dictionary=_crossing_by_edge[_edge_key(army["node"],army["route"][0])]
		if tick%int(crossing["departure_interval_ticks"])!=0 or int(busy.get(crossing["id"],0))>=int(crossing["capacity_formations"]): continue
		army["transport_elapsed"]=1
		busy[crossing["id"]]=int(busy.get(crossing["id"],0))+1
		_emit("ferry_departed",{"army":id,"ferry":crossing["id"]})
	return locked

func _move_armies() -> void:
	if get("tactical_rts")==true:TacticalMovement.step(self);return
	movement_traces.clear()
	for id in _sorted_ids(armies):movement_traces[id]=[army_position_units(armies[id])]
	var locked := _handle_ferries()
	var ids := _sorted_ids(armies)
	var budget: Dictionary={}
	for id in ids:
		var army: Dictionary=armies[id]
		if int(army["troops"])<=0 or locked.has(id) or army["order"]["type"]=="hold": continue
		var destination: String=_target_node(army["order"])
		if destination.is_empty() or (army["order"]["type"]=="siege" and cities[army["order"]["target"]]["owner"]==army["faction"]):
			_hold(army); continue
		if army["route"].is_empty() and destination!=army["node"]:
			if not _set_order(army,army["order"].duplicate()): _hold(army); continue
		if army["order"]["type"]=="attack" and armies.has(army["order"]["target"]) and _in_range(army,armies[army["order"]["target"]]): continue
		if army.order.type=="attack_move" and not army.engaged_ids.is_empty():continue
		if army["order"]["type"]=="attack" and tick%(5 if get("traditional_rts")==true else CampaignAI.DECISION_INTERVAL_TICKS)==0 and not army["route"].is_empty() and army["route"].back()!=destination:
			if not _set_order(army,army["order"].duplicate()): _hold(army); continue
		var terrain: String=nodes[army["node"]].get("terrain","plain")
		var pace: int=maxi(1,int(army["movement_per_tick"])*70/100) if army["unit_type"]=="cavalry" and terrain in ["forest","hill"] else int(army["movement_per_tick"])
		budget[id]=march_budget(id,pace)
	# Only active movement budgets need swept rounds; stationary armies still block movers.
	var rounds: int=0
	for amount in budget.values():rounds=maxi(rounds,mini(8,int(amount)))
	for round_index in range(rounds):
		var proposed: Dictionary={}
		for id in ids:
			var army: Dictionary=armies[id]
			if int(army["troops"])<=0: continue
			var proposal: Dictionary={"node":army["node"],"route":army["route"].duplicate(),"edge_progress":army["edge_progress"]}
			if int(budget.get(id,0))>round_index and not army["route"].is_empty():
				var next: String=army["route"][0]
				if not _crossing_by_edge.has(_edge_key(army["node"],next)):
					proposal["edge_progress"]+=1
					if int(proposal["edge_progress"])>=int(nodes[army["node"]]["edges"][next]):
						proposal["node"]=proposal["route"].pop_front(); proposal["edge_progress"]=0
			proposed[id]=proposal
		var blocked: Dictionary={}
		var buckets: Dictionary={}
		for id in proposed:
			var p:=_point(armies[id]); var bucket:=Vector2i(floori(p.x/MELEE_RANGE),floori(p.y/MELEE_RANGE))
			if not buckets.has(bucket): buckets[bucket]=[]
			buckets[bucket].append(id)
		for id in proposed:
			if locked.has(id): continue
			var army: Dictionary=armies[id]
			var p:=_point(army); var cell:=Vector2i(floori(p.x/MELEE_RANGE),floori(p.y/MELEE_RANGE))
			for x in range(-1,2):
				for z in range(-1,2):
					for other in buckets.get(cell+Vector2i(x,z),[]):
						if str(other)<=str(id) or armies[other]["faction"]==army["faction"] or locked.has(other): continue
						var q:=_point(armies[other])
						var a:=_proposal_point(proposed[id]); var b:=_proposal_point(proposed[other])
						var relative_start:=p-q; var relative_end:=a-b; var d:=relative_end-relative_start
						var t:=clampf(-relative_start.dot(d)/maxf(d.length_squared(),.00001),0,1)
						if (relative_start+t*d).length()>MELEE_RANGE: continue
						# Retreat may disengage only while separating, never advance through foes.
						if not army["routed"] or a.distance_to(q)<p.distance_to(q): blocked[id]=true
						if not armies[other]["routed"] or b.distance_to(p)<q.distance_to(p): blocked[other]=true
		for id in proposed:
			if blocked.has(id): continue
			if armies[id].node!=proposed[id].node:
				var corner: Array=nodes[proposed[id].node].position
				movement_traces[id].append(Vector3(corner[0],corner[1],corner[2]))
			for field in ["node","route","edge_progress"]:armies[id][field]=proposed[id][field]
	for id in ids:
		var army: Dictionary=armies[id]
		if army["route"].is_empty() and army["order"]["type"] in ["move","retreat","attack_move"]: _hold(army)
	for id in ids:movement_traces[id].append(army_position_units(armies[id]))
	_refresh_contacts()

func _proposal_point(proposal: Dictionary) -> Vector2:
	var p:=army_position_units(proposal)
	return Vector2(p.x,p.z)

func _in_range(attacker: Dictionary,defender: Dictionary) -> bool:
	if int(defender["troops"])<=0 or attacker["faction"]==defender["faction"] or int(defender["transport_elapsed"])>0: return false
	var radius: int=ARCHER_RANGE if attacker["unit_type"]=="archers" else MELEE_RANGE+2
	return _point(attacker).distance_squared_to(_point(defender))<=radius*radius and has_line_of_sight(attacker,defender)

func has_line_of_sight(a: Dictionary,b: Dictionary) -> bool:
	var start:=army_position_units(a); var finish:=army_position_units(b)
	var grid: Dictionary=world_metadata.get("los_grid",{})
	var samples: int=maxi(2,ceili(Vector2(start.x-finish.x,start.z-finish.z).length()/8))
	for index in range(1,samples):
		var p:=start.lerp(finish,float(index)/samples)
		for wall in world_metadata.get("los_walls",[]):
			if absf(p.x-wall[0])<wall[2] and absf(p.z-wall[1])<wall[3]: return false
		if not grid.is_empty():
			var gx:=clampf((p.x-grid["minimum"][0])/float(grid["step"]),0,float(grid["width"]-1))
			var gz:=clampf((p.z-grid["minimum"][1])/float(grid["step"]),0,float(grid["depth"]-1))
			var x:=mini(int(gx),int(grid["width"])-2); var z:=mini(int(gz),int(grid["depth"])-2)
			var heights: Array=grid["heights"]; var width: int=grid["width"]
			var h:=lerpf(lerpf(heights[z*width+x],heights[z*width+x+1],gx-x),lerpf(heights[(z+1)*width+x],heights[(z+1)*width+x+1],gx-x),gz-z)
			if h>p.y+12: return false
	return true

func _refresh_contacts() -> void:
	_contacts.clear()
	var buckets: Dictionary={}
	for id in _sorted_ids(armies):
		var army: Dictionary=armies[id]; army["engaged_ids"]=[]
		if int(army["troops"])<=0 or int(army["transport_elapsed"])>0: continue
		var p:=_point(army); var cell:=Vector2i(floori(p.x/ARCHER_RANGE),floori(p.y/ARCHER_RANGE))
		if not buckets.has(cell): buckets[cell]=[]
		buckets[cell].append(id)
	for id in _sorted_ids(armies):
		var army: Dictionary=armies[id]
		if int(army["troops"])<=0 or army["routed"] or int(army["transport_elapsed"])>0: continue
		var p:=_point(army); var cell:=Vector2i(floori(p.x/ARCHER_RANGE),floori(p.y/ARCHER_RANGE))
		var targets: Array=[]
		for x in range(-1,2):
			for z in range(-1,2):
				for other in buckets.get(cell+Vector2i(x,z),[]):
					if _in_range(army,armies[other]): targets.append(other)
		targets.sort(); army["engaged_ids"]=targets
		if not targets.is_empty(): _contacts[id]=targets

func _resolve_battles() -> void:
	var damage: Dictionary={}
	for id in _sorted_ids(_contacts):
		var attacker: Dictionary=armies[id]; var targets: Array=_contacts[id]
		var target: String=targets[0]
		if attacker["order"]["type"]=="attack" and attacker["order"]["target"] in targets: target=attacker["order"]["target"]
		else:
			for other in targets:
				if int(armies[other]["troops"])<int(armies[target]["troops"]): target=other
		var defender: Dictionary=armies[target]
		var terrain: String=nodes[defender["node"]].get("terrain","plain")
		var dealt: int=Combat.casualties(attacker,defender,terrain)
		damage[target]=int(damage.get(target,0))+dealt
		_emit("field_attack",{"army":id,"target":target,"damage":dealt,"ranged":attacker["unit_type"]=="archers"})
	_apply_damage(damage,"battle")

func _apply_damage(damage: Dictionary,reason: String) -> void:
	for id in _sorted_ids(damage):
		var army: Dictionary=armies[id]; var previous: int=army["troops"]
		army["troops"]=maxi(0,previous-int(damage[id]))
		army["morale"]=maxi(0,int(army["morale"])-mini(15,maxi(1,int(damage[id])*100/maxi(1,previous))))
		if int(army["troops"])==0: _defeat(army,reason)

func _resolve_sieges() -> void:
	var occupants:=_stationary_armies_by_node()
	for city_id in _sorted_ids(cities):
		var city: Dictionary=cities[city_id]; var attackers: Array=[]; var factions: Dictionary={}; var defenders: bool=false
		for id in occupants.get(city["node"],[]):
			var army: Dictionary=armies[id]
			if army["faction"]==city["owner"]: defenders=true
			elif not army["routed"] and army["order"]["type"]=="siege" and army["order"]["target"]==city_id:
				attackers.append(id); factions[army["faction"]]=true
		if attackers.is_empty(): continue
		if defenders or factions.size()!=1:
			for id in attackers: armies[id]["siege_state"]="contested"
			continue
		var outgoing: int=0; var retaliation: Dictionary={}
		var garrison_power: int=mini(20,maxi(0,int(city["garrison"])/30))
		for id in attackers:
			outgoing+=Combat.siege_damage(armies[id])
			armies[id]["siege_state"]="besieging" if int(city["wall_hp"])>0 else "breached"
			if garrison_power>0: retaliation[id]=maxi(1,garrison_power/attackers.size())
		if int(city["wall_hp"])>0: city["wall_hp"]=maxi(0,int(city["wall_hp"])-outgoing)
		else: city["garrison"]=maxi(0,int(city["garrison"])-outgoing)
		_apply_damage(retaliation,"garrison")
		var surviving: Array=[]
		for id in attackers:
			if int(armies[id]["troops"])>0 and int(armies[id]["morale"])>20: surviving.append(id)
		if int(city["wall_hp"])>0 or int(city["garrison"])>0 or surviving.is_empty(): continue
		var old_owner: String=city["owner"]
		city["owner"]=armies[surviving[0]]["faction"]
		for job in city["production_queue"]: _emit("recruitment_cancelled",{"city":city_id,"army":job["army_id"],"reason":"City captured."})
		city["production_queue"]=[]; city["food"]=int(city["food"])/2
		_supply_dirty=true
		_emit("city_captured",{"city":city_id,"old_owner":old_owner,"new_owner":city["owner"]})
		for id in surviving: _hold(armies[id]); armies[id]["siege_state"]="captured"

func _update_routs() -> void:
	for id in _sorted_ids(armies):
		var army: Dictionary=armies[id]
		if int(army["troops"])<=0: continue
		if army["routed"]:
			if tick>=int(army["rout_until"]) and army["supplied"] and int(army["morale"])>=45:
				army["routed"]=false; _emit("army_rallied",{"army":id})
			continue
		if int(army["morale"])>20: continue
		army["routed"]=true; army["rout_until"]=tick+100
		var home: String=""; var best: int=2147483647
		var routes:=find_routes_from(army["node"])
		for city in cities.values():
			if city["owner"]!=army["faction"] or _city_under_siege(city): continue
			var path:=route_from_tree(routes,city["node"])
			if path["ok"] and int(path["distance"])<best: home=city["node"]; best=path["distance"]
		if home.is_empty() or not _set_order(army,{"type":"retreat","target":home}): _hold(army)
		_emit("army_routed",{"army":id,"home":home})

func _current_supply_signature() -> int:
	var edges: Array=[]
	for id in _sorted_ids(armies):
		var army: Dictionary=armies[id]
		if int(army["troops"])>0 and not army["route"].is_empty() and int(army["edge_progress"])>0: edges.append([id,army["node"],army["route"][0]])
	return hash([super._current_supply_signature(),edges])

func _supply_max_distance() -> int:
	return 900

func _supply_blockades_outside_tree(graph: RefCounted, cache: Dictionary, old: Array, blocked: Dictionary, blocked_edges: Dictionary) -> bool:
	# Changes outside the existing reachable tree cannot change its shortest
	# routes. A removed node checks incoming frontier edges too, so opening a
	# chain of blockades is never mistaken for an irrelevant distant edit.
	var distance: PackedInt64Array=cache.distance_indices
	var old_nodes: Dictionary=old[2];var old_edges: Dictionary=old[3]
	var max_dist: int=_supply_max_distance()
	for id in blocked:
		if old_nodes.has(id):continue
		var i: int=int(graph.index.get(id,-1))
		if i>=0 and distance[i]>=0:return false
	for id in old_nodes:
		if blocked.has(id):continue
		var i: int=int(graph.index.get(id,-1))
		if i<0:continue
		var incoming: PackedInt32Array=graph.incoming_neighbors[i];var costs: PackedInt64Array=graph.incoming_weights[i]
		for edge in range(incoming.size()):
			var from: int=incoming[edge]
			if distance[from]>=0 and distance[from]+costs[edge]<=max_dist:return false
	for edges in [blocked_edges,old_edges]:
		var other_edges: Dictionary=old_edges if is_same(edges,blocked_edges) else blocked_edges
		for key in edges:
			if other_edges.has(key):continue
			var endpoints: PackedStringArray=str(key).split("|")
			if endpoints.size()!=2:return false
			for id in endpoints:
				var i: int=int(graph.index.get(id,-1))
				if i>=0 and distance[i]>=0:return false
	return true

func _rebuild_supply_cache() -> void:
	performance_metrics["supply_rebuilds"]+=1
	var graph: RefCounted=_compact_navigation()
	var factions: Dictionary={}
	for army in armies.values():
		if int(army.troops)>0:factions[army.faction]=true
	for faction in _supply_cache.keys():
		if not factions.has(faction):_supply_cache.erase(faction);_compact_supply_inputs.erase(faction)
	var city_ids: Array=_sorted_ids(cities)
	for faction in _sorted_ids(factions):
		var blocked: Dictionary=_blocked_nodes(faction);var blocked_edges: Dictionary={}
		for army in armies.values():
			if army.faction!=faction and army.troops>0 and army.edge_progress>0 and not army.route.is_empty():blocked_edges[_edge_key(army.node,army.route[0])]=true
		var seeds: Array=[]
		for index in range(city_ids.size()):
			var c: Dictionary=cities[city_ids[index]]
			if c.owner==faction and c.food>0 and not blocked.has(c.node):seeds.append([graph.index[c.node],index])
		# Own troop motion does not change a faction's supply tree. Compare only
		# topology, source eligibility and hostile node/edge blockade inputs.
		var inputs: Array=[_compact_graph_signature,city_ids,blocked,blocked_edges,seeds]
		if _supply_cache.has(faction) and _compact_supply_inputs.get(faction,[])==inputs:
			performance_metrics["supply_faction_reuses"]=int(performance_metrics.get("supply_faction_reuses",0))+1
			continue
		var old: Array=_compact_supply_inputs.get(faction,[])
		if _supply_cache.has(faction) and old.size()==5 and old[0]==inputs[0] and old[1]==city_ids and old[4]==seeds and _supply_blockades_outside_tree(graph,_supply_cache[faction],old,blocked,blocked_edges):
			_supply_cache[faction].blocked_edges=blocked_edges;_compact_supply_inputs[faction]=inputs
			performance_metrics["supply_far_blockade_reuses"]=int(performance_metrics.get("supply_far_blockade_reuses",0))+1
			continue
		_compact_supply_inputs[faction]=inputs
		# Keep v4 supply passability semantics exactly; route searches still enforce it.
		var solved: Dictionary=graph.solve(seeds,blocked,blocked_edges,_supply_max_distance(),-1,false)
		performance_metrics["supply_node_visits"]+=int(solved.visits)
		_supply_cache[faction]={"distance_indices":solved.distance,"source_indices":solved.source,"previous_indices":solved.previous,"blocked_edges":blocked_edges,"city_ids":city_ids,"node_ids":graph.ids,"node_index":graph.index,"discovered":solved.discovered}
	_supply_signature=_current_supply_signature();_supply_dirty=false

func supply_route_for(id: String) -> Dictionary:
	if not armies.has(id):return {"connected":false,"source":"","route":[],"reason":"Army does not exist"}
	var army: Dictionary=armies[id]
	if army.transport_elapsed>0:return {"connected":false,"source":"","route":[],"reason":"Ferry transit — using carried food"}
	if not army.supplied:return {"connected":false,"source":"","route":[],"reason":"Route blocked or out of supply range — using carried food"}
	var cache: Dictionary=_supply_cache.get(army.faction,{})
	var start: String=army.node
	var max_dist: int=_supply_max_distance()
	if army.edge_progress>0:
		for endpoint in [army.node,army.route[0]]:
			var i: int=int(cache.get("node_index",{}).get(endpoint,-1))
			var extra: int=army.edge_progress if endpoint==army.node else nodes[army.node].edges[army.route[0]]-army.edge_progress
			if i>=0 and cache.source_indices[i]>=0 and cache.city_ids[cache.source_indices[i]]==army.supply_source and cache.distance_indices[i]+extra<=max_dist:start=endpoint;break
	var route: Array=[start];var current: int=int(cache.get("node_index",{}).get(start,-1))
	if current>=0:
		for _step in range(nodes.size()):
			var parent: int=cache.previous_indices[current]
			if parent<0:break
			route.append(cache.node_ids[parent]);current=parent
	return {"connected":true,"source":army.supply_source,"route":route,"reason":"Supplied from "+army.supply_source}

func materialize_supply_cache() -> Dictionary:
	# Diagnostic compatibility view; normal updates do not rebuild thousands of dictionaries.
	var result: Dictionary={}
	for faction in _supply_cache:
		var cache: Dictionary=_supply_cache[faction];var distances: Dictionary={};var sources: Dictionary={};var previous: Dictionary={}
		for i in cache.discovered:
			var id: String=cache.node_ids[i];distances[id]=int(cache.distance_indices[i]);sources[id]=cache.city_ids[cache.source_indices[i]]
			previous[id]="" if cache.previous_indices[i]<0 else cache.node_ids[cache.previous_indices[i]]
		result[faction]={"distances":distances,"sources":sources,"blocked_edges":cache.blocked_edges,"previous":previous}
	return result

func _update_supply(consume: bool) -> void:
	if _current_supply_signature()!=_supply_signature:_supply_dirty=true
	if _supply_dirty:_rebuild_supply_cache()
	for id in _sorted_ids(armies):
		var army: Dictionary=armies[id];var cache: Dictionary=_supply_cache.get(army.faction,{})
		var i: int=int(cache.get("node_index",{}).get(army.node,-1));var source: String=""
		if i>=0 and cache.source_indices[i]>=0:source=cache.city_ids[cache.source_indices[i]]
		var connected: bool=not source.is_empty() and army.transport_elapsed==0
		if army.edge_progress>0 and army.transport_elapsed==0:
			connected=false
			if not army.route.is_empty():
				var next: String=army.route[0]
				if not cache.get("blocked_edges",{}).has(_edge_key(army.node,next)):
					for endpoint in [army.node,next]:
						var j: int=int(cache.get("node_index",{}).get(endpoint,-1))
						var extra: int=army.edge_progress if endpoint==army.node else nodes[army.node].edges[next]-army.edge_progress
						if j>=0 and cache.source_indices[j]>=0 and cache.distance_indices[j]+extra<=_supply_max_distance():connected=true;source=cache.city_ids[cache.source_indices[j]];break
		if army.troops<=0:connected=false
		army.supplied=connected;army.supply_source=source if connected else ""
		if not consume or army.troops<=0:continue
		army.food=maxi(0,int(army.food)-1)
		if connected:
			var amount: int=mini(3,mini(int(cities[source].food),int(army.food_capacity)-int(army.food)))
			army.food+=amount;cities[source].food-=amount;army.morale=mini(100,int(army.morale)+2)
		if army.food==0:
			army.morale=maxi(0,int(army.morale)-2);army.troops=maxi(0,int(army.troops)-1)
			if army.troops==0:_defeat(army,"starvation")

func _validate_production(city_table: Dictionary,army_table: Dictionary) -> String:
	var validation: Dictionary=city_table.duplicate(true)
	for city in validation.values():
		for job in city["production_queue"]:
			if not job is Dictionary or job.get("unit_type") not in PROFILES or not _integer_at_least(job.get("remaining_ticks"),1): return "Recruitment job is invalid."
			if int(job["remaining_ticks"])>int(PROFILES[job["unit_type"]]["training"]): return "Recruitment duration is invalid."
			job["remaining_ticks"]=1
	return super._validate_production(validation,army_table)

func queue_recruitment(faction: String,city_id: String,army_id: String,troops: int=500,unit_type: String="infantry") -> String:
	if match_state=="finished": return "Campaign finished."
	if unit_type not in PROFILES or troops<1 or troops>3000: return "Recruitment type or troop count is invalid."
	var active: int=0
	for army in armies.values():
		if army["faction"]==faction and int(army["troops"])>0: active+=1
	for city in cities.values():
		for job in city["production_queue"]:
			if job["faction"]==faction: active+=1
	if active>=8: return "Faction army limit reached."
	var cost: int=troops*int(PROFILES[unit_type]["cost"])
	var error: String=super.queue_recruitment(faction,city_id,army_id,cost,unit_type)
	if not error.is_empty(): return error
	var job: Dictionary=cities[city_id]["production_queue"].back()
	job["troops"]=troops; job["remaining_ticks"]=PROFILES[unit_type]["training"]
	return ""

func _update_production() -> void:
	for city_id in _sorted_ids(cities):
		var city: Dictionary=cities[city_id]
		if _city_under_siege(city): continue
		if tick%FOOD_INTERVAL==0: city["food"]+=int(city["food_per_interval"])
		if city["production_queue"].is_empty(): continue
		var job: Dictionary=city["production_queue"][0]; job["remaining_ticks"]-=1
		if int(job["remaining_ticks"])>0: continue
		city["production_queue"].pop_front()
		var id: String=job["army_id"]; var profile: Dictionary=PROFILES[job["unit_type"]]
		armies[id]={"id":id,"faction":job["faction"],"node":city["node"],"troops":job["troops"],"food_capacity":120,"food":80,"morale":100,
			"movement_per_tick":profile["movement"],"attack":10,"defense":10,"siege_power":profile["siege"],"supplied":false,
			"order":{"type":"hold","target":""},"route":[],"edge_progress":0,"siege_state":"none","unit_type":job["unit_type"],"stance":"balanced"}
		_initialize_army(armies[id]); _supply_dirty=true
		_emit("army_recruited",{"city":city_id,"army":id,"faction":job["faction"],"unit_type":job["unit_type"]})

func snapshot() -> Dictionary:
	var data:=super.snapshot()
	data["format_version"]=CAMPAIGN_FORMAT
	data["campaign"]={"world":world_metadata.duplicate(true),"match_state":match_state,"continued":continued}
	return data

func _validate_saved_army(id,army,state: Dictionary) -> String:
	if not army is Dictionary: return "Save army is invalid."
	var proxy: Dictionary=army.duplicate(true)
	if army.get("order") is Dictionary and army["order"].get("type")=="hold" and army.get("route") is Array and not army["route"].is_empty():
		proxy["order"]={"type":"move","target":army["route"].back()}
	if proxy.get("siege_state")=="aborted": proxy["siege_state"]="none"
	var error: String=super._validate_saved_army(id,proxy,state)
	if not error.is_empty(): return error
	if not army.get("routed") is bool or not army.get("engaged_ids") is Array or not army.get("transport_id") is String or not army.get("deferred_order") is Dictionary: return "Save campaign army state is invalid."
	for key in ["rout_until","transport_elapsed","transport_queued_tick"]:
		if not _integer_at_least(army.get(key),0): return "Save campaign army timer is invalid."
	for other in army["engaged_ids"]:
		if not other is String or not state["armies"].has(other): return "Save engagement target is invalid."
	if not army["deferred_order"].is_empty():
		error=_validate_saved_order(army["deferred_order"],state["nodes"],state["armies"],state["cities"])
		if not error.is_empty(): return error
	return ""

func load_json(text: String) -> String:
	var parser:=JSON.new()
	if parser.parse(text)!=OK or not parser.data is Dictionary: return "Save file is not valid JSON."
	if _contains_fractional_number(parser.data): return "Save requires integer state."
	var data: Dictionary=_integer_data(parser.data)
	return _load_campaign_data(data)

func _load_campaign_data(data: Dictionary, trusted_world: bool=false) -> String:
	if data.get("format_version")!=CAMPAIGN_FORMAT or not data.get("campaign") is Dictionary: return "Campaign save format is unsupported."
	var campaign: Dictionary=data["campaign"]
	if campaign.get("match_state") not in ["running","finished"] or not campaign.get("continued") is bool or not campaign.get("world") is Dictionary: return "Save campaign metadata is invalid."
	if not _integer_at_least(data.get("tick"),0): return "Save campaign tick is invalid."
	if not data.get("armies") is Dictionary: return "Save army table is invalid."
	if campaign["match_state"]=="finished" and (campaign["continued"] or data.get("paused")!=true or not data.get("winner") is String or data["winner"].is_empty()): return "Save finished match state is invalid."
	if campaign["match_state"]=="running" and data.get("winner","")!="": return "Save running match state is invalid."
	var world: Dictionary=campaign["world"].duplicate(); world["nodes"]=data.get("nodes")
	var error: String=""
	if not trusted_world:
		error=_validate_world(world)
		if not error.is_empty(): return error
	if get("allow_world_switch")!=true and not world_metadata.is_empty() and (world.get("id")!=world_metadata.get("id") or world.get("revision")!=world_metadata.get("revision") or world.get("sha256","")!=world_metadata.get("sha256","")): return "Save belongs to a different world revision."
	if get("allow_world_switch")!=true and not world_metadata.is_empty() and (campaign["world"]!=world_metadata or world["nodes"]!=nodes): return "Save world content differs from the configured world."
	var preserve_navigation: bool=not _settlement_route_cache.is_empty() and campaign["world"]==world_metadata and world["nodes"]==nodes
	var passengers: Dictionary={}
	for army in data.get("armies",{}).values():
		if not army is Dictionary: return "Save army is invalid."
		if not army.get("deferred_order") is Dictionary: return "Save deferred ferry order is invalid."
		for key in ["transport_elapsed","transport_queued_tick"]:
			if not _integer_at_least(army.get(key),0): return "Save ferry timer is invalid."
		if not army.get("transport_id") is String: return "Save ferry identity is invalid."
		if army["transport_id"].is_empty() and (army["transport_elapsed"]!=0 or not army.get("deferred_order",{}).is_empty()): return "Save inactive ferry state is invalid."
		if not str(army.get("transport_id","")).is_empty():
			var found: bool=false
			for crossing in world.get("crossings",[]):
				if crossing["id"]!=army["transport_id"]: continue
				if army.get("node") not in crossing["nodes"] or not army.get("route") is Array or army["route"].is_empty() or army["route"][0] not in crossing["nodes"] or army["route"][0]==army["node"]: continue
				var elapsed: int=army["transport_elapsed"]
				if elapsed>=int(crossing["travel_ticks"]) or army["transport_queued_tick"]>data.get("tick",-1): continue
				var length: int=world["nodes"][army["node"]]["edges"][army["route"][0]]
				# Departure starts with zero progress; each later tick advances.
				var expected: int=0 if elapsed<=1 else mini(length-1,int(length*elapsed/int(crossing["travel_ticks"])))
				if army.get("edge_progress")!=expected: continue
				if elapsed>0:
					passengers[crossing["id"]]=int(passengers.get(crossing["id"],0))+1
					if passengers[crossing["id"]]>crossing["capacity_formations"]: return "Save ferry capacity is exceeded."
				found=true
			if not found: return "Save ferry progress is invalid."
	var proxy: Dictionary=data.duplicate();proxy["format_version"]=FORMAT_VERSION;proxy.erase("campaign")
	error=super._load_base_data(proxy,trusted_world)
	if not error.is_empty(): return error
	if not preserve_navigation:_settlement_route_cache.clear();_reverse_routes.clear()
	world_metadata=campaign["world"]; match_state=campaign["match_state"]; continued=campaign["continued"]
	_rebuild_crossings(); _refresh_contacts()
	_rebuild_navigation_mask(world)
	return ""

func route_to_settlement(start: String, target: String) -> Dictionary:
	# Only the content-hashed immutable campaign graph uses persistent routing caches.
	# Dynamic unit occupancy never participates in these static route costs.
	if str(world_metadata.get("sha256","")).length()!=64:return {}
	var settlement: bool=false
	for city in cities.values():
		if target in city.get("gate_nodes",[city.node]):settlement=true;break
	if not settlement:return {}
	if not nodes.has(start) or not nodes.has(target):return {"ok":false,"route":[],"distance":-1}
	if not _settlement_route_cache.has(target):
		if _reverse_routes.is_empty():
			for id in nodes:_reverse_routes[id]={}
			for id in nodes:
				for other in nodes[id].edges:_reverse_routes[other][id]=nodes[id].edges[other]
		var distance: Dictionary={target:0};var next: Dictionary={};var open=PriorityQueue.new()
		open.push(0,target)
		while not open.is_empty():
			var entry: Array=open.pop();var current: String=entry[1]
			if entry[0]!=distance[current]:continue
			if current!=target and not is_navigation_open(current):continue
			for previous in _sorted_ids(_reverse_routes[current]):
				var cost: int=int(distance[current])+int(_reverse_routes[current][previous])
				if not distance.has(previous) or cost<int(distance[previous]):
					distance[previous]=cost;next[previous]=current;open.push(cost,previous)
		_settlement_route_cache[target]={"distance":distance,"next":next}
	var tree: Dictionary=_settlement_route_cache[target]
	if not tree.distance.has(start):return {"ok":false,"route":[],"distance":-1}
	var route: Array=[];var current: String=start
	while current!=target:
		current=tree.next[current];route.append(current)
	return {"ok":true,"route":route,"distance":tree.distance[start]}

func prewarm_campaign_navigation() -> Dictionary:
	# Invoke while loading, before starting the simulation clock. Static route
	# caches do not modify orders, resources, pending events or saved state.
	var began: int=Time.get_ticks_usec()
	lock_navigation_topology()
	var starts: Dictionary={}
	for army in armies.values():
		if int(army.troops)>0:starts[army.node]=true
	var origin: String=""
	for id in _sorted_ids(nodes):
		if is_navigation_open(id):origin=id;break
	if origin.is_empty():return {"milliseconds":0.0,"settlement_trees":0,"army_start_trees":0}
	for city_id in _sorted_ids(cities):
		for gate in cities[city_id].get("gate_nodes",[cities[city_id].node]):route_to_settlement(origin,gate)
	for start in _sorted_ids(starts):find_routes_from(start)
	return {"milliseconds":float(Time.get_ticks_usec()-began)/1000.0,"settlement_trees":_settlement_route_cache.size(),"army_start_trees":starts.size()}
