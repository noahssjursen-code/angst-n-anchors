class_name ImpostorService
extends RefCounted

## Thin façade over ImpostorCache + ImpostorWarmup for LodService consumers.

const IMPOSTOR_CACHE := preload("res://scripts/core/impostor_cache.gd")
const IMPOSTOR_WARMUP := preload("res://scripts/core/impostor_warmup.gd")
const CRANE_PROXIES := {
	"crane:provision": "res://resources/models/scenery/port_distance/provision_distance.glb",
	"crane:bulk": "res://resources/models/scenery/port_distance/bulk_distance.glb",
}


static func has_key(key: String) -> bool:
	if CRANE_PROXIES.has(key): return ResourceLoader.exists(CRANE_PROXIES[key])
	if key.begins_with("building:") or key.begins_with("land_house:"):
		return IMPOSTOR_CACHE.has_geometry(key)
	return IMPOSTOR_CACHE.has_key(key)


static func stamp(key: String, show_ghost: bool = false) -> Node3D:
	if CRANE_PROXIES.has(key):
		var proxy := (load(CRANE_PROXIES[key]) as PackedScene).instantiate() as Node3D
		for mesh: MeshInstance3D in proxy.find_children("*","MeshInstance3D",true,false):
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		return proxy
	if (key.begins_with("building:") or key.begins_with("land_house:")) and not IMPOSTOR_CACHE.has_geometry(key):
		return Node3D.new()
	return IMPOSTOR_CACHE.instance(key, show_ghost) as Node3D


static func clear() -> void:
	IMPOSTOR_CACHE.clear()


static func bake(
		host: Node,
		key: String,
		source: Node3D,
		resolution: int = 128,
) -> void:
	await IMPOSTOR_CACHE.bake_from_node(host, key, source, resolution)


static func warm_catalog(host: Node, status_cb: Callable = Callable()) -> void:
	await IMPOSTOR_WARMUP.warm_all(host, status_cb)


static func building_key(blueprint_id: String) -> String:
	return IMPOSTOR_WARMUP.building_key(blueprint_id)


static func land_house_key(variant: int) -> String:
	return IMPOSTOR_WARMUP.land_house_key(variant)


static func crane_key(kind: String) -> String:
	return IMPOSTOR_WARMUP.crane_key(kind)
