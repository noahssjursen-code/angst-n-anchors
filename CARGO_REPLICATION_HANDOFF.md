# Handoff: Cargo replication duplicates (Issue #1)

**For:** next agent picking up multiplayer replication work  
**Last updated:** 2026-05-25  
**Status:** Fix attempts landed in working tree — **NOT confirmed fixed by user** after full server + client redeploy  
**Severity:** High — blocks credible 2-player playtests  

---

## One-line summary

When a second player is nearby, each client sees **duplicate fish/cargo crates on their own ship**: one real (local `CargoDeckComponent`) plus one lagging ghost (`ReplicationDrawingService` remote proxy). Alone in MP, the bug does **not** appear — it only shows up once another player enters AOI and snapshot rate increases.

---

## User-reported behavior

| Context | Behavior |
|--------|----------|
| Solo (MP connected, no one nearby) | No duplicate cargo on own ship |
| 2+ players in vicinity | Duplicate crates on **own** ship deck; ghost lags behind real cargo |
| Port apron | Same class of bug reported (not just on-ship) |
| Sell point | Moving ghost + real crate together can **re-add cargo to ship** instead of selling |
| Ghost crates | Show **0 value**, persist, never despawn cleanly |

User also suspects cargo may be “replicating locally for each player” — i.e. duplication correlates with other players being in range, not with cargo count alone.

---

## Architecture (how cargo is supposed to work)

1. **Local authority:** `CargoDeckComponent` spawns `PalletNode` under `PalletVisuals/` and calls `NetworkManager.register_cargo_spawn(pallet.id, pallet, node)`.
2. **Outbound:** `NetworkManager._tick_outbound` sends cargo state to server (format 4 payload = **ship-local** x,y,z,yaw when parented; meta includes `parent=<ship_entity_id>`).
3. **Server:** Stores entity with `OwnerID = cu.PlayerID`. Snapshots should **never** echo owned entities back to the owning observer.
4. **Remote clients:** `ReplicationDrawingService.apply_entities` spawns remote `PalletNode`, reparents via `parent=` meta to remote ship node in `_visible_entities`.

**The bug:** Step 4 runs on the **owning** client too — a second `PalletNode` is created and interpolated with lag on top of the real deck cargo.

---

## Root causes identified (multiple, layered)

### 1. Server echoing owned entities (fixed in code, needs deploy)

`angst-n-anchors-mp/internal/world/snapshot.go` previously sent all AOI-relevant entities including ones the observer already simulates locally.

**Fix:** `entitySimulatedByObserverLocked()` in `world.go` skips entities when:
- `entity.ID == observer.PlayerID`
- `entity.ID` has prefix `observer.PlayerID + "_"` (ships, prefixed ids)
- `entity.OwnerID == observer.PlayerID`
- `entity.Type == "cargo"` and meta `parent=` points to observer-owned ship (prefix or parent entity lookup)

### 2. Client not filtering hard enough before drawing (fixed in code, needs rebuild)

Even if server leaks, client must never draw local cargo from snapshots.

**Fix layers in `angst-n-anchors`:**
- `network_manager.gd` — `_filter_snapshot_entities()` strips locally authoritative entities before `apply_entities`
- `replication_drawing_service.gd` — `_should_skip_remote_entity()`, per-frame `purge_local_authority_echoes()`, cargo-specific blocks
- `_process_attachment_meta()` — despawn remote cargo if `parent=` resolves to a **local registered node** (not just dict key match)

### 3. Wire ID truncation mismatch (likely key bug for “only when P2 nearby”)

Wire protocol caps entity IDs at **64 bytes** (`wire_protocol.gd` / `wire.MaxStringLen`).

- Client registers senders with **full** ids (e.g. `DisplayName_12345_<vessel_uid>`).
- Server stores/snapshots **truncated** ids.
- When alone, snapshots are sparse — ghost may be subtle or absent.
- When P2 nearby, AOI tier increases snapshot frequency → ghost cargo visibly rubber-bands every frame.

**Fix:** `network_manager.gd` now maintains `_wire_id_aliases` (truncated → canonical) and `_has_local_sender()` / `_truncate_wire_id()` used in all authority checks.

### 4. MP session start race

Cargo loaded before `begin_multiplayer_session()` may not be in `_local_senders` when first fast snapshots arrive after a second player connects.

**Fix:** `begin_multiplayer_session()` calls `_reregister_local_authority()` which:
- `_ensure_local_ship_registered()`
- `CargoDeckComponent.reregister_network_pallets()` on active ship decks
- Purges drawing service ghosts

---

## Files changed (working tree, may be uncommitted)

### Client (`angst-n-anchors`)

| File | Changes |
|------|---------|
| `scripts/network/network_manager.gd` | Wire ID aliases, snapshot filter, `_reregister_local_authority()`, `is_snapshot_entity_locally_authoritative()`, `get_local_registered_node()`, per-frame purge |
| `scripts/network/replication_drawing_service.gd` | Stronger skip/purge/attachment guards; delegate to NetworkManager authority checks |
| `scripts/ship/cargo_deck_component.gd` | `reregister_network_pallets()` |

