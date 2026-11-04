using Test, OpenCRG

const DATA = joinpath(@__DIR__, "data")

# Build variants without mutating a parsed fixture shared by other checks.
function display_data(d; comment = d.comment, refline = d.refline, mods = d.mods,
        opts = d.opts, phi = d.phi, banking = d.banking, slope = d.slope,
        v = d.v, z = d.z)
    return CRGData(comment, refline, d.format_code, opts, mods, d.mpro,
        phi, banking, slope, v, z)
end

@testset "CRGData display" begin
    d = read_crg(joinpath(DATA, "handmade_curved_banked_sloped.crg"))
    one = sprint(show, d)
    @test startswith(one, "CRGData(")
    @test occursin("CRG file example", one)
    @test occursin("23×7 grid", one)
    @test occursin("u ∈ [0.0, 22.0] m", one)
    @test !occursin('\n', one)

    plain = sprint(show, MIME"text/plain"(), d)
    for text in ("23 × 7 points (u × v)", "u: [0.0, 22.0] m; increment: 1.0 m",
            "v: [-1.5, 1.5] m; increment: nonuniform", "reference-line x/y",
            "phi", "elevation z", "banking", "slope", "z range (raw):",
            "closed (coincident endpoints): no", "Modifiers: none", "Options: none",
            "Comment:")
        @test occursin(text, plain)
    end
    @test length(split(plain, '\n')) <= 10
    @test !occursin("Matrix", plain)
    @test !occursin("Vector", plain)
    @test sprint(show, MIME"text/plain"(), d; context = :compact => true) ==
        sprint(show, d; context = :compact => true)

    # Unicode, escaping, multiline comments and IOContext truncation.
    verbose = display_data(d; comment = "  道路 \"name\" \\ " * repeat("α", 200) * "\nSECRET_SECOND_LINE")
    limited = sprint(show, verbose; context = :limit => true)
    unlimited = sprint(show, verbose; context = :limit => false)
    @test occursin("道路", limited)
    @test occursin("\\\"name\\\"", limited)
    @test occursin('…', limited)
    @test length(limited) < length(unlimited)
    @test !occursin("SECRET_SECOND_LINE", unlimited)
    @test length(sprint(show, MIME"text/plain"(), verbose; context = :limit => true)) <
        length(sprint(show, MIME"text/plain"(), verbose; context = :limit => false))

    # Missing header end_u must not obscure the payload-derived extent.
    minimal = read_crg(joinpath(DATA, "handmade_curved_minimalist.crg"))
    @test occursin("u ∈ [0.0, 22.0]", sprint(show, minimal))
    short = display_data(minimal; phi = [0.0, 0.0, 0.0], v = [-1.0, 0.0, 1.0],
        z = [NaN -10.0 100.0; 0.0 12.34567 1.0; 2.0 3.0 4.0])
    summary = sprint(show, MIME"text/plain"(), short)
    @test occursin("v: [-1.0, 1.0] m; increment: 1.0 m", summary)
    @test occursin("z range (raw): [-10.0, 100.0] m", summary)
    @test !occursin("12.34567", summary) # no interior array entries
    @test !occursin("; banking", summary)
    @test !occursin("; slope", summary)
    @test occursin("no defined cells", sprint(show, MIME"text/plain"(),
        display_data(short; z = fill(NaN, 3, 3))))

    # Endpoint integration handles an actual closed polygon without grids.
    closed = display_data(short; phi = [0.0, 0.0, π/2, π, 3π/2], z = zeros(5, 3))
    @test occursin("closed (coincident endpoints): yes", sprint(show, MIME"text/plain"(), closed))
    empty_data = display_data(short; phi = Float64[], v = Float64[], z = zeros(0, 0))
    empty_summary = sprint(show, MIME"text/plain"(), empty_data)
    @test occursin("0 × 0 points", empty_summary)
    @test occursin("v: empty", empty_summary)
    @test occursin("closed (coincident endpoints): unknown", empty_summary)

    mods = OpenCRG.RoadCrgMods(scale_z_grid = 2.0, grid_nan_mode = 0,
        scale_width = 1.5, scale_length = 3.0, scale_slope = 2.5, refpoint_x = 1.0)
    settings = display_data(short; mods, opts = Dict("BORDER_MODE_U" => 1.0))
    full = sprint(show, MIME"text/plain"(), settings; context = :limit => false)
    @test occursin("scale_z_grid=2.0", full)
    @test occursin("grid_nan_mode=0", full) # integer-valued modifier
    @test occursin("refpoint_x=1.0", full)
    @test occursin("BORDER_MODE_U", full)
    @test occursin('…', sprint(show, MIME"text/plain"(), settings; context = :limit => true))
    many_options = display_data(short; opts = Dict("OPTION_$i" => Float64(i) for i in 1:8))
    @test occursin('…', sprint(show, MIME"text/plain"(), many_options; context = :limit => true))

    # Concrete helper results guard the inference needed by trimmed callers.
    @test (@inferred OpenCRG._show_u_end(d)) == 22.0
    io = IOBuffer()
    @test (@inferred show(io, d)) === nothing
    @test (@inferred show(io, MIME"text/plain"(), d)) === nothing
end
