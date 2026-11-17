extends "res://campaign_ui.gd"
## Functional review controls; decorative textures remain the exact classic HUD art.

var management_button: Button
var management_dialog: AcceptDialog
var management_feedback: Label
var management_resources: Label
var management_residents: OptionButton
var management_training: OptionButton
var management_transfers: OptionButton
var _management_body: VBoxContainer
var _management_scroll: ScrollContainer
var _management_city: String=""
var _management_army: String=""
var _management_pause_before: bool=true
var _management_sim: RefCounted
var recruit_amount: OptionButton
var _last_battle_tick: int=-1
var _last_battle_sig: String=""

func _recruit_count() -> int:
	return int(recruit_amount.get_item_metadata(recruit_amount.selected)) if is_instance_valid(recruit_amount) else 100

func _whole(value: int) -> int:
	return int(value/1000)

func _gold(faction_id: String) -> int:
	return _whole(int(map.simulation.faction_gold.get(faction_id,0)))

func update_view(delta: float) -> void:
	var prev_tick: int=_last_hud_tick;var prev_sig: String=_last_hud_signature
	super.update_view(delta)
	if app==null or app.screen!="campaign":return
	if _last_hud_tick==prev_tick and _last_hud_signature==prev_sig and _last_battle_tick==_last_hud_tick and _last_battle_sig==_last_hud_signature:return
	_last_battle_tick=_last_hud_tick;_last_battle_sig=_last_hud_signature
	var sim=map.simulation
	var data: Dictionary=app.session.summary()
	var reserves: int=0
	for city in sim.cities.values():
		if city.owner==app.session.faction:reserves+=int(city.get("recruits",0))
	summary.text="%s  |  Food %d  |  Gold %d  |  Cities %d/8"%[data.faction.capitalize(),_whole(int(data.food)),_gold(data.faction),data.cities]
	summary.tooltip_text="Recruits %d | Enemy troops %d | Time %02d:%02d\n%s"%[reserves,sim.enemy_troops(data.faction),data.tick/600,(data.tick/10)%60,log_label.text]
	_objective.text="Capture all 8 cities and defeat every enemy troop."
	if is_instance_valid(management_dialog) and management_dialog.visible:_refresh_management()

func _build_city_dock() -> void:
	super._build_city_dock()
	var commands: VBoxContainer=_command_shell.get_child(0)
	var choice_row:=HBoxContainer.new();choice_row.add_theme_constant_override("separation",5);commands.add_child(choice_row)
	recruit_commander_picker.reparent(choice_row);recruit_commander_picker.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	recruit_amount=OptionButton.new();recruit_amount.name="RecruitTroopCount";recruit_amount.add_theme_font_size_override("font_size",12);recruit_amount.custom_minimum_size=Vector2(82,26)
	choice_row.add_child(recruit_amount)
	_prepare_picker(recruit_amount)
	for amount in ([100,200,300] if map.simulation.traditional_rts else [500,1000,1500,3000]):
		recruit_amount.add_item(str(amount));recruit_amount.set_item_metadata(recruit_amount.item_count-1,amount)
	recruit_amount.tooltip_text="Troops in the new formation. Food, Gold, Recruits and city capacity use this amount."
	recruit_amount.item_selected.connect(func(_index):_update_city(map.controller.selected_city))
	commands.move_child(choice_row,1)
	management_button=_button("City management",func():open_city_management(map.controller.selected_city),commands)
	management_button.name="CityManagementButton"
	management_button.custom_minimum_size.y=24
	management_button.add_theme_font_size_override("font_size",12)

func _recruit_city(kind: String) -> void:
	if not _city_context_active():return
	_update_city(map.controller.selected_city)
	var button: Button=_city_buttons[kind]
	if button.disabled:message(button.get_meta("blocked_reason","Recruitment unavailable."),true);return
	var count: int=_recruit_count();var chosen: String=_refresh_recruit_commander()
	var error: String=app.session.recruit_for_commander(kind,chosen,count)
	message(error,not error.is_empty(),kind.capitalize()+" queued | %d troops."%count);_last_hud_tick=-1;update_view(1)

func _build_commander_controls(parent: VBoxContainer) -> void:
	super._build_commander_controls(parent)
	var row: HBoxContainer=parent.get_child(parent.get_child_count()-1)
	management_button=_button("Garrison",func():open_army_management(_active_army),row,80)
	management_button.name="FormationManagementButton"
	management_button.custom_minimum_size.y=24
	management_button.add_theme_font_size_override("font_size",12)

