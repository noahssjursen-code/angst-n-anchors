# Character appearance and wardrobe

Players and NPCs share one `CharacterAppearance` record and one
`CharacterVisual` renderer. The record is JSON-safe: gameplay, saves, and a
future multiplayer server replicate ids and colours rather than scene nodes.

## Data ownership

- `catalog.json` is the source of available body presets, wardrobe entries,
  complete working-look presets, and company-uniform roles.
- `resources/data/models/characters/npc_character_study.json` is the approved
  base body.
- `resources/data/models/characters/wardrobe/` contains JSON models generated
  by `scripts/apps/character_wardrobe_author.gd`.
- `scripts/character/character_visual.gd` equips only the selected model for
  each slot and applies personal and company colours.

Do not add a separate player-character mesh or an NPC-only clothing system.
The same appearance record must produce the same character in onboarding, the
F6 showcase, single-player NPCs, and remote multiplayer presentation.

## Adding a cosmetic

1. Add the catalog entry and its stable `inventory_key`.
2. Add its block-model recipe to `character_wardrobe_author.gd`.
3. Run the author once to regenerate the wardrobe JSON models.
4. Add or update a complete outfit preset that proves the item works with the
   rest of the silhouette.
5. Run `tests/character_wardrobe_test.tscn` and inspect
   `scenes/showcases/character_customization_showcase.tscn`.

`trade_policy` is metadata for a future authoritative inventory service. An
equipped id never proves ownership; a server or local single-player authority
must validate owned cosmetics before accepting an appearance update.

## Onboarding

`CharacterCreatorPanel` is step 1 of the single-player captain flow. Company
identity and the starter vessel are step 2, followed by the existing home-port
chart. `scenes/showcases/captain_onboarding_showcase.tscn` is the isolated F6
review scene for the first two steps.
