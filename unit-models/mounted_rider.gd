extends RefCounted
## Mount owns travel/bob. Seat alignment is derived from the two source rigs.
const SEAT_OFFSET: Vector3=Vector3(0,.08,-.04)
var rider: Node3D
var mount: Node3D
var rider_rig: Skeleton3D
var mount_rig: Skeleton3D
var rider_hip: int=-1
var mount_hip: int=-1

func configure(person: Node3D, horse: Node3D) -> bool:
	rider=person;mount=horse
	var people: Array=rider.find_children("*","Skeleton3D",true,false)
	var horses: Array=mount.find_children("*","Skeleton3D",true,false)
	if people.size()!=1 or horses.size()!=1:return false
	rider_rig=people[0];mount_rig=horses[0]
	rider_hip=rider_rig.find_bone("source_joint_0001");mount_hip=mount_rig.find_bone("source_joint_0001")
	if rider_hip<0 or mount_hip<0:return false
	sample();return true

func sample() -> void:
	var parent: Node3D=rider.get_parent()
	if mount_rig!=null:mount_rig.force_update_all_bone_transforms()
	if rider_rig!=null:rider_rig.force_update_all_bone_transforms()
	var saddle: Vector3=parent.to_local(mount_rig.to_global(mount_rig.get_bone_global_pose(mount_hip).origin))
	var hip: Vector3=rider.to_local(rider_rig.to_global(rider_rig.get_bone_global_pose(rider_hip).origin))
	rider.position=saddle+SEAT_OFFSET-rider.basis*hip
	rider.rotation=Vector3.ZERO
