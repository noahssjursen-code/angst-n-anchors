# Playtest Notes

Findings from multiplayer playtests. Add new entries under **Open issues** as we go.

---

## Fixed / needs retest

- **#5 — Stale remote ships after respawn:** Client sends `state=despawned` on hull free; server deletes entity; removed owned-entity LastSeen blanket refresh. **Redeploy MP server required.**
- **Replication pass (2026-05-24, unverified solo):** skip/despawn local echoes for owned cargo/cranes; `adopt_scene_node` for cranes; remote ships can't be mooring targets; company panel uses full `owned_vessels`. **2026-05-25:** server no longer echoes `OwnerID == observer` entities; client purges owned cargo ghosts each snapshot.
- **Main menu:** no UDP connect or ghost ships/fleet on menu load.

## Open issues (fix landed — confirm on next 2-player session)

### 1. Cargo replication — duplicate local + remote instances everywhere

**Handoff doc:** See [`CARGO_REPLICATION_HANDOFF.md`](CARGO_REPLICATION_HANDOFF.md) for full agent context, root causes, fixes attempted, and retest steps.

**Status:** Open  
**Severity:** High  
**Mode:** Multiplayer (2 players confirmed)  
**Reported:** 2026-05-24

**Summary**  
Both players see doubled cargo: a local authoritative crate plus a replicated ghost. The system does not clearly separate “my cargo” from “remote cargo,” and ghosts never clean up even when they behave differently (0 value).

**Symptoms**
- **On ship:** Each player's own ship has duplicate crates; the remote copies rubberband / jitter on the deck.
- **At port:** Cargo on the apron / staging area also duplicates — not limited to aboard-ship state.
- **2-player session:** With two active players, each ship shows doubled cargo (both players affected).
- **Replicated ghost cargo:** Shows **0 value** (correct for non-authoritative copy) but **never disappears** — stale visuals persist indefinitely.
- **Sell / delivery interaction bug:** Physically moving a replicated (0-value) ghost crate to a sell point with the real crate **re-adds cargo to the ship** instead of completing delivery or ignoring the ghost.

