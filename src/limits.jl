"""
    lim(f, c; n=6, m=1, dir="+-")
    lim(f, c, dir; n-5)

Means to generate numeric table of values of `f` as `h` gets close to `c`.

* `n`, `m`: powers of `10` to add (subtract) to (from) `c`.
* `dir`: Either `"+-"` (show left and right), `"+"` (right limit), or `"-"` (left limit). Can also use functions `+`, `-`, `±`.

Example:

```
julia> f(x) = sin(x) / x
f (generic function with 1 method)

julia> lim(f, 0)
 0.1        0.9983341664682815
 0.01       0.9999833334166665
 0.001      0.9999998333333416
 0.0001     0.9999999983333334
 1.0e-5     0.9999999999833332
 1.0e-6     0.9999999999998334
   ⋮          ⋮
   c          L?
   ⋮          ⋮
-1.0e-6     0.9999999999998334
-1.0e-5     0.9999999999833332
-0.0001     0.9999999983333334
-0.001      0.9999998333333416
-0.01       0.9999833334166665
-0.1        0.9983341664682815
```
"""
function lim(f::Function, c::Real; n::Int=6, m::Int=1, dir="+-")
    dir = string(dir)
    Limit(f, c, n, m, dir)
end
lim(f::Function, c::Real, dir; n::Int=6, m::Int=1) = lim(f,c; n, m, dir=string(dir))


struct Limit{F,R}
    f::F
    c::R
    n::Int
    m::Int
    dir::String
end

# try to better align numbers
_l8(x) = length(string(x)) ÷ 8

function Base.show(io::IO, L::Limit)
    f,c,n,m,dir = L.f, L.c, L.n, L.m, L.dir

    ms = maximum(length ∘ string, (c-1/10^n, c+1/10^n))
    sc = (sign(c-m) * sign(c+m) < 0)

    h = 1/10^n
    nt = 2 + maximum(_l8, (c-h, c+h)) + (n ÷ 8)

    if dir == "+" || dir == "+-" || dir == "±"
        show₊(io, L; sc, ms)
    end
    print_dots(io, "c", "L?"; sc, ms)
    if dir == "-" || dir == "--" || dir == "+-" || dir == "±"
        show₋(io, L; sc, ms)
    end
    nothing
end

function show₊(io::IO, L::Limit; sc=false, ms=0)

    f,c,n,m,dir = L.f, L.c, L.n, L.m, L.dir

    hs = [1/10^i for i in m:n] # close to 0
    xsᵣ = c .+ hs
    ysᵣ = string.(f.(xsᵣ))

    last_y = nothing

    for (x,y) ∈ zip(xsᵣ, ysᵣ)
        print_next(io, x, y, last_y; sc, ms)
        last_y = y
        println(io, "")
    end

    print_dots(io; sc, ms)
end

# show - case
function show₋(io::IO, L::Limit; sc=false, ms=0)
    f,c,n,m,dir = L.f, L.c, L.n, L.m, L.dir

    hs = [1/10^i for i in n:-1:m] # close to 0
    xsₗ = c .- hs
    ysₗ = string.(f.(xsₗ))

    last_y = nothing

    i, l = 1, length(ysₗ)
    nl = true
    #dir == "-" && print_dots(io; sc, ms)
    print_dots(io; sc, ms)
    for (x, y) ∈ zip(xsₗ, ysₗ)
        if i == l
            last_y = nothing
            nl = false
        else
            last_y = ysₗ[i+1]
            i += 1
        end
        print_next(io, x, y, last_y; sc, ms)
        nl && println(io, "")
    end

end

# print dots or c L
function print_dots(io::IO, l="⋮", r="⋮"; sc, ms)
    d = ms ÷ 2
    d = 5
    println(io, " "^d, l, " "^(4 +2d), r)
end


# print next number referring to last one for styling
function print_next(io::IO, x, y, last_y=nothing; sc=false, ms=0)
    xₛ = x#string(x)
    sc && x >= 0 && print(io, " ")
    @printf(io, "%.6f", xₛ)
    l = length(xₛ)
    print(io, " "^5) #(max(1, ms - l + 5)))
    if isnothing(last_y)
        print(io, y)
    else
        flag = true
        ly = length(last_y)
        for (i,yᵢ) ∈ enumerate(y)
            if flag && i <= ly && yᵢ == last_y[i]
                printstyled(io, yᵢ; bold=true)
            else
                print(io, yᵢ)
                flag=false
            end
        end
    end
