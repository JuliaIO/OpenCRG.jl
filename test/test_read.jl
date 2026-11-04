using Test, OpenCRG
include("helpers/fixtures.jl")

@testset "sample files" begin
    # name => (format, size(z), extrema(v), has banking, has slope)
    expected = [
        "handmade_curved_minimalist.crg"    => (:LRFI, (23, 7), (-1.5, 1.5), false, false),
        "handmade_curved_banked_sloped.crg" => (:LRFI, (23, 7), (-1.5, 1.5), true, true),
        "synthetic_end_anchored.crg"        => (:LRFI, (5, 1), (0.0, 0.0), false, false),
        "synthetic_end_anchored_2col.crg"   => (:LRFI, (5, 3), (-1.0, 1.0), false, true),
        "synthetic_hairpin.crg"             => (:KDBI, (3, 2), (-1.0, 1.0), false, false),
        "belgian_block.crg"                 => (:KRBI, (1001, 341), (-1.7, 1.7), false, false),
    ]
    for (name, (format, zsize, vext, has_banking, has_slope)) in expected
        @testset "$name" begin
            data = read_crg(fixture(name))
            @test data isa CRGData
            @test data.format_code == format
            @test size(data.z) == zsize
            @test length(data.phi) == zsize[1]
            @test length(data.v) == zsize[2]
            @test issorted(data.v)
            @test extrema(data.v) == vext
            @test (data.banking !== nothing) == has_banking
            @test (data.slope !== nothing) == has_slope
            @test !isempty(data.comment)
        end
    end
end

@testset "sample values" begin
    banked = read_crg(fixture("handmade_curved_banked_sloped.crg"))
    @test banked.phi[1:3] == [0.0, 0.0, 0.011]
    @test banked.z[1, :] == zeros(7)
    @test count(isnan, banked.z) == 3
    @test any(!=(0.0), banked.banking)
    @test any(!=(0.0), banked.slope)

    hairpin = read_crg(fixture("synthetic_hairpin.crg"))
    @test hairpin.phi == [0.0, 0.0, Float64(pi)]   # binary Float64 keeps pi exact

    belgian = read_crg(fixture("belgian_block.crg"))
    @test belgian.v[1:3] ≈ [-1.7, -1.69, -1.68]
    @test belgian.phi[1] == belgian.phi[2] ≈ 2.6527974605560303
    @test all(isnan, belgian.z[1, 1:21])            # missing samples at the road border
    @test belgian.z[1, 23] ≈ 2.12190318107605
    @test belgian.opts == Dict("WARN_CURV_GLOBAL" => 1.0, "WARN_CURV_LOCAL" => 0.0)
end

@testset "LDFI file with index-form channels" begin
    # 20-character fields, 4 per line, so each 5-channel row wraps onto 2 lines.
    field(x) = lpad(x, 20)
    path = tmpcrg("""
        \$CT
        synthetic LDFI file
        \$ROAD_CRG
        REFERENCE_LINE_INCREMENT = 1.0
        LONG_SECTION_V_RIGHT = -1.5
        LONG_SECTION_V_LEFT = 1.5
        \$KD_DEFINITION
        #:LDFI
        D:reference line phi,rad
        D:long section 1,m
        D:long section 2,m
        D:long section 3,m
        D:long section 4,m
        \$\$\$\$
        $(field("0.0"))$(field("0.1"))$(field("0.2"))$(field("1.0D-01"))
        $(field("0.4"))
        $(field("0.0"))$(field("*missing*"))$(field("-2.5"))$(field("3.0"))
        $(field("4.0"))
        """)
    data = read_crg(path)
    @test data.format_code == :LDFI
    @test data.v == [-1.5, -0.5, 0.5, 1.5]
    @test data.z[1, :] == [0.1, 0.2, 0.1, 0.4]
    @test isnan(data.z[2, 1])
    @test data.z[2, 2:4] == [-2.5, 3.0, 4.0]
end

@testset "errors" begin
    @testset "unrecognized format code" begin
        path = edited("handmade_curved_minimalist.crg", "#:LRFI" => "#:UNKNOWN")
        err = try
            read_crg(path)
        catch e
            e
        end
        @test err isa OpenCRG.UnrecognizedFormatError
        @test err.format_code === :UNKNOWN
        @test sprint(showerror, err) == "unrecognized CRG data format code: UNKNOWN"
    end

    @testset "no channels declared" begin
        @test_throws ErrorException read_crg(tmpcrg("\$CT\nno \$KD_DEFINITION at all\n\$\$\$\$\n"))
    end

    @testset "mixed position-form and index-form channels" begin
        path = edited("handmade_curved_minimalist.crg",
                      r"D:long section at v = *-1\.500,m" => "D:long section 1,m")
        @test_throws Exception read_crg(path)
    end

    @testset "truncated ASCII payload" begin
        text = read(fixture("handmade_curved_banked_sloped.crg"), String)
        @test_throws ErrorException read_crg(tmpcrg(text[1:findlast("\n", chomp(text))[1]]))
    end

    @testset "truncated binary payload" begin
        bytes = read(fixture("belgian_block.crg"))
        @test_throws ErrorException read_crg(tmpcrg(bytes[1:end-1000]))
    end
end