func _update_city(id: String) -> void:
	var sim=map.simulation
	if not sim.cities.has(id):return
	var city: Dictionary=sim.cities[id]
	var under_siege: bool=sim._city_under_siege(city)
	_heading_label.text=app.settlement_name(id)
	var phase_text: String=" | "+sim.Tactical.city_phase(city)+" (22m)" if sim.tactical_rts and city.kind=="city" else ""
	_meta_label.text="%s · %s%s   |   Recruits %d/%d · Residents %d/2"%[city.owner.capitalize(),"Under siege" if under_siege else "City" if city.victory_point else "Village",phase_text,int(city.get("recruits",0)),int(city.get("recruits_cap",0)),sim.resident_ids(id).size()]
	_stats.Garrison.text=str(city.garrison)
	_stats.Walls.text="%d/%d"%[city.wall_hp,int(city.get("wall_max",1200 if city.victory_point else 0))]
	_stats.Food.text=str(_whole(int(city.food)))
	_stats["City HP"].text="%d/%d"%[int(city.get("city_hp",0)),int(city.get("city_hp_max",0))]
	_stats["City Morale"].text=str(int(city.get("city_morale",0)))
	var chosen: String=_refresh_recruit_commander()
	var forces: int=app.session.summary().armies+_queued_armies()
	var occupied: int=sim.city_capacity(id)
	var limit: int=int(city.get("people_capacity",10000 if city.victory_point else 100))
	_capacity_label.text="Squads %d/%d | Training %d/3"%[forces,sim.formation_limit(),city.production_queue.size()]
	var capacity: Dictionary=sim.capacity_breakdown(id)
	_capacity_label.tooltip_text="Guards %d | Resident troops %d | Incoming %d\nTraining reserved %d | Reinforcement reserved %d\nTotal %d/%d"%[capacity.guards,capacity.residents,capacity.incoming,capacity.training,capacity.reinforcement,capacity.total,limit]
	var count: int=_recruit_count()
	for kind in _city_buttons:
		var p: Dictionary=sim.PROFILES[kind]
		var food_cost: int=int(p.cost)*count
		var gold_cost: int=int(sim.GOLD_COST[kind])*count/500
		var reason: String=""
		if city.owner!=app.session.faction:reason="Select a friendly city."
		elif not city.recruitment_enabled:reason="Villages cannot recruit."
		elif sim.salary_arrears(app.session.faction)>=300:reason="Recruitment is suspended until overdue faction salaries are paid."
		elif city.production_queue.size()>=3:reason="Training queue is full."
		elif forces>=sim.formation_limit():reason="Squad limit reached."
		elif occupied+count>limit:reason="Not enough city capacity for %d troops."%count
		elif chosen.is_empty():reason="Choose an available commander first."
		elif city.food<food_cost*1000:reason="Not enough city food."
		elif int(sim.faction_gold.get(app.session.faction,0))<gold_cost*1000:reason="Not enough gold."
		elif int(city.get("recruits",0))<count:reason="Not enough recruits."
		var button: Button=_city_buttons[kind]
		button.text="[%s] %s\n%dF %dG | %ds"%[CITY_KEY_LABELS[kind],kind.capitalize(),food_cost,gold_cost,sim.recruitment_ticks(kind)/10]
		button.disabled=not reason.is_empty()
		button.set_meta("blocked_reason",reason)
		button.tooltip_text="%d troops: %d Food, %d Gold, %d Recruits. %s"%[count,food_cost,gold_cost,count,reason if not reason.is_empty() else "Reserve the selected commander and city capacity."]
	if is_instance_valid(management_button):
		management_button.disabled=city.owner!=app.session.faction
		management_button.tooltip_text="Reinforce guards, repair walls, transfer food, manage residents or cancel training."
	if city.production_queue.is_empty():
		queue_label.text="No units in training."
		_training_label.text="%d recruits per formation"%count
	else:
		var job: Dictionary=city.production_queue[0]
		var commander: String=str(job.get("commander_id",""))
		var name: String=sim.Officers.DEFINITIONS[commander].name if sim.Officers.DEFINITIONS.has(commander) else "Commander"
		queue_label.text=name+" | "+str(job.unit_type).capitalize()
		_training_label.text="%ds remaining | %d waiting"%[ceili(int(job.remaining_ticks)/10.0),city.production_queue.size()-1]

