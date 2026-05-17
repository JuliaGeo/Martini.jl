using Test
using Martini

include("util.jl")

@testset "Martini.jl" begin
    @testset "Mesher construction" begin
        @test_throws ArgumentError Mesher(256)  # not 2^k + 1
        @test_throws ArgumentError Mesher(2)    # tile_size = 1; we reject sizes < 3
        @test_throws ArgumentError Mesher(0)
        @test_throws ArgumentError Mesher(-1)

        m = Mesher(257)
        @test m.grid_size == 257
    end

    @testset "Mesher coords (5x5 grid)" begin
        # tile_size = 4 -> num_triangles = 4*4*2 - 2 = 30
        m = Mesher(5)
        @test m.num_triangles == 30
        @test m.num_parent_triangles == 30 - 16   # 14

        # Triangle 0 (i=0, id=2): top-right corner of the whole tile.
        @test m.coords[1:4] == UInt16[4, 4, 0, 0]

        # Triangle 1 (i=1, id=3): bottom-left of the whole tile.
        @test m.coords[5:8] == UInt16[0, 0, 4, 4]
    end

    @testset "Tile / errors" begin
        m = Mesher(5)
        # Length mismatch should be rejected.
        @test_throws ArgumentError create_tile(m, zeros(Float32, 10))

        # Flat terrain -> all errors are 0.
        flat = zeros(Float32, 25)
        tile = create_tile(m, flat)
        @test tile.errors == zeros(Float32, 25)

        # Pointy: spike at the center vertex (0-based (2,2), 1-based index 13).
        # Linear interpolation of any pair of neighbors through (2,2) is 0,
        # so the error at that vertex should equal the height itself.
        terrain = zeros(Float32, 25)
        terrain[13] = 100f0
        tile2 = create_tile(m, terrain)
        @test tile2.errors[13] == 100f0
    end

    @testset "get_mesh on flat terrain" begin
        m = Mesher(5)
        tile = create_tile(m, zeros(Float32, 25))
        mesh = get_mesh(tile; max_error = 0)
        # Flat -> no subdivision: 4 corner vertices, 2 triangles.
        @test size(mesh.vertices) == (2, 4)
        @test size(mesh.triangles) == (3, 2)
        coord_set = Set(eachcol(mesh.vertices))
        @test coord_set == Set([UInt16[0, 0], UInt16[4, 0], UInt16[0, 4], UInt16[4, 4]])
        # Triangle indices are 1-based and refer to existing columns.
        @test all(1 .<= mesh.triangles .<= 4)
    end

    @testset "get_mesh subdivides when error exceeds threshold" begin
        m = Mesher(5)
        terrain = zeros(Float32, 25)
        terrain[13] = 100f0           # spike at center
        tile = create_tile(m, terrain)
        mesh_loose = get_mesh(tile; max_error = 1000)   # threshold above spike
        mesh_tight = get_mesh(tile; max_error = 0)      # threshold below spike
        @test size(mesh_tight.vertices, 2) > size(mesh_loose.vertices, 2)
    end

    @testset "mapbox_terrain_to_grid (fuji)" begin
        terrain = mapbox_terrain_to_grid(joinpath(@__DIR__, "fixtures", "fuji.png"))
        # fuji.png is 512x512 -> grid 513x513
        @test length(terrain) == 513 * 513
        # Heights should sit in a sane terrestrial range (m above sea level).
        @test minimum(terrain) > -500f0
        @test maximum(terrain) < 5000f0    # Mt. Fuji peak ~3776m
    end
end
