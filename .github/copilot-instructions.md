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

Follow the `phased-implementation-workflow` skill — it is the source of truth for branching, where PR boundaries fall, CI, and merge discipline; do not restate its rules here. The `knowledge-capture-conventions` skill governs where learnings go; plan documents live in the gitignored `_research/` folder (local-only, never commit).

## Versioning & Releases

Not registered in Julia's General registry; no upstream PRs intended (0.x SemVer marks divergence, not release-readiness). Never add registry tooling (TagBot etc.). Upstream is the `upstream` git remote — pull improvements by **cherry-picking** specific commits, not merging wholesale (the rename + fresh UUID make full merges conflict-heavy by design).

**After every version bump here, bump `[compat] CalculusWithJuliaSquared` in `Calculus`.**
Manifests are gitignored across these repos, so that bound is the *only* thing pinning a
version — and when it is too tight nothing errors. The resolver quietly keeps the old
release and the new API is simply absent. That is not hypothetical: `Calculus` sat on
`"0.5.0"` (i.e. `< 0.6.0`) from v0.6.0 through v0.7.0, so `symlim` and `tlim` were invisible
to `using Calculus` and missing from the published API docs, with no error anywhere and no
symptom beyond a function that "should exist" not existing.

Because each `0.x` minor is breaking in Julia's SemVer, the bound cannot be widened once to
cover the future — it needs the edit every time. Convenient side effect: `Project.toml` is
in the path filter that triggers `Calculus`'s docs deploy, so the same one-line bump both
fixes resolution and publishes the new docstrings.
