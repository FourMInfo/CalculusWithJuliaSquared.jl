using CalculusWithJuliaSquared
using Test

@testset "Symbolics reexport" begin

    # `Symbolics` is a hard, reexported dependency -- `using CalculusWithJuliaSquared`
    # alone should expose both its exported macros/functions (e.g. `@variables`)
    # and, via Reexport.jl, the qualified `Symbolics.foo` form.
    @variables t
    @test isequal(Symbolics.derivative(t^2, t), 2t)

end

@testset "Symbolics extension" begin

    @variables x y z

    f = x^2 * y * z
    @test isequal(gradient(f, [x, y, z]), Symbolics.gradient(f, [x, y, z]))

    F₁ = [x, y, z]
    @test isequal(divergence(F₁, [x, y, z]), 3)

    F₂ = [-y, x, 0 * z]
    c = curl(F₂, [x, y, z])
    @test isequal(c[1], 0)
    @test isequal(c[2], 0)
    @test isequal(c[3], 2)

    # default `vars` argument (inferred via Symbolics.get_variables) should also work
    @test isequal(gradient(f), Symbolics.gradient(f, collect(Symbolics.get_variables(f))))

end

@testset "Nemo extension" begin

    # `symbolic_solve` on a polynomial needs Symbolics' Nemo extension, which is only
    # active once Nemo is loaded. This package imports it, so a plain
    # `using CalculusWithJuliaSquared` is enough -- no `using Nemo` downstream.
    @test Base.get_extension(Symbolics, :SymbolicsNemoExt) !== nothing
    @variables c::Real x::Real
    @test Symbolics.value.(symbolic_solve(c + 3 ~ 0, c)) == [-3]
    @test Symbolics.value.(symbolic_solve(2c + 3 ~ 0, c)) == [-3//2]
    @test length(symbolic_solve(x^2 - 2, x)) == 2

    # ...and it is an `import`, not a reexport: nothing of Nemo's leaks into the
    # namespace, where `derivative`, `coeff` and `roots` would collide with Symbolics.
    @test !isdefined(@__MODULE__, :ZZ)
    @test !isdefined(@__MODULE__, :QQ)
    @test :Nemo ∉ names(CalculusWithJuliaSquared)
    @test !isdefined(@__MODULE__, :derivative)          # Nemo exports one; Symbolics does not — neither may appear
    @test isequal(Symbolics.value(Symbolics.derivative(x^2, x)), Symbolics.value(2x))

end

@testset "Roots <-> Symbolics bridge (v0.11.0)" begin

    @variables x y

    # --- A. the cases this exists for: the notes' own calls -------------------------
    # `Roots` ships these for `SymPy` and not for `Symbolics`; without the bridge each
    # of them throws "is not callable".
    #
    # These match the values on the upstream published page exactly, which is the real
    # contract -- the ported chapter must reproduce them.
    @test find_zero(x^3 - x + 1, (-2, -1)) === -1.324717957244746
    @test find_zero(cos(x) ~ x, (0, 2))    === 0.7390851332151607

    # Against a hand-written function, compare with `≈`, NOT `==`. `build_function` emits
    # the expression in Symbolics' canonical order -- `x^5 - x^4 + x^3 - x^2 + 1` becomes
    # `1 + (-1 * x^2) + x^3 + (-1 * x^4) + x^5`, ascending, subtraction as `* -1` -- and
    # floating-point addition is not associative, so the two orders can differ by an ulp
    # near a root. Measured: the `find_zeros` case below differed by exactly 1 ulp. Both
    # are correct evaluations of the same polynomial; demanding bit equality across two
    # evaluation orders asserts something neither Roots nor Symbolics promises.
    @test find_zero(x^3 - x + 1, (-2, -1)) ≈ find_zero(u -> u^3 - u + 1, (-2, -1))
    @test find_zero(cos(x) ~ x, (0, 2))    ≈ find_zero(u -> cos(u) - u, (0, 2))

    # an equation with a constant side, as the arrow example writes it
    @test find_zero(x^2 - 4 ~ 0, (1, 3)) ≈ find_zero(u -> u^2 - 4, (1, 3))

    # --- B. the guarantee the chapter teaches must survive the bridge ---------------
    # `find_zero` promises an exact zero, or a sign change between adjacent floats.
    let r = find_zero(cos(x) ~ x, (0, 2)), f = u -> cos(u) - u
        @test sign(f(prevfloat(r))) != sign(f(nextfloat(r)))
    end

    # --- C. every other Roots entry point the notes use ----------------------------
    let zs = find_zeros(x^5 - x^4 + x^3 - x^2 + 1, (-10, 10)),
        ws = find_zeros(u -> u^5 - u^4 + u^3 - u^2 + 1, (-10, 10))
        @test length(zs) == length(ws)          # same zeros found, ...
        @test zs ≈ ws                           # ... to within the reordering above
        @test all(z -> abs(z^5 - z^4 + z^3 - z^2 + 1) < 1e-12, zs)   # and they ARE zeros
    end
    @test find_zero(x^3 - x + 1, (-2, -1), Roots.A42()) ≈
          find_zero(u -> u^3 - u + 1, (-2, -1), Roots.A42())
    # both sides symbolic here, so this one IS exact: it tests only that any `extrema`-able
    # container works as a bracket, which is what the chapter's prose claims.
    @test find_zero(x^3 - x + 1, [-2, -1]) === find_zero(x^3 - x + 1, (-2, -1))
    @test solve(ZeroProblem(x^5 - x - 1, (1, 2))) ≈ solve(ZeroProblem(u -> u^5 - u - 1, (1, 2)))

    # --- D. negative space: it must refuse, not guess -------------------------------
    # two free variables -- there is no single variable to solve for
    @test_throws ArgumentError find_zero(x^2 + y, (-2, 2))
    @test_throws ArgumentError find_zeros(x * y - 1, (-2, 2))
    @test_throws ArgumentError find_zero(x ~ y, (-2, 2))
    # no free variable at all
    @test_throws ArgumentError find_zero(Symbolics.Num(1), (-1, 1))

    # --- E. it must not disturb the ordinary numeric path ---------------------------
    @test find_zero(sin, (3, 4)) === Float64(pi)
    @test find_zeros(sin, (-4, 4)) == find_zeros(u -> sin(u), (-4, 4))
    @test fzero(sin, (3, 4)) === Float64(pi)          # the MATLAB-style alias still works

end

@testset "display of a solution set (v0.11.0)" begin

    @variables x y

    rs = symbolic_solve(x^2 - 4 ~ 0, x)
    html = repr(MIME("text/html"), rs)
    tex  = repr(MIME("text/latex"), rs)

    # display math, not the internal type name
    @test occursin("\\[", html) && occursin("\\]", html)
    @test occursin("\\[", tex)  && occursin("\\]", tex)
    @test !occursin("BasicSymbolic", html)
    @test !occursin("BasicSymbolic", tex)
    @test occursin("-2", html) && occursin("2", html)

    # deliberately NOT widened to `Vector{Num}`: that is what `Symbolics.gradient`
    # returns, and published chapters already render it the default way.
    @test !showable(MIME("text/html"), Symbolics.gradient(x^2 * y, [x, y]))

end
