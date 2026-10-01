;; Shared population engine for Step 9 and subsequent BOA/hBOA models.
;; No legacy univariate or hill-climbing implementation is called here.
;; All local state is explicit. Archive/seen are deme-local; model is refit
;; each generation. Population cap is independent of output/archive limits.
;; Model callbacks supply only fitting and sampling behavior; the engine keeps
;; candidate scoring, duplicate handling, budgets, replacement, and stopping
;; policy common across univariate, BOA, and hBOA searches.
;; Config: population, selection, offspring, tournament, alpha, exploration,
;;         max refill attempts PER generation, stagnation generations.
;; Constructs the active EDA configuration record from global parameters.
;;   Arguments: None; values are read from the optimizer parameter environment.
;;   Returns: mkEDAConfig record containing population, selection, offspring, and replacement bounds.
(= (edaConfigured)
   (mkEDAConfig (param edaPopulationSize) (param edaSelectionSize)
     (param edaOffspringSize) (param edaTournamentSize) (param edaPseudocount)
     (param edaExploration) (param edaMaxRefillAttempts) (param edaStagnationGenerations)))

;; Tests whether a value is a strictly positive natural number.
;;   $n: Value to test.
;;   Returns: True if $n is an integer > 0, False otherwise.
(= (edaPositiveInt $n) (if (continNatural $n) (> $n 0) False))

;; Validates that all EDA configuration parameters satisfy type and range constraints.
;;   $config: Candidate mkEDAConfig record.
;;   Returns: True if configuration values are valid finite bounds, False otherwise.
(= (edaConfigValid $config)
   (case $config
     (((mkEDAConfig $p $s $o $t $a $e $r $stale)
       ;; MeTTa and is eager: guard types before any arithmetic comparison.
       (if (all ((edaPositiveInt $p) (edaPositiveInt $s) (edaPositiveInt $o)
                 (edaPositiveInt $t) (edaPositiveInt $r) (edaPositiveInt $stale)))
           (if (and (optimizerFiniteNumber $a) (optimizerFiniteNumber $e))
               (and (<= $o $p)
                 (and (and (> $a 0) (optimizerFiniteNumber (catch (+ $s (* $a 2147483646)))))
                      (and (>= $e 0) (<= $e 1)))) False)
           False))
      ($bad False))))

;; Unpacks the inner scoring context and objective scalar target from an optimizer context.
;;   $context: Problem scoring context (optimizer context, continuous, Boolean, or action).
;;   Returns: Tuple ($scoring $target) for candidate evaluation.
(= (edaContext $context)
   (case $context
     (((mkOptimizerContext $inner $target)
       (let ($scoring $ignored) (edaContext $inner) ($scoring $target)))
      ((mkContinCtx $table $loss $ratio $mode $target) ($context $target))
      ((mkTruthTableBScore $ratio $size $table) (($table $ratio) 0))
      ((mkActionCtx $trials $ratio $target) ((mkActionScoreContext $ratio $trials) $target)))))

;; Constructs the problem field schema from representation and scoring context.
;;   (mkRep $map $tree): Representation containing knob map and tree template.
;;   $context: Problem scoring context.
;;   Returns: Field schema defining field indices, continuous depths, and cardinalities.
(= (edaSchema (mkRep $map $tree) $context)
   (case $context
     (((mkContinCtx $table $loss $ratio $mode $target) (continFieldSchema (mkRep $map $tree)))
      ($discrete (case $map
        (((mkKbMap (mkDscMp $rows)) (discreteFieldSchema (mkDscMp $rows)))
         ((mkKbMap $otherMap (mkDscMp $rows)) (discreteFieldSchema (mkDscMp $rows)))))))))

;; Validates candidate rows and determines if $new is strictly better than $old.
;; Stable ties retain the incumbent; rank by penalized score, then reduced complexity.
;;   $new: Candidate to compare.
;;   $old: Incumbent candidate (or empty list if none).
;;   Returns: True if $new has higher penalized score or lower complexity on tie, False otherwise.
(= (edaBetter $new $old)
   (if (== $old ()) True
       (let* (($a (candidateScore $new)) ($b (candidateScore $old)))
         (or (> (getPenScore $a) (getPenScore $b))
             (and (== (getPenScore $a) (getPenScore $b)) (< (getComp $a) (getComp $b)))))))

