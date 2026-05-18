## Single convention for headings, bearings, and chart north-up.
## World axes: Godot horizontal plane X/Z, Y up. Chart maps +X east (right),
## smaller screen Y toward smaller world Z — so **north = world −Z**.

extends RefCounted
class_name NavigationAxes


## Heading / bearing clockwise from north in radians (−TAU/2 .. TAU/2).
static func heading_rad_horizontal(bow_horizontal: Vector2) -> float:
	var bh := bow_horizontal
	if bh.length_squared() < 1e-10:
		return 0.0
	bh = bh.normalized()
	return atan2(bh.x, -bh.y)


static func heading_deg_horizontal(bow_horizontal: Vector2) -> float:
	return fposmod(rad_to_deg(heading_rad_horizontal(bow_horizontal)), 360.0)


static func compass_card_rotation_rad(heading_rad: float) -> float:
	return -heading_rad


## Horizontal bow from a vessel node (meshes authored with bow at local +Z).
static func vessel_bow_horizontal(node: Node3D) -> Vector2:
	var b := node.global_transform.basis
	return Vector2(b.z.x, b.z.z)


## Bearing from world-space delta.xyz on the XZ plane, clockwise from north.
static func bearing_rad_world_delta(delta: Vector3) -> float:
	return atan2(delta.x, -delta.z)