**Expected**
- One visual + one logical cargo instance per crate for the owning client.
- Locally owned / locally registered cargo must **not** spawn a second remote drawable in `ReplicationDrawingService`.
- Port-staged cargo: same rule — no duplicate if this client owns or already simulates it.
- Replicated copies (other players' cargo) may show 0 value or no UI, but must despawn when the entity leaves snapshot / is delivered / is picked up.
- Interacting with a ghost crate must not mutate local ship cargo state.

**Repro (approx.)**
1. Two clients connect to shared server (Digital Ocean).
2. Each player spawns / loads a ship with cargo (or picks up cargo at port).
3. Observe doubled crates on deck and at port.
4. Remote copies rubberband; show 0 value; do not despawn.
5. Haul ghost + real crate to sell point → cargo incorrectly re-added to ship.

**Hypothesis / investigation**
- **Ownership filter gap:** `ReplicationDrawingService.apply_entities` may not exclude cargo whose `owner_id` matches local player, or cargo parented to local senders (`parent=ship_id` meta).
- **Double registration:** Local cargo registered as outbound sender *and* echoed back in snapshot → client draws both.
- **No despawn on deliver:** Delivered / picked-up cargo not removed from `_visible_entities` or local deck when meta says delivered; ghost persists at 0 value.
- **Interaction targets wrong instance:** Sell point / crane / deck pickup may hit replicated `PalletNode` and write back into local cargo state.
- **Port apron:** Staged cargo may register on load at port for both clients without deduping by entity id.

**Code touchpoints**
- `scripts/network/replication_drawing_service.gd` — spawn/filter/despawn cargo
- `scripts/network/network_manager.gd` — `register_cargo_spawn`, sender ids, snapshot routing
- `scripts/ship/cargo_deck_component.gd` — local deck state
- `scripts/cargo/pallet_node.gd` — value display, interaction
- Port staging / sell-point handlers — ensure authority checks before mutating cargo

---

### 2. Company agent — owned ships missing after assigning NPC vessel

**Status:** Open  
**Severity:** High  
**Mode:** Multiplayer  
**Reported:** 2026-05-24

**Symptoms**
- After assigning a ship to an NPC / autonomous fleet via the company agent, the panel no longer loads other ships the player owns.
- Fleet / owned-vessel list appears broken or empty for remaining hulls.

**Expected**
- Assigning one vessel to NPC operation should not hide or drop the rest of the player's owned fleet in the company agent UI.
- All owned ships should remain listable / manageable.

**Hypothesis / investigation**
- `company_fleet_panel.gd` / `PlayerSession.data.owned_vessels` — state not refreshed after activate?
- MP vessel sync (`VesselSync`) may overwrite or filter local list when one record goes autonomous.
- Server `/v1/vessels` response may omit non-active hulls after fleet assignment.

**Code touchpoints**
- `scripts/npc/company_fleet_panel.gd`
- `scripts/player/vessel_sync.gd`
- `scripts/player/autonomous_vessel_manager.gd`
- `scripts/player/player_session.gd` — `owned_vessels`, `vessels_synced`

---

### 3. Crane replication — duplicate remote crane + split authority

**Status:** Open  
**Severity:** High  
**Mode:** Multiplayer (2 players confirmed)  
**Reported:** 2026-05-24

**Summary**  
Cranes suffer the same class of bug as cargo: one player sees a single local crane, the other sees **two** (local + replicated ghost). Crane operation authority is split across invisible duplicate instances — each player can only operate the copy they see, not the same physical crane.

**Symptoms**
- **Observer A (crane owner / port local):** Sees **one** crane at the berth.
- **Observer B (remote client):** Sees **two** cranes — likely local pre-placed scene node **plus** replicated duplicate.
- **Cross-use deadlock:** If B has used "their" crane, A trying to use A's crane is **frozen / standstill** (no movement).
- **Asymmetric control:** B can operate the **replicated ghost** of A's crane (which A cannot see). B **cannot** operate the same crane instance A sees locally.
- Result: two players cannot share or hand off the same berth crane; operation state diverges per client.

**Expected**
- Exactly **one** crane entity per berth crane id on every client.
- Pre-placed port cranes bind to scene node by id — snapshot must **update** that node, not spawn a second dynamic mesh.
- When a player boards / operates a crane, all clients see the same operator lock and the same joint state.
- Remote operator uses replicated state on the **same** node; no invisible second crane.

**Repro (approx.)**
1. Two players at same port berth with gantry crane.
2. Player A sees one crane; Player B sees two.
3. B operates crane → A's crane stuck / unresponsive.
4. B operates the duplicate they see; A has no matching visual.

**Hypothesis / investigation**
- `ReplicationDrawingService` binds `scene_nodes[id]` for cranes but may **also** spawn dynamic duplicate when snapshot arrives.
- `_scene_nodes` registration vs `apply_entities` spawn path — double instantiate for same crane id.
- Operator meta (`op=player_id`) applied to wrong node instance on remote client.
- Local crane sender + snapshot echo → two nodes with same logical id.
- Boarding / `_remotely_operated_by` lock on one instance while input goes to the other.

**Code touchpoints**
- `scripts/network/replication_drawing_service.gd` — crane spawn vs scene bind
- `scripts/network/network_manager.gd` — `register_crane`, `notify_crane_operated`
- `scripts/port/gantry_crane.gd` — operator lock, boarding, replication send

---

### 4. Phantom mooring — friend's ship soft-locked at dock

**Status:** Open  
**Severity:** High  
**Mode:** Multiplayer (2 players confirmed)  
**Reported:** 2026-05-24

**Summary**  
One player moored another player's ship once (added a rope). The ship owner now has **no visible mooring lines** but the hull behaves as if still moored — same drive restriction as trying to leave while legitimately tied up.

**Symptoms**
- Player B (ship owner): **no visible ropes / mooring lines** on their ship.
- Player B **cannot leave the dock** — helm behaves like the vessel is still attached to bollards.
- Triggered after Player A interacted with B's ship **once** and added a mooring rope.
- Possible **phantom mooring state**: logical attachment exists on owner client without matching visuals (or attachment lives on wrong replicated instance).

**Expected**
- Mooring state, rope visuals, and physics constraint must stay in sync on all clients.
- Only the ship owner (or agreed authority) should attach/detach lines on their hull.
- If moored: ropes visible. If not moored: ship can drive away.
- Remote-assisted mooring (if allowed) must replicate attach **and** detach cleanly.

**Repro (approx.)**
1. Two players at same berth; Player A adds a mooring line to Player B's ship (once).
2. Player B sees no ropes.
3. Player B tries to drive away → blocked as if still moored.

**Hypothesis / investigation**
- `MooringComponent` attachment state set locally on A's client or on a **ghost ship** copy, then persisted in snapshot meta without B's local component updating visuals.
- Detach / release never sent or never applied on owner's authoritative hull.
- Remote ship duplicate: A moored the replicated ghost; B's real ship inherited constraint without rope meshes.
- Berth registration on `PortDock` may mark ship moored on server/snapshot while owner's `MooringComponent` desynced.

**Code touchpoints**
- `scripts/port/mooring_component.gd` — attach/detach, rope visuals, drive lock
- `scripts/port/port_dock.gd` — berth registration, ship moor state
- `scripts/network/network_manager.gd` — ship replication meta (mooring / berth)
- `scripts/network/replication_drawing_service.gd` — remote ship instance vs local

---

## Ideas / polish

_(Non-blocking observations.)_
