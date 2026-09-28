;; ==============================================================================
;; Test Suite: tests/continuous-reference-fixtures-test.metta
;; Purpose: Verify Golden Reference Fixtures for Continuous Domain Contracts
;;
;; Closes: Step 1 / Phase 0 of initial-continuous-domain-porting-plan.md
;;
;; Reference (commit f88ccd3279f3dd853e8c23103be5376a0e7eafc1):
;;   - moses/moses/representation/field_set.h (contin_stepper L233-275)
;;   - moses/moses/scoring/bscores.h, bscores.cc (contin_bscore L140-179)
;;   - moses/moses/optimization/optimization.cc (score_improved L121-136)
;;   - moses/moses/moses/complexity.cc (tree_complexity L56-111)
;;
;; What this file is:
;;   A set of concrete expected-value assertions that pin down the exact
;;   semantic choices made in Phase 0.  These fixtures distinguish:
;;     - negative SSE/SAE from mean-squared error
;;     - production stepper defaults (depth=5, step=1, expansion=2) from
;;       build_knobs constructor defaults (expansion=1, depth=4)
;;     - continuous relative improvement threshold from Boolean absolute threshold
;;   The stepper decode logic below is an inline reference simulation used only
;;   to verify fixture values.  The production stepper lives in
;;   representation/contin-stepper.metta (Phase 2).
;; ==============================================================================

;; assertEqual is defined by this project's test helpers, not by PeTTa itself.
!(import! &self ../utilities/general-helpers)
!(import! &self ../parameters/registry)
!(import! &self ../parameters/defaults)
!(import! &self ../scoring/cscore)
!(import! &self ../representation/knob-representation)
!(import! &self ../representation/contin-spec)
!(import! &self ../scoring/contin-eval)
!(import! &self ../scoring/contin-score)
!(import! &self ../optimization/optimizer-contract)

;; ------------------------------------------------------------------------------
;; Part 1: Stepper Reference Simulation
;; ------------------------------------------------------------------------------
;; Inline simulation of field_set.h contin_stepper (L233-275).
;; This is NOT the production implementation — it is a reference decode used only
;; to compute and check the fixture values in the table below.
;; Production implementation: representation/contin-stepper.metta (Phase 2).
;;
;; State:
;;   $val      — accumulated real value
;;   $step     — current step size
;;   $allLeft  — True if every non-STOP move so far was LEFT
;;   $allRight — True if every non-STOP move so far was RIGHT
;;   $exp      — expansion factor
;;   trit list — remaining trits to process

(= (decodeTritList $val $step $allLeft $allRight $exp ())
   ;; No more trits: return accumulated value.
   $val)

(= (decodeTritList $val $step $allLeft $allRight $exp (cons $head $tail))
   (if (== $head 0)
       ;; STOP: halt immediately; remaining trits are dead tail.
       $val
       (if (== $head 1)
           ;; LEFT move
           (if $allLeft
               ;; Purely-left streak: subtract step, expand for next time.
               (decodeTritList (- $val $step) (* $step $exp) True False $exp $tail)
               ;; Reversal or refinement continuation:
               ;;   On the very first reversal from a purely-right streak,
               ;;   divide step by (expansion * 2) before applying.
               ;;   Thereafter (both $allLeft and $allRight are False), just use step.
               (let $s (if $allRight (/ $step (* $exp 2)) $step)
                 (decodeTritList (- $val $s) (/ $s 2) False False $exp $tail)))
           ;; RIGHT move; malformed trits must not silently become RIGHT.
           (if (== $head 2)
             (if $allRight
               ;; Purely-right streak: add step, expand for next time.
               (decodeTritList (+ $val $step) (* $step $exp) False True $exp $tail)
               ;; Reversal or refinement continuation:
               (let $s (if $allLeft (/ $step (* $exp 2)) $step)
                 (decodeTritList (+ $val $s) (/ $s 2) False False $exp $tail)))
             (mkCEvalError "InvalidTrit")))))

;; Convenience entry point using production defaults: mean=0, step=1, expansion=2.
(= (runStepper $trits)
   (let (mkContinSpec $mean $step $exp $depth) (defaultContinSpec 0.0)
     (decodeTritList $mean $step True True $exp $trits)))

;; ---- Fixture 1: STOP at position 0 -> mean = 0.0 ----
!(assertEqual (runStepper (0 0 0 0 0)) 0.0)

;; ---- Fixture 2: R -> 0 + 1 = 1.0 ----
!(assertEqual (runStepper (2 0 0 0 0)) 1.0)

