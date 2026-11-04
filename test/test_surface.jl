using Test, OpenCRG
include("helpers/fixtures.jl")

@testset "grid shape and axes" begin
    for name in ("handmade_curved_minimalist.crg", "handmade_curved_banked_sloped.crg",
                 "synthetic_end_anchored_2col.crg", "synthetic_hairpin.crg", "belgian_block.crg")
        @testset "$name" begin
            data = read_crg(fixture(name))
            u, v, X, Y, Z = road_surface_grid(data)
            @test size(X) == size(Y) == size(Z) == (length(u), length(v)) == size(data.z)
            @test v == data.v
            @test issorted(u) && allunique(u)
            @test all(isfinite, X) && all(isfinite, Y)
        end
    end
    u, = road_surface_grid(read_crg(fixture("belgian_block.crg")))
    @test (first(u), last(u)) == (730.0, 740.0)
end

@testset "curved road" begin
    u, v, X, Y, Z = road_surface_grid(read_crg(fixture("handmade_curved_minimalist.crg")))
    @test u == 0.0:1.0:22.0
    @test X[1, :] == zeros(7)          # starts at the origin heading along +x...
    @test Y[1, :] == v                 # ...so the first cross-section lies along +y
    @test X[end, end] ≈ 21.95344589863713
    @test Y[end, end] ≈ 2.7086585009283226
    @test Z[12, 4] ≈ 0.0222222

    # Same reference line, plus banking and slope: identical plan view, different heights.
    ub, vb, Xb, Yb, Zb = road_surface_grid(read_crg(fixture("handmade_curved_banked_sloped.crg")))
    @test Xb == X && Yb == Y
    @test Zb[12, 4] ≈ 0.6272222
    @test Zb[end, end] ≈ 1.21
end

@testset "REFERENCE_LINE_START_Z lifts a flat road" begin
    name = "handmade_curved_minimalist.crg"
    _, _, _, _, Z0 = road_surface_grid(read_crg(fixture(name)))
    path = edited(name, "REFERENCE_LINE_INCREMENT = 1.0" => "REFERENCE_LINE_INCREMENT = 1.0\nREFERENCE_LINE_START_Z = 5.0")
    _, _, _, _, Z = road_surface_grid(read_crg(path))
    @test Z ≈ Z0 .+ 5.0
end

@testset "end-anchored reference line" begin
    # 1-column file: integrating phi = 0 alone would end at x = 4; the declared
    # end point x = 4.4 is reached by blending in the error along the way.
    u, v, X, Y, Z = road_surface_grid(read_crg(fixture("synthetic_end_anchored.crg")))
    @test X[:, 1] ≈ [0.0, 1.1, 2.25, 3.3625, 4.4] atol = 1e-12
    @test all(iszero, Y)

    # End position and end elevation are both hit exactly on the centre line.
    data = read_crg(fixture("synthetic_end_anchored_2col.crg"))
    u, v, X, Y, Z = road_surface_grid(data)
    @test v[2] == 0.0
    @test X[end, 2] ≈ 4.3
    @test Y[end, 2] ≈ 0.35
    @test Z[end, 2] - data.z[end, 2] ≈ 0.5
end

@testset "exactly one of END_X/END_Y is an error" begin
    msg = "REFERENCE_LINE_END_X/END_Y must both be set or both be absent, not just one"
    for drop in (r"REFERENCE_LINE_END_Y.*\n", r"REFERENCE_LINE_END_X.*\n")
        path = edited("synthetic_end_anchored.crg", drop => "")
        @test_throws ErrorException(msg) road_surface_grid(read_crg(path))
    end
end

@testset "hairpin collapses onto the reference line" begin
    # At an exact 180° turn the lateral direction is undefined; like the C
    # reference, every v maps to the reference line point itself.
    u, v, X, Y, Z = road_surface_grid(read_crg(fixture("synthetic_hairpin.crg")))
    @test X[2, :] ≈ [1.0, 1.0]
    @test Y[2, :] ≈ [0.0, 0.0] atol = 1e-12
    @test X[3, :] ≈ [0.0, 0.0] atol = 1e-12
    @test Y[3, :] ≈ [1.0, -1.0]
end
