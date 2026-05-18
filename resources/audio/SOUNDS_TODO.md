# Crane + Cargo Sound Manifest

Prompts shaped for ElevenLabs SFX generator. Files go into either
`resources/audio/looped/<subsystem>/` or `resources/audio/normal/<subsystem>/`
as marked below. Filenames are what the code will load.

---

## Looped (seamless, no fade)

These should be 2–4 s tonal loops, no fade in/out. Each gated by axis activity.

### `resources/audio/looped/crane/motor_gantry_loop.wav`
> Industrial electric gantry motor on rails — low-pitched humming and rolling sound, steady gear whir, faint metallic creak. Heavy, rumbling, mechanical, no sudden peaks. Seamless 3-second loop.

### `resources/audio/looped/crane/motor_trolley_loop.wav`
> Trolley motor traversing a steel I-beam — mid-pitched whirring belt drive, faint wheel clacking, lighter than the gantry. Smooth and continuous. Seamless 3-second loop.

### `resources/audio/looped/crane/motor_hoist_loop.wav`
> Heavy crane hoist winch under load — deep electric motor whine with a slow rhythmic cable-drum click. Tense, working hard. Seamless 3-second loop.

---

## Normal (one-shots)

### Crane — `resources/audio/normal/crane/`

#### `chain_engage.wav`
> Four heavy steel chains snapping taut against a steel pallet — quick metallic clank-clank-clank-clank in rapid succession, ending in a solid clunk. Crisp, satisfying. 0.6 seconds total.

#### `chain_release.wav`
> Heavy steel chains being released — single solid metallic clunk followed by chain links rattling free. 0.4 seconds.

#### `crane_board.wav`
> A heavy operator pulling himself into a steel cabin seat — leather creak, brief metallic seat squeak, light thud. 0.5 seconds.

#### `crane_exit.wav`
> Operator standing up from a metal seat — leather and seat-spring rebound, light footstep on grated floor. 0.4 seconds.

#### `hook_bottom.wav`
> Crane hoist reaching its lower limit — sharp metallic clunk as a brake engages, faint cable twang. 0.3 seconds.

#### `hook_top.wav`
> Crane hoist reaching its upper limit — similar to hook_bottom but slightly higher pitched, brake clack. 0.3 seconds.

#### `beacon_blink.wav` *(optional)*
> Single soft electrical click — relay clack with the briefest mechanical buzz. Plays each time the red beacon at the top of the crane flashes. 0.1 seconds.

### Cargo — `resources/audio/normal/cargo/`

#### `pallet_set_wood.wav`
> Wooden cargo crate being set down on a hard wooden pallet — solid muffled thunk, faint dust shuffle. Heavy. 0.5 seconds.

#### `pallet_set_barrel.wav`
> Oak barrel set down hard on a wooden pallet — deep hollow boom, the wood ringing slightly. 0.5 seconds.

#### `pallet_set_sack.wav`
> Heavy canvas sack of grain dropped onto a wooden pallet — soft dense thud, dust puff, no bounce. 0.4 seconds.

#### `pallet_set_metal.wav`
> Heavy iron ore crate / metal cargo set onto a steel deck — sharp clanging thud, brief reverberation. Used for iron_ore / coal placements. 0.5 seconds.

#### `pallet_lift.wav`
> Pallet leaving the ground as chains pull tight — creaking wood under sudden tension, small grunt of strained timber. 0.4 seconds.

#### `delivery_chime.wav`
> Cargo sold at port — short bright cash-register-style ding-cha-ching, slightly nautical (could include a faint bell tone). Rewarding, not too loud. 0.8 seconds.

#### `destination_ping.wav` *(optional)*
> Subtle marker / sonar ping — soft mid-frequency bloop, slightly metallic. Plays when an accepted contract spawns its destination beacon. 0.4 seconds.

### UI — `resources/audio/normal/ui/`

#### `contract_accept.wav`
> Contract paper being stamped and signed — quick paper rustle, firm wooden stamp thud, pen scratch. 0.5 seconds.

#### `contract_decline.wav`
> Soft negative UI tone — a short low "nope" beep or a muffled wood-block tap. 0.2 seconds.

#### `menu_open.wav`
> Soft paper or canvas unrolling — quick whoosh / rustle. 0.3 seconds.

#### `menu_close.wav`
> Soft paper or canvas rolling up — quick reverse whoosh. 0.2 seconds.

---

## Wiring notes (for me, after files land)

- Looped motors: `AudioStreamPlayer3D` parented to the trolley/hook/frame, `playing = axis_speed > 0.01`.
- One-shots: spatial 3D for crane/cargo (panned), 2D UI for menu sounds.
- Vol guidelines: motors −12 dB, one-shots −6 dB, chime −3 dB.
