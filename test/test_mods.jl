using Test, OpenCRG
include("helpers/fixtures.jl")

# Modifiers from a file's $ROAD_CRG_MODS section, observed through
# road_surface_grid. test_crossvalidate.jl checks the same modifiers
# against the C reference.

surface(name, mods::Pair...) = road_surface_grid(read_crg(with_mods(name, mods...)))

@testset "no modifiers section is a no-op" begin
    name = "handmade_curved_banked_sloped.crg"
    @test isequal(road_surface_grid(read_crg(fixture(name))), surface(name))
end

@testset "REFPOINT_X/Y/PHI/Z place the road start" begin
    u, v, X, Y, Z = surface("belgian_block.crg", "REFPOINT_X" => 10.0, "REFPOINT_Y" => 20.0,
                            "REFPOINT_PHI" => 0.5, "REFPOINT_Z" => 42.0)
    j = findfirst(==(0.0), v)
    @test X[1, j] ≈ 10.0
    @test Y[1, j] ≈ 20.0
    @test atan(Y[2, j] - Y[1, j], X[2, j] - X[1, j]) ≈ 0.5 atol = 1e-3
    @test Z[1, j] ≈ 42.0

    # Any REFPOINT_* without REFPOINT_Z moves the start elevation to 0.
    u, v, X, Y, Z = surface("belgian_block.crg", "REFPOINT_X" => 10.0)
    @test Z[1, j] ≈ 0.0 atol = 1e-6
end

@testset "scaling" begin
    name = "handmade_curved_banked_sloped.crg"
    u0, v0, X0, Y0, Z0 = road_surface_grid(read_crg(fixture(name)))

    u, v, X, Y, Z = surface(name, "SCALE_LENGTH" => 1.5)
    @test u ≈ 1.5 .* u0
    @test last(u) ≈ 33.0

    u, v, X, Y, Z = surface(name, "SCALE_WIDTH" => 2.0)
    @test v ≈ 2.0 .* v0
    @test X[:, 4] ≈ X0[:, 4] && Y[:, 4] ≈ Y0[:, 4]   # centre line unchanged

    _, _, _, _, Z0 = road_surface_grid(read_crg(fixture("handmade_curved_minimalist.crg")))
    _, _, _, _, Z = surface("handmade_curved_minimalist.crg", "SCALE_Z_GRID" => 2.0)
    @test Z ≈ 2.0 .* Z0
end

@testset "errors" begin
    # Selecting the reference point by (u, v) is not supported.
    for key in ("REFPOINT_U", "REFPOINT_U_FRACTION", "REFPOINT_V", "REFPOINT_V_FRACTION")
        @test_throws Exception surface("handmade_curved_minimalist.crg", key => 0.5)
    end
    # REFPOINT_* needs a long section exactly at v = 0.
    @test_throws Exception surface("synthetic_hairpin.crg", "REFPOINT_X" => 5.0)
end