;; Inserts a candidate row into a sorted list of candidate rows maintaining descending rank order.
;;   $row: Candidate row to insert.
;;   $rows: Existing sorted list of candidate rows.
;;   Returns: Updated sorted list of candidate rows.
(= (edaInsert $row $rows)
   (case $rows
     ((() ($row))
      ((cons $head $tail) (if (edaBetter $row $head) (cons $row $rows)
                            (cons $head (edaInsert $row $tail)))))))

;; Sorts a list of evaluated candidate rows in descending order of fitness.
;;   $rows: Unsorted list of evaluated candidate rows.
;;   Returns: Sorted list of candidate rows.
(= (edaRank $rows) (foldl-atom $rows () $sorted $row (edaInsert $row $sorted)))

;; Performs elitist truncation replacement, keeping the top $size individuals from population and offspring.
;;   $population: Current population candidate rows.
;;   $offspring: Newly evaluated offspring candidate rows.
;;   $size: Target population size to retain.
;;   Returns: Ranked list of the top $size candidate rows.
(= (edaReplace $population $offspring $size)
   (List.takeN $size (edaRank (List.concat $population $offspring))))
;; RTR distance is Hamming over CANONICAL raw fields (inactive tails are 0).
;; Window indices are sampled WITHOUT replacement. Distance ties keep the
;; first randomly drawn incumbent; score/complexity ties never replace it.
;; Archive retains every valid evaluation, including both champions and RTR
;; rejects. Seen-genotype deduplication is shared with elitist replacement.
;; Computes the Hamming distance between two canonical raw genotype instances.
;;   (mkInst $a): First candidate instance.
;;   (mkInst $b): Second candidate instance.
;;   Returns: Integer number of coordinate positions where $a and $b differ.
(= (edaHamming (mkInst $a) (mkInst $b))
   (List.sum (List.zipWith edaDifferent $a $b)))

;; Indicator function returning 1 if two values are different, 0 if equal.
;;   $a: First value.
;;   $b: Second value.
;;   Returns: 1 if $a != $b, 0 if $a == $b.
(= (edaDifferent $a $b) (if (== $a $b) 0 1))

;; Samples a random window of unique population indices without replacement.
;;   $indices: Candidate population index pool.
;;   $left: Number of indices left to sample.
;;   $rng: Random number generator state.
;;   Returns: Tuple ($sampledIndices $nextRng).
(= (edaWindow $indices $left $rng)
   (if (or (<= $left 0) (== $indices ())) (() $rng)
     (let* ((($pick $next) (optimizerRandomInt 0 (- (List.length $indices) 1) $rng))
            (($tail $end) (edaWindow (List.removeAtIdx $indices $pick) (- $left 1) $next)))
       ((cons (List.getByIdx $indices $pick) $tail) $end))))

;; Finds the population index within a window that has minimum Hamming distance to a candidate row.
;;   $population: Current population list.
;;   $row: Offspring candidate row.
;;   $indices: List of candidate population indices in the tournament window.
;;   Returns: Index of closest incumbent individual.
(= (edaClosest $population $row $indices)
   (foldl-atom (cdr-atom $indices) (car-atom $indices) $best $index
     (if (< (edaHamming (candidateInstance $row) (candidateInstance (List.getByIdx $population $index)))
            (edaHamming (candidateInstance $row) (candidateInstance (List.getByIdx $population $best))))
       $index $best)))

;; Executes Restricted Tournament Replacement (RTR) on a batch of offspring to preserve population diversity.
;;   $population: Incumbent population list.
;;   $offspring: Offspring candidates to consider for replacement.
;;   $size: Target population size.
;;   $window: Window size for neighborhood sampling.
;;   $rng: Random number generator state.
;;   $accepted: Count of offspring that successfully replaced an incumbent.
;;   Returns: Tuple (($rankedPopulation) $nextRng $acceptedCount).
(= (edaRTR $population $offspring $size $window $rng $accepted)
   (case $offspring
     ((() ((edaRank $population) $rng $accepted))
      ((cons $row $rest)
       (if (< (List.length $population) $size)
         (edaRTR (List.append $row $population) $rest $size $window $rng (+ $accepted 1))
         (let* ((($indices $next) (edaWindow (fieldPriorIndices 0 (List.length $population)) $window $rng))
                ($closest (edaClosest $population $row $indices))
                ($better (edaBetter $row (List.getByIdx $population $closest))))
           (edaRTR (if $better (List.replaceAt $population $closest $row) $population)
             $rest $size $window $next (+ $accepted (if $better 1 0)))))))))

