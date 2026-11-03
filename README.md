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

## Test data and licensing

This package is MIT-licensed. The `.crg` files in `test/data/` named
`handmade_*` and `belgian_block.crg` are sample files from the upstream
[asam-ev/OpenCRG](https://github.com/asam-ev/OpenCRG) project, distributed under
the Apache License 2.0 (see the notice at the top of each file;
`belgian_block.crg` data courtesy of DaimlerChrysler, 2005). The `synthetic_*`
files were created for this package's tests. See `test/data/README.md`.
