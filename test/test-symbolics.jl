using CalculusWithJuliaSquared
using Symbolics
using Test

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
