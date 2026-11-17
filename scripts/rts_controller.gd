extends Node3D
const GroupOrders=preload("res://scripts/rts_group_orders.gd")
const OrderInput=preload("res://scripts/rts_order_input.gd")
## Connects data simulation to injected visuals; never loads or creates game assets.
## Review callers must stage their scene outside the gameplay project.

signal selection_changed(ids: Array)
signal order_result(error: String)
signal order_feedback(text: String, failed: bool)
signal context_order_accepted(target: Dictionary)
signal city_selection_changed(id: String)

var simulation: RefCounted
var node_positions: Dictionary = {}
var visual_bindings: Dictionary = {}
var selected_armies: Array = []
var player_faction: String = "red"
var camera: Camera3D
var hud: CanvasLayer
var controls_enabled: bool = true
var terrain_collision_mask: int = 1
var terrain_height: float = 0.0
var pick_radius_pixels: float = 24.0
var max_snap_distance: float = INF
var drag_threshold_pixels: float = 8.0
var _drag_start: Vector2 = Vector2.ZERO
var _dragging: bool = false
var _command_sequence: int = 0
const MotionTrack=preload("res://scripts/rts_motion_track.gd")
var _motion_tracks: Dictionary={}
var presentation_revision: int=0
var _previous_positions: Dictionary = {}
var _tick_paths: Dictionary={}
var _path_tick: int=-1
var accepted_order: Dictionary={}
var _time_fraction_us: float = 0.0
var selected_city: String = ""
var control_groups: Dictionary = {}
var city_positions: Dictionary = {}
var city_hud_position: Callable
var ground_picker: Callable
var ground_sampler: Callable
var camera_focus: Callable
var display_position: Callable
var hud_position: Callable
var screen_offset: Callable
var entity_visual_pick: Callable
var friendly_visual_pick: Callable
var city_screen_offset: Vector2=Vector2.ZERO

func configure(sim: RefCounted, positions: Dictionary, bindings: Dictionary = {}, mode: String = "review", approval_manifest: Array = []) -> String:
	if mode not in ["review", "gameplay"] or sim == null or not sim.has_method("submit_command"):
		return "Controller mode or simulation is invalid."
	for id in sim.nodes:
		if not positions.has(id) or not positions[id] is Vector3 or not positions[id].is_finite():
			return "Every navigation node requires a finite Vector3 visual position."
	for entity_id in bindings:
		var binding = bindings[entity_id]
		if not binding is Dictionary or not binding.get("node") is Node3D or not is_instance_valid(binding["node"]):
			return "Visual binding requires an existing Node3D."
		if not sim.armies.has(entity_id) and not sim.cities.has(entity_id):
			return "Visual binding references an unknown entity."
		if mode == "gameplay" and not _binding_approved(binding, approval_manifest):
			return "Visual binding is not approved for this exact asset/version/use: " + str(entity_id)
	simulation = sim
	node_positions = positions.duplicate()
	visual_bindings = bindings.duplicate()
	selected_armies.clear()
	selected_city = ""
	control_groups.clear()
	_time_fraction_us = 0.0
	_command_sequence = 0
	_dragging = false
	reset_interpolation();accepted_order.clear()
	return ""

func _binding_approved(binding: Dictionary, manifest: Array) -> bool:
	for key in ["asset_review_id", "sha256", "intended_use"]:
		if not binding.get(key) is String or binding[key].is_empty():
			return false
	var version = binding.get("version")
	if not ((version is String and not version.is_empty()) or (version is int and version > 0)):
		return false
	for entry in manifest:
		if entry is Dictionary and entry.get("status", "") == "approved" and entry.get("id", "") == binding["asset_review_id"] and entry.get("version", "") == binding["version"] and entry.get("sha256", "") == binding["sha256"] and entry.get("intended_use", "") == binding["intended_use"]:
			return true
	return false

func attach_camera(value: Camera3D) -> void:
	camera = value

