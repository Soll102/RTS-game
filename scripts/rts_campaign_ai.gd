extends RefCounted
## Authored deterministic strategy through the player's paid command APIs.
const Rules=preload("res://scripts/rts_combat_rules.gd")
const DECISION_INTERVAL_TICKS=40
const MAX_ROUTE_QUERIES=8
const MAX_ORDERS=8
const MAX_FORMATIONS=6
const THREAT_RANGE=180.0
const RELIEF_RANGE=420.0
const RALLY_RANGE=140.0
const ESCORT_RANGE=420.0

static func strength(army: Dictionary, against: String="infantry") -> int:
	var value: int=int(army.troops)*maxi(25,int(army.morale))/100
	value=value*Rules.counter_percent(army.unit_type,against)/100
	if army.food==0:value=value*75/100
	if army.stance=="defensive":value=value*110/100
	value=value*Rules.lead_percent(army)/100
	return maxi(1,value)

static func _distance(sim,a: String,b: String) -> float:
	var p: Array=sim.nodes[a].position;var q: Array=sim.nodes[b].position
	return Vector2(p[0],p[2]).distance_to(Vector2(q[0],q[2]))

static func _eligible(sim,faction: String) -> Array:
	var reserved: Dictionary={}
	for command in sim.command_queue:
		for id in command.army_ids:reserved[id]=true
	var ids: Array=[]
	for id in sim._sorted_ids(sim.armies):
		var a: Dictionary=sim.armies[id]
		if a.faction==faction and a.troops>0 and not reserved.has(id) and not a.routed and a.transport_elapsed==0 and a.get("resident_city","").is_empty() and a.get("garrison_target","").is_empty():ids.append(id)
	return ids

static func _threats(sim,faction: String) -> Array:
	var result: Array=[]
	for city_id in sim._sorted_ids(sim.cities):
		var city: Dictionary=sim.cities[city_id]
		if city.owner!=faction:continue
		var enemies: Array=[];var power: int=0
		for id in sim._sorted_ids(sim.armies):
			var enemy: Dictionary=sim.armies[id]
			if enemy.faction==faction or enemy.troops<=0 or enemy.routed or enemy.transport_elapsed>0 or not enemy.get("resident_city","").is_empty():continue
			# A declared siege from across the map does not summon every defender.
			var nearest: int=2147483647
			for gate in (sim.gate_nodes(city_id) if sim.has_method("gate_nodes") else [city.node]):nearest=mini(nearest,_distance(sim,enemy.node,gate))
			if nearest<=THREAT_RANGE:
				enemies.append(id);power+=strength(enemy)
		if not enemies.is_empty():result.append({"city":city_id,"enemies":enemies,"power":power,"besieged":sim._city_under_siege(city)})
	result.sort_custom(func(a,b):return a.power>b.power if a.power!=b.power else a.city<b.city)
	return result

static func _tree(sim,id: String,context: Dictionary) -> Dictionary:
	var node: String=sim.armies[id].node
	if context.trees.has(node):return context.trees[node]
	if context.queries>=MAX_ROUTE_QUERIES:return {}
	context.queries+=1;var tree: Dictionary=sim.find_routes_from(node);context.trees[node]=tree;return tree

static func _path(sim,id: String,target: String,context: Dictionary) -> Dictionary:
	if sim.has_method("route_to_settlement"):
		var cached: Dictionary=sim.route_to_settlement(sim.armies[id].node,target)
		if not cached.is_empty():return cached
	var tree: Dictionary=_tree(sim,id,context)
	if tree.is_empty():return {"ok":false,"distance":2147483647}
	return sim.route_from_tree(tree,target)

static func _assign(sim,id: String,type: String,target: String,goal: String,context: Dictionary) -> bool:
	if context.assigned.has(id) or context.orders.size()>=MAX_ORDERS:return false
	var a: Dictionary=sim.armies[id]
	if type=="attack" and not sim.armies.has(target):return false
	var node: String=sim.armies[target].node if type=="attack" else sim.choose_siege_gate(a,target) if type=="siege" and sim.has_method("choose_siege_gate") else sim.cities[target].node if type=="siege" else target
	if type!="hold" and not _path(sim,id,node,context).ok:return false
	if type=="retreat" and node==a.node and a.edge_progress==0:type="hold";target=""
	context.assigned[id]=goal
	if a.order.type==type and a.order.target==target:return true
	context.orders.append({"army_id":id,"type":type,"target":target,"goal":goal});return true

