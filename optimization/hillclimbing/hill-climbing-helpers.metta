;; A negative value means that a direct hill-climbing caller has not supplied
;; a share of the complete-run evaluation allowance. Counted deme expansion
;; temporarily replaces it with the budget allocated to that deme.
!(bind! &localEvalLimit (new-state -1))

;; Verbatim port of the Information theoretic bits function from C++.
;; Params: $knobMap: A map of knobs with their multiplicities
;; Returns: Sum of log2(multiplicity) for the knobs in the map.
; (: informationTheoreticBits (-> (MultiMap (DiscSpec $knob)) Number))
;; C++ measures the information carried by a discrete field, rather than the
;; number of values in that field.  A seven-way ant action knob therefore adds
;; log2(7) bits, not seven bits.
(= (knobInformationBits $knob)
   (let (mkMultip $multiplicity) (getKnobMultip $knob)
     (log-math 2 $multiplicity)))

;; A native fold remains compositional when the estimator consumes the result
;; as a nested expression under PeTTa.
(= (informationTheoreticBits $knobMap)
   (floor-math (foldl-atom (MultiMap.values $knobMap) 0 $bits $knob
     (+ $bits (knobInformationBits $knob)))))

;; feature selection version of the informationTheoreticBits function
;; In the case of feature selection, the information theoretic bits is simply the number of features we have
; (: informationTheoreticBitsFs (-> (List Symbol) Number))
(= (informationTheoreticBitsFs $labels)
   (- (List.length $labels) 1))

;; Verbatim port of the Estimate neighborhood function from c++
;; Params: $distance: The hamming distance from the current knob
;;         $knobMap: A map of knobs with their multiplicities
;; Returns: twice the truncated information-bit estimate at distance one, or
;;          its binomial coefficient at greater distances.
; (: estimateNeighborhood (-> Number (MultiMap (DiscSpec $knob)) Number))
(= (estimateNeighborhood $distance $knobMap)
   (if (== $distance 0)
       1
       ;; C++ stores the floating-point information sum in size_t before using
       ;; it as a neighborhood dimension. `floor-math` is the exact
       ;; nonnegative truncation and remains grounded inside this `let`.
       (let $nnEstimate (floor-math (informationTheoreticBits $knobMap))
         ;; Match hill_climbing::estimate_neighborhood: an approximate field
         ;; dimension smaller than the requested Hamming distance still has
         ;; one maximally distant combination; it is not an empty neighborhood.
         (let $clampedDistance (min $distance $nnEstimate)
          (if (== $clampedDistance 1)
              (* 2 $nnEstimate)
              (binomial $nnEstimate $clampedDistance)))))) ;; INFO: Could use a safe binomial coefficient here if the estiamte starts becoming very large.

;; similar to the above 'estimateNeighborhood' but this one uses the informationTheoreticBitsFs which is for feature selection
; (: estimateNeighborhoodFs (-> Number (List Symbol) Number))
(= (estimateNeighborhoodFs $distance $labels)
   (if (== $distance 0)
       1
       (let $nnEstimate (informationTheoreticBitsFs $labels)
        (if (== $distance 1)
             (* 2 $nnEstimate)
             (binomial $nnEstimate $distance))))) ;; INFO: Could use a safe binomial coefficient here if the estiamte starts becoming very large.

;; Return an estimate of the number of new instances to search
(= (nNewInstances $distance $maxEvals $currentEvals $totalNeighbors)
   (if (== $distance 0)
       1
       (let*
           (
             ;; TODO: Most of the clamping logic here depens on the usage of number of evals and max number of evals. So best to do it after those are integrated into the system. For now we will be returning the total neighborhood clamped to the max_evals only.
             ;; ($_ (println! (Inside newInstances: $distance $maxEvals $currentEvals $totalNeighbors)))
             ($hc_params_fraction_of_nn (param hcFractionOfNN))
             ($numberOfNewInstaces (int (* $totalNeighbors (pow-math $hc_params_fraction_of_nn $distance))))
             ($nLeft (- $maxEvals $currentEvals))
             ($minDemeSize (param hcMinDemeSize))
           )
           (if (< $numberOfNewInstaces $minDemeSize)
               (min $nLeft $minDemeSize)
               (if (< $nLeft $numberOfNewInstaces)
                   $nLeft
                   $numberOfNewInstaces)))))

;; Counts the number of instances at a specific distance from a given instance.
;; Params:
;;   $kbMap: Contains DiscKnobMap and DiscMap
;;   $inst: Reference instance
;;   $dist: Distance to measure
;;   $startIdx: Starting index
;;   $maxCount: Maximum count to return (e.g., 20).
;; Returns:
;;   Count of instances at distance $dist from $inst

;; Count combinations at one exact distance from the current instance.
;; The distance-zero result represents the unchanged instance and the index
;; guard prevents recursive calls from reading beyond the final knob.
;; (: countNeighborhoodFromIdx (-> KnobMap Instance Number Number Number Number))
(= (countNeighborhoodFromIdx (mkKbMap (mkDscMp $dscMp)) $inst $dist $startIdx $maxCount)
   (if (== $dist 0)
       1
       (if (>= $startIdx (MultiMap.length $dscMp))
           0
           (let*
             (
               (($kbSpec $knob) (MultiMap.getByIdx $startIdx $dscMp))
               ((mkMultip $multip) (getKnobMultip $knob))
               ;; A Boolean-only suffix has a direct binomial count, avoiding
               ;; the per-knob recursion used for mixed-multiplicity maps.
               ($isBoolTail
                 (and (== $multip 2)
                      (allBooleanKnobs
                        (mkKbMap (mkDscMp $dscMp)) (+ $startIdx 1))))
             )
             (if $isBoolTail
                 (let* (($n (- (MultiMap.length $dscMp) $startIdx)))
                   ;; Distances beyond the remaining Boolean dimensions are
                   ;; impossible; otherwise cap the count for callers that
                   ;; only need a bounded neighborhood estimate.
                   (if (> $dist $n)
                       0
                       (let $count (binomial $n $dist)
                         (if (> $count $maxCount) $maxCount $count))))
                 ;; For mixed knobs, skip or change the current knob and add
                 ;; the resulting counts from the remaining dimensions.
                 (let $updatedNumInstances
                            (countNeighborhoodFromIdx
                              (mkKbMap (mkDscMp $dscMp)) $inst $dist
                              (+ $startIdx 1) $maxCount)
                   (if (> $updatedNumInstances $maxCount)
                       $updatedNumInstances
                       (+ $updatedNumInstances
                          (* (- $multip 1)
                             (countNeighborhoodFromIdx
                               (mkKbMap (mkDscMp $dscMp)) $inst
                               (- $dist 1) (+ $startIdx 1) $maxCount))))))))))

