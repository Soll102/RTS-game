extends Node
## Authored march poses on exact source Skin; all source rest transforms remain untouched.
var skeleton: Skeleton3D
var actor: Node3D
var horse: bool=false
var legs: Array=[]
var base: Array=[]
var indices: Dictionary={}
var last_stamp: int=-1
var last_moving: bool=false
var base_position: Vector3
var last_lift: float=0.0
var last_detailed: bool=false
var last_weight: int=-1
var stance_fraction: float=.62
var _leg_bones: Array=[]
var _pelvis_bone: int=-1
var pose_updated: bool=false

static func stride_speed(role: String) -> float:
	# Distance traversed by a planted foot during the stance part of a cycle.
	return .64/(.8*.26) if role=="cavalry" else .68/(.72*(.62 if role=="siege" else .35))

func configure(source: Node3D, mounted: bool=false) -> bool:
	actor=source;horse=mounted;base_position=actor.position
	stance_fraction=.26 if horse else .62
	var rigs: Array=actor.find_children("*","Skeleton3D",true,false)
	if rigs.size()!=1:return false
	skeleton=rigs[0];skeleton.force_update_all_bone_transforms()
	_pelvis_bone=skeleton.find_bone("source_joint_0001")
	var chains: Array=[[37,41,54,0.0],[39,42,56,0.5],[21,38,45,0.75],[25,40,47,0.25]] if horse else [[3,5,7,0.0],[4,6,8,0.5]]
	for chain in chains:
		for joint in chain.slice(0,3):
			var index: int=skeleton.find_bone("source_joint_%04d"%int(joint))
			if index<0:return false
			indices[int(joint)]=index
			_leg_bones.append(index)
		var u_idx: int=indices[int(chain[0])];var l_idx: int=indices[int(chain[1])];var f_idx: int=indices[int(chain[2])]
		var ug: Transform3D=skeleton.get_bone_global_pose(u_idx)
		var lg: Transform3D=skeleton.get_bone_global_pose(l_idx)
		var fg: Transform3D=skeleton.get_bone_global_pose(f_idx)
		var up_parent: Basis=skeleton.get_bone_global_pose(skeleton.get_bone_parent(u_idx)).basis
		var lo_parent: Basis=skeleton.get_bone_global_pose(skeleton.get_bone_parent(l_idx)).basis
		var ft_parent: Basis=skeleton.get_bone_global_pose(skeleton.get_bone_parent(f_idx)).basis
		legs.append({"upper":int(chain[0]),"lower":int(chain[1]),"foot":int(chain[2]),"phase":chain[3],"origin":fg.origin,"basis":fg.basis,
			"a":ug.origin,"b":lg.origin,"c":fg.origin,"first":ug.origin.distance_to(lg.origin),"second":lg.origin.distance_to(fg.origin),
			"u_basis":ug.basis,"l_basis":lg.basis,"u_parent":up_parent,"l_parent":lo_parent,"f_parent":ft_parent})
	for bone in range(skeleton.get_bone_count()):
		base.append({"position":skeleton.get_bone_pose_position(bone),"rotation":skeleton.get_bone_pose_rotation(bone),"scale":skeleton.get_bone_pose_scale(bone),"rest":skeleton.get_bone_rest(bone)})
	return true

func _global(joint: int) -> Transform3D:return skeleton.get_bone_global_pose(indices[joint])
func _basis(joint: int, basis: Basis) -> void:
	var index: int=indices[joint];var parent: int=skeleton.get_bone_parent(index)
	var local: Basis=basis if parent<0 else skeleton.get_bone_global_pose(parent).basis.inverse()*basis
	skeleton.set_bone_pose_rotation(index,local.orthonormalized().get_rotation_quaternion());skeleton.force_update_all_bone_transforms()
func _aim(joint: int, child: int, target: Vector3) -> void:
	var start: Transform3D=_global(joint)
	var old: Vector3=(_global(child).origin-start.origin).normalized();var desired: Vector3=(target-start.origin).normalized()
	if old.length_squared()>.5 and desired.length_squared()>.5:_basis(joint,Basis(Quaternion(old,desired))*start.basis)

