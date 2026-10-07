class_name ImpostorWarmup
extends RefCounted

## Boot-time bake of port structure impostors so far LODs can stamp cheaply.
## Call from World while LoadingGate is still up.

const IMPOSTOR_CACHE := preload("res://scripts/core/impostor_cache.gd")
const PROVISION_CRANE_SCRIPT := preload("res://scripts/port/provision_crane.gd")
const BULK_CRANE_SCRIPT := preload("res://scripts/port/bulk_crane.gd")
const BAKE_RESOLUTION := 128


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


static func warm_buildings(host: Node, status_cb: Callable = Callable()) -> void:
	var ids := BuildingBlueprintCatalog.ids()
	var i := 0
	for blueprint_id in ids:
		i += 1
		var key := building_key(blueprint_id)
		if IMPOSTOR_CACHE.has_key(key):
			continue
		_status(status_cb, "Baking building impostors (%d/%d)…" % [i, ids.size()])
		var layout := BuildingBlueprintCatalog.by_id(blueprint_id)
		if layout == null:
			continue
		var node := BuildingCache.instance(layout, false)
		if node == null:
			continue
		host.add_child(node)
		await host.get_tree().process_frame
		await host.get_tree().process_frame
		await IMPOSTOR_CACHE.bake_from_node(host, key, node, BAKE_RESOLUTION)
		node.free()
		await host.get_tree().process_frame


static func warm_land_houses(host: Node, status_cb: Callable = Callable()) -> void:
	for variant in range(LandDecorCache.VARIANT_COUNT):
		var key := land_house_key(variant)
		if IMPOSTOR_CACHE.has_key(key):
			continue
		_status(status_cb, "Baking house impostors (%d/%d)…" % [variant + 1, LandDecorCache.VARIANT_COUNT])
		# u=v=0 and index=variant → variant_index resolves to variant.
		var node := LandDecorCache.house_instance(variant, 0.0, 0.0)
		host.add_child(node)
		await host.get_tree().process_frame
		await IMPOSTOR_CACHE.bake_from_node(host, key, node, BAKE_RESOLUTION)
		node.free()
		await host.get_tree().process_frame


static func warm_cranes(host: Node, status_cb: Callable = Callable()) -> void:
	# Offline Blender proxies carry real silhouette/depth and live lighting.
	# No six-view crane viewport baking on game startup.
	if ResourceLoader.exists("res://resources/models/scenery/port_distance/provision_distance.glb") and ResourceLoader.exists("res://resources/models/scenery/port_distance/bulk_distance.glb"):
		return
	var kinds := ["provision", "bulk"]
	var i := 0
	for kind in kinds:
		i += 1
		var key := crane_key(kind)
		if IMPOSTOR_CACHE.has_key(key):
			continue
		_status(status_cb, "Baking crane impostors (%d/%d)…" % [i, kinds.size()])
		var node := _build_crane_bake_source(kind)
		if node == null:
			continue
		host.add_child(node)
		await host.get_tree().process_frame
		await host.get_tree().process_frame
		await host.get_tree().process_frame
		await IMPOSTOR_CACHE.bake_from_node(host, key, node, BAKE_RESOLUTION)
		node.free()
		await host.get_tree().process_frame


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
			return bulk
		_:
			return null


static func _status(cb: Callable, text: String) -> void:
	if cb.is_valid():
		cb.call(text)
