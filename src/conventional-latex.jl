## ---------------------------------------------------------------------------------
## Conventional mathematical typesetting for `Symbolics` expressions.
##
## `Latexify` renders a `Symbolics` expression faithfully -- which is the problem. It
## prints the tree, and the tree is in a canonical form chosen for algebra, not for
## reading. The artefacts that show up in the expressions these notes produce:
##
##   1. A rational coefficient stays a separate factor. `Symbolics` keeps a quotient as
##      a division term ONLY while its rational coefficient is exactly 1; any other
##      coefficient folds into a product, which `Latexify` writes as a fraction TIMES a
##      symbol:  2*pi/3  ->  \frac{2}{3} ~ \pi   where a text writes  \frac{2\pi}{3}.
##
##   2. A rational numerator nests: `partial_fractions` yields terms like (1//3)/(x+2),
##      rendered  \frac{\frac{1}{3}}{2 + x}  where a text writes  \frac{1}{3(x+2)}.
##
##   3. Terms and factors come out in storage order: `x - 1` renders as  -1 + x,
##      `a*x^2 + b*x + c` as  c + b ~ x + x^{2} ~ a.
##
##   4. A negative power is STORED as a power of a reciprocal -- `x^(-2)` and `(1/x)^2` are
##      one tree -- and a multi-character name is set in typewriter, as code: `\mathtt{x0}`.
##
## None of these can be fixed by rewriting the expression, and that is not a matter of
## trying harder: `(2//3)*pi`, `(2*pi)/3` and `Num(2)*pi/Num(3)` all construct the SAME
## tree -- `isequal` returns `true` -- because canonicalisation happens on construction.
## The tree is not wrong; it simply is not prose. So the conversion has to happen while
## emitting the LaTeX, which is what this file does: it walks the expression and writes
## the string itself rather than post-processing what `Latexify` produced.
##
## There is an uglier symptom that this also cures. A leading negative renders as
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

# ---------------------------------------------------------------------------------
# the session defaults
#
# Which letters are the variables, and which way a sum runs, cannot be read off the
# expression: `1 - x` and `-x + 1` are one tree, and so are a Taylor polynomial and any
# other polynomial. So both are settings, with a default taken from mathematical
# convention, overridable per call by keyword or for the whole session. The session form
# exists because a notebook cell's display cannot be handed a keyword.
# ---------------------------------------------------------------------------------

const _CL_DEFAULT_VARIABLES = Symbol[:n, :r, :t, :u, :v, :w, :x, :y, :z, :θ, :theta]
const _CL_ORDERS = (:descending, :ascending)
const _CL_FACTOR_ORDERS = (:roots, :degree)
const _CL_PF_POWERS = (:ascending, :descending)
const _CL_SETTINGS = Dict{Symbol, Any}()
const _CL_SETTINGS_LOCK = ReentrantLock()

_cl_name(v::Symbol) = v
_cl_name(v::AbstractString) = Symbol(v)
_cl_name(v) = Symbolics.getname(Symbolics.unwrap(v))

# A single variable is accepted as readily as a collection of them.
_cl_varnames(v::Union{Symbol, AbstractString, Symbolics.Num, _SU.BasicSymbolic}) = [_cl_name(v)]
_cl_varnames(vs) = Symbol[_cl_name(v) for v in vs]

function _cl_check_order(o)
    o in _CL_ORDERS ||
        throw(ArgumentError("`order` must be :descending or :ascending, got $(repr(o))"))
    o
end

function _cl_check_factor_order(o)
    o in _CL_FACTOR_ORDERS ||
        throw(ArgumentError("`factor_order` must be :roots or :degree, got $(repr(o))"))
    o
end

function _cl_check_pf_powers(o)
    o in _CL_PF_POWERS ||
        throw(ArgumentError("`partial_fraction_powers` must be :ascending or :descending, got $(repr(o))"))
    o
end

"""
    set_conventional_default(; variables, order, factor_order, partial_fraction_powers) -> NamedTuple

Change, for the rest of the session, the defaults [`conventional_latex`](@ref) uses -- and
therefore how every symbolic expression *displays*, since a notebook or document cell has
no way to pass a keyword to its own display.

  * `variables` -- the names treated as variables when ordering a sum. A collection of
    symbolic variables or `Symbol`s (`[s, θ]` or `[:s, :θ]`); it *replaces* the default set
    rather than adding to it.
  * `order` -- `:descending` (highest degree first, as a polynomial is written) or
    `:ascending` (lowest first, as a Taylor polynomial or power series is written).
  * `factor_order` -- `:roots` (linear factors by root, the default) or `:degree` (monic
    factors first); see [`conventional_latex`](@ref).
  * `partial_fraction_powers` -- `:ascending` (the default) or `:descending`.

Options not passed keep their current value, so two calls setting one option each combine,
as they do for `Latexify`'s own `set_default`. Returns the resulting defaults, as
[`get_conventional_default`](@ref) does. An unknown option or order throws an
`ArgumentError` and changes nothing.

This is global state for the session, shared by every package that displays a `Num`.

```julia
julia> @variables s k;

julia> set_conventional_default(; variables = [s]);

julia> conventional_latex(expand((s - k)^2))
"s^{2} - 2 k s + k^{2}"

julia> reset_conventional_default();
```
"""
function set_conventional_default(; kwargs...)
    new = Dict{Symbol, Any}()
    for (k, v) in kwargs                      # validate everything before changing anything
        if k === :variables
            new[:variables] = _cl_varnames(v)
        elseif k === :order
            new[:order] = _cl_check_order(v)
        elseif k === :factor_order
            new[:factor_order] = _cl_check_factor_order(v)
        elseif k === :partial_fraction_powers
            new[:partial_fraction_powers] = _cl_check_pf_powers(v)
        else
            throw(ArgumentError(
                "unknown option `$k`: `set_conventional_default` accepts `variables`, `order`, " *
                "`factor_order` and `partial_fraction_powers`"))
        end
    end
    lock(() -> merge!(_CL_SETTINGS, new), _CL_SETTINGS_LOCK)
    get_conventional_default()
end

"""
    get_conventional_default() -> NamedTuple

The defaults [`conventional_latex`](@ref) and symbolic display currently use, as
a `NamedTuple` with fields `variables`, `order`, `factor_order` and
`partial_fraction_powers`. Out of the box that is

```julia
(variables = [:n, :r, :t, :u, :v, :w, :x, :y, :z, :θ, :theta], order = :descending,
 factor_order = :roots, partial_fraction_powers = :ascending)
```

See [`set_conventional_default`](@ref) and [`reset_conventional_default`](@ref).
"""
get_conventional_default() = lock(_CL_SETTINGS_LOCK) do
    (variables               = copy(get(_CL_SETTINGS, :variables, _CL_DEFAULT_VARIABLES)),
     order                   = get(_CL_SETTINGS, :order, :descending),
     factor_order            = get(_CL_SETTINGS, :factor_order, :roots),
     partial_fraction_powers = get(_CL_SETTINGS, :partial_fraction_powers, :ascending))
end

"""
    reset_conventional_default() -> NamedTuple

Undo every [`set_conventional_default`](@ref), restoring the out-of-the-box defaults, and
return them.
"""
function reset_conventional_default()
    lock(() -> empty!(_CL_SETTINGS), _CL_SETTINGS_LOCK)
    get_conventional_default()
end

# What one call is rendering with: the defaults resolved against its keywords.
struct _CLContext
    variables::Set{Symbol}
    ascending::Bool
    factor_degree::Bool        # L3: `factor_order = :degree`
    pf_descending::Bool        # L6: `partial_fraction_powers = :descending`
end

