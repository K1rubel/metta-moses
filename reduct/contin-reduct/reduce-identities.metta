;; Additive/multiplicative identities; requires contin-helpers.
(= (crIdentity $op) (if (== $op c_add) 0.0 1.0))
(= (crWithoutIdentities $op $children)
   (case $children
     ((() ())
      ((cons $child $rest)
       (if (crIsValue $child (crIdentity $op)) (crWithoutIdentities $op $rest)
           (cons $child (crWithoutIdentities $op $rest)))))))
