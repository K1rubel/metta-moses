;; ==============================================================================
;; Module: scoring/contin-eval.metta
;; Purpose: Continuous Evaluation Context and Tagged Result Types
;;
;; Phase 1 / Step 4: numerical evaluation and in-memory table validation.
;;
;; Reference (commit f88ccd3279f3dd853e8c23103be5376a0e7eafc1):
;;   - moses/comboreduct/interpreter/interpreter.cc — contin_eval
;;   - moses/comboreduct/combo/vertex.h — operator symbol definitions
;;   - moses/moses/scoring/behave_cscore.cc (L63-86) — exception -> worst_composite_score
;;
;; CONCEPTS:
;; ---------
;; 1. Continuous context (mkContinCtx):
;;    Carries all configuration needed to evaluate and score a continuous candidate.
;;    The plan requires this to be threaded explicitly through every stage —
;;    selection, representation building, optimization, scoring, merging — so that
;;    domain dispatch never guesses from tree structure.
;;
;;    Fields:
;;      $itable          : mkITable — column-major dataset with exact header labels
;;      $errorType       : squared_error | abs_error
;;      $complexityRatio : Number   — complexity penalty coefficient
;;      $searchMode      : linear | nonlinear
;;      $targetScore     : Number   — raw termination threshold (normally 0.0)
;;
;; 2. Continuous AST operator tags:
;;    Explicit atom names prevent continuous nodes from being parsed or reduced
;;    by existing Boolean / action rules.  Operators defined here are those
;;    in the active C++ vocabulary (vertex.h).  Mixed-domain operators
;;    (c_if, c_gt_zero, c_impulse) are outside the linear MVP scope.
;;
;;    MVP operators: c_add  c_mul  c_div  c_sin  c_log  c_exp
;;    (ABS_LOG is documented in vertex.h but NOT in the active C++ vocabulary.)
;;
;; 3. Tagged evaluation result (mkCEvalOk / mkCEvalError):
;;    Evaluation must not silently substitute 0 or a large sentinel.  Any
;;    operation failure — division by zero, log of non-positive, non-finite
;;    result, unknown label, arity mismatch — must return mkCEvalError.
;;    The scorer maps any mkCEvalError on any row to (worstCscore) for
;;    the whole candidate (parity with behave_cscore.cc L63-86).
;; ==============================================================================

;; ------------------------------------------------------------------------------
;; Continuous Context: mkContinCtx
;; ------------------------------------------------------------------------------
;; The single source of truth for what domain a run operates in.
;; Domain-specific code MUST match on (mkContinCtx ...) — never infer the
;; domain from incidental tree contents.
(: ContinCtx Type)
(: mkContinCtx (-> Atom Atom Number Atom Number ContinCtx))

;; Accessors
(= (continCtxTable         (mkContinCtx $tbl $err $ratio $mode $target)) $tbl)
(= (continCtxErrorType     (mkContinCtx $tbl $err $ratio $mode $target)) $err)
(= (continCtxComplexityRatio (mkContinCtx $tbl $err $ratio $mode $target)) $ratio)
(= (continCtxSearchMode    (mkContinCtx $tbl $err $ratio $mode $target)) $mode)
(= (continCtxTargetScore   (mkContinCtx $tbl $err $ratio $mode $target)) $target)

;; Dispatcher: True only when the value is genuinely a continuous context.
;; Used to guard every domain-dispatch point so continuous problems never
;; fall through to the Boolean default branch.
(= (isContinContext $context)
   (case $context
     (((mkContinCtx $tbl $err $ratio $mode $target) True)
      ($other False))))

;; ------------------------------------------------------------------------------
;; Continuous AST Operator Tags
;; ------------------------------------------------------------------------------
;; These atoms are used as node operators in continuous program trees.
;; Separate names prevent confusion with grounded arithmetic operators or
;; Boolean / action tree operators.
;;
;; Shared with reduct/contin-reduct/contin-reduction.metta (Step 6).
;;
;; MVP scope (linear + nonlinear continuous):
;;   c_add — n-ary addition           complexity weight: 0
;;   c_mul — n-ary multiplication     complexity weight: 0
;;   c_div — binary division          complexity weight: 1
;;   c_sin — unary sine               complexity weight: 1
;;   c_log — unary natural log        complexity weight: 1
;;   c_exp — unary exponential        complexity weight: 1
;;
;; Reserved for mixed domain (outside Phase 0-5 scope):
;;   c_if, c_gt_zero, c_impulse
;;
;; Note: ABS_LOG exists in vertex.h but is NOT part of the active C++ vocabulary
;; and must NOT be introduced here.

;; (Operator names are plain MeTTa atoms; no type annotation is required to
;;  make them usable.  They are documented here so every module that matches
;;  on them imports from the same canonical source.)

;; ------------------------------------------------------------------------------
;; Tagged Evaluation Results
;; ------------------------------------------------------------------------------
;; Every expression evaluation on a single input row must return one of:

;; Success — $val is a finite floating-point number.
(: CEvalResult Type)
(: mkCEvalOk (-> Number CEvalResult))

