class_name ShipDriveVisual
extends Node3D

## Read-only stern-gear presentation. No forces, input polling, or save ownership.
const DIRECTORY := "res://resources/models/parts/stern_gear/"
var propeller: Node3D
var rudder: Node3D
var propellers: Array[Node3D] = []
var rudders: Array[Node3D] = []
var revision := -1
var signed_rpm := 0.0
var steering_degrees := 0.0
var local_boat: BoatBody
var max_rpm := 240.0
var max_rudder_degrees := 28.0

func _init(mount_file: String = "mounts_14m.json") -> void:
	name = "DriveGear"
	var mounts: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DIRECTORY + mount_file))
	max_rpm = float(mounts["visual_max_rpm"])
	max_rudder_degrees = float(mounts["max_rudder_degrees"])
	for shaft: Dictionary in mounts.get("shafts", [mounts]):
		for spec in [["support", "transom_shaft_support"], ["propeller", "propeller_1040"], ["rudder", "rudder_0950"]]:
			var asset: String = mounts.get("assets", {}).get(spec[0], spec[1])
			var item := (load(DIRECTORY + asset + ".glb") as PackedScene).instantiate() as Node3D
			item.name = spec[0]
			var p: Array = shaft[spec[0]]
			item.position = Vector3(p[0], p[1], p[2])
			add_child(item)
			for mesh in item.find_children("*", "MeshInstance3D", true, false):
				mesh.set_meta("stern_gear_visual", true)
			if spec[0] == "propeller": propellers.append(item)
			if spec[0] == "rudder": rudders.append(item)
	propeller = propellers[0]
	rudder = rudders[0]

func bind_local(boat: BoatBody) -> void:
	local_boat = boat

## Confirmed authority state, normalized ahead-positive throttle. A network adapter
## may call this after unbinding local_boat; transport remains external.
func apply_snapshot(snapshot: Dictionary, sequence: int) -> bool:
	if sequence <= revision or snapshot.size() != 3: return false
	for key in ["throttle", "steering"]:
		var value: Variant = snapshot.get(key)
		if not (value is float or value is int) or not is_finite(float(value)): return false
	if not snapshot.get("powered") is bool: return false
	signed_rpm = clampf(float(snapshot["throttle"]), -1, 1) * max_rpm if snapshot["powered"] else 0.0
	steering_degrees = clampf(float(snapshot["steering"]), -1, 1) * max_rudder_degrees
	revision = sequence
	return true

func _process(delta: float) -> void:
	if is_instance_valid(local_boat):
		var drive := local_boat.get_node_or_null("PropulsionComponent") as PropulsionComponent
		var steering := local_boat.get_node_or_null("RudderComponent") as RudderComponent
		if drive != null and steering != null:
			max_rudder_degrees = steering.max_rudder_angle_deg
			apply_snapshot({"throttle":-drive.throttle, "steering":steering.rudder_input,
				"powered":local_boat.get_fuel_fraction() > 0.0}, revision + 1)
	for rotor in propellers:
		rotor.rotation.z = wrapf(rotor.rotation.z + signed_rpm * TAU / 60.0 * delta, -PI, PI)
	# Positive helm pushes stern toward port: trailing edge turns starboard.
	for blade in rudders: blade.rotation.y = deg_to_rad(steering_degrees)
