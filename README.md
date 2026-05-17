# Martini.jl

A Julia port of [Mapbox Martini](https://github.com/mapbox/martini): real-time
RTIN terrain mesh generation from height data. Given a `(2^k + 1) × (2^k + 1)`
heightfield, it generates a hierarchy of triangle meshes at arbitrary level of
detail in milliseconds.

Based on ["Right-Triangulated Irregular Networks" by Will Evans et al. (1997)](https://www.cs.ubc.ca/~will/papers/rtin.pdf).

## Install

```julia
import Pkg
Pkg.add(url = "https://github.com/asinghvi17/Martini.jl")
```

## Example

```julia
using Martini

# 257×257 grid (2^8 + 1)
m = Mesher(257)

# `terrain` is a length-65 025 (=257²) Vector{Float32} of heights, y-major
# (matches the Mapbox/JS convention). A 257×257 Matrix{Float32} also works —
# the two layouts share memory once reshape'd internally.
tile = create_tile(m, terrain)

# 10-metre approximation error
mesh = get_mesh(tile; max_error = 10)

# mesh.vertices  :: Matrix{UInt16}  size (2, N) — columns are 1-based (x, y) grid coords in [1, 257]
# mesh.triangles :: Matrix{UInt32}  size (3, M) — columns are 1-based vertex indices
```

For WebGL/OpenGL output, subtract 1 from both `mesh.vertices` (to land in
`[0, grid_size-1]`) and `mesh.triangles` (to get 0-based indices).

## Layout & indexing notes

- The `terrain` input is laid out **y-major** when supplied as a flat `Vector`:
  `terrain[y * grid_size + x + 1]` for 0-based `(x, y)`. This matches the Mapbox
  PNG decoding pipeline. Internally it's reshape'd to a `Matrix{Float32}` of
  size `(grid_size, grid_size)`, accessed `terrain[x, y]` with 1-based
  `(x, y)`.
- Output vertex coordinates in `mesh.vertices` are 1-based, in `[1, grid_size]`.
- Triangle indices in `mesh.triangles` are 1-based — they index columns of
  `mesh.vertices` directly under Julia conventions.

## Reference ports

- [Mapbox Martini](https://github.com/mapbox/martini) — original JavaScript
- [pymartini](https://github.com/kylebarron/pymartini) — Python

## License

ISC (matches upstream).
