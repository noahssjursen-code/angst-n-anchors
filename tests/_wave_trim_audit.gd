extends SceneTree

## SCRATCH PROBE (leading underscore, not gate-scored).
##
##   xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy \
##     --script res://tests/_wave_trim_audit.gd
##
## Resolves each critic fixture through PieceKit and prints, per placement, the
## world-space AABB of the plates it draws, so "a spar runs past the stem" can be
## answered in metres instead of pixels.

const PieceKitScript := preload("res://scripts/construction/piece_kit.gd")

const FIXTURES := [
	"res://resources/data/structures/critic_yacht.json",
	"res://resources/data/structures/critic_barge.json",
	"res://resources/data/structures/critic_ferry.json",
]


func _init() -> void:
	for path in FIXTURES:
		_audit(path)
	quit()


func _audit(path: String) -> void:
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path)) as Dictionary
	var hull: Dictionary = doc.get("hull", {}) as Dictionary
	var loa := float(hull.get("loa_m", 0.0))
	var beam := float(hull.get("beam_m", 0.0))
	print("\n=== %s  loa=%.1f m beam=%.1f m  deck rect x 0..%.1f  z 0..%.1f"
		% [path.get_file(), loa, beam, beam, loa])

	var placements: Array = doc.get("pieces", []) as Array
	for placement_variant in placements:
		var placement := placement_variant as Dictionary
		var result := PieceKitScript.resolve_placement(placement, 1)
		for message in result["errors"] as PackedStringArray:
			print("  ERROR %s" % message)
		var box := AABB()
		var first := true
		for item_variant in result["items"] as Array:
			var item := item_variant as Dictionary
			var at_list: Array = item["at"] as Array
			var at := Vector3(float(at_list[0]), float(at_list[1]), float(at_list[2]))
			var yaw := deg_to_rad(float(item.get("yaw", 0.0)))
			var basis := Basis(Vector3.UP, yaw)
			for corner_variant in (item["props"] as Dictionary)["corners"] as Array:
				var corner_list: Array = corner_variant as Array
				var world: Vector3 = at + basis * Vector3(
					float(corner_list[0]), float(corner_list[1]), float(corner_list[2])
				)
				if first:
					box = AABB(world, Vector3.ZERO)
					first = false
				else:
					box = box.expand(world)
		if first:
			continue
		var over_bow := maxf(0.0, -box.position.z)
		var over_stern := maxf(0.0, box.position.z + box.size.z - loa)
		var over_port := maxf(0.0, -box.position.x)
		var over_stbd := maxf(0.0, box.position.x + box.size.x - beam)
		var flag := ""
		if maxf(maxf(over_bow, over_stern), maxf(over_port, over_stbd)) > 0.001:
			flag = "  OFF-DECK bow=%.3f stern=%.3f port=%.3f stbd=%.3f" % [
				over_bow, over_stern, over_port, over_stbd
			]
		print("  id=%-3s %-12s facing=%-3s  x %6.2f..%-6.2f  y %5.2f..%-5.2f  z %6.2f..%-6.2f  %s%s"
			% [
				str(placement.get("id", "?")), str(placement.get("piece", "?")),
				str(placement.get("facing", 0)),
				box.position.x, box.position.x + box.size.x,
				box.position.y, box.position.y + box.size.y,
				box.position.z, box.position.z + box.size.z,
				str(placement.get("_is", "")), flag,
			])
