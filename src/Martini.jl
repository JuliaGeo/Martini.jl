module Martini

using GeometryBasics

export MartiniMesh, create_tile, get_mesh

"""
    MartiniMesh

Main structure for RTIN (Right-Triangulated Irregular Networks) terrain mesh generation.
Holds precomputed triangle coordinates for efficient mesh generation.

# Fields
- `gridsize::Int`: Size of the grid (must be 2^n + 1)
- `num_triangles::Int`: Total number of triangles in the hierarchy
- `num_parent_triangles::Int`: Number of parent triangles
- `indices::Vector{UInt32}`: Index mapping for vertices
- `coords::Matrix{UInt16}`: Precomputed triangle coordinates (4 × num_triangles)
"""
struct MartiniMesh
    gridsize::Int
    num_triangles::Int
    num_parent_triangles::Int
    indices::Vector{UInt32}
    coords::Matrix{UInt16}
end

"""
    MartiniMesh(gridsize::Int=257)

Create a new MartiniMesh for terrain mesh generation.

# Arguments
- `gridsize::Int`: Size of the terrain grid. Must be 2^n + 1 (e.g., 257, 513, 1025)

# Example
```julia
martini = MartiniMesh(257)
```
"""
function MartiniMesh(gridsize::Int=257)
    tilesize = gridsize - 1
    # Check if tilesize is a power of 2
    if (tilesize & (tilesize - 1)) != 0
        error("Expected grid size to be 2^n+1, got $gridsize")
    end

    num_triangles = tilesize * tilesize * 2 - 2
    num_parent_triangles = num_triangles - tilesize * tilesize

    indices = zeros(UInt32, gridsize * gridsize)
    coords = zeros(UInt16, 4, num_triangles)

    # Get triangle coordinates from its index in an implicit binary tree
    for i in 1:num_triangles
        id = i + 1  # Adjust for 1-based indexing
        ax, ay, bx, by, cx, cy = 0, 0, 0, 0, 0, 0

        if (id & 1) != 0
            # bottom-left triangle
            bx = by = cx = tilesize
        else
            # top-right triangle
            ax = ay = cy = tilesize
        end

        id >>= 1
        while id > 1
            mx = (ax + bx) >> 1
            my = (ay + by) >> 1

            if (id & 1) != 0  # left half
                bx, by = ax, ay
                ax, ay = cx, cy
            else  # right half
                ax, ay = bx, by
                bx, by = cx, cy
            end
            cx, cy = mx, my
            id >>= 1
        end

        coords[:, i] = [ax, ay, bx, by]
    end

    MartiniMesh(gridsize, num_triangles, num_parent_triangles, indices, coords)
end

"""
    MartiniTile

Represents a terrain tile with height data and computed error metrics.

# Fields
- `terrain::Vector{Float64}`: Flattened terrain height data
- `martini::MartiniMesh`: Parent MartiniMesh structure
- `errors::Vector{Float64}`: Computed error metrics for each point
"""
struct MartiniTile
    terrain::Vector{Float64}
    martini::MartiniMesh
    errors::Vector{Float64}
end

