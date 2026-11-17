extends "res://scripts/rts_commander_campaign.gd"
## Authored design revision 2. Integer fixed-point resources; presentation never deals damage.
const SCALE=1000
const BATTLE_FORMAT=14
const Traditional=preload("res://scripts/rts_traditional_rules.gd")
const Tactical=preload("res://scripts/rts_tactical_rules.gd")
const TacticalCombat=preload("res://scripts/rts_tactical_combat.gd")
const TacticalOrders=preload("res://scripts/rts_tactical_orders.gd")
var traditional_rts: bool=true
var tactical_rts: bool=true
var navigation_warmup: bool=true
var allow_world_switch: bool=true
const RiverNavigation=preload("res://scripts/rts_river_navigation.gd")
const BoatTransport=preload("res://scripts/rts_boat_transport.gd")
const GameplaySave=preload("res://scripts/rts_gameplay_save.gd")
var river_navigation: RefCounted=RiverNavigation.new()
var vessels: Dictionary={}
const WINDUP_US=350000
## Ranged volley lethality. 3 wiped a committed assault before it could clear a
## 1,000-guard city; 2 lets a real cohort capture in ~110 s (measured 2026-11-03).
const VOLLEY_MULTIPLIER=2
const GOLD_COST={"infantry":300,"archers":450,"cavalry":750,"siege":900}
const FOOD_UPKEEP={"infantry":16,"archers":16,"cavalry":24,"siege":20}
const GOLD_UPKEEP={"infantry":3,"archers":4,"cavalry":7,"siege":5}
var faction_gold: Dictionary={}
var operations: Array=[]
var transfers: Array=[]
var pending_volleys: Array=[]
var pending_windups: Array=[]
var operation_serial: int=0
var outcome: Dictionary={}

func configure(world: Dictionary, initial_armies: Array, initial_cities: Array, initial_seed: int=1) -> String:
	if not traditional_rts:tactical_rts=false
	var error: String=super.configure(world,initial_armies,initial_cities,initial_seed)
	if not error.is_empty():return error
	speed=1
	faction_gold={"wei":1000*SCALE,"shu":1000*SCALE,"wu":1000*SCALE}
	operations.clear();transfers.clear();pending_volleys.clear();pending_windups.clear();operation_serial=0;outcome.clear()
	river_navigation.configure(world_metadata);vessels=BoatTransport.initial(world_metadata)
	for id in cities:
		var c: Dictionary=cities[id];var village: bool=c.kind=="village";var extra: bool=id in ["C5","C6"]
		c.wall_hp=0 if village else 300 if traditional_rts else 1200;c.wall_max=c.wall_hp
		c.garrison=(50 if village else 250) if traditional_rts else (100 if village else 1000);c.people_capacity=100 if village else 2000 if traditional_rts else 10000
		c.food_cap=(2000 if village else 6000)*SCALE
		c.food_per_interval=(30 if village else 90 if extra else 60)*SCALE
		c.gold_per_interval=5000 if village else 22500 if extra else 15000
		c.recruits=0 if village else 750 if extra else 500
		c.recruits_cap=0 if village else 2250 if extra else 1500
		c.recruits_per_interval=0 if village else 30 if extra else 20
		c.capture_ticks=0;c.capture_faction="";c.last_siege_tick=0;c.repair={}
		c.city_hp=0 if village else 400 if traditional_rts else 1000;c.city_hp_max=c.city_hp;c.city_morale=100
		if tactical_rts and not village:
			c.wall_hp=Tactical.WALL_HP;c.wall_max=Tactical.WALL_HP;c.garrison=Tactical.CITY_GARRISON
			c.city_hp=Tactical.CITY_HP;c.city_hp_max=Tactical.CITY_HP
		c.starved_ticks=0;c.unpaid_ticks=0;c.food=0
	for a in armies.values():_init_design_army(a,true)
	for faction in Officers.FACTIONS:
		var stock: int=6000*SCALE;var total: int=0;var homes: Array=[]
		for a in armies.values():
			if a.faction==faction:stock-=a.food
		for id in _sorted_ids(cities):
			if cities[id].owner==faction:homes.append(id);total+=cities[id].food_per_interval
		var left: int=stock
		for id in homes:
			var amount: int=stock*int(cities[id].food_per_interval)/maxi(1,total)
			cities[id].food=amount;left-=amount
		if not homes.is_empty():cities[homes[0]].food+=left
	_supply_dirty=true;_update_supply(false)
	prewarm_campaign_navigation()
	return ""

func _init_design_army(a: Dictionary, initial: bool=false) -> void:
	if tactical_rts:TacticalOrders.initialize(a)
	if traditional_rts:Traditional.configure_army(a)
	else:a.erase("traditional_unit")
	a.original_troops=int(a.troops);a.resident_city="";a.garrison_target="";a.entry_ticks=0;a.sortie_pending=false
	a.starved_ticks=0;a.unpaid_ticks=0;a.last_volley_tick=-30
	a.food_capacity=_food_rate(a)*12;a.food=_food_rate(a)*8 if initial else 0

func food_units(value: int) -> int:return value/SCALE
func _food_rate(a: Dictionary) -> int:return int(a.troops)*SCALE*int(FOOD_UPKEEP[a.unit_type])/500
func _gold_rate(a: Dictionary) -> int:return int(a.troops)*SCALE*int(GOLD_UPKEEP[a.unit_type])/500
func rations_seconds(id: String) -> int:
	if not armies.has(id) or armies[id].troops<=0:return 0
	return int(armies[id].food)*10/maxi(1,_food_rate(armies[id]))

func resident_ids(id: String) -> Array:
	var result: Array=[]
	for key in _sorted_ids(armies):
		if armies[key].troops>0 and armies[key].get("resident_city","")==id:result.append(key)
	return result

func _capacity_for(id: String, army_table: Dictionary, city_table: Dictionary, op_table: Array) -> int:
	var total: int=int(city_table[id].garrison)
	for a in army_table.values():
		if a.troops>0 and (a.get("resident_city","")==id or a.get("garrison_target","")==id):total+=int(a.troops)
	for job in city_table[id].production_queue:total+=int(job.troops)
	for op in op_table:
		if op.city==id and op.type=="reinforce":total+=int(op.amount)
	return total

func city_capacity(id: String) -> int:return _capacity_for(id,armies,cities,operations) if cities.has(id) else 0
func capacity_breakdown(id: String) -> Dictionary:
	var result: Dictionary={"guards":0,"residents":0,"incoming":0,"training":0,"reinforcement":0,"total":0}
	if not cities.has(id):return result
	result.guards=int(cities[id].garrison)
	for a in armies.values():
		if a.troops<=0:continue
		if a.resident_city==id:result.residents+=int(a.troops)
		elif a.garrison_target==id:result.incoming+=int(a.troops)
	for job in cities[id].production_queue:result.training+=int(job.troops)
	for op in operations:
		if op.city==id:result.reinforcement+=int(op.amount)
	for key in ["guards","residents","incoming","training","reinforcement"]:result.total+=int(result[key])
	return result

func salary_arrears(faction: String) -> int:
	var overdue: int=0
	for a in armies.values():
		if a.faction==faction and a.troops>0:overdue=maxi(overdue,int(a.unpaid_ticks))
	for c in cities.values():
		if c.owner==faction and c.garrison>0:overdue=maxi(overdue,int(c.unpaid_ticks))
	return overdue

func faction_troops(faction: String) -> int:
	var total: int=0
	for c in cities.values():
		if c.owner==faction:total+=int(c.garrison)
	for a in armies.values():
		if a.faction==faction:total+=int(a.troops)
	return total

func enemy_troops(faction: String) -> int:
	var total: int=0
	for f in Officers.FACTIONS:
		if f!=faction:total+=faction_troops(f)
	return total

func _new_id(prefix: String) -> String:
	operation_serial+=1;return "%s-%d"%[prefix,operation_serial]

func _city_access(faction: String, id: String, peaceful: bool=true) -> String:
	if match_state=="finished":return "Campaign finished."
	if not cities.has(id) or cities[id].owner!=faction:return "Choose a friendly settlement."
	if peaceful and _city_under_siege(cities[id]):return "Settlement is under siege."
	return ""

func _army_access(faction: String, id: String) -> String:
	if match_state=="finished":return "Campaign finished."
	if not armies.has(id) or armies[id].faction!=faction or armies[id].troops<=0:return "Choose a living friendly formation."
	if armies[id].transport_elapsed>0 or armies[id].routed or not armies[id].engaged_ids.is_empty():return "Formation is fighting, routing or aboard a ferry."
	return ""

func _spend(faction: String, city_id: String, food: int, gold: int, recruits: int) -> String:
	var c: Dictionary=cities[city_id]
	if gold>0 and salary_arrears(faction)>=300:return "Pay overdue faction salaries before training or repairing."
	if c.food<food:return "Not enough Food."
	if int(faction_gold.get(faction,0))<gold:return "Not enough Gold."
	if c.recruits<recruits:return "Not enough Recruits."
	c.food-=food;faction_gold[faction]-=gold;c.recruits-=recruits;_supply_dirty=true
	return ""

func recruit_with_commander(faction: String, city_id: String, army_id: String, officer_id: String, troops: int=500, kind: String="infantry") -> String:
	var error: String=_city_access(faction,city_id,false)
	if not error.is_empty():return error
	var c: Dictionary=cities[city_id]
	if not c.recruitment_enabled or kind not in PROFILES or troops<1 or troops>3000:return "Recruitment type, count or settlement is invalid."
	if officer_id not in available_commanders(faction):return "Choose an available commander."
	if army_id.is_empty() or armies.has(army_id):return "Recruitment identity already exists."
	var count: int=0
	for a in armies.values():
		if a.faction==faction and a.troops>0:count+=1
	for city in cities.values():
		for job in city.production_queue:
			if job.army_id==army_id:return "Recruitment identity already exists."
			if job.faction==faction:count+=1
	if count>=formation_limit():return "Faction squad limit reached, including residents and training."
	if c.production_queue.size()>=3:return "City training queue is full."
	if city_capacity(city_id)+troops>c.people_capacity:return "City capacity would exceed %d people."%int(c.people_capacity)
	var food: int=troops*int(PROFILES[kind].cost)*SCALE
	var gold: int=troops*int(GOLD_COST[kind])*SCALE/500
	error=_spend(faction,city_id,food,gold,troops)
	if not error.is_empty():return error
	c.production_queue.append({"army_id":army_id,"faction":faction,"unit_type":kind,"troops":troops,"remaining_ticks":Traditional.training(kind) if traditional_rts else int(PROFILES[kind].training),"commander_id":officer_id,"food_cost":food,"gold_cost":gold})
	officers[officer_id].reserved_army=army_id
	_emit("commander_reserved",{"army":army_id,"officer":officer_id,"city":city_id})
	return ""

