class_name MarineEngineCatalog
extends RefCounted
## One installed machinery package per imported hull; presentation never grants power.
const DIRECTORY := "res://resources/models/machinery/"
const MOUNTS := {"catamaran_36x11":Vector3(0,.45,12.5), "trawler_hull_14m":Vector3(0,.35,3.2), "hull_24x8":Vector3(0,.55,7.2), "hull_32x10":Vector3(0,.65,10.2), "hull_88x14":Vector3(0,1,36)}
static var _presets: Array = []

static func options(hull_id: String) -> Array[Dictionary]:
	if _presets.is_empty(): _presets = JSON.parse_string(FileAccess.get_file_as_string("res://resources/data/vessels/engine_presets.json")).presets
	var result: Array[Dictionary] = []
	for spec: Dictionary in _presets:
		if spec.hull == hull_id: result.append(spec.duplicate(true))
	return result

static func resolve(hull_id: String, id: String = "") -> Dictionary:
	for spec in options(hull_id):
		if spec.id == id or (id.is_empty() and spec.get("default",false)): return spec
	return {}

static func apply(profile: HullPhysicsProfile, hull_id: String, id: String) -> void:
	var spec := resolve(hull_id,id)
	assert(not spec.is_empty())
	# Default hull displacement already includes the standard machinery package.
	# Upgrades add only the real difference, keeping hull/ballast mass unchanged.
	profile.design_displacement_t += (float(spec.mass_kg)-float(resolve(hull_id).mass_kg))/1000.0
	profile.engine_mass_kg = spec.mass_kg
	profile.engine_position = MOUNTS[hull_id] + Vector3(0,.7,0)
	profile.shaft_power_kw = spec.power_kw
	profile.bollard_thrust_n = float(spec.power_kw)*1000.0*profile.propulsive_efficiency/5.0
	profile.fuel_burn_l_per_sec_full = float(spec.fuel_lph)/3600.0
	profile.calibrate_longitudinal_mass_center()

static func visual(hull_id: String, id: String = "") -> Node3D:
	var spec := resolve(hull_id,id)
	assert(not spec.is_empty())
	var root := Node3D.new()
	for offset: Array in spec.get("visual_offsets", [[0,0,0]]):
		var engine := (load(DIRECTORY+str(spec.model)+".glb") as PackedScene).instantiate() as Node3D
		engine.position = Vector3(offset[0],offset[1],offset[2])
		root.add_child(engine)
		var socket := engine.find_child("OutputCoupling",true,false) as Node3D
		assert(socket != null)
		var coupling := (load(DIRECTORY+"marine_drive_coupling.glb") as PackedScene).instantiate() as Node3D
		coupling.name = "CouplingRotor"
		socket.add_child(coupling)
	SurfaceMaterialLibrary.apply(root, "engine")
	return root
