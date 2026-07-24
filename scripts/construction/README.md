# Construction engine

Parametric structure for vessels and land buildings. Structure is **drawn**,
not stacked.

| Script | Role |
|--------|------|
| `structure_plan.gd` | `structure_plan_v1` document model |
| `structure_baker.gd` | Plan → merged meshes + matching collision boxes |
| `structure_material_library.gd` | Global construction surfaces (textures + PBR + categories) |
| `structure_item_catalog.gd` | Equipment/decor registry (**empty this pass**) |
| `structure_studio_math.gd` | Pure drag/clamp / mirror helpers |
| `structure_studio_openings.gd` | Pure opening defaults / snap / ghost geom |
| `structure_studio_help.gd` | Help overlay copy |
| `structure_studio_document.gd` | Plan path / naming helpers |
| `structure_studio_inspector.gd` | Inspector row factories |

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

Demos:
- `demo_workboat.json` — vessel shell + cargo deck
- `demo_bridge_cabin.json` — compact wheelhouse cabin
- `demo_fish_hold.json` — open-top hold
- `demo_harbour_shed.json` — brick shed on concrete apron
- `demo_quay_office.json` — two-storey quay office
- `demo_canopy.json` — free-wall canopy + corrugated roof

## Studio UX notes

Dirty title asterisk, overwrite/load/new confirms, 45s named autosave,
material category filters + search, building plot sizes, deferred rebake
for gizmo/spin edits, Esc cancel for staged moves, mirror (X / Shift+X),
eyedropper (E), entity list picker, raise-to-level, opening type cycle.