;; ---- Fixture 3: RR -> 0 + 1 + 2 = 3.0 (expansion kicks in) ----
!(assertEqual (runStepper (2 2 0 0 0)) 3.0)

;; ---- Fixture 4: RRR -> 0 + 1 + 2 + 4 = 7.0 ----
!(assertEqual (runStepper (2 2 2 0 0)) 7.0)

;; ---- Fixture 5: RL -> first reversal from right
;;   After R: val=1, step=2 (expanded)
;;   First reversal (allRight was True): newStep = 2 / (2*2) = 0.5
;;   val = 1 - 0.5 = 0.5
!(assertEqual (runStepper (2 1 0 0 0)) 0.5)

;; ---- Fixture 6: RLR -> refinement continues
;;   After RL: val=0.5, step=0.5/2=0.25 (halved after reversal apply)
;;   R in refinement: s = 0.25 (not first reversal, allLeft=False)
;;   val = 0.5 + 0.25 = 0.75, next step = 0.25/2 = 0.125
!(assertEqual (runStepper (2 1 2 0 0)) 0.75)

;; ---- Fixture 7: L -> -1.0 ----
!(assertEqual (runStepper (1 0 0 0 0)) -1.0)

;; ---- Fixture 8: LL -> 0 - 1 - 2 = -3.0 ----
!(assertEqual (runStepper (1 1 0 0 0)) -3.0)

;; ---- Fixture 9: LR -> first reversal from left
;;   After L: val=-1, step=2 (expanded)
;;   First reversal (allLeft was True): newStep = 2 / 4 = 0.5
;;   val = -1 + 0.5 = -0.5
!(assertEqual (runStepper (1 2 0 0 0)) -0.5)

;; ---- Fixture 10: Dead tail after STOP is ignored ----
;;   [2, 0, 1, 2, 1] must decode identically to [2, 0, 0, 0, 0] = 1.0
!(assertEqual (runStepper (2 0 1 2 1)) 1.0)
!(assertEqual (runStepper (2 1 1 0 0)) 0.25)
!(assertEqual (runStepper (1 2 2 0 0)) -0.25)
!(assertEqual (runStepper (2 2 2 2 2)) 31.0)
!(assertEqual (runStepper (3 0 0 0 0)) (mkCEvalError "InvalidTrit"))


;; ------------------------------------------------------------------------------
;; Part 2: Score Sign and Value Fixtures (Negative SSE and SAE)
;; ------------------------------------------------------------------------------
;; Data: Target Y = [1.0, 3.0, 5.0], Prediction Y' = [1.5, 2.0, 6.0]
;;
;; This is critical: raw score must be a NEGATIVE SUM, not a mean, not positive.
;; Best raw score = 0.0 (perfect fit).

;; Squared-error row scores
!(assertEqual (continRowScore squared_error 1.5 1.0) -0.25)  ;; -(0.5)^2
!(assertEqual (continRowScore squared_error 2.0 3.0) -1.0)   ;; -(-1.0)^2
!(assertEqual (continRowScore squared_error 6.0 5.0) -1.0)   ;; -(1.0)^2

;; Total SSE raw score = -2.25
!(assertEqual (+ (continRowScore squared_error 1.5 1.0)
                (+ (continRowScore squared_error 2.0 3.0)
                   (continRowScore squared_error 6.0 5.0))) -2.25)

;; Absolute-error row scores
!(assertEqual (continRowScore abs_error 1.5 1.0) -0.5)   ;; -|0.5|
!(assertEqual (continRowScore abs_error 2.0 3.0) -1.0)   ;; -|-1.0|
!(assertEqual (continRowScore abs_error 6.0 5.0) -1.0)   ;; -|1.0|

;; Total SAE raw score = -2.5
!(assertEqual (+ (continRowScore abs_error 1.5 1.0)
                (+ (continRowScore abs_error 2.0 3.0)
                   (continRowScore abs_error 6.0 5.0))) -2.5)
!(assertEqual (continRowScore squared_error 3.0 3.0) 0.0)
!(assertEqual (continRowScore abs_error 3.0 3.0) 0.0)


;; ------------------------------------------------------------------------------
;; Part 3: Continuous Complexity Weights
;; ------------------------------------------------------------------------------
;; Reference: complexity.cc tree_complexity (L100-110)
;; Weights: c_add=0, c_mul=0, c_div=1, c_exp=1, c_log=1, c_sin=1; leaves=1

