---
applyTo: 'test/**'
---
# Testing Conventions

## Every Test File Must Be Wired In

`Pkg.test()` runs only `test/runtests.jl`. Any new test file must be `include`d from it — this repo's history is the cautionary tale: two test files (`package-test.jl`, `test-plots.jl`) sat orphaned for years upstream, and wiring them in surfaced two functions that had **never worked** (`fubini()` calling an undeclared dependency; `trimplot()` calling a nonexistent helper). See the `julia-coding-conventions` skill, "Test-Suite Wiring Check".

## Real Assertions, Not Smoke Tests

Test against known mathematical answers, not just "doesn't throw":

```julia
# ✅ known-answer assertion
c = curl([-y, x, 0*z], [x, y, z])
@test isequal(c[3], 2)

# ❌ smoke test (this style hid broken functions for years)
vectorfieldplot(V, xlims=(-2,2))
```

## Numerical Tolerances for `riemann()` Methods

Convergence rates differ by method — calibrated tolerances (verified empirically):

| Methods | n | atol |
|---|---|---|
| `left`, `right`, `mid`, `trapezoid`, `ct` | 1_000 | 1e-4 |
| `simpsons` (converges much faster) | 1_000 | 1e-6 |
| `m̃`, `M̃` (bound the integral, converge slowly) | 10_000 | 1e-3 |

## Plotting Tests

- GR is the only backend used — **no `plotly()` backend switching** (a stale upstream `# surface and gr() don't mix` comment was verified false; GR handles the 3D surface cases fine, and PlotlyBase would be a needless extra dependency).
- Plot calls in tests are exercised for errors; where feasible, assert on returned data/attributes rather than just calling.

## Test Dependencies

`test/Project.toml` is the authoritative test environment (not the root `[extras]`/`[targets]`, which linger from upstream). Add test-only deps there.

## Running

```bash
julia --project=. -e 'using Pkg; Pkg.test()'
```

CI runs the same on a single job (stable Julia, macOS/aarch64). If a Manifest is stale after dependency changes, `rm Manifest.toml && julia --project=. -e 'using Pkg; Pkg.instantiate()'` first.
