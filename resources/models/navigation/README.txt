Norwegian shallow-water pointer poles

Original Blender-authored jernstang med viser, exported as navigation/jernstang.glb.
Source and reproducible builder: _source/navigation_marks/jernstang.blend and build_jernstang.py.
Metres; origin at mean waterline; arm points along local +X. 3.2 m exposed height,
0.13 m shaft diameter, buried stem down to -5 m. PointerTip socket verifies yaw.
Black painted iron uses the existing ambientCG Paint004 colour, roughness and
OpenGL normal maps (CC0); tint baked for correct glTF export. Shared static mesh.
Material source: https://ambientcg.com/view?id=Paint004

Reference convention: the arm points toward navigable water. It does not specify
a guaranteed clearance distance or a draft suitable for every ship.
https://www.kystverket.no/en/fairway/lightshouses-and-navigations-marks/standard-for-norwegian-coast/
https://sjomerker.no/stang
No reference photographs or third-party meshes are distributed.

CoastalSeamarks derives stable records from the seeded coastline and seabed.
Sites are submerged rock crests 1.5-4 m deep, at least 80 m from the shore, at least 450 m apart and 450 m from port anchors.
The pointer sector is checked for increasing depth and at least 12 m at 160 m.
Only nearby marks (2.6 km) are instantiated; no per-pole processing or lighting.
World runtime creates the layer after terrain setup. Existing seeds regenerate
identical marks. This pass covers coastal shelves, not a complete official chart
marking scheme. No lights, collision, cardinal marks or grounding mechanics added.

Review: scenes/showcases/seamark_showcase.tscn, arrows orbit/zoom.
Run with -- --shipyard-playtest; --capture archives close and approach screenshots.
Tests: tests/coastal_seamarks_test.tscn checks three seeds, deterministic placement,
depth sector, spacing, port exclusion, actual imported pointer yaw and streaming.
Final shape follows the supplied user photograph: short horizontal rectangular plate, no angled arm or brace.