func cancel_training(faction: String, city_id: String, index: int) -> String:
	var error: String=_city_access(faction,city_id,false)
	if not error.is_empty():return error
	var c: Dictionary=cities[city_id]
	if index<0 or index>=c.production_queue.size():return "Training job no longer exists."
	var job: Dictionary=c.production_queue[index]
	c.production_queue.remove_at(index)
	c.food=mini(c.food_cap,c.food+int(job.food_cost)/2);c.recruits=mini(c.recruits_cap,c.recruits+int(job.troops))
	faction_gold[faction]+=int(job.gold_cost)/2;_reconcile_reservations();_supply_dirty=true
	_emit("recruitment_cancelled",{"city":city_id,"army":job.army_id,"reason":"Player cancelled; Recruits and half Food/Gold refunded."})
	return ""

func request_garrison(faction: String, army_id: String, city_id: String) -> String:
	var error: String=_city_access(faction,city_id,false)
	if not error.is_empty():return error
	error=_army_access(faction,army_id)
	if not error.is_empty():return error
	var a: Dictionary=armies[army_id];var c: Dictionary=cities[city_id]
	if c.kind!="city" or not a.resident_city.is_empty():return "Choose a city for a field formation."
	if a.garrison_target==city_id:return ""
	var slots: int=resident_ids(city_id).size()
	for other in armies.values():
		if other.troops>0 and other.garrison_target==city_id and other.id!=army_id:slots+=1
	if slots>=2:return "City already has two resident or incoming formations."
	if city_capacity(city_id)+a.troops>c.people_capacity:return "City capacity would exceed %d people."%int(c.people_capacity)
	if not _set_order(a,{"type":"move","target":c.node}):return "No route to this city."
	_cancel_earlier_field_orders(army_id)
	if tactical_rts:a.waypoints.clear();a.combat_target="";a.stuck_ticks=0
	a.garrison_target=city_id;a.entry_ticks=0
	_emit("garrison_order",{"army":army_id,"city":city_id});return ""

func request_sortie(faction: String, army_id: String) -> String:
	var error: String=_army_access(faction,army_id)
	if not error.is_empty():return error
	var a: Dictionary=armies[army_id]
	if a.resident_city.is_empty():return "Formation is not resident in a city."
	if cities[a.resident_city].owner!=faction:return "City no longer belongs to this formation."
	for op in operations:
		if op.army==army_id:return "Wait for reinforcement to finish."
	a.sortie_pending=true;return ""

func request_reinforce(faction: String, city_id: String, army_id: String="") -> String:
	var error: String=_city_access(faction,city_id)
	if not error.is_empty():return error
	var c: Dictionary=cities[city_id]
	if c.kind!="city":return "Villages cannot train replacements."
	var amount: int=100;var gold: int=50*SCALE
	if not army_id.is_empty():
		error=_army_access(faction,army_id)
		if not error.is_empty():return error
		var a: Dictionary=armies[army_id]
		if a.resident_city!=city_id or a.sortie_pending:return "Reinforce a formation resident in this city."
		amount=mini(100,int(a.original_troops)-int(a.troops));gold=amount*int(GOLD_COST[a.unit_type])*SCALE/500
	if amount<=0:return "Formation already has its original troop strength."
	for op in operations:
		if op.city==city_id and op.army==army_id:return "Reinforcement is already in progress."
	if city_capacity(city_id)+amount>c.people_capacity:return "City capacity would exceed %d people."%int(c.people_capacity)
	error=_spend(faction,city_id,amount*SCALE,gold,amount)
	if not error.is_empty():return error
	operations.append({"id":_new_id("reinforce"),"type":"reinforce","city":city_id,"army":army_id,"faction":faction,"amount":amount,"remaining_ticks":50})
	return ""

func request_disband(faction: String, army_id: String) -> String:
	var error: String=_army_access(faction,army_id)
	if not error.is_empty():return error
	var a: Dictionary=armies[army_id]
	if a.resident_city.is_empty():return "Disband only in a friendly city."
	error=_city_access(faction,a.resident_city)
	if not error.is_empty():return error
	for op in operations:
		if op.army==army_id:return "Wait for reinforcement to finish."
	var c: Dictionary=cities[a.resident_city]
	c.recruits=mini(c.recruits_cap,c.recruits+int(a.troops)/2);c.food=mini(c.food_cap,c.food+a.food)
	a.food=0;a.troops=0;_defeat(a,"disbanded");return ""

func request_repair(faction: String, city_id: String) -> String:
	var error: String=_city_access(faction,city_id)
	if not error.is_empty():return error
	var c: Dictionary=cities[city_id]
	if c.wall_hp>=c.wall_max:return "Walls are already repaired."
	if not c.repair.is_empty():return "Repair is already in progress."
	if tick-int(c.last_siege_tick)<150:return "Wait 15 seconds after siege before repairing."
	error=_spend(faction,city_id,40*SCALE,20*SCALE,0)
	if not error.is_empty():return error
	c.repair={"faction":faction,"remaining_ticks":250};return ""

func request_transfer(faction: String, source_city: String, destination_city: String, amount: int) -> String:
	var error: String=_city_access(faction,source_city)
	if not error.is_empty():return error
	error=_city_access(faction,destination_city)
	if not error.is_empty():return error
	if source_city==destination_city or amount<1 or amount>6000:return "Choose another warehouse and a positive Food amount."
	if transfers.size()>=24:return "Logistics transfer limit reached."
	var route: Dictionary=find_path(cities[source_city].node,cities[destination_city].node)
	if not route.ok:return "No logistics route between these warehouses."
	var moving: int=amount*SCALE
	if cities[destination_city].food+moving>cities[destination_city].food_cap:return "Destination warehouse lacks space."
	var reserved: int=0
	for t in transfers:
		if t.destination==destination_city:reserved+=int(t.amount)
	if cities[destination_city].food+reserved+moving>cities[destination_city].food_cap:return "Destination space is already reserved for other transfers."
	error=_spend(faction,source_city,moving,0,0)
	if not error.is_empty():return error
	transfers.append({"id":_new_id("food"),"source":source_city,"destination":destination_city,"faction":faction,"amount":moving,"route":[cities[source_city].node]+route.route,"leg":0,"progress":0,"ferry_ticks":0,"ferry_id":"","queued_tick":0,"departed":false,"state":"Reserved"})
	_emit("food_reserved",{"source":source_city,"destination":destination_city,"food":amount});return ""

func cancel_transfer(faction: String, id: String) -> String:
	for i in range(transfers.size()):
		var t: Dictionary=transfers[i]
		if t.id!=id:continue
		if t.faction!=faction or t.departed:return "Only an undeparted friendly transfer can be cancelled."
		if cities[t.source].owner==faction:cities[t.source].food=mini(cities[t.source].food_cap,cities[t.source].food+t.amount)
		BoatTransport.cancel_reservation(self,"cargo:"+id)
		transfers.remove_at(i);return ""
	return "Transfer no longer exists."

func _set_order(a: Dictionary, order: Dictionary) -> bool:
	if not a.get("resident_city","").is_empty():return false
	if tactical_rts and order.type=="attack" and not TacticalOrders.field_enemy(self,a,order.target):return false
	# A re-issued order must not eject a formation from the ferry queue: the queue
	# identity and its timestamp survive while the new route still crosses the same
	# ferry from the same node. Measured 2026-11-03: formations queued at ferry1 were
	# re-queued every 40 ticks by the AI and never boarded.
	if order.type=="siege":
		order=order.duplicate()
		if not cities.has(order.target):return false
		var gate: String=str(order.get("gate_node",""))
		if gate.is_empty():gate=choose_siege_gate(a,str(order.target))
		if gate not in gate_nodes(str(order.target)):return false
		order.gate_node=gate
	var was_queued: String=str(a.get("transport_id",""))
	var was_tick: int=int(a.get("transport_queued_tick",0))
	var was_node: String=str(a.get("node",""))
	var keep_queue: bool=false
	if not was_queued.is_empty() and int(a.get("transport_elapsed",0))==0 and not a.get("route",[]).is_empty():
		var key: String=_edge_key(was_node,a.route[0])
		keep_queue=_crossing_by_edge.has(key) and str(_crossing_by_edge[key].id)==was_queued
	var ok: bool=super._set_order(a,order)
	if ok and keep_queue and str(a.get("node",""))==was_node and not a.get("route",[]).is_empty():
		var next_key: String=_edge_key(a.node,a.route[0])
		if _crossing_by_edge.has(next_key) and str(_crossing_by_edge[next_key].id)==was_queued:
			a["transport_id"]=was_queued;a["transport_queued_tick"]=was_tick
	if ok and not was_queued.is_empty() and a.get("transport_id","")!=was_queued:BoatTransport.cancel_reservation(self,"army:"+str(a.id))
	if ok and not a.get("garrison_target","").is_empty():
		if order.type!="move" or order.target!=cities[a.garrison_target].node:a.garrison_target="";a.entry_ticks=0
	if ok and tactical_rts and order.type in ["move","retreat","hold"]:_cancel_field_windup(str(a.id))
	return ok

func _cancel_field_windup(army_id: String) -> void:
	var kept: Array=[]
	for job in pending_windups:
		if job.source==army_id and job.kind=="army" and job.mode=="field":
			_emit("volley_cancelled",{"windup":job.id,"reason":"Movement or stop interrupted the draw."})
		else:kept.append(job)
	pending_windups=kept

func submit_command(command: Dictionary) -> String:
	if not command.get("army_ids") is Array:return "Command schema is invalid."
	if tactical_rts:
		var queue_error: String=TacticalOrders.check_queue(self,command)
		if not queue_error.is_empty():return queue_error
	if command.get("type") in ["move","retreat","attack_move"]:
		var destination: String=str(command.get("target",""))
		if not is_navigation_open(destination):return "Move destination is blocked or missing."
		for id in command.army_ids:
			if armies.has(id) and not find_path(armies[id].node,destination).ok:return "No valid route for the entire movement group."
	if command.has("gate_node") and (command.get("type")!="siege" or not command.gate_node is String or command.gate_node not in gate_nodes(str(command.get("target","")))):return "Siege gate does not belong to the target city."
	if command.get("type")=="siege":
		for id in command.get("army_ids",[]):
			if not armies.has(id):continue
			var gate: String=str(command.get("gate_node",choose_siege_gate(armies[id],str(command.get("target","")))))
			if gate.is_empty() or not find_path(armies[id].node,gate).ok:return "No reachable gate for the entire assault group."
	for id in command.get("army_ids",[]):
		if armies.has(id) and not armies[id].get("resident_city","").is_empty():return "Sortie before issuing field orders."
		if tactical_rts and armies.has(id) and command.get("type")=="attack" and not TacticalOrders.field_enemy(self,armies[id],str(command.get("target",""))):return "Attack target is not an available enemy field formation."
	var error: String=super.submit_command(command)
	if error.is_empty() and tactical_rts:command_queue[-1].append=command.get("append",false)
	return error

