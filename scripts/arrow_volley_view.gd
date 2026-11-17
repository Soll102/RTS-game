extends Node3D
## Authored arrow geometry/UV selection and ballistic display using exact ROTK XIV atlas pixels.
## Pending simulation shots are authoritative. This adapter never applies damage or collision.
const TEXTURE_PATH = "res://combat-effects/9b80b8a3.png"
const MAX_ARROWS = 192
const ARROWS_PER_VOLLEY = 12
const IMPACT_FADE_SECONDS = 0.2
var simulation: RefCounted
var controller: Node3D
var active: bool = false
var records: Dictionary = {}
var _mesh_node: MultiMeshInstance3D
var _multimesh: MultiMesh
var _last_tick: int = -1
var _drawn: int = 0
var _configured: bool = false
var _controller_revision: int=-1

func configure(sim: RefCounted, controls: Node3D) -> String:
	if sim == null or controls == null or not controls.ground_sampler.is_valid():
		return "Arrow volleys require simulation shots and actual terrain grounding."
	if not FileAccess.file_exists(TEXTURE_PATH):return "Missing exact original arrow atlas."
	simulation = sim
	controller = controls
	var shader := Shader.new()
	shader.code = """shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform sampler2D source_texture : source_color, filter_linear_mipmap, repeat_disable;
varying float arrow_fade;
varying vec3 arrow_tint;
void vertex() { arrow_fade = INSTANCE_CUSTOM.a; arrow_tint=INSTANCE_CUSTOM.rgb; }
void fragment() {
	vec4 pixel = texture(source_texture, UV);
	ALBEDO = pixel.rgb * arrow_tint;
	ALPHA = pixel.a * arrow_fade;
}"""
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("source_texture",load(TEXTURE_PATH))
	var arrow: ArrayMesh = _arrow_mesh()
	arrow.surface_set_material(0,material)
	_multimesh = MultiMesh.new()
	_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_multimesh.use_custom_data = true
	_multimesh.mesh = arrow
	_multimesh.instance_count = MAX_ARROWS
	_multimesh.visible_instance_count = 0
	_mesh_node = MultiMeshInstance3D.new()
	_mesh_node.name = "AuthoredOriginalAtlasArrowVolley"
	_mesh_node.multimesh = _multimesh
	_mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh_node)
	_configured = true
	reset()
	return ""

func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, uv_a: Vector2, uv_b: Vector2, uv_c: Vector2) -> void:
	surface.set_uv(uv_a);surface.add_vertex(a)
	surface.set_uv(uv_b);surface.add_vertex(b)
	surface.set_uv(uv_c);surface.add_vertex(c)

func _face(surface: SurfaceTool, a: Vector3,b: Vector3,c: Vector3,d: Vector3, uv: Rect2) -> void:
	_triangle(surface,a,b,c,uv.position,uv.position+Vector2(uv.size.x,0),uv.end)
	_triangle(surface,a,c,d,uv.position,uv.end,uv.position+Vector2(0,uv.size.y))

func _arrow_mesh() -> ArrayMesh:
	# These are deliberately authored display dimensions, not recovered source geometry.
	var s := SurfaceTool.new()
	s.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w: float = 0.012
	var tail: float = -0.42
	var front: float = 0.31
	var wood := Rect2(0.19,0.025,0.71,0.16)
	_face(s,Vector3(-w,-w,tail),Vector3(w,-w,tail),Vector3(w,-w,front),Vector3(-w,-w,front),wood)
	_face(s,Vector3(-w,w,front),Vector3(w,w,front),Vector3(w,w,tail),Vector3(-w,w,tail),wood)
	_face(s,Vector3(-w,-w,front),Vector3(-w,w,front),Vector3(-w,w,tail),Vector3(-w,-w,tail),wood)
	_face(s,Vector3(w,-w,tail),Vector3(w,w,tail),Vector3(w,w,front),Vector3(w,-w,front),wood)
	var tip := Vector3(0,0,0.46)
	var silver := Rect2(0.01,0.28,0.14,0.60)
	var corners: Array = [Vector3(-.035,-.02,.29),Vector3(.035,-.02,.29),Vector3(.035,.02,.29),Vector3(-.035,.02,.29)]
	for i in range(4):
		_triangle(s,corners[i],corners[(i+1)%4],tip,silver.position,silver.end,silver.position+Vector2(.07,.30))
	var feather := Rect2(.22,.33,.64,.48)
	_face(s,Vector3(-.045,0,-.41),Vector3(.045,0,-.41),Vector3(.022,0,-.19),Vector3(-.022,0,-.19),feather)
	_face(s,Vector3(0,-.045,-.41),Vector3(0,.045,-.41),Vector3(0,.022,-.19),Vector3(0,-.022,-.19),feather)
	s.generate_normals()
	return s.commit()

func reset() -> void:
	records.clear()
	_drawn=0
	_last_tick=-1
	if _multimesh!=null:_multimesh.visible_instance_count=0

func _clock() -> float:
	return (float(simulation.tick)+clampf(float(simulation.accumulator_us)/float(simulation.TICK_US),0.0,1.0))*.1

func _ground(point: Array, lift: float) -> Vector3:
	var x: float=float(point[0])/10.0
	var z: float=float(point[1])/10.0
	return Vector3(x,float(controller.ground_sampler.call(x,z))+lift,z)

