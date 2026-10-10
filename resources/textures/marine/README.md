# Shared physical materials

This library finishes imported ships, fittings, port facilities, cranes, cargo
and clothing. PNGs are original **ambientCG downloads**, not generated substitutes.
`sources.json` records official pages, downloads, CC0 licensing and file SHA256.
`MetalPlates001` is the hull plate source Noah chose.

## System

- `profiles.json`: surface finish, repeat size in metres, roughness, relief,
  metallic response and colour treatment. Several finishes reuse each source.
- `assignments.json`: authored material names/prefixes and narrow asset overrides.
  Existing `Office render` also occurs on tank shells and cardboard loads; those
  exceptions must not become global mappings. New Blender assets need accurate
  physical material names.
- `SurfaceMaterialLibrary`: lazy immutable materials, paint variants, rest-frame
  mapping, deforming clothing UVs and finished MultiMesh prototypes.
- `marine_surface.gdshader`: rigid-asset projection. Pavement retains continuous
  world coordinates; skinned clothing retains authored UVs and printed albedo.
- `scenes/showcases/material_library_showcase.tscn`: isolated F6 review. Number
  keys select ships/facilities/swatches; C clothing, V cargo, X bulk, N lighting,
  B original/new, P archived photo. Right-drag/wheel orbit/zoom. Swatches always
  show the library itself, not a baseline.

## Add a physical item

1. Select an appropriate existing profile, retaining separate names for paint,
   exposed metal, seals, glass and upholstery.
2. For a missing source, inspect its official page, then use
   `python tools/material_library.py --fetch AssetID`. Do not invent source IDs
   or relabel generated images as downloads.
3. Import once in Godot, run `--configure-imports`, then reimport. Original 1K
   maps use high-quality VRAM compression and mipmaps. Albedo is sRGB; roughness,
   metalness and OpenGL normal channels are data. No displacement geometry added.
4. Add the physical profile and exact semantic assignment. Call
   `SurfaceMaterialLibrary.apply(root, asset_context)` after assembly, before
   motion. Apply to detailed and distant models. `finished_mesh()` carries
   overrides into MultiMesh after the prototype is freed; never mutate imported
   mesh material slots.
5. Run `python tools/material_library.py --verify --audit`, the material contract
   scene and affected gameplay checks. Inspect close/assembled daylight and
   artificial-light renders, moving parts and distant mip behaviour. Archive
   every capture under Noah's `Pictures/machinescreenshots`.

## Seams, moving parts and colours

Rigid surfaces project in the asset rest frame. Adjacent ship panels are mapped
into a common vessel frame after placement and miter fitting so the phase agrees
at joins. Mapping then stays fixed while boat, doors and controls move. World
projection makes vessel textures swim and must not replace this.

Imported halfwalls contain some inward-facing triangles and two-sided materials.
The shared shader preserves two-sided rendering and flips the back normal.
Reintroducing backface culling exposes inner/end surfaces as apparent railing
seams. Any future source winding migration needs an assembled close-up check.

`ModelPaint` selects immutable cached variants rather than editing shared colours.
Original surface names and hull/deck/wall/upholstery controls remain. Ghosts skip
hidden finishing. Crane/container colour atlases retain their markings and wear;
shared maps supply surface response. Skin, hair, optical/emissive materials,
foliage and accepted ocean/terrain/sky keep their own deliberate paths.

Clothing uses per-character StandardMaterial copies and deforming UVs. Existing
knit prints remain; cloth/rubber/oilskin normal and roughness maps follow the rig.
Never project rigid rest coordinates onto a skinned body.

## Budget and remaining coverage

18 original sets, 61 maps and 40 profiles. Texture resources and immutable
materials are shared, loaded only when used, with bounded material/prototype
caches. The full world exceeded Godot's default instance-uniform allocation.
The Forward+ project reserves 262144 vec4 entries (4 MiB GPU storage, 3 MiB over
default) so modular ships and streamed ports fit. This is not a geometry or
texture budget increase, nor a guarantee for an unlimited number of vessels.

Source audit counts are not visual acceptance. The 11 anonymous `Material` slots
are default `Cube` nodes in parked coastal prototypes with no current gameplay
references found in scripts, scenes or catalogs. Before reuse they need deliberate authoring; procedural
village buildings and Noah's queued terrain overhaul remain outside this pass.
Do not claim every world object is finished from a mapped-name count.

Official sources: https://ambientcg.com/ and https://docs.ambientcg.com/license/ .
Exact individual asset URLs/checksums are in `sources.json`.

## Terrain surfaces

TerrainSurfaceMaps shares original Rock030, Ground037 and Ground048 colour,
OpenGL normal and roughness maps between terrain LODs. Rock uses triplanar
4 m tiles; moss/woodland ground uses 2.1 m tiles and soil 1.4 m tiles.
Procedural macro and forest maps control coverage only. Near detail normals
fade between 80 and 200 m; distant land retains matching colour texture
coordinates. No terrain heights, collisions or saved world identity change.
Review with tests/terrain_material_review.tscn and tests/forest_root_review.tscn
using --shipyard-playtest. Source URLs and original file hashes are in sources.json.

The 10 October terrain pass uses a three-sample triangular offset blend for
Ground037/Ground048 colour, normals and roughness, with explicit texture
footprints for stable mip selection. The shared include is terrain_tile.gdshaderinc.
It uses the tiling/blending idea described by Deliot and Heitz, not their full
histogram-transform algorithm: https://eheitzresearch.wordpress.com/738-2/ .
Separate shader functions retain Godot's required sampler-hint consistency.
The woodland moss mask also blends differently oriented scales to remove its
previous repeating 28 m patch pattern. Source texture files remain untouched.

## Rain exposure

Sourced finishes stay dry unless their caller explicitly supplies `rain_exposed`
to `SurfaceMaterialLibrary.material`. Exposed and sheltered copies have separate
cache keys; do not wet cabins merely because they share paint with an exterior.
Asphalt and crushed aggregate define wet darkening/roughness/relief in
`profiles.json`. Harbour paving/road paint and both terrain LODs use the same
gradual local `SurfaceWetness` amount. Original images remain unchanged.
Coverage, timing, limitations and rendered reviews: `docs/weather-rain.txt`.
