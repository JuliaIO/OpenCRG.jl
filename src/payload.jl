
const ASCII_FIELD_WIDTH = Dict(:LRFI => 10, :LDFI => 20)
const FIELDS_PER_RECORD = Dict(:LRFI => 8, :LDFI => 4, :KRBI => 20, :KDBI => 10)

"""
    decode_ascii_field(raw) -> Float64

Decode one fixed-width ASCII payload field (`**unused**` → 0.0, non-numeric → NaN).
"""
function decode_ascii_field(raw::AbstractString)
    raw == "**unused**" && return 0.0
    s = strip(raw)
    if !all(c -> c in "0123456789+-.eEdD", s)
        return NaN
    end
    normalized = replace(replace(s, 'D' => 'e'), 'd' => 'e')
    v = tryparse(Float64, normalized)
    return v === nothing ? NaN : v
end

"""
    decode_ascii_payload(payload_lines, format_code, nchannels) -> Matrix{Float64}

Decode an ASCII (`:LRFI`/`:LDFI`) payload into an `(nu, nchannels)` matrix.
"""
function decode_ascii_payload(payload_lines::Vector{<:AbstractString}, format_code::Symbol, nchannels::Int)
    width = ASCII_FIELD_WIDTH[format_code]
    per_record = FIELDS_PER_RECORD[format_code]
    lines_per_row = cld(nchannels, per_record)
    rem(length(payload_lines), lines_per_row) == 0 ||
        error("ASCII payload has $(length(payload_lines)) lines, not a whole multiple of $lines_per_row lines/row for $nchannels channels at $format_code")
    nu = length(payload_lines) ÷ lines_per_row
    data = Matrix{Float64}(undef, nu, nchannels)
    line_idx = 0
    for row in 1:nu
        ch = 0
        for _ in 1:lines_per_row
            line_idx += 1
            line = payload_lines[line_idx]
            nfields_here = min(per_record, nchannels - ch)
            for f in 1:nfields_here
                lo = (f - 1) * width + 1
                hi = min(f * width, ncodeunits(line))
                field = lo <= ncodeunits(line) ? line[lo:hi] : ""
                ch += 1
                data[row, ch] = decode_ascii_field(field)
            end
        end
    end
    return data
end

struct UnrecognizedFormatError <: Exception
    format_code::Symbol
end

Base.showerror(io::IO, err::UnrecognizedFormatError) = print(io, "unrecognized CRG data format code: ", err.format_code)

"""
    decode_binary_payload(payload, format_code, nchannels) -> Matrix{Float64}

Decode a big-endian binary payload (`:KRBI`/`:KDBI`) into an `(nu, nchannels)` matrix.
"""
function decode_binary_payload(payload::AbstractVector{UInt8}, format_code::Symbol, nchannels::Int)
    format_code == :KRBI && return decode_binary_payload_typed(payload, Float32, nchannels)
    format_code == :KDBI && return decode_binary_payload_typed(payload, Float64, nchannels)
    throw(UnrecognizedFormatError(format_code))
end

function decode_binary_payload_typed(payload::AbstractVector{UInt8}, ::Type{T}, nchannels::Int) where {T<:Union{Float32,Float64}}
    esize = sizeof(T)
    row_bytes = nchannels * esize
    nu = length(payload) ÷ row_bytes
    needed = nu * row_bytes
    length(payload) - needed < 80 ||
        error("binary payload has $(length(payload) - needed) leftover bytes after $nu whole rows of $row_bytes bytes each — expected less than 80 bytes of end-of-payload padding, this looks like a truncated row")
    raw = reinterpret(T, Vector{UInt8}(payload[1:needed]))
    raw_be = ntoh.(raw)
    # File layout is row-major (channel fastest within a row); Julia's reshape
    # fills column-major, so reshape(flat, nchannels, nu) puts each file row
    # into one *column* first — transpose to get our (nu, nchannels) convention.
    return Float64.(permutedims(reshape(collect(raw_be), nchannels, nu)))
end

"""
    assemble_channels(raw, channels, refline) -> (phi, banking, slope, v, z)

Split the raw payload matrix into `(phi, banking, slope, v, z)`, sorting long sections by `v`.
"""
function assemble_channels(raw::Matrix{Float64}, channels::Vector{ChannelDef}, refline::ReferenceLineParams)
    nu = size(raw, 1)
    phi = fill(NaN, nu)
    banking = nothing
    slope = nothing
    long_idxs = Int[]
    for (i, c) in enumerate(channels)
        if c.kind == :phi
            phi = raw[:, i]
        elseif c.kind == :banking
            banking = raw[:, i]
        elseif c.kind == :slope
            slope = raw[:, i]
        elseif c.kind == :long_section
            push!(long_idxs, i)
        end
    end
    isempty(long_idxs) && error("no :long_section channels declared in \$KD_DEFINITION -- a CRG file must have elevation data")
    v_all = v_axis(channels, refline)
    order = sortperm(v_all)
    v = v_all[order]
    z = raw[:, long_idxs[order]]
    isempty(phi) || (phi = copy(phi); phi[1] = refline.start_phi)
    return phi, banking, slope, v, z
end