static func _nearest_home(sim,id: String,cities: Array,context: Dictionary) -> String:
	var nearest: String="";var distance: int=2147483647
	for city_id in cities:
		if sim.cities[city_id].food<=0 or sim._city_under_siege(sim.cities[city_id]):continue
		var route: Dictionary=_path(sim,id,sim.cities[city_id].node,context)
		if route.ok and route.distance<distance:nearest=city_id;distance=route.distance
	return nearest

static func _objective(sim,faction: String,leader: String,group: Array,context: Dictionary) -> String:
	# The declared siege objective is faction-wide, not group-local: a cohort that
	# temporarily detaches (resupply, relief) must not lose the city it already
	# committed to, otherwise every assault restarts from scratch and the walls are
	# repaired in between (measured 2026-11-03).
	var previous: String=""
	for id in sim._sorted_ids(sim.armies):
		var a: Dictionary=sim.armies[id]
		if a.faction!=faction or a.troops<=0:continue
		if a.order.type=="siege" and sim.cities.has(a.order.target) and sim.cities[a.order.target].owner!=faction:
			previous=a.order.target;break
	if previous.is_empty():
		for id in group:
			var a: Dictionary=sim.armies[id]
			if a.order.type=="siege" and sim.cities.has(a.order.target) and sim.cities[a.order.target].owner!=faction:
				previous=a.order.target;break
	if not previous.is_empty():return previous
	var result: String="";var best: float=INF;var wall_power: int=0
	for id in group:wall_power+=Rules.siege_damage(sim.armies[id])
	var has_hostile_city: bool=false
	for c in sim.cities.values():
		if c.victory_point and c.owner!=faction:has_hostile_city=true;break
	for city_id in sim._sorted_ids(sim.cities):
		var c: Dictionary=sim.cities[city_id]
		if c.owner==faction:continue
		var owner_has_city: bool=false
		for holding in sim.cities.values():
			if holding.owner==c.owner and holding.victory_point:owner_has_city=true;break
		# A faction's final village still contains enemy guards. Ignoring it until
		# all eight cities fall prevents a valid defeat and final cleanup.
		if has_hostile_city and not c.victory_point and owner_has_city:continue
		var gate: String=sim.choose_siege_gate(sim.armies[leader],city_id) if sim.has_method("choose_siege_gate") else c.node
		var route: Dictionary=_path(sim,leader,gate,context)
		if not route.ok:continue
		var score: float=float(route.distance)+(float(c.wall_hp+c.garrison)/maxi(1,wall_power))*10.0+(100.0 if c.kind=="village" and owner_has_city else 0.0)
		if score<best:best=score;result=city_id
	return result

