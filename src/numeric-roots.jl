## ---------------------------------------------------------------------------------
## Numeric roots, and certified enclosures of the real ones.
##
##   numeric_roots     every root as a `Float64`/`ComplexF64`, multiplicity included
##   root_enclosures   the real roots as intervals that provably contain them
##
## Both go through `Nemo.roots(Nemo.QQBar, p)`, which returns the roots as *exact
## algebraic numbers*. They therefore exist even where Abel-Ruffini denies a radical
## formula and `Symbolics.symbolic_solve` can only answer `roots_of(...)` -- which is
## precisely the case the quintics in `precalc/polynomial_roots` run into.
##
## Why a certified enclosure rather than just a float: two floats printed close together
## say nothing about whether they are two roots, or one root computed twice with
## different error. Two *disjoint* enclosures, each provably containing a root, are a
## proof that there are two. `precalc/rational_functions` has the case that needs it --
## `s^15 - 16129s^2 + 254s - 1`, whose two small roots sit two ulps apart in `Float64`,
## far inside the error of any floating-point root-finder. That is why the `Polynomials`
## package reports that cluster as complex, and why this is worth having.
##
## `Nemo` is already imported by this module to switch on `symbolic_solve`, and the
## conversion helpers (`_nemo_ring`, `_to_nemo`, `_from_nemo`) are shared with the
## factoring code in `symbolic-algebra.jl`, so none of this adds a dependency.
## ---------------------------------------------------------------------------------

# Converting an exact algebraic number straight to `Float64` LOSES THE LAST BIT. Measured
# 2026-09-10 on Nemo 0.56: `Float64(qqbar)` returns 1.414213562373095 for the positive root
# of `x^2 - 2`, where `sqrt(2)` is 1.4142135623730951 -- a different `Float64`. Same one-ulp
# error on `cbrt(2)` and on the golden ratio. Rounding through a ball of well over double
# precision gives the correctly-rounded result in every case, so that a reader who compares
# `numeric_roots(x^2 - 2, x)` against `sqrt(2)` gets `true` rather than a puzzle.
#
# 128 bits is far more than the 53 a `Float64` keeps; the point is only to be clear of the
# boundary, and the cost is negligible next to finding the roots.
const _ROOT_CONV_BITS = 128

_cf64(r)  = Float64(Nemo.ArbField(_ROOT_CONV_BITS)(r))
_ccf64(r) = ComplexF64(Nemo.AcbField(_ROOT_CONV_BITS)(r))

# `Nemo.roots` answers `[]` for any constant. That is right for a non-zero constant and
# actively wrong for the zero polynomial, where every number is a root. Neither is a
# useful thing to hand back, so both are refused rather than silently returning nothing.
function _nemo_poly_for_roots(ex, var, R, y)
    p = _to_nemo(ex, var, R, y)
    Nemo.degree(p) >= 1 || throw(ArgumentError(
        "expected a polynomial of degree 1 or more in `$var`, got `$ex`. " *
        "A non-zero constant has no roots, and every number is a root of `0`; " *
        "neither is a list this function can return."))
    p
end

