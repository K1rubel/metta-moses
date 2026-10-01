# Step 14 — controlled continuous-optimizer qualification (partial)

## Executive result

The ten-seed equal-evaluation study shows that hBOA is not a general improvement
over the current HC configuration. It ties HC on exact held-out fits for affine
linear, multivariate and correlated regression, but spends more calls and wall
time on the identifiable affine cases. hBOA underperforms on cubic, polynomial
interaction and exponential targets. The absolute-loss fixture is an exception:
HC misses all ten exact targets while all three population optimizers reach
them. On sine, exact success is rare for every default arm.

The controlled ablations make the earlier “dependency learning is the cause”
claim too narrow. On the quadratic interaction, hBOA with elitist replacement
solves 3/5 paired seeds versus default hBOA+RTR at 1/5; disabling dependencies
solves 2/5. Increasing the fit-call ceiling to 1024 solves 1/5 and costs
substantially more time. Matched BOA+RTR solves only 1/5 although default
BOA+elitist solves 9/10 in the primary matrix. This is evidence that RTR is a
major contributor on this family, while the dependency model can still hurt:
the no-dependency control is only a modest improvement, not a recovery to HC.
These five-seed ablations are directional, not a final per-family default rule.

On sine, widened HC solves all five ablation seeds with a median 63 scorer
calls, while default HC solves 0/5 and default hBOA solves 0/5. That materially
changes the interpretation of the default-HC comparison: search-neighborhood
configuration is a confound, and the results do not establish that model-based
sampling is intrinsically worse than a properly matched HC baseline.

HC remains the default. Step 14 is **not complete**: the quartic cell could not
be completed safely, the equal-time run is only a single-expansion diagnostic,
and noisy-data/generalization and a continuous fixed-deme study remain open.

## Study design and audit trail

The completed primary equal-evaluation cells use ten paired seeds (400–409), a
500 actual-scorer-call allowance, the same train/validation/test fixtures, and
the same declared representation/scoring settings for HC, univariate EDA, BOA
and hBOA. Success requires both training error and test error at or below
`1e-8`; test data never participates in selection. Outputs include each
returned program, independent train/validation/test metrics, call traces,
time-to-intermediate-target, fitting diagnostics, replacement diagnostics and
anytime curves.

The fully completed equal-evaluation matrix is 8 fixtures × 10 seeds × 4 arms
(320 runs): `linear`, `multivariate`, `absolute`, `correlated`, `sr-cubic`,
`sr-interaction`, `sr-sine`, and `sr-exp`. The separate quartic stress cell was
started, but only nine of its planned 40 runs were recorded before an hBOA
process exceeded the wrapper's safety timeout. Its timeout record is retained;
it is not included as a measured runtime or folded into a success denominator.
The prior Step 13 three-seed quartic result remains separate and exploratory.

The five-seed causal-ablation batch covers `sr-interaction` and `sr-sine` with
nine arms: HC, widened HC, univariate+RTR, BOA+RTR, hBOA+RTR, hBOA without
learned dependencies, hBOA+elitist, hBOA with a 1024 local fit-score-call
ceiling, and hBOA with population/selection/offspring 64/32/32. The equal-time
folder contains 60 runs on linear and sine, but is reported only as a
single-expansion deadline diagnostic (see limitations below).

| Artifact | Contents |
| --- | --- |
| [Primary manifest](../../tests/fixtures/continuous/step14-primary-manifest.json) | 10 seeds, four primary algorithms, nine declared fixture families and shared 500-call settings |
| [Consolidated machine-readable aggregate](step14-aggregate.json) | Complete primary rates, partial quartic counts, ablation rates and equal-time diagnostic status |
| [Ablation manifest](../../tests/fixtures/continuous/step14-ablation-manifest.json) | Replacement, dependency, HC-widening, population and fit-call controls |
| [Equal-time manifest](../../tests/fixtures/continuous/step14-equal-time-manifest.json) | 15-second optimizer deadline, one outer generation and 5000-call safety allowance |
| [Equal-evaluation records](step14-equal-evals/) | Per-run JSON/stdout and metadata; partial quartic cell means no aggregate summary was written |
| [Unary records and summary](step14-primary-unary/) | Full ten-seed sine/exp primary cells, metadata and summary |
| [Ablation records and summary](step14-ablation/) | 90 paired-control records, metadata and summary |
| [Deadline diagnostic records and summary](step14-equal-time/) | 60 records, metadata and summary; not a global equal-wall-clock comparison |
| [Initialization-failure smoke audit](step14-smoke/) | Preserved pre-fix empty-result outputs; these are invalid runs, not algorithm data |

