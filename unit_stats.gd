extends RefCounted
## Read-only views use the same integer damage/protection stages as the simulation.
const Campaign=preload("res://scripts/rts_campaign_simulation.gd")
const Combat=preload("res://scripts/rts_combat_rules.gd")
const Officers=preload("res://scripts/rts_commander_rules.gd")
const Traditional=preload("res://scripts/rts_traditional_rules.gd")
const TYPES=["infantry","archers","cavalry","siege"]
const NAMES={"infantry":"Infantry","archers":"Archers","cavalry":"Cavalry","siege":"Siege"}
const TICK_SECONDS=.1
const DEFAULT_RECRUIT_TROOPS=500

static func types() -> Array:return TYPES.duplicate()
static func ticks_to_seconds(ticks: int) -> float:return float(ticks)*TICK_SECONDS
static func units_to_metres(units: float) -> float:return units/10.0

static func movement_budget(army: Dictionary, terrain: String="plain", speed_percent: int=100) -> int:
	var budget: int=maxi(1,int(army.get("movement_per_tick",1))*maxi(0,speed_percent)/100)
	if army.get("unit_type")=="cavalry" and terrain in ["forest","hill"]:budget=maxi(1,budget*70/100)
	return mini(8,budget)

static func speed_metres_per_second(army: Dictionary, terrain: String="plain", speed_percent: int=100) -> float:
	return float(movement_budget(army,terrain,speed_percent))

static func attack_range_metres(kind: String) -> float:
	return units_to_metres(Campaign.ARCHER_RANGE if kind=="archers" else Campaign.MELEE_RANGE+2)

static func field_damage(attacker: Dictionary, defender: Dictionary, terrain: String="plain", attack_percent: int=100, protection_percent: int=100, field_percent: int=100) -> int:
	var adjusted: Dictionary=attacker.duplicate(true)
	adjusted.attack=maxi(1,int(adjusted.attack)*maxi(0,attack_percent)/100)
	var damage: int=maxi(1,Combat.casualties(adjusted,defender,terrain)*field_percent/100)
	return maxi(1,damage*10000/(Combat.lead_percent(defender)*maxi(100,protection_percent)))

static func base_profile(kind: String, _simulation: RefCounted=null, _officer: String="") -> Dictionary:
	if kind not in TYPES:return {}
	var raw: Dictionary=Campaign.PROFILES[kind]
	var profile: Dictionary={"kind":kind,"name":NAMES[kind],"people":8,"rows":2,"columns":4,
		"starting_troops":500 if kind=="siege" else 750,"default_recruit_troops":500,"recruitment_cost":500*int(raw.cost),
		"cost_per_troop":int(raw.cost),"training_ticks":int(raw.training),"attack":10,"defense":10,
		"movement_per_tick":int(raw.movement),"siege_power":int(raw.siege),"morale":100,"food_initial":80,"food_capacity":120,
		"reference_strength":500,"attack_range_metres":attack_range_metres(kind),"combat_seconds":ticks_to_seconds(Campaign.COMBAT_INTERVAL),
		"food_interval_seconds":ticks_to_seconds(Campaign.FOOD_INTERVAL),"commander":{}}
	profile.traditional_rts=_simulation!=null and _simulation.get("traditional_rts")==true
	profile.field_percent=_simulation.Tactical.FIELD_POWER_PERCENT if _simulation!=null and _simulation.get("tactical_rts")==true else 100
	if _simulation!=null and _simulation.get("tactical_rts")==true and kind=="archers":profile.combat_seconds=ticks_to_seconds(_simulation.Tactical.ARCHER_INTERVAL)
	if _simulation!=null and _simulation.get("traditional_rts")==true:
		var p: Dictionary=Traditional.PROFILES[kind]
		profile.merge({"people":4,"rows":2,"columns":2,"starting_troops":p.strength,"default_recruit_troops":100,"recruitment_cost":100*int(raw.cost),"attack":p.attack,"defense":p.defense,"movement_per_tick":p.movement,"siege_power":p.siege,"training_ticks":p.training,"reference_strength":100},true)
	var reference: Dictionary=army_from_profile(profile)
	if _simulation!=null and _simulation.get("traditional_rts")==true:reference.traditional_unit=true
	profile.speed_metres_per_second=speed_metres_per_second(reference)
	profile.siege_damage=Combat.siege_damage(reference)
	profile.damage_vs_infantry=field_damage(reference,reference_defender(),"plain",100,100,profile.field_percent)
	return profile

