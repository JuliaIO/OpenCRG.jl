# LibOpenCRG.jl

Julia wrapper for the [ASAM OpenCRG](https://www.asam.net/standards/detail/opencrg/)
C reference library (via [`OpenCRG_jll`](https://github.com/JuliaBinaryWrappers/OpenCRG_jll.jl)),
with an interface modelled on the pure-Julia
[OpenCRG.jl](https://github.com/JuliaIO/OpenCRG.jl) in the repository root.
Use LibOpenCRG when you need the reference implementation's point evaluation
(`uv2xy`, `xy2z`, heading/curvature, ...) or want bit-for-bit upstream behaviour.

## Usage

```julia
using LibOpenCRG

read_crg("road.crg") do data          # released on exit; or `data = read_crg(...)` + `close(data)`
    umin, umax = urange(data)
    x, y = uv2xy(data, 10.0, 0.5)     # road frame -> world
    u, v = xy2uv(data, x, y)          # world -> road frame
    z = uv2z(data, u, v)              # elevation (also xy2z)
    heading, curvature = uv2pk(data, u, v)   # also xy2pk
    u, v, X, Y, Z = road_surface_grid(data)
end
```

`CRGData` handles are also released by finalizers if you forget to `close`
them. Out-of-domain evaluations return `NaN`s. The C library has global state
and is not thread-safe; calls are serialized with a lock.

`read_crg`, `CRGData` and `road_surface_grid` share names with OpenCRG.jl's
exports; qualify them if you load both packages.

The raw bindings, one-to-one with `crgBaseLib.h`, are in `LibOpenCRG.C`
(e.g. `LibOpenCRG.C.crgLoaderReadFile`), including the modifier functions,
for which there is no high-level interface yet.

## Tests

The tests use the sample files in the repository root's `test/data`, so run
them from a repository checkout.
