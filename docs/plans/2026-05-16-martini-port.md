# Martini.jl Port Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task.

**Goal:** Port the [Mapbox Martini](https://github.com/mapbox/martini) JavaScript library — real-time RTIN terrain mesh generation — to Julia as `Martini.jl`, with byte-for-byte parity against the reference JS output on the fuji.png fixture.

**Architecture:** Two-struct design mirroring the JS source:
1. `Mesher` precomputes the implicit binary-tree triangle coordinates for a given grid size (constant per grid size).
2. `Tile` holds the terrain heightfield + error map for a single tile and is re-meshable at any error threshold.

Algorithm is unchanged from the JS reference (Evans et al. 1997, RTIN). The plan is **staged**:

- **Phase 1 (Tasks 1–7)** — verbatim JS port. Internal coord variables (`ax`, `ay`, …) are 0-based grid positions in `[0, tile_size]`; Julia arrays are accessed via the explicit `y * size + x + 1` offset. Parity test against the JS reference output passes byte-for-byte (modulo the +1 on triangle indices). This gives a strong correctness baseline.
- **Phase 2 (Task 8)** — refactor internals to fully 1-based. `terrain` and `errors` become `Matrix{Float32}(grid_size, grid_size)` indexed `terrain[ax, ay]`, eliminating scattered `+ 1` arithmetic. Internal coord variables shift to `[1, grid_size]`; output `Mesh.vertices` values shift +1 (corners go from `(0,0)…(tile_size, tile_size)` to `(1,1)…(grid_size, grid_size)`). Triangle indices remain 1-based throughout.

**Tech Stack:**
- Julia ≥ 1.10 (uses `const` fields in mutable structs)
- Test dependencies only: `Test`, `PNGFiles` (for the fuji.png parity test)
- No runtime dependencies — pure stdlib

**Naming caveat:** The user-selected preview showed `m = Martini(257)`, but a Julia module and struct named `Martini` collide under `using Martini` (verified in REPL — the module binding shadows the exported struct, so `Martini(257)` raises `MethodError: objects of type Module are not callable`). The plan uses **`Mesher`** for the main struct (module remains `Martini`), giving:

```julia
using Martini
m = Mesher(257)
tile = create_tile(m, terrain)
mesh = get_mesh(tile; max_error=10)
```

This follows the `DataFrames`/`DataFrame`, `Polynomials`/`Polynomial` convention. If the user prefers the literal `Martini(257)` API, the workaround is to keep the struct named `Martini` and document `using Martini: Martini` as the required import — call this out at plan review.

---

## File Layout (target)

```
Martini.jl/
├── .gitignore
├── LICENSE                       # ISC (matches upstream)
├── Project.toml
├── README.md
├── docs/plans/2026-05-16-martini-port.md   # this file
├── src/
│   └── Martini.jl                # main module
├── test/
│   ├── runtests.jl
│   ├── util.jl                   # mapbox_terrain_to_grid helper
│   └── fixtures/
│       └── fuji.png              # copied from upstream
└── bench/
    └── bench.jl                  # optional perf script
```

---

## Task 1: Scaffold the package

**Files:**
- Create: `Martini.jl/.gitignore`
- Create: `Martini.jl/LICENSE`
- Create: `Martini.jl/Project.toml`
- Create: `Martini.jl/src/Martini.jl`
- Create: `Martini.jl/test/runtests.jl`

**Step 1: Generate a UUID for Project.toml**

```bash
julia -e 'using UUIDs; println(uuid4())'
```

Capture the output; substitute for `<UUID>` below.

**Step 2: Write `Project.toml`**

```toml
name = "Martini"
uuid = "<UUID>"
authors = ["Anshul Singhvi <anshulsinghvi@gmail.com>"]
version = "0.1.0"

[compat]
julia = "1.10"

[extras]
PNGFiles = "f57f5aa1-a3ce-4bc8-8ab9-96f992907883"
Test = "8dfed614-e22c-5e08-85e1-65c5234f0b40"

[targets]
test = ["PNGFiles", "Test"]
```

**Step 3: Write `.gitignore`**

```
/Manifest.toml
/test/Manifest.toml
*.cov
/docs/build/
```

(Keep `Project.toml` checked in; ignore the lockfile per Julia convention for libraries.)

**Step 4: Write `LICENSE`** — copy the upstream ISC verbatim, updating the copyright line:

```
ISC License

Copyright (c) 2019, Mapbox
Copyright (c) 2026, Anshul Singhvi (Julia port)

Permission to use, copy, modify, and/or distribute this software for any purpose
with or without fee is hereby granted, provided that the above copyright notice
and this permission notice appear in all copies.

THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH
REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY AND
FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT,
INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS
OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER
TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF
THIS SOFTWARE.
```

**Step 5: Write `src/Martini.jl` skeleton**

```julia
module Martini

export Mesher, Tile, Mesh, create_tile, get_mesh

# Implementation lands in subsequent tasks.

end # module
```

**Step 6: Write `test/runtests.jl` skeleton**

```julia
using Test
using Martini

@testset "Martini.jl" begin
    # populated in subsequent tasks
end
```

**Step 7: Verify package loads**

Run (via the `mcp__julia__julia_eval` tool, with `env_path = "/Users/anshul/temp/geo/martini-julia/Martini.jl"`):

```julia
using Pkg
Pkg.activate(".")
Pkg.instantiate()
using Martini
println("OK")
```

Expected: prints `OK`.

**Step 8: Commit**

```bash
cd /Users/anshul/temp/geo/martini-julia/Martini.jl
git add Project.toml LICENSE .gitignore src/Martini.jl test/runtests.jl docs/
git commit -m "scaffold Martini.jl package"
```

---

## Task 2: `Mesher` struct — validation only (RED → GREEN)

**Files:**
- Modify: `src/Martini.jl`
- Modify: `test/runtests.jl`

**Step 1: Write the failing test** (in `test/runtests.jl`, replace the empty `@testset` body)

```julia
@testset "Mesher construction" begin
    @test_throws ArgumentError Mesher(256)  # not 2^k + 1
    @test_throws ArgumentError Mesher(2)    # tile_size = 1 is technically 2^0 but the JS code accepts it; we reject sizes < 3
    @test_throws ArgumentError Mesher(0)
    @test_throws ArgumentError Mesher(-1)

    m = Mesher(257)
    @test m.grid_size == 257
end
```

**Step 2: Run tests to confirm RED**

Via `mcp__julia__julia_eval` with `env_path = "/Users/anshul/temp/geo/martini-julia/Martini.jl"`:

```julia
using Pkg; Pkg.activate("."); Pkg.test()
```

Expected: failure citing `Mesher` not defined.

**Step 3: Implement `Mesher` with validation only**

In `src/Martini.jl`, between `export ...` and `end # module`:

```julia
struct Mesher
    grid_size::Int
    num_triangles::Int
    num_parent_triangles::Int
    coords::Vector{UInt16}   # flat: [a1x, a1y, b1x, b1y, a2x, a2y, b2x, b2y, ...]

    function Mesher(grid_size::Integer = 257)
        grid_size >= 3 || throw(ArgumentError(
            "Expected grid size to be 2^n+1 with n>=1, got $grid_size."))
        tile_size = grid_size - 1
        (tile_size & (tile_size - 1)) == 0 || throw(ArgumentError(
            "Expected grid size to be 2^n+1, got $grid_size."))

        num_triangles = tile_size * tile_size * 2 - 2
        num_parent_triangles = num_triangles - tile_size * tile_size
        coords = Vector{UInt16}(undef, num_triangles * 4)

        # coords filled in next task; leave undef for now
        return new(grid_size, num_triangles, num_parent_triangles, coords)
    end
end
```

**Step 4: Run tests to confirm GREEN**

```julia
Pkg.test()
```

Expected: all 5 assertions pass.

**Step 5: Commit**

```bash
git add src/Martini.jl test/runtests.jl
git commit -m "add Mesher struct with grid-size validation"
```

---

## Task 3: Mesher coordinate precomputation

**Files:**
- Modify: `src/Martini.jl` (replace the body of the inner constructor)
- Modify: `test/runtests.jl`

**Step 1: Write the failing test**

Append inside `@testset "Martini.jl" ...`:

```julia
@testset "Mesher coords (5x5 grid)" begin
    # tile_size = 4 → num_triangles = 4*4*2 - 2 = 30
    # Reference values produced by running the JS code at gridSize=5
    # (computed offline from index.js lines 12-44, recorded here so this test is self-contained).
    m = Mesher(5)
    @test m.num_triangles == 30
    @test m.num_parent_triangles == 30 - 16   # 14

    # Spot-check the first and last triangles. Indices 0..29 in JS == 1..30 in Julia.
    # Triangle 0 (i=0, id=2): top-right corner triangle of the whole tile.
    #   ax,ay,bx,by = 4,4,0,0   (when id=2 even -> ax=ay=cy=tileSize=4, then id>>=1=1 so loop skipped)
    @test m.coords[1:4] == UInt16[4, 4, 0, 0]

    # Triangle 1 (i=1, id=3): bottom-left of the whole tile.
    #   ax,ay,bx,by = 0,0,4,4
    @test m.coords[5:8] == UInt16[0, 0, 4, 4]
end
```

> **Note for implementer:** if the spot-check values above are wrong, do NOT change them blindly. Re-derive them by reading the JS algorithm in `martini/index.js:18-44`. The exact expected values for a 5×5 grid can also be regenerated by running the JS reference (Node) on `gridSize=5` and printing `martini.coords`.

**Step 2: Run tests to confirm RED**

```julia
Pkg.test()
```

Expected: test fails because `coords[1:4]` is currently undefined garbage.

**Step 3: Implement coords precomputation**

In `src/Martini.jl`, replace the inner constructor body so it computes `coords`. Final form:

```julia
function Mesher(grid_size::Integer = 257)
    grid_size >= 3 || throw(ArgumentError(
        "Expected grid size to be 2^n+1 with n>=1, got $grid_size."))
    tile_size = grid_size - 1
    (tile_size & (tile_size - 1)) == 0 || throw(ArgumentError(
        "Expected grid size to be 2^n+1, got $grid_size."))

    num_triangles = tile_size * tile_size * 2 - 2
    num_parent_triangles = num_triangles - tile_size * tile_size
    coords = Vector{UInt16}(undef, num_triangles * 4)

    @inbounds for i in 0:(num_triangles - 1)
        id = i + 2
        ax = ay = bx = by = cx = cy = 0
        if id & 1 != 0
            bx = by = cx = tile_size          # bottom-left triangle
        else
            ax = ay = cy = tile_size          # top-right triangle
        end
        id >>= 1
        while id > 1
            mx = (ax + bx) >> 1
            my = (ay + by) >> 1
            if id & 1 != 0                    # left half
                bx, by = ax, ay
                ax, ay = cx, cy
            else                              # right half
                ax, ay = bx, by
                bx, by = cx, cy
            end
            cx, cy = mx, my
            id >>= 1
        end
        k = i * 4 + 1                         # 1-based offset of triangle i
        coords[k    ] = ax
        coords[k + 1] = ay
        coords[k + 2] = bx
        coords[k + 3] = by
    end

    return new(grid_size, num_triangles, num_parent_triangles, coords)
end
```

**Step 4: Run tests to confirm GREEN**

```julia
Pkg.test()
```

Expected: pass.

**Step 5: Commit**

```bash
git add src/Martini.jl test/runtests.jl
git commit -m "precompute Mesher triangle coordinates"
```

---

## Task 4: `Tile` + error-map computation

**Files:**
- Modify: `src/Martini.jl`
- Modify: `test/runtests.jl`

**Step 1: Write the failing test**

```julia
@testset "Tile / errors" begin
    m = Mesher(5)
    # Length mismatch should be rejected.
    @test_throws ArgumentError create_tile(m, zeros(Float32, 10))

    # Flat terrain → all errors are 0.
    flat = zeros(Float32, 25)
    tile = create_tile(m, flat)
    @test tile.errors == zeros(Float32, 25)

    # Pointy terrain: center vertex is elevated. The error at the center
    # should equal the height delta (since linear interp of the surrounding
    # vertices is 0, observed is height).
    terrain = zeros(Float32, 25)
    terrain[3 * 5 + 3]  = 100f0   # center of a 5x5 grid (0-based (2,2)), 1-based [13]
    # (with 1-based: y=2, x=2 → index = 2*5 + 2 + 1 = 13)
    tile2 = create_tile(m, terrain)
    @test tile2.errors[13] == 100f0
end
```

**Step 2: Run tests to confirm RED**

```julia
Pkg.test()
```

Expected: failure on `create_tile` undefined.

**Step 3: Implement `Tile` + `create_tile` + the internal `_update_errors!`**

Append to `src/Martini.jl` (before `end # module`):

```julia
struct Tile
    mesher::Mesher
    terrain::Vector{Float32}
    errors::Vector{Float32}
end

"""
    create_tile(mesher::Mesher, terrain::AbstractVector{<:Real}) -> Tile

Build a `Tile` for the given terrain heightfield (length must equal
`mesher.grid_size^2`, row-major, y-major: `terrain[y*size + x + 1]`).
Computes the per-vertex max-error map eagerly.
"""
function create_tile(mesher::Mesher, terrain::AbstractVector{<:Real})
    size = mesher.grid_size
    length(terrain) == size * size || throw(ArgumentError(
        "Expected terrain of length $(size * size) ($size x $size), got $(length(terrain))."))
    terrain_f32 = terrain isa Vector{Float32} ? copy(terrain) : Vector{Float32}(terrain)
    errors = zeros(Float32, length(terrain_f32))
    tile = Tile(mesher, terrain_f32, errors)
    _update_errors!(tile)
    return tile
end

function _update_errors!(tile::Tile)
    m = tile.mesher
    coords = m.coords
    size = m.grid_size
    terrain = tile.terrain
    errors = tile.errors
    npt = m.num_parent_triangles
    nt = m.num_triangles

    @inbounds for i in (nt - 1):-1:0
        k = i * 4 + 1
        ax = Int(coords[k    ])
        ay = Int(coords[k + 1])
        bx = Int(coords[k + 2])
        by = Int(coords[k + 3])
        mx = (ax + bx) >> 1
        my = (ay + by) >> 1
        cx = mx + my - ay
        cy = my + ax - mx

        interp = (terrain[ay * size + ax + 1] + terrain[by * size + bx + 1]) / 2
        middle_idx = my * size + mx + 1
        middle_err = abs(interp - terrain[middle_idx])
        errors[middle_idx] = max(errors[middle_idx], middle_err)

        if i < npt
            left_child  = ((ay + cy) >> 1) * size + ((ax + cx) >> 1) + 1
            right_child = ((by + cy) >> 1) * size + ((bx + cx) >> 1) + 1
            errors[middle_idx] = max(errors[middle_idx], errors[left_child], errors[right_child])
        end
    end
    return tile
end
```

**Step 4: Run tests to confirm GREEN**

```julia
Pkg.test()
```

Expected: pass.

**Step 5: Commit**

```bash
git add src/Martini.jl test/runtests.jl
git commit -m "add Tile and error-map computation"
```

---

## Task 5: `get_mesh` — count + fill (TDD)

**Files:**
- Modify: `src/Martini.jl`
- Modify: `test/runtests.jl`

**Step 1: Write the failing test**

```julia
@testset "get_mesh on flat terrain" begin
    m = Mesher(5)
    tile = create_tile(m, zeros(Float32, 25))
    mesh = get_mesh(tile; max_error = 0)
    # Flat → no subdivision: 4 corner vertices, 2 triangles covering the tile.
    @test size(mesh.vertices) == (2, 4)
    @test size(mesh.triangles) == (2, 2) || size(mesh.triangles) == (3, 2)
    @test size(mesh.triangles) == (3, 2)
    # Vertex coords are 0..tile_size (=4); each column is (x,y).
    coord_set = Set(eachcol(mesh.vertices))
    @test coord_set == Set([UInt16[0, 0], UInt16[4, 0], UInt16[0, 4], UInt16[4, 4]])
    # Triangle indices are 1-based and refer to existing columns.
    @test all(1 .<= mesh.triangles .<= 4)
end

@testset "get_mesh subdivides when error exceeds threshold" begin
    m = Mesher(5)
    terrain = zeros(Float32, 25)
    terrain[13] = 100f0           # spike at center (1-based index 13)
    tile = create_tile(m, terrain)
    mesh_loose = get_mesh(tile; max_error = 1000)   # threshold above spike
    mesh_tight = get_mesh(tile; max_error = 0)      # threshold below spike
    @test size(mesh_tight.vertices, 2) > size(mesh_loose.vertices, 2)
end
```

**Step 2: Run tests to confirm RED**

```julia
Pkg.test()
```

Expected: `get_mesh` undefined.

**Step 3: Implement `Mesh` + `get_mesh`**

Append to `src/Martini.jl`:

```julia
"""
    Mesh

Result of `get_mesh`. `vertices` is a `2 × N` matrix where each column is a
`(x, y)` grid coordinate (0-based, in the `[0, grid_size-1]` range). `triangles`
is a `3 × M` matrix where each column is a triple of **1-based** column indices
into `vertices`.
"""
struct Mesh
    vertices::Matrix{UInt16}
    triangles::Matrix{UInt32}
end

# Internal scratch state. `const` fields require Julia >= 1.8.
mutable struct _Builder
    const size::Int
    const max_error::Float32
    const errors::Vector{Float32}
    const indices::Vector{UInt32}
    num_vertices::Int
    num_triangles::Int
end

function _count!(b::_Builder, ax::Int, ay::Int, bx::Int, by::Int, cx::Int, cy::Int)
    mx = (ax + bx) >> 1
    my = (ay + by) >> 1
    @inbounds if abs(ax - cx) + abs(ay - cy) > 1 &&
                 b.errors[my * b.size + mx + 1] > b.max_error
        _count!(b, cx, cy, ax, ay, mx, my)
        _count!(b, bx, by, cx, cy, mx, my)
    else
        @inbounds for (x, y) in ((ax, ay), (bx, by), (cx, cy))
            idx = y * b.size + x + 1
            if b.indices[idx] == 0
                b.num_vertices += 1
                b.indices[idx] = b.num_vertices
            end
        end
        b.num_triangles += 1
    end
end

mutable struct _Filler
    const size::Int
    const max_error::Float32
    const errors::Vector{Float32}
    const indices::Vector{UInt32}
    const vertices::Vector{UInt16}   # flat: 2*N
    const triangles::Vector{UInt32}  # flat: 3*M
    tri_offset::Int                  # 0-based offset into triangles
end

function _process!(f::_Filler, ax::Int, ay::Int, bx::Int, by::Int, cx::Int, cy::Int)
    mx = (ax + bx) >> 1
    my = (ay + by) >> 1
    @inbounds if abs(ax - cx) + abs(ay - cy) > 1 &&
                 f.errors[my * f.size + mx + 1] > f.max_error
        _process!(f, cx, cy, ax, ay, mx, my)
        _process!(f, bx, by, cx, cy, mx, my)
    else
        @inbounds begin
            a  = f.indices[ay * f.size + ax + 1]
            b  = f.indices[by * f.size + bx + 1]
            c  = f.indices[cy * f.size + cx + 1]

            f.vertices[2 * (a - 1) + 1] = ax
            f.vertices[2 * (a - 1) + 2] = ay
            f.vertices[2 * (b - 1) + 1] = bx
            f.vertices[2 * (b - 1) + 2] = by
            f.vertices[2 * (c - 1) + 1] = cx
            f.vertices[2 * (c - 1) + 2] = cy

            f.triangles[f.tri_offset + 1] = a
            f.triangles[f.tri_offset + 2] = b
            f.triangles[f.tri_offset + 3] = c
            f.tri_offset += 3
        end
    end
end

"""
    get_mesh(tile::Tile; max_error::Real = 0) -> Mesh

Walk the implicit RTIN binary tree top-down, emitting a triangle whenever the
error at the long-edge midpoint is below `max_error`. Returns a `Mesh` with
1-based triangle vertex indices.
"""
function get_mesh(tile::Tile; max_error::Real = 0)
    m = tile.mesher
    size = m.grid_size
    max_idx = size - 1
    err = Float32(max_error)
    indices = zeros(UInt32, size * size)

    builder = _Builder(size, err, tile.errors, indices, 0, 0)
    _count!(builder, 0,       0,       max_idx, max_idx, max_idx, 0      )
    _count!(builder, max_idx, max_idx, 0,       0,       0,       max_idx)

    verts_flat = Vector{UInt16}(undef, 2 * builder.num_vertices)
    tris_flat  = Vector{UInt32}(undef, 3 * builder.num_triangles)

    filler = _Filler(size, err, tile.errors, indices, verts_flat, tris_flat, 0)
    _process!(filler, 0,       0,       max_idx, max_idx, max_idx, 0      )
    _process!(filler, max_idx, max_idx, 0,       0,       0,       max_idx)

    return Mesh(
        reshape(verts_flat, 2, builder.num_vertices),
        reshape(tris_flat,  3, builder.num_triangles),
    )
end
```

**Step 4: Run tests to confirm GREEN**

```julia
Pkg.test()
```

Expected: pass.

**Step 5: Commit**

```bash
git add src/Martini.jl test/runtests.jl
git commit -m "implement get_mesh (count + fill)"
```

---

## Task 6: Copy the fuji.png fixture + `mapbox_terrain_to_grid` helper

**Files:**
- Create: `test/fixtures/fuji.png` (copy)
- Create: `test/util.jl`
- Modify: `test/runtests.jl`

**Step 1: Copy the fixture**

```bash
mkdir -p /Users/anshul/temp/geo/martini-julia/Martini.jl/test/fixtures
cp /Users/anshul/temp/geo/martini-julia/martini/test/fixtures/fuji.png \
   /Users/anshul/temp/geo/martini-julia/Martini.jl/test/fixtures/fuji.png
```

**Step 2: Write `test/util.jl`**

Direct port of `martini/test/util.js`. PNGFiles returns a `Matrix{RGB{N0f8}}` (or `RGBA`); we want raw 0–255 byte values per channel. Using `reinterpret(UInt8, ...)` after dropping alpha would be efficient, but the safe-and-clear route is per-pixel `red()`/`green()`/`blue()` with explicit scaling.

```julia
using PNGFiles
using FixedPointNumbers: N0f8

"""
    mapbox_terrain_to_grid(png_path::AbstractString) -> Vector{Float32}

Decode a Mapbox RGB terrain PNG into a length `(width+1)^2` heightfield, matching
the reference JS implementation in `martini/test/util.js`.
"""
function mapbox_terrain_to_grid(png_path::AbstractString)
    img = PNGFiles.load(png_path)            # Matrix of RGB or RGBA
    height, width = size(img)
    width == height || error("expected square tile, got $(width)x$(height)")

    tile_size = width
    grid_size = tile_size + 1
    terrain = Vector{Float32}(undef, grid_size * grid_size)

    @inbounds for y in 0:(tile_size - 1)
        for x in 0:(tile_size - 1)
            # PNGFiles is row-major image[row, col] == image[y+1, x+1]
            px = img[y + 1, x + 1]
            r = reinterpret(UInt8, N0f8(red(px)))   # 0..255
            g = reinterpret(UInt8, N0f8(green(px)))
            b = reinterpret(UInt8, N0f8(blue(px)))
            terrain[y * grid_size + x + 1] =
                (Int(r) * 65536 + Int(g) * 256 + Int(b)) / 10f0 - 10000f0
        end
    end

    # Backfill right + bottom borders (mirror JS lines 19-24)
    for x in 0:(grid_size - 2)
        terrain[(grid_size - 1) * grid_size + x + 1] =
            terrain[(grid_size - 2) * grid_size + x + 1]
    end
    for y in 0:(grid_size - 1)
        terrain[y * grid_size + (grid_size - 1) + 1] =
            terrain[y * grid_size + (grid_size - 2) + 1]
    end
    return terrain
end
```

> **Note for implementer:** `PNGFiles.load` may return either `RGB` or `RGBA` color types depending on the source file. Both expose `red`/`green`/`blue`. If the import of `red, green, blue` fails, add `using ColorTypes: red, green, blue` (ColorTypes ships with PNGFiles transitively).

**Step 3: Add a smoke test for the decoder**

In `test/runtests.jl`, add an include + test before the parity test (next task):

```julia
include("util.jl")

@testset "mapbox_terrain_to_grid (fuji)" begin
    terrain = mapbox_terrain_to_grid(joinpath(@__DIR__, "fixtures", "fuji.png"))
    # fuji.png is 512×512 → grid 513×513
    @test length(terrain) == 513 * 513
    # Heights should be in a sane terrestrial range (m above sea level).
    @test minimum(terrain) > -500f0
    @test maximum(terrain) < 5000f0    # Mt. Fuji peak ~3776m
end
```

**Step 4: Run tests to confirm GREEN**

```julia
Pkg.test()
```

Expected: pass.

**Step 5: Commit**

```bash
git add test/util.jl test/fixtures/fuji.png test/runtests.jl
git commit -m "port mapbox terrain PNG decoder for tests"
```

---

## Task 7: Cross-port parity test against the JS reference

**Files:**
- Modify: `test/runtests.jl`

**Step 1: Add the parity test**

The JS test (`martini/test/test.js`) asserts specific vertex and 0-based triangle arrays for `getMesh(500)` on `fuji.png` with `gridSize = fuji.width + 1 = 513`. We assert the same vertices (identical numbers, since they're grid coordinates) and the same triangles **with +1 added** to every index (1-based).

Append in `test/runtests.jl`:

```julia
@testset "Fuji parity with martini.js getMesh(500)" begin
    terrain = mapbox_terrain_to_grid(joinpath(@__DIR__, "fixtures", "fuji.png"))
    m = Mesher(513)
    tile = create_tile(m, terrain)
    mesh = get_mesh(tile; max_error = 500)

    expected_vertices = UInt16[
        320, 64, 256, 128, 320, 128, 384, 128, 256, 0, 288, 160, 256, 192, 288, 192,
        320, 192, 304, 176, 256, 256, 288, 224, 352, 160, 320, 160, 512, 0, 384, 0,
        128, 128, 128, 0, 64, 64, 64, 0, 0, 0, 32, 32, 192, 192, 384, 384, 512, 256,
        384, 256, 320, 320, 320, 256, 512, 512, 512, 128, 448, 192, 384, 192, 128,
        384, 256, 512, 256, 384, 0, 512, 128, 256, 64, 192, 0, 256, 64, 128, 32, 96,
        0, 128, 32, 64, 16, 48, 0, 64, 0, 32,
    ]
    expected_triangles_0based = UInt32[
        0, 1, 2, 3, 0, 2, 4, 1, 0, 5, 6, 7, 7, 8, 9, 5, 7, 9, 1, 6, 5, 6, 10, 11, 11,
        8, 7, 6, 11, 7, 12, 2, 13, 8, 12, 13, 3, 2, 12, 2, 1, 5, 13, 5, 9, 8, 13, 9, 2,
        5, 13, 3, 14, 15, 15, 4, 0, 3, 15, 0, 16, 4, 17, 18, 17, 19, 19, 20, 21, 18,
        19, 21, 16, 17, 18, 1, 16, 22, 22, 10, 6, 1, 22, 6, 4, 16, 1, 23, 24, 25, 26,
        25, 27, 10, 26, 27, 23, 25, 26, 28, 24, 23, 29, 3, 30, 24, 29, 30, 14, 3, 29,
        8, 25, 31, 31, 3, 12, 8, 31, 12, 27, 8, 11, 10, 27, 11, 25, 8, 27, 25, 24, 30,
        30, 3, 31, 25, 30, 31, 32, 33, 34, 10, 32, 34, 35, 33, 32, 33, 28, 23, 34, 23,
        26, 10, 34, 26, 33, 23, 34, 36, 16, 37, 38, 36, 37, 36, 10, 22, 16, 36, 22,
        39, 18, 40, 41, 39, 40, 16, 18, 39, 42, 21, 43, 44, 42, 43, 18, 21, 42, 21,
        20, 45, 45, 44, 43, 21, 45, 43, 44, 41, 40, 40, 18, 42, 44, 40, 42, 41, 38,
        37, 37, 16, 39, 41, 37, 39, 38, 35, 32, 32, 10, 36, 38, 32, 36,
    ]
    expected_triangles = expected_triangles_0based .+ UInt32(1)

    @test vec(mesh.vertices)  == expected_vertices
    @test vec(mesh.triangles) == expected_triangles
end
```

**Step 2: Run tests**

```julia
Pkg.test()
```

Expected: pass. If it fails, the most likely culprits (in order):
1. Off-by-one in the `y * size + x + 1` indexing — re-derive from JS.
2. `_count!` and `_process!` traversal order mismatch — the JS uses two top-level calls in a specific order: `(0,0)→(max,max)→(max,0)` then `(max,max)→(0,0)→(0,max)`. Confirm both Julia calls match.
3. `_update_errors!` iteration order (must be `nt-1` down to `0`, not the other way) — children must already have their errors when the parent is processed.
4. Vertex ID assignment order in `_count!` — JS assigns to `ay*size+ax`, `by*size+bx`, `cy*size+cx` **in that order**. The Julia loop `for (x,y) in ((ax,ay), (bx,by), (cx,cy))` matches; do NOT reorder.

**Step 3: Commit**

```bash
git add test/runtests.jl
git commit -m "add JS parity test on fuji.png getMesh(500)"
```

---

## Task 8: Refactor internal coords to 1-based (Julia-idiomatic)

**Goal:** Eliminate the scattered `y * size + x + 1` arithmetic by shifting internal coord variables to 1-based throughout. `terrain`/`errors`/`indices` become `Matrix{...}(grid_size, grid_size)` so access is `terrain[ax, ay]`. Output `mesh.vertices` values shift +1 (corners go from `(0,0)…(tile_size, tile_size)` to `(1,1)…(grid_size, grid_size)`); triangle indices remain 1-based.

> **Why this is safe to do as a refactor:** the bit-tricks `(ax + bx) >> 1`, `cx = mx + my - ay`, etc. are translation-invariant in integer math when the inputs shift by the same amount. The Phase 1 parity test guards behavior; we re-run after each step.

**Files:**
- Modify: `src/Martini.jl`
- Modify: `test/runtests.jl`

**Step 1: Update the Mesher coord spot-check**

For a 5×5 grid in 1-based coords: corners at 1 and 5 (not 0 and 4).

In `test/runtests.jl`, replace the two spot-check lines:

```julia
# Triangle 0 (i=0, id=2): top-right corner of the whole tile
@test m.coords[1:4] == UInt16[5, 5, 1, 1]
# Triangle 1 (i=1, id=3): bottom-left of the whole tile
@test m.coords[5:8] == UInt16[1, 1, 5, 5]
```

**Step 2: Shift Mesher coord precomputation**

In `src/Martini.jl`, two lines inside the inner constructor change:

```julia
@inbounds for i in 0:(num_triangles - 1)
    id = i + 2
    ax = ay = bx = by = cx = cy = 1        # was: = 0
    if id & 1 != 0
        bx = by = cx = grid_size           # was: = tile_size
    else
        ax = ay = cy = grid_size           # was: = tile_size
    end
    # ... rest of the loop body is byte-for-byte identical ...
end
```

The midpoint and rotation math is unchanged — only the initial corner values shift.

**Step 3: Switch `Tile` to `Matrix`-backed terrain/errors**

Replace the struct definition and `create_tile`:

```julia
struct Tile
    mesher::Mesher
    terrain::Matrix{Float32}    # size (grid_size, grid_size); terrain[x, y]
    errors::Matrix{Float32}
end

function create_tile(mesher::Mesher, terrain)
    sz = mesher.grid_size
    length(terrain) == sz * sz || throw(ArgumentError(
        "Expected terrain of length $(sz * sz) ($sz x $sz), got $(length(terrain))."))
    # `reshape(collect(Float32, terrain), sz, sz)` works for both Vector and Matrix inputs.
    # The flat-vector convention is y-major (matches JS); column-major reshape then gives
    # us a Matrix where mat[x, y] == flat[(y-1)*sz + x].
    terrain_mat = reshape(collect(Float32, terrain), sz, sz)
    errors_mat = zeros(Float32, sz, sz)
    tile = Tile(mesher, terrain_mat, errors_mat)
    _update_errors!(tile)
    return tile
end
```

**Step 4: Rewrite `_update_errors!` with 2D indexing**

```julia
function _update_errors!(tile::Tile)
    m = tile.mesher
    coords = m.coords
    terrain = tile.terrain
    errors = tile.errors
    npt = m.num_parent_triangles
    nt = m.num_triangles

    @inbounds for i in (nt - 1):-1:0
        k = i * 4 + 1
        ax = Int(coords[k    ])
        ay = Int(coords[k + 1])
        bx = Int(coords[k + 2])
        by = Int(coords[k + 3])
        mx = (ax + bx) >> 1
        my = (ay + by) >> 1
        cx = mx + my - ay
        cy = my + ax - mx

        interp = (terrain[ax, ay] + terrain[bx, by]) / 2
        middle_err = abs(interp - terrain[mx, my])
        errors[mx, my] = max(errors[mx, my], middle_err)

        if i < npt
            errors[mx, my] = max(
                errors[mx, my],
                errors[(ax + cx) >> 1, (ay + cy) >> 1],
                errors[(bx + cx) >> 1, (by + cy) >> 1],
            )
        end
    end
    return tile
end
```

No more `+ 1` arithmetic in the hot path.

**Step 5: Update `_Builder`, `_Filler`, `_count!`, `_process!`**

Change the scratch types and the index access. The shape of the code is unchanged.

```julia
mutable struct _Builder
    const size::Int
    const max_error::Float32
    const errors::Matrix{Float32}
    const indices::Matrix{UInt32}
    num_vertices::Int
    num_triangles::Int
end

function _count!(b::_Builder, ax::Int, ay::Int, bx::Int, by::Int, cx::Int, cy::Int)
    mx = (ax + bx) >> 1
    my = (ay + by) >> 1
    @inbounds if abs(ax - cx) + abs(ay - cy) > 1 && b.errors[mx, my] > b.max_error
        _count!(b, cx, cy, ax, ay, mx, my)
        _count!(b, bx, by, cx, cy, mx, my)
    else
        @inbounds for (x, y) in ((ax, ay), (bx, by), (cx, cy))
            if b.indices[x, y] == 0
                b.num_vertices += 1
                b.indices[x, y] = b.num_vertices
            end
        end
        b.num_triangles += 1
    end
end

mutable struct _Filler
    const size::Int
    const max_error::Float32
    const errors::Matrix{Float32}
    const indices::Matrix{UInt32}
    const vertices::Vector{UInt16}
    const triangles::Vector{UInt32}
    tri_offset::Int
end

function _process!(f::_Filler, ax::Int, ay::Int, bx::Int, by::Int, cx::Int, cy::Int)
    mx = (ax + bx) >> 1
    my = (ay + by) >> 1
    @inbounds if abs(ax - cx) + abs(ay - cy) > 1 && f.errors[mx, my] > f.max_error
        _process!(f, cx, cy, ax, ay, mx, my)
        _process!(f, bx, by, cx, cy, mx, my)
    else
        @inbounds begin
            a = f.indices[ax, ay]
            b = f.indices[bx, by]
            c = f.indices[cx, cy]
            f.vertices[2 * (a - 1) + 1] = ax
            f.vertices[2 * (a - 1) + 2] = ay
            f.vertices[2 * (b - 1) + 1] = bx
            f.vertices[2 * (b - 1) + 2] = by
            f.vertices[2 * (c - 1) + 1] = cx
            f.vertices[2 * (c - 1) + 2] = cy
            f.triangles[f.tri_offset + 1] = a
            f.triangles[f.tri_offset + 2] = b
            f.triangles[f.tri_offset + 3] = c
            f.tri_offset += 3
        end
    end
end
```

**Step 6: Update `get_mesh` corner calls**

```julia
function get_mesh(tile::Tile; max_error::Real = 0)
    m = tile.mesher
    sz = m.grid_size
    err = Float32(max_error)
    indices = zeros(UInt32, sz, sz)   # was: zeros(UInt32, sz * sz)

    builder = _Builder(sz, err, tile.errors, indices, 0, 0)
    _count!(builder, 1,  1,  sz, sz, sz, 1 )   # was: 0, 0, max, max, max, 0
    _count!(builder, sz, sz, 1,  1,  1,  sz)   # was: max, max, 0, 0, 0, max

    verts_flat = Vector{UInt16}(undef, 2 * builder.num_vertices)
    tris_flat  = Vector{UInt32}(undef, 3 * builder.num_triangles)

    filler = _Filler(sz, err, tile.errors, indices, verts_flat, tris_flat, 0)
    _process!(filler, 1,  1,  sz, sz, sz, 1 )
    _process!(filler, sz, sz, 1,  1,  1,  sz)

    return Mesh(
        reshape(verts_flat, 2, builder.num_vertices),
        reshape(tris_flat,  3, builder.num_triangles),
    )
end
```

**Step 7: Update synthetic tests**

In the flat-terrain test, corner coords shift:

```julia
@testset "get_mesh on flat terrain" begin
    m = Mesher(5)
    tile = create_tile(m, zeros(Float32, 25))
    mesh = get_mesh(tile; max_error = 0)
    @test size(mesh.vertices) == (2, 4)
    @test size(mesh.triangles) == (3, 2)
    coord_set = Set(eachcol(mesh.vertices))
    @test coord_set == Set([UInt16[1, 1], UInt16[5, 1], UInt16[1, 5], UInt16[5, 5]])  # was 0/4
    @test all(1 .<= mesh.triangles .<= 4)
end
```

In the pointy-terrain error test, switch to 2D indexing for the error assertion:

```julia
@testset "Tile / errors" begin
    m = Mesher(5)
    @test_throws ArgumentError create_tile(m, zeros(Float32, 10))

    flat = zeros(Float32, 25)
    tile = create_tile(m, flat)
    @test all(tile.errors .== 0)
    @test size(tile.errors) == (5, 5)    # confirms the Matrix shape

    terrain = zeros(Float32, 25)
    terrain[13] = 100f0                  # 13th flat element = (x=3, y=3) after reshape
    tile2 = create_tile(m, terrain)
    @test tile2.errors[3, 3] == 100f0    # was: tile2.errors[13] == 100f0
end
```

**Step 8: Shift parity-test expected vertices by +1**

```julia
expected_vertices_0based = UInt16[
    320, 64, 256, 128, 320, 128, 384, 128, 256, 0, 288, 160, 256, 192, 288, 192,
    320, 192, 304, 176, 256, 256, 288, 224, 352, 160, 320, 160, 512, 0, 384, 0,
    128, 128, 128, 0, 64, 64, 64, 0, 0, 0, 32, 32, 192, 192, 384, 384, 512, 256,
    384, 256, 320, 320, 320, 256, 512, 512, 512, 128, 448, 192, 384, 192, 128,
    384, 256, 512, 256, 384, 0, 512, 128, 256, 64, 192, 0, 256, 64, 128, 32, 96,
    0, 128, 32, 64, 16, 48, 0, 64, 0, 32,
]
expected_vertices = expected_vertices_0based .+ UInt16(1)
@test vec(mesh.vertices) == expected_vertices
```

`expected_triangles_0based .+ UInt32(1)` is already in the Phase 1 test — leave it alone.

**Step 9: Update the `Mesh` docstring**

```julia
"""
    Mesh

Result of `get_mesh`. `vertices` is a `2 × N` matrix where each column is a
**1-based** `(x, y)` grid coordinate in `[1, grid_size]`. `triangles` is a
`3 × M` matrix where each column is a triple of 1-based column indices into
`vertices`. For WebGL/OpenGL output, subtract 1 from both `vertices`
(to land in `[0, grid_size-1]`) and `triangles` (to get 0-based indices).
"""
struct Mesh
    vertices::Matrix{UInt16}
    triangles::Matrix{UInt32}
end
```

**Step 10: Run the full test suite**

```julia
Pkg.test()
```

Expected: every test passes — Mesher validation, the updated coord spot-check, flat-terrain mesh with 1-based corners, error spike at `[3, 3]`, mapbox PNG decoder smoke test, and the parity test with the +1 expected vertices.

**Step 11: Commit**

```bash
git add src/Martini.jl test/runtests.jl
git commit -m "refactor: internal coords now 1-based (Matrix-backed terrain/errors)"
```

---

## Task 9: README + docstrings

**Files:**
- Create: `README.md`

**Step 1: Write `README.md`**

```markdown
# Martini.jl

A Julia port of [Mapbox Martini](https://github.com/mapbox/martini): real-time
RTIN terrain mesh generation from height data. Given a `(2^k + 1) × (2^k + 1)`
heightfield, it generates a hierarchy of triangle meshes at arbitrary level of
detail in milliseconds.

Based on ["Right-Triangulated Irregular Networks" by Will Evans et al. (1997)](https://www.cs.ubc.ca/~will/papers/rtin.pdf).

## Install

```julia
import Pkg; Pkg.add(url = "https://github.com/asinghvi17/Martini.jl")
```

## Example

```julia
using Martini

# 257×257 grid (2^8 + 1)
m = Mesher(257)

# `terrain` is a length-65 025 (=257²) Vector{Float32} of heights, y-major
# (matches the Mapbox/JS convention). A 257×257 Matrix{Float32} is also accepted —
# they share memory once reshape'd internally.
tile = create_tile(m, terrain)

# 10-metre approximation error
mesh = get_mesh(tile; max_error = 10)

# mesh.vertices  :: Matrix{UInt16}  size (2, N) — columns are 1-based (x, y) grid coords in [1, 257]
# mesh.triangles :: Matrix{UInt32}  size (3, M) — columns are 1-based vertex indices
```

For WebGL/OpenGL, subtract 1 from both `mesh.vertices` (to land in `[0, grid_size-1]`) and `mesh.triangles` (to get 0-based indices).

## Reference ports

- [pymartini](https://github.com/kylebarron/pymartini) — Python
- [Mapbox Martini](https://github.com/mapbox/martini) — original JavaScript

## License

ISC (matches upstream).
```

**Step 2: Add docstrings already added in earlier tasks** — verify they render:

```julia
using Martini
?Mesher
?create_tile
?get_mesh
```

(Visual check only — no automated test.)

**Step 3: Commit**

```bash
git add README.md
git commit -m "add README"
```

---

## Task 10 (optional): Benchmark script

**Files:**
- Create: `bench/bench.jl`

**Step 1: Write a parity benchmark**

Port of `martini/bench.js`:

```julia
using BenchmarkTools, Martini
include(joinpath(@__DIR__, "..", "test", "util.jl"))

terrain = mapbox_terrain_to_grid(joinpath(@__DIR__, "..", "test", "fixtures", "fuji.png"))

@info "init Mesher(513)"
@btime Mesher(513)

@info "create_tile"
m = Mesher(513)
@btime create_tile($m, $terrain)

@info "get_mesh(max_error=30)"
tile = create_tile(m, terrain)
@btime get_mesh($tile; max_error = 30)

mesh = get_mesh(tile; max_error = 30)
@info "mesh stats" vertices=size(mesh.vertices, 2) triangles=size(mesh.triangles, 2)

@info "sweep max_error 0..20"
for e in 0:20
    @info "  max_error=$e" t=@elapsed(get_mesh(tile; max_error = e))
end
```

Add `BenchmarkTools` to `[extras]` and the `bench` target in `Project.toml` — or keep it ad-hoc and document `Pkg.add("BenchmarkTools")` in the bench README.

**Step 2: Commit**

```bash
git add bench/bench.jl Project.toml
git commit -m "add benchmark script"
```

---

## Task 11 (optional): CI

**Files:**
- Create: `.github/workflows/CI.yml`

**Step 1: Add a minimal GitHub Actions matrix**

```yaml
name: CI
on:
  push:
    branches: [main]
  pull_request:
jobs:
  test:
    runs-on: ${{ matrix.os }}
    strategy:
      fail-fast: false
      matrix:
        version: ['1.10', '1']
        os: [ubuntu-latest]
    steps:
      - uses: actions/checkout@v4
      - uses: julia-actions/setup-julia@v2
        with:
          version: ${{ matrix.version }}
      - uses: julia-actions/cache@v2
      - uses: julia-actions/julia-buildpkg@v1
      - uses: julia-actions/julia-runtest@v1
```

**Step 2: Commit + push**

```bash
git add .github/workflows/CI.yml
git commit -m "add GitHub Actions CI"
```

---

## Open questions / things to confirm before execution

1. **Struct name**: confirm `Mesher` is acceptable (vs the literal `Martini` from the API preview the user picked). See the "Naming caveat" in the plan header. If `Martini` is required, document `using Martini: Martini` and adjust all references.
2. **UUID**: needs to be generated in Task 1 step 1; the implementer should paste the output into `Project.toml`.
3. **PNG decoder choice**: `PNGFiles.jl` is the recommended low-dep option. `ImageIO`+`FileIO` would also work but pulls more.
4. **`indices` scratch buffer ownership**: this plan allocates a fresh `Vector{UInt32}` per `get_mesh` call. The JS version reuses one buffer per `Mesher`. For real-time use cases, exposing an optional `scratch` kwarg later is a fast follow.
5. **Thread safety**: with per-call scratch, `get_mesh` is thread-safe across distinct `Tile`s sharing one `Mesher`. Worth noting in docs.

---

## Execution handoff

**Plan complete and saved to `Martini.jl/docs/plans/2026-05-16-martini-port.md`.**

Two execution options:

1. **Subagent-Driven (this session)** — I dispatch a fresh subagent per task with code review between tasks; fast iteration.
2. **Parallel Session (separate)** — Open a new session pointed at `Martini.jl/` and use `superpowers:executing-plans` to run batches with checkpoints.

Which approach?