end


# ----------------------------------------------------------------------------
# Symbolic limits
#
# `Symbolics` computes no limits of its own. `SymbolicLimits` supplies a Gruntz
# engine, but it is built for log-exponential asymptotics at infinity and, as of
# v1.1.5, returns silently wrong values for several ordinary calculus inputs. The
# staged approach below reaches for it last, after the routes that are both exact
# and reliable: substitution, cancellation, and series comparison.
# ----------------------------------------------------------------------------

import SymbolicLimits

const _uw = Symbolics.value
_isnum(e)   = _uw(e) isa Number
_symzero(e) = _isnum(e) && iszero(_uw(e))

# Free symbols other than the limit variable, given arbitrary sample values, so that
# the numeric guards below can still run on an expression carrying parameters. The
# limit of ((x+h)^5 - x^5)/h in `h` is 5x^4 — perfectly valid, but nothing about it
# can be evaluated to a number until `x` is pinned down.
function _ground(ex, v)
    vs = Symbolics.get_variables(ex)
    d  = Dict()
    for (i, u) in enumerate(vs)
        isequal(u, Symbolics.unwrap(v)) && continue
        d[u] = 1.3247179572447458 + 0.1i    # nothing special; just not 0, 1 or π
    end
    isempty(d) ? ex : substitute(ex, d)
end

"""
Is a substituted result usable as a limit?

A numeric result must be finite. A *symbolic* result is fine too — `5x^4` is the honest
answer to a limit taken in `h` — provided it no longer mentions the limit variable and
grounds to a finite value. Requiring a `Number` here was a bug: it threw away correct
answers for every limit carrying a parameter, and sent them to the Gruntz engine instead.
"""
function _usable(e, v)
    x = _uw(e)
    x isa Number && return try isfinite(float(x)) catch; false end
    any(isequal(Symbolics.unwrap(v)), Symbolics.get_variables(e)) && return false
    g = _uw(_ground(e, v))
    g isa Number ? (try isfinite(float(g)) catch; false end) : false
end

# Fold an expression to a number at a point; `nothing` if it is not defined there.
function _numfold(ex, v, c)
    try
        f = Symbolics.build_function(_ground(ex, v), v; expression = Val(false))
        y = f(float(c))
        (y isa Number && isfinite(float(y))) ? float(y) : nothing
    catch
        nothing
    end
end

# ----------------------------------------------------------------------------
# One-sided numeric evidence
#
# Every route below can be checked against what the function actually does on
# each side of `c`. That evidence is what distinguishes a limit from a jump, and
# it is the only thing that catches a route returning a confident wrong number.
# ----------------------------------------------------------------------------

# Step sizes stop at 1e-6 deliberately. Finer steps are where floating point
# starts destroying the answer — the numerator of (1 - cos(x))/x^2 underflows to
# exactly zero below about 1e-7 — and a spurious verdict there would suppress
# limits the series route gets exactly right.
const _SIDE_HS = (1e-2, 1e-3, 1e-4, 1e-5, 1e-6)

"""
What the samples on ONE side of `c` say. `s` is `+1` for the right, `-1` for the left.

  * `nothing` — `ex` cannot be evaluated on that side, so its domain does not
    reach `c` from that direction. Not a failure: `log` at `0` is exactly this.
  * `(:finite, y)` — the samples are settling on `y`.
  * `(:diverges, ±Inf)` — the increments are not collapsing and hold one sign.
  * `(:erratic, NaN)` — evaluable, but neither settling nor monotone. No opinion.

Testing the *increments* rather than the magnitude is what catches logarithmic
divergence, which grows by a constant per decade and never passes a fixed threshold.
"""
function _side(ex, v, c, s; hs = _SIDE_HS)
    f = try
        Symbolics.build_function(_ground(ex, v), v; expression = Val(false))
    catch
        return nothing
    end
    ys = Float64[]
    for h in hs
        y = try
            r = f(float(c + s * h))
            (r isa Number && isfinite(float(r))) ? float(r) : nothing
        catch
            nothing
        end
        y === nothing && return nothing
        push!(ys, y)
    end
    d = diff(ys)
    length(d) >= 2 || return (:erratic, NaN)
    maximum(abs, d) < 1e-12       && return (:finite, ys[end])   # constant
    abs(d[end]) < 0.1 * abs(d[1]) && return (:finite, ys[end])   # increments collapsing
    # An increment small against the value itself is convergence however its sign
    # wandered. Without this, float noise in an already-converged sequence — the
    # last samples of (1 - cos(x))/x^2 jitter in the 5th decimal — can land every
    # increment on one sign and read as divergence.
    abs(d[end]) < 1e-3 * max(1, abs(ys[end])) && return (:finite, ys[end])
    all(<(0), d) && return (:diverges, -Inf)
    all(>(0), d) && return (:diverges,  Inf)
    (:erratic, NaN)
