# Imported 3D models

## Harbour environment kit (6 October 2026)

`_source/harbour_kit/build_harbour_kit.py` authors six independent Blender/GLB
pairs: 2 m quay coping, hollow arch fender with flange anchors, quay ladder,
7.5 m light pole, 2 m drain grate and 12 x 18 m industrial warehouse shell.
Exports live in `parts/harbour_kit`. The source files remain editable; the
warehouse is an exterior shell, not a modular building editor or usable interior.

Kit coordinates: X along quay edge, Blender +Y towards water, Z=0 at pavement;
exported Godot -Z faces water. Existing berth terminal nodes instead use +Z
seaward. HarbourEnvironmentKit deliberately converts this convention: do not
reverse pier-to-apron connections using the vessel bow convention. Coping is
flush, with a 12 mm visual clearance over the supporting deck and 15 mm outward
clearance to avoid overlapping pier faces. Small construction joints are
intentional. Repeated coping, fenders and grates use MultiMesh batches.

The visualizer preserves all berth records and equipment locations. It adds
marked quay access lanes joined to a coastline-following apron lane, uses a
lit world-scale asphalt material, and substitutes the imported shell only when
an apron plot has no saved BuildingBlueprint and is large enough. It never
scales door height to fit a plot. Named LoadingDoor/PersonnelDoor/Light sockets
provide future attachment locations. Warehouse shell and poles have simple
solid collision; ladders do not yet support climbing, doors do not yet open,
fenders do not simulate compression, and poles do not yet emit runtime lights.
Fine grate/coping details use the underlying continuous walking surface.

Port Showcase now preserves the exported seed, starts at noon and collapses
the data panel (H). T toggles the real player on a quay access lane and enables
nearby terrain collision while walking. Direct F6 runs are isolated from captain
saves through ShipyardPlaytestMode. R rebuilds, -/= selects another seed, and
the existing size/region controls remain. The broader zoning/port-profile
redesign is still pending; see `docs/harbour-rebuild-plan.txt`.

Rendered regression: `tests/harbour_environment_test.tscn -- --shipyard-playtest
--capture` checks the four imported shells, original three terminals, batched
fenders, walk/fly switching, real-player travel across the quay/apron join and
solid closed warehouse frontage. Captures are saved under Noah's machine
screenshot archive. Foundation coverage remains covered by
`tests/port_surface_collision_test.tscn`. This is not all-seed layout, maximum
port performance, multiplayer, ladder interaction or full building acceptance.

Primary design references (product descriptions, not engineering ratings):
https://www.trelleborg.com/en/marine-and-infrastructure/products-solutions-and-services/marine/marine-fenders/fixed-fenders/arch-fenders
https://www.trelleborg.com/en/marine-and-infrastructure/products-solutions-and-services/marine/marine-fenders/accessories/ladders
The arch form, flange mounting and separate access hardware inform game
geometry; no manufacturer performance or certification is implied.

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

Paint finish (7 October): `crane_kit/paint_bake.py` authors metre-space staining,
localized panel-edge/cylinder-collar chips and fine surface relief in Blender.
Cycles bakes base colour, roughness and tangent normals into the individual GLBs;
no runtime world-space rust shader, so slew/luff movement carries the finish.
Intact paint is dielectric. Glass, cables, dark steel and polished piston rods
retain separate materials. Bake-only coordinate empties are removed before export.
Equal paint slots MUST be compacted after joining: the boom remains three surfaces,
not one draw surface per lattice member. Triangle counts and all pivots are unchanged.
Maps use 1024px for large parts, 512px for jaws/head and 256px for barrels,
with mipmaps and committed VRAM-compressed import settings (normal maps explicit).
Do not replace these settings with uncompressed automatic imports. Source blends
pack their own maps; purge orphan meshes/materials/images between generated parts.
Actual close-up and daylight port renders plus the existing loading-cycle and
articulation checks cover this finish; wear is artistic, not a corrosion simulation.
Primary maintenance reference: https://www.liebherr.com/en-us/maritime-cranes/customer-service/services/inspections-4433279
Texture import contract: https://docs.godotengine.org/en/4.6/classes/class_resourceimportertexture.html

`_source/crane_kit/build_crane.py` produces eleven independent editable Blender/GLB
pairs in `parts/crane_kit`: pedestal, slewing cabin/machinery, 30 m lattice boom,
luff-cylinder barrel and rod, paired 10 m rest hoist ropes, grab head, two jaws and separate grab-cylinder barrels/piston shafts.
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
replica or validated engineering/reeving design. Hoist feed wires now run from an exposed drum to the moving boom heel, then
along the boom to the tip. Exact sheave contact/reeving, sway and moving boom/grab
collision remain simplified. The ladder/guard/access artwork does not add climbing.

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
The afternoon refinement also tests both grab-cylinder endpoints at five opening
fractions and three scales, plus feed-wire endpoints at three boom angles.
Primary visual comparison: Liebherr floating crane brochure page 2 for machinery,
hoist routing and service access,
https://www.liebherr.com/shared/media/maritime-cranes/downloads-and-brochures/fts/fts_downloads_brochures/liebherr-floating-cranes-cbg-300-350.pdf
The game keeps its existing two hoist lines and luff hydraulics, not that
manufacturer's four-rope arrangement or engineering ratings. Grab power supply
umbilical and exact sheave contact remain to be modeled.

Primary visual reference inspected: Liebherr CBG 360 general arrangement, page 2,
https://www.liebherr.com/shared/media/maritime-cranes/downloads-and-brochures/fts/fts_downloads_brochures/liebherr-sc-fts-cbg-360-datasheet.pdf
Its column, separate machinery enclosure, extended cab, service platform and
grab arrangement inform component separation; its dimensions/ratings are not
applied to the game's pre-existing lattice-boom crane.

## Fishing equipment and editable trawler example (6 October 2026)

Open `resources/models/examples/coastal_trawler_draft.json` through the builder's
Drafts > Open. It is a normal version-1 draft containing 67 reusable placements:
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
It has 93 separate placements, an aft bridge and two central covers. Review with
scenes/showcases/cargo_kit_showcase.tscn: 1 whole boat, 2 uncover hold (visual review
only), --capture <png> captures both. --verify-draft checks cross-hull switching,
93 records, floor/cell offsets, cover selection, invalid-load preservation and
save/load. The normal shipyard_playtest supports both installed hulls. Production
fleet commissioning remains outside this draft sandbox.

### Divided bulk hold (6 October 2026)

bulk_divider_5m is an individual Blender bulkhead, not a new baked ship. It fits
the existing hull_24x8 opening and coaming at [0,3.6,0]; HoldForward/HoldAft sockets
place two 5 x 3.9 x 2.7 m inventory compartments. The upper lip is y=4.3 and the
tank top y=1.6. Each has a provisional 40 t payload limit. The separate divider
slot must coexist with the coaming at the same origin. Do not overwrite one with
the other in builder selection or save keys. The bulk example has 93 records,
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


