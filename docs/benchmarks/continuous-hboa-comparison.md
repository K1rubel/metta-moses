# Step 11: does hBOA outperform default HC?

Not generally in this initial, untuned comparison. hBOA solves one affine
plateau that default HC misses, but independent sampling and widened HC solve
it too. On the other three affine fixtures, HC produces equally accurate
programs with lower median scorer-call and elapsed-time costs. Keep HC as the
default; hBOA remains opt-in. These results concern this bounded implementation
and these small fixtures, not all hBOA configurations or symbolic regression.

## Protocol and evidence

380 serial fresh-process runs: four affine fixtures × eight configurations ×
10 paired seeds, plus two fixed-deme diagnostics × three configurations × 10
seeds. Seeds **200–209** are disjoint from development seed 0 and the earlier
Step 8/10 measurement seeds. No settings were tuned after seeing these results.

- [Manifest](../../tests/fixtures/continuous/step11-manifest.json): complete
  settings, seeds, cases and algorithm-specific overrides.
- [Metadata](step11-comparison-results/metadata.json),
  [summary with paired intervals](step11-comparison-results/summary.json), and
  [per-run JSON/stdout](step11-comparison-results/): full commands, programs,
  scores, evaluation curves, time-to-target, fitting and replacement traces.
- [Audit](step11-comparison-audit.json): integrity explanation, control checks,
  fit-limit statistics, and diagnostic success seeds.
- [Verification](step11-verification.json): 30 MeTTa suites / 1,259 assertions,
  22 Python tests, and 12 rejected invalid CLI configurations. The legacy
  univariate files retain their pre-Step-11 hashes.

**Provenance caveat, not suppressed:** the recorder exited 1 because its final
byte-level source hash differed, despite all 380 runs passing runtime and score
validation. During the run, `hboaConfigValid` was reformatted across three lines.
Reconstructing only those original spaces/newlines in memory reproduces the
exact starting hash of **all** hashed source files. Thus executable content did
not change, but this was not a byte-identical run. The original warning, metadata,
summary and raw records remain unchanged; the audit records both file/repository
hashes and the exact reconstruction. The 74-assertion hBOA suite passed again
afterward. The formatting edit is preserved.

Runtime: Windows 10, SWI-Prolog 10.0.2, Python 3.14.6, PeTTa commit
`429e22916630ea6fd1f24a3d45869f0082a85852`. Process times include imports, CSV
loading, search and instrumentation. Search-target times start at cache reset.
Runs were serial with rotated arm order per seed; this was a shared workstation,
not an isolated timing machine. Documentation work and light result inspection
continued during execution, but no other test/benchmark suite ran concurrently.
The development run did overlap tests/source edits and is excluded throughout.

The comparison uses equal **allowances**, not forced equal work: affine budgets
are 1,000 actual scorer calls, 10 outer generations and one selected deme;
earlier success/stagnation/exhaustion remain valid stopping conditions. All arms
share depth-2 trits, step 1, expansion 2, zero program-complexity penalty, the
same training/validation/test splits, and no nonlinear operators. Targets and
ranking see training data only. Every returned program's reported training
score is independently checked; the training-selected champions are evaluated
on validation/test data. There were no invalid evaluations or budget violations.

The HC arm uses actual default **HC search settings**, notably
`hcWidenSearch=False`, crossover enabled, and maximum distance 4. Representation,
data and budget settings are explicit experiment overrides. Earlier Step 8/10
comparisons used `hcWidenSearch=True`; this report includes that separate arm.

| Arm | Model | Replacement / difference |
| --- | --- | --- |
| `hc` | Default HC | No learned model |
| `hc_wide` | HC | `hcWidenSearch=True` |
| `univariate_rtr` | Independent categorical | RTR |
| `boa` | Categorical CPT | Elitist, BOA default |
| `boa_rtr` | Categorical CPT | RTR |
| `hboa_elitist` | Conditional trees | Elitist |
| `hboa` | Conditional trees | RTR, hBOA default |
| `hboa_no_dependencies` | Root distributions only | RTR; fixed activation remains |

EDA settings are matched: population 32, selection 16, offspring 16, tournament
2, pseudocount 1, exploration 0.1, refill 256, stagnation 10, RTR window 8.
BOA/hBOA each allow 256 candidate fit checks and 16 committed changes per fit,
with a cooperative 10-second cap. BOA defaults to two learned parents and 256
CPT cells; hBOA to three parents, depth three, eight leaves, support two. These
are declared implementation defaults, not equal model capacities or tuned
best-performing configurations. See [the hBOA policy](../hboa-optimizer.md).

## Affine quality and efficiency

All entries are medians across ten runs; success means the training target was
reached and the returned solution also had zero validation/test error.

