# API reference

## OpenCRG.jl

```@autodocs
Modules = [OpenCRG]
Private = false
```

## LibOpenCRG.jl

```@autodocs
Modules = [LibOpenCRG]
Private = false
```

`close` and `isopen` extend `Base` for [`CRGData`](@ref LibOpenCRG.CRGData):

```@docs
Base.close(::LibOpenCRG.CRGData)
Base.isopen(::LibOpenCRG.CRGData)
```

### Raw C bindings

```@autodocs
Modules = [LibOpenCRG.C]
Private = false
```
