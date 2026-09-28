;; ==============================================================================
;; Module: scoring/contin-eval.metta
;; Purpose: Continuous Evaluation Context and Tagged Result Types
;;
;; Phase: Phase 0 — Freeze Contracts (closes Step 1)
;;        Phase 1 will add the full row-by-row evaluator implementation.
;;
;; Reference (commit f88ccd3279f3dd853e8c23103be5376a0e7eafc1):
;;   - moses/comboreduct/interpreter/eval.cc — operator evaluation and failure handling
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
;; Declared here so that contin-eval.metta (Phase 1) and contin-reduct.metta
;; (Phase 1) can both import this file and share the same atom identity.
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
;; Failure boundary (implemented by the scorer in Phase 1)
;; ------------------------------------------------------------------------------
;; Keep mkCEvalError until the candidate-scoring boundary, where it maps to the
;; existing composite (worstCscore), with explicit evaluated/invalid status.
;; Do not invent a continuous raw-score sentinel: a valid negative SSE can be
;; less than any selected finite cutoff (including -1e9 or the legacy -1e100).
;; Phase 1 must preserve validity separately when ordering candidates; changing
;; the global worstCscore or wiring the pipeline is outside this Phase 0 module.
