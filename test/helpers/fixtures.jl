# Helpers for building temporary variants of the sample files in test/data.

const DATA = joinpath(@__DIR__, "..", "data")
fixture(name) = joinpath(DATA, name)

"""
    tmpcrg(bytes) -> path

Write `bytes` (or a string) to a fresh temporary `.crg` file.
"""
function tmpcrg(bytes)
    path = tempname() * ".crg"
    write(path, bytes)
    return path
end

"""
    edited(name, pairs...) -> path

A temporary copy of the sample file `name` with `replace(text, pairs...)` applied.
"""
edited(name, pairs...) = tmpcrg(replace(read(fixture(name), String), pairs...))

"""
    with_mods(name, mods::Pair...) -> path

A temporary copy of the sample file `name` with a `\$ROAD_CRG_MODS` section
(`KEY = value` for each pair) prepended to its header.
"""
function with_mods(name, mods::Pair...)
    block = "\$ROAD_CRG_MODS\n" * join(("$k = $v\n" for (k, v) in mods)) * "\$\n"
    return tmpcrg(vcat(Vector{UInt8}(block), read(fixture(name))))
end
