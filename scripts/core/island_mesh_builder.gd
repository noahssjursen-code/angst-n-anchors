@tool
class_name IslandMeshBuilder
extends RefCounted

## Deterministic organic island polygon + heightmapped terrain mesh.
##
## Two phases:
##   1. `build_polygon(...)`  — silhouette in port-plot local XZ space. Water face
##      (Z = -plot_depth/2) is a straight edge; the other three sides are noise-
##      displaced for an organic outline. Unchanged from the flat version, so
##      LandField and the map overlay continue to consume the same shape.
##   2. `to_mesh(polygon, pad_w, pad_d, seed)` — tessellates the polygon interior
##      with a regular XZ grid (Delaunay triangulation), then lifts each vertex
##      by a noise heightmap. Inside the rectangular **port pad** (plot_w × plot_d
##      centred at origin) heights are forced to 0 so docks, facilities, and NPCs
##      drop in on a flat surface. A smooth ring blends the pad edge into the
##      noise terrain, and a shore falloff sinks heights back to 0 at the polygon
##      perimeter so coast meets water cleanly.
##
## Collision (`to_collision_shape`) reuses the same vertex/triangle data so the
## player walks on the visible terrain.

# ── Silhouette knobs ────────────────────────────────────────────────────────
const MARGIN      : float = 45.0   # avg land extension beyond port rectangle on 3 sides
const AMPLITUDE   : float = 15.0   # noise variation around MARGIN
const DEPTH       : float =  8.0   # extrusion thickness below Y=0
const SIDE_SEGS   : int   =  8
const INLAND_SEGS : int   =  7

# ── Terrain knobs ───────────────────────────────────────────────────────────
const GRID_STEP_M        : float = 4.0    # interior grid spacing
const TERRAIN_PEAK_M     : float = 18.0   # max elevation above the pad
const TERRAIN_NOISE_FREQ : float = 0.025
const TERRAIN_NOISE_OCT  : int   = 3
const PAD_BLEND_M        : float = 10.0   # smooth ring around the port pad
const SHORE_FALLOFF_M    : float = 16.0   # beach-like falloff at the polygon edge

# ── Vertex colour ramp (sand → grass → rock) ────────────────────────────────
const C_SAND  : Color = Color(0.62, 0.54, 0.36)
const C_GRASS : Color = Color(0.10, 0.22, 0.08)
const C_ROCK  : Color = Color(0.24, 0.22, 0.18)
const C_PAD   : Color = Color(0.18, 0.22, 0.14)


static func build_polygon(island_width: float, plot_depth: float, seed: int) -> PackedVector2Array:
	var hw : float = island_width * 0.5
	var hd : float = plot_depth   * 0.5
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


