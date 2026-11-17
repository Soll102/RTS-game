extends Control
## Authored flat edge ornament; not recovered ROTK XIV art.
const THREAD=Color("6c7d65",.65)
const BRASS=Color("94744b",.65)
var panels: Array[Rect2]=[]

func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	for rect in panels:
		var left: float=rect.position.x+7
		var right: float=rect.end.x-7
		var top: float=rect.position.y+3
		var bottom: float=rect.end.y-10
		# Short key-fret corners leave all content and map pixels unobstructed.
		for edge in [left,right]:
			var direction: float=1 if edge==left else -1
			var p:=Vector2(edge,top)
			var points:=PackedVector2Array([p+Vector2(0,6),p,p+Vector2(21*direction,0),p+Vector2(21*direction,3),p+Vector2(13*direction,3)])
			draw_polyline(points,THREAD,1,true)
			var q:=Vector2(edge,bottom)
			var key:=PackedVector2Array([q+Vector2(0,-3),q+Vector2(0,3),q+Vector2(24*direction,3),q+Vector2(24*direction,-3),q+Vector2(16*direction,-3),q+Vector2(16*direction,0)])
			draw_polyline(key,BRASS,1,true)
		var middle: float=(left+right)*.5
		draw_line(Vector2(left+31,bottom),Vector2(middle-18,bottom),THREAD,1,true)
		draw_line(Vector2(middle+18,bottom),Vector2(right-31,bottom),THREAD,1,true)
		for offset in [-10,0,10]:
			var center:=Vector2(middle+offset,bottom)
			var radius: float=3 if offset==0 else 2
			var diamond:=PackedVector2Array([center+Vector2(-radius,0),center+Vector2(0,-radius),center+Vector2(radius,0),center+Vector2(0,radius),center+Vector2(-radius,0)])
			draw_polyline(diamond,BRASS,1,true)
