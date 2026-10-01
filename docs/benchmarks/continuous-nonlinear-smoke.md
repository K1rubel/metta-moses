# Step 13: exploratory nonlinear optimizer comparison

## Result

On these supported polynomial regression problems, default HC beat the tested
univariate, BOA and hBOA configurations in both accuracy within the allowance
and resources consumed. HC solved 9/9 runs; each population method solved 6/9.
All solved runs also achieved zero held-out SSE. No optimizer default changed.

This is a **36-run exploratory comparison**, not Step 14 qualification or evidence
that dependency learning never helps. Three paired seeds are insufficient for
broad enable/disable advice. Polynomial targets are nonlinear in the inputs but
linear in their fixed-basis coefficients; richer expression syntax alone does
not guarantee a difficult dependency-learning problem.

## Protocol

Run on 2026-09-29, using [the versioned manifest](../../tests/fixtures/continuous/step13-manifest.json):
seeds 300, 301, 302; serial fresh processes; rotated optimizer order per seed;
500 actual scorer-call allowance (including initialization), ten outer
generations, depth-two trits, step 1, expansion 2, squared error, zero complexity
penalty. Default HC has widening disabled and crossover enabled. All algorithms
receive the same case-specific vocabulary, degree and scaffold settings.
Early target/stagnation/exemplar exhaustion can use fewer than 500 calls.

The three target families are:

- Quadratic interaction: `1 + x*x + x*z - z*z`, degree 2; six initial
  coefficient knobs / twelve trits; 25 training rows.
- Cubic: `1 + x - x*x + x*x*x`, degree 3; four knobs / eight trits; five
  training rows.
- Quartic interaction: `1 + x*z + x*x*z*z`, degree 4; fifteen knobs / thirty
  trits; 25 training rows.

Each target has an explicit legal genotype reachable from zero in the builder
tests. Validation/test input rows are disjoint from training, include fractional
points and test extrapolation to ±2.5, and never guide search or champion
selection. Acceptance is summed error ≤ `1e-8`; intermediate targets, scorer
indices and elapsed-time curves remain in the records.

The population methods use population/selection/offspring sizes 32/16/16,
pseudocount 1, exploration 0.1, and the manifest's fitting limits. BOA and hBOA
have 256 local-score calls per fit and a cooperative ten-second fit guard.
hBOA uses RTR; BOA/univariate use elitist replacement. Consequently this compares
configured algorithms, **not** an isolated causal effect of learned dependencies.
Matched-replacement and dependency-disabled ablations remain Step 14.

## Resource and quality results

Medians over all three runs per cell, retaining unsuccessful runs. Calls are
actual total scorer calls to run termination, **not** claimed time-to-target
for failed runs. Process seconds include interpreter startup, imports, CSV and
diagnostic output; fit seconds are the logged model-fitting subtotal.

| Target | Optimizer | Train + test success | Actual calls | Process seconds | Fit seconds |
| --- | --- | --- | --- | --- | --- |
| Cubic | hc | 3/3 | 37 | 3.366 | 0.000 |
| Cubic | univariate | 3/3 | 270 | 4.687 | 0.132 |
| Cubic | boa | 3/3 | 187 | 5.857 | 1.829 |
| Cubic | hboa | 3/3 | 199 | 6.913 | 2.231 |
| Quadratic interaction | hc | 3/3 | 53 | 2.729 | 0.000 |
| Quadratic interaction | univariate | 3/3 | 342 | 8.669 | 0.263 |
| Quadratic interaction | boa | 3/3 | 320 | 25.346 | 16.079 |
| Quadratic interaction | hboa | 3/3 | 427 | 18.526 | 4.964 |
| Quartic interaction | hc | 3/3 | 92 | 6.496 | 0.000 |
| Quartic interaction | univariate | 0/3 | 500 | 23.826 | 1.142 |
| Quartic interaction | boa | 0/3 | 500 | 43.021 | 18.417 |
| Quartic interaction | hboa | 0/3 | 463 | 32.703 | 7.063 |

The cubic and quadratic cases had zero training/test error and complexity 8
for every optimizer. The quartic case separates output quality:

