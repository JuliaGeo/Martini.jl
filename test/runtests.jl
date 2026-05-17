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
end
