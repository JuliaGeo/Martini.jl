using PNGFiles
using ColorTypes: red, green, blue
using FixedPointNumbers: N0f8

"""
    mapbox_terrain_to_grid(png_path::AbstractString) -> Vector{Float32}

Decode a Mapbox RGB terrain PNG into a length `(width+1)^2` heightfield, matching
the reference JS implementation in `martini/test/util.js`.
"""
function mapbox_terrain_to_grid(png_path::AbstractString)
    img = PNGFiles.load(png_path)
    height, width = size(img)
    width == height || error("expected square tile, got $(width)x$(height)")

    tile_size = width
    grid_size = tile_size + 1
    terrain = Vector{Float32}(undef, grid_size * grid_size)

    @inbounds for y in 0:(tile_size - 1)
        for x in 0:(tile_size - 1)
            px = img[y + 1, x + 1]
            r = Int(reinterpret(UInt8, N0f8(red(px))))
            g = Int(reinterpret(UInt8, N0f8(green(px))))
            b = Int(reinterpret(UInt8, N0f8(blue(px))))
            # JS decodes in Float64 then truncates on Float32Array store; the F32
            # pipeline gives ~1 ULP differences that flip subdivision decisions
            # at low max_error thresholds.
            terrain[y * grid_size + x + 1] =
                Float32((r * 65536 + g * 256 + b) / 10.0 - 10000.0)
        end
    end

    # Backfill right + bottom borders (mirror JS lines 19-24).
    for x in 0:(grid_size - 2)
        terrain[(grid_size - 1) * grid_size + x + 1] =
            terrain[(grid_size - 2) * grid_size + x + 1]
    end
    for y in 0:(grid_size - 1)
        terrain[y * grid_size + (grid_size - 1) + 1] =
            terrain[y * grid_size + (grid_size - 2) + 1]
    end
    return terrain
end
