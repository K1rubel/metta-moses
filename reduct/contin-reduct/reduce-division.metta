;; Division simplification; requires contin-helpers and reduce-nary.
;; Safe inversion subset: denominator is an exact power of two and its
;; reciprocal is finite/nonzero. General reciprocals can change rounding and
;; overflow/underflow, so e.g. x/3 and x/1e-320 remain divisions.
(= (crExactReciprocal $den)
   (if (crNumber $den)
       (if (crIsValue $den 0) noReciprocal
           (let $value (crValue $den)
             (if (== (py-call (math.fabs (py-call (operator.getitem (py-call (math.frexp $value)) 0)))) 0.5)
                 (case (continCheckedNumber (catch (/ 1.0 $value)))
                   (((mkCEvalOk $reciprocal)
                     (if (continIsZero $reciprocal) noReciprocal (mkReciprocal $reciprocal)))
                    ($error noReciprocal))) noReciprocal))) noReciprocal))
(= (crDivision $children)
   (case $children
     ((($num $den)
       (if (crIsValue $num 0) (crLeaf 0.0)
           (case (crExactReciprocal $den)
             (((mkReciprocal $value) (crNary c_mul ($num (crLeaf $value))))
              ($other (mkTree (mkNode c_div) $children))))))
      ($arity (mkTree (mkNode c_div) $children)))))
