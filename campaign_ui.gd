extends CanvasLayer
signal skill_order_accepted(target: Dictionary)
const T=preload("res://ui_tokens.gd")
const Overlay=preload("res://strategic_overlay.gd")
const Minimap=preload("res://campaign_minimap.gd")
const DockOrnament=preload("res://dock_ornament.gd")
const ClassicSkin=preload("res://scripts/hud_classic_skin.gd")
const StatsData=preload("res://unit_stats.gd")
const StatsPanel=preload("res://unit_stats_panel.gd")
const CommandBar=preload("res://scripts/rts_command_bar.gd")
var command_bar: HBoxContainer
var commander_portrait: TextureRect
var commander_name: Label
var commander_str: Label
var commander_lead: Label
var commander_bonus: Label
var recruit_commander_picker: OptionButton
var field_guide: PanelContainer
var _stats_army: String=""
var _strength_caption: Label
# Hallmark · component: bottom campaign HUD · genre: atmospheric · theme: inherited/source art
# States: default, hover, focus, pressed, disabled, queued/cooldown, error, success.
# Pre-emit critique: Philosophy5 Hierarchy5 Execution4 Specificity5 Restraint5 Variety4.
var _classic_identity: PanelContainer
var _classic_backdrop: ColorRect
var _classic_commands: PanelContainer
var _classic_stats: Dictionary={}
var _command_buttons: Dictionary={}
var _target_mode: String=""
var _mode_issuer: String=""
var _mode_armies: Array=[]
var _skill_feedback: String=""
var _skill_feedback_army: String=""
var _skill_feedback_until: int=0
var _skill_feedback_error: bool=false
var _commander_dialog: AcceptDialog
var app: RefCounted
var map: Node3D
var root: Control
var overlay: Control
var hud: Control
var modal: Control
var panel: VBoxContainer
var summary: Label
var details: Label
var queue_label: Label
var log_label: Label
var status: Label
var pause_button: Button
var minimap: Control
var stance_picker: OptionButton
var army_row: HBoxContainer
var recruit_row: VBoxContainer
var commander_row: VBoxContainer
var commander_label: Label
var commander_picker: OptionButton
var target_picker: OptionButton
var skill_button: Button
var roster: GridContainer
var city_roster: GridContainer
var faction: String="wei"
var challenge: String="standard"
var _last_screen: String=""
var _elapsed: float=0
var _message_until: int=0
var _modal_scroll: ScrollContainer
var confirmation: ConfirmationDialog
var _confirmed_action: Callable
var _skill_sequence: int=0
var _active_army: String=""
var _assign_button: Button
var _commander_selection: String=""
var _shell: PanelContainer
var _mini_shell: PanelContainer
var _context: VBoxContainer
var _heading_label: Label
var _meta_label: Label
var _stats: Dictionary={}
var _city_buttons: Dictionary={}
var _roster_open: bool=false
var _selection_signature: String=""
var _status_box: PanelContainer
var _objective: Label
# Hallmark · pre-emit critique: P4 H5 E4 S5 R5 V4
const CITY_KEYS={KEY_1:"infantry",KEY_2:"archers",KEY_3:"cavalry",KEY_4:"siege",KEY_Q:"infantry",KEY_E:"archers",KEY_R:"cavalry",KEY_T:"siege"}
const CITY_KEY_LABELS={"infantry":"1 / Q","archers":"2 / E","cavalry":"3 / R","siege":"4 / T"}
var _city_dock: bool=false
var _dock_row: HBoxContainer
var _city_info: VBoxContainer
var _command_shell: PanelContainer
var _queue_slots: Array=[]
var _training_bar: ProgressBar
var _training_label: Label
var _capacity_label: Label
var _dock_ornament: Control
var _top_panels: Array[PanelContainer]=[]
var _city_info_panel: PanelContainer
var _roster_forces: PanelContainer
var _officer_details: VBoxContainer
var _officer_details_open: bool=false
var _idle_hint: Label
var _last_hud_tick: int=-1
var _last_hud_signature: String=""

func _has_ui_popup(node: Node) -> bool:
	for child in node.get_children(true):
		if child is Window:
			if child.visible:return true
		elif _has_ui_popup(child):return true
	return false

func keyboard_camera_allowed() -> bool:
	if app==null or app.screen!="campaign" or not hud.visible or _roster_open or _has_ui_popup(root):return false
	var focus: Control=get_viewport().gui_get_focus_owner()
	return focus==null or not (focus is LineEdit or focus is TextEdit)

func _prepare_picker(picker: OptionButton) -> void:
	picker.fit_to_longest_item=false;picker.clip_text=true
	picker.focus_mode=Control.FOCUS_NONE
	picker.get_popup().popup_hide.connect(func():picker.release_focus())
	picker.item_selected.connect(func(_i):picker.release_focus())


func configure(value: RefCounted, scene: Node3D) -> void:
	app=value;map=scene
	root=Control.new();add_child(root);root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter=Control.MOUSE_FILTER_IGNORE;root.theme=ClassicSkin.theme()
	overlay=Overlay.new();root.add_child(overlay);overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter=Control.MOUSE_FILTER_IGNORE;overlay.app=app;overlay.map=map;overlay.interface=self
	_build_hud()
	modal=Control.new();root.add_child(modal);modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	confirmation=ConfirmationDialog.new();confirmation.borderless=true;confirmation.theme=ClassicSkin.theme();root.add_child(confirmation)
	confirmation.get_ok_button().theme=ClassicSkin.primary_theme()
	confirmation.confirmed.connect(func():
		if _confirmed_action.is_valid():_confirmed_action.call()
		_confirmed_action=Callable())
	confirmation.canceled.connect(func():_confirmed_action=Callable())
	map.controller.order_feedback.connect(func(text,failed):message(text,failed))
	map.controller.context_order_accepted.connect(func(_target):
		var order: String=str(map.controller.accepted_order.get("order","move"))
		message("Order added to queue." if map.controller.accepted_order.get("queued",false) else "Attack-move order issued." if order=="attack_move" else order.capitalize()+" order issued."))
	get_viewport().size_changed.connect(_layout)
	_load_settings();refresh_screen();call_deferred("_layout")

func _label(text: String, font_size: int=18, color: Color=T.INK) -> Label:
	var label:=Label.new();label.text=text;label.add_theme_font_size_override("font_size",font_size);label.add_theme_color_override("font_color",color);label.add_theme_color_override("font_outline_color",Color.TRANSPARENT);label.add_theme_constant_override("outline_size",0)
	return label
func _heading(text: String, font_size: int=30) -> Label:
	var label:=_label(text,font_size);label.add_theme_font_override("font",T.display_font());return label
func _button(text: String, action: Callable, parent: Node, width: float=0, primary: bool=false) -> Button:
	var button:=Button.new();button.text=text;button.custom_minimum_size=Vector2(width,36)
	if primary:button.theme=ClassicSkin.primary_theme()
	button.pressed.connect(func():button.release_focus();action.call());parent.add_child(button);return button
