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

```julia
using Pkg
Pkg.add("OpenCRG")
```

The quick start below also needs `Pkg.add("DataInterpolationsND")`.

## Main function

`read_crg(path)` parses a file and returns a `CRGData` holding all data from
that file.

`road_surface_grid(data)` turns that into a grid `(u, v, X, Y, Z)`. Here, `u`
and `v` are vectors of along-track and across-track distance, respectively.
`X`, `Y`, `Z` are matrices of size `(length(u), length(v))` that together define
Cartesian positions of the surface of the road.

Positive `v` points left and negative `v` right, looking in the direction of
increasing `u`. Undefined cells are `NaN`.

## Quick start

Load a fixture and interpolate its surface directly with
[DataInterpolationsND.jl](https://github.com/SciML/DataInterpolationsND.jl).
OpenCRG.jl provides the grid; interpolation packages such as
[Interpolations.jl](https://github.com/JuliaMath/Interpolations.jl) or
DataInterpolationsND.jl evaluate it between nodes.

```julia
using OpenCRG, DataInterpolationsND

data = read_crg(joinpath(pkgdir(OpenCRG), "test", "data", "handmade_curved_banked_sloped.crg"))
u, v, X, Y, Z = road_surface_grid(data)

dimensions = (LinearInterpolationDimension(u), LinearInterpolationDimension(v))
surface = NDInterpolation(cat(X, Y, Z; dims = 3), dimensions)

surface(10.5, 0.5)  # Cartesian [x, y, z] at along-track 10.5 m, across-track 0.5 m
```

## LibOpenCRG.jl

[`lib/LibOpenCRG.jl`](lib/LibOpenCRG.jl) is a separate package that wraps the
upstream C library and adds point evaluation (`uv2xy`, `xy2z`, ...), which
OpenCRG.jl does not provide.

## Documentation

See the OpenCRG.jl [documentation](https://juliaio.github.io/OpenCRG.jl/stable) for the
supported modifiers, known limitations and out-of-domain behaviour.

## License

The code is MIT-licensed. The sample files in `test/data` from the upstream
[asam-ev/OpenCRG](https://github.com/asam-ev/OpenCRG) project are Apache-2.0
(see `test/data/LICENSE-APACHE-2.0` and `test/data/NOTICE`).

## Acknowledgement

This package was written with the help of generative AI.