func attach_hud(value: CanvasLayer) -> void:
	hud = value
	if hud == null:
		return
	hud.pause_requested.connect(toggle_pause)
	hud.speed_requested.connect(change_speed)
	hud.hold_requested.connect(hold_selected)
	hud.retreat_requested.connect(retreat_selected)
	hud.focus_requested.connect(focus_selection)
	_refresh_hud()

func _process(delta: float) -> void:
	if simulation == null:
		return
	_time_fraction_us += maxf(0.0, delta) * 1000000.0
	var elapsed: int = int(_time_fraction_us)
	_time_fraction_us -= elapsed
	advance_time_us(elapsed, 8)
	sync_visuals()

func advance_time_us(elapsed_us: int, max_ticks: int = 0) -> int:
	if simulation!=null:simulation.speed=1
	if simulation == null or simulation.paused or elapsed_us < 0:
		return 0
	simulation.accumulator_us += elapsed_us * simulation.speed
	var processed: int = 0
	while simulation.accumulator_us >= simulation.TICK_US and (max_ticks <= 0 or processed < max_ticks):
		simulation.accumulator_us -= simulation.TICK_US
		_previous_positions = _current_positions()
		var passengers: Dictionary={}
		for id in simulation.armies:passengers[id]=simulation.armies[id].get("transport_elapsed",0)>0
		simulation.step()
		_tick_paths.clear();_path_tick=simulation.tick
		var traces=simulation.get("movement_traces")
		if traces is Dictionary:
			var units: float=float(simulation.world_metadata.get("coordinate_units_per_world",10))
			for id in traces:
				var points: Array=[]
				for point in traces[id]:points.append(point/units)
				if passengers.get(id,false) and simulation.armies[id].transport_elapsed==0:points=[army_position(id)]
				_tick_paths[id]=points
				if not _motion_tracks.has(id):_motion_tracks[id]=MotionTrack.new()
				var army: Dictionary=simulation.armies[id]
				_motion_tracks[id].capture(points,simulation.tick,army.order.type!="hold" and not army.route.is_empty() and army.transport_elapsed==0)
		processed += 1
		if simulation.paused:
			break
	if simulation.has_method("settle_subtick_events"):simulation.settle_subtick_events()
	_prune_selection()
	_refresh_hud()
	return processed

func army_position(id: String) -> Vector3:
	if simulation == null or not simulation.armies.has(id):
		return Vector3.ZERO
	var army: Dictionary = simulation.armies[id]
	if simulation.has_method("army_position_units"):return simulation.army_position_units(army)/float(simulation.world_metadata.get("coordinate_units_per_world",10))
	var origin: Vector3 = node_positions[army["node"]]
	if army["route"].is_empty():
		return origin
	var next: String = str(army["route"][0])
	var edge_length: float = float(simulation.nodes[army["node"]]["edges"][next])
	return origin.lerp(node_positions[next], clampf(float(army["edge_progress"]) / edge_length, 0.0, 1.0))

func grounded_position(id: String) -> Vector3:
	var point := interpolated_position(id)
	if ground_sampler.is_valid(): point.y = ground_sampler.call(point.x,point.z)
	return point

func _current_positions() -> Dictionary:
	var positions: Dictionary = {}
	if simulation != null:
		for id in simulation.armies:
			positions[id] = army_position(str(id))
	return positions

func reset_interpolation() -> void:
	presentation_revision+=1
	_previous_positions=_current_positions();_tick_paths.clear();_motion_tracks.clear();_path_tick=-1

func interpolated_position(id: String) -> Vector3:
	var current: Vector3=army_position(id)
	if simulation==null:return current
	var alpha: float=clampf(float(simulation.accumulator_us)/simulation.TICK_US,0,1)
	if simulation.armies.has(id) and simulation.armies[id].get("transport_elapsed",0)>0 and simulation.has_method("vessel_display_position"):
		for boat in simulation.vessels.values():
			if boat.phase=="occupied" and boat.request=="army:"+id:
				return simulation.vessel_display_position(boat.id,alpha)/float(simulation.world_metadata.get("coordinate_units_per_world",10))
	var points: Array=_tick_paths.get(id,[]) if _path_tick==simulation.tick else []
	if not points.is_empty() and points[-1].distance_to(current)<.001 and _motion_tracks.has(id):return _motion_tracks[id].sample(alpha)
	if not points.is_empty() and points[-1].distance_to(current)<.001:
		var total: float=0
		for i in range(points.size()-1):total+=points[i].distance_to(points[i+1])
		var remaining: float=total*alpha
		for i in range(points.size()-1):
			var length: float=points[i].distance_to(points[i+1])
			if remaining<=length:return points[i].lerp(points[i+1],remaining/maxf(.000001,length))
			remaining-=length
		return current
	if simulation.paused:return current
	return _previous_positions.get(id,current).lerp(current,alpha)