func apply_walk(clock: float, moving: bool, offset: float=0.0, weight: float=1.0) -> void:
	if not moving:return
	var units: float=actor.scale.y
	for leg in legs:
		var phase: float=fposmod(clock/(.8 if horse else .72)+float(leg.phase)+offset,1.0)
		var stride: float=.32 if horse else .34;var lift: float=0.0;var travel: float=0.0
		if phase<stance_fraction:travel=lerpf(stride,-stride,phase/stance_fraction)
		else:
			var swing: float=(phase-stance_fraction)/(1.0-stance_fraction)
			travel=lerpf(-stride,stride,smoothstep(0.0,1.0,swing));lift=(.15 if horse else .16)*sin(swing*PI)
		var target: Vector3=leg.origin+Vector3(0,lift,travel)*clampf(weight,0.0,1.0)/units
		var a: Vector3=leg.a;var b: Vector3=leg.b;var c: Vector3=leg.c
		var first: float=leg.first;var second: float=leg.second
		var direction: Vector3=(target-a).normalized();var distance: float=clampf(a.distance_to(target),absf(first-second)+.001,first+second-.001)
		var along: float=(first*first-second*second+distance*distance)/(2.0*distance)
		var rise: float=sqrt(maxf(0,first*first-along*along))
		var pole: Vector3=Vector3(0,0,-1 if horse and leg.upper in [21,25] else 1)
		var side: Vector3=(pole-direction*pole.dot(direction)).normalized()
		var knee: Vector3=a+direction*along+side*rise
		var upper_turn:=Basis(Quaternion((b-a).normalized(),(knee-a).normalized()))
		var lower_turn:=Basis(Quaternion((upper_turn*(c-b)).normalized(),(a+direction*distance-knee).normalized()))
		var upper: int=indices[leg.upper];var lower: int=indices[leg.lower];var foot: int=indices[leg.foot]
		var upper_parent: Basis=leg.u_parent
		var lower_parent: Basis=upper_turn*leg.l_parent
		var foot_parent: Basis=lower_turn*upper_turn*leg.f_parent
		skeleton.set_bone_pose_rotation(upper,(upper_parent.inverse()*upper_turn*leg.u_basis).orthonormalized().get_rotation_quaternion())
		skeleton.set_bone_pose_rotation(lower,(lower_parent.inverse()*lower_turn*upper_turn*leg.l_basis).orthonormalized().get_rotation_quaternion())
		skeleton.set_bone_pose_rotation(foot,(foot_parent.inverse()*Basis(leg.basis)).orthonormalized().get_rotation_quaternion())
	skeleton.force_update_all_bone_transforms()

func sample(clock: float, moving: bool, detailed: bool, offset: float=0.0, weight: float=1.0, sample_clock: float=-1.0) -> float:
	var rate: float=30.0 if sample_clock>=0.0 else 60.0
	var render_clock: float=sample_clock if sample_clock>=0.0 else clock
	var stamp: int=int(render_clock*rate) if moving and detailed else 0
	var blend_stamp: int=int(clampf(weight,0.0,1.0)*rate) if detailed and moving else 0
	if stamp==last_stamp and moving==last_moving and detailed==last_detailed and blend_stamp==last_weight:
		pose_updated=false
		return last_lift
	pose_updated=true
	last_stamp=stamp;last_moving=moving;last_detailed=detailed;last_weight=blend_stamp
	for bone in _leg_bones:
		skeleton.set_bone_pose_position(bone,base[bone].position);skeleton.set_bone_pose_rotation(bone,base[bone].rotation);skeleton.set_bone_pose_scale(bone,base[bone].scale)
	if _pelvis_bone>=0:
		skeleton.set_bone_pose_position(_pelvis_bone,base[_pelvis_bone].position);skeleton.set_bone_pose_rotation(_pelvis_bone,base[_pelvis_bone].rotation)
	if moving and detailed:
		apply_walk(clock,true,offset,weight)
	else:
		skeleton.force_update_all_bone_transforms()
	last_lift=.025*(1.0-cos(clock*TAU/.4))*weight if horse and moving and detailed else 0.0
	actor.position=base_position+Vector3.UP*last_lift
	return last_lift

