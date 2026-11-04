using Pkg
# Develop both packages from this checkout, so the docs always match the source.
const ROOT = dirname(@__DIR__)
Pkg.develop([PackageSpec(path = ROOT),
             PackageSpec(path = joinpath(ROOT, "lib", "LibOpenCRG.jl"))])

using Documenter
using OpenCRG, LibOpenCRG

DocMeta.setdocmeta!(OpenCRG, :DocTestSetup, :(using OpenCRG); recursive = true)
DocMeta.setdocmeta!(LibOpenCRG, :DocTestSetup, :(using LibOpenCRG); recursive = true)

makedocs(;
    sitename = "OpenCRG.jl",
    modules = [OpenCRG, LibOpenCRG],
    authors = "Anshul Singhvi",
    checkdocs = :exports,
    doctest = true,
    warnonly = false,
    format = Documenter.HTML(;
        canonical = "https://juliaio.github.io/OpenCRG.jl",
        edit_link = "main",
        prettyurls = get(ENV, "CI", "false") == "true",
    ),
    pages = [
        "Home" => "index.md",
        "API reference" => "api.md",
    ],
)

deploydocs(;
    repo = "github.com/JuliaIO/OpenCRG.jl.git",
    devbranch = "main",
    push_preview = false,
)
