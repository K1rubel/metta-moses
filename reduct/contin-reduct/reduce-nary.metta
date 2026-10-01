;; Addition/product simplification; requires reduce-identities,
;; reorder-commutative, contin-stepper list helpers and contin-eval.
;; Each recursion removes a node, identity, or constant-prefix operand. Only a
;; LEFTMOST same-operator child can be leveled without changing IEEE grouping.
(= (crNary $op $children)
   (let $xs (crWithoutIdentities $op $children)
     (case $xs
       ((() (crLeaf (crIdentity $op)))
        (($only) $only)
        ((cons $first $rest)
         (if (and (== $op c_mul) (crIsValue $first 0)) (crLeaf 0.0)
             (case $first
               (((mkTree (mkNode $innerOp) $innerChildren)
                 (if (== $innerOp $op)
                     (crNary $op (continAppend $innerChildren $rest))
                     (let (cons $second $tail) $rest
                       (if (and (crNumber $first) (crNumber $second))
                           (case (continEval (mkTree (mkNode $op) ($first $second)) ())
                             (((mkCEvalOk $folded) (crNary $op (cons (crLeaf $folded) $tail)))
                              ($failed (mkTree (mkNode $op) $xs))))
                           (mkTree (mkNode $op) (crOrderPair $op $xs))))))))))))))
