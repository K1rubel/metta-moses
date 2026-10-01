;; Shared counted evaluation boundary for HC and future population optimizers.
;; Dependencies (loaded by the application): cacheSpace, representation, list
;; helpers, optimizer-contract and the domain scorers. Like the other shared
;; modules, imports belong to entrypoints (PeTTa resolves from the entrypoint).
;; No hill-climbing state is read here.

;; Scorers return a composite score with EXPLICIT status. A valid score equal
;; to worstCscore remains valid. Numerical evaluators may return mkCEvalError;
;; decoder callbacks may return mkCandidateDecodeError or mkCEvalError.
(: CandidateScore Type)
(: mkCandidateScore (-> Atom CandidateStatus CandidateScore))

;; A batch is an evaluated prefix plus an untouched pending suffix. At the
;; first cache miss with no remaining allowance, stop; do not skip that row to
;; search later rows for hits. -1 means unlimited; zero forbids scorer calls.
;; The allowance is an integer >= 0 or -1, as specified by OptimizerLimits.
;; decodeFailures counts NEW failed decodes (zero scorer calls); cached decode
;; failures count as hits instead. Scorer failures count as one invocation.
(: CandidateBatch Type)
(: mkCandidateBatch (-> Atom Atom Number Number Number CandidateBatch))
(= (batchEvaluated (mkCandidateBatch $done $pending $calls $hits $decodes)) $done)
(= (batchPending (mkCandidateBatch $done $pending $calls $hits $decodes)) $pending)
(= (batchActualEvaluations (mkCandidateBatch $done $pending $calls $hits $decodes)) $calls)
(= (batchCacheHits (mkCandidateBatch $done $pending $calls $hits $decodes)) $hits)
(= (batchDecodeFailures (mkCandidateBatch $done $pending $calls $hits $decodes)) $decodes)

;; Single case dispatch avoids overlapping action/fallback rewrite clauses.
(= (candidateCallDecoder $decoder $rep $inst) ($decoder $rep $inst))
(= (materializeCandidateForContext $rep $id $inst $context)
   (case $context
     (((mkContinCtx $table $error $ratio $mode $target)
        ;; Validate/decode/reduce before phenotype caching; never Boolean rules.
        (candidateCallDecoder finalizeContinCandidate $rep $inst))
      ((mkActionScoreContext $ratio $trials)
        (getCandidateHelper $inst (getRepTree $rep)))
      ((mkActionCtx $trials $ratio $target)
        (getCandidateHelper $inst (getRepTree $rep)))
      ($other (getCandidate $rep $id $inst)))))

;; Target is a stopping condition, not part of fitness. Include the configured
;; action fitness function, as the lower-level action cache already does.
(= (candidateEvaluationContext $context)
   (case $context
     (((mkActionScoreContext $ratio $trials)
        (mkActionEvaluationKey (param fitness) $trials $ratio))
      ((mkActionCtx $trials $ratio $target)
        (mkActionEvaluationKey (param fitness) $trials $ratio))
      ($other $context))))

;; Boolean subtree memoization is table-scoped. The complete-program cache can
;; retain several contexts; reset the lower cache when scoring a different table.
!(bind! &candidateBooleanTable (new-state ()))
(= (prepareCandidateBooleanTable $table)
   (if (== (get-state &candidateBooleanTable) $table)
       True
       (let* (($_reset (resetSubtreeCache))
              ($_table (change-state! &candidateBooleanTable $table))) True)))

(= (candidateCallScorer $scorer $tree $context) ($scorer $tree $context))
(= (scoreMaterializedCandidate $tree $context)
   (case $context
     (((mkContinCtx $table $error $ratio $mode $target)
        ;; Runtime dispatch lets Boolean/action-only entrypoints omit the
        ;; continuous modules. Continuous entrypoints load eval then score.
        (candidateCallScorer scoreContinCandidate $tree $context))
      (((mkITable $rows $labels) $ratio)
        (let* (($_table (prepareCandidateBooleanTable (mkITable $rows $labels)))
               ($bs (scoreTree (mkITable $rows $labels) $tree &bscoreCache)))
          (if-error $bs
            (mkCandidateScore (worstCscore) (candidateInvalid "Boolean evaluation failed"))
            (mkCandidateScore (getCscore $tree $ratio $bs) candidateValid))))
      ((mkActionScoreContext $ratio $trials)
        (scoreMaterializedActionCandidate $tree $trials $ratio))
      ((mkActionCtx $trials $ratio $target)
        (scoreMaterializedActionCandidate $tree $trials $ratio))
      ($other (mkCEvalError "Unsupported scoring context")))))