static func plan_decisions(sim,faction: String) -> Dictionary:
	var context: Dictionary={"trees":{},"queries":0,"orders":[],"assigned":{}}
	var ids: Array=_eligible(sim,faction)
	if ids.is_empty():return context
	var cities: Array=[]
	for id in sim._sorted_ids(sim.cities):
		if sim.cities[id].owner==faction:cities.append(id)
	# Exhausted units return to a real supplied stockpile rather than changing targets every pulse.
	# Thresholds are deliberately low: a cohort that keeps peeling off to resupply never
	# breaches a wall, and the defender repairs it in between.
	for id in ids:
		var a: Dictionary=sim.armies[id]
		# A formation already besieging a hostile city stays at the gate. Pulling it
		# home to resupply lets the defender repair the wall, so the assault restarts
		# from zero every cycle (measured 2026-11-03: wall 1200->1172->1190, no breach).
		if a.order.type=="siege" and sim.cities.has(a.order.target) and sim.cities[a.order.target].owner!=faction:continue
		if a.food>=10 and a.morale>=25:continue
		var home: String=_nearest_home(sim,id,cities,context)
		if not home.is_empty():_assign(sim,id,"retreat",sim.cities[home].node,"Resupply",context)
	# Only local formations answer actual nearby threats; committed distant assaults remain intact.
	for threat in _threats(sim,faction):
		var city: Dictionary=sim.cities[threat.city];var local: Array=[]
		for id in ids:
			var a: Dictionary=sim.armies[id]
			if context.assigned.has(id) or a.unit_type=="siege" or a.food<10 or a.morale<25 or a.order.type=="siege":continue
			if _distance(sim,a.node,city.node)<=RELIEF_RANGE:local.append(id)
		local.sort_custom(func(a,b):return _distance(sim,sim.armies[a].node,city.node)<_distance(sim,sim.armies[b].node,city.node))
		for id in local.slice(0,2):_assign(sim,id,"attack",threat.enemies[0],"Local relief",context)
	var ready: Array=[]
	for id in ids:
		var a: Dictionary=sim.armies[id]
		if not context.assigned.has(id) and a.food>=10 and a.morale>=25:ready.append(id)
	var ram: String=""
	for id in ready:
		if sim.armies[id].unit_type=="siege":ram=id;break
	var escorts: Array=[]
	for id in ready:
		if id!=ram and sim.armies[id].unit_type!="siege":escorts.append(id)
	escorts.sort_custom(func(a,b):
		var x: Dictionary=sim.armies[a];var y: Dictionary=sim.armies[b]
		var px: int=0 if x.unit_type=="infantry" else 1 if x.unit_type=="cavalry" else 2
		var py: int=0 if y.unit_type=="infantry" else 1 if y.unit_type=="cavalry" else 2
		return px<py if px!=py else x.troops>y.troops if x.troops!=y.troops else a<b)
	var group: Array=escorts.slice(0,4)
	if not ram.is_empty():group.push_front(ram)
	var melee: int=0
	for id in group:
		if sim.armies[id].unit_type in ["infantry","cavalry"]:melee+=1
	if not group.is_empty() and melee>0:
		var leader: String=ram if not ram.is_empty() else group[0]
		var objective: String=_objective(sim,faction,leader,group,context)
		if not objective.is_empty():
			# A shared target alone does not synchronize 2/3/4-speed formations.
			# Faster escorts briefly hold until the marching cohort is within 140
			# route units; soldiers pinned in combat do not stall the whole column.
			var remaining: Dictionary={};var furthest: int=0
			for id in group:
				var gate: String=sim.choose_siege_gate(sim.armies[id],objective) if sim.has_method("choose_siege_gate") else sim.cities[objective].node
				var route: Dictionary=_path(sim,id,gate,context)
				if not route.ok:continue
				remaining[id]=maxi(0,int(route.distance)-int(sim.armies[id].edge_progress))
				if sim.armies[id].engaged_ids.is_empty():furthest=maxi(furthest,int(remaining[id]))
			for id in group:
				var a: Dictionary=sim.armies[id]
				var at_gate: bool=a.node in (sim.gate_nodes(objective) if sim.has_method("gate_nodes") else [sim.cities[objective].node]) and a.edge_progress==0
				if remaining.has(id) and not at_gate and a.engaged_ids.is_empty() and int(remaining[id])+int(RALLY_RANGE)<furthest:
					_assign(sim,id,"hold","","Wait for assault cohort",context)
				else:_assign(sim,id,"siege",objective,"Assault cohort",context)
	# If no hostile settlement remains, hunt all living opponents, including routed units.
	var hostile: bool=false
	for c in sim.cities.values():
		if c.owner!=faction:hostile=true;break
	for id in ids:
		if context.assigned.has(id):continue
		var enemies: Array=[]
		for other in sim._sorted_ids(sim.armies):
			var b: Dictionary=sim.armies[other]
			if b.faction!=faction and b.troops>0 and b.transport_elapsed==0 and b.get("resident_city","").is_empty() and (not hostile or _distance(sim,sim.armies[id].node,b.node)<=120):enemies.append(other)
		enemies.sort_custom(func(a,b):return _distance(sim,sim.armies[id].node,sim.armies[a].node)<_distance(sim,sim.armies[id].node,sim.armies[b].node))
		var done: bool=false
		for enemy in enemies:
			if _assign(sim,id,"attack",enemy,"Clear remaining forces" if not hostile else "Screen",context):done=true;break
		if not done:_assign(sim,id,"hold","","Reserve",context)
	return context

