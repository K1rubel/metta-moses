# Step 8: continuous affine HC baseline

This is the HC reference for later BOA/hBOA comparisons, not a claim that those
optimizers are implemented or outperform HC. The full nonlinear comparison is
still Steps 13–14. Configuration and datasets are versioned in
[baseline-manifest.json](../../tests/fixtures/continuous/baseline-manifest.json).

## Protocol

- Four clean synthetic affine training problems: `1+2*x`, identifiable
  `1+2*x-z`, absolute-error `-1+0.5*x`, and `1+3*x` with redundant feature `z=2*x`.
  The latter has no unique coefficient solution; assess predictions only on
  that feature relation. No off-manifold or noisy-data claim is made.
- CSV train/validation/test splits are checked in separately. Validation and
  test data are never sent to the search process. Champions are selected using
  training raw/penalized scores alone, then assessed on both held-out splits.
  The small test splits include extrapolation and fractional inputs.
- Development uses seed 0. Recorded baseline seeds are **100–129**, 30 per
  problem, with the same seed list reserved for paired future optimizer runs.
  No tuning against those recorded runs or held-out scores is permitted.
- Explicit settings: HC, step 1, expansion 2, depth 2, zero complexity penalty,
  10 outer expansions, one deme, 1,000 total scorer calls, raw target zero,
  relative improvement threshold `-1e-4`, and **widening enabled**, max distance 4.
  Crossover remains enabled; all remaining controls are recorded in the manifest.
  Initialization is charged; caches are fresh for every run; timing is serial.
- Success: training summed error at most `1e-8`. Intermediate summed-error
  targets are 1, 0.1 and 0.01. Held-out success is reported separately using the
  same tolerance. Identifiable coefficient error is reported independently.
  Evaluation checkpoints are 1, 10, 25, 50, 100, 250, 500 and 1,000 calls.
- Proposal/generation limits are safeguards, not alternative evaluation budgets.
  Runtime safety timeout is 120 seconds per process; a timeout/error remains a
  failed run in the denominator. Unreached error targets are null, not zero time.
  Local optimizer stop reasons are retained in each run's JSON.

Widening is an explicit benchmark override; application defaults were **not**
changed. During the seed-0 development check, nearest-neighbor stopping stalled
on the SAE fixture at raw score `-3`: coefficient 0 and coefficient 1 give equal
absolute error, while reaching 0.5 requires crossing that plateau/activating a
second trit. Widening allowed that fixture to reach zero. This motivates recording
the setting, not claiming that the default HC policy or every regression problem
will behave like this baseline. Future BOA/hBOA comparisons must retain this
declared HC configuration, or report configuration changes as separate experiments.

## Recorded results

Recorded on 2026-09-29: **120/120 runs succeeded**, with zero training,
validation and test error for the returned raw champions. All three identifiable
cases recovered their coefficients exactly. There were no process/report failures
or invalid scorer evaluations. Each case's 30/30 training success rate has a
Wilson 95% interval of approximately **88.65%–100%**.

Representative seed-100 programs (quoted names are CSV feature labels):

| Case | Returned program | Complexity |
| --- | --- | ---: |
| Linear | `(c_add 1.0 (c_mul 2.0 "x"))` | 3 |
| Multivariate | `(c_add 1.0 (c_mul 2.0 "x") (c_mul -1.0 "z"))` | 5 |
| Absolute error | `(c_add -1.0 (c_mul 0.5 "x"))` | 3 |
| Correlated | `(c_add 1.0 "x" "z")` | 3 |

The correlated output equals `1+3*x` on `z=2*x`; it is not a recovered unique
coefficient vector. Complexity uses the continuous scorer's cost, not AST node
count. Raw and penalized champion criteria coincide here because the declared
complexity penalty is zero.

Time values below are seconds. Brackets show the observed minimum–maximum;
unbracketed times and total call counts are medians across 30 seeds.

| Case | Calls to first error ≤ `1e-8` | Search time to that target | Total scorer calls | Process wall time |
| --- | ---: | ---: | ---: | ---: |
| Linear | 51 (all seeds) | 0.405 [0.350–0.894] | 52 [51–52] | 2.583 [2.166–5.154] |
| Multivariate | 299 (all seeds) | 2.973 [2.429–8.994] | 301 [300–301] | 5.416 [4.186–13.715] |
| Absolute error | 10 (all seeds) | 0.054 [0.048–0.135] | 21 [21–21] | 2.011 [1.852–4.177] |
| Correlated | 15 (all seeds) | 0.100 [0.075–0.265] | 20 [20–20] | 2.518 [1.836–5.174] |

