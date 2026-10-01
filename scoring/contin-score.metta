;; ==============================================================================
;; Module: scoring/contin-score.metta
;; Purpose: Continuous Score Formula, Complexity Weights, and Improvement Predicate
;;
;; Phase 1 / Step 4: full validated numerical candidate scoring.
;; Load contin-eval before this module; candidate-evaluation after it.
;;
;; Reference (commit f88ccd3279f3dd853e8c23103be5376a0e7eafc1):
;;   - moses/moses/scoring/bscores.h (contin_bscore)
;;   - moses/moses/scoring/bscores.cc (L140-179, contin_bscore implementation)
;;   - moses/moses/optimization/optimization.cc (L116-136, score_improved)
;;   - moses/moses/moses/complexity.cc (L56-111, tree_complexity)
;; Requires scoring/cscore and parameters/{registry,defaults} for failure
;; mapping and the existing Boolean/action improvement threshold respectively.
;;
;; CONCEPTS:
;; ---------
;; 1. Raw score sign convention (C++ parity):
;;    Both squared-error and absolute-error scores are NEGATIVE sums:
;;      row_score(squared_error) = -(prediction - target)^2
;;      row_score(abs_error)     = -|prediction - target|
;;      raw_score                = sum(row_scores)          -- always <= 0
;;    The best possible raw score is therefore 0.0, not a large positive number.
;;    This sign is load-bearing: comparisons, caches, and termination all rely on
;;    "higher is better, 0 is perfect."
;;
;; 2. Penalized score:
;;      penalized_score = raw_score - complexityRatio * continTreeComplexity(tree)
;;    Because raw_score <= 0 and complexityRatio >= 0 and complexity >= 0,
;;    penalized_score <= raw_score.  Both higher-is-better ordering and the
;;    distinction between raw and penalized champions must be preserved.
;;
;; 3. Continuous complexity weights (complexity.cc L100-110):
;;    Operators and their weights:
;;      c_add, c_mul, c_gt_zero, c_impulse  -> 0
;;      c_div, c_exp, c_log, c_sin          -> 1
;;      rand, equ, cond                     -> 1
;;      constants and input variables       -> 1  (leaves always cost 1)
;;    Accumulation is recursive across all subtrees.
;;    NOTE: Only MVP-phase operators need executable clauses; weights for
;;    deferred operators (c_gt_zero, c_impulse, cond, equ, rand) are
;;    documented here and must be wired when those operators are introduced.
;;
;; 4. Relative improvement threshold (optimization.cc L116-136):
;;    C++ min_improv for contin_bscore = -1.0e-4  (bscores.cc L174-178)
;;    For a negative threshold t, improvement requires:
;;      new_score > old_score - t * |old_score|
;;    For a non-negative threshold t:
;;      new_score > old_score + t
;;    The Boolean / action domain uses +0.5 (absolute threshold).
;;    These must remain DOMAIN-SEPARATE: (scoreImproved ctx new old) dispatches
;;    on context kind.  The global hcScoreImprovedThreshold 0.5 must NOT be
;;    silently applied to continuous candidates.
;; ==============================================================================

;; ------------------------------------------------------------------------------
;; Continuous Tree Complexity: continTreeComplexity
;; ------------------------------------------------------------------------------
;; Computes the recursive structural complexity of a continuous program tree.
;; Reference: complexity.cc tree_complexity (L56-111).

;; A single dispatcher prevents overlapping clauses from producing duplicate
;; answers under PeTTa. Unknown internal operators follow C++'s zero weight;
;; operator/arity validation is the evaluator's responsibility.
(= (continOperatorCost $op)
   (case $op
     ((c_div 1) (c_exp 1) (c_log 1) (c_sin 1) ($other 0))))

;; Empty c_add/c_mul are still operator nodes, not unit-cost variable leaves.
(= (continLeafCost $value)
   (case $value
     ((c_add 0) (c_mul 0) ($other 1))))

;; C++ tree_complexity stops at *(0 subtree) during knob probing. Match numeric
;; zero (both integer and float), not an arbitrary variable label or expression.
(= (continZeroProduct $op $children)
   (case ($op $children)
     (((c_mul (cons (mkTree (mkNode $value) ()) $rest))
       (if (== (get-type $value) Number)
           (and (<= $value 0) (>= $value 0)) False))
      ($other False))))

(= (continTreeComplexity (mkTree (mkNode $op) $children))
   (if (== $children ())
       (continLeafCost $op)
       (if (continZeroProduct $op $children)
           0
           (+ (continOperatorCost $op)
              (continChildComplexity $children)))))