func _update_army(ids: Array) -> void:
	super._update_army(ids)
	var sim=map.simulation
	var least: int=2147483647
	for id in ids:least=mini(least,sim.rations_seconds(id))
	_stats.Food.text="%ds"%least
	_stats.Food.tooltip_text="Remaining carried rations at current troop strength. For groups, the shortest reserve is shown. Food is transferred from a real friendly stockpile."
	var food_cell: Node=_stats.Food.get_parent()
	if food_cell.get_child_count()>0 and food_cell.get_child(0) is Label:food_cell.get_child(0).text="RATIONS"
	var army: Dictionary=sim.armies[ids[0]]
	var resident: String=str(army.get("resident_city",""))
	if not resident.is_empty():_meta_label.text=army.faction.capitalize()+" | Garrisoned at "+app.settlement_name(resident)
	elif int(army.get("transport_elapsed",0))>0:
		var boat_id: String=""
		var boat: Dictionary={}
		for v in sim.vessels.values():
			if str(v.get("request",""))=="army:"+army.id:boat_id=str(v.get("id",""));boat=v;break
		var total_s: int=maxi(1,ceili(float(boat.get("duration",50))/10.0))
		var elapsed_s: int=clampi(ceili(float(army.get("transport_elapsed",0))/10.0),1,total_s)
		_meta_label.text="%s | On %s (%d/%ds)"%[army.faction.capitalize(),boat_id if not boat_id.is_empty() else str(army.get("transport_id","boat")),elapsed_s,total_s]
	elif not str(army.get("transport_id","")).is_empty():
		var boat_id: String=""
		var boat: Dictionary={}
		for v in sim.vessels.values():
			if str(v.get("request",""))=="army:"+army.id:boat_id=str(v.get("id",""));boat=v;break
		if not boat.is_empty() and str(boat.get("phase",""))=="reposition":
			var total_s: int=maxi(1,ceili(float(boat.get("duration",30))/10.0))
			var elapsed_s: int=clampi(ceili(float(boat.get("elapsed",0))/10.0),1,total_s)
			_meta_label.text="%s | Boat %s approaching (%d/%ds)"%[army.faction.capitalize(),boat_id,elapsed_s,total_s]
		else:
			_meta_label.text="%s | Waiting for boat (%s)"%[army.faction.capitalize(),str(army.get("transport_id","ferry"))]
	for job in sim.pending_windups:
		if job.source==army.id and job.kind=="army":_meta_label.text=army.faction.capitalize()+" | Preparing volley"
	if is_instance_valid(management_button):
		management_button.disabled=ids.size()!=1
		management_button.text="Manage"
		management_button.tooltip_text="Enter a friendly city, sortie, reinforce or disband this formation."

func _refresh_commander_controls(ids: Array) -> void:
	super._refresh_commander_controls(ids)
	var has_resident: bool=false
	for id in ids:
		if not map.simulation.armies[id].get("resident_city","").is_empty():has_resident=true
	if has_resident:
		for key in ["move","attack","hold","retreat"]:
			_command_buttons[key].disabled=true
			_command_buttons[key].tooltip_text="Use Manage > Sortie before giving field orders."

func _classic_command(key: String) -> void:
	for id in map.controller.selected_armies:
		if not map.simulation.armies[id].get("resident_city","").is_empty() and key in ["move","attack","hold","retreat"]:
			message("Sortie from the city before giving field orders.",true)
			return
	super._classic_command(key)

func _city_context_active() -> bool:
	return super._city_context_active() and not (is_instance_valid(management_dialog) and management_dialog.visible)

func _input(event: InputEvent) -> void:
	if is_instance_valid(management_dialog) and management_dialog.visible:return
	super._input(event)

func _layout() -> void:
	super._layout()
	if is_instance_valid(management_dialog) and management_dialog.visible:_fit_management()

func refresh_screen() -> void:
	if app!=null and app.screen!="campaign":_close_management(false)
	super.refresh_screen()
	if app!=null and app.screen in ["menu","help"]:_correct_objective_labels(modal)

func _correct_objective_labels(node: Node) -> void:
	if node is Label:
		node.text=node.text.replace("Command your forces. Secure the eight cities.","Capture every city and eliminate all enemy troops.").replace("Capture all eight cities to win.","Capture all eight cities and eliminate every enemy troop to win.")
	for child in node.get_children():_correct_objective_labels(child)

func _new_management(title: String) -> VBoxContainer:
	_close_management(true)
	_management_sim=map.simulation
	_management_pause_before=_management_sim.paused
	_management_sim.paused=true
	_cancel_target_mode()
	management_dialog=AcceptDialog.new()
	management_dialog.name="BattleManagementDialog"
	management_dialog.title=title
	management_dialog.theme=ClassicSkin.theme()
	management_dialog.exclusive=true
	management_dialog.min_size=Vector2i.ZERO
	management_dialog.size=Vector2i(540,450)
	management_dialog.get_ok_button().text="Close"
	root.add_child(management_dialog)
	management_dialog.confirmed.connect(func():_close_management(true))
	management_dialog.canceled.connect(func():_close_management(true))
	management_dialog.close_requested.connect(func():_close_management(true))
	_management_scroll=ScrollContainer.new()
	_management_scroll.name="ManagementScroll"
	_management_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	_management_scroll.custom_minimum_size=Vector2(496,350)
	management_dialog.add_child(_management_scroll)
	var body:=VBoxContainer.new()
	_management_body=body
	body.name="ManagementActions"
	body.add_theme_constant_override("separation",8)
	body.custom_minimum_size.x=minf(480,get_viewport().get_visible_rect().size.x-80)
	body.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_management_scroll.add_child(body)
	management_resources=_label("",14)
	management_resources.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	body.add_child(management_resources)
	management_feedback=_label("The battlefield is paused while this panel is open.",13,T.MUTED)
	management_feedback.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	body.add_child(management_feedback)
	return body