| Fixture | HC / hBOA successes | HC calls | hBOA calls | HC process seconds | hBOA process seconds |
| --- | --- | ---: | ---: | ---: | ---: |
| `1 + 2*x` | 10 / 10 | 28 | 51.5 | 2.142 | 2.714 |
| `1 + 2*x - z` | 10 / 10 | 78 | 277.5 | 2.537 | 11.601 |
| `-1 + 0.5*x`, absolute loss | 0 / 10 | 33* | 27 | 2.315* | 2.118 |
| `1 + 3*x`, correlated inputs | 10 / 10 | 20 | 50.5 | 2.630 | 3.325 |

`*` HC's absolute-loss figures are work spent **without** finding a solution,
not time-to-success. Its champion is constant `-1`, training SAE 3, validation
SAE 1.75 and test SAE **3.125** (test MAE 1.04167). hBOA's program is
`-1 + 0.5*x`, with zero error on all three splits. However, **all seven
non-default-HC arms solve this fixture 10/10**, and six hBOA runs finish
before any learned-model fit. This does not establish a dependency-learning gain.

Across the four fixtures, hBOA solves 40/40 and HC 30/40. Where both solve,
there is no accuracy advantage: train, validation and test errors are all zero.
Identifiable coefficients are exact. hBOA's seed-200 programs are `1+2*x`,
`1+2*x-z`, `-1+0.5*x`, and `1+3*x`. Complexity is respectively 3, 5, 3, and
3–5 across seeds; HC has 3, 5, 1 (the inaccurate constant), and 3. Thus hBOA
does not show a simpler-program advantage either. For the correlated fixture,
`z=2*x` makes coefficients non-identifiable; held-out results apply on that
manifold, not to independent off-manifold changes of `x,z`.

First-exact-target **search** times, excluding startup, also favor HC where it
solves: linear 0.157 vs 0.750 seconds, multivariate 0.572 vs 9.430, correlated
0.096 vs 0.618. hBOA's absolute-loss median is 0.083 seconds; HC never reaches
that target. HC sometimes finishes scoring a batch after encountering a target:
multivariate first-target calls have median 77 vs 78 total, correlated 15 vs 20.
Do not interchange final call counts and first-target counts.

Paired hBOA-minus-HC total-call differences are +23 on linear (bootstrap 95%
interval [22, 28]), +198.5 on multivariate ([179, 230.5]), and +30.5 on correlated
([8, 56]). hBOA takes more calls and more process time on **all ten** linear and
multivariate pairs. The multivariate paired time difference is +9.073 seconds
([6.971, 9.694]). These intervals are exploratory percentile-bootstrap summaries
of ten pairs, not broad population guarantees. For perspective, 10/10 successes
has a Wilson 95% interval of approximately [0.722, 1], and 0/10 [0, 0.278].

## What the controls say

Median total scorer calls, with the same success pattern described above:

| Arm | Linear | Multivariate | Absolute | Correlated |
| --- | ---: | ---: | ---: | ---: |
| Default HC | 28 | 78 | 33 (failed) | 20 |
| Widened HC | 51 | 300 | 21 | 20 |
| Univariate + RTR | 57 | 248 | 27 | 40 |
| BOA + elitist | 55.5 | 267 | 27 | 52 |
| BOA + RTR | 55 | 289.5 | 27 | 45.5 |
| hBOA + elitist | 57 | 251 | 27 | 47 |
| hBOA + RTR | 51.5 | 277.5 | 27 | 50.5 |
| hBOA without dependencies + RTR | 57 | 248 | 27 | 40 |

The no-dependency and univariate-RTR controls have identical total calls,
proposal counts **and returned programs for all 40 affine pairs**. Timing and
model diagnostics differ, but this checks that turning learning off does not
silently change the underlying independent search distribution.

- **Learning effect, replacement matched:** hBOA vs no-dependencies has a paired
  median linear saving of 5.5 calls, but interval [-11.5, 0] includes no gain.
  Multivariate instead costs 14 more calls ([-24, 63], five wins/five losses),
  and 4.459 more process seconds ([2.110, 5.863]). No general learning advantage.
- **RTR effect, tree model matched:** linear improves by 3.5 calls ([-14, -2],
  nine wins/one tie); multivariate costs 22.5 more ([-3, 48], two wins/eight
  losses). Absolute calls tie on every seed; correlated calls never improve.
  RTR is useful on one fixture, not a universally better replacement policy.
- **Tree vs CPT, replacement matched:** hBOA-minus-BOA-RTR multivariate calls
  differ by +6 ([-29, 24.5]), while process time increases by 1.800 seconds
  ([0.783, 3.992]). This does not support replacing CPTs with trees for speed
  on these fixtures. Model capacity/fit operators differ as declared above.
- **Default versus widened HC matters:** hBOA's multivariate median uses fewer
  calls than widened HC (277.5 vs 300), but many more than default HC (78), and
  is slower than both. A favorable comparison only to widened HC would answer
  a different question from the one asked here.

## Fitting overhead and bounds

| hBOA fixture | Fits | Fits hitting 256-check cap | Max learned edges | Median total fit seconds/run |
| --- | ---: | ---: | ---: | ---: |
| Linear | 29 | 0 | 3 | 0.135 |
| Multivariate | 155 | 144 | 4 | 2.573 |
| Absolute | 4 | 0 | 2 | 0.000 |
| Correlated | 20 | 19 | 3 | 0.341 |