!(assertEqual (continOperatorCost c_add) 0)
!(assertEqual (continOperatorCost c_mul) 0)
!(assertEqual (continOperatorCost c_div) 1)
!(assertEqual (continOperatorCost c_exp) 1)
!(assertEqual (continOperatorCost c_log) 1)
!(assertEqual (continOperatorCost c_sin) 1)

;; Leaf complexity: any constant or variable name costs 1
!(assertEqual (continTreeComplexity (mkTree (mkNode 2.0) ())) 1)
!(assertEqual (continTreeComplexity (mkTree (mkNode x) ())) 1)

;; Subtree (c_mul 2.0 x): cost = 0 + 1 + 1 = 2
!(assertEqual (continTreeComplexity
               (mkTree (mkNode c_mul)
                 (cons (mkTree (mkNode 2.0) ())
                 (cons (mkTree (mkNode x) ()) ()))))
              2)

;; Full tree (c_add (c_mul 2.0 x) 1.0): cost = 0 + 2 + 1 = 3
!(assertEqual (continTreeComplexity
               (mkTree (mkNode c_add)
                 (cons (mkTree (mkNode c_mul)
                         (cons (mkTree (mkNode 2.0) ())
                         (cons (mkTree (mkNode x) ()) ())))
                 (cons (mkTree (mkNode 1.0) ()) ()))))
              3)

;; Penalized score: raw=-2.25, ratio=0.1, complexity=3 -> -2.25 - 0.3 = -2.55
!(assertEqual (continPenalizedScore -2.25 0.1 3) -2.55)


;; ------------------------------------------------------------------------------
;; Part 4: Domain-Aware Improvement Threshold
;; ------------------------------------------------------------------------------
;; Reference: optimization.cc score_improved (L121-136)
;;   C++ contin_bscore::min_improv() returns -1.0e-4   (bscores.cc L174-178)
;;   C++ logical_bscore::min_improv() returns  0.5     (bscores.cc L125-127)
;;
;; For threshold t = -0.0001 and oldScore = -100.0:
;;   margin = -(-0.0001) * |-100.0| = 0.01
;;   acceptance: newScore > -100.0 + 0.01 = -99.99

!(assertEqual (scoreImprovedWithThreshold -99.98  -100.0 -0.0001) True)
!(assertEqual (scoreImprovedWithThreshold -99.99  -100.0 -0.0001) False)
!(assertEqual (scoreImprovedWithThreshold -99.995 -100.0 -0.0001) False)

;; Boolean domain: threshold = +0.5 (absolute), oldScore = -10.0
;; acceptance: newScore > -10.0 + 0.5 = -9.5
!(assertEqual (scoreImprovedWithThreshold -9.4 -10.0 0.5) True)
!(assertEqual (scoreImprovedWithThreshold -9.6 -10.0 0.5) False)


;; ------------------------------------------------------------------------------
;; Part 5: Raw Trit Field — Discrete Map Interface
;; ------------------------------------------------------------------------------
;; Verify that mkContinTritField integrates with the existing generic knob
;; accessor functions (getKnobMultip / getKnobDefault) defined in
;; knob-representation.metta.  This is the interface that lets hill-climbing
;; and other optimizers treat continuous coordinates as ordinary discrete fields.

!(assertEqual (getKnobMultip  (mkContinTritField bias 0)) (mkMultip  3))
!(assertEqual (getKnobDefault (mkContinTritField bias 0)) (mkDiscSpec 0))

;; Offset doesn't change multiplicity or default — every trit in a knob is the same.
!(assertEqual (getKnobMultip  (mkContinTritField x_weight 3)) (mkMultip  3))
!(assertEqual (getKnobDefault (mkContinTritField x_weight 3)) (mkDiscSpec 0))

