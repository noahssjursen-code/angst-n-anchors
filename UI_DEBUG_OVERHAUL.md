# UI / Debug Overhaul — Design Document

Audit + plan for the UI/debug rework on `feature/ui-debug-overhaul`.
Goals from the brief:

1. **Centralized debug readouts** that don't hurt performance.
2. **System stats**: GPU, CPU, disk, RAM.
3. **Loading log** — when an island/port/ship spawns, capture how long it
   took.
4. **General UI cleanup**.
5. **Map GUI** — currently 1004 lines in one file, split it.
6. **Player GUI** improvements.
7. **Boat GUI feels like it's missing something** — figure out what.
8. **Proper UI-creation system** for reuse.
9. **Multiplayer-ready architecture** so when multiplayer lands the UI
   doesn't fight itself.

Same delivery model as the ship-building overhaul: phased commits on
this branch, design doc as Phase 0, code phases as separate commits.

---

## 1 — What exists today

### 1.1 UI files

| File | Lines | Layer | Trigger | Notes |
| --- | ---:| --- | --- | --- |
| `debug_hud.gd` | 61 | 100 | F3 toggle | Autoload; owns CanvasLayer + DebugDraw + WeatherDebugPresets. Adds F3/F4/E hotkeys. |
| `debug_draw.gd` | 202 | 100 | `queue_redraw()` per frame while visible | Reads `GameState` + queries the scene tree (`get_nodes_in_group` x2) every frame. Own color palette — blue+gold, doesn't use HudStyle. |
| `game_menu.gd` | 244 | 5 (HUD) + 20 (modal) | ESC / M | Autoload; owns WalkingHud + pause menu + MapOverlay. Hard-coded color overrides instead of HudStyle. |
| `walking_hud.gd` | 62 | 5 | `queue_redraw()` every frame | Marks balance + active contracts. Polls `PlayerSession.get_marks()` + `ContractRegistry.get_accepted_contracts()` per frame. |
| `ship_hud.gd` | 302 | (added by `BoatController`) | `queue_redraw()` every frame | Compass + throttle telegraph + dashboard. Half the data updates per frame (heading, speed); other half doesn't (mode label, controller state). |
| `map_overlay.gd` | **1004** | 20 | `queue_redraw()` only while visible | Procedural sea chart + port panel + compass rose + weather field overlay. Way too much for one file. |
| `hud_style.gd` | 83 | n/a | static helpers | Central palette + `make_theme()`. Underused — debug_draw and game_menu both bypass it. |

### 1.2 Telemetry data available

| Source | Metric | Cost |
| --- | --- | --- |
| `Performance.get_monitor(Performance.TIME_FPS)` | Frame rate | free |
| `Performance.TIME_PROCESS` | CPU time in `_process` (s/frame) | free |
| `Performance.TIME_PHYSICS_PROCESS` | CPU time in physics | free |
| `Performance.MEMORY_STATIC` | Heap usage (bytes) | free |
| `Performance.OBJECT_COUNT` | Total live Objects | free |
| `Performance.OBJECT_NODE_COUNT` | Live Nodes | free |
| `Performance.OBJECT_ORPHAN_NODE_COUNT` | Leaked nodes — useful! | free |
| `Performance.RENDER_TOTAL_OBJECTS_IN_FRAME` | Render-able objects | free |
| `Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME` | Polygons drawn | free |
| `Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME` | **GPU draw calls** — proxy for GPU load | free |
| `Performance.RENDER_VIDEO_MEM_USED` | **GPU memory total** | free |
| `Performance.RENDER_TEXTURE_MEM_USED` | GPU memory in textures | free |
| `Performance.RENDER_BUFFER_MEM_USED` | GPU memory in buffers | free |
| `Performance.AUDIO_OUTPUT_LATENCY` | Audio buffer latency | free |
| `OS.get_memory_info()` | physical / free / available **system RAM** | cheap |
| `OS.get_processor_count()` | CPU cores | static, free |
| `OS.get_processor_name()` | CPU name | static, free |
| `OS.get_video_adapter_driver_info()` | GPU driver info | cheap, static |
| `RenderingServer.get_video_adapter_name()` | **GPU name** | static, free |
| `RenderingServer.get_rendering_device().get_memory_usage()` | RD memory by type | cheap |

**What's NOT directly available from Godot:**

- **Per-process CPU usage** — Godot has no API. Could read `/proc/self/stat` (Linux) or `GetProcessTimes` (Windows). For now we'll use `(TIME_PROCESS + TIME_PHYSICS_PROCESS) / frame_time` as the **% of frame budget the game logic burns**, which is the gameplay-relevant number.
- **Per-process GPU usage** — no API. Use `RENDER_TOTAL_DRAW_CALLS_IN_FRAME` + frame time delta as proxies. RTX-specific overlays can show real GPU%.
- **Disk I/O** — not directly tracked; less useful for a runtime HUD anyway.

### 1.3 Performance audit of current UIs

