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

    # A constant lands last, whatever order the tree holds it in. `1 - x` left this list in
    # v0.15.0: a two-term sum no longer leads with a minus, so it now renders `1 - x`.
    for ex in (x - 1, x^2 - 3, 5 + x^2)
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

# A `^{...}` group followed directly by another `^` is a double superscript, which TeX
# rejects outright. Brace-aware, so an exponent that itself contains braces is skipped whole.
function _no_double_superscript(s)
    i = firstindex(s)
    while i <= lastindex(s)
        if s[i] == '^' && i < lastindex(s) && s[nextind(s, i)] == '{'
            depth, j = 0, nextind(s, i)
            while j <= lastindex(s)
                s[j] == '{' && (depth += 1)
                s[j] == '}' && (depth -= 1)
                depth == 0 && break
                j = nextind(s, j)
            end
            j < lastindex(s) && s[nextind(s, j)] == '^' && return false
        end
        i = nextind(s, i)
    end
    true
end

# Run `f` with the session defaults changed, restoring them whatever happens -- a failure
# here must not leak a changed setting into every later test.
function _with_default(f; kw...)
    set_conventional_default(; kw...)
    try
        f()
    finally
        reset_conventional_default()
    end
end

@testset "conventional display (v0.15.0)" begin

    @variables x y z a b c h k m p q s t n r E F
    @variables x0 y0 x_0 x₀ theta θ rho_0 lambda1 height v_max f_x x_alpha xs[0:2]
    PI = Symbolics.Num(pi)
    SQ(v) = sqrt(Symbolics.Num(v))
    outputs = String[]                       # every output below, for the structural checks
    cl(ex; kw...) = (out = conventional_latex(ex; kw...); push!(outputs, out); out)

    # ---- 1. a power's base is bracketed unless it is a bare symbol or plain number -----
    # Measured against v0.14.1: a product base lost its brackets, which is WRONG MATH
    # (`(a*x)^y` came out `x a^{y}`), and a power or exponential base produced a double
    # superscript, which TeX refuses to typeset.

    @test cl((a*x)^y)    == "\\left( a x \\right)^{y}"
    @test cl((x/2)^2)    == "\\left( \\frac{x}{2} \\right)^{2}"
    @test cl((1//2)^x)   == "\\left( \\frac{1}{2} \\right)^{x}"
    @test cl((x^2)^y)    == "\\left( x^{2} \\right)^{y}"
    @test cl(exp(x)^2)   == "\\left( e^{x} \\right)^{2}"
    @test cl(sqrt(x)^3)  == "\\left( \\sqrt{x} \\right)^{3}"
    @test cl(log(x)^2)   == "\\left( \\log\\left( x \\right) \\right)^{2}"
    @test cl(abs(x)^2)   == "\\left( \\left|x\\right| \\right)^{2}"

    # negative space: these bases need no brackets, or already had the right ones
    @test cl((x+1)^2)            == "\\left( x + 1 \\right)^{2}"
    @test cl(Symbolics.Num(2)^x) == "2^{x}"
    @test cl((-2)^x)             == "\\left( -2 \\right)^{x}"
    @test cl(PI^x)               == "\\pi^{x}"
    @test cl((x^2)^(1//3))       == "x^{\\frac{2}{3}}"
    @test cl((2.5)^x)            == "2.5^{x}"

    # ---- 2. negative powers ----------------------------------------------------------
    # Symbolics STORES `x^(-2)` as `(1/x)^2` -- the same tree -- so this is how a negative
    # power reaches the page. A text writes it as one fraction.

    @test isequal(Symbolics.value(x^(-2)), Symbolics.value((1/x)^2))
    @test cl(x^(-2))         == "\\frac{1}{x^{2}}"
    @test cl((1/x)^2)        == "\\frac{1}{x^{2}}"
    @test cl((1/(x+1))^2)    == "\\frac{1}{\\left( x + 1 \\right)^{2}}"
    @test cl(a*x^(-2))       == "\\frac{a}{x^{2}}"      # stored as `a * (1/x)^2`
    @test cl(x^(-1))         == "\\frac{1}{x}"          # unchanged: stored as `1/x`
    # only a numerator of 1 folds; any other fraction base keeps its brackets
    @test cl((a/x)^2)        == "\\left( \\frac{a}{x} \\right)^{2}"

    # ---- 3. factor order: numbers, constants, letters (variables last), sums, functions --

    @test cl(a*x^2)              == "a x^{2}"
    @test cl(b*x)                == "b x"
    @test cl(3*h*x)              == "3 h x"
    @test cl(-2*b*x)             == "-2 b x"
    @test cl(PI*a*x)             == "\\pi a x"
    @test cl(F*E)                == "E F"               # alphabetical, ignoring case
    @test cl(a*E^2)              == "a E^{2}"
    @test cl(k*x*t)              == "k t x"             # variables after other letters
    @test cl(sqrt(x)*a)          == "a \\sqrt{x}"       # a radical of a symbol is a function
    @test cl((x+1)*(x-1)*a)      == "a \\left( x - 1 \\right) \\left( x + 1 \\right)"
    @test cl((x+1)*sin(x))       == "\\left( x + 1 \\right) \\sin\\left( x \\right)"
    @test cl(factored_poly(2x^3 - 6x^2 + 4x, x)) ==
          "2 x \\left( x - 1 \\right) \\left( x - 2 \\right)"

    # functions in textbook order, not the alphabetical order the total key would fall to
    @test cl(sin(x)*cos(x))      == "\\sin\\left( x \\right) \\cos\\left( x \\right)"
    @test cl(exp(x)*sin(x))      == "e^{x} \\sin\\left( x \\right)"
    @test cl(sec(x)*tan(x))      == "\\tan\\left( x \\right) \\sec\\left( x \\right)"
    @test cl(log(x)*sin(x))      == "\\sin\\left( x \\right) \\log\\left( x \\right)"
    @test cl(sin(2x)*sin(x))     == "\\sin\\left( x \\right) \\sin\\left( 2 x \\right)"

    # negative space
    @test cl(2*PI*x)             == "2 \\pi x"
    @test cl(SQ(2)*x)            == "\\sqrt{2} x"
    @test cl(x^5*sin(x))         == "x^{5} \\sin\\left( x \\right)"
    @test cl(exp(x)*x^2)         == "x^{2} e^{x}"
    @test cl(x*(x+1))            == "x \\left( x + 1 \\right)"
    @test cl(SQ(2)*x + 1)        == "\\sqrt{2} x + 1"

    # ---- 4. the arguments of a function are typeset by the same rules ------------------

    @test cl(cos(2x))            == "\\cos\\left( 2 x \\right)"
    @test cl(abs(x - 1))         == "\\left|x - 1\\right|"
    @test cl(exp(x - 1))         == "e^{x - 1}"
    @test cl(exp(-x^2/2))        == "e^{-\\frac{x^{2}}{2}}"
    @test cl(cos(PI*x/2))        == "\\cos\\left( \\frac{\\pi x}{2} \\right)"
    @test cl(atan(2x))           == "\\arctan\\left( 2 x \\right)"
    @test cl(sin(a*(x - b*PI) + c)) == "\\sin\\left( a \\left( x - \\pi b \\right) + c \\right)"
    @test cl(sin(x)^2)           == "\\sin^{2}\\left( x \\right)"
    # negative space
    @test cl(log(x + 1))         == "\\log\\left( x + 1 \\right)"
    @test occursin("\\arctan", cl(atan(y, x)))           # two arguments: Latexify's shape

    # ---- 5. complex constants keep their imaginary unit ---------------------------------
    # Measured against v0.14.1: `abs` of a Complex was taken, so `i` came out `1.0` and
    # `-1 + 2i` came out as its modulus -- silently wrong mathematics.

    @test Set(cl.(symbolic_solve(x^2 + 1, x)))      == Set(["i", "-i"])
    @test Set(cl.(symbolic_solve(x^2 + 2x + 5, x))) == Set(["-1 + 2 i", "-1 - 2 i"])
    @test Set(cl.(symbolic_solve(x^3 - 1, x)))      ==
          Set(["1", "-\\frac{1}{2} + \\frac{\\sqrt{3}}{2} i", "-\\frac{1}{2} - \\frac{\\sqrt{3}}{2} i"])
    # Cardano's coefficients arrive as FLOATS (`0.0 + 0.5im`), and a float stays a float; what
    # matters is that the unit survives, ends its term, and is not bracketed with its sign.
    let cardano2 = cl(symbolic_solve(x^3 + p*x + q, x)[2])
        @test occursin(r" i( [+-] |$)", cardano2)
        @test !occursin(r"\\left\( -?[0-9.]+ i \\right\)", cardano2)
    end

    # ---- 6. sums: degree in the VARIABLE letters, then total degree, then alphabetical --
    # Default variables n r t u v w x y z θ. Subscripted names are constants (exact match).

    @test cl(x - b*PI)                     == "x - \\pi b"
    @test cl(a + PI)                       == "a + \\pi"        # v0.14.1: `\pi + a` -- π is a constant
    @test cl(3x^2 + 3h*x + h^2)            == "3 x^{2} + 3 h x + h^{2}"
    @test cl(simplify(expand(((x-h)^3 - x^3)/h))) == "-3 x^{2} + 3 h x - h^{2}"
    @test cl(expand(a*(x-E)^2 + b*(x-E) + c + F)) ==
          "a x^{2} - 2 a E x + b x + a E^{2} - b E + c + F"
    @test cl(simplify(expand(x^2 * substitute(a*x^2 + b*x + c, x => 1/x)))) == "c x^{2} + b x + a"
    @test cl(a*x^2 + b*x + c)              == "a x^{2} + b x + c"
    @test cl(m*x - m*x0 + y0)              == "m x - m x_{0} + y_{0}"   # x0, y0 are constants
    @test cl(x^2 + 2x*y + y^2)             == "x^{2} + 2 x y + y^{2}"   # v0.14.1: `2 x y + x^{2} + y^{2}`
    @test cl(x^3 + p*x + q)                == "x^{3} + p x + q"         # v0.14.1: `x^{3} + x p + q`
    # negative space
    @test cl(b^2 - 4c)                     == "b^{2} - 4 c"
    @test cl(-(1//2)*b + (1//2)*sqrt(b^2 - 4c)) == "\\frac{-b + \\sqrt{b^{2} - 4 c}}{2}"
    @test cl(3//4 + (1//4)*SQ(41))         == "\\frac{3 + \\sqrt{41}}{4}"

    # the keyword replaces the default letters for one call, and only that call
    @test cl(expand((s - k)^2))                      == "k^{2} - 2 k s + s^{2}"
    @test cl(expand((s - k)^2); variables = [s])     == "s^{2} - 2 k s + k^{2}"
    @test cl(expand((s - k)^2); variables = [:s])    == "s^{2} - 2 k s + k^{2}"
    @test cl(expand((s - k)^2))                      == "k^{2} - 2 k s + s^{2}"

    # ---- two-term sums do not lead with a minus ------------------------------------------
    # `1 - x` and `-x + 1` are one tree, so this is a rule about display, not about input.

    @test cl(1 - x)              == "1 - x"
    @test cl(1 - x^2)            == "1 - x^{2}"
    @test cl(100 - 16t^2)        == "100 - 16 t^{2}"
    @test cl(1 - r^(n + 1))      == "1 - r^{n + 1}"
    @test cl(h - x)              == "h - x"
    @test cl(-(1//2)*x + 1//2)   == "\\frac{1 - x}{2}"       # the swap happens before combining
    # negative space: an all-negative pair, three or more terms, and a radical-only second
    # term (the quadratic formula keeps `-b + \sqrt{...}`; `a + b i` keeps its real part first)
    @test cl(-x - 1)             == "-x - 1"
    @test cl(-x^2 + 2x - 1)      == "-x^{2} + 2 x - 1"
    @test cl(x - 1)              == "x - 1"

    # ---- the order option: descending by default, ascending on request ------------------

    @test cl(1 + x + x^2/2)                          == "\\frac{x^{2}}{2} + x + 1"
    @test cl(1 + x + x^2/2; order = :ascending)      == "1 + x + \\frac{x^{2}}{2}"
    @test cl(Symbolics.taylor(exp(x), x, 0:3); order = :ascending) ==
          "1 + x + \\frac{x^{2}}{2} + \\frac{x^{3}}{6}"
    @test cl(1 + x + x^2/2; order = :descending)     == "\\frac{x^{2}}{2} + x + 1"
    @test_throws ArgumentError conventional_latex(x + 1; order = :sideways)

    # ---- the session defaults, read by conventional_latex AND by show ---------------------

    const_default_vars = [:n, :r, :t, :u, :v, :w, :x, :y, :z, :θ, :theta]
    @test issetequal(get_conventional_default().variables, const_default_vars)
    @test get_conventional_default().order == :descending
    @test _with_default(() -> conventional_latex(expand((s - k)^2)); variables = [s]) ==
          "s^{2} - 2 k s + k^{2}"
    @test _with_default(() -> sprint(show, MIME"text/latex"(), expand((s - k)^2)); variables = [:s]) ==
          "\\[ s^{2} - 2 k s + k^{2} \\]"
    @test _with_default(() -> sprint(show, MIME"text/latex"(), 1 + x + x^2/2); order = :ascending) ==
          "\\[ 1 + x + \\frac{x^{2}}{2} \\]"
    @test _with_default(() -> get_conventional_default().variables; variables = [s, t]) == [:s, :t]
    # setting one option leaves the other alone, as Latexify's `set_default` does
    @test _with_default(; variables = [s]) do
        set_conventional_default(; order = :ascending)
        get_conventional_default()
    end == (variables = [:s], order = :ascending)
    # a keyword still wins over the session default, for that call only
    @test _with_default(() -> conventional_latex(1 + x; order = :descending); order = :ascending) == "x + 1"
    @test_throws ArgumentError set_conventional_default(; colour = :red)
    # and everything is back to the default afterwards
    @test issetequal(get_conventional_default().variables, const_default_vars)
    @test get_conventional_default().order == :descending

    # ---- 7. show goes through conventional_latex ---------------------------------------

    @test sprint(show, MIME"text/latex"(), a*x^2 + b*x + c) == "\\[ a x^{2} + b x + c \\]"
    @test sprint(show, MIME"text/html"(), a*x^2 + b*x + c) ==
          "<span class=\"math-left-align\" style=\"padding-left:4px;width:0;float:left;\">\\[ a x^{2} + b x + c \\]</span>"
    @test sprint(show, MIME"text/latex"(), Symbolics.Num(4)) == "\\[ 4 \\]"
    # the solution vector keeps Latexify's array layout, one conventional row per root
    @test sprint(show, MIME"text/latex"(), symbolic_solve(x^2 - 2, x)) ==
          "\\[ \\left[\n\\begin{array}{c}\n\\sqrt{2} \\\\\n-\\sqrt{2} \\\\\n\\end{array}\n\\right] \\]"
    @test occursin("\\frac{-b + \\sqrt{b^{2} - 4 c}}{2}",
                   sprint(show, MIME"text/html"(), symbolic_solve(x^2 + b*x + c, x)))

    # ---- 8. operator names upright, and no `~` ------------------------------------------

    @test cl(sign(x))                 == "\\operatorname{sign}\\left( x \\right)"
    @test cl(max(x, y))               == "\\max\\left( x, y \\right)"
    @test cl(min(x, y))               == "\\min\\left( x, y \\right)"
    # A derivative is written in FRACTION form, always. The operator form `\frac{d}{dx} u(x)`
    # was tried first and the book replay caught it: inside a product it reads
    # `\frac{d}{dx} u(x) v(x)` -- the derivative OF uv -- in the very section teaching the
    # product rule. A derivative factor also follows the plain functions it multiplies, as
    # the prose puts it: "u times the derivative of v". The `d` is ITALIC, as US calculus texts
    # and this book's own prose write it (110 italic `\frac{dy}{dx}`-style uses, no upright
    # one); Latexify's upright `\mathrm{d}` is the ISO 80000-2 convention, which would also
    # want an upright e and i, and sat jarringly under the prose.
    @test cl(Differential(x)(sin(x)))     == "\\frac{d \\sin\\left( x \\right)}{dx}"
    @test cl(Differential(x)(x^2 + 1))    == "\\frac{d \\left( x^{2} + 1 \\right)}{dx}"
    @test cl((Differential(x)^2)(sin(x))) == "\\frac{d^{2} \\sin\\left( x \\right)}{dx^{2}}"
    let (u, v) = (@variables u(..) v(..))
        prod_rule = cl(expand_derivatives(Differential(x)(u(x) * v(x))))
        @test occursin("u\\left( x \\right) \\frac{d v\\left( x \\right)}{dx}", prod_rule)
        @test occursin("v\\left( x \\right) \\frac{d u\\left( x \\right)}{dx}", prod_rule)
        @test !occursin("{dx} u", prod_rule) && !occursin("{dx} v", prod_rule)
        # expand_derivatives gives `-u v'/v^2 + u'/v` here, not one fraction
        quot_rule = cl(expand_derivatives(Differential(x)(u(x) / v(x))))
        @test occursin("u\\left( x \\right) \\frac{d v\\left( x \\right)}{dx}", quot_rule)
        @test occursin("\\frac{d u\\left( x \\right)}{dx}", quot_rule)
        @test !occursin("{dx} u", quot_rule) && !occursin("{dx} v", quot_rule)
    end

    # ---- 10. symbol names typeset as mathematics, not as code ---------------------------
    # Latexify sets every multi-character name in typewriter: `\mathtt{x0}`, `\mathtt{theta}`.

    @test cl(x0)      == "x_{0}"
    @test cl(x_0)     == "x_{0}"
    @test cl(x₀)      == "x_{0}"
    @test cl(theta)   == "\\theta"
    @test cl(θ)       == "\\theta"
    @test cl(rho_0)   == "\\rho_{0}"
    @test cl(lambda1) == "\\lambda_{1}"
    @test cl(height)  == "\\mathit{height}"
    @test cl(v_max)   == "v_{\\mathrm{max}}"          # a descriptive subscript is upright
    @test cl(f_x)     == "f_{x}"                      # a one-letter subscript is italic
    @test cl(x_alpha) == "x_{\\alpha}"
    @test cl(r*theta) == "r \\theta"                  # both default variables
    @test cl(xs[1])   == "\\mathit{xs}_{1}"           # array elements: published in polynomials_package

    # Array elements order by name AND index. The book replay caught the index being ignored:
    # polynomials_package's Lagrange coefficients tied on `xs`/`ys`, fell to the printed-text
    # tiebreak, and came out with every negative term first.
    @variables ys[0:2]
    @test cl(xs[1]*xs[0])      == "\\mathit{xs}_{0} \\mathit{xs}_{1}"
    @test cl(xs[2]^2 * xs[0])  == "\\mathit{xs}_{0} \\mathit{xs}_{2}^{2}"
    @test cl(xs[0]*ys[1] - xs[0]*ys[2] - xs[1]*ys[0] + xs[1]*ys[2]) ==
          "\\mathit{xs}_{0} \\mathit{ys}_{1} - \\mathit{xs}_{0} \\mathit{ys}_{2} - \\mathit{xs}_{1} \\mathit{ys}_{0} + \\mathit{xs}_{1} \\mathit{ys}_{2}"

    # ---- the ordering stays DETERMINISTIC -----------------------------------------------
    # Rebuild each expression every time; sorting a cached tree would test nothing.

    for build in (() -> expand(a*(x-E)^2 + b*(x-E) + c + F), () -> sin(x)*cos(x)*exp(x)*x^2*a,
                  () -> expand((s - k)^2), () -> symbolic_solve(x^3 - 1, x)[2])
        @test length(Set(conventional_latex(build()) for _ in 1:20)) == 1
    end

    # ---- structural validity of everything produced above -------------------------------

    @test length(outputs) > 80                  # guards against the checks running on nothing
    for out in outputs
        @test _braces_balanced(out)
        @test _no_double_superscript(out)
        @test !startswith(out, " ")              # the Pandoc defect
        @test !occursin("~", out)                # Latexify's product separator
        @test !occursin("\\mathtt", out)         # names set as code
    end
end
