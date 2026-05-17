# Parametric eltypes Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make `Tile`, `Mesh`, and `get_mesh` parametric on user-chosen
element types — float type for the heightfield, point type for vertices,
face type for triangles — so that callers can opt into `Float32` or
`Float64` tiles and request output as e.g. `Vector{Point2{UInt16}}` /
`Vector{GLTriangleFace}` from GeometryBasics.

**Architecture:** Three orthogonal type parameters.
- `Tile{T<:AbstractFloat}` — eltype of `terrain` and `errors` matrices.
  Inferred from `eltype(terrain)` in `create_tile`. Internal arithmetic
  uses `widen_for_error(T)` as the intermediate type so the JS Float32
  parity guarantee is preserved (F32→F64) while F64 stays F64.
- `Mesh{P,F}` — `vertices::Vector{P}` (constructed `P(x,y)`) and
  `triangles::Vector{F}` (constructed `F(a,b,c)`), both 1-based by
  default. `GLTriangleFace` users get auto 0-based via that type's own
  `OffsetInteger{-1, UInt32}` semantics.
- `get_mesh(tile; point_type, face_type, max_error, cache)` — types as
  kwargs (default `NTuple{2,UInt16}` and `NTuple{3,UInt32}` so no
  runtime dep on GeometryBasics). `cache::MesherCache` is **required
  conceptually** but defaults to a fresh allocation so casual callers
  don't have to think about it — hot loops pass an explicit one.

**Compilation:** `Base.@constprop :aggressive` on `get_mesh` and
`create_tile` so that the kwarg-supplied types (`point_type`,
`face_type`) and the input `eltype` propagate through to the inner
`_Filler{P,F,Te}` / `Tile{T}` specialization sites. Without this, the
compiler can drop specialization at the kwarg dispatch boundary and
leave us with type-unstable inner calls.

**Tech Stack:** Julia 1.10+, GeometryBasics as a test-only dep, Documenter.

**Out of scope:** Rewriting `_Builder`/`_Filler` as immutable + Refs.
Current form is the modern Julia 1.8+ idiom and the Ref alternative would
add one heap allocation per counter. If you disagree after reading the
plan, the change is local to those two structs and easy to redo.

---

### Task 1: Add `widen_for_error` helper for intermediate arithmetic

**Files:**
- Modify: `src/Martini.jl` — insert above `_update_errors!`

**Step 1: Add helper**

```julia
@inline widen_for_error(::Type{Float32}) = Float64
@inline widen_for_error(::Type{T}) where {T<:AbstractFloat} = T
```

The point: for `Float32` we promote to `Float64` to bit-match the JS
reference (since JS Float32Array reads become Number/F64 for arithmetic).
For `Float64` and beyond, we stay in `T` — no spurious widening, no
BigFloat precision loss.

**Step 2: Confirm it compiles**

Run: `julia --project=. -e 'using Martini; @show Martini.widen_for_error(Float32) Martini.widen_for_error(Float64)'`
Expected: `Float64`, `Float64`.

**Step 3: Commit**

```bash
git add src/Martini.jl
git commit -m "feat: add widen_for_error helper for parametric tile arithmetic"
```

---

### Task 2: Parameterize `Tile` on T <: AbstractFloat

**Files:**
- Modify: `src/Martini.jl:77-138` (struct + create_tile + _update_errors!)

**Step 1: Rewrite struct + docstring**

```julia
"""
    Tile{T<:AbstractFloat}

A heightfield bound to a [`Mesher`](@ref), together with the per-vertex
maximum approximation error map. `T` is the storage eltype (default
`Float32`; pass `Float64` terrain to `create_tile` to get a `Tile{Float64}`).
"""
struct Tile{T<:AbstractFloat}
    mesher::Mesher
    terrain::Matrix{T}
    errors::Matrix{T}
end
```

**Step 2: Rewrite `create_tile` to dispatch on input eltype**