func _management_size() -> Vector2i:
	var visible: Vector2=get_viewport().get_visible_rect().size
	var physical: Vector2i=get_window().size
	var width: int=mini(int(visible.x),physical.x)
	var height: int=mini(int(visible.y),physical.y)
	var needed_height: int=450
	if is_instance_valid(_management_body):needed_height=maxi(450,ceili(_management_body.get_combined_minimum_size().y)+90)
	return Vector2i(mini(540,maxi(480,width-48)),mini(needed_height,maxi(300,height-70)))

func _fit_management() -> void:
	if not is_instance_valid(management_dialog):return
	var wanted: Vector2i=_management_size()
	if is_instance_valid(_management_body):_management_body.custom_minimum_size.x=wanted.x-60
	if is_instance_valid(_management_scroll):_management_scroll.custom_minimum_size=Vector2(wanted.x-44,wanted.y-90)
	if management_dialog.size!=wanted:management_dialog.size=wanted
	var logical_bounds: Vector2=get_viewport().get_visible_rect().size
	var physical_bounds: Vector2i=get_window().size
	var bounds:=Vector2(minf(logical_bounds.x,physical_bounds.x),minf(logical_bounds.y,physical_bounds.y))
	var max_position:=Vector2i(maxi(0,int(bounds.x)-management_dialog.size.x),maxi(0,int(bounds.y)-management_dialog.size.y))
	management_dialog.position=Vector2i(clampi(management_dialog.position.x,0,max_position.x),clampi(management_dialog.position.y,0,max_position.y))

func _popup_management() -> void:
	_fit_management()
	management_dialog.popup_centered(_management_size())
	call_deferred("_fit_management")

func _close_management(restore_pause: bool) -> void:
	if is_instance_valid(management_dialog):
		management_dialog.hide()
		management_dialog.queue_free()
	management_dialog=null
	if restore_pause and _management_sim!=null and app!=null and app.screen=="campaign" and _management_sim==map.simulation and _management_sim.match_state!="finished":_management_sim.paused=_management_pause_before
	_management_sim=null
	_management_city=""
	_management_army=""
	management_residents=null
	management_training=null
	management_transfers=null
	_management_body=null
	_management_scroll=null

func _picker_value(picker: OptionButton) -> String:
	return str(picker.get_item_metadata(picker.selected)) if is_instance_valid(picker) and picker.selected>=0 else ""

func _operation(action: Callable, success: String) -> void:
	var error: String=str(action.call())
	if is_instance_valid(management_feedback):
		management_feedback.text=success if error.is_empty() else error
		management_feedback.add_theme_color_override("font_color",T.SUCCESS if error.is_empty() else T.ERROR)
	message(error,not error.is_empty(),success)
	_refresh_management()
	update_view(1)

func _friendly_city_picker(parent: Node, excluded: String="", preferred: String="") -> OptionButton:
	var picker:=OptionButton.new()
	picker.custom_minimum_size=Vector2(240,32)
	parent.add_child(picker)
	for id in map.simulation._sorted_ids(map.simulation.cities):
		var city: Dictionary=map.simulation.cities[id]
		if city.owner!=app.session.faction or id==excluded:continue
		if not excluded.is_empty() or city.victory_point:
			picker.add_item(app.settlement_name(id))
			picker.set_item_metadata(picker.item_count-1,id)
			if id==preferred:picker.select(picker.item_count-1)
	if picker.item_count==0:
		picker.add_item("No friendly destination")
		picker.set_item_metadata(0,"")
		picker.disabled=true
	return picker

