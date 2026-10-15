class_name CustomPortTestVisitors
extends RefCounted
## Explicit empty scenario visitors, available only in the isolated workshop.
## Admission uses the same revisioned authority command as an external fleet
## projection; no company, live fleet, purchase or cargo source is changed.
const VESSELS=preload("res://scripts/port/state/custom_port_vessel_projection.gd")
const PRESETS: Array[Dictionary]=[
	{"id":"fishing_hook_line","name":"Nordlys · 14 m","vessel_name":"Nordlys","container_mass_limit_kg":0},
	{"id":"28_10_m","name":"Harbour Cargo · 24 m","vessel_name":"Harbour Cargo","container_mass_limit_kg":48000},
	{"id":"coastal_coaster","name":"Coastal Bulk · 32 m","vessel_name":"Coastal Bulk","container_mass_limit_kg":0}]

static func options() -> Array[Dictionary]:
	return PRESETS.duplicate(true)

static func invite(state: CustomPortState,prebuilt_id: String) -> Dictionary:
	if not ShipyardPlaytestMode.active():return {"ok":false,"code":"workshop_only"}
	var preset: Dictionary={}
	for entry in PRESETS:
		if entry.id==prebuilt_id:preset=entry;break
	if preset.is_empty():return {"ok":false,"code":"unknown_test_vessel"}
	var snapshot:=state.to_dict()
	var ordinal:=1
	var known: Dictionary={}
	for vessel in snapshot.vessels:known[str(vessel.id)]=true
	while known.has("test-visitor-%d"%ordinal):ordinal+=1
	var id:="test-visitor-%d"%ordinal
	var vessel:=VESSELS.from_prebuilt(prebuilt_id,id,"company-test-visitor",str(preset.vessel_name),float(preset.container_mass_limit_kg))
	if vessel.is_empty():return {"ok":false,"code":"test_blueprint_unavailable"}
	return state.apply({"command_id":"invite-%s-%d"%[id,state.revision()],"expected_revision":state.revision(),"actor_company_id":vessel.owner_company_id,
		"kind":"admit_vessel","payload":{"vessel_id":id}}, {"vessel_records":{id:vessel}})
