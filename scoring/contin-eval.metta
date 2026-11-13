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

;; Accessors: $context is an mkContinCtx record. Each function returns the
;; named stored field: table, error type, complexity ratio, search mode, or
;; raw target score respectively.

(= (continCtxTable         (mkContinCtx $tbl $err $ratio $mode $target)) $tbl)
(= (continCtxErrorType     (mkContinCtx $tbl $err $ratio $mode $target)) $err)
(= (continCtxComplexityRatio (mkContinCtx $tbl $err $ratio $mode $target)) $ratio)
(= (continCtxSearchMode    (mkContinCtx $tbl $err $ratio $mode $target)) $mode)
(= (continCtxTargetScore   (mkContinCtx $tbl $err $ratio $mode $target)) $target)

;; isContinContext: $context is any value. Returns True only for an
;; mkContinCtx record; malformed or unrelated values return False.
;; Dispatcher: True only when the value is genuinely a continuous context.
;; Used to guard every domain-dispatch point so continuous problems never
;; fall through to the Boolean default branch.

(= (isContinContext $context)
   (case $context
     (
      ((mkContinCtx $tbl $err $ratio $mode $target) True)
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

;; isCEvalOk: $result is a tagged evaluation result. Returns True for
;; mkCEvalOk and False for mkCEvalError.
;; getCEvalValue: $result is a successful mkCEvalOk record. Returns its number.
;; getCEvalError: $result is a failed mkCEvalError record. Returns its reason.
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

;; continFiniteNumber: $value is a candidate numeric value. Returns True if it
;; is a finite number representable by the runtime's binary64 conversion;
;; non-numbers, NaN/Inf, and conversion exceptions return False.
;; Catch native arithmetic/Python exceptions AND reject returned NaN/Inf.
;; Binary64 conversion matches C++ contin_t, including integer overflow.

(= (continFiniteNumber $value)
   (if (== (get-type $value) Number)
       (== (catch (py-call (builtins.int (py-call (math.isfinite $value))))) 1) False))

;; continCheckedNumber: $value is the result of a numeric operation. Returns
;; mkCEvalOk with the unchanged value when finite, otherwise NonFinite error.

(= (continCheckedNumber $value)
   (if (continFiniteNumber $value) (mkCEvalOk $value) (mkCEvalError "NonFinite")))

;; continIsZero: $value is a number. Returns True exactly for numeric zero.

(= (continIsZero $value) (and (<= $value 0) (>= $value 0)))

;; continLiteral: $value is an AST leaf value. Converts numeric values to
;; finite float evaluation results; returns NonNumeric for other types.

(= (continLiteral $value)
   (if (== (get-type $value) Number)
       (continCheckedNumber (catch (py-call (builtins.float $value))))
       (mkCEvalError "NonNumeric")))

;; continIsOperator: $op is a candidate AST operator/label. Returns True for
;; the supported continuous operators and False for every other atom.
;; XXX -- to do this could be done using is-member very neatly
;;(= (continIsOperator $op)
;;   (case $op 
;;    (
;;      (c_add True) 
;;      (c_mul True) 
;;      (c_div True) 
;;      (c_sin True)
;;      (c_log True) 
;;      (c_exp True) 
;;      ($other False))))

(= (continIsOperator $op) (is-member $op (c_add c_mul c_div c_sin c_log c_exp )))

;; continLookup: $label is an input feature name and $env is a list of
;; mkContinBinding(label,value) records. Returns the finite bound value, or
;; UnknownLabel / InvalidEnvironment error when lookup cannot succeed.
;; Environment: ((mkContinBinding label value) ...), inputs only, never target.

(= (continLookup $label $env)
   (case $env
     (
      (() (mkCEvalError "UnknownLabel"))
      ((cons (mkContinBinding $key $value) $rest)
       (if (== $label $key) (continLiteral $value) (continLookup $label $rest)))
      ($badEnv (mkCEvalError "InvalidEnvironment")))))

;; Runtime dispatch resolves mutual recursion under PeTTa's eager compilation.
;; continCall1: $function is a unary MeTTa function symbol and $arg its input.
;; Returns that function's result; this callback indirection permits mutual
;; recursion to compile under PeTTa's evaluation rules.

(= (continCall1 $function $arg) ($function $arg))

;; continCall2: same callback bridge for a function of two arguments.

(= (continCall2 $function $first $second) ($function $first $second))

;; continEvalFold: $op is c_add or c_mul, $children are AST children, $env is
;; the row binding environment, and $acc is the identity/current fold value.
;; Returns the folded mkCEvalOk number or the first child/arithmetic error.

(= (continEvalFold $op $children $env $acc)
   (case $children
     (
      (() (mkCEvalOk $acc))
      ((cons $child $rest)
        (case (continEval $child $env)
         (
          ((mkCEvalError $reason) (mkCEvalError $reason))
          ((mkCEvalOk $value)
           (let $next (continCheckedNumber
                       (catch (if (== $op c_add) (+ $acc $value) (* $acc $value))))
             (case $next
               (
                ((mkCEvalError $failure) (mkCEvalError $failure))
                ((mkCEvalOk $result)
                 (if (and (== $op c_mul) (continIsZero $result))
                     (mkCEvalOk $result)
                     (continEvalFold $op $rest $env $result))))))))))
      ($badChildren (mkCEvalError "InvalidTree")))))

;; continEvalUnary: $op is c_log, c_exp, or c_sin; $children is the operator's
;; child list and $env is the row environment. Returns the computed finite
;; mkCEvalOk value, a propagated child error, LogNonPositive/NonFinite, or
;; ArityMismatch when the list does not contain exactly one child.

(= (continEvalUnary $op $children $env)
   (case $children
     (
      (($child)
       (case (continEval $child $env)
         (
          ((mkCEvalError $reason) (mkCEvalError $reason))
          ((mkCEvalOk $value)
           (case $op
             (
              (c_log (if (<= $value 0) (mkCEvalError "LogNonPositive")
                         (continCheckedNumber (catch (py-call (math.log $value))))))
              (c_exp (continCheckedNumber (catch (py-call (math.exp $value)))))
              (c_sin (continCheckedNumber (catch (py-call (math.sin $value)))))))))))
      ($wrongArity (mkCEvalError "ArityMismatch")))))

;; continEvalDivision: $children is the numerator/denominator pair and $env is
;; the row environment. Returns their finite quotient, propagates evaluation
;; errors, or returns DivisionByZero / ArityMismatch. A zero numerator returns
;; zero without evaluating the denominator.

(= (continEvalDivision $children $env)
   (case $children
     (
      (($numerator $denominator)
       (case (continEval $numerator $env)
         (
          ((mkCEvalError $reason) (mkCEvalError $reason))
          ((mkCEvalOk $num)
           (if (continIsZero $num) (mkCEvalOk $num)
               (case (continCall2 continEval $denominator $env)
                 (
                  ((mkCEvalError $denError) (mkCEvalError $denError))
                  ((mkCEvalOk $den)
                   (if (continIsZero $den) (mkCEvalError "DivisionByZero")
                       (continCheckedNumber (catch (/ $num $den))))))))))))
      ($wrongArity (mkCEvalError "ArityMismatch")))))

;; continEval: $tree is a continuous AST and $env is the input-row binding
;; list. Returns mkCEvalOk(number) or mkCEvalError(reason). Skipped subtrees
;; are not evaluated. Empty add/mul
;; require normalization by the reducer: C++ childless placeholders
;; are not ordinary numeric zero/one identities.

(= (continEval $tree $env)
   (case $tree
     (
      ((mkTree (mkNode $op) $children)
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

;; continTreeWellFormed: $tree is a candidate AST. Returns True if it and all
;; descendants have valid tree structure; it does not evaluate labels,
;; arithmetic, or operator arity.
;; Structural validation prevents malformed dead subtrees breaking complexity.
;; It does not eagerly check their labels, numerical operations, or arities.

(= (continTreeWellFormed $tree)
   (case $tree
     (((mkTree (mkNode $op) $children)
       (continCall1 continChildrenWellFormed $children))
      ($badTree False))))

;; continChildrenWellFormed: $children is a proper list of AST children.
;; Returns True only when every child subtree passes continTreeWellFormed.

(= (continChildrenWellFormed $children)
   (case $children
     (
      (() True)
      ((cons $child $rest) (if (continTreeWellFormed $child) (continChildrenWellFormed $rest) False))
      ($badChildren False))))

;; Strict finite, rectangular, column-major tables. Target-only tables support
;; intercept-only models. Labels are unique symbols/strings, not operator tags.
;; continListLength: $xs is expected to be a proper list. Returns its length,
;; or -1 for a value that is not a proper list.

(= (continListLength $xs)
   (case $xs
     (
      (() 0)
      ((cons $head $tail) (let $n (continListLength $tail) (if (< $n 0) -1 (+ 1 $n))))
      ($notAList -1))))

;; continContains: $value is compared with elements of $xs. Returns True when
;; an equal element occurs, otherwise False.
;; XXX - replace this with already existing utility function

(= (continContains $value $xs)
   (case $xs
     (
      (() False)
      ((cons $head $tail) (if (== $value $head) True (continContains $value $tail))))))

;; continValidLabels: $labels is the table header and $seen is the labels
;; already accepted. Returns True if labels are unique symbols/strings and do
;; not collide with continuous operators; otherwise False.

(= (continValidLabels $labels $seen)
   (case $labels
     (
      (() True)
      ((cons $label $rest)
       (if (and (or (== (get-metatype $label) Symbol) (== (get-type $label) String))
                (and (not (continIsOperator $label)) (not (continContains $label $seen))))
           (continValidLabels $rest (cons $label $seen)) False))
      ($badLabels False))))

;; continFiniteColumn: $column is one table column. Returns True when it is a
;; proper list containing only finite numbers.
;; XXX --- to do -> this could be done with fold
;;(= (continFiniteColumn $column)
;;   (case $column
;;     (
;;      (() True)
;;      ((cons $value $rest)
;;       (if (continFiniteNumber $value) (continFiniteColumn $rest) False))
;;      ($badColumn False))))

(= (continFiniteColumn $column)  (foldl-atom $column True $acc $val (and (continFiniteNumber $val) $acc)))

;; continValidColumns: $columns is a list of table columns and $n is the
;; required row count. Returns True when every column is finite and has length n.
;; XXX --- to do -- use fold for this one too

;;(= (continValidColumns $columns $n)
;;   (case $columns
;;     (
;;      (() True)
;;      ((cons $column $rest)
;;       (if (and (== (continListLength $column) $n) (continFiniteColumn $column))
;;           (continValidColumns $rest $n) 
;;           False))
;;      ($badColumns False))))

(= (continValidColumns $columns $n) 
  (foldl-atom $columns True $acc $column 
                                        (and $acc (and (== (continListLength $column) $n) (continFiniteColumn $column)))))
;; continSplitTable: 
;;      $columns is validated column-major data and 
;;      $labels is its header (inputs followed by target). 
;;      Returns mkContinData(inputs, feature
;;      columns, target column), separating the final column as the target.

(= (continSplitTable $columns $labels)
   (case ($columns $labels)
     (
      ((($targets) ($targetLabel)) (mkContinData () () $targets))
      (((cons $column $moreColumns) (cons $label $moreLabels))
          (let (mkContinData $inputs $features $targets) (continSplitTable $moreColumns $moreLabels)
                (mkContinData (cons $label $inputs) (cons $column $features) $targets))))))

;; Testing continSplitTable using column major table

!(continSplitTable ((1)) (A))
!(continSplitTable ((1) (2)) (A B))

;; an example table

(= (table1) 
      (mkITable 
        (cons (cons 1 (cons 3 ()))
        (cons (cons 2 (cons 4 ())) ()))
              (cons A (cons B ()))))

;; without the cons stuff
(= (table2)
    (mkITable ((1 3) (2 4)) (A B)))

;; What would my implementation of the column major table would look like 

;; continPrepareTable: 
;;      $table is an mkITable with column-major data and header.
;;      Returns mkContinData after validating nonempty, rectangular, finite columns
;;      and labels, or mkCEvalError("InvalidTable").

(= (continPrepareTable $table)
   (case $table
     (
      ((mkITable (cons $column $rest) $labels)
        (if (and (== (continListLength $labels) (+ 1 (continListLength $rest)))
                (continValidLabels $labels ()))
             (let $n (continListLength $column)
               (if (and (> $n 0) (continValidColumns (cons $column $rest) $n))
                   (continSplitTable (cons $column $rest) $labels)
                   (mkCEvalError "InvalidTable")))
           (mkCEvalError "InvalidTable")))
      ($badTable (mkCEvalError "InvalidTable")))))

!(continPrepareTable (table1))
!(continPrepareTable (table1))

;; continPrepareContext: $context is the run's mkContinCtx. Returns validated
;; mkContinData after checking error type, mode, finite nonnegative complexity
;; ratio, finite target, and table; any invalid setting returns mkCEvalError.

(= (continPrepareContext $context)
   (case $context
     (
       ((mkContinCtx $table $error $ratio $mode $target)
         (if (and (or (== $error squared_error) (== $error abs_error))
                (or (== $mode linear) (== $mode nonlinear)))
           (if (and (continFiniteNumber $ratio) (continFiniteNumber $target))
               (if (>= $ratio 0) (continPrepareTable $table) (mkCEvalError "InvalidContext"))
               (mkCEvalError "InvalidContext"))
           (mkCEvalError "InvalidContext")))
      ($badContext (mkCEvalError "InvalidContext")))))

;; continRowEnvironment: $labels and $columns are parallel remaining lists;
;; each column is a list of row values. Returns bindings from each label to the
;; head of its column (one sample row).

(= (continRowEnvironment () ()) ())
(= (continRowEnvironment (cons $label $labels) (cons (cons $value $tail) $columns))
   (cons (mkContinBinding $label $value) (continRowEnvironment $labels $columns)))

;; continNextColumns: $columns is a list of nonempty columns. Returns the same
;; columns with the first row value removed from each, ready for the next row.

(= (continNextColumns ()) ())
(= (continNextColumns (cons (cons $value $tail) $columns))
   (cons $tail (continNextColumns $columns)))
