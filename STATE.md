# STATE.md — Branding & GUI milestone

Position file for the orchestration loop. Read `CONVENTIONS.md` first.
This file is rewritten at every checkpoint. If it disagrees with the tree, the tree wins —
re-verify and correct it.

- **Branch:** `claude/branding-gui-orchestration-hhjb52` (both repos)
- **Last updated:** 2026-08-09 · setup wave
- **Milestone:** M0 — Foundations (make the loop runnable and the claims checkable)

---

## Where we are

The repo arrived with a branded design system already built (commit `9338897`,
179 files, +11 217 lines) and a brand kit under `branding/`. The work now is not
"add branding" — it is **make the branded system real, verified, and extended to the
internal apps, with Structure Studio as the centre of gravity.**

M0 exists because none of that can be trusted until the tooling can prove it. As of
this writing the gate had never been run in this container, `--headless` silently
mis-reports, and a sample test was found printing `PASS` while its assertions failed.

---

## Verified facts (measured, this container)

| | |
|---|---|
| Godot | 4.6-stable installed; `--headless --import` clean, **0 errors** |
| Cores | 4 → workflow agent concurrency caps at **2** |
| Renderer | xvfb + `opengl3` → Mesa llvmpipe, GL 4.5. **No Vulkan ICD → Forward+ cannot run here** |
| Capture | **Works.** Probe produced a 1280×720 PNG with real pixels under xvfb+opengl3 |
| `--headless` | **Unusable as the gate.** No autoloads; `frame_post_draw` never fires → render tests hang to timeout |
| `--script` | **Never registers autoloads**, any driver. Autoload-touching tests must run as a scene |
| Test files | 81 under `tests/` — **58** `extends SceneTree`, **23** `extends Node`/`Node3D` (need a `.tscn`) |
| Test scenes | 24 `.tscn` under `tests/` |

### The false-green defect

`tests/company_service_test.gd` prints `company_service_test: PASS` and exits **0**
while three of its assertions fail. Cause: Godot's `assert()` does not abort and does
not set an exit code; the test's own bookkeeping never consults it.

**38 of 81 test files use bare `assert()`.** Until that is fixed, a green gate is not
evidence for those files. This is the single biggest threat to every claim this
milestone will make.

### Suspected shipping defect (unverified — needs an actual export)

`branding/.gdignore` tells Godot to skip the whole `branding/` tree, but
`BrandTokens.PALETTE_PATH` is `res://branding/brand/tokens/palette.json`
(`scripts/ui/design_system/brand_tokens.gd:10`) and it is the **only** loader of the
palette. If the exporter honours `.gdignore`, an exported build has no palette and
every token resolves to `Color.MAGENTA` (`brand_tokens.gd:120`). `export_presets.cfg`
has `include_filter="resources/*,*.json,*.glsl"`, which *may* rescue it. **Verify by
exporting a build and inspecting the PCK — do not reason about it further.**

---

## Assets and specs on hand

- `branding/brand/tokens/` — `design-tokens.json`, `palette.json`, `palette.gd`, `palette.css`
- `branding/brand/logo/` — 5 SVG marks, 2 lockups, 20 PNGs; `currency/mark-glyph.svg`
- `resources/fonts/brand/` — Saira, Saira Condensed, JetBrains Mono, PT Sans (+ OFL licences)
- `resources/ui/brand/` — marks + currency glyphs imported for runtime
- Five `.dc.html` design specs: Brand Profile · Screens (chart + dialogue) · **Structure Studio** · Socials Kit · Steam Kit
- `scripts/ui/design_system/` — `BrandTheme`, `BrandTokens`, `BrandComponents`, `BrandFormat`,
  `BrandMotion` + 8 components
- `tests/ui_system_contract_test.gd` — the only branding guard; passes

### Structure Studio, as found

`scripts/apps/structure_studio.gd` (86 KB) builds its scene and UI entirely in code
from a one-node `.tscn`. Tools: SELECT / WALL / ROOM / CORRIDOR / DECK / STAIR / OPENING,
undo/redo, build levels, ghosting, gizmo move, face resize, JSON save/load.

