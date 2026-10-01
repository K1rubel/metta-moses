# Step 10: HC, univariate EDA and BOA

This is the initial affine/Boolean comparison required by Step 10, not the later
hBOA, RTR, nonlinear or equal-wall-time qualification. HC remains the default.

Recorded artifacts: [metadata](step10-comparison-results/metadata.json),
[full summary](step10-comparison-results/summary.json), and
[post-run audit](step10-comparison-audit.json). All 540 processes completed;
the runner exits 1 because 15 Boolean exports fail strict score validation,
not because processes crashed. The audit preserves that distinction.

Recorded source SHA256:
`37c5db93e78c122014a1537d96a0d53d261c405a17932c66effddc9b21ce3aea`.
The runner's end-of-run hash check confirms no source changes during measurement.
Runtime: SWI 10.0.2, Python 3.14.6, Windows 10; PeTTa revision is pinned below.
The metadata records the available processor/platform identification.

## Protocol and reproduction

The frozen [manifest](../../tests/fixtures/continuous/step10-manifest.json)
specifies seeds 100–129, three optimizers and six cases (540 fresh processes).
Seed 0 is reserved for development. Run serially from the repository root:

```powershell
python scripts/optimizer_comparison.py --petta-main ../PeTTa/src/main.pl --swipl "C:/Program Files/swipl/bin/swipl.exe" --petta-commit 429e22916630ea6fd1f24a3d45869f0082a85852 --output docs/benchmarks/my-step10-results
```

The output directory must not already exist. Individual `.metta` tests and
searches still run normally through `..\PeTTa\run.bat`; the recorder invokes the
same SWI/PeTTa entrypoint directly to capture process exit status reliably.
Algorithm order rotates per seed to reduce ordering bias. No optimizer is
tuned on evaluation seeds or held-out data. All algorithms are rerun on the same
source snapshot; the earlier Step 8 measurements remain untouched.

Affine cases use depth 2, step 1, expansion 2, a zero program-complexity penalty,
the same legal vocabulary, and a **1,000-call maximum** including seed scoring.
Raw-target termination can end a run early. EDA population/selection/offspring
sizes are 32/16/16, tournament size 2, pseudocount 1 and legal-prior exploration
0.1. Univariate and BOA share initialization and replacement policies. HC's
`hcWidenSearch=True` override is retained from the predeclared Step 8 protocol;
the application default is unchanged. HC's center is not portrayed as an EDA
population, and EDA initialization is not free.

Four affine targets are `1+2*x`, `1+2*x-z`, absolute-error `-1+0.5*x`, and
`1+3*x` on the correlated `z=2*x` manifold. Validation/test CSVs are never passed
to search. The recorder independently evaluates every returned program and
checks exported scores, then reports raw and penalized champions selected using
training data only. The predeclared success tolerance is summed error `1e-8`;
intermediate targets and evaluation checkpoints are retained in each run.
Correlated coefficients are not uniquely identifiable; no off-manifold claim is
made. With zero complexity penalty, this experiment does not establish an
error-versus-simplicity tradeoff.

The two Boolean controls, `disjunction3` and odd `parity3`, use the full 8-row
truth table, **200 local scorer calls** and at most 3 outer expansions. They
retain the frozen Boolean default `complexityRatio=3.5` and have no held-out
split. Their final scores are checked independently. Unlike
continuous runs, their legacy initial exemplar is not scored; call totals come
from the shared optimizer diagnostics rather than a Boolean per-call trace.
The disjunction control is easy logical search, not a proof of an independent
knob landscape; the direct model tests supply the independent categorical
control. Parity supplies a harder interacting logical target, not hBOA's future
hierarchical/deceptive benchmark suite.

## Timing and interpretation

Process wall time includes imports, CSV loading, the whole MOSES loop and trace
output. Continuous time-to-target starts at run cache reset and includes fitting,
sampling, scoring and earlier expansions. Model-fit time is a separately
instrumented subset, not a substitute for total elapsed time. Scorer calls,
proposals and cache hits are distinct; EDA's unretained-proposal count includes
canonical repeats and any pending-at-deadline proposal. Raw logs retain fit
sizes, cache hits and fitting stop reasons.

Results retain failures and non-successes. Unreached targets are censored, not
zero-cost successes; target-time medians are explicitly conditional on reaching
the target. Summary JSON includes per-group median/min/max, Wilson success-rate
intervals, and paired BOA-minus-control differences with a deterministic 2,000
resample percentile bootstrap for median differences. Paired seeds identify
trials, not identical random draws across HC and EDA.

These are small, noiseless affine fixtures on a shared workstation. Reporting
30 seeds does not make them representative of hard symbolic regression.
Fitting has cooperative deadlines; one local fit/root initialization may finish
after its timestamp. Equal-time quality, fixed-representation isolation,
no-dependency BOA ablation, matched RTR, noisy generalization and nonlinear
quality remain later planned experiments.

The machine was not an isolated benchmarking host: background activity and
occasional inspection of completed results can affect wall times. Algorithm
order rotates within each seed, but the timing intervals do not establish
performance on other hardware or under controlled load.

