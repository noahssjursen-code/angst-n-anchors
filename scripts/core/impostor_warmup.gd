class_name ImpostorWarmup
extends RefCounted

## Prepare shared 3D port distance geometry. Legacy keys remain for compatibility.
## Call from World while LoadingGate is still up.

const IMPOSTOR_CACHE := preload("res://scripts/core/impostor_cache.gd")
const PROVISION_CRANE_SCRIPT := preload("res://scripts/port/provision_crane.gd")
const BULK_CRANE_SCRIPT := preload("res://scripts/port/bulk_crane.gd")


static func building_key(blueprint_id: String) -> String:
	return "building:%s" % blueprint_id.strip_edges()


static func land_house_key(variant: int) -> String:
	return "land_house:%d" % variant


static func crane_key(kind: String) -> String:
	return "crane:%s" % kind.strip_edges()


static func warm_all(host: Node, status_cb: Callable = Callable()) -> void:
	if host == null or not host.is_inside_tree():
		return
	await warm_buildings(host, status_cb)
	await warm_land_houses(host, status_cb)
	await warm_cranes(host, status_cb)


static func warm_buildings(_host: Node, _status_cb: Callable = Callable()) -> void:
	# Retired blueprint image boxes must never return to live ports. Custom
	# saved blueprints without a mesh variant keep their detailed geometry.
	pass


static func warm_land_houses(host: Node, status_cb: Callable = Callable()) -> void:
	for variant in range(LandDecorCache.VARIANT_COUNT):
		var key := land_house_key(variant)
		if IMPOSTOR_CACHE.has_key(key):
			continue
		_status(status_cb, "Preparing distant houses (%d/%d)..." % [variant + 1, LandDecorCache.VARIANT_COUNT])
		IMPOSTOR_CACHE.register_geometry(key,LandDecorCache.house_distance_mesh(variant))



static func warm_cranes(_host: Node, _status_cb: Callable = Callable()) -> void:
	# Required offline mesh assets; never substitute baked image panels.
	for path in ImpostorService.CRANE_PROXIES.values():
		assert(ResourceLoader.exists(path), "Missing imported crane distance mesh: " + path)


static func _build_crane_bake_source(kind: String) -> Node3D:
	match kind:
		"provision":
			var provision := PROVISION_CRANE_SCRIPT.new() as ProvisionCrane
			provision.name = "ProvisionCraneBake"
			provision.rotation_degrees.y = -90.0
			return provision
		"bulk":
			var bulk := BULK_CRANE_SCRIPT.new() as BulkCrane
			bulk.name = "BulkCraneBake"
			bulk.rotation_degrees.y = -90.0
			bulk.show_operator = false
			bulk.boom_angle_deg = 38.0
			bulk.hoist_length_m = 10.0
			return bulk
		_:
			return null


static func _status(cb: Callable, text: String) -> void:
	if cb.is_valid():
		cb.call(text)
