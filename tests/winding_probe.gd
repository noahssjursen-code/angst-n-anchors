extends SceneTree

## Dev probe: prints whether Godot's front-face winding matches the right-hand
## rule (normal = cross(b-a, c-a)) by inspecting a built-in BoxMesh surface.

func _initialize() -> void:
	var box := BoxMesh.new()
	var arrays := box.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var a := vertices[indices[0]]
	var b := vertices[indices[1]]
	var c := vertices[indices[2]]
	var stored := normals[indices[0]]
	var right_hand := (b - a).cross(c - a).normalized()
	print("stored normal: ", stored, " right-hand cross: ", right_hand)
	print("CONVENTION: ", "RIGHT_HAND (CCW front)" if stored.dot(right_hand) > 0.0 else "CLOCKWISE front")
	quit(0)
