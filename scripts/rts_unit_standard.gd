extends RefCounted
## Small world-space team standards; no screen-space army card or source texture edit.
const Tokens=preload("res://ui_tokens.gd")
static var _pole_mesh: CylinderMesh
static var _finial_mesh: SphereMesh
static var _backing_mesh: BoxMesh
static var _cloth_mesh: BoxMesh
static var _bronze_mat: StandardMaterial3D
static var _edge_mat: StandardMaterial3D
static var _dye_mats: Dictionary={}

static func _ensure_shared() -> void:
	if _pole_mesh!=null:return
	_pole_mesh=CylinderMesh.new();_pole_mesh.top_radius=.038;_pole_mesh.bottom_radius=.042;_pole_mesh.height=2.85;_pole_mesh.radial_segments=6
	_finial_mesh=SphereMesh.new();_finial_mesh.radius=.09;_finial_mesh.height=.22;_finial_mesh.radial_segments=8;_finial_mesh.rings=4
	_backing_mesh=BoxMesh.new();_backing_mesh.size=Vector3(1.18,.78,.045)
	_cloth_mesh=BoxMesh.new();_cloth_mesh.size=Vector3(1.06,.66,.062)
	_bronze_mat=StandardMaterial3D.new();_bronze_mat.albedo_color=Color("d8b86a");_bronze_mat.metallic=.45;_bronze_mat.roughness=.38
	_edge_mat=StandardMaterial3D.new();_edge_mat.albedo_color=Color("e6c878");_edge_mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	for f in Tokens.FACTION:
		var m:=StandardMaterial3D.new();m.albedo_color=Tokens.FACTION[f];m.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		_dye_mats[f]=m

static func create(faction: String) -> Node3D:
	_ensure_shared()
	var root:=Node3D.new();root.name="SquadStandard";root.position=Vector3(-1.45,0,0)
	var staff:=MeshInstance3D.new();root.add_child(staff)
	staff.mesh=_pole_mesh;staff.position.y=1.425;staff.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	staff.material_override=_bronze_mat
	var finial:=MeshInstance3D.new();root.add_child(finial)
	finial.mesh=_finial_mesh;finial.position=Vector3(0,2.90,0);finial.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	finial.material_override=_edge_mat
	var banner:=MeshInstance3D.new();root.add_child(banner)
	var rim:=MeshInstance3D.new();root.add_child(rim)
	rim.mesh=_backing_mesh;rim.position=Vector3(.58,2.34,0)
	rim.material_override=_edge_mat;rim.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	banner.mesh=_cloth_mesh;banner.position=Vector3(.58,2.34,0)
	banner.material_override=_dye_mats.get(faction,_edge_mat);banner.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var letter:=Label3D.new();letter.text={"wei":"WEI","shu":"SHU","wu":"WU"}.get(faction,faction.to_upper())
	letter.font=Tokens.display_font();letter.font_size=34;letter.pixel_size=.0085
	letter.position=Vector3(.58,2.34,0);letter.modulate=Color("fff8e6");letter.outline_modulate=Color("14100a")
	letter.outline_size=6;letter.double_sided=true;letter.no_depth_test=false;root.add_child(letter)
	var letter_back:=Label3D.new();letter_back.text=letter.text
	letter_back.font=Tokens.display_font();letter_back.font_size=34;letter_back.pixel_size=.0085
	letter_back.position=Vector3(.58,2.34,-.036);letter_back.rotation.y=PI;letter_back.modulate=Color("fff8e6");letter_back.outline_modulate=Color("14100a")
	letter_back.outline_size=6;root.add_child(letter_back)
	letter.position.z=.036
	root.set_meta("faction",faction);return root
