class_name PortDataCache
extends RefCounted

## Dedupes `PortExpander.expand()` during world boot and lazy port loads.
## Keyed by port identity + world seed + layout checksum + optional expand attrs.

static var _cache: Dictionary = {}


static func clear() -> void:
	_cache.clear()


static func expand(
		definition: PortDefinition,
		world_seed: int,
		world_layout: WorldLayout = null,
		extra_attributes: Dictionary = {},
) -> PortData:
	var key := _cache_key(definition, world_seed, world_layout, extra_attributes)
	if _cache.has(key):
		return _cache[key] as PortData
	var data := PortExpander.expand_uncached(
		definition,
		world_seed,
		world_layout,
		extra_attributes,
	)
	_cache[key] = data
	return data


static func _cache_key(
		definition: PortDefinition,
		world_seed: int,
		world_layout: WorldLayout,
		extra_attributes: Dictionary,
) -> String:
	var layout_checksum := ""
	if world_layout != null:
		layout_checksum = str(world_layout.layout_checksum)
	var site_seed := definition.site_seed if definition.site_seed != 0 \
			else world_seed ^ definition.port_id.hash()
	var attrs_hash := extra_attributes.hash() if not extra_attributes.is_empty() else 0
	return "%s|%d|%d|%d|%s|%d|%d|%d|%d" % [
		definition.port_id,
		world_seed,
		site_seed,
		definition.port_generation_version,
		layout_checksum,
		definition.size,
		definition.site_max_size,
		int(definition.region_kind),
		attrs_hash,
	]
