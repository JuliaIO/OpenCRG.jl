using Test, OpenCRG
const DATA = joinpath(@__DIR__, "data")
include("helpers/LibOpenCRG.jl")

# Scaling modifiers invalidate the header's end anchors in the C reference
# (crgDataSetModifiersApply clears X/Y end after SCALE_LENGTH/SCALE_CURVATURE and
# Z end after SCALE_LENGTH/SCALE_SLOPE). Cross-validate against OpenCRG_jll on
# end-anchored fixtures.

using .LibOpenCRG

function oracle_vs_julia(path, jl_mods, c_mods)
    data = OpenCRG.read_crg(path)
    dm = OpenCRG.CRGData(data.comment, data.refline, data.format_code, data.opts, jl_mods,
                         data.mpro, data.phi, data.banking, data.slope, data.v, data.z)
    u, v, X, Y, Z = OpenCRG.road_surface_grid(dm)
    dsId = crgLoaderReadFile(path)
    @assert dsId != 0
    crgDataSetModifierRemoveAll(dsId)
    for (id, val) in c_mods
        crgDataSetModifierSetDouble(dsId, id, val) != 0 || error("could not set modifier $id")
    end
    crgDataSetModifiersApply(dsId)
    cpId = crgContactPointCreate(dsId)
    compared = 0
    mismatches = 0
    for i in eachindex(u), j in eachindex(v)
        r = crgEvaluv2xy(cpId, u[i], v[j])
        r.status != 0 || continue
        compared += 1
        (isapprox(X[i, j], r.x; atol = 1e-6) && isapprox(Y[i, j], r.y; atol = 1e-6)) || (mismatches += 1)
        rz = crgEvaluv2z(cpId, u[i], v[j])
        if rz.status != 0 && !isnan(rz.z) && !isnan(Z[i, j])
            isapprox(Z[i, j], rz.z; atol = 1e-6) || (mismatches += 1)
        end
    end
    crgContactPointDelete(cpId); crgDataSetRelease(dsId); crgMemRelease()
    return compared, mismatches, OpenCRG.apply_mods(dm).refline
end

@testset "scaling modifiers drop obsolete end anchors (vs C oracle)" begin
    path = joinpath(DATA, "synthetic_end_anchored_2col.crg")
    cases = [
        "SCALE_LENGTH"                   => (OpenCRG.RoadCrgMods(scale_length = 2.0),
                                             [LibOpenCRG.dCrgModScaleLength => 2.0], (:x, :y, :z)),
        "SCALE_CURVATURE"                => (OpenCRG.RoadCrgMods(scale_curvature = 3.0),
                                             [LibOpenCRG.dCrgModScaleCurvature => 3.0], (:x, :y)),
        "SCALE_SLOPE"                    => (OpenCRG.RoadCrgMods(scale_slope = 2.0),
                                             [LibOpenCRG.dCrgModScaleSlope => 2.0], (:z,)),
        "SCALE_LENGTH + SCALE_SLOPE"     => (OpenCRG.RoadCrgMods(scale_length = 0.5, scale_slope = 1.5),
                                             [LibOpenCRG.dCrgModScaleLength => 0.5, LibOpenCRG.dCrgModScaleSlope => 1.5],
                                             (:x, :y, :z)),
        "SCALE_Z_GRID keeps anchors"     => (OpenCRG.RoadCrgMods(scale_z_grid = 2.0),
                                             [LibOpenCRG.dCrgModScaleZ => 2.0], ()),
        "SCALE_WIDTH keeps anchors"      => (OpenCRG.RoadCrgMods(scale_width = 2.0),
                                             [LibOpenCRG.dCrgModScaleWidth => 2.0], ()),
        "SCALE_LENGTH + REFPOINT_X/Y"    => (OpenCRG.RoadCrgMods(scale_length = 2.0, refpoint_x = 5.0, refpoint_y = -3.0),
                                             [LibOpenCRG.dCrgModScaleLength => 2.0,
                                              LibOpenCRG.dCrgModRefPointX => 5.0,
                                              LibOpenCRG.dCrgModRefPointY => -3.0], (:x, :y, :z)),
        "SCALE_CURVATURE + REFLINE_OFFSET" => (OpenCRG.RoadCrgMods(scale_curvature = 2.0, refline_offset_phi = 0.3,
                                                                    refline_offset_x = 1.0, refline_offset_z = 0.2),
                                             [LibOpenCRG.dCrgModScaleCurvature => 2.0,
                                              LibOpenCRG.dCrgModRefLineOffsetPhi => 0.3,
                                              LibOpenCRG.dCrgModRefLineOffsetX => 1.0,
                                              LibOpenCRG.dCrgModRefLineOffsetZ => 0.2], (:x, :y)),
    ]
    for (name, (jl_mods, c_mods, cleared)) in cases
        @testset "$name" begin
            compared, mismatches, rl = oracle_vs_julia(path, jl_mods, c_mods)
            @test compared > 0
            @test mismatches == 0
            @test (rl.end_x === nothing) == (:x in cleared)
            @test (rl.end_y === nothing) == (:y in cleared)
            @test (rl.end_z === nothing) == (:z in cleared)
        end
    end
end
