extends RefCounted
## Persistent local offset. Repeated renders never advance the steering clock.
const RESPONSE: float=7.0
const MAX_SPEED: float=2.4
var offset: Vector3=Vector3.ZERO
var last_clock: float=-1.0

static func clear_segment(start: Vector3, finish: Vector3, half: Vector2, allowed: Callable) -> bool:
	if not allowed.is_valid():return true
	var length: float=Vector2(finish.x-start.x,finish.z-start.z).length()
	var steps: int=maxi(1,ceili(length/.35))
	for i in range(1,steps+1):
		if not allowed.call(start.lerp(finish,float(i)/steps),half):return false
	return true

func sample(base: Vector3, desired: Vector3, clock: float, reference_speed: float, half: Vector2, allowed: Callable) -> Vector3:
	desired.y=0.0
	if last_clock<0.0 or clock<last_clock:
		offset=desired;last_clock=clock;return base+offset
	var elapsed: float=clock-last_clock
	if elapsed<=.000001:return base+offset
	last_clock=clock
	var goal: Vector3=offset.lerp(desired,1.0-exp(-RESPONSE*elapsed))
	var candidate: Vector3=offset.move_toward(goal,minf(MAX_SPEED,maxf(.8,reference_speed*.45))*elapsed)
	if clear_segment(base+offset,base+candidate,half,allowed):offset=candidate
	return base+offset
