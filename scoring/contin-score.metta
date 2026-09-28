;; ==============================================================================
;; Module: scoring/contin-score.metta
;; Purpose: Continuous Score Formula, Complexity Weights, and Improvement Predicate
;;
;; Phase: Phase 0 — Freeze Contracts (closes Step 1)
;;        Phase 1 will add the full per-row scoring and aggregation implementation.
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
;; operator/arity validation is the future evaluator's responsibility.
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
;; Phase 1 will call this once per row.
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
;; Continuous defaults are local until the production parameter-wiring phase;
;; Boolean/action callers retain the configured hcScoreImprovedThreshold.
;;
;; Edge case: when oldScore is 0.0, the relative branch reduces to
;;   newScore > 0 - (-1e-4) * 0 = 0, i.e. any positive new score is an
;;   improvement. Never clamp non-finite scores to an arbitrary finite value.
;; Explicit candidate validity handles initialization from an invalid candidate
;; in O0; the scalar helper also handles an old negative infinity safely.
(= (continImprovementThreshold) -0.0001)

(= (scoreImproved $context $newScore $oldScore)
   (let $threshold
        (case $context
          (((mkContinCtx $tbl $err $ratio $mode $target) (continImprovementThreshold))
           ($other (param hcScoreImprovedThreshold))))
     (scoreImprovedWithThreshold $newScore $oldScore $threshold)))

(= (continFiniteNumber $value)
   (if (== (get-type $value) Number)
       ;; Convert Janus Python bools to integers before MeTTa comparison.
       (== (py-call (builtins.int (py-call (math.isfinite $value)))) 1) False))

(= (scoreImprovedWithThreshold $newScore $oldScore $threshold)
   (if (and (continFiniteNumber $newScore) (continFiniteNumber $threshold))
       (if (continFiniteNumber $oldScore)
           (scoreImprovedFinite $newScore $oldScore $threshold)
           (if (== (get-type $oldScore) Number)
               (if (== (py-call (builtins.int (py-call (math.isinf $oldScore)))) 1)
                   (< $oldScore 0) False)
               False))
       False))

(= (scoreImprovedFinite $newScore $oldScore $threshold)
   (if (>= $threshold 0)
       (> $newScore (+ $oldScore $threshold))
       (let $margin (* (- 0 $threshold)
                       (if (< $oldScore 0) (- 0 $oldScore) $oldScore))
         (> $newScore (+ $oldScore $margin)))))
