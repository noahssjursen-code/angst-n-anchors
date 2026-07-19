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
	print("Traffic vessel presentation policy: 50 records, deterministic 4-full budget PASS")
	quit(0)
