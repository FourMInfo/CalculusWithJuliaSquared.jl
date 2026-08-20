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

    # -- at infinity, where the Gruntz engine is at home
    @test symlim(log(x)/x, x, Inf)[1] == 0
    @test symlim(x^7/exp(x), x, Inf)[1] == 0
    @test symlim(log(x)/x, x, Inf)[2] === :gruntz

    # -- honest refusals rather than plausible guesses.
    #    x*sin(1/x) does have the limit 0, by the squeeze theorem; no route here
    #    can show that, so none claims to. Symbolics folds 0*sin(1/0) to 0 by the
    #    zero-product rule, and this guards against accepting that as an answer.
    @test symlim(x * sin(1/x), x, 0)[1] === nothing
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

    # -- tlim on its own
    @test tlim(sin(x), x, x) == 1
    @test tlim(1 - cos(x), x^2, x) == 1//2
    @test tlim(2sin(x) - sin(2x), x - sin(x), x) == 6
    @test tlim(sqrt(x + 1) - 1, x, x) == 1//2

end

include("package-test.jl")
include("test-symbolics.jl")
include("test-plots.jl")
