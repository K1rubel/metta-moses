;; Exact duplicate NONLEAF addends: t+t -> 2*t. Evaluation of t and its failure
;; is preserved; binary64 doubling is exact subject to the same overflow.
;; Do not distribute, factor different terms, cancel x/x or undo log/exp:
;; those algebraic rewrites can hide numerical failures or change rounding.
;; Leaf duplicates retain the affine builder's existing rejection contract.
(= (crRepeatedNonlinear $tree)
   (case $tree
     (((mkTree (mkNode c_add) ($first $second))
       (if (== $first $second)
           (case $first
             (((mkTree (mkNode $op) (cons $head $tail))
               (mkTree (mkNode c_mul) ((crLeaf 2.0) $first)))
              ($leaf $tree))) $tree))
      ($other $other))))
