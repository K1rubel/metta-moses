# Step 9: schema-aware univariate EDA

`--optAlgo=univariate` selects a new implementation under `optimization/eda/`.
The old `optimization/univariate/univariate.metta` and its tests are unchanged
and are not imported by the production entrypoint. HC remains the default.
BOA/hBOA and nonlinear `sr` are not enabled by this step. [Step 10](boa-optimizer.md)
subsequently adds BOA while retaining this implementation as the population-only control.

From the repository root on Windows:

```powershell
..\PeTTa\run.bat moses.metta -s --problem=linear --optAlgo=univariate --continDepth=2 --maxGen=10 --maxEvals=1000
..\PeTTa\run.bat moses.metta -s --problem=linear --optAlgo=univariate --inputFile=tests/fixtures/continuous/linear-train.csv --continDepth=2 --maxGen=10 --maxEvals=1000
```

## Modules and model

- `univariate-model.metta`: active-coordinate categorical fitting and sampling.
- `population.metta`: initialization, tournament selection, evaluated archive,
  replacement, resource enforcement, stopping and explicit RNG ownership.
- `univariate-optimizer.metta`: common six-argument adapter and CLI validation.

The engine accepts fitting/sampling function symbols. BOA/hBOA can replace those
functions and extend configuration/diagnostics without creating another scoring
or budget loop. RTR is a later replacement policy, not implemented here.

Each active coordinate has weights `count(value) + alpha`. Its distribution is
normalized using its own active observation count and schema cardinality. Empty
active samples give a uniform categorical fallback. Fields are not assumed to
have three values: discrete cardinalities are read from their knob schema.

For a continuous coefficient, only non-STOP prefixes activate later trits.
Inactive padding does not contribute to child counts. For selected samples
`(0 0), (0 0), (2 1)` and alpha 1, the first-coordinate weights are `(3 1 2)`;
the second-coordinate weights are `(1 2 1)`, not `(3 2 1)`. Sampling forces the
tail to zero after STOP and consumes no random draws for that inactive tail.
There are no learned cross-coordinate dependencies yet.

## Population and scoring policy

1. Validate settings/schema, canonicalize the supplied initial instance, and
   evaluate it first. Incoming deme instances are also considered. Attached
   input scores are not trusted across contexts; these instances are evaluated
   through the run cache, so existing cached results cost no scorer calls.
2. Fill toward the population size with bounded unique legal prior samples.
   The prior chooses a uniform prefix length per continuous coefficient and
   then fair LEFT/RIGHT values, not a uniform decoded real number.
3. Select valid candidates by tournament with replacement. Exact canonical
   population duplicates are removed, but intentional tournament multiplicity
   remains in the training data.
4. Fit active-coordinate marginals. Each offspring uses either the fitted model
   or, with the configured exploration probability, the legal prior.
5. Evaluate unseen canonical genotypes one at a time. Stop immediately at a raw
   target or resource boundary; reuse reduced-phenotype scores through the
   existing shared evaluator. Distinct genotypes with equal phenotypes can
   remain separate model observations. Invalid candidates never train a model.
6. Retain the best `populationSize` candidates from parents plus new valid
   offspring, ranked by penalized score then lower complexity. Exact ties keep
   incumbents. This is elitist truncation, not RTR or the old replace-worst code.
7. Repeat, retaining a separate archive of all evaluated valid genotypes. The
   archive preserves the raw champion even when penalized selection excludes
   it from the population. Deme output/merge caps do not resize the population.

The seen-genotype set includes invalid evaluated genotypes; repeated proposals
do not trigger repeated scoring or increase model weight. Archive, population,
seen set and fitted models are fresh for each representation/deme. The run-wide
phenotype cache remains reusable across compatible contexts.

## Settings and limits

These are explicit starting defaults, not experimentally optimized settings:

