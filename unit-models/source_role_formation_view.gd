extends Node3D
## Original model pixels/rigs, explicit authored RTS role assemblies.
const Infantry=preload("res://scripts/contact_formation_view.gd")
const RoleMotion=preload("res://unit-models/source_role_motion.gd")
const Locomotion=preload("res://unit-models/source_locomotion.gd")
const SiegeMotion=preload("res://unit-models/siege_machine_motion.gd")
const ContactMotion=preload("res://unit-models/melee_contact_motion.gd")
const MarchState=preload("res://unit-models/formation_locomotion_state.gd")
const TeamStandard=preload("res://scripts/rts_unit_standard.gd")
const FactionView=preload("res://scripts/rts_faction_view.gd")
const MountedRider=preload("res://unit-models/mounted_rider.gd")
const FormationSteering=preload("res://scripts/rts_formation_steering.gd")
var contact_motion: RefCounted
var simulation: RefCounted
var controller: Node3D
var formations: Dictionary={}
var role_formations: Dictionary={}
var catalog: Dictionary={}
var scenes: Dictionary={}
var infantry: Node3D
var active: bool=false
var source_height: float=2.2
var _horse_groom: Dictionary={}
var _last_tick: int=-1
var _failed: bool=false
var _slot_signature: String=""
var _slot_positions: Dictionary={}
var _presentation_members: int=-1
var _controller_revision: int=-1
var _wall_rects: Array=[]
var _walls_source: Array=[]
var _horse_lod_meshes: Dictionary={}
var _friendly_slots_tick: int=-1
var _friendly_slots_cache: Dictionary={}

func _half_size(role: String) -> Vector2:return Vector2(2.4,4.2 if role=="cavalry" else 2.4) if simulation.get("traditional_rts")==true else Vector2(3.7,5.4 if role=="cavalry" else 3.0)

func _allowed_field(point: Vector3, half: Vector2) -> bool:
	var units: float=float(simulation.world_metadata.get("coordinate_units_per_world",10.0))
	if simulation.get("river_navigation")!=null and not simulation.river_navigation.dry_footprint(Vector2(point.x,point.z)*units,half*units):return false
	var walls: Array=simulation.world_metadata.get("los_walls",[])
	if walls!=_walls_source:
		_walls_source=walls;_wall_rects.clear()
		for wall in walls:
			_wall_rects.append(Rect2(Vector2(wall[0]-wall[2],wall[1]-wall[3])/units,Vector2(wall[2],wall[3])*2.0/units))
	var footprint:=Rect2(Vector2(point.x,point.z)-half,half*2.0)
	for obstacle in _wall_rects:
		if footprint.intersects(obstacle):return false
	return true

func _local_nodes(start: String) -> Array:
	var result: Array=[];var visited: Dictionary={start:true};var frontier: Array=[start]
	for _depth in range(4):
		var following: Array=[]
		for node in frontier:
			if simulation.nodes[node].get("passable",true) and simulation.nodes[node].get("terrain","") not in ["water","river"]:result.append(node)
			for neighbor in simulation.nodes[node].edges:
				if simulation._crossing_by_edge.has(simulation._edge_key(node,neighbor)):continue
				if not visited.has(neighbor):visited[neighbor]=true;following.append(neighbor)
		frontier=following
	return result

