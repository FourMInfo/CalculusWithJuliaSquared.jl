# Run the `jldoctest` examples in CWJS's own docstrings, so a stale example fails this
# suite like any other test. Nothing else runs them: this package publishes no docs site,
# and Calculus (which embeds these docstrings) cannot load CWJS by name, so its docs build
# skips doctests (`doctest = false` there). Each example starts with its own `using`.

using Documenter

@testset "docstring examples (doctests)" begin
    Documenter.doctest(CalculusWithJuliaSquared; manual = false)
end
