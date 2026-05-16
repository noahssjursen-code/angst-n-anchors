# Mesh Authoring Guide — Angst 'n Anchors

Reference for the in-house low-poly mesh AI. Study the existing files in this folder before generating a new one.

---

## File format

Every file in this folder is a **multi-part model assembly** — the same format `ModelAssembler` reads. There is no bare `{vertices, indices}` file format in production; everything is wrapped in the parts structure.

```json
{
  "name": "model_name",
  "parts": [
    {
      "name": "part_name",
      "mesh": {
        "vertices": [x, y, z,  x, y, z, ...],
        "indices":  [i, i, i,  i, i, i, ...]
      },
      "role": "physics_body",
      "position": [0, 0, 0],
      "rotation_degrees": [0, 0, 0],
      "scale": 1,
      "material": "material_name",
      "color": [r, g, b],
      "roughness": 0.85,
      "metallic": 0.0,
      "collision": "convex"
    }
  ]
}
```

---

## Coordinate system

Godot 4 uses **Y-up, right-handed**.

| Axis | Direction |
|------|-----------|
| +Y   | up        |
| +X   | right     |
| -Z   | forward (into screen by default) |

Model origin should sit at a natural anchor point — typically the **centre of the base** for buildings and props, the **waterline centre** for hulls. `MeshTransformer` re-centres bounds, but author meshes centred anyway.

---

## Vertices

- Flat array of floats: `[x0, y0, z0, x1, y1, z1, ...]`
- No normals. No UVs. `SurfaceTool` auto-generates smooth normals from the geometry.
- No per-vertex colour. Colour comes from the part's `color` field.
- Units are **Godot world units (metres)**. A human is ~1.8 m tall.

---

## Indices and winding

- Flat array of ints: `[a, b, c, a, b, c, ...]` — three per triangle.
- Winding is **counter-clockwise when viewed from outside** (Godot default front-face).
- Every enclosed volume must be **fully closed** — no missing faces unless the part is intentionally open (e.g. a flat wall panel).

### Standard closed box — vertex layout and index recipe

This pattern appears in almost every file. Memorise it.

```
Vertices (8):
  0: (-hx, -hy, -hz)   bottom ring, -Z corner
  1: ( hx, -hy, -hz)
  2: ( hx, -hy,  hz)
  3: (-hx, -hy,  hz)
  4: (-hx,  hy, -hz)   top ring
  5: ( hx,  hy, -hz)
  6: ( hx,  hy,  hz)
  7: (-hx,  hy,  hz)

Indices (36 — 12 triangles, 6 faces):
  Top:    4,5,6, 4,6,7
  Bottom: 0,2,1, 0,3,2
  Front:  0,1,5, 0,5,4
  Right:  1,2,6, 1,6,5
  Back:   2,3,7, 2,7,6
  Left:   3,0,4, 3,4,7
```

> **Check**: each face's two triangles share the diagonal edge and together cover the quad without gaps or overlap.

---

## Common shape recipes

### Flat quad (open panel / window / wall face)

Two triangles only. Used for windows, thin wall cladding, and any face where backfaces aren't visible.

```
Vertices (4): four corners of the plane, any order that keeps them planar.
Indices (6):  0,1,2, 0,2,3   (CCW from the visible side)
```

### Prism / tapered box (hull sections, roof peaks)

Two rings of vertices at different Y heights, where the upper ring is smaller. Connect with side quads exactly like the standard box.

- `cargo_ship_hull` `hull_upper` and `keel_lower` show a tapered hull this way.
- `open_warehouse` `gabled_roof` uses a ridge polygon (two points at peak) with fan triangles on each slope.

### Polygon ring extrusion (bollards, posts, octagonal columns)

Place N vertices around a circle at the base, duplicate the ring at the top, connect with 2N triangles (N quads). Cap the top and bottom with N−2 triangles each (fan from first vertex).

- `docking_bollard` `central_post` is an 8-gon extrusion (r ≈ 0.15 m, 8 vertices per ring).
- Circle approximation: `x = r*cos(i * 2π/N)`, `z = r*sin(i * 2π/N)`.

