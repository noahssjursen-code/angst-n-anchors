class_name PortDefinition
extends RefCounted

## Lean port record — the only thing that needs to be seeded, stored, or networked.
## Everything else is derived locally by PortExpander.

var port_id:        String  = ""
var display_name:   String  = ""
var world_position: Vector3 = Vector3.ZERO
var size:           int     = 1   ## 0 (small landing) → 4 (large industrial port)


func to_dict() -> Dictionary:
	return {
		"port_id":        port_id,
		"display_name":   display_name,
		"world_position": { "x": world_position.x, "y": world_position.y, "z": world_position.z },
		"size":           size,
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
	return p
