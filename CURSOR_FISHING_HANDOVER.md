# Cursor handover — fishing boat, harpe, heavy pilk and next crab-trapping work

Prepared 12 October 2026. Read this AND repository AGENTS.md before editing.

## Workspace and safety

- Repository: C:/Users/noahs/Documents/angst-n-anchors
- Current branch: feature/seabed-foundation
- Godot 4.6.1, GDScript, Forward+ / D3D12, Jolt. No C#.
- Godot executable: C:/Users/noahs/Downloads/Godot_v4.6.1-stable_win64.exe/Godot_v4.6.1-stable_win64.exe
- Blender executable: C:/Program Files (x86)/Steam/steamapps/common/Blender/blender.exe
- There is a LARGE existing dirty/untracked worktree spanning many systems. Do not reset, clean, overwrite unrelated work, or assume all changes are from this pass. No commit was made for this handover.
- All automated runs MUST use --shipyard-playtest, including showcases, to isolate real captain saves. Do not kill the user's editor/game; distinguish your own test process by its command line.
- Windows GUI executables can return from PowerShell before finishing. Read the named log for PASS/errors rather than trusting the shell exit status.
- Save every machine/application/in-engine screenshot in C:/Users/noahs/Pictures/machinescreenshots with a unique name. Additional review copies are fine.
- Read/write source explicitly as UTF-8. Python Path.read_text() default on this Windows machine caused mojibake in UI strings; repaired in the latest pass. Always specify encoding='utf-8' and newline='\n' for writes.

## User's latest decisions — do not reinterpret

1. Fishing is performed by a person on deck, NOT while driving at the helm.
2. Rod: stout ocean rod, heavy chrome pilk, larger/heavier fish deeper down.
3. Harpe: FLAT plastic handline winder, not a circular drum reel and not a harpoon. Six small hooks catch more but lighter fish. User supplied a photograph: grey moulded handle opening, white line wound around waist, green hook keeper below, six red-beaded hooks, red teardrop sinker clipped to face.
4. User supplied pilk photograph: long tapered chrome body, swivels/split rings, red-sleeved treble hook at bottom.
5. BOTH outfits DROP directly over the side. NO charged cast, throwing motion, or distance selection. RMB lowers/pays out; LMB retrieves. During a fish fight BOTH controls still advance the continuous haul: keep the fish inside the white bar to prevent snapping, rather than reverse haul progress with RMB.
6. Fishing-boat rod stand is a generic equipment mount whose model changes to the ship's equipped rod/harpe. Purchased gear belongs to a durable ship record. Harbourmaster has Equipment shop actions.
7. Crab boat/trapping is separate work. User explicitly rejected expanding the fishing-boat harpe pass into crab gameplay. This handover describes crab work for the next stage; do not silently make all boats crab boats.
8. Earlier progression: first fishing boat rod/line, second crab boat; trawler removed from this small solo-boat progression. A future trawler should be a substantially larger vessel. Old trawl code still exists; do not assume its presence means user wants it reinstated.
9. Currency is NOK, NOT 'marks' in user-facing UI. Legacy internal money fields still use marks.
10. Sonar UI belongs on ALL ships and reads real seabed/schools. User wants the vivid blue/red/yellow traditional scrolling echo display from the supplied reference, not an invented grid/dashboard. Preserve it.
11. Players cannot see through ocean. Bites must correspond to actual school positions/depths seen on sonar, with forgiving ~70 m horizontal catch radius and existing depth tolerance. Preserve fish and catch-area gizmos under ocean-disable/debug workflow.
12. Player inventory is intended for a later branch. Do not launch a broad personal-inventory rewrite to implement ship-owned gear.

## What is implemented now

### Ship purchases / selection

