using Test
using Aqua
using LibOpenCRG

# The sample .crg files live in the OpenCRG.jl repo root's test/data and are
# deliberately not duplicated here. This works because the registered
# package is tested from a checkout of the repository, where this file sits
# at lib/LibOpenCRG.jl/test/.
const DATA = joinpath(@__DIR__, "..", "..", "..", "test", "data")
const BANKED = joinpath(DATA, "handmade_curved_banked_sloped.crg")
const MINIMAL = joinpath(DATA, "handmade_curved_minimalist.crg")

@testset "LibOpenCRG" begin
    @testset "Aqua" begin
        Aqua.test_all(LibOpenCRG)
    end

    @testset "C layer" begin
        @test occursin("OpenCRG", LibOpenCRG.C.crgGetReleaseInfo())
        ds = LibOpenCRG.C.crgLoaderReadFile(BANKED)
        @test ds > 0
        @test LibOpenCRG.C.crgCheck(ds) != 0
        cp = LibOpenCRG.C.crgContactPointCreate(ds)
        @test cp >= 0
        r = LibOpenCRG.C.crgEvaluv2xy(cp, 10.0, 0.5)
        @test r.status == 1
        @test LibOpenCRG.C.crgContactPointDelete(cp) == 1
        @test LibOpenCRG.C.crgDataSetRelease(ds) == 1
    end

    @testset "loading and metadata" for path in (BANKED, MINIMAL)
        @test isfile(path)
        data = read_crg(path)
        @test data isa CRGData
        @test isopen(data)
        umin, umax = urange(data)
        vmin, vmax = vrange(data)
        du, dv = increments(data)
        @test umax > umin && vmax > vmin
        @test du > 0 && dv > 0
        @test !isclosedtrack(data)
        close(data)
        @test !isopen(data)
        close(data)  # idempotent
        @test_throws ArgumentError uv2xy(data, 1.0, 0.0)
    end

    @testset "errors" begin
        @test_throws ArgumentError read_crg(joinpath(DATA, "does_not_exist.crg"))
    end

    @testset "do-block releases resources" begin
        leaked = Ref{CRGData}()
        z = read_crg(BANKED) do data
            leaked[] = data
            uv2z(data, 10.0, 0.5)
        end
        @test z ≈ 0.5611666503064334 atol = 1e-9
        @test !isopen(leaked[])
        @test_throws ErrorException read_crg(BANKED) do data
            leaked[] = data
            error("boom")
        end
        @test !isopen(leaked[])
    end

    @testset "evaluation" begin
        read_crg(BANKED) do data
            umin, umax = urange(data)
            vmin, vmax = vrange(data)
            for u in range(umin + 1, umax - 1; length = 7), v in range(vmin + 0.2, vmax - 0.2; length = 5)
                x, y = uv2xy(data, u, v)
                @test isfinite(x) && isfinite(y)
                u2, v2 = xy2uv(data, x, y)
                @test u2 ≈ u atol = 1e-6
                @test v2 ≈ v atol = 1e-6

                z = uv2z(data, u, v)
                @test isnan(z) || isapprox(xy2z(data, x, y), z; atol = 1e-6)

                h, k = uv2pk(data, u, v)
                @test isfinite(h) && isfinite(k)
                h2, k2 = xy2pk(data, x, y)
                @test h2 ≈ h atol = 1e-6
                @test k2 ≈ k atol = 1e-6
            end
            # Known values from the reference implementation
            @test all(isapprox.(uv2xy(data, 10.0, 0.5), (9.930611107774567, 0.9918308919767347); atol = 1e-9))
            @test all(isapprox.(uv2pk(data, 10.0, 0.5), (0.099, 0.01106061029784817); atol = 1e-9))
        end
    end

    @testset "road_surface_grid" begin
        read_crg(BANKED) do data
            u, v, X, Y, Z = road_surface_grid(data)
            @test size(X) == size(Y) == size(Z) == (length(u), length(v))
            @test (first(u), last(u)) == urange(data)
            @test first(v) ≈ vrange(data)[1] && last(v) ≈ vrange(data)[2]
            @test count(isnan, X) == 0
            @test any(!isnan, Z)
            i, j = 5, 100
            @test (X[i, j], Y[i, j]) == uv2xy(data, u[i], v[j])
            @test isequal(Z[i, j], uv2z(data, u[i], v[j]))
        end
    end

    @testset "finalizer releases native handles" begin
        # Many loads without explicit close must not exhaust the library.
        for _ in 1:20
            read_crg(MINIMAL)
        end
        GC.gc(); GC.gc()
        @test read_crg(d -> isopen(d), MINIMAL)
    end
end
