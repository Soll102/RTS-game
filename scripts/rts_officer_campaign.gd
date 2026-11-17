extends "res://scripts/rts_campaign_simulation.gd"
## Asset-independent officers. Every action and timer uses simulation ticks.
const Officers=preload("res://scripts/rts_officer_rules.gd")
const OFFICER_FORMAT=6
var officers: Dictionary={}
var skill_queue: Array=[]
var buffs: Dictionary={}

func configure(world: Dictionary, initial_armies: Array, initial_cities: Array, initial_seed: int=1) -> String:
	var error: String=super.configure(world,initial_armies,initial_cities,initial_seed)
	if not error.is_empty():return error
	officers=Officers.create_roster(armies);skill_queue.clear();buffs.clear()
	return ""

func officer_for(army_id: String) -> String:
	for id in officers:
		if officers[id].army_id==army_id and not officers[id].defeated:return id
	return ""

func assign_officer(faction: String, officer_id: String, army_id: String) -> String:
	if match_state=="finished":return "Campaign finished."
	if not officers.has(officer_id) or Officers.DEFINITIONS[officer_id].faction!=faction:return "Officer does not belong to this faction."
	if officers[officer_id].defeated:return "Officer was defeated in this campaign."
	if not armies.has(army_id) or armies[army_id].faction!=faction or armies[army_id].troops<=0:return "Choose a living friendly formation."
	if not officer_for(army_id).is_empty() and officer_for(army_id)!=officer_id:return "This formation already has an officer."
	if not officers[officer_id].army_id.is_empty() and officers[officer_id].army_id!=army_id:return "Officer already commands another formation."
	if armies[army_id].routed or armies[army_id].transport_elapsed>0:return "Formation is unavailable for officer assignment."
	officers[officer_id].army_id=army_id;_emit("officer_assigned",{"army":army_id,"officer":officer_id})
	return ""

func skill_remaining_ticks(officer_id: String) -> int:
	return maxi(0,int(officers.get(officer_id,{}).get("cooldown_until",0))-tick)

func submit_skill(faction: String, army_id: String, target_id: String, command_id: String) -> String:
	if command_id.is_empty() or command_ids.has(command_id):return "Command ID is missing or already used."
	if match_state=="finished":return "Campaign finished."
	var hero: String=officer_for(army_id)
	if hero.is_empty() or not armies.has(army_id) or armies[army_id].faction!=faction:return "Select a friendly formation with an officer."
	if armies[army_id].troops<=0 or armies[army_id].routed or armies[army_id].transport_elapsed>0:return "Officer cannot act while defeated, routing or aboard a ferry."
	if skill_remaining_ticks(hero)>0:return "Skill is on cooldown."
	for order in skill_queue:
		if order.officer==hero:return "This officer already has a queued skill."
	var command: Dictionary={"command_id":command_id,"faction":faction,"army_id":army_id,"officer":hero,"target":target_id,"issued_tick":tick}
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
	_expire_buffs()
	for hero in officers:
		var state: Dictionary=officers[hero]
		if state.army_id.is_empty() or not armies.has(state.army_id):continue
		var army: Dictionary=armies[state.army_id]
		if army.troops<=0:state.defeated=true;continue
		if army.faction not in ai_factions or (tick-1)%CampaignAI.DECISION_INTERVAL_TICKS!=0 or skill_remaining_ticks(hero)>0:continue
		var target: String="";var nearest: float=INF
		for other in _sorted_ids(armies):
			if armies[other].faction==army.faction or armies[other].troops<=0:continue
			var distance: float=_point(armies[other]).distance_to(_point(army))
			if distance<nearest:nearest=distance;target=other
		if nearest<=120:submit_skill(army.faction,state.army_id,target,"hero-ai-%s-%d"%[hero,tick])
	var damage: Dictionary={}
	for command in skill_queue:
		var state: Dictionary=officers[command.officer];var army: Dictionary=armies[command.army_id]
		if state.defeated or state.army_id!=command.army_id or army.troops<=0 or army.routed or army.transport_elapsed>0 or skill_remaining_ticks(command.officer)>0:continue
		var targets: Array=_skill_targets(command)
		if targets.is_empty():_emit("skill_failed",{"officer":command.officer,"reason":"Target unavailable."});continue
		var definition: Dictionary=Officers.DEFINITIONS[command.officer]
		for id in targets:
			match definition.effect:
				"sweep","volley":damage[id]=int(damage.get(id,0))+int(definition.power)
				"roar":armies[id].morale=maxi(0,int(armies[id].morale)-int(definition.power))
				"rally":armies[id].morale=mini(100,int(armies[id].morale)+int(definition.power))
				"defense_aura":_add_buff(id,"defense",definition.power,definition.duration)
				_:_add_buff(id,definition.effect,definition.power,definition.duration)
		state.cooldown_until=tick+int(definition.cooldown)
		_emit("hero_skill",{"officer":command.officer,"army":command.army_id,"skill":definition.skill,"targets":targets})
	skill_queue.clear();_apply_damage(damage,"hero_skill");super._apply_commands()

func _move_armies() -> void:
	var original: Dictionary={}
	for id in armies:
		original[id]=armies[id].movement_per_tick
		armies[id].movement_per_tick=maxi(1,int(original[id])*buff_percent(id,"speed")/100)
	super._move_armies()
	for id in original:armies[id].movement_per_tick=original[id]

func _resolve_battles() -> void:
	# Apply an attack modifier once to the aggregate army, not once per model.
	var original: Dictionary={}
	for id in armies:
		original[id]=armies[id].attack
		armies[id].attack=maxi(1,int(original[id])*buff_percent(id,"attack")/100)
	super._resolve_battles()
	for id in original:armies[id].attack=original[id]

