extends Node3D
## Pending decorative apron; no collision, passability, units or map vertices added.
const RINGS=[0.0,4.0,12.0,32.0,80.0,160.0,360.0,800.0,1800.0]
const RECT=Rect2(-180,-140,360,280)
var triangle_count: int=0
var interior_vertices: int=0

func configure(height_at: Callable, floor_y: float) -> void:
	var surface:=SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in range(4):
		var count: int=900 if side%2==0 else 700
		for ring in range(RINGS.size()-1):
			for index in range(count):
				var a: Vector3=_point(side,float(index)/count,RINGS[ring],height_at,floor_y)
				var b: Vector3=_point(side,float(index+1)/count,RINGS[ring],height_at,floor_y)
				var c: Vector3=_point(side,float(index)/count,RINGS[ring+1],height_at,floor_y)
				var d: Vector3=_point(side,float(index+1)/count,RINGS[ring+1],height_at,floor_y)
				for vertex in [a,c,b,b,c,d]:surface.set_normal(Vector3.UP);surface.add_vertex(vertex)
				triangle_count+=2
	var material:=ShaderMaterial.new();material.shader=load("res://background/exterior.gdshader")
	material.set_shader_parameter("source_ground",load("res://assets/map-v8/TRB6-TERRAIN-001-albedo-v8.png"))
	var mesh:=MeshInstance3D.new();mesh.name="DecorativeExteriorApron";mesh.mesh=surface.commit();mesh.material_override=material
	mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;add_child(mesh)

func _point(side: int, along: float, expansion: float, height_at: Callable, floor_y: float) -> Vector3:
	var lo: Vector2=RECT.position-Vector2.ONE*expansion;var hi: Vector2=RECT.end+Vector2.ONE*expansion
	var position: Vector2
	match side:
		0:position=Vector2(lerpf(lo.x,hi.x,along),lo.y)
		1:position=Vector2(hi.x,lerpf(lo.y,hi.y,along))
		2:position=Vector2(lerpf(hi.x,lo.x,along),hi.y)
		_:position=Vector2(lo.x,lerpf(hi.y,lo.y,along))
	var edge:=Vector2(clampf(position.x,-180,180),clampf(position.y,-140,140))
	var source_y: float=float(height_at.call(edge.x,edge.y))
	var blend: float=smoothstep(0,160,expansion)
	var y: float=lerpf(source_y-.03,floor_y-4.0,blend)
	if position.x> -180 and position.x<180 and position.y> -140 and position.y<140:interior_vertices+=1
	return Vector3(position.x,y,position.y)
