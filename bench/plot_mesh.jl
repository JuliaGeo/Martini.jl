# End-to-end visual: load fuji.png, build a Martini mesh, convert directly to
# a GeometryBasics.Mesh, and plot with CairoMakie. Demonstrates that the
# Martini output (vertices::Vector{Point2{Float32}}, triangles::Vector{GLTriangleFace})
# plugs into the GeometryBasics → Makie pipeline with no per-element conversion.
#
# Run with:
#   julia --project=bench bench/plot_mesh.jl

using Martini
using GeometryBasics
using CairoMakie
using Printf

include(joinpath(@__DIR__, "..", "test", "util.jl"))

const FIXTURE = joinpath(@__DIR__, "..", "test", "fixtures", "fuji.png")
const OUT_PNG = joinpath(@__DIR__, "fuji_mesh.png")
const MAX_ERROR = 30f0          # metres

terrain_flat = mapbox_terrain_to_grid(FIXTURE)
gs = isqrt(length(terrain_flat))
@assert gs * gs == length(terrain_flat)
terrain = reshape(terrain_flat, gs, gs)

m = Mesher(gs)
tile = create_tile(m, terrain)
mesh = get_mesh(tile;
    max_error  = MAX_ERROR,
    point_type = Point2{Float32},
    face_type  = GLTriangleFace,
)
@printf "Martini mesh: %d vertices, %d triangles at max_error=%.0fm\n" length(mesh.vertices) length(mesh.triangles) MAX_ERROR

# Lift to 3D using terrain elevation; vertices are 1-based (x, y) grid coords.
elevs   = [terrain[Int(v[1]), Int(v[2])] for v in mesh.vertices]
verts3d = [Point3{Float32}(v[1], v[2], e) for (v, e) in zip(mesh.vertices, elevs)]

# Direct conversion: Martini's output fields are exactly what GeometryBasics expects.
mesh2d = GeometryBasics.Mesh(mesh.vertices, mesh.triangles)
mesh3d = GeometryBasics.Mesh(verts3d,        mesh.triangles)

fig = Figure(size = (1600, 720))

ax1 = Axis(fig[1, 1];
    aspect = DataAspect(),
    title = @sprintf("RTIN triangulation (max_error = %.0f m)\n%d vertices, %d triangles",
                     MAX_ERROR, length(mesh.vertices), length(mesh.triangles)),
    xlabel = "x (grid)", ylabel = "y (grid)",
)
mesh!(ax1, mesh2d; color = elevs, colormap = :terrain, shading = NoShading)
wireframe!(ax1, mesh2d; color = (:black, 0.35), linewidth = 0.25)

ax2 = Axis3(fig[1, 2];
    title = "3D mesh, elevation as z (vertical exaggeration ≈ 2×)",
    aspect = (1, 1, 0.5),
    azimuth = 0.4π, elevation = 0.18π,
    xlabel = "x", ylabel = "y", zlabel = "z (m)",
)
mesh!(ax2, mesh3d; color = elevs, colormap = :terrain, shading = NoShading)

Colorbar(fig[1, 3]; limits = extrema(elevs), colormap = :terrain, label = "elevation (m)")

save(OUT_PNG, fig)
println("Saved: ", OUT_PNG)