;; Failure — $reason is a descriptive string.
;; Failure conditions (all must be caught; none may be silently substituted):
;;   "DivisionByZero"  — evaluated denominator is exactly zero for nonzero numerator
;;                      Tiny nonzero denominators are legal if the result is finite.
;; C++ short-circuits a zero numerator to zero without visiting the denominator,
;; and multiplication stops after a zero product (interpreter.cc contin_eval).
;;   "LogNonPositive"  — argument to c_log is <= 0
;;   "NonFinite"       — result is NaN or Inf (e.g. exp overflow)
;;   "UnknownLabel"    — input feature label not found in the row environment
;;   "ArityMismatch"   — wrong number of child trees for the operator
(: mkCEvalError (-> String CEvalResult))

;; Predicates and extractors
(= (isCEvalOk (mkCEvalOk $val))   True)
(= (isCEvalOk (mkCEvalError $err)) False)

(= (getCEvalValue (mkCEvalOk $val))   $val)
(= (getCEvalError (mkCEvalError $err)) $err)

;; ------------------------------------------------------------------------------
;; Failure boundary (implemented by contin-score.metta)
;; ------------------------------------------------------------------------------
;; Keep mkCEvalError until the candidate-scoring boundary, where it maps to the
;; existing composite (worstCscore), with explicit evaluated/invalid status.
;; Do not invent a continuous raw-score sentinel: a valid negative SSE can be
;; less than any selected finite cutoff (including -1e9 or the legacy -1e100).
;; Candidate validity is separate from the global worstCscore sentinel.

;; Catch native arithmetic/Python exceptions AND reject returned NaN/Inf.
;; Binary64 conversion matches C++ contin_t, including integer overflow.
(= (continFiniteNumber $value)
   (if (== (get-type $value) Number)
       (== (catch (py-call (builtins.int (py-call (math.isfinite $value))))) 1) False))
(= (continCheckedNumber $value)
   (if (continFiniteNumber $value) (mkCEvalOk $value) (mkCEvalError "NonFinite")))
(= (continIsZero $value) (and (<= $value 0) (>= $value 0)))
(= (continLiteral $value)
   (if (== (get-type $value) Number)
       (continCheckedNumber (catch (py-call (builtins.float $value))))
       (mkCEvalError "NonNumeric")))
(= (continIsOperator $op)
   (case $op ((c_add True) (c_mul True) (c_div True) (c_sin True)
              (c_log True) (c_exp True) ($other False))))

;; Environment: ((mkContinBinding label value) ...), inputs only, never target.
(= (continLookup $label $env)
   (case $env
     ((() (mkCEvalError "UnknownLabel"))
      ((cons (mkContinBinding $key $value) $rest)
       (if (== $label $key) (continLiteral $value) (continLookup $label $rest)))
      ($badEnv (mkCEvalError "InvalidEnvironment")))))

;; Runtime dispatch resolves mutual recursion under PeTTa's eager compilation.
(= (continCall1 $function $arg) ($function $arg))
(= (continCall2 $function $first $second) ($function $first $second))
(= (continEvalFold $op $children $env $acc)
   (case $children
     ((() (mkCEvalOk $acc))
      ((cons $child $rest)
       (case (continCall2 continEval $child $env)
         (((mkCEvalError $reason) (mkCEvalError $reason))
          ((mkCEvalOk $value)
           (let $next (continCheckedNumber
                       (catch (if (== $op c_add) (+ $acc $value) (* $acc $value))))
             (case $next
               (((mkCEvalError $failure) (mkCEvalError $failure))
                ((mkCEvalOk $result)
                 (if (and (== $op c_mul) (continIsZero $result))
                     (mkCEvalOk $result)
                     (continEvalFold $op $rest $env $result))))))))))
      ($badChildren (mkCEvalError "InvalidTree")))))
(= (continEvalUnary $op $children $env)
   (case $children
     ((($child)
       (case (continCall2 continEval $child $env)
         (((mkCEvalError $reason) (mkCEvalError $reason))
          ((mkCEvalOk $value)
           (case $op
             ((c_log (if (<= $value 0) (mkCEvalError "LogNonPositive")
                         (continCheckedNumber (catch (py-call (math.log $value))))))
              (c_exp (continCheckedNumber (catch (py-call (math.exp $value)))))
              (c_sin (continCheckedNumber (catch (py-call (math.sin $value)))))))))))
      ($wrongArity (mkCEvalError "ArityMismatch")))))
(= (continEvalDivision $children $env)
   (case $children
     ((($numerator $denominator)
       (case (continCall2 continEval $numerator $env)
         (((mkCEvalError $reason) (mkCEvalError $reason))
          ((mkCEvalOk $num)
           (if (continIsZero $num) (mkCEvalOk $num)
               (case (continCall2 continEval $denominator $env)
                 (((mkCEvalError $denError) (mkCEvalError $denError))
                  ((mkCEvalOk $den)
                   (if (continIsZero $den) (mkCEvalError "DivisionByZero")
                       (continCheckedNumber (catch (/ $num $den))))))))))))
      ($wrongArity (mkCEvalError "ArityMismatch")))))

