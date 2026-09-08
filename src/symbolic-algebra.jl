## ---------------------------------------------------------------------------------
## Exact symbolic algebra: the three `SymPy` facilities the notes lean on that
## `Symbolics` core does not provide.
##
##   exact_trig_values   cos(PI/6)          ->  sqrt(3)/2      (SymPy: automatic)
##   factored_poly       x^3-6x^2+11x-6     ->  (x-3)(x-2)(x-1)          (SymPy: factor)
##   poly_factors        the same, as a list, so a cell can count them
##   partial_fractions   1/((x-1)(x-2))     ->  1/(x-2) - 1/(x-1)        (SymPy: apart)
##
## Factoring and partial fractions are `Nemo`'s, reached through the polynomial ring
## over the rationals. `Nemo` is already imported by this module (see the header) to
## switch on `symbolic_solve`, so none of this adds a dependency.
##
## Every function here REFUSES rather than guesses: handed something outside its
## domain it returns the input unchanged (`exact_trig_values`) or throws with a
## message naming the restriction. That matters most for `exact_trig_values`, which
## recognises an angle *structurally* rather than numerically -- see `_is_exact_pi_angle`
## for why a numeric match alone silently invents exact answers.
## ---------------------------------------------------------------------------------

const _SU = Symbolics.SymbolicUtils

# --------------------------------------------------------------------------------
# exact trigonometric values at the special angles
# --------------------------------------------------------------------------------

# cos(k*pi) on the special angles of the first quadrant, 0 <= k <= 1//2.
# `nothing` means "not a special angle"; every caller propagates that as a refusal.
function _cos_first_quadrant(k::Rational{Int})
    k == 0//1 && return Symbolics.Num(1)
    k == 1//6 && return sqrt(Symbolics.Num(3)) / 2
    k == 1//4 && return sqrt(Symbolics.Num(2)) / 2
    k == 1//3 && return Symbolics.Num(1) / 2
    k == 1//2 && return Symbolics.Num(0)
    nothing
end

_negate(v) = v === nothing ? nothing : -v

