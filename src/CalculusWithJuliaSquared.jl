"""
    CalculusWithJuliaSquared

A personal, pure-Julia fork of `CalculusWithJulia.jl` to accompany notes at [https://calculuswithjulia.github.io](https://calculuswithjulia.github.io) on using Julia for topics from the calculus sequence.

This package does two things:

* It loads a few other packages making it easier to use (and install) the functionality provided by them and

* It defines a handful of functions for convenience. The exported ones
are `unzip`, `rangeclamp` `tangent`, `secant`, `D` (and the prime
notation), `divergence`, `gradient`, `curl`, and `∇`, along with some plotting
functions. The constant `e` is assigned to `exp(1)`.


## Packages loaded by `CalculusWithJuliaSquared`

* The `SpecialFunctions` is loaded giving access to a few special functions used in these notes, e.g., `airyai`, `gamma`

* The `ForwardDiff` package is loaded giving access to its  `derivative`,  `gradient`, `jacobian`, and `hessian` functions for finding automatic derivatives of functions. In addition, this package defines `'` (for functions) to return a derivative (which commits [type piracy](https://docs.julialang.org/en/v1/manual/style-guide/index.html#Avoid-type-piracy-1)), `∇` to find the gradient (`∇(f)`), the divergence (`∇⋅F`). and the curl (`∇×F`), along with `divergence` and `curl`.


* The `LinearAlgebra` package is loaded for access to several of its functions for working with vectors `norm`, `cdot` (`⋅`), `cross` (`×`), `det`.

* The `PlotUtils` package is loaded so that its `adapted_grid` function is available.

* The `Symbolics` package is loaded (and reexported) giving access to symbolic math (`@variables`, etc.) along with symbolic `gradient`, `divergence`, and `curl` methods -- pure Julia, no Python dependency.

* The `Nemo` package is loaded -- imported, not reexported -- which switches on `Symbolics.symbolic_solve` for polynomial equations. No `using Nemo` is needed downstream, and none of Nemo's own names (`derivative`, `coeff`, `roots`, ...) enter the namespace, where they would collide with Symbolics.

* The `Plots` package is loaded (and reexported) providing the plotting interface directly -- no separate `using Plots` needed.

Several plot recipes are provided to ease the creation of plots in the notes.
`plotif`, `trimplot`, and `signchart` are used for plotting univariate functions;
`plot_polar` and `plot_parametric` are used to plot curves in 2 or 3 dimensions;
`plot_parametric` also makes the plotting og parameterically defined surfaces easier;
`vectorfieldplot` and `vectorfieldplot3d` can be used to plot vector fields; and
`arrow` is a simplified interface to `quiver` that also indicates 3D vectors.

The `plot_implicit` function can plot `2D` implicit plots. (It is borrowed from [ImplicitPlots.jl](https://github.com/saschatimme/ImplicitPlots.jl), which is avoided, as it has dependencies that hold other packages back.)

## Other packages with a recurring role in the accompanying notes:

* `Roots` is used to find zeros of univariate functions

* `QuadGK` and `HCubature` are used for numeric integration

## Cautions for anyone else using this package

This is a personal study fork, not a registered package: you have to go out of your way to
install it, and nobody maintains it for you. Several of its conveniences change `Julia`'s
behaviour *globally* for the whole session, not only for calls into this package. They are
collected here so that nobody has to discover them by debugging.

**Type piracy.** [Type piracy](https://docs.julialang.org/en/v1/manual/style-guide/index.html#Avoid-type-piracy-1)
means adding a method to a function you do not own, dispatching on a type you do not own.
Julia's method tables are global, so such a method is visible to every package in the
session. This one commits it three times, each deliberately:

* `f'` on a function returns its derivative, dispatching `Base.adjoint` (inherited from
  upstream `CalculusWithJulia`).

* `show` for a `Symbolics.Num`, and for the vector of solutions that `symbolic_solve`
  returns, emits display math so expressions typeset in Quarto, Documenter and Jupyter
  rather than printing their internal type names.

* `find_zero`, `find_zeros` and the `ZeroProblem` interface accept a symbolic expression
  or a `~` equation, mirroring the `SymPy` extension that `Roots` already ships. Should
  `Roots` ever add its own `Symbolics` support, expect a method-overwrite warning on load;
  the fix is to delete ours.

All three are the benign kind -- each replaces an error with an answer, so no working code
changes behaviour -- but they are piracy nonetheless, and the manual's own carve-out for
coupled packages that "separate features from definitions" is the ground they stand on.

**Loading this package changes what `Symbolics` can do.** `Nemo` is imported (never
`using`), which switches on `Symbolics.symbolic_solve` for polynomial equations. Code that
fails without this package will succeed with it.

**A lot of names arrive at once.** `Roots`, `LinearAlgebra`, `SpecialFunctions`,
`IntervalSets`, `Symbolics` and `Plots` are reexported, `ForwardDiff` is exported, and `e`
is exported as `exp(1)`. Clashes are real rather than theoretical: alongside SciML's
`BracketingNonlinearSolve`, both `Bisection` and `solve` become ambiguous and have to be
qualified.

**The plotting backend is configured on load.** `__init__` selects `GR` and forces headless
mode whenever `Julia` is non-interactive, so that document renders embed figures instead of
trying to open a window.

"""
module CalculusWithJuliaSquared