end

# Do the two sides tell the same story? `nothing` and `:erratic` are "no opinion",
# never agreement — this is true only on positive, matching evidence.
function _agree(l, r)
    (l === nothing || r === nothing) && return false
    l[1] === r[1] || return false
    # A jump is O(1); what separates the two sides of a continuous function here is
    # only the sampling offset, O(h_min). Anything tighter than this calls
    # (x^2-1)/(x-1) — which samples as 2+h against 2-h — a discontinuity.
    l[1] === :finite   && return abs(l[2] - r[2]) <= 1e-3 * max(1, abs(l[2]), abs(r[2]))
    l[1] === :diverges && return l[2] == r[2]
    false
end

# Is a route's answer consistent with the evidence? True whenever there is nothing
# to contradict it — a symbolic answer that will not ground to a number, an
# `:erratic` side, no evidence at all.
function _consistent(val, ev, v)
    (ev === nothing || ev[1] === :erratic) && return true
    g = _uw(_ground(val, v))
    g isa Number || return true
    y = try float(g) catch; return true end
    ev[1] === :finite && return abs(y - ev[2]) <= 1e-3 * max(1, abs(ev[2]))
    y == ev[2]
end

# Run `f()` on a worker thread, giving up after `secs`. A hung `SymbolicLimits`
# call is CPU-bound and never yields, so a same-thread watchdog would starve —
# this needs Julia started with `-t 2` or more to be effective.
function _timed(f, secs)
    t = Threads.@spawn try f() catch; nothing end
    for _ in 1:round(Int, secs * 20)
        istaskdone(t) && return fetch(t)
        sleep(0.05)
    end
    nothing
end

# Every call into SymbolicLimits goes through here — it is the only stage that
# can fail to terminate.
function _gruntz(ex, v, c; secs = 10, side = :both)
    r = _timed(secs) do
        if side === :both
            SymbolicLimits.limit(Symbolics.unwrap(ex), Symbolics.unwrap(v), c)[1]
        else
            SymbolicLimits.limit(Symbolics.unwrap(ex), Symbolics.unwrap(v), c, side)[1]
        end
    end
    r === nothing ? (nothing, :unresolved) : (r, :gruntz)
end

_coeffs(t, w, n) = Any[substitute(t, Dict(w => 0));
                       [Symbolics.coeff(t, w^k) for k in 1:n]]

# Ranking series only needs to know which coefficient is the first NON-ZERO one, and
# that question is answerable for a symbolic coefficient too: 5x^4 is not zero.
function _coeff_iszero(c)
    x = _uw(c)
    x isa Number && return iszero(x)
    # `iszero` on a symbolic term does not return a Bool, so compare structurally
    # against zero after simplifying.
    isequal(_uw(simplify(c)), 0)
end

# Does any power in `ex` carry an exponent that is not a fixed number? Ranking two
# series by leading order is meaningless when an exponent is unknown: the order of
# `x^k` is `k`, so `sin(sin(x^2))/x^k` has limit 0, 1 or ∞ depending on `k` alone.
# Returning an answer for one of them would be a guess dressed as a computation.
function _symbolic_exponent(ex)
    x = _uw(ex)
    x isa Number && return false
    SU = Symbolics.SymbolicUtils
    try
        SU.iscall(x) || return false
        as = SU.arguments(x)
        if SU.operation(x) === (^) && length(as) == 2
            isempty(Symbolics.get_variables(as[2])) || return true
        end
        return any(_symbolic_exponent, as)
    catch
        return false
    end
end

function _order(cs)
    for (i, c) in pairs(cs)
        _coeff_iszero(c) || return i - 1
    end
    nothing
end