func open_city_management(city_id: String) -> void:
	var sim=map.simulation
	if not sim.cities.has(city_id) or sim.cities[city_id].owner!=app.session.faction:
		message("Select a friendly settlement first.",true)
		return
	var body: VBoxContainer=_new_management("City management | "+app.settlement_name(city_id))
	_management_city=city_id
	var actions:=HBoxContainer.new()
	body.add_child(actions)
	var guards:=_button("Guards +100",func():_operation(func():return sim.request_reinforce(app.session.faction,city_id,""),"Guard reinforcement queued."),actions)
	guards.name="ReinforceGuardsButton"
	guards.tooltip_text="100 Recruits + 100 Food + 50 Gold; 5 simulation seconds. Shared city capacity applies."
	var repair:=_button("Repair +100 HP",func():_operation(func():return sim.request_repair(app.session.faction,city_id),"Wall repair queued."),actions)
	repair.name="RepairWallsButton"
	repair.disabled=not sim.cities[city_id].victory_point
	repair.tooltip_text="40 Food + 20 Gold per 100 HP; 25 simulation seconds. Repair waits while the city is besieged."
	body.add_child(_label("Resident formations",13,T.MUTED))
	var residents:=HBoxContainer.new()
	body.add_child(residents)
	management_residents=OptionButton.new()
	management_residents.name="ResidentFormationPicker"
	management_residents.fit_to_longest_item=false
	management_residents.custom_minimum_size=Vector2(265,32)
	residents.add_child(management_residents)
	management_residents.item_selected.connect(func(_index):_refresh_management_buttons())
	_button("Sortie",func():_operation(func():return sim.request_sortie(app.session.faction,_picker_value(management_residents)),"Sortie queued."),residents).name="ResidentSortieButton"
	_button("Reinforce",func():_reinforce_resident(city_id),residents).name="ResidentReinforceButton"
	body.add_child(_label("Training queue",13,T.MUTED))
	var training:=HBoxContainer.new()
	body.add_child(training)
	management_training=OptionButton.new()
	management_training.name="TrainingQueuePicker"
	management_training.fit_to_longest_item=false
	management_training.custom_minimum_size=Vector2(330,32)
	training.add_child(management_training)
	management_training.item_selected.connect(func(_index):_refresh_management_buttons())
	var cancel:=_button("Cancel training",func():_cancel_selected_training(city_id),training)
	cancel.name="CancelTrainingButton"
	cancel.tooltip_text="Return recruits, 50% Food/Gold and release the reserved commander."
	body.add_child(_label("Transfer Food",13,T.MUTED))
	var transfer:=HBoxContainer.new()
	body.add_child(transfer)
	var destination: OptionButton=_friendly_city_picker(transfer,city_id)
	destination.name="FoodDestinationPicker"
	var amount:=SpinBox.new()
	amount.name="TransferFoodAmount"
	amount.min_value=100
	amount.max_value=5000
	amount.step=100
	amount.value=300
	amount.custom_minimum_size=Vector2(95,32)
	transfer.add_child(amount)
	_button("Transfer",func():_operation(func():return sim.request_transfer(app.session.faction,city_id,_picker_value(destination),int(amount.value)),"Food transfer dispatched."),transfer).name="TransferFoodButton"
	body.add_child(_label("Food transfers from this city",13,T.MUTED))
	var shipments:=HBoxContainer.new()
	body.add_child(shipments)
	management_transfers=OptionButton.new()
	management_transfers.name="FoodTransferPicker"
	management_transfers.fit_to_longest_item=false
	management_transfers.custom_minimum_size=Vector2(320,32)
	shipments.add_child(management_transfers)
	management_transfers.item_selected.connect(func(_index):_refresh_management_buttons())
	var cancel_transfer:=_button("Cancel reserved",func():_operation(func():return sim.cancel_transfer(app.session.faction,_picker_value(management_transfers)),"Reserved food transfer cancelled."),shipments)
	cancel_transfer.name="CancelFoodTransferButton"
	cancel_transfer.tooltip_text="Only a friendly transfer that has not departed can be cancelled. Its Food returns to the source warehouse."
	_refresh_management()
	_popup_management()

func _reinforce_resident(city_id: String) -> void:
	var id: String=_picker_value(management_residents)
	if id.is_empty():_operation(func():return "Choose a resident formation first.","");return
	_operation(func():return map.simulation.request_reinforce(app.session.faction,city_id,id),"Formation reinforcement queued.")

func _cancel_selected_training(city_id: String) -> void:
	var chosen: String=_picker_value(management_training)
	var sim=map.simulation
	if chosen.is_empty():_operation(func():return "Choose a training order first.","");return
	for index in range(sim.cities[city_id].production_queue.size()):
		if sim.cities[city_id].production_queue[index].army_id==chosen:
			_operation(func():return sim.cancel_training(app.session.faction,city_id,index),"Training cancelled; commander released.")
			return
	_operation(func():return "This training order is no longer available.","")

