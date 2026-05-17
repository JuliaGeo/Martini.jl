# Martini.jl

A Julia port of [Mapbox Martini](https://github.com/mapbox/martini): real-time
RTIN terrain mesh generation from height data. Given a `(2^k + 1) × (2^k + 1)`
heightfield, it generates a hierarchy of triangle meshes at arbitrary level of
detail in milliseconds.

Based on ["Right-Triangulated Irregular Networks" by Will Evans et al. (1997)](https://www.cs.ubc.ca/~will/papers/rtin.pdf).

## Install

```julia
import Pkg
Pkg.add(url = "https://github.com/JuliaGeo/Martini.jl")
```

## Example

```julia
using Martini

# 257×257 grid (2^8 + 1)
m = Mesher(257)

# `terrain` is a length-65 025 (=257²) Vector{Float32} of heights, y-major
# (matches the Mapbox/JS convention). A 257×257 Matrix{Float32} also works.
# Pass a Float64 array to get a Tile{Float64} back (Tile is parametric on
# AbstractFloat).
tile = create_tile(m, terrain)

# 10-metre approximation error.
mesh = get_mesh(tile; max_error = 10)

# mesh.vertices  :: Vector{Tuple{UInt16, UInt16}}     — 1-based (x, y) grid coords
# mesh.triangles :: Vector{Tuple{UInt32, UInt32, UInt32}} — 1-based vertex indices
```

For WebGL/OpenGL output, subtract 1 from both `mesh.vertices` (to land in
`[0, grid_size-1]`) and `mesh.triangles` (to get 0-based indices) — or use
`GeometryBasics.GLTriangleFace`, which stores 0-based offsets natively:

```julia
using GeometryBasics
mesh = get_mesh(tile;
    max_error  = 10,
    point_type = Point2{UInt16},
    face_type  = GLTriangleFace,   # 0-based via OffsetInteger{-1, UInt32}
)
```

### Reusing scratch buffers in hot loops

```julia
cache = MesherCache(m)
for err in 1:50
    mesh = get_mesh(tile; max_error = err, cache)
end
```

`MesherCache` is one allocation per concurrent task. It is deliberately *not*
on the `Mesher` so a single `Mesher` remains thread-safely shareable.

## Layout & indexing notes

- The `terrain` input is laid out **y-major** when supplied as a flat `Vector`:
  `terrain[y * grid_size + x + 1]` for 0-based `(x, y)`. This matches the Mapbox
  PNG decoding pipeline. Internally it's reshape'd to a `Matrix{T}` of size
  `(grid_size, grid_size)`, accessed `terrain[x, y]` with 1-based `(x, y)`.
- Output vertex coordinates in `mesh.vertices` are 1-based, in `[1, grid_size]`.
- Triangle indices in `mesh.triangles` are 1-based — they index `mesh.vertices`
  directly under Julia conventions.

## Reference ports

- [Mapbox Martini](https://github.com/mapbox/martini) — original JavaScript
- [pymartini](https://github.com/kylebarron/pymartini) — Python

## License

ISC (matches upstream).
