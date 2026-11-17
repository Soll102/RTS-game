extends RefCounted
## Subtract only painted UI regions; split-panel gaps remain usable map space.
const Routes=preload("res://scripts/rts_route_presentation.gd")
static func visible_line(a: Vector2, b: Vector2, viewport: Rect2, blockers: Array) -> Array:
	var first: PackedVector2Array=Routes.clip_line(a,b,viewport)
	if first.is_empty():return []
	var segments: Array=[first]
	for obstacle in blockers:
		var next: Array=[]
		for part in segments:
			var cut: PackedVector2Array=Routes.clip_line(part[0],part[1],obstacle)
			if cut.is_empty():next.append(part);continue
			if part[0].distance_to(cut[0])>.01:next.append(PackedVector2Array([part[0],cut[0]]))
			if part[1].distance_to(cut[1])>.01:next.append(PackedVector2Array([cut[1],part[1]]))
		segments=next
	return segments
static func visible_box(box: Rect2, viewport: Rect2, blockers: Array) -> bool:
	if not viewport.encloses(box):return false
	for rect in blockers:
		if rect.intersects(box):return false
	return true
static func pattern_runs(length: float, phase: float, pattern: Vector2) -> Array:
	var runs: Array=[];var at: float=0;var cycle: float=pattern.x+pattern.y
	while at<length-.001:
		var position: float=fposmod(phase+at,cycle)
		var amount: float=minf(length-at,(pattern.x-position) if position<pattern.x else (cycle-position))
		amount=maxf(.001,amount)
		if position<pattern.x:runs.append(Vector2(at,at+amount))
		at+=amount
	return runs
