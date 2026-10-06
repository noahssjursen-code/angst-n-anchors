# Imported 3D models

## Mooring and fish landing kit (6 October 2026)

`_source/port_kit/build_port_kit.py` produces seven individual Blender/GLB models:
deck double bitt, quay tee bollard, deck roller fairlead, landing skid, separator,
pump drive/control cabinet and receiving trough. Default MooringPoint/MooringPost
models use the imports; alternate JSON paths and timber posts retain their
previous behavior. Model rebuild preserves the quay post interaction UI.

ImportedDraftVessel installs four discoverable inboard bitts and perimeter guides
per hull at explicit positions. RopeAnchor follows the bitt visual scale/rotation;
RopeLead is 1.12 m above the deck. The external mooring constraint now attaches at
that guide; the visual includes the fixed inboard run from the bitt. Unguided
MooringPoints retain their existing attachment. Keep the rope segment pool bounded
when prepending that run. No draft/save schema or authority protocol changes.
The supplied flat-wall fixture clears the line. This is NOT collision-aware
routing around arbitrary user structures or all shore heights/boat attitudes;
rope wrap over the roller is a simplified bend, not a contact simulation.

FishLandingPump loads four components at their common plant datum. The lower,
domed pressure/vacuum tank has profiled saddles, retaining straps, inspection
hatch and separate full-bore fish / narrow vacuum paths. The motor drives the
vacuum unit; fish does not pass through that motor. Preserve socket coordinates:
HoseConnection Godot (3.72,1.35,-.82), FillDatum (-3.28,1.10,0).
HoseDeparture defines the outward axial tangent; the runtime hose uses a continuous
swept surface with transported ring frames. Do not replace it with disconnected
cylinder segments or start the bend sideways through the coupling. Receiving
fill remains dynamic. CatchLot withdrawal, capacity and unload states are unchanged.
The footprint and throughput remain inherited game values, not engineering ratings.

`scenes/showcases/port_kit_showcase.tscn` isolates player saves. Capture mode checks
both hulls' guide locations, transformed/moving sockets, flat perimeter clearance,
maximum rope pool, tie/release, continuous hose endpoints, actual partial/complete
250 kg transfer and disconnect. Whole/pump/service/mooring captures show Godot
geometry. Ocean regression also exercises normal helm, seats, doors, walking,
HUD, drive/rudder and reset. Neither is full multiplayer or production-save acceptance.

Primary references: Trelleborg Bollard Application Design Manual page 5 inspected
for tee and double-bitt forms:
https://www.trelleborg.com/marine-systems/~/media/marine-systems/resources/guides-and-design-manual/downloads/bollardmanual.pdf
IRAS pressure/vacuum system technical description, diagram on page 4 visually
inspected for separate vessel, power unit, fish routes, air routes and controls:
https://www.senja.kommune.no/_f/p1/iaf10ce27-bf8f-4fff-9eb1-5b3492c3f458/12-teknisk-beskrivelse-av-pumpesystem-og-vurdering-av-fiskevelferdpdf.PDF
These inform the game models; neither manufacturer's ratings are applied.
Further work: physical rope routing/wrap, fenders, full port population, shore
tank artwork and service details. Functional passes are not final art acceptance.

## Harbour bulk crane (6 October 2026)

`_source/crane_kit/build_crane.py` produces nine independent editable Blender/GLB
pairs in `parts/crane_kit`: pedestal, slewing cabin/machinery, 30 m lattice boom,
luff-cylinder barrel and rod, paired 10 m rest hoist ropes, grab head and two jaws.
Paint and fixed glass, steel, rope and piston materials remain distinct. These
are internal equipment components, not nine new shipyard palette choices.

BulkCrane's existing default model identifier now selects BlenderBulkCraneRig.
Explicit alternate JSON model paths retain the existing ModelAssembler route;
ProvisionCrane and other unmigrated cranes are unchanged. No model identifier,
save schema, authority, slew/hoist control, cargo job or mass logic is replaced.
The current game pivots remain: slew Y at 2.29 m, boom hinge (-1.75,3.7,-.25)
relative to cabin, 30 m local -Z outreach, cable vertically below the tip.
The luff piston follows the actual boom attachment across its 8–72 degree range.
This is a game presentation with inherited reach/capacity, not a manufacturer
replica or validated engineering/reeving design. Detailed winch routing, sway,
collision/damage on moving boom/grab and full service access remain unfinished.

Only the single origin-centred cable mesh stretches with hoist length. The bucket
root stays unscaled and vertical; GrabScale scales the imported head, jaw pivots
and jaws once. Jaw pivots are 1 m below the hook; closed CuttingLip sockets meet
1.6 m below it, matching the existing gameplay pickup point. Right jaw opens
toward local +Z and left toward -Z. Preserve those signs and the authored inverse
6-degree closed-pose correction. Tests check outward movement as well as distance:
separation alone would also pass jaws incorrectly rotating through each other.
Update Blender's dependency graph before rotating newly created socket matrices.

Pedestal and slewing cabin/machinery retain solid collision proxies on layer 1.
Do not infer a walkable crane interior from the visible cabin. The seated NPC now
plays the shared character rig's `seated` clip; it no longer retries access to the
deleted character ModelAssembler. The authored seat avoids a duplicate primitive.

