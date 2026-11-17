extends PanelContainer
## Flat jade guide with one original commander portrait for the selected formation.
const Stats=preload("res://unit_stats.gd")
const T=preload("res://ui_tokens.gd")
signal close_requested
var simulation: RefCounted
var faction: String=""
var selected_army: String=""
var active_type: String="compare"
var _close_action: Callable
var _body: VBoxContainer
var _scroll: ScrollContainer
var _tabs: HBoxContainer
var _title: Label
var _summary: Label
var _built: bool=false
var _poll_elapsed: float=0.0
var _state_signature: String=""

func configure(sim: RefCounted, player: String="", close_action: Callable=Callable()) -> void:
	simulation=sim;faction=player;_close_action=close_action
	if not _built:_build()
	_refresh()

func open_type(kind: String) -> void:
	active_type=kind if kind in Stats.types() else "compare"
	selected_army="";_refresh()

func show_selected(army_id: String) -> void:
	selected_army=army_id
	var profile: Dictionary=Stats.selected_profile(simulation,army_id)
	active_type=str(profile.get("kind","compare"));_refresh()

func refresh_current() -> void:
	_refresh(true)

func _process(delta: float) -> void:
	if not _built or not is_visible_in_tree() or selected_army.is_empty():return
	_poll_elapsed+=delta
	if _poll_elapsed<.5:return
	_poll_elapsed=0.0
	var profile: Dictionary=Stats.selected_profile(simulation,selected_army)
	var signature: String=str(profile)
	if signature!=_state_signature:
		_state_signature=signature;_refresh(true)

func _label(text: String, size: int=16, color: Color=T.INK) -> Label:
	var label:=Label.new();label.text=text;label.add_theme_font_size_override("font_size",size)
	label.add_theme_color_override("font_color",color);label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	return label

func _build() -> void:
	_built=true;theme=T.theme();custom_minimum_size=Vector2(760,450)
	add_theme_stylebox_override("panel",T.surface("panel",18,14))
	var layout:=VBoxContainer.new();layout.size_flags_horizontal=Control.SIZE_EXPAND_FILL;add_child(layout)
	var heading:=HBoxContainer.new();layout.add_child(heading)
	_title=_label("Unit field guide",30);_title.add_theme_font_override("font",T.display_font());_title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;heading.add_child(_title)
	var close:=Button.new();close.text="Close [Esc]";heading.add_child(close)
	close.pressed.connect(func():
		close_requested.emit()
		if _close_action.is_valid():_close_action.call())
	_summary=_label("Base unit profiles and effective selected values. Time follows the simulation clock.",14,T.MUTED);layout.add_child(_summary)
	_tabs=HBoxContainer.new();layout.add_child(_tabs)
	var entries: Array=["compare"]+Stats.types()
	for kind in entries:
		var button:=Button.new();button.text="Compare" if kind=="compare" else Stats.NAMES[kind]
		button.toggle_mode=true;button.size_flags_horizontal=Control.SIZE_EXPAND_FILL;button.add_theme_font_size_override("font_size",15)
		button.set_meta("stats_type",kind);_tabs.add_child(button)
		button.pressed.connect(func():open_type(kind))
	_scroll=ScrollContainer.new();_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;_scroll.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;layout.add_child(_scroll)
	_body=VBoxContainer.new();_body.size_flags_horizontal=Control.SIZE_EXPAND_FILL;_scroll.add_child(_body)
	var footer:=_label("One commander per living unit. LEAD strengthens troops; STR strengthens commander skills.",13,T.MUTED);layout.add_child(footer)

func _refresh(preserve_scroll: bool=false) -> void:
	if not _built:return
	var old_scroll: int=_scroll.scroll_vertical if preserve_scroll else 0
	for child in _body.get_children():_body.remove_child(child);child.queue_free()
	for button in _tabs.get_children():button.set_pressed_no_signal(button.get_meta("stats_type")==active_type)
	if active_type=="compare":
		var amount: int=Stats.base_profile("infantry",simulation).default_recruit_troops
		_title.text="Unit field guide";_summary.text="Recruitment costs are for %d troops. Values use full morale, carried food and open ground."%amount
		_build_comparison();return
	var profile: Dictionary=Stats.selected_profile(simulation,selected_army) if not selected_army.is_empty() else Stats.base_profile(active_type,simulation,"")
	if profile.is_empty():_body.add_child(_label("This entity is unavailable."));return
	_title.text=profile.name
	_summary.text="Current formation and commander values." if profile.has("army_id") else "Base values use LEAD 50 and full morale."
	var commander: Dictionary=profile.get("commander",{})
	if not commander.is_empty():
		var identity:=HBoxContainer.new();identity.add_theme_constant_override("separation",14);_body.add_child(identity)
		var portrait:=TextureRect.new();portrait.name="OriginalCommanderPortrait";portrait.custom_minimum_size=Vector2(84,84)
		portrait.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;portrait.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.texture=load("res://"+str(commander.portrait)) as Texture2D;portrait.set_meta("commander_id",commander.id);identity.add_child(portrait)
		var caption:=_label("%s\nSTR %d  |  LEAD %d"%[commander.name,commander.str,commander.lead],22);identity.add_child(caption)
	for section in Stats.detail_sections(profile):
		var heading:=_label(section.title,20,T.ACCENT);_body.add_child(heading)
		var grid:=GridContainer.new();grid.columns=2;grid.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		grid.add_theme_constant_override("h_separation",20);grid.add_theme_constant_override("v_separation",9);_body.add_child(grid)
		for row in section.rows:
			var name:=_label(str(row[0]),15,T.MUTED);name.custom_minimum_size.x=174;grid.add_child(name)
			var value:=_label(str(row[1]),15);value.size_flags_horizontal=Control.SIZE_EXPAND_FILL;grid.add_child(value)
		_body.add_child(HSeparator.new())
	_scroll.set_deferred("scroll_vertical",old_scroll)

func _build_comparison() -> void:
	var grid:=GridContainer.new();grid.columns=8;grid.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation",10);grid.add_theme_constant_override("v_separation",14);_body.add_child(grid)
	var amount: int=Stats.base_profile("infantry",simulation).default_recruit_troops
	for header in ["Type","Food / %d"%amount,"Train","Speed","Range","Attack","Defense","Siege / s"]:
		var label:=_label(header,14,T.ACCENT);label.size_flags_horizontal=Control.SIZE_EXPAND_FILL;grid.add_child(label)
	for row in Stats.comparison_rows(simulation):
		for value in row:
			var label:=_label(str(value),15);label.size_flags_horizontal=Control.SIZE_EXPAND_FILL;grid.add_child(label)
	_body.add_child(HSeparator.new())
	for text in ["Field damage uses current strength × attack × morale, then type, stance, terrain, food and target-defense modifiers.",
		Stats.matchup_description(simulation),
		"LEAD increases formation damage, siege power and protection. STR increases skill damage, morale effects and buff bonuses.",
		"Type tabs show detailed rules. A selected entity view adds actual morale, food, stance, terrain, buffs and the movement budget before contact or ferry blocking."]:
		_body.add_child(_label(text,16,T.MUTED))
	_scroll.scroll_vertical=0