func _create(shot: Dictionary) -> void:
	var start: Vector3=_ground(shot.origin,4.2 if shot.kind=="city" else 1.8)
	if shot.kind=="army" and simulation.armies.has(shot.source) and simulation.armies[shot.source].resident_city.is_empty() and controller.display_position.is_valid():start=controller.display_position.call(shot.source)+Vector3.UP*1.5
	var goal: Vector3=_ground(shot.goal,.12)
	var across: Vector3=(goal-start).cross(Vector3.UP).normalized()
	if across.is_zero_approx():across=Vector3.RIGHT
	var forward: Vector3=Vector3(across.z,0,-across.x)
	var phase_seed: int=abs(str(shot.id).hash())%97
	var arrows: Array=[]
	for index in range(ARROWS_PER_VOLLEY):
		var members: int=4 if simulation.traditional_rts or shot.kind=="city" else 8
		var columns: int=4 if shot.kind=="city" or members==8 else 2
		var person: int=index%members
		var source_side: float=(float(person%columns)-float(columns-1)*.5)*(0.7 if shot.kind=="city" else 1.2)
		var source_row: float=(float(int(person/columns))-.5)*.75
		var a: Vector3=start+across*source_side+forward*source_row
		a.y=float(controller.ground_sampler.call(a.x,a.z))+(4.2 if shot.kind=="city" else 1.8)
		var spread: float=(float((index*37+phase_seed)%24)-11.5)*.12
		var b: Vector3=goal+across*spread+forward*(float(index%3)-1.0)*.38
		b.y=float(controller.ground_sampler.call(b.x,b.z))+.12
		arrows.append({"start":a,"goal":b,"delay":float(int(index/members))*.03,"height":(4.6 if shot.kind=="city" else 3.6)+float(index%5)*.12})
	records[shot.id]={"shot":shot.duplicate(true),"start":start,"goal":goal,"release":float(shot.release_time_us)/1000000.0,"impact":float(shot.impact_tick)*.1,"arrows":arrows}

func sync() -> void:
	if not _configured or simulation==null:return
	if _controller_revision!=controller.presentation_revision:
		reset();_controller_revision=controller.presentation_revision
	if not active:
		reset()
		return
	if _last_tick>simulation.tick:reset()
	_last_tick=simulation.tick
	var clock: float=_clock()
	var pending = simulation.get("pending_volleys")
	if not pending is Array:return
	var shots: Array=pending.duplicate()
	# A load at the same/later tick can reuse packet IDs with different geometry.
	# Existing records must describe the exact current simulation packet.
	for shot in shots:
		if records.has(shot.id) and records[shot.id].shot!=shot:records.erase(shot.id)
	shots.sort_custom(func(a,b):return a.kind=="city" if a.kind!=b.kind else a.release_tick<b.release_tick if a.release_tick!=b.release_tick else str(a.id)<str(b.id))
	for id in records.keys():
		if clock>=float(records[id].impact)+IMPACT_FADE_SECONDS:records.erase(id)
	# Reserve visible budget for defensive volleys first; damage stays in simulation.
	for shot in shots:
		if records.has(shot.id) or records.size()>=MAX_ARROWS/ARROWS_PER_VOLLEY:continue
		if shot.get("origin") is Array and shot.get("goal") is Array and float(shot.impact_tick)*.1+IMPACT_FADE_SECONDS>clock:_create(shot)
	_drawn=0
	for id in records:
		var r: Dictionary=records[id]
		for index in range(ARROWS_PER_VOLLEY):
			if _drawn>=MAX_ARROWS:break
			var arrow: Dictionary=r.arrows[index]
			var delay: float=arrow.delay
			var release: float=r.release+delay
			if clock<release:continue
			var duration: float=maxf(.1,r.impact-release)
			var u: float=clampf((clock-release)/duration,0.0,1.0)
			var start: Vector3=arrow.start
			var goal: Vector3=arrow.goal
			var arc_height: float=arrow.height
			var position: Vector3=start.lerp(goal,u)+Vector3.UP*(arc_height*4.0*u*(1.0-u))
			var velocity: Vector3=goal-start+Vector3.UP*(arc_height*4.0*(1.0-2.0*u))
			if velocity.is_zero_approx():velocity=Vector3.DOWN
			var up: Vector3=Vector3.FORWARD if absf(velocity.normalized().dot(Vector3.UP))>.98 else Vector3.UP
			var basis: Basis=Basis.looking_at(velocity.normalized(),up,true)
			if r.shot.kind=="city":basis=basis.scaled(Vector3(1.7,1.7,1.35))
			_multimesh.set_instance_transform(_drawn,Transform3D(basis,position))
			var fade: float=clampf(1.0-(clock-r.impact)/IMPACT_FADE_SECONDS,0.0,1.0) if clock>=r.impact else 1.0
			_multimesh.set_instance_custom_data(_drawn,Color(1.7,1.35,.8,fade) if r.shot.kind=="city" else Color(1,1,1,fade))
			_drawn+=1
	_multimesh.visible_instance_count=_drawn

func _process(_delta: float) -> void:sync()

func diagnostics() -> Dictionary:
	var transforms: Array=[]
	if _multimesh!=null:
		for i in range(mini(_drawn,3)):
			var p: Vector3=_multimesh.get_instance_transform(i).origin
			transforms.append([p.x,p.y,p.z])
	return {"active":active,"volleys":records.size(),"winding_up":simulation.pending_windups.size() if simulation!=null else 0,"visible_arrows":_drawn,"budget":MAX_ARROWS,"sample_positions":transforms,"clock":_clock() if simulation!=null else 0.0,"mesh_triangles":16,"geometry_origin":"authored derivative using original texture","damage_from_visual":false}
