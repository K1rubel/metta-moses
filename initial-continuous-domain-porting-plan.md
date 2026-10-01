# Continuous-Domain Porting and BOA/hBOA Integration Plan

## Goal and parity target

Port the continuous-domain path from OpenCog MOSES into `metta-moses` without weakening the existing Boolean and action domains. The reference behavior is the C++ implementation under `C:\Users\KirA\Desktop\iCog\moses`, especially the continuous knob/canonizer, `contin_bscore`, continuous interpreter, reduction rules, and optimization-improvement semantics.

The work is split deliberately:

1. Deliver a fully integrated **linear continuous MVP** that can learn affine expressions end to end.
2. Extend the representation and reducer to **nonlinear symbolic regression** and only then route the `sr` problem through the continuous path.

Alongside these representation milestones, build an optimizer track: shared optimizer services, an integrated univariate EDA baseline, BOA, then hBOA. BOA/hBOA optimize knob populations inside a deme. The outer MOSES loop continues to select exemplars, construct representations, optimize demes, and merge candidates. The linear milestone remains the first complete continuous test; nonlinear canonization and dependency learning are separate capabilities.

Keep `hc` as the default until comparative benchmarks justify changing it. Add `univariate`, `boa`, and `hboa` as explicit choices after their respective integration gates pass. Better sampling is a hypothesis to measure in both scorer calls and elapsed time.

The linear MVP is not presented as full C++ parity. In particular, the C++ continuous canonizer recursively creates polynomial/nonlinear basis terms, whereas an affine-only builder cannot implement `sr` faithfully.

### C++ parity anchors

Treat these files under `C:\Users\KirA\Desktop\iCog\moses` as the source of truth for the corresponding behavior:

| Concern | Reference |
|---|---|
| Trit values, continuous field layout, stepping, STOP handling, and `set_contin` | `moses/moses/representation/field_set.h`, `field_set.cc` |
| Continuous knob attachment/materialization | `moses/moses/representation/knobs.h`, `knobs.cc` |
| Linear versus nonlinear knob construction | `moses/moses/representation/build_knobs.cc` |
| Production step/expansion/depth and recentering | `moses/moses/representation/representation.cc` |
| Continuous error scoring and `min_improv()` | `moses/moses/scoring/bscores.h`, `bscores.cc` |
| Invalid-evaluation-to-worst-score behavior and penalty composition | `moses/moses/scoring/behave_cscore.cc` |
| Absolute versus relative improvement threshold | `moses/moses/optimization/optimization.cc` |
| Operator evaluation and pure/mixed vocabulary split | `moses/comboreduct/interpreter/eval.cc`, `interpreter.cc` |
| Active operator vocabulary, including inactive `ABS_LOG` | `moses/comboreduct/combo/vertex.h` |
| Continuous complexity weights | `moses/moses/moses/complexity.cc` |
| Continuous reduction rules | `moses/comboreduct/reduct/contin_rules.cc`, `contin_reduction.cc` |
| `sr` selecting nonlinear continuous construction | `moses/moses/main/demo-problems.cc` |
| CLI continuous defaults such as depth five | `moses/moses/main/problem-params.cc` |
| Population optimization and active univariate policy | `moses/moses/optimization/univariate.cc`, `moses/moses/eda/optimize.h` |
| Conditional model storage, sampling, and built-in continuous dependencies | `moses/moses/eda/local_structure.h`, `local_structure.cc` |
| Population replacement, including RTR | `moses/moses/eda/replacement.h` |

When the reference contains a constructor default and a later production override, the production path wins. Golden tests should cite the exact reference function and commit used to derive their expected result.

### BOA/hBOA reference boundary

The C++ tree contains useful conditional-model infrastructure, but `univariate` performs no learned structure search, `bde_local_structure_learning` is a commented-out implementation placeholder, and the active univariate optimizer uses `replace_the_worst` with RTR commented out. Fixed dependencies imposed by continuous encoding must be distinguished from dependencies learned from selected candidates.