func gate_nodes(city_id: String) -> Array:
	if not cities.has(city_id):return []
	return cities[city_id].get("gate_nodes",[cities[city_id].node])

func choose_siege_gate(a: Dictionary, city_id: String) -> String:
	if a.order.type=="siege" and a.order.target==city_id and a.order.get("gate_node","") in gate_nodes(city_id):return a.order.gate_node
	var chosen: String="";var distance: int=2147483647
	for gate in gate_nodes(city_id):
		var route: Dictionary=route_to_settlement(a.node,gate)
		if route.is_empty():route=find_path(a.node,gate)
		if route.ok and (route.distance<distance or (route.distance==distance and str(gate)<chosen)):
			chosen=gate;distance=int(route.distance)
	return chosen

func _target_node(order: Dictionary) -> String:
	if order.get("type")=="siege" and cities.has(order.get("target","")):
		var gate: String=str(order.get("gate_node",cities[order.target].node))
		return gate if gate in gate_nodes(order.target) else ""
	return super._target_node(order)

func _validate_saved_order(order, graph: Dictionary, army_table: Dictionary, city_table: Dictionary) -> String:
	var error: String=super._validate_saved_order(order,graph,army_table,city_table)
	if not error.is_empty():return error
	if order.has("gate_node"):
		if order.type!="siege" or not order.gate_node is String or order.gate_node not in city_table[order.target].get("gate_nodes",[city_table[order.target].node]):return "Save siege gate is invalid."
	return ""

func _guard_origin(c: Dictionary, target: Dictionary) -> Vector2:
	if tactical_rts:return TacticalCombat.guard_origin(self,c,target)
	var chosen: Vector2=_point({"node":c.node,"edge_progress":0,"route":[]});var distance: float=INF
	for gate in gate_nodes(c.id):
		var origin: Dictionary={"node":gate,"edge_progress":0,"route":[]}
		var candidate: Vector2=_point(origin);var length: float=candidate.distance_to(_point(target))
		if length<=120 and length<distance and has_line_of_sight(origin,target):chosen=candidate;distance=length
	return chosen

func _in_range(a: Dictionary,b: Dictionary) -> bool:
	if not a.get("resident_city","").is_empty() or not b.get("resident_city","").is_empty():return false
	return super._in_range(a,b)

func _defeat(a: Dictionary, reason: String) -> void:
	if tactical_rts:
		a.waypoints.clear();a.combat_target="";a.stuck_ticks=0
		for other in armies.values():
			if other.get("combat_target","")==a.id:other.combat_target=""
			if other.order.get("type","")=="attack" and other.order.get("target","")==a.id:
				TacticalOrders.advance(self,other)
	BoatTransport.cancel_reservation(self,"army:"+str(a.id))
	a.resident_city="";a.garrison_target="";a.sortie_pending=false;a.entry_ticks=0
	var windups: Array=[]
	for job in pending_windups:
		if job.kind!="army" or job.source!=a.id:windups.append(job)
	pending_windups=windups
	var kept: Array=[]
	for op in operations:
		if op.army!=a.id:kept.append(op)
	operations=kept;super._defeat(a,reason)

func _update_supply(consume: bool) -> void:
	super._update_supply(false)
	# Residents eat locally even when the road to their besieged gate is blockaded.
	for a in armies.values():
		if a.troops>0 and not a.resident_city.is_empty():
			var c: Dictionary=cities[a.resident_city]
			a.supplied=c.food>0;a.supply_source=c.id if a.supplied else ""
	if not consume:return
	for id in _sorted_ids(armies):
		var a: Dictionary=armies[id]
		if a.troops<=0:continue
		var rate: int=_food_rate(a);var capacity: int=rate*12
		# Casualties retain carried stock within the original capacity; no resource is silently deleted.
		a.food_capacity=maxi(int(a.food),capacity)
		var ate: int=0
		if not a.resident_city.is_empty():
			var c: Dictionary=cities[a.resident_city];ate=mini(c.food,rate);c.food-=ate
			var carried: int=mini(int(a.food),rate-ate);a.food-=carried;ate+=carried
			a.supplied=ate==rate;a.supply_source=c.id
		else:
			if a.supplied and cities.has(a.supply_source) and not _city_under_siege(cities[a.supply_source]):
				var c: Dictionary=cities[a.supply_source];var amount: int=mini(c.food,maxi(0,capacity-int(a.food)))
				c.food-=amount;a.food+=amount
			ate=mini(a.food,rate);a.food-=ate
		var paid: int=mini(int(faction_gold[a.faction]),_gold_rate(a));faction_gold[a.faction]-=paid
		a.starved_ticks=0 if ate==rate else int(a.starved_ticks)+100
		a.unpaid_ticks=0 if paid==_gold_rate(a) else int(a.unpaid_ticks)+100
		if ate<rate:
			a.morale=maxi(0,a.morale-2)
			if a.starved_ticks>=300:a.troops=maxi(0,a.troops-maxi(1,int(a.troops)/100))
		elif a.unpaid_ticks>=300:a.morale=maxi(0,a.morale-1)
		elif a.supplied:a.morale=mini(100,a.morale+2)
		if a.troops<=0:_defeat(a,"starvation")
	for c in cities.values():
		var need: int=int(c.garrison)*20;var ate: int=mini(c.food,need);c.food-=ate
		var wage: int=int(c.garrison)*4;var paid: int=mini(int(faction_gold.get(c.owner,0)),wage)
		faction_gold[c.owner]=int(faction_gold.get(c.owner,0))-paid
		c.starved_ticks=0 if ate==need else int(c.starved_ticks)+100;c.unpaid_ticks=0 if paid==wage else int(c.unpaid_ticks)+100
		if ate<need and c.starved_ticks>=300:c.garrison=maxi(0,c.garrison-maxi(1,int(c.garrison)/100))
	_supply_dirty=true

func _free_spawn(city_id: String) -> String:
	var candidates: Array=[]
	for s in world_metadata.settlements:
		if s.id==city_id:
			candidates=s.get("gate_nodes",[cities[city_id].node]).duplicate()
			if not candidates.has(cities[city_id].node):candidates.append(cities[city_id].node)
			break
	for node in candidates.duplicate():
		for other in _sorted_ids(nodes[node].edges):
			if other not in candidates:candidates.append(other)
	for node in candidates:
		if not is_navigation_open(node):continue
		var free: bool=true
		for a in armies.values():
			if a.troops>0 and a.resident_city.is_empty() and a.node==node and a.edge_progress==0:free=false;break
		if free:return node
	return ""

func _residency_tick() -> void:
	for id in _sorted_ids(armies):
		var a: Dictionary=armies[id]
		if a.troops<=0:continue
		if not a.garrison_target.is_empty():
			var c: Dictionary=cities[a.garrison_target]
			if c.owner!=a.faction:a.garrison_target="";a.entry_ticks=0;continue
			if a.node!=c.node or a.edge_progress>0 or not a.route.is_empty() or not a.engaged_ids.is_empty():a.entry_ticks=0;continue
			a.entry_ticks+=1
			if a.entry_ticks>=30:
				a.resident_city=c.id;a.garrison_target="";a.entry_ticks=0;_hold(a)
				_emit("formation_garrisoned",{"army":id,"city":c.id});_supply_dirty=true
		if a.sortie_pending and not a.resident_city.is_empty():
			var spawn: String=_free_spawn(a.resident_city)
			if spawn.is_empty():continue
			var city_id: String=a.resident_city;a.resident_city="";a.sortie_pending=false;a.node=spawn;_hold(a)
			_emit("formation_sortied",{"army":id,"city":city_id});_supply_dirty=true

func _update_production() -> void:
	# Unbesieged cities slowly recover structural integrity and civic morale.
	for id in _sorted_ids(cities):
		var city: Dictionary=cities[id]
		if not city.has("city_hp") or _city_under_siege(city):continue
		if tick%100==0:
			city.city_hp=mini(int(city.city_hp_max),int(city.city_hp)+2)
			city.city_morale=mini(100,int(city.city_morale)+2)
	for id in _sorted_ids(cities):
		var c: Dictionary=cities[id]
		var besieged: bool=_city_under_siege(c)
		if besieged:c.last_siege_tick=tick
		if tick%100==0 and not besieged:
			c.food=mini(c.food_cap,c.food+c.food_per_interval);c.recruits=mini(c.recruits_cap,c.recruits+c.recruits_per_interval)
			faction_gold[c.owner]=int(faction_gold.get(c.owner,0))+int(c.gold_per_interval)
		if salary_arrears(c.owner)>=300:continue
		if not c.repair.is_empty() and tick-int(c.last_siege_tick)>=150 and not besieged:
			c.repair.remaining_ticks-=1
			if c.repair.remaining_ticks<=0:c.wall_hp=mini(c.wall_max,c.wall_hp+100);c.repair={};_emit("walls_repaired",{"city":id})
		if c.production_queue.is_empty():continue
		# Salary arrears halt training until wages can be paid again.
		if salary_arrears(c.owner)>=300:continue
		var job: Dictionary=c.production_queue[0]
		job.remaining_ticks-=1
		if job.remaining_ticks>0:continue
		var spawn: String=_free_spawn(id)
		if spawn.is_empty():job.remaining_ticks=1;continue
		c.production_queue.pop_front();var p: Dictionary=PROFILES[job.unit_type]
		var a: Dictionary={"id":job.army_id,"faction":job.faction,"node":spawn,"troops":job.troops,"food":0,"food_capacity":1,"morale":100,"movement_per_tick":p.movement,"siege_power":p.siege,"attack":10,"defense":10,"unit_type":job.unit_type,"stance":"balanced","supplied":false,"order":{"type":"hold","target":""},"route":[],"edge_progress":0,"siege_state":"none"}
		_initialize_army(a);_init_design_army(a)
		a.food=mini(int(job.food_cost),_food_rate(a)*8);a.food_capacity=_food_rate(a)*12
		armies[a.id]=a;_emit("army_recruited",{"city":id,"army":a.id,"unit_type":a.unit_type});_supply_dirty=true
	var kept: Array=[]
	for op in operations:
		if cities[op.city].owner!=op.faction:continue
		if _city_under_siege(cities[op.city]):kept.append(op);continue
		op.remaining_ticks-=1
		if op.remaining_ticks>0:kept.append(op);continue
		if op.army.is_empty():cities[op.city].garrison+=int(op.amount)
		elif armies.has(op.army) and armies[op.army].troops>0 and armies[op.army].resident_city==op.city:
			armies[op.army].troops+=int(op.amount);armies[op.army].food_capacity=maxi(armies[op.army].food,_food_rate(armies[op.army])*12)
		_emit("reinforcement_completed",{"city":op.city,"army":op.army,"troops":op.amount})
	operations=kept;_reconcile_reservations()

