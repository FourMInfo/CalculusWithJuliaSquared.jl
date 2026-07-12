module CalculusWithJuliaSquaredSymbolicsExt

import CalculusWithJuliaSquared: gradient, divergence, curl
import Symbolics
import Symbolics: Num

gradient(ex::Num, vars::AbstractArray=collect(Symbolics.get_variables(ex))) =
    Symbolics.gradient(ex, collect(vars))

divergence(F::Vector{<:Num}, vars=collect(Symbolics.get_variables(F))) =
    sum(Symbolics.derivative.(F, vars))

curl(F::Vector{<:Num}, vars=collect(Symbolics.get_variables(F))) =
    curl(Symbolics.jacobian(F, vars))

end
