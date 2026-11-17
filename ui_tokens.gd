extends RefCounted
## Authored mineral-green flat panels. Transparent carriers preserve map-visible gaps.
const PAPER=Color("2e2418",0.94)
const PANEL=Color("1c1610",0.92)
const RAISED=Color("120e0a",0.94)
const RULE=Color("b89650")
const INK=Color("f6ebd2")
const MUTED=Color("cbbd9d")
const ACCENT=Color("d4b66a")
const PRIMARY_INK=Color("1e1508")
const ERROR=Color("f4a68e")
const SUCCESS=Color("a8db96")
const DOCK_BASE=Color("18130e",0.93)
const DOCK_RULE=Color("b6934c",0.88)
const WORLD_BASE=Color("0e141b",0.90)
const WORLD_MUTED=Color("c5d2d8")
const WORLD_ACCENT=Color("f0dc9c")
const WORLD_ERROR=Color("ffab9c")
const WORLD_SUCCESS=Color("a8e2b8")
const FACTION={"wei":Color("559dff"),"shu":Color("58ec83"),"wu":Color("ff6560")}
const PANEL_FACTION=FACTION
static func font() -> Font:return load("res://fonts/SourceSans3-Semibold.ttf")
static func display_font() -> Font:return load("res://fonts/Marcellus-Regular.ttf")
static func box(color: Color, border: Color=Color.TRANSPARENT) -> StyleBoxFlat:
	var style:=StyleBoxFlat.new();style.bg_color=color;style.border_color=border;style.shadow_color=Color(0,0,0,0.38)
	style.shadow_size=4 if border.a>0 and color.a>0.5 else 0;style.shadow_offset=Vector2(0,2)
	style.set_corner_radius_all(3);style.anti_aliasing=true
	style.set_border_width_all(1 if border.a>0 else 0);style.set_content_margin_all(12)
	return style
static func surface(kind: String="panel", horizontal: int=14, vertical: int=12) -> StyleBoxFlat:
	if kind in ["normal","hover","pressed","disabled","focus","hover_pressed"]:return state(kind,horizontal,vertical)
	var style:=box(RAISED if kind=="inset" else PAPER if kind=="menu" else PANEL,DOCK_RULE)
	if kind!="inset":style.border_width_top=2
	style.content_margin_left=horizontal;style.content_margin_right=horizontal
	style.content_margin_top=vertical;style.content_margin_bottom=vertical
	return style
static func state(kind: String, horizontal: int=10, vertical: int=6) -> StyleBoxFlat:
	var fills: Dictionary={"normal":PAPER,"hover":Color("463723",0.96),"pressed":Color("1a140c",0.96),"hover_pressed":Color("261d11",0.96),"disabled":RAISED,"focus":Color.TRANSPARENT}
	var style:=box(fills[kind],ACCENT if kind in ["hover","pressed","hover_pressed","focus"] else DOCK_RULE)
	style.shadow_size=2 if kind in ["normal","hover"] else 0
	style.content_margin_left=horizontal;style.content_margin_right=horizontal
	style.content_margin_top=vertical;style.content_margin_bottom=vertical
	if kind=="focus":style.set_border_width_all(2)
	return style
static func primary_theme() -> Theme:
	var result:=theme()
	var fills: Dictionary={"normal":ACCENT,"hover":Color("e5ca83"),"pressed":Color("b9984e"),"hover_pressed":Color("c9aa5c"),"disabled":RAISED}
	for kind in fills:
		var style:=state(kind);style.bg_color=fills[kind];style.border_color=DOCK_RULE if kind=="disabled" else PRIMARY_INK
		result.set_stylebox(kind,"Button",style)
	var focus:=state("focus");focus.border_color=PRIMARY_INK;focus.set_border_width_all(2)
	result.set_stylebox("focus","Button",focus)
	for property in ["font_color","font_hover_color","font_pressed_color","font_hover_pressed_color","font_focus_color","icon_normal_color","icon_hover_color","icon_pressed_color","icon_hover_pressed_color","icon_focus_color"]:result.set_color(property,"Button",PRIMARY_INK)
	result.set_color("font_disabled_color","Button",MUTED);result.set_color("icon_disabled_color","Button",MUTED)
	return result