static func _skills(sim,faction: String) -> void:
	if not sim.has_method("submit_skill"):return
	for id in sim._sorted_ids(sim.armies):
		var a: Dictionary=sim.armies[id]
		if a.faction!=faction or a.troops<=0 or a.routed or a.transport_elapsed>0 or not a.get("resident_city","").is_empty():continue
		var target: String="";var best: float=121.0
		for other in sim._sorted_ids(sim.armies):
			var b: Dictionary=sim.armies[other]
			if b.faction==faction or b.troops<=0 or b.transport_elapsed>0:continue
			var distance: float=sim._point(a).distance_to(sim._point(b))
			if distance<best:best=distance;target=other
		if not target.is_empty():sim.submit_skill(faction,id,target,"strategy-skill-%s-%d"%[id,sim.tick])

static func decide(sim,faction: String) -> void:
	var plan: Dictionary=plan_decisions(sim,faction)
	for order in plan.orders:
		sim.submit_command({"command_id":"campaign-ai-%s-%s-%d"%[faction,order.army_id,sim.tick],"faction":faction,"army_ids":[order.army_id],"type":order.type,"target":order.target})
	sim.performance_metrics["ai_route_queries"]=int(sim.performance_metrics.get("ai_route_queries",0))+plan.queries
	_skills(sim,faction)
	recruit(sim,faction)

static func recruit(sim,faction: String) -> void:
	var count: int=0;var types: Dictionary={}
	for a in sim.armies.values():
		if a.faction==faction and a.troops>0:count+=1;types[a.unit_type]=int(types.get(a.unit_type,0))+1
	for c in sim.cities.values():
		for job in c.production_queue:
			if job.faction==faction:count+=1;types[job.unit_type]=int(types.get(job.unit_type,0))+1
	if count>=(sim.formation_limit() if sim.has_method("formation_limit") else MAX_FORMATIONS):return
	var melee: int=int(types.get("infantry",0))+int(types.get("cavalry",0));var kind: String="infantry"
	if melee<2:kind="infantry"
	elif int(types.get("siege",0))<1:kind="siege"
	elif int(types.get("archers",0))<1:kind="archers"
	elif int(types.get("cavalry",0))<1:kind="cavalry"
	elif melee<3:kind="infantry"
	elif int(types.get("archers",0))<2:kind="archers"
	# Prefer the missing role; an affordable infantry formation can still storm a
	# city while saving for an expensive replacement. No prices or limits change.
	var choices: Array=[kind]
	# Filling every free commander with cheaper infantry prevents replacement of
	# the lost siege role. Save the real Food/Gold budget for the missing machine.
	if kind!="siege":
		for fallback in ["infantry","archers","cavalry"]:
			if fallback not in choices:choices.append(fallback)
	var holdings: int=0
	for city in sim.cities.values():
		if city.victory_point and city.owner==faction:holdings+=1
	var preferred_troops: int=100 if sim.get("traditional_rts")==true else 1500 if holdings>=6 else 1000 if holdings>=4 else 500
	for choice in choices:
		for city_id in sim._sorted_ids(sim.cities):
			var c: Dictionary=sim.cities[city_id]
			if c.owner!=faction or not c.recruitment_enabled or sim._city_under_siege(c):continue
			var wages: int=0;var food_need: int=0
			for a in sim.armies.values():
				if a.faction==faction and a.troops>0:wages+=sim._gold_rate(a);food_need+=sim._food_rate(a)*6
			for city in sim.cities.values():
				if city.owner==faction:wages+=int(city.garrison)*4
			var amounts: Array=[preferred_troops]
			if preferred_troops!=500 and sim.get("traditional_rts")!=true:amounts.append(500)
			for amount in amounts:
				var cost: int=int(amount)*int(sim.GOLD_COST[choice])*sim.SCALE/500
				var food_cost: int=int(amount)*int(sim.PROFILES[choice].cost)*sim.SCALE
				if sim.faction_gold[faction]<cost+wages*6 or c.food<food_cost+food_need:continue
				var available: Array=sim.available_commanders(faction)
				if available.is_empty():return
				if sim.recruit_with_commander(faction,city_id,"campaign-recruit-%s-%s-%d"%[faction,city_id,sim.tick],available[0],int(amount),choice).is_empty():return