func _logistics_blocked(a: String,b: String,faction: String) -> bool:
	for unit in armies.values():
		if unit.faction==faction or unit.troops<=0 or unit.transport_elapsed>0 or not unit.resident_city.is_empty():continue
		if unit.node in [a,b] and unit.edge_progress==0:return true
		if not unit.route.is_empty() and _edge_key(unit.node,unit.route[0])==_edge_key(a,b):return true
	return false

func _transfer_tick() -> void:
	var kept: Array=[]
	for t in transfers:
		if cities[t.destination].owner!=t.faction and t.ferry_ticks==0:t.state="Destination lost";kept.append(t);continue
		if t.leg>=t.route.size()-1:
			var c: Dictionary=cities[t.destination]
			if c.food+t.amount>c.food_cap:t.state="Warehouse full";kept.append(t);continue
			c.food+=int(t.amount);_emit("food_delivered",{"destination":t.destination,"food":int(t.amount)/SCALE});_supply_dirty=true;continue
		var a: String=t.route[t.leg];var b: String=t.route[t.leg+1]
		if t.ferry_ticks==0 and _logistics_blocked(a,b,t.faction):t.state="Blockaded";kept.append(t);continue
		var crossing: Dictionary=_crossing_by_edge.get(_edge_key(a,b),{})
		if not crossing.is_empty():
			# Boarding and progress belong to the same fleet allocator as armies.
			if t.ferry_ticks==0:t.state="Waiting for boat"
		else:
			t.departed=true;t.progress+=2;t.state="In transit"
			if t.progress>=nodes[a].edges[b]:t.leg+=1;t.progress=0
		kept.append(t)
	transfers=kept

func _handle_ferries() -> Dictionary:
	return BoatTransport.step(self) if not vessels.is_empty() else super._handle_ferries()

func vessel_position(id: String, alpha: float=0.0) -> Vector3:
	return BoatTransport.position(self,vessels[id],alpha)

func vessel_display_position(id: String, alpha: float=0.0) -> Vector3:
	# Display the last committed trip interval on its actual river polyline.
	# Passengers and their vessel share this clock instead of cutting a chord.
	return vessel_position(id,clampf(alpha,0.0,1.0)-1.0) if vessels[id].phase!="idle" else vessel_position(id)

func army_position_units(a: Dictionary) -> Vector3:
	if a.get("transport_elapsed",0)>0 and not river_navigation.nodes.is_empty():
		for boat in vessels.values():
			if boat.phase=="occupied" and boat.request=="army:"+str(a.id):return vessel_position(boat.id)
	return super.army_position_units(a)

func _target_for(a: Dictionary, candidates: Array) -> String:
	var target: String=""
	for id in candidates:
		if not armies.has(id) or armies[id].troops<=0:continue
		if a.order.type=="attack" and a.order.target==id:return id
		if target.is_empty() or armies[id].troops<armies[target].troops:target=id
	return target

func _clock_us() -> int:
	return tick*TICK_US+clampi(accumulator_us,0,TICK_US-1)

func _begin_volley(source: String, kind: String, faction: String, targets: Array, mode: String, city: String="") -> void:
	for job in pending_windups:
		if job.source==source and job.kind==kind:return
	var job: Dictionary={"id":_new_id("windup"),"source":source,"kind":kind,"faction":faction,"targets":targets.duplicate(),"mode":mode,"city":city,"started_us":tick*TICK_US,"release_us":tick*TICK_US+WINDUP_US}
	pending_windups.append(job);_emit("arrow_windup",job.duplicate(true))

func _flight_us(distance: int) -> int:
	# Half-tick release plus55/65/75/85 centiseconds lands on a simulation tick.
	return 550000+mini(3,maxi(0,distance)/30)*100000

func _release_windups(clock_us: int) -> void:
	var kept: Array=[]
	for job in pending_windups:
		if clock_us<int(job.release_us):kept.append(job);continue
		var valid: Array=[];var origin:=Vector2.ZERO;var power: int=0
		if job.mode=="guard":
			if not cities.has(job.source) or cities[job.source].owner!=job.faction or cities[job.source].garrison<=0:
				_emit("volley_cancelled",{"windup":job.id,"reason":"Defenders unavailable before release."});continue
			var c: Dictionary=cities[job.source];var available: Array=_guard_targets(c)
			for target in job.targets:
				if target in available:valid.append(target)
			origin=_point({"node":c.node,"edge_progress":0,"route":[]})
			power=Tactical.guard_power(c) if tactical_rts else mini(20,int(c.garrison)/30)*3
			if c.food==0 and not tactical_rts:power=power/2
		else:
			if not armies.has(job.source):continue
			var a: Dictionary=armies[job.source]
			if a.troops<=0 or a.routed or a.transport_elapsed>0:continue
			if tactical_rts and job.mode=="field" and a.order.type in ["move","retreat"] and not a.route.is_empty():
				_emit("volley_cancelled",{"windup":job.id,"reason":"Movement interrupted the draw."});continue
			if job.mode=="resident":
				if a.resident_city!=job.city or not cities.has(job.city) or cities[job.city].owner!=job.faction:continue
				var available: Array=_guard_targets(cities[job.city])
				for target in job.targets:
					if target in available:valid.append(target)
			elif a.resident_city.is_empty():
				for target in job.targets:
					if armies.has(target) and _in_range(a,armies[target]):valid.append(target)
			origin=_point(a)
		if valid.is_empty():_emit("volley_cancelled",{"windup":job.id,"reason":"Target unavailable before release."});continue
		for index in range(valid.size()):
			var target: String=valid[index];var amount: int=0
			if job.mode in ["guard","resident"]:origin=_guard_origin(cities[job.city],armies[target])
			if job.mode=="guard":amount=power if tactical_rts else power/valid.size()+(1 if index<power%valid.size() else 0)
			else:
				var adjusted: Dictionary=armies[job.source].duplicate(true)
				adjusted.attack=maxi(1,int(adjusted.attack)*buff_percent(job.source,"attack")/100)
				amount=TacticalCombat.damage(self,armies[job.source],armies[target]) if tactical_rts else Combat.casualties(adjusted,armies[target],str(nodes[armies[target].node].get("terrain","plain")))*(1 if traditional_rts else VOLLEY_MULTIPLIER)
			if amount>0:_queue_volley(job.source,job.kind,job.faction,target,amount,origin,int(job.release_us),_flight_us(int(origin.distance_to(_point(armies[target])))),int(job.started_us))
	pending_windups=kept

func _queue_volley(source: String, kind: String, faction: String, target: String, damage: int, origin: Vector2, release_us: int=-1, flight_us: int=800000, started_us: int=-1) -> void:
	# Immediate packets are retained for controlled impact fixtures; gameplay uses _begin_volley.
	if release_us<0:release_us=tick*TICK_US
	if started_us<0:started_us=release_us
	var point: Vector2=_point(armies[target])
	var shot: Dictionary={"id":_new_id("volley"),"source":source,"kind":kind,"faction":faction,"target":target,"damage":damage,"impact_tick":(release_us+flight_us+TICK_US-1)/TICK_US,"release_tick":release_us/TICK_US,"release_time_us":release_us,"windup_start_us":started_us,"origin":[int(origin.x),int(origin.y)],"goal":[int(point.x),int(point.y)]}
	pending_volleys.append(shot)
	_emit("arrow_volley",shot.duplicate(true))

func _resolve_battles() -> void:
	if tactical_rts:TacticalCombat.resolve_battles(self);return
	var damage: Dictionary={}
	for id in _sorted_ids(_contacts):
		if not armies.has(id) or armies[id].troops<=0:continue
		var a: Dictionary=armies[id];var target: String=_target_for(a,_contacts[id])
		if target.is_empty():continue
		var b: Dictionary=armies[target];var adjusted: Dictionary=a.duplicate(true)
		adjusted.attack=maxi(1,int(a.attack)*buff_percent(id,"attack")/100)
		var dealt: int=Combat.casualties(adjusted,b,str(nodes[b.node].get("terrain","plain")))
		if a.unit_type=="archers":
			if tick-int(a.last_volley_tick)<30:continue
			a.last_volley_tick=tick;_begin_volley(id,"army",a.faction,[target],"field")
		else:
			damage[target]=int(damage.get(target,0))+dealt
			_emit("field_attack",{"army":id,"target":target,"damage":dealt,"ranged":false})
	_apply_damage(damage,"battle")

func _impact_tick() -> void:
	var kept: Array=[];var damage: Dictionary={}
	for shot in pending_volleys:
		if tick<int(shot.impact_tick):kept.append(shot);continue
		if armies.has(shot.target) and armies[shot.target].troops>0 and armies[shot.target].faction!=shot.faction and armies[shot.target].transport_elapsed==0 and armies[shot.target].resident_city.is_empty():
			damage[shot.target]=int(damage.get(shot.target,0))+int(shot.damage)
			_emit("volley_impact",{"army":shot.source,"target":shot.target,"damage":shot.damage,"volley":shot.id})
		else:_emit("volley_expired",{"volley":shot.id,"reason":"Target unavailable; no retargeting."})
	pending_volleys=kept;_apply_damage(damage,"battle")

func _guard_targets(c: Dictionary) -> Array:
	if tactical_rts:return TacticalCombat.guard_targets(self,c)
	var result: Array=[]
	for id in _sorted_ids(armies):
		var a: Dictionary=armies[id]
		if a.faction==c.owner or a.troops<=0 or a.transport_elapsed>0 or not a.resident_city.is_empty():continue
		for gate in gate_nodes(c.id):
			var origin: Dictionary={"node":gate,"edge_progress":0,"route":[]}
			if _point(origin).distance_to(_point(a))<=120 and has_line_of_sight(origin,a):result.append(id);break
	return result

