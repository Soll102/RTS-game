extends Node3D
## Isolated pending source-model/motion composition, never a production asset gate.
const Motion=preload("res://attack-motion/source_rig_motion.gd")
const REUSE=[0,0,0,0,0,0,0,0]
var simulation: RefCounted
var controller: Node3D
var catalog: Dictionary={}
var formations: Dictionary={}
var scenes: Dictionary={}
var active: bool=false
var source_height: float=2.2
var _event_tick: int=-1

func configure(sim: RefCounted, controls: Node3D) -> String:
	if sim==null or controls==null or not controls.ground_sampler.is_valid():return "Source motion review requires actual campaign grounding."
	catalog=JSON.parse_string(FileAccess.get_file_as_string("res://attack-motion/animation-catalog.json"))
	if catalog.get("schema")!=1 or catalog.get("approved",true) or catalog.models.size()!=1:return "Pending source motion dependencies are required."
	for entry in catalog.models:
		if FileAccess.get_sha256("res://"+entry.file)!=entry.sha256:return "Exact source bytes differ: "+entry.id
		var packed:=load("res://"+entry.file) as PackedScene
		if packed==null:return "Source scene failed to import: "+entry.id
		scenes[entry.id]=packed
	simulation=sim;controller=controls
	return ""

func reset() -> void:
	for record in formations.values():record.root.queue_free()
	formations.clear();_event_tick=-1

func _create(id: String) -> String:
	var army: Dictionary=simulation.armies[id]
	var root:=Node3D.new();root.name="SourceReview_"+id;add_child(root)
	var people: Array=[];var pivots: Array=[];var motions: Array=[];var entries: Array=[]
	var compact: bool=simulation.get("traditional_rts")==true
	for slot in range(4 if compact else 8):
		var entry: Dictionary=catalog.models[0]
		var pivot:=Node3D.new();root.add_child(pivot)
		pivot.position=Vector3((slot%2-.5)*1.5,0,(int(slot/2)-.5)*2.0) if compact else Vector3((slot%4-1.5)*1.5,0,(int(slot/4)-.5)*1.75)
		var actor: Node3D=scenes[entry.id].instantiate();pivot.add_child(actor)
		var height: float=1.8 if compact else source_height
		var factor: float=height/(float(entry.bounds[1][1])-float(entry.bounds[0][1]))
		actor.scale=Vector3.ONE*factor;actor.position=Vector3(0,-float(entry.bounds[0][1])*factor,0)
		var motion:=Motion.new();actor.add_child(motion)
		if not motion.configure(actor,entry.id,"res://attack-motion/animation-catalog.json"):root.queue_free();return "Source Skin/rig/clip binding failed: "+entry.id
		# One explicit simulation sample owns the pose, including procedural legs.
		motion.player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		people.append(actor);pivots.append(pivot);motions.append(motion);entries.append(entry)
	formations[id]={"root":root,"people":people,"pivots":pivots,"motions":motions,"entries":entries,
		"previous":Vector3.INF,"gesture_until":0,"was_alive":true,"state":"rest"}
	return ""

func _events() -> void:
	for event in simulation.events:
		if int(event.get("tick",0))<=_event_tick:continue
		var id: String=str(event.get("army",""))
		if event.get("type")=="commander_skill" and formations.has(id):formations[id].gesture_until=simulation.tick+12
	_event_tick=simulation.tick

func sync() -> void:
	if simulation==null:return
	if simulation.tick<_event_tick:reset()
	for id in formations.keys():
		if not simulation.armies.has(id) or simulation.armies[id].troops<=0 or not simulation.armies[id].get("resident_city","").is_empty():
			formations[id].root.visible=false;formations[id].root.queue_free();formations.erase(id)
	for id in simulation._sorted_ids(simulation.armies):
		var army: Dictionary=simulation.armies[id]
		if army.unit_type!="infantry" or army.troops<=0 or not army.get("resident_city","").is_empty():continue
		if not formations.has(id):
			var error: String=_create(id)
			if not error.is_empty():push_error(error);active=false;return
	_events()
	for id in formations:
		var army: Dictionary=simulation.armies[id];var record: Dictionary=formations[id];var root: Node3D=record.root
		var alive: bool=army.troops>0
		if alive and not record.was_alive:
			record.previous=Vector3.INF;record.gesture_until=0
			for motion in record.motions:motion.reset_to_rest()
		record.was_alive=alive
		var p: Vector3=controller.grounded_position(id)
		p.y=float(controller.ground_sampler.call(p.x,p.z));root.position=p
		var moving: bool=false
		if alive and record.previous.is_finite():
			var delta: Vector3=p-record.previous;delta.y=0
			moving=delta.length_squared()>.000001
			# The active role adapter owns the smoothed travel heading.
		if alive:record.previous=p
		# Movement keeps the original source rest; only attack is animated.
		moving=moving or (alive and not army.route.is_empty() and army.engaged_ids.is_empty() and army.transport_elapsed==0)
		var state: String="attack" if alive and (simulation.tick<record.gesture_until or not army.engaged_ids.is_empty() or army.siege_state in ["besieging","breached"]) else "rest"
		if simulation.get("tactical_rts")==true and army.order.type in ["move","retreat"] and not army.route.is_empty():state="rest"
		if state=="attack":
			var aim: Vector3=Vector3.INF
			if not army.engaged_ids.is_empty() and simulation.armies.has(army.engaged_ids[0]):aim=controller.grounded_position(army.engaged_ids[0])
			elif army.order.type=="siege" and simulation.cities.has(army.order.target):aim=controller.city_positions.get(army.order.target,controller.node_positions[simulation._target_node(army.order)])
			if aim.is_finite() and Vector2(aim.x-p.x,aim.z-p.z).length_squared()>.0001:root.rotation.y=atan2(aim.x-p.x,aim.z-p.z)
		record.state=state
		root.visible=active and army.transport_elapsed==0 and alive
		if record.has("locomotion"):continue
		for index in range(record.motions.size()):
			var motion=record.motions[index]
			motion.set_state(state)
			var multiplier: float=0.0 if simulation.paused or not active else float(simulation.speed)
			motion.set_speed(multiplier)
			var pivot: Node3D=record.pivots[index]
			var point: Vector3=root.to_global(Vector3(pivot.position.x,0,pivot.position.z))
			pivot.position.y=float(controller.ground_sampler.call(point.x,point.z))-p.y

func _process(_delta: float) -> void:sync()

func pick(screen: Vector2) -> String:
	if not active or controller.camera==null:return ""
	var origin: Vector3=controller.camera.project_ray_origin(screen)
	var direction: Vector3=controller.camera.project_ray_normal(screen)
	var chosen: String="";var nearest: float=INF
	for id in simulation._sorted_ids(formations):
		var record: Dictionary=formations[id]
		if not record.root.visible or simulation.armies[id].troops<=0 or not simulation.armies[id].get("resident_city","").is_empty():continue
		var box:=AABB();var first: bool=true
		for index in range(record.people.size()):
			var entry: Dictionary=record.entries[index];var lo: Array=entry.bounds[0];var hi: Array=entry.bounds[1]
			var original:=AABB(Vector3(lo[0],lo[1],lo[2]),Vector3(hi[0]-lo[0],hi[1]-lo[1],hi[2]-lo[2]))
			var current: AABB=record.people[index].global_transform*original
			box=current if first else box.merge(current);first=false
		var hit=box.grow(.25).intersects_ray(origin,direction)
		if hit!=null:
			var distance: float=origin.distance_squared_to(hit)
			if distance<nearest:nearest=distance;chosen=id
	return chosen
