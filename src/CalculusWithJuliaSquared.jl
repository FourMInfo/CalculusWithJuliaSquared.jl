"""
    CalculusWithJuliaSquared

A personal, pure-Julia fork of `CalculusWithJulia.jl` to accompany notes at [https://calculuswithjulia.github.io](https://calculuswithjulia.github.io) on using Julia for topics from the calculus sequence.

This package does two things:

* It loads a few other packages making it easier to use (and install) the functionality provided by them and

* It defines a handful of functions for convenience. The exported ones
are `unzip`, `rangeclamp` `tangent`, `secant`, `D` (and the prime
notation), `divergence`, `gradient`, `curl`, and `∇`, along with some plotting
functions. The constant `e` is assigned to `exp(1)`.

* It supplies the exact symbolic algebra that `Symbolics` core does not: `exact_trig_values`
(the special-angle table, so `cos(π/6)` becomes `√3/2` instead of staying unevaluated),
`factored_poly` and `poly_factors` (factoring over the rationals), and `partial_fractions`.
These stand in for `SymPy`'s automatic special angles, `factor` and `apart`. Alongside them,
`numeric_roots` and `root_enclosures` find roots exactly and report them as floats or as
certified intervals, standing in for `N.(solve(...))` and `sympy.real_roots`; and `divrem`
divides one polynomial by another.

* It displays symbolic expressions in conventional notation. `conventional_latex` typesets an
expression the way a mathematics text writes it -- term and factor order, fractions, powers,
names -- and every symbolic expression displays through it in Quarto, Jupyter and Documenter.
`set_conventional_default`, `get_conventional_default` and `reset_conventional_default`
choose, for the session, which letters are the variables and which way a sum runs.


## Packages loaded by `CalculusWithJuliaSquared`

* The `SpecialFunctions` is loaded giving access to a few special functions used in these notes, e.g., `airyai`, `gamma`

* The `ForwardDiff` package is loaded giving access to its  `derivative`,  `gradient`, `jacobian`, and `hessian` functions for finding automatic derivatives of functions. In addition, this package defines `'` (for functions) to return a derivative (which commits [type piracy](https://docs.julialang.org/en/v1/manual/style-guide/index.html#Avoid-type-piracy-1)), `∇` to find the gradient (`∇(f)`), the divergence (`∇⋅F`). and the curl (`∇×F`), along with `divergence` and `curl`.


* The `LinearAlgebra` package is loaded for access to several of its functions for working with vectors `norm`, `cdot` (`⋅`), `cross` (`×`), `det`.

* The `PlotUtils` package is loaded so that its `adapted_grid` function is available.

* The `Symbolics` package is loaded (and reexported) giving access to symbolic math (`@variables`, etc.) along with symbolic `gradient`, `divergence`, and `curl` methods -- pure Julia, no Python dependency.

* The `Nemo` package is loaded -- imported, not reexported -- which switches on `Symbolics.symbolic_solve` for polynomial equations, and also backs `factored_poly`, `poly_factors` and `partial_fractions`. The module name itself IS exported, so `Nemo.overlaps`, `Nemo.midpoint` and `Nemo.radius` are available for the balls `root_enclosures` returns; but no `using Nemo` is needed downstream, and none of Nemo's own names (`derivative`, `coeff`, `roots`, ...) enter the namespace, where they would collide with Symbolics.

* The `Plots` package is loaded (and reexported) providing the plotting interface directly -- no separate `using Plots` needed.

* The `LaTeXStrings` package is loaded (and reexported), so `L"..."` works with no separate `using`. `Plots` does *not* pass this through. It is carried here because it is house standard across the sibling study repos, which means a downstream package or notebook environment need not name it alongside this one.

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

### Type piracy: what this package does, and the rule it follows

[Type piracy](https://docs.julialang.org/en/v1/manual/style-guide/index.html#Avoid-type-piracy-1)
means adding a method to a function you do not own, dispatching on a type you do not own.
It matters because Julia's method tables are **global**: such a method is visible to every
package in the session, not only to code that calls into this one. Loading this package can
therefore change how *unrelated* code behaves, which is why the practice is discouraged.

This package commits it five times, each deliberately, and each passing the same test:

> **The benign test.** Every call the pirated method answers is a call that would otherwise
> have **thrown** — a `MethodError`, or an outright error. No working code changes its
> behaviour; code that used to fail now succeeds. The manual's own carve-out for tightly
> coupled packages that "separate features from definitions" is the ground these stand on.

A piracy that changed the *result* of a call that already worked would not pass that test,
and none of the five below does.

| method | what it adds | without it |
|:--|:--|:--|
| `Base.adjoint` on a function | `f'` returns the derivative (inherited from upstream `CalculusWithJulia`) | `MethodError` |
| `Base.show` for `Symbolics.Num`, and for the vector `symbolic_solve` returns | display math, so expressions typeset in Quarto, Documenter and Jupyter instead of printing internal type names | prints the type, not the mathematics |
| `Roots.find_zero`, `find_zeros`, `ZeroProblem` on a symbolic expression or `~` equation | solving `find_zero(x^3 - x + 1, (-2, -1))` directly, mirroring the `SymPy` extension `Roots` already ships | `MethodError` |
| `Base.divrem` on two `Symbolics.Num`s | Euclidean division of polynomials, `a = b*q + r` with `deg r < deg b` | `MethodError` |
| `Plots._show` for `text/html` on a `Plot{PlotlyBackend}` | emits the plot *body*, so an interactive Plotly figure appears inline in a rendered page (inherited from upstream's Plots extension) | errors: *"only png or svg allowed. got: :html"* |

Three of these are worth a further word:

  * **`divrem` is named, not renamed.** A `poly_divrem` of our own would have avoided the
    piracy entirely. It is not used because the point being taught is that Julia's *generic*
    `divrem` divides polynomials exactly as it divides integers; a bespoke name would state
    the opposite.

  * **`Plots._show` pirates an *internal*.** The leading underscore marks it as private to
    `Plots`, so unlike the other four it carries no API stability promise at all: a patch
    release could rename or remove it, and the symptom would be a plot that silently stops
    being interactive rather than an error. Measured 2026-09-11 against `Plots` v1 —
    `_best_html_output_type` maps `:plotly => :html`, and the generic
    `_show(::IO, ::MIME"text/html", ::Plot)` has no `:html` branch, so without this method
    the call throws. That is what keeps it on the benign side of the test above.

  * **`find_zero` may one day collide.** Should `Roots` add its own `Symbolics` support,
    expect a **method-overwrite warning on load**. That is not a bug to work around: the fix
    is to delete our block, because upstream's version supersedes it. The same applies to any
    of the five if the owning package adopts the method itself.

### `Nemo` is imported, and only its *name* is exported

`Nemo` does two jobs here: it switches on `Symbolics.symbolic_solve` for polynomial
equations (via Symbolics' `SymbolicsNemoExt`), and it backs `factored_poly`, `poly_factors`,
`partial_fractions`, `numeric_roots`, `root_enclosures` and `divrem`. **So loading this
package changes what `Symbolics` itself can do** — code that fails without it will succeed
with it.

How it is loaded is a deliberate middle course, and knowing which one you are in explains
every "why must I qualify this?" question:

| | what your code sees | `Nemo.overlaps(a, b)` |
|:--|:--|:--|
| `import Nemo` alone | nothing | `UndefVarError` |
| **`import Nemo` + `export Nemo`** ← this package | the module binding, and nothing else | works |
| `@reexport using Nemo` | all ~1200 of Nemo's names | works, at a price |

The module **name** is exported, exactly as `ForwardDiff`'s is, so you can call
`Nemo.overlaps`, `Nemo.midpoint`, `Nemo.radius` and `Nemo.contains` on the balls
[`root_enclosures`](@ref) returns without adding `Nemo` to your own project. No `using Nemo`
is needed, and none of Nemo's functions enter your namespace.

**Why not reexport.** Nemo exports `roots`, `degree`, `derivative`, `coeff`, `factor`, `term`
and `terms`. Every one of those collides with something these notes use — `Polynomials.roots`
and `Polynomials.degree` above all, and `derivative` is a three-way clash between Nemo,
`Polynomials` and `Symbolics`. Reexporting would turn working code into ambiguity errors. The
same reasoning applies to `Symbolics`' own public-but-unexported names (`derivative`, `value`,
`get_variables`, `jacobian`, `hessian` and others): this package does **not** re-export them
either, so they stay qualified as `Symbolics.derivative`. That is upstream's decision and
overriding it would break the collision-avoidance it exists for.

### A lot of names arrive at once

`Roots`, `LinearAlgebra`, `SpecialFunctions`, `IntervalSets`, `Symbolics`, `Plots` and
`LaTeXStrings` are reexported; `ForwardDiff` and `Nemo` are exported as module names; and `e`
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
# The module NAME is exported (as `ForwardDiff` is above), so that downstream code can
# write `Nemo.overlaps(a, b)` on the balls `root_enclosures` returns without taking a
# dependency of its own. Only the binding `Nemo` enters scope -- none of its functions.
export Nemo

using Reexport
@reexport using Roots
@reexport using LinearAlgebra
@reexport using SpecialFunctions
@reexport using IntervalSets
@reexport using Symbolics
@reexport using Plots
# House standard across the sibling study repos: `Math_Foundations` and `Linear_Algebra`
# both carry `LaTeXStrings` at top level, and `Calculus` had to name it *beside* this
# package (`@reexport using CalculusWithJuliaSquared, LaTeXStrings`) precisely because we
# did not. `Plots` does NOT pass it through -- `@L_str` is not among its exported names --
# so every consumer was adding it separately. Carrying it here is what makes this package
# the single house foundation it is meant to be for the calculus repos.
@reexport using LaTeXStrings

import SplitApplyCombine

include("multidimensional.jl")
include("limits.jl")
include("derivatives.jl")
include("integration.jl")
include("plot-utils.jl")
include("plots.jl")
include("symbolics.jl")
include("symbolic-algebra.jl")
include("numeric-roots.jl")
include("conventional-latex.jl")

# Typeset symbolic expressions as display math in HTML/LaTeX frontends (Quarto, Jupyter,
# Documenter), parallel to SymPy's built-in text/latex show. Emit clean \[ ... \] via both
# MIMEs -- Latexify's default wraps in $$\begin{equation}...\end{equation}$$, which Quarto
# renders literally -- and typeset the body with `conventional_latex`, so what a reader SEES
# is conventional notation rather than Symbolics' storage order. (No effect in the REPL.)
"""
    show(io, ::MIME"text/latex", x::Symbolics.Num)
    show(io, ::MIME"text/html",  x::Symbolics.Num)

