using Martini
using GeometryBasics

# Example 1: Simple random terrain
println("Example 1: Random terrain")
println("=" ^ 50)

martini = MartiniMesh(65)  # 2^6 + 1 = 65
terrain = rand(65, 65) .* 100  # Random heights 0-100

tile = create_tile(martini, terrain)

# Generate meshes with different error thresholds
mesh_detailed = get_mesh(tile, max_error=1.0)
mesh_simple = get_mesh(tile, max_error=10.0)

println("Detailed mesh (error=1.0): $(length(coordinates(mesh_detailed))) vertices, $(length(faces(mesh_detailed))) triangles")
println("Simple mesh (error=10.0): $(length(coordinates(mesh_simple))) vertices, $(length(faces(mesh_simple))) triangles")
println()

# Example 2: Mountain terrain
println("Example 2: Mountain terrain")
println("=" ^ 50)

martini2 = MartiniMesh(129)  # 2^7 + 1 = 129
center = 64
terrain2 = zeros(129, 129)

# Create a conical mountain
for i in 1:129, j in 1:129
    dist = sqrt((i - center)^2 + (j - center)^2)
    terrain2[i, j] = max(0, 500 - dist * 5)
end

tile2 = create_tile(martini2, terrain2)

mesh_mountain = get_mesh(tile2, max_error=5.0)
println("Mountain mesh: $(length(coordinates(mesh_mountain))) vertices, $(length(faces(mesh_mountain))) triangles")

# Access vertex metadata
vertices = coordinates(mesh_mountain)
heights = GeometryBasics.metadata(vertices)[:height]
println("Height range: $(minimum(heights)) to $(maximum(heights))")
println()

# Example 3: Showing LOD behavior
println("Example 3: Level of Detail (LOD) comparison")
println("=" ^ 50)

martini3 = MartiniMesh(257)
# Create varied terrain with ridges
terrain3 = [(sin(i/10) * cos(j/10) * 50 + (i+j)/4) for i in 1:257, j in 1:257]
tile3 = create_tile(martini3, terrain3)

for error in [0.0, 1.0, 5.0, 10.0, 20.0]
    mesh = get_mesh(tile3, max_error=error)
    println("Error threshold $error: $(length(coordinates(mesh))) vertices")
end