## Build a heightmapped terrain mesh from the polygon. Inside the port pad
## rectangle heights are 0 (flat); outside, a deterministic noise field rises up
## to TERRAIN_PEAK_M with a smooth pad-edge blend and a shore falloff.
static func to_mesh(polygon: PackedVector2Array, pad_width: float, pad_depth: float, seed: int) -> ArrayMesh:
	var data := _build_terrain(polygon, pad_width, pad_depth, seed)
	var verts : PackedVector3Array = data["vertices"]
	var tris  : PackedInt32Array   = data["indices"]
	if verts.is_empty() or tris.is_empty():
		return ArrayMesh.new()

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Top surface — terrain, with vertex colour by elevation.
	# Geometry2D.triangulate_delaunay's docs promise CCW output but in
	# practice the winding is mixed across the returned triangle list.
	# Godot uses CW winding for front-facing triangles (`SurfaceTool`'s
	# `generate_normals` produces +Y normals for CW-wound triangles, not
	# CCW), so we force every emitted triangle to be CW-from-above.
	#
	# The 2D XZ cross product `(v1-v0) × (v2-v0)` Y-component is positive
	# for *standard* CCW winding — which is Godot CW from below, i.e. the
	# wrong direction. So we swap when the value is positive.
	var tri_count : int = tris.size() / 3
	for i in range(tri_count):
		var base : int = i * 3
		var v0 := verts[tris[base + 0]]
		var v1 := verts[tris[base + 1]]
		var v2 := verts[tris[base + 2]]
		var cross_y : float = (v1.z - v0.z) * (v2.x - v0.x) - (v1.x - v0.x) * (v2.z - v0.z)
		if cross_y > 0.0:
			var tmp := v1
			v1 = v2
			v2 = tmp
		st.set_color(_colour_for_height(v0.y, pad_width, pad_depth, v0))
		st.add_vertex(v0)
		st.set_color(_colour_for_height(v1.y, pad_width, pad_depth, v1))
		st.add_vertex(v1)
		st.set_color(_colour_for_height(v2.y, pad_width, pad_depth, v2))
		st.add_vertex(v2)

	# Side walls — extrude polygon down from Y=0 (where the terrain meets the shore).
	var bottom : float = 0.0 - DEPTH
	var n : int = polygon.size()
	for i in range(n):
		var a := polygon[i]
		var b := polygon[(i + 1) % n]
		# Wall is dark rock so it doesn't fight the grass top visually.
		st.set_color(C_ROCK * 0.6)
		st.add_vertex(Vector3(a.x, 0.0,    a.y))
		st.add_vertex(Vector3(a.x, bottom, a.y))
		st.add_vertex(Vector3(b.x, 0.0,    b.y))
		st.add_vertex(Vector3(b.x, 0.0,    b.y))
		st.add_vertex(Vector3(a.x, bottom, a.y))
		st.add_vertex(Vector3(b.x, bottom, b.y))

	st.generate_normals()
	return st.commit()


## Collision shape that matches the visible terrain top. Side walls are omitted —
## the player walks on the top surface; falling off the edge drops into the ocean.
static func to_collision_shape(polygon: PackedVector2Array, pad_width: float, pad_depth: float, seed: int) -> ConcavePolygonShape3D:
	var data := _build_terrain(polygon, pad_width, pad_depth, seed)
	var verts : PackedVector3Array = data["vertices"]
	var tris  : PackedInt32Array   = data["indices"]
	var faces := PackedVector3Array()
	# Same per-triangle winding correction as to_mesh — Godot/Jolt use CW
	# winding for face normals, so we swap whenever the standard cross
	# product Y component is positive (= standard CCW = Godot's "wrong way").
	var tri_count : int = tris.size() / 3
	for i in range(tri_count):
		var base : int = i * 3
		var v0 := verts[tris[base + 0]]
		var v1 := verts[tris[base + 1]]
		var v2 := verts[tris[base + 2]]
		var cross_y : float = (v1.z - v0.z) * (v2.x - v0.x) - (v1.x - v0.x) * (v2.z - v0.z)
		if cross_y > 0.0:
			var tmp := v1
			v1 = v2
			v2 = tmp
		faces.append(v0)
		faces.append(v1)
		faces.append(v2)
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	return shape


# ── Internal terrain construction ───────────────────────────────────────────

