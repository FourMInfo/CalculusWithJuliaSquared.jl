## symbolic gradient/divergence/curl via Symbolics.jl (a hard dependency, reexported)

gradient(ex::Symbolics.Num, vars::AbstractArray=collect(Symbolics.get_variables(ex))) =
    Symbolics.gradient(ex, collect(vars))

divergence(F::Vector{<:Symbolics.Num}, vars=collect(Symbolics.get_variables(F))) =
    sum(Symbolics.derivative.(F, vars))

curl(F::Vector{<:Symbolics.Num}, vars=collect(Symbolics.get_variables(F))) =
    curl(Symbolics.jacobian(F, vars))


## ---------------------------------------------------------------------------------
## Roots <-> Symbolics: let a symbolic expression or equation stand where `Roots`
## expects a function, so the notes can write
##
##     find_zero(x^3 - x + 1, (-2, -1))        and        find_zero(cos(x) ~ x, (0, 2))
##
## `Roots` ships exactly this for `SymPy` (`RootsSymPyExt`) but not for `Symbolics`, and
## an extension of `Roots` can only be declared inside `Roots` itself. These three methods
## are that extension's mirror image, with `build_function` in place of `lambdify`.
##
## This is TYPE PIRACY, deliberately: neither the functions nor the types are ours. It is
## the benign kind -- every call below throws without it, so no working code can change
## behaviour -- but it is listed in the "Cautions" section of the module docstring. Should
## `Roots` ever ship its own `Symbolics` support, expect a method-overwrite warning on
## load; the fix is to delete this block.
## ---------------------------------------------------------------------------------

# One free variable, or we cannot know which one `find_zero` is solving for.
function _symbolic_callable(ex::Symbolics.Num)
    vars = Symbolics.get_variables(ex)
    length(vars) == 1 || throw(ArgumentError(
        "expected an expression in exactly one variable, got $(length(vars)) in `$ex`. " *
        "Substitute values for the others first, e.g. `substitute(ex, Dict(a => 1))`."))
    Symbolics.build_function(ex, only(vars); expression = Val(false))
end

# `lhs ~ rhs` is solved as `lhs - rhs == 0`, as `RootsSymPyExt` does for `SymPy`.
_symbolic_callable(eq::Symbolics.Equation) =
    _symbolic_callable(Symbolics.Num(eq.lhs - eq.rhs))

const _SymbolicRootInput = Union{Symbolics.Num, Symbolics.Equation}

Roots.Callable_Function(M::Roots.AbstractUnivariateZeroMethod,
                        f::_SymbolicRootInput, p = nothing) =
    Roots.Callable_Function(M, _symbolic_callable(f), p)

Roots.FnWrapper(f::_SymbolicRootInput) = Roots.FnWrapper(_symbolic_callable(f))

Roots.find_zeros(f::_SymbolicRootInput, a, b = nothing; kwargs...) =
    Roots.find_zeros(_symbolic_callable(f), a, b; kwargs...)