func _city_volleys() -> void:
	if tactical_rts:TacticalCombat.city_volleys(self);return
	for id in _sorted_ids(cities):
		var c: Dictionary=cities[id];var targets: Array=_guard_targets(c)
		if targets.is_empty():continue
		if tick%30==0 and c.garrison>0:
			_begin_volley(id,"city",c.owner,targets,"guard",id)
		for resident in resident_ids(id):
			var a: Dictionary=armies[resident]
			if a.routed or a.unit_type!="archers" or tick-int(a.last_volley_tick)<30:continue
			var target: String=targets[0];var adjusted: Dictionary=a.duplicate(true)
			adjusted.attack=maxi(1,int(a.attack)*buff_percent(resident,"attack")/100)
			a.last_volley_tick=tick
			_begin_volley(resident,"army",a.faction,[target],"resident",id)

func _city_under_siege(c: Dictionary) -> bool:
	if tactical_rts:return TacticalCombat.besieged(self,c)
	for a in armies.values():
		if a.troops>0 and a.faction!=c.owner and a.order.type=="siege" and a.order.target==c.id and a.node==_target_node(a.order) and a.edge_progress==0 and a.transport_elapsed==0 and a.resident_city.is_empty():return true
	return false

func _resolve_sieges() -> void:
	if tactical_rts:TacticalCombat.resolve_sieges(self);return
	var retaliation: Dictionary={}
	for id in _sorted_ids(cities):
		var c: Dictionary=cities[id];var attackers: Array=[];var factions: Dictionary={};var defenders: bool=false
		for key in _sorted_ids(armies):
			var a: Dictionary=armies[key]
			if a.troops<=0 or a.transport_elapsed>0 or not a.resident_city.is_empty() or a.node not in gate_nodes(id) or a.edge_progress>0:continue
			if a.faction==c.owner:defenders=true
			elif not a.routed and a.order.type=="siege" and a.order.target==id and a.node==_target_node(a.order):attackers.append(key);factions[a.faction]=true
		if attackers.is_empty():c.capture_ticks=0;c.capture_faction="";continue
		c.last_siege_tick=tick
		if defenders or factions.size()!=1:
			c.capture_ticks=0;c.capture_faction=""
			for key in attackers:armies[key].siege_state="contested"
			continue
		var outgoing: int=0
		for key in attackers:
			outgoing+=Combat.siege_damage(armies[key]);armies[key].siege_state="besieging" if c.wall_hp>0 else "breached"
		if c.wall_hp>0:
			c.wall_hp=maxi(0,c.wall_hp-outgoing)
			if c.has("city_morale"):c.city_morale=maxi(0,int(c.city_morale)-maxi(1,mini(3,attackers.size())))
		else:
			# Storming the breach: once the wall is down, infantry and cavalry fight the
			# gate garrison directly at half field power instead of waiting for the siege
			# engine to grind it alone. Measured 2026-11-03: a committed 2,750-troop
			# assault broke the wall in 85 s but could never clear the 1,000 guards.
			var storm: int=0
			var garrison_proxy: Dictionary={"troops":maxi(1,int(c.garrison)),"defense":10,"unit_type":"infantry","stance":"balanced","morale":100,"food":1,"attack":10}
			for key in attackers:
				var a: Dictionary=armies[key]
				if a.unit_type=="siege":continue
				var adjusted: Dictionary=a.duplicate(true)
				adjusted.attack=maxi(1,int(a.attack)*buff_percent(key,"attack")/100)
				storm+=Combat.casualties(adjusted,garrison_proxy,"plain")/2
			outgoing+=storm
			if c.has("city_hp"):c.city_hp=maxi(0,int(c.city_hp)-outgoing)
			if c.has("city_morale"):c.city_morale=maxi(0,int(c.city_morale)-2)
			var residents: Array=resident_ids(id);var strength: int=int(c.garrison)
			for key in residents:strength+=int(armies[key].troops)
			if strength>0:
				var guard_damage: int=outgoing*int(c.garrison)/strength;c.garrison=maxi(0,int(c.garrison)-guard_damage)
				var damage: Dictionary={};var spent: int=guard_damage
				for index in range(residents.size()):
					var key: String=residents[index]
					var share: int=outgoing*int(armies[key].troops)/strength
					if index==residents.size()-1:share=outgoing-spent
					damage[key]=share;spent+=share
					if armies[key].unit_type in ["infantry","cavalry","archers"]:
						var a: Dictionary=armies[key];var adjusted: Dictionary=a.duplicate(true)
						adjusted.attack=maxi(1,int(a.attack)*buff_percent(key,"attack")/100)
						var target: String=attackers[0]
						# Resident archers already use their volley budget; no second attack.
						if a.unit_type!="archers":retaliation[target]=int(retaliation.get(target,0))+Combat.casualties(adjusted,armies[target],"plain")
				_apply_damage(damage,"garrison")
		var alive: Array=[]
		for key in attackers:
			if armies[key].troops>0 and armies[key].morale>20 and armies[key].unit_type in ["infantry","cavalry"]:alive.append(key)
		var broken: bool=c.kind=="city" and (c.has("city_hp") or c.has("city_morale")) and (int(c.get("city_hp",1))<=0 or int(c.get("city_morale",100))<=0)
		if alive.is_empty():c.capture_ticks=0;c.capture_faction="";continue
		if not broken and (c.wall_hp>0 or c.garrison>0 or not resident_ids(id).is_empty()):c.capture_ticks=0;c.capture_faction="";continue
		var faction: String=armies[alive[0]].faction
		if c.capture_faction!=faction:c.capture_ticks=0;c.capture_faction=faction
		c.capture_ticks+=10
		if not broken and c.capture_ticks<(50 if c.kind=="village" else 100):continue
		# Retaliation is applied before a living melee unit can complete capture.
		_apply_damage(retaliation,"garrison");retaliation.clear()
		var survivor: bool=false
		for key in alive:
			if armies[key].troops>0 and armies[key].morale>20:survivor=true
		if not survivor:c.capture_ticks=0;continue
		_capture_city(c,attackers,faction)
	_apply_damage(retaliation,"garrison")

func _capture_city(c: Dictionary, attackers: Array, faction: String) -> void:
	var id: String=c.id
	var previous: String=c.owner
	# A morale/HP capture can happen while defenders and incoming formations are
	# still alive. Evacuate residents and cancel incoming reservations atomically;
	# otherwise the next save contains a formation resident in an enemy city.
	for army_id in _sorted_ids(armies):
		var defender: Dictionary=armies[army_id]
		if defender.faction==faction:continue
		if defender.garrison_target==id:defender.garrison_target="";defender.entry_ticks=0
		if defender.resident_city!=id:continue
		defender.resident_city="";defender.sortie_pending=false;defender.garrison_target="";defender.entry_ticks=0
		_hold(defender);defender.engaged_ids=[];defender.morale=mini(20,int(defender.morale));defender.routed=true;defender.rout_until=tick+100
		_emit("formation_sortied",{"army":army_id,"city":id});_emit("army_routed",{"army":army_id,"home":""})
	for job in c.production_queue:_emit("recruitment_cancelled",{"city":id,"army":job.army_id,"reason":"City captured."})
	c.production_queue=[];c.owner=faction;c.food=int(c.food)/2;c.recruits=int(c.recruits)/4;c.repair={};c.capture_ticks=0;c.capture_faction=""
	# A captured city is damaged but not instantly re-capturable.
	if c.has("city_hp_max"):c.city_hp=maxi(1,int(c.city_hp_max)/4);c.city_morale=50
	var windups: Array=[]
	for job in pending_windups:
		if job.city!=id:windups.append(job)
	pending_windups=windups
	c.starved_ticks=0;c.unpaid_ticks=0
	var kept: Array=[]
	for op in operations:
		if op.city!=id:kept.append(op)
	operations=kept;_supply_dirty=true;_reconcile_reservations()
	_emit("city_captured",{"city":id,"old_owner":previous,"new_owner":faction})
	for key in attackers:
		if armies[key].troops>0:_hold(armies[key]);armies[key].siege_state="captured"

func _update_routs() -> void:
	var residents: Dictionary={}
	for id in armies:
		var army: Dictionary=armies[id]
		if not army.resident_city.is_empty():residents[id]=army.morale;army.morale=maxi(21,int(army.morale))
		elif tactical_rts and army.troops>0 and (army.routed or army.morale<=20):
			# Rout replaces the entire tactical intent, including old-save queues.
			army.waypoints.clear();army.combat_target=""
			if not army.routed:army.stuck_ticks=0
			_cancel_earlier_field_orders(id)
			_cancel_field_windup(id)
	super._update_routs()
	for id in residents:armies[id].morale=residents[id]
	# Safe cities, not exposed/captured villages, are the recovery destination.
	for id in _sorted_ids(armies):
		var a: Dictionary=armies[id]
		if a.troops<=0 or not a.routed or a.transport_elapsed>0 or not a.resident_city.is_empty():continue
		var current_home: bool=false
		for c in cities.values():
			if c.kind=="city" and c.owner==a.faction and c.food>0 and not _city_under_siege(c) and a.order.type=="retreat" and a.order.target==c.node:current_home=true;break
		if current_home and not a.route.is_empty():continue
		if tick%40!=0:continue
		var choice: String="";var best: int=2147483647;var blocked: Dictionary=_blocked_nodes(a.faction);blocked.erase(a.node)
		for kind in ["city","village"]:
			for city_id in _sorted_ids(cities):
				var c: Dictionary=cities[city_id]
				if c.kind!=kind or c.owner!=a.faction or c.food<=0 or _city_under_siege(c):continue
				var path: Dictionary=find_path(a.node,c.node,blocked)
				if path.ok and path.distance<best:choice=c.node;best=path.distance
			if not choice.is_empty():break
		if not choice.is_empty() and _set_safe_retreat(a,choice,blocked):_emit("rout_refuge_changed",{"army":id,"home":choice})
	# Resting at a friendly, unbesieged settlement restores morale faster than field
	# supply and lets a routed formation rally below the field-supply threshold.
	# Without this a formation that starved during a siege never leaves rout, so the
	# campaign can never resolve (measured 2026-11-03: ownership frozen after tick 2000).
	for id in _sorted_ids(armies):
		var a: Dictionary=armies[id]
		if a.troops<=0 or not a.resident_city.is_empty() or a.transport_elapsed>0:continue
		if not a.engaged_ids.is_empty():continue
		var resting: bool=false
		for c in cities.values():
			if c.owner==a.faction and c.node==a.node and not _city_under_siege(c):resting=true;break
		if not resting:continue
		if tick%100==0:a.morale=mini(100,int(a.morale)+6)
		if a.routed and int(a.morale)>=30:a.routed=false;_emit("army_rallied",{"army":id})

