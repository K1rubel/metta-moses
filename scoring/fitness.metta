
!(bind! &space (new-space))

(= (removeFromSpace $row $space) (remove-atom $space $row))

;  This function counts the total occurrences of variable $X in an expression non-deterministically.
;; (= (findX $expr $x)
;;     (if (== $expr ())
;;         (empty)
;;         (let $a (superpose $expr)
;;             (if (or (== (get-metatype $a) Grounded) (== (get-metatype $a) Symbol))
;;                 (if (== $a $x)
;;                     1
;;                     (empty)
;;                 )
;;                 (findX $a $x)
;;             )
;;         )
;;     )
;; )

(= (findX $expr $x)
   (if (once (is-member $x $expr))
       True
       (List.any (map-atom $expr $ex
             (if (or (== (get-metatype $ex) Grounded) (== (get-metatype $ex) Symbol))
                 (== $ex $x)
                 (findX $ex $x))))))

 ;; Replaces variables in an expression with their corresponding truth values from the space.
 ;; If a variable is not found, it is replaced with undefined.
(= (replaceWithTruth $expr $space $spaceContent)
    (if (== (get-metatype $expr) Expression) 
        (if (== (cdr-atom $expr) ()) ;; Special case: (A) → Should replace as a symbol
            (map-atom $expr $ex (replaceWithTruth $ex $space $spaceContent))
            (let* (
                ($op (car-atom $expr))
                ($tuple (cdr-atom $expr)) 
                ($substitutedArgs (map-atom $tuple $tp (replaceWithTruth $tp $space $spaceContent)))
                ($tupleWithOp (cons-atom $op $substitutedArgs))
            )
                $tupleWithOp
            )
        )
        (let $res (collapse (match $space ($expr $value) $value))
            (if (== $res ()) undefined $res)
        )
    )
)


 ;; Evaluate a boolean expression to a grounded True/False value.
 ;; Handles: grounded literals, singleton wrappers like (True),
 ;; n-ary AND/OR via short-circuit helpers, and NOT in both the flat
 ;; (NOT A) and wrapped (NOT (A)) forms produced by preOrderExp.
(= (evaluate $expr)
    (if (== (get-metatype $expr) Grounded)
        $expr
        (if (== (cdr-atom $expr) ())
            (evaluate (car-atom $expr))
            (case (car-atom $expr)
                (
                    (AND (evaluateAnd (cdr-atom $expr)))
                    (OR  (evaluateOr  (cdr-atom $expr)))
                    (NOT (not (evaluate (cdr-atom $expr))))
                    ($_ ERROR)
                )
            )
        )
    )
)

 ;;  Evaluate OR subexpression
 ;;  Returns True if any argument evaluates to True, otherwise False.
(= (evaluateOr $args)
    (if (== $args ())
        False
        (let* 
          (
            ($first (car-atom $args))
            ($rest (cdr-atom $args))
          )
          (if (== (evaluate $first) True)
              True
              (evaluateOr $rest)
          )
        )
    )
)

 ;;  Evaluate AND subexpression
 ;;  Returns False if any argument evaluates to False, otherwise True.
(= (evaluateAnd $args)
    (if (== $args ())
        True
        (let* 
          (
            ($first (car-atom $args))
            ($rest (cdr-atom $args))
          )
          (if (== (evaluate $first) False)
              False
              (evaluateAnd $rest)
          )
        )
    )
)