Complete BOA/hBOA is therefore an extension beyond that active C++ optimizer path. Use the C++ code for representation semantics and reusable EDA mechanics; use [Pelikan's BOA/hBOA treatment](https://link.springer.com/book/10.1007/b10910) and [Pelikan and Lin, Section 2 and Figure 1](https://arxiv.org/pdf/cs/0402031) for algorithmic acceptance. hBOA combines Bayesian networks with local conditional structures and restricted tournament replacement. Its hierarchy is learned statistical structure; it is not automatically the program AST hierarchy.

## Reference semantics to preserve

### Continuous context

Use one explicit context value throughout selection, representation construction, optimization, evaluation, merging, and reporting:

```metta
(mkContinCtx $itable $errorType $complexityRatio $searchMode $targetScore)
```

Where:

- `$itable` is the existing column-major `mkITable` container.
- `$errorType` is `squared_error` or `abs_error`.
- `$complexityRatio` is the continuous complexity penalty coefficient.
- `$searchMode` is `linear` or `nonlinear`.
- `$targetScore` is normally `0`, because the best raw continuous score is zero.

Domain-dependent code must dispatch on the context or an explicit representation tag. It must not infer a continuous problem from incidental tree contents.

Keep optimizer configuration separate from this scoring context. `searchMode` controls the representation vocabulary; `optAlgo` controls how instances are searched. Changing `hc` to `boa` must not change the candidate's score or the score-cache key.

### Continuous AST

Represent an input variable by its exact table-column label. Do not introduce textual leaves such as `$1`, because `$...` is MeTTa pattern-variable syntax. The evaluator binds each label to the corresponding row value.

Use explicit continuous operator tags so continuous nodes cannot be confused with grounded arithmetic or the existing Boolean/action tree language:

```text
c_add, c_mul, c_div, c_sin, c_log, c_exp
```

Later mixed-domain work may add:

```text
c_if, c_gt_zero, c_impulse
```

The pure C++ continuous interpreter supports addition, multiplication, division, logarithm, exponential, sine, and random input. It does not expose cosine. Conditional, impulse, and greater-than-zero belong to the mixed evaluator and are outside the linear MVP.

### Evaluation and failure handling

Continuous evaluation must return an explicit result rather than silently substituting a number:

```metta
(mkCEvalOk $number)
(mkCEvalError $reason)
```

For evaluated operands, division by exactly zero with a nonzero numerator, logarithm of a non-positive number, exponential overflow, an unknown input label, malformed arity, and any non-finite result are evaluation failures. Tiny nonzero denominators are legal if the quotient is finite; there is no epsilon cutoff. Preserve the C++ short circuits: a zero division numerator returns zero without evaluating its denominator (including `0/0`), and multiplication stops once its running product is zero. As in the C++ scorer, one failed row makes the entire candidate receive the worst composite score. Operator implementations must not substitute values for encountered errors.

`log(x)` follows the current C++ vertex/interpreter behavior: `x <= 0` is invalid. `ABS_LOG` is not part of the active C++ vocabulary.

Addition and multiplication support n-ary expressions. Normalize empty addition/multiplication scaffolds to 0/1 before numerical scoring as an explicit port policy; C++ has special childless-operator placeholder returns for folding, which are not ordinary numeric identities. Division, sine, logarithm, and exponential must validate arity explicitly.

### Scores and improvement threshold

Match `contin_bscore`:

```text
row score       = -(prediction - target)^2    for squared_error
row score       = -abs(prediction - target)   for abs_error
raw score       = sum(row scores)
penalized score = raw score - complexityRatio * continTreeComplexity(tree)
```

These are negative SSE and negative SAE, not means. The best raw score is `0`. Keep the sign convention explicit so the pipeline does not negate an already negative error score.

Continuous score improvement must also match the C++ negative-threshold convention. Refactor the hill-climbing comparison behind a domain-aware operation such as:

```metta
(scoreImproved $context $newScore $oldScore)
```

For a non-negative threshold `t`, improvement means `new > old + t`. For a negative threshold `t`, it means:

```text
new > old - t * abs(old)
```

Use the C++ continuous default `-1e-4`. Preserve the current Boolean/action threshold behavior rather than replacing the global `hcScoreImprovedThreshold 0.5` for every domain.

### Continuous complexity

Do not reuse the Boolean `treeComplexity` unchanged. Add `continTreeComplexity` with the C++ weights:

- numeric constants and input arguments cost `1`;
- `c_div`, `c_exp`, `c_log`, `c_sin`, random input, equality, and conditional operators cost `1`;
- `c_add`, `c_mul`, `c_gt_zero`, and `c_impulse` cost `0`;
- all child complexities are accumulated recursively.

Match the C++ knob-probing exception: a product with a leading numeric zero has complexity zero and stops child traversal. Empty addition/multiplication nodes keep their zero operator cost. A reduced constant-zero leaf has cost one, so score the designated reduced phenotype consistently.

Only operators actually implemented in a milestone need executable clauses, but reserved weights should remain documented and tested when those operators are introduced.

## Continuous knob representation

### Production defaults

Use the defaults applied by the production C++ representation path, not only the constructor defaults:

```text
step size = 1
expansion = 2
depth     = 5
```

Keep them configurable through problem parameters. The current C++ `problem-params` continuous depth default is also five.

### Tree-level knob metadata and raw search fields

At each numeric constant leaf, store a typed continuous knob specification and the start offset of its raw trit slice. One acceptable shape is:

```metta
(mkCTK (mkContinSpec $mean $step $expansion $depth) $startIdx)
```

The raw optimizer still receives a flat `mkDscMp`, so existing neighborhood and crossover machinery can be reused. Each continuous knob contributes exactly `$depth` append-only entries:

```metta
(mkContinTritField $ownerId $offset)
```

Each field has multiplicity `3` and default `0`, with the canonical trit meanings:

```text
0 = STOP
1 = LEFT
2 = RIGHT
```

Required invariants:

- A representation with `n` continuous constants at depth `d` has exactly `n*d` continuous raw entries.
- `$startIdx` is the raw-map length immediately before that knob's fields are appended.
- Slices never overlap and insertion order is deterministic.
- All raw defaults decode to the current constant mean.
- Existing Boolean/action raw-field behavior remains unchanged.

Add `getKnobMultip`, `getKnobDefault`, and any raw-field-spec accessors for `mkContinTritField`. Update `representationExpandable` only through explicit dispatch; do not make every discrete map continuous by accident.

### Field schema and activation for population sampling

Expose a schema accessor over the raw map. For each coordinate it returns its index, cardinality, default, owner, kind, and activation rule. For continuous fields it also resolves the owner's start index, depth, and spec. Derive this information from the authoritative knob metadata rather than keeping conflicting copies.

The first trit of each knob is active. Trit `j > 0` is active only when every preceding trit in that knob is non-STOP. After the first STOP, canonicalize the entire remaining slice to STOP. For example, `[R, STOP, L, R, L]` and `[R, STOP, R, L, R]` both normalize to `[R, STOP, STOP, STOP, STOP]` without changing the decoded value.

Required behavior for all population optimizers:

- Enforce activation during initialization and sampling, then canonicalize before storage, learning, and duplicate checks.
- Distinguish an active choice of STOP from an inactive position whose stored value is STOP. Inactive child rows do not contribute observations of an active STOP decision.
- Represent inactive parent values explicitly in the model view, for example with a derived activity mask. Do not conflate inactive and active-zero parent states.
- Treat activation ordering as a fixed constraint. Learned dependency edges must preserve an acyclic sampling order together with those constraints.
- Read cardinalities from the schema; do not assume all fields are binary or ternary.
- Keep activation scoped to the owning knob. A STOP in one coefficient must not disable another coefficient.

For the initial population, include the all-default exemplar once and generate diverse legal instances. Make the continuous prefix-length prior explicit: a simple starting policy samples a length from `0..depth`, samples LEFT/RIGHT within that prefix, and pads with STOP. This is uniform over lengths, not over all legal vectors or decoded values. Compare alternative priors in benchmarks; independent uniform trits implicitly favor short prefixes.

### Stepper algorithm

Implement the C++ continuous stepper over a knob slice:

1. Start at `mean`, with `currentStep = step`.
2. Stop at the first STOP trit and ignore the suffix.
3. While every move so far is in the same direction, apply `currentStep` and then multiply it by `expansion`.
4. On the first opposite-direction move, divide the current step by `expansion * 2`, apply it in the new direction, halve it for the next move, and enter refinement mode.
5. In refinement mode, apply the current step for every subsequent non-STOP move and then halve it, regardless of whether the direction repeats or reverses.

For `(mean=0, step=1, expansion=2, depth=5)`, lock down at least these fixtures:

| Trit sequence | Decoded value |
|---|---:|
| `STOP` | `0` |
| `R` | `1` |
| `RR` | `3` |
| `RRR` | `7` |
| `RL` | `0.5` |
| `RLR` | `0.75` |
| `L` | `-1` |
| `LL` | `-3` |
| `LR` | `-0.5` |

Also test that suffixes after STOP are ignored and that invalid trits or slices produce a tagged decoding error.

The inverse/nearest encoding equivalent to C++ `set_contin` is useful for parity and initialization, but it is not a blocker for the first end-to-end MVP unless a caller requires it.

### Candidate materialization

`getCandidateHelper` must decode exactly the knob's raw slice and return a tree leaf:

```metta
(mkTree (mkNode $decodedNumber) ())
```

It must not return a bare number. Dead raw tails after STOP therefore materialize to the same tree. Materialization must happen before the complete-candidate cache lookup so equivalent phenotypes share the existing context-plus-tree cache key.

Re-centering needs no separate mutable phase. When selected exemplars are expanded into new demes, representation construction uses their current numeric constants as the new means and installs fresh STOP-default trit fields.

Optimizer populations and learned models initially live only for one deme optimization. Tag them with the representation identity/schema version and discard them when the representation is rebuilt. Coordinate indices, owners, and coefficient means can change across expansions. Cross-deme model transfer requires an explicit mapping and is deferred.

## Linear MVP canonizer and reducer

### Seed and linear form

Build the initial linear candidate from the numeric input labels and a bias term. The canonical shape should encode an affine expression equivalent to:

```text
bias + w1*x1 + ... + wn*xn
```

Every coefficient and the bias are continuous knobs. The exact tree nesting may follow existing `mkTree` conventions, but it must be deterministic and use the continuous operator tags.

The MVP canonizer may only add affine coefficient knobs. Name and document it accordingly; do not call this implementation the full C++ continuous canonizer.

### MVP reduction

Run continuous reduction after materialization and before caching or scoring. The first reducer must support:

- constant folding when the operation is valid and finite;
- additive and multiplicative identities;
- flattening/leveling nested `c_add` and `c_mul` nodes;
- safe inversion of division by a known non-zero constant;
- deterministic ordering of commutative children where required for cache-key stability.

This is an explicit MVP subset, not full C++ reduction parity. Later nonlinear work must add the relevant fraction normalization, factorization/distribution, sine/log/exp rewrites, commutative normalization, and mixed-domain rules before claiming comparable search behavior.

Step 6 safety qualification: reduction preserves encountered numerical failures and binary64 evaluation grouping. Leveling therefore applies to leftmost same-operator children, constant folding to valid closed expressions/leading constant runs, and commutative ordering to safe binary leaf cases. Do not move a zero ahead of an evaluated potentially failing subtree, reassociate arbitrary sums/products, or collapse `x/x`. Division inversion is limited to exact power-of-two denominators with finite nonzero reciprocals; general reciprocal rewrites can alter rounding and overflow. This is intentionally more conservative than C++'s unrestricted `reduce_times_one_zero`/`reorder_commutative` rules. Safe equivalent forms share keys; arbitrary algebraic equivalence is not promised.

The affine MVP canonizer accepts constants, declared labels, scalar-times-label terms, and flat sums with distinct features and at most one bias after safe reduction. It preserves existing term order and appends missing zero-valued bias/feature slots in declared-label order. Repeated terms, distribution, and unsafe nested-sum regrouping fail explicitly instead of silently altering numerical behavior. This grammar is closed over the builder's own materialized/reduced outputs; it is not a general algebraic affine-expression parser.

## Pipeline integration points

Continuous support is complete only when the context flows through every stage below.

### Representation construction and finalization

Update:

- `representation/build-knobs.metta` to route continuous contexts to the continuous builder rather than the logical builder;
- `representation/representation.metta` to finalize continuous candidates with continuous materialization and reduction rather than Boolean `cleanTree`;
- `representation/knob-representation.metta` with continuous raw-field multiplicity/default/spec accessors and slice decoding;
- `deme/expand-deme.metta` so initial instances, selected demes, optimizer contexts, merge contexts, cache resets, and initial evaluation counts all preserve the continuous context.

The continuous representation can remain structurally compatible with:

```metta
(mkRep (mkKbMap (mkDscMp $rawFields)) $annotatedTree)
```

This permits the current raw optimizer to operate on trits while continuous materialization owns phenotype construction.

### Optimization and scoring

Update:

- extract `materializeCandidateForContext`, `scoreMaterializedTree`, counted cached evaluation, and domain-aware improvement comparisons from `optimization/hillclimbing/hill-climbing-helpers.metta` into shared optimizer/scoring modules, then add continuous dispatch there;
- `deme/score-deme.metta` so continuous trees are reduced, evaluated row-by-row, and scored with the correct sign;
- `deme/merge-demes.metta` so `demeToTrees` recomputes or preserves continuous behavioral/composite scores correctly;
- the complete-candidate cache path so its key is the continuous context plus reduced materialized tree;
- any score ordering or termination checks that currently assume Boolean accuracy ranges.

Hill-climbing mutation, neighborhood generation, and crossover continue to operate on the flat trit vector. With depth five, its current maximum-distance default of four remains meaningful. EDA optimizers generate vectors from population models and have their own population and generation controls; `hcMaxDist` does not constrain a BOA sample.

### Problem routing and defaults

Update:

- `moses/demo-problems.metta` to build continuous contexts, use the affine seed for the linear MVP, set best/target raw score to zero, route symbolic regression only after nonlinear support is ready, and extend `optimizer-for` as each optimizer passes integration;
- `parameters/defaults.metta` with continuous step `1`, expansion `2`, depth `5`, complexity ratio, error type, search mode, and continuous improvement threshold defaults without changing existing domain defaults;
- `moses.metta` imports for the new representation, evaluator, scorer, reducer, and CSV hooks.

Audit every context pattern match. In particular, cover `createSelectedDemes`, `optimizerContextFor`, `mergeContextFor`, `resetDomainRunCaches`, initial score/evaluation bookkeeping, materialization, scoring, merge conversion, and run termination. A continuous problem must never fall through to the logical default branch.

## Shared optimizer contract and BOA/hBOA design

### Optimizer boundary

Introduce an optimizer-independent call/result contract, with adapters for existing public hill-climbing callers. A proposed shape is:

```text
optimize(deme, context, initialInstance, limits, rngState, optimizerConfig)
  -> mkOptimizerResult(optimizedDeme, bestInstance,
                       actualEvaluations, stopReason, diagnostics, nextRngState)
```

`limits` carries the local scorer-call allowance and proposal/generation/time limits. `bestInstance` uses penalized ordering; preserve the raw champion in the returned scored candidates for the outer loop's raw-target checks. Specify stable tie-breaking and empty-result behavior.

Replace `hillStateEvaluationCount` at the `optimizeDemeCounted` boundary with result accessors. Hill-climbing may retain its internal state tuple, but callers must not interpret it. The same local/global budget rules apply to all algorithms.

All optimizers use the same path:

```text
instance -> canonicalize inactive fields -> materialize -> reduce
         -> context-and-tree cache -> score on cache miss -> attach score
```

Use explicit unevaluated/evaluated row status. The current `scoreNeedsEvaluation` comparison with `worstCscore` cannot distinguish a new row from a legitimately evaluated invalid candidate. Cache failures as evaluated results too. If decoding fails before a tree exists, record the failure by representation identity and canonical instance and expose it separately in diagnostics.

The Phase 0 contract uses `candidatePending`, `candidateValid`, and `(candidateInvalid reason)` as the status field of `mkEvaluatedCandidate`. Both valid and invalid states are evaluated. Preserve this validity distinction in later selection/termination: the repository's legacy finite worst-score sentinel is not a lower bound on arbitrary continuous SSE. Never infer validity from score equality or introduce a separate continuous raw sentinel.

Check the remaining allowance before each actual scorer call, including initialization and local refinement. Cache hits cost zero calls; a new invalid candidate that reaches the scorer costs one. Return partial scored batches when the allowance is exhausted, without treating unevaluated rows as training data. Proposal and generation limits bound duplicate-only runs that spend no further scorer calls. Account for model-fitting time separately and check time limits between bounded fitting steps.

Selection and replacement use penalized fitness. Raw fitness governs target termination. The domain improvement predicate controls stagnation detection; explicitly handle initialization from a worst/non-finite score before applying the relative-threshold formula. Keep per-deme EDA generations distinct from outer MOSES expansion counts.

### Population loop

For each deme:

1. Build its field schema and initialize a diverse legal population, including the exemplar instance.
2. Evaluate through the shared counted service, stopping immediately if the raw target or budget is reached.
3. Select promising evaluated candidates, initially with configurable tournament selection.
4. Learn a model from selected canonical instances using the chosen policy.
5. Sample legal offspring in dependency order, respecting activation and field cardinalities.
6. Canonicalize, materialize, reduce, reuse cached scores, and evaluate new candidates within budget.
7. Replace population members using the selected replacement policy, retain champions, and update diagnostics.
8. Repeat until target, budget, time/proposal/generation limit, or declared stagnation; return scored candidates to the usual MOSES merge.

Separate population storage from the final deme candidate archive. Population size must not accidentally be truncated by archive/output settings intended for merging or reporting.

### Univariate baseline

Implement a clean schema-aware univariate optimizer under `optimization/eda/` before introducing learned dependencies. Leave `optimization/univariate/univariate.metta` and its tests untouched. The new implementation uses the shared contract, counted scorer, field schema and explicit RNG rather than the legacy helpers.

Learn one smoothed categorical distribution per active coordinate and enforce fixed activation constraints. This baseline has no learned cross-coordinate edges; it is still aware of the encoding's mandatory dependencies. Use configurable population/offspring sizes and selection pressure. Test normalized distributions, zero-count categories, unseen contexts, and deterministic seeded sampling.

### BOA model learning

The initial BOA implementation uses a categorical Bayesian network:

```text
P(instance) = product_i P(field_i | learnedParents_i, activationContext_i)
```

Use bounded greedy acyclic structure search with a decomposable BIC score initially. Cache local sufficient statistics and local model scores. Search legal edge additions and, where implemented, removals/reversals; specify deterministic tie-breaking. Limit learned parents per variable, conditional-table size, fitting iterations, and fitting time. Fixed activation dependencies participate in cycle checks even though they are not learned edges.

For an active child's conditional model, count only active-child rows and encode parent inactivity distinctly. With local active sample count `N_i > 0`, use a documented score of `logLikelihood_i - 0.5 * parameterCount_i * log(N_i)`. Count free parameters for permitted active contexts consistently across model comparisons. For zero-data contexts, use the declared prior/backoff instead of evaluating `log(0)` or inventing evidence.

Estimate sampling probabilities with positive Dirichlet pseudocounts and use explicit fallback distributions for unseen parent contexts. A configurable small fraction of legal fresh samples can preserve exploration. Start fitting from fixed constraints and an otherwise empty graph each generation; warm-starting is a later optimization.

The statistical penalty for network complexity is separate from MOSES's program-complexity penalty. The former regularizes a model of selected instances; the latter ranks candidate programs.

### hBOA local structure and replacement

Extend BOA with decision-tree conditional distributions: internal nodes test parent fields/activity, and leaves store categorical counts. Learn splits with a declared Bayesian/MDL-style local score, minimum support, and bounds on tree depth/leaves. Check the combined dependency graph for cycles whenever a split introduces a dependency. Fit compact context-specific dependencies instead of allocating every full parent configuration.

Add restricted tournament replacement (RTR): for each evaluated offspring, sample a population window, find its nearest member, and replace that member only if the offspring is better under the common comparison. Bound the window by the available population size and declare tie handling. Start with Hamming distance over canonical raw vectors, which ignores arbitrary dead-tail differences; record knob-normalized or decoded-value distances as later experiments. Preserve both champions outside replacement as needed.

Use the same RTR option with BOA during ablations to distinguish gains from learned local structure versus gains from replacement. A decision tree over fixed STOP dependencies alone does not satisfy the hBOA learning milestone.

### Duplicate weighting, invalid populations, and model lifetime

At population insertion, merge exact canonical-vector duplicates so arbitrary tails cannot increase their learning weight. Tournament selection may intentionally select the same member multiple times; retain that multiplicity as selection pressure. Different canonical vectors that reduce to the same program share an evaluation but are not automatically interchangeable model observations. Track this phenotype multiplicity and test an optional cap without silently changing the baseline policy.

Exclude invalid candidates from model fitting when valid candidates exist. If there are too few valid selected rows to fit a dependency model, back off to the smoothed univariate/prior sampler. An entirely invalid population triggers bounded legal reinitialization or an explicit stop reason. Bound initialization/refill retries when the legal or unique search space is smaller than the requested population.

Never reuse a model for a changed representation without a schema/meaning mapping. Re-centering, nonlinear scaffold expansion, and feature-selection changes all invalidate naive coordinate-based transfer.

### Configuration and diagnostics

Add separate optimizer parameters for population size, selection size/tournament pressure, offspring size, inner generation/stagnation limits, proposal/time limits, pseudocounts, exploration fraction, learned-parent/table-size limits, model search limits, local-tree support/depth/leaves, RTR window, and RNG seed handling. Validate combinations such as zero selection size or a window larger than the population. Choose initial numeric tuning defaults through benchmarks; do not present them as C++ parity requirements.

Report optimizer name, representation identity, outer expansion, inner generation, actual evaluations, proposals, cache hits, invalids, canonical/phenotype duplicates, effective population size, best raw/penalized scores, model edges/leaves, fitting time, total time, and stop reason. Count initialization and any refinement in the same evaluation totals.

An optional later hybrid may hill-climb selected offspring under a reserved sub-budget. Feed the refined instances and their attached scores back into the population. Benchmark it separately; uncharged local search must never appear as a BOA sampling improvement.

## Numeric CSV loading

Extend `scripts/csv_helper.py` with a separate continuous loader rather than weakening Boolean validation:

```text
load_continuous_table
```

It must:

- parse every feature and target cell as a finite number;
- treat the final column as the target by default, or move an exactly named `targetFeature` column last;
- preserve exact header labels as string labels for feature lookup, including whitespace and quoting;
- emit the existing column-major `mkITable` form;
- report malformed values with row and column information;
- reject NaN, infinity, binary64 overflow, missing cells, malformed rows, and empty/duplicate headers.

Boolean CSV loading and its current accepted values must remain unchanged.

Step 8 implements this contract through `read_continuous_table`,
`load_continuous_table`, and the tagged-error `load_continuous_table_result`
bridge. Numeric CSV requires explicit `--problem=linear`; supplying both
`inputFile` and `continTable` fails rather than choosing one silently.

## Proposed source layout

Keep continuous concerns separate enough to test directly while reusing generic pipeline machinery:

```text
representation/contin-spec.metta
representation/contin-stepper.metta
representation/field-schema.metta
representation/contin-canonize.metta
representation/build-contin.metta
scoring/contin-eval.metta
scoring/contin-score.metta
scoring/candidate-evaluation.metta
reduct/contin-reduct/contin-helpers.metta
reduct/contin-reduct/reduce-identities.metta
reduct/contin-reduct/reorder-commutative.metta
reduct/contin-reduct/reduce-nary.metta
reduct/contin-reduct/reduce-division.metta
reduct/contin-reduct/fold-constants.metta
reduct/contin-reduct/contin-reduction.metta
optimization/optimizer-contract.metta
optimization/eda/population.metta
optimization/eda/categorical-model.metta
optimization/eda/replacement.metta
optimization/eda/univariate-model.metta
optimization/eda/univariate-optimizer.metta
optimization/univariate/univariate.metta        # legacy implementation; leave unchanged
optimization/boa/boa.metta
optimization/boa/structure-learning.metta
optimization/hboa/hboa.metta
optimization/hboa/local-structure.metta
tests/representation/contin-stepper-test.metta
tests/representation/contin-representation-test.metta
tests/scoring/contin-eval-test.metta
tests/scoring/contin-score-test.metta
tests/scoring/candidate-evaluation-test.metta
tests/reduct/contin-reduct-test.metta
tests/integration/contin-linear-test.metta
tests/optimization/optimizer-contract-test.metta
tests/optimization/eda-sampling-test.metta
tests/optimization/boa-model-test.metta
tests/optimization/hboa-model-test.metta
tests/integration/optimizer-budget-test.metta
tests/integration/contin-optimizers-test.metta
```

Follow the repository's final naming and test conventions if they differ; the architectural separation is the requirement.

## Delivery phases and gates

Phases 0–7 describe continuous semantics and representation milestones. Optimizer milestones O0–O4 below share those foundations and have explicit dependencies. The final roadmap gives one recommended implementation order; nonlinear work does not depend on completing hBOA.

### Phase 0 — Freeze the semantic contract

- Record the C++ sources/functions used for each semantic decision.
- Add fixtures for stepper outputs, score sign, invalid evaluation, complexity, and improvement-threshold behavior.
- Confirm the column-major table/label contract.
- Specify optimizer result, evaluated-row status, RNG ownership, activation metadata, budget semantics, and per-representation model lifetime.

Gate: the fixtures distinguish negative SSE/SAE from mean error, production stepper defaults from constructor defaults, and continuous from Boolean threshold semantics. The optimizer contract specifies what is counted, cached, sampled, and reset.

### Phase 1 — Evaluator, score, and complexity

- Add continuous operator tags and row environment lookup by column label.
- Implement tagged success/failure propagation.
- Implement raw and penalized scoring plus continuous complexity.
- Add the domain-aware improvement predicate.

Gate: unit tests cover valid n-ary expressions, identity cases, unknown labels, divide-by-zero, invalid log, exponential overflow/non-finite results, negative SSE/SAE totals, best score zero, worst-score mapping, complexity weights, and relative improvement.

### Phase 2 — Raw trit fields and stepper

- Add the continuous spec and raw-field constructors.
- Implement multiplicity/default accessors and exact slice decoding.
- Materialize decoded values as tree leaves.
- Expose field schema/cardinalities/activation and implement canonical STOP tails plus legal diverse initialization.
- Add nearest/inverse encoding only if required by an active caller.

Gate: the exact stepper matrix above passes; STOP tails collapse to one materialized tree; invalid fields fail explicitly. Canonicalization is idempotent and phenotype-preserving. Sampling never activates a stopped suffix or crosses owner boundaries.

### Phase 3 — Linear canonizer and MVP reduction

- Construct a deterministic affine seed from table labels.
- Annotate every coefficient with its own knob slice.
- Implement the MVP continuous reducer and continuous finalizer.

Gate: for `n` features, the representation has `(n+1)*depth` raw fields, all defaults are STOP, slices do not overlap, the default phenotype equals the seed, and equivalent reduced expressions have identical cache keys.

### Phase 4 — Full pipeline wiring

- Thread `mkContinCtx` through deme construction, optimization, scoring, selection, caching, merging, and termination.
- Complete O0: route hill-climbing through the common result and counted evaluation service.
- Preserve the current Boolean/action branches and defaults.
- Verify recentering by rebuilding a representation around a selected continuous exemplar.

Gate: no continuous context reaches `buildLogicalRep`, Boolean `cleanTree`, Boolean scoring, or the absolute `0.5` hill-climbing threshold. Two raw vectors that differ only after STOP cause one actual tree evaluation when scored in the same context. The outer loop no longer reads hill-climbing state positions, and a cached invalid score does not trigger reevaluation.

### Phase 5 — Linear end-to-end milestone and numeric CSV

- Add the continuous CSV loader.
- Run a deterministic affine problem such as `y = 2*x + 1` with a fixed seed.
- Add a multivariate affine case and an absolute-error case.

Gate: the run improves toward raw score zero and recovers coefficients within the resolution reachable by the configured depth/step. Loading the same numeric data from CSV produces the same `mkITable` and score behavior. Existing Boolean/action regression suites remain green.

### Phase 6 — Nonlinear representation and reduction

- Port the recursive continuous canonizer behavior needed to introduce products/polynomial basis terms and supported unary operators.
- Expand reduction toward the C++ continuous rules.
- Add search-mode-aware vocabulary restrictions.

Gate: nonlinear mode can generate and retain a term equivalent to `x*x` starting from the designated seed, while linear mode cannot introduce nonlinear structure.

### Phase 7 — Symbolic-regression routing and parity

- Route `sr` through `(mkContinCtx ... nonlinear ...)`.
- Add low-order symbolic-regression fixtures with deterministic seeds.
- Compare decoded constants, reduced trees, raw scores, penalized scores, and invalid-candidate behavior against small C++ golden cases.

Gate: an order-two regression case is solved within declared tolerance, score signs and complexity penalties match the C++ fixtures, and no affine-only implementation is described as `sr` parity.

### O0 — Shared optimizer services

Depends on Phase 0; complete before Phase 4 closes.

- Introduce the optimizer contract, explicit evaluation status, shared counted scoring, and seeded RNG handling.
- Adapt hill-climbing and `optimizeDemeCounted`; preserve direct-call compatibility with adapters.
- Separate raw-target termination from penalized selection and expose generic stop reasons/diagnostics.

Gate: existing Boolean/action runs retain behavior; zero/tiny budgets, partial batches, cache hits, invalid scores, and multi-deme allocation are correct through the shared interface.

### O1 — Integrated univariate EDA

Depends on O0 and the field-schema portion of Phase 2. It can first be tested on existing discrete domains; continuous acceptance also requires Phase 4.

- Build a new univariate implementation with schema-defined cardinalities and activation; preserve the legacy module/tests unchanged.
- Add the reusable population lifecycle, smoothing, bounded refill, duplicate policy, and proposal/generation limits.
- Wire `optAlgo=univariate` with common scoring, results, and diagnostics.

Gate: seeded distribution tests and population tests pass; affine runs complete; empty/small/all-invalid/duplicate-only populations terminate correctly; actual evaluation totals match the shared scorer log.

### O2 — BOA dependency learning

Depends on O1; continuous comparisons use the Phase 5 baseline.

- Add bounded DAG structure search, local statistics/BIC scoring, smoothed conditional tables, and topological sampling.
- Enforce fixed activation constraints alongside learned dependencies.
- Wire `optAlgo=boa` and record model size/fitting time.

Gate: synthetic correlated categorical fixtures show that sampling preserves known dependencies more accurately than the univariate baseline; independent data does not routinely produce an unrestricted dense graph. Sampling is legal, model search is bounded, and equal-budget optimization results are reported across seeds.

### O3 — hBOA local structure and RTR

Depends on O2. It can be developed/tested before the nonlinear canonizer is complete.

- Add scored decision-tree splits, bounded local-model learning, and cycle-safe conditional sampling.
- Add RTR, champion retention, and declared canonical-vector distance/tie policy.
- Wire `optAlgo=hboa`; expose RTR to BOA for controlled comparisons.

Gate: context-specific dependency fixtures exercise learned local structure, RTR tests verify nearest-window replacement, and hierarchical/deceptive benchmarks report success, evaluations, and time. Fixed encoding trees alone do not pass this gate.

### O4 — Comparative qualification and optional hybrid

Depends on O3 and Phase 7 for the full continuous benchmark suite.

- Run `hc`, `univariate`, `boa`, and `hboa` on identical problem/representation settings with paired seeds and matched evaluation allowances.
- Repeat under time limits and report fitting overhead, invalids, and duplicate rates.
- Evaluate the optional budgeted local-refinement hybrid separately if implemented.

Gate: publish reproducible results and declared tolerances; keep hill-climbing as default unless evidence supports a change. Performance gains are reported for measured problem classes, not assumed for all continuous tasks.

## Test matrix

At minimum, maintain these groups:

1. **Stepper:** left/right expansion, first reversal, refinement after reversal, STOP, full-depth sequences, invalid trits, and production defaults.
2. **Representation:** raw length, slice ownership, deterministic order, default decoding, tree-leaf materialization, recentering, and dead-tail phenotype equivalence.
3. **Evaluation:** every implemented operator, label substitution, arity validation, non-finite propagation, invalid division/log/exp, and whole-candidate failure.
4. **Scoring:** negative SSE, negative SAE, zero optimum, complexity penalty, worst score, and relative improvement threshold.
5. **Reduction/cache:** constant folding, identities, leveling, deterministic commutative form, and one evaluation for equivalent materialized trees.
6. **Integration:** fixed-seed affine learning, multivariate input, numeric CSV equivalence, Boolean/action regressions, and later nonlinear symbolic regression.
7. **Field/model semantics:** heterogeneous cardinalities, active STOP versus inactive fields, independent knob activation, canonical-tail invariance, normalized probabilities, unseen contexts, and smoothing.
8. **Optimizer contract:** zero/tiny budgets, initialization accounting, partial batches, cached invalid scores, raw versus penalized champions, seeded replay, generic results, and model reset after representation rebuild.
9. **Learning/replacement:** known categorical dependencies, independent controls, local conditional splits, cycle rejection, parent/table/tree limits, RTR window/ties, and population-versus-archive size separation.
10. **Termination:** all-invalid populations, too few valid training rows, exhausted finite search spaces, duplicate-only generations, and bounded refill/model fitting.

For performance experiments, include independent discrete controls, interacting/deceptive discrete problems, correlated-feature affine data, and nonlinear regression after Phase 7. The simple `y = 2*x + 1` case is an integration check, not evidence of a BOA advantage. For correlated or non-identifiable data, assess prediction error rather than requiring unique coefficient recovery.

Use multiple recorded seeds, common initialization policies where applicable, fixed datasets/splits, identical complexity penalties, and identical representation depth/vocabulary. Report success rate at a declared raw-error tolerance, best raw and penalized fitness, actual scorer calls, proposals/cache hits, duplicate/invalid rates, fitting time, wall time, and model size. Distinguish calls from unique phenotypes and declare the cache policy, especially for stochastic action scorers. Include medians and spread; do not infer improvement from a single successful run. Compare BOA and hBOA with matched replacement as well as their intended configurations.

## Future continuous comparison: BOA/hBOA off versus on

This is a required staged experiment and analysis deliverable, **not a blanket claim of measured improvement**. Here, "off" means `optAlgo=hc`; "on" means selecting `optAlgo=boa` or, after Step 11, `optAlgo=hboa` instead of HC. It does not mean silently adding dependency learning to HC. A combined EDA/HC optimizer is the separate Step 15 hybrid experiment.

Step 10 now implements BOA and records the first affine subset of this protocol
in [the HC/univariate/BOA report](docs/benchmarks/continuous-boa-comparison.md).
Step 11 adds hBOA, matched-RTR and fixed-representation diagnostics. Steps 12–13
add bounded nonlinear construction and an exploratory polynomial comparison.
The broader nonlinear, noisy-data and equal-time qualification remains Step 14;
none of the initial results is a blanket dependency-learning benefit claim.

The comparison must answer two independent questions: **does the optimizer produce better regression programs for a fixed resource budget, and how much resource does it require to find a program of a specified quality?** BOA/hBOA do not expand the operator vocabulary or create a richer representation by themselves. Hold the available representation constant so a richer nonlinear scaffold cannot be mistaken for an optimizer improvement.

| Question | Required evidence |
| --- | --- |
| Are the returned programs more accurate? | Training raw SSE/SAE, held-out prediction RMSE/MAE, and success rate at predeclared error tolerances. Keep the configured summed-error objective distinct from normalized reporting metrics. |
| Are the programs simpler or more useful? | Final reduced expressions, continuous complexity, penalized score, and error-versus-complexity trade-offs. Report both the returned raw champion and penalized champion. Recover coefficients only on identifiable synthetic problems; structural similarity alone is not correctness. |
| Are good candidates found with fewer evaluations? | Actual scorer calls to first reach each target, success probability versus evaluation budget, and best-so-far error curves. Include initialization, invalid scored candidates, and any refinement. |
| Are good candidates found sooner? | Wall-clock time to the same targets and quality under equal time limits, including model fitting, sampling, decoding/reduction, cache lookup, scoring and merge. Fewer scorer calls do not automatically mean less elapsed time. |
| Why did performance change? | Model-fitting overhead, learned model size, proposals, active-field coverage, canonical/phenotype duplicates, invalid rates, cache hits, and population diversity. Use controlled ablations rather than attributing every gain to learned dependencies. |

#### Experimental controls

1. Freeze datasets, train/validation/test splits, target tolerances, seed list, resource budgets and reporting checkpoints before comparison. Use a planned 30 paired seeds per problem/configuration; disclose any smaller exploratory run rather than treating it as final qualification. Use validation data for tuning/candidate selection if needed, and keep test data out of optimization, stopping, model selection and tuning. A target used during search must be defined on the declared training/validation criterion, not the held-out test set.
2. Keep step/expansion/depth, vocabulary, canonizer/reducer, complexity penalty, scoring objective, cache policy, outer selection/revisit settings, and machine/thread configuration identical. Reset caches between independent runs. Record repository version, hardware and timing boundaries. Optimizers may follow different exemplar/recentering trajectories; that is part of their end-to-end effect, not a reason to force their trajectories to match.
3. Run two views: fixed-representation local-deme experiments to isolate sampling behavior, and full MOSES runs to measure final program quality including selection, recentering and merging. Use the same initial exemplar and charge each algorithm's initialization. Match initial populations across the EDA variants; do not pretend HC's single center and an EDA population are identical initialization or give EDA free initial evaluations. Paired seeds identify reproducible trials, not identical random draws across algorithms.
4. Compare **HC, univariate EDA, BOA and hBOA**. In addition to their intended settings, compare univariate/BOA/hBOA with matched population size, selection, initialization and RTR to separate learned dependencies from population search and replacement effects. A no-learned-dependencies control must retain mandatory STOP/inactive-tail constraints. Report BOA with and without RTR. Keep tuning effort comparable and separate tuning problems/seeds from final evaluation.
5. Perform equal-evaluation and equal-wall-time experiments separately. Record several error targets and budget checkpoints, not only the final winner. Predeclare sufficient proposal/generation safeguards so they do not silently substitute for the intended resource budget; log the actual stop reason. Include successes, failures, invalid-only runs and early stops. Treat unreached targets as failures/censored observations, not zero-cost successes, and do not compare only successful runs' average times.
6. Report paired differences, success rates, medians, spread and uncertainty across seeds. Report predictive validity/coverage on held-out rows; an invalid prediction is a failed output, not a row to omit. Publish representative wins, ties and losses, with actual simplified programs and their errors/complexity. Do not promise that BOA or hBOA will dominate HC on every problem.

#### Problem coverage and interpretation

Start with independent/identifiable affine controls, multivariate affine targets, correlated or non-identifiable features, and both squared/absolute error. After Step 13, include nonlinear interaction/polynomial cases and supported unary-function targets, plus a declared noisy-data generalization case. Only include targets reachable by the configured representation, or clearly label approximation-only tasks. The simple affine smoke test is a correctness control, not sufficient evidence of a modeling advantage.

The hypotheses to test are that coordinated sampling may help when successful coefficient/field settings depend on one another, and that hBOA's local conditional models may help where dependencies differ by context. They may also provide no gain or lose to HC because fitting and maintaining a population costs time. Learned trit dependencies are not automatically meaningful feature interactions or improved generalization. The report must distinguish **better final prediction**, **lower program complexity**, **fewer scorer calls**, and **less elapsed time**, including cases where these disagree.

#### Delivery milestones

- **Step 8:** define the protocol and record HC affine baselines, seeds, splits, tolerances, programs and resource traces. No BOA/hBOA results are required before those optimizers exist.
- **Step 10:** produce the first affine HC-versus-BOA comparison, with univariate EDA as the population-only control.
- **Step 11:** add affine hBOA comparisons and matched-replacement/dependency-learning ablations.
- **Steps 13–14:** repeat on supported nonlinear symbolic regression and publish the full comparative analysis in `docs/benchmarks/continuous-optimizer-comparison.md`, backed by machine-readable run logs/configurations, exported programs and reproducible commands. This report is a planned artifact, not yet generated.

Completion requires answering, per tested problem family, **what quality changed, how many evaluations and seconds were saved or lost, and whether the evidence supports enabling BOA/hBOA for that use case**. Keep HC as the default unless the results justify a change. A negative or mixed result is a valid completed comparison.

## Explicit non-goals for the linear MVP

The following are deferred and must not block the first integrated affine milestone:

- full recursive nonlinear canonization;
- the full C++ continuous/mixed reducer;
- mixed Boolean/continuous conditionals, impulses, and predicates;
- random-input semantics;
- exact C++ packed-bit storage, provided raw trit behavior is equivalent;
- inverse `set_contin` encoding unless required by initialization;
- completed BOA/hBOA implementations (their schema and shared-service prerequisites are required early, but their release gates are separate);
- search-performance parity.

The C++ `continmax` example may be used as a low-level knob/optimizer smoke test only. Its own source notes that it may be incomplete or broken, and it is not a program-learning acceptance benchmark.

Cross-deme model transfer, parameter-less population sizing, direct real-valued density models, and automatic AST-hierarchy learning are outside the initial BOA/hBOA extension. Optional local refinement is also a separate experiment. First deliver bounded categorical optimizers over the declared field schema.

## Definitions of done

### Continuous port

The continuous port is complete only when:

- the linear continuous pipeline works end to end without Boolean fallthroughs;
- raw trits decode with C++ production defaults and reversal/refinement semantics;
- invalid numerical evaluation produces a worst candidate score rather than a fabricated value;
- scores are negative summed errors with correctly signed complexity penalties;
- continuous complexity and relative improvement semantics are domain-specific;
- continuous reduction precedes cache lookup and scoring;
- numeric CSV input is finite, labeled, and column-major;
- recentering occurs naturally when selected trees become new deme exemplars;
- existing Boolean and action behavior remains intact;
- `sr` is enabled only after nonlinear term generation and its required reduction are implemented and tested against C++ fixtures.

### BOA/hBOA extension

The optimizer extension is complete when:

- `hc`, `univariate`, `boa`, and `hboa` use the common result, scorer/cache, budgeting, and RNG contracts;
- learned sampling respects cardinality, activation, canonical tails, and combined graph acyclicity;
- BOA learns cross-field dependencies and hBOA learns local conditional structures with RTR;
- model complexity regularization is distinct from candidate-program complexity penalties;
- evaluated invalid candidates remain evaluated, and duplicate-only runs terminate;
- rebuilding a representation resets incompatible model/population state;
- integration and regression gates pass, and comparative results include both evaluations and elapsed time;
- the implementation's deviations from the C++ path and chosen BOA/hBOA reference variants are documented.

## Step-by-step implementation roadmap

Follow this order for the first implementation. Each step ends with a reviewable change and a concrete completion check. Steps 12–13 can advance independently of the BOA/hBOA work after Step 9; the order below prioritizes proving the sampler first. Phase and O-milestone names above identify the corresponding acceptance criteria.

### Step 1 — Freeze contracts and reference fixtures

Record C++ reference commits/functions and the chosen BOA/hBOA variants. Specify the continuous context, field schema, optimizer input/result, evaluated-row status, score ordering, budget units, RNG ownership, and model lifetime. Add small expected-value fixtures for scores, the trit stepper, and representative conditional distributions.

Completion check: one written contract explains every boundary and distinguishes C++ parity requirements from optimizer extension choices. This closes Phase 0.

### Step 2 — Extract the shared evaluation service

Move materialization, domain scoring, cache lookup, and counted evaluation out of the hill-climbing helper module into `scoring/candidate-evaluation.metta`. Introduce explicit evaluation status, cache invalid results, stop before exceeding a budget, and return partial scored batches. Keep adapters where existing callers require them.

Completion check: repeated equivalent trees invoke the scorer once, cached failures are not rescored, and zero/one-call limits hold. Existing domain scoring tests pass.

### Step 3 — Make the optimizer boundary generic

Build on the existing `optimization/optimizer-contract.metta` records, adapt hill-climbing to produce the common result, and update `optimizeDemeCounted` and optimizer dispatch. Remove the outer loop's dependence on hill-state tuple positions. Thread RNG and limits, preserve raw and penalized champions, and record generic stop reasons.

Completion check: Boolean/action integration and multi-deme budgeting pass with hill-climbing through the new interface. This closes O0.

### Step 4 — Implement continuous evaluation and scoring

Add the continuous AST tags, label environment, tagged numerical evaluator, negative SSE/SAE scoring, complexity function, and relative improvement predicate. Connect them to the shared service from Step 2.

Completion check: hand-computed predictions/scores, invalid operations, complexity penalties, and relative-threshold cases pass. This closes Phase 1.

### Step 5 — Implement continuous fields, decoding, and legal sampling

Add continuous specs, one raw field per trit, schema accessors, activation rules, the exact stepper, tree-leaf materialization, and canonical STOP tails. Add a seeded legal-instance generator with an explicit prefix-length policy and bounds on refill attempts.

Completion check: defaults reconstruct means; slice counts/order are correct; reversal fixtures pass; canonicalization preserves decoded values; sampled coordinates obey cardinality and owner-specific activation. This closes Phase 2.

### Step 6 — Build the affine representation and reducer

Implement the affine seed/canonizer and the MVP continuous reducer/finalizer. Preserve knob scaffolding during representation construction, and reduce materialized phenotypes before score-cache lookup. When rebuilding a reduced exemplar, restore missing zero-weight feature slots so previously inactive terms remain searchable.

Completion check: an `n`-feature affine scaffold has `(n+1)*depth` raw fields, defaults preserve its phenotype, and rebuilding after zero-term reduction retains access to every input coefficient. This closes Phase 3.

### Step 7 — Wire the continuous problem through MOSES

Update selected-deme construction, optimizer/merge contexts, cache reset/seed handling, raw-target termination, imports, and defaults. Rebuild each selected exemplar with fresh knob means and fresh representation identity.

Completion check: a continuous run reaches scoring and merging without Boolean fallback, uses generic budget accounting, and recenters correctly on the next expansion. This closes Phase 4.

### Step 8 — Establish the linear baseline and numeric loader

Implement the finite numeric CSV loader and affine fixtures. Run `y = 2*x + 1`, a multivariate identifiable case, an absolute-error case, and a correlated-feature prediction case with hill-climbing. Freeze the future off-versus-on comparison protocol above and record HC baseline programs, splits, seeds, tolerances, evaluation/time traces and diagnostics.

Completion check: numeric CSV and in-memory data agree, affine learning meets declared tolerances, and Boolean/action regressions pass. This closes Phase 5 and establishes the comparison baseline.

### Step 9 — Integrate the univariate population optimizer

Build a new implementation using shared services and schema cardinalities, leaving
the old univariate files unchanged. Implement seeded initialization, tournament
selection, smoothed active-coordinate marginals, sampling, replacement, canonical
duplicate handling, champion retention, and bounded stopping/refill. Register
`optAlgo=univariate`.

Completion check: distribution fixtures pass; zero/tiny budgets and duplicate/all-invalid populations terminate; affine and existing discrete runs use the same scoring/budget rules as hill-climbing. This closes O1.

### Step 10 — Add BOA dependency learning and sampling

Implement categorical counts, decomposable local BIC scoring, bounded DAG search, cycle checks including activation constraints, smoothed conditional tables, and topological sampling. Add fitting diagnostics and `optAlgo=boa`.

Completion check: synthetic dependency fixtures distinguish BOA sampling from independent sampling, generated instances remain legal, all model limits hold, and discrete/affine benchmarks run under equal evaluation budgets. Deliver the first affine HC-versus-BOA quality/efficiency comparison, including the univariate control and elapsed-time overhead. This closes O2.

### Step 11 — Add hBOA local models and RTR

Implement scored decision-tree splits, minimum support, depth/leaf bounds, and cycle-safe local-model sampling. Implement restricted tournament replacement with the declared canonical-vector distance and champion retention. Register `optAlgo=hboa`; allow BOA with RTR for ablation.

Completion check: learned context-specific dependencies and RTR behavior pass direct tests; hierarchical/deceptive benchmark results include fitting overhead, success rates, and scorer calls. Extend the affine comparison to hBOA, with matched-replacement and no-learned-dependencies controls. This closes O3.

### Step 12 — Extend continuous construction to nonlinear terms

The builder/reducer suite has 52 explicit assertions, including `x*x` from zero,
all 27 depth-one quadratic instances rebuilding stably, and legal vectors for
interactions, cubic/quartic terms, nested sine, log, exp and rational targets.
This closes the bounded Phase 6 gate, **not** the complete C++ recursive
coefficient canonizer or algebraic reducer. See
[scope and limits](docs/nonlinear-continuous.md).

Port the recursive scaffold needed for products/polynomial terms and supported unary operators. Extend reduction and vocabulary restrictions. Reuse the field schema, common scoring, and optimizer interfaces; newly built representations start with fresh populations/models.

Completion check: nonlinear mode can expose `x*x` from the designated seed, linear mode remains affine, and all implemented optimizers accept the new schema without specialized scoring branches. This closes Phase 6.

### Step 13 — Enable and validate symbolic regression

All 33 selected MeTTa suites pass (1374 assertions), along with 25 Python tests.
Eight disjoint-split nonlinear fixture families and an independent numerical
checker prepare the full study. The [Step 13 exploratory report](docs/benchmarks/continuous-nonlinear-smoke.md)
records the harder polynomial comparison separately from correctness. This
closes the bounded Phase 7 integration/fixture gate; Step 14 remains next.

Exploratory outcome: 36 audited runs (three polynomial families × three paired
seeds × four optimizers), each with a 500-call allowance. HC solved 9/9; each
population method solved 6/9, missing all quartic targets. HC also consumed fewer
calls and less elapsed time on the solved families. All hBOA fits and quartic BOA
fits hit the configured score-call limit. This is evidence for these bounded
settings, not a general dependency-learning verdict. Source/data hashes were
unchanged; no runtime/report failures were discarded. Seven invalid CLI cases
were rejected and all four optional-function CLI vocabularies were accepted.

Route `sr` to nonlinear context, add an order-two regression problem, and compare small C++ golden cases for decoded constants, reduced trees, errors, penalties, and invalid candidates. Run all optimizer choices against the same representation settings.

Completion check: the nonlinear reference cases meet declared correctness tolerances and the regression target is reachable. Algorithm comparisons remain separate from semantic parity. This closes Phase 7.

### Step 14 — Qualify sampling improvements with controlled benchmarks

The results do **not** qualify the entire protocol. The quartic cell is partial
after a safety timeout; the deadline diagnostic is not a true run-global
equal-wall-clock comparison; noisy-data studies and a continuous fixed-deme
study are still absent; and causal ablations have only five paired seeds.
HC remains the default. The comparative results, per-run machine-readable
records, manifests, hashes, reproduction instructions, interpretation and
remaining work are documented in
[the Step 14 report](docs/benchmarks/step14-comparative-analysis.md).

After the standalone optimizers are qualified, allocate a declared fraction of a deme's remaining budget to hill-climbing selected offspring. Return refined genotypes and scores to the population and include every refinement evaluation in the common totals.

Completion check: compare the hybrid with standalone hBOA and hill-climbing under identical total evaluation/time limits. This is an optional follow-on and is not required to complete the continuous port or standalone BOA/hBOA extension.