;; ------------------------------------------------------------------------------
;; Part 6: Deterministic context, defaults, complexity, and failure contracts
;; ------------------------------------------------------------------------------
;; collapse detects overlapping clauses, even if they emit the same value.
!(assertEqual (collapse (isContinContext (mkContinCtx table squared_error 0.1 linear 0.0))) (True))
!(assertEqual (collapse (isContinContext (mkActionCtx 10 0.1 0.0))) (False))
!(assertEqual (isContinContext (mkContinCtx table squared_error)) False)
!(assertEqual (continCtxTable (mkContinCtx table abs_error 0.2 nonlinear 0.0)) table)
!(assertEqual (continCtxErrorType (mkContinCtx table abs_error 0.2 nonlinear 0.0)) abs_error)
!(assertEqual (continCtxComplexityRatio (mkContinCtx table abs_error 0.2 nonlinear 0.0)) 0.2)
!(assertEqual (continCtxSearchMode (mkContinCtx table abs_error 0.2 nonlinear 0.0)) nonlinear)
!(assertEqual (continCtxTargetScore (mkContinCtx table abs_error 0.2 nonlinear 0.0)) 0.0)
!(assertEqual (defaultContinSpec 4.5) (mkContinSpec 4.5 1.0 2.0 5))
!(assertEqual (continSpecMean (mkContinSpec 4.5 1.0 2.0 5)) 4.5)
!(assertEqual (continSpecStep (mkContinSpec 4.5 1.0 2.0 5)) 1.0)
!(assertEqual (continSpecExpansion (mkContinSpec 4.5 1.0 2.0 5)) 2.0)
!(assertEqual (continSpecDepth (mkContinSpec 4.5 1.0 2.0 5)) 5)
!(assertEqual (ctkSpec (mkCTK (mkContinSpec 4.5 1.0 2.0 5) 10)) (mkContinSpec 4.5 1.0 2.0 5))
!(assertEqual (ctkStartIdx (mkCTK (mkContinSpec 4.5 1.0 2.0 5) 10)) 10)
!(assertEqual (continFieldOwner (mkContinTritField bias 3)) bias)
!(assertEqual (continFieldOffset (mkContinTritField bias 3)) 3)
!(assertEqual (collapse (continTreeComplexity (mkTree (mkNode x) ()))) (1))
!(assertEqual (collapse (continTreeComplexity (mkTree (mkNode c_add) ((mkTree (mkNode x) ()) (mkTree (mkNode 2) ()))))) (2))
!(assertEqual (continTreeComplexity (mkTree (mkNode c_add) ())) 0)
!(assertEqual (continTreeComplexity (mkTree (mkNode c_mul) ())) 0)
!(assertEqual (continTreeComplexity (mkTree (mkNode c_mul) ((mkTree (mkNode 0) ()) (mkTree (mkNode x) ()))) ) 0)
!(assertEqual (continTreeComplexity (mkTree (mkNode c_mul) ((mkTree (mkNode 0.0) ()) (mkTree (mkNode x) ()))) ) 0)
;; The C++ probing shortcut is only for a leading zero, not any zero child.
!(assertEqual (continTreeComplexity (mkTree (mkNode c_mul) ((mkTree (mkNode x) ()) (mkTree (mkNode 0) ()))) ) 2)
!(assertEqual (continTreeComplexity (mkTree (mkNode c_sin) ((mkTree (mkNode x) ())))) 2)
!(assertEqual (isCEvalOk (mkCEvalOk 1.25)) True)
!(assertEqual (isCEvalOk (mkCEvalError "DivisionByZero")) False)
!(assertEqual (getCEvalValue (mkCEvalOk 1.25)) 1.25)
!(assertEqual (getCEvalError (mkCEvalError "DivisionByZero")) "DivisionByZero")
!(assertEqual (continFailureScore (mkCEvalError "DivisionByZero")) (worstCscore))
;; A real SSE may be below -1e9; it is not an evaluation error.
!(assertEqual (continRowScore squared_error 1000000.0 0.0) -1000000000000.0)
!(assertEqual (scoreImproved (mkContinCtx table squared_error 0.1 linear 0.0) -99.98 -100.0) True)
!(assertEqual (scoreImproved (mkActionCtx 10 0.1 0.0) -99.98 -100.0) False)
!(set-param hcScoreImprovedThreshold 0.01)
!(assertEqual (scoreImproved (mkActionCtx 10 0.1 0.0) -99.98 -100.0) True)
!(assertEqual (scoreImproved (mkContinCtx table squared_error 0.1 linear 0.0) -99.995 -100.0) False)
!(set-param hcScoreImprovedThreshold 0.5)
!(assertEqual (scoreImprovedWithThreshold 0.0 0.0 -0.0001) False)
!(assertEqual (scoreImprovedWithThreshold -2.0 (py-call (builtins.float "-inf")) -0.0001) True)
!(assertEqual (scoreImprovedWithThreshold (py-call (builtins.float "inf")) -2.0 -0.0001) False)
!(assertEqual (scoreImprovedWithThreshold -2.0 (py-call (builtins.float "nan")) -0.0001) False)