(= (scoreMaterializedActionCandidate $tree $trials $ratio)
   (if (== $tree (mkTree (mkNode and_seq) ()))
       (mkCandidateScore (mkCscore -4 0 $ratio 0 -4) candidateValid)
       (let $bs (scoreActionTree $tree $trials &actionScoreCache)
         (if-error $bs
           (mkCandidateScore (worstCscore) (candidateInvalid "Action evaluation failed"))
           (mkCandidateScore (actionCscoreFromBscore $tree $ratio $bs) candidateValid)))))

;; Compatibility projection for callers that only want the composite score.
(= (scoreMaterializedTree $tree $context)
   (let (mkCandidateScore $score $status)
        (normalizeCandidateScore (collapse (scoreMaterializedCandidate $tree $context)))
     $score))

;; A callback must produce exactly one tagged score, or a tagged failure. Empty,
;; ambiguous and malformed returns are evaluated failures, not pending rows.
(= (normalizeCandidateScore $results)
   (case $results
     ((((mkCandidateScore $score candidateValid)) (mkCandidateScore $score candidateValid))
      (((mkCandidateScore $score (candidateInvalid $reason)))
        (mkCandidateScore (worstCscore) (candidateInvalid $reason)))
      (((mkCEvalError $reason)) (mkCandidateScore (worstCscore) (candidateInvalid $reason)))
      ($other (mkCandidateScore (worstCscore) (candidateInvalid "Scorer did not return one tagged result"))))))

(= (normalizeCandidateTree $results)
   (case $results
     ((((mkTree $node $children)) (mkTree $node $children))
      (((mkCandidateDecodeError $reason)) (mkCandidateDecodeError $reason))
      (((mkCEvalError $reason)) (mkCandidateDecodeError $reason))
      ($other (mkCandidateDecodeError "Decoder did not return one tree")))))

;; Explicitly evaluated rows are trusted ONLY in the supplied context. Seed
;; them before traversal so even a later attached row can satisfy an early hit.
(= (seedEvaluatedCandidates () $context) True)
(= (seedEvaluatedCandidates (cons $row $rest) $context)
   (let $_seed
        (if (and (candidateIsEvaluated $row) (not (== (candidateTree $row) ())))
            (cacheCandidateEvaluation $context (candidateTree $row)
              (mkCandidateScore (candidateScore $row) (candidateStatus $row)))
            True)
     (seedEvaluatedCandidates $rest $context)))

(= (evaluateCandidateBatch $rows $rep $id $context $allowance)
   (let $prepared (case $context
                    (((mkContinCtx $table $error $ratio $mode $target)
                      (candidateCallDecoder canonicalizeContinCandidateRows $rep $rows))
                     ($otherContext $rows)))
     (evaluateCandidateBatchWith $prepared $rep $id $context $allowance
       materializeCandidateForContext scoreMaterializedCandidate)))

;; Callback variant is also the extension seam for new domains. The context
;; must identify all scoring inputs/configuration; callbacks are deterministic
;; within that context. Materializer takes rep/id/instance/context, scorer takes
;; tree/context. Input vectors must already be legal and canonical.
(= (evaluateCandidateBatchWith $rows $rep $id $context $allowance $materializer $scorer)
   (evaluateCandidateBatchUntil $rows $rep $id $context $allowance $materializer $scorer -1))

;; Cooperative deadline: check before each scorer call; do not preempt a scorer
;; already running. No clock read for unlimited calls.
(= (candidateNow) (py-call (time.monotonic)))
(= (candidateDeadlineReached $deadline)
   (case $deadline
     (((mkCandidateDeadline $clock $until) (>= ($clock) $until))
      ($numeric (if (< $deadline 0) False (>= (candidateNow) $deadline))))))
(= (evaluateCandidateBatchUntil $rows $rep $id $context $allowance $materializer $scorer $deadline)
   (let* (($key (candidateEvaluationContext $context))
          ($_seed (seedEvaluatedCandidates $rows $key)))
     (evaluateCandidateRows $rows $rep $id $context $key $allowance $materializer $scorer $deadline)))

(= (evaluateCandidateRows () $rep $id $context $key $left $materializer $scorer $deadline)
   (mkCandidateBatch () () 0 0 0))