### 32 x 10 m platform (6 October afternoon session)

`_source/hull_32x10/build_hull.py` authors a new hull with broad tank bottom,
rounded bilges and a raked underwater transom. The deck is exactly 32 x 10 m at
4.5 m, with shoulder at z=-8, 2:1 run to (+/-2,-14), and 1:1 stem to (0,-16).
All deck corners remain on the 0.5 m lattice. build_perimeter.py reuses the
existing independent angle/miter assets and verifies every adjacent profile;
no hull-wide wall mesh or extra palette variants are needed.

The real opening is 6 x 12 m, tank top 1.4 m, with 2 m side decks before coaming
projections. Separate hold_coaming_6x12 and four hatch_cover_6x3 placements sit at
[0,4.5,0] and [0,5.24,z], z=-4.5/-1.5/1.5/4.5. The same Hold coaming / Hatch cover
palette families resolve the fitting size from ImportedHullCatalog. Floor
visibility uses cargo_hatch style, not one older filename. Material paintability
comes from the asset manifest as well as the existing structural families.

`examples/coastal_32m_draft.json` is 113 editable placements with an aft bridge;
all covers are independently selected, erased, painted and saved. It adds no
operational inventory or powered hatch mechanism. Provisional handling is 420 t,
2.6 m draft, 1100 kW and 4500 l fuel using the existing physics components.
Mooring positions now belong to each platform descriptor. Stern gear now uses the dedicated raised-counter installation described below.
Owned-fleet commissioning and multiplayer transport remain separate work.

`coaster_kit_showcase.tscn` checks dimensions, actual tank-top/walkway ray hits,
gear motion, per-instance cover paint and captures whole/bow/hold/stern views.
`--verify-draft` checks 113 placements, hull switching, floor datum, fitting cover
seats, cover visibility/selectability, save/load and invalid-load preservation.
The real ocean playtest passed helm/seats, doors, walking, normal HUD, drive,
steering and reset. Its steering observation period now scales with hull length;
the same heading threshold is retained, without increasing game steering forces.
The initial 4-second small-boat window measured only .006 rad on this 32 m hull;
9.15 seconds measured .037 rad. Handling remains provisional rather than tuned.

Primary visual reference inspected: Damen Combi Freighter 3850 sheet page 1,
https://medialibrary.damen.com/m/4537b8913b7e976d/original/product-sheet-combi-freighter-3850.pdf
Used for open-hold / coaming / separate-cover / aft-bridge arrangement only.
Our much smaller hull is an original game platform, not a scaled manufacturer copy.


### Removable marine lighting kit (6 October afternoon)

Five separately authored Blender/GLB fixtures in lighting_kit: tilted/finned deck
floodlight, red port, green starboard, white stern and white mast lantern. Each has
its own bolted standard, Lens mesh and LightAim socket. LightAim supplies direction
and location; no light or emission is baked into the asset. BrickCatalog attaches
the existing ShipLight below that socket, with build_housing=false. ShipLighting
owns presets, weather/day output and the usual helm L key. A per-fixture cloned
lens material prevents one vessel changing another. Painted supports use the wall
channel; fixed housing, hardware and lens retain their assigned material colors.

Near-field range/energy and lens output are deliberately smaller than legacy
fixtures; do not restore the oversized colored wash or all-round deck flood.
Nav lens screens follow authored arcs, but the existing Light3D fill remains omni:
this is game lighting, not a certified navigation-sector or COLREG implementation.
Mast lantern is all-round white, not a regulated masthead-sector arrangement.

Run _source/lighting_kit/fit_examples.py after regenerating the four example drafts.
It adds six independent/removable placements to each and touches no user saves.
Current totals: trawler 67, cargo 93, bulk 93, 32 m coaster 113. Palette uses the
existing Lights category; source layouts and collision handling stay separate.
marine_lighting_showcase.tscn dispatches real L key events through BoatController,
checks OFF/NAV/WORK/ALL, lens off state, per-boat isolation, authored downward aim,
and daylight dimming; --capture writes night/off/close/coaster/day Godot images.
All four actual builder save/load fixtures verify these newly populated drafts.

Primary visual reference: Hella Sea Hawk XLR mounting diagram, finned housing and
U-yoke (original game geometry and stand, not manufacturer dimensions):
https://www.hellamarine.com/wp-content/uploads/2024/01/980_740-001_980_740-011_980_740-201_980_740-211_Sea_Hawk-XLR_Diagram_Web.pdf


### Dedicated 32 m stern installation

The 32 m shell now raises its underwater counter to 2.96 m at the stern, leaving
an aperture under the aft deck. End closure is built from horizontal strips,
not one non-planar n-gon. The exact deck outline, hatch opening and grid are
unchanged. Broad hydrostatic station/handling profiles remain provisional and
are not derived from the revised mesh volume.

build_coaster_gear.py produces three separate Blender/GLB assets: propeller_1800
(four cambered/skewed bronze blades, tapered hub/cap), rudder_2100 (2.1 m tapered
balanced foil, stock and anodes), coaster_shaft_support (stern tube, hanger,
bearing/seal/fasteners and rudder trunk). mounts_32m.json owns optional asset IDs
and exact metre coordinates; example-layout generators must not overwrite it.
14/24 m mounts retain the prior assets. Shaft local Z rotates; stock local Y turns.
Visuals only consume existing propulsion/fuel/rudder or sequenced external state.
They never relocate or augment physics force points.

stern_gear_showcase.tscn -- --coaster --capture <png> checks forward/reverse/stop,
dry fuel, stale/invalid snapshots, reload, full propeller Z extent at 15-degree
steps and rudder clearance at 2-degree steps. Sampled actual blade vertices are
ray-checked beneath the real raised counter; this is sampled geometric clearance,
not a continuous collision or hydrodynamic validation. Close/side/reverse Godot
renders inspected. Existing 14 m gear checks and 32 m ocean drive/helm/door/reset
checks pass. Moving gear remains excluded from walking collision.

Primary visual reference inspected: Becker Rudder Systems page 2 (full spade
placement, stock-to-hull relationship and foil proportions). Original symmetric
game foil, not Becker's proprietary flap/twist profile:
https://becker-marine-systems.com/fileadmin/redakteure/bilder/Company/Media/Downloads/Product_brochures/becker-rudder-systems.pdf


### Imported trawl rig and working deck (6 October afternoon)

build_trawl_rig.py authors seven individual Blender/GLB assets: 4 m gantry,
hanging block, grooved sheave, mirrored cambered doors, open diamond-mesh net and
stowed net bundle. The gantry is one palette choice with removable assembly
components and named sockets. Internal static geometry is merged by material;
it is not a monolithic boat. Gantry/doors expose the wall paint channel. Floats,
net twine, hardware and rope retain fixed materials. The supplied 14 m example
now has 67 records: winch moved to z=3.4, gantry at z=5, both deck-mounted at 2.92.
Door shoes rest on authored cradles. Net bundle and doors are solid when stowed.
The NPC sizing reference moves to z=2.4, clear of the relocated winch.