func sync_visuals() -> void:
	if simulation == null:
		return
	for id in visual_bindings:
		var visual = visual_bindings[id]["node"]
		if not is_instance_valid(visual):
			continue
		var local_point: Vector3
		if simulation.armies.has(id):
			local_point = grounded_position(str(id))
			visual.visible = int(simulation.armies[id]["troops"]) > 0
		else:
			var city_node: String=str(simulation.cities[id]["node"])
			if node_positions.has(city_node):local_point=node_positions[city_node]
			elif city_positions.has(id):local_point=city_positions[id]
			else:visual.visible=false;continue
		if visual.is_inside_tree() and is_inside_tree():
			visual.global_position = to_global(local_point)
		else:
			visual.position = local_point

func select_armies(ids: Array, additive: bool = false) -> void:
	if simulation == null:
		return
	var result: Array = selected_armies.duplicate() if additive else []
	for id in ids:
		if simulation.armies.has(id) and simulation.armies[id]["faction"] == player_faction and int(simulation.armies[id]["troops"]) > 0 and not result.has(id):
			result.append(id)
	result.sort()
	selected_armies = result
	selected_city = ""
	selection_changed.emit(selected_armies.duplicate())
	_refresh_hud()

func toggle_army(id: String) -> void:
	var selection: Array = selected_armies.duplicate()
	if selection.has(id): selection.erase(id)
	else: selection.append(id)
	select_armies(selection)

func select_city(id: String) -> void:
	if simulation == null or not simulation.cities.has(id): return
	selected_armies.clear()
	selected_city = id
	selection_changed.emit([])
	city_selection_changed.emit(id)
	_refresh_hud()

func store_control_group(group: int) -> void:
	if group < 1 or group > 9: return
	_prune_selection()
	control_groups[group] = selected_armies.duplicate()

func recall_control_group(group: int, additive: bool = false) -> void:
	select_armies(control_groups.get(group,[]),additive)

func set_stance(stance: String) -> String:
	return _report("Select an army first.") if simulation == null or selected_armies.is_empty() else _submit("stance",stance)

func _prune_selection() -> void:
	var filtered: Array = []
	for id in selected_armies:
		if simulation.armies.has(id) and simulation.armies[id]["faction"] == player_faction and int(simulation.armies[id]["troops"]) > 0:
			filtered.append(id)
	if filtered != selected_armies:
		selected_armies = filtered
		selection_changed.emit(selected_armies.duplicate())

func select_screen_rectangle(rectangle: Rect2, projected_positions: Dictionary = {}, additive: bool = false) -> void:
	var positions: Dictionary = projected_positions if not projected_positions.is_empty() else OrderInput.positions(self,true) if simulation.get("tactical_rts")==true else _screen_positions("army")
	var inside: Array = []
	for id in positions:
		if rectangle.abs().has_point(positions[id]):
			inside.append(id)
	select_armies(inside, additive)

func _screen_positions(kind: String) -> Dictionary:
	var result: Dictionary = {}
	if simulation == null or camera == null or not camera.is_inside_tree():
		return result
	var table: Dictionary = simulation.armies if kind == "army" else simulation.cities
	for id in table:
		if kind == "army" and int(table[id]["troops"]) <= 0:
			continue
		var local_point: Vector3
		if kind=="army":local_point=hud_position.call(str(id)) if hud_position.is_valid() else display_position.call(str(id)) if display_position.is_valid() else grounded_position(str(id))
		elif city_hud_position.is_valid():local_point=city_hud_position.call(str(id))
		elif city_positions.has(id):local_point=city_positions[id]
		elif node_positions.has(table[id]["node"]):local_point=node_positions[table[id]["node"]]
		else:continue
		if not local_point.is_finite():continue
		var point: Vector3 = to_global(local_point)
		if not camera.is_position_behind(point):
			result[id] = camera.unproject_position(point)
			if kind=="army" and screen_offset.is_valid():result[id]+=screen_offset.call(str(id))
			elif kind=="city":result[id]+=city_screen_offset
	return result

