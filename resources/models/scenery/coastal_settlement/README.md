# Coastal settlement kit

Original game artwork authored in Blender, not downloaded building models.
Source scenes and repeatable recipe: `../../_source/coastal_settlement/`.
Metres; ground origin; the entrance faces Godot +Z. Three separate reusable
building shells have matching near/far footprints, openings and roof lines.

| Asset | Footprint | Near triangles | Far triangles |
| --- | --- | ---: | ---: |
| Cottage | 8.6 × 7.4 m | 3,046 | 238 |
| Two-storey house | 8 × 10.2 m | 4,054 | 322 |
| Boathouse | 5.8 × 9.6 m | 2,494 | 154 |

Near shells include vertical timber battens, window joinery, sills, bargeboards,
roof seams, rainpipes and entrance steps/canopy. Six shared paint variants retain
separate wall, trim, roof, glazing, door and foundation finishes. Runtime mapping
is explicit in `CoastalBuildingLibrary`, using the existing approved material
profiles: painted_timber (ambientCG Wood096), roof_sheet (Metal032) and
working_concrete (Concrete048). See `../../../textures/marine/README.md` and its
source manifest for the CC0 texture provenance. Glass has its own optical finish.
Far shells merge those surfaces into one draw with averaged finish colours.

The visual references are traditional Norwegian timber houses and working
boathouse groups, interpreted for this game's coast rather than a replica of
any protected building:

- [Riksantikvaren: naust and sjøhus](https://riksantikvaren.no/kystens-kulturmiljo/naust-og-sjohus-sjoen-som-ressurs/)
- [Riksantikvaren: rebuilding the Stekka boathouse group](https://riksantikvaren.no/eksempelsamling/by-og-stedsutvikling/gjenoppbygging-av-naust-i-stekka/)

`CoastalSettlementPlan` follows existing shoreline metadata and rejects water,
port footprints, steep foundations and overlapping plots. It does not change
the world generator, terrain height or saved ports. Buildings and narrow roads
exclude only their occupied forest footprints. `CoastalSettlements` batches
shared meshes into 256 m groups, keeps physical far models visible, and creates
simple building collision only near the player. There are no per-house scripts,
skeletons, distant physics bodies or simulated residents.

These are **closed scenery exteriors**, not enterable houses or new businesses.
The roads are settlement scenery, not a vehicle navigation network. Foundation
placement follows the current terrain triangles without cutting new land pads.

Inspect the kit with `tests/coastal_building_review.tscn -- --shipyard-playtest`;
add `--capture` to exit after the archived close/detail/LOD views. The actual-world
review is `tests/coastal_settlement_review.tscn -- --shipyard-playtest --size=40000`.
Placement checks are in `tests/coastal_settlement_test.gd`. All review captures
go to the user's machinescreenshots archive.

Night windows use the shared solar daylight factor and a stable per-building/
floor occupancy seed. Near glazing and the one-draw far shell use matching
emissive panes; there are no individual point lights, interior simulations or
extra distant draw calls. Add `--night` to the world review for the night series.