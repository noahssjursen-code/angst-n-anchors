class_name PortData
extends RefCounted

## Expanded runtime port record. Produced by PortExpander from a PortDefinition + world seed.
## Lives in ContractRegistry for the session. Never serialized — always re-derived from the definition.

# Identity (copied from PortDefinition)
var port_id:        String  = ""
var display_name:   String  = ""
var world_position: Vector3 = Vector3.ZERO
var size:           int     = 1

# Dock layout
var dock_length:     float              = 60.0
var max_ship_class:  ShipClass.Type     = ShipClass.Type.COASTAL_TRADER
var berth_types:     Array[int]         = []   ## CargoBerthType.Type per slot
var has_fuel_point:  bool               = true

# Economy
var commodity_export:  String         = ""
var commodity_imports: Array[String]  = []

# Layout
var island_width: float = 80.0
var layout_seed:  int   = 0
var rotation_y:   float = 0.0

# Settlement
var population:  int          = 0
var features:    Array[String] = []
var berth_count: int          = 1