func open_army_management(army_id: String) -> void:
	var sim=map.simulation
	if not sim.armies.has(army_id) or sim.armies[army_id].troops<=0 or sim.armies[army_id].faction!=app.session.faction:
		message("Select a living friendly formation first.",true)
		return
	var body: VBoxContainer=_new_management("Formation management")
	_management_army=army_id
	var army: Dictionary=sim.armies[army_id]
	var current_city: String=str(army.get("resident_city",""))
	body.add_child(_label("Friendly city",13,T.MUTED))
	var destinations:=HBoxContainer.new()
	body.add_child(destinations)
	var destination: OptionButton=_friendly_city_picker(destinations,"",current_city)
	destination.name="GarrisonDestinationPicker"
	var enter:=_button("Garrison",func():_operation(func():return sim.request_garrison(app.session.faction,army_id,_picker_value(destination)),"City entry queued."),destinations)
	enter.name="EnterCityButton"
	enter.tooltip_text="Reach a friendly city gate and enter; the commander and formation slot remain reserved."
	var actions:=HBoxContainer.new()
	body.add_child(actions)
	_button("Sortie",func():_operation(func():return sim.request_sortie(app.session.faction,army_id),"Sortie queued."),actions).name="SortieFormationButton"
	_button("Reinforce +100",func():_operation(func():return sim.request_reinforce(app.session.faction,str(sim.armies.get(army_id,{}).get("resident_city","")),army_id),"Formation reinforcement queued."),actions).name="ReinforceFormationButton"
	_button("Disband",func():_operation(func():return sim.request_disband(app.session.faction,army_id),"Formation disbanded; commander released."),actions).name="DisbandFormationButton"
	var explanation:=_label("Reinforce and disband require a friendly city and no combat. Disband returns half the surviving troops as recruits and remaining carried food.",13,T.MUTED)
	explanation.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	explanation.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	body.add_child(explanation)
	_refresh_management()
	_popup_management()

func _refresh_management() -> void:
	if not is_instance_valid(management_dialog) or not is_instance_valid(management_resources):return
	var sim=map.simulation
	if not _management_city.is_empty() and sim.cities.has(_management_city):
		var city: Dictionary=sim.cities[_management_city]
		var capacity: Dictionary=sim.capacity_breakdown(_management_city)
		management_resources.text="%s | Walls %d/%d | Capacity %d/%d\nGuards %d | Residents %d | Incoming %d\nTraining %d | Reinforcement %d reserved\nFood %d | Gold %d | Recruits %d"%[app.settlement_name(_management_city),city.wall_hp,int(city.get("wall_max",0)),capacity.total,int(city.get("people_capacity",10000)),capacity.guards,capacity.residents,capacity.incoming,capacity.training,capacity.reinforcement,_whole(int(city.food)),_gold(app.session.faction),int(city.get("recruits",0))]
		_refresh_resident_picker()
		_refresh_training_picker()
		_refresh_transfer_picker()
	elif not _management_army.is_empty() and sim.armies.has(_management_army):
		var army: Dictionary=sim.armies[_management_army]
		var city: String=str(army.get("resident_city",""))
		management_resources.text="%s | Troops %d/%d | Rations %ds\n%s | Gold %d"%[str(army.unit_type).capitalize(),army.troops,int(army.get("original_troops",army.troops)),sim.rations_seconds(_management_army),"In the field" if city.is_empty() else "Garrisoned at "+app.settlement_name(city),_gold(app.session.faction)]
		if army.troops<=0:management_resources.text="Formation no longer active. Commander released."
	elif not _management_army.is_empty():management_resources.text="Formation no longer active. Commander released."
	_refresh_management_buttons()

func _set_management_disabled(name: String, disabled: bool) -> void:
	if not is_instance_valid(management_dialog):return
	var button:=management_dialog.find_child(name,true,false) as Button
	if button!=null:button.disabled=disabled

func _has_reinforcement(army_id: String, city_id: String) -> bool:
	for op in map.simulation.operations:
		if op.army==army_id and op.city==city_id:return true
	return false

func _resident_ready(id: String) -> bool:
	var army: Dictionary=map.simulation.armies.get(id,{})
	if army.is_empty() or int(army.get("troops",0))<=0 or army.get("faction")!=app.session.faction:return false
	var city_id: String=str(army.get("resident_city",""))
	return not city_id.is_empty() and not army.get("sortie_pending",false) and army.get("engaged_ids",[]).is_empty() and not _has_reinforcement(id,city_id)

