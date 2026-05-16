@tool
class_name IslandMeshBuilder
extends RefCounted

## Deterministic organic island polygon and mesh from port dimensions + seed.
## Coordinates are in port-plot local XZ space; Y=0 is ground level.
## Water face (Z = -hd) is always a straight edge. Other three sides are noise-displaced.

const MARGIN      : float = 14.0
const AMPLITUDE   : float =  8.0
const DEPTH       : float =  8.0
const SIDE_SEGS   : int   =  6
const INLAND_SEGS : int   =  5


static func build_polygon(island_width: float, plot_depth: float, seed: int) -> PackedVector2Array:
	var hw  : float = island_width * 0.5
	var hd  : float = plot_depth   * 0.5
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var pts := PackedVector2Array()

	# Water face: two fixed corners, no noise
	pts.append(Vector2(-hw, -hd))
	pts.append(Vector2( hw, -hd))

	# Right flank
	for i in range(1, SIDE_SEGS):
		var t      : float = float(i) / float(SIDE_SEGS)
		var offset : float = MARGIN + rng.randf_range(-AMPLITUDE, AMPLITUDE)
		var x      : float = hw + offset
		var z      : float = lerp(-hd, hd, t)
		pts.append(Vector2(x, z))

	# Inland face
	for i in range(INLAND_SEGS + 1):
		var t      : float = float(i) / float(INLAND_SEGS)
		var offset : float = MARGIN + rng.randf_range(-AMPLITUDE, AMPLITUDE)
		var x      : float = lerp(hw, -hw, t)
		var z      : float = hd + offset
		pts.append(Vector2(x, z))

	# Left flank
	for i in range(1, SIDE_SEGS):
		var t      : float = float(i) / float(SIDE_SEGS)
		var offset : float = MARGIN + rng.randf_range(-AMPLITUDE, AMPLITUDE)
		var x      : float = 0.0 - hw - offset
		var z      : float = lerp(hd, -hd, t)
		pts.append(Vector2(x, z))

	return pts


static func to_mesh(polygon: PackedVector2Array) -> ArrayMesh:
	var tris := Geometry2D.triangulate_polygon(polygon)
	if tris.is_empty():
		return ArrayMesh.new()

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var n : int = polygon.size()
	var bottom : float = 0.0 - DEPTH

	# Top face: expand triangle indices into explicit vertices
	var tri_count : int = tris.size() / 3
	for i in range(tri_count):
		var base : int = i * 3
		for j in range(3):
			var p := polygon[tris[base + j]]
			st.add_vertex(Vector3(p.x, 0.0, p.y))

	# Side walls: two triangles per edge
	for i in range(n):
		var a := polygon[i]
		var b := polygon[(i + 1) % n]
		st.add_vertex(Vector3(a.x, 0.0,    a.y))
		st.add_vertex(Vector3(b.x, 0.0,    b.y))
		st.add_vertex(Vector3(a.x, bottom, a.y))
		st.add_vertex(Vector3(b.x, 0.0,    b.y))
		st.add_vertex(Vector3(b.x, bottom, b.y))
		st.add_vertex(Vector3(a.x, bottom, a.y))

	return st.commit()


static func to_collision_shape(polygon: PackedVector2Array) -> ConcavePolygonShape3D:
	var tris := Geometry2D.triangulate_polygon(polygon)
	var faces := PackedVector3Array()
	var tri_count : int = tris.size() / 3
	for i in range(tri_count):
		var base : int = i * 3
		for j in range(3):
			var p := polygon[tris[base + j]]
			faces.append(Vector3(p.x, 0.0, p.y))
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	return shape
