"""
    LibOpenCRG

Wrapper around the ASAM OpenCRG C library (via `OpenCRG_jll`) with the same
interface as `OpenCRG.jl` (`read_crg`, `CRGData`, `road_surface_grid`), plus
point evaluation (`uv2xy`, `xy2uv`, `uv2z`, `xy2z`, `uv2pk`, `xy2pk`).
The raw `ccall` layer is the submodule [`LibOpenCRG.C`](@ref).

!!! note
    These names clash with `OpenCRG.jl`'s exports; qualify them if you load both.
    Calls into the (non-thread-safe) C library are serialized with a lock.
"""
module LibOpenCRG

include("C.jl")

export CRGData, read_crg, road_surface_grid,
       uv2xy, xy2uv, uv2z, xy2z, uv2pk, xy2pk,
       urange, vrange, increments, isclosedtrack

# The C library is global and non-reentrant.
const LOCK = ReentrantLock()

"""
    set_message_level(level::Integer)

Set the C library's message verbosity (0 = none ... 5 = debug). Defaults to 2 (warnings) on load.
"""
set_message_level(level::Integer) = lock(() -> C.crgMsgSetLevel(level), LOCK)

function __init__()
    set_message_level(2)
end

"""
    CRGData

A road loaded by the C library with [`read_crg`](@ref). Released on garbage
collection or with `close(data)`; using a closed `CRGData` throws an `ArgumentError`.
"""
mutable struct CRGData
    path::String
    dataset::Cint
    contact_point::Cint

    function CRGData(path::String, dataset::Cint, cp::Cint)
        d = new(path, dataset, cp)
        finalizer(_finalize!, d)
        return d
    end
end

# Finalizers may run at any allocation, on any thread, while another task holds
# `LOCK` and is inside the (non-thread-safe) C library, so they must neither
# touch the C library unlocked nor block or switch tasks waiting for `LOCK`
# (see "Safe use of Finalizers" in the Julia manual). Take the lock with
# `trylock`; if it is busy, re-register this finalizer so the handle is retried
# at a later GC rather than leaked. An explicit `close` makes this a no-op.
function _finalize!(d::CRGData)
    if trylock(LOCK)
        try
            _release!(d)
        finally
            unlock(LOCK)
        end
    else
        finalizer(_finalize!, d)
    end
    return nothing
end

# Idempotent (a released handle is marked by -1/0 and never freed twice).
# Callers must hold `LOCK`.
function _release!(d::CRGData)
    if d.contact_point >= 0
        C.crgContactPointDelete(d.contact_point)
        d.contact_point = -1
    end
    if d.dataset > 0
        C.crgDataSetRelease(d.dataset)
        d.dataset = 0
    end
    return nothing
end

"""
    isopen(data::CRGData) -> Bool

Whether the native resources of `data` are still alive.
"""
Base.isopen(d::CRGData) = d.dataset > 0

"""
    close(data::CRGData)

Release the native data set and contact point immediately. Idempotent.
"""
function Base.close(d::CRGData)
    lock(LOCK) do
        _release!(d)
    end
    return nothing
end

Base.show(io::IO, d::CRGData) =
    print(io, "LibOpenCRG.CRGData(", repr(d.path), isopen(d) ? "" : ", closed", ")")

function _check(d::CRGData)
    isopen(d) || throw(ArgumentError("CRGData for $(repr(d.path)) has been closed"))
    return d
end

"""
    read_crg(path) -> CRGData
    read_crg(f, path)

Load and consistency-check the `.crg` file at `path` with the C library.
Throws if the file is missing, cannot be parsed, or fails the check.
The second form returns `f(data)` and closes `data` afterwards.

```julia
z = read_crg("road.crg") do data
    uv2z(data, 10.0, 0.0)
end
```
"""
function read_crg(path::AbstractString)
    path = String(path)
    isfile(path) || throw(ArgumentError("CRG file not found: $(repr(path))"))
    lock(LOCK) do
        ds = C.crgLoaderReadFile(path)
        ds > 0 || error("failed to load CRG file $(repr(path))")
        if C.crgCheck(ds) == 0
            C.crgDataSetRelease(ds)
            error("CRG file $(repr(path)) failed the OpenCRG consistency check")
        end
        cp = C.crgContactPointCreate(ds)
        if cp < 0
            C.crgDataSetRelease(ds)
            error("failed to create a contact point for $(repr(path))")
        end
        return CRGData(path, ds, cp)
    end
end

function read_crg(f::Function, path::AbstractString)
    data = read_crg(path)
    try
        return f(data)
    finally
        close(data)
    end
end

function _query(f, d::CRGData, _)
    _check(d)
    return lock(LOCK) do
        _check(d)
        res = GC.@preserve d f()
        res.status == 0 ? nothing : res
    end
end