Per-frame waste (CPU side):

- **`walking_hud`**: redraws every frame regardless of whether marks or
  contracts changed. Should only redraw on `marks_changed` /
  `contract_accepted` / `contract_completed` signals. Currently
  ~0.05 ms wasted per frame.
- **`debug_draw` (while visible)**: rebuilds the entire entries Array
  every frame including `get_nodes_in_group()` × 2. Should consume a
  cached snapshot.
- **`ship_hud`**: redraws every frame. Compass/speed do change every
  frame so this is mostly justified, but the dashboard background
  could be cached.

Inconsistencies:

- `DebugDraw.C_BG` is cool blue; `HudStyle.C_BG` is warm hull-black.
  Two different visual identities depending on which UI you're looking
  at.
- `GameMenu._build_pause` constructs styles inline instead of using
  `HudStyle.make_theme()`.
- `MapOverlay` has its own palette (`C_SEA`, `C_ISLAND`, `C_PORT_*`)
  that's intentional for chart-feel — keep, but bridge it to HudStyle
  for borders/text.

### 1.4 Multiplayer readiness

Not addressed today. The relevant gotchas for the future:

- `WalkingHud` reads `/root/PlayerSession` — single-player only.
- `ShipHud.setup(boat, controller)` is per-helmed-boat; already
  per-instance. Good.
- `GameMenu` is an autoload. Pause is global. In multiplayer "pause
  the world" doesn't exist; ESC should pause local UI only.
- `DebugDraw` reads `GameState` which is single-player canonical
  state. In multiplayer it should read **local-player** state.

The fix is to consistently route UI through a per-client view of the
world: `LocalPlayerView` or similar. Out of scope for this branch
beyond making sure today's UIs don't add new global assumptions.

---

## 2 — Target architecture

### 2.1 Telemetry autoload

New file `scripts/state/telemetry.gd`, autoloaded as `Telemetry`.

```gdscript
extends Node

## Centralised performance + system data, read once per second by
## ring buffers. Consumers (DebugDraw, MapOverlay) read `snapshot()`
## which returns a Dictionary — no per-frame Performance.get_monitor()
## hammering.

signal sampled  # emitted at the end of each sample tick (every 1.0 s)

const SAMPLE_INTERVAL_S : float = 1.0
const HISTORY_LEN       : int   = 60   # 60 samples = 1 minute of history

# Static (set once at _ready):
var cpu_name:     String
var cpu_cores:    int
var gpu_name:     String
var gpu_driver:   String
var ram_total_mb: int

# Latest sample (updated every SAMPLE_INTERVAL_S):
var fps:                int
var frame_time_ms:      float
var process_time_ms:    float
var physics_time_ms:    float
var draw_calls:         int
var primitives:         int
var video_mem_mb:       int
var texture_mem_mb:     int
var node_count:         int
var orphan_count:       int
var heap_mb:            float
var ram_used_mb:        int
var ram_free_mb:        int

# Ring buffers for graphs (HISTORY_LEN entries, oldest first):
var fps_history:        PackedFloat32Array
var frame_time_history: PackedFloat32Array
var draw_calls_history: PackedInt32Array

# Loading log — recent timed events:
var load_events:        Array    # of { "name": String, "duration_ms": float, "ts": float }

func _process(delta: float) -> void:
    # Always-on, but does nothing on most frames.
    ...

func snapshot() -> Dictionary:
    # Returns a stable read-only view for UI consumers.
    ...

func mark_load_event(name: String) -> int:
    # Begin a timed event; returns a handle.
    ...

func end_load_event(handle: int) -> void:
    # Closes the event, records duration, appends to load_events.
    ...
```

Consumers connect to `sampled` signal — they don't read Telemetry
per frame.

Event API used like:

```gdscript
var h := Telemetry.mark_load_event("port.load:" + port_id)
... do the load ...
Telemetry.end_load_event(h)
```

Hooked into:

- `World._add_world_renderer` — full world init
- `ProximityLoader._load_entry` — port spawn
- `ShipBuilder.build` — ship instantiation
- `IslandMeshBuilder.to_mesh` — terrain mesh build (the heavy one)
- `LandField.initialize` — SDF bake
- `FFTWaterSystem._ready` — shader compile + buffer setup

### 2.2 UI signal-driven redraws

- **WalkingHud**: redraw only on `PlayerSession.marks_changed`,
  `ContractRegistry.contract_accepted`, `ContractRegistry.contract_completed`.
  Per-frame cost drops to zero.
- **DebugDraw**: redraw on `Telemetry.sampled` (1 Hz) instead of every
  frame. Snapshot includes all the system + gameplay stats it needs.
- **ShipHud**: split into the live compass (per frame) and the
  dashboard (per `state_changed` from BoatController / WeatherLighting).
  Compass and speed needle stay per-frame.

### 2.3 Map overlay split

`map_overlay.gd` becomes the orchestrator (200 lines). New files:

