extends RefCounted
## One captured simulation tick; sample its arc length at any render rate.
var points: Array=[]
var lengths: PackedFloat64Array=PackedFloat64Array()
var distance: float=0.0
var start_slope: float=0.0
var end_slope: float=0.0
var tick: int=-1

func capture(trace: Array, current_tick: int, continuing: bool) -> void:
	var previous_distance: float=distance if tick==current_tick-1 else 0.0
	tick=current_tick;points=trace.duplicate();lengths.clear();distance=0.0
	for i in range(points.size()-1):
		var length: float=points[i].distance_to(points[i+1]);lengths.append(length);distance+=length
	start_slope=clampf(previous_distance/maxf(.000001,distance),0.0,1.5)
	end_slope=1.0 if continuing else 0.0

func sample(alpha: float) -> Vector3:
	if points.is_empty():return Vector3.ZERO
	var a: float=clampf(alpha,0.0,1.0)
	var squared: float=a*a;var cubed: float=squared*a
	# Monotone Hermite time mapping eases start/arrival without leaving a leg.
	var fraction: float=(-2.0*cubed+3.0*squared)+(cubed-2.0*squared+a)*start_slope+(cubed-squared)*end_slope
	var remaining: float=clampf(fraction,0.0,1.0)*distance
	for i in range(lengths.size()):
		if remaining<=lengths[i]:return points[i].lerp(points[i+1],remaining/maxf(.000001,lengths[i]))
		remaining-=lengths[i]
	return points[-1]