func _toolbar_button(text: String, action: Callable, parent: Node, width: float) -> Button:
	var button:=_button(text,action,parent,width);button.flat=true
	for state in ["normal","hover","pressed","hover_pressed","disabled","focus"]:
		var style:=StyleBoxEmpty.new();style.content_margin_left=8;style.content_margin_right=8
		style.content_margin_top=4;style.content_margin_bottom=4
		button.add_theme_stylebox_override(state,style)
	# Keyboard focus uses an underline rather than another rectangular frame.
	var focus:=StyleBoxFlat.new();focus.bg_color=Color.TRANSPARENT;focus.border_color=T.ACCENT;focus.border_width_bottom=2
	focus.content_margin_left=8;focus.content_margin_right=8;focus.content_margin_top=4;focus.content_margin_bottom=4
	button.add_theme_stylebox_override("focus",focus);return button
func _clear(node: Node) -> void:
	for child in node.get_children():node.remove_child(child);child.queue_free()
func _stat(name: String, parent: Node) -> Label:
	var recess:=PanelContainer.new();parent.add_child(recess);recess.add_theme_stylebox_override("panel",T.surface("inset",10,5))
	var row:=HBoxContainer.new();recess.add_child(row)
	var caption:=_label(name,16,T.MUTED);caption.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(caption)
	var value:=_label("",18);row.add_child(value);return value
func _line(parent: Node) -> void:
	var line:=HSeparator.new();line.modulate=Color.WHITE;parent.add_child(line)

func _build_hud() -> void:
	hud=Control.new();root.add_child(hud);hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);hud.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_classic_backdrop=ColorRect.new();_classic_backdrop.color=T.WORLD_BASE;hud.add_child(_classic_backdrop);_classic_backdrop.mouse_filter=Control.MOUSE_FILTER_STOP
	var top:=PanelContainer.new();hud.add_child(top);top.theme=ClassicSkin.theme();top.add_theme_stylebox_override("panel",T.dock_surface(10,2));_top_panels.append(top)
	var bar:=HBoxContainer.new();bar.add_theme_constant_override("separation",8);bar.alignment=BoxContainer.ALIGNMENT_CENTER;top.add_child(bar)
	_toolbar_button("Menu",func():app.open_panel("pause");refresh_screen(),bar,56)
	var title_lbl:=_heading("Unification",17);title_lbl.add_theme_color_override("font_color",T.ACCENT);bar.add_child(title_lbl)
	var resources:=PanelContainer.new();hud.add_child(resources);resources.theme=ClassicSkin.theme();resources.add_theme_stylebox_override("panel",T.dock_surface(12,2));_top_panels.append(resources)
	summary=_label("",14,T.INK);summary.clip_text=true;summary.vertical_alignment=VERTICAL_ALIGNMENT_CENTER;resources.add_child(summary)
	var actions:=PanelContainer.new();hud.add_child(actions);actions.theme=ClassicSkin.theme();actions.add_theme_stylebox_override("panel",T.dock_surface(10,2));_top_panels.append(actions)
	var controls:=HBoxContainer.new();controls.add_theme_constant_override("separation",6);controls.alignment=BoxContainer.ALIGNMENT_CENTER;actions.add_child(controls)
	_toolbar_button("Roster",func():_roster_open=not _roster_open;_selection_signature="";_last_hud_tick=-1;update_view(1),controls,62)
	pause_button=_toolbar_button("Pause",map.controller.toggle_pause,controls,72)
	_objective=_label("Control all eight cities. Villages support your supply routes.",14,T.WORLD_MUTED);_objective.add_theme_color_override("font_outline_color",Color("060a0e"));_objective.add_theme_constant_override("outline_size",2);hud.add_child(_objective);_objective.position=Vector2(18,68)
	_idle_hint=_label("Click / drag: select   |   Right click: order   |   Shift: queue   |   Tab: all troops",13,T.WORLD_MUTED)
	_idle_hint.add_theme_color_override("font_outline_color",T.WORLD_BASE);_idle_hint.add_theme_constant_override("outline_size",3)
	_idle_hint.mouse_filter=Control.MOUSE_FILTER_IGNORE;hud.add_child(_idle_hint)
	_shell=PanelContainer.new();hud.add_child(_shell);_shell.add_theme_stylebox_override("panel",T.split_shell())
	var scroll:=ScrollContainer.new();_shell.add_child(scroll);scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	_context=VBoxContainer.new();_context.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(_context)
	_mini_shell=PanelContainer.new();hud.add_child(_mini_shell)
	_mini_shell.theme=T.dock_theme();_mini_shell.add_theme_stylebox_override("panel",T.dock_surface())
	var navigation:=VBoxContainer.new();_mini_shell.add_child(navigation)
	var row:=HBoxContainer.new();navigation.add_child(row)
	row.add_child(_label("REGION",12,T.MUTED))
	
	_button("Labels",func():app.show_labels=not app.show_labels;_save_settings(),row,60)
	_button("Guide",func():open_stats(),row,58)
	minimap=Minimap.new();minimap.custom_minimum_size=Vector2(208,130);navigation.add_child(minimap);minimap.configure(app,map);minimap.interface=self
	log_label=_label("",13,Color.WHITE);log_label.add_theme_color_override("font_outline_color",Color("060a0e"));log_label.add_theme_constant_override("outline_size",2);hud.add_child(log_label);log_label.position=Vector2(18,94)
	_status_box=PanelContainer.new();hud.add_child(_status_box);_status_box.theme=T.dock_theme()
	status=_label("",14);status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;_status_box.add_child(status);_status_box.visible=false
	command_bar=CommandBar.new();hud.add_child(command_bar);command_bar.configure(self,map)


func overlay_blockers() -> Array:
	var result: Array=[]
	for card in _top_panels:
		if card.is_visible_in_tree():result.append(card.get_global_rect().grow(3))
	for card in [_shell,_mini_shell,_status_box,_objective,log_label,_idle_hint,command_bar]:
		if is_instance_valid(card) and card.is_visible_in_tree():
			if card is Label and card.text.is_empty():continue
			result.append(card.get_global_rect().grow(3))
	if is_instance_valid(_classic_backdrop) and _classic_backdrop.is_visible_in_tree():result.append(_classic_backdrop.get_global_rect())
	return result

func map_rect() -> Rect2:
	var size: Vector2=get_viewport().get_visible_rect().size
	var bottom: float=minf(_shell.position.y-6,_mini_shell.position.y-6) if _shell.visible else _mini_shell.position.y-6
	if is_instance_valid(command_bar) and command_bar.visible:bottom=minf(bottom,command_bar.position.y-6)
	return Rect2(Vector2(8,8),Vector2(maxf(100,size.x-16),maxf(100,bottom-8)))

