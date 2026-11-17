extends Node3D
## Exact approved static ferry only; positions follow transport data, no clip.
const DIR = "res://assets/transport-v3/"
var simulation: RefCounted
var boats: Dictionary = {}
var crossings: Array = []
var water_height: float = .30
var packed_boat: PackedScene
var material: Material

func _load_scene(path: String) -> PackedScene:
	return load(path) as PackedScene

func _load_material(path: String) -> Material:
	return load(path) as Material

func configure(sim: RefCounted) -> String:
	if sim == null: return "Ferry view needs a configured campaign."
	var entries = JSON.parse_string(FileAccess.get_file_as_string(DIR+"approved-assets.json"))
	if not entries is Array or entries.size()!=2: return "Ferry exact approval is missing."
	for e in entries:
		if not e is Dictionary or e.get("status")!="approved": return "Ferry asset is not approved."
		if FileAccess.get_sha256(DIR+str(e.integrated_file).get_file())!=e.sha256: return "Approved ferry bytes changed."
	var packed: PackedScene = _load_scene(DIR+"RTS-FERRY-001-v3.glb")
	if packed == null: return "Ferry import is missing. Import the Godot project before playing."
	var candidate_material: Material = _load_material(DIR+"RTS-TRANSPORT-MAT-001-v1.tres")
	if candidate_material == null: return "Approved ferry material could not be loaded."
	if not sim.get("vessels") is Dictionary or sim.vessels.is_empty():return "Ferry view needs physical vessel state."
	var pending: Dictionary={}
	for id in sim._sorted_ids(sim.vessels):
		var instance: Node=packed.instantiate()
		if not instance is Node3D:
			if instance!=null:instance.free()
			_clear_pending(pending);return "Imported ferry root must be Node3D."
		pending[id]=instance
	for old in boats.values():old.queue_free()
	boats=pending;simulation=sim;crossings=sim.world_metadata.crossings;material=candidate_material;packed_boat=packed
	for boat in boats.values():_bind(boat);add_child(boat)
	_process(0)
	return ""

func _clear_pending(pending: Dictionary) -> void:
	for node in pending.values(): node.free()

func _bind(node: Node) -> void:
	if node is MeshInstance3D: node.material_override=material
	for child in node.get_children(): _bind(child)

func _node_position(id: String) -> Vector3:
	var p: Array=simulation.nodes[id].position
	return Vector3(p[0],p[1],p[2])/10

func _process(_delta: float) -> void:
	if simulation==null:return
	var alpha: float=clampf(float(simulation.accumulator_us)/simulation.TICK_US,0,1)
	for id in simulation._sorted_ids(simulation.vessels):
		if not boats.has(id):
			var instance: Node3D=packed_boat.instantiate();_bind(instance);add_child(instance);boats[id]=instance
		var boat: Node3D=boats[id]
		var point: Vector3=simulation.vessel_display_position(id,alpha)/10.0
		var ahead: Vector3=simulation.vessel_display_position(id,minf(1,alpha+.1))/10.0
		boat.position=point;boat.position.y=water_height
		if point.distance_squared_to(ahead)>.000001:
			var heading: float=atan2(ahead.x-point.x,ahead.z-point.z)+PI*.5
			if _delta<=0:boat.rotation.y=heading
			elif not simulation.paused:boat.rotation.y=lerp_angle(boat.rotation.y,heading,1.0-exp(-_delta*10.0))
	for id in boats.keys():
		if not simulation.vessels.has(id):boats[id].queue_free();boats.erase(id)