func _stationary_slots() -> Dictionary:
	var groups: Dictionary={}
	for id in simulation._sorted_ids(simulation.armies):
		var a: Dictionary=simulation.armies[id]
		if a.troops<=0 or a.transport_elapsed>0 or a.edge_progress>0 or a.routed or not a.get("resident_city","").is_empty() or not a.engaged_ids.is_empty():continue
		if not a.route.is_empty() and a.order.type!="hold":continue
		var key: String=a.faction+":"+a.node
		if not groups.has(key):groups[key]=[]
		groups[key].append(id)
	var signature: String=str(groups)
	if signature==_slot_signature:return _slot_positions
	_slot_signature=signature;_slot_positions.clear()
	for key in groups:
		var ids: Array=groups[key]
		if ids.size()==1 and _allowed_field(controller.node_positions[simulation.armies[ids[0]].node],_half_size(simulation.armies[ids[0]].unit_type)):continue
		ids.sort_custom(func(a,b):
			var order: Array=["cavalry","siege","infantry","archers"]
			var pa: int=order.find(simulation.armies[a].unit_type);var pb: int=order.find(simulation.armies[b].unit_type)
			return a<b if pa==pb else pa<pb)
		var node: String=simulation.armies[ids[0]].node;var anchor: Vector3=controller.node_positions[node]
		var candidates: Array=_local_nodes(node)
		candidates.sort_custom(func(a,b):
			var da: float=controller.node_positions[a].distance_squared_to(anchor);var db: float=controller.node_positions[b].distance_squared_to(anchor)
			return a<b if is_equal_approx(da,db) else da<db)
		var occupied: Array=[]
		for id in ids:
			var half: Vector2=_half_size(simulation.armies[id].unit_type)
			for candidate in candidates:
				var p: Vector3=controller.node_positions[candidate]
				if Vector2(p.x-anchor.x,p.z-anchor.z).length()>18 or not _allowed_field(p,half):continue
				var box:=Rect2(Vector2(p.x,p.z)-half,half*2.0).grow(.8)
				if occupied.any(func(other):return box.intersects(other)):continue
				occupied.append(box);_slot_positions[id]=p;break
	return _slot_positions

func _visual_radius(role: String) -> float:
	return 3.5 if role=="cavalry" else 2.8 if role=="siege" else 2.2

func _slot_offset(role: String, slot: int, stance: String, compact: bool) -> Vector3:
	if not compact:
		if role=="cavalry":return Vector3((slot%4-1.5)*2.45,0,(int(slot/4)-.5)*5.0)
		elif role=="siege":return Vector3(-1.6 if slot<4 else 1.6,0,(slot%4-1.5)*1.25)
		return Vector3((slot%4-1.5)*1.5,0,(int(slot/4)-.5)*1.75)
	if stance=="aggressive":
		if role=="cavalry":return [Vector3(0.0,0,2.3),Vector3(-1.95,0,-0.3),Vector3(1.95,0,-0.3),Vector3(0.0,0,-2.6)][slot%4]
		elif role=="siege":return [Vector3(-1.7,0,1.3),Vector3(1.7,0,1.3),Vector3(-2.1,0,-1.1),Vector3(2.1,0,-1.1)][slot%4]
		return [Vector3(0.0,0,1.45),Vector3(-1.35,0,-0.15),Vector3(1.35,0,-0.15),Vector3(0.0,0,-1.55)][slot%4]
	if stance=="defensive":
		if role=="cavalry":return [Vector3(-2.7,0,0.7),Vector3(-0.95,0,-0.5),Vector3(0.95,0,-0.5),Vector3(2.7,0,0.7)][slot%4]
		elif role=="siege":return [Vector3(-2.2,0,0.8),Vector3(-1.5,0,-0.8),Vector3(1.5,0,-0.8),Vector3(2.2,0,0.8)][slot%4]
		return [Vector3(-2.1,0,0.45),Vector3(-0.7,0,-0.25),Vector3(0.7,0,-0.25),Vector3(2.1,0,0.45)][slot%4]
	if role=="cavalry":return Vector3((slot%2-.5)*2.8,0,(int(slot/2)-.5)*4.4)
	elif role=="siege":return Vector3(-1.9 if slot<2 else 1.9,0,(slot%2-.5)*2.0)
	return Vector3((slot%2-.5)*1.5,0,(int(slot/2)-.5)*2.0)

func _travel_direction(id: String, point: Vector3) -> Vector3:
	var army: Dictionary=simulation.armies[id]
	if army.route.is_empty():return Vector3.ZERO
	var direction: Vector3=controller.node_positions[army.route[0]]-point;direction.y=0
	return direction.normalized() if direction.length_squared()>.0001 else Vector3.ZERO