func _layout() -> void:
	if not is_instance_valid(_shell):return
	var size: Vector2=get_viewport().get_visible_rect().size
	# Hallmark: native RTS workbench, gold/brown, bottom-aligned peripheral controls.
	if _top_panels.size()==3:
		_top_panels[0].position=Vector2(12,size.y-36);_top_panels[0].size=Vector2(196,28)
		_top_panels[1].position=Vector2(216,size.y-36);_top_panels[1].size=Vector2(minf(520,size.x-412),28)
		_top_panels[2].position=Vector2(size.x-188,size.y-36);_top_panels[2].size=Vector2(176,28)
		for card in _top_panels:
			card.add_theme_stylebox_override("panel",T.dock_surface(10,2))
			for button in card.find_children("*","Button",true,false):
				button.custom_minimum_size.y=22;button.add_theme_font_size_override("font_size",13)
	for card in [_classic_identity,_city_info_panel,_roster_forces,_classic_commands,_command_shell]:
		if is_instance_valid(card) and card.is_visible_in_tree():card.add_theme_stylebox_override("panel",T.dock_surface(12,8))
	var mini_width: float=184.0
	var idle: bool=not _shell.visible
	var height: float=minf(size.y-152,maxf(148,_context.get_combined_minimum_size().y+6)) if not idle else 32.0
	var top: float=size.y-height-44
	_classic_backdrop.visible=false
	_shell.position=Vector2(mini_width+20,top);_shell.size=Vector2(size.x-mini_width-32,height)
	_mini_shell.position=Vector2(12,size.y-170-44);_mini_shell.size=Vector2(mini_width,170)
	_mini_shell.theme=ClassicSkin.theme();_mini_shell.add_theme_stylebox_override("panel",T.dock_surface(8,8))
	minimap.custom_minimum_size=Vector2(mini_width-16,114);minimap.size_flags_vertical=Control.SIZE_EXPAND_FILL
	var navigation: VBoxContainer=_mini_shell.get_child(0);navigation.add_theme_constant_override("separation",4)
	for child in navigation.get_child(0).get_children():
		if child is Button:child.custom_minimum_size.y=22;child.add_theme_font_size_override("font_size",11)
	command_bar.position=Vector2(mini_width+20,top-44);command_bar.size=Vector2(size.x-mini_width-32,38)
	_status_box.position=Vector2(mini_width+20,top-76);_status_box.size=Vector2(minf(520,size.x-mini_width-32),26)
	_status_box.add_theme_stylebox_override("panel",T.dock_surface(10,3))
	_idle_hint.visible=idle;_idle_hint.position=Vector2(mini_width+24,size.y-68)
	_objective.visible=false
	if is_instance_valid(_dock_ornament):_dock_ornament.visible=false
	if _modal_scroll!=null and is_instance_valid(_modal_scroll):_modal_scroll.custom_minimum_size.y=minf(540,size.y-80)

func message(text: String, error: bool=false, success: String="") -> void:
	status.text=text if not text.is_empty() else success
	status.add_theme_color_override("font_color",T.ERROR if error else T.INK)
	_message_until=Time.get_ticks_msec()+(5000 if error else 2500);_status_box.visible=not status.text.is_empty()

func update_view(delta: float) -> void:
	if app==null:return
	if app.screen!=_last_screen:refresh_screen()
	if app.screen!="campaign":return
	_validate_target_mode()
	overlay.queue_redraw();minimap.queue_redraw();_elapsed+=delta
	if _elapsed<.15:return
	_elapsed=0
	var ids: Array=map.controller.selected_armies;var city: String=map.controller.selected_city
	var signature: String=str(ids)+city+str(_roster_open)+str(map.simulation.paused)
	var tick_now: int=int(map.simulation.tick)
	if Time.get_ticks_msec()>_message_until:_status_box.visible=false
	if signature==_last_hud_signature and tick_now==_last_hud_tick:return
	_last_hud_signature=signature;_last_hud_tick=tick_now
	command_bar.refresh()
	var data: Dictionary=app.session.summary()
	summary.text="%s    Food %s    Cities %d / 8    %02d:%02d"%[data.faction.capitalize(),data.food,data.cities,data.tick/600,(data.tick/10)%60]
	pause_button.text="Resume" if data.paused else "Pause"
	if signature!=_selection_signature:
		_selection_signature=signature;_build_context(ids,city);_layout()
		call_deferred("_layout")
	if _roster_open:_refresh_roster()
	elif not ids.is_empty():_update_army(ids)
	elif not city.is_empty():_update_city(city)
	_objective.visible=false
	_objective.text="%d / 8 cities controlled   |   Protect supply, escort siege, capture the region."%data.cities
	var events: Array=app.recent_events(2);var lines:=PackedStringArray()
	for event in events:lines.append("%02d:%02d   %s"%[event.tick/600,(event.tick/10)%60,event.text])
	log_label.text="\n".join(lines);log_label.visible=false

func _group(parent: Node) -> VBoxContainer:
	var shell:=PanelContainer.new();shell.add_theme_stylebox_override("panel",T.surface("panel",10,8));parent.add_child(shell)
	var content:=VBoxContainer.new();content.size_flags_horizontal=Control.SIZE_EXPAND_FILL;content.add_theme_constant_override("separation",5);shell.add_child(content)
	return content

func _build_context(ids: Array, city: String) -> void:
	_clear(_context);_stats.clear();_classic_stats.clear();_city_buttons.clear();_queue_slots.clear();_commander_selection="";_city_dock=false
	_shell.visible=true;_shell.add_theme_stylebox_override("panel",T.split_shell());_shell.theme=ClassicSkin.theme()
	_context.add_theme_constant_override("separation",0)
	if _roster_open:
		var row:=HBoxContainer.new();row.add_theme_constant_override("separation",12);_context.add_child(row)
		var forces:=PanelContainer.new();forces.size_flags_horizontal=Control.SIZE_EXPAND_FILL;forces.add_theme_stylebox_override("panel",ClassicSkin.panel("panel_cloud",10,8,true));row.add_child(forces)
		_roster_forces=forces
		var left:=VBoxContainer.new();forces.add_child(left);left.add_child(_heading("Your forces",19));roster=GridContainer.new();roster.columns=2;left.add_child(roster)
		var settlements:=PanelContainer.new();settlements.custom_minimum_size.x=294;settlements.add_theme_stylebox_override("panel",ClassicSkin.panel());row.add_child(settlements)
		var right:=VBoxContainer.new();settlements.add_child(right);city_roster=GridContainer.new();city_roster.columns=2;right.add_child(city_roster)
		_button("Back to selection",func():_roster_open=false;_selection_signature="";update_view(1),right).custom_minimum_size.y=24
		_refresh_roster();return
	if ids.is_empty() and not city.is_empty():_city_dock=true;_build_city_dock();return
	if ids.is_empty():_shell.visible=false;_active_army="";return
	var row:=HBoxContainer.new();row.add_theme_constant_override("separation",12);row.size_flags_horizontal=Control.SIZE_EXPAND_FILL;_context.add_child(row)
	_classic_identity=PanelContainer.new();_classic_identity.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_classic_identity.add_theme_stylebox_override("panel",ClassicSkin.panel("panel_cloud",10,8,true));row.add_child(_classic_identity)
	var body:=HBoxContainer.new();body.add_theme_constant_override("separation",12);_classic_identity.add_child(body)
	var portrait_frame:=PanelContainer.new();portrait_frame.add_theme_stylebox_override("panel",ClassicSkin.panel("portrait_frame",4,4));portrait_frame.size_flags_vertical=Control.SIZE_SHRINK_CENTER;body.add_child(portrait_frame)
	commander_portrait=TextureRect.new();commander_portrait.name="OriginalCommanderPortrait";commander_portrait.custom_minimum_size=Vector2(68,84)
	commander_portrait.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;commander_portrait.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	commander_portrait.mouse_filter=Control.MOUSE_FILTER_IGNORE;portrait_frame.add_child(commander_portrait)
	var identity:=VBoxContainer.new();identity.custom_minimum_size.x=176;identity.size_flags_horizontal=Control.SIZE_EXPAND_FILL;identity.add_theme_constant_override("separation",2);body.add_child(identity)
	_heading_label=_heading("Select a formation",19);_heading_label.add_theme_color_override("font_color",T.WORLD_ACCENT);identity.add_child(_heading_label)
	commander_name=_label("",15,T.INK);identity.add_child(commander_name)
	var population:=HBoxContainer.new();population.add_theme_constant_override("separation",8);identity.add_child(population)
	_strength_caption=_label("TROOPS",10,T.ACCENT);population.add_child(_strength_caption);_stats.Troops=_label("—",21,T.WORLD_ACCENT);population.add_child(_stats.Troops)
	_stats.Morale=_label("",12,T.SUCCESS);population.add_child(_stats.Morale)
	_meta_label=_label("",12,T.MUTED);identity.add_child(_meta_label)
	stance_picker=OptionButton.new();stance_picker.custom_minimum_size=Vector2(184,24);stance_picker.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN;stance_picker.add_theme_font_size_override("font_size",12)
	_prepare_picker(stance_picker)
	for stance in ["Phương Viên [Z] (Balanced)","Phong Thỉ [X] (Wedge)","Hạc Dực [C] (Line)"]:stance_picker.add_item(stance)
	stance_picker.item_selected.connect(func(i):map.controller.set_stance(["balanced","aggressive","defensive"][i]));identity.add_child(stance_picker)
	var grid:=GridContainer.new();grid.columns=2;grid.custom_minimum_size.x=124;grid.size_flags_vertical=Control.SIZE_SHRINK_CENTER;grid.add_theme_constant_override("h_separation",16);grid.add_theme_constant_override("v_separation",6);body.add_child(grid)
	for key in ["STR","LEAD","Attack","Armor","Speed","Food"]:
		var cell:=VBoxContainer.new();cell.add_theme_constant_override("separation",0);grid.add_child(cell);cell.add_child(_label(key.to_upper(),10,T.ACCENT))
		var value:=_label("—",17 if key in ["STR","LEAD"] else 14,T.WORLD_ACCENT if key in ["STR","LEAD"] else T.INK);cell.add_child(value);_classic_stats[key]=value
		cell.visible=key not in ["Attack","Armor"]
		if key=="STR":commander_str=value
		elif key=="LEAD":commander_lead=value
		elif key=="Food":_stats.Food=value
	_classic_commands=PanelContainer.new();_classic_commands.custom_minimum_size.x=294;_classic_commands.add_theme_stylebox_override("panel",ClassicSkin.panel());row.add_child(_classic_commands)
	var commands:=VBoxContainer.new();commands.add_theme_constant_override("separation",3);_classic_commands.add_child(commands);_build_commander_controls(commands)
	if ids.is_empty():
		commander_portrait.visible=false;stance_picker.disabled=true;commander_name.text="Choose a unit on the map"
		for button in _command_buttons.values():button.disabled=true
		commander_label.text="Skills follow the selected unit."

