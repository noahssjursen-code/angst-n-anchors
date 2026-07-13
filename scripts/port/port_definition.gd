class_name PortDefinition
extends RefCounted

## Lean port record — the only thing that needs to be seeded, stored, or networked.
## Everything else is derived locally by PortExpander.

enum RegionKind { LEGACY_ISLAND, MAINLAND, FJORD, ARCHIPELAGO }
enum GroundMode { LOCAL_ISLAND, WORLD_TERRAIN }

var port_id:        String  = ""
var display_name:   String  = ""
var world_position: Vector3 = Vector3.ZERO
var size:           int     = 1   ## 0 (small landing) → 4 (large industrial port)
var has_lighthouse: bool    = false
var has_fog_horn:   bool    = false
## Coast placement owns yaw when true. Local -Z must face navigable water.
var rotation_y:            float = 0.0
var has_explicit_rotation: bool = false
var region_kind:           RegionKind = RegionKind.LEGACY_ISLAND
var ground_mode:           GroundMode = GroundMode.LOCAL_ISLAND


func to_dict() -> Dictionary:
	return {
		"port_id":        port_id,
		"display_name":   display_name,
		"world_position": { "x": world_position.x, "y": world_position.y, "z": world_position.z },
		"size":           size,
		"has_lighthouse": has_lighthouse,
		"has_fog_horn":   has_fog_horn,
		"rotation_y": rotation_y,
		"has_explicit_rotation": has_explicit_rotation,
		"region_kind": int(region_kind),
		"ground_mode": int(ground_mode),
	}


static func from_dict(d: Dictionary) -> PortDefinition:
	var p          := PortDefinition.new()
	p.port_id      = str(d.get("port_id",      ""))
	p.display_name = str(d.get("display_name", ""))
	var wp         := d.get("world_position", {}) as Dictionary
	p.world_position = Vector3(
		float(wp.get("x", 0.0)),
		float(wp.get("y", 0.0)),
		float(wp.get("z", 0.0)),
	)
	p.size = int(d.get("size", 1))
	p.has_lighthouse = bool(d.get("has_lighthouse", false))
	p.has_fog_horn   = bool(d.get("has_fog_horn",   false))
	p.rotation_y = float(d.get("rotation_y", 0.0))
	p.has_explicit_rotation = bool(d.get("has_explicit_rotation", d.has("rotation_y")))
	p.region_kind = clampi(
		int(d.get("region_kind", PortDefinition.RegionKind.LEGACY_ISLAND)),
		PortDefinition.RegionKind.LEGACY_ISLAND,
		PortDefinition.RegionKind.ARCHIPELAGO,
	) as PortDefinition.RegionKind
	p.ground_mode = clampi(
		int(d.get("ground_mode", PortDefinition.GroundMode.LOCAL_ISLAND)),
		PortDefinition.GroundMode.LOCAL_ISLAND,
		PortDefinition.GroundMode.WORLD_TERRAIN,
	) as PortDefinition.GroundMode
	return p
