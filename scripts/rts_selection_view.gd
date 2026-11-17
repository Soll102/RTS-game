extends Node3D
## Selected squads receive a terrain-following white rectangle with depth testing.
var simulation: RefCounted
var controller: Node3D
var units: Node3D
var meshes: Dictionary={}
var geometry: Dictionary={}
var material: StandardMaterial3D

func configure(sim: RefCounted, controls: Node3D, view: Node3D) -> void:
	simulation=sim;controller=controls;units=view
	material=StandardMaterial3D.new();material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color=Color.WHITE;material.cull_mode=BaseMaterial3D.CULL_DISABLED
	material.no_depth_test=false

func _half(role: String) -> Vector2:
	if simulation.visible_members()!=4:
		return Vector2(4.4,5.2) if role=="cavalry" else Vector2(3.8,3.2) if role=="siege" else Vector2(3.0,2.0)
	return Vector2(2.0,3.0) if role=="cavalry" else Vector2(2.1,2.3) if role=="siege" else Vector2(1.3,1.5)

func _point(group: Node3D, p: Vector3) -> Vector3:
	var world: Vector3=group.to_global(p)
	world.y=float(controller.ground_sampler.call(world.x,world.z))+.045;return world

func _update(id: String, group: Node3D, half: Vector2, width: float) -> void:
	if geometry.has(id) and geometry[id].half==half and absf(geometry[id].width-width)<.005:
		if geometry[id].transform==group.global_transform:return
		if units.formations.get(id,{}).get("contact_active",false) and geometry[id].transform.origin.distance_squared_to(group.global_position)<.16:return
	var corners: Array=[Vector3(-half.x,0,-half.y),Vector3(half.x,0,-half.y),Vector3(half.x,0,half.y),Vector3(-half.x,0,half.y)]
	var vertices:=PackedVector3Array();var indices:=PackedInt32Array()
	for edge in range(4):
		var a: Vector3=corners[edge];var b: Vector3=corners[(edge+1)%4]
		var delta: Vector3=(b-a).normalized();var side:=Vector3(-delta.z,0,delta.x)*width*.5
		var count: int=ceili(a.distance_to(b)/.5);var first: int=vertices.size()
		for i in range(count+1):
			var p: Vector3=a.lerp(b,float(i)/count)
			vertices.append(_point(group,p-side));vertices.append(_point(group,p+side))
		for i in range(count):
			var p: int=first+i*2;indices.append_array(PackedInt32Array([p,p+1,p+2,p+1,p+3,p+2]))
	if not geometry.has(id) or geometry[id].count!=vertices.size():
		var arrays: Array=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_INDEX]=indices
		var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},Mesh.ARRAY_FLAG_USE_DYNAMIC_UPDATE);meshes[id].mesh=mesh
	else:
		meshes[id].mesh.surface_update_vertex_region(0,0,vertices.to_byte_array())
	var bounds:=AABB(vertices[0],Vector3.ZERO)
	for point in vertices:bounds=bounds.expand(point)
	# Updating a GPU vertex buffer does not rebuild its original culling bounds.
	meshes[id].custom_aabb=bounds.grow(.1)
	geometry[id]={"count":vertices.size(),"transform":group.global_transform,"width":width,"half":half}

func sync() -> void:
	if simulation==null or units==null:return
	var visible: Dictionary={}
	for id in controller.selected_armies:
		if not simulation.armies.has(id) or not units.formations.has(id):continue
		var army: Dictionary=simulation.armies[id];var record: Dictionary=units.formations[id]
		if army.troops<=0 or army.transport_elapsed>0 or not record.root.is_visible_in_tree():continue
		visible[id]=true
		if not meshes.has(id):
			var node=MeshInstance3D.new();node.name="WhiteSelection_"+id;node.material_override=material
			node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;add_child(node);meshes[id]=node
		var half: Vector2=_half(army.unit_type)
		var width: float=clampf(controller.camera.global_position.distance_to(record.root.global_position)*.0016,.055,.18) if controller.camera!=null else .08
		_update(id,record.root,half,width)
	for id in meshes.keys():
		if not visible.has(id):meshes[id].queue_free();meshes.erase(id);geometry.erase(id)

func _process(_delta: float) -> void:sync()