func _update_army(ids: Array) -> void:
	var sim=map.simulation;_active_army=ids[0]
	var army: Dictionary=sim.armies[_active_army];var profile: Dictionary=StatsData.selected_profile(sim,_active_army)
	_strength_caption.text="STRENGTH" if sim.get("traditional_rts")==true else "TROOPS"
	var troops: int=0;var food: int=0;var capacity: int=0;var morale: int=0
	for id in ids:
		troops+=sim.armies[id].troops;food+=sim.armies[id].food;capacity+=sim.armies[id].food_capacity;morale+=sim.armies[id].morale
	_heading_label.text=army.unit_type.capitalize() if ids.size()==1 else "%d formations"%ids.size()
	_meta_label.text=army.faction.capitalize()+" | "+CommandBar.order_label(army)+(" | %d queued"%army.waypoints.size() if army.get("waypoints",[]).size()>0 else "")
	_stats.Troops.text=str(troops);_stats.Morale.text="%d%% morale"%(morale/ids.size());_stats.Food.text="%d/%d"%[food,capacity]
	_classic_stats.Attack.text=str(profile.current_damage_vs_infantry);_classic_stats.Armor.text=str(profile.effective_defense)
	_classic_stats.Speed.text="%.1fm/s"%profile.current_speed_metres_per_second
	_classic_stats.Attack.tooltip_text="Damage per combat pulse against reference infantry. Troops, morale, stance, terrain and LEAD are included."
	_classic_stats.Armor.tooltip_text="Defense coefficient before LEAD and protection skills."
	_classic_stats.Speed.tooltip_text="Movement budget; contact, orders and ferries can stop movement."
	stance_picker.select(["balanced","aggressive","defensive"].find(army.stance));stance_picker.disabled=false
	_refresh_commander_controls(ids)

func _queued_armies() -> int:
	var count: int=0
	for city in map.simulation.cities.values():
		for job in city.production_queue:
			if job.faction==app.session.faction:count+=1
	return count

func _build_city_dock() -> void:
	var row:=HBoxContainer.new();row.add_theme_constant_override("separation",12);row.size_flags_horizontal=Control.SIZE_EXPAND_FILL;_context.add_child(row)
	_city_info_panel=PanelContainer.new();_city_info_panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL;_city_info_panel.add_theme_stylebox_override("panel",ClassicSkin.panel("panel_cloud",10,8,true));row.add_child(_city_info_panel)
	var body:=HBoxContainer.new();body.add_theme_constant_override("separation",12);_city_info_panel.add_child(body)
	var icon:=TextureRect.new();icon.texture=ClassicSkin.texture("city_icon");icon.custom_minimum_size=Vector2(54,64);icon.size_flags_vertical=Control.SIZE_SHRINK_CENTER;icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;body.add_child(icon)
	var data:=VBoxContainer.new();data.size_flags_horizontal=Control.SIZE_EXPAND_FILL;data.add_theme_constant_override("separation",1);body.add_child(data)
	_heading_label=_heading("",18);_heading_label.add_theme_color_override("font_color",T.WORLD_ACCENT);data.add_child(_heading_label);_meta_label=_label("",11,T.MUTED);data.add_child(_meta_label)
	var values:=GridContainer.new();values.columns=5;values.add_theme_constant_override("h_separation",14);values.add_theme_constant_override("v_separation",2);data.add_child(values)
	for key in ["Garrison","Walls","City HP","City Morale","Food"]:
		var cell:=VBoxContainer.new();cell.add_theme_constant_override("separation",0);values.add_child(cell);cell.add_child(_label(key.to_upper(),9,T.ACCENT));_stats[key]=_label("",15,T.INK);cell.add_child(_stats[key])
	var train_row:=HBoxContainer.new();train_row.add_theme_constant_override("separation",14);data.add_child(train_row)
	queue_label=_label("",11,T.WORLD_ACCENT);train_row.add_child(queue_label);_training_label=_label("",11,T.MUTED);train_row.add_child(_training_label)
	_command_shell=PanelContainer.new();_command_shell.custom_minimum_size.x=294;_command_shell.add_theme_stylebox_override("panel",ClassicSkin.panel());row.add_child(_command_shell)
	var commands:=VBoxContainer.new();commands.add_theme_constant_override("separation",3);_command_shell.add_child(commands)
	commands.add_child(_label("RECRUIT | CHOOSE COMMANDER",10,T.ACCENT))
	recruit_commander_picker=OptionButton.new();recruit_commander_picker.custom_minimum_size.y=24;recruit_commander_picker.add_theme_font_size_override("font_size",12);commands.add_child(recruit_commander_picker)
	recruit_commander_picker.custom_minimum_size.x=156;_prepare_picker(recruit_commander_picker)
	recruit_commander_picker.item_selected.connect(func(_i):_update_city(map.controller.selected_city))
	var grid:=GridContainer.new();grid.columns=2;grid.add_theme_constant_override("h_separation",5);grid.add_theme_constant_override("v_separation",4);commands.add_child(grid)
	for kind in ["infantry","archers","cavalry","siege"]:
		var button:=_button("",func():_recruit_city(kind),grid,130);button.custom_minimum_size.y=36;button.add_theme_font_size_override("font_size",12);_city_buttons[kind]=button
	_capacity_label=_label("",11,T.MUTED);commands.add_child(_capacity_label)