;; Public row evaluator. Skipped subtrees are not evaluated. Empty add/mul
;; require normalization by the reducer: C++ childless placeholders
;; are not ordinary numeric zero/one identities.
(= (continEval $tree $env)
   (case $tree
     (((mkTree (mkNode $op) $children)
       (case $op
         ((c_add (if (== $children ()) (mkCEvalError "ArityMismatch")
                     (continEvalFold c_add $children $env 0.0)))
          (c_mul (if (== $children ()) (mkCEvalError "ArityMismatch")
                     (continEvalFold c_mul $children $env 1.0)))
          (c_div (continEvalDivision $children $env))
          (c_log (continEvalUnary c_log $children $env))
          (c_exp (continEvalUnary c_exp $children $env))
          (c_sin (continEvalUnary c_sin $children $env))
          ($leaf (if (== $children ())
                     (if (== (get-type $op) Number) (continLiteral $op)
                         (continLookup $op $env))
                     (mkCEvalError "UnknownOperator"))))))
      ($malformed (mkCEvalError "InvalidTree")))))

;; Structural validation prevents malformed dead subtrees breaking complexity.
;; It does not eagerly check their labels, numerical operations, or arities.
(= (continTreeWellFormed $tree)
   (case $tree
     (((mkTree (mkNode $op) $children)
       (continCall1 continChildrenWellFormed $children))
      ($badTree False))))
(= (continChildrenWellFormed $children)
   (case $children
     ((() True)
      ((cons $child $rest)
       (if (continTreeWellFormed $child) (continChildrenWellFormed $rest) False))
      ($badChildren False))))

;; Strict finite, rectangular, column-major tables. Target-only tables support
;; intercept-only models. Labels are unique symbols/strings, not operator tags.
(= (continListLength $xs)
   (case $xs
     ((() 0)
      ((cons $head $tail)
       (let $n (continListLength $tail) (if (< $n 0) -1 (+ 1 $n))))
      ($notAList -1))))
(= (continContains $value $xs)
   (case $xs
     ((() False)
      ((cons $head $tail) (if (== $value $head) True (continContains $value $tail))))))
(= (continValidLabels $labels $seen)
   (case $labels
     ((() True)
      ((cons $label $rest)
       (if (and (or (== (get-metatype $label) Symbol) (== (get-type $label) String))
                (and (not (continIsOperator $label)) (not (continContains $label $seen))))
           (continValidLabels $rest (cons $label $seen)) False))
      ($badLabels False))))
(= (continFiniteColumn $column)
   (case $column
     ((() True)
      ((cons $value $rest)
       (if (continFiniteNumber $value) (continFiniteColumn $rest) False))
      ($badColumn False))))
(= (continValidColumns $columns $n)
   (case $columns
     ((() True)
      ((cons $column $rest)
       (if (and (== (continListLength $column) $n) (continFiniteColumn $column))
           (continValidColumns $rest $n) False))
      ($badColumns False))))
(= (continSplitTable $columns $labels)
   (case ($columns $labels)
     (((($targets) ($targetLabel)) (mkContinData () () $targets))
      (((cons $column $moreColumns) (cons $label $moreLabels))
       (let (mkContinData $inputs $features $targets) (continSplitTable $moreColumns $moreLabels)
         (mkContinData (cons $label $inputs) (cons $column $features) $targets))))))
(= (continPrepareTable $table)
   (case $table
     (((mkITable (cons $column $rest) $labels)
       (if (and (== (continListLength $labels) (+ 1 (continListLength $rest)))
                (continValidLabels $labels ()))
           (let $n (continListLength $column)
             (if (and (> $n 0) (continValidColumns (cons $column $rest) $n))
                 (continSplitTable (cons $column $rest) $labels)
                 (mkCEvalError "InvalidTable")))
           (mkCEvalError "InvalidTable")))
      ($badTable (mkCEvalError "InvalidTable")))))
(= (continPrepareContext $context)
   (case $context
     (((mkContinCtx $table $error $ratio $mode $target)
       (if (and (or (== $error squared_error) (== $error abs_error))
                (or (== $mode linear) (== $mode nonlinear)))
           (if (and (continFiniteNumber $ratio) (continFiniteNumber $target))
               (if (>= $ratio 0) (continPrepareTable $table) (mkCEvalError "InvalidContext"))
               (mkCEvalError "InvalidContext"))
           (mkCEvalError "InvalidContext")))
      ($badContext (mkCEvalError "InvalidContext")))))
;; These two helpers consume validated columns only.
(= (continRowEnvironment () ()) ())
(= (continRowEnvironment (cons $label $labels) (cons (cons $value $tail) $columns))
   (cons (mkContinBinding $label $value) (continRowEnvironment $labels $columns)))
(= (continNextColumns ()) ())
(= (continNextColumns (cons (cons $value $tail) $columns))
   (cons $tail (continNextColumns $columns)))
