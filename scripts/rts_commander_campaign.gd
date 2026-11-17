extends "res://scripts/rts_campaign_simulation.gd"
## Commanders are data attached to formations. No independent hero or respawn exists.
const Officers=preload("res://scripts/rts_commander_rules.gd")
const COMMANDER_FORMAT=8
var officers: Dictionary={}
var skill_queue: Array=[]
var buffs: Dictionary={}

func configure(world: Dictionary, initial_armies: Array, initial_cities: Array, initial_seed: int=1) -> String:
	if Officers.DEFINITIONS.size()!=18:return "The 18 exact commander portrait/balance records are required."
	for faction in Officers.FACTIONS:
		if Officers.choices_for(faction).size()!=Officers.MAX_FORMATIONS:return "Each faction needs exactly six commanders."
	var initial_choices: Dictionary={}
	for item in initial_armies:
		if not item is Dictionary or item.get("unit_type") not in ["infantry","archers","cavalry","siege"]:return "Only troop formations may enter this campaign."
		if not item.get("id") is String:return "Initial formation identity is invalid."
		initial_choices[item.id]=str(item.get("commander_id",Officers.INITIAL_ASSIGNMENTS.get(item.id,"")))
	var error: String=super.configure(world,initial_armies,initial_cities,initial_seed)
	if not error.is_empty():return error
	officers=Officers.create_roster();buffs.clear();skill_queue.clear()
	for id in _sorted_ids(armies):
		if armies[id].troops<=0:continue
		var choice: String=str(initial_choices.get(id,""))
		if choice.is_empty():
			var available: Array=available_commanders(armies[id].faction)
			if available.is_empty():return "A living formation needs an available commander."
			choice=available[0]
		error=assign_officer(armies[id].faction,choice,id)
		if not error.is_empty():return error
	_sync_commander_stats()
	return ""

func officer_for(army_id: String) -> String:
	for id in officers:
		if officers[id].army_id==army_id:return id
	return ""

func available_commanders(faction: String) -> Array:
	var result: Array=[]
	for id in Officers.choices_for(faction):
		var state: Dictionary=officers.get(id,{})
		if state.get("army_id","").is_empty() and state.get("reserved_army","").is_empty():result.append(id)
	return result

func commander_profile(army_id: String) -> Dictionary:
	var id: String=officer_for(army_id)
	if id.is_empty():return {}
	var result: Dictionary=Officers.DEFINITIONS[id].duplicate(true)
	result.id=id;result.army_id=army_id;result.lead_percent=Officers.stat_percent(int(result.lead))
	result.str_percent=Officers.stat_percent(int(result.str));result.skill_power=skill_power_for(id)
	result.cooldown_ticks=skill_remaining_ticks(id)
	return result

func assign_officer(faction: String, officer_id: String, army_id: String) -> String:
	if match_state=="finished":return "Campaign finished."
	if not officers.has(officer_id) or Officers.DEFINITIONS[officer_id].faction!=faction:return "Commander does not belong to this faction."
	if not armies.has(army_id) or armies[army_id].faction!=faction or armies[army_id].troops<=0:return "Choose a living friendly formation."
	var state: Dictionary=officers[officer_id]
	if not state.reserved_army.is_empty():return "Commander is reserved for a formation in training."
	if not state.army_id.is_empty() and state.army_id!=army_id:return "Commander already leads another living formation."
	var army: Dictionary=armies[army_id]
	if army.routed or army.transport_elapsed>0 or not army.engaged_ids.is_empty():return "Change commander while this formation is ready and on land."
	for command in skill_queue:
		if command.army_id==army_id:return "Wait for this formation's queued skill."
	var previous: String=officer_for(army_id)
	if previous==officer_id:return ""
	if not previous.is_empty():officers[previous].army_id=""
	state.army_id=army_id;_sync_commander_stats()
	_emit("commander_assigned",{"army":army_id,"officer":officer_id})
	return ""

