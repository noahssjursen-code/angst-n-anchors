extends Node

const Survey := preload("res://scripts/port/state/custom_port_water_survey.gd")
const State := preload("res://scripts/port/state/custom_port_state.gd")
var checks := 0
var failures: Array[String] = []

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var record := _record()
	var original := JSON.stringify(record)
	var positions: Array[Vector2] = []
	var sampled := func(at: Vector2) -> float:
		positions.append(at)
		return -11.5
	var started := Survey.begin(record, sampled, -1.5, {"apron_m": 0})
	_check(started.ok and started.total == 2, "Plot cover creates two 8m cells")
	var job = started.job
	_check(job.authority_context().is_empty(), "Incomplete work cannot be submitted as a survey")
	var status: Dictionary = job.step(1, 0)
	_check(status.completed == 1 and not status.done and status.progress == 0.5, "A one-cell step exposes bounded progress")
	status = job.step(1, 0)
	_check(status.done and status.ok and status.samples == 50, "Each complete water cell samples the 2m lattice")
	var context: Dictionary = job.authority_context()
	var regions: Array = context.water_survey.regions
	_check(regions.size() == 2 and regions[0].depth_m == 9.0, "Depth is seabed distance minus the safety allowance")
	_check(positions.front() == Vector2(100, 200) and positions.back() == Vector2(116, 208), "Sampler receives translated world coordinates")
	_check(regions[0].rect_m == [0.0, 0.0, 8.0, 8.0], "Output geometry remains port-local JSON data")
	_check(JSON.stringify(record) == original, "Surveying never mutates its source record")
	_check(context.water_survey.port_id == record.id and context.water_survey.world == record.world and context.water_survey.for_revision == 0, "Authority context binds the source port, world and revision")
	context.water_survey.regions.clear()
	_check(job.authority_context().water_survey.regions.size() == 2, "Returned context cannot mutate the retained survey")
	var state := State.from_dict(record, record.world, {})
	_check(state.validation_errors.is_empty(), "Minimal source port validates")
	var applied := state.apply({"command_id":"survey-1", "expected_revision":0, "actor_company_id":"owner", "kind":"refresh_water_survey", "payload":{}}, job.authority_context())
	_check(applied.ok and state.to_dict().water_regions.size() == 2, "Authority accepts the completed geography evidence")
	var stale := state.apply({"command_id":"survey-stale", "expected_revision":1, "actor_company_id":"owner", "kind":"refresh_water_survey", "payload":{}}, job.authority_context())
	_check(not stale.ok and stale.code == "survey_revision_mismatch", "A changed authority revision rejects an old job")
	var repeat := Survey.begin(state.to_dict(), sampled, -1.5, {"apron_m":0})
	_check(repeat.total == 0 and repeat.skipped == 2 and repeat.job.authority_context().water_survey.regions.is_empty(), "Previously verified coverage is not sampled or emitted twice")
	var expanded: Dictionary = state.to_dict()
	expanded.plots.append({"id":"next", "owner_company_id":"owner", "rect_m":[16,0,8,8]})
	var expansion := Survey.begin(expanded, sampled, -1.5, {"apron_m":0})
	_check(expansion.total == 1 and expansion.skipped == 2, "Expansion schedules only the newly acquired strip")
	expansion.job.step(256,0)
	_check(expansion.job.authority_context().water_survey.regions[0].rect_m == [16.0,0.0,8.0,8.0], "Expansion output cannot overwrite the old survey")
	var partial := _record()
	partial.water_regions = [{"rect_m":[0,0,4,8], "depth_m":6}]
	var partial_job := Survey.begin(partial, sampled, -1.5, {"apron_m":0})
	_check(partial_job.total == 1 and partial_job.skipped == 1, "A partially covered cell is skipped to avoid overlapping old evidence")
	var land := Survey.begin(_record(), func(at: Vector2) -> float: return 2.0 if at.x < 108 else -11.5, -1.5, {"apron_m":0})
	land.job.step(256,0)
	_check(land.job.authority_context().water_survey.regions.size() == 1, "Land or a dry sample prevents declaring the cell water")
	var shoal := Survey.begin(_record(), func(at: Vector2) -> float: return -4.5 if at == Vector2(104,204) else -11.5, -1.5, {"apron_m":0})
	shoal.job.step(256,0)
	_check(shoal.job.authority_context().water_survey.regions[0].depth_m == 2.0, "A shallow interior sample controls the entire cell")
	var small := _record()
	small.plots[0].rect_m = [0,0,8,8]
	var apron := Survey.begin(small, sampled, -1.5)
	_check(apron.total == 625, "The default survey includes the full 96m apron")
	var other := _record()
	other.plots[0].owner_company_id = "someone-else"
	_check(Survey.begin(other,sampled,-1.5).total == 0, "Unowned plot geometry does not enlarge a survey")
	var cancelled := Survey.begin(_record(),sampled,-1.5,{"apron_m":0})
	cancelled.job.step(1,0)
	cancelled.job.cancel()
	_check(cancelled.job.step().code == "cancelled" and cancelled.job.authority_context().is_empty(), "Cancelled partial work cannot be submitted")
	var invalid_sample := Survey.begin(_record(),func(_at: Vector2) -> float: return NAN,-1.5,{"apron_m":0})
	_check(not invalid_sample.job.step().ok and invalid_sample.job.authority_context().is_empty(), "Invalid geography fails without publishing partial coverage")
	_check(not Survey.begin(_record(),Callable(),-1.5).ok, "Missing sampler is rejected")
	_check(not Survey.begin(_record(),sampled,INF).ok, "Invalid sea datum is rejected")
	_check(not Survey.begin(_record(),sampled,-1.5,{"apron_m":-1}).ok, "Negative apron is rejected")
	var huge := _record()
	huge.plots[0].rect_m = [0,0,1000000,1000000]
	_check(Survey.begin(huge,sampled,-1.5).code == "survey_area_too_large", "Oversized work is rejected before sampling")
	var bounded := Survey.begin(_record(),sampled,-1.5,{"apron_m":0,"max_cells":1})
	_check(not bounded.ok, "Caller can impose a smaller area budget")
	var bad_old := _record()
	bad_old.water_regions = [{"rect_m":[0,0,8,8],"depth_m":NAN}]
	_check(not Survey.begin(bad_old,sampled,-1.5).ok, "Malformed prior evidence is rejected")
	if failures.is_empty(): print("CUSTOM PORT WATER SURVEY PASS (%d checks)" % checks)
	else:
		for failure in failures: push_error(failure)
	get_tree().quit(0 if failures.is_empty() else 1)

func _record() -> Dictionary:
	return {"schema_version":1,"id":"survey-port","owner_company_id":"owner",
		"world":{"seed":42,"generation_version":1,"checksum":"survey-test"},
		"origin_m":[100,0.5,200],"deck_height_above_sea_m":2,
		"plots":[{"id":"plot","owner_company_id":"owner","rect_m":[0,0,16,8]}],
		"placements":[],"stores":[],"vessels":[],"reservations":[],"water_regions":[],"revision":0,"receipts":{}}

func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok: failures.append(description)
