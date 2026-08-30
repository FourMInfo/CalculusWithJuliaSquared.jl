using CalculusWithJuliaSquared
using Test


## test package
@testset "test packages" begin

    ## Roots
    @test fzero(sin, 3, 4)  ≈ pi
    @test fzero(sin, 3.0)  ≈ pi

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

include("package-test.jl")
include("test-symbolics.jl")
include("test-plots.jl")