`scenes/showcases/crane_kit_showcase.tscn` isolates saves/network and checks scaled
jaw closure/pickup location, outward opening, cable attachment, boom reach, luff
cylinder endpoints and seated operator. Arrows slew/luff, PgUp/PgDn hoist, Space
opens/closes. `-- --capture <absolute.png>` writes whole/closed/open/cabin views.
The bulk kit's actual auto-load cycle also runs through this imported default rig;
both rendered scenes now exit without the old crane mesh/RID cleanup warnings.

Primary visual reference inspected: Liebherr CBG 360 general arrangement, page 2,
https://www.liebherr.com/shared/media/maritime-cranes/downloads-and-brochures/fts/fts_downloads_brochures/liebherr-sc-fts-cbg-360-datasheet.pdf
Its column, separate machinery enclosure, extended cab, service platform and
grab arrangement inform component separation; its dimensions/ratings are not
applied to the game's pre-existing lattice-boom crane.

## Fishing equipment and editable trawler example (6 October 2026)

Open `resources/models/examples/coastal_trawler_draft.json` through the builder's
Drafts > Open. It is a normal version-1 draft containing 60 reusable placements:
angled wheelhouse, crowned roof, consoles/helm, rising half-walls, stern working
opening, winch and two compact insulated deck tanks. It is not a merged boat
mesh or a commissioned fleet record. Tank spacing leaves a 0.9 m central route
behind the wheelhouse door. Side clearances are narrower; use the central route.

`_source/fishing_kit/build_fishing_kit.py` authors four separate .blend/.glb pairs:
fixed trawl-winch frame/motor, rotating drum with wound warp, insulated tank and
removable lid. The catalog exposes only Trawl winch and Insulated catch tank;
manufacturing components remain internal. `DrumPivot` is 0.95 m above the foot
plane; the exported drum axis is Godot Z. In this example yaw -90 places that
axis across the deck. `PayoutSocket` gives the rope's actual departure point.
Do not rotate the fixed bearings, motor, feet or mounting bolts with the drum.
Equipment placement checks all footprint corners against the deck polygon.

ImportedDraftVessel attaches the existing FishingSystem to placed winches and
CatchHoldComponent to tanks. The former consumes its existing trawling state
and animates the imported drum; the latter retains CatchLot inventory, capacity,
FIFO withdrawal and payload mass. Imported visuals bypass the old primitive
winch/hold presentation only on this path. Net and dynamic tow rope still use
the existing gameplay presentation; a realistic authored net, trawl doors,
gantry and working-gear deployment remain unfinished. Do not claim a complete
physical trawl simulation. FishingSystem currently fills the first discovered
hold; changing multi-hold distribution is separate gameplay work.

Each deck tank has a nominal game capacity of 600 kg. Its above-deck insulated
walls and closed lid do not imply a hole in the uncut hull deck. Named
PumpConnection/HoseDrop sockets meet the external flange; the existing dock
pump transfers real lots to ShoreRswTankBank. Opening lids, fill visuals and
animated lid handling remain future work. Tank metal/paint surfaces remain
separate; paint uses the existing wall region. No new fleet/server save schema.

`scenes/showcases/fishing_kit_showcase.tscn` inspects the assembly and deck.
`-- --capture <path.png>` verifies drum start/stop, hold discovery, imported hose
socket and real pump transfer, then renders two views. `-- --verify-draft`
checks real builder load/save/reload with temporary cache output. Headless
builder teardown currently reports thumbnail material/environment cleanup
warnings after assertions pass; ordinary rendered showcase and ocean verification
exit cleanly. The complete example also passes the normal isolated playtest's
F-to-helm, doors, walking, driving, steering, HUD and reset checks.

Reference accessed 6 October 2026: MacGregor's fishing deck-handling overview,
https://newproduction.macgregor.com/services/services-fishery-and-research/
distinguishes trawler machinery from purse-seine handling. This small winch is an
original game-scale design, not a dimensionally accurate manufacturer replica.
Further primary references and ship silhouettes are in docs/marine-integration-audit.txt.

## Default imported stern gear (6 October 2026)

`_source/stern_gear/build_stern_gear.py` authors three independent Blender files
and GLBs in `parts/stern_gear`: fixed transom shaft/support, 1.04 m four-bladed
cambered bronze propeller, and 0.95 m balanced rudder with stock. `ShaftAxis`
and `StockAxis` are named local datums. The propeller root rotates about Godot
Z; the rudder root about Godot Y. Never merge moving parts into the support.
Fixed bronze, stainless and bearing materials remain independent of paint;
support and foil expose `Paint_HullLower` and follow hull lower paint.

`mounts_14m.json` is the explicit hull-specific placement contract. This first
installation is an external transom prototype, extending aft of the 14 m deck;
it is not a recessed conventional stern aperture. The closed hull and deck
outline are unchanged. Do not claim hydrodynamic design validation. New hulls
need their own mount/clearance contract rather than multiplying these coordinates.

`TrawlerHullAsset.instantiate()` adds one `ShipDriveVisual` by default, including
the builder; `instantiate(false)` is reserved for the historical fit audit.
ImportedDraftVessel binds the visual to its existing propulsion/rudder components.
The gear is not an editable draft placement and is regenerated once on load.
Underwater gear meshes carry `stern_gear_visual` metadata and are excluded from
the hull convex collision and walk-deck triangles; no stale spinning collider.
Their collision/damage and exact hydrodynamic effects are not implemented.

