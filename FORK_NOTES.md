# Why CalculusWithJuliaSquared exists

[CalculusWithJulia.jl](https://github.com/jverzani/CalculusWithJulia.jl) is the support package behind John Verzani's excellent ["Calculus with Julia"](https://calculuswithjulia.github.io) notes — plot recipes, a `sign_chart` function, Riemann sums, a nicely-formatted `lim` display, vector calculus helpers, and a thin optional layer of symbolic-math convenience functions.

This fork exists for one reason: **to make that package fully pure-Julia**, with zero Python underneath, for personal study use. It's not registered anywhere, it's not a pull request waiting to happen upstream — it's a small, deliberate divergence, documented here so the reasoning isn't lost.

The book/notes content itself — the actual "Calculus with Julia" text, in [CalculusWithJuliaNotes.jl](https://github.com/jverzani/CalculusWithJuliaNotes.jl) — is untouched and used as-is. This fork only changes the small support package underneath it.

## The starting assumption, and why it was wrong

Going in, the assumption was: "pure Julia" means two things need replacing — the plotting backend and the symbolic math engine (SymPy).

The plotting half turned out not to exist as a problem. The package already plots entirely through [Plots.jl](https://github.com/JuliaPlots/Plots.jl) — GR, Plotly, whatever backend the user picks — with no `PyPlot`, `PyCall`, or `Conda` anywhere in the codebase. Nothing to do there.

The symbolic-math half was real, but much smaller than expected: the entire SymPy-dependent surface of this package was 12 lines, in one file, defining `gradient`/`divergence`/`curl` for `SymPy`-wrapped expressions. It was a *weak* dependency (a Julia package extension) — meaning it never even loaded unless a user separately brought in the SymPy package themselves. Still, "only loads if you ask for it" isn't the same as "never Python," and the goal was zero, not conditional.

## Phase A — cleaning up before changing anything

Before touching the actual dependency, the package got a pass to fix what was already broken or unused, on the theory that it's easier to see a real change against a clean baseline:

- **Two dead files deleted.** `src/sympy.jl` wasn't even loaded by the module — a leftover, six lines of duplicate logic against the *old* `SymPy.jl` package that no code path ever reached. `src/plot-recipes.jl` (380 lines) was fully superseded by the package extension that actually ships plotting today; its `include` was already commented out.
- **A whole test file was silently never running.** `test/package-test.jl` existed, had real assertions (vector calculus operators, higher-order derivatives, curve tests) — and was never `include`d by `test/runtests.jl`. It had been running zero times in CI. Wired in now, with the couple of duplicate assertions it shared with the main test file removed.
- **A test that was broken, not skipped.** The `lim()` display feature had a `@test_broken` masking the fact that the assertion underneath it (`out[end, 2]`) throws a `MethodError` — `Limit` was never actually an indexable/iterable type, despite a comment claiming otherwise. Replaced with real assertions on the underlying function values, the direction variants (`+`, `-`, `+-`), and the rendered display output.
- **A genuinely broken function, found by trying to un-skip its test.** `fubini()` — the multi-dimensional integration helper — called `quadgk(...)` from a package (`QuadGK`) that was never actually a dependency of this package at all. It had presumably never worked. Added `QuadGK` for real, exported `fubini`, and enabled its test.
- **CI cut down to reality.** The original matrix tested 2 Julia versions × 3 operating systems, plus a separate nightly workflow, plus `TagBot` (a bot that reacts to Julia package registry registration events). None of that applies to a personal fork that isn't registered anywhere and is only ever run on a Mac. CI is now a single job: current stable Julia, on Apple Silicon. `TagBot.yml` was deleted outright — not just because it was unused, but as a deliberate belt-and-suspenders move, since removing it entirely is a stronger guarantee than relying on it merely never being triggered.

## The rename — signalling the divergence

Before touching the actual SymPy dependency, the package and repo were renamed: `CalculusWithJulia` → **`CalculusWithJuliaSquared`**. The pun is deliberate — Julia, squared, meaning *only* Julia, nothing else underneath.

This wasn't just cosmetic. The package identity (its UUID in `Project.toml`) was also given a fresh, independent value rather than keeping the one inherited from upstream — since this fork is now a genuinely different, diverging package, sharing an identity with upstream would risk a real conflict if both were ever installed as dependencies somewhere. The GitHub repo itself was renamed too (GitHub keeps the old URL redirecting), and the local module, file names, and package extensions were all updated to match, so that the actual dependency-removal work landed against a name that wouldn't need touching again.

## Phase B — the actual dependency swap

This is the heart of it. The one remaining Python-touching piece — `gradient`, `divergence`, `curl` defined for symbolic expressions — was rebuilt on [Symbolics.jl](https://github.com/JuliaSymbolics/Symbolics.jl) instead.

Two things were worth being careful about here, and both turned out to matter:

**`SymPyCore` is not a Python-free stepping stone.** It might look like a lighter-weight alternative to `SymPy.jl`, but it's actually the shared backend-agnostic core that *both* `SymPy.jl` (via `PyCall`) and `SymPyPythonCall.jl` (via `PythonCall.jl`) sit on top of. A `SymPyCore.Sym` object doesn't compute anything by itself — it dispatches to a real, running Python `sympy` installation through one of those two bridges. Swapping to `SymPyCore` alone would have kept Python in the loop the moment anyone actually used a symbolic variable; it would only have moved which Julia package did the importing.

**Claims about a fast-moving package's capabilities need checking live, not assumed.** Partway through scoping this, a caveat got raised that Symbolics.jl's equation-solving and integration support were meaningfully weaker than SymPy's — sourced from the notes repo's own `alternatives/symbolics.qmd` documentation. That documentation turned out to be about a year old. Checked directly against the actually-installed current Symbolics.jl (v7.31.0) instead of trusting that doc or relying on training data: `Symbolics.gradient`/`Symbolics.jacobian` — the two functions this package actually needs — work exactly as required, and Symbolics has separately gained real polynomial equation-solving (`symbolic_solve`, backed by the pure-Julia `Nemo` package) since that documentation was written. Also worth noting: current Symbolics does expose a handful of `sympy_*`-prefixed fallback functions, but they're inert `MethodError`s unless a separate Python-bridge package is deliberately loaded alongside it — so ordinary use of Symbolics never touches Python, by construction, the same weak-dependency pattern this fork itself relies on.

The actual change:

- `Project.toml`: `SymPyCore` replaced by `Symbolics` as a weak dependency; version bumped `0.3.3` → `0.4.0` to mark the divergence (this isn't a claim of stability or registry-readiness — it's SemVer's `0.x` convention for "meaningfully changed, still evolving").
- The extension itself: `gradient`/`divergence`/`curl` reimplemented on `Symbolics.gradient`, `Symbolics.derivative`, and `Symbolics.jacobian`. The existing generic `curl(J::Matrix)` helper elsewhere in the package needed no changes at all — `Symbolics.jacobian` returns a plain `Matrix`, just like the old SymPy path did.
- Test coverage for this extension went from zero (neither the SymPy version nor an early Symbolics draft had any) to a real test file, checked against known answers (e.g. the curl of `[-y, x, 0]` should be `[0, 0, 2]`) before being written into the package at all.

## Phase C — filling in test coverage, and Symbolics becomes first-class

With the dependency swap done, the remaining work was closing test-coverage gaps that had been identified but deliberately deferred: `lim()` display edge cases, the untested `riemann()` integration methods, `sign_chart` edge cases, and a second orphaned test file.

**Wiring in the last orphaned test file surfaced two more real bugs**, the same way un-skipping `fubini()`'s test did in Phase A. `test/test-plots.jl` existed but — like `package-test.jl` before Phase A — was never actually run by the test suite. Making it run for the first time found:

- `trimplot()` called a `find_colors()` helper that doesn't exist anywhere in the codebase. It had presumably never worked. A stale `# use rangeclamp` comment sitting directly above the broken code was the tell — someone had started refactoring it to reuse the package's own working `rangeclamp` utility and never finished. Completed that refactor instead of resurrecting the missing helper.
- The test file itself called a `plot_parametric_curve` function that had been renamed to `plot_parametric` at some point, and separately passed a vector-valued function directly to Plots' generic `surface()` recipe (which expects a scalar `z = f(x,y)`) instead of the `xs, ys, zs` coordinate matrices it had already computed one line earlier and never used.
- A `plotly()` backend switch, justified by a `# surface and gr() don't mix` comment, turned out to be stale too — GR now renders this surface plot fine on its own. Verified that directly rather than assuming the comment was still accurate, so no new plotting dependency was needed. (Before ruling that out, `PlotlyBase.jl`'s and `PlotlyKaleido.jl`'s full dependency trees were checked in a throwaway sandbox anyway, on the theory that "Plotly" is a name every Python user also recognizes and it was worth confirming it wasn't secretly pulling one back in. It wasn't — `PlotlyBase` is pure Julia, and `PlotlyKaleido` depends on `Kaleido_jll`, a standalone precompiled binary artifact, not a Python wheel.)

**Test coverage added:** all 8 `riemann()` methods, checked against known convergence behavior (`left`/`right`/`mid`/`trapezoid`/`ct` converge quickly; the min/max-sampling `m̃`/`M̃` methods bound the integral rather than approximate it directly, so they converge much more slowly and needed a larger `n` and looser tolerance to test reliably). `sign_chart` edge cases: always-positive/always-negative functions with no sign change, multiple roots with no poles, and a pure pole (asymptote) with no actual root of `f`. `lim()` display edge cases: a genuinely divergent limit, confirming one-sided displays (`dir="+"`/`dir="-"`) correctly omit the other side's rows, and confirming the `n` keyword actually controls how many rows are shown.

**`Symbolics` promoted from a weak dependency to a hard, `@reexport`-ed one.** Through Phase B, `Symbolics` only loaded if a user separately did `using Symbolics` themselves — the same opt-in pattern the old `SymPyCore` extension used. But this fork's whole premise is that symbolic math *with Julia* is the default way of working here, not an optional extra, so that asymmetry didn't sit right. Now `using CalculusWithJuliaSquared` alone exposes `@variables` and the rest of Symbolics' interface directly — confirmed empirically that `Reexport.jl` re-exports the module name itself, not just its individual exported functions, so both the bare `@variables x` form and the qualified `Symbolics.gradient(...)` form work without a second import. Checked first that this couldn't silently break anything: none of `gradient`, `jacobian`, or `derivative` are actually exported by Symbolics, so there was no risk of colliding with this package's own same-named functions. The tradeoff accepted is real, though: Symbolics' roughly 40-second precompile is now paid every time, not just when opted into.

## What didn't change

The book content (`CalculusWithJuliaNotes.jl`) — deliberately untouched, used as-is. Reading through it, it's genuinely SymPy-heavy: roughly 76 of its 96 lesson files reference SymPy, concentrated in the derivatives and integrals chapters, and used for live computation (Taylor series, substitution, symbolic solving), not just display. Porting *that* to Symbolics would be a real, multi-week undertaking of its own — rewriting worked examples, not just swapping imports — and isn't something this fork is attempting.

## Status

The roadmap that motivated this fork is complete: zero Python dependencies remain, and the test-coverage gaps identified along the way have been closed. No further phases are currently planned — anything beyond this would be a fresh piece of work, not a continuation of a known punch list.

## Summary

| | Before | Now |
|---|---|---|
| Plotting | Pure Julia (Plots.jl) already | Unchanged |
| Symbolic math | `SymPyCore` weak dep → dispatches to Python `sympy` | `Symbolics.jl`, hard dependency, `@reexport`-ed |
| Package identity | Shared UUID with upstream | Own name (`CalculusWithJuliaSquared`), own UUID |
| Dead code | `sympy.jl`, `plot-recipes.jl` present, unreachable | Removed |
| Test suite | Two entire files (`package-test.jl`, `test-plots.jl`) never ran; `fubini()` and `trimplot()` both silently broken; a masked test failure; `riemann()`, `sign_chart`, and `lim()` only lightly tested | All wired in; both broken functions fixed; real assertions across `limits.jl`, all 8 `riemann()` methods, `sign_chart` edge cases |
| CI | 2 Julia versions × 3 OSes + nightly + registry-bot workflow | 1 job: current stable Julia, Apple Silicon |
