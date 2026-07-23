# Multiplayer client architecture

The Godot client has one gameplay authority seam in single-player and
multiplayer. Systems express intent through `WorldGateway`; they do not decide
shared outcomes by writing scene nodes or calling HTTP directly. The matching
Go authority lives in `C:\Users\noahs\Documents\angst-n-anchors-mp`.

## Identity and captain selection

An account is the multiplayer login. Captains are game records owned by that
account.

1. `RemoteCaptainClient` registers or logs in with email/password.
2. The password exists only in the request and is immediately discarded.
3. `RemoteAccountCredentialStore` keeps the returned opaque account token in
   `user://network/account_sessions.json`, scoped by normalized server URL.
4. The server validates the cached session before displaying a roster.
5. Roster queries return only captains owned by that account.
6. Joining exchanges account proof plus the selected captain for a short-lived
   authority session used by reliable commands and UDP transforms.

Changing server or signing out clears the visible roster and active session.
There is no fallback to a captain UUID, public roster, or local save. Future
Steam/Clerk login links another identity provider to the same server account;
it does not change captain IDs or save formats.

Email/password and bearer-token traffic must use HTTPS outside localhost. The
client persists an `http_scheme` with each server configuration, so a hostname
and TLS-terminating proxy can be introduced without changing any account,
captain, save, or authority contracts. The current IP-only alpha preset remains
plain HTTP and therefore must only use disposable test credentials.

## Persistence modes

`PlayerSession` explicitly selects `LOCAL` or `REMOTE` persistence.

### Local

`LocalCaptainStore` scopes each captain under
`user://save/captains/<account_id>/`. `PlayerSaveStore` validates temporary
writes, rotates a backup, and recovers a damaged primary. Vessel archives remain
local in this mode.

### Remote

The selected captain must finish loading before the shared world is entered.
`RemotePlayerSaveClient` reads and conditionally writes `/v2/captain-state` with
an expected revision. A stale device receives a conflict and saving stops rather
than overwriting newer state.

`RemoteSaveOutbox` stages every outgoing document before network I/O. After a
crash or timeout it can distinguish:

- the request never landed, so it may retry the same revision;
- the request landed, because the server advanced exactly one revision with the
  same document;
- another writer changed the document, which becomes an explicit conflict.

The generic document contains company setup, appearance, onboarding/tutorial
state, preferences, and other not-yet-domain-owned data. It excludes
`owned_vessels`, `active_vessel`, and `ship_runtime_state`; `VesselSync` and the
server vessel records are canonical for those fields. Server profile marks also
override the compatibility copy in the document.

## Two replication planes

### Reliable authority

```text
gameplay intent
    -> WorldGateway.command(name, body, expected_revision)
    -> LocalWorldBackend or RemoteWorldBackend
    -> accepted event stream
    -> WorldProjectionStore
    -> bindings and presentation
```

- Commands have unique request IDs and may be safely retried.
- Events have a global cursor and stream-local revisions.
- Projections are queryable current-state read models.
- Interest scopes such as `port:<id>` and `entity:<id>` limit consumption.
- Reconnect resumes from the last cursor or refreshes projections after a gap.

HTTP long polling is only a delivery mechanism; WebSockets can replace it
without changing gameplay contracts.

### Loss-tolerant transforms

Positions and rotations use UDP with authenticated sessions, spatial interest,
adaptive cadence, interpolation, and shortest-arc angle handling.
`NetworkTransformBinding` is the reusable registration point for players,
vessels, and other moving presentation.

Entity lifecycle on this plane is explicit: unregistering a ship (or a sender
whose node was freed) queues a repeated `state=despawned` tombstone, and the
server removes the replica immediately (~50 ms measured) instead of waiting
for its ~12 s TTL. A ship sender's durable identity (`vid`/`lh` meta) is bound
at registration from the ship node itself — never read live from the active
vessel record, which changes during replacement.

Remote presentation dead-reckons: entities extrapolate along their last
observed velocity across the full inter-update gap (up to ~1.25 s, confidence
decaying with age), so far-band contacts glide instead of stepping.

