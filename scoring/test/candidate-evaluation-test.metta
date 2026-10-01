!(import! &self ../../utilities/general-helpers)
!(import! &self ../../utilities/list-methods)
!(import! &self ../../utilities/tree)
!(import! &self ../../parameters/registry)
!(import! &self ../../parameters/defaults)
!(import! &self ../cacheSpace)
!(import! &self ../boolean-ops)
!(import! &self ../fitness)
!(import! &self ../bscore)
!(import! &self ../cscore)
!(import! &self ../action-registry)
!(import! &self ../action-score)
!(import! &self ../../optimization/optimizer-contract)
!(import! &self ../candidate-evaluation)

;; Instrument both stages so counts are checked against real side effects, not
;; only the batch's self-reported counters. Different vectors 0/1 decode to A.
!(bind! &fixtureCalls (new-state 0))
!(bind! &fixtureDecodes (new-state 0))
(= (resetFixture)
   (let* (($_cache (resetCandidateScoreCache))
          ($_calls (change-state! &fixtureCalls 0))
          ($_decodes (change-state! &fixtureDecodes 0))) True))
(= (fixtureMaterialize $rep $id (mkInst ($n)) $context)
   (let $_count (change-state! &fixtureDecodes (+ 1 (get-state &fixtureDecodes)))
     (case $n
       ((0 (mkTree (mkNode A) ()))
        (1 (mkTree (mkNode A) ()))
        (2 (mkTree (mkNode B) ()))
        (3 (mkTree (mkNode bad) ()))
        (4 (mkCandidateDecodeError "Bad vector"))
        (5 (mkTree (mkNode sentinel) ()))
        (6 (mkTree (mkNode malformed) ()))
        (7 (mkTree (mkNode emptyResult) ()))
        (8 (mkTree (mkNode ambiguous) ()))
        (9 (mkTree (mkNode belowSentinel) ()))))))
(= (fixtureScore (mkTree (mkNode $name) ()) $context)
   (let $_count (change-state! &fixtureCalls (+ 1 (get-state &fixtureCalls)))
     (case $name
       ((bad (mkCEvalError "Non-finite prediction"))
        (sentinel (mkCandidateScore (worstCscore) candidateValid))
        (belowSentinel (mkCandidateScore (mkCscore -1e101 0 0 0 -1e101) candidateValid))
        (malformed notAScore)
        (emptyResult (empty))
        (ambiguous (superpose ((mkCandidateScore (worstCscore) candidateValid)
                              (mkCandidateScore (worstCscore) candidateValid))))
        ($other (mkCandidateScore (mkCscore -2 1 0 0 -2) candidateValid))))))
(= (pending $n) (mkEvaluatedCandidate (mkInst ($n)) () () candidatePending))
(= (fixtureBatch $rows $budget)
   (evaluateCandidateBatchWith $rows fixtureRep fixtureId fixtureContext $budget fixtureMaterialize fixtureScore))
(= (batchSummary $batch)
   ((List.length (batchEvaluated $batch)) (List.length (batchPending $batch))
    (batchActualEvaluations $batch) (batchCacheHits $batch) (batchDecodeFailures $batch)))

;; Empty and zero-budget calls; no hidden scorer invocation.
!(resetFixture)
!(assertEqual (batchSummary (fixtureBatch () 0)) (0 0 0 0 0))
!(change-state! &zero (fixtureBatch ((pending 0) (pending 2)) 0))
!(assertEqual (batchSummary (get-state &zero)) (0 2 0 0 0))
!(assertEqual (batchPending (get-state &zero)) ((pending 0) (pending 2)))
!(assertEqual (get-state &fixtureCalls) 0)

;; Budget=1: consume A, reuse A for another vector, stop BEFORE B. Resume
;; pending B with a fresh allowance without rescoring the completed prefix.
!(resetFixture)
!(change-state! &one (fixtureBatch ((pending 0) (pending 1) (pending 2)) 1))
!(assertEqual (batchSummary (get-state &one)) (2 1 1 1 0))
!(assertEqual (get-state &fixtureCalls) 1)
!(assertEqual (List.map candidateInstance (batchEvaluated (get-state &one))) ((mkInst (0)) (mkInst (1))))
!(assertEqual (batchPending (get-state &one)) ((pending 2)))
!(assertEqual (batchSummary (fixtureBatch (batchPending (get-state &one)) 1)) (1 0 1 0 0))
!(assertEqual (get-state &fixtureCalls) 2)
!(assertEqual (batchSummary (fixtureBatch ((pending 0) (pending 2)) 0)) (2 0 0 2 0))
!(assertEqual (get-state &fixtureCalls) 2)