;; Validates whether the replacement policy and RTR window size parameters are legal.
;;   Arguments: None; reads edaReplacement and edaRTRWindow from optimizer parameters.
;;   Returns: True if policy is auto/elitist/rtr and window is a positive integer, False otherwise.
(= (edaReplacementValid)
   (and (continContains (param edaReplacement) (auto elitist rtr)) (edaPositiveInt (param edaRTRWindow))))

;; Dispatches population replacement according to configured policy (elitist truncation or RTR).
;;   $sample: Model sampling function reference (used to detect hBOA for auto policy).
;;   $population: Current population candidate rows.
;;   $offspring: Newly evaluated offspring candidate rows.
;;   $size: Target population size.
;;   $rng: Random number generator state.
;;   Returns: Tuple ($newPopulation $nextRng).
(= (edaReplacementStep $sample $population $offspring $size $rng)
   (let $policy (if (== (param edaReplacement) auto)
                    (if (== $sample hboaSample) rtr elitist) (param edaReplacement))
     (if (== $policy elitist) ((edaReplace $population $offspring $size) $rng)
       (let* ((($next $end $accepted) (edaRTR $population $offspring $size (param edaRTRWindow) $rng 0))
              ($_diag (if (param diagnostics)
                (println! (ReplacementDiagnostics (policy rtr) (offspring (List.length $offspring))
                  (accepted $accepted) (window (min (param edaRTRWindow) (List.length $population))))) ())))
         ($next $end)))))

;; Finds the candidate with the highest unpenalized raw score among a collection of candidate rows.
;;   $rows: List of evaluated candidate rows.
;;   Returns: Candidate row achieving maximal raw score.
(= (edaRawBest $rows)
   (foldl-atom $rows () $best $row
     (if (== $best ()) $row
         (if (> (getScore (candidateScore $row)) (getScore (candidateScore $best))) $row $best))))

;; Performs a single tournament selection of size $left, returning the fittest competitor.
;;   $population: Available population candidate rows.
;;   $left: Competitors remaining to sample for this tournament.
;;   $best: Current best competitor in this tournament.
;;   $rng: Random number generator state.
;;   Returns: Tuple ($winner $nextRng).
(= (edaTournament $population $left $best $rng)
   (if (== $left 0) ($best $rng)
       (let* ((($index $next) (optimizerRandomInt 0 (- (List.length $population) 1) $rng))
              ($row (List.getByIdx $population $index)))
         (edaTournament $population (- $left 1) (if (edaBetter $row $best) $row $best) $next))))

;; Selects $count individuals from the population using repeated tournament selection.
;;   $population: Current population candidate rows.
;;   $count: Number of individuals to select.
;;   $tournament: Tournament size per selection round.
;;   $rng: Random number generator state.
;;   Returns: Tuple ($selectedRows $nextRng).
(= (edaSelect $population $count $tournament $rng)
   (if (== $count 0) (() $rng)
       (let* ((($winner $next) (edaTournament $population $tournament () $rng))
              (($tail $end) (edaSelect $population (- $count 1) $tournament $next)))
         ((cons $winner $tail) $end))))

;; Exact canonical space size when representable under the cap, otherwise -1.
;; No floating exponentiation/overflow for deep schemas.
;; Computes the exact combinatorial size of a continuous prefix tree space without overflow.
;;   $depth: Remaining tree depth.
;;   $size: Cumulative prefix state size.
;;   Returns: Canonical state space size or -1 if exceeding representation limits.
(= (edaPrefixSpace $depth $size)
   (if (== $depth 0) $size
       (if (> $size 1073741823) -1 (edaPrefixSpace (- $depth 1) (+ 1 (* 2 $size))))))