A transform is never proof that cargo was delivered, money was earned, a berth
was acquired, or a machine operation completed.

## Runtime components

| Component | Responsibility |
|---|---|
| `WorldGateway` | Sessions, commands, interests, events, and projections |
| `LocalWorldBackend` | In-process single-player/showcase authority |
| `RemoteWorldBackend` | Account-authenticated HTTP v2 authority client |
| `WorldProjectionStore` | Revision-aware read models and signals |
| `WorldStateBinding` | Generic low-frequency shared entity state |
| `NetworkTransformBinding` | Generic high-frequency transform registration |
| `HarbourAuthorityBridge` | Accepted port-operation presentation |
| `RemoteAccountCredentialStore` | Server-scoped account session cache |
| `RemoteCaptainClient` | Account login and owned captain roster |
| `RemotePlayerSaveClient` | Revisioned captain document load/save |
| `RemoteSaveOutbox` | Crash-safe write-ahead persistence |
| `VesselSync` | Authenticated durable vessel records |

`scenes/showcases/world_authority_showcase.tscn` exercises the local authority
contract without a server.

## Automated multiplayer test suite

`scenes/showcases/mp_test_suite_showcase.tscn` runs an automated service-layer
suite against the real deployed server using in-process virtual clients that
each host the REAL service stack — a private `WorldGateway` instance over
`RemoteWorldBackend`, plus a `WireProtocol` UDP socket:

```
godot --headless --path . res://scenes/showcases/mp_test_suite_showcase.tscn
```

Append `-- --mp-server=local` to target `127.0.0.1` instead. Exit code is
non-zero on failure; a JSON report with failure forensics is written to
`user://mp_test_report.json`. `MP_BACKEND_DEBUG=1` traces event polls.

