class_name WorldPropLod
extends RefCounted

## Contract for mainland / coastal decorative props.
## Keep decorations cheap: few primitives or low-poly JSON meshes, always with
## distance LOD or fade. Never stream high-detail clutter across the full
## visual terrain radius.

const LOD_NEAR_M := 280.0
const LOD_MID_M := 750.0
const LOD_FAR_M := 1600.0
## Props beyond this are culled entirely (terrain carries the silhouette).
const CULL_M := 2200.0

enum Tier {
	FULL, ## Near: full prop (still low-poly)
	PROXY, ## Mid: simplified impostor / fewer parts
	BILLBOARD_OR_SKIP, ## Far: flat card or omit
	CULLED,
}


static func tier_for_distance(distance_m: float) -> Tier:
	if distance_m > CULL_M:
		return Tier.CULLED
	if distance_m > LOD_FAR_M:
		return Tier.BILLBOARD_OR_SKIP
	if distance_m > LOD_MID_M:
		return Tier.PROXY
	if distance_m > LOD_NEAR_M:
		return Tier.PROXY
	return Tier.FULL


static func should_spawn(distance_m: float) -> bool:
	return tier_for_distance(distance_m) != Tier.CULLED
