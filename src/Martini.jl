module Martini

export Mesher, MesherCache, Tile, Mesh, create_tile, get_mesh

"""
    Mesher(grid_size::Integer = 257)

Precompute the implicit RTIN binary-tree triangle coordinates for a tile of
size `grid_size × grid_size`. `grid_size` must be `2^k + 1` for some `k >= 1`
(i.e. 3, 5, 9, 17, 33, 65, 129, 257, 513, …). Constant per grid size — reuse
a single `Mesher` across many terrains via [`create_tile`](@ref).
"""
struct Mesher
    grid_size::Int
    num_triangles::Int
    num_parent_triangles::Int
    coords::Vector{UInt16}   # flat: [a1x, a1y, b1x, b1y, a2x, a2y, b2x, b2y, ...]
                             # values are 1-based grid positions in [1, grid_size]

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
            ax = ay = bx = by = cx = cy = 1
            if id & 1 != 0
                bx = by = cx = grid_size          # bottom-left triangle
            else
                ax = ay = cy = grid_size          # top-right triangle
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
            k = i * 4 + 1
            coords[k    ] = ax
            coords[k + 1] = ay
            coords[k + 2] = bx
            coords[k + 3] = by
        end

        return new(grid_size, num_triangles, num_parent_triangles, coords)
    end
end

"""
    Tile{T<:AbstractFloat}

A heightfield bound to a [`Mesher`](@ref), together with the per-vertex maximum
approximation error map. Constructed via [`create_tile`](@ref); pass to
[`get_mesh`](@ref) to extract a triangle mesh at any error threshold.

`T` is the storage eltype, inferred from the input array passed to
`create_tile` (defaults to `Float32` for non-`AbstractFloat` input).

Fields:
- `mesher::Mesher` — the precomputed RTIN structure
- `terrain::Matrix{T}` — `(grid_size, grid_size)`, indexed `terrain[x, y]` (1-based)
- `errors::Matrix{T}`  — same shape; `errors[x, y]` is the worst error
  observed at grid position `(x, y)` across all triangle levels.
"""
struct Tile{T<:AbstractFloat}
    mesher::Mesher
    terrain::Matrix{T}
    errors::Matrix{T}
end

"""
    create_tile(mesher::Mesher, terrain) -> Tile

Build a `Tile` for the given terrain heightfield. `terrain` may be a `Vector`
of length `grid_size^2` (y-major, matching the Mapbox/JS convention) or a
`Matrix` of size `(grid_size, grid_size)` indexed `terrain[x, y]` with 1-based
`(x, y)`. The two layouts share memory after reshape. Computes the per-vertex
max-error map eagerly.

The element type of `terrain` determines the `Tile{T}` eltype: pass
`Matrix{Float64}` to get a `Tile{Float64}`. Non-`AbstractFloat` input is
collected into `Float32`.
"""
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

function create_tile(mesher::Mesher, terrain)
    create_tile(mesher, collect(Float32, terrain))
end

@inline widen_for_error(::Type{Float32}) = Float64
@inline widen_for_error(::Type{T}) where {T<:AbstractFloat} = T

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
        ax = Int(coords[k    ])
        ay = Int(coords[k + 1])
        bx = Int(coords[k + 2])
        by = Int(coords[k + 3])
        mx = (ax + bx) >> 1
        my = (ay + by) >> 1
        cx = mx + my - ay
        cy = my + ax - mx

        # For T=Float32, widen to Float64 to bit-match the JS reference (its
        # Float32Array reads promote to Number/F64, comparisons happen in F64,
        # and truncation only on store). For T=Float64 this is a no-op.
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

"""
    Mesh{P,F}

Result of [`get_mesh`](@ref). `vertices::Vector{P}` and `triangles::Vector{F}`,
both 1-based by default.

- `P` is constructed as `P(x, y)` where `(x, y)` are 1-based grid coordinates
  in `[1, grid_size]`.
- `F` is constructed as `F(a, b, c)` where `(a, b, c)` are 1-based column
  indices into `vertices`.

Defaults are `P = NTuple{2,UInt16}` and `F = NTuple{3,UInt32}` so there is no
runtime dependency on GeometryBasics. For GL-ready output:

```julia
using GeometryBasics
mesh = get_mesh(tile; point_type = Point2{UInt16}, face_type = GLTriangleFace)
```

`GLTriangleFace` stores its indices in `OffsetInteger{-1, UInt32}`, so 1-based
inputs become 0-based on construction — directly GL-uploadable.
"""
struct Mesh{P,F}
    vertices::Vector{P}
    triangles::Vector{F}
end

"""
    MesherCache(grid_size::Integer)
    MesherCache(mesher::Mesher)

Preallocated scratch buffer for [`get_mesh`](@ref). Holds the per-call
`Matrix{UInt32}` index map (1 MB at `grid_size = 513`). Pass via the `cache`
kwarg to avoid the per-call allocation in hot loops:

```julia
cache = MesherCache(mesher)
for err in 1:50
    mesh = get_mesh(tile; max_error = err, cache)
end
```

One `MesherCache` per concurrent task — it is **not** thread-safe to share.
It deliberately does not live on the `Mesher` itself so that a single
`Mesher` remains safely shareable across threads.
"""
struct MesherCache
    indices::Matrix{UInt32}
    MesherCache(grid_size::Integer) = new(zeros(UInt32, grid_size, grid_size))
    MesherCache(m::Mesher) = MesherCache(m.grid_size)
end

mutable struct _Builder{Te}
    const size::Int
    const max_error::Te
    const errors::Matrix{Te}
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
    return nothing
end

# Tuple types want their args as a single tuple; everything else (Point2{T}
# from GeometryBasics, user-defined Point structs, etc.) takes positional args.
@inline _construct(::Type{P}, x::Integer, y::Integer) where {P<:Tuple} = P((x, y))
@inline _construct(::Type{P}, x::Integer, y::Integer) where {P} = P(x, y)
@inline _construct(::Type{F}, a::Integer, b::Integer, c::Integer) where {F<:Tuple} = F((a, b, c))
@inline _construct(::Type{F}, a::Integer, b::Integer, c::Integer) where {F} = F(a, b, c)

mutable struct _Filler{P,F,Te}
    const size::Int
    const max_error::Te
    const errors::Matrix{Te}
    const indices::Matrix{UInt32}
    const vertices::Vector{P}
    const triangles::Vector{F}
    tri_count::Int
end

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
            f.vertices[a] = _construct(P, ax, ay)
            f.vertices[b] = _construct(P, bx, by)
            f.vertices[c] = _construct(P, cx, cy)
            f.tri_count += 1
            f.triangles[f.tri_count] = _construct(F, a, b, c)
        end
    end
    return nothing
end

"""
    get_mesh(tile::Tile; max_error = 0,
             point_type = NTuple{2,UInt16},
             face_type  = NTuple{3,UInt32},
             cache      = MesherCache(tile.mesher)) -> Mesh

Walk the implicit RTIN binary tree top-down, emitting a triangle whenever the
error at its long-edge midpoint is at or below `max_error`. Returns a
`Mesh{P,F}` where vertices are constructed `point_type(x, y)` and triangles
are constructed `face_type(a, b, c)`. All indices are 1-based.

Pass an explicit `cache::MesherCache` in hot loops to avoid reallocating the
internal index buffer on every call.
"""
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

end # module
