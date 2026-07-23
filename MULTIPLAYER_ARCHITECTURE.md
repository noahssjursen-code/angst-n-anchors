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

## Reusable entity networking

Do not add per-door or per-crane branches to `NetworkManager`.

Use `WorldStateBinding` for stable low-frequency state such as a door, light,
machine mode, or accepted equipment operation. IDs must derive from deterministic
world data or durable server records—not scene paths or instance IDs.

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