static func _build_terrain(polygon: PackedVector2Array, pad_width: float, pad_depth: float, seed: int) -> Dictionary:
	if polygon.is_empty():
		return {"vertices": PackedVector3Array(), "indices": PackedInt32Array()}

	# 1. Bounding box of the polygon.
	var aabb_min := Vector2( INF,  INF)
	var aabb_max := Vector2(-INF, -INF)
	for p in polygon:
		aabb_min.x = minf(aabb_min.x, p.x)
		aabb_min.y = minf(aabb_min.y, p.y)
		aabb_max.x = maxf(aabb_max.x, p.x)
		aabb_max.y = maxf(aabb_max.y, p.y)

	# 2. All Delaunay input points: polygon boundary + interior grid.
	var pts := PackedVector2Array()
	for p in polygon:
		pts.append(p)

	# Skip interior grid points within EDGE_AVOID of the polygon boundary so
	# we don't end up with skinny near-duplicate triangles right next to a
	# boundary vertex.
	var EDGE_AVOID : float = GRID_STEP_M * 0.5
	var x : float = aabb_min.x + GRID_STEP_M * 0.5
	while x < aabb_max.x:
		var z : float = aabb_min.y + GRID_STEP_M * 0.5
		while z < aabb_max.y:
			var q := Vector2(x, z)
			if Geometry2D.is_point_in_polygon(q, polygon) and _dist_to_polygon_edge(q, polygon) > EDGE_AVOID:
				pts.append(q)
			z += GRID_STEP_M
		x += GRID_STEP_M

	# 3. Delaunay triangulate the full point set.
	var tri_indices := Geometry2D.triangulate_delaunay(pts)
	if tri_indices.is_empty():
		return {"vertices": PackedVector3Array(), "indices": PackedInt32Array()}

	# 4. Cull triangles whose centroid lies outside the polygon (Delaunay
	#    covers the convex hull, not the concave outline).
	var kept_indices := PackedInt32Array()
	var tri_count : int = tri_indices.size() / 3
	for i in range(tri_count):
		var i0 := tri_indices[i * 3 + 0]
		var i1 := tri_indices[i * 3 + 1]
		var i2 := tri_indices[i * 3 + 2]
		var centroid := (pts[i0] + pts[i1] + pts[i2]) / 3.0
		if not Geometry2D.is_point_in_polygon(centroid, polygon):
			continue
		kept_indices.append(i0)
		kept_indices.append(i1)
		kept_indices.append(i2)

	# 5. Lift each XZ vertex to Y via the height function.
	var noise := FastNoiseLite.new()
	noise.seed             = seed
	noise.noise_type       = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency        = TERRAIN_NOISE_FREQ
	noise.fractal_octaves  = TERRAIN_NOISE_OCT

	var verts := PackedVector3Array()
	verts.resize(pts.size())
	for i in range(pts.size()):
		var p := pts[i]
		var h := _height_at(p, polygon, pad_width, pad_depth, noise)
		verts[i] = Vector3(p.x, h, p.y)

	return {"vertices": verts, "indices": kept_indices}


static func _height_at(p: Vector2, polygon: PackedVector2Array, pad_w: float, pad_d: float, noise: FastNoiseLite) -> float:
	# Inside the rectangular pad → exactly flat.
	var pad_hw : float = pad_w * 0.5
	var pad_hd : float = pad_d * 0.5
	if absf(p.x) <= pad_hw and absf(p.y) <= pad_hd:
		return 0.0

	# Smooth blend from pad edge outward.
	var dx       : float = maxf(0.0, absf(p.x) - pad_hw)
	var dz       : float = maxf(0.0, absf(p.y) - pad_hd)
	var dist_pad : float = sqrt(dx * dx + dz * dz)
	var pad_t    : float = smoothstep(0.0, PAD_BLEND_M, dist_pad)

	# Beach-like falloff at the polygon perimeter.
	var dist_shore : float = _dist_to_polygon_edge(p, polygon)
	var shore_t    : float = smoothstep(0.0, SHORE_FALLOFF_M, dist_shore)

	# Noise sample in 0..1 (FastNoiseLite outputs -1..1).
	var n : float = noise.get_noise_2d(p.x, p.y) * 0.5 + 0.5
	return n * TERRAIN_PEAK_M * pad_t * shore_t


static func _dist_to_polygon_edge(p: Vector2, polygon: PackedVector2Array) -> float:
	var best : float = INF
	var n    : int   = polygon.size()
	for i in range(n):
		var a := polygon[i]
		var b := polygon[(i + 1) % n]
		var d := _dist_point_segment(p, a, b)
		if d < best:
			best = d
	return best


static func _dist_point_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var ab_len2 : float = ab.length_squared()
	if ab_len2 < 1e-6:
		return p.distance_to(a)
	var t : float = clampf((p - a).dot(ab) / ab_len2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


static func _colour_for_height(_h: float, pad_w: float, pad_d: float, v: Vector3) -> Color:
	var pad_hw : float = pad_w * 0.5
	var pad_hd : float = pad_d * 0.5
	if absf(v.x) <= pad_hw and absf(v.z) <= pad_hd:
		return C_PAD
	var t : float = clampf(v.y / TERRAIN_PEAK_M, 0.0, 1.0)
	if t < 0.18:
		return C_SAND.lerp(C_GRASS, smoothstep(0.0, 0.18, t))
	return C_GRASS.lerp(C_ROCK, smoothstep(0.18, 1.0, t))
