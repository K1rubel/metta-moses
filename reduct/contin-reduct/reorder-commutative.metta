;; Safe binary leaf ordering; requires contin-helpers.
;; Binary addition is commutative in binary64. Leaf-only ordering cannot change
;; which numerical/domain error is encountered. Symbol labels precede strings
;; when their text is identical. Longer sums retain their evaluation order.
(= (crLabelBefore $a $b)
   (let* (($x (crValue $a)) ($y (crValue $b))
          ($sx (py-call (builtins.str $x))) ($sy (py-call (builtins.str $y))))
     (if (== $sx $sy)
         (and (not (== (get-type $x) String)) (== (get-type $y) String))
         (== (py-call (builtins.int (py-call (operator.lt $sx $sy)))) 1))))
(= (crOrderPair $op $children)
   (case $children
     ((($a $b)
       (if (and (crLabel $a) (crNumber $b))
           ;; Never move zero before an evaluated label in a product.
           (if (or (== $op c_add) (not (crIsValue $b 0))) ($b $a) $children)
           (if (and (== $op c_add) (and (crLabel $a) (crLabel $b)))
               (if (crLabelBefore $b $a) ($b $a) $children) $children)))
      ($other $children))))