- resources/data/equipment/shop.json: fishing_rod (Heavy-pilk sea rod, 1800 NOK), harpe (950), crab_trap (650), rope_100m (450), marker_buoy (180), bait_pack (80).
- scripts/ship/vessel_equipment.gd: catalog, normalization, counts, has_mount using actual hook_line_station in imported layout.
- Owned record optional purchased_items = array of {uid,item_id,quantity,purchased_at_unix}. Optional equipped_fishing_item = fishing_rod or harpe.
- PlayerData ledger normalization preserves fields; partial vessel updates that omit fields must preserve existing values. Active mirror and owned ledger must stay consistent.
- CompanyService.purchase_equipment validates owned ship, catalog price, quantity, funds, idempotent order ID; rejects order-ID payload changes.
- PlayerSession.purchase_ship_equipment wraps local authority and persistence, rolling money AND goods back on save failure. Local-only; remote mode deliberately rejects unsupported mutation.
- CompanyService.equip_fishing_item checks mount compatibility and owned harpe. Existing mounted rod is included for legacy ships. PlayerSession.equip_ship_fishing_item rejects changes while gear is held, saves selection, emits refresh. Do not consume a purchased reusable harpe each time it is equipped.
- VesselSpawn carries equipped ID in boat metadata. RodFishingStation refreshes from vessel record and swaps model/session.
- scripts/port/port_service_desk.gd and scripts/ui/voyage_panel.gd: harbourmaster Equipment shop purchase/equip actions. UI reads via LocalPlayerView. Core commands remain authority-side.
- Trap supplies can currently be PURCHASED, but that is NOT a working preparation/deployment/recovery system.

### Rod and harpe gameplay

- scripts/ship/rod_fishing_station.gd: existing class/name retained for compatibility, but owns both outfits. F pick up/return at mount. _drop() checks straight vertical path from tip to water against hull/deck; rejects blocked drops with a rail prompt. RMB initiates drop from stowed/landed. LMB strikes a rod bite. No production charging input remains.
- scripts/ship/rod_fishing_session.gd: independent state machine. drop() immediately enters fishing with zero charge/reach, bypassing flight. Legacy begin_charge/cast functions and presentation branches remain for old tests/callers; don't confuse those with current player controls.
- scripts/ship/harpe_fishing_session.gd: six hook depths, spaced 0.65 m above sinker. Each hook queries actual habitat specimens and reserves a unique fish; six catches can coexist. LMB starts haul when at least one hook is occupied. All landed catches become separate CatchLots. Recovery releases reservations.
- Initial balance (NOT real-world gear specifications): harpe <=5 kg per fish; rod >=1.5 kg, with no new upper mass limit. This overlap is intentional initial tuning, not a finalized economy. Rod lowers at 6 m/s, harpe 3.5 m/s. Existing depth guard is 3–180 m; no new arbitrary minimum fishing depth was added.
- scripts/world/fishing_habitat.gd: at_hook now has optional min_kg/max_kg filters applied BEFORE nearest eligible specimen selection. Default arguments preserve other callers. Same schools, individual IDs, depths, terrain occlusion and horizontal catch radius remain in use.
- scripts/ship/harpe_rig_visual.gd: leader, six snoods/hooks, bottom sinker and actual caught fish models. Main rope ends at top of leader; fish attach by mouth, not body centre. Reserved fish disappear from free school presentation/sonar rather than being duplicated.
- scripts/ship/fishing_line_shape.gd: existing rope presentation; avoid restoring a straight ray-like line or making water draw over it.
- scripts/ui/fishing_instrument.gd: lower/retrieve prompts; harpe hook count and batch weight/value. Latest UI encoding corrected.
- scripts/ship/catch_hold_component.gd, scripts/cargo/catch_hold_state.gd, CatchLot/FishCatalog: existing catch crate and individual specimen library. Reuse this rather than inventing another catch inventory.

### Authored assets

