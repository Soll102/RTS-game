extends RefCounted
## Samples the exact Low triangle mesh; no generated visual or asset changes.
static func height_at(heights: PackedFloat32Array, x: float, z: float, stride: int=4, layout: Dictionary={}) -> float:
	var width: int=layout.get("grid_width",901);var depth: int=layout.get("grid_depth",701)
	var units: float=layout.get("units_per_metre",10);var cell: float=float(layout.get("cell_units",4))/units
	var minimum: Array=layout.get("minimum",[-1800,-1400])
	var gx := clampf((x-float(minimum[0])/units)/cell,0,width-1)
	var gz := clampf((z-float(minimum[1])/units)/cell,0,depth-1)
	var ix := mini(floori(gx/stride)*stride,width-1-stride)
	var iz := mini(floori(gz/stride)*stride,depth-1-stride)
	var tx := (gx-ix)/stride
	var tz := (gz-iz)/stride
	var a: float = heights[iz*width+ix]
	var b: float = heights[iz*width+ix+stride]
	var c: float = heights[(iz+stride)*width+ix]
	var d: float = heights[(iz+stride)*width+ix+stride]
	return a+(b-a)*tx+(c-a)*tz if tx+tz<=1 else d+(c-d)*(1-tx)+(b-d)*(1-tz)

static func pick_ground(camera: Camera3D, heights: PackedFloat32Array, screen: Vector2, stride: int=4, layout: Dictionary={}):
	var origin := camera.project_ray_origin(screen)
	var direction := camera.project_ray_normal(screen)
	if direction.y >= 0: return null
	var previous: float = 0
	var units: float=layout.get("units_per_metre",10);var minimum: Array=layout.get("minimum",[-1800,-1400]);var size: Array=layout.get("size",[3600,2800])
	var bounds:=Rect2(Vector2(minimum[0],minimum[1])/units,Vector2(size[0],size[1])/units)
	for index in range(1,1601 if not layout.is_empty() else 601):
		var t: float = index*2.0
		var p := origin+direction*t
		if not bounds.has_point(Vector2(p.x,p.z)): previous=t; continue
		if p.y <= height_at(heights,p.x,p.z,stride,layout):
			var lower := previous
			var upper := t
			for _refine in range(12):
				var mid := (lower+upper)*.5
				var q := origin+direction*mid
				if q.y>height_at(heights,q.x,q.z,stride,layout): lower=mid
				else: upper=mid
			var hit := origin+direction*upper
			hit.y=height_at(heights,hit.x,hit.z,stride,layout)
			return hit
		previous=t
	return null
