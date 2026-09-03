using CalculusWithJuliaSquared
using Test


## test package
@testset "test packages" begin

    ## Roots
    @test find_zero(sin, (3, 4)) ≈ pi        # Roots v3 deprecates the whole fzero/fzeros interface
    @test find_zero(sin, 3.0) ≈ pi
    @test find_zeros(sin, 3, 7) ≈ [pi, 2pi]

    ## ForwardDiff
    f(x) = sin(x)
    @test f'(2)  ≈ cos(2)
    @test f''(2)  ≈ -sin(2)


end

@testset "test functions" begin

    f(x) = sin(x)
    c = pi/4
    fn = tangent(f, c)
    @test fn(1)  ≈ f(c) + f'(c)*(1 - c)

    fn = secant(f, pi/6, pi/3)
    @test fn(pi/4) <= f(pi/4)

    out = lim(x -> sin(x)/x, 0)
    @test out isa CalculusWithJuliaSquared.Limit
    @test out.f(1e-6) ≈ 1 atol=1e-6
    @test out.f(-1e-6) ≈ 1 atol=1e-6
    for d in ("+", "-", "+-", +, -)
        @test lim(x -> sin(x)/x, 0, d).dir == string(d)
    end
    str = sprint(show, out)
    @test occursin("0.999999", str) # right- and left-hand values converge to 1
    @test occursin("c", str)        # limit-point marker row is rendered


    out = sign_chart(x -> (x-1)*(x-2)/(x-3), 0, 4)
    @test all([o[1] for o ∈ out] .≈[1,2,3])

    @test riemann(sin, 0, pi, 10_000)  ≈ 2
end


@testset "2d" begin

    x = [[1,2,3], [4,5,6]]
    @test unzip(x)[1] == [1, 4]
    @test unzip(x)[2] == [2, 5]
    @test unzip(x)[3] == [3, 6]

    @test length(unzip(x -> x, 0, 1)[1])  <= 50 # 21
    @test length(unzip(x-> sin(10pi*x), 0, 1)[1]) >= 50 # 233

    @test uvec([2,2]) == 1/sqrt(2) * [1,1]

end

@testset "limits (extra)" begin

    # divergent limit: shouldn't error, values should grow without bound
    out = lim(x -> 1/x, 0)
    @test out.f(1e-6) ≈ 1e6
    @test out.f(-1e-6) ≈ -1e6

    # one-sided displays omit the other side's rows
    str_plus = sprint(show, lim(x -> sin(x)/x, 0, "+"))
    @test occursin(" 0.100000", str_plus)
    @test !occursin("-0.100000", str_plus)

    str_minus = sprint(show, lim(x -> sin(x)/x, 0, "-"))
    @test occursin("-0.100000", str_minus)
    @test !occursin(" 0.100000", str_minus)

    # `n` controls how many rows are shown per side
    str_n3 = sprint(show, lim(x -> sin(x)/x, 0; n=3))
    str_default = sprint(show, lim(x -> sin(x)/x, 0))
    @test !occursin("0.000100", str_n3)     # n=3 stops before the 4th power of 10
    @test occursin("0.000100", str_default) # default n=6 includes it

end

@testset "riemann methods" begin

    # right/left/mid/trapezoid/ct converge quickly; loose atol at moderate n
    for method in ("left", "right", "mid", "trapezoid", "ct")
        @test riemann(sin, 0, pi, 1_000; method) ≈ 2 atol=1e-4
    end

    # simpsons converges very fast -- tight tolerance even at modest n
    @test riemann(sin, 0, pi, 1_000; method="simpsons") ≈ 2 atol=1e-6

    # m̃/M̃ sample the min/max over each subinterval -- bound the integral,
    # converge more slowly, so a larger n and looser tolerance is needed
    @test riemann(sin, 0, pi, 10_000; method="m̃") ≈ 2 atol=1e-3
    @test riemann(sin, 0, pi, 10_000; method="M̃") ≈ 2 atol=1e-3

end

@testset "sign_chart edge cases" begin

    # no sign change: always positive / always negative
    @test sign_chart(x -> x^2 + 1, -2, 2) == "No sign change, always positive"
    @test sign_chart(x -> -(x^2 + 1), -2, 2) == "No sign change, always negative"

    # multiple roots, no poles
    out = sign_chart(x -> (x-1)*(x-2)*(x-3), 0, 4)
    @test all([o[1] for o ∈ out] .≈ [1, 2, 3])
    @test out[1].sign_change isa CalculusWithJuliaSquared.MP # - to +
    @test out[2].sign_change isa CalculusWithJuliaSquared.PM # + to -
    @test out[3].sign_change isa CalculusWithJuliaSquared.MP # - to +

    # pure pole (asymptote), no actual zero of f
    out = sign_chart(x -> 1/(x-2), 0, 4)
    @test only(out).zero_oo_NaN ≈ 2
    @test only(out).sign_change isa CalculusWithJuliaSquared.MP # - to +

