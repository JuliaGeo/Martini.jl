module Martini

export Mesher, Tile, Mesh, create_tile, get_mesh

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

struct Tile
    mesher::Mesher
    terrain::Matrix{Float32}     # size (grid_size, grid_size); terrain[x, y]
    errors::Matrix{Float32}
end

"""
    create_tile(mesher::Mesher, terrain) -> Tile

Build a `Tile` for the given terrain heightfield. `terrain` may be a `Vector`
of length `grid_size^2` (y-major, matching the Mapbox/JS convention) or a
`Matrix` of size `(grid_size, grid_size)` indexed `terrain[x, y]` with 1-based
`(x, y)`. The two layouts share memory after reshape. Computes the per-vertex
max-error map eagerly.
"""
function create_tile(mesher::Mesher, terrain)
    sz = mesher.grid_size
    length(terrain) == sz * sz || throw(ArgumentError(
        "Expected terrain of length $(sz * sz) ($sz x $sz), got $(length(terrain))."))
    terrain_mat = reshape(collect(Float32, terrain), sz, sz)
    errors_mat = zeros(Float32, sz, sz)
    tile = Tile(mesher, terrain_mat, errors_mat)
    _update_errors!(tile)
    return tile
end

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

"""
    Mesh

Result of `get_mesh`. `vertices` is a `2 × N` matrix where each column is a
**1-based** `(x, y)` grid coordinate in `[1, grid_size]`. `triangles` is a
`3 × M` matrix where each column is a triple of 1-based column indices into
`vertices`. For WebGL/OpenGL output, subtract 1 from both `vertices` (to land
in `[0, grid_size-1]`) and `triangles` (to get 0-based indices).
"""
struct Mesh
    vertices::Matrix{UInt16}
    triangles::Matrix{UInt32}
end

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
    return nothing
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
    return nothing
end

"""
    get_mesh(tile::Tile; max_error::Real = 0) -> Mesh

Walk the implicit RTIN binary tree top-down, emitting a triangle whenever the
error at its long-edge midpoint is at or below `max_error`. Returns a `Mesh`
with 1-based vertex coordinates and 1-based triangle vertex indices.
"""
function get_mesh(tile::Tile; max_error::Real = 0)
    m = tile.mesher
    sz = m.grid_size
    err = Float32(max_error)
    indices = zeros(UInt32, sz, sz)

    builder = _Builder(sz, err, tile.errors, indices, 0, 0)
    _count!(builder, 1,  1,  sz, sz, sz, 1 )
    _count!(builder, sz, sz, 1,  1,  1,  sz)

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

end # module