The winch has two coupled winding bays, manifold/connected flexible hoses and
PayoutPort/PayoutStarboard sockets. One existing drum pivot drives both bays;
this is not two independently powered winches. Gantry block sockets route warps
over the sheave crowns. Nearest unclaimed gantry within 8 m binds to each winch.
A winch without a gantry still deploys the new net/doors, with direct lines;
arbitrary custom placements are not guaranteed to clear structures.

ImportedTrawlRig is read-only presentation beneath FishingSystem. It replaces the
old cylinder/cone net only for imported winches; it does not alter drag, catches,
requests, inventory, saves or authority. G at the actual helm still toggles the
existing fishing state. Two doors, two warps, four bridles and the net follow the
vessel heading and WaveSurface height. Reusable line spans are flexible runtime
geometry. Stow colliders disable while deployed and restore with the authored
stow transforms; underwater rig meshes never become walking surfaces.

Deployment currently switches between stored and towed poses. There is no
animated recovery/crew handling, seabed-contact solver, true cable catenary or
hydrodynamic door spreading. The game rig is shallow towed presentation, not a
simulation of a specified real fishing method. Do not describe this as complete
trawl physics or multiply catches based on these visuals.

fishing_kit_showcase checks transformed anchors, finite line pool, supplied stern
bulwark clearance, stow reset/colliders, drum motion, catch inventory and real
shore transfer. Captures include deck, deployed assembly, net and pulley closeup.
The real ocean playtest verifies G deployment/retraction while seated at the helm,
plus normal HUD, walking, doors, drive and reset. Draft load/save is verified.
Primary visual sources inspected: Thyboron Type 2 sheet page 1 (cambered/V plate,
ribs, shoe and towing chain) and Morgere 2025 catalogue PDF page 4 (fabrication and
tow-test arrangement). Original small game models, not copies of proprietary foil.
https://thyboron-trawldoor.dk/wp-content/uploads/2020/10/Produktblad-TTD-Type-2-Standard.pdf
https://www.morgere.com/wp-content/uploads/2025/06/catalogue-morgere-2025-filiere-peche-en-1.pdf

### Standard stairs and two-level coaster (6 October afternoon)

access_kit has separate deck_stair_220cm and deck_bracket_2m Blender/GLB assets.
The stair has exactly 11 x 0.2 m rises and a 3 m run (3/11 m going). LowerFloor
is the placement datum; UpperFloor is (0,2.2,-3) in Godot. One metre tread width,
1 m-high top rails at the landing, individual grip ribs, nosings, stringers and
bolted attachments. Rail/step materials stay fixed; structural steel exposes wall.
The 2 m knee is a separate under-deck support, with its top 0.1 m below the
placement datum to meet the underside of a standard floor. Do not scale stairs
to change floor heights: author a corresponding tread/rise variant.

32 m example now contains 162 editable placements: 5 x 6 m lower accommodation,
wraparound 2:1/45-degree upper bridge, separate console/controls/chairs, balcony,
external stairs and two knees attached to solid wall panels. Upper structural
floor datum is 6.7 m; the floor finish sits 5 mm above it to avoid a coplanar wall
cap. Roof datum is 8.9 m. The small white mast light moved to the aft balcony.
No accommodation occupancy/economy system is implied by this arrangement.

Rail posts are derived from panel endpoints by the same method in both editor
and ImportedDraftVessel. Previously playtest omitted these supports. They are
included in real walk collisions, remain panel-owned and add no save records.
Palette thumbnails now frame actual imported mesh bounds (including components),
so centred gantries and origin-at-wall brackets aren't cropped or off-centre.

Real-player testing exposed slow-motion step detection and capsule/nosing normals.
The controller now considers millimetre motion, checks the actual tread surface
when a capsule edge contact appears steep, and maintains step eligibility across
that brief contact. Full-body up/forward/down casts remain authoritative; low
ceilings and tall walls still block. tests/coaster_access_test.tscn checks slow
and normal speeds, +/- roll/pitch, ascent/descent, upper doorway and helm approach,
plus ceiling/tall-obstacle limits. Run rendered with --shipyard-playtest for real
mouse-captured input; headless mouse state does not simulate walking here.

Coaster showcase keys 3/4 inspect stairs and the bridge cutaway. Forward+ captures
are preferred: Compatibility shadow acne exaggerates small metal tread details.
Arrangement reference: the previously inspected Damen Combi Freighter sheet;
this is a compact original game arrangement, not its dimensions or certification.
Stair grip mats, nosing paint and millimetre ribs are tagged through the optional
walk_exclude_materials manifest contract. Only meshes entirely made of those
materials skip walk collision. The actual eleven imported tread pans, stringers,
rails and supports remain physical; there is no invisible ramp. Final refined
geometry repeats the full access checks successfully.

### Ventilation fittings (6 October afternoon)

ventilation_kit contains separately authored deck_mushroom_vent and wall_vent_louvre
GLB/Blender assets. The 0.8 m-wide, 1.01 m-tall deck head has a hollow flanged
trunk, eight holding bolts, weather hood, stays and a separate screened throat.
Hard fabricated profile breaks split normals while the hood remains smooth.
The wall intake has downturned blades, a dark throat, rain eyebrow, drip sill
and corner screws. Its origin is the standard wall centreline at floor height;
the visible mounting back lies 60 mm forward, matching the standard wall skin.
Ventilators face Godot -Z. Housings expose wall paint; screen and blade finishes
are fixed. These are static fittings, not an airflow or flooding subsystem.

The coaster now has 165 placements: two portside deck vents and an intake on a
solid lower front panel. The portside route was checked with the real player.
coaster_kit_showcase verifies per-instance paint and captures both details; key 5
shows the deck vent. The floor visibility threshold now matches its existing
selection tolerance, preserving the 5 mm finish at Floor 1. Save/reload checks
explicitly verify that finished surface remains visible/selectable.

Visual reference: Sealux Marine 2022 catalogue page 49, mushroom weather hoods,
fly-screen gaps and slatted wall openings. This is original, larger game-scale
fabrication; it is not a scaled copy or rated version of that small-vessel product.
https://www.sealuxmarine.com/wp-content/uploads/2022-METS-CATALOUE-07-High.pdf
# Continuation: 32 m cargo hold (6 October 2026)

## Starter fleet, engines and containers (6 October evening)

The four official starter ships now live in resources/data/vessels/prebuilt as
format_version 3. Their brick_layout is the versioned imported_models envelope,
including hull, individual parts, paint, floor visibility and engine_preset.
ImportedVesselLayout and ImportedShipPartsEditor share validation. Owned saves,
company grants, shipwright previews, VesselSpawn and replica hydration use this
same assembly; do not flatten it into a legacy cells dictionary. Imported ships
do not require the removed legal registration. Existing custom owned records
must not be replaced by new stock. Drafts > Starter vessels opens a copy; Save As
must never modify the canonical prebuilt. Show entire ship is a visibility option,
while selection still follows the active floor.

