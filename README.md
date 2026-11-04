# OpenCRG.jl

[![CI](https://github.com/JuliaIO/OpenCRG.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/JuliaIO/OpenCRG.jl/actions/workflows/CI.yml?query=branch%3Amain)
[![Docs stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://juliaio.github.io/OpenCRG.jl/stable)
[![Docs dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://juliaio.github.io/OpenCRG.jl/dev)
[![codecov](https://codecov.io/gh/JuliaIO/OpenCRG.jl/graph/badge.svg)](https://codecov.io/gh/JuliaIO/OpenCRG.jl)
[![Aqua QA](https://raw.githubusercontent.com/JuliaTesting/Aqua.jl/master/badge.svg)](https://github.com/JuliaTesting/Aqua.jl)

A pure-Julia reader for [ASAM OpenCRG](https://www.asam.net/standards/detail/opencrg/)
`.crg` files: high-resolution road surface elevation on a curved reference line,
addressed in a road-aligned `(u, v)` frame (`u` along the line, `v` across it).

## Installation

OpenCRG.jl is not yet in the General registry:

```julia
using Pkg
Pkg.add(url="https://github.com/JuliaIO/OpenCRG.jl")
```

Once registered, `Pkg.add("OpenCRG")` will work.

## Main function

`read_crg(path)` parses a file and returns a `CRGData` holding the header
(`refline`, `mods`, `opts`, `mpro`, `comment`), the reference-line heading `phi`,
optional `banking` and `slope` channels, the lateral axis `v`, and the elevation
grid `z`. `road_surface_grid(data)` turns that into world-frame grids
`(u, v, X, Y, Z)`, where `u` and `v` are axis vectors and `X`, `Y`, `Z` are
`(length(u), length(v))` matrices. Undefined cells are `NaN`.

## Quick start

Load a fixture and interpolate the centre-line elevation with
[DataInterpolations.jl](https://github.com/SciML/DataInterpolations.jl):

```julia
using OpenCRG, DataInterpolations

data = read_crg("test/data/handmade_curved_banked_sloped.crg")
u, v, X, Y, Z = road_surface_grid(data)

j = findfirst(==(0.0), v)           # centre-line column
profile = CubicSpline(Z[:, j], u)   # elevation along the road
path = CubicSpline(hcat(X[:, j], Y[:, j])', u)  # world (x, y) along the road

profile(10.5)  # 0.5719...
path(10.5)     # [x, y]
```

## LibOpenCRG.jl

[`lib/LibOpenCRG.jl`](lib/LibOpenCRG.jl) is a separate package that wraps the
upstream C library and adds point evaluation (`uv2xy`, `xy2z`, ...), which
OpenCRG.jl does not provide.

## Documentation

See the [documentation](https://juliaio.github.io/OpenCRG.jl/stable) for the
supported modifiers, known limitations and out-of-domain behaviour.

## License

The code is MIT-licensed. The sample files in `test/data` from the upstream
[asam-ev/OpenCRG](https://github.com/asam-ev/OpenCRG) project are Apache-2.0
(see `test/data/LICENSE-APACHE-2.0` and `test/data/NOTICE`).
