extends RefCounted
## Original ROTK XIV RGBA only. Nine-slicing is layout; no ornament pixels are generated.
const T=preload("res://ui_tokens.gd")
const CATALOG="res://hud-art/art-catalog.json"
static var _entries: Dictionary={}
static var _textures: Dictionary={}

static func _ensure() -> void:
	if not _entries.is_empty():return
	var data=JSON.parse_string(FileAccess.get_file_as_string(CATALOG))
	if not data is Dictionary:return
	for entry in data.get("files",[]):_entries[entry.key]=entry

static func texture(key: String) -> Texture2D:
	_ensure()
	if not _entries.has(key):return null
	if not _textures.has(key):_textures[key]=load("res://hud-art/"+str(_entries[key].file)) as Texture2D
	return _textures[key]

static func panel(key: String="panel_gray", horizontal: int=10, vertical: int=8, preserve_corner_space: bool=false) -> StyleBoxTexture:
	_ensure()
	var style:=StyleBoxTexture.new();style.texture=texture(key);style.draw_center=true
	var margins: Array=_entries.get(key,{}).get("margins",[4,4,4,4])
	for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:
		style.set_texture_margin(side,float(margins[side]))
		style.set_content_margin(side,float(margins[side]) if preserve_corner_space else float(horizontal if side in [SIDE_LEFT,SIDE_RIGHT] else vertical))
	return style

static func theme() -> Theme:
	var result: Theme=T.theme()
	for type in ["Button","OptionButton"]:
		for state in ["normal","hover","pressed","hover_pressed","disabled"]:
			var key: String="button_pressed" if state in ["pressed","hover_pressed"] else "button_disabled" if state=="disabled" else "button_hover" if state=="hover" else "button_normal"
			result.set_stylebox(state,type,panel(key,8,4))
		result.set_stylebox("focus",type,panel("frame_gold",8,4))
		result.set_color("font_color",type,T.INK);result.set_color("font_hover_color",type,T.WORLD_ACCENT)
		result.set_color("font_focus_color",type,T.WORLD_ACCENT);result.set_color("font_pressed_color",type,T.ACCENT)
		result.set_color("font_disabled_color",type,T.MUTED)
	return result

static func primary_theme() -> Theme:
	# Primary actions use the same source-art states as the rest of the menu.
	return theme()
