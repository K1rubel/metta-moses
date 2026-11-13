;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; KLD Feature Selector for Continuous Variables (MeTTa Port & Extension)
;;
;; Based on:
;; 1. OpenCog C++ KLD implementation:
;;    `opencog/util/KLD.h` (Author: Nil Geisweiller, based on Fernando Perez-Cruz:
;;    "Kullback-Leibler Divergence Estimation of Continuous Distributions")
;; 2. Implementation plan: `kld-implementation-plan.txt`
;;
;; Table representation: Column-major table (mkITable $table $labels)
;; where:
;;   $table  - list of columns (cons col0 (cons col1 ... (cons targetCol ())))
;;   $labels - list of column names (cons lbl0 (cons lbl1 ... (cons targetLbl ())))
;;   The last column in $table is the continuous target variable Y.
;;   Columns 0 .. (N - 2) are candidate continuous feature variables X.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Section 1: Fundamental Mathematical and List Helpers
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Natural logarithm with safety guard for non-positive values
;; Uses python math.log when available, with bounded floor fallback
(= (kld-ln $x)
    (if (<= $x 0.0)
        -100000.0
        (log-math 2.718281828 $x)))

(= (sort-numbers ()) ())
(= (sort-numbers (cons $x $xs))
    (List.insert $x (sort-numbers $xs)))

;; Find minimum and maximum of a non-empty cons list of numbers
;; Expects list of atleast one element
;; Doesnt recognize inf values
(= (cons-min-max $list)
    ((min-atom $list) (max-atom $list)))