"""
    tlim(num, den, v, c = 0; n = 6)

Limit of `num/den` as `v → c`, evaluated by Taylor series.

Both parts are expanded about `c` and compared by **leading order**: when the two
series start at the same power the limit is the ratio of their leading
coefficients; when the numerator starts higher the limit is `0`. The answer comes
back as an exact `Rational` wherever the coefficients are exact.

This reaches the limits `SymbolicLimits` declines outright — anything involving
trigonometric functions or roots — because a series turns them into polynomials:

```julia
julia> @variables x::Real;

julia> tlim(sin(x), x, x)
1//1

julia> tlim(1 - cos(x), x^2, x)
1//2

julia> tlim(2sin(x) - sin(2x), x - sin(x), x)
6//1
```

Returns `nothing` when the method does not apply: an essential singularity, a
coefficient that stays symbolic, or a numerator vanishing *slower* than the
denominator (a pole rather than a limit).

Two cautions. The expansion point must be one the series can be taken about, so
`v → ∞` is out of reach — use [`symlim`](@ref), which delegates those to the
Gruntz engine. And a series argument is **circular** if used to *derive* the
derivatives its own coefficients assume: proving `[sin(x)]' = cos(x)` from the
Taylor series of `sin` assumes the answer. Computing `lim sin(x)/x` is not
circular in that way, since the limit is the goal rather than a step toward it.

See also [`symlim`](@ref), [`lim`](@ref).
"""
function tlim(num, den, v, c = 0; n = 6)
    (_symbolic_exponent(num) || _symbolic_exponent(den)) && return nothing
    try
        @variables w::Real
        shift(e) = substitute(e, Dict(v => c + w))
        tn = Symbolics.taylor(shift(num), w, 0:n)
        td = Symbolics.taylor(shift(den), w, 0:n)
        cn, cd = _coeffs(tn, w, n), _coeffs(td, w, n)
        on, od = _order(cn), _order(cd)
        (on === nothing || od === nothing) && return nothing
        on >  od && return 0
        on == od && return simplify(cn[on + 1] / cd[od + 1])
        nothing
    catch
        nothing
    end
end

# Is `ex` a ratio of polynomials in the limit variable? Only `+`, `-`, `*`, `/` and
# integer powers qualify — and that is exactly the class the reciprocal route below
# can finish. Admit a `sqrt` or an `exp` and substituting `v -> 1/u` trades a limit
# at infinity for an essential singularity at `0`, which is harder, not easier:
# `x^3/exp(x)` becomes `u^-3/exp(1/u)`, which no stage here can touch even though
# the Gruntz engine handles the original perfectly well.
function _isratpoly(ex)
    x = _uw(ex)
    x isa Number && return true
    SU = Symbolics.SymbolicUtils
    try
        SU.iscall(x) || return true              # a bare symbol
        op, as = SU.operation(x), SU.arguments(x)
        if op === (^)
            _uw(as[2]) isa Integer || return false
            return _isratpoly(as[1])
        end
        (op === (+) || op === (-) || op === (*) || op === (/)) || return false
        return all(_isratpoly, as)
    catch
        false
    end
end

# A rational function at infinity is a rational function at 0 under `v -> ±1/u`,
# where cancellation settles it exactly. The Gruntz engine answers these too, but in
# floating point: `(x^2-2x+2)/(4x^2+3x-2)` comes back as `0.25` where this gives
# `1//4`. A study text should show the rational.
function _reciprocal(ex, v, c, cancel, check, n, secs)
    _isratpoly(ex) || return nothing
    try
        @variables u_recip::Real
        r = substitute(ex, Dict(v => (c > 0 ? 1 : -1) / u_recip))
        val, _ = _symlim(r, u_recip, 0, cancel, check, n, secs, :right)
        val === nothing ? nothing : (val, :reciprocal)
    catch
        nothing
    end
end

# Divergence, read off the side evidence already gathered.
#
# The previous version looped over both sides and returned from inside the loop on
# the first one that diverged, never consulting the second — so `1/x` at `0` came
# back as `+Inf`, the right-hand answer presented as a two-sided limit. A two-sided
# claim now requires both sides to diverge the *same* way. Where only one side is
# defined, that side is the limit, which is the ordinary reading of `lim log(x)`
# as `x → 0`.
function _diverges(side, L, R)
    if side === :both
        if L !== nothing && R !== nothing
            (L[1] === :diverges && R[1] === :diverges && L[2] == R[2]) || return nothing
            return L[2]
        end
        ev = L === nothing ? R : L
    else
        ev = side === :left ? L : R
    end
    (ev !== nothing && ev[1] === :diverges) ? ev[2] : nothing
end