The visual adapter never changes thrust, force points, fuel, steering or draft
data. Local throttle is negated into ahead-positive display state; zero fuel
stops the screw, neutral stops it, astern reverses it. The provisional visual
curve is linear to 240 RPM (not measured engine/shaft RPM). Rudder angle uses
the existing component's limit. This is a fixed-pitch presentation choice.
`apply_snapshot({throttle, steering, powered}, revision)` accepts confirmed state
with increasing revision, finite numeric controls and a boolean powered field.
Unbind `local_boat` before using remote snapshots. No multiplayer transport is
added by this adapter. Existing dry-fuel prop-wash physics remains separate.

Run `scenes/showcases/stern_gear_showcase.tscn` for actual imported-draft gear,
automatic reversing and rudder sweep. It isolates saves/network at startup.
Optional `-- --capture <absolute.png>` performs local/remote/stale/invalid-state,
dry-fuel telemetry, draft reload/no duplicates and imported swept-vertex clearance
checks, captures ahead/astern poses and exits. The ordinary isolated ocean
playtest also verifies the screw and rudder respond to actual F-to-helm controls.
Sources and rejected earlier mounts: `docs/marine-integration-audit.txt`.

## Ship model authoring contract

The current reference assets are `vessels/trawler_hull_14m/` and `parts/trawler_rails/`.
Editable Blender sources and deterministic build scripts live in matching `_source/`
directories. Older coastal-workboat and marine-kit experiments are not the accepted
construction reference. Do not copy their dimensions or model architecture by default.

### Coordinates and modular dimensions

- One Blender unit is one metre. Blender +Y points toward the bow and +Z points up.
  Exported Godot assets use -Z bow, +Y up, -X port and +X starboard.
- Apply object scale. Hull origin is the existing keel reference, deck height 2.92 m.
  A part's origin is its start connection at deck level; preserve `SocketStart` and
  `SocketEnd` empties in GLB export. Blender may append numeric suffixes to their names.
- The reference hull is 14 m long and 5 m wide. Its seven deck vertices are in
  `trawler_hull_14m/deck_outline.json`; `construction_edges.json` specifies its edges.
  Do not approximate those coordinates visually.
- Bow modules advance 1 m and move inward 0.5 m (atan(1/2), 26.565051177°), then
  advance 0.5 m and move inward 0.5 m (45°). Angles are measured from the longitudinal
  axis. Port and starboard are mirrored. Straight modules span 0.5 m or 1 m.
- Every deck corner is on a 0.5 m lattice. The current interior editor still has
  0.1 m picking and metre reference lines; those are not rail connection geometry.
  Perimeter pieces use exact endpoint placement and matching end-cut variants.
- Open rail height is 1 m; solid half-wall height is 0.75 m. Optional rising bow
  pieces increase height by 0.15 m per segment, totalling 0.75 m across five segments.
  Their bases remain on the deck. Do not raise entire pieces and leave gaps below.

### Seam and shape rules

Half-wall bodies are 0.08 m thick. Caps have their own material and matching miter
profiles. Adjacent pieces must share the exact same end-profile vertex positions,
including at the bow tip, stern corners and height transitions. Do not bevel mating
ends, hide gaps with posts, or merge the entire perimeter into one construction asset.
Use miter variants for direction changes and butt joins for collinear sections.
The railing builder verifies both end-profile vertex sets for all 37 joins.
Open rails use shared posts: create one post at a connection, not one per adjoining
panel. Their top/mid rails and toe plates retain their authored metal/paint colours.

### Paintable surfaces

`ModelPaint` matches material names, including Blender numeric suffixes:

| Material prefix | Editable region |
|---|---|
| `Warm white painted steel` on a half-wall | Wall panel |
| `Paint_HullUpper` | Upper hull |
| `Paint_HullLower` | Antifouling/lower hull |
| `Paint_Deck` | Deck |

Caps, rail metal and `Fixed_BootStripe` stay fixed. Do not use a whole-model tint.
Author actual separate material surfaces, including geometry cuts at hull paint
boundaries. Neutral paint textures preserve surface detail when changing hue.
Assign cloned surface overrides to each model instance so repainting one part does
not recolour another. Store linear RGB values by semantic region in each placement's
`colors` dictionary and hull-wide values in `hull_colors`. Do not serialize materials.

### Export and acceptance

Export only the selected asset in its active Blender scene, with applied transforms,
materials and connection empties. Keep a separate `.blend` and `.glb` per asset.
The railing manifest is authoritative; automatic miter variants remain individual
assets and must not clutter the user-facing palette. Expose two families: Railing
and Solid half-wall, plus a context-sensitive Rising bow toggle. Resolve the
length, side, angle, bow height and miter cuts from the hovered hull segment and
selected family/profile. Shared rail posts are automatic. Keep the hover preview
accurate; users must never decipher filenames or pick from manufacturing variants.
In Place mode, the toggle controls new placements. In Select mode, it reads and
edits selected bow assets, preserving paint and transforms. Show Mixed for mixed
profiles and disable the toggle for selections without bow parts. Keep the new-part
preference separate from selection state and save it with the draft.

Run the railing showcase to inspect flat/rising rails and half-walls (keys 1–4).
Verify the exported GLBs' sockets, shared heights, model dimensions and material
isolation. Test manual placement, selection/repainting, erase, and saved draft reload.
Render close views of bow and stern joins, not just a distant whole-boat image.
Keep screenshots distinct from Blender source and game-ready exports.

### Builder interaction contract

