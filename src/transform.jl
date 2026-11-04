
"""
    integrate_reference_line(refline, phi) -> (x, y)

Integrate heading `phi` into reference-line positions `(x, y)`, blending toward the end point if given.
"""
function integrate_reference_line(refline::ReferenceLineParams, phi::Vector{Float64})
    nu = length(phi)
    du = refline.increment
    x, y = Vector{Float64}(undef, nu), Vector{Float64}(undef, nu)
    x[1], y[1] = refline.start_x, refline.start_y
    if refline.end_x === nothing && refline.end_y === nothing
        for i in 1:nu-1
            x[i+1] = x[i] + du * cos(phi[i+1])
            y[i+1] = y[i] + du * sin(phi[i+1])
        end
        return x, y
    end
    xb, yb = Vector{Float64}(undef, nu), Vector{Float64}(undef, nu)
    xb[nu], yb[nu] = refline.end_x, refline.end_y
    for i in nu:-1:2
        xb[i-1] = xb[i] - du * cos(phi[i])
        yb[i-1] = yb[i] - du * sin(phi[i])
    end
    for i in 1:nu-1
        fraction = i / (nu - 1)
        x[i+1] = (1 - fraction) * (x[i] + du * cos(phi[i+1])) + fraction * xb[i+1]
        y[i+1] = (1 - fraction) * (y[i] + du * sin(phi[i+1])) + fraction * yb[i+1]
    end
    return x, y
end

"""
    integrate_reference_z(refline, slope, nu) -> z_ref

Integrate `slope` into the reference-line elevation profile, matching the C library's `calcRefLineZ`.
"""
function integrate_reference_z(refline::ReferenceLineParams, slope::Union{Vector{Float64},Nothing}, nu::Int)
    if slope === nothing && refline.start_slope == 0.0
        return fill(refline.start_z, nu)
    end
    du = refline.increment
    slope_at(i) = slope === nothing ? refline.start_slope : slope[i]
    z_ref = Vector{Float64}(undef, nu)
    z_ref[1] = refline.start_z
    if refline.end_z === nothing
        for i in 1:nu-1
            z_ref[i+1] = z_ref[i] + slope_at(i+1) * du
        end
        return z_ref
    end
    zb = Vector{Float64}(undef, nu)
    zb[nu] = refline.end_z
    for i in nu:-1:2
        zb[i-1] = zb[i] - slope_at(i) * du
    end
    if nu >= 2
        # the true end anchor -- set directly, matching `calcRefLineZ`'s
        # `data[size-1] = info.last` at the top of the function; the blend
        # loop below deliberately never touches this index again (its bound
        # is `1:nu-2`, one short of `integrate_reference_line`'s `1:nu-1`).
        z_ref[nu] = zb[nu]
    end
    for i in 1:nu-2
        fraction = (i - 1) / (nu - 1)
        z_ref[i+1] = (1 - fraction) * (z_ref[i] + slope_at(i+1) * du) + fraction * zb[i+1]
    end
    return z_ref
end