"""
    symlim(ex, v, c; side = :both, cancel = true, check = true, n = 8, secs = 10)

Symbolic limit of the expression `ex` as the variable `v` approaches `c`.

Returns `(value, route)`, where `route` names the method that produced the
answer. A `value` of `nothing` means every method declined — an honest refusal
rather than a guess.

# Routes, in the order they are tried

| route | fires when | exact? |
|:--|:--|:--|
| `:substitution` | `ex` is defined at `c` | yes |
| `:cancel` | a removable singularity `simplify_fractions` clears | yes |
| `:series` | still indeterminate; leading-order Taylor comparison | yes |
| `:reciprocal` | `c` is infinite and `ex` is a ratio of polynomials | yes |
| `:gruntz` | `c` is infinite, or nothing above applied | float |
| `:divergent_numeric` | the value grows without bound | `±Inf` |
| `:sides_disagree` | left and right limits both exist and differ | — |
| `:undefined_on_side` | a `side` was asked for that `ex` does not reach | — |
| `:unresolved` | nothing worked | — |

```julia
julia> @variables x::Real;

julia> symlim((x^2 - 1)/(x - 1), x, 1)
(2, :cancel)

julia> symlim(sin(x)/x, x, 0)
(1//1, :series)

julia> symlim(log(x)/x, x, Inf)
(0, :gruntz)

julia> symlim(x * sin(1/x), x, 0)
(nothing, :unresolved)

julia> symlim(abs(x)/x, x, 0)
(nothing, :sides_disagree)

julia> symlim(abs(x)/x, x, 0; side = :right)
(1, :series)
```

`x·sin(1/x)` has the limit `0`, by the squeeze theorem. No method here can show
that, so none claims to — see *Known limits* below.

# Sidedness

A limit exists at `c` only if the left and right limits both exist and agree, so
`side = :both` refuses when they demonstrably do not: `abs(x)/x` and `1/x` at `0`
are jumps, not limits. Ask for `:left` or `:right` to get the one-sided answer.

Refusing needs *positive* evidence from both sides. Where `ex` simply does not
reach `c` from one direction — `log(x)` at `0`, `x^x` at `0`, anything at the edge
of its domain — the defined side is the answer, which is the ordinary reading of
`lim_{x→0} log(x) = -∞`. Only a genuine two-sided disagreement is refused.

# Why the ordering matters

`Symbolics` computes no limits itself; the available engine, `SymbolicLimits`,
implements the Gruntz algorithm for log-exponential asymptotics at infinity. It is
excellent at that and unreliable elsewhere. As of v1.1.5 it does not cancel common
factors, so `limit((x^2-1)/(x-1), x, 1)` returns `0` rather than `2` — with its
assumption set reporting confidence. Cancelling and series comparison are tried
first because they are both exact and dependable; the engine is asked last, and
only for the work it was built for.

# Keyword arguments

  * `cancel = true` — clear removable singularities before the engine ever sees
    the expression. Setting `false` skips *that stage only*; the series stage
    below it will usually still find the right answer, so this is not a way to
    observe the underlying engine misbehaving. Use `check = false` for that, or
    call `SymbolicLimits.limit` directly.
  * `side = :both` — `:left` or `:right` for a one-sided limit. See *Sidedness*.
  * `check = true` — require every route's answer to agree with the numeric
    evidence on the side being approached, and move to the next route when it does
    not. Leave this on: the failure modes it guards against are silent, so nothing
    else will catch them. Setting `false` returns the first route's answer
    unchecked, which is the way to watch the engine misbehave.
  * `n` — highest order used by the series route.
  * `secs` — deadline for the Gruntz stage, which is the only one that can fail
    to terminate. **Start Julia with `-t 2` or more**, or the watchdog cannot run:
    a hung call never yields, so a same-thread timer would never fire.

# Known limits

  * **Expansion points involving `π`.** `Symbolics.taylor` converts `π` to a float
    and then to a rational, so a series about `π/2` carries a spurious constant
    term near `1e-17` instead of an exact `0`, which defeats leading-order
    ranking. `Num(pi)` does not help. Use [`lim`](@ref) for those.
  * **`(1 + 1/x)^x` as `x → ∞`.** `SymbolicLimits` does not terminate on this, nor
    on the log/exp rewrite its own error message suggests; the deadline returns
    `:unresolved`.
  * **Oscillatory expressions** such as `x·sin(1/x)`. Their limits follow from the
    squeeze theorem, which is not a computation any of these routes performs.
  * **`log` divergence cannot be delegated.** `SymbolicLimits.limit(log(u), u, 0,
    :right)` returns `0` rather than `-Inf` (v1.1.5). That answer now fails the
    `check` comparison and is discarded, and the numeric increment test supplies
    the `-Inf` — load-bearing, not a convenience.
  * **Unknown symbolic exponents.** The order of `x^k` is `k`, so the limit of
    `sin(sin(x^2))/x^k` at `0` is `0`, `1` or `∞` depending on `k` alone. The
    series route declines rather than picking one; substitute a concrete `k`, or
    rewrite `a^x` as `exp(x·log(a))` where the exponent is no longer the unknown.
  * **Limits at infinity are mostly the Gruntz engine.** Ratios of polynomials go
    through `:reciprocal` and come back exact. Everything else is a time-boxed call
    into the engine, with no numeric evidence to check it against and no series to
    take. It handles pure power/log/exp forms; add a `sin` or a `sqrt` —
    `exp(-x)·sin(x)`, `x/sqrt(x^2+4)` — and the answer is `:unresolved`.

See also [`tlim`](@ref), [`lim`](@ref).
"""
function symlim(ex, v, c; side = :both, cancel = true, check = true, n = 8, secs = 10)
    side in (:both, :left, :right) ||
        throw(ArgumentError("side must be :both, :left or :right; got $(repr(side))"))
    _symlim(ex, v, c, cancel, check, n, secs, side)