# ---------------------------------------------------------------------------------
# leaves
# ---------------------------------------------------------------------------------

# The plain number behind a leaf, or `nothing` if this is not a numeric leaf. `Symbolics`
# stores an irrational constant as a CALL, `identity(π)` (measured, v7), so that wrapper is
# looked through -- without it `π` was a degree-1 term of unknown shape, and `a + π`
# rendered `\pi + a`.
function _cl_number(a)
    a isa Number && return a
    if _SU.iscall(a)
        (_SU.operation(a) === identity && length(_SU.arguments(a)) == 1) || return nothing
        return _cl_number(_SU.arguments(a)[1])
    end
    _SU.isconst(a) || return nothing
    v = Symbolics.value(a)
    v isa Number ? v : nothing
end

# Only integers and rationals are folded into fractions. A float is left alone (writing
# `\frac{0.5 x}{1}` helps nobody) and an irrational such as `π` is a factor, not a
# coefficient -- folding it would produce `\frac{\pi x}{1}`.
function _cl_rational(a)
    v = _cl_number(a)
    v isa Integer && return Rational{BigInt}(v)
    v isa Rational && return Rational{BigInt}(v)
    nothing
end

# The imaginary part of a purely imaginary constant, else `nothing`. `symbolic_solve`
# writes a quadratic's or `x^3 - 1`'s complex coefficients as `Complex{Rational}`, but
# Cardano's as `Complex{Float64}` (`0.0 + 0.5im`, measured), so both have to be handled.
function _cl_imaginary(a)
    v = _cl_number(a)
    (v isa Complex && iszero(real(v))) || return nothing
    imag(v)
end

_cl_isneg(r::Rational) = r < 0

# The name of a symbol, or of the array an indexed element belongs to; `nothing` otherwise.
function _cl_symname(t)
    if _SU.iscall(t)
        _SU.operation(t) === getindex || return nothing
        t = _SU.arguments(t)[1]
        _SU.iscall(t) && return nothing
    end
    _cl_number(t) === nothing || return nothing
    try
        Symbolics.getname(t)
    catch
        nothing
    end
end

_cl_isvariable(t, ctx) = (nm = _cl_symname(t)) !== nothing && nm in ctx.variables

# The index of an array element as a sortable key (`""` for anything else), so `xs[2]` and
# `xs[10]` order numerically. Without it every element of one array ties on its name alone
# -- the book replay found the Lagrange coefficients sorted by printed text instead.
function _cl_index_key(t)
    (_SU.iscall(t) && _SU.operation(t) === getindex) || return ""
    join((let v = _cl_number(i)
              v isa Integer ? lpad(string(v), 12, '0') : string(i)
          end for i in _SU.arguments(t)[2:end]), ",")
end

# ---------------------------------------------------------------------------------
# names
#
# `Latexify` sets every multi-character name in typewriter -- `\mathtt{x0}`, `\mathtt{theta}`
# -- which is how code looks, not mathematics. A name is split into a base and an optional
# subscript (after `_`, as Unicode subscript characters, or as trailing digits), and each
# piece is written as a text would: a spelled Greek name as the letter; a longer base in
# italic, because italic is what marks a quantity; a longer subscript upright, because a
# descriptive subscript is a label (`v_{\mathrm{max}}`), while a one-letter or numeric one
# stays italic (`f_{x}`, `x_{0}`). A name this cannot read is left to `Latexify`.
# ---------------------------------------------------------------------------------

const _CL_GREEK = Set(split(
    "alpha beta gamma delta epsilon varepsilon zeta eta theta vartheta iota kappa lambda mu " *
    "nu xi pi varpi rho varrho sigma varsigma tau upsilon phi varphi chi psi omega " *
    "Gamma Delta Theta Lambda Xi Pi Sigma Upsilon Phi Psi Omega"))

const _CL_UNICODE_SUB = Dict(
    '₀' => '0', '₁' => '1', '₂' => '2', '₃' => '3', '₄' => '4', '₅' => '5', '₆' => '6',
    '₇' => '7', '₈' => '8', '₉' => '9', 'ₐ' => 'a', 'ₑ' => 'e', 'ₒ' => 'o', 'ₓ' => 'x',
    'ₕ' => 'h', 'ₖ' => 'k', 'ₗ' => 'l', 'ₘ' => 'm', 'ₙ' => 'n', 'ₚ' => 'p', 'ₛ' => 's',
    'ₜ' => 't', 'ᵢ' => 'i', 'ⱼ' => 'j', 'ᵣ' => 'r', 'ᵤ' => 'u', 'ᵥ' => 'v')

function _cl_split_subscript(s::AbstractString)
    i = findfirst('_', s)
    if i !== nothing && i > firstindex(s) && i < lastindex(s)
        return s[firstindex(s):prevind(s, i)], s[nextind(s, i):end]
    end
    j, cs = lastindex(s), Char[]
    while j > firstindex(s) && haskey(_CL_UNICODE_SUB, s[j])
        pushfirst!(cs, _CL_UNICODE_SUB[s[j]])
        j = prevind(s, j)
    end
    isempty(cs) || return s[firstindex(s):j], String(cs)
    m = match(r"^(.*[^0-9])([0-9]+)$", s)
    m === nothing || return String(m[1]), String(m[2])
    s, nothing
end

# One piece of a name: a base (`sub = false`) or a subscript (`sub = true`).
function _cl_name_piece(s::AbstractString, sub::Bool)
    s in _CL_GREEK && return "\\" * s
    all(isdigit, s) && return s
    if length(s) == 1
        isascii(s) && return s
        # a single Greek or other letter: Latexify already knows `θ` is `\theta`
        return _cl_fallback(Symbolics.unwrap(Symbolics.variable(Symbol(s))))
    end
    all(c -> isascii(c) && (isletter(c) || isdigit(c)), s) || return nothing
    sub ? "\\mathrm{$s}" : "\\mathit{$s}"
end

function _cl_symbol_latex(name::Symbol)
    base, sub = _cl_split_subscript(string(name))
    b = _cl_name_piece(base, false)
    b === nothing && return nothing
    sub === nothing && return b
    u = _cl_name_piece(sub, true)
    u === nothing ? nothing : "$(b)_{$(u)}"
end

# ---------------------------------------------------------------------------------
# ordering
# ---------------------------------------------------------------------------------

# Total degree, used to order the terms of a sum. It is a sort key rather than a rigorous
# degree, but it is RATIONAL rather than integer, because a radical halves the degree
# beneath it and that matters: `sqrt(41)` is a constant (degree 0), so it sorts alongside
# `3//4` rather than ahead of it, while `sqrt(b^2 - 4c)` is degree 1 and ties with `b`.
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
    1//1                                            # sin, log, an array element: degree 1
end

