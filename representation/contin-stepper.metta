;; Step 5. Load scoring/contin-eval and representation/contin-spec first.
;; Adapted from tests/continuous-reference-fixtures-test.metta:decodeTritList,
;; independently retained there as the C++ field_set.h reference simulation.
;;   $x: Candidate number; must be finite and equal to its integer floor.
;;   Returns: True for finite integral values, False otherwise.
(= (continInteger $x)
   (if (continFiniteNumber $x) (== $x (floor-math $x)) False))
;; !(py-call (builtins.isinstance 5 "int"))
;;   $x: candidate number; returns True only for a finite nonnegative integer.
(= (continNatural $x) (if (continInteger $x) (>= $x 0) False))
;;   $spec: mkContinSpec; returns whether mean/step/expansion are finite,
;;   step and expansion positive, and depth a positive integer.
(= (continSpecValid $spec)
   (case $spec
     (((mkContinSpec $mean $step $exp $depth)
       (if (and (continFiniteNumber $mean) (and (continFiniteNumber $step) (continFiniteNumber $exp)))
           (and (and (> $step 0) (> $exp 0)) (if (continInteger $depth) (> $depth 0) False)) False))
      ($bad False))))
;;   $trits: Raw trit list for one knob.
;;   Returns: True only when the list is proper and every value is 0, 1, or 2.
(= (continTritsValid $trits)
   (case $trits
     ((() True)
      ((cons $head $tail) (if (once (is-member $head (0 1 2))) (continTritsValid $tail) False))
      ($bad False))))

;; Python binary64 arithmetic lets an unused next-step overflow remain unused,
;; as in C++. E.g. the final move can be finite even if its NEXT step is Inf.
;; Only the decoded value escapes, checked at the public boundary. No global RNG.
;;   $val: Current decoded value.
;;   $step: Current signed-move magnitude.
;;   $allLeft/$allRight: Whether all prior non-STOP moves took that direction.
;;   $exp: Same-direction step expansion multiplier.
;;   $trits: Remaining validated trit choices.
;;   Returns: Decoded numeric value after consuming choices up to STOP or end.
(= (decodeContinTritList $val $step $allLeft $allRight $exp $trits)
   (case $trits
     ((() $val)
      ((cons $head $tail)
       (if (== $head 0) $val
         (if (== $head 1)
           (if $allLeft
               (decodeContinTritList (py-call (operator.sub $val $step))
                 (py-call (operator.mul $step $exp)) True False $exp $tail)
               (let $s (if $allRight (py-call (operator.truediv $step (py-call (operator.mul $exp 2.0)))) $step)
                 (decodeContinTritList (py-call (operator.sub $val $s))
                   (py-call (operator.truediv $s 2.0)) False False $exp $tail)))
           (if $allRight
               (decodeContinTritList (py-call (operator.add $val $step))
                 (py-call (operator.mul $step $exp)) False True $exp $tail)
               (let $r (if $allLeft (py-call (operator.truediv $step (py-call (operator.mul $exp 2.0)))) $step)
                 (decodeContinTritList (py-call (operator.add $val $r))
                   (py-call (operator.truediv $r 2.0)) False False $exp $tail)))))))))

;; Validate EVERY coordinate, including dead tails. Reject short/long slices,
;; non-integer trits and malformed specs rather than silently truncating them.
;;   $spec: Knob's finite, valid geometric decoding parameters.
;;   $trits: Full raw slice, exactly the configured depth.
;;   Returns: mkCEvalError on invalid input or a checked decoded number.
(= (decodeContinSlice $spec $trits)
   (if (continSpecValid $spec)
       (if (== (continListLength $trits) (continSpecDepth $spec))
           (if (continTritsValid $trits)
               (continCheckedNumber (catch
                 (decodeContinTritList (py-call (builtins.float (continSpecMean $spec)))
                   (py-call (builtins.float (continSpecStep $spec))) True True
                   (py-call (builtins.float (continSpecExpansion $spec))) $trits)))
               (mkCEvalError "InvalidTrit"))
           (mkCEvalError "InvalidSliceLength"))
       (mkCEvalError "InvalidContinSpec")))

;; Internal list helpers consume validated lengths/lists only.
;;   $xs: Input list.  $n: Number of leading values to retain.
;;   Returns: First n elements; caller must provide a valid range.
(= (continTake $xs $n)
   (if (== $n 0) () (let (cons $head $tail) $xs (cons $head (continTake $tail (- $n 1))))))
;;   $xs: input list; $n: number of leading items to skip. Returns remaining suffix.
(= (continDrop $xs $n)
   (if (== $n 0) $xs (let (cons $head $tail) $xs (continDrop $tail (- $n 1)))))
;;   $xs: first list (empty or cons); $ys: suffix list.
;;   Returns concatenation in original order.
(= (continAppend () $ys) $ys)
(= (continAppend (cons $head $tail) $ys) (cons $head (continAppend $tail $ys)))
;;   $x: value to repeat; $n: nonnegative count. Returns an n-element list.
(= (continRepeat $x $n) (if (== $n 0) () (cons $x (continRepeat $x (- $n 1)))))
;;   $xs: input list; $i: zero-based position. Returns item i (valid index required).
(= (continAt $xs $i) (car-atom (continDrop $xs $i)))

;;   $trits: raw knob slice; $active: whether earlier trits have avoided STOP.
;;   Returns same-length slice with every post-STOP coordinate canonicalized to 0.
(= (canonicalContinTail $trits $active)
   (case $trits
     ((() ())
      ((cons $head $tail)
       (cons (if $active $head 0) (canonicalContinTail $tail (and $active (not (== $head 0)))))))))
;;   $spec: validated knob parameters; $trits: exact-depth trit vector.
;;   Returns its canonical form or a structured spec/length/trit error.
(= (canonicalContinSlice $spec $trits)
   (if (continSpecValid $spec)
       (if (== (continListLength $trits) (continSpecDepth $spec))
           (if (continTritsValid $trits) (canonicalContinTail $trits True) (mkCEvalError "InvalidTrit"))
           (mkCEvalError "InvalidSliceLength"))
       (mkCEvalError "InvalidContinSpec")))