func pick_entity(screen_point: Vector2, prefer_gates: bool=false, friendly: bool=false) -> Dictionary:
	if simulation.get("tactical_rts")==true:return OrderInput.pick(self,screen_point,prefer_gates,friendly)
	# Stable nearest-distance tie break; armies take priority over cities.
	for kind in ["army", "city"]:
		if kind=="city" and prefer_gates:
			var gate: Dictionary=_gate_at(screen_point)
			if not gate.is_empty():return gate
		var positions: Dictionary = _screen_positions(kind)
		var ids: Array = positions.keys()
		ids.sort()
		var chosen: String = ""
		var best: float = pick_radius_pixels * pick_radius_pixels
		for id in ids:
			var distance: float = screen_point.distance_squared_to(positions[id])
			if distance < best:
				chosen = str(id)
				best = distance
		if not chosen.is_empty():
			return {"kind": kind, "id": chosen}
		if kind=="army" and prefer_gates:
			var gate: Dictionary=_gate_at(screen_point)
			if not gate.is_empty():return gate
		if kind=="army" and entity_visual_pick.is_valid():
			var visual_id: String=entity_visual_pick.call(screen_point)
			if not visual_id.is_empty():return {"kind":"army","id":visual_id}
	return _gate_at(screen_point)

func _gate_at(screen_point: Vector2) -> Dictionary:
	if simulation.has_method("gate_nodes") and camera!=null and camera.is_inside_tree():
		var chosen: Dictionary={};var best: float=minf(16,pick_radius_pixels)*minf(16,pick_radius_pixels)
		for city_id in simulation._sorted_ids(simulation.cities):
			for gate in simulation.gate_nodes(city_id):
				if not node_positions.has(gate):continue
				var point: Vector3=to_global(node_positions[gate])+Vector3.UP*.25
				if camera.is_position_behind(point):continue
				var distance: float=screen_point.distance_squared_to(camera.unproject_position(point))
				if distance<best:best=distance;chosen={"kind":"gate","id":city_id,"gate_node":gate}
		if not chosen.is_empty():return chosen
	return {}

## One rule for destinations and routing. The old footprint test rejected 205
## nodes that Dijkstra still used, so clicks were discarded as "blocked" while
## units happily took shortcuts through the very same points.
func _destination_clear(node: String, _army_id: String="") -> bool:
	if simulation==null or not simulation.nodes.has(node):return false
	if simulation.has_method("is_navigation_open"):return simulation.is_navigation_open(node)
	return bool(simulation.nodes[node].get("passable",true))

func nearest_node(point: Vector3) -> String:
	if simulation == null:
		return ""
	var ids: Array = node_positions.keys()
	ids.sort()
	var chosen: String = ""
	var best: float = INF
	for id in ids:
		if not _destination_clear(str(id)):continue
		var distance: float = point.distance_squared_to(node_positions[id])
		if distance<best:chosen=str(id);best=distance
	if chosen.is_empty():return ""
	var on_water: bool=simulation.get("river_navigation")!=null and simulation.river_navigation.contains(Vector2(point.x,point.z)*10.0)
	var snap: float=maxf(max_snap_distance,32.0) if simulation.get("tactical_rts")==true else max_snap_distance
	return chosen if on_water else "" if best>snap*snap else chosen