;; ---------------------------------------------------------------------------
;; Columnar subtree evaluation over the wrapped preOrderExp shape:
;;   node = (AND (c1 .. ck)) / (OR (c1 .. ck)) / (NOT (c));  leaf = label | True/False
;; Every subtree is evaluated ONCE into a boolean column over all rows and
;; memoized in &subtreeCache, keyed by its ground wrapped expr (valid for the
;; run's single fixed table). Operator semantics live solely in the AND/OR/NOT
;; clauses (scoring/boolean-ops): on a cache miss a one-level template with
;; fresh shared vars is built once and every row is scored by unification --
;; sealed freshens the vars, a positional let binds the row's child values,
;; and one let-bound `reduce` dispatches the clause. A head with no clause
;; stays unreduced and scores worst (-1), like the old ERROR column.
;; Probes: tmp/probe-sealed.metta, tmp/probe-mapvars.metta.
;; ---------------------------------------------------------------------------

;; Extract a label's column from the row-major table. Unknown label -> loud
;; Error (malformed input); index-atom skips List.getByIdx's per-cell re-scan.
;(: varColumn (-> (ITable $a) Symbol (List Bool)))
(= (varColumn (mkITable $rows $labels) $label)
   (let $idx (List.index $labels $label)
        (if (== $idx -1)
            (Error $label "varColumn: label not found in table")
            (map-atom $rows $r (index-atom $r $idx)))))

;; Node row-template, built once per cache miss: ($varsTerm $exprTerm) sharing
;; fresh vars, e.g. (($v1 $v2) (AND ($v1 $v2))). map-atom's per-element
;; copy_term mints the k distinct vars; `cons` keeps the node inert (a bare
;; (AND ...) literal would fire the clause at build time).
(= (mkNodeTemplate $op $cvs)
   (let* (($vars (map-atom $cvs $c $v))
          ($e    (cons $op (cons $vars ()))))
     ($vars $e)))

;; One row through the template: sealed copies vars and expr together (the
;; template stays unbound for the next row), the let unifies the row's child
;; values positionally, and `reduce` dispatches the operator clause.
(= (evalRow $template $row)
   (let ($vars $e) $template
        (sealed $vars (let $vars $row (reduce $e)))))

;; Non-empty equal-length columns -> per-row value tuples (ground data only).
(= (transposeCols $cols)
   (if (== (car-atom $cols) ())
       ()
       (cons (map-atom $cols $c (car-atom $c))
             (transposeCols (map-atom $cols $c (cdr-atom $c))))))

;; Child columns -> node column: template once, then each transposed row
;; through evalRow via the var-safe map (map-atom would copy the template
;; per row). Childless AND/OR reduce their identity once and repeat it.
(= (combineNode $op $cvs $n)
   (if (== $cvs ())
       (List.repeat $n (let $e (cons $op (cons () ())) (reduce $e)))
       (let $t (mkNodeTemplate $op $cvs)
         (map evalRow $t (transposeCols $cvs)))))

;; Wrapped (sub)expression -> boolean column. Nodes AND label leaves are
;; memoized, so a label's table walk happens once per run. The map-atom over
;; the destructured children is the engine's only tree recursion.
;(: evalSubtree (-> Expression (ITable $a) Number (List Bool)))
(= (evalSubtree $exp $itable $n)
   (if (== (get-metatype $exp) Grounded)
       ;; grounded literal (True/False): constant column, not worth caching
       (List.repeat $n $exp)
       ;; operator node or label leaf: one shared memo path
       (chain (collapse (match &subtreeCache (subtree $exp $v) $v)) $hit
         (if (== $hit ())
             (let* (
                     ($col (if (== (get-metatype $exp) Expression)
                              ;; every node is uniformly ($op ($c1 .. $ck))
                              (let* ((($op $children) $exp)
                                     ($cvs (map-atom $children $child (evalSubtree $child $itable $n))))
                                (combineNode $op $cvs $n))
                              (varColumn $itable $exp)))
                    ($_   (add-atom &subtreeCache (subtree $exp $col))))
               $col)
             (car-atom $hit)))))


 ;; Per-row behavioral score: 0 if the expression matches the target, -1 if
 ;; it doesn't (or if any variable is undefined).  This matches the C++ MOSES
 ;; convention where the behavioral score is a list of 0s (correct) and -1s
 ;; (incorrect), so that sum(bScore) = -(#wrong) and penalizedScore =
 ;; sum(bScore) - lambda * complexity.
 ;;
 ;; Parameters:
 ;; - $expr: The boolean expression to evaluate.
 ;; - $row: (target . inputs) where target is True/False and inputs are
 ;;   variable bindings like ((A True) (B False) ...).
 ;;
 ;; Flow: bind inputs → substitute truth values → evaluate → compare to target.
(= (rowFitness $expr $row )
    (let*
      (
        ($target (car-atom $row))
        ($inputs (cdr-atom $row))
        ($add (map-atom $inputs $z (add-atom &space $z)))
        ($replacedExpr (let $acc (replaceWithTruth $expr &space (collapse (match &space $x $x))) (if (== (get-metatype $acc) Symbol) ($acc) $acc))) ;; Guard: prevents a bare symbol from propagating when no variables are defined.
        ($isFaulty  (findX $replacedExpr undefined))
        ($evaluateuatedResult  (if (not $isFaulty) (evaluate $replacedExpr) null ))
        ($remove (map-atom $inputs $z (remove-atom &space $z)))
      )
      (if (== $evaluateuatedResult $target) 0 -1)
      )
)


 ;; Sum the per-row behavioral scores across all data rows.
 ;; Returns a value in [-N, 0] where N is the number of rows:
 ;; 0 = all correct, -N = all wrong.  Matches the C++ MOSES
 ;; composite score convention (sum of behavioral score vector).
 ;;
 ;; Args:
 ;;   $expr: The boolean expression to evaluate.
 ;;   $data: List of (target . inputs) rows.
(= (fitness $expr $data)
    (if (== $data ())
        0
        (let $result (map-atom $data $d (rowFitness $expr $d)) (sum $result))
    )
)

 ;; Penalized fitness: accuracy minus a complexity penalty.
 ;; Formula: penalizedScore = sum(bScore) - lambda * treeComplexity
 ;; where treeComplexity counts variable leaves (AND/OR/NOT = 0, each
 ;; argument = 1), matching the C++ MOSES tree_complexity() definition.
 ;; Lambda controls the accuracy-vs-simplicity trade-off.
(= (penalizedFitness $expr $data $lambda)
    (let*
      (
        ($score (fitness $expr $data))
        ($complexity (treeComplexity (buildTree $expr)))
      )
        (- $score (* $lambda $complexity))
    )
)


