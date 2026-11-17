extends Node
## Animate the original central ram mesh, preserving all source vertices/materials.
var machine: Node3D
var ram: MeshInstance3D
var rest: Transform3D
var last_stamp: int=-1
var last_attack: bool=false
var stroke_metres: float=0.0
func configure(source: Node3D) -> bool:
	machine=source
	for mesh in machine.find_children("*","MeshInstance3D",true,false):
		var box: AABB=mesh.mesh.get_aabb()
		if box.size.z>300.0 and box.size.x<40.0 and box.position.y>50.0 and box.end.y<90.0:
			if ram!=null:return false
			ram=mesh
	if ram==null:return false
	rest=ram.transform;return true
func sample(clock: float, attacking: bool, detailed: bool) -> void:
	var stamp: int=int(clock*20.0) if attacking and detailed else 0
	if stamp==last_stamp and attacking==last_attack:return
	last_stamp=stamp;last_attack=attacking;stroke_metres=0.0
	if attacking:
		var phase: float=fposmod(clock,1.0) if detailed else 0.0
		if phase<.18:stroke_metres=lerpf(.28,-.06,smoothstep(0.0,.18,phase))
		elif phase<.60:stroke_metres=-.06
		else:stroke_metres=lerpf(-.06,.28,smoothstep(.60,.90,phase))
	ram.transform=rest;ram.position.z+=stroke_metres/machine.scale.z
