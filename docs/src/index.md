# OpenCRG.jl

[ASAM OpenCRG](https://www.asam.net/standards/detail/opencrg/) (`.crg`) files
describe road surfaces as a *curved regular grid*: a reference line (position and
heading as a function of the distance `u` along the road) plus a regular grid of
elevations `z` over the lateral offset `v` from that line. OpenCRG.jl is a
pure-Julia reader for these files: it parses the header, decodes the ASCII and
binary payloads, applies the `\$ROAD_CRG_MODS` modifiers and integrates the
reference line into world-frame `(X, Y, Z)` grids. No C library is needed.

```julia
using Pkg
Pkg.add("OpenCRG")
Pkg.add("DataInterpolations")
```

## Walkthrough

The examples use a sample file from the repository's `test/data` directory
(ASAM's `handmade_curved_banked_sloped.crg`, a 22 m long, 3 m wide curved,
banked and sloped road).

### Load a file

[`read_crg`](@ref OpenCRG.read_crg) parses the file into a [`CRGData`](@ref OpenCRG.CRGData):

```@example walkthrough
using OpenCRG
using DataInterpolations

path = joinpath(pkgdir(OpenCRG), "test", "data", "handmade_curved_banked_sloped.crg")
data = OpenCRG.read_crg(path);
```

It holds the header (`data.refline`, `data.mods`, ...), the per-`u` channels
(`data.phi` heading, `data.banking`, `data.slope`) and the elevation grid
`data.z` with its lateral axis `data.v`:

```@example walkthrough
(data.refline.start_u, data.refline.end_u, data.refline.increment)
```

```@example walkthrough
(size(data.z), data.v)
```

### Evaluate the surface on a grid

[`road_surface_grid`](@ref OpenCRG.road_surface_grid) applies the modifiers,
integrates the reference line and returns the world-frame grids; `X`, `Y`
and `Z` have size `(length(u), length(v))`:

```@example walkthrough
u, v, X, Y, Z = OpenCRG.road_surface_grid(data)
size(Z)
```

`u` and `v` are the road-frame coordinates: the distance along the track and
the distance across it (lateral offset from the reference line). `X`, `Y` and
`Z` are the Cartesian world-frame coordinates of each `(u, v)` grid node.

### Interpolate with DataInterpolations.jl

OpenCRG.jl only provides the grid. To evaluate it between nodes, hand the
columns and rows to an interpolation package, like
[Interpolations.jl](https://github.com/JuliaMath/Interpolations.jl) or
[DataInterpolationsND.jl](https://github.com/SciML/DataInterpolationsND.jl).
The examples below use 1D slices with
[DataInterpolations.jl](https://docs.sciml.ai/DataInterpolations/stable/).
Elevation along the reference line (the `v = 0` column):

```@example walkthrough
j = findfirst(==(0.0), v)
z_centre = LinearInterpolation(Z[:, j], u)
z_centre(10.5)
```

The world-frame path of the reference line, parametrised by `u`, with a smooth
spline:

```@example walkthrough
x_centre = CubicSpline(X[:, j], u)
y_centre = CubicSpline(Y[:, j], u)
(x_centre(10.5), y_centre(10.5))
```

And a cross-section (elevation across the road at `u = 10`):

```@example walkthrough
i = findfirst(==(10.0), u)
z_across = LinearInterpolation(Z[i, :], v)
z_across(0.5)
```

Interpolants are only valid inside the grid (`u` in `extrema(u)`, `v` in
`extrema(v)`); outside it DataInterpolations extrapolates or throws, depending
on its settings.

### Restrictions

`REFPOINT_U`, `REFPOINT_V` and their `_FRACTION` variants are not supported
(an error is thrown), `REFPOINT_X/Y/Z/PHI` need an exact `v = 0` long-section
column, `GRID_NAN_MODE`/`GRID_NAN_OFFSET` are parsed but ignored (NaN cells are
not filled), and `\$ROAD_CRG_OPTS`/`\$ROAD_CRG_MPRO` have no effect.
