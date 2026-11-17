extends RefCounted
## Presentation-only gait, driven by ground travel rather than queued orders.
var previous: Vector3=Vector3.INF
var last_clock: float=-1.0
var march_clock: float=0.0
var weight: float=0.0
var speed: float=0.0
var heading: float=0.0
var has_heading: bool=false
var detailed: bool=true

func sample(point: Vector3, clock: float, can_walk: bool, reference_speed: float, initial_heading: float=0.0, intent: Vector3=Vector3.ZERO) -> void:
	if not point.is_finite():return
	if not previous.is_finite() or clock<last_clock:
		previous=point;last_clock=clock;march_clock=0.0;weight=0.0;speed=0.0
		heading=initial_heading;has_heading=true;return
	var elapsed: float=clock-last_clock
	# Multiple syncs of a paused/subtick frame must retain the same pose.
	if elapsed<=.000001:return
	var travel: Vector3=point-previous;travel.y=0.0
	previous=point;last_clock=clock
	if travel.length()>maxf(4.0,elapsed*reference_speed*4.0):
		weight=0.0;speed=0.0;has_heading=false;return
	var walking: bool=can_walk and travel.length_squared()>.00000001
	var desired_speed: float=travel.length()/elapsed if walking else 0.0
	var response: float=1.0-exp(-elapsed*16.0)
	var travelled: float=desired_speed*elapsed+(speed-desired_speed)*response/16.0
	speed=lerpf(speed,desired_speed,response)
	weight=move_toward(weight,1.0 if walking else 0.0,elapsed*7.0)
	if weight>.001:
		# Integrate the speed response exactly, so frame size does not alter stride.
		march_clock+=clampf(travelled/maxf(1.0,reference_speed),0.0,elapsed*3.0)
	var facing_direction: Vector3=travel if walking else intent if can_walk else Vector3.ZERO
	facing_direction.y=0.0
	if facing_direction.length_squared()>.00000001:
		var facing: float=atan2(facing_direction.x,facing_direction.z)
		var difference: float=wrapf(facing-heading,-PI,PI)
		# Keep a reversal readable without an instantaneous 180-degree snap.
		heading+=clampf(difference*(1.0-exp(-elapsed*8.0)),-elapsed*PI,elapsed*PI)
		has_heading=true

func update_detail(distance: float) -> bool:
	# Avoid alternating detailed/rest poses at the old single 75 m boundary.
	if detailed and distance>84.0:detailed=false
	elif not detailed and distance<72.0:detailed=true
	return detailed
