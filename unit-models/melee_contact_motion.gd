extends RefCounted
## Bounded visual contact, individual footwork, and staggered source attacks.
## No navigation, combat damage, morale, save, mesh, or rest-pose mutation.
const PERIOD=1.15
const ENTRY_SECONDS=.55
const EXIT_SECONDS=.40
var simulation: RefCounted
var controller: Node3D
var states: Dictionary={}
var previous: Dictionary={}
var previous_hud: Dictionary={}
var last_clock: float=-1.0

func configure(sim: RefCounted, controls: Node3D) -> void:
	simulation=sim;controller=controls;reset()

func reset() -> void:
	states.clear();previous.clear();previous_hud.clear();last_clock=-1.0

static func strike(clock: float) -> float:
	var phase: float=fposmod(clock,PERIOD)/PERIOD
	if phase<.14:return -.10*sin(phase/.14*PI)
	if phase<.34:return smoothstep(.14,.34,phase)
	if phase<.46:return 1.0-.18*smoothstep(.34,.46,phase)
	if phase<.78:return .82*(1.0-smoothstep(.46,.78,phase))
	return 0.0

static func slot_clock(clock: float, index: int, side: int) -> float:
	return clock+float(index%4)*.075+float(index/4)*.16+float(side)*.12

func _field(id: String, formations: Dictionary) -> bool:
	if not formations.has(id) or not simulation.armies.has(id):return false
	var a: Dictionary=simulation.armies[id]
	if simulation.get("tactical_rts")==true and a.order.type in ["move","retreat"] and not a.route.is_empty():return false
	return a.troops>0 and not a.routed and a.transport_elapsed==0 and a.get("resident_city","").is_empty()

func _depth(role: String) -> float:
	return 3.0 if role=="cavalry" else 2.3 if role=="siege" else 1.5

func _partners(formations: Dictionary) -> Dictionary:
	var candidates: Array=[];var seen: Dictionary={};var partners: Dictionary={}
	for id in simulation._sorted_ids(formations):
		if not _field(id,formations):continue
		var a: Dictionary=simulation.armies[id]
		if a.unit_type not in ["infantry","cavalry"]:continue
		for enemy in a.engaged_ids:
			if not _field(enemy,formations) or simulation.armies[enemy].faction==a.faction:continue
			var p: Vector3=controller.grounded_position(id);var q: Vector3=controller.grounded_position(enemy)
			var distance: float=Vector2(q.x-p.x,q.z-p.z).length()
			if distance>16.0:continue
			var names: Array=[id,enemy];names.sort();var key: String=str(names)
			if seen.has(key):continue
			seen[key]=true;candidates.append({"names":names,"distance":distance,"key":key})
	candidates.sort_custom(func(a,b):return a.key<b.key if is_equal_approx(a.distance,b.distance) else a.distance<b.distance)
	for item in candidates:
		var names: Array=item.names
		if partners.has(names[0]) or partners.has(names[1]):continue
		partners[names[0]]=names[1];partners[names[1]]=names[0]
	return partners

func _ground(record: Dictionary) -> void:
	var group: Node3D=record.root
	group.global_position.y=float(controller.ground_sampler.call(group.global_position.x,group.global_position.z))
	var anchor: Vector3=record.hud_anchor
	anchor.y=float(controller.ground_sampler.call(anchor.x,anchor.z));record.hud_anchor=anchor
	if record.get("last_contact_ground",Vector3.INF).distance_squared_to(group.global_position)<.0025 and is_equal_approx(float(record.get("last_contact_yaw",INF)),group.rotation.y) and record.has("contact_pivot_y"):
		var ys: Array=record.contact_pivot_y
		for i in range(mini(ys.size(),record.pivots.size())):record.pivots[i].position.y=float(ys[i])
		return
	record.last_contact_ground=group.global_position;record.last_contact_yaw=group.rotation.y
	var pivot_ys: Array=[]
	for pivot in record.pivots:
		var point: Vector3=group.to_global(Vector3(pivot.position.x,0,pivot.position.z))
		var py: float=float(controller.ground_sampler.call(point.x,point.z))-group.global_position.y
		pivot.position.y=py;pivot_ys.append(py)
	record.contact_pivot_y=pivot_ys

