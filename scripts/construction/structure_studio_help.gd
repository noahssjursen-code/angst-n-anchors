class_name StructureStudioHelp
extends RefCounted

## Help copy for Structure Studio (H / ? overlay).


static func text() -> String:
	return """STRUCTURE STUDIO — KEYS

Tools
  Q  Select / move / resize
  W  Wall run
  R  Room
  D  Deck plate
  O  Opening
  1–3  Opening type (while Opening tool)
  1–5  Tool shortcuts (otherwise)

Edit
  Arrows       Nudge selection (Shift+Up/Down = level)
  Face pads    Resize
  Axis arrows  Move
  Del          Delete
  Ctrl+D       Duplicate
  Ctrl+C / V   Copy / paste selection
  X / Shift+X  Mirror on mid X / Z
  E            Sample selection into armed material slot
  Tab / Shift+Tab  Cycle selection
  Esc          Cancel drag / clear selection

View
  T  Toggle roofs
  G  Ghost upper decks
  F  Focus selection (or whole structure)
  PgUp/PgDn        Level ± step
  Shift+PgUp/PgDn  Level ± storey (3 m)
  RMB orbit · MMB pan · wheel zoom

File
  Ctrl+S  Save (confirms overwrite)
  Ctrl+N  New plan (confirms if dirty)
  Ctrl+Z / Ctrl+Shift+Z / Ctrl+Y  Undo / Redo
  Named plans autosave every 45s while dirty

Surfaces
  Arm Outside or Inside, then click a material or colour.
  Filter materials by category (finish / timber / metal / …).
  Rooms are two-sided; walls become two-sided when Inside is painted.

Building plots
  Top-bar size picker: 16 / 24 / 32 / 48 m square.

Items / equipment arrive in a later pass — the Items tool is reserved."""