### Server (`angst-n-anchors-mp`)

| File | Changes |
|------|---------|
| `internal/world/world.go` | `entitySimulatedByObserverLocked()`, `metaValue()` |
| `internal/world/snapshot.go` | Uses `entitySimulatedByObserverLocked` instead of bare `OwnerID` check |

---

## Deploy / test requirements (CRITICAL)

User has previously tested **client-only** changes against an **old server** — bug persisted.

Both sides must be updated:

```powershell
# Server (DigitalOcean droplet 142.93.43.16)
cd c:\Users\noahs\Documents\angst-n-anchors-mp
Copy-Item .env.example .env.production   # if needed
.\deploy-server.ps1

# Client
cd c:\Users\noahs\Documents\angst-n-anchors
.\build-export.ps1
# Both players need the new zip/exe
```

MP flow: Main menu → Multiplayer → Digital Ocean → captain → **Sail Voyage** (UDP connects on voyage start).

---

## Repro checklist for verifying fix

1. Deploy server; confirm docker rebuild finished (not just upload).
2. Both players run **new** exe build.
3. Both connect, sail to same area, load fish/cargo on own ship (trawl or crane).
4. **Pass:** each player sees exactly one crate per logical pallet on own deck.
5. **Fail signals:** overlapping duplicate with lag; ghost at 0 value; duplicates only when within ~125–500m of other player.
6. Also test port apron staging and sell-point interaction with ghost present.

If still failing, ask user: are ghosts **exactly overlapping** real crates or **offset/lagging behind**? Overlap = echo on same ship; offset = wrong coordinate space (local vs world in snapshot decode).

---

## Related open issues (same replication class)

See `PLAYTEST_NOTES.md`:
- **#1** — this issue (cargo)
- **#3** — crane duplicate (scene node + dynamic spawn); `adopt_scene_node()` attempted
- **#4** — phantom mooring on friend's ship after remote rope attach
- **#2** — company agent fleet list (partial client fix attempted)

---

## Investigation ideas if still broken

1. **Confirm server binary** — SSH to droplet, verify container rebuilt after `deploy-server.ps1`; check logs for `entitySimulatedByObserver` path (no dedicated log yet).
2. **Log snapshot entity ids** on client — compare `ent.id` vs `_local_senders` keys and `_truncate_wire_id()` for mismatches.
3. **Cargo without `parent=` meta** — apron cargo before parent is set may bypass parent-based skip; ensure `owner_id` + sender registration covers it.
4. **Coordinate bug** — cargo on ship sends **local** coords in payload; `decode_snapshot` treats payload[0..2] as world `pos` for spawn position before reparent. May cause visible offset even for remote players' cargo (separate from own-ship echo).
5. **Interaction authority** — `pallet_node.gd` / sell-point handlers may raycast ghost `PalletNode` under `ReplicationDrawingService` or reparented to ship root; need `is_local_authority` or ignore remote proxies for mutations.
6. **Stale server entities** — reconnect with new `DisplayName_<pid>` leaves old OwnerID entities; server TTL is 12s (`world.go`) but may cause transient ghosts.

---

## Key code references

**Local cargo spawn (authoritative):**
- `scripts/ship/cargo_deck_component.gd` — `_spawn_pallet_node()` → `register_cargo_spawn`
- `scripts/ship/fishing_system.gd` — `_place_one_fish_crate()` → `deck.add_pallet()`

**Replication spawn (should NOT run for own cargo):**
- `scripts/network/replication_drawing_service.gd` — `_spawn_dynamic_entity_node()` type `"cargo"`, `_process_attachment_meta()`

**Server snapshot collection:**
- `angst-n-anchors-mp/internal/world/snapshot.go` — `collectRelevantEntitiesLocked()`
- `angst-n-anchors-mp/internal/transport/udp/sender.go` — per-client unicast (not broadcast — ruled out)

**Player id format:**
- `network_manager.get_local_player_id()` → `"<display_name>_<process_id>"`
- Ship id → `"<local_player_id>_<vessel_uid>"` via `register_ship_spawn()`

---

## Branch / context

- Playtest branch: `playtest/notes` (from `main`)
- Playtest log: `PLAYTEST_NOTES.md`
- Prior conversation transcript: `agent-transcripts/a9963b81-e837-4ebd-9df4-7e28c41eaa14.jsonl`

---

## Agent todo (suggested)

- [ ] Verify server deploy completed successfully
- [ ] Verify both clients on latest build
- [ ] Confirm or reject fix with 2-player deck cargo test
- [ ] If open: add temporary debug print of filtered vs applied cargo entity ids (remove before merge)
- [ ] If open: fix sell-point / interaction hitting ghost pallets
- [ ] If open: fix port apron duplication (may need same authority rules without `parent=` meta)
- [ ] Update `PLAYTEST_NOTES.md` issue #1 status when confirmed
