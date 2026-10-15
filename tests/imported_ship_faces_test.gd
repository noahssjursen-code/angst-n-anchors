extends Node

func _ready() -> void:
	var assembler:=ImportedShipPartsEditor.new()
	var vertices:=PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.FORWARD])
	for indexed in [false,true]:
		var arrays:=[]
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX]=vertices
		if indexed:arrays[Mesh.ARRAY_INDEX]=PackedInt32Array([0,1,2])
		var resource:=ArrayMesh.new()
		resource.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		var mesh:=MeshInstance3D.new()
		mesh.mesh=resource
		assert(assembler._deformed_faces(mesh)==vertices,"Indexed and unindexed triangles remain walkable")
		mesh.free()
		var shaped:=ArrayMesh.new()
		shaped.blend_shape_mode=Mesh.BLEND_SHAPE_MODE_RELATIVE
		shaped.add_blend_shape("Raise")
		var shape:=[]
		shape.resize(Mesh.ARRAY_MAX)
		shape[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3.UP,Vector3.UP,Vector3.UP])
		shaped.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[shape])
		mesh=MeshInstance3D.new()
		mesh.mesh=shaped
		mesh.set_blend_shape_value(0,.5)
		var faces:=assembler._deformed_faces(mesh)
		assert(faces.size()==3 and faces[0].is_equal_approx(Vector3.UP*.5),"Unindexed blend-shaped meshes preserve deformation")
		mesh.set_blend_shape_value(0,.25)
		assert(assembler._deformed_faces(mesh)[0].is_equal_approx(Vector3.UP*.25),"Changed blend weights cannot reuse stale faces")
		mesh.free()
	var line_arrays:=[]
	line_arrays.resize(Mesh.ARRAY_MAX)
	line_arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3.ZERO,Vector3.ONE,Vector3.RIGHT,Vector3.UP,Vector3.FORWARD,Vector3.BACK])
	var lines:=ArrayMesh.new()
	lines.add_surface_from_arrays(Mesh.PRIMITIVE_LINES,line_arrays)
	var wire:=MeshInstance3D.new()
	wire.mesh=lines
	assert(assembler._deformed_faces(wire).is_empty(),"Visual wires do not create invented walkable triangles")
	wire.free()
	var primitive:=MeshInstance3D.new()
	primitive.mesh=BoxMesh.new()
	assert(assembler._deformed_faces(primitive).size()==36,"Primitive mesh collision remains intact")
	primitive.free()
	assembler.free()
	print("IMPORTED SHIP FACES PASS indexed/unindexed, blend deformation and cache, visual wires, primitive collision")
	get_tree().quit()