| Parameter | Default | Meaning |
| --- | ---: | --- |
| `edaPopulationSize` | 32 | Maximum active population |
| `edaSelectionSize` | 16 | Tournament winners used for fitting |
| `edaOffspringSize` | 16 | Requested new valid genotypes per generation |
| `edaTournamentSize` | 2 | Competitors per tournament |
| `edaPseudocount` | 1.0 | Positive weight added to each category |
| `edaExploration` | 0.1 | Probability of sampling the legal prior |
| `edaMaxRefillAttempts` | 256 | Maximum random proposals per initialization/refill |
| `edaStagnationGenerations` | 10 | Generations without improved penalized ordering |

Counts must be positive integers; offspring size cannot exceed population size.
Selection is with replacement, so selection size can exceed population size.
Alpha must be positive and safely finite for categorical weight sums; exploration
must be in `[0,1]`. Invalid settings fail before a CLI run, even with zero outer
generations. Common optimizer limits accept zero or `-1` as already specified.

Initialization counts as one local generation. Zero evaluation/proposal/time/
generation allowance performs no new work. Every proposal, including canonical
duplicates, counts toward the proposal limit. Scored failures cost one scorer
call; decode failures cost zero calls but consume proposals. All-invalid
initialization stops explicitly after its bounded refill, rather than looping.
Exhausted small canonical spaces stop early; when exact space size exceeds
2^31-1, resource/stagnation/refill safeguards remain authoritative.

Stagnation uses strict improvement in penalized score or a complexity tie-break,
not HC's relative-improvement threshold. A duplicate-only sampler therefore
terminates even if all external resource limits are unlimited. A singleton or
undersized valid population remains usable; a population need not reach its
requested size before fitting.

The monotonic deadline includes initialization, selection, fitting and sampling
after schema/configuration setup. It is cooperative: checks occur between
proposals and before scorer calls, not by interrupting an in-progress scorer or
model fit. Explicit optimizer RNG state is passed forward between demes; the
new sampler does not consume Python's global RNG. Representation builders and
stochastic action evaluators retain their own existing randomness.

`OptimizerDiagnostics` reports actual calls, proposals, cache hits and invalids.
`PopulationDiagnostics` adds generations, population/archive sizes, stagnation,
and `unretainedProposals` (duplicates plus any proposal left unevaluated at a
deadline). Model size is zero because there are no learned dependency edges.
`continTrace=True` still logs only actual continuous scorer invocations.

## Integration and tests

```powershell
..\PeTTa\run.bat optimization/eda/tests/univariate-test.metta -s
..\PeTTa\run.bat moses/tests/univariate-pipeline-test.metta -s
```

The model/boundary suite has 75 assertions; the pipeline suite has 27. They pin
categorical weights, deterministic samples, resource counts and stop reasons;
exercise inactive tails, heterogeneous fields, cache collapse, invalid/decode
failures, valid scores below the old sentinel, duplicate-only stagnation, raw
versus penalized champions, replay and Python RNG isolation. Pipeline tests pin
the four affine winners and zero training/validation/test errors under seed 0,
plus Boolean AND learning and an ant action winner.

Validation also passed 24 existing MeTTa suites (including the unchanged legacy
univariate tests), 15 Python tests, and six direct-runtime CLI rejection checks.
The four seed-0 CSV CLI runs reached zero raw error; scorer traces and reported
totals agreed exactly at 63, 292, 10 and 42 calls for linear, multivariate,
absolute-error and correlated fixtures respectively. These counts verify
accounting only, not comparative efficiency across optimizers.

Action integration exposed duplicate filtering that used a different
finalization path from action scoring. `keepTopActionCandidates` now compares
the same unreduced materialized action trees as scoring/merge; Boolean and
continuous duplicate filters remain unchanged. This prevents a failed action
filter from backtracking into another search and dropping its counted work.

These are correctness/integration checks, not a new paired-seed performance
comparison. Step 8 artifacts remain unchanged and describe their original
source snapshot. The baseline recorder is still HC-only. Step 10 adds BOA and
the controlled affine comparison; Step 11 adds hBOA/RTR and matched controls.
The current list-based archive/counting implementation favors auditability;
larger-scale profiling and model-fitting telemetry remain later qualification.

PeTTa's current `run.bat` can mask a nonzero SWI-Prolog exit status. Check actual
assertion counts and error output as well as the wrapper's exit code; use the
direct runtime command when verifying CLI exit-status behavior.