func _friendly_slots() -> Dictionary:
	if _friendly_slots_tick==simulation.tick and not _friendly_slots_cache.is_empty():return _friendly_slots_cache
	_friendly_slots_tick=simulation.tick
	var result: Dictionary=_stationary_slots().duplicate()
	var positions: Dictionary={};var ids: Array=[]
	for id in simulation._sorted_ids(simulation.armies):
		var army: Dictionary=simulation.armies[id]
		if army.troops<=0 or army.transport_elapsed>0 or not army.get("resident_city","").is_empty() or not army.engaged_ids.is_empty():continue
		ids.append(id);positions[id]=result.get(id,controller.grounded_position(id))
	for _iteration in range(4):
		for i in range(ids.size()):
			var id: String=ids[i];var army: Dictionary=simulation.armies[id]
			for j in range(i+1,ids.size()):
				var other: String=ids[j];var other_army: Dictionary=simulation.armies[other]
				if other_army.faction!=army.faction:continue
				var a: Vector3=positions[id];var b: Vector3=positions[other];var delta: Vector3=a-b;delta.y=0
				var desired: float=_visual_radius(army.unit_type)+_visual_radius(other_army.unit_type)+0.25
				var distance: float=delta.length()
				if distance>=desired:continue
				if distance<.001:
					var heading: Vector3=_travel_direction(id,a)+_travel_direction(other,b)
					if heading.length_squared()<.001:heading=Vector3.FORWARD
					delta=Vector3(-heading.z,0,heading.x).normalized();distance=0.0
				else:delta/=distance
				var shift: float=(desired-distance)*.52+0.05
				var next_a: Vector3=a+delta*shift;var next_b: Vector3=b-delta*shift
				var allow_a: bool=_allowed_field(next_a,_half_size(army.unit_type));var allow_b: bool=_allowed_field(next_b,_half_size(other_army.unit_type))
				if not allow_a or not allow_b:
					var road_dir: Vector3=_travel_direction(id,a)
					if road_dir.length_squared()>.01:
						var alt_a: Vector3=a+road_dir*shift;var alt_b: Vector3=b-road_dir*shift
						if _allowed_field(alt_a,_half_size(army.unit_type)):allow_a=true;next_a=alt_a
						if _allowed_field(alt_b,_half_size(other_army.unit_type)):allow_b=true;next_b=alt_b
				if allow_a:positions[id]=next_a
				if allow_b:positions[other]=next_b
	for id in ids:
		var base: Vector3=controller.grounded_position(id)
		if positions[id].distance_squared_to(base)>.0025:result[id]=positions[id]
	var engaged_groups: Dictionary={}
	for id in simulation._sorted_ids(simulation.armies):
		var army: Dictionary=simulation.armies[id]
		if army.troops<=0 or army.transport_elapsed>0 or not army.get("resident_city","").is_empty() or army.engaged_ids.is_empty():continue
		var target_id: String=str(army.engaged_ids[0])
		if not simulation.armies.has(target_id):continue
		var key: String=army.faction+":"+target_id
		if not engaged_groups.has(key):engaged_groups[key]=[]
		engaged_groups[key].append(id)
	for key in engaged_groups:
		var group_ids: Array=engaged_groups[key]
		if group_ids.size()<=1:continue
		var target_id: String=key.split(":")[1]
		var target_pos: Vector3=controller.grounded_position(target_id)
		for idx in range(group_ids.size()):
			var id: String=group_ids[idx];var army: Dictionary=simulation.armies[id]
			var base: Vector3=controller.grounded_position(id)
			var to_enemy: Vector3=target_pos-base;to_enemy.y=0
			if to_enemy.length_squared()<.001:to_enemy=Vector3.FORWARD
			else:to_enemy=to_enemy.normalized()
			var lateral:=Vector3(-to_enemy.z,0,to_enemy.x)
			var rank_offset: float=(idx-(group_ids.size()-1)*.5)*4.2
			var candidate: Vector3=base+lateral*rank_offset
			if _allowed_field(candidate,_half_size(army.unit_type)):result[id]=candidate
	_friendly_slots_cache=result
	return result

