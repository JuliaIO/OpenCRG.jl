using Test, OpenCRG

@testset "trimmed executable" begin
    if !Sys.islinux()
        @info "Skipping JuliaC trim test: only Linux is currently supported by this test"
        @test_skip false
    elseif Sys.which(get(ENV, "JULIA_CC", "cc")) === nothing
        @info "Skipping JuliaC trim test: no C compiler found"
        @test_skip false
    else
        mktempdir() do dir
            build = `$(Base.julia_cmd()) --startup-file=no --project=$(@__DIR__) -e 'using JuliaC; JuliaC.main(ARGS)' -- --output-exe opencrg-trim --bundle $dir --trim=safe --experimental $(joinpath(@__DIR__, "app.jl"))`
            elapsed = @elapsed run(Cmd(build; dir=dir))
            exe = joinpath(dir, "bin", "opencrg-trim")
            @info "Trimmed executable" build_seconds=elapsed size_bytes=filesize(exe)
            for name in ("handmade_curved_banked_sloped.crg", "belgian_block.crg")
                fixture = joinpath(@__DIR__, "..", "data", name)
                lines = split(strip(read(`$exe $fixture`, String)), '\n')
                u, v, x, y, z = road_surface_grid(read_crg(fixture))
                indices = ((1, 1), (length(u) ÷ 2, length(v) ÷ 2), (length(u), length(v)))
                @test length(lines) == length(indices)
                for (line, (i, j)) in zip(lines, indices)
                    @test isapprox(parse.(Float64, split(line)), [u[i], v[j], x[i,j], y[i,j], z[i,j]]; nans=true)
                end
            end
        end
    end
end
