# Display the stored (unmodified) data, without constructing surface grids.
# All fields traversed here have concrete types or small concrete unions.
function _show_comment(io::IO, text::String, width::Int)
    print(io, '"')
    started = false
    count = 0
    for c in text
        if c == '\n' || c == '\r'
            started && break
            continue
        end
        !started && isspace(c) && continue
        started = true
        if count == width
            print(io, '…')
            break
        end
        if c == '"' || c == '\\'
            print(io, '\\')
        end
        print(io, iscntrl(c) ? ' ' : c)
        count += 1
    end
    print(io, '"')
end

_show_u_end(d::CRGData) = d.refline.start_u + max(0, size(d.z, 1) - 1) * d.refline.increment

function Base.show(io::IO, d::CRGData)
    print(io, "CRGData(")
    _show_comment(io, d.comment, get(io, :compact, false) === true ? 32 :
        get(io, :limit, false) === true ? 48 : 80)
    # Keep print calls short: Base's heterogeneous Vararg fallback erases
    # argument types on long calls, which is incompatible with --trim=safe.
    print(io, ", ", size(d.z, 1))
    print(io, '×', size(d.z, 2))
    print(io, " grid, u ∈ ")
    _show_range(io, d.refline.start_u, _show_u_end(d))
    print(io, " m)")
end

function _show_range(io::IO, lo::Float64, hi::Float64)
    print(io, '[')
    print(io, lo)
    print(io, ", ")
    print(io, hi)
    print(io, ']')
end

function _show_v(io::IO, v::Vector{Float64})
    if isempty(v)
        print(io, "empty")
        return
    end
    lo, hi = extrema(v)
    _show_range(io, lo, hi)
    print(io, " m; increment: ")
    if length(v) < 2
        print(io, "n/a")
        return
    end
    step = v[2] - v[1]
    uniform = true
    for i in 3:length(v)
        uniform &= isapprox(v[i] - v[i-1], step; atol = 1e-12, rtol = 1e-8)
    end
    uniform ? print(io, step, " m") : print(io, "nonuniform")
end

# Geometric closure of the raw reference line. This does not imply that the
# C library's optional track-extension policy is enabled. Integrate only the
# endpoint when no endpoint anchor is present, using the arrival-heading rule.
function _show_closed(io::IO, d::CRGData)
    r = d.refline
    if length(d.phi) < 2 || xor(r.end_x === nothing, r.end_y === nothing)
        print(io, "unknown")
        return
    end
    dx = 0.0
    dy = 0.0
    if r.end_x !== nothing && r.end_y !== nothing
        dx = r.end_x - r.start_x
        dy = r.end_y - r.start_y
    else
        for i in 2:length(d.phi)
            dx += r.increment * cos(d.phi[i])
            dy += r.increment * sin(d.phi[i])
        end
    end
    tolerance = 1e-8 * max(1.0, abs(_show_u_end(d) - r.start_u))
    print(io, hypot(dx, dy) <= tolerance ? "yes" : "no")
end

function _show_settings(io::IO, mods::RoadCrgMods, opts::Dict{String,Float64}, limit::Bool)
    print(io, "\n  Modifiers: ")
    count = 0
    for name in fieldnames(RoadCrgMods)
        value = getfield(mods, name)
        value === nothing && continue
        count > 0 && print(io, ", ")
        if limit && count == 4
            print(io, '…')
            break
        end
        print(io, name, '=')
        # Explicit narrowing also keeps the display call graph concrete.
        if value isa Float64
            print(io, value)
        elseif value isa Int
            print(io, value)
        end
        count += 1
    end
    count == 0 && print(io, "none")
    print(io, "\n  Options: ")
    count = 0
    for (name, value) in opts
        count > 0 && print(io, ", ")
        if limit && count == 4
            print(io, '…')
            break
        end
        _show_comment(io, name, limit ? 48 : 80)
        print(io, '=', value)
        count += 1
    end
    count == 0 && print(io, "none")
end

function Base.show(io::IO, ::MIME"text/plain", d::CRGData)
    if get(io, :compact, false) === true
        show(io, d)
        return
    end
    limited = get(io, :limit, false) === true
    print(io, "CRGData (stored data, before modifiers)\n  Grid: ", size(d.z, 1))
    print(io, " × ", size(d.z, 2))
    print(io, " points (u × v)\n  u: ")
    _show_range(io, d.refline.start_u, _show_u_end(d))
    print(io, " m; increment: ", d.refline.increment)
    print(io, " m\n  v: ")
    _show_v(io, d.v)
    print(io, "\n  Channels: reference-line x/y (integrated from phi), phi; elevation z")
    d.banking !== nothing && print(io, "; banking")
    d.slope !== nothing && print(io, "; slope")
    print(io, "\n  z range (raw): ")
    lo, hi = Inf, -Inf
    for z in d.z
        isnan(z) && continue
        lo = min(lo, z)
        hi = max(hi, z)
    end
    if lo > hi
        print(io, "no defined cells")
    else
        _show_range(io, lo, hi)
        print(io, " m")
    end
    print(io, "\n  Reference line closed (coincident endpoints): ")
    _show_closed(io, d)
    _show_settings(io, d.mods, d.opts, limited)
    print(io, "\n  Comment: ")
    _show_comment(io, d.comment, limited ? 80 : 160)
end