Typeset a symbolic expression as **display math** in HTML/LaTeX frontends — Quarto,
Jupyter, Documenter — parallel to the `text/latex` show `SymPy` has built in. Companion
methods do the same for the vector of roots `Symbolics.symbolic_solve` returns, which
would otherwise print its full internal type name ahead of the mathematics.

The mathematics is typeset by [`conventional_latex`](@ref), so an expression displays the
way a text writes it — `a x^{2} + b x + c`, not `c + b x + x^{2} a` — and the session
defaults set by [`set_conventional_default`](@ref) (which letters are variables, which way
a sum runs) apply to display too. See `conventional_latex` for the conventions. The
solution vector keeps `Latexify`'s array layout, one conventionally typeset root per row.

These emit a clean `\\[ ... \\]` through both MIME types, because `Latexify`'s own
`text/latex` output wraps the expression in `\$\$\\begin{equation}...\\end{equation}\$\$`,
which Quarto renders literally. There is no effect in the plain-text REPL, which uses
`text/plain`.

!!! note "These methods are type piracy"
    `show` belongs to `Base` and `Num` belongs to `Symbolics`, so these methods change how
    symbolic expressions display for every package in the session. They are benign in the
    sense set out under *Cautions* in the [`CalculusWithJuliaSquared`](@ref) module
    documentation: neither `Num` nor the solution vector has a `text/latex` or `text/html`
    method without them, so nothing that previously displayed changes — output that was
    unavailable becomes available.

    Deliberately **not** extended to `AbstractVector{<:Symbolics.Num}`: measured 2026-09-04,
    the only published cells rendering one are the echoed return of `@variables`, so
    widening would dress a macro's return value up as mathematics.
