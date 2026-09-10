## ---------------------------------------------------------------------------------
## Conventional mathematical typesetting for `Symbolics` expressions.
##
## `Latexify` renders a `Symbolics` expression faithfully -- which is the problem. It
## prints the tree, and the tree is in a canonical form chosen for algebra, not for
## reading. Three artefacts show up in every rendered expression these notes produce:
##
##   1. A rational coefficient stays a separate factor. `Symbolics` keeps a quotient as
##      a division term ONLY while its rational coefficient is exactly 1; any other
##      coefficient folds into a product, which `Latexify` writes as a fraction TIMES a
##      symbol:  2*pi/3  ->  \frac{2}{3} ~ \pi   where a text writes  \frac{2\pi}{3}.
##
##   2. A rational numerator nests: `partial_fractions` yields terms like (1//3)/(x+2),
##      rendered  \frac{\frac{1}{3}}{2 + x}  where a text writes  \frac{1}{3(x+2)}.
##
##   3. Terms come out in canonical order, constants first: `x - 1` is stored as a sum
##      with arguments [-1, x] and renders as  -1 + x.
##
## None of these can be fixed by rewriting the expression, and that is not a matter of
## trying harder: `(2//3)*pi`, `(2*pi)/3` and `Num(2)*pi/Num(3)` all construct the SAME
## tree -- `isequal` returns `true` -- because canonicalisation happens on construction.
## The tree is not wrong; it simply is not prose. So the conversion has to happen while
## emitting the LaTeX, which is what this file does: it walks the expression and writes
## the string itself rather than post-processing what `Latexify` produced.
##
## There is a fourth, uglier symptom that this also cures. A leading negative renders as
## `$ - \frac{1}{2} ~ \sqrt{2}$` -- note the space after the dollar. Pandoc will not open
## inline math on `$ `, so such a cell renders as a literal dollar sign followed by raw
## LaTeX. That is a broken page, not a cosmetic quibble.
##
## Anything this file does not recognise is handed to `Latexify` unchanged, so an
## unfamiliar expression renders as it always did rather than failing.
## ---------------------------------------------------------------------------------

# Precedence of the context a subexpression is being written into, so that parentheses
# are added exactly where they change the reading.
const _PREC_SUM   = 1   # inside a sum: nothing needs bracketing
const _PREC_PROD  = 2   # a factor in a product: a sum does
const _PREC_POWER = 3   # the base of a power: a sum or a product does

# The plain number behind a leaf, or `nothing` if this is not a numeric leaf.
_cl_number(a) = a isa Number ? a :
    (_SU.isconst(a) ? (Symbolics.value(a) isa Number ? Symbolics.value(a) : nothing) : nothing)

# Only integers and rationals are folded into fractions. A float is left alone (writing
# `\frac{0.5 x}{1}` helps nobody) and an irrational such as `π` is a factor, not a
# coefficient -- folding it would produce `\frac{\pi x}{1}`.
function _cl_rational(a)
    v = _cl_number(a)
    v isa Integer && return Rational{BigInt}(v)
    v isa Rational && return Rational{BigInt}(v)
    nothing
end

_cl_isneg(r::Rational) = r < 0

# Total degree, used only to order the terms of a sum the way a mathematics text does:
# highest power first, constant last. It is a sort key rather than a rigorous degree,
# but it is RATIONAL rather than integer, because a radical halves the degree beneath it
# and that matters: `sqrt(41)` is a constant (degree 0), so it sorts alongside `3//4`
# rather than ahead of it, while `sqrt(b^2 - 4c)` is degree 1 and ties with `b`. Both
# ties then break to plain-before-radical, which is how a text writes those formulas.
const _CLDeg = Rational{Int}