### Pyramid / spike (antenna, beacon cap)

Base ring of N vertices + one apex vertex.

```
Vertices: base ring [0..N-1], apex [N]
Side:  for each i: triangle(i, (i+1)%N, N)
Base:  fan from 0: triangle(0, i+1, i+2) for i in [0..N-3]
```

- `cargo_ship_hull` `comm_antenna` uses a square base (4 verts) + apex.

### Organic / island silhouette (fan from centre)

Define an irregular polygon ring (your silhouette), place a centre or peak vertex, fan triangles inward.

- `starter_island` `granite_base`: outer ring at Y=0, inner elevated ring at Y≈2.5, connected with side quads; top capped with a fan.
- `starter_island` `tundra_surface`: 7-vertex polygon fan to a single centre peak.

### Repeated identical sub-shapes in one mesh

Pack multiple identical shapes (pillars, pilings, cleats) into a single part by simply concatenating their vertices and offsetting their indices.

```
Shape A uses vertices 0–7,  indices reference 0–7.
Shape B uses vertices 8–15, indices reference 8–15.
```

- `concrete_pier` `support_pillars`: 6 pillars packed into one part, each 8 vertices.
- `dock` `support_pilings`: 8 pilings, each 8 vertices, indices striding by 8.

---

## Parts and roles

Split a model into **as few parts as needed** to express distinct materials or collision requirements. Don't split for splitting's sake.

| `role`        | Meaning |
|---------------|---------|
| `physics_body`| Primary physical presence. Usually gets collision. One per logical rigid body. |
| `visual`      | Decorative geometry. May or may not have collision. |
| `interactable`| Player can interact with this part (e.g. desk, cleat, beacon). |

`ModelAssembler` treats `role` as a free tag. Higher-level game systems attach meaning to it.

---

## Collision

| `collision` value | When to use |
|-------------------|-------------|
| `"convex"`        | Default for solid props. Jolt handles these perfectly on dynamic bodies. |
| `"none"`          | Decorative-only parts: windows, railings, cosmetic layers. |
| `"concave"`       | Static environment geometry only (open warehouse walls, roof slopes). **Never on a dynamic body** — Jolt silently ignores it. |

When a shape is concave (hollow, open-fronted building), split it into convex pieces that together approximate it, each with `"collision": "convex"`. Or keep the shell as `"collision": "concave"` and accept it's static.

One special-case field seen in `cargo_ship_hull` `bridge_structure`:
```json
"invert_collision_face_winding": true
```
Use this when `MeshTransformer` produces an inside-out convex hull (symptom: collider appears inverted). Rare — only needed when geometry reads as concave to the collision builder.

---

## Materials and colour

`material` is a **free-form string tag**. The runtime may map it to a cached `StandardMaterial3D` with additional shader effects, or ignore it and use only `color`, `roughness`, and `metallic`.

**Always fill `color`, `roughness`, and `metallic` with accurate values** — they're the guaranteed fallback.

### Material presets observed in existing meshes