func _refresh_management_buttons() -> void:
	if not is_instance_valid(management_dialog):return
	var sim=map.simulation
	if not _management_city.is_empty() and sim.cities.has(_management_city):
		var city: Dictionary=sim.cities[_management_city]
		var friendly: bool=city.owner==app.session.faction
		var safe: bool=friendly and not sim._city_under_siege(city)
		_set_management_disabled("ReinforceGuardsButton",not safe or city.kind!="city" or sim.city_capacity(_management_city)+100>city.people_capacity or city.recruits<100 or city.food<100000 or int(sim.faction_gold.get(app.session.faction,0))<50000 or _has_reinforcement("",_management_city))
		_set_management_disabled("RepairWallsButton",not safe or city.wall_hp>=city.wall_max or not city.repair.is_empty() or sim.tick-int(city.last_siege_tick)<150 or city.food<40000 or int(sim.faction_gold.get(app.session.faction,0))<20000)
		var resident: String=_picker_value(management_residents)
		var ready: bool=friendly and _resident_ready(resident)
		_set_management_disabled("ResidentSortieButton",not ready)
		var army: Dictionary=sim.armies.get(resident,{})
		_set_management_disabled("ResidentReinforceButton",not ready or not safe or int(army.get("troops",0))>=int(army.get("original_troops",0)))
		_set_management_disabled("CancelTrainingButton",not friendly or _picker_value(management_training).is_empty())
		_set_management_disabled("TransferFoodButton",not safe or city.food<100000)
		var cancel_allowed: bool=false
		for transfer in sim.transfers:
			if transfer.id==_picker_value(management_transfers) and transfer.faction==app.session.faction and not transfer.departed:cancel_allowed=true
		_set_management_disabled("CancelFoodTransferButton",not cancel_allowed)
	elif not _management_army.is_empty():
		var army: Dictionary=sim.armies.get(_management_army,{})
		var living: bool=not army.is_empty() and int(army.get("troops",0))>0 and army.get("faction")==app.session.faction
		var ready: bool=living and _resident_ready(_management_army)
		var city_id: String=str(army.get("resident_city",""))
		var safe: bool=ready and sim.cities.has(city_id) and not sim._city_under_siege(sim.cities[city_id])
		_set_management_disabled("EnterCityButton",not living or not city_id.is_empty() or not army.get("garrison_target","").is_empty())
		_set_management_disabled("SortieFormationButton",not ready)
		_set_management_disabled("ReinforceFormationButton",not safe or int(army.get("troops",0))>=int(army.get("original_troops",0)))
		_set_management_disabled("DisbandFormationButton",not safe)

func _refresh_resident_picker() -> void:
	if not is_instance_valid(management_residents):return
	var previous: String=_picker_value(management_residents)
	var ids: Array=map.simulation.resident_ids(_management_city)
	var signature: String=str(ids)
	if management_residents.get_meta("signature","")==signature:return
	management_residents.set_meta("signature",signature)
	management_residents.clear()
	if ids.is_empty():
		management_residents.add_item("No resident formations")
		management_residents.set_item_metadata(0,"")
		management_residents.disabled=true
		return
	management_residents.disabled=false
	for id in ids:
		var profile: Dictionary=map.simulation.commander_profile(id)
		management_residents.add_item(str(profile.get("name",id))+" | "+str(map.simulation.armies[id].unit_type).capitalize())
		management_residents.set_item_metadata(management_residents.item_count-1,id)
		if id==previous:management_residents.select(management_residents.item_count-1)

func _refresh_training_picker() -> void:
	if not is_instance_valid(management_training):return
	var previous: String=_picker_value(management_training)
	var jobs: Array=map.simulation.cities[_management_city].production_queue
	var signature: String=str(jobs)
	if management_training.get_meta("signature","")==signature:return
	management_training.set_meta("signature",signature)
	management_training.clear()
	if jobs.is_empty():
		management_training.add_item("No units in training")
		management_training.set_item_metadata(0,"")
		management_training.disabled=true
		return
	management_training.disabled=false
	for job in jobs:
		var commander: String=str(job.get("commander_id",""))
		var name: String=map.simulation.Officers.DEFINITIONS[commander].name if map.simulation.Officers.DEFINITIONS.has(commander) else "Commander"
		management_training.add_item(name+" | "+str(job.unit_type).capitalize())
		management_training.set_item_metadata(management_training.item_count-1,job.army_id)
		if job.army_id==previous:management_training.select(management_training.item_count-1)

func _refresh_transfer_picker() -> void:
	if not is_instance_valid(management_transfers):return
	var previous: String=_picker_value(management_transfers)
	var transfers: Array=[]
	for transfer in map.simulation.transfers:
		if transfer.source==_management_city and transfer.faction==app.session.faction:transfers.append(transfer)
	var signature: String=str(transfers)
	if management_transfers.get_meta("signature","")==signature:return
	management_transfers.set_meta("signature",signature)
	management_transfers.clear()
	if transfers.is_empty():
		management_transfers.add_item("No food transfers")
		management_transfers.set_item_metadata(0,"")
		management_transfers.disabled=true
		return
	management_transfers.disabled=false
	for transfer in transfers:
		management_transfers.add_item("%d Food to %s | %s"%[_whole(int(transfer.amount)),app.settlement_name(transfer.destination),str(transfer.state)])
		management_transfers.set_item_metadata(management_transfers.item_count-1,transfer.id)
		if transfer.id==previous:management_transfers.select(management_transfers.item_count-1)

