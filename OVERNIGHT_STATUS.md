# Overnight session — status

Branch on both repos: `claude/zen-mccarthy-BmE1z`. All commits are small and
land one change each so you can revert individually.

## What landed

### `angst-n-anchors-mp-server` (commit `a45eb45`)
**Email/password auth + scope captains and vessels by user**

- `users` table (email CITEXT, bcrypt `password_hash`, `is_admin` bool).
- `captains.user_id` FK added; **legacy captains/vessels are dropped on
  first boot of the new schema** (one-time, detected by absence of the
  `user_id` column).
- New `internal/auth/` package — bcrypt + HMAC-signed stateless tokens.
  Set `AUTH_SECRET` on the droplet to a long random string; falls back to
  a dev secret with a log warning otherwise.
- New endpoints: `POST /v1/auth/register`, `POST /v1/auth/login`,
  `GET /v1/auth/me`.
- `/v1/captains`, `/v1/vessels`, `/v1/autonomous_vessels` now require
  `Authorization: Bearer …` and scope every read/write to the caller's
  user_id.
- Wire `MaxStringLen` 64 → 128 so UUID-prefixed entity ids stop getting
  truncated by the server validation cap.

### `angst-n-anchors` (commits `d2fd1f2`, `c12862f`, `e576ceb`, `125d757`)

1. **`d2fd1f2` — email/password login + captain UUID as wire identity**
   - New `AuthSession` autoload at `scripts/network/auth_session.gd`.
     Persists token to `user://auth_session.cfg` so login survives runs.
   - Main menu adds a LOGIN page reached from the Multiplayer button when
     no valid session exists. Register / sign in / sign out / back.
   - Captain picker hits `/v1/auth/me` — you only see your own captains.
   - `get_local_player_id()` returns the captain UUID. Singleplayer keeps
     a `local_<name>_<pid>` fallback that never goes on the wire.
   - All account-scoped HTTP calls now send `Authorization: Bearer`
     (player session marks sync, vessel sync, autonomous vessel pull,
     captain CRUD in main menu).
   - Wire `MAX_STRING_LEN` 64 → 128 to match the server cap.
   - **This is the working theory for issue #1 (cargo replication ghosts)**
     — the old `<display_name>_<pid>` composite was unstable across runs
     and overflowed the cap, breaking the server's prefix-based ownership
     check whenever a second player was in AOI.

2. **`c12862f` — speed up autonomous vessel pathfinding**
   - `_connector_blocked`: collapsed two segment-sampling passes (land
     pierce + clearance violation) into a single walk. Each candidate
     edge now samples 32–256 points once instead of twice.
   - `_find_shortest_path`: replaced the per-iteration `sort_custom` +
     lambda allocation with a linear-scan min pop. ~64 nodes is small
     enough that the scan is cheaper, and the per-iteration `Callable`
     allocation is gone.
   - `World._bake_berth_lanes`: eagerly rebuilds the global navigation
     graph immediately after baking berth lanes, so the first NPC spawn
     no longer triggers a multi-hundred-ms land-clearance walk during
     ship load.

3. **`e576ceb` — keep owned vessels in panel when template rebuild fails (#2)**
   - `VesselSync._merge_server_row` was returning `{}` for an existing
     record when the local template file was missing AND
     `HullRegistry.get_by_id` couldn't rebuild it.
     `_apply_server_vessels` treated that `{}` as “skip this row,” then
     overwrote `owned_vessels` with the truncated list. One unrebuildable
     hull in the snapshot was wiping the rest of the captain's fleet
     from the company panel.
   - Now keeps the existing record (with merged display/hull/fleet
     state) when the template can't be rebuilt and logs a warning.

4. **`125d757` — restrict mooring interaction to the local player's ship (#4)**
   - `MooringPost._find_active_mooring` iterated every ship in range,
     including replicated copies of other players' ships. Player A
     pressing the moor key near B's docked hull was binding a line on
     A's local copy of B's ship and broadcasting a phantom berth lock
     that B's authoritative `MooringComponent` never saw.
   - Now filters candidates to bodies in `PlayerVessel.GROUP` — each
     player can only moor their own ship.

## What you need to do before testing

1. **Set `AUTH_SECRET`** in the server environment. Edit `docker-compose.yml`
   (or `.env.production` if you have one) to add a long random string.
   Without it the server logs a warning and uses a dev fallback secret.
2. **Redeploy the server** (`deploy-server.ps1`) — the legacy
   captains/vessels rows will be dropped on first boot of the new
   schema. This was the agreed migration path.
3. **Rebuild the client** (`build-export.ps1`) and distribute the new
   exe to your friend.

## Suggested test order

1. Solo: register an account → log in → captain picker is empty →
   create a captain → sail. Sanity check that nothing single-player
   regressed.
2. Two-player cargo (#1): both register accounts, sail to the same
   area, load fish/cargo. **Pass if each player sees exactly one crate
   per logical pallet on their own deck and the offset/lagging ghost is
   gone.** If still failing, see the “if it's still broken” section in
   `CARGO_REPLICATION_HANDOFF.md`.
3. Company panel (#2): assign one vessel to NPC operation, reopen the
   panel. Other owned hulls should still be listed.
4. Phantom mooring (#4): friend tries to interact with the bollard near
   your ship. Their key press should now do nothing (no line attached,
   no berth lock).
5. NPC path perf: at world load, watch the first 1–2 seconds. The
   navigation graph build now happens during `berth_lanes.bake`
   instead of staggered across ship spawns. Should feel smoother.

## Known risks / things I didn't touch

- **UDP path still trusts the client's claimed `PlayerID`.** The token
  only protects HTTP. For two friends this is fine, but anyone who
  reaches the UDP port and knows a captain UUID could spoof. Source-addr
  binding on the first packet is Phase 1.5 — let me know if you want it
  next.
- **Crane duplicate (#3)** — same class as cargo. The stable-UUID + cap
  fix should help, but I didn't add a separate fix. Verify in a 2-player
  test; if ghosts remain, the next move is auditing the
  `_scene_nodes` registration vs dynamic-spawn path in
  `replication_drawing_service.gd`.
- **The defensive cargo purge code** in `network_manager.gd` and
  `replication_drawing_service.gd` is still in place as belt-and-braces.
  If issue #1 verifies clean, that machinery (`_wire_id_aliases`,
  `_truncate_wire_id`, per-frame `purge_local_authority_echoes`) can be
  cleaned up in a follow-up.
- **No Godot binary in this env**, so I couldn't smoke-test the GDScript
  changes. The Go server side compiles clean (`go build ./...`).
  Watch for parse errors at first Godot launch — should be none, but
  flag if any.

## If you want a quick win when you wake up

Set `AUTH_SECRET` before deploying, otherwise the dev fallback is what
will sign your tokens. The token survives across server restarts only
while the secret stays the same.