These small fixtures exercise near-enumerative neighborhoods and show little
seed variation. They establish correctness and an auditable HC reference, not a
challenging enough benchmark to establish dependency-learning gains by themselves.
The wider ranges in wall time also reinforce the shared-host timing caveat below.
Exact records are in [summary.json](step8-hc-results/summary.json),
[metadata.json](step8-hc-results/metadata.json), and the per-run files.

## Reproduction

Run from the repository root; the output directory must not already exist:

```powershell
python scripts/continuous_baseline.py --swipl "C:/Program Files/swipl/bin/swipl.exe" --petta-main ../PeTTa/src/main.pl --output logs/step8-hc-reproduction
```

`--seeds 0` is an explicitly marked development override; omit it for the 30-seed
protocol. `--cases linear` limits a development check. If Git cannot inspect the
runtime checkout, supply its verified revision with `--petta-commit`; the runner
does not change global Git trust settings. The recorded runtime revision is in
the result metadata.

The numerical CSV path can also be exercised directly:

```powershell
swipl --stack_limit=8g -q -s ../PeTTa/src/main.pl -- moses.metta -s --problem=linear --inputFile=tests/fixtures/continuous/linear-train.csv --continDepth=2 --maxGen=10 --maxEvals=1000 --hcWidenSearch=True
```

Add `--targetFeature=header` when the target is not last. CSV headers are exact
string labels; whitespace is not silently stripped. Numeric `inputFile` and an
explicit `continTable` are mutually exclusive.

## Artifacts and measurement boundaries

[step8-hc-results/](step8-hc-results/) contains metadata, a summary, per-run JSON,
and raw stdout. Each run exports returned programs, both champions, training and
held-out errors/validity, complexity, identifiable coefficients, actual calls,
proposals/cache hits/invalids, generation diagnostics, and per-evaluation elapsed
times. Counted initialization plus local optimizer counts must equal the scorer
trace length; the recorder fails loudly if they do not agree. Exported program
scores are checked by an independent affine evaluator, not by a fitting shortcut.

Time-to-target is read from the scorer trace after the invocation that first
meets the **training** tolerance. Its clock starts at run cache reset and includes
initialization, representation construction and subsequent search work. Total
process-wall time also includes PeTTa startup/imports, CSV loading, output and
shutdown. Post-run report generation/held-out evaluation is excluded. Tracing
and diagnostic overhead is included; later algorithms must use the same setup.
Timing was taken on a shared workstation, not an isolated performance host, so
small wall-time differences are not meaningful evidence of algorithmic gains.

Best-so-far curves retain the result after an early stop; they do not fabricate
additional evaluations. Per-target first-hit values are distinct from total run
calls: an optimizer can finish its current batch after first discovering a target.
Failures/censored targets must remain visible in later comparisons. Success-rate
uncertainty uses Wilson 95% intervals; repeated seeds here vary search randomness,
not the fixed datasets, and do not establish generalization to other problem families.

## Scope of acceptance

`moses/tests/contin-linear-test.metta` covers exact CSV/in-memory results and
held-out numerical equivalence. Python tests cover loader failures, exact headers,
binary64 values, Boolean compatibility and recorder parsing/metrics. Boolean/action
pipeline regressions remain required. These tests and the HC measurements establish
the affine baseline only. Univariate EDA is Step 9; BOA/hBOA are Steps 10–11, followed
by nonlinear construction and the broader controlled comparison.

Acceptance validation for this implementation passed 15 Python tests and 23
MeTTa suites (952 passing runtime assertions, including the new 32-assertion
CSV/affine suite). The existing merge suite emits 38 runtime checks from 20
source assertions; all other suite counts matched their source assertions.
Coverage includes continuous decoder/reducer/scoring/lifecycle, generic optimizer
accounting, Boolean CSV/neighborhood/merge/scoring, ant and tic-tac-toe action
paths. Five direct CLI checks confirmed nonzero exits for invalid numeric cells,
unknown targets, missing files, unsupported `sr`, and conflicting CSV/in-memory
inputs. The development-only default-widening SAE check was repeated and still
returned raw `-3`; it is not included among the 120 configured baseline runs.

Follow-up test strengthening pins the four seed-0 winning programs as literal
expected expressions, alongside their existing explicit zero scores and separate
CSV/in-memory equivalence checks. The updated suite passes all 36 assertions via
`..\PeTTa\run.bat moses/tests/contin-linear-test.metta -s`. This test-only change
does not modify search code or the recorded benchmark artifacts; their source
hash describes the original measurement snapshot.
