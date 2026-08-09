extends SceneTree

const TestReport := preload("res://tests/support/test_report.gd")
const PRESENTATION_POLICY := preload(
	"res://scripts/traffic/traffic_vessel_presentation_policy.gd")


func _initialize() -> void:
	var t := TestReport.new("traffic_vessel_presentation_policy_test")
	var records: Array[Dictionary] = []
	for index in range(50):
		records.append({"id": "vessel-%03d" % index,
			"position": Vector2(float(index % 10) * 200.0, float(index / 10) * 200.0)})
	var near: Dictionary = PRESENTATION_POLICY.select(
		records, Vector2.ZERO, 650.0, 1400.0, 4)
	t.equal(
		"full budget is honoured",
		(near.get("full_ids", PackedStringArray()) as PackedStringArray).size(),
		4,
	)
	t.equal("every record is accounted for", int(near.get("record_count", 0)), 50)
	t.check("records beyond the budgets fall back to data only", int(near.get("data_only_count", 0)) > 0)
	var repeated: Dictionary = PRESENTATION_POLICY.select(
		records, Vector2.ZERO, 650.0, 1400.0, 4)
	t.equal("selection is deterministic for an unchanged viewer", repeated, near)
	var moved: Dictionary = PRESENTATION_POLICY.select(
		records, Vector2(1800.0, 800.0), 650.0, 1400.0, 4)
	t.equal(
		"full budget is honoured after the viewer moves",
		(moved.get("full_ids", PackedStringArray()) as PackedStringArray).size(),
		4,
	)
	t.not_equal(
		"a moved viewer selects different vessels",
		moved.get("full_ids", PackedStringArray()),
		near.get("full_ids", PackedStringArray()),
	)
	var tiered: Dictionary = PRESENTATION_POLICY.select(
		records, Vector2.ZERO, 650.0, 1400.0, 6, 260.0, 2, 8)
	t.equal(
		"physics budget is honoured",
		(tiered.get("physics_ids", PackedStringArray()) as PackedStringArray).size(),
		2,
	)
	t.equal(
		"tiered full budget is honoured",
		(tiered.get("full_ids", PackedStringArray()) as PackedStringArray).size(),
		6,
	)
	t.equal(
		"proxy budget is honoured",
		(tiered.get("proxy_ids", PackedStringArray()) as PackedStringArray).size(),
		8,
	)
	t.equal("remaining vessels stay data only", int(tiered.get("data_only_count", 0)), 36)
	t.finish(self)