```julia
Base.@constprop :aggressive function create_tile(
    mesher::Mesher,
    terrain::AbstractArray{T},
) where {T<:AbstractFloat}
    sz = mesher.grid_size
    length(terrain) == sz * sz || throw(ArgumentError(
        "Expected terrain of length $(sz * sz) ($sz x $sz), got $(length(terrain))."))
    terrain_mat = reshape(collect(T, terrain), sz, sz)
    errors_mat = zeros(T, sz, sz)
    tile = Tile{T}(mesher, terrain_mat, errors_mat)
    _update_errors!(tile)
    return tile
end

# Fallback: integer / unspecified eltype defaults to Float32 (matches old behavior)
function create_tile(mesher::Mesher, terrain)
    create_tile(mesher, collect(Float32, terrain))
end
```

**Step 3: Rewrite `_update_errors!` parametrically**

```julia
function _update_errors!(tile::Tile{T}) where {T<:AbstractFloat}
    m = tile.mesher
    coords = m.coords
    terrain = tile.terrain
    errors = tile.errors
    npt = m.num_parent_triangles
    nt = m.num_triangles
    W = widen_for_error(T)

    @inbounds for i in (nt - 1):-1:0
        k = i * 4 + 1
        ax = Int(coords[k    ]); ay = Int(coords[k + 1])
        bx = Int(coords[k + 2]); by = Int(coords[k + 3])
        mx = (ax + bx) >> 1
        my = (ay + by) >> 1
        cx = mx + my - ay
        cy = my + ax - mx

        interp = (W(terrain[ax, ay]) + W(terrain[bx, by])) / 2
        middle_err = abs(interp - W(terrain[mx, my]))
        errors[mx, my] = T(max(W(errors[mx, my]), middle_err))

        if i < npt
            errors[mx, my] = T(max(
                W(errors[mx, my]),
                W(errors[(ax + cx) >> 1, (ay + cy) >> 1]),
                W(errors[(bx + cx) >> 1, (by + cy) >> 1]),
            ))
        end
    end
    return tile
end
```

**Step 4: Verify existing tests still pass**

Run: `julia --project=test -e 'using Pkg; Pkg.test()'`
Expected: 23/23 tests still pass (the existing `Float32` parity test
should be unaffected — same code path: T=Float32 ⇒ W=Float64).

**Step 5: Commit**

```bash
git add src/Martini.jl
git commit -m "feat: parameterize Tile on AbstractFloat eltype"
```

---

### Task 3: Restructure `Mesh` to `Mesh{P,F}` + update `_Filler`

**Files:**
- Modify: `src/Martini.jl:140-152` (Mesh struct)
- Modify: `src/Martini.jl:181-215` (`_Filler` and `_process!`)

**Step 1: Rewrite `Mesh` struct + docstring**

```julia
"""
    Mesh{P,F}

Result of [`get_mesh`](@ref). `vertices::Vector{P}` and
`triangles::Vector{F}`, both 1-based. The point type `P` must accept
`P(x, y)` where `x, y` are 1-based grid coordinates in `[1, grid_size]`.
The face type `F` must accept `F(a, b, c)` where `a, b, c` are 1-based
column indices into `vertices`.

Defaults are `NTuple{2,UInt16}` and `NTuple{3,UInt32}` (no runtime deps).
GeometryBasics interop:

```julia
using GeometryBasics
mesh = get_mesh(tile; point_type = Point2{UInt16}, face_type = GLTriangleFace)
```

`GLTriangleFace` stores its indices in `OffsetInteger{-1, UInt32}`, so a
1-based `(a, b, c)` becomes 0-based internally — i.e. directly
GL-uploadable.
"""
struct Mesh{P,F}
    vertices::Vector{P}
    triangles::Vector{F}
end
```

**Step 2: Update `_Filler` to carry P, F**

```julia
mutable struct _Filler{P,F}
    const size::Int
    const max_error::Float32
    const errors::Matrix{Float32}    # NOTE: see Task 4 — also widen this for Tile{T}
    const indices::Matrix{UInt32}
    const vertices::Vector{P}
    const triangles::Vector{F}
    tri_offset::Int
end
```

**Step 3: Update `_process!` to construct P and F**

```julia
function _process!(f::_Filler{P,F}, ax::Int, ay::Int, bx::Int, by::Int, cx::Int, cy::Int) where {P,F}
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
            f.vertices[a] = P(ax, ay)
            f.vertices[b] = P(bx, by)
            f.vertices[c] = P(cx, cy)
            f.triangles[f.tri_offset ÷ 3 + 1] = F(a, b, c)
            f.tri_offset += 3
        end
    end
    return nothing
end
```