func source_rest_unchanged() -> bool:
	for i in range(base.size()):
		if skeleton.get_bone_rest(i)!=base[i].rest:return false
	return true

func apply_contact_step(clock: float, entry: float) -> void:
	for bone in _leg_bones:
		skeleton.set_bone_pose_rotation(bone,base[bone].rotation)
		skeleton.set_bone_pose_position(bone,base[bone].position)
	skeleton.force_update_all_bone_transforms()
	var phase: float=fposmod(clock,1.15)/1.15
	var weight: float=0.0
	if phase>=.14 and phase<.34:weight=smoothstep(.14,.34,phase)
	elif phase>=.34 and phase<.46:weight=1.0
	elif phase>=.46 and phase<.78:weight=1.0-smoothstep(.46,.78,phase)
	var lift: float=.065*sin(clampf((phase-.14)/.20,0.0,1.0)*PI) if phase<.34 else 0.0
	for index in range(legs.size()):
		var leg: Dictionary=legs[index]
		var target: Vector3=leg.origin+Vector3(0,lift if index==0 else 0.0,(.30 if index==0 else -.12)*weight)*entry/actor.scale.y
		var ug: Transform3D=_global(leg.upper);var lg: Transform3D=_global(leg.lower);var fg: Transform3D=_global(leg.foot)
		var a: Vector3=ug.origin;var b: Vector3=lg.origin;var c: Vector3=fg.origin
		var first: float=a.distance_to(b);var second: float=b.distance_to(c)
		var direction: Vector3=(target-a).normalized();var distance: float=clampf(a.distance_to(target),absf(first-second)+.001,first+second-.001)
		var along: float=(first*first-second*second+distance*distance)/(2.0*distance)
		var rise: float=sqrt(maxf(0,first*first-along*along))
		var pole: Vector3=Vector3(0,0,1);var side: Vector3=(pole-direction*pole.dot(direction)).normalized()
		var knee: Vector3=a+direction*along+side*rise
		var upper_turn:=Basis(Quaternion((b-a).normalized(),(knee-a).normalized()))
		var lower_turn:=Basis(Quaternion((upper_turn*(c-b)).normalized(),(a+direction*distance-knee).normalized()))
		var upper: int=indices[leg.upper];var lower: int=indices[leg.lower];var foot: int=indices[leg.foot]
		var upper_parent: Basis=skeleton.get_bone_global_pose(skeleton.get_bone_parent(upper)).basis
		var lower_parent: Basis=upper_turn*skeleton.get_bone_global_pose(skeleton.get_bone_parent(lower)).basis
		var foot_parent: Basis=lower_turn*upper_turn*skeleton.get_bone_global_pose(skeleton.get_bone_parent(foot)).basis
		skeleton.set_bone_pose_rotation(upper,(upper_parent.inverse()*upper_turn*ug.basis).orthonormalized().get_rotation_quaternion())
		skeleton.set_bone_pose_rotation(lower,(lower_parent.inverse()*lower_turn*upper_turn*lg.basis).orthonormalized().get_rotation_quaternion())
		skeleton.set_bone_pose_rotation(foot,(foot_parent.inverse()*Basis(leg.basis)).orthonormalized().get_rotation_quaternion())
	if _pelvis_bone>=0:
		var rotation: Quaternion=skeleton.get_bone_pose_rotation(_pelvis_bone)
		skeleton.set_bone_pose_rotation(_pelvis_bone,rotation*Quaternion(Vector3.RIGHT,deg_to_rad(6.0)*weight*entry))
	skeleton.force_update_all_bone_transforms()