static func army_from_profile(profile: Dictionary, strength: int=-1) -> Dictionary:
	return {"id":"stats-reference","unit_type":profile.kind,"troops":profile.reference_strength if strength<0 else strength,
		"attack":profile.attack,"defense":profile.defense,"movement_per_tick":profile.movement_per_tick,"siege_power":profile.siege_power,
		"morale":profile.morale,"food":profile.food_initial,"food_capacity":profile.food_capacity,"stance":"balanced","commander_lead":50}

static func reference_defender() -> Dictionary:
	return {"unit_type":"infantry","troops":500,"attack":10,"defense":10,"movement_per_tick":2,"siege_power":4,"morale":100,"food":80,"food_capacity":120,"stance":"balanced","commander_lead":50}

static func selected_profile(simulation: RefCounted, army_id: String) -> Dictionary:
	if simulation==null or not simulation.armies.has(army_id):return {}
	var army: Dictionary=simulation.armies[army_id]
	var profile: Dictionary=base_profile(str(army.unit_type),simulation)
	if profile.is_empty():return {}
	var terrain: String=str(simulation.nodes.get(army.node,{}).get("terrain","plain"))
	var attack_buff: int=simulation.buff_percent(army_id,"attack")
	var speed_buff: int=simulation.buff_percent(army_id,"speed")
	var protection: int=simulation.buff_percent(army_id,"defense")
	profile.merge({"army_id":army_id,"terrain":terrain,"stance":army.stance,"current_strength":int(army.troops),"current_morale":int(army.morale),
		"current_food":int(army.food),"food_capacity":int(army.food_capacity),"base_attack":int(army.attack),"effective_attack":maxi(1,int(army.attack)*attack_buff/100),
		"base_defense":int(army.defense),"effective_defense":Combat.defense(army,terrain,0),"attack_buff_percent":attack_buff,"speed_buff_percent":speed_buff,
		"protection_percent":protection,"current_speed_metres_per_second":speed_metres_per_second(army,terrain,speed_buff),"current_siege_damage":Combat.siege_damage(army),
		"current_damage_vs_infantry":field_damage(army,reference_defender(),terrain,attack_buff,100,profile.field_percent),"supplied":army.supplied,"routed":army.routed,
		"order":army.order.type,"on_ferry":army.transport_elapsed>0,"commander":simulation.commander_profile(army_id)},true)
	return profile

static func counter_rows(kind: String, traditional: bool=false) -> Array:
	var rows: Array=[]
	for target in TYPES:rows.append([NAMES[target],"%d%% outgoing field power"%Combat.counter_percent(kind,target,traditional)])
	return rows

static func matchup_description(simulation: RefCounted=null) -> String:
	var traditional: bool=simulation!=null and simulation.get("traditional_rts")==true
	return "Infantry beats cavalry, cavalry beats archers, and archers beat infantry: %d%% field power. Siege deals %d%% field power, but double raw fortification power."%[Combat.counter_percent("infantry","cavalry",traditional),Combat.counter_percent("siege","infantry",traditional)]

