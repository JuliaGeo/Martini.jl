# Martini.jl

A Julia port of [Mapbox's Martini](https://github.com/mapbox/martini) - a library for real-time RTIN terrain mesh generation.

## Overview

Martini generates simplified triangular meshes from terrain height data using the Right-Triangulated Irregular Networks (RTIN) algorithm. This is particularly useful for efficient 3D terrain visualization, enabling Level of Detail (LOD) rendering based on error thresholds.

## Installation

```julia
using Pkg
Pkg.add("Martini")
```

Or in development mode:

```julia
using Pkg
Pkg.develop(path="path/to/Martini.jl")
```

## Usage

### Basic Example

```julia
using Martini
using GeometryBasics

# Create a MartiniMesh with grid size 2^n + 1
# Common sizes: 257 (2^8+1), 513 (2^9+1), 1025 (2^10+1)
martini = MartiniMesh(257)

# Create terrain height data (257x257 matrix)
terrain = rand(257, 257) .* 1000  # Random heights 0-1000

# Create a tile from the terrain data
tile = create_tile(martini, terrain)

# Generate a mesh with maximum error threshold
mesh = get_mesh(tile, max_error=10.0)

# Access mesh data
vertices = coordinates(mesh)  # Vector of Point3f (x, y, z)
triangles = faces(mesh)       # Vector of TriangleFace
heights = GeometryBasics.metadata(vertices)[:height]  # Height metadata
```

### Creating Realistic Terrain

```julia
using Martini

# Create a simple mountain
martini = MartiniMesh(129)
center = 64
terrain = zeros(129, 129)

for i in 1:129, j in 1:129
    dist = sqrt((i - center)^2 + (j - center)^2)
    terrain[i, j] = max(0, 500 - dist * 5)
end

tile = create_tile(martini, terrain)

# Generate high-detail mesh (small error threshold)
high_detail = get_mesh(tile, max_error=1.0)

# Generate low-detail mesh (large error threshold)
low_detail = get_mesh(tile, max_error=20.0)

println("High detail: $(length(coordinates(high_detail))) vertices")
println("Low detail: $(length(coordinates(low_detail))) vertices")
```

### Error Threshold and Level of Detail

The `max_error` parameter controls mesh simplification:
- **max_error = 0**: No simplification, maximum detail
- **max_error > 0**: More simplification, fewer triangles
- Larger values produce coarser meshes with fewer vertices/triangles

This enables dynamic LOD rendering where distant terrain uses simplified meshes.

## API Reference

### `MartiniMesh(gridsize::Int=257)`

Creates a new MartiniMesh structure for terrain processing.

**Arguments:**
- `gridsize`: Size of the terrain grid. Must be 2^n + 1 (e.g., 3, 5, 9, 17, 33, 65, 129, 257, 513, 1025)

**Returns:** `MartiniMesh` instance

### `create_tile(martini::MartiniMesh, terrain::Matrix{<:Real})`

Creates a terrain tile from height data.

**Arguments:**
- `martini`: MartiniMesh instance
- `terrain`: n×m matrix of terrain heights (must match gridsize)

**Returns:** `MartiniTile` instance

### `get_mesh(tile::MartiniTile; max_error::Real=0)`

Generates a simplified mesh from the terrain tile.

**Arguments:**
- `tile`: MartiniTile instance
- `max_error`: Maximum allowed approximation error (default: 0)

**Returns:** `GeometryBasics.Mesh` with:
- Vertices as `Point3f` (x, y, z) where z is the height
- Triangular faces
- Vertex metadata containing height values (accessible via `GeometryBasics.metadata(vertices)[:height]`)

## Algorithm

Martini implements the RTIN (Right-Triangulated Irregular Networks) algorithm from [Garland & Heckbert (1995)](https://www.cs.cmu.edu/~./garland/scape/scape.pdf) and [Evans et al. (1997)](https://www.cs.unc.edu/~evans/GMIP97.pdf).

The algorithm:
1. Builds a hierarchical triangle structure over the terrain grid
2. Computes approximation errors for each triangle level
3. Recursively subdivides triangles based on error threshold
4. Generates an optimized mesh with fewer vertices where terrain is flat

## Differences from JavaScript Version

This Julia port maintains the same algorithm but with these adaptations:
- Uses 1-based indexing (Julia convention)
- Accepts `Matrix{<:Real}` input instead of flat arrays
- Returns `GeometryBasics.Mesh` with vertex metadata
- Leverages Julia's type system and multiple dispatch

## Performance

The algorithm is extremely fast, generating meshes in milliseconds even for large terrain grids (513×513 or 1025×1025).

## License

MIT License - see LICENSE file for details.

## Credits

This is a Julia port of [Mapbox's Martini](https://github.com/mapbox/martini) by Vladimir Agafonkin (@mourner).

Original JavaScript implementation: https://github.com/mapbox/martini