| Tag | Typical use | color (approx) | roughness | metallic |
|-----|-------------|-----------------|-----------|---------|
| `weathered_wood` | dock planks | (0.55, 0.38, 0.25) | 0.95 | 0.0 |
| `dark_wood` | pilings | (0.35, 0.25, 0.15) | 1.0 | 0.0 |
| `aged_wood_plank` | crate panels | (0.38, 0.28, 0.20) | 0.85 | 0.0 |
| `structured_timber` | crate frame | (0.52, 0.42, 0.32) | 0.70 | 0.0 |
| `polished_wood` | desk, furniture | (0.40, 0.25, 0.15) | 0.30 | 0.0 |
| `teak_wood` | handrail | (0.35, 0.20, 0.12) | 0.30 | 0.0 |
| `weathered_iron` | bollard, fittings | (0.15, 0.16, 0.18) | 0.75–0.80 | 0.60–0.70 |
| `forged_iron` | cleats | (0.20, 0.20, 0.20) | 0.40 | 0.80 |
| `railing_steel` | ship railings | (0.18, 0.18, 0.20) | 0.62 | 0.35 |
| `polished_chrome` | luxury fittings | (0.80, 0.80, 0.85) | 0.10 | 1.0 |
| `dark_steel` | superstructure | (0.15, 0.15, 0.18) | 0.60 | 0.50 |
| `hull_paint_black` | ship hull exterior | (0.10, 0.10, 0.11) | 0.82 | 0.0 |
| `keel_anti_fouling` | keel undercoat | (0.55, 0.08, 0.08) | 0.80 | 0.0 |
| `superstructure_paint` | bridge/cabin exterior | (0.74, 0.74, 0.76) | 0.72 | 0.0 |
| `deck_steel` | flat ship deck | (0.30, 0.30, 0.32) | 0.88 | 0.04 |
| `concrete` | pier deck, floor | (0.62, 0.61, 0.58) | 0.90 | 0.0 |
| `concrete_dark` | pier pillars | (0.42, 0.41, 0.39) | 0.92 | 0.0 |
| `concrete_painted` | beacon | (0.90, 0.90, 0.90) | 0.40 | 0.10 |
| `steel_frame` | warehouse frame | (0.20, 0.20, 0.22) | 0.55 | 0.60 |
| `cladding` | warehouse walls | (0.68, 0.68, 0.70) | 0.78 | 0.10 |
| `roofing_panels` | warehouse roof | (0.24, 0.25, 0.27) | 0.84 | 0.08 |
| `reinforced_glass` | bridge windows | (0.40, 0.60, 0.70) | 0.10 | 0.90 |
| `emission_glass` | beacon light | (1.0, 0.3, 0.1) | 0.10 | 0.0 |
| `weathered_granite` | island base | (0.32, 0.34, 0.38) | 0.85 | 0.10 |
| `mossy_turf` | island surface | (0.18, 0.28, 0.15) | 0.95 | 0.0 |
| `cold_sand` | shoreline | (0.55, 0.52, 0.48) | 1.0 | 0.0 |

Invent new tags freely — use a descriptive snake_case name. Keep colour values physically plausible.

---

## Position, rotation, scale per part

- `position` offsets the part **relative to the model origin** (not world).
- `rotation_degrees` is Euler XYZ.
- `scale` is uniform. Use it for variation (e.g. `0.8` for a smaller radar dish).
- Most parts sit at `[0,0,0]` with `[0,0,0]` rotation and `scale: 1`. Only set these when a part genuinely needs to be displaced or rotated within the assembly.

Example from `starter_island` — beacon placed on the hilltop:
```json
"position": [-3, 2.8, 4],
"rotation_degrees": [0, 15, 0],
"scale": 1
```

---

## Size reference

| Object | Approximate bounds |
|--------|-------------------|
| Wooden crate | 2×2×2 m |
| Docking bollard | 0.8 m wide, 1 m tall |
| Dock plank strip | 10 m long, 0.3 m thick |
| Concrete pier | 20.6 m × 4 m × 2 m |
| Cargo ship (whole) | ~20 m long, 4 m wide |
| Open warehouse | 20 m × 30 m × 8.5 m peak |
| Starter island | ~18 m across, 3 m tall |

---

## Authoring checklist

Before outputting a mesh file:

- [ ] Every volume is **closed** (no missing faces) unless intentionally open.
- [ ] All triangles face **outward** (CCW winding from outside).
- [ ] `physics_body` parts that need collision have `"collision": "convex"` (not `"concave"` unless static env).
- [ ] At least one part carries `"role": "physics_body"` if the object needs to be solid.
- [ ] `color`, `roughness`, `metallic` filled with physically plausible values on every part.
- [ ] Model is centred: origin at base centre or waterline centre.
- [ ] Coordinates are in metres. Nothing absurdly large or tiny relative to the size table above.
- [ ] Vertices array length is divisible by 3. Indices array length is divisible by 3.
- [ ] No index in `indices` exceeds `(vertices.length / 3) - 1`.
