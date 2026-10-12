class_name FishingLandingService
extends RefCounted

## Local authority facade for landing catch. The command/result shape can move
## behind the multiplayer server without exposing vessel scene nodes.

const MARKS_PER_100_KG := 24.0


static func quote(hold_states: Array[CatchHoldState]) -> Dictionary:
	var mass_kg := 0.0
	var value_marks := 0.0
	var lot_count := 0
	for state in hold_states:
		if state == null:
			continue
		for lot in state.lots:
			if lot == null or lot.is_empty():
				continue
			lot_count += 1
			mass_kg += lot.mass_kg
			value_marks += lot_value(lot,lot.mass_kg)
	return {
		"mass_kg": mass_kg,
		"lot_count": lot_count,
		"value_marks": maxi(int(round(value_marks)), 0),
	}


static func settle_transfer(report: Dictionary, session: Node, port_id: String) -> Dictionary:
	if session == null:
		return {"ok": false, "code": "authority_missing"}
	var mass_kg := maxf(float(report.get("mass_kg", 0.0)), 0.0)
	var value := maxi(int(report.get("value_marks", 0)), 0)
	if mass_kg <= CatchLot.MASS_EPS_KG:
		return {"ok": false, "code": "catch_empty"}
	if value <= 0:
		return {"ok": false, "code": "catch_has_no_value"}
	session.call(
		"earn_marks",
		value,
		"fish_landing",
		"Landed %.1f t of fresh groundfish" % (mass_kg / 1000.0),
		port_id,
	)
	return {"ok": true, "data": report.duplicate(true)}

static var _species:Dictionary={}

static func lot_value(lot:CatchLot,mass_kg:float)->float:
	if _species.is_empty():_species=JsonUtil.load("res://resources/data/fishing/species.json")
	var rate:=MARKS_PER_100_KG/100.0
	var multiplier:=maxf(lot.price_multiplier,0)
	if _species.has(lot.species_id):
		rate=float(_species[lot.species_id].marks_per_kg)
		multiplier=1.0
	return maxf(0,mass_kg)*rate*clampf(lot.quality,0,1)*multiplier
