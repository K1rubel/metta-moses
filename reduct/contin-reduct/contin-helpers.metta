;; Shared continuous tree predicates and constructors.
;; Requires scoring/contin-eval.
(= (crNumber $tree)
   (case $tree
     (((mkTree (mkNode $value) ()) (continFiniteNumber $value)) 
     ($other False))))
(= (crValue (mkTree (mkNode $value) ())) $value)
(= (crLeaf $value) (mkTree (mkNode $value) ()))
(= (crIsValue $tree $value)
   (if (crNumber $tree) (and (<= (crValue $tree) $value) (>= (crValue $tree) $value)) False))
(= (crLabel $tree)
   (case $tree
     (((mkTree (mkNode $label) ())
       (and (not (continIsOperator $label))
            (or (== (get-metatype $label) Symbol) (== (get-type $label) String))))
      ($other False))))
