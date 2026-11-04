# LibOpenCRG.jl

Julia wrapper for the [ASAM OpenCRG](https://www.asam.net/standards/detail/opencrg/)
C reference library (via [`OpenCRG_jll`](https://github.com/JuliaBinaryWrappers/OpenCRG_jll.jl)).
It lives in `lib/` of [OpenCRG.jl](https://github.com/JuliaIO/OpenCRG.jl), the
pure-Julia reader, and adds point evaluation (`uv2xy`, `xy2uv`, `uv2z`, `xy2z`,
`uv2pk`, `xy2pk`).

## Installation

```julia
using Pkg
Pkg.add(url="https://github.com/JuliaIO/OpenCRG.jl", subdir="lib/LibOpenCRG.jl")
```

## Main function

`read_crg(path)` loads a file and returns a `CRGData` handle to the C library's
data set. Use `read_crg(f, path)` to release it on exit, or call `close(data)`.
Handles are also released by finalizers; the C library is not thread-safe, so
calls are serialized with a lock, and finalizers never block.

## Quick start

From the root of a checkout:

```julia
using LibOpenCRG

read_crg("lib/LibOpenCRG.jl/test/data/handmade_curved_banked_sloped.crg") do data
    urange(data)                  # (0.0, 22.0)
    x, y = uv2xy(data, 10.0, 0.5) # road frame -> world: (9.93..., 0.99...)
    u, v = xy2uv(data, x, y)      # world -> road frame: (10.0, 0.5)
    uv2z(data, u, v)              # elevation: 0.561...
    uv2pk(data, u, v)             # heading, curvature: (0.099, 0.0110...)
    road_surface_grid(data)       # u, v, X, Y, Z, as in OpenCRG.jl
end
```

`read_crg`, `CRGData` and `road_surface_grid` share names with OpenCRG.jl's
exports; qualify them if you load both. The C library extrapolates or clamps
outside the road rather than failing; see the
[documentation](https://juliaio.github.io/OpenCRG.jl/stable) for details.

## License

MIT. The sample files in `test/data` come from upstream
[asam-ev/OpenCRG](https://github.com/asam-ev/OpenCRG) and are Apache-2.0
(see `test/data/LICENSE-APACHE-2.0` and `test/data/NOTICE`).