"""
Base.show(io::IO, ::MIME"text/latex", x::Symbolics.Num) =
    print(io, "\\[ ", conventional_latex(x), " \\]")
Base.show(io::IO, ::MIME"text/html", x::Symbolics.Num) = _html_math(io, conventional_latex(x))

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

# Latexify's own column layout for a vector, measured 2026-09-15, with each root typeset
# conventionally rather than by Latexify.
_solutions_latex(xs) = "\\left[\n\\begin{array}{c}\n" *
    join(conventional_latex(x) * " \\\\\n" for x in xs) * "\\end{array}\n\\right]"

Base.show(io::IO, ::MIME"text/latex", xs::_SymbolicSolutions) =
    print(io, "\\[ ", _solutions_latex(xs), " \\]")
Base.show(io::IO, ::MIME"text/html", xs::_SymbolicSolutions) = _html_math(io, _solutions_latex(xs))

# The HTML wrapper every display here uses: display math, left-aligned as a cell output.
_html_math(io::IO, latex::AbstractString) =
    print(io, "<span class=\"math-left-align\" style=\"padding-left:4px;width:0;float:left;\">\\[ ",
          latex, " \\]</span>")

# ---------------------------------------------------------------------------------
# Every other container a reader meets (v0.16.0)
#
# A Quarto page typesets a value only if it has a `text/html` method: `text/latex` does
# NOT beat `text/plain` there. So a `Vector{Num}` from `poly_factors`, a tuple from
# `divrem`, a single root taken out of a solution set and a `symlim` result all printed as
# Julia syntax -- a published page showed `sqrt(3) / 2` for eight days. These methods add
# `text/html` ONLY: Symbolics already owns `text/latex` for `Vector{Num}`, `Matrix{Num}`
# and `BasicSymbolic` (SymbolicsLatexifyExt), and redefining it would overwrite that
# method, which fails precompilation. Nothing had `text/html` before (measured), so each
# passes the module docstring's benign test.
# ---------------------------------------------------------------------------------

# \mathtt needs these characters escaped; a route such as `:parameter_dependent` has one.
_tt(s::AbstractString) = "\\mathtt{" *
    replace(s, "\\" => "\\backslash ", "_" => "\\_", "{" => "\\{", "}" => "\\}", "#" => "\\#",
            "\$" => "\\\$", "%" => "\\%", "&" => "\\&", "~" => "\\sim ", "^" => "\\hat{}") * "}"

# One element of a displayed tuple: mathematics as mathematics, anything else as code,
# so a route reads exactly as a reader would type it. `Bool <: Real`, hence first.
_element_latex(v::Symbolics.Num) = conventional_latex(v)
_element_latex(v::Symbolics.SymbolicUtils.BasicSymbolic) = conventional_latex(Symbolics.Num(v))
_element_latex(v::Bool) = _tt(string(v))
_element_latex(v::Symbol) = _tt(repr(v))
_element_latex(::Nothing) = _tt("nothing")
_element_latex(r::SymlimResult) = _tuple_latex(Tuple(r))
# `conventional_latex` writes the letters `Inf`, which in math mode read as I·n·f.
_element_latex(v::Real) = isinf(v) ? (v > 0 ? "\\infty" : "-\\infty") : conventional_latex(Symbolics.Num(v))
_element_latex(v) = _tt(repr(v))

_tuple_latex(t) = "\\left( " * join((_element_latex(v) for v in t), ",\\ ") * " \\right)"

# A single root taken out of `symbolic_solve`'s vector, or anything computed from one, is
# an unwrapped `BasicSymbolic`, and so is what `tlim` returns.
Base.show(io::IO, ::MIME"text/html", x::Symbolics.SymbolicUtils.BasicSymbolic) =
    _html_math(io, conventional_latex(Symbolics.Num(x)))

# Exactly `Vector{Num}` and `Matrix{Num}`, never `AbstractVector{<:Num}`: a symbolic array
# VARIABLE (`@variables zs[1:3]`) is an `AbstractVector{Num}` too, and it is a declaration,
# not a result. Arrays of three or more dimensions stay plain -- revisit when one can reach
# a reader (as of 2026-09-17 none can).
Base.show(io::IO, ::MIME"text/html", xs::Vector{Symbolics.Num}) = _html_math(io, _solutions_latex(xs))

function _matrix_latex(A)
    rows = (join((conventional_latex(a) for a in r), " & ") * " \\\\\n" for r in eachrow(A))
    "\\left[\n\\begin{array}{" * "c"^size(A, 2) * "}\n" * join(rows) * "\\end{array}\n\\right]"
end
Base.show(io::IO, ::MIME"text/html", A::Matrix{Symbolics.Num}) = _html_math(io, _matrix_latex(A))

# A tuple typesets when it holds a symbolic value, or a `symlim` result, in any of its
# first 16 positions. Dispatch cannot say "somewhere in the tuple", only "in position k",
# hence the union; 16 measured free (no ambiguities, under a microsecond per `showable`).
# A tuple with nothing symbolic in it -- `(1, 2)`, plot options -- has no `text/html`
# method, so it keeps Julia's display.
const _DisplayedElement = Union{Symbolics.Num, Symbolics.SymbolicUtils.BasicSymbolic, SymlimResult}
const _TUPLE_POSITIONS = 16
const _SymbolicTuple = Union{(Tuple{ntuple(_ -> Any, k - 1)..., _DisplayedElement, Vararg{Any}}
                              for k in 1:_TUPLE_POSITIONS)...}
Base.show(io::IO, ::MIME"text/html", t::_SymbolicTuple) = _html_math(io, _tuple_latex(t))

# Our own type, so no piracy at all: every limit result typesets, whatever its value.
Base.show(io::IO, ::MIME"text/html", r::SymlimResult) = _html_math(io, _tuple_latex(Tuple(r)))

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
export exact_trig_values, factored_poly, poly_factors, partial_fractions, combine_fractions, poly_rem
export numeric_roots, root_enclosures
export conventional_latex, set_conventional_default, get_conventional_default, reset_conventional_default

end # module
