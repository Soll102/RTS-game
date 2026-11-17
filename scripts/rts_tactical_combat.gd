extends RefCounted
const Rules=preload("res://scripts/rts_tactical_rules.gd")
const Combat=preload("res://scripts/rts_combat_rules.gd")
const Orders=preload("res://scripts/rts_tactical_orders.gd")

static func damage(sim: RefCounted, attacker: Dictionary, defender: Dictionary) -> int:
	var adjusted: Dictionary=attacker.duplicate(true)
	adjusted.attack=maxi(1,int(attacker.attack)*sim.buff_percent(attacker.id,"attack")/100)
	var raw: int=Combat.casualties(adjusted,defender,str(sim.nodes[defender.node].get("terrain","plain")))*Rules.FIELD_POWER_PERCENT/100
	var amount: int=maxi(1,raw)
	if defender.get("routed",false) and defender.troops<=60:
		amount=maxi(amount,defender.troops)
	elif defender.troops<=20:
		amount=maxi(amount,defender.troops)
	elif defender.troops<=40 and attacker.troops>=30:
		amount=maxi(amount,defender.troops)
	return amount

static func resolve_battles(sim: RefCounted) -> void:
	var hits: Dictionary={}
	for id in sim._sorted_ids(sim.armies):
		if not sim.armies.has(id):continue
		var army: Dictionary=sim.armies[id]
		if army.troops<=0 or army.routed or army.transport_elapsed>0 or not army.get("resident_city","").is_empty():continue
		if army.order.type in ["move","retreat"] and not army.route.is_empty():continue
		var target: String=""
		if sim._contacts.has(id):
			var contacts: Array=[]
			for candidate in sim._contacts[id]:
				if Orders.field_enemy(sim,army,candidate):contacts.append(candidate)
			target=army.combat_target if army.combat_target in contacts else sim._target_for(army,contacts)
		if target.is_empty():
			var potential: String=army.order.target if army.order.type=="attack" else army.combat_target
			if not potential.is_empty() and sim.armies.has(potential):
				var enemy: Dictionary=sim.armies[potential]
				if Orders.field_enemy(sim,army,potential):
					var max_reach: float=140.0 if army.unit_type=="archers" else 28.0
					if sim._point(army).distance_to(sim._point(enemy))<=max_reach and sim.has_line_of_sight(army,enemy):
						target=potential
		if target.is_empty():continue
		if army.unit_type=="archers":
			if sim.tick-int(army.last_volley_tick)<Rules.ARCHER_INTERVAL:continue
			army.last_volley_tick=sim.tick;sim._begin_volley(id,"army",army.faction,[target],"field")
		else:
			var amount: int=damage(sim,army,sim.armies[target])
			hits[target]=int(hits.get(target,0))+amount
			sim._emit("field_attack",{"army":id,"target":target,"damage":amount,"ranged":false})
	sim._apply_damage(hits,"battle")

static func guard_origin(sim: RefCounted, city: Dictionary, target: Dictionary) -> Vector2:
	var chosen: Vector2=sim._point({"node":city.node,"edge_progress":0,"route":[]});var distance: float=INF
	for gate in sim.gate_nodes(city.id):
		var origin: Dictionary={"node":gate,"edge_progress":0,"route":[]}
		var point: Vector2=sim._point(origin);var length: float=point.distance_to(sim._point(target))
		if length<distance and length<=Rules.GUARD_RANGE and sim.has_line_of_sight(origin,target):chosen=point;distance=length
	return chosen

static func guard_targets(sim: RefCounted, city: Dictionary) -> Array:
	var result: Array=[]
	for id in sim._sorted_ids(sim.armies):
		var army: Dictionary=sim.armies[id]
		if army.faction==city.owner or army.troops<=0 or army.transport_elapsed>0 or not army.resident_city.is_empty():continue
		for gate in sim.gate_nodes(city.id):
			var origin: Dictionary={"node":gate,"edge_progress":0,"route":[]}
			if sim._point(origin).distance_to(sim._point(army))<=Rules.GUARD_RANGE and sim.has_line_of_sight(origin,army):result.append(id);break
	# Stable nearest-first targeting gives the player a readable defensive front.
	result.sort_custom(func(a,b):
		var x: float=guard_origin(sim,city,sim.armies[a]).distance_squared_to(sim._point(sim.armies[a]))
		var y: float=guard_origin(sim,city,sim.armies[b]).distance_squared_to(sim._point(sim.armies[b]))
		return a<b if is_equal_approx(x,y) else x<y)
	return result.slice(0,Rules.GUARD_TARGETS)

