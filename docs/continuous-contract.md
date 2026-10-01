# Continuous Domain & BOA/hBOA Semantic Contract

**Document Version:** 1.13.0  
**Comparison:** Initial affine/linkage comparisons complete; nonlinear exploration in Step 13; full qualification remains Step 14  
**Progress:** Affine and bounded nonlinear search, numeric CSV, univariate EDA, BOA and bounded hBOA implemented  
**Project:** `metta-moses` Continuous-Domain Port and Optimizer Extension  
**Reference C++ Commit:** `f88ccd3279f3dd853e8c23103be5376a0e7eafc1` at `C:\Users\KirA\Desktop\iCog\moses`  

---

## 1. Executive Summary & Architectural Scope

The continuous-domain port brings numeric function learning and symbolic regression capabilities from OpenCog C++ MOSES into `metta-moses` while strictly preserving the existing Boolean and action-domain behavior.

This contract provides the authoritative specification for:
1. **C++ Parity Boundaries:** Production stepper semantics, continuous scoring, complexity calculations, evaluation failure handling, and domain-aware improvement thresholds, with the documented bounded representation and conservative reduction differences. Full C++ scaffold/algebraic parity is not claimed.
2. **Optimizer Extension Boundaries:** Extension beyond C++ MOSES to implement a shared optimizer contract supporting Hill-Climbing (`hc`), an integrated Univariate EDA (`univariate`), Bayesian Optimization Algorithm (`boa`), and hierarchical BOA with Restricted Tournament Replacement (`hboa`).

```text
+--------------------------------------+--------------------------------------+
|                              MOSES Outer Loop                               |
|  (Exemplar Selection -> Deme Creation -> Representation -> Optimization     |
|                                    -> Merge)                                |
+--------------------------------------+--------------------------------------+
                                       |
                                       v
+--------------------------------------+--------------------------------------+
|          C++ Parity Boundary         |     Optimizer Extension Boundary     |
| - Field set & raw trits              | - Shared optimizer contract          |
| - Contin stepper state machine       | - Explicit evaluation status         |
| - Affine & nonlinear trees           | - Univariate categorical EDA         |
| - contin_bscore (SSE / SAE)          | - BOA Bayesian network learning      |
| - continTreeComplexity               | - hBOA local decision trees + RTR    |
| - Relative min_improv (-1e-4)        | - Threaded pure RNG state            |
| - Column-major ITable                | - Deme-scoped model lifetime         |
+--------------------------------------+--------------------------------------+
```

---

## 2. C++ Source of Truth & Reference Anchors

All parity behaviors are pegged to commit `f88ccd3279f3dd853e8c23103be5376a0e7eafc1` of the C++ MOSES repository (`C:\Users\KirA\Desktop\iCog\moses`).

