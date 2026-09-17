using CalculusWithJuliaSquared
using Test

# What a reader SEES (v0.16.0). A Quarto page typesets a value only if it has a `text/html`
# method -- `text/latex` does not beat `text/plain` -- so every assertion here is on
# `text/html`, the MIME a page actually uses. Measured failure that motivates the file:
# `poly_factors` and `exact_trig_values` were tested for values only, returned a
# `Vector{Num}`, and a published page showed `sqrt(3) / 2` for eight days.

const _HTML = MIME("text/html")
_html(v) = repr(_HTML, v)
_typeset(v) = showable(_HTML, v) && occursin("\\[", _html(v))
# the LaTeX between `\[ ` and ` \]`
function _body(v)
    m = match(r"\\\[ (.*) \\\]"s, _html(v))
    m === nothing ? _html(v) : m.captures[1]
end
_owner(T) = which(show, (IO, MIME"text/latex", T)).module

@testset "display: vectors and matrices of expressions (v0.16.0)" begin

    @variables x y
    PI = Symbolics.Num(pi)

    # ---- the two functions that shipped untypeset ------------------------------------
    pf = poly_factors(x^2 - 3x + 2, x)
    @test pf isa Vector{Num}
    @test _typeset(pf)
    @test occursin("\\begin{array}{c}", _body(pf))
    @test occursin("x - 1", _body(pf)) && occursin("x - 2", _body(pf))

    tv = exact_trig_values.(cos.([0, PI/6, PI/4, PI/3, PI/2]))
    @test tv isa Vector{Num}
    @test _typeset(tv)
    @test occursin("\\frac{\\sqrt{3}}{2}", _body(tv))
    @test occursin("\\frac{\\sqrt{2}}{2}", _body(tv))
    @test occursin("\\frac{1}{2}", _body(tv))
    @test !occursin("sqrt(", _html(tv)) && !occursin("//", _html(tv))

    # a gradient typesets too -- v0.11.0 pinned the opposite, deliberately; reversed
    g = Symbolics.gradient(x^2 * y, [x, y])
    @test _typeset(g)
    @test occursin("2 x y", _body(g)) && occursin("x^{2}", _body(g))

    # `@variables` returns a `Vector{Num}`, so an echoed declaration is a column now; the
    # book's three echo cells end with `;` for that reason
    @test (@variables p q) isa Vector{Num}
    @test _typeset(@variables p q)

    # ---- matrices (decided 2026-09-17: why wait) --------------------------------------
    J = Symbolics.jacobian([x^2 * y, x + y], [x, y])
    @test J isa Matrix{Num}
    @test _typeset(J)
    @test occursin("\\begin{array}{cc}", _body(J))
    @test occursin("2 x y & x^{2}", _body(J))
    @test _typeset(Symbolics.hessian(x^2 * y, [x, y]))

    # ---- negative space ---------------------------------------------------------------
    @test !showable(_HTML, [1, 2])
    @test !showable(_HTML, [1.0, 2.5])
    @test !showable(_HTML, fill(x, 2, 2, 2))            # 3-D: not until one can reach a page
    # a symbolic ARRAY VARIABLE is a declaration, not a result: `Arr{Num,1} <: AbstractVector
    # {<:Num}`, so dispatching on the abstract type would print `zs` as a column of entries
    @variables zs[1:3]
    @test !showable(_HTML, zs)
    @test !showable(_HTML, @variables a zs2[1:3])      # a mixed declaration is a Vector{Any}
    @test _typeset(Num[])                               # empty, but still well-formed

    # Symbolics owns `text/latex` for these types; this package adds `text/html` only
    @test _owner(Vector{Num}) !== CalculusWithJuliaSquared
    @test _owner(Matrix{Num}) !== CalculusWithJuliaSquared

end

