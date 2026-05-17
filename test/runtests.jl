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
        # 1-based corners: max is grid_size=5, "zero" is 1.
        @test m.coords[1:4] == UInt16[5, 5, 1, 1]

        # Triangle 1 (i=1, id=3): bottom-left of the whole tile.
        @test m.coords[5:8] == UInt16[1, 1, 5, 5]
    end

    @testset "Tile / errors" begin
        m = Mesher(5)
        # Length mismatch should be rejected.
        @test_throws ArgumentError create_tile(m, zeros(Float32, 10))

        # Flat terrain -> all errors are 0. terrain/errors are now Matrix-backed.
        flat = zeros(Float32, 25)
        tile = create_tile(m, flat)
        @test size(tile.errors) == (5, 5)
        @test all(tile.errors .== 0)

        # Pointy: spike at the center vertex (1-based (3, 3)).
        # 13th flat element == (x=3, y=3) after reshape(_, 5, 5).
        terrain = zeros(Float32, 25)
        terrain[13] = 100f0
        tile2 = create_tile(m, terrain)
        @test tile2.errors[3, 3] == 100f0
    end

    @testset "get_mesh on flat terrain" begin
        m = Mesher(5)
        tile = create_tile(m, zeros(Float32, 25))
        mesh = get_mesh(tile; max_error = 0)
        # Flat -> no subdivision: 4 corner vertices, 2 triangles.
        @test mesh.vertices isa Vector{Tuple{UInt16, UInt16}}
        @test mesh.triangles isa Vector{Tuple{UInt32, UInt32, UInt32}}
        @test length(mesh.vertices) == 4
        @test length(mesh.triangles) == 2
        # 1-based corners: (1,1) … (5,5)
        @test Set(mesh.vertices) == Set([
            (UInt16(1), UInt16(1)), (UInt16(5), UInt16(1)),
            (UInt16(1), UInt16(5)), (UInt16(5), UInt16(5)),
        ])
        # Triangle indices are 1-based and refer to existing entries.
        @test all(tri -> all(1 .<= tri .<= 4), mesh.triangles)
    end

    @testset "get_mesh subdivides when error exceeds threshold" begin
        m = Mesher(5)
        terrain = zeros(Float32, 25)
        terrain[13] = 100f0           # spike at center
        tile = create_tile(m, terrain)
        mesh_loose = get_mesh(tile; max_error = 1000)   # threshold above spike
        mesh_tight = get_mesh(tile; max_error = 0)      # threshold below spike
        @test length(mesh_tight.vertices) > length(mesh_loose.vertices)
    end

    @testset "mapbox_terrain_to_grid (fuji)" begin
        terrain = mapbox_terrain_to_grid(joinpath(@__DIR__, "fixtures", "fuji.png"))
        # fuji.png is 512x512 -> grid 513x513
        @test length(terrain) == 513 * 513
        # Heights should sit in a sane terrestrial range (m above sea level).
        @test minimum(terrain) > -500f0
        @test maximum(terrain) < 5000f0    # Mt. Fuji peak ~3776m
    end

    @testset "Fuji parity with martini.js getMesh(500)" begin
        terrain = mapbox_terrain_to_grid(joinpath(@__DIR__, "fixtures", "fuji.png"))
        m = Mesher(513)
        tile = create_tile(m, terrain)
        mesh = get_mesh(tile; max_error = 500)

        expected_vertices_0based = UInt16[
            320, 64, 256, 128, 320, 128, 384, 128, 256, 0, 288, 160, 256, 192, 288, 192,
            320, 192, 304, 176, 256, 256, 288, 224, 352, 160, 320, 160, 512, 0, 384, 0,
            128, 128, 128, 0, 64, 64, 64, 0, 0, 0, 32, 32, 192, 192, 384, 384, 512, 256,
            384, 256, 320, 320, 320, 256, 512, 512, 512, 128, 448, 192, 384, 192, 128,
            384, 256, 512, 256, 384, 0, 512, 128, 256, 64, 192, 0, 256, 64, 128, 32, 96,
            0, 128, 32, 64, 16, 48, 0, 64, 0, 32,
        ]
        expected_vertices = expected_vertices_0based .+ UInt16(1)
        expected_triangles_0based = UInt32[
            0, 1, 2, 3, 0, 2, 4, 1, 0, 5, 6, 7, 7, 8, 9, 5, 7, 9, 1, 6, 5, 6, 10, 11, 11,
            8, 7, 6, 11, 7, 12, 2, 13, 8, 12, 13, 3, 2, 12, 2, 1, 5, 13, 5, 9, 8, 13, 9, 2,
            5, 13, 3, 14, 15, 15, 4, 0, 3, 15, 0, 16, 4, 17, 18, 17, 19, 19, 20, 21, 18,
            19, 21, 16, 17, 18, 1, 16, 22, 22, 10, 6, 1, 22, 6, 4, 16, 1, 23, 24, 25, 26,
            25, 27, 10, 26, 27, 23, 25, 26, 28, 24, 23, 29, 3, 30, 24, 29, 30, 14, 3, 29,
            8, 25, 31, 31, 3, 12, 8, 31, 12, 27, 8, 11, 10, 27, 11, 25, 8, 27, 25, 24, 30,
            30, 3, 31, 25, 30, 31, 32, 33, 34, 10, 32, 34, 35, 33, 32, 33, 28, 23, 34, 23,
            26, 10, 34, 26, 33, 23, 34, 36, 16, 37, 38, 36, 37, 36, 10, 22, 16, 36, 22,
            39, 18, 40, 41, 39, 40, 16, 18, 39, 42, 21, 43, 44, 42, 43, 18, 21, 42, 21,
            20, 45, 45, 44, 43, 21, 45, 43, 44, 41, 40, 40, 18, 42, 44, 40, 42, 41, 38,
            37, 37, 16, 39, 41, 37, 39, 38, 35, 32, 32, 10, 36, 38, 32, 36,
        ]
        expected_triangles = expected_triangles_0based .+ UInt32(1)

        expected_vertex_tuples = [
            (expected_vertices[2i-1], expected_vertices[2i])
            for i in 1:(length(expected_vertices) ÷ 2)
        ]
        expected_triangle_tuples = [
            (expected_triangles[3i-2], expected_triangles[3i-1], expected_triangles[3i])
            for i in 1:(length(expected_triangles) ÷ 3)
        ]
        @test mesh.vertices  == expected_vertex_tuples
        @test mesh.triangles == expected_triangle_tuples
    end

    @testset "Tile{Float64}" begin
        m = Mesher(5)
        terrain = zeros(Float64, 25)
        terrain[13] = 100.0
        tile = create_tile(m, terrain)
        @test tile isa Martini.Tile{Float64}
        @test eltype(tile.terrain) == Float64
        @test eltype(tile.errors) == Float64
        @test tile.errors[3, 3] == 100.0
        mesh = get_mesh(tile; max_error = 0)
        @test length(mesh.vertices) > 4
    end

    @testset "GeometryBasics interop" begin
        using GeometryBasics
        m = Mesher(5)
        tile = create_tile(m, zeros(Float32, 25))
        mesh = get_mesh(tile;
            point_type = Point2{UInt16},
            face_type  = GLTriangleFace,
        )
        @test mesh.vertices isa Vector{Point2{UInt16}}
        @test mesh.triangles isa Vector{GLTriangleFace}
        @test length(mesh.vertices) == 4
        @test length(mesh.triangles) == 2
        # GLTriangleFace stores via OffsetInteger{-1, UInt32}, so 1-based input
        # becomes 0-based GL-ready bytes. Verify via reinterpret.
        flat = reinterpret(UInt32, mesh.triangles)
        @test all(0 .<= flat .<= 3)
        @test sort(unique(flat)) == UInt32[0, 1, 2, 3]
    end

    @testset "MesherCache reuse" begin
        m = Mesher(5)
        tile = create_tile(m, zeros(Float32, 25))
        cache = MesherCache(m)
        mesh1 = get_mesh(tile; max_error = 0, cache)
        mesh2 = get_mesh(tile; max_error = 0, cache)
        @test mesh1.vertices == mesh2.vertices
        @test mesh1.triangles == mesh2.triangles

        # Size mismatch should error before mutating anything.
        bad = MesherCache(9)
        @test_throws ArgumentError get_mesh(tile; cache = bad)
    end
end