Canonical stock: Coastal Trawler 14 x 5 m (71 placements, two 600 kg catch tanks),
Harbour Cargo 24 x 8 m (128, raised bridge and two 20-foot deck containers), Coastal
Bulk 24 x 8 m (96, two open 40 t holds), Coastal Freighter 32 x 10 m (165, one open
120 t hold). Load limits remain game tuning. The wider 1.5 m stair has the existing
2.2 m floor rise and 11 real treads. _source/starter_fleet/assemble_starters.py
reproduces the arrangements without modifying the old example fixtures.

Container assets in models/cargo have exact 20/40-foot external dimensions:
2.438 m width, 2.591 m height, 6.058 / 12.192 m length. Metres, bottom-centre origin,
doors at Godot +Z. Continuous corrugated sheets, actual apertures in corner castings,
separate DoorPortPivot / DoorStarboardPivot, rod/keeper/handle hardware and floor.
Container_Paint is the only repaintable surface; fixed zinc, seals and plywood
retain their material. Doors can be inspected separately in the showcase; gameplay
cargo remains closed, with a full-box collision. Do not imply door interaction,
reefer functionality, stacking simulation or certified lifting equipment.

Each size has a separate lifting spreader. Hook is at container height +0.5 m;
ContainerNode shows it only while held. The crane uses actual unit height and
matching target footprints. ContainerUnit stores container_type independently
of freight ID, consignment, commodity, mass and value. Missing type means legacy
4 m break-bulk; the replacement legacy model retains its former 3.8 m visual size.
Do not silently reinterpret old freight or resize ISO geometry to fit a pad.
footprint_cells(cell_size) converts physical clearance (2.5 x 6.5 / 12.5 m) to
each pad lattice. A 40-foot box must be rejected by a shorter bed. The current
starter fleet has two 20-foot beds; there is no 40-foot ship berth yet.

Harbour Cargo carries boxes ON DECK, per Noah's correction, not down in the hold.
The separate cargo_deck_5x8 closes the opening at y=3.6 with underside girders.
Two container_bed_20ft assets sit at x=+/-1.25, y=3.6, z=0. Their CargoDatum socket
supports inherited CargoSlotPadComponent inventory, crane transfer and mass.
Runtime capacity requires the exact supported arrangement. Legacy 4 m beds remain
loadable for existing drafts; mixing bed families disables overlapping capacity.
Mass-entry prefixes must be unique per pad, even when their node names match.

MarineEngineCatalog reads six data presets from engine_presets.json: compact
300/450 kW, coastal 700/950 kW and freighter 1100/1600 kW. Three individual Blender
engines in models/machinery have foundations, isolators, sump, head covers, service
panels, fuel pipes, cooling circuit, turbo/intake, guarded belt and marine gearbox.
OutputCoupling receives the separate coupling model. Models are installed below
deck at catalog mounts; the builder's Inspect engine dialog exposes their actual
geometry without opening a hole in the deck. They are original generic machinery.

The selected preset controls shaft power, bollard pull, fuel use, package mass and
shaft presentation. Imported records cannot override power with a stale numeric
shaft_power_kw field. Old drafts default to the hull's standard preset; invalid or
incompatible IDs fail validation. Upgrades add their mass difference to the base
displacement. Coupling and propeller read the existing powered/throttle state;
no extra input, fuel, authority or engine singleton. There is no maintenance or
start/stop interaction system in this pass.

Generic RigidBody linear damping is replaced with zero for imported boats because
HydrodynamicsComponent owns resistance. Wave-drag coefficients .011/.007/.0065
are soft game tuning, not speed caps. Measured standard calm-water speeds after
120 seconds full ahead: 12.90, 14.50, 14.50 and 14.57 kn. Upgrade checks: 14.22,
15.67 (cargo carrying 48 t), 15.80 and 16.36 kn. Fuel-empty and reverse checks pass.
These are controlled test results, not a prediction for every sea/cargo state.

Review scenes: starter_fleet_showcase, container_showcase, marine_engine_showcase.
The latter two are automatically isolated just like shipyard playtest. Core checks:
imported_starter_fleet_test, starter_drafts_test, starter_access_test,
vessel_performance_test, company_service_test, vessel_persistence_test and the
ordinary shipyard ocean verification. Remote payload round trips are checked;
external multiplayer service acceptance is not verified by those local tests.

Visual references: Hapag-Lloyd Container Specification p5/p8/p10 (dimensions,
corrugations, doors, corner fittings) and Cummins QSK19 marine sheet (machinery
arrangement). Original game assets, no manufacturer marks or certification.
https://static-cf.hapag-lloyd.com/content/dam/website/downloads/press_and_media/publications/15211_Container_Specification_engl_Gesamt_web.pdf
https://mart.cummins.com/imagelibrary/data/assetfiles/0032290.pdf

## Trawl deployment and recovery

`ImportedTrawlRig` now approaches the existing FishingSystem desired state over
12 seconds out / 16 seconds back. The first segment lifts gear above the stern,
the second moves it clear, and the last lowers/spreads it. Reversing the desired
state traverses the same path without resetting the pose. This is presentation;
FishingSystem still owns catch, drag and authority. Its existing catch/drag timing
is unchanged. No seabed, cable physics or door hydrodynamics are implied.

The four meshes in `trawl_net_open.glb` carry a Blender-authored `Stowed` morph.
Floats and footrope weights keep their shape and remain attached to matching net
points throughout the blend. `trawl_net_bundle.glb` is baked from that exact final
shape, so the editor's static/collidable bundle matches the animation endpoint.
The `*Wing*Stowed` sockets describe folded bridle endpoints. Regenerate just these
assets with `build_trawl_rig.py -- --net-only`; preserve both Blender sources.

Drum and sheave rotation comes from actual change in routed warp length. They
reverse while recovering and hold still while towing. Stowed warps stay visibly
attached. Moving gear disables its stowed walking collision until it reaches the
cradle again; the deployed net remains presentation geometry. G uses the normal
helm control and the HUD reports SETTING GEAR / RECOVERING GEAR during transitions.

`fishing_kit_showcase.tscn` supports G to deploy/recover. Its checks cover full
travel, mid-haul reversal, stopping drums while towing, endpoint transforms,
sampled stern clearance and restored stowed collision. The ordinary ocean
playtest also tests G reversal and full recovery on the moving vessel in waves.
Capture mode adds intermediate 22/36/48/72 percent images for visual review.
The current launch path is verified on the supplied 14 m trawler; arbitrary
custom gantry placement/superstructures still require clearance review.

Reference: FAO's [bottom otter trawl gear description](https://www.fao.org/fishery/docs/CDrom/ARTFIMED/ArtFiWeb/descript/Gear/geartype/gt306.htm)
describes the two-bobbin warp winch. This game animation is a compact illustrative
handling sequence, not a simulation of crew work or a certified fishing rig.

