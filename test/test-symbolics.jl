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