;; Unlimited mode and independent scoring contexts.
;; A zero-allowance miss stops the batch even if a later row is cached.
!(assertEqual (batchSummary (fixtureBatch ((pending 3) (pending 0)) 0)) (0 2 0 0 0))
!(assertEqual (get-state &fixtureCalls) 2)
!(resetFixture)
!(assertEqual (batchSummary (fixtureBatch ((pending 0) (pending 1) (pending 2)) -1)) (3 0 2 1 0))
!(assertEqual (batchSummary
   (evaluateCandidateBatchWith ((pending 0)) fixtureRep fixtureId otherContext 1 fixtureMaterialize fixtureScore))
   (1 0 1 0 0))
!(assertEqual (get-state &fixtureCalls) 3)

;; Failed scorer calls cost one, preserve a reason, and are cached across
;; batches even though their score equals the legacy pending sentinel.
!(resetFixture)
!(change-state! &invalid (fixtureBatch ((pending 3) (pending 3)) 1))
!(assertEqual (batchSummary (get-state &invalid)) (2 0 1 1 0))
!(assertEqual (candidateStatus (List.head (batchEvaluated (get-state &invalid)))) (candidateInvalid "Non-finite prediction"))
!(assertEqual (candidateScore (List.head (batchEvaluated (get-state &invalid)))) (worstCscore))
!(assertEqual (candidateIsEvaluated (List.head (batchEvaluated (get-state &invalid)))) True)
!(assertEqual (candidateIsValid (List.head (batchEvaluated (get-state &invalid)))) False)
!(assertEqual (batchSummary (fixtureBatch ((pending 3)) 0)) (1 0 0 1 0))
!(assertEqual (get-state &fixtureCalls) 1)
!(assertEqual (cachedCandidateScore fixtureContext (mkTree (mkNode bad) ())) (worstCscore))
!(assertEqual (cachedCandidateEvaluation fixtureContext (mkTree (mkNode bad) ()))
   (mkCandidateScore (worstCscore) (candidateInvalid "Non-finite prediction")))
!(assertEqual (batchSummary (fixtureBatch (batchEvaluated (get-state &invalid)) 0)) (2 0 0 0 0))
!(assertEqual (get-state &fixtureCalls) 1)
!(resetFixture)
!(assertEqual (batchSummary (fixtureBatch ((pending 3) (pending 2)) 1)) (1 1 1 0 0))
!(assertEqual (get-state &fixtureCalls) 1)

;; Valid scores equal to or below the sentinel MUST stay valid. Also trust an
;; explicitly evaluated row at budget=0 without materializing/scoring it.
!(resetFixture)
!(change-state! &validWorst (fixtureBatch ((pending 5) (pending 9)) 2))
!(assertEqual (List.map candidateIsValid (batchEvaluated (get-state &validWorst))) (True True))
!(assertEqual (batchSummary (fixtureBatch (batchEvaluated (get-state &validWorst)) 0)) (2 0 0 0 0))
!(assertEqual (get-state &fixtureCalls) 2)
!(assertEqual (get-state &fixtureDecodes) 2)
!(resetFixture)
!(assertEqual (batchSummary (fixtureBatch
   ((pending 5) (mkEvaluatedCandidate (mkInst (5)) (mkTree (mkNode sentinel) ()) (worstCscore) candidateValid)) 0))
   (2 0 0 1 0))
!(assertEqual (get-state &fixtureCalls) 0)

;; Decoder failures consume no scorer calls, and have a separate keyed cache.
!(resetFixture)
!(change-state! &decode (fixtureBatch ((pending 4) (pending 4)) 0))
!(assertEqual (batchSummary (get-state &decode)) (2 0 0 1 1))
!(assertEqual (candidateTree (List.head (batchEvaluated (get-state &decode)))) ())
!(assertEqual (candidateFailureReason (List.head (batchEvaluated (get-state &decode)))) "Bad vector")
!(assertEqual (get-state &fixtureCalls) 0)
!(assertEqual (get-state &fixtureDecodes) 1)
!(assertEqual (batchSummary
   (evaluateCandidateBatchWith ((pending 4)) anotherRep fixtureId fixtureContext 0 fixtureMaterialize fixtureScore))
   (1 0 0 0 1))
!(assertEqual (batchSummary
   (evaluateCandidateBatchWith ((pending 4)) fixtureRep anotherId fixtureContext 0 fixtureMaterialize fixtureScore))
   (1 0 0 0 1))
!(assertEqual (get-state &fixtureDecodes) 3)
!(assertEqual (resetCandidateScoreCache) True)
!(assertEqual (cachedCandidateDecodeFailure fixtureContext fixtureRep fixtureId (mkInst (4))) ())