- Select uses visible mesh triangle picking, with a nearest-hit result. Never fall
  back to a nearby deck cell or edge when clicking empty space. Rail posts select
  their owning panel. Box selection includes parts whose projected bounds intersect
  the rectangle (including obscured parts); dragging works in either direction.
- Plain click/box replaces selection; Shift-click toggles, Shift-box adds. Empty
  click clears. Ctrl+A selects all, Escape clears selection before closing the app.
- Highlight the actual selected mesh surfaces with a translucent material overlay
  and show a count. Never draw per-part bounding rectangles. The drag marquee
  is visible only while dragging in Select; Place and Erase drags must not show it. Group paint affects selected wall
  panels while fixed caps and rail materials stay untouched.
- Delete removes the selection. Erase clicks/drags remove hit parts. Ctrl+Z undoes
  part placement/removal/paint; Ctrl+Y or Ctrl+Shift+Z redoes. A placement/erase drag
  is one undo operation. Loading a draft resets selection and part undo history.
- Hide perimeter-irrelevant legacy rotation/layer controls. Test press/move/release
  and real Godot GUI input routing, not just direct calls to placement methods.

The imported parts editor saves versioned authoring drafts separately from legacy
brick layouts. It does not yet commission these designs into gameplay vessels.

### Storey controls

Floor up/down (Page Up/Down or ]/[) move the edit plane by the standard 2.2 m
wall height: deck 2.92 m, floor 1 at 5.12 m, floor 2 at 7.32 m. They do not step
by grid cells or generate floor slabs. Move the grid, camera target and player
reference with the active storey. End any active run and clear selection on changes.
Show lower storeys for context, hide higher storeys, and restrict click/box/select-all
and erase to the active storey. Placement keys and rail-joint keys include elevation;
stacked parts must never replace each other. Crossing checks and miters stay on
one storey. Save active_floor (optional in version 1); older drafts default to deck.
Shift + Page Up/Down moves by one 0.1 m vertical cell. Store `cell_offset`
(0–21, optional; legacy default 0) alongside active_floor. Normalize at 22 cells;
clamp the overall range from deck to floor 24. Whole-floor controls preserve
the fine offset. Grid, reference, picking and camera follow the actual plane.
Verify with `tests/shipyard_floor_test.tscn`.

### Floor and roof surface kit

`surface_tiles` contains 109 individual Blender source/export pairs: full 0.5 m
panels, exact triangular boundary fillers and three roof-edge profiles. Use
`_source/surface_tiles/build_tiles.py` to regenerate. `ShipSurfaceKit` selects
and places these imported assets; it does not generate runtime mesh vertices.

Palette exposes only Floor and Roof. Click a closed 0.5 m lattice outline;
Enter or clicking its first point finishes, Backspace removes a point, Esc/RMB
cancels. Preview the actual assembled models. Axis-aligned, 1:1 (45 degree),
2:1 (26.565 degree) and rotated equivalents are supported, including concave
outlines. Reject self-intersections, unsupported slopes and overlapping surfaces
at the same elevation. Outlines are limited to 64 vertices within the hull deck.
Each drawn patch is selected, painted, erased and undone as one assembly; its
individual model pieces remain reusable assets. Holes and post-placement outline
editing are not yet implemented. Draw one continuous roof for a continuous fascia;
adjacent independent roof patches do not merge their overhangs.