"""
    lateral_offset_grid(x, y, v) -> (X, Y)

Offset the reference line by each `v` (miter normals, positive left) into `(X, Y)` grids.
"""
function lateral_offset_grid(x::Vector{Float64}, y::Vector{Float64}, v::Vector{Float64})
    nu = length(x)
    perp(d) = (-d[2], d[1])
    # Guarded normalize: matches `normalizeVector2` (crgEvaluv2xy.c ~line 197)
    # exactly -- leave the vector UNCHANGED (not divided) when its length is
    # below 1.0e-10, instead of dividing by (near-)zero and producing NaN/Inf.
    normalize2(d) = (n = hypot(d[1], d[2]); n < 1.0e-10 ? d : (d[1]/n, d[2]/n))

    seg = [normalize2((x[i+1]-x[i], y[i+1]-y[i])) for i in 1:nu-1]
    n12 = perp.(seg)

    offset_dir = Vector{Tuple{Float64,Float64}}(undef, nu)
    if nu == 1
        offset_dir[1] = (0.0, 1.0)   # degenerate single-node "line"; arbitrary but consistent
    else
        offset_dir[1] = n12[1]
        offset_dir[nu] = n12[nu-1]
        for i in 2:nu-1
            chord = normalize2((x[i+1]-x[i-1], y[i+1]-y[i-1]))
            n1 = perp(chord)
            denom = n1[1]*n12[i][1] + n1[2]*n12[i][2]
            # Guarded rescale: matches the C reference's `fabs(dotProd) > 1.0e-10`
            # check exactly -- only rescale when the dot product is big enough;
            # otherwise fall back to the (possibly still un-normalized, per the
            # guard above) bisector `n1` as-is. This is what produces the
            # graceful "stay on the reference line" fallback at a hairpin,
            # instead of blowing up to NaN/Inf.
            offset_dir[i] = abs(denom) > 1.0e-10 ? (n1[1]/denom, n1[2]/denom) : n1
        end
    end

    nv = length(v)
    X, Y = Matrix{Float64}(undef, nu, nv), Matrix{Float64}(undef, nu, nv)
    for i in 1:nu, j in 1:nv
        X[i,j] = x[i] + v[j] * offset_dir[i][1]
        Y[i,j] = y[i] + v[j] * offset_dir[i][2]
    end
    return X, Y
end

"""
    assemble_z_grid(z_grid, z_ref, banking, refline, v) -> Z

Combine the raw grid, reference elevation and banking into world `Z`.
"""
function assemble_z_grid(z_grid::Matrix{Float64}, z_ref::Vector{Float64}, banking::Union{Vector{Float64},Nothing}, refline::ReferenceLineParams, v::Vector{Float64})
    nu, nv = size(z_grid)
    Z = Matrix{Float64}(undef, nu, nv)
    vmin, vmax = first(v), last(v)
    for i in 1:nu
        bank_i = banking === nothing ? refline.start_banking : banking[i]
        for j in 1:nv
            vc = clamp(v[j], vmin, vmax)
            Z[i,j] = z_grid[i,j] + z_ref[i] + bank_i * vc
        end
    end
    return Z
end

