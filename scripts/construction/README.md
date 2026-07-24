# Construction engine

Parametric structure for vessels and land buildings. Structure is **drawn**,
not stacked.

| Script | Role |
|--------|------|
| `structure_plan.gd` | `structure_plan_v1` document model |
| `structure_baker.gd` | Plan → merged meshes + matching collision boxes |
| `structure_material_library.gd` | Global construction surfaces (textures + PBR) |
| `structure_item_catalog.gd` | Equipment/decor registry (**empty this pass**) |

## Authoring

- App: `scenes/apps/structure_studio.tscn`
- Plans: `resources/data/structures/*.json`
- Materials: `resources/data/materials/structure_materials.json`
- Albedo textures: `resources/textures/materials/structure/`
- Items (later): `resources/data/structures/item_catalog.json`

## Runtime

`DeckFitout.apply_any` routes `structure_plan_v1` to `apply_plan` (baker +
walk colliders + `PlanItems` mounts). Compliance/budgets still skip plans.

## Inspect

`scenes/showcases/structure_studio_showcase.tscn` — F6 bake/material inspect.
Demos: `demo_workboat.json` (vessel), `demo_harbour_shed.json` (building).

## Helpers

`structure_studio_math.gd` — pure drag/clamp math used by Structure Studio
(and covered by `tests/structure_construction_test.tscn`).
