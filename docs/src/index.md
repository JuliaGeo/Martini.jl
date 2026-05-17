```@meta
CurrentModule = Martini
```

# Martini.jl

A Julia port of [Mapbox Martini](https://github.com/mapbox/martini): real-time
**R**ight-**T**riangulated **I**rregular **N**etworks for terrain mesh generation.
Given a `(2^k + 1) × (2^k + 1)` heightfield, it generates a hierarchy of
triangle meshes at any error threshold in milliseconds.

Based on ["Right-Triangulated Irregular Networks" by Will Evans et al. (1997)](https://www.cs.ubc.ca/~will/papers/rtin.pdf).

## Install

```julia
import Pkg
Pkg.add(url = "https://github.com/JuliaGeo/Martini.jl")
```

## Quick start

```julia
using Martini

m = Mesher(257)                                # 2^8 + 1 grid
tile   = create_tile(m, terrain)               # length-65 025 Vector{Float32}, y-major
mesh   = get_mesh(tile; max_error = 10)        # 10-metre approximation error
```

Output:

* `mesh.vertices  :: Vector{Tuple{UInt16, UInt16}}` — each element is a
  **1-based** `(x, y)` grid coordinate in `[1, grid_size]`.
* `mesh.triangles :: Vector{Tuple{UInt32, UInt32, UInt32}}` — each element is
  a triple of 1-based indices into `mesh.vertices`.

For WebGL/OpenGL, subtract 1 from both `vertices` and `triangles` — or use
GeometryBasics' `GLTriangleFace`, which stores 0-based offsets natively:

```julia
using GeometryBasics
mesh = get_mesh(tile;
    max_error  = 10,
    point_type = Point2{UInt16},
    face_type  = GLTriangleFace,
)
```

## Type parameters

* `Tile{T<:AbstractFloat}` is inferred from `eltype(terrain)`: pass
  `Matrix{Float64}` to get a `Tile{Float64}`. Default is `Float32`.
* `Mesh{P,F}` is controlled by the `point_type` and `face_type` kwargs.
  Both default to plain `NTuple`s (no GeometryBasics runtime dep). Any
  callable that accepts `T(x, y)` / `T(a, b, c)` works, plus `Tuple`
  subtypes via a tuple-arg path.
* `MesherCache(mesher)` — preallocated scratch buffer; pass `cache = …`
  in hot loops to avoid the per-call index-map allocation.

## How it works

`Mesher(grid_size)` precomputes the implicit binary tree of right triangles
that subdivide the tile recursively. The tree has `tile_size² × 2 − 2` nodes —
one for every potential triangle at every level. Coordinates are packed into a
flat `Vector{UInt16}` indexed by triangle id.

`create_tile(mesher, terrain)` walks that tree **bottom-up**, computing the
per-vertex maximum error: each non-leaf triangle's long-edge midpoint records
the worst of its own approximation error and any descendant's error.

`get_mesh(tile; max_error)` walks the tree **top-down**, emitting a triangle
whenever the midpoint error is at or below `max_error`. Otherwise it recurses
into the two children. Two passes — first count vertices and triangles for
allocation, then fill the flat buffers.

## Numerical parity with JS

Internal arithmetic uses `Float64` intermediates and `Float32` storage,
mirroring how JavaScript treats `Float32Array` reads as `Number` (F64) and
only truncates on store. This yields **byte-identical** output to the
reference `@mapbox/martini` library on the `fuji.png` fixture at every
threshold tested.

## See also

* [`Mesher`](@ref), [`MesherCache`](@ref), [`Tile`](@ref), [`Mesh`](@ref)
* [`create_tile`](@ref), [`get_mesh`](@ref)
* [Mapbox Martini](https://github.com/mapbox/martini) — the original JavaScript
* [pymartini](https://github.com/kylebarron/pymartini) — Python port
