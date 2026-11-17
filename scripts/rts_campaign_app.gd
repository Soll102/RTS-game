extends RefCounted
## Single-map application lifecycle. No UI, scene or visual asset is created.
const Scenario=preload("res://scripts/commander_scenario.gd")
const Session=preload("res://scripts/commander_session.gd")
const Store=preload("res://scripts/rts_save_store.gd")
const Officers=preload("res://scripts/rts_commander_rules.gd")
var session: RefCounted
var controller: Node3D
var screen: String="menu"
var resume_paused: bool=true
var campaign_started: bool=false
var result: String=""
var difficulty: String="standard"
var show_supply: bool=false
var show_labels: bool=true
var panel_history: Array=[]
var _last_poll_tick: int=-1

func configure(sim: RefCounted, controls: Node3D) -> String:
	controller=controls; session=Session.new()
	var error: String=session.configure(sim,controls,"wei")
	if error.is_empty(): sim.paused=true; controller.controls_enabled=false; controller.set_process(false)
	return error

func start_campaign(faction: String, challenge: String="standard") -> String:
	if faction not in ["wei","shu","wu"]: return "Choose Wei, Shu or Wu."
	if challenge not in ["standard","relaxed"]: return "Choose a campaign difficulty."
	var candidate=Scenario.create(faction)
	if candidate==null: return "Choose Wei, Shu or Wu."
	if challenge=="relaxed":
		for city in candidate.cities.values():
			if city.owner==faction: city.food=mini(city.food_cap,city.food+2500000)
	var error: String=session.simulation.load_json(candidate.save_json())
	if not error.is_empty(): return error
	error=session.configure(session.simulation,controller,faction)
	if not error.is_empty(): return error
	controller.select_armies([]); controller.control_groups.clear()
	controller._time_fraction_us=0.0;controller.reset_interpolation();controller.accepted_order.clear()
	difficulty=challenge; campaign_started=true; result=""; screen="campaign"
	resume_paused=false;session.simulation.paused=false
	panel_history.clear()
	_set_controls(true); _last_poll_tick=-1
	return ""

func restart_campaign() -> String:
	if not campaign_started:return "Start a campaign before restarting."
	return start_campaign(session.faction,difficulty)

func open_panel(next: String) -> void:
	if next not in ["menu","faction","pause","load","save","settings","help","stats","restart"]: return
	if screen=="campaign": resume_paused=session.simulation.paused
	if screen!=next: panel_history.append(screen)
	session.simulation.paused=true;screen=next;_set_controls(false)
	controller._dragging=false

func back() -> void:
	var previous: String=str(panel_history.pop_back()) if not panel_history.is_empty() else "menu"
	if previous=="campaign" and campaign_started: resume();return
	screen=previous;_set_controls(false)

func resume() -> void:
	if not campaign_started: return
	panel_history.clear()
	screen="campaign";session.simulation.paused=resume_paused
	_set_controls(true)

func load_campaign(slot: int) -> String:
	var error: String=session.load_slot(slot)
	if not error.is_empty(): return error
	campaign_started=true;result="";screen="campaign";_last_poll_tick=-1
	panel_history.clear()
	resume_paused=session.simulation.paused;_set_controls(true)
	if session.simulation.match_state=="finished": poll()
	return ""

func save_campaign(slot: int) -> String:
	if not campaign_started: return "Start a campaign before saving."
	if screen!="campaign":return session.save(slot,resume_paused)
	return session.save(slot)

func poll() -> void:
	if screen!="campaign": return
	var sim=session.simulation
	controller._prune_selection()
	if sim.match_state=="finished":
		result="victory" if sim.winner==session.faction else "defeat"
		screen="result";_set_controls(false);return
	if sim.tick==_last_poll_tick: return
	_last_poll_tick=sim.tick
	var holdings: int=0;var living: int=0;var queued: int=0
	for city in sim.cities.values():
		if city.owner==session.faction: holdings+=1;queued+=city.production_queue.size()
	for army in sim.armies.values():
		if army.faction==session.faction and army.troops>0: living+=1
	if sim.faction_troops(session.faction)==0 and holdings==0 and queued==0:
		result="defeat";screen="result";sim.paused=true;_set_controls(false);return
	session.poll_autosave()

func continue_campaign() -> void:
	if result!="victory": return
	session.continue_campaign();screen="campaign";result="";_set_controls(true)

func _set_controls(enabled: bool) -> void:
	controller.controls_enabled=enabled;controller.set_process(enabled)

func settlement_name(id: String) -> String:
	var names: Dictionary={"C1":"Central City","C2":"West City","C3":"East City","C4":"Northwest City","C5":"Inland City","C6":"Eastward City","C7":"North City","C8":"Pass City","V1":"West Village","V2":"Ford Village","V3":"Meadow Village"}
	for item in session.simulation.world_metadata.settlements:
		if item.id==id: return str(item.get("name",names.get(id,id)))
	return id

func _army_label(id: String) -> String:
	if id.is_empty() or session==null or session.simulation==null: return id
	var profile: Dictionary=session.simulation.commander_profile(id)
	if not profile.is_empty() and profile.has("name"): return str(profile.name)
	return id

func _occupant_label(raw: String) -> String:
	if raw.begins_with("army:"): return _army_label(raw.substr(5))
	if raw.begins_with("cargo:"): return "Supply convoy "+raw.substr(6)
	return _army_label(raw)

func recent_events(limit: int=8) -> Array:
	var lines: Array=[]
	var events: Array=session.simulation.events
	for index in range(events.size()-1,-1,-1):
		var event: Dictionary=events[index]
		var detail: Dictionary=event
		var text: String=""
		match str(event.get("type",event.get("kind",""))):
			"city_captured": text="%s captured by %s"%[settlement_name(detail.get("city","")),str(detail.get("new_owner","")).capitalize()]
			"army_defeated": text="%s was defeated"%_army_label(str(detail.get("army","")))
			"army_recruited": text="New formation ready at %s"%settlement_name(detail.get("city",""))
			"army_rallied": text="%s rallied"%_army_label(str(detail.get("army","")))
			"army_routed": text="%s is retreating"%_army_label(str(detail.get("army","")))
			"victory": text="%s unified the region"%str(detail.get("faction","")).capitalize()
			"commander_skill": text="%s used %s"%[Officers.DEFINITIONS.get(detail.get("officer",""),{}).get("name","Officer"),detail.get("skill","Skill")]
			"ferry_queued": text="%s queued for river crossing (%s)"%[_army_label(str(detail.get("army",""))),str(detail.get("ferry","ferry"))]
			"boat_repositioning": text="Boat %s approaching %s (%s)"%[str(detail.get("boat","ferry")),_occupant_label(str(detail.get("occupant",""))),str(detail.get("ferry","ferry"))]
			"ferry_departed": text="%s boarded %s across %s"%[_occupant_label(str(detail.get("occupant",""))),str(detail.get("boat","ferry")),str(detail.get("ferry","river"))]
			"ferry_arrived": text="%s landed across %s (%s)"%[_army_label(str(detail.get("army",""))),str(detail.get("ferry","river")),str(detail.get("boat","ferry"))]
		if text.is_empty(): continue
		lines.append({"tick":event.get("tick",0),"text":text})
		if lines.size()>=limit: break
	return lines
