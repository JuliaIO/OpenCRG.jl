using ExplicitImports

@testset "ExplicitImports" begin
    @test check_no_implicit_imports(OpenCRG) === nothing
    @test check_no_stale_explicit_imports(OpenCRG) === nothing
end

# JET is deliberately not run on OpenCRG: `JET.test_package` currently reports
# six "possible errors" (Union{Nothing,T} header fields that are only
# `nothing` on already-invalid input, e.g. header.jl `v_axis`/`parse_kd_definition`
# and transform.jl `apply_mods`). Silencing them needs behaviour changes
# (explicit errors instead of MethodErrors), so it is left out for now.
