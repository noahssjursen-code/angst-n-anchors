class_name PassengerCabinVisual
extends Node3D

## Static seated crowd projected from the manifest. Shared Blender poses and
## MultiMeshes, not one animated skeleton/IK/controller per logical passenger.
const DIRECTORY := "res://resources/models/characters/passengers/"
const TOPS := [Color("c2b597"),Color("355663"),Color("763d31"),Color("545e40")]
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
		batch.mesh.visible_instance_count = maxi(0,ceili((rendered_count-int(batch.variant))/4.0))

func _build(manifest: Dictionary) -> void:
	for lod in ["near", "far"]:
		var prototype := (load(DIRECTORY+"seated_passenger_"+lod+".glb") as PackedScene).instantiate() as Node3D
		for source: MeshInstance3D in prototype.find_children("*","MeshInstance3D",true,false):
			var frame := source.transform
			var parent := source.get_parent()
			while parent != prototype:
				if parent is Node3D: frame = parent.transform*frame
				parent=parent.get_parent()
			for variant in 4:
				var mesh := source.mesh.duplicate() as ArrayMesh
				for surface in mesh.get_surface_count():
					var original := source.mesh.surface_get_material(surface)
					var material := SurfaceMaterialLibrary.character_material(original,str(source.name)) as StandardMaterial3D
					if original.resource_name in ["Top","Trim"]:material.albedo_color=TOPS[variant]
					if original.resource_name=="Skin":material.albedo_color=SKINS[variant]
					mesh.surface_set_material(surface,material)
				var multi:=MultiMesh.new(); multi.transform_format=MultiMesh.TRANSFORM_3D; multi.mesh=mesh
				multi.instance_count=maxi(0,ceili((int(manifest.total)-variant)/4.0))
				for i in multi.instance_count:
					var key:String=manifest.seat_ids[i*4+variant]
					var p:Array=manifest.seat_positions[key]
					var basis:=Basis(Vector3.UP,float(manifest.get("seat_yaws",{}).get(key,0)))
					multi.set_instance_transform(i,Transform3D(basis,Vector3(p[0],p[1]-.63,p[2]))*frame)
				var instance:=MultiMeshInstance3D.new();instance.multimesh=multi
				instance.visibility_range_begin=80 if lod=="far" else 0
				instance.visibility_range_end=450 if lod=="far" else 80
				add_child(instance)
				_batches.append({"mesh":multi,"variant":variant})
		prototype.free()
