# CalculusWithJuliaSquared.jl — local preview only

!!! warning "This page is a placeholder. It is not the published documentation."
    This site exists so a docstring can be checked for well-formedness before it goes
    anywhere. It is **never deployed** — `docs/make.jl` deliberately has no `deploydocs`,
    and there is no documentation workflow in `.github/workflows/`.

    **The published API reference lives in the `Calculus` docs:**
    [fourm.info/calculus/dev/API/CalculusWithJuliaSquared](https://fourm.info/calculus/dev/API/CalculusWithJuliaSquared/).
    `Calculus` `@reexport`s this package, so its helpers are what a reader actually calls;
    its `make.jl` renders the same docstrings with `@autodocs` and deploys them.

## Where to write what

Only **docstrings** travel between the two. They are compiled into the module, so
`@autodocs Modules = [CalculusWithJuliaSquared]` in `Calculus` reads them straight out of
the loaded package. A Markdown page like this one does **not** travel: Documenter builds
only from the `docs/src/` of the repo it is building, and has no directive for pulling a
page out of a dependency.

That splits the writing cleanly, and the split is worth keeping in mind before adding prose
anywhere:

| what | where it belongs | why |
|:--|:--|:--|
| how a function behaves | its **docstring** | reaches readers automatically |
| package-wide principles — the type piracy policy, how `Nemo` is loaded | the **module docstring** (see *Cautions*, below) | same: it travels |
| why this package is documented inside the `Calculus` docs at all | `Calculus/docs/src/API/CalculusWithJuliaSquared.md` | it is framing for a `Calculus` reader, and means nothing here |
| this notice | here | it is about the preview itself |

So: **nothing on this page needs to be duplicated into `Calculus`, and nothing in
`Calculus` needs to be duplicated here.** Prose that a reader must see goes in a docstring.

Two consequences worth knowing when a change seems not to have landed:

* A docstring edit reaches the published page only after it is **merged and pushed**, and
  after `Calculus/Project.toml` bumps its `[compat]` pin — `Calculus` resolves this package
  from its GitHub URL, not from a local path. The pin bump triggers the deploy by itself,
  since that workflow's path filter includes `Project.toml`.
* If the reference below looks out of date, the docs environment is probably stale.
  `julia --project=docs -e 'using Pkg; Pkg.resolve()'` re-points it at the working tree.

## Building and viewing this preview

```bash
julia --project=docs -e 'using Pkg; Pkg.instantiate()'
julia --project=docs docs/make.jl
julia --project=@liveserver -e 'using LiveServer; serve(dir="docs/build", port=8002)'
```

`docs/Project.toml` sources the package at `..`, so the preview always reflects the working
tree, uncommitted docstring edits included.

## About the package

A personal, pure-Julia fork of [CalculusWithJulia.jl](https://github.com/jverzani/CalculusWithJulia.jl),
carrying the study materials off `SymPy` and onto `Symbolics`. The ported notes are at
[CalculusWithJuliaSquaredNotes.jl](https://github.com/FourMInfo/CalculusWithJuliaSquaredNotes.jl),
rendered at [Calculus with Julia Squared](https://fourm.info/cwjsn/); the original notes, by
John Verzani, are at [calculuswithjulia.github.io](https://calculuswithjulia.github.io/).

This is a personal study fork, not a registered package, and several of its conveniences
change Julia's behaviour globally for the session — see **Cautions for anyone else using
this package** in the module docstring immediately below.

----

## Reference

Generated from the same docstrings the `Calculus` site publishes. The module docstring comes
first; the exported functions follow.

```@autodocs
Modules = [CalculusWithJuliaSquared]
```
