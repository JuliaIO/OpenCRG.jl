# OpenCRG.jl

[ASAM OpenCRG](https://www.asam.net/standards/detail/opencrg/) (`.crg`) files
describe road surfaces as a *curved regular grid*: a reference line (position and
heading as a function of the distance `u` along the road) plus a regular grid of
elevations `z` over the lateral offset `v` from that line. OpenCRG.jl is a
pure-Julia reader for these files: it parses the header, decodes the ASCII and
binary payloads, applies the `$ROAD_CRG_MODS` modifiers and integrates the
reference line into world-frame `(X, Y, Z)` grids. No C library is needed.

```julia
using Pkg
Pkg.add("OpenCRG")
Pkg.add("DataInterpolationsND")
```

## Walkthrough

The examples use a sample file from the repository's `test/data` directory
(ASAM's `handmade_curved_banked_sloped.crg`, a 22 m long, 3 m wide curved,
banked and sloped road).

### Load a file

[`read_crg`](@ref OpenCRG.read_crg) parses a file and returns a
[`CRGData`](@ref OpenCRG.CRGData) holding all data from that file:

```@example walkthrough
using OpenCRG
using DataInterpolationsND

path = joinpath(pkgdir(OpenCRG), "test", "data", "handmade_curved_banked_sloped.crg")
data = OpenCRG.read_crg(path)
```

### Evaluate the surface on a grid

[`road_surface_grid`](@ref OpenCRG.road_surface_grid) applies the modifiers,
integrates the reference line and returns a grid `(u, v, X, Y, Z)`.

Here, `u` and `v` are vectors of along-track and across-track distance,
respectively. `X`, `Y`, `Z` are matrices of size `(length(u), length(v))` that
together define Cartesian positions of the surface of the road.

Positive `v` points left and negative `v` right, looking in the direction of
increasing `u`. Undefined cells are `NaN`.

```@example walkthrough
u, v, X, Y, Z = OpenCRG.road_surface_grid(data)
size(Z)
```

### Interpolate with DataInterpolationsND.jl

OpenCRG.jl only provides the grid. To evaluate it between nodes, use an
interpolation package, like
[Interpolations.jl](https://github.com/JuliaMath/Interpolations.jl) or
[DataInterpolationsND.jl](https://github.com/SciML/DataInterpolationsND.jl).
Interpolate the complete surface directly over both road-frame axes:

```@example walkthrough
dimensions = (LinearInterpolationDimension(u), LinearInterpolationDimension(v))
surface = NDInterpolation(cat(X, Y, Z; dims = 3), dimensions)
surface(10.5, 0.5)  # Cartesian [x, y, z]
```

The same interpolant gives the centre-line position at `u = 10.5` or a point
across the road at `u = 10`:

```@example walkthrough
surface(10.5, 0.0)
```

```@example walkthrough
surface(10.0, 0.5)
```

Evaluate inside the grid (`u` in `extrema(u)`, `v` in `extrema(v)`).

### Restrictions

`REFPOINT_U`, `REFPOINT_V` and their `_FRACTION` variants are not supported
(an error is thrown), `REFPOINT_X/Y/Z/PHI` need an exact `v = 0` long-section
column, `GRID_NAN_MODE`/`GRID_NAN_OFFSET` are parsed but ignored (NaN cells are
not filled), and `$ROAD_CRG_OPTS`/`$ROAD_CRG_MPRO` have no effect.
