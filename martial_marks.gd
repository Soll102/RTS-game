extends RefCounted
## Authored HUD line glyphs; these are not recovered ROTK XIV widgets.
const M=preload("res://martial_tokens.gd")
static func line(canvas: Control, a: Vector2, b: Vector2, color: Color, width: float=M.STROKE) -> void:
	canvas.draw_line(a,b,color,width,true)
static func diamond(canvas: Control, p: Vector2, radius: float, color: Color) -> void:
	canvas.draw_polyline(PackedVector2Array([p+Vector2(0,-radius),p+Vector2(radius,0),p+Vector2(0,radius),p+Vector2(-radius,0),p+Vector2(0,-radius)]),color,M.STROKE,true)
static func type_icon(canvas: Control, p: Vector2, kind: String, color: Color) -> void:
	if kind=="infantry":
		line(canvas,p+Vector2(-5,5),p+Vector2(5,-5),color);line(canvas,p+Vector2(-5,-5),p+Vector2(5,5),color)
		line(canvas,p+Vector2(-5,1),p+Vector2(-1,5),color);line(canvas,p+Vector2(1,5),p+Vector2(5,1),color)
	elif kind=="archers":
		canvas.draw_polyline(PackedVector2Array([p+Vector2(-3,-6),p+Vector2(3,-3),p+Vector2(5,0),p+Vector2(3,3),p+Vector2(-3,6)]),color,M.STROKE,true)
		line(canvas,p+Vector2(-3,-6),p+Vector2(-3,6),color);line(canvas,p+Vector2(-6,0),p+Vector2(7,0),color)
	elif kind=="cavalry":
		canvas.draw_polyline(PackedVector2Array([p+Vector2(-5,6),p+Vector2(-3,0),p+Vector2(-4,-5),p+Vector2(0,-3),p+Vector2(4,-2),p+Vector2(5,1),p+Vector2(1,2),p+Vector2(0,6)]),color,M.STROKE,true)
	elif kind=="hero":
		diamond(canvas,p,6,color);line(canvas,p+Vector2(0,-7),p+Vector2(0,7),color)
	else:
		line(canvas,p+Vector2(-5,2),p+Vector2(5,2),color);line(canvas,p+Vector2(-2,2),p+Vector2(3,-6),color)
		line(canvas,p+Vector2(-4,-4),p+Vector2(5,-4),color)
		canvas.draw_arc(p+Vector2(-3,5),2,0,TAU,12,color,M.STROKE,true);canvas.draw_arc(p+Vector2(4,5),2,0,TAU,12,color,M.STROKE,true)
static func flag(canvas: Control, p: Vector2, color: Color) -> void:
	line(canvas,p+Vector2(0,5),p+Vector2(0,-16),M.INK,3.5)
	line(canvas,p+Vector2(0,5),p+Vector2(0,-16),color)
	var cloth:=PackedVector2Array([p+Vector2(0,-16),p+Vector2(12,-14),p+Vector2(9,-9),p+Vector2(0,-10)])
	canvas.draw_colored_polygon(cloth,M.BANNER);canvas.draw_polyline(PackedVector2Array([cloth[0],cloth[1],cloth[2],cloth[3],cloth[0]]),color,M.STROKE,true)
	diamond(canvas,p,4,color)
static func unit_banner(canvas: Control, center: Vector2, kind: String, faction: String, troops: int, morale: int, selected: bool, font: Font) -> Rect2:
	var box:=Rect2(center-M.HUD_SIZE*.5,M.HUD_SIZE)
	var p: Vector2=box.position;var s: Vector2=box.size
	var points:=PackedVector2Array([p,p+Vector2(s.x-5,0),p+Vector2(s.x,5),p+s,p+Vector2(5,s.y),p+Vector2(0,s.y-5)])
	canvas.draw_colored_polygon(points,M.BANNER)
	canvas.draw_polyline(PackedVector2Array([points[0],points[1],points[2],points[3],points[4],points[5],points[0]]),M.TEXT if selected else M.EDGE,1.5 if selected else 1.0,true)
	canvas.draw_rect(Rect2(p+Vector2(4,4),Vector2(14,17)),M.FACTION[faction])
	canvas.draw_string(font,p+Vector2(7,17),M.FACTION_LETTER[faction],HORIZONTAL_ALIGNMENT_LEFT,-1,11,M.SEAL_INK)
	type_icon(canvas,p+Vector2(28,13),kind,M.TEXT)
	canvas.draw_string(font,p+Vector2(38,18),str(troops),HORIZONTAL_ALIGNMENT_LEFT,-1,13,M.TEXT)
	for i in range(5):
		var color: Color=M.MORALE if morale>i*20 else M.INK
		line(canvas,p+Vector2(22+i*9,26),p+Vector2(28+i*9,26),color,2)
	return box