;; Sum complexity across a list of child subtrees.
(= (continChildComplexity ()) 0)
(= (continChildComplexity (cons $child $rest))
   (+ (continTreeComplexity $child)
      (continChildComplexity $rest)))

;; ------------------------------------------------------------------------------
;; Row-Level Error Formulas: continRowScore
;; ------------------------------------------------------------------------------
;; Returns the (negative) contribution of a single prediction/target pair.
;; The validated scoring path calls this once per row inside a catch boundary.
;;
;; Invariant: result is always <= 0.  The sum of all row scores is raw_score.

(= (continRowScore squared_error $pred $target)
   (let $d (- $pred $target)
     (- 0 (* $d $d))))

(= (continRowScore abs_error $pred $target)
   (let $d (- $pred $target)
     ;; Use built-in subtraction to get absolute value without a helper.
     (if (< $d 0) $d (- 0 $d))))

;; ------------------------------------------------------------------------------
;; Penalized Score: continPenalizedScore
;; ------------------------------------------------------------------------------
(= (continPenalizedScore $rawScore $complexityRatio $treeComplexity)
   (- $rawScore (* $complexityRatio $treeComplexity)))

;; A failure becomes the repository's composite sentinel only at the scoring
;; boundary. Retain its error/validity status separately; never treat this finite
;; legacy sentinel as proof that a row is unevaluated or as a universal bound.
(= (continFailureScore (mkCEvalError $reason)) (worstCscore))

;; ------------------------------------------------------------------------------
;; Domain-Aware Improvement Predicate: scoreImproved
;; ------------------------------------------------------------------------------
;; Implements the C++ score_improved logic (optimization.cc L121-136) with
;; domain dispatch on context kind.
;;
;; For continuous context — threshold = -1.0e-4 (negative):
;;   improved iff newScore > oldScore - t * |oldScore|
;;
;; For Boolean/action context — threshold = +0.5 (non-negative, from defaults.metta):
;;   improved iff newScore > oldScore + t
;;
;; Keep the numeric helper separate from the context-aware public operation.
;; Continuous defaults have their own production parameter;
;; Boolean/action callers retain the configured hcScoreImprovedThreshold.
;;
;; Edge case: when oldScore is 0.0, the relative branch reduces to
;;   newScore > 0 - (-1e-4) * 0 = 0, i.e. any positive new score is an
;;   improvement. Never clamp non-finite scores to an arbitrary finite value.
;; Explicit candidate validity handles initialization from an invalid candidate
;; in O0; the scalar helper also handles an old negative infinity safely.
(= (continImprovementThreshold) (param continImprovementThreshold))

(= (scoreImproved $context $newScore $oldScore)
   (let $threshold
        (case $context
          (((mkContinCtx $tbl $err $ratio $mode $target) (continImprovementThreshold))
           ($other (param hcScoreImprovedThreshold))))
     (scoreImprovedWithThreshold $newScore $oldScore $threshold)))

(= (scoreImprovedWithThreshold $newScore $oldScore $threshold)
   (if (and (continFiniteNumber $newScore) (continFiniteNumber $threshold))
       (if (continFiniteNumber $oldScore)
           (scoreImprovedFinite $newScore $oldScore $threshold)
           (if (== (get-type $oldScore) Number)
               (if (== (catch (py-call (builtins.int (py-call (math.isinf $oldScore))))) 1)
                   (< $oldScore 0) False)
               False))
       False))

(= (scoreImprovedFinite $newScore $oldScore $threshold)
   (== (catch (if (>= $threshold 0)
       (> $newScore (+ $oldScore $threshold))
       (let $margin (* (- 0 $threshold)
                       (if (< $oldScore 0) (- 0 $oldScore) $oldScore))
         (> $newScore (+ $oldScore $margin))))) True))

;; Full scoring path: preserve tagged failures until the composite boundary.
;; Catch EACH row and accumulation: overflow must not be hidden by later rows.
(= (continScoreRowsWithBehavior $tree $labels $columns $targets $error $total)
   (case $targets
     ((() (mkContinBehavior () $total))
      ((cons $target $rest)
       (case (continEval $tree (continRowEnvironment $labels $columns))
         (((mkCEvalError $reason) (mkCEvalError $reason))
          ((mkCEvalOk $prediction)
           (case (continCheckedNumber (catch (continRowScore $error $prediction $target)))
             (((mkCEvalError $rowError) (mkCEvalError $rowError))
              ((mkCEvalOk $contribution)
               (case (continCheckedNumber (catch (+ $total $contribution)))
                 (((mkCEvalError $sumError) (mkCEvalError $sumError))
                  ((mkCEvalOk $sum)
                   (case (continScoreRowsWithBehavior $tree $labels (continNextColumns $columns)
                                    $rest $error $sum)
                     (((mkCEvalError $tailError) (mkCEvalError $tailError))
                      ((mkContinBehavior $tailScores $raw)
                       (mkContinBehavior (cons $contribution $tailScores) $raw)))))))))))))))))