# cos(k*pi) for any rational k, by reflecting the first quadrant into the other three.
function _cos_kpi(k::Rational{Int})
    k = mod(k, 2)
    k <= 1//2 && return _cos_first_quadrant(k)
    k <= 1//1 && return _negate(_cos_first_quadrant(1//1 - k))
    k <= 3//2 && return _negate(_cos_first_quadrant(k - 1//1))
    _cos_first_quadrant(2//1 - k)
end

_sin_kpi(k::Rational{Int}) = _cos_kpi(1//2 - k)

_isexactzero(v) = isequal(Symbolics.value(v), 0)

# The four remaining functions are quotients, so they inherit the table and add the
# poles: `tan(pi/2)` and `cot(0)` have no value to return. SymPy answers those with
# complex infinity; refusing leaves the expression as written, which is honest.
function _exact_trig(op, k::Rational{Int})
    op === sin && return _sin_kpi(k)
    op === cos && return _cos_kpi(k)

    s, c = _sin_kpi(k), _cos_kpi(k)
    (s === nothing || c === nothing) && return nothing

    op === tan && return _isexactzero(c) ? nothing : s / c
    op === cot && return _isexactzero(s) ? nothing : c / s
    op === sec && return _isexactzero(c) ? nothing : 1 / c
    op === csc && return _isexactzero(s) ? nothing : 1 / s
    nothing
end

const _EXACT_TRIG_OPS = (sin, cos, tan, csc, sec, cot)

# The special angles all have denominator 1, 2, 3, 4 or 6. Search those directly
# rather than reaching for `rationalize`, which would happily hand back some huge
# rational for an angle that merely sits close to one.
const _SPECIAL_DENOMINATORS = (1, 2, 3, 4, 6)

# The numeric test alone is NOT enough, and getting this wrong is the whole risk in
# this function. `cos(Num(0.5235987755982988))` stays symbolic, and that float is
# `pi/6` to fifteen digits -- so a purely numeric match promotes it to `sqrt(3)/2`
# and silently claims an exact value for an input that never had one. Require the
# angle to be *built* from the symbolic `π` and exact rationals: then the numeric
# match is reading off a structure already known to be an exact multiple of π,
# rather than guessing that a float was meant to be one.
function _is_exact_pi_angle(t)
    if _SU.iscall(t)
        seen = false
        for a in _SU.arguments(t)
            r = _is_exact_pi_angle(a)
            r === nothing && return nothing
            seen |= r
        end
        return seen
    end

    v = t isa Number ? t : (_SU.isconst(t) ? Symbolics.value(t) : nothing)
    v === nothing && return nothing              # a free variable
    v isa AbstractFloat && return nothing        # a float anywhere disqualifies it
    v isa Irrational && return v === Base.pi ? true : nothing
    v isa Union{Integer, Rational} ? false : nothing
end

function _k_of_pi(a)
    t = Symbolics.value(a)

    # Exact zero is a multiple of π on the nose, and carries no π of its own to find.
    if !_SU.iscall(t)
        v = t isa Number ? t : (_SU.isconst(t) ? Symbolics.value(t) : nothing)
        v isa Union{Integer, Rational} && iszero(v) && return 0//1
    end

    _is_exact_pi_angle(t) === true || return nothing

    x = try
        Float64(Symbolics.value(Symbolics.simplify(Symbolics.Num(t))))
    catch
        return nothing
    end
    isfinite(x) || return nothing

    r = x / pi
    for d in _SPECIAL_DENOMINATORS
        n = round(r * d)
        abs(n) > 1e6 && continue
        isapprox(n / d, r; atol = 1e-10) && return Int(n) // d
    end
    nothing
end

# `1/(1//2)` comes back as `2//1`, which reads badly in a book. Rationals that are
# whole numbers print as integers.
function _tidy_exact(v)
    v === nothing && return nothing
    u = Symbolics.value(v)
    u isa Rational && denominator(u) == 1 && return Symbolics.Num(numerator(u))
    v
end

function _exact_trig_walk(t)
    _SU.iscall(t) || return t

    op = _SU.operation(t)
    old = _SU.arguments(t)
    args = map(_exact_trig_walk, old)

    if op in _EXACT_TRIG_OPS && length(args) == 1
        k = _k_of_pi(args[1])
        if k !== nothing
            v = _tidy_exact(_exact_trig(op, k))
            v === nothing || return Symbolics.value(v)
        end
    end

    # Rebuild only where something below actually changed. Passing an untouched term
    # back through `maketerm` returns an expression that prints identically but no
    # longer compares `isequal` to the input -- which turns every refusal into a
    # silently different object.
    all(p -> p[1] === p[2], zip(args, old)) && return t

    _SU.maketerm(typeof(t), op, args, _SU.metadata(t))
end

"""
    exact_trig_values(ex)

Replace every trigonometric function applied to a rational multiple of `π` in `ex`
with its exact value, leaving the rest of the expression alone.

`Symbolics` has no table of special angles, so `cos(Num(π)/6)` simply stays
unevaluated, and `simplify` makes matters worse by folding the `π` to a float.
This walks the expression instead and substitutes the exact value, which is an
ordinary symbolic term: `sqrt(3)/2` prints as `√3/2` and typesets as such.

Handles `sin`, `cos`, `tan`, `csc`, `sec` and `cot` at any rational multiple of `π`
with denominator 1, 2, 3, 4 or 6, in every quadrant.

Anything else is returned unchanged -- an angle that is not such a multiple, an
argument still carrying a free variable, and the poles (`tan(π/2)`, `cot(0)`),
which have no value to give. Note that the angle has to be exact going in: a
`Float64` that merely rounds to `π/6` is refused rather than guessed at.

## Examples

```julia
julia> PI = Symbolics.Num(pi);

julia> exact_trig_values(cos(PI/6))
sqrt(3) / 2

julia> exact_trig_values.(cos.([0, PI/6, PI/4, PI/3, PI/2]))
5-element Vector{Num}:
         1
 sqrt(3) / 2
 sqrt(2) / 2
       1//2
         0

julia> exact_trig_values(cos(Symbolics.Num(0.5235987755982988)))   # a float, not π/6
cos(0.5235987755982988)
```

See also [`factored_poly`](@ref), [`partial_fractions`](@ref).
"""
exact_trig_values(ex) = Symbolics.Num(_exact_trig_walk(Symbolics.value(ex)))

# --------------------------------------------------------------------------------
# Symbolics <-> Nemo, over the rationals
# --------------------------------------------------------------------------------

_shrink(n::Integer) = typemin(Int) <= n <= typemax(Int) ? Int(n) : n

# Prefer an integer to a rational with denominator 1, purely so factored output
# reads as `x - 3` rather than `x - 3//1`.
_pretty(r::Rational) = denominator(r) == 1 ? _shrink(numerator(r)) : r

_as_rational(c::Integer) = Rational{BigInt}(c)
_as_rational(c::Rational) = Rational{BigInt}(c)
# A float coefficient that is an exact integer is fine; a genuine float is not, since
# factoring over the rationals would have to invent a precision it was never given.
_as_rational(c::AbstractFloat) = isinteger(c) ? Rational{BigInt}(BigInt(c)) : nothing
_as_rational(::Any) = nothing

function _only_variable(ex, var)
    v = Symbolics.value(var)
    for u in Symbolics.get_variables(ex)
        isequal(u, v) || throw(ArgumentError(
            "expected a polynomial in `$var` alone, but `$ex` also involves `$u`. " *
            "Substitute values for the others first, e.g. `substitute(ex, Dict($u => 1))`."))
    end
    nothing
end

# Coefficients of `ex` as rationals, constant term first. Throws unless `ex` really is
# a univariate polynomial over the rationals -- verified by rebuilding it and checking
# the difference expands to zero, which catches everything `degree`/`coeff` would
# otherwise report a plausible-looking answer for.
function _rational_coeffs(ex0, var)
    _only_variable(ex0, var)

    # `coeff` reads coefficients off a sum, so a product such as `(x-1)*(x-2)` has to be
    # multiplied out first -- otherwise every coefficient comes back `0` and the rebuild
    # check below rejects a perfectly good polynomial.
    ex = Symbolics.expand(ex0)

    n = try
        Symbolics.degree(ex, var)
    catch
        throw(ArgumentError("`$ex0` is not a polynomial in `$var`."))
    end
    (n isa Integer && n >= 0) ||
        throw(ArgumentError("`$ex0` is not a polynomial in `$var` (degree `$n`)."))

    cs = Rational{BigInt}[]
    for i in 0:n
        c = Symbolics.value(Symbolics.coeff(ex, var^i))
        r = c isa Number ? _as_rational(c) : nothing
        r === nothing && throw(ArgumentError(
            "the coefficient of `$var^$i` in `$ex0` is `$c`, which is not rational. " *
            "Factoring happens over the rationals, so write exact coefficients " *
            "(`1//2`, not `0.5`)."))
        push!(cs, r)
    end

    rebuilt = sum((_pretty(c) * var^(i - 1) for (i, c) in enumerate(cs)); init = Symbolics.Num(0))
    isequal(Symbolics.expand(ex - rebuilt), 0) ||
        throw(ArgumentError("`$ex0` is not a polynomial in `$var`."))

    cs
end

_nemo_ring() = Nemo.polynomial_ring(Nemo.QQ, "y")

function _to_nemo(cs::Vector{Rational{BigInt}}, R, y)
    p = zero(R)
    for (i, c) in enumerate(cs)
        p += Nemo.QQ(Nemo.ZZ(numerator(c)), Nemo.ZZ(denominator(c))) * y^(i - 1)
    end
    p
end

_to_nemo(ex, var, R, y) = _to_nemo(_rational_coeffs(ex, var), R, y)

function _from_nemo(f, var)
    ex = Symbolics.Num(0)
    for i in 0:Nemo.degree(f)
        c = Nemo.coeff(f, i)
        r = Rational{BigInt}(BigInt(Nemo.numerator(c)), BigInt(Nemo.denominator(c)))
        iszero(r) && continue
        ex += _pretty(r) * var^i
    end
    ex
end

# --------------------------------------------------------------------------------
# factoring
# --------------------------------------------------------------------------------

"""
    poly_factors(ex, var)

Factor the univariate polynomial `ex` over the rationals and return its factors as a
vector, each repeated according to its multiplicity, with any constant factor first.

Use this where a count is wanted -- `length(poly_factors(ex, x))` -- and
[`factored_poly`](@ref) where the factored expression itself is wanted.

Factoring is over the **rationals**, so `x^2 - 2` comes back as a single factor: the
factorisation `(x-√2)(x+√2)` exists but is not rational. `symbolic_solve` will give
those roots.

The order is sorted by degree, so repeated runs and repeated renders agree.

Throws if `ex` is not a polynomial in `var` alone, or if any coefficient is not
rational.

## Examples

```julia
julia> @variables x;

julia> poly_factors(x^3 - 6x^2 + 11x - 6, x)
3-element Vector{Num}:
 -3 + x
 -2 + x
 -1 + x

julia> length(poly_factors(x^12 - 1, x))
6

julia> poly_factors(x^2 - 2, x)          # irreducible over the rationals
1-element Vector{Num}:
 -2 + x^2
```

See also [`factored_poly`](@ref), [`partial_fractions`](@ref).
"""
function poly_factors(ex, var)
    R, y = _nemo_ring()
    p = _to_nemo(ex, var, R, y)

    iszero(p) && return [Symbolics.Num(0)]

    fac = Nemo.factor(p)

    out = Symbolics.Num[]
    u = _from_nemo(Nemo.unit(fac), var)
    isequal(u, 1) || push!(out, u)

    # Nemo's iteration order is not specified; sort so the book renders the same
    # factorisation every time.
    for (f, e) in sort!([(f, e) for (f, e) in fac];
                        by = t -> (Nemo.degree(t[1]), string(t[1])))
        for _ in 1:e
            push!(out, _from_nemo(f, var))
        end
    end

    isempty(out) ? [Symbolics.Num(1)] : out
end

"""
    factored_poly(ex, var)

Factor the univariate polynomial `ex` over the rationals and return the factored
expression.

This is [`poly_factors`](@ref) multiplied back together, and carries the same
restrictions: the factorisation is over the rationals, so `x^2 - 2` is returned
unchanged, and a non-polynomial or non-rational coefficient throws.

## Examples

```julia
julia> @variables x;

julia> factored_poly(x^3 - 6x^2 + 11x - 6, x)
(-3 + x)*(-2 + x)*(-1 + x)

julia> factored_poly(x^2 - 2, x)
-2 + x^2
```

See also [`poly_factors`](@ref), [`partial_fractions`](@ref).
"""
factored_poly(ex, var) = prod(poly_factors(ex, var))

# --------------------------------------------------------------------------------
# partial fractions
# --------------------------------------------------------------------------------

# A partial-fraction denominator is the whole point of the exercise, so show it
# factored -- `(x-1)^2`, not the multiplied-out `1 - 2x + x^2` that Nemo hands back.
function _from_nemo_factored(f, var)
    Nemo.degree(f) <= 1 && return _from_nemo(f, var)

    fac = Nemo.factor(f)
    ex = _from_nemo(Nemo.unit(fac), var)
    for (g, e) in sort!([(g, e) for (g, e) in fac];
                        by = t -> (Nemo.degree(t[1]), string(t[1])))
        ex *= _from_nemo(g, var)^e
    end
    ex
end

function _numerator_denominator(t)
    if _SU.iscall(t) && _SU.operation(t) === /
        a = _SU.arguments(t)
        length(a) == 2 && return a[1], a[2]
    end
    t, 1
end

"""
    partial_fractions(ex, var)

Decompose the rational expression `ex` into partial fractions over the rationals,
returning the decomposition as a symbolic sum (`SymPy` spells this `apart`).

`ex` must be a single quotient of polynomials in `var` -- the shape `p/q` -- or a
polynomial, which is returned unchanged. A sum of separate fractions is not
recognised; put it over a common denominator first with `simplify` or
`simplify_fractions`.

The polynomial part of an improper fraction is included in the sum, and repeated
factors in the denominator produce the expected higher-power terms.

## Examples

```julia
julia> @variables x;

julia> partial_fractions(1/((x-1)*(x-2)), x)
-1 / (-1 + x) + 1 / (-2 + x)

julia> partial_fractions((x+3)/((x-1)^2*(x+2)), x)
(-1//9) / (-1 + x) + (1//9) / (2 + x) + (4//3) / ((-1 + x)^2)

julia> partial_fractions(x^3/((x-1)*(x-2)), x)      # improper: polynomial part included
3 + x + -1 / (-1 + x) + 8 / (-2 + x)
```

See also [`factored_poly`](@ref), [`exact_trig_values`](@ref).
"""
function partial_fractions(ex, var)
    num, den = _numerator_denominator(Symbolics.value(ex))

    R, y = _nemo_ring()
    p = _to_nemo(Symbolics.Num(num), var, R, y)
    q = _to_nemo(Symbolics.Num(den), var, R, y)

    iszero(q) && throw(ArgumentError("the denominator of `$ex` is zero."))
    Nemo.degree(q) == 0 && return Symbolics.Num(ex)

    F = Nemo.fraction_field(R)
    terms = Nemo.partial_fractions(F(p) // F(q))

    out = Symbolics.Num(0)
    for t in terms
        iszero(t) && continue
        n = _from_nemo(Nemo.numerator(t), var)
        d = _from_nemo_factored(Nemo.denominator(t), var)
        out += isequal(d, 1) ? n : n / d
    end
    out
end