Roof: bottom at active plane, top +0.10 m, outward eave 0.15 m from drawn
outline/wall centreline (0.10 m beyond a 0.10 m wall's outer face). Exterior
fascia has a 15 mm chamfer. No bevel on mating infill faces. Imported start/end
miter shape keys join the edge profiles, including angled corners.
Floor: finished top at active plane, underside -0.10 m. On the original hull,
raise the plane one cell before laying an added floor, so its underside meets
the hull deck. Place walls at the same finished-floor plane. For intermediate
floors the slab below that plane occupies the top 0.10 m of the storey below;
do not claim a full 2.2 m clear height beneath it. Roof caps instead sit above
wall tops. Storey buttons preserve the fine-cell offset.

Materials expose `surface`, `fascia`, `underside` independently; colours are
per-instance. Persist outline, asset family, elevation and colours in draft
records; validate before replacing any current work. No gameplay collision or
commissioning is added by this authoring kit.

The visual basis is the near-flat workboat roof, continuous fascia and separate
equipment visible in ARESA 2500 S, Damen Stan Tug 1606 and Metal Shark pilot boat
photos inspected on 2026-10-05. Our thickness and eave dimensions are kit choices,
not measurements from those photographs. Optional crown is a continuous cross-roof profile, evaluated through Blender-authored
polynomial morph targets shared by infill and mitered edge models. Crown rise is
min(0.12 m, half-width * 0.08). Flat remains the default. Extended overhang can
face bow, stern, port or starboard, growing from 0.15 m to 0.45 m on the chosen
side with matching corner offsets. Preserve `crown` and `visor_direction` in
drafts. Both controls work on new roofs and selected roof assemblies. These
are reusable ship-construction settings, not trawler styling presets. Hatches
and roof equipment remain separate future work.

Run `scenes/showcases/surface_tiles_showcase.tscn` (optional `--verify-roof`)
for coverage, imported miter-profile matching (including crown and overhang), actual input drawing/preview,
independent paint, draft round-trip and erase/undo checks plus rendered views.
`scenes/showcases/surface_library_showcase.tscn` displays four different footprints
from the same reusable module library, without a hull dependency.

### Draft and placement UX

The imported builder has a Drafts menu (New, Open, Save, Save As), Ctrl+S,
Ctrl+Shift+S and Ctrl+O. First Save asks for a filename; subsequent Save uses that
file. Default folder is `user://shipyard_drafts`; the legacy single-file draft can
still be opened from the menu. The title shows the draft name and dirty state.
Write to a temporary file, keep a `.bak` when overwriting, and replace the target
only after a successful write. Validate the entire incoming draft before replacing
current work; unknown parts or malformed fields must not cause silent partial loads.
New/Open/Back/window-close protect unsaved work with Save/Discard/Cancel.

Esc, a right-click without dragging, and the visible End run button all cancel the
current wall anchor and retain the chosen family. A right-button drag still orbits.
Handle placement Escape before GUI focus consumes it. Starting elsewhere must never
require selecting a different part. Keep help, tool hints and palette tooltips aligned
with actual controls. The imported builder has no legal-registration picker or gate.
Run `tests/shipyard_ux_test.tscn` for named file persistence, backups, invalid loads,
unsaved guards and focused cancellation checks.

## Structural wheelhouse kit

`parts/wheelhouse/manifest.json` contains 17 individual Blender-authored assets;
editable sources and the generator are in `_source/wheelhouse/`. The palette adds
only Wall, Door and Window. Never expose angle variants as separate library choices.

- Walls are 2.2 m tall and 0.10 m thick. Straight runs are 0.5 or 1 m; diagonal
  wall/window runs are (0.5, 1) and (0.5, 0.5) m, mirrored and quarter-turned.
- Doors have an 0.82 m opening and 2 m headroom. Their 45-degree module uses a
  (1, 1) m diagonal so the opening is never squeezed into a narrow wall section.
- Windows have a 0.95 m sill and 2.05 m head, real transparent glazing, separate
  fixed frames and rubber gaskets. Paint changes panel skins, not glass/hardware.
- Wall skins extend fully to their end sockets. No cover columns, setbacks or
  bevels on mating edges. Blender-authored MiterStart/MiterEnd shape keys shear
  only end-profile vertices; weights derive from adjoining wall directions.
  Straight seams use zero shear; corners share the exact same cut plane and
  profile. Keep glass, openings and door hardware outside these deformations.
  Create each key from Basis explicitly (from_mix=False), never another end key.
  Picking must evaluate these shape keys, not use the undeformed GLB triangles.
  The showcase checks all 14 actual imported mating profiles within 0.1 mm.
- Structural placement is two-click: start, aim/end. Start coordinates snap to
  0.5 m; choose the nearest authored endpoint/angle, then continue from that end.
  Escape ends the run. Reject off-deck, crossing and partially overlapping walls.
- DoorLeafPivot now uses ShipPartState for animated local-preview interaction and
  authoritative snapshots, with draft persistence. These remain authoring models, not gameplay-operable doors or
  commissioned vessel collision/navigation. Roof and floor slabs are supplied by the separate surface_tiles kit;
  the builder can author walls on upper storeys using the floor controls.
- The builder shows the game's NpcBase character at measured 1.80 m height, feet
  at deck height. Users can hide it or move it by clicking the deck. It is a scale
  aid, excluded from selection, ship placements and saved ship assets.

Run `scenes/showcases/wheelhouse_structural_showcase.tscn` for an editable 14-part
angled wheelhouse shell. Pass `-- --verify-wheelhouse` to validate GLB heights and
sockets, two-click placement, bounds/overlaps, door opening, paint, draft reload,
and delete/undo, capture the scene and exit.

## Earlier pipeline notes

Game-ready 3D artwork lives here. This is separate from `resources/data/models/`
and `resources/data/meshes/`, which contain the existing procedural JSON assets.
The trawler hull and railing kit are connected to the shipyard library, perimeter
placement, paint controls and versioned authoring drafts. Gameplay vessel spawning
is not yet migrated to these imported designs.

## Layout

```text
resources/models/
  vessels/<asset_id>/      Complete ship or hull visuals: <asset_id>.glb
  parts/<asset_id>/        Modular cabin, railing, mast, equipment, etc.
  props/<asset_id>/        Other imported world objects
  _source/<asset_id>/      Editable .blend files and source artwork
```

Use lowercase snake_case asset IDs. Keep each model's external textures beside
its GLB (for example, `<asset_id>/textures/`). GLB can also embed textures.
Record third-party asset authors, source links, and licenses alongside the asset.
The `_source/.gdignore` prevents Godot from importing Blender working files;
these files can still be tracked by Git. Track exported models and their Godot
`.import` sidecars; generated `.godot/` cache remains ignored.

## Blender to Godot workflow

1. Author in metres and apply object rotation/scale before export. Preserve
   intentional articulation pivots for moving parts.
2. Export glTF 2.0 binary (`.glb`) into the appropriate asset folder. Export only
   intended asset objects, not authoring cameras or lights. Use exportable PBR
   materials; bake Blender-only procedural shading when needed.
3. Check the imported result in Godot: +Y is up, bow is -Z, stern +Z, port -X,
   starboard +X. Verify actual dimensions rather than trusting legacy hull IDs
   or display labels. Blender and Godot use different up axes.
4. For an editor brick replacement, centre the visual on its footprint AABB,
   matching `BrickCatalog.create_visual()`, and match its actual `size_m()`.
   For a full hull, align the imported visual with the existing boat's origin,
   waterline and deck height; do not assume a generic floor-centred pivot fits.
5. Add gameplay in a Godot wrapper or the existing construction code. Avoid
   editing generated imported scenes directly; reimport can replace them.

Start with visual-only exports. Keep moving-body collision simple (primitive
or convex shapes), with separate walkable deck/interior collision as required
by the existing BoatBody/WalkDeck system. Do not add an independent rigid body
inside an existing BoatBody or automatically use the detailed render mesh for
all collision. Doors, helm interaction, lights and cargo need their own runtime
components and agreed node/pivot conventions.

## How the current shipyard works

- `scripts/apps/shipyard_brick_editor.gd`: standalone editor at
  `scenes/apps/shipyard_brick_editor.tscn`. Builds a frozen preview hull through
  `HullRegistry.build_hull()`, then maintains brick previews through
  `BrickCatalog.create_visual()`. Ghosts and thumbnails also use that factory.
- `scripts/ship/brick_catalog.gd`: brick definitions and procedural visual
  factory. This is the natural shared insertion point for imported part visuals.
- `scripts/ship/deck_fitout.gd`: calls the same visual factory at runtime, then
  adds mass, collision and compliance-approved functional components. Some
  components depend on existing visual structure, so interactive replacements
  need an adapter rather than a blind mesh swap.
- `scripts/ship/vessel_spawn.gd`: resolves an owned vessel record, validates its
  registration/layout, creates a BoatBody hull, applies fitout and identity.
  Its explicit scene-path route accepts `.tscn`/`.scn` with a BoatBody root;
  a raw GLB is not currently a drop-in vessel template.
- The editor saves prebuilt metadata and brick layouts as JSON under
  `resources/data/vessels/prebuilt/`. JSON can continue describing identity,
  placement and gameplay even when geometry comes from Blender.

## Recommended first experiment (not implemented yet)

Try one non-interactive imported part first, such as a railing or cabin shell.
Add an optional model-scene reference to its brick definition and instantiate
it through `BrickCatalog.create_visual()`, retaining the procedural fallback.
Check dimensions, paint/ghost materials, palette thumbnails, collision and
runtime placement. Shared materials must not be modified globally for ghosts
or per-instance paint. Keep collision and footprint consistent with the mesh.

For a complete ship, a separate experiment can place a GLB visual beneath the
existing BoatBody while retaining its physics and functional equipment. Start
with an isolated showcase before changing fleet saves, stock ships or network
records. Match hull shape/size to the physics profile and deck grid; a large
shape change needs collision and buoyancy work too. A later full replacement
of brick-based construction would also need equipment placement and compliance
data independent of the brick layout.

Godot 4.6 reference:
https://docs.godotengine.org/en/4.6/tutorials/assets_pipeline/importing_3d_scenes/available_formats.html


### Interior models and state contract

`_source/interior/build_interior.py` creates 53 individual Blender source/export
pairs under `parts/interior`: 12 directed console sections (both interior sides;
0.5/1 m straight and 26.565/45 degree diagonals), two seats, a display, and separate
fixed/moving wheel and throttle components plus their assembly socket assets.
Console datum is the wall centreline, counter top 0.85 m, usable depth 0.55 m,
rear offset 0.05 m; cabinet 0.78 m high. Mating faces have no bevel. Counter and
cabinet end morph keys share the same miter plane. Console records have a separate
slot namespace, so placing under a window never replaces that window. F flips
which side of the directed run contains the console. R rotates free interior
items in 45 degree increments. Equipment placement checks the console footprint,
mounts at +0.85 m and remains selectable on its originating editing floor.

Wheel base and rotor, throttle housing and lever are separate GLBs/.blend files.
`BrickCatalog.create_visual` assembles components under `WheelPivot` and
`ThrottlePivot`; do not merge these into the counter. Doors retain DoorLeafPivot.
Seats expose SeatSocket and ExitSocket for future character attachment and exit
validation. Seats currently expose occupancy state; actual player seating/poses
and collision/navigation are not implemented by this kit.

`ShipPartState` is the shared presentation consumer. `request(action,value)` emits
`request_sent`; remote mode does not mutate the confirmed state. An authority
validates ownership/range/occupation rules externally and supplies a complete or
partial `apply_snapshot(state,revision)` update. Only increasing revisions are
accepted; numeric values must be finite, booleans typed, unknown fields rejected.
Steering/throttle clamp to [-1,1]. The consumer animates wheel spin, lever travel
and door hinge without reading input directly. Occupied/powered flags and the
state_applied signal are available for other systems; these flags alone do not
implement passenger attachment, screen simulation or gameplay authority.

The builder explicitly enables local preview authority and offers selected-item
interaction plus steering/throttle sliders. Door open is animated and saved.
`bind_local_helm(BoatController)` is a read-only adapter for confirmed local boat
control output; it uses get_helm_visual_state(), including the propulsion sign
conversion, never feeds visual interpolation back into vessel physics. A server
transport can feed the same snapshot method; no multiplayer transport or imported
vessel commissioning is claimed here. Permission checks belong to the authority,
not to imported meshes. Do not add networking code inside Blender assets.

Run `scenes/showcases/interior_showcase.tscn -- --verify-interior` for actual GUI
placement under chamfered windows, all four imported console joints within 0.1 mm,
separate pivots, local requests, remote request waiting, stale/invalid snapshots,
local BoatController binding, animations and draft round-trip.


### Seating and variable-length benches

Chair backs are upright (no authored X tilt) and meet the seat cushion. Preserve
that orientation unless explicitly redesigning the seating ergonomics.
`cabin_bench_straight` is the only palette family for 32 Blender bench variants:
0.5 through 6 m straight lengths in 0.5 m steps, plus both 26.565 and 45 degree
diagonal directions, each with a mirrored seating side. Continue another section
for longer runs. Bench runs use the same two-click draw/continue and F side flip
as consoles, with a separate bench slot namespace and bench-only joint fitting.
They coexist with wall/window records without replacing them.

Seat cushion top is 0.625 m; back top 1.245 m. Upholstery and metal support style
match the standalone seats. Rounded cushion cross-sections are extruded along
the run; never bevel mating end faces. MiterStart/MiterEnd affect only cushion,
back and support-beam ends. Pedestals and feet remain undeformed. Named seat
sockets are future attachment points; multi-passenger occupancy is not implemented.
Seat upholstery paint applies to the whole selected bench section while metal
supports retain their finish. `scenes/showcases/bench_showcase.tscn` verifies an
actual drawn 2.5 m run and 1 m right-angle return, matching imported cushion/back/
beam profiles within 0.1 mm, and draft round-trip; it also shows both corrected
standalone chair backs. Pass `-- --verify-bench` to render and exit.

### Isolated builder playtest

The builder's **Playtest boat** button snapshots the current in-memory draft to
the OS cache and launches a separate Godot process into
`scenes/showcases/shipyard_playtest.tscn`. It never saves/commissions the draft,
changes the parent scene, or disconnects the parent's server. Closing the child
returns to the original builder. One test child at a time; temporary snapshots
are consumed on child startup. The normal WalkingHud, ShipHud, GameMenu and BoatCamera are retained. F targets
the wheel or a helm chair to drive, passenger chairs/bench sockets to sit, and
doors to open/close. Helm chairs retain their seated eye position and occupancy
state while activating the same BoatController and ShipHud as the wheel; leaving
the chair releases helm control. Seat roles come from catalog style, not proximity
to a wheel.
F or Escape leaves the helm/seat; V switches the helm/seat camera. Home resets;
the normal Escape menu offers Return to builder. There is no global H-to-drive
shortcut. A draft needs an installed wheel or helm chair to be driven. Falling overboard recovers the player; leaving
the 1.5 km test radius resets the vessel. Startup and reset set the local clock
to noon and apply clear visibility, 25% cloud, 6 m/s wind and sea state 0.35
through WeatherLighting, which drives the same FFT waves and buoyancy queries.
These settings affect only the child test process.

`ShipyardPlaytestMode.active()` must work **before autoload initialization**.
The explicit command-line flag (or the showcase scene argument for F6) disables
captain persistence, server configuration writes, settings writes, network-client
creation, and world gateway session startup. Keep normal gameplay HUDs and interactions
enabled; isolation is not a reason to replace the game UI. Never replace
these startup guards with a late scene-level "disconnect": that can already have
cleared the active captain or connected to a server. Exported builds must include
the showcase scene and its imported assets.

`ImportedDraftVessel` uses the same imported-part assembly, paint, authored morph
joins and state adapters as the editor. Dynamic hull collision is convex;
player-facing hull and part triangles live on BoatBody's separate WalkDeck
AnimatableBody, with moving door leaf colliders following the Blender hinge.
Never attach concave shapes to the dynamic RigidBody or replace the pointed deck
with a rectangular walk slab. Runtime door changes must not mutate draft records.

Physics and cameras reuse CatalogHullVessel's component installation and the
existing BoatController, StripBuoyancyComponent, hydrodynamics, propulsion, rudder,
thrusters and BoatCamera. This first test uses a **provisional 58 t / 300 kW hull
profile**. Per-part mass, exact imported underwater hydrostatics, selectable
engines, replicated seat occupancy/character sitting animation, and production
fleet/server commissioning remain
separate work. Do not describe this sandbox as a completed fleet migration.

Verification: run the showcase with `-- --shipyard-playtest <snapshot.json>
--verify-playtest` for deck walking, imported-part count, animated door collisions,
snapshot immutability, isolation, pause, real F-to-helm/seat input, normal HUD,
drive/turn, coasting on deck, and reset. The verification fixture needs a wheel or helm chair; a chair takes precedence
so the full drive/steering/exit sequence exercises seated helm control.
Optional `--capture <absolute.png>` saves a real rendered third-person view.
Run `tests/shipyard_playtest_launch_test.tscn -- --shipyard-playtest
--verify-playtest-launch` to exercise the actual button, child process, duplicate
launch guard, successful child verification and unchanged parent unsaved draft.


### Door passage and wave motion

Runtime F interaction uses `ShipPartState.request_door_from(player_position)`.
It chooses signed `door_swing` (+1/-1) in the closed Blender hinge frame so the
leaf opens away from the player regardless of the direction the wall was drawn.
Retain that sign while closing/reopening until fully shut; never flip an already
open leaf across the doorway. The sign is a validated state field suitable for
authority snapshots; requests still do not apply optimistically in remote mode.
Opening travel is 110 degrees. The full leaf, jambs and header collide; tiny
Blender meshes named `Door hinge*` and `Lever handle*` are visual hardware and do
not contribute player passage collision.

Part-state animation runs on the physics clock (priority -20), followed by
imported moving-collider synchronization (-10), then player movement. Imported
WalkDeck explicitly opts into `align_player_capsule`: the player's capsule aligns
its axis and centre with the supporting vessel's deck normal. Camera and movement
remain world-upright. Leaving that deck restores the normal upright capsule;
ordinary world/legacy collisions do not opt in. Do not fix rolling doorways by
removing the door collider, shrinking the character, or widening the models.

The test hull uses 58 t displacement at 1.6 m design draft, roll/pitch gyradii
0.40/0.32 of beam/length, critical heave damping (ratio 1.0), and angular damping
0.9. This increases rotational inertia and suppresses springy response while
retaining the real waves and shared buoyancy/steering components. These are still
provisional handling settings, not per-part weight simulation.

`tests/shipyard_door_motion_test.tscn -- --shipyard-playtest` checks 20 actual
collision sweeps: both door drawing orientations, both approach sides, level,
+/-12 degree roll and combined +/-8 degree pitch. Closed doors must block;
opened doors must pass the unchanged 0.7 m diameter / 1.8 m player capsule.

### Multiple imported hulls and cargo hatch kit (6 October 2026)

ImportedHullCatalog is an authoring/playtest descriptor, separate from the legacy
owned-fleet catalog. Keep existing trawler_hull_14m draft IDs stable. hull_24x8 is
24 x 8 m, deck 3.6 m, provisional 180 t / 2 m draft / 700 kW. Never infer this
from a legacy hull's 2x dimensions or scale the metre-based equipment with it.
Builder loading validates the complete draft before replacing hull/grid/records.
Floor controls use each hull's deck datum. Runtime physics and spawn searches use
that same descriptor; gear mounts come from mounts_24m.json. The shared propeller
hardware is a prototype installation, not validated real-world propulsion sizing.

The cargo platform has a REAL 5 x 8 m opening at x +/-2.5, z +/-4; tank top y=1.6.
Side walkways are 1.5 m before the coaming's small outboard projections. Grid lines
and lower-deck placement exclude the opening. WalkDeck ray tests verify the tank
top and side deck separately. Do not replace these triangles with a full deck slab.
The collision hull remains convex, separate from player-facing walking surfaces.

Separate Blender source/export assets: hull_24x8, hold_coaming_5x8 and
hatch_cover_5x4. Coaming sits at deck level; two covers sit at y=deck+0.74 and
z +/-2. Placement snaps to these authored seats. Covers are individually selected,
erased, saved, painted and reloaded. Lifting eyes/LiftPoint are future crane hooks;
there is NO powered cover operation, inventory, cargo authority or crane transfer
implemented by these visuals. The later bulk package must integrate real records.

Hull perimeter corners use the 0.5 m lattice, 2:1 then 1:1 bow runs. Existing rail
cross sections are reused; four extra half-wall miter variants have their own
Blender sources and GLBs. Flat perimeter only on this platform; Rising bow is
hidden until a matching profile is authored. Do not stretch the trawler's rising
parts to fit a different bow. build_perimeter.py loads only shared authoring
primitives from build_rails.py and verifies the mathematical miter rings.

Load resources/models/examples/coastal_cargo_draft.json through Drafts > Open.
It has 87 separate placements, an aft bridge and two central covers. Review with
scenes/showcases/cargo_kit_showcase.tscn: 1 whole boat, 2 uncover hold (visual review
only), --capture <png> captures both. --verify-draft checks cross-hull switching,
87 records, floor/cell offsets, cover selection, invalid-load preservation and
save/load. The normal shipyard_playtest supports both installed hulls. Production
fleet commissioning remains outside this draft sandbox.

### Divided bulk hold (6 October 2026)

bulk_divider_5m is an individual Blender bulkhead, not a new baked ship. It fits
the existing hull_24x8 opening and coaming at [0,3.6,0]; HoldForward/HoldAft sockets
place two 5 x 3.9 x 2.7 m inventory compartments. The upper lip is y=4.3 and the
tank top y=1.6. Each has a provisional 40 t payload limit. The separate divider
slot must coexist with the coaming at the same origin. Do not overwrite one with
the other in builder selection or save keys. The bulk example has 87 records,
forward hatch removed for loading and aft cover installed.

ImportedBulkHold extends the existing BulkHoldComponent inventory/transfer API.
It replaces the old fake pit/coaming presentation with the real Blender hull and
divider, places dynamic ore fill at the tank top, and registers cargo tonnes as
kilograms in BoatBody's existing mass ledger. Dynamic ore is presentation only;
its changing triangles are excluded from static WalkDeck collision. Cargo states
round-trip with the existing BulkHoldState dictionary API. Builder drafts remain
construction-only; this does not commission a ship or persist an active playtest.

Installed hatch covers block accepting/withdrawing lots and crane target selection.
Access is determined when the runtime draft is assembled. Removing a cover in the
builder and relaunching opens it; powered hatch interactions remain unfinished.
For compact imported holds, auto loading aims centrally, waits until the real grab
mouth enters the opening with a 0.7 m edge margin, and releases at the actual mouth.
An alignment timeout stops the operation instead of teleporting cargo to its target.
Existing legacy open holds retain their former crane positioning behavior.

bulk_kit_showcase.tscn verifies separate inventories, closed-hatch/mixed-commodity
rejection, cargo mass, state round-trip, actual crane lot/drop conservation, and
(with --verify-auto) a full existing operator load cycle. --verify-draft checks
builder save/load. The default crane is now the Blender kit described above;
the former crane cleanup warnings no longer occur in the rendered verification.
OreMound remains an unlimited stockpile source, not finite shore inventory.
Never describe this as completed harbour/economy migration.