;; Bad callback results are terminal failures and are not silently dropped.
!(resetFixture)
!(change-state! &badReturns (fixtureBatch ((pending 6) (pending 7) (pending 8)) 3))
!(assertEqual (batchSummary (get-state &badReturns)) (3 0 3 0 0))
!(assertEqual (List.map candidateIsEvaluated (batchEvaluated (get-state &badReturns))) (True True True))
!(assertEqual (List.map candidateIsValid (batchEvaluated (get-state &badReturns))) (False False False))
!(assertEqual (batchSummary (fixtureBatch ((pending 6) (pending 7) (pending 8)) 0)) (3 0 0 3 0))
!(assertEqual (get-state &fixtureCalls) 3)

;; Real domain scorers: Boolean contexts must not leak lower subtree-cache
;; values between tables. Action internal/public contexts share keys, but a
;; changed fitness function must not share complete candidate scores.
(= (booleanFixtureTree $rep $id $inst $context) (mkTree (mkNode A) ()))
(= (booleanTable1) (mkITable ((True True) (False False)) (A O)))
(= (booleanTable2) (mkITable ((False True) (True False)) (A O)))
!(resetFixture)
!(change-state! &bool1 (evaluateCandidateBatchWith ((pending 0)) rep id ((booleanTable1) 0) 1 booleanFixtureTree scoreMaterializedCandidate))
!(change-state! &bool2 (evaluateCandidateBatchWith ((pending 0)) rep id ((booleanTable2) 0) 1 booleanFixtureTree scoreMaterializedCandidate))
!(assertEqual (getScore (candidateScore (List.head (batchEvaluated (get-state &bool1))))) 0)
!(assertEqual (getScore (candidateScore (List.head (batchEvaluated (get-state &bool2))))) -2)
!(assertEqual (batchSummary (evaluateCandidateBatchWith ((pending 0)) rep id ((booleanTable1) 0) 0 booleanFixtureTree scoreMaterializedCandidate))
   (1 0 0 1 0))
(= (fixtureFitnessOne $exp $i) 1.0)
(= (fixtureFitnessTwo $exp $i) -1.0)
(= (actionFixtureTree $rep $id $inst $context) (mkTree (mkNode fixtureAction) ()))
!(set-param fitness fixtureFitnessOne)
!(change-state! &act1 (evaluateCandidateBatchWith ((pending 0)) rep id (mkActionScoreContext 0 2) 1 actionFixtureTree scoreMaterializedCandidate))
!(assertEqual (getScore (candidateScore (List.head (batchEvaluated (get-state &act1))))) 2.0)
!(assertEqual (batchSummary (evaluateCandidateBatchWith ((pending 0)) rep id (mkActionCtx 2 0 100) 0 actionFixtureTree scoreMaterializedCandidate))
   (1 0 0 1 0))
!(set-param fitness fixtureFitnessTwo)
!(change-state! &act2 (evaluateCandidateBatchWith ((pending 0)) rep id (mkActionScoreContext 0 2) 1 actionFixtureTree scoreMaterializedCandidate))
!(assertEqual (getScore (candidateScore (List.head (batchEvaluated (get-state &act2))))) -2.0)
!(assertEqual (batchActualEvaluations (get-state &act2)) 1)
!(assertEqual (resetCandidateScoreCache) True)
!(assertEqual (cachedCandidateEvaluation fixtureContext (mkTree (mkNode A) ())) ())
!(assertEqual (batchSummary (fixtureBatch ((pending 0)) 1)) (1 0 1 0 0))

;; Deterministic cooperative-deadline test: the first scorer advances a fake
;; monotonic clock; the next candidate must remain pending without a call.
!(bind! &fixtureClock (new-state 0))
(= (fixtureNow) (get-state &fixtureClock))
(= (timedFixtureScore $tree $context)
   (let $_tick (change-state! &fixtureClock 1) (fixtureScore $tree $context)))
!(resetFixture)
!(change-state! &timedBatch
   (evaluateCandidateBatchUntil ((pending 0) (pending 2)) rep id timedContext -1
     fixtureMaterialize timedFixtureScore (mkCandidateDeadline fixtureNow 1)))
!(assertEqual (batchSummary (get-state &timedBatch)) (1 1 1 0 0))
!(assertEqual (get-state &fixtureCalls) 1)
!(assertEqual (batchPending (get-state &timedBatch)) ((pending 2)))
!(assertEqual (batchSummary
   (evaluateCandidateBatchUntil ((pending 2)) rep id timedContext -1
     fixtureMaterialize timedFixtureScore 0)) (0 1 0 0 0))
!(assertEqual (get-state &fixtureCalls) 1)