func sync(formations: Dictionary, clock: float, allowed: Callable) -> void:
	if clock<last_clock:reset()
	last_clock=clock
	var partners: Dictionary=_partners(formations)
	for id in states.keys():
		if not _field(id,formations):states.erase(id);previous.erase(id);previous_hud.erase(id)
	for id in simulation._sorted_ids(formations):
		var record: Dictionary=formations[id];var group: Node3D=record.root
		if not record.has("hud_anchor"):record.hud_anchor=group.global_position
		if not record.has("contact_slots"):
			record.contact_slots=[]
			for pivot in record.pivots:record.contact_slots.append(pivot.position)
		for index in range(record.pivots.size()):
			var pivot: Node3D=record.pivots[index];var base: Vector3=record.contact_slots[index]
			pivot.position.x=base.x;pivot.position.z=base.z;pivot.rotation=Vector3.ZERO
		record.contact_active=false
		if partners.has(id):
			var enemy: String=partners[id]
			var p: Vector3=controller.grounded_position(id);var q: Vector3=controller.grounded_position(enemy)
			var forward: Vector3=q-p;forward.y=0
			if forward.length_squared()<.000001:forward=Vector3.RIGHT if id<enemy else Vector3.LEFT
			else:forward=forward.normalized()
			var role: String=simulation.armies[id].unit_type
			var gap: float=_depth(role)+_depth(simulation.armies[enemy].unit_type)+.35
			var destination: Vector3=(p+q)*.5-forward*gap*.5
			var anchor_destination: Vector3=destination
			var side: int=0 if id<enemy else 1
			var active_state: bool=states.has(id) and states[id].enemy==enemy and not states[id].get("leaving",false)
			if not active_state or states[id].get("base_dest",Vector3.INF).distance_squared_to(destination)>.01:
				if allowed.is_valid() and not allowed.call(destination,Vector2(4.8,5.4) if role=="cavalry" else Vector2(3.7,3.0)):continue
			# Different columns and factions strike at different instants.
			var pulse: float=strike(clock+float(side)*.12)
			var base_dest: Vector3=destination
			if not active_state:
				states[id]={"enemy":enemy,"start":clock,"origin":previous.get(id,group.global_position),"hud_origin":previous_hud.get(id,record.hud_anchor),"leaving":false,"base_dest":base_dest}
			else:
				states[id].base_dest=base_dest
			var elapsed: float=clock-float(states[id].start)
			var entry: float=smoothstep(0.0,ENTRY_SECONDS,elapsed)
			group.global_position=Vector3(states[id].origin).lerp(base_dest,entry)
			# The banner follows entry/exit, but never the repeated strike surge.
			record.hud_anchor=Vector3(states[id].hud_origin).lerp(anchor_destination,entry)
			group.rotation.y=lerp_angle(group.rotation.y,atan2(forward.x,forward.z),0.35)
			record.contact_active=true;record.contact_enemy=enemy;record.contact_entry=entry;record.display_forward=forward
			var detailed: bool=record.march.detailed if record.has("march") else controller.camera==null or controller.camera.global_position.distance_to(group.global_position)<75.0
			if not record.has("contact_stamps"):record.contact_stamps=[-1,-1,-1,-1,-1,-1,-1,-1]
			for index in range(record.pivots.size()):
				var pivot: Node3D=record.pivots[index];var personal_clock: float=slot_clock(clock,index,side)
				var base: Vector3=record.contact_slots[index]
				pivot.position=base;pivot.rotation=Vector3.ZERO
				var contact_stamp: int=int(personal_clock*24.0)*64+int(entry*32.0)
				if record.contact_stamps[index]!=contact_stamp:
					record.contact_stamps[index]=contact_stamp
					if role=="infantry":
						var motion=record.motions[index]
						motion.player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
						motion.set_state("attack");motion.set_speed(0.0)
						motion.seek(fposmod(personal_clock,motion.clip_duration("attack")))
					elif role=="cavalry":
						record.motions[index].sample(personal_clock,true,detailed)
						record.horse_motions[index].sample(personal_clock,false,detailed,0.0,0.0,personal_clock)
				if role=="cavalry":
					record.riders[index].sample()
			_ground(record)
		elif states.has(id):
			if record.has("contact_stamps"):record.contact_stamps=[-1,-1,-1,-1,-1,-1,-1,-1]
			if not states[id].leaving:states[id]={"enemy":"","leaving":true,"start":clock,"origin":previous.get(id,group.global_position),"hud_origin":previous_hud.get(id,record.hud_anchor)}
			var factor: float=smoothstep(0.0,EXIT_SECONDS,clock-float(states[id].start))
			group.global_position=Vector3(states[id].origin).lerp(group.global_position,factor)
			record.hud_anchor=Vector3(states[id].hud_origin).lerp(record.hud_anchor,factor)
			_ground(record)
			if record.get("role","")=="cavalry" and record.has("riders"):
				for rider in record.riders:rider.sample()
			if factor>=1.0:states.erase(id)
		previous[id]=group.global_position
		previous_hud[id]=record.hud_anchor
	for id in previous.keys():
		if not formations.has(id):previous.erase(id);previous_hud.erase(id)
