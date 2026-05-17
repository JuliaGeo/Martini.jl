# Martini.jl vs Martini.js — bench comparison

Hardware: Apple Silicon. Fixture: `test/fixtures/fuji.png` (512×512 → 513-grid).
Both runs single-threaded.

- **Julia**: Julia 1.12, Chairmarks `@b` median across many samples (steady-state).
- **JS**: Node v26.0.0, `console.time` single-call (V8 warms up across the sweep).

Mesh output: identical (9704 vertices, 19086 triangles at `max_error=30`).

## Headline operations

| op                 | JS (console.time) | Julia (Chairmarks median) | Julia (single-shot)¹ | speedup vs JS |
|--------------------|-------------------|---------------------------|----------------------|---------------|
| `Mesher(513)`      | 19.704 ms         | 3.715 ms                  | 3.806 ms             | **5.3×**      |
| `create_tile`      | 3.179 ms          | 1.267 ms                  | 1.425 ms             | **2.5×**      |
| `get_mesh(30)`     | 1.210 ms          | 0.181 ms                  | 0.425 ms             | **6.7×** (median) / 2.8× (single) |
| 21-mesh sweep total³ | 89.134 ms²        | 37.108 ms                 | —                    | **2.4×**      |

¹ Julia "single-shot" timings exclude method-compilation cost by running each operation once after a warm-up call. Comparable to JS `console.time` after V8 has compiled the hot path.

² JS bench reports `20 meshes total` for the loop `i = 0…20` — that's 21 iterations; the JS label is misleading.

³ Julia sweep reuses a single `MesherCache` across all 21 calls (saves the per-call `Matrix{UInt32}` allocation). See `bench/bench.jl`.

## max_error sweep, side-by-side

| max_error | JS     | Julia median | Julia/JS |
|----------:|-------:|-------------:|---------:|
|         0 | 13.492 |        3.707 |    0.27× |
|         1 | 10.526 |        4.281 |    0.41× |
|         2 |  9.418 |        4.315 |    0.46× |
|         3 |  7.965 |        3.661 |    0.46× |
|         4 |  6.724 |        3.208 |    0.48× |
|         5 |  5.584 |        2.607 |    0.47× |
|         6 |  4.726 |        2.196 |    0.46× |
|         7 |  4.065 |        1.833 |    0.45× |
|         8 |  3.521 |        1.616 |    0.46× |
|         9 |  3.121 |        1.430 |    0.46× |
|        10 |  2.755 |        1.277 |    0.46× |
|        11 |  2.487 |        1.120 |    0.45× |
|        12 |  2.263 |        1.015 |    0.45× |
|        13 |  2.013 |        0.931 |    0.46× |
|        14 |  1.843 |        0.798 |    0.43× |
|        15 |  1.695 |        0.687 |    0.41× |
|        16 |  1.529 |        0.632 |    0.41× |
|        17 |  1.415 |        0.564 |    0.40× |
|        18 |  1.291 |        0.509 |    0.39× |
|        19 |  1.193 |        0.477 |    0.40× |
|        20 |  1.113 |        0.417 |    0.37× |

Julia is **2–3× faster across the sweep**, holding roughly steady. The JS times trend slightly faster (relative to Julia) at low `max_error` because JS allocates more there and the V8 optimiser has more loop iterations to specialise; Julia's lead grows as the mesh shrinks.

## Reproducing

```bash
# Julia
cd Martini.jl
julia --project=bench bench/bench.jl

# JS (in the upstream repo)
cd martini
npm install
node bench.js
```

## Numerical parity

After the F64-intermediates fix in `_update_errors!` and `mapbox_terrain_to_grid`,
Julia produces byte-identical vertex and triangle arrays as JS for every
`max_error` tested (10, 30, 100, 500, 1000). Both render the same mesh.
