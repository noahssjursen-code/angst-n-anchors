# Seated passenger crowd

Original in-house asset derived from `../mariner.glb`, whose editable upstream
source is `_source/characters/mariner.blend`. No downloaded character or new
third-party license. Rebuild with Blender on
`_source/coastal_express/build_seated_passenger.py`; the editable baked pose is
saved beside that generator as `seated_passenger.blend`.

The generator evaluates the approved seated pose, removes hidden body/clothing
layers and narrows the civilian build for a 0.5 m seat pitch. Player geometry,
clips, skeleton and runtime IK remain untouched. UVs and named materials survive;
runtime finishes reuse `SurfaceMaterialLibrary.character_material`.

The near mesh has 6992 triangles; far has 1794. Full 240-seat geometry would be
about 1.68 million / 431 thousand triangles before engine import LOD. These are
geometry budgets, not a measured frame cost. Ten mesh parts are shared through
MultiMesh batches in four clothing/skin variants, with no per-person controller,
physics body or skeleton. Detail switches at 80 m; cabin occupants stop drawing
at 450 m. Gameplay count, mass and fares are independent of this visibility.

These are static seated crowd poses. They do not yet represent walking queues,
individual luggage, animated boarding or varied body/age appearances.
