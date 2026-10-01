# Nonlinear continuous construction — Steps 12 and 13

`--problem=sr` now selects `(mkContinCtx ... nonlinear ...)` explicitly. Like the
C++ `polynomial_problem`, it overrides the affine search-mode default. Without
custom data it fits the order-two target `x + x*x`; CSV/in-memory input follows
the existing numeric loader. `--problem=linear` requires linear mode and retains
the affine builder. HC is still the default optimizer.

## Representation

The new modules are `representation/contin-nonlinear.metta` and
`representation/build-nonlinear.metta`. They feed the existing CTK builder,
field schema, finalizer, scorer, optimizers, and merge lifecycle. There is no
nonlinear-only optimizer or second scoring path.

From zero with labels `(x z)` and degree two, the plain scaffold is equivalent
to `b + a*x + c*z + d*(x*x) + e*(x*z) + f*(z*z)`, initially all coefficients zero.
It contains six coefficient knobs, hence twelve raw trit fields at depth two.
Products are generated as combinations with repetition in declared label order;
`x*z` and `z*x` are not separately generated.

An allowed function adds a zero-weighted basis per label. For example `c_sin`
adds `a*sin(x)`. With scaffold depth one, its argument gets its own polynomial
and function terms, enabling `sin(x + x*x)` and learned offsets/scales. Depth
decreases at each recursively expanded unary/division argument. Division starts
as `a*(x/1)` and can acquire a trainable numerator and denominator. Every numeric
constant becomes a CTK, including denominator constants. Zero weights lead the
product, so default inactive `log(x)` branches do not invalidate the zero seed.

Existing supported trees are preserved rather than distributed or re-associated.
The builder reduces the exemplar, retains existing term order and coefficients,
and adds missing basis slots with zero weights. Function arguments are rebuilt
recursively. All-STOP materialization restores the reduced exemplar. Each selected
deme starts with a fresh representation, population, and learned model: coordinate
indices are not transferred from an earlier scaffold.

| Parameter | Default | Meaning |
| --- | --- | --- |
| `continPolyDegree` | `2` | Degree 1–4 of newly generated monomials, including interactions |
| `continScaffoldDepth` | `1` | 0–2 levels of recursive argument scaffolding; 0 keeps new function arguments fixed |
| `continOperators` | `(c_add c_mul)` | Explicit allowlist; both are mandatory; optionally add `c_sin c_log c_exp c_div` |
| `continMaxScaffoldNodes` | `10000` | Conservative admission bound plus exact constructed-tree node cap; allowed 1–100000 |

The degree bound does not reject a higher-degree *existing* tree or bound the
degree of a composition. Depth controls newly introduced argument scaffolds,
not arbitrary user-supplied AST depth. Limits reject construction explicitly
(`NonlinearScaffoldLimit`), without silently dropping terms. The admission bound
can reject a function-rich exemplar even if a tighter count would fit. This is
a resource guard, not an optimizer stopping criterion; an unbuildable selected
exemplar currently terminates the run with a diagnostic. Increase the cap or
reduce degree/depth/vocabulary deliberately when this happens.

Vocabulary, input labels, finite constants, and arities are validated before
reduction, including inside inactive zero gates. Unknown/mixed-domain operators
cannot disappear through simplification and then enter search unnoticed.

## Reduction and C++ scope

The pinned reference is OpenCog commit
`f88ccd3279f3dd853e8c23103be5376a0e7eafc1`, especially `build_knobs.cc`
(`contin_canonize`, `rec_canonize`, `append_linear_combination`) and
`main/demo-problems.cc` (`polynomial_problem`). Its recursive coefficient
expansion warns about explosive polynomial growth. This implementation uses
bounded explicit monomials and recursive function arguments instead; it does
not reproduce every C++ scaffold or fraction-normal form.

Rules stay in `reduct/contin-reduct/`, organized by function. The new
`reduce-nonlinear.metta` folds identical nonleaf addends `t+t` into `2*t` without
distributing/re-associating other terms. Existing closed unary folds, identities,
safe division-by-power-of-two conversion and zero-prefix gates still apply.
The reducer deliberately preserves `log(exp(x))`, `exp(log(x))`, `x/x`, and
error-sensitive grouping. Arbitrary C++ sine/log/exp algebra, general fraction
normalization/distribution, mixed conditionals/impulses, and full search parity
remain out of scope. The existing stricter finite-intermediate contract remains.

`tests/fixtures/continuous/nonlinear-reference.json` records **source-derived**
C++ semantic goldens with source anchors, not outputs from a C++ executable.
The MeTTa fixture suite pins constants, selected closed/zero-gate reduced trees,
SSE/SAE, complexity penalties, and invalid arithmetic; floating values use
absolute/relative tolerance `1e-12`. It does not claim whole-reducer differential
parity. Error outcomes are taken from the C++ interpreter/scorer contract;
post-reduction error assertions additionally protect this port's conservative
policy. C++ algebraic reduction can remove subexpressions that this port retains
to preserve numerical failures. A live C++ differential harness remains useful
follow-up work.

## Validation and harder problems

```powershell
..\PeTTa\run.bat representation/tests/contin-nonlinear-test.metta -s
..\PeTTa\run.bat tests/continuous-nonlinear-reference-test.metta -s
..\PeTTa\run.bat moses/tests/contin-sr-test.metta -s
python -m unittest discover -s scripts/tests -v
```

There are 52 builder/reducer assertions, 45 reference assertions, and 18 routing/
optimizer integration assertions. The integration test pins the explicit program
`(c_add x (c_mul x x))` and zero train/held-out error for HC, univariate, BOA, and
hBOA under identical representation settings. It also tests zero/one-call budgets.
All 33 selected regression suites passed (1374 assertions), including prior
affine, Boolean, action and optimizer suites; all 25 Python tests passed.
The legacy univariate implementation and test hashes are unchanged.

`step13-manifest.json` supplies eight targets with disjoint train/validation/test
inputs: order two, quadratic interaction, cubic, quartic interaction, nested
sine, positive-argument log, exponential, and rational regression. Explicit
legal depth-one vectors reach every target from zero; no target is smuggled in
as an initial exemplar. The Python checker independently validates all splits
and supports the full continuous vocabulary, complexity and short-circuit rules.
Targets for the trig/exp/log CSVs allow library-level rounding (`SSE < 1e-24`
for the declared target); search acceptance is separately declared as `1e-8`.

The [exploratory polynomial comparison](benchmarks/continuous-nonlinear-smoke.md)
uses equal scorer-call allowances and reports actual calls and fitting time.
It does not close Step 14: equal-time runs, more paired seeds, dependency/
replacement ablations, function-rich searches, noisy data and uncertainty-based
enable/disable guidance remain required. A richer grammar alone is not evidence
that dependency learning improves sampling.
