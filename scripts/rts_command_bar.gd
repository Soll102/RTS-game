extends HBoxContainer
const T=preload("res://ui_tokens.gd")
const SHORT={"infantry":"INF","archers":"BOW","cavalry":"CAV","siege":"RAM"}
var interface: CanvasLayer
var map: Node3D
var slots: Array=[]
var identities: Array=[]

static func order_label(army: Dictionary) -> String:
	if army.routed:return "Rallying"
	if not army.get("resident_city","").is_empty():return "In city"
	if army.transport_elapsed>0:return "On boat"
	if not army.transport_id.is_empty():return "Waiting for boat"
	if army.get("stuck_ticks",0)>=8:return "Finding a way"
	if not army.engaged_ids.is_empty() and army.order.type not in ["move","retreat"]:return "Fighting"
	return {"move":"Moving","attack_move":"Advancing","attack":"Attacking","siege":"Siege","retreat":"Retreating","hold":"Ready"}.get(army.order.type,"Ready")

func configure(hud: CanvasLayer, scene: Node3D) -> void:
	interface=hud;map=scene;name="ArmyCommandBar";add_theme_constant_override("separation",4)
	var all:=Button.new();all.name="SelectAllArmies";all.text="All\n[Tab]";all.custom_minimum_size=Vector2(62,40);all.add_theme_font_size_override("font_size",12);add_child(all)
	all.pressed.connect(func():all.release_focus();map.controller.select_all_armies();interface.update_view(1))
	all.tooltip_text="Select all field formations. Tab or Ctrl+A."
	for index in range(6):
		var button:=Button.new();button.name="ArmySlot%d"%index;button.toggle_mode=true;button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		button.custom_minimum_size=Vector2(76,40);button.add_theme_font_size_override("font_size",12);add_child(button);slots.append(button)
		button.clip_text=true
		button.pressed.connect(func():
			button.release_focus()
			if index>=identities.size():return
			var additive: bool=button.get_meta("additive",false)
			button.set_meta("additive",false)
			if additive:map.controller.toggle_army(identities[index])
			else:map.controller.select_armies([identities[index]])
			interface.update_view(1))
		button.gui_input.connect(func(event):
			if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:button.set_meta("additive",event.shift_pressed)
			elif event is InputEventKey and event.pressed:button.set_meta("additive",event.shift_pressed)
			if event is InputEventMouseButton and event.pressed and event.double_click and index<identities.size():map.controller.select_armies([identities[index]]);map.controller.focus_selection())
	refresh()

func refresh() -> void:
	identities.clear()
	for id in map.simulation._sorted_ids(map.simulation.armies):
		var army: Dictionary=map.simulation.armies[id]
		if army.faction==map.controller.player_faction and army.troops>0:identities.append(id)
	for index in range(slots.size()):
		var button: Button=slots[index]
		button.disabled=index>=identities.size()
		if button.disabled:button.text="—";button.set_pressed_no_signal(false);button.tooltip_text="A free formation slot.";continue
		var id: String=identities[index];var army: Dictionary=map.simulation.armies[id]
		var queued: int=army.get("waypoints",[]).size()
		var commander: Dictionary=map.simulation.commander_profile(id)
		var hero_short: String=str(commander.get("name","")).split(" ")[0]
		var top_line: String="%s · %s %d"%[hero_short,SHORT[army.unit_type],army.troops] if not hero_short.is_empty() else "%s  %d"%[SHORT[army.unit_type],army.troops]
		button.text="%s\n%s%s"%[top_line,order_label(army)," +%d"%queued if queued>0 else ""]
		var is_sel: bool=id in map.controller.selected_armies
		button.set_pressed_no_signal(is_sel)
		button.add_theme_color_override("font_color",T.WORLD_ACCENT if is_sel else T.FACTION[army.faction]);button.add_theme_color_override("font_pressed_color",T.WORLD_ACCENT)
		button.tooltip_text="%s — %s\nClick to select; Shift-click adds/removes; double-click focuses.\n%s%s"%[commander.get("name",id),army.unit_type.capitalize(),order_label(army)," | %d queued orders"%queued if queued>0 else ""]
