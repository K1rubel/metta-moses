;; ==============================================================================
;; Module: optimization/optimizer-contract.metta
;; Purpose: Common Optimizer Boundary Contract, Budget Limits, and Result Structures
;;
;; Reference:
;;   OpenCog C++ MOSES & EDA:
;;   - moses/moses/optimization/optimization.h, optimization.cc
;;   - moses/moses/optimization/univariate.cc
;;   - moses/moses/eda/optimize.h
;;   - Pelikan (2005) BOA/hBOA optimization loop
;;
;; CONCEPTS & EXPLANATION:
;; ----------------------
;; 1. Why a Unified Optimizer Contract?
;;    In original metta-moses, Hill-Climbing (`hc`) communicated through an
;;    ad-hoc internal state tuple (`hillState`) whose positions were directly
;;    accessed by the outer loop (`expand-deme.metta`).
;;    To integrate population-based EDA optimizers (`univariate`, `boa`, `hboa`)
;;    interchangeably, we decouple the caller from algorithm-specific internals.
;;    Every optimizer implements a standard call interface:
;;
;;      (optimizeDeme $deme $context $initialInstance $limits $rngState $config)
;;        -> (mkOptimizerResult $optimizedDeme $bestInstance $actualEvaluations
;;                              $stopReason $diagnostics $nextRngState)
;;
;; 2. Explicit Evaluation Status (mkEvaluatedCandidate):
;;    Previously, whether a candidate needed evaluation was inferred by checking
;;    if its score equalled `worstCscore`. But in continuous domains, an invalid
;;    candidate (e.g. division by zero) legitimately evaluates to `worstCscore`!
;;    Comparing with worstCscore causes invalid candidates to be repeatedly re-evaluated,
;;    wasting the evaluation budget.
;;    `mkEvaluatedCandidate` carries an explicit status:
;;      - candidatePending: Has not been evaluated in this context.
;;      - candidateValid: Has been evaluated successfully.
;;      - (candidateInvalid reason): Evaluated failure, cached like a valid result.
;;    Validity and evaluation status are distinct; a valid numeric score may
;;    equal or fall below the repository's finite worstCscore sentinel.
;;
;; 3. Budget Units & Scorer Call Accounting:
;;    MOSES budget is measured in ACTUAL NEW SCORER INVOCATIONS.
;;    - Cache Hit: Costs 0 scorer calls.
;;    - Evaluation Failure: Costs 1 scorer call, then is cached.
;;    - Duplicate Proposals: Cost 0 scorer calls if already evaluated in cache.
;;    When the budget is exhausted, the optimizer terminates immediately and
;;    returns partial batches rather than silently overshooting or discarding progress.
;;
;; 4. Dual Champion Tracking:
;;    - Internal Selection: Optimizers rank and select candidates based on
;;      PENALIZED composite score (accuracy minus complexity penalty).
;;    - Outer Loop Termination: The MOSES meta-loop checks if the RAW score has
;;      reached `targetScore` (e.g., 0.0).
;;    Both aspects are preserved in the result.
;;
;; 5. Deterministic Pure RNG State Threading:
;;    Rather than using uncontrolled global random side effects, random seeds
;;    are passed into and returned from optimizers (`$rngState` -> `$nextRngState`),
;;    enabling seeded replay under fixed evaluation/proposal limits. Time-based
;;    stops and stochastic evaluators require additional controls for replay.
;;
;; 6. Deme-Scoped Model Lifetime:
;;    Learned Bayesian networks and decision tree structures belong strictly
;;    to the current deme's representation. When selected exemplars are expanded
;;    into new demes with updated knob means, models and populations are
;;    cleanly reset.
;; ==============================================================================

;; ------------------------------------------------------------------------------
;; Optimizer Limits: mkOptimizerLimits
;; ------------------------------------------------------------------------------
;; Binds resource and iteration allowances for an optimization run inside a deme.
;;
;; Fields:
;;   $maxEvals       : Number - Maximum actual new scorer calls
;;   $maxProposals   : Number - Maximum candidate vectors allowed to be generated
;;   $maxGenerations : Number - Maximum population generations (for EDA / GA)
;;   $timeLimitSec   : Number - Maximum wall-clock seconds (-1 for unlimited)
;; Counts must be integers >= 0 or -1 for unlimited; time must be >= 0 or -1.
;; Zero grants no work in that category. Validation/enforcement comes in O0.
(: OptimizerLimits Type)
(: mkOptimizerLimits (-> Number Number Number Number OptimizerLimits))

(= (limitsMaxEvals (mkOptimizerLimits $evals $props $gens $time)) $evals)
(= (limitsMaxProposals (mkOptimizerLimits $evals $props $gens $time)) $props)
(= (limitsMaxGenerations (mkOptimizerLimits $evals $props $gens $time)) $gens)
(= (limitsTimeLimitSec (mkOptimizerLimits $evals $props $gens $time)) $time)