It already ships `_run_studio_probe()` (`structure_studio.gd:115`) — a self-checking
workout run via `godot scenes/apps/structure_studio.tscn -- --studio-probe` that drives
real placement paths and quits non-zero on a broken invariant. **This is the seam to
build the agentic harness on.** Its current limits: hardcoded coordinates rather than
data objects, calls private methods, captures no screenshots, and is not in the gate.

`structure_plan_v1` (`resources/data/structures/demo_workboat.json`) is the data-object
contract: `walls[] · decks[] · rooms[] · stairs[] · items[]` plus `format`, `context`,
`hull_id`, `palette`. `items` is empty everywhere — the spec's prop toolbox
(BARREL/BUNK/CHAIR/CLEAT/…) has no data behind it yet.

---

## Known documentation drift

- `ARCHITECTURE.md` §`scripts/apps/` still lists only `BuildingBrickEditor` and
  `ShipyardBrickEditor`. Structure Studio — which `AGENTS.md` calls the single unified
  builder — is absent.
- `AGENTS.md` says the old brick-editor scenes are "retired", yet
  `scenes/apps/shipyard_brick_editor.tscn` exists and `tests/shipyard_editor_ui_test.tscn`
  references that family. Retirement is claimed, not executed.

---

## In flight

- **Recon wave** (8 areas + 3 adversarial critics): Structure Studio anatomy · design-system
  fidelity · UI surface inventory · apps inventory · headless capture · agentic test seam ·
  brand spec corpus · mp-server. Results fold into this file when they land.
- **Full gate baseline:** started, then **stopped** — it and the recon wave starved each
  other on 4 cores. Re-run clean once recon completes. Partial run: 6 PASS, 1 NOTRUN
  (`chart_layer_manager_test`, autoload compile errors), 2 TIMEOUT under load.

---

## Owner decisions (2026-08-09)

Settled. Do not relitigate; if one turns out to be wrong, raise it explicitly.

| Question | Decision |
|---|---|
| Which internal apps are in scope | **Structure Studio** (rebuild to `branding/Angst n Anchors Structure Studio.dc.html`) and **`vessel_registration_audit`** (rebrand). The two legacy brick editors are **deleted** — scripts, scenes, and their tests — executing the retirement `AGENTS.md` already claims. |
| Out of scope for now | Character/wardrobe authors (`character_body_author`, `character_wardrobe_author`, `character_fitted_wardrobe_author`, `icelander_sweater_author`) and the mp-server admin web UI. Their defects stay recorded here, unworked. |
| Capture fidelity | **Accept GL/llvmpipe captures.** PNGs are evidence for layout, spacing, colour and typography — not shader accuracy. No lavapipe install. Every capture pairs with a machine-checkable assertion. |
| False greens | **Fix the helper and fix the breakage.** Convert all 38 bare-`assert()` files, then fix whatever genuinely fails until the gate is honestly green. No quarantine list. |

## Next actions

1. **Re-run `tools/gate.sh` clean** with nothing else on the box. Record the real
   pass/fail/NOTRUN split here. This number is the baseline every later claim is measured against.
2. **Kill the false greens.** Replace bare `assert()` in the 38 offending test files with a
   shared helper that records a failure and forces a non-zero exit. Fix whatever real
   breakage this exposes (`company_service_test` first). Nothing else in this milestone
   is trustworthy until this lands.
3. **Add gate lane B** — run the 23 scene-based tests as scenes so autoload-dependent code
   is covered at all, and migrate the NOTRUN `--script` tests into it.
4. **Verify the export/palette risk** by producing an actual export and inspecting the PCK.
5. **Build the Structure Studio headless harness**: data-object in → bake → assertions +
   canonical-angle PNGs out, on top of `_run_studio_probe`'s seam. Wire it into the gate.
6. **Then, and only then**, start the GUI work itself against the `.dc.html` specs, Structure
   Studio first.

---

## Milestone log

- **M0 — Foundations** · open · 2026-08-09. Exit criteria: gate is honest (no bare-`assert`
  false greens), covers both lanes, runs clean end-to-end; Structure Studio drivable from a
  data object headlessly with a captured PNG; all of it committed and pushed.