func _decide_design_ai(faction: String) -> void:

	var holdings: int=0
	for c in cities.values():
		if c.owner==faction and c.victory_point:holdings+=1
	for id in _sorted_ids(armies):
		var a: Dictionary=armies[id]
		if a.faction!=faction or a.troops<=0 or a.routed or a.transport_elapsed>0:continue
		if not a.resident_city.is_empty():
			var c: Dictionary=cities[a.resident_city]
			if _city_under_siege(c):continue
			# Use the existing paid disband/recruit APIs to replace a depleted small
			# formation with territory-funded larger recruitment. Commander cap and
			# prices remain the same; no troops are granted or upgraded in place.
			if holdings>=4 and a.original_troops<1000 and a.troops*100<a.original_troops*50 and faction_gold[faction]>=1500*SCALE and c.food>=3000*SCALE and c.recruits>=1000:
				if request_disband(faction,id).is_empty():continue
			if a.troops*100<a.original_troops*85:
				var reinforced: String=request_reinforce(faction,c.id,id)
				if reinforced.is_empty() or a.troops*100<a.original_troops*35:continue
			request_sortie(faction,id);continue
		# Keep a live assault at the hostile gate committed until capture or rout.
		if a.order.type=="siege" and cities.has(a.order.target) and cities[a.order.target].owner!=faction and a.node==_target_node(a.order) and a.edge_progress==0:continue
		if not a.garrison_target.is_empty() or not a.engaged_ids.is_empty() or a.troops*100>=a.original_troops*45:continue
		var home: String="";var nearest: int=2147483647
		for city_id in _sorted_ids(cities):
			var c: Dictionary=cities[city_id]
			if c.owner!=faction or c.kind!="city" or c.food<750*SCALE or c.recruits<100 or _city_under_siege(c) or _ai_city_slots(city_id)>=2:continue
			var path: Dictionary=route_to_settlement(a.node,c.node)
			if path.ok and path.distance<nearest:home=city_id;nearest=path.distance
		if not home.is_empty():request_garrison(faction,id,home)
	# Buy the field army before optional repairs and guard replenishment. Previously
	# every captured city spent the recruitment budget before the planner ran.
	CampaignAI.recruit(self,faction)
	var field_troops: int=0;var formation_count: int=0
	for a in armies.values():
		if a.faction==faction and a.troops>0:field_troops+=int(a.troops);formation_count+=1
	for c in cities.values():
		for job in c.production_queue:
			if job.faction==faction:formation_count+=1
	if formation_count>=6 and field_troops>=(400 if tactical_rts else 2400):
		for id in _sorted_ids(cities):
			var c: Dictionary=cities[id]
			if c.owner!=faction or c.kind!="city" or _city_under_siege(c):continue
			if c.wall_hp<c.wall_max:request_repair(faction,id)
			if c.garrison<(Tactical.CITY_GARRISON if tactical_rts else 500) and c.recruits>=100 and faction_gold[faction]>500*SCALE:request_reinforce(faction,id)
	# Reserve incoming/resident formations before the planner can queue field orders.
	var foods: Dictionary={}
	for id in armies:foods[id]=armies[id].food;armies[id].food=rations_seconds(id)
	CampaignAI.decide(self,faction)
	for id in foods:armies[id].food=foods[id]

func _update_victory() -> void:
	# A faction that holds no settlement has no base: its remaining field
	# formations disband after 30 s, so "all cities + no enemy troops" is reachable.
	for faction in Officers.FACTIONS:
		var owns: bool=false
		for c in cities.values():
			if c.owner==faction:owns=true;break
		if owns:
			for a in armies.values():
				if a.faction==faction:a.disband_ticks=0
			continue
		for id in _sorted_ids(armies):
			var a: Dictionary=armies[id]
			if a.faction!=faction or a.troops<=0:continue
			a.disband_ticks=int(a.get("disband_ticks",0))+1
			if a.disband_ticks>=300:
				a.troops=0;_defeat(a,"no city");_emit("formation_disbanded",{"army":id,"reason":"No settlement held."})
	if continued:return
	for faction in Officers.FACTIONS:
		var count: int=0;var all_owned: bool=true
		for c in cities.values():
			if c.victory_point:count+=1;all_owned=all_owned and c.owner==faction
		if count!=8 or not all_owned or enemy_troops(faction)>0:continue
		var queued: bool=false
		for c in cities.values():
			for job in c.production_queue:
				if job.faction!=faction:queued=true
		if queued:continue
		winner=faction;match_state="finished";paused=true;outcome={"kind":"victory","faction":faction}
		_emit("campaign_won",{"faction":faction});return
	var player: String=""
	for faction in Officers.FACTIONS:
		if faction not in ai_factions:player=faction
	if ai_factions.size()==2 and not player.is_empty():
		var holdings: int=0;var jobs: int=0
		for c in cities.values():
			if c.owner==player and c.victory_point:holdings+=1
			for job in c.production_queue:
				if job.faction==player:jobs+=1
		if holdings==0 and jobs==0 and faction_troops(player)==0:
			winner="";match_state="finished";paused=true;outcome={"kind":"defeat","faction":player};_emit("campaign_lost",{"faction":player})

func step(count: int=1) -> void:
	for _index in range(maxi(0,count)):
		if match_state=="finished":break
		# A half-tick release uses the previous committed state, independent of frame chunking.
		_release_windups((tick+1)*TICK_US)
		tick+=1
		if (tick-1)%40==0:
			for faction in ai_factions:_decide_design_ai(faction)
		if tick%200==0:
			for faction in ai_factions:_ai_food_transfers(faction)
		_apply_commands();_move_armies();_residency_tick();_update_supply(tick%100==0);_impact_tick()
		if tick%10==0:_resolve_battles();_resolve_sieges();_city_volleys()
		_update_routs();_update_production();_transfer_tick();_update_victory();_update_supply(false);_refresh_contacts()

func advance_real_time_us(elapsed_us: int,max_ticks: int=0) -> int:
	speed=1
	var processed: int=super.advance_real_time_us(elapsed_us,max_ticks)
	settle_subtick_events()
	return processed

func set_speed(value: int) -> bool:
	speed=1
	return value==1

func settle_subtick_events() -> void:
	if not paused and match_state!="finished":_release_windups(_clock_us())

func continue_campaign() -> void:
	super.continue_campaign();outcome.clear()

func snapshot() -> Dictionary:
	var data: Dictionary=super.snapshot();data.format_version=BATTLE_FORMAT if tactical_rts else 13 if traditional_rts else 12
	data.battle_state={"revision":Tactical.REVISION if tactical_rts else 6 if traditional_rts else 5,"vessels":vessels.duplicate(true),"faction_gold":faction_gold.duplicate(true),"operations":operations.duplicate(true),"transfers":transfers.duplicate(true),"pending_volleys":pending_volleys.duplicate(true),"pending_windups":pending_windups.duplicate(true),"serial":operation_serial,"outcome":outcome.duplicate(true)}
	if traditional_rts:data.battle_state.ruleset=Tactical.ID if tactical_rts else Traditional.ID
	# Schema 14 stores immutable navigation/map data by exact installed identity.
	# Older full schema-14 files remain loadable and are compacted on the next save.
	if tactical_rts:
		data.erase("nodes")
		data.campaign=data.campaign.duplicate()
		data.campaign.world=_world_reference(world_metadata)
	return data

func _world_reference(world: Dictionary) -> Dictionary:
	return {"id":world.get("id",""),"revision":world.get("revision",0),"sha256":world.get("sha256","")}

func formation_limit() -> int:return Traditional.FORMATION_LIMIT if traditional_rts else 6
func visible_members() -> int:return Traditional.MEMBERS if traditional_rts else 8
func recruitment_ticks(kind: String) -> int:return Traditional.training(kind) if traditional_rts else int(PROFILES[kind].training)

