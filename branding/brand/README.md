# Angst 'n Anchors — Brand Kit

Single source of truth for the game's visual identity. **Agents: read `tokens/design-tokens.json` first.**

## Rules that are not negotiable

1. **No hex literals in scenes, shaders or UI code.** Reference a token by name. A colour that is not in the map is a bug, not a choice.
2. **AMBER (#F2B233) is marketing-only.** Capsules, thumbnails, logo tile. It must not appear in a running build. In-game accent is BRASS (#D99A1F).
3. **HULL_\* is player paint.** It is the only family allowed on player-authored surfaces, and it never appears in UI.
4. **Night, storm and dusk come from lighting**, not from darker duplicate colours.
5. **No chamfered corners, no rounded corners.** See `shapes` in the tokens file.
6. **Data is mono, never bold.** Speed, headings, coordinates, ℳ amounts, MMSI.
7. **Every label has +40% width headroom.** Fixed-width text containers are forbidden — the game will be localised.

## Files

```
brand/
  tokens/
    design-tokens.json   colour + spacing + type + motion + shapes. THE source.
    palette.json         flat TOKEN -> hex lookup
    palette.gd           Godot: class_name Palette, const Color per token + ALL dict
    palette.css          CSS custom properties for web/marketing
  logo/
    anchor-mark.svg              master mark, marine
    anchor-mark-ink.svg          single-colour variants
    anchor-mark-paper.svg
    anchor-mark-brass.svg
    anchor-mark-amber-tile.svg   primary treatment (marine on amber)
    lockup-horizontal.svg        mark + wordmark + tagline
    lockup-stacked.svg
    png/                         16 / 32 / 64 / 256 / 1024 in 4 colourways (20 files)
  currency/
    mark-glyph.svg               the Marks currency glyph
```

## Colour map

146 tokens in 14 families: PAPER, INK, SEA, BRASS, STATUS (UI) · WATER, TERRAIN, FOLIAGE, SKY, BUILT (world) · HULL, CARGO, LIGHTS (objects) · CHART (navigation overlay).

Godot:

```gdscript
modulate = Palette.SEA
$Panel.self_modulate = Palette.get_color("PAPER_HIGH")
```

## Type

| Role | Family | Notes |
|---|---|---|
| Display | Saira Condensed 700 | titles, section heads, big numbers |
| UI / dialogue | Saira 400–600 | body, buttons, NPC speech |
| Data | JetBrains Mono 400/700 | AIS, gauges, prices, coordinates |
| Cyrillic display | PT Sans Narrow 700 | **Saira has no Cyrillic** |
| Cyrillic UI | PT Sans | ru/uk locales |

All Google Fonts, SIL OFL — free to bundle and ship.

Locale font table: `en/de/fr/es/it/pl → Saira · ru/uk → PT Sans · data → JetBrains Mono (all locales)`

## Fonts to bundle

Saira Condensed 600/700 · Saira 400/500/600 · JetBrains Mono 400/700 · PT Sans Narrow 700 · PT Sans 400/700

## Lockup note

The SVG lockups set the wordmark as live text in Saira Condensed 700. If you need them font-independent (print, third-party use), convert text to paths before sending them out.

## Voice

Deadpan, maritime, specific. "Storm in 3 hours" beats "Danger approaching!". The game never congratulates the player. No exclamation marks in system text.

---
Generated 2026-07-27 · palette v1.0.0 · regenerate token files from the styleguide, never hand-edit them.
