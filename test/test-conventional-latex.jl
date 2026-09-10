using CalculusWithJuliaSquared
using Test

# Whatever else it does, the output has to be LaTeX a renderer will accept. Every
# expression in this file is checked for balanced braces, because a regex-era bug that
# drops a `}` produces a page that fails to typeset rather than a wrong answer.
function _braces_balanced(s)
    depth = 0
    prev = ' '
    for ch in s
        if prev != '\\'
            ch == '{' && (depth += 1)
            ch == '}' && (depth -= 1)
        end
        depth < 0 && return false
        prev = ch
    end
    depth == 0
end

@testset "conventional_latex (v0.14.0)" begin

    @variables x b c p q s
    PI = Symbolics.Num(pi)

    # ---- symptom 1: a rational coefficient must fold into ONE fraction -------------
    # `Symbolics` keeps a quotient as a division term only while its rational
    # coefficient is exactly 1; every other coefficient becomes a product, which
    # Latexify writes as a fraction TIMES a symbol.

    @test conventional_latex((2//3) * PI)            == "\\frac{2 \\pi}{3}"
    @test conventional_latex((1//2) * PI)            == "\\frac{\\pi}{2}"
    @test conventional_latex((3//4) * PI)            == "\\frac{3 \\pi}{4}"
    @test conventional_latex((5//6) * PI)            == "\\frac{5 \\pi}{6}"

    # The sign is incidental -- negation merely turns a coefficient of 1 into -1, which
    # is no longer 1 -- but it is the case that produced a broken page, so pin it.
    @test conventional_latex(-(1//2) * sqrt(Symbolics.Num(2))) == "-\\frac{\\sqrt{2}}{2}"
    @test conventional_latex(-(1//3) * sqrt(Symbolics.Num(3))) == "-\\frac{\\sqrt{3}}{3}"

    # THE defect, not a cosmetic one: Pandoc will not open inline math on "$ ", so a
    # leading space after the delimiter renders as a literal dollar sign plus raw LaTeX.
    for ex in (-(1//2) * sqrt(Symbolics.Num(2)), -(2//3) * PI, -x, -(x + 1), -(1//2)*b)
        @test !startswith(conventional_latex(ex), " ")
    end

    # ---- symptom 2: a rational numerator must not nest -----------------------------
    # `partial_fractions` produces exactly this shape.

    @test conventional_latex(partial_fractions((x+1)/((x-1)*(x+2)), x)) ==
          "\\frac{1}{3 \\left( x + 2 \\right)} + \\frac{2}{3 \\left( x - 1 \\right)}"
    @test !occursin("\\frac{\\frac", conventional_latex(partial_fractions(1/(x*(x-3)*(x+3)), x)))

    # The brackets are load-bearing where the rational has a denominator: `\frac{1}{3x-1}`
    # is a different expression from `\frac{1}{3(x-1)}`. Where it does not, they must go.
    @test conventional_latex(1/(x-1)) == "\\frac{1}{x - 1}"
    @test occursin("3 \\left( x - 1 \\right)", conventional_latex((2//3)/(x-1)))

    # ---- symptom 3: terms in mathematical order ------------------------------------
    # Symbolics stores `x - 1` as a sum with arguments [-1, x].

    @test conventional_latex(x - 1)      == "x - 1"
    @test conventional_latex(x - 2)      == "x - 2"
    @test conventional_latex(x + 2)      == "x + 2"
    @test conventional_latex(x^2 + 1)    == "x^{2} + 1"
    @test conventional_latex(b^2 - 4c)   == "b^{2} - 4 c"
    @test conventional_latex(x^3 - x + 1) == "x^{3} - x + 1"

    # A constant always lands last, whatever order the tree holds it in.
    for ex in (x - 1, 1 - x, x^2 - 3, 5 + x^2)
        @test !startswith(conventional_latex(ex), "-1 ")
        @test !occursin(r"^-?\d+ [+-] ", conventional_latex(ex))
    end

    # ---- the expressions PR2 and PR3 actually render -------------------------------

    # ---- terms over a common denominator combine ----------------------------------
    # Two fractions added together is not how a text writes a closed-form solution; one
    # fraction is. This is the step that turns the pieces into the formula a reader
    # recognises.

    # the quadratic formula, with symbolic coefficients
    root = -(1//2)*b + (1//2)*sqrt(b^2 - 4c)
    @test conventional_latex(root) == "\\frac{-b + \\sqrt{b^{2} - 4 c}}{2}"

    # an exact surd from a numeric quadratic
    @test conventional_latex(3//4 + (1//4)*sqrt(Symbolics.Num(41))) ==
          "\\frac{3 + \\sqrt{41}}{4}"

    @test conventional_latex((1//2)*x - 1//2) == "\\frac{x - 1}{2}"

    # The negative space matters more than the feature. Combining requires EVERY term to
    # be a fraction over the SAME denominator:
    #   - different denominators must stay apart, or partial fractions -- whose whole
    #     point is separate denominators -- would be silently recombined;
    #   - a non-fraction term blocks it, since nobody writes `x + 1/2` as `(2x + 1)/2`.
    @test conventional_latex(x + 1//2) == "x + \\frac{1}{2}"
    let pf = conventional_latex(partial_fractions((x+1)/((x-1)*(x+2)), x))
        @test pf == "\\frac{1}{3 \\left( x + 2 \\right)} + \\frac{2}{3 \\left( x - 1 \\right)}"
        @test count("\\frac", pf) == 2      # two bars, not one
    end
    @test count("\\frac", conventional_latex(partial_fractions(1/(x*(x-3)*(x+3)), x))) == 3

    # Cardano. `symbolic_solve` builds radicals from `Symbolics.scbrt`, NOT `Base.cbrt`;
    # before that was recognised every cubic root fell through to the raw Latexify
    # output, which is the exact shape this function exists to fix.
    cardano = conventional_latex(symbolic_solve(x^3 + p*x + q, x)[1])
    @test occursin("\\sqrt[3]{", cardano)
    @test !occursin("~", cardano)            # `~` is Latexify's product separator
    @test !occursin("\\frac{1}{2} ~", cardano)
    @test occursin("-\\frac{q}{2}", cardano)

    # ---- the ordering must be DETERMINISTIC ----------------------------------------
    # `sort` is not guaranteed stable, so terms of equal degree could swap between one
    # render and the next -- silently rewriting a published page on an unrelated
    # rebuild. This was measured happening on Cardano's roots before the ordering key
    # was made total. Rebuild the expression each time: sorting a cached tree would
    # test nothing.

    @test length(Set(conventional_latex(symbolic_solve(x^3 + p*x + q, x)[1]) for _ in 1:20)) == 1
    @test length(Set(conventional_latex(-(1//2)*b + (1//2)*sqrt(b^2 - 4c)) for _ in 1:20)) == 1
    @test length(Set(conventional_latex(partial_fractions(1/(x*(x-3)*(x+3)), x)) for _ in 1:20)) == 1

    # ---- radicals sort last, but only when the term is nothing but a radical --------
    # `-b + sqrt(...)`, `-q/2 + sqrt(...)`, `3 + sqrt(41)`: the rational part leads.

    @test startswith(conventional_latex(-(1//2)*b + (1//2)*sqrt(b^2 - 4c)), "\\frac{-b +")
    @test occursin("-\\frac{q}{2} + \\sqrt{",
                   conventional_latex(symbolic_solve(x^3 + p*x + q, x)[1]))

    # ...and the guard that keeps that from overreaching: a radical multiplied by a
    # polynomial factor is ordered by degree as usual, not shoved to the end.
    @test conventional_latex(sqrt(Symbolics.Num(2))*x + 1) == "\\sqrt{2} x + 1"

    # ---- the fallback must not be silent breakage ----------------------------------
    # An unrecognised head renders as Latexify always rendered it, rather than failing.

    @test occursin("\\sin", conventional_latex(sin(x)))
    # Latexify writes the conventional name, not the Julia one -- `atan` is `\arctan`.
    @test occursin("\\arctan", conventional_latex(atan(x)))
    @test !isempty(conventional_latex(exp(x) + sin(x)*cos(x)))

    # A float coefficient is NOT folded into a fraction -- `\frac{0.5 x}{1}` helps nobody.
    @test !occursin("\\frac", conventional_latex(0.5 * x))

    # ---- structural validity -------------------------------------------------------

    for ex in (x - 1, b^2 - 4c, (2//3)*PI, -(1//2)*sqrt(Symbolics.Num(2)),
               partial_fractions((x+1)/((x-1)*(x+2)), x),
               partial_fractions(1/(x*(x-3)*(x+3)), x),
               symbolic_solve(x^3 + p*x + q, x)[1],
               factored_poly(2x^3 - 6x^2 + 4x, x),
               1/(x-1), x^3 - x + 1, sin(x) + cos(x), exp(x)*x^2,
               3//4 + (1//4)*sqrt(Symbolics.Num(41)))
        out = conventional_latex(ex)
        @test _braces_balanced(out)
        @test !startswith(out, " ")          # the Pandoc defect
        @test !occursin("\\begin{equation}", out)   # body only, no delimiters
        @test !isempty(out)
    end

    # ---- idempotence on strings ----------------------------------------------------
    # The call site passes cells that may already be plain text.

    @test conventional_latex("already text") == "already text"

    # ---- the v0.13.0 trig table still renders as it did ----------------------------
    # This function was extracted from `precalc/plotting.qmd`, whose table is the
    # regression case: if these change, a published chapter changes.

    @test conventional_latex(exact_trig_values(cos(PI/6))) == "\\frac{\\sqrt{3}}{2}"
    @test conventional_latex(exact_trig_values(sin(PI/6))) == "\\frac{1}{2}"
    @test conventional_latex(exact_trig_values(cos(3PI/4))) == "-\\frac{\\sqrt{2}}{2}"
    @test conventional_latex(exact_trig_values(cos(5PI/6))) == "-\\frac{\\sqrt{3}}{2}"
    @test conventional_latex(2PI/3) == "\\frac{2 \\pi}{3}"
    @test conventional_latex(3PI/4) == "\\frac{3 \\pi}{4}"
    @test conventional_latex(5PI/6) == "\\frac{5 \\pi}{6}"
end