## Development-record caveat

`step10-development-results/` contains the initial seed-0 probe. Its first
Boolean parity analyzer accidentally used even parity; the stored analysis
failures are preserved, not relabeled as optimizer failures. The recorder was
corrected to the repository's odd-parity truth table, unit-tested, and checked
again in `step10-parity-recorder-check/` before the frozen run. Development
timings overlapped checks and are **not** used for comparative conclusions.

## Results

The frozen run is recorded in `step10-comparison-results/`. All 360 affine runs
reached the training target and succeeded on the held-out test set (30/30 for
each case/algorithm), with zero train/validation/test RMSE and MAE, no invalid
evaluations and no scorer-budget violations. A 30/30 success result has a Wilson
95% interval of approximately 88.6%–100%; this is not a guarantee on new problems.

### Affine efficiency

Calls are actual charged evaluations. Brackets give the observed range. Times
are medians in seconds; **search-to-target** excludes startup while **process**
includes it. Fitting is a subset of search time, not an additional charge.

| Case | Optimizer | Calls, median [min–max] | Search-to-target | Process | Fitting |
| --- | --- | ---: | ---: | ---: | ---: |
| `1+2*x` | HC | 52 [51–52] | 0.398 | 2.679 | 0 |
| | Univariate | 56 [50–84] | 0.800 | 3.172 | 0.017 |
| | BOA | 57.5 [50–82] | 1.008 | 3.429 | 0.081 |
| `1+2*x-z` | HC | 301 [300–301] | 2.515 | 4.554 | 0 |
| | Univariate | 253 [207–314] | 5.114 | 7.202 | 0.092 |
| | BOA | 252.5 [207–332] | 5.906 | 8.037 | 0.732 |
| `-1+0.5*x`, SAE | HC | 21 [21–21] | 0.049 | 1.892 | 0 |
| | Univariate | 26 [5–48] | 0.090 | 1.935 | 0 |
| | BOA | 26 [5–48] | 0.079 | 1.928 | 0 |
| `1+3*x`, `z=2*x` | HC | 20 [20–20] | 0.076 | 1.923 | 0 |
| | Univariate | 43.5 [2–103] | 0.167 | 2.096 | 0.006 |
| | BOA | 42 [2–87] | 0.247 | 2.129 | 0.072 |

On the multivariate fixture, BOA used about 16% fewer median calls than HC, but
took about 76% more median process time. Univariate obtained essentially the
same median call reduction without dependency learning. This does **not**
establish a distinct BOA advantage. On the other three cases HC had fewer median
calls. Differences between marginal medians are descriptive; paired differences
and their uncertainty are reported in the machine-readable summary.

Selected paired medians below are **BOA minus control**; negative means less
resource consumed. Brackets are bootstrap 95% intervals for the median paired
difference, not intervals for individual runs.

| Case | Control | Call difference | Process-seconds difference |
| --- | --- | ---: | ---: |
| Linear | HC | +6 [1, 8.5] | +0.732 [0.585, 0.954] |
| Linear | Univariate | 0 [-1, 0] | +0.279 [0.059, 0.460] |
| Multivariate | HC | -48 [-56.5, -32] | +3.688 [2.915, 4.528] |
| Multivariate | Univariate | -2 [-17, 18] | +0.939 [0.622, 1.307] |
| Absolute error | HC | +5 [-4, 13] | +0.029 [-0.023, 0.088] |
| Absolute error | Univariate | 0 [0, 0] | +0.004 [-0.012, 0.055] |
| Correlated | HC | +22 [11, 35] | +0.207 [0.109, 0.357] |
| Correlated | Univariate | 0 [0, 0] | +0.056 [-0.004, 0.144] |

For multivariate data BOA used fewer calls than HC in 28/30 paired seeds but was
slower in all 30. Against univariate it won on calls in 15 seeds and lost in 15;
the call-difference interval spans zero. Zero median and a narrow/degenerate
bootstrap interval can coexist with individual wins and losses: correlated BOA
versus univariate had 7 call wins, 14 ties and 9 losses.

The `2*x` coefficient is outside the zero-centered depth-2 coefficient values
`{-3,-1,-0.5,0,0.5,1,3}`. The first two problems therefore require the outer
exemplar/recentering loop; their differences cannot be attributed solely to
sampling within one fixed representation.

In 19/30 absolute-error runs and 10/30 correlated runs, both EDA variants found
the target during common prior initialization, **before any model fit**. Those
successes are not evidence for learned dependencies. A median fitting time of
zero on the absolute-error case reflects this, not cost-free BOA learning.

### Affine output quality

The identifiable targets recover the expected programs and coefficients, with
continuous complexity 3 (`1+2*x`), 5 (`1+2*x-z`) and 3 (`-1+0.5*x`). Correlated
outputs are prediction-equivalent on the declared manifold, but complexity is
3 for HC and ranges from 3 to 5 for both population methods. With a zero
complexity penalty and immediate raw-target stopping, BOA is not guaranteed to
find the simplest equivalent program.

Concrete wins/ties/losses against the univariate control (all have zero
train/validation/test error):

