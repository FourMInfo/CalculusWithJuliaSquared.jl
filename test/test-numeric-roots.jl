using CalculusWithJuliaSquared
using Test

@testset "numeric_roots (v0.14.0)" begin

    @variables x s

    # ---- the cells this function exists for --------------------------------------
    # `precalc/polynomial_roots.qmd` calls `N.(solve(...))` on quintics, where
    # `symbolic_solve` can only answer `roots_of(...)`; and `sympy.real_roots` once.

    @test numeric_roots(x^2 - 2, x; real_only=true) ≈ [-sqrt(2), sqrt(2)]

    # EXACT equality, not `≈`. Converting an algebraic number straight to `Float64` loses
    # the last bit -- `Float64(qqbar)` gives 1.414213562373095 where `sqrt(2)` is
    # 1.4142135623730951 -- so the conversion routes through a high-precision ball. A
    # reader who compares a root against `sqrt(2)` must get `true`, not a puzzle. `≈` on
    # its own passes either way and would never have caught this.
    @test numeric_roots(x^2 - 2, x; real_only=true) == [-sqrt(2), sqrt(2)]
    @test numeric_roots(x^3 - 2, x; real_only=true) == [cbrt(2)]
    @test numeric_roots(x^2 - x - 1, x; real_only=true)[2] == (1 + sqrt(5))/2
    @test numeric_roots(x^2 + x + 1, x)[2] == (-1 + sqrt(3)*im)/2

    # A quintic with no formula in radicals: the whole reason this is not just
    # `Float64.(symbolic_solve(...))`.
    r = numeric_roots(x^5 - x - 1, x; real_only=true)
    @test length(r) == 1
    @test r[1] ≈ 1.1673039782614187
    # ...and it really is a root.
    @test abs(r[1]^5 - r[1] - 1) < 1e-12

    # ---- the ordering contract ---------------------------------------------------
    # Documented as stable so that a rendered document does not churn. Assert the
    # order, not merely the set.

    @test numeric_roots(x^3 - 6x^2 + 11x - 6, x; real_only=true) ≈ [1.0, 2.0, 3.0]
    @test issorted(numeric_roots((x-5)*(x+2)*(x-1), x; real_only=true))

    # Complex results sort by real part, then imaginary part.
    c = numeric_roots(x^2 + 1, x)
    @test c ≈ [-im, im]
    @test issorted(c; by = z -> (real(z), imag(z)))

    # ---- the multiplicity contract -----------------------------------------------
    # Documented: repeats repeat, so the count equals the degree. A `unique`d
    # implementation would pass every test above and fail these.

    @test length(numeric_roots((x-1)^2 * (x-2)^3, x)) == 5
    @test count(≈(1.0), real.(numeric_roots((x-1)^2 * (x-2)^3, x))) == 2
    @test count(≈(2.0), real.(numeric_roots((x-1)^2 * (x-2)^3, x))) == 3
    # degree == number of roots, for a polynomial with both real and complex roots
    @test length(numeric_roots(x^4 - 1, x)) == 4

    # ---- return types ------------------------------------------------------------

    @test numeric_roots(x^2 - 2, x; real_only=true) isa Vector{Float64}
    @test numeric_roots(x^2 - 2, x) isa Vector{ComplexF64}

    # ---- the negative space ------------------------------------------------------
    # `real_only` must actually drop the non-real roots, and must not drop real ones.

    @test length(numeric_roots(x^4 - 1, x; real_only=true)) == 2
    @test numeric_roots(x^4 - 1, x; real_only=true) ≈ [-1.0, 1.0]
    # a polynomial with NO real roots gives an empty vector rather than an error
    @test isempty(numeric_roots(x^2 + 1, x; real_only=true))

    # Refusals: a constant has no roots to list, and the zero polynomial has all of
    # them. `Nemo.roots` answers `[]` for both, which is wrong for the second.
    @test_throws ArgumentError numeric_roots(Symbolics.Num(5), x)
    @test_throws ArgumentError numeric_roots(0*x, x)

    # Float coefficients would make the exact algebra invent a precision never given.
    @test_throws ArgumentError numeric_roots(0.5x^2 - 1, x)

    # Two variables: which one is the indeterminate is not ours to guess.
    @test_throws ArgumentError numeric_roots(x^2 - s, x)

    # ---- boundaries --------------------------------------------------------------

    @test numeric_roots(2x - 1, x; real_only=true) ≈ [0.5]      # degree 1
    @test length(numeric_roots(x^7 - 1, x)) == 7                # only one real root
    @test length(numeric_roots(x^7 - 1, x; real_only=true)) == 1
end

