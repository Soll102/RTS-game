extends RefCounted
## Picking uses the rendered unit first, then its ground/health marker and city body.
static func _field(control: Node3D, id: String, friendly: bool) -> bool:
	var army: Dictionary=control.simulation.armies[id]
	return army.troops>0 and army.get("resident_city","").is_empty() and (not friendly or army.faction==control.player_faction)

static func positions(control: Node3D, friendly: bool=false) -> Dictionary:
	var result: Dictionary={}
	if control.camera==null or not control.camera.is_inside_tree():return result
	for id in control.simulation._sorted_ids(control.simulation.armies):
		if not _field(control,id,friendly):continue
		var local: Vector3=control.display_position.call(id) if control.display_position.is_valid() else control.grounded_position(id)
		var point: Vector3=control.to_global(local)
		if not control.camera.is_position_behind(point):result[id]=control.camera.unproject_position(point)
	return result

static func pick(control: Node3D, screen: Vector2, context: bool=false, friendly: bool=false) -> Dictionary:
	var visual: Callable=control.friendly_visual_pick if friendly else control.entity_visual_pick
	if visual.is_valid():
		var id: String=visual.call(screen)
		if not id.is_empty() and _field(control,id,friendly):return {"kind":"army","id":id}
	if context:
		var gate: Dictionary=control._gate_at(screen)
		if not gate.is_empty():return gate
	var points: Dictionary=positions(control,friendly);var labels: Dictionary=control._screen_positions("army")
	var chosen: String="";var closest: float=1.0
	for id in points:
		var army: Dictionary=control.simulation.armies[id]
		var is_enemy: bool=army.faction!=control.player_faction
		var radius: float=54.0 if is_enemy else 44.0
		var distance: float=screen.distance_squared_to(points[id])/(radius*radius)
		if labels.has(id):
			var l_radius: float=42.0
			distance=minf(distance,screen.distance_squared_to(labels[id])/(l_radius*l_radius))
		if distance<closest:chosen=id;closest=distance
	if not chosen.is_empty():return {"kind":"army","id":chosen}
	var ground=control.terrain_point(screen)
	if ground!=null:
		for id in control.simulation._sorted_ids(control.simulation.cities):
			var gates: Array=control.simulation.gate_nodes(id)
			if gates.is_empty() or not control.node_positions.has(gates[0]):continue
			var anchor: Vector3=control.node_positions[gates[0]]
			var box:=Rect2(Vector2(anchor.x,anchor.z),Vector2.ZERO)
			for gate in gates:
				if not control.node_positions.has(gate):continue
				var p: Vector3=control.node_positions[gate];box=box.expand(Vector2(p.x,p.z))
			if box.grow(4.0).has_point(Vector2(ground.x,ground.z)):return {"kind":"city","id":id}
	var city_points: Dictionary=control._screen_positions("city")
	chosen="";closest=26.0*26.0
	for id in city_points:
		var distance: float=screen.distance_squared_to(city_points[id])
		if distance<closest:chosen=id;closest=distance
	return {"kind":"city","id":chosen} if not chosen.is_empty() else {}
