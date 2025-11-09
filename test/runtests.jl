using Martini
using Test
using GeometryBasics

@testset "Martini.jl" begin
    @testset "MartiniMesh construction" begin
        # Test valid grid sizes (2^n + 1)
        @test MartiniMesh(3).gridsize == 3      # 2^1 + 1
        @test MartiniMesh(5).gridsize == 5      # 2^2 + 1
        @test MartiniMesh(9).gridsize == 9      # 2^3 + 1
        @test MartiniMesh(17).gridsize == 17    # 2^4 + 1
        @test MartiniMesh(257).gridsize == 257  # 2^8 + 1

        # Test invalid grid sizes
        @test_throws ErrorException MartiniMesh(4)   # Not 2^n + 1
        @test_throws ErrorException MartiniMesh(10)  # Not 2^n + 1
        @test_throws ErrorException MartiniMesh(256) # Not 2^n + 1
    end

    @testset "Tile creation" begin
        martini = MartiniMesh(17)

        # Test valid terrain
        terrain = rand(17, 17) .* 100
        tile = create_tile(martini, terrain)
        @test length(tile.terrain) == 17 * 17
        @test length(tile.errors) == 17 * 17

        # Test invalid terrain size
        @test_throws ErrorException create_tile(martini, rand(16, 16))
        @test_throws ErrorException create_tile(martini, rand(17, 16))
    end

    @testset "Mesh generation" begin
        martini = MartiniMesh(17)

        # Create a simple terrain (flat plane)
        terrain_flat = zeros(17, 17)
        tile_flat = create_tile(martini, terrain_flat)
        mesh_flat = get_mesh(tile_flat, max_error=0)

        @test mesh_flat isa GeometryBasics.Mesh
        @test length(coordinates(mesh_flat)) > 0
        @test length(faces(mesh_flat)) > 0

        # Create a terrain with variation
        terrain_varied = [(i + j) * 10.0 for i in 1:17, j in 1:17]
        tile_varied = create_tile(martini, terrain_varied)

        # Mesh with no simplification
        mesh_detailed = get_mesh(tile_varied, max_error=0)
        @test length(coordinates(mesh_detailed)) > 0

        # Mesh with simplification
        mesh_simple = get_mesh(tile_varied, max_error=50.0)
        @test length(coordinates(mesh_simple)) > 0
        @test length(coordinates(mesh_simple)) <= length(coordinates(mesh_detailed))

        # Check that vertices have height metadata
        verts = coordinates(mesh_detailed)
        @test haskey(GeometryBasics.metadata(verts), :height)

        # Verify heights match z coordinates
        heights = GeometryBasics.metadata(verts)[:height]
        for i in 1:length(verts)
            @test verts[i][3] == heights[i]
        end
    end

    @testset "Real terrain example" begin
        # Create a simple "mountain" terrain
        martini = MartiniMesh(33)
        center = 16
        terrain = zeros(33, 33)

        for i in 1:33, j in 1:33
            dist = sqrt((i - center)^2 + (j - center)^2)
            terrain[i, j] = max(0, 100 - dist * 5)
        end

        tile = create_tile(martini, terrain)

        # Generate meshes with different error thresholds
        mesh_high_detail = get_mesh(tile, max_error=1.0)
        mesh_low_detail = get_mesh(tile, max_error=10.0)

        @test length(coordinates(mesh_high_detail)) >= length(coordinates(mesh_low_detail))
        @test length(faces(mesh_high_detail)) >= length(faces(mesh_low_detail))

        println("High detail mesh: $(length(coordinates(mesh_high_detail))) vertices, $(length(faces(mesh_high_detail))) triangles")
        println("Low detail mesh: $(length(coordinates(mesh_low_detail))) vertices, $(length(faces(mesh_low_detail))) triangles")
    end
end
