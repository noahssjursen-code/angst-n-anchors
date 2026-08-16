class_name PlayerState
extends RefCounted

signal marks_changed(balance: int)
signal display_name_changed(name: String)

var marks: int = 0:
	set(v):
		marks = v
		marks_changed.emit(v)

var display_name: String = "Captain":
	set(v):
		display_name = v
		display_name_changed.emit(v)

## `current_port_id` was declared here and NEVER WRITTEN AND NEVER READ, by
## anything, in the whole repository — deleted 2026-08-16. The player's port
## context is answered by two live seams instead:
## `GameState.world.nearest_port_id` (PortProximity, proximity) and
## `LocalPlayerView.get_active_ship_berth_context()` (the moored berth). A third
## field that nothing maintained could only ever have been read as stale.
