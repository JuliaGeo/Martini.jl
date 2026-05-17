using Test
using Martini

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
end
