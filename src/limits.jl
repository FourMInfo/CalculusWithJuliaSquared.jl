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
import IntervalArithmetic

const _uw = Symbolics.value
_isnum(e)   = _uw(e) isa Number
_symzero(e) = _isnum(e) && iszero(_uw(e))

# Free symbols other than the limit variable, given arbitrary sample values, so that
# the numeric guards below can still run on an expression carrying parameters. The
# limit of ((x+h)^5 - x^5)/h in `h` is 5x^4 — perfectly valid, but nothing about it
# can be evaluated to a number until `x` is pinned down.
#
# The sample is keyed by the symbol's NAME and kept for the session, so `c` grounds to
# the same number in every call. It used to be assigned by the symbol's position in
# `get_variables`, and that position is not stable: `c` is the second variable of
# `x^2 + c` but the first of the answer `c` on its own. The evidence was gathered at
# one value and the answer judged at another, the check rejected a correct
# `:substitution`, and the fall-through reached `:squeeze`, which grounded `c` a third
# time and reported the sample: `symlim(3x^2 + c, x, 0; side = :right)` returned
# `1.5247…`. Found on the continuity chapter, whose one site is exactly that.
const _GROUND_SAMPLES = Dict{Symbol,Float64}()
const _GROUND_LOCK    = ReentrantLock()

function _ground_sample(u)
    lock(_GROUND_LOCK) do
        get!(_GROUND_SAMPLES, Symbol(string(u))) do
            1.3247179572447458 + 0.1 * (length(_GROUND_SAMPLES) + 1)   # not 0, 1 or π
        end
    end
end

function _ground(ex, v)
    d = Dict()
    for u in Symbolics.get_variables(ex)
        isequal(u, Symbolics.unwrap(v)) && continue
        d[u] = _ground_sample(u)
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
    _fold_const(e, v) === nothing || return true
    g = _uw(_ground(e, v))
    g isa Number ? (try isfinite(float(g)) catch; false end) : false
end

# An expression that is already constant but left UNEVALUATED.
#
# `substitute(sqrt(x), x => 0)` returns `sqrt(0)`, not `0`. That is not a `Number`,
# and `_ground` cannot help because there are no free parameters to fill in — so the
# substitution route judged a perfectly good answer unusable and declined. Found via
# `symlim(sqrt(x), x, 0; side = :right)`, which returned `:unresolved` although the
# limit is plainly `0`; the value was already available from `_numfold` all along.
# Any `f(c)` Symbolics chooses not to evaluate hits this, so fold it here rather
# than special-casing the function.
function _fold_const(e, v)
    x = _uw(e)
    x isa Number && return isfinite(float(x)) ? x : nothing
    isempty(Symbolics.get_variables(e)) || return nothing
    try
        f = Symbolics.build_function(e, v; expression = Val(false))
        y = f(0.0)
        (y isa Number && isfinite(float(y))) ? y : nothing
    catch
        nothing
    end
end

# Return the folded number where the expression is constant, otherwise unchanged --
# `5x^4` must stay symbolic, it is the honest answer to a limit taken in `h`.
function _maybe_fold(e, v)
    y = _fold_const(e, v)
    y === nothing && return e
    isinteger(y) && abs(y) < 1e15 ? Int(y) : y
end

# Which sign does `g` hold just to one side of `c`? `s` is `+1` for the right, `-1`
# for the left. Returns `0` when the samples disagree or `g` cannot be evaluated
# there, so callers can decline rather than guess.
function _sidesign(g, v, c, s; hs = (1e-2, 1e-4, 1e-6, 1e-8))
    ys = Float64[]
    for h in hs
        y = _numfold(g, v, c + s * h)
        y === nothing && return 0
        push!(ys, y)
    end
    all(>(0), ys) && return  1
    all(<(0), ys) && return -1
    0
end

