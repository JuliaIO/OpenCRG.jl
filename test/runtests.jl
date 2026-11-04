using Test, SafeTestsets

@testset "OpenCRG.jl" begin
    @safetestset "header" begin include("test_header.jl") end
    @safetestset "kddef" begin include("test_kddef.jl") end
    @safetestset "mods" begin include("test_mods.jl") end
    @safetestset "payload" begin include("test_payload.jl") end
    @safetestset "read" begin include("test_read.jl") end
    @safetestset "transform" begin include("test_transform.jl") end
    @safetestset "aqua" begin include("test_aqua.jl") end
    @safetestset "quality" begin include("test_quality.jl") end
    @safetestset "oracle_mods" begin include("test_oracle_mods.jl") end
    @safetestset "oracle_scale_anchors" begin include("test_oracle_scale_anchors.jl") end
    @safetestset "crossvalidate" begin include("test_crossvalidate.jl") end
    if VERSION >= v"1.12"
        @safetestset "trim" begin include("trim/runtests.jl") end
    end
end