```
scripts/ui/map/
    map_overlay.gd          — root Control, input, layout
    map_chart_renderer.gd   — port polygons, ship marker, edges, grid
    map_weather_renderer.gd — pressure field, wind field, extrema, legend
    map_port_panel.gd       — selected-port detail box
    map_compass_rose.gd     — compass rose top-right
    map_camera.gd           — pan/zoom state + world↔screen transforms
```

Each renderer is a child `Control` that gets handed the shared camera
+ data via `setup()` and does its own `_draw()`. Easier to reason about,
easier to test.

### 2.4 Centralised UI builder

New file `scripts/ui/ui_builder.gd` — static factory functions for
common UI components, all using `HudStyle`:

```gdscript
class_name UiBuilder
extends RefCounted

## Build a maritime-styled Panel with a brass border.
static func panel(min_size: Vector2 = Vector2.ZERO) -> PanelContainer
## Build a section header label.
static func section_header(text: String) -> Label
## Build a label-value row (label left, value right).
static func key_value_row(label: String, value: String, value_color: Color = HudStyle.C_TEXT) -> HBoxContainer
## Build a horizontal separator using HudStyle.C_SEP.
static func separator() -> HSeparator
## Build a button styled to HudStyle.
static func button(text: String, on_pressed: Callable) -> Button
```

`DialoguePanel`, `GameMenu._build_pause`, and any new panels use it.
Eliminates the inline `StyleBoxFlat.new()` repetition.

### 2.5 Boat HUD additions

Things the current `ShipHud` is missing that a sailor reasonably wants:

- **Heading numerical readout** — degrees magnetic, near the compass
- **Engine RPM / throttle %** — number under the telegraph
- **Wind indicator** — direction + force relative to bow
- **Fuel gauge** — placeholder until fuel system lands
- **Depth indicator** — placeholder until bathymetry
- **Distance + ETA to selected destination** — when a port is
  selected on the map
- **Helm state** — manual / autopilot / docking-thruster mode

Of these, **wind indicator** and **heading numerical** are the
highest-value additions (info that's actually computable today).

### 2.6 Multiplayer-clean refactor

A small lift: introduce `LocalPlayerView` — a single Node that any UI
asks for the "player I'm rendering for". Right now it just wraps
`PlayerSession` + the boat the player is currently helming. In a
multiplayer future, this becomes a per-client object.

Stop UIs from referencing `/root/PlayerSession` and
`/root/GameState` directly; instead they ask `LocalPlayerView` for
what they need. Today's behaviour is unchanged; tomorrow's multiplayer
just substitutes the view.

---

## 3 — Implementation phases

### Phase 0 — this design doc

Committed as the first commit on the branch.

### Phase 1 — Telemetry singleton

- New `scripts/state/telemetry.gd`, registered as autoload in
  `project.godot`.
- Hook `mark_load_event` / `end_load_event` into the four spawn-heavy
  places listed in §2.1.
- Smoke test: load the world, confirm `load_events` array is populated
  and durations look right.

### Phase 2 — DebugDraw redesign

- Rewrite `DebugDraw` to:
  - Use `HudStyle` palette (lose the cool blue).
  - Consume `Telemetry.sampled` instead of redrawing per frame.
  - Show new System Stats section (CPU, GPU, RAM, draw calls, video
    mem, FPS, frame time, node count).
  - Show Loading Log section (last N events).
- Keep the existing Player / Ship / Contracts / World sections.

### Phase 3 — Signal-driven WalkingHud

- Connect to relevant signals at `_ready()`; only `queue_redraw()` on
  change.
- Smoke check: idle frame doesn't trigger the WalkingHud `_draw`.

### Phase 4 — Map overlay split

- Carve the 1004-line monolith into the six files listed in §2.3.
- Same visual output; just better organisation.

### Phase 5 — `UiBuilder` factory + `HudStyle` unification

- New `scripts/ui/ui_builder.gd`.
- `GameMenu._build_pause` migrates to it.
- `DialoguePanel` (used by NPCs) migrates to it.

### Phase 6 — Boat HUD additions

- Wind indicator (direction + magnitude relative to bow).
- Heading numerical readout next to the compass.
- Throttle % readout under the telegraph.
- Helm-mode badge top of throttle.

### Phase 7 — `LocalPlayerView` indirection (multiplayer prep)

- New `scripts/state/local_player_view.gd`.
- WalkingHud, ShipHud, DebugDraw stop referencing `PlayerSession`
  /`GameState` directly; ask the view instead.
- No multiplayer code yet — purely a refactor that makes the seam
  available.

---

## 4 — Out of scope (for this branch)

- Multiplayer transport / RPCs.
- Actual fuel and bathymetry systems (the HUD shows placeholders).
- Save/load UI.
- Settings screen.
- Mini-map (the existing M-key chart is the chart — no plans for a
  persistent corner-minimap right now).

---

## 5 — Status log

- **Phase 0 — design doc** — drafting.

---

*Lives on `feature/ui-debug-overhaul`. Updated as phases land.*
