using Documenter
using CalculusWithJuliaSquared

makedocs(
    sitename="CalculusWithJuliaSquared",
    format = Documenter.HTML(),
    modules = [CalculusWithJuliaSquared],
    warnonly = Documenter.except(:autodocs_block)
)


# Documenter can also automatically deploy documentation to gh-pages.
# See "Hosting Documentation" and deploydocs() in the Documenter manual
# for more information.

deploydocs(
    repo = "github.com/FourMInfo/CalculusWithJuliaSquared.jl.git"
)
