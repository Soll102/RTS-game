extends Node
const Locomotion=preload("res://unit-models/source_locomotion.gd")
## Authored attack/held role poses on unchanged original Skin and bone rest.
## These are RTS role compositions, not recovered native class clips.
var actor: Node3D
var skeleton: Skeleton3D
var role: String
var bind_report: Dictionary={}
var _last_sample: int=-1
var _last_state: String=""
var _rest: Array=[]
var _scale: float=1.0
var locomotion: Node
var _last_detail: bool=false
var _last_weight: int=-1
var _bone_indices: Dictionary={}
var _rest_global: Dictionary={}
var _parent_rest_basis: Dictionary={}
var _modified_bones: Array=[]

func configure(source: Node3D, requested_role: String) -> bool:
	actor=source;role=requested_role;_scale=actor.scale.y
	var bones: Array=actor.find_children("*","Skeleton3D",true,false)
	if bones.size()!=1:return false
	skeleton=bones[0]
	var joints: Array=[1,3,4,5,6,7,8,15,16,17,18,19,20]
	for joint in joints:
		if _bone(joint)<0:return false
	for i in range(skeleton.get_bone_count()):_rest.append(skeleton.get_bone_rest(i))
	skeleton.reset_bone_poses();skeleton.force_update_all_bone_transforms()
	for joint in joints:
		var idx: int=_bone(joint)
		_modified_bones.append(idx)
		_rest_global[joint]=skeleton.get_bone_global_pose(idx)
		var parent: int=skeleton.get_bone_parent(idx)
		_parent_rest_basis[joint]=skeleton.get_bone_global_pose(parent).basis if parent>=0 else Basis.IDENTITY
	var triangles: int=0
	for mesh in actor.find_children("*","MeshInstance3D",true,false):
		if mesh.get_skin()==null or mesh.get_node_or_null(mesh.skeleton)!=skeleton:return false
		for surface in range(mesh.mesh.get_surface_count()):triangles+=mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_INDEX].size()/3
	bind_report={"actual_skin_binding":true,"original_rest_hierarchy":true,"triangles":triangles,"authored_role":role,"native_clip":false}
	if role!="cavalry":
		locomotion=Locomotion.new();add_child(locomotion)
		if not locomotion.configure(actor):return false
		locomotion.stance_fraction=.62 if role=="siege" else .35
	return true

func _bone(joint: int) -> int:
	if not _bone_indices.has(joint):_bone_indices[joint]=skeleton.find_bone("source_joint_%04d"%joint)
	return _bone_indices[joint]
func _global(joint: int) -> Transform3D:return skeleton.get_bone_global_pose(_bone(joint))

func _basis(joint: int, desired: Basis) -> void:
	var index: int=_bone(joint);var parent: int=skeleton.get_bone_parent(index)
	var local: Basis=desired if parent<0 else skeleton.get_bone_global_pose(parent).basis.inverse()*desired
	skeleton.set_bone_pose_rotation(index,local.orthonormalized().get_rotation_quaternion())
	skeleton.force_update_all_bone_transforms()

func _aim(joint: int, child: int, target: Vector3) -> void:
	var current: Transform3D=_global(joint)
	var old: Vector3=(_global(child).origin-current.origin).normalized()
	var direction: Vector3=(target-current.origin).normalized()
	if old.length_squared()<.5 or direction.length_squared()<.5:return
	_basis(joint,Basis(Quaternion(old,direction))*current.basis)

func _limb(upper: int, lower: int, hand: int, metres: Vector3, pole_metres: Vector3, end_basis: Variant=null) -> void:
	var ug: Transform3D=_rest_global[upper];var lg: Transform3D=_rest_global[lower];var hg: Transform3D=_rest_global[hand]
	var a: Vector3=ug.origin;var b: Vector3=lg.origin;var c: Vector3=hg.origin
	var target: Vector3=metres/_scale;var pole: Vector3=pole_metres/_scale
	var first: float=a.distance_to(b);var second: float=b.distance_to(c)
	var distance: float=clampf(a.distance_to(target),absf(first-second)+.01,first+second-.01)
	var direction: Vector3=(target-a).normalized();target=a+direction*distance
	var projection: float=(first*first-second*second+distance*distance)/(2.0*distance)
	var rise: float=sqrt(maxf(0,first*first-projection*projection))
	var side: Vector3=(pole-a)-direction*((pole-a).dot(direction))
	if side.length_squared()<.0001:side=direction.cross(Vector3.UP)
	side=side.normalized()
	var elbow: Vector3=a+direction*projection+side*rise
	var first_turn:=Basis(Quaternion((b-a).normalized(),(elbow-a).normalized()))
	var second_turn:=Basis(Quaternion((first_turn*(c-b)).normalized(),(target-elbow).normalized()))
	var first_index: int=_bone(upper);var second_index: int=_bone(lower)
	var first_parent: Basis=_parent_rest_basis[upper]
	var second_parent: Basis=first_turn*_parent_rest_basis[lower]
	var first_pose: Quaternion=(first_parent.inverse()*first_turn*ug.basis).orthonormalized().get_rotation_quaternion()
	var second_pose: Quaternion=(second_parent.inverse()*second_turn*first_turn*lg.basis).orthonormalized().get_rotation_quaternion()
	skeleton.set_bone_pose_rotation(first_index,first_pose);skeleton.set_bone_pose_rotation(second_index,second_pose)
	if end_basis is Basis:
		var hand_parent: Basis=second_turn*first_turn*_parent_rest_basis[hand]
		skeleton.set_bone_pose_rotation(_bone(hand),(hand_parent.inverse()*(end_basis as Basis)).orthonormalized().get_rotation_quaternion())