"""
    create_tile(martini::MartiniMesh, terrain::Matrix{T}) where T<:Real

Create a terrain tile from a height matrix.

# Arguments
- `martini::MartiniMesh`: The MartiniMesh structure
- `terrain::Matrix{T}`: An n×m matrix of terrain heights

# Returns
- `MartiniTile`: A tile ready for mesh generation

# Example
```julia
martini = MartiniMesh(257)
heights = rand(257, 257)
tile = create_tile(martini, heights)
```
"""
function create_tile(martini::MartiniMesh, terrain::Matrix{T}) where T<:Real
    nrows, ncols = size(terrain)
    size = martini.gridsize

    if nrows != size || ncols != size
        error("Expected terrain data of size $size × $size, got $nrows × $ncols")
    end

    # Flatten terrain to column-major order (Julia default)
    terrain_flat = vec(terrain')  # Transpose to match row-major semantics
    errors = zeros(Float64, length(terrain_flat))

    tile = MartiniTile(terrain_flat, martini, errors)
    update!(tile)
    return tile
end

"""
    update!(tile::MartiniTile)

Update error metrics for the terrain tile by computing approximation errors
across the triangle hierarchy.
"""
function update!(tile::MartiniTile)
    martini = tile.martini
    num_triangles = martini.num_triangles
    num_parent_triangles = martini.num_parent_triangles
    coords = martini.coords
    size = martini.gridsize
    terrain = tile.terrain
    errors = tile.errors

    # Iterate over all possible triangles, starting from the smallest level
    for i in num_triangles:-1:1
        ax = coords[1, i]
        ay = coords[2, i]
        bx = coords[3, i]
        by = coords[4, i]
        mx = (ax + bx) >> 1
        my = (ay + by) >> 1
        cx = mx + my - ay
        cy = my + ax - mx

        # Calculate error in the middle of the long edge of the triangle
        # Convert to 1-based indexing
        interpolated_height = (terrain[ay * size + ax + 1] + terrain[by * size + bx + 1]) / 2
        middle_index = my * size + mx + 1
        middle_error = abs(interpolated_height - terrain[middle_index])

        errors[middle_index] = max(errors[middle_index], middle_error)

        if i <= num_parent_triangles  # bigger triangles; accumulate error with children
            left_child_index = ((ay + cy) >> 1) * size + ((ax + cx) >> 1) + 1
            right_child_index = ((by + cy) >> 1) * size + ((bx + cx) >> 1) + 1
            errors[middle_index] = max(errors[middle_index], errors[left_child_index], errors[right_child_index])
        end
    end
end

"""
    get_mesh(tile::MartiniTile; max_error::Real=0)

Generate a simplified terrain mesh based on the specified error threshold.

# Arguments
- `tile::MartiniTile`: The terrain tile
- `max_error::Real`: Maximum allowed error for mesh simplification (default: 0)

# Returns
- `GeometryBasics.Mesh`: A mesh with vertices containing x, y, z coordinates where z is the height,
  and vertex metadata containing the height values

# Example
```julia
martini = MartiniMesh(257)
heights = rand(257, 257) .* 100
tile = create_tile(martini, heights)
mesh = get_mesh(tile, max_error=10.0)
```
"""
function get_mesh(tile::MartiniTile; max_error::Real=0)
    martini = tile.martini
    size = martini.gridsize
    indices = martini.indices
    errors = tile.errors
    terrain = tile.terrain

    num_vertices = 0
    num_triangles = 0
    max_idx = size - 1

    # Reset indices
    fill!(indices, 0)

    # First pass: count vertices and triangles
    function count_elements(ax, ay, bx, by, cx, cy)
        mx = (ax + bx) >> 1
        my = (ay + by) >> 1

        if abs(ax - cx) + abs(ay - cy) > 1 && errors[my * size + mx + 1] > max_error
            count_elements(cx, cy, ax, ay, mx, my)
            count_elements(bx, by, cx, cy, mx, my)
        else
            # Assign indices (1-based)
            idx_a = ay * size + ax + 1
            idx_b = by * size + bx + 1
            idx_c = cy * size + cx + 1

            if indices[idx_a] == 0
                num_vertices += 1
                indices[idx_a] = num_vertices
            end
            if indices[idx_b] == 0
                num_vertices += 1
                indices[idx_b] = num_vertices
            end
            if indices[idx_c] == 0
                num_vertices += 1
                indices[idx_c] = num_vertices
            end
            num_triangles += 1
        end
    end

    count_elements(0, 0, max_idx, max_idx, max_idx, 0)
    count_elements(max_idx, max_idx, 0, 0, 0, max_idx)

    # Allocate arrays for vertices and triangles
    vertices = Vector{Point3f}(undef, num_vertices)
    heights = Vector{Float64}(undef, num_vertices)
    triangles = Vector{TriangleFace{Int}}(undef, num_triangles)
    tri_index = 1

    # Second pass: populate vertex and triangle data
    function process_triangle(ax, ay, bx, by, cx, cy)
        mx = (ax + bx) >> 1
        my = (ay + by) >> 1

        if abs(ax - cx) + abs(ay - cy) > 1 && errors[my * size + mx + 1] > max_error
            # Triangle doesn't approximate the surface well enough; drill down further
            process_triangle(cx, cy, ax, ay, mx, my)
            process_triangle(bx, by, cx, cy, mx, my)
        else
            # Add a triangle
            idx_a = ay * size + ax + 1
            idx_b = by * size + bx + 1
            idx_c = cy * size + cx + 1

            a = indices[idx_a]
            b = indices[idx_b]
            c = indices[idx_c]

            # Store vertex coordinates with height as z coordinate
            vertices[a] = Point3f(ax, ay, terrain[idx_a])
            vertices[b] = Point3f(bx, by, terrain[idx_b])
            vertices[c] = Point3f(cx, cy, terrain[idx_c])

            # Store heights for metadata
            heights[a] = terrain[idx_a]
            heights[b] = terrain[idx_b]
            heights[c] = terrain[idx_c]

            # Store triangle indices
            triangles[tri_index] = TriangleFace(a, b, c)
            tri_index += 1
        end
    end

    process_triangle(0, 0, max_idx, max_idx, max_idx, 0)
    process_triangle(max_idx, max_idx, 0, 0, 0, max_idx)

    # Create mesh with vertex metadata
    return GeometryBasics.Mesh(
        meta(vertices, height=heights),
        triangles
    )
end

end # module