func _sync_commander_stats() -> void:
	for id in armies:
		var commander: String=officer_for(id)
		armies[id].commander_id=commander
		armies[id].commander_lead=int(Officers.DEFINITIONS[commander].lead) if not commander.is_empty() else 50
		armies[id].commander_str=int(Officers.DEFINITIONS[commander].str) if not commander.is_empty() else 50

func recruit_with_commander(faction: String, city_id: String, army_id: String, officer_id: String, troops: int=500, kind: String="infantry") -> String:
	if officer_id not in available_commanders(faction):return "Choose an available commander for this formation."
	var error: String=super.queue_recruitment(faction,city_id,army_id,troops,kind)
	if not error.is_empty():return error
	cities[city_id].production_queue.back().commander_id=officer_id
	officers[officer_id].reserved_army=army_id
	_emit("commander_reserved",{"army":army_id,"officer":officer_id,"city":city_id})
	return ""

func queue_recruitment(faction: String, city_id: String, army_id: String, troops: int=500, unit_type: String="infantry") -> String:
	# Human orders always come through the explicit commander choice.
	if faction not in ai_factions:return "Choose an available commander before recruiting."
	var available: Array=available_commanders(faction)
	if available.is_empty():return "No commander is available."
	return recruit_with_commander(faction,city_id,army_id,available[0],troops,unit_type)

func _reconcile_reservations() -> void:
	var jobs: Dictionary={}
	for city in cities.values():
		for job in city.production_queue:jobs[job.army_id]=true
	for id in officers:
		var state: Dictionary=officers[id]
		if not state.army_id.is_empty() and (not armies.has(state.army_id) or armies[state.army_id].troops<=0):state.army_id=""
		if state.reserved_army.is_empty():continue
		if armies.has(state.reserved_army) and armies[state.reserved_army].troops>0:
			state.army_id=state.reserved_army;state.reserved_army=""
		elif not jobs.has(state.reserved_army):
			_emit("commander_released",{"officer":id,"army":state.reserved_army});state.reserved_army=""
	_sync_commander_stats()

func _update_production() -> void:
	super._update_production();_reconcile_reservations()

func _resolve_sieges() -> void:
	super._resolve_sieges();_reconcile_reservations()

func skill_remaining_ticks(officer_id: String) -> int:
	return maxi(0,int(officers.get(officer_id,{}).get("cooldown_until",0))-tick)

func skill_power_for(officer_id: String) -> int:
	var power: int=Officers.skill_power(officer_id)
	if get("traditional_rts")==true and Officers.DEFINITIONS.get(officer_id,{}).get("effect","") in ["sweep","volley"]:power=maxi(1,power/4)
	return power

func submit_skill(faction: String, army_id: String, target_id: String, command_id: String) -> String:
	if command_id.is_empty() or command_ids.has(command_id):return "Command ID is missing or already used."
	if match_state=="finished":return "Campaign finished."
	var officer: String=officer_for(army_id)
	if officer.is_empty() or not armies.has(army_id) or armies[army_id].faction!=faction:return "Select a friendly formation with a commander."
	if armies[army_id].troops<=0 or armies[army_id].routed or armies[army_id].transport_elapsed>0:return "Commander cannot act while defeated, routing or aboard a ferry."
	if skill_remaining_ticks(officer)>0:return "Skill is on cooldown."
	for order in skill_queue:
		if order.officer==officer:return "This commander already has a queued skill."
	var command: Dictionary={"command_id":command_id,"faction":faction,"army_id":army_id,"officer":officer,"target":target_id,"issued_tick":tick}
	if _skill_targets(command).is_empty():return "No valid skill target in range and line of sight."
	command_ids[command_id]=true;skill_queue.append(command)
	return ""