static func detail_sections(p: Dictionary) -> Array:
	if p.is_empty():return []
	var sections: Array=[]
	var commander: Dictionary=p.get("commander",{})
	if not commander.is_empty():
		sections.append({"title":"Commander","rows":[["Name",commander.name],["STR",str(commander.str)],["LEAD",str(commander.lead)],
			["LEAD power / protection","%d%% outgoing army and siege power; incoming damage divided by %.2f."%[commander.lead_percent,commander.lead_percent/100.0]],
			["STR skill strength","%d%% of base skill damage, morale change or buff bonus."%commander.str_percent],
			["Skill",commander.skill+" | "+commander.description],["STR-adjusted skill power",str(commander.skill_power)],
			["Cooldown / duration","%.0fs / %.0fs of simulation time"%[ticks_to_seconds(commander.cooldown),ticks_to_seconds(commander.duration)]],
			["Range / radius","%.1fm / %.1fm"%[units_to_metres(commander.range),units_to_metres(commander.radius)]],
			["Availability","One commander per living unit. Training reserves its commander; defeat releases the commander."]]})
	if p.has("army_id"):
		sections.append({"title":"Selected formation","rows":[["Troops",str(p.current_strength)],["Morale / food","%d%% / %d of %d"%[p.current_morale,p.current_food,p.food_capacity]],
			["Terrain / stance",p.terrain.capitalize()+" / "+p.stance.capitalize()],["Attack / defense coefficient","%d / %d"%[p.effective_attack,p.effective_defense]],
			["Current reference damage","%d per pulse against reference infantry on this terrain"%p.current_damage_vs_infantry],
			["Current siege damage","%d per pulse"%p.current_siege_damage],["Protection buff","%d%%, in addition to LEAD"%p.protection_percent],
			["Speed budget","%.1fm/s before contact or ferry blocking"%p.current_speed_metres_per_second],["Status","Ferry" if p.on_ferry else "Routing" if p.routed else p.order.capitalize()],
			["Supply","Connected" if p.supplied else "Disconnected; carried food"]]})
	sections.append({"title":"Recruitment","rows":[["Starting troops",str(p.starting_troops)],["Cost / %d troops"%int(p.default_recruit_troops),"%d city food"%p.recruitment_cost],
		["Training","%.0f simulation seconds; the first queued order trains"%ticks_to_seconds(p.training_ticks)],
		["Commander","Choose a free commander before ordering. Each queued formation reserves a different commander."],
		["Limits","3 orders per city; 6 living or queued formations per faction."],["Training pauses","Villages cannot recruit; besieged cities suspend training."]]})
	sections.append({"title":"Base combat and movement","rows":[["Attack / defense coefficient","%d / %d"%[p.attack,p.defense]],
		["Attack range","%.1fm with line of sight"%p.attack_range_metres],["Combat pulse","%.1f simulation second"%p.combat_seconds],
		["Reference damage","%d per pulse for %d troops, full morale, open ground, LEAD 50"%[p.damage_vs_infantry,p.reference_strength]],
		["Base speed","%.1fm/s; contact and ferry queues may stop movement"%p.speed_metres_per_second],["Base siege damage","%d per pulse at LEAD 50"%p.siege_damage],
		["Siege","Destroy walls, then garrison. Competing factions or defending units contest capture."]]})
	sections.append({"title":"Conditional rules","rows":[["Aggressive / defensive","120% / 80% outgoing power; defense -10 / +30."],
		["Forest / hill / ford","Defense +20 / +25 / -15. Cavalry field power is 70% in rough terrain; forest/hill movement is slower."],
		["Food","Upkeep is proportional to troop strength and role, charged each %.0fs; disconnected supply uses carried food. Empty food reduces field/siege power and morale."%p.food_interval_seconds],
		["Morale","0-100; morale at 20 or below triggers retreat. Supplied units may rally after 10 seconds."],
		["LEAD formula","(50 + LEAD) / 100; applied once to outgoing power and once as the incoming protection divisor."],
		["STR formula","(50 + STR) / 100; buff bonuses scale above 100%, while cooldown and range stay fixed."]]})
	sections.append({"title":"Type matchups","rows":counter_rows(p.kind,p.get("traditional_rts",false))})
	return sections

static func comparison_rows(simulation: RefCounted=null) -> Array:
	var rows: Array=[]
	for kind in TYPES:
		var p: Dictionary=base_profile(kind,simulation)
		rows.append([p.name,str(p.recruitment_cost),"%.0fs"%ticks_to_seconds(p.training_ticks),"%.1fm/s"%p.speed_metres_per_second,
			"%.1fm"%p.attack_range_metres,str(p.attack),str(p.defense),str(p.siege_damage)])
	return rows