static func city_volleys(sim: RefCounted) -> void:
	for id in sim._sorted_ids(sim.cities):
		var city: Dictionary=sim.cities[id];var targets: Array=guard_targets(sim,city)
		if targets.is_empty():continue
		if sim.tick%Rules.GUARD_INTERVAL==0 and city.garrison>0:sim._begin_volley(id,"city",city.owner,targets,"guard",id)
		for resident in sim.resident_ids(id):
			var army: Dictionary=sim.armies[resident]
			if army.routed or army.unit_type!="archers" or sim.tick-int(army.last_volley_tick)<Rules.ARCHER_INTERVAL:continue
			army.last_volley_tick=sim.tick;sim._begin_volley(resident,"army",army.faction,[targets[0]],"resident",id)

static func besieged(sim: RefCounted, city: Dictionary) -> bool:
	for army in sim.armies.values():
		if army.troops>0 and not army.routed and army.faction!=city.owner and army.order.type=="siege" and army.order.target==city.id and army.node==sim._target_node(army.order) and army.edge_progress==0 and army.transport_elapsed==0 and army.resident_city.is_empty():return true
	return false

static func resolve_sieges(sim: RefCounted) -> void:
	for id in sim._sorted_ids(sim.cities):
		var city: Dictionary=sim.cities[id];var attackers: Array=[];var factions: Dictionary={};var contested: bool=false
		for key in sim._sorted_ids(sim.armies):
			var army: Dictionary=sim.armies[key]
			if army.troops<=0 or army.transport_elapsed>0 or not army.resident_city.is_empty() or army.node not in sim.gate_nodes(id) or army.edge_progress>0:continue
			if army.faction==city.owner and not army.routed:contested=true
			elif not army.routed and army.order.type=="siege" and army.order.target==id and army.node==sim._target_node(army.order):
				if not army.engaged_ids.is_empty():army.siege_state="contested";continue
				attackers.append(key);factions[army.faction]=true
		if attackers.is_empty():city.capture_ticks=0;city.capture_faction="";continue
		city.last_siege_tick=sim.tick
		if contested or factions.size()!=1:
			city.capture_ticks=0;city.capture_faction=""
			for key in attackers:sim.armies[key].siege_state="contested"
			continue
		var outgoing: int=0
		for key in attackers:
			outgoing+=Combat.siege_damage(sim.armies[key]);sim.armies[key].siege_state="besieging" if city.wall_hp>0 else "breached"
		if city.wall_hp>0:
			city.wall_hp=maxi(0,int(city.wall_hp)-outgoing)
			city.city_morale=maxi(0,int(city.city_morale)-1)
		else:
			var proxy: Dictionary={"troops":maxi(1,int(city.garrison)),"defense":20,"unit_type":"infantry","stance":"defensive","morale":100,"food":1,"attack":10}
			for key in attackers:
				var army: Dictionary=sim.armies[key]
				if army.unit_type not in ["infantry","cavalry"]:continue
				var adjusted: Dictionary=army.duplicate(true);adjusted.attack=maxi(1,int(army.attack)*sim.buff_percent(key,"attack")/100)
				outgoing+=Combat.casualties(adjusted,proxy,"plain")/2
			city.city_hp=maxi(0,int(city.city_hp)-outgoing)
			city.city_morale=maxi(0,int(city.city_morale)-1)
			var residents: Array=sim.resident_ids(id);var strength: int=int(city.garrison)
			for key in residents:strength+=int(sim.armies[key].troops)
			if strength>0:
				var guard_damage: int=outgoing*int(city.garrison)/strength
				city.garrison=maxi(0,int(city.garrison)-guard_damage)
				var hits: Dictionary={};var spent: int=guard_damage
				for index in range(residents.size()):
					var key: String=residents[index];var army: Dictionary=sim.armies[key]
					var share: int=outgoing*int(army.troops)/strength
					if index==residents.size()-1:share=outgoing-spent
					if share>0:hits[key]=share
					spent+=share
					if not army.routed and army.unit_type in ["infantry","cavalry"]:
						var target: String=attackers[0];hits[target]=int(hits.get(target,0))+damage(sim,army,sim.armies[target])
				if not hits.is_empty():sim._apply_damage(hits,"garrison")
		# Morale or inner HP alone never bypasses walls and living defenders.
		if city.wall_hp>0 or city.garrison>0 or city.city_hp>0 or not sim.resident_ids(id).is_empty():city.capture_ticks=0;city.capture_faction="";continue
		var occupiers: Array=[]
		for key in attackers:
			var army: Dictionary=sim.armies[key]
			if army.troops>0 and not army.routed and army.morale>20 and army.unit_type in ["infantry","cavalry"]:occupiers.append(key)
		if occupiers.is_empty():city.capture_ticks=0;city.capture_faction="";continue
		var faction: String=sim.armies[occupiers[0]].faction
		if city.capture_faction!=faction:city.capture_ticks=0;city.capture_faction=faction
		city.capture_ticks+=10
		if city.capture_ticks<Rules.capture_duration(city):continue
		sim._capture_city(city,attackers,faction)
		for key in attackers:
			if sim.armies[key].troops>0:Orders.advance(sim,sim.armies[key])
