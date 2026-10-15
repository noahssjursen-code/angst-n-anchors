class_name CustomPortFishLanding
extends Node3D
## Compact existing landing machinery. No harbour registration, jobs or sales.
const CAPACITY_KG := 40000.0
const HOSE_REACH_M := 24.0
var preview := false
var preview_valid := true
var collision_enabled := true
var pump: FishLandingPump
var bank: ShoreRswTankBank

func _ready() -> void:
	pump = FishLandingPump.new()
	pump.name = "FishLandingPump"
	pump.position = Vector3(6, 0, -1)
	pump.rotation_degrees.y = 90
	add_child(pump)
	bank = ShoreRswTankBank.new()
	bank.name = "ShoreRswTankBank"
	bank.bank_id = "projected_fish_store"
	bank.capacity_kg = CAPACITY_KG
	bank.position = Vector3(-3, 0, 0)
	add_child(bank)
	# Deliberately do not bind a receiving inventory to the pump. The custom
	# port's committed store owns all fish; playback only changes sight glasses.
	_finish_bank_materials()
	var discharge := pump.transform * Vector3(-4.75, 1.45, 0)
	var inlet := to_local(bank.inlet_world())
	var height := maxf(discharge.y, inlet.y) + 2.2
	var points := [discharge, Vector3(discharge.x, height, discharge.z), Vector3(inlet.x, height, inlet.z), inlet]
	for i in points.size() - 1: _pipe(points[i], points[i + 1])
	if collision_enabled and not preview:
		_box_collision(pump, Vector3(-.05,.90,0), Vector3(7.26,1.80,3.80))
		_box_collision(pump, Vector3(-3.35,.915,0), Vector3(2.56,1.83,2.70))
		_box_collision(pump, Vector3(-.15,2.20,0), Vector3(4.60,1.92,2.10))
		_box_collision(bank, Vector3(0,.14,0), Vector3(10.4,.28,11.5))
		_box_collision(bank, Vector3(3.65,1.4,0), Vector3(3.4,2.5,5.8))
		for z in [-2.35,2.35]:
			var cylinder := CylinderShape3D.new()
			cylinder.radius = 2.08
			cylinder.height = 5.0
			_collision(bank, Vector3(-1,2.75,z), cylinder)
	SurfaceMaterialLibrary.map_frame(self)
	if preview:
		var material := StandardMaterial3D.new()
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = Color(.28,1,.57,.32) if preview_valid else Color(1,.22,.16,.38)
		for mesh in SurfaceMaterialLibrary.meshes(self):
			mesh.material_override = material
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for nameplate in find_children("*","Label3D",true,false): nameplate.hide()

func set_preview(value: bool, valid: bool) -> void:
	preview = value
	preview_valid = valid

func apply_store(store: Dictionary) -> bool:
	var lots: Array = []
	for lot in store.get("lots", []):
		var data: Dictionary = lot.get("attributes", {}).duplicate(true)
		data.merge({"lot_id": str(lot.id), "product_id": str(lot.commodity_id),
			"mass_kg": float(lot.quantity) * float(lot.unit_mass_kg)}, true)
		lots.append(CatchLot.create(data).to_dict())
	bank.bank_id = str(store.id)
	bank.capacity_kg = float(store.capacity_kg)
	return bank.apply_projection({"hold_id": str(store.id), "capacity_kg": float(store.capacity_kg), "lots": lots})

func _finish_bank_materials() -> void:
	for mesh in SurfaceMaterialLibrary.meshes(bank):
		var original := mesh.get_active_material(0) as StandardMaterial3D
		if original == null: continue
		# Preserve optical sight glasses and their emissive-looking fill. Existing
		# procedural tank shells get the same approved finish as landing hardware.
		var colour := original.albedo_color
		if mesh in bank._sight_fills or (colour.r < .05 and colour.b > colour.r * 1.5): continue
		var profile := "brushed_steel" if original.metallic > .5 else "machinery_enamel"
		if mesh == bank.get_child(0): profile = "concrete_cast"
		mesh.material_override = SurfaceMaterialLibrary.material(profile, colour)

func _pipe(a: Vector3, b: Vector3) -> void:
	var mesh := MeshBuilder.cylinder(.18, a.distance_to(b), Color(.58,.62,.63), .38, .72)
	mesh.name = "RswTransferPipe"
	var direction := (b-a).normalized()
	var x := direction.cross(Vector3.FORWARD)
	if x.length_squared() < .001: x = direction.cross(Vector3.RIGHT)
	x = x.normalized()
	mesh.transform = Transform3D(Basis(x, direction, x.cross(direction).normalized()), (a+b)*.5)
	mesh.material_override = SurfaceMaterialLibrary.material("galvanized", Color(.58,.62,.63))
	add_child(mesh)

func _box_collision(parent: Node3D, at: Vector3, size: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	_collision(parent, at, shape)

func _collision(parent: Node3D, at: Vector3, shape: Shape3D) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = at
	body.set_meta("plot_build_visual", self)
	var volume := CollisionShape3D.new()
	volume.shape = shape
	body.add_child(volume)
	parent.add_child(body)
