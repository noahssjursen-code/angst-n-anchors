class_name ImpostorService
extends RefCounted

## Thin façade over ImpostorCache + ImpostorWarmup for LodService consumers.

const IMPOSTOR_CACHE := preload("res://scripts/core/impostor_cache.gd")
const IMPOSTOR_WARMUP := preload("res://scripts/core/impostor_warmup.gd")


static func has_key(key: String) -> bool:
	return IMPOSTOR_CACHE.has_key(key)


static func stamp(key: String, show_ghost: bool = false) -> Node3D:
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