;; Calculates the total size of the canonical search space defined by schema fields.
;;   $fields: List of schema field specifications.
;;   $size: Running product accumulator.
;;   Returns: Total number of valid discrete/continuous states, or -1 if unbounded/overflowing.
(= (edaSpace $fields $size)
   (case $fields
     ((() $size)
      ((cons $field $rest)
       (let* (($continuous (== (fieldKind $field) continuous))
              ($factor (if $continuous (edaPrefixSpace (fieldDepth $field) 1) (fieldCardinality $field)))
              ($tail (if $continuous (continDrop $fields (fieldDepth $field)) $rest)))
         (if (< $factor 0) -1
             (if (> $size (/ 2147483647 $factor)) -1 (edaSpace $tail (* $size $factor)))))))))

;; State: population, archive(valid evaluated genotypes), seen(all evaluated
;; canonical genotypes), calls, proposals, cache hits, invalids, RNG, gens, stale.
;; Extracts the archive of valid evaluated candidates from an EDA state.
;;   $state: EDA internal state, represented as mkEDAState with population,
;;           archive, seen genotypes, counters, RNG, generation, and stagnation.
;;   Returns: Evaluated candidate archive list $a.
(= (edaArchive (mkEDAState $p $a $s $c $n $h $i $r $g $z)) $a)

;; Checks whether any execution boundary, budget limit, or termination condition is triggered.
;;   $env: EDA environment context.
;;   $state: Current EDA state.
;;   Returns: Stop symbol (stopTargetReached, stopTimeExhausted, stopBudgetExhausted, etc.) or () if search continues.
(= (edaResourceStop (mkEDAEnv $rep $id $schema $ctx $target $limits $deadline $cfg $fit $sample $space)
                   (mkEDAState $p $a $s $calls $props $hits $invalids $rng $gens $stale))
   (if (if (== $a ()) False (>= (getScore (candidateScore (edaRawBest $a))) $target)) stopTargetReached
       (if (candidateDeadlineReached $deadline) stopTimeExhausted
         (if (optimizerLimitReached (limitsMaxEvals $limits) $calls) stopBudgetExhausted
           (if (optimizerLimitReached (limitsMaxProposals $limits) $props) stopProposalsExhausted
             (if (and (>= $space 0) (>= (List.length $s) $space)) stopExhaustedSpace ()))))))

;; Packages final optimizer result and deme from accumulated state and termination reason.
;;   $env: EDA environment context.
;;   $state: Current EDA state.
;;   $reason: Stop condition identifier.
;;   Returns: mkOptimizerResult containing resulting deme, best candidate, evals, and diagnostics.
(= (edaResult (mkEDAEnv $rep $id $schema $ctx $target $limits $deadline $cfg $fit $sample $space)
              (mkEDAState $p $a $s $calls $props $hits $invalids $rng $gens $stale) $reason)
   (let* (($ranked (edaRank $a))
          ($_diag (if (param diagnostics)
             (println! (PopulationDiagnostics (generations $gens) (population (List.length $p))
               (archive (List.length $a)) (unretainedProposals (max 0 (- $props (List.length $s))))
               (stagnation $stale))) ())))
     (mkOptimizerResult (mkDeme $rep (mkSInstSet (legacyScoredRows $ranked)) $id)
       (if (== $ranked ()) () (candidateInstance (car-atom $ranked))) $calls $reason
       (mkOptimizerDiag $props $hits $invalids 0) $rng)))

