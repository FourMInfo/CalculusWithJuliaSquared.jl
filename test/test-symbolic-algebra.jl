using CalculusWithJuliaSquared
using Test

const PI = Symbolics.Num(pi)

# A real decomposition is a sum of terms; a function that simply handed its input
# back would satisfy the "equals the original" tests without decomposing anything.
function _is_sum(ex)
    t = Symbolics.value(ex)
    Symbolics.SymbolicUtils.iscall(t) && Symbolics.SymbolicUtils.operation(t) === (+)
end

@testset "exact_trig_values (v0.13.0)" begin

    @variables x

    # ---- the cells this function exists for -------------------------------------
    # `precalc/trig_functions.qmd` and `precalc/plotting.qmd` each have exactly one
    # cell that needs exact values; test those, not a cousin of them.

    @test isequal(exact_trig_values.(cos.([0, PI/6, PI/4, PI/3, PI/2])),
                  [1, sqrt(Symbolics.Num(3))/2, sqrt(Symbolics.Num(2))/2, 1//2, 0])

    θs = [0, PI/6, PI/4, PI/3, PI/2, 2PI/3, 3PI/4, 5PI/6, PI]
    @test isequal(exact_trig_values.(cos.(θs)),
                  [1, sqrt(Symbolics.Num(3))/2, sqrt(Symbolics.Num(2))/2, 1//2, 0,
                   -1//2, -sqrt(Symbolics.Num(2))/2, -sqrt(Symbolics.Num(3))/2, -1])
    @test isequal(exact_trig_values.(sin.(θs)),
                  [0, 1//2, sqrt(Symbolics.Num(2))/2, sqrt(Symbolics.Num(3))/2, 1,
                   sqrt(Symbolics.Num(3))/2, sqrt(Symbolics.Num(2))/2, 1//2, 0])

    # ---- all four quadrants, against the standard table -------------------------
    for (k, c, s) in ((0//1,  1,     0),
                      (1//2,  0,     1),
                      (1//1, -1,     0),
                      (3//2,  0,    -1),
                      (2//1,  1,     0),
                      (7//6, -sqrt(Symbolics.Num(3))/2, -1//2),
                      (5//4, -sqrt(Symbolics.Num(2))/2, -sqrt(Symbolics.Num(2))/2),
                      (5//3,  1//2,  -sqrt(Symbolics.Num(3))/2),
                      (11//6, sqrt(Symbolics.Num(3))/2, -1//2))
        a = k * PI
        @test isequal(exact_trig_values(cos(a)), Symbolics.Num(c))
        @test isequal(exact_trig_values(sin(a)), Symbolics.Num(s))
    end

    # negative angles reduce the same way
    @test isequal(exact_trig_values(cos(-PI/3)), Symbolics.Num(1//2))
    @test isequal(exact_trig_values(sin(-PI/6)), Symbolics.Num(-1//2))

    # ---- the other four functions, and their poles ------------------------------
    @test isequal(exact_trig_values(tan(PI/4)), Symbolics.Num(1))
    @test isequal(exact_trig_values(sec(PI/3)), Symbolics.Num(2))
    @test isequal(exact_trig_values(csc(PI/6)), Symbolics.Num(2))
    @test isequal(exact_trig_values(cot(PI/4)), Symbolics.Num(1))

    # whole numbers print as integers, not `2//1`
    @test Symbolics.value(exact_trig_values(sec(PI/3))) isa Integer

    # A pole has no value to give, so the expression must survive untouched rather
    # than acquire an invented one.
    @test isequal(exact_trig_values(tan(PI/2)), tan(PI/2))
    @test isequal(exact_trig_values(cot(Symbolics.Num(0))), cot(Symbolics.Num(0)))
    @test isequal(exact_trig_values(sec(PI/2)), sec(PI/2))
    @test isequal(exact_trig_values(csc(Symbolics.Num(0))), csc(Symbolics.Num(0)))

    # ---- the negative space -----------------------------------------------------
    # THE case that matters. `cos(Num(0.5235987755982988))` stays symbolic and that
    # float agrees with π/6 to fifteen digits, so a numeric-only angle test hands
    # back `sqrt(3)/2` and silently claims exactness the input never had. It must
    # come back untouched.
    fl = cos(Symbolics.Num(0.5235987755982988))
    @test isequal(exact_trig_values(fl), fl)
    @test isequal(exact_trig_values(sin(Symbolics.Num(1.5707963267948966))),
                  sin(Symbolics.Num(1.5707963267948966)))
    # a float coefficient on an otherwise symbolic π is refused for the same reason
    @test isequal(exact_trig_values(cos(0.5 * PI)), cos(0.5 * PI))

    # angles outside the table
    @test isequal(exact_trig_values(cos(PI/5)), cos(PI/5))
    @test isequal(exact_trig_values(cos(PI/7)), cos(PI/7))
    @test isequal(exact_trig_values(cos(Symbolics.Num(2))), cos(Symbolics.Num(2)))

    # free variables
    @test isequal(exact_trig_values(cos(x)), cos(x))
    @test isequal(exact_trig_values(cos(PI * x)), cos(PI * x))
    @test isequal(exact_trig_values(cos(x + PI/6)), cos(x + PI/6))

    # non-trig functions are not touched
    @test isequal(exact_trig_values(exp(PI/6)), exp(PI/6))
    @test isequal(exact_trig_values(log(PI)), log(PI))

    # ---- it rewrites in place, leaving the rest of the expression alone ---------
    @test isequal(exact_trig_values(cos(PI/3) + sin(x)), 1//2 + sin(x))
    @test isequal(exact_trig_values(2 * cos(PI/3) * x), x)
    @test isequal(exact_trig_values(cos(PI/6 + PI/6)), Symbolics.Num(1//2))
    # nested inside another function
    @test isequal(exact_trig_values(exp(cos(PI/3))), exp(Symbolics.Num(1//2)))

    # a plain number in, a plain number out
    @test isequal(exact_trig_values(Symbolics.Num(3)), Symbolics.Num(3))

end

@testset "poly_factors / factored_poly (v0.13.0)" begin

    @variables x y

    # ---- the cells this exists for ----------------------------------------------
    # `precalc/polynomial.qmd` displays these three and counts the factors of two more.
    @test isequal(Symbolics.expand(factored_poly(x^3 - 6x^2 + 11x - 6, x)),
                  Symbolics.expand(x^3 - 6x^2 + 11x - 6))
    @test length(poly_factors(x^3 - 6x^2 + 11x - 6, x)) == 3

    @test length(poly_factors(x^11 - x, x)) == 5      # x(x-1)(x+1)(quartic)(quartic)
    @test length(poly_factors(x^12 - 1, x)) == 6

    # ---- factoring is over the RATIONALS ----------------------------------------
    # The chapter's point: `x^2 - 2` is left alone because √2 is not rational. A
    # version of this that "helpfully" factored it would break the lesson.
    @test isequal(factored_poly(x^2 - 2, x), x^2 - 2)
    @test length(poly_factors(x^2 - 2, x)) == 1
    @test length(poly_factors(x^2 + 1, x)) == 1

    # ---- multiplicity and constant factors --------------------------------------
    @test length(poly_factors((x - 1)^3, x)) == 3     # repeated, once per multiplicity
    @test isequal(Symbolics.expand(factored_poly((x - 1)^3, x)),
                  Symbolics.expand((x - 1)^3))

    fs = poly_factors(2x^2 - 2, x)
    @test length(fs) == 3                             # 2, (x-1), (x+1)
    @test any(f -> isequal(f, Symbolics.Num(2)), fs)
    @test isequal(Symbolics.expand(factored_poly(2x^2 - 2, x)), Symbolics.expand(2x^2 - 2))

    # rational coefficients are fine
    @test isequal(Symbolics.expand(factored_poly(x^2 - 1//4, x)), Symbolics.expand(x^2 - 1//4))

    # ---- the product always reconstructs the input ------------------------------
    for p in (x^2 - 1, x^4 - 1, x^5 - 5x^4 + 8x^3 - 8x^2 + 7x - 3,
              3x^2 + 6x + 3, x^3 + 1, x - 1, Symbolics.Num(x)^2)
        @test isequal(Symbolics.expand(prod(poly_factors(p, x)) - p), 0)
    end

    # a polynomial that does not factor comes back as itself
    @test isequal(factored_poly(x + 1, x), x + 1)

    # ---- ordering is stable, so a re-render produces the same book page ---------
    @test isequal(poly_factors(x^12 - 1, x), poly_factors(x^12 - 1, x))
    @test isequal(poly_factors(x^3 - 6x^2 + 11x - 6, x),
                  poly_factors(Symbolics.expand((x-1)*(x-2)*(x-3)), x))

    # ---- the negative space -----------------------------------------------------
    @test_throws ArgumentError poly_factors(x * y - 1, x)          # two variables
    @test_throws ArgumentError poly_factors(x^2 - 0.5, x)          # non-rational coefficient
    @test_throws ArgumentError poly_factors(sin(x), x)             # not a polynomial
    @test_throws ArgumentError poly_factors(1/x, x)                # not a polynomial

    # an integer-valued float is exact, so it is accepted rather than refused
    @test isequal(Symbolics.expand(factored_poly(x^2 - 4.0, x)), Symbolics.expand(x^2 - 4))

end

@testset "partial_fractions (v0.13.0)" begin

    @variables x y

    # ---- the shapes `precalc/rational_functions.qmd` decomposes ------------------
    d1 = partial_fractions(1/((x-1)*(x-2)), x)
    @test isequal(Symbolics.simplify(Symbolics.simplify_fractions(d1 - 1/((x-1)*(x-2)))), 0)

    d2 = partial_fractions((x+3)/((x-1)^2*(x+2)), x)
    @test isequal(Symbolics.simplify(Symbolics.simplify_fractions(d2 - (x+3)/((x-1)^2*(x+2)))), 0)

    # an improper fraction keeps its polynomial part
    d3 = partial_fractions(x^3/((x-1)*(x-2)), x)
    @test isequal(Symbolics.simplify(Symbolics.simplify_fractions(d3 - x^3/((x-1)*(x-2)))), 0)

    # ---- the decomposition is actually decomposed --------------------------------
    # A function that just handed the input back would pass the identity tests above,
    # so pin the shape too: a genuine decomposition is a sum of terms.
    @test _is_sum(d1)
    @test _is_sum(d2)
    @test _is_sum(d3)

    # repeated factors show as `(x-1)^2`, not the multiplied-out quadratic -- the
    # factored denominator is the thing the chapter is teaching.
    @test occursin("(-1 + x)^2", repr(d2))

    # ---- pass-through and refusals ----------------------------------------------
    @test isequal(partial_fractions(x^2 + 1, x), x^2 + 1)     # no denominator to split
    @test_throws ArgumentError partial_fractions(1/((x-1)*(y-2)), x)   # two variables
    @test_throws ArgumentError partial_fractions(sin(x)/(x-1), x)      # not rational

end

@testset "exports (v0.13.0)" begin

    # These four are the point of the release: a plain `using CalculusWithJuliaSquared`
    # has to expose them unqualified, since that is how the chapters call them.
    for f in (:exact_trig_values, :factored_poly, :poly_factors, :partial_fractions)
        @test f in names(CalculusWithJuliaSquared)
    end

end

# Equal at three exact rational points (positive: a symbolic exponent has no real value at a
# negative base). `simplify_fractions(a - b)` is NOT a proof of equality: it left
# `(x - 2) \frac{29}{x - 2}` uncancelled for two equal expressions (measured 2026-09-16).
function _equal_at_rationals(a, b, vars)
    for vals in ([7//3, 5//11, 2//7], [4//9, 13//5, 3//8], [11//2, 1//13, 9//4])
        sub = Dict(v => vals[i] for (i, v) in enumerate(vars))
        va = Symbolics.value(substitute(a, sub; fold = Val(true)))
        vb = Symbolics.value(substitute(b, sub; fold = Val(true)))
        (va isa Number && vb isa Number) || return false
        exact = va isa Union{Integer, Rational} && vb isa Union{Integer, Rational}
        (exact ? va == vb : isapprox(va, vb; rtol = 1e-12)) || return false
    end
    true
end

@testset "combine_fractions (v0.16.0)" begin

    @variables x a y n
    cl = conventional_latex

    # The prototype's cases (2026-09-16), displayed with v0.16.0's layout. Each result must
    # equal its input at exact rational points and display as mathematics.
    cases = [
        (x^3 + 2x^2 + 6x + 12 + 29/(x - 2), [x], "\\frac{x^{4} + 2 x^{2} + 5}{x - 2}"),
        (partial_fractions(((x-1)*(x-2)) / ((x-3)^3 * (x^2 - x - 1)), x), [x],     # PR2's, recombined
            "\\frac{x^{2} - 3 x + 2}{\\left( x - 3 \\right)^{3} \\left( x^{2} - x - 1 \\right)}"),
        (1/(x - 1) - 1/(x + 1) - 2/(x^2 - 1), [x], "0"),
        (1/(2x + 1) + 1, [x], "\\frac{2 x + 2}{2 x + 1}"),                  # no monic fractions
        (x/2 + 1/(3x), [x], "\\frac{3 x^{2} + 2}{6 x}"),                    # fractions cleared from both halves
        (a*x + 1/(x - a), [x, a], "\\frac{a x^{2} - a^{2} x + 1}{x - a}"),
        ((x^2 - a^2)/(x - a) + 1, [x, a], "x + a + 1"),                     # cancels through a parameter
        (1/x + 1/y, [x, y], "\\frac{x + y}{x y}"),
        ((1/x + 1)/(1/x - 1), [x], "-\\frac{x + 1}{x - 1}"),
        (sin(x) + 1/(x + 1), [x], "\\frac{x \\sin\\left( x \\right) + \\sin\\left( x \\right) + 1}{x + 1}"),
        (sin(x)/(sin(x)^2 - 1) + 1/(sin(x) + 1), [x],                         # cancels through an atom
            "\\frac{2 \\sin\\left( x \\right) - 1}{\\left( \\sin\\left( x \\right) - 1 \\right) " *
            "\\left( \\sin\\left( x \\right) + 1 \\right)}"),
        (x + PI/(x - 1), [x], "\\frac{x^{2} - x + \\pi}{x - 1}"),
        ((x - 1)*(x + 1)/(x + 2), [x], "\\frac{x^{2} - 1}{x + 2}"),
        (x + 1, [x], "x + 1"),
        # documented limits: atoms are independent, so `√2² = 2` is not used, and Symbolics
        # does not merge `x x^{n}`
        ((x^2 - 2)/(x - sqrt(Symbolics.Num(2))), [x], "\\frac{x^{2} - 2}{x - \\sqrt{2}}"),
        (x^n + 1/x, [x, n], "\\frac{x x^{n} + 1}{x}"),
    ]
    for (ex, vars, shown) in cases
        g = combine_fractions(ex)
        @test cl(g) == shown
        @test _equal_at_rationals(ex, g, vars)
        @test occursin("\\[", repr(MIME("text/html"), g))
    end

    # ---- a bigger decomposition: seven terms back to one fraction, factored ----------
    big = (x^7 + 1)/((x - 1)^4 * (x^2 + 1)^2 * (x + 2))
    pf = partial_fractions(big, x)
    @test length(Symbolics.SymbolicUtils.arguments(Symbolics.value(pf))) == 7
    g = combine_fractions(pf)
    @test cl(g) == "\\frac{x^{7} + 1}{\\left( x + 2 \\right) \\left( x - 1 \\right)^{4} " *
                   "\\left( x^{2} + 1 \\right)^{2}}"
    @test _equal_at_rationals(big, g, [x])
    @test (@elapsed combine_fractions(pf)) < 5

    # ---- exact input only, as partial_fractions ------------------------------------
    @test_throws ArgumentError combine_fractions(0.5x + 1/x)
    @test cl(combine_fractions(2.0x + 1/x)) == "\\frac{2 x^{2} + 1}{x}"      # integer-valued: exact
    @test isequal(combine_fractions(Symbolics.Num(3)), Symbolics.Num(3))

    @test :combine_fractions in names(CalculusWithJuliaSquared)
end
