class_name TrawlerHullAsset
extends RefCounted

const MODEL := "res://resources/models/vessels/trawler_hull_14m/trawler_hull_14m.glb"
const OUTLINE := "res://resources/models/vessels/trawler_hull_14m/deck_outline.json"


static func instantiate(include_drive: bool = true) -> Node3D:
	var packed := load(MODEL) as PackedScene
	if packed == null: return null
	var hull := packed.instantiate() as Node3D
	if include_drive: hull.add_child(ShipDriveVisual.new())
	return hull


static func make_build_grid() -> DeckGrid:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OUTLINE))
	var grid := DeckGrid.from_hull(float(data["length_m"]), float(data["beam_m"]), float(data["deck_y"]), 0.0, 0.1)
	for point in data["outline_xz"]:
		grid.deck_polygon.append(Vector2(float(point[0]), float(point[1])))
	return grid


static func make_grid_overlay(grid: DeckGrid, layer: int = 0) -> MeshInstance3D:
	var vertices := PackedVector3Array()
	var y := grid.deck_y + float(layer) * grid.cell_m + 0.018
	# Metre reference lines do not determine placement resolution.
	for axis in range(2):
		var limit := 7 if axis == 0 else 2
		for line in range(-limit, limit + 1):
			var hits: Array[float] = []
			for i in range(grid.deck_polygon.size()):
				var a := grid.deck_polygon[i]
				var b := grid.deck_polygon[(i+1)%grid.deck_polygon.size()]
				var av := a.y if axis == 0 else a.x
				var bv := b.y if axis == 0 else b.x
				if (av <= line and bv > line) or (bv <= line and av > line):
					var t := (float(line)-av)/(bv-av)
					hits.append(lerpf(a.x,b.x,t) if axis == 0 else lerpf(a.y,b.y,t))
			hits.sort()
			for i in range(0,hits.size()-1,2):
				for v in [hits[i],hits[i+1]]:
					vertices.append(Vector3(v,y,line) if axis == 0 else Vector3(line,y,v))

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.55, 0.84, 0.87)
	var visual := MeshInstance3D.new()
	visual.name = "DeckGrid1m"
	visual.mesh = mesh
	visual.material_override = mat
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return visual