@testset "root_enclosures (v0.14.0)" begin

    @variables x s

    # ---- the case this function exists for ---------------------------------------
    # `precalc/rational_functions.qmd` states in prose that `sympy.real_roots` is very
    # slow here and that `Polynomials.roots` reports the cluster as complex. The two
    # small roots sit 2 ulps apart in Float64.

    cluster = s^15 - 16129s^2 + 254s - 1

    e96 = root_enclosures(cluster, s; bits=96)
    @test length(e96) == 3
    # THE assertion: disjoint enclosures are the proof that these are two roots and
    # not one root computed twice. A merely-narrow interval would not establish it.
    @test !Nemo.overlaps(e96[1], e96[2])
    @test !Nemo.overlaps(e96[2], e96[3])

    # ---- `bits` is a real dial, not decoration -----------------------------------
    # At low precision the honest answer is "cannot separate these yet". The threshold
    # is the docstring's central claim, so pin BOTH sides of it: this cluster overlaps
    # at 53 bits -- exactly a Float64 mantissa, so double precision cannot resolve it
    # at all -- and separates at 64. If either of these flips, the docstring is wrong.

    @test Nemo.overlaps(root_enclosures(cluster, s; bits=53)[1],
                        root_enclosures(cluster, s; bits=53)[2])
    @test !Nemo.overlaps(root_enclosures(cluster, s; bits=64)[1],
                         root_enclosures(cluster, s; bits=64)[2])
    @test Nemo.overlaps(root_enclosures(cluster, s; bits=24)[1],
                        root_enclosures(cluster, s; bits=24)[2])

    # More bits must not mean a wider ball.
    @test Nemo.radius(root_enclosures(cluster, s; bits=128)[3]) <=
          Nemo.radius(root_enclosures(cluster, s; bits=32)[3])

    # ---- the enclosure really encloses -------------------------------------------

    encl = root_enclosures(x^2 - 2, x)
    @test length(encl) == 2
    # The claim is that the interval CONTAINS a root, so verify it the way the guarantee
    # is stated: evaluate the polynomial over the ball and check the result straddles 0.
    # Comparing midpoints to `sqrt(2)` would only test the midpoint, not the enclosure.
    @test Nemo.contains(encl[2]^2 - 2, 0)
    @test Nemo.contains(encl[1]^2 - 2, 0)
    @test Float64.(encl) ≈ [-sqrt(2), sqrt(2)]     # the documented escape hatch

    # ---- ordering and type -------------------------------------------------------

    @test encl isa Vector{Nemo.ArbFieldElem}
    @test issorted(Float64.(root_enclosures((x-5)*(x+2)*(x-1), x)))

    # ---- real roots only ---------------------------------------------------------
    # An Arb ball is real by construction, so the complex roots must be filtered out
    # rather than throwing (`ArbField(bits)(nonreal)` is a DomainError).

    @test length(root_enclosures(x^4 - 1, x)) == 2
    @test isempty(root_enclosures(x^2 + 1, x))

    # ---- the negative space ------------------------------------------------------

    @test_throws ArgumentError root_enclosures(x^2 - 2, x; bits=1)
    @test_throws ArgumentError root_enclosures(x^2 - 2, x; bits=0)
    @test_throws ArgumentError root_enclosures(Symbolics.Num(5), x)
    @test_throws ArgumentError root_enclosures(0*x, x)
    @test_throws ArgumentError root_enclosures(0.5x^2 - 1, x)
    @test_throws ArgumentError root_enclosures(x^2 - s, x)
end

@testset "divrem on polynomials -- piracy (v0.14.0)" begin

    @variables x y

    # ---- the cells this method exists for ----------------------------------------
    # `precalc/rational_functions.qmd` uses `divrem` three times; the chapter's prose
    # states these answers, so assert exactly them.

    q, r = divrem(5x^3 + 6x^2 + 2, x - 1)
    @test isequal(Symbolics.expand(q), Symbolics.expand(5x^2 + 11x + 11))
    @test isequal(r, 13)

    q, r = divrem((x-1)^2 * (x-2), (x+3)*(x-3))
    @test isequal(Symbolics.expand(q), Symbolics.expand(x - 4))
    @test isequal(Symbolics.expand(r), Symbolics.expand(14x - 38))

    # Exact rationals, not floats.
    q, r = divrem(x^5 - 2x^4 + 3x^3 - 4x^2 + 5, 5x^4 + 4x^3 + 3x^2 + 2x + 1)
    @test isequal(Symbolics.expand(q), Symbolics.expand((1//5)*x - 14//25))

    # ---- the defining identity ---------------------------------------------------
    # `a == b*q + r` is what makes this the division algorithm rather than a
    # plausible-looking pair of polynomials.

    for (a, b) in ((5x^3 + 6x^2 + 2, x - 1),
                   ((x-1)^2 * (x-2), (x+3)*(x-3)),
                   (x^5 - 1, x^2 + x + 1),
                   (x^2 + 1, x^3))                     # deg a < deg b
        q, r = divrem(a, b)
        @test isequal(Symbolics.expand(a - (b*q + r)), 0)
    end

    # ---- degree of the remainder -------------------------------------------------
    # Without this, `(q, r) = (0, a)` would satisfy the identity above for every input.

    q, r = divrem(x^5 - 1, x^2 + x + 1)
    @test Symbolics.degree(Symbolics.expand(r), x) < 2

    # Nothing to divide: quotient 0, remainder the numerator unchanged.
    q, r = divrem(x^2 + 1, x^3)
    @test isequal(q, 0)
    @test isequal(Symbolics.expand(r), Symbolics.expand(x^2 + 1))

    # ---- boundaries --------------------------------------------------------------

    q, r = divrem(x^2, Symbolics.Num(2))               # constant divisor
    @test isequal(Symbolics.expand(q), Symbolics.expand((1//2)*x^2))
    @test isequal(r, 0)

    q, r = divrem(x^2 - 1, x - 1)                      # exact division
    @test isequal(Symbolics.expand(q), Symbolics.expand(x + 1))
    @test isequal(r, 0)

    # ---- the negative space ------------------------------------------------------

    @test_throws DivideError divrem(x^2, 0*x)

    # Two variables, and no argument saying which is the indeterminate.
    @test_throws ArgumentError divrem(x^2 * y, x - 1)

    # Both constants: there is no polynomial variable to divide in.
    @test_throws ArgumentError divrem(Symbolics.Num(4), Symbolics.Num(2))

    # Still refuses non-rational coefficients, as the rest of the file does.
    @test_throws ArgumentError divrem(0.5x^2, x - 1)

    # ---- the piracy must not break integer `divrem` ------------------------------
    # The whole justification is that the generic function keeps working.

    @test divrem(7, 2) == (3, 1)
    @test divrem(7.5, 2) == (3.0, 1.5)
end
