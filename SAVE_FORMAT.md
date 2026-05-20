# Save Format — Angst 'n Anchors

Local save file lives at `user://player.save` (or whatever
`PlayerSaveStore.PATH` resolves to). Single envelope per local profile
today; designed to be replaceable with a server fetch when accounts
arrive — no game code reaches into the file directly, everything goes
through `PlayerSession.data`.

---

## Envelope

```json
{
  "version":       2,
  "saved_at_unix": 1716160000,
  "player":        { ... }
}
```

| Field | Type | Notes |
|---|---|---|
| `version` | int | Current format version. Bumped only when fields disappear or change semantics; additive changes (new keys with defaults) leave version alone. |
| `saved_at_unix` | int | Wall-clock time of the save, for "last played" display. Not used by load. |
| `player` | dict | The `PlayerData` payload — see below. |

---

## `player` payload (version 2)

```json
{
  "account_id":          "",
  "display_name":        "Captain",
  "marks":               0,
  "total_marks_earned":  0,
  "contracts_completed": 0,
  "distance_sailed_m":   0.0,
  "active_vessel":       { "uid": "...", "hull_id": "...", "display": "...", "template_path": "res://..." },
  "appearance":          { "skin_color": [r,g,b,a], "clothing_color": [r,g,b,a], "trousers_color": [r,g,b,a], "hat_id": "flat_cap" },

  "accepted_contracts":  [ { "id": "...", "taken_count": int, "delivered_count": int }, ... ],

  "ship_runtime_state":  {
    "world_pos":          [x, y, z],
    "yaw":                float,
    "throttle_stage_idx": int,
    "fuel_fraction":      float
  },

  "world_clock_hours":   float,
  "tutorial_seen":       { "welcome": true, "first_helm": true, ... }
}
```

### Field semantics

- **`active_vessel`** — ledger record for the captain's single hull. Empty `{}` until they commission one. `template_path` points to a JSON written by `StarterVessel.write_template_file()` or by the shipwright.
- **`accepted_contracts`** — restored on load by `ContractRegistry.restore_accepted()`. Mid-flight cargo (`taken > delivered`) is **forfeited on load**: `taken` is clamped to `delivered`. This matches the existing "ship despawn forfeits cargo" rule and avoids the bookkeeping of restoring pallet positions.
- **`ship_runtime_state`** — applied to the active ship by `PortDock.spawn_player_ship` → `LocalPlayerView.apply_runtime_state_to_active_ship()` after the harbour master finishes a respawn.
- **`world_clock_hours`** — `-1.0` sentinel means "no time saved yet, treat as fresh world." On load `WorldClock.set_game_hours_elapsed(hours)` re-anchors the clock so day/night picks up where it left off.
- **`tutorial_seen`** — `{ hint_id: true }` once a hint has fired. Persistence makes returning captains skip the welcome chain.

### Backward compatibility

`PlayerData.from_dict` tolerates missing v2 keys — they default to empty / `-1.0` sentinel — so a save written by an older build still loads cleanly. There is **no explicit migration step**; we accept defaults rather than rewriting old fields.

If a future change can't be expressed additively, bump `version` and gate the new behaviour on the loaded value.

---

## Triggers

`PlayerSession.save_now()` is invoked from:

- The 60 s autosave heartbeat (`PlayerSession._process`)
- `_notification(NOTIFICATION_WM_CLOSE_REQUEST)` and `NOTIFICATION_APPLICATION_PAUSED`
- `GameMenu._on_window_focus_exited` (alt-tab / clicking away)
- `_quit_to_desktop` in the pause menu
- The character creator on confirm (`begin_new_captain`)
- The harbour master's abandon-ship flow (`_commit_abandon`)
- Tutorial hint firing (to persist seen flags promptly)

`_request_save()` is a coalescing debounce for high-frequency callers (e.g. marks earned). It defers a single `_flush_save()` to the end of the frame so back-to-back marks emits write once.

---

## Where it lives in code

- `scripts/player/player_data.gd` — `to_dict()` / `from_dict()`
- `scripts/player/player_session.gd` — autoload, autosave, signal wiring
- `scripts/player/player_save_store.gd` — file I/O, envelope schema, `SAVE_VERSION` constant
- `scripts/state/local_player_view.gd` — `_snapshot_into_player_data()`, `restore_player_state()`, `apply_runtime_state_to_active_ship()`