## Continuous cargo space

The 32 m draft now exposes one `ImportedBulkHold` through `BoatBody.get_bulk_holds()`
when `hold_coaming_6x12` is seated at (0, 4.5, 0) with its authored orientation.
The hull's `HoldCentre` socket supplies tank-top height (1.4 m); the four coaming
`CoverSeat` sockets supply the lip (5.24 m). The continuous volume is 6 × 12 m,
3.84 m deep. Its 120 t limit is provisional game tuning, not certified deadweight.
Any hatch cover overlapping the opening blocks cargo handling for this undivided
hold. Remove all four lift-off covers in the builder to run an open-hold playtest.
No powered hatch, vessel commissioning or owned-save migration is implied.

`coaster_cargo_showcase.tscn -- --shipyard-playtest --verify` exercises covered and
partly covered rejection, invalid coaming placement, overflow, vessel mass,
inventory JSON restoration and the actual existing crane operator. Add
`--capture <absolute.png>` for whole-vessel, hold and loading captures. The 24 m
two-compartment bulk example retains its two separate 40 t holds.

## Procedural port facilities (generation 48)

Sources: `_source/port_facilities/build_facilities.py` and
`build_industrial_facilities.py`, with fourteen individual .blend files. Exports: `parts/port_facilities/*.glb`. These are metric individual assets,
not baked precincts. Blender Z is up, +Y exports to Godot -Z; origin is pavement
level. Office entrance is Blender -Y / Godot +Z and the port places it at yaw PI.
Its PublicEntrance socket is cosmetic until an interior/door system is added.
Fixed office glass/doors must not be advertised as interactive.

Named materials keep Office cladding, Ivory trim, Roof paint, Fixed glass,
Galvanized, Dark steel, Concrete and Dunnage timber separate. Preserve those
regions for future local paint overrides and worn texture maps. No shared imported
material should be mutated globally for an individual port's custom colour.

PortFacilityPlan owns persisted metre parcels and compatible berth links;
PortFacilityVisual composes the assets and explicit walking collision. Keep the
central seven-metre handling lane clear; do not fill empty storage bays with fake
inventory. General cargo import/export share a precinct; incompatible liquids
remain separate. Bulk dividers mate in four-metre runs; fence runs may adjust
length but equipment/office dimensions are fixed. Facilities that cannot fit are
reported in unmet, not shrunk to toy scales. New asset placement needs checks at
both persisted small footprints and new full-size/fallback footprints.

Use port_showcase for the real coastline and port_facility_showcase for all nine
precinct types (Left/Right and Space). Details, tests and remaining limits are in
`docs/procedural-port-facilities.txt`. All machine captures must also be archived
under C:/Users/noahs/Pictures/machinescreenshots.

The industrial expansion adds harbour_authority_20m (20 x 14m, four floors),
lng_terminal_tank_24m (24m diameter), open yard_pallet and loaded_storage_rack.
The office and LNG models have fixed metre dimensions; reserve adequate plots.
Tank collision must follow the cylindrical shell. Pallet/rack props are cosmetic
and must never create freight lots or imply owned inventory. Noah withdrew the
large decorative container-yard request; do not reintroduce ambient container
stock from this work. Keep cargo containers in their existing freight system.

## Artificial lighting acceptance (6 October 2026)

Imported deck floodlights use 24m range / energy 18, rather than the former 18m /
3.5 override. Their authored LightAim still owns orientation. Surface lighting,
lens emission and volumetric scattering are separate controls: work-light fog
energy is 0.18 and must not be used to compensate for an unlit deck. Shadow normal
bias is 0.25m; large biases can detach shadows from walls and fittings. Navigation
lights retain their localized wash and their independently visible lenses.

Quay poles use energy 28 / 28m range, downward aim below the lens, local shadows
fading after 65m, and light fading from 160m. The imported Light diffuser surface
gets a per-instance emissive override; never edit the shared material. Automatic
switching follows SolarCycle daylight, not fixed clock thresholds. Existing
ShipLighting OFF/NAV/WORK/ALL and player L input remain authoritative.

WorldRenderer blends from a small color ambient floor at night to sky contribution
by day. This avoids multiplying night fill by the nearly black sky cubemap while
preserving daytime sky shading and bounded exposure. Ocean near/mid/far/horizon
shaders retain their custom lighting, but must allow local specular response and
must not multiply ALBEDO into DIFFUSE_LIGHT a second time. Reference:
https://docs.godotengine.org/en/4.4/tutorials/shaders/shader_reference/spatial_shader.html

Acceptance uses tests/night_lighting_review.tscn with --shipyard-playtest, optionally
--vessel=coastal_coaster. It uses the actual WorldRenderer, ocean, port and starter
layout at its draft height. Clear/fog nights are captured lights on/off beside the
quay and 600m offshore, plus daylight. Deck-region pixel differences must exceed
0.008; trawler measured 0.093-0.117 and coaster 0.038-0.061 after correction.
Screenshots live in C:/Users/noahs/Pictures/machinescreenshots/night-lighting-*
(trawler 1791319397-085; coaster 1791319433-09). These are static lighting reviews,
not a claim of sea-trial physics validation or completed cabin lighting design.
WorldLightingGrade, ArtificialLightDayScale and the real L-switch marine showcase
also pass, including independent vessels and disabled emission in OFF mode.

### Natural night lighting follow-up

The initial brightness checks above did not establish visual acceptance. The next
pass uses finite emitter sizes (quay 0.65m, work flood 0.35m), broader quay pools
at energy20/range32, and neutral scattering albedo rather than dark night-sky
colour. Clear-night density is only0.00065, fades away by daylight0.3, and respects
the existing volumetric quality switch. Dense weather is still a separate term.
Night contrast is1.0 and ambient floor0.14; daylight contrast remains1.045.
SSIL adds local screen-space indirect detail (radius5/intensity0.65), controlled
by enable_ssil. It cannot bounce off-screen geometry and is not full world GI.
Do not present it as such. Godot reference:
https://docs.godotengine.org/en/4.6/classes/class_environment.html
Night review now includes eye-level and real weather grading/SSAO. Optional
--profile-lighting compares the extra effects with uncapped frame and GPU times.

### Imported cabin door runtime

ImportedDraftVessel installs DoorInteraction in owned, replicated and sea-trial
boats. Target the actual animated leaf collider with F; world surfaces occlude
it. Do not add another playtest-only keyboard handler. ShipPartState continues
to pose the authored hinge and existing moving collision follows it. Registered
vessels route open/close plus swing sign through WorldStateBinding using vessel
identity and stable part placement identity. No local optimistic mutation while
registered authority is unavailable. Unregistered isolated previews remain local.
Runtime regression: tests/imported_door_runtime_test.tscn -- --shipyard-playtest
[--capture-doors]. Covers both sides, occlusion, F input, open/close, late identity,
authority replay and stale rejection; captures are archived in machinescreenshots.

