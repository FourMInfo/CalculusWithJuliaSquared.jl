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

## Packages with extra features added when loaded

Through a package extension, additional code runs when the following package loads:

* `Plots`: the `Plots` package provides a plotting interface.

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

"""
module CalculusWithJuliaSquared

using Printf
import Contour
import PlotUtils
import ForwardDiff
export ForwardDiff

using Reexport
@reexport using Roots
@reexport using LinearAlgebra
@reexport using SpecialFunctions
@reexport using IntervalSets
@reexport using Symbolics

import SplitApplyCombine

include("multidimensional.jl")
include("limits.jl")
include("derivatives.jl")
include("integration.jl")
include("plot-utils.jl")
include("plots.jl")
include("symbolics.jl")

const e = exp(1)
export e

export unzip, rangeclamp
export lim
export tangent, secant, D, sign_chart, SignChart
export riemann, fubini
export divergence, gradient, curl, ∇, uvec

end # module