The primary matrix ran against the corrected current MeTTa sources; per-batch
metadata records source, dataset and manifest hashes, runtime versions, commands
and worktree status. The first batch used the pre-timeout-fix Python harness;
its 6210-second wall-clock field on the timed-out quartic record shows the
wrapper failed to return promptly and **must not** be interpreted as hBOA runtime.
The subsequent runner
uses file-backed output and Windows process-tree termination; its deliberate
0.2-second timeout probe returned within three seconds. No algorithm `.metta`
source or fixture data changed during a batch.

## Equal-evaluation primary results

Ten paired seeds per complete row. “Success” means exact declared training and
held-out test threshold; medians include unsuccessful search runs. Calls are
total actual scorer invocations. Seconds are fresh-process wall time, including
PeTTa startup, CSV import, instrumentation and model fitting.

| Fixture | HC | Univariate | BOA | hBOA | Median calls HC / hBOA | Median seconds HC / hBOA |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `linear` | 10/10 | 10/10 | 10/10 | 10/10 | 28 / 58 | 2.05 / 2.70 |
| `multivariate` | 10/10 | 10/10 | 10/10 | 10/10 | 78 / 243.5 | 2.51 / 7.83 |
| `absolute` | 0/10 | 10/10 | 10/10 | 10/10 | 33 / 25.5 | 2.33 / 2.06 |
| `correlated` | 10/10 | 10/10 | 10/10 | 10/10 | 20 / 28 | 2.07 / 2.16 |
| `sr-cubic` | 10/10 | 10/10 | 10/10 | 8/10 | 37 / 253.5 | 2.21 / 6.91 |
| `sr-interaction` | 10/10 | 7/10 | 9/10 | 3/10 | 53 / 500 | 2.73 / 16.78 |
| `sr-sine` | 0/10 | 0/10 | 1/10 | 1/10 | 412 / 500 | 25.10 / 20.13 |
| `sr-exp` | 10/10 | 3/10 | 2/10 | 3/10 | 7 / 452 | 2.11 / 15.26 |

All successful primary runs also passed held-out thresholds. On failures, the
median held-out errors still matter: hBOA median test RMSE is 0.5 on interaction,
0.748 on sine, and 0.507 on exponential; HC's corresponding medians are 0.0,
0.784, and 0.0. Thus sine hBOA's one success is not a broad test-quality win,
while exponential's HC advantage is consistent in both exact success and test
error. On the absolute-error case, HC's median raw champion has training SSE
2.5 (training SAE 3.0) and test RMSE 1.227, while each EDA median is exact; this is not a
dependency-learning-only result because univariate and BOA solve it too.

Paired hBOA-minus-HC median scorer-call differences (10 seed pairs) are +29.5
on linear, +165.5 on multivariate, +216.5 on cubic, +447 on interaction, and
+445 on exponential. Bootstrap intervals for those medians are respectively
[28.5, 32], [150, 178.5], [142, 360], [438, 447] and [190, 493]. On sine the
median call difference is +85 [60.5, 101]. On these noisy-time Windows runs,
paired hBOA-minus-HC median process-wall differences are +0.627 seconds
[0.507, 0.809] for linear, +5.376 [4.426, 6.789] for multivariate, +4.690
[3.093, 8.072] for cubic, +14.031 [13.893, 14.497] for interaction, and
+13.161 [4.597, 15.616] for exponential. Intervals are paired percentile
bootstrap intervals, not independent-run confidence intervals; ten pairs
remain a modest sample.