func _recruit_city(kind: String) -> void:
	if not _city_context_active():return
	_update_city(map.controller.selected_city)
	var button: Button=_city_buttons[kind]
	if button.disabled:
		message(button.get_meta("blocked_reason","Recruitment unavailable."),true);return
	var chosen: String=_refresh_recruit_commander()
	var error: String=app.session.recruit_for_commander(kind,chosen,500)
	message(error,not error.is_empty(),kind.capitalize()+" queued  |  500 troops.");_last_hud_tick=-1;update_view(1)

func _city_context_active() -> bool:
	return app!=null and app.screen=="campaign" and hud.visible and not confirmation.visible and not _roster_open and map.controller.selected_armies.is_empty() and map.simulation.cities.has(map.controller.selected_city)

func _focus_city() -> void:
	if _city_context_active():map.focus_map(map.controller.city_positions[map.controller.selected_city])

func _input(event: InputEvent) -> void:
	if app==null or app.screen!="campaign":return
	_validate_target_mode()
	if _has_ui_popup(root):return
	if _roster_open:
		if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:
			_roster_open=false;_selection_signature="";update_view(1);get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.ctrl_pressed and (event.physical_keycode if event.physical_keycode!=0 else event.keycode)==KEY_A:
		map.controller.select_all_armies();update_view(1);get_viewport().set_input_as_handled();return
	if event is InputEventKey and event.pressed and not event.echo and not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed:
		var key: int=event.physical_keycode if event.physical_keycode!=0 else event.keycode
		if key==KEY_TAB:map.controller.select_all_armies();update_view(1);get_viewport().set_input_as_handled();return
		if key==KEY_ESCAPE and not _target_mode.is_empty():_cancel_target_mode();get_viewport().set_input_as_handled();return
		if key==KEY_F1:open_stats(map.controller.selected_armies[0] if not map.controller.selected_armies.is_empty() else "");get_viewport().set_input_as_handled();return
		if _city_context_active() and key in CITY_KEYS:_recruit_city(CITY_KEYS[key]);get_viewport().set_input_as_handled();return
		if not map.controller.selected_armies.is_empty():
			var stances: Dictionary={KEY_Z:["balanced","Phương Viên (Balanced)"],KEY_X:["aggressive","Phong Thỉ (Wedge)"],KEY_C:["defensive","Hạc Dực (Shield Wall)"]}
			if stances.has(key):
				var err: String=map.controller.set_stance(stances[key][0])
				message(err,not err.is_empty(),"Formation: "+stances[key][1]);_last_hud_tick=-1;update_view(1);get_viewport().set_input_as_handled();return
			var keys: Dictionary={KEY_M:"move",KEY_A:"attack",KEY_Q:"skill",KEY_S:"hold",KEY_H:"hold",KEY_R:"retreat",KEY_F:"focus"}
			if keys.has(key):_classic_command(keys[key]);get_viewport().set_input_as_handled();return
	if not event is InputEventMouseButton or not event.pressed or _target_mode.is_empty():return
	if event.button_index==MOUSE_BUTTON_RIGHT:_cancel_target_mode();get_viewport().set_input_as_handled();return
	if event.button_index!=MOUSE_BUTTON_LEFT:return
	for box in overlay_blockers():
		if box.has_point(event.position):return
	var target: Dictionary=map.controller.pick_entity(event.position,_target_mode=="attack")
	if _target_mode=="move":
		var point=map.controller.terrain_point(event.position)
		if point!=null:target={"kind":"node","id":map.controller.nearest_node(point),"position":point}
	elif _target_mode=="skill":
		if target.get("kind","")!="army":message("Choose an enemy formation for this skill.",true);get_viewport().set_input_as_handled();return
		_submit_classic_skill(target.id);get_viewport().set_input_as_handled();return
	elif _target_mode=="attack":
		if target.get("kind","") not in ["army","city","gate"]:
			var ground=map.controller.terrain_point(event.position)
			var destination: String=map.controller.nearest_node(ground) if ground!=null else ""
			if destination.is_empty():message("Choose reachable terrain or an enemy target.",true);get_viewport().set_input_as_handled();return
			target={"kind":"attack_move","id":destination}
		else:
			var friendly: bool=map.simulation.armies[target.id].faction==app.session.faction if target.kind=="army" else map.simulation.cities[target.id].owner==app.session.faction
			if friendly:
				var point=map.controller.terrain_point(event.position)
				var node: String=map.controller.nearest_node(point) if point!=null else ""
				if node.is_empty():message("Choose reachable ground.",true);get_viewport().set_input_as_handled();return
				target={"kind":"attack_move","id":node}
	if not target.is_empty():
		var error: String=map.controller.issue_context_order(target,event.shift_pressed)
		if error.is_empty():
			map.controller.context_order_accepted.emit(target)
			if not event.shift_pressed:_cancel_target_mode()
	get_viewport().set_input_as_handled()

func _update_city(id: String) -> void:
	var sim=map.simulation;var city: Dictionary=sim.cities[id];var under_siege: bool=sim._city_under_siege(city)
	_heading_label.text=app.settlement_name(id);_meta_label.text=city.owner.capitalize()+" | "+("Under siege" if under_siege else "City" if city.victory_point else "Village")
	_stats.Garrison.text=str(city.garrison);_stats.Walls.text=str(city.wall_hp);_stats.Food.text=str(city.food)
	_stats["City HP"].text="%d/%d"%[int(city.get("city_hp",0)),int(city.get("city_hp_max",0))]
	_stats["City Morale"].text=str(int(city.get("city_morale",0)))
	var chosen: String=_refresh_recruit_commander();var capacity: int=app.session.summary().armies+_queued_armies()
	_capacity_label.text="Forces %d / 6 | Queue %d / 3"%[capacity,city.production_queue.size()]
	for kind in _city_buttons:
		var p: Dictionary=sim.PROFILES[kind];var cost: int=p.cost*500;var reason: String=""
		if city.owner!=app.session.faction:reason="Select a friendly city."
		elif not city.recruitment_enabled:reason="Villages cannot recruit."
		elif city.production_queue.size()>=3:reason="Training queue is full."
		elif capacity>=6:reason="Six-formation faction limit reached."
		elif chosen.is_empty():reason="Choose an available commander first."
		elif city.food<cost:reason="Not enough city food."
		var button: Button=_city_buttons[kind];button.text="[%s] %s\n%d food | %ds"%[CITY_KEY_LABELS[kind],kind.capitalize(),cost,p.training/10]
		button.disabled=not reason.is_empty();button.set_meta("blocked_reason",reason);button.tooltip_text="500 troops | "+reason if not reason.is_empty() else "500 troops | Reserve the selected commander."
	if city.production_queue.is_empty():queue_label.text="No units in training.";_training_label.text="Choose commander and unit type.";return
	var active: Dictionary=city.production_queue[0];var name: String=sim.Officers.DEFINITIONS[active.commander_id].name
	queue_label.text=name+" | "+active.unit_type.capitalize();_training_label.text="%ds remaining | %d waiting"%[ceili(active.remaining_ticks/10.0),city.production_queue.size()-1]

