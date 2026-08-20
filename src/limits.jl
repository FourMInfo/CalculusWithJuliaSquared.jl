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

# A substituted result is usable only when it has folded to a finite number.
function _okval(e)
    _isnum(e) || return false
    try isfinite(float(_uw(e))) catch; false end
end

# Fold an expression to a number at a point; `nothing` if it is not defined there.
function _numfold(ex, v, c)
    try
        f = Symbolics.build_function(ex, v; expression = Val(false))
        y = f(float(c))
        (y isa Number && isfinite(float(y))) ? float(y) : nothing
    catch
        nothing
    end
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
function _gruntz(ex, v, c; secs = 10)
    r = _timed(secs) do
        SymbolicLimits.limit(Symbolics.unwrap(ex), Symbolics.unwrap(v), c)[1]
    end
    r === nothing ? (nothing, :unresolved) : (r, :gruntz)
end

_coeffs(t, w, n) = Any[substitute(t, Dict(w => 0));
                       [Symbolics.coeff(t, w^k) for k in 1:n]]

function _order(cs)
    for (i, c) in pairs(cs)
        _isnum(c) || return nothing        # symbolic coefficient: cannot rank it
        iszero(_uw(c)) || return i - 1
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

# Evidence of divergence: a convergent sequence's increments collapse toward
# zero, a divergent one's do not. Testing the increments rather than the
# magnitude is what catches logarithmic divergence, which grows by a constant
# per decade and never reaches any fixed threshold.
function _diverges(ex, v, c; hs = (1e-2, 1e-4, 1e-6, 1e-8, 1e-10))
    for side in (1, -1)
        ys = Float64[]
        for h in hs
            y = _numfold(ex, v, c + side * h)
            y === nothing && break
            push!(ys, y)
        end
        length(ys) == length(hs) || continue
        d = diff(ys)
        length(d) >= 2 || continue
        abs(d[end]) < 0.1 * abs(d[1]) && continue      # increments collapsing: converges
        all(<(0), d) && return -Inf
        all(>(0), d) && return  Inf
    end
    nothing
end

"""
    symlim(ex, v, c; cancel = true, check = true, n = 8, secs = 10)

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
| `:gruntz` | `c` is infinite, or nothing above applied | float |
| `:divergent_numeric` | the value grows without bound | `±Inf` |
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
```

That last one has the limit `0`, by the squeeze theorem. No method here can show
that, so none claims to — see *Known limits* below.

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
    observe the underlying engine misbehaving. For that, call
    `SymbolicLimits.limit` directly.
  * `check = true` — cross-check the symbolic answer against a numeric probe near
    `c` and warn on disagreement. Leave this on. The failure modes it guards
    against are silent, so nothing else will catch them.
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
    :right)` returns `0` rather than `-Inf` (v1.1.5), so the numeric increment
    test is what establishes these — load-bearing, not a convenience.

See also [`tlim`](@ref), [`lim`](@ref).
"""
function symlim(ex, v, c; cancel = true, check = true, n = 8, secs = 10)
    val, route = _symlim(ex, v, c, cancel, n, secs)
    if check && val !== nothing && c isa Number && isfinite(float(c)) && _okval(val)
        nr = _numprobe(ex, v, c)
        s  = float(_uw(val))
        if nr !== nothing && isfinite(s) && abs(s - nr) > 1e-3 * max(1, abs(nr))
            @warn "symbolic and numeric limits disagree" symbolic=s numeric=nr route
        end
    end
    (val, route)
end

function _symlim(ex, v, c, cancel, n, secs)
    (c isa Number && isfinite(float(c))) || return _gruntz(ex, v, c; secs)
    sub(e) = substitute(e, Dict(v => c))

    # 1. direct substitution — only where `ex` is genuinely defined at `c`.
    #    Symbolics folds `0 * sin(1/0)` to `0` by the zero-product rule, which is
    #    the right answer for the wrong reason; requiring a finite numeric value
    #    at `c` rejects that.
    num, den = numerator(ex), denominator(ex)
    n0, d0 = sub(num), sub(den)
    if _okval(d0) && !_symzero(d0) && _okval(n0) && _numfold(ex, v, c) !== nothing
        return (simplify(n0 / d0), :substitution)
    end

    # 2. put over a common denominator and cancel. After a genuine cancellation
    #    the reduced form is defined at `c` — `(x^2-1)/(x-1)` becomes `x+1` — so
    #    the same definedness test admits every real cancellation.
    q = ex
    if cancel
        try
            q = Symbolics.simplify_fractions(ex)
            nq, dq = sub(numerator(q)), sub(denominator(q))
            if _okval(dq) && !_symzero(dq) && _okval(nq) && _numfold(q, v, c) !== nothing
                return (simplify(nq / dq), :cancel)
            end
        catch
            q = ex
        end
    end

    # 3. series comparison
    for target in (q, ex)
        r = tlim(numerator(target), denominator(target), v, c; n)
        r === nothing || return (r, :series)
    end

    # 4. the Gruntz engine, last and time-boxed
    g = _gruntz(ex, v, c; secs)
    g[1] === nothing || return g

    # 5. numeric evidence of divergence
    d = _diverges(ex, v, c)
    d === nothing || return (d, :divergent_numeric)

    (nothing, :unresolved)
end

# Two-sided numeric probe, used only to cross-check a symbolic answer. Returns
# `nothing` when the two sides disagree, so a genuine jump is never mistaken for
# a mismatch in the symbolic result.
function _numprobe(ex, v, c; hs = (1e-4, 1e-6))
    vals = Float64[]
    for h in hs, s in (1, -1)
        y = _numfold(ex, v, c + s * h)
        y === nothing || push!(vals, y)
    end
    isempty(vals) && return nothing
    (maximum(vals) - minimum(vals)) > 1e-2 * max(1, abs(vals[1])) && return nothing
    sum(vals) / length(vals)
end