func configure(sim: RefCounted, controls: Node3D) -> String:
	simulation=sim;controller=controls
	contact_motion=ContactMotion.new();contact_motion.configure(sim,controls)
	infantry=Infantry.new();add_child(infantry);infantry.set_process(false)
	var error: String=infantry.configure(sim,controls)
	if not error.is_empty():return error
	catalog=JSON.parse_string(FileAccess.get_file_as_string("res://unit-models/asset-catalog.json"))
	if catalog.get("approved",true):return "Pending original-role catalog required."
	for key in catalog.assets:
		var entry: Dictionary=catalog.assets[key]
		var path: String="res://"+str(entry.file).replace("\\","/")
		if FileAccess.get_sha256(path)!=entry.sha256:return "Role source hash differs: "+key
		scenes[key]=load(path)
		if scenes[key]==null:return "Role source failed import: "+key
	_horse_groom=JSON.parse_string(FileAccess.get_file_as_string("res://unit-models/horse-groom-pose.json"))
	return ""

func reset() -> void:
	if contact_motion!=null:contact_motion.reset()
	if infantry!=null:infantry.reset()
	for record in role_formations.values():record.root.queue_free()
	role_formations.clear();formations.clear();_last_tick=-1
	_slot_signature="";_slot_positions.clear();_friendly_slots_tick=-1;_friendly_slots_cache.clear()

func _actor(key: String, parent: Node3D, factor: float) -> Node3D:
	var actor: Node3D=scenes[key].instantiate();parent.add_child(actor);actor.scale=Vector3.ONE*factor
	for mesh in actor.find_children("*","MeshInstance3D",true,false):
		mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if key in ["bow","siege"]:mesh.lod_bias=.22
	return actor

func _horse(parent: Node3D) -> Node3D:
	# 260.4 source units tall -> ~2.35 m at the head, a believable warhorse next to a 2.2 m rider.
	var actor: Node3D=_actor("horse",parent,.00902)
	var skeleton: Skeleton3D=actor.find_children("*","Skeleton3D",true,false)[0]
	for channel in _horse_groom.channels:
		var bone: int=skeleton.find_bone(channel.bone)
		if bone<0:continue
		var p: Array=channel.position;var q: Array=channel.rotation
		skeleton.set_bone_pose_position(bone,Vector3(p[0],p[1],p[2]))
		skeleton.set_bone_pose_rotation(bone,Quaternion(q[0],q[1],q[2],q[3]))
	skeleton.force_update_all_bone_transforms()
	var meshes: Array=actor.find_children("*","MeshInstance3D",true,false)
	for index in range(meshes.size()):
		if not _horse_lod_meshes.has(index):
			var path: String="res://unit-models/assets/horse-mesh-%d-generated-lods.res"%index
			_horse_lod_meshes[index]=load(path) if ResourceLoader.exists(path) else null
		if _horse_lod_meshes[index]!=null:meshes[index].mesh=_horse_lod_meshes[index]
		meshes[index].lod_bias=.03
	return actor

