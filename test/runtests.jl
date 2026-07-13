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

include("package-test.jl")
include("test-symbolics.jl")
include("test-plots.jl")
