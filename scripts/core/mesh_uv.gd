class_name MeshUv
extends RefCounted

## Reusable UV helpers for the in-house JSON authoring pipeline. Purpose-built
## garments may still unwrap seams manually; props and future face/head meshes
## can use these deterministic projections instead of ad-hoc UV code.


static func valid_for(vertices: Array, uvs: Array) -> bool:
	return vertices.size() % 3 == 0 and uvs.size() == (vertices.size() / 3) * 2


static func planar(
		vertices: Array,
		u_axis: Vector3 = Vector3.RIGHT,
		v_axis: Vector3 = Vector3.UP,
		scale: Vector2 = Vector2.ONE,
		offset: Vector2 = Vector2.ZERO,
) -> Array:
	var result: Array = []
	for i in range(0, vertices.size(), 3):
		var point := Vector3(float(vertices[i]), float(vertices[i + 1]), float(vertices[i + 2]))
		result.append(point.dot(u_axis) * scale.x + offset.x)
		result.append(point.dot(v_axis) * scale.y + offset.y)
	return result


static func cylindrical_y(vertices: Array, center: Vector3 = Vector3.ZERO) -> Array:
	var min_y := INF
	var max_y := -INF
	for i in range(1, vertices.size(), 3):
		min_y = minf(min_y, float(vertices[i]))
		max_y = maxf(max_y, float(vertices[i]))
	var height := maxf(max_y - min_y, 0.000001)
	var result: Array = []
	for i in range(0, vertices.size(), 3):
		var point := Vector3(float(vertices[i]), float(vertices[i + 1]), float(vertices[i + 2])) - center
		result.append(fposmod(atan2(point.z, point.x) / TAU + 0.5, 1.0))
		result.append((point.y + center.y - min_y) / height)
	return result