;; A proposal is already canonical. One-at-a-time evaluation stops exactly on
;; a raw target and counts only new scorer calls, never archive/merge work.
;; `seen` tracks canonical genotypes even when evaluation is invalid, preventing
;; repeated work; only valid rows enter the archive, while cache-hit accounting
;; remains separate from actual scorer-call accounting.
;; Evaluates a candidate proposal against the problem context, skipping duplicates and tracking stats.
;;   $env: EDA environment context.
;;   $row: Proposed candidate row.
;;   $state: Current EDA state.
;;   Returns: Updated EDA state with new evaluation counts, cache hits, and archive additions.
(= (edaEvaluate $env $row
                 (mkEDAState $p $a $seen $calls $props $hits $invalids $rng $gens $stale))
   (let* (((mkEDAEnv $rep $id $schema $ctx $target $limits $deadline $cfg $fit $sample $space) $env)
          ($instance (candidateInstance $row))
          ($nextProps (+ $props 1)))
     (if (continContains $instance $seen)
         (mkEDAState $p $a $seen $calls $nextProps $hits $invalids $rng $gens $stale)
         (let* (($batch (evaluateCandidateBatchUntil ($row) $rep $id $ctx
                          (optimizerRemaining (limitsMaxEvals $limits) $calls)
                          materializeCandidateForContext scoreMaterializedCandidate $deadline))
                ($done (batchEvaluated $batch))
                ($valid (filter-atom $done $v (candidateIsValid $v))))
           (mkEDAState $p (List.concat $a $valid)
             (if (== $done ()) $seen (cons $instance $seen))
             (+ $calls (batchActualEvaluations $batch)) $nextProps (+ $hits (batchCacheHits $batch))
             (+ $invalids (- (List.length $done) (List.length $valid))) $rng $gens $stale)))))

;; Extracts the genotype instance payload from an evaluated candidate or scored instance row.
;;   $row: Candidate record (mkEvaluatedCandidate or mkSInst).
;;   Returns: Genotype mkInst payload.
(= (edaInputInstance $row)
   (case $row (((mkEvaluatedCandidate $inst $tree $score $status) $inst)
              ((mkSInst (mkPair $inst $score)) $inst))))

;; Revalidate incoming genotypes and obtain scores through the run cache.
;; Legacy attached scores are deliberately not trusted across contexts.
;; Evaluates and canonicalizes initial and incoming deme seed instances into the archive.
;;   $env: EDA environment context.
;;   $instances: List of initial genotype instances to ingest.
;;   $state: Current EDA state.
;;   Returns: Updated EDA state with evaluated seed rows.
(= (edaInitialRows $env $instances $state)
   (if (not (== (edaResourceStop $env $state) ())) $state
       (case $instances
         ((() $state)
          ((cons $inst $rest)
           (let (mkEDAEnv $rep $id $schema $ctx $target $limits $deadline $cfg $fit $sample $space) $env
             (case (canonicalizeInstance $schema $inst)
               (((mkCEvalError $reason) (Error $inst $reason))
                ($canonical (edaInitialRows $env $rest
                  (edaEvaluate $env (mkEvaluatedCandidate $canonical () () candidatePending) $state)))))))))))

;; Refill stops after a bounded number of draws even for duplicate-only,
;; all-invalid or phenotype-collapsed searches. Exploration uses the legal prior.
;; Sampling from the prior is also used before a model is fitted. The wanted
;; count is an archive threshold, so invalid and duplicate proposals consume
;; attempts but do not falsely increase the number of available individuals.
;; Refills population with candidate samples drawn from the model or legal prior up to target count.
;;   $env: EDA environment context.
;;   $model: Probabilistic model (or empty list for uniform sampling).
;;   $wanted: Target cumulative archive count.
;;   $attempts: Maximum refill attempts allowed before aborting.
;;   $state: Current EDA state.
;;   Returns: Updated EDA state with newly sampled and evaluated candidates.
(= (edaFill $env $model $wanted $attempts $state)
   (if (or (<= $attempts 0) (>= (List.length (edaArchive $state)) $wanted)) $state
       (if (not (== (edaResourceStop $env $state) ())) $state
           (let* (((mkEDAEnv $rep $id $schema $ctx $target $limits $deadline
                             (mkEDAConfig $pop $sel $offs $tour $alpha $explore $refill $stagnation) $fit $sample $space) $env)
                  ((mkEDAState $p $a $s $c $n $h $i $rng $g $z) $state)
                  ((mkLegalSample $inst $end)
                    (if (== $model ()) (sampleLegalInstance $schema $rng)
                        (let ($unit $next) (optimizerRandomUnit $rng)
                          (if (< $unit $explore) (sampleLegalInstance $schema $next) ($sample $schema $model $next)))))
                  ($advanced (mkEDAState $p $a $s $c $n $h $i $end $g $z))
                  ($evaluated (edaEvaluate $env (mkEvaluatedCandidate $inst () () candidatePending) $advanced)))
             (edaFill $env $model $wanted (- $attempts 1) $evaluated)))))

