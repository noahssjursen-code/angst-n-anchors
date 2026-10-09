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

### Opt-in passenger sailings

`company.passenger_sailings` is an optional array (absent means empty) used by the
local passenger-service development slice. This is additive to v6 and preserves
older captain data. `PassengerService` owns mutations; rendered passengers do not.
Each record stores `id`, `route_id`, `vessel_uid`, `origin_berth`,
`destination_berth`, `total`, `onboard`, `landed`, `returned`, `seat_ids`,
`seat_positions` (vessel-local XYZ arrays), `seat_yaws`, `fare_marks`, `phase` and
`paid_marks`. Positions and mass survive temporarily missing fit-out seats.

Phases are boarding, ready, underway, alighting, completed, returning or cancelled.
Completed and cancelled records are retained for idempotency. Fares use the
existing account ledger with request ID `passenger-fare:<sailing id>`; the ledger
is the durable receipt beyond the bounded processed-request cache. A quarter-second
vessel component reconstructs mass and crowd presentation from the manifest.

The isolated journey test verifies scratch save/reload and rebuilding a vessel
from its owned record. Production route/terminal registration and restoration of
a live passenger voyage after a normal world load remain pending; the test's
retained vessel pose is a fixture, not a changed deployment/save policy.

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

## Development captain (9 October 2026)

Singleplayer -> Development captain / all ships creates or reopens a separate
local captain. All valid ready-built catalog entries plus explicitly registered
review vessels are granted through the normal owned-vessel ledger. Current fleet:
Harbour Cargo, Coastal Bulk, Coastal Freighter, Northline 40, Coastal Trawler,
and Coastal Express. No normal captain is upgraded to development implicitly.

The optional company.development_captain flag opts in; company.development_fleet
maps stock IDs to granted vessel UIDs. Loading this captain grants newly added
catalog entries once. Existing owned records, names, paint, active selection and
runtime state are retained. Stock updates do not overwrite saved customizations.
Future yard stock is discovered automatically from PrebuiltVesselCatalog; review
arrangements not yet for sale are registered in DevelopmentFleet.REVIEW_RECIPES.
Normal company normalization preserves these optional JSON-safe fields; no save
version migration is required. This is a local development facility, not an
online account or a change to normal purchase/authority rules.

Verification: tests/development_captain_test.tscn -- --shipyard-playtest exercises
the real title button, isolated creation, disk roundtrip, reload/new-stock grants,
customization retention and byte-for-byte protection of another captain's save.