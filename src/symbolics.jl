## symbolic gradient/divergence/curl via Symbolics.jl (a hard dependency, reexported)

gradient(ex::Symbolics.Num, vars::AbstractArray=collect(Symbolics.get_variables(ex))) =
    Symbolics.gradient(ex, collect(vars))

divergence(F::Vector{<:Symbolics.Num}, vars=collect(Symbolics.get_variables(F))) =
    sum(Symbolics.derivative.(F, vars))

curl(F::Vector{<:Symbolics.Num}, vars=collect(Symbolics.get_variables(F))) =
    curl(Symbolics.jacobian(F, vars))