(= (continScoreRows $tree $labels $columns $targets $error $total)
   (case (continScoreRowsWithBehavior $tree $labels $columns $targets $error $total)
     (((mkCEvalError $reason) (mkCEvalError $reason))
      ((mkContinBehavior $scores $raw) (mkCEvalOk $raw)))))

(= (continComposite $tree $raw $ratio)
   (let $complexity (continTreeComplexity $tree)
     (case (continCheckedNumber (catch (* $ratio $complexity)))
       (((mkCEvalError $reason) (mkCEvalError $reason))
        ((mkCEvalOk $penalty)
         (case (continCheckedNumber (catch (- $raw $penalty)))
           (((mkCEvalError $penError) (mkCEvalError $penError))
            ((mkCEvalOk $penalized)
             (mkCscore $raw $complexity $penalty 0.0 $penalized)))))))))

;; Returns mkCscore or mkCEvalError. Validation is also needed for a constant
;; tree, so unused bad columns and invalid context fields cannot bypass it.
(= (continScoreDetails $tree $context)
   (case (continPrepareContext $context)
     (((mkCEvalError $reason) (mkCEvalError $reason))
      ((mkContinData $labels $columns $targets)
       (if (continTreeWellFormed $tree)
           (case (continScoreRowsWithBehavior $tree $labels $columns $targets (continCtxErrorType $context) 0.0)
             (((mkCEvalError $rowError) (mkCEvalError $rowError))
              ((mkContinBehavior $scores $raw)
               (case (continComposite $tree $raw (continCtxComplexityRatio $context))
                 (((mkCEvalError $penaltyError) (mkCEvalError $penaltyError))
                  ($composite (mkContinScore $composite (mkBScore $scores))))))))
           (mkCEvalError "InvalidTree"))))))

(= (continScoreTree $tree $context)
   (case (continScoreDetails $tree $context)
     (((mkCEvalError $reason) (mkCEvalError $reason))
      ((mkContinScore $score $behavior) $score))))

;; Retain per-row errors from the SAME counted invocation for merge/dominance.
;; Never rescore during merge. The lifecycle clears this alongside score caches.
!(bind! &continBehaviorCache (new-space))
!(bind! &continTraceStart (new-state 0.0))
!(bind! &continTraceCalls (new-state 0))
(= (cachedContinBehavior $context $tree)
   (let $hits (collapse (match &continBehaviorCache (continBehavior $context $tree $bs) $bs))
     (if (== $hits ()) (mkCEvalError "MissingContinuousBehavior") (car-atom $hits))))
(= (resetContinBehaviorCache)
   (let* (($entries (collapse (match &continBehaviorCache $entry $entry)))
          ($_ (map-atom $entries $entry (remove-atom &continBehaviorCache $entry)))
          ($_count (change-state! &continTraceCalls 0))
          ($_clock (if (param continTrace)
                      (change-state! &continTraceStart (py-call (time.monotonic))) True))) True))

;; Opt-in observational trace: only actual scorer invocations, never cache hits
;; or merge. Elapsed time starts at run cache reset (not process startup/CSV).
(= (continTraceEvaluation $tree $result)
   (let $_trace
        (if (param continTrace)
            (let* (($_count (change-state! &continTraceCalls (+ 1 (get-state &continTraceCalls))))
                   ($elapsed (- (py-call (time.monotonic)) (get-state &continTraceStart)))
                   ((mkCandidateScore $score $status) $result))
              (println! (ContinuousEvaluation (scorerCallIndex (get-state &continTraceCalls))
                (elapsed $elapsed) (status $status) (raw (getScore $score))
                (penalized (getPenScore $score)) (complexity (getComp $score))))) True)
     $result))

;; Status-aware shared scorer. A valid raw score below -1e100 stays valid.
(= (scoreContinCandidate $tree $context)
   (continTraceEvaluation $tree (case (continScoreDetails $tree $context)
     (((mkCEvalError $reason)
       (mkCandidateScore (worstCscore) (candidateInvalid $reason)))
      ((mkContinScore $score $behavior)
       (let $_cache
            (if (== (cachedContinBehavior $context $tree) (mkCEvalError "MissingContinuousBehavior"))
                (add-atom &continBehaviorCache (continBehavior $context $tree $behavior)) True)
         (mkCandidateScore $score candidateValid)))))))
