# LibOpenCRG.jl

[![CI](https://github.com/JuliaIO/OpenCRG.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/JuliaIO/OpenCRG.jl/actions/workflows/CI.yml?query=branch%3Amain)
[![codecov](https://codecov.io/gh/JuliaIO/OpenCRG.jl/graph/badge.svg)](https://codecov.io/gh/JuliaIO/OpenCRG.jl)
[![Aqua QA](https://raw.githubusercontent.com/JuliaTesting/Aqua.jl/master/badge.svg)](https://github.com/JuliaTesting/Aqua.jl)

Julia wrapper for the [ASAM OpenCRG](https://www.asam.net/standards/detail/opencrg/)
C reference library (via [`OpenCRG_jll`](https://github.com/JuliaBinaryWrappers/OpenCRG_jll.jl)).
It lives in `lib/` of [OpenCRG.jl](https://github.com/JuliaIO/OpenCRG.jl), the
pure-Julia reader, and adds point evaluation (`uv2xy`, `xy2uv`, `uv2z`, `xy2z`,
`uv2pk`, `xy2pk`).

## Installation

```julia
using Pkg
Pkg.add("LibOpenCRG")
```

## Main function

`read_crg(path)` loads a file and returns a `CRGData` handle holding all data
from that file. Use `read_crg(f, path)` to release it on exit, or call `close(data)`.

`road_surface_grid(data)` turns that into a grid `(u, v, X, Y, Z)`. Here, `u`
and `v` are vectors of along-track and across-track distance, respectively.
`X`, `Y`, `Z` are matrices of size `(length(u), length(v))` that together define
Cartesian positions of the surface of the road.

Positive `v` points left and negative `v` right, looking in the direction of
increasing `u`.

Handles are also released by finalizers; the C library is not thread-safe, so
calls are serialized with a lock, and finalizers never block.

## Quick start

Also needs `Pkg.add("DataInterpolationsND")` to interpolate the surface directly.
The grid can be handed to an interpolation package, like
[Interpolations.jl](https://github.com/JuliaMath/Interpolations.jl) or
[DataInterpolationsND.jl](https://github.com/SciML/DataInterpolationsND.jl).

```julia
using LibOpenCRG, DataInterpolationsND

read_crg(joinpath(pkgdir(LibOpenCRG), "test", "data", "handmade_curved_banked_sloped.crg")) do data
    urange(data)                  # (0.0, 22.0)
    x, y = uv2xy(data, 10.0, 0.5) # road frame -> world: (9.93..., 0.99...)
    u, v = xy2uv(data, x, y)      # world -> road frame: (10.0, 0.5)
    uv2z(data, u, v)              # elevation: 0.561...
    uv2pk(data, u, v)             # heading, curvature: (0.099, 0.0110...)
    u, v, X, Y, Z = road_surface_grid(data)
    dimensions = (LinearInterpolationDimension(u), LinearInterpolationDimension(v))
    surface = NDInterpolation(cat(X, Y, Z; dims = 3), dimensions)
    surface(10.5, 0.5)           # Cartesian [x, y, z] between grid nodes
end
```

`read_crg`, `CRGData` and `road_surface_grid` share names with OpenCRG.jl's
exports; qualify them if you load both. The C library extrapolates or clamps
outside the road rather than failing.

## License

MIT. The sample files in `test/data` come from upstream
[asam-ev/OpenCRG](https://github.com/asam-ev/OpenCRG) and are Apache-2.0
(see `test/data/LICENSE-APACHE-2.0` and `test/data/NOTICE`).

## Acknowledgement

This package was written with the help of generative AI.