func _apply_damage(damage: Dictionary, reason: String) -> void:
	var adjusted: Dictionary=damage.duplicate()
	if reason in ["battle","garrison","hero_skill"]:
		for id in adjusted:adjusted[id]=maxi(1,int(adjusted[id])*100/buff_percent(id,"defense")) if adjusted[id]>0 else 0
	super._apply_damage(adjusted,reason)
	for state in officers.values():
		if not state.army_id.is_empty() and armies.has(state.army_id) and armies[state.army_id].troops<=0:state.defeated=true
func snapshot() -> Dictionary:
	var data: Dictionary=super.snapshot()
	data.format_version=OFFICER_FORMAT
	data["officer_state"]={"revision":Officers.REVISION,"roster":officers.duplicate(true),"buffs":buffs.duplicate(true),"commands":skill_queue.duplicate(true)}
	return data

func load_json(text: String) -> String:
	var parser:=JSON.new()
	if parser.parse(text)!=OK or not parser.data is Dictionary:return "Save file is not valid JSON."
	var data: Dictionary=parser.data
	if data.get("format_version")==CAMPAIGN_FORMAT:
		var migrated: String=super.load_json(text)
		if not migrated.is_empty():return migrated
		officers=Officers.create_roster(armies);buffs.clear();skill_queue.clear()
		for state in officers.values():
			if not state.army_id.is_empty() and armies[state.army_id].troops<=0:state.defeated=true
		return ""
	if data.get("format_version")!=OFFICER_FORMAT or not data.get("officer_state") is Dictionary:return "Officer campaign save format is unsupported."
	var state: Dictionary=data.officer_state
	if state.get("revision")!=Officers.REVISION or not state.get("roster") is Dictionary or not state.get("buffs") is Dictionary or not state.get("commands") is Array:return "Officer save state is invalid."
	if not data.get("armies") is Dictionary or not _integer_at_least(data.get("tick"),0):return "Officer save armies or tick are invalid."
	if not data.get("command_ids") is Dictionary:return "Officer command ID registry is invalid."
	if state.roster.size()!=Officers.DEFINITIONS.size():return "Officer save roster is incomplete."
	var bound: Dictionary={}
	for id in state.roster:
		if not Officers.DEFINITIONS.has(id) or not state.roster[id] is Dictionary:return "Unknown officer in save."
		var hero: Dictionary=state.roster[id]
		if not hero.get("army_id") is String or not hero.get("defeated") is bool or not _integer_at_least(hero.get("cooldown_until"),0):return "Officer save timer or assignment is invalid."
		if hero.cooldown_until>int(data.tick)+int(Officers.DEFINITIONS[id].cooldown):return "Officer save cooldown exceeds its definition."
		if hero.army_id.is_empty():
			if hero.defeated:return "Unassigned officer cannot be defeated."
			continue
		if bound.has(hero.army_id) or not data.armies.has(hero.army_id) or not data.armies[hero.army_id] is Dictionary:return "Officer save army binding is invalid."
		var army: Dictionary=data.armies[hero.army_id]
		if army.get("faction")!=Officers.DEFINITIONS[id].faction or not _integer_at_least(army.get("troops"),0):return "Officer is bound to a different faction."
		if hero.defeated!=(army.troops<=0):return "Officer defeat state does not match the army."
		bound[hero.army_id]=id
	for id in state.buffs:
		if not data.armies.has(id) or not state.buffs[id] is Dictionary:return "Officer buff target is invalid."
		for stat in state.buffs[id]:
			var buff=state.buffs[id][stat]
			if stat not in ["speed","attack","defense"] or not buff is Dictionary:return "Officer buff type is invalid."
			if not _integer_at_least(buff.get("percent"),100) or buff.percent>150 or not _integer_at_least(buff.get("until_tick"),int(data.tick)+1) or buff.until_tick>int(data.tick)+80:return "Officer buff timer or strength is invalid."
	if state.commands.size()>Officers.DEFINITIONS.size():return "Too many queued officer commands."
	var queued: Dictionary={}
	for command in state.commands:
		if not command is Dictionary:return "Officer command is invalid."
		for field in ["command_id","faction","army_id","officer","target"]:
			if not command.get(field) is String:return "Officer command schema is invalid."
		if not state.roster.has(command.officer) or queued.has(command.officer):return "Officer command identity is invalid."
		if state.roster[command.officer].army_id!=command.army_id or Officers.DEFINITIONS[command.officer].faction!=command.faction:return "Officer command authority is invalid."
		if command.command_id.is_empty() or not data.get("command_ids",{}).has(command.command_id) or not _integer_at_least(command.get("issued_tick"),0) or command.issued_tick>data.tick:return "Officer command provenance is invalid."
		if Officers.DEFINITIONS[command.officer].effect in ["sweep","volley"] and not data.armies.has(command.target):return "Officer command target is invalid."
		queued[command.officer]=true
	var proxy: Dictionary=data.duplicate(true);proxy.format_version=CAMPAIGN_FORMAT;proxy.erase("officer_state")
	var error: String=super.load_json(JSON.stringify(proxy))
	if not error.is_empty():return error
	var canonical: Dictionary=_integer_data(state)
	officers=canonical.roster;buffs=canonical.buffs;skill_queue=canonical.commands
	return ""
func _defeat(army: Dictionary, reason: String) -> void:
	super._defeat(army,reason)
	for state in officers.values():
		if state.army_id==army.id:state.defeated=true