static func theme() -> Theme:
	var result:=Theme.new();result.default_font=font();result.default_font_size=18
	for type in ["Label","Button","OptionButton","PopupMenu","CheckButton","CheckBox","RichTextLabel","TooltipLabel","AcceptDialog"]:
		result.set_color("font_color",type,INK)
		result.set_color("font_outline_color",type,Color.TRANSPARENT);result.set_constant("outline_size",type,0)
		result.set_color("font_shadow_color",type,Color.TRANSPARENT)
		result.set_constant("shadow_offset_x",type,0);result.set_constant("shadow_offset_y",type,0)
	for type in ["Button","OptionButton","CheckButton","CheckBox"]:
		for kind in ["normal","hover","pressed","disabled","focus","hover_pressed"]:result.set_stylebox(kind,type,state(kind))
		for property in ["font_hover_color","font_pressed_color","font_hover_pressed_color","font_focus_color"]:result.set_color(property,type,INK)
		result.set_color("font_disabled_color",type,MUTED)
		result.set_color("icon_normal_color",type,INK);result.set_color("icon_hover_color",type,INK)
		result.set_color("icon_pressed_color",type,INK);result.set_color("icon_disabled_color",type,MUTED)
	for type in ["PanelContainer","Panel","PopupMenu","TooltipPanel","AcceptDialog","Window"]:result.set_stylebox("panel",type,surface())
	result.set_stylebox("hover","PopupMenu",state("hover",8,5));result.set_color("font_hover_color","PopupMenu",INK)
	result.set_color("font_disabled_color","PopupMenu",MUTED)
	result.set_color("title_color","Window",INK);result.set_color("font_color","TooltipLabel",INK)
	result.set_font_size("font_size","TooltipLabel",14)
	result.set_stylebox("background","ProgressBar",surface("inset",0,0))
	result.set_stylebox("fill","ProgressBar",box(ACCENT));result.set_color("font_color","ProgressBar",INK)
	for type in ["HScrollBar","VScrollBar"]:
		result.set_stylebox("scroll",type,box(RAISED))
		for kind in ["grabber","grabber_highlight","grabber_pressed"]:result.set_stylebox(kind,type,box(MUTED if kind=="grabber" else ACCENT))
	for type in ["HSeparator","VSeparator"]:
		var rule:=StyleBoxLine.new();rule.color=DOCK_RULE;rule.thickness=1;rule.vertical=type=="VSeparator"
		result.set_stylebox("separator",type,rule)
	result.set_constant("separation","VBoxContainer",10);result.set_constant("separation","HBoxContainer",8)
	return result
static func flat_bar() -> StyleBoxFlat:
	var style:=box(PANEL,DOCK_RULE);style.content_margin_top=3;style.content_margin_bottom=3
	return style
static func flat_state(kind: String) -> StyleBoxFlat:
	var style:=state(kind,8,3)
	if kind in ["normal","disabled"]:style.bg_color=Color.TRANSPARENT;style.set_border_width_all(0)
	if kind in ["pressed","hover_pressed"]:style.bg_color=Color("2a2013");style.set_border_width_all(0);style.border_width_bottom=2
	return style
static func flat_theme() -> Theme:
	var result:=theme()
	for type in ["Button","OptionButton"]:
		for kind in ["normal","hover","pressed","disabled","focus","hover_pressed"]:result.set_stylebox(kind,type,flat_state(kind))
	return result
static func dock_surface(horizontal: int=12, vertical: int=8, framed: bool=true) -> StyleBoxFlat:
	var style:=box(DOCK_BASE,DOCK_RULE if framed else Color.TRANSPARENT)
	if framed:
		style.border_width_top=2
		style.shadow_color=Color(0,0,0,0.45);style.shadow_size=6;style.shadow_offset=Vector2(0,2)
	style.content_margin_left=horizontal;style.content_margin_right=horizontal
	style.content_margin_top=vertical;style.content_margin_bottom=vertical
	return style
static func dock_state(kind: String) -> StyleBoxFlat:return state(kind)
static func dock_theme() -> Theme:return theme()
static func compact_dock() -> StyleBoxFlat:
	var style:=dock_surface();style.content_margin_bottom=20;return style
static func compact_commands() -> StyleBoxFlat:
	var style:=dock_surface(8,8);style.content_margin_bottom=20;return style
static func split_shell() -> StyleBoxFlat:
	var style:=box(Color.TRANSPARENT);style.set_content_margin_all(0);return style
