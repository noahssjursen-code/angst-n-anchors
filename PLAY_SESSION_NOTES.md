# Play Session Notes & Bug Diagnostics — May 22, 2026

It's fantastic that the exported executable works, you and your friend are successfully in-game playing together! Below are the diagnostics, root causes, and fixes for the two bugs reported during your play session.

---

## 1. Crane Interaction Bug: Losing "F to enter" Prompt
* **Symptom**: Cranes cannot be entered more than 1 or 2 times without losing the `F` interaction prompt.
* **Scope**: Local bug (interaction range check).

### Root Cause
In `scripts/port/gantry_crane.gd`, the function `_nearest_boardable_player()` determines if a player is close enough to enter/operate the crane:

```gdscript
func _nearest_boardable_player() -> CharacterBody3D:
	if not _remotely_operated_by.is_empty():
		return null
	for node in get_tree().get_nodes_in_group("player"):
		var body := node as CharacterBody3D
		if body != null and global_position.distance_to(body.global_position) <= board_range_m:
			return body
	return null
```

* The crane is a gantry crane. Its root node (where `global_position` resides) is a static point on the dock where the crane tracks start.
* When you board the crane and operate it, you move the gantry frame along the X-axis (`_gantry_x_offset`) and the trolley along the Z-axis (`_trolley_z`).
* When you exit the crane, the player is dropped right next to the moving cabin/gantry:
  ```gdscript
  _player.global_position = to_global(Vector3(_gantry_x_offset + 4.0, 0.0, 4.0))
  ```
* **The Bug**: Since `_nearest_boardable_player()` checks the distance between the player and the crane's *static root* (`global_position`) rather than the *moving gantry frame* (`_gantry_frame.global_position`), as soon as you roll the crane more than `board_range_m` (7.0 meters) away from its starting center point, the player on exit is dropped outside of the static root's 7.0-meter radius. Consequently, the game thinks you are too far away, and the "F to enter" prompt disappears forever!

### Fix
Modify `_nearest_boardable_player()` to measure proximity relative to the moving `_gantry_frame` instead of the static root:
```gdscript
func _nearest_boardable_player() -> CharacterBody3D:
	if not _remotely_operated_by.is_empty():
		return null
	var center_pos := global_position
	if _gantry_frame != null:
		center_pos = _gantry_frame.global_position
	for node in get_tree().get_nodes_in_group("player"):
		var body := node as CharacterBody3D
		if body != null and center_pos.distance_to(body.global_position) <= board_range_m:
			return body
	return null
```

---

## 2. Multiplayer Ship Rendering Bug: Cargo renders, but Remote Ships do not
* **Symptom**: Other players' ships do not render at all, but their cargo decks and cargo pallets successfully replicate and float in mid-air.
* **Scope**: Multiplayer replication bug.

### Root Cause
1. **Manual Spawning vs. Auto-restored Spawning**: In multiplayer, a ship's network replication is initiated by `NetworkManager.register_ship_spawn()`. This method registers the ship in `_local_ships`, binds enter/exit signals, and broadcasts spawn and transform packets.
2. **The Disconnect**:
   * If a player spawns a ship manually via the Shipwright or Harbour Master NPCs, `register_ship_spawn` is successfully called.
   * However, when a player boots up the game, the world-loader automatically spawns their last active/saved vessel on startup using `PortDock.spawn_player_ship()`. 
   * **The Bug**: `PortDock.spawn_player_ship()` has no knowledge of the network layer and never calls `NetworkManager.register_ship_spawn()`. 
3. **The Result**: Because the active vessel spawned at startup is never registered to the `NetworkManager`, the local client never tells the server or other players that their ship exists! The other players receive cargo replication updates (since cargo components bind to the world/cargo state independently), making the cargo float in mid-air on other clients while the ship hull remains invisible.

### Fix
Add an automatic active-ship detector to `NetworkManager`'s tick loop (`_tick_local_ship_outbound()`). If an active player ship exists in the world scene but hasn't been registered on the network yet, the `NetworkManager` will dynamically detect, register, and replicate it:

```gdscript
func _tick_local_ship_outbound(delta: float) -> void:
	# Automatically detect and register any auto-spawned or restored local active vessel
	var active_node := PlayerVessel.find_active_ship(get_tree())
	if active_node != null and is_instance_valid(active_node):
		var session := get_node_or_null("/root/PlayerSession")
		if session != null and session.get("data") != null:
			var pdata = session.get("data")
			if pdata != null and not pdata.active_vessel.is_empty():
				var ship_id := str(pdata.active_vessel.get("uid", ""))
				var hull_id := str(pdata.active_vessel.get("hull_id", ""))
				if not ship_id.is_empty() and not hull_id.is_empty():
					if not _local_ships.has(ship_id):
						register_ship_spawn(ship_id, hull_id, active_node)
```
This ensures that any ship restored on startup immediately begins broadcasting spawn and positional packet updates to other players!
