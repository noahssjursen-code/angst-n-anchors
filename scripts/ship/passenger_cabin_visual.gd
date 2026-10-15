class_name PassengerCabinVisual
extends Node3D

## Seated crew-base skins baked in Blender and batched by manifest seat.
## Both LODs have their origin at the cushion contact point.
const DIRECTORY := "res://resources/models/crew_base/passengers/"
const SKINS := [Color("b88966"),Color("cfaa8a"),Color("815538"),Color("bb9475")]
var _sailing := ""
var _batches: Array[Dictionary] = []
var rendered_count := 0

func sync(manifest: Dictionary) -> void:
	var id := str(manifest.get("id", ""))
	if id != _sailing:
		_sailing = id
		for child in get_children(): child.queue_free()
		_batches.clear()
		if not manifest.is_empty(): _build(manifest)
	rendered_count = int(manifest.get("onboard",0))
	for batch in _batches:
		var multi: MultiMesh = batch.mesh
		multi.visible_instance_count = clampi(ceili((rendered_count-int(batch.variant))/4.0), 0, multi.instance_count)

func _build(manifest: Dictionary) -> void:
	var seat_ids: Array = manifest.get("seat_ids", [])
	var positions: Dictionary = manifest.get("seat_positions", {})
	var yaws: Dictionary = manifest.get("seat_yaws", {})
	var total := mini(int(manifest.get("total", 0)), seat_ids.size())
	for lod in ["near", "far"]:
		var path: String = DIRECTORY+"seated_passenger_"+lod+".glb"
		if not ResourceLoader.exists(path):
			continue
		var packed := load(path) as PackedScene
		if packed == null:
			continue
		var prototype := packed.instantiate() as Node3D
		for source: MeshInstance3D in prototype.find_children("*", "MeshInstance3D", true, false):
			var frame := source.transform
			var ancestor := source.get_parent()
			while ancestor != null and ancestor != prototype:
				if ancestor is Node3D:
					frame = ancestor.transform*frame
				ancestor = ancestor.get_parent()
			for variant in SKINS.size():
				var mesh := source.mesh.duplicate() as ArrayMesh
				for surface in mesh.get_surface_count():
					var original := source.mesh.surface_get_material(surface)
					if original is StandardMaterial3D and original.resource_name == "Skin":
						var material := original.duplicate() as StandardMaterial3D
						material.albedo_color = SKINS[variant]
						mesh.surface_set_material(surface, material)
				var multi := MultiMesh.new()
				multi.transform_format = MultiMesh.TRANSFORM_3D
				multi.mesh = mesh
				multi.instance_count = maxi(0, ceili((total-variant)/4.0))
				for i in multi.instance_count:
					var key: String = str(seat_ids[i*4+variant])
					var p: Array = positions.get(key, [0.0, 0.0, 0.0])
					var basis := Basis(Vector3.UP, float(yaws.get(key, 0)))
					multi.set_instance_transform(i, Transform3D(basis, Vector3(p[0], p[1], p[2]))*frame)
				var instance := MultiMeshInstance3D.new()
				instance.multimesh = multi
				instance.visibility_range_begin = 80 if lod == "far" else 0
				instance.visibility_range_end = 450 if lod == "far" else 80
				add_child(instance)
				_batches.append({"mesh": multi, "variant": variant})
		prototype.free()