### Partial quartic stress cell

Only nine results exist: HC 2/2 succeeded at a median 92 calls (the process
times are not used because the cell is incomplete); univariate 0/2 at median
441.5 calls; BOA 0/3 at 500; hBOA 0/1 at 500, plus one additional hBOA safety
timeout with no result. These counts are **not** directly comparable because
their denominators differ. The separate Step 13 exploratory study found HC 3/3
and each EDA 0/3, but it used only three seeds and did not have these Step 14
ablations. Do not pool them as a formal 10-seed result.

## What the ablations establish (and do not)

| Target / arm | Exact successes | Median calls | Median fitting seconds |
| --- | ---: | ---: | ---: |
| Interaction: HC | 5/5 | 53 | 0 |
| Interaction: HC widened | 5/5 | 53 | 0 |
| Interaction: univariate+RTR | 2/5 | 500 | 0.42 |
| Interaction: BOA+RTR | 1/5 | 500 | 35.27 |
| Interaction: hBOA+RTR | 1/5 | 500 | 4.30 |
| Interaction: hBOA, dependencies off | 2/5 | 500 | 0.37 |
| Interaction: hBOA, elitist | 3/5 | 312 | 2.49 |
| Interaction: hBOA, fit-call ceiling 1024 | 1/5 | 500 | 16.57 |
| Interaction: hBOA, population 64 | 1/5 | 500 | 4.41 |
| Sine: HC | 0/5 | 410 | 0 |
| Sine: HC widened | 5/5 | 63 | 0 |
| Sine: univariate+RTR | 1/5 | 500 | 0.78 |
| Sine: BOA+RTR | 0/5 | 500 | 30.72 |
| Sine: hBOA+RTR | 0/5 | 500 | 7.36 |
| Sine: hBOA, dependencies off | 1/5 | 500 | 0.91 |
| Sine: hBOA, elitist | 0/5 | 500 | 7.13 |

Interpretation:

1. **RTR is the clearest identified contributor on interaction.** On identical
   five-seed interaction cells, default BOA (elitist) succeeds 9/10 in the
   primary study, whereas BOA+RTR succeeds 1/5 in the ablation. hBOA+elitist
   improves from default hBOA+RTR's 1/5 to 3/5. RTR may over-preserve a locally
   similar incumbent and reject globally useful coefficient combinations; the
   logs show lower accepted-replacement counts, but this mechanism still needs
   a generation-level diversity/selection analysis.
2. **Dependency learning is implicated but not isolated as the only cause.**
   Turning it off raises interaction success from 1/5 to 2/5 and lowers median
   model-fitting time sharply, but remains below HC and hBOA+elitist. On sine,
   dependency-off gets 1/5 while default and elitist hBOA get 0/5. This is
   suggestive, not enough for a stable per-family rule.
3. **The default fit-call ceiling is not the sole explanation.** Raising
   `hboaMaxScoreCalls` from 256 to 1024 raises median fit time from 4.30 to
   16.57 seconds on interaction without increasing the 1/5 success count.
   Some extra fits stop differently, but fitting more is expensive and did not
   rescue the sampler under this budget.
4. **Simply enlarging the population did not rescue these cells.** The 64/32/32
   hBOA arm solves 1/5 interaction and 0/5 sine. This rejects “population 32 is
   obviously too small” as a sufficient explanation, not all population-size
   effects.
5. **HC configuration is a major confound.** Widened HC is 5/5 on sine at 63
   calls in this ablation; default HC is 0/5 at median 410 calls. Any final
   model-based-vs-HC claim should include both official default HC and a
   declared widened HC control.

These outcomes are consistent with a population method paying repeated model
fit and broad-sampling costs while its replacement rule suppresses useful
recombination, plus learned conditional splits being noisy on small selected
populations. The present logs do not prove that complete mechanism: the
ablation batch has five paired seeds, no univariate-selected diversity traces,
and no counterfactual replay of the same offspring under different replacement
policies. Fit traces should be interpreted as binding-cost evidence, not a
direct measure of model predictive correctness.