"""
    apply_mods(data::CRGData) -> CRGData

Return a copy of `data` with its `\$ROAD_CRG_MODS` scale and offset modifiers applied.
Throws an error for the unsupported `REFPOINT_*` cases listed in [`road_surface_grid`](@ref).
"""
function apply_mods(data::CRGData)
    mods = data.mods
    r = data.refline
    xor(r.end_x === nothing, r.end_y === nothing) &&
        error("REFERENCE_LINE_END_X/END_Y must both be set or both be absent, not just one")
    phi = copy(data.phi)
    z = copy(data.z)
    slope = data.slope === nothing ? nothing : copy(data.slope)
    banking = data.banking === nothing ? nothing : copy(data.banking)
    v = copy(data.v)
    u_increment, start_slope, end_slope, start_banking, end_banking =
        r.increment, r.start_slope, r.end_slope, r.start_banking, r.end_banking
    # Endpoint anchors; crgDataSetModifiersApply invalidates the ones a scale
    # modifier makes obsolete (see the scaling blocks below).
    end_x, end_y, end_z = r.end_x, r.end_y, r.end_z

    mods.scale_z_grid === nothing || (z .*= mods.scale_z_grid)
    if mods.scale_slope !== nothing
        slope === nothing || (slope .*= mods.scale_slope)
        start_slope *= mods.scale_slope
        end_slope = end_slope === nothing ? nothing : end_slope * mods.scale_slope
        end_z = nothing  # crgMgr.c clears dCrgDataDefZEnd
    end
    if mods.scale_banking !== nothing
        banking === nothing || (banking .*= mods.scale_banking)
        start_banking *= mods.scale_banking
        end_banking = nothing  # crgMgr.c clears dCrgDataDefBankEnd
    end
    if mods.scale_length !== nothing
        u_increment *= mods.scale_length
        end_x = end_y = end_z = nothing  # crgMgr.c clears dCrgDataDefX/Y/ZEnd
    end
    mods.scale_width === nothing || (v .*= mods.scale_width)
    if mods.scale_curvature !== nothing
        base = phi[1]
        for i in 2:length(phi)
            phi[i] = base + mods.scale_curvature * (phi[i] - base)
        end
        end_x = end_y = nothing  # crgMgr.c clears dCrgDataDefX/YEnd
    end

    r2 = ReferenceLineParams(r.start_u, r.end_u, u_increment, r.start_x, r.start_y, r.start_phi,
        end_x, end_y, r.end_phi, r.start_z, end_z, r.v_right, r.v_left, r.v_increment,
        start_slope, end_slope, start_banking, end_banking)

    # SCALE_LENGTH: end_u must rescale proportionally about start_u (matching
    # crgDataSetModifiersApply's `channelU.info.last = channelU.info.first +
    # dValue * uRange`, crgMgr.c ~548-558) -- NOT stay fixed at r2.end_u, which
    # is otherwise never read again between here and r3's construction below
    # (only threaded straight through), making this the one place the
    # corrected value needs to land. See this function's docstring.
    new_end_u = r2.start_u + something(mods.scale_length, 1.0) * (r2.end_u - r2.start_u)

    # REFPOINT_U/REFPOINT_U_FRACTION/REFPOINT_V/REFPOINT_V_FRACTION pin an
    # arbitrary CONTINUOUS (u,v) point, which requires genuine point
    # interpolation (crgDataEvaluv2xy/crgDataEvaluv2z in the C reference) --
    # out of scope for this package's grid-only, forward-only design (see
    # this function's docstring). Error unconditionally on ANY value, rather
    # than special-casing "happens to equal the default", which would be
    # fragile, floating-point-exactness-dependent behavior.
    any(f -> getfield(mods, f) !== nothing,
        (:refpoint_u, :refpoint_u_fraction, :refpoint_v, :refpoint_v_fraction)) &&
        error("apply_mods: REFPOINT_U/REFPOINT_U_FRACTION/REFPOINT_V/REFPOINT_V_FRACTION are not " *
              "supported -- pinning an arbitrary continuous (u,v) point requires per-point " *
              "interpolation, which this package's grid-only, forward-only design does not " *
              "implement. Only REFPOINT_X/REFPOINT_Y/REFPOINT_Z/REFPOINT_PHI, anchored at the " *
              "implicit default point (u = start_u, v = 0), are supported.")

    # NOTE: REFPOINT_U_OFFSET/REFPOINT_V_OFFSET are deliberately absent from
    # this trigger tuple -- in the C reference they are only ever read from
    # INSIDE the UFrac/VFrac branches (crgMgr.c:846,865), never independent
    # triggers, so (matching that exactly) they must be inert here too, now
    # that the UFrac/VFrac path they'd otherwise feed always errors above.
    has_refpoint = any(f -> getfield(mods, f) !== nothing,
        (:refpoint_x, :refpoint_y, :refpoint_z, :refpoint_phi))

    if has_refpoint
        # The only supported anchor is the implicit default (u = start_u,
        # i.e. grid node 1; v = 0), which is exactly the reference line's own
        # start point -- no integration/interpolation needed for x/y/phi.
        from_x, from_y, from_phi = r2.start_x, r2.start_y, r2.start_phi
        rot_center = (from_x, from_y)
        rot_angle = something(mods.refpoint_phi, 0.0) - from_phi
        translation = (something(mods.refpoint_x, 0.0) - from_x, something(mods.refpoint_y, 0.0) - from_y)

        # Matching crgDataApplyTransformations exactly: the anchor's current
        # elevation (fromXYZ[2] there) is evaluated via crgDataEvaluv2z's
        # FULL z surface -- z-grid value at v=0 PLUS the reference-line
        # elevation, banking excluded since it's multiplied by v=0 -- not the
        # reference-line elevation alone, and this happens whenever ANY of
        # REFPOINT_X/Y/Z/PHI triggers this branch, not only when REFPOINT_Z
        # itself is set (cross-validated; see the docstring).
        v0_idx = findfirst(==(0.0), v)
        v0_idx === nothing && error("apply_mods: REFPOINT_X/Y/Z/PHI need the elevation at the default " *
              "anchor's v=0, which requires an exact v=0 declared long-section column -- this package " *
              "does not implement v-interpolation, and this file has no exact v=0 column.")
        # The reference-line component of the anchor's elevation is just
        # `r2.start_z`, not `integrate_reference_z(r2, slope, length(phi))[1]`
        # -- BOTH of integrate_reference_z's paths (the early-return AND the
        # general path) set element 1 to `refline.start_z` unconditionally
        # before any loop/blend logic runs (see its implementation), so that
        # element is always exactly `r2.start_z`, regardless of slope/end_z.
        # Calling the full O(nu) integration (including its forward/backward
        # + blend double loop when end_z is set) just to read element 1 is
        # wasted work; reading `r2.start_z` directly is identical.
        from_z = r2.start_z + z[1, v0_idx]
        z_shift = something(mods.refpoint_z, 0.0) - from_z
    else
        rot_center = (something(mods.refline_rotcenter_x, r2.start_x), something(mods.refline_rotcenter_y, r2.start_y))
        rot_angle = something(mods.refline_offset_phi, 0.0)
        translation = (something(mods.refline_offset_x, 0.0), something(mods.refline_offset_y, 0.0))
        z_shift = something(mods.refline_offset_z, 0.0)
    end

    c, s = cos(rot_angle), sin(rot_angle)
    dx, dy = r2.start_x - rot_center[1], r2.start_y - rot_center[2]
    new_start_x = rot_center[1] + dx*c - dy*s + translation[1]
    new_start_y = rot_center[2] + dx*s + dy*c + translation[2]
    new_start_phi = r2.start_phi + rot_angle
    phi .+= rot_angle
    new_start_z = r2.start_z + z_shift
    new_end_z = r2.end_z === nothing ? nothing : r2.end_z + z_shift
    new_end_x = r2.end_x === nothing ? nothing : rot_center[1] + (r2.end_x-rot_center[1])*c - (r2.end_y-rot_center[2])*s + translation[1]
    new_end_y = r2.end_y === nothing ? nothing : rot_center[2] + (r2.end_x-rot_center[1])*s + (r2.end_y-rot_center[2])*c + translation[2]
    new_end_phi = r2.end_phi === nothing ? nothing : r2.end_phi + rot_angle

    r3 = ReferenceLineParams(r2.start_u, new_end_u, r2.increment, new_start_x, new_start_y, new_start_phi,
        new_end_x, new_end_y, new_end_phi, new_start_z, new_end_z,
        r2.v_right, r2.v_left, r2.v_increment, r2.start_slope, r2.end_slope, r2.start_banking, r2.end_banking)

    return CRGData(data.comment, r3, data.format_code, data.opts, mods, data.mpro, phi, banking, slope, v, z)
end

"""
    road_surface_grid(data::CRGData) -> (u, v, X, Y, Z)

Apply `data`'s `\$ROAD_CRG_MODS` and compute world-frame grids of the road surface.
`u` (along the reference line) and `v` (positive left) are axis vectors in m;
`X`, `Y`, `Z` are `(length(u), length(v))` matrices.

Throws an error for unsupported modifiers (`REFPOINT_U*`/`REFPOINT_V*`, or
`REFPOINT_*` without an exact `v = 0` column) or if only one of
`REFERENCE_LINE_END_X`/`_END_Y` is set.

```julia
u, v, X, Y, Z = road_surface_grid(read_crg("road.crg"))
```
"""
function road_surface_grid(data::CRGData)
    d = apply_mods(data)
    nu = length(d.phi)
    u = [d.refline.start_u + (i-1)*d.refline.increment for i in 1:nu]
    x, y = integrate_reference_line(d.refline, d.phi)
    z_ref = integrate_reference_z(d.refline, d.slope, nu)
    X, Y = lateral_offset_grid(x, y, d.v)
    Z = assemble_z_grid(d.z, z_ref, d.banking, d.refline, d.v)
    return u, d.v, X, Y, Z
end
