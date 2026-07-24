---
applyTo: '**'
---
# Project Ecosystem Context

## What This Repository Is

A **standalone personal fork** — deliberately NOT part of the Math & Tech Study Hub website ecosystem (no DrWatson, no cross-repo docs deployment to `math_tech_study`, no Linear-managed milestones). Its structure conventions come from upstream `CalculusWithJulia.jl`, not from the study-hub canonical templates.

## Lineage & Relationships

| Repo | Relationship |
|---|---|
| `jverzani/CalculusWithJulia.jl` | Upstream original (`upstream` remote). Cherry-pick improvements; never PR back |
| `FourMInfo/CalculusWithJuliaSquared.jl` | This repo (`origin`). Renamed from `CalculusWithJulia.jl`; GitHub auto-redirects the old URL |
| `CalculusWithJuliaNotes.jl` (local sibling clone) | The actual "Calculus with Julia" book (Quarto). Used as-is for study; a possible future port off SymPy is scoped in the local-only `_research/PHASE_D_NOTES.md` |
| `FourMInfo/Calculus` | The study-hub project that will consume this package |

**Identity**: package UUID is `f826098b-d57e-4440-b91e-2a05d35c24ae` — deliberately fresh, NOT upstream's (`a2e0e22d-…`), so both packages can coexist in one dependency graph. Consumers install by URL or dev-path since the package is unregistered:

```julia
] add https://github.com/FourMInfo/CalculusWithJuliaSquared.jl#main
# or: ] dev /Users/aron/Code/Study/Julia/Math/CalculusWithJuliaSquared.jl
```

## CI

One workflow, one job: current stable Julia (`'1'`) on `macos-latest`/aarch64 — deliberately minimal for a personal fork used on one machine. `Documentation.yml` builds and deploys Documenter docs to this repo's own `gh-pages` on push to `main`.

## Critical Constraints — Do NOT Do These

| Action | Why |
|---|---|
| Add a dependency without checking its resolved tree for Python bridges (`PyCall`/`PythonCall`/`SymPyPythonCall`/`Conda`) | Python-free is the repo's entire purpose |
| Re-add `SymPyCore`/`SymPy` in any form | See above — these always dispatch to a Python `sympy` install |
| Add registry tooling (TagBot, Registrator workflows) | Not registered, never will be without upstream author's blessing |
| Change the UUID back to upstream's | Breaks coexistence with upstream in a shared dependency graph |
| Expand the CI matrix (more OSes/versions/nightly) | Personal fork, one machine; also `macos-13` (Intel) runners have unusably long queues |
| Commit anything in `_research/` | Local-only plan documents, gitignored by convention |
| Merge upstream wholesale (`git merge upstream/master`) | Identity divergence makes it conflict-heavy; cherry-pick instead |
