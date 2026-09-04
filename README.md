# CalculusWithJuliaSquared

[![CI](https://github.com/FourMInfo/CalculusWithJuliaSquared.jl/actions/workflows/ci.yml/badge.svg)](https://github.com/FourMInfo/CalculusWithJuliaSquared.jl/actions/workflows/ci.yml)

A personal, pure-Julia fork of [CalculusWithJulia.jl](https://github.com/jverzani/CalculusWithJulia.jl) — a `Julia` package providing conveniences for using `Julia` to address typical problems from the undergraduate calculus sequence.

This fork removes all Python dependencies (SymPy) from the package itself, in favor of `Symbolics.jl` (a pure-Julia symbolic math system), for personal study use. It is not registered in Julia's General registry and is not intended as a PR back upstream. See [FORK_NOTES.md](FORK_NOTES.md) for the full story of what changed and why.

The notes this package is written for are being ported chapter by chapter alongside it, and the ported book is published at [Calculus with Julia Squared](https://fourm.info/cwjsn/) (source: [CalculusWithJuliaSquaredNotes.jl](https://github.com/FourMInfo/CalculusWithJuliaSquaredNotes.jl)). The original, unmodified notes by John Verzani remain at [calculuswithjulia.github.io](https://calculuswithjulia.github.io), with their source in [CalculusWithJuliaNotes.jl](https://github.com/jverzani/CalculusWithJuliaNotes.jl/).

This package's API reference is published as part of the [Calculus documentation](https://fourm.info/calculus/dev/API/CalculusWithJuliaSquared/), generated from its own docstrings — this repository does not build or deploy a documentation site of its own.

## Installing

Not registered — install directly from this repo:

```julia
] add https://github.com/FourMInfo/CalculusWithJuliaSquared.jl#main
# or, for local editable development:
] dev /path/to/local/clone/of/CalculusWithJuliaSquared.jl
```

## Cautions

Several of this package's conveniences change `Julia`'s behaviour **globally for the whole session**, not only for calls into the package. Three of them are [type piracy](https://docs.julialang.org/en/v1/manual/style-guide/index.html#Avoid-type-piracy-1) — `f'` for derivatives, display math for symbolic expressions and solution sets, and symbolic input to `find_zero` — and loading the package also switches on `Symbolics.symbolic_solve`, reexports six packages, and configures the plotting backend. None of it is accidental, but you should know before you build on it.

The full list, with the reasoning for each, is in the module docstring — `?CalculusWithJuliaSquared` at the REPL, or published as part of the [Calculus API reference](https://fourm.info/calculus/dev/API/CalculusWithJuliaSquared/), which is generated from this package's own docstrings.

## Contributing

This is a personal fork for individual study use, not an actively maintained public package. For the original, actively-maintained package, see [jverzani/CalculusWithJulia.jl](https://github.com/jverzani/CalculusWithJulia.jl).