;; ------------------------------------------------------------------------------
;; Part 7: Optimizer records must remain inert and retain every field
;; ------------------------------------------------------------------------------
!(assertEqual (limitsMaxEvals (mkOptimizerLimits 7 20 3 1.5)) 7)
!(assertEqual (limitsMaxProposals (mkOptimizerLimits 7 20 3 1.5)) 20)
!(assertEqual (limitsMaxGenerations (mkOptimizerLimits 7 20 3 1.5)) 3)
!(assertEqual (limitsTimeLimitSec (mkOptimizerLimits 7 20 3 1.5)) 1.5)
!(assertEqual (candidateInstance (mkEvaluatedCandidate instance tree (worstCscore) (candidateInvalid "NonFinite"))) instance)
!(assertEqual (candidateTree (mkEvaluatedCandidate instance tree (worstCscore) (candidateInvalid "NonFinite"))) tree)
!(assertEqual (candidateScore (mkEvaluatedCandidate instance tree (worstCscore) (candidateInvalid "NonFinite"))) (worstCscore))
!(assertEqual (candidateIsEvaluated (mkEvaluatedCandidate instance tree (worstCscore) (candidateInvalid "NonFinite"))) True)
!(assertEqual (candidateIsEvaluated (mkEvaluatedCandidate instance () () candidatePending)) False)
!(assertEqual (candidateIsEvaluated (mkEvaluatedCandidate instance tree score candidateValid)) True)
!(assertEqual (candidateIsValid (mkEvaluatedCandidate instance tree (worstCscore) candidateValid)) True)
!(assertEqual (candidateIsValid (mkEvaluatedCandidate instance tree (worstCscore) (candidateInvalid "NonFinite"))) False)
!(assertEqual (candidateIsValid (mkEvaluatedCandidate instance () () candidatePending)) False)
!(assertEqual (candidateStatus (mkEvaluatedCandidate instance tree score candidateValid)) candidateValid)
!(assertEqual (candidateFailureReason (mkEvaluatedCandidate instance tree (worstCscore) (candidateInvalid "NonFinite"))) "NonFinite")
!(assertEqual (collapse (mkOptimizerDiag 20 4 2 6)) ((mkOptimizerDiag 20 4 2 6)))
!(assertEqual (diagProposals (mkOptimizerDiag 20 4 2 6)) 20)
!(assertEqual (diagCacheHits (mkOptimizerDiag 20 4 2 6)) 4)
!(assertEqual (diagInvalids (mkOptimizerDiag 20 4 2 6)) 2)
!(assertEqual (diagModelSize (mkOptimizerDiag 20 4 2 6)) 6)
!(assertEqual (resultDeme (mkOptimizerResult deme instance 7 stopTimeExhausted (mkOptimizerDiag 20 4 2 6) rng)) deme)
!(assertEqual (resultBestInstance (mkOptimizerResult deme instance 7 stopTimeExhausted (mkOptimizerDiag 20 4 2 6) rng)) instance)
!(assertEqual (resultActualEvaluations (mkOptimizerResult deme instance 7 stopTimeExhausted (mkOptimizerDiag 20 4 2 6) rng)) 7)
!(assertEqual (resultStopReason (mkOptimizerResult deme instance 7 stopTimeExhausted (mkOptimizerDiag 20 4 2 6) rng)) stopTimeExhausted)
!(assertEqual (resultDiagnostics (mkOptimizerResult deme instance 7 stopTimeExhausted (mkOptimizerDiag 20 4 2 6) rng)) (mkOptimizerDiag 20 4 2 6))
!(assertEqual (resultNextRngState (mkOptimizerResult deme instance 7 stopTimeExhausted (mkOptimizerDiag 20 4 2 6) rng)) rng)
!(assertEqual (resultBestInstance (mkOptimizerResult deme () 0 stopBudgetExhausted (mkOptimizerDiag 0 0 0 0) rng)) ())

;; Phase 0 conditional-distribution fixture for future BOA implementations:
;; selected (parent, child) rows: (L,L), (L,L), (R,R), (R,R).
;; With one pseudocount per category (STOP,L,R), the conditional distributions
;; are (1/5,3/5,1/5) and (1/5,1/5,3/5); an unseen STOP parent backs off to thirds.
;; This pins down expected data, not a claim that model learning is implemented.
(= (boaReferenceRows) ((1 1) (1 1) (2 2) (2 2)))
(= (boaReferenceCounts $parent $child)
   (foldl-atom (boaReferenceRows) 0 $n $row
     (+ $n (if (== $row ($parent $child)) 1 0))))
!(assertEqual (boaReferenceCounts 1 1) 2)
!(assertEqual (boaReferenceCounts 1 2) 0)
!(assertEqual (boaReferenceCounts 2 2) 2)
!(assertEqual (/ (+ 1 (boaReferenceCounts 1 1)) 5.0) 0.6)
!(assertEqual (/ (+ 1 (boaReferenceCounts 1 2)) 5.0) 0.2)