# `abs` has no derivative at a sign change, so `Symbolics.taylor(abs(w), w, 0:n)`
# grounds it as `w` — right approaching from the right, wrong from the left, and
# silently so. Nothing downstream recovers: `abs(x)/x` at `0` gave `1` for `:right`
# but `:unresolved` for `:left`, where the answer is `-1`.
#
# Resolve each `abs` against the side actually being approached, by sampling its
# argument there: on a side where the argument keeps one sign, `abs(g)` is `g` or
# `-g` and the series stage sees a function it can expand. Where the sign is not
# settled (a zero crossing inside the sample window) the `abs` is left in place and
# the route declines, as before — this widens what `tlim` can answer, and never
# invents a value.
function _resolve_abs(ex, v, c, side)
    side === :both && return ex
    s  = side === :left ? -1 : +1
    SU = Symbolics.SymbolicUtils
    try
        x = _uw(ex)
        SU.iscall(x) || return ex
        op   = SU.operation(x)
        args = [_resolve_abs(a, v, c, side) for a in SU.arguments(x)]
        if op === abs
            g  = args[1]
            sg = _sidesign(g, v, c, s)
            sg ==  1 && return g
            sg == -1 && return -g
            return abs(g)
        end
        op(args...)
    catch
        ex
    end
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
    # Divergence is a property of the tail, so judge the sign there. The first
    # increment is taken at the coarsest step, where a smooth term can still be
    # moving faster than the singular one and briefly reverse the sign: for
    # x^2 + 1 + log(abs(11x-15))/99 at 15//11 the x^2 term outruns the log over the
    # first decade, and requiring *every* increment to agree lost a genuine
    # divergence the published notes depended on.
    t = @view d[2:end]
    all(<(0), t) && return (:diverges, -Inf)
    all(>(0), t) && return (:diverges,  Inf)
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
#
# A constant that Symbolics leaves UNEVALUATED is an opinion, not the absence of one.
# `substitute(sign(x), x => 0)` is `sign(0)`, which is not a `Number`, and treating it
# as "nothing to contradict" let `symlim(sign(x), x, 0; side = :right)` return
# `(sign(0), :cancel)` — that is `0`, where the limit is `1`. Fold before judging.
function _consistent(val, ev, v)
    (ev === nothing || ev[1] === :erratic) && return true
    gv = _ground(val, v)
    g  = _uw(gv)
    if !(g isa Number)
        y0 = _fold_const(gv, v)
        y0 === nothing && return true
        g = y0
    end
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

# Julia's `/` on two `Int`s produces a `Float64`, so a series ratio whose leading
# coefficients are both integers came back as `1.0` where the limit is exactly `1`.
# The same reason the `:reciprocal` route exists — a study text should show the
# rational. Anything not a pair of integers divides as before.
function _exact_ratio(a, b)
    x, y = _uw(a), _uw(b)
    (x isa Integer && y isa Integer && !iszero(y)) ? x // y : a / b
end

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

Pass `side = :left` or `:right` where the expression contains an `abs`. A series
cannot see a sign change: `Symbolics.taylor(abs(w), w, 0:n)` returns `w`, which is
the right answer only from the right. Given a side, each `abs` is first resolved
against the sign its argument actually holds there, so `abs(x)/x` at `0` expands to
`x/x` on the right and `-x/x` on the left:

```julia
julia> @variables x::Real;

julia> tlim(abs(x), x, x, 0; side = :right), tlim(abs(x), x, x, 0; side = :left)
(1, -1)
```

Where the sign is not settled the `abs` stays put and the method declines.

Two cautions. The expansion point must be one the series can be taken about, so
`v → ∞` is out of reach — use [`symlim`](@ref), which delegates those to the
Gruntz engine. And a series argument is **circular** if used to *derive* the
derivatives its own coefficients assume: proving `[sin(x)]' = cos(x)` from the
Taylor series of `sin` assumes the answer. Computing `lim sin(x)/x` is not
circular in that way, since the limit is the goal rather than a step toward it.