### Sky and post-grade review

Sun and moon size uniforms are angular radii in radians, not offsets from a
cosine. Compare ray chord distance to 2*sin(radius/2). The old convention made
the moon roughly ten degrees wide. Keep the clear/cloud day/night palette
separate: overcast must not blend toward a daytime grey at midnight.
Screen contrast uses a bounded curve retaining faint nonzero light, and grain
scales down in dark pixels. Validate with tests/screen_grade_shadow_test.tscn.
Use tests/live_lighting_review.tscn for normal-world spawn and owned-vessel deck
views. Weather fixtures must write cloud_cover, precipitation, convection_index;
cloud_coverage/rain_amount/storm_intensity are DERIVED GETTERS. Do not assign them.
Both review scenes require --shipyard-playtest and archive machine captures.

### Ocean depth and weather transitions

Near water reads opaque scene colour/depth, reconstructs water thickness, and
uses per-channel absorption plus restrained refraction. Lit scene colour goes
through EMISSION, not ALBEDO (avoid lighting it twice). Preserve foreground depth
rejection, Fresnel/foam opacity and fade before the near/mid boundary. This is
screen-space transmission; transparent/off-screen objects are not represented.
FFT initial amplitudes are the active sea; a separate target spectrum receives
weather repacks. UPDATE evolves active complex amplitudes without resetting phase.
The shared WaveSurface.get_applied_wave_intensity drives both visuals and physics.
Do not restore instantaneous spectrum replacement or smooth only visual waves.
Run tests/ocean_transmission_review.tscn with -- --shipyard-playtest for GPU
convergence checks and archived renders. Optional --compare-shader=<absolute path>
compares shader GPU timing, not FFT cost. Depth convention reference:
https://docs.godotengine.org/en/4.6/tutorials/shaders/advanced_postprocessing.html

### Water reflection acceptance follow-up

Ocean surfaces now use actual Environment sky radiance and standard dielectric
lighting (SPECULAR=.25 / F0=.02), with per-pixel FFT slope sampling nearby and
footprint filtering. This supersedes the earlier custom local-light-only ocean
rule. Do not put a second sky reflection or sun highlight into ALBEDO. Keep
transmitted already-lit scene colour in EMISSION. Foam/wake atlas values are
coverage envelopes: fine foam detail is shaded separately and fades before it
becomes subpixel. The 2m wake atlas must not saturate into a solid white ribbon.
OceanTransmissionReview accepts --surface-review and --drive-review for actual
rendered weather and powered-vessel checks. Sunset is around22:00 in SolarCycle,
not18:00. Cloud layer is still procedural2D; do not describe it as volumetric.

### Filtered ocean slope field

FFT assembly writes base signed slopes; fft_ocean_slope_mip.glsl builds their
nine-level averaged mip chain in a separate compute list (D3D12 push-constant
layout differs from FFT passes). Near/mid/far/horizon sample filtered slopes per
pixel, retaining the existing cascade distance fades and shared wave amplitude.
Do not restore synthetic metre-scale cosine chop or discard an entire cascade
just because its highest frequencies become subpixel. All water tiers use the
same weather roughness driver. The review fixture verifies GPU mip averages;
--surface-review and --drive-review still require visual inspection. Added memory
is2.667MiB; measured mip compute0.049ms on RTX5070 is not a universal frame budget.

### Antifouling finish

Paint_HullLower is a non-metallic coating: metallic0, roughness.72. Preserve its
separate user colour slot on hulls, rudders and shaft supports. Exposed bronze
propellers and stainless shafts retain their metal response. A metallic lower
hull creates an artificial pale sky-reflection band through transparent water;
do not hide that material problem by disabling transmission. The --waterline-review
fixture compares opaque/transmissive/hidden water and asserts the imported finish.

### Cloud volume presentation (supersedes the earlier 2D cloud limitation)

Sky clouds now integrate a shallow 3D density layer at half resolution:64 view
samples with early exit, four light-path samples and distance-filtered density.
The offline-baked64^3 R8 texture includes all six downsampled levels (~.286MiB).
Run resources/textures/sky/bake_cloud_volume.gd with the graphical Godot renderer
when rebaking; Dummy/headless does not return the generated texture slices.
No noise worker runs at game start. Keep the deterministic seed and complete mip
chain. Cloud colour is premultiplied radiance; compose sky*(1-opacity)+cloud.
The same layer participates in sky radiance, with REALTIME cubemap processing.
Sun/moon/stars are occluded by local cloud opacity rather than a global coverage
multiplier in the sky shader. World weather still owns cover, convection and
lighting; the new density field is presentation, not gameplay weather authority.
This is a bounded slab, not planet-scale volumetric weather: no cloud shadows on
terrain, multiple scattering solver or fly-through acceptance. Keep those limits
explicit. tests/cloud_volume_review.tscn archives day/overcast/dusk/night/storm,
zenith and moving-camera frames and rejects black-sky shader failures. Compare
GPU runs with identical final camera/weather; storm and broken sky differ in cost.
References: https://docs.godotengine.org/en/4.6/tutorials/shaders/shader_reference/sky_shader.html
https://www.guerrilla-games.com/read/the-real-time-volumetric-cloudscapes-of-horizon-zero-dawn


### Ocean ring finish and editor preview materials

Near, mid and far ocean rings use the same weather foam gain, coverage, bubble
average, colour mix and roughness mask. Whitecaps continue through the384m
mid/far boundary and fade smoothly from800 to1400m, before the1536m horizon
boundary. Do not scale foam separately per material or omit it at a visible ring
edge. The far ring retains cheaper geometry/wave sampling; no physics change.
The world review scene tests real generated shore context and quantised camera
movement; its elevated cameras are diagnostic, not player traversal acceptance.
Realtime sky radiance is256, as required internally by Godot's realtime mode.

Imported builder ghosts use a uniform translucent material override. Call
create_part(record, false) for these previews: allocating per-instance paint
under that override is wasted work and triggered renderer material dependency
errors when previews were replaced before the next frame. Placed parts keep
create_part(record)'s default paint path and independent colour regions. Verify
both the ghost and placed model with imported_parts_paint_test.

### Provision crane hoist kit (7 October)

The default ProvisionCrane keeps its existing role hierarchy and cargo/authority
controls, but its trolley, wire and hook visuals now use three independent
Blender assets under parts/provision_hoist. Source build_hoist.py lives under
_source/provision_hoist and reuses the crane_kit paint baker. Three source blends
are retained; six512px baked paint maps use mipmaps and VRAM compression.

LoadSeat remains the existing hook origin. Lower-sheave tangents are x=+/-0.30m,
y=0.85m in Godot. Straight falls are authored10m downward and scale only in length;
the block and trolley must never inherit that stretch. Respect model_scale both
in visual dimensions and in the wire length calculation. Current rail centres
are +/-0.42m; trolley running-wheel bottoms sit on the existing rail top.
Custom JSON crane models keep their original visuals. Do not change freight
identity, pad placement, reach limits or AI control to accommodate cosmetic parts.

