# OpenCRG.jl

A pure-Julia reader for [ASAM OpenCRG](https://www.asam.net/standards/detail/opencrg/)
(`.crg`) road surface files. It parses the header sections, decodes ASCII
(`LRFI`/`LDFI`) and binary (`KRBI`/`KDBI`) payloads, applies `$ROAD_CRG_MODS`,
and integrates the reference line to produce world-frame `(X, Y, Z)` grids.
No C library is required.

## Installation

```julia
using Pkg
Pkg.add("OpenCRG")
```

## Example

```julia
using OpenCRG

data = read_crg("road.crg")            # ::CRGData (header, channels, z-grid)
u, v, X, Y, Z = road_surface_grid(data) # world-frame grids, size (length(u), length(v))
```

## Scope

Reference-line integration, lateral offsetting, elevation/banking assembly and
`REFLINE_*`/`REFPOINT_*`/`SCALE_*` modifiers are implemented and were
cross-validated against the upstream C reference library. Interpolated
point evaluation (`uv2xy`, `xy2z`, ...) is not provided. `$ROAD_CRG_OPTS` and
`$ROAD_CRG_MPRO` are parsed but have no effect.

## LibOpenCRG.jl

This repository also hosts a second package, [`LibOpenCRG.jl`](lib/LibOpenCRG.jl),
in `lib/LibOpenCRG.jl`. It wraps the upstream OpenCRG C reference library
(through [`OpenCRG_jll`](https://github.com/JuliaBinaryWrappers/OpenCRG_jll.jl))
behind an interface similar to OpenCRG.jl's (`read_crg`, `CRGData`,
`road_surface_grid`) and adds the point evaluation functions that OpenCRG.jl
does not provide: `uv2xy`, `xy2uv`, `uv2z`, `xy2z`, `uv2pk`, `xy2pk`. The raw
`ccall` bindings are available as `LibOpenCRG.C`. OpenCRG.jl itself stays
pure Julia and does not depend on LibOpenCRG; its tests cross-validate against
the C library through a small private helper in `test/helpers`.

```julia
using Pkg; Pkg.add("LibOpenCRG")
using LibOpenCRG
read_crg("road.crg") do data
    x, y = uv2xy(data, 10.0, 0.5)
    z = xy2z(data, x, y)
end
```

## Test data and licensing

The code in this repository is MIT-licensed; the test data is not uniformly so.
The `.crg` files in `test/data/` named
`handmade_*` and `belgian_block.crg` are sample files from the upstream
[asam-ev/OpenCRG](https://github.com/asam-ev/OpenCRG) project, distributed under
the Apache License 2.0 (see the notice at the top of each file;
`belgian_block.crg` data courtesy of DaimlerChrysler, 2005). The `synthetic_*`
files were created for this package's tests. See `test/data/README.md`, `test/data/LICENSE-APACHE-2.0` and
`test/data/NOTICE` (upstream's notice). The Apache-2.0 sample files are used only
for testing and are not part of the code's MIT license.
