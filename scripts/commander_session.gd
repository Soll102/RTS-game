extends "res://scripts/rts_campaign_session.gd"
const CommanderSimulation=preload("res://scripts/battle_campaign.gd")

func recruit_for_commander(kind: String, officer_id: String, troops: int=500) -> String:
	if selected_city.is_empty():return _report("Select a friendly city first.")
	recruitment_sequence+=1
	var id: String="%s-player-%d-%d"%[faction,simulation.tick,recruitment_sequence]
	while _army_id_exists(id):
		recruitment_sequence+=1;id="%s-player-%d-%d"%[faction,simulation.tick,recruitment_sequence]
	return _report(simulation.recruit_with_commander(faction,selected_city,id,officer_id,troops,kind))

func recruit(_kind: String, _troops: int=500) -> String:
	return _report("Choose an available commander before recruiting.")

func load_slot(slot: int=1) -> String:
	var candidate=CommanderSimulation.new()
	candidate.navigation_warmup=false
	var error: String=Store.load_slot(candidate,save_directory,slot)
	var players: Array=[]
	if error.is_empty():
		for player in ["wei","shu","wu"]:
			if player not in candidate.ai_factions:players.append(player)
		if candidate.ai_factions.size()!=2 or players.size()!=1:error="Save must identify one player and two opposing factions."
	if error.is_empty():error=simulation.load_json(candidate.save_json())
	if error.is_empty():
		faction=players[0];controller.player_faction=faction
		controller.select_armies([]);selected_city="";controller.control_groups.clear()
		controller._dragging=false;controller._time_fraction_us=0.0;controller.reset_interpolation();controller.accepted_order.clear()
		last_autosave_tick=simulation.tick;message="Campaign loaded."
	else:message=error
	message_is_error=not error.is_empty()
	return error