func terrain_point(screen_point: Vector2):
	if ground_picker.is_valid(): return ground_picker.call(screen_point)
	if camera == null or not camera.is_inside_tree() or not is_inside_tree():
		return null
	var origin: Vector3 = camera.project_ray_origin(screen_point)
	var direction: Vector3 = camera.project_ray_normal(screen_point)
	var query = PhysicsRayQueryParameters3D.create(origin, origin + direction * 10000.0, terrain_collision_mask)
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		return to_local(hit["position"])
	# Review maps may have no collision; the explicit fallback is a plane, no mesh.
	var normal := global_basis.y.normalized()
	var plane = Plane(normal, normal.dot(to_global(Vector3(0, terrain_height, 0))))
	var global_hit = plane.intersects_ray(origin, direction)
	if global_hit==null:return null
	return to_local(global_hit)

func issue_context_order(target: Dictionary, append: bool=false) -> String:
	if simulation == null or selected_armies.is_empty():
		return _report("Select an army first.")
	var kind: String = str(target.get("kind", "node"))
	var id: String = str(target.get("id", ""))
	if append and simulation.get("tactical_rts")!=true:return _report("Queued orders require a new campaign.")
	if kind=="attack_move":return move_group(id,"attack_move",append) if selected_armies.size()>1 else _submit("attack_move",id,"",append)
	if kind == "army":
		if not simulation.armies.has(id):
			return _report("Army target does not exist.")
		if simulation.armies[id]["faction"] != player_faction:
			return _submit("attack",id,"",append)
		return move_group(str(simulation.armies[id].node),"move",append) if selected_armies.size()>1 else _submit("move",str(simulation.armies[id].node),"",append)
	if kind in ["city","gate"]:
		if not simulation.cities.has(id):
			return _report("City target does not exist.")
		if simulation.cities[id]["owner"] != player_faction:
			return _submit("siege",id,str(target.get("gate_node","")),append)
		return move_group(str(target.get("gate_node",simulation.cities[id].node)),"move",append) if selected_armies.size()>1 else _submit("move",str(target.get("gate_node",simulation.cities[id].node)),"",append)
	return move_group(id,"move",append) if selected_armies.size()>1 else _submit("move",id,"",append)

func move_group(target: String, kind: String="move", append: bool=false) -> String:
	if simulation==null:return _report("Campaign is not configured.")
	if kind not in ["move","attack_move"]:return _report("Group movement order is invalid.")
	_prune_selection()
	if selected_armies.is_empty():return _report("Select an army first.")
	if not _destination_clear(target):return _report("Move target is blocked or does not exist.")
	if simulation.get("tactical_rts")==true:
		var plan: Dictionary=GroupOrders.plan(self,target)
		return _report(plan.error) if not plan.error.is_empty() else _submit_assignments(kind,plan.assignments,append)
	# Gather a local land-connected destination cluster. A nearby point across a
	# ferry must not split a group between opposite banks of the same click.
	var crossings: Array=[]
	if simulation.has_method("army_position_units"):crossings=simulation.world_metadata.get("crossings",[])
	var candidates: Array=[target];var visited: Dictionary={target:true};var cursor: int=0
	while cursor<candidates.size() and candidates.size()<128:
		var current: String=candidates[cursor];cursor+=1
		for neighbor in simulation._sorted_ids(simulation.nodes[current].edges):
			if visited.has(neighbor) or not _destination_clear(neighbor):continue
			if node_positions[neighbor].distance_to(node_positions[target])>12:continue
			var ferry: bool=false
			for crossing in crossings:
				if current in crossing.nodes and neighbor in crossing.nodes:ferry=true;break
			if ferry:continue
			visited[neighbor]=true;candidates.append(neighbor)
	candidates.sort_custom(func(a,b):
		var da: float=node_positions[a].distance_squared_to(node_positions[target])
		var db: float=node_positions[b].distance_squared_to(node_positions[target])
		return str(a)<str(b) if is_equal_approx(da,db) else da<db)
	var assignments: Dictionary={};var used: Dictionary={}
	for army_id in selected_armies:
		for node in candidates:
			if used.has(node) or not _destination_clear(node,army_id) or not simulation.find_path(simulation.armies[army_id].node,node).ok:continue
			assignments[army_id]=node;used[node]=true;break
		# Never fall back to an unreachable target. Sharing an already validated
		# destination is fine; sending a formation into an invalid route is not.
		if not assignments.has(army_id):
			if not simulation.find_path(simulation.armies[army_id].node,target).ok:return _report("No clear destination for the entire group.")
			assignments[army_id]=target
	return _submit_assignments(kind,assignments)

