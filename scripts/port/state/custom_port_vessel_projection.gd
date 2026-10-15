class_name CustomPortVesselProjection
extends RefCounted
## Scene-free adapter for imported vessel layouts used by the isolated port lab.
## Mounting rules mirror ImportedDraftVessel._configure_*; arbitrary bed counts
## do not create capacity. Real authority must supply its existing vessel record.
const HULLS = preload("res://scripts/ship/imported_hull_catalog.gd")
const COMMODITIES = preload("res://scripts/cargo/commodity_catalog.gd")


## Physical boundary validation, separate from the intentionally generic authority
## model. Call after its ordinary snapshot validation and before changing scenes.
## A prebuilt id promises this installed fitout; missing evidence is not abstract.
static func validate_snapshot(snapshot: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	for key in ["vessels", "stores", "reservations"]:
		if not snapshot.get(key, []) is Array:
			errors.append("Physical projection requires an array of %s." % key)
	if not errors.is_empty(): return _validation_result(errors)
	for vessel in snapshot.get("vessels", []):
		if not vessel is Dictionary:
			errors.append("Invalid vessel record at physical projection boundary.")
			continue
		if not vessel.has("prebuilt_id"): continue
		var pending: Array = []
		for reservation in snapshot.get("reservations", []):
			if not reservation is Dictionary:
				errors.append("Invalid cargo reservation at physical projection boundary.")
				continue
			if reservation.get("vessel_id") != vessel.get("id"): continue
			var store := _record_with_id(snapshot.get("stores", []), reservation.get("store_id"))
			var lot := _record_with_id(store.get("lots", []), reservation.get("lot_id"))
			if lot.is_empty() or not _finite_number(reservation.get("quantity")) or float(reservation.quantity) <= 0:
				errors.append("Vessel %s has an unresolved cargo reservation." % vessel.get("id", "?"))
				continue
			var projected := lot.duplicate(true)
			projected.quantity = reservation.quantity
			pending.append(projected)
		errors.append_array(_physical_vessel_errors(vessel, pending))
	return _validation_result(errors)


static func validate_vessel(vessel: Dictionary) -> Dictionary:
	return _validation_result(_physical_vessel_errors(vessel, []))


static func _physical_vessel_errors(vessel: Dictionary, pending: Array) -> Array[String]:
	var errors: Array[String] = []
	if not vessel.has("prebuilt_id"): return errors
	var label := str(vessel.get("id", "?"))
	if not vessel.prebuilt_id is String:
		errors.append("Vessel %s has an invalid prebuilt id." % label)
		return errors
	# Container pads currently have no authored payload rating. Keep the explicit
	# scenario ceiling, but never let that ceiling invent a bed or enlarge a hold.
	var limits: Variant = vessel.get("handling_capacity_kg")
	if not limits is Dictionary:
		errors.append("Vessel %s is missing installed handling capacities." % label)
		return errors
	var container_limit: Variant = limits.get("container", limits.get("general", 0.0))
	if not _finite_number(container_limit) or float(container_limit) < 0:
		errors.append("Vessel %s has an invalid container mass ceiling." % label)
		return errors
	var expected := from_prebuilt(vessel.prebuilt_id, label, str(vessel.get("owner_company_id", "")), "", float(container_limit))
	if expected.is_empty():
		errors.append("Vessel %s references an unknown or unsupported prebuilt: %s." % [label, vessel.prebuilt_id])
		return errors
	for field in ["hull_id", "length_m", "beam_m", "draft_m", "capacity_units", "cargo_holds", "container_beds", "handling_capacity_kg"]:
		var actual: Variant=vessel.get(field)
		if field=="cargo_holds" and actual is Array:
			actual=actual.duplicate(true)
			for definition in actual:
				if definition is Dictionary:definition.id=_installed_catch_id(definition)
		if not vessel.has(field) or not _same_evidence(actual, expected[field]):
			errors.append("Vessel %s %s does not match its installed prebuilt fitout." % [label, field])
	for field in ["accepted_handling_modes", "accepted_container_types"]:
		if not _same_string_set(vessel.get(field), expected[field]):
			errors.append("Vessel %s %s does not match its installed prebuilt fitout." % [label, field])
	if not _finite_number(vessel.get("capacity_kg")) or float(vessel.capacity_kg) < 0 or float(vessel.capacity_kg) > float(expected.capacity_kg) + 0.000001:
		errors.append("Vessel %s mass ceiling exceeds its installed fitout." % label)
	if not vessel.get("lots") is Array:
		errors.append("Vessel %s has no valid cargo manifest." % label)
	if not errors.is_empty(): return errors
	# Owner, name and instance identity may differ from the stock blueprint. A
	# scenario may impose a lower overall mass ceiling, but the installed hardware
	# evidence itself remains the canonical construction evidence.
	expected.capacity_kg = vessel.capacity_kg
	var payload: Array = vessel.lots.duplicate(true)
	payload.append_array(pending)
	errors.append_array(_payload_errors(expected, payload))
	return errors


static func _payload_errors(vessel: Dictionary, lots: Array) -> Array[String]:
	var errors: Array[String] = []
	var bulk: Array = []
	var catch_lots: Array = []
	var mode_mass: Dictionary = {}
	var used_beds: Dictionary = {}
	var available_beds: Dictionary = {}
	var total_mass := 0.0
	for bed in vessel.container_beds:
		available_beds[bed.container_type] = int(available_beds.get(bed.container_type, 0)) + 1
	for lot in lots:
		if not lot is Dictionary or not lot.get("id") is String or not lot.get("commodity_id") is String or not lot.get("attributes", {}) is Dictionary:
			errors.append("Vessel %s has an invalid physical cargo lot." % vessel.id)
			continue
		if not _finite_number(lot.get("quantity")) or not _finite_number(lot.get("unit_mass_kg")) or float(lot.quantity) <= 0 or float(lot.unit_mass_kg) <= 0:
			errors.append("Vessel %s has invalid physical cargo mass." % vessel.id)
			continue
		var mass := float(lot.quantity) * float(lot.unit_mass_kg)
		if not is_finite(mass):
			errors.append("Vessel %s has invalid physical cargo mass." % vessel.id)
			continue
		var mode := _physical_lot_mode(lot)
		if lot.get("attributes", {}).has("container_type") and str(lot.attributes.container_type).is_empty():
			# The physical presenter treats a declared container_type as a box.
			# An empty type must not disguise bulk/catch as container payload.
			errors.append("Vessel %s has cargo with an empty physical container type." % vessel.id)
		total_mass += mass
		mode_mass[mode] = float(mode_mass.get(mode, 0)) + mass
		if mode not in vessel.accepted_handling_modes:
			errors.append("Vessel %s has no installed equipment for %s cargo." % [vessel.id, mode])
		if mode in ["container", "general"]:
			var type := str(lot.get("attributes", {}).get("container_type", ""))
			if not is_equal_approx(float(lot.quantity), roundf(float(lot.quantity))) or type not in available_beds:
				errors.append("Vessel %s cargo does not fit an installed securing bed." % vessel.id)
			else:
				used_beds[type] = float(used_beds.get(type, 0)) + float(lot.quantity)
		elif mode == "bulk":
			bulk.append(lot)
		elif mode == "catch":
			catch_lots.append(lot)
	if total_mass > float(vessel.capacity_kg) + 0.000001:
		errors.append("Vessel %s carried and reserved cargo exceeds its physical mass ceiling." % vessel.id)
	for mode in mode_mass:
		if float(mode_mass[mode]) > float(vessel.handling_capacity_kg.get(mode, 0)) + 0.000001:
			errors.append("Vessel %s carried and reserved %s exceeds its installed capacity." % [vessel.id, mode])
	for type in used_beds:
		if float(used_beds[type]) > int(available_beds[type]):
			errors.append("Vessel %s has more carried and reserved containers than installed beds." % vessel.id)
	var plan := bulk_hold_plan(vessel, bulk)
	if not plan.ok:
		errors.append("Vessel %s physical bulk packing rejected: %s." % [vessel.id, plan.code])
	if not _catch_payload_fits(vessel, catch_lots):
		errors.append("Vessel %s catch cannot be fully installed in its actual tanks." % vessel.id)
	return errors


static func _catch_payload_fits(vessel: Dictionary, lots: Array) -> bool:
	return catch_hold_plan(vessel,lots).ok


## Shared validation for catch stored ashore or in an installed hold. Do not let
## CatchLot.create silently clamp or discard durable port inventory.
static func catch_lot_error(lot: Dictionary) -> String:
	for key in ["id","commodity_id"]:
		if not lot.get(key) is String or str(lot[key]).is_empty() or str(lot[key]).strip_edges()!=str(lot[key]):return "invalid_catch_"+key
	var attrs: Variant=lot.get("attributes",{})
	if not attrs is Dictionary:return "invalid_catch_attributes"
	if not _finite_number(lot.get("quantity")) or not _finite_number(lot.get("unit_mass_kg")):return "invalid_catch_mass"
	if float(lot.quantity)<=0 or float(lot.unit_mass_kg)<=0:return "invalid_catch_mass"
	var mass:=float(lot.quantity)*float(lot.unit_mass_kg)
	if not is_finite(mass):return "invalid_catch_mass"
	if mass<=CatchLot.MASS_EPS_KG:return "catch_below_component_threshold"
	for key in ["caught_game_hours","quality","price_multiplier","length_cm"]:
		if attrs.has(key) and (not _finite_number(attrs[key]) or float(attrs[key])<0):return "invalid_catch_"+key
	if float(attrs.get("quality",1))>1:return "invalid_catch_quality"
	if attrs.has("specimen") and not attrs.specimen is bool:return "invalid_catch_specimen"
	for key in ["species_id","ground_tier","size_grade"]:
		if attrs.has(key) and (not attrs[key] is String or str(attrs[key]).strip_edges()!=str(attrs[key])):return "invalid_catch_"+key
	if attrs.has("caught_position"):
		var at: Variant=attrs.caught_position
		if not at is Array or at.size()!=2 or not _finite_number(at[0]) or not _finite_number(at[1]):return "invalid_catch_position"
		if not Vector2(float(at[0]),float(at[1])).is_finite():return "invalid_catch_position"
	return ""


## Early port documents used catch:N for these authored tanks. Keep their JSON
## identity intact, but resolve that exact legacy alias to the installed part's
## tank_N ID for physical evidence and hose allocation. Other IDs are unchanged.
static func _installed_catch_id(definition: Dictionary) -> String:
	var id:=str(definition.get("id",""))
	if definition.get("source_asset","")=="insulated_catch_tank" and id.begins_with("catch:"):
		var suffix:=id.trim_prefix("catch:")
		if suffix.is_valid_int() and int(suffix)>=0 and str(int(suffix))==suffix:return "tank_"+suffix
	return id


## The same ordered acceptance as CatchHoldComponent, without scene instances.
## A specimen must fit one compartment. Bulk catch can spread between holds.
static func catch_hold_plan(vessel: Dictionary, lots: Array) -> Dictionary:
	if not vessel.has("cargo_holds"):return {"ok":true,"code":"abstract_capacity","hold_states":[],"allocations":[]}
	if not vessel.cargo_holds is Array:return {"ok":false,"code":"invalid_cargo_holds"}
	var holds: Array[CatchHoldState] = []
	var allocations: Array[Dictionary]=[]
	var ids: Dictionary={}
	for definition in vessel.cargo_holds:
		if not definition is Dictionary or not definition.get("id") is String or str(definition.id).is_empty() or ids.has(definition.id):return {"ok":false,"code":"invalid_cargo_holds"}
		ids[definition.id]=true
		if not definition.get("handling_mode") is String or not _finite_number(definition.get("capacity_kg")) or float(definition.capacity_kg)<=0:return {"ok":false,"code":"invalid_cargo_holds"}
		if definition.handling_mode != "catch": continue
		var hold := CatchHoldState.new()
		hold.hold_id = _installed_catch_id(definition)
		hold.capacity_kg = float(definition.capacity_kg)
		holds.append(hold)
	for lot in lots:
		var invalid:=catch_lot_error(lot)
		if not invalid.is_empty():return {"ok":false,"code":invalid,"lot_id":str(lot.get("id",""))}
		var attrs: Dictionary = lot.get("attributes", {})
		var data := attrs.duplicate(true)
		var mass := float(lot.quantity) * float(lot.unit_mass_kg)
		data.merge({"lot_id":str(lot.id), "product_id":str(lot.commodity_id), "mass_kg":mass,
			"vessel_id":str(vessel.id), "owner_id":str(vessel.owner_company_id)}, true)
		var remaining := CatchLot.create(data)
		var installed := 0.0
		for hold in holds:
			var before := hold.total_mass_kg()
			remaining = hold.accept_lot(remaining)
			var accepted:=hold.total_mass_kg()-before
			installed += accepted
			if accepted>0:allocations.append({"lot_id":str(lot.id),"hold_id":hold.hold_id,"mass_kg":accepted})
			if remaining.is_empty(): break
		if absf(installed - mass) > 0.000001:return {"ok":false,"code":"catch_compartments_exceeded","lot_id":str(lot.id),"unplaced_kg":maxf(0,mass-installed)}
	var states: Array[Dictionary]=[]
	for hold in holds:states.append(hold.to_dict())
	return {"ok":true,"code":"fits","hold_states":states,"allocations":allocations}


static func _physical_lot_mode(lot: Dictionary) -> String:
	var attributes: Dictionary = lot.get("attributes", {})
	var type := str(attributes.get("container_type", ""))
	if not type.is_empty(): return "general" if type == "legacy_4m" else "container"
	for entry in COMMODITIES.COMMODITIES:
		if str(entry.id) == str(lot.commodity_id): return str(entry.handling_mode)
	return str(attributes.get("handling_mode", "general"))


static func _same_evidence(actual: Variant, expected: Variant) -> bool:
	if _finite_number(expected):
		return _finite_number(actual) and absf(float(actual) - float(expected)) <= 0.000001
	if expected is Dictionary:
		if not actual is Dictionary or actual.size() != expected.size(): return false
		for key in expected:
			if not actual.has(key) or not _same_evidence(actual[key], expected[key]): return false
		return true
	if expected is Array:
		if not actual is Array or actual.size() != expected.size(): return false
		for index in expected.size():
			if not _same_evidence(actual[index], expected[index]): return false
		return true
	return typeof(actual) == typeof(expected) and actual == expected


static func _same_string_set(actual: Variant, expected: Array) -> bool:
	if not actual is Array or actual.size() != expected.size(): return false
	var seen: Dictionary = {}
	for value in actual:
		if not value is String or value not in expected or seen.has(value): return false
		seen[value] = true
	return true


static func _finite_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func _record_with_id(rows: Variant, id: Variant) -> Dictionary:
	if rows is Array:
		for row in rows:
			if row is Dictionary and row.get("id") == id: return row
	return {}


static func _validation_result(errors: Array[String]) -> Dictionary:
	return {"ok": errors.is_empty(), "code": "physical_projection_valid" if errors.is_empty() else "invalid_vessel_projection", "errors": errors}


## Simulate the same ordered compartment fill as the installed ship components.
## Input lots are already classified as bulk by the authority. This stays pure:
## BulkHoldState/BulkCargoLot are data objects, not scene equipment or services.
static func bulk_hold_plan(vessel: Dictionary, bulk_lots: Array) -> Dictionary:
	if not vessel.has("cargo_holds"):
		# Legacy abstract simulation records have no physical fitout projection.
		return {"ok":true,"code":"abstract_capacity","hold_states":[]}
	if not vessel.cargo_holds is Array:
		return {"ok":false,"code":"invalid_cargo_holds"}
	var holds: Array[BulkHoldState] = []
	var ids: Dictionary = {}
	for definition in vessel.cargo_holds:
		if not definition is Dictionary or not definition.get("id") is String or str(definition.id).is_empty() or ids.has(definition.id):
			return {"ok":false,"code":"invalid_cargo_holds"}
		ids[definition.id] = true
		if not definition.get("handling_mode") is String or not (definition.get("capacity_kg") is int or definition.get("capacity_kg") is float):
			return {"ok":false,"code":"invalid_cargo_holds"}
		if not is_finite(float(definition.capacity_kg)) or float(definition.capacity_kg) <= 0:
			return {"ok":false,"code":"invalid_cargo_holds"}
		if str(definition.handling_mode) != "bulk": continue
		var hold := BulkHoldState.new()
		hold.hold_id = str(definition.id)
		hold.capacity_tonnes_t = float(definition.capacity_kg) / 1000.0
		holds.append(hold)
	for lot in bulk_lots:
		var mass_kg := float(lot.quantity) * float(lot.unit_mass_kg)
		var shipment := str(lot.get("attributes", {}).get("consignment_id", lot.id))
		var remaining := BulkCargoLot.create(str(lot.commodity_id), mass_kg / 1000.0, shipment)
		var installed_kg := 0.0
		for hold in holds:
			var before := hold.filled_tonnes_t
			remaining = hold.accept_lot(remaining)
			installed_kg += (hold.filled_tonnes_t - before) * 1000.0
			if remaining.is_empty(): break
		# Component epsilon can discard a tiny lot/remainder; never accept mass
		# which would disappear from the exact manifest during reconstruction.
		if absf(mass_kg - installed_kg) > 0.000001:
			return {"ok":false,"code":"bulk_compartments_exceeded","lot_id":str(lot.id),"unplaced_kg":maxf(0,mass_kg-installed_kg)}
	var states: Array[Dictionary] = []
	for hold in holds: states.append(hold.to_dict())
	return {"ok":true,"code":"fits","hold_states":states}


static func from_prebuilt(prebuilt_id: String, vessel_id: String, company_id: String,
		display_name := "", container_mass_limit_kg := 0.0) -> Dictionary:
	# A catalog id is not an arbitrary filesystem path.
	if prebuilt_id.is_empty():
		return {}
	for character in prebuilt_id:
		if character not in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-":
			return {}
	var path := "res://resources/data/vessels/prebuilt/%s.json" % prebuilt_id
	if not FileAccess.file_exists(path):
		return {}
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not raw is Dictionary or not raw.get("brick_layout") is Dictionary:
		return {}
	var result := from_layout(vessel_id, company_id, str(raw.get("hull_id", "")), raw.brick_layout, container_mass_limit_kg)
	if not result.is_empty():
		result.prebuilt_id = prebuilt_id
		result.name = str(raw.get("name", vessel_id)) if display_name.is_empty() else display_name
	return result


static func from_layout(vessel_id: String, company_id: String, hull_id: String,
		layout: Dictionary, container_mass_limit_kg := 0.0) -> Dictionary:
	if not HULLS.ENTRIES.has(hull_id) or str(layout.get("hull", "")) != hull_id or not layout.get("parts") is Array or not is_finite(container_mass_limit_kg) or container_mass_limit_kg < 0:
		return {}
	var config: Dictionary = HULLS.ENTRIES[hull_id]
	var parts: Array[Dictionary] = []
	var seen: Dictionary = {}
	for raw in layout.get("parts", []):
		if not raw is Dictionary or not raw.get("position") is Array or raw.position.size() != 3:
			continue
		var valid := true
		for value in raw.position:
			valid = valid and (value is int or value is float) and is_finite(float(value))
		if not valid or not (raw.get("yaw_degrees", 0) is int or raw.get("yaw_degrees", 0) is float) or not is_finite(float(raw.get("yaw_degrees", 0))):
			continue
		var key := "%s@%s" % [raw.get("asset_id", ""), JSON.stringify(raw.position)]
		if seen.has(key):
			continue
		seen[key] = true
		parts.append(raw)
	var beds: Array[Dictionary] = []
	var holds: Array[Dictionary] = []
	var has_iso := _has(parts, "container_bed_20ft")
	var has_legacy := _has(parts, "cargo_securing_bed_4m")
	var sealed := _has(parts, "cargo_deck_5x8")
	for index in parts.size():
		var part: Dictionary = parts[index]
		var asset := str(part.get("asset_id", ""))
		var at := _position(part)
		if asset == "insulated_catch_tank":
			holds.append({"id": "tank_%d" % index, "handling_mode": "catch", "capacity_kg": 600,
				"position_m": part.position.duplicate(), "source_asset": asset})
		if not _aligned(part):
			continue
		if asset == "container_bed_20ft" and config.has("container_beds"):
			var mounts: Dictionary = config.container_beds
			for lane in mounts.lanes:
				for bay in int(mounts.bay_count):
					if at.is_equal_approx(Vector3(float(lane), float(config.depth_m), float(mounts.first_bay) + bay * float(mounts.bay_pitch))):
						beds.append(_bed(part, index, "20ft"))
		elif hull_id == "hull_24x8" and not _has(parts, "bulk_divider_5m") and not _has(parts, "hatch_cover_5x4"):
			if asset == "container_bed_20ft" and not has_legacy and _mounted(parts, "cargo_deck_5x8", Vector3(0, 3.6, 0)):
				if at.is_equal_approx(Vector3(-1.25, 3.6, 0)) or at.is_equal_approx(Vector3(1.25, 3.6, 0)):
					beds.append(_bed(part, index, "20ft"))
			elif asset == "cargo_securing_bed_4m" and not has_iso and not sealed:
				if at.is_equal_approx(Vector3(0, 1.6, -2)) or at.is_equal_approx(Vector3(0, 1.6, 2)):
					beds.append(_bed(part, index, "legacy_4m"))
	if hull_id == "hull_24x8" and not sealed and _mounted(parts, "bulk_divider_5m", Vector3(0, 3.6, 0)):
		for station in [-2.05, 2.05]:
			holds.append({"id": "bulk_forward" if station < 0 else "bulk_aft", "handling_mode": "bulk", "capacity_kg": 40000,
				"position_m": [0, 3.6, station], "source_asset": "bulk_divider_5m"})
	if hull_id == "hull_32x10" and _mounted(parts, "hold_coaming_6x12", Vector3(0, 4.5, 0)):
		holds.append({"id": "bulk_main", "handling_mode": "bulk", "capacity_kg": 120000,
			"position_m": [0, 4.5, 0], "source_asset": "hold_coaming_6x12"})
	var capacity: Dictionary = {}
	var types: Array[String] = []
	for hold in holds:
		capacity[hold.handling_mode] = float(capacity.get(hold.handling_mode, 0)) + float(hold.capacity_kg)
	for bed in beds:
		if bed.container_type not in types:
			types.append(bed.container_type)
		var mode := "general" if bed.container_type == "legacy_4m" else "container"
		capacity[mode] = container_mass_limit_kg
	var total := 0.0
	var modes: Array[String] = []
	for mode in capacity:
		total += float(capacity[mode])
		modes.append(mode)
	return {"id": vessel_id, "name": vessel_id, "owner_company_id": company_id, "hull_id": hull_id,
		"length_m": config.loa_m, "beam_m": config.beam_m, "draft_m": config.draft_m,
		"capacity_kg": total, "capacity_units": beds.size(), "accepted_handling_modes": modes,
		"handling_capacity_kg": capacity, "accepted_container_types": types,
		"container_beds": beds, "cargo_holds": holds, "lots": [], "berth_id": "",
		"capacity_source": {"geometry": "ImportedHullCatalog", "fitout": "ImportedDraftVessel mounting rules",
			"container_mass": "explicit scenario ceiling; runtime pads have no authored limit" if not beds.is_empty() else "none"}}


static func _bed(part: Dictionary, index: int, type: String) -> Dictionary:
	return {"id": "cargo:" + str(part.get("instance_id", "part-%d" % index)), "container_type": type,
		"position_m": part.position.duplicate(), "yaw_degrees": 0,
		"footprint_m": [4, 4] if type == "legacy_4m" else [2.5, 6.5]}


static func _has(parts: Array[Dictionary], asset: String) -> bool:
	for part in parts:
		if str(part.get("asset_id", "")) == asset:
			return true
	return false


static func _mounted(parts: Array[Dictionary], asset: String, at: Vector3) -> bool:
	for part in parts:
		if str(part.get("asset_id", "")) == asset and _aligned(part) and _position(part).is_equal_approx(at):
			return true
	return false


static func _aligned(part: Dictionary) -> bool:
	return is_zero_approx(fposmod(float(part.get("yaw_degrees", 0)), 360.0))


static func _position(part: Dictionary) -> Vector3:
	var p: Array = part.get("position", [0, 0, 0])
	return Vector3(float(p[0]), float(p[1]), float(p[2]))
