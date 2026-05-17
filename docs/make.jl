using Documenter
using Martini

DocMeta.setdocmeta!(Martini, :DocTestSetup, :(using Martini); recursive = true)

makedocs(
    sitename = "Martini.jl",
    modules = [Martini],
    authors = "Anshul Singhvi <anshulsinghvi@gmail.com> and contributors",
    repo = Documenter.Remotes.GitHub("JuliaGeo", "Martini.jl"),
    format = Documenter.HTML(
        canonical = "https://JuliaGeo.github.io/Martini.jl/stable/",
        prettyurls = get(ENV, "CI", "false") == "true",
        edit_link = "main",
    ),
    pages = [
        "Home" => "index.md",
        "API Reference" => "api.md",
    ],
    warnonly = [:missing_docs],
)

deploydocs(
    repo = "github.com/JuliaGeo/Martini.jl",
    devbranch = "main",
    push_preview = true,
)