@testset "display: tuples holding an expression (v0.16.0)" begin

    @variables x a b c

    # ---- the published shapes ---------------------------------------------------------
    @test _body(divrem(x^2 - 1, x + 3)) == "\\left( x - 3,\\ 8 \\right)"
    t = (substitute(a*x^2 + b*x + c, Dict(x => 2)), 21)
    @test _body(t) == "\\left( 4 a + 2 b + c,\\ 21 \\right)"
    PI = Symbolics.Num(pi)
    @test _body((substitute(cos(x), Dict(x => PI/2)), substitute(cos(x), Dict(x => pi/2)))) ==
          "\\left( \\cos\\left( \\frac{\\pi}{2} \\right),\\ \\cos\\left( 1.5707963267948966 \\right) \\right)"

    # ---- elements that are not expressions --------------------------------------------
    @test _body((x^2, :cancel)) == "\\left( x^{2},\\ \\mathtt{:cancel} \\right)"
    @test _body((x + 1, true)) == "\\left( x + 1,\\ \\mathtt{true} \\right)"
    @test _body((x, :parameter_dependent)) == "\\left( x,\\ \\mathtt{:parameter\\_dependent} \\right)"
    @test _body(("two", x)) == "\\left( \\mathtt{\"two\"},\\ x \\right)"
    @test _body((x, nothing)) == "\\left( x,\\ \\mathtt{nothing} \\right)"
    @test _body((x, 1//2, 0.5, -Inf)) == "\\left( x,\\ \\frac{1}{2},\\ 0.5,\\ -\\infty \\right)"
    @test _typeset((Symbolics.value(x^2), 1))           # an unwrapped expression counts

    # ---- which tuples: a symbolic element in positions 1 to 16 ------------------------
    @test _typeset(ntuple(i -> i == 16 ? x : i, 16))
    @test !showable(_HTML, ntuple(i -> i == 17 ? x : i, 17))

    # ---- negative space: a tuple with nothing symbolic keeps Julia's display ----------
    for t in ((1, 2), (true, 1.0), (), (:green, :dash), (1, "two", :three))
        @test !showable(_HTML, t)
    end
    @test !showable(MIME("text/latex"), (x, 1))         # `text/html` only, deliberately

end

@testset "display: a single root taken from a solution set (v0.16.0)" begin

    @variables x
    rts = symbolic_solve(x^2 - 2 ~ 0, x)
    @test all(_typeset, rts)
    @test Set(_body.(rts)) == Set(["\\sqrt{2}", "-\\sqrt{2}"])
    @test _body(prod(x - r for r in rts)) == "\\left( x - \\sqrt{2} \\right) \\left( x + \\sqrt{2} \\right)"
    @test _typeset(rts)                                  # the vector still does, as before

    # `tlim` returns an unwrapped expression as well
    @test _typeset(tlim(sin(x)/x, x, 0))

    # a symbolic comparison is also a BasicSymbolic; it must display, not throw
    @test occursin("\\[", _html(Symbolics.value(x < 1)))

    @test _owner(typeof(rts[1])) !== CalculusWithJuliaSquared

end

@testset "display: symlim results (v0.16.0)" begin

    @variables x c h

    # ---- it still behaves as the tuple `(value, route)` --------------------------------
    r = symlim(sin(x)/x, x, 0)
    @test r == (1//1, :series)
    @test (1//1, :series) == r
    @test isequal(r, (1//1, :series)) && isequal((1//1, :series), r)
    @test r[1] == 1//1 && r[2] === :series
    v, route = r
    @test v == 1//1 && route === :series
    @test length(r) == 2 && first(r) == 1//1 && last(r) === :series
    @test Tuple(r) === (1//1, :series)
    @test hash(r) == hash((1//1, :series))
    @test repr(r) == "(1//1, :series)"
    @test repr(MIME("text/plain"), r) == "(1//1, :series)"

    # ---- and it typesets, whatever the value is (T4 B) --------------------------------
    @test _body(r) == "\\left( 1,\\ \\mathtt{:series} \\right)"
    @test _body(symlim(1/x, x, 0)) == "\\left( \\mathtt{nothing},\\ \\mathtt{:sides\\_disagree} \\right)"
    @test _body(symlim(c + 1/x^2, x, 0)) == "\\left( \\infty,\\ \\mathtt{:divergent\\_numeric} \\right)"
    @test _body(symlim(x^2 + 1 + log(abs(11x - 15))/99, x, 15//11)) ==
          "\\left( -\\infty,\\ \\mathtt{:divergent\\_numeric} \\right)"
    @test _body(symlim(x * sin(1/x), x, 0)) == "\\left( 0.0,\\ \\mathtt{:squeeze} \\right)"
    @test _body(symlim((x^2 - 2x + 2)/(4x^2 + 3x - 2), x, Inf)) ==
          "\\left( \\frac{1}{4},\\ \\mathtt{:reciprocal} \\right)"
    @test occursin("5 x^{4},\\ \\mathtt{:", _body(symlim(((x + h)^5 - x^5)/h, h, 0)))

    # two results side by side, as the `floor` example in `symlim`'s docstring shows them
    both = (symlim(floor(x), x, 0; side = :right), symlim(floor(x), x, 0; side = :left))
    @test _body(both) == "\\left( \\left( 0,\\ \\mathtt{:substitution} \\right),\\ " *
                         "\\left( -1,\\ \\mathtt{:squeeze} \\right) \\right)"

end

@testset "display contract: every exported function that returns symbolic output (v0.16.0)" begin

    @variables x y z
    M = CalculusWithJuliaSquared

    # A real call for every exported function whose result is mathematics a reader sees.
    symbolic = Dict{Symbol, Function}(
        :symlim            => () -> symlim(sin(x)/x, x, 0),
        :tlim              => () -> tlim(sin(x)/x, x, 0),
        :exact_trig_values => () -> exact_trig_values(cos(Symbolics.Num(pi)/6)),
        :factored_poly     => () -> factored_poly(x^2 - 1, x),
        :poly_factors      => () -> poly_factors(x^2 - 1, x),
        :partial_fractions => () -> partial_fractions(1/(x^2 - 1), x),
        :divergence        => () -> divergence([x*y, y^2], [x, y]),
        :curl              => () -> curl([x*y, y^2, x*z], [x, y, z]),
        :∇                 => () -> ∇(x^2 * y),
        :gradient          => () -> gradient(x^2 * y, [x, y]),   # a method on an imported name
        :combine_fractions => () -> combine_fractions(1/x + 1/y),
        :poly_rem          => () -> poly_rem(x^2 + 1, x - 1),
    )
    for (name, call) in symbolic
        @testset "$name" begin
            @test _typeset(call())
        end
    end

    # Everything else this package exports, with the reason it is not symbolic output.
    not_symbolic = Dict{Symbol, String}(
        :ForwardDiff => "module", :Nemo => "module", :PlotUtils => "module", :Plots => "module",
        :e => "a Float64", :endpoints => "numbers", :adapted_grid => "numbers",
        :unzip => "numeric arrays", :rangeclamp => "a function", :uvec => "a numeric vector",
        :lim => "a numeric table", :riemann => "a number", :fubini => "a number",
        :D => "a function", :tangent => "a callable line", :secant => "a callable line",
        :sign_chart => "a numeric sign chart", :SignChart => "a type",
        :numeric_roots => "floats", :root_enclosures => "certified balls",
        :conventional_latex => "LaTeX SOURCE, by design",
        :set_conventional_default => "settings", :get_conventional_default => "settings",
        :reset_conventional_default => "settings",
        (n => "a plot" for n in (:plotif, :plotif!, :trimplot, :trimplot!, :signchart, :signchart!,
            :plot_polar, :plot_polar!, :plot_parametric, :plot_parametric!, :arrow, :arrow!,
            :vectorfieldplot, :vectorfieldplot!, :vectorfieldplot3d, :vectorfieldplot3d!,
            :implicit_plot, :implicit_plot!, :newton_vis, :newton_plot!,
            :riemann_plot, :riemann_plot!))...,
    )

    # A new export must be classified here, so its display is a decision, not an accident.
    own = [n for n in names(M) if n !== nameof(M) && isdefined(M, n) && which(M, n) === M]
    unclassified = setdiff(own, keys(symbolic), keys(not_symbolic))
    @test isempty(unclassified)
    isempty(unclassified) || @info "exports with no display classification" unclassified
    stale = setdiff(union(keys(symbolic), keys(not_symbolic)), names(M))
    @test isempty(stale)

end
