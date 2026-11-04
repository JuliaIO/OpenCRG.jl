using Test, OpenCRG

@testset "trimmed executable" begin
    mktempdir() do dir
        build = `$(Base.julia_cmd()) --startup-file=no --project=$(@__DIR__) -e 'using JuliaC; JuliaC.main(ARGS)' -- --output-exe opencrg-trim --bundle $dir --trim=safe --experimental $(joinpath(@__DIR__, "app.jl"))`
        elapsed = @elapsed run(Cmd(build; dir=dir))
        exe = joinpath(dir, "bin", Sys.iswindows() ? "opencrg-trim.exe" : "opencrg-trim")
        @info "Trimmed executable" build_seconds=elapsed size_bytes=filesize(exe)
        for name in ("handmade_curved_banked_sloped.crg", "belgian_block.crg", "synthetic_hairpin.crg")
            fixture = joinpath(pkgdir(OpenCRG), "test", "data", name)
            lines = split(strip(replace(read(`$exe $fixture`, String), "\r\n" => "\n")), '\n')
            u, v, x, y, z = road_surface_grid(read_crg(fixture))
            indices = ((1, 1), (length(u) ÷ 2, length(v) ÷ 2), (length(u), length(v)))
            @test length(lines) == length(indices)
            for (line, (i, j)) in zip(lines, indices)
                @test isequal(parse.(Float64, split(line)), [u[i], v[j], x[i,j], y[i,j], z[i,j]])
            end
        end
    end
end