| Concern | Reference File & Function | Key Semantic Rules |
|---|---|---|
| **Trit Values & Stepper** | `moses/moses/representation/field_set.h` (`contin_spec`, `contin_stepper`, L180-275) | Trits: `0=STOP`, `1=LEFT`, `2=RIGHT`. First reversal divides step by `expansion * 2` before the move and halves it afterward. |
| **Production Stepper Defaults** | `moses/moses/main/problem-params.cc`, `moses/moses/representation/representation.cc` | `step_size = 1.0`, `expansion = 2.0`, `depth = 5`. `build_knobs.h` constructor defaults are step 1, expansion 1, depth 4. |
| **Knob Attachment & Metadata** | `moses/moses/representation/knobs.h`, `moses/moses/representation/field_set.cc` | Each continuous knob occupies a contiguous slice of `depth` raw fields. |
| **Continuous Scoring** | `moses/moses/scoring/bscores.h`, `moses/moses/scoring/bscores.cc` (`contin_bscore`) | Negative per-row squared/absolute errors; aggregate by summing; raw best score is `0.0`. |
| **Evaluation Failure** | `moses/moses/scoring/behave_cscore.cc` (`behave_cscore::operator()`) | Evaluation exceptions map to the worst composite score. Keep failures tagged until this boundary. |
| **Numerical evaluation** | `moses/comboreduct/interpreter/interpreter.cc` (`contin_interpreter::contin_eval`) | Division uses exact zero semantics and short-circuits a zero numerator; multiplication short-circuits a zero product. |
| **Relative Improvement** | `moses/moses/optimization/optimization.cc` (`score_improved`) | For negative threshold `t`, require `new > old - t * abs(old)`; otherwise require `new > old + t`. Continuous `min_improv()` is `-1e-4`. |
| **Continuous Complexity** | `moses/moses/moses/complexity.cc` (`tree_complexity`, L56-111) | Constants/arguments cost 1; specified operators cost 0 or 1. A leading-zero product stops recursion with cost 0. |
| **Linear vs Nonlinear Scaffolding** | `moses/moses/representation/build_knobs.cc` | Recursive continuous canonization. The port's affine MVP is a deliberate subset; nonlinear mode adds further terms. |
| **Univariate EDA Baseline** | `moses/moses/optimization/univariate.cc`, `moses/moses/eda/optimize.h`, `moses/moses/eda/local_structure.h` | No learned cross-field structure; continuous encoding still imposes fixed dependencies. |

---

## 3. Algorithmic Acceptance for BOA and hBOA