func _create(id: String) -> String:
	var army: Dictionary=simulation.armies[id];var role: String=army.unit_type
	var group:=Node3D.new();group.name="OriginalRole_"+id;add_child(group)
	var record: Dictionary={"root":group,"people":[],"pivots":[],"motions":[],"entries":[],"bows":[],"horses":[],"horse_motions":[],"riders":[],"role":role,"state":"held","previous":Vector3.INF}
	var body_entry: Dictionary=catalog.assets.soldier if role=="cavalry" else catalog.assets.body
	var height: float=float(body_entry.bounds[1][1])-float(body_entry.bounds[0][1])
	var compact: bool=simulation.get("traditional_rts")==true
	var scale_factor: float=(1.8 if compact else 2.2)/height
	for slot in range(4 if compact else 8):
		var pivot:=Node3D.new();group.add_child(pivot)
		if role=="cavalry":pivot.position=Vector3((slot%4-1.5)*2.45,0,(int(slot/4)-.5)*5.0)
		elif role=="siege":pivot.position=Vector3(-1.6 if slot<4 else 1.6,0,(slot%4-1.5)*1.25)
		else:pivot.position=Vector3((slot%4-1.5)*1.5,0,(int(slot/4)-.5)*1.75)
		if compact:
			if role=="cavalry":pivot.position=Vector3((slot%2-.5)*2.8,0,(int(slot/2)-.5)*4.4)
			elif role=="siege":pivot.position=Vector3(-1.9 if slot<2 else 1.9,0,(slot%2-.5)*2.0)
			else:pivot.position=Vector3((slot%2-.5)*1.5,0,(int(slot/2)-.5)*2.0)
		var person: Node3D=_actor("soldier" if role=="cavalry" else "body",pivot,scale_factor)
		person.position.y=-float(body_entry.bounds[0][1])*scale_factor
		if role=="cavalry":
			var horse: Node3D=_horse(pivot);record.horses.append(horse);person.position+=Vector3(0,.12,-.05)
			var horse_motion:=Locomotion.new();horse.add_child(horse_motion)
			if not horse_motion.configure(horse,true):group.queue_free();return "Horse source locomotion binding failed"
			record.horse_motions.append(horse_motion)
		var motion:=RoleMotion.new();person.add_child(motion)
		if not motion.configure(person,role):group.queue_free();return "Role source Skin binding failed: "+role
		if role=="cavalry":
			var rider:=MountedRider.new()
			if not rider.configure(person,record.horses[-1]):group.queue_free();return "Mounted rider seat binding failed"
			record.riders.append(rider)
		record.people.append(person);record.pivots.append(pivot);record.motions.append(motion);record.entries.append(body_entry)
		if role=="archers":record.bows.append(_actor("bow",pivot,.01))
	if role=="siege":
		record.machine=_actor("siege",group,.0109)
		record.machine_motion=SiegeMotion.new();record.machine.add_child(record.machine_motion)
		if not record.machine_motion.configure(record.machine):group.queue_free();return "Original ram mesh binding failed"
	role_formations[id]=record
	return ""

func display_position(id: String) -> Vector3:
	if role_formations.has(id):return role_formations[id].root.global_position
	return infantry.display_position(id) if infantry!=null else controller.grounded_position(id)

func display_height(id: String) -> float:
	return 3.15 if role_formations.has(id) and role_formations[id].role=="cavalry" else source_height

func hud_position(id: String) -> Vector3:
	if formations.has(id):return formations[id].get("hud_anchor",formations[id].root.global_position)
	return controller.grounded_position(id)

func _steered_position(record: Dictionary, id: String, slots: Dictionary, clock: float) -> Vector3:
	if not record.has("steering"):record.steering=FormationSteering.new()
	var army: Dictionary=simulation.armies[id];var base: Vector3=controller.grounded_position(id)
	if int(army.get("transport_elapsed",0))>0:
		record.steering.offset=Vector3.ZERO;record.steering.last_clock=clock
		return Vector3(base.x,maxf(.30,base.y),base.z)
	var desired: Vector3=slots[id]-base if slots.has(id) else Vector3.ZERO
	if army.order.type!="hold" and army.route.size()>=2 and army.engaged_ids.is_empty():
		var next_pos: Vector3=controller.node_positions.get(army.route[0],base)
		var after_pos: Vector3=controller.node_positions.get(army.route[1],next_pos)
		var d_next: float=Vector2(next_pos.x-base.x,next_pos.z-base.z).length()
		if d_next<4.8 and d_next>.1:
			var corner_dir: Vector3=after_pos-next_pos;corner_dir.y=0
			if corner_dir.length_squared()>.01:
				var corner_blend: float=(1.0-d_next/4.8)*1.35
				var candidate_corner: Vector3=base+desired+corner_dir.normalized()*corner_blend
				if _allowed_field(candidate_corner,_half_size(army.unit_type)):desired+=corner_dir.normalized()*corner_blend
	var point: Vector3=record.steering.sample(base,desired,clock,float(army.movement_per_tick),_half_size(army.unit_type),_allowed_field)
	point.y=float(controller.ground_sampler.call(point.x,point.z));return point