func _skill_targets(command: Dictionary) -> Array:
	var id: String=command.army_id
	if not armies.has(id) or armies[id].troops<=0:return []
	var caster: Dictionary=armies[id];var definition: Dictionary=Officers.DEFINITIONS[command.officer]
	var effect: String=definition.effect;var origin: Vector2=_point(caster);var center: Vector2=origin;var direction:=Vector2.ZERO
	if effect in ["sweep","volley"]:
		if not armies.has(command.target):return []
		var target: Dictionary=armies[command.target]
		if target.troops<=0 or target.faction==caster.faction or target.transport_elapsed>0:return []
		center=_point(target);direction=center-origin
		if direction.length()>definition.range or not has_line_of_sight(caster,target):return []
		if effect=="sweep":center=origin
	var result: Array=[]
	for other in _sorted_ids(armies):
		var army: Dictionary=armies[other]
		if army.troops<=0 or army.transport_elapsed>0:continue
		if effect in ["speed","attack","defense"]:
			if other==id:result.append(other)
			continue
		var enemy: bool=army.faction!=caster.faction
		if enemy!=(effect in ["sweep","volley","roar"]):continue
		var delta: Vector2=_point(army)-center
		if delta.length()>definition.radius:continue
		if enemy and not has_line_of_sight(caster,army):continue
		if effect=="sweep" and not delta.is_zero_approx() and not direction.is_zero_approx() and delta.normalized().dot(direction.normalized())<cos(PI/4):continue
		if effect=="rally" and army.morale>=100:continue
		result.append(other)
	return result

func _expire_buffs() -> void:
	for id in buffs.keys():
		for stat in buffs[id].keys():
			if buffs[id][stat].until_tick<=tick:buffs[id].erase(stat)
		if buffs[id].is_empty():buffs.erase(id)

func _add_buff(army_id: String, stat: String, percent: int, duration: int) -> void:
	if not buffs.has(army_id):buffs[army_id]={}
	var previous: Dictionary=buffs[army_id].get(stat,{})
	buffs[army_id][stat]={"percent":maxi(percent,previous.get("percent",100)),"until_tick":maxi(tick+duration,previous.get("until_tick",0))}

func buff_percent(army_id: String, stat: String) -> int:
	var value: Dictionary=buffs.get(army_id,{}).get(stat,{})
	return value.get("percent",100) if value.get("until_tick",0)>tick else 100

func _apply_commands() -> void:
	_expire_buffs();_reconcile_reservations()
	for officer in officers:
		var state: Dictionary=officers[officer]
		if state.army_id.is_empty():continue
		var army: Dictionary=armies[state.army_id]
		if army.faction not in ai_factions or (tick-1)%CampaignAI.DECISION_INTERVAL_TICKS!=0 or skill_remaining_ticks(officer)>0:continue
		var target: String="";var nearest: float=INF
		for other in _sorted_ids(armies):
			if armies[other].faction==army.faction or armies[other].troops<=0:continue
			var distance: float=_point(armies[other]).distance_to(_point(army))
			if distance<nearest:nearest=distance;target=other
		if nearest<=120:submit_skill(army.faction,state.army_id,target,"commander-ai-%s-%d"%[officer,tick])
	var damage: Dictionary={}
	for command in skill_queue:
		var state: Dictionary=officers[command.officer];var army: Dictionary=armies[command.army_id]
		if state.army_id!=command.army_id or army.troops<=0 or army.routed or army.transport_elapsed>0 or skill_remaining_ticks(command.officer)>0:continue
		var targets: Array=_skill_targets(command)
		if targets.is_empty():_emit("skill_failed",{"officer":command.officer,"reason":"Target unavailable."});continue
		var definition: Dictionary=Officers.DEFINITIONS[command.officer];var power: int=skill_power_for(command.officer)
		for id in targets:
			match definition.effect:
				"sweep","volley":damage[id]=int(damage.get(id,0))+power
				"roar":armies[id].morale=maxi(0,int(armies[id].morale)-power)
				"rally":armies[id].morale=mini(100,int(armies[id].morale)+power)
				"defense_aura":_add_buff(id,"defense",power,definition.duration)
				_:_add_buff(id,definition.effect,power,definition.duration)
		state.cooldown_until=tick+int(definition.cooldown)
		_emit("commander_skill",{"officer":command.officer,"army":command.army_id,"skill":definition.skill,"targets":targets,"power":power,"str":int(definition.str)})
	skill_queue.clear();_apply_damage(damage,"commander_skill");super._apply_commands()