end

function _symlim(ex, v, c, cancel, check, n, secs, side)
    if !(c isa Number && isfinite(float(c)))
        # Rational functions first, for an exact answer; everything else is the
        # engine's own territory.
        r = _reciprocal(ex, v, c, cancel, check, n, secs)
        r === nothing || return r
        return _gruntz(ex, v, c; secs, side)
    end

    L = side === :right ? nothing : _side(ex, v, c, -1)
    R = side === :left  ? nothing : _side(ex, v, c, +1)

    if side === :both
        # A genuine jump: both sides speak, and they disagree. Refuse. This is the
        # case that used to come back as a confident wrong number — `abs(x)/x` at 0
        # returned `1.0`, `1/x` at 0 returned `Inf`.
        if L !== nothing && R !== nothing &&
           L[1] !== :erratic && R[1] !== :erratic && !_agree(L, R)
            return (nothing, :sides_disagree)
        end
    elseif (side === :left ? L : R) === nothing
        return (nothing, :undefined_on_side)
    end

    # The evidence each route's answer is checked against. Where both sides speak
    # they agree by now, so either serves; where only one does, that is the side the
    # limit is taken along.
    ev = side === :left ? L : side === :right ? R : (L === nothing ? R : L)
    ok(val) = !check || _consistent(val, ev, v)

    sub(e) = substitute(e, Dict(v => c))

    # 1. direct substitution — only where `ex` is genuinely defined at `c`.
    #    Symbolics folds `0 * sin(1/0)` to `0` by the zero-product rule, which is
    #    the right answer for the wrong reason; requiring a finite numeric value
    #    at `c` rejects that.
    num, den = numerator(ex), denominator(ex)
    n0, d0 = sub(num), sub(den)
    if _usable(d0, v) && !_symzero(d0) && _usable(n0, v) && _numfold(ex, v, c) !== nothing
        val = simplify(n0 / d0)
        ok(val) && return (val, :substitution)
    end

    # 2. put over a common denominator and cancel. After a genuine cancellation
    #    the reduced form is defined at `c` — `(x^2-1)/(x-1)` becomes `x+1` — so
    #    the same definedness test admits every real cancellation.
    q = ex
    if cancel
        try
            q = Symbolics.simplify_fractions(ex)
            nq, dq = sub(numerator(q)), sub(denominator(q))
            if _usable(dq, v) && !_symzero(dq) && _usable(nq, v) && _numfold(q, v, c) !== nothing
                val = simplify(nq / dq)
                ok(val) && return (val, :cancel)
            end
        catch
            q = ex
        end
    end

    # 3. series comparison
    for target in (q, ex)
        r = tlim(numerator(target), denominator(target), v, c; n)
        r === nothing && continue
        ok(r) && return (r, :series)
    end

    # 4. the Gruntz engine, last and time-boxed. Its answer is checked like any
    #    other — this is what demotes `limit(log(u), u, 0, :right) -> 0` (v1.1.5)
    #    rather than passing it on.
    g = _gruntz(ex, v, c; secs, side)
    g[1] !== nothing && ok(g[1]) && return g

    # 5. numeric evidence of divergence
    d = _diverges(side, L, R)
    d === nothing || return (d, :divergent_numeric)

    (nothing, :unresolved)
end

