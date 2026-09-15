# Copilot Instructions for CalculusWithJuliaSquared

> **Note:** Context-specific instructions (project ecosystem, source, testing) are in `.github/instructions/` and load automatically based on the file being edited.

## Project Overview

**A personal, pure-Julia fork of [CalculusWithJulia.jl](https://github.com/jverzani/CalculusWithJulia.jl)** — the support package behind the "Calculus with Julia" notes (plot recipes, `sign_chart`, Riemann sums, `lim` display, vector calculus helpers, symbolic gradient/divergence/curl). The fork exists to remove all Python dependencies (SymPy) in favor of `Symbolics.jl`, for personal study use. See [FORK_NOTES.md](../FORK_NOTES.md) for the full story.

## The Prime Directive: Python-Free

This package must have **zero Python anywhere in its dependency tree** — that is its entire reason for existing. Before adding any dependency, verify its full resolved dependency tree in a throwaway sandbox (see the `julia-coding-conventions` skill, "Dependency-Tree Hygiene"). Beware Julia-sounding packages that dispatch to Python underneath (`SymPyCore` is the canonical trap: it's the shared frontend for `SymPy.jl`/`SymPyPythonCall.jl` and always requires a Python `sympy` install).

## Core Architecture

- **`src/CalculusWithJuliaSquared.jl`**: main module — `@reexport`s `Roots`, `LinearAlgebra`, `SpecialFunctions`, `IntervalSets`, `Symbolics`, and `Plots` (all hard dependencies: one `using CalculusWithJuliaSquared` gives symbolic math, root finding, and plotting with nothing else to load); imports and exports `ForwardDiff`; defines `const e = exp(1)`
- **Topic files in `src/`**: `derivatives.jl`, `integration.jl`, `limits.jl`, `multidimensional.jl`, `plot-utils.jl`, `symbolics.jl` (symbolic `gradient`/`divergence`/`curl` for `Symbolics.Num`), `plots.jl` (all plotting functions and recipes)
- **No package extensions**: upstream kept `Plots` behind a weak-dependency extension to serve diverse users; this fork serves one user who always plots, so everything lives directly in `src/` (the `Symbolics` and `Plots` promotions happened in v0.4.0 and v0.5.0 respectively)
- **`docs/`**: minimal Documenter.jl site (see the `documenter-jl-conventions` skill when editing docs). **Its published home is the `Calculus` repo, not this one** — `Calculus/docs/make.jl` builds these docstrings via `modules=[Calculus, CalculusWithJuliaSquared]` into an `@autodocs` page at <https://fourm.info/calculus/dev/API/CalculusWithJuliaSquared/>. This repo's own `deploydocs` still writes to its `gh-pages`, which has no Pages site and which nothing serves — vestigial; see `_research/OPEN_QUESTIONS.md`. **So a docstring added here reaches the site only when `Calculus` redeploys, and only if `Calculus`'s `[compat]` bound admits the version containing it** — see *Versioning & Releases* below.

## Workflow

Follow the `phased-implementation-workflow` skill — it is the source of truth for branching, where PR boundaries fall, CI, and merge discipline; do not restate its rules here. Its companion `test-design-discipline` covers how to write tests that can actually fail, and the rule that **every API name appearing in prose must be executed** before it ships. The `knowledge-capture-conventions` skill governs where learnings go; plan documents live in the gitignored `_research/` folder (local-only, never commit).

## Versioning & Releases

Not registered in Julia's General registry; no upstream PRs intended (0.x SemVer marks divergence, not release-readiness). Never add registry tooling (TagBot etc.). Upstream is the `upstream` git remote — pull improvements by **cherry-picking** specific commits, not merging wholesale (the rename + fresh UUID make full merges conflict-heavy by design).

**Before merging a release whose change a published page could show, replay the book
against the branch.** Anything that reaches rendered output counts: `show`, `conventional_latex`,
a limit route, a value. Order: open the PR → re-render **every** published chapter of
`CalculusWithJuliaSquaredNotes.jl` against the branch while the PR is under review → push any
fix to the PR → merge on the go-ahead. Full, not scoped to the cells you reason are affected:
v0.15.0 changed the display of every symbolic cell, which only a full render shows. The
procedure (environment swap, render, cell-by-cell diff, restore) lives in that repo's
`.github/instructions/porting.instructions.md` → "Render the book against a CWJS branch while
its PR is open"; it runs from that repo's local `_research/scripts/`.

**After every version bump here, re-pin EVERY consumer — enumerated from disk, never from a
remembered list.** The set grows as book chapter groups are published (each carries its own
environment and pin), so a count written down goes stale. Find them with both:

```bash
# pinned consumers -- the ones to bump
/usr/bin/grep -rn 'CalculusWithJuliaSquared = "0\.' ~/Code/FourM/Study --include=Project.toml
# every environment depending on this package at all, pinned or not (this repo's own
# test/ and docs/ environments are sourced by path and are not consumers)
/usr/bin/grep -rln 'f826098b-d57e-4440-b91e-2a05d35c24ae' ~/Code/FourM/Study --include=Project.toml
```

An environment in the second list but not the first depends on this package with **no** pin,
and silently resolves whatever version it last saw. `/usr/bin/grep`, not `grep`: the shell's
`grep` is a `ugrep` wrapper that honours `.gitignore`. After bumping, `Pkg.update()` each
environment and read the resolved version back.

Manifests are gitignored across these repos, so a `[compat]` bound is the *only* thing pinning a
version — and when it is too tight nothing errors. The resolver quietly keeps the old
release and the new API is simply absent. That is not hypothetical: `Calculus` sat on
`"0.5.0"` (i.e. `< 0.6.0`) from v0.6.0 through v0.7.0, so `symlim` and `tlim` were invisible
to `using Calculus` and missing from the published API docs, with no error anywhere and no
symptom beyond a function that "should exist" not existing.

Bump it on **patch releases too**, and pin the exact version (`"0.8.1"`, not `"0.8"`).
A loose bound *admits* the new patch but does not *require* it: a fresh resolve picks the
newest and is fine, while an existing checkout keeps whatever its gitignored Manifest holds
and stays on the old patch indefinitely, with nothing forcing it forward. Pinning makes the
old version stop satisfying the bound, which is the only forcing function available here —
and a patch is exactly when it matters, since patches exist to fix regressions. (Each `0.x`
minor is breaking in Julia's SemVer anyway, so the bound can never be widened once to cover
the future.) Convenient side effect: `Project.toml` is
in the path filter that triggers `Calculus`'s docs deploy, so the same one-line bump both
fixes resolution and publishes the new docstrings.