func _refresh_roster() -> void:
	var signature: String=""
	for id in map.simulation._sorted_ids(map.simulation.armies):
		var army: Dictionary=map.simulation.armies[id]
		if army.faction==app.session.faction:signature+=id+str(army.troops)+map.simulation.officer_for(id)
	for city in map.simulation.cities.values():signature+=city.id+city.owner
	if roster.get_meta("signature","")==signature:return
	roster.set_meta("signature",signature);_clear(roster);_clear(city_roster)
	for id in map.simulation._sorted_ids(map.simulation.armies):
		var army: Dictionary=map.simulation.armies[id]
		if army.faction!=app.session.faction or army.troops<=0:continue
		var hero: String=map.simulation.officer_for(id)
		var name: String=map.simulation.Officers.DEFINITIONS[hero].name if not hero.is_empty() else army.unit_type.capitalize()
		_button("%s · %s · %d"%[name,army.unit_type.capitalize(),army.troops],func():
			_roster_open=false;map.controller.select_armies([id]);map.controller.focus_selection();_selection_signature="";update_view(1),roster)
	for id in map.simulation._sorted_ids(map.simulation.cities):
		if map.simulation.cities[id].owner!=app.session.faction:continue
		_button(app.settlement_name(id),func():
			_roster_open=false;map.controller.select_city(id);map.focus_map(map.controller.city_positions[id]);_selection_signature="";update_view(1),city_roster)

func _build_commander_controls(parent: VBoxContainer) -> void:
	_command_buttons.clear();parent.add_child(_label("ORDERS",11,T.MUTED))
	var grid:=GridContainer.new();grid.columns=3;grid.add_theme_constant_override("h_separation",4);grid.add_theme_constant_override("v_separation",4);parent.add_child(grid)
	for key in ["move","attack","hold","retreat","focus","skill"]:
		var labels: Dictionary={"move":"Move [M]","attack":"Attack [A]","hold":"Stop [S]","retreat":"Retreat [R]","focus":"Focus [F]","skill":"Skill [Q]"}
		var button:=_button(labels[key],func():_classic_command(key),grid,84);button.custom_minimum_size.y=32;button.add_theme_font_size_override("font_size",13)
		_command_buttons[key]=button
		if key=="attack":button.tooltip_text="Click an enemy to attack, or terrain to attack-move."
		if key=="skill":skill_button=button
	commander_label=_label("",14,T.WORLD_ACCENT);commander_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;commander_label.visible=false;parent.add_child(commander_label)
	commander_bonus=_label("",12,T.MUTED);commander_bonus.visible=false;parent.add_child(commander_bonus)
	var row:=HBoxContainer.new();parent.add_child(row)
	_button("Details",func():open_stats(_active_army),row,70).custom_minimum_size.y=24
	_button("Commander",func():_show_commander_choice(),row,96).custom_minimum_size.y=24
	for button in row.get_children():button.add_theme_font_size_override("font_size",12)

func cast_selected_skill() -> void:
	if app.screen!="campaign" or map.controller.selected_armies.is_empty():return
	_active_army=map.controller.selected_armies[0]
	_cancel_target_mode()
	var d: Dictionary=map.simulation.commander_profile(_active_army)
	if d.is_empty():return
	if map.simulation.skill_remaining_ticks(d.id)>0:message("Skill is on cooldown.",true);return
	if d.effect in ["sweep","volley"]:_arm_target_mode("skill");return
	_submit_classic_skill("")

func _refresh_commander_controls(ids: Array) -> void:
	var id: String=ids[0];var sim=map.simulation;var d: Dictionary=sim.commander_profile(id)
	if d.is_empty():return
	if _commander_selection!=id+d.id:
		_commander_selection=id+d.id;commander_portrait.texture=load("res://"+d.portrait) as Texture2D
		commander_portrait.visible=true;commander_portrait.set_meta("commander_id",d.id);commander_portrait.tooltip_text=d.name
	commander_name.text=d.name if ids.size()==1 else d.name+" | first unit"
	commander_str.text=str(d.str);commander_lead.text=str(d.lead)
	commander_str.tooltip_text="STR %d: %d%% skill strength."%[d.str,d.str_percent]
	commander_lead.tooltip_text="LEAD %d: %d%% army power and protection."%[d.lead,d.lead_percent]
	commander_label.text=d.skill
	var queued: bool=sim.skill_queue.any(func(command):return command.army_id==id)
	var remaining: int=sim.skill_remaining_ticks(d.id)
	commander_bonus.text="Queued" if queued else "Cooldown %ds"%ceili(remaining/10.0) if remaining>0 else "Ready"
	commander_bonus.add_theme_color_override("font_color",T.SUCCESS if queued else T.MUTED)
	if _skill_feedback_army==id and Time.get_ticks_msec()<_skill_feedback_until:
		commander_bonus.text=_skill_feedback;commander_bonus.add_theme_color_override("font_color",T.ERROR if _skill_feedback_error else T.SUCCESS)
	skill_button.disabled=queued or remaining>0 or sim.armies[id].routed or sim.armies[id].transport_elapsed>0
	skill_button.tooltip_text=d.description+"\nSTR-adjusted power %d | cooldown %ds | LEAD %d%% army power/protection."%[d.skill_power,d.cooldown/10,d.lead_percent]
	for key in ["move","attack","hold","retreat","focus"]:_command_buttons[key].disabled=false