func _validate_design(data: Dictionary, trusted_graph: bool=false) -> String:
	if not data.get("battle_state") is Dictionary or not data.get("armies") is Dictionary or not data.get("cities") is Dictionary or not data.get("nodes") is Dictionary:return "Battle save dictionaries are missing."
	if not _integer_at_least(data.get("tick"),0) or not data.get("campaign") is Dictionary or not data.campaign.get("world") is Dictionary or not data.get("ai_factions") is Array:return "Battle clock or world metadata is missing."
	if not trusted_graph:
		var graph_error: String=_validate_graph(data.nodes)
		if not graph_error.is_empty():return graph_error
	for id in data.cities:
		var c=data.cities[id]
		if not c is Dictionary or c.get("owner") not in Officers.FACTIONS or c.get("kind") not in ["city","village"] or not c.get("production_queue") is Array or not c.get("node") is String:return "Battle city identity is invalid."
		for key in ["garrison","food","wall_hp","food_per_interval"]:
			if not _integer_at_least(c.get(key),0):return "Battle city numeric state is invalid."
		for job in c.production_queue:
			if not job is Dictionary or not _integer_at_least(job.get("troops"),1) or not job.get("army_id") is String or not job.get("faction") is String:return "Battle training record is invalid."
	for id in data.armies:
		var a=data.armies[id]
		if not a is Dictionary or a.get("faction") not in Officers.FACTIONS or not _integer_at_least(a.get("troops"),0) or not _integer_at_least(a.get("transport_elapsed"),0) or not a.get("route") is Array or not a.get("node") is String or not a.get("order") is Dictionary:return "Battle army identity is invalid."
	var state: Dictionary=data.battle_state
	var tactical: bool=data.get("format_version")==14
	var traditional: bool=data.get("format_version") in [13,14]
	if traditional and state.get("ruleset")!=(Tactical.ID if tactical else Traditional.ID):return "Unknown RTS ruleset."
	if state.get("revision")!=(Tactical.REVISION if tactical else 6 if traditional else 5 if data.get("format_version")==12 else 4) or data.get("speed")!=1 or not state.get("faction_gold") is Dictionary or not state.get("operations") is Array or not state.get("transfers") is Array or not state.get("pending_volleys") is Array or not state.get("pending_windups") is Array or not state.get("outcome") is Dictionary:return "Battle save state or fixed pace is invalid."
	if not _integer_at_least(state.get("serial"),0):return "Battle serial is invalid."
	for f in Officers.FACTIONS:
		if not _integer_at_least(state.faction_gold.get(f),0):return "Battle treasury is invalid."
	for id in data.armies:
		var a=data.armies[id]
		if not a is Dictionary or not a.get("resident_city") is String or not a.get("garrison_target") is String or not a.get("sortie_pending") is bool:return "Resident formation data is invalid."
		if traditional:
			var profile: Dictionary=Traditional.PROFILES.get(a.get("unit_type",""),{})
			if profile.is_empty() or a.get("traditional_unit")!=true or a.get("attack")!=profile.attack or a.get("defense")!=profile.defense or a.get("movement_per_tick")!=profile.movement or a.get("siege_power")!=profile.siege:return "Squad attributes differ from the RTS ruleset."
		elif a.get("traditional_unit",false):return "Traditional squads cannot be relabeled as legacy saves."
		for key in ["original_troops","entry_ticks","starved_ticks","unpaid_ticks"]:
			if not _integer_at_least(a.get(key),0):return "Formation economy timer is invalid."
		if not a.get("last_volley_tick") is int or int(a.last_volley_tick)>int(data.tick) or int(a.last_volley_tick)<-30:return "Volley release clock is invalid."
		if a.original_troops<a.troops or a.original_troops>3000 or a.entry_ticks>30:return "Formation strength or entry timer is invalid."
		for key in ["resident_city","garrison_target"]:
			if not a[key].is_empty() and (not data.cities.has(a[key]) or data.cities[a[key]].owner!=a.faction or data.cities[a[key]].kind!="city"):return "Resident or incoming formation belongs to another city."
		if not a.resident_city.is_empty() and (not a.garrison_target.is_empty() or a.node!=data.cities[a.resident_city].node or not a.route.is_empty() or a.transport_elapsed>0):return "Resident formation also occupies the field."
	var unique: Dictionary={};var recipients: Dictionary={}
	for op in state.operations:
		if not op is Dictionary or not op.get("id") is String or unique.has(op.id) or op.get("type")!="reinforce" or not data.cities.has(op.get("city","")) or not op.get("army") is String:return "Reinforcement operation is invalid."
		unique[op.id]=true
		var recipient: String=op.city+"|"+op.army
		if recipients.has(recipient):return "Reinforcement recipient is reserved more than once."
		recipients[recipient]=true
		if not _serial_valid(op.id,"reinforce",state.serial):return "Reinforcement serial would be reused."
		if not _integer_at_least(op.get("amount"),1) or op.amount>100 or not _integer_at_least(op.get("remaining_ticks"),1) or op.remaining_ticks>50 or op.get("faction")!=data.cities[op.city].owner:return "Reinforcement amount, clock or owner is invalid."
		if not op.army.is_empty() and (not data.armies.has(op.army) or data.armies[op.army].resident_city!=op.city or data.armies[op.army].troops+op.amount>data.armies[op.army].original_troops):return "Reinforcement recipient is invalid."
	for id in data.cities:
		var c=data.cities[id]
		if not c is Dictionary or not c.get("repair") is Dictionary:return "City repair state is invalid."
		for key in ["wall_max","people_capacity","food_cap","gold_per_interval","recruits","recruits_cap","recruits_per_interval","capture_ticks","last_siege_tick","starved_ticks","unpaid_ticks"]:
			if not _integer_at_least(c.get(key),0):return "City economy field is invalid: "+key
		# Older optional health state stays optional as a complete group. Current
		# squads require all three fields before any production code can use them.
		if traditional or c.has("city_hp") or c.has("city_hp_max") or c.has("city_morale"):
			for key in ["city_hp","city_hp_max","city_morale"]:
				if not _integer_at_least(c.get(key),0):return "City health field is invalid: "+key
			var health_max: int=(Tactical.CITY_HP if tactical else 400 if traditional else 1000) if c.kind=="city" else 0
			if c.city_hp_max!=health_max or c.city_hp>health_max or c.city_morale>100:return "City health cap is invalid."
		if c.wall_max!=((Tactical.WALL_HP if tactical else 300 if traditional else 1200) if c.kind=="city" else 0) or c.people_capacity!=((2000 if traditional else 10000) if c.kind=="city" else 100) or c.wall_hp>c.wall_max or c.food>c.food_cap or c.recruits>c.recruits_cap or c.capture_ticks>(Tactical.CAPTURE_TICKS if tactical else 100):return "City economy cap is invalid."
		var village: bool=c.kind=="village";var extra: bool=id in ["C5","C6"]
		if c.food_cap!=(2000 if village else 6000)*SCALE or c.recruits_cap!=(0 if village else 2250 if extra else 1500) or c.food_per_interval!=(30 if village else 90 if extra else 60)*SCALE or c.gold_per_interval!=(5000 if village else 22500 if extra else 15000) or c.recruits_per_interval!=(0 if village else 30 if extra else 20):return "City income or warehouse profile differs from design."
		if not c.get("capture_faction") is String or c.last_siege_tick>data.tick:return "City capture or siege clock is invalid."
		if _capacity_for(id,data.armies,data.cities,state.operations)>c.people_capacity:return "City capacity exceeds its population limit."
		var slots: int=0
		for a in data.armies.values():
			if a.troops>0 and (a.resident_city==id or a.garrison_target==id):slots+=1
		if slots>2:return "City resident formation limit exceeded."
		if not c.repair.is_empty() and (c.repair.get("faction")!=c.owner or not _integer_at_least(c.repair.get("remaining_ticks"),1) or c.repair.remaining_ticks>250):return "Repair owner or timer is invalid."
		for job in c.production_queue:
			if not job is Dictionary or not _integer_at_least(job.get("troops"),1) or not _integer_at_least(job.get("food_cost"),1) or not _integer_at_least(job.get("gold_cost"),1) or job.food_cost!=job.troops*int(PROFILES.get(job.get("unit_type"),{}).get("cost",0))*SCALE or job.gold_cost!=job.troops*int(GOLD_COST.get(job.get("unit_type"),0))*SCALE/500:return "Recruitment resource reservation is invalid."
	if state.transfers.size()>24 or state.pending_volleys.size()>128 or state.pending_windups.size()>32:return "Battle queue budget exceeded."
	var ferry_occupants: Dictionary={}
	var crossing_lookup: Dictionary={}
	for crossing in data.campaign.world.get("crossings",[]):
		if not crossing is Dictionary or not crossing.get("nodes") is Array or crossing.nodes.size()!=2 or not crossing.get("id") is String or not _integer_at_least(crossing.get("travel_ticks"),1) or not _integer_at_least(crossing.get("capacity_formations"),1):return "Logistics crossing metadata is invalid."
		crossing_lookup[_edge_key(crossing.nodes[0],crossing.nodes[1])]=crossing
	for a in data.armies.values():
		if a.transport_elapsed>0:
			if not a.get("transport_id") is String:return "Passenger ferry identity is invalid."
			ferry_occupants[a.transport_id]=int(ferry_occupants.get(a.transport_id,0))+1
	for t in state.transfers:
		if not t is Dictionary or not t.get("id") is String or unique.has(t.id) or not data.cities.has(t.get("source","")) or not data.cities.has(t.get("destination","")) or t.get("faction") not in Officers.FACTIONS or not t.get("route") is Array or t.route.size()<2:return "Logistics record is invalid."
		unique[t.id]=true
		if not _serial_valid(t.id,"food",state.serial):return "Transfer serial would be reused."
		for key in ["amount","leg","progress","ferry_ticks"]:
			if not _integer_at_least(t.get(key),0):return "Logistics progress is invalid."
		if t.amount<=0 or t.amount>6000*SCALE or t.leg>=t.route.size() or not t.get("departed") is bool or not t.get("state") is String or not t.get("ferry_id") is String:return "Logistics amount or state is invalid."
		if t.route[0]!=data.cities[t.source].node or t.route[-1]!=data.cities[t.destination].node:return "Logistics endpoints are invalid."
		for index in range(t.route.size()-1):
			if not data.nodes.has(t.route[index]) or not data.nodes[t.route[index]].edges.has(t.route[index+1]):return "Logistics route is disconnected."
		if t.leg<t.route.size()-1 and t.progress>=int(data.nodes[t.route[t.leg]].edges[t.route[t.leg+1]]):return "Logistics progress exceeds its edge."
		if t.ferry_ticks>0:
			if t.leg>=t.route.size()-1:return "Arrived transfer is still on a ferry."
			var crossing: Dictionary=crossing_lookup.get(_edge_key(t.route[t.leg],t.route[t.leg+1]),{})
			if crossing.is_empty() or crossing.id!=t.ferry_id or t.ferry_ticks>=crossing.travel_ticks or t.progress!=0 or not t.departed or t.state!="Ferry transit":return "Logistics ferry identity or progress is invalid."
			ferry_occupants[t.ferry_id]=int(ferry_occupants.get(t.ferry_id,0))+1
		elif not t.ferry_id.is_empty():return "Inactive logistics ferry identity is invalid."
	for crossing in crossing_lookup.values():
		if int(ferry_occupants.get(crossing.id,0))>crossing.capacity_formations:return "Shared army and logistics ferry capacity exceeded."
	var emitters: Dictionary={}
	for job in state.pending_windups:
		if not job is Dictionary or not job.get("id") is String or not job.get("source") is String or unique.has(job.id) or job.get("kind") not in ["army","city"] or job.get("mode") not in ["field","guard","resident"] or job.get("faction") not in Officers.FACTIONS or not job.get("targets") is Array or job.targets.is_empty() or not job.get("city") is String:return "Windup identity is invalid."
		unique[job.id]=true
		if not _serial_valid(job.id,"windup",state.serial) or not _integer_at_least(job.get("started_us"),0) or not _integer_at_least(job.get("release_us"),0) or job.started_us%TICK_US!=0 or job.release_us!=job.started_us+WINDUP_US or job.started_us>data.tick*TICK_US or job.release_us<=data.tick*TICK_US:return "Windup clock is invalid."
		if job.kind=="army" and (not data.armies.has(job.get("source","")) or data.armies[job.source].faction!=job.faction) or job.kind=="city" and (not data.cities.has(job.get("source","")) or data.cities[job.source].owner!=job.faction):return "Windup source is invalid."
		if (job.mode=="guard")!=(job.kind=="city") or (job.mode in ["guard","resident"] and (not data.cities.has(job.city) or data.cities[job.city].owner!=job.faction)):return "Windup role or city is invalid."
		var emitter: String=job.kind+"|"+job.source
		if emitters.has(emitter):return "Emitter has more than one pending windup."
		emitters[emitter]=true
		var targets: Dictionary={}
		for target in job.targets:
			if not target is String or not data.armies.has(target) or targets.has(target) or data.armies[target].faction==job.faction:return "Windup target is invalid."
			targets[target]=true
	for shot in state.pending_volleys:
		if not shot is Dictionary or not shot.get("id") is String or unique.has(shot.id) or shot.get("kind") not in ["army","city"] or shot.get("faction") not in Officers.FACTIONS or not data.armies.has(shot.get("target","")):return "Pending volley identity is invalid."
		unique[shot.id]=true
		if not _serial_valid(shot.id,"volley",state.serial):return "Volley serial would be reused."
		if not _integer_at_least(shot.get("damage"),1) or not _integer_at_least(shot.get("release_tick"),0) or not _integer_at_least(shot.get("impact_tick"),0) or not _integer_at_least(shot.get("release_time_us"),0) or not _integer_at_least(shot.get("windup_start_us"),0):return "Pending volley damage or clock is invalid."
		var flight: int=int(shot.impact_tick)*TICK_US-int(shot.release_time_us)
		if shot.release_tick>data.tick or shot.release_time_us/TICK_US!=shot.release_tick or shot.impact_tick<=data.tick or flight<550000 or flight>900000 or int(shot.release_time_us)-int(shot.windup_start_us) not in [0,WINDUP_US]:return "Pending volley timeline is invalid."
		if shot.kind=="army" and not data.armies.has(shot.get("source","")) or shot.kind=="city" and not data.cities.has(shot.get("source","")):return "Pending volley source is invalid."
		if shot.kind=="army" and data.armies[shot.source].faction!=shot.faction:return "Pending volley source faction is invalid."
		for key in ["origin","goal"]:
			if not shot.get(key) is Array or shot[key].size()!=2:return "Pending volley coordinate is invalid."
			for n in shot[key]:
				if not n is int:return "Pending volley coordinates require integers."
	if tactical:
		if data.cities.size()!=data.campaign.world.get("settlements",[]).size():return "Save settlement roster is incomplete."
		return TacticalOrders.validate(self,data)
	return ""

