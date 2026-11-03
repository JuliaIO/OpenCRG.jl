# Cross-validation against the upstream C reference implementation (OpenCRG_jll).

using .LibOpenCRG

@testset "apply_mods" begin
    @testset "no mods: identity (road_surface_grid unaffected)" begin
        data = OpenCRG.read_crg(joinpath(DATA, "handmade_curved_minimalist.crg"))
        d2 = OpenCRG.apply_mods(data)
        @test d2.phi == data.phi
        @test d2.refline.start_x == data.refline.start_x
    end

    @testset "REFLINE_OFFSET_*: rotate then translate, cross-validated against LibOpenCRG" begin
        path = joinpath(DATA, "handmade_curved_minimalist.crg")
        data = OpenCRG.read_crg(path)
        mods = OpenCRG.RoadCrgMods(refline_offset_phi=1.57, refline_offset_x=100.0, refline_offset_y=50.0)
        data_with_mods = OpenCRG.CRGData(data.comment, data.refline, data.format_code, data.opts, mods,
                                          data.mpro, data.phi, data.banking, data.slope, data.v, data.z)
        u, v, X, Y, Z = OpenCRG.road_surface_grid(data_with_mods)

        dsId = crgLoaderReadFile(path)
        # crgLoaderReadFile seeds dCrgModRefPointX/Y/Z/Phi defaults (via
        # crgOptionSetDefaultModifiers), and crgDataApplyTransformations checks
        # for ANY dCrgModRefPoint* entry BEFORE dCrgModRefLineOffset*, silently
        # short-circuiting the offset modifiers below if not cleared first --
        # this exact bug was found and fixed in Task 15's own test; see the
        # crgDataSetModifiersApply docstring in test/helpers/LibOpenCRG.jl.
        @test crgDataSetModifierRemoveAll(dsId) != 0
        @test crgDataSetModifierSetDouble(dsId, LibOpenCRG.dCrgModRefLineOffsetPhi, 1.57) != 0
        @test crgDataSetModifierSetDouble(dsId, LibOpenCRG.dCrgModRefLineOffsetX, 100.0) != 0
        @test crgDataSetModifierSetDouble(dsId, LibOpenCRG.dCrgModRefLineOffsetY, 50.0) != 0
        crgDataSetModifiersApply(dsId)
        cpId = crgContactPointCreate(dsId)
        for i in eachindex(u), j in eachindex(v)
            ref = crgEvaluv2xy(cpId, u[i], v[j])
            @test ref.status != 0
            @test X[i,j] ≈ ref.x atol=1e-6
            @test Y[i,j] ≈ ref.y atol=1e-6
        end
        crgContactPointDelete(cpId); crgDataSetRelease(dsId); crgMemRelease()
    end

    @testset "REFPOINT_* overrides REFLINE_OFFSET_*/REFLINE_ROTCENTER_* entirely, cross-validated" begin
        # apply_mods's docstring claims REFPOINT_* (if ANY such field is set)
        # takes over the rotate+translate step entirely, ignoring
        # REFLINE_OFFSET_*/REFLINE_ROTCENTER_* completely -- matching
        # `crgDataApplyTransformations` in crgMgr.c, where `applyXform` is set
        # by any of the `dCrgModRefPoint{X,Y,Z,Phi,U,UFrac,V,VFrac}` checks, and
        # the WHOLE REFLINE_OFFSET_*/ROTCENTER_* block only runs `if (!applyXform)`.
        # No test anywhere in this package actually exercised a REFPOINT_* field
        # before this one -- confirmed by reading crgDataApplyTransformations
        # directly (`crgMgr.c` in asam-ev/OpenCRG, ~lines 804-922), then
        # closed here with a real cross-validation: refline_offset_*/rotcenter_*
        # are set to deliberately wild, easy-to-notice values (999.0, -999.0,
        # a 3.0 rad rotation, rotcenter far from the line) alongside a
        # refpoint_x/y/phi -- if has_refpoint's short-circuit were broken (e.g.
        # composing both instead of ignoring one), the result would be wildly
        # off from the C oracle, not subtly off.
        path = joinpath(DATA, "handmade_curved_minimalist.crg")
        data = OpenCRG.read_crg(path)
        mods = OpenCRG.RoadCrgMods(
            refpoint_x=10.0, refpoint_y=20.0, refpoint_phi=0.5,
            refline_offset_x=999.0, refline_offset_y=-999.0, refline_offset_phi=3.0,
            refline_rotcenter_x=-500.0, refline_rotcenter_y=500.0,
        )
        data_with_mods = OpenCRG.CRGData(data.comment, data.refline, data.format_code, data.opts, mods,
                                          data.mpro, data.phi, data.banking, data.slope, data.v, data.z)
        u, v, X, Y, Z = OpenCRG.road_surface_grid(data_with_mods)
        # refpoint_u/refpoint_u_fraction/refpoint_v/refpoint_v_fraction are all
        # unset, so the "from" point defaults to (u,v) = (start_u, 0) on BOTH
        # sides, matching crgDataApplyTransformations's own default (`uPos =
        # crgData->channelU.info.first; vPos = 0.0;`) -- so the reference line's
        # start point should land exactly on (refpoint_x, refpoint_y) with
        # heading refpoint_phi.
        d2 = OpenCRG.apply_mods(data_with_mods)
        @test d2.refline.start_x ≈ 10.0
        @test d2.refline.start_y ≈ 20.0
        @test d2.refline.start_phi ≈ 0.5
        # refpoint_z is UNSET here -- per apply_mods's docstring (Task 16+17
        # review fix), this still shifts elevation, targeting 0.0 by default
        # (mirroring refpoint_x/y's own "unset -> target 0.0" behavior), not
        # leaving it untouched. This fixture's z-grid happens to be exactly
        # 0.0 at (start_u, v=0) (confirmed by direct inspection), so this
        # particular assertion can't distinguish "shifted to 0.0" from "left
        # alone" -- it's the "REFPOINT_Z" testset below (using belgian_block.crg,
        # whose z-grid is NOT zero at the anchor) that actually exercises the
        # shift amount; this assertion is regression protection for the
        # mechanism itself (no error, no NaN, doesn't silently corrupt Z).
        @test d2.refline.start_z ≈ 0.0

        dsId = crgLoaderReadFile(path)
        @test crgDataSetModifierRemoveAll(dsId) != 0
        @test crgDataSetModifierSetDouble(dsId, LibOpenCRG.dCrgModRefPointX, 10.0) != 0
        @test crgDataSetModifierSetDouble(dsId, LibOpenCRG.dCrgModRefPointY, 20.0) != 0
        @test crgDataSetModifierSetDouble(dsId, LibOpenCRG.dCrgModRefPointPhi, 0.5) != 0
        @test crgDataSetModifierSetDouble(dsId, LibOpenCRG.dCrgModRefLineOffsetX, 999.0) != 0
        @test crgDataSetModifierSetDouble(dsId, LibOpenCRG.dCrgModRefLineOffsetY, -999.0) != 0
        @test crgDataSetModifierSetDouble(dsId, LibOpenCRG.dCrgModRefLineOffsetPhi, 3.0) != 0
        @test crgDataSetModifierSetDouble(dsId, LibOpenCRG.dCrgModRefLineRotCenterX, -500.0) != 0
        @test crgDataSetModifierSetDouble(dsId, LibOpenCRG.dCrgModRefLineRotCenterY, 500.0) != 0
        crgDataSetModifiersApply(dsId)
        cpId = crgContactPointCreate(dsId)
        for i in eachindex(u), j in eachindex(v)
            ref = crgEvaluv2xy(cpId, u[i], v[j])
            @test ref.status != 0
            @test X[i,j] ≈ ref.x atol=1e-6
            @test Y[i,j] ≈ ref.y atol=1e-6
            ref_z = crgEvaluv2z(cpId, u[i], v[j])
            @test ref_z.status != 0
            @test Z[i,j] ≈ ref_z.z atol=1e-6
        end
        crgContactPointDelete(cpId); crgDataSetRelease(dsId); crgMemRelease()
    end

    @testset "REFPOINT_U_OFFSET/REFPOINT_V_OFFSET alone (no _FRACTION sibling) do NOT trigger the REFPOINT branch" begin
        # Bug #2 from the Tasks 16+17 review: crgDataApplyTransformations only
        # ever reads dCrgModRefPointUOffset/VOffset from INSIDE the UFrac/VFrac
        # branches (crgMgr.c:846,865) -- alone, they never set applyXform, so
        # the C reference falls through to REFLINE_OFFSET_*/REFLINE_ROTCENTER_*.
        # The shipped `has_refpoint` incorrectly included refpoint_u_offset/
        # refpoint_v_offset as standalone triggers -- confirmed empirically
        # during the review: refpoint_u_offset=5.0 plus refline_offset_x=100.0
        # took the (wrong) REFPOINT branch in Julia vs. the C oracle's correct
        # fallthrough to REFLINE_OFFSET_X. This mirrors the existing
        # REFLINE_OFFSET_* cross-validation test above, with refpoint_u_offset/
        # refpoint_v_offset thrown in (and expected to be completely inert).
        path = joinpath(DATA, "handmade_curved_minimalist.crg")
        data = OpenCRG.read_crg(path)
        mods = OpenCRG.RoadCrgMods(refpoint_u_offset=5.0, refpoint_v_offset=0.3, refline_offset_x=100.0)
        data_with_mods = OpenCRG.CRGData(data.comment, data.refline, data.format_code, data.opts, mods,
                                          data.mpro, data.phi, data.banking, data.slope, data.v, data.z)
        u, v, X, Y, Z = OpenCRG.road_surface_grid(data_with_mods)

        dsId = crgLoaderReadFile(path)
        @test crgDataSetModifierRemoveAll(dsId) != 0
        @test crgDataSetModifierSetDouble(dsId, LibOpenCRG.dCrgModRefPointUOffset, 5.0) != 0
        @test crgDataSetModifierSetDouble(dsId, LibOpenCRG.dCrgModRefPointVOffset, 0.3) != 0
        @test crgDataSetModifierSetDouble(dsId, LibOpenCRG.dCrgModRefLineOffsetX, 100.0) != 0
        crgDataSetModifiersApply(dsId)
        cpId = crgContactPointCreate(dsId)
        for i in eachindex(u), j in eachindex(v)
            ref = crgEvaluv2xy(cpId, u[i], v[j])
            @test ref.status != 0
            @test X[i,j] ≈ ref.x atol=1e-6
            @test Y[i,j] ≈ ref.y atol=1e-6
        end
        crgContactPointDelete(cpId); crgDataSetRelease(dsId); crgMemRelease()

        # Extension: the offsets must stay inert not only when NOTHING else is
        # set (falling through to REFLINE_OFFSET_*, tested above) but also when
        # a REFPOINT_X/Y/Z/PHI field IS active and the REFPOINT branch itself
        # runs -- e.g. if a future change accidentally wired
        # refpoint_u_offset/refpoint_v_offset into that branch (mistaking them
        # for real overrides rather than the UFrac/VFrac-only offsets they are
        # in the C reference), this would catch it. Confirmed inert here both
        # against a Julia-only baseline (offsets removed, refpoint_x kept) and
        # against the real C library directly.
        mods_with_offsets = OpenCRG.RoadCrgMods(refpoint_x=10.0, refpoint_u_offset=5.0, refpoint_v_offset=0.3)
        mods_baseline = OpenCRG.RoadCrgMods(refpoint_x=10.0)
        data_wo = OpenCRG.CRGData(data.comment, data.refline, data.format_code, data.opts, mods_with_offsets,
                                   data.mpro, data.phi, data.banking, data.slope, data.v, data.z)
        data_bl = OpenCRG.CRGData(data.comment, data.refline, data.format_code, data.opts, mods_baseline,
                                   data.mpro, data.phi, data.banking, data.slope, data.v, data.z)
        u2, v2, X2, Y2, Z2 = OpenCRG.road_surface_grid(data_wo)
        _, _, X2b, Y2b, Z2b = OpenCRG.road_surface_grid(data_bl)
        @test X2 == X2b   # offsets change NOTHING even with an active refpoint_x
        @test Y2 == Y2b
        @test isequal(Z2, Z2b)

        dsId2 = crgLoaderReadFile(path)
        @test crgDataSetModifierRemoveAll(dsId2) != 0
        @test crgDataSetModifierSetDouble(dsId2, LibOpenCRG.dCrgModRefPointX, 10.0) != 0
        @test crgDataSetModifierSetDouble(dsId2, LibOpenCRG.dCrgModRefPointUOffset, 5.0) != 0
        @test crgDataSetModifierSetDouble(dsId2, LibOpenCRG.dCrgModRefPointVOffset, 0.3) != 0
        crgDataSetModifiersApply(dsId2)
        cpId2 = crgContactPointCreate(dsId2)
        for i in eachindex(u2), j in eachindex(v2)
            ref = crgEvaluv2xy(cpId2, u2[i], v2[j])
            @test ref.status != 0
            @test X2[i,j] ≈ ref.x atol=1e-6
            @test Y2[i,j] ≈ ref.y atol=1e-6
        end
        crgContactPointDelete(cpId2); crgDataSetRelease(dsId2); crgMemRelease()
    end

    @testset "REFPOINT_U/REFPOINT_U_FRACTION/REFPOINT_V/REFPOINT_V_FRACTION: unconditional error" begin
        # Bug #1's flip side, and the plan's required scope-narrowing: this
        # package can't pin an arbitrary continuous (u,v) point (no
        # per-point interpolation/inversion API), so ANY of these four
        # fields being set at all must error loudly rather than silently
        # pinning the wrong point (or, worse, happening to look right only
        # when the value coincides with the default anchor).
        data = OpenCRG.read_crg(joinpath(DATA, "handmade_curved_minimalist.crg"))
        for (field, value) in [(:refpoint_u, 2.0), (:refpoint_u_fraction, 0.5),
                                (:refpoint_v, 1.0), (:refpoint_v_fraction, 0.5)]
            mods = OpenCRG.RoadCrgMods(; Dict(field => value)...)
            data_with_mods = OpenCRG.CRGData(data.comment, data.refline, data.format_code, data.opts, mods,
                                              data.mpro, data.phi, data.banking, data.slope, data.v, data.z)
            @test_throws Exception OpenCRG.apply_mods(data_with_mods)
        end
    end

    @testset "REFPOINT_X/Y/Z/PHI without an exact v=0 column: error, not silent misbehavior" begin
        # synthetic_hairpin.crg declares LONG_SECTION_V_RIGHT/V_LEFT =
        # -1.0/1.0 with exactly those two long-section columns -- no exact
        # v=0 column, so `v0_idx = findfirst(==(0.0), v)` in apply_mods
        # returns `nothing`, and the guard immediately above `from_z`'s
        # computation must error rather than, e.g., throwing a generic
        # BoundsError from indexing `z[1, nothing]`, or silently picking some
        # fallback column. This exact guard did not exist before the
        # REFPOINT_X/Y/Z/PHI rework (b2323dd): the prior implementation never
        # read the z-grid at all when computing the anchor's "from" point (it
        # located the anchor via `integrate_reference_line`/an index into phi,
        # and shifted elevation via `refline_offset_z`, defaulting inertly to
        # 0.0) -- confirmed directly by re-running that exact prior logic
        # against this fixture+mods combination: it returns normally, with
        # elevation silently left at 0.0, no error at all, where the current
        # code correctly errors instead.
        data = OpenCRG.read_crg(joinpath(DATA, "synthetic_hairpin.crg"))
        @test findfirst(==(0.0), data.v) === nothing   # sanity: this fixture really has no exact v=0 column
        mods = OpenCRG.RoadCrgMods(refpoint_x=5.0)
        data_with_mods = OpenCRG.CRGData(data.comment, data.refline, data.format_code, data.opts, mods,
                                          data.mpro, data.phi, data.banking, data.slope, data.v, data.z)
        @test_throws Exception OpenCRG.apply_mods(data_with_mods)
    end

    @testset "REFPOINT_Z: pins elevation at the default anchor, cross-validated (resolves the v=0 z-grid-folding question)" begin
        # apply_mods's docstring hypothesized from_z = z_ref[1] alone (the
        # reference-line elevation, no z-grid contribution). Neither
        # handmade_*.crg fixture can test this: their z-grid is exactly 0.0
        # at (start_u, v=0) for every v (confirmed by direct inspection), so
        # both "z_ref[1] alone" and "z_ref[1] + z_grid[1, v0_idx]" happen to
        # give the same answer there. belgian_block.crg (added to the
        # cross-validation fixture list in this same fix) is real-world scan
        # data whose z-grid is NOT zero at the anchor (~2.13m) -- confirmed
        # by cross-validating against the real C library directly
        # (crgEvaluv2z on the UNMODIFIED data set at (start_u, 0.0) returns
        # ≈2.1315932273864746, matching z_ref[1] (=0.0, no slope/start_z in
        # this file) + data.z[1, v0_idx] (=2.1315932273864746) bit-for-bit --
        # NOT the unfolded 0.0 the original hypothesis would have given).
        # This is the fixture that empirically forced folding the z-grid's
        # own v=0 value into from_z.
        path = joinpath(DATA, "belgian_block.crg")
        data = OpenCRG.read_crg(path)

        v0_idx = findfirst(==(0.0), data.v)
        @test v0_idx !== nothing
        @test !isapprox(data.z[1, v0_idx], 0.0; atol=1e-9)   # sanity: this fixture CAN distinguish the two hypotheses

        target = 42.0
        mods = OpenCRG.RoadCrgMods(refpoint_z=target)
        data_with_mods = OpenCRG.CRGData(data.comment, data.refline, data.format_code, data.opts, mods,
                                          data.mpro, data.phi, data.banking, data.slope, data.v, data.z)
        d2 = OpenCRG.apply_mods(data_with_mods)
        # NOT `d2.refline.start_z ≈ target` -- `refline.start_z` is only the
        # reference-line-elevation channel (z_ref[1]), which excludes the
        # z-grid's own v=0 contribution (z_grid is left untouched by
        # apply_mods; only z_ref moves). Since target = new_start_z +
        # z_grid[1,v0_idx], `refline.start_z` alone comes out to
        # `target - z_grid[1,v0_idx]`, not `target`. It's the FULL anchor
        # elevation -- z_ref PLUS the z-grid's v=0 value, i.e. exactly what
        # `road_surface_grid`'s assembled `Z` reports at node 1 / v=0 -- that
        # is pinned to `target` exactly, by construction (see apply_mods's
        # docstring: `from_z` folds in `z[1, v0_idx]`, and the shift is
        # `target - from_z`, so `new_start_z + z[1, v0_idx] ==
        # (z_ref[1] + (target - from_z)) + z[1, v0_idx] == target` exactly,
        # since `from_z == z_ref[1] + z[1, v0_idx]`).
        @test d2.refline.start_z + d2.z[1, v0_idx] ≈ target

        u, v, X, Y, Z = OpenCRG.road_surface_grid(data_with_mods)
        @test Z[1, v0_idx] ≈ target   # same fact, via the assembled grid this time

        dsId = crgLoaderReadFile(path)
        @test dsId != 0
        @test crgDataSetModifierRemoveAll(dsId) != 0
        @test crgDataSetModifierSetDouble(dsId, LibOpenCRG.dCrgModRefPointZ, target) != 0
        crgDataSetModifiersApply(dsId)
        cpId = crgContactPointCreate(dsId)

        # belgian_block.crg is a large (1001x341) real-world fixture -- sample
        # a handful of (u,v) pairs (both ends of u, the middle, and a few v's
        # including v=0 and the road edges) rather than the full grid: this
        # test's purpose is confirming the Z-anchor-pinning shift mechanism,
        # not re-cross-validating the whole lateral/z-grid assembly pipeline
        # (already covered end-to-end, on the FULL grid, by
        # test_crossvalidate.jl now that belgian_block.crg is in its list).
        sample_i = unique(clamp.([1, 2, cld(length(u), 2), length(u) - 1, length(u)], 1, length(u)))
        sample_j = unique(clamp.([1, v0_idx, cld(length(v), 2), length(v)], 1, length(v)))
        mismatches = 0
        for i in sample_i, j in sample_j
            ref_z = crgEvaluv2z(cpId, u[i], v[j])
            if ref_z.status != 0 && !isnan(ref_z.z) && !isnan(Z[i,j])
                isapprox(Z[i,j], ref_z.z; atol=1e-6) || (mismatches += 1)
            end
        end
        @test mismatches == 0

        crgContactPointDelete(cpId); crgDataSetRelease(dsId); crgMemRelease()
    end

    @testset "SCALE_Z_GRID + REFPOINT_Z combined: scaling is applied to the z-grid BEFORE the anchor shift reads it, cross-validated" begin
        # Composition check: `apply_mods` scales `z` (`z .*= mods.scale_z_grid`)
        # BEFORE the REFPOINT branch reads `z[1, v0_idx]` to compute `from_z`
        # -- so the anchor-elevation shift must be computed from the
        # ALREADY-SCALED z-grid value, not the original unscaled one. If it
        # instead used the unscaled value, the anchor's final elevation would
        # be off by exactly `(scale_z_grid - 1) * original_z[1,v0_idx]` instead
        # of landing exactly on `refpoint_z`. belgian_block.crg's z-grid is
        # genuinely nonzero at the anchor (~2.13m, see the REFPOINT_Z testset
        # above), so this fixture can actually distinguish the two hypotheses
        # (a zero anchor z-grid value can't).
        path = joinpath(DATA, "belgian_block.crg")
        data = OpenCRG.read_crg(path)
        v0_idx = findfirst(==(0.0), data.v)
        @test v0_idx !== nothing

        scale = 3.0
        target = 42.0
        mods = OpenCRG.RoadCrgMods(scale_z_grid=scale, refpoint_z=target)
        data_with_mods = OpenCRG.CRGData(data.comment, data.refline, data.format_code, data.opts, mods,
                                          data.mpro, data.phi, data.banking, data.slope, data.v, data.z)
        d2 = OpenCRG.apply_mods(data_with_mods)
        @test isapprox(d2.z[1, v0_idx], scale * data.z[1, v0_idx])   # sanity: the z-grid itself really is scaled
        @test d2.refline.start_z + d2.z[1, v0_idx] ≈ target          # anchor still lands exactly on target regardless

        u, v, X, Y, Z = OpenCRG.road_surface_grid(data_with_mods)
        @test Z[1, v0_idx] ≈ target   # same fact, via the assembled grid this time

        dsId = crgLoaderReadFile(path)
        @test dsId != 0
        @test crgDataSetModifierRemoveAll(dsId) != 0
        @test crgDataSetModifierSetDouble(dsId, LibOpenCRG.dCrgModScaleZ, scale) != 0
        @test crgDataSetModifierSetDouble(dsId, LibOpenCRG.dCrgModRefPointZ, target) != 0
        crgDataSetModifiersApply(dsId)
        cpId = crgContactPointCreate(dsId)

        # Same sparse-sampling rationale as the REFPOINT_Z testset above:
        # belgian_block.crg is a large (1001x341) real-world fixture, and this
        # test's purpose is confirming the SCALE_Z_GRID+REFPOINT_Z composition,
        # not re-cross-validating the whole grid-assembly pipeline.
        sample_i = unique(clamp.([1, 2, cld(length(u), 2), length(u) - 1, length(u)], 1, length(u)))
        sample_j = unique(clamp.([1, v0_idx, cld(length(v), 2), length(v)], 1, length(v)))
        mismatches = 0
        for i in sample_i, j in sample_j
            ref_xy = crgEvaluv2xy(cpId, u[i], v[j])
            if ref_xy.status != 0 && !isnan(X[i,j]) && !isnan(Y[i,j])
                (isapprox(X[i,j], ref_xy.x; atol=1e-6) && isapprox(Y[i,j], ref_xy.y; atol=1e-6)) || (mismatches += 1)
            end
            ref_z = crgEvaluv2z(cpId, u[i], v[j])
            if ref_z.status != 0 && !isnan(ref_z.z) && !isnan(Z[i,j])
                isapprox(Z[i,j], ref_z.z; atol=1e-6) || (mismatches += 1)
            end
        end
        @test mismatches == 0

        crgContactPointDelete(cpId); crgDataSetRelease(dsId); crgMemRelease()
    end

    @testset "REFPOINT_X alone (REFPOINT_Z unset) on belgian_block.crg: anchor elevation still correctly targets 0.0, cross-validated" begin
        # Coverage-gap intent: confirm that omitting REFPOINT_Z does NOT
        # accidentally corrupt (e.g. NaN) or skip the elevation shift when
        # only REFPOINT_X/Y/PHI triggers the REFPOINT branch. What "correct"
        # means here is settled precisely by directly reading
        # crgDataApplyTransformations (crgMgr.c ~lines 787-828, 872-884,
        # 953-964) AND cross-validating against the real compiled C library
        # (both done below) -- NOT by the intuitive-but-WRONG guess that
        # omitting REFPOINT_Z should leave elevation untouched. `toXYZ[2]`
        # (the "to" elevation) is a local initialized to `0.0` and is only
        # ever overwritten by `crgOptionGetDouble(..., dCrgModRefPointZ,
        # ...)`, which -- per its own implementation (crgOptionMgmt.c ~line
        # 342) -- returns 0 and leaves its output argument COMPLETELY
        # UNTOUCHED when the option isn't set. So when only REFPOINT_X (or
        # Y/PHI) triggers `applyXform`, `toXYZ[2]` stays `0.0`, and the
        # z-channel shift actually applied is `toXYZ[2] - fromXYZ[2] ==
        # -fromXYZ[2]` -- i.e. the real C reference DELIBERATELY drives the
        # anchor's elevation to exactly `0.0`, the same "unset -> target 0.0"
        # default already used for refpoint_x/y themselves
        # (`something(mods.refpoint_x, 0.0)`), NOT preserving its original
        # value. Confirmed empirically below, both in Julia and directly
        # against the compiled C oracle -- they agree bit-for-bit. The
        # existing "REFPOINT_* overrides..." testset above already asserts
        # this same "targets 0.0" fact, but on handmade_curved_minimalist.crg,
        # whose z-grid happens to be exactly 0.0 at the anchor already -- so
        # it can't distinguish "correctly shifted to 0.0" from "coincidentally
        # already 0.0". belgian_block.crg's genuinely nonzero anchor elevation
        # (~2.13m) closes that gap.
        path = joinpath(DATA, "belgian_block.crg")
        data = OpenCRG.read_crg(path)
        v0_idx = findfirst(==(0.0), data.v)
        @test v0_idx !== nothing
        @test !isapprox(data.z[1, v0_idx], 0.0; atol=1e-9)   # sanity: nonzero anchor elevation -- this fixture CAN distinguish the two hypotheses

        mods = OpenCRG.RoadCrgMods(refpoint_x=10.0)   # refpoint_z deliberately left UNSET
        data_with_mods = OpenCRG.CRGData(data.comment, data.refline, data.format_code, data.opts, mods,
                                          data.mpro, data.phi, data.banking, data.slope, data.v, data.z)
        u, v, X, Y, Z = OpenCRG.road_surface_grid(data_with_mods)
        @test Z[1, v0_idx] ≈ 0.0 atol=1e-6   # NOT ≈ 2.1315932273864746 (the pre-transform value) -- confirms shift-to-0.0, not a no-op

        dsId = crgLoaderReadFile(path)
        @test dsId != 0
        @test crgDataSetModifierRemoveAll(dsId) != 0
        @test crgDataSetModifierSetDouble(dsId, LibOpenCRG.dCrgModRefPointX, 10.0) != 0
        crgDataSetModifiersApply(dsId)
        cpId = crgContactPointCreate(dsId)

        sample_i = unique(clamp.([1, 2, cld(length(u), 2), length(u) - 1, length(u)], 1, length(u)))
        sample_j = unique(clamp.([1, v0_idx, cld(length(v), 2), length(v)], 1, length(v)))
        mismatches = 0
        for i in sample_i, j in sample_j
            ref_xy = crgEvaluv2xy(cpId, u[i], v[j])
            if ref_xy.status != 0 && !isnan(X[i,j]) && !isnan(Y[i,j])
                (isapprox(X[i,j], ref_xy.x; atol=1e-6) && isapprox(Y[i,j], ref_xy.y; atol=1e-6)) || (mismatches += 1)
            end
            ref_z = crgEvaluv2z(cpId, u[i], v[j])
            if ref_z.status != 0 && !isnan(ref_z.z) && !isnan(Z[i,j])
                isapprox(Z[i,j], ref_z.z; atol=1e-6) || (mismatches += 1)
            end
        end
        @test mismatches == 0

        crgContactPointDelete(cpId); crgDataSetRelease(dsId); crgMemRelease()
    end

    @testset "SCALE_Z_GRID doubles elevation" begin
        data = OpenCRG.read_crg(joinpath(DATA, "handmade_curved_banked_sloped.crg"))
        mods = OpenCRG.RoadCrgMods(scale_z_grid=2.0)
        data_with_mods = OpenCRG.CRGData(data.comment, data.refline, data.format_code, data.opts, mods,
                                          data.mpro, data.phi, data.banking, data.slope, data.v, data.z)
        d2 = OpenCRG.apply_mods(data_with_mods)
        # NOT plain `≈` here: this real fixture genuinely has 3 NaN samples
        # scattered in its z data (border columns at rows 12/14/16 -- confirmed
        # by direct inspection, `count(isnan, data.z) == 3`), and whole-array
        # `isapprox` is norm-based (`norm(d2.z - 2.0.*data.z) <= atol + ...`):
        # a NaN anywhere in the difference poisons the norm to NaN, which is
        # never `<=` anything, so the plan's original `d2.z ≈ 2.0 .* data.z`
        # fails even though every entry -- NaN included, since NaN*2.0 is still
        # NaN at the same position on both sides -- is exactly what it should
        # be. `isequal` is exact (not approximate) but that's fine: `.*=` here
        # is a single scalar multiply, bit-for-bit identical to `2.0 .* data.z`,
        # and `isequal`'s NaN-as-equal-to-itself semantics is exactly what's
        # needed to compare the missing-sample positions correctly.
        @test isequal(d2.z, 2.0 .* data.z)
    end

    @testset "SCALE_WIDTH preserves the v-ascending / z-column invariant assemble_z_grid relies on" begin
        # Task 14's review flagged that assemble_z_grid's banking clamp is only a
        # documented no-op because CRGData.v is always sorted ascending and lines
        # up 1:1 with CRGData.z's columns (Task 9's sortperm guarantee). apply_mods
        # is the only place in this task that touches `v` at all (via
        # SCALE_WIDTH), so this regression-tests that a (positive) width scale
        # can't desync that invariant: v must stay sorted ascending, and each
        # column of z must still correspond to the same (scaled) v it did before.
        data = OpenCRG.read_crg(joinpath(DATA, "handmade_curved_banked_sloped.crg"))
        mods = OpenCRG.RoadCrgMods(scale_width=2.0)
        data_with_mods = OpenCRG.CRGData(data.comment, data.refline, data.format_code, data.opts, mods,
                                          data.mpro, data.phi, data.banking, data.slope, data.v, data.z)
        d2 = OpenCRG.apply_mods(data_with_mods)
        @test d2.v ≈ 2.0 .* data.v
        @test issorted(d2.v)
        # isequal, not ==: this fixture has real NaN samples (see the
        # SCALE_Z_GRID testset above) and plain `==` treats NaN != NaN even in
        # the exact-same-position, exact-same-untouched-value case here.
        @test isequal(d2.z, data.z)   # z itself is untouched -- only the v labels attached to its columns change
    end

    # The four testsets below close a whole-plan-final-review coverage gap:
    # scale_length/scale_curvature/scale_slope/scale_banking had ZERO
    # behavioral test coverage anywhere in this file before this fix (grep
    # confirmed none of those four identifiers appeared here), in sharp
    # contrast to SCALE_Z_GRID/SCALE_WIDTH above. All four use
    # handmade_curved_banked_sloped.crg: it's the only vendored fixture with
    # BOTH a nonzero, unequal start_u/end_u range (0.0/22.0 -- needed to
    # distinguish "scaled" from "stale" for SCALE_LENGTH) AND real, non-flat,
    # non-constant per-row banking/slope/phi channel data (all three ramp
    # 0.0 -> 0.11 -> 0.0 -- confirmed by direct inspection; belgian_block.crg,
    # the other candidate, has neither banking nor slope channels at all, and
    # its phi is a real recorded curve but it's a much larger fixture with no
    # offsetting benefit here). It's also small (23 rows x 7 v-columns = 161
    # grid points), so every cross-validation below enumerates the FULL grid
    # rather than sparse-sampling like the belgian_block.crg tests above.

    @testset "SCALE_LENGTH rescales end_u proportionally about start_u (was stale before this fix), cross-validated" begin
        # Found during the whole-plan final review: apply_mods scaled
        # u_increment under SCALE_LENGTH but threaded r.end_u straight through
        # to r2/r3 completely UNCHANGED. The real C reference
        # (crgDataSetModifiersApply, crgMgr.c ~548-558) instead recomputes
        # `channelU.info.last = channelU.info.first + dValue * uRange` (uRange
        # being the ORIGINAL, pre-scale `last - first`) -- i.e. end_u must
        # scale proportionally about start_u, not stay fixed. This bug has
        # zero effect on road_surface_grid's own output (its u-axis is built
        # from `start_u + (i-1)*increment` only; end_u is never read
        # downstream -- see road_surface_grid's body and apply_mods's
        # docstring) -- but end_u IS part of the public
        # ReferenceLineParams/CRGData struct a caller could read directly, so
        # leaving it stale was a real, if inert, correctness bug.
        path = joinpath(DATA, "handmade_curved_banked_sloped.crg")
        data = OpenCRG.read_crg(path)
        @test data.refline.start_u == 0.0    # sanity: nonzero, UNEQUAL start_u/end_u --
        @test data.refline.end_u == 22.0     # otherwise this fixture couldn't distinguish "scaled" from "stale"

        factor = 1.5
        mods = OpenCRG.RoadCrgMods(scale_length=factor)
        data_with_mods = OpenCRG.CRGData(data.comment, data.refline, data.format_code, data.opts, mods,
                                          data.mpro, data.phi, data.banking, data.slope, data.v, data.z)
        d2 = OpenCRG.apply_mods(data_with_mods)
        @test d2.refline.start_u == 0.0                              # start_u itself never moves
        @test d2.refline.end_u ≈ 0.0 + factor * (22.0 - 0.0)         # == 33.0: proportional about start_u, NOT the stale 22.0
        @test !isapprox(d2.refline.end_u, data.refline.end_u)         # sanity: distinguishable from the (bug's) unchanged value
        @test d2.refline.increment ≈ factor * data.refline.increment # the part that was already correct before this fix

        u, v, X, Y, Z = OpenCRG.road_surface_grid(data_with_mods)

        dsId = crgLoaderReadFile(path)
        @test dsId != 0
        @test crgDataSetModifierRemoveAll(dsId) != 0
        @test crgDataSetModifierSetDouble(dsId, LibOpenCRG.dCrgModScaleLength, factor) != 0
        crgDataSetModifiersApply(dsId)

        # Cross-validate the end_u fix directly against the compiled oracle's
        # own post-scale internal state (crgDataSetGetURange reads
        # channelU.info.first/last back out), not just hand arithmetic.
        uRangeRes = crgDataSetGetURange(dsId)
        @test uRangeRes.status != 0
        @test uRangeRes.uMin ≈ d2.refline.start_u atol=1e-9
        @test uRangeRes.uMax ≈ d2.refline.end_u atol=1e-9

        # Cross-validate the actually-behaviorally-visible effect too
        # (increment stretching the whole grid), same mismatch-counting
        # pattern as the REFPOINT_Z/SCALE_Z_GRID+REFPOINT_Z cross-validation
        # tests above.
        cpId = crgContactPointCreate(dsId)
        mismatches = 0
        for i in eachindex(u), j in eachindex(v)
            ref_xy = crgEvaluv2xy(cpId, u[i], v[j])
            if ref_xy.status != 0 && !isnan(X[i,j]) && !isnan(Y[i,j])
                (isapprox(X[i,j], ref_xy.x; atol=1e-6) && isapprox(Y[i,j], ref_xy.y; atol=1e-6)) || (mismatches += 1)
            end
            ref_z = crgEvaluv2z(cpId, u[i], v[j])
            if ref_z.status != 0 && !isnan(ref_z.z) && !isnan(Z[i,j])
                isapprox(Z[i,j], ref_z.z; atol=1e-6) || (mismatches += 1)
            end
        end
        @test mismatches == 0

        crgContactPointDelete(cpId); crgDataSetRelease(dsId); crgMemRelease()
    end

    @testset "SCALE_CURVATURE: phi-transformation formula, hand-verified with non-trivial non-constant phi" begin
        # Unlike the other SCALE_* fields, curvature scaling has no
        # crgDataScaleChannel analogue -- it's hand-rolled identically in both
        # the Julia and C implementations: phi[i] = base + scale*(phi[i]-base)
        # for every index EXCEPT the first (base = phi[1], never itself
        # rescaled). A CONSTANT phi structurally cannot distinguish a correct
        # per-element transform from e.g. an off-by-one bug that scales about
        # the wrong pivot or a formula that scales phi[i] by a constant
        # instead of (phi[i]-base) -- same rationale as
        # integrate_reference_line/integrate_reference_z's own
        # "arrival-heading/-slope convention" tests earlier in this file --
        # hence the deliberately non-constant, non-monotonic phi below.
        r = OpenCRG.parse_road_crg(["REFERENCE_LINE_START_PHI=0.3"])
        phi = [0.3, 0.5, -0.3, 0.9, 1.4]   # phi[1] == start_phi, matching real parsed data (assemble_channels's row-1 overwrite)
        mods = OpenCRG.RoadCrgMods(scale_curvature=2.0)
        data = OpenCRG.CRGData("", r, :LRFI, Dict{String,Float64}(), mods, Dict{String,String}(),
                                phi, nothing, nothing, [0.0], zeros(5, 1))
        d2 = OpenCRG.apply_mods(data)
        # Hand-computed: base = phi[1] = 0.3; phi[i]_new = 0.3 + 2.0*(phi[i]-0.3) for i=2:5.
        #   phi[2]: 0.3 + 2.0*(0.5 - 0.3)  = 0.3 + 0.4  = 0.7
        #   phi[3]: 0.3 + 2.0*(-0.3 - 0.3) = 0.3 - 1.2  = -0.9
        #   phi[4]: 0.3 + 2.0*(0.9 - 0.3)  = 0.3 + 1.2  = 1.5
        #   phi[5]: 0.3 + 2.0*(1.4 - 0.3)  = 0.3 + 2.2  = 2.5
        # No REFLINE_OFFSET_PHI/REFPOINT_PHI set here, so apply_mods's later
        # unconditional `phi .+= rot_angle` step adds exactly 0.0 -- this
        # isolates the curvature transform alone. Independently verified both
        # by hand (above) and in an isolated Julia scratch session.
        @test d2.phi ≈ [0.3, 0.7, -0.9, 1.5, 2.5] atol=1e-12
    end

    @testset "SCALE_CURVATURE: phi transform on real curved data, cross-validated against LibOpenCRG" begin
        # dCrgModScaleCurvature (LibOpenCRG.jl constant, =26, added in Task 15)
        # DOES exist as a real, isolated C-library modifier id, same as the
        # other 5 SCALE_* fields -- so this closes the gap the same
        # cross-validated way as SCALE_LENGTH/SCALE_SLOPE/SCALE_BANKING,
        # checking the whole (X,Y,Z) grid this time rather than just phi in
        # isolation (the previous testset already hand-verified the raw phi
        # formula; this one confirms it composes correctly with everything
        # downstream -- integrate_reference_line, lateral_offset_grid, etc.).
        path = joinpath(DATA, "handmade_curved_banked_sloped.crg")
        data = OpenCRG.read_crg(path)
        @test length(unique(data.phi[2:end])) > 1   # sanity: genuinely non-constant (curved) phi data, not a degenerate straight line

        factor = 1.5
        mods = OpenCRG.RoadCrgMods(scale_curvature=factor)
        data_with_mods = OpenCRG.CRGData(data.comment, data.refline, data.format_code, data.opts, mods,
                                          data.mpro, data.phi, data.banking, data.slope, data.v, data.z)
        u, v, X, Y, Z = OpenCRG.road_surface_grid(data_with_mods)

        dsId = crgLoaderReadFile(path)
        @test dsId != 0
        @test crgDataSetModifierRemoveAll(dsId) != 0
        @test crgDataSetModifierSetDouble(dsId, LibOpenCRG.dCrgModScaleCurvature, factor) != 0
        crgDataSetModifiersApply(dsId)
        cpId = crgContactPointCreate(dsId)
        mismatches = 0
        for i in eachindex(u), j in eachindex(v)
            ref_xy = crgEvaluv2xy(cpId, u[i], v[j])
            if ref_xy.status != 0 && !isnan(X[i,j]) && !isnan(Y[i,j])
                (isapprox(X[i,j], ref_xy.x; atol=1e-6) && isapprox(Y[i,j], ref_xy.y; atol=1e-6)) || (mismatches += 1)
            end
            ref_z = crgEvaluv2z(cpId, u[i], v[j])
            if ref_z.status != 0 && !isnan(ref_z.z) && !isnan(Z[i,j])
                isapprox(Z[i,j], ref_z.z; atol=1e-6) || (mismatches += 1)
            end
        end
        @test mismatches == 0
        crgContactPointDelete(cpId); crgDataSetRelease(dsId); crgMemRelease()
    end

    @testset "SCALE_SLOPE scales the slope channel (and start_slope/end_slope), cross-validated" begin
        path = joinpath(DATA, "handmade_curved_banked_sloped.crg")
        data = OpenCRG.read_crg(path)
        @test data.slope !== nothing
        @test any(!=(0.0), data.slope)   # sanity: real, nonzero per-row slope data -- not a vacuous all-zero test

        factor = 2.0
        mods = OpenCRG.RoadCrgMods(scale_slope=factor)
        data_with_mods = OpenCRG.CRGData(data.comment, data.refline, data.format_code, data.opts, mods,
                                          data.mpro, data.phi, data.banking, data.slope, data.v, data.z)
        d2 = OpenCRG.apply_mods(data_with_mods)
        @test d2.slope ≈ factor .* data.slope
        # This fixture's header never declares REFERENCE_LINE_START_S/END_S,
        # so start_slope defaults to 0.0 (scaling is a no-op, but still
        # regression-tested) and end_slope stays `nothing` throughout.
        @test d2.refline.start_slope == 0.0
        @test d2.refline.end_slope === nothing

        u, v, X, Y, Z = OpenCRG.road_surface_grid(data_with_mods)

        dsId = crgLoaderReadFile(path)
        @test dsId != 0
        @test crgDataSetModifierRemoveAll(dsId) != 0
        @test crgDataSetModifierSetDouble(dsId, LibOpenCRG.dCrgModScaleSlope, factor) != 0
        crgDataSetModifiersApply(dsId)
        cpId = crgContactPointCreate(dsId)
        mismatches = 0
        for i in eachindex(u), j in eachindex(v)
            ref_z = crgEvaluv2z(cpId, u[i], v[j])
            if ref_z.status != 0 && !isnan(ref_z.z) && !isnan(Z[i,j])
                isapprox(Z[i,j], ref_z.z; atol=1e-6) || (mismatches += 1)
            end
        end
        @test mismatches == 0
        crgContactPointDelete(cpId); crgDataSetRelease(dsId); crgMemRelease()
    end

    @testset "SCALE_BANKING scales the banking channel (and start_banking/end_banking), cross-validated" begin
        path = joinpath(DATA, "handmade_curved_banked_sloped.crg")
        data = OpenCRG.read_crg(path)
        @test data.banking !== nothing
        @test any(!=(0.0), data.banking)   # sanity: real, nonzero per-row banking data -- not a vacuous all-zero test

        factor = 2.0
        mods = OpenCRG.RoadCrgMods(scale_banking=factor)
        data_with_mods = OpenCRG.CRGData(data.comment, data.refline, data.format_code, data.opts, mods,
                                          data.mpro, data.phi, data.banking, data.slope, data.v, data.z)
        d2 = OpenCRG.apply_mods(data_with_mods)
        @test d2.banking ≈ factor .* data.banking
        # Same "header never declares START_B/END_B" situation as SCALE_SLOPE
        # above: start_banking defaults to 0.0 (scaling is a no-op, but still
        # regression-tested) and end_banking stays `nothing`.
        @test d2.refline.start_banking == 0.0
        @test d2.refline.end_banking === nothing

        u, v, X, Y, Z = OpenCRG.road_surface_grid(data_with_mods)

        dsId = crgLoaderReadFile(path)
        @test dsId != 0
        @test crgDataSetModifierRemoveAll(dsId) != 0
        @test crgDataSetModifierSetDouble(dsId, LibOpenCRG.dCrgModScaleBank, factor) != 0
        crgDataSetModifiersApply(dsId)
        cpId = crgContactPointCreate(dsId)
        mismatches = 0
        for i in eachindex(u), j in eachindex(v)
            ref_z = crgEvaluv2z(cpId, u[i], v[j])
            if ref_z.status != 0 && !isnan(ref_z.z) && !isnan(Z[i,j])
                isapprox(Z[i,j], ref_z.z; atol=1e-6) || (mismatches += 1)
            end
        end
        @test mismatches == 0
        crgContactPointDelete(cpId); crgDataSetRelease(dsId); crgMemRelease()
    end
end
