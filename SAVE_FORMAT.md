# Player Save Format

Local saves use a multi-captain roster under `user://save/`.

```
user://save/
  index.json
  captains/{account_id}/
    player.json
    player.json.bak
    vessels/{uid}.json
```

## Index (`index.json`)

```json
{
  "version": 1,
  "captains": [
    {
      "id": "uuid",
      "display_name": "Captain",
      "home_port_id": "port-home",
      "world_seed": 123456,
      "last_played_unix": 0,
      "marks": 0
    }
  ]
}
```

## Captain envelope (`captains/{id}/player.json`)

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

## Migration

A legacy single-slot `user://save/player.json` is moved into
`captains/{account_id}/` on first boot by `LocalCaptainStore`. Matching vessel
archives under `user://save/vessels/` move with that captain.

## Home port

`home_port_id` selects which coastal quay is named `HomePort` on world load.
New captains pick it from a chart after character creation. Defaults to
`port-home` for legacy saves.

## Ship deployment state

Loading a captain always starts them on foot at their home quay with no hull in
the water. Their active vessel remains in the ownership ledger and is deployed
normally through the harbour master. New saves omit `ship_runtime_state`; old
runtime coordinates, vessel state, boarding state, and helm state are ignored.

## World context (v3)

Each singleplayer captain owns a world seed. New captains roll a fresh seed via
`WorldBootstrap.roll_seed()` before home-port selection. Continue hydrates
`GameSettings` from that captain's context before world load.

```json
{
  "world_context": {
    "seed": 123456,
    "generation_version": 1,
    "weather_generation_version": 3,
    "layout_checksum": "sha256..."
  }
}
```

`LocalPlayerView` restores accepted contracts and ship coordinates only when
the current generated world matches this identity. Marks, appearance, and the
owned-vessel ledger are not world-local and remain available. Legacy saves with
no context are accepted once and adopt the current context on their next save.

Multiplayer worlds take `world_seed`, `generation_version`, and
`weather_generation_version` from the server (`GET /v1/world-options`).

## Compatibility

- v1 lacked runtime contract/ship/time snapshots.
- v2 added accepted contracts, ship runtime state, and world-clock hours.
  Ship runtime state is now ignored.
- v3 added generated-world identity.
- Multi-captain folders + `index.json` are additive; legacy single-file saves migrate automatically.

`PlayerData.from_dict()` supplies defaults for missing fields, so old envelopes
upgrade on the next successful save. Flat legacy player dictionaries are still
wrapped into the current envelope by `PlayerSaveStore`.