This is a hoist-kit migration, not a finished whole-crane replacement. Mast,
jib, cab and counterweight remain legacy models. Running wheels/sheaves are
fixed meshes for now; drum/feed-rope routing and rotation remain future work.
No certified load rating or mechanical simulation is implied by these visuals.
Original geometry was informed by the manufacturer's two-fall/trolley arrangement:
https://www.liebherr.com/en-sg/tower-cranes/assistance-systems-7101961
https://assets-cdn.liebherr.com/assets/api/ac6958da-b4ba-40b6-8f25-3f1734d3a33c/Original/

Run tests/provision_hoist_review.tscn -- --shipyard-playtest for rendered motion,
rope-tangent checks at three scales/lengths, and real container pickup/move/release.
Use tests/port_material_review.tscn with --provision-review for daylight port
context. Captures are archived under Pictures/machinescreenshots.

### Provision crane structural modules (7 October follow-up)

Mast/jib/rail geometry now also uses Blender assets in provision_structure;
this supersedes the preceding hoist-only limitation. Six5m mast sections form
exactly30m. Fifteen5m triangular jib sections run from20m aft to55m forward,
with a separate terminal frame. Ten5m rail pairs plus one3m end pair preserve
existing1-54m trolley limits and +/-0.42m rail centres. Named end sockets and
flat mating faces are authoring contracts. Avoid duplicated end triangles at
module boundaries; only the far tip receives the extra closure frame.

Each repeated family is a MultiMesh with shared imported mesh/material resources,
not one complete-crane asset or dozens of separate rendering nodes. Five authored
meshes total5584triangles/7surfaces before instancing; the full structural assembly
is42408triangles before imported LOD. Source build_structure.py and five blends
are retained. Nine512px paint maps are mipmapped/VRAM compressed; check actual
vram_texture metadata after rebakes, not just compress/mode settings. Generated
image hashes can otherwise leave a previous uncompressed texture cached.

Keep the existing role parents and conservative mast/lower-jib collision; an
additional upper envelope follows the taller triangular jib. Internal ladders,
rest landings and service strips are visual details, not climbable gameplay.
Existing cab, machinery housing, foundation and counterweight remain legacy.
Full winch/feed routing and rotating sheaves remain unfinished. Do not claim a
mechanically certified crane or a complete imported-crane conversion.

Manufacturer tower-joint/ladder/landing visual reference (original game dimensions):
https://www.liebherr.com/en-gb/tower-cranes/technologies/tower-systems-5222681
provision_hoist_review checks module seams at three scales, physical ray hits,
hoist/load contracts and optional --baseline-structure comparisons.

### Provision crane cab, station and ballast (7 October)

The remaining default T-crane visual bodies now use five separate Blender assets
in parts/provision_station: operator_cab, machinery_station, slew_platform,
tower_foundation and counterweight_rack. The generator and five standalone blends
are under _source/provision_station. Total 5820 triangles / 11 material surfaces;
fifteen 512px baked maps have mipmaps and verified VRAM compression. Enamel,
ochre paint, dark steel, glazing and non-metallic cast concrete stay distinct.

The existing ModelAssembler roles still own slew/trolley/hoist/cargo. Only their
visual meshes are replaced; custom JSON model paths retain their old presentation.
MastSeat is exactly (0,1,0) in Godot; machinery JibPivot is (-1.75,3.7,-.25).
The wider 5.20 x 5.19m service deck has its own moving collision, as does the
raised cab roof. Other old conservative collision envelopes are retained.
Railings, cab furniture/door and service access are visual details, not new
climbable routes or player interaction. Preserve that distinction in UI/docs.

The original cab geometry takes cues from large forward/downward glazing and
side controls described by the manufacturer, not an exact product replica:
https://www.liebherr.com/en-ca/tower-cranes/technologies/crane-cabin-4020326
The bearing, anchors and retained ballast dimensions are game presentation;
no certified structural calculations or crane load rating is implied.

provision_hoist_review now captures the cab/foundation/ballast and checks station
pivot, mast mounting and roof/platform collision at three scales. Optional
--baseline-station restores only the previous station visuals for comparison.
port_material_review --provision-review includes front/rear station views.
All captures remain archived in Pictures/machinescreenshots.

Still unfinished: winch/feed-rope routing, rotating sheaves/wheels, and replacing
the build-then-discard legacy visual assembly with a direct imported rig. Do not
call the complete crane mechanically finished or the entire art pass accepted.

### Provision hoist reeving and moving parts (7 October follow-up)

The hook block, trolley and new winch retain independent named rotating mesh nodes:
LowerSheave, HeadSheave_L/R, RunningWheel_LF/LB/RF/RB and HoistDrum. Do not join
these into the static chassis or bake their rotation into a whole-crane animation.
The two upper pulleys now lie in the fore/aft vertical plane; the previous
sideways discs could not redirect the longitudinal feed ropes into the falls.

The main hoist is a two-fall presentation: counter-jib winch -> left upper pulley
-> hook block -> right upper pulley -> fixed jib-end anchor. Two instances of an
authored 1m rope scale in length only. Radius stays12mm. Straight segments meet
quarter-turn wraps at the upper pulleys and the lower half-wrap at the block.
The new winch includes an independent drum with wound cable, motor/reduction unit
and mounting bracket. Its winding is a fixed layer; there is no fleet-angle or
multi-layer spooling simulation. No trolley drive cable or rope-sag physics yet.

Animation is derived from current trolley/hoist positions, not input or an idle
clock. Wheel phase follows travel/radius; drum payout is twice hook travel. The
tip-side head sheave stays still during pure hoisting. Trolley movement exchanges
the horizontal spans without turning the hoist drum. Reversing positions exactly
restores phases, including direct pose assignments. This adds no network state.

Rail coverage is now0.5-54.5m for wheel axles0.5m either side of the1-54m trolley
centre limits. Use ten5m pairs and one4m end pair; the old3m asset remains available
but is not assembled by the default crane. Default-model travel limits scale with
model_scale, preventing small cranes from rolling beyond their shorter tracks.
Full-size reach is unchanged; custom JSON models keep their prior limit handling.
Structure generator accepts --asset=<name> for a scoped part rebake.

All six hoist GLBs total15212triangles/21surfaces, including4608triangles in the
close-up cable winding. Moving steel uses vertex-colour witness marks to avoid a
second material draw for each wheel. Twelve512px baked maps remain compressed
and mipmapped. Actual close-up and port views plus tangent, phase, end-limit and
real-container regression checks are in provision_hoist_review/port_material_review.
The retained legacy build-then-replace assembly and live model_scale rebuild
lifecycle still merit a separate pass. These changes do not add crane walk-up use.

### Distant cranes (7 October)