;; Fit callbacks retain the Step 9 three-argument interface. BOA additionally
;; receives the optimizer deadline; both models report fitting wall time.
;; Wraps model fitting with execution timing and diagnostic emission.
;;   $fit: Model fitting function callback (univariate, BOA, or hBOA).
;;   $schema: Problem field schema.
;;   $selected: List of selected candidate rows.
;;   $alpha: Dirichlet pseudocount.
;;   $deadline: Cutoff timestamp.
;;   Returns: Fitted probabilistic model.
(= (edaFitTimed $fit $schema $selected $alpha $deadline)
   (let* (($started (candidateNow))
          ($model (if (or (== $fit boaFitConfigured) (== $fit hboaFitConfigured)) ($fit $schema $selected $alpha $deadline)
                      ($fit $schema $selected $alpha)))
          ($elapsed (- (candidateNow) $started))
          ($_diag (if (param diagnostics)
            (case $model
              (((mkBOAModel $nodes $order $a (mkBOAFitStats $seconds $edges $parameters $cells $iterations $scores $hits $reason))
                (println! (ModelFitDiagnostics (algorithm boa) (seconds $elapsed)
                  (learnedEdges $edges) (parameters $parameters) (tableCells $cells)
                  (iterations $iterations) (localFits $scores) (scoreCacheHits $hits) (stop $reason))))
               ((mkHBOAModel $hn $ho $ha (mkHFitStats $hs $he $hp $ht $hl $hi $hc $hr))
                (println! (ModelFitDiagnostics (algorithm hboa) (seconds $elapsed)
                  (learnedEdges $he) (parameters $hp) (treeNodes $ht) (leaves $hl)
                  (iterations $hi) (localFits $hc) (scoreCacheHits 0) (stop $hr))))
               ($other (println! (ModelFitDiagnostics (algorithm univariate) (seconds $elapsed)))))) ())))
     $model))

;; Extracts the model parameter count from a fitted model record.
;;   $model: Fitted probabilistic model (BOA, hBOA, or univariate).
;;   Returns: Number of free parameters in the model.
(= (edaModelSize $model)
   (case $model
     (((mkBOAModel $nodes $order $alpha (mkBOAFitStats $seconds $edges $parameters $cells $iterations $scores $hits $reason)) $parameters)
      ((mkHBOAModel $hn $ho $ha (mkHFitStats $hs $he $hp $ht $hl $hi $hc $hr)) $hp)
      ($other 0))))

;; Attaches learned model parameter size to optimizer diagnostics before returning result.
;;   $env: EDA environment context.
;;   $state: Current EDA state.
;;   $reason: Stop condition identifier.
;;   $size: Model parameter size.
;;   Returns: mkOptimizerResult with model size in diagnostics.
(= (edaSizedResult $env $state $reason $size)
   (let (mkOptimizerResult $deme $best $calls $stop (mkOptimizerDiag $props $hits $invalids $old) $rng)
        (edaResult $env $state $reason)
     (mkOptimizerResult $deme $best $calls $stop (mkOptimizerDiag $props $hits $invalids $size) $rng)))

;; Helper entry point for one generational step with default initial model size 0.
;;   $env: EDA environment context.
;;   $state: Current EDA state.
;;   Returns: Result of edaGenerationSized.
(= (edaGeneration $env $state) (edaGenerationSized $env $state 0))

