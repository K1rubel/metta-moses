;; Closed-expression folding; requires contin-helpers, contin-eval
;; and contin-stepper's late-call helper for mutual recursion.
;; Folding is attempted on closed expressions only. Failed folds stay as ASTs
;; so the counted scorer records the numerical failure (or a parent skips it).
(= (crClosedChildren $children)
   (case $children
     ((() True)
      ((cons $child $rest)
       (if (continCall1 crClosed $child) (crClosedChildren $rest) False)))))
(= (crClosed (mkTree (mkNode $op) $children))
   (if (== $children ()) (== (get-type $op) Number)
       (and (continIsOperator $op) (crClosedChildren $children))))
(= (crFoldClosed $tree)
   (if (crClosed $tree)
       (case (continEval $tree ()) (((mkCEvalOk $value) (crLeaf $value)) ($failed $tree))) $tree))
