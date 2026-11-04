using Test, OpenCRG
include("helpers/fixtures.jl")
include("helpers/oracle.jl")

# Every node of `road_surface_grid` must agree with the C reference
# implementation (OpenCRG_jll) evaluated at the same (u, v).

@testset "sample files" begin
    for name in ["handmade_curved_minimalist.crg", "handmade_curved_banked_sloped.crg",
                 "synthetic_end_anchored_2col.crg", "synthetic_hairpin.crg", "belgian_block.crg"]
        @testset "$name" begin
            compared, mismatches = oracle_mismatches(fixture(name))
            @test compared > 0
            @test mismatches == 0
        end
    end
end

@testset "\$ROAD_CRG_MODS" begin
    L = LibOpenCRG
    # The Julia side reads the modifiers from a `$ROAD_CRG_MODS` section in the
    # file; the C side gets the same modifiers through its API.
    # (file, [header key => (C modifier id, value)])
    cases = [
        "handmade_curved_minimalist.crg" => ["REFLINE_OFFSET_PHI" => (L.dCrgModRefLineOffsetPhi, 1.57),
                                             "REFLINE_OFFSET_X" => (L.dCrgModRefLineOffsetX, 100.0),
                                             "REFLINE_OFFSET_Y" => (L.dCrgModRefLineOffsetY, 50.0)],
        # REFPOINT_* takes precedence over REFLINE_OFFSET_*/REFLINE_ROTCENTER_*
        "handmade_curved_minimalist.crg" => ["REFPOINT_X" => (L.dCrgModRefPointX, 10.0),
                                             "REFPOINT_Y" => (L.dCrgModRefPointY, 20.0),
                                             "REFPOINT_PHI" => (L.dCrgModRefPointPhi, 0.5),
                                             "REFLINE_OFFSET_X" => (L.dCrgModRefLineOffsetX, 999.0),
                                             "REFLINE_OFFSET_Y" => (L.dCrgModRefLineOffsetY, -999.0),
                                             "REFLINE_OFFSET_PHI" => (L.dCrgModRefLineOffsetPhi, 3.0),
                                             "REFLINE_ROTCENTER_X" => (L.dCrgModRefLineRotCenterX, -500.0),
                                             "REFLINE_ROTCENTER_Y" => (L.dCrgModRefLineRotCenterY, 500.0)],
        # REFPOINT_U_OFFSET/V_OFFSET alone do not select a reference point
        "handmade_curved_minimalist.crg" => ["REFPOINT_U_OFFSET" => (L.dCrgModRefPointUOffset, 5.0),
                                             "REFPOINT_V_OFFSET" => (L.dCrgModRefPointVOffset, 0.3),
                                             "REFLINE_OFFSET_X" => (L.dCrgModRefLineOffsetX, 100.0)],
        "belgian_block.crg" => ["REFPOINT_Z" => (L.dCrgModRefPointZ, 42.0)],
        "belgian_block.crg" => ["SCALE_Z_GRID" => (L.dCrgModScaleZ, 3.0),
                                "REFPOINT_Z" => (L.dCrgModRefPointZ, 42.0)],
        "belgian_block.crg" => ["REFPOINT_X" => (L.dCrgModRefPointX, 10.0)],
        "handmade_curved_banked_sloped.crg" => ["SCALE_Z_GRID" => (L.dCrgModScaleZ, 2.0)],
        "handmade_curved_banked_sloped.crg" => ["SCALE_WIDTH" => (L.dCrgModScaleWidth, 2.0)],
        "handmade_curved_banked_sloped.crg" => ["SCALE_LENGTH" => (L.dCrgModScaleLength, 1.5)],
        "handmade_curved_banked_sloped.crg" => ["SCALE_CURVATURE" => (L.dCrgModScaleCurvature, 1.5)],
        "handmade_curved_banked_sloped.crg" => ["SCALE_SLOPE" => (L.dCrgModScaleSlope, 2.0)],
        "handmade_curved_banked_sloped.crg" => ["SCALE_BANKING" => (L.dCrgModScaleBank, 2.0)],
        # Scaling length, curvature or slope invalidates the end anchors in the header.
        "synthetic_end_anchored_2col.crg" => ["SCALE_LENGTH" => (L.dCrgModScaleLength, 2.0)],
        "synthetic_end_anchored_2col.crg" => ["SCALE_CURVATURE" => (L.dCrgModScaleCurvature, 3.0)],
        "synthetic_end_anchored_2col.crg" => ["SCALE_SLOPE" => (L.dCrgModScaleSlope, 2.0)],
        "synthetic_end_anchored_2col.crg" => ["SCALE_LENGTH" => (L.dCrgModScaleLength, 0.5),
                                              "SCALE_SLOPE" => (L.dCrgModScaleSlope, 1.5)],
        "synthetic_end_anchored_2col.crg" => ["SCALE_LENGTH" => (L.dCrgModScaleLength, 2.0),
                                              "REFPOINT_X" => (L.dCrgModRefPointX, 5.0),
                                              "REFPOINT_Y" => (L.dCrgModRefPointY, -3.0)],
        "synthetic_end_anchored_2col.crg" => ["SCALE_CURVATURE" => (L.dCrgModScaleCurvature, 2.0),
                                              "REFLINE_OFFSET_PHI" => (L.dCrgModRefLineOffsetPhi, 0.3),
                                              "REFLINE_OFFSET_X" => (L.dCrgModRefLineOffsetX, 1.0),
                                              "REFLINE_OFFSET_Z" => (L.dCrgModRefLineOffsetZ, 0.2)],
    ]
    for (name, mods) in cases
        label = name * ": " * join(first.(mods), ", ")
        @testset "$label" begin
            path = with_mods(name, (k => last(m) for (k, m) in mods)...)
            # Sample the large belgian_block grid instead of evaluating every node.
            big = name == "belgian_block.crg"
            compared, mismatches = oracle_mismatches(path, fixture(name); c_mods = last.(mods),
                                                     rows = big ? (1:50:1001) : (:), cols = big ? (1:17:341) : (:))
            @test compared > 0
            @test mismatches == 0
        end
    end
end
