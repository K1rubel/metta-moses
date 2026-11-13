;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Unit & Compatibility Tests for KLD Feature Selector
;; Validates Phase 1, Phase 2, and Improvement Options from kld-implementation-plan.txt
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

!(import! &self utilities/list-methods)
!(import! &self utilities/general-helpers)
!(import! &self feature-selection/feature-selection-helpers)
!(import! &self feature-selection/kld-feature-selection)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Test 1: Frequency Counter (count-values) with repeated continuous values
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

!(assertEqual
    (count-values (cons 2.0 (cons 1.0 (cons 2.0 (cons 3.0 (cons 1.0 ()))))))
    (cons (1.0 2.0) (cons (2.0 2.0) (cons (3.0 1.0) ()))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Test 2: Phase 1 Compatibility - Identical xs and ys produce KLD = -1.0
;; (Under legacy Perez-Cruz / C++ KLDS implementation, identical sequences produce
;;  res = 0, so res / p_s - 1.0 = -1.0. Feature score is - KLD = 1.0)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

!(assertEqual
    (raw-legacy-kld (cons 1.0 (cons 2.0 (cons 3.0 ()))) (cons 1.0 (cons 2.0 (cons 3.0 ()))) 1.0)
    -1.0)

!(assertEqual
    (legacy-kld-score (cons 1.0 (cons 2.0 (cons 3.0 ()))) (cons 1.0 (cons 2.0 (cons 3.0 ()))))
    1.0)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Test 3: Phase 1 Compatibility - Permuting ys leaves marginal score unchanged
;; (Documents the limitation of marginal KLD: target ordering is ignored)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

!(assertEqual
    (legacy-kld-score (cons 1.0 (cons 2.0 (cons 3.0 ()))) (cons 1.0 (cons 2.0 (cons 3.0 ()))))
    (legacy-kld-score (cons 1.0 (cons 2.0 (cons 3.0 ()))) (cons 3.0 (cons 1.0 (cons 2.0 ())))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Test 4: Phase 2 Dependability - Input Validation Checks
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Empty list
!(assertEqual
    (validate-column-pair () (cons 1.0 ()))
    False)

;; Unequal lengths
!(assertEqual
    (validate-column-pair (cons 1.0 (cons 2.0 ())) (cons 1.0 ()))
    False)

;; Valid inputs pass
!(assertEqual
    (validate-column-pair (cons 1.0 (cons 2.0 ())) (cons 3.0 (cons 4.0 ())))
    True)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Test 5: Column-Major Table Integration and Diagnostic Output
;; Defines a continuous column-major table:
;;   Col 0 (F0): Identical to target (perfect score)
;;   Col 1 (F1): Displaced/shifted continuous feature
;;   Col 2 (Target): Continuous output variable
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(= (test-contin-table)
    (mkITable
        (cons (cons 1.0 (cons 2.0 (cons 3.0 ())))
        (cons (cons 10.0 (cons 20.0 (cons 30.0 ())))
        (cons (cons 1.0 (cons 2.0 (cons 3.0 ()))) ())))
        (cons F0 (cons F1 (cons Target ())))))

;; Scoring all features produces diagnostic tuples: (Label ColIdx Score)
!(assertEqual
    (kldScoreAllFeatures (test-contin-table) legacy)
    (cons (F0 0 1.0) (cons (F1 1 (legacy-kld-score (cons 10.0 (cons 20.0 (cons 30.0 ()))) (cons 1.0 (cons 2.0 (cons 3.0 ()))))) ())))

;; Invalid columns retain the reserved score but are never selected,
;; even when the threshold is below that score.
!(assertEqual
    (score-all-features-helper (cons () ()) (cons Invalid ()) (cons 1.0 ()) legacy 0)
    (cons (Invalid 0 -999999.0) ()))

;; Selecting top 1 feature from column-major table picks F0 (index 0)
!(assertEqual
    (kldSelectTopFeatures (test-contin-table) 0.0 1 legacy)
    (cons 0 ()))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Test 6: Improvement Option 4 - Continuous Paired Binned Mutual Information
;; Perfectly correlated continuous feature scores significantly higher than
;; independent / opposite continuous variable.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

!(assertEqual
    (> (binned-mi-score (cons 1.0 (cons 2.0 (cons 3.0 (cons 4.0 ())))) (cons 2.0 (cons 4.0 (cons 6.0 (cons 8.0 ())))) 4) 0.5)
    True)

