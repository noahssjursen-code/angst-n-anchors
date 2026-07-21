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

`player` contains identity, the company aggregate, the compatibility marks balance,
lifetime stats, appearance, owned and active vessels, home port id, accepted
contracts, world-clock hours, tutorial flags, and starter-vessel state. Vector
values inside JSON are arrays.

## Company aggregate (v6)

`player.company` is the JSON-safe authority record for company identity, branding,
home port, account ledger, inventory lots, warehouse leases, processed request ids,
and onboarding state. `player.marks` remains as a compatibility mirror while older
HUD/gameplay call sites migrate; `company.account.balance_marks` is authoritative.

Company mutations use explicit command/result contracts through `CompanyService`.
Processed request ids make opening-company and money commands idempotent so the same
boundary can later be hosted by a multiplayer server.

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
- v6 added company identity, an immutable money ledger, starter warehouse lease,
  inventory-lot contracts, onboarding state, and idempotency records. Existing
  captains migrate their current balance and fleet without receiving a new vessel.
- Multi-captain folders + `index.json` are additive; legacy single-file saves migrate automatically.

`PlayerData.from_dict()` supplies defaults for missing fields, so old envelopes
upgrade on the next successful save. Flat legacy player dictionaries are still
wrapped into the current envelope by `PlayerSaveStore`.