See also [`symlim`](@ref), [`lim`](@ref).
"""
function tlim(num, den, v, c = 0; n = 6, side = :both)
    (_symbolic_exponent(num) || _symbolic_exponent(den)) && return nothing
    try
        @variables w::Real
        num, den = _resolve_abs(num, v, c, side), _resolve_abs(den, v, c, side)
        shift(e) = substitute(e, Dict(v => c + w))
        tn = Symbolics.taylor(shift(num), w, 0:n)
        td = Symbolics.taylor(shift(den), w, 0:n)
        cn, cd = _coeffs(tn, w, n), _coeffs(td, w, n)
        on, od = _order(cn), _order(cd)
        (on === nothing || od === nothing) && return nothing
        on >  od && return 0
        on == od && return simplify(_exact_ratio(cn[on + 1], cd[od + 1]))
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

# `v -> 1/u` for anything, tried as a LAST resort.
#
# `_reciprocal` above is gated to ratios of polynomials, and that gate is right as a
# *first* choice: substituting into `x^3/exp(x)` yields `u^-3/exp(1/u)`, which looks
# far worse. But the stated fear does not survive measurement — that very expression
# resolves at `0+` — and the gate blocks cases where the substitution is the whole
# answer. `n*log(1 + 1/n)` at infinity is refused by every route; under `u = 1/n` it
# is `log(1+u)/u` at `0`, which the series route settles exactly as `1`.
#
# So: try it for anything, but only after every other route has declined, and only
# accept an answer the numeric evidence agrees with. Nothing that already resolves
# can reach this stage, so no existing route label moves.
function _recip_general(ex, v, c, cancel, check, n, secs)
    (c isa Number && isfinite(float(c))) && return nothing   # only at ±∞
    try
        @variables u_rg::Real
        r = substitute(ex, Dict(v => (c > 0 ? 1 : -1) / u_rg))
        # Substituting `v -> 1/u` routinely leaves a nested fraction the later
        # stages cannot see through: `n*log(n/(n+1))` becomes
        # `(1/u)*log((1/u)/((1/u)+1))`, whose series expansion fails, while the
        # reduced `log(1/(1+u))/u` settles at once. Try the reduced form too.
        # Each candidate needs its OWN guard: the raw substituted form can *throw*
        # rather than decline -- `n*log(n/(n+1))` becomes `log(1/((1 + 1/u)*u))/u`,
        # which raises a DivideError -- and a single shared `try` would let that
        # abort the loop before the reduced forms, which do resolve, are ever tried.
        for cand in (r, (try Symbolics.simplify_fractions(r) catch; nothing end),
                        (try simplify(r) catch; nothing end))
            cand === nothing && continue
            got = try
                _symlim(cand, u_rg, 0, cancel, check, n, secs, :right)
            catch
                continue
            end
            (got[1] === nothing || got[2] === :unresolved) && continue
            return got[1]
        end
        nothing
    catch
        nothing
    end
end

# The limit of a composition, which is the rule the text states but the tooling did
# not implement: for `f` continuous at `L`, `lim f(h(x)) = f(lim h(x))`.
#
# This is what stood between `symlim` and the `1^∞` family. `(1 + 1/n)^n` at infinity
# is refused by every route, yet its inner limit is available exactly — rewrite the
# power as `exp(n·log(1 + 1/n))`, take the inner limit (`1`), and the answer is `e`.
# Without this stage the book had to do that composition in prose, which teaches the
# reader nothing they can reuse.
#
# Tried last, after `:squeeze`, so it can only ever turn an `:unresolved` into an
# answer — no expression that already resolves reaches here.
const _CONTINUOUS = (exp, sin, cos, atan, tanh, sinh, cosh)

function _composition(ex, v, c, cancel, check, n, secs, side, depth)
    depth > 3 && return nothing
    SU = Symbolics.SymbolicUtils
    x = _uw(ex)
    SU.iscall(x) || return nothing
    op, as = SU.operation(x), SU.arguments(x)

    # `f^g` with the variable in the exponent is the indeterminate-power family;
    # rewrite to log-exp form and let the `exp` branch below handle it.
    if op === (^) && length(as) == 2
        base, expo = as
        vars = Symbolics.get_variables(expo)
        if any(isequal(Symbolics.unwrap(v)), vars)
            return _composition(exp(expo * log(base)), v, c, cancel, check, n, secs, side, depth + 1)
        end
        return nothing
    end

    (op in _CONTINUOUS && length(as) == 1) || return nothing

    L, route = _symlim(as[1], v, c, cancel, check, n, secs, side, depth + 1)
    (L === nothing || route === :unresolved) && return nothing

    g = _uw(L)
    g isa Number || return nothing
    y = try float(g) catch; return nothing end

    # `exp` is the one place an infinite inner limit is still informative:
    # `exp(-Inf)` is 0 and `exp(Inf)` is Inf. Everything else needs a finite `L`.
    if !isfinite(y)
        op === exp || return nothing
        return y == -Inf ? 0.0 : Inf
    end
    val = try op(L) catch; return nothing end
    _usable(val, v) || return nothing
    _confirms(ex, v, c, val, side) ? val : nothing
end

# Does the original expression actually approach `val`? Composition applies `f` to an
# inner limit, so an error in either half would otherwise pass straight through — and
# a plausible wrong number is the failure mode this whole package exists to avoid.
# At a finite `c` the ordinary side evidence already covers it; this is the check for
# `c = ±∞`, where no `_side` evidence is gathered.
function _confirms(ex, v, c, val, side; xs = (1e2, 1e3, 1e4))
    y = _uw(val)
    y isa Number || return true
    target = try float(y) catch; return true end
    s = (c isa Number && isfinite(float(c))) ? nothing : (c > 0 ? 1 : -1)
    s === nothing && return true
    seen = Float64[]
    for X in xs
        z = _numfold(ex, v, s * X)
        z === nothing && return false
        push!(seen, z)
    end
    if isfinite(target)
        # the last sample should be near the claimed limit, and the trend toward it
        return abs(seen[end] - target) <= 1e-2 * max(1, abs(target)) &&
               abs(seen[end] - target) <= abs(seen[1] - target) + 1e-9
    end
    target ==  Inf && return all(>(0), seen) && seen[end] > seen[1]
    target == -Inf && return all(<(0), seen) && seen[end] < seen[1]
    true
end

# Does the answer depend on a free parameter we were never told anything about?
#
# `Symbolics` has no assumptions system, so a symbol carries no sign or range. The
# engine will then happily answer for *one* branch with nothing marking which:
# `exp(n·log(1+delta)) - n` at infinity returns `-Inf`, correct for `delta < 0` and
# the exact opposite of the `delta > 0` reading a reader almost certainly intends.
# That is worse than a refusal, because it arrives looking like an ordinary result.
#
# `symlim` already refuses when the two *sides* disagree. This is the same refusal
# for two parameter *branches*: pin each free parameter to a positive and a negative
# sample, take the limit again, and if specialising the general answer contradicts
# the specialised limit, decline and say why.
#
# The same check guards every route that can only produce a NUMBER — `:squeeze`,
# `:divergent_numeric`, the engine at a finite point. Those routes work on the
# grounded expression, so with a free parameter present their answer is a statement
# about the sample value, not about the parameter: `c + x*sin(1/x)` at 0 came back as
# `(1.4247…, :squeeze)`, the sample standing in for `c`. Specialising catches it, and
# leaves `c*x*sin(1/x)` — whose limit is 0 for every `c` — alone.
#
# Every parameter is pinned to the same probe, which keeps this to two extra limits
# however many parameters there are. The earlier cap of two parameters saved nothing
# and removed the guard exactly where a fabricated number is hardest to notice.
function _param_dependent(ex, v, c, val, cancel, check, n, secs, side)
    ps = [p for p in Symbolics.get_variables(ex)
          if !isequal(p, Symbolics.unwrap(v))]
    isempty(ps) && return false
    for probe in (1//2, -1//2)
        d = Dict(p => probe for p in ps)
        specialised = try
            s, r = _symlim(substitute(ex, d), v, c, cancel, check, n, secs, side)
            (s === nothing || r === :unresolved) && continue
            _uw(s)
        catch
            continue
        end
        general = try _uw(substitute(val, d)) catch; continue end
        (specialised isa Number && general isa Number) || continue
        a = try float(specialised) catch; continue end
        b = try float(general)     catch; continue end
        if isnan(a) || isnan(b) ||
           (isinf(a) || isinf(b) ? a != b : abs(a - b) > 1e-3 * max(1, abs(a), abs(b)))
            return true
        end
    end
    false
end

# The squeeze theorem, computed.
#
# Evaluate `ex` over a nested sequence of intervals closing on `c`, using interval
# arithmetic, which returns a *rigorous enclosure* of every value the function takes
# on that interval. If the enclosures collapse to a point, the limit exists and is
# that point — every nearby value is trapped in a box whose width goes to zero,
# which is exactly the squeeze argument. If they stay wide, there is nothing to
# report and the route declines: `sin(x)` at infinity encloses to `[-1, 1]` at every
# scale, correctly, because it has no limit.
#
# The boxes EXCLUDE `c` itself: `[c + h/10, c + h]` on the right, its mirror on the
# left, and for a two-sided limit the hull of the two must collapse. A limit never
# consults `f(c)`, so this is the faithful formulation, and it is the one that lets
# a step function resolve from one side — `floor` over `[-h, -h/10]` is `[-1, -1]`,
# while over `[-h, 0]` it was `[-1, 0]` and never collapsed. It is also monotone:
# the annulus sits inside the old box, so nothing that collapsed before stops.
#
# The answer is the simplest number that lies rigorously inside the final enclosure
# (`_snap`): `0` when the box contains it, a rational with a small denominator when
# one fits, otherwise the float. Reporting the midpoint gave `-1.0e-14` for
# `x^2*(cos(1/x) - 1)` at 0, which is arithmetic debris, not a limit.
#
# `build_function` emits `NaNMath` calls by default and NaNMath has no interval
# methods, so `nanmath = false` is required, not cosmetic.
#
# Only `interval`, `inf`, `sup` and the `Interval` type are used, all of which behave
# identically on IntervalArithmetic 0.20 and 1.x. The compat bound admits both
# deliberately: `ImplicitEquations` (used by the notes' implicit-plotting chapters)
# pins 0.20.9 even at its latest release, and requiring 1.x here would make this
# package unusable alongside it.
#
# Tried LAST. Intervals are useless on the indeterminate forms the earlier routes
# exist for: `sin(x)/x` over `[h/10, h]` encloses to roughly `[0.1, 10]` however
# small `h` is, because interval arithmetic cannot see that the two occurrences of
# `x` are the same number (the dependency problem). `x*floor(1/x)` declines for the
# same reason. That ordering is a starting position rather than a considered design —
# see the workplan note in the notes repo before changing it on one example.
function _snap(lo, hi)
    lo <= 0 <= hi && return 0
    mid = (lo + hi) / 2
    r = try
        rationalize(Int, mid; tol = (hi - lo) / 2 + 4eps(mid))
    catch
        return mid
    end
    (lo <= r <= hi && denominator(r) <= 100) || return mid
    denominator(r) == 1 ? numerator(r) : r
end

function _squeeze(ex, v, c, side; hs = (1e-1, 1e-3, 1e-5, 1e-7))
    IA = IntervalArithmetic
    f = try
        Symbolics.build_function(_ground(ex, v), v; expression = Val(false), nanmath = false)
    catch
        return nothing
    end
    finite = c isa Number && isfinite(float(c))
    sides  = finite ? (side === :right ? (+1,) : side === :left ? (-1,) : (-1, +1)) :
                      (c > 0 ? (+1,) : (-1,))
    los, his = Float64[], Float64[]
    for h in hs
        lo, hi = Inf, -Inf
        for s in sides
            box = try
                if finite
                    cf = float(c)
                    s > 0 ? IA.interval(cf + h / 10, cf + h) : IA.interval(cf - h, cf - h / 10)
                else
                    m = 1 / h
                    s > 0 ? IA.interval(m, 1e300) : IA.interval(-1e300, -m)
                end
            catch
                return nothing
            end
            y = try f(box) catch; return nothing end
            y isa IA.Interval || return nothing
            l, u = IA.inf(y), IA.sup(y)
            (isfinite(l) && isfinite(u)) || return nothing
            lo, hi = min(lo, l), max(hi, u)
        end
        push!(los, lo)
        push!(his, hi)
    end
    wids = his .- los
    length(wids) >= 2 || return nothing
    mid = (los[end] + his[end]) / 2
    # Closing at the rate the scales close. The step sizes fall by 1e-6 across `hs`,
    # so a function with a limit sees its enclosure widths fall by about that factor
    # too. The bound is RELATIVE, which makes the coefficient's size irrelevant —
    # `1000*x*sin(1/x)` closes as surely as `x*sin(1/x)`, where an absolute `1e-6`
    # refused it, and refused `c*x*sin(1/x)` or not depending on which sample value
    # the session had handed `c`. A width that stays put is an oscillation, however
    # tiny: `1e-9*sin(1/x)` sits under any absolute bound at every scale and has no
    # limit. A zero-width enclosure is a step function, already closed. The price is
    # that a limit approached more slowly than linearly — `sqrt(x)*sin(1/x)` —
    # declines; at four scales there is no telling it from an oscillation.
    closing = wids[1] == 0 ? wids[end] == 0 : wids[end] <= 3e-6 * wids[1]
    closing                                      || return nothing
    wids[end] < 1e-3 * max(1, abs(mid))          || return nothing
    _snap(los[end], his[end])
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
| `:squeeze` | interval enclosures, `c` excluded, collapse to a point | simplest number inside them |
| `:composition` | `lim f(h) = f(lim h)` for `f` continuous at the inner limit | inherits |
| `:sides_disagree` | left and right limits both exist and differ | — |
| `:undefined_on_side` | a `side` was asked for that `ex` does not reach | — |
| `:parameter_dependent` | the answer turns on a free parameter, or a numeric route would have to invent a value for one | — |
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
(0, :squeeze)

julia> symlim(abs(x)/x, x, 0)
(nothing, :sides_disagree)

julia> symlim(abs(x)/x, x, 0; side = :right)
(1//1, :series)

julia> symlim(abs(x)/x, x, 0; side = :left)
(-1//1, :series)

julia> symlim(floor(x), x, 0; side = :right), symlim(floor(x), x, 0; side = :left)
((0, :substitution), (-1, :squeeze))

julia> @variables c::Real;

julia> symlim(3x^2 + c, x, 0; side = :right)
(c, :substitution)
```

`x·sin(1/x)` has the limit `0` by the squeeze theorem, which the `:squeeze` route
establishes: interval arithmetic bounds the function on a shrinking neighbourhood of
`0`, and the enclosures collapse to a point. Where they do not collapse the route
declines — `sin(x)` at infinity encloses to `[-1, 1]` at every scale, correctly,
because it has no limit. The boxes exclude `c` itself, since a limit never consults
`f(c)`; that is what lets `floor` resolve from the left, where the value at `0` is
not the limit.

`:substitution` is the definition of continuity, computed: the value at `c` exists and
the function approaches it. The route says so. `floor` from the right is
`:substitution` and from the left is not, which is the statement that `floor` is
right-continuous at the integers.

A free parameter rides through the exact routes — `c`, `5x^4`, `1/x` are all honest
answers to limits taken in another variable. A route that can only produce a number
(`:squeeze`, `:divergent_numeric`, the engine at a finite point) is not allowed to
invent a value for one, and refuses with `:parameter_dependent` instead.

# Sidedness

A limit exists at `c` only if the left and right limits both exist and agree, so
`side = :both` refuses when they demonstrably do not: `abs(x)/x` and `1/x` at `0`
are jumps, not limits. Ask for `:left` or `:right` to get the one-sided answer.

Refusing needs *positive* evidence from both sides. Where `ex` simply does not
reach `c` from one direction — `log(x)` at `0`, `x^x` at `0`, anything at the edge
of its domain — the defined side is the answer, which is the ordinary reading of
`lim_{x→0} log(x) = -∞`, and every route is asked for that side's limit. Only a
genuine two-sided disagreement is refused.

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
    ranking. A `Num` limit point such as `Num(pi)/2` is folded to a float at the
    door, so it behaves exactly like `pi/2` and does not help either. Use
    [`lim`](@ref) for those.
  * **`(1 + 1/x)^x` as `x → ∞`.** `SymbolicLimits` does not terminate on this, nor
    on the log/exp rewrite its own error message suggests; the deadline returns
    `:unresolved`.
  * **Oscillation without a limit.** `sin(x)` as `x → ∞` genuinely has none. The
    `:squeeze` route treats its enclosure `[-1, 1]` as a refusal rather than an answer;
    call `IntervalArithmetic` directly to see the bound itself, which is the closest
    analogue to what a `SymPy` user gets from `AccumBounds`.
  * **`:squeeze` is tried last**, because interval arithmetic cannot see that two
    occurrences of `x` are the same number: `sin(x)/x` over `[h/10, h]` encloses to
    roughly `[0.1, 10]` however small `h` is, and `x·floor(1/x)` declines the same way.
    Every exact route is asked first for that reason. The enclosures must close at
    the rate the scales do, so `sqrt(x)·sin(1/x)` — whose limit is `0`, approached
    too slowly — declines. Its answer is the simplest number lying rigorously inside
    the final enclosure — `0`, a rational with a small denominator, otherwise the
    float — so `x·sin(1/x)` reports `0`, not `-1.0e-14`.
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
    # `Num <: Number`, so `c isa Number` does not exclude a symbolic limit point, and
    # `tan(x)` at `Num(pi)/2` died with a `MethodError` from `float(c)` deep inside a
    # numeric stage. A constant `Num` folds here; a genuinely symbolic point is refused
    # at the door, where the message can say what was wrong.
    if !(c isa Real) || c isa Num
        y = try
            cn = c isa Num ? c : Symbolics.Num(c)
            isempty(Symbolics.get_variables(cn)) ? _fold_const(cn, v) : nothing
        catch
            nothing
        end
        y === nothing &&
            throw(ArgumentError("the limit point must be a real number or ±Inf; got $(repr(c))"))
        c = isinteger(y) && abs(y) < 1e15 ? Int(y) : y
    end
    _symlim(ex, v, c, cancel, check, n, secs, side)
end

function _symlim(ex, v, c, cancel, check, n, secs, side, depth = 0)
    # Guard every answer that carries a free parameter: an engine with no
    # assumptions system will answer for one branch without saying which.
    pd(val) = _param_dependent(ex, v, c, val, cancel, check, n, secs, side)

    if !(c isa Number && isfinite(float(c)))
        # Rational functions first, for an exact answer; everything else is the
        # engine's own territory.
        r = _reciprocal(ex, v, c, cancel, check, n, secs)
        if r !== nothing
            return pd(r[1]) ? (nothing, :parameter_dependent) : r
        end
        g = _gruntz(ex, v, c; secs, side)
        if g[1] !== nothing
            return pd(g[1]) ? (nothing, :parameter_dependent) : g
        end
        sq = _squeeze(ex, v, c, side)
        sq === nothing || return pd(sq) ? (nothing, :parameter_dependent) : (sq, :squeeze)
        # Last resorts. Composition first, so the reported route names the method
        # that actually settled it: `(1 + 1/n)^n` is the composition rule applied to
        # a rewritten power, and reporting `:reciprocal` for it would describe the
        # substitution that merely got the inner limit within reach.
        co = _composition(ex, v, c, cancel, check, n, secs, side, depth)
        if co !== nothing
            return pd(co) ? (nothing, :parameter_dependent) : (co, :composition)
        end
        rg = _recip_general(ex, v, c, cancel, check, n, secs)
        if rg !== nothing
            return pd(rg) ? (nothing, :parameter_dependent) : (rg, :reciprocal)
        end
        return (nothing, :unresolved)
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
        # Reaching `c` from one direction only is a one-sided limit in all but name,
        # and the routes should be asked for one. `exp(x*log(x))` at 0 was
        # `:unresolved` two-sided while `side = :right` gave `(1, :gruntz)`: the
        # engine was being asked about a side on which the function does not exist.
        if (L === nothing) ⊻ (R === nothing)
            side = L === nothing ? :right : :left
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
        val = _maybe_fold(simplify(n0 / d0), v)
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
                val = _maybe_fold(simplify(nq / dq), v)
                ok(val) && return (val, :cancel)
            end
        catch
            q = ex
        end
    end

    # 3. series comparison
    for target in (q, ex)
        r = tlim(numerator(target), denominator(target), v, c; n, side)
        r === nothing && continue
        ok(r) && return (r, :series)
    end

    # 4. the Gruntz engine, last and time-boxed. Its answer is checked like any
    #    other — this is what demotes `limit(log(u), u, 0, :right) -> 0` (v1.1.5)
    #    rather than passing it on.
    #    A free parameter makes each of the three numeric answers below a statement
    #    about the grounding sample, not the parameter — see `_param_dependent`.
    g = _gruntz(ex, v, c; secs, side)
    if g[1] !== nothing && ok(g[1])
        return pd(g[1]) ? (nothing, :parameter_dependent) : g
    end

    # 5. numeric evidence of divergence
    d = _diverges(side, L, R)
    d === nothing || return pd(d) ? (nothing, :parameter_dependent) : (d, :divergent_numeric)

    # 6. the squeeze theorem, by rigorous enclosure
    sq = _squeeze(ex, v, c, side)
    sq === nothing || return pd(sq) ? (nothing, :parameter_dependent) : (sq, :squeeze)

    # 7. the limit of a composition — last, so it only ever rescues an
    #    `:unresolved`. `lim f(h) = f(lim h)` for `f` continuous at the inner limit.
    co = _composition(ex, v, c, cancel, check, n, secs, side, depth)
    if co !== nothing
        return pd(co) ? (nothing, :parameter_dependent) : (co, :composition)
    end

    (nothing, :unresolved)
end

