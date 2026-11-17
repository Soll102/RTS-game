extends RefCounted
## One shared height grid, fixed chunk seams, optional stride for inexpensive terrain.

static func create(heights: PackedFloat32Array, stride: int) -> Node3D:
	var root := Node3D.new()
	root.name = "TerrainChunks"
	for cz in range(7):
		for cx in range(9):
			var vertices := PackedVector3Array()
			var normals := PackedVector3Array()
			var uvs := PackedVector2Array()
			var tangents := PackedFloat32Array()
			var indices := PackedInt32Array()
			var xs: Array[int] = []
			var zs: Array[int] = []
			for x in range(cx * 100, (cx + 1) * 100 + 1, stride): xs.append(x)
			for z in range(cz * 100, (cz + 1) * 100 + 1, stride): zs.append(z)
			for z in zs:
				for x in xs:
					var h: float = heights[z * 901 + x]
					vertices.append(Vector3(-180 + x * 0.4, h, -140 + z * 0.4))
					var dx: float = (heights[z * 901 + mini(x+1,900)] - heights[z * 901 + maxi(x-1,0)]) / (0.4 * (mini(x+1,900)-maxi(x-1,0)))
					var dz: float = (heights[mini(z+1,700) * 901 + x] - heights[maxi(z-1,0) * 901 + x]) / (0.4 * (mini(z+1,700)-maxi(z-1,0)))
					normals.append(Vector3(-dx, 1, -dz).normalized())
					var tangent := Vector3(1,dx,0).normalized()
					tangents.append_array(PackedFloat32Array([tangent.x,tangent.y,tangent.z,-1]))
					uvs.append(Vector2(x / 900.0, z / 700.0))
			for z in range(zs.size()-1):
				for x in range(xs.size()-1):
					var a: int = z * xs.size() + x
					var c: int = a + xs.size()
					# Godot ArrayMesh uses clockwise fronts; glTF import reverses winding.
					indices.append_array(PackedInt32Array([a,a+1,c,a+1,c+1,c]))
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = vertices
			arrays[Mesh.ARRAY_NORMAL] = normals
			arrays[Mesh.ARRAY_TANGENT] = tangents
			arrays[Mesh.ARRAY_TEX_UV] = uvs
			arrays[Mesh.ARRAY_INDEX] = indices
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			var instance := MeshInstance3D.new()
			instance.mesh = mesh
			instance.name = "Terrain_%d_%d" % [cx,cz]
			root.add_child(instance)
	return root
