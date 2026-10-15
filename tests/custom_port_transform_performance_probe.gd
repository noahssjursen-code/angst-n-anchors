extends Node
## Bounded real-size preview diagnostic. It does not commit any edit.

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var world := {"seed":73119,"generation_version":1,"checksum":"transform-performance-fixture"}
	var plots: Array = [{"id":"plot","rect_m":[-124,-108,200,200],"owner_company_id":CustomPortExample.OWNER}]
	var snapshot := CustomPortExample.build(Vector3(0,.5,0),plots,world)
	snapshot.erase("_site_yaw")
	snapshot.water_regions = [{"rect_m":[-128,-104,232,168],"depth_m":12}]
	var catalog := CustomPortCatalog.definitions()
	var state := CustomPortState.from_dict(snapshot,world,catalog)
	if not state.validation_errors.is_empty():
		push_error(str(state.validation_errors));get_tree().quit(1);return
	var editor := CustomPortEditor.new()
	editor.configure(state,catalog,CustomPortExample.OWNER)
	var placement_id := ""
	for placement in snapshot.placements:
		if placement.asset_id == "workshop_corner_trim": placement_id=placement.id;break
	var before := state.to_dict()
	var total := 0.0
	var failures := 0
	for index in 10:
		var start := Time.get_ticks_usec()
		var proposal := editor.preview_transform(placement_id,Vector3(index*1.0,0,40),0)
		var elapsed := (Time.get_ticks_usec()-start)/1000.0
		total += elapsed
		if not proposal.ok: failures += 1
		var cold := CustomPortState.from_dict(before,world,catalog)
		var checked := cold.preview_transform({"placement_id":placement_id,"expected_placement":proposal.expected_placement,
			"position_m":proposal.placement.position_m,"yaw_degrees":proposal.placement.yaw_degrees},CustomPortExample.OWNER)
		if checked.ok != proposal.ok: failures += 1
		print("TRANSFORM_PREVIEW_PERF cell=",index," ms=",elapsed," ok=",proposal.ok," errors=",proposal.errors)
	if state.to_dict() != before: failures += 1
	print("TRANSFORM_PREVIEW_PERF placements=",snapshot.placements.size()," mean_ms=",total/10.0," failures=",failures)
	get_tree().quit(0 if failures == 0 else 1)