func refresh_screen() -> void:
	_last_screen=app.screen;hud.visible=app.screen=="campaign";overlay.visible=hud.visible
	if not hud.visible:overlay.clear_move_target();_cancel_target_mode()
	modal.visible=not hud.visible;_clear(modal)
	if hud.visible:_selection_signature="";update_view(1);return
	if app.screen=="stats":
		_build_stats_modal();return
	var shade:=ColorRect.new();shade.color=Color(0.05,0.06,0.05,0.52);shade.mouse_filter=Control.MOUSE_FILTER_STOP;modal.add_child(shade);shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center:=CenterContainer.new();modal.add_child(center);center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shell:=PanelContainer.new();shell.custom_minimum_size=Vector2(540,0);center.add_child(shell)
	var modal_style:=T.dock_surface(26,22,true);modal_style.bg_color=Color("18130e",0.96);modal_style.border_color=T.ACCENT;modal_style.set_border_width_all(2);modal_style.shadow_size=14
	shell.add_theme_stylebox_override("panel",modal_style)
	var scroll:=ScrollContainer.new();shell.add_child(scroll);scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	_modal_scroll=scroll;scroll.custom_minimum_size=Vector2(496,0)
	panel=VBoxContainer.new();panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(panel)
	panel.add_child(_label("STRATEGIC CAMPAIGN",12,T.ERROR))
	match app.screen:
		"menu":
			panel.add_child(_heading("Unification",46))
			panel.add_child(_label("Command your forces. Secure the eight cities.",15,T.MUTED));_line(panel)
			var can_resume: bool=app.campaign_started and app.result.is_empty()
			var start:=_button("New campaign",func():app.open_panel("faction");refresh_screen(),panel,0,not can_resume)
			start.custom_minimum_size.y=46
			var cont:=_button("Continue",func():app.resume();refresh_screen(),panel,0,can_resume);cont.disabled=not can_resume
			_button("Load campaign",func():app.open_panel("load");refresh_screen(),panel)
			var row:=HBoxContainer.new();panel.add_child(row)
			var settings:=_button("Settings",func():app.open_panel("settings");refresh_screen(),row);settings.size_flags_horizontal=Control.SIZE_EXPAND_FILL
			var exit:=_button("Exit",func():map.request_exit() if map.has_method("request_exit") else get_tree().quit(),row);exit.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		"faction":_faction_screen()
		"pause":
			panel.add_child(_heading("Campaign paused",34));panel.add_child(_label("The battlefield clock is stopped.",15,T.MUTED));_line(panel)
			_button("Resume campaign",func():app.resume();refresh_screen(),panel,0,true)
			_button("Save",func():app.open_panel("save");refresh_screen(),panel)
			_button("Load",func():app.open_panel("load");refresh_screen(),panel)
			_button("Settings",func():app.open_panel("settings");refresh_screen(),panel)
			_button("Unit stats",func():open_stats(),panel)
			_button("Controls",func():app.open_panel("help");refresh_screen(),panel)
			_button("Restart",func():_confirm("Restart campaign?","Unsaved progress will be lost.",func():map.start(app.session.faction,app.difficulty)),panel)
			_button("Main menu",func():app.open_panel("menu");refresh_screen(),panel)
		"save","load":_slots()
		"settings":
			panel.add_child(_heading("Settings",34));_line(panel)
			var labels:=CheckButton.new();labels.text="Settlement labels";labels.button_pressed=app.show_labels;panel.add_child(labels)
			labels.toggled.connect(func(value):app.show_labels=value;_save_settings())
			panel.add_child(_label("Map graphics: Low preset\nArrows / WASD pan  |  Wheel zoom  |  Middle drag pan\nSelected troops: A attack-move, S stop. Tab selects all troops.\nOpen menus use arrows for UI.",15,T.MUTED));_back()
		"help":
			panel.add_child(_heading("Field guide",34));_line(panel)
			var text:=_label("Recruit at a friendly city and choose an available commander. Select armies by click or drag.\nRight-click terrain to move, enemies to attack, cities to siege.\nEscort siege forces and keep supply routes open.\nCapture all eight cities and eliminate every enemy troop to win, including village guards and ferry passengers.\n\nArrows pan the camera on the battlefield. Open menus use them for UI only.\nWASD also pans; A is Attack when a formation is selected.\nCity health bars appear during combat or when walls / city HP are damaged.\n\nSelected units use their name and health bar instead of ground rings.\nMove, attack, siege and skill targets use a short-lived compact marker.\nA then ground: attack-move.\n\nSpace pause  |  H hold  |  R retreat  |  F focus\nCity: Q infantry  |  E archers  |  R cavalry  |  T siege
F focus city  |  F1 field guide (city selected)
Q officer skill (army selected)  |  Shift add selection\nCtrl+1–9 store group  |  1–9 recall\nF5 quicksave  |  F9 quickload  |  Esc menu",15,T.MUTED)
			text.text="Click a unit or its quick slot to select it. Drag a box or Shift-click to select several. Double-click a unit to select the same type on screen. Tab / Ctrl+A selects all field troops.\n\nRight-click terrain to move, an enemy to attack, or a city/gate to siege. Shift-right-click queues destinations. The minimap also accepts right-click orders. S stops and clears the queue; H is an alternate stop key. A then ground advances while engaging enemies. Direct move and retreat orders can disengage from melee.\n\nWei: blue. Shu: green. Wu: red. Selection is shown by the unit name, health bar, faction standard and HUD—there are no ground rings.\n\nCities fire defensive arrows automatically. Break walls and inner defenses, defeat the garrison, then hold a gate with infantry or cavalry to occupy it. Use siege crews with escorts and keep supplies available.\n\nArrows pan the camera. WASD also pans when a key is not used by the selected troops. Wheel zooms; middle drag pans.\n\nSpace: pause | Q: skill | R: retreat | F: focus\nCtrl+1–9: store group | 1–9: recall group\nF1: guide | F5: save | F9: load | Esc: menu"
			text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;panel.add_child(text);_back()
		"result":
			panel.add_child(_heading("Region unified" if app.result=="victory" else "Campaign lost",38));_line(panel)
			var data: Dictionary=app.session.summary()
			panel.add_child(_label("%s  |  %d cities controlled  |  %d troops"%[data.faction.capitalize(),data.cities,data.troops],15,T.MUTED))
			if app.result=="victory":_button("Continue campaign",func():app.continue_campaign();refresh_screen(),panel,0,true)
			_button("New campaign",func():app.open_panel("faction");refresh_screen(),panel,0,app.result!="victory")
			_button("Main menu",func():app.open_panel("menu");refresh_screen(),panel)
	call_deferred("_fit_modal")

func _back() -> void:_button("Back",func():app.back();refresh_screen(),panel)
func _faction_screen() -> void:
	panel.add_child(_heading("Choose a faction",34));panel.add_child(_label("One region  |  eight cities  |  three rivals",15,T.MUTED));_line(panel)
	var row:=HBoxContainer.new();panel.add_child(row)
	for id in ["wei","shu","wu"]:
		var button:=_button(id.capitalize(),func():faction=id;refresh_screen(),row,150)
		button.toggle_mode=true;button.button_pressed=faction==id;button.add_theme_color_override("font_color",T.PANEL_FACTION[id])
	var description: Dictionary={"wei":"Wei starts in the centre and east, with three cities.","shu":"Shu holds the western approaches and three cities.","wu":"Wu begins with two southern cities. Protect your supply."}
	var detail:=_label(description[faction],15,T.MUTED);detail.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;panel.add_child(detail)
	_line(panel)
	panel.add_child(_label("Four compact starting squads. Each squad has one commander.\nSelect a unit to see its commander's portrait, STR and LEAD.\nChoose an available commander when recruiting.",15,T.MUTED))
	var difficulty:=OptionButton.new();difficulty.custom_minimum_size.y=38;panel.add_child(difficulty)
	difficulty.add_item("Standard  |  360x280m tactical region")
	difficulty.add_item("Relaxed  |  more starting food")
	difficulty.selected=1 if challenge=="relaxed" else 0
	difficulty.item_selected.connect(func(i):challenge="relaxed" if i==1 else "standard")
	_button("Begin campaign",func():map.start(faction,challenge),panel,0,true);_back()

func open_stats(army_id: String="") -> void:
	_stats_army=army_id;app.open_panel("stats");refresh_screen()

func _build_stats_modal() -> void:
	_modal_scroll=null
	var center:=CenterContainer.new();modal.add_child(center);center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	field_guide=StatsPanel.new();center.add_child(field_guide)
	field_guide.configure(map.simulation,app.session.faction,func():app.back();refresh_screen())
	if not _stats_army.is_empty():field_guide.show_selected(_stats_army)
	var viewport: Vector2=get_viewport().get_visible_rect().size
	field_guide.custom_minimum_size=Vector2(minf(860,viewport.x-40),minf(610,viewport.y-60))

func _slots() -> void:
	var saving: bool=app.screen=="save"
	panel.add_child(_heading("Save campaign" if saving else "Load campaign",34));_line(panel)
	var metadata: Dictionary={}
	var schema: int=14 if map.simulation.tactical_rts else 13 if map.simulation.traditional_rts else 12
	for slot in app.Store.list_slots(app.session.save_directory):
		if not saving:metadata[slot.slot]=slot
		elif slot.schema==schema:metadata[slot.slot%5]=slot
	var feedback:=_label("",14,T.ERROR);panel.add_child(feedback)
	for slot in range(5 if saving else app.Store.LOAD_SLOT_COUNT):
		if slot>=5 and not metadata.has(slot):continue
		var display_slot: int=slot%5
		var text: String=("Legacy schema %d — "%int(metadata[slot].get("schema",0)) if slot>=5 else "")+("Autosave" if display_slot==0 else "Slot %d"%display_slot)
		if metadata.has(slot):text+="   %s  |  %02d:%02d"%[metadata[slot].faction.capitalize(),metadata[slot].tick/600,(metadata[slot].tick/10)%60]
		else:text+="   Empty"
		var button:=_button(text,func():
			var error: String=app.save_campaign(slot) if saving else app.load_campaign(slot)
			if not error.is_empty():feedback.text=error;return
			if saving:feedback.text="Campaign saved.";feedback.add_theme_color_override("font_color",T.SUCCESS)
			else:refresh_screen(),panel)
		button.disabled=(slot==0 if saving else not metadata.has(slot) or not metadata[slot].valid_metadata)
	_back()

func _load_settings() -> void:
	if not FileAccess.file_exists("user://campaign-settings.json"):return
	var data=JSON.parse_string(FileAccess.get_file_as_string("user://campaign-settings.json"))
	if not data is Dictionary:return
	if data.get("labels") is bool:app.show_labels=data.labels
	if data.get("supply") is bool:app.show_supply=data.supply
func _save_settings() -> void:
	var file:=FileAccess.open("user://campaign-settings.json",FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify({"labels":app.show_labels,"supply":app.show_supply}));file.close()
func _confirm(title: String, text: String, action: Callable) -> void:
	confirmation.title=title;confirmation.dialog_text=title+"

"+text;_confirmed_action=action;confirmation.popup_centered()
func _fit_modal() -> void:
	if not is_instance_valid(_modal_scroll) or not is_instance_valid(panel):return
	_modal_scroll.custom_minimum_size.y=minf(panel.get_combined_minimum_size().y,get_viewport().get_visible_rect().size.y-80)

func _refresh_recruit_commander() -> String:
	var sim=map.simulation;var available: Array=sim.available_commanders(app.session.faction)
	var previous: String=str(recruit_commander_picker.get_item_metadata(recruit_commander_picker.selected)) if recruit_commander_picker.item_count>0 and recruit_commander_picker.selected>=0 else ""
	var signature: String=app.session.faction+str(available)
	if recruit_commander_picker.get_meta("signature","")!=signature:
		recruit_commander_picker.set_meta("signature",signature);recruit_commander_picker.clear()
		recruit_commander_picker.add_item("Choose a commander" if not available.is_empty() else "No commander available");recruit_commander_picker.set_item_metadata(0,"")
		for id in available:
			var d: Dictionary=sim.Officers.DEFINITIONS[id]
			recruit_commander_picker.add_item(d.name+" | STR %d LEAD %d"%[d.str,d.lead]);recruit_commander_picker.set_item_metadata(recruit_commander_picker.item_count-1,id)
			if id==previous:recruit_commander_picker.select(recruit_commander_picker.item_count-1)
		if recruit_commander_picker.selected<=0 and not available.is_empty():
			recruit_commander_picker.select(1)
		recruit_commander_picker.disabled=available.is_empty()
	return str(recruit_commander_picker.get_item_metadata(recruit_commander_picker.selected)) if recruit_commander_picker.selected>=0 else ""

func _classic_command(key: String) -> void:
	if map.controller.selected_armies.is_empty():return
	if key in ["move","attack"]:_arm_target_mode(key);return
	if key=="skill":cast_selected_skill();return
	_cancel_target_mode()
	match key:
		"hold":map.controller.hold_selected();overlay.clear_move_target()
		"retreat":map.controller.retreat_selected()
		"focus":map.controller.focus_selection()
	_last_hud_tick=-1;update_view(1)

func _arm_target_mode(mode: String) -> void:
	map.controller._dragging=false
	_target_mode=mode;_mode_issuer=map.controller.selected_armies[0]
	_mode_armies=map.controller.selected_armies.duplicate()
	Input.set_default_cursor_shape(Input.CURSOR_CROSS)
	message("Choose an enemy target for the skill." if mode=="skill" else "Choose a move destination." if mode=="move" else "Choose terrain to attack-move, or an enemy target.",false)

func _cancel_target_mode() -> void:
	_target_mode="";_mode_issuer="";_mode_armies.clear();Input.set_default_cursor_shape(Input.CURSOR_ARROW)

func _validate_target_mode() -> void:
	if _target_mode.is_empty():return
	if _roster_open or _mode_armies!=map.controller.selected_armies or _has_ui_popup(root):
		_cancel_target_mode();message("Targeting cancelled.")

func _submit_classic_skill(target: String) -> void:
	if map.controller.selected_armies.is_empty():return
	var id: String=map.controller.selected_armies[0]
	if not _mode_issuer.is_empty() and _mode_issuer!=id:_cancel_target_mode();return
	_skill_sequence+=1
	var command_id: String="player-skill-%d-%d"%[map.simulation.tick,_skill_sequence]
	while map.simulation.command_ids.has(command_id):
		_skill_sequence+=1;command_id="player-skill-%d-%d"%[map.simulation.tick,_skill_sequence]
	var error: String=map.simulation.submit_skill(app.session.faction,id,target,command_id)
	_skill_feedback_army=id;_skill_feedback_error=not error.is_empty();_skill_feedback="Skill queued" if error.is_empty() else error;_skill_feedback_until=Time.get_ticks_msec()+2200
	if error.is_empty():
		var d: Dictionary=map.simulation.commander_profile(id);skill_order_accepted.emit({"kind":"army","id":target if d.effect in ["sweep","volley"] else id});_cancel_target_mode()
	else:overlay.clear_move_target()
	message(error,not error.is_empty(),"Skill queued.");_last_hud_tick=-1;update_view(1)

func _show_commander_choice() -> void:
	if map.controller.selected_armies.is_empty():return
	_cancel_target_mode()
	_active_army=map.controller.selected_armies[0]
	if is_instance_valid(_commander_dialog):_commander_dialog.queue_free()
	_commander_dialog=AcceptDialog.new();_commander_dialog.title="Choose commander";_commander_dialog.theme=ClassicSkin.theme();_commander_dialog.size=Vector2i(340,130);root.add_child(_commander_dialog)
	var picker:=OptionButton.new();picker.custom_minimum_size=Vector2(300,36);_commander_dialog.add_child(picker)
	var sim=map.simulation;var choices: Array=[sim.officer_for(_active_army)]+sim.available_commanders(app.session.faction)
	for id in choices:
		var d: Dictionary=sim.Officers.DEFINITIONS[id]
		picker.add_item(d.name+" | STR %d LEAD %d"%[d.str,d.lead]);picker.set_item_metadata(picker.item_count-1,id)
	_commander_dialog.confirmed.connect(func():
		var error: String=sim.assign_officer(app.session.faction,str(picker.get_item_metadata(picker.selected)),_active_army)
		message(error,not error.is_empty(),"Commander assigned.");_commander_selection="";update_view(1))
	_commander_dialog.popup_centered()
