extends RefCounted
## Campaign actions and file lifecycle, independent of any visual or HUD asset.
const Scenario = preload("res://scripts/v8_scenario.gd")
const Store = preload("res://scripts/rts_save_store.gd")
const Simulation = preload("res://scripts/rts_officer_campaign.gd")
var simulation: RefCounted
var controller: Node3D
var faction: String = "wei"
var save_directory: String = "user://campaign-saves"
var selected_city: String = ""
var last_autosave_tick: int = 0
var autosave_interval_ticks: int = 1800
var recruitment_sequence: int = 0
var message: String = ""
var message_is_error: bool = false

func configure(sim: RefCounted, controls: Node3D, player: String) -> String:
	if player not in ["wei","shu","wu"] or sim == null or controls == null: return "Invalid campaign setup."
	simulation=sim; controller=controls; faction=player
	controller.player_faction=player
	selected_city=""; message=""; message_is_error=false
	recruitment_sequence=0
	last_autosave_tick=sim.tick
	if not controller.city_selection_changed.is_connected(_select_city): controller.city_selection_changed.connect(_select_city)
	if not controller.selection_changed.is_connected(_select_armies): controller.selection_changed.connect(_select_armies)
	return ""

func _select_armies(_ids: Array) -> void:
	selected_city=""

func _select_city(id: String) -> void:
	selected_city=id

func recruit(kind: String, troops: int = 500) -> String:
	if selected_city.is_empty(): return _report("Select a friendly city first.")
	recruitment_sequence+=1
	var id: String = "%s-player-%d-%d"%[faction,simulation.tick,recruitment_sequence]
	while _army_id_exists(id):
		recruitment_sequence+=1; id="%s-player-%d-%d"%[faction,simulation.tick,recruitment_sequence]
	return _report(simulation.queue_recruitment(faction,selected_city,id,troops,kind))

func _army_id_exists(id: String) -> bool:
	if simulation.armies.has(id): return true
	for city in simulation.cities.values():
		for job in city.production_queue:
			if job.army_id==id: return true
	return false

func save(slot: int = 1, paused_override = null) -> String:
	var original_pause: bool=simulation.paused
	if paused_override is bool and simulation.match_state!="finished": simulation.paused=paused_override
	var error: String=Store.save_slot(simulation,save_directory,slot)
	simulation.paused=original_pause
	if error.is_empty(): message="Campaign saved."
	else: message=error
	message_is_error=not error.is_empty()
	return error

func load_slot(slot: int = 1) -> String:
	# Determine player authority before changing the live match. The sole
	# campaign always saves exactly two AI factions and one human faction.
	var candidate=Simulation.new()
	var error: String=Store.load_slot(candidate,save_directory,slot)
	var players: Array=[]
	if error.is_empty():
		for player in Scenario.FACTIONS:
			if player not in candidate.ai_factions: players.append(player)
		if candidate.ai_factions.size()!=2 or players.size()!=1:
			error="Save does not identify one player and two opposing factions."
	if error.is_empty(): error=simulation.load_json(candidate.save_json())
	if error.is_empty():
		faction=players[0];controller.player_faction=faction
		controller.select_armies([]); selected_city=""; controller.control_groups.clear()
		controller._dragging=false;controller._time_fraction_us=0.0
		controller._previous_positions=controller._current_positions()
		last_autosave_tick=simulation.tick; message="Campaign loaded."
	else: message=error
	message_is_error=not error.is_empty()
	return error

func poll_autosave() -> void:
	if simulation == null or simulation.paused or simulation.match_state == "finished": return
	if simulation.tick-last_autosave_tick < autosave_interval_ticks: return
	last_autosave_tick=simulation.tick
	var error: String=Store.save_slot(simulation,save_directory,0)
	if not error.is_empty(): message=error;message_is_error=true

func continue_campaign() -> void:
	simulation.continue_campaign()

func summary() -> Dictionary:
	var cities: int=0; var villages: int=0; var food: int=0; var troops: int=0; var count: int=0
	for city in simulation.cities.values():
		if city.owner!=faction: continue
		food+=city.food
		if city.victory_point: cities+=1
		else: villages+=1
	for army in simulation.armies.values():
		if army.faction==faction and army.troops>0: troops+=army.troops;count+=1
	return {"faction":faction,"cities":cities,"villages":villages,"food":food,"troops":troops,"armies":count,
		"tick":simulation.tick,"paused":simulation.paused,"speed":simulation.speed,"match_state":simulation.match_state,"winner":simulation.winner}

func _report(error: String) -> String:
	message=error
	message_is_error=not error.is_empty()
	return error