;; Helper: check if all knobs from $startIdx onward have multiplicity 2 (boolean).
(= (allBooleanKnobs (mkKbMap (mkDscMp ())) $startIdx) True)
(= (allBooleanKnobs (mkKbMap (mkDscMp (cons ($spec $knob) $tail))) $startIdx)
   (let (mkMultip $multip) (getKnobMultip $knob)
     (if (== $multip 2)
         (allBooleanKnobs (mkKbMap (mkDscMp $tail)) (+ $startIdx 1))
         False)))

; countNeighborhood
;; (: countNeighborhood (-> KnobMap Instance Number Number Number))
(= (countNeighborhood $kbMap $inst $dist $maxCount)
(countNeighborhoodFromIdx $kbMap $inst $dist 0 $maxCount))

;; factorial
; (: factorial (-> Number Number))
(= (factorial $n)
   (if (<= $n 1) 1 (* $n (factorial (- $n 1)))))

;; binomial coefficient
; (: binomial (-> Number Number Number))
(= (binomial $n $k)
   (if (or (< $k 0) (> $k $n))
       0
       (/ (factorial $n) (* (factorial $k) (factorial (- $n $k))))))

;; Feature selection version of countNeighborhoodFromIdx
;; uses the BInomial coefficient to count the number of instances at a specific distance from a given instance.
; (: countNeighborhoodFromIdxFs (-> Instance Number Number Number Number))
(= (countNeighborhoodFromIdxFs (mkInst $instance) $dist $startIdx $maxCount)
(if (== $dist 0) 1 
(let*
  (
    ($n (- (List.length $instance) $startIdx))
    ($count (binomial $n $dist))
  )
  (if (> $dist $n) 0 (if (> $count $maxCount) $maxCount $count))
))
)

;; Feature selection version of countNeighborhood
;; uses the countNeighborhoodFromIdxFs
; (: countNeighborhoodFs (-> Instance Number Number Number))
(= (countNeighborhoodFs $instance $dist $maxCount)
   (countNeighborhoodFromIdxFs $instance $dist 0 $maxCount))
  
;; mergeOffspring
;; Combines offspring produced by the three crossover operators, removes
;; duplicates, appends new instances after the original deme, and returns the
;; updated deme together with the number of newly added instances.
(= (mergeOffspring $origDeme $newInstances1 $newInstances2 $newInstances3)

   (let*
      (
       ((mkDeme $rep (mkSInstSet $origSet) $demeId) $origDeme)

       ;; List.appendList(a, b) is implemented as append(b, a). Reverse the
       ;; helper arguments so first-occurrence deduplication sees
       ;; the same one-, two-, then three-simplex order as the C++ driver.
       ($temp (List.appendList $newInstances2 $newInstances1))
       ($allNewInstances (List.appendList $newInstances3 $temp))

       ($uniqueNewInstances (unique-atom $allNewInstances))
       ;; Crossover can rediscover a vector that is already in the scored
       ;; prefix.  Comparing the complete mkSInst row misses that duplicate
       ;; because the rediscovered row carries worstCscore while the existing
       ;; row carries its real score.  Filter by the instance payload so an
       ;; already evaluated vector is neither appended nor charged again.
       ($origInstances
         (map-atom $origSet $row
           (let (mkSInst (mkPair $inst $_score)) $row $inst)))
       ($freshNewInstances
         (filter-atom $uniqueNewInstances $row
           (let (mkSInst (mkPair $inst $_score)) $row
             (not (once (is-member $inst $origInstances))))))

       ($finalSet (List.appendList $freshNewInstances $origSet))

       ($nNewAdded (List.length $freshNewInstances))
      )
     ((mkDeme $rep (mkSInstSet $finalSet) $demeId) $nNewAdded)
))

;; crossover
;; Main crossover driver.
;; Distributes the crossover budget across 1-, 2-, and 3-simplex operators,
;; collects their offspring, merges the results, removes duplicates,
;; and returns the updated deme and count of newly added instances.
;; (: crossover (-> Number Number Instance Deme (Deme Number)))
(= (crossover $demeSize $nNewInstances $sampleStart $sampleSize $centerInst $deme)

   ;; Keep the crossover population configurable; 120 is the C++ default.
    (let*
      (
       ($nToMake (min $nNewInstances (param hcCrossoverPopSize)))
       ($third (if (get-state &hcActive) (floor-math (/ $nToMake 3)) (/ $nToMake 3)))
   
       ($newInstances1 (crossTopOne $deme (+ $third (% $nToMake 3)) $sampleStart $sampleSize $centerInst))
       ($newInstances2 (crossTopTwo $deme $third $sampleStart $sampleSize $centerInst))
       ($newInstances3 (crossTopThree $deme $third $sampleStart $sampleSize $centerInst))
       ($_proposals (hcRecordProposals (+ (List.length $newInstances1)
                          (+ (List.length $newInstances2) (List.length $newInstances3)))))
      )
      (mergeOffspring $deme $newInstances1 $newInstances2 $newInstances3)
)
 )

;; Raw fitness is tracked independently from the penalized center score.
(= (bestRawScore $scoredInstances)
   (foldl-atom $scoredInstances () $bestRaw $scoredInst
     (let (mkSInst (mkPair $inst $score)) $scoredInst
       (let $raw (getScore $score)
         (if (== $bestRaw ()) $raw (max $bestRaw $raw))))))