- `scripts/network/testing/virtual_client.gd` (`MpVirtualClient`) — one full
  independent client identity: account login, captain, vessels, a private
  `WorldGateway`, and UDP. Composable awaitable primitives: `await_command`,
  `await_event`, `await_projection`, `await_snapshot_entity`,
  `await_entity_absent`, `make_state_binding` (a real `WorldStateBinding`
  wired to that client's gateway), `reopen_session`.
- `scripts/network/testing/mp_test_runner.gd` (`MpTestRunner`) — scenario
  registry, assertion steps, EXPECTED_FAIL support, stdout summary + JSON
  report.
- `scripts/network/testing/mp_test_suite.gd` — 22 scenarios: presence, berth
  claim/contention/fallback, mooring replication, tombstone removal,
  silent-drop ghost TTL measurement, atomic vessel replacement,
  release/reclaim, interaction scope filtering, `WorldStateBinding` service
  round-trip with hydration idempotence, late-joiner hydration, reconnect
  resume, simultaneous-claim races, double-submit idempotency, logout-race
  recovery, simultaneous spawns, a 24-entity fleet stress pass, and a
  20-command burst with latency percentiles.

Isolation seams used by the suite (and available to future workers):
`WorldGateway.set_connection_override()` points a gateway instance at a
specific server + account token; `WorldStateBinding.set_gateway()` binds a
state component to a specific gateway. Both default to process-global behavior
so normal gameplay is unchanged.

Berth scenarios use a fictional port id (`mp-test-harness-port/...`) so live
gameplay berths are never contended, and all realtime entities spawn at a far
corner of the world outside any real player's area of interest.

Service rules the suite enforces (and that new code must respect):
- The hydrate/subscribe seam is lossless — interest changes never skip events
  (interest-epoch rescan in `RemoteWorldBackend`).
- Applying a projection is idempotent — equal revisions never re-emit
  (`WorldStateBinding`) and never re-trigger reconciliation side effects
  (`HarbourAuthorityBridge` / `HarbourController.plug_ship`).
- Projections are scope-filtered even for their author; retain the entity
  scope before hydrating (bindings do this automatically).
- UDP batches split on encoded byte size, not entity count — oversized
  datagrams are silently dropped by the server.

New networked features extend the suite with a scenario built from the same
primitives before assets adopt them.

## Stress rig

`cmd/stressbot` (server repo) drives protocol-true bot fleets against the
deployed server — scenarios: `-hotspot N` (one crowded harbour disc),
`-spread N` (clusters spaced beyond player AOI), `-ships N` (sailing loops).
Dedicated `mp-stress-*` accounts hold 32 captains each (512 identities max),
created once and reused; defaults sit in the far world corner away from
players. Example: `go run ./cmd/stressbot -hotspot 150 -spread 300 -ships 50
-duration 5m`.

`scenes/showcases/mp_stress_viewer_showcase.tscn` is the live viewer and the
only thing a human needs to run: **F6 it in the editor** — it joins as one real
observer client, auto-launches the prebuilt swarm (`stressbot.exe` in the
sibling server repo root; rebuild with `go build -o stressbot.exe
./cmd/stressbot` after bot changes), and winds the swarm down gracefully via a
stop-file when the scene closes. Captains render as capsules, ships as boxes,
with a HUD of client-observed truth — visible counts, snapshot rate, downlink
KB/s, per-entity staleness p50/p95, server session count. WASD moves the AOI
focus, wheel zooms, keys 1/2/3 teleport between hotspot / spread clusters /
empty ocean, B stops/restarts the swarm. Headless runs print the same stats
and quit after `-- --stress-view-seconds=N` (add `--stress-autostart` to also
spawn the swarm headlessly).

Baseline on the 1 vCPU / 1 GB droplet (2026-07-23, untuned AOI): 501 sessions
held with zero errors at the 500-bot design load (~4 MB/s egress); dense-crowd
per-entity staleness is the only degradation (p95 0.4 s at 50-in-port → 1.7 s
at a 250-entity AOI). Player relevance is currently 1000 m — far wider than
gameplay visibility (~200 m); tightening it is the planned lever for crowd
freshness.

## Reusable entity networking

Do not add per-door or per-crane branches to `NetworkManager`.

Use `WorldStateBinding` for stable low-frequency state such as a door, light,
machine mode, or accepted equipment operation. IDs must derive from deterministic
world data or durable server records—not scene paths or instance IDs.

`BrickDoor` is the live template: it attaches a `WorldStateBinding` with a
deterministic id (`door:<server_vessel_id>:<brick cell>` on ships,
`door:land:<quantized position>` on buildings), routes F-press intent through
`request("open"/"close")`, and animates only from `authoritative_state_changed`.
Doors on unregistered vessels or without a world session fall back to plain
local behavior, so single-player and editor previews are unchanged.

Use `NetworkTransformBinding` only for lossy movement. Reliable lifecycle facts
still travel through the gateway.

## Port workers and equipment

Players request work; they do not control crane joints over the network.

1. Gameplay requests a port operation with stable port, berth, equipment,
   vessel, mode, cargo/contract context, and duration.
2. The authority validates account/captain identity, vessel ownership,
   equipment availability, and command shape.
3. Every interested client receives the same accepted operation.
4. Local dock workers, cranes, forklifts, or pumps present that operation.
5. The server scheduler completes timed work even if the player disconnects.

Stopping is an owner request. Successful completion is server-only.

## Economy boundary

There is no multiplayer `set_balance` or generic inventory replacement. Every
commercial feature requires a named server command, server-owned calculation,
one database transaction, and immutable private events. Planned migrations are
vessel/fuel purchase, cargo lifecycle and settlement, warehouse inventory, then
company wages and route settlement.

Single-player uses the same contracts through `LocalWorldBackend`; only the
authority host changes.

## Failure rules

- A missing/expired account session is an authentication failure, never
  permission to use a public captain ID.
- A failed remote document load blocks world entry; it never opens a local save.
- A save revision conflict is surfaced and future writes stop until reconciled.
- Reject seed/version/checksum mismatch before restoring coordinate state.
- Refresh projections after an event cursor gap rather than guessing state.
- Never use UDP metadata as ownership, payment, cargo, contract, or berth-lock
  authority.
