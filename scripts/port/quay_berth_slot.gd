class_name QuayBerthSlot
extends Node3D

## One quay face / station side. Geometry lives nearby; occupancy is owned by HarbourController.
## Slot origin is the terminal/pad centre. Ships spawn outside the deck face in water.

var berth_id: String = ""
var station_id: String = ""
var family: String = "general"
var commodities: PackedStringArray = PackedStringArray()
var length_m: float = 0.0
var width_m: float = 0.0
var berth_sign: float = 1.0
## Unit vector in slot local space toward open water.
var water_dir_local: Vector3 = Vector3(0.0, 0.0, 1.0)
## Metres from slot origin to the coping / water face (half deck width or pad depth).
var face_offset_m: float = 0.0
## Extra gap beyond the hull half-beam once clear of the face.
var berth_gap_m: float = 2.5

var _bollards: Array[Node] = []
var _yard_nodes: Array[Node] = []


func setup(
		id: String,
		station: String,
		family_in: String,
		commodities_in: PackedStringArray,
		length: float,
		width: float,
		sign: float = 1.0,
		water_dir: Vector3 = Vector3(0.0, 0.0, 1.0),
		face_offset: float = -1.0,
) -> void:
	berth_id = id.strip_edges()
	station_id = station.strip_edges()
	family = family_in.strip_edges()
	if family.is_empty():
		family = "general"
	commodities = commodities_in.duplicate()
	length_m = length
	width_m = width
	berth_sign = sign
	if water_dir.length_squared() > 0.0001:
		water_dir_local = water_dir.normalized()
	else:
		water_dir_local = Vector3(sign if not is_zero_approx(sign) else 1.0, 0.0, 0.0)
	## Default: water face is half the cross-section extent (deck width / pad depth).
	face_offset_m = face_offset if face_offset >= 0.0 else maxf(width_m * 0.5, 1.0)
	name = "BerthSlot_%s" % station_id.replace("/", "_")


## Distance from slot origin to ship centre along water_dir for a given half-beam.
func ship_clearance_m(half_beam_m: float) -> float:
	return face_offset_m + maxf(half_beam_m, 1.0) + berth_gap_m


## Local AABB of the legal ship pocket (water side of the coping).
func ship_pocket_local(design_beam_m: float = 16.0, design_loa_m: float = -1.0) -> AABB:
	var water := _water_unit()
	var along := _along_unit(water)
	var loa := design_loa_m if design_loa_m > 1.0 else maxf(length_m * 0.88, 20.0)
	var beam := maxf(design_beam_m, 8.0)
	var pocket_depth := beam + berth_gap_m * 2.0
	var centre := water * (face_offset_m + berth_gap_m + beam * 0.5)
	## Build axis-aligned box in slot space covering the pocket.
	var half_along := along * (loa * 0.5)
	var half_out := water * (pocket_depth * 0.5)
	var min_c := centre - half_along.abs() - half_out.abs() - Vector3(0.0, 1.0, 0.0)
	var max_c := centre + half_along.abs() + half_out.abs() + Vector3(0.0, 3.0, 0.0)
	## When along/water are axis-aligned (always for our stamps), abs on components works.
	return AABB(min_c, max_c - min_c)


## Local transform for a ship origin (bow = −Z) in the water pocket.
func ship_dock_local(half_beam_m: float) -> Transform3D:
	var water := _water_unit()
	var along := _along_unit(water)
	var clearance := ship_clearance_m(half_beam_m)
	## Basis.looking_at: model −Z aims at `forward` (along the quay).
	var basis := Basis.looking_at(along, Vector3.UP)
	return Transform3D(basis, water * clearance)


func accepts_loa_m(loa_world_m: float, margin_m: float = 4.0) -> bool:
	if length_m <= 0.01:
		return true
	return length_m + 0.01 >= loa_world_m + margin_m


func add_bollard(post: Node) -> void:
	if post == null or not is_instance_valid(post):
		return
	post.set_meta("berth_id", berth_id)
	_bollards.append(post)


func bollards() -> Array[Node]:
	var live: Array[Node] = []
	for post in _bollards:
		if post != null and is_instance_valid(post):
			live.append(post)
	_bollards = live
	return _bollards


func add_yard(yard: Node) -> void:
	if yard == null or not is_instance_valid(yard):
		return
	yard.set_meta("berth_id", berth_id)
	_yard_nodes.append(yard)


func yards() -> Array[Node]:
	var live: Array[Node] = []
	for yard in _yard_nodes:
		if yard != null and is_instance_valid(yard):
			live.append(yard)
	_yard_nodes = live
	return _yard_nodes


func primary_yard() -> Node:
	var list := yards()
	return list[0] if not list.is_empty() else null


func contains_bollard(post: Node) -> bool:
	if post == null:
		return false
	if str(post.get_meta("berth_id", "")) == berth_id and not berth_id.is_empty():
		return true
	for b in bollards():
		if b == post:
			return true
	return false


func matches_family(wanted: String) -> bool:
	var w := wanted.strip_edges()
	return w.is_empty() or family == w


func _water_unit() -> Vector3:
	if water_dir_local.length_squared() < 0.0001:
		return Vector3(0.0, 0.0, 1.0)
	return water_dir_local.normalized()


func _along_unit(water: Vector3) -> Vector3:
	var along := Vector3(-water.z, 0.0, water.x)
	if along.length_squared() < 0.0001:
		return Vector3(0.0, 0.0, -1.0)
	return along.normalized()
