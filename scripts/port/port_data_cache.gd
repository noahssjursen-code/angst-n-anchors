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
	## `expand_uncached` RESOLVES the definition in place: it clamps `size` and
	## writes back `site_max_size` (`port_expander.gd` ~:131-153), and both are
	## part of the key above. So `key` describes the REQUEST as it arrived and
	## the same definition object can never produce it again — a fresh
	## definition defaults `site_max_size` to 8 and comes back holding 4, so the
	## first expansion of every port was a miss stored under a key nothing would
	## ever look up, and the caller got a second full expansion. Register the
	## resolved key against the same PortData so the request and its resolution
	## are one cache entry's worth of work.
	var resolved_key := _cache_key(definition, world_seed, world_layout, extra_attributes)
	if resolved_key != key:
		_cache[resolved_key] = data
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
