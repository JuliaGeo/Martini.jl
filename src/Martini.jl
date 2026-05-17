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

end # module