| Case and seed | BOA calls | Univariate calls | BOA reduced program | Complexity |
| --- | ---: | ---: | --- | ---: |
| Linear 118, win | 51 | 62 | `(c_add 1.0 (c_mul 2.0 "x"))` | 3 |
| Linear 101, tie | 50 | 50 | `(c_add 1.0 (c_mul 2.0 "x"))` | 3 |
| Linear 115, loss | 82 | 56 | `(c_add 1.0 (c_mul 2.0 "x"))` | 3 |
| Multivariate 120, win | 218 | 271 | `(c_add 1.0 (c_mul 2.0 "x") (c_mul -1.0 "z"))` | 5 |
| Multivariate 114, loss | 301 | 240 | `(c_add 1.0 (c_mul 2.0 "x") (c_mul -1.0 "z"))` | 5 |
| Correlated 114, win | 65 | 103 | `(c_add 1.0 (c_mul 3.0 "x"))` | 3 |
| Correlated 110, loss | 87 | 56 | `(c_add 1.0 "x" "z")` | 3 |

All 580 affine BOA fits stopped at the greedy convergence condition rather than
a resource cap. Maximum learned edges observed per fitted model were 3, 5, 2
and 5 for linear, multivariate, absolute and correlated cases respectively.
This confirms learning occurred, but not that the learned edges improved
prediction. Both raw and penalized champions are recorded; their objective
values coincide here because the continuous complexity penalty is zero.

**Current affine recommendation:** retain HC as the default. BOA is a working
opt-in dependency learner, but these measurements show no predictive improvement
and no general efficiency win over HC or the univariate control. This conclusion
is restricted to the tested small affine fixtures, not a claim that dependency
learning cannot help harder problems.

### Boolean export-validation limitation

The strict validator found a pre-existing discrepancy in some Boolean exports:
the initial `true` exemplar is assigned `-N` without being evaluated in
`problem-context` (`moses/demo-problems.metta`), and `scoreTree`
(`scoring/bscore.metta`) deliberately assigns `-N` to a root empty `AND`.
Both expressions conventionally predict true, so their actual disjunction3
error score is `-1`, not `-8`. A short successful run can retain these rows
alongside its correctly scored winner in `FinalResult`.

These are existing initialization/scoring conventions, not learned BOA edges
or mixed continuous/Boolean representations. Step 10 does not silently change
Boolean scoring policy or rescore exports outside the evaluation budget. The
recorder retains each affected run as an explicit **report-validation failure**,
including raw stdout. Such a failure is not the same as failure to discover the
target. Summary success counts for that control consequently mean fully
validated successful exports, not an unbiased estimate of target discovery.
The Boolean scoring/export contract needs a separate correction or explicit
status labeling before making broad discrete-output quality claims. No affine
run has this problem.

### Boolean control results

A post-run audit independently evaluated each highest-reported-raw-score
program on all eight truth-table rows and verified its score in **all 180**
Boolean runs. It also enumerated every mismatching lower-ranked row. This
separate audit does not reclassify the 15 whole-export failures as passing.
The following calls and wall times include all 30 runs per row, recovered from
raw optimizer diagnostics even when strict export validation failed. They are
work consumed, not time-to-success for failed searches.

| Control | Optimizer | Correct exact winners | Whole-export failures | Calls, median [range] | Process seconds | Median best raw |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| Disjunction3 | HC | 30/30 | 0/30 | 51.5 [46–57] | 2.154 | 0 |
| | Univariate | 29/30 | 8/30 | 40.5 [2–200] | 2.246 | 0 |
| | BOA | 30/30 | 7/30 | 43.5 [2–178] | 2.831 | 0 |
| Parity3 | HC | 0/30 | 0/30 | 200 [200–200] | 3.779 | -2 |
| | Univariate | 0/30 | 0/30 | 200 [200–200] | 4.623 | -2.5 |
| | BOA | 0/30 | 0/30 | 200 [200–200] | 13.247 | -2.5 |

Disjunction offers no elapsed-time advantage for BOA, despite its lower median
call count than HC. The isolated univariate non-success is not evidence of a
reliable BOA success-rate advantage. On parity all methods exhausted the
allowance; HC's best raw scores ranged from -3 to -1, while both EDAs ranged
from -3 to -2. BOA's median model-fit time alone was 8.105 seconds, without an
improvement over univariate's median final raw score.

All 425 Boolean BOA fits hit the configured **256 candidate-local-fit cap**;
none should be described as an unconstrained converged network. These larger
discrete representations expose the computational bound and deterministic
scan-order limitation. Increasing/tuning that bound is a future separately
measured experiment, not a retroactive change to this comparison. No claim is
made that this small, untuned bounded BOA configuration establishes the limit
of BOA or hBOA on discrete problems.

The original summary's disjunction call/fitting aggregates omit the 15 invalid
exports and therefore are not all-run resource estimates. Use the audited table
above for that control; use its strict counts to assess whole-export validity.
The artifact [audit](step10-comparison-audit.json) includes every affected seed
and mismatch. The recorder intentionally returns failure rather than hiding
the discrepancy. Broad Boolean export qualification remains open.