using Printf
import Contour
import PlotUtils
import ForwardDiff
export ForwardDiff
import Latexify

# Loading Nemo -- import, never `using` -- activates Symbolics' `SymbolicsNemoExt`, so
# `symbolic_solve` works on polynomial equations for every user of this package with no
# `using Nemo` of their own. A reexport would drag in Nemo's `derivative`, `coeff`, `roots`
# and friends, which clash with Symbolics; a bare import brings in nothing.
import Nemo

using Reexport
@reexport using Roots
@reexport using LinearAlgebra
@reexport using SpecialFunctions
@reexport using IntervalSets
@reexport using Symbolics
@reexport using Plots

import SplitApplyCombine

include("multidimensional.jl")
include("limits.jl")
include("derivatives.jl")
include("integration.jl")
include("plot-utils.jl")
include("plots.jl")
include("symbolics.jl")

# Typeset symbolic expressions as display math in HTML/LaTeX frontends (Quarto, Jupyter,
# Documenter), parallel to SymPy's built-in text/latex show. Latexify's default text/latex
# wraps in $$\begin{equation}...\end{equation}$$ which Quarto renders literally, so emit
# clean \[ ... \] via both MIMEs. (No effect in the plain-text REPL.)
Base.show(io::IO, ::MIME"text/latex", x::Symbolics.Num) =
    print(io, "\\[ ", Latexify.latexify(x; env=:raw), " \\]")
Base.show(io::IO, ::MIME"text/html", x::Symbolics.Num) =
    print(io, "<span class=\"math-left-align\" style=\"padding-left:4px;width:0;float:left;\">\\[ ",
          Latexify.latexify(x; env=:raw), " \\]</span>")

# `symbolic_solve` returns a `Vector` of raw `BasicSymbolic`, which otherwise prints with
# its full type name -- `Vector{SymbolicUtils.BasicSymbolicImpl.var"typeof(BasicSymbolicImpl)"
# {SymReal}}` -- ahead of the roots. Typeset the solution set as display math instead, the
# same way the scalar methods above do, which also matches how SymPy showed a solution set.
#
# Deliberately NOT extended to `AbstractVector{<:Symbolics.Num}`. Measured 2026-09-04: the
# only two published cells rendering a `Vector{Num}` are the echoed return of `@variables`,
# so widening would typeset a variable declaration -- dressing a macro's return value up as
# mathematics. `gradient`/`divergence`/`curl` do return one and would genuinely benefit, but
# they live in the vector-calculus groups, which are not ported and not yet in the port
# order. Decide it there, against a real rendered gradient. See `_research/CHAPTER_MAP.md`.
const _SymbolicSolutions = AbstractVector{<:Symbolics.SymbolicUtils.BasicSymbolic}

Base.show(io::IO, ::MIME"text/latex", xs::_SymbolicSolutions) =
    print(io, "\\[ ", Latexify.latexify(xs; env=:raw), " \\]")
Base.show(io::IO, ::MIME"text/html", xs::_SymbolicSolutions) =
    print(io, "<span class=\"math-left-align\" style=\"padding-left:4px;width:0;float:left;\">\\[ ",
          Latexify.latexify(xs; env=:raw), " \\]</span>")

# auto-configure plotting for headless vs interactive use
# (see the julia-coding-conventions skill, "CI / Headless Plotting Detection")
#
# MUST live in `__init__` — at module top level this runs during *precompilation*, where the
# `ENV` write is discarded and never reaches the loading process, so the guard silently does
# nothing. `!isinteractive()` is what catches document renders: a Quarto/Documenter build runs
# Julia as a non-interactive worker and sets neither `CI` nor `GKSwstype`, so without it GR
# resolves to an on-screen GKS workstation and figures open outside the page instead of being
# embedded. The REPL and IJulia both report `isinteractive() == true`, so they stay interactive.
function __init__()
    if haskey(ENV, "CI") || get(ENV, "GKSwstype", "") == "100" || !isinteractive()
        ENV["GKSwstype"] = "100"  # Force GKS headless mode
        gr(show=false)             # Disable plot display
    else
        gr()                       # Interactive mode
    end
end

const e = exp(1)
export e

export unzip, rangeclamp
export lim, symlim, tlim
export tangent, secant, D, sign_chart, SignChart
export riemann, fubini
export divergence, gradient, curl, ∇, uvec

end # module