;; ------------------------------------------------------------------------------
;; Evaluated Candidate Wrapper: mkEvaluatedCandidate
;; ------------------------------------------------------------------------------
;; Represents an instance paired with its tree, score, and evaluation status.
;;
;; Fields:
;;   $instance    : Instance - The discrete trit genotype vector
;;   $tree        : Tree     - The materialized/reduced candidate AST (phenotype)
;;   $score       : Atom     - The composite score or worst score
;;   $status      : CandidateStatus - pending, valid, or invalid with reason
;; Before materialization/evaluation, tree and score may be (). Context changes
;; invalidate attached scores. Invalid candidates carry (worstCscore) for legacy
;; interoperability; future selection must prefer valid candidates by status.
(: CandidateStatus Type)
(: candidatePending CandidateStatus)
(: candidateValid CandidateStatus)
(: candidateInvalid (-> String CandidateStatus))
(: EvaluatedCandidate Type)
(: mkEvaluatedCandidate (-> Atom Atom Atom CandidateStatus EvaluatedCandidate))

(= (candidateInstance (mkEvaluatedCandidate $inst $tree $sc $eval)) $inst)
(= (candidateTree (mkEvaluatedCandidate $inst $tree $sc $eval)) $tree)
(= (candidateScore (mkEvaluatedCandidate $inst $tree $sc $eval)) $sc)
(= (candidateStatus (mkEvaluatedCandidate $inst $tree $sc $status)) $status)
(= (candidateIsEvaluated (mkEvaluatedCandidate $inst $tree $sc $status))
   (case $status
     ((candidatePending False) (candidateValid True)
      ((candidateInvalid $reason) True))))
(= (candidateIsValid (mkEvaluatedCandidate $inst $tree $sc $status))
   (case $status
     ((candidatePending False) (candidateValid True)
      ((candidateInvalid $reason) False))))
(= (candidateFailureReason
      (mkEvaluatedCandidate $inst $tree $sc (candidateInvalid $reason))) $reason)

;; ------------------------------------------------------------------------------
;; Standard Termination / Stop Reasons
;; ------------------------------------------------------------------------------
;; Inert typed atoms, consistent with the result constructor's reason type.
(: OptimizerStopReason Type)
(: stopTargetReached OptimizerStopReason)
(: stopBudgetExhausted OptimizerStopReason)
(: stopProposalsExhausted OptimizerStopReason)
(: stopGenerationsExhausted OptimizerStopReason)
(: stopTimeExhausted OptimizerStopReason)
(: stopStagnation OptimizerStopReason)
(: stopAllInvalid OptimizerStopReason)
(: stopExhaustedSpace OptimizerStopReason)

;; ------------------------------------------------------------------------------
;; Unified Optimizer Result: mkOptimizerResult
;; ------------------------------------------------------------------------------
;; Standard return tuple produced by all optimizers.
;;
;; Fields:
;;   $optimizedDeme     : Deme   - The deme containing final scored candidates
;;   $bestInstance      : Atom   - Instance of the top penalized individual, or ()
;;                                when no evaluated candidates exist. The deme
;;                                must also retain the raw champion.
;;   $actualEvaluations : Number - Exact count of novel scoring calls consumed
;;   $stopReason        : OptimizerStopReason - Declared reason for halting search
;;   $diagnostics       : Atom   - Key-value metadata (proposals, cache hits, model stats)
;;   $nextRngState      : Atom   - Updated PRNG generator state
(: OptimizerResult Type)
(: mkOptimizerResult (-> Atom Atom Number OptimizerStopReason Atom Atom OptimizerResult))

(= (resultDeme (mkOptimizerResult $deme $best $evals $reason $diag $rng)) $deme)
(= (resultBestInstance (mkOptimizerResult $deme $best $evals $reason $diag $rng)) $best)
(= (resultActualEvaluations (mkOptimizerResult $deme $best $evals $reason $diag $rng)) $evals)
(= (resultStopReason (mkOptimizerResult $deme $best $evals $reason $diag $rng)) $reason)
(= (resultDiagnostics (mkOptimizerResult $deme $best $evals $reason $diag $rng)) $diag)
(= (resultNextRngState (mkOptimizerResult $deme $best $evals $reason $diag $rng)) $rng)

;; ------------------------------------------------------------------------------
;; Diagnostics Record Helper
;; ------------------------------------------------------------------------------
;; Structured telemetry attached to every optimizer result.
;;
;; Fields:
;;   $proposals : Number — total candidate vectors generated (including duplicates)
;;   $cacheHits : Number — scorer calls avoided via cache lookup
;;   $invalids  : Number — candidates that returned mkCEvalError on evaluation
;;   $modelSize : Number — learned edges (BOA) or tree nodes (hBOA); 0 for HC
;; An inert record, not a function that rewrites itself into a different type.
(: OptimizerDiagnostics Type)
(: mkOptimizerDiag (-> Number Number Number Number OptimizerDiagnostics))
(= (diagProposals (mkOptimizerDiag $props $hits $invalids $size)) $props)
(= (diagCacheHits (mkOptimizerDiag $props $hits $invalids $size)) $hits)
(= (diagInvalids (mkOptimizerDiag $props $hits $invalids $size)) $invalids)
(= (diagModelSize (mkOptimizerDiag $props $hits $invalids $size)) $size)
