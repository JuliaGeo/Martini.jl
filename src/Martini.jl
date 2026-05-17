module Martini

export Mesher, Tile, Mesh, create_tile, get_mesh

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
end

struct Tile
    mesher::Mesher
    terrain::Vector{Float32}
    errors::Vector{Float32}
end

"""
    create_tile(mesher::Mesher, terrain::AbstractVector{<:Real}) -> Tile

Build a `Tile` for the given terrain heightfield. `terrain` must have length
`mesher.grid_size^2`, laid out y-major: `terrain[y*size + x + 1]` is the height
at 0-based grid position `(x, y)`. Computes the per-vertex max-error map eagerly.
"""
function create_tile(mesher::Mesher, terrain::AbstractVector{<:Real})
    sz = mesher.grid_size
    length(terrain) == sz * sz || throw(ArgumentError(
        "Expected terrain of length $(sz * sz) ($sz x $sz), got $(length(terrain))."))
    terrain_f32 = terrain isa Vector{Float32} ? copy(terrain) : Vector{Float32}(terrain)
    errors = zeros(Float32, length(terrain_f32))
    tile = Tile(mesher, terrain_f32, errors)
    _update_errors!(tile)
    return tile
end

function _update_errors!(tile::Tile)
    m = tile.mesher
    coords = m.coords
    sz = m.grid_size
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

        interp = (terrain[ay * sz + ax + 1] + terrain[by * sz + bx + 1]) / 2
        middle_idx = my * sz + mx + 1
        middle_err = abs(interp - terrain[middle_idx])
        errors[middle_idx] = max(errors[middle_idx], middle_err)

        if i < npt
            left_child  = ((ay + cy) >> 1) * sz + ((ax + cx) >> 1) + 1
            right_child = ((by + cy) >> 1) * sz + ((bx + cx) >> 1) + 1
            errors[middle_idx] = max(errors[middle_idx], errors[left_child], errors[right_child])
        end
    end
    return tile
end

end # module