end

@testset "symbolic limits" begin

    @variables x::Real

    # -- cancellation. Every one of these is a case where SymbolicLimits alone
    #    returns a wrong value (0, or the reciprocal) with no warning.
    @test symlim((x^2 - 1)/(x - 1), x, 1)[1] == 2
    @test symlim((x^2 - 4)/(x - 2), x, 2)[1] == 4
    @test symlim((x^3 - 1)/(x - 1), x, 1)[1] == 3
    @test symlim((x^2 - 5x + 6)/(x^2 + x - 6), x, 2)[1] == -1//5
    @test symlim((x - 2)/(x^2 - 4), x, 2)[1] == 1//4
    @test symlim((3x^2 - x - 10)/(x^2 - 4), x, 2)[1] == 11//4
    @test symlim((x^2 - 1)/(x - 1), x, 1)[2] === :cancel

    # -- series: the trigonometric and root limits the Gruntz engine declines
    @test symlim(sin(x)/x, x, 0)[1] == 1
    @test symlim((1 - cos(x))/x^2, x, 0)[1] == 1//2
    @test symlim((1 - cos(x))/x, x, 0)[1] == 0
    @test symlim(tan(x)/x, x, 0)[1] == 1
    @test symlim((2sin(x) - sin(2x))/(x - sin(x)), x, 0)[1] == 6
    @test symlim((sqrt(x + 1) - 1)/x, x, 0)[1] == 1//2
    @test symlim((exp(x) - 1 - x)/x^2, x, 0)[1] == 1//2
    @test symlim((x - 27)/(x^(1//3) - 3), x, 27)[1] == 27
    @test symlim(x/(x - 1) - 1/log(x), x, 1)[1] == 1//2
    @test symlim(sin(x)/x, x, 0)[2] === :series

    # -- answers stay exact, not floating point
    @test symlim(sin(x)/x, x, 0)[1] isa Union{Integer,Rational}

    # -- divergence. SymbolicLimits returns 0 for log(x) at 0+, so this cannot be
    #    delegated to it; the numeric increment test is what establishes it.
    @test symlim(log(x), x, 0)[1] == -Inf
    @test symlim(x^2 + 1 + log(11x - 15)/99, x, 15//11)[1] == -Inf
    #    with `abs`, the function is defined on BOTH sides, so the two-sided rule
    #    applies -- and the x^2 term outruns the log over the first decade, flipping
    #    the sign of the first increment. Judging divergence from every increment
    #    rather than the tail lost this one, which the published notes render.
    @test symlim(x^2 + 1 + log(abs(11x - 15))/99, x, 15//11) == (-Inf, :divergent_numeric)

    # -- at infinity, where the Gruntz engine is at home
    @test symlim(log(x)/x, x, Inf)[1] == 0
    @test symlim(x^7/exp(x), x, Inf)[1] == 0
    @test symlim(log(x)/x, x, Inf)[2] === :gruntz

    # -- RATIONAL functions at infinity go through the reciprocal route instead, to
    #    keep the answer exact: the engine returns 0.25 where the limit is 1//4.
    @test symlim((x^2 - 2x + 2)/(4x^2 + 3x - 2), x,  Inf) == (1//4, :reciprocal)
    @test symlim((x^2 - 2x + 2)/(4x^2 + 3x - 2), x, -Inf)[1] == 1//4
    #    the point of the route: exact, where the engine gives the float 0.25
    @test !(Symbolics.value(symlim((x^2 - 2x + 2)/(4x^2 + 3x - 2), x, Inf)[1]) isa AbstractFloat)
    @test symlim((x + 1)/(x^3 + 2), x, Inf)[1] == 0
    @test symlim(x^4/x^3, x, Inf)[1] == Inf
    #    but only for that class: substituting x -> 1/u turns anything else into an
    #    essential singularity at 0, so those must stay with the engine
    @test symlim(x^7/exp(x), x, Inf)[2] === :gruntz
    @test !CalculusWithJuliaSquared._isratpoly(x/sqrt(x^2 + 4))
    @test !CalculusWithJuliaSquared._isratpoly(log(x)/x)
    @test  CalculusWithJuliaSquared._isratpoly((x^2 - 2x + 2)/(4x^2 + 3x - 2))

    # -- SQUEEZE. x*sin(1/x) has the limit 0 by the squeeze theorem, which the
    #    interval route now establishes rather than declining. Note the guard that
    #    still matters underneath: Symbolics folds 0*sin(1/0) to 0 by the zero-product
    #    rule, so :substitution must not claim this one — the route is what proves it.
    @test symlim(x * sin(1/x), x, 0) == (0.0, :squeeze)
    @test symlim(exp(-x) * sin(x), x, Inf) == (0.0, :squeeze)

    #    but an enclosure that does not collapse is a refusal, not an answer:
    #    sin(x) at infinity encloses to [-1, 1] at every scale because it has no limit
    @test symlim(sin(x), x, Inf)[1] === nothing

    #    and the route is last, so it never displaces an exact answer
    @test symlim(sin(x)/x, x, 0)[2] === :series
    @test symlim((x^2 - 1)/(x - 1), x, 1)[2] === :cancel
    @test symlim(log(x), x, 0)[2] === :divergent_numeric
    @test symlim(cos(pi*x)/(1 - (2x)^2), x, 1//2)[1] === nothing   # pi floated by taylor

    # -- the stages back each other up: with cancellation switched off, the
    #    series stage still reaches the right answer by another route
    @test symlim((x^3 - 1)/(x - 1), x, 1; cancel = false)[1] == 3
    @test symlim((x^3 - 1)/(x - 1), x, 1; cancel = false)[2] === :series

    # -- pin the upstream defect this staging exists to route around. If this
    #    test starts failing, SymbolicLimits has been fixed and the ordering
    #    here can be revisited.
    let SL = CalculusWithJuliaSquared.SymbolicLimits, uw = Symbolics.unwrap
        @test SL.limit(uw((x^3 - 1)/(x - 1)), uw(x), 1)[1] == 0       # should be 3
        @test SL.limit(uw(log(x)), uw(x), 0, :right)[1] == 0          # should be -Inf
    end

    # -- SYMBOLIC-VALUED limits: the answer carries a free parameter.
    #    This whole class was untested when symlim first landed, and it was broken:
    #    the gate required the substituted result to be a `Number`, so `5x^4` was
    #    rejected and the problem fell through to the Gruntz engine, which answers 0.
    #    Note the routes are asserted, not just the values — the log and exp cases
    #    returned the RIGHT values by the WRONG route, so a value-only test passes
    #    straight over the bug.
    @variables h::Real

    @test isequal(symlim(simplify(expand(((x+h)^5 - x^5)/h)), h, 0)[1], 5x^4)
    @test isequal(symlim(((x+h)^5 - x^5)/h, h, 0)[1], 5x^4)          # raw 0/0
    @test symlim(((x+h)^5 - x^5)/h, h, 0)[2] === :cancel
    @test isequal(symlim(((x+h)^3 - x^3)/h, h, 0)[1], 3x^2)
    @test isequal(symlim((1/(x+h) - 1/x)/h, h, 0)[1], -1/x^2)
    @test isequal(symlim((log(x+h) - log(x))/h, h, 0)[1], 1/x)
    @test symlim((log(x+h) - log(x))/h, h, 0)[2] === :series
    @test isequal(symlim((exp(x+h) - exp(x))/h, h, 0)[1], exp(x))
    @test symlim((exp(x+h) - exp(x))/h, h, 0)[2] === :series

    # -- tlim likewise: ranking a series needs to know which coefficient is the first
    #    NON-ZERO one, which is answerable for a symbolic coefficient too
    @test isequal(tlim((x+h)^5 - x^5, h, h), 5x^4)
    @test isequal(tlim(sin(x+h) - sin(x), h, h), cos(x))

    # -- tlim on its own
    @test tlim(sin(x), x, x) == 1
    @test tlim(1 - cos(x), x^2, x) == 1//2
    @test tlim(2sin(x) - sin(2x), x - sin(x), x) == 6
    @test tlim(sqrt(x + 1) - 1, x, x) == 1//2

    # -- SIDEDNESS. A limit exists at c only if both one-sided limits exist and
    #    agree. Both of these used to come back as confident wrong numbers:
    #    abs(x)/x as `1.0` from the series route (a Taylor expansion of `abs`
    #    about the one point it is not differentiable), and 1/x as `Inf` because
    #    _diverges returned from inside its own `for side in (1,-1)` loop on the
    #    first side that diverged and never consulted the second.
    @test symlim(abs(x)/x, x, 0) == (nothing, :sides_disagree)
    @test symlim(1/x, x, 0)      == (nothing, :sides_disagree)

    # `abs` under a one-sided limit. A Taylor series cannot see a sign change --
    # `taylor(abs(w), w, 0:n)` is `w` -- so before v0.8.3 the right side answered
    # `1` and the left silently declined, where the answer is `-1`. Each `abs` is
    # now resolved against the sign its argument holds on the side approached.
    # `[1]` may come back wrapped, so unwrap before comparing: `==` on a `Num`
    # builds an equation rather than answering one.
    sval(r) = Symbolics.value(r)
    @test sval(symlim(abs(x)/x, x, 0; side = :right)[1]) ==  1
    @test sval(symlim(abs(x)/x, x, 0; side = :left)[1])  == -1
    @test symlim(abs(x)/x, x, 0; side = :right)[2] === :series
    @test symlim(abs(x)/x, x, 0; side = :left)[2]  === :series
    @test sval(symlim(x/abs(x), x, 0; side = :left)[1])  == -1
    @test sval(symlim(abs(x), x, 0; side = :left)[1])    ==  0
    # a shifted sign change: |x-2| is negative-argument to the left of 2
    @test sval(symlim(abs(x - 2)/(x - 2), x, 2; side = :left)[1])  == -1
    @test sval(symlim(abs(x - 2)/(x - 2), x, 2; side = :right)[1]) ==  1
    # symbols for the composition / parameter-dependence tests below
    @variables n::Real d::Real m::Real

    # ---- :parameter_dependent -- refuse rather than answer for an unstated branch.
    #      With `delta` free the engine returns -Inf, correct for delta < 0 and the
    #      opposite of the delta > 0 reading intended; that is worse than a refusal
    #      because it looks like an ordinary result.
    @test symlim(exp(n*log(1 + d)) - n, n, Inf) == (nothing, :parameter_dependent)
    @test symlim(exp(n*log(3//2)) - n, n, Inf)[1] ==  Inf   # pinned, r > 1
    @test symlim(exp(n*log(1//2)) - n, n, Inf)[1] == -Inf   # pinned, r < 1

    #      ADVERSARIAL: it must NOT fire when the answer holds for every value of the
    #      parameter. Over-refusing would be as bad as the wrong answer it replaces.
    @test symlim(exp(m*log(x) - x), x, Inf)[1] == 0          # 0 for all real m
    @test isequal(symlim(((x+h)^5 - x^5)/h, h, 0)[1], 5x^4)  # free x, still fine
    @test symlim(sin(h)/h, h, 0)[1] == 1                     # no free parameter at all
    @test symlim(log(x)/x, x, Inf)[1] == 0

    # tlim gained the same keyword, and defaults to the old behaviour
    @test sval(tlim(abs(x), x, x, 0; side = :right)) ==  1
    @test sval(tlim(abs(x), x, x, 0; side = :left))  == -1
    # ...and the two sides are reported in the SAME form. `/` on two `Int`s is
    # Float64 in Julia, so the right side used to print `1.0` beside an exact
    # `-1//1` on the left -- a matched pair rendered two different ways.
    @test !(sval(symlim(abs(x)/x, x, 0; side = :right)[1]) isa AbstractFloat)
    @test !(sval(symlim(abs(x)/x, x, 0; side = :left)[1])  isa AbstractFloat)
    @test !(sval(tlim(abs(x), x, x, 0; side = :right))     isa AbstractFloat)
    @test symlim(1/x, x, 0; side = :right)[1] ==  Inf
    @test symlim(1/x, x, 0; side = :left)[1]  == -Inf
    @test symlim(x^x, x, 0; side = :right)[1] == 1
    @test symlim(x^x * (1 + log(x)), x, 0; side = :right)[1] == -Inf
    @test symlim(log(x), x, 0; side = :left) == (nothing, :undefined_on_side)
    @test_throws ArgumentError symlim(sin(x)/x, x, 0; side = :up)

    # -- A one-sided DOMAIN is not a disagreement. Where ex does not reach c from
    #    one direction there is nothing to disagree with, and the defined side is
    #    the limit — the ordinary reading of lim log(x) = -Inf as x -> 0. The
    #    published notes render this cell, so a stricter rule here would silently
    #    invalidate them.
    @test symlim(log(x), x, 0)[2] === :divergent_numeric
    @test symlim(x^x, x, 0)[1] == 1

    # -- UNKNOWN SYMBOLIC EXPONENTS. The order of x^k is k, so the limit below is
    #    0, 1 or Inf according to k alone; the series route ranked leading orders
    #    as if k were fixed and returned 0. Pin a k and the same expression
    #    resolves exactly — including k = 3, where the two sides now disagree
    #    rather than reporting the right-hand answer as if it were the limit.
    @variables k::Integer
    @test symlim(sin(sin(x^2))/x^k, x, 0)[1] === nothing
    @test tlim(sin(sin(x^2)), x^k, x) === nothing
    @test symlim(sin(sin(x^2))/x^1, x, 0)[1] == 0
    @test symlim(sin(sin(x^2))/x^2, x, 0)[1] == 1
    @test symlim(sin(sin(x^2))/x^3, x, 0) == (nothing, :sides_disagree)
    @test symlim(sin(sin(x^2))/x^3, x, 0; side = :right)[1] == Inf

    # -- `check` demotes the engine's known-bad answer rather than passing it on.
    #    SymbolicLimits returns 0 for log(x) at 0+ (v1.1.5, pinned above). Unchecked
    #    that becomes symlim's answer; checked, it contradicts the numeric evidence
    #    on the side being approached and the divergence test supplies -Inf instead.
    @test symlim(log(x), x, 0; side = :right, check = false) == (0, :gruntz)
    @test symlim(log(x), x, 0; side = :right)[1] == -Inf
    @test symlim(log(x), x, 0; side = :right)[2] === :divergent_numeric

end

@testset "symbolic limits: free parameters, step functions, snapping (v0.10.0)" begin

    @variables x::Real c::Real a::Real b::Real n::Real d::Real m::Real
    sval(r) = Symbolics.value(r)
    CW = CalculusWithJuliaSquared

    # ---- A. The continuity chapter's site, verbatim. v0.9.0 answered
    #      (1.5247…, :squeeze) — a number invented for `c`. The parameter must ride
    #      through, and by :substitution, which is what makes the piece continuous.
    @test isequal(sval(symlim(3x^2 + c, x, 0; side = :right)[1]), sval(c))
    @test symlim(3x^2 + c, x, 0; side = :right)[2] === :substitution
    @test symlim(2x - 3, x, 0; side = :left) == (-3, :substitution)
    #      the shape that exposed it: a squared term reorders get_variables, so `c`
    #      grounded to one sample in the expression and another in the answer
    for ex in (x^2 + c, c + x^2, 3x^2 + c, x^2 - c, x^2 + 2c, x + c, x^3 + c, (x - 1)^2 + c)
        @test symlim(ex, x, 0)[2] === :substitution
    end
    @test isequal(sval(symlim(x^2 - c, x, 0)[1]), sval(-c))
    @test isequal(sval(symlim(x^2 + 2c, x, 0)[1]), sval(2c))
    @test isequal(sval(symlim((x - 1)^2 + c, x, 1)[1]), sval(c))
    @test isequal(sval(symlim((x^2 - 1)/(x - 1) + c, x, 1)[1]), sval(2 + c))
    @test symlim((x^2 - 1)/(x - 1) + c, x, 1)[2] === :cancel
    #      grounding is keyed by the symbol, not its position: `c` gets the same
    #      sample whatever else is in the expression
    gc = sval(CW._ground(c, x))
    @test gc == sval(substitute(CW._ground(x^2 + c, x), Dict(x => 0)))
    @test gc == sval(substitute(CW._ground(c + x^2, x), Dict(x => 0)))
    @test gc == sval(substitute(CW._ground(a*x + c, x), Dict(x => 0)))
    @test gc != sval(CW._ground(a, x))                # distinct symbols, distinct samples
    #      exact routes carry a parameter through, by the route they always took
    @test symlim(sin(c*x)/x, x, 0)[2] === :series
    @test isequal(sval(symlim(sin(c*x)/x, x, 0)[1]), sval(c))
    @test isequal(sval(symlim((exp(c*x) - 1)/x, x, 0)[1]), sval(c))
    @test isequal(sval(symlim(sin(x) + c, x, 0)[1]), sval(c))
    @test sval(symlim(c*x + 1, x, 0)[1]) == 1
    @test isequal(sval(symlim(a*x^2 + b*x + c, x, 0)[1]), sval(c))

    # ---- B. A route that can only produce a NUMBER cannot answer for a free
    #      parameter. v0.9.0 grounded `c` to its sample and reported the sample:
    #      symlim(c + x*sin(1/x), x, 0) was (1.4247…, :squeeze).
    @test symlim(c + x*sin(1/x), x, 0) == (nothing, :parameter_dependent)
    @test symlim(c + x*sin(1/x), x, 0; side = :right)[1] === nothing
    #      ...but it must NOT refuse where the answer holds for every value
    @test symlim(c*x*sin(1/x), x, 0) == (0.0, :squeeze)
    @test symlim(c + 1/x^2, x, 0) == (Inf, :divergent_numeric)
    @test symlim(exp(n*log(1 + d)) - n, n, Inf) == (nothing, :parameter_dependent)
    @test symlim(exp(m*log(x) - x), x, Inf)[1] == 0
    #      LURKING: the guard used to give up above two parameters ("keep the cost
    #      bounded" — it never did, every parameter is pinned in one substitution),
    #      which removed the protection exactly where a fabricated number is hardest
    #      to notice. Three parameters, same invented number without it.
    @test symlim(a + b + c + x*sin(1/x), x, 0) == (nothing, :parameter_dependent)
    @test symlim((a + b + c)*x*sin(1/x), x, 0) == (0.0, :squeeze)
    #      the collapse test is RELATIVE — the widths must fall by about the factor
    #      the step sizes did — so the coefficient's size is irrelevant. An absolute
    #      bound refused these, and made the three-parameter case above depend on
    #      which sample values the session had already handed out.
    @test symlim(10x*sin(1/x), x, 0)   == (0.0, :squeeze)
    @test symlim(1000x*sin(1/x), x, 0) == (0.0, :squeeze)
    #      ...independent of how many symbols were grounded before it
    @variables p1 p2 p3 p4 p5 p6 a2 b2 c2
    foreach(p -> CW._ground(p, x), (p1, p2, p3, p4, p5, p6))
    @test symlim((a2 + b2 + c2)*x*sin(1/x), x, 0) == (0.0, :squeeze)
    #      ...and a width that stays put is an oscillation, however tiny: no limit.
    #      An absolute bound accepted this one as (0, :squeeze).
    @test symlim(1e-9*sin(1/x), x, 0)[1] === nothing
    @test symlim(1e-9*sin(1/x), x, 0; side = :right)[1] === nothing

    # ---- C. An unevaluated constant is an opinion, not the absence of one.
    #      symlim(sign(x), x, 0; side = :right) returned (sign(0), :cancel) — that is
    #      0, and the limit is 1. `substitute` leaves `sign(0)` unevaluated and
    #      `_consistent` waved it through as "nothing to contradict".
    s0 = substitute(sign(x), Dict(x => 0))
    @test !(sval(s0) isa Number)                      # the shape that slipped through
    @test !CW._consistent(s0, (:finite, 1.0), x)
    @test  CW._consistent(s0, (:finite, 0.0), x)
    @test symlim(sign(x), x, 0; side = :right)[2] !== :cancel
    @test symlim(floor(x), x, 0; side = :left)[2] !== :cancel
    #      with the check off, the unfolded first answer is what you asked for — the
    #      documented way to watch a stage misbehave, pinned so it stays deliberate
    @test symlim(sign(x), x, 0; side = :right, check = false)[1] == 0

    # ---- D. The step family, one-sided, by :squeeze over boxes that EXCLUDE c.
    @test symlim(sign(x),  x, 0; side = :right) == (1, :squeeze)
    @test symlim(sign(x),  x, 0; side = :left)  == (-1, :squeeze)
    @test symlim(floor(x), x, 0; side = :left)  == (-1, :squeeze)
    @test symlim(floor(x), x, 2; side = :left)  == (1, :squeeze)
    @test symlim(ceil(x),  x, 0; side = :right) == (1, :squeeze)
    @test symlim(floor(x)/x, x, 1; side = :left) == (0, :squeeze)
    #      right-continuity of floor is :substitution — the value IS the limit — and
    #      that label is the evidence the notes quote, so pin it
    @test symlim(floor(x), x, 0; side = :right) == (0, :substitution)
    @test symlim(floor(x), x, 1//2)             == (0, :substitution)
    #      two-sided, a step is a jump, and a jump is refused — never "the right side"
    @test symlim(sign(x),  x, 0) == (nothing, :sides_disagree)
    @test symlim(floor(x), x, 0) == (nothing, :sides_disagree)
    @test symlim(ceil(x),  x, 0) == (nothing, :sides_disagree)
    #      ADVERSARIAL: excluding c must not let the route steal an exact answer, and
    #      an enclosure that does not collapse is still a refusal
    @test symlim(sin(x)/x, x, 0)[2]          === :series
    @test symlim((x^2 - 1)/(x - 1), x, 1)[2] === :cancel
    @test symlim(sqrt(x), x, 0; side = :right)[2] === :substitution
    @test symlim(sin(x), x, Inf)   == (nothing, :unresolved)
    @test symlim(sin(1/x), x, 0)   == (nothing, :unresolved)
    @test symlim(sin(1/x), x, 0; side = :right)[1] === nothing
    #      the dependency problem is a refusal, not a wrong number: the limit is 1
    @test symlim(x*floor(1/x), x, 0; side = :right)[1] === nothing

    # ---- E. What a collapsed enclosure may claim: the number's TYPE reports how the
    #      answer was established. Zero width is exact; containing 0 is a clean 0.0;
    #      anything else is a float, because a float is all a bound knows.
    @test symlim(x^2*(cos(1/x) - 1), x, 0) == (0.0, :squeeze)        # was -1.0e-14: debris
    @test symlim(x^2*(cos(1/x) - 1), x, 0)[1] === 0.0
    @test symlim(x*sin(1/x), x, 0)[1] === 0.0                         # exactly as published
    @test symlim(x*sin(1/x), x, 0; side = :right)[1] === 0.0
    @test symlim(exp(-x)*sin(x), x, Inf)[1] === 0.0
    #      bounded, NOT derived: a limit the route only encloses stays a float, so a
    #      reader can tell it from an exact answer. `1//4` here would print a bound
    #      exactly like a derivation.
    r = symlim(1//4 + x*sin(1/x), x, 0)
    @test r[2] === :squeeze && r[1] isa AbstractFloat && r[1] ≈ 0.25
    r = symlim(sqrt(2) + x*sin(1/x), x, 0)
    @test r[2] === :squeeze && r[1] isa AbstractFloat && r[1] ≈ sqrt(2)
    #      exact because the enclosure IS exact: a step function over a box that
    #      excludes the step has zero width
    @test symlim(floor(x), x, 0; side = :left)[1]  === -1
    @test symlim(sign(x),  x, 0; side = :right)[1] === 1
    #      _snap itself
    S = CW._snap
    @test S(-2e-14, 0.0)            === 0.0
    @test S(-1e-7, 1e-7)            === 0.0
    @test S(0.0, 0.0)               === 0                # zero width, integer: exact
    @test S(-1.0, -1.0)             === -1
    @test S(-0.5, -0.5)             === -0.5             # zero width, not an integer: as is
    @test S(1e300, 1e300)           isa AbstractFloat    # too large for an Int
    @test S(0.9999998, 1.0000002)   isa AbstractFloat    # near 1 is not 1: bounded
    @test S(0.5, 0.6)               === nothing          # a band is not a point
    @test S(0.2499999, 0.2500001)   isa AbstractFloat
    @test S(0.2499999, 0.2500001)   ≈ 0.25

    # ---- F. Limit points and one-sided domains.
    @test symlim(tan(x), x, Num(pi)/2) == (nothing, :sides_disagree)       # was a MethodError
    @test symlim(tan(x), x, Num(pi)/2; side = :left)[1]  ==  Inf
    @test symlim(tan(x), x, Num(pi)/2; side = :right)[1] == -Inf
    @test symlim(x^2, x, Num(3)) == (9, :substitution)
    @test symlim(x^2, x, Num(pi))[1] ≈ pi^2
    @test_throws ArgumentError symlim(x^2, x, c)                          # a symbolic point
    @test_throws ArgumentError symlim(x^2, x, x)
    #      an undefined side means a one-sided limit, and the routes are asked for one
    @test sval(symlim(exp(x*log(x)), x, 0)[1]) == 1                        # was :unresolved
    @test symlim(exp(x*log(x)), x, 0)[2] === :gruntz
    @test sval(symlim(x*log(x), x, 0)[1]) == 0
    #      ...without moving anything that already worked on that rule
    @test symlim(log(x), x, 0)  == (-Inf, :divergent_numeric)
    @test symlim(sqrt(x), x, 0) == (0, :substitution)
    @test symlim(x^x, x, 0)[1]  == 1
    @test symlim(log(x), x, 0; side = :left) == (nothing, :undefined_on_side)
    @test symlim(1/x, x, 0) == (nothing, :sides_disagree)                   # both sides exist

    #      ADVERSARIAL: a probe the guard cannot settle is NOT evidence of
    #      independence. With `secs = 0` every Gruntz call times out, so both probes
    #      are unsettled — and a numeric answer must then be refused, not waved
    #      through. This is what CI hit: abandoned hung Gruntz tasks from the 1^∞
    #      cases held the thread pool, the probe's call timed out, and the guard
    #      passed (-Inf, :gruntz) on as if it had checked.
    @test CW._param_dependent(exp(n*log(1 + d)) - n, n, Inf, -Inf, true, true, 8, 0, :both)
    @test symlim(exp(n*log(1 + d)) - n, n, Inf; secs = 0)[1] === nothing
    #      ...while a SYMBOLIC answer that shows its parameter is still let through
    #      when a probe is unsettled — the reader can judge it, a number cannot be
    @test !CW._param_dependent(a*x^2 + c, x, 0, c, true, true, 8, 0, :both)
    @test isequal(sval(symlim(a*x^2 + c, x, 0; secs = 0)[1]), sval(c))

    #      ADVERSARIAL: an enclosure can be INFLATED by the dependency problem and
    #      still pass a closing test — `(2x + sin x)/x - 3` over `[m, 1e300]` straddles
    #      0 while the function sits at -1 — so :squeeze is held to pointwise samples
    #      like every other route. Reaching the route needs the engine to decline,
    #      which `sin` guarantees.
    @test symlim((2x + sin(x))/x - 3, x, Inf)[1] != 0
    @test symlim((2x + sin(x))/x - 3, x, Inf)[2] !== :squeeze
    #      and a band that closes at the scale rate but never gets tight is refused:
    #      `log(x)/x` over `[m, 1e300]` shrinks like 1/m and would report half a band
    @test CW._squeeze(log(x)/x, x, Inf, :both) === nothing

    # ---- Every docstring example, pinned by route.
    @test symlim((x^2 - 1)/(x - 1), x, 1)          == (2, :cancel)
    @test symlim(sin(x)/x, x, 0)                   == (1//1, :series)
    @test symlim(log(x)/x, x, Inf)                 == (0, :gruntz)
    @test symlim(x*sin(1/x), x, 0)                 == (0.0, :squeeze)
    @test symlim(abs(x)/x, x, 0)                   == (nothing, :sides_disagree)
    @test symlim(abs(x)/x, x, 0; side = :right)    == (1//1, :series)
    @test symlim(abs(x)/x, x, 0; side = :left)     == (-1//1, :series)
    @test symlim(floor(x), x, 0; side = :right)    == (0, :substitution)
    @test symlim(floor(x), x, 0; side = :left)     == (-1, :squeeze)

end

@testset "symbolic limits: the 1^∞ family — LAST, because a hung Gruntz call is a lost thread" begin

    # `SymbolicLimits` does not terminate on `exp(n*log(1 + 1/n))` — measured at
    # >150 s, and a second call is no better, so it is not compilation. The watchdog
    # abandons the task but cannot kill a CPU-bound one, so every case below costs the
    # session a thread for good. Anything Gruntz-dependent that runs AFTER them is at
    # the mercy of the scheduler: locally it kept passing, on CI it did not. Hence this
    # block runs last, and its own label assertions come before its hangs.
    @variables x::Real n::Real

    #      ADVERSARIAL: the route must be a LAST resort. Everything that resolved
    #      before must still resolve the SAME WAY -- a route label is a compatibility
    #      surface the notes quote, so a silent relabel is a break even when the
    #      value is right. Asserted BEFORE the hangs, so a poisoned pool cannot
    #      relabel them here either.
    @test symlim(log(x)/x, x, Inf)[2]                        === :gruntz
    @test symlim(x^7/exp(x), x, Inf)[2]                      === :gruntz
    @test symlim((x^2 - 2x + 2)/(4x^2 + 3x - 2), x, Inf)[2]  === :reciprocal
    @test symlim(x^4/x^3, x, Inf)[2]                         === :reciprocal
    @test symlim(exp(-x) * sin(x), x, Inf)[2]                === :squeeze
    @test symlim(x * sin(1/x), x, 0)[2]                      === :squeeze
    @test symlim(sin(x)/x, x, 0)[2]                          === :series
    @test symlim((x^2 - 1)/(x - 1), x, 1)[2]                 === :cancel
    #      ...and the refusals must still refuse
    @test symlim(sin(x), x, Inf)      == (nothing, :unresolved)
    @test symlim(abs(x)/x, x, 0)      == (nothing, :sides_disagree)
    #      a composed answer is confirmed against the function itself, so an inner
    #      limit that is right cannot smuggle out a wrong outer value
    @test symlim(exp(1/x), x, Inf)[1] ≈ 1
    @test symlim(exp(-x^2), x, Inf)[1] == 0

    # ---- :composition -- lim f(h) = f(lim h) for f continuous at the inner limit.
    #      This is what stood between symlim and the 1^inf family. Each of these
    #      abandons at least one hung Gruntz task.
    @test symlim((1 + 1/n)^n, n, Inf)[1] ≈ exp(1)
    @test symlim((1 + 2/n)^n, n, Inf)[1] ≈ exp(2)
    @test symlim((n/(n+1))^n, n, Inf)[1] ≈ exp(-1)
    @test symlim((1 + 1/n)^n, n, Inf)[2] === :composition

    #      ADVERSARIAL: composition must not reach through a function that is NOT
    #      continuous at the inner limit. `log` and `sqrt` are deliberately absent
    #      from the continuous set -- log(x) at 0 must stay divergent-by-evidence,
    #      not become `log(0)` handed back as a composed answer. None of these needs
    #      the engine, so they are safe after the hangs.
    @test symlim(log(x), x, 0; side = :right)[2] === :divergent_numeric
    #      `sqrt` at 0+ resolves by substitution; what matters here is that
    #      composition does not step in and manufacture an answer for it.
    @test symlim(sqrt(x), x, 0; side = :right)[2] !== :composition
    @test symlim(sqrt(x), x, 4)[1] == 2

end

include("package-test.jl")
include("test-symbolics.jl")
include("test-plots.jl")