Distant provision/bulk cranes use offline Blender three-dimensional proxies in
scenery/port_distance. They are lit by the current environment, not six unlit
screenshot faces. The provision proxy has 13074 triangles; bulk has 3174, three
shared material surfaces each. These are static presentation only. Existing
PortStructureLod owns detailed crane creation, teardown and gameplay registration.
No remote cargo, animation, occupancy or authority is derived from these meshes.

Rebuild: run tests/export_crane_sources.tscn with --shipyard-playtest in a real
rendered Godot process, then Blender --background --python
resources/models/_source/port_distance/build_distance.py. Headless dummy rendering
returned stacked MultiMesh transforms during export; the exporter now rejects it.
Source GLBs are reproducible intermediate files; editable final .blend files are
tracked. Runtime-generated bulk hoist cable has a static six-sided proxy connector.
Tiny equipment and live hoist poses are intentionally absent from this distance model.

Run tests/port_distance_review.tscn -- --shipyard-playtest for day/night geometry
review and mesh/material/bounds checks. Existing building/house screenshot
impostors now generate mipmaps, but their full lighting/transition replacement
remains separate work. Do not describe all port-distance presentation as complete.

### Coastal forest foliage (7 October)

`scenery/coastal_vegetation` contains pine, birch, spruce and juniper, each with a
branch-card near model and a matching two-triangle distant silhouette. Near trees
use 1328-1978 triangles and two surfaces; distant trees use one surface. Metre-scale
assets replace the oversized cone trees. Blender sources pack their images and
`_source/coastal_vegetation/build_foliage.py` regenerates the complete set. Sprays
and silhouettes are rendered from authored geometry, not downloaded photographs.

Keep automatic GLB mesh simplification disabled for these assets: it removes
foliage cards and opens the canopy. Texture imports use mipmaps and high-quality
VRAM compression. The runtime foliage shader uses alpha cutout/depth writing and
live lighting, with crown normals/occlusion for near cards and an upright facing
silhouette at distance. CPU bounds cover the billboard at every yaw. Do not use
unlit screenshot materials or crossed silhouette planes here.

WorldForestStreamer uses deterministic 256m MultiMesh patches, 6.5m candidates,
four species groups and unchanged density/shore/slope/port exclusions. Placement
advances in 16-candidate batches under the frame budget. Empty results, positions
and species groups survive detail changes. Assets load in the background. Forest
and terrain clearance queries filter spatially before testing nearby zones.

Review `tests/forest_visual_demo.tscn` with `-- --shipyard-playtest`: Space switches
near/distant geometry, N switches lighting, 1/2/3 change views. `--capture-forest`
archives comparisons in Pictures/machinescreenshots. `tests/coastal_distance_review.tscn`
checks the actual generated world; `--forest-only` skips repeated port captures.
`--capture-lod` inspects individual tree handover at120-220m. Forest/terrain scripts test deterministic incremental placement, clearance,
distribution, mesh budgets, empty-patch caching and conservative bounds.

Near trunks use periodic512px bark colour/normal maps generated by Blender's
`bark_materials.py`: conifer plates and birch lenticels. Cylindrical UVs repeat by
physical branch length, with integral circumferential repeats to close the seam.
Trunks use eight sides with smooth side normals; small branches retain five.
Keep bark separate from cutout foliage when changing the material loader.

Near patches carry both near geometry and the cheap silhouette. Bark/foliage
share a complementary screen-door handover per tree at140-200m, using the main
viewport camera even during shadow passes. Fully hidden geometry collapses in
the vertex stage; pixel cutouts retain depth writing. The CPU can replace the
whole patch only beyond that band. Isolated review models opt out by default;
the streamer sets the shared `forest_lod_enabled` instance parameter. A fine
dither pattern can still be visible within the transition, particularly without TAA.

This is a dense coastal-forest foundation. Understory/rock integration, richer
branch/foliage variation and canopy beyond 2.2km remain work.
Single-view silhouettes are intended for distant viewing, not walking among them.

Distant canopy handover (7 October): individual silhouettes screen-door fade
between1950 and2180m, before their256m patches can be culled at2200m. The
terrain carries the remaining woodland mass; this does not add distant trees
or a three-dimensional treeline. Both terrain shaders share world-aligned,
derivative-filtered crown colour breakup and a palette closer to lit foliage.
Coverage is a256px R8 mipmapped map (about85KiB including mipmaps), sampled at
texel centres in the same world coordinate convention as the shaders. It is
still a broad156m coverage approximation at40km world size, not an exact mask
for small forest clearings. Preserve exact ForestField exclusions for geometry.

Use coastal_distance_review --forest-only --far-forest for1700-3500m views;
--sea-level adds8m viewpoints and a night view. The capture loop waits for
nearby terrain AND forest jobs, with a45s bound per view; inspect reported
pending counts before making convergence claims. --coverage-debug is an
unshaded diagnostic only. Terrain material review key4 shows the canopy
surface. All runs still require --shipyard-playtest.

Building/house impostor lighting (7 October): runtime captures now use the
unshaded albedo debug pass, with mipmaps, and the six faces receive live
per-pixel lighting. Do not bake a fixed sun into these colour maps or render
the resulting faces unshaded. X faces point outward and captures are not
horizontally mirrored. Footprint debug ghosts remain intentionally unshaded.
This repairs lighting/orientation, not the AABB silhouette limitation: gabled
roofs still look box-like at oblique angles. True simplified building geometry
and eliminating startup building captures remain future work.
Run tests/building_light_review.tscn with --shipyard-playtest for source/proxy
day, opposite sun and night comparisons plus albedo/mipmap/source-material and
rendered brightness regressions. Actual-world port review can use --ports-only.

Whole-world forest silhouettes (user correction, 7 October): the terrain-only
handover was insufficient. DistantForest now retains batched, lit two-triangle
tree silhouettes throughout the generated world, independent of the camera's
nearby256m patch set. Never return to a camera-centred square of trees with only
flat tint outside it. The existing1950-2180m fade now hands over to these tree
silhouettes. Geographic density, bare shoreline and port clearings still apply.
Distant crowns approximate coverage at9m candidates (near trees6.5m); crown width
is1.8x, height remains authored scale. These are woodland massing, not exact
one-to-one copies of every nearby tree. Ordinary camera far clipping still applies.

Generation reads immutable layout data and a copied coverage image/clear zones
on one worker. Do not use ForestField's mutable zone-cache dictionary on that
worker; inside_flatten_zones is the pure exclusion helper. Scene/GPU creation
stays on the main thread with a2ms upload budget and4x4 coverage-cell batches.
Cancellation is mutex-protected and joined at exit. Initial generation happens
in the background; completion is exposed in world_canopy_pending telemetry.
The test40km world has1,749,103 distant crowns, about80MiB of raw GPU transforms;
not free memory. This is a whole-world persistent layer, not additional detailed
models/collisions. Consider a versioned visual cache for faster repeated startup.
Review coastal_distance_review with --forest-only --far-forest --whole-forest;
add --sea-level for offshore views. All runs require --shipyard-playtest.