func _march(record: Dictionary, army: Dictionary, point: Vector3, clock: float, attacking: bool) -> RefCounted:
	if not record.has("march"):record.march=MarchState.new()
	var gait: RefCounted=record.march
	var can_walk: bool=not attacking and army.troops>0 and army.transport_id.is_empty() and army.transport_elapsed==0
	var intent:=Vector3.ZERO
	if can_walk and army.order.type!="hold" and not army.route.is_empty():intent=controller.node_positions[army.route[0]]-point
	gait.sample(point,clock,can_walk,Locomotion.stride_speed(str(army.unit_type)),record.root.rotation.y,intent)
	if controller.camera!=null:gait.update_detail(controller.camera.global_position.distance_to(record.root.global_position))
	if can_walk and gait.has_heading:record.root.rotation.y=gait.heading
	return gait

func sync() -> void:
	if simulation==null or _failed:return
	if _controller_revision!=controller.presentation_revision:
		reset();_controller_revision=controller.presentation_revision
	var members: int=simulation.visible_members()
	if _presentation_members!=members:
		if _presentation_members>=0:reset()
		_presentation_members=members;source_height=1.8 if members==4 else 2.2
	if simulation.tick<_last_tick:reset()
	_last_tick=simulation.tick
	infantry.simulation=simulation;infantry.controller=controller
	for id in infantry.formations.keys():
		if simulation.armies.has(id) and simulation.armies[id].unit_type!="infantry":
			infantry.formations[id].root.visible=false;infantry.formations[id].root.queue_free();infantry.formations.erase(id)
	infantry.active=active;infantry.sync()
	for id in role_formations.keys():
		if not simulation.armies.has(id) or simulation.armies[id].troops<=0 or not simulation.armies[id].get("resident_city","").is_empty() or simulation.armies[id].unit_type!=role_formations[id].role:
			role_formations[id].root.visible=false;role_formations[id].root.queue_free();role_formations.erase(id)
	for id in simulation._sorted_ids(simulation.armies):
		var army: Dictionary=simulation.armies[id]
		if army.unit_type not in ["archers","cavalry","siege"] or army.troops<=0 or not army.get("resident_city","").is_empty():continue
		if not role_formations.has(id):
			var error: String=_create(id)
			if not error.is_empty():push_error(error);active=false;_failed=true;return
	var clock: float=(float(simulation.tick)+clampf(float(simulation.accumulator_us)/100000.0,0.0,1.0))*.1
	var slots: Dictionary=_friendly_slots()
	var draws: Dictionary={}
	var jobs=simulation.get("pending_windups")
	if jobs is Array:
		for job in jobs:
			if job.kind=="army":draws[job.source]=clampf((clock*1000000.0-float(job.started_us))/350000.0,0.0,1.0)
	formations=infantry.formations.duplicate()
	for id in role_formations:formations[id]=role_formations[id]
	contact_motion.simulation=simulation;contact_motion.controller=controller
	var contact_partners: Dictionary=contact_motion._partners(formations)
	for id in role_formations:
		var army: Dictionary=simulation.armies[id];var record: Dictionary=role_formations[id];var group: Node3D=record.root
		var p: Vector3=_steered_position(record,id,slots,clock);group.position=p
		var attacking: bool=not army.routed and (not army.engaged_ids.is_empty() or army.siege_state in ["besieging","breached"] or army.get("preparing_volley",false))
		if record.role=="archers":attacking=draws.has(id) and not army.routed
		if simulation.get("tactical_rts")==true and army.order.type in ["move","retreat"] and not army.route.is_empty():attacking=false
		var gait: RefCounted=_march(record,army,p,clock,attacking)
		var aim: Vector3=Vector3.INF
		if not army.engaged_ids.is_empty() and simulation.armies.has(army.engaged_ids[0]):aim=controller.grounded_position(army.engaged_ids[0])
		elif army.order.type in ["siege","attack_city"] and simulation.cities.has(army.order.target):aim=controller.city_positions.get(army.order.target,controller.node_positions[simulation._target_node(army.order)])
		elif army.order.type=="attack" and simulation.armies.has(army.order.target):aim=controller.grounded_position(army.order.target)
		if attacking and aim.is_finite() and Vector2(aim.x-p.x,aim.z-p.z).length_squared()>.0001:
			var target_yaw: float=atan2(aim.x-p.x,aim.z-p.z)
			group.rotation.y=lerp_angle(group.rotation.y,target_yaw,0.35)
		group.visible=active and army.transport_elapsed==0
		var marching: bool=not attacking and gait.weight>.001 and army.transport_id.is_empty() and army.transport_elapsed==0
		record.state="attack" if attacking else ("move" if marching else "held")
		var detailed: bool=gait.detailed
		var in_contact: bool=contact_partners.has(id)
		for index in range(record.motions.size()):
			if not in_contact:
				var r_changed: bool=record.motions[index].sample(clock,attacking,detailed,float(draws.get(id,0.0)) if record.role=="archers" else -1.0,marching,float(index%4)*.035,gait.march_clock,gait.weight)
				if record.role=="cavalry":
					record.horse_motions[index].sample(gait.march_clock,marching,detailed,float(index%4)*.035,gait.weight,clock)
					record.riders[index].sample()
			if record.role=="archers":
				var bow: Node3D=record.bows[index]
				bow.global_transform=Transform3D(group.global_basis*Basis(Vector3.FORWARD,PI/2.0).scaled(Vector3.ONE*.01),record.motions[index].wrist_position())
		if record.has("machine"):record.machine_motion.sample(clock,attacking,detailed)
	for id in infantry.formations:
		var record: Dictionary=infantry.formations[id];var army: Dictionary=simulation.armies[id]
		if not record.has("locomotion"):
			record.locomotion=[];record.stance_motions=[]
			for person in record.people:
				var motion:=RoleMotion.new();person.add_child(motion)
				if not motion.configure(person,"infantry"):push_error("Infantry source locomotion binding failed");return
				record.stance_motions.append(motion);record.locomotion.append(motion.locomotion)
		var attacking: bool=record.state=="attack"
		record.root.position=_steered_position(record,id,slots,clock)
		var gait: RefCounted=_march(record,army,record.root.position,clock,attacking)
		var moving: bool=not attacking and gait.weight>.001 and army.transport_id.is_empty() and army.transport_elapsed==0
		var detailed: bool=gait.detailed
		var in_contact: bool=contact_partners.has(id)
		for index in range(record.locomotion.size()):
			if attacking:
				record.stance_motions[index]._last_state="attack"
				if not in_contact:
					record.motions[index].set_speed(0.0);record.motions[index].seek(fposmod(clock,record.motions[index].clip_duration("attack")))
			else:record.stance_motions[index].sample(clock,false,detailed,-1.0,moving,float(index%4)*.035,gait.march_clock,gait.weight)
		if moving:record.state="move"
	for id in formations:
		var record: Dictionary=formations[id];var group: Node3D=record.root;var f_army: Dictionary=simulation.armies[id]
		var f_stance: String=str(f_army.get("stance","balanced"))
		if record.get("last_stance","balanced")!=f_stance:
			record.last_stance=f_stance;record.last_ground_pos=Vector3.INF;record.last_contact_ground=Vector3.INF
			var is_compact: bool=simulation.get("traditional_rts")==true
			var new_slots: Array=[]
			for slot_i in range(record.pivots.size()):
				var off: Vector3=_slot_offset(str(f_army.unit_type),slot_i,f_stance,is_compact)
				new_slots.append(off)
				record.pivots[slot_i].position.x=off.x;record.pivots[slot_i].position.z=off.z
			record.contact_slots=new_slots
		if not contact_partners.has(id):
			if record.get("last_ground_pos",Vector3.INF).distance_squared_to(group.position)>.0001 or not is_equal_approx(float(record.get("last_ground_yaw",INF)),group.rotation.y):
				record.last_ground_pos=group.position;record.last_ground_yaw=group.rotation.y
				for pivot in record.pivots:
					var point: Vector3=group.to_global(Vector3(pivot.position.x,0,pivot.position.z))
					pivot.position.y=float(controller.ground_sampler.call(point.x,point.z))-group.position.y
		record.hud_anchor=group.global_position
		if simulation.traditional_rts:
			var army: Dictionary=simulation.armies[id]
			FactionView.apply(record,army.faction)
			if not record.has("standard"):
				record.standard=TeamStandard.create(army.faction);record.root.add_child(record.standard)
			var alive: int=clampi(ceili(float(army.troops)*record.people.size()/maxi(1,army.original_troops)),0,record.people.size())
			if record.get("last_alive",-1)!=alive:
				record.last_alive=alive
				for i in range(record.people.size()):
					record.people[i].visible=i<alive
					if i<record.get("horses",[]).size():record.horses[i].visible=i<alive
					if i<record.get("bows",[]).size():record.bows[i].visible=i<alive
	contact_motion.sync(formations,clock,_allowed_field)
	controller.display_position=display_position
	controller.hud_position=hud_position