Zero median fit time on absolute loss means at least half the runs needed no
fit, not that fitting is free. Three correlated runs also finish without a fit.
No recorded hBOA fit ended at its wall-time limit. Fitting overhead is material,
but it is not the entire EDA overhead: selection, archive/deduplication, refill,
replacement and materialization also consume time.

These are tiny local spaces (49 or 343 legal depth-2 genotypes). Some exact
targets require recentering coefficients in a new deme. Population filling and
near-exhaustive local exploration can therefore cost more than HC's quick
local improvement/recentering. That is an interpretation of this representation
and the traces, not an isolated causal experiment.

## Separate fixed-deme linkage diagnostics

These are **not regression workloads**. A fixed representation holds 12 or 8
binary knobs. Its injective tree encoding uses the existing action-fitness seam,
one deterministic episode, zero complexity penalty and the common counted
scorer/cache. Scores, every evaluation event, and returned vectors are checked
independently by Python. No synthetic uncounted optimizer or surrogate HC is
substituted. Complexity still breaks equal-score ties, consistently for all arms.

`trap12` sums four 3-bit traps: a block with three ones scores 3; otherwise it
scores `2 - number_of_ones`. All-zero initialization is a local optimum of 8,
with global target 12. `hiff8` rewards uniform aligned blocks at sizes 1, 2, 4,
8 by their size; alternating initialization scores 8, and either uniform vector
scores 32. Each run has a 256-call allowance. These tiny cases do not test scaling.

| Diagnostic | Arm | Successes | Median final raw score | Median total calls | Process seconds | Fit seconds |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| Trap12 | HC | 10/10 | 12 | 253 | 3.218 | 0 |
| Trap12 | hBOA | 2/10 | 10.5 | 256 | 7.301 | 2.761 |
| Trap12 | No-dependency RTR | 0/10 | 10 | 256 | 4.767 | 0.213 |
| HIFF8 | HC | 10/10 | 32 | 28 | 2.316 | 0 |
| HIFF8 | hBOA | 10/10 | 32 | 56.5 | 3.026 | 0.436 |
| HIFF8 | No-dependency RTR | 10/10 | 32 | 58 | 2.480 | 0.018 |

The two successful hBOA trap seeds (202, 209) hit at 73 and 159 calls; this is
**not** a general 116-call time-to-success claim, because eight runs are censored.
HC's first target occurs at 250 calls on all ten seeds (253 final). Repository
HC includes crossover/distance moves and can cross a three-bit block: this is
not a comparison against a strict single-bit local optimizer.

All **116** hBOA trap fits hit the score-check cap and learn at most **one edge**.
A root-level scan alone has up to `12*11*2=264` binary test candidates; a cap
of 256 cannot complete it before a first split. This setting severely limits
the model and introduces scan-order bias. HIFF8's 21 fits also hit the cap
(maximum three learned edges); two runs solve during initialization. Its paired
call difference from no-dependency sampling has median zero, interval [-26.5,
2]. Neither diagnostic demonstrates an advantage over default HC. The 2/10
versus 0/10 trap result is too small and uncertain to establish a dependable
learning benefit, especially with these tight fitting bounds.

## Conclusion and next experiments

Step 11's implementation/integration gate is met: context-specific trees,
bounded cycle-safe sampling, RTR, controls, direct tests and initial comparisons
are present. A performance win is not required to declare the feature implemented,
and **is not claimed**. Keep HC as the default and expose hBOA explicitly.

Before claiming an hBOA advantage, separately test increased fit/selection
budgets on development data, then evaluate fresh seeds with equal tuning effort.
Do not retune against the held-out rows or revise this report's fixed settings
afterward. Larger linkage problems and coefficient-coupled regression could test
different regimes. Step 14 still owes equal-time runs, nonlinear/noisy workloads,
larger independent test sets and broader uncertainty analysis after Steps 12–13
provide nonlinear representations. Current archive-wide duplicate suppression
(including prior RTR rejects) is another declared policy, not textbook unlimited
resampling; its effect has not been isolated here.

## Reproduction

```powershell
..\PeTTa\run.bat optimization/hboa/tests/hboa-test.metta -s
..\PeTTa\run.bat moses/tests/hboa-pipeline-test.metta -s
python -m unittest discover -s scripts/tests -v
python scripts/optimizer_comparison.py --petta-main ../PeTTa/src/main.pl --swipl "C:/Program Files/swipl/bin/swipl.exe" --petta-commit 429e22916630ea6fd1f24a3d45869f0082a85852 --manifest tests/fixtures/continuous/step11-manifest.json --output docs/benchmarks/step11-reproduction
```

Use a new output directory; the runner refuses to overwrite evidence. Do not
edit source during a reproduction, including formatting, or the byte-hash guard
will flag it. `run.bat` remains supported for MeTTa tests and normal CLI runs;
the recorder invokes SWI directly to capture reliable process exit codes.