func _submit_assignments(kind: String, assignments: Dictionary, append: bool=false) -> String:
	# Rejected move/retreat batches never leave only some selected armies ordered.
	var previous_ids: Dictionary=simulation.command_ids.duplicate(true)
	var previous_queue: Array=simulation.command_queue.duplicate(true)
	for army_id in selected_armies:
		_command_sequence+=1
		var id: String="controller-%d-%d"%[simulation.tick,_command_sequence]
		while simulation.command_ids.has(id):_command_sequence+=1;id="controller-%d-%d"%[simulation.tick,_command_sequence]
		var error: String=simulation.submit_command({"command_id":id,"faction":player_faction,"army_ids":[army_id],"type":kind,"target":assignments[army_id],"append":append})
		if not error.is_empty():
			simulation.command_ids=previous_ids;simulation.command_queue=previous_queue
			return _report(error)
	accepted_order={"kind":"node","id":assignments[selected_armies[0]],"assignments":assignments.duplicate(),"order":kind,"queued":append}
	if not simulation.paused:simulation._apply_commands()
	return _report("","Group %s order issued."%kind)

func _submit(kind: String, target: String, gate: String="", append: bool=false) -> String:
	_prune_selection()
	_command_sequence += 1
	var command_id: String = "controller-%d-%d" % [simulation.tick, _command_sequence]
	while simulation.command_ids.has(command_id):
		_command_sequence += 1
		command_id = "controller-%d-%d" % [simulation.tick, _command_sequence]
	var command: Dictionary={"command_id":command_id,"faction":player_faction,"army_ids":selected_armies.duplicate(),"type":kind,"target":target,"append":append}
	if not gate.is_empty():command.gate_node=gate
	var error: String=simulation.submit_command(command)
	if error.is_empty():
		accepted_order={"kind":"army" if kind=="attack" else "gate" if kind=="siege" and not gate.is_empty() else "city" if kind=="siege" else "node","id":target,"order":kind,"assignments":{}}
		accepted_order.queued=append
		if kind=="siege":accepted_order.gate_node=gate if not gate.is_empty() else simulation.choose_siege_gate(simulation.armies[selected_armies[0]],target)
		for id in selected_armies:
			if kind in ["move","retreat","attack_move"]:accepted_order.assignments[id]=target
			elif kind=="siege":accepted_order.assignments[id]=gate if not gate.is_empty() else simulation.choose_siege_gate(simulation.armies[id],target)
		if not simulation.paused:simulation._apply_commands()
	return _report(error,"Order added to queue." if append else "Stopped." if kind=="hold" else "%s order issued."%kind.capitalize())

func hold_selected() -> String:
	return _report("Select an army first.") if simulation == null or selected_armies.is_empty() else _submit("hold", "")

func retreat_selected() -> String:
	if simulation==null:return _report("Select an army first.")
	_prune_selection()
	if selected_armies.is_empty():return _report("Select an army first.")
	var cities: Array=simulation.cities.keys();cities.sort()
	var assignments: Dictionary={}
	for army_id in selected_armies:
		var best_distance: int=2147483647;var target: String=""
		for city_id in cities:
			var city: Dictionary=simulation.cities[city_id]
			if city.owner!=player_faction:continue
			var path: Dictionary=simulation.find_path(str(simulation.armies[army_id].node),str(city.node))
			if path.ok and int(path.distance)<best_distance:best_distance=int(path.distance);target=str(city.node)
		if target.is_empty():return _report("No reachable friendly city for the entire retreat group.")
		assignments[army_id]=target
	return _submit_assignments("retreat",assignments)

func toggle_pause() -> void:
	if simulation != null:
		if simulation.get("match_state") == "finished": return
		simulation.paused = not simulation.paused
		_refresh_hud()

