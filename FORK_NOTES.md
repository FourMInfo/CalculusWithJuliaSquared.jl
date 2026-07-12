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

## What didn't change

The book content (`CalculusWithJuliaNotes.jl`) — deliberately untouched, used as-is. Reading through it, it's genuinely SymPy-heavy: roughly 76 of its 96 lesson files reference SymPy, concentrated in the derivatives and integrals chapters, and used for live computation (Taylor series, substitution, symbolic solving), not just display. Porting *that* to Symbolics would be a real, multi-week undertaking of its own — rewriting worked examples, not just swapping imports — and isn't something this fork is attempting.

## What's left (planned, not yet done)

Test coverage is still thinner than it should be in a few spots: the `lim()` display logic beyond the basics now covered, the less-common `riemann()` integration methods (`"left"`, `"trapezoid"`, `"simpsons"`, `"ct"` are currently untested), `sign_chart` edge cases (multiple roots, discontinuities), and `test/test-plots.jl` — which, like `package-test.jl` before Phase A, is written but never actually wired into the test suite. There's also an open design question about whether `Symbolics` should be promoted from a weak, opt-in dependency to a hard one that's `@reexport`-ed (so `using CalculusWithJuliaSquared` alone would expose `@variables` and friends) — trading a real always-on precompile cost for better ergonomics, given this fork's whole point is making symbolic math with Julia the default way of working, not an optional extra.

## Summary

| | Before | Now |
|---|---|---|
| Plotting | Pure Julia (Plots.jl) already | Unchanged |
| Symbolic math | `SymPyCore` weak dep → dispatches to Python `sympy` | `Symbolics.jl` weak dep, genuinely pure Julia |
| Package identity | Shared UUID with upstream | Own name (`CalculusWithJuliaSquared`), own UUID |
| Dead code | `sympy.jl`, `plot-recipes.jl` present, unreachable | Removed |
| Test suite | An entire file (`package-test.jl`) never ran; `fubini()` silently broken; a masked test failure | Fixed, wired in, real assertions added |
| CI | 2 Julia versions × 3 OSes + nightly + registry-bot workflow | 1 job: current stable Julia, Apple Silicon |
