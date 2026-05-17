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
end