(= (all-finite $xs) 
    (foldl-atom $xs True $acc $x 
      (and $acc 
          (and (!= $x (py-call (float nan))) 
            (and (!= $x (py-call (float inf))) (!= $x (py-call (float -inf))))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Section 2: Phase 1 & 2 Modular Density Estimation Functions
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Step 2.1: Frequency counter (count-values)
;; Converts a sorted list of numbers into a list of distinct (value count) pairs.
;; Produces sorted ascending entries: (cons ($val $count) ...)

(= (count-sorted-asc () $currVal $currCount)
    (cons ($currVal $currCount) ()))
(= (count-sorted-asc (cons $x $xs) $currVal $currCount)
    (if (== $x $currVal)
        ;; Same value encountered: increment count
        (count-sorted-asc $xs $currVal (+ $currCount 1.0))
        ;; Distinct value reached: emit previous pair and start count for next
        (cons ($currVal $currCount) (count-sorted-asc $xs $x 1.0))))

;; count-values: Sorts raw continuous list and aggregates into distinct pairs
(= (count-values ()) ())
(= (count-values (cons $x $xs))
    (let (cons $first $rest) (sort-numbers (cons $x $xs))
      (count-sorted-asc $rest $first 1.0)))

;; Step 2.2: P density estimates (p-density-estimates)
;; For each distinct input value p_x, divide its count by the gap from previous distinct value:
;;   delta_p = count / (p_x - p_x_prev)
;; For the very first point, the boundary is reproduced from C++:
;;   x_very_first = min(xs) - margin (default margin = 1.0)
;;   delta_p_0 = count_0 / (p_0 - (p_0 - margin)) = count_0 / margin.

(= (p-densities-helper () $prevX) ())
(= (p-densities-helper (cons ($px $c) $rest) $prevX)
    (let* (
        ($deltaPx (- $px $prevX))
        ;; Guard against zero width gap
        ($safeDelta (if (<= $deltaPx 0.0) 0.000001 $deltaPx))
        ($deltaP (/ $c $safeDelta))
    )
    (cons ($px $c $deltaP) (p-densities-helper $rest $px))))

(= (p-density-estimates $pPdf $margin)
    (if (== $pPdf ())
        ()
        (let (cons ($p0 $c0) $rest) $pPdf
            (let $xVeryFirst (- $p0 $margin)
                (p-densities-helper $pPdf $xVeryFirst)))))

;; Step 2.3: Q density bracket advancement (advance-q-bracket)
;; Exactly reproduces C++ `KLDS::next`:
;; Advances the iterator over sorted Q pairs while q_x < p_x.
;; Tracks q_x_pre (initialized to x_very_first = min(xs) - margin).
;; When cit_q reaches the end of Q, q_x is bounded by x_very_last = max(xs) + margin,
;; and n_duplicates defaults to 1.0.
;; Returns: ($currQx $currQxPre $nDup $remQ)
(= (advance-q-bracket $px () $qxPre $xVeryLast)
    ;; Q is exhausted: bracket against x_very_last with duplicate count 1.0
    ($xVeryLast $qxPre 1.0 ()))

(= (advance-q-bracket $px (cons ($qx $nq) $qRest) $qxPre $xVeryLast)
    (if (< $qx $px)
        ;; Target point is below current p_x: advance q_x_pre to this point and continue
        (advance-q-bracket $px $qRest $qx $xVeryLast)
        ;; Found bracket point with q_x >= p_x: return current target and remaining stream
        ($qx $qxPre $nq (cons ($qx $nq) $qRest))))

;; Step 2.4: Sum of log(delta_p / delta_q) terms across distinct P points
;; Evaluates: sum log(delta_p / delta_q)
;; where:
;;   delta_q = (p_s / q_s) * n_duplicates / (q_x - q_x_pre)
(= (legacy-sum-terms () $qList $qxPre $pS $qS $xVeryLast) 0.0)
(= (legacy-sum-terms (cons ($px $c $deltaP) $pRest) $qList $qxPre $pS $qS $xVeryLast)
    (let ($currQx $currQxPre $nDup $remQ) (advance-q-bracket $px $qList $qxPre $xVeryLast)
        (let* (
            ($deltaQx (- $currQx $currQxPre))
            ($safeDeltaQx (if (<= $deltaQx 0.0) 0.000001 $deltaQx))
            ($deltaQ (/ (* (/ $pS $qS) $nDup) $safeDeltaQx))
            ($ratio (if (<= $deltaQ 0.0) 1.0 (/ $deltaP $deltaQ)))
            ($term (kld-ln $ratio))
            ($restSum (legacy-sum-terms $pRest $remQ $currQxPre $pS $qS $xVeryLast))
        )
        (+ $term $restSum))))

;; Weighted sum: weights each log contribution by count c(p_x)
;; Implements improvement option: E_P[log(P/Q)]
(= (weighted-sum-terms () $qList $qxPre $pS $qS $xVeryLast) 0.0)
(= (weighted-sum-terms (cons ($px $c $deltaP) $pRest) $qList $qxPre $pS $qS $xVeryLast)
    (let ($currQx $currQxPre $nDup $remQ) (advance-q-bracket $px $qList $qxPre $xVeryLast)
        (let* (
            ($deltaQx (- $currQx $currQxPre))
            ($safeDeltaQx (if (<= $deltaQx 0.0) 0.000001 $deltaQx))
            ($deltaQ (/ (* (/ $pS $qS) $nDup) $safeDeltaQx))
            ($ratio (if (<= $deltaQ 0.0) 1.0 (/ $deltaP $deltaQ)))
            ($term (* $c (kld-ln $ratio)))
            ($restSum (weighted-sum-terms $pRest $remQ $currQxPre $pS $qS $xVeryLast))
        )
        (+ $term $restSum))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Section 3: Input Validation and Score Computation Pipelines
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Validate input columns before scoring
;; Returns: True for valid pairs and False otherwise
(= (validate-column-pair $xs $ys)
  (and (and (!= $xs ()) (!= $ys ()))
    (and (== (List.length $xs) (List.length $ys)) 
      (and (all-finite $xs) (all-finite $ys)))))

;; Legacy KLD calculation directly porting C++ KLDS::operator():
;;   KLD = (sum / p_s) - 1.0
;;   Score = - KLD
(= (raw-legacy-kld $xs $ys $margin)
    (let* (
        ($pPdf (count-values $xs))
        ($qPdf (count-values $ys))
        ($pS (List.length $xs))
        ($qS (List.length $ys))
        (($minX $maxX) (cons-min-max $xs))
        ($xVeryFirst (- $minX $margin))
        ($xVeryLast (+ $maxX $margin))
        ($pEst (p-density-estimates $pPdf $margin))
        ($sum (legacy-sum-terms $pEst $qPdf $xVeryFirst $pS $qS $xVeryLast))
    )
    (- (/ $sum $pS) 1.0)))

;; Legacy KLD feature score: returns negative of KLD
;; XXX -- column validty checks appears redundant
(= (legacy-kld-score $xs $ys)
    (if (validate-column-pair $xs $ys)
        (- 0.0 (raw-legacy-kld $xs $ys 1.0))
        -999999.0))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Section 4: Improvement Options
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Improvement Option 1: Scale-Adaptive Boundary Margin
;; Derives margin from data spread: margin = (max(xs) - min(xs)) / distinct_count
;; Eliminates sensitivity to unit changes (e.g. meters vs millimeters)
(= (compute-adaptive-margin $xs $pPdf)
    (let ($minX $maxX) (cons-min-max $xs)
        (let $range (- $maxX $minX)
            (let $numDistinct (size-atom $pPdf)
                (if (<= $range 0.0)
                    1.0
                    (/ $range (max 1.0 $numDistinct)))))))

(= (adaptive-kld-score $xs $ys)
    (if (validate-column-pair $xs $ys)
        (let* (
            ($pPdf (count-values $xs))
            ($qPdf (count-values $ys))
            ($pS (size-atom $xs))
            ($qS (size-atom $ys))
            (($minX $maxX) (cons-min-max $xs))
            ($margin (compute-adaptive-margin $xs $pPdf))
            ($xVeryFirst (- $minX $margin))
            ($xVeryLast (+ $maxX $margin))
            ($pEst (p-density-estimates $pPdf $margin))
            ($sum (legacy-sum-terms $pEst $qPdf $xVeryFirst $pS $qS $xVeryLast))
            ($kld (- (/ $sum $pS) 1.0))
        )
        (- 0.0 $kld))
        -999999.0))

;; Improvement Option 2: Count-Weighted Contributions
;; Weights log-ratio by each distinct input point's count c(p_x)
(= (weighted-kld-score $xs $ys)
    (if (validate-column-pair $xs $ys)
        (let* (
            ($pPdf (count-values $xs))
            ($qPdf (count-values $ys))
            ($pS (size-atom $xs))
            ($qS (size-atom $ys))
            (($minX $maxX) (cons-min-max $xs))
            ($margin 1.0)
            ($xVeryFirst (- $minX $margin))
            ($xVeryLast (+ $maxX $margin))
            ($pEst (p-density-estimates $pPdf $margin))
            ($sum (weighted-sum-terms $pEst $qPdf $xVeryFirst $pS $qS $xVeryLast))
            ($kld (- (/ $sum $pS) 1.0))
        )
        (- 0.0 $kld))
        -999999.0))

;; Improvement Option 3: Proper KL Divergence Estimator
;; Removes the unexplained -1.0 offset and weights by sample frequency:
;; KL(P || Q) = (1 / |xs|) * sum_{distinct} c(p_x) * log(delta_p / delta_q)
;; Under this estimator, identical distributions yield KL ~ 0.0.
;; Score is defined as 1 / (1 + max(0, KL)) so scores are bounded in (0, 1].
(= (proper-kld-score $xs $ys)
    (if (validate-column-pair $xs $ys)
        (let* (
            ($pPdf (count-values $xs))
            ($qPdf (count-values $ys))
            ($pS (size-atom $xs))
            ($qS (size-atom $ys))
            (($minX $maxX) (cons-min-max $xs))
            ($margin (compute-adaptive-margin $xs $pPdf))
            ($xVeryFirst (- $minX $margin))
            ($xVeryLast (+ $maxX $margin))
            ($pEst (p-density-estimates $pPdf $margin))
            ($sum (weighted-sum-terms $pEst $qPdf $xVeryFirst $pS $qS $xVeryLast))
            ($properKld (/ $sum $pS))
            ($nonNegKld (max 0.0 $properKld))
        )
        (/ 1.0 (+ 1.0 $nonNegKld)))
        0.0))

;; Improvement Option 4: Paired Continuous Mutual Information via Binning
;; Preserves paired row relationships (x_i, y_i) to detect true dependency
;; and distinguish genuine correlation from shuffled targets.

;; Bin continuous scalar into bin index 0 .. (numBins - 1)
(= (continuous-to-bin $val $minVal $maxVal $numBins)
    (let $range (- $maxVal $minVal)
        (if (<= $range 0.0)
            0
            (let $norm (/ (- $val $minVal) $range)
                (let $rawBin (py-call (builtins.int (* $norm $numBins)))
                    (if (>= $rawBin $numBins)
                        (- $numBins 1)
                        (if (< $rawBin 0) 0 $rawBin)))))))

;; Map paired row values (xs, ys) into joint bin pairs: (cons (bx by) ...)
(= (map-to-bin-pairs () () $minX $maxX $minY $maxY $numBins) ())
(= (map-to-bin-pairs (cons $x $xs) (cons $y $ys) $minX $maxX $minY $maxY $numBins)
    (let* (
        ($bx (continuous-to-bin $x $minX $maxX $numBins))
        ($by (continuous-to-bin $y $minY $maxY $numBins))
    )
    (cons ($bx $by) (map-to-bin-pairs $xs $ys $minX $maxX $minY $maxY $numBins))))

;; Count occurrences in a list of items using associative accumulator
(= (count-occurrences () $acc) $acc)
(= (count-occurrences (cons $x $xs) $acc)
    (if (patternExists ($x $c) $acc)
        (chain (updateCount $x $acc) $updated
            (count-occurrences $xs $updated))
        (chain (union-atom $acc (($x 1.0))) $added
            (count-occurrences $xs $added))))

;; Helper to extract marginal counts from joint bin counts
(= (extract-x-counts () $acc) $acc)
(= (extract-x-counts (cons (($bx $by) $c) $rest) $acc)
    (if (patternExists ($bx $curCount) $acc)
        (chain (collapse (chain (superpose $acc) $entry
                    (if (= $entry ($bx $curCount)) ($bx (+ $curCount $c)) $entry))) $updated
            (extract-x-counts $rest $updated))
        (chain (union-atom $acc (($bx $c))) $added
            (extract-x-counts $rest $added))))

(= (extract-y-counts () $acc) $acc)
(= (extract-y-counts (cons (($bx $by) $c) $rest) $acc)
    (if (patternExists ($by $curCount) $acc)
        (chain (collapse (chain (superpose $acc) $entry
                    (if (= $entry ($by $curCount)) ($by (+ $curCount $c)) $entry))) $updated
            (extract-y-counts $rest $updated))
        (chain (union-atom $acc (($by $c))) $added
            (extract-y-counts $rest $added))))

;; Find count for a key in a tuple of (Key Count) pairs
(= (lookup-count $targetKey ()) 0.0)
(= (lookup-count $targetKey (cons ($k $c) $rest))
    (if (== $targetKey $k) $c (lookup-count $targetKey $rest)))

;; Compute I(X; Y) = sum_{x,y} p(x, y) * log(p(x,y) / (p(x) * p(y)))
(= (compute-mi-sum () $xCounts $yCounts $nTotal) 0.0)
(= (compute-mi-sum (cons (($bx $by) $jointC) $rest) $xCounts $yCounts $nTotal)
    (let* (
        ($cx (lookup-count $bx $xCounts))
        ($cy (lookup-count $by $yCounts))
        ($pxy (/ $jointC $nTotal))
        ($px (/ $cx $nTotal))
        ($py (/ $cy $nTotal))
        ($denom (* $px $py))
        ($ratio (if (<= $denom 0.0) 1.0 (/ $pxy $denom)))
        ($term (* $pxy (kld-ln $ratio)))
        ($restSum (compute-mi-sum $rest $xCounts $yCounts $nTotal))
    )
    (+ $term $restSum)))

;; Binned mutual information feature score for continuous paired columns
(= (binned-mi-score $xs $ys $numBins)
    (if (validate-column-pair $xs $ys)
        (let* (
            (($minX $maxX) (cons-min-max $xs))
            (($minY $maxY) (cons-min-max $ys))
            ($nTotal (size-atom $xs))
            ($binPairs (map-to-bin-pairs $xs $ys $minX $maxX $minY $maxY $numBins))
            ($jointCounts (count-occurrences $binPairs ()))
            ($jointList (collapse (superpose $jointCounts)))
            ($xCounts (extract-x-counts (List.listToExpr $jointList) ()))
            ($yCounts (extract-y-counts (List.listToExpr $jointList) ()))
        )
        (compute-mi-sum (List.listToExpr $jointList) (List.listToExpr $xCounts) (List.listToExpr $yCounts) $nTotal))
        0.0))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Section 5: Column-Major Table Integration and Feature Selection
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Dispatches scoring method based on algorithm mode symbol:
;;   adaptive -> Adaptive margin KLD score
;;   weighted -> Count-weighted KLD score
;;   proper   -> Proper continuous KL score
;;   mi       -> Continuous binned Mutual Information score
;;   if none of the above are specified use the Legacy scorer
(= (dispatch-feature-score $mode $xs $ys)
    (case $mode (
        (adaptive (adaptive-kld-score $xs $ys))
        (weighted (weighted-kld-score $xs $ys))
        (proper (proper-kld-score $xs $ys))
        (mi (binned-mi-score $xs $ys 5))
        ($_ (legacy-kld-score $xs $ys))
    )))

;; Score all candidate features in a column-major table
;; Emits diagnostic list: (cons (Label ColIdx Score) ...)
;; Invalid column pairs carry the reserved score -999999.0.
;; $colIdx: current candidate index (0 .. N-2)
(= (score-all-features-helper () () $targetCol $mode $colIdx) ())
(= (score-all-features-helper (cons $col $colsRest) (cons $lbl $lblsRest) $targetCol $mode $colIdx)
    (let* (
        ($score (if (validate-column-pair $col $targetCol)
                    (dispatch-feature-score $mode $col $targetCol)
                    -999999.0))
        ($rest (score-all-features-helper $colsRest $lblsRest $targetCol $mode (+ $colIdx 1)))
    )
    (cons ($lbl $colIdx $score) $rest)))


(= (kldScoreAllFeatures (mkITable $table $labels) $mode)
    (let* (
        ($numCols (size-atom $labels))
        ($targetIdx (- $numCols 1))
        ($targetCol (Table.getColumn $targetIdx $table))
        ;; Candidate columns are all columns except the last
        ($candidateCols (List.takeN $targetIdx $table))
        ($candidateLabels (List.takeN $targetIdx $labels))
    )
    (score-all-features-helper $candidateCols $candidateLabels $targetCol $mode 0)))

;; Insert scored feature entry in descending order of score
(= (insert-descending $entry ()) (cons $entry ()))
(= (insert-descending ($lbl $idx $score) (cons ($hLbl $hIdx $hScore) $t))
    (if (>= $score $hScore)
        (cons ($lbl $idx $score) (cons ($hLbl $hIdx $hScore) $t))
        (cons ($hLbl $hIdx $hScore) (insert-descending ($lbl $idx $score) $t))))

(= (sort-scored-descending ()) ())
(= (sort-scored-descending (cons $x $xs))
    (insert-descending $x (sort-scored-descending $xs)))

;; Take top N items from a cons list
(= (cons-take 0 $list) ())
(= (cons-take $n ()) ())
(= (cons-take $n (cons $x $xs))
    (cons $x (cons-take (- $n 1) $xs)))

;; kldSelectTopFeatures: Full selection returning top-k feature indices
(= (kldSelectTopFeatures (mkITable $table $labels) $th $numDesired $mode)
    (let* (
        ($scored (kldScoreAllFeatures (mkITable $table $labels) $mode))
        ($filtered (filter-atom $scored ($lbl $idx $score) (and (!= $score -999999.0) (>= $score $th))))
        ($sorted (sort-scored-descending $filtered))
        ($top (List.takeN $numDesired $sorted))
    )
    (map-atom $top ($lbl $idx $score) $idx)))

;; kldFeatureSelector: Drop-in compatibility interface matching simpleFeatureSelector
;; Parameters:
;;   $th          - Score threshold
;;   $numDesired  - Desired number of features (0 means return all candidate indices)
;;   $mode        - Scoring mode ('legacy', 'adaptive', 'weighted', 'proper', 'mi')
;;   (mkITable)   - Column-major table
;;   $acc         - Accumulator (kept for signature parity)

(= (kldFeatureSelector $th $numDesired $mode (mkITable $table $labels) $acc)
    (let $numCols (size-atom $labels)
        (if (== $numDesired 0)
            ;; Default fallback: return all candidate feature indices
            ((0 (List.range 0 (- $numCols 1))))
            (let $selected (kldSelectTopFeatures (mkITable $table $labels) $th $numDesired $mode)
                ((0 $selected))))))