function _cl_degree(t)::_CLDeg
    r = _cl_number(t)
    r !== nothing && return 0//1
    _SU.iscall(t) || return 1//1                    # a bare symbol
    op, args = _SU.operation(t), _SU.arguments(t)
    op === (+) && return maximum(_cl_degree, args; init = 0//1)
    op === (*) && return sum(_cl_degree, args; init = 0//1)
    if op === (^)
        e = _cl_number(args[2])
        e isa Union{Integer, Rational} && return _cl_degree(args[1]) * _CLDeg(e)
        return _cl_degree(args[1])
    end
    op === (/) && return _cl_degree(args[1]) - _cl_degree(args[2])
    (op === sqrt || op === Symbolics.ssqrt) && return _cl_degree(args[1]) // 2
    (op === cbrt || op === Symbolics.scbrt) && return _cl_degree(args[1]) // 3
    1//1                                            # sin, log, ... : treat as degree 1
end

# Does this term contain a radical or another non-arithmetic head? Used only to break a
# tie in the ordering: a text writes Cardano's root as `-q/2 + sqrt(...)`, putting the
# plain term before the radical, and both have total degree 1.
function _cl_hasradical(t)
    _SU.iscall(t) || return false
    op, args = _SU.operation(t), _SU.arguments(t)
    op in (+, *, /, ^) || return true
    any(_cl_hasradical, args)
end

# Degree of the parts of a term lying OUTSIDE any radical. `sqrt(2)*x` has outer degree
# 1 (the `x`); `sqrt(b^2 - 4c)/2` has outer degree 0, being nothing but a radical.
function _cl_outer_degree(t)::_CLDeg
    r = _cl_number(t)
    r !== nothing && return 0//1
    _SU.iscall(t) || return 1//1
    op, args = _SU.operation(t), _SU.arguments(t)
    (op === sqrt || op === Symbolics.ssqrt ||
     op === cbrt || op === Symbolics.scbrt) && return 0//1
    op === (*) && return sum(_cl_outer_degree, args; init = 0//1)
    op === (+) && return maximum(_cl_outer_degree, args; init = 0//1)
    op === (/) && return _cl_outer_degree(args[1]) - _cl_outer_degree(args[2])
    if op === (^)
        e = _cl_number(args[2])
        e isa Union{Integer, Rational} && return _cl_outer_degree(args[1]) * _CLDeg(e)
        return _cl_outer_degree(args[1])
    end
    1//1
end

# A term that is nothing but a radical (times a rational) sorts LAST, whatever its
# degree. That is the convention in every closed-form solution these notes print:
# `-b + sqrt(b^2 - 4c)`, `-q/2 + sqrt(q^2/4 + p^3/27)`, `3 + sqrt(41)` -- the rational
# part leads and the radical follows. Requiring outer degree 0 is what keeps it from
# overreaching: `sqrt(2)*x + 1` has a polynomial factor outside the radical, so it is
# ordered by degree as usual and still comes out as `sqrt(2) x + 1`.
_cl_isradicalterm(t) = _cl_hasradical(t) && _cl_outer_degree(t) == 0

# The ordering key for the terms of a sum. It must be TOTAL, not merely a preference:
# `sort` is not guaranteed stable, so any two terms comparing equal could swap between
# one render and the next. That is not a cosmetic risk -- it silently rewrites a
# published page on an unrelated rebuild. Measured happening on Cardano's roots.
# `string(t)` is the final tiebreak precisely because it can never tie.
_cl_sortkey(a) = (_cl_isradicalterm(a), -_cl_degree(a), string(a))

# `Latexify`'s own rendering of a subtree, with the display-math wrapper stripped. This
# is the escape hatch for every node shape not handled below.
function _cl_fallback(t)
    s = string(Latexify.latexify(Symbolics.Num(t)))
    s = replace(s, "\\begin{equation}" => "", "\\end{equation}" => "")
    s = replace(s, "π" => "\\pi")
    String(strip(s))
end

_cl_paren(s) = "\\left( " * s * " \\right)"

# ---------------------------------------------------------------------------------
# numbers
# ---------------------------------------------------------------------------------

function _cl_num_latex(r::Rational)
    d = denominator(r)
    n = numerator(r)
    d == 1 && return string(n)
    n < 0 ? "-\\frac{$(-n)}{$d}" : "\\frac{$n}{$d}"
end

# ---------------------------------------------------------------------------------
# the walk
#
# `_cl_parts` is the heart of it. It returns three things rather than a string:
#
#     (negative?, numerator, denominator)
#
# Keeping the sign separate lets a sum write ` - x` instead of ` + -x`, and stops a
# leading minus ever landing next to a `$` delimiter (the Pandoc defect). Keeping the
# DENOMINATOR separate lets a sum notice that its terms share one and write them over a
# single bar -- so `-b/2 + sqrt(b^2-4c)/2` becomes the quadratic formula as a text
# prints it, rather than two fractions added together.
#
# Negation is never applied to the tree, which would re-canonicalise; only to the
# string being built.
# ---------------------------------------------------------------------------------

# Returns `(negative::Bool, numerator::String, denominator::String)`. An empty denominator
# means the term is not a fraction. A comment rather than a docstring deliberately: this is
# a private helper, and `@autodocs` would otherwise publish it as part of the API.
function _cl_parts(t, prec::Int = _PREC_SUM)
    # --- numeric leaf ---------------------------------------------------------
    r = _cl_rational(t)
    if r !== nothing
        neg = _cl_isneg(r)
        a = abs(r)
        d = denominator(a)
        return d == 1 ? (neg, string(numerator(a)), "") :
                        (neg, string(numerator(a)), string(d))
    end
    v = _cl_number(t)
    if v !== nothing
        v isa Irrational && return (false, v === Base.pi ? "\\pi" : _cl_fallback(t), "")
        return (v isa Real && v < 0, string(abs(v)), "")
    end

    # --- symbol ---------------------------------------------------------------
    _SU.iscall(t) || return (false, _cl_fallback(t), "")

    op, args = _SU.operation(t), _SU.arguments(t)

    # --- sum ------------------------------------------------------------------
    if op === (+)
        terms = sort(collect(args); by = _cl_sortkey)
        parts = [_cl_parts(a, _PREC_SUM) for a in terms]

        # If every term is a fraction over the SAME denominator, write one fraction.
        # Requiring *every* term to share it is what keeps `1/(3(x+2)) + 2/(3(x-1))`
        # apart -- those denominators differ -- and keeps `x + 1/2` from becoming
        # `(2x + 1)/2`, which is not how anyone writes it.
        den1 = parts[1][3]
        if !isempty(den1) && all(p -> p[3] == den1, parts)
            io = IOBuffer()
            print(io, parts[1][1] ? "-" : "", parts[1][2])
            for p in parts[2:end]
                print(io, p[1] ? " - " : " + ", p[2])
            end
            return (false, String(take!(io)), den1)
        end

        io = IOBuffer()
        n1, b1 = _cl_join(parts[1])
        print(io, n1 ? "-" : "", b1)
        for p in parts[2:end]
            n, b = _cl_join(p)
            print(io, n ? " - " : " + ", b)
        end
        s = String(take!(io))
        return (false, prec >= _PREC_PROD ? _cl_paren(s) : s, "")
    end

    # --- product --------------------------------------------------------------
    if op === (*)
        coeff = Rational{BigInt}(1)
        rest = Any[]
        for a in args
            c = _cl_rational(a)
            c === nothing ? push!(rest, a) : (coeff *= c)
        end
        neg = _cl_isneg(coeff)
        coeff = abs(coeff)
        p, q = numerator(coeff), denominator(coeff)

        if isempty(rest)                       # a pure number after all
            return q == 1 ? (neg, string(p), "") : (neg, string(p), string(q))
        end

        factors = join((_cl_render(a, _PREC_PROD) for a in rest), " ")
        num = p == 1 ? factors : "$p $factors"
        # THE fix for symptom 1: one fraction, numerator carrying the factors.
        return q == 1 ? (neg, num, "") : (neg, num, string(q))
    end

    # --- division -------------------------------------------------------------
    if op === (/)
        nu, de = args[1], args[2]
        rn = _cl_rational(nu)
        if rn !== nothing
            # THE fix for symptom 2: (1//3)/(x+2) becomes \frac{1}{3(x+2)}, not a
            # fraction stacked on a fraction.
            neg = _cl_isneg(rn)
            rn = abs(rn)
            p, q = numerator(rn), denominator(rn)
            # `\frac{}{}` already groups, so a lone denominator needs no brackets. Once
            # the rational's own denominator multiplies it, it does: `\frac{1}{3 x - 1}`
            # would be a different expression from `\frac{1}{3(x - 1)}`.
            den = q == 1 ? _cl_render(de, _PREC_SUM) : "$q $(_cl_render(de, _PREC_PROD))"
            return (neg, string(p), den)
        end
        nneg, nbody = _cl_join(_cl_parts(nu, _PREC_SUM))
        return (nneg, nbody, _cl_render(de, _PREC_SUM))
    end

    # --- power ----------------------------------------------------------------
    if op === (^)
        base, ex = args[1], args[2]
        e = _cl_number(ex)
        if e isa Rational && numerator(e) == 1 && denominator(e) == 2
            return (false, "\\sqrt{$(_cl_render(base, _PREC_SUM))}", "")
        end
        b = _cl_render(base, _PREC_POWER)
        return (false, "$b^{$(_cl_render(ex, _PREC_SUM))}", "")
    end

    # --- roots ----------------------------------------------------------------
    # `symbolic_solve` builds radicals from Symbolics' own `ssqrt`/`scbrt` rather than
    # `Base.sqrt`/`cbrt` -- they are the branch-safe versions -- so both spellings have
    # to be recognised. Missing `scbrt` sent every Cardano root to the fallback, which
    # is exactly the shape this function exists to fix.
    if op === sqrt || op === Symbolics.ssqrt
        return (false, "\\sqrt{$(_cl_render(args[1], _PREC_SUM))}", "")
    end
    if op === cbrt || op === Symbolics.scbrt
        return (false, "\\sqrt[3]{$(_cl_render(args[1], _PREC_SUM))}", "")
    end
    if op === log || op === Symbolics.slog
        return (false, "\\log\\left( $(_cl_render(args[1], _PREC_SUM)) \\right)", "")
    end

    # --- anything else --------------------------------------------------------
    (false, _cl_fallback(t), "")
end

# Fold a `(neg, num, den)` triple back into `(neg, body)`.
function _cl_join(p::Tuple{Bool, AbstractString, AbstractString})
    neg, num, den = p
    isempty(den) && return (neg, num)
    (neg, "\\frac{$num}{$den}")
end

_cl_signed(t, prec::Int = _PREC_SUM) = _cl_join(_cl_parts(t, prec))

# Render `t` with its sign folded back in, bracketing if the context needs it.
function _cl_render(t, prec::Int)
    neg, body = _cl_signed(t, prec)
    neg || return body
    prec >= _PREC_PROD ? _cl_paren("-" * body) : "-" * body
end

"""
    conventional_latex(ex) -> String

Typeset a symbolic expression the way a mathematics text writes it.

`Latexify` renders a `Symbolics` expression faithfully, and faithfully means printing the
canonical algebraic form rather than conventional notation. This walks the expression and
emits the LaTeX directly, fixing three things at once:

| | `latexify` | `conventional_latex` |
|:--|:--|:--|
| rational coefficient | `\\frac{2}{3} ~ \\pi` | `\\frac{2 \\pi}{3}` |
| rational numerator | `\\frac{\\frac{1}{3}}{2 + x}` | `\\frac{1}{3 (x + 2)}` |
| term order | `-1 + x` | `x - 1` |
| common denominator | `\\frac{\\sqrt{41}}{4} + \\frac{3}{4}` | `\\frac{3 + \\sqrt{41}}{4}` |

It also removes a genuine defect rather than an infelicity: a leading negative renders
with a space after the opening delimiter, and Pandoc will not open inline math on a
dollar-sign-then-space, so those cells appear on the page as a literal dollar followed by
raw LaTeX.

The result is the body of a math expression, with no delimiters, so a caller wraps it as
it needs -- inline, display, or as a cell of a table.

```julia
julia> @variables x;

julia> conventional_latex(x - 1)
"x - 1"

julia> conventional_latex((2//3) * Symbolics.Num(pi))
"\\\\frac{2 \\\\pi}{3}"
```

Sums are ordered by descending total degree, so the constant comes last, except that a
term which is nothing but a radical sorts last of all -- which is how `-b + \\sqrt{b^2-4c}`
and `3 + \\sqrt{41}` are conventionally written. The ordering is total, so a rebuild
renders a given expression identically; it will not quietly rearrange a published page.

When every term of a sum is a fraction over the *same* denominator they are written over
one bar, which is what turns the pieces above into the quadratic formula rather than two
fractions added together. Terms over *different* denominators are left alone -- otherwise
a partial-fraction decomposition, whose entire point is separate denominators, would be
recombined into the thing it was decomposed from.

Any expression shape this does not recognise is passed to `Latexify` unchanged, so an
unfamiliar function renders as it always did rather than failing.
"""
function conventional_latex(ex)
    t = Symbolics.value(ex)
    neg, body = _cl_signed(t, _PREC_SUM)
    neg ? "-" * body : body
end

conventional_latex(s::AbstractString) = s