func _process(_delta: float) -> void:sync()

func _half_frame(role: String) -> Vector2:
	return Vector2(2.0,3.0) if role=="cavalry" else Vector2(2.1,2.3) if role=="siege" else Vector2(1.3,1.5)

func pick(screen: Vector2, faction_filter: String="") -> String:
	if not active or controller.camera==null:return ""
	var hit: String=""
	var origin: Vector3=controller.camera.project_ray_origin(screen);var direction: Vector3=controller.camera.project_ray_normal(screen)
	var nearest: float=INF
	for id in simulation._sorted_ids(formations):
		if not faction_filter.is_empty() and simulation.armies[id].faction!=faction_filter:continue
		var record: Dictionary=formations[id]
		if not record.root.visible:continue
		var root_pos: Vector3=record.root.global_position
		# White frame ground & volume raycast (interact by clicking directly on or inside the white frame):
		var half:=_half_frame(simulation.armies[id].unit_type)
		var local_origin: Vector3=record.root.to_local(origin)
		var local_dir: Vector3=(record.root.global_basis.inverse()*direction).normalized()
		if absf(local_dir.y)>0.0001:
			var t: float=-local_origin.y/local_dir.y
			if t>0.0:
				var hit_local: Vector3=local_origin+local_dir*t
				if absf(hit_local.x)<=half.x+0.35 and absf(hit_local.z)<=half.y+0.35:
					var world_p: Vector3=record.root.to_global(hit_local)
					var dist_sq: float=origin.distance_squared_to(world_p)
					if dist_sq<nearest:nearest=dist_sq;hit=id
		var frame_box:=AABB(Vector3(-half.x-0.3,-0.2,-half.y-0.3),Vector3((half.x+0.3)*2.0,3.4,(half.y+0.3)*2.0))
		var frame_hit=frame_box.intersects_ray(local_origin,local_dir)
		if frame_hit!=null:
			var world_hit: Vector3=record.root.to_global(frame_hit)
			var dist_sq: float=origin.distance_squared_to(world_hit)
			if dist_sq<nearest:nearest=dist_sq;hit=id
		var bounds:=AABB(root_pos+Vector3(-2.0,-0.2,-2.0),Vector3(4.0,3.2,4.0))
		var actors: Array=record.people.duplicate();var entries: Array=record.entries.duplicate()
		if record.has("horses"):
			for horse in record.horses:actors.append(horse);entries.append(catalog.assets.horse)
		if record.has("bows"):
			for bow in record.bows:actors.append(bow);entries.append(catalog.assets.bow)
		if record.has("machine"):actors.append(record.machine);entries.append(catalog.assets.siege)
		for index in range(actors.size()):
			if not actors[index].visible:continue
			var lo: Array=entries[index].bounds[0];var hi: Array=entries[index].bounds[1]
			var original:=AABB(Vector3(lo[0],lo[1],lo[2]),Vector3(hi[0]-lo[0],hi[1]-lo[1],hi[2]-lo[2]))
			bounds=bounds.merge(actors[index].global_transform*original)
		if record.has("standard") and is_instance_valid(record.standard):
			bounds=bounds.merge(record.standard.global_transform*AABB(Vector3(-.3,0,-.3),Vector3(1.6,3.0,1.6)))
		var point=bounds.grow(1.2).intersects_ray(origin,direction)
		if point!=null and origin.distance_squared_to(point)<nearest:nearest=origin.distance_squared_to(point);hit=id
	return hit