func _move_armies() -> void:
	var original: Dictionary={}
	for id in armies:
		original[id]=armies[id].movement_per_tick
		armies[id].movement_per_tick=maxi(1,int(original[id])*buff_percent(id,"speed")/100)
	super._move_armies()
	for id in original:armies[id].movement_per_tick=original[id]

func _resolve_battles() -> void:
	var original: Dictionary={}
	for id in armies:
		original[id]=armies[id].attack;armies[id].attack=maxi(1,int(original[id])*buff_percent(id,"attack")/100)
	super._resolve_battles()
	for id in original:armies[id].attack=original[id]

func _apply_damage(damage: Dictionary, reason: String) -> void:
	var adjusted: Dictionary=damage.duplicate()
	if reason in ["battle","garrison","commander_skill"]:
		for id in adjusted:
			var protection: int=Officers.stat_percent(int(armies[id].get("commander_lead",50)))*buff_percent(id,"defense")
			adjusted[id]=maxi(1,int(adjusted[id])*10000/protection) if adjusted[id]>0 else 0
	super._apply_damage(adjusted,reason)

func _defeat(army: Dictionary, reason: String) -> void:
	super._defeat(army,reason)
	var officer: String=officer_for(army.id)
	if not officer.is_empty():
		officers[officer].army_id="";_emit("commander_released",{"officer":officer,"army":army.id})
	buffs.erase(army.id)
	var kept: Array=[]
	for command in skill_queue:
		if command.army_id!=army.id:kept.append(command)
	skill_queue=kept;_sync_commander_stats()

func snapshot() -> Dictionary:
	var data: Dictionary=super.snapshot();data.format_version=COMMANDER_FORMAT
	data.commander_state={"revision":Officers.REVISION,"source_sha256":Officers.source_hash(),"roster":officers.duplicate(true),"buffs":buffs.duplicate(true),"commands":skill_queue.duplicate(true)}
	return data

