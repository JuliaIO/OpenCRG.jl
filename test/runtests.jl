using Test, SafeTestsets

@testset "OpenCRG.jl" begin
    @safetestset "read" begin include("test_read.jl") end
    @safetestset "surface" begin include("test_surface.jl") end
    @safetestset "mods" begin include("test_mods.jl") end
    @safetestset "crossvalidate" begin include("test_crossvalidate.jl") end
    @safetestset "aqua" begin include("test_aqua.jl") end
    @safetestset "quality" begin include("test_quality.jl") end
    if VERSION >= v"1.12"
        @safetestset "trim" begin include("trim/runtests.jl") end
    end
end