# The same, counting only the VARIABLE letters. This is what lets `a x^2 + b x + c` read
# as a polynomial in `x`: by total degree `a x^2` and `b x` and `c` are 3, 2, 1 -- right
# by luck -- but `x - b π` ties at 1 and the expanded `a (x - E)^2 + ...` sorts `a E^2`
# ahead of `a x^2`. A function of a variable counts as degree 1 in it.
function _cl_vdegree(t, ctx)::_CLDeg
    _cl_number(t) !== nothing && return 0//1
    if !_SU.iscall(t) || _SU.operation(t) === getindex
        return _cl_isvariable(t, ctx) ? 1//1 : 0//1
    end
    op, args = _SU.operation(t), _SU.arguments(t)
    op === (+) && return maximum(a -> _cl_vdegree(a, ctx), args; init = 0//1)
    op === (*) && return sum(a -> _cl_vdegree(a, ctx), args; init = 0//1)
    if op === (^)
        e = _cl_number(args[2])
        e isa Union{Integer, Rational} && return _cl_vdegree(args[1], ctx) * _CLDeg(e)
        return _cl_vdegree(args[1], ctx)
    end
    op === (/) && return _cl_vdegree(args[1], ctx) - _cl_vdegree(args[2], ctx)
    (op === sqrt || op === Symbolics.ssqrt) && return _cl_vdegree(args[1], ctx) // 2
    (op === cbrt || op === Symbolics.scbrt) && return _cl_vdegree(args[1], ctx) // 3
    any(a -> _cl_hasvariable(a, ctx), args) ? 1//1 : 0//1
end

_cl_hasvariable(t, ctx) = _cl_isvariable(t, ctx) ||
    (_SU.iscall(t) && _SU.operation(t) !== getindex &&
     any(a -> _cl_hasvariable(a, ctx), _SU.arguments(t)))

# A monomial's letters with their exponents, alphabetically (ignoring case). Comparing two
# of these is how equal-degree terms fall into alphabetical order: `k^2`, `k s`, `s^2`;
# `c`, `F`. The exponent is negated so that, letter for letter, the higher power leads.
function _cl_signature(t)
    if !_SU.iscall(t) || _SU.operation(t) === getindex
        nm = _cl_symname(t)
        nm === nothing && return ()
        return ((lowercase(string(nm)), string(nm) * "\0" * _cl_index_key(t), -1//1),)
    end
    op, args = _SU.operation(t), _SU.arguments(t)
    if op === (^)
        e, inner = _cl_number(args[2]), _cl_signature(args[1])
        (e isa Union{Integer, Rational} && length(inner) == 1) || return ()
        return ((inner[1][1], inner[1][2], inner[1][3] * _CLDeg(e)),)
    end
    if op === (*)
        sig = Tuple{String, String, _CLDeg}[]
        for a in args, s in _cl_signature(a)
            push!(sig, s)
        end
        return Tuple(sort!(sig; by = s -> (s[1], s[2])))
    end
    ()
end

# Does this term contain a radical or another non-arithmetic head? Used only to break a
# tie in the ordering: a text writes Cardano's root as `-q/2 + sqrt(...)`, putting the
# plain term before the radical, and both have total degree 1.
function _cl_hasradical(t)
    (_SU.iscall(t) && _cl_number(t) === nothing) || return false
    op, args = _SU.operation(t), _SU.arguments(t)
    op in (+, *, /, ^, getindex) || return true
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

# A term that is nothing but a radical (times a constant) sorts LAST, whatever its degree
# and whichever way the sum runs. That is the convention in every closed-form solution
# these notes print: `-b + sqrt(b^2 - 4c)`, `-q/2 + sqrt(q^2/4 + p^3/27)`, `3 + sqrt(41)`,
# and the imaginary part of `-1/2 + (sqrt(3)/2) i`. Requiring outer degree 0 is what keeps
# it from overreaching: `sqrt(2)*x + 1` is ordered by degree and stays `sqrt(2) x + 1`.
_cl_isradicalterm(t) = _cl_hasradical(t) && _cl_outer_degree(t) == 0

# The ordering key for the terms of a sum: radical-only terms last; then degree in the
# variables; then total degree; then alphabetical. It must be TOTAL, not merely a
# preference: `sort` is not guaranteed stable, so any two terms comparing equal could swap
# between one render and the next -- silently rewriting a published page on an unrelated
# rebuild. Measured happening on Cardano's roots. `string(t)` is the final tiebreak
# precisely because it can never tie.
function _cl_sortkey(a, ctx)
    s = ctx.ascending ? 1 : -1
    (_cl_isradicalterm(a), s * _cl_vdegree(a, ctx), s * _cl_degree(a), _cl_signature(a), string(a))
end

# The order functions take in a product, as a textbook writes them: `\sqrt{x} e^{x}
# \sin x \cos x \log x`. A head not listed sorts after these, alphabetically.
const _CL_HEAD_RANK = Dict{Any, Int}(
    sqrt => 0, Symbolics.ssqrt => 0, cbrt => 0, Symbolics.scbrt => 0, abs => 0,
    exp => 1,
    sin => 2, cos => 3, tan => 4, cot => 5, sec => 6, csc => 7,
    asin => 8, acos => 9, atan => 10, acot => 11, asec => 12, acsc => 13,
    sinh => 14, cosh => 15, tanh => 16, coth => 17, sech => 18, csch => 19,
    asinh => 20, acosh => 21, atanh => 22,
    log => 23, Symbolics.slog => 23, log2 => 24, log10 => 25)

const _CL_HEAD_UNRANKED = 50
# A derivative follows the functions it multiplies: `u(x) \frac{d v(x)}{dx}`, "u times the
# derivative of v".
const _CL_HEAD_DERIVATIVE = 60

# The ordering key for the factors of a product: numbers, constants, letters (the
# variables after the rest, each group alphabetically), bracketed sums, functions. Total,
# for the same reason as `_cl_sortkey`. Two calls of one head go simpler argument first,
# `\sin(x) \sin(2 x)`, measured by the length of the argument as printed.
function _cl_factor_key(a, ctx)
    # `1/u` and `(1/u)^n` in a denominator sort as `u` would (L3)
    u = _cl_unit_reciprocal(a)
    u === nothing || return _cl_factor_key(u, ctx)
    if _SU.iscall(a) && _SU.operation(a) === (^)
        u = _cl_unit_reciprocal(_SU.arguments(a)[1])
        u === nothing || return _cl_factor_key(u, ctx)
    end
    s = string(a)
    v = _cl_number(a)
    v !== nothing && return (v isa Irrational ? 1 : 0, 0, "", "", s)
    if (!_SU.iscall(a) || _SU.operation(a) === getindex ||
        (_SU.operation(a) === (^) && _cl_symname(_SU.arguments(a)[1]) !== nothing))
        b = _SU.iscall(a) && _SU.operation(a) === (^) ? _SU.arguments(a)[1] : a
        nm = _cl_symname(b)
        if nm !== nothing
            return (2, nm in ctx.variables ? 1 : 0, lowercase(string(nm)),
                    string(nm) * "\0" * _cl_index_key(b), s)
        end
    end
    _SU.iscall(a) || return (4, _CL_HEAD_UNRANKED, "", "", s)
    isempty(Symbolics.get_variables(a)) && return (1, 0, "", "", s)   # `sqrt(2)`, `π^2`
    op, args = _SU.operation(a), _SU.arguments(a)
    f = op === (^) && _SU.iscall(args[1]) ? args[1] : a
    fop = _SU.operation(f)
    fop === (+) && return (3, _cl_sum_factor_key(f, ctx), "", "", s)
    rank = fop isa Symbolics.Differential ? _CL_HEAD_DERIVATIVE : get(_CL_HEAD_RANK, fop, _CL_HEAD_UNRANKED)
    argkey = join((lpad(length(string(x)), 4, '0') * string(x) for x in _SU.arguments(f)), "|")
    (4, rank, rank == _CL_HEAD_UNRANKED ? string(fop) : "", argkey, s)
end

# ---------------------------------------------------------------------------------
# Latexify's shape for a function, with our arguments in it
#
# Rather than keep a hand-written table of how every head is typeset -- `\sin\left(x\right)`,
# `e^{x}`, `\left|x\right|`, `\sin^{2}\left(x\right)` for a power of a trig function but
# `\left(\log\left(x\right)\right)^{2}` for a power of a log -- ask `Latexify` once per head,
# on placeholder arguments, and splice the arguments in, each typeset by the rules here.
# The shape then always matches `Latexify`'s own, including for heads added later.
#
# The template has to be read through `Num`, as the fallback is: `Latexify` renders a raw
# `BasicSymbolic` differently (measured: `\mathrm{sign}` against `sign`), and the two
# must agree.
# ---------------------------------------------------------------------------------

const _CL_TEMPLATES = Dict{Tuple{Any, Int, Bool}, Union{Nothing, String}}()
const _CL_TEMPLATES_LOCK = ReentrantLock()

_cl_marker(i) = "CLPLACEHOLDER" * ('A' + i - 1)
_cl_marker_latex(i) = "\\mathtt{" * _cl_marker(i) * "}"

# LaTeX's own operator commands; any other word-named function becomes `\operatorname`.
const _CL_LATEX_OPERATORS = Set(["max", "min", "sup", "inf", "gcd", "det", "deg", "dim",
                                 "exp", "ln", "lg", "arg", "ker", "hom", "lim"])

# `Latexify` leaves some function names as bare italic words (`sign\left( x \right)`, which
# reads as the product s·i·g·n) and sets others `\mathrm{arccot}`. Either way, an operator
# name is written upright with operator spacing.
function _cl_operator_names(s::AbstractString)
    m = match(r"^(?:\\math(?:rm|tt)\{([A-Za-z][A-Za-z0-9]*(?:\\_[A-Za-z0-9]+)*)\}|([A-Za-z][A-Za-z0-9]+))(?=\\left|\^|_)", s)
    m === nothing && return s
    w = something(m[1], m[2])
    (w in _CL_LATEX_OPERATORS ? "\\" * w : "\\operatorname{$w}") * s[length(m.match) + 1:end]
end

function _cl_make_template(op, nargs::Int, power::Bool)
    phs = [Symbolics.unwrap(Symbolics.variable(Symbol(_cl_marker(i)))) for i in 1:(nargs + power)]
    tv = try
        call = Symbolics.unwrap(op(phs[1:nargs]...))
        power ? Symbolics.unwrap(call^phs[end]) : call
    catch
        return nothing
    end
    # the call must still be the one asked for: arithmetic can canonicalise it away
    _SU.iscall(tv) || return nothing
    if power
        _SU.operation(tv) === (^) || return nothing
        base = _SU.arguments(tv)[1]
        (_SU.iscall(base) && isequal(_SU.operation(base), op)) || return nothing
    else
        isequal(_SU.operation(tv), op) || return nothing
    end
    s = _cl_fallback(tv)
    all(i -> count(_cl_marker_latex(i), s) == 1, 1:(nargs + power)) || return nothing
    _cl_operator_names(replace(s, " ~ " => " "))
end

function _cl_template(op, nargs::Int, power::Bool)
    lock(_CL_TEMPLATES_LOCK) do
        get!(() -> _cl_make_template(op, nargs, power), _CL_TEMPLATES, (op, nargs, power))
    end
end

# Splice the arguments into a template. An argument sitting inside a delimiter the template
# supplies -- `\left( `, `{`, `|`, `, ` -- needs no brackets of its own; anywhere else, a
# sum does.
function _cl_fill(tpl::AbstractString, args, ctx)
    s = tpl
    for (i, a) in enumerate(args)
        r = findfirst(_cl_marker_latex(i), s)
        before = s[firstindex(s):prevind(s, first(r))]
        grouped = any(p -> endswith(before, p), ("( ", "{", "|", ", ", "lfloor ", "lceil "))
        s = before * _cl_render(a, grouped ? _PREC_SUM : _PREC_PROD, ctx) * s[nextind(s, last(r)):end]
    end
    s
end

# `Latexify`'s own rendering of a subtree, with the display-math wrapper stripped. This
# is the escape hatch for every node shape not handled below.
function _cl_fallback(t)
    s = string(Latexify.latexify(Symbolics.Num(t)))
    s = replace(s, "\\begin{equation}" => "", "\\end{equation}" => "")
    s = replace(s, "π" => "\\pi")
    String(strip(s))
end

_cl_paren(s) = "\\left( " * s * " \\right)"

_cl_isroot(op) = op === sqrt || op === Symbolics.ssqrt || op === cbrt || op === Symbolics.scbrt

# ---------------------------------------------------------------------------------
# numbers
# ---------------------------------------------------------------------------------

function _cl_num_latex(r::Rational)
    d = denominator(r)
    n = numerator(r)
    d == 1 && return string(n)
    n < 0 ? "-\\frac{$(-n)}{$d}" : "\\frac{$n}{$d}"
end

_cl_real_latex(v) = v isa Union{Integer, Rational} ? _cl_num_latex(Rational{BigInt}(v)) : string(v)

# `i`, `2 i`, `\frac{1}{2} i` -- for a non-negative magnitude.
function _cl_imag_latex(m)
    isone(m) && return "i"
    _cl_real_latex(m) * " i"
end

# ---------------------------------------------------------------------------------
# powers
# ---------------------------------------------------------------------------------

# A base that needs no brackets under a superscript: a symbol, an indexed element, or a
# non-negative number with no denominator. Everything else is bracketed -- measured on
# v0.14.1, an unbracketed product base was wrong mathematics (`(a*x)^y` came out
# `x a^{y}`) and a power or exponential base was a double superscript TeX refuses.
function _cl_bare_base(b)
    v = _cl_number(b)
    if v !== nothing
        v isa Irrational && return true
        v isa Rational && return denominator(v) == 1 && v >= 0
        return v isa Real && v >= 0
    end
    _cl_symname(b) !== nothing
end

function _cl_pow_string(base, ex, ctx)
    if _SU.iscall(base)
        op, args = _SU.operation(base), _SU.arguments(base)
        if !(op in (+, *, /, ^, getindex)) && !_cl_isroot(op) && !(op isa Symbolics.Differential)
            # a function takes Latexify's shape for its power: `\sin^{2}\left( x \right)`
            tpl = _cl_template(op, length(args), true)
            tpl === nothing || return _cl_fill(tpl, [args..., ex], ctx)
        end
    end
    exs = _cl_render(ex, _PREC_SUM, ctx)
    _cl_bare_base(base) && return "$(_cl_render(base, _PREC_POWER, ctx))^{$exs}"
    "$(_cl_paren(_cl_render(base, _PREC_SUM, ctx)))^{$exs}"
end

# `1/u` -> `u`, else `nothing`. A negative power reaches the page in this shape.
function _cl_unit_reciprocal(a)
    (_SU.iscall(a) && _SU.operation(a) === (/)) || return nothing
    n = _cl_rational(_SU.arguments(a)[1])
    (n !== nothing && isone(n)) ? _SU.arguments(a)[2] : nothing
end

# If `a` is `1/u` or `(1/u)^n`, the denominator it contributes to a product; else `nothing`.
function _cl_denominator_factor(a, ctx)
    u = _cl_unit_reciprocal(a)
    u === nothing || return _cl_render(u, _PREC_PROD, ctx)
    if _SU.iscall(a) && _SU.operation(a) === (^)
        u = _cl_unit_reciprocal(_SU.arguments(a)[1])
        u === nothing || return _cl_pow_string(u, _SU.arguments(a)[2], ctx)
    end
    nothing
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
function _cl_parts(t, prec::Int, ctx)
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
        if v isa Complex
            # `abs` of a complex number is its MODULUS: taking it here, as v0.14.1 did,
            # printed `i` as `1.0` and `-1 + 2i` as `2.236...`. Split the parts instead.
            re, im = _cl_half(real(v)), _cl_half(imag(v))
            iszero(im) && return _cl_parts(re, prec, ctx)
            iszero(re) && return (im < 0, _cl_imag_latex(abs(im)), "")
            s = "$(_cl_real_latex(re)) $(im < 0 ? "-" : "+") $(_cl_imag_latex(abs(im)))"
            return (false, prec >= _PREC_PROD ? _cl_paren(s) : s, "")
        end
        return (v isa Real && v < 0, string(abs(v)), "")
    end

    # --- symbol ---------------------------------------------------------------
    if !_SU.iscall(t)
        nm = _cl_symname(t)
        s = nm === nothing ? nothing : _cl_symbol_latex(nm)
        return (false, s === nothing ? _cl_fallback(t) : s, "")
    end

    op, args = _SU.operation(t), _SU.arguments(t)

    # --- indexed element ------------------------------------------------------
    if op === getindex
        nm = _cl_symname(t)
        base = nm === nothing ? nothing : _cl_symbol_latex(nm)
        if base !== nothing && !occursin("_{", base)
            idx = join((_cl_render(i, _PREC_SUM, ctx) for i in args[2:end]), ",")
            return (false, "$(base)_{$(idx)}", "")
        end
        return (false, _cl_fallback(t), "")
    end

    # --- sum ------------------------------------------------------------------
    op === (+) && return _cl_sum_parts(t, prec, ctx)

    # --- product --------------------------------------------------------------
    if op === (*)
        neg, num, den, imaginary = _cl_product_parts(args, ctx)
        if imaginary
            # THE unit goes outside the fraction: `\frac{\sqrt{3}}{2} i`.
            body = isempty(den) ? (num == "1" ? "i" : "$num i") : "\\frac{$num}{$den} i"
            return (neg, body, "")
        end
        # THE fix for symptom 1: one fraction, numerator carrying the factors.
        return (neg, num, den)
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
            den = q == 1 ? _cl_render(de, _PREC_SUM, ctx) : "$q $(_cl_render(de, _PREC_PROD, ctx))"
            return (neg, string(p), den)
        end
        # L8 (v0.16.0): when BOTH halves lead with a minus -- judged by the highest-degree
        # term, so `1 - x` leads with `-x` -- negate both: `\frac{x - 1}{x + 1}`, not
        # `\frac{1 - x}{-x - 1}`. Only the string is negated; the tree is left alone.
        flip = _cl_leads_negative(nu, ctx) && _cl_leads_negative(de, ctx)
        # L2: a numerator whose every term is negative puts its minus in front.
        nneg, nnum, nden = _cl_is_sum(nu) ?
            _cl_sum_parts(nu, _PREC_SUM, ctx; negate = flip, front_minus = true) :
            _cl_flipped(_cl_parts(nu, _PREC_SUM, ctx), flip)
        isempty(nden) && return (nneg, nnum, _cl_render_signed(de, _PREC_SUM, ctx; negate = flip))
        # L1: a numerator that is itself over a number -- partial fractions store
        # `(-(1//25) + (2//25)*x) / (x^2 - x - 1)` -- merges that number into the outer
        # denominator, as the rational-numerator case above always has.
        return (nneg, nnum, "$nden $(_cl_render_signed(de, _PREC_PROD, ctx; negate = flip))")
    end

    # --- power ----------------------------------------------------------------
    if op === (^)
        base, ex = args[1], args[2]
        e = _cl_number(ex)
        if e isa Rational && numerator(e) == 1 && denominator(e) == 2
            return (false, "\\sqrt{$(_cl_render(base, _PREC_SUM, ctx))}", "")
        end
        # Symbolics stores `x^(-2)` as `(1/x)^2`; a text writes `\frac{1}{x^{2}}`.
        u = _cl_unit_reciprocal(base)
        u === nothing || return (false, "1", _cl_pow_string(u, ex, ctx))
        return (false, _cl_pow_string(base, ex, ctx), "")
    end

    # --- roots ----------------------------------------------------------------
    # `symbolic_solve` builds radicals from Symbolics' own `ssqrt`/`scbrt` rather than
    # `Base.sqrt`/`cbrt` -- they are the branch-safe versions -- so both spellings have
    # to be recognised. Missing `scbrt` sent every Cardano root to the fallback, which
    # is exactly the shape this function exists to fix.
    if op === sqrt || op === Symbolics.ssqrt
        return (false, "\\sqrt{$(_cl_render(args[1], _PREC_SUM, ctx))}", "")
    end
    if op === cbrt || op === Symbolics.scbrt
        return (false, "\\sqrt[3]{$(_cl_render(args[1], _PREC_SUM, ctx))}", "")
    end
    if op === log || op === Symbolics.slog
        return (false, "\\log\\left( $(_cl_render(args[1], _PREC_SUM, ctx)) \\right)", "")
    end

    # --- derivative ---------------------------------------------------------
    # Always the fraction form. `Latexify` switches between `\frac{d f}{dx}` and the operator
    # form `\frac{d}{dx} f` depending on the argument, and the operator form is ambiguous in
    # a product: `\frac{d}{dx} u(x) v(x)` reads as the derivative OF uv (caught by the book
    # replay, in the product-rule section). The `d` is italic, as US calculus texts -- and
    # this book's prose, throughout -- write it; Latexify's upright `\mathrm{d}` is the ISO
    # convention, which would also want an upright e and i.
    if op isa Symbolics.Differential
        n = op.order
        xv = _cl_render(Symbolics.unwrap(op.x), _PREC_SUM, ctx)
        num = isone(n) ? "d" : "d^{$n}"
        den = isone(n) ? "d$xv" : "d$(xv)^{$n}"
        return (false, "\\frac{$num $(_cl_render(args[1], _PREC_PROD, ctx))}{$den}", "")
    end

    # --- any other function: Latexify's shape, our arguments ------------------
    tpl = _cl_template(op, length(args), false)
    tpl === nothing || return (false, _cl_fill(tpl, args, ctx), "")

    # --- anything else --------------------------------------------------------
    (false, _cl_fallback(t), "")
end

# Fold a `(neg, num, den)` triple back into `(neg, body)`.
function _cl_join(p::Tuple{Bool, AbstractString, AbstractString})
    neg, num, den = p
    isempty(den) && return (neg, num)
    (neg, "\\frac{$num}{$den}")
end

_cl_signed(t, prec::Int, ctx) = _cl_join(_cl_parts(t, prec, ctx))

# Render `t` with its sign folded back in, bracketing if the context needs it.
function _cl_render(t, prec::Int, ctx)
    neg, body = _cl_signed(t, prec, ctx)
    neg || return body
    prec >= _PREC_PROD ? _cl_paren("-" * body) : "-" * body
end

# ---------------------------------------------------------------------------------
# sums, products and their signs (v0.16.0)
# ---------------------------------------------------------------------------------

_cl_is_sum(t) = _SU.iscall(t) && _SU.operation(t) === (+)
_cl_flipped(p, flip::Bool) = flip ? (!p[1], p[2], p[3]) : p

# L5: Cardano's complex coefficients arrive as floats (`0.0 + 0.5im`, measured). An exact
# half of one is shown as the fraction it stands for; any other float stays a float, and
# a REAL float is never touched (`0.5 x`, `cos(1.5707963267948966)` are what was computed).
_cl_half(v) = v isa AbstractFloat && isinteger(2v) && !isinteger(v) ? Rational{BigInt}(BigInt(2v), 2) : v

# `(negative, numerator, denominator, imaginary)` for the factors of a product, with the
# imaginary unit NOT yet written, so a sum can collect imaginary terms (L5).
function _cl_product_parts(args, ctx)
    coeff = Rational{BigInt}(1)
    imaginary = false
    rest, dens = Any[], Any[]
    for a in args
        c = _cl_rational(a)
        if c !== nothing
            coeff *= c
            continue
        end
        m = _cl_imaginary(a)
        if m !== nothing
            m = _cl_half(m)
            if m isa Union{Integer, Rational}
                coeff *= Rational{BigInt}(m)
            else                                      # a float stays a float
                m < 0 && (coeff = -coeff)
                isone(abs(m)) || push!(rest, abs(m))
            end
            imaginary && (coeff = -coeff)             # i * i
            imaginary = !imaginary
            continue
        end
        f = _cl_number(a)
        if f isa AbstractFloat && f < 0
            coeff = -coeff
            push!(rest, -f)
            continue
        end
        _cl_denominator_factor(a, ctx) === nothing ? push!(rest, a) : push!(dens, a)
    end
    neg = _cl_isneg(coeff)
    coeff = abs(coeff)
    p, q = numerator(coeff), denominator(coeff)

    # keys computed once each: an L3 key factors a polynomial, too dear to repeat per comparison
    rest = rest[sortperm([_cl_factor_key(a, ctx) for a in rest])]
    dens = dens[sortperm([_cl_factor_key(a, ctx) for a in dens])]
    factors = join((_cl_render(a, _PREC_PROD, ctx) for a in rest), " ")
    num = isempty(rest) ? string(p) : (isone(p) ? factors : "$p $factors")
    denparts = String[]
    isone(q) || push!(denparts, string(q))
    append!(denparts, (_cl_denominator_factor(a, ctx) for a in dens))
    (neg, num, join(denparts, " "), imaginary)
end

# A term's parts with its imaginary unit removed, or `nothing` if it is a real term.
function _cl_imag_term(a, ctx)
    m = _cl_imaginary(a)
    if m !== nothing
        m = _cl_half(m)
        return (m < 0, isone(abs(m)) ? "1" : _cl_real_latex(abs(m)), "")
    end
    (_SU.iscall(a) && _SU.operation(a) === (*)) || return nothing
    neg, num, den, imaginary = _cl_product_parts(_SU.arguments(a), ctx)
    imaginary ? (neg, num, den) : nothing
end

# The rational coefficients of `t` as a polynomial in its ONE variable, lowest power first;
# `nothing` for two symbols (`x - a`), a non-variable letter, or a non-rational coefficient.
function _cl_univariate_coeffs(t, ctx)
    vs = Symbolics.get_variables(t)
    length(vs) == 1 || return nothing
    v = only(vs)
    _cl_isvariable(v, ctx) || return nothing
    try
        _rational_coeffs(Symbolics.Num(t), Symbolics.Num(v))
    catch
        nothing
    end
end

# L3: where a bracketed sum goes among a product's factors. Lower degree first; under
# `factor_order = :degree`, monic before the rest; then a linear factor with rational
# coefficients by its root on the number line -- `(x + 3)(x + 1)(2x - 1)(x - 3)`, a sign
# chart's order; then anything else (a symbolic root) by its printed form. Until v0.16.0
# factors went by their stored text, an accident.
function _cl_sum_factor_key(f, ctx)
    cs = _cl_univariate_coeffs(f, ctx)
    deg = cs === nothing ? _cl_vdegree(f, ctx) : _CLDeg(length(cs) - 1)
    monic = cs !== nothing && isone(last(cs))
    root = cs !== nothing && length(cs) == 2 ? -cs[1] / cs[2] : nothing
    (deg, ctx.factor_degree && !monic ? 1 : 0, root === nothing ? 1 : 0,
     root === nothing ? Rational{BigInt}(0) : root, string(f))
end

# L6: the factor and power of a partial-fraction term -- a numerator over a power of one
# polynomial in one variable with rational coefficients -- else `nothing`.
function _cl_pf_base(d, ctx)
    if _SU.iscall(d) && _SU.operation(d) === (*)
        others = [a for a in _SU.arguments(d) if _cl_number(a) === nothing]
        length(others) == 1 || return nothing
        d = only(others)
    end
    base, pw = d, 1
    if _SU.iscall(d) && _SU.operation(d) === (^)
        e = _cl_number(_SU.arguments(d)[2])
        (e isa Integer && e > 0) || return nothing
        base, pw = _SU.arguments(d)[1], Int(e)
    end
    (_cl_is_sum(base) || _cl_isvariable(base, ctx)) || return nothing
    _cl_univariate_coeffs(base, ctx) === nothing && return nothing
    (base, pw)
end

function _cl_pf_factor(t, ctx)
    _SU.iscall(t) || return nothing
    op, args = _SU.operation(t), _SU.arguments(t)
    op === (/) && return _cl_pf_base(args[2], ctx)
    op === (*) || return nothing
    found = nothing
    for a in args
        u = _cl_unit_reciprocal(a)
        pw = 1
        if u === nothing && _SU.iscall(a) && _SU.operation(a) === (^)
            u = _cl_unit_reciprocal(_SU.arguments(a)[1])
            e = _cl_number(_SU.arguments(a)[2])
            (e isa Integer && e > 0) || (u = nothing)
            u === nothing || (pw = Int(e))
        end
        u === nothing && continue
        found === nothing || return nothing           # two denominators: not one term
        b = _cl_pf_base(u, ctx)
        b === nothing && return nothing
        found = (b[1], b[2] * pw)
    end
    found
end

# A sum's terms in display order, and whether they were grouped as partial fractions (L6).
# Grouping needs at least one term over a polynomial factor, so a Laurent polynomial
# (`x + 1 + \frac{1}{x}`) and a difference quotient (`\frac{1}{x + h} - \frac{1}{x}`, whose
# factor holds a second symbol) keep the degree order. The polynomial part leads.
function _cl_sorted_terms(t, ctx)
    terms = collect(_SU.arguments(t))
    terms = terms[sortperm([_cl_sortkey(a, ctx) for a in terms])]
    pfs = [_cl_pf_factor(a, ctx) for a in terms]
    any(p -> p !== nothing && _cl_is_sum(p[1]), pfs) || return (terms, false)
    idx = findall(!isnothing, pfs)
    s = ctx.pf_descending ? -1 : 1
    keys = [(_cl_sum_factor_key(pfs[i][1], ctx), s * pfs[i][2], i) for i in idx]
    poly = [terms[i] for i in eachindex(terms) if pfs[i] === nothing]
    (vcat(poly, terms[idx[sortperm(keys)]]), true)
end

# L8: does `t` lead with a minus? For a sum, the highest-degree term decides, whatever
# direction the sum is being written in.
function _cl_leads_negative(t, ctx)
    if _cl_is_sum(t)
        desc = _CLContext(ctx.variables, false, ctx.factor_degree, ctx.pf_descending)
        terms, _ = _cl_sorted_terms(t, desc)
        return _cl_parts(first(terms), _PREC_SUM, ctx)[1]
    end
    _cl_parts(t, _PREC_SUM, ctx)[1]
end

# Two terms, the first negative and the second not: swap, so the pair does not open with a
# minus.
_cl_no_leading_minus(parts) =
    length(parts) == 2 && parts[1][1] && !parts[2][1] ? parts[[2, 1]] : parts

function _cl_join_terms(parts)
    io = IOBuffer()
    n1, b1 = _cl_join(parts[1])
    print(io, n1 ? "-" : "", b1)
    for p in parts[2:end]
        n, b = _cl_join(p)
        print(io, n ? " - " : " + ", b)
    end
    String(take!(io))
end

# A sum's `(negative, numerator, denominator)`. `negate` flips every term (L8);
# `front_minus` lets an all-negative sum carry its minus outside (L2, numerators only).
function _cl_sum_parts(t, prec::Int, ctx; negate::Bool = false, front_minus::Bool = false)
    terms, grouped = _cl_sorted_terms(t, ctx)
    parts = [_cl_flipped(_cl_parts(a, _PREC_SUM, ctx), negate) for a in terms]

    # L5: two or more imaginary terms are written as ONE imaginary part after the real part,
    # `a + \left( b + c \right) i`, each part a sum as a text writes it, fractions kept apart.
    imag = [_cl_imag_term(a, ctx) for a in terms]
    if count(!isnothing, imag) >= 2
        re = [parts[i] for i in eachindex(terms) if imag[i] === nothing]
        im = [_cl_flipped(imag[i], negate) for i in eachindex(terms) if imag[i] !== nothing]
        inner = "\\left( " * _cl_join_terms(_cl_no_leading_minus(im)) * " \\right) i"
        s = isempty(re) ? inner : _cl_join_terms(_cl_no_leading_minus(re)) * " + " * inner
        return (false, prec >= _PREC_PROD ? _cl_paren(s) : s, "")
    end

    lead = false
    if front_minus && all(p -> p[1], parts)
        parts = [(false, p[2], p[3]) for p in parts]
        lead = true
    end

    # A sum of two terms does not open with a minus: `1 - x`, not `-x + 1`. Not when the
    # second term is radical-only and the first is not, which keeps a radical in its
    # conventional place last (`-b + \sqrt{...}`, and the real part of `a + b i` first); two
    # radicals do swap (L4). Not in a partial-fraction sum either, whose order is its
    # factors' (L6): `-\frac{1}{x - 1} + \frac{1}{x - 2}`.
    if !grouped && length(parts) == 2 && parts[1][1] && !parts[2][1] &&
       (!_cl_isradicalterm(terms[2]) || _cl_isradicalterm(terms[1]))
        parts = parts[[2, 1]]
    end

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
        return (lead, String(take!(io)), den1)
    end

    s = _cl_join_terms(parts)
    (lead, prec >= _PREC_PROD ? _cl_paren(s) : s, "")
end

# `_cl_render`, optionally with every term's sign flipped (L8).
function _cl_render_signed(t, prec::Int, ctx; negate::Bool = false)
    negate || return _cl_render(t, prec, ctx)
    p = _cl_is_sum(t) ? _cl_sum_parts(t, prec, ctx; negate = true) :
                        _cl_flipped(_cl_parts(t, prec, ctx), true)
    neg, body = _cl_join(p)
    neg || return body
    prec >= _PREC_PROD ? _cl_paren("-" * body) : "-" * body
end

"""
    conventional_latex(ex; variables, order, factor_order, partial_fraction_powers) -> String

Typeset a symbolic expression the way a mathematics text writes it.

`Latexify` renders a `Symbolics` expression faithfully, and faithfully means printing the
canonical algebraic form -- storage order, separate rational factors, names in typewriter --
rather than conventional notation. This walks the expression and emits the LaTeX directly.
It is also what every symbolic expression, and the solutions `symbolic_solve` returns, use
for **display** once this package is loaded, so the conventions below are what a reader sees.

The result is the body of a math expression, with no delimiters, so a caller wraps it as
it needs -- inline, display, or as a cell of a table.

```julia
julia> @variables x a b c;

julia> conventional_latex(a*x^2 + b*x + c)
"a x^{2} + b x + c"

julia> conventional_latex((2//3) * Symbolics.Num(pi))
"\\\\frac{2 \\\\pi}{3}"
```

# Fractions

| | `latexify` | `conventional_latex` |
|:--|:--|:--|
| rational coefficient | `\\frac{2}{3} ~ \\pi` | `\\frac{2 \\pi}{3}` |
| rational numerator | `\\frac{\\frac{1}{3}}{2 + x}` | `\\frac{1}{3 (x + 2)}` |
| common denominator | `\\frac{\\sqrt{41}}{4} + \\frac{3}{4}` | `\\frac{3 + \\sqrt{41}}{4}` |
| negative power | `\\left( \\frac{1}{x} \\right)^{2}` | `\\frac{1}{x^{2}}` |

When every term of a sum is a fraction over the *same* denominator they are written over
one bar, which is what turns the pieces of the quadratic formula into the formula rather
than two fractions added together. Terms over *different* denominators are left alone --
otherwise a partial-fraction decomposition, whose entire point is separate denominators,
would be recombined into the thing it was decomposed from.

`Symbolics` stores `x^(-2)` as `(1/x)^2` -- the two are one expression -- so a power of a
reciprocal is written as one fraction, `\\frac{1}{x^{2}}`, and a product containing one puts
it in the denominator: `a*x^(-2)` is `\\frac{a}{x^{2}}`.

A fraction never sits inside a numerator: a numerator over its own number merges that number
into the denominator, `\\frac{2 x - 1}{25 \\left( x^{2} - x - 1 \\right)}`. A numerator whose
every term is negative puts the minus in front, `-\\frac{x + 1}{x^{2} + 1}`; a sum over one
number, such as `\\frac{-b - \\sqrt{b^{2} - 4 c}}{2}`, is not a numerator and keeps its signs,
so the two roots of a quadratic still look alike. When *both* halves lead with a minus --
judged by the highest-degree term, so `1 - x` leads with `-x` -- both are negated:
`\\frac{x - 1}{x + 1}`, not `\\frac{1 - x}{-x - 1}`.

# The order of the terms of a sum

A sum is ordered by these keys, each deciding only between terms the ones before it tie:

1. **Degree in the variables**, highest first. The variables are, by default, the letters a
   text uses for them: `n r t u v w x y z θ` (`θ` also spelled `theta`). Every other name is
   a constant, and so is a *subscripted* name, whatever its letter -- `x0`, `x_0` and `x₀`
   are fixed values, like an expansion point or an initial condition.
2. **Total degree**, highest first.
3. **Alphabetical**, ignoring case, higher power first letter by letter: `k^{2} - 2 k s + s^{2}`.

So `a*x^2 + b*x + c` is `a x^{2} + b x + c` rather than being sorted by the degree of `a x^2`
as a whole, and `x - b*pi` is `x - \\pi b`.

Two exceptions follow convention rather than degree:

  * **A term that is nothing but a radical comes last**, whatever its degree:
    `\\frac{-b + \\sqrt{b^{2} - 4 c}}{2}`, `\\frac{3 + \\sqrt{41}}{4}`, and the imaginary part of
    a complex root. A radical multiplied by a variable is ordered normally: `\\sqrt{2} x + 1`.
  * **A sum of two terms does not open with a minus**: `1 - x`, `1 - x^{2}`, `100 - 16 t^{2}`,
    not `-x + 1`, and two radicals swap too: `\\sqrt{1 + \\frac{\\sqrt{2}}{2}} - \\sqrt{1 - \\frac{\\sqrt{2}}{2}}`.
    With three or more terms the order above stands: `-x^{2} + 2 x - 1`.

## Partial fractions

A sum with a term over a polynomial factor -- what [`partial_fractions`](@ref) returns -- is
written the way the decomposition is taught: the polynomial part first, then the fractions
grouped by factor, in the factor order of a product (below), each factor's powers rising:

`x - 4 + \\frac{40}{3 \\left( x + 3 \\right)} + \\frac{2}{3 \\left( x - 3 \\right)}` and
`-\\frac{2}{25 \\left( x - 3 \\right)} + \\frac{1}{5 \\left( x - 3 \\right)^{2}} + \\frac{2}{5 \\left( x - 3 \\right)^{3}} + \\frac{2 x - 1}{25 \\left( x^{2} - x - 1 \\right)}`.

Here the factor order wins over "two terms do not open with a minus", so the template
`\\frac{A}{x - 1} + \\frac{B}{x - 2}` reads `-\\frac{1}{x - 1} + \\frac{1}{x - 2}`. Only a factor
that is a polynomial in one variable with rational coefficients groups a sum, so a Laurent
polynomial, `x + 1 + \\frac{1}{x}`, and a difference quotient,
`\\frac{1}{x + h} - \\frac{1}{x}`, keep the order above.

The input form makes no difference: `1 - x` and `-x + 1` construct the same expression.

## Choosing the variables and the direction

The keywords override the session defaults for one call:

  * `variables` -- the names to treat as variables, replacing the default set. Symbolic
    variables or `Symbol`s. Use it when an expression's variable is not one of the default
    letters:

    ```julia
    julia> @variables s k;

    julia> conventional_latex(expand((s - k)^2))                     # no default variable
    "k^{2} - 2 k s + s^{2}"

    julia> conventional_latex(expand((s - k)^2); variables = [s])
    "s^{2} - 2 k s + k^{2}"
    ```

  * `order` -- `:descending` (the default, as a polynomial is written) or `:ascending`, as a
    Taylor polynomial or power series is written:

    ```julia
    julia> conventional_latex(Symbolics.taylor(exp(x), x, 0:3); order = :ascending)
    "1 + x + \\\\frac{x^{2}}{2} + \\\\frac{x^{3}}{6}"
    ```

  * `factor_order` -- how the bracketed sums of a product are ordered: `:roots` (the default)
    puts lower degree first and linear factors by their root on the number line, as a sign
    chart reads, `\\left( x + 3 \\right) \\left( x + 1 \\right) \\left( 2 x - 1 \\right) \\left( x - 3 \\right)`;
    `:degree` puts monic factors before the rest within a degree,
    `\\left( x + 3 \\right) \\left( x + 1 \\right) \\left( x - 3 \\right) \\left( 2 x - 1 \\right)`.

  * `partial_fraction_powers` -- `:ascending` (the default), `\\frac{A}{x - 3} + \\frac{B}{\\left( x - 3 \\right)^{2}}`,
    or `:descending`, highest power first, as a Laurent expansion is written.

To change any of these for *display* -- which cannot be passed a keyword -- use
[`set_conventional_default`](@ref); [`reset_conventional_default`](@ref) undoes it.

# The order of the factors of a product

Numbers, then constants (`\\pi`, `\\sqrt{2}`), then letters alphabetically with the variables
after the rest, then bracketed sums, then functions: `3 h x`, `2 \\pi x`, `a E^{2}`,
`2 x \\left( x - 1 \\right) \\left( x - 2 \\right)`, `x^{2} e^{x}`. Bracketed sums go by `factor_order`
(above): by default lower degree first, then a linear factor by its root on the number line,
`\\left( x + 1 \\right) \\left( x - 1 \\right) \\left( x^{2} + 1 \\right)`; a factor whose root is a letter,
`x - a`, follows the numeric ones. A power sorts by its base. Functions go in textbook
order -- radicals and absolute values, exponentials, `sin cos tan cot sec csc`, inverse
trigonometric, hyperbolic, logarithms, then any other alphabetically, and derivatives last --
so `2 \\sin x \\cos x`, `e^{x} \\sin x` and `u\\left( x \\right) \\frac{d v\\left( x \\right)}{dx}`.
The same function twice goes simpler argument first: `\\sin\\left( x \\right) \\sin\\left( 2 x \\right)`.
Elements of an array go by name, then index: `\\mathit{xs}_{0} \\mathit{xs}_{1}`.

# Powers

A power's base is bracketed unless it is a symbol or a non-negative number:
`\\left( a x \\right)^{y}`, `\\left( \\frac{x}{2} \\right)^{2}`, `\\left( e^{x} \\right)^{2}`,
`\\left( \\sqrt{x} \\right)^{3}`, but `x^{2}`, `2^{x}`, `\\pi^{x}`. A power of a trigonometric or
hyperbolic function is written on the name, `\\sin^{2}\\left( x \\right)`, as `Latexify` does.

# Functions and their arguments

A function is typeset in `Latexify`'s own shape for it -- `\\sin\\left( x \\right)`, `e^{x}`,
`\\left|x\\right|`, `\\log_{10}\\left( x \\right)` -- with its arguments typeset by all of the
rules here: `\\cos\\left( \\frac{\\pi x}{2} \\right)`, `e^{-\\frac{x^{2}}{2}}`. A function
`Latexify` names with a plain word is set upright as an operator, `\\operatorname{sign}`,
using LaTeX's own command where there is one: `\\max`, `\\min`. So is the placeholder for roots
`symbolic_solve` cannot find: `\\operatorname{roots\\_of}\\left( x^{5} - x + 1, x \\right)`. A derivative is always in
fraction form, `\\frac{d \\sin\\left( x \\right)}{dx}` or `\\frac{d^{2} f}{dx^{2}}`: the operator
form `\\frac{d}{dx} u v` would read as the derivative of the whole product. The `d` is italic,
as calculus texts write it, rather than `Latexify`'s upright `\\mathrm{d}`.

# Complex numbers

The real part first, the imaginary unit last: `-1 + 2 i`, `-\\frac{1}{2} + \\frac{\\sqrt{3}}{2} i`.
Two or more imaginary terms are written as one imaginary part, as Cardano's roots are:
`-\\frac{u}{2} - \\frac{v}{2} + \\left( \\frac{\\sqrt{3} u}{2} - \\frac{\\sqrt{3} v}{2} \\right) i`. `Symbolics`
computes Cardano's halves as the float `0.5`; an exact half in a complex coefficient is shown as
the fraction it stands for, while every other float, and every real one, stays a float.

# Names

A name longer than one character is split into a base and a subscript -- after an `_`, as
Unicode subscript characters, or as trailing digits -- and each piece is written as a text
would:

| declared | typeset |
|:--|:--|
| `x0`, `x_0`, `x₀` | `x_{0}` |
| `theta`, `θ` | `\\theta` |
| `rho_0`, `lambda1` | `\\rho_{0}`, `\\lambda_{1}` |
| `f_x`, `x_alpha` | `f_{x}`, `x_{\\alpha}` |
| `v_max` | `v_{\\mathrm{max}}` |
| `height` | `\\mathit{height}` |
| `xs[1]` | `\\mathit{xs}_{1}` |

A spelled Greek name becomes the letter. A longer base is italic, because italic marks a
quantity; a longer *subscript* is upright, because a descriptive subscript is a label, while
a one-letter or numeric subscript stays italic.

# Everything else

The ordering is total, so a rebuild renders a given expression identically; it will not
quietly rearrange a published page. A leading negative never follows a space, which Pandoc
would refuse to open as inline math. Any expression shape this does not recognise is passed
to `Latexify` unchanged, so an unfamiliar function renders as it always did rather than
failing. A string is returned as it is.
"""
function conventional_latex(ex; variables = nothing, order = nothing, factor_order = nothing,
                            partial_fraction_powers = nothing)
    d = get_conventional_default()
    ctx = _CLContext(Set{Symbol}(variables === nothing ? d.variables : _cl_varnames(variables)),
                     (order === nothing ? d.order : _cl_check_order(order)) === :ascending,
                     (factor_order === nothing ? d.factor_order :
                         _cl_check_factor_order(factor_order)) === :degree,
                     (partial_fraction_powers === nothing ? d.partial_fraction_powers :
                         _cl_check_pf_powers(partial_fraction_powers)) === :descending)
    t = Symbolics.value(ex)
    neg, body = _cl_signed(t, _PREC_SUM, ctx)
    neg ? "-" * body : body
end

conventional_latex(s::AbstractString; kwargs...) = s
