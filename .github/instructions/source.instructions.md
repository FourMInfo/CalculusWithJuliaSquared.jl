---
applyTo: 'src/**'
---
# Source Code Conventions

## Where New Code Goes

| Kind of code | Location |
|---|---|
| Numeric/generic methods (derivatives, integration, limits, vector calculus) | The matching topic file: `src/derivatives.jl`, `src/integration.jl`, `src/limits.jl`, `src/multidimensional.jl` |
| Symbolic methods dispatching on `Symbolics.Num` | `src/symbolics.jl` |
| Plotting functions and recipes | `src/plots.jl` |
| Small plotting-adjacent helpers with no direct Plots calls (e.g. `rangeclamp`) | `src/plot-utils.jl` |

## Everything Is a Hard, Reexported Dependency (deliberate)

The main module `@reexport`s `Roots`, `LinearAlgebra`, `SpecialFunctions`, `IntervalSets`, `Symbolics`, and `Plots` — a single `using CalculusWithJuliaSquared` provides `@variables`, `fzero`, `plot`, and qualified access to every reexported module (see the `julia-coding-conventions` skill on `@reexport` passing module names through). Upstream used weak-dependency extensions to keep these opt-in for diverse users; this fork deliberately does not — it serves one user whose sessions always use symbolic math and plotting, so always-on precompile is cheaper than per-session imports. Don't reintroduce extension indirection.

## Adding Methods (the expected growth path)

As study progresses, new methods get added here rather than pulling in new packages reflexively. When a new dependency IS genuinely needed:

1. Sandbox-check its resolved dependency tree for Python bridges first (`julia-coding-conventions` skill, "Dependency-Tree Hygiene") — non-negotiable.
2. For symbolic capabilities, verify claims against the actually-installed current `Symbolics`/`Nemo`/`SymbolicNumericIntegration` before designing around them — this ecosystem moves fast and documentation lags (same skill, "Verifying Capability Claims").
3. Add proper `[compat]` bounds in `Project.toml`.

## Existing Patterns to Reuse

- **Generic helpers are shared across numeric and symbolic paths**: e.g. `curl(J::Matrix)` in `src/multidimensional.jl` works unchanged for both `ForwardDiff.jacobian` (numeric) and `Symbolics.jacobian` (returns plain `Matrix{Num}`) — extend this style rather than duplicating logic per path.
- **Upstream style**: this is mostly inherited code; match its comment density, naming, and docstring style rather than imposing new conventions.
- **Known type piracy**: `Base.adjoint(::Function)` is defined so `f'` means derivative — inherited from upstream, deliberate, documented. Don't "fix" it; don't add more piracy without discussion.

## Docstrings

Every exported function keeps a docstring (Documenter picks them up via `@autodocs` in `docs/src/index.md`). Follow upstream's docstring format; see the `documenter-jl-conventions` skill for LaTeX specifics when adding math notation.
