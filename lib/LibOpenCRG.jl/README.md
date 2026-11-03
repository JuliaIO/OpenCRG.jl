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
them (finalizers never block: if another thread is using the library the
release is retried at a later GC). The C library has global state and is not
thread-safe; calls are serialized with a lock.

### Out-of-domain behaviour

The C library generally extrapolates or clamps instead of failing, so do not
rely on `NaN` to detect points off the road (compare against `urange`/`vrange`
yourself):

| function | outside the road |
|---|---|
| `uv2xy`, `xy2uv` | extrapolated (reference line continued beyond `u` range, lateral offset beyond `v` range); `NaN` only if the C call reports failure |
| `uv2z`, `xy2z` | clamped to the nearest grid edge; `NaN` for undefined (NaN) grid cells |
| `uv2pk`, `xy2pk` | heading/curvature of the extrapolated reference line; `NaN` only on C failure |

### `road_surface_grid` restriction

`road_surface_grid` rebuilds the `v` axis from the lateral range and a uniform
increment, so roads with non-uniform (explicit) `v` sections throw an error.
Nodes the C library reports as undefined are `NaN`.

`read_crg`, `CRGData` and `road_surface_grid` share names with OpenCRG.jl's
exports; qualify them if you load both packages.

The raw bindings, one-to-one with `crgBaseLib.h`, are in `LibOpenCRG.C`
(e.g. `LibOpenCRG.C.crgLoaderReadFile`), including the modifier functions,
for which there is no high-level interface yet.

## Tests

The tests use two small sample files copied into `test/data/` (Apache-2.0, with
their license and NOTICE; see `test/data/README.md`), so they run from this
directory alone. They include a multithreaded finalizer test; run with
`JULIA_NUM_THREADS=2` (or more) to exercise it across threads.
