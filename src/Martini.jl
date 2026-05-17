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
        # coords filled in next task; leave undef for now.
        return new(grid_size, num_triangles, num_parent_triangles, coords)
    end
end

end # module
