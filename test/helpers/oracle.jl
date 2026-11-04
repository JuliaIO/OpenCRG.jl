# Compare `road_surface_grid` against the C reference implementation (OpenCRG_jll).

include("LibOpenCRG.jl")
using .LibOpenCRG

"""
    oracle_mismatches(jl_path, c_path = jl_path; c_mods = (), rows = :, cols = :) -> (compared, mismatches)

Evaluate the grid of `read_crg(jl_path)` with `road_surface_grid`, then load
`c_path` in the C library, apply the `c_mods` modifiers (`id => value` pairs)
and evaluate the same `(u, v)` nodes there. Returns how many nodes were
compared and how many disagree (in x, y or z) by more than `1e-6`.
"""
function oracle_mismatches(jl_path, c_path = jl_path; c_mods = (), rows = :, cols = :)
    u, v, X, Y, Z = road_surface_grid(read_crg(jl_path))
    dsId = crgLoaderReadFile(c_path)
    dsId != 0 && crgCheck(dsId) != 0 || error("C library could not load $c_path")
    # The loader seeds default modifiers; clear them so only `c_mods` apply.
    crgDataSetModifierRemoveAll(dsId)
    for (id, val) in c_mods
        crgDataSetModifierSetDouble(dsId, id, val) != 0 || error("could not set modifier $id")
    end
    crgDataSetModifiersApply(dsId)
    cpId = crgContactPointCreate(dsId)
    compared = mismatches = 0
    for i in eachindex(u)[rows], j in eachindex(v)[cols]
        r = crgEvaluv2xy(cpId, u[i], v[j])
        r.status != 0 || continue
        compared += 1
        ok = isapprox(X[i, j], r.x; atol = 1e-6) && isapprox(Y[i, j], r.y; atol = 1e-6)
        rz = crgEvaluv2z(cpId, u[i], v[j])
        if rz.status != 0 && !isnan(rz.z) && !isnan(Z[i, j])
            ok &= isapprox(Z[i, j], rz.z; atol = 1e-6)
        end
        ok || (mismatches += 1)
    end
    crgContactPointDelete(cpId); crgDataSetRelease(dsId); crgMemRelease()
    return compared, mismatches
end
