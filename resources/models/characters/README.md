# Blender character contract

The visual target is Noah's angular maritime characters: square head, restrained
face, practical clothes and patterned knit. Do not replace this with rounded
realistic anatomy. Spend geometry on bevels, silhouettes, hands and deformation.

`mariner.glb` is the shared body, skeleton and modular wardrobe. Editable source:
`../_source/characters/mariner.blend`. Rebuild using Blender in background with
`tools/build_character_blender.py`; geometry lives in `tools/mariner_geometry.py`.
Source coordinates: metres, Z up, +Y forward; Godot: Y up, -Z forward.

- All parts share the same 42-bone bind pose. Do not attach a second skeleton to
  each garment. Hands and their rest bones are oriented together in the bind pose:
  palms face the thighs with thumbs forward. Never compensate for a wrong hand
  bind pose by twisting the whole forearm or sleeve 90 degrees. Two joints per
  finger/thumb provide relaxed curl. Forearm twist bones are available for later
  interaction poses but have no artificial axial twist in the locomotion clips.
  Hand attachment bones inherit this anatomical orientation.
- Arm and leg shafts use a single segment bone. Blend across the elbow/knee only
  within about 5 cm of the joint, rather than weighting an entire limb by nearest
  bone distance. Preserve the authored joint loops and avoid rubbery shafts.
- Four exported clips: idle, walk, run, seated. `tools/mariner_animation.py` solves
  two-bone limb poses in Blender and bakes quaternion/translation tracks at 60 Hz.
  Walk/run have a linear planted stance and raised swing; no limb may stretch to
  reach its target. The head stays comparatively stable. This is authored ground
  contact, not runtime terrain IK or a facial animation rig.
- Walk: 1-second cycle, 1 metre per loop. Run: .7-second cycle, 2.625 metres per
  loop (3.75 m/s). CharacterAnimator smooths speed, uses transition hysteresis,
  crossfades and adjusts playback rate. Ambient NPCs seek by travelled distance.
  Physics and game movement speeds are unchanged; playback is capped at 2.3x.
- Review `scenes/showcases/character_motion_showcase.tscn` in motion. Studio
  playback control supports pausing and slow motion; press J in the motion review
  to display the actual moving skeleton. `animation_contract.json`
  records clip timing and authored stance samples for regression checks.
- Build, Belly, Frame and Age are four independent relative shape keys, each
  authored from Basis. Never generate one from the preceding shape or mixed state.
  Every garment receives the identical deformation mapping.
- Age is an adult 18–80 appearance control: modest face/posture changes and hair
  greying. It is not a photorealistic ageing simulation.
- Base region meshes Body_Torso/Arms/Legs/Feet are hidden under the matching
  selected garment. Base_Shorts is hidden under trousers. Hair is hidden by hats.
  Head, neck and hands remain. Do not restore coplanar duplicate surface layers.
- Sweater cuff/hem trim uses material regions on the sweater itself, not a second
  surface pasted onto it. Knit texture is UV mapped and packed into the GLB.
- Exposed Skin, Top, Trousers, Footwear, Hair, Headwear and Outerwear materials are
  duplicated per character before tinting. Hardware/trim retain their own colours.
- Appearance schema 6 carries sliders and selections through existing JSON,
  captain saves and replication. No mesh data belongs in a save or network packet.
- These are visual proportions. Player capsule and movement physics are unchanged.

Run `tests/blender_character_test.tscn` and `tests/captain_onboarding_test.tscn`
with `--shipyard-playtest` to isolate persistent saves. The character studio is
`scenes/showcases/character_customization_showcase.tscn`; it offers colour, body,
wardrobe and animation controls, orbit/zoom, plus separate saved-look drafts.
Check neutral and combined maximum morph values in motion and from both sides.
`mesh_stats.json` records Blender counts; imported vertex counts may grow at UV
and material seams. Retired character JSON models must remain deleted.