Note: `tri_offset` stays in units of 3 (to keep the `_Filler` signature
unchanged from Task 5's perspective), but we now index `triangles`
element-by-element since each `F(a,b,c)` is one element.

**Step 4: No commit yet — `_process!` won't compile standalone until Task 4 wires `get_mesh`.**

---

### Task 4: Add `MesherCache` + update `get_mesh` with kwargs and aggressive constprop

**Files:**
- Modify: `src/Martini.jl:154-161` (`_Builder` — also parameterize on errors eltype)
- Modify: `src/Martini.jl:163-178` (`_count!` — change error matrix eltype)
- Modify: `src/Martini.jl:224-245` (`get_mesh`)
- Add: `MesherCache` struct near the top, exported

**Step 1: Add `MesherCache` struct**

```julia
"""
    MesherCache(grid_size::Integer)
    MesherCache(mesher::Mesher)

Preallocated scratch buffer for [`get_mesh`](@ref). Holds the per-call
`Matrix{UInt32}` index map (1 MB at grid_size=513). Pass via the `cache`
kwarg to avoid the per-call allocation in hot loops:

```julia
cache = MesherCache(mesher)
for err in 1:50
    mesh = get_mesh(tile; max_error = err, cache)
end
```

One `MesherCache` per concurrent task — it is **not** thread-safe to
share. It deliberately does NOT live on the `Mesher` itself, so that a
single `Mesher` remains safely shareable across threads.
"""
struct MesherCache
    indices::Matrix{UInt32}
    MesherCache(grid_size::Integer) = new(zeros(UInt32, grid_size, grid_size))
    MesherCache(m::Mesher) = MesherCache(m.grid_size)
end
```

Add `MesherCache` to the `export` line at the top of the module.

**Step 2: Parameterize `_Builder` on `Te` (errors eltype)**

```julia
mutable struct _Builder{Te}
    const size::Int
    const max_error::Te
    const errors::Matrix{Te}
    const indices::Matrix{UInt32}
    num_vertices::Int
    num_triangles::Int
end
```

`_count!` becomes `function _count!(b::_Builder{Te}, ...) where {Te}` —
everything else inside stays the same.

**Step 3: Parameterize `_Filler` on Te too**

`_Filler{P,F,Te}` carries `const errors::Matrix{Te}` and
`const max_error::Te`. Mesh construction still uses `P, F` for
vertices/triangles.

**Step 4: Rewrite `get_mesh`**

```julia
Base.@constprop :aggressive function get_mesh(
    tile::Tile{T};
    max_error::Real = 0,
    point_type::Type{P} = NTuple{2,UInt16},
    face_type::Type{F}  = NTuple{3,UInt32},
    cache::MesherCache  = MesherCache(tile.mesher),
) where {T<:AbstractFloat, P, F}
    m = tile.mesher
    sz = m.grid_size
    size(cache.indices) == (sz, sz) || throw(ArgumentError(
        "MesherCache size $(size(cache.indices)) doesn't match grid $sz × $sz."))
    err = T(max_error)
    indices = cache.indices
    fill!(indices, UInt32(0))

    builder = _Builder{T}(sz, err, tile.errors, indices, 0, 0)
    _count!(builder, 1,  1,  sz, sz, sz, 1 )
    _count!(builder, sz, sz, 1,  1,  1,  sz)

    verts = Vector{P}(undef, builder.num_vertices)
    tris  = Vector{F}(undef, builder.num_triangles)

    filler = _Filler{P,F,T}(sz, err, tile.errors, indices, verts, tris, 0)
    _process!(filler, 1,  1,  sz, sz, sz, 1 )
    _process!(filler, sz, sz, 1,  1,  1,  sz)

    return Mesh(verts, tris)
end
```

Notes:
- `_Filler` is now `_Filler{P,F,Te}` (3-param). Update its definition in
  Task 3 accordingly before this task — or merge Tasks 3 and 4 into one
  batch as a single commit if you prefer atomic intermediate states.
- `fill!(indices, UInt32(0))` zeros the reused buffer; this is the same
  O(sz²) work `zeros(UInt32, sz, sz)` did before, but with no
  allocation.
- `Base.@constprop :aggressive` is on the method definition, **not** the
  generated kwarg helper. In practice you may need to write the
  annotation on the `_get_mesh_impl(tile, max_error, P, F, cache)`
  helper if profiling shows the kwarg wrapper losing specialization.
  Plan: ship the simple form first; verify with `@code_warntype` on a
  call site with literal types; only refactor to a helper if specialization
  is not happening.

**Step 5: Smoke-test compilation + specialization**

Run:
```julia
julia --project=test -e '
using Martini
m = Mesher(5)
t = create_tile(m, zeros(Float32, 25))
mesh = get_mesh(t)
@show typeof(mesh) length(mesh.vertices) length(mesh.triangles)
@code_warntype get_mesh(t; max_error=0)
'
```
Expected: `Mesh{Tuple{UInt16,UInt16}, Tuple{UInt32,UInt32,UInt32}}`,
4 vertices, 2 triangles. `@code_warntype` clean (no `Any`, no `Union`s
in the return type).

**Step 6: Commit Tasks 3 + 4 together**

```bash
git add src/Martini.jl
git commit -m "feat: parametric Mesh{P,F}, MesherCache, aggressive constprop on get_mesh"
```

---

### Task 5: Update existing tests for new Mesh shape

**Files:**
- Modify: `test/runtests.jl` — every assertion against `mesh.vertices`/`mesh.triangles`
- Modify: `test/Project.toml` — add `GeometryBasics`

**Step 1: Update `get_mesh on flat terrain` testset**

```julia
@testset "get_mesh on flat terrain" begin
    m = Mesher(5)
    tile = create_tile(m, zeros(Float32, 25))
    mesh = get_mesh(tile; max_error = 0)
    @test length(mesh.vertices) == 4
    @test length(mesh.triangles) == 2
    @test Set(mesh.vertices) == Set([
        (UInt16(1), UInt16(1)), (UInt16(5), UInt16(1)),
        (UInt16(1), UInt16(5)), (UInt16(5), UInt16(5)),
    ])
    @test all(t -> all(1 .<= t .<= 4), mesh.triangles)
end
```

**Step 2: Update `subdivides when error exceeds threshold` testset**

```julia
@test length(mesh_tight.vertices) > length(mesh_loose.vertices)
```

**Step 3: Update `Fuji parity` testset**

Reshape the expected flat arrays into the new tuple form:

```julia
expected_vertex_tuples = [
    (expected_vertices[2i-1], expected_vertices[2i])
    for i in 1:(length(expected_vertices) ÷ 2)
]
expected_triangle_tuples = [
    (expected_triangles[3i-2], expected_triangles[3i-1], expected_triangles[3i])
    for i in 1:(length(expected_triangles) ÷ 3)
]
@test mesh.vertices  == expected_vertex_tuples
@test mesh.triangles == expected_triangle_tuples
```

**Step 4: Run tests**

Run: `julia --project=test -e 'using Pkg; Pkg.test()'`
Expected: all existing testsets still pass (23 tests, possibly +0 in
count since we restructured assertions in-place).

**Step 5: Commit**

```bash
git add test/runtests.jl
git commit -m "test: update existing assertions to Vector{NTuple} mesh shape"
```

---

### Task 6: Add Float64 tile testset

**Files:**
- Modify: `test/runtests.jl` — append new testset

**Step 1: Write the testset**

```julia
@testset "Float64 tile" begin
    m = Mesher(5)
    terrain = zeros(Float64, 25)
    terrain[13] = 100.0
    tile = create_tile(m, terrain)
    @test tile isa Martini.Tile{Float64}
    @test eltype(tile.terrain) == Float64
    @test eltype(tile.errors) == Float64
    @test tile.errors[3, 3] == 100.0
    mesh = get_mesh(tile; max_error = 0)
    @test length(mesh.vertices) > 4  # spike forces subdivision
end
```

**Step 2: Run tests**

Run: `julia --project=test -e 'using Pkg; Pkg.test()'`
Expected: all pass.

**Step 3: Commit**

```bash
git add test/runtests.jl
git commit -m "test: cover Tile{Float64} path"
```

---

### Task 7: Add GeometryBasics integration testset

**Files:**
- Modify: `test/Project.toml` — add `GeometryBasics = "5c1252a2-..."` (look up actual UUID from registry)
- Modify: `test/runtests.jl` — append testset

**Step 1: Add GeometryBasics to test deps**

Look up UUID:
```bash
grep -A1 '^GeometryBasics' ~/.julia/registries/General/G/GeometryBasics/Package.toml | head -3
```

Add to `test/Project.toml`:
```toml
[deps]
GeometryBasics = "<uuid>"
...
[compat]
GeometryBasics = "0.4, 0.5"  # check what's current at write time
```

**Step 2: Write the testset**

```julia
@testset "GeometryBasics interop" begin
    using GeometryBasics
    m = Mesher(5)
    tile = create_tile(m, zeros(Float32, 25))
    mesh = get_mesh(tile;
        point_type = Point2{UInt16},
        face_type  = GLTriangleFace,
    )
    @test mesh.vertices isa Vector{Point2{UInt16}}
    @test mesh.triangles isa Vector{GLTriangleFace}
    @test length(mesh.vertices) == 4
    @test length(mesh.triangles) == 2
    # GLTriangleFace stores values in OffsetInteger{-1, UInt32}, so a
    # 1-based input becomes 0-based GL-ready output:
    flat = reinterpret(UInt32, mesh.triangles)
    @test all(0 .<= flat .<= 3)
end
```

**Step 3: Run tests**

Run: `julia --project=test -e 'using Pkg; Pkg.instantiate(); Pkg.test()'`
Expected: all pass.

**Step 4: Commit**

```bash
git add test/Project.toml test/runtests.jl
git commit -m "test: cover GeometryBasics Point2/GLTriangleFace interop"
```

---

### Task 8: Add `MesherCache` reuse testset + bench update

**Files:**
- Modify: `test/runtests.jl` — append testset
- Modify: `bench/bench.jl` — reuse one `MesherCache` across the sweep

**Step 1: Add reuse testset**

```julia
@testset "MesherCache reuse" begin
    m = Mesher(5)
    tile = create_tile(m, zeros(Float32, 25))
    cache = MesherCache(m)
    mesh1 = get_mesh(tile; max_error = 0, cache)
    mesh2 = get_mesh(tile; max_error = 0, cache)
    @test mesh1.vertices == mesh2.vertices
    @test mesh1.triangles == mesh2.triangles

    # Size mismatch should error.
    bad = MesherCache(9)
    @test_throws ArgumentError get_mesh(tile; cache = bad)
end
```

**Step 2: Update `bench/bench.jl` `sweep!`**

Construct one `MesherCache(mesher)` outside the loop and pass it on
every `get_mesh` call.

**Step 3: Run tests**

Run: `julia --project=test -e 'using Pkg; Pkg.test()'`
Expected: all pass.

**Step 4: Run bench**

Run: `julia --project=bench bench/bench.jl`
Compare to `bench/RESULTS.md` — cache reuse should *reduce* the
sweep total. Update `RESULTS.md` if there is a meaningful shift.

**Step 5: Commit**

```bash
git add test/runtests.jl bench/bench.jl bench/RESULTS.md
git commit -m "test+bench: cover MesherCache reuse path"
```

---

### Task 9: Docs + push

**Files:**
- Modify: `docs/src/index.md` — new API in quick-start; note on type params and MesherCache
- Modify: `docs/src/api.md` — add `MesherCache` to the type list
- Modify: `README.md` — same updates

**Step 1: Update docs**

Cover four things: `Tile{T}` eltype dispatch from `eltype(terrain)`,
`point_type`/`face_type` kwargs with GeometryBasics example, `MesherCache`
reuse, and the new `Mesh{P,F}` output shape.

**Step 2: Build docs locally**

Run: `julia --project=docs docs/make.jl`
Expected: clean build, no missing-docs warnings.

**Step 3: Bump version**

In root `Project.toml`: `version = "0.2.0"` (minor bump — breaking
output-shape change for `Mesh`).

**Step 4: Commit and push**

```bash
git add docs/ README.md Project.toml
git commit -m "docs: document parametric eltypes (Tile, Mesh) + bump to 0.2.0"
git push
```

**Step 5: Watch CI**

Run: `gh run watch --exit-status`
Expected: all matrix jobs pass; Documentation deploys.