(= (evaluateCandidateRows (cons $row $rest) $rep $id $context $key $left $materializer $scorer $deadline)
   (if (candidateIsEvaluated $row)
       (prependCandidateBatch $row 0 0 0
         (evaluateCandidateRows $rest $rep $id $context $key $left $materializer $scorer $deadline))
       (let* (($inst (candidateInstance $row))
              ($decodeHit (cachedCandidateDecodeFailure $key $rep $id $inst)))
         (if (not (== $decodeHit ()))
             (prependCandidateBatch (mkEvaluatedCandidate $inst () (worstCscore) $decodeHit) 0 1 0
               (evaluateCandidateRows $rest $rep $id $context $key $left $materializer $scorer $deadline))
             (let $tree (normalizeCandidateTree (collapse ($materializer $rep $id $inst $context)))
               (case $tree
                 (((mkCandidateDecodeError $reason)
                    (let $_cache (cacheCandidateDecodeFailure $key $rep $id $inst $reason)
                      (prependCandidateBatch
                        (mkEvaluatedCandidate $inst () (worstCscore) (candidateInvalid $reason)) 0 0 1
                        (evaluateCandidateRows $rest $rep $id $context $key $left $materializer $scorer $deadline))))
                  ($validTree
                    (let $cached (cachedCandidateEvaluation $key $tree)
                      (if (or (candidateDeadlineReached $deadline) (and (== $cached ()) (== $left 0)))
                          (mkCandidateBatch () (cons $row $rest) 0 0 0)
                          (evaluateMaterializedCandidate $row $rest $tree $cached
                            $rep $id $context $key $left $materializer $scorer $deadline)))))))))))

(= (evaluateMaterializedCandidate $row $rest $tree $cached $rep $id $context $key $left $materializer $scorer $deadline)
   (let* (($miss (== $cached ()))
          ($result (if $miss (normalizeCandidateScore (collapse ($scorer $tree $context))) $cached))
          ((mkCandidateScore $score $status) $result)
          ($_cache (cacheCandidateEvaluation $key $tree $result))
          ($calls (if $miss 1 0))
          ($nextLeft (if (< $left 0) -1 (- $left $calls))))
     (prependCandidateBatch
       (mkEvaluatedCandidate (candidateInstance $row) $tree $score $status)
       $calls (if $miss 0 1) 0
       (evaluateCandidateRows $rest $rep $id $context $key $nextLeft $materializer $scorer $deadline))))

(= (prependCandidateBatch $row $calls $hits $decodes
      (mkCandidateBatch $done $pending $restCalls $restHits $restDecodes))
   (mkCandidateBatch (cons $row $done) $pending
     (+ $calls $restCalls) (+ $hits $restHits) (+ $decodes $restDecodes)))

;; Legacy HC adapters. Only this old input boundary infers pending from the
;; sentinel; the shared service never does. Cached invalid rows retain status
;; even when projected back to the old score-only population representation.
(= (scoreNeedsEvaluation $score) (== $score (worstCscore)))
(= (legacyCandidateRows () $rep $id $context) ())
(= (legacyCandidateRows (cons (mkSInst (mkPair $inst $score)) $rest) $rep $id $context)
   (cons
     (if (scoreNeedsEvaluation $score)
         (mkEvaluatedCandidate $inst () () candidatePending)
         (mkEvaluatedCandidate $inst (materializeCandidateForContext $rep $id $inst $context) $score candidateValid))
     (legacyCandidateRows $rest $rep $id $context)))
(= (legacyScoredRows ()) ())
(= (legacyScoredRows (cons $row $rest))
   (cons (mkSInst (mkPair (candidateInstance $row) (candidateScore $row))) (legacyScoredRows $rest)))

(= (scoreNewInstancesCounted $instances $rep $id $context)
   (let $batch (evaluateCandidateBatch (legacyCandidateRows $instances $rep $id $context) $rep $id $context -1)
     ((legacyScoredRows (batchEvaluated $batch)) (batchActualEvaluations $batch))))
(= (transformIncremental (mkSInstSet $instances) $rep $id $context)
   (let ($scored $count) (scoreNewInstancesCounted $instances $rep $id $context)
     ((mkSInstSet $scored) $count)))

;; Preserve the already-scored prefix byte-for-byte; only evaluate the suffix.
;; HC cannot train/select pending rows, so the bounded adapter omits them. The
;; full shared batch API above retains them for resumable population evaluation.
(= (transformAppendedIncremental $set $prefixSize $rep $id $context)
   (transformAppendedIncrementalBounded $set $prefixSize $rep $id $context -1))
(= (transformAppendedIncrementalBounded (mkSInstSet $instances) $prefixSize $rep $id $context $left)
   (let* (($prefix (List.takeN $prefixSize $instances))
          ($suffix (List.drop $prefixSize $instances))
          ($batch (evaluateCandidateBatch (legacyCandidateRows $suffix $rep $id $context) $rep $id $context $left)))
     ((mkSInstSet (List.concat $prefix (legacyScoredRows (batchEvaluated $batch))))
      (batchActualEvaluations $batch))))
(= (seedAttachedCandidateScores (mkDeme $rep (mkSInstSet $instances) $id) $context)
   (seedEvaluatedCandidates (legacyCandidateRows $instances $rep $id $context)
     (candidateEvaluationContext $context)))