func change_speed(value: int) -> bool:
	if simulation == null:
		return false
	var accepted: bool = simulation.set_speed(value)
	_refresh_hud()
	return accepted

func focus_selection() -> void:
	if camera_focus.is_valid() and not selected_armies.is_empty():
		var point := Vector3.ZERO
		for id in selected_armies: point+=army_position(str(id))
		camera_focus.call(point/selected_armies.size())
		return
	if camera == null or not camera.has_method("focus_at") or selected_armies.is_empty():
		return
	var center: Vector3 = Vector3.ZERO
	for id in selected_armies:
		center += army_position(str(id))
	var focus_point: Vector3 = center / selected_armies.size()
	if is_inside_tree() and camera.is_inside_tree():
		focus_point = camera.get_parent().to_local(to_global(focus_point)) if camera.get_parent() is Node3D else to_global(focus_point)
	camera.focus_at(focus_point)

func select_all_armies() -> void:
	var ids: Array=[]
	for id in simulation._sorted_ids(simulation.armies):
		var army: Dictionary=simulation.armies[id]
		if army.faction==player_faction and army.troops>0 and army.get("resident_city","").is_empty():ids.append(id)
	select_armies(ids)

func select_same_type(id: String, additive: bool=false) -> void:
	if not simulation.armies.has(id):return
	var type: String=simulation.armies[id].unit_type;var ids: Array=[]
	var viewport: Rect2=get_viewport().get_visible_rect()
	var positions: Dictionary=OrderInput.positions(self,true)
	for other in positions:
		if simulation.armies[other].unit_type==type and viewport.has_point(positions[other]):ids.append(other)
	select_armies(ids,additive)

func _report(error: String, success: String = "") -> String:
	order_result.emit(error)
	if not error.is_empty() or not success.is_empty():order_feedback.emit(error if not error.is_empty() else success,not error.is_empty())
	if hud != null and hud.has_method("show_message"):
		hud.show_message(error if not error.is_empty() else success)
	return error

func _refresh_hud() -> void:
	if hud != null and simulation != null and hud.has_method("update_state"):
		hud.update_state(simulation, selected_armies)

func _unhandled_input(event: InputEvent) -> void:
	if not controls_enabled or simulation == null:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed and camera != null and camera.has_method("zoom"):
			camera.zoom(-1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed and camera != null and camera.has_method("zoom"):
			camera.zoom(1)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if event.double_click and simulation.get("tactical_rts")==true:
					var hit: Dictionary=pick_entity(event.position,false,true)
					if hit.get("kind")=="army":select_same_type(hit.id,event.shift_pressed);_dragging=false;return
				_drag_start = event.position
				_dragging = true
			elif _dragging:
				_dragging = false
				if event.position.distance_to(_drag_start) > drag_threshold_pixels:
					select_screen_rectangle(Rect2(_drag_start, event.position - _drag_start), {}, event.shift_pressed)
				else:
					var target: Dictionary = pick_entity(event.position,false,true)
					if target.get("kind", "") in ["city","gate"]:select_city(target["id"])
					elif target.get("kind", "") == "army" and event.shift_pressed: toggle_army(target["id"])
					else: select_armies([target["id"]] if target.get("kind", "") == "army" else [])
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed and not event.alt_pressed:
			var target: Dictionary=pick_entity(event.position,true)
			if target.is_empty():
				var point = terrain_point(event.position)
				if point != null:
					target = {"kind": "node", "id": nearest_node(point), "position": point}
			if not target.is_empty():
				var error: String=issue_context_order(target,event.shift_pressed)
				if error.is_empty():context_order_accepted.emit(target.duplicate())
	if event is InputEventKey and event.pressed and not event.echo:
		var key: int = event.physical_keycode if event.physical_keycode!=0 else event.keycode
		if key >= KEY_1 and key <= KEY_9:
			var group: int = key - KEY_1 + 1
			if event.ctrl_pressed: store_control_group(group)
			else: recall_control_group(group,event.shift_pressed)
			return
		match key:
			KEY_SPACE: toggle_pause()
			KEY_H: hold_selected()
			KEY_R: retreat_selected()
			KEY_F: focus_selection()