In C++ MOSES, `bde_local_structure_learning` was an incomplete placeholder and `univariate` did not learn dependencies. To provide competent search over complex continuous representations:
- **BOA (Bayesian Optimization Algorithm):** A bounded categorical BOA variant informed by [Pelikan (2005)](https://link.springer.com/book/10.1007/b10910); BIC is this port's chosen initial model score, not a claim of exact algorithmic identity. Learns a Directed Acyclic Graph (DAG) over active coordinates using greedy structure search with a decomposable Bayesian Information Criterion (BIC) metric:

  ```text
  Score(B) = sum over i in 1..n of
               [ log L_i(data | parents(X_i))
                 - 0.5 * abs(param_i) * log(N_i) ]
  ```

  Probabilities are smoothed using Laplace/Dirichlet pseudocounts. Sampling occurs in topological order respecting activation constraints.
- **hBOA (Hierarchical BOA):** Replaces full conditional probability tables with local decision tree models per variable. Each split tests an active parent value and is evaluated via MDL/BIC split gain. Offspring are integrated into the population via Restricted Tournament Replacement (RTR):
  - An offspring is compared against the nearest candidate in a sampled population window based on Hamming distance over canonical vectors. Configure an integer window with `1 <= W <= actualPopulationSize` for a nonempty population; an empty population follows bounded initialization/termination. Do not let a heuristic round to zero for small populations. Replace only when the offspring is better; ties retain the incumbent. See [Pelikan and Lin, Section 2](https://arxiv.org/pdf/cs/0402031).
- **Independence of Regularization:** Model complexity penalties (BIC / MDL) regularize the statistical dependency graph; program complexity penalties regularize candidate ASTs. These two metrics are completely separate.

---

## 4. Continuous Context Specification

A continuous run is governed by an explicit context structure threaded through every stage:

```metta
(mkContinCtx $itable $errorType $complexityRatio $searchMode $targetScore)
```

### Parameters:
1. `$itable`: Column-major input table:

   ```metta
   (mkITable ($col1 $col2 ... $targetCol) ($label1 $label2 ... $targetLabel))
   ```

   All feature values and the target column are finite floating-point numbers.
2. `$errorType`: Symbol, either `squared_error` or `abs_error`.
3. `$complexityRatio`: Non-negative float penalizing continuous tree complexity:

   ```text
   CompositeScore = RawScore - complexityRatio * continTreeComplexity(tree)
   ```

4. `$searchMode`: Symbol, either `linear` (affine MVP) or `nonlinear` (polynomial / trigonometric).
5. `$targetScore`: Raw termination threshold, default `0.0`.

### Invariants:
- Problem domain MUST be checked via context matching `(mkContinCtx ...)`. Incident AST structure must never be used to guess the domain.
- `searchMode` controls tree scaffolding and reduction rules. It does NOT alter the optimizer algorithm (`optAlgo`).
- Scoring-context identity includes the data and scoring settings, but excludes optimizer tuning. All columns must have equal nonzero length, labels must be unique, and the final column is the target. Step 8 validates numeric CSV and moves an explicitly named target to that final position.

---

## 5. Continuous AST & Evaluation Contract

### Continuous Operator Tags
To prevent collisions with grounded arithmetic or Boolean operators:
- N-ary: `c_add`, `c_mul`
- Binary: `c_div`
- Unary: `c_sin`, `c_log`, `c_exp`
- Leaves: Exact input feature labels (e.g. `x`, `temp`, `pressure`) or numeric constant nodes `(mkNode $value)`.

### Evaluation Return Shapes
Continuous evaluation returns an explicit status wrapper:
- Success: `(mkCEvalOk $number)`
- Failure: `(mkCEvalError $reason)`

### Evaluation Invariants:
- Division with a nonzero numerator and exactly zero denominator: `(mkCEvalError "DivisionByZero")`. Tiny nonzero denominators are valid when the quotient is finite; there is no epsilon cutoff.
- C++ evaluates a division numerator first and returns zero immediately for a zero numerator, without evaluating the denominator. Thus `0/0` also returns zero on this path. Multiplication evaluates left to right and skips remaining children once its product is zero. These short circuits are reference semantics, not substitutes for encountered errors.
- Logarithm of a non-positive argument: `(mkCEvalError "LogNonPositive")`.
- Encountered non-finite inputs/results, including overflow: `(mkCEvalError "NonFinite")`. The port explicitly checks row-error accumulation too; finite predictions can still overflow a squared error or total.
- Unknown evaluated feature label: `(mkCEvalError "UnknownLabel")`.
- Arity mismatch: `(mkCEvalError "ArityMismatch")`.
- Empty `c_add`/`c_mul` scaffolds should normalize to 0/1 in the port's reducer before numerical scoring. This is an explicit normalization policy: C++ has special childless-operator placeholder returns for folding, not ordinary evaluated 0/1 leaves. Do not describe those placeholder returns as numeric-identity parity.
- **Whole-Candidate Failure Rule:** A row returning `mkCEvalError` stops further row evaluation and maps to `(worstCscore)` at the composite-scoring boundary, preserving invalid/evaluated status. Step 4 implements this mapping, row evaluation, and aggregation.

The repository's existing `(worstCscore)` uses a finite `-1e100` sentinel; the C++ type uses its numeric type's lowest value. Neither licenses introducing a separate `-1e9` sentinel. Valid negative SSE can fall below a finite sentinel, so the shared candidate layer must prefer valid candidates by explicit status and must never infer evaluation status from score equality. Global legacy-score migration is outside Phase 0.

---

## 6. Continuous Knob Representation & Stepper State Machine

### Knob Metadata
Each numeric constant leaf is backed by a continuous knob specification:

```metta
(mkCTK (mkContinSpec $mean $step $expansion $depth) $startIdx)
```

- `$mean`: Center value (number).
- `$step`: Initial step size (production default: `1.0`).
- `$expansion`: Step multiplier during unidirectional moves (production default: `2.0`).
- `$depth`: Number of raw trit fields (production default: `5`).
- `$startIdx`: Non-negative integer offset in the flat discrete map `mkDscMp`.

### Raw Trit Fields
Each knob allocates exactly `$depth` consecutive raw fields:

```metta
(mkContinTritField $ownerId $offset)
```

- Multiplicity: 3 (`(mkMultip 3)`).
- Default value: 0 (`(mkDiscSpec 0)`).
- Semantics: `0 = STOP`, `1 = LEFT`, `2 = RIGHT`.

### Stepper Algorithm
Given initial state, then for each trit `t_i` in `[t_0, ..., t_{d-1}]`:

```text
initial:
  value        = mean
  current_step = step
  all_left     = true
  all_right    = true

for each trit t_i in [t_0 .. t_{d-1}]:

  if t_i == 0  (STOP):
    terminate decoding immediately; return value

  if t_i == 1  (LEFT):
    if all_left:
      value        = value - current_step
      current_step = current_step * expansion
      all_right    = false
    else:
      if all_right:
        all_right    = false
        current_step = current_step / (expansion * 2)
      value        = value - current_step
      current_step = current_step / 2

  if t_i == 2  (RIGHT):
    if all_right:
      value        = value + current_step
      current_step = current_step * expansion
      all_left     = false
    else:
      if all_left:
        all_left     = false
        current_step = current_step / (expansion * 2)
      value        = value + current_step
      current_step = current_step / 2
```

### Canonicalization Invariant
Any trit occurring after the first `STOP` is inactive dead tail. To guarantee cache hit consistency, canonicalization rewrites all trits after the first `0` to `0`:

```text
[2, 0, 1, 2, 1]  --canonicalize-->  [2, 0, 0, 0, 0]
```

Materialization maps the decoded numeric value directly to a tree leaf:

```metta
(mkTree (mkNode $decodedNumber) ())
```

Step 5's schema exposes coordinate index, cardinality, default, owner, offset, owner spec/start/depth, and activation. The first trit is active; later trits are active only while all earlier trits in that owner are non-STOP. The model view distinguishes active STOP from an inactive stored zero, allowing later learners to mask inactive child observations and distinguish inactive parent values. Sampling enforces these fixed dependencies before learning additional ones. `contin-spec.metta` supplies the records; `contin-stepper.metta`, `contin-representation.metta`, `field-schema.metta`, and `optimization/legal-instance-sampling.metta` implement their production behavior.

---

## 7. Continuous Complexity & Improvement Threshold

### Complexity Function: `continTreeComplexity`
Recursive complexity weight accumulation:
- Leaves (numbers, variables): cost = 1.
- `c_add`, `c_mul`: cost = 0.
- `c_div`, `c_exp`, `c_log`, `c_sin`: cost = 1.
- Subtree complexity = operator weight + sum of child complexities.
- Empty `c_add`/`c_mul` remain zero-cost operator nodes. A `c_mul` with a leading numeric zero has complexity 0 without visiting later children, matching the C++ knob-probing shortcut. This differs from complexity after reduction to a constant-zero leaf (cost 1); score the designated reduced phenotype consistently.

### Domain-Aware Improvement Predicate: `scoreImproved`
Given `S_new`, `S_old`, and threshold `t`:
- **Non-negative threshold (`t >= 0`, Boolean/Action default `+0.5`):**

  ```text
  Improved  <=>  S_new > S_old + t
  ```

- **Negative threshold (`t < 0`, Continuous default `-1e-4`):**

  ```text
  Improved  <=>  S_new > S_old - t * abs(S_old)
  ```

---

## 8. Shared Optimizer Boundary Contract

To support `hc`, `univariate`, `boa`, and `hboa` interchangeably:

### Optimizer Signature

```metta
(optimizeDeme $deme $context $initialInstance $limits $rngState $optimizerConfig)
```

### Return Shape

```metta
(mkOptimizerResult $optimizedDeme $bestInstance $actualEvaluations $stopReason $diagnostics $nextRngState)
```

`bestInstance` is an instance, not an evaluated-candidate wrapper; it is `()` when no scored candidates exist. The optimized deme also retains the raw champion. Stop reasons are inert `OptimizerStopReason` atoms (`stopTargetReached`, `stopBudgetExhausted`, `stopProposalsExhausted`, `stopGenerationsExhausted`, `stopTimeExhausted`, `stopStagnation`, `stopAllInvalid`, `stopExhaustedSpace`). Diagnostic constructors remain inert records, following the repository type convention.

Limits use `(mkOptimizerLimits maxEvals maxProposals maxGenerations timeLimitSec)`. Counts are integers >= 0 or -1 for unlimited; time is >= 0 or -1. Zero allows no work in that category. Check before each scorer call, including initialization/refinement, and return the evaluated portion of a partial batch. Cache hits cost zero calls, newly scored failures cost one, and decoding failures before scoring are separate diagnostics. Proposal/generation/time limits bound duplicate-only loops. Count population generations separately from MOSES expansions. The records themselves are inert; Step 3's runtime validates limits and the common HC adapter enforces them.

### Invariants:
1. **Budget Accounting:** `$actualEvaluations` counts only actual calls to the scoring function. Cache hits cost 0 evaluations.
2. **Evaluated Status:** Candidates carry explicit evaluation status:

   ```metta
   (mkEvaluatedCandidate $instance $tree $compositeScore $status)
   ```

   Status is `candidatePending`, `candidateValid`, or `(candidateInvalid reason)`. Pending tree/score may be `()`. Both valid and invalid states are evaluated, so cached failures do not trigger another scorer call. A valid score equal to the finite sentinel remains valid. `candidateIsEvaluated` and `candidateIsValid` expose these separate properties. Context/cache-lifetime changes invalidate attached scores; "evaluated" is not a permanent global property.
3. **Model Lifetime:** Learned Bayesian networks or decision trees belong strictly to the current representation. When an exemplar is selected and a new representation is constructed with updated means, all population models are discarded and re-initialized.
4. **Dual Champions:** `$bestInstance` selection and internal tournament selection use **penalized score** (`S_raw - penalty`). MOSES outer-loop termination checks use **raw score** (`S_raw >= targetScore`).
5. **RNG Ownership:** Optimizers consume an explicit state and return the next state. Step 3 defines the Park–Miller stream and routes common-contract HC sampling through it. Identical seeds only promise replay with fixed draw order and evaluation/proposal limits; wall-clock stops and stochastic evaluator state require additional controls.
6. **Model Training:** Only evaluated valid candidates train a model. Canonical-vector deduplication precedes selection; intentional tournament multiplicity retains selection pressure. Phenotype caching reuses scores without equating all distinct genotypes. Too few valid rows trigger the declared prior/univariate fallback, and all-invalid/refill loops are bounded.

---

## 9. Reference Fixture Matrix

The following fixture values must be verified by automated unit tests.

### 9.1 Continuous Stepper Fixtures
Spec: `(mkContinSpec 0.0 1.0 2.0 5)` (mean=0.0, step=1.0, expansion=2.0, depth=5)

| Trit Vector | Moves | Value | Note |
|---|---|---:|---|
| `[0, 0, 0, 0, 0]` | STOP | `0.0` | Initial default (mean) |
| `[2, 0, 0, 0, 0]` | R | `1.0` | `0 + 1` |
| `[2, 2, 0, 0, 0]` | RR | `3.0` | `0 + 1 + 2` (expansion) |
| `[2, 2, 2, 0, 0]` | RRR | `7.0` | `0 + 1 + 2 + 4` (expansion) |
| `[2, 1, 0, 0, 0]` | RL | `0.5` | `1 - (2 / (2*2)) = 0.5` (first reversal) |
| `[2, 1, 2, 0, 0]` | RLR | `0.75` | `0.5 + 0.25` (refinement mode) |
| `[1, 0, 0, 0, 0]` | L | `-1.0` | `0 - 1` |
| `[1, 1, 0, 0, 0]` | LL | `-3.0` | `0 - 1 - 2` (expansion) |
| `[1, 2, 0, 0, 0]` | LR | `-0.5` | `-1 + (2/4) = -0.5` (first reversal) |
| `[2, 0, 1, 2, 1]` | R then dead tail | `1.0` | Identical to `[2, 0, 0, 0, 0]` |

### 9.2 Score & Penalty Fixtures
Input data: targets `Y = [1.0, 3.0, 5.0]`, predictions `Y_hat = [1.5, 2.0, 6.0]`
Errors: `Y - Y_hat = [-0.5, 1.0, -1.0]`

- **Squared Error (SSE):**

  ```text
  RawScore = -[(-0.5)^2 + (1.0)^2 + (-1.0)^2]
           = -[0.25 + 1.0 + 1.0]
           = -2.25
  ```

- **Absolute Error (SAE):**

  ```text
  RawScore = -[abs(-0.5) + abs(1.0) + abs(-1.0)]
           = -[0.5 + 1.0 + 1.0]
           = -2.5
  ```

- **Penalized Score:**
  For tree `(c_add (c_mul 2.0 x) 1.0)`, leaves are `2.0` (1), `x` (1), `1.0` (1) = 3, and operators are `c_add` (0), `c_mul` (0) = 0, so total complexity = 3. With `complexityRatio = 0.1`:

  ```text
  PenalizedScore_SSE = -2.25 - (0.1 * 3) = -2.55
  ```

### 9.3 Improvement Threshold Fixtures
Threshold `t = -1e-4`, baseline `S_old = -100.0`:

```text
delta     = -(-0.0001) * abs(-100.0) = 0.01
required  S_new > -100.0 + 0.01 = -99.99
```

- Score `-99.98`: **Improved**
- Score `-99.99`: **Not improved**
- Score `-99.995`: **Not improved**

Boolean baseline `S_old = -10.0` with `t = +0.5`:

```text
required  S_new > -10.0 + 0.5 = -9.5
```

- Score `-9.4`: **Improved**
- Score `-9.6`: **Not improved**

The public function is `(scoreImproved context new old)`; continuous contexts select `-1e-4`, while Boolean/action contexts use the existing configured `hcScoreImprovedThreshold`. `(scoreImprovedWithThreshold new old threshold)` tests the numeric formula separately. Reject non-finite new scores/thresholds and NaN old scores; a finite score improves an old negative infinity. Invalid-candidate initialization is handled by status in the future shared optimizer, not by clamping numerical values.

### 9.4 Conditional-distribution fixture for future BOA

Use four selected `(parent, child)` rows: `(L,L), (L,L), (R,R), (R,R)`, with categories `(STOP,L,R)` and one Dirichlet pseudocount per category. Given parent L the expected child distribution is `(1/5,3/5,1/5)`; given parent R it is `(1/5,1/5,3/5)`. An unseen STOP parent uses the uniform prior. Both coordinates in this fixture are active; deterministic inactive suffixes are a separate activation test. These expected values are test data for O1/O2, not an implemented Bayesian model.

---

## 10. Completion Check Verification

- [x] C++ reference commit and file/function anchors have been checked against the local checkout.
- [x] Clear demarcation between C++ parity mechanics and BOA/hBOA optimizer extensions.
- [x] Phase 0 formats for continuous context, evaluation results, and optimizer records are specified; enforcement is assigned to later milestones.
- [x] Invariants for raw trits, stepper, canonicalization, and model lifetime are established.
- [x] Test matrix of expected values provides exact verification fixtures.

### Implemented and deferred scope

Phase 0 provides inert records/accessors, deterministic context recognition, production spec defaults, finite row-score formulas, continuous complexity, failure-to-composite mapping, and the context-aware improvement predicate. The fixtures exercise those helpers and a test-only C++ stepper simulation.

Step 2 adds `scoring/candidate-evaluation.metta`, imported with `optimization/optimizer-contract.metta` by `moses.metta` and hill-climbing entrypoints. Materialization, scoring, caching, and counted batches now live outside hill-climbing. Its existing public result shape is unchanged; the counted path passes its remaining allowance into the shared service.
