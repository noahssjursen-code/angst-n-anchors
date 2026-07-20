extends SceneTree

const PRESENTATION_POLICY := preload(
	"res://scripts/traffic/traffic_vessel_presentation_policy.gd")


func _initialize() -> void:
	var records: Array[Dictionary] = []
	for index in range(50):
		records.append({"id": "vessel-%03d" % index,
			"position": Vector2(float(index % 10) * 200.0, float(index / 10) * 200.0)})
	var near: Dictionary = PRESENTATION_POLICY.select(
		records, Vector2.ZERO, 650.0, 1400.0, 4)
	assert((near.get("full_ids", PackedStringArray()) as PackedStringArray).size() == 4)
	assert(int(near.get("record_count", 0)) == 50)
	assert(int(near.get("data_only_count", 0)) > 0)
	var repeated: Dictionary = PRESENTATION_POLICY.select(
		records, Vector2.ZERO, 650.0, 1400.0, 4)
	assert(repeated == near)
	var moved: Dictionary = PRESENTATION_POLICY.select(
		records, Vector2(1800.0, 800.0), 650.0, 1400.0, 4)
	assert((moved.get("full_ids", PackedStringArray()) as PackedStringArray).size() == 4)
	assert(moved.get("full_ids", PackedStringArray()) != near.get("full_ids", PackedStringArray()))
	var tiered: Dictionary = PRESENTATION_POLICY.select(
		records, Vector2.ZERO, 650.0, 1400.0, 6, 260.0, 2, 8)
	assert((tiered.get("physics_ids", PackedStringArray()) as PackedStringArray).size() == 2)
	assert((tiered.get("full_ids", PackedStringArray()) as PackedStringArray).size() == 6)
	assert((tiered.get("proxy_ids", PackedStringArray()) as PackedStringArray).size() == 8)
	assert(int(tiered.get("data_only_count", 0)) == 36)
	print("Traffic vessel presentation policy: deterministic physics/full/proxy budgets PASS")
	quit(0)
