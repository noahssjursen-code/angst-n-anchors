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
  "version": 6,
  "player": {},
  "saved_at_unix": 0
}
```

`player` contains identity, marks/lifetime stats, appearance, owned and active
vessels, home port id, accepted contracts, ship runtime state, world-clock hours,
tutorial flags, and legacy starter-vessel state. New captains begin with an
empty vessel registry. Vector values inside JSON are arrays.

Save v6 adds `company_state`: the company name, named employees and hourly
wages, vessel-to-crew route assignments, bounded finance ledger, and
`last_simulated_unix`. These are authority data only. Physical workers and NPC
ships are reconstructed projections, so the same record can later be stored on
an authoritative multiplayer server.

Underway dormant location is reconstructed from the assigned berth endpoints,
sea-route algorithm, leg timestamps, and current wall-clock time. That position
is only the initial condition when a vessel enters local simulation. From then
until it leaves interest, ordinary BoatBody physics and the autonomous captain
own movement. On interest exit, real autopilot progress is folded back into the
dormant timestamps so a later reconstruction continues from the correct point.

The deterministic voyage profile uses crab-speed clearance at each quay,
harbour speed through approach lanes, and passage speed offshore. Thus clients
reconstruct both the same sea path and the same point along it from timestamps.

Company assignment rows also persist their operational phase (`preparing`,
`underway`, `turnaround`, `inactive`, or `unpaid`), current route leg, crew,
payroll totals, cargo-operation tokens, and a JSON-safe cargo manifest. General
cargo stores the exact serialized `ContainerUnit` rows; bulk cargo stores each
hold's `BulkHoldState`. Tokens and manifests are authority data, not scene nodes:
nearby ships, mooring lines, yard containers, and crane jobs are rebuilt from the
assignment when that harbour enters client interest.
If no client is present, a bounded deterministic turnaround completes the same
leg without simulating physical cargo. A departure timestamp is never issued
until either the local crane flow or that abstract turnaround has completed.
Freight revenue settles at that unload boundary; merely reaching the destination
timestamp does not credit the company.

Maritime traffic intents, collision agreements, route-block leases, and port
arrival queues are world/server authority state rather than captain-save state.
They are JSON-safe snapshots replicated with the live world and are rebuilt as
vessels re-enter interest. Company assignment and cargo records remain durable;
short-lived traffic leases do not survive a server restart.

## Migration

A legacy single-slot `user://save/player.json` is moved into
`captains/{account_id}/` on first boot by `LocalCaptainStore`. Matching vessel
archives under `user://save/vessels/` move with that captain.

Save v4 adds `registration_id` to every owned-vessel ledger row. Legacy rows
without a declaration migrate to `review_required` and cannot deploy until they
pass a shipyard registration/refit audit. Registration compliance is recomputed
from the current legal-code catalog and brick layout; no certification boolean is
persisted.

Save v5 previously stored `port_operations_state` (vessel calls / yard ledger).
That field is currently cleared on snapshot and ignored on restore. First Freight
persists the complete accepted movement dictionary in `accepted_contracts`.
Physical in-transit cargo is not restored yet, so a resumed movement returns
to `accepted` with `loaded_count = 0` and must be loaded again.

## Home port

`home_port_id` selects which coastal quay is named `HomePort` on world load.
New captains pick it from a chart after character creation. Defaults to
`port-home` for legacy saves.

## Ship deployment state

Loading a captain always starts them on foot at their home quay with no hull in
the water. Their active vessel remains in the ownership ledger and is deployed
through vessel spawn / future shipyard UI. New saves omit `ship_runtime_state`; old
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

`LocalPlayerView` restores accepted freight movements only when
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
- v4 added vessel registration declarations.
- v5 added vessel-call and port-yard cargo state (legacy unitized packing removed; containers/pads are layout-driven, not saved as in-flight pallets).
- v6 added deterministic company, employee, payroll, and autonomous fleet state.
- Multi-captain folders + `index.json` are additive; legacy single-file saves migrate automatically.

`PlayerData.from_dict()` supplies defaults for missing fields, so old envelopes
upgrade on the next successful save. Flat legacy player dictionaries are still
wrapped into the current envelope by `PlayerSaveStore`.