;; Executes the generational cycle: selection, model fitting, offspring sampling, evaluation, and replacement.
;; The model is fitted from tournament-selected rows, then refill proposes only
;; enough new archive entries to meet the offspring target. Replacement consumes
;; those newly archived rows; the full archive remains available for final output.
;;   $env: EDA environment context.
;;   $state: Current EDA state.
;;   $modelSize: Maximum model parameter size observed so far.
;;   Returns: mkOptimizerResult when terminated, or recurses to next generation.
(= (edaGenerationSized $env $state $modelSize)
   (let* (((mkEDAEnv $rep $id $schema $ctx $target $limits $deadline
                      (mkEDAConfig $pop $sel $offs $tour $alpha $explore $refill $stagnation) $fit $sample $space) $env)
          ((mkEDAState $p $a $s $calls $props $hits $invalids $rng $gens $stale) $state)
          ($resource (edaResourceStop $env $state))
          ($stop (if (not (== $resource ())) $resource
                    (if (== $p ()) stopAllInvalid
                      (if (optimizerLimitReached (limitsMaxGenerations $limits) $gens) stopGenerationsExhausted
                        (if (>= $stale $stagnation) stopStagnation ()))))))
     (if (not (== $stop ())) (edaSizedResult $env $state $stop $modelSize)
         (let* ((($selected $selectedRng) (edaSelect $p $sel $tour $rng))
                ($model (edaFitTimed $fit $schema $selected $alpha $deadline))
                ($ready (mkEDAState $p $a $s $calls $props $hits $invalids $selectedRng $gens $stale))
                ((mkEDAState $unusedP $newA $newS $newC $newN $newH $newI $newR $unusedG $unusedZ)
                  (edaFill $env $model (+ (List.length $a) $offs) $refill $ready))
                (($newP $replaceRng) (edaReplacementStep $sample $p (List.drop (List.length $a) $newA) $pop $newR))
                ($improved (edaBetter (car-atom $newP) (car-atom $p)))
                ($newState (mkEDAState $newP $newA $newS $newC $newN $newH $newI $replaceRng
                             (+ $gens 1) (if $improved 0 (+ $stale 1)))))
           (edaGenerationSized $env $newState (max $modelSize (edaModelSize $model)))))))

;; Main engine entry point for EDA-based optimizers (univariate, BOA, hBOA).
;; Validates the shared contracts, canonicalizes/re-scores supplied seeds in the
;; current context, builds an initial legal population, then enters the same
;; generation loop used by every EDA model.
;;   $deme: Input deme containing representation and scored candidates.
;;   $context: Scoring context.
;;   $initial: Seed instance.
;;   $limits: Resource limits.
;;   $rng: Random number generator state.
;;   $cfg: EDA configuration parameters.
;;   $fit: Model fitting callback.
;;   $sample: Model sampling callback.
;;   Returns: mkOptimizerResult containing optimized deme, best instance, and diagnostics.
(= (edaStart $deme $context $initial $limits $rng $cfg $fit $sample)
   (if (not (and (optimizerLimitsValid $limits) (optimizerRngValid $rng)))
       (Error $limits "Invalid EDA limits or RNG")
       (if (not (and (edaConfigValid $cfg) (edaReplacementValid))) (Error $cfg "Invalid EDA configuration or replacement policy")
           (let* (((mkDeme $rep (mkSInstSet $input) $id) $deme)
                  (($ctx $target) (edaContext $context))
                  ($schema (edaSchema $rep $ctx)))
             (if (not (fieldSchemaValid $schema)) (Error $schema "Invalid EDA schema")
                 (if (not (legalSamplingFieldsValid (schemaFields $schema))) (Error $schema "Unsupported EDA cardinality")
                   (let* (($seconds (limitsTimeLimitSec $limits))
                          ($deadline (if (< $seconds 0) -1 (+ (candidateNow) $seconds)))
                          ($env (mkEDAEnv $rep $id $schema $ctx $target $limits $deadline $cfg $fit $sample
                                  (edaSpace (schemaFields $schema) 1)))
                          ($empty (mkEDAState () () () 0 0 0 0 $rng 0 0))
                          ($early (edaResourceStop $env $empty)))
                     (if (not (== $early ())) (edaResult $env $empty $early)
                       (if (== (limitsMaxGenerations $limits) 0) (edaResult $env $empty stopGenerationsExhausted)
                         (let* (((mkEDAConfig $pop $sel $offs $tour $alpha $explore $refill $stagnation) $cfg)
                                ($seeded (edaInitialRows $env (cons $initial (map-atom $input $row (edaInputInstance $row))) $empty)))
                           (case $seeded
                             (((Error $value $reason) $seeded)
                              ($validSeeded
                               (let (mkEDAState $p $a $s $c $n $h $i $r $g $z)
                                    (edaFill $env () $pop $refill $validSeeded)
                                 (edaGeneration $env (mkEDAState (List.takeN $pop (edaRank $a)) $a $s $c $n $h $i $r 1 0))))))))))))))))
