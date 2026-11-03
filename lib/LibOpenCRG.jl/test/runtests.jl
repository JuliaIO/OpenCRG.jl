using Test
using Aqua
using LibOpenCRG

# Sample files copied from the upstream asam-ev/OpenCRG project (Apache-2.0);
# see test/data/README.md. Kept inside this subpackage so the tests also work
# when LibOpenCRG is tested on its own.
const DATA = joinpath(@__DIR__, "data")
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

    @testset "finalizer never touches the library while it is locked" begin
        d = read_crg(MINIMAL)
        held = Base.Event(); done = Base.Event()
        holder = Threads.@spawn lock(LibOpenCRG.LOCK) do
            notify(held); wait(done)
        end
        wait(held)
        LibOpenCRG._finalize!(d)       # lock busy elsewhere: must not release
        @test isopen(d)
        notify(done); wait(holder)
        LibOpenCRG._finalize!(d)       # lock free: releases
        @test !isopen(d)
        LibOpenCRG._finalize!(d)       # idempotent
        close(d)
        @test !isopen(d)
    end

    @testset "finalizers are safe under concurrent evaluation" begin
        # Finalizers run on whichever thread triggers GC, while other tasks may
        # be inside the (non-thread-safe) C library. Churn handles and GC while
        # other tasks evaluate a long-lived road; results must stay correct and
        # no handle may be lost or double-freed.
        shared = read_crg(BANKED)
        zref = uv2z(shared, 10.0, 0.5)
        xyref = uv2xy(shared, 10.0, 0.5)
        stop = Threads.Atomic{Bool}(false)
        nworkers = max(2, Threads.nthreads())
        workers = [Threads.@spawn(begin
            ok = true
            n = 0
            while true   # at least one evaluation, even if the churn loop finishes first
                ok &= uv2z(shared, 10.0, 0.5) == zref
                ok &= uv2xy(shared, 10.0, 0.5) == xyref
                n += 1
                stop[] && break
                yield()
            end
            (ok, n)
        end) for _ in 1:nworkers]
        for i in 1:400
            read_crg(i % 2 == 0 ? MINIMAL : BANKED)   # dropped without close
            i % 25 == 0 && GC.gc()
            i % 5 == 0 && yield()
        end
        # explicit close racing with the finalizer of an abandoned handle
        for _ in 1:50
            d = read_crg(MINIMAL)
            close(d)
            close(d)
            GC.gc()
        end
        stop[] = true
        results = fetch.(workers)
        @test all(first, results)
        @test all(r -> r[2] > 0, results)
        GC.gc(); GC.gc()
        @test uv2z(shared, 10.0, 0.5) == zref
        # abandoned handles must still be reclaimable: loading keeps working
        for _ in 1:3
            GC.gc()
            @test read_crg(d -> isopen(d), MINIMAL)
        end
        close(shared)
    end
end
