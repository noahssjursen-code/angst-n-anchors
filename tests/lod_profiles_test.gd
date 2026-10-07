extends Node

## Run the scene with --headless -- --shipyard-playtest, not --script.
## Autoload dependencies must exist before compiling the LOD service.
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _ready() -> void:
	if not ShipyardPlaytestMode.active():
		push_error("LOD test requires isolated --shipyard-playtest")
		get_tree().quit(1)
		return
	call_deferred("run")

func run() -> void:
	LodProfiles.reload()
	var service := get_node("/root/LodService")
	check(service != null, "LOD autoload must exist")
	if service == null:
		get_tree().quit(1)
		return
	check(service.tier_at(100, &"default", 1, "missing") == service.Tier.DETAILED, "Near detail")
	check(service.tier_at(500, &"default", 1, "missing") == service.Tier.DETAILED, "Missing proxy keeps detail")
	check(service.tier_at(2250, &"default", 1, "missing", service.Tier.DETAILED) == service.Tier.DETAILED, "Missing proxy hysteresis")
	check(service.tier_at(2400, &"default", 1, "missing", service.Tier.DETAILED) == service.Tier.CULLED, "Missing proxy culls")
	for key in ["crane:provision", "crane:bulk"]:
		check(ImpostorService.has_key(key), "Imported crane proxy must exist: " + key)
		check(service.tier_at(700, &"tall", 1, key, service.Tier.DETAILED) == service.Tier.DETAILED, "Detailed downgrade grace")
		check(service.tier_at(721, &"tall", 1, key, service.Tier.DETAILED) == service.Tier.IMPOSTOR, "Detailed downgrade")
		for distance in [4300, 5600, 7800, 8160]:
			check(service.tier_at(distance, &"tall", 1, key, service.Tier.IMPOSTOR) == service.Tier.IMPOSTOR, "Crane range including downgrade grace")
		check(service.tier_at(8161, &"tall", 1, key, service.Tier.IMPOSTOR) == service.Tier.CULLED, "Crane cull boundary")
		check(service.tier_at(8050, &"tall", 1, key, service.Tier.CULLED) == service.Tier.CULLED, "No early reappearance")
		check(service.tier_at(8000, &"tall", 1, key, service.Tier.CULLED) == service.Tier.IMPOSTOR, "Crane reappears on approach")
		check(service.tier_at(560, &"tall", 1, key, service.Tier.IMPOSTOR) == service.Tier.DETAILED, "Detail returns on approach")
	# Exercise actual scene ownership and repeated swaps, not just distance math.
	var camera := Camera3D.new()
	add_child(camera)
	camera.current = true
	camera.position = Vector3(0, 0, 100)
	var initial_entries: int = service._entries.size()
	var host := PortStructureLod.new()
	add_child(host)
	host.setup("crane:provision", func() -> Node3D: return Node3D.new(), PortStructureLod.PROFILE_TALL)
	for distance in [100, 900, 8400, 7800, 100, 900, 8400]:
		camera.position.z = distance
		service._tick()
		var tier: int = service.current_tier(host._handle)
		var expected: int = service.Tier.DETAILED if distance == 100 else (service.Tier.CULLED if distance == 8400 else service.Tier.IMPOSTOR)
		check(tier == expected, "Actual camera-driven tier at " + str(distance))
		check(host.get_child_count() == (0 if expected == service.Tier.CULLED else 1), "No leftover visual after tier swap")
	host.free()
	check(service._entries.size() == initial_entries, "Host destruction unregisters its LOD entry")
	camera.free()
	if OS.get_cmdline_user_args().has("--verify-failure-exit"):
		check(false, "Intentional harness failure")
	if failures == 0: print("lod_profiles_test: PASS (ranges, hysteresis, repeated scene swaps, cleanup)")
	else: print("lod_profiles_test: FAIL ", failures)
	get_tree().quit(0 if failures == 0 else 1)
