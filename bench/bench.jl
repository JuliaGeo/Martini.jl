# Parity benchmark for Martini.jl, mirroring martini/bench.js.
# Run with:
#   julia --project=bench bench/bench.jl
using Chairmarks
using Martini
using Printf

include(joinpath(@__DIR__, "..", "test", "util.jl"))

const FIXTURE = joinpath(@__DIR__, "..", "test", "fixtures", "fuji.png")

format_ms(r::Chairmarks.Sample) = @sprintf("%7.3f ms", r.time * 1e3)
format_ms(t::Real)              = @sprintf("%7.3f ms", t * 1e3)

terrain = mapbox_terrain_to_grid(FIXTURE)
grid_size = isqrt(length(terrain))      # 513 for fuji
@assert grid_size * grid_size == length(terrain)

println("== Martini.jl bench (Chairmarks) — fuji.png ($(grid_size)×$(grid_size)) ==\n")

# 1) Mesher construction (precomputes triangle coords).
res_init = @b Mesher($grid_size)
println("init tileset        : ", format_ms(res_init))

# 2) create_tile (heightfield -> Tile with error map).
m = Mesher(grid_size)
res_tile = @b create_tile($m, $terrain)
println("create tile         : ", format_ms(res_tile))

# 3) get_mesh at max_error=30 — the JS bench's headline number.
tile = create_tile(m, terrain)
res_mesh30 = @b get_mesh($tile; max_error = 30)
println("mesh (max_error=30) : ", format_ms(res_mesh30))

mesh30 = get_mesh(tile; max_error = 30)
@printf "  vertices=%d triangles=%d\n\n" length(mesh30.vertices) length(mesh30.triangles)

# 4) Sweep max_error 0..20 with a reused MesherCache.
println("== max_error sweep (Chairmarks median, per get_mesh; cache reused) ==")
function sweep!(tile, cache)
    total_s = 0.0
    for e in 0:20
        r = @b get_mesh($tile; max_error = $e, cache = $cache)
        total_s += r.time
        @printf "mesh %2d : %s\n" e format_ms(r)
    end
    return total_s
end
sweep_cache = MesherCache(m)
sweep_total_s = sweep!(tile, sweep_cache)
@printf "\n21 meshes total (sum of medians): %s\n" format_ms(sweep_total_s)

# 5) First-call latency — what JS console.time would see including JIT.
println("\n== Single-shot timings (one call each, post-warmup) ==")
let m2 = Mesher(grid_size)
    GC.gc()
    t0 = time_ns(); Mesher(grid_size);                t1 = time_ns()
    GC.gc()
    t2 = time_ns(); tile2 = create_tile(m2, terrain); t3 = time_ns()
    GC.gc()
    t4 = time_ns(); get_mesh(tile2; max_error = 30);  t5 = time_ns()
    @printf "init tileset : %s\n"  format_ms((t1 - t0) / 1e9)
    @printf "create tile  : %s\n"  format_ms((t3 - t2) / 1e9)
    @printf "mesh(30)     : %s\n"  format_ms((t5 - t4) / 1e9)
end