"""
    urange(data) -> (umin, umax)

The longitudinal (`u`) extent of the road, in meters.
"""
function urange(d::CRGData)
    r = _query(() -> C.crgDataSetGetURange(d.dataset), d, "u range")
    r === nothing && error("could not get u range")
    return (r.uMin, r.uMax)
end

"""
    vrange(data) -> (vmin, vmax)

The lateral (`v`) extent of the road, in meters.
"""
function vrange(d::CRGData)
    r = _query(() -> C.crgDataSetGetVRange(d.dataset), d, "v range")
    r === nothing && error("could not get v range")
    return (r.vMin, r.vMax)
end

"""
    increments(data) -> (du, dv)

The grid increments in `u` and `v`. `dv` is 0 if the lateral grid is
non-uniform (explicit `v` positions).
"""
function increments(d::CRGData)
    r = _query(() -> C.crgDataSetGetIncrements(d.dataset), d, "increments")
    r === nothing && error("could not get increments")
    return (r.uInc, r.vInc)
end

"""
    isclosedtrack(data) -> Bool

Whether the reference line forms a closed track.
"""
function isclosedtrack(d::CRGData)
    r = _query(() -> C.crgDataSetGetUtilityDataClosedTrack(d.dataset), d, "closed track")
    r === nothing && error("could not get closed track data")
    return r.uIsClosed != 0
end

# Shared plumbing for the point evaluators: NaN-filled outputs when the point
# lies outside the defined road (C status 0).
function _eval(cfun, d::CRGData, a::Real, b::Real, ::Val{N}) where {N}
    r = _query(() -> cfun(d.contact_point, a, b), d, "evaluation")
    r === nothing && return ntuple(_ -> NaN, Val(N))
    return Base.tail(Tuple(r))
end

"""
    uv2xy(data, u, v) -> (x, y)

World coordinates of road-frame `(u, v)`. Points outside the road are
extrapolated, not `NaN`; `NaN`s only if the C library fails.
"""
uv2xy(d::CRGData, u::Real, v::Real) = _eval(C.crgEvaluv2xy, d, u, v, Val(2))

"""
    xy2uv(data, x, y) -> (u, v)

Road-frame coordinates of world `(x, y)`. Off-road points are extrapolated like
[`uv2xy`](@ref), so the result may lie outside [`urange`](@ref)/[`vrange`](@ref).
"""
xy2uv(d::CRGData, x::Real, y::Real) = _eval(C.crgEvalxy2uv, d, x, y, Val(2))

"""
    uv2z(data, u, v) -> z

Bilinearly interpolated elevation (m) at road-frame `(u, v)`. Clamps to the
grid edge outside the road; `NaN` for undefined grid cells.
"""
uv2z(d::CRGData, u::Real, v::Real) = only(_eval(C.crgEvaluv2z, d, u, v, Val(1)))

"""
    xy2z(data, x, y) -> z

Elevation (m) at world `(x, y)`; same out-of-road behaviour as [`uv2z`](@ref).
"""
xy2z(d::CRGData, x::Real, y::Real) = only(_eval(C.crgEvalxy2z, d, x, y, Val(1)))

"""
    uv2pk(data, u, v) -> (heading, curvature)

Heading (rad) and curvature (1/m) at road-frame `(u, v)`, from the
extrapolated reference line outside the `u` range.
"""
uv2pk(d::CRGData, u::Real, v::Real) = _eval(C.crgEvaluv2pk, d, u, v, Val(2))

"""
    xy2pk(data, x, y) -> (heading, curvature)

Heading (rad) and curvature (1/m) at world `(x, y)`; see [`uv2pk`](@ref).
"""
xy2pk(d::CRGData, x::Real, y::Real) = _eval(C.crgEvalxy2pk, d, x, y, Val(2))

"""
    road_surface_grid(data) -> (u, v, X, Y, Z)

World-frame road surface grids, as in `OpenCRG.road_surface_grid`: axis vectors
`u`, `v` and `(length(u), length(v))` matrices `X`, `Y`, `Z`, `NaN` where undefined.
Throws an error for roads with non-uniform `v` sections.
"""
function road_surface_grid(d::CRGData)
    umin, umax = urange(d)
    vmin, vmax = vrange(d)
    du, dv = increments(d)
    dv > 0 || error("road_surface_grid: non-uniform v sections are not supported")
    u = collect(range(umin; step = du, length = round(Int, (umax - umin) / du) + 1))
    v = collect(range(vmin; step = dv, length = round(Int, (vmax - vmin) / dv) + 1))
    X = fill(NaN, length(u), length(v))
    Y = similar(X)
    Z = similar(X)
    for j in eachindex(v), i in eachindex(u)
        X[i, j], Y[i, j] = uv2xy(d, u[i], v[j])
        Z[i, j] = uv2z(d, u[i], v[j])
    end
    return u, v, X, Y, Z
end

end # module LibOpenCRG