func _validate_queued_command(command, data: Dictionary) -> String:
	var error: String=super._validate_queued_command(command,data)
	if not error.is_empty():return error
	if command.has("append") and not command.append is bool:return "Queued-order flag is invalid."
	if command.has("gate_node"):
		return _validate_saved_order({"type":command.type,"target":command.target,"gate_node":command.gate_node},data.nodes,data.armies,data.cities)
	return ""

func _serial_valid(id: String, prefix: String, serial: int) -> bool:
	if not id.begins_with(prefix+"-"):return false
	var tail: String=id.trim_prefix(prefix+"-")
	return tail.is_valid_int() and tail.to_int()>0 and tail.to_int()<=serial

func load_json(text: String) -> String:
	var parser:=JSON.new()
	if parser.parse(text)!=OK or not parser.data is Dictionary:return "Battle save JSON is invalid."
	if _contains_fractional_number(parser.data):return "Battle save requires integer fixed-point state."
	var data: Dictionary=_integer_data(parser.data)
	var format: int=int(data.get("format_version",0))
	if format not in [11,12,13,14]:return "Earlier campaign schemas remain separate; choose schema 11, 12, 13 or 14."
	if not data.get("campaign") is Dictionary or not data.campaign.get("world") is Dictionary:return "Battle world metadata is missing."
	var saved_world_id: String=str(data.campaign.world.get("id",""))
	var expected: Dictionary=_integer_data(RiverNavigation.load_world(format==11,saved_world_id))
	if not expected.get("nodes") is Dictionary:return "Installed navigation data is missing."
	var graph: Dictionary=expected.nodes;expected.erase("nodes")
	var compact: bool=format==14 and not data.has("nodes")
	if compact:
		if data.campaign.world!=_world_reference(expected):return "Save world reference does not match the exact installed navigation revision."
		data.campaign=data.campaign.duplicate();data.campaign.world=expected;data.nodes=graph
	elif data.campaign.world!=expected or data.get("nodes")!=graph:
		return "Save world does not match the exact installed navigation revision."
	if format==11:
		var candidate: RefCounted=get_script().new()
		candidate.navigation_warmup=navigation_warmup
		var error: String=candidate._load_design_data(data,true)
		if not error.is_empty():return error
		var upgraded: Dictionary=GameplaySave.migrate(data)
		if not upgraded.error.is_empty():return upgraded.error
		return load_json(JSON.stringify(upgraded.data))
	var error: String=_validate_design(data,true)
	if not error.is_empty():return error
	var gates: Dictionary={}
	for s in expected.settlements:gates[s.id]=s.get("gate_nodes",[s.node])
	for id in data.cities:
		if data.cities[id].get("gate_nodes")!=gates.get(id,[]):return "Save gate metadata differs from the world."
	error=BoatTransport.validate(data)
	if not error.is_empty():return error
	return _load_design_data(data,true,true)

func _load_design_json(text: String) -> String:
	var parser:=JSON.new()
	if parser.parse(text)!=OK or not parser.data is Dictionary:return "Battle save JSON is invalid."
	if _contains_fractional_number(parser.data):return "Battle save requires integer fixed-point state."
	var data: Dictionary=_integer_data(parser.data)
	return _load_design_data(data)

func _load_design_data(data: Dictionary, trusted_world: bool=false, design_validated: bool=false) -> String:
	if data.get("format_version") not in [11,12,13,14]:return "This campaign requires schema 14 or a validated earlier campaign."
	var error: String=""
	if not design_validated:
		error=_validate_design(data,trusted_world)
		if not error.is_empty():return error
	var state: Dictionary=data.battle_state.duplicate(true)
	var proxy: Dictionary=data.duplicate();proxy.campaign=data.campaign.duplicate();proxy.erase("battle_state");proxy.format_version=8
	var defeat: bool=state.outcome.get("kind","")=="defeat"
	if defeat:
		var faction: String=state.outcome.get("faction","");var living: int=0;var holdings: int=0
		if faction not in Officers.FACTIONS or data.campaign.match_state!="finished" or data.winner!="" or not data.paused:return "Defeat outcome is invalid."
		if data.ai_factions.size()!=2 or faction in data.ai_factions:return "Defeat outcome must identify the human faction."
		for a in data.armies.values():
			if a.faction==faction:living+=int(a.troops)
		for c in data.cities.values():
			if c.owner==faction:living+=int(c.garrison);holdings+=1 if c.victory_point else 0
			for job in c.production_queue:
				if job.get("faction")==faction:return "Defeated faction still has a valid training job."
		if living>0 or holdings>0:return "Defeated faction still has cities or troops."
		proxy.campaign.match_state="running"
	if not data.winner.is_empty():
		if state.outcome.get("kind")!="victory" or state.outcome.get("faction")!=data.winner:return "Victory outcome differs from the winning faction."
		for a in data.armies.values():
			if a.faction!=data.winner and a.troops>0:return "Winner still has enemy formations."
		for c in data.cities.values():
			if c.owner!=data.winner and c.garrison>0:return "Winner still has enemy garrisons."
	error=super._load_commander_data(proxy,trusted_world)
	if not error.is_empty():return error
	faction_gold=state.faction_gold;operations=state.operations;transfers=state.transfers;pending_volleys=state.pending_volleys;pending_windups=state.pending_windups;operation_serial=int(state.serial);outcome=state.outcome
	traditional_rts=data.format_version in [13,14];tactical_rts=data.format_version==14
	vessels=state.get("vessels",{});river_navigation.configure(world_metadata)
	if defeat:match_state="finished"
	_refresh_contacts()
	if navigation_warmup:prewarm_campaign_navigation()
	return ""

func _ai_food_transfers(faction: String) -> void:
	for destination in _sorted_ids(cities):
		var c: Dictionary=cities[destination]
		# Transfers take real travel time. Start before an active recovery city
		# exhausts its stock, and use village warehouses as legitimate donors.
		var desired: int=2500 if _ai_city_slots(destination)>0 else 1000
		if c.owner!=faction or c.kind!="city" or c.food>=desired*SCALE or _city_under_siege(c):continue
		var reserved: bool=false
		for t in transfers:
			if t.faction==faction and t.destination==destination:reserved=true;break
		if reserved:continue
		var donor: String="";var nearest: int=2147483647
		for source in _sorted_ids(cities):
			var stock: Dictionary=cities[source]
			var reserve: int=1000 if stock.kind=="village" else 2500
			if source==destination or stock.owner!=faction or stock.food<(reserve+500)*SCALE or _city_under_siege(stock):continue
			var path: Dictionary=route_to_settlement(stock.node,c.node)
			if path.ok and path.distance<nearest:donor=source;nearest=path.distance
		if not donor.is_empty():
			var stock: Dictionary=cities[donor]
			var reserve: int=1000 if stock.kind=="village" else 2500
			var amount: int=mini(1500,int(stock.food)/SCALE-reserve)
			amount=mini(amount,int(c.food_cap-c.food)/SCALE)
			if amount>=500:request_transfer(faction,donor,destination,amount)

func _ai_city_slots(city_id: String) -> int:
	var slots: int=0
	for a in armies.values():
		if a.troops>0 and (a.resident_city==city_id or a.garrison_target==city_id):slots+=1
	return slots

func _move_armies() -> void:
	_move_field_armies()

func _move_field_armies() -> void:
	# Residents occupy the wall/garrison layer, not field collision or ferry space.
	var residents: Dictionary={}
	for id in armies.keys():
		if not armies[id].resident_city.is_empty():residents[id]=armies[id];armies.erase(id)
	super._move_armies()
	for id in residents:
		armies[id]=residents[id];armies[id].engaged_ids=[]

func _set_safe_retreat(a: Dictionary, destination: String, blocked: Dictionary) -> bool:
	if not NavigationPlan.commit(a,NavigationPlan.plan(self,a,destination,blocked)):return false
	a.order={"type":"retreat","target":destination}
	a.transport_id="";a.transport_elapsed=0;a.deferred_order={};a.siege_state="none"
	a.garrison_target="";a.entry_ticks=0
	BoatTransport.cancel_reservation(self,"army:"+str(a.id))
	if tactical_rts:
		TacticalOrders.initialize(a)
		_cancel_earlier_field_orders(str(a.id))
		_cancel_field_windup(str(a.id))
	return true

func _cancel_earlier_field_orders(army_id: String) -> void:
	var kept: Array=[]
	for command in command_queue:
		if command.type not in ["move","attack_move","attack","siege","retreat","hold"] or army_id not in command.army_ids:
			kept.append(command);continue
		var remaining: Array=command.army_ids.duplicate();remaining.erase(army_id)
		if remaining.is_empty():continue
		var group: Dictionary=command.duplicate(true);group.army_ids=remaining;kept.append(group)
	command_queue=kept