"""
    numeric_roots(ex, var; real_only=false)

Every root of the univariate polynomial `ex`, as a floating-point number.

Returns `ComplexF64` values by default, or `Float64` values when `real_only=true`, in
which case the non-real roots are dropped. This is the counterpart of `SymPy`'s
`N.(solve(...))` and, with `real_only=true`, of `sympy.real_roots`.

Roots are found exactly, as algebraic numbers, and rounded only on the way out. So they
are returned even for polynomials that have no formula in radicals, where
`symbolic_solve` can only answer `roots_of(...)`:

```jldoctest
julia> using CalculusWithJuliaSquared

julia> @variables x;

julia> numeric_roots(x^2 - 2, x; real_only=true)
2-element Vector{Float64}:
 -1.4142135623730951
  1.4142135623730951
```

Two guarantees worth relying on when rendering a document:

  * **The order is stable.** Real results are sorted ascending; complex results are
    sorted by real part, then imaginary part. The same input renders the same way
    every time.
  * **Repeated roots repeat.** A double root appears twice, so with `real_only=false`
    the number of values always equals the degree.

`ex` must be a polynomial in `var` alone with rational coefficients; anything else
throws rather than guessing. A constant is refused, since it has either no roots or all
of them.

For real roots *with an error bound you can reason about* -- rather than a float whose
accuracy is unstated -- use [`root_enclosures`](@ref).

See also [`poly_factors`](@ref), [`factored_poly`](@ref).
"""
function numeric_roots(ex, var; real_only = false)
    R, y = _nemo_ring()
    p = _nemo_poly_for_roots(ex, var, R, y)
    rts = Nemo.roots(Nemo.QQBar, p)

    if real_only
        # `Float64` of a non-real algebraic number throws, so filter before converting.
        vals = Float64[_cf64(r) for r in rts if Nemo.is_real(r)]
        return sort!(vals)
    end

    # `sort` on `QQBar` itself throws on non-real entries ("comparing nonreal numbers"),
    # so the ordering is imposed after the conversion, where it is total.
    vals = ComplexF64[_ccf64(r) for r in rts]
    sort!(vals; by = z -> (real(z), imag(z)))
end

"""
    root_enclosures(ex, var; bits=128)

The real roots of the univariate polynomial `ex`, each as an interval that is
*guaranteed* to contain one.

Returns `Nemo.ArbFieldElem` values -- ball arithmetic, printed as `[midpoint +/- radius]`
-- sorted ascending. Each is a rigorous enclosure computed from the exact algebraic root,
not a float with an informal error estimate.

The point of an enclosure is that it supports proof rather than eyeballing. Two nearby
floats cannot tell you whether there are two roots or one root computed twice; two
enclosures that do **not** overlap can only come from two distinct roots:

```julia
julia> @variables s;

julia> es = root_enclosures(s^15 - 16129s^2 + 254s - 1, s; bits=96);

julia> Nemo.overlaps(es[1], es[2])      # disjoint => genuinely two roots
false
```

`bits` sets the working precision, and is a real dial rather than decoration. On the
polynomial above the first two enclosures still *overlap* at 53 bits -- the honest answer
being "these cannot be told apart yet" -- and separate only at 64. That threshold is the
point of the whole exercise: 53 bits is exactly the precision of a `Float64` mantissa, so
no computation carried in double precision can establish that this cluster is two roots
rather than one. Nothing built on `Float64` interval endpoints could do it either, since
their radius bottoms out at an ulp.

Useful `Nemo` functions for working with the results -- `Nemo` is imported by this
package but not reexported, so they must be qualified:

  * `Nemo.overlaps(a, b)` -- do two enclosures intersect?
  * `Nemo.contains(ball, x)` -- is `x` inside? **Note:** there is no method for a
    `Float64` argument; wrap it first, as `Nemo.contains(b, Nemo.ArbField(96)(6.94))`.
  * `Nemo.midpoint(ball)`, `Nemo.radius(ball)` -- the two halves of `[m +/- r]`.

Arithmetic works and stays certified (`b + 1.0`, `b^2`, `sin(b)`, `sqrt(b)`), and
`Float64.(root_enclosures(...))` drops back to plain numbers when that is all you need.

Only real roots are returned; a ball is real by construction. For the complex ones, or
for plain floats, use [`numeric_roots`](@ref).
"""
function root_enclosures(ex, var; bits = 128)
    bits isa Integer && bits >= 2 || throw(ArgumentError(
        "`bits` must be an integer of at least 2, got `$bits`."))

    R, y = _nemo_ring()
    p = _nemo_poly_for_roots(ex, var, R, y)

    # Sorting happens on the exact algebraic roots, where the order is unambiguous.
    # Sorting the balls instead would compare intervals, which is undecidable when two
    # of them overlap -- exactly the case this function exists to expose.
    rts = sort(filter(Nemo.is_real, Nemo.roots(Nemo.QQBar, p)))

    CC = Nemo.ArbField(bits)
    Nemo.ArbFieldElem[CC(r) for r in rts]
end