Source: resources/models/_source/fishing_items/
- build_harpe.py -> harpe.blend, harpe_hook.blend, harpe_sinker.blend
- build_heavy_pilk.py -> heavy_pilk.blend
- build_fishing_items.py -> spinning_rod.blend and hook_line_station.blend (legacy filenames; now thicker/shorter sea rod with transverse conventional reel)
Exports: resources/models/fishing_items/*.glb and resources/models/parts/coastal_fishing/hook_line_station.glb.
Harpe has RightGrip, LeftGrip, LineTip, StoredTackle nodes. StoredTackle hides when deployed. No rotating crank on the flat winder.
Rod flex joints remain articulated. scripts/character/rod_hand_pose.gd has a handline-specific orientation branch; original character skeleton limb lengths are preserved.
SurfaceMaterialLibrary harpe mapping exists in resources/textures/marine/assignments.json. New polymer finishes authored in Blender; metal uses existing named material conventions. Keep sources and exports together.

## Verified evidence (do not exaggerate)

Latest actual in-engine test:
.codex/fishing-outfits-review-clean.log
HARPE LIVE PASS: purchased, equipped, mount changes, held swap blocked, vertical drop, six unique fish, haul, six crate lots, rod swap and saved selection.
It also picks up the replacement sea rod, lowers the pilk with RMB and checks depth >2 m, then captures it close up.
- .codex/fishing-drop-size-test.log: harpe six unique fish, reservations/release, wrong surface depth, drop without charge/flight, rod lowering speed, LMB retrieval, size eligibility.
- .codex/harpe-equipment-final.log: purchase price authority, ownership, ship separation, retry, JSON save roundtrip, partial updates, invalid input and save rollback.
- .codex/fishing-outfits-ui-test.log: 52 UI checks, zero failures.
- No claim that multiplayer fishing or trapping is implemented.
- JSON selection roundtrip passed; do not treat that alone as a full quit/restart/deploy acceptance test.

Run examples from repository (PowerShell):
& 'C:/Users/noahs/Downloads/Godot_v4.6.1-stable_win64.exe/Godot_v4.6.1-stable_win64.exe' --headless --path . tests/harpe_fishing_test.tscn --log-file .codex/cursor-harpe-test.log -- --shipyard-playtest
& 'C:/Users/noahs/Downloads/Godot_v4.6.1-stable_win64.exe/Godot_v4.6.1-stable_win64.exe' --path . scenes/showcases/harpe_fishing_showcase.tscn --log-file .codex/cursor-harpe-live.log -- --shipyard-playtest --harpe-review
F6 playable inspect scene: scenes/showcases/harpe_fishing_showcase.tscn
Other relevant tests: vessel_equipment_test, voyage_ui_test, catch_hold_test.
Old rod_fishing_test/showcase review paths may still assume charged casting and all species on rod; update obsolete expectations deliberately, don't restore rejected controls to make old tests pass.

## Known rough edges / next fishing checks

- Hand/winder pose is an initial adaptation of rod IK, not a polished hand-over-hand winding animation. Inspect close-up from separate cameras. The user has repeatedly rejected claims that hands were fixed without real close-up evidence. Do not claim this is final.
- Flat winder remains on existing rod pedestal/holder; mount support can be refined to actually cradle/hang it. Model swap works, physical presentation can improve.
- Metal appearance in the simple test scene lacks real world reflection richness. Inspect in actual ocean lighting before claiming production visual quality.
- Drop follows tip horizontally while sinking; no full current/drift tackle physics. Keep sonar/hook/visual positions consistent if expanding this.
- Harpe near-surface leader presentation can need refinement: full 3.9 m leader versus available water/hand height. Verify gradual deployment and retrieval rather than assuming every hook is submerged immediately.
- Harpe bite timers are per hook, not keyed to a continuously tracked fish candidate. Candidate changes currently do not reset wait unless no eligible target.
- Full-crate partial batch handling uses existing per-fish acceptance; inspect message/total presentation if some fish are released.
- Fish attachment to rod during fight still follows existing mouth attachment. Pilk visualization is currently shown for unhooked tackle; refine pilk-on-hooked-fish presentation if desired.
- No full crab loop exists. Do not describe purchased stock or decorative deck props as deployed gear.

## Crab trapping: user's intended experience

The user wants working with hands on deck, NOT a helm menu or automatic catch generator:
1. Limited physical cages aboard (user suggested 12; treat as initial capacity proposal, not an already implemented universal number).
2. Pick up an actual cage.
3. Attach/tie rope and buoy.
4. Put bait inside.
5. Put/throw prepared cage overboard from deck.
6. Return to buoy, recover with boat's pot hauler/rope, bring trap aboard, inspect catch, transfer it, rebait/redeploy.
The 'no throwing' clarification explicitly referred to rod and harpe hooks. Do not automatically apply a charged cast to traps or infer a precise trap throwing UI without testing the physical deck workflow.

Existing footholds:
- resources/data/vessels/prebuilt/fishing_crab.json: Coastal Crabber, imported layout, shares hull lineage but user wants a distinct upgrade in appearance/use.
- resources/models/parts/coastal_fishing/: crab_creel.glb, pot_hauler.glb, pot_rope_buoy and bait/work shelter assets (verify exact filenames); original Blender sources under resources/models/_source/coastal_fishing/.
- BrickCatalog has crab_creel, pot_hauler, pot_rope_buoy, bait_work_table, crabber_work_shelter identifiers.
- Purchased supplies exist: crab_trap, rope_100m, marker_buoy, bait_pack.
- FishingSystem is largely LEGACY TRAWLING code, not a crab-trap controller. Don't repurpose its timed trawl-crate generator as traps.

## Recommended crab implementation (proposal, not completed work)

A. Model authority and persistence first
- Reuse vessel UUID/owner/company command/save seams. Add explicit trap instances with stable IDs; purchased quantity alone cannot track preparation, location or soak state.
- Suggested states: stowed -> carried -> prepared -> deployed -> recovering -> aboard; bait/rope/buoy attachment state separately recorded. A single authoritative state owns each trap, preventing duplicate deck/deployed instances.
- Suggested instance data: trap_id, vessel_id, owner_id, state, deck slot, attached rope/buoy IDs or quantities, bait amount/type, deployment world identity and position, bottom depth, deployed game time, catch contents, revision. Refine schema according to existing save contracts; no blind version bump or destructive migration.
- Treat reusable traps/rope/buoys differently from consumed bait. Authority reserves/consumes stock once, saves atomically, rolls back failure. Repeated commands/recovery cannot duplicate catches or gear.
- Deployed state must survive vessel despawn and reload. Match world seed/version/checksum before restoring coordinates. Future server owns catch decisions; local-only support must be explicit.

B. Deck interactions
- Use existing interaction pattern and character rig. Make staged preparation visible on the actual cage; disable deployment until required prep is complete.
- A carried cage is attached to hands, removed/reserved from its deck slot; don't also leave a duplicate cage in the pile.
- Use Blender grip sockets and fixed-length arm posing, not stretched arms or a camera-only first-person prop leaking into third person.
- Bound deck slots and footprint clearance; don't grant unlimited physical capacity from purchases. Let the crabber's authored equipment/capacity define support, not its display name.
- Preserve boat movement/local coordinates, collision and safe transition over railing. Avoid physics explosions from trapping rigid bodies inside hull collision.

C. Deployed trap and catch
- Sample actual seabed. Trap settles at bottom with correct orientation; rope connects trap/hauler/buoy, buoy follows water surface. Never float trap legs above bed or bury them in terrain.
- Use bounded/lazy soak evaluation based on game time and habitat, not per-frame simulation of every trap worldwide. Store deterministic decisions/seed and last evaluation time as appropriate; do not reroll by opening UI.
- Research Norwegian crab species/habitat and appropriate catch presentation when starting this stage. Don't invent current legal restrictions; gameplay parameters should be distinguished from real regulations.
- Integrate crab species/individual catch lots with existing crate/landing/value systems after checking their assumptions. Preserve size/weight/value information and physical inspection.
- Recovery should require being near that buoy, usable hauler and capacity. Account for partial hold capacity without losing or duplicating catch. Depletion/rebait/soak should have visible feedback.

D. Performance
- User strongly rejects 40-second startup, spawning the entire world for boat tests, and 10-second waits between nearby assets.
- Only detailed nearby trap/buoy/rope visuals and collisions. Durable deployed trap records remain cheap data; far catches evaluate lazily. Prioritize within ~1 km, then background/LOD work. No global per-frame ropes, fish or trap physics.
- Self-contained F6 crab showcase with actual crabber/player/gear, bounded water/seabed and isolated saves. No whole-world generation for this test.

E. Acceptance tests before calling it done
- Buy -> correct ship stock; cannot use another ship's supplies.
- Prepare -> attach rope/buoy -> bait -> deploy only from deck; missing prep rejects cleanly.
- Exactly one trap instance through every state; held/deployed objects aren't duplicated.
- 12-slot example fills; next trap cannot materialize beyond capacity.
- Actual seabed contact, rope endpoints, buoy waves; close-up and third-person captures.
- Soak catch deterministic across reload; save failure and command retry safe.
- Recovery transfers actual contents once; full hold handled; reusable gear returned; bait consumption once.
- Despawn/rejoin/redeploy, world mismatch, lost/abandoned gear ownership, remote unsupported path.
- First/third-person hand contact on moving boat; no helm fishing/trapping input bleed.
- Profile startup and local activation; no far-world continuous simulation.

## Reference outputs

C:/Users/noahs/Documents/Codex/2026-10-11/referenced-chatgpt-conversation-this-is-an/outputs/fishing-equipment/
- harpe-blender.png: authored flat winder render
- harpe-in-game.png: current held pose (review critically)
- pilk-in-game.png: actual imported pilk under water with ocean hidden
All original review images also archived in C:/Users/noahs/Pictures/machinescreenshots.
Latest source notes: docs/fishing-equipment.txt and SAVE_FORMAT.md.

Do not ask Noah to repeat the design above. Start by checking the current source, preserving unrelated work, and verify every claimed physical interaction in-engine. Be candid about unfinished presentation and unimplemented trapping.
