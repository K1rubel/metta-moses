;; Independent test-only C++ stepper simulation, extracted unchanged from
;; continuous-reference-fixtures-test.metta for exhaustive production checks.
(= (decodeTritList $val $step $allLeft $allRight $exp ())
   ;; No more trits: return accumulated value.
   $val)

(= (decodeTritList $val $step $allLeft $allRight $exp (cons $head $tail))
   (if (== $head 0)
       ;; STOP: halt immediately; remaining trits are dead tail.
       $val
       (if (== $head 1)
           ;; LEFT move
           (if $allLeft
               ;; Purely-left streak: subtract step, expand for next time.
               (decodeTritList (- $val $step) (* $step $exp) True False $exp $tail)
               ;; Reversal or refinement continuation:
               ;;   On the very first reversal from a purely-right streak,
               ;;   divide step by (expansion * 2) before applying.
               ;;   Thereafter (both $allLeft and $allRight are False), just use step.
               (let $s (if $allRight (/ $step (* $exp 2)) $step)
                 (decodeTritList (- $val $s) (/ $s 2) False False $exp $tail)))
           ;; RIGHT move; malformed trits must not silently become RIGHT.
           (if (== $head 2)
             (if $allRight
               ;; Purely-right streak: add step, expand for next time.
               (decodeTritList (+ $val $step) (* $step $exp) False True $exp $tail)
               ;; Reversal or refinement continuation:
               (let $s (if $allLeft (/ $step (* $exp 2)) $step)
                 (decodeTritList (+ $val $s) (/ $s 2) False False $exp $tail)))
             (mkCEvalError "InvalidTrit")))))
