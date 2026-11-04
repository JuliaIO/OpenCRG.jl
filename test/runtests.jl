using Test
using OpenCRG

const DATA = joinpath(@__DIR__, "data")

include("helpers/LibOpenCRG.jl")

@testset "OpenCRG.jl" begin
    include("test_header.jl")
    include("test_kddef.jl")
    include("test_mods.jl")
    include("test_payload.jl")
    include("test_read.jl")
    include("test_transform.jl")
    include("test_aqua.jl")
    include("test_quality.jl")

    # Cross-validation against the upstream C reference implementation
    # (OpenCRG_jll), through a small ccall wrapper kept in test/helpers.
    include("test_oracle_mods.jl")
    include("test_oracle_scale_anchors.jl")
    include("test_crossvalidate.jl")
end

if VERSION >= v"1.12"
    mktempdir() do trim_project
        trim_source = joinpath(pkgdir(OpenCRG), "test", "trim")
        project = read(joinpath(trim_source, "Project.toml"), String)
        patched = replace(project, "path = \"../..\"" => "path = $(repr(pkgdir(OpenCRG)))")
        @assert patched != project "failed to rewrite OpenCRG [sources] path in test/trim/Project.toml"
        project = patched
        write(joinpath(trim_project, "Project.toml"), project)
        for file in ("app.jl", "runtests.jl")
            cp(joinpath(trim_source, file), joinpath(trim_project, file))
        end
        load_path = join(("@", "@stdlib"), Sys.iswindows() ? ';' : ':')
        run(addenv(`$(Base.julia_cmd()) --startup-file=no --project=$trim_project -e 'using Pkg; Pkg.instantiate()'`, "JULIA_LOAD_PATH" => load_path))
        run(addenv(`$(Base.julia_cmd()) --startup-file=no --project=$trim_project $(joinpath(trim_project, "runtests.jl"))`, "JULIA_LOAD_PATH" => load_path))
    end
end
