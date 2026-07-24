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
- **`docs/`**: minimal Documenter.jl site deploying to this repo's own `gh-pages` (see the `documenter-jl-conventions` skill when editing docs)

## Workflow

Follow the `phased-implementation-workflow` skill: branch per phase, PR when done, wait for CI + explicit approval, **squash-merge** (`gh pr merge --squash --delete-branch`). Small, explicitly-approved docs-only edits may go directly to `main`. The `knowledge-capture-conventions` skill governs where learnings go; plan documents live in the gitignored `_research/` folder (local-only, never commit).

## Versioning & Registry Stance

Not registered in Julia's General registry; no upstream PRs intended (0.x SemVer marks divergence, not release-readiness). Never add registry tooling (TagBot etc.). Upstream is the `upstream` git remote — pull improvements by **cherry-picking** specific commits, not merging wholesale (the rename + fresh UUID make full merges conflict-heavy by design).
