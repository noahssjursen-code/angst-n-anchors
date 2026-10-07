# Blender character contract

The visual target is Noah's angular maritime characters: square head, restrained
face, practical clothes and patterned knit. Do not replace this with rounded
realistic anatomy. Spend geometry on bevels, silhouettes, hands and deformation.

`mariner.glb` is the shared body, skeleton and modular wardrobe. Editable source:
`../_source/characters/mariner.blend`. Rebuild using Blender in background with
`tools/build_character_blender.py`; geometry lives in `tools/mariner_geometry.py`.
Source coordinates: metres, Z up, +Y forward; Godot: Y up, -Z forward.
Noah rejected the downloaded character/clothing replacements on 7 October.
Continue from this original in-house mariner. Do not reintroduce those assets.
`tools/mariner_refinement.py` improves the original hands, cap, sweater and
trouser topology and weights; it does not replace the character with a new body.

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
- All four clips (idle, walk, run, seated) were discarded and authored afresh.
  `tools/mariner_animation.py` uses local FK rotations for shoulders/elbows/hands.
  Only the pelvis translates. Never key elbow/wrist locations or scale limb bones;
  never drive arms with moving wrist targets or changing elbow poles. Arms swing
  opposite their same-side legs, without artificial axial twist. Legs use a
  fixed-length two-bone solve baked to rotations at 60 Hz, with heel/toe roll and
  continuous lift-off/landing trajectories. This is authored ground contact,
  not runtime terrain IK or a facial animation rig.
- Walk: 1-second cycle, 1 metre per loop. Run: .7-second cycle, 1.579 metres per
  loop (2.256 m/s). CharacterAnimator smooths speed, uses transition hysteresis,
  crossfades and adjusts playback rate. Ambient NPCs seek by travelled distance.
  Physics and game movement speeds are unchanged; playback is capped at 2.3x.
- Review `scenes/showcases/character_motion_showcase.tscn` in motion. Studio
  playback control supports pausing and slow motion; press J in the motion review
  to display the actual moving skeleton. `animation_contract.json`
  records clip timing and authored stance samples for regression checks.
- Build, Belly, Frame and Age are four independent relative shape keys, each
  authored from Basis. Never generate one from the preceding shape or mixed state.
  Every garment receives the identical deformation mapping.
  Correct hand bind orientation BEFORE generating its shape keys so extreme body
  sliders cannot displace hands away from the sleeves.
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
The motion scene accepts `--heavy` for combined maximum body sliders and
`--frames <directory>` for a 120-frame Godot capture. Put captures under
`C:/Users/noahs/Pictures/machinescreenshots` with a unique directory name.
Regression checks cover every imported frame's fixed joint offsets and scale,
continuous arm rotations, loop seams, opposing arm/leg swing and foot travel.
`mesh_stats.json` records Blender counts; imported vertex counts may grow at UV
and material seams. Retired character JSON models must remain deleted.