func sample(clock: float, attacking: bool, detailed: bool=true, draw_progress: float=-1.0, marching: bool=false, slot_phase: float=0.0, march_clock: float=-1.0, march_weight: float=1.0) -> bool:
	if skeleton==null:return false
	var state: String="attack" if attacking else ("move" if marching else "held")
	var gait_clock: float=march_clock if march_clock>=0.0 else clock
	var stamp: int=int(clock*24.0) if detailed and attacking else int(clock*30.0) if detailed and marching and role!="cavalry" else 0
	var blend_stamp: int=int(clampf(march_weight,0.0,1.0)*24.0) if marching and role!="cavalry" else 0
	if stamp==_last_sample and state==_last_state and detailed==_last_detail and blend_stamp==_last_weight:return false
	_last_sample=stamp;_last_state=state;_last_detail=detailed;_last_weight=blend_stamp
	for idx in _modified_bones:
		var r: Transform3D=_rest[idx]
		skeleton.set_bone_pose_position(idx,r.origin)
		skeleton.set_bone_pose_rotation(idx,r.basis.get_rotation_quaternion())
		skeleton.set_bone_pose_scale(idx,r.basis.get_scale())
	var phase: float=fposmod(clock,1.15)/1.15
	var pull: float=sin(phase*PI) if attacking else .15
	if draw_progress>=0.0:pull=clampf(draw_progress,0.0,1.0)
	if role=="archers":
		_limb(16,18,20,Vector3(-.30,lerpf(1.38,1.78,pull),.43),Vector3(-.6,1.75,.02))
		_limb(15,17,19,Vector3(.26,lerpf(1.34,1.77,pull),.33-.24*pull),Vector3(.7,1.72,-.25))
	elif role=="cavalry":
		var right_foot: Basis=_rest_global[7].basis;var left_foot: Basis=_rest_global[8].basis
		var spear_wrist: Basis=_rest_global[20].basis
		_limb(3,5,7,Vector3(.38,.36,.38),Vector3(.8,.85,.7),right_foot)
		_limb(4,6,8,Vector3(-.38,.36,.38),Vector3(-.8,.85,.7),left_foot)
		_limb(16,18,20,Vector3(-.26,1.40,.26+.13*pull),Vector3(-.65,1.4,-.1),Basis(Quaternion(Vector3.LEFT,Vector3(.15*pull,-.12,1).normalized()))*spear_wrist)
		_limb(15,17,19,Vector3(.25,1.35,.30),Vector3(.6,1.38,-.1))
	elif role=="siege":
		_limb(16,18,20,Vector3(-.27,1.15,.30+.10*pull),Vector3(-.6,1.2,0))
		_limb(15,17,19,Vector3(.27,1.15,.30+.10*pull),Vector3(.6,1.2,0))
	elif role=="infantry":
		var spear_wrist: Basis=_rest_global[20].basis
		_limb(16,18,20,Vector3(-.26,1.40,.38),Vector3(-.65,1.5,-.1),Basis(Quaternion(Vector3.LEFT,Vector3(0,.65,1).normalized()))*spear_wrist)
		_limb(15,17,19,Vector3(.25,1.30,.30),Vector3(.6,1.38,-.1))
	if locomotion!=null and marching and not attacking and detailed:
		locomotion.apply_walk(gait_clock,true,slot_phase,march_weight)
	else:
		skeleton.force_update_all_bone_transforms()
	return true

func wrist_position() -> Vector3:return actor.to_global(_global(20).origin)

## Authored march cycle on the unchanged source rig: alternating leg swing with a
## short foot lift, pelvis bob and counter-swinging arms. Mounted roles keep the
## seat and let the mount carry the travel, so only the torso breathes.
func _walk(clock: float) -> void:
	var period: float=1.10
	var phase: float=fposmod(clock,period)/period
	var bob: float=0.9*cos(4.0*PI*phase)
	var legs: Array=[["right",3,5,7,0.0],["left",4,6,8,0.5]]
	if role=="cavalry":
		for leg in legs:
			var upper: int=leg[1];var lower: int=leg[2];var foot: int=leg[3]
			var rest: Basis=_global(foot).basis
			_limb(upper,lower,foot,Vector3(.38 if leg[0]=="right" else -.38,.36,.38),Vector3(.8,.85,.7))
			_basis(foot,rest)
		return
	for leg in legs:
		var side: String=leg[0];var upper: int=leg[1];var lower: int=leg[2];var foot: int=leg[3]
		var leg_phase: float=fposmod(phase+float(leg[4]),1.0)
		var foot_z: float
		var lift: float
		if leg_phase<0.60:
			foot_z=24.0-48.0*(leg_phase/0.60);lift=0.0
		else:
			var swing: float=(leg_phase-0.60)/0.40
			foot_z=-24.0+48.0*swing;lift=16.0*pow(sin(PI*swing),2.0)
		var x: float=0.24 if side=="right" else -0.24
		_limb(upper,lower,foot,Vector3(x,0.05+lift*0.01,foot_z*0.01),Vector3(x*2.0,0.55,0.55))
	var sway: float=sin(2.0*PI*phase)
	if role=="archers":
		_limb(16,18,20,Vector3(-.30-0.02*sway,1.40+0.02*bob,.43),Vector3(-.6,1.75,.02))
		_limb(15,17,19,Vector3(.26+0.02*sway,1.36-0.02*bob,.33),Vector3(.7,1.72,-.25))
	else:
		_limb(16,18,20,Vector3(-.26-0.06*sway,1.36+0.03*bob,.30+0.10*sway),Vector3(-.65,1.4,-.1))
		_limb(15,17,19,Vector3(.25+0.06*sway,1.32-0.03*bob,.26-0.10*sway),Vector3(.6,1.38,-.1))
