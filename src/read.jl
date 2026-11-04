
"""
    CRGData

All data parsed from an OpenCRG file by [`read_crg`](@ref). Fields:

- `comment`: `\$CT` comment lines, joined with newlines
- `refline`: reference-line and long-section parameters from `\$ROAD_CRG`
- `format_code`: payload format, one of `:LRFI`, `:LDFI`, `:KRBI`, `:KDBI`
- `opts`: numeric `\$ROAD_CRG_OPTS` entries, keyed by upper-cased name
- `mods`: `\$ROAD_CRG_MODS` modifiers (applied by [`road_surface_grid`](@ref), not here)
- `mpro`: `\$ROAD_CRG_MPRO` projection entries as strings (parsed, never applied)
- `phi`: reference-line heading at each `u` row (rad); `phi[1]` is the start heading
- `banking`: cross slope at each `u` row (m/m), or `nothing` if absent
- `slope`: longitudinal slope at each `u` row (m/m), or `nothing` if absent
- `v`: lateral positions of the long sections, ascending (m, positive left)
- `z`: raw `(nu, nv)` elevation grid relative to the reference line (m); columns match `v`
"""
struct CRGData
    comment::String
    refline::ReferenceLineParams
    format_code::Symbol
    opts::Dict{String,Float64}
    mods::RoadCrgMods
    mpro::Dict{String,String}
    phi::Vector{Float64}
    banking::Union{Vector{Float64},Nothing}
    slope::Union{Vector{Float64},Nothing}
    v::Vector{Float64}
    z::Matrix{Float64}
end

"""
    read_crg(path) -> CRGData

Parse the OpenCRG `.crg` file at `path`. The row count comes from the payload
size. Throws an error if the file declares no channels or no long sections,
or if the payload is truncated or has an unknown format.
"""
function read_crg(path::AbstractString)
    bytes = read(path)
    header_end = find_header_end(bytes)
    header_lines = split_lines(bytes[1:header_end-1])
    payload = bytes[header_end:end]
    sections = group_sections(header_lines)

    comment = join(get(sections, "CT", String[]), "\n")
    refline = parse_road_crg(get(sections, "ROAD_CRG", String[]))
    format_code, channels = parse_kd_definition(get(sections, "KD_DEFINITION", String[]))
    opts = parse_keyvalues(get(sections, "ROAD_CRG_OPTS", String[]))
    mods = parse_road_crg_mods(get(sections, "ROAD_CRG_MODS", String[]))
    mpro = parse_keyvalue_strings(get(sections, "ROAD_CRG_MPRO", String[]))

    nchannels = length(channels)
    nchannels == 0 && error("no channels declared in \$KD_DEFINITION (section missing or empty) -- not a valid CRG file")
    raw = if format_code in (:LRFI, :LDFI)
        decode_ascii_payload(split_lines(payload), format_code, nchannels)
    else
        decode_binary_payload(payload, format_code, nchannels)
    end
    phi, banking, slope, v, z = assemble_channels(raw, channels, refline)

    return CRGData(comment, refline, format_code, opts, mods, mpro, phi, banking, slope, v, z)
end