## Equal-time attempt: diagnostic, not qualification

The 60-run time study set `optimizerTimeLimitSec=15`, `maxGen=1`, and a 5000-call
safety allowance on linear and sine. `maxGen=1` deliberately makes one outer
MOSES expansion so the per-optimizer timer is not restarted across ten outer
iterations. This also changes search coverage: on linear, all three arms stop
after 26 HC / 49 EDA calls with median train SSE 10 and zero exact successes,
whereas the equal-evaluation full-MOSES runs all succeed. On sine, more model-
based candidates can be scored (median 340 hBOA, 530.5 dependency-off, versus
226 HC), but this is one expansion and several runs finish early. Process time
includes startup and is not a shared run-wide deadline. Therefore these records
are retained as an implementation diagnostic, **not evidence that hBOA has an
equal-time advantage**.

A proper equal-wall comparison needs a run-global deadline shared across
MOSES's outer expansions and local optimizer calls (or a genuinely fixed-deme
continuous entry point), with deadline exhaustion distinguished from
stagnation. It should then report both fixed-deme and full-MOSES results.

## Fix discovered during qualification

Before the trit-validator fix, identical live affine invocations returned
`(FinalResult ())`, with zero scorer calls and zero retained seeds, despite
older saved Step 11 logs showing scored programs. The cause was
`continTritsValid` calling `is-member` without the current trit and allowed
category list. This made the default genotype fail as `InvalidTrit`. The
validator now checks each head against `(0 1 2)`; the live affine smoke succeeds
and the field-schema/affine/pipeline/linear/SR/hBOA `.metta` suites show no
failing assertions. The comparison correctly stopped until this was fixed.

The benchmark harness was also changed to capture stdout to a file and kill
Windows child process trees on safety timeout, and to flag empty `FinalResult`s
as invalid reports. The Python regression suite now has 27 passing tests,
including a deliberately timed-out child process that returns within the
bounded test window.

## Step 14 remaining work

- Repair or replace the quartic hBOA timeout path, then run complete paired
  quartic cells with the required controls; use the fixed-timeout harness.
- Add noisy training fixtures with separate clean validation/test data and
  report predictive error and complexity, not only exact recovery.
- Add a continuous fixed-deme optimizer seam and a true run-global wall-clock
  limit; repeat equal-time HC/default HC widened/univariate/BOA/hBOA and causal
  controls.
- Expand the causal ablations to at least 10–30 paired seeds, especially
  dependency-on/off and RTR/elitist under otherwise identical hBOA settings.
- Instrument selected-set distinct genotypes, active-field coverage, learned
  split support/gain, duplicate tournament selections, candidate rejection by
  RTR, and target-vs-population/archive stagnation to test the proposed failure
  mechanisms directly.
- Do not change defaults from these partial and small-ablation results. Keep HC
  default; treat BOA/hBOA as opt-in and configuration-sensitive.

Reproduction (from repository root; each output directory must be new):

```powershell
python scripts/optimizer_comparison.py --petta-main ../PeTTa/src/main.pl --swipl 'C:/Program Files/swipl/bin/swipl.exe' --manifest tests/fixtures/continuous/step14-primary-manifest.json --output docs/benchmarks/step14-reproduction-primary --timeout 120
python scripts/optimizer_comparison.py --petta-main ../PeTTa/src/main.pl --swipl 'C:/Program Files/swipl/bin/swipl.exe' --manifest tests/fixtures/continuous/step14-primary-manifest.json --output docs/benchmarks/step14-reproduction-unary --cases sr-sine,sr-exp --timeout 120
python scripts/optimizer_comparison.py --petta-main ../PeTTa/src/main.pl --swipl 'C:/Program Files/swipl/bin/swipl.exe' --manifest tests/fixtures/continuous/step14-ablation-manifest.json --output docs/benchmarks/step14-reproduction-ablation --seeds 400,401,402,403,404 --cases sr-interaction,sr-sine --timeout 120
```

The archived outputs already exist; do not rerun into those same paths.