;; Project the raw-best score directly from a deme's attached scored rows.
(= (bestRawDeme (mkDeme $rep (mkSInstSet $scoredInstances) $id))
   (bestRawScore $scoredInstances))

;; Candidate scoring/cache/counting adapters live in scoring/candidate-evaluation.

;; Feature-selection hill climbing has no representation/id pair, but it still
;; appends new rows after an already-scored prefix. Score only that suffix and
;; report its real row count instead of rescoring the accumulated population.
(= (transformAppendedFeatureSelection
      (mkSInstSet $instances) $prefixSize $transformFunction $itable
      $miConfidence $prePenalty $preMinActivation $preMaxActivation
      $prePositive $scorerType)
   (let* (
          ($prefix (List.takeN $prefixSize $instances))
          ($suffix (List.drop $prefixSize $instances))
          ($scoredSuffix
            ($transformFunction
              (mkSInstSet $suffix) $itable
              $miConfidence $prePenalty $preMinActivation
              $preMaxActivation $prePositive $scorerType))
          ((mkSInstSet $scoredRows) $scoredSuffix)
         )
     ((mkSInstSet (List.concat $prefix $scoredRows))
      (List.length $suffix))))

;; crossover for feature selection
; (: crossoverFs (-> Number Number Instance (InstanceSet $a) ((InstanceSet $a) Number)))
(= (crossoverFs $size $nNewInstances $sampleStart $sampleSize $centerInst $scoredInstSet)
   (let* (
          ((mkSInstSet $before) $scoredInstSet)
          ($updated
            (crossTopOneFs
              $scoredInstSet $nNewInstances
              $sampleStart $sampleSize $centerInst))
          ((mkSInstSet $after) $updated)
         )
     ($updated (- (List.length $after) (List.length $before)))))

;; (: returnBest (-> (ScoredInstance Number) (ScoredInstance Number) (ScoredInstance Number)))
(= (returnBest (mkSInst $inst1) (mkSInst $inst2)) (returnBest < (mkSInst $inst1) (mkSInst $inst2)) )

;; (: returnBest (-> (-> $score $score Bool) (ScoredInstance $score) (ScoredInstance $score) (ScoredInstance $score)))
(= (returnBest $lessFn (mkSInst $inst1) (mkSInst $inst2))
   (if (apply $lessFn (Pair.second $inst1) (Pair.second $inst2))
       (mkSInst $inst2)
       (mkSInst $inst1)))

(= (getDisk (mkDeme (mkRep (mkKbMap $kbMap (mkDscMp $disc)) $tree) $instSet $id)) $disc)
(= (getDisk (mkDeme (mkRep (mkKbMap (mkDscMp $disc)) $tree) $instSet $id)) $disc)

(= (getTTableParams (mkTruthTableBScore $cpxCoeff $size $iTable))
    ($cpxCoeff $size $iTable)
)
(= (getITableParams (mkITable $rows $labels))
    ($rows $labels)
)

;; Hillclimbing implementation
;;
;; Algorihtm:
;; Takes the maximum distance and best possible scores.
;; Takes the number of iteration under consideration.
;; Tracks the best score found so far as well.
;; Start with center instance and previous center as the same instance
;; Iterates until a certain critera is met.
;;    Criteria: If either the best possible score is found or the maximum distance has reached.
;;    Steps:
;;      Estimate neighborhood
;;      Number of new instances
;;      Cross over if iteration is > 1 and (either minimum in a deme is greater than 3 or last chance) and not already crossed over. Set the already cross over as true.
;;      Sample new instances if not cross over
;;      Change the prevCenter with centerInstance
;;      Score every instance in the deme using the scorer
;;      Get the best instance in the deme and make sure it is greater than the best instance so far.
;;      Check if the score has improve, if so update the center instance by the best instance found. Set the distance to 1. and change already xover to false.
;;      If not, check if no crossover was made and if so increase the distance by 1.
;;      If it is the first time through the loop, we should not exit but we should set the distance to 1 and retry the iteration.

;; (: hillClimbing (-> Deme (TruthTableBScore $a) Instance (-> Deme (TruthTableBScore $a) Instance $Scorer (Instance Deme $state))))
(= (hillClimbing $POASet $tTableBscorer $centerInst) 
    (hillClimbing $POASet $tTableBscorer $centerInst (mkParams applyComplexityBasedScore ())))
    
;; (: hillClimbing (-> Deme (TruthTableBScore $a) Instance $Scorer (Instance Deme $state)))
;; $FsScorer should be passed using a `mkScorer` constructor other wise it will cause an error in PeTTa.
;; ($optimize $deme $targetScore $inst (mkParams applyActionBasedScore ($nTrials $complexityRatio)))
(= (hillClimbing $POASet $tTableBscorer $centerInst (mkParams $scorer $FsScorer))
  (case (mkParams $scorer)
    (
      ((mkParams applyComplexityBasedScore)
        (let*
          (
            ($disc (getDisk $POASet))
            (($cpxCoeff $size $iTable) (getTTableParams $tTableBscorer))
            ($_seedAttached
              (seedAttachedCandidateScores
                $POASet ($iTable $cpxCoeff)))
          )
(hillClimbing ((min (param maxDist) (List.length (second $centerInst))) (param minXoverNeighbors) 0) (False False False $centerInst 0 0 (worstCscore) (* -1 (pow-math 10 308)) 0 0 1)
                        $POASet
                        ($disc $cpxCoeff $size $iTable)
                        $centerInst
                        ()
                        estimateNeighborhood crossover
                        sampleNewInstances transform)))
      ((mkParams applyMutualInformationBasedScore)
        (let*
          (
            ;; ($_ (println! $tTableBscorer))
            (($rows $labels) (getITableParams $tTableBscorer))
            ;; ($_ (println! (iTable: $tTableBscorer)))
            ;; ($_ (println! (Rows: $rows)))
            ;; ($_ (println! (Labels: $labels)))
            ($FsScorerType (if (== $FsScorer ()) mi $FsScorer))
          )
(hillClimbing ((min (param maxDist) (List.length (second $centerInst))) (param minXoverNeighbors) 0) (False False False $centerInst 0 0 0 0 0 0 1)
              $POASet 
              ($labels $rows () ())
              $centerInst
              (50.0 1.0 0.5 1.0 True $FsScorerType)
              estimateNeighborhoodFs crossoverFs 
              sampleNewInstancesFs transformFs
          )))
      ((mkParams applyActionBasedScore)
        (let*
          (
            ($disc (getDisk $POASet))
            (($nTrials $complexityRatio) $FsScorer)
            ;; $tTableBscorer is the scalar target score for this action arm.
            ($targetPenScore $tTableBscorer)
)
          ;; Slot-packing: $rowOCoeff <- $nTrials and $iTable <-
          ;; $complexityRatio. The recursive engine wraps those values in a
          ;; tagged payload before candidate scoring.
(hillClimbing ((param maxDist) (param minXoverNeighbors) $targetPenScore)
                                    (False False False $centerInst 0 0 (worstCscore) (* -1 (pow-math 10 308)) 0 0 1)
                                    $POASet
                                    ($disc $nTrials mkActionCtx $complexityRatio)
                                    $centerInst
                                    ()
                                    estimateNeighborhood crossover
                                    sampleNewInstances transform)))
    )))

