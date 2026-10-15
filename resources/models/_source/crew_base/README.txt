CREW BASE — anatomical player and NPC visual

This is a new unclothed adult base. It does not load or reuse geometry from
mariner or the previous procedural character. Existing movement, authority,
collision and equipment logic remain separate from this visual asset.

SOURCE AND LICENSE
The anatomical topology, source rig data, skin weights and eye geometry are
MakeHuman graphical assets under CC0. Exact immutable upstream URLs, hashes
and license copies are in reference/source_manifest.json and reference/.
Only asset data is vendored; no MakeHuman application code is executed.

REBUILD
Run Blender in background with tools/build_crew_base_blender.py from the repo.
The builder reads the adult male target and applies the source-authored skin
weights to a 50-bone game rig. Source geometry is transformed into the game's
lower A pose. The final editable source is crew_base.blend; runtime export is
resources/models/crew_base/crew_base.glb.

COMPATIBILITY
Height is 1.80 metres before animation. Source convention is Blender Z-up,
forward +Y; glTF exports Godot Y-up, forward -Z. Left limbs are positive X.
Mesh names: Body, Head, Neck, Hands, Eyes. Skin is a tintable matte material.
The material UV coordinates and eye texture are retained from the source.
Head/Neck/Eyes may be hidden for first-person view without hiding Hands.

The skeleton retains root, hips, spine, chest, neck, head, clavicles, articulated
arms/hands and three joints per finger (two thumb joints). The animation
contracts are idle, walk, run and seated. Movement clips use fixed bone lengths;
only hips translate. Hand contacts and handle grip poses are regenerated from
the new rig, not copied from the rejected model.

No clothing, hair, accessories or wardrobe variants are part of this base.
Build/Belly/Frame/Age morph targets are intentionally not authored yet.
Contact JSON includes zero morph deltas so current optional-morph consumers
can use the new base without special cases.

REVIEW
Run tools/review_crew_base_blender.py for actual rest/idle/walk/run/seated and
hand/foot captures. Captures are archived with unique names under
C:/Users/noahs/Pictures/machinescreenshots. The native integration test and
showcase are maintained by the parent task. Blender renders are geometry
reviews and do not substitute for native movement/attachment checks.
