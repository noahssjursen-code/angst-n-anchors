# Player Save Format

Local saves use `user://save/player.json`.

```json
{
  "version": 3,
  "player": {},
  "saved_at_unix": 0
}
```

`player` contains identity, marks/lifetime stats, appearance, owned and active
vessels, home port id, accepted contracts, ship runtime state, world-clock hours,
tutorial flags, and starter-vessel state. Vector values inside JSON are arrays.

## Home port

`home_port_id` selects which coastal quay is named `HomePort` on world load.
New captains pick it from a chart after character creation. Defaults to
`port-home` for legacy saves.

## Ship runtime resume

When `ship_runtime_state` is non-empty and the world context matches,
`LocalPlayerView` respawns the active vessel at the saved pose and places the
captain on deck (optionally resuming helm). Empty runtime means the captain
starts on the home quay with no hull in the water — deploy via the harbour
master.

```json
{
  "world_pos": [x, y, z],
  "yaw": 0.0,
  "throttle_stage_idx": 1,
  "fuel_fraction": 1.0,
  "aboard": true,
  "helming": false
}
```

## World context (v3)

Coordinate-bearing state is associated with:

```json
{
  "world_context": {
    "seed": 42,
    "generation_version": 1,
    "layout_checksum": "sha256..."
  }
}
```

`LocalPlayerView` restores accepted contracts and ship coordinates only when
the current generated world matches this identity. Marks, appearance, and the
owned-vessel ledger are not world-local and remain available. Legacy saves with
no context are accepted once and adopt the current context on their next save.

## Compatibility

- v1 lacked runtime contract/ship/time snapshots.
- v2 added accepted contracts, ship runtime state, and world-clock hours.
- v3 added generated-world identity.

`PlayerData.from_dict()` supplies defaults for missing fields, so old envelopes
upgrade on the next successful save. Flat legacy player dictionaries are still
wrapped into the current envelope by `PlayerSaveStore`.
