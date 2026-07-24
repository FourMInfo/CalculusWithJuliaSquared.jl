# CalculusWithJuliaSquared

[![CI](https://github.com/FourMInfo/CalculusWithJuliaSquared.jl/actions/workflows/ci.yml/badge.svg)](https://github.com/FourMInfo/CalculusWithJuliaSquared.jl/actions/workflows/ci.yml)

A personal, pure-Julia fork of [CalculusWithJulia.jl](https://github.com/jverzani/CalculusWithJulia.jl) — a `Julia` package providing conveniences for using `Julia` to address typical problems from the undergraduate calculus sequence.

This fork removes all Python dependencies (SymPy) from the package itself, in favor of `Symbolics.jl` (a pure-Julia symbolic math system), for personal study use. It is not registered in Julia's General registry and is not intended as a PR back upstream. See [FORK_NOTES.md](FORK_NOTES.md) for the full story of what changed and why.

The accompanying notes ("Calculus with Julia") this package supports may be read at [calculuswithjulia.github.io](https://calculuswithjulia.github.io) — those notes and their source live in the separate, unmodified [CalculusWithJuliaNotes.jl](https://github.com/jverzani/CalculusWithJuliaNotes.jl/) repository.

## Installing

Not registered — install directly from this repo:

```julia
] add https://github.com/FourMInfo/CalculusWithJuliaSquared.jl#main
# or, for local editable development:
] dev /path/to/local/clone/of/CalculusWithJuliaSquared.jl
```

## Contributing

This is a personal fork for individual study use, not an actively maintained public package. For the original, actively-maintained package, see [jverzani/CalculusWithJulia.jl](https://github.com/jverzani/CalculusWithJulia.jl).