| Optimizer | Train SSE | Test RMSE | Tree complexity |
| --- | --- | --- | --- |
| hc | 0 | 0.000000 | 7 |
| univariate | 95 | 3.560626 | 10 |
| boa | 302.5 | 6.615502 | 17 |
| hboa | 825 | 10.394581 | 16 |

These are independent marginal medians; they need not describe the same seed.
No held-out data selected these champions. The HC quartic winner is equivalent
to `1 + x*z + x*x*z*z`. Full exported programs, validation/test metrics,
raw/penalized champions, failure-aware threshold crossings and anytime traces
are retained in each run JSON.

### Learning cost and fitting bounds

BOA learned up to four edges for cubic and nine for quadratic interaction;
its 84 fits on these two families converged. For quartic, all 86 BOA fits hit
`fitScoreLimit`, with at most one learned edge per fit.

All 183 hBOA fits hit `fitScoreLimit`. The maximum learned-edge counts were
two for cubic and one for each interaction family. On quartic, hBOA runs used
463, 383 and 500 scorer calls; stagnation/outer lifecycle stopping is a valid
outcome, not a dropped failure. Thus this experiment also exposes the effect of
small fitting budgets as the field count grows. It cannot establish how a
better-supported or more thoroughly fitted dependency model would perform.

Default HC's coordinate search was effective on these noise-free, reachable
polynomial targets. The population methods spent more calls exploring and more
time maintaining/fitting models, without better predictions here. Even
univariate failed quartic, so dependency learning is not the sole explanation:
population size, search budget, replacement, representation and fit limits all
need controlled investigation.

## Correctness versus parity

Steps 12–13 add bounded polynomial/recursive-function construction, explicit
`sr` routing and an order-two end-to-end correctness gate for all four optimizers.
The [implementation document](../nonlinear-continuous.md) states the bounds and
C++ differences. Reference fixtures are **source-derived** from pinned C++ code,
not a live executable differential test and not full algebraic-reduction parity.

The remaining sine/log/exp/rational families have validated data and explicit
reachable genotypes, but their optimizer performance was **not measured here**.
Step 14 must add those coupled-argument searches, noisy data, more paired seeds,
equal-time budgets and learning/replacement ablations before broader guidance.

## Audit and reproduction

All 36 raw outputs were re-analyzed: exported programs, training and held-out
scores, counted initialization/optimizer traces, and model diagnostics agree
with their JSON records. There were zero runtime/report failures and zero invalid
evaluations in this polynomial study. Unsuccessful quartic searches remain in
the statistics. Source and dataset checksums were unchanged.

- [Machine-readable summary](step13-comparison-results/summary.json) includes
  paired deltas, bootstrap intervals and Wilson intervals; three-seed uncertainty
  is necessarily large.
- [Environment, exact configuration and hashes](step13-comparison-results/metadata.json).
  PeTTa's Git commit lookup returned null; the runtime path and main-file SHA-256
  are recorded. No missing provenance is silently filled in.
- [Validation/audit record](step13-validation.json).
- Per-run JSON and stdout are in `step13-comparison-results/`; source SHA-256:
  `f15fcc939b721b7ff35acfc69fbb0518867dba391900ac6621c8d6a395e18dde`.

```powershell
python scripts/optimizer_comparison.py --petta-main ../PeTTa/src/main.pl --swipl "C:/Program Files/swipl/bin/swipl.exe" --manifest tests/fixtures/continuous/step13-manifest.json --cases sr-interaction,sr-cubic,sr-quartic-interaction --output docs/benchmarks/step13-reproduction --timeout 180
```

Use a new output directory; the runner refuses to overwrite an existing run.
The direct SWI executable gives the benchmark reliable process exits. Ordinary
MeTTa tests and CLI searches still work with `..\PeTTa\run.bat`; because that
wrapper can mask failures, verification checks assertion counts/error output too.

Validation: 33 MeTTa suites / 1374 assertions; 25 Python tests; seven invalid CLI
configurations rejected with exit 1; four optional-function CLI routes accepted.
Legacy univariate file hashes are unchanged.