func _validate_commander_save(data: Dictionary) -> String:
	if not data.get("armies") is Dictionary or not data.get("cities") is Dictionary or not _integer_at_least(data.get("tick"),0):return "Commander save armies, cities or clock are invalid."
	var state=data.get("commander_state")
	if not state is Dictionary or state.get("revision")!=Officers.REVISION or state.get("source_sha256")!=Officers.source_hash():return "Commander source/rules revision differs from this review."
	if not state.get("roster") is Dictionary or state.roster.size()!=Officers.DEFINITIONS.size() or not state.get("buffs") is Dictionary or not state.get("commands") is Array:return "Commander save roster, buffs or commands are incomplete."
	var bound: Dictionary={};var reserved: Dictionary={};var jobs: Dictionary={}
	for city in data.cities.values():
		if not city is Dictionary or not city.get("production_queue") is Array:return "Commander recruitment queue is invalid."
		for job in city.production_queue:
			if not job is Dictionary or not job.get("army_id") is String or not job.get("commander_id") is String or not job.get("faction") is String:return "Recruitment must reserve an exact commander."
			if jobs.has(job.army_id):return "Duplicate recruitment identity."
			jobs[job.army_id]=job
	for id in state.roster:
		if not Officers.DEFINITIONS.has(id) or not state.roster[id] is Dictionary:return "Unknown commander in save."
		var officer: Dictionary=state.roster[id]
		if not officer.get("army_id") is String or not officer.get("reserved_army") is String or not _integer_at_least(officer.get("cooldown_until"),0):return "Commander assignment or clock is invalid."
		if officer.cooldown_until>int(data.tick)+int(Officers.DEFINITIONS[id].cooldown):return "Commander cooldown exceeds its definition."
		if not officer.army_id.is_empty() and not officer.reserved_army.is_empty():return "A commander cannot lead and train two formations."
		if not officer.army_id.is_empty():
			if bound.has(officer.army_id) or not data.armies.get(officer.army_id) is Dictionary:return "A commander may lead only one living formation."
			var army: Dictionary=data.armies[officer.army_id]
			if not _integer_at_least(army.get("troops"),1) or army.get("faction")!=Officers.DEFINITIONS[id].faction:return "Commander faction or living army binding is invalid."
			bound[officer.army_id]=id
		if not officer.reserved_army.is_empty():
			if reserved.has(officer.reserved_army) or not jobs.has(officer.reserved_army):return "Commander reservation has no unique recruitment job."
			var job: Dictionary=jobs[officer.reserved_army]
			if job.commander_id!=id or job.faction!=Officers.DEFINITIONS[id].faction:return "Commander recruitment authority is invalid."
			reserved[officer.reserved_army]=id
	if jobs.size()!=reserved.size():return "Every recruitment job needs its own available commander."
	for id in data.armies:
		var army=data.armies[id]
		if not army is Dictionary or army.get("unit_type") not in ["infantry","archers","cavalry","siege"] or not _integer_at_least(army.get("troops"),0):return "Only troop formations are supported; hero saves are not imported."
		var officer: String=bound.get(id,"")
		if army.troops>0 and officer.is_empty():return "A living formation is missing its commander."
		if army.get("commander_id")!=officer:return "Commander portrait identity differs from the formation."
		var lead: int=int(Officers.DEFINITIONS[officer].lead) if not officer.is_empty() else 50
		var strength: int=int(Officers.DEFINITIONS[officer].str) if not officer.is_empty() else 50
		if army.get("commander_lead")!=lead or army.get("commander_str")!=strength:return "Commander stats differ from the exact source catalog."
	for id in state.buffs:
		if not data.armies.has(id) or not state.buffs[id] is Dictionary:return "Commander buff target is invalid."
		for stat in state.buffs[id]:
			var buff=state.buffs[id][stat]
			if stat not in ["speed","attack","defense"] or not buff is Dictionary:return "Commander buff type is invalid."
			if not _integer_at_least(buff.get("percent"),100) or buff.percent>175 or not _integer_at_least(buff.get("until_tick"),int(data.tick)+1) or buff.until_tick>int(data.tick)+80:return "Commander buff strength or timer is invalid."
	if state.commands.size()>state.roster.size() or not data.get("command_ids") is Dictionary:return "Commander command registry is invalid."
	var queued: Dictionary={}
	for command in state.commands:
		if not command is Dictionary:return "Commander command is invalid."
		for field in ["command_id","faction","army_id","officer","target"]:
			if not command.get(field) is String:return "Commander command schema is invalid."
		if not state.roster.has(command.officer) or queued.has(command.officer):return "Commander has duplicate queued skills."
		if bound.get(command.army_id,"")!=command.officer or Officers.DEFINITIONS[command.officer].faction!=command.faction:return "Commander command authority is invalid."
		if command.command_id.is_empty() or not data.command_ids.has(command.command_id) or not _integer_at_least(command.get("issued_tick"),0) or command.issued_tick>data.tick:return "Commander command provenance is invalid."
		if Officers.DEFINITIONS[command.officer].effect in ["sweep","volley"] and not data.armies.has(command.target):return "Commander command target is invalid."
		queued[command.officer]=true
	return ""

func load_json(text: String) -> String:
	var parser:=JSON.new()
	if parser.parse(text)!=OK or not parser.data is Dictionary:return "Save file is not valid JSON."
	if _contains_fractional_number(parser.data):return "Commander save requires integer numeric state."
	var data: Dictionary=_integer_data(parser.data)
	return _load_commander_data(data)

func _load_commander_data(data: Dictionary, trusted_world: bool=false) -> String:
	if data.get("format_version")!=COMMANDER_FORMAT:return "This units-only campaign uses save format 8. Older hero saves remain separate."
	if data.has("hero_state") or data.has("officer_state"):return "Separate hero state is not supported."
	var error: String=_validate_commander_save(data)
	if not error.is_empty():return error
	var state: Dictionary=data.commander_state.duplicate(true)
	var proxy: Dictionary=data.duplicate();proxy.erase("commander_state");proxy.format_version=CAMPAIGN_FORMAT
	error=super._load_campaign_data(proxy,trusted_world)
	if not error.is_empty():return error
	officers=state.roster;buffs=state.buffs;skill_queue=state.commands
	_sync_commander_stats()
	return ""