func _build_stats_modal() -> void:
	if not _stats_army.is_empty():
		super._build_stats_modal();return
	_modal_scroll=null
	var center:=CenterContainer.new()
	modal.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shell:=PanelContainer.new()
	shell.theme=ClassicSkin.theme()
	shell.add_theme_stylebox_override("panel",ClassicSkin.panel("panel_cloud",18,14,true))
	shell.custom_minimum_size=Vector2(minf(790,get_viewport().get_visible_rect().size.x-40),0)
	center.add_child(shell)
	var scroll:=ScrollContainer.new()
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.y=minf(580,get_viewport().get_visible_rect().size.y-80)
	shell.add_child(scroll)
	var body:=VBoxContainer.new()
	body.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation",8)
	scroll.add_child(body)
	body.add_child(_heading("Battle and economy guide",28))
	var sim=map.simulation
	if not _stats_army.is_empty() and sim.armies.has(_stats_army):
		var army: Dictionary=sim.armies[_stats_army]
		var commander: Dictionary=sim.commander_profile(_stats_army)
		if not commander.is_empty():
			var identity:=HBoxContainer.new()
			body.add_child(identity)
			var portrait:=TextureRect.new()
			portrait.name="OriginalCommanderPortrait"
			portrait.custom_minimum_size=Vector2(72,84)
			portrait.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
			portrait.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			portrait.texture=load("res://"+str(commander.portrait)) as Texture2D
			identity.add_child(portrait)
			identity.add_child(_label("%s\nSTR %d | LEAD %d\n%s"%[commander.name,commander.str,commander.lead,commander.skill],18))
		body.add_child(_label("%s | Troops %d/%d | Morale %d%% | Rations %ds"%[str(army.unit_type).capitalize(),army.troops,int(army.get("original_troops",army.troops)),army.morale,sim.rations_seconds(_stats_army)],16))
		body.add_child(_label("LEAD strengthens this formation's power and protection. STR strengthens its commander's skill; range, cooldown and duration remain fixed.",14,T.MUTED))
	var recruit_strength: int=100 if sim.traditional_rts else 500
	body.add_child(_heading("Recruit %d troops"%recruit_strength,20))
	var prices:=GridContainer.new()
	prices.columns=5
	prices.add_theme_constant_override("h_separation",20)
	prices.add_theme_constant_override("v_separation",6)
	body.add_child(prices)
	for text in ["Type","Food","Gold","Recruits","Time"]:prices.add_child(_label(text,14,T.MUTED))
	for kind in ["infantry","archers","cavalry","siege"]:
		var profile: Dictionary=sim.PROFILES[kind]
		for text in [str(kind).capitalize(),str(int(profile.cost)*recruit_strength),str(int(sim.GOLD_COST[kind])*recruit_strength/500),str(recruit_strength),"%ds"%(sim.recruitment_ticks(kind)/10)]:prices.add_child(_label(text,15))
	body.add_child(_heading("Upkeep per 500 troops, each 10 seconds",20))
	var upkeep:=GridContainer.new()
	upkeep.columns=3
	upkeep.add_theme_constant_override("h_separation",20)
	upkeep.add_theme_constant_override("v_separation",6)
	body.add_child(upkeep)
	for text in ["Type","Food","Gold"]:upkeep.add_child(_label(text,14,T.MUTED))
	for kind in ["infantry","archers","cavalry","siege"]:
		for text in [str(kind).capitalize(),str(sim.FOOD_UPKEEP[kind]),str(sim.GOLD_UPKEEP[kind])]:upkeep.add_child(_label(text,15))
	for text in ["Fixed guards","10","2"]:upkeep.add_child(_label(text,15))
	var starting_guards: int=sim.Tactical.CITY_GARRISON if sim.tactical_rts else 250 if sim.traditional_rts else 1000
	var starting_walls: int=sim.Tactical.WALL_HP if sim.tactical_rts else 300 if sim.traditional_rts else 1200
	var population_limit: int=2000 if sim.traditional_rts else 10000
	var rules:=_label("Each city starts with %d guards, %d wall HP and shared capacity for %d people. Residents and training reserve that capacity.\n\nOne commander per formation; six living or training formations per faction. Garrison does not release the commander. Use Sortie to return to the field.\n\nReinforce guards or residents at a friendly city. Repair 100 HP costs 40 Food and 20 Gold, taking 25 seconds after the siege clears. Food transfers use a real supply route.\n\nWin by controlling all eight cities and eliminating all enemy troops, including guards in villages and troops on ferries. There is no extra 30-second victory wait."%[starting_guards,starting_walls,population_limit],14,T.MUTED)
	rules.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	body.add_child(rules)
	if sim.tactical_rts:body.add_child(_label("Fortified cities fire defensive arrows automatically within 22m. Break the walls, defeat the garrison and inner defenses, then hold the gate for 15 seconds with infantry or cavalry. Morale alone never captures a city.\n\nRight-click moves or attacks. Shift-right-click queues orders. A then ground advances while engaging enemies. S stops and clears orders. Tab selects all field troops; double-click a unit selects the same type on screen. Wei is blue, Shu green, Wu red.",14,T.MUTED))
	_button("Close [Esc]",func():app.back();refresh_screen(),body)
