;; Shared optimizer boundary. Import after optimizer-contract and candidate-evaluation.
;; Explicit, portable Park-Miller RNG (multiplier 48271, modulus 2147483647).
;; State is an integer in [1, 2147483646]. No Python/global RNG is consumed.
(= (optimizerRngFromSeed $seed) (+ 1 (% (+ (% $seed 2147483646) 2147483646) 2147483646)))
(= (optimizerRngNext $state) (% (* 48271 $state) 2147483647))
;; Half-open [0,1) draw for categorical weights and exploration decisions.
(= (optimizerRandomUnit $state)
   (let $next (optimizerRngNext $state) ((/ (- $next 1) 2147483646.0) $next)))
(= (optimizerRandomInt $low $high $state)
   (let $width (+ 1 (- $high $low))
     (if (or (<= $width 0) (> $width 2147483646))
         (Error ($low $high) "Invalid optimizer RNG range")
         (optimizerRandomIntDraw $low $high $state))))
(= (optimizerRandomIntDraw $low $high $state)
   (let* (($width (+ 1 (- $high $low)))
          ($next (optimizerRngNext $state))
          ($value (- $next 1))
          ($ceiling (- 2147483646 (% 2147483646 $width))))
     (if (< $value $ceiling)
         ((+ $low (% $value $width)) $next)
         (optimizerRandomIntDraw $low $high $next))))

(= (optimizerFiniteNumber $x)
   (if (== (get-type $x) Number)
       (== (py-call (builtins.int (py-call (math.isfinite $x)))) 1)
       False))
(= (optimizerCountLimitValid $x)
   (if (optimizerFiniteNumber $x)
       (and (>= $x -1) (== $x (floor-math $x))) False))
(= (optimizerLimitsValid $limits)
   (case $limits
     (((mkOptimizerLimits $evals $props $gens $time)
       (and (optimizerCountLimitValid $evals)
         (and (optimizerCountLimitValid $props)
           (and (optimizerCountLimitValid $gens)
             (if (optimizerFiniteNumber $time) (or (== $time -1) (>= $time 0)) False)))))
      ($other False))))
(= (optimizerRngValid $rng)
   (if (optimizerFiniteNumber $rng)
       (and (== $rng (floor-math $rng)) (and (>= $rng 1) (< $rng 2147483647))) 
       False))
(= (optimizerLimitReached $limit $used) (and (>= $limit 0) (>= $used $limit)))
(= (optimizerRemaining $limit $used) (if (< $limit 0) -1 (max 0 (- $limit $used))))
(= (optimizerCap $requested $remaining) (if (< $remaining 0) $requested (min $requested $remaining)))

;; Algorithm symbol is a function implementing the six-argument common contract.
;; Legacy hc/hillClimbing names are accepted at this boundary, not by the outer
;; loop. Unsupported CLI names are still rejected by optimizer-for.
(= (optimizeDeme $deme $context $initial $limits $rng (mkOptimizerConfig $algorithm))
   (if (not (optimizerLimitsValid $limits))
       (Error $limits "Invalid optimizer limits")
       (if (not (optimizerRngValid $rng))
           (Error $rng "Invalid optimizer RNG state")
           (let $runner (case $algorithm ((hc hillClimbingOptimizer) (hillClimbing hillClimbingOptimizer)
                                         (univariate univariateOptimizer) (boa boaOptimizer) (hboa hboaOptimizer) ($otherAlgorithm $algorithm)))
             (case (collapse ($runner $deme $context $initial $limits $rng (mkOptimizerConfig $algorithm)))
               ((((mkOptimizerResult $out $best $calls $reason $diag $next))
                 (mkOptimizerResult $out $best $calls $reason $diag $next))
                ($badResults (Error $badResults "Optimizer did not return one common result"))))))))

;; Run-level ownership: a stream is passed from one local optimizer result to
;; the next. The HC compatibility scope below is separate and always restored.
!(bind! &optimizerRunRng (new-state 1))
(= (configuredOptimizerLimits $evals)
   (mkOptimizerLimits $evals (param optimizerMaxProposals)
     (param optimizerMaxGenerations) (param optimizerTimeLimitSec)))

;; Stable penalized ordering; exact ties select the latest row, matching the
;; legacy HC fold's argument order. The caller
;; supplies only valid rows, so finite worst-score sentinels never win by accident.
(= (optimizerBetterRow $old $new)
   (if (== $old ()) $new
       (let* (($a (getSInstScore $old)) ($b (getSInstScore $new)))
         (if (or (> (getPenScore $b) (getPenScore $a))
                 (and (== (getPenScore $b) (getPenScore $a)) (<= (getComp $b) (getComp $a))))
             $new $old))))
(= (optimizerBestRow $rows) (foldl-atom $rows () $best $row (optimizerBetterRow $best $row)))

;; Scoped bridge for the legacy recursive HC engine. New optimizers need not
;; use these cells: limits/RNG/results remain explicit at their public boundary.
!(bind! &hcActive (new-state False))
!(bind! &hcLimits (new-state (mkOptimizerLimits -1 -1 -1 -1)))
!(bind! &hcRng (new-state 1))
!(bind! &hcDeadline (new-state -1))
!(bind! &hcProposals (new-state 0))
!(bind! &hcGenerations (new-state 0))
!(bind! &hcHits (new-state 0))
!(bind! &hcInvalids (new-state 0))
!(bind! &hcStop (new-state ()))
(= (hcRecordProposals $n)
   (if (get-state &hcActive) (change-state! &hcProposals (+ (get-state &hcProposals) $n)) True))
(= (hcProposalAllowance $requested)
   (if (get-state &hcActive)
       (optimizerCap $requested (optimizerRemaining (limitsMaxProposals (get-state &hcLimits)) (get-state &hcProposals)))
       $requested))
(= (hcRecordBatch $batch)
   (let* (($_hits (change-state! &hcHits (+ (get-state &hcHits) (batchCacheHits $batch))))
          ($_invalids (change-state! &hcInvalids
             (+ (get-state &hcInvalids)
                (List.length (filter-atom (batchEvaluated $batch) $row (not (candidateIsValid $row)))))))) True))
(= (hcResourceStop $evals)
   (let $limits (get-state &hcLimits)
     (if (candidateDeadlineReached (get-state &hcDeadline)) stopTimeExhausted
       (if (optimizerLimitReached (limitsMaxEvals $limits) $evals) stopBudgetExhausted
         (if (optimizerLimitReached (limitsMaxProposals $limits) (get-state &hcProposals)) stopProposalsExhausted
           (if (optimizerLimitReached (limitsMaxGenerations $limits) (get-state &hcGenerations)) stopGenerationsExhausted ()))))))