(= (hillClimbing $constants $state $deme $payload $center $hyper $estimate $cross $sample $transform)
   (let $reason (hcBoundaryStop $constants $state $deme)
     (if (== $reason ())
         (let $_generation (if (get-state &hcActive)
                              (change-state! &hcGenerations (+ 1 (get-state &hcGenerations))) True)
           (hillClimbingStep $constants $state $deme $payload $center $hyper $estimate $cross $sample $transform))
         (let $_stop (change-state! &hcStop $reason) ($center $deme $state)))))

(= (hillClimbingStep ($maxDist $minXoverNeighbors $bestPossibleScore) ;; Constant parameters
                 ($alreadyXover $lastChance $__ $prevCenter $prevStart $prevSize $bestSscore $bestScore $currentNInstances $d $i)
                 $POASet
                 ($neighborhood $rowOCoeff $size $iTable)
                 $centerInst
                 $hyperparamsfs
                 $estimateFunction $crossoverFunction $samplingFunction $transformFunction) ;; Helper functions
   (let*
      (
        ;; Long searches can execute thousands of iterations, so progress
        ;; output is controlled uniformly for every problem.
        ($progressEnabled (param diagnostics))
        ($_blank (if $progressEnabled (println! "") ()))
        ($_iteration (if $progressEnabled (println! (Iteration $i running)) ()))

        ($totalNNeighbors ($estimateFunction $d $neighborhood))
        ($_neighborhoodEstimate
          (if (param diagnostics)
              (println! (HillClimbingNeighborhoodEstimate
                           (distance $d) (neighbors $totalNNeighbors)))
              ()))

        ;; Counted expansion installs this deme's fair share of the remaining
        ;; complete-run budget. Direct calls fall back to maxEvals. A large
        ;; numeric allowance represents the documented negative/unlimited mode.
        ($outerLimit (get-state &localEvalLimit))
        ($configuredLimit
          (if (get-state &hcActive)
              (limitsMaxEvals (get-state &hcLimits))
              (if (< $outerLimit 0) (param maxEvals) $outerLimit)))
        ($maxEvals
          (if (< $configuredLimit 0)
              (pow-math 10 18)
              $configuredLimit))
        ($nNewNeighbors (hcProposalAllowance (nNewInstances $d $maxEvals $currentNInstances $totalNNeighbors)))

        ;; Evaluation count and population index are different quantities.
        ($currentDemeSize
          (if (and (not (== $rep ())) (not (== $id ())))
              (let (mkDeme $_rep (mkSInstSet $currentInstances) $_id) $POASet
                (List.length $currentInstances))
              $currentNInstances))

        ($largeNbh (>= $totalNNeighbors $minXoverNeighbors))
        ;; Honor the C++ crossover switch.
        ($xOver (and (param hcCrossover)
                     (and (> $i 2)
                          (and (>= $currentDemeSize 3)
                               (and (not $alreadyXover) (or $largeNbh $lastChance)))))) ;; INFO: Has to be greater than 2 minimum.
        ($_crossover (if $progressEnabled (println! (Crossover: $xOver)) ()))
        ($_center
          (if $progressEnabled
              (println! (CenterInst: (second $centerInst)))
              ()))
        ($_size (if $progressEnabled (println! (size: $size)) ()))
        ($_neighborhood
          (if $progressEnabled
              (println! ($totalNNeighbors : $nNewNeighbors : $d))
              ()))
        ( 
          ; $newPOA
          ((mkDeme $rep $updatedInstSet $id) $newInstances)
                                                            (case ($xOver $size)
                                                              (
                                                                ((True ()) (let ($updatedInstSet $newInstances) ($crossoverFunction $currentDemeSize $nNewNeighbors $prevStart $prevSize $prevCenter $POASet)
                                                                              ((mkDeme () $updatedInstSet ()) $newInstances)))
                                                                ;; Cross the previous sample relative to the center from which it was generated.
                                                                ((True $notEmpty)  ($crossoverFunction $currentDemeSize $nNewNeighbors $prevStart $prevSize $prevCenter $POASet))
                                                                ((False ()) (let ($updatedInstSet $newInstances) ($samplingFunction $totalNNeighbors $nNewNeighbors $centerInst (mkITable $rowOCoeff $neighborhood) $POASet $d)
                                                                              ((mkDeme () $updatedInstSet ()) $newInstances)))
                                                                ((False $notEmpty)
                                                                        (let $result (if (get-state &hcActive)
                                                                                         (hcSampleCounted $nNewNeighbors $centerInst $POASet $d)
                                                                                         ($samplingFunction $totalNNeighbors $nNewNeighbors $centerInst $POASet $d))
                                                                        ;; (trace! ("Result: " $result)
                                                                                $result
                                                                        ;; )
                                                                        ))
                                                              )
                                                          ))
        ; ($_ (println! (New POASet: $newPOA)))
        ; (((mkDeme $rep $upInstSet $id) $newInstances) $newPOA)
        ; ($_ (println! (New rep: $rep)))
        ;; ($_ (println! (New Inst: $newInstances at Distance: $d)))
        ;; ($exprList (let (mkSInstSet $list) $updatedInstSet (List.listToExpr $list)))
        ;; ($bmr (map-atom $exprList $inst (let (mkSInst $x) $inst (println! (Inst: (List.listToExpr (second (Pair.first $x))) Tree: (preOrder (getCandidate $rep (Pair.first $x))))))))
        ;; ($_ (println! ""))
        ;; ($_ (println! (Newinstances: $updatedInstSet)))
        ;; ($_ (println! ""))
        ;; deconstruct the hyper params for fs function
        (($miConfi $prePenalty $preMinActivation $preMaxActivation $prePositive $scorerType) (if (== () $hyperparamsfs) (() () () () () ()) $hyperparamsfs))

        ;; Keep the action optimizer's internal scorer payload distinct from
        ;; the canonical lifecycle context used by Boolean runs.
        ($incrementalContext
          (case $iTable
            (((mkContinCtx $table $error $ratio $mode $target) $iTable)
             ((mkITable $rows $labels) ($iTable $rowOCoeff))
             ($other (mkActionScoreContext $iTable $rowOCoeff)))))
        ($scoreBatch
          (if (or (== $rep ()) (== $id ()))
              (transformAppendedFeatureSelection
                $updatedInstSet $currentDemeSize $transformFunction
                (mkITable $rowOCoeff $neighborhood)
                $miConfi $prePenalty $preMinActivation
                $preMaxActivation $prePositive $scorerType)
              (if (get-state &hcActive)
                  (hcScoreAppended $updatedInstSet $currentDemeSize $rep $id $incrementalContext
                    (optimizerRemaining (limitsMaxEvals (get-state &hcLimits)) $currentNInstances))
                  (transformAppendedIncrementalBounded
                    $updatedInstSet $currentDemeSize $rep $id $incrementalContext
                    (max 0 (- $maxEvals $currentNInstances))))))
        (($scoredSet $actualNewEvals) $scoreBatch)
        ((mkSInstSet $scoredInstances) $scoredSet)
        ($retainedNewInstances (if (get-state &hcActive)
                                  (- (List.length $scoredInstances) $currentDemeSize)
                                  $newInstances))
        ($updatedEvalCount (+ $currentNInstances $actualNewEvals))
        ($_evalDiagnostics
          (if (param diagnostics)
              (println! (HillClimbingEvaluations
                           (actualNew $actualNewEvals)
                           (cumulativeLocal $updatedEvalCount)))
              ()))

        ($updatedDeme (if (or (== $rep ()) (== $id ())) 
                          (mkSInstSet $scoredInstances) 
                          (mkDeme $rep (mkSInstSet $scoredInstances) $id)))
        
        ;; ($sExprList (List.listToExpr $scoredInstances))
        ;; ($amr (map-atom $sExprList $inst (let (mkSInst $x) $inst (println! (Inst: (List.listToExpr (second (Pair.first $x))) Tree: (preOrder (getCandidate $rep $id (Pair.first $x))) Score: (getPenScore (Pair.second $x)))))))
        ;; ($_ (println! ""))
        ;; ($_ (println! (Scored instances: $scoredInstances)))
        ;; ($_ (println! (Scored instances....)))
        ;; ($_ (println! ""))

        ((mkSInst $newBestInstPair)
          (if (and (get-state &hcActive) (not (== $scoredInstances ())))
              (optimizerBestRow $scoredInstances)
              (List.foldl hillScoreHelper (mkSInst (mkPair $centerInst $bestSscore)) $scoredInstances)))
        ($newBestScore (if (or (== $rep ()) (== $id ())) 
                          (Pair.second $newBestInstPair)
                          (getPenScore (Pair.second $newBestInstPair)))) ;; This could be the original best candidate or a new one.
        ($hasImproved
          (case $incrementalContext
            (((mkContinCtx $improvementTable $improvementError $improvementRatio $improvementMode $improvementTarget)
              (let $improved scoreImproved ($improved $incrementalContext $newBestScore $bestScore)))
             ($nonContinuousImprovement (> $newBestScore (+ $bestScore (param hcScoreImprovedThreshold)))))))
        
        ;; ($_ (println! (Best instance: (Pair.first $newBestInstPair))))
        ;; ($_ (println! (Best candidate: (preOrder (getCandidate $rep (Pair.first $newBestInstPair))))))
        ($_best
          (if $progressEnabled
              (println! (New best score: $newBestScore))
              ()))
        ;; ($_ (println! ""))

        ($nextCenterInst (if $hasImproved (Pair.first $newBestInstPair) $centerInst))
        ($nextBestScore (if $hasImproved $newBestScore $bestScore))
        ($nextBestSscore (if $hasImproved (Pair.second $newBestInstPair) $bestSscore))
        ($nextDistance (if $hasImproved 1 (if (not $xOver) (+ 1 $d) $d)))
        
        ;; ($_ (println! (NextDistance: $nextDistance)))

        ($hillStepResult (if (and (== $totalNNeighbors 1) (== $nextDistance 1))
                                  (hillClimbing ($maxDist $minXoverNeighbors $bestPossibleScore)
                                                ((and $xOver (not $hasImproved)) $lastChance $hasImproved $centerInst $prevStart $prevSize $nextBestSscore $nextBestScore $updatedEvalCount $nextDistance (+ 1 $i)) ;; Updated state
                                                $updatedDeme
                                                ($neighborhood $rowOCoeff $size $iTable)
                                                $nextCenterInst
                                                $hyperparamsfs
                                                $estimateFunction $crossoverFunction $samplingFunction $transformFunction)
                                  ($nextCenterInst $updatedDeme ((and $xOver (not $hasImproved)) $lastChance $hasImproved $centerInst $currentDemeSize $retainedNewInstances $nextBestSscore $nextBestScore $updatedEvalCount $nextDistance $i))))
        (($newCenter $newDeme ($newXover $newLastChance $newHasImproved $newPrevCenter $newPrevStart $newPrevSize $newBestSscore $nextNewBestScore $newCurrentNInstance $newDistance $newI)) $hillStepResult)
        
        ;; Termination check compares against the scalar `$bestPossibleScore`,
        ;; which carries the *raw* best score (matching classic MOSES). So we
        ;; must extract the raw-score field from the candidate's Cscore here,
        ;; not the penalty-adjusted one -- comparing penScore against a raw
        ;; target would mix the complexity penalty into the threshold.
        ($scoreToCompareBelow
          (if (or (== $rep ()) (== $id ()))
              $newBestSscore
              (bestRawDeme $newDeme)))
        ($_bestDiagnostics
          (if (param diagnostics)
              (println! (HillClimbingBest
                           (bestRaw $scoreToCompareBelow)
                           (bestPenalized $newBestScore)))
              ()))
        ;; ($_ (println! (Found newBestSscore After (+ 1 $i) iteration is: $newBestSscore $scoreToCompareBelow)))
        ;; ($_ (println! ""))
        ($_ (cut)) ;; Commit choice points before tail-recursing — mirrors runMoses pattern. This gives few extra seconds of speed
    )
    (if (<= (- $maxEvals $newCurrentNInstance) 0)
        (trace! (Terminating because of maxEval ending) ($newCenter $newDeme ($newXover $newLastChance $newHasImproved $newPrevCenter $newPrevStart $newPrevSize $newBestSscore $nextNewBestScore $newCurrentNInstance $newDistance $newI)))
        (if (<= $bestPossibleScore $scoreToCompareBelow)
                  (trace! (Terminating because of best possible score: $bestPossibleScore found $scoreToCompareBelow)
            ($newCenter $newDeme ($newXover $newLastChance $newHasImproved $newPrevCenter $newPrevStart $newPrevSize $newBestSscore $nextNewBestScore $newCurrentNInstance $newDistance $newI))
                  )
            (let ($finalCenter $finalDeme ($finalXover $finalLastChance $finalHasImproved $finalPrevCenter $finalPrevStart $finalPrevSize $finalBestCscore $finalNewBestScore $finalCurrentNInstance $finalDistance $finalI))
              ;; Match the C++ "last chance" rule: simplex crossover is tried
              ;; after a stalled nearest-neighbor scan when widening is off,
              ;; or only after widened search has exhausted maxDist.
              (if (and (param hcCrossover)
                       (and (and (not $newHasImproved) (not $newLastChance))
                            (and (not $newXover)
                                 (or (not (param hcWidenSearch))
                                     (< $maxDist $newDistance)))))
                  ;; If we just did the nearest neighbors and found no improvement,
                  ;;  then try again one last time, we may get lucky.
                  (hillClimbing ($maxDist $minXoverNeighbors $bestPossibleScore)
                                ($newXover True $newHasImproved $newPrevCenter $newPrevStart $newPrevSize $newBestSscore $nextNewBestScore $newCurrentNInstance $newDistance (+ 1 $newI)) ;; Updated state
                                $newDeme
                                ($neighborhood $rowOCoeff $size $iTable)
                                $newCenter
                                $hyperparamsfs
                                $estimateFunction $crossoverFunction $samplingFunction $transformFunction)
                  ;; (trace! (Continue to next iteration because of no more last chance)
                          ($newCenter $newDeme ($newXover $newLastChance $newHasImproved $newPrevCenter $newPrevStart $newPrevSize $newBestSscore $nextNewBestScore $newCurrentNInstance $newDistance $newI))
                  ;; )
                  )
  
              (if (< $maxDist $finalDistance)
                  (trace! (Terminating because of maximum distance reached)
                  ($finalCenter $finalDeme ($finalXover False $finalHasImproved $finalPrevCenter $finalPrevStart $finalPrevSize $finalBestCscore $finalNewBestScore $finalCurrentNInstance $finalDistance $finalI))
                  ) ;; I don't know why I didn't do this earlier but incrementing is needed here.
                  ;; With widening disabled, stop at the local optimum exactly
                  ;; as C++ does.  When enabled, continue at the wider distance.
                  (if (and (not $finalHasImproved) (not (param hcWidenSearch)))
                      (trace! (Terminating because score hasn't improved) ($finalCenter $finalDeme ($finalXover False $finalHasImproved $finalPrevCenter $finalPrevStart $finalPrevSize $finalBestCscore $finalNewBestScore $finalCurrentNInstance $finalDistance $finalI)))
                      (hillClimbing ($maxDist $minXoverNeighbors $bestPossibleScore)
                                ($finalXover False $finalHasImproved $finalPrevCenter $finalPrevStart $finalPrevSize $finalBestCscore $finalNewBestScore $finalCurrentNInstance $finalDistance (+ 1 $finalI)) ;; Updated state
                                $finalDeme
                                ($neighborhood $rowOCoeff $size $iTable)
                                $finalCenter
                                $hyperparamsfs
                                $estimateFunction $crossoverFunction $samplingFunction $transformFunction)
                    )
                  )
            )
            )
    
                    )

     
    )          
)

(= (hillScoreHelper $inst1 $inst2) (returnBest < $inst1 $inst2))

;; Helper to get initial disc spec from a knob
(= (getInitDiscSpec (mkLSK (mkDiscKnob $k $m (mkDiscSpec $init) $cur $opts)))
   (if (== $opts ()) $init 0))

;; Helper to initialize center instance from deme
;; Creates an instance with knobs set to their initial disc specs
(= (initCenterInst (mkDeme (mkRep (mkKbMap $kbMp (mkDscMp $disc)) $tree) $instSet $id))
   (let $knobList (MultiMap.values $disc)
     (let $initSpecs (List.map getInitDiscSpec $knobList)
       (mkInst $initSpecs))))

;; Common-contract adapter. All legacy HC state interpretation stays here.
(= (hcContextParts $context)
   (case $context
     (((mkOptimizerContext $inner $target)
       (let ($scoring $unusedTarget) (hcContextParts $inner) ($scoring $target)))
      ((mkContinCtx $table $error $ratio $mode $target) ($context $target))
      ((mkTruthTableBScore $ratio $size $table) (($table $ratio) 0))
      ((mkActionCtx $trials $ratio $target) ((mkActionScoreContext $ratio $trials) $target)))))

(= (hcSnapshot)
   ((get-state &hcActive) (get-state &hcLimits) (get-state &hcRng) (get-state &hcDeadline)
    (get-state &hcProposals) (get-state &hcGenerations) (get-state &hcHits)
    (get-state &hcInvalids) (get-state &hcStop) (get-state &localEvalLimit)))
(= (hcRestore ($active $limits $rng $deadline $props $gens $hits $invalids $stop $local))
   (let* (($_a (change-state! &hcActive $active)) ($_l (change-state! &hcLimits $limits))
          ($_r (change-state! &hcRng $rng)) ($_d (change-state! &hcDeadline $deadline))
          ($_p (change-state! &hcProposals $props)) ($_g (change-state! &hcGenerations $gens))
          ($_h (change-state! &hcHits $hits)) ($_i (change-state! &hcInvalids $invalids))
          ($_s (change-state! &hcStop $stop)) ($_e (change-state! &localEvalLimit $local))) True))

(= (hillClimbingOptimizer $deme $context $initial $limits $rng $config)
   (let* (($saved (hcSnapshot))
          ($seconds (limitsTimeLimitSec $limits))
          ($deadline (if (< $seconds 0) -1 (+ (candidateNow) $seconds)))
          ($_scope (hcRestore (True $limits $rng $deadline 0 0 0 0 () (limitsMaxEvals $limits))))
          ;; collapse contains the legacy engine's cut and permits cleanup on
          ;; an empty result. Domain callbacks must tag native runtime errors.
          ($results (collapse (hcStartCommon $deme $context $initial $limits)))
          ($_restore (hcRestore $saved)))
     (case $results
       ((($one) $one)
        ($other (Error $results "HC did not return one optimizer result"))))))

(= (hcPrepareRows $rep $rows $context)
   (case $context
     (((mkContinCtx $table $error $ratio $mode $target)
       (let $canonical canonicalizeContinCandidateRows ($canonical $rep $rows)))
      ($other $rows))))
(= (hcAppendRows $prefix $suffix $context)
   (case $context
     (((mkContinCtx $table $error $ratio $mode $target)
       (let $dedup uniqueUnseenScoredInstances
         (List.concat $prefix ($dedup $suffix $prefix))))
      ($other (List.concat $prefix $suffix)))))

(= (hcInputRows () $rep $id $context) ())
(= (hcInputRows (cons $row $rest) $rep $id $context)
   (cons (case $row
           (((mkEvaluatedCandidate $inst $tree $score $status) $row)
            ((mkSInst (mkPair $inst $score))
             (List.head (legacyCandidateRows ($row) $rep $id $context)))))
         (hcInputRows $rest $rep $id $context)))

(= (hcStartCommon (mkDeme $rep (mkSInstSet $inputRows) $id) $context $initial $limits)
   (let* ((($scoring $target) (hcContextParts $context))
          ($rows (hcPrepareRows $rep (hcInputRows $inputRows $rep $id $scoring) $scoring))
          ($attached (filter-atom $rows $row (candidateIsEvaluated $row)))
          ($validAttached (filter-atom $attached $row (candidateIsValid $row)))
          ($_attachedInvalids (change-state! &hcInvalids
             (List.length (filter-atom $attached $row (not (candidateIsValid $row))))))
          ($known (legacyScoredRows $validAttached))
          ($initialDeme (mkDeme $rep (mkSInstSet $known) $id))
          ($_seed (seedEvaluatedCandidates $attached (candidateEvaluationContext $scoring)))
          ($early (hcStopForDeme $initialDeme $target 0)))
     (if (not (== $early ()))
         (hcCommonResult $initialDeme 0 $early)
         (let* (($pending (filter-atom $rows $row (not (candidateIsEvaluated $row))))
                ($instances (List.map candidateInstance $rows))
                ($toScore (if (once (is-member $initial $instances)) $pending
                             (cons (mkEvaluatedCandidate $initial () () candidatePending) $pending)))
                ($selected (List.takeN (hcProposalAllowance (List.length $toScore)) $toScore))
                ($_props (hcRecordProposals (List.length $selected)))
                ($_gen (change-state! &hcGenerations 1))
                ($batch (evaluateCandidateBatchUntil (hcPrepareRows $rep $selected $scoring) $rep $id $scoring (limitsMaxEvals $limits)
                          materializeCandidateForContext scoreMaterializedCandidate (get-state &hcDeadline)))
                ($_stats (hcRecordBatch $batch))
                ($valid (filter-atom (batchEvaluated $batch) $row (candidateIsValid $row)))
                ($scored (hcAppendRows $known (legacyScoredRows $valid) $scoring))
                ($deme (mkDeme $rep (mkSInstSet $scored) $id))
                ($calls (batchActualEvaluations $batch))
                ($reason (hcStopForDeme $deme $target $calls)))
           (if (not (== $reason ()))
               (hcCommonResult $deme $calls $reason)
               (let* (($best (optimizerBestRow $scored))
                      ($center (if (== $best ()) $initial (getInst $best)))
                      ($score (if (== $best ()) (worstCscore) (getSInstScore $best)))
                      ($state (False False True $initial 0 (List.length $scored) $score (getPenScore $score) $calls 1 2))
                      (($ignored $finalDeme $finalState)
                        (hcRunCommonEngine $deme $scoring $target $center $state))
                      ($used (hcStateEvaluations $finalState))
                      ($stop (hcStopForDeme $finalDeme $target $used)))
                 (hcCommonResult $finalDeme $used (if (== $stop ()) stopStagnation $stop))))))))

(= (hcStateEvaluations ($x $last $improved $center $start $size $score $pen $evals $dist $iteration)) $evals)
(= (hcBoundaryStop ($maxDist $minXover $target) $state $deme)
   (if (get-state &hcActive)
       (let $stop (get-state &hcStop)
         (if (== $stop ()) (hcStopForDeme $deme $target (hcStateEvaluations $state)) $stop))
       ()))
(= (hcStopForDeme (mkDeme $rep (mkSInstSet $rows) $id) $target $evals)
   (if (if (== $rows ()) False (>= (bestRawScore $rows) $target)) stopTargetReached
       (let $resource (hcResourceStop $evals)
         (if (not (== $resource ())) $resource
             (if (and (== $rows ()) (> (get-state &hcInvalids) 0)) stopAllInvalid
                 (let $space (foldl-atom (getDisk (mkDeme $rep (mkSInstSet $rows) $id)) 1 $size $entry
                                (let (mkMultip $m) (getKnobMultip (second $entry)) (* $size $m)))
                   (if (>= (List.length (unique-atom (List.map getInst $rows))) $space)
                       stopExhaustedSpace ())))))))

(= (hcRunCommonEngine $deme $scoring $target $center $state)
   (let $disc (getDisk $deme)
     (case $scoring
       (((mkContinCtx $table $error $ratio $mode $targetScore)
         (hillClimbing ((min (param maxDist) (List.length (second $center))) (param minXoverNeighbors) $target)
           $state $deme ($disc $ratio mkContinCtx $scoring) $center ()
           estimateNeighborhood crossover sampleNewInstances transform))
        (((mkITable $rows $labels) $ratio)
         (hillClimbing ((min (param maxDist) (List.length (second $center))) (param minXoverNeighbors) $target)
           $state $deme ($disc $ratio (List.length $rows) (mkITable $rows $labels)) $center ()
           estimateNeighborhood crossover sampleNewInstances transform))
        ((mkActionScoreContext $ratio $trials)
         (hillClimbing ((param maxDist) (param minXoverNeighbors) $target)
           $state $deme ($disc $trials mkActionCtx $ratio) $center ()
           estimateNeighborhood crossover sampleNewInstances transform))))))

(= (hcCommonResult (mkDeme $rep (mkSInstSet $rows) $id) $calls $reason)
   (let $best (optimizerBestRow $rows)
     (mkOptimizerResult (mkDeme $rep (mkSInstSet $rows) $id)
       (if (== $best ()) () (getInst $best)) $calls $reason
       (mkOptimizerDiag (get-state &hcProposals) (get-state &hcHits) (get-state &hcInvalids) 0)
       (get-state &hcRng))))

(= (hcScoreAppended (mkSInstSet $rows) $prefixSize $rep $id $context $left)
   (let* (($prefix (List.takeN $prefixSize $rows))
          ($pending (hcPrepareRows $rep (legacyCandidateRows (List.drop $prefixSize $rows) $rep $id $context) $context))
          ($batch (evaluateCandidateBatchUntil $pending $rep $id $context $left
                    materializeCandidateForContext scoreMaterializedCandidate (get-state &hcDeadline)))
          ($_stats (hcRecordBatch $batch))
          ($valid (filter-atom (batchEvaluated $batch) $row (candidateIsValid $row))))
     ((mkSInstSet (hcAppendRows $prefix (legacyScoredRows $valid) $context)) (batchActualEvaluations $batch))))

;; Bounded pure sampling. Select coordinates without replacement (no rejection
;; loop over already-picked coordinates), then choose a different legal value.
(= (hcRandomNeighbor 0 $pool $values $disc $rng) ((mkInst $values) $rng))
(= (hcRandomNeighbor $distance $pool $values $disc $rng)
   (if (> $distance 0)
       (let* ((($choice $rng1) (optimizerRandomInt 0 (- (List.length $pool) 1) $rng))
              ($index (List.getByIdx $pool $choice))
              ($remaining (filter-atom $pool $i (not (== $i $index))))
              (($spec $knob) (MultiMap.getByIdx $index $disc))
              ((mkMultip $m) (getKnobMultip $knob))
              (($value $rng2) (optimizerRandomInt 1 (- $m 1) $rng1))
              ($old (List.getByIdx $values $index))
              ($new (if (== $old $value) 0 $value)))
         (hcRandomNeighbor (- $distance 1) $remaining (List.replaceAt $values $index $new) $disc $rng2))
       (empty)))
(= (hcRandomNeighbors 0 $distance $disc $center $pool $rng) (() $rng))
(= (hcRandomNeighbors $n $distance $disc (mkInst $values) $pool $rng)
   (if (> $n 0)
       (let* ((($inst $rng1) (hcRandomNeighbor $distance $pool $values $disc $rng))
              (($rest $next) (hcRandomNeighbors (- $n 1) $distance $disc (mkInst $values) $pool $rng1)))
         ((cons $inst $rest) $next)) (empty)))
(= (hcSampleCounted $requested $center (mkDeme (mkRep (mkKbMap (mkDscMp $disc)) $tree) (mkSInstSet $rows) $id) $distance)
   (let* (($kb (mkKbMap (mkDscMp $disc)))
          ($available (countNeighborhood $kb $center $distance $requested))
          ($pool (filter-atom (genList (- (List.length (second $center)) 1)) $i
                   (let ($spec $knob) (MultiMap.getByIdx $i $disc)
                     (let (mkMultip $m) (getKnobMultip $knob) (> $m 1)))))
          (($proposals $nextRng)
            (if (or (== $requested 0) (> $distance (List.length $pool))) (() (get-state &hcRng))
              (if (<= $available $requested)
                  ((let $enumerate generateAllInNeighborhoodForDisc ($enumerate (mkDscMp $disc) $center $distance)) (get-state &hcRng))
                  (hcRandomNeighbors $requested $distance $disc $center $pool (get-state &hcRng)))))
          ($_rng (change-state! &hcRng $nextRng))
          ($_props (hcRecordProposals (List.length $proposals)))
          ($fresh (let $dedup uniqueUnseenScoredInstances ($dedup (List.map initInstScore $proposals) $rows))))
     ((mkDeme (mkRep $kb $tree) (mkSInstSet (List.concat $rows $fresh)) $id) (List.length $fresh))))
