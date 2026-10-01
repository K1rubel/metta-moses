;; Step 6 MVP, not the full C++ contin_reduction rule set. Dependencies:
;; scoring/contin-eval, representation/contin-stepper (list helpers).
;; Only plain materialized trees enter here. Never reduce CTK scaffolds.
;; Preserve error/short-circuit order and IEEE grouping: arbitrary associative
;; flattening, sorting, x*0, x/x and log/exp cancellation are NOT safe rewrites.
;; Load helpers, identity, ordering, n-ary, division and folding modules first.
;; Entry points own imports, as in the Boolean/action domains.
(= (crChildren $children)
   (case $children
     ((() ())
      ((cons $child $rest) (cons (continCall1 crReduce $child) (crChildren $rest))))))
(= (crReduce (mkTree (mkNode $op) $children))
   (let* (($reduced (crChildren $children))
          ($tree (case $op
                   ((c_add (crNary c_add $reduced))
                    (c_mul (crNary c_mul $reduced))
                    (c_div (crDivision $reduced))
                    ($other (mkTree (mkNode $op) $reduced))))))
     (crFoldClosed (crRepeatedNonlinear $tree))))
(= (reduceContinTree $tree)
   (if (continTreeWellFormed $tree) (crReduce $tree) (mkCEvalError "InvalidMaterializedTree")))

;; The shared cache/scorer must see this phenotype, not the raw decoded tree.
;; Raw materializeContinCandidate remains available for stepper/schema tests.
(= (finalizeContinCandidate $rep $instance)
   (case (continCall2 materializeContinCandidate $rep $instance)
     (((mkCEvalError $reason) (mkCEvalError $reason))
      ($tree (reduceContinTree $tree)))))
