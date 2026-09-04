using Documenter
using CalculusWithJuliaSquared

# LOCAL PREVIEW ONLY -- there is deliberately no `deploydocs` here, and no documentation
# workflow in `.github/workflows/`.
#
# This package does not publish a documentation site of its own. Its API reference is
# published as part of the `Calculus` docs, whose `make.jl` pulls these same docstrings via
# `@autodocs Modules = [CalculusWithJuliaSquared]` and deploys, like every other repo in
# this family, into `math_tech_study` -- which is what serves <https://fourm.info>.
# See <https://fourm.info/calculus/dev/API/CalculusWithJuliaSquared/>.
#
# What this file is for: checking a docstring renders before it goes anywhere. Build with
#
#     julia --project=docs -e 'using Pkg; Pkg.instantiate()'
#     julia --project=docs docs/make.jl
#
# then open `docs/build/index.html`. `docs/Project.toml` sources the package at `..`, so
# the preview always reflects the working tree, including uncommitted docstring edits.
#
# The published page is rendered by `Calculus`, not by this file, so treat this as a
# well-formedness check on the docstrings rather than a preview of the final page.

makedocs(
    sitename="CalculusWithJuliaSquared",
    format = Documenter.HTML(),
    modules = [CalculusWithJuliaSquared],
    warnonly = Documenter.except(:autodocs_block)
)
