extends RefCounted
const T=preload("res://ui_tokens.gd")
static var materials: Dictionary={}

static func apply(record: Dictionary, faction: String) -> void:
	if record.get("team_tint","")==faction:return
	record.team_tint=faction
	var tint: Color=Color(1,1,1).lerp(T.FACTION.get(faction,Color.WHITE),.24)
	for person in record.get("people",[]):
		for mesh in person.find_children("*","MeshInstance3D",true,false):
			var key: String=faction+":"+str(mesh.mesh.get_rid())
			if not materials.has(key):
				var base_mat: Material=mesh.get_active_material(0)
				if base_mat is StandardMaterial3D:
					var m: StandardMaterial3D=base_mat.duplicate()
					m.albedo_color=m.albedo_color*tint
					m.roughness=clampf(m.roughness*.88,.25,.85)
					materials[key]=m
			if materials.has(key):
				mesh.material_override=materials[key]
